// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/common/function/type4/Parser.java, InstructionSequence.java,
// InstructionSequenceBuilder.java, ExecutionContext.java and Operators.java (3.0.8)
unit Pdf4D.Graphics.&Function.PostScript;

{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  System.Generics.Collections;

const
  // Nesting of { } procedures in the text of a function
  MaxPostScriptProcedureDepth = 100;
  // Values on the operand stack, the input included
  MaxPostScriptStackSize = 1000;
  // Instructions (numbers, operators and procedures) that one run may execute
  MaxPostScriptOperations = 100000;

type
  TPsValueKind = (Int, Real, Bool, Proc);

  // A value of the operand stack. Int and Real keep the difference of PostScript, which PDFBox keeps as well: idiv, mod,
  // bitshift, and, or, xor, copy, index and roll accept integers only.
  TPsValue = record
    Kind: TPsValueKind;
    // The integer, the boolean (0 or 1) or the index of the procedure
    IntValue: Integer;
    RealValue: Single;

    class function FromInt(const Value: Integer): TPsValue; static;
    class function FromReal(const Value: Single): TPsValue; static;
    class function FromBool(const Value: Boolean): TPsValue; static;
    class function FromProc(const Index: Integer): TPsValue; static;

    // An integer or a real as a Single; a boolean gives 1 or 0 and a procedure 0
    function AsSingle: Single;
  end;

  // How a run ended. Everything but Completed leaves the stack as it was at that moment.
  TPsOutcome = (Completed, Failed, StackLimit, OperationLimit);

  TPsOperator = (Unknown, Abs, Add, AndOp, Atan, BitShift, Ceiling, Copy, Cos, Cvi, Cvr, DivOp, Dup, Eq, Exch, Exp, FalseOp,
                 Floor, Ge, Gt, IDiv, IfOp, IfElse, Index, Le, Ln, Log, Lt, ModOp, Mul, Ne, Neg, NotOp, OrOp, Pop, Roll, Round,
                 Sin, Sqrt, Sub, TrueOp, Truncate, XorOp);

  // The floating point behaviour that Java gives and the Delphi RTL does not give for sure (NaN, infinity, saturating casts)
  TFunctionMath = record
    class function Power(const Base, Exponent: Double): Double; static;
    class function PowerWithInfinity(const Base, Exponent: Double): Double; static;
    class function FloorOf(const Value: Double): Double; static;
    class function CeilOf(const Value: Double): Double; static;
    // The cast (int) of Java: truncates, saturates at the limits of an Integer and turns NaN into 0
    class function ToInteger(const Value: Double): Integer; static;
    // Math.round of Java: the nearest integer, halves up, NaN gives 0
    class function RoundHalfUp(const Value: Double): Double; static;
    class function NaturalLog(const Value: Double): Double; static;
    class function Log10Of(const Value: Double): Double; static;
  end;

  TPsInstructionKind = (PushInt, PushReal, PushProc, Execute);

  TPsInstruction = record
    Kind: TPsInstructionKind;
    IntValue: Integer;
    RealValue: Single;
    Operator_: TPsOperator;
  end;

  TPsProcedure = TArray<TPsInstruction>;

  // The program of a type 4 function: the numbers, operators and procedures between the outermost braces. A program is not
  // thread safe (it reuses its stack between runs), like the objects of a document.
  TPsProgram = class
  private
    FProcedures: TList<TPsProcedure>;
    FRootIndex: Integer;
    FStack: TArray<TPsValue>;
    FCount: Integer;
    FOperations: Integer;
    FOutcome: TPsOutcome;

    constructor CreateFrom(const Procedures: TList<TPsProcedure>; const RootIndex: Integer);

    procedure RunProcedure(const Index: Integer);
    function ExecuteInstruction(const Instruction: TPsInstruction): Boolean;
    function ExecuteOperator(const Operation: TPsOperator): Boolean;

    function Push(const Value: TPsValue): Boolean;
    function PushIntegerOrReal(const Value: Int64): Boolean;
    function TryPop(out Value: TPsValue): Boolean;
    function TryPopInteger(out Value: Integer): Boolean;
    function TryPopNumber(out Value: TPsValue): Boolean;
    function TryPopSingle(out Value: Single): Boolean;
    function TryPopBoolean(out Value: Boolean): Boolean;
    function TryPopProcedure(out Index: Integer): Boolean;
    function TryPopTwoNumbers(out First, Second: TPsValue): Boolean;
    function TryPopTwoIntegers(out First, Second: Integer): Boolean;

    function ExecuteAdd(const Operation: TPsOperator): Boolean;
    function ExecuteDivision(const Operation: TPsOperator): Boolean;
    function ExecuteAbsoluteOrNegate(const Operation: TPsOperator): Boolean;
    function ExecuteRounding(const Operation: TPsOperator): Boolean;
    function ExecuteConversion(const Operation: TPsOperator): Boolean;
    function ExecuteTranscendental(const Operation: TPsOperator): Boolean;
    function ExecuteAtan: Boolean;
    function ExecuteExp: Boolean;
    function ExecuteSquareRoot: Boolean;
    function ExecuteLogical(const Operation: TPsOperator): Boolean;
    function ExecuteBitShift: Boolean;
    function ExecuteNot: Boolean;
    function ExecuteComparison(const Operation: TPsOperator): Boolean;
    function ExecuteEquality(const Operation: TPsOperator): Boolean;
    function ExecuteOrdering(const Operation: TPsOperator): Boolean;
    function ExecuteConditional(const Operation: TPsOperator): Boolean;
    function ExecuteStackOperator(const Operation: TPsOperator): Boolean;
    function ExecuteCopy: Boolean;
    function ExecuteIndex: Boolean;
    function ExecuteRoll: Boolean;
    procedure SwapBlocks(const LowerSize, UpperSize: Integer);

    class function AreEqual(const First, Second: TPsValue): Boolean; static;

  public
    // Raises EPdfParseException for a number that does not fit (an integer outside the range of an Integer, a lone "."), and
    // for a nesting deeper than MaxPostScriptProcedureDepth. An unknown operator is no error here: it fails when it runs, as
    // in PDFBox.
    class function Parse(const Text: string): TPsProgram; static;

    destructor Destroy; override;

    // Pushes Input as reals, runs the program and gives the stack, the bottom value first. Stops at the first failing
    // operator (a stack underflow, a value of the wrong type, an unknown operator), at a stack of
    // MaxPostScriptStackSize values and after MaxPostScriptOperations instructions; Outcome says which.
    function Run(const Input: TArray<Single>; out Outcome: TPsOutcome): TArray<TPsValue>;

    // The instructions that the last run executed (the one that stopped it included)
    property Operations: Integer read FOperations;
  end;

implementation

uses
  System.Math,
  Pdf4D.Common.Defines;

const
  OperatorNames: array[TPsOperator] of string = (
    '', 'abs', 'add', 'and', 'atan', 'bitshift', 'ceiling', 'copy', 'cos', 'cvi', 'cvr', 'div', 'dup', 'eq', 'exch', 'exp',
    'false', 'floor', 'ge', 'gt', 'idiv', 'if', 'ifelse', 'index', 'le', 'ln', 'log', 'lt', 'mod', 'mul', 'ne', 'neg', 'not',
    'or', 'pop', 'roll', 'round', 'sin', 'sqrt', 'sub', 'true', 'truncate', 'xor');

  DegreesToRadians = 0.017453292519943295;
  RadiansToDegrees = 57.29577951308232;
  // 2^52: from here on every Double is an integer
  IntegerLimitOfDouble = 4503599627370496.0;
  MaxInt64Double = 9.223372036854775807E18;
  FullCircleDegrees = 360;

type
  // Reads the text of a program and builds the procedures
  TPsParser = class
  private
    FText: string;
    FPosition: Integer;
    FOpenProcedures: TObjectList<TList<TPsInstruction>>;
    FProcedures: TList<TPsProcedure>;
    FIsOutermostOpen: Boolean;
    FHasOutermost: Boolean;

    function TryNextToken(out Token: string): Boolean;
    procedure SkipWhitespaceAndComments;
    class function IsWhitespace(const Character: Char): Boolean; static;
    class function IsDigit(const Character: Char): Boolean; static;
    class function IsIntegerToken(const Token: string): Boolean; static;
    class function IsRealToken(const Token: string): Boolean; static;
    class function IsRealExponent(const Token: string; const Start: Integer): Boolean; static;
    class function ParseInteger(const Token: string): Integer; static;
    class function ParseReal(const Token: string): Single; static;
    class function OutOfRangeValue(const Mantissa, Fraction, Exponent: string): Single; static;
    class function LookupOperator(const Token: string): TPsOperator; static;

    procedure Add(const Instruction: TPsInstruction);
    procedure OpenBrace;
    procedure CloseBrace;
    procedure CloseInnermostProcedure;
    procedure HandleToken(const Token: string);

  public
    constructor Create(const Text: string);
    destructor Destroy; override;

    // Gives the procedures; the root procedure is the last one
    function ParseProgram: TList<TPsProcedure>;
  end;

{ TPsValue }

class function TPsValue.FromInt(const Value: Integer): TPsValue;
begin
  Result.Kind := TPsValueKind.Int;
  Result.IntValue := Value;
  Result.RealValue := 0;
end;

class function TPsValue.FromReal(const Value: Single): TPsValue;
begin
  Result.Kind := TPsValueKind.Real;
  Result.IntValue := 0;
  Result.RealValue := Value;
end;

class function TPsValue.FromBool(const Value: Boolean): TPsValue;
begin
  Result.Kind := TPsValueKind.Bool;
  Result.IntValue := Ord(Value);
  Result.RealValue := 0;
end;

class function TPsValue.FromProc(const Index: Integer): TPsValue;
begin
  Result.Kind := TPsValueKind.Proc;
  Result.IntValue := Index;
  Result.RealValue := 0;
end;

function TPsValue.AsSingle: Single;
begin
  case Kind of
    TPsValueKind.Int:
    begin
      Result := IntValue;
    end;
    TPsValueKind.Real:
    begin
      Result := RealValue;
    end;
    TPsValueKind.Bool:
    begin
      Result := IntValue;
    end;
    else
    begin
      Result := 0;
    end;
  end;
end;

{ TFunctionMath }

class function TFunctionMath.Power(const Base, Exponent: Double): Double;
begin
  if IsNaN(Exponent) then
  begin
    Exit(NaN);
  end;
  if Exponent = 0 then
  begin
    Exit(1);
  end;
  if IsNaN(Base) then
  begin
    Exit(NaN);
  end;
  if IsInfinite(Base) or IsInfinite(Exponent) then
  begin
    Exit(PowerWithInfinity(Base, Exponent));
  end;
  Result := System.Math.Power(Base, Exponent);
end;

// The 32 bit RTL gives NaN for some of these; Java has fixed results
class function TFunctionMath.PowerWithInfinity(const Base, Exponent: Double): Double;
begin
  if IsInfinite(Exponent) then
  begin
    if Abs(Base) = 1 then
    begin
      Exit(NaN);
    end;
    if (Abs(Base) > 1) = (Exponent > 0) then
    begin
      Exit(Infinity);
    end;
    Exit(0);
  end;

  const IsOddInteger = (Frac(Exponent) = 0) and (Abs(Exponent) < IntegerLimitOfDouble) and Odd(Trunc(Exponent));
  const IsNegativeOdd = (Base < 0) and IsOddInteger;
  if Exponent > 0 then
  begin
    if IsNegativeOdd then
    begin
      Exit(NegInfinity);
    end;
    Exit(Infinity);
  end;
  if IsNegativeOdd then
  begin
    Exit(-0.0);
  end;
  Result := 0;
end;

class function TFunctionMath.FloorOf(const Value: Double): Double;
begin
  if IsNaN(Value) or IsInfinite(Value) or (Abs(Value) >= IntegerLimitOfDouble) then
  begin
    Exit(Value);
  end;
  Result := Int(Value);
  if (Value < 0) and (Result <> Value) then
  begin
    Result := Result - 1;
  end;
end;

class function TFunctionMath.CeilOf(const Value: Double): Double;
begin
  if IsNaN(Value) or IsInfinite(Value) or (Abs(Value) >= IntegerLimitOfDouble) then
  begin
    Exit(Value);
  end;
  Result := Int(Value);
  if (Value > 0) and (Result <> Value) then
  begin
    Result := Result + 1;
  end;
end;

class function TFunctionMath.ToInteger(const Value: Double): Integer;
begin
  if IsNaN(Value) then
  begin
    Exit(0);
  end;
  if Value >= MaxInt then
  begin
    Exit(MaxInt);
  end;
  if Value <= Low(Integer) then
  begin
    Exit(Low(Integer));
  end;
  Result := Trunc(Value);
end;

class function TFunctionMath.RoundHalfUp(const Value: Double): Double;
begin
  if IsNaN(Value) then
  begin
    Exit(0);
  end;
  Result := FloorOf(Value + 0.5);
  if Result > MaxInt64Double then
  begin
    Result := MaxInt64Double;
  end
  else if Result < -MaxInt64Double then
  begin
    Result := -MaxInt64Double;
  end;
end;

class function TFunctionMath.NaturalLog(const Value: Double): Double;
begin
  if IsNaN(Value) or (Value < 0) then
  begin
    Exit(NaN);
  end;
  if Value = 0 then
  begin
    Exit(NegInfinity);
  end;
  Result := Ln(Value);
end;

class function TFunctionMath.Log10Of(const Value: Double): Double;
begin
  if IsNaN(Value) or (Value < 0) then
  begin
    Exit(NaN);
  end;
  if Value = 0 then
  begin
    Exit(NegInfinity);
  end;
  Result := Log10(Value);
end;

{ TPsParser }

constructor TPsParser.Create(const Text: string);
begin
  inherited Create;
  FText := Text;
  FPosition := 1;
  FOpenProcedures := TObjectList<TList<TPsInstruction>>.Create(True);
  FOpenProcedures.Add(TList<TPsInstruction>.Create);
  FProcedures := TList<TPsProcedure>.Create;
end;

destructor TPsParser.Destroy;
begin
  FProcedures.Free;
  FOpenProcedures.Free;
  inherited;
end;

function TPsParser.ParseProgram: TList<TPsProcedure>;
var
  Token: string;
begin
  while TryNextToken(Token) do
  begin
    HandleToken(Token);
  end;
  while FOpenProcedures.Count > 1 do
  begin
    CloseInnermostProcedure;
  end;

  FProcedures.Add(FOpenProcedures[0].ToArray);
  Result := FProcedures;
  FProcedures := nil;
end;

procedure TPsParser.HandleToken(const Token: string);
begin
  if Token = '{' then
  begin
    OpenBrace;
    Exit;
  end;
  if Token = '}' then
  begin
    CloseBrace;
    Exit;
  end;

  var Instruction: TPsInstruction;
  Instruction.IntValue := 0;
  Instruction.RealValue := 0;
  Instruction.Operator_ := TPsOperator.Unknown;
  if IsIntegerToken(Token) then
  begin
    Instruction.Kind := TPsInstructionKind.PushInt;
    Instruction.IntValue := ParseInteger(Token);
  end
  else if IsRealToken(Token) then
  begin
    Instruction.Kind := TPsInstructionKind.PushReal;
    Instruction.RealValue := ParseReal(Token);
  end
  else
  begin
    Instruction.Kind := TPsInstructionKind.Execute;
    Instruction.Operator_ := LookupOperator(Token);
  end;
  Add(Instruction);
end;

procedure TPsParser.Add(const Instruction: TPsInstruction);
begin
  FOpenProcedures.Last.Add(Instruction);
end;

// The first { of a program is the frame of the whole program: what is inside it belongs to the program itself, like in PDFBox
procedure TPsParser.OpenBrace;
begin
  const IsOutermost = (FOpenProcedures.Count = 1) and (FOpenProcedures[0].Count = 0) and not FHasOutermost;
  if IsOutermost then
  begin
    FHasOutermost := True;
    FIsOutermostOpen := True;
    Exit;
  end;

  if FOpenProcedures.Count > MaxPostScriptProcedureDepth then
  begin
    raise EPdfParseException.CreateFmt('A PostScript function nests procedures deeper than %d levels', [MaxPostScriptProcedureDepth]);
  end;
  FOpenProcedures.Add(TList<TPsInstruction>.Create);
end;

procedure TPsParser.CloseBrace;
begin
  if FOpenProcedures.Count > 1 then
  begin
    CloseInnermostProcedure;
  end
  else if FIsOutermostOpen then
  begin
    FIsOutermostOpen := False;
  end;
end;

procedure TPsParser.CloseInnermostProcedure;
begin
  const Body = FOpenProcedures.Last.ToArray;
  FOpenProcedures.Delete(FOpenProcedures.Count - 1);
  FProcedures.Add(Body);

  var Instruction: TPsInstruction;
  Instruction.Kind := TPsInstructionKind.PushProc;
  Instruction.IntValue := FProcedures.Count - 1;
  Instruction.RealValue := 0;
  Instruction.Operator_ := TPsOperator.Unknown;
  Add(Instruction);
end;

class function TPsParser.IsWhitespace(const Character: Char): Boolean;
begin
  Result := CharInSet(Character, [#0, #9, #10, #12, #13, ' ']);
end;

class function TPsParser.IsDigit(const Character: Char): Boolean;
begin
  Result := (Character >= '0') and (Character <= '9');
end;

procedure TPsParser.SkipWhitespaceAndComments;
begin
  while FPosition <= FText.Length do
  begin
    const Character = FText[FPosition];
    if IsWhitespace(Character) then
    begin
      Inc(FPosition);
    end
    else if Character = '%' then
    begin
      while (FPosition <= FText.Length) and not CharInSet(FText[FPosition], [#10, #13]) do
      begin
        Inc(FPosition);
      end;
    end
    else
    begin
      Break;
    end;
  end;
end;

function TPsParser.TryNextToken(out Token: string): Boolean;
begin
  SkipWhitespaceAndComments;
  if FPosition > FText.Length then
  begin
    Token := '';
    Exit(False);
  end;

  const Start = FPosition;
  if CharInSet(FText[FPosition], ['{', '}']) then
  begin
    Inc(FPosition);
  end
  else
  begin
    while (FPosition <= FText.Length) and not IsWhitespace(FText[FPosition]) and not CharInSet(FText[FPosition], ['{', '}', '%']) do
    begin
      Inc(FPosition);
    end;
  end;
  Token := FText.Substring(Start - 1, FPosition - Start);
  Result := True;
end;

// [+-]?[0-9]+
class function TPsParser.IsIntegerToken(const Token: string): Boolean;
begin
  var Start := 1;
  if (Token.Length > 0) and CharInSet(Token[1], ['+', '-']) then
  begin
    Start := 2;
  end;
  if Start > Token.Length then
  begin
    Exit(False);
  end;
  for var Position := Start to Token.Length do
  begin
    if not IsDigit(Token[Position]) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

// -?[0-9]*.[0-9]*([Ee]-?[0-9]+)?
class function TPsParser.IsRealToken(const Token: string): Boolean;
begin
  var Position := 1;
  if (Token.Length > 0) and (Token[1] = '-') then
  begin
    Inc(Position);
  end;
  while (Position <= Token.Length) and IsDigit(Token[Position]) do
  begin
    Inc(Position);
  end;
  if (Position > Token.Length) or (Token[Position] <> '.') then
  begin
    Exit(False);
  end;
  Inc(Position);
  while (Position <= Token.Length) and IsDigit(Token[Position]) do
  begin
    Inc(Position);
  end;
  if Position > Token.Length then
  begin
    Exit(True);
  end;
  Result := IsRealExponent(Token, Position);
end;

// [Ee]-?[0-9]+ up to the end of the token
class function TPsParser.IsRealExponent(const Token: string; const Start: Integer): Boolean;
begin
  if not CharInSet(Token[Start], ['E', 'e']) then
  begin
    Exit(False);
  end;
  var Position := Start + 1;
  if (Position <= Token.Length) and (Token[Position] = '-') then
  begin
    Inc(Position);
  end;
  if Position > Token.Length then
  begin
    Exit(False);
  end;
  while Position <= Token.Length do
  begin
    if not IsDigit(Token[Position]) then
    begin
      Exit(False);
    end;
    Inc(Position);
  end;
  Result := True;
end;

class function TPsParser.ParseInteger(const Token: string): Integer;
begin
  var Value: Int64 := 0;
  var IsNegative := False;
  var Start := 1;
  if CharInSet(Token[1], ['+', '-']) then
  begin
    IsNegative := (Token[1] = '-');
    Start := 2;
  end;
  for var Position := Start to Token.Length do
  begin
    Value := (Value * 10) + (Ord(Token[Position]) - Ord('0'));
    if Value > (Int64(High(Integer)) + 1) then
    begin
      raise EPdfParseException.CreateFmt('The integer %s in a PostScript function is out of range', [Token]);
    end;
  end;
  if IsNegative then
  begin
    Value := -Value;
  end;
  if Value > High(Integer) then
  begin
    raise EPdfParseException.CreateFmt('The integer %s in a PostScript function is out of range', [Token]);
  end;
  Result := Integer(Value);
end;

// Java accepts "1." and ".5" where the Delphi RTL wants a digit on both sides of the point
class function TPsParser.ParseReal(const Token: string): Single;
begin
  const PointPosition = Token.IndexOf('.');
  var Mantissa := Token.Substring(0, PointPosition);
  var Rest := Token.Substring(PointPosition + 1);
  var Fraction: string;
  var Exponent := '';
  const ExponentPosition = Rest.IndexOfAny(['E', 'e']);
  if ExponentPosition >= 0 then
  begin
    Fraction := Rest.Substring(0, ExponentPosition);
    Exponent := Rest.Substring(ExponentPosition);
  end
  else
  begin
    Fraction := Rest;
  end;

  const HasMantissaDigits = (Mantissa.TrimLeft(['-']) <> '') or (Fraction <> '');
  if not HasMantissaDigits then
  begin
    raise EPdfParseException.CreateFmt('The number %s in a PostScript function is not valid', [Token]);
  end;
  if Mantissa.TrimLeft(['-']) = '' then
  begin
    Mantissa := Mantissa + '0';
  end;
  if Fraction = '' then
  begin
    Fraction := '0';
  end;

  var Value: Double;
  if not TryStrToFloat(Mantissa + '.' + Fraction + Exponent, Value, TFormatSettings.Invariant) then
  begin
    // The text is a well-formed number whose magnitude the RTL refuses: Java's Float.parseFloat gives Infinity or zero
    if Exponent = '' then
    begin
      raise EPdfParseException.CreateFmt('The number %s in a PostScript function is not valid', [Token]);
    end;
    Exit(OutOfRangeValue(Mantissa, Fraction, Exponent));
  end;
  if Abs(Value) > MaxSingle then
  begin
    Exit(OutOfRangeValue(Mantissa, Fraction, '+'));
  end;
  Result := Value;
end;

class function TPsParser.OutOfRangeValue(const Mantissa, Fraction, Exponent: string): Single;
begin
  const IsNegative = Mantissa.StartsWith('-');
  const IsZero = (Mantissa + Fraction).Replace('-', '').Replace('0', '') = '';
  const IsSmall = Exponent.StartsWith('e-', True);
  if IsZero or IsSmall then
  begin
    Result := 0;
  end
  else if IsNegative then
  begin
    Result := NegInfinity;
  end
  else
  begin
    Result := Infinity;
  end;
end;

class function TPsParser.LookupOperator(const Token: string): TPsOperator;
begin
  for var Candidate := Succ(TPsOperator.Unknown) to High(TPsOperator) do
  begin
    if OperatorNames[Candidate] = Token then
    begin
      Exit(Candidate);
    end;
  end;
  Result := TPsOperator.Unknown;
end;

{ TPsProgram }

class function TPsProgram.Parse(const Text: string): TPsProgram;
begin
  const Parser = TPsParser.Create(Text);
  try
    const Procedures = Parser.ParseProgram;
    try
      Result := TPsProgram.CreateFrom(Procedures, Procedures.Count - 1);
    except
      Procedures.Free;
      raise;
    end;
  finally
    Parser.Free;
  end;
end;

constructor TPsProgram.CreateFrom(const Procedures: TList<TPsProcedure>; const RootIndex: Integer);
begin
  inherited Create;
  FProcedures := Procedures;
  FRootIndex := RootIndex;
end;

destructor TPsProgram.Destroy;
begin
  FProcedures.Free;
  inherited;
end;

function TPsProgram.Run(const Input: TArray<Single>; out Outcome: TPsOutcome): TArray<TPsValue>;
begin
  if Length(FStack) = 0 then
  begin
    SetLength(FStack, MaxPostScriptStackSize);
  end;
  FCount := 0;
  FOperations := 0;
  FOutcome := TPsOutcome.Completed;

  for var Value in Input do
  begin
    Push(TPsValue.FromReal(Value));
  end;
  if FOutcome = TPsOutcome.Completed then
  begin
    RunProcedure(FRootIndex);
  end;

  Outcome := FOutcome;
  SetLength(Result, FCount);
  for var Index := 0 to FCount - 1 do
  begin
    Result[Index] := FStack[Index];
  end;
end;

procedure TPsProgram.RunProcedure(const Index: Integer);
begin
  for var Instruction in FProcedures[Index] do
  begin
    Inc(FOperations);
    if FOperations > MaxPostScriptOperations then
    begin
      FOutcome := TPsOutcome.OperationLimit;
    end
    else if not ExecuteInstruction(Instruction) and (FOutcome = TPsOutcome.Completed) then
    begin
      FOutcome := TPsOutcome.Failed;
    end;
    if FOutcome <> TPsOutcome.Completed then
    begin
      Exit;
    end;
  end;
end;

function TPsProgram.ExecuteInstruction(const Instruction: TPsInstruction): Boolean;
begin
  case Instruction.Kind of
    TPsInstructionKind.PushInt:
    begin
      Result := Push(TPsValue.FromInt(Instruction.IntValue));
    end;
    TPsInstructionKind.PushReal:
    begin
      Result := Push(TPsValue.FromReal(Instruction.RealValue));
    end;
    TPsInstructionKind.PushProc:
    begin
      Result := Push(TPsValue.FromProc(Instruction.IntValue));
    end;
    TPsInstructionKind.Execute:
    begin
      Result := ExecuteOperator(Instruction.Operator_);
    end;
    else
    begin
      Result := False;
    end;
  end;
end;

function TPsProgram.ExecuteOperator(const Operation: TPsOperator): Boolean;
begin
  case Operation of
    TPsOperator.Abs, TPsOperator.Neg:
    begin
      Result := ExecuteAbsoluteOrNegate(Operation);
    end;
    TPsOperator.Add, TPsOperator.Sub, TPsOperator.Mul:
    begin
      Result := ExecuteAdd(Operation);
    end;
    TPsOperator.DivOp, TPsOperator.IDiv, TPsOperator.ModOp:
    begin
      Result := ExecuteDivision(Operation);
    end;
    TPsOperator.Ceiling, TPsOperator.Floor, TPsOperator.Round, TPsOperator.Truncate:
    begin
      Result := ExecuteRounding(Operation);
    end;
    TPsOperator.Cvi, TPsOperator.Cvr:
    begin
      Result := ExecuteConversion(Operation);
    end;
    TPsOperator.Atan:
    begin
      Result := ExecuteAtan;
    end;
    TPsOperator.Exp:
    begin
      Result := ExecuteExp;
    end;
    TPsOperator.Sqrt:
    begin
      Result := ExecuteSquareRoot;
    end;
    TPsOperator.Cos, TPsOperator.Sin, TPsOperator.Ln, TPsOperator.Log:
    begin
      Result := ExecuteTranscendental(Operation);
    end;
    TPsOperator.AndOp, TPsOperator.OrOp, TPsOperator.XorOp, TPsOperator.TrueOp, TPsOperator.FalseOp:
    begin
      Result := ExecuteLogical(Operation);
    end;
    TPsOperator.NotOp:
    begin
      Result := ExecuteNot;
    end;
    TPsOperator.BitShift:
    begin
      Result := ExecuteBitShift;
    end;
    TPsOperator.Eq, TPsOperator.Ne, TPsOperator.Ge, TPsOperator.Gt, TPsOperator.Le, TPsOperator.Lt:
    begin
      Result := ExecuteComparison(Operation);
    end;
    TPsOperator.IfOp, TPsOperator.IfElse:
    begin
      Result := ExecuteConditional(Operation);
    end;
    TPsOperator.Copy, TPsOperator.Dup, TPsOperator.Exch, TPsOperator.Index, TPsOperator.Pop, TPsOperator.Roll:
    begin
      Result := ExecuteStackOperator(Operation);
    end;
    else
    begin
      // An unknown name: PDFBox fails when the instruction runs
      Result := False;
    end;
  end;
end;

{ stack }

function TPsProgram.Push(const Value: TPsValue): Boolean;
begin
  if FCount >= MaxPostScriptStackSize then
  begin
    FOutcome := TPsOutcome.StackLimit;
    Exit(False);
  end;
  FStack[FCount] := Value;
  Inc(FCount);
  Result := True;
end;

// An integer result that no longer fits becomes a real, like in PDFBox
function TPsProgram.PushIntegerOrReal(const Value: Int64): Boolean;
begin
  if (Value >= Low(Integer)) and (Value <= High(Integer)) then
  begin
    Result := Push(TPsValue.FromInt(Value));
  end
  else
  begin
    Result := Push(TPsValue.FromReal(Value));
  end;
end;

function TPsProgram.TryPop(out Value: TPsValue): Boolean;
begin
  if FCount = 0 then
  begin
    Value := TPsValue.FromInt(0);
    Exit(False);
  end;
  Dec(FCount);
  Value := FStack[FCount];
  Result := True;
end;

function TPsProgram.TryPopInteger(out Value: Integer): Boolean;
begin
  var Popped: TPsValue;
  Value := 0;
  Result := TryPop(Popped) and (Popped.Kind = TPsValueKind.Int);
  if Result then
  begin
    Value := Popped.IntValue;
  end;
end;

function TPsProgram.TryPopNumber(out Value: TPsValue): Boolean;
begin
  Result := TryPop(Value) and (Value.Kind in [TPsValueKind.Int, TPsValueKind.Real]);
end;

function TPsProgram.TryPopSingle(out Value: Single): Boolean;
begin
  var Popped: TPsValue;
  Value := 0;
  Result := TryPopNumber(Popped);
  if Result then
  begin
    Value := Popped.AsSingle;
  end;
end;

function TPsProgram.TryPopBoolean(out Value: Boolean): Boolean;
begin
  var Popped: TPsValue;
  Value := False;
  Result := TryPop(Popped) and (Popped.Kind = TPsValueKind.Bool);
  if Result then
  begin
    Value := (Popped.IntValue <> 0);
  end;
end;

function TPsProgram.TryPopProcedure(out Index: Integer): Boolean;
begin
  var Popped: TPsValue;
  Index := 0;
  Result := TryPop(Popped) and (Popped.Kind = TPsValueKind.Proc);
  if Result then
  begin
    Index := Popped.IntValue;
  end;
end;

// The second operand is on top of the stack
function TPsProgram.TryPopTwoNumbers(out First, Second: TPsValue): Boolean;
begin
  First := TPsValue.FromInt(0);
  Result := TryPopNumber(Second) and TryPopNumber(First);
end;

function TPsProgram.TryPopTwoIntegers(out First, Second: Integer): Boolean;
begin
  First := 0;
  Result := TryPopInteger(Second) and TryPopInteger(First);
end;

{ arithmetic }

function TPsProgram.ExecuteAbsoluteOrNegate(const Operation: TPsOperator): Boolean;
begin
  var Value: TPsValue;
  if not TryPopNumber(Value) then
  begin
    Exit(False);
  end;

  if Value.Kind = TPsValueKind.Real then
  begin
    if Operation = TPsOperator.Abs then
    begin
      Exit(Push(TPsValue.FromReal(System.Abs(Value.RealValue))));
    end;
    Exit(Push(TPsValue.FromReal(-Value.RealValue)));
  end;

  // Math.abs(Integer.MIN_VALUE) stays negative in Java, and its negation becomes a real in PDFBox
  if Operation = TPsOperator.Abs then
  begin
    if Value.IntValue = Low(Integer) then
    begin
      Exit(Push(Value));
    end;
    Exit(Push(TPsValue.FromInt(System.Abs(Value.IntValue))));
  end;
  Result := PushIntegerOrReal(-Int64(Value.IntValue));
end;

function TPsProgram.ExecuteAdd(const Operation: TPsOperator): Boolean;
begin
  var First: TPsValue;
  var Second: TPsValue;
  if not TryPopTwoNumbers(First, Second) then
  begin
    Exit(False);
  end;

  if (First.Kind = TPsValueKind.Int) and (Second.Kind = TPsValueKind.Int) then
  begin
    case Operation of
      TPsOperator.Add:
      begin
        Exit(PushIntegerOrReal(Int64(First.IntValue) + Second.IntValue));
      end;
      TPsOperator.Sub:
      begin
        Exit(PushIntegerOrReal(Int64(First.IntValue) - Second.IntValue));
      end;
      else
      begin
        Exit(PushIntegerOrReal(Int64(First.IntValue) * Second.IntValue));
      end;
    end;
  end;

  const Left = First.AsSingle;
  const Right = Second.AsSingle;
  case Operation of
    TPsOperator.Add:
    begin
      Result := Push(TPsValue.FromReal(Left + Right));
    end;
    TPsOperator.Sub:
    begin
      Result := Push(TPsValue.FromReal(Left - Right));
    end;
    else
    begin
      Result := Push(TPsValue.FromReal(Left * Right));
    end;
  end;
end;

function TPsProgram.ExecuteDivision(const Operation: TPsOperator): Boolean;
begin
  if Operation = TPsOperator.DivOp then
  begin
    var Numerator: Single;
    var Denominator: Single;
    if not (TryPopSingle(Denominator) and TryPopSingle(Numerator)) then
    begin
      Exit(False);
    end;
    Exit(Push(TPsValue.FromReal(Numerator / Denominator)));
  end;

  var Dividend: Integer;
  var Divisor: Integer;
  if not TryPopTwoIntegers(Dividend, Divisor) or (Divisor = 0) then
  begin
    Exit(False);
  end;
  if Operation = TPsOperator.IDiv then
  begin
    // Integer.MIN_VALUE / -1 wraps around in Java
    Exit(Push(TPsValue.FromInt(Integer(Int64(Dividend) div Divisor))));
  end;
  if Divisor = -1 then
  begin
    Exit(Push(TPsValue.FromInt(0)));
  end;
  Result := Push(TPsValue.FromInt(Dividend mod Divisor));
end;

function TPsProgram.ExecuteRounding(const Operation: TPsOperator): Boolean;
begin
  var Value: TPsValue;
  if not TryPopNumber(Value) then
  begin
    Exit(False);
  end;
  if Value.Kind = TPsValueKind.Int then
  begin
    Exit(Push(Value));
  end;

  case Operation of
    TPsOperator.Ceiling:
    begin
      Result := Push(TPsValue.FromReal(TFunctionMath.CeilOf(Value.RealValue)));
    end;
    TPsOperator.Floor:
    begin
      Result := Push(TPsValue.FromReal(TFunctionMath.FloorOf(Value.RealValue)));
    end;
    TPsOperator.Round:
    begin
      Result := Push(TPsValue.FromReal(TFunctionMath.RoundHalfUp(Value.RealValue)));
    end;
    else
    begin
      Result := Push(TPsValue.FromReal(TFunctionMath.ToInteger(Value.RealValue)));
    end;
  end;
end;

function TPsProgram.ExecuteConversion(const Operation: TPsOperator): Boolean;
begin
  var Value: TPsValue;
  if not TryPopNumber(Value) then
  begin
    Exit(False);
  end;

  if Operation = TPsOperator.Cvr then
  begin
    Exit(Push(TPsValue.FromReal(Value.AsSingle)));
  end;
  if Value.Kind = TPsValueKind.Int then
  begin
    Exit(Push(Value));
  end;
  Result := Push(TPsValue.FromInt(TFunctionMath.ToInteger(Value.RealValue)));
end;

function TPsProgram.ExecuteTranscendental(const Operation: TPsOperator): Boolean;
begin
  var Value: Single;
  if not TryPopSingle(Value) then
  begin
    Exit(False);
  end;

  case Operation of
    TPsOperator.Cos:
    begin
      Result := Push(TPsValue.FromReal(Cos(Value * DegreesToRadians)));
    end;
    TPsOperator.Sin:
    begin
      Result := Push(TPsValue.FromReal(Sin(Value * DegreesToRadians)));
    end;
    TPsOperator.Ln:
    begin
      Result := Push(TPsValue.FromReal(TFunctionMath.NaturalLog(Value)));
    end;
    else
    begin
      Result := Push(TPsValue.FromReal(TFunctionMath.Log10Of(Value)));
    end;
  end;
end;

function TPsProgram.ExecuteAtan: Boolean;
begin
  var Numerator: Single;
  var Denominator: Single;
  if not (TryPopSingle(Denominator) and TryPopSingle(Numerator)) then
  begin
    Exit(False);
  end;

  var Degrees: Double := ArcTan2(Numerator, Denominator) * RadiansToDegrees;
  if Degrees < 0 then
  begin
    Degrees := Degrees + FullCircleDegrees;
  end;
  Result := Push(TPsValue.FromReal(Degrees));
end;

function TPsProgram.ExecuteExp: Boolean;
begin
  var Base: Single;
  var Exponent: Single;
  if not (TryPopSingle(Exponent) and TryPopSingle(Base)) then
  begin
    Exit(False);
  end;
  Result := Push(TPsValue.FromReal(TFunctionMath.Power(Base, Exponent)));
end;

function TPsProgram.ExecuteSquareRoot: Boolean;
begin
  var Value: Single;
  if not TryPopSingle(Value) or (Value < 0) then
  begin
    Exit(False);
  end;
  Result := Push(TPsValue.FromReal(Sqrt(Value)));
end;

{ logic }

function TPsProgram.ExecuteLogical(const Operation: TPsOperator): Boolean;
begin
  if Operation = TPsOperator.TrueOp then
  begin
    Exit(Push(TPsValue.FromBool(True)));
  end;
  if Operation = TPsOperator.FalseOp then
  begin
    Exit(Push(TPsValue.FromBool(False)));
  end;

  var First: TPsValue;
  var Second: TPsValue;
  if not (TryPop(Second) and TryPop(First)) or (First.Kind <> Second.Kind) then
  begin
    Exit(False);
  end;
  if not (First.Kind in [TPsValueKind.Int, TPsValueKind.Bool]) then
  begin
    Exit(False);
  end;

  var Combined: Integer;
  case Operation of
    TPsOperator.AndOp:
    begin
      Combined := First.IntValue and Second.IntValue;
    end;
    TPsOperator.OrOp:
    begin
      Combined := First.IntValue or Second.IntValue;
    end;
    else
    begin
      Combined := First.IntValue xor Second.IntValue;
    end;
  end;
  if First.Kind = TPsValueKind.Bool then
  begin
    Exit(Push(TPsValue.FromBool(Combined <> 0)));
  end;
  Result := Push(TPsValue.FromInt(Combined));
end;

// PDFBox negates an integer here instead of inverting its bits
function TPsProgram.ExecuteNot: Boolean;
begin
  var Value: TPsValue;
  if not TryPop(Value) then
  begin
    Exit(False);
  end;

  case Value.Kind of
    TPsValueKind.Bool:
    begin
      Result := Push(TPsValue.FromBool(Value.IntValue = 0));
    end;
    TPsValueKind.Int:
    begin
      Result := PushIntegerOrReal(-Int64(Value.IntValue));
    end;
    else
    begin
      Result := False;
    end;
  end;
end;

// Shifts like Java: the count counts modulo 32 and a shift to the right keeps the sign
function TPsProgram.ExecuteBitShift: Boolean;
begin
  var Value: Integer;
  var Shift: Integer;
  if not TryPopTwoIntegers(Value, Shift) then
  begin
    Exit(False);
  end;

  const Count = Integer(System.Abs(Int64(Shift)) and 31);
  if Shift >= 0 then
  begin
    Exit(Push(TPsValue.FromInt(Integer(Cardinal(Value) shl (Shift and 31)))));
  end;
  if Value >= 0 then
  begin
    Exit(Push(TPsValue.FromInt(Value shr Count)));
  end;
  Result := Push(TPsValue.FromInt(not ((not Value) shr Count)));
end;

function TPsProgram.ExecuteComparison(const Operation: TPsOperator): Boolean;
begin
  if Operation in [TPsOperator.Eq, TPsOperator.Ne] then
  begin
    Result := ExecuteEquality(Operation);
  end
  else
  begin
    Result := ExecuteOrdering(Operation);
  end;
end;

class function TPsProgram.AreEqual(const First, Second: TPsValue): Boolean;
begin
  const IsFirstNumber = First.Kind in [TPsValueKind.Int, TPsValueKind.Real];
  const IsSecondNumber = Second.Kind in [TPsValueKind.Int, TPsValueKind.Real];
  if IsFirstNumber and IsSecondNumber then
  begin
    const Left = First.AsSingle;
    const Right = Second.AsSingle;
    Exit((Left = Right) or (IsNaN(Left) and IsNaN(Right)));
  end;
  Result := (First.Kind = Second.Kind) and (First.IntValue = Second.IntValue);
end;

function TPsProgram.ExecuteEquality(const Operation: TPsOperator): Boolean;
begin
  var First: TPsValue;
  var Second: TPsValue;
  if not (TryPop(Second) and TryPop(First)) then
  begin
    Exit(False);
  end;
  const IsEqual = AreEqual(First, Second);
  Result := Push(TPsValue.FromBool(IsEqual = (Operation = TPsOperator.Eq)));
end;

function TPsProgram.ExecuteOrdering(const Operation: TPsOperator): Boolean;
begin
  var Left: Single;
  var Right: Single;
  if not (TryPopSingle(Right) and TryPopSingle(Left)) then
  begin
    Exit(False);
  end;

  var Holds: Boolean;
  case Operation of
    TPsOperator.Ge:
    begin
      Holds := (Left >= Right);
    end;
    TPsOperator.Gt:
    begin
      Holds := (Left > Right);
    end;
    TPsOperator.Le:
    begin
      Holds := (Left <= Right);
    end;
    else
    begin
      Holds := (Left < Right);
    end;
  end;
  Result := Push(TPsValue.FromBool(Holds));
end;

{ conditionals }

function TPsProgram.ExecuteConditional(const Operation: TPsOperator): Boolean;
begin
  var Condition: Boolean;
  var ThenProcedure: Integer;
  var ElseProcedure := -1;
  if Operation = TPsOperator.IfElse then
  begin
    if not TryPopProcedure(ElseProcedure) then
    begin
      Exit(False);
    end;
  end;
  if not (TryPopProcedure(ThenProcedure) and TryPopBoolean(Condition)) then
  begin
    Exit(False);
  end;

  if Condition then
  begin
    RunProcedure(ThenProcedure);
  end
  else if ElseProcedure >= 0 then
  begin
    RunProcedure(ElseProcedure);
  end;
  // A limit that the procedure hit is already recorded; the caller stops on it
  Result := (FOutcome = TPsOutcome.Completed);
end;

{ stack operators }

function TPsProgram.ExecuteStackOperator(const Operation: TPsOperator): Boolean;
begin
  case Operation of
    TPsOperator.Copy:
    begin
      Result := ExecuteCopy;
    end;
    TPsOperator.Index:
    begin
      Result := ExecuteIndex;
    end;
    TPsOperator.Roll:
    begin
      Result := ExecuteRoll;
    end;
    TPsOperator.Dup:
    begin
      Result := (FCount > 0) and Push(FStack[FCount - 1]);
    end;
    TPsOperator.Exch:
    begin
      Result := (FCount > 1);
      if Result then
      begin
        const Top = FStack[FCount - 1];
        FStack[FCount - 1] := FStack[FCount - 2];
        FStack[FCount - 2] := Top;
      end;
    end;
    else
    begin
      var Discarded: TPsValue;
      Result := TryPop(Discarded);
    end;
  end;
end;

// A count of zero or less copies nothing, like in PDFBox
function TPsProgram.ExecuteCopy: Boolean;
begin
  var Count: Integer;
  if not TryPopInteger(Count) or (Count > FCount) then
  begin
    Exit(False);
  end;
  if Count <= 0 then
  begin
    Exit(True);
  end;

  const Start = FCount - Count;
  for var Offset := 0 to Count - 1 do
  begin
    if not Push(FStack[Start + Offset]) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

function TPsProgram.ExecuteIndex: Boolean;
begin
  var Depth: Integer;
  if not TryPopInteger(Depth) or (Depth < 0) or (Depth >= FCount) then
  begin
    Exit(False);
  end;
  Result := Push(FStack[FCount - 1 - Depth]);
end;

// PDFBox pops j values and n - j values and pushes them back swapped; where j is larger than n that swap has nothing to do
function TPsProgram.ExecuteRoll: Boolean;
begin
  var Count: Integer;
  var Shift: Integer;
  if not TryPopTwoIntegers(Count, Shift) or (Count < 0) then
  begin
    Exit(False);
  end;
  if (Count = 0) or (Shift = 0) then
  begin
    Exit(True);
  end;

  // Int64: the negation of Low(Integer) does not fit an Integer
  var UpperSize: Int64;
  var LowerSize: Int64;
  if Shift > 0 then
  begin
    UpperSize := Shift;
    LowerSize := Max(Int64(Count) - Shift, 0);
  end
  else
  begin
    LowerSize := -Int64(Shift);
    UpperSize := Max(Int64(Count) + Shift, 0);
  end;
  if LowerSize + UpperSize > FCount then
  begin
    Exit(False);
  end;
  SwapBlocks(Integer(LowerSize), Integer(UpperSize));
  Result := True;
end;

// The block of UpperSize values on top and the block of LowerSize values under it change places
procedure TPsProgram.SwapBlocks(const LowerSize, UpperSize: Integer);
begin
  const Start = FCount - LowerSize - UpperSize;
  var Swapped: TArray<TPsValue>;
  SetLength(Swapped, LowerSize + UpperSize);
  for var Offset := 0 to UpperSize - 1 do
  begin
    Swapped[Offset] := FStack[Start + LowerSize + Offset];
  end;
  for var Offset := 0 to LowerSize - 1 do
  begin
    Swapped[UpperSize + Offset] := FStack[Start + Offset];
  end;
  for var Offset := 0 to Length(Swapped) - 1 do
  begin
    FStack[Start + Offset] := Swapped[Offset];
  end;
end;

end.
