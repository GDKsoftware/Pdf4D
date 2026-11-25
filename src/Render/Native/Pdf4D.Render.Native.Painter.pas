// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: tiny-skia v0.12.0 src/painter.rs (the drawing methods of Pixmap and PixmapMut, treat_as_hairline, is_too_big_for_math, DrawTiler)
// and the drawing methods of src/mask.rs (fill_path, intersect_path)
// Copyright (c) 2006 The Android Open Source Project, (c) 2020 Yevhenii Reizner. BSD-3-Clause, see licenses/tiny-skia-BSD-3-Clause.txt.
unit Pdf4D.Render.Native.Painter;

{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.Transform,
  Pdf4D.Render.Native.Path,
  Pdf4D.Render.Native.Scan,
  Pdf4D.Render.Native.Pixmap,
  Pdf4D.Render.Native.Mask,
  Pdf4D.Render.Native.Shader,
  Pdf4D.Render.Native.Dash,
  Pdf4D.Render.Native.Stroker;

// The painter of tiny-skia: the methods of Pixmap that draw. They are static methods over a TTsPixmap here; the pixmap shares its data with
// the regions that the pipeline blitter writes, so a draw changes the pixels of the caller. A nil mask is the Rust `None`.
//
// The Rust log::warn! messages are dropped: the draw returns without a change. A Rust panic that input can reach is an early exit that draws
// nothing. The tiler splits a pixmap larger than 8191 pixels, because the scan converters use fixed point numbers that cannot hold more.
//
// The fill of a path on a mask (Mask::fill_path, Mask::intersect_path) is a record helper in this unit: the Mask unit cannot use the
// blitter, which uses the Mask unit.
//
// Must run inside TTsFloatMode, like the scan converters.

type
  // Splits the target pixmap into a list of tiles
  TTsDrawTiler = record
  public const
    // 8K is 1 too big, since 8K << supersample == 32768 which is too big for Fixed
    MaxDimensions = 8192 - 1;

  private
    FImageWidth: Cardinal;
    FImageHeight: Cardinal;
    FXOffset: Cardinal;
    FYOffset: Cardinal;

  public
    class function Required(const ImageWidth, ImageHeight: Cardinal): Boolean; static;

    // DrawTiler::new: False when the pixmap does not need tiles
    class function TryCreate(const ImageWidth, ImageHeight: Cardinal; out Tiler: TTsDrawTiler): Boolean; static;

    // Iterator::next: False when there is no tile left
    function TryNext(out Tile: TTsScreenIntRect): Boolean;
  end;

  TTsPainter = record
  private
    class function TreatAsHairline(const Paint: TTsPaint; const Stroke: TTsStroke; const Ts: TTsTransform;
                                   out Coverage: Single): Boolean; static;
    class procedure StrokeHairline(const Path: TTsPath; const Paint: TTsPaint; const LineCap: TTsLineCap; const Mask: TTsSubMaskRef;
                                   const Pixmap: TTsSubPixmapMut); static;
    class function SubMaskOf(const Mask: PTsMask): TTsSubMaskRef; static;
    class function SubMaskOfTile(const Mask: PTsMask; const Tile: TTsScreenIntRect): TTsSubMaskRef; static;
    // False when the mask has another size than the pixmap: nothing is drawn then, with or without tiles
    class function MaskFitsPixmap(const Mask: PTsMask; const Pixmap: TTsPixmap): Boolean; static;

  public
    // Sometimes in the drawing pipeline, we have to perform math on path coordinates, even after the path is in device-coordinates. To
    // preflight issues where these operations could turn finite path values into infinities (or NaNs), the path is rejected if its bounds
    // are too close to the maximum float.
    class function IsTooBigForMath(const Path: TTsPath): Boolean; static;

    // Draws a filled rectangle onto the pixmap. Usually slower than filling a rectangular path, but it does not suffer from weird clipping
    // of horizontal and vertical edges.
    class procedure FillRect(var Pixmap: TTsPixmap; const Rect: TTsRect; const Paint: TTsPaint; const Transform: TTsTransform;
                             const Mask: PTsMask); static;

    class procedure FillPath(var Pixmap: TTsPixmap; const Path: TTsPath; const Paint: TTsPaint; const FillRule: TTsFillRule;
                             const Transform: TTsTransform; const Mask: PTsMask); static;

    // Strokes a path. A stroke that is not wider than a pixel after the transform is drawn as a hairline, a wider one is converted into a
    // path that is filled.
    class procedure StrokePath(var Pixmap: TTsPixmap; const Path: TTsPath; const Paint: TTsPaint; const Stroke: TTsStroke;
                               const Transform: TTsTransform; const Mask: PTsMask); static;

    // Draws a pixmap on top of the pixmap: the same as filling a rectangle with a pixmap pattern
    class procedure DrawPixmap(var Pixmap: TTsPixmap; const X, Y: Integer; const Source: TTsPixmapRef; const Paint: TTsPixmapPaint;
                               const Transform: TTsTransform; const Mask: PTsMask); static;

    // Masks-out the content that is already drawn. The mask must have the size of the pixmap; no transform or offset is allowed.
    class procedure ApplyMask(var Pixmap: TTsPixmap; const Mask: TTsMask); static;
  end;

  // Mask::fill_path and Mask::intersect_path
  TTsMaskPainter = record helper for TTsMask
    // Draws a filled path onto the mask: in terms of an RGB image, a white path on top of a black mask. Doesn't reset the existing content.
    procedure FillPath(const Path: TTsPath; const FillRule: TTsFillRule; const AntiAlias: Boolean; const Transform: TTsTransform);

    // Intersects the path with the current clipping path: a temporary mask with the same size is created
    procedure IntersectPath(const Path: TTsPath; const FillRule: TTsFillRule; const AntiAlias: Boolean; const Transform: TTsTransform);
  end;

implementation

uses
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Color,
  Pdf4D.Render.Native.BlendMode,
  Pdf4D.Render.Native.Stage,
  Pdf4D.Render.Native.Pipeline.Context,
  Pdf4D.Render.Native.Pipeline,
  Pdf4D.Render.Native.Pipeline.Blitter,
  Pdf4D.Render.Native.Scan.AntiAlias,
  Pdf4D.Render.Native.Scan.Hairline,
  Pdf4D.Render.Native.Scan.HairlineAntiAlias;

const
  // 0.25: scales the maximum down to allow for small multiplies
  ScaleDownToAllowForSmallMultiplies: Single = 0.25;
  Scale256: Single = 256;
  Scale255: Single = 255;

// path = path.transform(ts) of the tile loops; the transformed path is a separate variable, because the out parameter would clear the path
function MoveTilePath(var Path: TTsPath; const Ts: TTsTransform): Boolean;
begin
  var Transformed: TTsPath;
  if not Path.TryTransform(Ts, Transformed) then
  begin
    Exit(False);
  end;

  Path := Transformed;
  Result := True;
end;

// Pixmap::size().to_screen_int_rect(0, 0); False for an empty pixmap, which cannot draw
function TryWholeRect(const Width, Height: Cardinal; out Clip: TTsScreenIntRect): Boolean;
begin
  var Size: TTsIntSize;
  if not TTsIntSize.TryFromWH(Width, Height, Size) then
  begin
    Clip := Default(TTsScreenIntRect);
    Exit(False);
  end;

  Clip := Size.ToScreenIntRect(0, 0);
  Result := True;
end;

{ TTsDrawTiler }

class function TTsDrawTiler.Required(const ImageWidth, ImageHeight: Cardinal): Boolean;
begin
  Result := ((ImageWidth > MaxDimensions) or (ImageHeight > MaxDimensions));
end;

class function TTsDrawTiler.TryCreate(const ImageWidth, ImageHeight: Cardinal; out Tiler: TTsDrawTiler): Boolean;
begin
  Tiler := Default(TTsDrawTiler);

  if not Required(ImageWidth, ImageHeight) then
  begin
    Exit(False);
  end;

  Tiler.FImageWidth := ImageWidth;
  Tiler.FImageHeight := ImageHeight;
  Result := True;
end;

function TTsDrawTiler.TryNext(out Tile: TTsScreenIntRect): Boolean;
begin
  Tile := Default(TTsScreenIntRect);

  // TODO of tiny-skia: iterate only over tiles that actually affected by the shape
  if (FXOffset >= FImageWidth) or (FYOffset >= FImageHeight) then
  begin
    Exit(False);
  end;

  var Width := FImageWidth - FXOffset;
  if Width > MaxDimensions then
  begin
    Width := MaxDimensions;
  end;

  var Height := FImageHeight - FYOffset;
  if Height > MaxDimensions then
  begin
    Height := MaxDimensions;
  end;

  Result := TTsScreenIntRect.TryFromXYWH(FXOffset, FYOffset, Width, Height, Tile);

  Inc(FXOffset, MaxDimensions);
  if FXOffset >= FImageWidth then
  begin
    FXOffset := 0;
    Inc(FYOffset, MaxDimensions);
  end;
end;

{ TTsPainter }

class function TTsPainter.IsTooBigForMath(const Path: TTsPath): Boolean;
begin
  const B = Path.Bounds;
  const TooBigMax: Single = TTsScalar.ScalarMax * ScaleDownToAllowForSmallMultiplies;
  const NegativeMax: Single = -TooBigMax;

  // use the negated form so that we return true if the bounds contain NaN
  if (B.Left >= NegativeMax) and (B.Top >= NegativeMax) and (B.Right <= TooBigMax) and (B.Bottom <= TooBigMax) then
  begin
    Exit(False);
  end;

  Result := True;
end;

class function TTsPainter.SubMaskOf(const Mask: PTsMask): TTsSubMaskRef;
begin
  if Mask = nil then
  begin
    Exit(Default(TTsSubMaskRef));
  end;

  Result := Mask.AsSubMask;
end;

class function TTsPainter.SubMaskOfTile(const Mask: PTsMask; const Tile: TTsScreenIntRect): TTsSubMaskRef;
begin
  Result := Default(TTsSubMaskRef);
  if Mask = nil then
  begin
    Exit;
  end;

  // a tile that the mask does not intersect has no mask, as in Rust (and_then)
  if not Mask.TrySubMask(Tile.ToIntRect, Result) then
  begin
    Result := Default(TTsSubMaskRef);
  end;
end;

class function TTsPainter.MaskFitsPixmap(const Mask: PTsMask; const Pixmap: TTsPixmap): Boolean;
begin
  // Pdf4D: without tiles the blitter rejects a mask of another size, with tiles a tile that the mask does not cover would be drawn unmasked
  Result := ((Mask = nil) or ((Mask.Width = Pixmap.Width) and (Mask.Height = Pixmap.Height)));
end;

class procedure TTsPainter.FillRect(var Pixmap: TTsPixmap; const Rect: TTsRect; const Paint: TTsPaint; const Transform: TTsTransform;
  const Mask: PTsMask);
begin
  if not MaskFitsPixmap(Mask, Pixmap) then
  begin
    Exit;
  end;

  // TODO of tiny-skia: we probably can use tiler for rect too
  if Transform.IsIdentity and (not TTsDrawTiler.Required(Pixmap.Width, Pixmap.Height)) then
  begin
    // TODO of tiny-skia: ignore rects outside the pixmap
    var Clip: TTsScreenIntRect;
    if not TryWholeRect(Pixmap.Width, Pixmap.Height, Clip) then
    begin
      Exit;
    end;

    var Blitter: TTsRasterPipelineBlitter;
    if not TTsRasterPipelineBlitter.TryCreate(Paint, SubMaskOf(Mask), Pixmap.SubPixmap, Blitter) then
    begin
      // nothing to do, all good
      Exit;
    end;

    try
      if Paint.AntiAlias then
      begin
        TTsScan.FillRectAntiAlias(Rect, Clip, Blitter);
      end
      else
      begin
        TTsScan.FillRect(Rect, Clip, Blitter);
      end;
    finally
      Blitter.Free;
    end;
  end
  else
  begin
    FillPath(Pixmap, TTsPathBuilder.FromRect(Rect), Paint, TTsFillRule.Winding, Transform, Mask);
  end;
end;

class procedure TTsPainter.FillPath(var Pixmap: TTsPixmap; const Path: TTsPath; const Paint: TTsPaint; const FillRule: TTsFillRule;
  const Transform: TTsTransform; const Mask: PTsMask);
begin
  if not MaskFitsPixmap(Mask, Pixmap) then
  begin
    Exit;
  end;

  if not Transform.IsIdentity then
  begin
    var Transformed: TTsPath;
    if not Path.TryTransform(Transform, Transformed) then
    begin
      // path transformation failed
      Exit;
    end;

    var TransformedPaint := Paint;
    TransformedPaint.Shader.ApplyTransform(Transform);

    FillPath(Pixmap, Transformed, TransformedPaint, FillRule, TTsTransform.Identity, Mask);
    Exit;
  end;

  // This is sort of similar to SkDraw::drawPath

  // Skip empty paths and horizontal/vertical lines
  const PathBounds = Path.Bounds;
  if TTsScalar.IsNearlyZero(PathBounds.Width) or TTsScalar.IsNearlyZero(PathBounds.Height) then
  begin
    // empty paths and horizontal/vertical lines cannot be filled
    Exit;
  end;

  if IsTooBigForMath(Path) then
  begin
    // path coordinates are too big
    Exit;
  end;

  // TODO of tiny-skia: ignore paths outside the pixmap

  var Tiler: TTsDrawTiler;
  if TTsDrawTiler.TryCreate(Pixmap.Width, Pixmap.Height, Tiler) then
  begin
    var TilePath := Path;
    var TilePaint := Paint;

    // Rust leaves the path shifted after a tile whose subpixmap or blitter is None (continue skips the translate forward); Delphi always
    // translates back, which is the correct behaviour and changes no image.
    var Tile: TTsScreenIntRect;
    while Tiler.TryNext(Tile) do
    begin
      const BackTs = TTsTransform.FromTranslate(-Single(Tile.X), -Single(Tile.Y));
      if not MoveTilePath(TilePath, BackTs) then
      begin
        // path transformation failed
        Exit;
      end;
      TilePaint.Shader.ApplyTransform(BackTs);

      const ClipRect = Tile.Size.ToScreenIntRect(0, 0);
      var Region: TTsSubPixmapMut;
      if Pixmap.TrySubPixmap(Tile.ToIntRect, Region) then
      begin
        var Blitter: TTsRasterPipelineBlitter;
        // a blitter that cannot be created has nothing to do
        if TTsRasterPipelineBlitter.TryCreate(TilePaint, SubMaskOfTile(Mask, Tile), Region, Blitter) then
        begin
          try
            // We're ignoring "errors" here, because the fill returns nothing when rendering a tile that doesn't have a path on it. Which is
            // not an error in this case.
            if TilePaint.AntiAlias then
            begin
              TTsScanAntiAlias.FillPath(TilePath, FillRule, ClipRect, Blitter);
            end
            else
            begin
              TTsScan.FillPath(TilePath, FillRule, ClipRect, Blitter);
            end;
          finally
            Blitter.Free;
          end;
        end;
      end;

      const ForwardTs = TTsTransform.FromTranslate(Single(Tile.X), Single(Tile.Y));
      if not MoveTilePath(TilePath, ForwardTs) then
      begin
        Exit;
      end;
      TilePaint.Shader.ApplyTransform(ForwardTs);
    end;
  end
  else
  begin
    var ClipRect: TTsScreenIntRect;
    if not TryWholeRect(Pixmap.Width, Pixmap.Height, ClipRect) then
    begin
      Exit;
    end;

    var Blitter: TTsRasterPipelineBlitter;
    if not TTsRasterPipelineBlitter.TryCreate(Paint, SubMaskOf(Mask), Pixmap.SubPixmap, Blitter) then
    begin
      // nothing to do, all good
      Exit;
    end;

    try
      if Paint.AntiAlias then
      begin
        TTsScanAntiAlias.FillPath(Path, FillRule, ClipRect, Blitter);
      end
      else
      begin
        TTsScan.FillPath(Path, FillRule, ClipRect, Blitter);
      end;
    finally
      Blitter.Free;
    end;
  end;
end;

class procedure TTsPainter.StrokePath(var Pixmap: TTsPixmap; const Path: TTsPath; const Paint: TTsPaint; const Stroke: TTsStroke;
  const Transform: TTsTransform; const Mask: PTsMask);
begin
  if not MaskFitsPixmap(Mask, Pixmap) then
  begin
    Exit;
  end;

  if Stroke.Width < 0 then
  begin
    // negative stroke width isn't allowed
    Exit;
  end;

  const ResScale = TTsPathStroker.ComputeResolutionScale(Transform);

  var StrokedSource := Path;
  if Stroke.HasDash then
  begin
    if not Path.TryDash(Stroke.Dash, ResScale, StrokedSource) then
    begin
      // path dashing failed
      Exit;
    end;
  end;

  var Coverage: Single;
  if TreatAsHairline(Paint, Stroke, Transform, Coverage) then
  begin
    var HairlinePaint := Paint;
    if Coverage = 1 then
    begin
      // No changes to the paint
    end
    else if HairlinePaint.BlendMode.ShouldPreScaleCoverage then
    begin
      // This is the old technique, which we preserve for now so we don't change previous results (testing); the new way seems fine, its
      // just (a tiny bit) different.
      const CoverageScaled: Single = Coverage * Scale256;
      const Scale = TTsScalar.SaturateToInt32(CoverageScaled);
      const NewAlpha = (255 * Scale) shr 8;
      const NewAlphaValue: Single = NewAlpha;
      HairlinePaint.Shader.ApplyOpacity(NewAlphaValue / Scale255);
    end;

    var Tiler: TTsDrawTiler;
    if TTsDrawTiler.TryCreate(Pixmap.Width, Pixmap.Height, Tiler) then
    begin
      var TilePath := StrokedSource;
      var TilePaint := HairlinePaint;

      if not Transform.IsIdentity then
      begin
        TilePaint.Shader.ApplyTransform(Transform);
        if not MoveTilePath(TilePath, Transform) then
        begin
          // path transformation failed
          Exit;
        end;
      end;

      var Tile: TTsScreenIntRect;
      while Tiler.TryNext(Tile) do
      begin
        const BackTs = TTsTransform.FromTranslate(-Single(Tile.X), -Single(Tile.Y));
        if not MoveTilePath(TilePath, BackTs) then
        begin
          // path transformation failed
          Exit;
        end;
        TilePaint.Shader.ApplyTransform(BackTs);

        var Region: TTsSubPixmapMut;
        if Pixmap.TrySubPixmap(Tile.ToIntRect, Region) then
        begin
          // We're ignoring "errors" here, because the hairline stroke returns nothing when rendering a tile that doesn't have a path on it
          StrokeHairline(TilePath, TilePaint, Stroke.LineCap, SubMaskOfTile(Mask, Tile), Region);
        end;

        const ForwardTs = TTsTransform.FromTranslate(Single(Tile.X), Single(Tile.Y));
        if not MoveTilePath(TilePath, ForwardTs) then
        begin
          Exit;
        end;
        TilePaint.Shader.ApplyTransform(ForwardTs);
      end;
    end
    else
    begin
      const Region = Pixmap.SubPixmap;
      const SubMask = SubMaskOf(Mask);
      if not Transform.IsIdentity then
      begin
        HairlinePaint.Shader.ApplyTransform(Transform);

        var Transformed: TTsPath;
        if not StrokedSource.TryTransform(Transform, Transformed) then
        begin
          // path transformation failed
          Exit;
        end;

        StrokeHairline(Transformed, HairlinePaint, Stroke.LineCap, SubMask, Region);
      end
      else
      begin
        StrokeHairline(StrokedSource, HairlinePaint, Stroke.LineCap, SubMask, Region);
      end;
    end;
  end
  else
  begin
    var Outline: TTsPath;
    if not StrokedSource.TryStroke(Stroke, ResScale, Outline) then
    begin
      // path stroking failed
      Exit;
    end;

    FillPath(Pixmap, Outline, Paint, TTsFillRule.Winding, Transform, Mask);
  end;
end;

class procedure TTsPainter.StrokeHairline(const Path: TTsPath; const Paint: TTsPaint; const LineCap: TTsLineCap; const Mask: TTsSubMaskRef;
  const Pixmap: TTsSubPixmapMut);
begin
  var Clip: TTsScreenIntRect;
  if not TryWholeRect(Pixmap.Width, Pixmap.Height, Clip) then
  begin
    Exit;
  end;

  var Blitter: TTsRasterPipelineBlitter;
  if not TTsRasterPipelineBlitter.TryCreate(Paint, Mask, Pixmap, Blitter) then
  begin
    // nothing to do, all good
    Exit;
  end;

  try
    if Paint.AntiAlias then
    begin
      TTsScanHairlineAntiAlias.StrokePath(Path, LineCap, Clip, Blitter);
    end
    else
    begin
      TTsScanHairline.StrokePath(Path, LineCap, Clip, Blitter);
    end;
  finally
    Blitter.Free;
  end;
end;

class function TTsPainter.TreatAsHairline(const Paint: TTsPaint; const Stroke: TTsStroke; const Ts: TTsTransform;
  out Coverage: Single): Boolean;

  function FastLen(const P: TTsPoint): Single;
  begin
    var X: Single := Abs(P.X);
    var Y: Single := Abs(P.Y);
    if X < Y then
    begin
      const Swapped: Single = X;
      X := Y;
      Y := Swapped;
    end;

    Result := X + TTsScalar.Half(Y);
  end;

begin
  Coverage := 0;

  if Stroke.Width = 0 then
  begin
    Coverage := 1;
    Exit(True);
  end;

  if not Paint.AntiAlias then
  begin
    Exit(False);
  end;

  // We don't care about translate
  var NoTranslate := Ts;
  NoTranslate.TX := 0;
  NoTranslate.TY := 0;

  // We need to try to fake a thick-stroke with a modulated hairline
  var Points: array[0..1] of TTsPoint;
  Points[0] := TTsPoint.FromXY(Stroke.Width, 0);
  Points[1] := TTsPoint.FromXY(0, Stroke.Width);
  NoTranslate.MapPoints(Points);

  const Len0: Single = FastLen(Points[0]);
  const Len1: Single = FastLen(Points[1]);

  if (Len0 <= 1) and (Len1 <= 1) then
  begin
    Coverage := TTsScalar.Ave(Len0, Len1);
    Exit(True);
  end;

  Result := False;
end;

class procedure TTsPainter.DrawPixmap(var Pixmap: TTsPixmap; const X, Y: Integer; const Source: TTsPixmapRef; const Paint: TTsPixmapPaint;
  const Transform: TTsTransform; const Mask: PTsMask);
begin
  if (Source.Width = 0) or (Source.Height = 0) then
  begin
    Exit;
  end;

  if not MaskFitsPixmap(Mask, Pixmap) then
  begin
    Exit;
  end;

  // An offset that moves the right or the bottom edge beyond the integer range draws nothing (Rust would panic here)
  var IntRect: TTsIntRect;
  if not TTsIntRect.TryFromXYWH(X, Y, Source.Width, Source.Height, IntRect) then
  begin
    Exit;
  end;
  const Rect = IntRect.ToRect;

  // TODO of tiny-skia: SkSpriteBlitter, partially clipped, clipped out

  // Translate pattern as well as bounds
  const PattTransform = TTsTransform.FromTranslate(X, Y);

  var FillPaint := TTsPaint.Default;
  // Pad, otherwise we will get weird borders overlap
  FillPaint.Shader := TTsShader.NewPattern(Source, TTsSpreadMode.Pad, Paint.Quality, Paint.Opacity, PattTransform);
  FillPaint.BlendMode := Paint.BlendMode;
  // Skia doesn't use it too
  FillPaint.AntiAlias := False;
  // Pattern will use hq anyway
  FillPaint.ForceHqPipeline := False;

  FillRect(Pixmap, Rect, FillPaint, Transform, Mask);
end;

class procedure TTsPainter.ApplyMask(var Pixmap: TTsPixmap; const Mask: TTsMask);
begin
  if (Pixmap.Width <> Mask.Width) or (Pixmap.Height <> Mask.Height) then
  begin
    // Pixmap and Mask are expected to have the same size
    Exit;
  end;

  var Rect: TTsScreenIntRect;
  if not TryWholeRect(Pixmap.Width, Pixmap.Height, Rect) then
  begin
    Exit;
  end;

  // Just a dummy
  var PixmapSrc: TTsPixmapRef;
  if not TTsPixmapRef.TryFromBytes([0, 0, 0, 0], 1, 1, PixmapSrc) then
  begin
    Exit;
  end;

  var Builder := TTsRasterPipelineBuilder.New;
  Builder.Push(TTsStage.LoadMaskU8);
  Builder.Push(TTsStage.LoadDestination);
  Builder.Push(TTsStage.DestinationIn);
  Builder.Push(TTsStage.Store);
  var Compiled := Builder.Compile;

  var Region := Pixmap.SubPixmap;
  Compiled.Run(Rect, Default(TTsAAMaskCtx), Mask.AsSubMask.MaskCtx, PixmapSrc, Region);
end;

{ TTsMaskPainter }

procedure TTsMaskPainter.FillPath(const Path: TTsPath; const FillRule: TTsFillRule; const AntiAlias: Boolean; const Transform: TTsTransform);
begin
  if not Transform.IsIdentity then
  begin
    var Transformed: TTsPath;
    if not Path.TryTransform(Transform, Transformed) then
    begin
      // path transformation failed
      Exit;
    end;

    FillPath(Transformed, FillRule, AntiAlias, TTsTransform.Identity);
    Exit;
  end;

  // This is sort of similar to SkDraw::drawPath

  // Skip empty paths and horizontal/vertical lines
  const PathBounds = Path.Bounds;
  if TTsScalar.IsNearlyZero(PathBounds.Width) or TTsScalar.IsNearlyZero(PathBounds.Height) then
  begin
    // empty paths and horizontal/vertical lines cannot be filled
    Exit;
  end;

  if TTsPainter.IsTooBigForMath(Path) then
  begin
    // path coordinates are too big
    Exit;
  end;

  var Tiler: TTsDrawTiler;
  if TTsDrawTiler.TryCreate(Width, Height, Tiler) then
  begin
    var TilePath := Path;

    var Tile: TTsScreenIntRect;
    while Tiler.TryNext(Tile) do
    begin
      const BackTs = TTsTransform.FromTranslate(-Single(Tile.X), -Single(Tile.Y));
      if not MoveTilePath(TilePath, BackTs) then
      begin
        // path transformation failed
        Exit;
      end;

      const ClipRect = Tile.Size.ToScreenIntRect(0, 0);
      var Region: TTsSubPixmapMut;
      if TrySubPixmap(Tile.ToIntRect, Region) then
      begin
        var Blitter: TTsRasterPipelineBlitter;
        // a blitter that cannot be created has nothing to do
        if TTsRasterPipelineBlitter.TryCreateForMask(Region, Blitter) then
        begin
          try
            if AntiAlias then
            begin
              TTsScanAntiAlias.FillPath(TilePath, FillRule, ClipRect, Blitter);
            end
            else
            begin
              TTsScan.FillPath(TilePath, FillRule, ClipRect, Blitter);
            end;
          finally
            Blitter.Free;
          end;
        end;
      end;

      const ForwardTs = TTsTransform.FromTranslate(Single(Tile.X), Single(Tile.Y));
      if not MoveTilePath(TilePath, ForwardTs) then
      begin
        Exit;
      end;
    end;
  end
  else
  begin
    var ClipRect: TTsScreenIntRect;
    if not TryWholeRect(Width, Height, ClipRect) then
    begin
      Exit;
    end;

    var Blitter: TTsRasterPipelineBlitter;
    if not TTsRasterPipelineBlitter.TryCreateForMask(SubPixmap, Blitter) then
    begin
      // nothing to do, all good
      Exit;
    end;

    try
      if AntiAlias then
      begin
        TTsScanAntiAlias.FillPath(Path, FillRule, ClipRect, Blitter);
      end
      else
      begin
        TTsScan.FillPath(Path, FillRule, ClipRect, Blitter);
      end;
    finally
      Blitter.Free;
    end;
  end;
end;

procedure TTsMaskPainter.IntersectPath(const Path: TTsPath; const FillRule: TTsFillRule; const AntiAlias: Boolean;
  const Transform: TTsTransform);
begin
  var Submask: TTsMask;
  if not TTsMask.TryCreate(Width, Height, Submask) then
  begin
    Exit;
  end;

  Submask.FillPath(Path, FillRule, AntiAlias, Transform);

  for var I := 0 to High(Data) do
  begin
    Data[I] := TTsColorMath.PremultiplyU8(Data[I], Submask.Data[I]);
  end;
end;

end.
