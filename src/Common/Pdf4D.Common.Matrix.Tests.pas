// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/test/java/org/apache/pdfbox/util/MatrixTest.java (3.0.8)
unit Pdf4D.Common.Matrix.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Common.Matrix;

type
  [TestFixture]
  TMatrixTests = class
  private
    const Delta = 0.00001;

  private
    function FilledMatrix(const Offset: Integer): TPdfMatrix;
    procedure AssertValues(const Expected: array of Single; const Actual: TPdfMatrix);
    procedure AssertIdentity(const Actual: TPdfMatrix);

  public
    [Test]
    procedure TestIdentityAndCopy;

    [Test]
    procedure TestScalingFactor;

    [Test]
    procedure TestNegativeZeroShearTakesTheRootBranch;

    [Test]
    procedure TestFromCosArrayWithInvalidInputGivesIdentity;

    [Test]
    procedure TestFromCosArrayReadsSixNumbers;

    [Test]
    procedure TestMultiplication;

    [Test]
    procedure TestConcatenateAppliesTheFirstMatrixLast;

    [Test]
    procedure TestMultiplicationOverflowRaises;

    [Test]
    [TestCase('NaN', 'NaN')]
    [TestCase('PositiveInfinity', 'PositiveInfinity')]
    [TestCase('NegativeInfinity', 'NegativeInfinity')]
    procedure TestIllegalValueRaises(const Kind: string);

    [Test]
    procedure TestGetValues;

    [Test]
    procedure TestScaling;

    [Test]
    procedure TestTranslation;

    [Test]
    procedure TestTransformPointAndVector;

    [Test]
    procedure TestInstancesAreTranslationAndScale;

    [Test]
    procedure TestValueOutsideTheMatrixRaises;
  end;

implementation

uses
  System.Math,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Float,
  Pdf4D.Cos.PdfArray;

{ TMatrixTests }

function TMatrixTests.FilledMatrix(const Offset: Integer): TPdfMatrix;
begin
  Result := TPdfMatrix.Identity;
  for var Row := 0 to 2 do
  begin
    for var Column := 0 to 2 do
    begin
      Result.SetValue(Row, Column, Offset + Row + Column);
    end;
  end;
end;

procedure TMatrixTests.AssertValues(const Expected: array of Single; const Actual: TPdfMatrix);
begin
  for var Index := 0 to High(Expected) do
  begin
    Assert.AreEqual(Expected[Index], Actual.GetValue(Index div 3, Index mod 3), Delta,
                    Format('Incorrect value for matrix[%d,%d]', [Index div 3, Index mod 3]));
  end;
end;

procedure TMatrixTests.AssertIdentity(const Actual: TPdfMatrix);
begin
  AssertValues([1, 0, 0, 0, 1, 0, 0, 0, 1], Actual);
end;

procedure TMatrixTests.TestIdentityAndCopy;
begin
  const First = TPdfMatrix.Identity;
  var Second := First;
  AssertIdentity(First);
  AssertIdentity(Second);

  Second.SetValue(0, 0, 5);

  AssertIdentity(First);
  Assert.IsFalse(First.IsEqual(Second));
end;

procedure TMatrixTests.TestScalingFactor;
begin
  const Initial = TPdfMatrix.Identity;
  Assert.AreEqual(Single(1), Initial.ScalingFactorX, 0);
  Assert.AreEqual(Single(1), Initial.ScalingFactorY, 0);

  const Skewed = TPdfMatrix.Create(2, 4, 4, 2, 0, 0);
  const Expected = Single(Sqrt(20));
  Assert.AreEqual(Expected, Skewed.ScalingFactorX, 0);
  Assert.AreEqual(Expected, Skewed.ScalingFactorY, 0);
end;

procedure TMatrixTests.TestNegativeZeroShearTakesTheRootBranch;
begin
  var Zero: Single := 0;
  const NegativeZero = -Zero;
  const Matrix = TPdfMatrix.Create(-3, NegativeZero, NegativeZero, -3, 0, 0);

  // Float.compare(-0.0f, 0.0f) is not 0 in Java, so the result is the length and not the scale
  Assert.AreEqual(Single(3), Matrix.ScalingFactorX, 0);
  Assert.AreEqual(Single(3), Matrix.ScalingFactorY, 0);
end;

procedure TMatrixTests.TestFromCosArrayWithInvalidInputGivesIdentity;
begin
  AssertIdentity(TPdfMatrix.FromCosArray(nil));

  const Short = TCosArray.Create;
  try
    Short.Add(TCosName.Create('A'));
    AssertIdentity(TPdfMatrix.FromCosArray(Short));
  finally
    Short.Free;
  end;

  const NoNumbers = TCosArray.Create;
  try
    for var Index := 0 to 5 do
    begin
      NoNumbers.Add(TCosName.Create('A'));
    end;
    AssertIdentity(TPdfMatrix.FromCosArray(NoNumbers));
  finally
    NoNumbers.Free;
  end;
end;

procedure TMatrixTests.TestFromCosArrayReadsSixNumbers;
begin
  const Values = TCosArray.Create;
  try
    Values.Add(TCosInteger.Create(2));
    Values.Add(TCosInteger.Create(4));
    Values.Add(TCosFloat.Create(5.5));
    Values.Add(TCosInteger.Create(8));
    Values.Add(TCosInteger.Create(10));
    Values.Add(TCosInteger.Create(20));

    AssertValues([2, 4, 0, 5.5, 8, 0, 10, 20, 1], TPdfMatrix.FromCosArray(Values));
  finally
    Values.Free;
  end;
