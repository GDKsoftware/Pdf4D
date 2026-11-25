// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of tiny-skia v0.12.0 src/pipeline/mod.rs (blend_tests, highp) and of the high precision stages of src/pipeline/highp.rs
unit Pdf4D.Render.Native.Pipeline.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Math,
  DUnitX.TestFramework,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.Transform,
  Pdf4D.Render.Native.Color,
  Pdf4D.Render.Native.Stage,
  Pdf4D.Render.Native.BlendMode,
  Pdf4D.Render.Native.Pipeline.Context,
  Pdf4D.Render.Native.Pipeline.Highp,
  Pdf4D.Render.Native.Pipeline;

type
  TTsRgb = record
    R: Double;
    G: Double;
    B: Double;
  end;

  // The blend functions of PDF 32000-1 section 11.3.5 on opaque colors, as the expected values of the blend mode tests
  TTsPdfBlendReference = class
  private
    class function MakeRgb(const R, G, B: Double): TTsRgb; static;
    class function Luminosity(const Value: TTsRgb): Double; static;
    class function Saturation(const Value: TTsRgb): Double; static;
    class function Scale(const Value: TTsRgb; const Center, Factor: Double): TTsRgb; static;
    class function ClipColor(const Value: TTsRgb): TTsRgb; static;
    class function SetLuminosity(const Value: TTsRgb; const Target: Double): TTsRgb; static;
    class function SetSaturation(const Value: TTsRgb; const Target: Double): TTsRgb; static;
    class function SoftLight(const Backdrop, Source: Double): Double; static;
    class function HardLight(const Backdrop, Source: Double): Double; static;
    class function Separable(const Mode: TTsBlendMode; const Backdrop, Source: Double): Double; static;
    class function NonSeparable(const Mode: TTsBlendMode; const Backdrop, Source: TTsRgb): TTsRgb; static;
    class function IsNonSeparable(const Mode: TTsBlendMode): Boolean; static;
    class function ToByte(const Value: Double): Integer; static;

  public
    // The three bytes of the blended color, for opaque colors given as bytes
    class function Blend(const Mode: TTsBlendMode; const Backdrop, Source: array of Byte): TBytes; static;
  end;

  [TestFixture]
  TTsPipelineTests = class
  private
    FFloatState: TTsFloatState;

    function Opaque(const R, G, B: Byte): TTsPremultipliedColor;
    function PixelBytes(const R, G, B, A: Byte): TBytes;
    function FilledBytes(const Count: Integer; const R, G, B, A: Byte): TBytes;
    function Region(const Width, Height: Cardinal): TTsScreenIntRect;
    function NoPixmap: TTsPixmapRef;
    function Image(const Pixels: array of Byte; const Width, Height: Cardinal): TTsPixmapRef;
    // Runs the pipeline over the whole destination
    procedure RunOver(var Pipeline: TTsRasterPipeline; var Dst: TTsSubPixmapMut; const Src: TTsPixmapRef);
    procedure AssertPixel(const Data: TBytes; const Index: Integer; const R, G, B, A: Byte; const Tolerance: Integer = 0);
    procedure PushOutOfRangeStage;
    procedure PushTooManyStages;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    // test_blend_highp! of pipeline/mod.rs: the destination is (50, 127, 150, 200), the source (220, 140, 75, 180) premultiplied
    [Test]
    [TestCase('ClearHighp', '0,0,0,0,0')]
    [TestCase('DestinationHighp', '2,39,100,118,200')]
    [TestCase('SourceOverHighp', '3,167,128,88,239')]
    [TestCase('DestinationOverHighp', '4,72,121,129,239')]
    [TestCase('SourceInHighp', '5,122,78,42,141')]
    [TestCase('DestinationInHighp', '6,28,71,83,141')]
    [TestCase('SourceOutHighp', '7,33,21,11,39')]
    [TestCase('DestinationOutHighp', '8,11,29,35,59')]
    [TestCase('SourceAtopHighp', '9,133,107,76,200')]
    [TestCase('DestinationAtopHighp', '10,61,92,95,180')]
    [TestCase('XorHighp', '11,45,51,46,98')]
    [TestCase('PlusHighp', '12,194,199,171,255')]
    [TestCase('ModulateHighp', '13,24,39,24,141')]
    [TestCase('ScreenHighp', '14,171,160,146,239')]
    [TestCase('OverlayHighp', '15,92,128,106,239')]
    [TestCase('DarkenHighp', '16,72,121,88,239')]
    [TestCase('LightenHighp', '17,167,128,129,239')]
    [TestCase('ColorDodgeHighp', '18,186,192,164,239')]
    [TestCase('ColorBurnHighp', '19,54,63,46,239')]
    [TestCase('HardLightHighp', '20,155,128,95,239')]
    [TestCase('SoftLightHighp', '21,98,124,115,239')]
    [TestCase('DifferenceHighp', '22,139,58,88,239')]
    [TestCase('ExclusionHighp', '23,147,121,122,239')]
    [TestCase('MultiplyHighp', '24,69,89,71,239')]
    [TestCase('HueHighp', '25,128,103,74,239')]
    [TestCase('SaturationHighp', '26,59,126,140,239')]
    [TestCase('ColorHighp', '27,139,100,60,239')]
    [TestCase('LuminosityHighp', '28,100,149,157,239')]
    procedure TestBlendHighp(const Mode, R, G, B, A: Integer);

    // Source is a no-op: its stage list is empty
    [Test]
    procedure TestSourceBlendModeHasNoStage;

    [Test]
    procedure TestLoadStoreRoundTrip;

    [Test]
    procedure TestLoadStoreRoundTripWithTail;

    [Test]
    procedure TestSourceOverHalfAlpha;

    [Test]
    procedure TestEveryPdfBlendModeMatchesFormula;

    [Test]
    procedure TestScale1FloatAndLerpU8;

    [Test]
    procedure TestScaleU8CoversTwoPixels;

    [Test]
    procedure TestMaskU8StopsAZeroRun;

    [Test]
    procedure TestPremultiplyAndClamps;

    [Test]
    procedure TestMoveStagesCopyTheColor;

    [Test]
    procedure TestSeedShaderAndTransformGather;

    [Test]
    procedure TestRepeatTilesTheCoordinates;

    [Test]
    procedure TestReflectMirrorsTheCoordinates;

    [Test]
    procedure TestBilinearHalfwayBetweenTwoPixels;

    [Test]
    procedure TestSamplersKeepAUniformImage;

    [Test]
    procedure TestNaNCoordinateGathersTheFirstPixel;

    [Test]
    procedure TestX1StagesNormalize;

    [Test]
    procedure TestSourceOverRgbaBlendsOverTheDestination;

    [Test]
    procedure TestStageTableHoldsExactlyThePortedStages;

    [Test]
    procedure TestPushUniformColorFillsTheContext;

    [Test]
    procedure TestPushTransformSkipsIdentityAndNonFinite;

    [Test]
    procedure TestPushOfAStageWithoutImplementationRaises;

    [Test]
    procedure TestPushBeyondMaxStagesRaises;

    [Test]
    procedure TestEmptyPipelineDrawsNothing;

    [Test]
    procedure TestRegionOutsideTheDataDrawsNothing;

    [Test]
    procedure TestSubPixmapStartsAtItsOffset;
  end;

