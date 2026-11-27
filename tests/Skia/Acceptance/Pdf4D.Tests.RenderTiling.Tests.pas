// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// The pixel tests of RenderTiling on the Skia backend; the tests are in Pdf4D.Tests.RenderTiling.Base
unit Pdf4D.Tests.RenderTiling.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  DUnitX.TestFramework,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Tests.RenderTiling.Base;

type
  [TestFixture]
  TRenderTilingTests = class(TRenderTilingTestsBase)
  protected
    function CreateBackend: IPdfRenderBackend; override;
  end;

implementation

uses
  Pdf4D.Render.Skia.Backend;

{ TRenderTilingTests }

function TRenderTilingTests.CreateBackend: IPdfRenderBackend;
begin
  Result := TPdfSkiaBackend.Create;
end;

end.
