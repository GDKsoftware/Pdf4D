// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// The pixel tests of RenderGroups on the Skia backend; the tests are in Pdf4D.Tests.RenderGroups.Base
unit Pdf4D.Tests.RenderGroups.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  DUnitX.TestFramework,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Tests.RenderGroups.Base;

type
  [TestFixture]
  TGroupDevicePixelTests = class(TGroupDevicePixelTestsBase)
  protected
    function CreateBackend: IPdfRenderBackend; override;
  end;

  [TestFixture]
  TRenderGroupTests = class(TRenderGroupTestsBase)
  protected
    function CreateBackend: IPdfRenderBackend; override;
  end;

implementation

uses
  Pdf4D.Render.Skia.Backend;

{ TGroupDevicePixelTests }

function TGroupDevicePixelTests.CreateBackend: IPdfRenderBackend;
begin
  Result := TPdfSkiaBackend.Create;
end;

{ TRenderGroupTests }

function TRenderGroupTests.CreateBackend: IPdfRenderBackend;
begin
  Result := TPdfSkiaBackend.Create;
end;

end.
