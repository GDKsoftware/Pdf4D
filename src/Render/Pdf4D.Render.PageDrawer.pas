// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/rendering/PageDrawer.java (3.0.8): drawPage, setClip, getStroke, getDashArray,
// strokePath, fillPath, fillAndStrokePath, clip, adjustClip, endPath and the path construction; the paint is the solid colour of
// getPaint, and showFontGlyph, drawGlyph, beginText, endText, beginTextClip and endTextClip, and drawImage and drawBufferedImage with the
// transfer function and the soft mask of the graphics state (the soft mask itself is made by Pdf4D.Render.SoftMaskPaint), and showTransparencyGroup
// with the inner class TransparencyGroup (bounds, backdrop, the group of a soft mask) and hasBlendMode, and shadingFill, intersectShadingBBox and the shading
// paint of getPaint (shading patterns as fill and stroke colour; the shading itself is made by Pdf4D.Render.Shading.Context), and the tiling patterns of
// getPaint with drawTilingPattern (the cell is made by Pdf4D.Render.TilingPaint, which ports TilingPaint and TilingPaintFactory).
// Port of: pdfbox/src/main/java/org/apache/pdfbox/contentstream/PDFStreamEngine.java (3.0.8), transformWidth, clipToRect, showGlyph,
// showType3Glyph and processTilingPattern
// Port of: pdfbox/src/main/java/org/apache/pdfbox/rendering/PageDrawer.java (3.0.8), the optional content and annotation part: the nested count of
// hidden marked content (beginMarkedContentSequence, endMarkedContentSequence, isContentRendered), /OC of images and forms, showAnnotation and
// shouldSkipAnnotation, and the annotation loop of drawPage; the decisions about optional content are made by Pdf4D.Render.OptionalContent
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
  Pdf4D.Graphics.Pattern,
  Pdf4D.Graphics.Shading,
  Pdf4D.Graphics.SoftMask,
  Pdf4D.Model.Annotation,
  Pdf4D.Model.FormXObject,
  Pdf4D.Model.OptionalContent,
  Pdf4D.Model.Page,
  Pdf4D.Model.Rectangle,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Render.GraphicsEngine,
  Pdf4D.Render.GroupDevice,
  Pdf4D.Render.OptionalContent,
  Pdf4D.Render.Renderer,
  Pdf4D.Render.Renderer.Interfaces,
  Pdf4D.Render.Shading.Context,
  Pdf4D.Render.TilingPaint;

type
  // What is done with the paint of a pattern while its bitmap exists
  TPdfPaintAction = reference to procedure(const Paint: TPdfPaint);

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
    // What the Single translation of FPageToDevice lacks of the double one that PDFBox has; only the stroke normalization needs it
    FTranslationResidualX: Double;
    FTranslationResidualY: Double;
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
    FSoftMaskDepth: Integer;
    FHasLoggedSoftMaskDepth: Boolean;
    FHasLoggedClipDepth: Boolean;
    // The last clip chain that was moved into the pixels of a group layer, with the offset it was moved by: the groups of one clip share it
    FTranslatedSource: IPdfClipPath;
    FTranslatedOffset: TPoint;
    FTranslatedResult: IPdfClipPath;
    // How many clip paths the translated chains of the groups of this page may still copy; a page of many groups with different clips
    // and a deep clip chain would otherwise copy the whole chain again and again
    FTranslatedLinkBudget: Integer;
    FHasLoggedClipCut: Boolean;
    // The last soft mask that was made, for the state, matrix and device size it was made for; nil for a soft mask that draws nothing
    FCachedMaskSource: IPdfSoftMask;
    FCachedMaskMatrix: TPdfMatrix;
    FCachedMaskWidth: Integer;
    FCachedMaskHeight: Integer;
    FCachedMask: TPdfAlphaMask;
    // The shadings and shading patterns that were made, by the dictionary they come from; a nil value is one that could not be made
    FShadings: TObjectDictionary<TCosDictionary, TPDShading>;
    FShadingPatterns: TObjectDictionary<TCosDictionary, TPDShadingPattern>;
    // The same for the tiling patterns, which are views on their streams
    FTilingPatterns: TObjectDictionary<TCosDictionary, TPDTilingPattern>;
    // TilingPaintFactory: the cells that were made. Nil only while the drawer is being made or destroyed.
    FTilingPaints: TPdfTilingPaintFactory;
    // The patterns whose cells are being drawn, inside each other
    FPatternDepth: Integer;
    FHasLoggedPatternDepth: Boolean;
    // The work that all shadings of the page share
    FShadingBudget: TPdfShadingBudget;
    // The warnings of the tiling paint that are in the log, so that a pattern that is used on every glyph gives one line
    FLoggedTilingWarnings: TDictionary<string, Boolean>;
    FVisibility: TPdfOptionalContentVisibility;
    // PageDrawer.nestedHiddenOCGCount: the depth of the marked-content sequences inside the first one that is hidden, 0 when content is shown
    FHiddenDepth: Integer;
    // While the annotation of a rotated page is drawn against the rotation (NoRotate), FPageToDevice holds that rotation
    FIsAnnotationTurned: Boolean;

    function IsContentRendered: Boolean;
    function IsFormHidden(const Form: TPDFormXObject): Boolean;
    function IsImageHidden(const Image: TPDImage): Boolean;
    function ShouldSkipAnnotation(const Annotation: TPDAnnotation): Boolean;
    procedure ShowTurnedAnnotation(const Annotation: TPDAnnotation);
    procedure DrawAnnotations;
    function TryShowAnnotation(const Annotation: TPDAnnotation): Boolean;
    function TransformWidth(const Width: Single): Single;
    function PlainNonStrokingComposite(const IsAntiAliased: Boolean): TPdfComposite;
    function NonStrokingComposite(const IsAntiAliased: Boolean): TPdfComposite;
    function ImageComposite(const Image: TPDImage): TPdfComposite;
    function StrokingComposite: TPdfComposite;
    function CurrentSoftMask: TPdfAlphaMask;
    function IsSoftMaskCached(const Mask: IPdfSoftMask): Boolean;
    function BuildSoftMask(const Mask: IPdfSoftMask): TPdfAlphaMask;
    function SolidPaint(const Color: TPDColor): TPdfPaint;
    function TryGetShading(const Value: TCosBase; out Shading: TPDShading): Boolean;
    function TryGetPatternValue(const Color: TPDColor; out Value: TCosBase): Boolean;
    class function IsTilingPattern(const Value: TCosBase): Boolean; static;
    function TryGetShadingPattern(const Color: TPDColor; const Value: TCosBase; out Pattern: TPDShadingPattern): Boolean;
    function TryGetTilingPattern(const Color: TPDColor; const Value: TCosBase; out Pattern: TPDTilingPattern): Boolean;
    class function IsPatternColor(const Color: TPDColor): Boolean; static;
    class function UnderlyingColorSpace(const Color: TPDColor): TPDColorSpace; static;
    function IsPatternDepthReached: Boolean;
    procedure LogTilingWarning(const Fmt: string; const Args: array of const);
    procedure WithShadingPaint(const Color: TPDColor; const Value: TCosBase; const Bounds: TRectF; const Action: TPdfPaintAction);
    procedure WithTilingPaint(const Color: TPDColor; const Value: TCosBase; const Bounds: TRectF; const Action: TPdfPaintAction);
    function CreateTilingState(const Pattern: TPDTilingPattern; const ColorSpace: TPDColorSpace; const Color: TPDColor): TPDGraphicsState;
    class function DeviceBoundsOf(const Path: TPdfPath; const Transform: TPdfMatrix): TRectF; static;
    class function WholePixels(const Area: TRectF): TRect; static;
    function StrokeBoundsOf(const Path: TPdfPath; const Stroke: TPdfStrokeStyle): TRectF;
    function TryGetPatternArea(const Bounds: TRectF; const BoxPath: TPdfPath; out Area: TRect): Boolean;
    procedure WithPatternPaint(const Color: TPDColor; const Bounds: TRectF; const Action: TPdfPaintAction);
    procedure PaintShadingArea(const Shading: TPDShading; const ShadingToDevice: TPdfMatrix; const Area: TRect; const Action: TPdfPaintAction);
    procedure FillShadingArea(const Shading: TPDShading; const ShadingToDevice: TPdfMatrix; const Area: TRect; const BoxPath: TPdfPath);
    procedure FillWithColor(const Path: TPdfPath; const FillRule: TPdfFillRule; const Color: TPDColor; const IsAntiAliased: Boolean);
    procedure StrokeWithColor(const Path: TPdfPath; const Stroke: TPdfStrokeStyle; const Color: TPDColor);
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
    procedure ApplyTransferFunction(const Bitmap: TPdfBitmap);
    function TryGetGroupBounds(const Form: TPDFormXObject; const Ctm: TPdfMatrix; const UsesClips: Boolean; out Bounds: TRect; out Shift: Single): Boolean;
    function GroupShift(const Area: TRectF): Single;
    function IntersectedWithClips(const Area: TRectF): TRectF;
    class function TranslatedClip(const Clip: IPdfClipPath; const OffsetX, OffsetY, MaxLinks: Integer): IPdfClipPath; static;
    class function ChainLength(const Clip: IPdfClipPath): Integer; static;
    function SharedTranslatedClip(const Clip: IPdfClipPath; const OffsetX, OffsetY: Integer): IPdfClipPath;
    procedure IntersectStateClip(const Path: TPdfPath; const FillRule: TPdfFillRule);
    class function HasBlendMode(const Form: TPDFormXObject; const Done: TList<TCosStream>): Boolean; static;
    class function HasBlendModeState(const Resources: TCosDictionary): Boolean; static;
    class function HasBlendModeChild(const Resources: TCosDictionary; const Done: TList<TCosStream>): Boolean; static;
    function NeedsBackdrop(const Form: TPDFormXObject): Boolean;
    function BackdropComposite: TPdfComposite;
    procedure DrawGroup(const Form: TPDFormXObject; const Bounds: TRect; const Shift: Single);
    procedure RunGroupContent(const Form: TPDFormXObject; const GroupDevice: IPdfRasterDevice; const Bounds: TRect; const Ctm: TPdfMatrix;
                              const IsSoftMask: Boolean);
    procedure RunGroupStream(const Form: TPDFormXObject; const Bounds: TRect; const Ctm: TPdfMatrix; const IsSoftMask: Boolean);
    procedure DrawGroupResult(const GroupDevice: TPdfGroupDevice; const Bounds: TRect; const Shift: Single);

  protected
    // The page clip: the crop box
    function CreateInitialGraphicsState(const Page: TPDPage): TPDGraphicsState; override;
    function StopRequested: Boolean; override;
    procedure ClipToRect(const Rect: TPdfRectangle); override;
    function CreateAnnotationGraphicsState: TPDGraphicsState; override;

  public
    // Device is drawn on without being cleared. The region of Params must be valid already, the renderer checks the arguments.
    constructor Create(const Renderer: TPdfRenderer; const Page: TPDPage; const Device: IPdfGraphicsDevice; const Params: TPdfRenderParams);
    destructor Destroy; override;

    procedure DrawPage;
    // Draws the group of a soft mask on a layer of its own, which starts with Backdrop when HasBackdrop. Ctm replaces the CTM of the state,
    // the state is that of the caller without soft mask. The layer lies at Bounds; unlike a group that is drawn, the content of a soft mask is
    // not lower (the references show the mask exactly on the box). False when nothing of the group is in the device. The caller owns Image.
    function TryRenderMaskGroup(const Form: TPDFormXObject; const Ctm: TPdfMatrix; const HasBackdrop: Boolean; const Backdrop: TPdfDeviceColor;
                                out Bounds: TRect; out Image: TPdfBitmap): Boolean;

    // PageDrawer.drawTilingPattern: draws the content of the pattern on Layer, a layer of the device with the cell of the pattern. PatternMatrix is
    // the matrix of the content and LayerTransform goes from the space after it to the pixels of the layer. ColorSpace and Color are those of
    // an uncoloured pattern.
    procedure DrawTilingPattern(const Layer: IPdfRasterDevice; const Pattern: TPDTilingPattern; const ColorSpace: TPDColorSpace; const Color: TPDColor;
                                const PatternMatrix, LayerTransform: TPdfMatrix);

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
    procedure ShowForm(const Form: TPDFormXObject); override;
    procedure ShowAnnotation(const Annotation: TPDAnnotation); override;
    procedure BeginMarkedContentSequence(const Tag: string; const Properties: TCosDictionary); override;
    procedure EndMarkedContentSequence; override;

    property Renderer: TPdfRenderer read FRenderer;
    property Page: TPDPage read FPage;
    // True once the cancel token of the parameters has said so
    property IsCancelled: Boolean read FIsCancelled;
  end;

