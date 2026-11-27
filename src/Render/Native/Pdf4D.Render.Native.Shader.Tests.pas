// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of the pipeline blitter (src/pipeline/blitter.rs), the pattern shader (src/shaders/pattern.rs) with its Decal spread mode, and of the
// pixmap and the mask (src/pixmap.rs, src/mask.rs)
unit Pdf4D.Render.Native.Shader.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.Transform,
  Pdf4D.Render.Native.Color,
  Pdf4D.Render.Native.BlendMode,
  Pdf4D.Render.Native.AlphaRuns,
  Pdf4D.Render.Native.Pixmap,
  Pdf4D.Render.Native.Mask,
  Pdf4D.Render.Native.Pipeline.Context,
  Pdf4D.Render.Native.Shader,
  Pdf4D.Render.Native.Pipeline.Blitter;

type
  [TestFixture]
  TTsShaderTests = class
  private
    FFloatState: TTsFloatState;

    function NewPixmap(const Width, Height: Cardinal): TTsPixmap;
    function NewImage(const Pixels: array of Byte; const Width, Height: Cardinal): TTsPixmap;
    function RedImage: TTsPixmap;
    function Whole(const Width, Height: Cardinal): TTsScreenIntRect;
    function IntRect(const Left, Top, Right, Bottom: Integer): TTsIntRect;
    function PaintOf(const Shader: TTsShader): TTsPaint;
    procedure FillWith(var Pixmap: TTsPixmap; const Paint: TTsPaint);
    procedure AssertPixel(const Pixmap: TTsPixmap; const X, Y: Cardinal; const R, G, B, A: Byte; const Tolerance: Integer = 0);
    procedure AssertTransparent(const Pixmap: TTsPixmap; const X, Y: Cardinal);
    procedure AssertBicubicColorStaysWithinAlpha(const SpreadMode: TTsSpreadMode);
    procedure AssertPatternDrawsNothing(const Pattern: TTsShader);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestSolidShaderBlitsPremultipliedColor;

    [Test]
    procedure TestPatternRepeatNearest;

    [Test]
    procedure TestPatternDecalOutsideIsTransparent;

    [Test]
    procedure TestDecalBilinearScaled;

    [Test]
    procedure TestBicubicNeverExceedsAlpha;

    [Test]
    procedure TestBicubicNeverExceedsAlphaWithReflect;

    [Test]
    procedure TestBicubicNeverExceedsAlphaWithDecal;

    [Test]
    procedure TestOpacityScalesPattern;

    [Test]
    procedure TestPixmapOverBitmapSharesBytes;

    [Test]
    procedure TestPixmapOverBitmapHasTheByteOrderOfTheDeviceContract;

    [Test]
    procedure TestDecalBicubicIsTransparentOutside;

    [Test]
    procedure TestReflectAndPadPatterns;

    [Test]
    procedure TestSingularPatternTransformDrawsNothing;

    [Test]
    procedure TestZeroScalePatternTransformDrawsNothing;

    [Test]
    procedure TestSubnormalScalePatternTransformDrawsNothing;

    [Test]
    procedure TestNanScalePatternTransformDrawsNothing;

    [Test]
    procedure TestEmptyPatternPixmapDrawsNothing;

    [Test]
    procedure TestShortPatternDataDrawsNothing;

    [Test]
    procedure TestBlitterRejectsAPixmapWhoseDataIsShort;

    [Test]
    procedure TestDefaultPaintIsBlackSourceOver;

    [Test]
    procedure TestDestinationBlendModeIsRejected;

    [Test]
    procedure TestOpaqueSourceOverIsASolidFill;

    [Test]
    procedure TestClearWithoutAntiAliasClears;

    [Test]
    procedure TestBlitAntiHRunsWithOffset;

    [Test]
    procedure TestBlitVAndTheTwoPixelBlits;

    [Test]
    procedure TestBlitsOutsideThePixmapAreClipped;

    [Test]
    procedure TestMaskMultipliesTheCoverage;

    [Test]
    procedure TestMaskOfAnotherSizeIsRejected;

    [Test]
    procedure TestMaskBlitterDrawsCoverage;

    [Test]
    procedure TestSubPixmapBlits;

    [Test]
    procedure TestPixmapFactories;

    [Test]
    procedure TestPixmapCloneRectAndPixel;

    [Test]
    procedure TestMaskFromPixmap;

    [Test]
    procedure TestShaderOpacityAndTransform;
  end;

implementation

{ TTsShaderTests }

procedure TTsShaderTests.Setup;
begin
  FFloatState := TTsFloatMode.Enter;
end;

