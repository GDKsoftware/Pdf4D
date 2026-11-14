// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/test/java/org/apache/fontbox/ttf/TestTTFParser.java (3.0.8)
// Port of: fontbox/src/test/java/org/apache/fontbox/ttf/TestCMapSubtable.java (3.0.8)
unit Pdf4D.FontBox.TrueType.Cmap.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.FontBox.TrueType.Cmap,
  Pdf4D.Tests.TrueTypeBuilder;

type
  TCmapSubtableSpec = record
    PlatformId: Integer;
    EncodingId: Integer;
    Bytes: TBytes;
  end;

  TCmapSegmentSpec = record
    FirstCode: Integer;
    LastCode: Integer;
    IdDelta: Integer;
    IdRangeOffset: Integer;
  end;

  TCmapGroupSpec = record
    FirstCode: Int64;
    LastCode: Int64;
    GlyphId: Int64;
  end;

  [TestFixture]
  TTrueTypeCmapTests = class
  private
    const LiberationSans = 'LiberationSans-Regular.ttf';
    const GlyphCount = 20;
    const MaximumHostileMilliseconds = 2000;

  private
    class function Segment(const FirstCode, LastCode, IdDelta, IdRangeOffset: Integer): TCmapSegmentSpec; static;
    class function Group(const FirstCode, LastCode, GlyphId: Int64): TCmapGroupSpec; static;
    class function DeltaFor(const Code, GlyphId: Integer): Integer; static;
    class function Spec(const PlatformId, EncodingId: Integer; const Bytes: TBytes): TCmapSubtableSpec; static;
    class function BuildCmapTable(const Specs: array of TCmapSubtableSpec): TBytes; static;

    class function Format0(const Code, GlyphId: Integer): TBytes; static;
    class function Format2(const FirstCode: Integer; const Glyphs: array of Integer): TBytes; static;
    class function Format4(const Segments: array of TCmapSegmentSpec; const GlyphArray: array of Integer): TBytes; static;
    class function Format6(const FirstCode: Integer; const Glyphs: array of Integer): TBytes; static;
    class function Format8(const Groups: array of TCmapGroupSpec; const DeclaredGroupCount: Int64): TBytes; static;
    class function Format10(const StartCode, NumChars: Int64): TBytes; static;
    class function Format12Or13(const Format: Integer; const Groups: array of TCmapGroupSpec; const DeclaredGroupCount: Int64): TBytes; static;
    class function Format14: TBytes; static;
    class function FormatWithOnlyHeader(const Format: Integer): TBytes; static;

    class function SubtableForFormat(const Format: Integer): TBytes; static;
    class procedure CheckEqual(const Expected, Actual: Integer; const Message: string = ''); static;
    class procedure CheckCodes(const Expected: array of Integer; const Actual: TArray<Integer>); static;
    class procedure ReadCmapTable(const Host: TTestTableHost; const Bytes: TBytes); static;
    class function LoadCmap(const Host: TTestTableHost; const Bytes: TBytes): TCmapTable; static;
    class function ParseFailureWithCmap(const CmapBytes: TBytes): string; static;
    class function RecordsOnOneSubtable(const Subtable: TBytes; const RecordTotal: Integer): TBytes; static;
    class function CountSubtablesWithGlyph(const Cmap: TCmapTable; const GlyphId: Integer): Integer; static;

  public
    [Test]
    procedure TestPostTable;

    [Test]
    procedure TestSpaceAndA;

    [Test]
    procedure TestNameToGID;

    [Test]
    procedure TestNameToGIDRejectsMalformedNames;

    [Test]
    procedure TestWidthAndHasGlyphByName;

    [Test]
    procedure TestUnicodeCmapLookupOrder;

    [Test]
    procedure TestFontWithoutUnicodeCmapFailsStrictAndFallsBackLeniently;

    [Test]
    [TestCase('Format 0', '0')]
    [TestCase('Format 2', '2')]
    [TestCase('Format 4', '4')]
    [TestCase('Format 6', '6')]
    [TestCase('Format 8', '8')]
    [TestCase('Format 12', '12')]
    [TestCase('Format 13', '13')]
    procedure TestSubtableMapsKnownCharacter(const Format: Integer);

    [Test]
    procedure TestCharCodesOfGlyphWithSeveralCodesAreSorted;

    [Test]
    procedure TestFormat4WithSegCountZeroIsLenient;

    [Test]
    procedure TestFormat4WithBadSegmentsIsLenient;

    [Test]
    procedure TestFormat4OverlappingSegmentsLastOneWins;

    [Test]
    procedure TestFormat4ReadsGlyphArrayThroughRangeOffset;

    [Test]
    procedure TestFormat4RangeOffsetBeyondDataRaises;

    [Test]
    procedure TestFormat10IsValidatedAndMapsNothing;

    [Test]
    procedure TestFormat10WithInvalidCodesRaises;

    [Test]
    procedure TestFormat14IsIgnoredWithWarning;

    [Test]
    procedure TestUnknownFormatRaises;

    [Test]
    procedure TestFormat12GlyphBeyondNumGlyphsIsCutShort;

    [Test]
    procedure TestFormat12SurrogateCodeRaises;

    [Test]
    procedure TestFormat12GroupCountOf2To32Raises;

    [Test]
    procedure TestFormat13GlyphEqualToNumGlyphsEndsTheTable;

    [Test]
    procedure TestFormat8GroupCountTooLargeRaises;

    [Test]
    procedure TestFormat8CodeBeyondFlagArrayRaises;

    [Test]
    procedure TestFormat8GlyphEqualToNumGlyphsRaises;

    [Test]
    procedure TestFormat2SubheaderIndexBeyondDataRaises;

    [Test]
    procedure TestFormat2GlyphArrayBeyondDataRaises;

    [Test]
    procedure TestSubtableCountBeyondDataRaises;

    [Test]
    procedure TestOverlappingGroupsStopAtTheWorkLimit;

    [Test]
    procedure TestManySubtablesOnTheSameDataStopAtTheWorkLimit;

    [Test]
    procedure TestManyRecordsOnOneEmptyFormat13SubtableAllocateLittle;

    [Test]
    procedure TestManyRecordsOnOneFormat4SubtableAreChargedForTheLookup;

    [Test]
    procedure TestRecordsOnOneSubtableShareItsMappings;

    [Test]
    procedure TestBudgetThatRunsOutKeepsBothDirectionsConsistent;

    [Test]
    procedure TestHostileFormat12InFontEndsInParseError;

    [Test]
    procedure TestSubtableWithoutDataHasNoGlyphs;
  end;

