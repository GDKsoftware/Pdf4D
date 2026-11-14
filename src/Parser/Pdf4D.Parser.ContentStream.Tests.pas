// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Parser.ContentStream.Tests;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Common.Defines,
  Pdf4D.Common.Log,
  Pdf4D.Parser.ContentStream;

type
  [TestFixture]
  TPdfStreamParserTests = class
  private
    FParser: TPdfStreamParser;
    FLogLines: TList<string>;
    FLog: TPdfLog;
    FErrorCount: Integer;

    procedure Start(const Data: TBytes); overload;
    procedure Start(const Data: TBytes; const MaxInlineImageSize: Integer); overload;
    procedure Start(const Text: AnsiString); overload;
    function DescribeNextToken: string;
    function DescribeAll: string;
    procedure DiscardNextToken;
    function BytesOf(const Text: AnsiString): TBytes;
    function InlineImageWithData(const Data: TBytes; const Tail: AnsiString): TBytes;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestTextOperators;

    [Test]
    procedure TestReferenceSyntaxIsNumbersAndOperator;

    [Test]
    procedure TestInlineImage;

    [Test]
    procedure TestInlineImageWithEIInsideData;

    [Test]
    procedure TestManyIgnoredEIAreLoggedOnlyTheFirstTimes;

    [Test]
    procedure TestInlineImageWithoutEIEndsStream;

    [Test]
    procedure TestInlineImageLimit;

    [Test]
    procedure TestGarbageDoesNotHang;

    [Test]
    procedure TestNumbersAndKeywords;

    [Test]
    procedure TestNegativeZeroIsZero;

    [Test]
    procedure TestArrayAndDictionaryOperands;

    [Test]
    procedure TestStrayClosingBracketIsNull;

    [Test]
    procedure TestIsolatedPlusIsNull;

    [Test]
    procedure TestUnbalancedArrayAtEndOfStream;

    [Test]
    procedure TestUnbalancedDictionaryEndsStream;

    [Test]
    procedure TestManyOperandsBeforeOperator;

    [Test]
    procedure TestNestedBeginInlineImageRaises;

    [Test]
    procedure TestInlineImageDataWithoutIDRaises;

    [Test]
    procedure TestParseReturnsAllTokens;

    [Test]
    procedure TestType3Operators;
  end;

implementation

uses
  System.Classes,
  System.Diagnostics,
  Pdf4D.Content.Operator,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Boolean,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Float,
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Null,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Cos.PdfString;

{ TPdfStreamParserTests }

procedure TPdfStreamParserTests.Setup;
begin
  FLogLines := TList<string>.Create;
  FErrorCount := 0;
  FLog := TPdfLog.Create(
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      FLogLines.Add(Message);
      if Level = TPdfLogLevel.Error then
      begin
        Inc(FErrorCount);
      end;
    end);
end;

procedure TPdfStreamParserTests.TearDown;
begin
  FreeAndNil(FParser);
  FreeAndNil(FLog);
  FreeAndNil(FLogLines);
end;

procedure TPdfStreamParserTests.Start(const Data: TBytes);
begin
  Start(Data, DefaultMaxInlineImageSize);
end;

procedure TPdfStreamParserTests.Start(const Data: TBytes; const MaxInlineImageSize: Integer);
begin
  FreeAndNil(FParser);

  var Options := TPdfLoadOptions.Default;
  Options.MaxInlineImageSize := MaxInlineImageSize;
  FParser := TPdfStreamParser.Create(Data, Options, FLog);
end;

procedure TPdfStreamParserTests.Start(const Text: AnsiString);
begin
  Start(BytesOf(Text));
end;

function TPdfStreamParserTests.BytesOf(const Text: AnsiString): TBytes;
begin
  SetLength(Result, Length(Text));
  for var Index := 0 to Length(Text) - 1 do
  begin
    Result[Index] := Byte(Text[Index + 1]);
  end;
end;

function TPdfStreamParserTests.InlineImageWithData(const Data: TBytes; const Tail: AnsiString): TBytes;
begin
  const Head = BytesOf('BI /W 2 /H 1 /BPC 8 /CS /G ID ');
  const After = BytesOf(Tail);
  SetLength(Result, Length(Head) + Length(Data) + Length(After));
  Move(Head[0], Result[0], Length(Head));
  if Length(Data) > 0 then
  begin
    Move(Data[0], Result[Length(Head)], Length(Data));
  end;
  Move(After[0], Result[Length(Head) + Length(Data)], Length(After));
