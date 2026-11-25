// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of tiny-skia v0.12.0 src/color.rs (inline tests), and of the colors around them
unit Pdf4D.Render.Native.Color.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Color;

type
  [TestFixture]
  TTsColorTests = class
  private
    procedure AssertColorU8(const Expected, Actual: TTsPremultipliedColorU8); overload;
    procedure AssertColorU8(const Expected, Actual: TTsColorU8); overload;

  public
    [Test]
    procedure TestPremultiplyU8Color;

    [Test]
    procedure TestPremultiplyU8Opaque;

    [Test]
    procedure TestDemultiplyU8First;

    [Test]
    procedure TestDemultiplyU8Opaque;

    [Test]
    procedure TestDemultiplyU8Third;

    [Test]
    procedure TestBytemuckCastsRgba;

    [Test]
    [TestCase('Half', '255,128,128')]
    [TestCase('Third', '100,128,50')]
    [TestCase('ZeroColor', '0,255,0')]
    [TestCase('ZeroAlpha', '255,0,0')]
    procedure TestPremultiplyU8(const Color, Alpha, Expected: Integer);

    [Test]
    procedure TestDemultiplyU8OfTransparentSaturates;

    [Test]
    procedure TestPremultipliedColorU8FromRgbaChecksTheAlpha;

    [Test]
    procedure TestColorFromRgbaRejectsOutOfRange;

    [Test]
    procedure TestColorFromRgba8DividesBy255;

    [Test]
    procedure TestColorSettersClamp;

    [Test]
    procedure TestApplyOpacityClampsOpacityAndResult;

    [Test]
    procedure TestColorPremultiplyScalesTheChannels;

    [Test]
    procedure TestColorPremultiplyOpaqueKeepsTheChannels;

    [Test]
    procedure TestColorToColorU8Rounds;

    [Test]
    procedure TestPremultipliedColorDemultiply;

    [Test]
    procedure TestPremultipliedColorToColorU8;
  end;

implementation

{ TTsColorTests }

procedure TTsColorTests.AssertColorU8(const Expected, Actual: TTsPremultipliedColorU8);
begin
  Assert.AreEqual(Integer(Expected.Red), Integer(Actual.Red), 'red');
  Assert.AreEqual(Integer(Expected.Green), Integer(Actual.Green), 'green');
  Assert.AreEqual(Integer(Expected.Blue), Integer(Actual.Blue), 'blue');
  Assert.AreEqual(Integer(Expected.Alpha), Integer(Actual.Alpha), 'alpha');
end;

procedure TTsColorTests.AssertColorU8(const Expected, Actual: TTsColorU8);
begin
  Assert.AreEqual(Integer(Expected.Red), Integer(Actual.Red), 'red');
  Assert.AreEqual(Integer(Expected.Green), Integer(Actual.Green), 'green');
  Assert.AreEqual(Integer(Expected.Blue), Integer(Actual.Blue), 'blue');
  Assert.AreEqual(Integer(Expected.Alpha), Integer(Actual.Alpha), 'alpha');
end;

procedure TTsColorTests.TestPremultiplyU8Color;
begin
  const Expected = TTsPremultipliedColorU8.FromRgbaUnchecked(2, 3, 5, 40);

  const Actual = TTsColorU8.FromRgba(10, 20, 30, 40).Premultiply;

  AssertColorU8(Expected, Actual);
end;

procedure TTsColorTests.TestPremultiplyU8Opaque;
begin
  const Expected = TTsPremultipliedColorU8.FromRgbaUnchecked(10, 20, 30, 255);

  const Actual = TTsColorU8.FromRgba(10, 20, 30, 255).Premultiply;

  AssertColorU8(Expected, Actual);
end;

procedure TTsColorTests.TestDemultiplyU8First;
begin
  const Expected = TTsColorU8.FromRgba(13, 19, 32, 40);

  const Actual = TTsPremultipliedColorU8.FromRgbaUnchecked(2, 3, 5, 40).Demultiply;

  AssertColorU8(Expected, Actual);
end;

procedure TTsColorTests.TestDemultiplyU8Opaque;
begin
  const Expected = TTsColorU8.FromRgba(10, 20, 30, 255);

  const Actual = TTsPremultipliedColorU8.FromRgbaUnchecked(10, 20, 30, 255).Demultiply;

  AssertColorU8(Expected, Actual);
end;

procedure TTsColorTests.TestDemultiplyU8Third;
begin
  const Expected = TTsColorU8.FromRgba(217, 140, 77, 180);

  const Actual = TTsPremultipliedColorU8.FromRgbaUnchecked(153, 99, 54, 180).Demultiply;

  AssertColorU8(Expected, Actual);
end;

procedure TTsColorTests.TestBytemuckCastsRgba;
begin
  const Pixels: TArray<TTsPremultipliedColorU8> = [TTsPremultipliedColorU8.FromRgbaUnchecked(0, 1, 2, 3),
                                                   TTsPremultipliedColorU8.FromRgbaUnchecked(10, 11, 12, 13)];
  var Bytes: TArray<Byte>;
  SetLength(Bytes, 8);

  Move(Pixels[0], Bytes[0], SizeOf(Bytes));

  Assert.AreEqual<Integer>(4, SizeOf(TTsPremultipliedColorU8));
  Assert.AreEqual<TArray<Byte>>([0, 1, 2, 3, 10, 11, 12, 13], Bytes);
end;

procedure TTsColorTests.TestPremultiplyU8(const Color, Alpha, Expected: Integer);
begin
  const Actual = TTsColorMath.PremultiplyU8(Byte(Color), Byte(Alpha));

  Assert.AreEqual(Expected, Integer(Actual));
