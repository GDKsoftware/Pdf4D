// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Codec.Jpeg.Tests;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Common.Log,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Graphics.Image,
  Pdf4D.Codec.Jpeg;

type
  // The largest and the mean absolute difference per channel between a decoded image and the PNG that PDFBox wrote for it
  TImageDifference = record
    Largest: Integer;
    Mean: Double;
  end;

  [TestFixture]
  TJpegImageTests = class
  private
    FLines: TList<string>;
    FLog: TPdfLog;

    class function ReferenceFolder: string; static;
    class function ReadReference(const Name: string): TBytes; static;
    class function Join(const Parts: array of TBytes): TBytes; static;
    class function IndexOfMarker(const Data: TBytes; const MarkerCode: Word): Integer; static;
    class function Marker(const Value: Word): TBytes; static;
    class function Header(const MarkerCode: Word; const Payload: array of Byte): TBytes; static;
    class function Frame(const Height, Width: Word; const Components: array of Byte): TBytes; static;
    class function EmptyRefinementFile(const ScanCount: Integer): TBytes; static;
    class function Difference(const Image: TPDImageXObject; const PngPath: string): TImageDifference; static;
    class function IsDctImage(const Stream: TCosStream): Boolean; static;

    function CompareJpegImagesOf(const Entry, ReferenceRoot: string; const Misses: TList<string>): Integer;
    function Decode(const Data: TBytes; const ColorTransform: Integer = -1; const MaxPixels: Int64 = 100000000): TJpegImage;
    procedure AssertDecodeRaisesParseError(const Data: TBytes; const MaxPixels: Int64 = 100000000);
    procedure AssertImageMatches(const ImageName: string; const MaxLargest: Integer; const MaxMean: Double);
    procedure AssertSamplesEqual(const Expected, Actual: TBytes);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestBaselineGray;

    [Test]
    procedure TestBaselineRgb420;

    [Test]
    procedure TestBaselineRgb444;

    [Test]
    procedure TestProgressive;

    [Test]
    procedure TestRestartInterval;

    [Test]
    procedure TestAdobeCmyk;

    [Test]
    procedure TestYcckInverted;

    [Test]
    procedure TestCorpusJpegImagesMatch;

    [Test]
    procedure TestProgressiveEqualsBaselineOfTheSameCoefficients;

    [Test]
    procedure TestRestartIntervalEqualsPlainBaseline;

    [Test]
    procedure TestSamplesHaveTheSizeOfTheHeader;

    [Test]
    procedure TestColorTransformZeroKeepsTheLumaAndChromaSamples;

    [Test]
    procedure TestTruncatedJpegKeepsDecodedRows;

    [Test]
    procedure TestNotAJpegRaisesParseError;

    [Test]
    procedure TestHugeDimensionsRespectMaxPixels;

    [Test]
    procedure TestThinImageCannotMultiplyTheBlockBuffer;

    [Test]
    procedure TestInvalidFrameHeadersRaiseParseError;

    [Test]
    procedure TestUnknownComponentInScanRaisesParseError;

    [Test]
    procedure TestMissingHuffmanTableRaisesParseError;

    [Test]
    procedure TestMissingQuantizationTableRaisesParseError;

    [Test]
    procedure TestTwelveBitPrecisionRaisesParseError;

    [Test]
    procedure TestArithmeticCodingRaisesParseError;

    [Test]
    procedure TestMoreThanThousandScansRaisesParseError;

    [Test]
    procedure TestGarbageScanDataEndsWithParseErrorOrAnImage;

    [Test]
    procedure TestEmptyRefinementScansAreBoundedByAWorkBudget;

    [Test]
    procedure TestAFewRepeatedScansStayWithinTheWorkBudget;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.Math,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Names,
  Pdf4D.Graphics.Color,
  Pdf4D.Model.Document,
  Pdf4D.Model.Page,
  Pdf4D.Render.Bitmap,
  Pdf4D.Tests.Corpus,
  Pdf4D.Tests.Png;

