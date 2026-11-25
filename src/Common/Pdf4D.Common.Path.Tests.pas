// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Common.Path.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Types,
  DUnitX.TestFramework,
  Pdf4D.Common.Matrix,
  Pdf4D.Common.Path;

type
  [TestFixture]
  TPdfPathTests = class
  private
    procedure AssertPoint(const Expected: TPointF; const Actual: TPointF);

  public
    [Test]
    procedure TestVerbsAndPointsAreRecorded;

    [Test]
    procedure TestLineToWithoutMoveToStartsSubpath;

    [Test]
    procedure TestQuadToAndCubicToWithoutMoveToStartSubpath;

    [Test]
    procedure TestClosePathWithoutCurrentPointIsNoOp;

    [Test]
    procedure TestClosePathKeepsTheStartOfTheSubpathAsCurrentPoint;

    [Test]
    procedure TestBoundsIncludeControlPoints;

    [Test]
    procedure TestBoundsOfEmptyPathIsEmpty;

    [Test]
    procedure TestTransformAppliesMatrix;

    [Test]
    procedure TestAppendWithTransformLeavesOtherUnchanged;

    [Test]
    procedure TestAppendWithoutTransformCopiesVerbsAndPoints;

    [Test]
    procedure TestCloneIsIndependent;

    [Test]
    procedure TestClearEmptiesThePath;

    [Test]
    procedure TestCurrentPointWithoutPointRaises;

    [Test]
    procedure TestIndexOutOfRangeRaises;

    [Test]
    procedure TestManyPointsGrowTheArrays;
  end;

implementation

{ TPdfPathTests }

procedure TPdfPathTests.AssertPoint(const Expected: TPointF; const Actual: TPointF);
begin
  Assert.AreEqual(Expected.X, Actual.X, 0.00001);
  Assert.AreEqual(Expected.Y, Actual.Y, 0.00001);
end;

procedure TPdfPathTests.TestVerbsAndPointsAreRecorded;
begin
  const Path = TPdfPath.Create;
  try
    Path.MoveTo(0, 0);
    Path.LineTo(10, 0);
    Path.QuadTo(10, 5, 5, 5);
    Path.CubicTo(4, 5, 0, 4, 0, 0);
    Path.ClosePath;

    Assert.AreEqual(5, Path.VerbCount);
    Assert.AreEqual(7, Path.PointCount);
    Assert.IsTrue(Path.Verb(0) = TPdfPathVerb.MoveTo);
    Assert.IsTrue(Path.Verb(2) = TPdfPathVerb.QuadTo);
    Assert.IsTrue(Path.Verb(3) = TPdfPathVerb.CubicTo);
    Assert.IsTrue(Path.Verb(4) = TPdfPathVerb.Close);
    AssertPoint(PointF(10, 5), Path.Point(2));
    AssertPoint(PointF(0, 0), Path.Point(6));
    Assert.IsFalse(Path.IsEmpty);
  finally
    Path.Free;
  end;
end;

procedure TPdfPathTests.TestLineToWithoutMoveToStartsSubpath;
begin
  const Path = TPdfPath.Create;
  try
    Path.LineTo(3, 4);

    Assert.AreEqual(1, Path.VerbCount);
    Assert.IsTrue(Path.Verb(0) = TPdfPathVerb.MoveTo);
    AssertPoint(PointF(3, 4), Path.Point(0));

    Path.LineTo(5, 6);

    Assert.AreEqual(2, Path.VerbCount);
    Assert.IsTrue(Path.Verb(1) = TPdfPathVerb.LineTo);
    AssertPoint(PointF(5, 6), Path.Point(1));
  finally
    Path.Free;
  end;
end;

procedure TPdfPathTests.TestQuadToAndCubicToWithoutMoveToStartSubpath;
begin
  const QuadPath = TPdfPath.Create;
  const CubicPath = TPdfPath.Create;
  try
    QuadPath.QuadTo(1, 2, 3, 4);
    CubicPath.CubicTo(1, 2, 3, 4, 5, 6);

    Assert.AreEqual(2, QuadPath.VerbCount);
    Assert.IsTrue(QuadPath.Verb(0) = TPdfPathVerb.MoveTo);
    AssertPoint(PointF(1, 2), QuadPath.Point(0));
    Assert.AreEqual(3, QuadPath.PointCount);
    Assert.AreEqual(2, CubicPath.VerbCount);
    AssertPoint(PointF(1, 2), CubicPath.Point(0));
    Assert.AreEqual(4, CubicPath.PointCount);
  finally
    QuadPath.Free;
    CubicPath.Free;
  end;
end;

procedure TPdfPathTests.TestClosePathWithoutCurrentPointIsNoOp;
begin
  const Path = TPdfPath.Create;
  try
    Path.ClosePath;

    Assert.IsTrue(Path.IsEmpty);
    Assert.IsFalse(Path.HasCurrentPoint);
  finally
    Path.Free;
  end;
end;

procedure TPdfPathTests.TestClosePathKeepsTheStartOfTheSubpathAsCurrentPoint;
begin
  const Path = TPdfPath.Create;
  try
    Path.MoveTo(2, 3);
    Path.LineTo(8, 9);
    Path.ClosePath;

    AssertPoint(PointF(2, 3), Path.CurrentPoint);
  finally
    Path.Free;
  end;
end;

