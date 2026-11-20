// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/rendering/PageDrawer.java (3.0.8): drawPage, setClip, getStroke, getDashArray,
// strokePath, fillPath, fillAndStrokePath, clip, adjustClip, endPath and the path construction; the paint is the solid colour of
// getPaint, and showFontGlyph, drawGlyph, beginText, endText, beginTextClip and endTextClip, and drawImage and drawBufferedImage without
// the soft mask and the transfer function of the graphics state, and without the pre-scaling of strongly reduced images (the device
// scales), and showTransparencyGroup with the inner class TransparencyGroup (bounds, backdrop) and hasBlendMode. Shadings, patterns
// and soft masks are not drawn yet.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/contentstream/PDFStreamEngine.java (3.0.8), transformWidth, clipToRect, showGlyph and
// showType3Glyph
unit Pdf4D.Render.PageDrawer;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  System.Generics.Collections,
  Pdf4D.Common.Matrix,
  Pdf4D.Common.Path,
  Pdf4D.Content.GraphicsState,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Font.Base,
  Pdf4D.Font.Type3,
  Pdf4D.Graphics.Color,
  Pdf4D.Graphics.Image,
  Pdf4D.Model.FormXObject,
  Pdf4D.Model.Page,
  Pdf4D.Model.Rectangle,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Render.GraphicsEngine,
  Pdf4D.Render.GroupDevice,
  Pdf4D.Render.Renderer,
  Pdf4D.Render.Renderer.Interfaces;

type
  // Draws one page on a device. The page is drawn in page space: the path of an operator is kept after the CTM, and the device gets it
  // with the matrix from page space to device pixels (the scale, the rotation, the flip and the offset of the region).
  TPdfPageDrawer = class(TPdfGraphicsEngine)
  private
    const MinimumLineWidth = 0.25;
    const MinimumDashLength = 0.062;
    const MinimumDashLengthAtSmallScale = 0.2;
    const SmallScale = 0.5;
    const MaximumDashPhase = 32767;
    const DefaultMiterLimit = 10;
    const MinimumClipSize = 2.0;
    const RectangleCorners = 4;
    // Paths further out are not adjusted: their bounds do not fit in an Integer
    const MaximumAdjustedCoordinate = 1.0e9;

  private
    FRenderer: TPdfRenderer;
    FPage: TPDPage;
    FDevice: IPdfGraphicsDevice;
    FParams: TPdfRenderParams;
    // xform of PageDrawer, with the offset of the region: page space to device pixels
    FPageToDevice: TPdfMatrix;
    // Of the matrix of the page without the offset of the region, as xformScalingFactorX
    FScalingFactorX: Single;
    FScalingFactorY: Single;
    FLinePath: TPdfPath;
    // The clip that the device has; the clip chain is immutable, so identity says whether it changed
    FLastClip: IPdfClipPath;
    FIsCancelled: Boolean;
    // The glyphs of a text object with a clipping mode, in page space; the clip is made at its end
    FTextClip: TPdfPath;
    FType3Depth: Integer;
    // The Type 3 glyphs without procedure that are in the log, so that a long text with one gives one line
    FLoggedMissingGlyphs: TDictionary<Int64, Boolean>;
    FGroupDepth: Integer;
    FHasLoggedGroupDepth: Boolean;

    function TransformWidth(const Width: Single): Single;
    function NonStrokingComposite(const IsAntiAliased: Boolean): TPdfComposite;
    function StrokingComposite: TPdfComposite;
    function SolidPaint(const Color: TPDColor): TPdfPaint;
    function TryBuildStroke(out Stroke: TPdfStrokeStyle): Boolean;
    function TryBuildDashes(out Dashes: TArray<Single>; out Phase: Single): Boolean;
    function PathAround(const Rect: TPdfRectangle; const Transform: TPdfMatrix): TPdfPath;
    function AdjustedClip(const Path: TPdfPath): TPdfPath;
    class function IsRectangular(const Path: TPdfPath): Boolean; static;
    class function IsPoint(const Path: TPdfPath): Boolean; static;
    class function HasSegments(const Path: TPdfPath): Boolean; static;
    class function FloorToInteger(const Value: Single): Integer; static;
    class function LimitedAlpha(const Alpha: Single): Single; static;
    procedure ApplyClip;
    procedure PaintFill(const Path: TPdfPath; const FillRule: TPdfFillRule);
    procedure PaintStroke(const Path: TPdfPath);
    procedure DrawStroke(const Path: TPdfPath; const Stroke: TPdfStrokeStyle; const Paint: TPdfPaint);
    function GlyphMatrix(const TextRenderingMatrix: TPdfMatrix; const Font: TPDFont; const Code: Integer;
                         const Displacement: TPdfVector): TPdfMatrix;
    procedure ShowFontGlyph(const TextRenderingMatrix: TPdfMatrix; const Font: TPDFont; const Code: Integer; const Displacement: TPdfVector);
    procedure DrawGlyph(const GlyphPath: TPdfPath);
    procedure ShowType3Glyph(const TextRenderingMatrix: TPdfMatrix; const Font: TPDType3Font; const Code: Integer);
    procedure RunType3CharProc(const Font: TPDType3Font; const CharProc: TPDType3CharProc; const TextRenderingMatrix: TPdfMatrix);
    procedure LogMissingCharProc(const Font: TPDType3Font; const Code: Integer);
    class function IsFinitePath(const Path: TPdfPath): Boolean; static;
    function ImageFilter(const Image: TPDImage; const Width, Height: Integer): TPdfImageFilter;
    function TryMakeStencilBitmap(const Mask: TPdfBitmap): Boolean;
    function ImageToPage(const Width, Height: Integer): TPdfMatrix;
    function TryScaleDown(const Bitmap: TPdfBitmap; const ImageTransform: TPdfMatrix; out Scaled: TPdfBitmap): Boolean;
    procedure DrawImageBitmap(const Image: TPDImage; const Bitmap: TPdfBitmap);
    procedure DrawStencil(const Image: TPDImage);
    function TryGetGroupBounds(const Form: TPDFormXObject; out Bounds: TRect): Boolean;
    function IntersectedWithClips(const Area: TRectF): TRectF;
    class function TranslatedClip(const Clip: IPdfClipPath; const OffsetX, OffsetY: Integer): IPdfClipPath; static;
    class function HasBlendMode(const Form: TPDFormXObject; const Done: TList<TCosStream>): Boolean; static;
    class function HasBlendModeState(const Resources: TCosDictionary): Boolean; static;
    class function HasBlendModeChild(const Resources: TCosDictionary; const Done: TList<TCosStream>): Boolean; static;
    function NeedsBackdrop(const Form: TPDFormXObject): Boolean;
    function BackdropComposite: TPdfComposite;
    procedure DrawGroup(const Form: TPDFormXObject; const Bounds: TRect);
    procedure RunGroupContent(const Form: TPDFormXObject; const GroupDevice: IPdfRasterDevice; const Bounds: TRect);
    procedure RunGroupStream(const Form: TPDFormXObject; const Bounds: TRect);
    procedure DrawGroupResult(const GroupDevice: TPdfGroupDevice; const Bounds: TRect);

  protected
    // The page clip: the crop box
    function CreateInitialGraphicsState(const Page: TPDPage): TPDGraphicsState; override;
    function StopRequested: Boolean; override;
    procedure ClipToRect(const Rect: TPdfRectangle); override;

  public
    // Device is drawn on without being cleared. The region of Params must be valid already, the renderer checks the arguments.
    constructor Create(const Renderer: TPdfRenderer; const Page: TPDPage; const Device: IPdfGraphicsDevice; const Params: TPdfRenderParams);
    destructor Destroy; override;

    procedure DrawPage;

    procedure BeginText; override;
    procedure EndText; override;
    procedure ShowGlyph(const TextRenderingMatrix: TPdfMatrix; const Font: TPDFont; const Code: Integer; const Displacement: TPdfVector); override;

    procedure AppendRectangle(const P0, P1, P2, P3: TPointF); override;
    procedure Clip(const FillRule: TPdfFillRule); override;
    procedure MoveTo(const X, Y: Single); override;
    procedure LineTo(const X, Y: Single); override;
    procedure CurveTo(const X1, Y1, X2, Y2, X3, Y3: Single); override;
    function TryGetCurrentPoint(out Point: TPointF): Boolean; override;
    procedure ClosePath; override;
    procedure EndPath; override;
    procedure StrokePath; override;
    procedure FillPath(const FillRule: TPdfFillRule); override;
    procedure FillAndStrokePath(const FillRule: TPdfFillRule); override;
    procedure ShadingFill(const ShadingName: string); override;
    procedure DrawImage(const Image: TPDImage); override;
    procedure ShowTransparencyGroup(const Form: TPDFormXObject); override;

    property Renderer: TPdfRenderer read FRenderer;
    // True once the cancel token of the parameters has said so
    property IsCancelled: Boolean read FIsCancelled;
  end;