end;

procedure TMatrixTests.TestMultiplication;
begin
  const First = FilledMatrix(0);
  const Second = FilledMatrix(8);

  AssertValues([29, 32, 35, 56, 62, 68, 83, 92, 101], First.Multiply(Second));
  AssertValues([5, 8, 11, 8, 14, 20, 11, 20, 29], First.Multiply(First));
  AssertValues([0, 1, 2, 1, 2, 3, 2, 3, 4], First);

  var Concatenated := First;
  Concatenated.ConcatenateWith(Second);
  AssertValues([29, 56, 83, 32, 62, 92, 35, 68, 101], Concatenated);
  AssertValues([8, 9, 10, 9, 10, 11, 10, 11, 12], Second);
end;

procedure TMatrixTests.TestConcatenateAppliesTheFirstMatrixLast;
begin
  const Scale = TPdfMatrix.GetScaleInstance(2, 3);
  const Move = TPdfMatrix.GetTranslateInstance(10, 20);

  const Combined = TPdfMatrix.Concatenate(Scale, Move);

  const Point = Combined.TransformPoint(1, 1);
  // Like PDFBox, Concatenate(A, B) is B.Multiply(A): the move comes first, then the scale
  Assert.AreEqual(Single(22), Point.X, Delta);
  Assert.AreEqual(Single(63), Point.Y, Delta);
end;

procedure TMatrixTests.TestMultiplicationOverflowRaises;
begin
  var Huge := TPdfMatrix.Identity;
  Huge.SetValue(0, 0, MaxSingle);

  Assert.WillRaise(
    procedure
    begin
      Huge.Multiply(Huge);
    end,
    EPdfParseException);
end;

procedure TMatrixTests.TestIllegalValueRaises(const Kind: string);
begin
  var Broken := TPdfMatrix.Identity;
  if Kind = 'NaN' then
  begin
    Broken.SetValue(0, 0, NaN);
  end
  else if Kind = 'PositiveInfinity' then
  begin
    Broken.SetValue(0, 0, Infinity);
  end
  else
  begin
    Broken.SetValue(0, 0, NegInfinity);
  end;

  Assert.WillRaise(
    procedure
    begin
      Broken.Multiply(Broken);
    end,
    EPdfParseException);
end;

procedure TMatrixTests.TestGetValues;
begin
  const Matrix = TPdfMatrix.Create(2, 4, 4, 2, 15, 30);

  AssertValues([2, 4, 0, 4, 2, 0, 15, 30, 1], Matrix);
  Assert.AreEqual(Single(2), Matrix.ScaleX, 0);
  Assert.AreEqual(Single(4), Matrix.ShearY, 0);
  Assert.AreEqual(Single(4), Matrix.ShearX, 0);
  Assert.AreEqual(Single(2), Matrix.ScaleY, 0);
  Assert.AreEqual(Single(15), Matrix.TranslateX, 0);
  Assert.AreEqual(Single(30), Matrix.TranslateY, 0);
end;

procedure TMatrixTests.TestScaling;
begin
  var Matrix := TPdfMatrix.Create(2, 4, 4, 2, 15, 30);

  Matrix.Scale(2, 3);

  AssertValues([4, 8, 0, 12, 6, 0, 15, 30, 1], Matrix);
end;

procedure TMatrixTests.TestTranslation;
begin
  var Matrix := TPdfMatrix.Create(2, 4, 4, 2, 15, 30);

  Matrix.Translate(2, 3);

  AssertValues([2, 4, 0, 4, 2, 0, 31, 44, 1], Matrix);
end;

procedure TMatrixTests.TestTransformPointAndVector;
begin
  const Matrix = TPdfMatrix.Create(2, 0, 0, 3, 5, 7);

  const Point = Matrix.TransformPoint(10, 10);
  const Moved = Matrix.Transform(TPdfVector.Create(1, 2));

  Assert.AreEqual(Single(25), Point.X, Delta);
  Assert.AreEqual(Single(37), Point.Y, Delta);
  Assert.AreEqual(Single(7), Moved.X, Delta);
  Assert.AreEqual(Single(13), Moved.Y, Delta);
  Assert.AreEqual(Single(1.5), TPdfVector.Create(1, 2).Scale(1.5).X, Delta);
  Assert.AreEqual(Single(3), TPdfVector.Create(1, 2).Scale(1.5).Y, Delta);
end;

procedure TMatrixTests.TestInstancesAreTranslationAndScale;
begin
  AssertValues([1, 0, 0, 0, 1, 0, 3, 4, 1], TPdfMatrix.GetTranslateInstance(3, 4));
  AssertValues([5, 0, 0, 0, 6, 0, 0, 0, 1], TPdfMatrix.GetScaleInstance(5, 6));
end;

procedure TMatrixTests.TestValueOutsideTheMatrixRaises;
begin
  const Matrix = TPdfMatrix.Identity;

  Assert.WillRaise(
    procedure
    begin
      Matrix.GetValue(3, 0);
    end,
    EArgumentOutOfRangeException);
end;

end.
