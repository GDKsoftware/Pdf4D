// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.Skia.Device.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Types,
  System.Math,

  System.Skia,
  DUnitX.TestFramework,
  Pdf4D.Common.Matrix,
  Pdf4D.Common.Path,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.ClipPath,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Render.Skia.Backend,
  Pdf4D.Render.Skia.Device,
  Pdf4D.Tests.DeviceContract;

type
  TRgb = record
    R, G, B: Double;
  end;

  // The blend functions of PDF 32000-1 section 11.3.5 on opaque colors, as the expected values of the blend mode tests
  TPdfBlendReference = class
  private
    class function ToRgb(const Color: TPdfDeviceColor): TRgb; static;
    class function ToColor(const Value: TRgb): TPdfDeviceColor; static;
    class function MakeRgb(const R, G, B: Double): TRgb; static;
    class function Luminosity(const Value: TRgb): Double; static;
    class function Saturation(const Value: TRgb): Double; static;
    class function Scale(const Value: TRgb; const Center, Factor: Double): TRgb; static;
    class function ClipColor(const Value: TRgb): TRgb; static;
    class function SetLuminosity(const Value: TRgb; const Target: Double): TRgb; static;
    class function SetSaturation(const Value: TRgb; const Target: Double): TRgb; static;
    class function SoftLight(const Backdrop, Source: Double): Double; static;
    class function HardLight(const Backdrop, Source: Double): Double; static;
    class function Separable(const Mode: TPdfBlendMode; const Backdrop, Source: Double): Double; static;
    class function NonSeparable(const Mode: TPdfBlendMode; const Backdrop, Source: TRgb): TRgb; static;
    class function IsNonSeparable(const Mode: TPdfBlendMode): Boolean; static;

  public
    class function Blend(const Mode: TPdfBlendMode; const Backdrop, Source: TPdfDeviceColor): TPdfDeviceColor; static;
  end;

  // A device whose surface cannot be made
  TPdfNoSurfaceDevice = class(TPdfSkiaDevice)
  protected
    function MakeSurface: ISkSurface; override;
  end;

  // The contract tests come from the base class; what follows is what only the Skia device has to do
  [TestFixture]
  TPdfSkiaDeviceTests = class(TPdfDeviceContractTests)
  protected
    function CreateBackend: IPdfRenderBackend; override;

  public
    [Test]
    procedure TestBackendNameIsSkia;

    [Test]
    procedure TestMultiplyBlend;

    [Test]
    procedure TestScreenBlend;

    [Test]
    procedure TestEveryBlendModeIsMapped;

    [Test]
    procedure TestSoftMaskScalesAlpha;

    [Test]
    procedure TestSoftMaskOutsideValue;

    [Test]
    procedure TestSoftMaskWithBlendAndAlpha;

    [Test]
    procedure TestSoftMaskDoesNotLeakIntoLaterDrawing;

    [Test]
    procedure TestAntiAliasOffGivesHardEdges;

    [Test]
    procedure TestBitmapWithBlendMode;

    [Test]
    procedure TestSurfaceThatCannotBeMadeRaisesOutOfMemory;

    [Test]
    procedure TestFailedClipLeavesTheDeviceUnclipped;

    [Test]
    procedure TestSoftMaskAtAnOffsetWithOutsideValue;

    [Test]
    procedure TestClipCombinedWithSoftMask;
  end;


implementation

{ TPdfBlendReference }

class function TPdfBlendReference.ToRgb(const Color: TPdfDeviceColor): TRgb;
begin
  Result := MakeRgb(Color.R / 255, Color.G / 255, Color.B / 255);
end;

class function TPdfBlendReference.ToColor(const Value: TRgb): TPdfDeviceColor;
begin
  Result := TPdfDeviceColor.Create(Round(EnsureRange(Value.R, 0, 1) * 255), Round(EnsureRange(Value.G, 0, 1) * 255),
                                   Round(EnsureRange(Value.B, 0, 1) * 255));
end;