const
  JpegCorpusFile = 'generated/render/jpeg.pdf';
  ImagesFolder = 'images';
  SelectionFile = 'selection.txt';
  // Without chroma subsampling the decoder is within a few levels of PDFBox. With it, jpg.js repeats the nearest chroma sample where
  // libjpeg interpolates, which differs most where the colour changes quickly (measured: 72 and 1.4 on average for the photo of the
  // PDFBox tests, 56 and 4.2 for the generated image with its colour ramps, 60 and 3.2 in the corpus).
  MaxLargestDifference = 4;
  MaxMeanDifference = 0.5;
  MaxLargestSubsampled = 80;
  MaxMeanSubsampled = 5.0;
  // A CMYK image with /Decode [1 0 ...] puts the dark colours where the conversion to RGB amplifies a difference (measured: 11 and 0.13)
  MaxLargestInvertedCmyk = 12;
  MinimumComparedCorpusImages = 11;
  MaxScans = 1000;
  Soi = $FFD8;
  Eoi = $FFD9;
  Sof0 = $FFC0;
  Sof2 = $FFC2;
  Sof9 = $FFC9;
  Dht = $FFC4;
  Dqt = $FFDB;
  Sos = $FFDA;
  TruncatedRowsKept = 64;
  GrayLevel = 128;

{ TJpegImageTests }

procedure TJpegImageTests.Setup;
begin
  FLines := TList<string>.Create;
  FLog := TPdfLog.Create(
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      if Level >= TPdfLogLevel.Warning then
      begin
        FLines.Add(Message);
      end;
    end);
end;

procedure TJpegImageTests.TearDown;
begin
  FLog.Free;
  FLines.Free;
end;

class function TJpegImageTests.ReferenceFolder: string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.GetDirectoryName(TCorpus.Folder), 'reference'), 'jpeg');
end;

class function TJpegImageTests.ReadReference(const Name: string): TBytes;
begin
  Result := TFile.ReadAllBytes(TPath.Combine(ReferenceFolder, Name));
end;

class function TJpegImageTests.Join(const Parts: array of TBytes): TBytes;
begin
  Result := nil;
  for var Part in Parts do
  begin
    Result := Result + Part;
  end;
end;

class function TJpegImageTests.IndexOfMarker(const Data: TBytes; const MarkerCode: Word): Integer;
begin
  for Result := 0 to Length(Data) - 2 do
  begin
    const IsMarker = ((Data[Result] = Hi(MarkerCode)) and (Data[Result + 1] = Lo(MarkerCode)));
    if IsMarker then
    begin
      Exit;
    end;
  end;
  raise EArgumentException.CreateFmt('Marker %x not found', [MarkerCode]);
end;

class function TJpegImageTests.Marker(const Value: Word): TBytes;
begin
  Result := [Hi(Value), Lo(Value)];
end;

class function TJpegImageTests.Header(const MarkerCode: Word; const Payload: array of Byte): TBytes;
begin
  const Size = Length(Payload) + 2;
  Result := [Hi(MarkerCode), Lo(MarkerCode), Hi(Size), Lo(Size)];
  for var Value in Payload do
  begin
    Result := Result + [Value];
  end;
end;

// A SOF0 header: 8 bit precision, then each component as id, sampling factors and quantization table
class function TJpegImageTests.Frame(const Height, Width: Word; const Components: array of Byte): TBytes;
begin
  var Payload: TBytes := [8, Hi(Height), Lo(Height), Hi(Width), Lo(Width), Length(Components) div 3];
  for var Value in Components do
  begin
    Payload := Payload + [Value];
  end;
  Result := Header(Sof0, Payload);
end;

class function TJpegImageTests.IsDctImage(const Stream: TCosStream): Boolean;
begin
  Result := False;
  for var FilterName in Stream.GetFilterNames do
  begin
    Result := (Result or FilterName.StartsWith('DCT'));
  end;
end;

class function TJpegImageTests.Difference(const Image: TPDImageXObject; const PngPath: string): TImageDifference;
begin
  var Actual: TPdfBitmap;
  Assert.IsTrue(Image.TryGetImage(MaxInt, Actual), 'The image should decode');
  const Expected = TPng.Read(PngPath);
  try
    Assert.AreEqual(Expected.Width, Actual.Width, 'width');
    Assert.AreEqual(Expected.Height, Actual.Height, 'height');
    Expected.FlattenOn(TPdfDeviceColor.White);
    Actual.FlattenOn(TPdfDeviceColor.White);
    var Total: Int64 := 0;
    Result.Largest := 0;
    for var Position := 0 to Length(Expected.Pixels) - 1 do
    begin
      const Delta = Abs(Integer(Expected.Pixels[Position]) - Integer(Actual.Pixels[Position]));
      Result.Largest := Max(Result.Largest, Delta);
      Inc(Total, Delta);
    end;
    Result.Mean := Total / Max(Length(Expected.Pixels), 1);
  finally
    Expected.Free;
    Actual.Free;
  end;
