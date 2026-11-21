// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.Skia.Device;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Types,
  System.Math.Vectors,
  System.Skia,
  Pdf4D.Common.Matrix,
  Pdf4D.Common.Path,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Device.Interfaces;

type
  TPdfDrawWithComposite = reference to procedure(const Composite: TPdfComposite);

  // A raster device on a Skia surface of premultiplied RGBA. Every Skia call runs inside TPdfFloatGuard, because Skia works
  // with floating point exceptions masked and the callers of the device do not.
  TPdfSkiaDevice = class(TInterfacedObject, IPdfRasterDevice)
  private
    FWidth: Integer;
    FHeight: Integer;
    FSurface: ISkSurface;
    FCanvas: ISkCanvas;
    // The save level of the canvas without any clip
    FBaseLevel: Integer;
    FClip: IPdfClipPath;

    procedure CreateSurface;
    procedure ApplyClip(const Clip: IPdfClipPath);
    procedure ClipChain(const Clip: IPdfClipPath);
    procedure ResetCanvasClip;
    // Runs Draw with Composite itself, or, with a soft mask, with a plain composite on a layer that is masked and then put on the canvas
    procedure Composited(const Composite: TPdfComposite; const Draw: TPdfDrawWithComposite);
    procedure DrawMasked(const Composite: TPdfComposite; const Draw: TPdfDrawWithComposite);
    function MaskedArea(const Mask: TPdfAlphaMask): TRect;
    procedure ApplyMask(const Mask: TPdfAlphaMask; const Area: TRect);
    procedure DrawPath(const Path: TPdfPath; const FillRule: TPdfFillRule; const Transform: TPdfMatrix; const Paint: TPdfPaint;
                       const Composite: TPdfComposite; const Stroke: TPdfStrokeStyle; const IsStroke: Boolean);
    function ReadArea(const Area: TRect): TPdfBitmap;

  protected
    // Nil when Skia cannot allocate the surface
    function MakeSurface: ISkSurface; virtual;

  public
    // Raises EArgumentOutOfRangeException like TPdfBitmap.CheckSize
    constructor Create(const Width, Height: Integer);

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
  end;

implementation

uses
  Pdf4D.Common.FloatGuard,
  Pdf4D.Render.Skia.Convert,
  Pdf4D.Render.StrokeNormalizer;

const
  MaxChannel = 255;

{ TPdfSkiaDevice }

constructor TPdfSkiaDevice.Create(const Width, Height: Integer);
begin
  TPdfBitmap.CheckSize(Width, Height);

  inherited Create;
  FWidth := Width;
  FHeight := Height;
  CreateSurface;
end;

function TPdfSkiaDevice.Width: Integer;
begin
  Result := FWidth;
end;

function TPdfSkiaDevice.Height: Integer;
begin
  Result := FHeight;
end;

procedure TPdfSkiaDevice.SetClip(const Clip: IPdfClipPath);
begin
  const IsSameClip = (Clip = FClip);
  if IsSameClip then
  begin
    Exit;
  end;

  ApplyClip(Clip);
end;

procedure TPdfSkiaDevice.FillPath(const Path: TPdfPath; const Transform: TPdfMatrix; const FillRule: TPdfFillRule; const Paint: TPdfPaint;
                                  const Composite: TPdfComposite);
begin
  DrawPath(Path, FillRule, Transform, Paint, Composite, Default(TPdfStrokeStyle), False);
end;

procedure TPdfSkiaDevice.StrokePath(const Path: TPdfPath; const Transform: TPdfMatrix; const Stroke: TPdfStrokeStyle; const Paint: TPdfPaint;
                                    const Composite: TPdfComposite);
begin
  DrawPath(Path, TPdfFillRule.NonZero, Transform, Paint, Composite, Stroke, True);
end;

procedure TPdfSkiaDevice.DrawBitmap(const Bitmap: TPdfBitmap; const BitmapToDevice: TPdfMatrix; const Filter: TPdfImageFilter;
                                    const Composite: TPdfComposite);
begin
  TPdfFloatGuard.Run(
    procedure
    begin
      Composited(Composite,
        procedure(const Plain: TPdfComposite)
        begin
          const Image = TPdfSkiaConvert.Image(Bitmap);
          const Paint = TPdfSkiaConvert.ImagePaint(Plain);
          const Destination = TRectF.Create(0, 0, Bitmap.Width, Bitmap.Height);

          FCanvas.SetMatrix(TPdfSkiaConvert.Matrix(BitmapToDevice));
          FCanvas.DrawImageRect(Image, Destination, TPdfSkiaConvert.ImageSampling(Filter), Paint);
        end);
    end);
