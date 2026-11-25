// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: tiny-skia v0.12.0 src/scan/hairline_aa.rs
// Copyright (c) 2011 Google Inc., (c) 2020 Yevhenii Reizner. BSD-3-Clause, see licenses/tiny-skia-BSD-3-Clause.txt.
unit Pdf4D.Render.Native.Scan.HairlineAntiAlias;

{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}
// Rust casts i32 to u32 and adds and shifts with wrapping in a release build
{$OVERFLOWCHECKS OFF}
{$RANGECHECKS OFF}

interface

uses
  System.SysUtils,
  System.Math,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.FixedPoint,
  Pdf4D.Render.Native.EdgeClipper,
  Pdf4D.Render.Native.Path,
  Pdf4D.Render.Native.Stroker,
  Pdf4D.Render.Native.AlphaRuns,
  Pdf4D.Render.Native.Blitter,
  Pdf4D.Render.Native.Scan.Hairline;

// The anti-aliased hairline stroker and the anti-aliased rectangle fill.
//
// The Rust Option<u32> row of call_hline_blitter is dropped: a row that is None (a subtraction below zero) draws nothing, and nothing else
// of that function depends on it. The anti-hair blitters are one record that switches on its kind instead of a trait with four types; the
// RectClipBlitter is a class because it is a TTsBlitter.
//
// Must run inside TTsFloatMode, like the other scan converters.

type
  TTsScanHairlineAntiAlias = record
  private type
    TFixedRect = record
      Left: Integer;
      Top: Integer;
      Right: Integer;
      Bottom: Integer;
    end;

  private
    class function AlphaMul(const Value: Byte; const Alpha256: Integer): Byte; static;
    class procedure FillFixedRect(const Rect: TFixedRect; const Blitter: TTsBlitter); static;
    class procedure FillDot8(const L, T, R, B: Integer; const FillInner: Boolean; const Blitter: TTsBlitter); static;
    class procedure DoScanline(const L, Top, R: Integer; const Alpha: Byte; const Blitter: TTsBlitter); static;
    class procedure DoAntiHairline(const X0, Y0, X1, Y1: Integer; const HasClip: Boolean; const ClipOpt: TTsScreenIntRect;
                                   const Blitter: TTsBlitter); static;
    class function AnyBadInts(const A, B, C, D: Integer): Integer; static;
    class function BadInt(const X: Integer): Integer; static;
    class function Contribution64(const Ordinate: Integer): Integer; static;

  public
    class procedure FillRect(const Rect: TTsRect; const Clip: TTsScreenIntRect; const Blitter: TTsBlitter); static;
    class procedure StrokePath(const Path: TTsPath; const LineCap: TTsLineCap; const Clip: TTsScreenIntRect;
                               const Blitter: TTsBlitter); static;

    // The line procedure of the anti-aliased hairline
    class procedure AntiHairLineRgn(const Points: array of TTsPoint; const HasClip: Boolean; const Clip: TTsScreenIntRect;
                                    const Blitter: TTsBlitter); static;
  end;

implementation

const
  HlineStackBuffer = 100;
  FixedBoundsMax: Single = 32767.0;

type
  TTsAntiHairBlitterKind = (
    HLine,
    Horish,
    VLine,
    Vertish);

  // The trait AntiHairBlitter of Rust and its four implementations
  TTsAntiHairBlitter = record
  public
    Kind: TTsAntiHairBlitterKind;
    Blitter: TTsBlitter;

    function DrawCap(const X: Cardinal; const Fy, Slope, Mod64: Integer): Integer;
    function DrawLine(const X, StopX: Cardinal; const Fy, Slope: Integer): Integer;
  end;

  TTsRectClipBlitter = class(TTsBlitter)
  private
    FBlitter: TTsBlitter;
    FClip: TTsScreenIntRect;
    FAlphas2: TArray<Byte>;
    FRuns2: TArray<TTsAlphaRun>;
    FAlphas1: TArray<Byte>;
    FRuns1: TArray<TTsAlphaRun>;

    class function ComputeAntiWidth(const Runs: TArray<TTsAlphaRun>; const Offset: Integer): Cardinal; static;

  public
    constructor Create(const Blitter: TTsBlitter; const Clip: TTsScreenIntRect);

    procedure BlitAntiH(const X, Y: Cardinal; const Antialias: TArray<Byte>; const Runs: TArray<TTsAlphaRun>; const Offset: Integer); override;
    procedure BlitV(const X, Y, Height: Cardinal; const Alpha: Byte); override;
    procedure BlitAntiH2(const X, Y: Cardinal; const Alpha0, Alpha1: Byte); override;
    procedure BlitAntiV2(const X, Y: Cardinal; const Alpha0, Alpha1: Byte); override;
  end;

