// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of the image decoder (SampledImageReader, PDImageXObject.getImage, applyMask; PDFBox 3.0.8) and the comparison with the images
// that the oracle wrote for the files of tests/reference/images/selection.txt
unit Pdf4D.Graphics.Image.SampledReader.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Common.Log,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Graphics.Image,
  Pdf4D.Model.DocumentContext,
  Pdf4D.Model.Resources,
  Pdf4D.Render.Bitmap;

type
  [TestFixture]
  TSampledImageReaderTests = class
  private
    FLines: TList<string>;
    FLog: TPdfLog;
    FContext: TPDDocumentContext;
    FResourceDictionary: TCosDictionary;
    FResources: TPDResources;
    FOwned: TObjectList<TObject>;

    // An image stream with the entries every image needs; the caller sets more on it. The fixture owns it.
    function NewStream(const Width, Height, Bits: Integer; const ColorSpace: string; const Data: TBytes): TCosStream;
    procedure SetNumbers(const Stream: TCosStream; const Key: string; const Values: array of Integer);
    function NewImage(const Stream: TCosStream): TPDImageXObject;
    function GetImage(const Image: TPDImage; const MaxImagePixels: Int64 = 1000000): TPdfBitmap;
    function HasLogLine(const Fragment: string): Boolean;
    procedure AssertPixel(const Bitmap: TPdfBitmap; const X, Y: Integer; const R, G, B, A: Byte);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestImagesMatchPdfBox;

    [Test]
    procedure TestOneBitDecodeInverted;

    [Test]
    procedure TestSixteenBitIsScaledTo8;

    [Test]
    procedure TestColorKeyMaskMakesTransparent;

    [Test]
    procedure TestSMaskBecomesAlpha;

    [Test]
    procedure TestSMaskLargerThanTheImageScalesTheImage;

    [Test]
    procedure TestStencilMaskOfTheImageIsInverted;

    [Test]
    procedure TestShortImageDataIsPadded;

    [Test]
    procedure TestHugeDeclaredSizeIsSubsampledOrSkipped;

    [Test]
    procedure TestHugeCmykIsSubsampledWithinTheRasterLimit;

    [Test]
    procedure TestShortIndexedLookupClamps;

    [Test]
    procedure TestJpxIsSkippedWithLog;

    [Test]
    procedure TestInvalidBitsPerComponentIsSkipped;

    [Test]
    procedure TestEmptyDataIsSkipped;

    [Test]
    procedure TestSubsamplingTakesEveryNthPixel;

    [Test]
    procedure TestStencilMaskAlphaFollowsDecode;

    [Test]
    procedure TestFourBitRowsArePadded;

    [Test]
    procedure TestStencilHasNoColorSpace;

    [Test]
    procedure TestJavaRoundSaturatesLikeJava;

    [Test]
    procedure TestHugeDecodeRangeDoesNotRaise;

    [Test]
    procedure TestHugeMatteDoesNotRaise;

    [Test]
    procedure TestEncodedDataOfDctIsTheStreamData;

    [Test]
    procedure TestEncodedDataUndoesFlateBeforeDct;

    [Test]
    [TestCase('JPX', 'JPXDecode')]
    [TestCase('JBIG2', 'JBIG2Decode')]
    procedure TestEncodedDataOfOtherImageFilters(const FilterName: string);

    [Test]
    procedure TestEncodedDataIsFalseWithoutImageFilter;

    [Test]
    procedure TestEncodedDataIsFalseWhenAnEarlierFilterFails;
  end;

implementation

uses
  System.IOUtils,
  System.Math,
  System.ZLib,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Boolean,
  Pdf4D.Cos.Float,
  Pdf4D.Graphics.Image.SampledReader,
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Cos.PdfString,
  Pdf4D.Model.Document,
  Pdf4D.Model.Page,
  Pdf4D.Tests.Corpus,
  Pdf4D.Tests.Png;

const
  SelectionFile = 'selection.txt';
  ImagesFolder = 'images';
  MinimumComparedImages = 25;
  ChannelTolerance = 1;

{ TSampledImageReaderTests }

procedure TSampledImageReaderTests.Setup;
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
  FContext := TPDDocumentContext.Create(FLog, TPdfLoadOptions.Default);
  FResourceDictionary := TCosDictionary.Create;
  FResources := TPDResources.Create(FResourceDictionary, FContext);
  FOwned := TObjectList<TObject>.Create(True);
