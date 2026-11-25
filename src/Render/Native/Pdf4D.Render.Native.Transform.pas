// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: tiny-skia v0.12.0 path/src/transform.rs
// Port of: tiny-skia v0.12.0 path/src/rect.rs (Rect.transform, Rect.bbox_transform, Rect.to_non_zero_rect, NonZeroRect.transform, NonZeroRect.bbox_transform)
// Copyright (c) 2006 The Android Open Source Project, (c) 2020 Yevhenii Reizner. BSD-3-Clause, see licenses/tiny-skia-BSD-3-Clause.txt.
unit Pdf4D.Render.Native.Transform;

{$EXCESSPRECISION OFF}

interface

uses
  System.Math,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Wide,
  Pdf4D.Render.Native.Geometry;

// An affine transformation matrix. It does not guarantee to be valid (the Skia quirk): Transform(0, 0, 0, 0, 0, 0) is fine and so are
// non-finite values. We are using column-major-column-vector matrix notation, therefore it is ky-kx, not kx-ky.
//
// The fields are compared as Rust compares f32: a NaN is never equal to anything. The arithmetic runs in the float mode of TTsFloatMode:
// the inverse of a transform with a zero scale divides by zero and gives infinities, as Rust does.
//
// The Rust Option<Transform> of invert is TryInvert. Rect.transform and the other rectangle methods that need a transform are record
// helpers of this unit, because Pdf4D.Render.Native.Geometry cannot use this unit.

type
  TTsTransform = record
  public
    SX: Single;
    KY: Single;
    KX: Single;
    SY: Single;
    TX: Single;
    TY: Single;

    class function Identity: TTsTransform; static;

    // The parameters are in the order of the rows: (SX, KY, KX, SY, TX, TY)
    class function FromRow(const ScaleX, SkewY, SkewX, ScaleY, TranslateX, TranslateY: Single): TTsTransform; static;
    class function FromTranslate(const TranslateX, TranslateY: Single): TTsTransform; static;
    class function FromScale(const ScaleX, ScaleY: Single): TTsTransform; static;
    class function FromSkew(const SkewX, SkewY: Single): TTsTransform; static;

    // The angle is in degrees
    class function FromRotate(const Angle: Single): TTsTransform; static;
    class function FromRotateAt(const Angle, TranslateX, TranslateY: Single): TTsTransform; static;
    class function FromBBox(const BBox: TTsNonZeroRect): TTsTransform; static;
    class function FromSinCos(const Sin, Cos: Single): TTsTransform; static;

    // True when the transform is finite
    function IsFinite: Boolean;

    // True when the transform is finite and has a non-zero scale
    function IsValid: Boolean;
    function IsIdentity: Boolean;
    function IsScale: Boolean;
    function IsSkew: Boolean;
    function IsTranslate: Boolean;

    // True when the transform contains only scale and translate
    function IsScaleTranslate: Boolean;
    function HasScale: Boolean;
    function HasSkew: Boolean;
    function HasTranslate: Boolean;

    procedure GetScale(out XScale, YScale: Single);

    function PreScale(const ScaleX, ScaleY: Single): TTsTransform;
    function PostScale(const ScaleX, ScaleY: Single): TTsTransform;
    function PreTranslate(const TranslateX, TranslateY: Single): TTsTransform;
    function PostTranslate(const TranslateX, TranslateY: Single): TTsTransform;
    function PreRotate(const Angle: Single): TTsTransform;
    function PostRotate(const Angle: Single): TTsTransform;
    function PreRotateAt(const Angle, TranslateX, TranslateY: Single): TTsTransform;
    function PostRotateAt(const Angle, TranslateX, TranslateY: Single): TTsTransform;
    function PreConcat(const Other: TTsTransform): TTsTransform;
    function PostConcat(const Other: TTsTransform): TTsTransform;

    procedure MapPoint(var Point: TTsPoint);
    procedure MapPoints(var Points: array of TTsPoint);

    // invert of the Rust code: False when the transform cannot be inverted
    function TryInvert(out Inverted: TTsTransform): Boolean;

    class operator Equal(const A, B: TTsTransform): Boolean;
    class operator NotEqual(const A, B: TTsTransform): Boolean;
  end;

  TTsRectTransform = record helper for TTsRect
    // If the transform is a skew, the result is a bounding box around the skewed rectangle
    function TryTransform(const Ts: TTsTransform; out Transformed: TTsRect): Boolean;
    function BBoxTransform(const BBox: TTsNonZeroRect): TTsRect;
    function TryToNonZeroRect(out Converted: TTsNonZeroRect): Boolean;
  end;

  TTsNonZeroRectTransform = record helper for TTsNonZeroRect
    // If the transform is a skew, the result is a bounding box around the skewed rectangle
    function TryTransform(const Ts: TTsTransform; out Transformed: TTsNonZeroRect): Boolean;
    function BBoxTransform(const BBox: TTsNonZeroRect): TTsNonZeroRect;
  end;

