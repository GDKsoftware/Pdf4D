// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/test/java/org/apache/fontbox/ttf/TTFParserTest.java (3.0.8)
unit Pdf4D.FontBox.TrueType.Parser.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.FontBox.TrueType.DataStream,
  Pdf4D.FontBox.TrueType.Font;

type
  [TestFixture]
  TTrueTypeParserTests = class
  private
    const LiberationSans = 'LiberationSans-Regular.ttf';
    const MaximumHostileParseMilliseconds = 1000;

  private
    class function Unsigned16(const Data: TBytes; const Position: Integer): Integer; static;
    class procedure Write16(const Data: TBytes; const Position, Value: Integer); static;
    class procedure Write32(const Data: TBytes; const Position: Integer; const Value: UInt32); static;
    class function DirectoryEntry(const Data: TBytes; const Tag: string): Integer; static;
    class function TableOffset(const Data: TBytes; const Tag: string): Integer; static;
    class function MemoryStream(const Bytes: array of Byte): TTTFMemoryDataStream; static;

    function ParseFailure(const Data: TBytes): string;
    procedure CheckParseOutcomeIsBounded(const Data: TBytes);

  public
    [Test]
    procedure TestLiberationSansHeader;

    [Test]
    [TestCase('LiberationSans', 'LiberationSans-Regular.ttf')]
    [TestCase('JosefinSans', 'JosefinSans-Italic.ttf')]
    procedure TestAdvanceWidthsMatchReference(const FileName: string);

    [Test]
    procedure TestGidBeyondNumberOfHMetricsUsesLastAdvance;

    [Test]
    procedure TestNegativeGidRaisesParseError;

    [Test]
    [TestCase('Header only', '100')]
    [TestCase('Directory only', '1000')]
    [TestCase('Some tables', '50000')]
    [TestCase('Four bytes', '4')]
    [TestCase('Empty', '0')]
    procedure TestTruncatedFontRaisesParseError(const Size: Integer);

    [Test]
    procedure TestTableOffsetBeyondEndRaisesParseError;

    [Test]
    procedure TestTableLengthOverflowIsSkippedNotWrapped;

    [Test]
    procedure TestHugeNumGlyphsIsBounded;

    [Test]
    procedure TestHugeNumberOfTablesRaisesParseError;

    [Test]
    procedure TestHugeNameRecordCountIsBounded;

    [Test]
    procedure TestNameStringOutsideTableIsSkipped;

    [Test]
    procedure TestDuplicateDirectoryEntryLastOneWins;

    [Test]
    procedure TestMissingHeadTableRaisesParseError;

    [Test]
    procedure TestEmbeddedFontMayLackPostNameAndCmap;

    [Test]
    procedure TestOS2Values;

    [Test]
    procedure TestFontBBoxAndMatrixScaleToThousand;

    [Test]
    procedure TestReadAllTablesInitializesEveryTable;

    [Test]
    procedure TestGetTableBytesReturnsTableData;

    [Test]
    procedure TestGetTableBytesOfUnknownTagRaises;

    [Test]
    procedure TestMemoryStreamReadsBigEndian;

    [Test]
    procedure TestReadLongKeepsSign;

    [Test]
    procedure TestRandomAccessStreamReadsLikeMemoryStream;

    [Test]
    procedure TestReadPastEndRaisesParseError;

    [Test]
    procedure TestHugeByteCountDoesNotAllocate;

    [Test]
    procedure TestSeekBeyondEndStaysAtEnd;
  end;

implementation

uses
  System.Classes,
  System.Diagnostics,
  System.Generics.Collections,
  Pdf4D.Common.Defines,
  Pdf4D.IO.RandomAccessRead,
  Pdf4D.FontBox.TrueType.Tables,
  Pdf4D.FontBox.TrueType.Parser,
  Pdf4D.Tests.TestFonts;

const
  DirectoryHeaderSize = 12;
  DirectoryEntrySize = 16;
  EntryOffsetField = 8;
  EntryLengthField = 12;
  NumberOfTablesField = 4;

{ TTrueTypeParserTests }

class function TTrueTypeParserTests.Unsigned16(const Data: TBytes; const Position: Integer): Integer;
begin
  Result := (Data[Position] shl 8) or Data[Position + 1];
end;

class procedure TTrueTypeParserTests.Write16(const Data: TBytes; const Position, Value: Integer);
begin
  Data[Position] := Byte(Value shr 8);
  Data[Position + 1] := Byte(Value);
end;

