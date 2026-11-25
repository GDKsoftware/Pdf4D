// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.Skia.Device.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Types,
  System.Math,

  System.Skia,
  DUnitX.TestFramework,
  Pdf4D.Common.Matrix,
  Pdf4D.Common.Path,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.ClipPath,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Render.Skia.Backend,
  Pdf4D.Render.Skia.Device,
  Pdf4D.Tests.DeviceContract;

type
  // A device whose surface cannot be made
  TPdfNoSurfaceDevice = class(TPdfSkiaDevice)
  protected
    function MakeSurface: ISkSurface; override;
  end;

  // The contract tests come from the base class; what follows is what only the Skia device has to do
  [TestFixture]
  TPdfSkiaDeviceTests = class(TPdfDeviceContractTests)
  protected
    function CreateBackend: IPdfRenderBackend; override;

  public
    [Test]
    procedure TestBackendNameIsSkia;

    [Test]
    procedure TestSurfaceThatCannotBeMadeRaisesOutOfMemory;

    [Test]
    procedure TestFailedClipLeavesTheDeviceUnclipped;
  end;

implementation

{ TPdfNoSurfaceDevice }

function TPdfNoSurfaceDevice.MakeSurface: ISkSurface;
begin
  Result := nil;
end;

{ TPdfSkiaDeviceTests }

function TPdfSkiaDeviceTests.CreateBackend: IPdfRenderBackend;
begin
  Result := TPdfSkiaBackend.Create;
end;

procedure TPdfSkiaDeviceTests.TestBackendNameIsSkia;
begin
  Assert.AreEqual('Skia', FBackend.Name);
  Assert.AreEqual(10, FDevice.Width);
  Assert.AreEqual(10, FDevice.Height);
end;

procedure TPdfSkiaDeviceTests.TestSurfaceThatCannotBeMadeRaisesOutOfMemory;
begin
  Assert.WillRaise(
    procedure
    begin
      TPdfNoSurfaceDevice.Create(4, 4);
    end,
    EOutOfMemory);
end;

procedure TPdfSkiaDeviceTests.TestFailedClipLeavesTheDeviceUnclipped;
begin
  const GoodClip = NewClip(nil, 2, 2, 5, 5);
  FDevice.SetClip(GoodClip);

  const BadClip = TPdfClipPath.Create(nil, NewRectPath(0, 0, 10, 10), TPdfMatrix.Identity, TPdfFillRule(99));
  Assert.WillRaise(
    procedure
    begin
      FDevice.SetClip(BadClip);
    end,
    ENotSupportedException);

  FillWholeDevice(Red, NoAntiAlias);
  AssertPixel(8, 8, TPdfDeviceColor.Create(255, 0, 0));

  FDevice.Clear(TPdfDeviceColor.Transparent);
  FDevice.SetClip(GoodClip);
  FillWholeDevice(Red, NoAntiAlias);
  AssertPixel(3, 3, TPdfDeviceColor.Create(255, 0, 0));
  AssertTransparent(8, 8);
end;

end.
