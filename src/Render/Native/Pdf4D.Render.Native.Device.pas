// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.Native.Device;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Types,
  Pdf4D.Common.Matrix,
  Pdf4D.Common.Path,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Render.Native.Transform,
  Pdf4D.Render.Native.Pixmap,
  Pdf4D.Render.Native.Path,
  Pdf4D.Render.Native.Mask,
  Pdf4D.Render.Native.Shader,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.ClipMask;

type
  // A raster device on the pixels of a TPdfBitmap, drawn by the port of the painter of tiny-skia. Every method that draws runs inside
  // TTsFloatMode, because the painter works with floating point exceptions masked and the callers of the device do not. Input that cannot
  // be drawn (a path with a point that is not a number, a matrix that cannot be inverted, a dash that is refused) draws nothing.
  //
  // The soft mask of a composite is not applied yet.
  TPdfNativeDevice = class(TInterfacedObject, IPdfRasterDevice)
  private
    FBitmap: TPdfBitmap;
    FPixmap: TTsPixmap;
    FClip: IPdfClipPath;
    FClipMask: TTsClipMask;

    // The clip of the next draw: False when it clips everything away. Mask is nil for a clip without a mask.
    function TryPrepareClip(out Clip: TTsScreenIntRect; out Mask: PTsMask): Boolean;
    // The paint for a draw in device pixels after PathToDevice: False when nothing can be drawn with it
    function TryMakePaint(const Paint: TPdfPaint; const Composite: TPdfComposite; const PathToDevice: TTsTransform;
                          out Source: TPdfBitmap; out TsPaint: TTsPaint): Boolean;
    // Bitmap itself, or a copy of it when it is the bitmap of this device: a draw never reads the pixels that it writes
    function SourceOf(const Bitmap: TPdfBitmap; out Copy: TPdfBitmap): TPdfBitmap;
    function TryMakeFillPath(const Path: TPdfPath; const Transform: TPdfMatrix; const DeviceTransform: TTsTransform;
                             const AntiAlias: Boolean; out DevicePath: TTsPath): Boolean;
    procedure DoFillPath(const Path: TPdfPath; const Transform: TPdfMatrix; const FillRule: TPdfFillRule; const Paint: TPdfPaint;
                         const Composite: TPdfComposite);
    procedure DoStrokePath(const Path: TPdfPath; const Transform: TPdfMatrix; const Stroke: TPdfStrokeStyle; const Paint: TPdfPaint;
                           const Composite: TPdfComposite);
    procedure DoDrawBitmap(const Bitmap: TPdfBitmap; const BitmapToDevice: TPdfMatrix; const Filter: TPdfImageFilter;
                           const Composite: TPdfComposite);
    function ReadArea(const Area: TRect): TPdfBitmap;
{$IFDEF PDF4D_TESTS}
    function GetBuildCount: Integer;
    function GetClipKind: TTsClipKind;
    function GetForceMaskClip: Boolean;
    procedure SetForceMaskClip(const Value: Boolean);
{$ENDIF}

  public
    // Takes ownership of Bitmap
    constructor Create(const Bitmap: TPdfBitmap);
    destructor Destroy; override;

    function Width: Integer;
    function Height: Integer;
    procedure SetClip(const Clip: IPdfClipPath);
    procedure FillPath(const Path: TPdfPath; const Transform: TPdfMatrix; const FillRule: TPdfFillRule; const Paint: TPdfPaint;
                       const Composite: TPdfComposite);
    procedure StrokePath(const Path: TPdfPath; const Transform: TPdfMatrix; const Stroke: TPdfStrokeStyle; const Paint: TPdfPaint;
                         const Composite: TPdfComposite);
    procedure DrawBitmap(const Bitmap: TPdfBitmap; const BitmapToDevice: TPdfMatrix; const Filter: TPdfImageFilter;
                         const Composite: TPdfComposite);
    procedure Clear(const Color: TPdfDeviceColor);
    function CreateLayer(const Width, Height: Integer): IPdfRasterDevice;
    // False when Area does not overlap the device
    function TryReadPixels(const Area: TRect; out Bitmap: TPdfBitmap): Boolean;
    function ToBitmap: TPdfBitmap;

{$IFDEF PDF4D_TESTS}
    // For tests only, compiled when PDF4D_TESTS is defined: how many clip chains were built
    property ClipBuildCount: Integer read GetBuildCount;
    // For tests only: what the clip of the last draw came to
    property ClipKind: TTsClipKind read GetClipKind;
    // For tests only: makes a rectangular clip a mask as well, to compare the two ways to clip
    property ForceMaskClip: Boolean read GetForceMaskClip write SetForceMaskClip;
{$ENDIF}
  end;

