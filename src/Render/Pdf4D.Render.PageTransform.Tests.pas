// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of the page geometry of PDFRenderer.renderImage and PageDrawer.drawPage (PDFBox 3.0.8)
unit Pdf4D.Render.PageTransform.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  DUnitX.TestFramework,
  Pdf4D.Model.Rectangle,
  Pdf4D.Render.PageTransform;

type
  [TestFixture]
  TPdfPageTransformTests = class
  private
    const Tolerance: Single = 0.001;

  private
    procedure AssertNear(const Expected, Actual: Single);
    function Box(const LowerLeftX, LowerLeftY, UpperRightX, UpperRightY: Single): TPdfRectangle;
    procedure AssertPoint(const ExpectedX, ExpectedY: Single; const Actual: TPointF);
    procedure AssertMapping(const Transform: TPdfPageTransform; const PageX, PageY, DeviceX, DeviceY: Single);

  public
    [Test]
    procedure TestLetterAtScaleOne;

    [Test]
    procedure TestRotate90;

    [Test]
    procedure TestRotate180;

    [Test]
    procedure TestRotate270;

    [Test]
    procedure TestCropBoxOffset;

    [Test]
    procedure TestFloorAndMinimumOne;

    [Test]
    procedure TestDeviceToPageInverts;

    [Test]
    procedure TestRotationOutsideTheFourAnglesRaises;

    [Test]
    procedure TestHugeScaleGivesFiniteMatrixAndLimitedSize;
  end;

implementation

uses
  System.SysUtils,
  Pdf4D.Common.Matrix;

{ TPdfPageTransformTests }

procedure TPdfPageTransformTests.AssertNear(const Expected, Actual: Single);
begin
  Assert.AreEqual(Double(Expected), Double(Actual), Double(Tolerance));
end;

function TPdfPageTransformTests.Box(const LowerLeftX, LowerLeftY, UpperRightX, UpperRightY: Single): TPdfRectangle;
begin
  Result.LowerLeftX := LowerLeftX;
  Result.LowerLeftY := LowerLeftY;
  Result.UpperRightX := UpperRightX;
  Result.UpperRightY := UpperRightY;
end;

procedure TPdfPageTransformTests.AssertPoint(const ExpectedX, ExpectedY: Single; const Actual: TPointF);
begin
  AssertNear(ExpectedX, Actual.X);
  AssertNear(ExpectedY, Actual.Y);
end;

procedure TPdfPageTransformTests.AssertMapping(const Transform: TPdfPageTransform; const PageX, PageY, DeviceX, DeviceY: Single);
begin
  AssertPoint(DeviceX, DeviceY, Transform.PageToDevice.TransformPoint(PageX, PageY));
end;

procedure TPdfPageTransformTests.TestLetterAtScaleOne;
begin
  const Transform = TPdfPageTransform.Create(Box(0, 0, 612, 792), 0, 1);

  Assert.AreEqual<Integer>(612, Transform.Size.cx);
  Assert.AreEqual<Integer>(792, Transform.Size.cy);
  AssertMapping(Transform, 0, 0, 0, 792);
  AssertMapping(Transform, 612, 792, 612, 0);
end;

procedure TPdfPageTransformTests.TestRotate90;
begin
  const Transform = TPdfPageTransform.Create(Box(0, 0, 612, 792), 90, 1);

  Assert.AreEqual<Integer>(792, Transform.Size.cx);
  Assert.AreEqual<Integer>(612, Transform.Size.cy);
  AssertMapping(Transform, 0, 0, 0, 0);
  AssertMapping(Transform, 612, 0, 0, 612);
  AssertMapping(Transform, 0, 792, 792, 0);
end;

procedure TPdfPageTransformTests.TestRotate180;
begin
  const Transform = TPdfPageTransform.Create(Box(0, 0, 612, 792), 180, 1);

  Assert.AreEqual<Integer>(612, Transform.Size.cx);
  Assert.AreEqual<Integer>(792, Transform.Size.cy);
  AssertMapping(Transform, 0, 0, 612, 0);
  AssertMapping(Transform, 612, 0, 0, 0);
  AssertMapping(Transform, 0, 792, 612, 792);
  AssertMapping(Transform, 612, 792, 0, 792);
end;

procedure TPdfPageTransformTests.TestRotate270;
begin
  const Transform = TPdfPageTransform.Create(Box(0, 0, 612, 792), 270, 1);

  Assert.AreEqual<Integer>(792, Transform.Size.cx);
  Assert.AreEqual<Integer>(612, Transform.Size.cy);
  AssertMapping(Transform, 0, 0, 792, 612);
  AssertMapping(Transform, 612, 0, 792, 0);
  AssertMapping(Transform, 0, 792, 0, 612);
  AssertMapping(Transform, 612, 792, 0, 0);
end;

procedure TPdfPageTransformTests.TestCropBoxOffset;
begin
  const Transform = TPdfPageTransform.Create(Box(50, 50, 562, 742), 0, 2);

  Assert.AreEqual<Integer>(1024, Transform.Size.cx);
  Assert.AreEqual<Integer>(1384, Transform.Size.cy);
  AssertMapping(Transform, 50, 742, 0, 0);
  AssertMapping(Transform, 562, 50, 1024, 1384);
end;

procedure TPdfPageTransformTests.TestFloorAndMinimumOne;
begin
  const Third = TPdfPageTransform.Create(Box(0, 0, 612, 792), 0, 0.3333);
  const Tiny = TPdfPageTransform.Create(Box(0, 0, 0.1, 0.1), 0, 1);

  Assert.AreEqual<Integer>(203, Third.Size.cx);
  Assert.AreEqual<Integer>(263, Third.Size.cy);
  Assert.AreEqual<Integer>(1, Tiny.Size.cx);
  Assert.AreEqual<Integer>(1, Tiny.Size.cy);
end;

procedure TPdfPageTransformTests.TestDeviceToPageInverts;
begin
  for var Rotation in [0, 90, 180, 270] do
  begin
    const Transform = TPdfPageTransform.Create(Box(50, 20, 562, 742), Rotation, 1.5);
    const Device = Transform.PageToDevice.TransformPoint(123, 456);

    AssertPoint(123, 456, Transform.DeviceToPage(Device));
  end;
end;

procedure TPdfPageTransformTests.TestRotationOutsideTheFourAnglesRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      TPdfPageTransform.Create(Box(0, 0, 612, 792), 45, 1);
    end,
    EArgumentException);
end;

procedure TPdfPageTransformTests.TestHugeScaleGivesFiniteMatrixAndLimitedSize;
begin
  const Transform = TPdfPageTransform.Create(Box(0, 0, 612, 792), 0, 3e38);

  Assert.AreEqual<Integer>(High(Integer), Transform.Size.cx);
  Assert.IsFalse(Transform.PageToDevice.ScaleX.IsInfinity);
  Assert.IsFalse(Transform.PageToDevice.TranslateY.IsInfinity);
end;

end.
