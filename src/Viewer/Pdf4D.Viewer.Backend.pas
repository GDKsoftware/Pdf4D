// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.Backend;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  Pdf4D.Render.Device.Interfaces;

type
  // A component that makes the render backend of a document, so that the choice of backend is a property on the form
  TPdf4DRenderBackend = class(TComponent)
  public
    function CreateBackend: IPdfRenderBackend; virtual; abstract;
  end;

  TPdfViewerDefaults = class
  public
    // The backend of a document that has neither RenderBackend nor a Backend component: the own rasterizer
    class function CreateBackend: IPdfRenderBackend; static;
  end;

implementation

uses
  Pdf4D.Render.Native.Backend;

{ TPdfViewerDefaults }

class function TPdfViewerDefaults.CreateBackend: IPdfRenderBackend;
begin
  Result := TPdfNativeBackend.Create;
end;

end.
