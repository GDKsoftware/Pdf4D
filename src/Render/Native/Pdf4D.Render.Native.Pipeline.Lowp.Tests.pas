// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of tiny-skia v0.12.0 src/pipeline/mod.rs (blend_tests, lowp) and of the low precision stages of src/pipeline/lowp.rs
unit Pdf4D.Render.Native.Pipeline.Lowp.Tests;

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
  Pdf4D.Render.Native.Wide,
  Pdf4D.Render.Native.Stage,
  Pdf4D.Render.Native.BlendMode,
  Pdf4D.Render.Native.Pipeline.Context,
  Pdf4D.Render.Native.Pipeline.Highp,
  Pdf4D.Render.Native.Pipeline.Lowp,
  Pdf4D.Render.Native.Pipeline;

type
  [TestFixture]
  TTsPipelineLowpTests = class
  private
    FFloatState: TTsFloatState;

    function PixelBytes(const R, G, B, A: Byte): TBytes;
    function FilledBytes(const Count: Integer; const R, G, B, A: Byte): TBytes;
    function Region(const Width, Height: Cardinal): TTsScreenIntRect;
    function NoPixmap: TTsPixmapRef;
    procedure RunOver(var Pipeline: TTsRasterPipeline; var Dst: TTsSubPixmapMut);
    procedure AssertPixel(const Data: TBytes; const Index: Integer; const R, G, B, A: Byte; const Tolerance: Integer = 0);
    function CompileSolid(const Stage: TTsStage; const Color: TTsPremultipliedColor; const ForceHq: Boolean): TTsRasterPipeline;
    function BlendOver(const Backdrop: TBytes; const Color: TTsPremultipliedColor; const ForceHq: Boolean): TBytes;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    // test_blend_lowp! of pipeline/mod.rs: the destination is (50, 127, 150, 200), the source (220, 140, 75, 180) premultiplied
    [Test]
    [TestCase('ClearLowp', '0,0,0,0,0')]
    [TestCase('DestinationLowp', '2,39,100,118,200')]
    [TestCase('SourceOverLowp', '3,167,129,88,239')]
    [TestCase('DestinationOverLowp', '4,73,122,130,239')]
    [TestCase('SourceInLowp', '5,122,78,42,141')]
    [TestCase('DestinationInLowp', '6,28,71,83,141')]
    [TestCase('SourceOutLowp', '7,34,22,12,39')]
    [TestCase('DestinationOutLowp', '8,12,30,35,59')]
    [TestCase('SourceAtopLowp', '9,133,107,76,200')]
    [TestCase('DestinationAtopLowp', '10,61,92,95,180')]
    [TestCase('XorLowp', '11,45,51,46,98')]
    [TestCase('PlusLowp', '12,194,199,171,255')]
    [TestCase('ModulateLowp', '13,24,39,25,141')]
    [TestCase('ScreenLowp', '14,170,160,146,239')]
    [TestCase('OverlayLowp', '15,92,128,106,239')]
    [TestCase('DarkenLowp', '16,72,121,88,239')]
    [TestCase('LightenLowp', '17,166,128,129,239')]
    [TestCase('HardLightLowp', '20,154,128,95,239')]
    [TestCase('DifferenceLowp', '22,138,57,87,239')]
    [TestCase('ExclusionLowp', '23,146,121,121,239')]
    [TestCase('MultiplyLowp', '24,69,90,71,238')]
    procedure TestBlendLowp(const Mode, R, G, B, A: Integer);

    [Test]
    procedure TestLowpChosenForSolidSourceOver;

    [Test]
    procedure TestHighpForHue;

    [Test]
    procedure TestHighpForEveryStageWithoutLowp;

    [Test]
    procedure TestForceHqPipelineUsesHighp;

    [Test]
    procedure TestEmptyPipelineIsHighp;

    [Test]
    procedure TestLowpTableHoldsTheStagesOfLowpRs;

    [Test]
    procedure TestLowpDiv255;

    [Test]
    procedure TestLowpAndHighpSourceOverDifferAtMostOne;

    [Test]
    procedure TestLowpLoadStoreRoundTripWithTail;

    [Test]
    procedure TestLowpCoversTheTailOfTheRow;

    [Test]
    procedure TestLowpScaleAndLerpOfTheCoverage;

    [Test]
    procedure TestLowpAntiAliasMasks;

    [Test]
    procedure TestLowpMaskU8;

    [Test]
    procedure TestLowpA8PixmapRoundTrip;

    [Test]
    procedure TestLowpLoadMaskU8;

    [Test]
    procedure TestLowpSourceOverRgba;

    [Test]
    procedure TestLowpSeedShaderAndTransformKeepTheFloatBits;

    [Test]
    procedure TestLowpX1StagesNormalize;

    [Test]
    procedure TestLowpRegionOutsideTheDataDrawsNothing;

    [Test]
    procedure TestLowpSubPixmapStartsAtItsOffset;
  end;

