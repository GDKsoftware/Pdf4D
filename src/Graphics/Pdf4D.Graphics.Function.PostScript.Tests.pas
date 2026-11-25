// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Tests of Pdf4D for the type 4 (PostScript calculator) functions of PDFBox (3.0.8); the reference values
// (tests/reference/functions) come from PDFBox
unit Pdf4D.Graphics.&Function.PostScript.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Graphics.&Function,
  Pdf4D.Graphics.&Function.PostScript,
  Pdf4D.Tests.Functions;

type
  [TestFixture]
  TPostScriptFunctionTests = class
  private
    FBuilder: TFunctionTestBuilder;

    class procedure AssertCount(const Expected: Integer; const Actual: Int64; const Message: string = ''); static;
    class procedure AssertNear(const Expected: Double; const Actual: Single; const Tolerance: Double; const Message: string = ''); static;
    function NewFunction(const Code, Domain, Range: string): TPDFunction;
    function Run(const Code: string; const Input: TArray<Single>; out Outcome: TPsOutcome): TArray<TPsValue>;
    class function Repeated(const Text: string; const Count: Integer): string; static;
    procedure CheckOperatorCase(const OperatorCase: TArray<string>);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestType4InstructionsOfAPageAreBudgeted;

    [Test]
    procedure TestType4DupMul;

    [Test]
    procedure TestType4IfElse;

    [Test]
    procedure TestType4AllOperators;

    [Test]
    procedure TestType4InfiniteLoopIsBounded;

    [Test]
    procedure TestType4StackUnderflowGivesPartialResult;

    [Test]
    procedure TestType4StackLimitGivesOneWarning;

    [Test]
    procedure TestType4WarnsOncePerFunction;

    [Test]
    procedure TestType4UnknownOperatorStopsWhenItRuns;

    [Test]
    procedure TestType4NestingOfHundredProceduresIsAccepted;

    [Test]
    procedure TestType4NestingBeyondTheLimitRaises;

    [Test]
    procedure TestType4NumberThatDoesNotFitRaises;

    [Test]
    procedure TestType4NeedsAStreamWithDomainAndRange;

    [Test]
    procedure TestType4UsesTheTopOfTheStackAsOutputs;

    [Test]
    procedure TestType4ClipsInputAndOutput;

    [Test]
    procedure TestType4EvaluatesRepeatedly;

    [Test]
    procedure TestProgramOutcomes;

    [Test]
    procedure TestProgramKeepsIntegersAndReals;

    [Test]
    procedure TestCopyWithNegativeCountCopiesNothing;

    [Test]
    procedure TestCopyBeyondTheStackFails;

    [Test]
    procedure TestRollWithLowestShiftFails;

    [Test]
    procedure TestRealBeyondTheRangeIsInfinity;
  end;

implementation

uses
  System.Math;

const
  OutputTolerance = 0.0001;
  WideRange = '-100000000000 100000000000';
  WideDomain = '-1000 1000';


type
  TOperatorCase = record
    Name: string;
    Code: string;
    Domain: string;
    Range: string;
    Input: string;
    Expected: string;
  end;

