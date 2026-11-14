// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Parser.Base.Tests;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Document,
  Pdf4D.Parser.Base;

type
  [TestFixture]
  TBaseParserTests = class
  private
    FDocument: TCosDocument;
    FParser: TBaseParser;
    FLogLines: TList<string>;

    procedure Start(const Text: string); overload;
    procedure Start(const Text: string; const MaxNestingDepth: Integer); overload;
    function ParseStringBytes(const Text: string): TBytes;
    function ParseNameText(const Text: string): string;
    procedure AssertBytes(const Expected: array of Byte; const Actual: TBytes);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestParsesLiteralStringEscapes;

    [Test]
    procedure TestParsesLiteralStringOctalAndLineContinuation;

    [Test]
    procedure TestParsesBalancedNestedParentheses;

    [Test]
    procedure TestParsesUnbalancedParenthesisLeniently;

    [Test]
    procedure TestEndOfStringDetectionLikePdfBox;

    [Test]
    procedure TestLiteralStringReachingEndOfDataStops;

    [Test]
    procedure TestParsesHexStringOddLength;

    [Test]
    procedure TestParsesHexStringWithWhitespace;

    [Test]
    procedure TestHexStringWithInvalidCharacterDropsUnpairedDigit;

    [Test]
    procedure TestHexStringWithoutClosingBracketRaises;

    [Test]
    procedure TestParsesNameEscapes;

    [Test]
    procedure TestNameExamplesFromSpecification;

    [Test]
    procedure TestNameWithInvalidEscapeKeepsHash;

    [Test]
    procedure TestNameEndsAtDelimiters;

    [Test]
    procedure TestNameWithTruncatedEscapeAtEndOfData;

    [Test]
    procedure TestParsesKeywordsAndNumbers;

    [Test]
    procedure TestNumberFollowedByEndobjKeepsKeyword;

    [Test]
    procedure TestOutOfRangeIntegerIsInvalid;

    [Test]
    procedure TestNotANumberRaises;

    [Test]
    procedure TestParsesDictionaryWithReference;

    [Test]
    procedure TestSkipsComments;

    [Test]
    procedure TestDictionaryRecoversFromGarbageValue;

    [Test]
    procedure TestDictionaryRecoversFromGarbageKey;

    [Test]
    procedure TestDictionaryStopsAtEndobj;

    [Test]
    procedure TestDictionaryWithoutClosingBracketsReturnsEntries;

    [Test]
    procedure TestDictionarySkipsOutOfRangeNumber;

    [Test]
    procedure TestDictionaryInvalidReferencesBecomeNull;

    [Test]
    procedure TestDictionaryWithBrokenReferenceRaisesWithoutLeak;

    [Test]
    procedure TestParsesNestedContainers;

    [Test]
    procedure TestParsesArrayWithReferences;

    [Test]
    procedure TestArrayStopsAtEndobj;

    [Test]
    procedure TestArrayKeepsNullForGarbageElement;

    [Test]
    procedure TestReferenceWithoutDocumentRaises;

    [Test]
    procedure TestDeepNestingRaises;

    [Test]
    procedure TestDeepDictionaryNestingRaises;

    [Test]
    procedure TestNestingLimitComesFromOptions;

    [Test]
    procedure TestNestingCounterIsReleasedAfterParse;

    [Test]
    procedure TestNestingLimitIsClamped;

    [Test]
    procedure TestReadLongAndInt;

    [Test]
    procedure TestReadNumberErrorsRewind;

    [Test]
    procedure TestReadObjectAndGenerationNumberLimits;

    [Test]
    procedure TestReadLine;

    [Test]
    procedure TestReadStringAndExpected;

    [Test]
    procedure TestCharacterClasses;

    [Test]
    procedure TestSkipLinebreakAndWhiteSpaces;

    [Test]
    procedure TestMalformedInputNeverHangs;
  end;

implementation

uses
  System.Classes,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Boolean,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Float,
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.Null,
  Pdf4D.Cos.Number,
  Pdf4D.Cos.ObjectKey,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Cos.PdfObject,
  Pdf4D.Cos.PdfString,
  Pdf4D.IO.RandomAccessRead;