implementation

uses
  System.Diagnostics,
  System.Classes,
  Pdf4D.Common.Defines,
  Pdf4D.Common.Log,
  Pdf4D.FontBox.TrueType.DataStream,
  Pdf4D.FontBox.TrueType.Font,
  Pdf4D.FontBox.TrueType.Parser,
  Pdf4D.FontBox.TrueType.Post,
  Pdf4D.Tests.TestFonts;

{ TTrueTypeCmapTests }

class function TTrueTypeCmapTests.Segment(const FirstCode, LastCode, IdDelta, IdRangeOffset: Integer): TCmapSegmentSpec;
begin
  Result.FirstCode := FirstCode;
  Result.LastCode := LastCode;
  Result.IdDelta := IdDelta;
  Result.IdRangeOffset := IdRangeOffset;
end;

class function TTrueTypeCmapTests.Group(const FirstCode, LastCode, GlyphId: Int64): TCmapGroupSpec;
begin
  Result.FirstCode := FirstCode;
  Result.LastCode := LastCode;
  Result.GlyphId := GlyphId;
end;

class function TTrueTypeCmapTests.DeltaFor(const Code, GlyphId: Integer): Integer;
begin
  Result := (GlyphId - Code) and $FFFF;
end;

class function TTrueTypeCmapTests.Spec(const PlatformId, EncodingId: Integer; const Bytes: TBytes): TCmapSubtableSpec;
begin
  Result.PlatformId := PlatformId;
  Result.EncodingId := EncodingId;
  Result.Bytes := Bytes;
end;

class function TTrueTypeCmapTests.BuildCmapTable(const Specs: array of TCmapSubtableSpec): TBytes;
begin
  const Writer = TTestByteWriter.Create;
  try
    Writer.U16(0);
    Writer.U16(Length(Specs));
    var Offset := 4 + (8 * Length(Specs));
    for var Entry in Specs do
    begin
      Writer.U16(Entry.PlatformId);
      Writer.U16(Entry.EncodingId);
      Writer.U32(Offset);
      Inc(Offset, Length(Entry.Bytes));
    end;
    for var Entry in Specs do
    begin
      Writer.Append(Entry.Bytes);
    end;
    Result := Writer.ToBytes;
  finally
    Writer.Free;
  end;
end;

class function TTrueTypeCmapTests.Format0(const Code, GlyphId: Integer): TBytes;
begin
  const Writer = TTestByteWriter.Create;
  try
    Writer.U16(0);
    Writer.U16(262);
    Writer.U16(0);
    for var Index := 0 to 255 do
    begin
      if Index = Code then
      begin
        Writer.U8(GlyphId);
      end
      else
      begin
        Writer.U8(0);
      end;
    end;
    Result := Writer.ToBytes;
  finally
    Writer.Free;
  end;
end;

class function TTrueTypeCmapTests.Format2(const FirstCode: Integer; const Glyphs: array of Integer): TBytes;
begin
  const Writer = TTestByteWriter.Create;
  try
    Writer.U16(2);
    Writer.U16(0);
    Writer.U16(0);
    for var Key := 0 to 255 do
    begin
      Writer.U16(0);
    end;
    // One subheader whose glyph array follows it directly
    Writer.U16(FirstCode);
    Writer.U16(Length(Glyphs));
    Writer.U16(0);
    Writer.U16(2);
    for var GlyphId in Glyphs do
    begin
      Writer.U16(GlyphId);
    end;
    Result := Writer.ToBytes;
  finally
    Writer.Free;
  end;
end;

class function TTrueTypeCmapTests.Format4(const Segments: array of TCmapSegmentSpec; const GlyphArray: array of Integer): TBytes;
begin
  const Writer = TTestByteWriter.Create;
  try
    Writer.U16(4);
    Writer.U16(16 + (8 * Length(Segments)) + (2 * Length(GlyphArray)));
    Writer.U16(0);
    Writer.U16(2 * Length(Segments));
    Writer.U16(0);
    Writer.U16(0);
    Writer.U16(0);
    for var Entry in Segments do
    begin
      Writer.U16(Entry.LastCode);
    end;
    Writer.U16(0);
    for var Entry in Segments do
    begin
      Writer.U16(Entry.FirstCode);
    end;
    for var Entry in Segments do
    begin
      Writer.U16(Entry.IdDelta);
    end;
    for var Entry in Segments do
    begin
      Writer.U16(Entry.IdRangeOffset);
    end;
    for var GlyphId in GlyphArray do
    begin
      Writer.U16(GlyphId);
    end;
    Result := Writer.ToBytes;
  finally
    Writer.Free;
  end;
end;

class function TTrueTypeCmapTests.Format6(const FirstCode: Integer; const Glyphs: array of Integer): TBytes;
begin
  const Writer = TTestByteWriter.Create;
  try
    Writer.U16(6);
    Writer.U16(10 + (2 * Length(Glyphs)));
    Writer.U16(0);
    Writer.U16(FirstCode);
    Writer.U16(Length(Glyphs));
    for var GlyphId in Glyphs do
    begin
      Writer.U16(GlyphId);
    end;
    Result := Writer.ToBytes;
  finally
    Writer.Free;
  end;
end;

