// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Hostile input for the native device: coordinates, matrices, sizes and clips that no PDF should hold but a damaged or malicious one can.
// The device must draw nothing or something sensible, take bounded time and raise only EPdfLimitExceededException.
unit Pdf4D.Render.Native.Device.Hostile.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Types,
  System.Diagnostics,
  DUnitX.TestFramework,
  Pdf4D.Common.Defines,
  Pdf4D.Common.FloatGuard,
  Pdf4D.Common.Matrix,
  Pdf4D.Common.Path,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.ClipPath,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Render.Native.Backend,
  Pdf4D.Render.Native.Device;

type
  [TestFixture]
  TPdfNativeHostileTests = class
  private const
    DeviceSize = 100;
    // Win64 Release; a Debug build needs a looser bound for the tests of a million segments and of the random calls
    TimeLimitMilliseconds = 5000;
    CallLimitMilliseconds = 1000;
    HangGuardMilliseconds = 60000;

  private
    FBackend: IPdfRenderBackend;
    FDevice: IPdfRasterDevice;
    FHugePath: TPdfPath;
    FSnapshot: TPdfBitmap;
    FRandomBitmaps: TArray<TPdfBitmap>;
    FRandomMasks: TArray<TPdfAlphaMask>;
    FRandomClips: TArray<IPdfClipPath>;

    function Native: TPdfNativeDevice;
    procedure CreateDevice(const Width, Height: Integer);
    function Red: TPdfPaint;
    function RedValue: TPdfDeviceColor;
    function NoAntiAlias: TPdfComposite;
    function NewRectPath(const Left, Top, Right, Bottom: Single): TPdfPath;
    function NewClip(const Parent: IPdfClipPath; const Left, Top, Right, Bottom: Single): IPdfClipPath;
    function NewDiamondClipAround(const Parent: IPdfClipPath; const CenterX, CenterY, HalfDiagonal: Single): IPdfClipPath;
    function NewStroke(const Width: Single): TPdfStrokeStyle;
    function NewTile: TPdfBitmap;
    // The path of the tests of non-finite points: a move, a line, a quad, a cubic and a close, 14 coordinates
    function NewPathOfCoordinates(const Coordinates: TArray<Single>): TPdfPath;
    function NewZigZag(const SegmentCount, Amplitude: Integer): TPdfPath;
    function NewSnake(const SegmentCount: Integer): TPdfPath;
    procedure FillWithPaint(const Path: TPdfPath; const Paint: TPdfPaint; const Composite: TPdfComposite);
    procedure FillRect(const Left, Top, Right, Bottom: Single; const Paint: TPdfPaint; const Composite: TPdfComposite);
    procedure FillWholeDevice(const Paint: TPdfPaint; const Composite: TPdfComposite);
    procedure FillWholeDeviceWithMask(const Mask: TPdfAlphaMask);
    procedure FillHugePath;
    procedure StrokeHugePath;
    procedure AssertNothingIsDrawn;
    procedure AssertEveryPixelIsRed(const What: string = '');
    procedure AssertWithinTime(const Watch: TStopwatch; const Limit: Integer; const What: string);
    function RedPixelCount(const Row, FromX, ToX: Integer): Integer;

    // The random calls
    function RandomValue: Single;
    function RandomMatrix: TPdfMatrix;
    function RandomPath: TPdfPath;
    function RandomClip: IPdfClipPath;
    function RandomStroke: TPdfStrokeStyle;
    function RandomComposite: TPdfComposite;
    function RandomPaint: TPdfPaint;
    procedure MakeRandomPools;
    procedure FreeRandomPools;
    procedure DoRandomCall(const Device: IPdfRasterDevice; const Depth: Integer);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestNaNAndInfPointsDrawNothing;

    [Test]
    procedure TestNonFiniteTransformDrawsNothing;

    [Test]
    procedure TestHugeButFiniteRectFillsDevice;

    [Test]
    procedure TestCoordinatesOf1e30AreClipped;

    [Test]
    procedure TestMillionSegmentPathIsBounded;

    [Test]
    procedure TestDenseEdgesTerminate;

    [Test]
    procedure TestPathOverTheVerbLimitRaises;

    [Test]
    procedure TestHugeStrokeWidthIsBounded;

    [Test]
    procedure TestDashedStrokeOfHugeWidthIsBounded;

    [Test]
    procedure TestMillionsOfDashesDrawNothing;

    [Test]
    procedure TestDeepCurveIsBounded;

    [Test]
    procedure TestBitmapPaintWithSingularMatrixDrawsNothing;

    [Test]
    procedure TestPatternOfScaleZeroAndOneDrawsNothing;

    [Test]
    procedure TestPatternOfSubnormalScaleDrawsNothing;

    [Test]
    procedure TestTinyRepeatTileIsBounded;

    [Test]
    procedure TestOneByOneBitmapScaledHuge;

    [Test]
    procedure TestSoftMaskWithHugeOffset;

    [Test]
    procedure TestSoftMaskAtTheLowestOffset;

    [Test]
    procedure TestSoftMaskOfZeroSize;

    [Test]
    procedure TestSoftMaskLargerThanDevice;

    [Test]
    procedure TestMismatchedSoftMaskOnASmallDevice;

    [Test]
    procedure TestMismatchedSoftMaskAcrossTiles;

    [Test]
    procedure TestDrawBitmapAtHighIntegerDrawsNothing;

    [Test]
    procedure TestBitmapPaintAtHighIntegerDrawsNothing;

    [Test]
    procedure TestClipWithNaNPointClipsEverything;

    [Test]
    procedure TestClipRectOf3e9DoesNotClip;

    [Test]
    procedure TestClipRectOf1e30DoesNotClip;

    // 100 000 W n operations with a draw after each
    [Test]
    procedure TestHundredThousandRectClipsAreAppliedOnce;

    // 1 000 clips that are not rectangles, with a draw after each
    [Test]
    procedure TestThousandNonRectClipsAreAppliedOnce;

    // The CTM stretches x by 100 and y by 0.01; the bitmap of the paint has to stay where it is put
    [Test]
    procedure TestStrokeWithBitmapPaintUnderIllConditionedCtm;

    [Test]
    procedure TestStrokeWithBitmapPaintUnderTheWorstCtmIsBounded;

    [Test]
    procedure TestRandomDeviceCallsAreSafe;
  end;

implementation

uses
  System.Math,
  System.Generics.Collections;