implementation

uses
  System.Math,
  System.SysUtils,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Names,
  Pdf4D.Graphics.State,
  Pdf4D.Model.ExtendedGraphicsState,
  Pdf4D.Render.ClipPath,
  Pdf4D.Render.GlyphCache,
  Pdf4D.Render.ImageScaler,
  Pdf4D.Render.PageTransform,
  Pdf4D.Render.StrokeNormalizer;

const
  Half = 0.5;
  LargestStyleCode = 2;
  // A glyph of a font that is not embedded is made as wide as the PDF says (in thousandths of text space)
  Thousand = 1000;
  WidthTolerance = 0.0001;
  MaximumLoggedMissingGlyphs = 1024;
  // PDFRenderer.imageDownscalingOptimizationThreshold: an image that is drawn at less than this scale is averaged down first
  ImageDownscalingThreshold = 0.5;
  CodeShift = 48;
  CodeMask = $FFFF;

{ TPdfPageDrawer }

constructor TPdfPageDrawer.Create(const Renderer: TPdfRenderer; const Page: TPDPage; const Device: IPdfGraphicsDevice;
                                  const Params: TPdfRenderParams);
begin
  inherited Create;
  FRenderer := Renderer;
  FPage := Page;
  FDevice := Device;
  FParams := Params;
  FLinePath := TPdfPath.Create;
  FTextClip := TPdfPath.Create;
  FLoggedMissingGlyphs := TDictionary<Int64, Boolean>.Create;

  const Transform = TPdfPageTransform.Create(Page.CropBox, Page.Rotation + Params.ExtraRotation, Params.Scale);
  const Whole = Transform.PageToDevice;
  // The device shows the region: its pixel (0, 0) is the top left pixel of the region
  FPageToDevice := TPdfMatrix.Create(Whole.ScaleX, Whole.ShearY, Whole.ShearX, Whole.ScaleY, Whole.TranslateX - Params.Region.Left,
                                     Whole.TranslateY - Params.Region.Top);
  FScalingFactorX := Abs(Whole.ScalingFactorX);
  FScalingFactorY := Abs(Whole.ScalingFactorY);
end;

destructor TPdfPageDrawer.Destroy;
begin
  FLoggedMissingGlyphs.Free;
  FTextClip.Free;
  FLinePath.Free;
  inherited;
end;

procedure TPdfPageDrawer.DrawPage;
begin
  ProcessPage(FPage);
end;

// PDGraphicsState(PDRectangle) makes the crop box the first clipping path
function TPdfPageDrawer.CreateInitialGraphicsState(const Page: TPDPage): TPDGraphicsState;
begin
  Result := inherited CreateInitialGraphicsState(Page);
  try
    const CropPath = PathAround(Page.CropBox, TPdfMatrix.Identity);
    try
      TPdfRenderGraphicsState(Result).IntersectClip(CropPath, FPageToDevice, TPdfFillRule.NonZero);
    finally
      CropPath.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TPdfPageDrawer.StopRequested: Boolean;
begin
  if (not FIsCancelled) and Assigned(FParams.Cancel) then
  begin
    FIsCancelled := FParams.Cancel.IsCancelled;
  end;
  Result := FIsCancelled;
end;

// PDRectangle.transform: the corners after the matrix, in the order lower left, lower right, upper right, upper left
function TPdfPageDrawer.PathAround(const Rect: TPdfRectangle; const Transform: TPdfMatrix): TPdfPath;
begin
  const P0 = Transform.TransformPoint(Rect.LowerLeftX, Rect.LowerLeftY);
  const P1 = Transform.TransformPoint(Rect.UpperRightX, Rect.LowerLeftY);
  const P2 = Transform.TransformPoint(Rect.UpperRightX, Rect.UpperRightY);
  const P3 = Transform.TransformPoint(Rect.LowerLeftX, Rect.UpperRightY);

  Result := TPdfPath.Create;
  Result.MoveTo(P0.X, P0.Y);
  Result.LineTo(P1.X, P1.Y);
  Result.LineTo(P2.X, P2.Y);
  Result.LineTo(P3.X, P3.Y);
  Result.ClosePath;