procedure TTsShaderTests.TearDown;
begin
  TTsFloatMode.Leave(FFloatState);
end;

function TTsShaderTests.NewPixmap(const Width, Height: Cardinal): TTsPixmap;
begin
  Assert.IsTrue(TTsPixmap.TryCreate(Width, Height, Result));
end;

function TTsShaderTests.NewImage(const Pixels: array of Byte; const Width, Height: Cardinal): TTsPixmap;
begin
  var Bytes: TBytes;
  SetLength(Bytes, Length(Pixels));
  Move(Pixels[0], Bytes[0], Length(Pixels));

  Assert.IsTrue(TTsPixmap.TryFromBytes(Bytes, Width, Height, Result));
end;

function TTsShaderTests.RedImage: TTsPixmap;
begin
  Result := NewImage([255, 0, 0, 255,  255, 0, 0, 255,  255, 0, 0, 255,  255, 0, 0, 255], 2, 2);
end;

function TTsShaderTests.Whole(const Width, Height: Cardinal): TTsScreenIntRect;
begin
  Result := TTsScreenIntRect.FromXYWHSafe(0, 0, Width, Height);
end;

function TTsShaderTests.IntRect(const Left, Top, Right, Bottom: Integer): TTsIntRect;
begin
  Assert.IsTrue(TTsIntRect.TryFromLTRB(Left, Top, Right, Bottom, Result));
end;

function TTsShaderTests.PaintOf(const Shader: TTsShader): TTsPaint;
begin
  Result := TTsPaint.Default;
  Result.Shader := Shader;
end;

procedure TTsShaderTests.FillWith(var Pixmap: TTsPixmap; const Paint: TTsPaint);
begin
  var Blitter: TTsRasterPipelineBlitter;
  Assert.IsTrue(TTsRasterPipelineBlitter.TryCreate(Paint, Default(TTsSubMaskRef), Pixmap.SubPixmap, Blitter));
  try
    Blitter.BlitRect(Whole(Pixmap.Width, Pixmap.Height));
  finally
    Blitter.Free;
  end;
end;

procedure TTsShaderTests.AssertPixel(const Pixmap: TTsPixmap; const X, Y: Cardinal; const R, G, B, A: Byte; const Tolerance: Integer);
begin
  var Color: TTsPremultipliedColorU8;
  Assert.IsTrue(Pixmap.TryPixel(X, Y, Color));

  const Message = Format('Pixel (%d,%d) is (%d,%d,%d,%d), expected (%d,%d,%d,%d)',
                         [X, Y, Color.Red, Color.Green, Color.Blue, Color.Alpha, R, G, B, A]);
  Assert.AreEqual(Integer(R), Integer(Color.Red), Tolerance, Message);
  Assert.AreEqual(Integer(G), Integer(Color.Green), Tolerance, Message);
  Assert.AreEqual(Integer(B), Integer(Color.Blue), Tolerance, Message);
  Assert.AreEqual(Integer(A), Integer(Color.Alpha), Tolerance, Message);
end;

procedure TTsShaderTests.AssertTransparent(const Pixmap: TTsPixmap; const X, Y: Cardinal);
begin
  AssertPixel(Pixmap, X, Y, 0, 0, 0, 0);
end;

procedure TTsShaderTests.TestSolidShaderBlitsPremultipliedColor;
begin
  var Pixmap := NewPixmap(4, 4);

  FillWith(Pixmap, PaintOf(TTsShader.NewSolidColor(TTsColor.FromRgba8(255, 0, 0, 128))));

  for var Y := 0 to 3 do
  begin
    for var X := 0 to 3 do
    begin
      AssertPixel(Pixmap, X, Y, 128, 0, 0, 128, 1);
    end;
  end;
end;

procedure TTsShaderTests.TestPatternRepeatNearest;
begin
  const Tile = NewImage([0, 0, 0, 255,  255, 255, 255, 255,
                         255, 255, 255, 255,  0, 0, 0, 255], 2, 2);
  var Pixmap := NewPixmap(8, 8);

  FillWith(Pixmap, PaintOf(TTsShader.NewPattern(Tile.AsRef, TTsSpreadMode.&Repeat, TTsFilterQuality.Nearest, 1, TTsTransform.Identity)));

  AssertPixel(Pixmap, 0, 0, 0, 0, 0, 255);
  AssertPixel(Pixmap, 2, 2, 0, 0, 0, 255);
  AssertPixel(Pixmap, 3, 2, 255, 255, 255, 255);
  AssertPixel(Pixmap, 7, 6, 255, 255, 255, 255);
  AssertPixel(Pixmap, 7, 7, 0, 0, 0, 255);