implementation

uses
  Pdf4D.Render.StrokeNormalizer,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Color,
  Pdf4D.Render.Native.Stroker,
  Pdf4D.Render.Native.Painter,
  Pdf4D.Render.Native.Conversion;

const
  BytesPerPixel = 4;

// A constant alpha as the pipeline takes it: 0 for a value that is not a number, else 0..1
function SanitizedAlpha(const Alpha: Single): Single;
begin
  if not (Alpha > 0) then
  begin
    Exit(0);
  end;

  if Alpha > 1 then
  begin
    Exit(1);
  end;

  Result := Alpha;
end;

{ TPdfNativeDevice }

constructor TPdfNativeDevice.Create(const Bitmap: TPdfBitmap);
begin
  inherited Create;
  FBitmap := Bitmap;
  FPixmap := TTsPixmap.CreateOver(Bitmap);
  FClipMask := TTsClipMask.Create;
end;

destructor TPdfNativeDevice.Destroy;
begin
  FClipMask.Free;
  FBitmap.Free;
  inherited Destroy;
end;

function TPdfNativeDevice.Width: Integer;
begin
  Result := FBitmap.Width;
end;

function TPdfNativeDevice.Height: Integer;
begin
  Result := FBitmap.Height;
end;

procedure TPdfNativeDevice.SetClip(const Clip: IPdfClipPath);
begin
  // The clip is built when something is drawn: a chain that is set and replaced without a draw costs nothing
  FClip := Clip;
end;

function TPdfNativeDevice.TryPrepareClip(out Clip: TTsScreenIntRect; out Mask: PTsMask): Boolean;
begin
  FClipMask.Update(FClip, FBitmap.Width, FBitmap.Height);

  Mask := nil;
  Clip := Default(TTsScreenIntRect);
  case FClipMask.Kind of
    TTsClipKind.Empty:
      begin
        Exit(False);
      end;
    TTsClipKind.Mask:
      begin
        Mask := FClipMask.MaskRef;
      end;
  end;

  Clip := FClipMask.Rect;
  Result := True;
end;

function TPdfNativeDevice.SourceOf(const Bitmap: TPdfBitmap; out Copy: TPdfBitmap): TPdfBitmap;
begin
  Copy := nil;

  const IsOwnBitmap = (Pointer(Bitmap.Pixels) = Pointer(FBitmap.Pixels));
  if not IsOwnBitmap then
  begin
    Exit(Bitmap);
  end;

  Copy := Bitmap.Clone;
  Result := Copy;
end;

// The paint of a draw whose path goes through PathToDevice in the painter: the bitmap of a bitmap paint is placed by BitmapToDevice alone,
// so the shader gets the matrix that the painter will concatenate with PathToDevice taken out again
function TPdfNativeDevice.TryMakePaint(const Paint: TPdfPaint; const Composite: TPdfComposite; const PathToDevice: TTsTransform;
                                       out Source: TPdfBitmap; out TsPaint: TTsPaint): Boolean;
begin
  Source := nil;
  TsPaint := TTsPaint.Default;
  TsPaint.BlendMode := TTsConversion.ToBlendMode(Composite.BlendMode);
  TsPaint.AntiAlias := Composite.AntiAlias;

  case Paint.Kind of
    TPdfPaintKind.Solid:
      begin
        TsPaint.Shader := TTsShader.NewSolidColor(TTsConversion.ToColor(Paint.Color, Composite.Alpha));
        Result := True;
      end;
    TPdfPaintKind.Bitmap:
      begin
        if not Assigned(Paint.Bitmap) then
        begin
          Exit(False);
        end;

        var BitmapToDevice: TTsTransform;
        if not TTsConversion.TryToDeviceTransform(Paint.BitmapToDevice, BitmapToDevice) then
        begin
          Exit(False);
        end;

        var ShaderTransform := BitmapToDevice;
        if not PathToDevice.IsIdentity then
        begin
          var Inverse: TTsTransform;
          if not PathToDevice.TryInvert(Inverse) then
          begin
            Exit(False);
          end;

          ShaderTransform := BitmapToDevice.PostConcat(Inverse);
        end;

        const Pixmap = TTsPixmap.CreateOver(SourceOf(Paint.Bitmap, Source));
        TsPaint.Shader := TTsShader.NewPattern(Pixmap.AsRef, TTsConversion.ToSpreadMode(Paint.TileMode),
                                               TTsConversion.ToFilterQuality(Paint.Filter), SanitizedAlpha(Composite.Alpha), ShaderTransform);
        Result := True;
      end;
  else
    raise ENotSupportedException.CreateFmt('Unsupported paint kind: %d', [Ord(Paint.Kind)]);
  end;