procedure CallHlineBlitter(const X: Cardinal; const HasY: Boolean; const Y: Cardinal; const Count: Cardinal; const Alpha: Byte;
                           const Blitter: TTsBlitter); forward;

function I32ToAlpha(const A: Integer): Byte;
begin
  Result := Byte(A and $FF);
end;

// The `max(1) - 1` of Rust on a u32: the value minus one, stopping at zero
function PreviousOrZero(const Value: Cardinal): Cardinal;
begin
  Result := Value;
  if Value > 0 then
  begin
    Result := Value - 1;
  end;
end;

{ TTsScanHairlineAntiAlias }

// Multiplies value by 0..256, and shift the result down 8 (i.e. return (value * alpha256) >> 8)
class function TTsScanHairlineAntiAlias.AlphaMul(const Value: Byte; const Alpha256: Integer): Byte;
begin
  Result := Byte(TTsScalar.ShiftRightI32(Integer(Value) * Alpha256, 8));
end;

class procedure TTsScanHairlineAntiAlias.FillRect(const Rect: TTsRect; const Clip: TTsScreenIntRect; const Blitter: TTsBlitter);
begin
  var Clipped: TTsRect;
  if not Rect.TryIntersect(Clip.ToRect, Clipped) then
  begin
    // everything was clipped out
    Exit;
  end;

  var Fr: TFixedRect;
  Fr.Left := TTsFdot16.FromF32(Clipped.Left);
  Fr.Top := TTsFdot16.FromF32(Clipped.Top);
  Fr.Right := TTsFdot16.FromF32(Clipped.Right);
  Fr.Bottom := TTsFdot16.FromF32(Clipped.Bottom);
  FillFixedRect(Fr, Blitter);
end;

class procedure TTsScanHairlineAntiAlias.FillFixedRect(const Rect: TFixedRect; const Blitter: TTsBlitter);
begin
  FillDot8(TTsFdot8.FromFdot16(Rect.Left), TTsFdot8.FromFdot16(Rect.Top), TTsFdot8.FromFdot16(Rect.Right), TTsFdot8.FromFdot16(Rect.Bottom),
           True, Blitter);
end;

class procedure TTsScanHairlineAntiAlias.FillDot8(const L, T, R, B: Integer; const FillInner: Boolean; const Blitter: TTsBlitter);
begin
  // check for empty now that we're in our reduced precision space
  if (L >= R) or (T >= B) then
  begin
    Exit;
  end;

  var Top := TTsScalar.ShiftRightI32(T, 8);
  if Top = TTsScalar.ShiftRightI32(B - 1, 8) then
  begin
    // just one scanline high
    DoScanline(L, Top, R, Byte(B - T - 1), Blitter);
    Exit;
  end;

  if (T and $FF) <> 0 then
  begin
    DoScanline(L, Top, R, Byte(256 - (T and $FF)), Blitter);
    Inc(Top);
  end;

  const Bottom = TTsScalar.ShiftRightI32(B, 8);
  const Height = Bottom - Top;
  if Height > 0 then
  begin
    var Left := TTsScalar.ShiftRightI32(L, 8);
    if Left = TTsScalar.ShiftRightI32(R - 1, 8) then
    begin
      // just 1-pixel wide
      if (Left >= 0) and (Top >= 0) then
      begin
        Blitter.BlitV(Cardinal(Left), Cardinal(Top), Cardinal(Height), Byte(R - L - 1));
      end;
    end
    else
    begin
      if (L and $FF) <> 0 then
      begin
        if (Left >= 0) and (Top >= 0) then
        begin
          Blitter.BlitV(Cardinal(Left), Cardinal(Top), Cardinal(Height), Byte(256 - (L and $FF)));
        end;

        Inc(Left);
      end;

      const Right = TTsScalar.ShiftRightI32(R, 8);
      const Width = Right - Left;
      if FillInner then
      begin
        if (Width > 0) and (Left >= 0) and (Top >= 0) then
        begin
          Blitter.BlitRect(TTsScreenIntRect.FromXYWHSafe(Cardinal(Left), Cardinal(Top), Cardinal(Width), Cardinal(Height)));
        end;
      end;

      if (R and $FF) <> 0 then
      begin
        if (Right >= 0) and (Top >= 0) then
        begin
          Blitter.BlitV(Cardinal(Right), Cardinal(Top), Cardinal(Height), Byte(R and $FF));
        end;
      end;
    end;
  end;

  if (B and $FF) <> 0 then
  begin
    DoScanline(L, Bottom, R, Byte(B and $FF), Blitter);
  end;