class function TPdfBlendReference.MakeRgb(const R, G, B: Double): TRgb;
begin
  Result.R := R;
  Result.G := G;
  Result.B := B;
end;

class function TPdfBlendReference.Luminosity(const Value: TRgb): Double;
begin
  Result := 0.3 * Value.R + 0.59 * Value.G + 0.11 * Value.B;
end;

class function TPdfBlendReference.Saturation(const Value: TRgb): Double;
begin
  Result := Max(Value.R, Max(Value.G, Value.B)) - Min(Value.R, Min(Value.G, Value.B));
end;

class function TPdfBlendReference.Scale(const Value: TRgb; const Center, Factor: Double): TRgb;
begin
  Result := MakeRgb(Center + (Value.R - Center) * Factor, Center + (Value.G - Center) * Factor, Center + (Value.B - Center) * Factor);
end;

class function TPdfBlendReference.ClipColor(const Value: TRgb): TRgb;
begin
  Result := Value;
  const L = Luminosity(Value);
  const Lowest = Min(Value.R, Min(Value.G, Value.B));
  const Highest = Max(Value.R, Max(Value.G, Value.B));

  if Lowest < 0 then
  begin
    Result := Scale(Result, L, L / (L - Lowest));
  end;

  if Highest > 1 then
  begin
    Result := Scale(Result, L, (1 - L) / (Highest - L));
  end;
end;

class function TPdfBlendReference.SetLuminosity(const Value: TRgb; const Target: Double): TRgb;
begin
  const Delta = Target - Luminosity(Value);
  Result := ClipColor(MakeRgb(Value.R + Delta, Value.G + Delta, Value.B + Delta));
end;

class function TPdfBlendReference.SetSaturation(const Value: TRgb; const Target: Double): TRgb;
begin
  const Lowest = Min(Value.R, Min(Value.G, Value.B));
  const Range = Saturation(Value);
  if Range <= 0 then
  begin
    Exit(MakeRgb(0, 0, 0));
  end;

  Result := MakeRgb((Value.R - Lowest) * Target / Range, (Value.G - Lowest) * Target / Range, (Value.B - Lowest) * Target / Range);
end;

class function TPdfBlendReference.SoftLight(const Backdrop, Source: Double): Double;
begin
  if Source <= 0.5 then
  begin
    Exit(Backdrop - (1 - 2 * Source) * Backdrop * (1 - Backdrop));
  end;

  var Curve: Double;
  if Backdrop <= 0.25 then
  begin
    Curve := ((16 * Backdrop - 12) * Backdrop + 4) * Backdrop;
  end
  else
  begin
    Curve := Sqrt(Backdrop);
  end;

  Result := Backdrop + (2 * Source - 1) * (Curve - Backdrop);
end;

class function TPdfBlendReference.HardLight(const Backdrop, Source: Double): Double;
begin
  if Source <= 0.5 then
  begin
    Exit(Backdrop * 2 * Source);
  end;

  const Screened = 2 * Source - 1;
  Result := Backdrop + Screened - Backdrop * Screened;
end;

class function TPdfBlendReference.Separable(const Mode: TPdfBlendMode; const Backdrop, Source: Double): Double;
begin
  case Mode of
    TPdfBlendMode.Normal     : Result := Source;
    TPdfBlendMode.Multiply   : Result := Backdrop * Source;
    TPdfBlendMode.Screen     : Result := Backdrop + Source - Backdrop * Source;
    TPdfBlendMode.Overlay    : Result := HardLight(Source, Backdrop);
    TPdfBlendMode.Darken     : Result := Min(Backdrop, Source);
    TPdfBlendMode.Lighten    : Result := Max(Backdrop, Source);
    TPdfBlendMode.ColorDodge : Result := Min(1, Backdrop / (1 - Source));
    TPdfBlendMode.ColorBurn  : Result := 1 - Min(1, (1 - Backdrop) / Source);
    TPdfBlendMode.HardLight  : Result := HardLight(Backdrop, Source);
    TPdfBlendMode.SoftLight  : Result := SoftLight(Backdrop, Source);
    TPdfBlendMode.Difference : Result := Abs(Backdrop - Source);
    TPdfBlendMode.Exclusion  : Result := Backdrop + Source - 2 * Backdrop * Source;
  else
    raise EArgumentException.CreateFmt('Not a separable blend mode: %d', [Ord(Mode)]);
  end;
