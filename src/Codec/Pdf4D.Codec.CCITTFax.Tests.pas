// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Codec.CCITTFax.Tests;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Common.Log,
  Pdf4D.Codec.CCITTFax;

type
  [TestFixture]
  TCCITTFaxTests = class
  private
    FLines: TList<string>;
    FLog: TPdfLog;

    class function PackBits(const BitText: string): TBytes; static;
    class function ParametersOf(const K, Columns, Rows: Integer; const BlackIs1: Boolean = True): TCCITTFaxParameters; static;
    class function ExpectedPicture: TBytes; static;
    class function ImageData(const ImageName: string; out Parameters: TCCITTFaxParameters): TBytes; static;

    function DecodeRaw(const Data: TBytes; const Parameters: TCCITTFaxParameters; const MaxPixels: Int64 = 100000000): TBytes;
    procedure AssertBytesEqual(const Expected, Actual: TBytes);
    procedure AssertImageEqualsPicture(const ImageName: string);
    procedure AssertGarbageIsHarmless(const K: Integer);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestGroup3OneDimensional;

    [Test]
    procedure TestGroup3TwoDimensional;

    [Test]
    procedure TestGroup4;

    [Test]
    procedure TestBlackIs1Inverts;

    [Test]
    procedure TestPaddingBitsAreInvertedToo;

    [Test]
    procedure TestEncodedByteAlign;

    [Test]
    procedure TestModifiedHuffmanWithoutEndOfLine;

    [Test]
    procedure TestCorpusCcittImages;

    [Test]
    procedure TestGarbageCCITTDoesNotHang;

    [Test]
    procedure TestRowsLimitedByMaxPixels;

    [Test]
    procedure TestInvalidDimensionsRaiseParseError;

    [Test]
    procedure TestTruncatedDataLeavesTheRestWhite;

    [Test]
    procedure TestMalformedRowKeepsTheRowsBefore;

    [Test]
    procedure TestEmptyDataRaisesParseError;

    [Test]
    procedure TestParametersFromDictionary;
  end;

implementation

uses
  System.Classes,
  System.Diagnostics,
  System.IOUtils,
  System.Math,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Boolean,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Names,
  Pdf4D.Graphics.Image,
  Pdf4D.Model.Document,
  Pdf4D.Render.Bitmap,
  Pdf4D.Tests.Corpus;

const
  CcittCorpusFile = 'generated/render/ccitt.pdf';
  PictureColumns = 96;
  PictureRows = 64;
  EndOfLineCode = '000000000001';
  // Codes of the tables of T.4 for a row of 8 pixels: 2 white, 3 black, 3 white
  WhiteTwo = '0111';
  BlackThree = '10';
  WhiteThree = '1000';
  WhiteZero = '00110101';
  BlackZero = '0000110111';
  HorizontalMode = '001';
  VerticalZero = '1';
  ByteBits = 8;
  RowOfPattern = $38;
  InvertedRowOfPattern = $C7;
  GarbageSize = 1024 * 1024;
  GarbageSeed = 42;
  GarbageRows = 4096;
  GarbageColumns = 1728;
  GarbageLimitMilliseconds = 2000;
  MinimumCorpusImages = 6;
  CorpusFiles: array[0..5] of string = (
    'generated/render/ccitt.pdf',
    'pdfbox/input/merge/multitiff.pdf',
    'pdfbox-jira/PDFBOX-3785-202097.pdf',
    'pdfbox-jira/PDFBOX-4418-000671.pdf',
    'pdfbox-jira/PDFBOX-4831.pdf',
    'pdfbox-jira/PDFBOX-3949-MKFYUGZWS3OPXLLVU2Z4LWCTVA5WNOGF.pdf');

{ TCCITTFaxTests }

procedure TCCITTFaxTests.Setup;
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

procedure TCCITTFaxTests.TearDown;
begin
  FLog.Free;
  FLines.Free;
end;

// The bits of a text of 0 and 1 (spaces ignored), the last byte padded with 0 bits
class function TCCITTFaxTests.PackBits(const BitText: string): TBytes;
begin
  const Bits = BitText.Replace(' ', '');
  SetLength(Result, (Length(Bits) + ByteBits - 1) div ByteBits);
  for var Position := 0 to Length(Bits) - 1 do
  begin
    if Bits[Position + 1] = '1' then
    begin
      Result[Position div ByteBits] := Result[Position div ByteBits] or (Byte($80) shr (Position mod ByteBits));
    end;
  end;
end;