end;

function TJpegImageTests.Decode(const Data: TBytes; const ColorTransform: Integer; const MaxPixels: Int64): TJpegImage;
begin
  Result := TJpegImage.Decode(Data, TJpegDecodeOptions.ForPdf(ColorTransform, MaxPixels), FLog);
end;

procedure TJpegImageTests.AssertDecodeRaisesParseError(const Data: TBytes; const MaxPixels: Int64);
begin
  Assert.WillRaise(
    procedure
    begin
      Decode(Data, -1, MaxPixels).Free;
    end,
    EPdfParseException);
end;

procedure TJpegImageTests.AssertSamplesEqual(const Expected, Actual: TBytes);
begin
  Assert.AreEqual<Integer>(Length(Expected), Length(Actual), 'sample count');
  for var Index := 0 to Length(Expected) - 1 do
  begin
    if Expected[Index] <> Actual[Index] then
    begin
      Assert.Fail(Format('Sample %d is %d, expected %d', [Index, Actual[Index], Expected[Index]]));
    end;
  end;
end;

// The image of the JPEG test PDF with this resource name is the image that PDFBox made, within the tolerance
procedure TJpegImageTests.AssertImageMatches(const ImageName: string; const MaxLargest: Integer; const MaxMean: Double);
begin
  const ImagesRoot = TPath.Combine(TPath.Combine(TPath.GetDirectoryName(TCorpus.Folder), 'reference'), ImagesFolder);
  const Document = TPDDocument.Load(TFileStream.Create(TCorpus.PdfPath(JpegCorpusFile), fmOpenRead or fmShareDenyWrite), True, TPdfLoadOptions.Default);
  try
    const Resources = Document.Pages.Get(0).Resources;
    var XObjects: TCosDictionary;
    Assert.IsTrue(Resources.CosObject.TryGetCosDictionary(TCosNames.XObject, XObjects), 'XObject resources');

    var ImageIndex := 0;
    for var Name in XObjects.Keys do
    begin
      var Stream: TCosStream;
      if (not Resources.IsImageXObject(Name)) or (not Resources.TryGetXObject(Name, Stream)) then
      begin
        Continue;
      end;
      Inc(ImageIndex);
      if Name <> ImageName then
      begin
        Continue;
      end;

      const PngName = Format('p1-%d.png', [ImageIndex - 1]);
      const PngPath = TPath.Combine(TPath.Combine(ImagesRoot, JpegCorpusFile.Replace('/', '__')), PngName);
      const Image = TPDImageXObject.Create(Stream, Resources);
      try
        const Measured = Difference(Image, PngPath);
        const IsClose = ((Measured.Largest <= MaxLargest) and (Measured.Mean <= MaxMean));
        Assert.IsTrue(IsClose, Format('%s: largest difference %d, mean difference %.3f', [ImageName, Measured.Largest, Measured.Mean]));
      finally
        Image.Free;
      end;
      Exit;
    end;
    Assert.Fail(Format('Image %s is not in the test PDF', [ImageName]));
  finally
    Document.Free;
  end;
end;

procedure TJpegImageTests.TestBaselineGray;
begin
  AssertImageMatches('JpegGray', MaxLargestDifference, MaxMeanDifference);
  AssertImageMatches('PdfboxGray', MaxLargestDifference, MaxMeanDifference);
end;

procedure TJpegImageTests.TestBaselineRgb420;
begin
  AssertImageMatches('JpegRgb420', MaxLargestSubsampled, MaxMeanSubsampled);
  AssertImageMatches('PdfboxRgb', MaxLargestSubsampled, MaxMeanSubsampled);
end;