end;

class function TPdfBlendReference.NonSeparable(const Mode: TPdfBlendMode; const Backdrop, Source: TRgb): TRgb;
begin
  case Mode of
    TPdfBlendMode.Hue        : Result := SetLuminosity(SetSaturation(Source, Saturation(Backdrop)), Luminosity(Backdrop));
    TPdfBlendMode.Saturation : Result := SetLuminosity(SetSaturation(Backdrop, Saturation(Source)), Luminosity(Backdrop));
    TPdfBlendMode.Color      : Result := SetLuminosity(Source, Luminosity(Backdrop));
    TPdfBlendMode.Luminosity : Result := SetLuminosity(Backdrop, Luminosity(Source));
  else
    raise EArgumentException.CreateFmt('Not a non-separable blend mode: %d', [Ord(Mode)]);
  end;
end;

class function TPdfBlendReference.IsNonSeparable(const Mode: TPdfBlendMode): Boolean;
begin
  Result := (Mode in [TPdfBlendMode.Hue, TPdfBlendMode.Saturation, TPdfBlendMode.Color, TPdfBlendMode.Luminosity]);
end;

class function TPdfBlendReference.Blend(const Mode: TPdfBlendMode; const Backdrop, Source: TPdfDeviceColor): TPdfDeviceColor;
begin
  const BackdropRgb = ToRgb(Backdrop);
  const SourceRgb = ToRgb(Source);

  if IsNonSeparable(Mode) then
  begin
    Exit(ToColor(NonSeparable(Mode, BackdropRgb, SourceRgb)));
  end;

  Result := ToColor(MakeRgb(Separable(Mode, BackdropRgb.R, SourceRgb.R), Separable(Mode, BackdropRgb.G, SourceRgb.G),
                            Separable(Mode, BackdropRgb.B, SourceRgb.B)));
end;

{ TPdfNoSurfaceDevice }

function TPdfNoSurfaceDevice.MakeSurface: ISkSurface;
begin
  Result := nil;
end;

{ TPdfSkiaDeviceTests }

function TPdfSkiaDeviceTests.CreateBackend: IPdfRenderBackend;
begin
  Result := TPdfSkiaBackend.Create;
end;

procedure TPdfSkiaDeviceTests.TestBackendNameIsSkia;
begin
  Assert.AreEqual('Skia', FBackend.Name);
  Assert.AreEqual(10, FDevice.Width);
  Assert.AreEqual(10, FDevice.Height);
end;

procedure TPdfSkiaDeviceTests.TestMultiplyBlend;
begin
  FillOpaqueBackground(TPdfDeviceColor.Create(255, 128, 0));

  var Composite := NoAntiAlias;
  Composite.BlendMode := TPdfBlendMode.Multiply;
  FillWholeDevice(TPdfPaint.Solid(TPdfDeviceColor.Create(0, 0, 255)), Composite);

  AssertPixel(5, 5, TPdfDeviceColor.Create(0, 0, 0));
end;

procedure TPdfSkiaDeviceTests.TestScreenBlend;
begin
  const Grey = TPdfDeviceColor.Create(128, 128, 128);
  FillOpaqueBackground(Grey);

  var Composite := NoAntiAlias;
  Composite.BlendMode := TPdfBlendMode.Screen;
  FillWholeDevice(TPdfPaint.Solid(Grey), Composite);

  AssertPixel(5, 5, TPdfDeviceColor.Create(192, 192, 192), 1);
end;