const
  // One case for every operator of table 42 of PDF 32000: the program, the Domain and Range, the input and the output of PDFBox
  OperatorCases: array[0..41] of TOperatorCase = (
    (Name: 'abs'; Code: '{ abs }'; Domain: WideDomain; Range: WideRange; Input: '-3.5'; Expected: '3.5'),
    (Name: 'add'; Code: '{ 2 add }'; Domain: WideDomain; Range: WideRange; Input: '1.5'; Expected: '3.5'),
    (Name: 'and'; Code: '{ pop 12 10 and }'; Domain: WideDomain; Range: WideRange; Input: '0'; Expected: '8.0'),
    (Name: 'atan'; Code: '{ pop 1 1 atan }'; Domain: WideDomain; Range: WideRange; Input: '0'; Expected: '45.0'),
    (Name: 'bitshift'; Code: '{ pop 1 3 bitshift }'; Domain: WideDomain; Range: WideRange; Input: '0'; Expected: '8.0'),
    (Name: 'ceiling'; Code: '{ ceiling }'; Domain: WideDomain; Range: WideRange; Input: '1.2'; Expected: '2.0'),
    (Name: 'copy'; Code: '{ pop 1 2 2 copy }'; Domain: WideDomain; Range: '-100000000000 100000000000 -100000000000 100000000000 -100000000000 100000000000 -100000000000 100000000000'; Input: '0'; Expected: '1.0 2.0 1.0 2.0'),
    (Name: 'cos'; Code: '{ cos }'; Domain: WideDomain; Range: WideRange; Input: '60'; Expected: '0.5'),
    (Name: 'cvi'; Code: '{ cvi }'; Domain: WideDomain; Range: WideRange; Input: '3.7'; Expected: '3.0'),
    (Name: 'cvr'; Code: '{ pop 3 cvr }'; Domain: WideDomain; Range: WideRange; Input: '0'; Expected: '3.0'),
    (Name: 'div'; Code: '{ 4 div }'; Domain: WideDomain; Range: WideRange; Input: '1'; Expected: '0.25'),
    (Name: 'dup'; Code: '{ dup }'; Domain: WideDomain; Range: '-100000000000 100000000000 -100000000000 100000000000'; Input: '0.3'; Expected: '0.3 0.3'),
    (Name: 'eq'; Code: '{ 1 eq { 1 } { 0 } ifelse }'; Domain: WideDomain; Range: WideRange; Input: '1'; Expected: '1.0'),
    (Name: 'exch'; Code: '{ pop 1 2 exch }'; Domain: WideDomain; Range: '-100000000000 100000000000 -100000000000 100000000000'; Input: '0'; Expected: '2.0 1.0'),
    (Name: 'exp'; Code: '{ 3 exp }'; Domain: WideDomain; Range: WideRange; Input: '2'; Expected: '8.0'),
    (Name: 'false'; Code: '{ pop false { 1 } { 0 } ifelse }'; Domain: WideDomain; Range: WideRange; Input: '0'; Expected: '0.0'),
    (Name: 'floor'; Code: '{ floor }'; Domain: WideDomain; Range: WideRange; Input: '1.7'; Expected: '1.0'),
    (Name: 'ge'; Code: '{ 0.5 ge { 1 } { 0 } ifelse }'; Domain: WideDomain; Range: WideRange; Input: '0.4'; Expected: '0.0'),
    (Name: 'gt'; Code: '{ 0.5 gt { 1 } { 0 } ifelse }'; Domain: WideDomain; Range: WideRange; Input: '0.4'; Expected: '0.0'),
    (Name: 'idiv'; Code: '{ pop 7 2 idiv }'; Domain: WideDomain; Range: WideRange; Input: '0'; Expected: '3.0'),
    (Name: 'if'; Code: '{ dup 0.5 gt { pop 9 } if }'; Domain: WideDomain; Range: WideRange; Input: '0.7'; Expected: '9.0'),
    (Name: 'ifelse'; Code: '{ 0.5 gt { 1 } { 0 } ifelse }'; Domain: WideDomain; Range: WideRange; Input: '0.7'; Expected: '1.0'),
    (Name: 'index'; Code: '{ pop 10 20 30 2 index }'; Domain: WideDomain; Range: '-100000000000 100000000000 -100000000000 100000000000 -100000000000 100000000000 -100000000000 100000000000'; Input: '0'; Expected: '10.0 20.0 30.0 10.0'),
    (Name: 'le'; Code: '{ 0.5 le { 1 } { 0 } ifelse }'; Domain: WideDomain; Range: WideRange; Input: '0.4'; Expected: '1.0'),
    (Name: 'ln'; Code: '{ ln }'; Domain: WideDomain; Range: WideRange; Input: '2.718281828'; Expected: '0.99999994'),
    (Name: 'log'; Code: '{ log }'; Domain: WideDomain; Range: WideRange; Input: '100'; Expected: '2.0'),
    (Name: 'lt'; Code: '{ 0.5 lt { 1 } { 0 } ifelse }'; Domain: WideDomain; Range: WideRange; Input: '0.4'; Expected: '1.0'),
    (Name: 'mod'; Code: '{ pop 7 3 mod }'; Domain: WideDomain; Range: WideRange; Input: '0'; Expected: '1.0'),
    (Name: 'mul'; Code: '{ 3 mul }'; Domain: WideDomain; Range: WideRange; Input: '2'; Expected: '6.0'),
    (Name: 'ne'; Code: '{ 0.5 ne { 1 } { 0 } ifelse }'; Domain: WideDomain; Range: WideRange; Input: '0.4'; Expected: '1.0'),
    (Name: 'neg'; Code: '{ neg }'; Domain: WideDomain; Range: WideRange; Input: '2'; Expected: '-2.0'),
    (Name: 'not'; Code: '{ pop 5 not }'; Domain: WideDomain; Range: WideRange; Input: '0'; Expected: '-5.0'),
    (Name: 'or'; Code: '{ pop 12 10 or }'; Domain: WideDomain; Range: WideRange; Input: '0'; Expected: '14.0'),
    (Name: 'pop'; Code: '{ pop 1 2 pop }'; Domain: WideDomain; Range: WideRange; Input: '0'; Expected: '1.0'),
    (Name: 'roll'; Code: '{ pop 1 2 3 3 1 roll }'; Domain: WideDomain; Range: '-100000000000 100000000000 -100000000000 100000000000 -100000000000 100000000000'; Input: '0'; Expected: '3.0 1.0 2.0'),
    (Name: 'round'; Code: '{ round }'; Domain: WideDomain; Range: WideRange; Input: '2.5'; Expected: '3.0'),
    (Name: 'sin'; Code: '{ sin }'; Domain: WideDomain; Range: WideRange; Input: '30'; Expected: '0.5'),
    (Name: 'sqrt'; Code: '{ sqrt }'; Domain: WideDomain; Range: WideRange; Input: '4'; Expected: '2.0'),
    (Name: 'sub'; Code: '{ 1 sub }'; Domain: WideDomain; Range: WideRange; Input: '3'; Expected: '2.0'),
    (Name: 'true'; Code: '{ pop true { 1 } { 0 } ifelse }'; Domain: WideDomain; Range: WideRange; Input: '0'; Expected: '1.0'),
    (Name: 'truncate'; Code: '{ truncate }'; Domain: WideDomain; Range: WideRange; Input: '2.7'; Expected: '2.0'),
    (Name: 'xor'; Code: '{ pop 12 10 xor }'; Domain: WideDomain; Range: WideRange; Input: '0'; Expected: '6.0'));

