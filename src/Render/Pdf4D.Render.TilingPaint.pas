// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/rendering/TilingPaint.java and TilingPaintFactory.java (3.0.8). The cell of a pattern is
// drawn on a layer of the device (getImage), and the paint is the bitmap of that cell repeated (the TexturePaint of Java2D) with the
// matrix that createContext makes: the pattern matrix without its scaling, which the cell has already.
unit Pdf4D.Render.TilingPaint;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  System.Generics.Collections,
  Pdf4D.Common.Matrix,
  Pdf4D.Graphics.Color,
  Pdf4D.Graphics.Pattern,
  Pdf4D.Model.Rectangle,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Render.Options;

type
  // What the paint needs of the page drawer, which uses the paint: PDFBox gives TilingPaint the PageDrawer itself
  IPdfTilingHost = interface
    ['{4D1B8F36-52A9-4E7C-9B03-6A1E2C7D8F54}']
    // PDFStreamEngine.getInitialMatrix of the stream the pattern is used in
    function InitialMatrix: TPdfMatrix;
    function Options: TPdfRenderOptions;
    procedure LogWarning(const Fmt: string; const Args: array of const);
    // A transparent layer of the device that is drawn on
    function CreateLayer(const Width, Height: Integer): IPdfRasterDevice;
    // PageDrawer.drawTilingPattern: runs the content of the pattern on Layer, with PatternMatrix as the matrix of the content and
    // LayerTransform as the matrix from the space after that to the pixels of the layer. The colour space is that of an uncoloured pattern
    // (it may be nil for one that has none) and nil for a coloured one; the colour is the pattern colour with its components.
    procedure DrawTilingPattern(const Layer: IPdfRasterDevice; const Pattern: TPDTilingPattern; const ColorSpace: TPDColorSpace;
                                const Color: TPDColor; const PatternMatrix: TPdfMatrix; const LayerTransform: TPdfMatrix);
  end;

  // The sizes of the cell of a pattern: TilingPaint.getAnchorRect and the size of the image of getImage
  TPdfTilingGeometry = record
  private
    FPatternToPage: TPdfMatrix;
    FScalingFactorX: Single;
    FScalingFactorY: Single;
    FBox: TPdfRectangle;
    // The anchor rectangle: where the box lies in the scaled pattern space, and the size of a step in it (negative for a negative step)
    FAnchorX: Single;
    FAnchorY: Single;
    FAnchorWidth: Single;
    FAnchorHeight: Single;
    FRasterWidth: Integer;
    FRasterHeight: Integer;
    // The scale from points to pixels of the cell
    FCellScaleX: Single;
    FCellScaleY: Single;

    class function Ceiling(const Value: Double): Integer; static;
    class function IsUsable(const Value: Single): Boolean; static;
    class procedure ClampEdge(const Host: IPdfTilingHost; const Pattern: TPDTilingPattern; var Width, Height: Single); static;
    procedure SizeRaster(const Width, Height, EdgeLimit: Single; const ScaleX, ScaleY: Single);

  public
    // False, with a line in the log, for a pattern that has no box, a step that is not a number or a pattern matrix without scale. Xform is the
    // matrix from the space of the page to the device, of which the scale decides how many pixels the cell has.
    class function TryCreate(const Host: IPdfTilingHost; const Pattern: TPDTilingPattern; const Xform: TPdfMatrix; out Geometry: TPdfTilingGeometry): Boolean; static;

    // The matrix of the content of the cell: only the scale of the pattern matrix, with the origin of the box moved to (0, 0)
    function ContentMatrix: TPdfMatrix;
    // From the space after the content matrix to the pixels of the cell: the scale of the device, and the flips of negative steps
    function LayerTransform(const Pattern: TPDTilingPattern): TPdfMatrix;
    // The paint matrix of TilingPaint.createContext for a fill that is made with Xform
    function BitmapToDevice(const Xform: TPdfMatrix): TPdfMatrix;
    // The number of cells that the paint repeats over Area (device pixels), an estimate; infinite for a step without size on the device
    function CellCount(const Area: TRect; const Xform: TPdfMatrix): Double;

    property RasterWidth: Integer read FRasterWidth;
    property RasterHeight: Integer read FRasterHeight;
  end;

  // TilingPaint.TilingPaint: the cell of a pattern and the paint that repeats it
  TPdfTilingPaint = class
  private
    // Java2D takes, for a device pixel, the texel under the top left corner of the pixel (TexturePaintContext), Skia the one under its centre. The
    // matrix of the paint moves the texels by half a pixel to give the same texel, and by a small bias to the side where an exact edge of a texel
    // belongs to the texel that Java takes. The references show this on a pattern that is turned over by the page: its rows lie one pixel lower.
    class function SamplingMatrix(const BitmapToDevice: TPdfMatrix): TPdfMatrix; static;

  public
    // Draws the cell. Paint refers to Cell, which the caller owns and keeps as long as the paint is used. False, with a line in the log, when the
    // pattern cannot be drawn (see TPdfTilingGeometry.TryCreate, and a layer that cannot be made).
    class function TryCreate(const Host: IPdfTilingHost; const Pattern: TPDTilingPattern; const ColorSpace: TPDColorSpace; const Color: TPDColor;
                             const Xform: TPdfMatrix; out Paint: TPdfPaint; out Cell: TPdfBitmap): Boolean; static;
    // The same for a geometry that the caller has made
    class function TryCreateFromGeometry(const Host: IPdfTilingHost; const Geometry: TPdfTilingGeometry; const Pattern: TPDTilingPattern;
                                         const ColorSpace: TPDColorSpace; const Color: TPDColor; const Xform: TPdfMatrix; out Paint: TPdfPaint;
                                         out Cell: TPdfBitmap): Boolean; static;
  end;

  // TilingPaintFactory: the paints that were made, by pattern, colour and matrices. A cell stays as long as it is in the cache, so the cache
  // is limited in number and in pixels; the oldest paint goes first.
  TPdfTilingPaintFactory = class
  private
    type
      TCachedPaint = class
      public
        // The stream of the pattern
        Stream: TObject;
        ColorSpace: TPDColorSpace;
        Components: TArray<Single>;
        Xform: TPdfMatrix;
        InitialMatrix: TPdfMatrix;
        Paint: TPdfPaint;
        Cell: TPdfBitmap;

        destructor Destroy; override;
        function Matches(const Stream: TObject; const CandidateSpace: TPDColorSpace; const CandidateComponents: TArray<Single>;
                         const CandidateXform, CandidateInitial: TPdfMatrix): Boolean;
        function Pixels: Int64;
      end;

    const MaxCachedPaints = 16;
    const MaxCachedPixels = 16 * 1024 * 1024;

  private
    FHost: IPdfTilingHost;
    FPaints: TObjectList<TCachedPaint>;

    function TryFind(const Stream: TObject; const ColorSpace: TPDColorSpace; const Color: TPDColor; const Xform: TPdfMatrix; out Cached: TCachedPaint): Boolean;
    procedure Add(const Stream: TObject; const ColorSpace: TPDColorSpace; const Color: TPDColor; const Xform: TPdfMatrix; const Paint: TPdfPaint;
                  const Cell: TPdfBitmap);
    procedure MakeRoomFor(const Pixels: Int64);
    function CachedPixels: Int64;
    function IsTooManyCells(const Geometry: TPdfTilingGeometry; const Xform: TPdfMatrix; const Area: TRect): Boolean;

  public
    constructor Create(const Host: IPdfTilingHost);
    destructor Destroy; override;

    // The paint for the pattern; it lives until the next call that makes a paint. Area is what is painted, in device pixels: a pattern that would
    // repeat over it more than MaxTilingCells times is not painted. False when nothing is to be painted.
    function TryGetPaint(const Pattern: TPDTilingPattern; const ColorSpace: TPDColorSpace; const Color: TPDColor; const Xform: TPdfMatrix;
                         const Area: TRect; out Paint: TPdfPaint): Boolean;
  end;

