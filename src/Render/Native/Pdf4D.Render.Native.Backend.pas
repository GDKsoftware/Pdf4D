// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.Native.Backend;

{$EXCESSPRECISION OFF}

interface

uses
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Render.Native.Limits;

type
  TPdfNativeLimits = Pdf4D.Render.Native.Limits.TPdfNativeLimits;

  // The render backend on the native rasterizer (a port of tiny-skia): no library next to the program is needed. The backend holds only its
  // limits, which nothing changes after the constructor, so one backend can serve many threads; every device is its own.
  TPdfNativeBackend = class(TInterfacedObject, IPdfRenderBackend)
  private
    FLimits: TPdfNativeLimits;

  public
    constructor Create; overload;
    constructor Create(const Limits: TPdfNativeLimits); overload;

    function Name: string;
    // Raises EArgumentOutOfRangeException when Width or Height < 1 or Width * Height > MaxBitmapPixels
    function CreateRasterDevice(const Width, Height: Integer): IPdfRasterDevice;
  end;

implementation

uses
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Native.Device;

const
  BackendName = 'Native';

{ TPdfNativeBackend }

constructor TPdfNativeBackend.Create;
begin
  Create(TPdfNativeLimits.Default);
end;

constructor TPdfNativeBackend.Create(const Limits: TPdfNativeLimits);
begin
  inherited Create;
  FLimits := Limits;
end;

function TPdfNativeBackend.Name: string;
begin
  Result := BackendName;
end;

function TPdfNativeBackend.CreateRasterDevice(const Width, Height: Integer): IPdfRasterDevice;
begin
  Result := TPdfNativeDevice.Create(TPdfBitmap.Create(Width, Height), FLimits);
end;

end.