const
  // The coordinates of the path of the non-finite tests: M 10 10, L 90 10, Q 95 50 90 90, C 70 95 30 95 10 90, Z
  PathCoordinates: array[0..13] of Single = (10, 10, 90, 10, 95, 50, 90, 90, 70, 95, 30, 95, 10, 90);
  RandomSeed = 4321;
  RandomCallCount = 5000;
  WideDeviceWidth = 9000;

{ TPdfNativeHostileTests }

procedure TPdfNativeHostileTests.Setup;
begin
  FBackend := TPdfNativeBackend.Create;
  CreateDevice(DeviceSize, DeviceSize);
end;

procedure TPdfNativeHostileTests.TearDown;
begin
  FSnapshot.Free;
  FSnapshot := nil;
  FHugePath.Free;
  FHugePath := nil;
  FreeRandomPools;
  FDevice := nil;
  FBackend := nil;
end;

function TPdfNativeHostileTests.Native: TPdfNativeDevice;
begin
  Result := (FDevice as TPdfNativeDevice);
end;

procedure TPdfNativeHostileTests.CreateDevice(const Width, Height: Integer);
begin
  FDevice := FBackend.CreateRasterDevice(Width, Height);
end;

function TPdfNativeHostileTests.RedValue: TPdfDeviceColor;
begin
  Result := TPdfDeviceColor.Create(255, 0, 0);
end;

function TPdfNativeHostileTests.Red: TPdfPaint;
begin
  Result := TPdfPaint.Solid(RedValue);
end;

function TPdfNativeHostileTests.NoAntiAlias: TPdfComposite;
begin
  Result := TPdfComposite.Default;
  Result.AntiAlias := False;
end;

function TPdfNativeHostileTests.NewRectPath(const Left, Top, Right, Bottom: Single): TPdfPath;
begin
  Result := TPdfPath.Create;
  Result.MoveTo(Left, Top);
  Result.LineTo(Right, Top);
  Result.LineTo(Right, Bottom);
  Result.LineTo(Left, Bottom);
  Result.ClosePath;
end;

function TPdfNativeHostileTests.NewClip(const Parent: IPdfClipPath; const Left, Top, Right, Bottom: Single): IPdfClipPath;
begin
  Result := TPdfClipPath.Create(Parent, NewRectPath(Left, Top, Right, Bottom), TPdfMatrix.Identity, TPdfFillRule.NonZero);
end;

function TPdfNativeHostileTests.NewDiamondClipAround(const Parent: IPdfClipPath; const CenterX, CenterY, HalfDiagonal: Single): IPdfClipPath;
begin
  const Path = TPdfPath.Create;
  Path.MoveTo(CenterX, CenterY - HalfDiagonal);
  Path.LineTo(CenterX + HalfDiagonal, CenterY);
  Path.LineTo(CenterX, CenterY + HalfDiagonal);
  Path.LineTo(CenterX - HalfDiagonal, CenterY);
  Path.ClosePath;

  Result := TPdfClipPath.Create(Parent, Path, TPdfMatrix.Identity, TPdfFillRule.NonZero);
end;

function TPdfNativeHostileTests.NewStroke(const Width: Single): TPdfStrokeStyle;
begin
  Result := Default(TPdfStrokeStyle);
  Result.Width := Width;
  Result.Cap := TPdfLineCap.Butt;
  Result.Join := TPdfLineJoin.Miter;
  Result.MiterLimit := 10;
end;

// A tile of 1 x 1 pixel, opaque red; the caller frees it
function TPdfNativeHostileTests.NewTile: TPdfBitmap;
begin
  Result := TPdfBitmap.Create(1, 1);
  Result.SetPixel(0, 0, RedValue);
end;

function TPdfNativeHostileTests.NewPathOfCoordinates(const Coordinates: TArray<Single>): TPdfPath;
begin
  Result := TPdfPath.Create;
  Result.MoveTo(Coordinates[0], Coordinates[1]);
  Result.LineTo(Coordinates[2], Coordinates[3]);
  Result.QuadTo(Coordinates[4], Coordinates[5], Coordinates[6], Coordinates[7]);
  Result.CubicTo(Coordinates[8], Coordinates[9], Coordinates[10], Coordinates[11], Coordinates[12], Coordinates[13]);
  Result.ClosePath;
end;

// A zigzag inside the device: every segment goes from the top row to the row Amplitude and back, one column further
function TPdfNativeHostileTests.NewZigZag(const SegmentCount, Amplitude: Integer): TPdfPath;
begin
  Result := TPdfPath.Create;
  Result.MoveTo(0, 0);
  for var Index := 1 to SegmentCount do
  begin
    const Column = (Index mod DeviceSize);
    const Row = (Index mod 2) * Amplitude;
    Result.LineTo(Column, Row);
  end;
end;

// A path inside the device that winds down it: every segment goes one column further (and back after 100) and a hundredth of a row lower,
// so that its edges are short and few are active at a time
function TPdfNativeHostileTests.NewSnake(const SegmentCount: Integer): TPdfPath;
begin
  Result := TPdfPath.Create;
  Result.MoveTo(0, 0);
  for var Index := 1 to SegmentCount do
  begin
    const Column = (Index mod DeviceSize);
    const Row: Single = Index * (DeviceSize - 1) / SegmentCount;
    Result.LineTo(Column, Row);
  end;
end;

procedure TPdfNativeHostileTests.FillWithPaint(const Path: TPdfPath; const Paint: TPdfPaint; const Composite: TPdfComposite);
begin
  FDevice.FillPath(Path, TPdfMatrix.Identity, TPdfFillRule.NonZero, Paint, Composite);
end;

procedure TPdfNativeHostileTests.FillRect(const Left, Top, Right, Bottom: Single; const Paint: TPdfPaint; const Composite: TPdfComposite);
begin
  const Path = NewRectPath(Left, Top, Right, Bottom);
  try
    FillWithPaint(Path, Paint, Composite);
  finally
    Path.Free;
  end;
end;

procedure TPdfNativeHostileTests.FillWholeDevice(const Paint: TPdfPaint; const Composite: TPdfComposite);
begin
  const Path = NewRectPath(0, 0, FDevice.Width, FDevice.Height);
  try
    FillWithPaint(Path, Paint, Composite);
  finally
    Path.Free;
  end;
end;

procedure TPdfNativeHostileTests.FillWholeDeviceWithMask(const Mask: TPdfAlphaMask);
begin
  var Composite := NoAntiAlias;
  Composite.SoftMask := Mask;
  FillWholeDevice(Red, Composite);