implementation

uses
  System.Math,
  System.SysUtils,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Graphics.Color.Device,
  Pdf4D.Graphics.Color.Pattern,
  Pdf4D.Graphics.Color.Special,
  Pdf4D.Graphics.State,
  Pdf4D.Model.ExtendedGraphicsState,
  Pdf4D.Render.ClipPath,
  Pdf4D.Render.GlyphCache,
  Pdf4D.Render.ImageScaler,
  Pdf4D.Render.Options,
  Pdf4D.Render.PageTransform,
  Pdf4D.Render.SoftMaskPaint,
  Pdf4D.Render.StrokeNormalizer;

const
  Half = 0.5;
  // A square cap reaches further than half the width in its corners
  SquareCapReach = 1.5;
  LargestStyleCode = 2;
  // A glyph of a font that is not embedded is made as wide as the PDF says (in thousandths of text space)
  Thousand = 1000;
  WidthTolerance = 0.0001;
  MaximumLoggedMissingGlyphs = 1024;
  MaximumLoggedTilingWarnings = 256;
  // The clip paths that the groups of one page may copy in all, and what a group still gets when they are used up
  MaxTranslatedClipLinks = 50000;
  MinTranslatedClipLinks = 1;
  UncoloredWithoutSpaceWarning = 'An uncoloured pattern needs a colour space for its colour (/Pattern with an underlying space), nothing is painted';
  // PDFRenderer.imageDownscalingOptimizationThreshold: an image that is drawn at less than this scale is averaged down first
  ImageDownscalingThreshold = 0.5;
  CodeShift = 48;
  CodeMask = $FFFF;
  // A page turns by quarters; the rotation of a turned annotation is exact for those, as AffineTransform.rotate is
  QuarterTurn = 90;
  QuarterTurnCount = 4;
  QuarterCosine: array[0..QuarterTurnCount - 1] of Single = (1, 0, -1, 0);
  QuarterSine: array[0..QuarterTurnCount - 1] of Single = (0, 1, 0, -1);

// processSoftMask: the text matrices are new, and the colours are the initial colour of DeviceGray (black) for stroking and not stroking
procedure StartWithBlackDeviceGray(const State: TPdfRenderGraphicsState);
begin
  const Gray = TPDDeviceGray.Instance;
  State.SetTextMatrix(TPdfMatrix.Identity);
  State.SetTextLineMatrix(TPdfMatrix.Identity);
  State.NonStrokingColorSpace := Gray;
  State.NonStrokingColor := Gray.InitialColor;
  State.StrokingColorSpace := Gray;
  State.StrokingColor := Gray.InitialColor;
end;

type
  // What the tiling paint asks of the drawer that owns it. The drawer frees the factory that holds this, before it is gone itself.
  TPdfPageDrawerTilingHost = class(TInterfacedObject, IPdfTilingHost)
  private
    FDrawer: TPdfPageDrawer;

  public
    constructor Create(const Drawer: TPdfPageDrawer);

    function InitialMatrix: TPdfMatrix;
    function Options: TPdfRenderOptions;
    procedure LogWarning(const Fmt: string; const Args: array of const);
    function CreateLayer(const Width, Height: Integer): IPdfRasterDevice;
    procedure DrawTilingPattern(const Layer: IPdfRasterDevice; const Pattern: TPDTilingPattern; const ColorSpace: TPDColorSpace;
                                const Color: TPDColor; const PatternMatrix: TPdfMatrix; const LayerTransform: TPdfMatrix);
  end;

{ TPdfPageDrawerTilingHost }

constructor TPdfPageDrawerTilingHost.Create(const Drawer: TPdfPageDrawer);
begin
  inherited Create;
  FDrawer := Drawer;
end;

function TPdfPageDrawerTilingHost.InitialMatrix: TPdfMatrix;
begin
  Result := FDrawer.InitialMatrix;