class function TCCITTFaxTests.ParametersOf(const K, Columns, Rows: Integer; const BlackIs1: Boolean): TCCITTFaxParameters;
begin
  Result := TCCITTFaxParameters.FromDictionary(nil, Rows);
  Result.K := K;
  Result.Columns := Columns;
  Result.BlackIs1 := BlackIs1;
end;

// The picture of ccittg3.tif and ccittg4.tif as Pillow decodes it, in the samples of the DeviceGray image (1 bit per pixel, black is 0).
// The test images have /BlackIs1 true, so the decoder returns these bits as they are.
class function TCCITTFaxTests.ExpectedPicture: TBytes;
begin
  const Folder = TPath.Combine(TPath.Combine(TPath.GetDirectoryName(TCorpus.Folder), 'reference'), 'ccitt');
  Result := TFile.ReadAllBytes(TPath.Combine(Folder, 'ccitt.raw'));
end;

// The encoded data and the parameters of an image of ccitt.pdf
class function TCCITTFaxTests.ImageData(const ImageName: string; out Parameters: TCCITTFaxParameters): TBytes;
begin
  const Document = TPDDocument.Load(TFileStream.Create(TCorpus.PdfPath(CcittCorpusFile), fmOpenRead or fmShareDenyWrite), True, TPdfLoadOptions.Default);
  try
    const Resources = Document.Pages.Get(0).Resources;
    var Stream: TCosStream;
    Assert.IsTrue(Resources.TryGetXObject(ImageName, Stream), Format('%s is not in the test PDF', [ImageName]));
    var DecodeParms: TCosDictionary := nil;
    if not Stream.TryGetCosDictionary(TCosNames.DecodeParms, DecodeParms) then
    begin
      DecodeParms := nil;
    end;
    Parameters := TCCITTFaxParameters.FromDictionary(DecodeParms, Stream.GetInt(TCosNames.Height, 0));
    const Decoded = Stream.DecodeUntilImageFilter;
    Assert.AreEqual('CCITTFaxDecode', string.Join(',', Decoded.RemainingFilters));
    Result := Decoded.Data;
  finally
    Document.Free;
  end;
end;

function TCCITTFaxTests.DecodeRaw(const Data: TBytes; const Parameters: TCCITTFaxParameters; const MaxPixels: Int64): TBytes;
begin
  Result := TCCITTFaxDecoder.Decode(Data, Parameters, MaxPixels, FLog);
end;

procedure TCCITTFaxTests.AssertBytesEqual(const Expected, Actual: TBytes);
begin
  Assert.AreEqual<Integer>(Length(Expected), Length(Actual), 'byte count');
  for var Index := 0 to Length(Expected) - 1 do
  begin
    if Expected[Index] <> Actual[Index] then
    begin
      Assert.Fail(Format('Byte %d is %d, expected %d', [Index, Actual[Index], Expected[Index]]));
    end;
  end;
end;

procedure TCCITTFaxTests.AssertImageEqualsPicture(const ImageName: string);
begin
  var Parameters: TCCITTFaxParameters;
  const Data = ImageData(ImageName, Parameters);

  const Actual = DecodeRaw(Data, Parameters);

  Assert.AreEqual<Integer>(PictureColumns, Parameters.Columns);
  Assert.AreEqual<Integer>(PictureRows, Parameters.Rows);
  Assert.IsTrue(Parameters.BlackIs1, 'The test images say BlackIs1');
  AssertBytesEqual(ExpectedPicture, Actual);
  Assert.AreEqual<Integer>(0, FLines.Count, 'No warnings');
end;

procedure TCCITTFaxTests.TestGroup3OneDimensional;
begin
  // Group 3 without /EndOfLine: the decoder looks for the first EOL
  AssertImageEqualsPicture('Im2');
end;

procedure TCCITTFaxTests.TestGroup3TwoDimensional;
begin
  const Data = PackBits(EndOfLineCode + '1' + WhiteTwo + BlackThree + WhiteThree +
                        EndOfLineCode + '0' + VerticalZero + VerticalZero + VerticalZero);

  const Actual = DecodeRaw(Data, ParametersOf(1, 8, 2));

  AssertBytesEqual([RowOfPattern, RowOfPattern], Actual);
end;

procedure TCCITTFaxTests.TestGroup4;
begin
  AssertImageEqualsPicture('Im1');
end;

