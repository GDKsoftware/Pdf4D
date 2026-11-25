// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: tiny-skia v0.12.0 src/pipeline/lowp.rs
// Copyright (c) 2018 Google Inc., (c) 2020 Yevhenii Reizner. BSD-3-Clause, see licenses/tiny-skia-BSD-3-Clause.txt.
unit Pdf4D.Render.Native.Pipeline.Lowp;

// The wrapping arithmetic of the u16 lanes is intended
{$OVERFLOWCHECKS OFF}
{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

uses
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.Wide,
  Pdf4D.Render.Native.Stage,
  Pdf4D.Render.Native.Pipeline.Context;

// A low precision raster pipeline: u16 lanes instead of f32, sixteen pixels per run. It has no implementation of the stages that need high
// precision (Clamp0, ClampA, Gather, ColorBurn, ColorDodge, SoftLight, the non-separable modes, the samplers); their entries in the tables
// are nil, which is the null_fn of the Rust table. The gradient, conical gradient and gamma stages are not ported at all. The pipeline
// compiler uses this pipeline only when every stage has a function here.

type
  PTsLowpStageFunctions = ^TTsLowpStageFunctions;

  // Pipeline of lowp.rs. The pointers refer to values that live as long as the run of Start.
  TTsLowpPipeline = record
    Index: Integer;
    Functions: PTsLowpStageFunctions;
    PixmapDst: PTsSubPixmapMut;
    Ctx: PTsPipelineContext;
    MaskCtx: PTsMaskCtx;
    AAMaskCtx: PTsAAMaskCtx;
    R: TU16x16;
    G: TU16x16;
    B: TU16x16;
    A: TU16x16;
    DR: TU16x16;
    DG: TU16x16;
    DB: TU16x16;
    DA: TU16x16;
    Tail: Integer;
    DX: Integer;
    DY: Integer;

    procedure NextStage;
  end;

  TTsLowpStageFn = procedure(var P: TTsLowpPipeline);

  TTsLowpStageFunctions = record
    Items: array[0..MaxStages] of TTsLowpStageFn;
    Count: Integer;
  end;

  TTsLowpStageTable = array[TTsStage] of TTsLowpStageFn;

  // The STAGES table in the order of the stages, filled once by the class constructor and only read afterwards. A nil entry is null_fn.
  // TailTable has the functions of the last run of a row, which has fewer than sixteen pixels.
  TTsLowpStages = record
  public
    class var Table: TTsLowpStageTable;
    class var TailTable: TTsLowpStageTable;

    class constructor Create;

    // True when the stage has a function in this pipeline
    class function HasStage(const Stage: TTsStage): Boolean; static;

    // The function that ends the loop, which compile adds after the last stage
    class function JustReturn: TTsLowpStageFn; static;

    // (v + 255) >> 8 of lowp.rs, the division by 255 that this pipeline uses
    class function Div255(const V: TU16x16): TU16x16; static;

    // Runs the functions over every pixel of the rect, sixteen at a time and a tail of fewer than sixteen at the end of each row. The pixels
    // of the region must be in the data of PixmapDst; the caller checks that.
    class procedure Start(const Functions, FunctionsTail: TTsLowpStageFunctions; const Rect: TTsScreenIntRect;
                          const AAMaskCtx: TTsAAMaskCtx; const MaskCtx: TTsMaskCtx; var Ctx: TTsPipelineContext;
                          var PixmapDst: TTsSubPixmapMut); static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Color;

type
  TTsColors16 = array[0..LowpStageWidth - 1] of TTsPremultipliedColorU8;

  TTsBlendKernel = function(const S, D, SA, DA: TU16x16): TU16x16;

const
  Scale255: Single = 255;
  Half: Single = 0.5;

{ TTsLowpPipeline }

procedure TTsLowpPipeline.NextStage;
begin
  const Next = Functions^.Items[Index];
  Inc(Index);
  Next(Self);
end;

{ helpers of lowp.rs }

function Zero: TU16x16; inline;
begin
  Result := TU16x16.Splat(0);
end;

function Div255(const V: TU16x16): TU16x16; inline;
begin
  Result := (V + TU16x16.Splat(255)) shr TU16x16.Splat(8);
end;

function Inv(const V: TU16x16): TU16x16; inline;
begin
  Result := TU16x16.Splat(255) - V;
end;

function FromFloat(const F: Single): TU16x16;
begin
  // `(f * 255.0 + 0.5) as u16`: every step is an f32, the cast saturates
  const Scaled: Single = F * Scale255;
  const Rounded: Single = Scaled + Half;
  const Saturated = TTsScalar.SaturateToInt32(Rounded);

  Result := TU16x16.Splat(Word(Min(Max(Saturated, 0), High(Word))));
end;

function Lerp(const From, ToValue, T: TU16x16): TU16x16; inline;
begin
  Result := Div255(From * Inv(T) + ToValue * T);
end;

// split: the bytes of a f32x16 are two u16x16
procedure Split(const V: TF32x16; var Lo, Hi: TU16x16);
begin
  Move(V.Lanes[0], Lo.Lanes[0], SizeOf(Lo.Lanes));
  Move(V.Lanes[8], Hi.Lanes[0], SizeOf(Hi.Lanes));
end;

function Join(const Lo, Hi: TU16x16): TF32x16;
begin
  Move(Lo.Lanes[0], Result.Lanes[0], SizeOf(Lo.Lanes));
  Move(Hi.Lanes[0], Result.Lanes[8], SizeOf(Hi.Lanes));
end;

function Mad(const F, M, A: TF32x16): TF32x16; inline;
begin
  Result := F * M + A;
end;

procedure Load8888(const Data: TTsColors16; var R, G, B, A: TU16x16);
begin
  for var I := 0 to LowpStageWidth - 1 do
  begin
    R.Lanes[I] := Data[I].Red;
    G.Lanes[I] := Data[I].Green;
    B.Lanes[I] := Data[I].Blue;
    A.Lanes[I] := Data[I].Alpha;
  end;
end;

procedure Store8888(const R, G, B, A: TU16x16; var Data: TTsColors16);
begin
  for var I := 0 to LowpStageWidth - 1 do
  begin
    Data[I] := TTsPremultipliedColorU8.FromRgbaUnchecked(Byte(R.Lanes[I]), Byte(G.Lanes[I]), Byte(B.Lanes[I]), Byte(A.Lanes[I]));
  end;
end;

function ClearedColors: TTsColors16;
begin
  for var I := 0 to LowpStageWidth - 1 do
  begin
    Result[I] := TTsPremultipliedColorU8.Transparent;
  end;
end;

procedure ReadPixels(const Pixmap: TTsSubPixmapMut; const DX, DY, Count: Integer; var Colors: TTsColors16);
begin
  Move(Pixmap.Data[Pixmap.PixelIndex(DX, DY) * 4], Colors, Count * 4);
end;

procedure WritePixels(const Colors: TTsColors16; var Pixmap: TTsSubPixmapMut; const DX, DY, Count: Integer);
begin
  Move(Colors, Pixmap.Data[Pixmap.PixelIndex(DX, DY) * 4], Count * 4);
end;

// The coverage bytes of a mask for the pixels of the run. The Rust code panics for a byte outside the mask; here it is 0.
function MaskCoverage(const P: TTsLowpPipeline): TU16x16;
begin
  Result := Zero;

  const Offset = P.MaskCtx^.ByteIndex(P.DX, P.DY);
  for var I := 0 to P.Tail - 1 do
  begin
    const Position = Offset + I;
    const IsInsideMask = ((Position >= 0) and (Position < Length(P.MaskCtx^.Data)));
    if IsInsideMask then
    begin
      Result.Lanes[I] := P.MaskCtx^.Data[Position];
    end;
  end;
end;

function AACoverage(const P: TTsLowpPipeline): TU16x16;
begin
  var First, Second: Byte;
  P.AAMaskCtx^.CopyAtXY(P.DX, P.DY, P.Tail, First, Second);

  Result := Zero;
  Result.Lanes[0] := First;
  Result.Lanes[1] := Second;
end;

{ stages }

procedure MoveSourceToDestination(var P: TTsLowpPipeline);
begin
  P.DR := P.R;
  P.DG := P.G;
  P.DB := P.B;
  P.DA := P.A;

  P.NextStage;
end;

procedure MoveDestinationToSource(var P: TTsLowpPipeline);
begin
  P.R := P.DR;
  P.G := P.DG;
  P.B := P.DB;
  P.A := P.DA;

  P.NextStage;
end;

procedure Premultiply(var P: TTsLowpPipeline);
begin
  P.R := Div255(P.R * P.A);
  P.G := Div255(P.G * P.A);
  P.B := Div255(P.B * P.A);

  P.NextStage;
end;

procedure UniformColor(var P: TTsLowpPipeline);
begin
  P.R := TU16x16.Splat(P.Ctx^.UniformColor.Rgba[0]);
  P.G := TU16x16.Splat(P.Ctx^.UniformColor.Rgba[1]);
  P.B := TU16x16.Splat(P.Ctx^.UniformColor.Rgba[2]);
  P.A := TU16x16.Splat(P.Ctx^.UniformColor.Rgba[3]);

  P.NextStage;
end;

procedure SeedShader(var P: TTsLowpPipeline);
begin
  const Iota = TF32x16.Create(TF32x8.FromArray([0.5, 1.5, 2.5, 3.5, 4.5, 5.5, 6.5, 7.5]),
                              TF32x8.FromArray([8.5, 9.5, 10.5, 11.5, 12.5, 13.5, 14.5, 15.5]));
  const DXValue: Single = P.DX;
  const DYValue: Single = P.DY;
  const YCenter: Single = DYValue + Half;

  const X = TF32x16.Splat(DXValue) + Iota;
  const Y = TF32x16.Splat(YCenter);
  Split(X, P.R, P.G);
  Split(Y, P.B, P.A);

  P.NextStage;
end;

procedure LoadDst(var P: TTsLowpPipeline);
begin
  var Colors: TTsColors16;
  ReadPixels(P.PixmapDst^, P.DX, P.DY, LowpStageWidth, Colors);
  Load8888(Colors, P.DR, P.DG, P.DB, P.DA);

  P.NextStage;
end;

procedure LoadDstTail(var P: TTsLowpPipeline);
begin
  // Fill a dummy array with `tail` values, so that the full load can be reused
  var Colors := ClearedColors;
  ReadPixels(P.PixmapDst^, P.DX, P.DY, P.Tail, Colors);
  Load8888(Colors, P.DR, P.DG, P.DB, P.DA);

  P.NextStage;
end;

procedure Store(var P: TTsLowpPipeline);
begin
  var Colors: TTsColors16;
  Store8888(P.R, P.G, P.B, P.A, Colors);
  WritePixels(Colors, P.PixmapDst^, P.DX, P.DY, LowpStageWidth);

  P.NextStage;
end;

procedure StoreTail(var P: TTsLowpPipeline);
begin
  var Colors: TTsColors16;
  Store8888(P.R, P.G, P.B, P.A, Colors);
  WritePixels(Colors, P.PixmapDst^, P.DX, P.DY, P.Tail);

  P.NextStage;
end;

// The destination is an A8 pixmap: one byte per pixel
procedure LoadDstU8Count(var P: TTsLowpPipeline; const Count: Integer);
begin
  P.DA := Zero;

  const Start = P.PixmapDst^.MaskIndex(P.DX, P.DY);
  for var I := 0 to Count - 1 do
  begin
    P.DA.Lanes[I] := P.PixmapDst^.Data[Start + I];
  end;
end;

procedure StoreU8Count(var P: TTsLowpPipeline; const Count: Integer);
begin
  const Start = P.PixmapDst^.MaskIndex(P.DX, P.DY);
  for var I := 0 to Count - 1 do
  begin
    P.PixmapDst^.Data[Start + I] := Byte(P.A.Lanes[I]);
  end;
end;

procedure LoadDstU8(var P: TTsLowpPipeline);
begin
  LoadDstU8Count(P, LowpStageWidth);

  P.NextStage;
end;

procedure LoadDstU8Tail(var P: TTsLowpPipeline);
begin
  LoadDstU8Count(P, P.Tail);

  P.NextStage;
end;

procedure StoreU8(var P: TTsLowpPipeline);
begin
  StoreU8Count(P, LowpStageWidth);

  P.NextStage;
end;

procedure StoreU8Tail(var P: TTsLowpPipeline);
begin
  StoreU8Count(P, P.Tail);

  P.NextStage;
end;

// Similar to mask_u8, but only loads the mask values without actually masking the pipeline
procedure LoadMaskU8(var P: TTsLowpPipeline);
begin
  const C = MaskCoverage(P);

  P.R := Zero;
  P.G := Zero;
  P.B := Zero;
  P.A := C;

  P.NextStage;
end;

procedure MaskU8(var P: TTsLowpPipeline);
begin
  const C = MaskCoverage(P);

  if C = Zero then
  begin
    Exit;
  end;

  P.R := Div255(P.R * C);
  P.G := Div255(P.G * C);
  P.B := Div255(P.B * C);
  P.A := Div255(P.A * C);

  P.NextStage;
end;

procedure ScaleU8(var P: TTsLowpPipeline);
begin
  const C = AACoverage(P);

  P.R := Div255(P.R * C);
  P.G := Div255(P.G * C);
  P.B := Div255(P.B * C);
  P.A := Div255(P.A * C);

  P.NextStage;
end;

procedure LerpU8(var P: TTsLowpPipeline);
begin
  const C = AACoverage(P);

  P.R := Lerp(P.DR, P.R, C);
  P.G := Lerp(P.DG, P.G, C);
  P.B := Lerp(P.DB, P.B, C);
  P.A := Lerp(P.DA, P.A, C);

  P.NextStage;
end;

procedure Scale1Float(var P: TTsLowpPipeline);
begin
  const C = FromFloat(P.Ctx^.CurrentCoverage);

  P.R := Div255(P.R * C);
  P.G := Div255(P.G * C);
  P.B := Div255(P.B * C);
  P.A := Div255(P.A * C);

  P.NextStage;
end;

procedure Lerp1Float(var P: TTsLowpPipeline);
begin
  const C = FromFloat(P.Ctx^.CurrentCoverage);

  P.R := Lerp(P.DR, P.R, C);
  P.G := Lerp(P.DG, P.G, C);
  P.B := Lerp(P.DB, P.B, C);
  P.A := Lerp(P.DA, P.A, C);

  P.NextStage;
end;

{ blend_fn!: the same logic for the color and the alpha }

procedure ApplyBlend(var P: TTsLowpPipeline; const Kernel: TTsBlendKernel);
begin
  P.R := Kernel(P.R, P.DR, P.A, P.DA);
  P.G := Kernel(P.G, P.DG, P.A, P.DA);
  P.B := Kernel(P.B, P.DB, P.A, P.DA);
  P.A := Kernel(P.A, P.DA, P.A, P.DA);

  P.NextStage;
end;

function ClearKernel(const S, D, SA, DA: TU16x16): TU16x16;
begin
  Result := Zero;
end;

function SourceAtopKernel(const S, D, SA, DA: TU16x16): TU16x16;
begin
  Result := Div255(S * DA + D * Inv(SA));
end;

function DestinationAtopKernel(const S, D, SA, DA: TU16x16): TU16x16;
begin
  Result := Div255(D * SA + S * Inv(DA));
end;

function SourceInKernel(const S, D, SA, DA: TU16x16): TU16x16;
begin
  Result := Div255(S * DA);
end;

function DestinationInKernel(const S, D, SA, DA: TU16x16): TU16x16;
begin
  Result := Div255(D * SA);
end;

function SourceOutKernel(const S, D, SA, DA: TU16x16): TU16x16;
begin
  Result := Div255(S * Inv(DA));
end;

function DestinationOutKernel(const S, D, SA, DA: TU16x16): TU16x16;
begin
  Result := Div255(D * Inv(SA));
end;

function SourceOverKernel(const S, D, SA, DA: TU16x16): TU16x16;
begin
  Result := S + Div255(D * Inv(SA));
end;

function DestinationOverKernel(const S, D, SA, DA: TU16x16): TU16x16;
begin
  Result := D + Div255(S * Inv(DA));
end;

function ModulateKernel(const S, D, SA, DA: TU16x16): TU16x16;
begin
  Result := Div255(S * D);
end;

function MultiplyKernel(const S, D, SA, DA: TU16x16): TU16x16;
begin
  Result := Div255(S * Inv(DA) + D * Inv(SA) + S * D);
end;

function ScreenKernel(const S, D, SA, DA: TU16x16): TU16x16;
begin
  Result := S + D - Div255(S * D);
end;

function XorKernel(const S, D, SA, DA: TU16x16): TU16x16;
begin
  Result := Div255(S * Inv(DA) + D * Inv(SA));
end;

function PlusKernel(const S, D, SA, DA: TU16x16): TU16x16;
begin
  Result := (S + D).Min(TU16x16.Splat(255));
end;

procedure Clear(var P: TTsLowpPipeline);
begin
  ApplyBlend(P, ClearKernel);
end;

procedure SourceAtop(var P: TTsLowpPipeline);
begin
  ApplyBlend(P, SourceAtopKernel);
end;

procedure DestinationAtop(var P: TTsLowpPipeline);
begin
  ApplyBlend(P, DestinationAtopKernel);
end;

procedure SourceIn(var P: TTsLowpPipeline);
begin
  ApplyBlend(P, SourceInKernel);
end;

procedure DestinationIn(var P: TTsLowpPipeline);
begin
  ApplyBlend(P, DestinationInKernel);
end;

procedure SourceOut(var P: TTsLowpPipeline);
begin
  ApplyBlend(P, SourceOutKernel);
end;

procedure DestinationOut(var P: TTsLowpPipeline);
begin
  ApplyBlend(P, DestinationOutKernel);
end;

procedure SourceOver(var P: TTsLowpPipeline);
begin
  ApplyBlend(P, SourceOverKernel);
end;

procedure DestinationOver(var P: TTsLowpPipeline);
begin
  ApplyBlend(P, DestinationOverKernel);
end;

procedure Modulate(var P: TTsLowpPipeline);
begin
  ApplyBlend(P, ModulateKernel);
end;

procedure Multiply(var P: TTsLowpPipeline);
begin
  ApplyBlend(P, MultiplyKernel);
end;

procedure Screen(var P: TTsLowpPipeline);
begin
  ApplyBlend(P, ScreenKernel);
end;

procedure &Xor(var P: TTsLowpPipeline);
begin
  ApplyBlend(P, XorKernel);
end;

procedure Plus(var P: TTsLowpPipeline);
begin
  ApplyBlend(P, PlusKernel);
end;

{ blend_fn2!: the same logic applied to the color, and source_over for the alpha }

procedure ApplyBlend2(var P: TTsLowpPipeline; const Kernel: TTsBlendKernel);
begin
  P.R := Kernel(P.R, P.DR, P.A, P.DA);
  P.G := Kernel(P.G, P.DG, P.A, P.DA);
  P.B := Kernel(P.B, P.DB, P.A, P.DA);
  P.A := P.A + Div255(P.DA * Inv(P.A));

  P.NextStage;
end;

function DarkenKernel(const S, D, SA, DA: TU16x16): TU16x16;
begin
  Result := S + D - Div255((S * DA).Max(D * SA));
end;

function LightenKernel(const S, D, SA, DA: TU16x16): TU16x16;
begin
  Result := S + D - Div255((S * DA).Min(D * SA));
end;

function ExclusionKernel(const S, D, SA, DA: TU16x16): TU16x16;
begin
  Result := S + D - TU16x16.Splat(2) * Div255(S * D);
end;

function DifferenceKernel(const S, D, SA, DA: TU16x16): TU16x16;
begin
  Result := S + D - TU16x16.Splat(2) * Div255((S * DA).Min(D * SA));
end;

function HardLightKernel(const S, D, SA, DA: TU16x16): TU16x16;
begin
  const Branch = (S + S).CmpLe(SA).Blend(TU16x16.Splat(2) * S * D, SA * DA - TU16x16.Splat(2) * (SA - S) * (DA - D));

  Result := Div255(S * Inv(DA) + D * Inv(SA) + Branch);
end;

function OverlayKernel(const S, D, SA, DA: TU16x16): TU16x16;
begin
  const Branch = (D + D).CmpLe(DA).Blend(TU16x16.Splat(2) * S * D, SA * DA - TU16x16.Splat(2) * (SA - S) * (DA - D));

  Result := Div255(S * Inv(DA) + D * Inv(SA) + Branch);
end;

procedure Darken(var P: TTsLowpPipeline);
begin
  ApplyBlend2(P, DarkenKernel);
end;

procedure Lighten(var P: TTsLowpPipeline);
begin
  ApplyBlend2(P, LightenKernel);
end;

procedure Exclusion(var P: TTsLowpPipeline);
begin
  ApplyBlend2(P, ExclusionKernel);
end;

procedure Difference(var P: TTsLowpPipeline);
begin
  ApplyBlend2(P, DifferenceKernel);
end;

procedure HardLight(var P: TTsLowpPipeline);
begin
  ApplyBlend2(P, HardLightKernel);
end;

procedure Overlay(var P: TTsLowpPipeline);
begin
  ApplyBlend2(P, OverlayKernel);
end;

procedure SourceOverRgba(var P: TTsLowpPipeline);
begin
  var Colors: TTsColors16;
  ReadPixels(P.PixmapDst^, P.DX, P.DY, LowpStageWidth, Colors);
  Load8888(Colors, P.DR, P.DG, P.DB, P.DA);
  P.R := P.R + Div255(P.DR * Inv(P.A));
  P.G := P.G + Div255(P.DG * Inv(P.A));
  P.B := P.B + Div255(P.DB * Inv(P.A));
  P.A := P.A + Div255(P.DA * Inv(P.A));
  Store8888(P.R, P.G, P.B, P.A, Colors);
  WritePixels(Colors, P.PixmapDst^, P.DX, P.DY, LowpStageWidth);

  P.NextStage;
end;

procedure SourceOverRgbaTail(var P: TTsLowpPipeline);
begin
  var Colors := ClearedColors;
  ReadPixels(P.PixmapDst^, P.DX, P.DY, P.Tail, Colors);
  Load8888(Colors, P.DR, P.DG, P.DB, P.DA);
  P.R := P.R + Div255(P.DR * Inv(P.A));
  P.G := P.G + Div255(P.DG * Inv(P.A));
  P.B := P.B + Div255(P.DB * Inv(P.A));
  P.A := P.A + Div255(P.DA * Inv(P.A));
  Store8888(P.R, P.G, P.B, P.A, Colors);
  WritePixels(Colors, P.PixmapDst^, P.DX, P.DY, P.Tail);

  P.NextStage;
end;

procedure Transform(var P: TTsLowpPipeline);
begin
  const Ts = P.Ctx^.Transform;

  const X = Join(P.R, P.G);
  const Y = Join(P.B, P.A);

  const NX = Mad(X, TF32x16.Splat(Ts.SX), Mad(Y, TF32x16.Splat(Ts.KX), TF32x16.Splat(Ts.TX)));
  const NY = Mad(X, TF32x16.Splat(Ts.KY), Mad(Y, TF32x16.Splat(Ts.SY), TF32x16.Splat(Ts.TY)));

  Split(NX, P.R, P.G);
  Split(NY, P.B, P.A);

  P.NextStage;
end;

procedure PadX1(var P: TTsLowpPipeline);
begin
  const X = Join(P.R, P.G).Normalize;
  Split(X, P.R, P.G);

  P.NextStage;
end;

procedure ReflectX1(var P: TTsLowpPipeline);
begin
  const X = Join(P.R, P.G);
  const One = TF32x16.Splat(1);
  const Shifted = X - One;
  const Steps = (Shifted * TF32x16.Splat(Half)).Floor;
  const Reflected = (Shifted - (Steps + Steps) - One).Abs.Normalize;
  Split(Reflected, P.R, P.G);

  P.NextStage;
end;

procedure RepeatX1(var P: TTsLowpPipeline);
begin
  const X = Join(P.R, P.G);
  const Fraction = (X - X.Floor).Normalize;
  Split(Fraction, P.R, P.G);

  P.NextStage;
end;

procedure JustReturnStage(var P: TTsLowpPipeline);
begin
  // Ends the loop
end;

{ TTsLowpStages }

class constructor TTsLowpStages.Create;
begin
  Table[TTsStage.MoveSourceToDestination] := MoveSourceToDestination;
  Table[TTsStage.MoveDestinationToSource] := MoveDestinationToSource;
  Table[TTsStage.Premultiply] := Premultiply;
  Table[TTsStage.UniformColor] := UniformColor;
  Table[TTsStage.SeedShader] := SeedShader;
  Table[TTsStage.LoadDestination] := LoadDst;
  Table[TTsStage.Store] := Store;
  Table[TTsStage.LoadDestinationU8] := LoadDstU8;
  Table[TTsStage.StoreU8] := StoreU8;
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
  Table[TTsStage.Darken] := Darken;
  Table[TTsStage.Difference] := Difference;
  Table[TTsStage.Exclusion] := Exclusion;
  Table[TTsStage.HardLight] := HardLight;
  Table[TTsStage.Lighten] := Lighten;
  Table[TTsStage.Overlay] := Overlay;
  Table[TTsStage.SourceOverRgba] := SourceOverRgba;
  Table[TTsStage.Transform] := Transform;
  Table[TTsStage.PadX1] := PadX1;
  Table[TTsStage.ReflectX1] := ReflectX1;
  Table[TTsStage.RepeatX1] := RepeatX1;

  TailTable := Table;
  TailTable[TTsStage.LoadDestination] := LoadDstTail;
  TailTable[TTsStage.Store] := StoreTail;
  TailTable[TTsStage.LoadDestinationU8] := LoadDstU8Tail;
  TailTable[TTsStage.StoreU8] := StoreU8Tail;
  TailTable[TTsStage.SourceOverRgba] := SourceOverRgbaTail;
end;

class function TTsLowpStages.HasStage(const Stage: TTsStage): Boolean;
begin
  Result := Assigned(Table[Stage]);
end;

class function TTsLowpStages.JustReturn: TTsLowpStageFn;
begin
  Result := JustReturnStage;
end;

class function TTsLowpStages.Div255(const V: TU16x16): TU16x16;
begin
  Result := Pdf4D.Render.Native.Pipeline.Lowp.Div255(V);
end;

class procedure TTsLowpStages.Start(const Functions, FunctionsTail: TTsLowpStageFunctions; const Rect: TTsScreenIntRect;
  const AAMaskCtx: TTsAAMaskCtx; const MaskCtx: TTsMaskCtx; var Ctx: TTsPipelineContext; var PixmapDst: TTsSubPixmapMut);
begin
  var P := Default(TTsLowpPipeline);
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
    while X + LowpStageWidth <= EndX do
    begin
      P.Index := 0;
      P.DX := X;
      P.DY := Y;
      P.Tail := LowpStageWidth;
      P.NextStage;
      Inc(X, LowpStageWidth);
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