implementation

uses
  System.Math,
  System.SysUtils,
  Pdf4D.Common.Defines;

const
  HalfPixel = 0.5;
  TexelBias = 1 / 512;
  // TilingPaint.ceiling rounds to 5 decimals
  CeilingScale = 100000;
  ZeroStepWarning = '/%s is 0, using pattern /BBox %s';
  SurfaceWarning = 'Pattern surface larger than %d x %d, will be clipped (width %g, height %g, XStep %g, YStep %g)';
  BoxMissingWarning = 'Pattern /BBox is missing, nothing is painted';
  UnusableStepWarning = 'The pattern step (%g, %g) gives a cell without a usable size, nothing is painted';
  TooManyCellsWarning = 'The pattern would fill more than %d cells in the area that is painted, nothing is painted';
  CellFailedWarning = 'The cell of a pattern cannot be made, nothing is painted: %s';

{ TPdfTilingGeometry }

// TilingPaint.ceiling: BigDecimal.setScale(5, CEILING) and then intValue, which cuts off the decimals that are left
class function TPdfTilingGeometry.Ceiling(const Value: Double): Integer;
begin
  const Scaled = System.Math.Ceil(Value * CeilingScale);
  Result := Trunc(Min(Scaled / CeilingScale, Double(High(Integer))));
