// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/test/java/org/apache/fontbox/cff/CFFParserTest.java, CFFCharsetTest.java, CFFEncodingTest.java,
// DataInputTest.java and Type1FontUtilTest.java (3.0.8)
unit Pdf4D.FontBox.Cff.Parser.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Diagnostics,
  DUnitX.TestFramework,
  Pdf4D.FontBox.Cff.Font;

type
  TFontCheck = reference to procedure(const Font: TCFFType1Font);

  [TestFixture]
  TCFFDataInputTests = class
  private
    class function SampleData: TBytes; static;

  public
    [Test]
    procedure TestReadBytes;

    [Test]
    procedure TestReadByte;

    [Test]
    procedure TestReadUnsignedByte;

    [Test]
    procedure TestBasics;

    [Test]
    procedure TestPeek;

    [Test]
    procedure TestReadShort;

    [Test]
    procedure TestReadUnsignedShort;

    [Test]
    procedure TestReadInt;

    [Test]
    procedure TestReadOffset;
  end;

  [TestFixture]
  TCFFCharsetTests = class
  public
    [Test]
    procedure TestCFFCharsetType1;

    [Test]
    procedure TestCFFExpertCharset;

    [Test]
    procedure TestCFFExpertSubsetCharset;

    [Test]
    procedure TestCFFISOAdobeCharset;

    [Test]
    procedure TestPredefinedCharsetsAreShared;

    [Test]
    procedure TestStandardStringNames;

    [Test]
    procedure TestStandardStringOutOfRangeRaises;
  end;

  [TestFixture]
  TCFFEncodingTests = class
  public
    [Test]
    procedure TestCFFExpertEncoding;

    [Test]
    procedure TestCFFStandardEncoding;

    [Test]
    procedure TestPredefinedEncodingsAreShared;
  end;

  [TestFixture]
  TType1FontUtilTests = class
  private
    const Loops = 200;
    const DefaultSeed = 12345;

  private
    class function RandomBytes(const Count, Seed: Integer): TBytes; static;

  public
    [Test]
    procedure TestHexEncoding;

    [Test]
    procedure TestHexDecodeOfBadTextRaises;

    [Test]
    procedure TestEexecEncryption;

    [Test]
    procedure TestCharstringEncryption;

    [Test]
    procedure TestDecryptOfTooShortDataRaises;
  end;

  [TestFixture]
  TCFFParserTests = class
  private
    const SourceSansPro = 'SourceSansProBold.otf';
    const SfntHeaderSize = 12;
    const SfntDirectoryEntrySize = 16;

  private
    class function CffTableOfSourceSans: TBytes; static;
    class procedure WithFont(const Data: TBytes; const Check: TFontCheck); static;
    class procedure CheckBytes(const Expected: array of Byte; const Actual: TBytes); static;
    class procedure CheckNumbers(const Expected: array of Integer; const Actual: TArray<Double>); static;

  public
    [Test]
    procedure TestFontname;

    [Test]
    procedure TestFontBBox;

    [Test]
    procedure TestFontMatrix;

    [Test]
    procedure TestCharset;

    [Test]
    procedure TestEncoding;

    [Test]
    procedure TestCharStringBytes;

    [Test]
    procedure TestGlobalSubrIndex;

    [Test]
    procedure TestDeltaLists;

    [Test]
    procedure TestWholeOpenTypeFileGivesTheSameFont;

    [Test]
    procedure TestHasGlyphAndNameToGID;

    [Test]
    procedure TestSecondOpenTypeFile;
  end;

  [TestFixture]
  TCFFSyntheticFontTests = class
  private
    class function FontWith(const Charset, Encoding: TBytes; const GlyphCount: Integer = 3): TBytes; static;
  public
    [Test]
    procedure TestDefaultsOfAMinimalFont;

    [Test]
    procedure TestWidthsAndLocalSubrs;

    [Test]
    procedure TestRealNumbersInTheTopDict;

    [Test]
    procedure TestMissingExponentIsReadAsZero;

    [Test]
    procedure TestCharsetFormat0;

    [Test]
    procedure TestCharsetFormat1;

    [Test]
    procedure TestCharsetFormat2;

    [Test]
    procedure TestCustomStringsInTheCharset;

    [Test]
    procedure TestEncodingFormat0WithSupplement;

    [Test]
    procedure TestEncodingFormat1;

    [Test]
    procedure TestCIDFontIsUnsupported;

    [Test]
    procedure TestOpenTypeWithoutCffTableRaises;

    [Test]
    procedure TestTrueTypeCollectionRaises;
  end;

  [TestFixture]
  TCFFHostileInputTests = class
  private
    const MaximumHostileMilliseconds = 1000;

  private
    class function OutcomeOf(const Data: TBytes; out Message: string): string; overload; static;
    class function OutcomeOf(const Data: TBytes): string; overload; static;
    class procedure CheckRaises(const Data: TBytes; const MessageFragment: string = ''); static;
    class function RawFont(const TopDict: TBytes): TBytes; static;

  public
    [Test]
    procedure TestIndexCountBeyondDataRaises;

    [Test]
    procedure TestIndexOffsetsGoingBackwardsRaise;

    [Test]
    procedure TestIndexOffsetBeyondDataRaises;

    [Test]
    procedure TestIndexEntryBeyondDataRaises;

    [Test]
    procedure TestIllegalOffSizeRaises;

    [Test]
    procedure TestDictWithBadRealIsLenient;

    [Test]
    procedure TestDictWithUnterminatedRealRaises;

    [Test]
    procedure TestDictRealNumberLengthIsBounded;

    [Test]
    procedure TestDictOperandStackIsBounded;

    [Test]
    procedure TestDictWithInvalidByteRaises;

    [Test]
    procedure TestSyntheticBaseRaises;

    [Test]
    procedure TestCharsetBeyondDataRaises;

    [Test]
    procedure TestCharsetOfUnknownFormatRaises;

    [Test]
    procedure TestCharsetRangeStopsAtTheGlyphCount;

    [Test]
    procedure TestEncodingOfUnknownFormatRaises;

    [Test]
    procedure TestEncodingOffsetBeyondDataRaises;

    [Test]
    procedure TestTruncatedFontOnlyRaisesParseException;

    [Test]
    procedure TestTruncatedSourceSansOnlyRaisesParseException;

    [Test]
    procedure TestChangedBytesNeverEndInAnotherException;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.FontBox.BoundingBox,
  Pdf4D.FontBox.Encoding,
  Pdf4D.FontBox.Cff.Charset,
  Pdf4D.FontBox.Cff.DataInput,
  Pdf4D.FontBox.Cff.Encoding,
  Pdf4D.FontBox.Cff.Parser,
  Pdf4D.FontBox.Cff.StandardStrings,
  Pdf4D.FontBox.Cff.Type1FontUtil,
  Pdf4D.Tests.CffBuilder,
  Pdf4D.Tests.TestFonts;

{ TCFFDataInputTests }