end;

function TPdfPageDrawerTilingHost.Options: TPdfRenderOptions;
begin
  Result := FDrawer.FParams.Options;
end;

procedure TPdfPageDrawerTilingHost.LogWarning(const Fmt: string; const Args: array of const);
begin
  FDrawer.LogTilingWarning(Fmt, Args);
end;

function TPdfPageDrawerTilingHost.CreateLayer(const Width, Height: Integer): IPdfRasterDevice;
begin
  Result := FDrawer.FDevice.CreateLayer(Width, Height);
end;

procedure TPdfPageDrawerTilingHost.DrawTilingPattern(const Layer: IPdfRasterDevice; const Pattern: TPDTilingPattern; const ColorSpace: TPDColorSpace;
                                                     const Color: TPDColor; const PatternMatrix: TPdfMatrix; const LayerTransform: TPdfMatrix);
begin
  FDrawer.DrawTilingPattern(Layer, Pattern, ColorSpace, Color, PatternMatrix, LayerTransform);
end;

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
  FTranslatedLinkBudget := MaxTranslatedClipLinks;
  FLoggedMissingGlyphs := TDictionary<Int64, Boolean>.Create;
  FShadings := TObjectDictionary<TCosDictionary, TPDShading>.Create([doOwnsValues]);
  FShadingPatterns := TObjectDictionary<TCosDictionary, TPDShadingPattern>.Create([doOwnsValues]);
  FTilingPatterns := TObjectDictionary<TCosDictionary, TPDTilingPattern>.Create([doOwnsValues]);
  FLoggedTilingWarnings := TDictionary<string, Boolean>.Create;
  FTilingPaints := TPdfTilingPaintFactory.Create(TPdfPageDrawerTilingHost.Create(Self));
  FShadingBudget := TPdfShadingBudget.Create(Params.Options.MaxShadingWork);
  Page.Context.BeginFunctionWork(Params.Options.MaxPostScriptWork);

  var Properties: TPDOptionalContentProperties := nil;
  if not Renderer.TryGetOptionalContentProperties(Properties) then
  begin
    Properties := nil;
  end;
  FVisibility := TPdfOptionalContentVisibility.Create(Properties, Params.Options.Destination, Page.Context.Log);

  const Transform = TPdfPageTransform.Create(Page.CropBox, Page.Rotation + Params.ExtraRotation, Params.Scale);
  const Whole = Transform.PageToDevice;
  // The device shows the region: its pixel (0, 0) is the top left pixel of the region
  FPageToDevice := TPdfMatrix.Create(Whole.ScaleX, Whole.ShearY, Whole.ShearX, Whole.ScaleY, Whole.TranslateX - Params.Region.Left,
                                     Whole.TranslateY - Params.Region.Top);
  FTranslationResidualX := Double(Whole.TranslateX) + Transform.TranslationResidualX - Params.Region.Left - Double(FPageToDevice.TranslateX);
  FTranslationResidualY := Double(Whole.TranslateY) + Transform.TranslationResidualY - Params.Region.Top - Double(FPageToDevice.TranslateY);
  FScalingFactorX := Abs(Whole.ScalingFactorX);
  FScalingFactorY := Abs(Whole.ScalingFactorY);
end;

destructor TPdfPageDrawer.Destroy;
begin
  FVisibility.Free;
  FTilingPaints.Free;
  FShadingBudget.Free;
  FLoggedTilingWarnings.Free;
  FTilingPatterns.Free;
  FShadingPatterns.Free;
  FShadings.Free;
  FCachedMask.Free;
  FLoggedMissingGlyphs.Free;
  FTextClip.Free;
  FLinePath.Free;
  inherited;
end;

procedure TPdfPageDrawer.DrawPage;
begin
  ProcessPage(FPage);
  if FParams.Options.RenderAnnotations and (not StopRequested) then
  begin
    DrawAnnotations;
  end;
end;

// Where PDFBox raises, the annotation is skipped and the next one drawn; a budget that is used up or a stop ends the annotations
function TPdfPageDrawer.TryShowAnnotation(const Annotation: TPDAnnotation): Boolean;
begin
  Result := True;
  try
    ShowAnnotation(Annotation);
  except
    on Failure: EPdfLimitExceededException do
    begin
      if not StopRequested then
      begin
        LogError('The annotations are not drawn any further: %s', [Failure.Message]);
      end;
      Result := False;
    end;
    on Failure: EPdfException do
    begin
      LogError('An annotation is skipped: %s', [Failure.Message]);
    end;
    on Failure: Exception do
    begin
      if TPdfFailure.IsFatal(Failure) then
      begin
        raise;
      end;
      LogError('An annotation is skipped: %s: %s', [Failure.ClassName, Failure.Message]);
    end;
  end;
end;

procedure TPdfPageDrawer.DrawAnnotations;
begin
  const Count = FPage.AnnotationCount;
  const MaxAnnotations = Max(FParams.Options.MaxAnnotations, 0);
  if Count > MaxAnnotations then
  begin
    LogWarning('The page has %d annotations, only the first %d are drawn', [Count, MaxAnnotations]);
  end;

  const Annotations = FPage.Annotations(MaxAnnotations);
  try
    for var Annotation in Annotations do
    begin
      if not TryShowAnnotation(Annotation) then
      begin
        Break;
      end;
    end;
  finally
    Annotations.Free;
  end;
end;

function TPdfPageDrawer.ShouldSkipAnnotation(const Annotation: TPDAnnotation): Boolean;
begin
  const Destination = FParams.Options.Destination;
  const IsNotPrinted = ((Destination = TPdfRenderDestination.Print) and (not Annotation.IsPrinted));
  const IsNotViewed = ((Destination in [TPdfRenderDestination.View, TPdfRenderDestination.Export]) and Annotation.IsNoView);
  // The invisible flag only counts for a type of annotation that is not one of the standard types (and has no handler)
  const IsInvisibleUnknown = (Annotation.IsInvisible and (not Annotation.IsKnownType));
  var OptionalContent: TCosDictionary;
  const IsHiddenContent = (Annotation.TryGetOptionalContent(OptionalContent) and FVisibility.IsHidden(OptionalContent));
  Result := (IsNotPrinted or IsNotViewed or Annotation.IsHidden or IsInvisibleUnknown or IsHiddenContent);
end;

// PDFBOX-4744 avoids the appearances with transparency groups of a turned annotation by constructing a new appearance, which is not ported
procedure TPdfPageDrawer.ShowAnnotation(const Annotation: TPDAnnotation);
begin
  FLastClip := nil;
  if ShouldSkipAnnotation(Annotation) then
  begin
    Exit;
  end;

  const IsTurned = (Annotation.IsNoRotate and (FPage.Rotation <> 0) and Annotation.HasRect);
  if IsTurned then
  begin
    ShowTurnedAnnotation(Annotation);
  end
  else
  begin
    inherited ShowAnnotation(Annotation);
  end;
end;

// NoRotate: the upper left corner of the annotation stays at the same point in the page and the annotation pivots around it, against
// the rotation of the page. Graphics2D.rotate does that with the transform of the device, so clips made meanwhile turn with it.
procedure TPdfPageDrawer.ShowTurnedAnnotation(const Annotation: TPDAnnotation);
begin
  const Rect = Annotation.Rect;
  const Quarter = (FPage.Rotation div QuarterTurn) mod QuarterTurnCount;
  const Turn = TPdfMatrix.Create(QuarterCosine[Quarter], QuarterSine[Quarter], -QuarterSine[Quarter], QuarterCosine[Quarter], 0, 0);
  var Local := TPdfMatrix.GetTranslateInstance(-Rect.LowerLeftX, -Rect.UpperRightY);
  Local := Local.Multiply(Turn).Multiply(TPdfMatrix.GetTranslateInstance(Rect.LowerLeftX, Rect.UpperRightY));

  const SavedPageToDevice = FPageToDevice;
  FPageToDevice := Local.Multiply(SavedPageToDevice);
  FIsAnnotationTurned := True;
  FLastClip := nil;
  try
    inherited ShowAnnotation(Annotation);
  finally
    FIsAnnotationTurned := False;
    FPageToDevice := SavedPageToDevice;
    FLastClip := nil;
  end;
end;