class function TTrueTypeCmapTests.Format8(const Groups: array of TCmapGroupSpec; const DeclaredGroupCount: Int64): TBytes;
begin
  const Writer = TTestByteWriter.Create;
  try
    Writer.U16(8);
    Writer.U16(0);
    Writer.U32(0);
    Writer.U32(0);
    Writer.Zeros(8192);
    Writer.U32(DeclaredGroupCount);
    for var Entry in Groups do
    begin
      Writer.U32(Entry.FirstCode);
      Writer.U32(Entry.LastCode);
      Writer.U32(Entry.GlyphId);
    end;
    Result := Writer.ToBytes;
  finally
    Writer.Free;
  end;
end;

class function TTrueTypeCmapTests.Format10(const StartCode, NumChars: Int64): TBytes;
begin
  const Writer = TTestByteWriter.Create;
  try
    Writer.U16(10);
    Writer.U16(0);
    Writer.U32(0);
    Writer.U32(0);
    Writer.U32(StartCode);
    Writer.U32(NumChars);
    Result := Writer.ToBytes;
  finally
    Writer.Free;
  end;
end;

class function TTrueTypeCmapTests.Format12Or13(const Format: Integer; const Groups: array of TCmapGroupSpec; const DeclaredGroupCount: Int64): TBytes;
begin
  const Writer = TTestByteWriter.Create;
  try
    Writer.U16(Format);
    Writer.U16(0);
    Writer.U32(16 + (12 * Length(Groups)));
    Writer.U32(0);
    Writer.U32(DeclaredGroupCount);
    for var Entry in Groups do
    begin
      Writer.U32(Entry.FirstCode);
      Writer.U32(Entry.LastCode);
      Writer.U32(Entry.GlyphId);
    end;
    Result := Writer.ToBytes;
  finally
    Writer.Free;
  end;
end;

class function TTrueTypeCmapTests.Format14: TBytes;
begin
  const Writer = TTestByteWriter.Create;
  try
    Writer.U16(14);
    Writer.U16(0);
    Writer.U32(10);
    Writer.U32(0);
    Writer.U32(0);
    Result := Writer.ToBytes;
  finally
    Writer.Free;
  end;
end;

class function TTrueTypeCmapTests.FormatWithOnlyHeader(const Format: Integer): TBytes;
begin
  const Writer = TTestByteWriter.Create;
  try
    Writer.U16(Format);
    Writer.U16(0);
    Writer.U16(0);
    Result := Writer.ToBytes;
  finally
    Writer.Free;
  end;
end;

class function TTrueTypeCmapTests.SubtableForFormat(const Format: Integer): TBytes;
begin
  case Format of
    0 : Result := Format0($41, 5);
    2 : Result := Format2($41, [5, 6]);
    4 : Result := Format4([Segment($41, $43, DeltaFor($41, 5), 0), Segment($FFFF, $FFFF, 1, 0)], []);
    6 : Result := Format6($41, [5, 6, 7]);
    8 : Result := Format8([Group($41, $43, 5)], 1);
    12: Result := Format12Or13(12, [Group($41, $43, 5)], 1);
    13: Result := Format12Or13(13, [Group($41, $41, 5)], 1);
  else
    raise EArgumentException.CreateFmt('Test has no subtable for format %d', [Format]);
  end;
end;

class procedure TTrueTypeCmapTests.CheckEqual(const Expected, Actual: Integer; const Message: string);
begin
  Assert.AreEqual<Integer>(Expected, Actual, Message);
end;

class procedure TTrueTypeCmapTests.CheckCodes(const Expected: array of Integer; const Actual: TArray<Integer>);
begin
  CheckEqual(Length(Expected), Length(Actual));
  for var Index := 0 to High(Expected) do
  begin
    CheckEqual(Expected[Index], Actual[Index]);
  end;
end;

class procedure TTrueTypeCmapTests.ReadCmapTable(const Host: TTestTableHost; const Bytes: TBytes);
begin
  LoadCmap(Host, Bytes);
end;

class function TTrueTypeCmapTests.LoadCmap(const Host: TTestTableHost; const Bytes: TBytes): TCmapTable;
begin
  Result := TCmapTable.Create(TCmapTable.TableTag, 0, 0, Length(Bytes));
  Host.AddTable(Result);
  const Stream = TTTFMemoryDataStream.Create(Bytes);
  try
    Result.Read(Host, Stream);
  finally
    Stream.Free;
  end;
end;

// The cmap bytes go into LiberationSans in place of its own cmap table, which they have to fit in
class function TTrueTypeCmapTests.ParseFailureWithCmap(const CmapBytes: TBytes): string;
begin
  Result := '';
  const Data = TTestFonts.Bytes(LiberationSans);
  TTrueTypeTestData.ReplaceTable(Data, TCmapTable.TableTag, TCmapTable.TableTag, CmapBytes);

  const Parser = TTTFParser.Create;
  try
    const Stopwatch = TStopwatch.StartNew;
    try
      Parser.Parse(Data).Free;
    except
      on Failure: Exception do
      begin
        Result := Failure.ClassName;
      end;
    end;
    Assert.IsTrue(Stopwatch.ElapsedMilliseconds < MaximumHostileMilliseconds, 'Parsing took too long');
  finally
    Parser.Free;
  end;
end;

procedure TTrueTypeCmapTests.TestPostTable;
begin
  const Parser = TTTFParser.Create;
  try
    const Font = Parser.Parse(TTestFonts.Bytes(LiberationSans));
    try
      var Cmap: TCmapTable;
      Assert.IsTrue(Font.TryGetCmap(Cmap));
      var Subtable: TCmapSubtable;
      Assert.IsTrue(Cmap.TryGetSubtable(TCmapTable.PlatformWindows, TCmapTable.EncodingWinUnicodeBmp, Subtable));
      var PostScript: TPostScriptTable;
      Assert.IsTrue(Font.TryGetPostScript(PostScript));

      var TrademarkName: string;
      var EuroName: string;
      Assert.IsTrue(PostScript.TryGetName(Subtable.GetGlyphId($2122), TrademarkName));
      Assert.IsTrue(PostScript.TryGetName(Subtable.GetGlyphId($20AC), EuroName));

      Assert.AreEqual('trademark', TrademarkName);
      Assert.AreEqual('Euro', EuroName);
    finally
      Font.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TTrueTypeCmapTests.TestSpaceAndA;