end;

class procedure TTsScanHairlineAntiAlias.DoScanline(const L, Top, R: Integer; const Alpha: Byte; const Blitter: TTsBlitter);
begin
  if Top < 0 then
  begin
    Exit;
  end;

  if TTsScalar.ShiftRightI32(L, 8) = TTsScalar.ShiftRightI32(R - 1, 8) then
  begin
    // 1x1 pixel
    const Left = TTsScalar.ShiftRightI32(L, 8);
    if Left >= 0 then
    begin
      Blitter.BlitV(Cardinal(Left), Cardinal(Top), 1, AlphaMul(Alpha, R - L));
    end;

    Exit;
  end;

  var Left := TTsScalar.ShiftRightI32(L, 8);

  if (L and $FF) <> 0 then
  begin
    if Left >= 0 then
    begin
      Blitter.BlitV(Cardinal(Left), Cardinal(Top), 1, AlphaMul(Alpha, 256 - (L and $FF)));
    end;

    Inc(Left);
  end;

  const Right = TTsScalar.ShiftRightI32(R, 8);
  const Width = Right - Left;
  if (Width > 0) and (Left >= 0) then
  begin
    CallHlineBlitter(Cardinal(Left), True, Cardinal(Top), Cardinal(Width), Alpha, Blitter);
  end;

  if (R and $FF) <> 0 then
  begin
    if Right >= 0 then
    begin
      Blitter.BlitV(Cardinal(Right), Cardinal(Top), 1, AlphaMul(Alpha, R and $FF));
    end;
  end;
end;

procedure CallHlineBlitter(const X: Cardinal; const HasY: Boolean; const Y: Cardinal; const Count: Cardinal;
                          const Alpha: Byte; const Blitter: TTsBlitter);
begin
  if not HasY then
  begin
    Exit;
  end;

  var Runs: TArray<TTsAlphaRun>;
  SetLength(Runs, HlineStackBuffer + 1);
  var Aa: TArray<Byte>;
  SetLength(Aa, HlineStackBuffer + 1);

  var Start := X;
  var Remaining := Count;
  while True do
  begin
    // In theory, we should be able to just do this once (outside of the loop), since aa[] and runs[] are supposed" to be const when we
    // call the blitter. In reality, some wrapper-blitters (e.g. RgnClipBlitter) cast away that constness, and modify the buffers in-place.
    // Hence the need to be defensive here and reseed the aa value.
    Aa[0] := Alpha;

    var N := Remaining;
    if N > HlineStackBuffer then
    begin
      N := HlineStackBuffer;
    end;

    Runs[0] := TTsAlphaRun(N);
    Runs[N] := 0;
    Blitter.BlitAntiH(Start, Y, Aa, Runs, 0);
    Inc(Start, N);

    if (N >= Remaining) or (Remaining = 0) then
    begin
      Break;
    end;

    Dec(Remaining, N);
  end;
end;

class procedure TTsScanHairlineAntiAlias.StrokePath(const Path: TTsPath; const LineCap: TTsLineCap; const Clip: TTsScreenIntRect;
                                                    const Blitter: TTsBlitter);
begin
  TTsScanHairline.StrokePathImpl(Path, LineCap, Clip, AntiHairLineRgn, Blitter);
end;

class procedure TTsScanHairlineAntiAlias.AntiHairLineRgn(const Points: array of TTsPoint; const HasClip: Boolean;
                                                         const Clip: TTsScreenIntRect; const Blitter: TTsBlitter);
