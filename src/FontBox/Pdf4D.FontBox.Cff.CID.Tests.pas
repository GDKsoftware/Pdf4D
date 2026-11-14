// Copyright 2026 GDK Software
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
  Pdf4D.Tests.CffBuilder,
  Pdf4D.Tests.CffParseOutcome;

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

    [Test]
    procedure TestRangeCharsetLookupsMatchTheLinearSearch;

    [Test]
    procedure TestRangeCharsetOverlappingRangesKeepTheFirst;

    [Test]
    procedure TestFormat3FDSelectLookupsMatchTheLinearSearch;
  end;

  [TestFixture]
  TCFFCIDHostileInputTests = class
  private
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
    procedure TestFontDictsThatShareLocalSubrsShareTheIndex;

    [Test]
    procedure TestSharedPrivateDictOfManyOperandsRaisesOverBudget;

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

procedure TCFFCIDFontTests.TestRangeCharsetLookupsMatchTheLinearSearch;
begin
  // CIDs that are not in order, with gaps, and with ranges that overlap, as the ranges of a damaged font can
  const Starts: TArray<Integer> = [500, 10, 100, 300, 20];
  const Lefts: TArray<Integer> = [9, 4, 49, 0, 99];
  const Charset = TCFFRangeCharsetCID.Create;
  try
    Charset.AddCID(0, 0);
    var NextGID := 1;
    for var Index := 0 to High(Starts) do
    begin
      Charset.AddRangeMapping(NextGID, Starts[Index], Lefts[Index]);
      Inc(NextGID, Lefts[Index] + 1);
    end;
    Charset.Freeze;

    // PDFBox answers by the first range that holds the value
    for var CID := -2 to 700 do
    begin
      var ExpectedGID := 0;
      var First := 1;
      for var Index := 0 to High(Starts) do
      begin
        if (CID >= Starts[Index]) and (CID <= Starts[Index] + Lefts[Index]) then
        begin
          ExpectedGID := First + (CID - Starts[Index]);
          Break;
        end;
        Inc(First, Lefts[Index] + 1);
      end;
      Assert.AreEqual(ExpectedGID, Charset.GetGIDForCID(CID), Format('CID %d', [CID]));
    end;

    for var GID := -2 to NextGID + 5 do
    begin
      var ExpectedCID := 0;
      var First := 1;
      for var Index := 0 to High(Starts) do
      begin
        if (GID >= First) and (GID <= First + Lefts[Index]) then
        begin
          ExpectedCID := Starts[Index] + (GID - First);
          Break;
        end;
        Inc(First, Lefts[Index] + 1);
      end;
      Assert.AreEqual(ExpectedCID, Charset.GetCIDForGID(GID), Format('GID %d', [GID]));
    end;
  finally
    Charset.Free;
  end;
end;

procedure TCFFCIDFontTests.TestRangeCharsetOverlappingRangesKeepTheFirst;
begin
  const Charset = TCFFRangeCharsetCID.Create;
  try
    Charset.AddCID(0, 0);
    Charset.AddRangeMapping(1, 100, 9);
    Charset.AddRangeMapping(11, 105, 9);
    Charset.Freeze;
    // CID 107 is in both ranges; the first one maps it to GID 8
    Assert.AreEqual(8, Charset.GetGIDForCID(107));
    Assert.AreEqual(17, Charset.GetGIDForCID(111));
    Assert.AreEqual(0, Charset.GetGIDForCID(115));
  finally
    Charset.Free;
  end;
end;

function Format3Range(const First, FD: Integer): TCFFFormat3Range;
begin
  Result.First := First;
  Result.FD := FD;
end;

procedure TCFFCIDFontTests.TestFormat3FDSelectLookupsMatchTheLinearSearch;
begin
  const Sentinel = 60;
  // Sorted ranges use a binary search, ranges out of order keep the linear search of PDFBox; both give what that does
  for var IsSorted := False to True do
  begin
    var Ranges: TArray<TCFFFormat3Range>;
    if IsSorted then
    begin
      Ranges := [Format3Range(0, 0), Format3Range(10, 2), Format3Range(10, 3), Format3Range(40, 1)];
    end
    else
    begin
      Ranges := [Format3Range(20, 1), Format3Range(0, 0), Format3Range(40, 2)];
    end;
    const FDSelect = TCFFFormat3FDSelect.Create(Ranges, Sentinel);
    try
      for var GID := -3 to 70 do
      begin
        // PDFBox: the first range that starts at or before the glyph and whose successor starts after it
        var Expected := 0;
        for var Index := 0 to High(Ranges) do
        begin
          if Ranges[Index].First > GID then
          begin
            Continue;
          end;
          const IsLastRange = (Index + 1 = Length(Ranges));
          if IsLastRange then
          begin
            if Sentinel > GID then
            begin
              Expected := Ranges[Index].FD;
            end
            else
            begin
              Expected := -1;
            end;
            Break;
          end;
          if Ranges[Index + 1].First > GID then
          begin
            Expected := Ranges[Index].FD;
            Break;
          end;
        end;
        Assert.AreEqual(Expected, FDSelect.GetFDIndex(GID), Format('sorted %s, GID %d', [BoolToStr(IsSorted, True), GID]));
      end;
    finally
      FDSelect.Free;
    end;
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

