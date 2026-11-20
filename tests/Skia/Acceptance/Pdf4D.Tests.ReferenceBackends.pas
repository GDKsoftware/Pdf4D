// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.ReferenceBackends;

{$EXCESSPRECISION OFF}

interface

uses
  Pdf4D.Render.Device.Interfaces;

type
  // The backend that the acceptance tests against the PDFBox reference images render with. A later phase that has its own rasterizer
  // changes this one function and runs the same tests.
  TReferenceBackends = record
    class function Create: IPdfRenderBackend; static;
  end;

implementation

uses
  Pdf4D.Render.Skia.Backend;

{ TReferenceBackends }

class function TReferenceBackends.Create: IPdfRenderBackend;
begin
  Result := TPdfSkiaBackend.Create;
end;

end.
