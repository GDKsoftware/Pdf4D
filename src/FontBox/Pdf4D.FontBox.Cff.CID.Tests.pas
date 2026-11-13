// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: the CID-keyed font parts of fontbox/src/test/java/org/apache/fontbox/cff/CFFParserTest.java (3.0.8), and tests of
// Pdf4D for the CID-keyed fonts of fontbox/src/main/java/org/apache/fontbox/cff/CFFParser.java (3.0.8)
unit Pdf4D.FontBox.Cff.CID.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Diagnostics,
  DUnitX.TestFramework,
  Pdf4D.FontBox.Cff.Font,
  Pdf4D.Tests.CffBuilder;

type
  TCidFontCheck = reference to procedure(const Font: TCFFCIDFont);

  [TestFixture]
  TCFFCIDFontTests = class
  private
    class procedure WithFont(const Data: TBytes; const Check: TCidFontCheck); overload; static;
    class procedure WithFont(const Data: TBytes; const Messages: TList<string>; const Check: TCidFontCheck); overload; static;
    class function Options(const CIDs: TArray<Integer>): TCffCidOptions; static;
    class function Rounded(const Value: Double): Integer; static;

  public
    [Test]
    procedure TestCidFontFromSyntheticCff;

    [Test]
    procedure TestGlyphsAndSelectors;

    [Test]
    procedure TestCharsetFormat0;

    [Test]
    procedure TestCharsetFormat1;

    [Test]
    procedure TestCharsetFormat2;

    [Test]
    procedure TestCharsetWithSeveralRanges;

    [Test]
    procedure TestCharsetRangeBeyondTheGlyphsIsKept;

    [Test]
    procedure TestMissingCharsetMapsCidToGid;

    [Test]
    procedure TestFdSelectFormat3;

    [Test]
    procedure TestFdSelectFormat0;

    [Test]
    procedure TestFdSelectOutOfRangeIsLenient;

    [Test]
    procedure TestFdSelectSentinelBeyondTheGlyphsIsLenient;

    [Test]
    procedure TestWidthsAndSubrsComeFromThePrivateDictOfTheGlyph;

    [Test]
    procedure TestFontDictWithoutPrivateKeepsTheIndexes;

    [Test]
    procedure TestFontMatrixFromTheFontDict;

    [Test]
    procedure TestFontMatrixIsCombinedWithTheTopDictMatrix;

    [Test]
    procedure TestRosStringsOutsideTheStringIndex;

    [Test]
    procedure TestParseFirstSubFontROS;

    [Test]
    procedure TestParseFirstSubFontROSOfTheWholeOpenTypeFile;

    [Test]
    procedure TestSourceSansIsNotCidKeyed;
  end;

  [TestFixture]
  TCFFCIDHostileInputTests = class
  private
    const MaximumHostileMilliseconds = 1000;

  private
    class function OutcomeOf(const Data: TBytes; out Message: string): string; overload; static;
    class function OutcomeOf(const Data: TBytes): string; overload; static;
    class procedure CheckRaises(const Data: TBytes; const MessageFragment: string = ''); static;
    class function Options: TCffCidOptions; static;
    class function PrivateEntry(const Size, Offset: Integer): TBytes; static;

  public
    [Test]
    procedure TestMissingFDArrayRaises;

    [Test]
    procedure TestMissingFDSelectRaises;

    [Test]
    procedure TestFDSelectOfUnknownFormatRaises;

    [Test]
    procedure TestFDSelectRangeCountBeyondDataRaises;

    [Test]
    procedure TestFDArrayCountBeyondDataRaises;

    [Test]
    procedure TestMoreFontDictsThanFDSelectCanSelectRaise;

    [Test]
    procedure TestNoPrivateDictAtAllRaises;

    [Test]
    procedure TestPrivateOffsetBeyondDataRaises;

    [Test]
    procedure TestPrivateOffsetAndSizeAtTheLimitOfAnIntegerRaise;

    [Test]
    procedure TestNegativePrivateOffsetRaises;

    [Test]
    procedure TestPrivateSizeBeyondDataRaises;

    [Test]
    procedure TestPrivateSizeBeyondTheLimitRaises;

    [Test]
    procedure TestLocalSubrsBeyondTheFontRaise;

    [Test]
    procedure TestRosWithTwoOperandsRaises;

    [Test]
    procedure TestRosWithNegativeStringIndexRaises;

    [Test]
    procedure TestCharsetOfUnknownFormatRaises;

    [Test]
    procedure TestTruncatedCidFontOnlyRaisesParseException;

    [Test]
    procedure TestChangedBytesNeverEndInAnotherException;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Common.Log,
  Pdf4D.FontBox.Cff.Charset,
  Pdf4D.FontBox.Cff.Parser,
  Pdf4D.Tests.TestFonts;

