// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of tiny-skia v0.12.0 src/alpha_runs.rs
unit Pdf4D.Render.Native.AlphaRuns.Tests;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Render.Native.AlphaRuns;

type
  [TestFixture]
  TTsAlphaRunsTests = class
  private
    function NewRuns(const Width: Cardinal): TTsAlphaRuns;
    function ExpandAlpha(const Runs: TTsAlphaRuns; const Width: Integer): TArray<Byte>;
    function ExpandRuns(const Alpha: TArray<Byte>; const Runs: TArray<TTsAlphaRun>; const Width: Integer): TArray<Byte>;

  public
    [Test]
    procedure TestNewRunsAreOneEmptyRun;

    [Test]
    procedure TestTryNewRejectsAWidthTheRunsCannotCount;

    [Test]
    procedure TestResetStartsANewScanline;

    [Test]
    procedure TestAlphaRunsAddCoversStartMiddleStop;

    [Test]
    procedure TestAddReturnsTheOffsetForTheNextCall;

    [Test]
    procedure TestAddWithOffsetContinuesOnTheSameScanline;

    [Test]
    procedure TestAddOnlyAStartAlpha;

    [Test]
    procedure TestAddSumsOverlappingRunsAndCatchesTheOverflow;

    [Test]
    [TestCase('Zero', '0,0')]
    [TestCase('Half', '128,128')]
    [TestCase('Max', '255,255')]
    [TestCase('Overflow', '256,255')]
    procedure TestCatchOverflow(const Alpha, Expected: Integer);

    [Test]
    procedure TestBreakAtCutsARunIntoTwoWithTheSameAlpha;

    [Test]
    procedure TestBreakAtAtARunBoundaryChangesNothing;

    [Test]
    procedure TestBreakAtWithOffset;
  end;

implementation

{ TTsAlphaRunsTests }

function TTsAlphaRunsTests.NewRuns(const Width: Cardinal): TTsAlphaRuns;
begin
  Assert.IsTrue(TTsAlphaRuns.TryNew(Width, Result));
end;

function TTsAlphaRunsTests.ExpandAlpha(const Runs: TTsAlphaRuns; const Width: Integer): TArray<Byte>;
begin
  Result := ExpandRuns(Runs.Alpha, Runs.Runs, Width);
end;

function TTsAlphaRunsTests.ExpandRuns(const Alpha: TArray<Byte>; const Runs: TArray<TTsAlphaRun>; const Width: Integer): TArray<Byte>;
begin
  SetLength(Result, Width);
  var Position := 0;
  while Runs[Position] <> 0 do
  begin
    const Count = Runs[Position];
    for var Index := 0 to Count - 1 do
    begin
      Result[Position + Index] := Alpha[Position];
    end;
    Inc(Position, Count);
  end;
  Assert.AreEqual(Width, Position, 'the runs cover the width');
end;

procedure TTsAlphaRunsTests.TestNewRunsAreOneEmptyRun;
begin
  const Runs = NewRuns(10);

  Assert.AreEqual<Integer>(11, Length(Runs.Runs));
  Assert.AreEqual<Integer>(11, Length(Runs.Alpha));
  Assert.AreEqual(10, Integer(Runs.Runs[0]));
  Assert.AreEqual(0, Integer(Runs.Runs[10]));
  Assert.AreEqual(0, Integer(Runs.Alpha[0]));
  Assert.IsTrue(Runs.IsEmpty);
end;

procedure TTsAlphaRunsTests.TestTryNewRejectsAWidthTheRunsCannotCount;
begin
  var Runs: TTsAlphaRuns;

  Assert.IsTrue(TTsAlphaRuns.TryNew(65535, Runs));
  Assert.IsFalse(TTsAlphaRuns.TryNew(65536, Runs));
  Assert.IsFalse(TTsAlphaRuns.TryNew(0, Runs));
end;

procedure TTsAlphaRunsTests.TestResetStartsANewScanline;
begin
  var Runs := NewRuns(10);
  Runs.Add(2, 128, 3, 64, 255, 0);
  Assert.IsFalse(Runs.IsEmpty);

  Runs.Reset(10);

  Assert.IsTrue(Runs.IsEmpty);
  Assert.AreEqual(10, Integer(Runs.Runs[0]));
  Assert.AreEqual(0, Integer(Runs.Runs[10]));
end;

