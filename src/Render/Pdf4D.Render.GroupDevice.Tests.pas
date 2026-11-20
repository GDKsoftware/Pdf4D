// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of TPdfGroupDevice (GroupGraphics of PDFBox 3.0.8) with recording layers: what each layer gets
unit Pdf4D.Render.GroupDevice.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Common.Matrix,
  Pdf4D.Common.Path,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Render.GroupDevice,
  Pdf4D.Tests.RecordingDevice;

type
  [TestFixture]
  TGroupDeviceTests = class
  private
    FImage: TRecordingDevice;
    FAlpha: TRecordingDevice;
    FImageReference: IPdfRasterDevice;
    FAlphaReference: IPdfRasterDevice;
    FGroup: IPdfRasterDevice;

    procedure CreateGroup(const WithAlphaLayer: Boolean);
    procedure FillRectangle(const Paint: TPdfPaint; const Composite: TPdfComposite);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestFillGoesToBothLayersWhiteOnTheAlphaLayer;

    [Test]
    procedure TestAlphaLayerBlendsNormalAndKeepsTheAlpha;

    [Test]
    procedure TestBitmapGoesWhiteToTheAlphaLayer;

    [Test]
    procedure TestBitmapPaintGoesWhiteToTheAlphaLayer;

    [Test]
    procedure TestStrokeAndClipGoToBothLayers;

    [Test]
    procedure TestClearGoesToBothLayers;

    [Test]
    procedure TestWithoutAlphaLayerOnlyTheImageLayerIsDrawn;

    [Test]
    procedure TestSizeAndLayersComeFromTheImageLayer;

    [Test]
    procedure TestRemoveBackdropNeedsTheAlphaLayer;

    [Test]
    procedure TestImageIsRequired;
  end;

implementation

uses
  System.Types;

const
  LayerSize = 8;

{ TGroupDeviceTests }

procedure TGroupDeviceTests.Setup;
begin
  CreateGroup(True);
end;

procedure TGroupDeviceTests.TearDown;
begin
  FGroup := nil;
  FAlphaReference := nil;
  FImageReference := nil;
end;

procedure TGroupDeviceTests.CreateGroup(const WithAlphaLayer: Boolean);
begin
  FGroup := nil;
  FImage := TRecordingDevice.Create(LayerSize, LayerSize);
  FImageReference := FImage;
  FAlpha := TRecordingDevice.Create(LayerSize, LayerSize);
  FAlphaReference := FAlpha;
  if WithAlphaLayer then
  begin
    FGroup := TPdfGroupDevice.Create(FImageReference, FAlphaReference);
  end
  else
  begin
    FGroup := TPdfGroupDevice.Create(FImageReference, nil);
  end;
end;

procedure TGroupDeviceTests.FillRectangle(const Paint: TPdfPaint; const Composite: TPdfComposite);
begin
  const Path = TPdfPath.Create;
  try
    Path.MoveTo(1, 1);
    Path.LineTo(5, 1);
    Path.LineTo(5, 5);
    Path.ClosePath;
    FGroup.FillPath(Path, TPdfMatrix.Identity, TPdfFillRule.NonZero, Paint, Composite);
  finally
    Path.Free;
  end;
end;

procedure TGroupDeviceTests.TestFillGoesToBothLayersWhiteOnTheAlphaLayer;
begin
  FillRectangle(TPdfPaint.Solid(TPdfDeviceColor.Create(200, 10, 20)), TPdfComposite.Default);

  Assert.AreEqual<Integer>(1, FImage.Calls.Count);
  Assert.AreEqual(Byte(200), FImage.Calls[0].Paint.Color.R);
  Assert.AreEqual<Integer>(1, FAlpha.Calls.Count);
  Assert.AreEqual(TRecordedCallKind.Fill, FAlpha.Calls[0].Kind);
  Assert.AreEqual(Byte(255), FAlpha.Calls[0].Paint.Color.R);
  Assert.AreEqual(Byte(255), FAlpha.Calls[0].Paint.Color.G);
  Assert.AreEqual(Byte(255), FAlpha.Calls[0].Paint.Color.B);
end;

procedure TGroupDeviceTests.TestAlphaLayerBlendsNormalAndKeepsTheAlpha;
begin
  var Composite := TPdfComposite.Default;
  Composite.Alpha := 0.25;
  Composite.BlendMode := TPdfBlendMode.Multiply;

  FillRectangle(TPdfPaint.Solid(TPdfDeviceColor.Create(1, 2, 3)), Composite);

  Assert.AreEqual(TPdfBlendMode.Multiply, FImage.Calls[0].Composite.BlendMode);
  Assert.AreEqual(TPdfBlendMode.Normal, FAlpha.Calls[0].Composite.BlendMode);
  Assert.AreEqual(Double(0.25), Double(FAlpha.Calls[0].Composite.Alpha), 0.0001);
end;

