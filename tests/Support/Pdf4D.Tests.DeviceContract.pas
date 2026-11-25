// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.DeviceContract;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Types,
  System.Math,
  System.Diagnostics,
  DUnitX.TestFramework,
  Pdf4D.Common.Matrix,
  Pdf4D.Common.Path,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.ClipPath,
  Pdf4D.Render.Device.Interfaces;

type
  // The tests of the device contract of the renderer (IPdfRenderBackend and IPdfRasterDevice) that every backend has to pass. A backend has a
  // fixture that inherits from this class, adds [TestFixture] and says in CreateBackend which backend it is; the base class has no
  // [TestFixture] itself, so the runner never creates it.
  TPdfDeviceContractTests = class abstract
  protected
    FBackend: IPdfRenderBackend;
    FDevice: IPdfRasterDevice;
    FSnapshot: TPdfBitmap;

    function CreateBackend: IPdfRenderBackend; virtual; abstract;
    procedure CreateDevice(const Width, Height: Integer);
    function NewRectPath(const Left, Top, Right, Bottom: Single): TPdfPath;
    function NewLinePath(const FromX, FromY, ToX, ToY: Single): TPdfPath;
    function NewClip(const Parent: IPdfClipPath; const Left, Top, Right, Bottom: Single): IPdfClipPath;
    function NewStroke(const Width: Single; const Cap: TPdfLineCap): TPdfStrokeStyle;
    function NoAntiAlias: TPdfComposite;
    function Red: TPdfPaint;
    procedure FillRect(const Left, Top, Right, Bottom: Single; const Paint: TPdfPaint; const Composite: TPdfComposite);
    procedure FillWholeDevice(const Paint: TPdfPaint; const Composite: TPdfComposite);
    procedure StrokeLine(const FromX, FromY, ToX, ToY: Single; const Transform: TPdfMatrix; const Stroke: TPdfStrokeStyle);
    function Pixel(const X, Y: Integer): TPdfDeviceColor;
    procedure AssertPixel(const X, Y: Integer; const Expected: TPdfDeviceColor; const Tolerance: Integer = 0);
    procedure AssertTransparent(const X, Y: Integer);
    function NewTile: TPdfBitmap;
    function NewMask(const Left, Top, Width, Height: Integer; const Value, OutsideValue: Byte): TPdfAlphaMask;
    procedure FillOpaqueBackground(const Color: TPdfDeviceColor);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestFillRectWithoutAntiAlias;

    // Java2D puts the edge of a rectangle that is filled without anti-aliasing at ceil(x) (measured on the 1296 squares of the QR code of
    // PDFBOX-6207: 61 of 19044 pixels differ with ceil, 1479 with the clip rule, 2766 with the nearest boundary)
    [Test]
    procedure TestFillWithoutAntiAliasFollowsJava2D;

    // With another scale than 1 the edge is at floor(x + 0.25), as for a clip
    [Test]
    procedure TestFillWithoutAntiAliasAtAnotherScaleFollowsTheClipRule;

    [Test]
    procedure TestHalfAlphaIsPremultiplied;

    [Test]
    procedure TestEvenOddLeavesHole;

    [Test]
    procedure TestNonZeroFillsHole;

    [Test]
    procedure TestStrokeIsTransformed;

    [Test]
    procedure TestDashesInPathSpace;

    [Test]
    procedure TestRoundCapExtendsLine;

    [Test]
    procedure TestClipIsNotAntiAliased;

    // Java2D puts a clip edge at floor(x + 0.25), where the rasterizer alone would take the nearest pixel boundary
    [Test]
    procedure TestClipEdgeFollowsJava2D;

    [Test]
    procedure TestClipChainIntersects;

    [Test]
    procedure TestSetClipNilRemovesClip;

    [Test]
    procedure TestSwitchingBetweenBranchesOfAClipChain;

    [Test]
    procedure TestLongClipChainIsAppliedPathByPath;

    [Test]
    procedure TestDrawBitmapNearest;

    [Test]
    procedure TestBitmapPaintRepeats;

    [Test]
    procedure TestBitmapPaintDecalOutsideIsTransparent;

    [Test]
    procedure TestBitmapPaintFollowsTransform;

    [Test]
    procedure TestClearIgnoresClip;

    [Test]
    procedure TestToBitmapIsPremultipliedRgba;

    [Test]
    procedure TestTryReadPixelsClipsToDevice;

    [Test]
    procedure TestTryReadPixelsOutsideTheDeviceGivesNothing;

    [Test]
    procedure TestTooLargeDeviceRaises;

    [Test]
    procedure TestTransformUsesThePdfMatrixConvention;

    [Test]
    procedure TestSingularTransformDrawsNothing;

    [Test]
    procedure TestLayerIsTransparentAndSeparate;

    [Test]
    procedure TestExceptionMaskSurvivesDrawing;

    [Test]
    procedure TestVeryLongClipChain;

    [Test]
    procedure TestNearSingularBitmapPaintDrawsNothing;
  end;

