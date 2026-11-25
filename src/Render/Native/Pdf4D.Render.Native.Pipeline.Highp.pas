// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: tiny-skia v0.12.0 src/pipeline/highp.rs
// The DecalXY and CheckDecalMask stages are an addition of Pdf4D after the example of decal_x_and_y and check_decal_mask of Skia: DecalXY runs
// after the transform and before the tiling, and keeps the lanes whose sample point is inside [0, Width) x [0, Height) of the pixmap (the
// limits of the context); the filter taps pad. CheckDecalMask runs after the sampling and sets the color of the other lanes to zero.
// Another deviation of Pdf4D: ClampA also clamps the colour to the alpha, as clamp_a of Skia does (see ClampA).
// Copyright (c) 2018 Google Inc., (c) 2020 Yevhenii Reizner. BSD-3-Clause, see licenses/tiny-skia-BSD-3-Clause.txt.
unit Pdf4D.Render.Native.Pipeline.Highp;

// The wrapping arithmetic of the integer lanes is intended
{$OVERFLOWCHECKS OFF}
{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

uses
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.Wide,
  Pdf4D.Render.Native.Stage,
  Pdf4D.Render.Native.Pixmap,
  Pdf4D.Render.Native.Pipeline.Context;

// A high precision raster pipeline implemented with f32x8. Unlike lowp this one implements all stages that are ported; the stages of the
// gradients, the conical gradients and the gamma functions are not, so their entries in the tables are nil and the builder of the pipeline
// does not accept them. The stage functions call the next stage themselves, as in Rust: a stage that does not call it ends the run.

type
  PTsHighpStageFunctions = ^TTsHighpStageFunctions;

  // Pipeline of highp.rs. The pointers refer to values that live as long as the run of Start.
  TTsHighpPipeline = record
    Index: Integer;
    Functions: PTsHighpStageFunctions;
    PixmapSrc: PTsPixmapRef;
    PixmapDst: PTsSubPixmapMut;
    Ctx: PTsPipelineContext;
    MaskCtx: PTsMaskCtx;
    AAMaskCtx: PTsAAMaskCtx;
    R: TF32x8;
    G: TF32x8;
    B: TF32x8;
    A: TF32x8;
    DR: TF32x8;
    DG: TF32x8;
    DB: TF32x8;
    DA: TF32x8;
    Tail: Integer;
    DX: Integer;
    DY: Integer;

    procedure NextStage;
  end;

  TTsHighpStageFn = procedure(var P: TTsHighpPipeline);

  // The functions of a compiled pipeline: the ArrayVec of Rust, with room for the stages and the function that returns
  TTsHighpStageFunctions = record
    Items: array[0..MaxStages] of TTsHighpStageFn;
    Count: Integer;
  end;

  TTsHighpStageTable = array[TTsStage] of TTsHighpStageFn;

  // The STAGES table in the order of the stages. It is filled once, by the class constructor, and only read afterwards. TailTable has the
  // functions of the last run of a row, which has fewer than eight pixels: only the load and store functions differ from Table.
  TTsHighpStages = record
  public
    class var Table: TTsHighpStageTable;
    class var TailTable: TTsHighpStageTable;

    class constructor Create;

    // The function that ends the loop, which compile adds after the last stage
    class function JustReturn: TTsHighpStageFn; static;

    // Runs the functions over every pixel of the rect, eight at a time and a tail of fewer than eight at the end of each row. The pixels of the
    // region must be in the data of PixmapDst; the caller checks that.
    class procedure Start(const Functions, FunctionsTail: TTsHighpStageFunctions; const Rect: TTsScreenIntRect;
                          const AAMaskCtx: TTsAAMaskCtx; const MaskCtx: TTsMaskCtx; var Ctx: TTsPipelineContext;
                          const PixmapSrc: TTsPixmapRef; var PixmapDst: TTsSubPixmapMut); static;
  end;

implementation

uses
  System.SysUtils,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Color;

type
  TTsColors8 = array[0..HighpStageWidth - 1] of TTsPremultipliedColorU8;

  TTsBlendKernel = function(const S, D, SA, DA: TF32x8): TF32x8;

const
  // 1.0 / 255.0
  Factor: Single = 1 / 255;
  Scale255: Single = 255;
  Half: Single = 0.5;
  OneSingle: Single = 1;
  // The weights of lum() in highp.rs
  LumRed: Single = 0.30;
  LumGreen: Single = 0.59;
  LumBlue: Single = 0.11;

{ TTsHighpPipeline }

procedure TTsHighpPipeline.NextStage;
begin
  const Next = Functions^.Items[Index];
  Inc(Index);
  Next(Self);
end;

{ helpers of highp.rs }

function Zero: TF32x8; inline;
begin
  Result := TF32x8.Splat(0);
end;

function One: TF32x8; inline;
begin
  Result := TF32x8.Splat(OneSingle);
end;

function Inv(const V: TF32x8): TF32x8; inline;
begin
  Result := One - V;
end;

function Two(const V: TF32x8): TF32x8; inline;
begin
  Result := V + V;
end;

function Mad(const F, M, A: TF32x8): TF32x8; inline;
begin
  Result := F * M + A;
end;

function Lerp(const From, ToValue, T: TF32x8): TF32x8; inline;
begin
  Result := Mad(ToValue - From, T, From);
end;

function Unnorm(const V: TF32x8): TI32x8;
begin
  Result := (V.Max(Zero).Min(One) * TF32x8.Splat(Scale255)).RoundInt;
end;

procedure Load8888(const Data: TTsColors8; var R, G, B, A: TF32x8);
begin
  // Surprisingly, `f32 * FACTOR` is way faster than `f32x8 * f32x8::splat(FACTOR)`.
  for var I := 0 to HighpStageWidth - 1 do
  begin
    const Red: Single = Data[I].Red;
    const Green: Single = Data[I].Green;
    const Blue: Single = Data[I].Blue;
    const Alpha: Single = Data[I].Alpha;

    R.Lanes[I] := Red * Factor;
    G.Lanes[I] := Green * Factor;
    B.Lanes[I] := Blue * Factor;
    A.Lanes[I] := Alpha * Factor;
  end;
end;

procedure ReadPixels(const Pixmap: TTsSubPixmapMut; const DX, DY, Count: Integer; var Colors: TTsColors8);
begin
  const Start = Pixmap.PixelIndex(DX, DY) * 4;
  Move(Pixmap.Data[Start], Colors, Count * 4);
end;

procedure WritePixels(const Colors: TTsColors8; var Pixmap: TTsSubPixmapMut; const DX, DY, Count: Integer);
begin
  const Start = Pixmap.PixelIndex(DX, DY) * 4;
  Move(Colors, Pixmap.Data[Start], Count * 4);
end;

procedure Store8888(const R, G, B, A: TF32x8; var Data: TTsColors8);
begin
  const Red = Unnorm(R);
  const Green = Unnorm(G);
  const Blue = Unnorm(B);
  const Alpha = Unnorm(A);

  for var I := 0 to HighpStageWidth - 1 do
  begin
    Data[I] := TTsPremultipliedColorU8.FromRgbaUnchecked(Byte(Red.Lanes[I]), Byte(Green.Lanes[I]), Byte(Blue.Lanes[I]), Byte(Alpha.Lanes[I]));
  end;
end;

function ClearedColors: TTsColors8;
begin
  for var I := 0 to HighpStageWidth - 1 do
  begin
    Result[I] := TTsPremultipliedColorU8.Transparent;
  end;
end;

{ stages }

procedure MoveSourceToDestination(var P: TTsHighpPipeline);
begin
  P.DR := P.R;
  P.DG := P.G;
  P.DB := P.B;
  P.DA := P.A;

  P.NextStage;
end;

procedure Premultiply(var P: TTsHighpPipeline);
begin
  P.R := P.R * P.A;
  P.G := P.G * P.A;
  P.B := P.B * P.A;

  P.NextStage;
end;

procedure MoveDestinationToSource(var P: TTsHighpPipeline);
begin
  P.R := P.DR;
  P.G := P.DG;
  P.B := P.DB;
  P.A := P.DA;

  P.NextStage;
end;

procedure Clamp0(var P: TTsHighpPipeline);
begin
  P.R := P.R.Max(Zero);
  P.G := P.G.Max(Zero);
  P.B := P.B.Max(Zero);
  P.A := P.A.Max(Zero);

  P.NextStage;
end;

// Pdf4D deviation from tiny-skia: after the alpha is clamped to 1, the colour is clamped to the alpha, as clamp_a of Skia does. tiny-skia
// leaves the colour at 1, so a cubic filter whose far tap has a negative weight can store a colour above its alpha, an invalid premultiplied
// pixel that shows as a bright fringe next to transparency. The images of tiny-skia have a colour of k * alpha in every tap, so none of them
// changes. ClampA is only used after the bicubic sampler.
procedure ClampA(var P: TTsHighpPipeline);
begin
  P.A := P.A.Min(One);
  P.R := P.R.Min(P.A);
  P.G := P.G.Min(P.A);
  P.B := P.B.Min(P.A);

  P.NextStage;
end;

procedure UniformColor(var P: TTsHighpPipeline);
begin
  P.R := TF32x8.Splat(P.Ctx^.UniformColor.R);
  P.G := TF32x8.Splat(P.Ctx^.UniformColor.G);
  P.B := TF32x8.Splat(P.Ctx^.UniformColor.B);
  P.A := TF32x8.Splat(P.Ctx^.UniformColor.A);

  P.NextStage;
end;

procedure SeedShader(var P: TTsHighpPipeline);
begin
  const Iota = TF32x8.FromArray([0.5, 1.5, 2.5, 3.5, 4.5, 5.5, 6.5, 7.5]);
  const X: Single = P.DX;
  const Y: Single = P.DY;
  const YCenter: Single = Y + Half;

  P.R := TF32x8.Splat(X) + Iota;
  P.G := TF32x8.Splat(YCenter);
  P.B := One;
  P.A := Zero;

  P.DR := Zero;
  P.DG := Zero;
  P.DB := Zero;
  P.DA := Zero;

  P.NextStage;
end;

procedure LoadDst(var P: TTsHighpPipeline);
begin
  var Colors: TTsColors8;
  ReadPixels(P.PixmapDst^, P.DX, P.DY, HighpStageWidth, Colors);
  Load8888(Colors, P.DR, P.DG, P.DB, P.DA);

  P.NextStage;
end;

procedure LoadDstTail(var P: TTsHighpPipeline);
begin
  // Fill a dummy array with `tail` values, so that the full load can be reused
  var Colors := ClearedColors;
  ReadPixels(P.PixmapDst^, P.DX, P.DY, P.Tail, Colors);
  Load8888(Colors, P.DR, P.DG, P.DB, P.DA);

  P.NextStage;
end;

procedure Store(var P: TTsHighpPipeline);
begin
  var Colors: TTsColors8;
  Store8888(P.R, P.G, P.B, P.A, Colors);
  WritePixels(Colors, P.PixmapDst^, P.DX, P.DY, HighpStageWidth);

  P.NextStage;
end;

procedure StoreTail(var P: TTsHighpPipeline);
begin
  var Colors: TTsColors8;
  Store8888(P.R, P.G, P.B, P.A, Colors);
  WritePixels(Colors, P.PixmapDst^, P.DX, P.DY, P.Tail);

  P.NextStage;
end;

// Currently, all mask/A8 pixmaps are handled by lowp: unreachable
procedure LoadDstU8(var P: TTsHighpPipeline);
begin
end;

procedure LoadDstU8Tail(var P: TTsHighpPipeline);
begin
end;

procedure StoreU8(var P: TTsHighpPipeline);
begin
end;

procedure StoreU8Tail(var P: TTsHighpPipeline);
begin
end;

function UlpSub(const V: Single): Single;
begin
  // Somewhat similar to v - f32::EPSILON
  TTsLane.SetBits(Result, TTsLane.Bits(V) - 1);
end;

function GatherIx(const Pixmap: TTsPixmapRef; const X, Y: TF32x8): TU32x8;
begin
  // Exclusive -> inclusive
  const Width: Single = Pixmap.Width;
  const Height: Single = Pixmap.Height;
  const W: Single = UlpSub(Width);
  const H: Single = UlpSub(Height);
  const ClampedX = X.Max(Zero).Min(TF32x8.Splat(W));
  const ClampedY = Y.Max(Zero).Min(TF32x8.Splat(H));

  Result := (ClampedY.TruncInt * TI32x8.Splat(Integer(Pixmap.Width)) + ClampedX.TruncInt).ToU32x8Bitcast;
end;

// PixmapRef::gather: the indices are inside the pixmap, as gather_ix clamps them; a pixel that the data does not hold is transparent
procedure GatherPixels(const Pixmap: TTsPixmapRef; const Index: TU32x8; var Colors: TTsColors8);
begin
  for var I := 0 to HighpStageWidth - 1 do
  begin
    var Red, Green, Blue, Alpha: Byte;
    Pixmap.TryReadPixel(Index.Lanes[I], Red, Green, Blue, Alpha);
    Colors[I] := TTsPremultipliedColorU8.FromRgbaUnchecked(Red, Green, Blue, Alpha);
  end;
end;

procedure Gather(var P: TTsHighpPipeline);
begin
  var Colors: TTsColors8;
  const Ix = GatherIx(P.PixmapSrc^, P.R, P.G);
  GatherPixels(P.PixmapSrc^, Ix, Colors);
  Load8888(Colors, P.R, P.G, P.B, P.A);

  P.NextStage;
end;

procedure LoadMaskU8(var P: TTsHighpPipeline);
begin
  // unreachable
end;

procedure MaskU8(var P: TTsHighpPipeline);
begin
  const Offset = P.MaskCtx^.ByteIndex(P.DX, P.DY);
  var C := Zero;
  for var I := 0 to P.Tail - 1 do
  begin
    // The Rust code panics for a byte outside the mask; here it is a transparent pixel
    const Position = Offset + I;
    const IsInsideMask = ((Position >= 0) and (Position < Length(P.MaskCtx^.Data)));
    if IsInsideMask then
    begin
      const Coverage: Single = P.MaskCtx^.Data[Position];
      C.Lanes[I] := Coverage;
    end;
  end;
  C := C / TF32x8.Splat(Scale255);

  if C = Zero then
  begin
    Exit;
  end;

  P.R := P.R * C;
  P.G := P.G * C;
  P.B := P.B * C;
  P.A := P.A * C;

  P.NextStage;
end;

function AACoverage(const P: TTsHighpPipeline): TF32x8;
begin
  // Load u8xTail and cast it to f32x8
  var First, Second: Byte;
  P.AAMaskCtx^.CopyAtXY(P.DX, P.DY, P.Tail, First, Second);

  const FirstValue: Single = First;
  const SecondValue: Single = Second;
  Result := TF32x8.FromArray([FirstValue, SecondValue, 0, 0, 0, 0, 0, 0]);
  Result := Result / TF32x8.Splat(Scale255);
end;

procedure ScaleU8(var P: TTsHighpPipeline);
begin
  const C = AACoverage(P);
  P.R := P.R * C;
  P.G := P.G * C;
  P.B := P.B * C;
  P.A := P.A * C;

  P.NextStage;
end;

procedure LerpU8(var P: TTsHighpPipeline);
begin
  const C = AACoverage(P);
  P.R := Lerp(P.DR, P.R, C);
  P.G := Lerp(P.DG, P.G, C);
  P.B := Lerp(P.DB, P.B, C);
  P.A := Lerp(P.DA, P.A, C);

  P.NextStage;
end;

procedure Scale1Float(var P: TTsHighpPipeline);
begin
  const C = TF32x8.Splat(P.Ctx^.CurrentCoverage);
  P.R := P.R * C;
  P.G := P.G * C;
  P.B := P.B * C;
  P.A := P.A * C;

  P.NextStage;
end;

procedure Lerp1Float(var P: TTsHighpPipeline);
begin
  const C = TF32x8.Splat(P.Ctx^.CurrentCoverage);
  P.R := Lerp(P.DR, P.R, C);
  P.G := Lerp(P.DG, P.G, C);
  P.B := Lerp(P.DB, P.B, C);
  P.A := Lerp(P.DA, P.A, C);

  P.NextStage;
end;

{ blend_fn!: the same logic for the color and the alpha }

procedure ApplyBlend(var P: TTsHighpPipeline; const Kernel: TTsBlendKernel);
begin
  P.R := Kernel(P.R, P.DR, P.A, P.DA);
  P.G := Kernel(P.G, P.DG, P.A, P.DA);
  P.B := Kernel(P.B, P.DB, P.A, P.DA);
  P.A := Kernel(P.A, P.DA, P.A, P.DA);

  P.NextStage;
end;

function ClearKernel(const S, D, SA, DA: TF32x8): TF32x8;
begin
  Result := Zero;
end;

function SourceAtopKernel(const S, D, SA, DA: TF32x8): TF32x8;
begin
  Result := S * DA + D * Inv(SA);
end;

function DestinationAtopKernel(const S, D, SA, DA: TF32x8): TF32x8;
begin
  Result := D * SA + S * Inv(DA);
end;

function SourceInKernel(const S, D, SA, DA: TF32x8): TF32x8;
begin
  Result := S * DA;
end;

function DestinationInKernel(const S, D, SA, DA: TF32x8): TF32x8;
begin
  Result := D * SA;
end;

function SourceOutKernel(const S, D, SA, DA: TF32x8): TF32x8;
begin
  Result := S * Inv(DA);
end;

function DestinationOutKernel(const S, D, SA, DA: TF32x8): TF32x8;
begin
  Result := D * Inv(SA);
end;

function SourceOverKernel(const S, D, SA, DA: TF32x8): TF32x8;
begin
  Result := Mad(D, Inv(SA), S);
end;

function DestinationOverKernel(const S, D, SA, DA: TF32x8): TF32x8;
begin
  Result := Mad(S, Inv(DA), D);
end;

function ModulateKernel(const S, D, SA, DA: TF32x8): TF32x8;
begin
  Result := S * D;
end;

function MultiplyKernel(const S, D, SA, DA: TF32x8): TF32x8;
begin
  Result := S * Inv(DA) + D * Inv(SA) + S * D;
end;

function ScreenKernel(const S, D, SA, DA: TF32x8): TF32x8;
begin
  Result := S + D - S * D;
end;

function XorKernel(const S, D, SA, DA: TF32x8): TF32x8;
begin
  Result := S * Inv(DA) + D * Inv(SA);
end;

function PlusKernel(const S, D, SA, DA: TF32x8): TF32x8;
begin
  Result := (S + D).Min(One);
end;

procedure Clear(var P: TTsHighpPipeline);
begin
  ApplyBlend(P, ClearKernel);
end;

procedure SourceAtop(var P: TTsHighpPipeline);
begin
  ApplyBlend(P, SourceAtopKernel);
end;

procedure DestinationAtop(var P: TTsHighpPipeline);
begin
  ApplyBlend(P, DestinationAtopKernel);
end;

procedure SourceIn(var P: TTsHighpPipeline);
begin
  ApplyBlend(P, SourceInKernel);
end;

procedure DestinationIn(var P: TTsHighpPipeline);
begin
  ApplyBlend(P, DestinationInKernel);
end;

procedure SourceOut(var P: TTsHighpPipeline);
begin
  ApplyBlend(P, SourceOutKernel);
end;

procedure DestinationOut(var P: TTsHighpPipeline);
begin
  ApplyBlend(P, DestinationOutKernel);
end;

procedure SourceOver(var P: TTsHighpPipeline);
begin
  ApplyBlend(P, SourceOverKernel);
end;

procedure DestinationOver(var P: TTsHighpPipeline);
begin
  ApplyBlend(P, DestinationOverKernel);
end;

procedure Modulate(var P: TTsHighpPipeline);
begin
  ApplyBlend(P, ModulateKernel);
end;

procedure Multiply(var P: TTsHighpPipeline);
begin
  ApplyBlend(P, MultiplyKernel);
end;

procedure Screen(var P: TTsHighpPipeline);
begin
  ApplyBlend(P, ScreenKernel);
end;

procedure &Xor(var P: TTsHighpPipeline);
begin
  ApplyBlend(P, XorKernel);
end;

procedure Plus(var P: TTsHighpPipeline);
begin
  ApplyBlend(P, PlusKernel);
end;

{ blend_fn2!: the same logic applied to the color, and source_over for the alpha }

procedure ApplyBlend2(var P: TTsHighpPipeline; const Kernel: TTsBlendKernel);
begin
  P.R := Kernel(P.R, P.DR, P.A, P.DA);
  P.G := Kernel(P.G, P.DG, P.A, P.DA);
  P.B := Kernel(P.B, P.DB, P.A, P.DA);
  P.A := Mad(P.DA, Inv(P.A), P.A);

  P.NextStage;
end;

function DarkenKernel(const S, D, SA, DA: TF32x8): TF32x8;
begin
  Result := S + D - (S * DA).Max(D * SA);
end;

function LightenKernel(const S, D, SA, DA: TF32x8): TF32x8;
begin
  Result := S + D - (S * DA).Min(D * SA);
end;

function DifferenceKernel(const S, D, SA, DA: TF32x8): TF32x8;
begin
  Result := S + D - Two((S * DA).Min(D * SA));
end;

function ExclusionKernel(const S, D, SA, DA: TF32x8): TF32x8;
begin
  Result := S + D - Two(S * D);
end;

function ColorBurnKernel(const S, D, SA, DA: TF32x8): TF32x8;
begin
  const Other = SA * (DA - DA.Min((DA - D) * SA * S.RecipFast)) + S * Inv(DA) + D * Inv(SA);
  const NoSource = S.CmpEq(Zero).Blend(D * Inv(SA), Other);

  Result := D.CmpEq(DA).Blend(D + S * Inv(DA), NoSource);
end;

function ColorDodgeKernel(const S, D, SA, DA: TF32x8): TF32x8;
begin
  const Other = SA * DA.Min((D * SA) * (SA - S).RecipFast) + S * Inv(DA) + D * Inv(SA);
  const FullSource = S.CmpEq(SA).Blend(S + D * Inv(SA), Other);

  Result := D.CmpEq(Zero).Blend(S * Inv(DA), FullSource);
end;

function HardLightKernel(const S, D, SA, DA: TF32x8): TF32x8;
begin
  const Branch = Two(S).CmpLe(SA).Blend(Two(S * D), SA * DA - Two((DA - D) * (SA - S)));

  Result := S * Inv(DA) + D * Inv(SA) + Branch;
end;

function OverlayKernel(const S, D, SA, DA: TF32x8): TF32x8;
begin
  const Branch = Two(D).CmpLe(DA).Blend(Two(S * D), SA * DA - Two((DA - D) * (SA - S)));

  Result := S * Inv(DA) + D * Inv(SA) + Branch;
end;

function SoftLightKernel(const S, D, SA, DA: TF32x8): TF32x8;
begin
  const M = DA.CmpGt(Zero).Blend(D / DA, Zero);
  const S2 = Two(S);
  const M4 = Two(Two(M));

  // The logic forks three ways:
  //    1. dark src?
  //    2. light src, dark dst?
  //    3. light src, light dst?
  const DarkSrc = D * (SA + (S2 - SA) * (One - M));
  const DarkDst = (M4 * M4 + M4) * (M - One) + TF32x8.Splat(7) * M;
  const LiteDst = M.Sqrt - M;
  // 2 or 3?
  const LiteSrc = D * SA + DA * (S2 - SA) * Two(Two(D)).CmpLe(DA).Blend(DarkDst, LiteDst);

  // 1 or (2 or 3)?
  Result := S * Inv(DA) + D * Inv(SA) + S2.CmpLe(SA).Blend(DarkSrc, LiteSrc);
end;

procedure Darken(var P: TTsHighpPipeline);
begin
  ApplyBlend2(P, DarkenKernel);
end;

procedure Lighten(var P: TTsHighpPipeline);
begin
  ApplyBlend2(P, LightenKernel);
end;

procedure Difference(var P: TTsHighpPipeline);
begin
  ApplyBlend2(P, DifferenceKernel);
end;

procedure Exclusion(var P: TTsHighpPipeline);
begin
  ApplyBlend2(P, ExclusionKernel);
end;

procedure ColorBurn(var P: TTsHighpPipeline);
begin
  ApplyBlend2(P, ColorBurnKernel);
end;

procedure ColorDodge(var P: TTsHighpPipeline);
begin
  ApplyBlend2(P, ColorDodgeKernel);
end;

procedure HardLight(var P: TTsHighpPipeline);
begin
  ApplyBlend2(P, HardLightKernel);
end;

procedure Overlay(var P: TTsHighpPipeline);
begin
  ApplyBlend2(P, OverlayKernel);
end;

procedure SoftLight(var P: TTsHighpPipeline);
begin
  ApplyBlend2(P, SoftLightKernel);
end;

{ The non-separable blend modes. We're basing our implementation on
  https://www.w3.org/TR/compositing-1/#blendingnonseparable.
  and
  https://www.khronos.org/registry/OpenGL/specs/es/3.2/es_spec_3.2.pdf
  They're equivalent, but ES' math has been better simplified.
  Anything extra we add beyond that is to make the math work with premul inputs. }

function Sat(const R, G, B: TF32x8): TF32x8;
begin
  Result := R.Max(G.Max(B)) - R.Min(G.Min(B));
end;

function Lum(const R, G, B: TF32x8): TF32x8;
begin
  Result := R * TF32x8.Splat(LumRed) + G * TF32x8.Splat(LumGreen) + B * TF32x8.Splat(LumBlue);
end;

// Maps the min channel to 0, the max channel to s, and scales the middle proportionally
function SaturateChannel(const C, Mn, Range, S: TF32x8): TF32x8;
begin
  Result := Range.CmpEq(Zero).Blend(Zero, (C - Mn) * S / Range);
end;

procedure SetSat(var R, G, B: TF32x8; const S: TF32x8);
begin
  const Mn = R.Min(G.Min(B));
  const Mx = R.Max(G.Max(B));
  const Range = Mx - Mn;

  R := SaturateChannel(R, Mn, Range, S);
  G := SaturateChannel(G, Mn, Range, S);
  B := SaturateChannel(B, Mn, Range, S);
end;

procedure SetLum(var R, G, B: TF32x8; const L: TF32x8);
begin
  const Diff = L - Lum(R, G, B);

  R := R + Diff;
  G := G + Diff;
  B := B + Diff;
end;

function ClipChannel(const Channel, Mn, Mx, L, A: TF32x8): TF32x8;
begin
  Result := Mx.CmpGe(Zero).Blend(Channel, L + (Channel - L) * L / (L - Mn));
  Result := Mx.CmpGt(A).Blend(L + (Result - L) * (A - L) / (Mx - L), Result);
  // Sometimes without this we may dip just a little negative
  Result := Result.Max(Zero);
end;

procedure ClipColor(var R, G, B: TF32x8; const A: TF32x8);
begin
  const Mn = R.Min(G.Min(B));
  const Mx = R.Max(G.Max(B));
  const L = Lum(R, G, B);

  R := ClipChannel(R, Mn, Mx, L, A);
  G := ClipChannel(G, Mn, Mx, L, A);
  B := ClipChannel(B, Mn, Mx, L, A);
end;

procedure HueKernel(const R, G, B, A, DR, DG, DB, DA: TF32x8; out TR, TG, TB, TA: TF32x8);
begin
  var RR := R * A;
  var GG := G * A;
  var BB := B * A;

  SetSat(RR, GG, BB, Sat(DR, DG, DB) * A);
  SetLum(RR, GG, BB, Lum(DR, DG, DB) * A);
  ClipColor(RR, GG, BB, A * DA);

  TR := R * Inv(DA) + DR * Inv(A) + RR;
  TG := G * Inv(DA) + DG * Inv(A) + GG;
  TB := B * Inv(DA) + DB * Inv(A) + BB;
  TA := A + DA - A * DA;
end;

procedure SaturationKernel(const R, G, B, A, DR, DG, DB, DA: TF32x8; out TR, TG, TB, TA: TF32x8);
begin
  var RR := DR * A;
  var GG := DG * A;
  var BB := DB * A;

  SetSat(RR, GG, BB, Sat(R, G, B) * DA);
  // This is not redundant
  SetLum(RR, GG, BB, Lum(DR, DG, DB) * A);
  ClipColor(RR, GG, BB, A * DA);

  TR := R * Inv(DA) + DR * Inv(A) + RR;
  TG := G * Inv(DA) + DG * Inv(A) + GG;
  TB := B * Inv(DA) + DB * Inv(A) + BB;
  TA := A + DA - A * DA;
end;

procedure ColorKernel(const R, G, B, A, DR, DG, DB, DA: TF32x8; out TR, TG, TB, TA: TF32x8);
begin
  var RR := R * DA;
  var GG := G * DA;
  var BB := B * DA;

  SetLum(RR, GG, BB, Lum(DR, DG, DB) * A);
  ClipColor(RR, GG, BB, A * DA);

  TR := R * Inv(DA) + DR * Inv(A) + RR;
  TG := G * Inv(DA) + DG * Inv(A) + GG;
  TB := B * Inv(DA) + DB * Inv(A) + BB;
  TA := A + DA - A * DA;
end;

procedure LuminosityKernel(const R, G, B, A, DR, DG, DB, DA: TF32x8; out TR, TG, TB, TA: TF32x8);
begin
  var RR := DR * A;
  var GG := DG * A;
  var BB := DB * A;

  SetLum(RR, GG, BB, Lum(R, G, B) * DA);
  ClipColor(RR, GG, BB, A * DA);

  TR := R * Inv(DA) + DR * Inv(A) + RR;
  TG := G * Inv(DA) + DG * Inv(A) + GG;
  TB := B * Inv(DA) + DB * Inv(A) + BB;
  TA := A + DA - A * DA;
end;

procedure Hue(var P: TTsHighpPipeline);
begin
  var TR, TG, TB, TA: TF32x8;
  HueKernel(P.R, P.G, P.B, P.A, P.DR, P.DG, P.DB, P.DA, TR, TG, TB, TA);
  P.R := TR;
  P.G := TG;
  P.B := TB;
  P.A := TA;

  P.NextStage;
end;

procedure Saturation(var P: TTsHighpPipeline);
begin
  var TR, TG, TB, TA: TF32x8;
  SaturationKernel(P.R, P.G, P.B, P.A, P.DR, P.DG, P.DB, P.DA, TR, TG, TB, TA);
  P.R := TR;
  P.G := TG;
  P.B := TB;
  P.A := TA;

  P.NextStage;
end;

procedure Color(var P: TTsHighpPipeline);
begin
  var TR, TG, TB, TA: TF32x8;
  ColorKernel(P.R, P.G, P.B, P.A, P.DR, P.DG, P.DB, P.DA, TR, TG, TB, TA);
  P.R := TR;
  P.G := TG;
  P.B := TB;
  P.A := TA;

  P.NextStage;
end;

procedure Luminosity(var P: TTsHighpPipeline);
begin
  var TR, TG, TB, TA: TF32x8;
  LuminosityKernel(P.R, P.G, P.B, P.A, P.DR, P.DG, P.DB, P.DA, TR, TG, TB, TA);
  P.R := TR;
  P.G := TG;
  P.B := TB;
  P.A := TA;

  P.NextStage;
end;

procedure SourceOverRgba(var P: TTsHighpPipeline);
begin
  var Colors: TTsColors8;
  ReadPixels(P.PixmapDst^, P.DX, P.DY, HighpStageWidth, Colors);
  Load8888(Colors, P.DR, P.DG, P.DB, P.DA);
  P.R := Mad(P.DR, Inv(P.A), P.R);
  P.G := Mad(P.DG, Inv(P.A), P.G);
  P.B := Mad(P.DB, Inv(P.A), P.B);
  P.A := Mad(P.DA, Inv(P.A), P.A);
  Store8888(P.R, P.G, P.B, P.A, Colors);
  WritePixels(Colors, P.PixmapDst^, P.DX, P.DY, HighpStageWidth);

  P.NextStage;
end;

procedure SourceOverRgbaTail(var P: TTsHighpPipeline);
begin
  var Colors := ClearedColors;
  ReadPixels(P.PixmapDst^, P.DX, P.DY, P.Tail, Colors);
  Load8888(Colors, P.DR, P.DG, P.DB, P.DA);
  P.R := Mad(P.DR, Inv(P.A), P.R);
  P.G := Mad(P.DG, Inv(P.A), P.G);
  P.B := Mad(P.DB, Inv(P.A), P.B);
  P.A := Mad(P.DA, Inv(P.A), P.A);
  Store8888(P.R, P.G, P.B, P.A, Colors);
  WritePixels(Colors, P.PixmapDst^, P.DX, P.DY, P.Tail);

  P.NextStage;
end;

procedure Transform(var P: TTsHighpPipeline);
begin
  const Ts = P.Ctx^.Transform;

  const TR = Mad(P.R, TF32x8.Splat(Ts.SX), Mad(P.G, TF32x8.Splat(Ts.KX), TF32x8.Splat(Ts.TX)));
  const TG = Mad(P.R, TF32x8.Splat(Ts.KY), Mad(P.G, TF32x8.Splat(Ts.SY), TF32x8.Splat(Ts.TY)));
  P.R := TR;
  P.G := TG;

  P.NextStage;
end;

{ Tile x or y to [0,limit) == [0,limit - 1 ulp] (think, sampling from images). The gather stages will hard clamp the output of these
  stages to [0,limit)... we just need to do the basic repeat or mirroring. }

function ExclusiveReflect(const V: TF32x8; const Limit, InvLimit: Single): TF32x8;
begin
  const LimitLanes = TF32x8.Splat(Limit);
  const InvLimitLanes = TF32x8.Splat(InvLimit);
  const Shifted = V - LimitLanes;
  const Steps = (Shifted * (InvLimitLanes * TF32x8.Splat(Half))).Floor;

  Result := (Shifted - (LimitLanes + LimitLanes) * Steps - LimitLanes).Abs;
end;

function ExclusiveRepeat(const V: TF32x8; const Limit, InvLimit: Single): TF32x8;
begin
  Result := V - (V * TF32x8.Splat(InvLimit)).Floor * TF32x8.Splat(Limit);
end;

procedure Reflect(var P: TTsHighpPipeline);
begin
  P.R := ExclusiveReflect(P.R, P.Ctx^.LimitX.Scale, P.Ctx^.LimitX.InvScale);
  P.G := ExclusiveReflect(P.G, P.Ctx^.LimitY.Scale, P.Ctx^.LimitY.InvScale);

  P.NextStage;
end;

procedure &Repeat(var P: TTsHighpPipeline);
begin
  P.R := ExclusiveRepeat(P.R, P.Ctx^.LimitX.Scale, P.Ctx^.LimitX.InvScale);
  P.G := ExclusiveRepeat(P.G, P.Ctx^.LimitY.Scale, P.Ctx^.LimitY.InvScale);

  P.NextStage;
end;

// In bicubic interpolation, the 16 pixels and +/- 0.5 and +/- 1.5 offsets from the sample pixel center are combined with a non-uniform
// cubic filter, with higher values near the center. We break this function into two parts, one for near 0.5 offsets and one for far 1.5
// offsets.
function BicubicNear(const T: TF32x8): TF32x8;
const
  C21Over18: Single = -21 / 18;
  C27Over18: Single = 27 / 18;
  C9Over18: Single = 9 / 18;
  C1Over18: Single = 1 / 18;
begin
  // 1/18 + 9/18t + 27/18t^2 - 21/18t^3 == t ( t ( -21/18t + 27/18) + 9/18) + 1/18
  Result := Mad(T, Mad(T, Mad(TF32x8.Splat(C21Over18), T, TF32x8.Splat(C27Over18)), TF32x8.Splat(C9Over18)), TF32x8.Splat(C1Over18));
end;

function BicubicFar(const T: TF32x8): TF32x8;
const
  C7Over18: Single = 7 / 18;
  CMinus6Over18: Single = -6 / 18;
begin
  // 0/18 + 0/18*t - 6/18t^2 + 7/18t^3 == t^2 (7/18t - 6/18)
  Result := (T * T) * Mad(TF32x8.Splat(C7Over18), T, TF32x8.Splat(CMinus6Over18));
end;

function Tile(const V: TF32x8; const Mode: TTsSpreadMode; const Limit, InvLimit: Single): TF32x8;
begin
  case Mode of
    TTsSpreadMode.Pad     : Result := V;
    // The sample point is tested by DecalXY, the taps pad
    TTsSpreadMode.Decal   : Result := V;
    TTsSpreadMode.&Repeat : Result := ExclusiveRepeat(V, Limit, InvLimit);
    TTsSpreadMode.Reflect : Result := ExclusiveReflect(V, Limit, InvLimit);
  else
    raise EInvalidOpException.CreateFmt('Unsupported spread mode: %d', [Ord(Mode)]);
  end;
end;

procedure Sample(const Pixmap: TTsPixmapRef; const Ctx: TTsSamplerCtx; const X, Y: TF32x8; var R, G, B, A: TF32x8);
begin
  const Width: Single = Pixmap.Width;
  const Height: Single = Pixmap.Height;
  const TiledX = Tile(X, Ctx.SpreadMode, Width, Ctx.InvWidth);
  const TiledY = Tile(Y, Ctx.SpreadMode, Height, Ctx.InvHeight);

  var Colors: TTsColors8;
  GatherPixels(Pixmap, GatherIx(Pixmap, TiledX, TiledY), Colors);
  Load8888(Colors, R, G, B, A);
end;

// The 2x2 and the 4x4 samplers of highp.rs differ only in the count and the start; the weights are the factors of each row and column.
procedure SamplerNxN(const Pixmap: TTsPixmapRef; const Ctx: TTsSamplerCtx; const CX, CY: TF32x8; const Start: Single;
                     const WX, WY: array of TF32x8; var R, G, B, A: TF32x8);
begin
  R := Zero;
  G := Zero;
  B := Zero;
  A := Zero;

  const StartLanes = TF32x8.Splat(Start);
  var Y := CY + StartLanes;
  for var J := 0 to High(WY) do
  begin
    var X := CX + StartLanes;
    for var I := 0 to High(WX) do
    begin
      var RR, GG, BB, AA: TF32x8;
      Sample(Pixmap, Ctx, X, Y, RR, GG, BB, AA);

      const W = WX[I] * WY[J];
      R := Mad(W, RR, R);
      G := Mad(W, GG, G);
      B := Mad(W, BB, B);
      A := Mad(W, AA, A);

      X := X + One;
    end;

    Y := Y + One;
  end;
end;

procedure Bilinear(var P: TTsHighpPipeline);
begin
  const X = P.R;
  const Fx = (X + TF32x8.Splat(Half)).Fract;
  const Y = P.G;
  const Fy = (Y + TF32x8.Splat(Half)).Fract;
  const WX: TArray<TF32x8> = [One - Fx, Fx];
  const WY: TArray<TF32x8> = [One - Fy, Fy];
  const Start: Single = -0.5;

  SamplerNxN(P.PixmapSrc^, P.Ctx^.Sampler, X, Y, Start, WX, WY, P.R, P.G, P.B, P.A);

  P.NextStage;
end;

procedure Bicubic(var P: TTsHighpPipeline);
begin
  const X = P.R;
  const Fx = (X + TF32x8.Splat(Half)).Fract;
  const Y = P.G;
  const Fy = (Y + TF32x8.Splat(Half)).Fract;
  const WX: TArray<TF32x8> = [BicubicFar(One - Fx), BicubicNear(One - Fx), BicubicNear(Fx), BicubicFar(Fx)];
  const WY: TArray<TF32x8> = [BicubicFar(One - Fy), BicubicNear(One - Fy), BicubicNear(Fy), BicubicFar(Fy)];
  const Start: Single = -1.5;

  SamplerNxN(P.PixmapSrc^, P.Ctx^.Sampler, X, Y, Start, WX, WY, P.R, P.G, P.B, P.A);

  P.NextStage;
end;

procedure PadX1(var P: TTsHighpPipeline);
begin
  P.R := P.R.Normalize;

  P.NextStage;
end;

procedure ReflectX1(var P: TTsHighpPipeline);
begin
  const Shifted = P.R - One;
  const Steps = (Shifted * TF32x8.Splat(Half)).Floor;

  P.R := (Shifted - Two(Steps) - One).Abs.Normalize;

  P.NextStage;
end;

procedure RepeatX1(var P: TTsHighpPipeline);
begin
  P.R := (P.R - P.R.Floor).Normalize;

  P.NextStage;
end;

procedure DecalXY(var P: TTsHighpPipeline);
begin
  const Width = TF32x8.Splat(P.Ctx^.LimitX.Scale);
  const Height = TF32x8.Splat(P.Ctx^.LimitY.Scale);

  const InsideX = P.R.CmpGe(Zero) and P.R.CmpLt(Width);
  const InsideY = P.G.CmpGe(Zero) and P.G.CmpLt(Height);
  P.Ctx^.DecalMask := InsideX and InsideY;

  P.NextStage;
end;

procedure CheckDecalMask(var P: TTsHighpPipeline);
begin
  const Mask = P.Ctx^.DecalMask;

  P.R := P.R and Mask;
  P.G := P.G and Mask;
  P.B := P.B and Mask;
  P.A := P.A and Mask;

  P.NextStage;
end;

procedure JustReturnStage(var P: TTsHighpPipeline);
begin
  // Ends the loop
end;

{ TTsHighpStages }

class constructor TTsHighpStages.Create;
begin
  Table[TTsStage.MoveSourceToDestination] := MoveSourceToDestination;
  Table[TTsStage.MoveDestinationToSource] := MoveDestinationToSource;
  Table[TTsStage.Clamp0] := Clamp0;
  Table[TTsStage.ClampA] := ClampA;
  Table[TTsStage.Premultiply] := Premultiply;
  Table[TTsStage.UniformColor] := UniformColor;
  Table[TTsStage.SeedShader] := SeedShader;
  Table[TTsStage.LoadDestination] := LoadDst;
  Table[TTsStage.Store] := Store;
  Table[TTsStage.LoadDestinationU8] := LoadDstU8;
  Table[TTsStage.StoreU8] := StoreU8;
  Table[TTsStage.Gather] := Gather;
  Table[TTsStage.LoadMaskU8] := LoadMaskU8;
  Table[TTsStage.MaskU8] := MaskU8;
  Table[TTsStage.ScaleU8] := ScaleU8;
  Table[TTsStage.LerpU8] := LerpU8;
  Table[TTsStage.Scale1Float] := Scale1Float;
  Table[TTsStage.Lerp1Float] := Lerp1Float;
  Table[TTsStage.DestinationAtop] := DestinationAtop;
  Table[TTsStage.DestinationIn] := DestinationIn;
  Table[TTsStage.DestinationOut] := DestinationOut;
  Table[TTsStage.DestinationOver] := DestinationOver;
  Table[TTsStage.SourceAtop] := SourceAtop;
  Table[TTsStage.SourceIn] := SourceIn;
  Table[TTsStage.SourceOut] := SourceOut;
  Table[TTsStage.SourceOver] := SourceOver;
  Table[TTsStage.Clear] := Clear;
  Table[TTsStage.Modulate] := Modulate;
  Table[TTsStage.Multiply] := Multiply;
  Table[TTsStage.Plus] := Plus;
  Table[TTsStage.Screen] := Screen;
  Table[TTsStage.&Xor] := &Xor;
  Table[TTsStage.ColorBurn] := ColorBurn;
  Table[TTsStage.ColorDodge] := ColorDodge;
  Table[TTsStage.Darken] := Darken;
  Table[TTsStage.Difference] := Difference;
  Table[TTsStage.Exclusion] := Exclusion;
  Table[TTsStage.HardLight] := HardLight;
  Table[TTsStage.Lighten] := Lighten;
  Table[TTsStage.Overlay] := Overlay;
  Table[TTsStage.SoftLight] := SoftLight;
  Table[TTsStage.Hue] := Hue;
  Table[TTsStage.Saturation] := Saturation;
  Table[TTsStage.Color] := Color;
  Table[TTsStage.Luminosity] := Luminosity;
  Table[TTsStage.SourceOverRgba] := SourceOverRgba;
  Table[TTsStage.Transform] := Transform;
  Table[TTsStage.Reflect] := Reflect;
  Table[TTsStage.&Repeat] := &Repeat;
  Table[TTsStage.Bilinear] := Bilinear;
  Table[TTsStage.Bicubic] := Bicubic;
  Table[TTsStage.PadX1] := PadX1;
  Table[TTsStage.ReflectX1] := ReflectX1;
  Table[TTsStage.RepeatX1] := RepeatX1;
  Table[TTsStage.DecalXY] := DecalXY;
  Table[TTsStage.CheckDecalMask] := CheckDecalMask;

  TailTable := Table;
  TailTable[TTsStage.LoadDestination] := LoadDstTail;
  TailTable[TTsStage.Store] := StoreTail;
  TailTable[TTsStage.LoadDestinationU8] := LoadDstU8Tail;
  TailTable[TTsStage.StoreU8] := StoreU8Tail;
  TailTable[TTsStage.SourceOverRgba] := SourceOverRgbaTail;
end;

class function TTsHighpStages.JustReturn: TTsHighpStageFn;
begin
  Result := JustReturnStage;
end;

class procedure TTsHighpStages.Start(const Functions, FunctionsTail: TTsHighpStageFunctions; const Rect: TTsScreenIntRect;
  const AAMaskCtx: TTsAAMaskCtx; const MaskCtx: TTsMaskCtx; var Ctx: TTsPipelineContext; const PixmapSrc: TTsPixmapRef;
  var PixmapDst: TTsSubPixmapMut);
begin
  var P := Default(TTsHighpPipeline);
  P.PixmapSrc := @PixmapSrc;
  P.PixmapDst := @PixmapDst;
  P.MaskCtx := @MaskCtx;
  P.AAMaskCtx := @AAMaskCtx;
  P.Ctx := @Ctx;

  var Y := Int64(Rect.Y);
  while Y < Rect.Bottom do
  begin
    var X := Int64(Rect.X);
    const EndX = Int64(Rect.Right);

    P.Functions := @Functions;
    while X + HighpStageWidth <= EndX do
    begin
      P.Index := 0;
      P.DX := X;
      P.DY := Y;
      P.Tail := HighpStageWidth;
      P.NextStage;
      Inc(X, HighpStageWidth);
    end;

    if X <> EndX then
    begin
      P.Index := 0;
      P.Functions := @FunctionsTail;
      P.DX := X;
      P.DY := Y;
      P.Tail := EndX - X;
      P.NextStage;
    end;

    Inc(Y);
  end;
end;

end.