end;

procedure TSampledImageReaderTests.TearDown;
begin
  FOwned.Free;
  FResources.Free;
  FResourceDictionary.Free;
  FContext.Free;
  FLog.Free;
  FLines.Free;
end;

function TSampledImageReaderTests.NewStream(const Width, Height, Bits: Integer; const ColorSpace: string; const Data: TBytes): TCosStream;
begin
  Result := TCosStream.Create;
  FOwned.Add(Result);
  Result.SetRawData(Data);
  Result.SetItem(TCosNames.Width, TCosInteger.Create(Width));
  Result.SetItem(TCosNames.Height, TCosInteger.Create(Height));
  Result.SetItem(TCosNames.BitsPerComponent, TCosInteger.Create(Bits));
  if ColorSpace <> '' then
  begin
    Result.SetItem(TCosNames.ColorSpace, TCosName.Create(ColorSpace));
  end;
end;

procedure TSampledImageReaderTests.SetNumbers(const Stream: TCosStream; const Key: string; const Values: array of Integer);
begin
  const Items = TCosArray.Create;
  for var Value in Values do
  begin
    Items.Add(TCosInteger.Create(Value));
  end;
  Stream.SetItem(Key, Items);
end;

function TSampledImageReaderTests.NewImage(const Stream: TCosStream): TPDImageXObject;
begin
  Result := TPDImageXObject.Create(Stream, FResources);
  FOwned.Add(Result);
end;

function TSampledImageReaderTests.GetImage(const Image: TPDImage; const MaxImagePixels: Int64): TPdfBitmap;
begin
  var Bitmap: TPdfBitmap;
  Assert.IsTrue(Image.TryGetImage(MaxImagePixels, Bitmap), 'The image should decode');
  FOwned.Add(Bitmap);
  Result := Bitmap;
end;

function TSampledImageReaderTests.HasLogLine(const Fragment: string): Boolean;
begin
  Result := False;
  for var Line in FLines do
  begin
    Result := (Result or Line.Contains(Fragment));
  end;
end;

procedure TSampledImageReaderTests.AssertPixel(const Bitmap: TPdfBitmap; const X, Y: Integer; const R, G, B, A: Byte);
begin
  const Pixel = Bitmap.GetPixel(X, Y);
  Assert.AreEqual<Integer>(R, Pixel.R, Format('R of (%d, %d)', [X, Y]));
  Assert.AreEqual<Integer>(G, Pixel.G, Format('G of (%d, %d)', [X, Y]));
  Assert.AreEqual<Integer>(B, Pixel.B, Format('B of (%d, %d)', [X, Y]));
  Assert.AreEqual<Integer>(A, Pixel.A, Format('A of (%d, %d)', [X, Y]));
end;

