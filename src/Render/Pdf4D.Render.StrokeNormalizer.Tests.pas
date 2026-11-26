// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.StrokeNormalizer.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  DUnitX.TestFramework,
  Pdf4D.Common.Path;

type
  [TestFixture]
  TStrokeNormalizerTests = class
  private
    const Tolerance: Single = 0.0001;

  private
    procedure AssertPoint(const Path: TPdfPath; const Index: Integer; const ExpectedX, ExpectedY: Single);

  public
    [Test]
    procedure TestLineEndsMoveToPixelCentres;

    [Test]
    [TestCase('Below', '10.2,10.5')]
    [TestCase('Above', '10.9,10.5')]
    [TestCase('Integer', '10,10.5')]
    [TestCase('Negative', '-0.3,-0.5')]
    [TestCase('NegativeInteger', '-2,-1.5')]
    procedure TestEveryValueMovesToTheCentreOfItsPixel(const Value, Expected: Single);

    [Test]
    procedure TestPathIsNormalizedInDeviceSpace;

    // 12 points at 150 DPI (a scale of 150 / 72 as a Single) is 24.999999 pixels: Java2D transforms in double precision, so the point is in
    // pixel 24 and moves to 24.5; in single precision it would round up to 25.0 and move to 25.5
    [Test]
    procedure TestDevicePointJustBelowAPixelBoundaryStaysBelow;

    // The translation of the page matrix is a double in Java2D and a Single here; what the Single lost is passed as a residual, so that
    // a point at 24.999999 pixels is not rounded up to the pixel boundary by the matrix
    [Test]
    procedure TestTranslationResidualDecidesThePixel;

    [Test]
    procedure TestCubicControlPointsMoveWithTheEndPoints;

    [Test]
    procedure TestQuadControlPointMovesWithTheMean;

    [Test]
    procedure TestCloseAndTheVerbsStay;

    [Test]
    procedure TestSingularTransformGivesACopy;

    [Test]
    procedure TestSourceIsNotChanged;

    // The clip of Java2D: a vertex at device x moves to floor(x + 0.25) + 0.25 and pixels are taken by their centre, so an edge acts as if
    // it lay at floor(x + 0.25). The result is in device pixels.
    [Test]
    [TestCase('Below', '10.2,10.25')]
    [TestCase('JustBelowThreshold', '10.7,10.25')]
    [TestCase('AtThreshold', '10.75,11.25')]
    [TestCase('Above', '10.9,11.25')]
    [TestCase('Negative', '-0.3,-0.75')]
    procedure TestClipVertexMovesToFloorPlusQuarter(const Value, Expected: Single);

    // The fill without anti-aliasing: the edge of a rectangle is at ceil(x); the result is in device pixels
    [Test]
    [TestCase('Below', '10.2,11')]
    [TestCase('Above', '10.9,11')]
    [TestCase('Integer', '10,10')]
    [TestCase('HairAboveWhole', '10.0005,10')]
    [TestCase('Negative', '-0.3,0')]
    procedure TestFillVertexMovesToCeil(const Value, Expected: Single);

    [Test]
    procedure TestFillPathIsSnappedInDeviceSpace;

    // Another scale than 1 (150 DPI): the edge is at floor(x + 0.25), as for a clip
    [Test]
    procedure TestFillWithAnotherScaleFollowsTheClipRule;

    [Test]
    procedure TestClipPathIsSnappedInDeviceSpaceAndReturnedThere;

    [Test]
    procedure TestClipCurveControlPointsMoveWithTheEndPoints;

    // Matrices that make the determinant (0 times infinity) or the inverse (a translation of 1e36 under a scale of 1e-5) overflow or
    // invalid: the path comes back without an exception, also where the caller has not masked the floating point exceptions
    [Test]
    procedure TestHostileMatrixRaisesNoFloatException;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Pdf4D.Common.Matrix,
  Pdf4D.Render.StrokeNormalizer;