implementation

uses
  System.SysUtils;

const
  // PI / 180.0 as an f32, the RADS_PER_DEG of the standard library
  DegreesToRadians: Single = 0.017453292;

// to_radians of f32: the angle times (PI / 180) as an f32
function ToRadians(const Degrees: Single): Single;
begin
  Result := Degrees * DegreesToRadians;
end;

function DCross(const A, B, C, D: Double): Double;
begin
  Result := A * B - C * D;
end;

function DCrossDScale(const A, B, C, D: Single; const Scale: Double): Single;
begin
  Result := Single(DCross(Double(A), Double(B), Double(C), Double(D)) * Scale);
end;

function MulAddMul(const A, B, C, D: Single): Single;
begin
  Result := Single(Double(A) * Double(B) + Double(C) * Double(D));
end;

// The inverse of the determinant, or False when the determinant is nearly zero
function TryInvDeterminant(const Ts: TTsTransform; out InvDet: Double): Boolean;
begin
  const Det: Double = DCross(Double(Ts.SX), Double(Ts.SY), Double(Ts.KX), Double(Ts.KY));

  // Since the determinant is on the order of the cube of the matrix members, compare to the cube of the default nearly-zero constant
  // (although an estimate of the condition number would be better if it wasn't so expensive).
  const Tolerance: Single = TTsScalar.ScalarNearlyZero * TTsScalar.ScalarNearlyZero * TTsScalar.ScalarNearlyZero;
  if TTsScalar.IsNearlyZeroWithinTolerance(Single(Det), Tolerance) then
  begin
    InvDet := 0;

    Exit(False);
  end;

  InvDet := 1.0 / Det;
  Result := True;
end;

function ComputeInv(const Ts: TTsTransform; const InvDet: Double): TTsTransform;
begin
  Result := TTsTransform.FromRow(
    Single(Double(Ts.SY) * InvDet),
    Single(Double(-Ts.KY) * InvDet),
    Single(Double(-Ts.KX) * InvDet),
    Single(Double(Ts.SX) * InvDet),
    DCrossDScale(Ts.KX, Ts.TY, Ts.SY, Ts.TX, InvDet),
    DCrossDScale(Ts.KY, Ts.TX, Ts.SX, Ts.TY, InvDet));
end;

// invert of transform.rs; the transform is not the identity
function TryInvertNonIdentity(const Ts: TTsTransform; out Inverted: TTsTransform): Boolean;
begin
  Inverted := Default(TTsTransform);

  if Ts.IsScaleTranslate then
  begin
    if Ts.HasScale then
    begin
      const InvX: Single = TTsScalar.Invert(Ts.SX);
      const InvY: Single = TTsScalar.Invert(Ts.SY);

      Inverted := TTsTransform.FromRow(InvX, 0.0, 0.0, InvY, -Ts.TX * InvX, -Ts.TY * InvY);
    end
    else
    begin
      // translate only
      Inverted := TTsTransform.FromTranslate(-Ts.TX, -Ts.TY);
    end;

    Exit(True);
  end;

  var InvDet: Double;
  if not TryInvDeterminant(Ts, InvDet) then
  begin
    Exit(False);
  end;

  const InvTs = ComputeInv(Ts, InvDet);
  Result := InvTs.IsFinite;
  if Result then
  begin
    Inverted := InvTs;
  end;
end;