procedure TGroupDeviceTests.TestBitmapGoesWhiteToTheAlphaLayer;
begin
  const Bitmap = TPdfBitmap.Create(2, 1);
  try
    Bitmap.SetPixel(0, 0, TPdfDeviceColor.Create(100, 20, 10, 200));
    Bitmap.SetPixel(1, 0, TPdfDeviceColor.Transparent);

    FGroup.DrawBitmap(Bitmap, TPdfMatrix.Identity, TPdfImageFilter.Nearest, TPdfComposite.Default);
  finally
    Bitmap.Free;
  end;

  Assert.AreEqual<Integer>(100, FImage.Calls[0].BitmapPixels[0]);
  const Pixels = FAlpha.Calls[0].BitmapPixels;
  Assert.AreEqual<Integer>(200, Pixels[0]);
  Assert.AreEqual<Integer>(200, Pixels[1]);
  Assert.AreEqual<Integer>(200, Pixels[2]);
  Assert.AreEqual<Integer>(200, Pixels[3]);
  Assert.AreEqual<Integer>(0, Pixels[4]);
  Assert.AreEqual<Integer>(0, Pixels[7]);
end;

procedure TGroupDeviceTests.TestBitmapPaintGoesWhiteToTheAlphaLayer;
begin
  const Bitmap = TPdfBitmap.Create(1, 1);
  try
    Bitmap.SetPixel(0, 0, TPdfDeviceColor.Create(10, 20, 30, 128));

    FillRectangle(TPdfPaint.FromBitmap(Bitmap, TPdfMatrix.Identity, TPdfTileMode.Decal, TPdfImageFilter.Nearest), TPdfComposite.Default);

    // The paint of the call is the bitmap of the caller: the white copy is a different bitmap
    Assert.AreSame(Bitmap, FImage.Calls[0].Paint.Bitmap);
    Assert.AreNotSame(Bitmap, FAlpha.Calls[0].Paint.Bitmap);
    Assert.AreEqual(TPdfPaintKind.Bitmap, FAlpha.Calls[0].Paint.Kind);
    Assert.AreEqual<Integer>(10, Bitmap.GetPixel(0, 0).R);
  finally
    Bitmap.Free;
  end;
end;

procedure TGroupDeviceTests.TestStrokeAndClipGoToBothLayers;
begin
  FGroup.SetClip(nil);
  const Path = TPdfPath.Create;
  try
    Path.MoveTo(0, 0);
    Path.LineTo(4, 4);
    var Stroke := Default(TPdfStrokeStyle);
    Stroke.Width := 2;
    Stroke.MiterLimit := 10;
    FGroup.StrokePath(Path, TPdfMatrix.Identity, Stroke, TPdfPaint.Solid(TPdfDeviceColor.Create(9, 9, 9)), TPdfComposite.Default);
  finally
    Path.Free;
  end;

  Assert.AreEqual(TRecordedCallKind.SetClip, FImage.Calls[0].Kind);
  Assert.AreEqual(TRecordedCallKind.SetClip, FAlpha.Calls[0].Kind);
  Assert.AreEqual(TRecordedCallKind.Stroke, FImage.Calls[1].Kind);
  Assert.AreEqual(TRecordedCallKind.Stroke, FAlpha.Calls[1].Kind);
  Assert.AreEqual(Byte(255), FAlpha.Calls[1].Paint.Color.G);
end;

procedure TGroupDeviceTests.TestClearGoesToBothLayers;
begin
  FGroup.Clear(TPdfDeviceColor.Create(1, 2, 3, 100));

  Assert.AreEqual(Byte(1), FImage.Calls[0].Paint.Color.R);
  Assert.AreEqual(Byte(255), FAlpha.Calls[0].Paint.Color.R);
  Assert.AreEqual(Byte(100), FAlpha.Calls[0].Paint.Color.A);
end;

procedure TGroupDeviceTests.TestWithoutAlphaLayerOnlyTheImageLayerIsDrawn;
begin
  CreateGroup(False);

  FillRectangle(TPdfPaint.Solid(TPdfDeviceColor.Create(1, 2, 3)), TPdfComposite.Default);
  FGroup.SetClip(nil);
  FGroup.Clear(TPdfDeviceColor.White);

  Assert.AreEqual<Integer>(3, FImage.Calls.Count);
  Assert.AreEqual<Integer>(0, FAlpha.Calls.Count);
end;

procedure TGroupDeviceTests.TestSizeAndLayersComeFromTheImageLayer;
begin
  Assert.AreEqual<Integer>(LayerSize, FGroup.Width);
  Assert.AreEqual<Integer>(LayerSize, FGroup.Height);

  const Layer = FGroup.CreateLayer(3, 2);

  Assert.AreEqual<Integer>(3, Layer.Width);
  Assert.AreEqual<Integer>(1, FImage.LayerCount);
  Assert.AreEqual<Integer>(0, FAlpha.LayerCount);
  var Bitmap: TPdfBitmap;
  Assert.IsFalse(FGroup.TryReadPixels(TRect.Create(0, 0, 1, 1), Bitmap));
end;

procedure TGroupDeviceTests.TestRemoveBackdropNeedsTheAlphaLayer;
begin
  CreateGroup(False);

  Assert.WillRaise(
    procedure
    begin
      TPdfGroupDevice(FGroup as TObject).RemoveBackdrop(nil, 0, 0);
    end, EInvalidOpException);
end;

procedure TGroupDeviceTests.TestImageIsRequired;
begin
  Assert.WillRaise(
    procedure
    begin
      TPdfGroupDevice.Create(nil, nil);
    end, EArgumentNilException);
end;

end.