end;

procedure TTsShaderTests.TestPatternDecalOutsideIsTransparent;
begin
  var Pixmap := NewPixmap(8, 8);

  FillWith(Pixmap, PaintOf(TTsShader.NewPattern(RedImage.AsRef, TTsSpreadMode.Decal, TTsFilterQuality.Nearest, 1,
                                                TTsTransform.FromTranslate(3, 3))));

  AssertPixel(Pixmap, 3, 3, 255, 0, 0, 255);
  AssertPixel(Pixmap, 4, 4, 255, 0, 0, 255);
  AssertTransparent(Pixmap, 2, 2);
  AssertTransparent(Pixmap, 5, 5);
  AssertTransparent(Pixmap, 3, 2);
  AssertTransparent(Pixmap, 4, 5);
  AssertTransparent(Pixmap, 0, 0);
end;

procedure TTsShaderTests.TestDecalBilinearScaled;
begin
  var Pixmap := NewPixmap(12, 12);

  FillWith(Pixmap, PaintOf(TTsShader.NewPattern(RedImage.AsRef, TTsSpreadMode.Decal, TTsFilterQuality.Bilinear, 1,
                                                TTsTransform.FromScale(4, 4))));

  // The edge of the scaled bitmap pads, so it keeps its full alpha
  AssertPixel(Pixmap, 3, 3, 255, 0, 0, 255, 1);
  AssertPixel(Pixmap, 0, 0, 255, 0, 0, 255, 1);
  AssertPixel(Pixmap, 7, 7, 255, 0, 0, 255, 1);
  AssertTransparent(Pixmap, 9, 9);
  AssertTransparent(Pixmap, 8, 0);
end;

procedure TTsShaderTests.TestDecalBicubicIsTransparentOutside;
begin
  var Pixmap := NewPixmap(12, 12);

  FillWith(Pixmap, PaintOf(TTsShader.NewPattern(RedImage.AsRef, TTsSpreadMode.Decal, TTsFilterQuality.Bicubic, 1,
                                                TTsTransform.FromScale(4, 4))));

  AssertPixel(Pixmap, 3, 3, 255, 0, 0, 255, 1);
  AssertTransparent(Pixmap, 9, 9);
end;

procedure TTsShaderTests.AssertBicubicColorStaysWithinAlpha(const SpreadMode: TTsSpreadMode);
const
  // Every row is opaque black, opaque white, opaque white, transparent
  Row: array[0..15] of Byte = (0, 0, 0, 255,  255, 255, 255, 255,  255, 255, 255, 255,  0, 0, 0, 0);
begin
  // Every row is opaque black, opaque white, opaque white, transparent. The far tap of the cubic has a negative weight, so a pixel next to the
  // transparent texel gets a colour sum above its alpha unless the colour is clamped to the alpha.
  var Pixels: TBytes;
  SetLength(Pixels, 4 * 4 * 4);
  for var Y := 0 to 3 do
  begin
    Move(Row[0], Pixels[Y * 16], 16);
  end;

  var Image: TTsPixmap;
  Assert.IsTrue(TTsPixmap.TryFromBytes(Pixels, 4, 4, Image));
  var Pixmap := NewPixmap(20, 20);

  FillWith(Pixmap, PaintOf(TTsShader.NewPattern(Image.AsRef, SpreadMode, TTsFilterQuality.Bicubic, 1, TTsTransform.FromScale(3.7, 3.7))));

  for var Y := 0 to 19 do
  begin
    for var X := 0 to 19 do
    begin
      var Color: TTsPremultipliedColorU8;
      Assert.IsTrue(Pixmap.TryPixel(X, Y, Color));
      const Message = Format('Pixel (%d,%d) is (%d,%d,%d,%d)', [X, Y, Color.Red, Color.Green, Color.Blue, Color.Alpha]);
      Assert.IsTrue((Color.Red <= Color.Alpha) and (Color.Green <= Color.Alpha) and (Color.Blue <= Color.Alpha), Message);
    end;
  end;
end;

procedure TTsShaderTests.TestBicubicNeverExceedsAlpha;
begin
  AssertBicubicColorStaysWithinAlpha(TTsSpreadMode.&Repeat);
end;

procedure TTsShaderTests.TestBicubicNeverExceedsAlphaWithReflect;
begin
  AssertBicubicColorStaysWithinAlpha(TTsSpreadMode.Reflect);
end;

procedure TTsShaderTests.TestBicubicNeverExceedsAlphaWithDecal;
begin
  AssertBicubicColorStaysWithinAlpha(TTsSpreadMode.Decal);