const
  ParenthesisEnds: array[0..5] of string = (#10'/ ', #13'/ ', #13#10'/', #10'> ', #13'> ', #13#10'>');

{ TBaseParserTests }

procedure TBaseParserTests.Setup;
begin
  FLogLines := TList<string>.Create;
end;

procedure TBaseParserTests.TearDown;
begin
  FreeAndNil(FParser);
  FreeAndNil(FDocument);
  FreeAndNil(FLogLines);
end;

procedure TBaseParserTests.Start(const Text: string);
begin
  Start(Text, DefaultMaxNestingDepth);
end;

procedure TBaseParserTests.Start(const Text: string; const MaxNestingDepth: Integer);
begin
  FreeAndNil(FParser);
  FreeAndNil(FDocument);

  var Data: TBytes;
  SetLength(Data, Text.Length);
  for var Index := 0 to Text.Length - 1 do
  begin
    Data[Index] := Byte(Text.Chars[Index]);
  end;

  var Options := TPdfLoadOptions.Default;
  Options.MaxNestingDepth := MaxNestingDepth;
  Options.OnLog :=
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      FLogLines.Add(Message);
    end;

  FDocument := TCosDocument.Create(TRandomAccessRead.FromBytes(Data), Options);
  FParser := TBaseParser.Create(FDocument.Source, FDocument);
end;

function TBaseParserTests.ParseStringBytes(const Text: string): TBytes;
begin
  Start(Text);

  const Parsed = FParser.ParseCosString;
  try
    Result := Parsed.Bytes;
  finally
    Parsed.Free;
  end;
end;

function TBaseParserTests.ParseNameText(const Text: string): string;
begin
  Start(Text);

  const Parsed = FParser.ParseCosName;
  try
    Result := Parsed.Name;
  finally
    Parsed.Free;
  end;
end;

procedure TBaseParserTests.AssertBytes(const Expected: array of Byte; const Actual: TBytes);
begin
  Assert.AreEqual(Length(Expected), Length(Actual), 'byte count');
  for var Index := 0 to High(Expected) do
  begin
    Assert.AreEqual(Integer(Expected[Index]), Integer(Actual[Index]), Format('byte %d', [Index]));
  end;
end;

procedure TBaseParserTests.TestParsesLiteralStringEscapes;
begin
  const Actual = ParseStringBytes('(a\(b\)\n\101\'#10'c)');

  AssertBytes([Ord('a'), Ord('('), Ord('b'), Ord(')'), 10, Ord('A'), Ord('c')], Actual);
end;

procedure TBaseParserTests.TestParsesLiteralStringOctalAndLineContinuation;
begin
  AssertBytes([1, 2, 3, 255], ParseStringBytes('(\1\02\003\777)'));
  AssertBytes([Ord('1'), Ord('2'), Ord('3')], ParseStringBytes('(1\'#13#10'2\'#13'3)'));
  AssertBytes([9, 13, 8, 12, Ord('\'), Ord('q')], ParseStringBytes('(\t\r\b\f\\\q)'));
end;

procedure TBaseParserTests.TestParsesBalancedNestedParentheses;
begin
  AssertBytes([Ord('a'), Ord('('), Ord('b'), Ord('('), Ord(')'), Ord(')'), Ord('c')],
              ParseStringBytes('(a(b())c)'));
end;

procedure TBaseParserTests.TestParsesUnbalancedParenthesisLeniently;
begin
  // The second ')' is followed by an end of line and a name: that closes the string, like in PDFBox
  AssertBytes([Ord('('), Ord('T'), Ord('e'), Ord('s'), Ord('t')], ParseStringBytes('((Test)'#10'/Key 1'));

  // /Title (c:\) /Producer: the escaped ')' closes the string when a name follows on the next line
  AssertBytes([Ord('c'), Ord(':'), Ord('\')], ParseStringBytes('(c:\)'#13#10'/Producer'));
end;

procedure TBaseParserTests.TestEndOfStringDetectionLikePdfBox;
begin
  for var Ending in ParenthesisEnds do
  begin
    AssertBytes([Ord('('), Ord('T'), Ord('e'), Ord('s'), Ord('t')], ParseStringBytes('((Test)' + Ending));
  end;

  AssertBytes([Ord('T'), Ord('e'), Ord('s'), Ord('t')], ParseStringBytes('(Test)'));
end;

procedure TBaseParserTests.TestLiteralStringReachingEndOfDataStops;
begin
  AssertBytes([Ord('a'), Ord('b'), Ord('('), Ord('c')], ParseStringBytes('(ab(c'));
  AssertBytes([], ParseStringBytes('('));
  AssertBytes([Ord('a'), 255], ParseStringBytes('(a\'));
end;

procedure TBaseParserTests.TestParsesHexStringOddLength;
begin
  AssertBytes([$41, $40], ParseStringBytes('<414>'));
  AssertBytes([], ParseStringBytes('<>'));

  Start('<4a>');
  const Parsed = FParser.ParseCosString;
  try
    Assert.IsTrue(Parsed.IsHex);
  finally
    Parsed.Free;
  end;
end;

procedure TBaseParserTests.TestParsesHexStringWithWhitespace;
begin
  AssertBytes([$41, $42, $43], ParseStringBytes('< 41'#10'4 2'#9'43'#13#12' >'));
end;

procedure TBaseParserTests.TestHexStringWithInvalidCharacterDropsUnpairedDigit;
begin
  AssertBytes([$41], ParseStringBytes('<414G43>'));
  AssertBytes([$41, $42], ParseStringBytes('<4142G>'));
end;

procedure TBaseParserTests.TestHexStringWithoutClosingBracketRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      ParseStringBytes('<4142');
    end,
    EPdfParseException);

  Assert.WillRaise(
    procedure
    begin
      ParseStringBytes('<41G42');
    end,
    EPdfParseException);
end;

procedure TBaseParserTests.TestParsesNameEscapes;
begin
  Assert.AreEqual('A B', ParseNameText('/A#20B'));
  Assert.AreEqual('Name/Test', ParseNameText('/Name#2fTest '));
  Assert.AreEqual('Name/Test', ParseNameText('/Name#2FTest '));
  Assert.AreEqual('AB', ParseNameText('/A#42 '));
end;

procedure TBaseParserTests.TestNameExamplesFromSpecification;
begin
  Assert.AreEqual('Name1', ParseNameText('/Name1 '));
  Assert.AreEqual('ASomewhatLongerName', ParseNameText('/ASomewhatLongerName '));
  Assert.AreEqual('A;Name_With-Various***Characters?', ParseNameText('/A;Name_With-Various***Characters? '));
  Assert.AreEqual('1.2', ParseNameText('/1.2 '));
  Assert.AreEqual('$$', ParseNameText('/$$ '));
  Assert.AreEqual('@pattern', ParseNameText('/@pattern '));
  Assert.AreEqual('.notdef', ParseNameText('/#2Enotdef '));
  Assert.AreEqual('lime Green', ParseNameText('/lime#20Green '));
  Assert.AreEqual('paired()parentheses', ParseNameText('/paired#28#29parentheses '));
  Assert.AreEqual('The_Key_of_F#_Minor', ParseNameText('/The_Key_of_F#23_Minor '));
  Assert.AreEqual('', ParseNameText('/ '));
  Assert.AreEqual('Name', ParseNameText('/Name'#0'Extra '));
  Assert.AreEqual('!"$''*+-._:;=@~^`|\', ParseNameText('/!"$''*+-._:;=@~^`|\'));
end;

procedure TBaseParserTests.TestNameWithInvalidEscapeKeepsHash;
begin
  Assert.AreEqual('Name#GG', ParseNameText('/Name#GG '));
  Assert.AreEqual('Name#4G', ParseNameText('/Name#4G '));
end;

procedure TBaseParserTests.TestNameEndsAtDelimiters;
begin
  for var Delimiter in ['>', '<', '[', ']', '(', ')', '/', '%'] do
  begin
    Assert.AreEqual('Name', ParseNameText('/Name' + Delimiter));
    Assert.AreEqual(Int64(5), FParser.Source.GetPosition, 'the delimiter is not consumed');
  end;
end;

procedure TBaseParserTests.TestNameWithTruncatedEscapeAtEndOfData;
begin
  Assert.AreEqual('Name', ParseNameText('/Name#'));
  Assert.AreEqual('Name', ParseNameText('/Name#4'));
  Assert.IsTrue(FLogLines.Count > 0);
end;

procedure TBaseParserTests.TestParsesKeywordsAndNumbers;
begin
  Start('null true false 42 -7 +3 .5 4.25 - . [');

  var Value := FParser.ParseDirObject;
  Assert.IsTrue(Value is TCosNull);
  Value.Free;

  Value := FParser.ParseDirObject;
  Assert.IsTrue((Value is TCosBoolean) and TCosBoolean(Value).Value);
  Value.Free;

  Value := FParser.ParseDirObject;
  Assert.IsTrue((Value is TCosBoolean) and not TCosBoolean(Value).Value);
  Value.Free;

  Value := FParser.ParseDirObject;
  Assert.IsTrue(Value is TCosInteger);
  Assert.AreEqual(Int64(42), TCosInteger(Value).LongValue);
  Value.Free;

  Value := FParser.ParseDirObject;
  Assert.AreEqual(Int64(-7), TCosNumber(Value).LongValue);
  Value.Free;

  Value := FParser.ParseDirObject;
  Assert.AreEqual(Int64(3), TCosNumber(Value).LongValue);
  Value.Free;

  Value := FParser.ParseDirObject;
  Assert.IsTrue(Value is TCosFloat);
  Assert.AreEqual(Double(0.5), Double(TCosNumber(Value).FloatValue));
  Value.Free;

  Value := FParser.ParseDirObject;
  Assert.AreEqual(Double(4.25), Double(TCosNumber(Value).FloatValue));
  Value.Free;

  // A lone '-' and a lone '.' are read as 0, like PDFBOX-592
  Value := FParser.ParseDirObject;
  Assert.IsTrue(Value is TCosInteger);
  Assert.AreEqual(Int64(0), TCosNumber(Value).LongValue);
  Value.Free;

  Value := FParser.ParseDirObject;
  Assert.AreEqual(Int64(0), TCosNumber(Value).LongValue);
  Value.Free;

  Value := FParser.ParseDirObject;
  Assert.IsTrue(Value is TCosArray);
  Value.Free;
end;

procedure TBaseParserTests.TestNumberFollowedByEndobjKeepsKeyword;
begin
  Start('74191endobj');

  const Value = FParser.ParseDirObject;
  try
    Assert.AreEqual(Int64(74191), TCosNumber(Value).LongValue);
  finally
    Value.Free;
  end;
  Assert.AreEqual('endobj', FParser.ReadString);
end;

procedure TBaseParserTests.TestOutOfRangeIntegerIsInvalid;
begin
  Start('99999999999999999999 -99999999999999999999');

  var Value := FParser.ParseDirObject;
  Assert.IsFalse(TCosInteger(Value).IsValid);
  Assert.AreEqual(High(Int64), TCosInteger(Value).LongValue);
  Value.Free;

  Value := FParser.ParseDirObject;
  Assert.IsFalse(TCosInteger(Value).IsValid);
  Assert.AreEqual(Low(Int64), TCosInteger(Value).LongValue);
  Value.Free;
end;

procedure TBaseParserTests.TestNotANumberRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      Start('5-3');
      FParser.ParseDirObject.Free;
    end,
    EPdfParseException);

  Assert.WillRaise(
    procedure
    begin
      Start('+e');
      FParser.ParseDirObject.Free;
    end,
    EPdfParseException);
end;

procedure TBaseParserTests.TestParsesDictionaryWithReference;
begin
  Start('<< /Type /Page /Parent 3 0 R /MediaBox [0 0 612 792] >>');

  const Parsed = FParser.ParseDirObject;
  try
    Assert.IsTrue(Parsed is TCosDictionary);
    const Dictionary = TCosDictionary(Parsed);
    Assert.AreEqual(3, Dictionary.Count);
    Assert.IsTrue(Dictionary.Direct);

    const Parent = Dictionary.GetItem(TCosNames.Parent);
    Assert.IsTrue(Parent is TCosObject);
    Assert.AreEqual('3 0 R', TCosObject(Parent).Key.ToString);
    Assert.AreSame(FDocument.GetObjectFromPool(TCosObjectKey.Make(3, 0)), Parent);

    Assert.AreEqual('Page', Dictionary.GetNameAsString(TCosNames.Type_, ''));

    var MediaBox: TCosArray;
    Assert.IsTrue(Dictionary.TryGetCosArray(TCosNames.MediaBox, MediaBox));
    Assert.AreEqual(4, MediaBox.Count);
  finally
    Parsed.Free;
  end;
end;

procedure TBaseParserTests.TestSkipsComments;
begin
  Start('<< /A 1 % comment'#10' /B 2 >>');

  const Dictionary = FParser.ParseCosDictionary(True);
  try
    Assert.AreEqual(2, Dictionary.Count);
    Assert.AreEqual(1, Dictionary.GetInt('A', 0));
    Assert.AreEqual(2, Dictionary.GetInt('B', 0));
  finally
    Dictionary.Free;
  end;
end;

procedure TBaseParserTests.TestDictionaryRecoversFromGarbageValue;
begin
  Start('<< /A 1 /B xyz /C 3 >>');

  const Dictionary = FParser.ParseCosDictionary(False);
  try
    Assert.IsFalse(Dictionary.Direct);
    Assert.IsTrue(Dictionary.ContainsKey('A'));
    Assert.IsTrue(Dictionary.ContainsKey('C'));
    Assert.AreEqual(3, Dictionary.GetInt('C', 0));

    // PDFBox stores the skipped garbage as COSNull
    Assert.IsTrue(Dictionary.GetItem('B') is TCosNull);
  finally
    Dictionary.Free;
  end;
end;

procedure TBaseParserTests.TestDictionaryRecoversFromGarbageKey;
begin
  Start('<< /A 1 junk (x) /C 3 >>');

  const Dictionary = FParser.ParseCosDictionary(True);
  try
    Assert.AreEqual(2, Dictionary.Count);
    Assert.AreEqual(1, Dictionary.GetInt('A', 0));
    Assert.AreEqual(3, Dictionary.GetInt('C', 0));
  finally
    Dictionary.Free;
  end;
  Assert.IsTrue(FLogLines.Count > 0);
end;

procedure TBaseParserTests.TestDictionaryStopsAtEndobj;
begin
  Start('<< /A 1 /B (x) junk endobj'#10'3 0 obj');

  const Dictionary = FParser.ParseCosDictionary(True);
  try
    Assert.AreEqual(2, Dictionary.Count);
  finally
    Dictionary.Free;
  end;
end;

procedure TBaseParserTests.TestDictionaryWithoutClosingBracketsReturnsEntries;
begin
  Start('<< /A 1 /B 2');

  const Dictionary = FParser.ParseCosDictionary(True);
  try
    Assert.AreEqual(2, Dictionary.Count);
  finally
    Dictionary.Free;
  end;

  Start('<< /A 1 >');
  const Short = FParser.ParseCosDictionary(True);
  try
    Assert.AreEqual(1, Short.Count);
  finally
    Short.Free;
  end;
end;

procedure TBaseParserTests.TestDictionarySkipsOutOfRangeNumber;
begin
  Start('<< /A 99999999999999999999 /B 2 >>');

  const Dictionary = FParser.ParseCosDictionary(True);
  try
    Assert.IsFalse(Dictionary.ContainsKey('A'));
    Assert.AreEqual(2, Dictionary.GetInt('B', 0));
  finally
    Dictionary.Free;
  end;
end;

procedure TBaseParserTests.TestDictionaryInvalidReferencesBecomeNull;
begin
  Start('<< /A 0 0 R /B 4 -1 R /C 2.5 1 R /D 5 70000 R >>');

  const Dictionary = FParser.ParseCosDictionary(True);
  try
    // "4 -1 R": the generation number does not start with a digit, so 4 stays a number
    Assert.IsTrue(Dictionary.GetItem('A') is TCosNull);
    Assert.IsTrue(Dictionary.GetItem('B') is TCosInteger);
    Assert.IsTrue(Dictionary.GetItem('C') is TCosNull);
    Assert.IsTrue(Dictionary.GetItem('D') is TCosObject);
  finally
    Dictionary.Free;
  end;
end;

procedure TBaseParserTests.TestDictionaryWithBrokenReferenceRaisesWithoutLeak;
begin
  Start('<< /A [1 2] /B 1 2 >>');

  Assert.WillRaise(
    procedure
    begin
      FParser.ParseCosDictionary(True).Free;
    end,
    EPdfParseException);
end;

procedure TBaseParserTests.TestParsesNestedContainers;
begin
  Start('<< /Kids [<< /A (x) >> [1 2 [3]] /N null true] /Next <</B <4142>>> >>');

  const Dictionary = FParser.ParseCosDictionary(True);
  try
    Assert.AreEqual(2, Dictionary.Count);

    var Kids: TCosArray;
    Assert.IsTrue(Dictionary.TryGetCosArray('Kids', Kids));
    Assert.AreEqual(5, Kids.Count);
    Assert.IsTrue(Kids.Get(0) is TCosDictionary);
    Assert.IsTrue(Kids.Get(1) is TCosArray);
    Assert.IsTrue(Kids.Get(2) is TCosName);
    Assert.IsTrue(Kids.Get(3) is TCosNull);
    Assert.IsTrue(Kids.Get(4) is TCosBoolean);

    var Next: TCosDictionary;
    Assert.IsTrue(Dictionary.TryGetCosDictionary('Next', Next));
    Assert.AreEqual(1, Next.Count);
  finally
    Dictionary.Free;
  end;
end;

procedure TBaseParserTests.TestParsesArrayWithReferences;
begin
  Start('[ 12 0 R 5 1 7 0 R (s) ] 99');

  const Items = FParser.ParseCosArray;
  try
    Assert.AreEqual(5, Items.Count);
    Assert.IsTrue(Items.Get(0) is TCosObject);
    Assert.AreEqual('12 0 R', TCosObject(Items.Get(0)).Key.ToString);
    Assert.AreEqual(Int64(5), TCosNumber(Items.Get(1)).LongValue);
    Assert.AreEqual(Int64(1), TCosNumber(Items.Get(2)).LongValue);
    Assert.AreEqual('7 0 R', TCosObject(Items.Get(3)).Key.ToString);
    Assert.IsTrue(Items.Get(4) is TCosString);
  finally
    Items.Free;
  end;

  const Following = FParser.ParseDirObject;
  try
    Assert.AreEqual(Int64(99), TCosNumber(Following).LongValue);
  finally
    Following.Free;
  end;
end;

procedure TBaseParserTests.TestArrayStopsAtEndobj;
begin
  Start('[1 2 endobj'#10'rest');

  const Items = FParser.ParseCosArray;
  try
    Assert.AreEqual(2, Items.Count);
  finally
    Items.Free;
  end;
  Assert.AreEqual('endobj', FParser.ReadString);
end;

procedure TBaseParserTests.TestArrayKeepsNullForGarbageElement;
begin
  Start('[1 xyz 2]');

  const Items = FParser.ParseCosArray;
  try
    Assert.AreEqual(3, Items.Count);
    Assert.IsTrue(Items.Get(1) is TCosNull);
  finally
    Items.Free;
  end;
end;

procedure TBaseParserTests.TestReferenceWithoutDocumentRaises;
begin
  const Source = TRandomAccessRead.FromBytes(TEncoding.ASCII.GetBytes('[1 0 R]'));
  try
    const Parser = TBaseParser.Create(Source, nil);
    try
      Assert.WillRaise(
        procedure
        begin
          Parser.ParseCosArray.Free;
        end,
        EPdfParseException);
    finally
      Parser.Free;
    end;
  finally
    Source.Free;
  end;
end;

procedure TBaseParserTests.TestDeepNestingRaises;
begin
  Start(StringOfChar('[', 10000));

  Assert.WillRaise(
    procedure
    begin
      FParser.ParseDirObject.Free;
    end,
    EPdfParseException);
end;

procedure TBaseParserTests.TestDeepDictionaryNestingRaises;
begin
  var Text := '';
  for var Index := 1 to 3000 do
  begin
    Text := Text + '<</A ';
  end;
  Start(Text);

  Assert.WillRaise(
    procedure
    begin
      FParser.ParseDirObject.Free;
    end,
    EPdfParseException);
end;

procedure TBaseParserTests.TestNestingLimitComesFromOptions;
begin
  Start('[[[1]]]', 7);
  FParser.ParseDirObject.Free;

  Start('[[[1]]]', 6);
  Assert.WillRaise(
    procedure
    begin
      FParser.ParseDirObject.Free;
    end,
    EPdfParseException);
end;

procedure TBaseParserTests.TestNestingCounterIsReleasedAfterParse;
begin
  Start('[[[1]]] [[[1]]] [[[1]]]', 7);

  for var Round := 1 to 3 do
  begin
    FParser.ParseDirObject.Free;
  end;
  Assert.Pass;
end;

procedure TBaseParserTests.TestNestingLimitIsClamped;
begin
  Start(StringOfChar('[', 900) + StringOfChar(']', 900), High(Integer));
  FParser.ParseDirObject.Free;

  Start(StringOfChar('[', 100000), High(Integer));
  Assert.WillRaise(
    procedure
    begin
      FParser.ParseDirObject.Free;
    end,
    EPdfParseException);

  var Text := '';
  for var Index := 1 to 100000 do
  begin
    Text := Text + '<</A ';
  end;
  Start(Text, High(Integer));
  Assert.WillRaise(
    procedure
    begin
      FParser.ParseDirObject.Free;
    end,
    EPdfParseException);
end;

procedure TBaseParserTests.TestReadLongAndInt;
begin
  Start('  123 4567890123 0012');

  Assert.AreEqual(Int64(123), FParser.ReadLong);
  Assert.AreEqual(Int64(4567890123), FParser.ReadLong);
  Assert.AreEqual(12, FParser.ReadInt);
end;

procedure TBaseParserTests.TestReadNumberErrorsRewind;
begin
  Start('abc');
  Assert.WillRaise(
    procedure
    begin
      FParser.ReadLong;
    end,
    EPdfParseException);
  Assert.AreEqual(Int64(0), FParser.Source.GetPosition);

  Start('2147483648');
  Assert.WillRaise(
    procedure
    begin
      FParser.ReadInt;
    end,
    EPdfParseException);
  Assert.AreEqual(Int64(0), FParser.Source.GetPosition, 'digits are put back');

  Start('99999999999999999999');
  Assert.WillRaise(
    procedure
    begin
      FParser.ReadLong;
    end,
    EPdfParseException);

  Start('9223372036854775808');
  Assert.WillRaise(
    procedure
    begin
      FParser.ReadLong;
    end,
    EPdfParseException);
end;

procedure TBaseParserTests.TestReadObjectAndGenerationNumberLimits;
begin
  Start('9999999999 10000000000 65535 65536');

  Assert.AreEqual(Int64(9999999999), FParser.ReadObjectNumber);
  Assert.WillRaise(
    procedure
    begin
      FParser.ReadObjectNumber;
    end,
    EPdfParseException);
  Assert.AreEqual(65535, FParser.ReadGenerationNumber);
  Assert.WillRaise(
    procedure
    begin
      FParser.ReadGenerationNumber;
    end,
    EPdfParseException);
end;

procedure TBaseParserTests.TestReadLine;
begin
  Start('abc'#13#10'def'#10#10'ghi'#13'jkl');

  Assert.AreEqual('abc', FParser.ReadLine);
  Assert.AreEqual('def', FParser.ReadLine);
  Assert.AreEqual('', FParser.ReadLine);
  Assert.AreEqual('ghi', FParser.ReadLine);
  Assert.AreEqual('jkl', FParser.ReadLine);
  Assert.WillRaise(
    procedure
    begin
      FParser.ReadLine;
    end,
    EPdfParseException);
end;

procedure TBaseParserTests.TestReadStringAndExpected;
begin
  Start('  hello/world 12 xref');

  Assert.AreEqual('hello', FParser.ReadString);
  Assert.AreEqual(Int64(7), FParser.Source.GetPosition);
  FParser.ParseCosName.Free;
  Assert.AreEqual(Int64(12), FParser.ReadLong);
  FParser.ReadExpectedString('xref');
  Assert.IsTrue(FParser.Source.IsEOF);

  Start('xreg');
  Assert.WillRaise(
    procedure
    begin
      FParser.ReadExpectedString('xref');
    end,
    EPdfParseException);

  Start('R');
  Assert.WillRaise(
    procedure
    begin
      FParser.ReadExpectedChar('r');
    end,
    EPdfParseException);
  Start('');
  Assert.WillRaise(
    procedure
    begin
      FParser.ReadExpectedChar('r');
    end,
    EPdfParseException);
end;

procedure TBaseParserTests.TestCharacterClasses;
begin
  const WhitespaceCodes: TArray<Integer> = [0, 9, 12, 10, 13, 32];
  for var Code in WhitespaceCodes do
  begin
    Assert.IsTrue(TBaseParser.IsWhitespace(Code), Format('whitespace %d', [Code]));
  end;
  Assert.IsFalse(TBaseParser.IsWhitespace(Ord('a')));
  Assert.IsFalse(TBaseParser.IsWhitespace(-1));

  Assert.IsTrue(TBaseParser.IsEOL(10));
  Assert.IsTrue(TBaseParser.IsEOL(13));
  Assert.IsFalse(TBaseParser.IsEOL(32));
  Assert.IsFalse(TBaseParser.IsEOL(-1));

  Assert.IsTrue(TBaseParser.IsDigit(Ord('0')));
  Assert.IsTrue(TBaseParser.IsDigit(Ord('9')));
  Assert.IsFalse(TBaseParser.IsDigit(Ord('a')));
  Assert.IsFalse(TBaseParser.IsDigit(-1));

  const DelimiterCodes: TArray<Integer> = [32, 13, 10, 9, 62, 60, 91, 47, 93, 41, 40, 0, 12, 37, -1];
  for var Delimiter in DelimiterCodes do
  begin
    Assert.IsTrue(TBaseParser.IsEndOfName(Delimiter), Format('end of name %d', [Delimiter]));
  end;
  Assert.IsFalse(TBaseParser.IsEndOfName(Ord('a')));
  Assert.IsFalse(TBaseParser.IsEndOfName(Ord('#')));
end;

procedure TBaseParserTests.TestSkipLinebreakAndWhiteSpaces;
begin
  Start(#13#10'a'#10'b'#13'c');

  Assert.IsTrue(FParser.SkipLinebreak);
  Assert.AreEqual(Ord('a'), FParser.Source.Read);
  Assert.IsTrue(FParser.SkipLinebreak);
  Assert.IsFalse(FParser.SkipLinebreak);
  Assert.AreEqual(Ord('b'), FParser.Source.Read);
  Assert.IsTrue(FParser.SkipLinebreak);
  Assert.AreEqual(Ord('c'), FParser.Source.Read);
  Assert.IsFalse(FParser.SkipLinebreak);

  Start('   '#13#10'data');
  FParser.SkipWhiteSpaces;
  Assert.AreEqual(Ord('d'), FParser.Source.Read);

  Start('   data');
  FParser.SkipWhiteSpaces;
  Assert.AreEqual(Ord('d'), FParser.Source.Read);
end;

procedure TBaseParserTests.TestMalformedInputNeverHangs;
begin
  const Alphabet = '<>[]()/%\#.+-0123456789 '#10#13'RnulltruefalsendobjendstreamabcE';
  var Seed: Cardinal := 12345;

  for var Round := 1 to 400 do
  begin
    var Text := '';
    const TextLength = 1 + (Round mod 40);
    for var Index := 1 to TextLength do
    begin
      Seed := Cardinal((UInt64(Seed) * 1664525 + 1013904223) and $FFFFFFFF);
      Text := Text + Alphabet[1 + Integer((Seed shr 16) mod Cardinal(System.Length(Alphabet)))];
    end;

    Start(Text);
    for var Attempt := 1 to 60 do
    begin
      var Value: TCosBase;
      try
        Value := FParser.ParseDirObject;
      except
        on EPdfException do
        begin
          Break;
        end;
      end;

      const IsEnd = not Assigned(Value);
      Value.Free;
      if IsEnd then
      begin
        Break;
      end;
    end;
  end;
  Assert.Pass;
end;

end.
