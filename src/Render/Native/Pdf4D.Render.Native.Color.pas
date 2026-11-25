// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: tiny-skia v0.12.0 src/color.rs (ColorSpace::Linear only)
// Copyright (c) 2006 The Android Open Source Project, (c) 2020 Yevhenii Reizner. BSD-3-Clause, see licenses/tiny-skia-BSD-3-Clause.txt.
unit Pdf4D.Render.Native.Color;

{$EXCESSPRECISION OFF}

interface

uses
  System.Math,
  Pdf4D.Render.Native.Scalar;

// The 8-bit colors are four bytes in the order R, G, B, A and have the size of four bytes, like the pixels of TPdfBitmap and the arrays of
// the Rust code that are cast to bytes. A record cannot refer to a record declared later, so ColorU8.premultiply and Color.premultiply are
// record helpers that follow the records they convert to; they are called as methods of the color as in Rust.
//
// Only ColorSpace::Linear is ported: expand_channel, expand_color, compress_channel and the gamma stages of the other color spaces are not.
// Linear gives no stage, so a color space type has no use here.

const
  // 8-bit type for an alpha value. 255 is 100% opaque, zero is 100% transparent.
  AlphaU8Transparent = $00;
  AlphaU8Opaque = $FF;

type
  // A 32-bit RGBA color value
  TTsColorU8 = record
  private
    FRed: Byte;
    FGreen: Byte;
    FBlue: Byte;
    FAlpha: Byte;

  public
    class function FromRgba(const R, G, B, A: Byte): TTsColorU8; static;

    function Red: Byte;
    function Green: Byte;
    function Blue: Byte;
    function Alpha: Byte;

    // Alpha = 255
    function IsOpaque: Boolean;

    class operator Equal(const A, B: TTsColorU8): Boolean;
    class operator NotEqual(const A, B: TTsColorU8): Boolean;
  end;

  // A 32-bit premultiplied RGBA color value: the components of RGB are at most the alpha
  TTsPremultipliedColorU8 = record
  private
    FRed: Byte;
    FGreen: Byte;
    FBlue: Byte;
    FAlpha: Byte;

  public
    class function Transparent: TTsPremultipliedColorU8; static;

    // RGB components must be <= alpha
    class function TryFromRgba(const R, G, B, A: Byte; out Color: TTsPremultipliedColorU8): Boolean; static;
    class function FromRgbaUnchecked(const R, G, B, A: Byte): TTsPremultipliedColorU8; static;

    function Red: Byte;
    function Green: Byte;
    function Blue: Byte;
    function Alpha: Byte;

    // Alpha = 255
    function IsOpaque: Boolean;
    function Demultiply: TTsColorU8;

    class operator Equal(const A, B: TTsPremultipliedColorU8): Boolean;
    class operator NotEqual(const A, B: TTsPremultipliedColorU8): Boolean;
  end;

  // ColorU8::premultiply
  TTsColorU8Conversions = record helper for TTsColorU8
    function Premultiply: TTsPremultipliedColorU8;
  end;

  // An RGBA color value of four Singles, all in 0..1
  TTsColor = record
  private
    FRed: TTsNormalizedF32;
    FGreen: TTsNormalizedF32;
    FBlue: TTsNormalizedF32;
    FAlpha: TTsNormalizedF32;

  public
    class function Transparent: TTsColor; static;
    class function Black: TTsColor; static;
    class function White: TTsColor; static;

    // All values must be in 0..=1
    class function FromRgbaUnchecked(const R, G, B, A: Single): TTsColor; static;
    class function TryFromRgba(const R, G, B, A: Single; out Color: TTsColor): Boolean; static;

    // Each u8 is divided by 255 to get the float component
    class function FromRgba8(const R, G, B, A: Byte): TTsColor; static;

    function Red: Single;
    function Green: Single;
    function Blue: Single;
    function Alpha: Single;

    // The new value is clipped to the 0..=1 range
    procedure SetRed(const C: Single);
    procedure SetGreen(const C: Single);
    procedure SetBlue(const C: Single);
    procedure SetAlpha(const C: Single);

    // Multiplies the alpha by the opacity, which is clamped to 0..=1 first; the final alpha is clamped too
    procedure ApplyOpacity(const Opacity: Single);

    // Alpha = 1
    function IsOpaque: Boolean;
    function ToColorU8: TTsColorU8;

    class operator Equal(const A, B: TTsColor): Boolean;
    class operator NotEqual(const A, B: TTsColor): Boolean;
  end;

  // A premultiplied color of four Singles, all in 0..1 and with RGB at most the alpha
  TTsPremultipliedColor = record
  private
    FRed: TTsNormalizedF32;
    FGreen: TTsNormalizedF32;
    FBlue: TTsNormalizedF32;
    FAlpha: TTsNormalizedF32;

  public
    function Red: Single;
    function Green: Single;
    function Blue: Single;
    function Alpha: Single;

    function Demultiply: TTsColor;
    function ToColorU8: TTsPremultipliedColorU8;

    class operator Equal(const A, B: TTsPremultipliedColor): Boolean;
    class operator NotEqual(const A, B: TTsPremultipliedColor): Boolean;
  end;

  // Color::premultiply
  TTsColorConversions = record helper for TTsColor
    function Premultiply: TTsPremultipliedColor;
  end;

  TTsColorMath = record
  private
    class function ScaleChannel(const Channel, Alpha: TTsNormalizedF32): TTsNormalizedF32; static;
    class function DemultiplyChannelU8(const Channel, Alpha: Byte): Byte; static;
    class function SaturateDoubleToU8(const Value: Double): Byte; static;
    class function ChannelToU8(const Channel: TTsNormalizedF32): Byte; static;

  public
    // a * b / 255, rounding any fractional bits
    class function PremultiplyU8(const C, A: Byte): Byte; static;
  end;