class function TCFFDataInputTests.SampleData: TBytes;
begin
  Result := TCffBuilder.Bytes([0, 255, 2, 253, 4, 251, 6, 249, 8, 247]);
end;

procedure TCFFDataInputTests.TestReadBytes;
begin
  const Input = TCFFDataInput.Create(SampleData);
  try
    Assert.WillRaise(
      procedure
      begin
        Input.ReadBytes(20);
      end,
      EPdfParseException);
    Assert.AreEqual(0, Input.GetPosition);
    Assert.AreEqual<TBytes>(TCffBuilder.Bytes([0]), Input.ReadBytes(1));
    Assert.AreEqual<TBytes>(TCffBuilder.Bytes([255, 2, 253]), Input.ReadBytes(3));
    Input.SetPosition(6);
    Assert.AreEqual<TBytes>(TCffBuilder.Bytes([6, 249, 8]), Input.ReadBytes(3));
    Assert.WillRaise(
      procedure
      begin
        Input.ReadBytes(-1);
      end,
      EPdfParseException);
    Assert.WillRaise(
      procedure
      begin
        Input.ReadBytes(5);
      end,
      EPdfParseException);
  finally
    Input.Free;
  end;
end;

procedure TCFFDataInputTests.TestReadByte;
begin
  const Input = TCFFDataInput.Create(SampleData);
  try
    Assert.AreEqual(0, Integer(Input.ReadByte));
    Assert.AreEqual(-1, Integer(Input.ReadByte));
    Input.SetPosition(6);
    Assert.AreEqual(6, Integer(Input.ReadByte));
    Assert.AreEqual(-7, Integer(Input.ReadByte));
    Input.SetPosition(Input.GetLength - 1);
    Assert.AreEqual(-9, Integer(Input.ReadByte));
    Assert.WillRaise(
      procedure
      begin
        Input.ReadByte;
      end,
      EPdfParseException);
  finally
    Input.Free;
  end;
end;

procedure TCFFDataInputTests.TestReadUnsignedByte;
begin
  const Input = TCFFDataInput.Create(SampleData);
  try
    Assert.AreEqual(0, Input.ReadUnsignedByte);
    Assert.AreEqual(255, Input.ReadUnsignedByte);
    Input.SetPosition(6);
    Assert.AreEqual(6, Input.ReadUnsignedByte);
    Assert.AreEqual(249, Input.ReadUnsignedByte);
    Input.SetPosition(Input.GetLength - 1);
    Assert.AreEqual(247, Input.ReadUnsignedByte);
    Assert.WillRaise(
      procedure
      begin
        Input.ReadUnsignedByte;
      end,
      EPdfParseException);
  finally
    Input.Free;
  end;
end;

procedure TCFFDataInputTests.TestBasics;
begin
  const Input = TCFFDataInput.Create(SampleData);
  try
    Assert.AreEqual(10, Input.GetLength);
    Assert.IsTrue(Input.HasRemaining);
    Assert.WillRaise(
      procedure
      begin
        Input.SetPosition(-1);
      end,
      EPdfParseException);
    Assert.WillRaise(
      procedure
      begin
        Input.SetPosition(Input.GetLength);
      end,
      EPdfParseException);
  finally
    Input.Free;
  end;
end;

procedure TCFFDataInputTests.TestPeek;
begin
  const Input = TCFFDataInput.Create(SampleData);
  try
    Assert.AreEqual(0, Input.PeekUnsignedByte(0));
    Assert.AreEqual(251, Input.PeekUnsignedByte(5));
    Assert.WillRaise(
      procedure
      begin
        Input.PeekUnsignedByte(-1);
      end,
      EPdfParseException);
    Assert.WillRaise(
      procedure
      begin
        Input.PeekUnsignedByte(Input.GetLength);
      end,
      EPdfParseException);
    Assert.WillRaise(
      procedure
      begin
        Input.PeekUnsignedByte(MaxInt);
      end,
      EPdfParseException);
  finally
    Input.Free;
  end;
end;

procedure TCFFDataInputTests.TestReadShort;
begin
  const Input = TCFFDataInput.Create(TCffBuilder.Bytes([$00, $0F, $AA, 0, $FE, $FF]));
  try
    Assert.AreEqual($000F, Integer(Input.ReadShort));
    Assert.AreEqual(SmallInt($AA00), Input.ReadShort);
    Assert.AreEqual(SmallInt($FEFF), Input.ReadShort);
    Assert.WillRaise(
      procedure
      begin
        Input.ReadShort;
      end,
      EPdfParseException);
  finally
    Input.Free;
  end;
end;

procedure TCFFDataInputTests.TestReadUnsignedShort;
begin
  const Input = TCFFDataInput.Create(TCffBuilder.Bytes([$00, $0F, $AA, 0, $FE, $FF]));
  try
    Assert.AreEqual($000F, Input.ReadUnsignedShort);
    Assert.AreEqual($AA00, Input.ReadUnsignedShort);
    Assert.AreEqual($FEFF, Input.ReadUnsignedShort);
    Assert.WillRaise(
      procedure
      begin
        Input.ReadUnsignedShort;
      end,
      EPdfParseException);
  finally
    Input.Free;
  end;

  const Short = TCFFDataInput.Create(TCffBuilder.Bytes([0]));
  try
    Assert.WillRaise(
      procedure
      begin
        Short.ReadUnsignedShort;
      end,
      EPdfParseException);
  finally
    Short.Free;
  end;
end;

procedure TCFFDataInputTests.TestReadInt;
begin
  const Input = TCFFDataInput.Create(TCffBuilder.Bytes([$00, $0F, $AA, 0, $FE, $FF, $30, $50]));
  try
    Assert.AreEqual($000FAA00, Input.ReadInt);
    Assert.AreEqual(Integer($FEFF3050), Input.ReadInt);
    Assert.WillRaise(
      procedure
      begin
        Input.ReadInt;
      end,
      EPdfParseException);
  finally
    Input.Free;
  end;

  const Short = TCFFDataInput.Create(TCffBuilder.Bytes([$00, $0F, $AA]));
  try
    Assert.WillRaise(
      procedure
      begin
        Short.ReadInt;
      end,
      EPdfParseException);
  finally
    Short.Free;
  end;
end;

procedure TCFFDataInputTests.TestReadOffset;
begin
  const Input = TCFFDataInput.Create(TCffBuilder.Bytes([$12, $FF, $FF, $FF, $FF, $01, $02, $03]));
  try
    Assert.AreEqual(Int64($12), Input.ReadOffset(1));
    Assert.AreEqual(Int64($FFFFFFFF), Input.ReadOffset(4));
    Assert.AreEqual(Int64($010203), Input.ReadOffset(3));
  finally
    Input.Free;
  end;
end;

{ TCFFCharsetTests }