implementation

{ TPdfDeviceContractTests }

procedure TPdfDeviceContractTests.Setup;
begin
  FBackend := CreateBackend;
  CreateDevice(10, 10);
end;

procedure TPdfDeviceContractTests.TearDown;
begin
  FSnapshot.Free;
  FSnapshot := nil;
  FDevice := nil;
  FBackend := nil;
end;

procedure TPdfDeviceContractTests.CreateDevice(const Width, Height: Integer);
begin
  FDevice := FBackend.CreateRasterDevice(Width, Height);
end;

function TPdfDeviceContractTests.NewRectPath(const Left, Top, Right, Bottom: Single): TPdfPath;
begin
  Result := TPdfPath.Create;
  Result.MoveTo(Left, Top);
  Result.LineTo(Right, Top);
  Result.LineTo(Right, Bottom);
  Result.LineTo(Left, Bottom);
  Result.ClosePath;
end;

function TPdfDeviceContractTests.NewLinePath(const FromX, FromY, ToX, ToY: Single): TPdfPath;
begin
  Result := TPdfPath.Create;
  Result.MoveTo(FromX, FromY);
  Result.LineTo(ToX, ToY);
end;

function TPdfDeviceContractTests.NewClip(const Parent: IPdfClipPath; const Left, Top, Right, Bottom: Single): IPdfClipPath;
begin
  Result := TPdfClipPath.Create(Parent, NewRectPath(Left, Top, Right, Bottom), TPdfMatrix.Identity, TPdfFillRule.NonZero);
end;

function TPdfDeviceContractTests.NewStroke(const Width: Single; const Cap: TPdfLineCap): TPdfStrokeStyle;
begin
  Result := Default(TPdfStrokeStyle);
  Result.Width := Width;
  Result.Cap := Cap;
  Result.Join := TPdfLineJoin.Miter;
  Result.MiterLimit := 10;
end;

function TPdfDeviceContractTests.NoAntiAlias: TPdfComposite;
begin
  Result := TPdfComposite.Default;
  Result.AntiAlias := False;
end;

function TPdfDeviceContractTests.Red: TPdfPaint;
begin
  Result := TPdfPaint.Solid(TPdfDeviceColor.Create(255, 0, 0));
end;

procedure TPdfDeviceContractTests.FillRect(const Left, Top, Right, Bottom: Single; const Paint: TPdfPaint; const Composite: TPdfComposite);
begin
  const Path = NewRectPath(Left, Top, Right, Bottom);
  try
    FDevice.FillPath(Path, TPdfMatrix.Identity, TPdfFillRule.NonZero, Paint, Composite);
  finally
    Path.Free;
  end;
end;

procedure TPdfDeviceContractTests.FillWholeDevice(const Paint: TPdfPaint; const Composite: TPdfComposite);
begin
  FillRect(0, 0, FDevice.Width, FDevice.Height, Paint, Composite);
