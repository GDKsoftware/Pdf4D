// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Tests of Pdf4D for fontbox/src/main/java/org/apache/fontbox/pfb/PfbParser.java and fontbox/src/main/java/org/apache/fontbox/type1/*.java
// (3.0.8), ported from PfbParserTest and Type1LexerTest; the reference widths come from PDFBox
unit Pdf4D.FontBox.Type1.Font.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.FontBox.Pfb,
  Pdf4D.FontBox.Type1.Lexer,
  Pdf4D.FontBox.Type1.Font;

type
  TType1TestFont = record
    LenIV: Integer;
    HexEexec: Boolean;
    BuiltInEncoding: Boolean;
  end;

  [TestFixture]
  TPfbParserTests = class
  private
    class function Segment(const SegmentType: Byte; const Content: TBytes): TBytes; static;
    class function Join(const Parts: array of TBytes): TBytes; static;
    class function Filler(const Count: Integer): TBytes; static;

  public
    [Test]
    procedure TestSegmentsAreSplitByType;

    [Test]
    procedure TestSeveralBinarySegmentsAreJoined;

    [Test]
    procedure TestClearToMarkSegmentIsNotPartOfSegment1;

    [Test]
    procedure TestEmptyDataRaises;

    [Test]
    procedure TestShortDataRaises;

    [Test]
    procedure TestNegativeRecordSize;

    [Test]
    procedure TestSegmentLengthBeyondDataRaises;

    [Test]
    procedure TestHugeSegmentLengthRaises;

    [Test]
    procedure TestWrongStartMarkerRaises;

    [Test]
    procedure TestWrongRecordTypeRaises;

    [Test]
    procedure TestCutOffSizeFieldRaises;

    [Test]
    procedure TestMissingEndMarkerIsAccepted;

    [Test]
    procedure TestOnlyEndMarkerGivesEmptySegments;
  end;

  [TestFixture]
  TType1LexerTests = class
  private
    class function AsciiBytes(const Text: string): TBytes; static;
    class function ReadAll(const Lexer: TType1Lexer): TArray<TType1Token>; static;
    class function LexerFor(const Text: string): TType1Lexer; static;
    procedure CheckLexerRaises(const Text: string);

  public
    [Test]
    procedure TestRealNumbers;

    [Test]
    procedure TestEmptyName;

    [Test]
    procedure TestProcAndNameAndDictAndString;

    [Test]
    procedure TestData;

    [Test]
    procedure TestStringLengthLargerThanInputRaises;

    [Test]
    procedure TestRDWithoutIntegerRaises;

    [Test]
    procedure TestNegativeStringLengthRaises;

    [Test]
    procedure TestCharStringBeyondDataRaises;

    [Test]
    procedure TestUnterminatedStringEndsTheTokens;

    [Test]
    procedure TestClosingParenthesisOutsideStringRaises;

    [Test]
    procedure TestInvalidRadixRaises;

    [Test]
    procedure TestInvalidOctalEscapeRaises;

    [Test]
    procedure TestNumberAtTheEndOfTheDataRaises;

    [Test]
    procedure TestProcedureNestingLimitIsEnforced;

    [Test]
    procedure TestProcedureNestingAtTheLimitIsAccepted;

    [Test]
    procedure TestHugeNameIsRead;

    [Test]
    procedure TestHugeUnterminatedArrayDoesNotHang;
  end;

  [TestFixture]
  TType1FontTests = class
  private
    FFont: TType1Font;

    class function AsciiBytes(const Text: string): TBytes; static;
    class function Join(const Parts: array of TBytes): TBytes; static;
    class function Bytes(const Values: array of Byte): TBytes; static;
    class function CharStringEntry(const Name: string; const CharString: TBytes; const LenIV: Integer): TBytes; static;
    class function HeaderText(const BuiltInEncoding: Boolean): string; static;
    class function PrivateSection(const LenIV: Integer): TBytes; static;
    class function EncryptedSegment(const PrivatePlain: TBytes; const HexEexec: Boolean): TBytes; static;
    class function SyntheticSegments(const Options: TType1TestFont; out Segment2: TBytes): TBytes; static;
    class function DefaultOptions: TType1TestFont; static;
    procedure LoadSynthetic(const Options: TType1TestFont);
    procedure CheckFontRaises(const Segment1, Segment2: TBytes);
    procedure CheckSyntheticWidths;
    procedure CheckReferenceWidths(const FontFile: string);
    procedure CheckOpenSans(const Font: TType1Font);
    procedure CheckAllNamesAnswer(const Font: TType1Font);

  public
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestOpenSansProperties;

    [Test]
    procedure TestPfbWithSeveralBinarySegments;

    [Test]
    procedure TestOpenSansBoxAndMatrix;

    [Test]
    procedure TestType1WidthsMatchReference;

    [Test]
    procedure TestType1WidthsMatchReferenceOfSecondFont;

    [Test]
    procedure TestEmptyPfbRaises;

    [Test]
    procedure TestBrokenEexecRaisesParseError;

    [Test]
    procedure TestDeepProcedureNesting;

    [Test]
    procedure TestDeepProcedureNestingInTheHeader;

    [Test]
    procedure TestSyntheticFontParses;

    [Test]
    procedure TestSyntheticFontWithBuiltInEncoding;

    [Test]
    procedure TestLenIVZero;

    [Test]
    procedure TestLenIVMinusOneMeansNotEncrypted;

    [Test]
    procedure TestLenIVBelowMinusOneRaises;

    [Test]
    procedure TestHexEexecIsDetected;

    [Test]
    procedure TestHexEexecWithSpacesIsDetected;

    [Test]
    procedure TestCharStringShorterThanLenIVIsEmpty;

    [Test]
    procedure TestShortEexecDataRaises;

    [Test]
    procedure TestEmptyBinarySegmentGivesFontWithoutGlyphs;

    [Test]
    procedure TestEmptyAsciiSegmentRaises;

    [Test]
    procedure TestMissingEexecRaises;

    [Test]
    procedure TestMissingPrivateRaises;

    [Test]
    procedure TestMissingCharStringsRaises;

    [Test]
    procedure TestSubrsCountBeyondDataRaises;

    [Test]
    procedure TestNegativeSubrIndexRaises;

    [Test]
    procedure TestSubrIndexBeyondCountIsIgnored;

    [Test]
    procedure TestCharStringLengthBeyondDataRaises;

    [Test]
    procedure TestCharStringsCountBeyondDataIsLenient;

    [Test]
    procedure TestCharStringsCountBelowActualCountRaises;

    [Test]
    procedure TestUnterminatedProcedureRaises;

    [Test]
    procedure TestWrappedValuesAreBounded;

    [Test]
    procedure TestUnknownGlyphGetsNotdefWidth;

    [Test]
    procedure TestGetWidthWithoutNotdefRaises;

    [Test]
    procedure TestFontBBoxWithoutNumbersRaises;

    [Test]
    procedure TestUnknownEncodingNameRaises;

    [Test]
    procedure TestFontInfoWithoutValueRaises;

    [Test]
    procedure TestMutatedSyntheticFontEndsCleanly;

    [Test]
    procedure TestMutatedOpenSansEndsCleanly;
  end;

