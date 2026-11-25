// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: tiny-skia v0.12.0 src/pipeline/blitter.rs
// Copyright (c) 2016 Google Inc., (c) 2020 Yevhenii Reizner. BSD-3-Clause, see licenses/tiny-skia-BSD-3-Clause.txt.
unit Pdf4D.Render.Native.Pipeline.Blitter;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Math,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.Color,
  Pdf4D.Render.Native.BlendMode,
  Pdf4D.Render.Native.AlphaRuns,
  Pdf4D.Render.Native.Blitter,
  Pdf4D.Render.Native.Pixmap,
  Pdf4D.Render.Native.Mask,
  Pdf4D.Render.Native.Shader,
  Pdf4D.Render.Native.Pipeline;

// The blitter that writes the pixels of a paint through raster pipelines. The Rust blitter borrows the pixmap, the mask and the source
// pixmap; the records here hold the same arrays, so a draw changes the pixels of the caller.
//
// The Rust code indexes the pixmap with every coordinate that the scan converters give. Here a rect that leaves the pixmap is clipped to
// it first: the vertical hairline may blit at x = clip.right, and a pipeline would otherwise write into the next row.

type
  TTsRasterPipelineBlitter = class(TTsBlitter)
  private
    FMask: TTsSubMaskRef;
    FPixmapSrc: TTsPixmapRef;
    FPixmap: TTsSubPixmapMut;
    FHasMemset2dColor: Boolean;
    FMemset2dColor: TTsPremultipliedColorU8;
    FBlitAntiHPipeline: TTsRasterPipeline;
    FBlitRectPipeline: TTsRasterPipeline;
    FBlitMaskPipeline: TTsRasterPipeline;
    FIsMask: Boolean;

    function TryClipToPixmap(const Rect: TTsScreenIntRect; out Clipped: TTsScreenIntRect): Boolean;

    class function TryCompileAntiH(const Paint: TTsPaint; const BlendMode: TTsBlendMode; const HasMask: Boolean;
                                   out Pipeline: TTsRasterPipeline): Boolean; static;
    class function TryCompileRect(const Paint: TTsPaint; const BlendMode: TTsBlendMode; const HasMask: Boolean;
                                  out Pipeline: TTsRasterPipeline): Boolean; static;
    class function TryCompileMask(const Paint: TTsPaint; const BlendMode: TTsBlendMode; const HasMask: Boolean;
                                  out Pipeline: TTsRasterPipeline): Boolean; static;

  public
    // RasterPipelineBlitter::new. The mask is optional (an unassigned TTsSubMaskRef is None) and must have the size of the pixmap. False
    // means that nothing is drawn: a mismatching mask, a paint that changes nothing or a shader that does not draw.
    class function TryCreate(const Paint: TTsPaint; const Mask: TTsSubMaskRef; const Pixmap: TTsSubPixmapMut;
                             out Blitter: TTsRasterPipelineBlitter): Boolean; static;

    // RasterPipelineBlitter::new_mask: a blitter that draws coverage in an A8 pixmap
    class function TryCreateForMask(const Pixmap: TTsSubPixmapMut; out Blitter: TTsRasterPipelineBlitter): Boolean; static;

    procedure BlitH(const X, Y, Width: Cardinal); override;
    procedure BlitAntiH(const X, Y: Cardinal; const Antialias: TArray<Byte>; const Runs: TArray<TTsAlphaRun>; const Offset: Integer); override;
    procedure BlitV(const X, Y, Height: Cardinal; const Alpha: Byte); override;
    procedure BlitAntiH2(const X, Y: Cardinal; const Alpha0, Alpha1: Byte); override;
    procedure BlitAntiV2(const X, Y: Cardinal; const Alpha0, Alpha1: Byte); override;
    procedure BlitRect(const Rect: TTsScreenIntRect); override;
    procedure BlitMask(const Mask: TTsBlitterMask; const Clip: TTsScreenIntRect); override;
  end;

implementation

uses
  Pdf4D.Render.Native.Stage,
  Pdf4D.Render.Native.Pipeline.Context;

const
  // 1.0 / 255.0
  Reciprocal255: Single = 1 / 255;

{ TTsRasterPipelineBlitter }