class procedure TTrueTypeParserTests.Write32(const Data: TBytes; const Position: Integer; const Value: UInt32);
begin
  Write16(Data, Position, Integer(Value shr 16));
  Write16(Data, Position + 2, Integer(Value and $FFFF));
end;

class function TTrueTypeParserTests.DirectoryEntry(const Data: TBytes; const Tag: string): Integer;
begin
  const NumberOfTables = Unsigned16(Data, NumberOfTablesField);
  for var Index := 0 to NumberOfTables - 1 do
  begin
    const Position = DirectoryHeaderSize + (Index * DirectoryEntrySize);
    const EntryTag = string.Create([Char(Data[Position]), Char(Data[Position + 1]), Char(Data[Position + 2]), Char(Data[Position + 3])]);
    if EntryTag = Tag then
    begin
      Exit(Position);
    end;
  end;
  raise EArgumentException.CreateFmt('Test font has no table %s', [Tag]);
end;

class function TTrueTypeParserTests.TableOffset(const Data: TBytes; const Tag: string): Integer;
begin
  const Position = DirectoryEntry(Data, Tag) + EntryOffsetField;
  Result := (Unsigned16(Data, Position) shl 16) or Unsigned16(Data, Position + 2);
end;

class function TTrueTypeParserTests.MemoryStream(const Bytes: array of Byte): TTTFMemoryDataStream;
begin
  var Data: TBytes;
  SetLength(Data, Length(Bytes));
  for var Index := 0 to High(Bytes) do
  begin
    Data[Index] := Bytes[Index];
  end;
  Result := TTTFMemoryDataStream.Create(Data);
end;

function TTrueTypeParserTests.ParseFailure(const Data: TBytes): string;
begin
  Result := '';
  const Parser = TTTFParser.Create;
  try
    try
      Parser.Parse(Data).Free;
    except
      on Failure: Exception do
      begin
        Result := Failure.ClassName;
      end;
    end;
  finally
    Parser.Free;
  end;
end;

// A hostile font ends in a font or in EPdfParseException, quickly, and in nothing else
procedure TTrueTypeParserTests.CheckParseOutcomeIsBounded(const Data: TBytes);
begin
  const Stopwatch = TStopwatch.StartNew;
  const FailureClass = ParseFailure(Data);
  Stopwatch.Stop;

  const IsAccepted = ((FailureClass = '') or (FailureClass = EPdfParseException.ClassName));
  Assert.IsTrue(IsAccepted, Format('Unexpected exception class %s', [FailureClass]));
  Assert.IsTrue(Stopwatch.ElapsedMilliseconds < MaximumHostileParseMilliseconds, 'Parsing took too long');
end;

procedure TTrueTypeParserTests.TestLiberationSansHeader;
begin
  const Parser = TTTFParser.Create;
  try
    const Font = Parser.Parse(TTestFonts.Bytes(LiberationSans));
    try
      Assert.AreEqual(2048, Font.UnitsPerEm);

      var Naming: TNamingTable;
      Assert.IsTrue(Font.TryGetNaming(Naming));
      Assert.AreEqual('LiberationSans', Naming.PostScriptName);

      var OS2Windows: TOS2WindowsMetricsTable;
      Assert.IsTrue(Font.TryGetOS2Windows(OS2Windows));
      Assert.AreEqual(400, OS2Windows.WeightClass);
    finally
      Font.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TTrueTypeParserTests.TestAdvanceWidthsMatchReference(const FileName: string);
begin
  const Reference = TTestFonts.ReferenceWidths(FileName);
  try
    const Parser = TTTFParser.Create;
    try
      const Font = Parser.Parse(TTestFonts.Bytes(FileName));
      try
        Assert.IsTrue(Reference.Count > 0);
        for var Entry in Reference do
        begin
          const GlyphId = StrToInt(Entry.Key.Substring(3));
          Assert.AreEqual(Integer(Round(Entry.Value)), Font.GetAdvanceWidth(GlyphId), Entry.Key);
        end;
      finally
        Font.Free;
      end;
    finally
      Parser.Free;
    end;
  finally
    Reference.Free;
  end;
end;