begin
  var FixedBounds: TTsRect;
  if not TTsRect.TryFromLTRB(-FixedBoundsMax, -FixedBoundsMax, FixedBoundsMax, FixedBoundsMax, FixedBounds) then
  begin
    Exit;
  end;

  // We perform integral clipping later on, but we do a scalar clip first to ensure that our coordinates are expressible in fixed/integers.
  //
  // antialiased hairlines can draw up to 1/2 of a pixel outside of their bounds, so we need to outset the clip before calling the clipper.
  // To make the numerics safer, we outset by a whole pixel, since the 1/2 pixel boundary is important to the antihair blitter, we don't
  // want to risk numerical fate by chopping on that edge.
  var ClipBounds := Default(TTsRect);
  var HasClipBounds := False;
  if HasClip then
  begin
    HasClipBounds := Clip.ToRect.TryOutset(1.0, 1.0, ClipBounds);
  end;

  for var Index := 0 to High(Points) - 1 do
  begin
    var Pts: TTsPoints2;
    var Segment: TTsPoints2;
    Segment[0] := Points[Index];
    Segment[1] := Points[Index + 1];

    // We have to pre-clip the line to fit in a Fixed, so we just chop the line.
    if not TTsLineClipper.Intersect(Segment, FixedBounds, Pts) then
    begin
      Continue;
    end;

    if HasClipBounds then
    begin
      const Tmp = Pts;
      if not TTsLineClipper.Intersect(Tmp, ClipBounds, Pts) then
      begin
        Continue;
      end;
    end;

    const X0 = TTsFdot6.FromF32(Pts[0].X);
    const Y0 = TTsFdot6.FromF32(Pts[0].Y);
    const X1 = TTsFdot6.FromF32(Pts[1].X);
    const Y1 = TTsFdot6.FromF32(Pts[1].Y);

    if HasClip then
    begin
      const Left = Min(X0, X1);
      const Top = Min(Y0, Y1);
      const Right = Max(X0, X1);
      const Bottom = Max(Y0, Y1);

      var Ir: TTsIntRect;
      if not TTsIntRect.TryFromLTRB(TTsFdot6.Floor(Left) - 1, TTsFdot6.Floor(Top) - 1, TTsFdot6.Ceil(Right) + 1, TTsFdot6.Ceil(Bottom) + 1,
                                    Ir) then
      begin
        Exit;
      end;

      const ClipInt = Clip.ToIntRect;
      var Intersection: TTsIntRect;
      if not ClipInt.TryIntersect(Ir, Intersection) then
      begin
        Continue;
      end;

      if not ClipInt.Contains(Ir) then
      begin
        var Subclip: TTsScreenIntRect;
        if Intersection.TryToScreenIntRect(Subclip) then
        begin
          DoAntiHairline(X0, Y0, X1, Y1, True, Subclip, Blitter);
        end;

        Continue;
      end;

      // fall through to no-clip case
    end;

    DoAntiHairline(X0, Y0, X1, Y1, False, Default(TTsScreenIntRect), Blitter);
  end;
end;

// returns high-bit set if x == 0x8000
class function TTsScanHairlineAntiAlias.BadInt(const X: Integer): Integer;
begin
  Result := X and TTsScalar.WrappingSubI32(0, X);
end;

class function TTsScanHairlineAntiAlias.AnyBadInts(const A, B, C, D: Integer): Integer;
begin
  Result := TTsScalar.ShiftRightI32(BadInt(A) or BadInt(B) or BadInt(C) or BadInt(D), 31);
end;

// We want the fractional part of ordinate, but we want multiples of 64 to return 64, not 0, so we can't just say (ordinate & 63). We
// basically want to compute those bits, and if they're 0, return 64. We can do that w/o a branch with an extra sub and add.
class function TTsScanHairlineAntiAlias.Contribution64(const Ordinate: Integer): Integer;
begin
  Result := ((Ordinate - 1) and 63) + 1;
end;

class procedure TTsScanHairlineAntiAlias.DoAntiHairline(const X0, Y0, X1, Y1: Integer; const HasClip: Boolean;
                                                        const ClipOpt: TTsScreenIntRect; const Blitter: TTsBlitter);
