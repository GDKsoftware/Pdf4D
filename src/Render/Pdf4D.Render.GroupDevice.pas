// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/rendering/GroupGraphics.java (3.0.8)
unit Pdf4D.Render.GroupDevice;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  Pdf4D.Common.Matrix,
  Pdf4D.Common.Path,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Device.Interfaces;

type
  // The device that a transparency group is drawn on: every operation goes to the image layer, and to the alpha layer drawn in white, so
  // that the alpha layer holds the alpha of the group alone. The image layer may start with a copy of the backdrop (a group that is not
  // isolated and has a blend mode); RemoveBackdrop takes it out of the result again. Without backdrop the alpha layer can be nil, and the
  // image layer is the result.
  TPdfGroupDevice = class(TInterfacedObject, IPdfRasterDevice)
  private
    FImage: IPdfRasterDevice;
    FAlpha: IPdfRasterDevice;
    FResult: TPdfBitmap;

    class function WhitePaint(const Paint: TPdfPaint; out WhiteBitmap: TPdfBitmap): TPdfPaint; static;
    class function WhiteCopy(const Bitmap: TPdfBitmap): TPdfBitmap; static;
    class function AlphaComposite(const Composite: TPdfComposite): TPdfComposite; static;
    class function Unpremultiplied(const Pixel: PByte; const Channel: Integer): Single; static;
    class function ClampedByte(const Value: Single): Byte; static;
    procedure RemoveBackdropFromPixel(const ImagePixel, AlphaPixel, BackdropPixel, ResultPixel: PByte; const HasBackdrop: Boolean);

  public
    // Image is required; Alpha may be nil, see above. Both have the same size.
    constructor Create(const Image, Alpha: IPdfRasterDevice);
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
    // The pixels of the image layer: what a group inside this one has as backdrop
    function TryReadPixels(const Area: TRect; out Bitmap: TPdfBitmap): Boolean;
    // The group without backdrop, with the alpha of the alpha layer, when RemoveBackdrop has been called; else the image layer
    function ToBitmap: TPdfBitmap;

    // GroupGraphics.removeBackdrop: the image layer holds the group on top of the backdrop; the result becomes the colours of the group
    // alone, with the alpha of the alpha layer (C = Cn + (Cn - C0) * (alpha0 / alphagn - alpha0), ISO 32000-1 11.4.8). Pixel (x, y) of
    // the group lies on pixel (x + OffsetX, y + OffsetY) of Backdrop; outside Backdrop the backdrop is transparent. Needs the alpha layer.
    procedure RemoveBackdrop(const Backdrop: TPdfBitmap; const OffsetX, OffsetY: Integer);
  end;

implementation

uses
  System.SysUtils,
  System.Math;

const
  BytesPerPixel = 4;
  RedOffset = 0;
  AlphaOffset = 3;
  ChannelCount = 3;
  MaxChannel = 255;
  FullAlpha: Single = 255;

{ TPdfGroupDevice }

constructor TPdfGroupDevice.Create(const Image, Alpha: IPdfRasterDevice);
begin
  if not Assigned(Image) then
  begin
    raise EArgumentNilException.Create('Image');
  end;

  inherited Create;
  FImage := Image;
  FAlpha := Alpha;
end;

destructor TPdfGroupDevice.Destroy;
begin
  FResult.Free;
  inherited;
end;

// The colour of the paint as white with the same alpha; a bitmap becomes a copy that has white where it has alpha (premultiplied)
class function TPdfGroupDevice.WhitePaint(const Paint: TPdfPaint; out WhiteBitmap: TPdfBitmap): TPdfPaint;
begin
  WhiteBitmap := nil;
  if Paint.Kind = TPdfPaintKind.Solid then
  begin
    Exit(TPdfPaint.Solid(TPdfDeviceColor.Create(MaxChannel, MaxChannel, MaxChannel, Paint.Color.A)));
  end;

  WhiteBitmap := WhiteCopy(Paint.Bitmap);
  Result := TPdfPaint.FromBitmap(WhiteBitmap, Paint.BitmapToDevice, Paint.TileMode, Paint.Filter);
