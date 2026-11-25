// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.RecordingDevice.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Types,
  DUnitX.TestFramework,
  Pdf4D.Common.Matrix,
  Pdf4D.Common.Path,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Render.ClipPath,
  Pdf4D.Tests.RecordingDevice;

type
  [TestFixture]
  TRecordingDeviceTests = class
  public
    [Test]
    procedure TestFillRecordsBoundsAfterTransformAndPaint;

    [Test]
    procedure TestClipDepthFollowsTheClipChain;

    [Test]
    procedure TestBitmapAndClearAreRecorded;

    [Test]
    procedure TestLayerKeepsItsOwnCallsInTheParent;

    [Test]
    procedure TestNoPixelsAndTransparentBitmap;

    [Test]
    procedure TestBackendReportsNameAndLastDevice;
  end;

implementation

{ TRecordingDeviceTests }

procedure TRecordingDeviceTests.TestFillRecordsBoundsAfterTransformAndPaint;
begin
  const Backend = TRecordingBackend.Create;
  const BackendReference: IPdfRenderBackend = Backend;
  const Device = BackendReference.CreateRasterDevice(100, 50);
  const Path = TPdfPath.Create;
  try
    Path.MoveTo(0, 0);
    Path.LineTo(10, 0);
    Path.LineTo(10, 5);
    const Transform = TPdfMatrix.Create(2, 0, 0, 3, 7, 1);
    var Composite := TPdfComposite.Default;
    Composite.Alpha := 0.5;

    Device.FillPath(Path, Transform, TPdfFillRule.EvenOdd, TPdfPaint.Solid(TPdfDeviceColor.Create(1, 2, 3)), Composite);

    Assert.AreEqual(1, Integer(Backend.LastDevice.Calls.Count));
    const Call = Backend.LastDevice.Calls[0];
    Assert.AreEqual(TRecordedCallKind.Fill, Call.Kind);
    Assert.AreEqual(Double(7), Double(Call.DeviceBounds.Left), 0.0001);
    Assert.AreEqual(Double(1), Double(Call.DeviceBounds.Top), 0.0001);
    Assert.AreEqual(Double(27), Double(Call.DeviceBounds.Right), 0.0001);
    Assert.AreEqual(Double(16), Double(Call.DeviceBounds.Bottom), 0.0001);
    Assert.AreEqual(TPdfFillRule.EvenOdd, Call.FillRule);
    Assert.AreEqual(Byte(3), Call.Paint.Color.B);
    Assert.AreEqual(Double(0.5), Double(Call.Composite.Alpha), 0.0001);
    Assert.AreEqual(0, Call.ClipDepth);
  finally
    Path.Free;
  end;
end;

procedure TRecordingDeviceTests.TestClipDepthFollowsTheClipChain;
begin
  const Device = TRecordingDevice.Create(10, 10);
  const Reference: IPdfRasterDevice = Device;
  const FirstPath = TPdfPath.Create;
  const SecondPath = TPdfPath.Create;
  const First: IPdfClipPath = TPdfClipPath.Create(nil, FirstPath, TPdfMatrix.Identity, TPdfFillRule.NonZero);
  const Second: IPdfClipPath = TPdfClipPath.Create(First, SecondPath, TPdfMatrix.Identity, TPdfFillRule.NonZero);
  const Path = TPdfPath.Create;
  try
    Path.MoveTo(0, 0);

    Reference.SetClip(Second);
    Reference.FillPath(Path, TPdfMatrix.Identity, TPdfFillRule.NonZero, TPdfPaint.Solid(TPdfDeviceColor.White), TPdfComposite.Default);
    Reference.SetClip(nil);
    Reference.FillPath(Path, TPdfMatrix.Identity, TPdfFillRule.NonZero, TPdfPaint.Solid(TPdfDeviceColor.White), TPdfComposite.Default);

    Assert.AreEqual(4, Integer(Device.Calls.Count));
    Assert.AreEqual(2, Device.Calls[0].ClipDepth);
    Assert.AreEqual(2, Device.Calls[1].ClipDepth);
    Assert.AreEqual(0, Device.Calls[2].ClipDepth);
    Assert.AreEqual(0, Device.Calls[3].ClipDepth);
    Assert.AreEqual(TRecordedCallKind.SetClip, Device.Calls[0].Kind);
  finally
    Path.Free;
  end;
end;

procedure TRecordingDeviceTests.TestBitmapAndClearAreRecorded;
begin
  const Device = TRecordingDevice.Create(40, 30);
  const Reference: IPdfRasterDevice = Device;
  const Bitmap = TPdfBitmap.Create(4, 2);
  try
    Reference.DrawBitmap(Bitmap, TPdfMatrix.GetScaleInstance(10, 10), TPdfImageFilter.Bilinear, TPdfComposite.Default);
    Reference.Clear(TPdfDeviceColor.White);

    Assert.AreEqual(TRecordedCallKind.Bitmap, Device.Calls[0].Kind);
    Assert.AreEqual(Double(40), Double(Device.Calls[0].DeviceBounds.Right), 0.0001);
    Assert.AreEqual(Double(20), Double(Device.Calls[0].DeviceBounds.Bottom), 0.0001);
    Assert.AreEqual(TPdfImageFilter.Bilinear, Device.Calls[0].Paint.Filter);
    Assert.AreEqual(TRecordedCallKind.Clear, Device.Calls[1].Kind);
    Assert.AreEqual(Double(30), Double(Device.Calls[1].DeviceBounds.Bottom), 0.0001);
  finally
    Bitmap.Free;
  end;
end;

procedure TRecordingDeviceTests.TestLayerKeepsItsOwnCallsInTheParent;
begin
  const Device = TRecordingDevice.Create(40, 30);
  const Reference: IPdfRasterDevice = Device;

  const Layer = Reference.CreateLayer(8, 6);
  Layer.Clear(TPdfDeviceColor.Transparent);

  Assert.AreEqual(1, Device.LayerCount);
  Assert.AreEqual(0, Integer(Device.Calls.Count));
  Assert.AreEqual(1, Integer(Device.Layers[0].Calls.Count));
  Assert.AreEqual(8, Device.Layers[0].Width);
  Assert.AreEqual(6, Layer.Height);
end;

procedure TRecordingDeviceTests.TestNoPixelsAndTransparentBitmap;
begin
  const Device: IPdfRasterDevice = TRecordingDevice.Create(3, 2);

  var Pixels: TPdfBitmap := nil;
  Assert.IsFalse(Device.TryReadPixels(TRect.Create(0, 0, 3, 2), Pixels));
  Assert.IsNull(Pixels);

  const Bitmap = Device.ToBitmap;
  try
    Assert.AreEqual(3, Bitmap.Width);
    Assert.AreEqual(Byte(0), Bitmap.GetPixel(2, 1).A);
  finally
    Bitmap.Free;
  end;
end;

procedure TRecordingDeviceTests.TestBackendReportsNameAndLastDevice;
begin
  const Backend = TRecordingBackend.Create;
  const Reference: IPdfRenderBackend = Backend;

  Assert.AreEqual('Recording', Reference.Name);
  Assert.IsNull(Backend.LastDevice);

  const Device = Reference.CreateRasterDevice(5, 4);

  Assert.AreSame(Device as TObject, Backend.LastDevice as TObject);
  Assert.WillRaise(
    procedure
    begin
      Reference.CreateRasterDevice(0, 4);
    end,
    EArgumentOutOfRangeException);
end;

end.