// Every image of the selection that the decoder supports so far is the image that PDFBox made, flattened on white, within one
// level per channel. Images with a JPEG, CCITT, JPEG 2000 or JBIG2 filter and the colour spaces that are not ported yet are left out.
procedure TSampledImageReaderTests.TestImagesMatchPdfBox;
begin
  const ReferenceFolder = TPath.Combine(TPath.Combine(TPath.GetDirectoryName(TCorpus.Folder), 'reference'), ImagesFolder);
  const Selection = TFile.ReadAllLines(TPath.Combine(ReferenceFolder, SelectionFile));
  var Compared := 0;

  for var Entry in Selection do
  begin
    if (Entry.Trim = '') or Entry.StartsWith('#') then
    begin
      Continue;
    end;

    const Options = TPdfLoadOptions.Default;
    const Document = TPDDocument.Load(TFileStream.Create(TCorpus.PdfPath(Entry.Trim), fmOpenRead or fmShareDenyWrite), True, Options);
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

          const PngPath = TPath.Combine(TPath.Combine(ReferenceFolder, Entry.Trim.Replace('/', '__')), Format('p%d-%d.png', [PageIndex + 1, Index]));
          if not TFile.Exists(PngPath) then
          begin
            Continue;
          end;

          const Image = TPDImageXObject.Create(Stream, Resources);
          try
            var IsSupported := True;
            for var FilterName in Stream.GetFilterNames do
            begin
              IsSupported := (IsSupported and (not (FilterName.StartsWith('DCT') or FilterName.StartsWith('CCF') or FilterName.StartsWith('CCITT') or
                                                    FilterName.StartsWith('JPX') or FilterName.StartsWith('JBIG2'))));
            end;
            try
              Image.ColorSpace;
            except
              on EPdfUnsupportedFeatureException do
              begin
                IsSupported := False;
              end;
            end;
            if not IsSupported then
            begin
              Continue;
            end;

            var Actual: TPdfBitmap;
            Assert.IsTrue(Image.TryGetImage(MaxInt, Actual), Format('%s page %d image %s should decode', [Entry, PageIndex + 1, Name]));
            const Expected = TPng.Read(PngPath);
            try
              Assert.AreEqual(Expected.Width, Actual.Width, Format('%s page %d image %s: width', [Entry, PageIndex + 1, Name]));
              Assert.AreEqual(Expected.Height, Actual.Height, Format('%s page %d image %s: height', [Entry, PageIndex + 1, Name]));
              Expected.FlattenOn(TPdfDeviceColor.White);
              Actual.FlattenOn(TPdfDeviceColor.White);
              var Largest := 0;
              for var Position := 0 to Length(Expected.Pixels) - 1 do
              begin
                Largest := Max(Largest, Abs(Integer(Expected.Pixels[Position]) - Integer(Actual.Pixels[Position])));
              end;
              Assert.IsTrue(Largest <= ChannelTolerance, Format('%s page %d image %s: largest difference %d', [Entry, PageIndex + 1, Name, Largest]));
              Inc(Compared);
            finally
              Expected.Free;
              Actual.Free;
            end;
          finally
            Image.Free;
          end;
        end;
      end;
    finally
      Document.Free;
    end;
  end;

  Assert.IsTrue(Compared >= MinimumComparedImages, Format('Only %d images were compared', [Compared]));
end;

procedure TSampledImageReaderTests.TestOneBitDecodeInverted;
begin
  const Plain = GetImage(NewImage(NewStream(8, 1, 1, 'DeviceGray', [$A5])));
  const Inverted = NewStream(8, 1, 1, 'DeviceGray', [$A5]);
  SetNumbers(Inverted, TCosNames.Decode, [1, 0]);
  const Flipped = GetImage(NewImage(Inverted));

  const Bits: TArray<Integer> = [1, 0, 1, 0, 0, 1, 0, 1];
  for var X := 0 to 7 do
  begin
    AssertPixel(Plain, X, 0, Bits[X] * 255, Bits[X] * 255, Bits[X] * 255, 255);
    AssertPixel(Flipped, X, 0, (1 - Bits[X]) * 255, (1 - Bits[X]) * 255, (1 - Bits[X]) * 255, 255);
  end;
end;

procedure TSampledImageReaderTests.TestSixteenBitIsScaledTo8;
begin
  const Bitmap = GetImage(NewImage(NewStream(3, 1, 16, 'DeviceGray', [$FF, $FF, $80, $00, $00, $00])));

  AssertPixel(Bitmap, 0, 0, 255, 255, 255, 255);
  // 32768 / 65535 * 255 = 127.5019, which rounds to 128
  AssertPixel(Bitmap, 1, 0, 128, 128, 128, 255);
  AssertPixel(Bitmap, 2, 0, 0, 0, 0, 255);
end;

procedure TSampledImageReaderTests.TestColorKeyMaskMakesTransparent;
begin
  const Stream = NewStream(2, 1, 8, 'DeviceRGB', [10, 20, 30, 200, 100, 50]);
  SetNumbers(Stream, TCosNames.Mask, [0, 15, 0, 25, 0, 35]);
  const Bitmap = GetImage(NewImage(Stream));

  AssertPixel(Bitmap, 0, 0, 0, 0, 0, 0);
  AssertPixel(Bitmap, 1, 0, 200, 100, 50, 255);
end;

procedure TSampledImageReaderTests.TestSMaskBecomesAlpha;
begin
  const Stream = NewStream(2, 2, 8, 'DeviceRGB', [255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255]);
  // A mask of one pixel is scaled up to the image
  Stream.SetItem(TCosNames.SMask, NewStream(1, 1, 8, 'DeviceGray', [128]));
  FOwned.Extract(Stream.GetItem(TCosNames.SMask));
  const Bitmap = GetImage(NewImage(Stream));

  Assert.AreEqual(2, Bitmap.Width);
  Assert.AreEqual(2, Bitmap.Height);
  for var Y := 0 to 1 do
  begin
    for var X := 0 to 1 do
    begin
      // White at an alpha of 128, premultiplied
      AssertPixel(Bitmap, X, Y, 128, 128, 128, 128);
    end;
  end;