implementation

uses
  System.Math,
  Pdf4D.Common.Defines,
  Pdf4D.FontBox.BoundingBox,
  Pdf4D.FontBox.Encoding,
  Pdf4D.FontBox.Cff.Type1FontUtil,
  Pdf4D.Tests.TestFonts;

const
  AsciiType = 1;
  BinaryType = 2;
  EndType = 3;
  StartMarker = $80;
  OpenSansFile = 'OpenSans-Regular.pfb';
  DejaVuFile = 'DejaVuSerifCondensed.pfb';
  NotdefWidth = 250;
  AWidth = 500;
  BWidth = 600;
  CWidth = 700;

{ TPfbParserTests }

class function TPfbParserTests.Segment(const SegmentType: Byte; const Content: TBytes): TBytes;
begin
  const Size = Length(Content);
  SetLength(Result, 6 + Size);
  Result[0] := StartMarker;
  Result[1] := SegmentType;
  Result[2] := Size and $FF;
  Result[3] := (Size shr 8) and $FF;
  Result[4] := (Size shr 16) and $FF;
  Result[5] := (Size shr 24) and $FF;
  if Size > 0 then
  begin
    Move(Content[0], Result[6], Size);
  end;
end;

class function TPfbParserTests.Join(const Parts: array of TBytes): TBytes;
begin
  Result := nil;
  for var Part in Parts do
  begin
    const Start = Length(Result);
    SetLength(Result, Start + Length(Part));
    if Length(Part) > 0 then
    begin
      Move(Part[0], Result[Start], Length(Part));
    end;
  end;
end;

class function TPfbParserTests.Filler(const Count: Integer): TBytes;
begin
  SetLength(Result, Count);
  for var Index := 0 to Count - 1 do
  begin
    Result[Index] := Byte(Ord('a') + (Index mod 26));
  end;
end;

procedure TPfbParserTests.TestSegmentsAreSplitByType;
begin
  const Data = Join([Segment(AsciiType, Filler(10)), Segment(BinaryType, Filler(7)), Segment(EndType, nil)]);

  const Parser = TPfbParser.Create(Data);
  try
    Assert.AreEqual<TBytes>(Filler(10), Parser.Segment1);
    Assert.AreEqual<TBytes>(Filler(7), Parser.Segment2);
  finally
    Parser.Free;
  end;
end;

procedure TPfbParserTests.TestSeveralBinarySegmentsAreJoined;
begin
  // PDFBOX-5713: a font with several binary segments, and ASCII segments in between
  const Data = Join([Segment(AsciiType, Filler(5)), Segment(BinaryType, Filler(4)), Segment(AsciiType, Filler(6)),
                     Segment(BinaryType, Filler(3)), Segment(EndType, nil)]);

  const Parser = TPfbParser.Create(Data);
  try
    Assert.AreEqual<TBytes>(Join([Filler(5), Filler(6)]), Parser.Segment1);
    Assert.AreEqual<TBytes>(Join([Filler(4), Filler(3)]), Parser.Segment2);
  finally
    Parser.Free;
  end;
end;

procedure TPfbParserTests.TestClearToMarkSegmentIsNotPartOfSegment1;
begin
  const Zeros = TEncoding.ASCII.GetBytes('0000000000000000\ncleartomark\n');
  const Data = Join([Segment(AsciiType, Filler(10)), Segment(BinaryType, Filler(20)), Segment(AsciiType, Zeros),
                     Segment(EndType, nil)]);

  const Parser = TPfbParser.Create(Data);
  try
    Assert.AreEqual<TBytes>(Filler(10), Parser.Segment1);
    Assert.AreEqual<TBytes>(Filler(20), Parser.Segment2);
  finally
    Parser.Free;
  end;
end;

procedure TPfbParserTests.TestEmptyDataRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      TPfbParser.Create(nil).Free;
    end,
    EPdfParseException);
end;

procedure TPfbParserTests.TestShortDataRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      TPfbParser.Create(Filler(17)).Free;
    end,
    EPdfParseException);
end;

procedure TPfbParserTests.TestNegativeRecordSize;
begin
  // The size field 01 00 00 FF overflows a signed int to -16777215
  const Data: TBytes = [$80, $01, $01, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $27, $05, $F8, $FF, $D2, $40];

  Assert.WillRaise(
    procedure
    begin
      TPfbParser.Create(Data).Free;
    end,
    EPdfParseException);
end;

procedure TPfbParserTests.TestSegmentLengthBeyondDataRaises;
begin
  const Data = Join([Segment(AsciiType, Filler(20)), Segment(BinaryType, Filler(30))]);
  var Cut := Data;
  SetLength(Cut, Length(Data) - 5);

  Assert.WillRaise(
    procedure
    begin
      TPfbParser.Create(Cut).Free;
    end,
    EPdfParseException);
end;

procedure TPfbParserTests.TestHugeSegmentLengthRaises;
begin
  var Data := Join([Segment(AsciiType, Filler(20)), Segment(EndType, nil)]);
  // The size 0x7FFFFFFF
  Data[2] := $FF;
  Data[3] := $FF;
  Data[4] := $FF;
  Data[5] := $7F;

  Assert.WillRaise(
    procedure
    begin
      TPfbParser.Create(Data).Free;
    end,
    EPdfParseException);
end;

procedure TPfbParserTests.TestWrongStartMarkerRaises;
begin
  var Data := Join([Segment(AsciiType, Filler(20)), Segment(EndType, nil)]);
  Data[0] := $81;

  Assert.WillRaise(
    procedure
    begin
      TPfbParser.Create(Data).Free;
    end,
    EPdfParseException);
end;

procedure TPfbParserTests.TestWrongRecordTypeRaises;
begin
  var Data := Join([Segment(AsciiType, Filler(20)), Segment(EndType, nil)]);
  Data[1] := 7;

  Assert.WillRaise(
    procedure
    begin
      TPfbParser.Create(Data).Free;
    end,
    EPdfParseException);
end;