implementation

{ TTsPipelineLowpTests }

procedure TTsPipelineLowpTests.Setup;
begin
  FFloatState := TTsFloatMode.Enter;
end;

procedure TTsPipelineLowpTests.TearDown;
begin
  TTsFloatMode.Leave(FFloatState);
end;

function TTsPipelineLowpTests.PixelBytes(const R, G, B, A: Byte): TBytes;
begin
  Result := [R, G, B, A];
end;

function TTsPipelineLowpTests.FilledBytes(const Count: Integer; const R, G, B, A: Byte): TBytes;
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

function TTsPipelineLowpTests.Region(const Width, Height: Cardinal): TTsScreenIntRect;
begin
  Result := TTsScreenIntRect.FromXYWHSafe(0, 0, Width, Height);
end;

function TTsPipelineLowpTests.NoPixmap: TTsPixmapRef;
begin
  Result := Default(TTsPixmapRef);
end;

procedure TTsPipelineLowpTests.RunOver(var Pipeline: TTsRasterPipeline; var Dst: TTsSubPixmapMut);
begin
  Pipeline.Run(Region(Dst.Width, Dst.Height), Default(TTsAAMaskCtx), Default(TTsMaskCtx), NoPixmap, Dst);
end;

procedure TTsPipelineLowpTests.AssertPixel(const Data: TBytes; const Index: Integer; const R, G, B, A: Byte; const Tolerance: Integer);
begin
  const Message = Format('Pixel %d is (%d,%d,%d,%d), expected (%d,%d,%d,%d)',
                         [Index, Data[Index * 4], Data[Index * 4 + 1], Data[Index * 4 + 2], Data[Index * 4 + 3], R, G, B, A]);
  Assert.AreEqual(Integer(R), Integer(Data[Index * 4]), Tolerance, Message);
  Assert.AreEqual(Integer(G), Integer(Data[Index * 4 + 1]), Tolerance, Message);
  Assert.AreEqual(Integer(B), Integer(Data[Index * 4 + 2]), Tolerance, Message);
  Assert.AreEqual(Integer(A), Integer(Data[Index * 4 + 3]), Tolerance, Message);
end;

function TTsPipelineLowpTests.CompileSolid(const Stage: TTsStage; const Color: TTsPremultipliedColor;
  const ForceHq: Boolean): TTsRasterPipeline;
begin
  var Builder := TTsRasterPipelineBuilder.New;
  Builder.SetForceHqPipeline(ForceHq);
  Builder.PushUniformColor(Color);
  Builder.Push(TTsStage.LoadDestination);
  Builder.Push(Stage);
  Builder.Push(TTsStage.Store);
  Result := Builder.Compile;
end;

function TTsPipelineLowpTests.BlendOver(const Backdrop: TBytes; const Color: TTsPremultipliedColor; const ForceHq: Boolean): TBytes;
begin
  var Pipeline := CompileSolid(TTsStage.SourceOver, Color, ForceHq);
  var Dst := TTsSubPixmapMut.Whole(Copy(Backdrop), 1, 1);

  RunOver(Pipeline, Dst);

  Result := Dst.Data;