end;

procedure TPdfDeviceContractTests.StrokeLine(const FromX, FromY, ToX, ToY: Single; const Transform: TPdfMatrix; const Stroke: TPdfStrokeStyle);
begin
  const Path = NewLinePath(FromX, FromY, ToX, ToY);
  try
    FDevice.StrokePath(Path, Transform, Stroke, Red, NoAntiAlias);
  finally
    Path.Free;
  end;
end;

function TPdfDeviceContractTests.Pixel(const X, Y: Integer): TPdfDeviceColor;
begin
  FSnapshot.Free;
  FSnapshot := FDevice.ToBitmap;
  Result := FSnapshot.GetPixel(X, Y);
end;

procedure TPdfDeviceContractTests.AssertPixel(const X, Y: Integer; const Expected: TPdfDeviceColor; const Tolerance: Integer);
begin
  const Actual = Pixel(X, Y);
  const Message = Format('Pixel (%d, %d) is (%d,%d,%d,%d)', [X, Y, Actual.R, Actual.G, Actual.B, Actual.A]);

  Assert.AreEqual(Integer(Expected.R), Integer(Actual.R), Tolerance, Message);
  Assert.AreEqual(Integer(Expected.G), Integer(Actual.G), Tolerance, Message);
  Assert.AreEqual(Integer(Expected.B), Integer(Actual.B), Tolerance, Message);
  Assert.AreEqual(Integer(Expected.A), Integer(Actual.A), Tolerance, Message);
end;

procedure TPdfDeviceContractTests.AssertTransparent(const X, Y: Integer);
begin
  AssertPixel(X, Y, TPdfDeviceColor.Transparent);
end;

function TPdfDeviceContractTests.NewTile: TPdfBitmap;
begin
  Result := TPdfBitmap.Create(2, 2);
  const Black = TPdfDeviceColor.Create(0, 0, 0);
  const White = TPdfDeviceColor.White;
  Result.SetPixel(0, 0, Black);
  Result.SetPixel(1, 0, White);
  Result.SetPixel(0, 1, White);
  Result.SetPixel(1, 1, Black);
end;

function TPdfDeviceContractTests.NewMask(const Left, Top, Width, Height: Integer; const Value, OutsideValue: Byte): TPdfAlphaMask;
begin
  Result := TPdfAlphaMask.Create(Left, Top, Width, Height, OutsideValue);
  var Values := Result.Values;
  for var Index := 0 to Length(Values) - 1 do
  begin
    Values[Index] := Value;
  end;
end;

procedure TPdfDeviceContractTests.FillOpaqueBackground(const Color: TPdfDeviceColor);
begin
  FillWholeDevice(TPdfPaint.Solid(Color), NoAntiAlias);
end;

procedure TPdfDeviceContractTests.TestFillRectWithoutAntiAlias;
begin
  FillRect(2, 2, 8, 8, Red, NoAntiAlias);

  AssertPixel(5, 5, TPdfDeviceColor.Create(255, 0, 0));
  AssertTransparent(1, 1);
  AssertTransparent(8, 8);
end;

procedure TPdfDeviceContractTests.TestFillWithoutAntiAliasFollowsJava2D;
begin
  // 2.2 acts as 3 and 7.2 as 8: the pixels 3 to 7; the nearest boundaries would be 2 and 7
  FillRect(2.2, 2.2, 7.2, 7.2, Red, NoAntiAlias);

  AssertPixel(3, 3, TPdfDeviceColor.Create(255, 0, 0));
  AssertPixel(7, 7, TPdfDeviceColor.Create(255, 0, 0));
  AssertTransparent(2, 5);
  AssertTransparent(8, 5);
  AssertTransparent(5, 8);
  AssertTransparent(5, 2);
end;