procedure TCFFCharsetTests.TestCFFCharsetType1;
begin
  const Charset = TCFFCharsetType1.Create;
  try
    Assert.IsFalse(Charset.IsCIDFont);
    Charset.AddSID(10, 20, 'test');

    Assert.AreEqual(20, Charset.GetSID('test'));
    Assert.AreEqual(10, Charset.GetGIDForSID(20));
    Assert.AreEqual(20, Charset.GetSIDForGID(10));
    Assert.AreEqual('test', Charset.GetNameForGID(10));

    Assert.AreEqual(0, Charset.GetGIDForSID(99));
    Assert.AreEqual(0, Charset.GetSIDForGID(99));
    Assert.AreEqual(0, Charset.GetSID('unknown'));
    var Name: string;
    Assert.IsFalse(Charset.TryGetNameForGID(99, Name));
    Assert.WillRaise(
      procedure
      begin
        Charset.GetNameForGID(99);
      end,
      EPdfParseException);

    Assert.WillRaise(
      procedure
      begin
        Charset.GetCIDForGID(0);
      end,
      EInvalidOpException);
    Assert.WillRaise(
      procedure
      begin
        Charset.GetGIDForCID(0);
      end,
      EInvalidOpException);
    Assert.WillRaise(
      procedure
      begin
        Charset.AddCID(0, 0);
      end,
      EInvalidOpException);
  finally
    Charset.Free;
  end;
end;

procedure TCFFCharsetTests.TestCFFExpertCharset;
begin
  const Charset = TCFFExpertCharset.Instance;
  Assert.AreEqual(0, Charset.GetSIDForGID(0));
  Assert.AreEqual(0, Charset.GetSID('.notdef'));
  Assert.AreEqual('.notdef', Charset.GetNameForGID(0));

  Assert.AreEqual(253, Charset.GetSIDForGID(32));
  Assert.AreEqual(253, Charset.GetSID('asuperior'));
  Assert.AreEqual('asuperior', Charset.GetNameForGID(32));
  Assert.AreEqual(240, Charset.GetSIDForGID(17));
  Assert.AreEqual(240, Charset.GetSID('oneoldstyle'));
  Assert.AreEqual('oneoldstyle', Charset.GetNameForGID(17));
  Assert.AreEqual(347, Charset.GetSIDForGID(134));
  Assert.AreEqual(347, Charset.GetSID('Agravesmall'));
  Assert.AreEqual('Agravesmall', Charset.GetNameForGID(134));
end;

procedure TCFFCharsetTests.TestCFFExpertSubsetCharset;
begin
  const Charset = TCFFExpertSubsetCharset.Instance;
  Assert.AreEqual(0, Charset.GetSIDForGID(0));
  Assert.AreEqual(0, Charset.GetSID('.notdef'));
  Assert.AreEqual('.notdef', Charset.GetNameForGID(0));

  Assert.AreEqual(246, Charset.GetSIDForGID(19));
  Assert.AreEqual(246, Charset.GetSID('sevenoldstyle'));
  Assert.AreEqual('sevenoldstyle', Charset.GetNameForGID(19));
  Assert.AreEqual(324, Charset.GetSIDForGID(61));
  Assert.AreEqual(324, Charset.GetSID('onethird'));
  Assert.AreEqual('onethird', Charset.GetNameForGID(61));
  Assert.AreEqual(345, Charset.GetSIDForGID(85));
  Assert.AreEqual(345, Charset.GetSID('periodinferior'));
  Assert.AreEqual('periodinferior', Charset.GetNameForGID(85));
end;

procedure TCFFCharsetTests.TestCFFISOAdobeCharset;
begin
  const Charset = TCFFISOAdobeCharset.Instance;
  Assert.AreEqual(0, Charset.GetSIDForGID(0));
  Assert.AreEqual(0, Charset.GetSID('.notdef'));
  Assert.AreEqual('.notdef', Charset.GetNameForGID(0));

  Assert.AreEqual(32, Charset.GetSIDForGID(32));
  Assert.AreEqual(32, Charset.GetSID('question'));
  Assert.AreEqual('question', Charset.GetNameForGID(32));
  Assert.AreEqual(76, Charset.GetSIDForGID(76));
  Assert.AreEqual(76, Charset.GetSID('k'));
  Assert.AreEqual('k', Charset.GetNameForGID(76));
  Assert.AreEqual(218, Charset.GetSIDForGID(218));
  Assert.AreEqual(218, Charset.GetSID('odieresis'));
  Assert.AreEqual('odieresis', Charset.GetNameForGID(218));
end;

procedure TCFFCharsetTests.TestPredefinedCharsetsAreShared;
begin
  Assert.IsTrue(TCFFISOAdobeCharset.Instance = TCFFISOAdobeCharset.Instance);
  Assert.IsTrue(TCFFExpertCharset.Instance = TCFFExpertCharset.Instance);
  Assert.IsTrue(TCFFExpertSubsetCharset.Instance = TCFFExpertSubsetCharset.Instance);
end;

procedure TCFFCharsetTests.TestStandardStringNames;
begin
  Assert.AreEqual(391, TCFFStandardString.Count);
  Assert.AreEqual('.notdef', TCFFStandardString.GetName(0));
  Assert.AreEqual('space', TCFFStandardString.GetName(1));
  Assert.AreEqual('Semibold', TCFFStandardString.GetName(390));
  Assert.AreEqual('001.000', TCFFStandardString.GetName(379));
end;

procedure TCFFCharsetTests.TestStandardStringOutOfRangeRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      TCFFStandardString.GetName(391);
    end,
    EPdfParseException);
  Assert.WillRaise(
    procedure
    begin
      TCFFStandardString.GetName(-1);
    end,
    EPdfParseException);
end;

{ TCFFEncodingTests }

procedure TCFFEncodingTests.TestCFFExpertEncoding;
begin
  const Encoding = TCFFExpertEncoding.Instance;
  Assert.AreEqual('.notdef', Encoding.GetName(0));
  Assert.AreEqual('space', Encoding.GetName(32));
  Assert.AreEqual('Psmall', Encoding.GetName(112));
  Assert.AreEqual('Ucircumflexsmall', Encoding.GetName(251));

  var Code: Integer;
  Assert.IsTrue(Encoding.GetCode('space', Code));
  Assert.AreEqual(32, Code);
  Assert.IsTrue(Encoding.GetCode('Psmall', Code));
  Assert.AreEqual(112, Code);
  Assert.IsTrue(Encoding.GetCode('Ucircumflexsmall', Code));
  Assert.AreEqual(251, Code);
end;

procedure TCFFEncodingTests.TestCFFStandardEncoding;
begin
  const Encoding = TCFFStandardEncoding.Instance;
  Assert.AreEqual('.notdef', Encoding.GetName(0));
  Assert.AreEqual('space', Encoding.GetName(32));
  Assert.AreEqual('p', Encoding.GetName(112));
  Assert.AreEqual('germandbls', Encoding.GetName(251));

  var Code: Integer;
  Assert.IsTrue(Encoding.GetCode('space', Code));
  Assert.AreEqual(32, Code);
  Assert.IsTrue(Encoding.GetCode('p', Code));
  Assert.AreEqual(112, Code);
  Assert.IsTrue(Encoding.GetCode('germandbls', Code));
  Assert.AreEqual(251, Code);