procedure TPdfPathTests.TestBoundsIncludeControlPoints;
begin
  const Path = TPdfPath.Create;
  try
    Path.MoveTo(0, 0);
    Path.CubicTo(0, 10, 10, 10, 10, 0);

    const Bounds = Path.Bounds;

    Assert.AreEqual<Single>(0, Bounds.Left);
    Assert.AreEqual<Single>(0, Bounds.Top);
    Assert.AreEqual<Single>(10, Bounds.Right);
    Assert.AreEqual<Single>(10, Bounds.Bottom);
  finally
    Path.Free;
  end;
end;

procedure TPdfPathTests.TestBoundsOfEmptyPathIsEmpty;
begin
  const Path = TPdfPath.Create;
  try
    const Bounds = Path.Bounds;

    Assert.IsTrue(Bounds.IsEmpty);
    Assert.AreEqual<Single>(0, Bounds.Width);
    Assert.AreEqual<Single>(0, Bounds.Height);
  finally
    Path.Free;
  end;
end;

procedure TPdfPathTests.TestTransformAppliesMatrix;
begin
  const Path = TPdfPath.Create;
  try
    Path.MoveTo(1, 1);
    Path.QuadTo(2, 2, 3, 3);

    Path.Transform(TPdfMatrix.Create(2, 0, 0, 2, 1, 1));

    AssertPoint(PointF(3, 3), Path.Point(0));
    AssertPoint(PointF(5, 5), Path.Point(1));
    AssertPoint(PointF(7, 7), Path.Point(2));
  finally
    Path.Free;
  end;
end;

procedure TPdfPathTests.TestAppendWithTransformLeavesOtherUnchanged;
begin
  const Path = TPdfPath.Create;
  const Other = TPdfPath.Create;
  try
    Path.MoveTo(0, 0);
    Other.MoveTo(1, 1);
    Other.LineTo(2, 1);

    Path.Append(Other, TPdfMatrix.Create(1, 0, 0, 1, 10, 20));

    Assert.AreEqual(3, Path.VerbCount);
    Assert.AreEqual(3, Path.PointCount);
    AssertPoint(PointF(11, 21), Path.Point(1));
    AssertPoint(PointF(12, 21), Path.Point(2));
    Assert.AreEqual(2, Other.VerbCount);
    AssertPoint(PointF(1, 1), Other.Point(0));
    AssertPoint(PointF(2, 1), Other.Point(1));
  finally
    Path.Free;
    Other.Free;
  end;
end;

procedure TPdfPathTests.TestAppendWithoutTransformCopiesVerbsAndPoints;
begin
  const Path = TPdfPath.Create;
  const Other = TPdfPath.Create;
  try
    Path.MoveTo(0, 0);
    Other.MoveTo(5, 5);
    Other.CubicTo(1, 2, 3, 4, 5, 6);
    Other.ClosePath;

    Path.Append(Other);

    Assert.AreEqual(4, Path.VerbCount);
    Assert.AreEqual(5, Path.PointCount);
    Assert.IsTrue(Path.Verb(3) = TPdfPathVerb.Close);
    AssertPoint(PointF(5, 6), Path.Point(4));
  finally
    Path.Free;
    Other.Free;
  end;
end;

procedure TPdfPathTests.TestCloneIsIndependent;
begin
  const Path = TPdfPath.Create;
  try
    Path.MoveTo(1, 2);
    Path.LineTo(3, 4);

    const Copy = Path.Clone;
    try
      Path.Transform(TPdfMatrix.GetScaleInstance(10, 10));
      Copy.LineTo(5, 6);

      Assert.AreEqual(2, Path.VerbCount);
      AssertPoint(PointF(30, 40), Path.Point(1));
      Assert.AreEqual(3, Copy.VerbCount);
      AssertPoint(PointF(1, 2), Copy.Point(0));
      AssertPoint(PointF(3, 4), Copy.Point(1));
    finally
      Copy.Free;
    end;
  finally
    Path.Free;
  end;
end;

procedure TPdfPathTests.TestClearEmptiesThePath;
begin
  const Path = TPdfPath.Create;
  try
    Path.MoveTo(1, 2);
    Path.LineTo(3, 4);

    Path.Clear;

    Assert.IsTrue(Path.IsEmpty);
    Assert.AreEqual(0, Path.PointCount);
    Assert.IsFalse(Path.HasCurrentPoint);
  finally
    Path.Free;
  end;
end;

procedure TPdfPathTests.TestCurrentPointWithoutPointRaises;
begin
  const Path = TPdfPath.Create;
  try
    Assert.IsFalse(Path.HasCurrentPoint);
    Assert.WillRaise(
      procedure
      begin
        Path.CurrentPoint;
      end,
      EInvalidOpException);
  finally
    Path.Free;
  end;
end;

procedure TPdfPathTests.TestIndexOutOfRangeRaises;
begin
  const Path = TPdfPath.Create;
  try
    Path.MoveTo(1, 2);

    Assert.WillRaise(
      procedure
      begin
        Path.Verb(1);
      end,
      EArgumentOutOfRangeException);
    Assert.WillRaise(
      procedure
      begin
        Path.Point(-1);
      end,
      EArgumentOutOfRangeException);
  finally
    Path.Free;
  end;
end;

procedure TPdfPathTests.TestManyPointsGrowTheArrays;
begin
  const Path = TPdfPath.Create;
  try
    Path.MoveTo(0, 0);
    for var Index := 1 to 1000 do
    begin
      Path.LineTo(Index, Index * 2);
    end;

    Assert.AreEqual(1001, Path.VerbCount);
    Assert.AreEqual(1001, Path.PointCount);
    AssertPoint(PointF(1000, 2000), Path.CurrentPoint);
    AssertPoint(PointF(500, 1000), Path.Point(500));
  finally
    Path.Free;
  end;
end;

end.