procedure TPdfDeviceContractTests.TestFillWithoutAntiAliasAtAnotherScaleFollowsTheClipRule;
begin
  const Path = NewRectPath(1.1, 1.1, 3.6, 3.6);
  try
    // Device 2.2 to 7.2: floor(2.45) = 2 and floor(7.45) = 7, the pixels 2 to 6 (ceil would give 3 to 7)
    FDevice.FillPath(Path, TPdfMatrix.GetScaleInstance(2, 2), TPdfFillRule.NonZero, Red, NoAntiAlias);
  finally
    Path.Free;
  end;

  AssertPixel(2, 2, TPdfDeviceColor.Create(255, 0, 0));
  AssertPixel(6, 6, TPdfDeviceColor.Create(255, 0, 0));
  AssertTransparent(1, 5);
  AssertTransparent(7, 5);
end;

procedure TPdfDeviceContractTests.TestHalfAlphaIsPremultiplied;
begin
  var Composite := NoAntiAlias;
  Composite.Alpha := 0.5;

  FillRect(2, 2, 8, 8, Red, Composite);

  AssertPixel(5, 5, TPdfDeviceColor.Create(128, 0, 0, 128), 1);
end;

procedure TPdfDeviceContractTests.TestEvenOddLeavesHole;
begin
  const Path = NewRectPath(0, 0, 10, 10);
  try
    Path.MoveTo(3, 3);
    Path.LineTo(7, 3);
    Path.LineTo(7, 7);
    Path.LineTo(3, 7);
    Path.ClosePath;

    FDevice.FillPath(Path, TPdfMatrix.Identity, TPdfFillRule.EvenOdd, Red, NoAntiAlias);
  finally
    Path.Free;
  end;

  AssertTransparent(5, 5);
  AssertPixel(1, 1, TPdfDeviceColor.Create(255, 0, 0));
end;

procedure TPdfDeviceContractTests.TestNonZeroFillsHole;
begin
  const Path = NewRectPath(0, 0, 10, 10);
  try
    Path.MoveTo(3, 3);
    Path.LineTo(7, 3);
    Path.LineTo(7, 7);
    Path.LineTo(3, 7);
    Path.ClosePath;

    FDevice.FillPath(Path, TPdfMatrix.Identity, TPdfFillRule.NonZero, Red, NoAntiAlias);
  finally
    Path.Free;
  end;

  AssertPixel(5, 5, TPdfDeviceColor.Create(255, 0, 0));
end;

procedure TPdfDeviceContractTests.TestStrokeIsTransformed;
begin
  StrokeLine(0, 1.25, 2.5, 1.25, TPdfMatrix.GetScaleInstance(4, 4), NewStroke(0.5, TPdfLineCap.Butt));

  for var X := 0 to 9 do
  begin
    AssertPixel(X, 4, TPdfDeviceColor.Create(255, 0, 0));
    AssertPixel(X, 5, TPdfDeviceColor.Create(255, 0, 0));
  end;
  AssertTransparent(5, 2);
  AssertTransparent(5, 7);
end;

procedure TPdfDeviceContractTests.TestDashesInPathSpace;
begin
  var Stroke := NewStroke(2, TPdfLineCap.Butt);
  Stroke.Dashes := [2, 2];

  StrokeLine(0, 5, 10, 5, TPdfMatrix.Identity, Stroke);

  AssertPixel(0, 5, TPdfDeviceColor.Create(255, 0, 0));
  AssertPixel(1, 5, TPdfDeviceColor.Create(255, 0, 0));
  AssertTransparent(2, 5);
  AssertTransparent(3, 5);
  AssertPixel(4, 5, TPdfDeviceColor.Create(255, 0, 0));
  AssertPixel(5, 5, TPdfDeviceColor.Create(255, 0, 0));
end;