end;

// The path in device pixels, for a fill: with anti-aliasing the path as it is, without it the edges are snapped as Java2D does
function TPdfNativeDevice.TryMakeFillPath(const Path: TPdfPath; const Transform: TPdfMatrix; const DeviceTransform: TTsTransform;
                                          const AntiAlias: Boolean; out DevicePath: TTsPath): Boolean;
begin
  DevicePath := Default(TTsPath);

  if AntiAlias then
  begin
    var PathSpace: TTsPath;
    if not TTsConversion.TryToPath(Path, PathSpace) then
    begin
      Exit(False);
    end;

    Exit(PathSpace.TryTransform(DeviceTransform, DevicePath));
  end;

  // PDFBox fills rectangles without anti-aliasing, and the edges of such a fill lie at ceil(x) in the reference images, where tiny-skia
  // would take the nearest pixel boundary
  const Snapped = TPdfStrokeNormalizer.SnapForFill(Path, Transform);
  try
    Result := TTsConversion.TryToPath(Snapped, DevicePath);
  finally
    Snapped.Free;
  end;
end;

procedure TPdfNativeDevice.FillPath(const Path: TPdfPath; const Transform: TPdfMatrix; const FillRule: TPdfFillRule; const Paint: TPdfPaint;
                                    const Composite: TPdfComposite);
begin
  const FloatState = TTsFloatMode.Enter;
  try
    DoFillPath(Path, Transform, FillRule, Paint, Composite);
  finally
    TTsFloatMode.Leave(FloatState);
  end;
end;

procedure TPdfNativeDevice.DoFillPath(const Path: TPdfPath; const Transform: TPdfMatrix; const FillRule: TPdfFillRule;
                                      const Paint: TPdfPaint; const Composite: TPdfComposite);
begin
  var Clip: TTsScreenIntRect;
  var Mask: PTsMask;
  if not TryPrepareClip(Clip, Mask) then
  begin
    Exit;
  end;

  var DeviceTransform: TTsTransform;
  if not TTsConversion.TryToDeviceTransform(Transform, DeviceTransform) then
  begin
    Exit;
  end;

  var DevicePath: TTsPath;
  if not TryMakeFillPath(Path, Transform, DeviceTransform, Composite.AntiAlias, DevicePath) then
  begin
    Exit;
  end;

  // The path is already in device pixels, so the painter has nothing to transform and the shader keeps its own matrix
  var Source: TPdfBitmap;
  var TsPaint: TTsPaint;
  const HasPaint = TryMakePaint(Paint, Composite, TTsTransform.Identity, Source, TsPaint);
  try
    if HasPaint then
    begin
      TTsPainter.FillPath(FPixmap, DevicePath, TsPaint, TTsConversion.ToFillRule(FillRule), TTsTransform.Identity, Clip, Mask);
    end;
  finally
    Source.Free;
  end;
end;

procedure TPdfNativeDevice.StrokePath(const Path: TPdfPath; const Transform: TPdfMatrix; const Stroke: TPdfStrokeStyle; const Paint: TPdfPaint;
                                      const Composite: TPdfComposite);
begin
  const FloatState = TTsFloatMode.Enter;
  try
    DoStrokePath(Path, Transform, Stroke, Paint, Composite);
  finally
    TTsFloatMode.Leave(FloatState);
  end;
end;

procedure TPdfNativeDevice.DoStrokePath(const Path: TPdfPath; const Transform: TPdfMatrix; const Stroke: TPdfStrokeStyle;
                                        const Paint: TPdfPaint; const Composite: TPdfComposite);
begin
  var Clip: TTsScreenIntRect;
  var Mask: PTsMask;
  if not TryPrepareClip(Clip, Mask) then
  begin
    Exit;
  end;

  var DeviceTransform: TTsTransform;
  if not TTsConversion.TryToDeviceTransform(Transform, DeviceTransform) then
  begin
    Exit;
  end;

  var TsStroke: TTsStroke;
  if not TTsConversion.TryToStroke(Stroke, TsStroke) then
  begin
    Exit;
  end;

  var PathSpace: TTsPath;
  if not TTsConversion.TryToPath(Path, PathSpace) then
  begin
    Exit;
  end;

  // The stroke is built in path space and then transformed by the painter, so the shader has to be made for that transform
  var Source: TPdfBitmap;
  var TsPaint: TTsPaint;
  const HasPaint = TryMakePaint(Paint, Composite, DeviceTransform, Source, TsPaint);
  try
    if HasPaint then
    begin
      TTsPainter.StrokePath(FPixmap, PathSpace, TsPaint, TsStroke, DeviceTransform, Clip, Mask);
    end;
  finally
    Source.Free;
  end;
