// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/test/java/org/apache/fontbox/cmap/TestCMapParser.java (3.0.8)
// Port of: fontbox/src/test/java/org/apache/fontbox/cmap/TestCMap.java (3.0.8)
// Port of: fontbox/src/test/java/org/apache/fontbox/cmap/TestCodespaceRange.java (3.0.8)
// Port of: fontbox/src/test/java/org/apache/fontbox/cmap/CIDRangeTest.java (3.0.8)
// Port of: fontbox/src/test/java/org/apache/fontbox/cmap/CMapStringsTest.java (3.0.8)
unit Pdf4D.FontBox.CMapParser.Tests;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Common.Defines,
  Pdf4D.Common.Log,
  Pdf4D.FontBox.CMap,
  Pdf4D.FontBox.CMapParser;

type
  [TestFixture]
  TCodespaceRangeTests = class
  public
    [Test]
    procedure TestCodeLength;

    [Test]
    procedure TestConstructor;

    [Test]
    procedure TestMatches;
  end;

  [TestFixture]
  TCIDRangeTests = class
  public
    [Test]
    procedure TestCIDRange;

    [Test]
    procedure TestCIDRangeTwoByte;

    [Test]
    procedure TestExtendOnlyContinuesTheRange;

    [Test]
    procedure TestExtendDoesNotOverflow;
  end;

  [TestFixture]
  TCMapStringsTests = class
  public
    [Test]
    procedure GetNonCachedValues;

    [Test]
    procedure GetMappingOneByte;

    [Test]
    procedure GetMappingTwoByte;

    [Test]
    procedure GetMappingOfSurrogateGivesReplacementCharacter;

    [Test]
    procedure GetByteValues;

    [Test]
    procedure GetIndexValues;

    [Test]
    procedure DecodeUtf16BigEndianLikeJava;
  end;

  [TestFixture]
  TCMapTests = class
  public
    [Test]
    procedure TestLookup;

    [Test]
    procedure TestReadCodeWithMixedCodeLengths;

    [Test]
    procedure TestReadCodeWithoutMatchUsesMinimumLength;

    [Test]
    procedure TestReadCodeAtEndOfDataDoesNotMove;

    [Test]
    procedure TestReadCodeWithoutCodespaceReadsOneByte;

    [Test]
    procedure TestEmptyCodespaceRangeIsIgnored;

    [Test]
    procedure TestSpaceMapping;

    [Test]
    procedure TestMappingsStopAtTheLimit;
  end;

  [TestFixture]
  TCMapParserTests = class
  private
    FMessages: TList<string>;
    FLog: TPdfLog;

    function ParseText(const Text: string; const StrictMode: Boolean = False): TCMap;
    function ParsePredefined(const Name: string): TCMap;
    function HasWarning(const Fragment: string): Boolean;
    procedure ParseNestedArrays;
    procedure ParseUnknownUseCMap;
    procedure ParseHugeToken;
    procedure ParseBadNumber;
    procedure ParseBadCodespace;
    procedure ParseMissingBfCharValue;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestLookup;

    [Test]
    procedure TestIdentity;

    [Test]
    procedure TestUniJIS_UTF16_H;

    [Test]
    procedure TestUniJIS_UCS2_H;

    [Test]
    procedure TestAdobe_GB1_UCS2;

    [Test]
    procedure TestParserWithPoorWhitespace;

    [Test]
    procedure TestParserWithMalformedbfrange1;

    [Test]
    procedure TestParserWithMalformedbfrange2;

    [Test]
    procedure TestPredefinedMap;

    [Test]
    procedure TestIdentitybfrange;

    [Test]
    procedure TestBadIncrement;

    [Test]
    procedure TestHeaderFieldsAreRead;

    [Test]
    procedure TestBfCharWithLiteralName;

    [Test]
    procedure TestHugeBfRangeIsBounded;

    [Test]
    procedure TestHugeBfRangeBelowSignedLimitIsBounded;

    [Test]
    procedure TestRepeatedUseCMapIsBounded;

    [Test]
    procedure TestNestedArraysRaiseParseError;

    [Test]
    procedure TestUnknownUseCMapRaisesParseError;

    [Test]
    procedure TestHexTokenLargerThanBufferRaisesParseError;

    [Test]
    procedure TestInvalidNumberRaisesParseError;

    [Test]
    procedure TestCodespaceWithDifferentLengthsRaisesParseError;

    [Test]
    procedure TestMissingBfCharValueRaisesParseError;

    [Test]
    procedure TestTruncatedDataEndsWithoutHang;
  end;

implementation

uses
  System.Diagnostics,
  Pdf4D.IO.RandomAccessRead;