procedure TCFFCIDHostileInputTests.TestMissingFDArrayRaises;
begin
  var Data := Options;
  Data.OmitFDArray := True;
  TCffParseOutcome.CheckRaises(TCffTestBuilder.CidFont(Data), 'FDArray');
end;

procedure TCFFCIDHostileInputTests.TestMissingFDSelectRaises;
begin
  var Data := Options;
  Data.OmitFDSelect := True;
  TCffParseOutcome.CheckRaises(TCffTestBuilder.CidFont(Data), 'FDSelect');
end;

procedure TCFFCIDHostileInputTests.TestFDSelectOfUnknownFormatRaises;
begin
  for var FormatNumber in [1, 2, 4, 255] do
  begin
    var Data := Options;
    Data.FDSelectData := TCffTestBuilder.Bytes([Byte(FormatNumber), 0, 0, 0, 0, 0]);
    TCffParseOutcome.CheckRaises(TCffTestBuilder.CidFont(Data), 'FDSelect format');
  end;
end;

procedure TCFFCIDHostileInputTests.TestFDSelectRangeCountBeyondDataRaises;
begin
  var Data := Options;
  // 65535 ranges of three bytes each in a font of a few hundred bytes
  Data.FDSelectData := TCffTestBuilder.Bytes([3, $FF, $FF, 0, 0, 0, 0, 3]);
  TCffParseOutcome.CheckRaises(TCffTestBuilder.CidFont(Data), 'FDSelect needs');
end;

procedure TCFFCIDHostileInputTests.TestFDArrayCountBeyondDataRaises;
begin
  var Data := Options;
  // An INDEX of 65535 entries with 4-byte offsets, and the data of a single one
  Data.FDArrayRaw := TCffTestBuilder.Bytes([$FF, $FF, 4, 0, 0, 0, 1, 0, 0, 0, 2, 0]);
  TCffParseOutcome.CheckRaises(TCffTestBuilder.CidFont(Data));
end;

procedure TCFFCIDHostileInputTests.TestMoreFontDictsThanFDSelectCanSelectRaise;
begin
  var Data := Options;
  Data.FontDictCount := 300;
  TCffParseOutcome.CheckRaises(TCffTestBuilder.CidFont(Data), 'font DICTs');
end;

procedure TCFFCIDHostileInputTests.TestNoPrivateDictAtAllRaises;
begin
  var Data := Options;
  Data.FontDictCount := 2;
  Data.FontDictsWithoutPrivate := 2;
  TCffParseOutcome.CheckRaises(TCffTestBuilder.CidFont(Data), 'Private');
end;

procedure TCFFCIDHostileInputTests.TestPrivateOffsetBeyondDataRaises;
begin
  var Data := Options;
  Data.FontDictBytes := [PrivateEntry(10, 1000000)];
  TCffParseOutcome.CheckRaises(TCffTestBuilder.CidFont(Data), 'out of range');
end;

procedure TCFFCIDHostileInputTests.TestPrivateOffsetAndSizeAtTheLimitOfAnIntegerRaise;
begin
  var Data := Options;
  // The sum of the offset and the size does not fit in 32 bits
  Data.FontDictBytes := [PrivateEntry(100, MaxInt - 5)];
  TCffParseOutcome.CheckRaises(TCffTestBuilder.CidFont(Data));

  Data.FontDictBytes := [PrivateEntry(MaxInt, MaxInt)];
  TCffParseOutcome.CheckRaises(TCffTestBuilder.CidFont(Data));

  Data.FontDictBytes := [PrivateEntry(MaxInt, 20)];
  TCffParseOutcome.CheckRaises(TCffTestBuilder.CidFont(Data));
end;

procedure TCFFCIDHostileInputTests.TestNegativePrivateOffsetRaises;
begin
  var Data := Options;
  Data.FontDictBytes := [PrivateEntry(10, -20)];
  TCffParseOutcome.CheckRaises(TCffTestBuilder.CidFont(Data), 'negative');
end;

procedure TCFFCIDHostileInputTests.TestPrivateSizeBeyondDataRaises;
begin
  var Data := Options;
  Data.FontDictBytes := [PrivateEntry(60000, 10)];
  TCffParseOutcome.CheckRaises(TCffTestBuilder.CidFont(Data));