procedure TTsAlphaRunsTests.TestAlphaRunsAddCoversStartMiddleStop;
begin
  var Runs := NewRuns(10);

  Runs.Add(2, 128, 3, 64, 255, 0);

  const Expected: TArray<Byte> = [0, 0, 128, 255, 255, 255, 64, 0, 0, 0];
  Assert.AreEqual<TArray<Byte>>(Expected, ExpandAlpha(Runs, 10));
end;

procedure TTsAlphaRunsTests.TestAddReturnsTheOffsetForTheNextCall;
begin
  var Runs := NewRuns(10);

  const NextOffset = Runs.Add(2, 128, 3, 64, 255, 0);

  Assert.AreEqual(6, NextOffset);
end;

procedure TTsAlphaRunsTests.TestAddWithOffsetContinuesOnTheSameScanline;
begin
  var Runs := NewRuns(12);
  const NextOffset = Runs.Add(1, 10, 2, 20, 255, 0);

  const LastOffset = Runs.Add(7, 30, 2, 40, 255, NextOffset);

  const Expected: TArray<Byte> = [0, 10, 255, 255, 20, 0, 0, 30, 255, 255, 40, 0];
  Assert.AreEqual<TArray<Byte>>(Expected, ExpandAlpha(Runs, 12));
  Assert.AreEqual(10, LastOffset);
end;

procedure TTsAlphaRunsTests.TestAddOnlyAStartAlpha;
begin
  var Runs := NewRuns(5);

  const NextOffset = Runs.Add(0, 77, 0, 0, 255, 0);

  const Expected: TArray<Byte> = [77, 0, 0, 0, 0];
  Assert.AreEqual<TArray<Byte>>(Expected, ExpandAlpha(Runs, 5));
  Assert.AreEqual(0, NextOffset);
end;

procedure TTsAlphaRunsTests.TestAddSumsOverlappingRunsAndCatchesTheOverflow;
begin
  var Runs := NewRuns(6);
  Runs.Add(0, 200, 2, 0, 128, 0);

  Runs.Add(0, 56, 2, 0, 128, 0);

  // 200 + 56 = 256 and 128 + 128 = 256 are caught as 255
  const Expected: TArray<Byte> = [255, 255, 255, 0, 0, 0];
  Assert.AreEqual<TArray<Byte>>(Expected, ExpandAlpha(Runs, 6));
end;

procedure TTsAlphaRunsTests.TestCatchOverflow(const Alpha, Expected: Integer);
begin
  const Actual = TTsAlphaRuns.CatchOverflow(Word(Alpha));

  Assert.AreEqual(Expected, Integer(Actual));
end;

procedure TTsAlphaRunsTests.TestBreakAtCutsARunIntoTwoWithTheSameAlpha;
begin
  var Runs := NewRuns(10);
  Runs.Alpha[0] := 90;

  TTsAlphaRuns.BreakAt(Runs.Alpha, Runs.Runs, 0, 4);

  Assert.AreEqual(4, Integer(Runs.Runs[0]));
  Assert.AreEqual(6, Integer(Runs.Runs[4]));
  Assert.AreEqual(90, Integer(Runs.Alpha[4]));
  Assert.AreEqual<TArray<Byte>>([90, 90, 90, 90, 90, 90, 90, 90, 90, 90], ExpandAlpha(Runs, 10));
end;

procedure TTsAlphaRunsTests.TestBreakAtAtARunBoundaryChangesNothing;
begin
  var Runs := NewRuns(10);
  TTsAlphaRuns.BreakAt(Runs.Alpha, Runs.Runs, 0, 4);

  TTsAlphaRuns.BreakAt(Runs.Alpha, Runs.Runs, 0, 4);

  Assert.AreEqual(4, Integer(Runs.Runs[0]));
  Assert.AreEqual(6, Integer(Runs.Runs[4]));
end;

procedure TTsAlphaRunsTests.TestBreakAtWithOffset;
begin
  var Runs := NewRuns(10);
  TTsAlphaRuns.BreakAt(Runs.Alpha, Runs.Runs, 0, 4);

  // The slice starts at the run at 4 (6 pixels long): x = 2 cuts it at 6 and leaves the first run alone
  TTsAlphaRuns.BreakAt(Runs.Alpha, Runs.Runs, 4, 2);

  Assert.AreEqual(4, Integer(Runs.Runs[0]));
  Assert.AreEqual(2, Integer(Runs.Runs[4]));
  Assert.AreEqual(4, Integer(Runs.Runs[6]));
end;

end.