end;

function TPdfStreamParserTests.DescribeNextToken: string;
begin
  const Token = FParser.ParseNextToken;
  try
    if not Assigned(Token) then
    begin
      Result := '<end>';
    end
    else if Token is TContentOperator then
    begin
      Result := 'op ' + TContentOperator(Token).Name;
    end
    else if Token is TCosName then
    begin
      Result := '/' + TCosName(Token).Name;
    end
    else if Token is TCosInteger then
    begin
      Result := IntToStr(TCosInteger(Token).Value);
    end
    else if Token is TCosFloat then
    begin
      Result := 'f' + FloatToStr(TCosFloat(Token).FloatValue, TFormatSettings.Invariant);
    end
    else if Token is TCosString then
    begin
      Result := '(' + TCosString(Token).GetString + ')';
    end
    else if Token is TCosBoolean then
    begin
      Result := LowerCase(BoolToStr(TCosBoolean(Token).Value, True));
    end
    else if Token is TCosNull then
    begin
      Result := 'null';
    end
    else if Token is TCosArray then
    begin
      Result := Format('array[%d]', [TCosArray(Token).Count]);
    end
    else if Token is TCosDictionary then
    begin
      Result := Format('dict[%d]', [TCosDictionary(Token).Count]);
    end
    else
    begin
      Result := Token.ClassName;
    end;
  finally
    Token.Free;
  end;
end;

procedure TPdfStreamParserTests.DiscardNextToken;
begin
  const Token = FParser.ParseNextToken;
  Token.Free;
end;

function TPdfStreamParserTests.DescribeAll: string;
begin
  const Parts = TList<string>.Create;
  try
    var Part := DescribeNextToken;
    while Part <> '<end>' do
    begin
      Parts.Add(Part);
      Part := DescribeNextToken;
    end;
    Result := string.Join(', ', Parts.ToArray);
  finally
    Parts.Free;
  end;
end;

procedure TPdfStreamParserTests.TestTextOperators;
begin
  Start('BT /F1 12 Tf (Hi) Tj ET');

  Assert.AreEqual('op BT, /F1, 12, op Tf, (Hi), op Tj, op ET', DescribeAll);
end;

procedure TPdfStreamParserTests.TestReferenceSyntaxIsNumbersAndOperator;
begin
  Start('1 0 R');

  Assert.AreEqual('1, 0, op R', DescribeAll);
end;

procedure TPdfStreamParserTests.TestInlineImage;
begin
  Start(InlineImageWithData(TBytes.Create(0, $FF), ' EI Q'));

  const Token = FParser.ParseNextToken;
  try
    Assert.IsTrue(Token is TContentOperator, 'first token is an operator');
    const BeginOperator = TContentOperator(Token);
    Assert.AreEqual(TOperatorNames.BeginInlineImage, BeginOperator.Name);
    Assert.IsNotNull(BeginOperator.ImageParameters);
    Assert.AreEqual(2, BeginOperator.ImageParameters.GetInt('W', -1));
    Assert.AreEqual(1, BeginOperator.ImageParameters.GetInt('H', -1));
    Assert.AreEqual('G', BeginOperator.ImageParameters.GetNameAsString('CS', ''));
    // like in PDFBox, the white space in front of EI belongs to the data
    Assert.AreEqual<Integer>(3, Length(BeginOperator.ImageData));
    Assert.AreEqual<Integer>(0, BeginOperator.ImageData[0]);
    Assert.AreEqual<Integer>($FF, BeginOperator.ImageData[1]);
    Assert.AreEqual<Integer>($20, BeginOperator.ImageData[2]);
  finally
    Token.Free;
  end;

  Assert.AreEqual('op Q, <end>', DescribeNextToken + ', ' + DescribeNextToken);
  Assert.AreEqual<Integer>(0, FLogLines.Count);
end;

