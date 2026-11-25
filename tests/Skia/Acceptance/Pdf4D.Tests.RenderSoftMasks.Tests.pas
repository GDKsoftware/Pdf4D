// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// The pixel tests of RenderSoftMasks on the Skia backend; the tests are in Pdf4D.Tests.RenderSoftMasks.Base
unit Pdf4D.Tests.RenderSoftMasks.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  DUnitX.TestFramework,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Tests.RenderSoftMasks.Base;

type
  [TestFixture]
  TRenderSoftMaskTests = class(TRenderSoftMaskTestsBase)
  protected
    function CreateBackend: IPdfRenderBackend; override;
  end;

implementation

uses
  Pdf4D.Render.Skia.Backend;

{ TRenderSoftMaskTests }

function TRenderSoftMaskTests.CreateBackend: IPdfRenderBackend;
begin
  Result := TPdfSkiaBackend.Create;
end;

end.
