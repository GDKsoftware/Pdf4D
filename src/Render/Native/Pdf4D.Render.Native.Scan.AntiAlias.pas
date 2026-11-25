// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: tiny-skia v0.12.0 src/scan/path_aa.rs
// Copyright (c) 2006 The Android Open Source Project, (c) 2020 Yevhenii Reizner. BSD-3-Clause, see licenses/tiny-skia-BSD-3-Clause.txt.
unit Pdf4D.Render.Native.Scan.AntiAlias;

{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.Path,
  Pdf4D.Render.Native.AlphaRuns,
  Pdf4D.Render.Native.Blitter,
  Pdf4D.Render.Native.Scan;

// The anti-aliased scan converter: the path is walked at four times the resolution (SupersampleShift = 2) and the SuperBlitter accumulates
// the coverage of the sub-rows into alpha runs.
//
// Where the Rust code would panic on input, the SuperBlitter ignores the part of a span that lies outside of its row buffer (Rust notes
// that cubics go beyond the bounds, "hack, until I figure out why"), and a clip that the alpha runs cannot count draws nothing. The Drop of
// the Rust SuperBlitter is the explicit Flush after the walk.
//
// Must run inside TTsFloatMode, like the edge builder it uses.

type
  TTsScanAntiAlias = record
  public const
    // controls how much we super-sample (when we use that scan conversion)
    SupersampleShift = 2;

  private const
    Shift = SupersampleShift;
    Scale = 1 shl Shift;
    Mask = Scale - 1;

    // Our antialiasing can't handle a clip larger than 32767.
    MaxClipCoord = 32767;

  private
    class function RectOverflowsShortShift(const Rect: TTsIntRect; const ShiftBy: Integer): Integer; static;
    class function OverflowsShortShift(const Value, ShiftBy: Integer): Integer; static;
    class procedure FillPathImpl(const Path: TTsPath; const FillRule: TTsFillRule; const Bounds: TTsIntRect;
                                 const Clip: TTsScreenIntRect; const Blitter: TTsBlitter); static;

  public
    class procedure FillPath(const Path: TTsPath; const FillRule: TTsFillRule; const Clip: TTsScreenIntRect;
                             const Blitter: TTsBlitter); static;
  end;

  // The SuperBlitter is public only so that the tests can drive its spans.
  TTsBaseSuperBlitter = record
  public
    RealBlitter: TTsBlitter;

    // Current y coordinate, in destination coordinates.
    CurrIy: Integer;
    // Widest row of region to be blitted, in destination coordinates.
    Width: Cardinal;
    // Leftmost x coordinate in any row, in destination coordinates.
    Left: Cardinal;
    // Leftmost x coordinate in any row, in supersampled coordinates.
    SuperLeft: Cardinal;

    // Current y coordinate in supersampled coordinates.
    CurrY: Integer;
    // Initial y coordinate (top of bounds).
    Top: Integer;
    // The row after the last one of the bounds, in destination coordinates (Rust relies on the edges to stay inside)
    Bottom: Integer;

    class function TryCreate(const Bounds: TTsIntRect; const ClipRect: TTsScreenIntRect; const Blitter: TTsBlitter;
                             out Base: TTsBaseSuperBlitter): Boolean; static;
  end;

  TTsSuperBlitter = class(TTsBlitter)
  private
    FBase: TTsBaseSuperBlitter;
    FRuns: TTsAlphaRuns;
    FOffsetX: Integer;

    class function CoverageToPartialAlpha(const Aa: Cardinal): Byte; static;

  public
    class function TryCreate(const Bounds: TTsIntRect; const ClipRect: TTsScreenIntRect; const Blitter: TTsBlitter;
                             out SuperBlitter: TTsSuperBlitter): Boolean; static;

    // Once Runs contains a complete supersampled row, Flush blits it out through the wrapped blitter.
    procedure Flush;

    // Blits a row of pixels, with location and width specified in supersampled coordinates.
    procedure BlitH(const X, Y, Width: Cardinal); override;
  end;

implementation

{ TTsBaseSuperBlitter }

class function TTsBaseSuperBlitter.TryCreate(const Bounds: TTsIntRect; const ClipRect: TTsScreenIntRect; const Blitter: TTsBlitter;
                                             out Base: TTsBaseSuperBlitter): Boolean;
begin
  Base := Default(TTsBaseSuperBlitter);

  var Clipped: TTsIntRect;
  if not Bounds.TryIntersect(ClipRect.ToIntRect, Clipped) then
  begin
    Exit(False);
  end;

  var Sect: TTsScreenIntRect;
  if not Clipped.TryToScreenIntRect(Sect) then
  begin
    Exit(False);
  end;

  Base.RealBlitter := Blitter;
  Base.CurrIy := Integer(Sect.Top) - 1;
  Base.Width := Sect.WidthSafe;
  Base.Left := Sect.Left;
  Base.SuperLeft := Sect.Left shl TTsScanAntiAlias.SupersampleShift;
  Base.CurrY := Integer(Sect.Top shl TTsScanAntiAlias.SupersampleShift) - 1;
  Base.Top := Integer(Sect.Top);
  Base.Bottom := Integer(Sect.Bottom);
  Result := True;
end;

{ TTsSuperBlitter }

class function TTsSuperBlitter.TryCreate(const Bounds: TTsIntRect; const ClipRect: TTsScreenIntRect; const Blitter: TTsBlitter;
                                         out SuperBlitter: TTsSuperBlitter): Boolean;
begin
  SuperBlitter := nil;

  var Base: TTsBaseSuperBlitter;
  if not TTsBaseSuperBlitter.TryCreate(Bounds, ClipRect, Blitter, Base) then
  begin
    Exit(False);
  end;

  var Runs: TTsAlphaRuns;
  if not TTsAlphaRuns.TryNew(Base.Width, Runs) then
  begin
    Exit(False);
  end;

  SuperBlitter := TTsSuperBlitter.Create;
  SuperBlitter.FBase := Base;
  SuperBlitter.FRuns := Runs;
  SuperBlitter.FOffsetX := 0;
  Result := True;
end;

procedure TTsSuperBlitter.Flush;
begin
  if FBase.CurrIy >= FBase.Top then
  begin
    if not FRuns.IsEmpty then
    begin
      FBase.RealBlitter.BlitAntiH(FBase.Left, Cardinal(FBase.CurrIy), FRuns.Alpha, FRuns.Runs, 0);
      FRuns.Reset(FBase.Width);
      FOffsetX := 0;
    end;

    FBase.CurrIy := FBase.Top - 1;
  end;
end;

procedure TTsSuperBlitter.BlitH(const X, Y, Width: Cardinal);
begin
  const Iy = Integer(Y shr TTsScanAntiAlias.SupersampleShift);
  const SuperWidth = Int64(FBase.Width) shl TTsScanAntiAlias.SupersampleShift;

  var Start := X;
  var Count := Int64(Width);

  // hack, until I figure out why my cubics (I think) go beyond the bounds
  if Start >= FBase.SuperLeft then
  begin
    Start := Start - FBase.SuperLeft;
  end
  else
  begin
    Count := Int64(Start) + Count;
    Start := 0;
  end;

  // Rust panics when a span reaches outside of the row buffer: only the part inside is blitted
  const IsOutside = ((Iy < FBase.Top) or (Iy >= FBase.Bottom) or (Start >= SuperWidth));
  if IsOutside then
  begin
    Exit;
  end;

  if Start + Count > SuperWidth then
  begin
    Count := SuperWidth - Start;
  end;

  if FBase.CurrY <> Integer(Y) then
  begin
    FOffsetX := 0;
    FBase.CurrY := Integer(Y);
  end;

  if Iy <> FBase.CurrIy then
  begin
    // new scanline
    Flush;
    FBase.CurrIy := Iy;
  end;

  const Stop = Cardinal(Start + Count);

  // integer-pixel-aligned ends of blit, rounded out
  var Fb := Start and TTsScanAntiAlias.Mask;
  var Fe := Stop and TTsScanAntiAlias.Mask;
  var N := Integer(Stop shr TTsScanAntiAlias.SupersampleShift) - Integer(Start shr TTsScanAntiAlias.SupersampleShift) - 1;

  if N < 0 then
  begin
    Fb := Fe - Fb;
    N := 0;
    Fe := 0;
  end
  else
  begin
    if Fb = 0 then
    begin
      Inc(N);
    end
    else
    begin
      Fb := TTsScanAntiAlias.Scale - Fb;
    end;
  end;

  // The span of the hack above can be too long and leave the offset of its run right of the start of the next span of the same sub-row. The
  // offset only says where to start searching, so starting over from the first run gives the same alphas where Rust panics on an
  // underflow of `x - offset_x`.
  if Integer(Start shr TTsScanAntiAlias.SupersampleShift) < FOffsetX then
  begin
    FOffsetX := 0;
  end;

  const MaxValue = Byte((1 shl (8 - TTsScanAntiAlias.SupersampleShift)) - Integer(((Y and TTsScanAntiAlias.Mask) + 1) shr TTsScanAntiAlias.SupersampleShift));
  FOffsetX := FRuns.Add(Start shr TTsScanAntiAlias.SupersampleShift, CoverageToPartialAlpha(Fb), N, CoverageToPartialAlpha(Fe), MaxValue,
                        FOffsetX);
end;

// coverage_to_partial_alpha() is being used by AlphaRuns, which *accumulates* SCALE pixels worth of "alpha" in [0,(256/SCALE)] to produce a
// final value in [0, 255] and handles clamping 256->255 itself, with the same (alpha - (alpha >> 8)) correction as
// coverage_to_exact_alpha().
class function TTsSuperBlitter.CoverageToPartialAlpha(const Aa: Cardinal): Byte;
begin
  Result := Byte(Aa shl (8 - 2 * TTsScanAntiAlias.SupersampleShift));
end;

{ TTsScanAntiAlias }

class procedure TTsScanAntiAlias.FillPath(const Path: TTsPath; const FillRule: TTsFillRule; const Clip: TTsScreenIntRect;
                                          const Blitter: TTsBlitter);
begin
  // Unlike `path.bounds.to_rect()?.round_out()`, this method rounds out first and then converts into a Rect.
  const PathBounds = Path.Bounds;

  var Rounded: TTsRect;
  if not TTsRect.TryFromLTRB(TTsScalar.FloorF(PathBounds.Left), TTsScalar.FloorF(PathBounds.Top), TTsScalar.CeilF(PathBounds.Right),
                             TTsScalar.CeilF(PathBounds.Bottom), Rounded) then
  begin
    Exit;
  end;

  var Ir: TTsIntRect;
  if not Rounded.TryRoundOut(Ir) then
  begin
    Exit;
  end;

  // TODO: remove
  // If the intersection of the path bounds and the clip bounds will overflow 32767 when << by SHIFT, we can't supersample, so draw
  // without antialiasing.
  var ClippedIr: TTsIntRect;
  if not Ir.TryIntersect(Clip.ToIntRect, ClippedIr) then
  begin
    Exit;
  end;

  if RectOverflowsShortShift(ClippedIr, Shift) <> 0 then
  begin
    TTsScan.FillPath(Path, FillRule, Clip, Blitter);
    Exit;
  end;

  // TODO: remove
  // Our antialiasing can't handle a clip larger than 32767.
  // TODO: skia actually limits the clip to 32767
  if (Clip.Right > MaxClipCoord) or (Clip.Bottom > MaxClipCoord) then
  begin
    Exit;
  end;

  // TODO: SkScanClipper
  // TODO: AAA

  FillPathImpl(Path, FillRule, Ir, Clip, Blitter);
end;

// Would any of the coordinates of this rectangle not fit in a short, when left-shifted by shift?
class function TTsScanAntiAlias.RectOverflowsShortShift(const Rect: TTsIntRect; const ShiftBy: Integer): Integer;
begin
  // Since we expect these to succeed, we bit-or together for a tiny extra bit of speed.
  Result := OverflowsShortShift(Rect.Left, ShiftBy) or OverflowsShortShift(Rect.Top, ShiftBy) or OverflowsShortShift(Rect.Right, ShiftBy) or
            OverflowsShortShift(Rect.Bottom, ShiftBy);
end;

class function TTsScanAntiAlias.OverflowsShortShift(const Value, ShiftBy: Integer): Integer;
begin
  const S = 16 + ShiftBy;

  Result := TTsScalar.WrappingSubI32(TTsScalar.ShiftRightI32(TTsScalar.LeftShift(Value, S), S), Value);
end;

class procedure TTsScanAntiAlias.FillPathImpl(const Path: TTsPath; const FillRule: TTsFillRule; const Bounds: TTsIntRect;
                                              const Clip: TTsScreenIntRect; const Blitter: TTsBlitter);
begin
  // TODO: MaskSuperBlitter

  // TODO: 15% slower than skia, find out why
  var SuperBlitter: TTsSuperBlitter;
  if not TTsSuperBlitter.TryCreate(Bounds, Clip, Blitter, SuperBlitter) then
  begin
    // clipped out, nothing else to do
    Exit;
  end;

  try
    // If the bounds cannot be converted into a ScreenIntRect, the path is out of clip.
    var PathContainedInClip := False;
    var ScreenBounds: TTsScreenIntRect;
    if Bounds.TryToScreenIntRect(ScreenBounds) then
    begin
      PathContainedInClip := Clip.Contains(ScreenBounds);
    end;

    TTsScan.FillPathImpl(Path, FillRule, Clip, Bounds.Top, Bounds.Bottom, Shift, PathContainedInClip, SuperBlitter);

    // The Drop of the Rust SuperBlitter
    SuperBlitter.Flush;
  finally
    SuperBlitter.Free;
  end;
end;

end.