begin
  const Parser = TTTFParser.Create;
  try
    const Font = Parser.Parse(TTestFonts.Bytes(LiberationSans));
    try
      var Lookup: TCmapSubtable;
      Assert.IsTrue(Font.TryGetUnicodeCmapLookup(True, Lookup));

      const SpaceGlyph = Lookup.GetGlyphId($20);
      const LetterAGlyph = Lookup.GetGlyphId($41);

      CheckEqual(569, Font.GetAdvanceWidth(SpaceGlyph));
      CheckEqual(1366, Font.GetAdvanceWidth(LetterAGlyph));
    finally
      Font.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TTrueTypeCmapTests.TestNameToGID;
begin
  const Parser = TTTFParser.Create;
  try
    const Font = Parser.Parse(TTestFonts.Bytes(LiberationSans));
    try
      var Lookup: TCmapSubtable;
      Assert.IsTrue(Font.TryGetUnicodeCmapLookup(True, Lookup));
      const LetterAGlyph = Lookup.GetGlyphId($41);
      Assert.IsTrue(LetterAGlyph > 0);

      CheckEqual(LetterAGlyph, Font.NameToGID('A'));
      CheckEqual(LetterAGlyph, Font.NameToGID('uni0041'));
      CheckEqual(3, Font.NameToGID('g3'));
      CheckEqual(0, Font.NameToGID('.notdef'));
    finally
      Font.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TTrueTypeCmapTests.TestNameToGIDRejectsMalformedNames;
begin
  const Parser = TTTFParser.Create;
  try
    const Font = Parser.Parse(TTestFonts.Bytes(LiberationSans));
    try
      CheckEqual(0, Font.NameToGID(''), 'empty name');
      CheckEqual(0, Font.NameToGID('NoSuchGlyph'), 'unknown name');
      CheckEqual(0, Font.NameToGID('gg'), 'g followed by a letter');
      CheckEqual(0, Font.NameToGID('g12x'), 'g with a letter');
      CheckEqual(0, Font.NameToGID('g99999999999999999999'), 'g number beyond Integer');
      CheckEqual(0, Font.NameToGID('uniD800'), 'surrogate');
      CheckEqual(0, Font.NameToGID('uniZZZZ'), 'no hexadecimal digits');
      CheckEqual(0, Font.NameToGID('uni004'), 'too short');
      CheckEqual(0, Font.NameToGID('uni00410042'), 'two numbers are not accepted');
    finally
      Font.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TTrueTypeCmapTests.TestWidthAndHasGlyphByName;
begin
  const Parser = TTTFParser.Create;
  try
    const Font = Parser.Parse(TTestFonts.Bytes(LiberationSans));
    try
      Assert.AreEqual(Double(1366), Double(Font.GetWidth('A')));
      Assert.AreEqual(Double(569), Double(Font.GetWidth('space')));
      Assert.IsTrue(Font.HasGlyph('A'));
      Assert.IsTrue(Font.HasGlyph('trademark'));
      Assert.IsFalse(Font.HasGlyph('NoSuchGlyph'));
    finally
      Font.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TTrueTypeCmapTests.TestUnicodeCmapLookupOrder;
begin
  const Parser = TTTFParser.Create;
  try
    const Font = Parser.Parse(TTestFonts.Bytes(LiberationSans));
    try
      var Lookup: TCmapSubtable;
      Assert.IsTrue(Font.TryGetUnicodeCmapLookup(True, Lookup));

      CheckEqual(TCmapTable.PlatformUnicode, Lookup.PlatformId);
      CheckEqual(TCmapTable.EncodingUnicode20Bmp, Lookup.PlatformEncodingId);
      Assert.AreSame(Lookup, Font.GetUnicodeCmapLookup);
    finally
      Font.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TTrueTypeCmapTests.TestFontWithoutUnicodeCmapFailsStrictAndFallsBackLeniently;
begin
  const Data = TTestFonts.Bytes(LiberationSans);
  const Macintosh = BuildCmapTable([Spec(TCmapTable.PlatformMacintosh, TCmapTable.EncodingMacRoman, Format0($41, 7))]);
  TTrueTypeTestData.ReplaceTable(Data, TCmapTable.TableTag, TCmapTable.TableTag, Macintosh);

  const Parser = TTTFParser.Create;
  try
    const Font = Parser.Parse(Data);
    try
      var Lookup: TCmapSubtable;
      Assert.IsFalse(Font.TryGetUnicodeCmapLookup(True, Lookup));
      Assert.WillRaise(
        procedure
        begin
          Font.GetUnicodeCmapLookup;
        end,
        EPdfParseException);

      Assert.IsTrue(Font.TryGetUnicodeCmapLookup(False, Lookup));
      CheckEqual(7, Lookup.GetGlyphId($41));
      CheckEqual(7, Font.NameToGID('uni0041'));
    finally
      Font.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TTrueTypeCmapTests.TestSubtableMapsKnownCharacter(const Format: Integer);
begin
  const Host = TTestTableHost.Create(GlyphCount);
  try
    const Cmap = LoadCmap(Host, BuildCmapTable([Spec(3, 1, SubtableForFormat(Format))]));
    var Subtable: TCmapSubtable;
    Assert.IsTrue(Cmap.TryGetSubtable(3, 1, Subtable));

    CheckEqual(5, Subtable.GetGlyphId($41));
    CheckEqual(0, Subtable.GetGlyphId($5A), 'a code without a glyph gives 0');
    CheckCodes([$41], Subtable.GetCharCodes(5));
    CheckEqual(0, Length(Subtable.GetCharCodes(GlyphCount - 1)), 'a glyph without a code has no codes');
  finally
    Host.Free;
  end;