class function TTsRasterPipelineBlitter.TryCompileAntiH(const Paint: TTsPaint; const BlendMode: TTsBlendMode; const HasMask: Boolean;
  out Pipeline: TTsRasterPipeline): Boolean;
begin
  Pipeline := Default(TTsRasterPipeline);

  var Builder := TTsRasterPipelineBuilder.New;
  Builder.SetForceHqPipeline(Paint.ForceHqPipeline);
  var Shader := Paint.Shader;
  if not Shader.TryPushStages(Builder) then
  begin
    Exit(False);
  end;

  if HasMask then
  begin
    Builder.Push(TTsStage.MaskU8);
  end;

  var BlendStage: TTsStage;
  const HasBlendStage = BlendMode.TryToStage(BlendStage);

  if BlendMode.ShouldPreScaleCoverage then
  begin
    Builder.Push(TTsStage.Scale1Float);
    Builder.Push(TTsStage.LoadDestination);
    if HasBlendStage then
    begin
      Builder.Push(BlendStage);
    end;
  end
  else
  begin
    Builder.Push(TTsStage.LoadDestination);
    if HasBlendStage then
    begin
      Builder.Push(BlendStage);
    end;

    Builder.Push(TTsStage.Lerp1Float);
  end;

  Builder.Push(TTsStage.Store);

  Pipeline := Builder.Compile;
  Result := True;
end;

class function TTsRasterPipelineBlitter.TryCompileRect(const Paint: TTsPaint; const BlendMode: TTsBlendMode; const HasMask: Boolean;
  out Pipeline: TTsRasterPipeline): Boolean;
begin
  Pipeline := Default(TTsRasterPipeline);

  var Builder := TTsRasterPipelineBuilder.New;
  Builder.SetForceHqPipeline(Paint.ForceHqPipeline);
  var Shader := Paint.Shader;
  if not Shader.TryPushStages(Builder) then
  begin
    Exit(False);
  end;

  if HasMask then
  begin
    Builder.Push(TTsStage.MaskU8);
  end;

  if (BlendMode = TTsBlendMode.SourceOver) and (not HasMask) then
  begin
    // TODO of tiny-skia: ignore when dither_rate is non-zero
    Builder.Push(TTsStage.SourceOverRgba);
  end
  else
  begin
    if BlendMode <> TTsBlendMode.Source then
    begin
      Builder.Push(TTsStage.LoadDestination);

      var BlendStage: TTsStage;
      if BlendMode.TryToStage(BlendStage) then
      begin
        Builder.Push(BlendStage);
      end;
    end;

    Builder.Push(TTsStage.Store);
  end;

  Pipeline := Builder.Compile;
  Result := True;
end;

class function TTsRasterPipelineBlitter.TryCompileMask(const Paint: TTsPaint; const BlendMode: TTsBlendMode; const HasMask: Boolean;
  out Pipeline: TTsRasterPipeline): Boolean;
begin
  Pipeline := Default(TTsRasterPipeline);

  var Builder := TTsRasterPipelineBuilder.New;
  Builder.SetForceHqPipeline(Paint.ForceHqPipeline);
  var Shader := Paint.Shader;
  if not Shader.TryPushStages(Builder) then
  begin
    Exit(False);
  end;

  if HasMask then
  begin
    Builder.Push(TTsStage.MaskU8);
  end;

  var BlendStage: TTsStage;
  const HasBlendStage = BlendMode.TryToStage(BlendStage);

  if BlendMode.ShouldPreScaleCoverage then
  begin
    Builder.Push(TTsStage.ScaleU8);
    Builder.Push(TTsStage.LoadDestination);
    if HasBlendStage then
    begin
      Builder.Push(BlendStage);
    end;
  end
  else
  begin
    Builder.Push(TTsStage.LoadDestination);
    if HasBlendStage then
    begin
      Builder.Push(BlendStage);
    end;

    Builder.Push(TTsStage.LerpU8);
  end;

  Builder.Push(TTsStage.Store);

  Pipeline := Builder.Compile;
  Result := True;
end;

class function TTsRasterPipelineBlitter.TryCreate(const Paint: TTsPaint; const Mask: TTsSubMaskRef; const Pixmap: TTsSubPixmapMut;
  out Blitter: TTsRasterPipelineBlitter): Boolean;