{ TPostScriptFunctionTests }

class procedure TPostScriptFunctionTests.AssertCount(const Expected: Integer; const Actual: Int64; const Message: string);
begin
  Assert.AreEqual(Int64(Expected), Actual, Message);
end;

class procedure TPostScriptFunctionTests.AssertNear(const Expected: Double; const Actual: Single; const Tolerance: Double; const Message: string);
begin
  Assert.AreEqual(Expected, Double(Actual), Tolerance, Message);
end;

procedure TPostScriptFunctionTests.Setup;
begin
  FBuilder := TFunctionTestBuilder.Create;
end;

procedure TPostScriptFunctionTests.TearDown;
begin
  FBuilder.Free;
end;

function TPostScriptFunctionTests.NewFunction(const Code, Domain, Range: string): TPDFunction;
begin
  Result := TPDFunction.Create(FBuilder.NewType4(Domain, Range, Code), FBuilder.Context);
end;

function TPostScriptFunctionTests.Run(const Code: string; const Input: TArray<Single>; out Outcome: TPsOutcome): TArray<TPsValue>;
begin
  const ProgramToRun = TPsProgram.Parse(Code);
  try
    Result := ProgramToRun.Run(Input, Outcome);
  finally
    ProgramToRun.Free;
  end;
end;