end;

procedure TCFFCIDHostileInputTests.TestPrivateSizeBeyondTheLimitRaises;
begin
  var Data := Options;
  Data.FontDictBytes := [PrivateEntry(70000, 10)];
  TCffParseOutcome.CheckRaises(TCffTestBuilder.CidFont(Data), 'too large');
end;

// 256 font DICTs that share one private DICT and its 65535 empty subroutines (a font of about 130 KB) must not make 256
// copies of the INDEX, which would be about 128 MB
procedure TCFFCIDHostileInputTests.TestFontDictsThatShareLocalSubrsShareTheIndex;
begin
  var Data := Options;
  SetLength(Data.LocalSubrs, 65535);
  Data.FontDictCount := 256;
  const Font = TCffTestBuilder.CidFont(Data);

  const Stopwatch = TStopwatch.StartNew;
  const Parser = TCFFParser.Create;
  try
    const Fonts = Parser.Parse(Font);
    try
      const CidFont = TCFFCIDFont(Fonts[0]);
      Assert.AreEqual(256, Integer(CidFont.PrivDicts.Count));
      Assert.AreEqual(65535, Integer(Length(CidFont.PrivDicts[0].Subrs)));
      for var Index := 1 to CidFont.PrivDicts.Count - 1 do
      begin
        Assert.IsTrue(Pointer(CidFont.PrivDicts[0].Subrs) = Pointer(CidFont.PrivDicts[Index].Subrs),
                      Format('Font DICT %d has its own copy of the subroutines', [Index]));
      end;
    finally
      Fonts.Free;
    end;
  finally
    Parser.Free;
  end;
  Assert.IsTrue(Stopwatch.ElapsedMilliseconds < TCffParseOutcome.MaximumHostileMilliseconds, 'Parsing took too long');
end;

// A 50 KB private DICT of entries with 512 operands, read for each of 256 font DICTs, is far more work than the font holds
procedure TCFFCIDHostileInputTests.TestSharedPrivateDictOfManyOperandsRaisesOverBudget;
begin
  var Entry: TBytes;
  SetLength(Entry, 513);
  FillChar(Entry[0], 512, 139);
  Entry[512] := 20;
  var ExtraPrivateDict: TBytes;
  const EntryCount = 100;
  SetLength(ExtraPrivateDict, EntryCount * Length(Entry));
  for var Index := 0 to EntryCount - 1 do
  begin
    Move(Entry[0], ExtraPrivateDict[Index * Length(Entry)], Length(Entry));
  end;

  var Data := Options;
  Data.ExtraPrivateDict := ExtraPrivateDict;
  Data.FontDictCount := 256;
  TCffParseOutcome.CheckRaises(TCffTestBuilder.CidFont(Data), 'more work');
end;

procedure TCFFCIDHostileInputTests.TestRosWithTwoOperandsRaises;
begin
  var Data := Options;
  Data.RosData := TCffTestBuilder.Concat([TCffTestBuilder.IntegerOperand(391), TCffTestBuilder.IntegerOperand(392),
                                          TCffTestBuilder.Bytes([12, 30])]);
  TCffParseOutcome.CheckRaises(TCffTestBuilder.CidFont(Data), 'ROS');
end;

procedure TCFFCIDHostileInputTests.TestRosWithNegativeStringIndexRaises;
begin
  var Data := Options;
  Data.RosData := TCffTestBuilder.Concat([TCffTestBuilder.IntegerOperand(-1), TCffTestBuilder.IntegerOperand(392),
                                          TCffTestBuilder.IntegerOperand(0), TCffTestBuilder.Bytes([12, 30])]);
  TCffParseOutcome.CheckRaises(TCffTestBuilder.CidFont(Data), 'negative');
end;

procedure TCFFCIDHostileInputTests.TestCharsetOfUnknownFormatRaises;
begin
  var Data := Options;
  Data.CharsetData := TCffTestBuilder.Bytes([3, 0, 1]);
  TCffParseOutcome.CheckRaises(TCffTestBuilder.CidFont(Data), 'charset format');
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
    const Outcome = TCffParseOutcome.OutcomeOf(Copy(Font, 0, Size));
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
      const Outcome = TCffParseOutcome.OutcomeOf(Changed);
      Assert.IsTrue((Outcome = '') or (Outcome = EPdfParseException.ClassName),
                    Format('byte %d set to %d: %s', [Position, Value, Outcome]));
    end;
  end;
  Assert.IsTrue(Stopwatch.ElapsedMilliseconds < 20 * TCffParseOutcome.MaximumHostileMilliseconds, 'Parsing took too long');
end;

end.
