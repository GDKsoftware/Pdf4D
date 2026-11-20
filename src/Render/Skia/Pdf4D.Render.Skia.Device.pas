// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.Skia.Device;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Types,
  System.Skia,
  Pdf4D.Common.Matrix,
  Pdf4D.Common.Path,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Device.Interfaces;

type
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
    procedure GuardComposite(const Composite: TPdfComposite);
    procedure DrawPath(const Path: TPdfPath; const FillRule: TPdfFillRule; const Transform: TPdfMatrix; const Paint: TPdfPaint;
                       const Composite: TPdfComposite; const Stroke: TPdfStrokeStyle; const IsStroke: Boolean);
    function ReadArea(const Area: TRect): TPdfBitmap;

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
  Pdf4D.Render.Skia.Convert;

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
  GuardComposite(Composite);

  TPdfFloatGuard.Run(
    procedure
    begin
      const Image = TPdfSkiaConvert.Image(Bitmap);
      const Paint = TPdfSkiaConvert.ImagePaint(Composite);
      const Destination = TRectF.Create(0, 0, Bitmap.Width, Bitmap.Height);

      FCanvas.SetMatrix(TPdfSkiaConvert.Matrix(BitmapToDevice));
      FCanvas.DrawImageRect(Image, Destination, TPdfSkiaConvert.ImageSampling(Filter), Paint);
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
  raise ENotImplemented.Create('Offscreen layers of the Skia device are not implemented yet');
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

procedure TPdfSkiaDevice.CreateSurface;
begin
  TPdfFloatGuard.Run(
    procedure
    begin
      FSurface := TSkSurface.MakeRaster(FWidth, FHeight, TSkColorType.RGBA8888, TSkAlphaType.Premul);
      FCanvas := FSurface.Canvas;
      FBaseLevel := FCanvas.Save;
    end);

  const HasSurface = Assigned(FSurface);
  if not HasSurface then
  begin
    raise EOutOfMemory.CreateFmt('Skia could not make a %d x %d surface', [FWidth, FHeight]);
  end;
end;

procedure TPdfSkiaDevice.ApplyClip(const Clip: IPdfClipPath);
begin
  TPdfFloatGuard.Run(
    procedure
    begin
      FCanvas.RestoreToCount(FBaseLevel);
      FCanvas.Save;
      ClipChain(Clip);
    end);

  FClip := Clip;
end;

// From the root to the leaf: every path narrows the clip of the paths before it
procedure TPdfSkiaDevice.ClipChain(const Clip: IPdfClipPath);
begin
  const HasClip = Assigned(Clip);
  if not HasClip then
  begin
    Exit;
  end;

  ClipChain(Clip.Parent);

  FCanvas.SetMatrix(TPdfSkiaConvert.Matrix(Clip.Transform));
  FCanvas.ClipPath(TPdfSkiaConvert.Path(Clip.Path, Clip.FillRule), TSkClipOp.Intersect, False);
end;

procedure TPdfSkiaDevice.GuardComposite(const Composite: TPdfComposite);
begin
  const IsPlain = ((Composite.BlendMode = TPdfBlendMode.Normal) and not Assigned(Composite.SoftMask));
  if not IsPlain then
  begin
    raise ENotImplemented.Create('Blend modes and soft masks of the Skia device are not implemented yet');
  end;
end;

procedure TPdfSkiaDevice.DrawPath(const Path: TPdfPath; const FillRule: TPdfFillRule; const Transform: TPdfMatrix; const Paint: TPdfPaint;
                                  const Composite: TPdfComposite; const Stroke: TPdfStrokeStyle; const IsStroke: Boolean);
begin
  GuardComposite(Composite);

  TPdfFloatGuard.Run(
    procedure
    begin
      var SkPaint: ISkPaint;
      const HasPaint = TPdfSkiaConvert.TryMakePaint(Paint, Transform, Composite, SkPaint);
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