implementation

const
  Scale255: Single = 255.0;
  HalfSingle: Single = 0.5;
  Scale255Double: Double = 255.0;
  HalfDouble: Double = 0.5;

{ TTsColorU8 }

class function TTsColorU8.FromRgba(const R, G, B, A: Byte): TTsColorU8;
begin
  Result.FRed := R;
  Result.FGreen := G;
  Result.FBlue := B;
  Result.FAlpha := A;
end;

function TTsColorU8.Red: Byte;
begin
  Result := FRed;
end;

function TTsColorU8.Green: Byte;
begin
  Result := FGreen;
end;

function TTsColorU8.Blue: Byte;
begin
  Result := FBlue;
end;

function TTsColorU8.Alpha: Byte;
begin
  Result := FAlpha;
end;

function TTsColorU8.IsOpaque: Boolean;
begin
  Result := (FAlpha = AlphaU8Opaque);
end;

class operator TTsColorU8.Equal(const A, B: TTsColorU8): Boolean;
begin
  Result := ((A.FRed = B.FRed) and (A.FGreen = B.FGreen) and (A.FBlue = B.FBlue) and (A.FAlpha = B.FAlpha));
end;

class operator TTsColorU8.NotEqual(const A, B: TTsColorU8): Boolean;
begin
  Result := not (A = B);
end;

{ TTsPremultipliedColorU8 }

class function TTsPremultipliedColorU8.Transparent: TTsPremultipliedColorU8;
begin
  Result := FromRgbaUnchecked(0, 0, 0, 0);
end;

class function TTsPremultipliedColorU8.TryFromRgba(const R, G, B, A: Byte; out Color: TTsPremultipliedColorU8): Boolean;
begin
  Color := Default(TTsPremultipliedColorU8);

  const ComponentsFitTheAlpha = ((R <= A) and (G <= A) and (B <= A));
  if not ComponentsFitTheAlpha then
  begin
    Exit(False);
  end;

  Color := FromRgbaUnchecked(R, G, B, A);
  Result := True;
end;

class function TTsPremultipliedColorU8.FromRgbaUnchecked(const R, G, B, A: Byte): TTsPremultipliedColorU8;
begin
  Result.FRed := R;
  Result.FGreen := G;
  Result.FBlue := B;
  Result.FAlpha := A;
end;

function TTsPremultipliedColorU8.Red: Byte;
begin
  Result := FRed;
end;

function TTsPremultipliedColorU8.Green: Byte;
begin
  Result := FGreen;
end;

function TTsPremultipliedColorU8.Blue: Byte;
begin
  Result := FBlue;
end;

function TTsPremultipliedColorU8.Alpha: Byte;
begin
  Result := FAlpha;
end;

function TTsPremultipliedColorU8.IsOpaque: Boolean;
begin
  Result := (FAlpha = AlphaU8Opaque);
end;

function TTsPremultipliedColorU8.Demultiply: TTsColorU8;
begin
  if IsOpaque then
  begin
    Exit(TTsColorU8.FromRgba(FRed, FGreen, FBlue, FAlpha));
  end;

  Result := TTsColorU8.FromRgba(TTsColorMath.DemultiplyChannelU8(FRed, FAlpha),
                                TTsColorMath.DemultiplyChannelU8(FGreen, FAlpha),
                                TTsColorMath.DemultiplyChannelU8(FBlue, FAlpha),
                                FAlpha);
end;

class operator TTsPremultipliedColorU8.Equal(const A, B: TTsPremultipliedColorU8): Boolean;
begin
  Result := ((A.FRed = B.FRed) and (A.FGreen = B.FGreen) and (A.FBlue = B.FBlue) and (A.FAlpha = B.FAlpha));