function TPdfPageDrawer.CreateAnnotationGraphicsState: TPDGraphicsState;
begin
  if FIsAnnotationTurned then
  begin
    // The clip of the page is made again, with the turned matrix
    Result := CreateInitialGraphicsState(FPage);
  end
  else
  begin
    Result := inherited CreateAnnotationGraphicsState;
  end;
end;

function TPdfPageDrawer.IsContentRendered: Boolean;
begin
  Result := (FHiddenDepth <= 0);
end;

function TPdfPageDrawer.IsFormHidden(const Form: TPDFormXObject): Boolean;
begin
  var OptionalContent: TCosDictionary;
  Result := (Form.TryGetOptionalContent(OptionalContent) and FVisibility.IsHidden(OptionalContent));
end;

function TPdfPageDrawer.IsImageHidden(const Image: TPDImage): Boolean;
begin
  var OptionalContent: TCosDictionary;
  Result := ((Image is TPDImageXObject) and TPDImageXObject(Image).TryGetOptionalContent(OptionalContent) and FVisibility.IsHidden(OptionalContent));
end;

procedure TPdfPageDrawer.BeginMarkedContentSequence(const Tag: string; const Properties: TCosDictionary);
begin
  if FHiddenDepth > 0 then
  begin
    Inc(FHiddenDepth);
    Exit;
  end;

  if Assigned(Properties) and FVisibility.IsHidden(Properties) then
  begin
    FHiddenDepth := 1;
  end;
end;

procedure TPdfPageDrawer.EndMarkedContentSequence;
begin
  if FHiddenDepth > 0 then
  begin
    Dec(FHiddenDepth);
  end;
end;

procedure TPdfPageDrawer.ShowForm(const Form: TPDFormXObject);
begin
  if IsFormHidden(Form) or (not IsContentRendered) then
  begin
    Exit;
  end;
  inherited ShowForm(Form);
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
      IntersectStateClip(Path, TPdfFillRule.NonZero);
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
  const X: Double = Matrix.ScaleX + Matrix.ShearX;
  const Y: Double = Matrix.ScaleY + Matrix.ShearY;
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

function TPdfPageDrawer.PlainNonStrokingComposite(const IsAntiAliased: Boolean): TPdfComposite;
begin
  Result := TPdfComposite.Default;
  Result.Alpha := LimitedAlpha(RenderState.NonStrokeAlphaConstant);
  Result.BlendMode := RenderState.BlendMode;
  Result.AntiAlias := (FParams.Options.AntiAlias and IsAntiAliased);
end;

function TPdfPageDrawer.NonStrokingComposite(const IsAntiAliased: Boolean): TPdfComposite;
begin
  Result := PlainNonStrokingComposite(IsAntiAliased);
  Result.SoftMask := CurrentSoftMask;
end;

// PDFBOX-5307: an image with a /Mask or /SMask of its own ignores the soft mask of the graphics state
function TPdfPageDrawer.ImageComposite(const Image: TPDImage): TPdfComposite;
begin
  Result := PlainNonStrokingComposite(True);
  if not Image.HasMaskOrSMask then
  begin
    Result.SoftMask := CurrentSoftMask;
  end;
end;

function TPdfPageDrawer.StrokingComposite: TPdfComposite;
begin
  Result := TPdfComposite.Default;
  Result.Alpha := LimitedAlpha(RenderState.AlphaConstant);
  Result.BlendMode := RenderState.BlendMode;
  Result.AntiAlias := FParams.Options.AntiAlias;
  Result.SoftMask := CurrentSoftMask;
end;

// The mask of the soft mask of the graphics state in the pixels of the device, owned by the drawer; nil without soft mask and for a soft
// mask that draws nothing (Adobe ignores those). The mask lives until the next one is made, which is after the draw call that uses it.
function TPdfPageDrawer.CurrentSoftMask: TPdfAlphaMask;
begin
  const Mask = RenderState.SoftMask;
  if not Assigned(Mask) then
  begin
    Exit(nil);
  end;

  if not IsSoftMaskCached(Mask) then
  begin
    const Built = BuildSoftMask(Mask);
    FCachedMask.Free;
    FCachedMask := Built;
    FCachedMaskSource := Mask;
    FCachedMaskMatrix := FPageToDevice;
    FCachedMaskWidth := FDevice.Width;
    FCachedMaskHeight := FDevice.Height;
  end;
  Result := FCachedMask;
end;

function TPdfPageDrawer.IsSoftMaskCached(const Mask: IPdfSoftMask): Boolean;
begin
  Result := ((FCachedMaskSource = Mask) and FCachedMaskMatrix.IsEqual(FPageToDevice) and (FCachedMaskWidth = FDevice.Width) and
             (FCachedMaskHeight = FDevice.Height));
end;

// A soft mask that is nested as deep as the limit is left out
function TPdfPageDrawer.BuildSoftMask(const Mask: IPdfSoftMask): TPdfAlphaMask;
begin
  if FSoftMaskDepth >= Max(FParams.Options.MaxSoftMaskDepth, 1) then
  begin
    if not FHasLoggedSoftMaskDepth then
    begin
      FHasLoggedSoftMaskDepth := True;
      LogWarning('Soft masks are nested as deep as the limit of %d, the soft mask is skipped', [FParams.Options.MaxSoftMaskDepth]);
    end;
    Exit(nil);
  end;

  Inc(FSoftMaskDepth);
  try
    Result := TPdfSoftMaskBuilder.Build(Self, Mask);
  finally
    Dec(FSoftMaskDepth);
  end;
end;

// getPaint for a colour that is not a pattern. PDFBOX-4900: "The special colorant name None shall not produce any visible output", so the
// colour of such a Separation space is the transparent colour.
function TPdfPageDrawer.SolidPaint(const Color: TPDColor): TPdfPaint;
begin
  const IsNoneColorant = ((Color.ColorSpace is TPDSeparation) and TPDSeparation(Color.ColorSpace).IsNone);
  if IsNoneColorant then
  begin
    Exit(TPdfPaint.Solid(TPdfDeviceColor.Create(0, 0, 0, 0)));
  end;

  Result := TPdfPaint.Solid(Color.ToRgb.ToDeviceColor);
end;

class function TPdfPageDrawer.IsPatternColor(const Color: TPDColor): Boolean;
begin
  Result := (Assigned(Color.ColorSpace) and (Color.ColorSpace is TPDPattern));
end;

// A shading is made once for the page, however often it is painted: its functions may hold large tables. One that cannot be made is
// logged once.
function TPdfPageDrawer.TryGetShading(const Value: TCosBase; out Shading: TPDShading): Boolean;
begin
  const Key = TCosDictionary(Value);
  if FShadings.TryGetValue(Key, Shading) then
  begin
    Exit(Assigned(Shading));
  end;

  try
    Shading := TPDShading.Create(Value, Resources);
  except
    on Failure: EPdfException do
    begin
      Shading := nil;
      LogError('A shading is skipped: %s', [Failure.Message]);
    end;
  end;
  FShadings.Add(Key, Shading);
  Result := Assigned(Shading);
end;

// getPattern of PDPattern for the pattern colour: the dictionary or stream of the pattern. A pattern that is missing gives False (PDFBox fails
// and the operator paints nothing).
function TPdfPageDrawer.TryGetPatternValue(const Color: TPDColor; out Value: TCosBase): Boolean;
begin
  Result := Resources.TryGetPattern(Color.PatternName, Value);
  if not Result then
  begin
    LogError('The pattern ''%s'' was not found, nothing is painted', [Color.PatternName]);
  end;
end;

// PDAbstractPattern.create: PatternType 1 is a tiling pattern, anything else is taken for a shading pattern
class function TPdfPageDrawer.IsTilingPattern(const Value: TCosBase): Boolean;
begin
  const PatternType = TCosDictionary(Value).GetInt(TCosNames.PatternType, 0);
  Result := (PatternType = TilingPatternType);
end;

// A pattern that is no shading pattern gives False and a line in the log
function TPdfPageDrawer.TryGetShadingPattern(const Color: TPDColor; const Value: TCosBase; out Pattern: TPDShadingPattern): Boolean;
begin
  Pattern := nil;
  const Key = TCosDictionary(Value);
  if FShadingPatterns.TryGetValue(Key, Pattern) then
  begin
    Exit(Assigned(Pattern));
  end;

  try
    Pattern := TPDShadingPattern.Create(Value, Resources);
  except
    on Failure: EPdfException do
    begin
      Pattern := nil;
      LogError('The pattern ''%s'' is skipped: %s', [Color.PatternName, Failure.Message]);
    end;
  end;
  FShadingPatterns.Add(Key, Pattern);
  Result := Assigned(Pattern);