begin
  // check for integer NaN (0x80000000) which we can't handle (can't negate it). It appears typically from a huge float (inf or nan) being
  // converted to int. If we see it, just don't draw.
  if AnyBadInts(X0, Y0, X1, Y1) <> 0 then
  begin
    Exit;
  end;

  // The caller must clip the line to [-32767.0 ... 32767.0] ahead of time  (in dot6 format)
  if (Abs(X1 - X0) > TTsFdot6.FromI32(511)) or (Abs(Y1 - Y0) > TTsFdot6.FromI32(511)) then
  begin
    // instead of (x0 + x1) >> 1, we shift each separately. This is less precise, but avoids overflowing the intermediate result if the
    // values are huge. A better fix might be to clip the original pts directly (i.e. do the divide), so we don't spend time subdividing huge
    // lines at all.
    const Hx = TTsScalar.ShiftRightI32(X0, 1) + TTsScalar.ShiftRightI32(X1, 1);
    const Hy = TTsScalar.ShiftRightI32(Y0, 1) + TTsScalar.ShiftRightI32(Y1, 1);
    DoAntiHairline(X0, Y0, Hx, Hy, HasClip, ClipOpt, Blitter);
    DoAntiHairline(Hx, Hy, X1, Y1, HasClip, ClipOpt, Blitter);
    // we're done
    Exit;
  end;

  var Clipped := HasClip;
  var Clip := ClipOpt;
  var Px0 := X0;
  var Py0 := Y0;
  var Px1 := X1;
  var Py1 := Y1;

  var ScaleStart: Integer;
  var ScaleStop: Integer;
  var IStart: Integer;
  var IStop: Integer;
  var FStart: Integer;
  var Slope: Integer;
  var Kind: TTsAntiHairBlitterKind;

  if Abs(Px1 - Px0) > Abs(Py1 - Py0) then
  begin
    // mostly horizontal

    if Px0 > Px1 then
    begin
      // we want to go left-to-right
      const SwapX = Px0;
      Px0 := Px1;
      Px1 := SwapX;
      const SwapY = Py0;
      Py0 := Py1;
      Py1 := SwapY;
    end;

    IStart := TTsFdot6.Floor(Px0);
    IStop := TTsFdot6.Ceil(Px1);
    FStart := TTsFdot6.ToFdot16(Py0);
    if Py0 = Py1 then
    begin
      // completely horizontal, take fast case
      Slope := 0;
      Kind := TTsAntiHairBlitterKind.HLine;
    end
    else
    begin
      Slope := TTsFdot16.FastDiv(Py1 - Py0, Px1 - Px0);
      FStart := FStart + TTsScalar.ShiftRightI32(Slope * (32 - (Px0 and 63)) + 32, 6);
      Kind := TTsAntiHairBlitterKind.Horish;
    end;

    if IStop - IStart = 1 then
    begin
      // we are within a single pixel
      ScaleStart := Px1 - Px0;
      ScaleStop := 0;
    end
    else
    begin
      ScaleStart := 64 - (Px0 and 63);
      ScaleStop := Px1 and 63;
    end;

    if Clipped then
    begin
      const ClipRect = Clip.ToIntRect;

      if (IStart >= ClipRect.Right) or (IStop <= ClipRect.Left) then
      begin
        // we're done
        Exit;
      end;

      if IStart < ClipRect.Left then
      begin
        FStart := FStart + Slope * (ClipRect.Left - IStart);
        IStart := ClipRect.Left;
        ScaleStart := 64;
        if IStop - IStart = 1 then
        begin
          // we are within a single pixel
          ScaleStart := Contribution64(Px1);
          ScaleStop := 0;
        end;
      end;

      if IStop > ClipRect.Right then
      begin
        IStop := ClipRect.Right;
        // so we don't draw this last column
        ScaleStop := 0;
      end;

      if IStart = IStop then
      begin
        // we're done
        Exit;
      end;

      // now test if our Y values are completely inside the clip
      var Top: Integer;
      var Bottom: Integer;
      if Slope >= 0 then
      begin
        // T2B
        Top := TTsFdot16.FloorToI32(FStart - TTsFdot16.Half);
        Bottom := TTsFdot16.CeilToI32(FStart + (IStop - IStart - 1) * Slope + TTsFdot16.Half);
      end
      else
      begin
        // B2T
        Bottom := TTsFdot16.CeilToI32(FStart + TTsFdot16.Half);
        Top := TTsFdot16.FloorToI32(FStart + (IStop - IStart - 1) * Slope - TTsFdot16.Half);
      end;

      Dec(Top);
      Inc(Bottom);

      if (Top >= ClipRect.Bottom) or (Bottom <= ClipRect.Top) then
      begin
        // we're done
        Exit;
      end;

      if (ClipRect.Top <= Top) and (ClipRect.Bottom >= Bottom) then
      begin
        Clipped := False;
      end;
    end;
  end
  else
  begin
    // mostly vertical

    if Py0 > Py1 then
    begin
      // we want to go top-to-bottom
      const SwapX = Px0;
      Px0 := Px1;
      Px1 := SwapX;
      const SwapY = Py0;
      Py0 := Py1;
      Py1 := SwapY;
    end;

    IStart := TTsFdot6.Floor(Py0);
    IStop := TTsFdot6.Ceil(Py1);
    FStart := TTsFdot6.ToFdot16(Px0);
    if Px0 = Px1 then
    begin
      if Py0 = Py1 then
      begin
        // are we zero length? nothing to do
        Exit;
      end;

      Slope := 0;
      Kind := TTsAntiHairBlitterKind.VLine;
    end
    else
    begin
      Slope := TTsFdot16.FastDiv(Px1 - Px0, Py1 - Py0);
      FStart := FStart + TTsScalar.ShiftRightI32(Slope * (32 - (Py0 and 63)) + 32, 6);
      Kind := TTsAntiHairBlitterKind.Vertish;
    end;

    if IStop - IStart = 1 then
    begin
      // we are within a single pixel
      ScaleStart := Py1 - Py0;
      ScaleStop := 0;
    end
    else
    begin
      ScaleStart := 64 - (Py0 and 63);
      ScaleStop := Py1 and 63;
    end;

    if Clipped then
    begin
      const ClipRect = Clip.ToIntRect;

      if (IStart >= ClipRect.Bottom) or (IStop <= ClipRect.Top) then
      begin
        // we're done
        Exit;
      end;

      if IStart < ClipRect.Top then
      begin
        FStart := FStart + Slope * (ClipRect.Top - IStart);
        IStart := ClipRect.Top;
        ScaleStart := 64;
        if IStop - IStart = 1 then
        begin
          // we are within a single pixel
          ScaleStart := Contribution64(Py1);
          ScaleStop := 0;
        end;
      end;

      if IStop > ClipRect.Bottom then
      begin
        IStop := ClipRect.Bottom;
        // so we don't draw this last row
        ScaleStop := 0;
      end;

      if IStart = IStop then
      begin
        // we're done
        Exit;
      end;

      // now test if our X values are completely inside the clip
      var Left: Integer;
      var Right: Integer;
      if Slope >= 0 then
      begin
        // L2R
        Left := TTsFdot16.FloorToI32(FStart - TTsFdot16.Half);
        Right := TTsFdot16.CeilToI32(FStart + (IStop - IStart - 1) * Slope + TTsFdot16.Half);
      end
      else
      begin
        // R2L
        Right := TTsFdot16.CeilToI32(FStart + TTsFdot16.Half);
        Left := TTsFdot16.FloorToI32(FStart + (IStop - IStart - 1) * Slope - TTsFdot16.Half);
      end;

      Dec(Left);
      Inc(Right);

      if (Left >= ClipRect.Right) or (Right <= ClipRect.Left) then
      begin
        // we're done
        Exit;
      end;

      if (ClipRect.Left <= Left) and (ClipRect.Right >= Right) then
      begin
        Clipped := False;
      end;
    end;
  end;

  // Rust casts these to u32 (they are not negative with a clip, and without a clip the caller keeps them inside the clip)
  if (IStart < 0) or (IStop < 0) then
  begin
    Exit;
  end;

  var ClipBlitter: TTsRectClipBlitter := nil;
  try
    var HairBlitter: TTsAntiHairBlitter;
    HairBlitter.Kind := Kind;
    HairBlitter.Blitter := Blitter;
    if Clipped then
    begin
      ClipBlitter := TTsRectClipBlitter.Create(Blitter, Clip);
      HairBlitter.Blitter := ClipBlitter;
    end;

    var Start := Cardinal(IStart);
    const Stop = Cardinal(IStop);

    FStart := HairBlitter.DrawCap(Start, FStart, Slope, ScaleStart);
    Inc(Start);
    var FullSpans := Integer(Stop) - Integer(Start);
    if ScaleStop > 0 then
    begin
      Dec(FullSpans);
    end;

    if FullSpans > 0 then
    begin
      FStart := HairBlitter.DrawLine(Start, Start + Cardinal(FullSpans), FStart, Slope);
    end;

    if ScaleStop > 0 then
    begin
      HairBlitter.DrawCap(Stop - 1, FStart, Slope, ScaleStop);
    end;
  finally
    ClipBlitter.Free;
  end;