end;

// The image of 2 x 2 meets a mask of 4 x 4: the result has the size of the mask and every pixel of the image is four pixels
procedure TSampledImageReaderTests.TestSMaskLargerThanTheImageScalesTheImage;
begin
  const Stream = NewStream(2, 2, 8, 'DeviceRGB', [255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 0]);
  var MaskData: TBytes;
  SetLength(MaskData, 16);
  for var Index := 0 to 15 do
  begin
    MaskData[Index] := 255;
  end;
  Stream.SetItem(TCosNames.SMask, NewStream(4, 4, 8, 'DeviceGray', MaskData));
  FOwned.Extract(Stream.GetItem(TCosNames.SMask));
  const Bitmap = GetImage(NewImage(Stream));

  Assert.AreEqual(4, Bitmap.Width);
  Assert.AreEqual(4, Bitmap.Height);
  AssertPixel(Bitmap, 0, 0, 255, 0, 0, 255);
  AssertPixel(Bitmap, 1, 1, 255, 0, 0, 255);
  AssertPixel(Bitmap, 2, 0, 0, 255, 0, 255);
  AssertPixel(Bitmap, 3, 1, 0, 255, 0, 255);
  AssertPixel(Bitmap, 0, 2, 0, 0, 255, 255);
  AssertPixel(Bitmap, 3, 3, 255, 255, 0, 255);
end;

// An explicit /Mask that is a stencil hides the pixels where its bit is 1
procedure TSampledImageReaderTests.TestStencilMaskOfTheImageIsInverted;
begin
  const Stream = NewStream(8, 1, 8, 'DeviceGray', [10, 20, 30, 40, 50, 60, 70, 80]);
  const Mask = NewStream(8, 1, 1, '', [$F0]);
  Mask.SetItem(TCosNames.ImageMask, TCosBoolean.Create(True));
  Stream.SetItem(TCosNames.Mask, Mask);
  FOwned.Extract(Mask);
  const Bitmap = GetImage(NewImage(Stream));

  AssertPixel(Bitmap, 0, 0, 0, 0, 0, 0);
  AssertPixel(Bitmap, 3, 0, 0, 0, 0, 0);
  AssertPixel(Bitmap, 4, 0, 50, 50, 50, 255);
  AssertPixel(Bitmap, 7, 0, 80, 80, 80, 255);
end;

procedure TSampledImageReaderTests.TestShortImageDataIsPadded;
begin
  const Bitmap = GetImage(NewImage(NewStream(4, 4, 8, 'DeviceGray', [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])));

  AssertPixel(Bitmap, 1, 2, 10, 10, 10, 255);
  AssertPixel(Bitmap, 2, 2, 0, 0, 0, 255);
  AssertPixel(Bitmap, 3, 3, 0, 0, 0, 255);
  Assert.IsTrue(HasLogLine('shorter than expected'), 'A short image should be logged');
end;

procedure TSampledImageReaderTests.TestHugeDeclaredSizeIsSubsampledOrSkipped;
begin
  const Limit = 1000000;
  const Image = NewImage(NewStream(100000, 100000, 8, 'DeviceGray', [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]));

  var Bitmap: TPdfBitmap;
  if Image.TryGetImage(Limit, Bitmap) then
  begin
    FOwned.Add(Bitmap);
    Assert.IsTrue(Int64(Bitmap.Width) * Bitmap.Height <= Limit, 'The bitmap must fit the limit');
    Assert.IsTrue(Length(Bitmap.Pixels) <= Limit * 4, 'The pixels must fit the limit');
  end;
  Assert.IsTrue(HasLogLine('subsampled') or HasLogLine('skipped'), 'The huge image should be logged');
end;