end;

class function TPdfTilingGeometry.IsUsable(const Value: Single): Boolean;
begin
  Result := (not (IsNan(Value) or IsInfinite(Value) or (Value = 0)));
end;

// PDFBOX-3653: a surface larger than MAXEDGE x MAXEDGE is clipped to that size per edge
class procedure TPdfTilingGeometry.ClampEdge(const Host: IPdfTilingHost; const Pattern: TPDTilingPattern;
                                              var Width, Height: Single);
begin
  const Edge = Max(Host.Options.MaxTileEdge, 1);
  const IsLarge = (Abs(Double(Width) * Double(Height)) > Double(Edge) * Edge);
  if not IsLarge then
  begin
    Exit;
  end;

  Host.LogWarning(SurfaceWarning, [Edge, Edge, Width, Height, Pattern.XStep, Pattern.YStep]);
  Width := Min(Single(Edge), Abs(Width)) * Sign(Width);
  Height := Min(Single(Edge), Abs(Height)) * Sign(Height);
end;

// The image of getImage has the size of the anchor in device pixels, rounded with Ceiling. An image of more than EdgeLimit pixels along an edge
// or more than EdgeLimit squared pixels is made smaller, and the content is drawn smaller with it, so that no pattern allocates what the
// page cannot show; PDFBox has no such limit and allocates what the pattern asks for.
procedure TPdfTilingGeometry.SizeRaster(const Width, Height, EdgeLimit: Single; const ScaleX, ScaleY: Single);
begin
  const WidthInPixels = Abs(Double(Width)) * ScaleX;
  const HeightInPixels = Abs(Double(Height)) * ScaleY;
  var PixelsX := Max(1, Ceiling(WidthInPixels));
  var PixelsY := Max(1, Ceiling(HeightInPixels));
  FCellScaleX := ScaleX;
  FCellScaleY := ScaleY;

  const Area = Double(PixelsX) * PixelsY;
  const IsTooLarge = ((PixelsX > EdgeLimit) or (PixelsY > EdgeLimit) or (Area > Double(EdgeLimit) * EdgeLimit));
  if IsTooLarge then
  begin
    const Factor = Min(Min(EdgeLimit / PixelsX, EdgeLimit / PixelsY), EdgeLimit / Sqrt(Area));
    const SmallX = Max(1, Trunc(PixelsX * Factor));
    const SmallY = Max(1, Trunc(PixelsY * Factor));
    FCellScaleX := ScaleX * SmallX / PixelsX;
    FCellScaleY := ScaleY * SmallY / PixelsY;
    PixelsX := SmallX;
    PixelsY := SmallY;
  end;

  FRasterWidth := PixelsX;
  FRasterHeight := PixelsY;
end;

// getAnchorRect and the first lines of getImage
class function TPdfTilingGeometry.TryCreate(const Host: IPdfTilingHost; const Pattern: TPDTilingPattern; const Xform: TPdfMatrix;
                                            out Geometry: TPdfTilingGeometry): Boolean;