end;

procedure TPdfPageDrawer.ClipToRect(const Rect: TPdfRectangle);
begin
  const Path = PathAround(Rect, GraphicsState.CurrentTransformationMatrix);
  try
    const Bounds = Path.Bounds;
    const IsFinite = ((not (IsNan(Bounds.Left) or IsInfinite(Bounds.Left) or IsNan(Bounds.Top) or IsInfinite(Bounds.Top))) and
                      (not (IsNan(Bounds.Right) or IsInfinite(Bounds.Right) or IsNan(Bounds.Bottom) or IsInfinite(Bounds.Bottom))));
    if IsFinite then
    begin
      RenderState.IntersectClip(Path, FPageToDevice, TPdfFillRule.NonZero);
      FLastClip := nil;
    end
    else
    begin
      LogError('A clip to a rectangle is skipped: the rectangle does not give finite coordinates', []);
    end;
  finally
    Path.Free;
  end;
end;

// PDFStreamEngine.transformWidth
function TPdfPageDrawer.TransformWidth(const Width: Single): Single;
begin
  const Matrix = GraphicsState.CurrentTransformationMatrix;
  const X = Matrix.ScaleX + Matrix.ShearX;
  const Y = Matrix.ScaleY + Matrix.ShearY;
  Result := Width * Single(Sqrt((X * X + Y * Y) * Half));
end;

class function TPdfPageDrawer.LimitedAlpha(const Alpha: Single): Single;
begin
  if IsNan(Alpha) then
  begin
    Exit(1);
  end;
  Result := Min(Max(Alpha, 0), 1);
end;

function TPdfPageDrawer.NonStrokingComposite(const IsAntiAliased: Boolean): TPdfComposite;
begin
  Result := TPdfComposite.Default;
  Result.Alpha := LimitedAlpha(RenderState.NonStrokeAlphaConstant);
  Result.BlendMode := RenderState.BlendMode;
  Result.AntiAlias := (FParams.Options.AntiAlias and IsAntiAliased);
end;

function TPdfPageDrawer.StrokingComposite: TPdfComposite;
begin
  Result := TPdfComposite.Default;
  Result.Alpha := LimitedAlpha(RenderState.AlphaConstant);
  Result.BlendMode := RenderState.BlendMode;
  Result.AntiAlias := FParams.Options.AntiAlias;
end;

// getPaint for a colour that is not a pattern
function TPdfPageDrawer.SolidPaint(const Color: TPDColor): TPdfPaint;
begin
  Result := TPdfPaint.Solid(Color.ToRgb.ToDeviceColor);
end;

// PDFBOX-5168 and getDashArray. False when the dash pattern makes the line invisible.
function TPdfPageDrawer.TryBuildDashes(out Dashes: TArray<Single>; out Phase: Single): Boolean;
begin
  Dashes := nil;
  Phase := 0;
  const Pattern = RenderState.DashPattern;

  const DashCount = Length(Pattern.Dashes);
  var IsAllZero := (DashCount > 0);
  var IsUsable := (DashCount > 0);
  for var Dash in Pattern.Dashes do
  begin
    IsAllZero := (IsAllZero and (Dash = 0));
    IsUsable := (IsUsable and (not (IsNan(Dash) or IsInfinite(Dash))));
  end;
  if IsAllZero then
  begin
    Exit(False);
  end;

  Result := True;
  if not IsUsable then
  begin
    Exit;
  end;

  // The shortest dash that Java2D can draw; PDFBOX-4492 makes it longer when the page is drawn small
  var Shortest := MinimumDashLength;
  if FScalingFactorX < SmallScale then
  begin
    Shortest := MinimumDashLengthAtSmallScale;
  end;

  // An odd list starts again with the opposite meaning, which is the same as the list twice
  const RepeatCount = IfThen(Odd(DashCount), 2, 1);
  SetLength(Dashes, DashCount * RepeatCount);
  for var Index := 0 to High(Dashes) do
  begin
    Dashes[Index] := Max(TransformWidth(Pattern.Dashes[Index mod DashCount]), Shortest);
  end;

  Phase := TransformWidth(Pattern.Phase);
  if IsNan(Phase) or IsInfinite(Phase) or (Phase < 0) then
  begin
    Phase := 0;
  end;
  // PDFBOX-5653
  Phase := Min(Phase, MaximumDashPhase);
end;

// getStroke. False when nothing is to be drawn.
function TPdfPageDrawer.TryBuildStroke(out Stroke: TPdfStrokeStyle): Boolean;
begin
  Stroke := Default(TPdfStrokeStyle);

  var Phase: Single;
  if not TryBuildDashes(Stroke.Dashes, Phase) then
  begin
    Exit(False);
  end;
  Stroke.DashPhase := Phase;

  // The minimum line width is that of Adobe Reader
  var Width := TransformWidth(RenderState.LineWidth);
  if IsNan(Width) or IsInfinite(Width) or (Width < MinimumLineWidth) then
  begin
    Width := MinimumLineWidth;
  end;
  Stroke.Width := Width;

  Stroke.Cap := TPdfLineCap(Min(LargestStyleCode, Max(0, RenderState.LineCap)));
  Stroke.Join := TPdfLineJoin(Min(LargestStyleCode, Max(0, RenderState.LineJoin)));
  var MiterLimit := RenderState.MiterLimit;
  if not (MiterLimit >= 1) then
  begin
    LogWarning('Miter limit must be >= 1, value %g is ignored', [MiterLimit]);
    MiterLimit := DefaultMiterLimit;
  end;
  Stroke.MiterLimit := MiterLimit;
  Result := True;
end;

procedure TPdfPageDrawer.ApplyClip;
begin
  const Current = RenderState.Clip;
  if Current <> FLastClip then
  begin
    FDevice.SetClip(Current);
    FLastClip := Current;
  end;
end;

class function TPdfPageDrawer.FloorToInteger(const Value: Single): Integer;
begin
  if IsNan(Value) then
  begin
    Exit(0);
  end;
  if Value >= High(Integer) then
  begin
    Exit(High(Integer));
  end;
  if Value <= Low(Integer) then
  begin
    Exit(Low(Integer));
  end;
  Result := Floor(Value);
end;