class function TPostScriptFunctionTests.Repeated(const Text: string; const Count: Integer): string;
begin
  const Builder = TStringBuilder.Create;
  try
    for var Index := 1 to Count do
    begin
      Builder.Append(Text);
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

procedure TPostScriptFunctionTests.TestType4DupMul;
begin
  const Function_ = NewFunction('{ dup mul }', '0 1', '0 1');
  try
    AssertNear(0.25, Function_.Eval([0.5])[0], 0.0000001);
    Assert.AreEqual(4, Function_.FunctionType);
    Assert.AreEqual(1, Function_.NumberOfInputParameters);
    Assert.AreEqual(1, Function_.NumberOfOutputParameters);
  finally
    Function_.Free;
  end;
end;

procedure TPostScriptFunctionTests.TestType4IfElse;
begin
  const Function_ = NewFunction('{ 0.5 gt { 1 } { 0 } ifelse }', '0 1', '0 1');
  try
    AssertNear(1.0, Function_.Eval([0.7])[0], 0.0000001);
    AssertNear(0.0, Function_.Eval([0.2])[0], 0.0000001);
  finally
    Function_.Free;
  end;
end;

procedure TPostScriptFunctionTests.CheckOperatorCase(const OperatorCase: TArray<string>);
begin
  const OperatorName = OperatorCase[0];
  const Function_ = NewFunction(OperatorCase[1], OperatorCase[2], OperatorCase[3]);
  try
    const Expected = TFunctionTestBuilder.ParseSingles(OperatorCase[5]);
    const Actual = Function_.Eval(TFunctionTestBuilder.ParseSingles(OperatorCase[4]));

    Assert.AreEqual(Length(Expected), Length(Actual), Format('%s: number of outputs', [OperatorName]));
    for var Index := 0 to Length(Actual) - 1 do
    begin
      AssertNear(Expected[Index], Actual[Index], Max(OutputTolerance, Abs(Expected[Index]) * 0.000001),
                      Format('%s: output %d of %s', [OperatorName, Index, OperatorCase[1]]));
    end;
  finally
    Function_.Free;
  end;
end;

procedure TPostScriptFunctionTests.TestType4AllOperators;
begin
  AssertCount(42, Length(OperatorCases), 'every operator of table 42 of PDF 32000 has a case');
  for var OperatorCase in OperatorCases do
  begin
    CheckOperatorCase([OperatorCase.Name, OperatorCase.Code, OperatorCase.Domain, OperatorCase.Range, OperatorCase.Input, OperatorCase.Expected]);
  end;
end;

procedure TPostScriptFunctionTests.TestType4InfiniteLoopIsBounded;
begin
  const Code = '{ ' + Repeated('1 pop ', MaxPostScriptOperations) + '0.75 }';
  const Function_ = NewFunction(Code, '0 1', '0 1');
  try
    const Values = Function_.Eval([0.25]);

    AssertCount(1, Length(Values));
    AssertNear(0.25, Values[0], 0.0000001, 'the stack as it was when the operations ran out');
    Assert.AreEqual(1, FBuilder.WarningCount);
    Assert.IsTrue(FBuilder.Messages[0].Contains(IntToStr(MaxPostScriptOperations)), 'the warning names the limit');
  finally
    Function_.Free;
  end;
end;

procedure TPostScriptFunctionTests.TestType4StackUnderflowGivesPartialResult;
begin
  const Function_ = NewFunction('{ 0.8 add exch }', '0 1', '0 2 0 1');
  try
    const Values = Function_.Eval([0.5]);

    AssertCount(2, Length(Values));
    AssertNear(1.3, Values[0], 0.0000001, 'the sum that was made before exch failed');
    AssertNear(0.0, Values[1], 0.0000001, 'there is no second value');
    Assert.AreEqual(1, FBuilder.WarningCount);
  finally
    Function_.Free;
  end;
end;