const
  CMapTestText =
    '1 begincodespacerange<0000> <02FF>' + sLineBreak +
    'endcodespacerange' + sLineBreak +
    '2 beginbfchar' + sLineBreak +
    '<000A> <002A>' + sLineBreak +
    '<010A> <002B>' + sLineBreak +
    'endbfchar' + sLineBreak +
    '3 beginbfrange' + sLineBreak +
    '<0001> <0005> <0041>' + sLineBreak +
    '<0100> <0109> <0030>' + sLineBreak +
    '<0120> <0122> [<0050> <0052> <0054>]' + sLineBreak +
    'endbfrange' + sLineBreak +
    '3 begincidchar' + sLineBreak +
    '<0200> 512' + sLineBreak +
    '<0208> 520' + sLineBreak +
    '<020A> 522' + sLineBreak +
    'endcidchar' + sLineBreak +
    '2 begincidrange' + sLineBreak +
    '<0000> <00ff> 0' + sLineBreak +
    '<0100> <01ff> 256' + sLineBreak +
    '<0300> <0300> 300' + sLineBreak +
    'endcidrange' + sLineBreak +
    'endcmap' + sLineBreak +
    '%%EndResource' + sLineBreak +
    '%%EOF' + sLineBreak;

  PoorWhitespaceText =
    '/CIDInit /ProcSet findresource begin 12 dict begin begincmap /CIDSystemInfo <</Registry (DDACTR+F1+0) ' +
    '/Ordering (0) /Supplement 0 >> def/CMapName /DDACTR+F1+0 def' + sLineBreak +
    '/CMapType 2 def1 begincodespacerange <0000> <FFFF> endcodespacerange7 beginbfchar<0003> <0020>' + sLineBreak +
    '<0011> <002e>' + sLineBreak +
    '<001a> <0037>' + sLineBreak +
    '<001b> <0038>' + sLineBreak +
    '<0026> <0043>' + sLineBreak +
    '<0083> <00b0>' + sLineBreak +
    '<00ed> <2212>' + sLineBreak +
    'endbfcharendcmap CMapName currentdict /CMap defineresource pop end end' + sLineBreak +
    '%%EndResource' + sLineBreak +
    '%%EOF' + sLineBreak;

  Malformedbfrange1Text =
    '1 begincodespacerange<0000> <02FF>' + sLineBreak +
    'endcodespacerange' + sLineBreak +
    '2 beginbfrange' + sLineBreak +
    '<0001> <0009> <0041>' + sLineBreak +
    '<0109> <0100> <0030>' + sLineBreak +
    'endbfrange' + sLineBreak +
    'endcmap' + sLineBreak;

  Malformedbfrange2Text =
    '1 begincodespacerange<0000> <04FF>' + sLineBreak +
    'endcodespacerange' + sLineBreak +
    '2 beginbfrange' + sLineBreak +
    '<0001> <0009> <0030>' + sLineBreak +
    '<0232> <0432> <0041>' + sLineBreak +
    'endbfrange' + sLineBreak +
    'endcmap' + sLineBreak;

  IdentitybfrangeText =
    '/CIDInit /ProcSet findresource begin' + sLineBreak +
    '12 dict begin' + sLineBreak +
    'begincmap' + sLineBreak +
    '/CIDSystemInfo' + sLineBreak +
    '<<' + sLineBreak +
    '/Registry (Adobe)' + sLineBreak +
    '/Ordering (UCS)' + sLineBreak +
    '/Supplement 0' + sLineBreak +
    '>> def' + sLineBreak +
    '/CMapName /Adobe-Identity-UCS def' + sLineBreak +
    '/CMapType 2 def' + sLineBreak +
    '1 begincodespacerange' + sLineBreak +
    '<0000> <ffff>' + sLineBreak +
    'endcodespacerange' + sLineBreak +
    '1 beginbfrange' + sLineBreak +
    '<0000> <ffff> <0000>' + sLineBreak +
    'endbfrange' + sLineBreak +
    'endcmap' + sLineBreak +
    'CMapName currentdict /CMap defineresource pop' + sLineBreak +
    'end' + sLineBreak +
    'end' + sLineBreak;

  HeaderText =
    '/CIDSystemInfo 3 dict dup begin' + sLineBreak +
    '  /Registry (Adobe) def' + sLineBreak +
    '  /Ordering (Japan1) def' + sLineBreak +
    '  /Supplement 4 def' + sLineBreak +
    'end def' + sLineBreak +
    '/CMapName /Test-H def' + sLineBreak +
    '/CMapVersion 12.002 def' + sLineBreak +
    '/CMapType 1 def' + sLineBreak +
    '/WMode 1 def' + sLineBreak +
    'endcmap' + sLineBreak;

function Bytes(const Values: array of Byte): TBytes;
begin
  SetLength(Result, Length(Values));
  for var Index := 0 to High(Values) do
  begin
    Result[Index] := Values[Index];
  end;
end;

function UnicodeOf(const CMap: TCMap; const Code: TBytes): string;
begin
  if not CMap.TryToUnicode(Code, Result) then
  begin
    Result := '<none>';
  end;
end;

function Utf16BigEndian(const Values: array of Byte): string;
begin
  Result := TEncoding.BigEndianUnicode.GetString(Bytes(Values));
end;

{ TCodespaceRangeTests }

procedure TCodespaceRangeTests.TestCodeLength;
begin
  const Range1 = TCodespaceRange.Create(Bytes([$00]), Bytes([$20]));
  Assert.AreEqual(1, Range1.CodeLength);

  const Range2 = TCodespaceRange.Create(Bytes([$00, $00]), Bytes([$01, $20]));
  Assert.AreEqual(2, Range2.CodeLength);
