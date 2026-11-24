// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.FMX.Backend.Skia;

{$EXCESSPRECISION OFF}

interface

uses
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Viewer.Backend;

type
  // Puts the Skia render backend on a form: link it to the Backend property of a document. The application needs sk4d.dll next to
  // its program.
  TPdf4DSkiaBackend = class(TPdf4DRenderBackend)
  public
    function CreateBackend: IPdfRenderBackend; override;
  end;

implementation

uses
  Pdf4D.Render.Skia.Backend;

{ TPdf4DSkiaBackend }

function TPdf4DSkiaBackend.CreateBackend: IPdfRenderBackend;
begin
  Result := TPdfSkiaBackend.Create;
end;

end.
