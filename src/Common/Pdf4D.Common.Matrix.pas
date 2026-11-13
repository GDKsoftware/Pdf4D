// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/util/Matrix.java (3.0.8), as far as the text extraction uses it:
// without rotation, AffineTransform conversion and toCOSArray
// Port of: pdfbox/src/main/java/org/apache/pdfbox/util/Vector.java (3.0.8)
unit Pdf4D.Common.Matrix;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Types,
  Pdf4D.Cos.PdfArray;

type
  TPdfVector = record
    X: Single;
    Y: Single;

    class function Create(const X, Y: Single): TPdfVector; static;

    function Scale(const S: Single): TPdfVector;
  end;

  // A 3x3 matrix in the layout of PDFBox: [a b 0; c d 0; e f 1] is kept as nine Singles, row by row. Like the other
  // records it is a value: a copy does not share anything. Default(TPdfMatrix) is all zeros, not the identity.
  TPdfMatrix = record
  private
    const Size = 9;

  private
    FValues: array[0..Size - 1] of Single;

    class function MultiplyValues(const Left, Right: TPdfMatrix): TPdfMatrix; static;
    procedure CheckValuesAreFinite;

  public
    class function Create(const A, B, C, D, E, F: Single): TPdfMatrix; static;
    class function Identity: TPdfMatrix; static;
    // Port of Matrix.createMatrix: nil, fewer than six items or an item that is no number gives the identity
    class function FromCosArray(const Value: TCosArray): TPdfMatrix; static;
    class function GetTranslateInstance(const X, Y: Single): TPdfMatrix; static;
    class function GetScaleInstance(const X, Y: Single): TPdfMatrix; static;
    // Port of Matrix.concatenate(a, b), which is b.multiply(a): the point goes through B first and then through A
    class function Concatenate(const A, B: TPdfMatrix): TPdfMatrix; static;

    // Row and Column are 0..2; a value outside raises EArgumentOutOfRangeException
    function GetValue(const Row, Column: Integer): Single;
    procedure SetValue(const Row, Column: Integer; const Value: Single);
    function IsEqual(const Other: TPdfMatrix): Boolean;

    // This matrix first, then Other. Raises EPdfParseException when a value becomes infinite or NaN (the
    // IllegalArgumentException of PDFBox).
    function Multiply(const Other: TPdfMatrix): TPdfMatrix;
    // PDFBox concatenate: this := Other.Multiply(this), so a point goes through Other first and then through this matrix,
    // as the cm operator does with the current transformation matrix
    procedure ConcatenateWith(const Other: TPdfMatrix);
    procedure Translate(const Tx, Ty: Single);
    procedure Scale(const Sx, Sy: Single);

    function TransformPoint(const X, Y: Single): TPointF;
    function Transform(const V: TPdfVector): TPdfVector;

    function ScaleX: Single;
    function ScaleY: Single;
    function ShearX: Single;
    function ShearY: Single;
    function TranslateX: Single;
    function TranslateY: Single;
    function ScalingFactorX: Single;
    function ScalingFactorY: Single;
  end;

implementation

uses
  System.Math,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Number;

const
  IllegalValuesMessage = 'Multiplying two matrices produces illegal values';

// Float.compare(Value, 0.0f) != 0 in Java: true for -0.0 and NaN as well
function IsNotPositiveZero(const Value: Single): Boolean;
begin
  Result := ((Value <> 0) or (Value.SpecialType = TFloatSpecial.fsNZero));
end;

{ TPdfVector }

class function TPdfVector.Create(const X, Y: Single): TPdfVector;
begin
  Result.X := X;
  Result.Y := Y;
end;

function TPdfVector.Scale(const S: Single): TPdfVector;
begin
  Result.X := X * S;
  Result.Y := Y * S;
end;

{ TPdfMatrix }