procedure TTrueTypeParserTests.TestGidBeyondNumberOfHMetricsUsesLastAdvance;
begin
  const ExplicitMetrics = 10;
  const Data = TTestFonts.Bytes(LiberationSans);
  const HheaOffset = TableOffset(Data, THorizontalHeaderTable.TableTag);
  const NumberOfHMetricsField = 34;
  Write16(Data, HheaOffset + NumberOfHMetricsField, ExplicitMetrics);

  const Reference = TTestFonts.ReferenceWidths(LiberationSans);
  try
    const Parser = TTTFParser.Create;
    try
      const Font = Parser.Parse(Data);
      try
        const LastExplicit = Integer(Round(Reference['gid9']));
        Assert.AreEqual(LastExplicit, Font.GetAdvanceWidth(ExplicitMetrics - 1));
        Assert.AreEqual(LastExplicit, Font.GetAdvanceWidth(ExplicitMetrics));
        Assert.AreEqual(LastExplicit, Font.GetAdvanceWidth(100));
        Assert.AreEqual(LastExplicit, Font.GetAdvanceWidth(60000));
      finally
        Font.Free;
      end;
    finally
      Parser.Free;
    end;
  finally
    Reference.Free;
  end;
end;

procedure TTrueTypeParserTests.TestNegativeGidRaisesParseError;
begin
  const Parser = TTTFParser.Create;
  try
    const Font = Parser.Parse(TTestFonts.Bytes(LiberationSans));
    try
      Assert.WillRaise(
        procedure
        begin
          Font.GetAdvanceWidth(-1);
        end,
        EPdfParseException);
    finally
      Font.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TTrueTypeParserTests.TestTruncatedFontRaisesParseError(const Size: Integer);
begin
  var Data := TTestFonts.Bytes(LiberationSans);
  SetLength(Data, Size);

  Assert.AreEqual(EPdfParseException.ClassName, ParseFailure(Data));
end;

procedure TTrueTypeParserTests.TestTableOffsetBeyondEndRaisesParseError;
begin
  const Data = TTestFonts.Bytes(LiberationSans);
  Write32(Data, DirectoryEntry(Data, THorizontalMetricsTable.TableTag) + EntryOffsetField, $7FFFFFF0);

  Assert.AreEqual(EPdfParseException.ClassName, ParseFailure(Data));
end;

procedure TTrueTypeParserTests.TestTableLengthOverflowIsSkippedNotWrapped;
begin
  const Data = TTestFonts.Bytes(LiberationSans);
  const Entry = DirectoryEntry(Data, THorizontalMetricsTable.TableTag);
  Write32(Data, Entry + EntryOffsetField, $FFFFFFF0);
  Write32(Data, Entry + EntryLengthField, $FFFFFFF0);

  Assert.AreEqual(EPdfParseException.ClassName, ParseFailure(Data));
end;

procedure TTrueTypeParserTests.TestHugeNumGlyphsIsBounded;
begin
  const Data = TTestFonts.Bytes(LiberationSans);
  const NumGlyphsField = 4;
  const NumberOfHMetricsField = 34;
  Write16(Data, TableOffset(Data, TMaximumProfileTable.TableTag) + NumGlyphsField, 65535);
  Write16(Data, TableOffset(Data, THorizontalHeaderTable.TableTag) + NumberOfHMetricsField, 65535);

  CheckParseOutcomeIsBounded(Data);
end;

procedure TTrueTypeParserTests.TestHugeNumberOfTablesRaisesParseError;
begin
  var Data := TTestFonts.Bytes(LiberationSans);
  SetLength(Data, DirectoryHeaderSize + DirectoryEntrySize);
  Write16(Data, NumberOfTablesField, 65535);

  Assert.AreEqual(EPdfParseException.ClassName, ParseFailure(Data));
end;

procedure TTrueTypeParserTests.TestHugeNameRecordCountIsBounded;
begin
  const Data = TTestFonts.Bytes(LiberationSans);
  const RecordCountField = 2;
  Write16(Data, TableOffset(Data, TNamingTable.TableTag) + RecordCountField, 65535);

  CheckParseOutcomeIsBounded(Data);
end;

procedure TTrueTypeParserTests.TestNameStringOutsideTableIsSkipped;
begin
  const Data = TTestFonts.Bytes(LiberationSans);
  const NameOffset = TableOffset(Data, TNamingTable.TableTag);
  const FirstRecord = NameOffset + 6;
  const StringLengthField = 8;
  const StringOffsetField = 10;
  Write16(Data, FirstRecord + StringLengthField, 65535);
  Write16(Data, FirstRecord + StringOffsetField, 0);

  const Parser = TTTFParser.Create;
  try
    const Font = Parser.Parse(Data);
    try
      var Naming: TNamingTable;
      Assert.IsTrue(Font.TryGetNaming(Naming));
      Assert.IsFalse(Naming.NameRecords[0].HasValue);
    finally
      Font.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TTrueTypeParserTests.TestDuplicateDirectoryEntryLastOneWins;