function Concat(const A, B: TTsTransform): TTsTransform;
begin
  if A.IsIdentity then
  begin
    Exit(B);
  end;

  if B.IsIdentity then
  begin
    Exit(A);
  end;

  if (not A.HasSkew) and (not B.HasSkew) then
  begin
    // just scale and translate
    Exit(TTsTransform.FromRow(A.SX * B.SX, 0.0, 0.0, A.SY * B.SY, A.SX * B.TX + A.TX, A.SY * B.TY + A.TY));
  end;

  Result := TTsTransform.FromRow(
    MulAddMul(A.SX, B.SX, A.KX, B.KY),
    MulAddMul(A.KY, B.SX, A.SY, B.KY),
    MulAddMul(A.SX, B.KX, A.KX, B.SY),
    MulAddMul(A.KY, B.KX, A.SY, B.SY),
    MulAddMul(A.SX, B.TX, A.KX, B.TY) + A.TX,
    MulAddMul(A.KY, B.TX, A.SY, B.TY) + A.TY);
end;

{ TTsTransform }

class function TTsTransform.Identity: TTsTransform;
begin
  Result := FromRow(1.0, 0.0, 0.0, 1.0, 0.0, 0.0);
end;

class function TTsTransform.FromRow(const ScaleX, SkewY, SkewX, ScaleY, TranslateX, TranslateY: Single): TTsTransform;
begin
  Result.SX := ScaleX;
  Result.KY := SkewY;
  Result.KX := SkewX;
  Result.SY := ScaleY;
  Result.TX := TranslateX;
  Result.TY := TranslateY;
end;

class function TTsTransform.FromTranslate(const TranslateX, TranslateY: Single): TTsTransform;
begin
  Result := FromRow(1.0, 0.0, 0.0, 1.0, TranslateX, TranslateY);
end;

class function TTsTransform.FromScale(const ScaleX, ScaleY: Single): TTsTransform;
begin
  Result := FromRow(ScaleX, 0.0, 0.0, ScaleY, 0.0, 0.0);
end;

class function TTsTransform.FromSkew(const SkewX, SkewY: Single): TTsTransform;
begin
  Result := FromRow(1.0, SkewY, SkewX, 1.0, 0.0, 0.0);
end;

class function TTsTransform.FromRotate(const Angle: Single): TTsTransform;
begin
  const V: Single = ToRadians(Angle);
  const A: Single = System.Cos(V);
  const B: Single = System.Sin(V);
  const C: Single = -B;
  const D = A;

  Result := FromRow(A, B, C, D, 0.0, 0.0);
end;

class function TTsTransform.FromRotateAt(const Angle, TranslateX, TranslateY: Single): TTsTransform;
begin
  Result := Identity;
  Result := Result.PreTranslate(TranslateX, TranslateY);
  Result := Result.PreConcat(FromRotate(Angle));
  Result := Result.PreTranslate(-TranslateX, -TranslateY);
end;

class function TTsTransform.FromBBox(const BBox: TTsNonZeroRect): TTsTransform;
begin
  Result := FromRow(BBox.Width, 0.0, 0.0, BBox.Height, BBox.X, BBox.Y);
end;

class function TTsTransform.FromSinCos(const Sin, Cos: Single): TTsTransform;
begin
  Result := FromRow(Cos, Sin, -Sin, Cos, 0.0, 0.0);
end;

function TTsTransform.IsFinite: Boolean;
begin
  Result := (TTsScalar.IsFinite(SX) and TTsScalar.IsFinite(KY) and TTsScalar.IsFinite(KX) and TTsScalar.IsFinite(SY)
    and TTsScalar.IsFinite(TX) and TTsScalar.IsFinite(TY));
end;

function TTsTransform.IsValid: Boolean;
begin
  if not IsFinite then
  begin
    Exit(False);
  end;

  var XScale, YScale: Single;
  GetScale(XScale, YScale);

  Result := not (TTsScalar.IsNearlyZeroWithinTolerance(XScale, TTsScalar.FloatEpsilon)
    or TTsScalar.IsNearlyZeroWithinTolerance(YScale, TTsScalar.FloatEpsilon));
end;

function TTsTransform.IsIdentity: Boolean;
begin
  Result := (Self = Identity);
end;

function TTsTransform.IsScale: Boolean;
begin
  Result := (HasScale and (not HasSkew) and (not HasTranslate));
end;

function TTsTransform.IsSkew: Boolean;
begin
  Result := ((not HasScale) and HasSkew and (not HasTranslate));