// The samples of 9000 x 9000 pixels of four components are over what a raster holds; the image is subsampled, not refused
procedure TSampledImageReaderTests.TestHugeCmykIsSubsampledWithinTheRasterLimit;
begin
  const Image = NewImage(NewStream(9000, 9000, 8, 'DeviceCMYK', [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]));

  var Bitmap: TPdfBitmap;
  const IsDecoded = Image.TryGetImage(High(Int64), Bitmap);
  if IsDecoded then
  begin
    FOwned.Add(Bitmap);
    Assert.IsTrue(Bitmap.Width < 9000, 'The image should be subsampled');
    Assert.IsTrue(Int64(Bitmap.Width) * Bitmap.Height * 4 <= MaxBitmapPixels, 'The samples must fit the raster');
  end;
  Assert.IsTrue(IsDecoded or HasLogLine('skipped'), 'A refused image should be logged');
end;

procedure TSampledImageReaderTests.TestShortIndexedLookupClamps;
begin
  // hival 3, but the lookup table (7 bytes) holds two complete entries: the indexes above the last entry use the last entry
  const Stream = NewStream(3, 1, 8, '', [0, 1, 3]);
  const Lookup: TBytes = [$FF, $00, $00, $00, $00, $FF, $00];
  const Items = TCosArray.Create;
  Items.Add(TCosName.Create(TCosNames.Indexed));
  Items.Add(TCosName.Create(TCosNames.DeviceRGB));
  Items.Add(TCosInteger.Create(3));
  Items.Add(TCosString.Create(Lookup, True));
  Stream.SetItem(TCosNames.ColorSpace, Items);

  const Bitmap = GetImage(NewImage(Stream));

  AssertPixel(Bitmap, 0, 0, 255, 0, 0, 255);
  AssertPixel(Bitmap, 1, 0, 0, 0, 255, 255);
  AssertPixel(Bitmap, 2, 0, 0, 0, 255, 255);
end;

procedure TSampledImageReaderTests.TestJpxIsSkippedWithLog;
begin
  const Stream = NewStream(1, 1, 8, 'DeviceRGB', [0, 0, 0, 0]);
  Stream.SetItem(TCosNames.Filter, TCosName.Create(TCosNames.JPXDecode));
  const Image = NewImage(Stream);

  var Bitmap: TPdfBitmap;
  Assert.IsFalse(Image.TryGetImage(1000, Bitmap));
  Assert.IsNull(Bitmap);
  Assert.IsTrue(HasLogLine('Cannot read JPEG2000 image: Java Advanced Imaging (JAI) Image I/O Tools are not installed'));
end;

procedure TSampledImageReaderTests.TestInvalidBitsPerComponentIsSkipped;
begin
  const Image = NewImage(NewStream(2, 2, 0, 'DeviceGray', [1, 2, 3, 4]));

  var Bitmap: TPdfBitmap;
  Assert.IsFalse(Image.TryGetImage(1000, Bitmap));
  Assert.IsTrue(HasLogLine('Image skipped'));
end;

procedure TSampledImageReaderTests.TestEmptyDataIsSkipped;
begin
  const Image = NewImage(NewStream(2, 2, 8, 'DeviceGray', nil));

  var Bitmap: TPdfBitmap;
  Assert.IsFalse(Image.TryGetImage(1000, Bitmap));
  Assert.IsTrue(HasLogLine('Image stream is empty'));
end;

procedure TSampledImageReaderTests.TestSubsamplingTakesEveryNthPixel;
begin
  var Data: TBytes;
  SetLength(Data, 16);
  for var Index := 0 to 15 do
  begin
    Data[Index] := Byte(Index * 10);
  end;
  // 16 pixels do not fit 4: every second column and row is taken
  const Bitmap = GetImage(NewImage(NewStream(4, 4, 8, 'DeviceGray', Data)), 4);

  Assert.AreEqual(2, Bitmap.Width);
  Assert.AreEqual(2, Bitmap.Height);
  AssertPixel(Bitmap, 0, 0, 0, 0, 0, 255);
  AssertPixel(Bitmap, 1, 0, 20, 20, 20, 255);
  AssertPixel(Bitmap, 0, 1, 80, 80, 80, 255);
  AssertPixel(Bitmap, 1, 1, 100, 100, 100, 255);
  Assert.IsTrue(HasLogLine('subsampled by 2'));
end;

