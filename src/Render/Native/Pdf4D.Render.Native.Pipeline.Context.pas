// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: tiny-skia v0.12.0 src/pipeline/mod.rs (the contexts)
// Copyright (c) 2016 Google Inc., (c) 2020 Yevhenii Reizner. BSD-3-Clause, see licenses/tiny-skia-BSD-3-Clause.txt.
unit Pdf4D.Render.Native.Pipeline.Context;

{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  Pdf4D.Render.Native.Wide,
  Pdf4D.Render.Native.Transform,
  Pdf4D.Render.Native.Pixmap;

// The contexts of mod.rs that every stage of the pipelines shares. They live in a unit of their own because the high precision stages (Pdf4D.Render.Native.Pipeline.Highp) and the pipeline
// (Pdf4D.Render.Native.Pipeline) need them and the pipeline uses the stage tables, so that neither of the two can declare them.
//
// A Rust slice of mask data is a byte array and the byte offset where the slice starts. The gradient contexts, the conical gradient
// context and the sampler of gradients are not ported.

const
  // STAGE_WIDTH of the high precision pipeline: pixels per run
  HighpStageWidth = 8;
  // STAGE_WIDTH of the low precision pipeline
  LowpStageWidth = 16;
  // MAX_STAGES: More than enough
  MaxStages = 32;

type
  // The Rust SpreadMode, and Decal of Pdf4D: the shader gives a transparent color outside the pixmap (the DecalXY and CheckDecalMask stages of
  // the high precision pipeline), and the filter taps beyond the edge pad.
  TTsSpreadMode = (Pad, Reflect, &Repeat, Decal);

  // AAMaskCtx: the coverage of at most two pixels
  TTsAAMaskCtx = record
    Pixels: array[0..1] of Byte;
    // Can be zero
    Stride: Cardinal;
    // Mask offset/position in pixmap coordinates
    Shift: NativeInt;

    // copy_at_xy: only the three combinations that the super blitter produces are known, everything else gives zeros
    procedure CopyAtXY(const DX, DY, Tail: Integer; out First, Second: Byte);
  end;

  // MaskCtx: the bytes of a mask, from the first pixel of the region on. Data is the whole data of the mask, Offset the byte offset.
  TTsMaskCtx = record
    Data: TBytes;
    Offset: NativeInt;
    RealWidth: Cardinal;

    // offset(): the index in Data of the byte of the pixel (DX, DY), counted from Offset
    function ByteIndex(const DX, DY: Int64): Int64;
  end;

  TTsSamplerCtx = record
    SpreadMode: TTsSpreadMode;
    InvWidth: Single;
    InvHeight: Single;
  end;

  TTsUniformColorCtx = record
    R: Single;
    G: Single;
    B: Single;
    A: Single;
    // [0,255] in a 16-bit lane
    Rgba: array[0..3] of Word;
  end;

  TTsTileCtx = record
    Scale: Single;
    // Cache of 1/scale
    InvScale: Single;
  end;

  TTsPipelineContext = record
    CurrentCoverage: Single;
    Sampler: TTsSamplerCtx;
    UniformColor: TTsUniformColorCtx;
    LimitX: TTsTileCtx;
    LimitY: TTsTileCtx;
    Transform: TTsTransform;
    // DecalXY: the lanes (all bits set) whose sample point is inside the pixmap, for CheckDecalMask
    DecalMask: TF32x8;

    // Context::default(): the transform is the identity, everything else zero
    class function New: TTsPipelineContext; static;
  end;

  PTsPipelineContext = ^TTsPipelineContext;
  PTsAAMaskCtx = ^TTsAAMaskCtx;
  PTsMaskCtx = ^TTsMaskCtx;

implementation

{ TTsAAMaskCtx }

procedure TTsAAMaskCtx.CopyAtXY(const DX, DY, Tail: Integer; out First, Second: Byte);
begin
  First := 0;
  Second := 0;

  const Position = Int64(Stride) * DY + DX - Shift;

  if (Position = 0) and (Tail = 1) then
  begin
    First := Pixels[0];
  end
  else if (Position = 0) and (Tail = 2) then
  begin
    First := Pixels[0];
    Second := Pixels[1];
  end
  else if (Position = 1) and (Tail = 1) then
  begin
    First := Pixels[1];
  end;
end;

{ TTsMaskCtx }

function TTsMaskCtx.ByteIndex(const DX, DY: Int64): Int64;
begin
  Result := Offset + Int64(RealWidth) * DY + DX;
end;

{ TTsPipelineContext }

class function TTsPipelineContext.New: TTsPipelineContext;
begin
  Result := Default(TTsPipelineContext);
  Result.Transform := TTsTransform.Identity;
end;

end.