procedure TPdfDeviceContractTests.TestRoundCapExtendsLine;
begin
  CreateDevice(12, 12);
  StrokeLine(1, 5, 9, 5, TPdfMatrix.Identity, NewStroke(2, TPdfLineCap.Round));
  AssertPixel(0, 5, TPdfDeviceColor.Create(255, 0, 0));
  AssertTransparent(10, 5);

  CreateDevice(12, 12);
  StrokeLine(1, 5, 9, 5, TPdfMatrix.Identity, NewStroke(2, TPdfLineCap.Butt));
  AssertTransparent(0, 5);
end;

procedure TPdfDeviceContractTests.TestClipIsNotAntiAliased;
begin
  FDevice.SetClip(NewClip(nil, 2.5, 2.5, 7.5, 7.5));

  FillWholeDevice(Red, TPdfComposite.Default);

  FSnapshot := FDevice.ToBitmap;
  var HasPartialAlpha := False;
  for var Y := 0 to 9 do
  begin
    for var X := 0 to 9 do
    begin
      const Alpha = FSnapshot.GetPixel(X, Y).A;
      HasPartialAlpha := HasPartialAlpha or ((Alpha <> 0) and (Alpha <> 255));
    end;
  end;
  Assert.IsFalse(HasPartialAlpha, 'The clip edge must not produce partial alpha');
  Assert.AreEqual(255, Integer(FSnapshot.GetPixel(5, 5).A));
  Assert.AreEqual(0, Integer(FSnapshot.GetPixel(1, 1).A));
end;

procedure TPdfDeviceContractTests.TestClipEdgeFollowsJava2D;
begin
  // The left edge 2.6 acts as 2 (floor(2.85)), the right edge 7.6 as 7 (floor(7.85)); the nearest boundaries would be 3 and 8
  FDevice.SetClip(NewClip(nil, 2.6, 2.6, 7.6, 7.6));

  FillWholeDevice(Red, NoAntiAlias);

  AssertPixel(2, 2, TPdfDeviceColor.Create(255, 0, 0));
  AssertPixel(6, 6, TPdfDeviceColor.Create(255, 0, 0));
  AssertTransparent(1, 5);
  AssertTransparent(7, 5);
  AssertTransparent(5, 7);
  AssertTransparent(5, 1);
end;

procedure TPdfDeviceContractTests.TestClipChainIntersects;
begin
  const First = NewClip(nil, 2, 2, 8, 8);
  FDevice.SetClip(NewClip(First, 5, 5, 10, 10));

  FillWholeDevice(Red, NoAntiAlias);

  AssertPixel(6, 6, TPdfDeviceColor.Create(255, 0, 0));
  AssertTransparent(3, 3);
  AssertTransparent(9, 9);
  AssertTransparent(3, 6);
  AssertTransparent(6, 3);
end;

procedure TPdfDeviceContractTests.TestSetClipNilRemovesClip;
begin
  FDevice.SetClip(NewClip(nil, 2, 2, 4, 4));
  FDevice.SetClip(nil);

  FillWholeDevice(Red, NoAntiAlias);

  AssertPixel(9, 9, TPdfDeviceColor.Create(255, 0, 0));
end;

// The device keeps the paths that it has applied and applies only the others: a clip on another branch of the same chain, a parent and a
// deeper clip all have to give the intersection of their own chain
procedure TPdfDeviceContractTests.TestSwitchingBetweenBranchesOfAClipChain;
begin
  const Root = NewClip(nil, 0, 0, 10, 10);
  const Left = NewClip(Root, 0, 0, 5, 10);
  const Right = NewClip(Root, 5, 0, 10, 10);
  const UpperLeft = NewClip(Left, 0, 0, 5, 5);
  const Blue = TPdfDeviceColor.Create(0, 0, 255);
  const Green = TPdfDeviceColor.Create(0, 255, 0);

  FDevice.SetClip(UpperLeft);
  FillWholeDevice(Red, NoAntiAlias);
  FDevice.SetClip(Right);
  FillWholeDevice(TPdfPaint.Solid(Blue), NoAntiAlias);
  FDevice.SetClip(Left);
  FillRect(0, 5, 10, 10, TPdfPaint.Solid(Green), NoAntiAlias);

  AssertPixel(2, 2, TPdfDeviceColor.Create(255, 0, 0));
  AssertPixel(7, 2, Blue);
  AssertPixel(7, 7, Blue);
  AssertPixel(2, 7, Green);