implementation

{ TTsPdfBlendReference }

class function TTsPdfBlendReference.MakeRgb(const R, G, B: Double): TTsRgb;
begin
  Result.R := R;
  Result.G := G;
  Result.B := B;
end;

class function TTsPdfBlendReference.Luminosity(const Value: TTsRgb): Double;
begin
  Result := 0.3 * Value.R + 0.59 * Value.G + 0.11 * Value.B;
end;

class function TTsPdfBlendReference.Saturation(const Value: TTsRgb): Double;
begin
  Result := Max(Value.R, Max(Value.G, Value.B)) - Min(Value.R, Min(Value.G, Value.B));
end;

class function TTsPdfBlendReference.Scale(const Value: TTsRgb; const Center, Factor: Double): TTsRgb;
begin
  Result := MakeRgb(Center + (Value.R - Center) * Factor, Center + (Value.G - Center) * Factor, Center + (Value.B - Center) * Factor);
end;

class function TTsPdfBlendReference.ClipColor(const Value: TTsRgb): TTsRgb;
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

class function TTsPdfBlendReference.SetLuminosity(const Value: TTsRgb; const Target: Double): TTsRgb;
begin
  const Delta = Target - Luminosity(Value);
  Result := ClipColor(MakeRgb(Value.R + Delta, Value.G + Delta, Value.B + Delta));
end;

class function TTsPdfBlendReference.SetSaturation(const Value: TTsRgb; const Target: Double): TTsRgb;
begin
  const Lowest = Min(Value.R, Min(Value.G, Value.B));
  const Range = Saturation(Value);
  if Range <= 0 then
  begin
    Exit(MakeRgb(0, 0, 0));
  end;

  Result := MakeRgb((Value.R - Lowest) * Target / Range, (Value.G - Lowest) * Target / Range, (Value.B - Lowest) * Target / Range);
end;

class function TTsPdfBlendReference.SoftLight(const Backdrop, Source: Double): Double;
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

class function TTsPdfBlendReference.HardLight(const Backdrop, Source: Double): Double;
begin
  if Source <= 0.5 then
  begin
    Exit(Backdrop * 2 * Source);
  end;

  const Screened = 2 * Source - 1;
  Result := Backdrop + Screened - Backdrop * Screened;
end;

class function TTsPdfBlendReference.Separable(const Mode: TTsBlendMode; const Backdrop, Source: Double): Double;
begin
  case Mode of
    TTsBlendMode.SourceOver  : Result := Source;
    TTsBlendMode.Multiply    : Result := Backdrop * Source;
    TTsBlendMode.Screen      : Result := Backdrop + Source - Backdrop * Source;
    TTsBlendMode.Overlay     : Result := HardLight(Source, Backdrop);
    TTsBlendMode.Darken      : Result := Min(Backdrop, Source);
    TTsBlendMode.Lighten     : Result := Max(Backdrop, Source);
    TTsBlendMode.ColorDodge  : Result := Min(1, Backdrop / (1 - Source));
    TTsBlendMode.ColorBurn   : Result := 1 - Min(1, (1 - Backdrop) / Source);
    TTsBlendMode.HardLight   : Result := HardLight(Backdrop, Source);
    TTsBlendMode.SoftLight   : Result := SoftLight(Backdrop, Source);
    TTsBlendMode.Difference  : Result := Abs(Backdrop - Source);
    TTsBlendMode.Exclusion   : Result := Backdrop + Source - 2 * Backdrop * Source;
  else
    raise EArgumentException.CreateFmt('Not a separable PDF blend mode: %d', [Ord(Mode)]);
  end;
end;

class function TTsPdfBlendReference.NonSeparable(const Mode: TTsBlendMode; const Backdrop, Source: TTsRgb): TTsRgb;
begin
  case Mode of
    TTsBlendMode.Hue        : Result := SetLuminosity(SetSaturation(Source, Saturation(Backdrop)), Luminosity(Backdrop));
    TTsBlendMode.Saturation : Result := SetLuminosity(SetSaturation(Backdrop, Saturation(Source)), Luminosity(Backdrop));
    TTsBlendMode.Color      : Result := SetLuminosity(Source, Luminosity(Backdrop));
    TTsBlendMode.Luminosity : Result := SetLuminosity(Backdrop, Luminosity(Source));
  else
    raise EArgumentException.CreateFmt('Not a non-separable blend mode: %d', [Ord(Mode)]);
  end;
end;

class function TTsPdfBlendReference.IsNonSeparable(const Mode: TTsBlendMode): Boolean;
begin
  Result := (Mode in [TTsBlendMode.Hue, TTsBlendMode.Saturation, TTsBlendMode.Color, TTsBlendMode.Luminosity]);
