// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// The render comparison with the PDFBox reference images on the Skia backend; the tests are in Pdf4D.Tests.RenderGolden.Base
unit Pdf4D.Tests.RenderGolden.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  DUnitX.TestFramework,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Tests.RenderGolden.Base;

type
  [TestFixture]
  TRenderGoldenTests = class(TRenderGoldenTestsBase)
  protected
    function CreateBackend: IPdfRenderBackend; override;
    function BackendName: string; override;
    function PendingFileName: string; override;
  end;

implementation

uses
  Pdf4D.Tests.ReferenceBackends;

{ TRenderGoldenTests }

function TRenderGoldenTests.CreateBackend: IPdfRenderBackend;
begin
  Result := TReferenceBackends.Create;
end;

function TRenderGoldenTests.BackendName: string;
begin
  Result := 'Skia';
end;

function TRenderGoldenTests.PendingFileName: string;
begin
  Result := 'pending.txt';
end;

end.