{ TCFFCIDFontTests }

class function TCFFCIDFontTests.Options(const CIDs: TArray<Integer>): TCffCidOptions;
begin
  Result := TCffCidOptions.Standard;
  Result.CIDs := CIDs;
  SetLength(Result.Widths, Length(CIDs));
  for var Index := 0 to High(CIDs) do
  begin
    Result.Widths[Index] := 500;
  end;
end;

class function TCFFCIDFontTests.Rounded(const Value: Double): Integer;
begin
  Result := Integer(Round(Value));
end;

class procedure TCFFCIDFontTests.WithFont(const Data: TBytes; const Check: TCidFontCheck);
begin
  WithFont(Data, nil, Check);
end;

class procedure TCFFCIDFontTests.WithFont(const Data: TBytes; const Messages: TList<string>; const Check: TCidFontCheck);
begin
  var Log: TPdfLog := nil;
  if Assigned(Messages) then
  begin
    Log := TPdfLog.Create(
      procedure(const Level: TPdfLogLevel; const Message: string)
      begin
        Messages.Add(Message);
      end);
  end;

  try
    const Parser = TCFFParser.Create(Log);
    try
      const Fonts = Parser.Parse(Data);
      try
        Assert.AreEqual(1, Integer(Fonts.Count));
        Assert.IsTrue(Fonts[0] is TCFFCIDFont);
        Check(TCFFCIDFont(Fonts[0]));
      finally
        Fonts.Free;
      end;
    finally
      Parser.Free;
    end;
  finally
    Log.Free;
  end;
end;

procedure TCFFCIDFontTests.TestCidFontFromSyntheticCff;
begin
  WithFont(TCffTestBuilder.CidKeyed('Adobe', 'Japan1', 6, [843, 844], [480, 520]),
    procedure(const Font: TCFFCIDFont)
    begin
      Assert.AreEqual('Adobe', Font.Registry);
      Assert.AreEqual('Japan1', Font.Ordering);
      Assert.AreEqual(6, Font.Supplement);
      Assert.AreEqual(1, Font.CIDToGID(843));
      Assert.AreEqual(2, Font.CIDToGID(844));
      Assert.AreEqual(0, Font.CIDToGID(9999));
    end);
end;