procedure TCCITTFaxTests.TestBlackIs1Inverts;
begin
  var Parameters: TCCITTFaxParameters;
  const Data = ImageData('Im1', Parameters);
  Parameters.BlackIs1 := False;

  const Actual = DecodeRaw(Data, Parameters);

  var Expected := ExpectedPicture;
  for var Index := 0 to Length(Expected) - 1 do
  begin
    Expected[Index] := not Expected[Index];
  end;
  AssertBytesEqual(Expected, Actual);
end;

// CCITTFaxFilter inverts every byte of the buffer, the padding bits of a row included
procedure TCCITTFaxTests.TestPaddingBitsAreInvertedToo;
begin
  const Data = PackBits(VerticalZero + VerticalZero);

  const Actual = DecodeRaw(Data, ParametersOf(-1, 10, 2, False));

  AssertBytesEqual([$FF, $FF, $FF, $FF], Actual);
end;

procedure TCCITTFaxTests.TestEncodedByteAlign;
begin
  const FirstRow = HorizontalMode + WhiteTwo + BlackThree + VerticalZero;
  const Data = PackBits(FirstRow + '000000' + VerticalZero + VerticalZero + VerticalZero + '00000');
  var Parameters := ParametersOf(-1, 8, 2);
  Parameters.EncodedByteAlign := True;

  const Actual = DecodeRaw(Data, Parameters);

  AssertBytesEqual([RowOfPattern, RowOfPattern], Actual);
end;

// /K 0 with /EndOfLine false is the modified Huffman code: no EOL, one row after the other
procedure TCCITTFaxTests.TestModifiedHuffmanWithoutEndOfLine;
begin
  const Row = WhiteTwo + BlackThree + WhiteThree;
  const Data = PackBits(Row + Row);
  var Parameters := ParametersOf(0, 8, 2);
  Parameters.HasEndOfLine := True;
  Parameters.EndOfLine := False;

  const Actual = DecodeRaw(Data, Parameters);

  AssertBytesEqual([RowOfPattern, RowOfPattern], Actual);
end;

procedure TCCITTFaxTests.TestCorpusCcittImages;
begin
  var Decoded := 0;
  for var Entry in CorpusFiles do
  begin
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
        for var Name in XObjects.Keys do
        begin
          var Stream: TCosStream;
          if (not Resources.IsImageXObject(Name)) or (not Resources.TryGetXObject(Name, Stream)) then
          begin
            Continue;
          end;
          const IsCcitt = (Stream.DecodeUntilImageFilter.RemainingFilters <> nil) and
                          (TCosNames.CCITTFaxDecode = Stream.DecodeUntilImageFilter.RemainingFilters[0]);
          if not IsCcitt then
          begin
            Continue;
          end;

          const Image = TPDImageXObject.Create(Stream, Resources);
          try
            var Bitmap: TPdfBitmap;
            const IsDecoded = Image.TryGetImage(MaxInt, Bitmap);
            Assert.IsTrue(IsDecoded, Format('%s page %d image %s should decode', [Entry, PageIndex + 1, Name]));
            Bitmap.Free;
            Inc(Decoded);
          finally
            Image.Free;
          end;
        end;
      end;
    finally
      Document.Free;
    end;
  end;

  Assert.IsTrue(Decoded >= MinimumCorpusImages, Format('Only %d CCITT images were decoded', [Decoded]));
end;

procedure TCCITTFaxTests.AssertGarbageIsHarmless(const K: Integer);
begin
  RandSeed := GarbageSeed;
  var Garbage: TBytes;
  SetLength(Garbage, GarbageSize);
  for var Index := 0 to GarbageSize - 1 do
  begin
    Garbage[Index] := Byte(Random(256));
  end;
  const Stopwatch = TStopwatch.StartNew;

  const Actual = DecodeRaw(Garbage, ParametersOf(K, GarbageColumns, GarbageRows));

  Assert.AreEqual<Integer>(((GarbageColumns + 7) div 8) * GarbageRows, Length(Actual), Format('size for K %d', [K]));
  Assert.IsTrue(Stopwatch.ElapsedMilliseconds < GarbageLimitMilliseconds, Format('K %d took %d ms', [K, Stopwatch.ElapsedMilliseconds]));
end;

procedure TCCITTFaxTests.TestGarbageCCITTDoesNotHang;
begin
  AssertGarbageIsHarmless(-1);
  AssertGarbageIsHarmless(0);
  AssertGarbageIsHarmless(1);
end;