end;

// 3000 paths, and the clip changes to every one of them: applying the whole chain at each change would be 4.5 million paths
procedure TPdfDeviceContractTests.TestLongClipChainIsAppliedPathByPath;
begin
  const PathCount = 3000;
  var Clip: IPdfClipPath := nil;
  const Watch = TStopwatch.StartNew;
  for var Index := 1 to PathCount do
  begin
    Clip := NewClip(Clip, Index * 0.001, 0, 10, 10);
    FDevice.SetClip(Clip);
  end;
  FillWholeDevice(Red, NoAntiAlias);

  Assert.IsTrue(Watch.ElapsedMilliseconds < 5000, Format('Took %d ms', [Watch.ElapsedMilliseconds]));
  AssertPixel(8, 5, TPdfDeviceColor.Create(255, 0, 0));
end;

procedure TPdfDeviceContractTests.TestDrawBitmapNearest;
begin
  const Bitmap = TPdfBitmap.Create(2, 1);
  try
    Bitmap.SetPixel(0, 0, TPdfDeviceColor.Create(255, 0, 0));
    Bitmap.SetPixel(1, 0, TPdfDeviceColor.Create(0, 0, 255));

    FDevice.DrawBitmap(Bitmap, TPdfMatrix.GetScaleInstance(4, 4), TPdfImageFilter.Nearest, NoAntiAlias);
  finally
    Bitmap.Free;
  end;

  AssertPixel(1, 0, TPdfDeviceColor.Create(255, 0, 0));
  AssertPixel(5, 0, TPdfDeviceColor.Create(0, 0, 255));
  AssertTransparent(9, 0);
end;

procedure TPdfDeviceContractTests.TestBitmapPaintRepeats;
begin
  const Tile = NewTile;
  try
    const Paint = TPdfPaint.FromBitmap(Tile, TPdfMatrix.Identity, TPdfTileMode.&Repeat, TPdfImageFilter.Nearest);
    FillWholeDevice(Paint, NoAntiAlias);
  finally
    Tile.Free;
  end;

  AssertPixel(0, 0, TPdfDeviceColor.Create(0, 0, 0));
  AssertPixel(2, 2, TPdfDeviceColor.Create(0, 0, 0));
  AssertPixel(3, 2, TPdfDeviceColor.Create(255, 255, 255));
end;

procedure TPdfDeviceContractTests.TestBitmapPaintDecalOutsideIsTransparent;
begin
  const Tile = NewTile;
  try
    const Paint = TPdfPaint.FromBitmap(Tile, TPdfMatrix.Identity, TPdfTileMode.Decal, TPdfImageFilter.Nearest);
    FillWholeDevice(Paint, NoAntiAlias);
  finally
    Tile.Free;
  end;

  AssertPixel(0, 0, TPdfDeviceColor.Create(0, 0, 0));
  AssertPixel(1, 0, TPdfDeviceColor.Create(255, 255, 255));
  AssertTransparent(5, 5);
  AssertTransparent(2, 0);
end;

procedure TPdfDeviceContractTests.TestBitmapPaintFollowsTransform;
begin
  // The bitmap-to-device matrix is in device pixels, whatever transform the path has
  const Tile = NewTile;
  const Path = NewRectPath(0, 0, 2.5, 2.5);
  try
    const Paint = TPdfPaint.FromBitmap(Tile, TPdfMatrix.GetTranslateInstance(4, 0), TPdfTileMode.Decal, TPdfImageFilter.Nearest);
    FDevice.FillPath(Path, TPdfMatrix.GetScaleInstance(4, 4), TPdfFillRule.NonZero, Paint, NoAntiAlias);
  finally
    Path.Free;
    Tile.Free;
  end;

  AssertTransparent(3, 0);
  AssertPixel(4, 0, TPdfDeviceColor.Create(0, 0, 0));
  AssertPixel(5, 0, TPdfDeviceColor.Create(255, 255, 255));
  AssertPixel(4, 1, TPdfDeviceColor.Create(255, 255, 255));
  AssertTransparent(6, 0);