begin
  Blitter := nil;

  // Pdf4D: the memset and the pipelines write without a check, so the data must hold the whole region
  if not Pixmap.HoldsRegion(Pixmap.Width, Pixmap.Height) then
  begin
    Exit(False);
  end;

  const HasMask = Mask.IsAssigned;

  // Make sure that `mask` has the same size as `pixmap`
  if HasMask and ((Mask.Width <> Pixmap.Width) or (Mask.Height <> Pixmap.Height)) then
  begin
    Exit(False);
  end;

  // Fast-reject. This is basically SkInterpretXfermode().
  if Paint.BlendMode = TTsBlendMode.Destination then
  begin
    // `Destination` keeps the pixmap unchanged. Nothing to do here.
    Exit(False);
  end;

  if (Paint.BlendMode = TTsBlendMode.DestinationIn) and Paint.Shader.IsOpaque and Paint.IsSolidColor then
  begin
    Exit(False);
  end;

  // We can strength-reduce SourceOver into Source when opaque
  var BlendMode := Paint.BlendMode;
  if Paint.Shader.IsOpaque and (BlendMode = TTsBlendMode.SourceOver) and (not HasMask) then
  begin
    BlendMode := TTsBlendMode.Source;
  end;

  // When we're drawing a constant color in Source mode, we can sometimes just memset. Unlike Skia, our shader cannot be constant, so there
  // is no need to run a raster pipeline to get the color of the shader.
  var HasMemsetColor := False;
  var MemsetColor := TTsPremultipliedColorU8.Transparent;
  if Paint.IsSolidColor and (BlendMode = TTsBlendMode.Source) and (not HasMask) then
  begin
    HasMemsetColor := True;
    MemsetColor := Paint.Shader.Color.Premultiply.ToColorU8;
  end;

  // Clear is just a transparent color memset
  if (BlendMode = TTsBlendMode.Clear) and (not Paint.AntiAlias) and (not HasMask) then
  begin
    BlendMode := TTsBlendMode.Source;
    HasMemsetColor := True;
    MemsetColor := TTsPremultipliedColorU8.Transparent;
  end;

  var AntiHPipeline: TTsRasterPipeline;
  var RectPipeline: TTsRasterPipeline;
  var MaskPipeline: TTsRasterPipeline;
  if not (TryCompileAntiH(Paint, BlendMode, HasMask, AntiHPipeline) and
          TryCompileRect(Paint, BlendMode, HasMask, RectPipeline) and
          TryCompileMask(Paint, BlendMode, HasMask, MaskPipeline)) then
  begin
    Exit(False);
  end;

  Blitter := TTsRasterPipelineBlitter.Create;
  Blitter.FMask := Mask;
  Blitter.FPixmap := Pixmap;
  Blitter.FHasMemset2dColor := HasMemsetColor;
  Blitter.FMemset2dColor := MemsetColor;
  Blitter.FBlitAntiHPipeline := AntiHPipeline;
  Blitter.FBlitRectPipeline := RectPipeline;
  Blitter.FBlitMaskPipeline := MaskPipeline;
  Blitter.FIsMask := False;

  if Paint.Shader.Kind = TTsShaderKind.Pattern then
  begin
    Blitter.FPixmapSrc := Paint.Shader.Pattern.Pixmap;
  end
  else
  begin
    // Just a dummy one
    TTsPixmapRef.TryFromBytes([0, 0, 0, 0], 1, 1, Blitter.FPixmapSrc);
  end;

  Result := True;
end;

