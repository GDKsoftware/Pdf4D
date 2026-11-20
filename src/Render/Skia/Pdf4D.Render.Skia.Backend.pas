// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.Skia.Backend;

{$EXCESSPRECISION OFF}

interface

uses
  Pdf4D.Render.Device.Interfaces;

type
  // The render backend on the Skia that ships with RAD Studio. Applications that use it need sk4d.dll (libsk4d.so) next to
  // the program.
  TPdfSkiaBackend = class(TInterfacedObject, IPdfRenderBackend)
  public
    constructor Create;

    function Name: string;
    function CreateRasterDevice(const Width, Height: Integer): IPdfRasterDevice;
  end;

implementation

uses
  Pdf4D.Render.Skia.Device;

const
  BackendName = 'Skia';

{ TPdfSkiaBackend }

constructor TPdfSkiaBackend.Create;
begin
  inherited Create;
end;

function TPdfSkiaBackend.Name: string;
begin
  Result := BackendName;
end;

function TPdfSkiaBackend.CreateRasterDevice(const Width, Height: Integer): IPdfRasterDevice;
begin
  Result := TPdfSkiaDevice.Create(Width, Height);
end;

end.