procedure TPdfStreamParserTests.TestInlineImageWithEIInsideData;
begin
  // 'EI' followed by a space and binary bytes is data, the real EI comes later
  const Data = TBytes.Create($41, $20, $45, $49, $20, $01, $02, $FF, $FE, $80, $81, $82, $83);
  Start(InlineImageWithData(Data, 'EI Q'));

  const Token = FParser.ParseNextToken;
  try
    const BeginOperator = TContentOperator(Token);
    Assert.AreEqual<Integer>(Length(Data), Length(BeginOperator.ImageData));
    Assert.IsTrue(CompareMem(@Data[0], @BeginOperator.ImageData[0], Length(Data)), 'all data kept');
  finally
    Token.Free;
  end;

  Assert.AreEqual('op Q', DescribeNextToken);
  Assert.IsTrue(FLogLines.Count > 0, 'the ignored EI is logged');
end;

procedure TPdfStreamParserTests.TestManyIgnoredEIAreLoggedOnlyTheFirstTimes;
begin
  const Fake = BytesOf('EI ') + TBytes.Create($01, $02, $FF, $FE);
  var Data: TBytes;
  for var Count := 1 to 50 do
  begin
    Data := Data + Fake;
  end;
  Start(InlineImageWithData(Data, 'EI Q'));

  const Token = FParser.ParseNextToken;
  try
    Assert.AreEqual<Integer>(Length(Data), Length(TContentOperator(Token).ImageData), 'all fake EI stay in the data');
  finally
    Token.Free;
  end;

  var IgnoredLines := 0;
  var HasCount := False;
  for var Line in FLogLines do
  begin
    if Line.StartsWith('ignoring ''EI''') then
    begin
      Inc(IgnoredLines);
    end;
    HasCount := (HasCount or Line.Contains('without a log line'));
  end;
  Assert.AreEqual(5, IgnoredLines, 'only the first five are logged');
  Assert.IsTrue(HasCount, 'the rest is reported once as a count');
end;

procedure TPdfStreamParserTests.TestInlineImageWithoutEIEndsStream;
begin
  var Data: TBytes;
  SetLength(Data, 10000);
  for var Index := 0 to High(Data) do
  begin
    Data[Index] := Byte(Index mod 7) + $41;
  end;
  const Stream = BytesOf('BI /W 1 ID ');
  var Input: TBytes;
  SetLength(Input, Length(Stream) + Length(Data));
  Move(Stream[0], Input[0], Length(Stream));
  Move(Data[0], Input[Length(Stream)], Length(Data));
  Start(Input);

  const Watch = TStopwatch.StartNew;
  const First = DescribeNextToken;
  const Second = DescribeNextToken;

  Assert.AreEqual('op BI', First);
  Assert.AreEqual('<end>', Second);
  Assert.IsTrue(Watch.ElapsedMilliseconds < 1000, 'ends within a second');
  Assert.IsTrue(FLogLines.Count > 0, 'a warning is logged');
end;

procedure TPdfStreamParserTests.TestInlineImageLimit;
begin
  var Data: TBytes;
  SetLength(Data, 4096);
  FillChar(Data[0], Length(Data), Ord('A'));
  Start(InlineImageWithData(Data, ' EI Q'), 1024);

  const Token = FParser.ParseNextToken;
  try
    Assert.IsTrue(Token is TContentOperator, 'the BI operator is returned');
    Assert.AreEqual<Integer>(0, Length(TContentOperator(Token).ImageData), 'without data');
  finally
    Token.Free;
  end;

  Assert.AreEqual('<end>', DescribeNextToken);
  Assert.IsTrue(FErrorCount > 0, 'an error is logged');
end;

procedure TPdfStreamParserTests.TestGarbageDoesNotHang;
begin
  RandSeed := 3;
  var Data: TBytes;
  SetLength(Data, 64 * 1024);
  for var Index := 0 to High(Data) do
  begin
    Data[Index] := Byte(Random(256));
  end;
  Start(Data);

  const Watch = TStopwatch.StartNew;
  var TokenCount := 0;
  var IsEnded := False;
  try
    while not IsEnded do
    begin
      const Token = FParser.ParseNextToken;
      IsEnded := not Assigned(Token);
      Token.Free;
      Inc(TokenCount);
      Assert.IsTrue(TokenCount <= Length(Data) + 1, 'a token consumes at least one byte');
    end;
  except
    on EPdfException do
    begin
      // a corrupt stream may end in a parse error, like in PDFBox
    end;
  end;

  Assert.IsTrue(Watch.ElapsedMilliseconds < 2000, 'finishes within two seconds');
