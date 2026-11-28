// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Extract.PageSpace.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  DUnitX.TestFramework,
  Pdf4D.Model.Rectangle;

type
  [TestFixture]
  TPdfPageSpaceTests = class
  private
    const Tolerance = 0.001;

    function Box(const LowerLeftX, LowerLeftY, UpperRightX, UpperRightY: Single): TPdfRectangle;
    procedure CheckPoint(const Expected: TPointF; const Actual: TPointF);

  public
    // A point near the lower left of user space, (10, 20), on a CropBox of 600 x 800 at the origin
    [Test]
    procedure TestRotation0;

    [Test]
    procedure TestRotation90;

    [Test]
    procedure TestRotation180;

    [Test]
    procedure TestRotation270;

    [Test]
    procedure TestCropBoxOffsetIsSubtracted;

    [Test]
    [TestCase('0', '0')]
    [TestCase('90', '90')]
    [TestCase('180', '180')]
    [TestCase('270', '270')]
    procedure TestBoundsHavePositiveSize(const Rotation: Integer);

    [Test]
    procedure TestBoundsOfQuadAndOfPointsAgree;

    [Test]
    procedure TestNonMultipleOf90IsNormalised;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Pdf4D.Common.Quad,
  Pdf4D.Extract.PageSpace;

function TPdfPageSpaceTests.Box(const LowerLeftX, LowerLeftY, UpperRightX, UpperRightY: Single): TPdfRectangle;
begin
  Result.LowerLeftX := LowerLeftX;
  Result.LowerLeftY := LowerLeftY;
  Result.UpperRightX := UpperRightX;
  Result.UpperRightY := UpperRightY;
end;

procedure TPdfPageSpaceTests.CheckPoint(const Expected: TPointF; const Actual: TPointF);
begin
  Assert.AreEqual(Double(Expected.X), Double(Actual.X), Tolerance, 'X');
  Assert.AreEqual(Double(Expected.Y), Double(Actual.Y), Tolerance, 'Y');
end;

procedure TPdfPageSpaceTests.TestRotation0;
begin
  const Space = TPdfPageSpace.Create(Box(0, 0, 600, 800), 0);

  CheckPoint(TPointF.Create(10, 780), Space.ToPage(TPointF.Create(10, 20)));
  Assert.AreEqual(Double(600), Double(Space.Width), Tolerance);
  Assert.AreEqual(Double(800), Double(Space.Height), Tolerance);
end;

procedure TPdfPageSpaceTests.TestRotation90;
begin
  const Space = TPdfPageSpace.Create(Box(0, 0, 600, 800), 90);

  CheckPoint(TPointF.Create(20, 10), Space.ToPage(TPointF.Create(10, 20)));
  Assert.AreEqual(Double(800), Double(Space.Width), Tolerance);
  Assert.AreEqual(Double(600), Double(Space.Height), Tolerance);
end;

procedure TPdfPageSpaceTests.TestRotation180;
begin
  const Space = TPdfPageSpace.Create(Box(0, 0, 600, 800), 180);

  CheckPoint(TPointF.Create(590, 20), Space.ToPage(TPointF.Create(10, 20)));
  Assert.AreEqual(Double(600), Double(Space.Width), Tolerance);
  Assert.AreEqual(Double(800), Double(Space.Height), Tolerance);
end;

procedure TPdfPageSpaceTests.TestRotation270;
begin
  const Space = TPdfPageSpace.Create(Box(0, 0, 600, 800), 270);

  CheckPoint(TPointF.Create(780, 590), Space.ToPage(TPointF.Create(10, 20)));
  Assert.AreEqual(Double(800), Double(Space.Width), Tolerance);
  Assert.AreEqual(Double(600), Double(Space.Height), Tolerance);
end;

procedure TPdfPageSpaceTests.TestCropBoxOffsetIsSubtracted;
begin
  const Space = TPdfPageSpace.Create(Box(50, 100, 650, 900), 0);

  CheckPoint(TPointF.Create(10, 780), Space.ToPage(TPointF.Create(60, 120)));
  // The lower left corner of the CropBox is the lower left corner of the shown page
  CheckPoint(TPointF.Create(0, 800), Space.ToPage(TPointF.Create(50, 100)));
  CheckPoint(TPointF.Create(600, 0), Space.ToPage(TPointF.Create(650, 900)));
end;

procedure TPdfPageSpaceTests.TestBoundsHavePositiveSize(const Rotation: Integer);
begin
  const Space = TPdfPageSpace.Create(Box(0, 0, 600, 800), Rotation);
  const Quad = TPdfQuad.Create(TPointF.Create(10, 20), TPointF.Create(110, 20), TPointF.Create(110, 70), TPointF.Create(10, 70));

  const Bounds = Space.BoundsOf(Quad);

  const IsSideways = ((Rotation = 90) or (Rotation = 270));
  Assert.AreEqual(IfThen(IsSideways, 50.0, 100.0), Double(Bounds.Width), Tolerance, 'Width');
  Assert.AreEqual(IfThen(IsSideways, 100.0, 50.0), Double(Bounds.Height), Tolerance, 'Height');
  Assert.IsTrue(Bounds.Left <= Bounds.Right);
  Assert.IsTrue(Bounds.Top <= Bounds.Bottom);
end;

procedure TPdfPageSpaceTests.TestBoundsOfQuadAndOfPointsAgree;
begin
  const Space = TPdfPageSpace.Create(Box(0, 0, 600, 800), 0);
  const Quad = TPdfQuad.Create(TPointF.Create(10, 20), TPointF.Create(110, 20), TPointF.Create(110, 70), TPointF.Create(10, 70));

  const FromQuad = Space.BoundsOf(Quad);
  const FromPoints = Space.BoundsOf([Quad.P1, Quad.P2, Quad.P3, Quad.P4]);

  Assert.AreEqual(Double(10), Double(FromQuad.Left), Tolerance);
  Assert.AreEqual(Double(730), Double(FromQuad.Top), Tolerance);
  Assert.AreEqual(Double(FromQuad.Left), Double(FromPoints.Left), Tolerance);
  Assert.AreEqual(Double(FromQuad.Top), Double(FromPoints.Top), Tolerance);
  Assert.AreEqual(Double(FromQuad.Width), Double(FromPoints.Width), Tolerance);
  Assert.AreEqual(Double(FromQuad.Height), Double(FromPoints.Height), Tolerance);
end;

procedure TPdfPageSpaceTests.TestNonMultipleOf90IsNormalised;
begin
  const Point = TPointF.Create(10, 20);

  const Turned = TPdfPageSpace.Create(Box(0, 0, 600, 800), -90);
  const Odd = TPdfPageSpace.Create(Box(0, 0, 600, 800), 45);

  CheckPoint(TPdfPageSpace.Create(Box(0, 0, 600, 800), 270).ToPage(Point), Turned.ToPage(Point));
  CheckPoint(TPdfPageSpace.Create(Box(0, 0, 600, 800), 0).ToPage(Point), Odd.ToPage(Point));
  Assert.AreEqual(Double(600), Double(Odd.Width), Tolerance);
end;

end.
