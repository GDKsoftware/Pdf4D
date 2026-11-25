// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of tiny-skia v0.12.0 path/src/path_geometry.rs and src/path_geometry.rs (inline tests), and of the functions around them
unit Pdf4D.Render.Native.PathGeometry.Tests;

{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  System.Math,
  DUnitX.TestFramework,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.Transform,
  Pdf4D.Render.Native.PathGeometry;

type
  [TestFixture]
  TTsPathGeometryTests = class
  private
    function Pt(const X, Y: Single): TTsPoint;
    procedure AssertPoint(const Expected, Actual: TTsPoint; const Message: string = '');
    procedure AssertNear(const Expected, Actual: TTsPoint; const Tolerance: Double);

  public
    [Test]
    procedure TestEvalCubicAt1;

    [Test]
    procedure TestFindCubicMaxCurvature1;

    [Test]
    procedure TestChopCubicAtYExtrema1;

    [Test]
    procedure TestValidUnitDivide;

    [Test]
    procedure TestFindUnitQuadRoots;

    [Test]
    procedure TestChopQuadAtYExtrema;

    [Test]
    procedure TestChopQuadAtXExtremaMonotonic;

    [Test]
    procedure TestQuadMaxCurvatureAndTangent;
    [Test]
    procedure TestQuadMaxCurvatureOfHugeControlPointsFails;

    [Test]
    procedure TestFindCubicCusp;

    [Test]
    procedure TestFindCubicInflections;

    [Test]
    procedure TestBuildUnitArcQuarter;

    [Test]
    procedure TestAutoConicToQuads;
  end;

implementation

{ TTsPathGeometryTests }

function TTsPathGeometryTests.Pt(const X, Y: Single): TTsPoint;
begin
  Result := TTsPoint.FromXY(X, Y);
end;

procedure TTsPathGeometryTests.AssertPoint(const Expected, Actual: TTsPoint; const Message: string);
begin
  Assert.IsTrue(Expected = Actual, Format('%s expected (%g, %g), got (%g, %g)', [Message, Expected.X, Expected.Y, Actual.X, Actual.Y]));
end;

procedure TTsPathGeometryTests.AssertNear(const Expected, Actual: TTsPoint; const Tolerance: Double);
begin
  Assert.AreEqual(Double(Expected.X), Double(Actual.X), Tolerance);
  Assert.AreEqual(Double(Expected.Y), Double(Actual.Y), Tolerance);
end;

procedure TTsPathGeometryTests.TestEvalCubicAt1;
begin
  var Src: TTsPoints4;
  Src[0] := Pt(30.0, 40.0);
  Src[1] := Pt(30.0, 40.0);
  Src[2] := Pt(171.0, 45.0);
  Src[3] := Pt(180.0, 155.0);

  AssertPoint(Pt(30.0, 40.0), TTsPathGeometry.EvalCubicPosAt(Src, TTsNormalizedF32.Zero));
  AssertPoint(Pt(141.0, 5.0), TTsPathGeometry.EvalCubicTangentAt(Src, TTsNormalizedF32.Zero));
end;

procedure TTsPathGeometryTests.TestFindCubicMaxCurvature1;
begin
  var Src: TTsPoints4;
  Src[0] := Pt(20.0, 160.0);
  Src[1] := Pt(20.0001, 160.0);
  Src[2] := Pt(160.0, 20.0);
  Src[3] := Pt(160.0001, 20.0);

  var TValues: TTsNormalizedValues;
  for var Index := 0 to High(TValues) do
  begin
    TValues[Index] := TTsNormalizedF32.Zero;
  end;

  const Count = TTsPathGeometry.FindCubicMaxCurvature(Src, TValues);

  Assert.AreEqual(3, Count);
  Assert.AreEqual(Single(0.0), TValues[0].Get);
  Assert.AreEqual(Single(0.5), TValues[1].Get);
  Assert.AreEqual(Single(1.0), TValues[2].Get);
end;

procedure TTsPathGeometryTests.TestChopCubicAtYExtrema1;
begin
  var Src: TTsPoints4;
  Src[0] := Pt(10.0, 20.0);
  Src[1] := Pt(67.0, 437.0);
  Src[2] := Pt(298.0, 213.0);
  Src[3] := Pt(401.0, 214.0);

  var Dst: TTsPoints10;
  const N = TTsPathGeometry.ChopCubicAtYExtrema(Src, Dst);

  Assert.AreEqual(2, N);
  AssertPoint(Pt(10.0, 20.0), Dst[0], 'dst[0]');
  AssertPoint(Pt(37.508274, 221.24475), Dst[1], 'dst[1]');
  AssertPoint(Pt(105.541855, 273.19803), Dst[2], 'dst[2]');
  AssertPoint(Pt(180.15599, 273.19803), Dst[3], 'dst[3]');
  AssertPoint(Pt(259.80502, 273.19803), Dst[4], 'dst[4]');
  AssertPoint(Pt(346.9527, 213.99666), Dst[5], 'dst[5]');
  AssertPoint(Pt(400.30844, 213.99666), Dst[6], 'dst[6]');
  AssertPoint(Pt(400.53958, 213.99666), Dst[7], 'dst[7]');
  AssertPoint(Pt(400.7701, 213.99777), Dst[8], 'dst[8]');
  AssertPoint(Pt(401.0, 214.0), Dst[9], 'dst[9]');
end;

procedure TTsPathGeometryTests.TestValidUnitDivide;
begin
  var Quotient: TTsNormalizedF32Exclusive;

  Assert.IsTrue(TTsPathGeometry.TryValidUnitDivide(1.0, 4.0, Quotient));
  Assert.AreEqual(Single(0.25), Quotient.Get);

  Assert.IsTrue(TTsPathGeometry.TryValidUnitDivide(-1.0, -2.0, Quotient));
  Assert.AreEqual(Single(0.5), Quotient.Get);

  Assert.IsFalse(TTsPathGeometry.TryValidUnitDivide(0.0, 4.0, Quotient), 'zero numerator');
  Assert.IsFalse(TTsPathGeometry.TryValidUnitDivide(1.0, 0.0, Quotient), 'zero denominator');
  Assert.IsFalse(TTsPathGeometry.TryValidUnitDivide(4.0, 4.0, Quotient), 'one is not exclusive');
  Assert.IsFalse(TTsPathGeometry.TryValidUnitDivide(5.0, 4.0, Quotient), 'above one');
  Assert.IsFalse(TTsPathGeometry.TryValidUnitDivide(1.0, -4.0, Quotient), 'negative');
end;

procedure TTsPathGeometryTests.TestFindUnitQuadRoots;
begin
  var Roots := TTsPathGeometry.NewTValues;

  // 4t^2 - 4t + 0.75 = 0 has the roots 0.25 and 0.75, in increasing order
  Assert.AreEqual(2, TTsPathGeometry.FindUnitQuadRoots(4.0, -4.0, 0.75, Roots));
  Assert.AreEqual(Single(0.25), Roots[0].Get);
  Assert.AreEqual(Single(0.75), Roots[1].Get);

  // a double root counts once
  Assert.AreEqual(1, TTsPathGeometry.FindUnitQuadRoots(1.0, -1.0, 0.25, Roots));
  Assert.AreEqual(Single(0.5), Roots[0].Get);

  // no real roots
  Assert.AreEqual(0, TTsPathGeometry.FindUnitQuadRoots(1.0, 0.0, 1.0, Roots));

  // a linear equation
  Assert.AreEqual(1, TTsPathGeometry.FindUnitQuadRoots(0.0, 2.0, -1.0, Roots));
  Assert.AreEqual(Single(0.5), Roots[0].Get);
end;

procedure TTsPathGeometryTests.TestChopQuadAtYExtrema;
begin
  var Src: TTsPoints3;
  Src[0] := Pt(0.0, 0.0);
  Src[1] := Pt(10.0, 20.0);
  Src[2] := Pt(20.0, 0.0);

  var Dst: TTsPoints5;
  Assert.AreEqual(1, TTsPathGeometry.ChopQuadAtYExtrema(Src, Dst));
  AssertPoint(Pt(0.0, 0.0), Dst[0]);
  AssertPoint(Pt(5.0, 10.0), Dst[1]);
  AssertPoint(Pt(10.0, 10.0), Dst[2]);
  AssertPoint(Pt(15.0, 10.0), Dst[3]);
  AssertPoint(Pt(20.0, 0.0), Dst[4]);
end;

procedure TTsPathGeometryTests.TestChopQuadAtXExtremaMonotonic;
begin
  var Src: TTsPoints3;
  Src[0] := Pt(0.0, 0.0);
  Src[1] := Pt(5.0, 20.0);
  Src[2] := Pt(20.0, 0.0);

  var Dst: TTsPoints5;
  Assert.AreEqual(0, TTsPathGeometry.ChopQuadAtXExtrema(Src, Dst));
  AssertPoint(Pt(0.0, 0.0), Dst[0]);
  AssertPoint(Pt(5.0, 20.0), Dst[1]);
  AssertPoint(Pt(20.0, 0.0), Dst[2]);

  // not monotonic: the control point is beyond the end
  Src[1] := Pt(30.0, 20.0);
  Assert.AreEqual(1, TTsPathGeometry.ChopQuadAtXExtrema(Src, Dst));
  Assert.AreEqual(Dst[2].X, Dst[1].X);
  Assert.AreEqual(Dst[2].X, Dst[3].X);
end;

procedure TTsPathGeometryTests.TestQuadMaxCurvatureOfHugeControlPointsFails;
begin
  // numer is inf - inf = NaN, where Rust panics on an unwrap
  var Src: TTsPoints3;
  Src[0] := Pt(0.0, 0.0);
  Src[1] := Pt(1E30, 1E30);
  Src[2] := Pt(3E30, 1E30);

  const State = TTsFloatMode.Enter;
  try
    var MaxCurvature: TTsNormalizedF32;
    Assert.IsFalse(TTsPathGeometry.TryFindQuadMaxCurvature(Src, MaxCurvature));
  finally
    TTsFloatMode.Leave(State);
  end;
end;

procedure TTsPathGeometryTests.TestQuadMaxCurvatureAndTangent;
begin
  var Src: TTsPoints3;
  Src[0] := Pt(0.0, 0.0);
  Src[1] := Pt(10.0, 0.0);
  Src[2] := Pt(10.0, 10.0);

  var MaxCurvature: TTsNormalizedF32;
  Assert.IsTrue(TTsPathGeometry.TryFindQuadMaxCurvature(Src, MaxCurvature));
  Assert.AreEqual(Single(0.5), MaxCurvature.Get);
  AssertPoint(Pt(20.0, 0.0), TTsPathGeometry.EvalQuadTangentAt(Src, TTsNormalizedF32.Zero));
  AssertPoint(Pt(0.0, 20.0), TTsPathGeometry.EvalQuadTangentAt(Src, TTsNormalizedF32.One));
  AssertPoint(Pt(7.5, 2.5), TTsPathGeometry.EvalQuadAt(Src, TTsNormalizedF32.CreateClamped(0.5)));

  // the control point equals the start: the tangent comes from the end points
  Src[1] := Pt(0.0, 0.0);
  AssertPoint(Pt(10.0, 10.0), TTsPathGeometry.EvalQuadTangentAt(Src, TTsNormalizedF32.Zero));
end;

procedure TTsPathGeometryTests.TestFindCubicCusp;
begin
  var Src: TTsPoints4;
  var T: TTsNormalizedF32Exclusive;

  // The control lines cross and both derivatives are zero at t = 0.5: a cusp
  Src[0] := Pt(0.0, 0.0);
  Src[1] := Pt(10.0, 10.0);
  Src[2] := Pt(0.0, 10.0);
  Src[3] := Pt(10.0, 0.0);
  Assert.IsTrue(TTsPathGeometry.TryFindCubicCusp(Src, T), 'a cusp');
  Assert.IsTrue(Abs(T.Get - 0.5) < 1e-3, 'the cusp is at the middle');

  // a start point equal to the first control point is skipped
  Src[1] := Src[0];
  Assert.IsFalse(TTsPathGeometry.TryFindCubicCusp(Src, T));

  // control lines that do not cross
  Src[0] := Pt(0.0, 0.0);
  Src[1] := Pt(10.0, 0.0);
  Src[2] := Pt(10.0, 10.0);
  Src[3] := Pt(20.0, 10.0);
  Assert.IsFalse(TTsPathGeometry.TryFindCubicCusp(Src, T));
end;

procedure TTsPathGeometryTests.TestFindCubicInflections;
begin
  var Src: TTsPoints4;
  Src[0] := Pt(0.0, 0.0);
  Src[1] := Pt(10.0, 10.0);
  Src[2] := Pt(10.0, -10.0);
  Src[3] := Pt(20.0, 0.0);

  var TValues := TTsPathGeometry.NewTValues;
  Assert.AreEqual(1, TTsPathGeometry.FindCubicInflections(Src, TValues));
  Assert.AreEqual(Single(0.5), TValues[0].Get);
end;

procedure TTsPathGeometryTests.TestBuildUnitArcQuarter;
begin
  var Dst: array[0..4] of TTsConic;
  var Count: Integer;

  // A quarter turn clockwise from (1, 0) to (0, 1): one conic with the weight of a quarter circle
  Assert.IsTrue(TTsConic.TryBuildUnitArc(Pt(1.0, 0.0), Pt(0.0, 1.0), TTsPathDirection.CW, TTsTransform.Identity, Dst, Count));
  Assert.AreEqual(1, Count);
  AssertNear(Pt(1.0, 0.0), Dst[0].Points[0], 1e-6);
  AssertNear(Pt(1.0, 1.0), Dst[0].Points[1], 1e-6);
  AssertNear(Pt(0.0, 1.0), Dst[0].Points[2], 1e-6);
  Assert.AreEqual(Double(TTsScalar.ScalarRoot2Over2), Double(Dst[0].Weight), 1e-6);

  // The same vector twice is no arc
  Assert.IsFalse(TTsConic.TryBuildUnitArc(Pt(1.0, 0.0), Pt(1.0, 0.0), TTsPathDirection.CW, TTsTransform.Identity, Dst, Count));
  Assert.AreEqual(0, Count);
end;

procedure TTsPathGeometryTests.TestAutoConicToQuads;
begin
  var Quads: TTsAutoConicToQuads;

  // A quarter circle of radius 100 as a conic: at least two quads, all points on the circle within the tolerance of the chop
  Assert.IsTrue(TTsAutoConicToQuads.TryCompute(Pt(100.0, 0.0), Pt(100.0, 100.0), Pt(0.0, 100.0), TTsScalar.ScalarRoot2Over2, Quads));
  Assert.IsTrue(Quads.Len >= 2);
  AssertPoint(Pt(100.0, 0.0), Quads.Points[0]);
  AssertPoint(Pt(0.0, 100.0), Quads.Points[2 * Quads.Len]);

  // The points between are on or near the circle
  for var Index := 0 to 2 * Quads.Len do
  begin
    const Distance = Quads.Points[Index].Length;
    Assert.AreEqual(100.0, Double(Distance), 1.0, Format('point %d', [Index]));
  end;

  // A conic with a non-finite point does not give quads
  const State = TTsFloatMode.Enter;
  try
    Assert.IsFalse(TTsAutoConicToQuads.TryCompute(Pt(0.0, 0.0), Pt(Infinity, 1.0), Pt(2.0, 2.0), 0.5, Quads));
  finally
    TTsFloatMode.Leave(State);
  end;
end;

end.