procedure TCCITTFaxTests.TestRowsLimitedByMaxPixels;
begin
  const Data = PackBits(VerticalZero);
  const TooMany = ParametersOf(-1, 1728, 1000000);

  Assert.WillRaise(
    procedure
    begin
      DecodeRaw(Data, TooMany, 1000000);
    end,
    EPdfParseException);

  const Exactly = ParametersOf(-1, 1000, 1000);
  Assert.AreEqual<Integer>(125 * 1000, Length(DecodeRaw(Data, Exactly, 1000000)));
end;

procedure TCCITTFaxTests.TestInvalidDimensionsRaiseParseError;
begin
  const Data = PackBits(VerticalZero);

  Assert.WillRaise(
    procedure
    begin
      DecodeRaw(Data, ParametersOf(-1, 0, 4));
    end,
    EPdfParseException);
  Assert.WillRaise(
    procedure
    begin
      DecodeRaw(Data, ParametersOf(-1, 8, 0));
    end,
    EPdfParseException);
  Assert.WillRaise(
    procedure
    begin
      DecodeRaw(Data, ParametersOf(-1, MaxInt, 1));
    end,
    EPdfParseException);
end;

procedure TCCITTFaxTests.TestTruncatedDataLeavesTheRestWhite;
begin
  const Data = PackBits(HorizontalMode + WhiteTwo + BlackThree + VerticalZero);

  const Raw = DecodeRaw(Data, ParametersOf(-1, 8, 3));
  const Inverted = DecodeRaw(Data, ParametersOf(-1, 8, 3, False));

  AssertBytesEqual([RowOfPattern, 0, 0], Raw);
  AssertBytesEqual([InvertedRowOfPattern, $FF, $FF], Inverted);
  Assert.AreEqual<Integer>(0, FLines.Count, 'A short stream is not reported, like PDFBox');
end;

procedure TCCITTFaxTests.TestMalformedRowKeepsTheRowsBefore;
begin
  var Overflow := '';
  for var Count := 1 to 8 do
  begin
    Overflow := Overflow + HorizontalMode + WhiteZero + BlackZero;
  end;
  const FirstRow = HorizontalMode + WhiteTwo + BlackThree + VerticalZero;
  const Data = PackBits(FirstRow + Overflow + VerticalZero);

  const Actual = DecodeRaw(Data, ParametersOf(-1, 8, 4));

  AssertBytesEqual([RowOfPattern, 0, 0, 0], Actual);
  Assert.AreEqual<Integer>(1, FLines.Count, 'One warning for the damaged row');
end;

procedure TCCITTFaxTests.TestEmptyDataRaisesParseError;
begin
  Assert.WillRaise(
    procedure
    begin
      DecodeRaw(nil, ParametersOf(0, 8, 2));
    end,
    EPdfParseException);
end;

procedure TCCITTFaxTests.TestParametersFromDictionary;
begin
  const Defaults = TCCITTFaxParameters.FromDictionary(nil, 0);
  Assert.AreEqual<Integer>(0, Defaults.K);
  Assert.AreEqual<Integer>(1728, Defaults.Columns);
  Assert.AreEqual<Integer>(0, Defaults.Rows);
  Assert.IsFalse(Defaults.EncodedByteAlign);
  Assert.IsFalse(Defaults.HasEndOfLine);
  Assert.IsTrue(Defaults.EndOfBlock);
  Assert.IsFalse(Defaults.BlackIs1);
  Assert.AreEqual<Integer>(0, Defaults.DamagedRowsBeforeError);

  const Dictionary = TCosDictionary.Create;
  try
    Dictionary.SetItem(TCosNames.K, TCosInteger.Create(-1));
    Dictionary.SetItem(TCosNames.Columns, TCosInteger.Create(96));
    Dictionary.SetItem(TCosNames.Rows, TCosInteger.Create(10));
    Dictionary.SetItem(TCosNames.BlackIs1, TCosBoolean.Create(True));
    Dictionary.SetItem(TCosNames.EndOfLine, TCosBoolean.Create(False));

    const Taller = TCCITTFaxParameters.FromDictionary(Dictionary, 64);
    Assert.AreEqual<Integer>(-1, Taller.K);
    Assert.AreEqual<Integer>(96, Taller.Columns);
    Assert.AreEqual<Integer>(64, Taller.Rows, 'The height of the image wins over /Rows');
    Assert.IsTrue(Taller.BlackIs1);
    Assert.IsTrue(Taller.HasEndOfLine);
    Assert.IsFalse(Taller.EndOfLine);

    Assert.AreEqual<Integer>(10, TCCITTFaxParameters.FromDictionary(Dictionary, 0).Rows);
  finally
    Dictionary.Free;
  end;
end;

end.