end;

procedure TPdfSkiaDevice.Clear(const Color: TPdfDeviceColor);
begin
  // Clearing obeys the clip of the canvas, so the clip is taken off for the clear and put back afterwards
  const Clip = FClip;
  ApplyClip(nil);

  TPdfFloatGuard.Run(
    procedure
    begin
      FCanvas.Clear(TPdfSkiaConvert.MakeColor(Color.A, Color.R, Color.G, Color.B));
    end);

  ApplyClip(Clip);
end;

function TPdfSkiaDevice.CreateLayer(const Width, Height: Integer): IPdfRasterDevice;
begin
  Result := TPdfSkiaDevice.Create(Width, Height);
end;

function TPdfSkiaDevice.TryReadPixels(const Area: TRect; out Bitmap: TPdfBitmap): Boolean;
begin
  Bitmap := nil;

  const DeviceArea = TRect.Create(0, 0, FWidth, FHeight);
  const Visible = TRect.Intersect(Area, DeviceArea);
  const HasPixels = not Visible.IsEmpty;
  if not HasPixels then
  begin
    Exit(False);
  end;

  Bitmap := ReadArea(Visible);
  Result := True;
end;

function TPdfSkiaDevice.ToBitmap: TPdfBitmap;
begin
  Result := ReadArea(TRect.Create(0, 0, FWidth, FHeight));
end;

function TPdfSkiaDevice.MakeSurface: ISkSurface;
begin
  Result := TSkSurface.MakeRaster(FWidth, FHeight, TSkColorType.RGBA8888, TSkAlphaType.Premul);
end;

procedure TPdfSkiaDevice.CreateSurface;
begin
  TPdfFloatGuard.Run(
    procedure
    begin
      FSurface := MakeSurface;
      const HasSurface = Assigned(FSurface);
      if HasSurface then
      begin
        FCanvas := FSurface.Canvas;
        FBaseLevel := FCanvas.Save;
      end;
    end);

  const HasSurface = Assigned(FSurface);
  if not HasSurface then
  begin
    // The RTL raises its own preallocated EOutOfMemory; a new instance would never be freed by the exception cleanup
    OutOfMemoryError;
  end;
end;

// When the clip cannot be applied the device has no clip, on the canvas and in FClip, so the next SetClip starts from a known state
procedure TPdfSkiaDevice.ApplyClip(const Clip: IPdfClipPath);
begin
  FClip := nil;
  try
    TPdfFloatGuard.Run(
      procedure
      begin
        FCanvas.RestoreToCount(FBaseLevel);
        FCanvas.Save;
        ClipChain(Clip);
      end);
  except
    ResetCanvasClip;
    raise;
  end;

  FClip := Clip;
end;

procedure TPdfSkiaDevice.ResetCanvasClip;
begin
  TPdfFloatGuard.Run(
    procedure
    begin
      FCanvas.RestoreToCount(FBaseLevel);
      FCanvas.Save;
    end);
end;

// From the root to the leaf: every path narrows the clip of the paths before it. Iterative, because a file can chain very many clips.
procedure TPdfSkiaDevice.ClipChain(const Clip: IPdfClipPath);
begin
  var Count := 0;
  var Link := Clip;
  while Assigned(Link) do
  begin
    Inc(Count);
    Link := Link.Parent;
  end;

  var Chain: TArray<IPdfClipPath>;
  SetLength(Chain, Count);
  Link := Clip;
  for var Index := Count - 1 downto 0 do
  begin
    Chain[Index] := Link;
    Link := Link.Parent;
  end;

  for var Item in Chain do
  begin
    // Java2D moves the vertices of a clip before it takes the pixels, so the path goes to the canvas in device pixels
    const Snapped = TPdfStrokeNormalizer.SnapForClip(Item.Path, Item.Transform);
    try
      FCanvas.SetMatrix(TMatrix.Identity);
      FCanvas.ClipPath(TPdfSkiaConvert.Path(Snapped, Item.FillRule), TSkClipOp.Intersect, False);
    finally
      Snapped.Free;
    end;
  end;
end;