end;

class function TTsPdfBlendReference.ToByte(const Value: Double): Integer;
begin
  Result := Round(EnsureRange(Value, 0, 1) * 255);
end;

class function TTsPdfBlendReference.Blend(const Mode: TTsBlendMode; const Backdrop, Source: array of Byte): TBytes;
begin
  const BackdropRgb = MakeRgb(Backdrop[0] / 255, Backdrop[1] / 255, Backdrop[2] / 255);
  const SourceRgb = MakeRgb(Source[0] / 255, Source[1] / 255, Source[2] / 255);

  var Blended: TTsRgb;
  if IsNonSeparable(Mode) then
  begin
    Blended := NonSeparable(Mode, BackdropRgb, SourceRgb);
  end
  else
  begin
    Blended := MakeRgb(Separable(Mode, BackdropRgb.R, SourceRgb.R), Separable(Mode, BackdropRgb.G, SourceRgb.G),
                       Separable(Mode, BackdropRgb.B, SourceRgb.B));
  end;

  Result := [ToByte(Blended.R), ToByte(Blended.G), ToByte(Blended.B)];
end;

{ TTsPipelineTests }

procedure TTsPipelineTests.Setup;
begin
  FFloatState := TTsFloatMode.Enter;
end;

procedure TTsPipelineTests.TearDown;
begin
  TTsFloatMode.Leave(FFloatState);
end;

function TTsPipelineTests.Opaque(const R, G, B: Byte): TTsPremultipliedColor;
begin
  Result := TTsColor.FromRgba8(R, G, B, 255).Premultiply;
end;

function TTsPipelineTests.PixelBytes(const R, G, B, A: Byte): TBytes;
begin
  Result := [R, G, B, A];
end;

function TTsPipelineTests.FilledBytes(const Count: Integer; const R, G, B, A: Byte): TBytes;
begin
  SetLength(Result, Count * 4);
  for var I := 0 to Count - 1 do
  begin
    Result[I * 4] := R;
    Result[I * 4 + 1] := G;
    Result[I * 4 + 2] := B;
    Result[I * 4 + 3] := A;
  end;
end;

function TTsPipelineTests.Region(const Width, Height: Cardinal): TTsScreenIntRect;
begin
  Result := TTsScreenIntRect.FromXYWHSafe(0, 0, Width, Height);
end;

function TTsPipelineTests.NoPixmap: TTsPixmapRef;
begin
  Result := Default(TTsPixmapRef);
end;

function TTsPipelineTests.Image(const Pixels: array of Byte; const Width, Height: Cardinal): TTsPixmapRef;
begin
  var Bytes: TBytes;
  SetLength(Bytes, Length(Pixels));
  Move(Pixels[0], Bytes[0], Length(Pixels));

  Assert.IsTrue(TTsPixmapRef.TryFromBytes(Bytes, Width, Height, Result), 'The image data is too short');
end;

procedure TTsPipelineTests.RunOver(var Pipeline: TTsRasterPipeline; var Dst: TTsSubPixmapMut; const Src: TTsPixmapRef);
begin
  Pipeline.Run(Region(Dst.Width, Dst.Height), Default(TTsAAMaskCtx), Default(TTsMaskCtx), Src, Dst);
end;

procedure TTsPipelineTests.AssertPixel(const Data: TBytes; const Index: Integer; const R, G, B, A: Byte; const Tolerance: Integer);
begin
  const Message = Format('Pixel %d is (%d,%d,%d,%d), expected (%d,%d,%d,%d)',
                         [Index, Data[Index * 4], Data[Index * 4 + 1], Data[Index * 4 + 2], Data[Index * 4 + 3], R, G, B, A]);
  Assert.AreEqual(Integer(R), Integer(Data[Index * 4]), Tolerance, Message);
  Assert.AreEqual(Integer(G), Integer(Data[Index * 4 + 1]), Tolerance, Message);
  Assert.AreEqual(Integer(B), Integer(Data[Index * 4 + 2]), Tolerance, Message);
  Assert.AreEqual(Integer(A), Integer(Data[Index * 4 + 3]), Tolerance, Message);
end;

procedure TTsPipelineTests.PushOutOfRangeStage;
begin
  var Builder := TTsRasterPipelineBuilder.New;
  Builder.Push(TTsStage.Gradient);
end;

procedure TTsPipelineTests.PushTooManyStages;
begin
  var Builder := TTsRasterPipelineBuilder.New;
  for var I := 0 to MaxStages do
  begin
    Builder.Push(TTsStage.Premultiply);
  end;
end;

procedure TTsPipelineTests.TestBlendHighp(const Mode, R, G, B, A: Integer);
begin
  const Backdrop = TTsColor.FromRgba8(50, 127, 150, 200).Premultiply.ToColorU8;
  var Dst := TTsSubPixmapMut.Whole(PixelBytes(Backdrop.Red, Backdrop.Green, Backdrop.Blue, Backdrop.Alpha), 1, 1);

  const BlendMode = TTsBlendMode(Mode);
  var Stage: TTsStage;
  Assert.IsTrue(BlendMode.TryToStage(Stage));

  var Builder := TTsRasterPipelineBuilder.New;
  Builder.SetForceHqPipeline(True);
  Builder.PushUniformColor(TTsColor.FromRgba8(220, 140, 75, 180).Premultiply);
  Builder.Push(TTsStage.LoadDestination);
  Builder.Push(Stage);
  Builder.Push(TTsStage.Store);
  var Pipeline := Builder.Compile;

  RunOver(Pipeline, Dst, NoPixmap);

  AssertPixel(Dst.Data, 0, R, G, B, A);
end;

procedure TTsPipelineTests.TestSourceBlendModeHasNoStage;
begin
  var Stage: TTsStage;

  Assert.IsFalse(TTsBlendMode.Source.TryToStage(Stage));
end;