end;

procedure TTsPipelineLowpTests.TestBlendLowp(const Mode, R, G, B, A: Integer);
begin
  const Backdrop = TTsColor.FromRgba8(50, 127, 150, 200).Premultiply.ToColorU8;
  var Dst := TTsSubPixmapMut.Whole(PixelBytes(Backdrop.Red, Backdrop.Green, Backdrop.Blue, Backdrop.Alpha), 1, 1);

  const BlendMode = TTsBlendMode(Mode);
  var Stage: TTsStage;
  Assert.IsTrue(BlendMode.TryToStage(Stage));

  var Pipeline := CompileSolid(Stage, TTsColor.FromRgba8(220, 140, 75, 180).Premultiply, False);
  Assert.AreEqual(Ord(TTsPipelineKind.Lowp), Ord(Pipeline.Kind));

  RunOver(Pipeline, Dst);

  AssertPixel(Dst.Data, 0, R, G, B, A);
end;

procedure TTsPipelineLowpTests.TestLowpChosenForSolidSourceOver;
begin
  const Pipeline = CompileSolid(TTsStage.SourceOver, TTsColor.FromRgba8(255, 0, 0, 255).Premultiply, False);

  Assert.AreEqual(Ord(TTsPipelineKind.Lowp), Ord(Pipeline.Kind));
end;

procedure TTsPipelineLowpTests.TestHighpForHue;
begin
  const Pipeline = CompileSolid(TTsStage.Hue, TTsColor.FromRgba8(255, 0, 0, 255).Premultiply, False);

  Assert.AreEqual(Ord(TTsPipelineKind.Highp), Ord(Pipeline.Kind));
end;

procedure TTsPipelineLowpTests.TestHighpForEveryStageWithoutLowp;
begin
  const WithoutLowp: TArray<TTsStage> = [TTsStage.Clamp0, TTsStage.ClampA, TTsStage.Gather, TTsStage.ColorBurn, TTsStage.ColorDodge,
                                         TTsStage.SoftLight, TTsStage.Hue, TTsStage.Saturation, TTsStage.Color, TTsStage.Luminosity,
                                         TTsStage.Reflect, TTsStage.&Repeat, TTsStage.Bilinear, TTsStage.Bicubic];

  for var Stage in WithoutLowp do
  begin
    var Builder := TTsRasterPipelineBuilder.New;
    Builder.Push(TTsStage.UniformColor);
    Builder.Push(Stage);
    const Pipeline = Builder.Compile;

    Assert.AreEqual(Ord(TTsPipelineKind.Highp), Ord(Pipeline.Kind), Format('Stage %d', [Ord(Stage)]));
  end;
end;

procedure TTsPipelineLowpTests.TestForceHqPipelineUsesHighp;
begin
  const Pipeline = CompileSolid(TTsStage.SourceOver, TTsColor.FromRgba8(255, 0, 0, 255).Premultiply, True);

  Assert.AreEqual(Ord(TTsPipelineKind.Highp), Ord(Pipeline.Kind));
end;

procedure TTsPipelineLowpTests.TestEmptyPipelineIsHighp;
begin
  var Builder := TTsRasterPipelineBuilder.New;
  const Pipeline = Builder.Compile;

  Assert.AreEqual(Ord(TTsPipelineKind.Highp), Ord(Pipeline.Kind));
end;