procedure TStrokeNormalizerTests.AssertPoint(const Path: TPdfPath; const Index: Integer; const ExpectedX, ExpectedY: Single);
begin
  const Point = Path.Point(Index);

  Assert.AreEqual(ExpectedX, Point.X, Tolerance, 'x of point ' + IntToStr(Index));
  Assert.AreEqual(ExpectedY, Point.Y, Tolerance, 'y of point ' + IntToStr(Index));
end;

procedure TStrokeNormalizerTests.TestClipVertexMovesToFloorPlusQuarter(const Value, Expected: Single);
begin
  const Path = TPdfPath.Create;
  try
    Path.MoveTo(Value, Value);

    const Snapped = TPdfStrokeNormalizer.SnapForClip(Path, TPdfMatrix.Identity);
    try
      AssertPoint(Snapped, 0, Expected, Expected);
    finally
      Snapped.Free;
    end;
  finally
    Path.Free;
  end;
end;

procedure TStrokeNormalizerTests.TestFillVertexMovesToCeil(const Value, Expected: Single);
begin
  const Path = TPdfPath.Create;
  try
    Path.MoveTo(Value, Value);

    const Snapped = TPdfStrokeNormalizer.SnapForFill(Path, TPdfMatrix.Identity);
    try
      AssertPoint(Snapped, 0, Expected, Expected);
    finally
      Snapped.Free;
    end;
  finally
    Path.Free;
  end;
end;

procedure TStrokeNormalizerTests.TestFillPathIsSnappedInDeviceSpace;
begin
  const Path = TPdfPath.Create;
  try
    // Device x = x + 1: 5.1 is 6.1 and becomes 7; y = 400 - y: 100 is 300 and stays 300
    Path.MoveTo(5.1, 100);
    Path.LineTo(6.4, 99);

    const Snapped = TPdfStrokeNormalizer.SnapForFill(Path, TPdfMatrix.Create(1, 0, 0, -1, 1, 400));
    try
      AssertPoint(Snapped, 0, 7, 300);
      AssertPoint(Snapped, 1, 8, 301);
    finally
      Snapped.Free;
    end;
  finally
    Path.Free;
  end;
end;

procedure TStrokeNormalizerTests.TestFillWithAnotherScaleFollowsTheClipRule;
begin
  const Path = TPdfPath.Create;
  try
    // Device = 2 * x: 5.1 is 10.2 and becomes 10.25 (ceil would be 11); 7.4 is 14.8 and becomes 15.25
    Path.MoveTo(5.1, 5.1);
    Path.LineTo(7.4, 7.4);

    const Snapped = TPdfStrokeNormalizer.SnapForFill(Path, TPdfMatrix.Create(2, 0, 0, 2, 0, 0));
    try
      AssertPoint(Snapped, 0, 10.25, 10.25);
      AssertPoint(Snapped, 1, 15.25, 15.25);
    finally
      Snapped.Free;
    end;
  finally
    Path.Free;
  end;
end;

procedure TStrokeNormalizerTests.TestClipPathIsSnappedInDeviceSpaceAndReturnedThere;
begin
  const Path = TPdfPath.Create;
  try
    // Device x = 2 * x + 1: 5.1 is 11.2 and becomes 11.25; y = 400 - y: 100 is 300 and becomes 300.25
    Path.MoveTo(5.1, 100);
    Path.LineTo(6.4, 99);

    const Snapped = TPdfStrokeNormalizer.SnapForClip(Path, TPdfMatrix.Create(2, 0, 0, -1, 1, 400));
    try
      AssertPoint(Snapped, 0, 11.25, 300.25);
      // 6.4 is 13.8 and becomes 14.25; 99 is 301 and becomes 301.25
      AssertPoint(Snapped, 1, 14.25, 301.25);
    finally
      Snapped.Free;
    end;
  finally
    Path.Free;
  end;
end;