end;

class operator TTsPremultipliedColorU8.NotEqual(const A, B: TTsPremultipliedColorU8): Boolean;
begin
  Result := not (A = B);
end;

{ TTsColorU8Conversions }

function TTsColorU8Conversions.Premultiply: TTsPremultipliedColorU8;
begin
  if IsOpaque then
  begin
    Exit(TTsPremultipliedColorU8.FromRgbaUnchecked(Red, Green, Blue, Alpha));
  end;

  Result := TTsPremultipliedColorU8.FromRgbaUnchecked(TTsColorMath.PremultiplyU8(Red, Alpha),
                                                      TTsColorMath.PremultiplyU8(Green, Alpha),
                                                      TTsColorMath.PremultiplyU8(Blue, Alpha),
                                                      Alpha);
end;

{ TTsColor }

class function TTsColor.Transparent: TTsColor;
begin
  Result := FromRgbaUnchecked(0, 0, 0, 0);
end;

class function TTsColor.Black: TTsColor;
begin
  Result := FromRgbaUnchecked(0, 0, 0, 1);
end;

class function TTsColor.White: TTsColor;
begin
  Result := FromRgbaUnchecked(1, 1, 1, 1);
end;

class function TTsColor.FromRgbaUnchecked(const R, G, B, A: Single): TTsColor;
begin
  Result.FRed := TTsNormalizedF32.CreateUnchecked(R);
  Result.FGreen := TTsNormalizedF32.CreateUnchecked(G);
  Result.FBlue := TTsNormalizedF32.CreateUnchecked(B);
  Result.FAlpha := TTsNormalizedF32.CreateUnchecked(A);
end;

class function TTsColor.TryFromRgba(const R, G, B, A: Single; out Color: TTsColor): Boolean;
begin
  Color := Default(TTsColor);

  var Red, Green, Blue, Alpha: TTsNormalizedF32;
  const AllInRange = (TTsNormalizedF32.TryCreate(R, Red) and
                      TTsNormalizedF32.TryCreate(G, Green) and
                      TTsNormalizedF32.TryCreate(B, Blue) and
                      TTsNormalizedF32.TryCreate(A, Alpha));
  if not AllInRange then
  begin
    Exit(False);
  end;

  Color.FRed := Red;
  Color.FGreen := Green;
  Color.FBlue := Blue;
  Color.FAlpha := Alpha;
  Result := True;
end;

class function TTsColor.FromRgba8(const R, G, B, A: Byte): TTsColor;
begin
  Result.FRed := TTsNormalizedF32.CreateU8(R);
  Result.FGreen := TTsNormalizedF32.CreateU8(G);
  Result.FBlue := TTsNormalizedF32.CreateU8(B);
  Result.FAlpha := TTsNormalizedF32.CreateU8(A);
end;

function TTsColor.Red: Single;
begin
  Result := FRed.Get;
end;

function TTsColor.Green: Single;
begin
  Result := FGreen.Get;
end;

function TTsColor.Blue: Single;
begin
  Result := FBlue.Get;
end;

function TTsColor.Alpha: Single;
begin
  Result := FAlpha.Get;
end;

procedure TTsColor.SetRed(const C: Single);
begin
  FRed := TTsNormalizedF32.CreateClamped(C);
end;

procedure TTsColor.SetGreen(const C: Single);
begin
  FGreen := TTsNormalizedF32.CreateClamped(C);
end;

procedure TTsColor.SetBlue(const C: Single);
begin
  FBlue := TTsNormalizedF32.CreateClamped(C);
end;

procedure TTsColor.SetAlpha(const C: Single);
begin
  FAlpha := TTsNormalizedF32.CreateClamped(C);
end;

procedure TTsColor.ApplyOpacity(const Opacity: Single);
begin
  const BoundedOpacity: Single = TTsScalar.Bound(Opacity, 0, 1);
  const Scaled: Single = FAlpha.Get * BoundedOpacity;

  FAlpha := TTsNormalizedF32.CreateClamped(Scaled);
end;

function TTsColor.IsOpaque: Boolean;
begin
  Result := (FAlpha.Get = 1);
end;

function TTsColor.ToColorU8: TTsColorU8;
begin
  Result := TTsColorU8.FromRgba(TTsColorMath.ChannelToU8(FRed),
                                TTsColorMath.ChannelToU8(FGreen),
                                TTsColorMath.ChannelToU8(FBlue),
                                TTsColorMath.ChannelToU8(FAlpha));
end;

class operator TTsColor.Equal(const A, B: TTsColor): Boolean;
begin
  Result := ((A.FRed.Get = B.FRed.Get) and (A.FGreen.Get = B.FGreen.Get) and (A.FBlue.Get = B.FBlue.Get) and (A.FAlpha.Get = B.FAlpha.Get));