procedure TTsPipelineLowpTests.TestLowpTableHoldsTheStagesOfLowpRs;
begin
  // The stages that lowp.rs has a function for, among the ported stages: every other entry is null_fn
  const WithLowp: set of TTsStage = [
    TTsStage.MoveSourceToDestination, TTsStage.MoveDestinationToSource, TTsStage.Premultiply, TTsStage.UniformColor,
    TTsStage.SeedShader, TTsStage.LoadDestination, TTsStage.Store, TTsStage.LoadDestinationU8, TTsStage.StoreU8,
    TTsStage.LoadMaskU8, TTsStage.MaskU8, TTsStage.ScaleU8, TTsStage.LerpU8, TTsStage.Scale1Float, TTsStage.Lerp1Float,
    TTsStage.DestinationAtop, TTsStage.DestinationIn, TTsStage.DestinationOut, TTsStage.DestinationOver, TTsStage.SourceAtop,
    TTsStage.SourceIn, TTsStage.SourceOut, TTsStage.SourceOver, TTsStage.Clear, TTsStage.Modulate, TTsStage.Multiply,
    TTsStage.Plus, TTsStage.Screen, TTsStage.&Xor, TTsStage.Darken, TTsStage.Difference, TTsStage.Exclusion, TTsStage.HardLight,
    TTsStage.Lighten, TTsStage.Overlay, TTsStage.SourceOverRgba, TTsStage.Transform, TTsStage.PadX1, TTsStage.ReflectX1,
    TTsStage.RepeatX1];

  for var Stage := Low(TTsStage) to High(TTsStage) do
  begin
    const ExpectsLowp = (Stage in WithLowp);
    Assert.AreEqual(ExpectsLowp, TTsLowpStages.HasStage(Stage), Format('Stage %d', [Ord(Stage)]));
    Assert.AreEqual(ExpectsLowp, Assigned(TTsLowpStages.TailTable[Stage]), Format('Tail of stage %d', [Ord(Stage)]));
  end;
end;

procedure TTsPipelineLowpTests.TestLowpDiv255;
begin
  const Input = TU16x16.FromArray([65025, 32640, 0, 255, 254, 1, 128, 65535, 0, 0, 0, 0, 0, 0, 0, 0]);

  const Output = TTsLowpStages.Div255(Input);

  Assert.AreEqual(255, Integer(Output.Lanes[0]));
  Assert.AreEqual(128, Integer(Output.Lanes[1]));
  Assert.AreEqual(0, Integer(Output.Lanes[2]));
  // (v + 255) >> 8
  Assert.AreEqual(1, Integer(Output.Lanes[3]));
  Assert.AreEqual(1, Integer(Output.Lanes[4]));
  Assert.AreEqual(1, Integer(Output.Lanes[5]));
  Assert.AreEqual(1, Integer(Output.Lanes[6]));
  // 65535 + 255 wraps to 254 in a u16
  Assert.AreEqual(0, Integer(Output.Lanes[7]));
end;

procedure TTsPipelineLowpTests.TestLowpAndHighpSourceOverDifferAtMostOne;
begin
  for var Alpha := 0 to 255 do
  begin
    // The source is red 200 with the alpha, premultiplied
    const Color = TTsColor.FromRgba8(200, 0, 0, Alpha).Premultiply;
    const Backdrop = PixelBytes(50, 50, 50, 255);

    const Low = BlendOver(Backdrop, Color, False);
    const High = BlendOver(Backdrop, Color, True);

    for var Channel := 0 to 3 do
    begin
      const Message = Format('Alpha %d, channel %d: lowp %d, highp %d', [Alpha, Channel, Low[Channel], High[Channel]]);
      Assert.AreEqual(Integer(High[Channel]), Integer(Low[Channel]), 1, Message);
    end;
  end;
end;

procedure TTsPipelineLowpTests.TestLowpLoadStoreRoundTripWithTail;
begin
  // 16 + 16 + 5 pixels: two full runs and a tail of 5
  var Bytes: TBytes;
  SetLength(Bytes, 37 * 4);
  for var I := 0 to High(Bytes) do
  begin
    Bytes[I] := (I * 53 + 7) and 255;
  end;
  const Expected = Copy(Bytes);

  var Dst := TTsSubPixmapMut.Whole(Bytes, 37, 1);
  var Builder := TTsRasterPipelineBuilder.New;
  Builder.Push(TTsStage.LoadDestination);
  Builder.Push(TTsStage.MoveDestinationToSource);
  Builder.Push(TTsStage.Store);
  var Pipeline := Builder.Compile;
  Assert.AreEqual(Ord(TTsPipelineKind.Lowp), Ord(Pipeline.Kind));

  RunOver(Pipeline, Dst);

  for var I := 0 to High(Expected) do
  begin
    Assert.AreEqual(Integer(Expected[I]), Integer(Dst.Data[I]), Format('Byte %d changed', [I]));
  end;