begin
  const Data = TTestFonts.Bytes(LiberationSans);
  const MaxpEntry = DirectoryEntry(Data, TMaximumProfileTable.TableTag);
  const HeadEntry = DirectoryEntry(Data, THeaderTable.TableTag);
  // The maxp entry now also says head and comes after the real one: it replaces it, and the font has no maxp table
  Move(Data[HeadEntry], Data[MaxpEntry], 4);

  Assert.IsTrue(MaxpEntry > HeadEntry, 'The test needs maxp after head in the directory');
  Assert.AreEqual(EPdfParseException.ClassName, ParseFailure(Data));
end;

procedure TTrueTypeParserTests.TestMissingHeadTableRaisesParseError;
begin
  const Data = TTestFonts.Bytes(LiberationSans);
  const HeadEntry = DirectoryEntry(Data, THeaderTable.TableTag);
  Data[HeadEntry] := Ord('x');

  Assert.AreEqual(EPdfParseException.ClassName, ParseFailure(Data));
end;

procedure TTrueTypeParserTests.TestEmbeddedFontMayLackPostNameAndCmap;
begin
  const Data = TTestFonts.Bytes(LiberationSans);
  for var Tag in ['post', 'name', 'cmap'] do
  begin
    Data[DirectoryEntry(Data, Tag)] := Ord('x');
  end;

  Assert.AreEqual(EPdfParseException.ClassName, ParseFailure(Data), 'A font that is not embedded needs them');

  const Parser = TTTFParser.Create(True);
  try
    const Font = Parser.Parse(Data);
    try
      Assert.AreEqual('', Font.Name);
    finally
      Font.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TTrueTypeParserTests.TestOS2Values;
begin
  const Parser = TTTFParser.Create;
  try
    const Font = Parser.Parse(TTestFonts.Bytes(LiberationSans));
    try
      var OS2Windows: TOS2WindowsMetricsTable;
      Assert.IsTrue(Font.TryGetOS2Windows(OS2Windows));
      Assert.AreEqual<Integer>(10, Length(OS2Windows.Panose));
      Assert.AreEqual<Integer>(2048, Font.Header.UnitsPerEm);
      Assert.IsTrue(OS2Windows.TypoAscender > 0);
      Assert.IsTrue(OS2Windows.TypoDescender < 0);
      Assert.IsTrue(OS2Windows.Version >= 0);
    finally
      Font.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TTrueTypeParserTests.TestFontBBoxAndMatrixScaleToThousand;
begin
  const Parser = TTTFParser.Create;
  try
    const Font = Parser.Parse(TTestFonts.Bytes(LiberationSans));
    try
      const Header = Font.Header;
      const Scale: Single = 1000.0 / 2048;
      const Box = Font.FontBBox;
      Assert.AreEqual<Single>(Header.XMin * Scale, Box.LowerLeftX);
      Assert.AreEqual<Single>(Header.YMax * Scale, Box.UpperRightY);

      const Matrix = Font.FontMatrix;
      Assert.AreEqual<Integer>(6, Length(Matrix));
      Assert.AreEqual<Single>(0.001 * Scale, Matrix[0]);
      Assert.AreEqual<Single>(0, Matrix[1]);
    finally
      Font.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TTrueTypeParserTests.TestReadAllTablesInitializesEveryTable;
begin
  const Parser = TTTFParser.Create;
  try
    const Font = Parser.Parse(TTestFonts.Bytes(LiberationSans));
    try
      Font.ReadAllTables;

      Assert.IsTrue(Length(Font.TableTags) > 0);
      for var Tag in Font.TableTags do
      begin
        var Table: TTTFTable;
        Assert.IsTrue(Font.TryGetTable(Tag, Table));
        Assert.IsTrue(Table.Initialized, Tag);
      end;
    finally
      Font.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TTrueTypeParserTests.TestGetTableBytesReturnsTableData;
begin
  const Data = TTestFonts.Bytes(LiberationSans);
  const Parser = TTTFParser.Create;
  try
    const Font = Parser.Parse(Data);
    try
      const Bytes = Font.GetTableBytes(THeaderTable.TableTag);
      const Offset = TableOffset(Data, THeaderTable.TableTag);

      Assert.AreEqual<Integer>(54, Length(Bytes));
      Assert.AreEqual<Byte>(Data[Offset + 12], Bytes[12]);
      Assert.AreEqual<Integer>(Font.Header.UnitsPerEm, Unsigned16(Bytes, 18));
    finally
      Font.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TTrueTypeParserTests.TestGetTableBytesOfUnknownTagRaises;