procedure TPostScriptFunctionTests.TestType4StackLimitGivesOneWarning;
begin
  const Function_ = NewFunction('{ ' + Repeated('0.5 ', MaxPostScriptStackSize + 1) + '}', '0 1', '0 1');
  try
    const Values = Function_.Eval([0.25]);

    AssertNear(0.5, Values[0], 0.0000001);
    Assert.AreEqual(1, FBuilder.WarningCount);
    Assert.IsTrue(FBuilder.Messages[0].Contains(IntToStr(MaxPostScriptStackSize)), 'the warning names the limit');
  finally
    Function_.Free;
  end;
end;

procedure TPostScriptFunctionTests.TestType4WarnsOncePerFunction;
begin
  const Function_ = NewFunction('{ pop pop }', '0 1', '0 1');
  const Other = NewFunction('{ pop pop }', '0 1', '0 1');
  try
    Function_.Eval([0.5]);
    Function_.Eval([0.6]);
    Assert.AreEqual(1, FBuilder.WarningCount, 'one function warns once');

    Other.Eval([0.5]);
    Assert.AreEqual(2, FBuilder.WarningCount, 'every function has its own warning');
  finally
    Other.Free;
    Function_.Free;
  end;
end;

procedure TPostScriptFunctionTests.TestType4UnknownOperatorStopsWhenItRuns;
begin
  const Function_ = NewFunction('{ 0.5 foo 0.75 }', '0 1', '0 1');
  const Unreached = NewFunction('{ 0.5 true { 0.75 } { foo } ifelse }', '0 1', '0 1');
  try
    AssertNear(0.5, Function_.Eval([0.25])[0], 0.0000001, 'the values before the operator are kept');
    Assert.AreEqual(1, FBuilder.WarningCount);
    AssertNear(0.75, Unreached.Eval([0.25])[0], 0.0000001, 'an unknown operator that does not run does no harm, as in PDFBox');
    Assert.AreEqual(1, FBuilder.WarningCount);
  finally
    Unreached.Free;
    Function_.Free;
  end;
end;

procedure TPostScriptFunctionTests.TestType4NestingOfHundredProceduresIsAccepted;
begin
  const Code = '{ ' + Repeated('{ ', MaxPostScriptProcedureDepth) + Repeated('} ', MaxPostScriptProcedureDepth) + '0.75 }';
  const Function_ = NewFunction(Code, '0 1', '0 1');
  try
    AssertNear(0.75, Function_.Eval([0.25])[0], 0.0000001);
    Assert.AreEqual(0, FBuilder.WarningCount);
  finally
    Function_.Free;
  end;
end;

procedure TPostScriptFunctionTests.TestType4NestingBeyondTheLimitRaises;
begin
  const Code = '{ ' + Repeated('{ ', MaxPostScriptProcedureDepth + 1) + Repeated('} ', MaxPostScriptProcedureDepth + 1) + '0.75 }';
  const Stream = FBuilder.NewType4('0 1', '0 1', Code);

  Assert.WillRaise(
    procedure
    begin
      TPDFunction.Create(Stream, FBuilder.Context).Free;
    end, EPdfParseException);
end;

procedure TPostScriptFunctionTests.TestType4NumberThatDoesNotFitRaises;
begin
  const Codes: TArray<string> = ['{ 2147483648 }', '{ -2147483649 }', '{ . }', '{ -. }'];
  for var Code in Codes do
  begin
    const Stream = FBuilder.NewType4('0 1', '0 1', Code);
    Assert.WillRaise(
      procedure
      begin
        TPDFunction.Create(Stream, FBuilder.Context).Free;
      end, EPdfParseException, Code);
  end;
end;

