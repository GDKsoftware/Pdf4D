// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.Native.Conversion.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Render.Native.Scalar;

type
  [TestFixture]
  TTsConversionTests = class
  private
    FFloatState: TTsFloatState;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestMatrixMapsLikePdf;

    [Test]
    procedure TestQuadStaysQuad;

    [Test]
    procedure TestCubicAndCloseAreKept;

    [Test]
    procedure TestNonFinitePathGivesFalse;

    [Test]
    procedure TestPathWithoutSegmentGivesFalse;

    [Test]
    procedure TestStrokeStyleMapsCapsJoinsAndDashes;

    [Test]
    procedure TestInvalidStrokeStyleGivesFalse;

    [Test]
    procedure TestDeviceTransformNeedsAnInverse;

    [Test]
    procedure TestEveryBlendModeIsMapped;

    [Test]
    procedure TestFilterSpreadModeAndFillRuleAreMapped;

    [Test]
    procedure TestColorTakesTheAlpha;
  end;

implementation

uses
  Pdf4D.Common.Matrix,
  Pdf4D.Common.Path,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.Transform,
  Pdf4D.Render.Native.Path,
  Pdf4D.Render.Native.BlendMode,
  Pdf4D.Render.Native.Pipeline.Context,
  Pdf4D.Render.Native.Scan,
  Pdf4D.Render.Native.Shader,
  Pdf4D.Render.Native.Stroker,
  Pdf4D.Render.Native.Conversion;

procedure TTsConversionTests.Setup;
begin
  FFloatState := TTsFloatMode.Enter;
end;

procedure TTsConversionTests.TearDown;
begin
  TTsFloatMode.Leave(FFloatState);
end;

procedure TTsConversionTests.TestMatrixMapsLikePdf;
begin
  // x' = a * x + c * y + e and y' = b * x + d * y + f
  const Matrix = TPdfMatrix.Create(2, 0.5, 0.25, 3, 10, 20);
  const Ts = TTsConversion.ToTransform(Matrix);
  var Point := TTsPoint.FromXY(1, 2);

  Ts.MapPoint(Point);

  Assert.AreEqual(12.5, Point.X, 0.0001);
  Assert.AreEqual(26.5, Point.Y, 0.0001);
end;

procedure TTsConversionTests.TestQuadStaysQuad;
begin
  const Source = TPdfPath.Create;
  try
    Source.MoveTo(0, 0);
    Source.QuadTo(5, 8, 10, 0);

    var Ts: TTsPath;
    Assert.IsTrue(TTsConversion.TryToPath(Source, Ts));

    Assert.AreEqual(2, Integer(Length(Ts.Verbs)));
    Assert.AreEqual(Ord(TTsPathVerb.Move), Ord(Ts.Verbs[0]));
    Assert.AreEqual(Ord(TTsPathVerb.Quad), Ord(Ts.Verbs[1]));
    Assert.AreEqual(3, Integer(Length(Ts.Points)));
    Assert.AreEqual(5.0, Ts.Points[1].X, 0.0001);
    Assert.AreEqual(8.0, Ts.Points[1].Y, 0.0001);
    Assert.AreEqual(10.0, Ts.Points[2].X, 0.0001);
  finally
    Source.Free;
  end;
end;

procedure TTsConversionTests.TestCubicAndCloseAreKept;
begin
  const Source = TPdfPath.Create;
  try
    Source.MoveTo(0, 0);
    Source.CubicTo(1, 5, 4, 5, 5, 0);
    Source.LineTo(5, -4);
    Source.ClosePath;

    var Ts: TTsPath;
    Assert.IsTrue(TTsConversion.TryToPath(Source, Ts));

    Assert.AreEqual(4, Integer(Length(Ts.Verbs)));
    Assert.AreEqual(Ord(TTsPathVerb.Cubic), Ord(Ts.Verbs[1]));
    Assert.AreEqual(Ord(TTsPathVerb.Line), Ord(Ts.Verbs[2]));
    Assert.AreEqual(Ord(TTsPathVerb.Close), Ord(Ts.Verbs[3]));
    Assert.AreEqual(5, Integer(Length(Ts.Points)));
  finally
    Source.Free;
  end;
end;