// isRectangular: four points, and the first one shares a coordinate with the second, the third or the fourth. Like the iterator of Java
// it counts the points of lines and moves, fails at a curve and ignores a close.
class function TPdfPageDrawer.IsRectangular(const Path: TPdfPath): Boolean;
begin
  var Xs: array[0..RectangleCorners - 1] of Integer;
  var Ys: array[0..RectangleCorners - 1] of Integer;
  var Count := 0;
  var PointIndex := 0;

  for var VerbIndex := 0 to Path.VerbCount - 1 do
  begin
    case Path.Verb(VerbIndex) of
      TPdfPathVerb.MoveTo:
      begin
        if Count > 0 then
        begin
          Exit(False);
        end;
        Xs[Count] := FloorToInteger(Path.Point(PointIndex).X);
        Ys[Count] := FloorToInteger(Path.Point(PointIndex).Y);
        Inc(Count);
        Inc(PointIndex);
      end;
      TPdfPathVerb.LineTo:
      begin
        if Count >= RectangleCorners then
        begin
          Exit(False);
        end;
        Xs[Count] := FloorToInteger(Path.Point(PointIndex).X);
        Ys[Count] := FloorToInteger(Path.Point(PointIndex).Y);
        Inc(Count);
        Inc(PointIndex);
      end;
      TPdfPathVerb.QuadTo:
      begin
        Inc(PointIndex, 2);
      end;
      TPdfPathVerb.CubicTo:
      begin
        Exit(False);
      end;
    end;
  end;

  Result := ((Count = RectangleCorners) and ((Xs[0] = Xs[1]) or (Xs[0] = Xs[2]) or (Ys[0] = Ys[1]) or (Ys[0] = Ys[3])));
end;

// A path that is one point has no area and draws nothing
class function TPdfPageDrawer.IsPoint(const Path: TPdfPath): Boolean;
begin
  const Bounds = Path.Bounds;
  Result := ((Bounds.Right - Bounds.Left = 0) and (Bounds.Bottom - Bounds.Top = 0));
end;

class function TPdfPageDrawer.HasSegments(const Path: TPdfPath): Boolean;
begin
  Result := False;
  for var VerbIndex := 0 to Path.VerbCount - 1 do
  begin
    Result := (Result or (Path.Verb(VerbIndex) <> TPdfPathVerb.MoveTo));
  end;
end;

procedure TPdfPageDrawer.PaintFill(const Path: TPdfPath; const FillRule: TPdfFillRule);
begin
  if Path.IsEmpty or IsPoint(Path) then
  begin
    Exit;
  end;

  // Rectangles are not anti-aliased, to avoid small stripes where solid fills simulate piecewise gradients (PDFBOX-2302); paths of
  // no more than a point wide stand for lines and are anti-aliased (PDFBOX-1658)
  const Bounds = Path.Bounds;
  const IsLargeRectangle = (IsRectangular(Path) and (Bounds.Right - Bounds.Left > 1) and (Bounds.Bottom - Bounds.Top > 1));

  ApplyClip;
  const Paint = SolidPaint(RenderState.NonStrokingColor);
  FDevice.FillPath(Path, FPageToDevice, FillRule, Paint, NonStrokingComposite(not IsLargeRectangle));
end;

procedure TPdfPageDrawer.PaintStroke(const Path: TPdfPath);
begin
  var Stroke: TPdfStrokeStyle;
  if (not HasSegments(Path)) or (not TryBuildStroke(Stroke)) then
  begin
    Exit;
  end;

  ApplyClip;
  const Paint = SolidPaint(RenderState.StrokingColor);
  DrawStroke(Path, Stroke, Paint);
end;

// Java2D normalizes the geometry of a stroke, see TPdfStrokeNormalizer
procedure TPdfPageDrawer.DrawStroke(const Path: TPdfPath; const Stroke: TPdfStrokeStyle; const Paint: TPdfPaint);
begin
  const Normalized = TPdfStrokeNormalizer.Normalize(Path, FPageToDevice);
  try
    FDevice.StrokePath(Normalized, FPageToDevice, Stroke, Paint, StrokingComposite);
  finally
    Normalized.Free;
  end;
end;

procedure TPdfPageDrawer.StrokePath;
begin
  try
    PaintStroke(FLinePath);
  finally
    FLinePath.Clear;
  end;
end;

procedure TPdfPageDrawer.FillPath(const FillRule: TPdfFillRule);
begin
  try
    PaintFill(FLinePath, FillRule);
  finally
    FLinePath.Clear;
  end;
end;

procedure TPdfPageDrawer.FillAndStrokePath(const FillRule: TPdfFillRule);
begin
  try
    PaintFill(FLinePath, FillRule);
    PaintStroke(FLinePath);
  finally
    FLinePath.Clear;
  end;
end;

procedure TPdfPageDrawer.ShadingFill(const ShadingName: string);
begin
  LogWarning('Shading fills are not drawn yet: %s skipped', [ShadingName]);
end;

// PDFBOX-5715: below a scale of one, a clip that is thinner than two pixels is made two pixels wide, so that the lines that are drawn
// inside it do not vanish. The bounds are those of Java's Shape.getBounds, in whole points. Without rotation only; the result is Path
// itself or a new path that the caller frees.
function TPdfPageDrawer.AdjustedClip(const Path: TPdfPath): TPdfPath;
begin
  Result := Path;
  const HasRotation = ((FPageToDevice.ShearX <> 0) or (FPageToDevice.ShearY <> 0));
  const ScaleX = Abs(FPageToDevice.ScaleX);
  const ScaleY = Abs(FPageToDevice.ScaleY);
  const IsUnscaled = ((ScaleX = 1) and (ScaleY = 1));
  const IsEnlarged = ((ScaleX > 1) and (ScaleY > 1));
  const IsDegenerate = ((ScaleX = 0) or (ScaleY = 0));
  if HasRotation or IsUnscaled or IsEnlarged or IsDegenerate then
  begin
    Exit;
  end;

  const Bounds = Path.Bounds;
  const IsHuge = (Max(Max(Abs(Bounds.Left), Abs(Bounds.Top)), Max(Abs(Bounds.Right), Abs(Bounds.Bottom))) > MaximumAdjustedCoordinate);
  if IsHuge then
  begin
    Exit;
  end;

  const Left = Floor(Bounds.Left);
  const Top = Floor(Bounds.Top);
  var X: Double := Left;
  var Y: Double := Top;
  var Width: Double := Ceil(Bounds.Right) - Left;
  var Height: Double := Ceil(Bounds.Bottom) - Top;
  const CenterX = X + Width * Half;
  const CenterY = Y + Height * Half;
  const IsNarrow = (ScaleX * Width < MinimumClipSize);
  const IsLow = (ScaleY * Height < MinimumClipSize);
  if not (IsNarrow or IsLow) then
  begin
    Exit;
  end;

  if IsNarrow then
  begin
    Width := MinimumClipSize / ScaleX;
    X := CenterX - Width * Half;
  end;
  if IsLow then
  begin
    Height := MinimumClipSize / ScaleY;
    Y := CenterY - Height * Half;
  end;

  Result := TPdfPath.Create;
  Result.MoveTo(X, Y);
  Result.LineTo(X + Width, Y);
  Result.LineTo(X + Width, Y + Height);
  Result.LineTo(X, Y + Height);
  Result.ClosePath;