end;

procedure TCFFEncodingTests.TestPredefinedEncodingsAreShared;
begin
  Assert.IsTrue(TCFFStandardEncoding.Instance = TCFFStandardEncoding.Instance);
  Assert.IsTrue(TCFFExpertEncoding.Instance = TCFFExpertEncoding.Instance);
end;

{ TType1FontUtilTests }

class function TType1FontUtilTests.RandomBytes(const Count, Seed: Integer): TBytes;
begin
  RandSeed := Seed;
  SetLength(Result, Count);
  for var Index := 0 to Count - 1 do
  begin
    Result[Index] := Random(256);
  end;
end;

procedure TType1FontUtilTests.TestHexEncoding;
begin
  for var Loop := 0 to Loops do
  begin
    const Bytes = RandomBytes(128, DefaultSeed + Loop);
    const Encoded = TType1FontUtil.HexEncode(Bytes);
    Assert.AreEqual(256, Integer(Length(Encoded)));
    Assert.AreEqual<TBytes>(Bytes, TType1FontUtil.HexDecode(Encoded));
  end;
  Assert.AreEqual('00FF10', TType1FontUtil.HexEncode(TCffBuilder.Bytes([0, 255, 16])));
end;

procedure TType1FontUtilTests.TestHexDecodeOfBadTextRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      TType1FontUtil.HexDecode('ABC');
    end,
    EPdfParseException);
  Assert.WillRaise(
    procedure
    begin
      TType1FontUtil.HexDecode('ZZ');
    end,
    EPdfParseException);
end;

procedure TType1FontUtilTests.TestEexecEncryption;
begin
  for var Loop := 0 to Loops do
  begin
    const Bytes = RandomBytes(128, DefaultSeed + Loop);
    const Encrypted = TType1FontUtil.EexecEncrypt(Bytes);
    Assert.AreEqual(132, Integer(Length(Encrypted)));
    Assert.AreEqual<TBytes>(Bytes, TType1FontUtil.EexecDecrypt(Encrypted));
  end;
end;

procedure TType1FontUtilTests.TestCharstringEncryption;
begin
  for var Loop := 0 to Loops do
  begin
    const Bytes = RandomBytes(128, DefaultSeed + Loop);
    const Encrypted = TType1FontUtil.CharstringEncrypt(Bytes, 4);
    Assert.AreEqual<TBytes>(Bytes, TType1FontUtil.CharstringDecrypt(Encrypted, 4));
  end;
end;

procedure TType1FontUtilTests.TestDecryptOfTooShortDataRaises;
begin
  const Short = TCffBuilder.Bytes([1, 2, 3]);
  Assert.WillRaise(
    procedure
    begin
      TType1FontUtil.EexecDecrypt(Short);
    end,
    EPdfParseException);
end;

{ TCFFParserTests }

// The TrueType parser refuses fonts with CFF outlines, so the table is cut from the table directory here
class function TCFFParserTests.CffTableOfSourceSans: TBytes;
begin
  const Data = TTestFonts.Bytes(SourceSansPro);
  const TableCount = (Data[4] shl 8) or Data[5];
  for var Table := 0 to TableCount - 1 do
  begin
    const Entry = SfntHeaderSize + Table * SfntDirectoryEntrySize;
    if (Data[Entry] = Ord('C')) and (Data[Entry + 1] = Ord('F')) and (Data[Entry + 2] = Ord('F')) and
       (Data[Entry + 3] = Ord(' ')) then
    begin
      const Offset = (Data[Entry + 8] shl 24) or (Data[Entry + 9] shl 16) or (Data[Entry + 10] shl 8) or Data[Entry + 11];
      const Size = (Data[Entry + 12] shl 24) or (Data[Entry + 13] shl 16) or (Data[Entry + 14] shl 8) or Data[Entry + 15];
      Exit(Copy(Data, Offset, Size));
    end;
  end;
  raise EFileNotFoundException.Create('The CFF table of the test font was not found');
end;

class procedure TCFFParserTests.WithFont(const Data: TBytes; const Check: TFontCheck);
begin
  const Parser = TCFFParser.Create;
  try
    const Fonts = Parser.Parse(Data);
    try
      Assert.AreEqual(1, Integer(Fonts.Count));
      Assert.IsTrue(Fonts[0] is TCFFType1Font);
      Check(TCFFType1Font(Fonts[0]));
    finally
      Fonts.Free;
    end;
  finally
    Parser.Free;
  end;
end;

class procedure TCFFParserTests.CheckBytes(const Expected: array of Byte; const Actual: TBytes);
begin
  Assert.AreEqual<TBytes>(TCffBuilder.Bytes(Expected), Actual);
end;

class procedure TCFFParserTests.CheckNumbers(const Expected: array of Integer; const Actual: TArray<Double>);
begin
  Assert.AreEqual(Integer(Length(Expected)), Integer(Length(Actual)));
  for var Index := 0 to High(Expected) do
  begin
    Assert.AreEqual(Expected[Index], Integer(Round(Actual[Index])));
  end;
end;

procedure TCFFParserTests.TestFontname;
begin
  WithFont(CffTableOfSourceSans,
    procedure(const Font: TCFFType1Font)
    begin
      Assert.AreEqual('SourceSansPro-Bold', Font.Name);
    end);
end;

procedure TCFFParserTests.TestFontBBox;
begin
  WithFont(CffTableOfSourceSans,
    procedure(const Font: TCFFType1Font)
    begin
      const Box = Font.FontBBox;
      Assert.AreEqual(Single(-231), Box.LowerLeftX);
      Assert.AreEqual(Single(-384), Box.LowerLeftY);
      Assert.AreEqual(Single(1223), Box.UpperRightX);
      Assert.AreEqual(Single(974), Box.UpperRightY);
    end);
end;

procedure TCFFParserTests.TestFontMatrix;
begin
  WithFont(CffTableOfSourceSans,
    procedure(const Font: TCFFType1Font)
    begin
      const Matrix = Font.FontMatrix;
      Assert.AreEqual(6, Integer(Length(Matrix)));
      Assert.AreEqual(Single(0.001), Matrix[0]);
      Assert.AreEqual(Single(0), Matrix[1]);
      Assert.AreEqual(Single(0), Matrix[2]);
      Assert.AreEqual(Single(0.001), Matrix[3]);
      Assert.AreEqual(Single(0), Matrix[4]);
      Assert.AreEqual(Single(0), Matrix[5]);
    end);
end;