end;
procedure TTsShaderTests.TestOpacityScalesPattern;
begin
  var Pixmap := NewPixmap(4, 4);

  FillWith(Pixmap, PaintOf(TTsShader.NewPattern(RedImage.AsRef, TTsSpreadMode.&Repeat, TTsFilterQuality.Nearest, 0.5, TTsTransform.Identity)));

  AssertPixel(Pixmap, 0, 0, 128, 0, 0, 128, 1);
  AssertPixel(Pixmap, 3, 3, 128, 0, 0, 128, 1);
end;

procedure TTsShaderTests.TestReflectAndPadPatterns;
begin
  const Tile = NewImage([255, 0, 0, 255,  0, 255, 0, 255,
                         0, 0, 255, 255,  255, 255, 255, 255], 2, 2);

  // Pad: everything right of and below the tile takes the color of the edge
  var Pixmap := NewPixmap(4, 4);
  FillWith(Pixmap, PaintOf(TTsShader.NewPattern(Tile.AsRef, TTsSpreadMode.Pad, TTsFilterQuality.Nearest, 1, TTsTransform.Identity)));
  AssertPixel(Pixmap, 0, 0, 255, 0, 0, 255);
  AssertPixel(Pixmap, 3, 0, 0, 255, 0, 255);
  AssertPixel(Pixmap, 0, 3, 0, 0, 255, 255);
  AssertPixel(Pixmap, 3, 3, 255, 255, 255, 255);

  // Reflect: columns 0, 1, 1, 0
  Pixmap := NewPixmap(4, 4);
  FillWith(Pixmap, PaintOf(TTsShader.NewPattern(Tile.AsRef, TTsSpreadMode.Reflect, TTsFilterQuality.Nearest, 1, TTsTransform.Identity)));
  AssertPixel(Pixmap, 1, 0, 0, 255, 0, 255);
  AssertPixel(Pixmap, 2, 0, 0, 255, 0, 255);
  AssertPixel(Pixmap, 3, 0, 255, 0, 0, 255);
  AssertPixel(Pixmap, 0, 3, 255, 0, 0, 255);
end;

procedure TTsShaderTests.AssertPatternDrawsNothing(const Pattern: TTsShader);
begin
  var Pixmap := NewPixmap(4, 4);

  var Blitter: TTsRasterPipelineBlitter;
  const Created = TTsRasterPipelineBlitter.TryCreate(PaintOf(Pattern), Default(TTsSubMaskRef), Pixmap.SubPixmap, Blitter);

  Assert.IsFalse(Created);
  Assert.IsNull(Blitter);
end;

procedure TTsShaderTests.TestSingularPatternTransformDrawsNothing;
begin
  // A skew matrix with a determinant of zero cannot be inverted
  AssertPatternDrawsNothing(TTsShader.NewPattern(RedImage.AsRef, TTsSpreadMode.&Repeat, TTsFilterQuality.Nearest, 1,
                                                 TTsTransform.FromRow(1, 1, 1, 1, 0, 0)));
end;

procedure TTsShaderTests.TestZeroScalePatternTransformDrawsNothing;
begin
  // TryInvert succeeds here, but the inverse is infinite; tiny-skia would draw the untransformed pattern
  AssertPatternDrawsNothing(TTsShader.NewPattern(RedImage.AsRef, TTsSpreadMode.&Repeat, TTsFilterQuality.Nearest, 1,
                                                 TTsTransform.FromScale(0, 1)));
end;

procedure TTsShaderTests.TestSubnormalScalePatternTransformDrawsNothing;
begin
  // 1 / the smallest subnormal (bits 1, about 1.4e-45) overflows to infinity
  var Bits: Cardinal := 1;
  var Subnormal: Single;
  Move(Bits, Subnormal, SizeOf(Subnormal));
  Assert.IsTrue(Subnormal > 0, 'the value is positive');
  Assert.IsTrue(Subnormal < 1e-37, 'the value is subnormal');

  AssertPatternDrawsNothing(TTsShader.NewPattern(RedImage.AsRef, TTsSpreadMode.&Repeat, TTsFilterQuality.Nearest, 1,
                                                 TTsTransform.FromScale(Subnormal, 1)));
end;

procedure TTsShaderTests.TestNanScalePatternTransformDrawsNothing;
begin
  AssertPatternDrawsNothing(TTsShader.NewPattern(RedImage.AsRef, TTsSpreadMode.&Repeat, TTsFilterQuality.Nearest, 1,
                                                 TTsTransform.FromScale(Single.NaN, 1)));
end;