procedure TPdfSkiaDevice.Composited(const Composite: TPdfComposite; const Draw: TPdfDrawWithComposite);
begin
  const HasSoftMask = Assigned(Composite.SoftMask);
  if HasSoftMask then
  begin
    DrawMasked(Composite, Draw);
  end
  else
  begin
    Draw(Composite);
  end;
end;

// The soft mask works as the SoftMask paint of PDFBox: the shape is drawn on a layer, the layer keeps only the part that the
// mask lets through, and the layer is put on the canvas with the alpha and the blend mode
procedure TPdfSkiaDevice.DrawMasked(const Composite: TPdfComposite; const Draw: TPdfDrawWithComposite);
begin
  const Area = MaskedArea(Composite.SoftMask);
  const IsEmpty = Area.IsEmpty;
  if IsEmpty then
  begin
    Exit;
  end;

  var Plain := Composite;
  Plain.Alpha := 1;
  Plain.BlendMode := TPdfBlendMode.Normal;
  Plain.SoftMask := nil;

  FCanvas.SetMatrix(TMatrix.Identity);
  FCanvas.SaveLayer(TRectF.Create(Area), TPdfSkiaConvert.LayerPaint(Composite));
  try
    Draw(Plain);
    ApplyMask(Composite.SoftMask, Area);
  finally
    FCanvas.Restore;
  end;
end;

// Outside the mask the mask has OutsideValue; when that is 0, nothing outside the mask can show, so the layer stays small
function TPdfSkiaDevice.MaskedArea(const Mask: TPdfAlphaMask): TRect;
begin
  const DeviceArea = TRect.Create(0, 0, FWidth, FHeight);
  const HidesOutside = (Mask.OutsideValue = 0);
  if not HidesOutside then
  begin
    Exit(DeviceArea);
  end;

  const MaskArea = TRect.Create(Mask.Left, Mask.Top, Mask.Left + Mask.Width, Mask.Top + Mask.Height);
  Result := TRect.Intersect(DeviceArea, MaskArea);
end;

procedure TPdfSkiaDevice.ApplyMask(const Mask: TPdfAlphaMask; const Area: TRect);
begin
  FCanvas.SetMatrix(TMatrix.Identity);

  const Image = TPdfSkiaConvert.MaskImage(Mask, Area);
  FCanvas.DrawImage(Image, Area.Left, Area.Top, TSkSamplingOptions.Create(TSkFilterMode.Nearest, TSkMipmapMode.None),
                    TPdfSkiaConvert.MaskPaint(MaxChannel));
end;

procedure TPdfSkiaDevice.DrawPath(const Path: TPdfPath; const FillRule: TPdfFillRule; const Transform: TPdfMatrix; const Paint: TPdfPaint;
                                  const Composite: TPdfComposite; const Stroke: TPdfStrokeStyle; const IsStroke: Boolean);
begin
  TPdfFloatGuard.Run(
    procedure
    begin
      Composited(Composite,
        procedure(const Plain: TPdfComposite)
        begin
          var SkPaint: ISkPaint;
          const HasPaint = TPdfSkiaConvert.TryMakePaint(Paint, Transform, Plain, SkPaint);
          if not HasPaint then
          begin
            Exit;
          end;

          if IsStroke then
          begin
            TPdfSkiaConvert.MakeStroke(Stroke, SkPaint);
          end;

          FCanvas.SetMatrix(TPdfSkiaConvert.Matrix(Transform));
          FCanvas.DrawPath(TPdfSkiaConvert.Path(Path, FillRule), SkPaint);
        end);
    end);
end;

function TPdfSkiaDevice.ReadArea(const Area: TRect): TPdfBitmap;
begin
  const Bitmap = TPdfBitmap.Create(Area.Width, Area.Height);
  try
    var IsRead := False;
    TPdfFloatGuard.Run(
      procedure
      begin
        const ImageInfo = TSkImageInfo.Create(Area.Width, Area.Height, TSkColorType.RGBA8888, TSkAlphaType.Premul);
        const Snapshot = FSurface.MakeImageSnapshot;
        IsRead := Snapshot.ReadPixels(ImageInfo, @Bitmap.Pixels[0], Bitmap.Stride, Area.Left, Area.Top);
      end);

    if not IsRead then
    begin
      raise EInvalidOpException.CreateFmt('Skia could not read the pixels of area (%d, %d, %d, %d)', [Area.Left, Area.Top, Area.Right, Area.Bottom]);
    end;
  except
    Bitmap.Free;
    raise;
  end;

  Result := Bitmap;
end;

end.