end;

// A tiling pattern that cannot be made (it is no stream) gives False and a line in the log, once
function TPdfPageDrawer.TryGetTilingPattern(const Color: TPDColor; const Value: TCosBase; out Pattern: TPDTilingPattern): Boolean;
begin
  Pattern := nil;
  const Key = TCosDictionary(Value);
  if FTilingPatterns.TryGetValue(Key, Pattern) then
  begin
    Exit(Assigned(Pattern));
  end;

  try
    Pattern := TPDTilingPattern.Create(Value);
  except
    on Failure: EPdfException do
    begin
      Pattern := nil;
      LogError('The pattern ''%s'' is skipped: %s', [Color.PatternName, Failure.Message]);
    end;
  end;
  FTilingPatterns.Add(Key, Pattern);
  Result := Assigned(Pattern);
end;

// The colour space of the colour of an uncoloured pattern: the underlying space of the Pattern space. Nil when there is none.
class function TPdfPageDrawer.UnderlyingColorSpace(const Color: TPDColor): TPDColorSpace;
begin
  Result := nil;
  if Color.ColorSpace is TPDPatternColorSpace then
  begin
    Result := TPDPatternColorSpace(Color.ColorSpace).UnderlyingColorSpace;
  end;
end;

// PDFBox has no limit on patterns in patterns besides the stack
function TPdfPageDrawer.IsPatternDepthReached: Boolean;
begin
  Result := (FPatternDepth >= Max(FParams.Options.MaxPatternDepth, 1));
  if Result and (not FHasLoggedPatternDepth) then
  begin
    FHasLoggedPatternDepth := True;
    LogWarning('Patterns are nested as deep as the limit of %d, the pattern is skipped', [FParams.Options.MaxPatternDepth]);
  end;
end;

procedure TPdfPageDrawer.LogTilingWarning(const Fmt: string; const Args: array of const);
begin
  const Message = Format(Fmt, Args);
  const IsKnown = FLoggedTilingWarnings.ContainsKey(Message);
  const IsRoomLeft = (FLoggedTilingWarnings.Count < MaximumLoggedTilingWarnings);
  if (not IsKnown) and IsRoomLeft then
  begin
    FLoggedTilingWarnings.Add(Message, True);
    LogWarning('%s', [Message]);
  end;
end;

class function TPdfPageDrawer.DeviceBoundsOf(const Path: TPdfPath; const Transform: TPdfMatrix): TRectF;
begin
  const DevicePath = Path.Clone;
  try
    DevicePath.Transform(Transform);
    Result := DevicePath.Bounds;
  finally
    DevicePath.Free;
  end;
end;

class function TPdfPageDrawer.WholePixels(const Area: TRectF): TRect;
begin
  Result := TRect.Create(Floor(Area.Left), Floor(Area.Top), Ceil(Area.Right), Ceil(Area.Bottom));
end;

// The bounds that the paint context of Java2D gets for a stroke are those of the stroked shape; the outline is not made here, so the
// bounds of the path are widened by what the line can reach
function TPdfPageDrawer.StrokeBoundsOf(const Path: TPdfPath; const Stroke: TPdfStrokeStyle): TRectF;
begin
  const Bounds = DeviceBoundsOf(Path, FPageToDevice);
  const ScaleOfX: Double = Sqrt(Sqr(Double(FPageToDevice.ScaleX)) + Sqr(Double(FPageToDevice.ShearY)));
  const ScaleOfY: Double = Sqrt(Sqr(Double(FPageToDevice.ShearX)) + Sqr(Double(FPageToDevice.ScaleY)));
  var Reach: Double := SquareCapReach;
  if Stroke.Join = TPdfLineJoin.Miter then
  begin
    Reach := Max(Reach, Double(Stroke.MiterLimit));
  end;

  const Margin: Double = Single(Stroke.Width * Half * Reach * Max(ScaleOfX, ScaleOfY) + 1);
  Result := TRectF.Create(Bounds.Left - Margin, Bounds.Top - Margin, Bounds.Right + Margin, Bounds.Bottom + Margin);
end;

// The device area that a pattern is painted on: what is painted (Bounds), the device, the BBox of the shading (BoxPath, in page space, may
// be nil) and the clip. False when there is nothing of it to paint.
function TPdfPageDrawer.TryGetPatternArea(const Bounds: TRectF; const BoxPath: TPdfPath; out Area: TRect): Boolean;
begin
  Area := TRect.Empty;
  const IsFiniteBounds = (not (IsNan(Bounds.Left) or IsInfinite(Bounds.Left) or IsNan(Bounds.Top) or IsInfinite(Bounds.Top) or
                               IsNan(Bounds.Right) or IsInfinite(Bounds.Right) or IsNan(Bounds.Bottom) or IsInfinite(Bounds.Bottom)));
  if not IsFiniteBounds then
  begin
    Exit(False);
  end;

  var Whole := TRectF.Intersect(TRectF.Create(0, 0, FDevice.Width, FDevice.Height), Bounds);
  if Assigned(BoxPath) then
  begin
    if not IsFinitePath(BoxPath) then
    begin
      LogError('A shading is skipped: its bounding box does not give finite coordinates', []);
      Exit(False);
    end;
    Whole := TRectF.Intersect(Whole, DeviceBoundsOf(BoxPath, FPageToDevice));
  end;

  Whole := IntersectedWithClips(Whole);
  if Whole.IsEmpty then
  begin
    Exit(False);
  end;

  Area := WholePixels(Whole);
  Result := (not Area.IsEmpty);
end;

// The bitmap of the shading, as the paint of Action. The bitmap is gone when Action ends.
procedure TPdfPageDrawer.PaintShadingArea(const Shading: TPDShading; const ShadingToDevice: TPdfMatrix; const Area: TRect;
                                          const Action: TPdfPaintAction);
begin
  if FShadingBudget.IsExhausted then
  begin
    FShadingBudget.Report(Shading);
    Exit;
  end;

  const Bitmap = TPdfShadingRasterizer.Rasterize(Shading, ShadingToDevice, Area, FParams.Cancel, FShadingBudget);
  try
    Action(TPdfPaint.FromBitmap(Bitmap, TPdfMatrix.GetTranslateInstance(Area.Left, Area.Top), TPdfTileMode.Decal, TPdfImageFilter.Nearest));
  finally
    Bitmap.Free;
  end;
end;

// getPaint for a pattern colour. Action paints with the paint and the clip that was made.
procedure TPdfPageDrawer.WithPatternPaint(const Color: TPDColor; const Bounds: TRectF; const Action: TPdfPaintAction);
begin
  var Value: TCosBase;
  if not TryGetPatternValue(Color, Value) then
  begin
    Exit;
  end;

  if IsTilingPattern(Value) then
  begin
    WithTilingPaint(Color, Value, Bounds, Action);
  end
  else
  begin
    WithShadingPaint(Color, Value, Bounds, Action);
  end;
end;

// getPaint for a tiling pattern: the paint repeats the cell, which is made once for the colour and the matrices (TilingPaintFactory). A coloured
// pattern has no colour of its own to key on, an uncoloured one has the components of its colour in the underlying space.
procedure TPdfPageDrawer.WithTilingPaint(const Color: TPDColor; const Value: TCosBase; const Bounds: TRectF; const Action: TPdfPaintAction);
begin
  var Pattern: TPDTilingPattern;
  if (not TryGetTilingPattern(Color, Value, Pattern)) or IsPatternDepthReached then
  begin
    Exit;
  end;

  var Area: TRect;
  if not TryGetPatternArea(Bounds, nil, Area) then
  begin
    Exit;
  end;

  var ColorSpace: TPDColorSpace := nil;
  var CellColor := TPDColor.Create(nil, nil);
  if Pattern.PaintType <> PaintTypeColored then
  begin
    ColorSpace := UnderlyingColorSpace(Color);
    if not Assigned(ColorSpace) then
    begin
      LogTilingWarning(UncoloredWithoutSpaceWarning, []);
      Exit;
    end;
    CellColor := TPDColor.Create(ColorSpace, Color.Components);
  end;

  var Paint: TPdfPaint;
  if FTilingPaints.TryGetPaint(Pattern, ColorSpace, CellColor, FPageToDevice, Area, Paint) then
  begin
    Action(Paint);
  end;