procedure TCFFParserTests.TestCharset;
begin
  WithFont(CffTableOfSourceSans,
    procedure(const Font: TCFFType1Font)
    begin
      const Charset = Font.Charset;
      Assert.IsNotNull(Charset);
      Assert.IsFalse(Charset.IsCIDFont);

      Assert.AreEqual('.notdef', Charset.GetNameForGID(0));
      Assert.AreEqual('space', Charset.GetNameForGID(1));
      Assert.AreEqual('F', Charset.GetNameForGID(7));
      Assert.AreEqual('jcircumflex', Charset.GetNameForGID(300));
      Assert.AreEqual('infinity', Charset.GetNameForGID(700));

      Assert.AreEqual(0, Charset.GetSIDForGID(0));
      Assert.AreEqual(1, Charset.GetSIDForGID(1));
      Assert.AreEqual(39, Charset.GetSIDForGID(7));
      Assert.AreEqual(585, Charset.GetSIDForGID(300));
      Assert.AreEqual(872, Charset.GetSIDForGID(700));

      Assert.AreEqual(0, Charset.GetSID('.notdef'));
      Assert.AreEqual(1, Charset.GetSID('space'));
      Assert.AreEqual(39, Charset.GetSID('F'));
      Assert.AreEqual(585, Charset.GetSID('jcircumflex'));
      Assert.AreEqual(872, Charset.GetSID('infinity'));
    end);
end;

procedure TCFFParserTests.TestEncoding;
begin
  WithFont(CffTableOfSourceSans,
    procedure(const Font: TCFFType1Font)
    begin
      Assert.IsNotNull(Font.Encoding);
      Assert.IsTrue(Font.Encoding = TCFFStandardEncoding.Instance);
    end);
end;

procedure TCFFParserTests.TestCharStringBytes;
begin
  WithFont(CffTableOfSourceSans,
    procedure(const Font: TCFFType1Font)
    begin
      Assert.AreEqual(824, Integer(Length(Font.CharStrings)));
      CheckBytes([252, 15, 14], Font.CharStrings[1]);
      CheckBytes([72, 29, 243, 29, 247, 182, 247, 43, 3, 33, 29, 14], Font.CharStrings[16]);
      CheckBytes([215, 88, 29, 209, 247, 12, 1, 133, 10, 3, 35, 29, 247, 206, 247, 62, 247, 3, 10, 85, 200, 61, 10],
                 Font.CharStrings[195]);
      CheckBytes([251, 187, 195, 248, 28, 1, 247, 57, 217, 191, 29, 14], Font.CharStrings[525]);
      CheckBytes([107, 208, 10, 247, 20, 247, 123, 3, 247, 144, 248, 210, 21, 246, 115, 10], Font.CharStrings[738]);
    end);
end;

procedure TCFFParserTests.TestGlobalSubrIndex;
begin
  WithFont(CffTableOfSourceSans,
    procedure(const Font: TCFFType1Font)
    begin
      Assert.AreEqual(278, Integer(Length(Font.GlobalSubrs)));
      CheckBytes([21, 186, 173, 171, 184, 184, 105, 171, 92, 91, 105, 107, 10, 173, 247, 62, 10], Font.GlobalSubrs[12]);
      CheckBytes([58, 122, 29, 251, 48, 6, 11], Font.GlobalSubrs[120]);
      CheckBytes([68, 80, 29, 211, 247, 16, 248, 164, 119, 11], Font.GlobalSubrs[253]);
    end);
end;

procedure TCFFParserTests.TestDeltaLists;
begin
  WithFont(CffTableOfSourceSans,
    procedure(const Font: TCFFType1Font)
    begin
      var Values: TArray<Double>;
      Assert.IsTrue(Font.TryGetPrivateDictArray('BlueValues', Values));
      CheckNumbers([-12, 0, 496, 508, 578, 590, 635, 647, 652, 664, 701, 713], Values);
      Assert.IsTrue(Font.TryGetPrivateDictArray('OtherBlues', Values));
      CheckNumbers([-196, -184], Values);
      Assert.IsTrue(Font.TryGetPrivateDictArray('FamilyBlues', Values));
      CheckNumbers([-12, 0, 486, 498, 574, 586, 638, 650, 656, 668, 712, 724], Values);
      Assert.IsTrue(Font.TryGetPrivateDictArray('FamilyOtherBlues', Values));
      CheckNumbers([-217, -205], Values);
      Assert.IsTrue(Font.TryGetPrivateDictArray('StemSnapH', Values));
      CheckNumbers([115], Values);
      Assert.IsTrue(Font.TryGetPrivateDictArray('StemSnapV', Values));
      CheckNumbers([146, 150], Values);
    end);
end;

procedure TCFFParserTests.TestWholeOpenTypeFileGivesTheSameFont;
begin
  WithFont(TTestFonts.Bytes(SourceSansPro),
    procedure(const Font: TCFFType1Font)
    begin
      Assert.AreEqual('SourceSansPro-Bold', Font.Name);
      Assert.AreEqual(824, Integer(Length(Font.CharStrings)));
      Assert.AreEqual('infinity', Font.Charset.GetNameForGID(700));
    end);
end;

procedure TCFFParserTests.TestHasGlyphAndNameToGID;
begin
  WithFont(CffTableOfSourceSans,
    procedure(const Font: TCFFType1Font)
    begin
      Assert.IsTrue(Font.HasGlyph('F'));
      Assert.AreEqual(7, Font.NameToGID('F'));
      Assert.AreEqual(700, Font.NameToGID('infinity'));
      Assert.IsFalse(Font.HasGlyph('nosuchglyph'));
      Assert.AreEqual(0, Font.NameToGID('nosuchglyph'));
    end);
end;

procedure TCFFParserTests.TestSecondOpenTypeFile;
begin
  WithFont(TTestFonts.Bytes('FoglihtenNo07.otf'),
    procedure(const Font: TCFFType1Font)
    begin
      Assert.AreEqual('FoglihtenNo07', Font.Name);
      Assert.IsTrue(Length(Font.CharStrings) > 0);
      Assert.AreEqual('.notdef', Font.Charset.GetNameForGID(0));
    end);
end;

{ TCFFSyntheticFontTests }

class function TCFFSyntheticFontTests.FontWith(const Charset, Encoding: TBytes; const GlyphCount: Integer): TBytes;
begin
  var Options := TCffType1Options.Standard;
  Options.CharsetData := Charset;
  Options.EncodingData := Encoding;
  Options.GlyphCount := GlyphCount;
  Result := TCffBuilder.Type1Font(Options);
end;

