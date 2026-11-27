// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// The render fuzz tests on the Skia backend; the tests are the ones of the shared base class
unit Pdf4D.Tests.RenderRobustness.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  DUnitX.TestFramework,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Tests.RenderRobustness.Base;

type
  [TestFixture]
  TRenderRobustnessTests = class(TRenderRobustnessTestsBase)
  protected
    function CreateBackend: IPdfRenderBackend; override;
  end;

implementation

uses
  Pdf4D.Tests.ReferenceBackends;

{ TRenderRobustnessTests }

function TRenderRobustnessTests.CreateBackend: IPdfRenderBackend;
begin
  Result := TReferenceBackends.Create;
end;

end.