procedure TPfbParserTests.TestCutOffSizeFieldRaises;
begin
  // The second record starts so near the end that its size field does not fit
  const Header: TBytes = [StartMarker, AsciiType, 1, 0];
  const Data = Join([Segment(AsciiType, Filler(14)), Header]);

  Assert.WillRaise(
    procedure
    begin
      TPfbParser.Create(Data).Free;
    end,
    EPdfParseException);
end;

procedure TPfbParserTests.TestMissingEndMarkerIsAccepted;
begin
  const Data = Join([Segment(AsciiType, Filler(20)), Segment(BinaryType, Filler(5))]);

  const Parser = TPfbParser.Create(Data);
  try
    Assert.AreEqual<TBytes>(Filler(20), Parser.Segment1);
    Assert.AreEqual<TBytes>(Filler(5), Parser.Segment2);
  finally
    Parser.Free;
  end;
end;

procedure TPfbParserTests.TestOnlyEndMarkerGivesEmptySegments;
begin
  var Data := Join([Segment(EndType, nil), Filler(20)]);

  const Parser = TPfbParser.Create(Data);
  try
    Assert.AreEqual<Integer>(0, Length(Parser.Segment1));
    Assert.AreEqual<Integer>(0, Length(Parser.Segment2));
  finally
    Parser.Free;
  end;
end;

{ TType1LexerTests }

class function TType1LexerTests.AsciiBytes(const Text: string): TBytes;
begin
  Result := TEncoding.ASCII.GetBytes(Text);
end;

class function TType1LexerTests.LexerFor(const Text: string): TType1Lexer;
begin
  Result := TType1Lexer.Create(AsciiBytes(Text));
end;

class function TType1LexerTests.ReadAll(const Lexer: TType1Lexer): TArray<TType1Token>;
begin
  const Tokens = TList<TType1Token>.Create;
  try
    while Lexer.PeekToken.Kind <> TType1TokenKind.None do
    begin
      Tokens.Add(Lexer.NextToken);
    end;
    Result := Tokens.ToArray;
  finally
    Tokens.Free;
  end;
end;

procedure TType1LexerTests.CheckLexerRaises(const Text: string);
begin
  var Failed := False;
  try
    const Lexer = LexerFor(Text);
    try
      ReadAll(Lexer);
    finally
      Lexer.Free;
    end;
  except
    on EPdfParseException do
    begin
      Failed := True;
    end;
  end;
  Assert.IsTrue(Failed, Format('"%s" must give an EPdfParseException', [Copy(Text, 1, 40)]));
end;

procedure TType1LexerTests.TestRealNumbers;
begin
  // PDFBOX-5155
  const Lexer = LexerFor('/FontMatrix [1e-3 0e-3 0e-3 -1E-03 0 0 1.23 -1.23 ] readonly def');
  try
    const Tokens = ReadAll(Lexer);

    Assert.AreEqual<Integer>(13, Length(Tokens));
    Assert.AreEqual<TType1TokenKind>(TType1TokenKind.Literal, Tokens[0].Kind);
    Assert.AreEqual('FontMatrix', Tokens[0].Text);
    Assert.AreEqual<TType1TokenKind>(TType1TokenKind.StartArray, Tokens[1].Kind);
    for var Index := 2 to 5 do
    begin
      Assert.AreEqual<TType1TokenKind>(TType1TokenKind.Real, Tokens[Index].Kind);
    end;
    Assert.AreEqual<TType1TokenKind>(TType1TokenKind.Int, Tokens[6].Kind);
    Assert.AreEqual<TType1TokenKind>(TType1TokenKind.Int, Tokens[7].Kind);
    Assert.AreEqual<TType1TokenKind>(TType1TokenKind.Real, Tokens[8].Kind);
    Assert.AreEqual<TType1TokenKind>(TType1TokenKind.Real, Tokens[9].Kind);
    Assert.AreEqual('1e-3', Tokens[2].Text);
    Assert.AreEqual('0e-3', Tokens[3].Text);
    Assert.AreEqual('0e-3', Tokens[4].Text);
    Assert.AreEqual('-1E-03', Tokens[5].Text);
    Assert.AreEqual<Single>(-1E-3, Tokens[5].FloatValue);
    Assert.AreEqual('0', Tokens[6].Text);
    Assert.AreEqual('0', Tokens[7].Text);
    Assert.AreEqual('1.23', Tokens[8].Text);
    Assert.AreEqual('-1.23', Tokens[9].Text);
    Assert.AreEqual<TType1TokenKind>(TType1TokenKind.EndArray, Tokens[10].Kind);
    Assert.AreEqual<TType1TokenKind>(TType1TokenKind.Name, Tokens[11].Kind);
    Assert.AreEqual<TType1TokenKind>(TType1TokenKind.Name, Tokens[12].Kind);
  finally
    Lexer.Free;
  end;
end;

procedure TType1LexerTests.TestEmptyName;
begin
  var Message := '';
  try
    const Lexer = LexerFor('dup 127 / put');
    try
      ReadAll(Lexer);
    finally
      Lexer.Free;
    end;
  except
    on E: EPdfParseException do
    begin
      Message := E.Message;
    end;
  end;

  Assert.AreEqual('Could not read token at position 9', Message);
end;