end;

procedure TPdfPageDrawer.Clip(const FillRule: TPdfFillRule);
begin
  // PDFBOX-4949: "W n" with nothing in the path does not clip
  if not FLinePath.IsEmpty then
  begin
    const Adjusted = AdjustedClip(FLinePath);
    try
      RenderState.IntersectClip(Adjusted, FPageToDevice, FillRule);
    finally
      if Adjusted <> FLinePath then
      begin
        Adjusted.Free;
      end;
    end;
  end;

  // PDFBOX-3836: the new clip has to be set on the device before the next paint
  FLastClip := nil;
end;

// The path is made the way PageDrawer does it, by lines and a close, so that a line cap is not drawn at the start of the rectangle
procedure TPdfPageDrawer.AppendRectangle(const P0, P1, P2, P3: TPointF);
begin
  FLinePath.MoveTo(P0.X, P0.Y);
  FLinePath.LineTo(P1.X, P1.Y);
  FLinePath.LineTo(P2.X, P2.Y);
  FLinePath.LineTo(P3.X, P3.Y);
  FLinePath.ClosePath;
end;

procedure TPdfPageDrawer.MoveTo(const X, Y: Single);
begin
  FLinePath.MoveTo(X, Y);
end;

procedure TPdfPageDrawer.LineTo(const X, Y: Single);
begin
  FLinePath.LineTo(X, Y);
end;

procedure TPdfPageDrawer.CurveTo(const X1, Y1, X2, Y2, X3, Y3: Single);
begin
  FLinePath.CubicTo(X1, Y1, X2, Y2, X3, Y3);
end;

function TPdfPageDrawer.TryGetCurrentPoint(out Point: TPointF): Boolean;
begin
  Result := FLinePath.HasCurrentPoint;
  if Result then
  begin
    Point := FLinePath.CurrentPoint;
  end
  else
  begin
    Point := TPointF.Zero;
  end;
end;

procedure TPdfPageDrawer.ClosePath;
begin
  FLinePath.ClosePath;
end;

procedure TPdfPageDrawer.EndPath;
begin
  FLinePath.Clear;
end;

// beginTextClip: the text clip starts empty
procedure TPdfPageDrawer.BeginText;
begin
  FTextClip.Clear;
end;

// endTextClip: the glyphs of the clipping modes become the clip. Like PDFBox this reads the rendering mode at ET.
procedure TPdfPageDrawer.EndText;
begin
  try
    if RenderState.TextState.RenderingMode.IsClip and (not FTextClip.IsEmpty) then
    begin
      RenderState.IntersectClip(FTextClip, FPageToDevice, TPdfFillRule.NonZero);
      FLastClip := nil;
    end;
  finally
    FTextClip.Clear;
  end;
end;

procedure TPdfPageDrawer.ShowGlyph(const TextRenderingMatrix: TPdfMatrix; const Font: TPDFont; const Code: Integer;
                                   const Displacement: TPdfVector);
begin
  if Font is TPDType3Font then
  begin
    // PageDrawer.showType3Glyph: invisible text is not run
    if RenderState.TextState.RenderingMode <> TRenderingMode.Neither then
    begin
      ShowType3Glyph(TextRenderingMatrix, TPDType3Font(Font), Code);
    end;
  end
  else
  begin
    ShowFontGlyph(TextRenderingMatrix, Font, Code, Displacement);
  end;
end;

class function TPdfPageDrawer.IsFinitePath(const Path: TPdfPath): Boolean;
begin
  const Bounds = Path.Bounds;
  Result := (not (IsNan(Bounds.Left) or IsInfinite(Bounds.Left) or IsNan(Bounds.Top) or IsInfinite(Bounds.Top) or
                  IsNan(Bounds.Right) or IsInfinite(Bounds.Right) or IsNan(Bounds.Bottom) or IsInfinite(Bounds.Bottom)));
end;

// The path of the font program to page space: the font matrix and the text rendering matrix, with the stretch of a glyph of a font that
// is not embedded (drawGlyph), when it is not a standard 14 font and has a width of its own in the PDF. A vertical font is not stretched: its
// displacement has no horizontal part, which would flatten the glyph.
function TPdfPageDrawer.GlyphMatrix(const TextRenderingMatrix: TPdfMatrix; const Font: TPDFont; const Code: Integer;
                                    const Displacement: TPdfVector): TPdfMatrix;
begin
  Result := Font.GetFontMatrix.Multiply(TextRenderingMatrix);
  const IsStretchable = ((not Font.IsEmbedded) and (not Font.IsVertical) and (not Font.IsStandard14) and Font.HasExplicitWidth(Code));
  if not IsStretchable then
  begin
    Exit;
  end;

  // PDFBOX-5611: a width of zero in the PDF is ignored
  const FontWidth = Font.GetWidthFromFont(Code);
  const PdfWidth = Displacement.X * Thousand;
  if (Displacement.X > 0) and (FontWidth > 0) and (Abs(FontWidth - PdfWidth) > WidthTolerance) then
  begin
    Result := TPdfMatrix.GetScaleInstance(PdfWidth / FontWidth, 1).Multiply(Result);
  end;
end;

procedure TPdfPageDrawer.ShowFontGlyph(const TextRenderingMatrix: TPdfMatrix; const Font: TPDFont; const Code: Integer;
                                       const Displacement: TPdfVector);
begin
  var FontPath: TPdfPath;
  if not FRenderer.GlyphCache.TryGetPath(Font, Code, FontPath) then
  begin
    Exit;
  end;

  const GlyphPath = FontPath.Clone;
  try
    GlyphPath.Transform(GlyphMatrix(TextRenderingMatrix, Font, Code, Displacement));
    DrawGlyph(GlyphPath);
  finally
    GlyphPath.Free;
  end;
end;