end;

function TTsTransform.IsTranslate: Boolean;
begin
  Result := ((not HasScale) and (not HasSkew) and HasTranslate);
end;

function TTsTransform.IsScaleTranslate: Boolean;
begin
  Result := ((HasScale or HasTranslate) and (not HasSkew));
end;

function TTsTransform.HasScale: Boolean;
begin
  Result := (TTsLane.IsNe(SX, 1.0) or TTsLane.IsNe(SY, 1.0));
end;

function TTsTransform.HasSkew: Boolean;
begin
  Result := (TTsLane.IsNe(KX, 0.0) or TTsLane.IsNe(KY, 0.0));
end;

function TTsTransform.HasTranslate: Boolean;
begin
  Result := (TTsLane.IsNe(TX, 0.0) or TTsLane.IsNe(TY, 0.0));
end;

procedure TTsTransform.GetScale(out XScale, YScale: Single);
begin
  XScale := System.Sqrt(SX * SX + KX * KX);
  YScale := System.Sqrt(KY * KY + SY * SY);
end;

function TTsTransform.PreScale(const ScaleX, ScaleY: Single): TTsTransform;
begin
  Result := PreConcat(FromScale(ScaleX, ScaleY));
end;

function TTsTransform.PostScale(const ScaleX, ScaleY: Single): TTsTransform;
begin
  Result := PostConcat(FromScale(ScaleX, ScaleY));
end;

function TTsTransform.PreTranslate(const TranslateX, TranslateY: Single): TTsTransform;
begin
  Result := PreConcat(FromTranslate(TranslateX, TranslateY));
end;

function TTsTransform.PostTranslate(const TranslateX, TranslateY: Single): TTsTransform;
begin
  Result := PostConcat(FromTranslate(TranslateX, TranslateY));
end;

function TTsTransform.PreRotate(const Angle: Single): TTsTransform;
begin
  Result := PreConcat(FromRotate(Angle));
end;

function TTsTransform.PostRotate(const Angle: Single): TTsTransform;
begin
  Result := PostConcat(FromRotate(Angle));
end;

function TTsTransform.PreRotateAt(const Angle, TranslateX, TranslateY: Single): TTsTransform;
begin
  Result := PreConcat(FromRotateAt(Angle, TranslateX, TranslateY));
end;

function TTsTransform.PostRotateAt(const Angle, TranslateX, TranslateY: Single): TTsTransform;
begin
  Result := PostConcat(FromRotateAt(Angle, TranslateX, TranslateY));
end;

function TTsTransform.PreConcat(const Other: TTsTransform): TTsTransform;
begin
  Result := Concat(Self, Other);
end;

function TTsTransform.PostConcat(const Other: TTsTransform): TTsTransform;
begin
  Result := Concat(Other, Self);
end;

procedure TTsTransform.MapPoint(var Point: TTsPoint);
begin
  if IsIdentity then
  begin
    // Do nothing.
    Exit;
  end;

  if IsTranslate then
  begin
    Point.X := Point.X + TX;
    Point.Y := Point.Y + TY;
  end
  else if IsScaleTranslate then
  begin
    Point.X := Point.X * SX + TX;
    Point.Y := Point.Y * SY + TY;
  end
  else
  begin
    const NewX: Single = Point.X * SX + Point.Y * KX + TX;
    const NewY: Single = Point.X * KY + Point.Y * SY + TY;

    Point.X := NewX;
    Point.Y := NewY;
  end;
end;

procedure TTsTransform.MapPoints(var Points: array of TTsPoint);
begin
  if Length(Points) = 0 then
  begin
    Exit;
  end;

  // The Rust code has a TODO for simd here; only the scalar loops exist
  if IsIdentity then
  begin
    // Do nothing.
    Exit;
  end;

  const Translate = IsTranslate;
  const ScaleTranslate = IsScaleTranslate;

  for var I := 0 to High(Points) do
  begin
    if Translate then
    begin
      Points[I].X := Points[I].X + TX;
      Points[I].Y := Points[I].Y + TY;
    end
    else if ScaleTranslate then
    begin
      Points[I].X := Points[I].X * SX + TX;
      Points[I].Y := Points[I].Y * SY + TY;
    end
    else
    begin
      const NewX: Single = Points[I].X * SX + Points[I].Y * KX + TX;
      const NewY: Single = Points[I].X * KY + Points[I].Y * SY + TY;

      Points[I].X := NewX;
      Points[I].Y := NewY;
    end;
  end;