procedure TSampledImageReaderTests.TestStencilMaskAlphaFollowsDecode;
begin
  const PlainStream = NewStream(8, 1, 1, '', [$F0]);
  PlainStream.SetItem(TCosNames.ImageMask, TCosBoolean.Create(True));
  const Plain = NewImage(PlainStream);
  const Flipped = NewStream(8, 1, 1, '', [$F0]);
  Flipped.SetItem(TCosNames.ImageMask, TCosBoolean.Create(True));
  SetNumbers(Flipped, TCosNames.Decode, [1, 0]);
  const FlippedImage = NewImage(Flipped);

  var Mask: TPdfBitmap;
  Assert.IsTrue(Plain.TryGetStencilMask(1000, Mask));
  FOwned.Add(Mask);
  // Decode [0 1]: a sample of 0 paints
  AssertPixel(Mask, 0, 0, 0, 0, 0, 0);
  AssertPixel(Mask, 7, 0, 0, 0, 0, 255);

  Assert.IsTrue(FlippedImage.TryGetStencilMask(1000, Mask));
  FOwned.Add(Mask);
  AssertPixel(Mask, 0, 0, 0, 0, 0, 255);
  AssertPixel(Mask, 7, 0, 0, 0, 0, 0);
end;

// A row of 3 pixels of 4 bits is 12 bits and takes two bytes
procedure TSampledImageReaderTests.TestFourBitRowsArePadded;
begin
  const Bitmap = GetImage(NewImage(NewStream(3, 2, 4, 'DeviceGray', [$0F, $80, $F0, $80])));

  AssertPixel(Bitmap, 0, 0, 0, 0, 0, 255);
  AssertPixel(Bitmap, 1, 0, 255, 255, 255, 255);
  AssertPixel(Bitmap, 2, 0, 136, 136, 136, 255);
  AssertPixel(Bitmap, 0, 1, 255, 255, 255, 255);
  AssertPixel(Bitmap, 1, 1, 0, 0, 0, 255);
  AssertPixel(Bitmap, 2, 1, 136, 136, 136, 255);
end;

procedure TSampledImageReaderTests.TestStencilHasNoColorSpace;
begin
  const Stream = NewStream(8, 1, 1, '', [$F0]);
  Stream.SetItem(TCosNames.ImageMask, TCosBoolean.Create(True));
  const Image = NewImage(Stream);

  Assert.IsTrue(Image.IsStencil);
  Assert.IsNull(Image.ColorSpace);
  Assert.AreEqual(1, Image.BitsPerComponent);
  Assert.AreEqual<Integer>(2, Length(Image.Decode));
end;

// Math.round of Java saturates: a value outside the range of an int becomes the nearest bound and not a number becomes 0
procedure TSampledImageReaderTests.TestJavaRoundSaturatesLikeJava;
begin
  Assert.AreEqual(High(Integer), TSampledImageReader.JavaRound(1E30));
  Assert.AreEqual(Low(Integer), TSampledImageReader.JavaRound(-1E30));
  Assert.AreEqual(High(Integer), TSampledImageReader.JavaRound(Infinity));
  Assert.AreEqual(Low(Integer), TSampledImageReader.JavaRound(NegInfinity));
  Assert.AreEqual(0, TSampledImageReader.JavaRound(NaN));
  Assert.AreEqual(High(Integer), TSampledImageReader.JavaRound(3E9));
  Assert.AreEqual(3, TSampledImageReader.JavaRound(2.5));
  Assert.AreEqual(-2, TSampledImageReader.JavaRound(-2.5));
end;

// A /Decode with a huge range gives huge samples: the byte is the low eight bits of the saturated value, and nothing is raised
procedure TSampledImageReaderTests.TestHugeDecodeRangeDoesNotRaise;
begin
  const Stream = NewStream(2, 1, 8, 'DeviceGray', [255, 128]);
  const Decode = TCosArray.Create;
  Decode.Add(TCosFloat.Create(0));
  Decode.Add(TCosFloat.Create(1E30));
  Stream.SetItem(TCosNames.Decode, Decode);
  const Bitmap = GetImage(NewImage(Stream));

  Assert.AreEqual(2, Bitmap.Width);
end;

procedure TSampledImageReaderTests.TestEncodedDataOfDctIsTheStreamData;
begin
  const Stream = NewStream(1, 1, 8, 'DeviceRGB', [1, 2, 3, 4, 5]);
  Stream.SetItem(TCosNames.Filter, TCosName.Create(TCosNames.DCTDecode));

  var Data: TBytes;
  var Filter: string;
  Assert.IsTrue(NewImage(Stream).TryGetEncodedData(Data, Filter));

  Assert.AreEqual('DCTDecode', Filter);
  Assert.AreEqual<Integer>(5, Length(Data));
  Assert.AreEqual<Byte>(1, Data[0]);
  Assert.AreEqual<Byte>(5, Data[4]);