end;

class function TPdfGroupDevice.WhiteCopy(const Bitmap: TPdfBitmap): TPdfBitmap;
begin
  Result := Bitmap.Clone;
  try
    for var Y := 0 to Result.Height - 1 do
    begin
      const Row = Result.ScanLine(Y);
      for var X := 0 to Result.Width - 1 do
      begin
        const Pixel = Row + X * BytesPerPixel;
        const Alpha = Pixel[AlphaOffset];
        Pixel[0] := Alpha;
        Pixel[1] := Alpha;
        Pixel[2] := Alpha;
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

// The alpha layer accumulates with plain source over: the blend mode changes the colours, not the coverage
class function TPdfGroupDevice.AlphaComposite(const Composite: TPdfComposite): TPdfComposite;
begin
  Result := Composite;
  Result.BlendMode := TPdfBlendMode.Normal;
end;

function TPdfGroupDevice.Width: Integer;
begin
  Result := FImage.Width;
end;

function TPdfGroupDevice.Height: Integer;
begin
  Result := FImage.Height;
end;

procedure TPdfGroupDevice.SetClip(const Clip: IPdfClipPath);
begin
  FImage.SetClip(Clip);
  if Assigned(FAlpha) then
  begin
    FAlpha.SetClip(Clip);
  end;
end;

procedure TPdfGroupDevice.FillPath(const Path: TPdfPath; const Transform: TPdfMatrix; const FillRule: TPdfFillRule; const Paint: TPdfPaint;
                                   const Composite: TPdfComposite);
begin
  FImage.FillPath(Path, Transform, FillRule, Paint, Composite);
  if not Assigned(FAlpha) then
  begin
    Exit;
  end;

  var WhiteBitmap: TPdfBitmap;
  const White = WhitePaint(Paint, WhiteBitmap);
  try
    FAlpha.FillPath(Path, Transform, FillRule, White, AlphaComposite(Composite));
  finally
    WhiteBitmap.Free;
  end;
end;

procedure TPdfGroupDevice.StrokePath(const Path: TPdfPath; const Transform: TPdfMatrix; const Stroke: TPdfStrokeStyle; const Paint: TPdfPaint;
                                     const Composite: TPdfComposite);
begin
  FImage.StrokePath(Path, Transform, Stroke, Paint, Composite);
  if not Assigned(FAlpha) then
  begin
    Exit;
  end;

  var WhiteBitmap: TPdfBitmap;
  const White = WhitePaint(Paint, WhiteBitmap);
  try
    FAlpha.StrokePath(Path, Transform, Stroke, White, AlphaComposite(Composite));
  finally
    WhiteBitmap.Free;
  end;
end;

procedure TPdfGroupDevice.DrawBitmap(const Bitmap: TPdfBitmap; const BitmapToDevice: TPdfMatrix; const Filter: TPdfImageFilter;
                                     const Composite: TPdfComposite);
begin
  FImage.DrawBitmap(Bitmap, BitmapToDevice, Filter, Composite);
  if not Assigned(FAlpha) then
  begin
    Exit;
  end;

  const White = WhiteCopy(Bitmap);
  try
    FAlpha.DrawBitmap(White, BitmapToDevice, Filter, AlphaComposite(Composite));
  finally
    White.Free;
  end;
end;

procedure TPdfGroupDevice.Clear(const Color: TPdfDeviceColor);
begin
  FImage.Clear(Color);
  if Assigned(FAlpha) then
  begin
    FAlpha.Clear(TPdfDeviceColor.Create(MaxChannel, MaxChannel, MaxChannel, Color.A));
  end;
end;

function TPdfGroupDevice.CreateLayer(const Width, Height: Integer): IPdfRasterDevice;
begin
  Result := FImage.CreateLayer(Width, Height);