procedure TJpegImageTests.TestBaselineRgb444;
begin
  AssertImageMatches('JpegRgb444', MaxLargestDifference, MaxMeanDifference);
end;

procedure TJpegImageTests.TestProgressive;
begin
  AssertImageMatches('JpegProgressive', MaxLargestSubsampled, MaxMeanSubsampled);
end;

procedure TJpegImageTests.TestRestartInterval;
begin
  AssertImageMatches('JpegRestart', MaxLargestSubsampled, MaxMeanSubsampled);
end;

// jpegcmyk.jpg of the PDFBox tests is YCCK (Adobe transform 2); cmyk.jpg has Adobe transform 0
procedure TJpegImageTests.TestAdobeCmyk;
begin
  AssertImageMatches('PdfboxYcck', MaxLargestDifference, MaxMeanDifference);
  AssertImageMatches('JpegCmyk', MaxLargestDifference, MaxMeanDifference);
end;

procedure TJpegImageTests.TestYcckInverted;
begin
  AssertImageMatches('PdfboxYcckInverted', MaxLargestInvertedCmyk, MaxMeanDifference);
  AssertImageMatches('JpegCmykInverted', MaxLargestDifference, MaxMeanDifference);
end;

// Every image with a DCTDecode filter in the files of the image selection is the image that PDFBox made
procedure TJpegImageTests.TestCorpusJpegImagesMatch;
begin
  const ReferenceRoot = TPath.Combine(TPath.Combine(TPath.GetDirectoryName(TCorpus.Folder), 'reference'), ImagesFolder);
  const Selection = TFile.ReadAllLines(TPath.Combine(ReferenceRoot, SelectionFile));
  const Misses = TList<string>.Create;
  try
    var Compared := 0;
    for var Entry in Selection do
    begin
      const IsEntry = ((Entry.Trim <> '') and (not Entry.StartsWith('#')));
      if IsEntry then
      begin
        Inc(Compared, CompareJpegImagesOf(Entry.Trim, ReferenceRoot, Misses));
      end;
    end;

    Assert.AreEqual<Integer>(0, Misses.Count, string.Join(sLineBreak, Misses.ToArray));
    Assert.IsTrue(Compared >= MinimumComparedCorpusImages, Format('Only %d JPEG images were compared', [Compared]));
  finally
    Misses.Free;
  end;
end;

// The number of DCT images of the file that were compared; the ones that are not close are added to Misses
function TJpegImageTests.CompareJpegImagesOf(const Entry, ReferenceRoot: string; const Misses: TList<string>): Integer;
begin
  Result := 0;
  const Document = TPDDocument.Load(TFileStream.Create(TCorpus.PdfPath(Entry), fmOpenRead or fmShareDenyWrite), True, TPdfLoadOptions.Default);
  try
    for var PageIndex := 0 to Document.Pages.Count - 1 do
    begin
      const Resources = Document.Pages.Get(PageIndex).Resources;
      var XObjects: TCosDictionary;
      if (not Assigned(Resources.CosObject)) or (not Resources.CosObject.TryGetCosDictionary(TCosNames.XObject, XObjects)) then
      begin
        Continue;
      end;

      var ImageIndex := 0;
      for var Name in XObjects.Keys do
      begin
        var Stream: TCosStream;
        if (not Resources.IsImageXObject(Name)) or (not Resources.TryGetXObject(Name, Stream)) then
        begin
          Continue;
        end;
        const Index = ImageIndex;
        Inc(ImageIndex);

        const PngName = Format('p%d-%d.png', [PageIndex + 1, Index]);
        const PngPath = TPath.Combine(TPath.Combine(ReferenceRoot, Entry.Replace('/', '__')), PngName);
        if (not IsDctImage(Stream)) or (not TFile.Exists(PngPath)) then
        begin
          Continue;
        end;

        const Image = TPDImageXObject.Create(Stream, Resources);
        try
          const Measured = Difference(Image, PngPath);
          const IsClose = ((Measured.Largest <= MaxLargestSubsampled) and (Measured.Mean <= MaxMeanSubsampled));
          if not IsClose then
          begin
            Misses.Add(Format('%s page %d image %s: largest difference %d, mean difference %.3f', [Entry, PageIndex + 1, Name, Measured.Largest, Measured.Mean]));
          end;
          Inc(Result);
        finally
          Image.Free;
        end;
      end;
    end;
  finally
    Document.Free;
  end;
