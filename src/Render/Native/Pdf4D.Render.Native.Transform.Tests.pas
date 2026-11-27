// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.Native.Transform.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Math,
  DUnitX.TestFramework,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.Transform;

type
  [TestFixture]
  TTsTransformTests = class
  private
    procedure AssertTransform(const Expected, Actual: TTsTransform; const Tolerance: Double = 0);
    function MakeRect(const Left, Top, Right, Bottom: Single): TTsRect;
    function MakeNonZeroRect(const Left, Top, Right, Bottom: Single): TTsNonZeroRect;

  public
    [Test]
    procedure TestTransform;

    [Test]
    procedure TestConcat;

    [Test]
    procedure TestMapPointsUsesRowOrder;

    [Test]
    procedure TestMapPointBranches;

    [Test]
    procedure TestMapPointsBranches;

    [Test]
    procedure TestTryInvertSingularFails;

    [Test]
    procedure TestTryInvertOfAZeroScaleGivesInfinitiesAsInRust;

    [Test]
    procedure TestTryInvert;

    [Test]
    procedure TestTryInvertRoundTrip;

    [Test]
    procedure TestIsValidAndIsFinite;

    [Test]
    procedure TestNaNFieldsFollowRustComparisons;

    [Test]
    procedure TestRotate;

    [Test]
    procedure TestPreAndPostOperations;

    [Test]
    procedure TestFromBBoxAndBBoxTransform;

    [Test]
    procedure TestRectTransform;

    [Test]
    procedure TestNonZeroRectTransform;

    [Test]
    procedure TestRectToNonZeroRect;
  end;

implementation

{ TTsTransformTests }

procedure TTsTransformTests.AssertTransform(const Expected, Actual: TTsTransform; const Tolerance: Double);
begin
  const Message = Format('expected (%g, %g, %g, %g, %g, %g), got (%g, %g, %g, %g, %g, %g)',
    [Expected.SX, Expected.KY, Expected.KX, Expected.SY, Expected.TX, Expected.TY,
    Actual.SX, Actual.KY, Actual.KX, Actual.SY, Actual.TX, Actual.TY]);

  if Tolerance = 0 then
  begin
    Assert.IsTrue(Expected = Actual, Message);
    Exit;
  end;

  Assert.AreEqual(Double(Expected.SX), Double(Actual.SX), Tolerance, Message);
  Assert.AreEqual(Double(Expected.KY), Double(Actual.KY), Tolerance, Message);
  Assert.AreEqual(Double(Expected.KX), Double(Actual.KX), Tolerance, Message);
  Assert.AreEqual(Double(Expected.SY), Double(Actual.SY), Tolerance, Message);
  Assert.AreEqual(Double(Expected.TX), Double(Actual.TX), Tolerance, Message);
  Assert.AreEqual(Double(Expected.TY), Double(Actual.TY), Tolerance, Message);
end;

function TTsTransformTests.MakeRect(const Left, Top, Right, Bottom: Single): TTsRect;
begin
  Assert.IsTrue(TTsRect.TryFromLTRB(Left, Top, Right, Bottom, Result), 'a valid rect');
end;

function TTsTransformTests.MakeNonZeroRect(const Left, Top, Right, Bottom: Single): TTsNonZeroRect;
begin
  Assert.IsTrue(TTsNonZeroRect.TryFromLTRB(Left, Top, Right, Bottom, Result), 'a valid non-zero rect');
end;