procedure TTsPipelineTests.TestLoadStoreRoundTrip;
begin
  // Every channel takes every value of 0..255: 37 and 91 are odd, so they are permutations modulo 256
  var Bytes: TBytes;
  SetLength(Bytes, 256 * 4);
  for var I := 0 to 255 do
  begin
    Bytes[I * 4] := I;
    Bytes[I * 4 + 1] := 255 - I;
    Bytes[I * 4 + 2] := (I * 37) and 255;
    Bytes[I * 4 + 3] := (I * 91 + 13) and 255;
  end;
  const Expected = Copy(Bytes);

  var Dst := TTsSubPixmapMut.Whole(Bytes, 256, 1);
  var Builder := TTsRasterPipelineBuilder.New;
  Builder.SetForceHqPipeline(True);
  Builder.Push(TTsStage.LoadDestination);
  Builder.Push(TTsStage.MoveDestinationToSource);
  Builder.Push(TTsStage.Store);
  var Pipeline := Builder.Compile;

  RunOver(Pipeline, Dst, NoPixmap);

  Assert.AreEqual(Length(Expected), Length(Dst.Data));
  for var I := 0 to High(Expected) do
  begin
    Assert.AreEqual(Integer(Expected[I]), Integer(Dst.Data[I]), Format('Byte %d changed', [I]));
  end;
end;

procedure TTsPipelineTests.TestLoadStoreRoundTripWithTail;
begin
  // 8 + 8 + 5 pixels: two full runs and a tail of 5
  var Bytes: TBytes;
  SetLength(Bytes, 21 * 4);
  for var I := 0 to High(Bytes) do
  begin
    Bytes[I] := (I * 53 + 7) and 255;
  end;
  const Expected = Copy(Bytes);

  var Dst := TTsSubPixmapMut.Whole(Bytes, 21, 1);
  var Builder := TTsRasterPipelineBuilder.New;
  Builder.SetForceHqPipeline(True);
  Builder.Push(TTsStage.LoadDestination);
  Builder.Push(TTsStage.MoveDestinationToSource);
  Builder.Push(TTsStage.Store);
  var Pipeline := Builder.Compile;

  RunOver(Pipeline, Dst, NoPixmap);

  for var I := 0 to High(Expected) do
  begin
    Assert.AreEqual(Integer(Expected[I]), Integer(Dst.Data[I]), Format('Byte %d changed', [I]));
  end;
end;

procedure TTsPipelineTests.TestSourceOverHalfAlpha;
begin
  var Dst := TTsSubPixmapMut.Whole(PixelBytes(0, 0, 255, 255), 1, 1);

  var Builder := TTsRasterPipelineBuilder.New;
  Builder.SetForceHqPipeline(True);
  Builder.PushUniformColor(TTsColor.FromRgba8(255, 0, 0, 128).Premultiply);
  Builder.Push(TTsStage.LoadDestination);
  Builder.Push(TTsStage.SourceOver);
  Builder.Push(TTsStage.Store);
  var Pipeline := Builder.Compile;

  RunOver(Pipeline, Dst, NoPixmap);

  AssertPixel(Dst.Data, 0, 128, 0, 127, 255, 1);
end;

procedure TTsPipelineTests.TestEveryPdfBlendModeMatchesFormula;
begin
  const PdfModes: TArray<TTsBlendMode> = [
    TTsBlendMode.SourceOver, TTsBlendMode.Multiply, TTsBlendMode.Screen, TTsBlendMode.Overlay, TTsBlendMode.Darken,
    TTsBlendMode.Lighten, TTsBlendMode.ColorDodge, TTsBlendMode.ColorBurn, TTsBlendMode.HardLight, TTsBlendMode.SoftLight,
    TTsBlendMode.Difference, TTsBlendMode.Exclusion, TTsBlendMode.Hue, TTsBlendMode.Saturation, TTsBlendMode.Color,
    TTsBlendMode.Luminosity];

  for var Mode in PdfModes do
  begin
    var Stage: TTsStage;
    Assert.IsTrue(Mode.TryToStage(Stage));

    var Dst := TTsSubPixmapMut.Whole(PixelBytes(50, 100, 200, 255), 1, 1);
    var Builder := TTsRasterPipelineBuilder.New;
    Builder.SetForceHqPipeline(True);
    Builder.PushUniformColor(Opaque(200, 100, 50));
    Builder.Push(TTsStage.LoadDestination);
    Builder.Push(Stage);
    Builder.Push(TTsStage.Store);
    var Pipeline := Builder.Compile;

    RunOver(Pipeline, Dst, NoPixmap);

    const Expected = TTsPdfBlendReference.Blend(Mode, [50, 100, 200], [200, 100, 50]);
    const Message = Format('Blend mode %d gives (%d,%d,%d), expected (%d,%d,%d)',
                           [Ord(Mode), Dst.Data[0], Dst.Data[1], Dst.Data[2], Expected[0], Expected[1], Expected[2]]);
    Assert.AreEqual(Expected[0], Integer(Dst.Data[0]), 1, Message);
    Assert.AreEqual(Expected[1], Integer(Dst.Data[1]), 1, Message);
    Assert.AreEqual(Expected[2], Integer(Dst.Data[2]), 1, Message);
    Assert.AreEqual(255, Integer(Dst.Data[3]), Message);
  end;
end;

