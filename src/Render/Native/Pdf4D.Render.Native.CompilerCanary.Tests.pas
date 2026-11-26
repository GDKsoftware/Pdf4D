// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.Native.CompilerCanary.Tests;

// Compiler canary of the native renderer. The port of tiny-skia relies on a few floating-point behaviours of the Delphi compiler: Rust
// rounds every f32 operation, Delphi often does not. Every test pins the behaviour of Delphi 13 (Studio 37.0) on Win64 and says what
// the port relies on. When another compiler (Delphi 12, Linux64) or a later version behaves differently, a test here fails first and
// names the rule of the port that has to be checked again.
//
// The behaviours depend on the optimization of the compiler, so the unit is pinned to the optimization of the Release build.
{$OPTIMIZATION ON}
{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Math,
  System.TypInfo,
  DUnitX.TestFramework,
  Pdf4D.Render.Native.Scalar;

type
  [TestFixture]
  TTsCompilerCanaryTests = class
  private
    FFloatState: TTsFloatState;
    FNaN: Single;
    FSeven: Single;
    FSingle: Single;

    function InferredType<T>(const Value: T): PTypeInfo;
    function NegatedLess(const A, B: Single): Boolean;
    function NegatedGreater(const A, B: Single): Boolean;
    function NegatedLessOrEqual(const A, B: Single): Boolean;
    function NegatedGreaterOrEqual(const A, B: Single): Boolean;
    function NegatedEqual(const A, B: Single): Boolean;
    function LessEqualsFalse(const A, B: Single): Boolean;
    function IfNotLess(const A, B: Single): Boolean;
    function AbsChain(const A, C: Single): Single;
    function AbsChainStepwise(const A, C: Single): Single;
    function SqrtChain(const A, C: Single): Single;
    function SqrtChainStepwise(const A, C: Single): Single;
    function InlineVarChain(const A, C: Single): Single;
    function InlineVarChainStepwise(const A, C: Single): Single;
    function LiteralF64Chain(const A, B: Double): Double;
    function TypedF64Chain(const A, B: Double): Double;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestNonDyadicLiteralKeepsItsDoubleValue;

    [Test]
    procedure TestTypedSingleConstantRoundsLikeRust;

    [Test]
    procedure TestAbsInAChainSkipsTheSingleRounding;

    [Test]
    procedure TestSqrtInAChainSkipsTheSingleRounding;

    [Test]
    procedure TestUntypedInlineVarOfASingleIsExtended;

    [Test]
    procedure TestUntypedInlineVarSkipsTheSingleRounding;

    [Test]
    procedure TestPlainComparisonsWithNaNAreIeeeCorrect;

    [Test]
    procedure TestIfNotComparisonWithNaNIsCorrect;

    [Test]
    procedure TestNegatedComparisonAsAValueIsMiscompiledForNaN;

    [Test]
    procedure TestUntypedRealLiteralVarIsCurrencyOnWin64;

    [Test]
    procedure TestRealLiteralTakesAnF64ChainToExtendedOnLinux64;

    [Test]
    procedure TestSystemSqrtOfADoubleIsDoubleRoundedOnLinux64;
  end;

implementation

const
  // Not exact in f32: the typed constant holds the f32 value, the bare literal keeps its Double value
  TenthAsSingle: Single = 0.1;
  NineAsDouble: Double = 9.0;
  SampleCount = 20000;

{ TTsCompilerCanaryTests }

function TTsCompilerCanaryTests.InferredType<T>(const Value: T): PTypeInfo;
begin
  Result := TypeInfo(T);
end;

function TTsCompilerCanaryTests.NegatedLess(const A, B: Single): Boolean;
begin
  Result := not (A < B);
end;

function TTsCompilerCanaryTests.NegatedGreater(const A, B: Single): Boolean;
begin
  Result := not (A > B);
end;

function TTsCompilerCanaryTests.NegatedLessOrEqual(const A, B: Single): Boolean;
begin
  Result := not (A <= B);
end;

function TTsCompilerCanaryTests.NegatedGreaterOrEqual(const A, B: Single): Boolean;
begin
  Result := not (A >= B);
end;

function TTsCompilerCanaryTests.NegatedEqual(const A, B: Single): Boolean;
begin
  Result := not (A = B);
end;

function TTsCompilerCanaryTests.LessEqualsFalse(const A, B: Single): Boolean;
begin
  Result := ((A < B) = False);
end;

function TTsCompilerCanaryTests.IfNotLess(const A, B: Single): Boolean;
begin
  if not (A < B) then
  begin
    Exit(True);
  end;

  Result := False;
end;

function TTsCompilerCanaryTests.AbsChain(const A, C: Single): Single;
begin
  Result := Abs(A - C) * C + A;
end;

function TTsCompilerCanaryTests.AbsChainStepwise(const A, C: Single): Single;
begin
  var Step: Single := A - C;
  Step := Abs(Step);
  Step := Step * C;
  Result := Step + A;
end;

function TTsCompilerCanaryTests.SqrtChain(const A, C: Single): Single;
begin
  Result := A * C - Sqrt(A * A) * C;
end;

function TTsCompilerCanaryTests.SqrtChainStepwise(const A, C: Single): Single;
begin
  var Product: Single := A * C;
  var Square: Single := A * A;
  Square := Sqrt(Square);
  Square := Square * C;
  Result := Product - Square;
end;

function TTsCompilerCanaryTests.InlineVarChain(const A, C: Single): Single;
begin
  var Copy := A;
  Result := Copy * C + A;
end;

function TTsCompilerCanaryTests.InlineVarChainStepwise(const A, C: Single): Single;
begin
  var Copy: Single := A;
  var Step: Single := Copy * C;
  Result := Step + A;
end;

function TTsCompilerCanaryTests.LiteralF64Chain(const A, B: Double): Double;
begin
  Result := 9.0 * A * B;
end;

function TTsCompilerCanaryTests.TypedF64Chain(const A, B: Double): Double;
begin
  Result := NineAsDouble * A * B;
end;

procedure TTsCompilerCanaryTests.Setup;
begin
  FFloatState := TTsFloatMode.Enter;
  FNaN := Single.NaN;
  FSeven := 7;
end;

procedure TTsCompilerCanaryTests.TearDown;
begin
  TTsFloatMode.Leave(FFloatState);
end;

procedure TTsCompilerCanaryTests.TestNonDyadicLiteralKeepsItsDoubleValue;
begin
  var KeptDouble := 0;
  var Differences := 0;

  for var I := 1 to 1000 do
  begin
    FSingle := I;
    FSingle := FSingle / FSeven;

    const Literal: Single = FSingle * 0.1;
    const RoundedOnce: Single = Single(Double(FSingle) * 0.1);
    const Typed: Single = FSingle * TenthAsSingle;

    if Literal = RoundedOnce then
    begin
      Inc(KeptDouble);
    end;

    if Literal <> Typed then
    begin
      Inc(Differences);
    end;
  end;

  Assert.AreEqual(1000, KeptDouble, 'The port relies on: a literal that is not exact in f32 (0.1, 1.055, 1/255) keeps its Double value, ' +
    'also in one single operation, so every such literal is a typed Single constant');
  Assert.IsTrue(Differences > 0, 'The port relies on: the typed Single constant gives another result than the bare literal for some ' +
    'values; if this never differs, the compiler rounds literals to f32 and the typed-constant rule may be relaxed');
end;

procedure TTsCompilerCanaryTests.TestTypedSingleConstantRoundsLikeRust;
begin
  Assert.IsTrue(Double(TenthAsSingle) <> 0.1, 'The port relies on: a typed Single constant holds the f32 value of the literal');

  var Mismatches := 0;
  for var I := 1 to 1000 do
  begin
    FSingle := I;
    FSingle := FSingle / FSeven;

    // The product of two f32 values is exact in a Double, so one rounding to f32 is what Rust does
    const Reference: Single = Single(Double(FSingle) * Double(TenthAsSingle));
    const Typed: Single = FSingle * TenthAsSingle;

    if Typed <> Reference then
    begin
      Inc(Mismatches);
    end;
  end;

  Assert.AreEqual(0, Mismatches, 'The port relies on: a Single operation with a typed Single constant is rounded once to f32 as in Rust');
end;

procedure TTsCompilerCanaryTests.TestAbsInAChainSkipsTheSingleRounding;
begin
  RandSeed := 7;

  var Mismatches := 0;
  for var I := 1 to SampleCount do
  begin
    const A: Single = (Random - 0.5) * 64;
    const C: Single = (Random - 0.5) * 64;

    if AbsChain(A, C) <> AbsChainStepwise(A, C) then
    begin
      Inc(Mismatches);
    end;
  end;

  Assert.IsTrue(Mismatches > 0, 'The port relies on: Abs() inside a chain skips the f32 rounding, so its result feeds a further operation ' +
    'only through a Single variable or a Single(...) cast; if this never differs, the rule may be relaxed');
end;

procedure TTsCompilerCanaryTests.TestSqrtInAChainSkipsTheSingleRounding;
begin
  RandSeed := 7;

  var Mismatches := 0;
  for var I := 1 to SampleCount do
  begin
    const A: Single = (Random - 0.5) * 64;
    const C: Single = (Random - 0.5) * 64;

    if SqrtChain(A, C) <> SqrtChainStepwise(A, C) then
    begin
      Inc(Mismatches);
    end;
  end;

  {$IFDEF CPUX86}
  // x87 runs the chain and the steps alike in its own precision; Win32 matches tiny-skia within tolerances only
  Assert.AreEqual(0, Mismatches, 'Win32 (x87): the chain and the steps no longer agree; check the rule for Sqrt() in a chain');
  {$ELSE}
  Assert.IsTrue(Mismatches > 0, 'The port relies on: Sqrt() inside a chain skips the f32 rounding, so its result feeds a further ' +
    'operation only through a Single variable or a Single(...) cast; if this never differs, the rule may be relaxed');
  {$ENDIF}
end;

procedure TTsCompilerCanaryTests.TestUntypedInlineVarOfASingleIsExtended;
begin
  FSingle := 1.5;

  var Inferred := FSingle;
  Assert.IsTrue(InferredType(Inferred) = TypeInfo(Extended), 'The port relies on: an untyped inline var of a Single is an Extended ' +
    '(8 bytes on Win64, wider than a Single), so every inline float var or const gets an explicit : Single');
end;

procedure TTsCompilerCanaryTests.TestUntypedInlineVarSkipsTheSingleRounding;
begin
  RandSeed := 7;

  var Mismatches := 0;
  for var I := 1 to SampleCount do
  begin
    const A: Single = (Random - 0.5) * 64;
    const C: Single = (Random - 0.5) * 64;

    if InlineVarChain(A, C) <> InlineVarChainStepwise(A, C) then
    begin
      Inc(Mismatches);
    end;
  end;

  Assert.IsTrue(Mismatches > 0, 'The port relies on: a chain through an untyped inline var (a Double) differs from the f32 steps of Rust; ' +
    'if this never differs, the compiler keeps the f32 type and the rule may be relaxed');
end;

procedure TTsCompilerCanaryTests.TestPlainComparisonsWithNaNAreIeeeCorrect;
begin
  Assert.IsFalse(FNaN < 1, 'The port relies on: NaN < x is False');
  Assert.IsFalse(FNaN <= 1, 'The port relies on: NaN <= x is False');
  Assert.IsFalse(FNaN > 1, 'The port relies on: NaN > x is False');
  Assert.IsFalse(FNaN >= 1, 'The port relies on: NaN >= x is False');
  Assert.IsFalse(FNaN = FNaN, 'The port relies on: NaN = NaN is False');
  Assert.IsTrue(FNaN <> FNaN, 'The port relies on: NaN <> NaN is True');
  Assert.IsFalse(Abs(FNaN) < 1, 'The port relies on: Abs(NaN) < x is False');
  Assert.IsTrue(NegatedEqual(FNaN, 1), 'The port relies on: not (NaN = x) is True as a value');
end;

procedure TTsCompilerCanaryTests.TestIfNotComparisonWithNaNIsCorrect;
begin
  Assert.IsTrue(IfNotLess(FNaN, 1), 'The port relies on: if not (A < B) then ... runs for a NaN, as Rust !(a < b) does');
end;

procedure TTsCompilerCanaryTests.TestNegatedComparisonAsAValueIsMiscompiledForNaN;
begin
  // IEEE says True for all of these; Delphi 13 Win64 gives False. Win32 (x87) and Linux64 (LLVM) compile them correctly. The port never
  // uses these forms.
  const RuleText = 'The port relies on: nothing, it never uses a negated comparison as a boolean value (X := not (A < B)), ' +
    'because Delphi 13 Win64 gives False for NaN. If this changes, the compiler was fixed or is another one: check the rule';

  {$IFDEF WIN64}
  const Expected = False;
  {$ELSE}
  const Expected = True;
  {$ENDIF}

  Assert.AreEqual(Expected, NegatedLess(FNaN, 1), 'not (NaN < x). ' + RuleText);
  Assert.AreEqual(Expected, NegatedGreater(FNaN, 1), 'not (NaN > x). ' + RuleText);
  Assert.AreEqual(Expected, NegatedLessOrEqual(FNaN, 1), 'not (NaN <= x). ' + RuleText);
  Assert.AreEqual(Expected, NegatedGreaterOrEqual(FNaN, 1), 'not (NaN >= x). ' + RuleText);
  Assert.AreEqual(Expected, LessEqualsFalse(FNaN, 1), '(NaN < x) = False. ' + RuleText);
end;

procedure TTsCompilerCanaryTests.TestUntypedRealLiteralVarIsCurrencyOnWin64;
begin
  var Inferred := 0.0;
  {$IFDEF LINUX64}
  const Expected = 'Extended';
  {$ELSE}
  const Expected = 'Currency';
  {$ENDIF}

  Assert.AreEqual(Expected, string(InferredType(Inferred)^.Name), 'The port relies on: nothing, every inline float var gets an explicit ' +
    'type, because var X := 0.0 is a Currency (four decimals) on Win64 and an 80-bit Extended on Linux64');
end;

procedure TTsCompilerCanaryTests.TestRealLiteralTakesAnF64ChainToExtendedOnLinux64;
begin
  RandSeed := 7;

  var Mismatches := 0;
  for var I := 1 to SampleCount do
  begin
    const A: Double = (Random - 0.5) * 64 / 3;
    const B: Double = (Random - 0.5) * 64 / 7;

    if LiteralF64Chain(A, B) <> TypedF64Chain(A, B) then
    begin
      Inc(Mismatches);
    end;
  end;

  {$IFDEF LINUX64}
  Assert.IsTrue(Mismatches > 0, 'The port relies on: a real literal is an Extended on Linux64 and takes an f64 chain to 80 bits, so the ' +
    'literals of the f64 code are typed Double constants; if this never differs, the rule may be relaxed');
  {$ELSE}
  Assert.AreEqual(0, Mismatches, 'A real literal changes an f64 chain on this platform as well: type the literals of the f64 code');
  {$ENDIF}
end;

procedure TTsCompilerCanaryTests.TestSystemSqrtOfADoubleIsDoubleRoundedOnLinux64;
begin
  RandSeed := 13;

  var Mismatches := 0;
  for var I := 1 to SampleCount do
  begin
    const X: Single = (Random - 0.5) * 2000;
    const Y: Single = (Random - 0.5) * 2000;
    const Xx: Double = X;
    const Yy: Double = Y;
    const Sum: Double = Xx * Xx + Yy * Yy;
    const RtlRoot: Double = System.Sqrt(Sum);

    if RtlRoot <> TTsScalar.SqrtF64(Sum) then
    begin
      Inc(Mismatches);
    end;
  end;

  {$IFDEF LINUX64}
  Assert.IsTrue(Mismatches > 0, 'The port relies on: System.Sqrt of a Double rounds twice on Linux64 (sqrtl), so the f64 code uses ' +
    'TTsScalar.SqrtF64; if this never differs, the rule may be relaxed');
  {$ELSE}
  Assert.AreEqual(0, Mismatches, 'System.Sqrt of a Double is not correctly rounded on this platform: TTsScalar.SqrtF64 must cover it');
  {$ENDIF}
end;

end.