end;

procedure TPdfDeviceContractTests.TestClearIgnoresClip;
begin
  FDevice.SetClip(NewClip(nil, 2, 2, 4, 4));

  FDevice.Clear(TPdfDeviceColor.Create(0, 0, 255));

  AssertPixel(0, 0, TPdfDeviceColor.Create(0, 0, 255));
  AssertPixel(9, 9, TPdfDeviceColor.Create(0, 0, 255));

  // The clip is still in place afterwards
  FDevice.Clear(TPdfDeviceColor.Transparent);
  FillWholeDevice(Red, NoAntiAlias);
  AssertPixel(3, 3, TPdfDeviceColor.Create(255, 0, 0));
  AssertTransparent(0, 0);
end;

procedure TPdfDeviceContractTests.TestToBitmapIsPremultipliedRgba;
begin
  FillRect(2, 2, 8, 8, TPdfPaint.Solid(TPdfDeviceColor.Create(10, 20, 30)), NoAntiAlias);

  FSnapshot := FDevice.ToBitmap;
  const Row = FSnapshot.ScanLine(5);
  Assert.AreEqual(10, Integer(Row[5 * 4]));
  Assert.AreEqual(20, Integer(Row[5 * 4 + 1]));
  Assert.AreEqual(30, Integer(Row[5 * 4 + 2]));
  Assert.AreEqual(255, Integer(Row[5 * 4 + 3]));
  Assert.AreEqual(10, FSnapshot.Width);
  Assert.AreEqual(10, FSnapshot.Height);
end;

procedure TPdfDeviceContractTests.TestTryReadPixelsClipsToDevice;
begin
  FillRect(0, 0, 3, 3, Red, NoAntiAlias);

  Assert.IsTrue(FDevice.TryReadPixels(TRect.Create(-2, -2, 4, 4), FSnapshot));

  Assert.AreEqual(4, FSnapshot.Width);
  Assert.AreEqual(4, FSnapshot.Height);
  Assert.AreEqual(255, Integer(FSnapshot.GetPixel(0, 0).R));
  Assert.AreEqual(255, Integer(FSnapshot.GetPixel(2, 2).A));
  Assert.AreEqual(0, Integer(FSnapshot.GetPixel(3, 3).A));
end;

procedure TPdfDeviceContractTests.TestTryReadPixelsOutsideTheDeviceGivesNothing;
begin
  var Bitmap: TPdfBitmap;

  const HasPixels = FDevice.TryReadPixels(TRect.Create(20, 20, 30, 30), Bitmap);

  Assert.IsFalse(HasPixels);
  Assert.IsNull(Bitmap);
end;

procedure TPdfDeviceContractTests.TestTooLargeDeviceRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      FBackend.CreateRasterDevice(65536, 65536);
    end,
    EArgumentOutOfRangeException);
  Assert.WillRaise(
    procedure
    begin
      FBackend.CreateRasterDevice(0, 5);
    end,
    EArgumentOutOfRangeException);
end;

procedure TPdfDeviceContractTests.TestTransformUsesThePdfMatrixConvention;
begin
  // x' = a * x + c * y + e and y' = b * x + d * y + f: this quarter turn maps the square (0,0)-(2,2) onto x 3..5, y 0..2
  const Transform = TPdfMatrix.Create(0, 1, -1, 0, 5, 0);
  const Path = NewRectPath(0, 0, 2, 2);
  try
    FDevice.FillPath(Path, Transform, TPdfFillRule.NonZero, Red, NoAntiAlias);
  finally
    Path.Free;
  end;

  AssertPixel(3, 1, TPdfDeviceColor.Create(255, 0, 0));
  AssertPixel(4, 0, TPdfDeviceColor.Create(255, 0, 0));
  AssertTransparent(5, 1);
  AssertTransparent(4, 2);
  AssertTransparent(2, 1);
