// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: tiny-skia v0.12.0 src/pipeline/mod.rs
// Copyright (c) 2016 Google Inc., (c) 2020 Yevhenii Reizner. BSD-3-Clause, see licenses/tiny-skia-BSD-3-Clause.txt.
unit Pdf4D.Render.Native.Pipeline;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.Transform,
  Pdf4D.Render.Native.Color,
  Pdf4D.Render.Native.Stage,
  Pdf4D.Render.Native.Pipeline.Context,
  Pdf4D.Render.Native.Pipeline.Highp;

// A raster pipeline: a list of stages that share one context. The builder compiles the list into the functions of the high precision
// pipeline (the low precision pipeline follows in Pdf4D.Render.Native.Pipeline.Lowp) and the pipeline runs them over a rect.
//
// The Rust code panics where a run would leave the pixels of the destination or where a stage is pushed that the pipeline does not have:
// a run that does not fit draws nothing, and pushing a stage that is not ported, or more than MaxStages stages, is a programming error
// that raises EInvalidOpException; input cannot reach it.

type
  TTsRasterPipeline = record
  private
    FFunctions: TTsHighpStageFunctions;
    FTailFunctions: TTsHighpStageFunctions;

    function FitsPixmaps(const Rect: TTsScreenIntRect; const PixmapSrc: TTsPixmapRef; const PixmapDst: TTsSubPixmapMut): Boolean;

  public
    Ctx: TTsPipelineContext;

    // The pipeline without stages draws nothing
    procedure Run(const Rect: TTsScreenIntRect; const AAMaskCtx: TTsAAMaskCtx; const MaskCtx: TTsMaskCtx; const PixmapSrc: TTsPixmapRef;
                  var PixmapDst: TTsSubPixmapMut);
  end;

  TTsRasterPipelineBuilder = record
  private
    FStages: array[0..MaxStages - 1] of TTsStage;
    FStageCount: Integer;
    FForceHqPipeline: Boolean;

  public
    Ctx: TTsPipelineContext;

    class function New: TTsRasterPipelineBuilder; static;

    procedure SetForceHqPipeline(const Hq: Boolean);
    procedure Push(const Stage: TTsStage);

    // The transform is skipped when it is the identity or not finite
    procedure PushTransform(const Ts: TTsTransform);
    procedure PushUniformColor(const C: TTsPremultipliedColor);
    function Compile: TTsRasterPipeline;

    property StageCount: Integer read FStageCount;
  end;

implementation

uses
  System.Math,
  Pdf4D.Render.Native.Scalar;

const
  Scale255: Single = 255;
  Half: Single = 0.5;

// `(c * 255.0 + 0.5) as u16`: every step is an f32, the cast saturates
function ColorToLane(const Channel: Single): Word;
begin
  const Scaled: Single = Channel * Scale255;
  const Rounded: Single = Scaled + Half;
  const Saturated = TTsScalar.SaturateToInt32(Rounded);

  Result := Word(Min(Max(Saturated, 0), High(Word)));
end;

{ TTsRasterPipelineBuilder }

class function TTsRasterPipelineBuilder.New: TTsRasterPipelineBuilder;
begin
  Result := Default(TTsRasterPipelineBuilder);
  Result.Ctx := TTsPipelineContext.New;
end;

procedure TTsRasterPipelineBuilder.SetForceHqPipeline(const Hq: Boolean);
begin
  FForceHqPipeline := Hq;
end;

procedure TTsRasterPipelineBuilder.Push(const Stage: TTsStage);
begin
  if FStageCount >= MaxStages then
  begin
    raise EInvalidOpException.CreateFmt('A raster pipeline has at most %d stages', [MaxStages]);
  end;

  if not Assigned(TTsHighpStages.Table[Stage]) then
  begin
    raise EInvalidOpException.CreateFmt('The pipeline has no implementation of stage %d', [Ord(Stage)]);
  end;

  FStages[FStageCount] := Stage;
  Inc(FStageCount);
end;

procedure TTsRasterPipelineBuilder.PushTransform(const Ts: TTsTransform);
begin
  if Ts.IsFinite and not Ts.IsIdentity then
  begin
    Push(TTsStage.Transform);
    Ctx.Transform := Ts;
  end;
end;

procedure TTsRasterPipelineBuilder.PushUniformColor(const C: TTsPremultipliedColor);
begin
  Ctx.UniformColor.R := C.Red;
  Ctx.UniformColor.G := C.Green;
  Ctx.UniformColor.B := C.Blue;
  Ctx.UniformColor.A := C.Alpha;
  Ctx.UniformColor.Rgba[0] := ColorToLane(C.Red);
  Ctx.UniformColor.Rgba[1] := ColorToLane(C.Green);
  Ctx.UniformColor.Rgba[2] := ColorToLane(C.Blue);
  Ctx.UniformColor.Rgba[3] := ColorToLane(C.Alpha);

  Push(TTsStage.UniformColor);
end;

function TTsRasterPipelineBuilder.Compile: TTsRasterPipeline;
begin
  Result := Default(TTsRasterPipeline);
  Result.Ctx := TTsPipelineContext.New;

  if FStageCount = 0 then
  begin
    Exit;
  end;

  Result.Ctx := Ctx;
  for var I := 0 to FStageCount - 1 do
  begin
    Result.FFunctions.Items[I] := TTsHighpStages.Table[FStages[I]];
    // Two "programs": one for the full runs and one for the tail runs. The only difference is the load and the store functions.
    Result.FTailFunctions.Items[I] := TTsHighpStages.TailTable[FStages[I]];
  end;

  Result.FFunctions.Items[FStageCount] := TTsHighpStages.JustReturn();
  Result.FTailFunctions.Items[FStageCount] := TTsHighpStages.JustReturn();
  Result.FFunctions.Count := FStageCount + 1;
  Result.FTailFunctions.Count := FStageCount + 1;
end;

{ TTsRasterPipeline }

function TTsRasterPipeline.FitsPixmaps(const Rect: TTsScreenIntRect; const PixmapSrc: TTsPixmapRef;
  const PixmapDst: TTsSubPixmapMut): Boolean;
begin
  const SourceBytes = Int64(PixmapSrc.Width) * Int64(PixmapSrc.Height) * 4;
  const HoldsSource = (SourceBytes <= Length(PixmapSrc.Data));

  Result := (HoldsSource and PixmapDst.HoldsRegion(Rect.Right, Rect.Bottom));
end;

procedure TTsRasterPipeline.Run(const Rect: TTsScreenIntRect; const AAMaskCtx: TTsAAMaskCtx; const MaskCtx: TTsMaskCtx;
  const PixmapSrc: TTsPixmapRef; var PixmapDst: TTsSubPixmapMut);
begin
  const HasStages = (FFunctions.Count > 0);
  if (not HasStages) or (not FitsPixmaps(Rect, PixmapSrc, PixmapDst)) then
  begin
    Exit;
  end;

  TTsHighpStages.Start(FFunctions, FTailFunctions, Rect, AAMaskCtx, MaskCtx, Ctx, PixmapSrc, PixmapDst);
end;

end.