end;

procedure TPdfStreamParserTests.TestNumbersAndKeywords;
begin
  Start('-5 +3 .5 1.25 --7 1-2 true false null foo');

  Assert.AreEqual('-5, 3, f0.5, f1.25, -7, 12, true, false, null, op foo', DescribeAll);
end;

procedure TPdfStreamParserTests.TestNegativeZeroIsZero;
begin
  // A matrix such as "-1 0 -0 -1" is found in real files
  Start('-0 -00 +0');

  Assert.AreEqual('0, 0, 0', DescribeAll);
end;

procedure TPdfStreamParserTests.TestArrayAndDictionaryOperands;
begin
  Start('[(a) -120 (b)] TJ <</MCID 3>> BDC <4142> Tj');

  Assert.AreEqual('array[3], op TJ, dict[1], op BDC, (AB), op Tj', DescribeAll);
end;

procedure TPdfStreamParserTests.TestStrayClosingBracketIsNull;
begin
  Start('] 1');

  Assert.AreEqual('null, 1', DescribeAll);
end;

procedure TPdfStreamParserTests.TestIsolatedPlusIsNull;
begin
  Start('+ 1');

  Assert.AreEqual('null, 1', DescribeAll);
  Assert.IsTrue(FLogLines.Count > 0);
end;

procedure TPdfStreamParserTests.TestUnbalancedArrayAtEndOfStream;
begin
  Start('1 2 [ (a) [ (b) /c 5 ');

  Assert.AreEqual('1, 2, array[2]', DescribeAll);
end;

procedure TPdfStreamParserTests.TestUnbalancedDictionaryEndsStream;
begin
  var Text := '1 << /A [ ';
  for var Index := 1 to 20000 do
  begin
    Text := Text + '<< /K ';
  end;
  Start(AnsiString(Text));

  const Watch = TStopwatch.StartNew;
  const Described = DescribeAll;

  Assert.AreEqual('1', Described);
  Assert.IsTrue(Watch.ElapsedMilliseconds < 2000);
  Assert.IsTrue(FLogLines.Count > 0);
end;

procedure TPdfStreamParserTests.TestManyOperandsBeforeOperator;
begin
  const Count = 200000;
  var Text := TStringBuilder.Create;
  try
    for var Index := 1 to Count do
    begin
      Text.Append('1 ');
    end;
    Text.Append('m');
    Start(AnsiString(Text.ToString));
  finally
    Text.Free;
  end;

  var Operands := 0;
  var Last := '';
  var Described := DescribeNextToken;
  while Described <> '<end>' do
  begin
    Last := Described;
    Inc(Operands);
    Described := DescribeNextToken;
  end;

  Assert.AreEqual<Integer>(Count + 1, Operands);
  Assert.AreEqual('op m', Last);
end;

procedure TPdfStreamParserTests.TestNestedBeginInlineImageRaises;
begin
  Start('BI /W 1 BI /H 2 ID x EI');

  Assert.WillRaise(
    procedure
    begin
      DiscardNextToken;
    end,
    EPdfParseException);
end;

procedure TPdfStreamParserTests.TestInlineImageDataWithoutIDRaises;
begin
  Start('1 Ix 2');

  Assert.AreEqual('1', DescribeNextToken);
  Assert.WillRaise(
    procedure
    begin
      DiscardNextToken;
    end,
    EPdfParseException);
  Assert.AreEqual('<end>', DescribeNextToken, 'the stream is closed after the error');
end;

procedure TPdfStreamParserTests.TestParseReturnsAllTokens;
begin
  Start('q 1 0 0 1 5 5 cm Q');

  const Tokens = FParser.Parse;
  try
    Assert.AreEqual<Integer>(9, Tokens.Count);
    Assert.AreEqual('cm', TContentOperator(Tokens[7]).Name);
  finally
    Tokens.Free;
  end;
end;

procedure TPdfStreamParserTests.TestType3Operators;
begin
  Start('500 0 d0 1 2 3 4 5 6 d1');

  Assert.AreEqual('500, 0, op d0, 1, 2, 3, 4, 5, 6, op d1', DescribeAll);
end;

end.