// drawGlyph, from the point where the glyph is a shape in page space
procedure TPdfPageDrawer.DrawGlyph(const GlyphPath: TPdfPath);
begin
  if not IsFinitePath(GlyphPath) then
  begin
    LogError('A glyph is skipped: it does not give finite coordinates', []);
    Exit;
  end;

  const Mode = RenderState.TextState.RenderingMode;
  if Mode.IsFill and (not GlyphPath.IsEmpty) then
  begin
    ApplyClip;
    FDevice.FillPath(GlyphPath, FPageToDevice, TPdfFillRule.NonZero, SolidPaint(RenderState.NonStrokingColor), NonStrokingComposite(True));
  end;

  var Stroke: TPdfStrokeStyle;
  if Mode.IsStroke and HasSegments(GlyphPath) and TryBuildStroke(Stroke) then
  begin
    ApplyClip;
    DrawStroke(GlyphPath, Stroke, SolidPaint(RenderState.StrokingColor));
  end;

  if Mode.IsClip then
  begin
    FTextClip.Append(GlyphPath);
  end;
end;

procedure TPdfPageDrawer.LogMissingCharProc(const Font: TPDType3Font; const Code: Integer);
begin
  const Key = ((Int64(Code and CodeMask) shl CodeShift) xor Int64(NativeInt(Font.CosObject)));
  if (FLoggedMissingGlyphs.Count < MaximumLoggedMissingGlyphs) and (not FLoggedMissingGlyphs.ContainsKey(Key)) then
  begin
    FLoggedMissingGlyphs.Add(Key, True);
    LogWarning('No glyph procedure for code %d in Type 3 font %s, the glyph is skipped', [Code, Font.Name]);
  end;
end;

// showType3Glyph: the procedure runs with the text rendering matrix, scaled by the font matrix, as CTM
procedure TPdfPageDrawer.ShowType3Glyph(const TextRenderingMatrix: TPdfMatrix; const Font: TPDType3Font; const Code: Integer);
begin
  var CharProc: TPDType3CharProc;
  if not Font.TryGetCharProc(Code, CharProc) then
  begin
    LogMissingCharProc(Font, Code);
    Exit;
  end;

  if FType3Depth >= Max(FParams.Options.MaxType3Depth, 1) then
  begin
    LogWarning('Type 3 glyphs are nested as deep as the limit of %d, the glyph is skipped', [FParams.Options.MaxType3Depth]);
    Exit;
  end;

  RunType3CharProc(Font, CharProc, TextRenderingMatrix);
end;

procedure TPdfPageDrawer.RunType3CharProc(const Font: TPDType3Font; const CharProc: TPDType3CharProc; const TextRenderingMatrix: TPdfMatrix);
begin
  var Resources: TCosDictionary;
  if not CharProc.TryGetResources(Resources) then
  begin
    Resources := nil;
  end;

  const State = GraphicsState.Clone;
  State.CurrentTransformationMatrix := Font.GetFontMatrix.Multiply(TextRenderingMatrix);

  Inc(FType3Depth);
  try
    ProcessType3CharProc(CharProc.Stream, Resources, State);
  finally
    Dec(FType3Depth);
  end;
end;

// Java's Math.round: half up
function RoundHalfUp(const Value: Single): Int64;
begin
  if IsNan(Value) then
  begin
    Exit(0);
  end;
  if Abs(Value) >= High(Integer) then
  begin
    Exit(Sign(Value) * Int64(High(Integer)));
  end;
  Result := Floor(Double(Value) + Half);
end;

// The filter of drawImage: an image that is not scaled up gets the smooth (bicubic) interpolation of the rendering hints, also when
// it is scaled down (PDFBOX-2364); an image that is scaled up gets the nearest neighbour unless it says /Interpolate (PDFBOX-2302)
function TPdfPageDrawer.ImageFilter(const Image: TPDImage; const Width, Height: Integer): TPdfImageFilter;
begin
  if Image.Interpolate then
  begin
    Exit(TPdfImageFilter.Bicubic);
  end;

  const Matrix = GraphicsState.CurrentTransformationMatrix;
  const IsScaledUp = ((Width <= Abs(RoundHalfUp(Matrix.ScalingFactorX * FScalingFactorX))) or
                      (Height <= Abs(RoundHalfUp(Matrix.ScalingFactorY * FScalingFactorY))));
  if IsScaledUp then
  begin
    Result := TPdfImageFilter.Nearest;
  end
  else
  begin
    Result := TPdfImageFilter.Bicubic;
  end;
end;

// drawBufferedImage: the pixel (i, j) of the bitmap covers [i, i + 1] x [j, j + 1] in a unit square that the CTM maps to the page
procedure TPdfPageDrawer.DrawImageBitmap(const Image: TPDImage; const Bitmap: TPdfBitmap);
begin
  var ImageTransform: TPdfMatrix;
  var BitmapToDevice: TPdfMatrix;
  try
    ImageTransform := ImageToPage(Bitmap.Width, Bitmap.Height);
    BitmapToDevice := ImageTransform.Multiply(FPageToDevice);
  except
    on Error: EPdfException do
    begin
      LogError('An image is skipped: the transformation does not give finite coordinates', []);
      Exit;
    end;
  end;

  const Filter = ImageFilter(Image, Bitmap.Width, Bitmap.Height);
  // PDFBOX-4516 and others: Java2D scales down badly, so an image that is drawn small gets averaged down to its size first, and
  // that smaller image is drawn at the same place. It only happens with the bicubic interpolation of the rendering hints.
  var Scaled: TPdfBitmap := nil;
  if (Filter = TPdfImageFilter.Bicubic) and TryScaleDown(Bitmap, ImageTransform, Scaled) then
  begin
    try
      BitmapToDevice := ImageToPage(Scaled.Width, Scaled.Height).Multiply(FPageToDevice);
      ApplyClip;
      FDevice.DrawBitmap(Scaled, BitmapToDevice, Filter, NonStrokingComposite(True));
    finally
      Scaled.Free;
    end;
    Exit;
  end;

  ApplyClip;
  FDevice.DrawBitmap(Bitmap, BitmapToDevice, Filter, NonStrokingComposite(True));
end;

// The matrix that puts the pixel (i, j) of an image of Width x Height pixels on [i, i + 1] x [j, j + 1] of the unit square of the CTM
function TPdfPageDrawer.ImageToPage(const Width, Height: Integer): TPdfMatrix;
begin
  const UnitSquare = TPdfMatrix.GetTranslateInstance(0, -Height).Multiply(TPdfMatrix.GetScaleInstance(1 / Width, -1 / Height));
  Result := UnitSquare.Multiply(GraphicsState.CurrentTransformationMatrix);
end;