procedure TPdfSkiaDeviceTests.TestEveryBlendModeIsMapped;
begin
  const Backdrop = TPdfDeviceColor.Create(50, 100, 200);
  const Source = TPdfDeviceColor.Create(200, 100, 50);

  for var Mode := Low(TPdfBlendMode) to High(TPdfBlendMode) do
  begin
    FillOpaqueBackground(Backdrop);

    var Composite := NoAntiAlias;
    Composite.BlendMode := Mode;
    FillWholeDevice(TPdfPaint.Solid(Source), Composite);

    const Expected = TPdfBlendReference.Blend(Mode, Backdrop, Source);
    const Actual = Pixel(5, 5);
    const Message = Format('Blend mode %d gives (%d,%d,%d), expected (%d,%d,%d)',
                           [Ord(Mode), Actual.R, Actual.G, Actual.B, Expected.R, Expected.G, Expected.B]);
    Assert.AreEqual(Integer(Expected.R), Integer(Actual.R), 2, Message);
    Assert.AreEqual(Integer(Expected.G), Integer(Actual.G), 2, Message);
    Assert.AreEqual(Integer(Expected.B), Integer(Actual.B), 2, Message);
    Assert.AreEqual(255, Integer(Actual.A), Message);
  end;
end;

procedure TPdfSkiaDeviceTests.TestSoftMaskScalesAlpha;
begin
  const Mask = NewMask(0, 0, 10, 10, 128, 0);
  try
    var Composite := NoAntiAlias;
    Composite.SoftMask := Mask;
    FillWholeDevice(Red, Composite);
  finally
    Mask.Free;
  end;

  AssertPixel(5, 5, TPdfDeviceColor.Create(128, 0, 0, 128), 1);
end;

procedure TPdfSkiaDeviceTests.TestSoftMaskOutsideValue;
begin
  const Mask = NewMask(0, 0, 2, 2, 255, 0);
  try
    var Composite := NoAntiAlias;
    Composite.SoftMask := Mask;
    FillWholeDevice(Red, Composite);
  finally
    Mask.Free;
  end;

  AssertTransparent(5, 5);
  AssertPixel(1, 1, TPdfDeviceColor.Create(255, 0, 0));
end;

procedure TPdfSkiaDeviceTests.TestSoftMaskWithBlendAndAlpha;
begin
  const Backdrop = TPdfDeviceColor.Create(200, 150, 100);
  const Source = TPdfDeviceColor.Create(100, 200, 250);

  FillOpaqueBackground(Backdrop);
  var Plain := NoAntiAlias;
  Plain.Alpha := 0.5;
  Plain.BlendMode := TPdfBlendMode.Multiply;
  FillWholeDevice(TPdfPaint.Solid(Source), Plain);
  const Expected = Pixel(5, 5);

  FillOpaqueBackground(Backdrop);
  const Mask = NewMask(0, 0, 10, 10, 255, 255);
  try
    var Masked := Plain;
    Masked.SoftMask := Mask;
    FillWholeDevice(TPdfPaint.Solid(Source), Masked);
  finally
    Mask.Free;
  end;

  AssertPixel(5, 5, Expected, 1);
end;

procedure TPdfSkiaDeviceTests.TestSoftMaskDoesNotLeakIntoLaterDrawing;
begin
  const Mask = NewMask(0, 0, 2, 2, 255, 0);
  try
    var Masked := NoAntiAlias;
    Masked.SoftMask := Mask;
    FillWholeDevice(Red, Masked);
  finally
    Mask.Free;
  end;

  FillRect(6, 6, 9, 9, Red, NoAntiAlias);

  AssertPixel(7, 7, TPdfDeviceColor.Create(255, 0, 0));
  AssertTransparent(4, 4);
end;

procedure TPdfSkiaDeviceTests.TestAntiAliasOffGivesHardEdges;
begin
  const Triangle = TPdfPath.Create;
  try
    Triangle.MoveTo(0, 0);
    Triangle.LineTo(10, 3);
    Triangle.LineTo(0, 10);
    Triangle.ClosePath;
    FDevice.FillPath(Triangle, TPdfMatrix.Identity, TPdfFillRule.NonZero, Red, NoAntiAlias);
  finally
    Triangle.Free;
  end;

  FSnapshot := FDevice.ToBitmap;
  for var Y := 0 to FSnapshot.Height - 1 do
  begin
    for var X := 0 to FSnapshot.Width - 1 do
    begin
      const Alpha = FSnapshot.GetPixel(X, Y).A;
      const IsHard = ((Alpha = 0) or (Alpha = 255));
      Assert.IsTrue(IsHard, Format('Pixel (%d, %d) has the partial alpha %d', [X, Y, Alpha]));
    end;
  end;