procedure TTsShaderTests.TestEmptyPatternPixmapDrawsNothing;
begin
  AssertPatternDrawsNothing(TTsShader.NewPattern(Default(TTsPixmapRef), TTsSpreadMode.&Repeat, TTsFilterQuality.Nearest, 1, TTsTransform.Identity));
end;

procedure TTsShaderTests.TestShortPatternDataDrawsNothing;
begin
  var Short := RedImage.AsRef;
  SetLength(Short.Data, 8);

  AssertPatternDrawsNothing(TTsShader.NewPattern(Short, TTsSpreadMode.&Repeat, TTsFilterQuality.Nearest, 1, TTsTransform.Identity));
end;

procedure TTsShaderTests.TestBlitterRejectsAPixmapWhoseDataIsShort;
begin
  var Pixmap := NewPixmap(4, 4);
  var Region := Pixmap.SubPixmap;
  SetLength(Region.Data, 8);

  var Blitter: TTsRasterPipelineBlitter;
  Assert.IsFalse(TTsRasterPipelineBlitter.TryCreate(TTsPaint.Default, Default(TTsSubMaskRef), Region, Blitter));
  Assert.IsNull(Blitter);
  Assert.IsFalse(TTsRasterPipelineBlitter.TryCreateForMask(Region, Blitter));
  Assert.IsNull(Blitter);
end;
procedure TTsShaderTests.TestPixmapOverBitmapSharesBytes;
begin
  const Bitmap = TPdfBitmap.Create(3, 2);
  try
    var Pixmap := TTsPixmap.CreateOver(Bitmap);

    Pixmap.Fill(TTsColor.FromRgba8(255, 0, 0, 128));

    const Pixel = Bitmap.GetPixel(2, 1);
    Assert.AreEqual(128, Integer(Pixel.R));
    Assert.AreEqual(0, Integer(Pixel.G));
    Assert.AreEqual(0, Integer(Pixel.B));
    Assert.AreEqual(128, Integer(Pixel.A));
    Assert.AreEqual(3, Integer(Pixmap.Width));
    Assert.AreEqual(2, Integer(Pixmap.Height));
  finally
    Bitmap.Free;
  end;
end;

procedure TTsShaderTests.TestPixmapOverBitmapHasTheByteOrderOfTheDeviceContract;
begin
  // TPdfBitmap is premultiplied RGBA, like the pixmap: a blit shows the bytes R, G, B, A in that order
  const Bitmap = TPdfBitmap.Create(2, 1);
  try
    var Pixmap := TTsPixmap.CreateOver(Bitmap);

    FillWith(Pixmap, PaintOf(TTsShader.NewSolidColor(TTsColor.FromRgba8(10, 20, 30, 255))));

    const Row = Bitmap.ScanLine(0);
    Assert.AreEqual(10, Integer(Row[0]));
    Assert.AreEqual(20, Integer(Row[1]));
    Assert.AreEqual(30, Integer(Row[2]));
    Assert.AreEqual(255, Integer(Row[3]));
  finally
    Bitmap.Free;
  end;
end;

procedure TTsShaderTests.TestDefaultPaintIsBlackSourceOver;
begin
  const Paint = TTsPaint.Default;

  Assert.AreEqual(Ord(TTsBlendMode.SourceOver), Ord(Paint.BlendMode));
  Assert.IsTrue(Paint.AntiAlias);
  Assert.IsFalse(Paint.ForceHqPipeline);
  Assert.IsTrue(Paint.IsSolidColor);
  Assert.IsTrue(Paint.Shader.IsOpaque);
  Assert.AreEqual(Ord(TTsBlendMode.SourceOver), Ord(TTsPixmapPaint.Default.BlendMode));
end;

procedure TTsShaderTests.TestDestinationBlendModeIsRejected;
begin
  var Pixmap := NewPixmap(2, 2);
  var Paint := TTsPaint.Default;
  Paint.BlendMode := TTsBlendMode.Destination;

  var Blitter: TTsRasterPipelineBlitter;
  Assert.IsFalse(TTsRasterPipelineBlitter.TryCreate(Paint, Default(TTsSubMaskRef), Pixmap.SubPixmap, Blitter));

  // An opaque solid color changes nothing in DestinationIn either
  Paint.BlendMode := TTsBlendMode.DestinationIn;
  Assert.IsFalse(TTsRasterPipelineBlitter.TryCreate(Paint, Default(TTsSubMaskRef), Pixmap.SubPixmap, Blitter));
end;