procedure TTsTransformTests.TestTransform;
begin
  AssertTransform(TTsTransform.FromRow(1, 0, 0, 1, 0, 0), TTsTransform.Identity);
  AssertTransform(TTsTransform.FromRow(1, 0, 0, 2, 0, 0), TTsTransform.FromScale(1, 2));
  AssertTransform(TTsTransform.FromRow(1, 3, 2, 1, 0, 0), TTsTransform.FromSkew(2, 3));
  AssertTransform(TTsTransform.FromRow(1, 0, 0, 1, 5, 6), TTsTransform.FromTranslate(5, 6));

  var Ts := TTsTransform.Identity;
  Assert.IsTrue(Ts.IsIdentity);
  Assert.IsFalse(Ts.IsScale);
  Assert.IsFalse(Ts.IsSkew);
  Assert.IsFalse(Ts.IsTranslate);
  Assert.IsFalse(Ts.IsScaleTranslate);
  Assert.IsFalse(Ts.HasScale);
  Assert.IsFalse(Ts.HasSkew);
  Assert.IsFalse(Ts.HasTranslate);

  Ts := TTsTransform.FromScale(2, 3);
  Assert.IsFalse(Ts.IsIdentity);
  Assert.IsTrue(Ts.IsScale);
  Assert.IsFalse(Ts.IsSkew);
  Assert.IsFalse(Ts.IsTranslate);
  Assert.IsTrue(Ts.IsScaleTranslate);
  Assert.IsTrue(Ts.HasScale);
  Assert.IsFalse(Ts.HasSkew);
  Assert.IsFalse(Ts.HasTranslate);

  Ts := TTsTransform.FromSkew(2, 3);
  Assert.IsFalse(Ts.IsIdentity);
  Assert.IsFalse(Ts.IsScale);
  Assert.IsTrue(Ts.IsSkew);
  Assert.IsFalse(Ts.IsTranslate);
  Assert.IsFalse(Ts.IsScaleTranslate);
  Assert.IsFalse(Ts.HasScale);
  Assert.IsTrue(Ts.HasSkew);
  Assert.IsFalse(Ts.HasTranslate);

  Ts := TTsTransform.FromTranslate(2, 3);
  Assert.IsFalse(Ts.IsIdentity);
  Assert.IsFalse(Ts.IsScale);
  Assert.IsFalse(Ts.IsSkew);
  Assert.IsTrue(Ts.IsTranslate);
  Assert.IsTrue(Ts.IsScaleTranslate);
  Assert.IsFalse(Ts.HasScale);
  Assert.IsFalse(Ts.HasSkew);
  Assert.IsTrue(Ts.HasTranslate);

  Ts := TTsTransform.FromRow(1, 2, 3, 4, 5, 6);
  Assert.IsFalse(Ts.IsIdentity);
  Assert.IsFalse(Ts.IsScale);
  Assert.IsFalse(Ts.IsSkew);
  Assert.IsFalse(Ts.IsTranslate);
  Assert.IsFalse(Ts.IsScaleTranslate);
  Assert.IsTrue(Ts.HasScale);
  Assert.IsTrue(Ts.HasSkew);
  Assert.IsTrue(Ts.HasTranslate);

  Assert.IsFalse(TTsTransform.FromScale(1, 1).HasScale);
  Assert.IsFalse(TTsTransform.FromSkew(0, 0).HasSkew);
  Assert.IsFalse(TTsTransform.FromTranslate(0, 0).HasTranslate);
end;

procedure TTsTransformTests.TestConcat;
begin
  var Ts := TTsTransform.FromRow(1.2, 3.4, -5.6, -7.8, 1.2, 3.4);

  Ts := Ts.PreScale(2.0, -4.0);
  AssertTransform(TTsTransform.FromRow(2.4, 6.8, 22.4, 31.2, 1.2, 3.4), Ts);

  Ts := TTsTransform.FromRow(1.2, 3.4, -5.6, -7.8, 1.2, 3.4);
  Ts := Ts.PostScale(2.0, -4.0);
  AssertTransform(TTsTransform.FromRow(2.4, -13.6, -11.2, 31.2, 2.4, -13.6), Ts);
end;

procedure TTsTransformTests.TestMapPointsUsesRowOrder;
begin
  var Points: TArray<TTsPoint> := [TTsPoint.FromXY(1, 2)];

  TTsTransform.FromRow(2, 0.5, 0.25, 3, 10, 20).MapPoints(Points);

  Assert.AreEqual<Single>(12.5, Points[0].X);
  Assert.AreEqual<Single>(26.5, Points[0].Y);
end;

procedure TTsTransformTests.TestMapPointBranches;
begin
  var P := TTsPoint.FromXY(1, 2);

  TTsTransform.Identity.MapPoint(P);
  Assert.IsTrue(P = TTsPoint.FromXY(1, 2));

  TTsTransform.FromTranslate(10, 20).MapPoint(P);
  Assert.IsTrue(P = TTsPoint.FromXY(11, 22));

  P := TTsPoint.FromXY(1, 2);
  TTsTransform.FromRow(3, 0, 0, 4, 10, 20).MapPoint(P);
  Assert.IsTrue(P = TTsPoint.FromXY(13, 28));

  P := TTsPoint.FromXY(1, 2);
  TTsTransform.FromRow(2, 0.5, 0.25, 3, 10, 20).MapPoint(P);
  Assert.IsTrue(P = TTsPoint.FromXY(12.5, 26.5));