procedure TType1LexerTests.TestProcAndNameAndDictAndString;
begin
  const Text = '/ND {noaccess def} executeonly def '#10' 8#173 +2#110 '#10'%comment '#10'<< (string \n \r \t \b \f \\ \( \) \123) >>';
  const Lexer = LexerFor(Text);
  try
    const Tokens = ReadAll(Lexer);

    Assert.AreEqual<Integer>(12, Length(Tokens));
    Assert.AreEqual<TType1TokenKind>(TType1TokenKind.Literal, Tokens[0].Kind);
    Assert.AreEqual('ND', Tokens[0].Text);
    Assert.AreEqual<TType1TokenKind>(TType1TokenKind.StartProc, Tokens[1].Kind);
    Assert.AreEqual<TType1TokenKind>(TType1TokenKind.Name, Tokens[2].Kind);
    Assert.AreEqual('noaccess', Tokens[2].Text);
    Assert.AreEqual<TType1TokenKind>(TType1TokenKind.Name, Tokens[3].Kind);
    Assert.AreEqual('def', Tokens[3].Text);
    Assert.AreEqual<TType1TokenKind>(TType1TokenKind.EndProc, Tokens[4].Kind);
    Assert.AreEqual<TType1TokenKind>(TType1TokenKind.Name, Tokens[5].Kind);
    Assert.AreEqual('executeonly', Tokens[5].Text);
    Assert.AreEqual<TType1TokenKind>(TType1TokenKind.Name, Tokens[6].Kind);
    Assert.AreEqual('def', Tokens[6].Text);
    Assert.AreEqual<TType1TokenKind>(TType1TokenKind.Int, Tokens[7].Kind);
    Assert.AreEqual('123', Tokens[7].Text);
    Assert.AreEqual<TType1TokenKind>(TType1TokenKind.Int, Tokens[8].Kind);
    Assert.AreEqual('6', Tokens[8].Text);
    Assert.AreEqual<TType1TokenKind>(TType1TokenKind.StartDict, Tokens[9].Kind);
    Assert.AreEqual<TType1TokenKind>(TType1TokenKind.Str, Tokens[10].Kind);
    Assert.AreEqual('string '#10' '#10' '#9' '#8' '#12' \ ( ) ' + Chr($53), Tokens[10].Text);
    Assert.AreEqual<TType1TokenKind>(TType1TokenKind.EndDict, Tokens[11].Kind);
  finally
    Lexer.Free;
  end;
end;

procedure TType1LexerTests.TestData;
begin
  const Lexer = LexerFor('3 RD 123 ND');
  try
    const Tokens = ReadAll(Lexer);

    Assert.AreEqual<Integer>(3, Length(Tokens));
    Assert.AreEqual<TType1TokenKind>(TType1TokenKind.Int, Tokens[0].Kind);
    Assert.AreEqual(3, Tokens[0].IntValue);
    Assert.AreEqual<TType1TokenKind>(TType1TokenKind.CharString, Tokens[1].Kind);
    Assert.AreEqual<TBytes>(AsciiBytes('123'), Tokens[1].Data);
    Assert.AreEqual<TType1TokenKind>(TType1TokenKind.Name, Tokens[2].Kind);
    Assert.AreEqual('ND', Tokens[2].Text);
  finally
    Lexer.Free;
  end;
end;

procedure TType1LexerTests.TestStringLengthLargerThanInputRaises;
begin
  // PDFBOX-6043
  var Message := '';
  try
    const Lexer = LexerFor('999 RD');
    try
      ReadAll(Lexer);
    finally
      Lexer.Free;
    end;
  except
    on E: EPdfParseException do
    begin
      Message := E.Message;
    end;
  end;

  Assert.AreEqual('String length 999 is larger than input', Message);
end;

procedure TType1LexerTests.TestRDWithoutIntegerRaises;
begin
  CheckLexerRaises('/a RD 1234 ');
end;

procedure TType1LexerTests.TestNegativeStringLengthRaises;
begin
  CheckLexerRaises('-5 RD abcdefgh ');
end;

procedure TType1LexerTests.TestCharStringBeyondDataRaises;
begin
  CheckLexerRaises('10 RD abc');
end;

procedure TType1LexerTests.TestUnterminatedStringEndsTheTokens;
begin
  const Lexer = LexerFor('/a (never closed \( ');
  try
    const Tokens = ReadAll(Lexer);

    Assert.AreEqual<Integer>(1, Length(Tokens));
    Assert.AreEqual('a', Tokens[0].Text);
  finally
    Lexer.Free;
  end;
end;

procedure TType1LexerTests.TestClosingParenthesisOutsideStringRaises;
begin
  CheckLexerRaises('/a ) ');
end;

procedure TType1LexerTests.TestInvalidRadixRaises;
begin
  CheckLexerRaises('99#1 ');
  CheckLexerRaises('1#1 ');
  CheckLexerRaises('8#9 ');
  CheckLexerRaises('10#99999999999 ');
end;

procedure TType1LexerTests.TestInvalidOctalEscapeRaises;
begin
  CheckLexerRaises('(a\8 ) ');
  CheckLexerRaises('(a\129) ');
  CheckLexerRaises('(a\12');
end;

procedure TType1LexerTests.TestNumberAtTheEndOfTheDataRaises;
begin
  // PDFBox reads one character past the number and runs into the end of its buffer
  CheckLexerRaises('/a 123');
end;

procedure TType1LexerTests.TestProcedureNestingLimitIsEnforced;
begin
  CheckLexerRaises(StringOfChar('{', 10000));
  CheckLexerRaises(StringOfChar('{', MaxProcedureDepth + 1) + ' ');
end;

procedure TType1LexerTests.TestProcedureNestingAtTheLimitIsAccepted;
begin
  const Lexer = LexerFor(StringOfChar('{', MaxProcedureDepth) + StringOfChar('}', MaxProcedureDepth) + ' ');
  try
    const Tokens = ReadAll(Lexer);

    Assert.AreEqual<Integer>(MaxProcedureDepth * 2, Length(Tokens));
  finally
    Lexer.Free;
  end;
end;

procedure TType1LexerTests.TestHugeNameIsRead;
begin
  const Lexer = LexerFor('/' + StringOfChar('x', 2000000) + ' ');
  try
    const Tokens = ReadAll(Lexer);

    Assert.AreEqual<Integer>(1, Length(Tokens));
    Assert.AreEqual<Integer>(2000000, Length(Tokens[0].Text));
  finally
    Lexer.Free;
  end;
end;

procedure TType1LexerTests.TestHugeUnterminatedArrayDoesNotHang;
begin
  const Lexer = LexerFor(StringOfChar('[', 2000000));
  try
    const Tokens = ReadAll(Lexer);

    Assert.AreEqual<Integer>(2000000, Length(Tokens));
  finally
    Lexer.Free;
  end;
end;

{ TType1FontTests }

class function TType1FontTests.AsciiBytes(const Text: string): TBytes;
begin
  Result := TEncoding.ASCII.GetBytes(Text);
end;

class function TType1FontTests.Bytes(const Values: array of Byte): TBytes;
begin
  SetLength(Result, Length(Values));
  for var Index := 0 to High(Values) do
  begin
    Result[Index] := Values[Index];
  end;
end;

class function TType1FontTests.Join(const Parts: array of TBytes): TBytes;
begin
  Result := nil;
  for var Part in Parts do
  begin
    const Start = Length(Result);
    SetLength(Result, Start + Length(Part));
    if Length(Part) > 0 then
    begin
      Move(Part[0], Result[Start], Length(Part));
    end;
  end;
end;

class function TType1FontTests.DefaultOptions: TType1TestFont;
begin
  Result.LenIV := 4;
  Result.HexEexec := False;
  Result.BuiltInEncoding := False;
end;

procedure TType1FontTests.TearDown;
begin
  FreeAndNil(FFont);
end;

// "name len RD <data> ND" with the data encrypted the way lenIV says
class function TType1FontTests.CharStringEntry(const Name: string; const CharString: TBytes; const LenIV: Integer): TBytes;
begin
  var Data := CharString;
  if LenIV >= 0 then
  begin
    Data := TType1FontUtil.CharstringEncrypt(CharString, LenIV);
  end;
  Result := Join([AsciiBytes(Format('/%s %d RD ', [Name, Length(Data)])), Data, AsciiBytes(' ND'#10)]);
end;

class function TType1FontTests.HeaderText(const BuiltInEncoding: Boolean): string;
begin
  var EncodingText := '/Encoding StandardEncoding def'#10;
  if BuiltInEncoding then
  begin
    EncodingText := '/Encoding 256 array'#10'0 1 255 {1 index exch /.notdef put} for'#10'dup 65 /A put'#10'dup 66 /B put'#10 +
                    'readonly def'#10;
  end;

  Result := '%!PS-AdobeFont-1.0: TestFont 1.0'#10 +
            '11 dict begin'#10 +
            '/FontInfo 4 dict dup begin'#10 +
            '/version (1.5) readonly def'#10 +
            '/FullName (Test Full) readonly def'#10 +
            '/ItalicAngle -12.5 def'#10 +
            '/isFixedPitch true def'#10 +
            'end readonly def'#10 +
            '/FontName /TestFont def'#10 +
            '/PaintType 0 def'#10 +
            '/FontType 1 def'#10 +
            '/FontMatrix [0.001 0 0 0.001 0 0] readonly def'#10 +
            EncodingText +
            '/FontBBox {-10 -20 1000 900} readonly def'#10 +
            'currentdict end'#10 +
            'currentfile eexec'#10;
end;

class function TType1FontTests.PrivateSection(const LenIV: Integer): TBytes;
begin
  const Notdef = TType1FontTests.Bytes([139, 247, 142, 13, 14]);
  const GlyphA = TType1FontTests.Bytes([139, 248, 136, 13, 14]);
  const GlyphB = TType1FontTests.Bytes([139, 248, 236, 13, 14]);
  const GlyphC = TType1FontTests.Bytes([139, 10, 14]);
  const Subr0 = TType1FontTests.Bytes([139, 249, 80, 13, 11]);

  var LenIVText := '';
  if LenIV <> 4 then
  begin
    LenIVText := Format('/lenIV %d def'#10, [LenIV]);
  end;
  var SubrData := Subr0;
  if LenIV >= 0 then
  begin
    SubrData := TType1FontUtil.CharstringEncrypt(Subr0, LenIV);
  end;

  Result := Join([
    AsciiBytes('dup /Private 8 dict dup begin'#10 +
               '/RD {string currentfile exch readstring pop} executeonly def'#10 +
               '/ND {noaccess def} executeonly def'#10 +
               '/NP {noaccess put} executeonly def'#10 +
               '/BlueValues [-10 0 700 710] def'#10 +
               LenIVText +
               '/Subrs 1 array'#10),
    AsciiBytes(Format('dup 0 %d RD ', [Length(SubrData)])), SubrData, AsciiBytes(' NP'#10'ND'#10),
    AsciiBytes('2 index /CharStrings 4 dict dup begin'#10),
    CharStringEntry('.notdef', Notdef, LenIV),
    CharStringEntry('A', GlyphA, LenIV),
    CharStringEntry('B', GlyphB, LenIV),
    CharStringEntry('C', GlyphC, LenIV),
    AsciiBytes('end end readonly put noaccess put'#10'dup /FontName get exch definefont pop'#10 +
               'mark currentfile closefile'#10)]);
end;

class function TType1FontTests.EncryptedSegment(const PrivatePlain: TBytes; const HexEexec: Boolean): TBytes;
begin
  const Encrypted = TType1FontUtil.EexecEncrypt(PrivatePlain);
  if not HexEexec then
  begin
    Exit(Encrypted);
  end;
  Result := AsciiBytes(TType1FontUtil.HexEncode(Encrypted));
end;

class function TType1FontTests.SyntheticSegments(const Options: TType1TestFont; out Segment2: TBytes): TBytes;
begin
  Result := AsciiBytes(HeaderText(Options.BuiltInEncoding));
  Segment2 := EncryptedSegment(PrivateSection(Options.LenIV), Options.HexEexec);
end;

procedure TType1FontTests.LoadSynthetic(const Options: TType1TestFont);
begin
  var Segment2: TBytes;
  const Segment1 = SyntheticSegments(Options, Segment2);
  FreeAndNil(FFont);
  FFont := TType1Font.CreateWithSegments(Segment1, Segment2);
end;

procedure TType1FontTests.CheckFontRaises(const Segment1, Segment2: TBytes);
begin
  var Failed := False;
  try
    TType1Font.CreateWithSegments(Segment1, Segment2).Free;
  except
    on EPdfParseException do
    begin
      Failed := True;
    end;
  end;
  Assert.IsTrue(Failed, 'The font must give an EPdfParseException');
end;

procedure TType1FontTests.CheckSyntheticWidths;
begin
  Assert.AreEqual<Single>(AWidth, FFont.GetWidth('A'));
  Assert.AreEqual<Single>(BWidth, FFont.GetWidth('B'));
  Assert.AreEqual<Single>(CWidth, FFont.GetWidth('C'));
  Assert.AreEqual<Single>(NotdefWidth, FFont.GetWidth('.notdef'));
  Assert.AreEqual(4, Integer(FFont.CharStringsDict.Count));
  Assert.AreEqual<Integer>(1, Length(FFont.Subrs));
end;

procedure TType1FontTests.CheckOpenSans(const Font: TType1Font);
begin
  Assert.AreEqual('1.10', Font.Version);
  Assert.AreEqual('OpenSans-Regular', Font.FontName);
  Assert.AreEqual('OpenSans-Regular', Font.Name);
  Assert.AreEqual('Open Sans Regular', Font.FullName);
  Assert.AreEqual('Open Sans', Font.FamilyName);
  Assert.AreEqual('Digitized data copyright (c) 2010-2011, Google Corporation.', Font.Notice);
  Assert.IsFalse(Font.IsFixedPitch);
  Assert.IsFalse(Font.IsForceBold);
  Assert.AreEqual<Single>(0, Font.ItalicAngle);
  Assert.AreEqual('Book', Font.Weight);
  Assert.IsTrue(Font.Encoding is TFontBoxBuiltInEncoding);
  Assert.AreEqual<Integer>(4498, Length(Font.ASCIISegment));
  Assert.AreEqual<Integer>(95911, Length(Font.BinarySegment));
  Assert.AreEqual(938, Integer(Font.CharStringsDict.Count));
end;

procedure TType1FontTests.CheckAllNamesAnswer(const Font: TType1Font);
begin
  for var Pair in Font.CharStringsDict do
  begin
    Assert.IsTrue(Font.HasGlyph(Pair.Key));
    Font.GetWidth(Pair.Key);
  end;
end;

procedure TType1FontTests.TestOpenSansProperties;
begin
  FFont := TType1Font.CreateWithPFB(TTestFonts.Bytes(OpenSansFile));

  CheckOpenSans(FFont);
  CheckAllNamesAnswer(FFont);
end;

procedure TType1FontTests.TestPfbWithSeveralBinarySegments;
begin
  // PDFBOX-5713
  FFont := TType1Font.CreateWithPFB(TTestFonts.Bytes(DejaVuFile));

  Assert.AreEqual('Version 2.33', FFont.Version);
  Assert.AreEqual('DejaVuSerifCondensed', FFont.FontName);
  Assert.AreEqual('DejaVu Serif Condensed', FFont.FullName);
  Assert.AreEqual('DejaVu Serif Condensed', FFont.FamilyName);
  Assert.AreEqual('Copyright [c] 2003 by Bitstream, Inc. All Rights Reserved.', FFont.Notice);
  Assert.IsFalse(FFont.IsFixedPitch);
  Assert.IsFalse(FFont.IsForceBold);
  Assert.AreEqual<Single>(0, FFont.ItalicAngle);
  Assert.AreEqual('Book', FFont.Weight);
  Assert.IsTrue(FFont.Encoding is TFontBoxBuiltInEncoding);
  Assert.AreEqual<Integer>(5959, Length(FFont.ASCIISegment));
  Assert.AreEqual<Integer>(1056090, Length(FFont.BinarySegment));
  Assert.AreEqual(3399, Integer(FFont.CharStringsDict.Count));
end;

procedure TType1FontTests.TestOpenSansBoxAndMatrix;
begin
  FFont := TType1Font.CreateWithPFB(TTestFonts.Bytes(OpenSansFile));

  const Box = FFont.FontBBox;
  const Matrix = FFont.FontMatrix;

  Assert.IsTrue(Box.Width > 0);
  Assert.IsTrue(Box.Height > 0);
  Assert.AreEqual<Integer>(6, Length(Matrix));
  // 2048 units per em
  Assert.AreEqual(Double(0.000488281), Double(Matrix[0]), 1E-9);
  Assert.IsTrue(FFont.Subrs <> nil);
  Assert.IsTrue(FFont.HasGlyph('A'));
  Assert.IsFalse(FFont.HasGlyph('no-such-glyph'));
end;

procedure TType1FontTests.CheckReferenceWidths(const FontFile: string);
begin
  const Reference = TTestFonts.ReferenceWidths(FontFile);
  try
    FreeAndNil(FFont);
    FFont := TType1Font.CreateWithPFB(TTestFonts.Bytes(FontFile));

    Assert.IsTrue(Reference.Count > 0);
    for var Pair in Reference do
    begin
      Assert.AreEqual<Single>(Pair.Value, FFont.GetWidth(Pair.Key), Format('Width of %s in %s', [Pair.Key, FontFile]));
    end;
  finally
    Reference.Free;
  end;
end;

procedure TType1FontTests.TestType1WidthsMatchReference;
begin
  CheckReferenceWidths(OpenSansFile);
end;

procedure TType1FontTests.TestType1WidthsMatchReferenceOfSecondFont;
begin
  CheckReferenceWidths(DejaVuFile);
end;

procedure TType1FontTests.TestEmptyPfbRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      TType1Font.CreateWithPFB(nil).Free;
    end,
    EPdfParseException);
end;

procedure TType1FontTests.TestBrokenEexecRaisesParseError;
begin
  const Font = TType1Font.CreateWithPFB(TTestFonts.Bytes(OpenSansFile));
  var Segment1: TBytes;
  try
    Segment1 := Font.ASCIISegment;
  finally
    Font.Free;
  end;

  var Junk: TBytes;
  SetLength(Junk, 200);
  RandSeed := 7;
  for var Index := 0 to High(Junk) do
  begin
    Junk[Index] := Byte(Random(256));
  end;

  CheckFontRaises(Segment1, Junk);
end;

procedure TType1FontTests.TestDeepProcedureNesting;
begin
  CheckFontRaises(AsciiBytes(StringOfChar('{', 10000)), nil);
end;

procedure TType1FontTests.TestDeepProcedureNestingInTheHeader;
begin
  // Reaches the procedure that the parser skips, not the check of the first bytes
  const Header = '%!PS-AdobeFont-1.0'#10'FontDirectory /F known {' + StringOfChar('{', 10000) + ' ';

  CheckFontRaises(AsciiBytes(Header), nil);
end;

procedure TType1FontTests.TestSyntheticFontParses;
begin
  LoadSynthetic(DefaultOptions);

  CheckSyntheticWidths;
  Assert.AreEqual('TestFont', FFont.FontName);
  Assert.AreEqual('1.5', FFont.Version);
  Assert.AreEqual('Test Full', FFont.FullName);
  Assert.AreEqual<Single>(-12.5, FFont.ItalicAngle);
  Assert.IsTrue(FFont.IsFixedPitch);
  Assert.AreEqual(0, FFont.PaintType);
  Assert.AreEqual(1, FFont.FontType);
  Assert.IsTrue(FFont.Encoding = TFontBoxEncoding(TFontBoxStandardEncoding.Instance));
  Assert.AreEqual<Integer>(4, Length(FFont.BlueValues));
  Assert.AreEqual<Single>(700, FFont.BlueValues[2]);

  const Box = FFont.FontBBox;
  Assert.AreEqual<Single>(-10, Box.LowerLeftX);
  Assert.AreEqual<Single>(-20, Box.LowerLeftY);
  Assert.AreEqual<Single>(1000, Box.UpperRightX);
  Assert.AreEqual<Single>(900, Box.UpperRightY);
end;

procedure TType1FontTests.TestSyntheticFontWithBuiltInEncoding;
begin
  var Options := DefaultOptions;
  Options.BuiltInEncoding := True;

  LoadSynthetic(Options);

  Assert.IsTrue(FFont.Encoding is TFontBoxBuiltInEncoding);
  Assert.AreEqual('A', FFont.Encoding.GetName(65));
  Assert.AreEqual('B', FFont.Encoding.GetName(66));
  Assert.AreEqual('.notdef', FFont.Encoding.GetName(67));
  CheckSyntheticWidths;
end;

procedure TType1FontTests.TestLenIVZero;
begin
  var Options := DefaultOptions;
  Options.LenIV := 0;

  LoadSynthetic(Options);

  CheckSyntheticWidths;
end;

procedure TType1FontTests.TestLenIVMinusOneMeansNotEncrypted;
begin
  var Options := DefaultOptions;
  Options.LenIV := -1;

  LoadSynthetic(Options);

  CheckSyntheticWidths;
  Assert.AreEqual<TBytes>(Bytes([139, 248, 136, 13, 14]), FFont.CharStringsDict['A']);
end;

procedure TType1FontTests.TestLenIVBelowMinusOneRaises;
begin
  var Options := DefaultOptions;
  Options.LenIV := -2;
  var Segment2: TBytes;
  const Segment1 = SyntheticSegments(Options, Segment2);

  CheckFontRaises(Segment1, Segment2);
end;

procedure TType1FontTests.TestHexEexecIsDetected;
begin
  var Options := DefaultOptions;
  Options.HexEexec := True;

  LoadSynthetic(Options);

  CheckSyntheticWidths;
end;

procedure TType1FontTests.TestHexEexecWithSpacesIsDetected;
begin
  var Options := DefaultOptions;
  Options.HexEexec := True;
  var Segment2: TBytes;
  const Segment1 = SyntheticSegments(Options, Segment2);
  // Line breaks and spaces between the digits are skipped
  const Text = TEncoding.ASCII.GetString(Segment2);
  var Spaced := '';
  for var Index := 1 to Length(Text) do
  begin
    Spaced := Spaced + Text[Index];
    if (Index mod 64) = 0 then
    begin
      Spaced := Spaced + #13#10;
    end
    else if (Index mod 10) = 0 then
    begin
      Spaced := Spaced + ' ';
    end;
  end;

  FFont := TType1Font.CreateWithSegments(Segment1, AsciiBytes(Spaced));

  CheckSyntheticWidths;
end;

procedure TType1FontTests.TestCharStringShorterThanLenIVIsEmpty;
begin
  const Private = Join([
    AsciiBytes('dup /Private 3 dict dup begin'#10 +
               '/RD {string currentfile exch readstring pop} executeonly def'#10 +
               '/ND {noaccess def} executeonly def'#10 +
               '2 index /CharStrings 2 dict dup begin'#10 +
               '/.notdef 2 RD ab ND'#10 +
               '/zero 0 RD  ND'#10 +
               'end end'#10)]);

  FFont := TType1Font.CreateWithSegments(AsciiBytes(HeaderText(False)), EncryptedSegment(Private, False));

  Assert.AreEqual<Integer>(0, Length(FFont.CharStringsDict['.notdef']));
  Assert.AreEqual<Integer>(0, Length(FFont.CharStringsDict['zero']));
  Assert.AreEqual<Single>(0, FFont.GetWidth('.notdef'));
end;

procedure TType1FontTests.TestShortEexecDataRaises;
begin
  CheckFontRaises(AsciiBytes(HeaderText(False)), Bytes([1, 2, 3]));
  CheckFontRaises(AsciiBytes(HeaderText(False)), Bytes([1, 2, 3, 4]));
end;

procedure TType1FontTests.TestEmptyBinarySegmentGivesFontWithoutGlyphs;
begin
  FFont := TType1Font.CreateWithSegments(AsciiBytes(HeaderText(False)), nil);

  Assert.AreEqual('TestFont', FFont.FontName);
  Assert.AreEqual(0, Integer(FFont.CharStringsDict.Count));
  Assert.IsFalse(FFont.HasGlyph('A'));
end;

procedure TType1FontTests.TestEmptyAsciiSegmentRaises;
begin
  CheckFontRaises(nil, Bytes([1, 2, 3, 4, 5]));
  CheckFontRaises(AsciiBytes('   '#10'  '), nil);
  CheckFontRaises(AsciiBytes('x'), nil);
end;

procedure TType1FontTests.TestMissingEexecRaises;
begin
  const Header = StringReplace(HeaderText(False), 'currentfile eexec'#10, '', []);
  var Segment2: TBytes;
  SyntheticSegments(DefaultOptions, Segment2);

  CheckFontRaises(AsciiBytes(Header), Segment2);
end;

procedure TType1FontTests.TestMissingPrivateRaises;
begin
  const Private = AsciiBytes('/Nothing 1 def'#10'/Else 2 def'#10);

  CheckFontRaises(AsciiBytes(HeaderText(False)), EncryptedSegment(Private, False));
end;

procedure TType1FontTests.TestMissingCharStringsRaises;
begin
  const Private = AsciiBytes('dup /Private 2 dict dup begin'#10'/RD {string currentfile exch readstring pop} executeonly def'#10 +
                             'end end'#10);

  CheckFontRaises(AsciiBytes(HeaderText(False)), EncryptedSegment(Private, False));
end;

procedure TType1FontTests.TestSubrsCountBeyondDataRaises;
begin
  const Private = AsciiBytes('dup /Private 2 dict dup begin'#10'/Subrs 2000000000 array'#10'dup 0 1 RD a NP'#10'ND'#10);

  CheckFontRaises(AsciiBytes(HeaderText(False)), EncryptedSegment(Private, False));
end;

procedure TType1FontTests.TestNegativeSubrIndexRaises;
begin
  const Private = AsciiBytes('dup /Private 2 dict dup begin'#10'/Subrs 2 array'#10'dup -1 1 RD a NP'#10'ND'#10);

  CheckFontRaises(AsciiBytes(HeaderText(False)), EncryptedSegment(Private, False));
end;

procedure TType1FontTests.TestSubrIndexBeyondCountIsIgnored;
begin
  const Private = Join([
    AsciiBytes('dup /Private 3 dict dup begin'#10 +
               '/RD {string currentfile exch readstring pop} executeonly def'#10 +
               '/ND {noaccess def} executeonly def'#10 +
               '/Subrs 1 array'#10'dup 5 5 RD abcde NP'#10'ND'#10 +
               '2 index /CharStrings 1 dict dup begin'#10 +
               '/.notdef 5 RD abcde ND'#10 +
               'end end'#10)]);

  FFont := TType1Font.CreateWithSegments(AsciiBytes(HeaderText(False)), EncryptedSegment(Private, False));

  Assert.AreEqual<Integer>(1, Length(FFont.Subrs));
  Assert.AreEqual<Integer>(0, Length(FFont.Subrs[0]));
end;

procedure TType1FontTests.TestCharStringLengthBeyondDataRaises;
begin
  const Private = AsciiBytes('dup /Private 3 dict dup begin'#10 +
                             '/RD {string currentfile exch readstring pop} executeonly def'#10 +
                             '2 index /CharStrings 1 dict dup begin'#10 +
                             '/A 99999 RD abc ND'#10'end end'#10);

  CheckFontRaises(AsciiBytes(HeaderText(False)), EncryptedSegment(Private, False));
end;

procedure TType1FontTests.TestCharStringsCountBeyondDataIsLenient;
begin
  const Private = AsciiBytes('dup /Private 3 dict dup begin'#10 +
                             '/RD {string currentfile exch readstring pop} executeonly def'#10 +
                             '2 index /CharStrings 5000 dict dup begin'#10 +
                             '/.notdef 5 RD abcde ND'#10'end end'#10);

  FFont := TType1Font.CreateWithSegments(AsciiBytes(HeaderText(False)), EncryptedSegment(Private, False));

  Assert.AreEqual(1, Integer(FFont.CharStringsDict.Count));
end;

procedure TType1FontTests.TestCharStringsCountBelowActualCountRaises;
begin
  const Private = AsciiBytes('dup /Private 3 dict dup begin'#10 +
                             '/RD {string currentfile exch readstring pop} executeonly def'#10 +
                             '2 index /CharStrings 1 dict dup begin'#10 +
                             '/.notdef 5 RD abcde ND'#10'/A 5 RD abcde ND'#10'end end'#10);

  CheckFontRaises(AsciiBytes(HeaderText(False)), EncryptedSegment(Private, False));
end;

procedure TType1FontTests.TestUnterminatedProcedureRaises;
begin
  const Header = '%!PS-AdobeFont-1.0'#10'11 dict begin'#10'/FontBBox {1 2 3 4'#10;
  const Private = AsciiBytes('dup /Private 3 dict dup begin'#10'/RD {string currentfile exch');

  CheckFontRaises(AsciiBytes(Header), nil);
  CheckFontRaises(AsciiBytes(HeaderText(False)), EncryptedSegment(Private, False));
end;

procedure TType1FontTests.TestWrappedValuesAreBounded;
begin
  var Header := '%!PS-AdobeFont-1.0'#10'11 dict begin'#10'/FontName ';
  for var Index := 1 to 5000 do
  begin
    Header := Header + 'x systemdict /internaldict known {} {} ifelse {pop ';
  end;

  CheckFontRaises(AsciiBytes(Header), nil);
end;

procedure TType1FontTests.TestUnknownGlyphGetsNotdefWidth;
begin
  LoadSynthetic(DefaultOptions);

  Assert.AreEqual<Single>(NotdefWidth, FFont.GetWidth('no-such-glyph'));
  Assert.IsFalse(FFont.HasGlyph('no-such-glyph'));
end;

procedure TType1FontTests.TestGetWidthWithoutNotdefRaises;
begin
  const Private = AsciiBytes('dup /Private 3 dict dup begin'#10 +
                             '/RD {string currentfile exch readstring pop} executeonly def'#10 +
                             '2 index /CharStrings 1 dict dup begin'#10 +
                             '/A 5 RD abcde ND'#10'end end'#10);
  FFont := TType1Font.CreateWithSegments(AsciiBytes(HeaderText(False)), EncryptedSegment(Private, False));

  Assert.WillRaise(
    procedure
    begin
      FFont.GetWidth('B');
    end,
    EPdfParseException);
end;

procedure TType1FontTests.TestFontBBoxWithoutNumbersRaises;
begin
  const Header = StringReplace(HeaderText(False), '/FontBBox {-10 -20 1000 900} readonly def'#10, '', []);
  var Segment2: TBytes;
  SyntheticSegments(DefaultOptions, Segment2);
  FFont := TType1Font.CreateWithSegments(AsciiBytes(Header), Segment2);

  Assert.WillRaise(
    procedure
    begin
      FFont.FontBBox;
    end,
    EPdfParseException);
end;

procedure TType1FontTests.TestUnknownEncodingNameRaises;
begin
  const Header = StringReplace(HeaderText(False), 'StandardEncoding', 'MyEncoding', []);

  CheckFontRaises(AsciiBytes(Header), nil);
end;

procedure TType1FontTests.TestFontInfoWithoutValueRaises;
begin
  const Header = '%!PS-AdobeFont-1.0'#10'11 dict begin'#10'/FontInfo 1 dict dup begin'#10'/Notice def'#10'end readonly def'#10 +
                 'currentdict end'#10'currentfile eexec'#10;

  CheckFontRaises(AsciiBytes(Header), nil);
end;

procedure TType1FontTests.TestMutatedSyntheticFontEndsCleanly;
begin
  var Segment2Unused: TBytes;
  const Segment1 = SyntheticSegments(DefaultOptions, Segment2Unused);
  const PrivatePlain = PrivateSection(DefaultOptions.LenIV);

  RandSeed := 11;
  for var Round := 1 to 400 do
  begin
    var Header := Copy(Segment1, 0, Length(Segment1));
    var Plain := Copy(PrivatePlain, 0, Length(PrivatePlain));
    for var Flip := 1 to 1 + Random(3) do
    begin
      if Random(2) = 0 then
      begin
        Header[Random(Length(Header))] := Byte(Random(256));
      end
      else
      begin
        Plain[Random(Length(Plain))] := Byte(Random(256));
      end;
    end;

    var Font: TType1Font := nil;
    try
      try
        Font := TType1Font.CreateWithSegments(Header, EncryptedSegment(Plain, Random(2) = 0));
        for var Pair in Font.CharStringsDict do
        begin
          Font.GetWidth(Pair.Key);
        end;
      except
        on EPdfParseException do
        begin
          // A clean failure is a valid result for a damaged font
        end;
      end;
    finally
      Font.Free;
    end;
  end;
  Assert.IsTrue(True);
end;

procedure TType1FontTests.TestMutatedOpenSansEndsCleanly;
begin
  const Original = TType1Font.CreateWithPFB(TTestFonts.Bytes(OpenSansFile));
  var Segment1: TBytes;
  var Segment2: TBytes;
  try
    Segment1 := Original.ASCIISegment;
    Segment2 := Original.BinarySegment;
  finally
    Original.Free;
  end;

  RandSeed := 23;
  for var Round := 1 to 60 do
  begin
    var Header := Copy(Segment1, 0, Length(Segment1));
    var Binary := Copy(Segment2, 0, Length(Segment2));
    if Random(2) = 0 then
    begin
      Header[Random(Length(Header))] := Byte(Random(256));
    end
    else
    begin
      // The key chain of eexec carries a change to the end of the segment, so the rest turns into noise
      Binary[Random(Length(Binary))] := Byte(Random(256));
    end;
    if Random(4) = 0 then
    begin
      SetLength(Binary, Random(Length(Binary)));
    end;

    var Font: TType1Font := nil;
    try
      try
        Font := TType1Font.CreateWithSegments(Header, Binary);
        for var Pair in Font.CharStringsDict do
        begin
          Font.GetWidth(Pair.Key);
        end;
      except
        on EPdfParseException do
        begin
          // A clean failure is a valid result for a damaged font
        end;
      end;
    finally
      Font.Free;
    end;
  end;
  Assert.IsTrue(True);
end;

end.
