// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: tiny-skia v0.12.0 src/alpha_runs.rs
// Copyright (c) 2006 The Android Open Source Project, (c) 2020 Yevhenii Reizner. BSD-3-Clause, see licenses/tiny-skia-BSD-3-Clause.txt.
unit Pdf4D.Render.Native.AlphaRuns;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils;

// Rust `AlphaRun` is `Option<NonZeroU16>`: a Word where zero stands for None.
//
// The Rust code passes sub-slices of the two arrays (`&mut runs[offset..]`). The array of runs and the array of alphas are always cut at the
// same index, so every function that takes a slice takes the two arrays and one Offset where the slice starts.
//
// Rust panics (unwrap of a None run, an index past the buffer, a width that does not fit a u16, a subtraction below zero) become
// EInvalidOpException here: the scan converter keeps every x and width inside the buffer, so no input reaches them. TryNew is the way to
// reject a width that the runs cannot count.

type
  TTsAlphaRun = Word;

  // Sparse array of run-length-encoded alpha (supersampling coverage) values. Sparseness allows us to independently compose several paths
  // into the same buffer.
  TTsAlphaRuns = record
  public
    Runs: TArray<TTsAlphaRun>;
    Alpha: TArray<Byte>;

  private
    class function RunLengthAt(const RunLengths: TArray<TTsAlphaRun>; const Index: Integer): Integer; static;

    // Break the runs in the buffer at offsets x and x+count, properly updating the runs to the right and left. From the state AAAABBBB,
    // run-length encoded as A4B4, break_run(..., 2, 5) would produce AAAABBBB rle as A2A2B3B1.
    class procedure BreakRun(const RunLengths: TArray<TTsAlphaRun>; const Alphas: TArray<Byte>; const Offset, X, Count: Integer); static;

  public
    // The width must be 1..=65535
    class function TryNew(const Width: Cardinal; out AlphaRuns: TTsAlphaRuns): Boolean; static;

    // Returns 0-255 given 0-256
    class function CatchOverflow(const Value: Word): Byte; static;

    // True if the scanline contains only a single run, of alpha value 0
    function IsEmpty: Boolean;

    // Reinitialize for a new scanline; Width is the width that TryNew accepted
    procedure Reset(const Width: Cardinal);

    // Insert into the buffer a run starting at (x - offset_x):
    //   if start_alpha > 0: one pixel with value += start_alpha, max 255
    //   if middle_count > 0: middle_count pixels with value += max_value
    //   if stop_alpha > 0: one pixel with value += stop_alpha
    // Returns the offset_x value that should be passed on the next call, assuming we're on the same scanline. If the caller is switching
    // scanlines, then offset_x should be 0 when this is called.
    function Add(const X: Cardinal; const StartAlpha: Byte; const MiddleCount: Integer; const StopAlpha, MaxValue: Byte;
                 const OffsetX: Integer): Integer;

    // Cut (at offset x in the buffer) a run into two shorter runs with matching alpha values. Used by the RectClipBlitter to trim a RLE
    // encoding to match the clipping rectangle. As in the Rust code, the two new runs are written at the start of the slice.
    class procedure BreakAt(const Antialias: TArray<Byte>; const RunLengths: TArray<TTsAlphaRun>; const Offset, X: Integer); static;
  end;

implementation

const
  MaxRunWidth = High(Word);

{ TTsAlphaRuns }

class function TTsAlphaRuns.RunLengthAt(const RunLengths: TArray<TTsAlphaRun>; const Index: Integer): Integer;
begin
  const IsInsideTheBuffer = ((Index >= 0) and (Index < Length(RunLengths)));
  if not IsInsideTheBuffer then
  begin
    raise EInvalidOpException.CreateFmt('Alpha run index %d is outside the buffer', [Index]);
  end;

  Result := RunLengths[Index];
  if Result = 0 then
  begin
    raise EInvalidOpException.CreateFmt('Alpha run at index %d is not set', [Index]);
  end;
end;

class procedure TTsAlphaRuns.BreakRun(const RunLengths: TArray<TTsAlphaRun>; const Alphas: TArray<Byte>; const Offset, X, Count: Integer);
begin
  var RunIndex := Offset;
  var Remaining := X;

  while Remaining > 0 do
  begin
    const RunLength = RunLengthAt(RunLengths, RunIndex);

    if Remaining < RunLength then
    begin
      Alphas[RunIndex + Remaining] := Alphas[RunIndex];
      RunLengths[RunIndex] := TTsAlphaRun(Remaining);
      RunLengths[RunIndex + Remaining] := TTsAlphaRun(RunLength - Remaining);
      Break;
    end;

    Inc(RunIndex, RunLength);
    Dec(Remaining, RunLength);
  end;

  RunIndex := Offset + X;
  Remaining := Count;

  while True do
  begin
    const RunLength = RunLengthAt(RunLengths, RunIndex);

    if Remaining < RunLength then
    begin
      Alphas[RunIndex + Remaining] := Alphas[RunIndex];
      RunLengths[RunIndex] := TTsAlphaRun(Remaining);
      RunLengths[RunIndex + Remaining] := TTsAlphaRun(RunLength - Remaining);
      Break;
    end;

    Dec(Remaining, RunLength);
    if Remaining = 0 then
    begin
      Break;
    end;

    Inc(RunIndex, RunLength);
  end;