class function TPdfMatrix.Create(const A, B, C, D, E, F: Single): TPdfMatrix;
begin
  Result.FValues[0] := A;
  Result.FValues[1] := B;
  Result.FValues[2] := 0;
  Result.FValues[3] := C;
  Result.FValues[4] := D;
  Result.FValues[5] := 0;
  Result.FValues[6] := E;
  Result.FValues[7] := F;
  Result.FValues[8] := 1;
end;

class function TPdfMatrix.Identity: TPdfMatrix;
begin
  Result := TPdfMatrix.Create(1, 0, 0, 1, 0, 0);
end;

class function TPdfMatrix.FromCosArray(const Value: TCosArray): TPdfMatrix;
begin
  const HasSixItems = (Assigned(Value) and (Value.Count >= 6));
  if not HasSixItems then
  begin
    Exit(Identity);
  end;

  var Numbers: array[0..5] of Single;
  for var Index := 0 to 5 do
  begin
    const Item: TCosBase = Value.GetObject(Index);
    if not (Item is TCosNumber) then
    begin
      Exit(Identity);
    end;
    Numbers[Index] := TCosNumber(Item).FloatValue;
  end;

  Result := TPdfMatrix.Create(Numbers[0], Numbers[1], Numbers[2], Numbers[3], Numbers[4], Numbers[5]);
end;

class function TPdfMatrix.GetTranslateInstance(const X, Y: Single): TPdfMatrix;
begin
  Result := TPdfMatrix.Create(1, 0, 0, 1, X, Y);
end;

class function TPdfMatrix.GetScaleInstance(const X, Y: Single): TPdfMatrix;
begin
  Result := TPdfMatrix.Create(X, 0, 0, Y, 0, 0);
end;

class function TPdfMatrix.Concatenate(const A, B: TPdfMatrix): TPdfMatrix;
begin
  Result := B.Multiply(A);
end;

function TPdfMatrix.GetValue(const Row, Column: Integer): Single;
begin
  const IsInside = ((Row >= 0) and (Row < 3) and (Column >= 0) and (Column < 3));
  if not IsInside then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('Matrix position (%d, %d) is outside the 3x3 matrix', [Row, Column]);
  end;
  Result := FValues[Row * 3 + Column];
end;

procedure TPdfMatrix.SetValue(const Row, Column: Integer; const Value: Single);
begin
  const IsInside = ((Row >= 0) and (Row < 3) and (Column >= 0) and (Column < 3));
  if not IsInside then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('Matrix position (%d, %d) is outside the 3x3 matrix', [Row, Column]);
  end;
  FValues[Row * 3 + Column] := Value;
end;

function TPdfMatrix.IsEqual(const Other: TPdfMatrix): Boolean;
begin
  Result := True;
  for var Index := 0 to Size - 1 do
  begin
    if FValues[Index] <> Other.FValues[Index] then
    begin
      Exit(False);
    end;
  end;
end;

class function TPdfMatrix.MultiplyValues(const Left, Right: TPdfMatrix): TPdfMatrix;
begin
  const A = Left.FValues;
  const B = Right.FValues;
  try
    Result.FValues[0] := A[0] * B[0] + A[1] * B[3] + A[2] * B[6];
    Result.FValues[1] := A[0] * B[1] + A[1] * B[4] + A[2] * B[7];
    Result.FValues[2] := A[0] * B[2] + A[1] * B[5] + A[2] * B[8];
    Result.FValues[3] := A[3] * B[0] + A[4] * B[3] + A[5] * B[6];
    Result.FValues[4] := A[3] * B[1] + A[4] * B[4] + A[5] * B[7];
    Result.FValues[5] := A[3] * B[2] + A[4] * B[5] + A[5] * B[8];
    Result.FValues[6] := A[6] * B[0] + A[7] * B[3] + A[8] * B[6];
    Result.FValues[7] := A[6] * B[1] + A[7] * B[4] + A[8] * B[7];
    Result.FValues[8] := A[6] * B[2] + A[7] * B[5] + A[8] * B[8];
  except
    // Depending on the platform an overflow arrives as an exception or as an infinity; both mean the same here
    on EMathError do
    begin
      raise EPdfParseException.Create(IllegalValuesMessage);
    end;
  end;
