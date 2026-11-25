// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: tiny-skia v0.12.0 src/pipeline/mod.rs (the contexts), src/pixmap.rs (PixmapRef, SubPixmapMut), src/mask.rs (SubMaskRef)
// Copyright (c) 2016 Google Inc., (c) 2020 Yevhenii Reizner. BSD-3-Clause, see licenses/tiny-skia-BSD-3-Clause.txt.
unit Pdf4D.Render.Native.Pipeline.Context;

{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  Pdf4D.Render.Native.Transform;

// The contexts of mod.rs that every stage of the pipelines shares, with the minimal pixmap and mask views that the pipeline reads and
// writes. They live in a unit of their own because the high precision stages (Pdf4D.Render.Native.Pipeline.Highp) and the pipeline
// (Pdf4D.Render.Native.Pipeline) need them and the pipeline uses the stage tables, so that neither of the two can declare them.
//
// A Rust slice of the pixel data is a byte array and the byte offset where the slice starts. The gradient contexts, the conical gradient
// context and the sampler of gradients are not ported.

const
  // STAGE_WIDTH of the high precision pipeline: pixels per run
  HighpStageWidth = 8;
  // MAX_STAGES: More than enough
  MaxStages = 32;

type
  // The Rust SpreadMode. Pdf4D adds Decal in the shader unit.
  TTsSpreadMode = (Pad, Reflect, &Repeat);

  // PixmapRef: premultiplied RGBA bytes of Width * Height pixels, stride Width * 4. The data holds at least that many bytes.
  TTsPixmapRef = record
    Data: TBytes;
    Width: Cardinal;
    Height: Cardinal;

    // PixmapRef::from_bytes: a zero size, a width above i32::MAX / 4 or too few bytes give False
    class function TryFromBytes(const Data: TBytes; const Width, Height: Cardinal; out Pixmap: TTsPixmapRef): Boolean; static;

    // The pixel at Index, in the order of the bytes. False when the data does not hold the pixel.
    function TryReadPixel(const Index: Int64; out R, G, B, A: Byte): Boolean;
  end;

  // SubPixmapMut: a region of a parent pixmap. Data is the whole data of the parent, Offset the byte offset where the region starts, so
  // that the pixel (X, Y) of the region is the pixel Offset div 4 + RealWidth * Y + X of Data.
  TTsSubPixmapMut = record
    Data: TBytes;
    Offset: NativeInt;
    Width: Cardinal;
    Height: Cardinal;
    RealWidth: NativeUInt;

    // as_subpixmap: the region is the whole pixmap
    class function Whole(const Data: TBytes; const Width, Height: Cardinal): TTsSubPixmapMut; static;

    // offset(): the index, in pixels from the start of Data, of the pixel (DX, DY) of the region
    function PixelIndex(const DX, DY: Int64): Int64;

    // True when Data holds the pixels from the first pixel of the region up to Right pixels in each of the Bottom rows
    function HoldsRegion(const Right, Bottom: Cardinal): Boolean;
  end;

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

    // Context::default(): the transform is the identity, everything else zero
    class function New: TTsPipelineContext; static;
  end;

  PTsPipelineContext = ^TTsPipelineContext;
  PTsAAMaskCtx = ^TTsAAMaskCtx;
  PTsMaskCtx = ^TTsMaskCtx;
  PTsPixmapRef = ^TTsPixmapRef;
  PTsSubPixmapMut = ^TTsSubPixmapMut;

implementation

const
  BytesPerPixel = 4;
  // i32::MAX / 4: the largest width a pixmap can have
  MaxPixmapWidth: Cardinal = 536870911;

{ TTsPixmapRef }

class function TTsPixmapRef.TryFromBytes(const Data: TBytes; const Width, Height: Cardinal; out Pixmap: TTsPixmapRef): Boolean;
begin
  Pixmap := Default(TTsPixmapRef);

  if (Width = 0) or (Height = 0) or (Width > MaxPixmapWidth) then
  begin
    Exit(False);
  end;

  if Int64(Length(Data)) < Int64(Width) * Int64(Height) * BytesPerPixel then
  begin
    Exit(False);
  end;

  Pixmap.Data := Data;
  Pixmap.Width := Width;
  Pixmap.Height := Height;
  Result := True;
end;

function TTsPixmapRef.TryReadPixel(const Index: Int64; out R, G, B, A: Byte): Boolean;
begin
  R := 0;
  G := 0;
  B := 0;
  A := 0;

  if (Index < 0) or ((Index + 1) * BytesPerPixel > Length(Data)) then
  begin
    Exit(False);
  end;

  const Start = Index * BytesPerPixel;
  R := Data[Start];
  G := Data[Start + 1];
  B := Data[Start + 2];
  A := Data[Start + 3];
  Result := True;
end;

{ TTsSubPixmapMut }

class function TTsSubPixmapMut.Whole(const Data: TBytes; const Width, Height: Cardinal): TTsSubPixmapMut;
begin
  Result.Data := Data;
  Result.Offset := 0;
  Result.Width := Width;
  Result.Height := Height;
  Result.RealWidth := Width;
end;

function TTsSubPixmapMut.PixelIndex(const DX, DY: Int64): Int64;
begin
  Result := Offset div BytesPerPixel + Int64(RealWidth) * DY + DX;
end;

function TTsSubPixmapMut.HoldsRegion(const Right, Bottom: Cardinal): Boolean;
begin
  if (Offset < 0) or (Right = 0) or (Bottom = 0) then
  begin
    Exit(False);
  end;

  const LastPixel = PixelIndex(Int64(Right) - 1, Int64(Bottom) - 1);
  Result := ((LastPixel + 1) * BytesPerPixel <= Length(Data));
end;

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