end;

procedure TPdfNativeHostileTests.FillHugePath;
begin
  FDevice.FillPath(FHugePath, TPdfMatrix.Identity, TPdfFillRule.NonZero, Red, TPdfComposite.Default);
end;

procedure TPdfNativeHostileTests.StrokeHugePath;
begin
  FDevice.StrokePath(FHugePath, TPdfMatrix.Identity, NewStroke(1), Red, TPdfComposite.Default);
end;

procedure TPdfNativeHostileTests.AssertNothingIsDrawn;
begin
  FSnapshot.Free;
  FSnapshot := FDevice.ToBitmap;
  for var Index := 0 to Length(FSnapshot.Pixels) - 1 do
  begin
    if FSnapshot.Pixels[Index] <> 0 then
    begin
      Assert.Fail(Format('Byte %d of the device is %d, nothing should be drawn', [Index, FSnapshot.Pixels[Index]]));
    end;
  end;
end;

procedure TPdfNativeHostileTests.AssertEveryPixelIsRed(const What: string);
begin
  FSnapshot.Free;
  FSnapshot := FDevice.ToBitmap;
  for var Y := 0 to FSnapshot.Height - 1 do
  begin
    for var X := 0 to FSnapshot.Width - 1 do
    begin
      const Color = FSnapshot.GetPixel(X, Y);
      const IsRed = ((Color.R = 255) and (Color.G = 0) and (Color.B = 0) and (Color.A = 255));
      if not IsRed then
      begin
        Assert.Fail(Format('%s: pixel (%d, %d) is (%d, %d, %d, %d), not red', [What, X, Y, Color.R, Color.G, Color.B, Color.A]));
      end;
    end;
  end;
end;

procedure TPdfNativeHostileTests.AssertWithinTime(const Watch: TStopwatch; const Limit: Integer; const What: string);
begin
  Assert.IsTrue(Watch.ElapsedMilliseconds < Limit, Format('%s took %d ms (limit %d ms)', [What, Watch.ElapsedMilliseconds, Limit]));
end;

// The number of red pixels of a row of the device between FromX and ToX, both included
function TPdfNativeHostileTests.RedPixelCount(const Row, FromX, ToX: Integer): Integer;
begin
  FSnapshot.Free;
  FSnapshot := FDevice.ToBitmap;
  Result := 0;
  for var X := FromX to ToX do
  begin
    const Color = FSnapshot.GetPixel(X, Row);
    if (Color.R = 255) and (Color.G = 0) and (Color.B = 0) and (Color.A = 255) then
    begin
      Inc(Result);
    end;
  end;
end;

procedure TPdfNativeHostileTests.TestNaNAndInfPointsDrawNothing;
begin
  const Values: TArray<Single> = [Single.NaN, Single.PositiveInfinity, Single.NegativeInfinity];
  for var Slot := 0 to High(PathCoordinates) do
  begin
    for var Value in Values do
    begin
      var Coordinates: TArray<Single>;
      SetLength(Coordinates, Length(PathCoordinates));
      for var Index := 0 to High(PathCoordinates) do
      begin
        Coordinates[Index] := PathCoordinates[Index];
      end;
      Coordinates[Slot] := Value;

      const Path = NewPathOfCoordinates(Coordinates);
      try
        FillWithPaint(Path, Red, TPdfComposite.Default);
        FillWithPaint(Path, Red, NoAntiAlias);
        FDevice.FillPath(Path, TPdfMatrix.GetScaleInstance(2, 2), TPdfFillRule.EvenOdd, Red, NoAntiAlias);
        FDevice.StrokePath(Path, TPdfMatrix.Identity, NewStroke(4), Red, TPdfComposite.Default);
        FDevice.StrokePath(Path, TPdfMatrix.Identity, NewStroke(0.5), Red, NoAntiAlias);
      finally
        Path.Free;
      end;
    end;
  end;

  AssertNothingIsDrawn;
end;

procedure TPdfNativeHostileTests.TestNonFiniteTransformDrawsNothing;
begin
  var Matrices: TArray<TPdfMatrix>;
  for var Slot := 0 to 5 do
  begin
    var Components: TArray<Single> := [1, 0, 0, 1, 0, 0];
    Components[Slot] := Single.NaN;
    Matrices := Matrices + [TPdfMatrix.Create(Components[0], Components[1], Components[2], Components[3], Components[4], Components[5])];
  end;
  Matrices := Matrices + [TPdfMatrix.Create(0, 0, 0, 0, 0, 0)];

  const Tile = NewTile;
  const Path = NewRectPath(10, 10, 90, 90);
  try
    for var Matrix in Matrices do
    begin
      FDevice.FillPath(Path, Matrix, TPdfFillRule.NonZero, Red, TPdfComposite.Default);
      FDevice.FillPath(Path, Matrix, TPdfFillRule.NonZero, Red, NoAntiAlias);
      FDevice.StrokePath(Path, Matrix, NewStroke(3), Red, TPdfComposite.Default);
      FDevice.DrawBitmap(Tile, Matrix, TPdfImageFilter.Bilinear, TPdfComposite.Default);
      FDevice.DrawBitmap(Tile, Matrix, TPdfImageFilter.Nearest, NoAntiAlias);
      FDevice.FillPath(Path, TPdfMatrix.Identity, TPdfFillRule.NonZero,
                       TPdfPaint.FromBitmap(Tile, Matrix, TPdfTileMode.Repeat, TPdfImageFilter.Bilinear), TPdfComposite.Default);
    end;
  finally
    Path.Free;
    Tile.Free;
  end;

  AssertNothingIsDrawn;
end;

procedure TPdfNativeHostileTests.TestHugeButFiniteRectFillsDevice;
begin
  const Path = NewRectPath(-1E9, -1E9, 1E9, 1E9);
  try
    FillWithPaint(Path, Red, NoAntiAlias);
    AssertEveryPixelIsRed('without anti-aliasing');

    FDevice.Clear(TPdfDeviceColor.Transparent);
    FillWithPaint(Path, Red, TPdfComposite.Default);
    AssertEveryPixelIsRed('with anti-aliasing');
  finally
    Path.Free;
  end;
end;