class function TTsRasterPipelineBlitter.TryCreateForMask(const Pixmap: TTsSubPixmapMut; out Blitter: TTsRasterPipelineBlitter): Boolean;
begin
  Blitter := nil;

  // Pdf4D: the data of the A8 pixmap must hold the whole region
  if not Pixmap.HoldsMaskRegion(Pixmap.Width, Pixmap.Height) then
  begin
    Exit(False);
  end;

  const Color = TTsColor.White.Premultiply;

  var AntiHBuilder := TTsRasterPipelineBuilder.New;
  AntiHBuilder.PushUniformColor(Color);
  AntiHBuilder.Push(TTsStage.LoadDestinationU8);
  AntiHBuilder.Push(TTsStage.Lerp1Float);
  AntiHBuilder.Push(TTsStage.StoreU8);

  var RectBuilder := TTsRasterPipelineBuilder.New;
  RectBuilder.PushUniformColor(Color);
  RectBuilder.Push(TTsStage.StoreU8);

  var MaskBuilder := TTsRasterPipelineBuilder.New;
  MaskBuilder.PushUniformColor(Color);
  MaskBuilder.Push(TTsStage.LoadDestinationU8);
  MaskBuilder.Push(TTsStage.LerpU8);
  MaskBuilder.Push(TTsStage.StoreU8);

  Blitter := TTsRasterPipelineBlitter.Create;
  Blitter.FPixmap := Pixmap;
  Blitter.FHasMemset2dColor := True;
  Blitter.FMemset2dColor := Color.ToColorU8;
  Blitter.FBlitAntiHPipeline := AntiHBuilder.Compile;
  Blitter.FBlitRectPipeline := RectBuilder.Compile;
  Blitter.FBlitMaskPipeline := MaskBuilder.Compile;
  Blitter.FIsMask := True;
  TTsPixmapRef.TryFromBytes([0, 0, 0, 0], 1, 1, Blitter.FPixmapSrc);

  Result := True;
end;

function TTsRasterPipelineBlitter.TryClipToPixmap(const Rect: TTsScreenIntRect; out Clipped: TTsScreenIntRect): Boolean;
begin
  Clipped := Rect;

  const InsideX = (Rect.X < FPixmap.Width);
  const InsideY = (Rect.Y < FPixmap.Height);
  if (not InsideX) or (not InsideY) then
  begin
    Exit(False);
  end;

  const Right = Int64(Rect.X) + Rect.Width;
  const Bottom = Int64(Rect.Y) + Rect.Height;
  const FitsX = (Right <= FPixmap.Width);
  const FitsY = (Bottom <= FPixmap.Height);
  if FitsX and FitsY then
  begin
    Exit(True);
  end;

  const ClippedWidth = Cardinal(Int64(FPixmap.Width) - Rect.X);
  const ClippedHeight = Cardinal(Int64(FPixmap.Height) - Rect.Y);
  Result := TTsScreenIntRect.TryFromXYWH(Rect.X, Rect.Y, Min(Rect.Width, ClippedWidth), Min(Rect.Height, ClippedHeight), Clipped);
end;

procedure TTsRasterPipelineBlitter.BlitH(const X, Y, Width: Cardinal);
begin
  var Rect: TTsScreenIntRect;
  if TTsScreenIntRect.TryFromXYWH(X, Y, Width, 1, Rect) then
  begin
    BlitRect(Rect);
  end;
end;

procedure TTsRasterPipelineBlitter.BlitAntiH(const X, Y: Cardinal; const Antialias: TArray<Byte>; const Runs: TArray<TTsAlphaRun>;
  const Offset: Integer);
begin
  const MaskCtx = FMask.MaskCtx;

  var RunX := X;
  var AAOffset := Offset;
  var RunOffset := Offset;
  while (RunOffset < Length(Runs)) and (Runs[RunOffset] <> 0) and (AAOffset < Length(Antialias)) do
  begin
    const RunLength = Runs[RunOffset];
    const Width = Cardinal(RunLength);

    const Alpha = Antialias[AAOffset];
    if Alpha = AlphaU8Opaque then
    begin
      BlitH(RunX, Y, Width);
    end
    else if Alpha <> AlphaU8Transparent then
    begin
      const Coverage: Single = Alpha;
      FBlitAntiHPipeline.Ctx.CurrentCoverage := Coverage * Reciprocal255;

      var Rect: TTsScreenIntRect;
      var Clipped: TTsScreenIntRect;
      if TTsScreenIntRect.TryFromXYWH(RunX, Y, Width, 1, Rect) and TryClipToPixmap(Rect, Clipped) then
      begin
        FBlitAntiHPipeline.Run(Clipped, Default(TTsAAMaskCtx), MaskCtx, FPixmapSrc, FPixmap);
      end;
    end;

    Inc(RunX, Width);
    Inc(RunOffset, RunLength);
    Inc(AAOffset, RunLength);
  end;