end;

// The tests of PDFBox use fonts that are not part of the test set; a cmap with the same shape (two codes for one glyph) stands in
procedure TTrueTypeCmapTests.TestCharCodesOfGlyphWithSeveralCodesAreSorted;
begin
  const Host = TTestTableHost.Create(GlyphCount);
  try
    const Segments: TArray<TCmapSegmentSpec> = [Segment(100, 100, DeltaFor(100, 8), 0),
                      Segment(63847, 63847, DeltaFor(63847, 8), 0),
                      Segment($FFFF, $FFFF, 1, 0)];
    const Groups: TArray<TCmapGroupSpec> = [Group(63847, 63847, 8), Group(100, 100, 8)];
    const Cmap = LoadCmap(Host, BuildCmapTable([Spec(0, 3, Format4(Segments, [])), Spec(0, 4, Format12Or13(12, Groups, 2))]));

    var Bmp: TCmapSubtable;
    var Full: TCmapSubtable;
    Assert.IsTrue(Cmap.TryGetSubtable(0, 3, Bmp));
    Assert.IsTrue(Cmap.TryGetSubtable(0, 4, Full));

    CheckCodes([100, 63847], Bmp.GetCharCodes(8));
    CheckCodes([100, 63847], Full.GetCharCodes(8));
  finally
    Host.Free;
  end;
end;

procedure TTrueTypeCmapTests.TestFormat4WithSegCountZeroIsLenient;
begin
  const Host = TTestTableHost.Create(GlyphCount);
  try
    const Cmap = LoadCmap(Host, BuildCmapTable([Spec(3, 1, Format4([], []))]));

    var Subtable: TCmapSubtable;
    Assert.IsTrue(Cmap.TryGetSubtable(3, 1, Subtable));
    CheckEqual(0, Subtable.GetGlyphId($41));
    CheckEqual(0, Length(Subtable.GetCharCodes(0)));
  finally
    Host.Free;
  end;
end;

// Segments that end before they start, and the reserved last segment, hold no characters
procedure TTrueTypeCmapTests.TestFormat4WithBadSegmentsIsLenient;
begin
  const Host = TTestTableHost.Create(GlyphCount);
  try
    const Segments: TArray<TCmapSegmentSpec> = [Segment($50, $40, DeltaFor($50, 5), 0),
                      Segment($45, $41, DeltaFor($45, 6), 0),
                      Segment($FFFF, $FFFF, 1, 0)];
    const Cmap = LoadCmap(Host, BuildCmapTable([Spec(3, 1, Format4(Segments, []))]));

    var Subtable: TCmapSubtable;
    Assert.IsTrue(Cmap.TryGetSubtable(3, 1, Subtable));
    for var Code := $38 to $52 do
    begin
      CheckEqual(0, Subtable.GetGlyphId(Code));
    end;
    CheckEqual(0, Subtable.GetGlyphId($FFFF));
  finally
    Host.Free;
  end;
end;

procedure TTrueTypeCmapTests.TestFormat4OverlappingSegmentsLastOneWins;
begin
  const Host = TTestTableHost.Create(GlyphCount);
  try
    const Segments: TArray<TCmapSegmentSpec> = [Segment($41, $43, DeltaFor($41, 5), 0),
                      Segment($42, $44, DeltaFor($42, 9), 0),
                      Segment($FFFF, $FFFF, 1, 0)];
    const Cmap = LoadCmap(Host, BuildCmapTable([Spec(3, 1, Format4(Segments, []))]));

    var Subtable: TCmapSubtable;
    Assert.IsTrue(Cmap.TryGetSubtable(3, 1, Subtable));
    CheckEqual(5, Subtable.GetGlyphId($41));
    CheckEqual(9, Subtable.GetGlyphId($42));
    CheckEqual(10, Subtable.GetGlyphId($43));
    CheckEqual(11, Subtable.GetGlyphId($44));
  finally
    Host.Free;
  end;
end;

procedure TTrueTypeCmapTests.TestFormat4ReadsGlyphArrayThroughRangeOffset;
begin
  const Host = TTestTableHost.Create(GlyphCount);
  try
    // The offset counts from the idRangeOffset entry of the segment: two entries remain after it, so 4 bytes reach the array
    const Segments: TArray<TCmapSegmentSpec> = [Segment($41, $42, 0, 4), Segment($FFFF, $FFFF, 1, 0)];
    const Cmap = LoadCmap(Host, BuildCmapTable([Spec(3, 1, Format4(Segments, [7, 0]))]));

    var Subtable: TCmapSubtable;
    Assert.IsTrue(Cmap.TryGetSubtable(3, 1, Subtable));
    CheckEqual(7, Subtable.GetGlyphId($41));
    CheckEqual(0, Subtable.GetGlyphId($42), 'a zero in the array is no glyph');
  finally
    Host.Free;
  end;
end;

procedure TTrueTypeCmapTests.TestFormat4RangeOffsetBeyondDataRaises;
begin
  const Host = TTestTableHost.Create(GlyphCount);
  try
    const Segments: TArray<TCmapSegmentSpec> = [Segment($41, $42, 0, $FFFE), Segment($FFFF, $FFFF, 1, 0)];
    const Bytes = BuildCmapTable([Spec(3, 1, Format4(Segments, []))]);

    Assert.WillRaise(
      procedure
      begin
        ReadCmapTable(Host, Bytes);
      end,
      EPdfParseException);
  finally
    Host.Free;
  end;
end;

procedure TTrueTypeCmapTests.TestFormat10IsValidatedAndMapsNothing;
begin
  const Host = TTestTableHost.Create(GlyphCount);
  try
    const Cmap = LoadCmap(Host, BuildCmapTable([Spec(3, 10, Format10($41, 4))]));

    var Subtable: TCmapSubtable;
    Assert.IsTrue(Cmap.TryGetSubtable(3, 10, Subtable));
    CheckEqual(0, Subtable.GetGlyphId($41));
  finally
    Host.Free;
  end;