procedure TTsPipelineTests.TestScale1FloatAndLerpU8;
begin
  // Scale1Float: the coverage 0.5 halves the premultiplied source
  var Dst := TTsSubPixmapMut.Whole(PixelBytes(0, 0, 0, 0), 1, 1);
  var Builder := TTsRasterPipelineBuilder.New;
  Builder.SetForceHqPipeline(True);
  Builder.PushUniformColor(Opaque(255, 0, 0));
  Builder.Push(TTsStage.Scale1Float);
  Builder.Push(TTsStage.Store);
  Builder.Ctx.CurrentCoverage := 0.5;
  var Pipeline := Builder.Compile;

  RunOver(Pipeline, Dst, NoPixmap);

  AssertPixel(Dst.Data, 0, 128, 0, 0, 128, 1);

  // Lerp1Float with the same coverage is halfway between the destination and the source
  Dst := TTsSubPixmapMut.Whole(PixelBytes(0, 0, 255, 255), 1, 1);
  Builder := TTsRasterPipelineBuilder.New;
  Builder.SetForceHqPipeline(True);
  Builder.PushUniformColor(Opaque(255, 0, 0));
  Builder.Push(TTsStage.LoadDestination);
  Builder.Push(TTsStage.Lerp1Float);
  Builder.Push(TTsStage.Store);
  Builder.Ctx.CurrentCoverage := 0.5;
  Pipeline := Builder.Compile;

  RunOver(Pipeline, Dst, NoPixmap);

  AssertPixel(Dst.Data, 0, 128, 0, 127, 255, 1);

  // LerpU8 with the coverage 128 of the anti-aliasing mask
  Dst := TTsSubPixmapMut.Whole(PixelBytes(0, 0, 255, 255), 1, 1);
  Builder := TTsRasterPipelineBuilder.New;
  Builder.SetForceHqPipeline(True);
  Builder.PushUniformColor(Opaque(255, 0, 0));
  Builder.Push(TTsStage.LoadDestination);
  Builder.Push(TTsStage.LerpU8);
  Builder.Push(TTsStage.Store);
  Pipeline := Builder.Compile;

  var AAMask := Default(TTsAAMaskCtx);
  AAMask.Pixels[0] := 128;
  Pipeline.Run(Region(1, 1), AAMask, Default(TTsMaskCtx), NoPixmap, Dst);

  AssertPixel(Dst.Data, 0, 128, 0, 127, 255, 1);
end;

procedure TTsPipelineTests.TestScaleU8CoversTwoPixels;
begin
  var Dst := TTsSubPixmapMut.Whole(FilledBytes(2, 0, 0, 0, 0), 2, 1);
  var Builder := TTsRasterPipelineBuilder.New;
  Builder.SetForceHqPipeline(True);
  Builder.PushUniformColor(Opaque(255, 0, 0));
  Builder.Push(TTsStage.ScaleU8);
  Builder.Push(TTsStage.Store);
  var Pipeline := Builder.Compile;

  var AAMask := Default(TTsAAMaskCtx);
  AAMask.Pixels[0] := 255;
  AAMask.Pixels[1] := 128;
  Pipeline.Run(Region(2, 1), AAMask, Default(TTsMaskCtx), NoPixmap, Dst);

  AssertPixel(Dst.Data, 0, 255, 0, 0, 255);
  AssertPixel(Dst.Data, 1, 128, 0, 0, 128, 1);
end;

procedure TTsPipelineTests.TestMaskU8StopsAZeroRun;
begin
  // 11 pixels: a run of 8 with a zero mask, which is not stored, and a tail of 3 with a full mask
  var Dst := TTsSubPixmapMut.Whole(FilledBytes(11, 9, 9, 9, 9), 11, 1);

  var Builder := TTsRasterPipelineBuilder.New;
  Builder.SetForceHqPipeline(True);
  Builder.PushUniformColor(Opaque(255, 0, 0));
  Builder.Push(TTsStage.MaskU8);
  Builder.Push(TTsStage.Store);
  var Pipeline := Builder.Compile;

  var Mask := Default(TTsMaskCtx);
  SetLength(Mask.Data, 11);
  Mask.Data[8] := 255;
  Mask.Data[9] := 255;
  Mask.Data[10] := 255;
  Mask.RealWidth := 11;
  Pipeline.Run(Region(11, 1), Default(TTsAAMaskCtx), Mask, NoPixmap, Dst);

  for var I := 0 to 7 do
  begin
    AssertPixel(Dst.Data, I, 9, 9, 9, 9);
  end;

  for var I := 8 to 10 do
  begin
    AssertPixel(Dst.Data, I, 255, 0, 0, 255);
  end;
end;

procedure TTsPipelineTests.TestPremultiplyAndClamps;
begin
  // The uniform color is premultiplied already: Premultiply scales the color by the alpha once more, the clamps change nothing
  var Dst := TTsSubPixmapMut.Whole(PixelBytes(0, 0, 0, 0), 1, 1);
  var Builder := TTsRasterPipelineBuilder.New;
  Builder.SetForceHqPipeline(True);
  Builder.PushUniformColor(TTsColor.FromRgba8(255, 255, 255, 128).Premultiply);
  Builder.Push(TTsStage.Premultiply);
  Builder.Push(TTsStage.Clamp0);
  Builder.Push(TTsStage.ClampA);
  Builder.Push(TTsStage.Store);
  var Pipeline := Builder.Compile;

  RunOver(Pipeline, Dst, NoPixmap);

  // (128/255) * (128/255) * 255 = 64.25
  AssertPixel(Dst.Data, 0, 64, 64, 64, 128, 1);
end;

procedure TTsPipelineTests.TestMoveStagesCopyTheColor;
begin
  // The uniform color moves to the destination and back, and the loaded destination (1, 2, 3, 4) is gone
  var Dst := TTsSubPixmapMut.Whole(PixelBytes(1, 2, 3, 4), 1, 1);
  var Builder := TTsRasterPipelineBuilder.New;
  Builder.SetForceHqPipeline(True);
  Builder.PushUniformColor(Opaque(10, 20, 30));
  Builder.Push(TTsStage.LoadDestination);
  Builder.Push(TTsStage.MoveSourceToDestination);
  Builder.Push(TTsStage.MoveDestinationToSource);
  Builder.Push(TTsStage.Store);
  var Pipeline := Builder.Compile;

  RunOver(Pipeline, Dst, NoPixmap);

  AssertPixel(Dst.Data, 0, 10, 20, 30, 255);
end;

