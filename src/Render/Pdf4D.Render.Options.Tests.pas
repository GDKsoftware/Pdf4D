// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.Options.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Types,
  DUnitX.TestFramework,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Options,
  Pdf4D.Render.Renderer.Interfaces;

type
  [TestFixture]
  TPdfRenderOptionsTests = class
  public
    [Test]
    procedure TestDefaultRenderOptions;

    [Test]
    procedure TestDefaultConstants;
  end;

  [TestFixture]
  TPdfRenderParamsTests = class
  public
    [Test]
    procedure TestRenderParamsFromDpi;

    [Test]
    procedure TestRenderParamsDefaults;

    [Test]
    procedure TestNonPositiveScaleRaises;
  end;

implementation

{ TPdfRenderOptionsTests }

procedure TPdfRenderOptionsTests.TestDefaultRenderOptions;
begin
  const Options = TPdfRenderOptions.Default;

  Assert.AreEqual(TPdfRenderDestination.Export, Options.Destination);
  Assert.AreEqual(Byte(255), Options.Background.R);
  Assert.AreEqual(Byte(255), Options.Background.G);
  Assert.AreEqual(Byte(255), Options.Background.B);
  Assert.AreEqual(Byte(255), Options.Background.A);
  Assert.IsTrue(Options.AntiAlias);
  Assert.IsTrue(Options.RenderAnnotations);
  Assert.AreEqual(Int64(64 * 1024 * 1024), Options.MaxRenderPixels);
  Assert.AreEqual(Int64(64 * 1024 * 1024), Options.MaxImagePixels);
  Assert.AreEqual(8, Options.MaxPatternDepth);
  Assert.AreEqual(8, Options.MaxSoftMaskDepth);
  Assert.AreEqual(16, Options.MaxTransparencyGroupDepth);
  Assert.AreEqual(8, Options.MaxType3Depth);
  Assert.AreEqual(Int64(1048576), Options.MaxTilingCells);
  Assert.AreEqual(3000, Options.MaxTileEdge);
end;

procedure TPdfRenderOptionsTests.TestDefaultConstants;
begin
  Assert.AreEqual(Int64(64 * 1024 * 1024), DefaultMaxRenderPixels);
  Assert.AreEqual(Int64(64 * 1024 * 1024), DefaultMaxImagePixels);
  Assert.AreEqual(8, DefaultMaxPatternDepth);
  Assert.AreEqual(8, DefaultMaxSoftMaskDepth);
  Assert.AreEqual(16, DefaultMaxTransparencyGroupDepth);
  Assert.AreEqual(8, DefaultMaxType3Depth);
  Assert.AreEqual(Int64(1048576), DefaultMaxTilingCells);
  Assert.AreEqual(3000, DefaultMaxTileEdge);
  Assert.AreEqual(Int64(256 * 1024 * 1024), MaxBitmapPixels);
end;

{ TPdfRenderParamsTests }

procedure TPdfRenderParamsTests.TestRenderParamsFromDpi;
begin
  const Params = TPdfRenderParams.FromDpi(150);

  Assert.AreEqual(Double(150 / 72), Double(Params.Scale), 0.00001);
end;

procedure TPdfRenderParamsTests.TestRenderParamsDefaults;
begin
  const Params = TPdfRenderParams.Create(2);

  Assert.AreEqual(Double(2), Double(Params.Scale), 0.00001);
  Assert.AreEqual(0, Params.ExtraRotation);
  Assert.IsTrue(Params.Region.IsEmpty);
  Assert.IsNull(Params.Cancel);
  Assert.AreEqual(TPdfRenderDestination.Export, Params.Options.Destination);
  Assert.IsTrue(Params.Options.AntiAlias);
end;

procedure TPdfRenderParamsTests.TestNonPositiveScaleRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      TPdfRenderParams.Create(0);
    end,
    EArgumentOutOfRangeException);
  Assert.WillRaise(
    procedure
    begin
      TPdfRenderParams.FromDpi(-72);
    end,
    EArgumentOutOfRangeException);
end;

end.
