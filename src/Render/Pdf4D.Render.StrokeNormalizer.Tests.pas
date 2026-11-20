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