procedure TTsShaderTests.TestOpaqueSourceOverIsASolidFill;
begin
  var Pixmap := NewPixmap(3, 3);
  Pixmap.Fill(TTsColor.FromRgba8(9, 9, 9, 9));

  FillWith(Pixmap, PaintOf(TTsShader.NewSolidColor(TTsColor.FromRgba8(1, 2, 3, 255))));

  AssertPixel(Pixmap, 0, 0, 1, 2, 3, 255);
  AssertPixel(Pixmap, 2, 2, 1, 2, 3, 255);
end;

procedure TTsShaderTests.TestClearWithoutAntiAliasClears;
begin
  var Pixmap := NewPixmap(3, 3);
  Pixmap.Fill(TTsColor.FromRgba8(9, 9, 9, 255));
  var Paint := TTsPaint.Default;
  Paint.BlendMode := TTsBlendMode.Clear;
  Paint.AntiAlias := False;

  FillWith(Pixmap, Paint);

  AssertTransparent(Pixmap, 1, 1);
end;

procedure TTsShaderTests.TestBlitAntiHRunsWithOffset;
begin
  // Two opaque pixels, then two pixels with the coverage 128, as runs of a scan line that starts at index 1 of the arrays
  const Alphas: TArray<Byte> = [7, 255, 0, 128, 0, 0];
  const Runs: TArray<TTsAlphaRun> = [0, 2, 0, 2, 0, 0];

  var Pixmap := NewPixmap(6, 1);
  var Paint := TTsPaint.Default;
  Paint.Shader := TTsShader.NewSolidColor(TTsColor.FromRgba8(255, 0, 0, 255));
  var Blitter: TTsRasterPipelineBlitter;
  Assert.IsTrue(TTsRasterPipelineBlitter.TryCreate(Paint, Default(TTsSubMaskRef), Pixmap.SubPixmap, Blitter));
  try
    Blitter.BlitAntiH(1, 0, Alphas, Runs, 1);
  finally
    Blitter.Free;
  end;

  AssertTransparent(Pixmap, 0, 0);
  AssertPixel(Pixmap, 1, 0, 255, 0, 0, 255);
  AssertPixel(Pixmap, 2, 0, 255, 0, 0, 255);
  AssertPixel(Pixmap, 3, 0, 128, 0, 0, 128, 1);
  AssertPixel(Pixmap, 4, 0, 128, 0, 0, 128, 1);
  AssertTransparent(Pixmap, 5, 0);
end;

procedure TTsShaderTests.TestBlitVAndTheTwoPixelBlits;
begin
  var Pixmap := NewPixmap(4, 4);
  var Paint := TTsPaint.Default;
  Paint.Shader := TTsShader.NewSolidColor(TTsColor.FromRgba8(255, 0, 0, 255));
  var Blitter: TTsRasterPipelineBlitter;
  Assert.IsTrue(TTsRasterPipelineBlitter.TryCreate(Paint, Default(TTsSubMaskRef), Pixmap.SubPixmap, Blitter));
  try
    Blitter.BlitV(0, 0, 3, 255);
    Blitter.BlitV(1, 0, 3, 128);
    Blitter.BlitAntiH2(2, 0, 255, 128);
    Blitter.BlitAntiV2(3, 2, 64, 255);
  finally
    Blitter.Free;
  end;

  AssertPixel(Pixmap, 0, 0, 255, 0, 0, 255);
  AssertPixel(Pixmap, 0, 2, 255, 0, 0, 255);
  AssertTransparent(Pixmap, 0, 3);
  AssertPixel(Pixmap, 1, 1, 128, 0, 0, 128, 1);
  AssertPixel(Pixmap, 2, 0, 255, 0, 0, 255);
  AssertPixel(Pixmap, 3, 0, 128, 0, 0, 128, 1);
  AssertPixel(Pixmap, 3, 2, 64, 0, 0, 64, 1);
  AssertPixel(Pixmap, 3, 3, 255, 0, 0, 255);
end;

procedure TTsShaderTests.TestBlitsOutsideThePixmapAreClipped;
begin
  // The vertical hairline may blit at x = clip.right: that must not touch the next row
  var Pixmap := NewPixmap(4, 3);
  var Paint := TTsPaint.Default;
  Paint.Shader := TTsShader.NewSolidColor(TTsColor.FromRgba8(255, 0, 0, 255));
  var Blitter: TTsRasterPipelineBlitter;
  Assert.IsTrue(TTsRasterPipelineBlitter.TryCreate(Paint, Default(TTsSubMaskRef), Pixmap.SubPixmap, Blitter));
  try
    Blitter.BlitV(4, 0, 2, 255);
    Blitter.BlitV(5, 0, 2, 100);
    Blitter.BlitH(2, 5, 9);
    Blitter.BlitH(3, 1, 9);
    Blitter.BlitAntiH2(3, 2, 255, 255);
    Blitter.BlitRect(TTsScreenIntRect.FromXYWHSafe(2, 2, 10, 10));
  finally
    Blitter.Free;
  end;

  AssertTransparent(Pixmap, 0, 1);
  AssertTransparent(Pixmap, 0, 0);
  AssertPixel(Pixmap, 3, 1, 255, 0, 0, 255);
  AssertPixel(Pixmap, 3, 2, 255, 0, 0, 255);
  AssertPixel(Pixmap, 2, 2, 255, 0, 0, 255);
  AssertTransparent(Pixmap, 2, 1);