end;

// drawTilingPattern and processTilingPattern: the content of the pattern runs on the layer of the cell, with a clean graphics state whose clip is
// the box of the pattern. The page drawer of PDFBox draws a group in a pattern upside down (flipTG) because the graphics of the cell is not
// turned over; the layer of a group here is drawn with the matrix of the cell, so it needs no such correction.
procedure TPdfPageDrawer.DrawTilingPattern(const Layer: IPdfRasterDevice; const Pattern: TPDTilingPattern; const ColorSpace: TPDColorSpace;
                                           const Color: TPDColor; const PatternMatrix, LayerTransform: TPdfMatrix);
begin
  var BBox: TPdfRectangle;
  if not Pattern.TryGetBBox(BBox) then
  begin
    Exit;
  end;

  var PatternResources: TCosDictionary;
  if not Pattern.TryGetResources(PatternResources) then
  begin
    PatternResources := nil;
  end;

  const SavedDevice = FDevice;
  const SavedMatrix = FPageToDevice;
  const SavedResidualX = FTranslationResidualX;
  const SavedResidualY = FTranslationResidualY;
  const SavedLinePath = FLinePath;
  const SavedTextClip = FTextClip;
  const SavedLastClip = FLastClip;
  FDevice := Layer;
  FPageToDevice := LayerTransform;
  FTranslationResidualX := 0;
  FTranslationResidualY := 0;
  FLinePath := TPdfPath.Create;
  FTextClip := TPdfPath.Create;
  FLastClip := nil;
  Inc(FPatternDepth);
  try
    ProcessChildStream(Pattern.Stream, PatternResources, CreateTilingState(Pattern, ColorSpace, Color), PatternMatrix, True, BBox);
  finally
    Dec(FPatternDepth);
    FTextClip.Free;
    FLinePath.Free;
    FTextClip := SavedTextClip;
    FLinePath := SavedLinePath;
    FDevice := SavedDevice;
    FPageToDevice := SavedMatrix;
    FTranslationResidualX := SavedResidualX;
    FTranslationResidualY := SavedResidualY;
    FLastClip := SavedLastClip;
  end;
end;

// The state that processTilingPattern pushes: new, without clip; an uncoloured pattern paints with its colour in the underlying space
function TPdfPageDrawer.CreateTilingState(const Pattern: TPDTilingPattern; const ColorSpace: TPDColorSpace; const Color: TPDColor): TPDGraphicsState;
begin
  const State = TPdfRenderGraphicsState.Create;
  if Pattern.PaintType <> PaintTypeColored then
  begin
    State.NonStrokingColorSpace := ColorSpace;
    State.StrokingColorSpace := ColorSpace;
    State.NonStrokingColor := Color;
    State.StrokingColor := Color;
  end;
  Result := State;
end;

// getPaint for a shading pattern, with intersectShadingBBox: the pattern is the shading placed by its matrix in the initial space of
// the stream, and the box of the shading cuts what is painted. PDFBox intersects the Area of the shape with the box; here the device
// gets the box as one more link of the clip, which cuts without anti-aliasing.
procedure TPdfPageDrawer.WithShadingPaint(const Color: TPDColor; const Value: TCosBase; const Bounds: TRectF; const Action: TPdfPaintAction);
begin
  var Pattern: TPDShadingPattern;
  if not TryGetShadingPattern(Color, Value, Pattern) then
  begin
    Exit;
  end;

  const PatternToPage = Pattern.Matrix.Multiply(InitialMatrix);
  var BBox: TPdfRectangle;
  var BoxPath: TPdfPath := nil;
  if Pattern.Shading.TryGetBBox(BBox) then
  begin
    BoxPath := PathAround(BBox, PatternToPage);
  end;

  try
    var Area: TRect;
    if not TryGetPatternArea(Bounds, BoxPath, Area) then
    begin
      Exit;
    end;

    if Assigned(BoxPath) then
    begin
      FDevice.SetClip(TPdfClipPath.Create(RenderState.Clip, BoxPath.Clone, FPageToDevice, TPdfFillRule.NonZero));
      FLastClip := nil;
    end;
    PaintShadingArea(Pattern.Shading, PatternToPage.Multiply(FPageToDevice), Area, Action);
  finally
    BoxPath.Free;
  end;
end;

procedure TPdfPageDrawer.FillWithColor(const Path: TPdfPath; const FillRule: TPdfFillRule; const Color: TPDColor; const IsAntiAliased: Boolean);
begin
  ApplyClip;
  if not IsPatternColor(Color) then
  begin
    FDevice.FillPath(Path, FPageToDevice, FillRule, SolidPaint(Color), NonStrokingComposite(IsAntiAliased));
    Exit;
  end;

  // The composite is made when the paint is there: making the cell of a pattern may build another soft mask, which replaces the one that the
  // composite would point to
  WithPatternPaint(Color, DeviceBoundsOf(Path, FPageToDevice),
    procedure(const Paint: TPdfPaint)
    begin
      FDevice.FillPath(Path, FPageToDevice, FillRule, Paint, NonStrokingComposite(IsAntiAliased));
    end);
end;

procedure TPdfPageDrawer.StrokeWithColor(const Path: TPdfPath; const Stroke: TPdfStrokeStyle; const Color: TPDColor);
begin
  ApplyClip;
  if not IsPatternColor(Color) then
  begin
    DrawStroke(Path, Stroke, SolidPaint(Color));
    Exit;
  end;

  WithPatternPaint(Color, StrokeBoundsOf(Path, Stroke),
    procedure(const Paint: TPdfPaint)
    begin
      DrawStroke(Path, Stroke, Paint);
    end);
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
  var Shortest: Single := MinimumDashLength;
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
  var Width: Double := TransformWidth(RenderState.LineWidth);
  if IsNan(Width) or IsInfinite(Width) or (Width < MinimumLineWidth) then
  begin
    Width := MinimumLineWidth;
  end;
  Stroke.Width := Width;

  Stroke.Cap := TPdfLineCap(Min(LargestStyleCode, Max(0, RenderState.LineCap)));
  Stroke.Join := TPdfLineJoin(Min(LargestStyleCode, Max(0, RenderState.LineJoin)));
  var MiterLimit: Double := RenderState.MiterLimit;
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
  if (not IsContentRendered) or Path.IsEmpty or IsPoint(Path) then
  begin
    Exit;
  end;

  // Rectangles are not anti-aliased, to avoid small stripes where solid fills simulate piecewise gradients (PDFBOX-2302); paths of
  // no more than a point wide stand for lines and are anti-aliased (PDFBOX-1658)
  const Bounds = Path.Bounds;
  const IsLargeRectangle = (IsRectangular(Path) and (Bounds.Right - Bounds.Left > 1) and (Bounds.Bottom - Bounds.Top > 1));

  FillWithColor(Path, FillRule, RenderState.NonStrokingColor, not IsLargeRectangle);
end;

procedure TPdfPageDrawer.PaintStroke(const Path: TPdfPath);
begin
  var Stroke: TPdfStrokeStyle;
  if (not IsContentRendered) or (not HasSegments(Path)) or (not TryBuildStroke(Stroke)) then
  begin
    Exit;
  end;

  StrokeWithColor(Path, Stroke, RenderState.StrokingColor);
end;

// Java2D normalizes the geometry of a stroke, see TPdfStrokeNormalizer
procedure TPdfPageDrawer.DrawStroke(const Path: TPdfPath; const Stroke: TPdfStrokeStyle; const Paint: TPdfPaint);
begin
  const Normalized = TPdfStrokeNormalizer.Normalize(Path, FPageToDevice, FTranslationResidualX, FTranslationResidualY);
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