end;

// The progressive file holds the same coefficients as the baseline file, so the samples are the same
procedure TJpegImageTests.TestProgressiveEqualsBaselineOfTheSameCoefficients;
begin
  const Baseline = Decode(ReadReference('rgb420.jpg'));
  try
    const Progressive = Decode(ReadReference('progressive.jpg'));
    try
      AssertSamplesEqual(Baseline.Samples, Progressive.Samples);
    finally
      Progressive.Free;
    end;
  finally
    Baseline.Free;
  end;
end;

procedure TJpegImageTests.TestRestartIntervalEqualsPlainBaseline;
begin
  const Baseline = Decode(ReadReference('rgb420.jpg'));
  try
    const Restart = Decode(ReadReference('restart.jpg'));
    try
      AssertSamplesEqual(Baseline.Samples, Restart.Samples);
    finally
      Restart.Free;
    end;
  finally
    Baseline.Free;
  end;
end;

procedure TJpegImageTests.TestSamplesHaveTheSizeOfTheHeader;
begin
  const Gray = Decode(ReadReference('gray.jpg'));
  try
    Assert.AreEqual(61, Gray.Width);
    Assert.AreEqual(45, Gray.Height);
    Assert.AreEqual(1, Gray.Components);
    Assert.AreEqual<Integer>(61 * 45, Length(Gray.Samples));
  finally
    Gray.Free;
  end;

  const Cmyk = Decode(ReadReference('cmyk.jpg'));
  try
    Assert.AreEqual(4, Cmyk.Components);
    Assert.AreEqual<Integer>(61 * 45 * 4, Length(Cmyk.Samples));
  finally
    Cmyk.Free;
  end;
end;

// Without an Adobe segment and with /ColorTransform 0 the three components are not converted: a gray area keeps its chroma at 128
procedure TJpegImageTests.TestColorTransformZeroKeepsTheLumaAndChromaSamples;
begin
  const Data = ReadReference('rgb444.jpg');
  const Converted = Decode(Data);
  try
    const Raw = Decode(Data, 0);
    try
      Assert.AreEqual<Integer>(Length(Converted.Samples), Length(Raw.Samples));
      var IsEqual := True;
      for var Index := 0 to Length(Raw.Samples) - 1 do
      begin
        IsEqual := (IsEqual and (Raw.Samples[Index] = Converted.Samples[Index]));
      end;
      Assert.IsFalse(IsEqual, 'ColorTransform 0 should leave the samples as Y, Cb and Cr');
    finally
      Raw.Free;
    end;
  finally
    Converted.Free;
  end;
end;

procedure TJpegImageTests.TestTruncatedJpegKeepsDecodedRows;
begin
  const Data = ReadReference('pdfbox-jpeg.jpg');
  const Original = Decode(Data);
  try
    FLines.Clear;
    const Half = Copy(Data, 0, Length(Data) div 2);
    const Truncated = Decode(Half);
    try
      Assert.AreEqual(Original.Height, Truncated.Height);
      Assert.AreEqual<Integer>(Length(Original.Samples), Length(Truncated.Samples));

      const RowBytes = Original.Width * Original.Components;
      for var Position := 0 to (TruncatedRowsKept * RowBytes) - 1 do
      begin
        if Original.Samples[Position] <> Truncated.Samples[Position] then
        begin
          Assert.Fail(Format('Sample %d of the top rows differs', [Position]));
        end;
      end;

      const LastRowStart = (Original.Height - 1) * RowBytes;
      for var Position := LastRowStart to LastRowStart + RowBytes - 1 do
      begin
        Assert.IsTrue(Abs(Integer(Truncated.Samples[Position]) - GrayLevel) <= 1, 'The rows that were not decoded are gray');
      end;
      Assert.AreEqual<Integer>(1, FLines.Count, 'One warning for the truncated data');
    finally
      Truncated.Free;
    end;
  finally
    Original.Free;
  end;
end;