end;

function TTsTransform.TryInvert(out Inverted: TTsTransform): Boolean;
begin
  // Allow the trivial case to be inlined.
  if IsIdentity then
  begin
    Inverted := Self;

    Exit(True);
  end;

  Result := TryInvertNonIdentity(Self, Inverted);
end;

class operator TTsTransform.Equal(const A, B: TTsTransform): Boolean;
begin
  Result := (TTsLane.IsEq(A.SX, B.SX) and TTsLane.IsEq(A.KX, B.KX) and TTsLane.IsEq(A.KY, B.KY) and TTsLane.IsEq(A.SY, B.SY)
    and TTsLane.IsEq(A.TX, B.TX) and TTsLane.IsEq(A.TY, B.TY));
end;

class operator TTsTransform.NotEqual(const A, B: TTsTransform): Boolean;
begin
  Result := not (A = B);
end;

{ TTsRectTransform }

function TTsRectTransform.TryTransform(const Ts: TTsTransform; out Transformed: TTsRect): Boolean;
begin
  Transformed := Default(TTsRect);

  if Ts.IsIdentity then
  begin
    Transformed := Self;

    Exit(True);
  end;

  if Ts.HasSkew then
  begin
    // we need to transform all 4 corners
    var Corners: array[0..3] of TTsPoint;
    Corners[0] := TTsPoint.FromXY(Left, Top);
    Corners[1] := TTsPoint.FromXY(Right, Top);
    Corners[2] := TTsPoint.FromXY(Left, Bottom);
    Corners[3] := TTsPoint.FromXY(Right, Bottom);

    Ts.MapPoints(Corners);
    Exit(TTsRect.TryFromPoints(Corners, Transformed));
  end;

  // Faster (more common) case
  var Opposite: array[0..1] of TTsPoint;
  Opposite[0] := TTsPoint.FromXY(Left, Top);
  Opposite[1] := TTsPoint.FromXY(Right, Bottom);

  Ts.MapPoints(Opposite);
  Result := TTsRect.TryFromPoints(Opposite, Transformed);
end;

function TTsRectTransform.BBoxTransform(const BBox: TTsNonZeroRect): TTsRect;
begin
  const NewX: Single = X * BBox.Width + BBox.X;
  const NewY: Single = Y * BBox.Height + BBox.Y;
  const NewW: Single = Width * BBox.Width;
  const NewH: Single = Height * BBox.Height;

  if not TTsRect.TryFromXYWH(NewX, NewY, NewW, NewH, Result) then
  begin
    raise ETsGeometryError.Create('Rect.from_xywh failed on the result of a bounding box transform');
  end;
end;

function TTsRectTransform.TryToNonZeroRect(out Converted: TTsNonZeroRect): Boolean;
begin
  Result := TTsNonZeroRect.TryFromXYWH(X, Y, Width, Height, Converted);
end;

{ TTsNonZeroRectTransform }

function TTsNonZeroRectTransform.TryTransform(const Ts: TTsTransform; out Transformed: TTsNonZeroRect): Boolean;
begin
  Transformed := Default(TTsNonZeroRect);

  if Ts.IsIdentity then
  begin
    Transformed := Self;

    Exit(True);
  end;

  var TransformedRect: TTsRect;
  Result := (ToRect.TryTransform(Ts, TransformedRect) and TransformedRect.TryToNonZeroRect(Transformed));
end;

function TTsNonZeroRectTransform.BBoxTransform(const BBox: TTsNonZeroRect): TTsNonZeroRect;
begin
  const NewX: Single = X * BBox.Width + BBox.X;
  const NewY: Single = Y * BBox.Height + BBox.Y;
  const NewW: Single = Width * BBox.Width;
  const NewH: Single = Height * BBox.Height;

  if not TTsNonZeroRect.TryFromXYWH(NewX, NewY, NewW, NewH, Result) then
  begin
    raise ETsGeometryError.Create('NonZeroRect.from_xywh failed on the result of a bounding box transform');
  end;
end;

end.