procedure TCFFCIDFontTests.TestGlyphsAndSelectors;
begin
  WithFont(TCffTestBuilder.CidKeyed('Adobe', 'Japan1', 6, [843, 844], [480, 520]),
    procedure(const Font: TCFFCIDFont)
    begin
      Assert.AreEqual('TestCID', Font.Name);
      Assert.IsTrue(Font.Charset.IsCIDFont);
      Assert.AreEqual(3, Integer(Length(Font.CharStrings)));
      Assert.AreEqual(843, Font.Charset.GetCIDForGID(1));
      Assert.AreEqual(0, Font.Charset.GetCIDForGID(77));
      Assert.IsTrue(Font.HasGlyph('\843'));
      Assert.IsFalse(Font.HasGlyph('\0'));
      Assert.IsTrue(Font.HasGlyph('\-5'));
      Assert.WillRaise(
        procedure
        begin
          Font.HasGlyph('A');
        end,
        EPdfParseException);
      Assert.WillRaise(
        procedure
        begin
          Font.HasGlyph('\12x');
        end,
        EPdfParseException);
      Assert.WillRaise(
        procedure
        begin
          Font.HasGlyph('\');
        end,
        EPdfParseException);
      Assert.WillRaise(
        procedure
        begin
          Font.HasGlyph('\99999999999');
        end,
        EPdfParseException);
      Assert.WillRaise(
        procedure
        begin
          Font.Charset.GetSIDForGID(1);
        end,
        EInvalidOpException);
    end);
end;

procedure TCFFCIDFontTests.TestCharsetFormat0;
begin
  var Data := Options([10, 20, 30]);
  WithFont(TCffTestBuilder.CidFont(Data),
    procedure(const Font: TCFFCIDFont)
    begin
      Assert.IsTrue(Font.Charset is TCFFCharsetCID);
      Assert.AreEqual(3, Font.CIDToGID(30));
      Assert.AreEqual(30, Font.Charset.GetCIDForGID(3));
      Assert.AreEqual(0, Font.CIDToGID(0));
    end);
end;

procedure TCFFCIDFontTests.TestCharsetFormat1;
begin
  var Data := Options([0, 0, 0]);
  // CIDs 100 to 102 for the glyphs 1 to 3: first 100, 2 more
  Data.CharsetData := TCffTestBuilder.Bytes([1, 0, 100, 2]);
  WithFont(TCffTestBuilder.CidFont(Data),
    procedure(const Font: TCFFCIDFont)
    begin
      Assert.IsTrue(Font.Charset is TCFFRangeCharsetCID);
      Assert.AreEqual(1, Font.CIDToGID(100));
      Assert.AreEqual(3, Font.CIDToGID(102));
      Assert.AreEqual(0, Font.CIDToGID(103));
      Assert.AreEqual(101, Font.Charset.GetCIDForGID(2));
    end);
end;

procedure TCFFCIDFontTests.TestCharsetFormat2;
begin
  var Data := Options([0, 0, 0]);
  Data.CharsetData := TCffTestBuilder.Bytes([2, 1, 0, 0, 2]);
  WithFont(TCffTestBuilder.CidFont(Data),
    procedure(const Font: TCFFCIDFont)
    begin
      Assert.AreEqual(1, Font.CIDToGID(256));
      Assert.AreEqual(3, Font.CIDToGID(258));
      Assert.AreEqual(0, Font.CIDToGID(259));
      Assert.AreEqual(257, Font.Charset.GetCIDForGID(2));
    end);
end;

procedure TCFFCIDFontTests.TestCharsetWithSeveralRanges;
begin
  var Data := Options([0, 0, 0, 0]);
  // glyph 1 is CID 10, the glyphs 2 to 4 are CIDs 50 to 52
  Data.CharsetData := TCffTestBuilder.Bytes([1, 0, 10, 0, 0, 50, 2]);
  WithFont(TCffTestBuilder.CidFont(Data),
    procedure(const Font: TCFFCIDFont)
    begin
      Assert.AreEqual(1, Font.CIDToGID(10));
      Assert.AreEqual(2, Font.CIDToGID(50));
      Assert.AreEqual(4, Font.CIDToGID(52));
      Assert.AreEqual(52, Font.Charset.GetCIDForGID(4));
    end);
end;

// A range can say more glyphs than the font has. PDFBox keeps that too: the lookup still works and no glyph is made for it.
procedure TCFFCIDFontTests.TestCharsetRangeBeyondTheGlyphsIsKept;
begin
  var Data := Options([0]);
  Data.CharsetData := TCffTestBuilder.Bytes([2, 0, 0, $FF, $FF]);
  WithFont(TCffTestBuilder.CidFont(Data),
    procedure(const Font: TCFFCIDFont)
    begin
      Assert.AreEqual(1, Font.CIDToGID(0));
      Assert.AreEqual(1001, Font.CIDToGID(1000));
      Assert.AreEqual(2, Integer(Length(Font.CharStrings)));
    end);
end;

procedure TCFFCIDFontTests.TestMissingCharsetMapsCidToGid;
begin
  var Data := Options([5, 6]);
  Data.OmitCharset := True;
  WithFont(TCffTestBuilder.CidFont(Data),
    procedure(const Font: TCFFCIDFont)
    begin
      Assert.AreEqual(1, Font.CIDToGID(1));
      Assert.AreEqual(2, Font.CIDToGID(2));
      // PDFBox maps one CID more than there are glyphs, because it counts .notdef too
      Assert.AreEqual(3, Font.CIDToGID(3));
      Assert.AreEqual(0, Font.CIDToGID(4));
      Assert.AreEqual(2, Font.Charset.GetCIDForGID(2));
    end);
end;

procedure TCFFCIDFontTests.TestFdSelectFormat3;
begin
  var Data := Options([1, 2, 3]);
  Data.FontDictCount := 2;
  // The glyphs 0 and 1 use font DICT 0, the glyphs 2 and 3 use font DICT 1, the sentinel is 4
  Data.FDSelectData := TCffTestBuilder.Bytes([3, 0, 2, 0, 0, 0, 0, 2, 1, 0, 4]);
  WithFont(TCffTestBuilder.CidFont(Data),
    procedure(const Font: TCFFCIDFont)
    begin
      Assert.IsTrue(Font.FdSelect is TCFFFormat3FDSelect);
      Assert.AreEqual(2, Integer(Font.FontDicts.Count));
      Assert.AreEqual(2, Integer(Font.PrivDicts.Count));
      Assert.AreEqual(0, Font.FdSelect.GetFDIndex(0));
      Assert.AreEqual(0, Font.FdSelect.GetFDIndex(1));
      Assert.AreEqual(1, Font.FdSelect.GetFDIndex(2));
      Assert.AreEqual(1, Font.FdSelect.GetFDIndex(3));
      // Past the sentinel
      Assert.AreEqual(-1, Font.FdSelect.GetFDIndex(4));
      Assert.AreEqual(1, Font.FdSelect.MaxFDIndex);
    end);
end;

procedure TCFFCIDFontTests.TestFdSelectFormat0;
begin
  var Data := Options([1, 2, 3]);
  Data.FontDictCount := 2;
  Data.FDSelectData := TCffTestBuilder.Bytes([0, 0, 1, 1, 0]);
  WithFont(TCffTestBuilder.CidFont(Data),
    procedure(const Font: TCFFCIDFont)
    begin
      Assert.IsTrue(Font.FdSelect is TCFFFormat0FDSelect);
      Assert.AreEqual(1, Font.FdSelect.GetFDIndex(1));
      Assert.AreEqual(1, Font.FdSelect.GetFDIndex(2));
      Assert.AreEqual(0, Font.FdSelect.GetFDIndex(3));
      // Beyond the table PDFBox answers 0
      Assert.AreEqual(0, Font.FdSelect.GetFDIndex(40));
      Assert.AreEqual(0, Font.FdSelect.GetFDIndex(-1));
      Assert.AreEqual(1, Font.FdSelect.MaxFDIndex);
    end);
end;

procedure TCFFCIDFontTests.TestFdSelectOutOfRangeIsLenient;
begin
  var Data := Options([1, 2]);
  Data.NominalWidthX := 100;
  Data.LocalSubrs := [TCffTestBuilder.Bytes([11])];
  // Glyph 1 selects font DICT 5, but the font has one
  Data.FDSelectData := TCffTestBuilder.Bytes([0, 0, 5, 0]);
  const Messages = TList<string>.Create;
  try
    WithFont(TCffTestBuilder.CidFont(Data), Messages,
      procedure(const Font: TCFFCIDFont)
      begin
        Assert.AreEqual(5, Font.FdSelect.GetFDIndex(1));
        Assert.AreEqual(1000, Font.GetDefaultWidthX(1));
        Assert.AreEqual(0, Font.GetNominalWidthX(1));
        Assert.AreEqual(0, Integer(Length(Font.GetLocalSubrs(1))));
        // The glyphs that select an existing font DICT keep its values
        Assert.AreEqual(100, Font.GetNominalWidthX(2));
        Assert.AreEqual(1, Integer(Length(Font.GetLocalSubrs(2))));
      end);

    Assert.AreEqual(1, Integer(Messages.Count));
    Assert.IsTrue(Messages[0].Contains('font DICT 5'), Messages[0]);
  finally
    Messages.Free;
  end;
end;

procedure TCFFCIDFontTests.TestFdSelectSentinelBeyondTheGlyphsIsLenient;
begin
  var Data := Options([1, 2]);
  // One range, with a sentinel of 65535 for a font of 3 glyphs
  Data.FDSelectData := TCffTestBuilder.Bytes([3, 0, 1, 0, 0, 0, $FF, $FF]);
  WithFont(TCffTestBuilder.CidFont(Data),
    procedure(const Font: TCFFCIDFont)
    begin
      Assert.AreEqual(0, Font.FdSelect.GetFDIndex(2));
      Assert.AreEqual(0, Font.FdSelect.GetFDIndex(65534));
      Assert.AreEqual(-1, Font.FdSelect.GetFDIndex(65535));
      Assert.AreEqual(1000, Font.GetDefaultWidthX(65535));
    end);
end;

procedure TCFFCIDFontTests.TestWidthsAndSubrsComeFromThePrivateDictOfTheGlyph;
begin
  var Data := Options([1, 2]);
  Data.DefaultWidthX := 700;
  Data.NominalWidthX := 300;
  Data.LocalSubrs := [TCffTestBuilder.Bytes([11]), TCffTestBuilder.Bytes([14])];
  WithFont(TCffTestBuilder.CidFont(Data),
    procedure(const Font: TCFFCIDFont)
    begin
      Assert.AreEqual(700, Font.GetDefaultWidthX(1));
      Assert.AreEqual(300, Font.GetNominalWidthX(1));
      Assert.AreEqual(2, Integer(Length(Font.GetLocalSubrs(1))));
      Assert.AreEqual<TBytes>(TCffTestBuilder.Bytes([14]), Font.GetLocalSubrs(1)[1]);
      Assert.AreEqual(300, Rounded(Font.PrivDicts[0].GetNumber('nominalWidthX', -1)));
    end);
end;

// PDFBOX-5843: a font DICT without a Private entry keeps its place, so the private DICT of the next one is still found
procedure TCFFCIDFontTests.TestFontDictWithoutPrivateKeepsTheIndexes;
begin
  var Data := Options([1, 2]);
  Data.FontDictCount := 2;
  Data.FontDictsWithoutPrivate := 1;
  Data.DefaultWidthX := 700;
  Data.FDSelectData := TCffTestBuilder.Bytes([0, 0, 0, 1]);
  WithFont(TCffTestBuilder.CidFont(Data),
    procedure(const Font: TCFFCIDFont)
    begin
      Assert.AreEqual(2, Integer(Font.PrivDicts.Count));
      Assert.AreEqual(1000, Font.GetDefaultWidthX(1));
      Assert.AreEqual(700, Font.GetDefaultWidthX(2));
    end);
end;

procedure TCFFCIDFontTests.TestFontMatrixFromTheFontDict;
begin
  var Data := Options([1]);
  Data.FontDictExtra := TCffTestBuilder.Concat([TCffTestBuilder.IntegerOperand(2), TCffTestBuilder.IntegerOperand(0),
                                                TCffTestBuilder.IntegerOperand(0), TCffTestBuilder.IntegerOperand(2),
                                                TCffTestBuilder.IntegerOperand(0), TCffTestBuilder.IntegerOperand(0),
                                                TCffTestBuilder.Bytes([12, 7])]);
  WithFont(TCffTestBuilder.CidFont(Data),
    procedure(const Font: TCFFCIDFont)
    begin
      const Matrix = Font.FontMatrix;
      Assert.AreEqual(6, Integer(Length(Matrix)));
      Assert.AreEqual(2, Rounded(Matrix[0]));
      Assert.AreEqual(2, Rounded(Matrix[3]));
    end);

  // Without a FontMatrix anywhere the default stays
  WithFont(TCffTestBuilder.CidKeyed('Adobe', 'Identity', 0, [1], [500]),
    procedure(const Font: TCFFCIDFont)
    begin
      Assert.AreEqual(1, Rounded(Font.FontMatrix[0] * 1000));
    end);
end;

// PDFBOX-3579. The second number of the result uses d1 where a matrix product has d2; PDFBox does the same.
procedure TCFFCIDFontTests.TestFontMatrixIsCombinedWithTheTopDictMatrix;
begin
  var Data := Options([1]);
  Data.ExtraTopDict := TCffTestBuilder.Concat([TCffTestBuilder.IntegerOperand(1), TCffTestBuilder.IntegerOperand(2),
                                               TCffTestBuilder.IntegerOperand(3), TCffTestBuilder.IntegerOperand(4),
                                               TCffTestBuilder.IntegerOperand(0), TCffTestBuilder.IntegerOperand(0),
                                               TCffTestBuilder.Bytes([12, 7])]);
  Data.FontDictExtra := TCffTestBuilder.Concat([TCffTestBuilder.IntegerOperand(5), TCffTestBuilder.IntegerOperand(6),
                                                TCffTestBuilder.IntegerOperand(7), TCffTestBuilder.IntegerOperand(8),
                                                TCffTestBuilder.IntegerOperand(0), TCffTestBuilder.IntegerOperand(0),
                                                TCffTestBuilder.Bytes([12, 7])]);
  WithFont(TCffTestBuilder.CidFont(Data),
    procedure(const Font: TCFFCIDFont)
    begin
      const Matrix = Font.FontMatrix;
      Assert.AreEqual(19, Rounded(Matrix[0]));
      Assert.AreEqual(14, Rounded(Matrix[1]));
      Assert.AreEqual(43, Rounded(Matrix[2]));
      Assert.AreEqual(50, Rounded(Matrix[3]));
      Assert.AreEqual(0, Rounded(Matrix[4]));
      Assert.AreEqual(0, Rounded(Matrix[5]));
    end);
end;

procedure TCFFCIDFontTests.TestRosStringsOutsideTheStringIndex;
begin
  var Data := Options([1]);
  // Registry SID 5000 and ordering SID 100000 are not in the String INDEX; supplement -7
  Data.RosData := TCffTestBuilder.Concat([TCffTestBuilder.IntegerOperand(5000), TCffTestBuilder.IntegerOperand(100000),
                                          TCffTestBuilder.IntegerOperand(-7), TCffTestBuilder.Bytes([12, 30])]);
  WithFont(TCffTestBuilder.CidFont(Data),
    procedure(const Font: TCFFCIDFont)
    begin
      Assert.AreEqual('SID5000', Font.Registry);
      Assert.AreEqual('SID100000', Font.Ordering);
      Assert.AreEqual(-7, Font.Supplement);
    end);

  // A standard string works as well: SID 1 is "space"
  Data.RosData := TCffTestBuilder.Concat([TCffTestBuilder.IntegerOperand(1), TCffTestBuilder.IntegerOperand(2),
                                          TCffTestBuilder.IntegerOperand(0), TCffTestBuilder.Bytes([12, 30])]);
  WithFont(TCffTestBuilder.CidFont(Data),
    procedure(const Font: TCFFCIDFont)
    begin
      Assert.AreEqual('space', Font.Registry);
      Assert.AreEqual('exclam', Font.Ordering);
    end);
end;

procedure TCFFCIDFontTests.TestParseFirstSubFontROS;
begin
  const Parser = TCFFParser.Create;
  try
    var Registry: string;
    var Ordering: string;
    var Supplement: Integer;
    const IsCid = Parser.ParseFirstSubFontROS(TCffTestBuilder.CidKeyed('Adobe', 'Japan1', 6, [843, 844], [480, 520]),
                                              Registry, Ordering, Supplement);
    Assert.IsTrue(IsCid);
    Assert.AreEqual('Adobe', Registry);
    Assert.AreEqual('Japan1', Ordering);
    Assert.AreEqual(6, Supplement);

    const IsType1 = Parser.ParseFirstSubFontROS(TCffTestBuilder.Type1Font(TCffType1Options.Standard), Registry, Ordering,
                                                Supplement);
    Assert.IsFalse(IsType1);
    Assert.AreEqual('', Registry);
    Assert.AreEqual('', Ordering);
    Assert.AreEqual(0, Supplement);
  finally
    Parser.Free;
  end;
end;

procedure TCFFCIDFontTests.TestParseFirstSubFontROSOfTheWholeOpenTypeFile;
begin
  const Parser = TCFFParser.Create;
  try
    var Registry: string;
    var Ordering: string;
    var Supplement: Integer;
    Assert.IsFalse(Parser.ParseFirstSubFontROS(TTestFonts.Bytes('SourceSansProBold.otf'), Registry, Ordering, Supplement));
    Assert.IsFalse(Parser.ParseFirstSubFontROS(TTestFonts.Bytes('FoglihtenNo07.otf'), Registry, Ordering, Supplement));

    Assert.WillRaise(
      procedure
      begin
        var Name: string;
        var Kind: string;
        var Level: Integer;
        Parser.ParseFirstSubFontROS(TCffTestBuilder.Bytes([1, 0, 4, 4, 0, 1]), Name, Kind, Level);
      end,
      EPdfParseException);
  finally
    Parser.Free;
  end;
end;

procedure TCFFCIDFontTests.TestSourceSansIsNotCidKeyed;
begin
  const Parser = TCFFParser.Create;
  try
    const Fonts = Parser.Parse(TTestFonts.Bytes('SourceSansProBold.otf'));
    try
      Assert.IsTrue(Fonts[0] is TCFFType1Font);
    finally
      Fonts.Free;
    end;
  finally
    Parser.Free;
  end;
end;

{ TCFFCIDHostileInputTests }

class function TCFFCIDHostileInputTests.Options: TCffCidOptions;
begin
  Result := TCffCidOptions.Standard;
  Result.CIDs := [1, 2];
  Result.Widths := [500, 600];
end;

class function TCFFCIDHostileInputTests.PrivateEntry(const Size, Offset: Integer): TBytes;
begin
  Result := TCffTestBuilder.Concat([TCffTestBuilder.IntegerOperand(Size), TCffTestBuilder.IntegerOperand(Offset),
                                    TCffTestBuilder.Bytes([18])]);
end;

class function TCFFCIDHostileInputTests.OutcomeOf(const Data: TBytes; out Message: string): string;
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

class function TCFFCIDHostileInputTests.OutcomeOf(const Data: TBytes): string;
begin
  var Message: string;
  Result := OutcomeOf(Data, Message);
end;

class procedure TCFFCIDHostileInputTests.CheckRaises(const Data: TBytes; const MessageFragment: string);
begin
  const Stopwatch = TStopwatch.StartNew;
  var Message: string;
  const Outcome = OutcomeOf(Data, Message);
  Assert.AreEqual(EPdfParseException.ClassName, Outcome);
  Assert.IsTrue((MessageFragment = '') or Message.Contains(MessageFragment),
                Format('Message "%s" does not contain "%s"', [Message, MessageFragment]));
  Assert.IsTrue(Stopwatch.ElapsedMilliseconds < MaximumHostileMilliseconds, 'Parsing took too long');
end;

procedure TCFFCIDHostileInputTests.TestMissingFDArrayRaises;
begin
  var Data := Options;
  Data.OmitFDArray := True;
  CheckRaises(TCffTestBuilder.CidFont(Data), 'FDArray');
end;

procedure TCFFCIDHostileInputTests.TestMissingFDSelectRaises;
begin
  var Data := Options;
  Data.OmitFDSelect := True;
  CheckRaises(TCffTestBuilder.CidFont(Data), 'FDSelect');
end;

procedure TCFFCIDHostileInputTests.TestFDSelectOfUnknownFormatRaises;
begin
  for var FormatNumber in [1, 2, 4, 255] do
  begin
    var Data := Options;
    Data.FDSelectData := TCffTestBuilder.Bytes([Byte(FormatNumber), 0, 0, 0, 0, 0]);
    CheckRaises(TCffTestBuilder.CidFont(Data), 'FDSelect format');
  end;
end;

procedure TCFFCIDHostileInputTests.TestFDSelectRangeCountBeyondDataRaises;
begin
  var Data := Options;
  // 65535 ranges of three bytes each in a font of a few hundred bytes
  Data.FDSelectData := TCffTestBuilder.Bytes([3, $FF, $FF, 0, 0, 0, 0, 3]);
  CheckRaises(TCffTestBuilder.CidFont(Data), 'FDSelect needs');
end;

procedure TCFFCIDHostileInputTests.TestFDArrayCountBeyondDataRaises;
begin
  var Data := Options;
  // An INDEX of 65535 entries with 4-byte offsets, and the data of a single one
  Data.FDArrayRaw := TCffTestBuilder.Bytes([$FF, $FF, 4, 0, 0, 0, 1, 0, 0, 0, 2, 0]);
  CheckRaises(TCffTestBuilder.CidFont(Data));
end;

procedure TCFFCIDHostileInputTests.TestMoreFontDictsThanFDSelectCanSelectRaise;
begin
  var Data := Options;
  Data.FontDictCount := 300;
  CheckRaises(TCffTestBuilder.CidFont(Data), 'font DICTs');
end;

procedure TCFFCIDHostileInputTests.TestNoPrivateDictAtAllRaises;
begin
  var Data := Options;
  Data.FontDictCount := 2;
  Data.FontDictsWithoutPrivate := 2;
  CheckRaises(TCffTestBuilder.CidFont(Data), 'Private');
end;

procedure TCFFCIDHostileInputTests.TestPrivateOffsetBeyondDataRaises;
begin
  var Data := Options;
  Data.FontDictBytes := [PrivateEntry(10, 1000000)];
  CheckRaises(TCffTestBuilder.CidFont(Data), 'out of range');
end;

procedure TCFFCIDHostileInputTests.TestPrivateOffsetAndSizeAtTheLimitOfAnIntegerRaise;
begin
  var Data := Options;
  // The sum of the offset and the size does not fit in 32 bits
  Data.FontDictBytes := [PrivateEntry(100, MaxInt - 5)];
  CheckRaises(TCffTestBuilder.CidFont(Data));

  Data.FontDictBytes := [PrivateEntry(MaxInt, MaxInt)];
  CheckRaises(TCffTestBuilder.CidFont(Data));

  Data.FontDictBytes := [PrivateEntry(MaxInt, 20)];
  CheckRaises(TCffTestBuilder.CidFont(Data));
end;

procedure TCFFCIDHostileInputTests.TestNegativePrivateOffsetRaises;
begin
  var Data := Options;
  Data.FontDictBytes := [PrivateEntry(10, -20)];
  CheckRaises(TCffTestBuilder.CidFont(Data), 'negative');
end;

procedure TCFFCIDHostileInputTests.TestPrivateSizeBeyondDataRaises;
begin
  var Data := Options;
  Data.FontDictBytes := [PrivateEntry(60000, 10)];
  CheckRaises(TCffTestBuilder.CidFont(Data));
end;

procedure TCFFCIDHostileInputTests.TestPrivateSizeBeyondTheLimitRaises;
begin
  var Data := Options;
  Data.FontDictBytes := [PrivateEntry(70000, 10)];
  CheckRaises(TCffTestBuilder.CidFont(Data), 'too large');
end;

// Font DICTs that share one private DICT would each copy the same local subroutines
procedure TCFFCIDHostileInputTests.TestLocalSubrsBeyondTheFontRaise;
begin
  var Data := Options;
  var Subr: TBytes;
  SetLength(Subr, 60);
  FillChar(Subr[0], Length(Subr), 11);
  Data.LocalSubrs := [Subr];
  Data.FontDictCount := 1;
  Assert.AreEqual(EmptyStr, OutcomeOf(TCffTestBuilder.CidFont(Data)));

  Data.FontDictCount := 40;
  CheckRaises(TCffTestBuilder.CidFont(Data), 'larger than the font');
end;

procedure TCFFCIDHostileInputTests.TestRosWithTwoOperandsRaises;
begin
  var Data := Options;
  Data.RosData := TCffTestBuilder.Concat([TCffTestBuilder.IntegerOperand(391), TCffTestBuilder.IntegerOperand(392),
                                          TCffTestBuilder.Bytes([12, 30])]);
  CheckRaises(TCffTestBuilder.CidFont(Data), 'ROS');
end;

procedure TCFFCIDHostileInputTests.TestRosWithNegativeStringIndexRaises;
begin
  var Data := Options;
  Data.RosData := TCffTestBuilder.Concat([TCffTestBuilder.IntegerOperand(-1), TCffTestBuilder.IntegerOperand(392),
                                          TCffTestBuilder.IntegerOperand(0), TCffTestBuilder.Bytes([12, 30])]);
  CheckRaises(TCffTestBuilder.CidFont(Data), 'negative');
end;

procedure TCFFCIDHostileInputTests.TestCharsetOfUnknownFormatRaises;
begin
  var Data := Options;
  Data.CharsetData := TCffTestBuilder.Bytes([3, 0, 1]);
  CheckRaises(TCffTestBuilder.CidFont(Data), 'charset format');
end;

procedure TCFFCIDHostileInputTests.TestTruncatedCidFontOnlyRaisesParseException;
begin
  var Data := Options;
  Data.FontDictCount := 2;
  Data.LocalSubrs := [TCffTestBuilder.Bytes([11])];
  Data.CharsetData := TCffTestBuilder.Bytes([1, 0, 1, 1]);
  const Font = TCffTestBuilder.CidFont(Data);
  for var Size := 0 to Length(Font) - 1 do
  begin
    const Outcome = OutcomeOf(Copy(Font, 0, Size));
    Assert.IsTrue((Outcome = '') or (Outcome = EPdfParseException.ClassName), Format('%d bytes: %s', [Size, Outcome]));
  end;
end;

procedure TCFFCIDHostileInputTests.TestChangedBytesNeverEndInAnotherException;
begin
  var Data := Options;
  Data.FontDictCount := 2;
  Data.LocalSubrs := [TCffTestBuilder.Bytes([11])];
  Data.CharsetData := TCffTestBuilder.Bytes([1, 0, 1, 1]);
  Data.FDSelectData := TCffTestBuilder.Bytes([3, 0, 2, 0, 0, 0, 0, 2, 1, 0, 3]);
  const Original = TCffTestBuilder.CidFont(Data);

  const Stopwatch = TStopwatch.StartNew;
  for var Position := 0 to Length(Original) - 1 do
  begin
    for var Value in TCffTestBuilder.Bytes([0, 1, 3, $7F, $80, $FF]) do
    begin
      var Changed := Copy(Original);
      Changed[Position] := Value;
      const Outcome = OutcomeOf(Changed);
      Assert.IsTrue((Outcome = '') or (Outcome = EPdfParseException.ClassName),
                    Format('byte %d set to %d: %s', [Position, Value, Outcome]));
    end;
  end;
  Assert.IsTrue(Stopwatch.ElapsedMilliseconds < 20 * MaximumHostileMilliseconds, 'Parsing took too long');
end;

end.