end;

function TPdfGroupDevice.TryReadPixels(const Area: TRect; out Bitmap: TPdfBitmap): Boolean;
begin
  Result := FImage.TryReadPixels(Area, Bitmap);
end;

function TPdfGroupDevice.ToBitmap: TPdfBitmap;
begin
  if Assigned(FResult) then
  begin
    Result := FResult.Clone;
  end
  else
  begin
    Result := FImage.ToBitmap;
  end;
end;

class function TPdfGroupDevice.Unpremultiplied(const Pixel: PByte; const Channel: Integer): Single;
begin
  const Alpha = Pixel[AlphaOffset];
  if Alpha = 0 then
  begin
    Exit(0);
  end;
  Result := Min(Pixel[Channel] / Single(Alpha), 1);
end;

class function TPdfGroupDevice.ClampedByte(const Value: Single): Byte;
begin
  Result := Byte(Min(Max(Round(Value), 0), MaxChannel));
end;

procedure TPdfGroupDevice.RemoveBackdropFromPixel(const ImagePixel, AlphaPixel, BackdropPixel, ResultPixel: PByte; const HasBackdrop: Boolean);
begin
  const GroupAlpha = AlphaPixel[AlphaOffset];
  if GroupAlpha = 0 then
  begin
    Exit;
  end;

  const AlphaGroup = GroupAlpha / FullAlpha;
  var BackdropAlpha: Single := 0;
  if HasBackdrop then
  begin
    BackdropAlpha := BackdropPixel[AlphaOffset] / FullAlpha;
  end;
  const Factor = BackdropAlpha / AlphaGroup - BackdropAlpha;

  for var Channel := RedOffset to RedOffset + ChannelCount - 1 do
  begin
    const Composited = Unpremultiplied(ImagePixel, Channel);
    var BackdropColor: Single := 0;
    if HasBackdrop then
    begin
      BackdropColor := Unpremultiplied(BackdropPixel, Channel);
    end;
    const Color = Min(Max(Composited + (Composited - BackdropColor) * Factor, 0), 1);
    ResultPixel[Channel] := ClampedByte(Color * GroupAlpha);
  end;
  ResultPixel[AlphaOffset] := GroupAlpha;
end;

procedure TPdfGroupDevice.RemoveBackdrop(const Backdrop: TPdfBitmap; const OffsetX, OffsetY: Integer);
begin
  if not Assigned(FAlpha) then
  begin
    raise EInvalidOpException.Create('A group without an alpha layer has no backdrop to remove');
  end;

  const Composited = FImage.ToBitmap;
  try
    const GroupAlpha = FAlpha.ToBitmap;
    try
      const Output = TPdfBitmap.Create(Composited.Width, Composited.Height);
      FResult.Free;
      FResult := Output;

      for var Y := 0 to Output.Height - 1 do
      begin
        const BackdropY = Y + OffsetY;
        const IsRowInside = (Assigned(Backdrop) and (BackdropY >= 0) and (BackdropY < Backdrop.Height));
        for var X := 0 to Output.Width - 1 do
        begin
          const BackdropX = X + OffsetX;
          const IsInside = (IsRowInside and (BackdropX >= 0) and (BackdropX < Backdrop.Width));
          var BackdropPixel: PByte := nil;
          if IsInside then
          begin
            BackdropPixel := Backdrop.ScanLine(BackdropY) + BackdropX * BytesPerPixel;
          end;
          RemoveBackdropFromPixel(Composited.ScanLine(Y) + X * BytesPerPixel, GroupAlpha.ScanLine(Y) + X * BytesPerPixel, BackdropPixel,
                                  Output.ScanLine(Y) + X * BytesPerPixel, IsInside);
        end;
      end;
    finally
      GroupAlpha.Free;
    end;
  finally
    Composited.Free;
  end;
end;

end.