procedure TTsConversionTests.TestNonFinitePathGivesFalse;
begin
  const NotANumber = TPdfPath.Create;
  const Infinite = TPdfPath.Create;
  try
    NotANumber.MoveTo(0, 0);
    NotANumber.LineTo(Single.NaN, 3);
    NotANumber.LineTo(5, 5);

    Infinite.MoveTo(0, 0);
    Infinite.LineTo(4, 4);
    Infinite.QuadTo(5, Single.NegativeInfinity, 6, 6);

    var Ts: TTsPath;
    Assert.IsFalse(TTsConversion.TryToPath(NotANumber, Ts), 'NaN');
    Assert.IsFalse(TTsConversion.TryToPath(Infinite, Ts), 'infinity in a control point');
  finally
    NotANumber.Free;
    Infinite.Free;
  end;
end;

procedure TTsConversionTests.TestPathWithoutSegmentGivesFalse;
begin
  const Empty = TPdfPath.Create;
  const OnlyMove = TPdfPath.Create;
  try
    OnlyMove.MoveTo(3, 3);

    var Ts: TTsPath;
    Assert.IsFalse(TTsConversion.TryToPath(Empty, Ts), 'an empty path');
    Assert.IsFalse(TTsConversion.TryToPath(OnlyMove, Ts), 'a path of one MoveTo');
  finally
    Empty.Free;
    OnlyMove.Free;
  end;
end;

procedure TTsConversionTests.TestStrokeStyleMapsCapsJoinsAndDashes;
begin
  var Style := Default(TPdfStrokeStyle);
  Style.Width := 3;
  Style.MiterLimit := 7;
  Style.Cap := TPdfLineCap.Round;
  Style.Join := TPdfLineJoin.Bevel;
  Style.Dashes := [2, 1];
  Style.DashPhase := 0.5;

  var Stroke: TTsStroke;
  Assert.IsTrue(TTsConversion.TryToStroke(Style, Stroke));

  Assert.AreEqual(3.0, Stroke.Width, 0.0001);
  Assert.AreEqual(7.0, Stroke.MiterLimit, 0.0001);
  Assert.AreEqual(Ord(TTsLineCap.Round), Ord(Stroke.LineCap));
  Assert.AreEqual(Ord(TTsLineJoin.Bevel), Ord(Stroke.LineJoin));
  Assert.IsTrue(Stroke.HasDash);

  Style.Cap := TPdfLineCap.Butt;
  Style.Join := TPdfLineJoin.Miter;
  Style.Dashes := nil;
  Assert.IsTrue(TTsConversion.TryToStroke(Style, Stroke));
  Assert.AreEqual(Ord(TTsLineCap.Butt), Ord(Stroke.LineCap));
  Assert.AreEqual(Ord(TTsLineJoin.Miter), Ord(Stroke.LineJoin));
  Assert.IsFalse(Stroke.HasDash);

  Style.Cap := TPdfLineCap.Square;
  Style.Join := TPdfLineJoin.Round;
  Assert.IsTrue(TTsConversion.TryToStroke(Style, Stroke));
  Assert.AreEqual(Ord(TTsLineCap.Square), Ord(Stroke.LineCap));
  Assert.AreEqual(Ord(TTsLineJoin.Round), Ord(Stroke.LineJoin));
end;

procedure TTsConversionTests.TestInvalidStrokeStyleGivesFalse;
begin
  var Valid := Default(TPdfStrokeStyle);
  Valid.Width := 2;
  Valid.MiterLimit := 4;

  var Stroke: TTsStroke;
  var Style := Valid;
  Style.Width := Single.NaN;
  Assert.IsFalse(TTsConversion.TryToStroke(Style, Stroke), 'a width that is not a number');

  Style := Valid;
  Style.Width := -1;
  Assert.IsFalse(TTsConversion.TryToStroke(Style, Stroke), 'a negative width');

  Style := Valid;
  Style.Width := Single.PositiveInfinity;
  Assert.IsFalse(TTsConversion.TryToStroke(Style, Stroke), 'an infinite width');

  Style := Valid;
  Style.MiterLimit := Single.NaN;
  Assert.IsFalse(TTsConversion.TryToStroke(Style, Stroke), 'a miter limit that is not a number');

  Style := Valid;
  Style.Dashes := [Single.NaN, 1];
  Assert.IsFalse(TTsConversion.TryToStroke(Style, Stroke), 'a dash that is not a number');

  Style := Valid;
  Style.Dashes := [0, 0];
  Assert.IsFalse(TTsConversion.TryToStroke(Style, Stroke), 'dashes that add up to zero');

  Style := Valid;
  Style.Dashes := [2, -1];
  Assert.IsFalse(TTsConversion.TryToStroke(Style, Stroke), 'a negative dash');

  Style := Valid;
  Style.Dashes := [2, 1];
  Style.DashPhase := Single.NaN;
  Assert.IsFalse(TTsConversion.TryToStroke(Style, Stroke), 'a phase that is not a number');