begin
  Geometry := Default(TPdfTilingGeometry);
  if not Pattern.TryGetBBox(Geometry.FBox) then
  begin
    Host.LogWarning(BoxMissingWarning, []);
    Exit(False);
  end;

  var XStep := Pattern.XStep;
  if XStep = 0 then
  begin
    Host.LogWarning(ZeroStepWarning, ['XStep', 'width']);
    XStep := Geometry.FBox.Width;
  end;
  var YStep := Pattern.YStep;
  if YStep = 0 then
  begin
    Host.LogWarning(ZeroStepWarning, ['YStep', 'height']);
    YStep := Geometry.FBox.Height;
  end;

  try
    Geometry.FPatternToPage := TPdfMatrix.Concatenate(Host.InitialMatrix, Pattern.Matrix);
  except
    on Failure: EPdfException do
    begin
      Host.LogWarning(CellFailedWarning, [Failure.Message]);
      Exit(False);
    end;
  end;

  Geometry.FScalingFactorX := Geometry.FPatternToPage.ScalingFactorX;
  Geometry.FScalingFactorY := Geometry.FPatternToPage.ScalingFactorY;
  var Width: Single := XStep * Geometry.FScalingFactorX;
  var Height: Single := YStep * Geometry.FScalingFactorY;
  const IsUsableSize = (IsUsable(Width) and IsUsable(Height) and IsUsable(Geometry.FScalingFactorX) and IsUsable(Geometry.FScalingFactorY));
  if not IsUsableSize then
  begin
    Host.LogWarning(UnusableStepWarning, [Width, Height]);
    Exit(False);
  end;

  ClampEdge(Host, Pattern, Width, Height);
  Geometry.FAnchorX := Geometry.FBox.LowerLeftX * Geometry.FScalingFactorX;
  Geometry.FAnchorY := Geometry.FBox.LowerLeftY * Geometry.FScalingFactorY;
  Geometry.FAnchorWidth := Width;
  Geometry.FAnchorHeight := Height;

  // The device scale of the cell (see PDPage rendering with a DPI): the scale of the matrix, without rotation
  const ScaleX = Abs(Xform.ScalingFactorX);
  const ScaleY = Abs(Xform.ScalingFactorY);
  if not (IsUsable(ScaleX) and IsUsable(ScaleY)) then
  begin
    Host.LogWarning(UnusableStepWarning, [ScaleX, ScaleY]);
    Exit(False);
  end;

  Geometry.SizeRaster(Width, Height, Max(Host.Options.MaxTileEdge, 1), ScaleX, ScaleY);
  Result := True;
end;

function TPdfTilingGeometry.ContentMatrix: TPdfMatrix;
begin
  const Moved = TPdfMatrix.GetTranslateInstance(-FBox.LowerLeftX, -FBox.LowerLeftY);
  Result := Moved.Multiply(TPdfMatrix.GetScaleInstance(Abs(FScalingFactorX), Abs(FScalingFactorY)));
end;

// getImage: a negative YStep flips the image around its own axis, and so does a negative XStep, and then the device scale is applied
function TPdfTilingGeometry.LayerTransform(const Pattern: TPDTilingPattern): TPdfMatrix;
begin
  Result := TPdfMatrix.GetScaleInstance(FCellScaleX, FCellScaleY);
  if Pattern.XStep < 0 then
  begin
    Result := Result.Multiply(TPdfMatrix.GetScaleInstance(-1, 1)).Multiply(TPdfMatrix.GetTranslateInstance(FRasterWidth, 0));
  end;
  if Pattern.YStep < 0 then
  begin
    Result := Result.Multiply(TPdfMatrix.GetScaleInstance(1, -1)).Multiply(TPdfMatrix.GetTranslateInstance(0, FRasterHeight));
  end;
end;

// The TexturePaint puts the image on the anchor rectangle, and createContext adds the pattern matrix without its scale, and the transform
// of the graphics that fills
function TPdfTilingGeometry.BitmapToDevice(const Xform: TPdfMatrix): TPdfMatrix;
begin
  Result := TPdfMatrix.GetScaleInstance(FAnchorWidth / FRasterWidth, FAnchorHeight / FRasterHeight);
  Result := Result.Multiply(TPdfMatrix.GetTranslateInstance(FAnchorX, FAnchorY));
  Result := Result.Multiply(TPdfMatrix.GetScaleInstance(1 / FScalingFactorX, 1 / FScalingFactorY));
  Result := Result.Multiply(FPatternToPage);
  Result := Result.Multiply(Xform);
end;