procedure TPdfNativeHostileTests.TestCoordinatesOf1e30AreClipped;
begin
  const Triangle = TPdfPath.Create;
  try
    Triangle.MoveTo(-1E30, -1E30);
    Triangle.LineTo(1E30, -1E30);
    Triangle.LineTo(1E30, 1E30);
    Triangle.ClosePath;

    // Whether it is drawn or not is decided by the port of is_too_big_for_math; only an exception would be wrong
    FillWithPaint(Triangle, Red, TPdfComposite.Default);
    FillWithPaint(Triangle, Red, NoAntiAlias);
    FDevice.StrokePath(Triangle, TPdfMatrix.Identity, NewStroke(2), Red, TPdfComposite.Default);
    FDevice.StrokePath(Triangle, TPdfMatrix.Identity, NewStroke(0), Red, TPdfComposite.Default);
  finally
    Triangle.Free;
  end;
  Assert.Pass;
end;

procedure TPdfNativeHostileTests.TestMillionSegmentPathIsBounded;
begin
  const Path = NewSnake(1000000);
  try
    const Watch = TStopwatch.StartNew;
    FillWithPaint(Path, Red, TPdfComposite.Default);
    AssertWithinTime(Watch, TimeLimitMilliseconds, 'Filling a million segments');

    const StrokeWatch = TStopwatch.StartNew;
    FDevice.StrokePath(Path, TPdfMatrix.Identity, NewStroke(1), Red, TPdfComposite.Default);
    AssertWithinTime(StrokeWatch, TimeLimitMilliseconds, 'Stroking a million segments');
  finally
    Path.Free;
  end;
end;

// Dense edges: every segment crosses all 100 rows (the full height) or the same 3 rows, so that all of them are active at the same time. The
// work grows with the square of the number of edges that share rows (the insertion sort of the active edges, as in tiny-skia and Skia): a
// million of them take 15 s to fill. The clock here is a guard against a hang only; the verb limit bounds the cost.
procedure TPdfNativeHostileTests.TestDenseEdgesTerminate;
begin
  for var Amplitude in [3, DeviceSize - 1] do
  begin
    const Path = NewZigZag(100000, Amplitude);
    try
      const Watch = TStopwatch.StartNew;
      FillWithPaint(Path, Red, TPdfComposite.Default);
      FDevice.StrokePath(Path, TPdfMatrix.Identity, NewStroke(1), Red, TPdfComposite.Default);
      AssertWithinTime(Watch, HangGuardMilliseconds, Format('Filling and stroking 100 000 segments of an amplitude of %d', [Amplitude]));
    finally
      Path.Free;
    end;
  end;
end;

procedure TPdfNativeHostileTests.TestPathOverTheVerbLimitRaises;
begin
  FHugePath := NewZigZag(5000000, DeviceSize - 1);

  Assert.WillRaise(FillHugePath, EPdfLimitExceededException);
  Assert.WillRaise(StrokeHugePath, EPdfLimitExceededException);
  AssertNothingIsDrawn;
end;

procedure TPdfNativeHostileTests.TestHugeStrokeWidthIsBounded;
begin
  const Path = TPdfPath.Create;
  try
    Path.MoveTo(10, 10);
    Path.LineTo(90, 50);
    Path.LineTo(20, 90);

    for var Width in [Single(1E20), Single(1E38), Single(Single.MaxValue)] do
    begin
      const Watch = TStopwatch.StartNew;
      FDevice.StrokePath(Path, TPdfMatrix.Identity, NewStroke(Width), Red, TPdfComposite.Default);
      var Round := NewStroke(Width);
      Round.Cap := TPdfLineCap.Round;
      Round.Join := TPdfLineJoin.Round;
      FDevice.StrokePath(Path, TPdfMatrix.Identity, Round, Red, NoAntiAlias);
      AssertWithinTime(Watch, TimeLimitMilliseconds, 'A huge stroke');
    end;
  finally
    Path.Free;
  end;
  Assert.Pass;
end;

// Found by the fuzz of the renderer (generated graphics stream 79 and 799 of seed 8642): a dashed path of curves at a width of 1e11 took 2.5 s,
// at 1e9 4 s, and a page of such strokes did not end within 10 s. The device takes a width of at most 1e6 pixels.
procedure TPdfNativeHostileTests.TestDashedStrokeOfHugeWidthIsBounded;
begin
  const Path = TPdfPath.Create;
  try
    Path.MoveTo(101, 49);
    Path.LineTo(203, 49);
    Path.LineTo(203, 217);
    Path.LineTo(101, 217);
    Path.ClosePath;
    Path.CubicTo(119.589996, 130.01001, 2.53000188, 181.630005, 167, 95);
    Path.LineTo(141, 165);
    Path.CubicTo(190.860001, 90.0999985, 182.949997, 149.51001, 193, 107);
    Path.CubicTo(188.949997, 31.2100067, 157, 181, 157, 181);
    Path.CubicTo(157, 181, 96.3500061, 45.2799988, 131, 173);
    Path.CubicTo(193.850006, 106.959991, 72.9399948, 71.4700012, 127, -7);
    Path.ClosePath;

    const Ctm = TPdfMatrix.Create(0.5, 0, 0, -0.5, 0, 100);
    for var Width in [Single(1E7), Single(1E9), Single(1E11)] do
    begin
      var Stroke := NewStroke(Width);
      Stroke.Dashes := [5, 0.062];
      Stroke.DashPhase := 32767;

      const Watch = TStopwatch.StartNew;
      FDevice.StrokePath(Path, Ctm, Stroke, Red, TPdfComposite.Default);
      AssertWithinTime(Watch, TimeLimitMilliseconds div 5, Format('A dashed stroke of width %g', [Width]));
    end;
  finally
    Path.Free;
  end;
  Assert.Pass;
end;

procedure TPdfNativeHostileTests.TestMillionsOfDashesDrawNothing;
begin
  const Path = TPdfPath.Create;
  try
    Path.MoveTo(0, 50);
    Path.LineTo(1E7, 50);

    var Stroke := NewStroke(1);
    Stroke.Dashes := [0.001, 0.001];

    const Watch = TStopwatch.StartNew;
    FDevice.StrokePath(Path, TPdfMatrix.Identity, Stroke, Red, TPdfComposite.Default);
    AssertWithinTime(Watch, TimeLimitMilliseconds, 'Ten million dashes');
  finally
    Path.Free;
  end;

  AssertNothingIsDrawn;
end;