end;

{ TTsAntiHairBlitter }

function TTsAntiHairBlitter.DrawCap(const X: Cardinal; const Fy, Slope, Mod64: Integer): Integer;
begin
  var Position := Fy + TTsFdot16.Half;
  if Position < 0 then
  begin
    Position := 0;
  end;

  const Coordinate = Cardinal(TTsScalar.ShiftRightI32(Position, 16));
  const A = I32ToAlpha(TTsScalar.ShiftRightI32(Position, 8));

  case Kind of
    TTsAntiHairBlitterKind.HLine:
      begin
        // lower line
        var Ma := TTsFdot6.SmallScale(A, Mod64);
        if Ma <> 0 then
        begin
          CallHlineBlitter(X, True, Coordinate, 1, Ma, Blitter);
        end;

        // upper line
        Ma := TTsFdot6.SmallScale(Byte(255 - A), Mod64);
        if Ma <> 0 then
        begin
          CallHlineBlitter(X, Coordinate > 0, PreviousOrZero(Coordinate), 1, Ma, Blitter);
        end;

        Result := Position - TTsFdot16.Half;
      end;

    TTsAntiHairBlitterKind.Horish:
      begin
        const A0 = TTsFdot6.SmallScale(Byte(255 - A), Mod64);
        const A1 = TTsFdot6.SmallScale(A, Mod64);
        Blitter.BlitAntiV2(X, PreviousOrZero(Coordinate), A0, A1);

        Result := Position + Slope - TTsFdot16.Half;
      end;

    TTsAntiHairBlitterKind.VLine:
      begin
        var Ma := TTsFdot6.SmallScale(A, Mod64);
        if Ma <> 0 then
        begin
          Blitter.BlitV(Coordinate, X, 1, Ma);
        end;

        Ma := TTsFdot6.SmallScale(Byte(255 - A), Mod64);
        if Ma <> 0 then
        begin
          Blitter.BlitV(PreviousOrZero(Coordinate), X, 1, Ma);
        end;

        Result := Position - TTsFdot16.Half;
      end;
  else
    begin
      // Vertish
      Blitter.BlitAntiH2(PreviousOrZero(Coordinate), X, TTsFdot6.SmallScale(Byte(255 - A), Mod64), TTsFdot6.SmallScale(A, Mod64));

      Result := Position + Slope - TTsFdot16.Half;
    end;
  end;