end;

procedure TCodespaceRangeTests.TestConstructor;
begin
  // "1 begincodespacerange <00> <ffff> endcodespacerange" is accepted
  const Range = TCodespaceRange.Create(Bytes([$00]), Bytes([$FF, $FF]));
  Assert.AreEqual(2, Range.CodeLength);
  Assert.IsTrue(Range.Matches(Bytes([$12, $34])));

  Assert.WillRaise(
    procedure
    begin
      TCodespaceRange.Create(Bytes([$01]), Bytes([$01, $20]));
    end,
    EArgumentException);
end;

procedure TCodespaceRangeTests.TestMatches;
begin
  const Range1 = TCodespaceRange.Create(Bytes([$00]), Bytes([$A0]));
  Assert.IsTrue(Range1.Matches(Bytes([$00])));
  Assert.IsTrue(Range1.Matches(Bytes([$A0])));
  Assert.IsTrue(Range1.Matches(Bytes([$10])));
  Assert.IsFalse(Range1.Matches(Bytes([$A1])));
  Assert.IsFalse(Range1.Matches(Bytes([$D0])));
  Assert.IsFalse(Range1.Matches(Bytes([$00, $10])));

  const Range2 = TCodespaceRange.Create(Bytes([$81, $40]), Bytes([$9F, $FC]));
  Assert.IsTrue(Range2.Matches(Bytes([$81, $40])));
  Assert.IsTrue(Range2.Matches(Bytes([$81, $FC])));
  Assert.IsTrue(Range2.Matches(Bytes([$9F, $40])));
  Assert.IsTrue(Range2.Matches(Bytes([$81, $65])));
  Assert.IsTrue(Range2.Matches(Bytes([$90, $40])));
  Assert.IsFalse(Range2.Matches(Bytes([$81, $FD])));
  Assert.IsFalse(Range2.Matches(Bytes([$A0, $40])));
  Assert.IsFalse(Range2.Matches(Bytes([$81, $20])));
  Assert.IsFalse(Range2.Matches(Bytes([$10, $40])));
  Assert.IsFalse(Range2.Matches(Bytes([$82, $20])));
  Assert.IsFalse(Range2.Matches(Bytes([$00])));
end;

{ TCIDRangeTests }

procedure TCIDRangeTests.TestCIDRange;
begin
  const Range = TCIDRange.Create(0, 20, 65, 1);
  Assert.AreEqual(1, Range.CodeLength);
  Assert.AreEqual(65, Range.Map(Bytes([0])));
  Assert.AreEqual(75, Range.Map(Bytes([10])));
  Assert.AreEqual(-1, Range.Map(Bytes([30])));
  Assert.AreEqual(-1, Range.Map(Bytes([0, 10])));

  Assert.AreEqual(65, Range.Map(0, 1));
  Assert.AreEqual(75, Range.Map(10, 1));
  Assert.AreEqual(-1, Range.Map(30, 1));
  Assert.AreEqual(-1, Range.Map(10, 2));

  Assert.AreEqual(0, Range.Unmap(65));
  Assert.AreEqual(10, Range.Unmap(75));
  Assert.AreEqual(-1, Range.Unmap(100));
end;

procedure TCIDRangeTests.TestCIDRangeTwoByte;
begin
  const Range = TCIDRange.Create(256, 280, 65, 2);
  Assert.AreEqual(2, Range.CodeLength);
  Assert.AreEqual(65, Range.Map(Bytes([1, 0])));
  Assert.AreEqual(75, Range.Map(Bytes([1, 10])));
  Assert.AreEqual(-1, Range.Map(Bytes([1, 30])));
  Assert.AreEqual(-1, Range.Map(Bytes([10])));

  Assert.AreEqual(65, Range.Map(256, 2));
  Assert.AreEqual(75, Range.Map(266, 2));
  Assert.AreEqual(-1, Range.Map(290, 2));
  Assert.AreEqual(-1, Range.Map(256, 1));

  Assert.AreEqual(256, Range.Unmap(65));
  Assert.AreEqual(266, Range.Unmap(75));
  Assert.AreEqual(-1, Range.Unmap(100));
end;

procedure TCIDRangeTests.TestExtendOnlyContinuesTheRange;
begin
  var Range := TCIDRange.Create(0, 9, 100, 2);

  Assert.IsFalse(Range.Extend(11, 20, 111, 2), 'a gap in the codes');
  Assert.IsFalse(Range.Extend(10, 20, 999, 2), 'a gap in the CIDs');
  Assert.IsFalse(Range.Extend(10, 20, 110, 1), 'another code length');
  Assert.IsTrue(Range.Extend(10, 20, 110, 2));
  Assert.AreEqual(120, Range.Map(20, 2));
end;

procedure TCIDRangeTests.TestExtendDoesNotOverflow;
begin
  var Range := TCIDRange.Create(0, MaxInt, 0, 4);

  Assert.IsFalse(Range.Extend(Low(Integer), Low(Integer), 0, 4));
end;

{ TCMapStringsTests }

procedure TCMapStringsTests.GetNonCachedValues;
var
  Text: string;
  Index: Integer;
  Value: TBytes;
