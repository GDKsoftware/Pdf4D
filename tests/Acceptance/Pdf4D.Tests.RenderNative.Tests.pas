// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// The pixel tests of the renderer (groups, soft masks, tiling patterns) on the native backend; the tests are the ones that the Skia backend
// runs, from the shared base classes
unit Pdf4D.Tests.RenderNative.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  DUnitX.TestFramework,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Tests.RenderGroups.Base,
  Pdf4D.Tests.RenderSoftMasks.Base,
  Pdf4D.Tests.RenderTiling.Base;

type
  [TestFixture]
  TNativeGroupDevicePixelTests = class(TGroupDevicePixelTestsBase)
  protected
    function CreateBackend: IPdfRenderBackend; override;
  end;

  [TestFixture]
  TNativeRenderGroupTests = class(TRenderGroupTestsBase)
  protected
    function CreateBackend: IPdfRenderBackend; override;
  end;

  [TestFixture]
  TNativeRenderSoftMaskTests = class(TRenderSoftMaskTestsBase)
  protected
    function CreateBackend: IPdfRenderBackend; override;
  end;

  [TestFixture]
  TNativeRenderTilingTests = class(TRenderTilingTestsBase)
  protected
    function CreateBackend: IPdfRenderBackend; override;
  end;

implementation

uses
  Pdf4D.Render.Native.Backend;

{ TNativeGroupDevicePixelTests }

function TNativeGroupDevicePixelTests.CreateBackend: IPdfRenderBackend;
begin
  Result := TPdfNativeBackend.Create;
end;

{ TNativeRenderGroupTests }

function TNativeRenderGroupTests.CreateBackend: IPdfRenderBackend;
begin
  Result := TPdfNativeBackend.Create;
end;

{ TNativeRenderSoftMaskTests }

function TNativeRenderSoftMaskTests.CreateBackend: IPdfRenderBackend;
begin
  Result := TPdfNativeBackend.Create;
end;

{ TNativeRenderTilingTests }

function TNativeRenderTilingTests.CreateBackend: IPdfRenderBackend;
begin
  Result := TPdfNativeBackend.Create;
end;

end.