procedure TCFFSyntheticFontTests.TestDefaultsOfAMinimalFont;
begin
  TCFFParserTests.WithFont(TCffBuilder.Type1Font(TCffType1Options.Standard),
    procedure(const Font: TCFFType1Font)
    begin
      Assert.AreEqual('TestFont', Font.Name);
      Assert.AreEqual(3, Integer(Length(Font.CharStrings)));
      Assert.AreEqual(0, Integer(Length(Font.GlobalSubrs)));
      Assert.AreEqual(0, Integer(Length(Font.LocalSubrs)));
      Assert.IsTrue(Font.Charset = TCFFISOAdobeCharset.Instance);
      Assert.IsTrue(Font.Encoding = TCFFStandardEncoding.Instance);

      Assert.AreEqual(Double(0), Font.GetTopDictNumber('ItalicAngle', -1));
      Assert.AreEqual(Double(-100), Font.GetTopDictNumber('UnderlinePosition', 0));
      Assert.AreEqual(Double(50), Font.GetTopDictNumber('UnderlineThickness', 0));
      Assert.AreEqual(Double(2), Font.GetTopDictNumber('CharstringType', 0));
      Assert.AreEqual(Double(7), Font.GetTopDictNumber('NoSuchKey', 7));
      const Box = Font.FontBBox;
      Assert.AreEqual(Single(-10), Box.LowerLeftX);
      Assert.AreEqual(Single(900), Box.UpperRightY);
      Assert.AreEqual(Single(0.001), Font.FontMatrix[0]);

      var Values: TArray<Double>;
      Assert.IsFalse(Font.TryGetTopDictArray('XUID', Values));
      var Text: string;
      Assert.IsFalse(Font.TryGetTopDictString('Notice', Text));
    end);
end;

procedure TCFFSyntheticFontTests.TestWidthsAndLocalSubrs;
begin
  var Options := TCffType1Options.Standard;
  Options.LocalSubrs := [TCffBuilder.Bytes([11]), TCffBuilder.Bytes([1, 2, 11])];
  TCFFParserTests.WithFont(TCffBuilder.Type1Font(Options),
    procedure(const Font: TCFFType1Font)
    begin
      Assert.AreEqual(500, Font.DefaultWidthX);
      Assert.AreEqual(600, Font.NominalWidthX);
      Assert.AreEqual(2, Integer(Length(Font.LocalSubrs)));
      Assert.AreEqual<TBytes>(TCffBuilder.Bytes([1, 2, 11]), Font.LocalSubrs[1]);
    end);
end;

procedure TCFFSyntheticFontTests.TestRealNumbersInTheTopDict;
begin
  var Options := TCffType1Options.Standard;
  // FontMatrix 0.002 0 0 0 0 0.5
  Options.ExtraTopDict := TCffBuilder.Concat([TCffBuilder.RealOperand([0, $A, 0, 0, 2, $F]),
                                              TCffBuilder.IntegerOperand(0), TCffBuilder.IntegerOperand(0),
                                              TCffBuilder.IntegerOperand(0), TCffBuilder.IntegerOperand(0),
                                              TCffBuilder.RealOperand([0, $A, 5, $F]), TCffBuilder.Bytes([12, 7]),
                                              // ItalicAngle -1.5E-2
                                              TCffBuilder.RealOperand([$E, 1, $A, 5, $C, 2, $F]),
                                              TCffBuilder.Bytes([12, 2])]);
  TCFFParserTests.WithFont(TCffBuilder.Type1Font(Options),
    procedure(const Font: TCFFType1Font)
    begin
      const Matrix = Font.FontMatrix;
      Assert.AreEqual(6, Integer(Length(Matrix)));
      Assert.AreEqual(Single(0.002), Matrix[0]);
      Assert.AreEqual(Single(0), Matrix[1]);
      Assert.AreEqual(Single(0.5), Matrix[5]);
      Assert.AreEqual(Double(-0.015), Font.GetTopDictNumber('ItalicAngle', 0), 1E-12);
    end);
end;

procedure TCFFSyntheticFontTests.TestMissingExponentIsReadAsZero;
begin
  var Options := TCffType1Options.Standard;
  Options.ExtraTopDict := TCffBuilder.Concat([TCffBuilder.RealOperand([2, $B, $F]), TCffBuilder.Bytes([12, 2])]);
  TCFFParserTests.WithFont(TCffBuilder.Type1Font(Options),
    procedure(const Font: TCFFType1Font)
    begin
      Assert.AreEqual(Double(2), Font.GetTopDictNumber('ItalicAngle', 0));
    end);
end;

procedure TCFFSyntheticFontTests.TestCharsetFormat0;
begin
  TCFFParserTests.WithFont(FontWith(TCffBuilder.Bytes([0, 0, 1, 0, 2]), nil),
    procedure(const Font: TCFFType1Font)
    begin
      Assert.IsFalse(Font.Charset is TCFFISOAdobeCharset);
      Assert.AreEqual('.notdef', Font.Charset.GetNameForGID(0));
      Assert.AreEqual('space', Font.Charset.GetNameForGID(1));
      Assert.AreEqual('exclam', Font.Charset.GetNameForGID(2));
      Assert.AreEqual(2, Font.NameToGID('exclam'));
    end);
end;

procedure TCFFSyntheticFontTests.TestCharsetFormat1;
begin
  TCFFParserTests.WithFont(FontWith(TCffBuilder.Bytes([1, 0, 10, 1]), nil),
    procedure(const Font: TCFFType1Font)
    begin
      Assert.AreEqual(10, Font.Charset.GetSIDForGID(1));
      Assert.AreEqual(11, Font.Charset.GetSIDForGID(2));
      Assert.AreEqual(TCFFStandardString.GetName(11), Font.Charset.GetNameForGID(2));
    end);
end;

procedure TCFFSyntheticFontTests.TestCharsetFormat2;
begin
  TCFFParserTests.WithFont(FontWith(TCffBuilder.Bytes([2, 0, 20, 0, 1]), nil),
    procedure(const Font: TCFFType1Font)
    begin
      Assert.AreEqual(20, Font.Charset.GetSIDForGID(1));
      Assert.AreEqual(21, Font.Charset.GetSIDForGID(2));
    end);
end;

procedure TCFFSyntheticFontTests.TestCustomStringsInTheCharset;
begin
  var Options := TCffType1Options.Standard;
  Options.StringIndexEntries := ['custom'];
  // SID 391 is the first string of the String INDEX, SID 5000 is not in it
  Options.CharsetData := TCffBuilder.Bytes([0, 1, $87, $13, $88]);
  TCFFParserTests.WithFont(TCffBuilder.Type1Font(Options),
    procedure(const Font: TCFFType1Font)
    begin
      Assert.AreEqual('custom', Font.Charset.GetNameForGID(1));
      Assert.AreEqual('SID5000', Font.Charset.GetNameForGID(2));
      Assert.AreEqual(1, Font.NameToGID('custom'));
    end);
end;

procedure TCFFSyntheticFontTests.TestEncodingFormat0WithSupplement;
begin
  // Format 0 with a supplement: one code for glyph 1, and code 200 for SID 3 (quotedbl)
  TCFFParserTests.WithFont(FontWith(nil, TCffBuilder.Bytes([$80, 1, 65, 1, 200, 0, 3])),
    procedure(const Font: TCFFType1Font)
    begin
      Assert.IsTrue(Font.Encoding is TCFFFormat0Encoding);
      Assert.AreEqual('.notdef', Font.Encoding.GetName(0));
      Assert.AreEqual('space', Font.Encoding.GetName(65));
      Assert.AreEqual('quotedbl', Font.Encoding.GetName(200));
      Assert.AreEqual(1, Integer(Length(TCFFBuiltInEncoding(Font.Encoding).Supplement)));
      Assert.AreEqual('.notdef', Font.Encoding.GetName(66));
    end);