end;

procedure TPdfNativeDevice.DrawBitmap(const Bitmap: TPdfBitmap; const BitmapToDevice: TPdfMatrix; const Filter: TPdfImageFilter;
                                      const Composite: TPdfComposite);
begin
  const FloatState = TTsFloatMode.Enter;
  try
    DoDrawBitmap(Bitmap, BitmapToDevice, Filter, Composite);
  finally
    TTsFloatMode.Leave(FloatState);
  end;
end;

procedure TPdfNativeDevice.DoDrawBitmap(const Bitmap: TPdfBitmap; const BitmapToDevice: TPdfMatrix; const Filter: TPdfImageFilter;
                                        const Composite: TPdfComposite);
begin
  if not Assigned(Bitmap) then
  begin
    Exit;
  end;

  var Clip: TTsScreenIntRect;
  var Mask: PTsMask;
  if not TryPrepareClip(Clip, Mask) then
  begin
    Exit;
  end;

  var DeviceTransform: TTsTransform;
  if not TTsConversion.TryToDeviceTransform(BitmapToDevice, DeviceTransform) then
  begin
    Exit;
  end;

  var PixmapPaint := TTsPixmapPaint.Default;
  PixmapPaint.Opacity := SanitizedAlpha(Composite.Alpha);
  PixmapPaint.BlendMode := TTsConversion.ToBlendMode(Composite.BlendMode);
  PixmapPaint.Quality := TTsConversion.ToFilterQuality(Filter);

  var Copy: TPdfBitmap := nil;
  try
    const Source = TTsPixmap.CreateOver(SourceOf(Bitmap, Copy));
    TTsPainter.DrawPixmap(FPixmap, 0, 0, Source.AsRef, PixmapPaint, DeviceTransform, Clip, Mask);
  finally
    Copy.Free;
  end;
end;

procedure TPdfNativeDevice.Clear(const Color: TPdfDeviceColor);
begin
  const Red = TTsColorMath.PremultiplyU8(Color.R, Color.A);
  const Green = TTsColorMath.PremultiplyU8(Color.G, Color.A);
  const Blue = TTsColorMath.PremultiplyU8(Color.B, Color.A);

  // Clearing does not obey the clip
  const Pixels = FBitmap.Pixels;
  for var Index := 0 to FBitmap.Width * FBitmap.Height - 1 do
  begin
    Pixels[Index * BytesPerPixel] := Red;
    Pixels[Index * BytesPerPixel + 1] := Green;
    Pixels[Index * BytesPerPixel + 2] := Blue;
    Pixels[Index * BytesPerPixel + 3] := Color.A;
  end;
end;

function TPdfNativeDevice.CreateLayer(const Width, Height: Integer): IPdfRasterDevice;
begin
  Result := TPdfNativeDevice.Create(TPdfBitmap.Create(Width, Height));
end;

function TPdfNativeDevice.TryReadPixels(const Area: TRect; out Bitmap: TPdfBitmap): Boolean;
begin
  Bitmap := nil;

  const DeviceArea = TRect.Create(0, 0, FBitmap.Width, FBitmap.Height);
  const Visible = TRect.Intersect(Area, DeviceArea);
  const HasPixels = not Visible.IsEmpty;
  if not HasPixels then
  begin
    Exit(False);
  end;

  Bitmap := ReadArea(Visible);
  Result := True;
end;

function TPdfNativeDevice.ToBitmap: TPdfBitmap;
begin
  Result := FBitmap.Clone;
end;

function TPdfNativeDevice.ReadArea(const Area: TRect): TPdfBitmap;
begin
  Result := TPdfBitmap.Create(Area.Width, Area.Height);
  try
    const RowBytes = Area.Width * BytesPerPixel;
    for var Row := 0 to Area.Height - 1 do
    begin
      Move(FBitmap.ScanLine(Area.Top + Row)[Area.Left * BytesPerPixel], Result.ScanLine(Row)^, RowBytes);
    end;
  except
    Result.Free;
    raise;
  end;
end;

{$IFDEF PDF4D_TESTS}
function TPdfNativeDevice.GetBuildCount: Integer;
begin
  Result := FClipMask.BuildCount;
end;

function TPdfNativeDevice.GetClipKind: TTsClipKind;
begin
  Result := FClipMask.Kind;
end;

function TPdfNativeDevice.GetForceMaskClip: Boolean;
begin
  Result := FClipMask.ForceMask;
end;

procedure TPdfNativeDevice.SetForceMaskClip(const Value: Boolean);
begin
  FClipMask.ForceMask := Value;
end;
{$ENDIF}

end.