procedure TStrokeNormalizerTests.TestClipCurveControlPointsMoveWithTheEndPoints;
begin
  const Path = TPdfPath.Create;
  try
    Path.MoveTo(0.5, 0.5);
    Path.CubicTo(2, 2, 3, 3, 4.9, 4.9);

    // The first end point moves by -0.25 (0.5 becomes 0.25) and the last by +0.35 (4.9 becomes 5.25); the control points follow
    const Snapped = TPdfStrokeNormalizer.SnapForClip(Path, TPdfMatrix.Identity);
    try
      AssertPoint(Snapped, 0, 0.25, 0.25);
      AssertPoint(Snapped, 1, 1.75, 1.75);
      AssertPoint(Snapped, 2, 3.35, 3.35);
      AssertPoint(Snapped, 3, 5.25, 5.25);
    finally
      Snapped.Free;
    end;
  finally
    Path.Free;
  end;
end;

procedure TStrokeNormalizerTests.TestLineEndsMoveToPixelCentres;
begin
  const Path = TPdfPath.Create;
  try
    Path.MoveTo(10, 20);
    Path.LineTo(30, 20);

    const Normalized = TPdfStrokeNormalizer.Normalize(Path, TPdfMatrix.Identity);
    try
      AssertPoint(Normalized, 0, 10.5, 20.5);
      AssertPoint(Normalized, 1, 30.5, 20.5);
    finally
      Normalized.Free;
    end;
  finally
    Path.Free;
  end;
end;

procedure TStrokeNormalizerTests.TestEveryValueMovesToTheCentreOfItsPixel(const Value, Expected: Single);
begin
  const Path = TPdfPath.Create;
  try
    Path.MoveTo(Value, Value);

    const Normalized = TPdfStrokeNormalizer.Normalize(Path, TPdfMatrix.Identity);
    try
      AssertPoint(Normalized, 0, Expected, Expected);
    finally
      Normalized.Free;
    end;
  finally
    Path.Free;
  end;
end;

procedure TStrokeNormalizerTests.TestPathIsNormalizedInDeviceSpace;
begin
  const Path = TPdfPath.Create;
  try
    // Device x = 2 * x + 1: 5 becomes 11, moves to 11.5 and is 5.25 in path space; y is flipped: 400 - y
    Path.MoveTo(5, 100);

    const Normalized = TPdfStrokeNormalizer.Normalize(Path, TPdfMatrix.Create(2, 0, 0, -1, 1, 400));
    try
      // y: device 300, to 300.5, path y 99.5
      AssertPoint(Normalized, 0, 5.25, 99.5);
    finally
      Normalized.Free;
    end;
  finally
    Path.Free;
  end;
end;

procedure TStrokeNormalizerTests.TestDevicePointJustBelowAPixelBoundaryStaysBelow;
begin
  const Scale: Single = 150 / 72;
  const Path = TPdfPath.Create;
  try
    Path.MoveTo(12, 12);

    const Normalized = TPdfStrokeNormalizer.Normalize(Path, TPdfMatrix.Create(Scale, 0, 0, Scale, 0, 0));
    try
      AssertPoint(Normalized, 0, 24.5 / Scale, 24.5 / Scale);
    finally
      Normalized.Free;
    end;
  finally
    Path.Free;
  end;
end;

procedure TStrokeNormalizerTests.TestTranslationResidualDecidesThePixel;
begin
  const Path = TPdfPath.Create;
  try
    Path.MoveTo(0, 0);

    // The matrix has 25 as its translation, the exact one is 25 - 0.000001
    const Plain = TPdfStrokeNormalizer.Normalize(Path, TPdfMatrix.Create(1, 0, 0, 1, 25, 25));
    const Exact = TPdfStrokeNormalizer.Normalize(Path, TPdfMatrix.Create(1, 0, 0, 1, 25, 25), -0.000001, -0.000001);
    try
      AssertPoint(Plain, 0, 0.5, 0.5);
      AssertPoint(Exact, 0, -0.5, -0.5);
    finally
      Plain.Free;
      Exact.Free;
    end;
  finally
    Path.Free;
  end;
end;