procedure TJpegImageTests.TestNotAJpegRaisesParseError;
begin
  AssertDecodeRaisesParseError(nil);
  AssertDecodeRaisesParseError([$FF]);
  AssertDecodeRaisesParseError(TEncoding.ASCII.GetBytes('GIF89a not a jpeg'));
  AssertDecodeRaisesParseError([$89, $50, $4E, $47, $0D, $0A, $1A, $0A]);
  AssertDecodeRaisesParseError(Header(Soi, []));
  AssertDecodeRaisesParseError([Hi(Soi), Lo(Soi), Hi(Eoi), Lo(Eoi)]);
end;

procedure TJpegImageTests.TestHugeDimensionsRespectMaxPixels;
begin
  const Components: array of Byte = [1, $22, 0, 2, $11, 0, 3, $11, 0];
  const Data = Join([Marker(Soi), Frame(65535, 65535, Components), Marker(Eoi)]);

  AssertDecodeRaisesParseError(Data, 1000000);
  AssertDecodeRaisesParseError(Data, High(Int64));
  AssertDecodeRaisesParseError(Data, 0);
end;

// 1 x N pixels with 4:2:0 sampling is a small area but a block buffer of 40 samples per pixel
procedure TJpegImageTests.TestThinImageCannotMultiplyTheBlockBuffer;
begin
  const Components: array of Byte = [1, $22, 0, 2, $11, 0, 3, $11, 0];
  const Data = Join([Marker(Soi), Frame(60000, 1, Components), Marker(Eoi)]);

  AssertDecodeRaisesParseError(Data, 60000);
end;

procedure TJpegImageTests.TestInvalidFrameHeadersRaiseParseError;
begin
  const Start: TBytes = [Hi(Soi), Lo(Soi)];
  const Ending: TBytes = [Hi(Eoi), Lo(Eoi)];
  const ZeroSampling: array of Byte = [1, $00, 0];
  const FiveComponents: array of Byte = [1, $11, 0, 2, $11, 0, 3, $11, 0, 4, $11, 0, 5, $11, 0];
  const TwoComponents: array of Byte = [1, $11, 0, 2, $11, 0];
  const HugeSampling: array of Byte = [1, $F1, 0];
  const NoComponents: array of Byte = [];
  const OneComponent: array of Byte = [1, $11, 0];

  AssertDecodeRaisesParseError(Join([Start, Frame(8, 8, ZeroSampling), Ending]));
  AssertDecodeRaisesParseError(Join([Start, Frame(8, 8, FiveComponents), Ending]));
  AssertDecodeRaisesParseError(Join([Start, Frame(8, 8, TwoComponents), Ending]));
  AssertDecodeRaisesParseError(Join([Start, Frame(8, 8, HugeSampling), Ending]));
  AssertDecodeRaisesParseError(Join([Start, Frame(8, 8, NoComponents), Ending]));
  AssertDecodeRaisesParseError(Join([Start, Frame(0, 8, OneComponent), Ending]));
  AssertDecodeRaisesParseError(Join([Start, Frame(8, 0, OneComponent), Ending]));
  AssertDecodeRaisesParseError(Join([Start, Frame(8, 8, OneComponent), Frame(8, 8, OneComponent), Ending]));
end;

procedure TJpegImageTests.TestUnknownComponentInScanRaisesParseError;
begin
  const Data = ReadReference('gray.jpg');
  const ScanStart = IndexOfMarker(Data, Sos);
  var Changed := Copy(Data, 0, Length(Data));
  Changed[ScanStart + 5] := 9;

  AssertDecodeRaisesParseError(Changed);
end;

procedure TJpegImageTests.TestMissingHuffmanTableRaisesParseError;
begin
  const Data = ReadReference('gray.jpg');
  const ScanStart = IndexOfMarker(Data, Sos);
  var Changed := Copy(Data, 0, Length(Data));
  Changed[ScanStart + 6] := $FF;

  AssertDecodeRaisesParseError(Changed);
end;

procedure TJpegImageTests.TestMissingQuantizationTableRaisesParseError;
begin
  const Data = ReadReference('gray.jpg');
  const FrameStart = IndexOfMarker(Data, Sof0);
  var Changed := Copy(Data, 0, Length(Data));
  Changed[FrameStart + 12] := 7;

  AssertDecodeRaisesParseError(Changed);
end;