procedure TPdfNativeHostileTests.TestDeepCurveIsBounded;
begin
  const Path = TPdfPath.Create;
  try
    Path.MoveTo(0, 0);
    Path.CubicTo(1E6, 0, -1E6, 1E6, 100, 100);
    Path.ClosePath;

    const Watch = TStopwatch.StartNew;
    FillWithPaint(Path, Red, TPdfComposite.Default);
    FDevice.StrokePath(Path, TPdfMatrix.Identity, NewStroke(2), Red, TPdfComposite.Default);
    AssertWithinTime(Watch, TimeLimitMilliseconds, 'A cubic with control points 1e6 apart');
  finally
    Path.Free;
  end;
  Assert.Pass;
end;

procedure TPdfNativeHostileTests.TestBitmapPaintWithSingularMatrixDrawsNothing;
begin
  const Tile = NewTile;
  try
    const Singular: TArray<TPdfMatrix> = [TPdfMatrix.Create(0, 0, 0, 0, 0, 0), TPdfMatrix.Create(1, 1, 1, 1, 0, 0),
                                          TPdfMatrix.Create(1, 0, 0, 0, 0, 0)];
    for var Matrix in Singular do
    begin
      FillWholeDevice(TPdfPaint.FromBitmap(Tile, Matrix, TPdfTileMode.Repeat, TPdfImageFilter.Bilinear), TPdfComposite.Default);
      FillWholeDevice(TPdfPaint.FromBitmap(Tile, Matrix, TPdfTileMode.Decal, TPdfImageFilter.Nearest), NoAntiAlias);
    end;
  finally
    Tile.Free;
  end;

  AssertNothingIsDrawn;
end;

procedure TPdfNativeHostileTests.TestPatternOfScaleZeroAndOneDrawsNothing;
begin
  const Tile = NewTile;
  try
    const Matrix = TPdfMatrix.GetScaleInstance(0, 1);
    FillWholeDevice(TPdfPaint.FromBitmap(Tile, Matrix, TPdfTileMode.Repeat, TPdfImageFilter.Bicubic), TPdfComposite.Default);
    FDevice.DrawBitmap(Tile, Matrix, TPdfImageFilter.Bilinear, TPdfComposite.Default);
  finally
    Tile.Free;
  end;

  AssertNothingIsDrawn;
end;

procedure TPdfNativeHostileTests.TestPatternOfSubnormalScaleDrawsNothing;
begin
  const Tile = NewTile;
  try
    // 1e-40 is below the smallest normal Single: the matrix has no inverse that a Single can hold
    const Subnormal: Single = 1E-40;
    const Matrices: TArray<TPdfMatrix> = [TPdfMatrix.GetScaleInstance(Subnormal, Subnormal), TPdfMatrix.GetScaleInstance(1, Subnormal)];
    for var Matrix in Matrices do
    begin
      FillWholeDevice(TPdfPaint.FromBitmap(Tile, Matrix, TPdfTileMode.Repeat, TPdfImageFilter.Bilinear), TPdfComposite.Default);
      FDevice.DrawBitmap(Tile, Matrix, TPdfImageFilter.Nearest, NoAntiAlias);
    end;
  finally
    Tile.Free;
  end;

  AssertNothingIsDrawn;
end;

procedure TPdfNativeHostileTests.TestTinyRepeatTileIsBounded;
begin
  const Tile = NewTile;
  try
    const Watch = TStopwatch.StartNew;
    FillWholeDevice(TPdfPaint.FromBitmap(Tile, TPdfMatrix.GetScaleInstance(1E-6, 1E-6), TPdfTileMode.Repeat, TPdfImageFilter.Nearest),
                    TPdfComposite.Default);
    FillWholeDevice(TPdfPaint.FromBitmap(Tile, TPdfMatrix.GetScaleInstance(1E-6, 1E-6), TPdfTileMode.Repeat, TPdfImageFilter.Bilinear),
                    NoAntiAlias);
    AssertWithinTime(Watch, TimeLimitMilliseconds, 'A tile of 1e-6');
  finally
    Tile.Free;
  end;
  Assert.Pass;
end;

procedure TPdfNativeHostileTests.TestOneByOneBitmapScaledHuge;
begin
  const Tile = NewTile;
  try
    const Watch = TStopwatch.StartNew;
    const Scale = TPdfMatrix.GetScaleInstance(1E4, 1E4);
    FDevice.DrawBitmap(Tile, Scale, TPdfImageFilter.Bicubic, TPdfComposite.Default);
    AssertWithinTime(Watch, TimeLimitMilliseconds, 'A bitmap of one pixel scaled by 1e4');
    const Color = FDevice.ToBitmap;
    try
      Assert.AreEqual(255, Integer(Color.GetPixel(50, 50).A), 'the middle of the device is covered by the one pixel');
    finally
      Color.Free;
    end;

    FillWholeDevice(TPdfPaint.FromBitmap(Tile, Scale, TPdfTileMode.Decal, TPdfImageFilter.Bicubic), TPdfComposite.Default);
  finally
    Tile.Free;
  end;
end;

procedure TPdfNativeHostileTests.TestSoftMaskWithHugeOffset;
begin
  const Opaque = TPdfAlphaMask.Create(High(Integer) - 10, High(Integer) - 10, 20, 20, 255);
  const Clear = TPdfAlphaMask.Create(High(Integer) - 10, High(Integer) - 10, 20, 20, 0);
  try
    FillWholeDeviceWithMask(Opaque);
    AssertEveryPixelIsRed;

    FDevice.Clear(TPdfDeviceColor.Transparent);
    FillWholeDeviceWithMask(Clear);
    AssertNothingIsDrawn;
  finally
    Opaque.Free;
    Clear.Free;
  end;
end;

procedure TPdfNativeHostileTests.TestSoftMaskAtTheLowestOffset;
begin
  // Left = -2^31: the right edge is a long way from the device, the pixels of the device are outside
  const Opaque = TPdfAlphaMask.Create(Low(Integer), Low(Integer), 20, 20, 255);
  const Clear = TPdfAlphaMask.Create(Low(Integer), Low(Integer), 20, 20, 0);
  try
    FillWholeDeviceWithMask(Opaque);
    AssertEveryPixelIsRed;

    FDevice.Clear(TPdfDeviceColor.Transparent);
    FillWholeDeviceWithMask(Clear);
    AssertNothingIsDrawn;
  finally
    Opaque.Free;
    Clear.Free;
  end;
end;