procedure TPostScriptFunctionTests.TestType4NeedsAStreamWithDomainAndRange;
begin
  const NotAStream = FBuilder.NewDictionary(4, ['Domain', '0 1', 'Range', '0 1']);
  const NoDomain = FBuilder.NewStream(4, ['Range', '0 1'], TEncoding.ASCII.GetBytes('{ }'));
  const NoRange = FBuilder.NewStream(4, ['Domain', '0 1'], TEncoding.ASCII.GetBytes('{ }'));

  var Broken: TArray<TCosDictionary> := [NotAStream, NoDomain, NoRange];
  for var Invalid in Broken do
  begin
    Assert.WillRaise(
      procedure
      begin
        TPDFunction.Create(Invalid, FBuilder.Context).Free;
      end, EPdfParseException);
  end;
end;

procedure TPostScriptFunctionTests.TestType4UsesTheTopOfTheStackAsOutputs;
begin
  const Function_ = NewFunction('{ dup dup }', '0 1', '0 1');
  const Two = NewFunction('{ 0.25 0.75 }', '0 1', '0 1 0 1');
  try
    AssertCount(1, Length(Function_.Eval([0.5])));
    AssertCount(2, Length(Two.Eval([0.5])));
    AssertNear(0.25, Two.Eval([0.5])[0], 0.0000001, 'the first output is the deeper value');
    AssertNear(0.75, Two.Eval([0.5])[1], 0.0000001);
  finally
    Two.Free;
    Function_.Free;
  end;
end;

procedure TPostScriptFunctionTests.TestType4ClipsInputAndOutput;
begin
  const Function_ = NewFunction('{ 2 mul }', '0 1', '0 1.5');
  try
    AssertNear(1.5, Function_.Eval([0.9])[0], 0.0000001, 'the output is clipped to the range');
    AssertNear(0.0, Function_.Eval([-5])[0], 0.0000001, 'the input is clipped to the domain');
    AssertNear(1.5, Function_.Eval([5])[0], 0.0000001, 'the input 1 gives 2, clipped to 1.5');
  finally
    Function_.Free;
  end;
end;

procedure TPostScriptFunctionTests.TestType4EvaluatesRepeatedly;
begin
  const Function_ = NewFunction('{ dup 0.5 gt { 1 exch sub } if }', '0 1', '0 1');
  try
    for var Round := 1 to 3 do
    begin
      AssertNear(0.25, Function_.Eval([0.25])[0], 0.0000001);
      AssertNear(0.25, Function_.Eval([0.75])[0], 0.0000001);
    end;
    Assert.AreEqual(0, FBuilder.WarningCount);
  finally
    Function_.Free;
  end;
end;

procedure TPostScriptFunctionTests.TestProgramOutcomes;
begin
  var Outcome: TPsOutcome;

  Run('{ 1 2 add }', [], Outcome);
  Assert.AreEqual(Ord(TPsOutcome.Completed), Ord(Outcome));

  Run('{ add }', [1], Outcome);
  Assert.AreEqual(Ord(TPsOutcome.Failed), Ord(Outcome), 'a stack underflow');

  Run('{ true 1 add }', [], Outcome);
  Assert.AreEqual(Ord(TPsOutcome.Failed), Ord(Outcome), 'a boolean where a number is needed');

  Run('{ foo }', [], Outcome);
  Assert.AreEqual(Ord(TPsOutcome.Failed), Ord(Outcome), 'an unknown operator');

  Run('{ ' + Repeated('1 ', MaxPostScriptStackSize + 1) + '}', [], Outcome);
  Assert.AreEqual(Ord(TPsOutcome.StackLimit), Ord(Outcome));

  Run('{ ' + Repeated('1 pop ', MaxPostScriptOperations) + '}', [], Outcome);
  Assert.AreEqual(Ord(TPsOutcome.OperationLimit), Ord(Outcome));
end;