function TPdfTilingGeometry.CellCount(const Area: TRect; const Xform: TPdfMatrix): Double;
begin
  const ToDevice = BitmapToDevice(Xform);
  const Origin = ToDevice.TransformPoint(0, 0);
  const StepX = ToDevice.TransformPoint(FRasterWidth, 0);
  const StepY = ToDevice.TransformPoint(0, FRasterHeight);
  const Ux = Double(StepX.X) - Origin.X;
  const Uy = Double(StepX.Y) - Origin.Y;
  const Vx = Double(StepY.X) - Origin.X;
  const Vy = Double(StepY.Y) - Origin.Y;

  const CellArea = Abs(Ux * Vy - Uy * Vx);
  const LengthX = Sqrt(Ux * Ux + Uy * Uy);
  const LengthY = Sqrt(Vx * Vx + Vy * Vy);
  const IsWithoutSize = ((CellArea = 0) or (LengthX = 0) or (LengthY = 0) or IsNan(CellArea));
  if IsWithoutSize then
  begin
    Exit(Infinity);
  end;

  // The cells that cover the area, with the row and the column that the edges of the area cut
  Result := (Double(Area.Width) * Area.Height) / CellArea + Area.Width / LengthX + Area.Height / LengthY + 1;
end;

{ TPdfTilingPaint }

class function TPdfTilingPaint.SamplingMatrix(const BitmapToDevice: TPdfMatrix): TPdfMatrix;
begin
  Result := TPdfMatrix.GetTranslateInstance(-TexelBias, -TexelBias);
  Result := Result.Multiply(BitmapToDevice);
  Result := Result.Multiply(TPdfMatrix.GetTranslateInstance(HalfPixel, HalfPixel));
end;

class function TPdfTilingPaint.TryCreate(const Host: IPdfTilingHost; const Pattern: TPDTilingPattern; const ColorSpace: TPDColorSpace;
                                         const Color: TPDColor; const Xform: TPdfMatrix; out Paint: TPdfPaint; out Cell: TPdfBitmap): Boolean;
begin
  Paint := Default(TPdfPaint);
  Cell := nil;

  var Geometry: TPdfTilingGeometry;
  if not TPdfTilingGeometry.TryCreate(Host, Pattern, Xform, Geometry) then
  begin
    Exit(False);
  end;

  Result := TryCreateFromGeometry(Host, Geometry, Pattern, ColorSpace, Color, Xform, Paint, Cell);
end;

class function TPdfTilingPaint.TryCreateFromGeometry(const Host: IPdfTilingHost; const Geometry: TPdfTilingGeometry; const Pattern: TPDTilingPattern;
                                                     const ColorSpace: TPDColorSpace; const Color: TPDColor; const Xform: TPdfMatrix; out Paint: TPdfPaint;
                                                     out Cell: TPdfBitmap): Boolean;
begin
  Paint := Default(TPdfPaint);
  Cell := nil;

  try
    const Layer = Host.CreateLayer(Geometry.RasterWidth, Geometry.RasterHeight);
    Host.DrawTilingPattern(Layer, Pattern, ColorSpace, Color, Geometry.ContentMatrix, Geometry.LayerTransform(Pattern));
    Cell := Layer.ToBitmap;
    Paint := TPdfPaint.FromBitmap(Cell, SamplingMatrix(Geometry.BitmapToDevice(Xform)), TPdfTileMode.&Repeat, TPdfImageFilter.Nearest);
    Result := True;
  except
    on Failure: EPdfException do
    begin
      FreeAndNil(Cell);
      Host.LogWarning(CellFailedWarning, [Failure.Message]);
      Result := False;
    end;
    on Failure: EArgumentException do
    begin
      FreeAndNil(Cell);
      Host.LogWarning(CellFailedWarning, [Failure.Message]);
      Result := False;
    end;
    on Failure: EOutOfMemory do
    begin
      FreeAndNil(Cell);
      Host.LogWarning(CellFailedWarning, [Failure.Message]);
      Result := False;
    end;
  end;
end;

{ TPdfTilingPaintFactory.TCachedPaint }

destructor TPdfTilingPaintFactory.TCachedPaint.Destroy;
begin
  Cell.Free;
  inherited;
end;

function TPdfTilingPaintFactory.TCachedPaint.Matches(const Stream: TObject; const CandidateSpace: TPDColorSpace;
                                                     const CandidateComponents: TArray<Single>; const CandidateXform, CandidateInitial: TPdfMatrix): Boolean;
