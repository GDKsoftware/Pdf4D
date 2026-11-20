// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.RecordingDevice;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  System.Generics.Collections,
  Pdf4D.Common.Matrix,
  Pdf4D.Common.Path,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Device.Interfaces;

type
  {$SCOPEDENUMS ON}
  TRecordedCallKind = (Fill, Stroke, Bitmap, Clear, SetClip);
  {$SCOPEDENUMS OFF}

  // One call on the device. Paint.Bitmap is the pointer the caller passed: not owned, valid during the call only.
  TRecordedCall = record
    Kind: TRecordedCallKind;
    // The bounds of the path after Transform (of the bitmap rectangle for Bitmap, of the whole device for Clear)
    DeviceBounds: TRectF;
    Paint: TPdfPaint;
    Composite: TPdfComposite;
    Stroke: TPdfStrokeStyle;
    FillRule: TPdfFillRule;
    // The length of the clip chain at that moment (of the new clip for SetClip)
    ClipDepth: Integer;
  end;

  // Records every call instead of drawing; has no pixels
  TRecordingDevice = class(TInterfacedObject, IPdfRasterDevice)
  private
    FWidth: Integer;
    FHeight: Integer;
    FClip: IPdfClipPath;
    FCalls: TList<TRecordedCall>;
    FLayers: TList<TRecordingDevice>;
    // Keeps the layers alive; FLayers holds the same objects as class references
    FLayerReferences: TList<IPdfRasterDevice>;

    function ClipDepthOf(const Clip: IPdfClipPath): Integer;
    function NewCall(const Kind: TRecordedCallKind; const DeviceBounds: TRectF; const Composite: TPdfComposite): TRecordedCall;
    function BoundsAfterTransform(const Path: TPdfPath; const Transform: TPdfMatrix): TRectF;
    function GetLayerCount: Integer;
    function GetLayer(const Index: Integer): TRecordingDevice;

  public
    // Raises EArgumentOutOfRangeException like a real backend
    constructor Create(const Width, Height: Integer);
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
    // A new recording device that is also kept in Layers of this device
    function CreateLayer(const Width, Height: Integer): IPdfRasterDevice;
    // Always False
    function TryReadPixels(const Area: TRect; out Bitmap: TPdfBitmap): Boolean;
    // A transparent bitmap of the size of the device
    function ToBitmap: TPdfBitmap;

    // The calls in order; the list is owned by the device
    property Calls: TList<TRecordedCall> read FCalls;
    property LayerCount: Integer read GetLayerCount;
    // The layers made by CreateLayer, in order, each with its own calls
    property Layers[const Index: Integer]: TRecordingDevice read GetLayer;
    property Clip: IPdfClipPath read FClip;
  end;

  TRecordingBackend = class(TInterfacedObject, IPdfRenderBackend)
  private
    // Keeps the device alive for LastDevice
    FLastDeviceReference: IPdfRasterDevice;
    FLastDevice: TRecordingDevice;

  public
    function Name: string;
    function CreateRasterDevice(const Width, Height: Integer): IPdfRasterDevice;

    // The device of the last CreateRasterDevice call (layers are no raster devices of the backend); nil before the first call
    property LastDevice: TRecordingDevice read FLastDevice;
  end;

implementation

{ TRecordingDevice }

constructor TRecordingDevice.Create(const Width, Height: Integer);
begin
  TPdfBitmap.CheckSize(Width, Height);

  inherited Create;
  FWidth := Width;
  FHeight := Height;
  FCalls := TList<TRecordedCall>.Create;
  FLayers := TList<TRecordingDevice>.Create;
  FLayerReferences := TList<IPdfRasterDevice>.Create;
end;

destructor TRecordingDevice.Destroy;
begin
  FLayerReferences.Free;
  FLayers.Free;
  FCalls.Free;
  inherited;
end;

function TRecordingDevice.Width: Integer;
begin
  Result := FWidth;
end;

function TRecordingDevice.Height: Integer;
begin
  Result := FHeight;
end;

procedure TRecordingDevice.SetClip(const Clip: IPdfClipPath);
begin
  FClip := Clip;

  const Call = NewCall(TRecordedCallKind.SetClip, TRectF.Empty, TPdfComposite.Default);
  FCalls.Add(Call);
end;