end;

procedure TPdfSkiaDeviceTests.TestBitmapWithBlendMode;
begin
  FillOpaqueBackground(TPdfDeviceColor.Create(255, 128, 0));

  const Bitmap = TPdfBitmap.Create(2, 2);
  try
    for var Y := 0 to 1 do
    begin
      for var X := 0 to 1 do
      begin
        Bitmap.SetPixel(X, Y, TPdfDeviceColor.Create(0, 0, 255));
      end;
    end;

    var Composite := NoAntiAlias;
    Composite.BlendMode := TPdfBlendMode.Multiply;
    FDevice.DrawBitmap(Bitmap, TPdfMatrix.Create(5, 0, 0, 5, 0, 0), TPdfImageFilter.Nearest, Composite);
  finally
    Bitmap.Free;
  end;

  AssertPixel(5, 5, TPdfDeviceColor.Create(0, 0, 0));
end;

procedure TPdfSkiaDeviceTests.TestSurfaceThatCannotBeMadeRaisesOutOfMemory;
begin
  Assert.WillRaise(
    procedure
    begin
      TPdfNoSurfaceDevice.Create(4, 4);
    end,
    EOutOfMemory);
end;

procedure TPdfSkiaDeviceTests.TestFailedClipLeavesTheDeviceUnclipped;
begin
  const GoodClip = NewClip(nil, 2, 2, 5, 5);
  FDevice.SetClip(GoodClip);

  const BadClip = TPdfClipPath.Create(nil, NewRectPath(0, 0, 10, 10), TPdfMatrix.Identity, TPdfFillRule(99));
  Assert.WillRaise(
    procedure
    begin
      FDevice.SetClip(BadClip);
    end,
    ENotSupportedException);

  FillWholeDevice(Red, NoAntiAlias);
  AssertPixel(8, 8, TPdfDeviceColor.Create(255, 0, 0));

  FDevice.Clear(TPdfDeviceColor.Transparent);
  FDevice.SetClip(GoodClip);
  FillWholeDevice(Red, NoAntiAlias);
  AssertPixel(3, 3, TPdfDeviceColor.Create(255, 0, 0));
  AssertTransparent(8, 8);
end;

procedure TPdfSkiaDeviceTests.TestSoftMaskAtAnOffsetWithOutsideValue;
begin
  const Mask = NewMask(3, 3, 2, 2, 255, 128);
  try
    var Composite := NoAntiAlias;
    Composite.SoftMask := Mask;
    FillWholeDevice(Red, Composite);
  finally
    Mask.Free;
  end;

  AssertPixel(3, 3, TPdfDeviceColor.Create(255, 0, 0));
  AssertPixel(4, 4, TPdfDeviceColor.Create(255, 0, 0));
  AssertPixel(0, 0, TPdfDeviceColor.Create(128, 0, 0, 128), 1);
  AssertPixel(8, 8, TPdfDeviceColor.Create(128, 0, 0, 128), 1);
end;

procedure TPdfSkiaDeviceTests.TestClipCombinedWithSoftMask;
begin
  FDevice.SetClip(NewClip(nil, 0, 0, 5, 5));

  const Mask = NewMask(0, 0, 10, 10, 255, 0);
  try
    var Composite := NoAntiAlias;
    Composite.SoftMask := Mask;
    FillWholeDevice(Red, Composite);
  finally
    Mask.Free;
  end;

  AssertPixel(2, 2, TPdfDeviceColor.Create(255, 0, 0));
  AssertTransparent(7, 7);
end;

end.