// The scaling of drawBufferedImage that PDFBox applies before it draws an image that is shown smaller than the threshold in one
// direction: the size on the device is the size of the image in pixels times the scale of the image and the device, rounded. An
// image that would become larger than the image limit is drawn as it is.
function TPdfPageDrawer.TryScaleDown(const Bitmap: TPdfBitmap; const ImageTransform: TPdfMatrix; out Scaled: TPdfBitmap): Boolean;
begin
  Scaled := nil;
  const ScaleX = Abs(ImageTransform.ScalingFactorX * FPageToDevice.ScalingFactorX);
  const ScaleY = Abs(ImageTransform.ScalingFactorY * FPageToDevice.ScalingFactorY);
  if not ((ScaleX < ImageDownscalingThreshold) or (ScaleY < ImageDownscalingThreshold)) then
  begin
    Exit(False);
  end;

  const Width = RoundHalfUp(Bitmap.Width * ScaleX);
  const Height = RoundHalfUp(Bitmap.Height * ScaleY);
  if (Width < 1) or (Height < 1) or (Width * Height > Max(FParams.Options.MaxImagePixels, 1)) then
  begin
    Exit(False);
  end;

  Scaled := TPdfImageScaler.ScaleSmooth(Bitmap, Integer(Width), Integer(Height));
  Result := True;
end;

// The mask becomes the paint colour where it paints: the bitmap of getStencilImage(getNonStrokingPaint()). False when the colour has
// no RGB value (a pattern that is not painted yet).
function TPdfPageDrawer.TryMakeStencilBitmap(const Mask: TPdfBitmap): Boolean;
begin
  var Color: TPdfDeviceColor;
  try
    Color := SolidPaint(RenderState.NonStrokingColor).Color;
  except
    on Error: Exception do
    begin
      const IsRecoverable = ((Error is EPdfException) or (Error is EInvalidOpException) or (Error is EArgumentException));
      if not IsRecoverable then
      begin
        raise;
      end;
      LogWarning('A stencil mask is skipped: its colour is not painted yet: %s', [Error.Message]);
      Exit(False);
    end;
  end;

  for var Y := 0 to Mask.Height - 1 do
  begin
    const Row = Mask.ScanLine(Y);
    for var X := 0 to Mask.Width - 1 do
    begin
      if Row[X * 4 + 3] <> 0 then
      begin
        Row[X * 4] := Color.R;
        Row[X * 4 + 1] := Color.G;
        Row[X * 4 + 2] := Color.B;
      end;
    end;
  end;
  Result := True;
end;

procedure TPdfPageDrawer.DrawStencil(const Image: TPDImage);
begin
  var Mask: TPdfBitmap;
  if not Image.TryGetStencilMask(FParams.Options.MaxImagePixels, Mask) then
  begin
    Exit;
  end;

  try
    if TryMakeStencilBitmap(Mask) then
    begin
      DrawImageBitmap(Image, Mask);
    end;
  finally
    Mask.Free;
  end;
end;

procedure TPdfPageDrawer.DrawImage(const Image: TPDImage);
begin
  if Image.IsStencil then
  begin
    DrawStencil(Image);
    Exit;
  end;

  var Bitmap: TPdfBitmap;
  if not Image.TryGetImage(FParams.Options.MaxImagePixels, Bitmap) then
  begin
    Exit;
  end;

  try
    DrawImageBitmap(Image, Bitmap);
  finally
    Bitmap.Free;
  end;
end;

// showTransparencyGroup, with the depth limit of the options
procedure TPdfPageDrawer.ShowTransparencyGroup(const Form: TPDFormXObject);
begin
  if FGroupDepth >= Max(FParams.Options.MaxTransparencyGroupDepth, 1) then
  begin
    if not FHasLoggedGroupDepth then
    begin
      FHasLoggedGroupDepth := True;
      LogWarning('Transparency groups are nested as deep as the limit of %d, the group is skipped', [FParams.Options.MaxTransparencyGroupDepth]);
    end;
    Exit;
  end;

  var Bounds: TRect;
  if not TryGetGroupBounds(Form, Bounds) then
  begin
    Exit;
  end;

  Inc(FGroupDepth);
  try
    DrawGroup(Form, Bounds);
  finally
    Dec(FGroupDepth);
  end;
end;

// The area is cut with the bounds of each path of the clip chain: a chain of rectangles gives the exact intersection, another shape a
// slightly larger area, which only costs a few pixels of layer
function TPdfPageDrawer.IntersectedWithClips(const Area: TRectF): TRectF;
begin
  Result := Area;
  var Link := RenderState.Clip;
  while Assigned(Link) and (not Result.IsEmpty) do
  begin
    const Shape = Link.Path.Clone;
    try
      Shape.Transform(Link.Transform);
      Result := TRectF.Intersect(Result, Shape.Bounds);
    finally
      Shape.Free;
    end;
    Link := Link.Parent;
  end;
end;

// The bounds of TransparencyGroup in device pixels: the BBox with the CTM and the matrix of the form, the clip and the device. False
// when nothing of the group can be seen.
function TPdfPageDrawer.TryGetGroupBounds(const Form: TPDFormXObject; out Bounds: TRect): Boolean;
begin
  Bounds := TRect.Empty;
  var Area := TRectF.Create(0, 0, FDevice.Width, FDevice.Height);

  var BBox: TPdfRectangle;
  if Form.TryGetBBox(BBox) then
  begin
    var Matrix := GraphicsState.CurrentTransformationMatrix;
    Matrix.ConcatenateWith(Form.Matrix);
    const Box = PathAround(BBox, Matrix);
    try
      Box.Transform(FPageToDevice);
      if not IsFinitePath(Box) then
      begin
        LogError('A transparency group is skipped: its bounding box does not give finite coordinates', []);
        Exit(False);
      end;
      Area := TRectF.Intersect(Area, Box.Bounds);
    finally
      Box.Free;
    end;
  end;

  Area := IntersectedWithClips(Area);
  if Area.IsEmpty then
  begin
    Exit(False);
  end;

  Bounds := TRect.Create(Floor(Area.Left), Floor(Area.Top), Ceil(Area.Right), Ceil(Area.Bottom));
  Result := (not Bounds.IsEmpty);
end;

// The clip chain in the pixels of a layer whose top left corner lies at (-OffsetX, -OffsetY) of the device
class function TPdfPageDrawer.TranslatedClip(const Clip: IPdfClipPath; const OffsetX, OffsetY: Integer): IPdfClipPath;
begin
  Result := nil;
  const Chain = TList<IPdfClipPath>.Create;
  try
    var Link := Clip;
    while Assigned(Link) do
    begin
      Chain.Add(Link);
      Link := Link.Parent;
    end;

    const Shift = TPdfMatrix.GetTranslateInstance(OffsetX, OffsetY);
    for var Index := Chain.Count - 1 downto 0 do
    begin
      const Original = Chain[Index];
      Result := TPdfClipPath.Create(Result, Original.Path.Clone, Original.Transform.Multiply(Shift), Original.FillRule);
    end;
  finally
    Chain.Free;
  end;