// shadingFill: the shading is painted on the area of its BBox (with the CTM) that the clip leaves, in the device. The shading area is
// the box, or without one the clip; the clip of the device cuts the box where PDFBox intersects the two Areas.
procedure TPdfPageDrawer.ShadingFill(const ShadingName: string);
begin
  if not IsContentRendered then
  begin
    Exit;
  end;

  var Value: TCosBase;
  if not Resources.TryGetShading(ShadingName, Value) then
  begin
    LogError('shading %s does not exist in resources dictionary', [ShadingName]);
    Exit;
  end;

  var Shading: TPDShading;
  if not TryGetShading(Value, Shading) then
  begin
    Exit;
  end;

  const Ctm = GraphicsState.CurrentTransformationMatrix;
  var BBox: TPdfRectangle;
  var BoxPath: TPdfPath := nil;
  if Shading.TryGetBBox(BBox) then
  begin
    BoxPath := PathAround(BBox, Ctm);
  end;

  try
    var Area: TRect;
    if TryGetPatternArea(TRectF.Create(0, 0, FDevice.Width, FDevice.Height), BoxPath, Area) then
    begin
      FillShadingArea(Shading, Ctm.Multiply(FPageToDevice), Area, BoxPath);
    end;
  finally
    BoxPath.Free;
  end;
end;

// Fills the box (page space), or the area (device pixels) when there is no box, with the bitmap of the shading
procedure TPdfPageDrawer.FillShadingArea(const Shading: TPDShading; const ShadingToDevice: TPdfMatrix; const Area: TRect; const BoxPath: TPdfPath);
begin
  ApplyClip;
  const Composite = NonStrokingComposite(True);
  const AreaPath = TPdfPath.Create;
  try
    AreaPath.MoveTo(Area.Left, Area.Top);
    AreaPath.LineTo(Area.Right, Area.Top);
    AreaPath.LineTo(Area.Right, Area.Bottom);
    AreaPath.LineTo(Area.Left, Area.Bottom);
    AreaPath.ClosePath;

    var Outline := AreaPath;
    var OutlineToDevice := TPdfMatrix.Identity;
    if Assigned(BoxPath) then
    begin
      Outline := BoxPath;
      OutlineToDevice := FPageToDevice;
    end;

    PaintShadingArea(Shading, ShadingToDevice, Area,
      procedure(const Paint: TPdfPaint)
      begin
        FDevice.FillPath(Outline, OutlineToDevice, TPdfFillRule.NonZero, Paint, Composite);
      end);
  finally
    AreaPath.Free;
  end;
end;

// PDFBOX-5715: below a scale of one, a clip that is thinner than two pixels is made two pixels wide, so that the lines that are drawn
// inside it do not vanish. The bounds are those of Java's Shape.getBounds, in whole points. Without rotation only; the result is Path
// itself or a new path that the caller frees.
function TPdfPageDrawer.AdjustedClip(const Path: TPdfPath): TPdfPath;
begin
  Result := Path;
  const HasRotation = ((FPageToDevice.ShearX <> 0) or (FPageToDevice.ShearY <> 0));
  const ScaleX: Double = Abs(FPageToDevice.ScaleX);
  const ScaleY: Double = Abs(FPageToDevice.ScaleY);
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
  const CenterX: Double = X + Width * Half;
  const CenterY: Double = Y + Height * Half;
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
      IntersectStateClip(Adjusted, FillRule);
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
      IntersectStateClip(FTextClip, TPdfFillRule.NonZero);
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
  const FontWidth: Double = Font.GetWidthFromFont(Code);
  const PdfWidth: Double = Displacement.X * Thousand;
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
  const IsRendered = IsContentRendered;
  if IsRendered and Mode.IsFill and (not GlyphPath.IsEmpty) then
  begin
    FillWithColor(GlyphPath, TPdfFillRule.NonZero, RenderState.NonStrokingColor, True);
  end;

  var Stroke: TPdfStrokeStyle;
  if IsRendered and Mode.IsStroke and HasSegments(GlyphPath) and TryBuildStroke(Stroke) then
  begin
    StrokeWithColor(GlyphPath, Stroke, RenderState.StrokingColor);
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
      FDevice.DrawBitmap(Scaled, BitmapToDevice, Filter, ImageComposite(Image));
    finally
      Scaled.Free;
    end;
    Exit;
  end;

  ApplyClip;
  FDevice.DrawBitmap(Bitmap, BitmapToDevice, Filter, ImageComposite(Image));
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
  const ScaleX: Double = Abs(ImageTransform.ScalingFactorX * FPageToDevice.ScalingFactorX);
  const ScaleY: Double = Abs(ImageTransform.ScalingFactorY * FPageToDevice.ScalingFactorY);
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

// drawImage: the transfer function of the graphics state (/TR or /TR2) changes the colours of an image; a name (/Identity, /Default) does not
procedure TPdfPageDrawer.ApplyTransferFunction(const Bitmap: TPdfBitmap);
begin
  const Transfer = RenderState.Transfer;
  const IsFunction = ((Transfer is TCosArray) or (Transfer is TCosDictionary));
  if IsFunction then
  begin
    TPdfImageTransfer.Apply(Bitmap, Transfer, FPage.Context);
  end;
end;

procedure TPdfPageDrawer.DrawImage(const Image: TPDImage);
begin
  if IsImageHidden(Image) or (not IsContentRendered) then
  begin
    Exit;
  end;

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
    ApplyTransferFunction(Bitmap);
    DrawImageBitmap(Image, Bitmap);
  finally
    Bitmap.Free;
  end;
end;

// showTransparencyGroup, with the depth limit of the options
procedure TPdfPageDrawer.ShowTransparencyGroup(const Form: TPDFormXObject);
begin
  if IsFormHidden(Form) or (not IsContentRendered) then
  begin
    Exit;
  end;

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
  var Shift: Single;
  if not TryGetGroupBounds(Form, GraphicsState.CurrentTransformationMatrix, True, Bounds, Shift) then
  begin
    Exit;
  end;

  Inc(FGroupDepth);
  try
    DrawGroup(Form, Bounds, Shift);
  finally
    Dec(FGroupDepth);
  end;
end;

// The area is cut with the bounds of each path of the clip chain: a chain of rectangles gives the exact intersection, another shape a
// slightly larger area, which only costs a few pixels of layer
function TPdfPageDrawer.IntersectedWithClips(const Area: TRectF): TRectF;
begin
  Result := Area;
  const Clip = RenderState.Clip;
  if Assigned(Clip) then
  begin
    Result := TRectF.Intersect(Result, Clip.Bounds);
  end;
end;

// The clip of the state gets one more path. A chain beyond MaxClipDepth is replaced by the rectangle of its bounds: every clip change on
// the device and every group walks over the chain, so an unbounded chain makes a page quadratic.
procedure TPdfPageDrawer.IntersectStateClip(const Path: TPdfPath; const FillRule: TPdfFillRule);
begin
  const MaxDepth = FParams.Options.MaxClipDepth;
  if RenderState.IntersectClip(Path, FPageToDevice, FillRule, MaxDepth) and (not FHasLoggedClipDepth) then
  begin
    FHasLoggedClipDepth := True;
    LogWarning('The clip of the page chains more than %d clip paths; from there on it is the rectangle around them', [Max(MaxDepth, 1)]);
  end;
end;

function TPdfPageDrawer.SharedTranslatedClip(const Clip: IPdfClipPath; const OffsetX, OffsetY: Integer): IPdfClipPath;
begin
  const Offset = TPoint.Create(OffsetX, OffsetY);
  const IsShared = (Assigned(Clip) and (Clip = FTranslatedSource) and (Offset = FTranslatedOffset));
  if IsShared then
  begin
    Exit(FTranslatedResult);
  end;

  // A chain that does not fit in what is left is cut back to its innermost paths: the groups of a hostile page cost a bounded time
  const Depth = ChainLength(Clip);
  const Allowed = Max(MinTranslatedClipLinks, Min(Depth, FTranslatedLinkBudget));
  if (Allowed < Depth) and (not FHasLoggedClipCut) then
  begin
    FHasLoggedClipCut := True;
    LogWarning('The clip of a transparency group is cut back to its last %d clip paths: the groups of the page copy more than %d', [Allowed, MaxTranslatedClipLinks]);
  end;
  Dec(FTranslatedLinkBudget, Min(Allowed, FTranslatedLinkBudget));

  Result := TranslatedClip(Clip, OffsetX, OffsetY, Allowed);
  FTranslatedSource := Clip;
  FTranslatedOffset := Offset;
  FTranslatedResult := Result;
end;