end;

procedure TCFFSyntheticFontTests.TestEncodingFormat1;
begin
  TCFFParserTests.WithFont(FontWith(nil, TCffBuilder.Bytes([1, 1, 65, 1])),
    procedure(const Font: TCFFType1Font)
    begin
      Assert.IsTrue(Font.Encoding is TCFFFormat1Encoding);
      Assert.AreEqual('space', Font.Encoding.GetName(65));
      Assert.AreEqual('exclam', Font.Encoding.GetName(66));
    end);
end;

procedure TCFFSyntheticFontTests.TestCIDFontIsUnsupported;
begin
  var Options := TCffType1Options.Standard;
  // ROS 0 0 0
  Options.ExtraTopDict := TCffBuilder.Bytes([$8B, $8B, $8B, 12, 30]);
  const Data = TCffBuilder.Type1Font(Options);
  const Parser = TCFFParser.Create;
  try
    Assert.WillRaise(
      procedure
      begin
        Parser.Parse(Data).Free;
      end,
      EPdfUnsupportedFeatureException);
  finally
    Parser.Free;
  end;
end;

procedure TCFFSyntheticFontTests.TestOpenTypeWithoutCffTableRaises;
begin
  const Data = TCffBuilder.Concat([TCffBuilder.AsciiBytes('OTTO'), TCffBuilder.Bytes([0, 0, 0, 0, 0, 0, 0, 0])]);
  const Parser = TCFFParser.Create;
  try
    Assert.WillRaise(
      procedure
      begin
        Parser.Parse(Data).Free;
      end,
      EPdfParseException);
  finally
    Parser.Free;
  end;
end;

procedure TCFFSyntheticFontTests.TestTrueTypeCollectionRaises;
begin
  const Collection = TCffBuilder.Concat([TCffBuilder.AsciiBytes('ttcf'), TCffBuilder.Bytes([0, 1, 0, 0])]);
  const TrueType = TCffBuilder.Bytes([0, 1, 0, 0, 0, 0]);
  const Parser = TCFFParser.Create;
  try
    Assert.WillRaise(
      procedure
      begin
        Parser.Parse(Collection).Free;
      end,
      EPdfParseException);
    Assert.WillRaise(
      procedure
      begin
        Parser.Parse(TrueType).Free;
      end,
      EPdfParseException);
  finally
    Parser.Free;
  end;
end;

{ TCFFHostileInputTests }

// The class name of the exception that parsing ends in, or an empty string when it gives fonts
class function TCFFHostileInputTests.OutcomeOf(const Data: TBytes; out Message: string): string;
begin
  Result := '';
  Message := '';
  const Parser = TCFFParser.Create;
  try
    try
      Parser.Parse(Data).Free;
    except
      on Failure: Exception do
      begin
        Result := Failure.ClassName;
        Message := Failure.Message;
      end;
    end;
  finally
    Parser.Free;
  end;
end;

class function TCFFHostileInputTests.OutcomeOf(const Data: TBytes): string;
begin
  var Message: string;
  Result := OutcomeOf(Data, Message);
end;

class procedure TCFFHostileInputTests.CheckRaises(const Data: TBytes; const MessageFragment: string);
begin
  const Stopwatch = TStopwatch.StartNew;
  var Message: string;
  const Outcome = OutcomeOf(Data, Message);
  Assert.AreEqual(EPdfParseException.ClassName, Outcome);
  Assert.IsTrue((MessageFragment = '') or Message.Contains(MessageFragment), Format('Message "%s" does not contain "%s"', [Message, MessageFragment]));
  Assert.IsTrue(Stopwatch.ElapsedMilliseconds < MaximumHostileMilliseconds, 'Parsing took too long');
end;

class function TCFFHostileInputTests.RawFont(const TopDict: TBytes): TBytes;
begin
  Result := TCffBuilder.Concat([TCffBuilder.Bytes([1, 0, 4, 4]), TCffBuilder.Index([TCffBuilder.AsciiBytes('A')], 1),
                                TCffBuilder.Index([TopDict], 2), TCffBuilder.Index(nil), TCffBuilder.Index(nil)]);
end;

procedure TCFFHostileInputTests.TestIndexCountBeyondDataRaises;
begin
  // 20 bytes: the header, then an INDEX that claims 65535 entries of 4-byte offsets
  CheckRaises(TCffBuilder.Bytes([1, 0, 4, 4, $FF, $FF, 4, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 3, 0]));
end;

procedure TCFFHostileInputTests.TestIndexOffsetsGoingBackwardsRaise;
begin
  // Name INDEX with one entry, offsets 5 and 1
  CheckRaises(TCffBuilder.Bytes([1, 0, 4, 4, 0, 1, 1, 5, 1, 0, 0, 0, 0, 0, 0, 0]));
end;

procedure TCFFHostileInputTests.TestIndexOffsetBeyondDataRaises;
begin
  CheckRaises(TCffBuilder.Bytes([1, 0, 4, 4, 0, 1, 1, 1, $FF, 0, 0, 0]));
end;

procedure TCFFHostileInputTests.TestIndexEntryBeyondDataRaises;
begin
  // The offsets are inside the data, but the entry would be longer than what is left of it
  CheckRaises(TCffBuilder.Bytes([1, 0, 4, 4, 0, 1, 1, 1, 12, 65, 66, 67, 68, 0, 0, 0]));
end;

procedure TCFFHostileInputTests.TestIllegalOffSizeRaises;
begin
  CheckRaises(TCffBuilder.Bytes([1, 0, 4, 4, 0, 1, 0, 1, 2, 65]));
  CheckRaises(TCffBuilder.Bytes([1, 0, 4, 4, 0, 1, 5, 1, 2, 65]));
  CheckRaises(TCffBuilder.Bytes([1, 0, 4, 0]));
end;

procedure TCFFHostileInputTests.TestDictWithBadRealIsLenient;
begin
  // A real number that is only a minus sign has no value
  CheckRaises(RawFont(TCffBuilder.Concat([TCffBuilder.RealOperand([$E, $F]), TCffBuilder.Bytes([12, 2])])),
             'Invalid real number');
  // A real number of two dots
  CheckRaises(RawFont(TCffBuilder.Concat([TCffBuilder.RealOperand([1, $A, 2, $A, 3, $F]), TCffBuilder.Bytes([12, 2])])),
             'Invalid real number');
end;

procedure TCFFHostileInputTests.TestDictWithUnterminatedRealRaises;
begin
  // The real number has no $F nibble: the DICT ends inside it
  CheckRaises(RawFont(TCffBuilder.Concat([TCffBuilder.RealOperand([1, 2, 3, 4])])), 'End of CFF data');
end;