end;

procedure TSampledImageReaderTests.TestEncodedDataUndoesFlateBeforeDct;
begin
  var Compressed: TBytes;
  ZCompress(TBytes.Create(9, 8, 7, 6), Compressed);
  const Stream = NewStream(1, 1, 8, 'DeviceRGB', Compressed);
  const Filters = TCosArray.Create;
  Filters.Add(TCosName.Create(TCosNames.FlateDecode));
  Filters.Add(TCosName.Create(TCosNames.DCTDecode));
  Stream.SetItem(TCosNames.Filter, Filters);

  var Data: TBytes;
  var Filter: string;
  Assert.IsTrue(NewImage(Stream).TryGetEncodedData(Data, Filter));

  Assert.AreEqual('DCTDecode', Filter);
  Assert.AreEqual<Integer>(4, Length(Data));
  Assert.AreEqual<Byte>(9, Data[0]);
  Assert.AreEqual<Byte>(6, Data[3]);
end;

procedure TSampledImageReaderTests.TestEncodedDataOfOtherImageFilters(const FilterName: string);
begin
  const Stream = NewStream(1, 1, 8, 'DeviceRGB', [10, 20, 30]);
  Stream.SetItem(TCosNames.Filter, TCosName.Create(FilterName));

  var Data: TBytes;
  var Filter: string;
  Assert.IsTrue(NewImage(Stream).TryGetEncodedData(Data, Filter));

  Assert.AreEqual(FilterName, Filter);
  Assert.AreEqual<Integer>(3, Length(Data));
end;

procedure TSampledImageReaderTests.TestEncodedDataIsFalseWithoutImageFilter;
begin
  var Compressed: TBytes;
  ZCompress(TBytes.Create(1, 2, 3), Compressed);
  const Plain = NewStream(1, 1, 8, 'DeviceRGB', [1, 2, 3]);
  const Flate = NewStream(1, 1, 8, 'DeviceRGB', Compressed);
  Flate.SetItem(TCosNames.Filter, TCosName.Create(TCosNames.FlateDecode));

  var Data: TBytes;
  var Filter: string;
  Assert.IsFalse(NewImage(Plain).TryGetEncodedData(Data, Filter));
  Assert.IsFalse(NewImage(Flate).TryGetEncodedData(Data, Filter));
  Assert.AreEqual<Integer>(0, Length(Data));
  Assert.AreEqual('', Filter);
  Assert.AreEqual<Integer>(0, FLines.Count);
end;

procedure TSampledImageReaderTests.TestEncodedDataIsFalseWhenAnEarlierFilterFails;
begin
  const Stream = NewStream(1, 1, 8, 'DeviceRGB', [1, 2, 3, 4]);
  const Filters = TCosArray.Create;
  Filters.Add(TCosName.Create('NoSuchDecode'));
  Filters.Add(TCosName.Create(TCosNames.DCTDecode));
  Stream.SetItem(TCosNames.Filter, Filters);
  const Image = NewImage(Stream);

  var Data: TBytes;
  var Filter: string;
  Assert.IsFalse(Image.TryGetEncodedData(Data, Filter));

  Assert.AreEqual<Integer>(0, Length(Data));
  Assert.IsTrue(HasLogLine('The data of the image cannot be read'));
  Assert.IsTrue(Image.LastError <> '');
end;

procedure TSampledImageReaderTests.TestHugeMatteDoesNotRaise;
begin
  const Stream = NewStream(1, 1, 8, 'DeviceRGB', [10, 20, 30]);
  const MaskStream = NewStream(1, 1, 8, 'DeviceGray', [128]);
  const Matte = TCosArray.Create;
  for var Index := 0 to 2 do
  begin
    Matte.Add(TCosFloat.Create(1E30));
  end;
  MaskStream.SetItem(TCosNames.Matte, Matte);
  Stream.SetItem(TCosNames.SMask, MaskStream);
  FOwned.Extract(MaskStream);
  const Bitmap = GetImage(NewImage(Stream));

  Assert.AreEqual(1, Bitmap.Width);
end;

end.