end;

procedure TTsShaderTests.TestMaskMultipliesTheCoverage;
begin
  var Mask: TTsMask;
  Assert.IsTrue(TTsMask.TryFromBytes([255, 128, 0, 255], 2, 2, Mask));

  var Pixmap := NewPixmap(2, 2);
  var Paint := TTsPaint.Default;
  Paint.Shader := TTsShader.NewSolidColor(TTsColor.FromRgba8(255, 0, 0, 255));
  var Blitter: TTsRasterPipelineBlitter;
  Assert.IsTrue(TTsRasterPipelineBlitter.TryCreate(Paint, Mask.AsSubMask, Pixmap.SubPixmap, Blitter));
  try
    Blitter.BlitRect(Whole(2, 2));
  finally
    Blitter.Free;
  end;

  AssertPixel(Pixmap, 0, 0, 255, 0, 0, 255);
  AssertPixel(Pixmap, 1, 0, 128, 0, 0, 128, 1);
  AssertTransparent(Pixmap, 0, 1);
  AssertPixel(Pixmap, 1, 1, 255, 0, 0, 255);
end;

procedure TTsShaderTests.TestMaskOfAnotherSizeIsRejected;
begin
  var Mask: TTsMask;
  Assert.IsTrue(TTsMask.TryCreate(3, 2, Mask));
  var Pixmap := NewPixmap(2, 2);

  var Blitter: TTsRasterPipelineBlitter;
  Assert.IsFalse(TTsRasterPipelineBlitter.TryCreate(TTsPaint.Default, Mask.AsSubMask, Pixmap.SubPixmap, Blitter));
  Assert.IsNull(Blitter);
end;

procedure TTsShaderTests.TestMaskBlitterDrawsCoverage;
begin
  var Mask: TTsMask;
  Assert.IsTrue(TTsMask.TryCreate(5, 2, Mask));

  var Blitter: TTsRasterPipelineBlitter;
  Assert.IsTrue(TTsRasterPipelineBlitter.TryCreateForMask(Mask.SubPixmap, Blitter));
  try
    Blitter.BlitH(1, 0, 3);
    Blitter.BlitV(4, 0, 2, 128);
  finally
    Blitter.Free;
  end;

  Assert.AreEqual(0, Integer(Mask.Data[0]));
  Assert.AreEqual(255, Integer(Mask.Data[1]));
  Assert.AreEqual(255, Integer(Mask.Data[3]));
  Assert.AreEqual(128, Integer(Mask.Data[4]), 1);
  Assert.AreEqual(128, Integer(Mask.Data[9]), 1);
  Assert.AreEqual(0, Integer(Mask.Data[5]));
end;

procedure TTsShaderTests.TestSubPixmapBlits;
begin
  var Pixmap := NewPixmap(5, 4);
  var Region: TTsSubPixmapMut;
  Assert.IsTrue(Pixmap.TrySubPixmap(IntRect(1, 1, 4, 3), Region));
  Assert.AreEqual(3, Integer(Region.Width));
  Assert.AreEqual(2, Integer(Region.Height));

  var Paint := TTsPaint.Default;
  Paint.Shader := TTsShader.NewSolidColor(TTsColor.FromRgba8(255, 0, 0, 255));
  var Blitter: TTsRasterPipelineBlitter;
  Assert.IsTrue(TTsRasterPipelineBlitter.TryCreate(Paint, Default(TTsSubMaskRef), Region, Blitter));
  try
    Blitter.BlitRect(Whole(3, 2));
    // Beyond the region but inside the parent: clipped to the region
    Blitter.BlitH(0, 3, 5);
  finally
    Blitter.Free;
  end;

  AssertTransparent(Pixmap, 0, 1);
  AssertPixel(Pixmap, 1, 1, 255, 0, 0, 255);
  AssertPixel(Pixmap, 3, 2, 255, 0, 0, 255);
  AssertTransparent(Pixmap, 4, 2);
  AssertTransparent(Pixmap, 1, 3);
  AssertTransparent(Pixmap, 1, 0);