end;

procedure TTsConversionTests.TestDeviceTransformNeedsAnInverse;
begin
  var Ts: TTsTransform;

  Assert.IsTrue(TTsConversion.TryToDeviceTransform(TPdfMatrix.Identity, Ts), 'identity');
  Assert.IsTrue(TTsConversion.TryToDeviceTransform(TPdfMatrix.Create(2, 0.5, 0.25, 3, 10, 20), Ts), 'a plain matrix');
  Assert.IsFalse(TTsConversion.TryToDeviceTransform(TPdfMatrix.GetScaleInstance(0, 0), Ts), 'zero scale');
  Assert.IsFalse(TTsConversion.TryToDeviceTransform(TPdfMatrix.Create(1, 2, 2, 4, 0, 0), Ts), 'a singular matrix');
  Assert.IsFalse(TTsConversion.TryToDeviceTransform(TPdfMatrix.GetScaleInstance(1E-39, 1E-39), Ts), 'an inverse that is not finite');
end;

procedure TTsConversionTests.TestEveryBlendModeIsMapped;
begin
  var Expected: TArray<TTsBlendMode> := [
    TTsBlendMode.SourceOver, TTsBlendMode.Multiply, TTsBlendMode.Screen, TTsBlendMode.Overlay, TTsBlendMode.Darken,
    TTsBlendMode.Lighten, TTsBlendMode.ColorDodge, TTsBlendMode.ColorBurn, TTsBlendMode.HardLight, TTsBlendMode.SoftLight,
    TTsBlendMode.Difference, TTsBlendMode.Exclusion, TTsBlendMode.Hue, TTsBlendMode.Saturation, TTsBlendMode.Color,
    TTsBlendMode.Luminosity];

  for var Mode := Low(TPdfBlendMode) to High(TPdfBlendMode) do
  begin
    Assert.AreEqual(Ord(Expected[Ord(Mode)]), Ord(TTsConversion.ToBlendMode(Mode)), Format('blend mode %d', [Ord(Mode)]));
  end;
end;

procedure TTsConversionTests.TestFilterSpreadModeAndFillRuleAreMapped;
begin
  Assert.AreEqual(Ord(TTsFilterQuality.Nearest), Ord(TTsConversion.ToFilterQuality(TPdfImageFilter.Nearest)));
  Assert.AreEqual(Ord(TTsFilterQuality.Bilinear), Ord(TTsConversion.ToFilterQuality(TPdfImageFilter.Bilinear)));
  Assert.AreEqual(Ord(TTsFilterQuality.Bicubic), Ord(TTsConversion.ToFilterQuality(TPdfImageFilter.Bicubic)));

  Assert.AreEqual(Ord(TTsSpreadMode.Decal), Ord(TTsConversion.ToSpreadMode(TPdfTileMode.Decal)));
  Assert.AreEqual(Ord(TTsSpreadMode.&Repeat), Ord(TTsConversion.ToSpreadMode(TPdfTileMode.&Repeat)));

  Assert.AreEqual(Ord(TTsFillRule.Winding), Ord(TTsConversion.ToFillRule(TPdfFillRule.NonZero)));
  Assert.AreEqual(Ord(TTsFillRule.EvenOdd), Ord(TTsConversion.ToFillRule(TPdfFillRule.EvenOdd)));
end;

procedure TTsConversionTests.TestColorTakesTheAlpha;
begin
  const Half = TTsConversion.ToColor(TPdfDeviceColor.Create(255, 0, 51), 0.5);
  Assert.AreEqual(1.0, Half.Red, 0.0001);
  Assert.AreEqual(0.0, Half.Green, 0.0001);
  Assert.AreEqual(0.2, Half.Blue, 0.0001);
  Assert.AreEqual(0.5, Half.Alpha, 0.0001);

  const OnAlpha = TTsConversion.ToColor(TPdfDeviceColor.Create(255, 0, 0, 128), 0.5);
  Assert.AreEqual(128 / 255 * 0.5, OnAlpha.Alpha, 0.0001);

  const NotANumber = TTsConversion.ToColor(TPdfDeviceColor.Create(255, 0, 0), Single.NaN);
  Assert.AreEqual(0.0, NotANumber.Alpha, 0.0001);

  const TooLarge = TTsConversion.ToColor(TPdfDeviceColor.Create(255, 0, 0), 7);
  Assert.AreEqual(1.0, TooLarge.Alpha, 0.0001);
end;

end.