end;

procedure TPdfMatrix.CheckValuesAreFinite;
begin
  for var Index := 0 to Size - 1 do
  begin
    const IsFinite = (not (IsNan(FValues[Index]) or IsInfinite(FValues[Index])));
    if not IsFinite then
    begin
      raise EPdfParseException.Create(IllegalValuesMessage);
    end;
  end;
end;

function TPdfMatrix.Multiply(const Other: TPdfMatrix): TPdfMatrix;
begin
  Result := MultiplyValues(Self, Other);
  Result.CheckValuesAreFinite;
end;

procedure TPdfMatrix.ConcatenateWith(const Other: TPdfMatrix);
begin
  const Product = MultiplyValues(Other, Self);
  Product.CheckValuesAreFinite;
  Self := Product;
end;

procedure TPdfMatrix.Translate(const Tx, Ty: Single);
begin
  var Moved := Self;
  try
    Moved.FValues[6] := Moved.FValues[6] + Tx * Moved.FValues[0] + Ty * Moved.FValues[3];
    Moved.FValues[7] := Moved.FValues[7] + Tx * Moved.FValues[1] + Ty * Moved.FValues[4];
    Moved.FValues[8] := Moved.FValues[8] + Tx * Moved.FValues[2] + Ty * Moved.FValues[5];
  except
    on EMathError do
    begin
      raise EPdfParseException.Create(IllegalValuesMessage);
    end;
  end;
  Moved.CheckValuesAreFinite;
  Self := Moved;
end;

procedure TPdfMatrix.Scale(const Sx, Sy: Single);
begin
  var Scaled := Self;
  try
    Scaled.FValues[0] := Scaled.FValues[0] * Sx;
    Scaled.FValues[1] := Scaled.FValues[1] * Sx;
    Scaled.FValues[2] := Scaled.FValues[2] * Sx;
    Scaled.FValues[3] := Scaled.FValues[3] * Sy;
    Scaled.FValues[4] := Scaled.FValues[4] * Sy;
    Scaled.FValues[5] := Scaled.FValues[5] * Sy;
  except
    on EMathError do
    begin
      raise EPdfParseException.Create(IllegalValuesMessage);
    end;
  end;
  Scaled.CheckValuesAreFinite;
  Self := Scaled;
end;

function TPdfMatrix.TransformPoint(const X, Y: Single): TPointF;
begin
  Result.X := X * FValues[0] + Y * FValues[3] + FValues[6];
  Result.Y := X * FValues[1] + Y * FValues[4] + FValues[7];
end;

function TPdfMatrix.Transform(const V: TPdfVector): TPdfVector;
begin
  Result.X := V.X * FValues[0] + V.Y * FValues[3] + FValues[6];
  Result.Y := V.X * FValues[1] + V.Y * FValues[4] + FValues[7];
end;

function TPdfMatrix.ScaleX: Single;
begin
  Result := FValues[0];
end;

function TPdfMatrix.ScaleY: Single;
begin
  Result := FValues[4];
end;

function TPdfMatrix.ShearX: Single;
begin
  Result := FValues[3];
end;

function TPdfMatrix.ShearY: Single;
begin
  Result := FValues[1];
end;

function TPdfMatrix.TranslateX: Single;
begin
  Result := FValues[6];
end;

function TPdfMatrix.TranslateY: Single;
begin
  Result := FValues[7];
end;

function TPdfMatrix.ScalingFactorX: Single;
begin
  if IsNotPositiveZero(FValues[1]) then
  begin
    Exit(Sqrt(Sqr(Double(FValues[0])) + Sqr(Double(FValues[1]))));
  end;
  Result := FValues[0];
end;

function TPdfMatrix.ScalingFactorY: Single;
begin
  if IsNotPositiveZero(FValues[3]) then
  begin
    Exit(Sqrt(Sqr(Double(FValues[3])) + Sqr(Double(FValues[4]))));
  end;
  Result := FValues[4];
end;

end.