end;

procedure TTsShaderTests.TestPixmapFactories;
begin
  var Pixmap: TTsPixmap;
  Assert.IsFalse(TTsPixmap.TryCreate(0, 4, Pixmap));
  Assert.IsFalse(TTsPixmap.TryCreate(4, 0, Pixmap));
  Assert.IsFalse(TTsPixmap.TryCreate(536870912, 1, Pixmap));
  Assert.IsFalse(TTsPixmap.TryFromBytes([1, 2, 3], 1, 1, Pixmap));
  Assert.IsTrue(TTsPixmap.TryFromBytes([1, 2, 3, 4], 1, 1, Pixmap));

  var Mask: TTsMask;
  Assert.IsFalse(TTsMask.TryCreate(0, 1, Mask));
  Assert.IsFalse(TTsMask.TryFromBytes([1, 2, 3], 2, 2, Mask));
  Assert.IsTrue(TTsMask.TryFromBytes([1, 2, 3, 4], 2, 2, Mask));

  var Ref: TTsPixmapRef;
  Assert.IsFalse(TTsPixmapRef.TryFromBytes([1, 2, 3, 4], 2, 1, Ref));
end;

procedure TTsShaderTests.TestPixmapCloneRectAndPixel;
begin
  var Pixmap := NewPixmap(4, 4);
  Pixmap.Fill(TTsColor.FromRgba8(0, 0, 255, 255));
  Pixmap.Data[(1 * 4 + 2) * 4] := 77;

  var Clone: TTsPixmap;
  Assert.IsTrue(Pixmap.TryCloneRect(IntRect(1, 1, 9, 3), Clone));
  Assert.AreEqual(3, Integer(Clone.Width));
  Assert.AreEqual(2, Integer(Clone.Height));
  AssertPixel(Clone, 1, 0, 77, 0, 255, 255);
  AssertPixel(Clone, 0, 0, 0, 0, 255, 255);

  Assert.IsFalse(Pixmap.TryCloneRect(IntRect(10, 10, 12, 12), Clone));

  var Color: TTsPremultipliedColorU8;
  Assert.IsFalse(Pixmap.TryPixel(4, 0, Color));
  Assert.IsFalse(Pixmap.TryPixel(0, 4, Color));
end;

procedure TTsShaderTests.TestMaskFromPixmap;
begin
  // A transparent pixel, a half transparent red, an opaque white
  const Image = NewImage([0, 0, 0, 0,  128, 0, 0, 128,  255, 255, 255, 255], 3, 1);

  const AlphaMask = TTsMask.FromPixmap(Image.AsRef, TTsMaskType.Alpha);
  Assert.AreEqual(0, Integer(AlphaMask.Data[0]));
  Assert.AreEqual(128, Integer(AlphaMask.Data[1]));
  Assert.AreEqual(255, Integer(AlphaMask.Data[2]));

  const Luminosity = TTsMask.FromPixmap(Image.AsRef, TTsMaskType.Luminosity);
  Assert.AreEqual(0, Integer(Luminosity.Data[0]));
  // The demultiplied red is 1, so the luma is 0.2126; times the alpha 0.502 and 255 that is 27.2, rounded up
  Assert.AreEqual(28, Integer(Luminosity.Data[1]));
  Assert.AreEqual(255, Integer(Luminosity.Data[2]));
end;

procedure TTsShaderTests.TestShaderOpacityAndTransform;
begin
  var Shader := TTsShader.NewSolidColor(TTsColor.FromRgba8(255, 0, 0, 255));
  Shader.ApplyOpacity(0.5);
  Assert.AreEqual(Double(0.5), Double(Shader.Color.Alpha), 0.001);
  Assert.IsFalse(Shader.IsOpaque);

  Shader := TTsShader.NewPattern(RedImage.AsRef, TTsSpreadMode.Pad, TTsFilterQuality.Nearest, 0.5, TTsTransform.FromTranslate(1, 2));
  Shader.ApplyOpacity(0.5);
  Shader.ApplyOpacity(7);
  Assert.AreEqual(Double(0.25), Double(Shader.Pattern.Opacity.Get), 0.0001);
  Shader.ApplyOpacity(-1);
  Assert.AreEqual(Double(0), Double(Shader.Pattern.Opacity.Get), 0.0001);

  Shader.ApplyTransform(TTsTransform.FromTranslate(10, 20));
  Assert.AreEqual(Double(11), Double(Shader.Pattern.Transform.TX), 0.0001);
  Assert.AreEqual(Double(22), Double(Shader.Pattern.Transform.TY), 0.0001);
end;

end.