procedure TJpegImageTests.TestTwelveBitPrecisionRaisesParseError;
begin
  const Data = ReadReference('gray.jpg');
  const FrameStart = IndexOfMarker(Data, Sof0);
  var Changed := Copy(Data, 0, Length(Data));
  Changed[FrameStart + 4] := 12;

  AssertDecodeRaisesParseError(Changed);
end;

procedure TJpegImageTests.TestArithmeticCodingRaisesParseError;
begin
  const Data = ReadReference('gray.jpg');
  const FrameStart = IndexOfMarker(Data, Sof0);
  var Changed := Copy(Data, 0, Length(Data));
  Changed[FrameStart + 1] := Lo(Sof9);

  AssertDecodeRaisesParseError(Changed);
end;

// Over MaxScans scans is an error; a file that repeats a whole scan that often also runs into the work budget first, and the
// decoder raises its parse error either way
procedure TJpegImageTests.TestMoreThanThousandScansRaisesParseError;
begin
  const Data = ReadReference('gray.jpg');
  const ScanStart = IndexOfMarker(Data, Sos);
  const EndStart = Length(Data) - 2;
  const Scan = Copy(Data, ScanStart, EndStart - ScanStart);

  var Repeated := Copy(Data, 0, ScanStart);
  for var Count := 1 to MaxScans + 1 do
  begin
    Repeated := Repeated + Scan;
  end;
  Repeated := Repeated + [Hi(Eoi), Lo(Eoi)];

  AssertDecodeRaisesParseError(Repeated);
end;

// A file whose header is a 1024 x 1024 progressive gray image and that has ScanCount scans. Each scan refines the AC coefficients
// of every block and takes two bytes of data: one code for an end-of-band run over all 16384 blocks. The blocks are all empty, and
// without a bound on the work each scan still walks over every block.
class function TJpegImageTests.EmptyRefinementFile(const ScanCount: Integer): TBytes;
begin
  const FrameSide = 1024;
  var QuantizationPayload: TBytes := [0];
  for var Index := 1 to 64 do
  begin
    QuantizationPayload := QuantizationPayload + [1];
  end;
  // One code of one bit for symbol 0 in the DC table and for the end-of-band run of 2^14 blocks (symbol $E0) in the AC table
  const DcTable: TBytes = [$00, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
  const AcTable: TBytes = [$10, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, $E0];
  const RunData: TBytes = [0, 0];
  const Scan = Join([Header(Sos, [1, 1, $00, 1, 63, $10]), RunData]);

  Result := Join([Marker(Soi), Header(Dqt, QuantizationPayload), Header(Sof2, [8, Hi(FrameSide), Lo(FrameSide), Hi(FrameSide), Lo(FrameSide), 1, 1, $11, 0]),
                  Header(Dht, DcTable), Header(Dht, AcTable)]);
  for var Count := 1 to ScanCount do
  begin
    Result := Result + Scan;
  end;
  Result := Result + Marker(Eoi);
end;

procedure TJpegImageTests.TestEmptyRefinementScansAreBoundedByAWorkBudget;
begin
  AssertDecodeRaisesParseError(EmptyRefinementFile(MaxScans));
end;

procedure TJpegImageTests.TestAFewRepeatedScansStayWithinTheWorkBudget;
begin
  const FewScans = 5;

  Decode(EmptyRefinementFile(FewScans)).Free;
end;

// Random scan data behind a valid header: the decoder gives an image or EPdfParseException, quickly and without reading outside
procedure TJpegImageTests.TestGarbageScanDataEndsWithParseErrorOrAnImage;
begin
  const Data = ReadReference('rgb420.jpg');
  const ScanStart = IndexOfMarker(Data, Sos);
  const HeaderEnd = ScanStart + 14;
  const Prefix = Copy(Data, 0, HeaderEnd);

  RandSeed := 20260;
  for var Attempt := 1 to 40 do
  begin
    var Garbage: TBytes;
    SetLength(Garbage, 400 + (Attempt * 37));
    for var Index := 0 to High(Garbage) do
    begin
      Garbage[Index] := Byte(Random(256));
    end;

    try
      Decode(Prefix + Garbage).Free;
    except
      on EPdfParseException do
      begin
        Continue;
      end;
    end;
  end;
  Assert.Pass;
end;

end.