procedure TPdfNativeHostileTests.TestSoftMaskOfZeroSize;
begin
  const Opaque = TPdfAlphaMask.Create(0, 0, 0, 0, 255);
  const Clear = TPdfAlphaMask.Create(5, 5, 0, 7, 0);
  try
    FillWholeDeviceWithMask(Opaque);
    AssertEveryPixelIsRed;

    FDevice.Clear(TPdfDeviceColor.Transparent);
    FillWholeDeviceWithMask(Clear);
    AssertNothingIsDrawn;
  finally
    Opaque.Free;
    Clear.Free;
  end;
end;

procedure TPdfNativeHostileTests.TestSoftMaskLargerThanDevice;
begin
  // 300 x 300 from (-100, -100) with value 255 inside and 0 outside: the whole device is inside
  const Mask = TPdfAlphaMask.Create(-100, -100, 300, 300, 0);
  try
    FillChar(Mask.Values[0], Length(Mask.Values), 255);
    FillWholeDeviceWithMask(Mask);
    AssertEveryPixelIsRed;
  finally
    Mask.Free;
  end;
end;

// A mask of 10 x 10 at (20, 20): value 255 inside, 0 outside; only those pixels are drawn
procedure TPdfNativeHostileTests.TestMismatchedSoftMaskOnASmallDevice;
begin
  const Mask = TPdfAlphaMask.Create(20, 20, 10, 10, 0);
  try
    FillChar(Mask.Values[0], Length(Mask.Values), 255);
    FillWholeDeviceWithMask(Mask);

    Assert.AreEqual(10, RedPixelCount(25, 0, DeviceSize - 1), 'ten pixels in a row of the mask');
    Assert.AreEqual(0, RedPixelCount(19, 0, DeviceSize - 1), 'the row above the mask');
    Assert.AreEqual(0, RedPixelCount(30, 0, DeviceSize - 1), 'the row below the mask');
    Assert.AreEqual(10, RedPixelCount(20, 20, 29), 'the first row of the mask');
    Assert.AreEqual(10, RedPixelCount(29, 20, 29), 'the last row of the mask');
  finally
    Mask.Free;
  end;
end;

// The device is wider than a tile of the painter; the mask lies over the seam and ends before the right edge of the device
procedure TPdfNativeHostileTests.TestMismatchedSoftMaskAcrossTiles;
begin
  CreateDevice(WideDeviceWidth, 4);
  const Mask = TPdfAlphaMask.Create(4000, 1, 5000, 2, 0);
  try
    FillChar(Mask.Values[0], Length(Mask.Values), 255);
    FillWholeDeviceWithMask(Mask);

    Assert.AreEqual(0, RedPixelCount(0, 0, WideDeviceWidth - 1), 'the row above the mask');
    Assert.AreEqual(0, RedPixelCount(3, 0, WideDeviceWidth - 1), 'the row below the mask');
    for var Row := 1 to 2 do
    begin
      Assert.AreEqual(5000, RedPixelCount(Row, 0, WideDeviceWidth - 1), Format('the pixels of the mask in row %d', [Row]));
      Assert.AreEqual(5000, RedPixelCount(Row, 4000, 8999), Format('and they are the ones from 4000 on, row %d', [Row]));
    end;
  finally
    Mask.Free;
  end;
end;

procedure TPdfNativeHostileTests.TestDrawBitmapAtHighIntegerDrawsNothing;
begin
  const Tile = NewTile;
  try
    const Offsets: TArray<Single> = [2147483647, 2147483648, 3E9, -2147483648, -3E9];
    for var Offset in Offsets do
    begin
      FDevice.DrawBitmap(Tile, TPdfMatrix.Create(1, 0, 0, 1, Offset, Offset), TPdfImageFilter.Nearest, NoAntiAlias);
      FDevice.DrawBitmap(Tile, TPdfMatrix.Create(1, 0, 0, 1, Offset, 0), TPdfImageFilter.Bilinear, TPdfComposite.Default);
      FDevice.DrawBitmap(Tile, TPdfMatrix.Create(1, 0, 0, 1, 0, Offset), TPdfImageFilter.Bicubic, TPdfComposite.Default);
    end;
  finally
    Tile.Free;
  end;

  AssertNothingIsDrawn;
end;

procedure TPdfNativeHostileTests.TestBitmapPaintAtHighIntegerDrawsNothing;
begin
  const Tile = NewTile;
  try
    const Offsets: TArray<Single> = [2147483647, 2147483648, 3E9, -2147483648, -3E9];
    for var Offset in Offsets do
    begin
      FillWholeDevice(TPdfPaint.FromBitmap(Tile, TPdfMatrix.Create(1, 0, 0, 1, Offset, Offset), TPdfTileMode.Decal, TPdfImageFilter.Nearest),
                      TPdfComposite.Default);
    end;
  finally
    Tile.Free;
  end;

  AssertNothingIsDrawn;
end;

procedure TPdfNativeHostileTests.TestClipWithNaNPointClipsEverything;
begin
  const Path = NewPathOfCoordinates([10, 10, 90, Single.NaN, 95, 50, 90, 90, 70, 95, 30, 95, 10, 90]);
  FDevice.SetClip(TPdfClipPath.Create(nil, Path, TPdfMatrix.Identity, TPdfFillRule.NonZero));
  FillWholeDevice(Red, NoAntiAlias);
  FillWholeDevice(Red, TPdfComposite.Default);

  AssertNothingIsDrawn;
end;

procedure TPdfNativeHostileTests.TestClipRectOf3e9DoesNotClip;
begin
  FDevice.SetClip(NewClip(nil, 0, 0, 3E9, 3E9));
  FillWholeDevice(Red, NoAntiAlias);

  AssertEveryPixelIsRed;
end;

procedure TPdfNativeHostileTests.TestClipRectOf1e30DoesNotClip;
begin
  FDevice.SetClip(NewClip(nil, -1E30, -1E30, 1E30, 1E30));
  FillWholeDevice(Red, NoAntiAlias);

  AssertEveryPixelIsRed;
end;

procedure TPdfNativeHostileTests.TestHundredThousandRectClipsAreAppliedOnce;
begin
  const PathCount: Integer = 100000;
  var Clip: IPdfClipPath := nil;
  const Watch = TStopwatch.StartNew;
  for var Index := 1 to PathCount do
  begin
    Clip := NewClip(Clip, Index * 0.0001, 0, DeviceSize, DeviceSize);
    FDevice.SetClip(Clip);
    FillRect(80, 40, 81, 41, Red, NoAntiAlias);
  end;

  AssertWithinTime(Watch, TimeLimitMilliseconds * 6, '100 000 clips with a draw after each');
  Assert.AreEqual(PathCount, Native.ClipLinkCount, 'every path is applied once');
  Assert.AreEqual(1, RedPixelCount(40, 80, 80));