procedure TTsPipelineTests.TestSeedShaderAndTransformGather;
begin
  // A 2x2 image: red and green over blue and white
  const Src = Image([255, 0, 0, 255,  0, 255, 0, 255,
                     0, 0, 255, 255,  255, 255, 255, 255], 2, 2);

  // The destination is 10x2, so one full run and a tail of 2. Device x 0..4 samples column 0, 5..9 column 1.
  var Dst := TTsSubPixmapMut.Whole(FilledBytes(20, 0, 0, 0, 0), 10, 2);
  var Builder := TTsRasterPipelineBuilder.New;
  Builder.SetForceHqPipeline(True);
  Builder.Push(TTsStage.SeedShader);
  Builder.PushTransform(TTsTransform.FromScale(0.2, 1));
  Builder.Push(TTsStage.Gather);
  Builder.Push(TTsStage.Store);
  var Pipeline := Builder.Compile;

  RunOver(Pipeline, Dst, Src);

  AssertPixel(Dst.Data, 0, 255, 0, 0, 255);
  AssertPixel(Dst.Data, 4, 255, 0, 0, 255);
  AssertPixel(Dst.Data, 5, 0, 255, 0, 255);
  AssertPixel(Dst.Data, 9, 0, 255, 0, 255);
  AssertPixel(Dst.Data, 10, 0, 0, 255, 255);
  AssertPixel(Dst.Data, 14, 0, 0, 255, 255);
  AssertPixel(Dst.Data, 15, 255, 255, 255, 255);
  AssertPixel(Dst.Data, 19, 255, 255, 255, 255);
end;

procedure TTsPipelineTests.TestRepeatTilesTheCoordinates;
begin
  const Src = Image([255, 0, 0, 255,  0, 255, 0, 255,
                     0, 0, 255, 255,  255, 255, 255, 255], 2, 2);

  var Dst := TTsSubPixmapMut.Whole(FilledBytes(16, 0, 0, 0, 0), 4, 4);
  var Builder := TTsRasterPipelineBuilder.New;
  Builder.SetForceHqPipeline(True);
  Builder.Push(TTsStage.SeedShader);
  Builder.Push(TTsStage.&Repeat);
  Builder.Push(TTsStage.Gather);
  Builder.Push(TTsStage.Store);
  Builder.Ctx.LimitX.Scale := 2;
  Builder.Ctx.LimitX.InvScale := 0.5;
  Builder.Ctx.LimitY.Scale := 2;
  Builder.Ctx.LimitY.InvScale := 0.5;
  var Pipeline := Builder.Compile;

  RunOver(Pipeline, Dst, Src);

  // Columns 0, 1, 0, 1 and rows 0, 1, 0, 1
  AssertPixel(Dst.Data, 0, 255, 0, 0, 255);
  AssertPixel(Dst.Data, 1, 0, 255, 0, 255);
  AssertPixel(Dst.Data, 2, 255, 0, 0, 255);
  AssertPixel(Dst.Data, 3, 0, 255, 0, 255);
  AssertPixel(Dst.Data, 4, 0, 0, 255, 255);
  AssertPixel(Dst.Data, 5, 255, 255, 255, 255);
  AssertPixel(Dst.Data, 10, 255, 0, 0, 255);
  AssertPixel(Dst.Data, 15, 255, 255, 255, 255);
end;

procedure TTsPipelineTests.TestReflectMirrorsTheCoordinates;
begin
  const Src = Image([255, 0, 0, 255,  0, 255, 0, 255,
                     0, 0, 255, 255,  255, 255, 255, 255], 2, 2);

  var Dst := TTsSubPixmapMut.Whole(FilledBytes(16, 0, 0, 0, 0), 4, 4);
  var Builder := TTsRasterPipelineBuilder.New;
  Builder.SetForceHqPipeline(True);
  Builder.Push(TTsStage.SeedShader);
  Builder.Push(TTsStage.Reflect);
  Builder.Push(TTsStage.Gather);
  Builder.Push(TTsStage.Store);
  Builder.Ctx.LimitX.Scale := 2;
  Builder.Ctx.LimitX.InvScale := 0.5;
  Builder.Ctx.LimitY.Scale := 2;
  Builder.Ctx.LimitY.InvScale := 0.5;
  var Pipeline := Builder.Compile;

  RunOver(Pipeline, Dst, Src);

  // Columns 0, 1, 1, 0 and rows 0, 1, 1, 0
  AssertPixel(Dst.Data, 0, 255, 0, 0, 255);
  AssertPixel(Dst.Data, 1, 0, 255, 0, 255);
  AssertPixel(Dst.Data, 2, 0, 255, 0, 255);
  AssertPixel(Dst.Data, 3, 255, 0, 0, 255);
  AssertPixel(Dst.Data, 5, 255, 255, 255, 255);
  AssertPixel(Dst.Data, 10, 255, 255, 255, 255);
  AssertPixel(Dst.Data, 12, 255, 0, 0, 255);
  AssertPixel(Dst.Data, 15, 255, 0, 0, 255);
end;

procedure TTsPipelineTests.TestBilinearHalfwayBetweenTwoPixels;
begin
  // A black and a white pixel; the sample point x = 1 lies exactly between their centers
  const Src = Image([0, 0, 0, 255,  255, 255, 255, 255], 2, 1);

  var Dst := TTsSubPixmapMut.Whole(PixelBytes(0, 0, 0, 0), 1, 1);
  var Builder := TTsRasterPipelineBuilder.New;
  Builder.SetForceHqPipeline(True);
  Builder.Push(TTsStage.SeedShader);
  Builder.PushTransform(TTsTransform.FromTranslate(0.5, 0));
  Builder.Push(TTsStage.Bilinear);
  Builder.Push(TTsStage.Store);
  Builder.Ctx.Sampler.SpreadMode := TTsSpreadMode.Pad;
  Builder.Ctx.Sampler.InvWidth := 0.5;
  Builder.Ctx.Sampler.InvHeight := 1;
  var Pipeline := Builder.Compile;

  RunOver(Pipeline, Dst, Src);

  AssertPixel(Dst.Data, 0, 127, 127, 127, 255, 1);
end;