begin
  Assert.IsFalse(TCMapStrings.TryGetMapping(Bytes([0, 0, 0]), Text));
  Assert.IsFalse(TCMapStrings.TryGetMapping(Bytes([0, 0, 0, 0]), Text));
  Assert.IsFalse(TCMapStrings.TryGetByteValue(Bytes([0, 0, 0]), Value));
  Assert.IsFalse(TCMapStrings.TryGetByteValue(Bytes([0, 0, 0, 0]), Value));
  Assert.IsFalse(TCMapStrings.TryGetIndexValue(Bytes([0, 0, 0]), Index));
  Assert.IsFalse(TCMapStrings.TryGetIndexValue(Bytes([0, 0, 0, 0]), Index));
end;

procedure TCMapStringsTests.GetMappingOneByte;
var
  Text: string;
begin
  Assert.IsTrue(TCMapStrings.TryGetMapping(Bytes([0]), Text));
  Assert.AreEqual(#0, Text);

  Assert.IsTrue(TCMapStrings.TryGetMapping(Bytes([$FF]), Text));
  Assert.AreEqual(#$00FF, Text);

  Assert.IsTrue(TCMapStrings.TryGetMapping(Bytes([98]), Text));
  Assert.AreEqual('b', Text);
end;

procedure TCMapStringsTests.GetMappingTwoByte;
var
  Text: string;
begin
  Assert.IsTrue(TCMapStrings.TryGetMapping(Bytes([0, 0]), Text));
  Assert.AreEqual(#0, Text);

  Assert.IsTrue(TCMapStrings.TryGetMapping(Bytes([$62, $43]), Text));
  Assert.AreEqual(Utf16BigEndian([$62, $43]), Text);

  Assert.IsTrue(TCMapStrings.TryGetMapping(Bytes([$38, $FF]), Text));
  Assert.AreEqual(#$38FF, Text);

  Assert.IsTrue(TCMapStrings.TryGetMapping(Bytes([$FF, $43]), Text));
  Assert.AreEqual(#$FF43, Text);
end;

procedure TCMapStringsTests.GetMappingOfSurrogateGivesReplacementCharacter;
var
  Text: string;
begin
  Assert.IsTrue(TCMapStrings.TryGetMapping(Bytes([$FF, $FF]), Text));
  Assert.AreEqual(#$FFFF, Text, 'U+FFFF is a valid UTF-16 unit');

  Assert.IsTrue(TCMapStrings.TryGetMapping(Bytes([$D8, $00]), Text));
  Assert.AreEqual(#$FFFD, Text);

  Assert.IsTrue(TCMapStrings.TryGetMapping(Bytes([$DC, $00]), Text));
  Assert.AreEqual(#$FFFD, Text);
end;

procedure TCMapStringsTests.GetByteValues;
var
  Value: TBytes;
begin
  const OneByte = Bytes([98]);
  Assert.IsTrue(TCMapStrings.TryGetByteValue(OneByte, Value));
  Assert.AreEqual<Integer>(1, Length(Value));
  Assert.AreEqual<Integer>(98, Value[0]);
  Value[0] := 1;
  Assert.AreEqual<Integer>(98, OneByte[0], 'the result is a copy');

  Assert.IsTrue(TCMapStrings.TryGetByteValue(Bytes([$FF, $43]), Value));
  Assert.AreEqual<Integer>(2, Length(Value));
  Assert.AreEqual<Integer>($FF, Value[0]);
  Assert.AreEqual<Integer>($43, Value[1]);
end;

procedure TCMapStringsTests.GetIndexValues;
var
  Index: Integer;
begin
  Assert.IsTrue(TCMapStrings.TryGetIndexValue(Bytes([0]), Index));
  Assert.AreEqual(0, Index);
  Assert.IsTrue(TCMapStrings.TryGetIndexValue(Bytes([$FF]), Index));
  Assert.AreEqual($FF, Index);
  Assert.IsTrue(TCMapStrings.TryGetIndexValue(Bytes([98]), Index));
  Assert.AreEqual(98, Index);

  Assert.IsTrue(TCMapStrings.TryGetIndexValue(Bytes([0, 0]), Index));
  Assert.AreEqual(0, Index);
  Assert.IsTrue(TCMapStrings.TryGetIndexValue(Bytes([$FF, $FF]), Index));
  Assert.AreEqual($FFFF, Index);
  Assert.IsTrue(TCMapStrings.TryGetIndexValue(Bytes([$62, $43]), Index));
  Assert.AreEqual($6243, Index);
  Assert.IsTrue(TCMapStrings.TryGetIndexValue(Bytes([$38, $FF]), Index));
  Assert.AreEqual($38FF, Index);
end;

procedure TCMapStringsTests.DecodeUtf16BigEndianLikeJava;
begin
  Assert.AreEqual('A', TCMapStrings.DecodeUtf16BigEndian(Bytes([0, $41])));
  Assert.AreEqual('A' + #$D83D + #$DE00, TCMapStrings.DecodeUtf16BigEndian(Bytes([0, $41, $D8, $3D, $DE, $00])), 'a surrogate pair');
  Assert.AreEqual(#$FFFD + 'A', TCMapStrings.DecodeUtf16BigEndian(Bytes([$D8, $3D, 0, $41])), 'a high surrogate without a low one');
  Assert.AreEqual(#$FFFD, TCMapStrings.DecodeUtf16BigEndian(Bytes([$DE, $00])), 'a lone low surrogate');
  Assert.AreEqual('A' + #$FFFD, TCMapStrings.DecodeUtf16BigEndian(Bytes([0, $41, $42])), 'a dangling byte');
  Assert.AreEqual('A' + #$FFFD, TCMapStrings.DecodeUtf16BigEndian(Bytes([0, $41, $D8, $3D])), 'a high surrogate at the end');
  Assert.AreEqual('', TCMapStrings.DecodeUtf16BigEndian(nil));
end;

{ TCMapTests }

procedure TCMapTests.TestLookup;
begin
  const Code = Bytes([200]);
  const CMap = TCMap.Create;
  try
    CMap.AddCharMapping(Code, 'a');

    Assert.AreEqual('a', UnicodeOf(CMap, Code));
    Assert.IsTrue(CMap.HasUnicodeMappings);
    Assert.IsFalse(CMap.HasCIDMappings);
  finally
    CMap.Free;
  end;
end;

procedure TCMapTests.TestReadCodeWithMixedCodeLengths;
begin
  const CMap = TCMap.Create;
  try
    CMap.AddCodespaceRange(TCodespaceRange.Create(Bytes([$00]), Bytes([$80])));
    CMap.AddCodespaceRange(TCodespaceRange.Create(Bytes([$81, $40]), Bytes([$9F, $FC])));
    const Data = Bytes([$41, $81, $40, $90]);

    var Position := 0;
    Assert.AreEqual($41, CMap.ReadCode(Data, Position));
    Assert.AreEqual(1, Position);
    Assert.AreEqual($8140, CMap.ReadCode(Data, Position));
    Assert.AreEqual(3, Position);
  finally
    CMap.Free;
  end;
end;

procedure TCMapTests.TestReadCodeWithoutMatchUsesMinimumLength;
begin
  const Messages = TList<string>.Create;
  const Log = TPdfLog.Create(
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      Messages.Add(Message);
    end);
  const CMap = TCMap.Create;
  try
    CMap.AddCodespaceRange(TCodespaceRange.Create(Bytes([$81, $40]), Bytes([$9F, $FC])));
    CMap.Name := 'Test-H';
    const Data = Bytes([$20, $21, $22]);

    var Position := 0;
    const Code = CMap.ReadCode(Data, Position, Log);

    Assert.AreEqual($2021, Code, 'Adobe Reader behaviour');
    Assert.AreEqual(2, Position);
    Assert.AreEqual<Integer>(1, Messages.Count);
    Assert.Contains(Messages[0], 'Test-H');
  finally
    CMap.Free;
    Log.Free;
    Messages.Free;
  end;
end;

procedure TCMapTests.TestReadCodeAtEndOfDataDoesNotMove;
begin
  const CMap = TCMap.Create;
  try
    CMap.AddCodespaceRange(TCodespaceRange.Create(Bytes([$00, $00]), Bytes([$FF, $FF])));

    var Position := 2;
    Assert.AreEqual(0, CMap.ReadCode(Bytes([1, 2]), Position));
    Assert.AreEqual(2, Position);

    Position := 0;
    Assert.AreEqual($0100, CMap.ReadCode(Bytes([1]), Position), 'a short code is padded with zeros');
    Assert.AreEqual(1, Position);
  finally
    CMap.Free;
  end;
end;

procedure TCMapTests.TestReadCodeWithoutCodespaceReadsOneByte;
begin
  const CMap = TCMap.Create;
  try
    var Position := 0;
    Assert.AreEqual($12, CMap.ReadCode(Bytes([$12, $34]), Position));
    Assert.AreEqual(1, Position);
  finally
    CMap.Free;
  end;
end;

procedure TCMapTests.TestEmptyCodespaceRangeIsIgnored;
begin
  const CMap = TCMap.Create;
  try
    CMap.AddCodespaceRange(TCodespaceRange.Create(nil, nil));

    var Position := 0;
    const Code = CMap.ReadCode(Bytes([$12, $34]), Position);

    Assert.AreEqual($12, Code);
    Assert.IsTrue(Position > 0, 'every read moves forward');
  finally
    CMap.Free;
  end;
end;

procedure TCMapTests.TestSpaceMapping;
begin
  const CMap = TCMap.Create;
  try
    var Code: Integer;
    Assert.IsFalse(CMap.TryGetSpaceMapping(Code));

    CMap.AddCharMapping(Bytes([$00, $03]), ' ');

    Assert.IsTrue(CMap.TryGetSpaceMapping(Code));
    Assert.AreEqual(3, Code);
  finally
    CMap.Free;
  end;
end;

procedure TCMapTests.TestMappingsStopAtTheLimit;
begin
  const CMap = TCMap.Create;
  try
    for var Index := 0 to MaxCMapMappings + 10 do
    begin
      CMap.AddCharMapping(Bytes([Byte(Index shr 16), Byte(Index shr 8), Byte(Index)]), 'x');
    end;

    Assert.AreEqual(MaxCMapMappings, CMap.MappingCount);
    Assert.IsTrue(CMap.IsFull);
  finally
    CMap.Free;
  end;
end;

{ TCMapParserTests }

procedure TCMapParserTests.Setup;
begin
  FMessages := TList<string>.Create;
  FLog := TPdfLog.Create(
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      FMessages.Add(Message);
    end);
end;

procedure TCMapParserTests.TearDown;
begin
  FLog.Free;
  FMessages.Free;
end;

function TCMapParserTests.ParseText(const Text: string; const StrictMode: Boolean): TCMap;
begin
  const Parser = TCMapParser.Create(StrictMode, FLog);
  try
    const Source = TRandomAccessRead.FromBytes(TEncoding.ASCII.GetBytes(Text));
    try
      Result := Parser.Parse(Source);
    finally
      Source.Free;
    end;
  finally
    Parser.Free;
  end;
end;

function TCMapParserTests.ParsePredefined(const Name: string): TCMap;
begin
  const Parser = TCMapParser.Create(False, FLog);
  try
    Result := Parser.ParsePredefined(Name);
  finally
    Parser.Free;
  end;
end;

function TCMapParserTests.HasWarning(const Fragment: string): Boolean;
begin
  Result := False;
  for var Message in FMessages do
  begin
    if Message.Contains(Fragment) then
    begin
      Exit(True);
    end;
  end;
end;

procedure TCMapParserTests.TestLookup;
begin
  const CMap = ParseText(CMapTestText);
  try
    Assert.AreEqual('A', UnicodeOf(CMap, Bytes([0, 1])), 'bytes 00 01 from bfrange <0001> <0005> <0041>');
    Assert.AreEqual('0', UnicodeOf(CMap, Bytes([1, 0])), 'bytes 01 00 from bfrange <0100> <0109> <0030>');
    Assert.AreEqual('P', UnicodeOf(CMap, Bytes([1, 32])), 'bytes 01 20 from the array of bfrange <0120> <0122>');
    Assert.AreEqual('R', UnicodeOf(CMap, Bytes([1, 33])), 'bytes 01 21 from the array of bfrange <0120> <0122>');
    Assert.AreEqual('*', UnicodeOf(CMap, Bytes([0, 10])), 'bytes 00 0A from bfchar <000A> <002A>');
    Assert.AreEqual('+', UnicodeOf(CMap, Bytes([1, 10])), 'bytes 01 0A from bfchar <010A> <002B>');

    Assert.AreEqual(65, CMap.ToCID(Bytes([0, 65])), 'CID 65 from cidrange <0000> <00ff> 0');
    Assert.AreEqual($0118, CMap.ToCID(Bytes([1, 24])), 'CID 280 from cidrange <0100> <01ff> 256');
    Assert.AreEqual($0208, CMap.ToCID(Bytes([2, 8])), 'CID 520 from cidchar <0208> 520');
    Assert.AreEqual($012C, CMap.ToCID(Bytes([1, $2C])), 'CID 300 from cidrange <0300> <0300> 300');
  finally
    CMap.Free;
  end;
end;

procedure TCMapParserTests.TestIdentity;
begin
  const CMap = ParsePredefined('Identity-H');
  try
    Assert.AreEqual(65, CMap.ToCID(Bytes([0, 65])), 'Identity-H CID 65');
    Assert.AreEqual(12345, CMap.ToCID(Bytes([$30, $39])), 'Identity-H CID 12345');
    Assert.AreEqual($FFFF, CMap.ToCID(Bytes([$FF, $FF])), 'Identity-H CID 0xFFFF');
  finally
    CMap.Free;
  end;
end;

procedure TCMapParserTests.TestUniJIS_UTF16_H;
begin
  const CMap = ParsePredefined('UniJIS-UTF16-H');
  try
    // the first three cases show that CMap.ToCID(Code) can give a false result
    Assert.AreEqual(694, CMap.ToCID($B1), 'UniJIS-UTF16-H CID 0xb1 -> 694');
    Assert.AreNotEqual(694, CMap.ToCID($B1, 1), 'UniJIS-UTF16-H CID 0xb1 -> 694');
    Assert.AreEqual(694, CMap.ToCID($B1, 2), 'UniJIS-UTF16-H CID 0x00b1 -> 694');

    // 1:1 cid char mapping
    Assert.AreEqual(694, CMap.ToCID(Bytes([$00, $B1])), 'UniJIS-UTF16-H CID 0x00b1 -> 694');
    Assert.AreEqual(20168, CMap.ToCID(Bytes([$D8, $50, $DC, $4B])), 'UniJIS-UTF16-H CID 0xd850dc4b -> 20168');

    // cid range mapping
    Assert.AreEqual(19223, CMap.ToCID(Bytes([$54, $34])), 'UniJIS-UTF16-H CID 0x5434 -> 19223');
    Assert.AreEqual(10006, CMap.ToCID(Bytes([$D8, $3C, $DD, $12])), 'UniJIS-UTF16-H CID 0xd83cdd12 -> 10006');
  finally
    CMap.Free;
  end;
end;

procedure TCMapParserTests.TestUniJIS_UCS2_H;
begin
  const CMap = ParsePredefined('UniJIS-UCS2-H');
  try
    Assert.AreEqual(34, CMap.ToCID(Bytes([0, 65])), 'UniJIS-UCS2-H CID 65 -> 34');
  finally
    CMap.Free;
  end;
end;

procedure TCMapParserTests.TestAdobe_GB1_UCS2;
begin
  const CMap = ParsePredefined('Adobe-GB1-UCS2');
  try
    Assert.AreEqual('0', UnicodeOf(CMap, Bytes([0, $11])), 'Adobe-GB1-UCS2 CID 0x11 -> "0"');
  finally
    CMap.Free;
  end;
end;

procedure TCMapParserTests.TestParserWithPoorWhitespace;
begin
  const CMap = ParseText(PoorWhitespaceText);
  try
    Assert.IsNotNull(CMap, 'Failed to parse nasty CMap file');
    Assert.AreEqual('DDACTR+F1+0', CMap.Name);
    Assert.AreEqual(#$2212, UnicodeOf(CMap, Bytes([0, $ED])));
  finally
    CMap.Free;
  end;
end;

procedure TCMapParserTests.TestParserWithMalformedbfrange1;
begin
  const CMap = ParseText(Malformedbfrange1Text);
  try
    Assert.AreEqual('A', UnicodeOf(CMap, Bytes([0, 1])), 'bytes 00 01 from bfrange <0001> <0009> <0041>');
    Assert.AreEqual('<none>', UnicodeOf(CMap, Bytes([1, 0])));
  finally
    CMap.Free;
  end;
end;

procedure TCMapParserTests.TestParserWithMalformedbfrange2;
begin
  var CMap := ParseText(Malformedbfrange2Text);
  try
    Assert.AreEqual('0', UnicodeOf(CMap, Bytes([0, 1])), 'bytes 00 01 from bfrange <0001> <0009> <0030>');
    Assert.AreEqual('A', UnicodeOf(CMap, Bytes([2, $32])), 'bytes 02 32 from bfrange <0232> <0432> <0041>');

    // border values in non-strict mode
    Assert.AreNotEqual('<none>', UnicodeOf(CMap, Bytes([2, $F0])));
    Assert.AreNotEqual('<none>', UnicodeOf(CMap, Bytes([2, $F1])));
  finally
    CMap.Free;
  end;

  CMap := ParseText(Malformedbfrange2Text, True);
  try
    // border values in strict mode
    Assert.AreNotEqual('<none>', UnicodeOf(CMap, Bytes([2, $F0])));
    Assert.AreEqual('<none>', UnicodeOf(CMap, Bytes([2, $F1])));
  finally
    CMap.Free;
  end;
end;

procedure TCMapParserTests.TestPredefinedMap;
begin
  var CMap := ParsePredefined('Adobe-Korea1-UCS2');
  try
    Assert.AreEqual('Adobe-Korea1-UCS2', CMap.Name, 'wrong CMap name');
    Assert.AreEqual(0, CMap.WMode, 'wrong WMode');
    Assert.IsFalse(CMap.HasCIDMappings);
    Assert.IsTrue(CMap.HasUnicodeMappings);
  finally
    CMap.Free;
  end;

  CMap := ParsePredefined('Identity-V');
  try
    Assert.AreEqual('Identity-V', CMap.Name);
  finally
    CMap.Free;
  end;
end;

procedure TCMapParserTests.TestIdentitybfrange;
begin
  const CMap = ParseText(IdentitybfrangeText, True);
  try
    Assert.AreEqual('Adobe-Identity-UCS', CMap.Name, 'wrong CMap name');

    Assert.AreEqual(Utf16BigEndian([0, 65]), UnicodeOf(CMap, Bytes([0, 65])), 'Identity 0x0041');
    Assert.AreEqual(Utf16BigEndian([$30, $39]), UnicodeOf(CMap, Bytes([$30, $39])), 'Identity 0x3039');

    // border values for strict mode
    Assert.AreEqual(Utf16BigEndian([$30, $FF]), UnicodeOf(CMap, Bytes([$30, $FF])), 'Identity 0x30FF');
    Assert.AreEqual(Utf16BigEndian([$31, $00]), UnicodeOf(CMap, Bytes([$31, $00])), 'Identity 0x3100');
    Assert.AreEqual(Utf16BigEndian([$FF, $FF]), UnicodeOf(CMap, Bytes([$FF, $FF])), 'Identity 0xFFFF');
  finally
    CMap.Free;
  end;
end;

procedure TCMapParserTests.TestBadIncrement;
begin
  const CMap = ParseText('1 beginbfrange' + sLineBreak + '<> <> <2223>' + sLineBreak + 'endbfrange');
  try
    Assert.IsNotNull(CMap);
    Assert.IsTrue(HasWarning('4 bytes'), 'a mapping without a usable code length is reported');
  finally
    CMap.Free;
  end;
end;

procedure TCMapParserTests.TestHeaderFieldsAreRead;
begin
  const CMap = ParseText(HeaderText);
  try
    Assert.AreEqual('Test-H', CMap.Name);
    Assert.AreEqual('12.002', CMap.Version);
    Assert.AreEqual(1, CMap.CMapType);
    Assert.AreEqual(1, CMap.WMode);
    Assert.AreEqual('Adobe', CMap.Registry);
    Assert.AreEqual('Japan1', CMap.Ordering);
    Assert.AreEqual(4, CMap.Supplement);
  finally
    CMap.Free;
  end;
end;

procedure TCMapParserTests.TestBfCharWithLiteralName;
begin
  const CMap = ParseText('1 begincodespacerange <00> <FF> endcodespacerange 1 beginbfchar <01> /fi endbfchar');
  try
    Assert.AreEqual('fi', UnicodeOf(CMap, Bytes([1])));
  finally
    CMap.Free;
  end;
end;

procedure TCMapParserTests.TestHugeBfRangeIsBounded;
begin
  const Watch = TStopwatch.StartNew;

  const CMap = ParseText('1 beginbfrange <00000000> <FFFFFFFF> <0000> endbfrange');
  try
    Assert.IsTrue(Watch.ElapsedMilliseconds < 2000, 'Parsing took too long');
    Assert.IsTrue(CMap.MappingCount <= MaxCMapMappings);
    Assert.IsTrue(HasWarning('bfrange'), 'The range is reported');
  finally
    CMap.Free;
  end;
end;

procedure TCMapParserTests.TestHugeBfRangeBelowSignedLimitIsBounded;
begin
  const Watch = TStopwatch.StartNew;

  const CMap = ParseText('1 beginbfrange <00000000> <7FFFFFFE> <0041> endbfrange');
  try
    Assert.IsTrue(Watch.ElapsedMilliseconds < 20000, 'Parsing took too long');
    Assert.AreEqual(MaxCMapMappings, CMap.MappingCount);
    Assert.IsTrue(HasWarning('limit'), 'The limit is reported');
    Assert.AreEqual('A', UnicodeOf(CMap, Bytes([0, 0, 0, 0])));
  finally
    CMap.Free;
  end;
end;

procedure TCMapParserTests.TestRepeatedUseCMapIsBounded;
begin
  const Watch = TStopwatch.StartNew;
  var Text := '';
  for var Index := 1 to 200 do
  begin
    Text := Text + '/UniJIS-UCS2-H usecmap ';
  end;

  const CMap = ParseText(Text);
  try
    Assert.IsTrue(CMap.HasCIDMappings);
    Assert.IsTrue(CMap.MappingCount <= MaxCMapMappings);
    Assert.IsTrue(Watch.ElapsedMilliseconds < 20000, 'Parsing took too long');
  finally
    CMap.Free;
  end;
end;

procedure TCMapParserTests.ParseNestedArrays;
begin
  ParseText('1 beginbfrange <00> <01> ' + string.Create('[', 100000));
end;

procedure TCMapParserTests.ParseUnknownUseCMap;
begin
  ParseText('/NoSuchCMap usecmap');
end;

procedure TCMapParserTests.ParseHugeToken;
begin
  ParseText('1 beginbfchar <' + string.Create('0', 1200) + '> <0041> endbfchar');
end;

procedure TCMapParserTests.ParseBadNumber;
begin
  ParseText('99999999999 beginbfchar <01> <0041> endbfchar');
end;

procedure TCMapParserTests.ParseBadCodespace;
begin
  ParseText('1 begincodespacerange <0102> <03> endcodespacerange');
end;

procedure TCMapParserTests.ParseMissingBfCharValue;
begin
  ParseText('1 beginbfchar <01> 5 endbfchar');
end;

procedure TCMapParserTests.TestNestedArraysRaiseParseError;
begin
  Assert.WillRaise(ParseNestedArrays, EPdfParseException);
end;

procedure TCMapParserTests.TestUnknownUseCMapRaisesParseError;
begin
  Assert.WillRaise(ParseUnknownUseCMap, EPdfParseException);
end;

procedure TCMapParserTests.TestHexTokenLargerThanBufferRaisesParseError;
begin
  Assert.WillRaise(ParseHugeToken, EPdfParseException);
end;

procedure TCMapParserTests.TestInvalidNumberRaisesParseError;
begin
  Assert.WillRaise(ParseBadNumber, EPdfParseException);
end;

procedure TCMapParserTests.TestCodespaceWithDifferentLengthsRaisesParseError;
begin
  Assert.WillRaise(ParseBadCodespace, EPdfParseException);
end;

procedure TCMapParserTests.TestMissingBfCharValueRaisesParseError;
begin
  Assert.WillRaise(ParseMissingBfCharValue, EPdfParseException);
end;

procedure TCMapParserTests.TestTruncatedDataEndsWithoutHang;
begin
  const Texts: TArray<string> = [
    '', '(', '<', '<<', '[', '/', '%', '>', '1 begincodespacerange <00', '2 beginbfchar <01> <00',
    '1 beginbfrange <00> <10> [<0041>', '/WMode', '/CMapVersion'
  ];

  for var Text in Texts do
  begin
    try
      ParseText(Text).Free;
    except
      on EPdfParseException do
      begin
        // an error is as good as a result; hanging is not
      end;
    end;
  end;
end;

end.