end;

procedure TTrueTypeCmapTests.TestFormat10WithInvalidCodesRaises;
begin
  const Host = TTestTableHost.Create(GlyphCount);
  try
    const BeyondUnicode = BuildCmapTable([Spec(3, 10, Format10($10FFF0, $20))]);
    const NumberOfCharsTooLarge = BuildCmapTable([Spec(3, 10, Format10(0, $80000000))]);

    Assert.WillRaise(
      procedure
      begin
        ReadCmapTable(Host, BeyondUnicode);
      end,
      EPdfParseException);
    Assert.WillRaise(
      procedure
      begin
        ReadCmapTable(Host, NumberOfCharsTooLarge);
      end,
      EPdfParseException);
  finally
    Host.Free;
  end;
end;

procedure TTrueTypeCmapTests.TestFormat14IsIgnoredWithWarning;
begin
  const Warnings = TList<string>.Create;
  const Log = TPdfLog.Create(
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      if Level = TPdfLogLevel.Warning then
      begin
        Warnings.Add(Message);
      end;
    end);
  const Host = TTestTableHost.Create(GlyphCount);
  try
    Host.Log := Log;
    const Cmap = LoadCmap(Host, BuildCmapTable([Spec(0, 5, Format14)]));

    var Subtable: TCmapSubtable;
    Assert.IsTrue(Cmap.TryGetSubtable(0, 5, Subtable));
    CheckEqual(0, Subtable.GetGlyphId($41));
    CheckEqual(1, Warnings.Count);
  finally
    Host.Free;
    Log.Free;
    Warnings.Free;
  end;
end;

procedure TTrueTypeCmapTests.TestUnknownFormatRaises;
begin
  const Host = TTestTableHost.Create(GlyphCount);
  try
    const Bytes = BuildCmapTable([Spec(3, 1, FormatWithOnlyHeader(99))]);

    Assert.WillRaise(
      procedure
      begin
        ReadCmapTable(Host, Bytes);
      end,
      EPdfParseException);
  finally
    Host.Free;
  end;
end;

procedure TTrueTypeCmapTests.TestFormat12GlyphBeyondNumGlyphsIsCutShort;
begin
  const Host = TTestTableHost.Create(GlyphCount);
  try
    // The group wants the glyphs 15 to 114, but the font has 20
    const Groups: TArray<TCmapGroupSpec> = [Group($41, $41 + 99, 15), Group($1000, $1001, 3)];
    const Cmap = LoadCmap(Host, BuildCmapTable([Spec(3, 10, Format12Or13(12, Groups, 2))]));

    var Subtable: TCmapSubtable;
    Assert.IsTrue(Cmap.TryGetSubtable(3, 10, Subtable));
    CheckEqual(15, Subtable.GetGlyphId($41));
    CheckEqual(19, Subtable.GetGlyphId($41 + 4));
    CheckEqual(0, Subtable.GetGlyphId($41 + 5));
    CheckEqual(3, Subtable.GetGlyphId($1000), 'the next group is still read');
  finally
    Host.Free;
  end;
end;

procedure TTrueTypeCmapTests.TestFormat12SurrogateCodeRaises;
begin
  const Host = TTestTableHost.Create(GlyphCount);
  try
    const Bytes = BuildCmapTable([Spec(3, 10, Format12Or13(12, [Group($D800, $D801, 1)], 1))]);

    Assert.WillRaise(
      procedure
      begin
        ReadCmapTable(Host, Bytes);
      end,
      EPdfParseException);
  finally
    Host.Free;
  end;
end;

procedure TTrueTypeCmapTests.TestFormat12GroupCountOf2To32Raises;
begin
  const Host = TTestTableHost.Create(GlyphCount);
  try
    const Bytes = BuildCmapTable([Spec(3, 10, Format12Or13(12, [Group($41, $43, 1)], $FFFFFFFF))]);

    Assert.WillRaise(
      procedure
      begin
        ReadCmapTable(Host, Bytes);
      end,
      EPdfParseException);
  finally
    Host.Free;
  end;
end;

procedure TTrueTypeCmapTests.TestFormat13GlyphEqualToNumGlyphsEndsTheTable;
begin
  const Host = TTestTableHost.Create(GlyphCount);
  try
    const Groups: TArray<TCmapGroupSpec> = [Group($41, $42, 4), Group($50, $51, GlyphCount), Group($60, $61, 5)];
    const Cmap = LoadCmap(Host, BuildCmapTable([Spec(3, 10, Format12Or13(13, Groups, 3))]));

    var Subtable: TCmapSubtable;
    Assert.IsTrue(Cmap.TryGetSubtable(3, 10, Subtable));
    CheckEqual(4, Subtable.GetGlyphId($42));
    CheckEqual(0, Subtable.GetGlyphId($50));
    CheckEqual(0, Subtable.GetGlyphId($60));
  finally
    Host.Free;
  end;
end;

procedure TTrueTypeCmapTests.TestFormat8GroupCountTooLargeRaises;
begin
  const Host = TTestTableHost.Create(GlyphCount);
  try
    const Bytes = BuildCmapTable([Spec(3, 10, Format8([], 65537))]);

    Assert.WillRaise(
      procedure
      begin
        ReadCmapTable(Host, Bytes);
      end,
      EPdfParseException);
  finally
    Host.Free;
  end;
end;

procedure TTrueTypeCmapTests.TestFormat8CodeBeyondFlagArrayRaises;
begin
  const Host = TTestTableHost.Create(GlyphCount);
  try
    const Bytes = BuildCmapTable([Spec(3, 10, Format8([Group($41, $FFFFFFF0, 1)], 1))]);

    Assert.WillRaise(
      procedure
      begin
        ReadCmapTable(Host, Bytes);
      end,
      EPdfParseException);
  finally
    Host.Free;
  end;