// The context counts the instructions of all type 4 functions: when the budget is spent the function gives the start of its range
procedure TPostScriptFunctionTests.TestType4InstructionsOfAPageAreBudgeted;
begin
  const Function_ = NewFunction('{ pop 0.75 }', '0 1', '0 1');
  try
    Assert.AreEqual<Single>(0.75, Function_.Eval([0.5])[0], 'no budget is started: no limit');

    FBuilder.Context.BeginFunctionWork(40);
    Assert.AreEqual<Single>(0.75, Function_.Eval([0.5])[0]);
    Assert.IsFalse(FBuilder.Context.IsFunctionWorkExhausted);
    for var Index := 1 to 10 do
    begin
      Function_.Eval([0.5]);
    end;

    Assert.IsTrue(FBuilder.Context.IsFunctionWorkExhausted);
    Assert.AreEqual<Single>(0, Function_.Eval([0.5])[0], 'the start of the range');

    FBuilder.Context.BeginFunctionWork(40);
    Assert.AreEqual<Single>(0.75, Function_.Eval([0.5])[0], 'a new page starts a new budget');
  finally
    Function_.Free;
  end;
end;

procedure TPostScriptFunctionTests.TestProgramKeepsIntegersAndReals;
begin
  var Outcome: TPsOutcome;

  const Sum = Run('{ 2147483647 1 add }', [], Outcome);
  const Quotient = Run('{ 7 2 idiv }', [], Outcome);
  const Division = Run('{ 7 2 div }', [], Outcome);
  const Failed = Run('{ 7.0 2 idiv }', [], Outcome);

  Assert.AreEqual(Ord(TPsValueKind.Real), Ord(Sum[0].Kind), 'an integer sum that does not fit becomes a real');
  Assert.AreEqual(Ord(TPsValueKind.Int), Ord(Quotient[0].Kind));
  Assert.AreEqual(3, Quotient[0].IntValue);
  AssertNear(3.5, Division[0].RealValue, 0.0000001);
  Assert.AreEqual(Ord(TPsOutcome.Failed), Ord(Outcome), 'idiv wants integers');
  AssertCount(0, Length(Failed), 'both operands were taken from the stack');
end;

procedure TPostScriptFunctionTests.TestCopyWithNegativeCountCopiesNothing;
begin
  var Outcome: TPsOutcome;

  const Lowest = Run('{ 7 -2147483648 copy }', [], Outcome);
  Assert.AreEqual(Ord(TPsOutcome.Completed), Ord(Outcome), 'the lowest count');
  AssertCount(1, Length(Lowest));
  Assert.AreEqual(7, Lowest[0].IntValue);

  const Small = Run('{ 7 -5 copy }', [], Outcome);
  Assert.AreEqual(Ord(TPsOutcome.Completed), Ord(Outcome), 'a small negative count');
  AssertCount(1, Length(Small));
end;

procedure TPostScriptFunctionTests.TestCopyBeyondTheStackFails;
begin
  var Outcome: TPsOutcome;

  const Values = Run('{ 7 5 copy }', [], Outcome);

  Assert.AreEqual(Ord(TPsOutcome.Failed), Ord(Outcome));
  AssertCount(1, Length(Values), 'the stack as it was');
end;

procedure TPostScriptFunctionTests.TestRollWithLowestShiftFails;
begin
  var Outcome: TPsOutcome;

  const Values = Run('{ 1 2 3 3 -2147483648 roll }', [], Outcome);

  Assert.AreEqual(Ord(TPsOutcome.Failed), Ord(Outcome), 'PDFBox would pop 2^31 values');
  AssertCount(3, Length(Values));
end;

procedure TPostScriptFunctionTests.TestRealBeyondTheRangeIsInfinity;
begin
  var Outcome: TPsOutcome;

  const Positive = Run('{ 1.0e999 }', [], Outcome);
  Assert.AreEqual(Ord(TPsOutcome.Completed), Ord(Outcome));
  Assert.IsTrue(IsInfinite(Positive[0].RealValue) and (Positive[0].RealValue > 0), '1e999');

  const Negative = Run('{ -1.0e999 }', [], Outcome);
  Assert.IsTrue(IsInfinite(Negative[0].RealValue) and (Negative[0].RealValue < 0), '-1e999');

  const Tiny = Run('{ 1.0e-999 }', [], Outcome);
  AssertNear(0, Tiny[0].RealValue, 0, '1e-999');
end;

end.