end;

procedure TTsPipelineLowpTests.TestLowpCoversTheTailOfTheRow;
begin
  // 3 rows of 21 pixels with a 2 pixel gap on the right: only the region is drawn, and its last run has 5 pixels
  var Dst := TTsSubPixmapMut.Whole(FilledBytes(23 * 3, 9, 9, 9, 9), 23, 3);
  var Builder := TTsRasterPipelineBuilder.New;
  Builder.PushUniformColor(TTsColor.FromRgba8(255, 0, 0, 255).Premultiply);
  Builder.Push(TTsStage.Store);
  var Pipeline := Builder.Compile;
  Assert.AreEqual(Ord(TTsPipelineKind.Lowp), Ord(Pipeline.Kind));

  Pipeline.Run(Region(21, 3), Default(TTsAAMaskCtx), Default(TTsMaskCtx), NoPixmap, Dst);

  for var Y := 0 to 2 do
  begin
    for var X := 0 to 22 do
    begin
      if X < 21 then
      begin
        AssertPixel(Dst.Data, Y * 23 + X, 255, 0, 0, 255);
      end
      else
      begin
        AssertPixel(Dst.Data, Y * 23 + X, 9, 9, 9, 9);
      end;
    end;
  end;
end;

procedure TTsPipelineLowpTests.TestLowpScaleAndLerpOfTheCoverage;
begin
  // Scale1Float: from_float(0.5) = 128, so the red 255 becomes div255(255 * 128) = 128
  var Dst := TTsSubPixmapMut.Whole(PixelBytes(0, 0, 0, 0), 1, 1);
  var Builder := TTsRasterPipelineBuilder.New;
  Builder.PushUniformColor(TTsColor.FromRgba8(255, 0, 0, 255).Premultiply);
  Builder.Push(TTsStage.Scale1Float);
  Builder.Push(TTsStage.Store);
  Builder.Ctx.CurrentCoverage := 0.5;
  var Pipeline := Builder.Compile;
  Assert.AreEqual(Ord(TTsPipelineKind.Lowp), Ord(Pipeline.Kind));

  RunOver(Pipeline, Dst);

  AssertPixel(Dst.Data, 0, 128, 0, 0, 128);

  // Lerp1Float between blue and red
  Dst := TTsSubPixmapMut.Whole(PixelBytes(0, 0, 255, 255), 1, 1);
  Builder := TTsRasterPipelineBuilder.New;
  Builder.PushUniformColor(TTsColor.FromRgba8(255, 0, 0, 255).Premultiply);
  Builder.Push(TTsStage.LoadDestination);
  Builder.Push(TTsStage.Lerp1Float);
  Builder.Push(TTsStage.Store);
  Builder.Ctx.CurrentCoverage := 0.5;
  Pipeline := Builder.Compile;

  RunOver(Pipeline, Dst);

  AssertPixel(Dst.Data, 0, 128, 0, 127, 255, 1);

  // A coverage above 1 saturates to a u16 and a NaN gives 0
  Dst := TTsSubPixmapMut.Whole(PixelBytes(0, 0, 255, 255), 1, 1);
  Builder := TTsRasterPipelineBuilder.New;
  Builder.PushUniformColor(TTsColor.FromRgba8(255, 0, 0, 255).Premultiply);
  Builder.Push(TTsStage.Scale1Float);
  Builder.Push(TTsStage.Store);
  Builder.Ctx.CurrentCoverage := NaN;
  Pipeline := Builder.Compile;

  RunOver(Pipeline, Dst);

  AssertPixel(Dst.Data, 0, 0, 0, 0, 0);
