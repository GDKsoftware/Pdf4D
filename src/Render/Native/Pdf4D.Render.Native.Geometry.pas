// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: tiny-skia v0.12.0 path/src/lib.rs (Point)
// Port of: tiny-skia v0.12.0 path/src/rect.rs
// Port of: tiny-skia v0.12.0 path/src/size.rs
// Port of: tiny-skia v0.12.0 src/geom.rs
// Copyright (c) 2011 Google Inc., (c) 2020 Yevhenii Reizner. BSD-3-Clause, see licenses/tiny-skia-BSD-3-Clause.txt.
unit Pdf4D.Render.Native.Geometry;

// The wrapping arithmetic of the integer helpers is intended
{$OVERFLOWCHECKS OFF}
{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Math,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Wide;

// A Rust Option<T> result is a Boolean function with an out parameter (TryFromLTRB, TryFromXYWH, TryFromWH); an unwrap() that fails raises
// ETsGeometryError. LengthU32 (NonZeroU32) is a Cardinal that the constructors keep above zero; the FromWHSafe and FromXYWHSafe
// constructors trust the caller, as the Rust ones do.
//
// Rust compares floats with NaN as false. The values of the rectangles and sizes are finite by construction, so their comparisons need no
// guard; TTsPoint holds any Single, and its comparisons are guarded where a NaN can reach them.
//
// The operations that can see an infinity or a NaN in arithmetic (a product of an infinity and zero, a division by zero) run in the float
// mode of TTsFloatMode, like the rest of the native renderer.
//
// A record cannot refer to a record declared later, so the conversions that point forward are record helpers at the end of the interface
// (TTsIntSizeConversions, TTsSizeConversions, TTsIntRectConversions). The conversions that need a transform (Rect.transform,
// Rect.bbox_transform, Rect.to_non_zero_rect, NonZeroRect.transform, NonZeroRect.bbox_transform) are record helpers in
// Pdf4D.Render.Native.Transform.

type
  ETsGeometryError = class(Exception);

  TTsPoint = record
  public
    X: Single;
    Y: Single;

    class function FromXY(const FromX, FromY: Single): TTsPoint; static;
    class function FromF32x2(const Value: TF32x2): TTsPoint; static;
    function ToF32x2: TF32x2;
    class function Zero: TTsPoint; static;

    function IsZero: Boolean;

    // Both values are other than infinities and NaN
    function IsFinite: Boolean;
    function AlmostEqual(const Other: TTsPoint): Boolean;
    function EqualsWithinTolerance(const Other: TTsPoint; const Tolerance: Single): Boolean;

    // Scales (X, Y) so that Length is one, if possible. If the length is nearly zero, sets the vector to (0, 0) and returns False.
    function Normalize: Boolean;
    function SetNormalize(const FromX, FromY: Single): Boolean;
    function CanNormalize: Boolean;

    // The Euclidean distance from the origin
    function Length: Single;
    function SetLength(const NewLength: Single): Boolean;
    function SetLengthFrom(const FromX, FromY, NewLength: Single): Boolean;
    function Distance(const Other: TTsPoint): Single;
    function Dot(const Other: TTsPoint): Single;
    function Cross(const Other: TTsPoint): Single;
    function DistanceToSqd(const Point: TTsPoint): Single;
    function LengthSqd: Single;

    // Scale in Rust: scales the point in place
    procedure Scale(const Factor: Single);
    function Scaled(const Factor: Single): TTsPoint;
    procedure SwapCoords;
    procedure RotateCw;
    procedure RotateCcw;

    // The AddAssign, SubAssign and MulAssign operators are not ported (a Rust a += b is a := a + b)
    class operator Negative(const A: TTsPoint): TTsPoint;
    class operator Add(const A, B: TTsPoint): TTsPoint;
    class operator Subtract(const A, B: TTsPoint): TTsPoint;
    class operator Multiply(const A, B: TTsPoint): TTsPoint;
    class operator Equal(const A, B: TTsPoint): Boolean;
    class operator NotEqual(const A, B: TTsPoint): Boolean;
  end;

  // Width and height are positive and non-zero
  TTsIntSize = record
  private
    FWidth: Cardinal;
    FHeight: Cardinal;

  public
    class function TryFromWH(const Width, Height: Cardinal; out Size: TTsIntSize): Boolean; static;
    class function FromWHSafe(const Width, Height: Cardinal): TTsIntSize; static;

    function Width: Cardinal;
    function Height: Cardinal;
    procedure Dimensions(out OfWidth, OfHeight: Cardinal);

    function TryScaleBy(const Factor: Single; out Scaled: TTsIntSize): Boolean;
    function ScaleTo(const Target: TTsIntSize): TTsIntSize;
    function TryScaleToWidth(const NewWidth: Cardinal; out Scaled: TTsIntSize): Boolean;
    function TryScaleToHeight(const NewHeight: Cardinal; out Scaled: TTsIntSize): Boolean;

    class operator Equal(const A, B: TTsIntSize): Boolean;
    class operator NotEqual(const A, B: TTsIntSize): Boolean;
  end;

  // Width and height are positive, non-zero and finite
  TTsSize = record
  private
    FWidth: TTsNonZeroPositiveF32;
    FHeight: TTsNonZeroPositiveF32;

  public
    class function TryFromWH(const Width, Height: Single; out Size: TTsSize): Boolean; static;

    function Width: Single;
    function Height: Single;

    function ScaleTo(const Target: TTsSize): TTsSize;
    function ExpandTo(const Target: TTsSize): TTsSize;
    function TryScaleBy(const Factor: Single; out Scaled: TTsSize): Boolean;
    function TryScaleToWidth(const NewWidth: Single; out Scaled: TTsSize): Boolean;
    function TryScaleToHeight(const NewHeight: Single; out Scaled: TTsSize): Boolean;
    function ToIntSize: TTsIntSize;

    class operator Equal(const A, B: TTsSize): Boolean;
    class operator NotEqual(const A, B: TTsSize): Boolean;
  end;

  // Width and height are in 1..=i32::MAX range, X+Width and Y+Height do not overflow
  TTsIntRect = record
  private
    FX: Integer;
    FY: Integer;
    FWidth: Cardinal;
    FHeight: Cardinal;

  public
    class function TryFromXYWH(const X, Y: Integer; const Width, Height: Cardinal; out Rect: TTsIntRect): Boolean; static;
    class function TryFromLTRB(const Left, Top, Right, Bottom: Integer; out Rect: TTsIntRect): Boolean; static;

    function X: Integer;
    function Y: Integer;
    function Width: Cardinal;
    function Height: Cardinal;
    function Left: Integer;
    function Top: Integer;
    function Right: Integer;
    function Bottom: Integer;
    function Size: TTsIntSize;

    // True when the rect completely includes Other
    function Contains(const Other: TTsIntRect): Boolean;
    function TryIntersect(const Other: TTsIntRect; out Intersection: TTsIntRect): Boolean;
    function TryInset(const Dx, Dy: Integer; out Inset: TTsIntRect): Boolean;
    function TryMakeOutset(const Dx, Dy: Integer; out Outset: TTsIntRect): Boolean;
    function TryTranslate(const Tx, Ty: Integer; out Translated: TTsIntRect): Boolean;
    function TryTranslateTo(const NewX, NewY: Integer; out Translated: TTsIntRect): Boolean;

    class operator Equal(const A, B: TTsIntRect): Boolean;
    class operator NotEqual(const A, B: TTsIntRect): Boolean;
  end;

  // All values are finite, Left <= Right, Top <= Bottom, width and height are <= f32::MAX
  TTsRect = record
  private
    FLeft: TTsFiniteF32;
    FTop: TTsFiniteF32;
    FRight: TTsFiniteF32;
    FBottom: TTsFiniteF32;

  public
    class function TryFromLTRB(const Left, Top, Right, Bottom: Single; out Rect: TTsRect): Boolean; static;
    class function TryFromXYWH(const X, Y, Width, Height: Single; out Rect: TTsRect): Boolean; static;

    // Returns False if the array is empty or contains an infinity or a NaN
    class function TryFromPoints(const Points: array of TTsPoint; out Rect: TTsRect): Boolean; static;

    function Left: Single;
    function Top: Single;
    function Right: Single;
    function Bottom: Single;
    function X: Single;
    function Y: Single;
    function Width: Single;
    function Height: Single;
    function IsEmpty: Boolean;

    // Converts into an IntRect by adding 0.5 and discarding the fractional portion; width and height are >= 1
    function TryRound(out Rounded: TTsIntRect): Boolean;

    // Converts into an IntRect rounding outwards; width and height are >= 1
    function TryRoundOut(out Rounded: TTsIntRect): Boolean;
    function TryIntersect(const Other: TTsRect; out Intersection: TTsRect): Boolean;

    // Returns False if the width or height would overflow
    function TryJoin(const Other: TTsRect; out Joined: TTsRect): Boolean;
    function TryInset(const Dx, Dy: Single; out Inset: TTsRect): Boolean;
    function TryOutset(const Dx, Dy: Single; out Outset: TTsRect): Boolean;

    class operator Equal(const A, B: TTsRect): Boolean;
    class operator NotEqual(const A, B: TTsRect): Boolean;
  end;

  // Like TTsRect, but Left < Right and Top < Bottom
  TTsNonZeroRect = record
  private
    FLeft: TTsFiniteF32;
    FTop: TTsFiniteF32;
    FRight: TTsFiniteF32;
    FBottom: TTsFiniteF32;

  public
    class function TryFromLTRB(const Left, Top, Right, Bottom: Single; out Rect: TTsNonZeroRect): Boolean; static;
    class function TryFromXYWH(const X, Y, Width, Height: Single; out Rect: TTsNonZeroRect): Boolean; static;

    function Left: Single;
    function Top: Single;
    function Right: Single;
    function Bottom: Single;
    function X: Single;
    function Y: Single;
    function Width: Single;
    function Height: Single;
    function Size: TTsSize;
    function TryTranslateTo(const NewX, NewY: Single; out Translated: TTsNonZeroRect): Boolean;
    function ToRect: TTsRect;
    function ToIntRect: TTsIntRect;

    class operator Equal(const A, B: TTsNonZeroRect): Boolean;
    class operator NotEqual(const A, B: TTsNonZeroRect): Boolean;
  end;

  // X and Y are in 0..=i32::MAX, width and height in 1..=i32::MAX, X+Width and Y+Height do not overflow
  TTsScreenIntRect = record
  private
    FX: Cardinal;
    FY: Cardinal;
    FWidth: Cardinal;
    FHeight: Cardinal;

  public
    class function TryFromXYWH(const X, Y, Width, Height: Cardinal; out Rect: TTsScreenIntRect): Boolean; static;
    class function FromXYWHSafe(const X, Y, Width, Height: Cardinal): TTsScreenIntRect; static;

    function X: Cardinal;
    function Y: Cardinal;
    function Width: Cardinal;
    function Height: Cardinal;
    function WidthSafe: Cardinal;
    function Left: Cardinal;
    function Top: Cardinal;

    // The right edge is at least 1
    function Right: Cardinal;

    // The bottom edge is at least 1
    function Bottom: Cardinal;
    function Size: TTsIntSize;

    // True when the rect completely includes Other
    function Contains(const Other: TTsScreenIntRect): Boolean;
    function ToIntRect: TTsIntRect;
    function ToRect: TTsRect;

    class operator Equal(const A, B: TTsScreenIntRect): Boolean;
    class operator NotEqual(const A, B: TTsScreenIntRect): Boolean;
  end;

  TTsIntSizeConversions = record helper for TTsIntSize
    function ToSize: TTsSize;
    function ToIntRect(const X, Y: Integer): TTsIntRect;

    // IntSizeExt::to_screen_int_rect
    function ToScreenIntRect(const X, Y: Cardinal): TTsScreenIntRect;
  end;

  TTsSizeConversions = record helper for TTsSize
    function TryToRect(const X, Y: Single; out Rect: TTsRect): Boolean;
    function ToNonZeroRect(const X, Y: Single): TTsNonZeroRect;
  end;

  TTsIntRectConversions = record helper for TTsIntRect
    function ToRect: TTsRect;

    // IntRectExt::to_screen_int_rect: False when X or Y is negative
    function TryToScreenIntRect(out Rect: TTsScreenIntRect): Boolean;
  end;

implementation

const
  // i32::MAX as a u32
  MaxInt32AsCardinal: Cardinal = 2147483647;
  // f32::MAX as a Double, for checked_f32_sub
  F32MaxAsDouble: Double = 3.4028234663852886E+38;

procedure RaiseUnwrapFailed(const Operation: string);
begin
  raise ETsGeometryError.CreateFmt('%s failed on a value that is checked by its constructor', [Operation]);
end;

// `x as u32` for a Single: saturating, NaN becomes 0
function SaturateToUInt32(const Value: Single): Cardinal;
begin
  if IsNan(Value) or (Value <= 0) then
  begin
    Exit(0);
  end;

  if Value >= 4294967296.0 then
  begin
    Exit(High(Cardinal));
  end;

  Result := Cardinal(Trunc(Value));
end;

// `x as f32` for a u32
function UInt32ToSingle(const Value: Cardinal): Single;
begin
  Result := Single(Int64(Value));
end;

function SaturatingSubInt32(const A, B: Integer): Integer;
begin
  const Difference = Int64(A) - Int64(B);

  if Difference < Low(Integer) then
  begin
    Exit(Low(Integer));
  end;

  if Difference > High(Integer) then
  begin
    Exit(High(Integer));
  end;

  Result := Integer(Difference);
end;

function SaturatingAddInt32(const A, B: Integer): Integer;
begin
  const Sum = Int64(A) + Int64(B);

  if Sum < Low(Integer) then
  begin
    Exit(Low(Integer));
  end;

  if Sum > High(Integer) then
  begin
    Exit(High(Integer));
  end;

  Result := Integer(Sum);
end;

// i32::checked_add for an i32 and a value that is already known to fit in an i64
function TryCheckedAddInt32(const A: Integer; const B: Int64; out Sum: Integer): Boolean;
begin
  const Total = Int64(A) + B;

  Result := ((Total >= Low(Integer)) and (Total <= High(Integer)));
  if Result then
  begin
    Sum := Integer(Total);
  end
  else
  begin
    Sum := 0;
  end;
end;

// checked_f32_sub of rect.rs. Not sure if this is perfectly correct, as the Rust comment says.
function TryCheckedF32Sub(const A, B: Single; out Difference: Single): Boolean;
begin
  const N = Double(A) - Double(B);

  Result := ((N > -F32MaxAsDouble) and (N < F32MaxAsDouble));
  if Result then
  begin
    Difference := Single(N);
  end
  else
  begin
    Difference := 0;
  end;
end;

{ TTsPoint }

class function TTsPoint.FromXY(const FromX, FromY: Single): TTsPoint;
begin
  Result.X := FromX;
  Result.Y := FromY;
end;

class function TTsPoint.FromF32x2(const Value: TF32x2): TTsPoint;
begin
  Result := FromXY(Value.X, Value.Y);
end;

function TTsPoint.ToF32x2: TF32x2;
begin
  Result := TF32x2.Create(X, Y);
end;

class function TTsPoint.Zero: TTsPoint;
begin
  Result := FromXY(0, 0);
end;

function TTsPoint.IsZero: Boolean;
begin
  Result := (TTsLane.IsEq(X, 0) and TTsLane.IsEq(Y, 0));
end;

function TTsPoint.IsFinite: Boolean;
begin
  Result := TTsScalar.IsFinite(X * Y);
end;

function TTsPoint.AlmostEqual(const Other: TTsPoint): Boolean;
begin
  Result := not (Self - Other).CanNormalize;
end;

function TTsPoint.EqualsWithinTolerance(const Other: TTsPoint; const Tolerance: Single): Boolean;
begin
  Result := (TTsScalar.IsNearlyZeroWithinTolerance(X - Other.X, Tolerance)
    and TTsScalar.IsNearlyZeroWithinTolerance(Y - Other.Y, Tolerance));
end;

function TTsPoint.Normalize: Boolean;
begin
  Result := SetLengthFrom(X, Y, 1.0);
end;

function TTsPoint.SetNormalize(const FromX, FromY: Single): Boolean;
begin
  Result := SetLengthFrom(FromX, FromY, 1.0);
end;

function TTsPoint.CanNormalize: Boolean;
begin
  Result := (TTsScalar.IsFinite(X) and TTsScalar.IsFinite(Y) and (TTsLane.IsNe(X, 0) or TTsLane.IsNe(Y, 0)));
end;

function TTsPoint.Length: Single;
begin
  const Mag2: Single = X * X + Y * Y;

  if TTsScalar.IsFinite(Mag2) then
  begin
    Exit(System.Sqrt(Mag2));
  end;

  const Xx = Double(X);
  const Yy = Double(Y);

  Result := Single(System.Sqrt(Xx * Xx + Yy * Yy));
end;

function TTsPoint.SetLength(const NewLength: Single): Boolean;
begin
  Result := SetLengthFrom(X, Y, NewLength);
end;

// set_point_length of lib.rs. We have to worry about 2 tricky conditions:
// 1. underflow of mag2 (compared against nearlyzero^2)
// 2. overflow of mag2 (compared w/ isfinite)
// If we underflow, we return false. If we overflow, we compute again using doubles, which is much slower but will not overflow.
// The Rust code is always called with orig_length = None, so that parameter is not ported.
function TTsPoint.SetLengthFrom(const FromX, FromY, NewLength: Single): Boolean;
begin
  // our mag2 step overflowed to infinity, so use doubles instead. Much slower, but needed when x or y are very large, otherwise we
  // divide by inf. and return (0,0) vector.
  const Xx = Double(FromX);
  const Yy = Double(FromY);
  const Dmag: Double = System.Sqrt(Xx * Xx + Yy * Yy);
  const Dscale: Double = Double(NewLength) / Dmag;
  const ScaledX: Single = FromX * Single(Dscale);
  const ScaledY: Single = FromY * Single(Dscale);

  // check if we're not finite, or we're zero-length
  if (not TTsScalar.IsFinite(ScaledX)) or (not TTsScalar.IsFinite(ScaledY)) or (TTsLane.IsEq(ScaledX, 0) and TTsLane.IsEq(ScaledY, 0)) then
  begin
    Self := Zero;

    Exit(False);
  end;

  Self := FromXY(ScaledX, ScaledY);
  Result := True;
end;

function TTsPoint.Distance(const Other: TTsPoint): Single;
begin
  Result := (Self - Other).Length;
end;

function TTsPoint.Dot(const Other: TTsPoint): Single;
begin
  Result := X * Other.X + Y * Other.Y;
end;

function TTsPoint.Cross(const Other: TTsPoint): Single;
begin
  Result := X * Other.Y - Y * Other.X;
end;

function TTsPoint.DistanceToSqd(const Point: TTsPoint): Single;
begin
  const Dx: Single = X - Point.X;
  const Dy: Single = Y - Point.Y;

  Result := Dx * Dx + Dy * Dy;
end;

function TTsPoint.LengthSqd: Single;
begin
  Result := Dot(Self);
end;

procedure TTsPoint.Scale(const Factor: Single);
begin
  X := X * Factor;
  Y := Y * Factor;
end;

function TTsPoint.Scaled(const Factor: Single): TTsPoint;
begin
  Result := FromXY(X * Factor, Y * Factor);
end;

procedure TTsPoint.SwapCoords;
begin
  const Swapped = X;

  X := Y;
  Y := Swapped;
end;

procedure TTsPoint.RotateCw;
begin
  SwapCoords;
  X := -X;
end;

procedure TTsPoint.RotateCcw;
begin
  SwapCoords;
  Y := -Y;
end;

class operator TTsPoint.Negative(const A: TTsPoint): TTsPoint;
begin
  Result := FromXY(-A.X, -A.Y);
end;

class operator TTsPoint.Add(const A, B: TTsPoint): TTsPoint;
begin
  Result := FromXY(A.X + B.X, A.Y + B.Y);
end;

class operator TTsPoint.Subtract(const A, B: TTsPoint): TTsPoint;
begin
  Result := FromXY(A.X - B.X, A.Y - B.Y);
end;

class operator TTsPoint.Multiply(const A, B: TTsPoint): TTsPoint;
begin
  Result := FromXY(A.X * B.X, A.Y * B.Y);
end;

class operator TTsPoint.Equal(const A, B: TTsPoint): Boolean;
begin
  Result := (TTsLane.IsEq(A.X, B.X) and TTsLane.IsEq(A.Y, B.Y));
end;

class operator TTsPoint.NotEqual(const A, B: TTsPoint): Boolean;
begin
  Result := not (A = B);
end;

{ TTsIntSize }

class function TTsIntSize.TryFromWH(const Width, Height: Cardinal; out Size: TTsIntSize): Boolean;
begin
  Size := Default(TTsIntSize);

  Result := ((Width <> 0) and (Height <> 0));
  if Result then
  begin
    Size.FWidth := Width;
    Size.FHeight := Height;
  end;
end;

class function TTsIntSize.FromWHSafe(const Width, Height: Cardinal): TTsIntSize;
begin
  Result.FWidth := Width;
  Result.FHeight := Height;
end;

function TTsIntSize.Width: Cardinal;
begin
  Result := FWidth;
end;

function TTsIntSize.Height: Cardinal;
begin
  Result := FHeight;
end;

procedure TTsIntSize.Dimensions(out OfWidth, OfHeight: Cardinal);
begin
  OfWidth := FWidth;
  OfHeight := FHeight;
end;

function TTsIntSize.TryScaleBy(const Factor: Single; out Scaled: TTsIntSize): Boolean;
begin
  const ScaledWidth: Single = UInt32ToSingle(FWidth) * Factor;
  const ScaledHeight: Single = UInt32ToSingle(FHeight) * Factor;

  Result := TryFromWH(SaturateToUInt32(TTsScalar.RoundHalfAwayFromZero(ScaledWidth)),
    SaturateToUInt32(TTsScalar.RoundHalfAwayFromZero(ScaledHeight)), Scaled);
end;

// size_scale of size.rs, with expand = False
function TTsIntSize.ScaleTo(const Target: TTsIntSize): TTsIntSize;
begin
  const Rw = SaturateToUInt32(TTsScalar.CeilF(UInt32ToSingle(Target.Height) * UInt32ToSingle(FWidth) / UInt32ToSingle(FHeight)));
  const WithH = (Rw >= Target.Width);

  if not WithH then
  begin
    if not TryFromWH(Rw, Target.Height, Result) then
    begin
      RaiseUnwrapFailed('IntSize.from_wh');
    end;

    Exit;
  end;

  const H = SaturateToUInt32(TTsScalar.CeilF(UInt32ToSingle(Target.Width) * UInt32ToSingle(FHeight) / UInt32ToSingle(FWidth)));

  if not TryFromWH(Target.Width, H, Result) then
  begin
    RaiseUnwrapFailed('IntSize.from_wh');
  end;
end;

function TTsIntSize.TryScaleToWidth(const NewWidth: Cardinal; out Scaled: TTsIntSize): Boolean;
begin
  const NewHeight = TTsScalar.CeilF(UInt32ToSingle(NewWidth) * UInt32ToSingle(FHeight) / UInt32ToSingle(FWidth));

  Result := TryFromWH(NewWidth, SaturateToUInt32(NewHeight), Scaled);
end;

function TTsIntSize.TryScaleToHeight(const NewHeight: Cardinal; out Scaled: TTsIntSize): Boolean;
begin
  const NewWidth = TTsScalar.CeilF(UInt32ToSingle(NewHeight) * UInt32ToSingle(FWidth) / UInt32ToSingle(FHeight));

  Result := TryFromWH(SaturateToUInt32(NewWidth), NewHeight, Scaled);
end;

class operator TTsIntSize.Equal(const A, B: TTsIntSize): Boolean;
begin
  Result := ((A.FWidth = B.FWidth) and (A.FHeight = B.FHeight));
end;

class operator TTsIntSize.NotEqual(const A, B: TTsIntSize): Boolean;
begin
  Result := not (A = B);
end;

{ TTsSize }

class function TTsSize.TryFromWH(const Width, Height: Single; out Size: TTsSize): Boolean;
begin
  Size := Default(TTsSize);

  Result := (TTsNonZeroPositiveF32.TryCreate(Width, Size.FWidth) and TTsNonZeroPositiveF32.TryCreate(Height, Size.FHeight));
end;

function TTsSize.Width: Single;
begin
  Result := FWidth.Get;
end;

function TTsSize.Height: Single;
begin
  Result := FHeight.Get;
end;

// size_scale_f64 of size.rs: the Rust name says f64, the arithmetic is f32
function SizeScaleF64(const S1, S2: TTsSize; const Expand: Boolean): TTsSize;
begin
  const Rw: Single = S2.Height * S1.Width / S1.Height;

  var WithH: Boolean;
  if Expand then
  begin
    WithH := TTsLane.IsLe(Rw, S2.Width);
  end
  else
  begin
    WithH := TTsLane.IsGe(Rw, S2.Width);
  end;

  if not WithH then
  begin
    if not TTsSize.TryFromWH(Rw, S2.Height, Result) then
    begin
      RaiseUnwrapFailed('Size.from_wh');
    end;

    Exit;
  end;

  const H: Single = S2.Width * S1.Height / S1.Width;

  if not TTsSize.TryFromWH(S2.Width, H, Result) then
  begin
    RaiseUnwrapFailed('Size.from_wh');
  end;
end;

function TTsSize.ScaleTo(const Target: TTsSize): TTsSize;
begin
  Result := SizeScaleF64(Self, Target, False);
end;

function TTsSize.ExpandTo(const Target: TTsSize): TTsSize;
begin
  Result := SizeScaleF64(Self, Target, True);
end;

function TTsSize.TryScaleBy(const Factor: Single; out Scaled: TTsSize): Boolean;
begin
  Result := TryFromWH(Width * Factor, Height * Factor, Scaled);
end;

function TTsSize.TryScaleToWidth(const NewWidth: Single; out Scaled: TTsSize): Boolean;
begin
  const NewHeight: Single = NewWidth * Height / Width;

  Result := TryFromWH(NewWidth, NewHeight, Scaled);
end;

function TTsSize.TryScaleToHeight(const NewHeight: Single; out Scaled: TTsSize): Boolean;
begin
  const NewWidth: Single = NewHeight * Width / Height;

  Result := TryFromWH(NewWidth, NewHeight, Scaled);
end;

function TTsSize.ToIntSize: TTsIntSize;
begin
  const IntWidth = SaturateToUInt32(TTsScalar.RoundHalfAwayFromZero(Width));
  const IntHeight = SaturateToUInt32(TTsScalar.RoundHalfAwayFromZero(Height));

  if not TTsIntSize.TryFromWH(Max(Cardinal(1), IntWidth), Max(Cardinal(1), IntHeight), Result) then
  begin
    RaiseUnwrapFailed('IntSize.from_wh');
  end;
end;

class operator TTsSize.Equal(const A, B: TTsSize): Boolean;
begin
  Result := ((A.Width = B.Width) and (A.Height = B.Height));
end;

class operator TTsSize.NotEqual(const A, B: TTsSize): Boolean;
begin
  Result := not (A = B);
end;

{ TTsIntRect }

class function TTsIntRect.TryFromXYWH(const X, Y: Integer; const Width, Height: Cardinal; out Rect: TTsIntRect): Boolean;
begin
  Rect := Default(TTsIntRect);

  var Ignored: Integer;
  const FitsX = ((Width <= MaxInt32AsCardinal) and TryCheckedAddInt32(X, Width, Ignored));
  const FitsY = ((Height <= MaxInt32AsCardinal) and TryCheckedAddInt32(Y, Height, Ignored));

  Result := (FitsX and FitsY and (Width <> 0) and (Height <> 0));
  if Result then
  begin
    Rect.FX := X;
    Rect.FY := Y;
    Rect.FWidth := Width;
    Rect.FHeight := Height;
  end;
end;

class function TTsIntRect.TryFromLTRB(const Left, Top, Right, Bottom: Integer; out Rect: TTsIntRect): Boolean;
begin
  Rect := Default(TTsIntRect);

  const Width = Int64(Right) - Int64(Left);
  const Height = Int64(Bottom) - Int64(Top);

  // checked_sub, then u32::try_from: a negative or an out-of-range difference fails
  if (Width < 0) or (Width > High(Integer)) or (Height < 0) or (Height > High(Integer)) then
  begin
    Exit(False);
  end;

  Result := TryFromXYWH(Left, Top, Cardinal(Width), Cardinal(Height), Rect);
end;

function TTsIntRect.X: Integer;
begin
  Result := FX;
end;

function TTsIntRect.Y: Integer;
begin
  Result := FY;
end;

function TTsIntRect.Width: Cardinal;
begin
  Result := FWidth;
end;

function TTsIntRect.Height: Cardinal;
begin
  Result := FHeight;
end;

function TTsIntRect.Left: Integer;
begin
  Result := FX;
end;

function TTsIntRect.Top: Integer;
begin
  Result := FY;
end;

function TTsIntRect.Right: Integer;
begin
  // No overflow is guaranteed by constructors.
  Result := FX + Integer(FWidth);
end;

function TTsIntRect.Bottom: Integer;
begin
  // No overflow is guaranteed by constructors.
  Result := FY + Integer(FHeight);
end;

function TTsIntRect.Size: TTsIntSize;
begin
  Result := TTsIntSize.FromWHSafe(FWidth, FHeight);
end;

function TTsIntRect.Contains(const Other: TTsIntRect): Boolean;
begin
  Result := ((FX <= Other.FX) and (FY <= Other.FY) and (Right >= Other.Right) and (Bottom >= Other.Bottom));
end;

function TTsIntRect.TryIntersect(const Other: TTsIntRect; out Intersection: TTsIntRect): Boolean;
begin
  const IntersectLeft = Max(FX, Other.FX);
  const IntersectTop = Max(FY, Other.FY);

  const IntersectRight = Min(Right, Other.Right);
  const IntersectBottom = Min(Bottom, Other.Bottom);

  Result := TryFromLTRB(IntersectLeft, IntersectTop, IntersectRight, IntersectBottom, Intersection);
end;

function TTsIntRect.TryInset(const Dx, Dy: Integer; out Inset: TTsIntRect): Boolean;
begin
  Result := TryFromLTRB(TTsScalar.WrappingAddI32(Left, Dx), TTsScalar.WrappingAddI32(Top, Dy),
    TTsScalar.WrappingSubI32(Right, Dx), TTsScalar.WrappingSubI32(Bottom, Dy), Inset);
end;

function TTsIntRect.TryMakeOutset(const Dx, Dy: Integer; out Outset: TTsIntRect): Boolean;
begin
  Result := TryFromLTRB(SaturatingSubInt32(Left, Dx), SaturatingSubInt32(Top, Dy),
    SaturatingAddInt32(Right, Dx), SaturatingAddInt32(Bottom, Dy), Outset);
end;

function TTsIntRect.TryTranslate(const Tx, Ty: Integer; out Translated: TTsIntRect): Boolean;
begin
  Result := TryFromXYWH(TTsScalar.WrappingAddI32(FX, Tx), TTsScalar.WrappingAddI32(FY, Ty), FWidth, FHeight, Translated);
end;

function TTsIntRect.TryTranslateTo(const NewX, NewY: Integer; out Translated: TTsIntRect): Boolean;
begin
  Result := TryFromXYWH(NewX, NewY, FWidth, FHeight, Translated);
end;

class operator TTsIntRect.Equal(const A, B: TTsIntRect): Boolean;
begin
  Result := ((A.FX = B.FX) and (A.FY = B.FY) and (A.FWidth = B.FWidth) and (A.FHeight = B.FHeight));
end;

class operator TTsIntRect.NotEqual(const A, B: TTsIntRect): Boolean;
begin
  Result := not (A = B);
end;

{ TTsRect }

class function TTsRect.TryFromLTRB(const Left, Top, Right, Bottom: Single; out Rect: TTsRect): Boolean;
begin
  Rect := Default(TTsRect);

  var FiniteLeft, FiniteTop, FiniteRight, FiniteBottom: TTsFiniteF32;
  const AllFinite = (TTsFiniteF32.TryCreate(Left, FiniteLeft) and TTsFiniteF32.TryCreate(Top, FiniteTop)
    and TTsFiniteF32.TryCreate(Right, FiniteRight) and TTsFiniteF32.TryCreate(Bottom, FiniteBottom));
  if not AllFinite then
  begin
    Exit(False);
  end;

  if (FiniteLeft.Get > FiniteRight.Get) or (FiniteTop.Get > FiniteBottom.Get) then
  begin
    Exit(False);
  end;

  // Width and height must not overflow.
  var Difference: Single;
  if not (TryCheckedF32Sub(FiniteRight.Get, FiniteLeft.Get, Difference) and TryCheckedF32Sub(FiniteBottom.Get, FiniteTop.Get, Difference)) then
  begin
    Exit(False);
  end;

  Rect.FLeft := FiniteLeft;
  Rect.FTop := FiniteTop;
  Rect.FRight := FiniteRight;
  Rect.FBottom := FiniteBottom;
  Result := True;
end;

class function TTsRect.TryFromXYWH(const X, Y, Width, Height: Single; out Rect: TTsRect): Boolean;
begin
  Result := TryFromLTRB(X, Y, Width + X, Height + Y, Rect);
end;

class function TTsRect.TryFromPoints(const Points: array of TTsPoint; out Rect: TTsRect): Boolean;
begin
  Rect := Default(TTsRect);

  var Offset := 0;
  var MinLanes := Default(TF32x4Path);
  var MaxLanes := Default(TF32x4Path);

  // Handle trivial-size lists without creating vectors, since they won't actually use the vector min/max code
  case System.Length(Points) of
    0:
      Exit(False);

    1:
      Exit(TryFromXYWH(Points[0].X, Points[0].Y, 0.0, 0.0, Rect));

    2:
    begin
      const X0 = Points[0].X;
      const Y0 = Points[0].Y;
      const X1 = Points[1].X;
      const Y1 = Points[1].Y;

      // Avoid min/max to preserve a NaN for rejection by TryFromLTRB
      var L, R, T, B: Single;
      if TTsLane.IsLt(X0, X1) then
      begin
        L := X0;
        R := X1;
      end
      else
      begin
        L := X1;
        R := X0;
      end;

      if TTsLane.IsLt(Y0, Y1) then
      begin
        T := Y0;
        B := Y1;
      end
      else
      begin
        T := Y1;
        B := Y0;
      end;

      Exit(TryFromLTRB(L, T, R, B, Rect));
    end;
  else
    if (System.Length(Points) and 1) <> 0 then
    begin
      const Pt = Points[0];

      MinLanes := TF32x4Path.Create(Pt.X, Pt.Y, Pt.X, Pt.Y);
      MaxLanes := MinLanes;
      Offset := 1;
    end
    else
    begin
      const Pt0 = Points[0];
      const Pt1 = Points[1];

      MinLanes := TF32x4Path.Create(Pt0.X, Pt0.Y, Pt1.X, Pt1.Y);
      MaxLanes := MinLanes;
      Offset := 2;
    end;
  end;

  var Accum := Default(TF32x4Path);
  while Offset <> System.Length(Points) do
  begin
    const Pt0 = Points[Offset];
    const Pt1 = Points[Offset + 1];
    const Xy = TF32x4Path.Create(Pt0.X, Pt0.Y, Pt1.X, Pt1.Y);

    Accum := Accum * Xy;
    MinLanes := MinLanes.Min(Xy);
    MaxLanes := MaxLanes.Max(Xy);
    Offset := Offset + 2;
  end;

  const AllFinite = ((Accum * Default(TF32x4Path)) = Default(TF32x4Path));
  if not AllFinite then
  begin
    Exit(False);
  end;

  Result := TryFromLTRB(TTsScalar.MinF(MinLanes.Lanes[0], MinLanes.Lanes[2]), TTsScalar.MinF(MinLanes.Lanes[1], MinLanes.Lanes[3]),
    TTsScalar.MaxF(MaxLanes.Lanes[0], MaxLanes.Lanes[2]), TTsScalar.MaxF(MaxLanes.Lanes[1], MaxLanes.Lanes[3]), Rect);
end;

function TTsRect.Left: Single;
begin
  Result := FLeft.Get;
end;

function TTsRect.Top: Single;
begin
  Result := FTop.Get;
end;

function TTsRect.Right: Single;
begin
  Result := FRight.Get;
end;

function TTsRect.Bottom: Single;
begin
  Result := FBottom.Get;
end;

function TTsRect.X: Single;
begin
  Result := FLeft.Get;
end;

function TTsRect.Y: Single;
begin
  Result := FTop.Get;
end;

function TTsRect.Width: Single;
begin
  Result := FRight.Get - FLeft.Get;
end;

function TTsRect.Height: Single;
begin
  Result := FBottom.Get - FTop.Get;
end;

function TTsRect.IsEmpty: Boolean;
begin
  Result := ((FLeft.Get = FRight.Get) or (FTop.Get = FBottom.Get));
end;

function TTsRect.TryRound(out Rounded: TTsIntRect): Boolean;
begin
  const RoundedLeft = TTsScalar.SaturateRound(Left);
  const RoundedTop = TTsScalar.SaturateRound(Top);
  const RoundedRight = TTsScalar.SaturateRound(Right);
  const RoundedBottom = TTsScalar.SaturateRound(Bottom);

  Result := TTsIntRect.TryFromXYWH(RoundedLeft, RoundedTop, Cardinal(Max(1, SaturatingSubInt32(RoundedRight, RoundedLeft))),
    Cardinal(Max(1, SaturatingSubInt32(RoundedBottom, RoundedTop))), Rounded);
end;

function TTsRect.TryRoundOut(out Rounded: TTsIntRect): Boolean;
begin
  const RoundedLeft = TTsScalar.SaturateFloor(Left);
  const RoundedTop = TTsScalar.SaturateFloor(Top);
  const RoundedRight = TTsScalar.SaturateCeil(Right);
  const RoundedBottom = TTsScalar.SaturateCeil(Bottom);

  Result := TTsIntRect.TryFromXYWH(RoundedLeft, RoundedTop, Cardinal(Max(1, SaturatingSubInt32(RoundedRight, RoundedLeft))),
    Cardinal(Max(1, SaturatingSubInt32(RoundedBottom, RoundedTop))), Rounded);
end;

function TTsRect.TryIntersect(const Other: TTsRect; out Intersection: TTsRect): Boolean;
begin
  const IntersectLeft = TTsScalar.MaxF(X, Other.X);
  const IntersectTop = TTsScalar.MaxF(Y, Other.Y);

  const IntersectRight = TTsScalar.MinF(Right, Other.Right);
  const IntersectBottom = TTsScalar.MinF(Bottom, Other.Bottom);

  Result := TryFromLTRB(IntersectLeft, IntersectTop, IntersectRight, IntersectBottom, Intersection);
end;

function TTsRect.TryJoin(const Other: TTsRect; out Joined: TTsRect): Boolean;
begin
  if Other.IsEmpty then
  begin
    Joined := Self;

    Exit(True);
  end;

  if IsEmpty then
  begin
    Joined := Other;

    Exit(True);
  end;

  const JoinLeft = TTsScalar.MinF(X, Other.X);
  const JoinTop = TTsScalar.MinF(Y, Other.Y);

  const JoinRight = TTsScalar.MaxF(Right, Other.Right);
  const JoinBottom = TTsScalar.MaxF(Bottom, Other.Bottom);

  Result := TryFromLTRB(JoinLeft, JoinTop, JoinRight, JoinBottom, Joined);
end;

function TTsRect.TryInset(const Dx, Dy: Single; out Inset: TTsRect): Boolean;
begin
  Result := TryFromLTRB(Left + Dx, Top + Dy, Right - Dx, Bottom - Dy, Inset);
end;

function TTsRect.TryOutset(const Dx, Dy: Single; out Outset: TTsRect): Boolean;
begin
  Result := TryInset(-Dx, -Dy, Outset);
end;

class operator TTsRect.Equal(const A, B: TTsRect): Boolean;
begin
  Result := ((A.Left = B.Left) and (A.Top = B.Top) and (A.Right = B.Right) and (A.Bottom = B.Bottom));
end;

class operator TTsRect.NotEqual(const A, B: TTsRect): Boolean;
begin
  Result := not (A = B);
end;

{ TTsNonZeroRect }

class function TTsNonZeroRect.TryFromLTRB(const Left, Top, Right, Bottom: Single; out Rect: TTsNonZeroRect): Boolean;
begin
  Rect := Default(TTsNonZeroRect);

  var FiniteLeft, FiniteTop, FiniteRight, FiniteBottom: TTsFiniteF32;
  const AllFinite = (TTsFiniteF32.TryCreate(Left, FiniteLeft) and TTsFiniteF32.TryCreate(Top, FiniteTop)
    and TTsFiniteF32.TryCreate(Right, FiniteRight) and TTsFiniteF32.TryCreate(Bottom, FiniteBottom));
  if not AllFinite then
  begin
    Exit(False);
  end;

  if (FiniteLeft.Get >= FiniteRight.Get) or (FiniteTop.Get >= FiniteBottom.Get) then
  begin
    Exit(False);
  end;

  // Width and height must not overflow.
  var Difference: Single;
  if not (TryCheckedF32Sub(FiniteRight.Get, FiniteLeft.Get, Difference) and TryCheckedF32Sub(FiniteBottom.Get, FiniteTop.Get, Difference)) then
  begin
    Exit(False);
  end;

  Rect.FLeft := FiniteLeft;
  Rect.FTop := FiniteTop;
  Rect.FRight := FiniteRight;
  Rect.FBottom := FiniteBottom;
  Result := True;
end;

class function TTsNonZeroRect.TryFromXYWH(const X, Y, Width, Height: Single; out Rect: TTsNonZeroRect): Boolean;
begin
  Result := TryFromLTRB(X, Y, Width + X, Height + Y, Rect);
end;

function TTsNonZeroRect.Left: Single;
begin
  Result := FLeft.Get;
end;

function TTsNonZeroRect.Top: Single;
begin
  Result := FTop.Get;
end;

function TTsNonZeroRect.Right: Single;
begin
  Result := FRight.Get;
end;

function TTsNonZeroRect.Bottom: Single;
begin
  Result := FBottom.Get;
end;

function TTsNonZeroRect.X: Single;
begin
  Result := FLeft.Get;
end;

function TTsNonZeroRect.Y: Single;
begin
  Result := FTop.Get;
end;

function TTsNonZeroRect.Width: Single;
begin
  Result := FRight.Get - FLeft.Get;
end;

function TTsNonZeroRect.Height: Single;
begin
  Result := FBottom.Get - FTop.Get;
end;

function TTsNonZeroRect.Size: TTsSize;
begin
  if not TTsSize.TryFromWH(Width, Height, Result) then
  begin
    RaiseUnwrapFailed('Size.from_wh');
  end;
end;

function TTsNonZeroRect.TryTranslateTo(const NewX, NewY: Single; out Translated: TTsNonZeroRect): Boolean;
begin
  Result := TryFromXYWH(NewX, NewY, Width, Height, Translated);
end;

function TTsNonZeroRect.ToRect: TTsRect;
begin
  if not TTsRect.TryFromXYWH(X, Y, Width, Height, Result) then
  begin
    RaiseUnwrapFailed('Rect.from_xywh');
  end;
end;

function TTsNonZeroRect.ToIntRect: TTsIntRect;
begin
  const FlooredX = TTsScalar.SaturateToInt32(TTsScalar.FloorF(X));
  const FlooredY = TTsScalar.SaturateToInt32(TTsScalar.FloorF(Y));
  const CeiledWidth = SaturateToUInt32(TTsScalar.CeilF(Width));
  const CeiledHeight = SaturateToUInt32(TTsScalar.CeilF(Height));

  if not TTsIntRect.TryFromXYWH(FlooredX, FlooredY, Max(Cardinal(1), CeiledWidth), Max(Cardinal(1), CeiledHeight), Result) then
  begin
    RaiseUnwrapFailed('IntRect.from_xywh');
  end;
end;

class operator TTsNonZeroRect.Equal(const A, B: TTsNonZeroRect): Boolean;
begin
  Result := ((A.Left = B.Left) and (A.Top = B.Top) and (A.Right = B.Right) and (A.Bottom = B.Bottom));
end;

class operator TTsNonZeroRect.NotEqual(const A, B: TTsNonZeroRect): Boolean;
begin
  Result := not (A = B);
end;

{ TTsScreenIntRect }

class function TTsScreenIntRect.TryFromXYWH(const X, Y, Width, Height: Cardinal; out Rect: TTsScreenIntRect): Boolean;
begin
  Rect := Default(TTsScreenIntRect);

  // i32::try_from of every value, then checked_add of u32
  const FitsInt32 = ((X <= MaxInt32AsCardinal) and (Y <= MaxInt32AsCardinal) and (Width <= MaxInt32AsCardinal) and (Height <= MaxInt32AsCardinal));
  if not FitsInt32 then
  begin
    Exit(False);
  end;

  const NoOverflow = ((Int64(X) + Int64(Width) <= High(Cardinal)) and (Int64(Y) + Int64(Height) <= High(Cardinal)));
  if not NoOverflow then
  begin
    Exit(False);
  end;

  Result := ((Width <> 0) and (Height <> 0));
  if Result then
  begin
    Rect.FX := X;
    Rect.FY := Y;
    Rect.FWidth := Width;
    Rect.FHeight := Height;
  end;
end;

class function TTsScreenIntRect.FromXYWHSafe(const X, Y, Width, Height: Cardinal): TTsScreenIntRect;
begin
  Result.FX := X;
  Result.FY := Y;
  Result.FWidth := Width;
  Result.FHeight := Height;
end;

function TTsScreenIntRect.X: Cardinal;
begin
  Result := FX;
end;

function TTsScreenIntRect.Y: Cardinal;
begin
  Result := FY;
end;

function TTsScreenIntRect.Width: Cardinal;
begin
  Result := FWidth;
end;

function TTsScreenIntRect.Height: Cardinal;
begin
  Result := FHeight;
end;

function TTsScreenIntRect.WidthSafe: Cardinal;
begin
  Result := FWidth;
end;

function TTsScreenIntRect.Left: Cardinal;
begin
  Result := FX;
end;

function TTsScreenIntRect.Top: Cardinal;
begin
  Result := FY;
end;

function TTsScreenIntRect.Right: Cardinal;
begin
  // No overflow is guaranteed by constructors.
  Result := FX + FWidth;
end;

function TTsScreenIntRect.Bottom: Cardinal;
begin
  // No overflow is guaranteed by constructors.
  Result := FY + FHeight;
end;

function TTsScreenIntRect.Size: TTsIntSize;
begin
  if not TTsIntSize.TryFromWH(Width, Height, Result) then
  begin
    RaiseUnwrapFailed('IntSize.from_wh');
  end;
end;

function TTsScreenIntRect.Contains(const Other: TTsScreenIntRect): Boolean;
begin
  Result := ((FX <= Other.FX) and (FY <= Other.FY) and (Right >= Other.Right) and (Bottom >= Other.Bottom));
end;

function TTsScreenIntRect.ToIntRect: TTsIntRect;
begin
  // Everything is already checked by constructors, except that x + width can exceed i32::MAX, which makes the Rust unwrap panic.
  if not TTsIntRect.TryFromXYWH(Integer(FX), Integer(FY), FWidth, FHeight, Result) then
  begin
    RaiseUnwrapFailed('IntRect.from_xywh');
  end;
end;

function TTsScreenIntRect.ToRect: TTsRect;
begin
  const FloatX = UInt32ToSingle(FX);
  const FloatY = UInt32ToSingle(FY);

  // Can't fail, because ScreenIntRect is always valid. And u32 always fits into f32.
  if not TTsRect.TryFromLTRB(FloatX, FloatY, FloatX + UInt32ToSingle(FWidth), FloatY + UInt32ToSingle(FHeight), Result) then
  begin
    RaiseUnwrapFailed('Rect.from_ltrb');
  end;
end;

class operator TTsScreenIntRect.Equal(const A, B: TTsScreenIntRect): Boolean;
begin
  Result := ((A.FX = B.FX) and (A.FY = B.FY) and (A.FWidth = B.FWidth) and (A.FHeight = B.FHeight));
end;

class operator TTsScreenIntRect.NotEqual(const A, B: TTsScreenIntRect): Boolean;
begin
  Result := not (A = B);
end;

{ TTsIntSizeConversions }

function TTsIntSizeConversions.ToSize: TTsSize;
begin
  if not TTsSize.TryFromWH(UInt32ToSingle(Width), UInt32ToSingle(Height), Result) then
  begin
    RaiseUnwrapFailed('Size.from_wh');
  end;
end;

function TTsIntSizeConversions.ToIntRect(const X, Y: Integer): TTsIntRect;
begin
  if not TTsIntRect.TryFromXYWH(X, Y, Width, Height, Result) then
  begin
    RaiseUnwrapFailed('IntRect.from_xywh');
  end;
end;

function TTsIntSizeConversions.ToScreenIntRect(const X, Y: Cardinal): TTsScreenIntRect;
begin
  if not TTsScreenIntRect.TryFromXYWH(X, Y, Width, Height, Result) then
  begin
    RaiseUnwrapFailed('ScreenIntRect.from_xywh');
  end;
end;

{ TTsSizeConversions }

function TTsSizeConversions.TryToRect(const X, Y: Single; out Rect: TTsRect): Boolean;
begin
  Result := TTsRect.TryFromXYWH(X, Y, Width, Height, Rect);
end;

function TTsSizeConversions.ToNonZeroRect(const X, Y: Single): TTsNonZeroRect;
begin
  if not TTsNonZeroRect.TryFromXYWH(X, Y, Width, Height, Result) then
  begin
    RaiseUnwrapFailed('NonZeroRect.from_xywh');
  end;
end;

{ TTsIntRectConversions }

function TTsIntRectConversions.ToRect: TTsRect;
begin
  const FloatX = Single(X);
  const FloatY = Single(Y);

  // Can't fail, because IntRect is always valid.
  if not TTsRect.TryFromLTRB(FloatX, FloatY, FloatX + UInt32ToSingle(Width), FloatY + UInt32ToSingle(Height), Result) then
  begin
    RaiseUnwrapFailed('Rect.from_ltrb');
  end;
end;

function TTsIntRectConversions.TryToScreenIntRect(out Rect: TTsScreenIntRect): Boolean;
begin
  Rect := Default(TTsScreenIntRect);

  if (X < 0) or (Y < 0) then
  begin
    Exit(False);
  end;

  Result := TTsScreenIntRect.TryFromXYWH(Cardinal(X), Cardinal(Y), Width, Height, Rect);
end;

end.