begin
  const Parser = TTTFParser.Create;
  try
    const Font = Parser.Parse(TTestFonts.Bytes(LiberationSans));
    try
      Assert.WillRaise(
        procedure
        begin
          Font.GetTableBytes('zzzz');
        end,
        EPdfParseException);
    finally
      Font.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TTrueTypeParserTests.TestMemoryStreamReadsBigEndian;
begin
  const Stream = MemoryStream([$FF, $FE, $01, $02, $03, $04, $80, 0, 0, 0, 0, 0, $00, $01, $80, $00, Ord('A'), Ord('B'), Ord('C'), Ord('D')]);
  try
    Assert.AreEqual<Integer>(-2, Stream.ReadSignedShort);
    Assert.AreEqual<Int64>($01020304, Stream.ReadUnsignedInt);
    Assert.AreEqual<Integer>(-128, Stream.ReadSignedByte);
    Stream.Seek(12);
    Assert.AreEqual<Single>(1.5, Stream.Read32Fixed);
    Assert.AreEqual('ABCD', Stream.ReadTag);
  finally
    Stream.Free;
  end;
end;

procedure TTrueTypeParserTests.TestReadLongKeepsSign;
begin
  const Stream = MemoryStream([0, 0, 0, 1, 0, 0, 0, 2, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF]);
  try
    Assert.AreEqual<Int64>($0000000100000002, Stream.ReadLong);
    Assert.AreEqual<Int64>(-1, Stream.ReadLong);
  finally
    Stream.Free;
  end;
end;

procedure TTrueTypeParserTests.TestRandomAccessStreamReadsLikeMemoryStream;
begin
  const Data = TTestFonts.Bytes(LiberationSans);
  const Source = TRandomAccessRead.FromBytes(Data);
  try
    const Stream = TTTFRandomAccessDataStream.Create(Source);
    try
      Assert.AreEqual<Int64>(Length(Data), Stream.OriginalDataSize);
      Stream.Seek(4);
      Assert.AreEqual(Unsigned16(Data, 4), Stream.ReadUnsignedShort);
      Assert.AreEqual<Int64>(6, Stream.CurrentPosition);
      Assert.AreEqual(Length(Data), Length(Stream.OriginalData));
      Assert.AreEqual<Int64>(6, Stream.CurrentPosition);
    finally
      Stream.Free;
    end;
  finally
    Source.Free;
  end;
end;

procedure TTrueTypeParserTests.TestReadPastEndRaisesParseError;
begin
  const Stream = MemoryStream([1, 2, 3]);
  try
    Assert.WillRaise(
      procedure
      begin
        Stream.ReadUnsignedInt;
      end,
      EPdfParseException);
    Stream.Seek(3);
    Assert.AreEqual<Integer>(-1, Stream.Read);
    Assert.WillRaise(
      procedure
      begin
        Stream.ReadUnsignedByte;
      end,
      EPdfParseException);
    Stream.Seek(2);
    Assert.WillRaise(
      procedure
      begin
        Stream.ReadLong;
      end,
      EPdfParseException);
  finally
    Stream.Free;
  end;
end;

procedure TTrueTypeParserTests.TestHugeByteCountDoesNotAllocate;
begin
  const Stream = MemoryStream([1, 2, 3]);
  try
    Assert.WillRaise(
      procedure
      begin
        Stream.ReadBytes(MaxInt);
      end,
      EPdfParseException);
    Assert.WillRaise(
      procedure
      begin
        Stream.ReadUnsignedShortArray(MaxInt);
      end,
      EPdfParseException);
    Assert.WillRaise(
      procedure
      begin
        Stream.ReadBytes(-1);
      end,
      EPdfParseException);
  finally
    Stream.Free;
  end;
end;

procedure TTrueTypeParserTests.TestSeekBeyondEndStaysAtEnd;
begin
  const Stream = MemoryStream([1, 2, 3]);
  try
    Stream.Seek(Int64(MaxInt) * 4);

    Assert.AreEqual<Int64>(3, Stream.CurrentPosition);
    Assert.WillRaise(
      procedure
      begin
        Stream.Seek(-1);
      end,
      EPdfParseException);
  finally
    Stream.Free;
  end;
end;

end.