end;

procedure TTrueTypeCmapTests.TestFormat8GlyphEqualToNumGlyphsRaises;
begin
  const Host = TTestTableHost.Create(GlyphCount);
  try
    const Bytes = BuildCmapTable([Spec(3, 10, Format8([Group($41, $41, GlyphCount)], 1))]);

    Assert.WillRaise(
      procedure
      begin
        ReadCmapTable(Host, Bytes);
      end,
      EPdfParseException);
  finally
    Host.Free;
  end;
end;

// The key of the highest subheader promises 8192 subheaders that the data does not hold
procedure TTrueTypeCmapTests.TestFormat2SubheaderIndexBeyondDataRaises;
begin
  const Host = TTestTableHost.Create(GlyphCount);
  try
    const Writer = TTestByteWriter.Create;
    try
      Writer.U16(2);
      Writer.U16(0);
      Writer.U16(0);
      Writer.U16($FFF8);
      for var Key := 1 to 255 do
      begin
        Writer.U16(0);
      end;
      Writer.Zeros(16);
      const Bytes = BuildCmapTable([Spec(3, 1, Writer.ToBytes)]);

      Assert.WillRaise(
        procedure
        begin
          ReadCmapTable(Host, Bytes);
        end,
        EPdfParseException);
    finally
      Writer.Free;
    end;
  finally
    Host.Free;
  end;
end;

procedure TTrueTypeCmapTests.TestFormat2GlyphArrayBeyondDataRaises;
begin
  const Host = TTestTableHost.Create(GlyphCount);
  try
    const Writer = TTestByteWriter.Create;
    try
      Writer.U16(2);
      Writer.U16(0);
      Writer.U16(0);
      for var Key := 0 to 255 do
      begin
        Writer.U16(0);
      end;
      Writer.U16($41);
      Writer.U16(65535);
      Writer.U16(0);
      Writer.U16(2);
      const Bytes = BuildCmapTable([Spec(3, 1, Writer.ToBytes)]);

      Assert.WillRaise(
        procedure
        begin
          ReadCmapTable(Host, Bytes);
        end,
        EPdfParseException);
    finally
      Writer.Free;
    end;
  finally
    Host.Free;
  end;
end;

procedure TTrueTypeCmapTests.TestSubtableCountBeyondDataRaises;
begin
  const Host = TTestTableHost.Create(GlyphCount);
  try
    const Writer = TTestByteWriter.Create;
    try
      Writer.U16(0);
      Writer.U16($FFFF);
      Writer.Zeros(16);
      const Bytes = Writer.ToBytes;

      Assert.WillRaise(
        procedure
        begin
          ReadCmapTable(Host, Bytes);
        end,
        EPdfParseException);
    finally
      Writer.Free;
    end;
  finally
    Host.Free;
  end;
end;

// Thousands of groups that all cover the same range: the table stops at its work limit, keeps what it has and logs it once
procedure TTrueTypeCmapTests.TestOverlappingGroupsStopAtTheWorkLimit;
begin
  const Warnings = TList<string>.Create;
  const Log = TPdfLog.Create(
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      if Message.Contains('too large') then
      begin
        Warnings.Add(Message);
      end;
    end);
  const Host = TTestTableHost.Create(65535);
  try
    Host.Log := Log;
    const GroupTotal = 20000;
    var Groups: TArray<TCmapGroupSpec>;
    SetLength(Groups, GroupTotal);
    for var Index := 0 to GroupTotal - 1 do
    begin
      Groups[Index] := Group(0, $FFF, 1);
    end;
    const Bytes = BuildCmapTable([Spec(3, 10, Format12Or13(12, Groups, GroupTotal))]);

    const Stopwatch = TStopwatch.StartNew;
    const Cmap = LoadCmap(Host, Bytes);
    Stopwatch.Stop;

    var Subtable: TCmapSubtable;
    Assert.IsTrue(Cmap.TryGetSubtable(3, 10, Subtable));
    CheckEqual(1 + $41, Subtable.GetGlyphId($41));
    Assert.IsTrue(Stopwatch.ElapsedMilliseconds < MaximumHostileMilliseconds, 'The table took too long');
    CheckEqual(1, Warnings.Count);
  finally
    Host.Free;
    Log.Free;
    Warnings.Free;
  end;
end;

procedure TTrueTypeCmapTests.TestManySubtablesOnTheSameDataStopAtTheWorkLimit;
begin
  const Host = TTestTableHost.Create(GlyphCount);
  try
    const SubtableTotal = 5000;
    const Writer = TTestByteWriter.Create;
    try
      Writer.U16(0);
      Writer.U16(SubtableTotal);
      const DataStart = 4 + (8 * SubtableTotal);
      for var Index := 1 to SubtableTotal do
      begin
        Writer.U16(3);
        Writer.U16(1);
        Writer.U32(DataStart);
      end;
      // One format 4 subtable with the maximum number of segments, shared by all records
      const SegmentTotal = 30000;
      var Segments: TArray<TCmapSegmentSpec>;
      SetLength(Segments, SegmentTotal);
      for var Index := 0 to SegmentTotal - 1 do
      begin
        Segments[Index] := Segment(0, $FFFE, 0, 0);
      end;
      Writer.Append(Format4(Segments, []));

      const Stopwatch = TStopwatch.StartNew;
      const Cmap = LoadCmap(Host, Writer.ToBytes);
      Stopwatch.Stop;

      CheckEqual(SubtableTotal, Cmap.Subtables.Count);
      Assert.IsTrue(Stopwatch.ElapsedMilliseconds < MaximumHostileMilliseconds, 'The table took too long');
    finally
      Writer.Free;
    end;
  finally
    Host.Free;
  end;
end;