procedure TRecordingDevice.FillPath(const Path: TPdfPath; const Transform: TPdfMatrix; const FillRule: TPdfFillRule;
                                    const Paint: TPdfPaint; const Composite: TPdfComposite);
begin
  var Call := NewCall(TRecordedCallKind.Fill, BoundsAfterTransform(Path, Transform), Composite);
  Call.FillRule := FillRule;
  Call.Paint := Paint;
  FCalls.Add(Call);
end;

procedure TRecordingDevice.StrokePath(const Path: TPdfPath; const Transform: TPdfMatrix; const Stroke: TPdfStrokeStyle;
                                      const Paint: TPdfPaint; const Composite: TPdfComposite);
begin
  var Call := NewCall(TRecordedCallKind.Stroke, BoundsAfterTransform(Path, Transform), Composite);
  Call.Stroke := Stroke;
  Call.Paint := Paint;
  FCalls.Add(Call);
end;

procedure TRecordingDevice.DrawBitmap(const Bitmap: TPdfBitmap; const BitmapToDevice: TPdfMatrix; const Filter: TPdfImageFilter;
                                      const Composite: TPdfComposite);
begin
  const Outline = TPdfPath.Create;
  try
    Outline.MoveTo(0, 0);
    Outline.LineTo(Bitmap.Width, 0);
    Outline.LineTo(Bitmap.Width, Bitmap.Height);
    Outline.LineTo(0, Bitmap.Height);
    Outline.ClosePath;

    var Call := NewCall(TRecordedCallKind.Bitmap, BoundsAfterTransform(Outline, BitmapToDevice), Composite);
    Call.Paint := TPdfPaint.FromBitmap(Bitmap, BitmapToDevice, TPdfTileMode.Decal, Filter);
    FCalls.Add(Call);
  finally
    Outline.Free;
  end;
end;

procedure TRecordingDevice.Clear(const Color: TPdfDeviceColor);
begin
  var Call := NewCall(TRecordedCallKind.Clear, TRectF.Create(0, 0, FWidth, FHeight), TPdfComposite.Default);
  Call.Paint := TPdfPaint.Solid(Color);
  FCalls.Add(Call);
end;

function TRecordingDevice.CreateLayer(const Width, Height: Integer): IPdfRasterDevice;
begin
  const Layer = TRecordingDevice.Create(Width, Height);
  Result := Layer;
  FLayers.Add(Layer);
  FLayerReferences.Add(Result);
end;

function TRecordingDevice.TryReadPixels(const Area: TRect; out Bitmap: TPdfBitmap): Boolean;
begin
  Bitmap := nil;
  Result := False;
end;

function TRecordingDevice.ToBitmap: TPdfBitmap;
begin
  Result := TPdfBitmap.Create(FWidth, FHeight);
end;

function TRecordingDevice.ClipDepthOf(const Clip: IPdfClipPath): Integer;
begin
  Result := 0;
  var Link := Clip;
  while Assigned(Link) do
  begin
    Inc(Result);
    Link := Link.Parent;
  end;
end;

function TRecordingDevice.NewCall(const Kind: TRecordedCallKind; const DeviceBounds: TRectF; const Composite: TPdfComposite): TRecordedCall;
begin
  Result := Default(TRecordedCall);
  Result.Kind := Kind;
  Result.DeviceBounds := DeviceBounds;
  Result.Composite := Composite;
  Result.Paint := TPdfPaint.Solid(TPdfDeviceColor.Transparent);
  Result.ClipDepth := ClipDepthOf(FClip);
end;

function TRecordingDevice.BoundsAfterTransform(const Path: TPdfPath; const Transform: TPdfMatrix): TRectF;
begin
  const DevicePath = Path.Clone;
  try
    DevicePath.Transform(Transform);
    Result := DevicePath.Bounds;
  finally
    DevicePath.Free;
  end;
end;

function TRecordingDevice.GetLayerCount: Integer;
begin
  Result := FLayers.Count;
end;

function TRecordingDevice.GetLayer(const Index: Integer): TRecordingDevice;
begin
  Result := FLayers[Index];
end;

{ TRecordingBackend }

function TRecordingBackend.Name: string;
begin
  Result := 'Recording';
end;

function TRecordingBackend.CreateRasterDevice(const Width, Height: Integer): IPdfRasterDevice;
begin
  const Device = TRecordingDevice.Create(Width, Height);
  Result := Device;
  FLastDeviceReference := Result;
  FLastDevice := Device;
end;

end.