procedure TCFFHostileInputTests.TestDictRealNumberLengthIsBounded;
begin
  var Nibbles: TBytes;
  SetLength(Nibbles, 400);
  for var Index := 0 to High(Nibbles) do
  begin
    Nibbles[Index] := 1;
  end;
  Nibbles[High(Nibbles)] := $F;
  CheckRaises(RawFont(TCffBuilder.Concat([TCffBuilder.RealOperand(Nibbles), TCffBuilder.Bytes([12, 2])])), 'too long');
end;

procedure TCFFHostileInputTests.TestDictOperandStackIsBounded;
begin
  var Operands: TBytes;
  SetLength(Operands, 3000);
  for var Index := 0 to High(Operands) do
  begin
    Operands[Index] := $8B;
  end;
  CheckRaises(RawFont(TCffBuilder.Concat([Operands, TCffBuilder.Bytes([5])])), 'Too many operands');
end;

procedure TCFFHostileInputTests.TestDictWithInvalidByteRaises;
begin
  CheckRaises(RawFont(TCffBuilder.Bytes([$FF, 5])), 'invalid DICT');
  CheckRaises(RawFont(TCffBuilder.Bytes([22, 5])), 'invalid DICT');
  CheckRaises(RawFont(TCffBuilder.Bytes([31, 5])), 'invalid DICT');
end;

procedure TCFFHostileInputTests.TestSyntheticBaseRaises;
begin
  var Options := TCffType1Options.Standard;
  Options.ExtraTopDict := TCffBuilder.Concat([TCffBuilder.IntegerOperand(0), TCffBuilder.Bytes([12, 20])]);
  CheckRaises(TCffBuilder.Type1Font(Options), 'Synthetic');
end;

procedure TCFFHostileInputTests.TestCharsetBeyondDataRaises;
begin
  var Options := TCffType1Options.Standard;
  Options.GlyphCount := 65535;
  // Format 0 with room for one SID, where 65534 are needed
  Options.CharsetData := TCffBuilder.Bytes([0, 0, 1]);
  CheckRaises(TCffBuilder.Type1Font(Options));
end;

procedure TCFFHostileInputTests.TestCharsetOfUnknownFormatRaises;
begin
  var Options := TCffType1Options.Standard;
  Options.CharsetData := TCffBuilder.Bytes([7, 0, 1]);
  CheckRaises(TCffBuilder.Type1Font(Options));
end;

procedure TCFFHostileInputTests.TestCharsetRangeStopsAtTheGlyphCount;
begin
  const Stopwatch = TStopwatch.StartNew;
  // Three glyphs, and a format 2 range of 65536 glyphs, and a format 1 range of 256
  for var Format := 1 to 2 do
  begin
    var Options := TCffType1Options.Standard;
    if Format = 2 then
    begin
      Options.CharsetData := TCffBuilder.Bytes([2, 0, 1, $FF, $FF]);
    end
    else
    begin
      Options.CharsetData := TCffBuilder.Bytes([1, 0, 1, $FF]);
    end;
    TCFFParserTests.WithFont(TCffBuilder.Type1Font(Options),
      procedure(const Font: TCFFType1Font)
      begin
        Assert.AreEqual('space', Font.Charset.GetNameForGID(1));
        Assert.AreEqual('exclam', Font.Charset.GetNameForGID(2));
        var Name: string;
        Assert.IsFalse(Font.Charset.TryGetNameForGID(3, Name));
        Assert.IsFalse(Font.Charset.TryGetNameForGID(1000, Name));
        Assert.AreEqual(0, Font.Charset.GetGIDForSID(100));
      end);
  end;
  Assert.IsTrue(Stopwatch.ElapsedMilliseconds < MaximumHostileMilliseconds, 'Parsing took too long');
end;

procedure TCFFHostileInputTests.TestEncodingOfUnknownFormatRaises;
begin
  var Options := TCffType1Options.Standard;
  Options.EncodingData := TCffBuilder.Bytes([5, 0, 0]);
  CheckRaises(TCffBuilder.Type1Font(Options));
end;

procedure TCFFHostileInputTests.TestEncodingOffsetBeyondDataRaises;
begin
  var Options := TCffType1Options.Standard;
  // A format 0 encoding that claims 255 codes, at the very end of the data
  Options.EncodingData := TCffBuilder.Bytes([0, 255]);
  const Data = TCffBuilder.Type1Font(Options);
  CheckRaises(Copy(Data, 0, Length(Data) - 20));
end;

procedure TCFFHostileInputTests.TestTruncatedFontOnlyRaisesParseException;
begin
  var Options := TCffType1Options.Standard;
  Options.CharsetData := TCffBuilder.Bytes([1, 0, 1, 1]);
  Options.EncodingData := TCffBuilder.Bytes([1, 1, 65, 1]);
  Options.LocalSubrs := [TCffBuilder.Bytes([11])];
  const Data = TCffBuilder.Type1Font(Options);
  for var Size := 0 to Length(Data) - 1 do
  begin
    const Outcome = OutcomeOf(Copy(Data, 0, Size));
    Assert.IsTrue((Outcome = '') or (Outcome = EPdfParseException.ClassName), Format('%d bytes: %s', [Size, Outcome]));
  end;
end;

procedure TCFFHostileInputTests.TestTruncatedSourceSansOnlyRaisesParseException;
begin
  const Data = TTestFonts.Bytes('SourceSansProBold.otf');
  const Stopwatch = TStopwatch.StartNew;
  for var Step := 0 to 40 do
  begin
    const Outcome = OutcomeOf(Copy(Data, 0, Length(Data) * Step div 41));
    Assert.IsTrue((Outcome = '') or (Outcome = EPdfParseException.ClassName), Format('step %d: %s', [Step, Outcome]));
  end;
  Assert.IsTrue(Stopwatch.ElapsedMilliseconds < 10 * MaximumHostileMilliseconds, 'Parsing took too long');
end;

procedure TCFFHostileInputTests.TestChangedBytesNeverEndInAnotherException;
begin
  var Options := TCffType1Options.Standard;
  Options.CharsetData := TCffBuilder.Bytes([1, 0, 1, 1]);
  Options.EncodingData := TCffBuilder.Bytes([1, 1, 65, 1]);
  Options.LocalSubrs := [TCffBuilder.Bytes([11])];
  const Original = TCffBuilder.Type1Font(Options);

  const Stopwatch = TStopwatch.StartNew;
  for var Position := 0 to Length(Original) - 1 do
  begin
    for var Value in TCffBuilder.Bytes([0, 1, 4, $7F, $80, $FF]) do
    begin
      var Changed := Copy(Original);
      Changed[Position] := Value;
      const Outcome = OutcomeOf(Changed);
      const IsAccepted = ((Outcome = '') or (Outcome = EPdfParseException.ClassName) or
                          (Outcome = EPdfUnsupportedFeatureException.ClassName));
      Assert.IsTrue(IsAccepted, Format('byte %d set to %d: %s', [Position, Value, Outcome]));
    end;
  end;
  Assert.IsTrue(Stopwatch.ElapsedMilliseconds < 20 * MaximumHostileMilliseconds, 'Parsing took too long');
end;

end.