end;

procedure TPdfNativeHostileTests.TestThousandNonRectClipsAreAppliedOnce;
begin
  const LinkCount = 1000;
  var Clip: IPdfClipPath := nil;
  const Watch = TStopwatch.StartNew;
  for var Index := 1 to LinkCount do
  begin
    Clip := NewDiamondClipAround(Clip, 50, 50, 49 - Index * 0.04);
    FDevice.SetClip(Clip);
    FillRect(50, 50, 51, 51, Red, NoAntiAlias);
  end;

  AssertWithinTime(Watch, TimeLimitMilliseconds * 6, '1 000 diamond clips with a draw after each');
  Assert.AreEqual(LinkCount, Native.ClipLinkCount, 'every path is applied once');
  Assert.AreEqual(1, RedPixelCount(50, 50, 50));
end;

// A stroke of the red tile under a transform that stretches x by 100 and y by 0.01 (a condition of 1e4): the shader keeps the place of the
// bitmap. The line runs along x from path x 0 to 1 (device 0 to 100) at path y 5000 (device 50) and is 1000 wide (device 10 high).
procedure TPdfNativeHostileTests.TestStrokeWithBitmapPaintUnderIllConditionedCtm;
begin
  const Tile = NewTile;
  const Path = TPdfPath.Create;
  try
    Path.MoveTo(0, 5000);
    Path.LineTo(1, 5000);

    const Ctm = TPdfMatrix.Create(100, 0, 0, 0.01, 0, 0);
    const Paint = TPdfPaint.FromBitmap(Tile, TPdfMatrix.GetScaleInstance(1000, 1000), TPdfTileMode.Decal, TPdfImageFilter.Nearest);
    FDevice.StrokePath(Path, Ctm, NewStroke(1000), Paint, NoAntiAlias);

    Assert.AreEqual(DeviceSize, RedPixelCount(50, 0, DeviceSize - 1), 'the stroke is painted with the bitmap along its whole length');
    Assert.AreEqual(0, RedPixelCount(10, 0, DeviceSize - 1), 'and not outside it');
  finally
    Path.Free;
    Tile.Free;
  end;
end;

// The same at a condition of 1e12 (x by 1e6, y by 1e-6, width 1e7): the width is cut to 1e6 pixels along the largest stretch, which leaves
// less than a pixel across the line, so nothing may show; the call has to end in time without an exception
procedure TPdfNativeHostileTests.TestStrokeWithBitmapPaintUnderTheWorstCtmIsBounded;
begin
  const Tile = NewTile;
  const Path = TPdfPath.Create;
  try
    Path.MoveTo(0, 5E7);
    Path.LineTo(1E-4, 5E7);

    const Ctm = TPdfMatrix.Create(1E6, 0, 0, 1E-6, 0, 0);
    const Paint = TPdfPaint.FromBitmap(Tile, TPdfMatrix.GetScaleInstance(1000, 1000), TPdfTileMode.Decal, TPdfImageFilter.Nearest);
    const Watch = TStopwatch.StartNew;
    FDevice.StrokePath(Path, Ctm, NewStroke(1E7), Paint, NoAntiAlias);
    FDevice.StrokePath(Path, Ctm, NewStroke(1), Paint, TPdfComposite.Default);
    AssertWithinTime(Watch, TimeLimitMilliseconds, 'A stroke under a transform of the condition 1e12');
  finally
    Path.Free;
    Tile.Free;
  end;
  Assert.Pass;
end;

// Values that break arithmetic, now and then; else a coordinate around the device
function TPdfNativeHostileTests.RandomValue: Single;
begin
  case Random(24) of
    0: Result := Single.NaN;
    1: Result := Single.PositiveInfinity;
    2: Result := Single.NegativeInfinity;
    3: Result := 1E30;
    4: Result := -1E30;
    5: Result := 1E-30;
    6: Result := 3E9;
    7: Result := 2147483648.0;
    8: Result := Single.MaxValue;
    9: Result := -Single.MaxValue;
    10: Result := 1E-40;
    11: Result := 0;
    12: Result := 1;
    13: Result := -1;
    14: Result := 1E6;
  else
    Result := Random * 200 - 50;
  end;
end;

function TPdfNativeHostileTests.RandomMatrix: TPdfMatrix;
begin
  if Random(2) = 0 then
  begin
    Exit(TPdfMatrix.Create(0.2 + Random * 3, Random - 0.5, Random - 0.5, 0.2 + Random * 3, Random * 50 - 20, Random * 50 - 20));
  end;

  Result := TPdfMatrix.Create(RandomValue, RandomValue, RandomValue, RandomValue, RandomValue, RandomValue);
end;

function TPdfNativeHostileTests.RandomPath: TPdfPath;
begin
  Result := TPdfPath.Create;
  var VerbCount := Random(13);
  if Random(50) = 0 then
  begin
    VerbCount := 2000;
  end;

  for var Index := 1 to VerbCount do
  begin
    case Random(5) of
      0: Result.MoveTo(RandomValue, RandomValue);
      1: Result.LineTo(RandomValue, RandomValue);
      2: Result.QuadTo(RandomValue, RandomValue, RandomValue, RandomValue);
      3: Result.CubicTo(RandomValue, RandomValue, RandomValue, RandomValue, RandomValue, RandomValue);
    else
      Result.ClosePath;
    end;
  end;
end;

// A clip on one of the clips that came before, or on nothing. The clip works out the bounds of its path, so it is made with the floating
// point exceptions masked, as the renderer makes it.
function TPdfNativeHostileTests.RandomClip: IPdfClipPath;
begin
  const FloatState = TPdfFloatGuard.Enter;
  try
    var Parent: IPdfClipPath := nil;
    if (Length(FRandomClips) > 0) and (Random(2) = 0) then
    begin
      Parent := FRandomClips[Random(Length(FRandomClips))];
    end;
    Result := TPdfClipPath.Create(Parent, RandomPath, RandomMatrix, TPdfFillRule(Random(2)));
  finally
    TPdfFloatGuard.Leave(FloatState);
  end;

  const PoolSize = 8;
  if Length(FRandomClips) < PoolSize then
  begin
    FRandomClips := FRandomClips + [Result];
  end
  else
  begin
    FRandomClips[Random(PoolSize)] := Result;
  end;
end;