procedure TStrokeNormalizerTests.TestCubicControlPointsMoveWithTheEndPoints;
begin
  const Path = TPdfPath.Create;
  try
    Path.MoveTo(0, 0);
    Path.CubicTo(1, 1, 2, 2, 3.25, 3);

    const Normalized = TPdfStrokeNormalizer.Normalize(Path, TPdfMatrix.Identity);
    try
      // The start moves by 0.5, the end by 0.25 in x and 0.5 in y; the first control point goes with the start, the second with the end
      AssertPoint(Normalized, 0, 0.5, 0.5);
      AssertPoint(Normalized, 1, 1.5, 1.5);
      AssertPoint(Normalized, 2, 2.25, 2.5);
      AssertPoint(Normalized, 3, 3.5, 3.5);
    finally
      Normalized.Free;
    end;
  finally
    Path.Free;
  end;
end;

procedure TStrokeNormalizerTests.TestQuadControlPointMovesWithTheMean;
begin
  const Path = TPdfPath.Create;
  try
    Path.MoveTo(0, 0);
    Path.QuadTo(1, 1, 3.5, 3);

    const Normalized = TPdfStrokeNormalizer.Normalize(Path, TPdfMatrix.Identity);
    try
      // Moves of the start: 0.5; of the end: 0 in x and 0.5 in y
      AssertPoint(Normalized, 1, 1.25, 1.5);
      AssertPoint(Normalized, 2, 3.5, 3.5);
    finally
      Normalized.Free;
    end;
  finally
    Path.Free;
  end;
end;

procedure TStrokeNormalizerTests.TestCloseAndTheVerbsStay;
begin
  const Path = TPdfPath.Create;
  try
    Path.MoveTo(0, 0);
    Path.LineTo(10, 0);
    Path.LineTo(10, 10);
    Path.ClosePath;

    const Normalized = TPdfStrokeNormalizer.Normalize(Path, TPdfMatrix.Identity);
    try
      Assert.AreEqual(Path.VerbCount, Normalized.VerbCount);
      Assert.AreEqual(Path.PointCount, Normalized.PointCount);
      Assert.IsTrue(Normalized.Verb(3) = TPdfPathVerb.Close);
      AssertPoint(Normalized, 2, 10.5, 10.5);
    finally
      Normalized.Free;
    end;
  finally
    Path.Free;
  end;
end;

procedure TStrokeNormalizerTests.TestSingularTransformGivesACopy;
begin
  const Path = TPdfPath.Create;
  try
    Path.MoveTo(1.2, 3.4);

    const Normalized = TPdfStrokeNormalizer.Normalize(Path, TPdfMatrix.Create(0, 0, 0, 0, 5, 5));
    try
      AssertPoint(Normalized, 0, 1.2, 3.4);
    finally
      Normalized.Free;
    end;
  finally
    Path.Free;
  end;
end;

procedure TStrokeNormalizerTests.TestHostileMatrixRaisesNoFloatException;
begin
  const Matrices: TArray<TPdfMatrix> = [
    TPdfMatrix.Create(Single.PositiveInfinity, 0, 0, 0, 0, 0),
    TPdfMatrix.Create(0, Single.PositiveInfinity, Single.PositiveInfinity, 0, 0, 0),
    TPdfMatrix.Create(1E-5, 0, 0, 1E-5, 1E36, 0),
    TPdfMatrix.Create(1E-5, 0, 0, 1E-5, 0, -1E36),
    TPdfMatrix.Create(Single.NaN, 0, 0, 1, 0, 0)];

  // The mask of Delphi: invalid operations, overflow and division by zero raise
  const Previous = SetExceptionMask([exDenormalized, exUnderflow, exPrecision]);
  try
    const Path = TPdfPath.Create;
    try
      Path.MoveTo(1.2, 3.4);
      Path.LineTo(5, 6);
      for var Index := 0 to High(Matrices) do
      begin
        const Normalized = TPdfStrokeNormalizer.Normalize(Path, Matrices[Index]);
        Normalized.Free;
      end;
    finally
      Path.Free;
    end;
  finally
    SetExceptionMask(Previous);
  end;
end;

procedure TStrokeNormalizerTests.TestSourceIsNotChanged;
begin
  const Path = TPdfPath.Create;
  try
    Path.MoveTo(1, 1);

    TPdfStrokeNormalizer.Normalize(Path, TPdfMatrix.Identity).Free;

    AssertPoint(Path, 0, 1, 1);
  finally
    Path.Free;
  end;
end;

end.