procedure TTsPipelineTests.TestSamplersKeepAUniformImage;
begin
  // The weights of both filters add up to one, so a uniform image stays as it is, whatever the spread mode
  const Src = Image([100, 50, 25, 200,  100, 50, 25, 200,  100, 50, 25, 200,  100, 50, 25, 200], 2, 2);

  for var Sampler in [TTsStage.Bilinear, TTsStage.Bicubic] do
  begin
    for var Spread := Low(TTsSpreadMode) to High(TTsSpreadMode) do
    begin
      var Dst := TTsSubPixmapMut.Whole(FilledBytes(9, 0, 0, 0, 0), 9, 1);
      var Builder := TTsRasterPipelineBuilder.New;
      Builder.SetForceHqPipeline(True);
      Builder.Push(TTsStage.SeedShader);
      Builder.PushTransform(TTsTransform.FromScale(0.37, 0.37));
      Builder.Push(Sampler);
      Builder.Push(TTsStage.Store);
      Builder.Ctx.Sampler.SpreadMode := Spread;
      Builder.Ctx.Sampler.InvWidth := 0.5;
      Builder.Ctx.Sampler.InvHeight := 0.5;
      var Pipeline := Builder.Compile;

      RunOver(Pipeline, Dst, Src);

      for var I := 0 to 8 do
      begin
        AssertPixel(Dst.Data, I, 100, 50, 25, 200, 1);
      end;
    end;
  end;
end;

procedure TTsPipelineTests.TestNaNCoordinateGathersTheFirstPixel;
begin
  const Src = Image([1, 2, 3, 4,  5, 6, 7, 8], 2, 1);

  var Dst := TTsSubPixmapMut.Whole(FilledBytes(3, 0, 0, 0, 0), 3, 1);
  var Builder := TTsRasterPipelineBuilder.New;
  Builder.SetForceHqPipeline(True);
  Builder.Push(TTsStage.SeedShader);
  // PushTransform would skip a transform that is not finite, so the stage is pushed by hand
  Builder.Push(TTsStage.Transform);
  Builder.Ctx.Transform := TTsTransform.FromRow(NaN, NaN, NaN, NaN, NaN, NaN);
  Builder.Push(TTsStage.Gather);
  Builder.Push(TTsStage.Store);
  var Pipeline := Builder.Compile;

  RunOver(Pipeline, Dst, Src);

  for var I := 0 to 2 do
  begin
    AssertPixel(Dst.Data, I, 1, 2, 3, 4);
  end;
end;

procedure TTsPipelineTests.TestX1StagesNormalize;
begin
  // SeedShader gives x = 0.5, 1.5, 2.5 ...; the x1 stages bring them into 0..1: pad clamps, repeat takes the fraction and reflect mirrors
  var Dst := TTsSubPixmapMut.Whole(FilledBytes(4, 0, 0, 0, 0), 4, 1);
  var Builder := TTsRasterPipelineBuilder.New;
  Builder.SetForceHqPipeline(True);
  Builder.Push(TTsStage.SeedShader);
  Builder.Push(TTsStage.PadX1);
  Builder.Push(TTsStage.Store);
  var Pipeline := Builder.Compile;

  RunOver(Pipeline, Dst, NoPixmap);

  // r = 0.5 for the first pixel and 1 above; g = 0.5 -> 128, b = 1, a = 0
  AssertPixel(Dst.Data, 0, 128, 128, 255, 0, 1);
  AssertPixel(Dst.Data, 1, 255, 128, 255, 0);

  Dst := TTsSubPixmapMut.Whole(FilledBytes(4, 0, 0, 0, 0), 4, 1);
  Builder := TTsRasterPipelineBuilder.New;
  Builder.SetForceHqPipeline(True);
  Builder.Push(TTsStage.SeedShader);
  Builder.Push(TTsStage.RepeatX1);
  Builder.Push(TTsStage.Store);
  Pipeline := Builder.Compile;

  RunOver(Pipeline, Dst, NoPixmap);

  // 0.5, 1.5, 2.5, 3.5 repeat to 0.5
  AssertPixel(Dst.Data, 0, 128, 128, 255, 0, 1);
  AssertPixel(Dst.Data, 3, 128, 128, 255, 0, 1);

  Dst := TTsSubPixmapMut.Whole(FilledBytes(4, 0, 0, 0, 0), 4, 1);
  Builder := TTsRasterPipelineBuilder.New;
  Builder.SetForceHqPipeline(True);
  Builder.Push(TTsStage.SeedShader);
  Builder.Push(TTsStage.ReflectX1);
  Builder.Push(TTsStage.Store);
  Pipeline := Builder.Compile;

  RunOver(Pipeline, Dst, NoPixmap);

  // 0.5 stays, 1.5 mirrors to 0.5, 2.5 to 0.5, 3.5 to 0.5
  AssertPixel(Dst.Data, 0, 128, 128, 255, 0, 1);
  AssertPixel(Dst.Data, 1, 128, 128, 255, 0, 1);
  AssertPixel(Dst.Data, 2, 128, 128, 255, 0, 1);
end;

procedure TTsPipelineTests.TestSourceOverRgbaBlendsOverTheDestination;
begin
  // The stage loads and stores the destination itself; 11 pixels also run its tail variant
  var Dst := TTsSubPixmapMut.Whole(FilledBytes(11, 0, 0, 255, 255), 11, 1);
  var Builder := TTsRasterPipelineBuilder.New;
  Builder.SetForceHqPipeline(True);
  Builder.PushUniformColor(TTsColor.FromRgba8(255, 0, 0, 128).Premultiply);
  Builder.Push(TTsStage.SourceOverRgba);
  var Pipeline := Builder.Compile;

  RunOver(Pipeline, Dst, NoPixmap);

  for var I := 0 to 10 do
  begin
    AssertPixel(Dst.Data, I, 128, 0, 127, 255, 1);
  end;
end;