end;

procedure TTsPipelineLowpTests.TestLowpAntiAliasMasks;
begin
  // ScaleU8 over two pixels
  var Dst := TTsSubPixmapMut.Whole(FilledBytes(2, 0, 0, 0, 0), 2, 1);
  var Builder := TTsRasterPipelineBuilder.New;
  Builder.PushUniformColor(TTsColor.FromRgba8(255, 0, 0, 255).Premultiply);
  Builder.Push(TTsStage.ScaleU8);
  Builder.Push(TTsStage.Store);
  var Pipeline := Builder.Compile;
  Assert.AreEqual(Ord(TTsPipelineKind.Lowp), Ord(Pipeline.Kind));

  var AAMask := Default(TTsAAMaskCtx);
  AAMask.Pixels[0] := 255;
  AAMask.Pixels[1] := 128;
  Pipeline.Run(Region(2, 1), AAMask, Default(TTsMaskCtx), NoPixmap, Dst);

  AssertPixel(Dst.Data, 0, 255, 0, 0, 255);
  AssertPixel(Dst.Data, 1, 128, 0, 0, 128);

  // LerpU8 on the second pixel only: the mask starts one pixel before the run, so the run reads the second byte
  Dst := TTsSubPixmapMut.Whole(FilledBytes(2, 0, 0, 255, 255), 2, 1);
  Builder := TTsRasterPipelineBuilder.New;
  Builder.PushUniformColor(TTsColor.FromRgba8(255, 0, 0, 255).Premultiply);
  Builder.Push(TTsStage.LoadDestination);
  Builder.Push(TTsStage.LerpU8);
  Builder.Push(TTsStage.Store);
  Pipeline := Builder.Compile;

  AAMask.Pixels[0] := 0;
  AAMask.Pixels[1] := 255;
  AAMask.Shift := 0;
  Pipeline.Run(TTsScreenIntRect.FromXYWHSafe(1, 0, 1, 1), AAMask, Default(TTsMaskCtx), NoPixmap, Dst);

  AssertPixel(Dst.Data, 0, 0, 0, 255, 255);
  AssertPixel(Dst.Data, 1, 255, 0, 0, 255);
end;

procedure TTsPipelineLowpTests.TestLowpMaskU8;
begin
  // 21 pixels: a run of 16 with a zero mask, which is not stored, and a tail of 5 with a full mask
  var Dst := TTsSubPixmapMut.Whole(FilledBytes(21, 9, 9, 9, 9), 21, 1);

  var Builder := TTsRasterPipelineBuilder.New;
  Builder.PushUniformColor(TTsColor.FromRgba8(255, 0, 0, 255).Premultiply);
  Builder.Push(TTsStage.MaskU8);
  Builder.Push(TTsStage.Store);
  var Pipeline := Builder.Compile;
  Assert.AreEqual(Ord(TTsPipelineKind.Lowp), Ord(Pipeline.Kind));

  var Mask := Default(TTsMaskCtx);
  SetLength(Mask.Data, 21);
  for var I := 16 to 20 do
  begin
    Mask.Data[I] := 255;
  end;
  Mask.RealWidth := 21;
  Pipeline.Run(Region(21, 1), Default(TTsAAMaskCtx), Mask, NoPixmap, Dst);

  for var I := 0 to 15 do
  begin
    AssertPixel(Dst.Data, I, 9, 9, 9, 9);
  end;

  for var I := 16 to 20 do
  begin
    AssertPixel(Dst.Data, I, 255, 0, 0, 255);
  end;
end;