end;

class operator TTsColor.NotEqual(const A, B: TTsColor): Boolean;
begin
  Result := not (A = B);
end;

{ TTsPremultipliedColor }

function TTsPremultipliedColor.Red: Single;
begin
  Result := FRed.Get;
end;

function TTsPremultipliedColor.Green: Single;
begin
  Result := FGreen.Get;
end;

function TTsPremultipliedColor.Blue: Single;
begin
  Result := FBlue.Get;
end;

function TTsPremultipliedColor.Alpha: Single;
begin
  Result := FAlpha.Get;
end;

function TTsPremultipliedColor.Demultiply: TTsColor;
begin
  const AlphaValue: Single = FAlpha.Get;
  if AlphaValue = 0 then
  begin
    Exit(TTsColor.Transparent);
  end;

  const RedValue: Single = FRed.Get / AlphaValue;
  const GreenValue: Single = FGreen.Get / AlphaValue;
  const BlueValue: Single = FBlue.Get / AlphaValue;

  Result.FRed := TTsNormalizedF32.CreateClamped(RedValue);
  Result.FGreen := TTsNormalizedF32.CreateClamped(GreenValue);
  Result.FBlue := TTsNormalizedF32.CreateClamped(BlueValue);
  Result.FAlpha := FAlpha;
end;

function TTsPremultipliedColor.ToColorU8: TTsPremultipliedColorU8;
begin
  Result := TTsPremultipliedColorU8.FromRgbaUnchecked(TTsColorMath.ChannelToU8(FRed),
                                                      TTsColorMath.ChannelToU8(FGreen),
                                                      TTsColorMath.ChannelToU8(FBlue),
                                                      TTsColorMath.ChannelToU8(FAlpha));
end;

class operator TTsPremultipliedColor.Equal(const A, B: TTsPremultipliedColor): Boolean;
begin
  Result := ((A.FRed.Get = B.FRed.Get) and (A.FGreen.Get = B.FGreen.Get) and (A.FBlue.Get = B.FBlue.Get) and (A.FAlpha.Get = B.FAlpha.Get));
end;

class operator TTsPremultipliedColor.NotEqual(const A, B: TTsPremultipliedColor): Boolean;
begin
  Result := not (A = B);
end;

{ TTsColorConversions }

function TTsColorConversions.Premultiply: TTsPremultipliedColor;
begin
  if IsOpaque then
  begin
    Result.FRed := FRed;
    Result.FGreen := FGreen;
    Result.FBlue := FBlue;
    Result.FAlpha := FAlpha;
    Exit;
  end;

  Result.FRed := TTsColorMath.ScaleChannel(FRed, FAlpha);
  Result.FGreen := TTsColorMath.ScaleChannel(FGreen, FAlpha);
  Result.FBlue := TTsColorMath.ScaleChannel(FBlue, FAlpha);
  Result.FAlpha := FAlpha;
end;

{ TTsColorMath }

class function TTsColorMath.ScaleChannel(const Channel, Alpha: TTsNormalizedF32): TTsNormalizedF32;
begin
  const Scaled: Single = Channel.Get * Alpha.Get;

  Result := TTsNormalizedF32.CreateClamped(Scaled);
end;

class function TTsColorMath.DemultiplyChannelU8(const Channel, Alpha: Byte): Byte;
begin
  // The division by an alpha of zero gives NaN for a zero channel and infinity otherwise; both saturate as the `as u8` of Rust does
  if Alpha = 0 then
  begin
    if Channel = 0 then
    begin
      Exit(0);
    end;

    Exit(255);
  end;

  const AlphaFraction: Double = Double(Alpha) / Scale255Double;
  const Divided: Double = Double(Channel) / AlphaFraction;
  const Rounded: Double = Divided + HalfDouble;

  Result := SaturateDoubleToU8(Rounded);
end;

class function TTsColorMath.SaturateDoubleToU8(const Value: Double): Byte;
begin
  if IsNan(Value) or (Value <= 0) then
  begin
    Exit(0);
  end;

  if Value >= 255 then
  begin
    Exit(255);
  end;

  Result := Byte(Trunc(Value));
end;

class function TTsColorMath.ChannelToU8(const Channel: TTsNormalizedF32): Byte;
begin
  const Scaled: Single = Channel.Get * Scale255;
  const Rounded: Single = Scaled + HalfSingle;

  Result := Byte(TTsScalar.BoundInt(0, TTsScalar.SaturateToInt32(Rounded), 255));
end;

class function TTsColorMath.PremultiplyU8(const C, A: Byte): Byte;
begin
  const Product: Cardinal = Cardinal(C) * Cardinal(A) + 128;

  Result := Byte((Product + (Product shr 8)) shr 8);
end;

end.