end;

class function TTsAlphaRuns.TryNew(const Width: Cardinal; out AlphaRuns: TTsAlphaRuns): Boolean;
begin
  AlphaRuns := Default(TTsAlphaRuns);

  const WidthFitsTheRuns = ((Width >= 1) and (Width <= MaxRunWidth));
  if not WidthFitsTheRuns then
  begin
    Exit(False);
  end;

  SetLength(AlphaRuns.Runs, Width + 1);
  SetLength(AlphaRuns.Alpha, Width + 1);
  AlphaRuns.Reset(Width);
  Result := True;
end;

class function TTsAlphaRuns.CatchOverflow(const Value: Word): Byte;
begin
  Result := Byte(Value - (Value shr 8));
end;

function TTsAlphaRuns.IsEmpty: Boolean;
begin
  const FirstRun = Runs[0];
  if FirstRun = 0 then
  begin
    Exit(True);
  end;

  Result := ((Alpha[0] = 0) and (Runs[FirstRun] = 0));
end;

procedure TTsAlphaRuns.Reset(const Width: Cardinal);
begin
  const WidthIsInsideTheBuffer = ((Width <= MaxRunWidth) and (Width < Cardinal(Length(Runs))));
  if not WidthIsInsideTheBuffer then
  begin
    raise EInvalidOpException.CreateFmt('Alpha runs of %d pixels do not fit the buffer', [Width]);
  end;

  Runs[0] := TTsAlphaRun(Width);
  Runs[Width] := 0;
  Alpha[0] := 0;
end;

function TTsAlphaRuns.Add(const X: Cardinal; const StartAlpha: Byte; const MiddleCount: Integer; const StopAlpha, MaxValue: Byte;
                          const OffsetX: Integer): Integer;
begin
  const StartX = Int64(X) - OffsetX;
  const StartExtent = Ord(StartAlpha <> 0);
  const StopExtent = Ord(StopAlpha <> 0);

  const FitsTheBuffer = ((OffsetX >= 0) and (StartX >= 0) and (MiddleCount >= 0) and
                         (Int64(OffsetX) + StartX + StartExtent + MiddleCount + StopExtent < Length(Runs)));
  if not FitsTheBuffer then
  begin
    raise EInvalidOpException.CreateFmt('Alpha run at %d with offset %d and %d pixels does not fit the buffer', [X, OffsetX, MiddleCount]);
  end;

  var RunIndex := OffsetX;
  var LastAlphaIndex := OffsetX;
  var CurrentX := Integer(StartX);
  var Middle := MiddleCount;

  if StartAlpha <> 0 then
  begin
    BreakRun(Runs, Alpha, RunIndex, CurrentX, 1);

    // The trailing edge of the previous span and the leading edge of this span can round to the same super-sampled x, which would give
    // 256 with a plain add, hence the subtraction.
    const Total = Word(Alpha[RunIndex + CurrentX]) + StartAlpha;
    Alpha[RunIndex + CurrentX] := Byte(Total - (Total shr 8));

    Inc(RunIndex, CurrentX + 1);
    CurrentX := 0;
  end;

  if Middle <> 0 then
  begin
    BreakRun(Runs, Alpha, RunIndex, CurrentX, Middle);
    Inc(RunIndex, CurrentX);
    CurrentX := 0;

    repeat
      Alpha[RunIndex] := CatchOverflow(Word(Word(Alpha[RunIndex]) + MaxValue));

      const RunLength = RunLengthAt(Runs, RunIndex);
      Inc(RunIndex, RunLength);
      Dec(Middle, RunLength);
    until Middle <= 0;

    LastAlphaIndex := RunIndex;
  end;

  if StopAlpha <> 0 then
  begin
    BreakRun(Runs, Alpha, RunIndex, CurrentX, 1);
    Inc(RunIndex, CurrentX);

    // A plain add in Rust: a release build wraps
    Alpha[RunIndex] := Byte(Alpha[RunIndex] + StopAlpha);
    LastAlphaIndex := RunIndex;
  end;

  Result := LastAlphaIndex;
end;

class procedure TTsAlphaRuns.BreakAt(const Antialias: TArray<Byte>; const RunLengths: TArray<TTsAlphaRun>; const Offset, X: Integer);
begin
  var Index := Offset;
  var Remaining := X;

  while Remaining > 0 do
  begin
    const RunLength = RunLengthAt(RunLengths, Index);

    if Remaining < RunLength then
    begin
      Antialias[Index + Remaining] := Antialias[Index];
      RunLengths[Offset] := TTsAlphaRun(Remaining);
      RunLengths[Offset + Remaining] := TTsAlphaRun(RunLength - Remaining);
      Break;
    end;

    Inc(Index, RunLength);
    Dec(Remaining, RunLength);
  end;
end;

end.