end;

function TTsAntiHairBlitter.DrawLine(const X, StopX: Cardinal; const Fy, Slope: Integer): Integer;
begin
  // The run along the line: columns (or rows) X..StopX-1; a line with no length draws nothing
  if StopX <= X then
  begin
    Exit(Fy);
  end;

  var Position := Fy + TTsFdot16.Half;
  var Along := X;

  case Kind of
    TTsAntiHairBlitterKind.HLine:
      begin
        if Position < 0 then
        begin
          Position := 0;
        end;

        const Y = Cardinal(TTsScalar.ShiftRightI32(Position, 16));
        var A := I32ToAlpha(TTsScalar.ShiftRightI32(Position, 8));
        const Count = StopX - X;

        // lower line
        if A <> 0 then
        begin
          CallHlineBlitter(X, True, Y, Count, A, Blitter);
        end;

        // upper line
        A := Byte(255 - A);
        if A <> 0 then
        begin
          CallHlineBlitter(X, Y > 0, PreviousOrZero(Y), Count, A, Blitter);
        end;
      end;

    TTsAntiHairBlitterKind.Horish:
      repeat
        if Position < 0 then
        begin
          Position := 0;
        end;

        const LowerY = Cardinal(TTsScalar.ShiftRightI32(Position, 16));
        const A = I32ToAlpha(TTsScalar.ShiftRightI32(Position, 8));
        Blitter.BlitAntiV2(Along, PreviousOrZero(LowerY), Byte(255 - A), A);
        Position := Position + Slope;

        Inc(Along);
      until Along >= StopX;

    TTsAntiHairBlitterKind.VLine:
      begin
        if Position < 0 then
        begin
          Position := 0;
        end;

        const Column = Cardinal(TTsScalar.ShiftRightI32(Position, 16));
        var A := I32ToAlpha(TTsScalar.ShiftRightI32(Position, 8));
        const Height = StopX - X;

        if A <> 0 then
        begin
          Blitter.BlitV(Column, X, Height, A);
        end;

        A := Byte(255 - A);
        if A <> 0 then
        begin
          Blitter.BlitV(PreviousOrZero(Column), X, Height, A);
        end;
      end;
  else
    repeat
      // Vertish
      if Position < 0 then
      begin
        Position := 0;
      end;

      const Column = Cardinal(TTsScalar.ShiftRightI32(Position, 16));
      const A = I32ToAlpha(TTsScalar.ShiftRightI32(Position, 8));
      Blitter.BlitAntiH2(PreviousOrZero(Column), Along, Byte(255 - A), A);
      Position := Position + Slope;

      Inc(Along);
    until Along >= StopX;
  end;

  Result := Position - TTsFdot16.Half;