end;

procedure TPdfDeviceContractTests.TestSingularTransformDrawsNothing;
begin
  const Tile = NewTile;
  const Path = NewRectPath(0, 0, 10, 10);
  try
    const Paint = TPdfPaint.FromBitmap(Tile, TPdfMatrix.Identity, TPdfTileMode.&Repeat, TPdfImageFilter.Nearest);
    FDevice.FillPath(Path, TPdfMatrix.GetScaleInstance(0, 0), TPdfFillRule.NonZero, Paint, NoAntiAlias);
  finally
    Path.Free;
    Tile.Free;
  end;

  AssertTransparent(0, 0);
  AssertTransparent(5, 5);
end;

procedure TPdfDeviceContractTests.TestLayerIsTransparentAndSeparate;
begin
  const Layer = FDevice.CreateLayer(4, 4);
  const Fresh = Layer.ToBitmap;
  try
    Assert.AreEqual(4, Layer.Width);
    Assert.AreEqual(4, Layer.Height);
    Assert.AreEqual(0, Integer(Fresh.GetPixel(2, 2).A), 'A new layer must be transparent');
  finally
    Fresh.Free;
  end;

  const Path = NewRectPath(0, 0, 2, 2);
  try
    Layer.FillPath(Path, TPdfMatrix.Identity, TPdfFillRule.NonZero, Red, NoAntiAlias);
  finally
    Path.Free;
  end;

  const Drawn = Layer.ToBitmap;
  try
    Assert.AreEqual(255, Integer(Drawn.GetPixel(1, 1).R));
    Assert.AreEqual(255, Integer(Drawn.GetPixel(1, 1).A));
    Assert.AreEqual(0, Integer(Drawn.GetPixel(3, 3).A));
  finally
    Drawn.Free;
  end;

  AssertTransparent(1, 1);
end;

procedure TPdfDeviceContractTests.TestExceptionMaskSurvivesDrawing;
begin
  const MaskBefore = GetExceptionMask;

  FillRect(2, 2, 8, 8, Red, NoAntiAlias);
  FDevice.Clear(TPdfDeviceColor.White);
  FSnapshot := FDevice.ToBitmap;

  Assert.IsTrue(MaskBefore = GetExceptionMask, 'The device must give the floating point exception mask back as it found it');
end;

procedure TPdfDeviceContractTests.TestVeryLongClipChain;
begin
  var Clip: IPdfClipPath;
  for var Index := 1 to 100000 do
  begin
    Clip := NewClip(Clip, 2, 2, 8, 8);
  end;

  FDevice.SetClip(Clip);
  FillWholeDevice(Red, NoAntiAlias);

  AssertPixel(5, 5, TPdfDeviceColor.Create(255, 0, 0));
  AssertTransparent(1, 1);
end;

procedure TPdfDeviceContractTests.TestNearSingularBitmapPaintDrawsNothing;
begin
  const Tile = NewTile;
  const Path = NewRectPath(0, 0, 10, 10);
  try
    const BitmapToDevice = TPdfMatrix.GetScaleInstance(1E30, 1E30);
    const Paint = TPdfPaint.FromBitmap(Tile, BitmapToDevice, TPdfTileMode.&Repeat, TPdfImageFilter.Nearest);
    FDevice.FillPath(Path, TPdfMatrix.GetScaleInstance(1E-10, 1E-10), TPdfFillRule.NonZero, Paint, NoAntiAlias);
  finally
    Path.Free;
    Tile.Free;
  end;

  AssertTransparent(0, 0);
  AssertTransparent(5, 5);
end;

end.