begin
  Result := ((Self.Stream = Stream) and (ColorSpace = CandidateSpace) and (Length(Components) = Length(CandidateComponents)) and
             Xform.IsEqual(CandidateXform) and InitialMatrix.IsEqual(CandidateInitial));
  if not Result then
  begin
    Exit;
  end;

  for var Index := 0 to High(Components) do
  begin
    Result := (Result and (Components[Index] = CandidateComponents[Index]));
  end;
end;

function TPdfTilingPaintFactory.TCachedPaint.Pixels: Int64;
begin
  Result := Int64(Cell.Width) * Cell.Height;
end;

{ TPdfTilingPaintFactory }

constructor TPdfTilingPaintFactory.Create(const Host: IPdfTilingHost);
begin
  inherited Create;
  FHost := Host;
  FPaints := TObjectList<TCachedPaint>.Create(True);
end;

destructor TPdfTilingPaintFactory.Destroy;
begin
  FPaints.Free;
  inherited;
end;

function TPdfTilingPaintFactory.TryFind(const Stream: TObject; const ColorSpace: TPDColorSpace; const Color: TPDColor; const Xform: TPdfMatrix;
                                        out Cached: TCachedPaint): Boolean;
begin
  for var Candidate in FPaints do
  begin
    if Candidate.Matches(Stream, ColorSpace, Color.Components, Xform, FHost.InitialMatrix) then
    begin
      Cached := Candidate;
      Exit(True);
    end;
  end;

  Cached := nil;
  Result := False;
end;

function TPdfTilingPaintFactory.CachedPixels: Int64;
begin
  Result := 0;
  for var Candidate in FPaints do
  begin
    Result := Result + Candidate.Pixels;
  end;
end;

procedure TPdfTilingPaintFactory.MakeRoomFor(const Pixels: Int64);
begin
  while (FPaints.Count > 0) and ((FPaints.Count >= MaxCachedPaints) or (CachedPixels + Pixels > MaxCachedPixels)) do
  begin
    FPaints.Delete(0);
  end;
end;

procedure TPdfTilingPaintFactory.Add(const Stream: TObject; const ColorSpace: TPDColorSpace; const Color: TPDColor; const Xform: TPdfMatrix;
                                     const Paint: TPdfPaint; const Cell: TPdfBitmap);
begin
  MakeRoomFor(Int64(Cell.Width) * Cell.Height);

  const Cached = TCachedPaint.Create;
  Cached.Stream := Stream;
  Cached.ColorSpace := ColorSpace;
  Cached.Components := Copy(Color.Components);
  Cached.Xform := Xform;
  Cached.InitialMatrix := FHost.InitialMatrix;
  Cached.Paint := Paint;
  Cached.Cell := Cell;
  FPaints.Add(Cached);
end;

function TPdfTilingPaintFactory.IsTooManyCells(const Geometry: TPdfTilingGeometry; const Xform: TPdfMatrix; const Area: TRect): Boolean;
begin
  Result := (Geometry.CellCount(Area, Xform) > FHost.Options.MaxTilingCells);
  if Result then
  begin
    FHost.LogWarning(TooManyCellsWarning, [FHost.Options.MaxTilingCells]);
  end;
end;

function TPdfTilingPaintFactory.TryGetPaint(const Pattern: TPDTilingPattern; const ColorSpace: TPDColorSpace; const Color: TPDColor;
                                            const Xform: TPdfMatrix; const Area: TRect; out Paint: TPdfPaint): Boolean;
begin
  Paint := Default(TPdfPaint);
  var Cached: TCachedPaint;
  if TryFind(Pattern.Stream, ColorSpace, Color, Xform, Cached) then
  begin
    Paint := Cached.Paint;
    Exit(True);
  end;

  var Geometry: TPdfTilingGeometry;
  if not TPdfTilingGeometry.TryCreate(FHost, Pattern, Xform, Geometry) then
  begin
    Exit(False);
  end;

  if IsTooManyCells(Geometry, Xform, Area) then
  begin
    Exit(False);
  end;

  var Cell: TPdfBitmap;
  if not TPdfTilingPaint.TryCreateFromGeometry(FHost, Geometry, Pattern, ColorSpace, Color, Xform, Paint, Cell) then
  begin
    Exit(False);
  end;

  Add(Pattern.Stream, ColorSpace, Color, Xform, Paint, Cell);
  Result := True;
end;

end.