end;

procedure TTsColorTests.TestDemultiplyU8OfTransparentSaturates;
begin
  const State = TTsFloatMode.Enter;
  try
    const FromColor = TTsPremultipliedColorU8.FromRgbaUnchecked(5, 0, 0, 0).Demultiply;
    const FromZero = TTsPremultipliedColorU8.Transparent.Demultiply;

    Assert.AreEqual(255, Integer(FromColor.Red));
    Assert.AreEqual(0, Integer(FromColor.Green));
    Assert.AreEqual(0, Integer(FromZero.Red));
    Assert.AreEqual(0, Integer(FromZero.Alpha));
  finally
    TTsFloatMode.Leave(State);
  end;
end;

procedure TTsColorTests.TestPremultipliedColorU8FromRgbaChecksTheAlpha;
begin
  var Color: TTsPremultipliedColorU8;

  Assert.IsTrue(TTsPremultipliedColorU8.TryFromRgba(10, 20, 30, 30, Color));
  Assert.AreEqual(30, Integer(Color.Blue));
  Assert.IsFalse(TTsPremultipliedColorU8.TryFromRgba(10, 20, 31, 30, Color));
end;

procedure TTsColorTests.TestColorFromRgbaRejectsOutOfRange;
begin
  var Color: TTsColor;

  Assert.IsTrue(TTsColor.TryFromRgba(0, 0.5, 1, 1, Color));
  Assert.IsFalse(TTsColor.TryFromRgba(1.01, 0, 0, 1, Color));
  Assert.IsFalse(TTsColor.TryFromRgba(0, -0.01, 0, 1, Color));
  Assert.IsFalse(TTsColor.TryFromRgba(0, 0, 0, Single.NaN, Color));
end;

procedure TTsColorTests.TestColorFromRgba8DividesBy255;
begin
  const Color = TTsColor.FromRgba8(255, 51, 0, 255);

  Assert.AreEqual<Single>(1, Color.Red);
  Assert.AreEqual<Single>(TTsNormalizedF32.CreateU8(51).Get, Color.Green);
  Assert.AreEqual<Single>(0, Color.Blue);
  Assert.IsTrue(Color.IsOpaque);
end;

procedure TTsColorTests.TestColorSettersClamp;
begin
  var Color := TTsColor.Black;

  Color.SetRed(2);
  Color.SetGreen(-1);
  Color.SetBlue(0.25);
  Color.SetAlpha(0.5);

  Assert.AreEqual<Single>(1, Color.Red);
  Assert.AreEqual<Single>(0, Color.Green);
  Assert.AreEqual<Single>(0.25, Color.Blue);
  Assert.AreEqual<Single>(0.5, Color.Alpha);
  Assert.IsFalse(Color.IsOpaque);
end;

procedure TTsColorTests.TestApplyOpacityClampsOpacityAndResult;
begin
  var Color := TTsColor.White;

  Color.ApplyOpacity(0.5);
  Assert.AreEqual<Single>(0.5, Color.Alpha);

  Color.ApplyOpacity(3);
  Assert.AreEqual<Single>(0.5, Color.Alpha);

  Color.ApplyOpacity(-1);
  Assert.AreEqual<Single>(0, Color.Alpha);
end;

procedure TTsColorTests.TestColorPremultiplyScalesTheChannels;
begin
  const Color = TTsColor.FromRgba8(255, 128, 0, 255);
  var Translucent := Color;
  Translucent.SetAlpha(0.5);

  const Premultiplied = Translucent.Premultiply;

  Assert.AreEqual<Single>(0.5, Premultiplied.Red);
  Assert.AreEqual<Single>(Single(Color.Green * 0.5), Premultiplied.Green);
  Assert.AreEqual<Single>(0, Premultiplied.Blue);
  Assert.AreEqual<Single>(0.5, Premultiplied.Alpha);
end;

procedure TTsColorTests.TestColorPremultiplyOpaqueKeepsTheChannels;
begin
  const Color = TTsColor.FromRgba8(10, 20, 30, 255);

  const Premultiplied = Color.Premultiply;

  Assert.AreEqual<Single>(Color.Red, Premultiplied.Red);
  Assert.AreEqual<Single>(Color.Green, Premultiplied.Green);
  Assert.AreEqual<Single>(Color.Blue, Premultiplied.Blue);
  Assert.AreEqual<Single>(1, Premultiplied.Alpha);
end;

procedure TTsColorTests.TestColorToColorU8Rounds;
begin
  const Expected = TTsColorU8.FromRgba(255, 128, 0, 64);

  const Actual = TTsColor.FromRgba8(255, 128, 0, 64).ToColorU8;

  AssertColorU8(Expected, Actual);
end;

procedure TTsColorTests.TestPremultipliedColorDemultiply;
begin
  var Translucent := TTsColor.FromRgba8(200, 100, 0, 255);
  Translucent.SetAlpha(0.5);

  const Back = Translucent.Premultiply.Demultiply;
  const Transparent = TTsColor.Transparent.Premultiply.Demultiply;

  Assert.AreEqual<Single>(Translucent.Red, Back.Red);
  Assert.AreEqual<Single>(0.5, Back.Alpha);
  Assert.AreEqual<Single>(0, Transparent.Red);
  Assert.AreEqual<Single>(0, Transparent.Alpha);
end;

procedure TTsColorTests.TestPremultipliedColorToColorU8;
begin
  var Translucent := TTsColor.White;
  Translucent.SetAlpha(0.5);

  const Actual = Translucent.Premultiply.ToColorU8;

  AssertColorU8(TTsPremultipliedColorU8.FromRgbaUnchecked(128, 128, 128, 128), Actual);
end;

end.