// PageDrawer.showTransparencyGroupOnGraphics draws the image of a group with its top at the top of the box, while TransparencyGroup
// gives the image one row more than the box (floor(maximum) + 1 - floor(minimum) of the bounds in the page, y upwards) and puts the
// content at the bottom of it. The content therefore lies lower than it should, by the difference of the two heights (one pixel for
// a box on whole pixels). That is a bug of PDFBox that the references have, so the port has it: the layer is drawn this much lower.
// A page that is turned does not follow this rule in PDFBox (the image is drawn through the rotation), so the shift is 0 there.
function TPdfPageDrawer.GroupShift(const Area: TRectF): Single;
begin
  const IsUpright = ((FPageToDevice.ShearX = 0) and (FPageToDevice.ShearY = 0) and (FPageToDevice.ScaleY < 0));
  if not IsUpright then
  begin
    Exit(0);
  end;

  // The y of the page times the scale, upwards: the translation of the matrix minus the y of the device
  const Minimum: Double = Double(FPageToDevice.TranslateY) - Area.Bottom;
  const Maximum: Double = Double(FPageToDevice.TranslateY) - Area.Top;
  Result := Floor(Maximum) + 1 - Floor(Minimum) - (Maximum - Minimum);
end;

// The bounds of TransparencyGroup in device pixels: the BBox with the CTM and the matrix of the form, the clip and the device. False
// when nothing of the group can be seen.
function TPdfPageDrawer.TryGetGroupBounds(const Form: TPDFormXObject; const Ctm: TPdfMatrix; const UsesClips: Boolean; out Bounds: TRect; out Shift: Single): Boolean;
begin
  Bounds := TRect.Empty;
  var Area := TRectF.Create(0, 0, FDevice.Width, FDevice.Height);

  var BBox: TPdfRectangle;
  if Form.TryGetBBox(BBox) then
  begin
    var Matrix := Ctm;
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

  if UsesClips then
  begin
    Area := IntersectedWithClips(Area);
  end;
  if Area.IsEmpty then
  begin
    Exit(False);
  end;

  Bounds := TRect.Create(Floor(Area.Left), Floor(Area.Top), Ceil(Area.Right), Ceil(Area.Bottom));
  Shift := GroupShift(Area);
  Result := (not Bounds.IsEmpty);
end;

// The clip chain in the pixels of a layer whose top left corner lies at (-OffsetX, -OffsetY) of the device
class function TPdfPageDrawer.ChainLength(const Clip: IPdfClipPath): Integer;
begin
  Result := 0;
  var Link := Clip;
  while Assigned(Link) do
  begin
    Inc(Result);
    Link := Link.Parent;
  end;
end;

// The innermost MaxLinks paths of the chain
class function TPdfPageDrawer.TranslatedClip(const Clip: IPdfClipPath; const OffsetX, OffsetY, MaxLinks: Integer): IPdfClipPath;
begin
  Result := nil;
  const Chain = TList<IPdfClipPath>.Create;
  try
    var Link := Clip;
    while Assigned(Link) and (Chain.Count < MaxLinks) do
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

function TPdfPageDrawer.TryRenderMaskGroup(const Form: TPDFormXObject; const Ctm: TPdfMatrix; const HasBackdrop: Boolean;
                                           const Backdrop: TPdfDeviceColor; out Bounds: TRect; out Image: TPdfBitmap): Boolean;
begin
  Image := nil;
  var Shift: Single;
  if not TryGetGroupBounds(Form, Ctm, False, Bounds, Shift) then
  begin
    Exit(False);
  end;

  const Layer = FDevice.CreateLayer(Bounds.Width, Bounds.Height);
  if HasBackdrop then
  begin
    Layer.Clear(Backdrop);
  end;

  const Reference: IPdfRasterDevice = TPdfGroupDevice.Create(Layer, nil);
  RunGroupContent(Form, Reference, Bounds, Ctm, True);
  Image := TPdfGroupDevice(Reference).ToBitmap;
  Result := True;
end;

// TransparencyGroup and showTransparencyGroupOnGraphics: the group is drawn on a layer of its own, which then is drawn on the device
// with the alpha constant and the blend mode of the graphics state. The layer starts at the top left of Bounds.
procedure TPdfPageDrawer.DrawGroup(const Form: TPDFormXObject; const Bounds: TRect; const Shift: Single);
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
    RunGroupContent(Form, Reference, Bounds, GraphicsState.CurrentTransformationMatrix, False);
    if Assigned(Backdrop) then
    begin
      TPdfGroupDevice(Reference).RemoveBackdrop(Backdrop, 0, 0);
    end;
    DrawGroupResult(TPdfGroupDevice(Reference), Bounds, Shift);
  finally
    Backdrop.Free;
  end;
end;

// The group draws on the layer: the matrix to the device moves by the corner of the layer, and so does the clip. The path under
// construction and the glyphs of a text clip belong to the operator that is running, which a soft mask may interrupt (it is made when
// that operator paints), so the group gets paths of its own.
procedure TPdfPageDrawer.RunGroupContent(const Form: TPDFormXObject; const GroupDevice: IPdfRasterDevice; const Bounds: TRect; const Ctm: TPdfMatrix;
                                         const IsSoftMask: Boolean);
begin
  const SavedDevice = FDevice;
  const SavedMatrix = FPageToDevice;
  const SavedResidualX = FTranslationResidualX;
  const SavedResidualY = FTranslationResidualY;
  const SavedLinePath = FLinePath;
  const SavedTextClip = FTextClip;
  FDevice := GroupDevice;
  FPageToDevice := SavedMatrix.Multiply(TPdfMatrix.GetTranslateInstance(-Bounds.Left, -Bounds.Top));
  // PDFBox draws a group in a space that has the scale only (TransparencyGroup), without the translation of the page, so the double
  // translation of the page matrix has no meaning inside a group
  FTranslationResidualX := 0;
  FTranslationResidualY := 0;
  FLinePath := TPdfPath.Create;
  FTextClip := TPdfPath.Create;
  FLastClip := nil;
  try
    RunGroupStream(Form, Bounds, Ctm, IsSoftMask);
  finally
    FTextClip.Free;
    FLinePath.Free;
    FTextClip := SavedTextClip;
    FLinePath := SavedLinePath;
    FDevice := SavedDevice;
    FPageToDevice := SavedMatrix;
    FTranslationResidualX := SavedResidualX;
    FTranslationResidualY := SavedResidualY;
    FLastClip := nil;
  end;
end;

// processTransparencyGroup: the blend mode starts at Normal, the alpha constants at 1 and the soft mask at none. A soft mask runs on the
// CTM that gs saw (processSoftMask), and without clip: its image does not depend on where it is drawn.
procedure TPdfPageDrawer.RunGroupStream(const Form: TPDFormXObject; const Bounds: TRect; const Ctm: TPdfMatrix; const IsSoftMask: Boolean);
begin
  const State = TPdfRenderGraphicsState(GraphicsState.Clone);
  try
    State.Clip := nil;
    if not IsSoftMask then
    begin
      State.Clip := SharedTranslatedClip(RenderState.Clip, -Bounds.Left, -Bounds.Top);
    end;
    State.CurrentTransformationMatrix := Ctm;
    State.SoftMask := nil;
    State.BlendMode := TPdfBlendMode.Normal;
    State.AlphaConstant := 1;
    State.NonStrokeAlphaConstant := 1;
    if IsSoftMask then
    begin
      StartWithBlackDeviceGray(State);
    end;
  except
    State.Free;
    raise;
  end;
  ProcessFormWithState(Form, State);
end;

procedure TPdfPageDrawer.DrawGroupResult(const GroupDevice: TPdfGroupDevice; const Bounds: TRect; const Shift: Single);
begin
  const Image = GroupDevice.ToBitmap;
  try
    ApplyClip;
    // A shift of whole pixels copies the pixels; a fraction is interpolated, like Java2D does for a translation
    var Filter := TPdfImageFilter.Nearest;
    if Frac(Shift) <> 0 then
    begin
      Filter := TPdfImageFilter.Bicubic;
    end;
    FDevice.DrawBitmap(Image, TPdfMatrix.GetTranslateInstance(Bounds.Left, Bounds.Top + Shift), Filter, NonStrokingComposite(False));
  finally
    Image.Free;
  end;
end;

end.
