// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of tiny-skia v0.12.0 src/blend_mode.rs
unit Pdf4D.Render.Native.BlendMode.Tests;

{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  System.TypInfo,
  DUnitX.TestFramework,
  Pdf4D.Render.Native.Stage,
  Pdf4D.Render.Native.BlendMode;

type
  [TestFixture]
  TTsBlendModeTests = class
  public
    [Test]
    procedure TestBlendModeHasTheValuesOfTinySkiaInOrder;

    [Test]
    [TestCase('SourceOver', 'SourceOver,True')]
    [TestCase('Destination', 'Destination,True')]
    [TestCase('DestinationOver', 'DestinationOver,True')]
    [TestCase('Plus', 'Plus,True')]
    [TestCase('DestinationOut', 'DestinationOut,True')]
    [TestCase('SourceAtop', 'SourceAtop,True')]
    [TestCase('Xor', 'Xor,True')]
    [TestCase('Multiply', 'Multiply,False')]
    [TestCase('Hue', 'Hue,False')]
    [TestCase('Source', 'Source,False')]
    [TestCase('Clear', 'Clear,False')]
    [TestCase('DestinationAtop', 'DestinationAtop,False')]
    [TestCase('Luminosity', 'Luminosity,False')]
    procedure TestShouldPreScaleCoverage(const Mode: TTsBlendMode; const Expected: Boolean);

    [Test]
    procedure TestSourceHasNoStage;

    [Test]
    procedure TestEveryOtherModeHasItsOwnStage;

    [Test]
    procedure TestDestinationMovesDestinationToSource;

    [Test]
    procedure TestStageEnumKeepsTheOrderOfTinySkia;
  end;

implementation

{ TTsBlendModeTests }

procedure TTsBlendModeTests.TestBlendModeHasTheValuesOfTinySkiaInOrder;
begin
  const Names: TArray<string> = ['Clear', 'Source', 'Destination', 'SourceOver', 'DestinationOver', 'SourceIn', 'DestinationIn', 'SourceOut',
                                 'DestinationOut', 'SourceAtop', 'DestinationAtop', 'Xor', 'Plus', 'Modulate', 'Screen', 'Overlay', 'Darken',
                                 'Lighten', 'ColorDodge', 'ColorBurn', 'HardLight', 'SoftLight', 'Difference', 'Exclusion', 'Multiply', 'Hue',
                                 'Saturation', 'Color', 'Luminosity'];

  Assert.AreEqual<Integer>(29, Length(Names));
  Assert.AreEqual<Integer>(Length(Names) - 1, Ord(High(TTsBlendMode)));
  for var Index := 0 to High(Names) do
  begin
    Assert.AreEqual(Names[Index], GetEnumName(TypeInfo(TTsBlendMode), Index));
  end;
end;

procedure TTsBlendModeTests.TestShouldPreScaleCoverage(const Mode: TTsBlendMode; const Expected: Boolean);
begin
  const Actual = Mode.ShouldPreScaleCoverage;

  Assert.AreEqual(Expected, Actual);
end;

procedure TTsBlendModeTests.TestSourceHasNoStage;
begin
  var Stage: TTsStage;

  Assert.IsFalse(TTsBlendMode.Source.TryToStage(Stage));
end;

procedure TTsBlendModeTests.TestEveryOtherModeHasItsOwnStage;
begin
  for var Mode := Low(TTsBlendMode) to High(TTsBlendMode) do
  begin
    var Stage: TTsStage;
    const HasStage = Mode.TryToStage(Stage);

    if Mode = TTsBlendMode.Source then
    begin
      Assert.IsFalse(HasStage);
    end
    else if Mode = TTsBlendMode.Destination then
    begin
      Assert.IsTrue(HasStage);
      Assert.AreEqual(Ord(TTsStage.MoveDestinationToSource), Ord(Stage));
    end
    else
    begin
      Assert.IsTrue(HasStage, GetEnumName(TypeInfo(TTsBlendMode), Ord(Mode)));
      Assert.AreEqual(GetEnumName(TypeInfo(TTsBlendMode), Ord(Mode)), GetEnumName(TypeInfo(TTsStage), Ord(Stage)));
    end;
  end;
end;

procedure TTsBlendModeTests.TestDestinationMovesDestinationToSource;
begin
  var Stage: TTsStage;

  Assert.IsTrue(TTsBlendMode.Destination.TryToStage(Stage));
  Assert.AreEqual(Ord(TTsStage.MoveDestinationToSource), Ord(Stage));
end;

procedure TTsBlendModeTests.TestStageEnumKeepsTheOrderOfTinySkia;
begin
  Assert.AreEqual(0, Ord(TTsStage.MoveSourceToDestination));
  Assert.AreEqual(25, Ord(TTsStage.SourceOver));
  Assert.AreEqual(44, Ord(TTsStage.Luminosity));
  Assert.AreEqual(45, Ord(TTsStage.SourceOverRgba));
  Assert.AreEqual(50, Ord(TTsStage.Bicubic));
  Assert.AreEqual(78, Ord(TTsStage.GammaCompressSrgb));

  // The 79 stages of tiny-skia in their order, then the two additions of Pdf4D at the end
  const Names: TArray<string> = [
    'MoveSourceToDestination', 'MoveDestinationToSource', 'Clamp0', 'ClampA', 'Premultiply', 'UniformColor', 'SeedShader',
    'LoadDestination', 'Store', 'LoadDestinationU8', 'StoreU8', 'Gather', 'LoadMaskU8', 'MaskU8', 'ScaleU8', 'LerpU8', 'Scale1Float',
    'Lerp1Float', 'DestinationAtop', 'DestinationIn', 'DestinationOut', 'DestinationOver', 'SourceAtop', 'SourceIn', 'SourceOut',
    'SourceOver', 'Clear', 'Modulate', 'Multiply', 'Plus', 'Screen', 'Xor', 'ColorBurn', 'ColorDodge', 'Darken', 'Difference',
    'Exclusion', 'HardLight', 'Lighten', 'Overlay', 'SoftLight', 'Hue', 'Saturation', 'Color', 'Luminosity', 'SourceOverRgba',
    'Transform', 'Reflect', 'Repeat', 'Bilinear', 'Bicubic', 'PadX1', 'ReflectX1', 'RepeatX1', 'Gradient', 'EvenlySpaced2StopGradient',
    'XYToUnitAngle', 'XYToRadius', 'XYTo2PtConicalFocalOnCircle', 'XYTo2PtConicalWellBehaved', 'XYTo2PtConicalSmaller',
    'XYTo2PtConicalGreater', 'XYTo2PtConicalStrip', 'Mask2PtConicalNan', 'Mask2PtConicalDegenerates', 'ApplyVectorMask',
    'Alter2PtConicalCompensateFocal', 'Alter2PtConicalUnswap', 'NegateX', 'ApplyConcentricScaleBias', 'GammaExpand2',
    'GammaExpandDestination2', 'GammaCompress2', 'GammaExpand22', 'GammaExpandDestination22', 'GammaCompress22', 'GammaExpandSrgb',
    'GammaExpandDestinationSrgb', 'GammaCompressSrgb',
    'DecalXY', 'CheckDecalMask'];

  Assert.AreEqual<Integer>(81, Length(Names));
  Assert.AreEqual<Integer>(Length(Names), Ord(High(TTsStage)) + 1);
  for var Index := 0 to High(Names) do
  begin
    Assert.AreEqual(Names[Index], GetEnumName(TypeInfo(TTsStage), Index));
  end;
end;

end.