procedure TTsPipelineTests.TestStageTableHoldsExactlyThePortedStages;
begin
  const NotPorted: set of TTsStage = [TTsStage.Gradient, TTsStage.EvenlySpaced2StopGradient, TTsStage.XYToUnitAngle, TTsStage.XYToRadius,
                     TTsStage.XYTo2PtConicalFocalOnCircle, TTsStage.XYTo2PtConicalWellBehaved, TTsStage.XYTo2PtConicalSmaller,
                     TTsStage.XYTo2PtConicalGreater, TTsStage.XYTo2PtConicalStrip, TTsStage.Mask2PtConicalNan,
                     TTsStage.Mask2PtConicalDegenerates, TTsStage.ApplyVectorMask, TTsStage.Alter2PtConicalCompensateFocal,
                     TTsStage.Alter2PtConicalUnswap, TTsStage.NegateX, TTsStage.ApplyConcentricScaleBias, TTsStage.GammaExpand2,
                     TTsStage.GammaExpandDestination2, TTsStage.GammaCompress2, TTsStage.GammaExpand22,
                     TTsStage.GammaExpandDestination22, TTsStage.GammaCompress22, TTsStage.GammaExpandSrgb,
                     TTsStage.GammaExpandDestinationSrgb, TTsStage.GammaCompressSrgb];

  for var Stage := Low(TTsStage) to High(TTsStage) do
  begin
    const Message = Format('Stage %d', [Ord(Stage)]);
    const IsPorted = not (Stage in NotPorted);
    Assert.AreEqual(IsPorted, Assigned(TTsHighpStages.Table[Stage]), Message);
    Assert.AreEqual(IsPorted, Assigned(TTsHighpStages.TailTable[Stage]), Message);
  end;
end;

procedure TTsPipelineTests.TestPushUniformColorFillsTheContext;
begin
  var Builder := TTsRasterPipelineBuilder.New;

  Builder.PushUniformColor(TTsColor.FromRgba8(255, 128, 0, 128).Premultiply);

  const Ctx = Builder.Ctx.UniformColor;
  Assert.AreEqual(Double(128 / 255), Double(Ctx.A), 1E-6);
  Assert.AreEqual(Double(128 / 255), Double(Ctx.R), 1E-6);
  Assert.AreEqual(Double(0), Double(Ctx.B), 1E-6);
  // (r * 255 + 0.5) as u16
  Assert.AreEqual(128, Integer(Ctx.Rgba[0]));
  Assert.AreEqual(64, Integer(Ctx.Rgba[1]));
  Assert.AreEqual(0, Integer(Ctx.Rgba[2]));
  Assert.AreEqual(128, Integer(Ctx.Rgba[3]));
end;

procedure TTsPipelineTests.TestPushTransformSkipsIdentityAndNonFinite;
begin
  var Builder := TTsRasterPipelineBuilder.New;
  Builder.PushTransform(TTsTransform.Identity);
  Builder.PushTransform(TTsTransform.FromTranslate(Infinity, 0));
  Assert.AreEqual(0, Builder.StageCount);

  Builder.PushTransform(TTsTransform.FromTranslate(3, 4));
  Assert.AreEqual(1, Builder.StageCount);
  Assert.AreEqual(Double(3), Double(Builder.Ctx.Transform.TX), 0.0001);
  Assert.AreEqual(Double(4), Double(Builder.Ctx.Transform.TY), 0.0001);
end;

procedure TTsPipelineTests.TestPushOfAStageWithoutImplementationRaises;
begin
  Assert.WillRaise(PushOutOfRangeStage, EInvalidOpException);
end;

procedure TTsPipelineTests.TestPushBeyondMaxStagesRaises;
begin
  Assert.WillRaise(PushTooManyStages, EInvalidOpException);
end;

procedure TTsPipelineTests.TestEmptyPipelineDrawsNothing;
begin
  var Dst := TTsSubPixmapMut.Whole(PixelBytes(1, 2, 3, 4), 1, 1);
  var Builder := TTsRasterPipelineBuilder.New;
  var Pipeline := Builder.Compile;

  RunOver(Pipeline, Dst, NoPixmap);

  AssertPixel(Dst.Data, 0, 1, 2, 3, 4);
end;

procedure TTsPipelineTests.TestRegionOutsideTheDataDrawsNothing;
begin
  var Dst := TTsSubPixmapMut.Whole(FilledBytes(4, 1, 2, 3, 4), 2, 2);
  var Builder := TTsRasterPipelineBuilder.New;
  Builder.SetForceHqPipeline(True);
  Builder.PushUniformColor(Opaque(255, 0, 0));
  Builder.Push(TTsStage.Store);
  var Pipeline := Builder.Compile;

  // The region is larger than the data: the Rust code would panic, here nothing is drawn
  Pipeline.Run(Region(2, 3), Default(TTsAAMaskCtx), Default(TTsMaskCtx), NoPixmap, Dst);
  Pipeline.Run(Region(9, 1), Default(TTsAAMaskCtx), Default(TTsMaskCtx), NoPixmap, Dst);

  for var I := 0 to 3 do
  begin
    AssertPixel(Dst.Data, I, 1, 2, 3, 4);
  end;
end;

procedure TTsPipelineTests.TestSubPixmapStartsAtItsOffset;
begin
  // A 4x3 parent with a 2x2 region at (1, 1): the pixel (0, 0) of the region is the pixel 5 of the parent
  var Dst := TTsSubPixmapMut.Whole(FilledBytes(12, 9, 9, 9, 9), 4, 3);
  Dst.Offset := 5 * 4;
  Dst.Width := 2;
  Dst.Height := 2;

  var Builder := TTsRasterPipelineBuilder.New;
  Builder.SetForceHqPipeline(True);
  Builder.PushUniformColor(Opaque(255, 0, 0));
  Builder.Push(TTsStage.Store);
  var Pipeline := Builder.Compile;

  RunOver(Pipeline, Dst, NoPixmap);

  for var Index in [5, 6, 9, 10] do
  begin
    AssertPixel(Dst.Data, Index, 255, 0, 0, 255);
  end;

  for var Index in [0, 1, 2, 3, 4, 7, 8, 11] do
  begin
    AssertPixel(Dst.Data, Index, 9, 9, 9, 9);
  end;
end;

end.