class function TTrueTypeCmapTests.RecordsOnOneSubtable(const Subtable: TBytes; const RecordTotal: Integer): TBytes;
begin
  const Writer = TTestByteWriter.Create;
  try
    Writer.U16(0);
    Writer.U16(RecordTotal);
    const DataStart = 4 + (8 * RecordTotal);
    for var Index := 1 to RecordTotal do
    begin
      Writer.U16(3);
      Writer.U16(1);
      Writer.U32(DataStart);
    end;
    Writer.Append(Subtable);
    Result := Writer.ToBytes;
  finally
    Writer.Free;
  end;
end;

class function TTrueTypeCmapTests.CountSubtablesWithGlyph(const Cmap: TCmapTable; const GlyphId: Integer): Integer;
begin
  Result := 0;
  for var Subtable in Cmap.Subtables do
  begin
    if Length(Subtable.GetCharCodes(GlyphId)) > 0 then
    begin
      Inc(Result);
    end;
  end;
end;

// 65535 records on one format 13 subtable without groups: nothing is mapped, so nothing may be allocated per record
procedure TTrueTypeCmapTests.TestManyRecordsOnOneEmptyFormat13SubtableAllocateLittle;
begin
  const MaximumGlyphs = 65535;
  const MaximumRecords = 65535;
  const Host = TTestTableHost.Create(MaximumGlyphs);
  try
    const Bytes = RecordsOnOneSubtable(Format12Or13(13, [], 0), MaximumRecords);

    const Stopwatch = TStopwatch.StartNew;
    const Cmap = LoadCmap(Host, Bytes);
    Stopwatch.Stop;

    CheckEqual(MaximumRecords, Cmap.Subtables.Count);
    Assert.IsTrue(Stopwatch.ElapsedMilliseconds < MaximumHostileMilliseconds, 'The table took too long');
    CheckEqual(0, CountSubtablesWithGlyph(Cmap, 0));
  finally
    Host.Free;
  end;
end;

// One format 4 segment with delta 65535 gives a lookup of 65536 entries: the records share the budget for those
procedure TTrueTypeCmapTests.TestManyRecordsOnOneFormat4SubtableAreChargedForTheLookup;
begin
  const MaximumGlyphs = 65535;
  const MaximumRecords = 65535;
  const LookupSize = 65536;
  const Host = TTestTableHost.Create(MaximumGlyphs);
  try
    const Bytes = RecordsOnOneSubtable(Format4([Segment(0, 0, 65535, 0)], []), MaximumRecords);

    const Stopwatch = TStopwatch.StartNew;
    const Cmap = LoadCmap(Host, Bytes);
    Stopwatch.Stop;

    CheckEqual(MaximumRecords, Cmap.Subtables.Count);
    Assert.IsTrue(Stopwatch.ElapsedMilliseconds < MaximumHostileMilliseconds, 'The table took too long');

    const WithLookup = CountSubtablesWithGlyph(Cmap, 65535);
    Assert.IsTrue(WithLookup >= 1, 'The first subtable is read');
    Assert.IsTrue(WithLookup <= (TCmapTable.MaximumWork div LookupSize) + 1, Format('%d subtables kept a lookup', [WithLookup]));
  finally
    Host.Free;
  end;
end;

procedure TTrueTypeCmapTests.TestRecordsOnOneSubtableShareItsMappings;
begin
  const Host = TTestTableHost.Create(GlyphCount);
  try
    const Bytes = RecordsOnOneSubtable(Format4([Segment($41, $42, DeltaFor($41, 3), 0)], []), 3);
    const Cmap = LoadCmap(Host, Bytes);

    CheckEqual(3, Cmap.Subtables.Count);
    for var Subtable in Cmap.Subtables do
    begin
      CheckEqual(3, Subtable.GetGlyphId($41));
      CheckEqual(4, Subtable.GetGlyphId($42));
      CheckCodes([$41], Subtable.GetCharCodes(3));
    end;
  finally
    Host.Free;
  end;
end;

// A budget that runs out in a subtable must not leave codes without reverse lookup (or the other way round)
procedure TTrueTypeCmapTests.TestBudgetThatRunsOutKeepsBothDirectionsConsistent;
begin
  const Host = TTestTableHost.Create(65535);
  try
    const GroupTotal = 2000;
    var Groups: TArray<TCmapGroupSpec>;
    SetLength(Groups, GroupTotal);
    for var Index := 0 to GroupTotal - 1 do
    begin
      Groups[Index] := Group(0, $FFF, 1);
    end;
    const Cmap = LoadCmap(Host, BuildCmapTable([Spec(3, 10, Format12Or13(12, Groups, GroupTotal)),
                                                Spec(3, 1, Format4([Segment(0, 0, 65535, 0)], []))]));

    for var Subtable in Cmap.Subtables do
    begin
      for var Code := 0 to $FFF do
      begin
        const GlyphId = Subtable.GetGlyphId(Code);
        if GlyphId > 0 then
        begin
          var FoundAt: Integer;
          Assert.IsTrue(TArray.BinarySearch<Integer>(Subtable.GetCharCodes(GlyphId), Code, FoundAt), Format('Code %d has no reverse lookup', [Code]));
        end;
      end;
    end;
  finally
    Host.Free;
  end;
end;

procedure TTrueTypeCmapTests.TestHostileFormat12InFontEndsInParseError;
begin
  const Bytes = BuildCmapTable([Spec(3, 10, Format12Or13(12, [Group($41, $43, 1)], $FFFFFFFF))]);

  Assert.AreEqual(EPdfParseException.ClassName, ParseFailureWithCmap(Bytes));
end;

procedure TTrueTypeCmapTests.TestSubtableWithoutDataHasNoGlyphs;
begin
  const Subtable = TCmapSubtable.Create;
  try
    CheckEqual(0, Subtable.GetGlyphId($41));
    CheckEqual(0, Length(Subtable.GetCharCodes(1)));
    CheckEqual(0, Length(Subtable.GetCharCodes(-1)));
  finally
    Subtable.Free;
  end;
end;

end.