end;

procedure TTsRasterPipelineBlitter.BlitV(const X, Y, Height: Cardinal; const Alpha: Byte);
begin
  var Bounds: TTsScreenIntRect;
  if not TTsScreenIntRect.TryFromXYWH(X, Y, 1, Height, Bounds) then
  begin
    Exit;
  end;

  var Mask := Default(TTsBlitterMask);
  Mask.Image[0] := Alpha;
  Mask.Image[1] := Alpha;
  Mask.Bounds := Bounds;
  // So we reuse the 1 "row" for all of height
  Mask.RowBytes := 0;

  BlitMask(Mask, Bounds);
end;

procedure TTsRasterPipelineBlitter.BlitAntiH2(const X, Y: Cardinal; const Alpha0, Alpha1: Byte);
begin
  var Bounds: TTsScreenIntRect;
  if not TTsScreenIntRect.TryFromXYWH(X, Y, 2, 1, Bounds) then
  begin
    Exit;
  end;

  var Mask := Default(TTsBlitterMask);
  Mask.Image[0] := Alpha0;
  Mask.Image[1] := Alpha1;
  Mask.Bounds := Bounds;
  Mask.RowBytes := 2;

  BlitMask(Mask, Bounds);
end;

procedure TTsRasterPipelineBlitter.BlitAntiV2(const X, Y: Cardinal; const Alpha0, Alpha1: Byte);
begin
  var Bounds: TTsScreenIntRect;
  if not TTsScreenIntRect.TryFromXYWH(X, Y, 1, 2, Bounds) then
  begin
    Exit;
  end;

  var Mask := Default(TTsBlitterMask);
  Mask.Image[0] := Alpha0;
  Mask.Image[1] := Alpha1;
  Mask.Bounds := Bounds;
  Mask.RowBytes := 1;

  BlitMask(Mask, Bounds);
end;

procedure TTsRasterPipelineBlitter.BlitRect(const Rect: TTsScreenIntRect);
begin
  var Clipped: TTsScreenIntRect;
  if not TryClipToPixmap(Rect, Clipped) then
  begin
    Exit;
  end;

  if FHasMemset2dColor then
  begin
    for var Row := 0 to Integer(Clipped.Height) - 1 do
    begin
      const RowY = Int64(Clipped.Y) + Row;
      if FIsMask then
      begin
        const Start = FPixmap.MaskIndex(Clipped.X, RowY);
        for var Column := 0 to Integer(Clipped.Width) - 1 do
        begin
          FPixmap.Data[Start + Column] := FMemset2dColor.Alpha;
        end;
      end
      else
      begin
        const Start = FPixmap.PixelIndex(Clipped.X, RowY) * 4;
        for var Column := 0 to Integer(Clipped.Width) - 1 do
        begin
          FPixmap.Data[Start + Column * 4] := FMemset2dColor.Red;
          FPixmap.Data[Start + Column * 4 + 1] := FMemset2dColor.Green;
          FPixmap.Data[Start + Column * 4 + 2] := FMemset2dColor.Blue;
          FPixmap.Data[Start + Column * 4 + 3] := FMemset2dColor.Alpha;
        end;
      end;
    end;

    Exit;
  end;

  FBlitRectPipeline.Run(Clipped, Default(TTsAAMaskCtx), FMask.MaskCtx, FPixmapSrc, FPixmap);
end;

procedure TTsRasterPipelineBlitter.BlitMask(const Mask: TTsBlitterMask; const Clip: TTsScreenIntRect);
begin
  var Clipped: TTsScreenIntRect;
  if not TryClipToPixmap(Clip, Clipped) then
  begin
    Exit;
  end;

  var AAMaskCtx := Default(TTsAAMaskCtx);
  AAMaskCtx.Pixels[0] := Mask.Image[0];
  AAMaskCtx.Pixels[1] := Mask.Image[1];
  AAMaskCtx.Stride := Mask.RowBytes;
  AAMaskCtx.Shift := Int64(Mask.Bounds.Left) + Int64(Mask.Bounds.Top) * Mask.RowBytes;

  FBlitMaskPipeline.Run(Clipped, AAMaskCtx, FMask.MaskCtx, FPixmapSrc, FPixmap);
end;

end.
