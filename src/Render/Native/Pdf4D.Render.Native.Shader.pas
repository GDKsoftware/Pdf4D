// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: tiny-skia v0.12.0 src/shaders/mod.rs (solid color and pattern only), src/shaders/pattern.rs, src/painter.rs (Paint)
// The Decal spread mode is an addition of Pdf4D: see Pdf4D.Render.Native.Pipeline.Highp for its stages.
// Copyright (c) 2006 The Android Open Source Project, (c) 2020 Yevhenii Reizner. BSD-3-Clause, see licenses/tiny-skia-BSD-3-Clause.txt.
unit Pdf4D.Render.Native.Shader;

{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

uses
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Transform,
  Pdf4D.Render.Native.Color,
  Pdf4D.Render.Native.BlendMode,
  Pdf4D.Render.Native.Pixmap,
  Pdf4D.Render.Native.Pipeline.Context,
  Pdf4D.Render.Native.Pipeline;

// The contract has only solid and bitmap paints, so the gradients are not ported and only ColorSpace::Linear exists, which adds no stage.
// The spread mode lives in Pdf4D.Render.Native.Pipeline.Context, where the sampler context needs it.

type
  // Controls how much filtering to be done when transforming images
  TTsFilterQuality = (
    // Nearest-neighbor. Low quality, but fastest.
    Nearest,
    Bilinear,
    // High quality, but slow
    Bicubic
  );

  TTsShaderKind = (SolidColor, Pattern);

  // A pattern shader; essentially a SkImageShader
  TTsPattern = record
    Pixmap: TTsPixmapRef;
    SpreadMode: TTsSpreadMode;
    Quality: TTsFilterQuality;
    Opacity: TTsNormalizedF32;
    Transform: TTsTransform;
  end;

  // A shader specifies the source color for what is being drawn
  TTsShader = record
    Kind: TTsShaderKind;
    Color: TTsColor;
    Pattern: TTsPattern;

    class function NewSolidColor(const Color: TTsColor): TTsShader; static;

    // The opacity is clamped to the 0..=1 range
    class function NewPattern(const Pixmap: TTsPixmapRef; const SpreadMode: TTsSpreadMode; const Quality: TTsFilterQuality;
                              const Opacity: Single; const Transform: TTsTransform): TTsShader; static;

    // Checks if the shader is guaranteed to produce only opaque colors
    function IsOpaque: Boolean;

    // False means that nothing is drawn: a pattern whose transform cannot be inverted
    function TryPushStages(var Builder: TTsRasterPipelineBuilder): Boolean;

    // Transforms the shader
    procedure ApplyTransform(const Ts: TTsTransform);

    // Shifts the opacity of the shader; the opacity is clamped to the 0..=1 range
    procedure ApplyOpacity(const Opacity: Single);
  end;

  // Controls how a pixmap should be blended; like TTsPaint, but for a pixmap
  TTsPixmapPaint = record
    // In 0..=1
    Opacity: Single;
    BlendMode: TTsBlendMode;
    Quality: TTsFilterQuality;

    // Opacity 1, SourceOver, Nearest
    class function Default: TTsPixmapPaint; static;
  end;

  // Controls how a shape should be painted
  TTsPaint = record
    Shader: TTsShader;
    BlendMode: TTsBlendMode;
    AntiAlias: Boolean;
    // Forces the high precision pipeline
    ForceHqPipeline: Boolean;

    // A black solid color, SourceOver, anti-aliased, no forced pipeline
    class function Default: TTsPaint; static;

    function IsSolidColor: Boolean;
  end;

implementation

uses
  System.SysUtils,
  Pdf4D.Render.Native.Stage;

const
  OneSingle: Single = 1;

// pattern.rs push_stages. Without a Decal the limits are used by Repeat and Reflect, with a Decal also by DecalXY.
function PushPatternStages(const Pattern: TTsPattern; var Builder: TTsRasterPipelineBuilder): Boolean;
begin
  var Ts: TTsTransform;
  if not Pattern.Transform.TryInvert(Ts) then
  begin
    // failed to invert a pattern transform: nothing will be rendered
    Exit(False);
  end;

  Builder.Push(TTsStage.SeedShader);
  Builder.PushTransform(Ts);

  const IsDecal = (Pattern.SpreadMode = TTsSpreadMode.Decal);
  if IsDecal then
  begin
    Builder.Push(TTsStage.DecalXY);
  end;

  var Quality := Pattern.Quality;
  if Ts.IsIdentity or Ts.IsTranslate then
  begin
    Quality := TTsFilterQuality.Nearest;
  end;

  if Quality = TTsFilterQuality.Bilinear then
  begin
    // When the matrix is just an integer translate, bilerp == nearest neighbor
    const IsIntegerTranslate = (Ts.IsTranslate and (Ts.TX = TTsScalar.TruncF(Ts.TX)) and (Ts.TY = TTsScalar.TruncF(Ts.TY)));
    if IsIntegerTranslate then
    begin
      Quality := TTsFilterQuality.Nearest;
    end;
  end;

  const Width: Single = Pattern.Pixmap.Width;
  const Height: Single = Pattern.Pixmap.Height;
  const InvWidth: Single = OneSingle / Width;
  const InvHeight: Single = OneSingle / Height;

  Builder.Ctx.LimitX.Scale := Width;
  Builder.Ctx.LimitX.InvScale := InvWidth;
  Builder.Ctx.LimitY.Scale := Height;
  Builder.Ctx.LimitY.InvScale := InvHeight;

  case Quality of
    TTsFilterQuality.Nearest:
      begin
        case Pattern.SpreadMode of
          // The gather stage clamps for us; a Decal is checked after the sampling
          TTsSpreadMode.Pad, TTsSpreadMode.Decal : ;
          TTsSpreadMode.&Repeat                  : Builder.Push(TTsStage.&Repeat);
          TTsSpreadMode.Reflect                  : Builder.Push(TTsStage.Reflect);
        else
          raise EInvalidOpException.CreateFmt('Unsupported spread mode: %d', [Ord(Pattern.SpreadMode)]);
        end;

        Builder.Push(TTsStage.Gather);
      end;

    TTsFilterQuality.Bilinear:
      begin
        Builder.Ctx.Sampler.SpreadMode := Pattern.SpreadMode;
        Builder.Ctx.Sampler.InvWidth := InvWidth;
        Builder.Ctx.Sampler.InvHeight := InvHeight;
        Builder.Push(TTsStage.Bilinear);
      end;

    TTsFilterQuality.Bicubic:
      begin
        Builder.Ctx.Sampler.SpreadMode := Pattern.SpreadMode;
        Builder.Ctx.Sampler.InvWidth := InvWidth;
        Builder.Ctx.Sampler.InvHeight := InvHeight;
        Builder.Push(TTsStage.Bicubic);

        // Bicubic filtering naturally produces out of range values on both sides of [0,1]
        Builder.Push(TTsStage.Clamp0);
        Builder.Push(TTsStage.ClampA);
      end;
  else
    raise EInvalidOpException.CreateFmt('Unsupported filter quality: %d', [Ord(Quality)]);
  end;

  if IsDecal then
  begin
    Builder.Push(TTsStage.CheckDecalMask);
  end;

  // Unlike Skia, we do not support global opacity and only Pattern allows it
  if Pattern.Opacity.Get <> OneSingle then
  begin
    Builder.Ctx.CurrentCoverage := Pattern.Opacity.Get;
    Builder.Push(TTsStage.Scale1Float);
  end;

  Result := True;
end;

{ TTsShader }

class function TTsShader.NewSolidColor(const Color: TTsColor): TTsShader;
begin
  Result := Default(TTsShader);
  Result.Kind := TTsShaderKind.SolidColor;
  Result.Color := Color;
end;

class function TTsShader.NewPattern(const Pixmap: TTsPixmapRef; const SpreadMode: TTsSpreadMode; const Quality: TTsFilterQuality;
  const Opacity: Single; const Transform: TTsTransform): TTsShader;
begin
  Result := Default(TTsShader);
  Result.Kind := TTsShaderKind.Pattern;
  Result.Pattern.Pixmap := Pixmap;
  Result.Pattern.SpreadMode := SpreadMode;
  Result.Pattern.Quality := Quality;
  Result.Pattern.Opacity := TTsNormalizedF32.CreateClamped(Opacity);
  Result.Pattern.Transform := Transform;
end;

function TTsShader.IsOpaque: Boolean;
begin
  case Kind of
    TTsShaderKind.SolidColor : Result := Color.IsOpaque;
    TTsShaderKind.Pattern    : Result := False;
  else
    raise EInvalidOpException.CreateFmt('Unsupported shader kind: %d', [Ord(Kind)]);
  end;
end;

function TTsShader.TryPushStages(var Builder: TTsRasterPipelineBuilder): Boolean;
begin
  case Kind of
    TTsShaderKind.SolidColor:
      begin
        Builder.PushUniformColor(Color.Premultiply);
        Result := True;
      end;

    TTsShaderKind.Pattern:
      Result := PushPatternStages(Pattern, Builder);
  else
    raise EInvalidOpException.CreateFmt('Unsupported shader kind: %d', [Ord(Kind)]);
  end;
end;

procedure TTsShader.ApplyTransform(const Ts: TTsTransform);
begin
  if Kind = TTsShaderKind.Pattern then
  begin
    Pattern.Transform := Pattern.Transform.PostConcat(Ts);
  end;
end;

procedure TTsShader.ApplyOpacity(const Opacity: Single);
begin
  case Kind of
    TTsShaderKind.SolidColor:
      Color.ApplyOpacity(Opacity);

    TTsShaderKind.Pattern:
      begin
        const Bounded = TTsScalar.Bound(Opacity, 0, 1);
        const Product: Single = Pattern.Opacity.Get * Bounded;
        Pattern.Opacity := TTsNormalizedF32.CreateClamped(Product);
      end;
  else
    raise EInvalidOpException.CreateFmt('Unsupported shader kind: %d', [Ord(Kind)]);
  end;
end;

{ TTsPixmapPaint }

class function TTsPixmapPaint.Default: TTsPixmapPaint;
begin
  Result.Opacity := 1;
  Result.BlendMode := TTsBlendMode.SourceOver;
  Result.Quality := TTsFilterQuality.Nearest;
end;

{ TTsPaint }

class function TTsPaint.Default: TTsPaint;
begin
  Result.Shader := TTsShader.NewSolidColor(TTsColor.Black);
  Result.BlendMode := TTsBlendMode.SourceOver;
  Result.AntiAlias := True;
  Result.ForceHqPipeline := False;
end;

function TTsPaint.IsSolidColor: Boolean;
begin
  Result := (Shader.Kind = TTsShaderKind.SolidColor);
end;

end.