end;

procedure TTsTransformTests.TestMapPointsBranches;
begin
  var Points: TArray<TTsPoint> := [TTsPoint.FromXY(1, 2), TTsPoint.FromXY(-1, 0)];

  TTsTransform.Identity.MapPoints(Points);
  Assert.IsTrue(Points[0] = TTsPoint.FromXY(1, 2));

  TTsTransform.FromTranslate(10, 20).MapPoints(Points);
  Assert.IsTrue(Points[0] = TTsPoint.FromXY(11, 22));
  Assert.IsTrue(Points[1] = TTsPoint.FromXY(9, 20));

  TTsTransform.FromScale(2, 3).MapPoints(Points);
  Assert.IsTrue(Points[0] = TTsPoint.FromXY(22, 66));
  Assert.IsTrue(Points[1] = TTsPoint.FromXY(18, 60));

  var None: TArray<TTsPoint> := [];
  TTsTransform.FromScale(2, 3).MapPoints(None);
  Assert.AreEqual<Integer>(0, Length(None));
end;

procedure TTsTransformTests.TestTryInvertSingularFails;
begin
  var Inverted: TTsTransform;

  // The determinant sx * sy - kx * ky is 0 and the transform has a skew part
  Assert.IsFalse(TTsTransform.FromRow(1, 2, 2, 4, 5, 5).TryInvert(Inverted));
  Assert.IsTrue(TTsTransform.FromRow(0, 1, 1, 0, 0, 0).TryInvert(Inverted), 'a swap of the axes has an inverse');
end;

// Rust: a transform with only a scale and a translate part is inverted without a check of its scale, so Transform(0, 0, 0, 0, 5, 5)
// gives Some(infinities). The brief of this port expected a failure; the Rust behaviour is kept.
procedure TTsTransformTests.TestTryInvertOfAZeroScaleGivesInfinitiesAsInRust;
begin
  var Inverted: TTsTransform;
  var Succeeded: Boolean;

  const State = TTsFloatMode.Enter;
  try
    Succeeded := TTsTransform.FromRow(0, 0, 0, 0, 5, 5).TryInvert(Inverted);
  finally
    TTsFloatMode.Leave(State);
  end;

  Assert.IsTrue(Succeeded);
  Assert.IsFalse(Inverted.IsFinite);
  Assert.IsTrue(IsInfinite(Inverted.SX));
end;

procedure TTsTransformTests.TestTryInvert;
begin
  var Inverted: TTsTransform;

  Assert.IsTrue(TTsTransform.Identity.TryInvert(Inverted));
  AssertTransform(TTsTransform.Identity, Inverted);

  Assert.IsTrue(TTsTransform.FromTranslate(3, -4).TryInvert(Inverted));
  AssertTransform(TTsTransform.FromTranslate(-3, 4), Inverted);

  Assert.IsTrue(TTsTransform.FromRow(2, 0, 0, 4, 10, 20).TryInvert(Inverted));
  AssertTransform(TTsTransform.FromRow(0.5, 0, 0, 0.25, -5, -5), Inverted);

  // det = 2 * 3 - 1 * 1 = 5
  Assert.IsTrue(TTsTransform.FromRow(2, 1, 1, 3, 5, 7).TryInvert(Inverted));
  AssertTransform(TTsTransform.FromRow(0.6, -0.2, -0.2, 0.4, -1.6, -1.8), Inverted, 1E-6);
end;

procedure TTsTransformTests.TestTryInvertRoundTrip;
begin
  var Inverted: TTsTransform;
  const Ts = TTsTransform.FromRow(1.5, 0.3, -0.7, 2.25, 11, -13);

  Assert.IsTrue(Ts.TryInvert(Inverted));
  AssertTransform(TTsTransform.Identity, Ts.PreConcat(Inverted), 1E-5);
  AssertTransform(TTsTransform.Identity, Ts.PostConcat(Inverted), 1E-5);