procedure TTsPipelineLowpTests.TestLowpA8PixmapRoundTrip;
begin
  // The destination has one byte per pixel; 37 pixels are two runs and a tail of 5
  var Bytes: TBytes;
  SetLength(Bytes, 37);
  for var I := 0 to High(Bytes) do
  begin
    Bytes[I] := (I * 7 + 3) and 255;
  end;
  const Expected = Copy(Bytes);

  var Dst := TTsSubPixmapMut.Whole(Bytes, 37, 1);
  var Builder := TTsRasterPipelineBuilder.New;
  Builder.Push(TTsStage.LoadDestinationU8);
  Builder.Push(TTsStage.MoveDestinationToSource);
  Builder.Push(TTsStage.StoreU8);
  var Pipeline := Builder.Compile;
  Assert.AreEqual(Ord(TTsPipelineKind.Lowp), Ord(Pipeline.Kind));

  RunOver(Pipeline, Dst);

  for var I := 0 to High(Expected) do
  begin
    Assert.AreEqual(Integer(Expected[I]), Integer(Dst.Data[I]), Format('Byte %d changed', [I]));
  end;

  // The region must fit the bytes of the A8 pixmap, not four bytes per pixel
  Dst := TTsSubPixmapMut.Whole(Copy(Expected), 37, 1);
  Builder := TTsRasterPipelineBuilder.New;
  Builder.PushUniformColor(TTsColor.FromRgba8(0, 0, 0, 255).Premultiply);
  Builder.Push(TTsStage.StoreU8);
  Pipeline := Builder.Compile;

  RunOver(Pipeline, Dst);

  for var I := 0 to High(Expected) do
  begin
    Assert.AreEqual(255, Integer(Dst.Data[I]), Format('Byte %d', [I]));
  end;
end;

procedure TTsPipelineLowpTests.TestLowpLoadMaskU8;
begin
  // LoadMaskU8 puts the mask in the alpha and clears the color
  var Dst := TTsSubPixmapMut.Whole(FilledBytes(3, 9, 9, 9, 9), 3, 1);
  var Builder := TTsRasterPipelineBuilder.New;
  Builder.PushUniformColor(TTsColor.FromRgba8(255, 0, 0, 255).Premultiply);
  Builder.Push(TTsStage.LoadMaskU8);
  Builder.Push(TTsStage.Store);
  var Pipeline := Builder.Compile;

  var Mask := Default(TTsMaskCtx);
  Mask.Data := [10, 20, 30];
  Mask.RealWidth := 3;
  Pipeline.Run(Region(3, 1), Default(TTsAAMaskCtx), Mask, NoPixmap, Dst);

  AssertPixel(Dst.Data, 0, 0, 0, 0, 10);
  AssertPixel(Dst.Data, 1, 0, 0, 0, 20);
  AssertPixel(Dst.Data, 2, 0, 0, 0, 30);
end;

procedure TTsPipelineLowpTests.TestLowpSourceOverRgba;
begin
  // The stage loads and stores the destination itself; 21 pixels also run its tail variant
  var Dst := TTsSubPixmapMut.Whole(FilledBytes(21, 0, 0, 255, 255), 21, 1);
  var Builder := TTsRasterPipelineBuilder.New;
  Builder.PushUniformColor(TTsColor.FromRgba8(255, 0, 0, 128).Premultiply);
  Builder.Push(TTsStage.SourceOverRgba);
  var Pipeline := Builder.Compile;
  Assert.AreEqual(Ord(TTsPipelineKind.Lowp), Ord(Pipeline.Kind));

  RunOver(Pipeline, Dst);

  for var I := 0 to 20 do
  begin
    AssertPixel(Dst.Data, I, 128, 0, 127, 255, 1);
  end;
end;