end;

{ TTsRectClipBlitter }

constructor TTsRectClipBlitter.Create(const Blitter: TTsBlitter; const Clip: TTsScreenIntRect);
begin
  inherited Create;

  FBlitter := Blitter;
  FClip := Clip;
  SetLength(FAlphas2, 2);
  SetLength(FRuns2, 3);
  SetLength(FAlphas1, 1);
  SetLength(FRuns1, 2);
end;

class function TTsRectClipBlitter.ComputeAntiWidth(const Runs: TArray<TTsAlphaRun>; const Offset: Integer): Cardinal;
begin
  var Index := Offset;
  Result := 0;
  while Runs[Index] <> 0 do
  begin
    Inc(Result, Runs[Index]);
    Inc(Index, Runs[Index]);
  end;
end;

procedure TTsRectClipBlitter.BlitAntiH(const X, Y: Cardinal; const Antialias: TArray<Byte>; const Runs: TArray<TTsAlphaRun>;
                                       const Offset: Integer);
begin
  // y_in_rect and x >= right: the u32 subtraction of Rust wraps to a large number for a row above the clip
  const YInRect = (TTsScalar.WrappingSubU32(Y, FClip.Top) < FClip.Height);
  if (not YInRect) or (X >= FClip.Right) then
  begin
    Exit;
  end;

  var X0 := X;
  var X1 := X + ComputeAntiWidth(Runs, Offset);

  if X1 <= FClip.Left then
  begin
    Exit;
  end;

  var SliceOffset := Offset;

  if X0 < FClip.Left then
  begin
    const Dx = FClip.Left - X0;
    TTsAlphaRuns.BreakAt(Antialias, Runs, SliceOffset, Integer(Dx));
    Inc(SliceOffset, Integer(Dx));
    X0 := FClip.Left;
  end;

  if X1 > FClip.Right then
  begin
    X1 := FClip.Right;
    TTsAlphaRuns.BreakAt(Antialias, Runs, SliceOffset, Integer(X1 - X0));
    Runs[SliceOffset + Integer(X1 - X0)] := 0;
  end;

  FBlitter.BlitAntiH(X0, Y, Antialias, Runs, SliceOffset);
end;

procedure TTsRectClipBlitter.BlitV(const X, Y, Height: Cardinal; const Alpha: Byte);
begin
  const XInRect = (TTsScalar.WrappingSubU32(X, FClip.Left) < FClip.Width);
  if not XInRect then
  begin
    Exit;
  end;

  var Y0 := Y;
  var Y1 := Y + Height;

  if Y0 < FClip.Top then
  begin
    Y0 := FClip.Top;
  end;

  if Y1 > FClip.Bottom then
  begin
    Y1 := FClip.Bottom;
  end;

  if Y0 < Y1 then
  begin
    FBlitter.BlitV(X, Y0, Y1 - Y0, Alpha);
  end;
end;

procedure TTsRectClipBlitter.BlitAntiH2(const X, Y: Cardinal; const Alpha0, Alpha1: Byte);
begin
  FAlphas2[0] := Alpha0;
  FAlphas2[1] := Alpha1;
  FRuns2[0] := 1;
  FRuns2[1] := 1;
  FRuns2[2] := 0;
  BlitAntiH(X, Y, FAlphas2, FRuns2, 0);
end;

procedure TTsRectClipBlitter.BlitAntiV2(const X, Y: Cardinal; const Alpha0, Alpha1: Byte);
begin
  FAlphas1[0] := Alpha0;
  FRuns1[0] := 1;
  FRuns1[1] := 0;
  BlitAntiH(X, Y, FAlphas1, FRuns1, 0);

  FAlphas1[0] := Alpha1;
  FRuns1[0] := 1;
  FRuns1[1] := 0;
  BlitAntiH(X, Y + 1, FAlphas1, FRuns1, 0);
end;

end.