end;

procedure TTsTransformTests.TestIsValidAndIsFinite;
begin
  const State = TTsFloatMode.Enter;
  try
    Assert.IsTrue(TTsTransform.FromScale(2, 3).IsValid);
    Assert.IsFalse(TTsTransform.FromScale(0, 3).IsValid);
    Assert.IsFalse(TTsTransform.FromScale(2, 0).IsValid);
    Assert.IsFalse(TTsTransform.FromScale(Single.NaN, 3).IsValid);
    Assert.IsFalse(TTsTransform.FromScale(Single.PositiveInfinity, 3).IsValid);

    Assert.IsTrue(TTsTransform.Identity.IsFinite);
    Assert.IsFalse(TTsTransform.FromTranslate(Single.NaN, 0).IsFinite);
    Assert.IsFalse(TTsTransform.FromTranslate(0, Single.NegativeInfinity).IsFinite);
    Assert.IsFalse(TTsTransform.FromRow(0, 0, 0, 0, 0, 0).IsValid);
  finally
    TTsFloatMode.Leave(State);
  end;
end;

procedure TTsTransformTests.TestNaNFieldsFollowRustComparisons;
begin
  // Rust: NaN != 1.0 is true, NaN != 0.0 is true, and a Transform with a NaN is not equal to itself
  const WithNaN = TTsTransform.FromRow(Single.NaN, 0, 0, 1, 0, 0);

  Assert.IsTrue(WithNaN.HasScale);
  Assert.IsFalse(WithNaN.IsIdentity);
  Assert.IsFalse(WithNaN = WithNaN);
  Assert.IsTrue(TTsTransform.FromRow(1, 0, Single.NaN, 1, 0, 0).HasSkew);
  Assert.IsTrue(TTsTransform.FromRow(1, 0, 0, 1, Single.NaN, 0).HasTranslate);
end;

procedure TTsTransformTests.TestRotate;
begin
  AssertTransform(TTsTransform.FromRow(0, 1, -1, 0, 0, 0), TTsTransform.FromRotate(90), 1E-6);
  AssertTransform(TTsTransform.FromRow(-1, 0, 0, -1, 0, 0), TTsTransform.FromRotate(180), 1E-6);
  AssertTransform(TTsTransform.FromRow(0.5, 0.8660254, -0.8660254, 0.5, 0, 0), TTsTransform.FromRotate(60), 1E-6);
  AssertTransform(TTsTransform.FromRow(0, 1, -1, 0, 0, 0), TTsTransform.FromSinCos(1, 0));

  // A rotation of 90 degrees around (1, 0) keeps (1, 0) and maps (2, 0) to (1, 1)
  var Points: TArray<TTsPoint> := [TTsPoint.FromXY(1, 0), TTsPoint.FromXY(2, 0)];

  TTsTransform.FromRotateAt(90, 1, 0).MapPoints(Points);
  Assert.AreEqual(1.0, Double(Points[0].X), 1E-6);
  Assert.AreEqual(0.0, Double(Points[0].Y), 1E-6);
  Assert.AreEqual(1.0, Double(Points[1].X), 1E-6);
  Assert.AreEqual(1.0, Double(Points[1].Y), 1E-6);
end;

procedure TTsTransformTests.TestPreAndPostOperations;
begin
  const Base = TTsTransform.FromRow(2, 0, 0, 3, 10, 20);

  // Pre-translate moves in the local space, post-translate in the target space
  AssertTransform(TTsTransform.FromRow(2, 0, 0, 3, 12, 23), Base.PreTranslate(1, 1));
  AssertTransform(TTsTransform.FromRow(2, 0, 0, 3, 11, 21), Base.PostTranslate(1, 1));
  AssertTransform(TTsTransform.FromRow(4, 0, 0, 9, 10, 20), Base.PreScale(2, 3));
  AssertTransform(TTsTransform.FromRow(4, 0, 0, 9, 20, 60), Base.PostScale(2, 3));
  AssertTransform(Base, Base.PreConcat(TTsTransform.Identity));
  AssertTransform(Base, TTsTransform.Identity.PostConcat(Base));

  AssertTransform(Base.PreConcat(TTsTransform.FromRotate(30)), Base.PreRotate(30));
  AssertTransform(Base.PostConcat(TTsTransform.FromRotate(30)), Base.PostRotate(30));
  AssertTransform(Base.PreConcat(TTsTransform.FromRotateAt(30, 4, 5)), Base.PreRotateAt(30, 4, 5));
  AssertTransform(Base.PostConcat(TTsTransform.FromRotateAt(30, 4, 5)), Base.PostRotateAt(30, 4, 5));

  var XScale, YScale: Single;
  TTsTransform.FromRow(3, 0, 4, 5, 0, 0).GetScale(XScale, YScale);
  Assert.AreEqual<Single>(5, XScale);
  Assert.AreEqual<Single>(5, YScale);