procedure TTsPipelineLowpTests.TestLowpSeedShaderAndTransformKeepTheFloatBits;
begin
  // The coordinates are f32 bits in the u16 lanes: the register r holds x of the pixels 0..7, g those of 8..15, and a u16 lane is half a
  // float. Stored, a pixel shows the low byte of its lane. x = 1.5 is 0x3FC00000, 2.5 is 0x40200000, 3.5 is 0x40600000, 9.5 is 0x41180000.
  var Dst := TTsSubPixmapMut.Whole(FilledBytes(16, 0, 0, 0, 0), 16, 1);
  var Builder := TTsRasterPipelineBuilder.New;
  Builder.Push(TTsStage.SeedShader);
  Builder.PushTransform(TTsTransform.FromTranslate(1, 0));
  Builder.Push(TTsStage.Store);
  var Pipeline := Builder.Compile;
  Assert.AreEqual(Ord(TTsPipelineKind.Lowp), Ord(Pipeline.Kind));

  RunOver(Pipeline, Dst);

  Assert.AreEqual($00, Integer(Dst.Data[0 * 4]));
  Assert.AreEqual($C0, Integer(Dst.Data[1 * 4]));
  Assert.AreEqual($20, Integer(Dst.Data[3 * 4]));
  Assert.AreEqual($60, Integer(Dst.Data[5 * 4]));
  Assert.AreEqual($18, Integer(Dst.Data[1 * 4 + 1]));
end;

procedure TTsPipelineLowpTests.TestLowpX1StagesNormalize;
begin
  // x = 0.5 (0x3F000000), 1.5, 2.5 ...: pad clamps all but the first to 1.0 (0x3F800000), repeat and reflect bring them to 0.5
  const Stages: TArray<TTsStage> = [TTsStage.PadX1, TTsStage.RepeatX1, TTsStage.ReflectX1];
  const ExpectedForSecondFloat: TArray<Integer> = [$80, $00, $00];

  for var I := 0 to High(Stages) do
  begin
    var Dst := TTsSubPixmapMut.Whole(FilledBytes(16, 0, 0, 0, 0), 16, 1);
    var Builder := TTsRasterPipelineBuilder.New;
    Builder.Push(TTsStage.SeedShader);
    Builder.Push(Stages[I]);
    Builder.Push(TTsStage.Store);
    var Pipeline := Builder.Compile;
    Assert.AreEqual(Ord(TTsPipelineKind.Lowp), Ord(Pipeline.Kind));

    RunOver(Pipeline, Dst);

    // The high half of the second float is the lane 3
    Assert.AreEqual($00, Integer(Dst.Data[1 * 4]), Format('Stage %d, first float', [Ord(Stages[I])]));
    Assert.AreEqual(ExpectedForSecondFloat[I], Integer(Dst.Data[3 * 4]), Format('Stage %d, second float', [Ord(Stages[I])]));
  end;
end;

procedure TTsPipelineLowpTests.TestLowpRegionOutsideTheDataDrawsNothing;
begin
  var Dst := TTsSubPixmapMut.Whole(FilledBytes(4, 1, 2, 3, 4), 2, 2);
  var Builder := TTsRasterPipelineBuilder.New;
  Builder.PushUniformColor(TTsColor.FromRgba8(255, 0, 0, 255).Premultiply);
  Builder.Push(TTsStage.Store);
  var Pipeline := Builder.Compile;

  Pipeline.Run(Region(2, 3), Default(TTsAAMaskCtx), Default(TTsMaskCtx), NoPixmap, Dst);
  Pipeline.Run(Region(40, 1), Default(TTsAAMaskCtx), Default(TTsMaskCtx), NoPixmap, Dst);

  for var I := 0 to 3 do
  begin
    AssertPixel(Dst.Data, I, 1, 2, 3, 4);
  end;
end;

procedure TTsPipelineLowpTests.TestLowpSubPixmapStartsAtItsOffset;
begin
  // A 4x3 parent with a 2x2 region at (1, 1)
  var Dst := TTsSubPixmapMut.Whole(FilledBytes(12, 9, 9, 9, 9), 4, 3);
  Dst.Offset := 5 * 4;
  Dst.Width := 2;
  Dst.Height := 2;

  var Builder := TTsRasterPipelineBuilder.New;
  Builder.PushUniformColor(TTsColor.FromRgba8(255, 0, 0, 255).Premultiply);
  Builder.Push(TTsStage.Store);
  var Pipeline := Builder.Compile;
  Assert.AreEqual(Ord(TTsPipelineKind.Lowp), Ord(Pipeline.Kind));

  RunOver(Pipeline, Dst);

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