end;

class function TPdfPageDrawer.HasBlendModeState(const Resources: TCosDictionary): Boolean;
begin
  Result := False;
  var States: TCosDictionary;
  if not Resources.TryGetCosDictionary(TCosNames.ExtGState, States) then
  begin
    Exit;
  end;

  for var Name in States.Keys do
  begin
    var Dictionary: TCosDictionary;
    if States.TryGetCosDictionary(Name, Dictionary) then
    begin
      const State = TPDExtendedGraphicsState.Create(Dictionary);
      try
        if State.GetBlendModeName <> TCosNames.Normal then
        begin
          Exit(True);
        end;
      finally
        State.Free;
      end;
    end;
  end;
end;

class function TPdfPageDrawer.HasBlendModeChild(const Resources: TCosDictionary; const Done: TList<TCosStream>): Boolean;
begin
  Result := False;
  var XObjects: TCosDictionary;
  if not Resources.TryGetCosDictionary(TCosNames.XObject, XObjects) then
  begin
    Exit;
  end;

  for var Name in XObjects.Keys do
  begin
    var Stream: TCosStream;
    if XObjects.TryGetCosStream(Name, Stream) then
    begin
      const Child = TPDFormXObject.Create(Stream);
      try
        if Child.IsTransparencyGroup and HasBlendMode(Child, Done) then
        begin
          Exit(True);
        end;
      finally
        Child.Free;
      end;
    end;
  end;
end;

// hasBlendMode: a group, or a group inside it, whose resources have an ExtGState with another blend mode than Normal. A group that is
// met twice counts once, so that a group that draws itself ends.
class function TPdfPageDrawer.HasBlendMode(const Form: TPDFormXObject; const Done: TList<TCosStream>): Boolean;
begin
  Result := False;
  if Done.Contains(Form.Stream) then
  begin
    Exit;
  end;
  Done.Add(Form.Stream);

  var Resources: TCosDictionary;
  if Form.TryGetResources(Resources) then
  begin
    Result := (HasBlendModeState(Resources) or HasBlendModeChild(Resources, Done));
  end;
end;

// A group that is not isolated shows the backdrop to the blend modes inside it; without a blend mode the backdrop changes nothing
function TPdfPageDrawer.NeedsBackdrop(const Form: TPDFormXObject): Boolean;
begin
  var Group: TPDTransparencyGroupAttributes;
  Result := (Form.TryGetGroup(Group) and (not Group.IsIsolated));
  if Result then
  begin
    const Done = TList<TCosStream>.Create;
    try
      Result := HasBlendMode(Form, Done);
    finally
      Done.Free;
    end;
  end;
end;

// The backdrop is copied as it is
function TPdfPageDrawer.BackdropComposite: TPdfComposite;
begin
  Result := TPdfComposite.Default;
  Result.AntiAlias := False;
end;

// TransparencyGroup and showTransparencyGroupOnGraphics: the group is drawn on a layer of its own, which then is drawn on the device
// with the alpha constant and the blend mode of the graphics state. The layer starts at the top left of Bounds.
procedure TPdfPageDrawer.DrawGroup(const Form: TPDFormXObject; const Bounds: TRect);
begin
  var Backdrop: TPdfBitmap := nil;
  if NeedsBackdrop(Form) and (not FDevice.TryReadPixels(Bounds, Backdrop)) then
  begin
    Backdrop := nil;
  end;

  try
    const Image = FDevice.CreateLayer(Bounds.Width, Bounds.Height);
    var Alpha: IPdfRasterDevice := nil;
    if Assigned(Backdrop) then
    begin
      Alpha := FDevice.CreateLayer(Bounds.Width, Bounds.Height);
      Image.DrawBitmap(Backdrop, TPdfMatrix.Identity, TPdfImageFilter.Nearest, BackdropComposite);
    end;

    const Reference: IPdfRasterDevice = TPdfGroupDevice.Create(Image, Alpha);
    RunGroupContent(Form, Reference, Bounds);
    if Assigned(Backdrop) then
    begin
      TPdfGroupDevice(Reference).RemoveBackdrop(Backdrop, 0, 0);
    end;
    DrawGroupResult(TPdfGroupDevice(Reference), Bounds);
  finally
    Backdrop.Free;
  end;
end;

// The group draws on the layer: the matrix to the device moves by the corner of the layer, and so does the clip
procedure TPdfPageDrawer.RunGroupContent(const Form: TPDFormXObject; const GroupDevice: IPdfRasterDevice; const Bounds: TRect);
begin
  const SavedDevice = FDevice;
  const SavedMatrix = FPageToDevice;
  FDevice := GroupDevice;
  FPageToDevice := SavedMatrix.Multiply(TPdfMatrix.GetTranslateInstance(-Bounds.Left, -Bounds.Top));
  FLastClip := nil;
  try
    RunGroupStream(Form, Bounds);
  finally
    FDevice := SavedDevice;
    FPageToDevice := SavedMatrix;
    FLastClip := nil;
  end;
end;

// processTransparencyGroup: the blend mode starts at Normal, the alpha constants at 1 (and the soft mask at none)
procedure TPdfPageDrawer.RunGroupStream(const Form: TPDFormXObject; const Bounds: TRect);
begin
  const State = TPdfRenderGraphicsState(GraphicsState.Clone);
  try
    State.Clip := TranslatedClip(State.Clip, -Bounds.Left, -Bounds.Top);
    State.BlendMode := TPdfBlendMode.Normal;
    State.AlphaConstant := 1;
    State.NonStrokeAlphaConstant := 1;
  except
    State.Free;
    raise;
  end;
  ProcessFormWithState(Form, State);
end;

procedure TPdfPageDrawer.DrawGroupResult(const GroupDevice: TPdfGroupDevice; const Bounds: TRect);
begin
  const Image = GroupDevice.ToBitmap;
  try
    ApplyClip;
    FDevice.DrawBitmap(Image, TPdfMatrix.GetTranslateInstance(Bounds.Left, Bounds.Top), TPdfImageFilter.Nearest, NonStrokingComposite(False));
  finally
    Image.Free;
  end;
end;

end.