end;

procedure TTsTransformTests.TestFromBBoxAndBBoxTransform;
begin
  const BBox = MakeNonZeroRect(10, 20, 30, 60);

  AssertTransform(TTsTransform.FromRow(20, 0, 0, 40, 10, 20), TTsTransform.FromBBox(BBox));

  const Rect = MakeRect(0.25, 0.5, 0.75, 1.0).BBoxTransform(BBox);
  Assert.IsTrue(Rect = MakeRect(15, 40, 25, 60));

  const NonZero = MakeNonZeroRect(0.25, 0.5, 0.75, 1.0).BBoxTransform(BBox);
  Assert.IsTrue(NonZero = MakeNonZeroRect(15, 40, 25, 60));
end;

procedure TTsTransformTests.TestRectTransform;
begin
  // Tests based on 2x2 rectangle
  const Rect = MakeRect(1, 2, 3, 4);
  var Transformed: TTsRect;

  Assert.IsTrue(Rect.TryTransform(TTsTransform.Identity, Transformed));
  Assert.IsTrue(Transformed = Rect);

  // Scale x by 1x, y by 2x
  Assert.IsTrue(Rect.TryTransform(TTsTransform.FromScale(1, 2), Transformed));
  Assert.IsTrue(Transformed = MakeRect(1, 4, 3, 8));

  // Skew box along x-axis - vertical lines at y=c go to y=c+x and horizontal lines stay put. Result is bounding box
  Assert.IsTrue(Rect.TryTransform(TTsTransform.FromSkew(1, 0), Transformed));
  Assert.IsTrue(Transformed = MakeRect(3, 2, 7, 4));

  // Skew box along y-axis - horizontal lines at x=c go to x=c+2y
  Assert.IsTrue(Rect.TryTransform(TTsTransform.FromSkew(0, 2), Transformed));
  Assert.IsTrue(Transformed = MakeRect(1, 4, 3, 10));

  // A transform with a NaN gives no rect
  const State = TTsFloatMode.Enter;
  try
    Assert.IsFalse(Rect.TryTransform(TTsTransform.FromScale(Single.NaN, 1), Transformed));
    Assert.IsFalse(Rect.TryTransform(TTsTransform.FromRow(1, 0, 0, 1, Single.PositiveInfinity, 0), Transformed));
  finally
    TTsFloatMode.Leave(State);
  end;
end;

procedure TTsTransformTests.TestNonZeroRectTransform;
begin
  const Rect = MakeNonZeroRect(1, 2, 3, 4);
  var Transformed: TTsNonZeroRect;

  Assert.IsTrue(Rect.TryTransform(TTsTransform.Identity, Transformed));
  Assert.IsTrue(Transformed = Rect);

  Assert.IsTrue(Rect.TryTransform(TTsTransform.FromScale(1, 2), Transformed));
  Assert.IsTrue(Transformed = MakeNonZeroRect(1, 4, 3, 8));

  Assert.IsFalse(Rect.TryTransform(TTsTransform.FromScale(0, 1), Transformed), 'a zero width is not a non-zero rect');
end;

procedure TTsTransformTests.TestRectToNonZeroRect;
begin
  var Converted: TTsNonZeroRect;

  Assert.IsTrue(MakeRect(1, 2, 3, 4).TryToNonZeroRect(Converted));
  Assert.IsTrue(Converted = MakeNonZeroRect(1, 2, 3, 4));
  Assert.IsFalse(MakeRect(1, 2, 1, 4).TryToNonZeroRect(Converted));
end;

end.