function TPdfNativeHostileTests.RandomStroke: TPdfStrokeStyle;
begin
  Result := Default(TPdfStrokeStyle);
  Result.Width := Random * 10;
  if Random(2) = 0 then
  begin
    Result.Width := RandomValue;
  end;
  Result.Cap := TPdfLineCap(Random(3));
  Result.Join := TPdfLineJoin(Random(3));
  Result.MiterLimit := RandomValue;
  if Random(3) = 0 then
  begin
    SetLength(Result.Dashes, Random(5));
    for var Index := 0 to High(Result.Dashes) do
    begin
      Result.Dashes[Index] := Random * 5;
      if Random(4) = 0 then
      begin
        Result.Dashes[Index] := RandomValue;
      end;
    end;
  end;
  Result.DashPhase := RandomValue;
end;

function TPdfNativeHostileTests.RandomComposite: TPdfComposite;
begin
  Result := TPdfComposite.Default;
  Result.Alpha := Random;
  if Random(3) = 0 then
  begin
    Result.Alpha := RandomValue;
  end;
  Result.BlendMode := TPdfBlendMode(Random(Ord(High(TPdfBlendMode)) + 1));
  if Random(3) = 0 then
  begin
    Result.SoftMask := FRandomMasks[Random(Length(FRandomMasks))];
  end;
  Result.AntiAlias := (Random(2) = 0);
end;

function TPdfNativeHostileTests.RandomPaint: TPdfPaint;
begin
  if Random(3) = 0 then
  begin
    Exit(TPdfPaint.FromBitmap(FRandomBitmaps[Random(Length(FRandomBitmaps))], RandomMatrix, TPdfTileMode(Random(2)),
                              TPdfImageFilter(Random(3))));
  end;

  Result := TPdfPaint.Solid(TPdfDeviceColor.Create(Random(256), Random(256), Random(256), Random(256)));
end;

// Bitmaps with any bytes (not even premultiplied) and masks of every kind that the tests above pin one by one
procedure TPdfNativeHostileTests.MakeRandomPools;
begin
  const Sizes: TArray<TSize> = [TSize.Create(1, 1), TSize.Create(3, 3), TSize.Create(7, 2)];
  for var Size in Sizes do
  begin
    const Bitmap = TPdfBitmap.Create(Size.cx, Size.cy);
    FRandomBitmaps := FRandomBitmaps + [Bitmap];
    for var Index := 0 to High(Bitmap.Pixels) do
    begin
      Bitmap.Pixels[Index] := Random(256);
    end;
  end;

  FRandomMasks := [TPdfAlphaMask.Create(0, 0, 0, 0, 128), TPdfAlphaMask.Create(10, 10, 50, 50, 0), TPdfAlphaMask.Create(-5, -5, 200, 200, 255),
                   TPdfAlphaMask.Create(High(Integer) - 10, Low(Integer), 20, 20, 255), TPdfAlphaMask.Create(Low(Integer), 0, 20, 20, 0)];
  for var Mask in FRandomMasks do
  begin
    for var Index := 0 to High(Mask.Values) do
    begin
      Mask.Values[Index] := Random(256);
    end;
  end;
end;

procedure TPdfNativeHostileTests.FreeRandomPools;
begin
  for var Bitmap in FRandomBitmaps do
  begin
    Bitmap.Free;
  end;
  FRandomBitmaps := nil;

  for var Mask in FRandomMasks do
  begin
    Mask.Free;
  end;
  FRandomMasks := nil;
  FRandomClips := nil;
end;

// One call of a method of the device with random arguments. A layer gets a few calls of its own and is drawn on the device.
procedure TPdfNativeHostileTests.DoRandomCall(const Device: IPdfRasterDevice; const Depth: Integer);
begin
  case Random(10) of
    0:
      begin
        if Random(8) = 0 then
        begin
          Device.SetClip(nil);
        end
        else
        begin
          Device.SetClip(RandomClip);
        end;
      end;
    1, 2:
      begin
        const Path = RandomPath;
        try
          Device.FillPath(Path, RandomMatrix, TPdfFillRule(Random(2)), RandomPaint, RandomComposite);
        finally
          Path.Free;
        end;
      end;
    3, 4:
      begin
        const Path = RandomPath;
        try
          Device.StrokePath(Path, RandomMatrix, RandomStroke, RandomPaint, RandomComposite);
        finally
          Path.Free;
        end;
      end;
    5:
      begin
        Device.DrawBitmap(FRandomBitmaps[Random(Length(FRandomBitmaps))], RandomMatrix, TPdfImageFilter(Random(3)), RandomComposite);
      end;
    6:
      begin
        Device.Clear(TPdfDeviceColor.Create(Random(256), Random(256), Random(256), Random(256)));
      end;
    7:
      begin
        const LayerDepthLimit = 2;
        if Depth < LayerDepthLimit then
        begin
          const Layer = Device.CreateLayer(Random(60) + 1, Random(60) + 1);
          for var Index := 1 to 3 do
          begin
            DoRandomCall(Layer, Depth + 1);
          end;
          const Pixels = Layer.ToBitmap;
          try
            Device.DrawBitmap(Pixels, RandomMatrix, TPdfImageFilter(Random(3)), RandomComposite);
          finally
            Pixels.Free;
          end;
        end;
      end;
    8:
      begin
        var Pixels: TPdfBitmap;
        const Area = TRect.Create(Round(Random * 140 - 20), Round(Random * 140 - 20), Round(Random * 140 - 20), Round(Random * 140 - 20));
        if Device.TryReadPixels(Area, Pixels) then
        begin
          Pixels.Free;
        end;
      end;
  else
    begin
      const Pixels = Device.ToBitmap;
      Pixels.Free;
    end;
  end;
end;

procedure TPdfNativeHostileTests.TestRandomDeviceCallsAreSafe;
begin
  RandSeed := RandomSeed;
  MakeRandomPools;

  for var Index := 1 to RandomCallCount do
  begin
    const Watch = TStopwatch.StartNew;
    try
      DoRandomCall(FDevice, 0);
    except
      on E: Exception do
      begin
        if not (E is EPdfLimitExceededException) then
        begin
          Assert.Fail(Format('Call %d (seed %d) raised %s: %s', [Index, RandomSeed, E.ClassName, E.Message]));
        end;
      end;
    end;
    AssertWithinTime(Watch, CallLimitMilliseconds, Format('Call %d (seed %d)', [Index, RandomSeed]));
  end;
  Assert.Pass;
end;

end.
