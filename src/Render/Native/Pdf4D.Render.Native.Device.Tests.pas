// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.Native.Device.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Common.Matrix,
  Pdf4D.Common.Path,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.ClipPath,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Render.Native.ClipMask,
  Pdf4D.Render.Native.Device,
  Pdf4D.Tests.DeviceContract;

type
  // The backend of these tests: it makes native devices of a bitmap of the size that is asked for. The backend of the renderer replaces it.
  TPdfNativeTestBackend = class(TInterfacedObject, IPdfRenderBackend)
  public
    function Name: string;
    function CreateRasterDevice(const Width, Height: Integer): IPdfRasterDevice;
  end;

  // The contract tests of the device come from the base class
  [TestFixture]
  TPdfNativeDeviceTests = class(TPdfDeviceContractTests)
  private
    function Native: TPdfNativeDevice;
    function NewDiamondClip(const Parent: IPdfClipPath): IPdfClipPath;
    function NewPathClip(const Parent: IPdfClipPath; const Path: TPdfPath; const Transform: TPdfMatrix): IPdfClipPath;
    procedure AssertNothingIsDrawn;
    procedure AssertRowIsRed(const Row, FromX, ToX: Integer);

  protected
    function CreateBackend: IPdfRenderBackend; override;

  public
    [Test]
    procedure TestBackendNameIsNative;

    [Test]
    procedure TestRectClipFastPathEqualsMaskPath;

    [Test]
    procedure TestRotatedClipUsesMask;

    [Test]
    procedure TestClipMaskIsBuiltOncePerChain;

    [Test]
    procedure TestClipOutsideDeviceDrawsNothing;

    [Test]
    procedure TestEmptyClipDrawsNothing;

    [Test]
    procedure TestClipOfTheWholeDeviceNeedsNoClip;

    [Test]
    procedure TestRectAndMaskClipsIntersectInEitherOrder;

    [Test]
    procedure TestInvalidDashDrawsNothing;

    [Test]
    procedure TestSingularStrokeTransformDrawsNothing;

    [Test]
    procedure TestPathWithNonFinitePointDrawsNothing;

    [Test]
    procedure TestWideDeviceFillsAcrossTiles;

    [Test]
    procedure TestRectClipAcrossTiles;

    [Test]
    procedure TestThinRectClipStillDrawsHairlines;

    [Test]
    procedure TestDrawBitmapRespectsRectClip;
  end;

implementation

const
  Cos45: Single = 0.70710678;

{ TPdfNativeTestBackend }

function TPdfNativeTestBackend.Name: string;
begin
  Result := 'Native';
end;

function TPdfNativeTestBackend.CreateRasterDevice(const Width, Height: Integer): IPdfRasterDevice;
begin
  Result := TPdfNativeDevice.Create(TPdfBitmap.Create(Width, Height));
end;

{ TPdfNativeDeviceTests }

function TPdfNativeDeviceTests.CreateBackend: IPdfRenderBackend;
begin
  Result := TPdfNativeTestBackend.Create;
end;

function TPdfNativeDeviceTests.Native: TPdfNativeDevice;
begin
  Result := (FDevice as TPdfNativeDevice);
end;

function TPdfNativeDeviceTests.NewPathClip(const Parent: IPdfClipPath; const Path: TPdfPath; const Transform: TPdfMatrix): IPdfClipPath;
begin
  Result := TPdfClipPath.Create(Parent, Path, Transform, TPdfFillRule.NonZero);
end;

// The diamond with the corners (1,5), (5,1), (9,5) and (5,9)
function TPdfNativeDeviceTests.NewDiamondClip(const Parent: IPdfClipPath): IPdfClipPath;
begin
  const Path = TPdfPath.Create;
  Path.MoveTo(5, 1);
  Path.LineTo(9, 5);
  Path.LineTo(5, 9);
  Path.LineTo(1, 5);
  Path.ClosePath;

  Result := NewPathClip(Parent, Path, TPdfMatrix.Identity);
end;

procedure TPdfNativeDeviceTests.AssertNothingIsDrawn;
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

procedure TPdfNativeDeviceTests.AssertRowIsRed(const Row, FromX, ToX: Integer);
begin
  for var X := FromX to ToX do
  begin
    AssertPixel(X, Row, TPdfDeviceColor.Create(255, 0, 0));
  end;
end;

procedure TPdfNativeDeviceTests.TestBackendNameIsNative;
begin
  Assert.AreEqual('Native', FBackend.Name);
  Assert.AreEqual(10, FDevice.Width);
  Assert.AreEqual(10, FDevice.Height);
end;

procedure TPdfNativeDeviceTests.TestRectClipFastPathEqualsMaskPath;
begin
  // The clip (2.3, 2.7)-(7.6, 7.2) acts as the pixels 2 to 6; the edges of the shape that is filled are anti-aliased
  const Clip = NewClip(nil, 2.3, 2.7, 7.6, 7.2);
  FDevice.SetClip(Clip);

  Native.ForceMaskClip := False;
  FillRect(0.5, 0.5, 9.5, 9.5, Red, TPdfComposite.Default);
  Assert.AreEqual(Ord(TTsClipKind.Rect), Ord(Native.ClipKind), 'the fast path clips with a rectangle');
  const FastPath = FDevice.ToBitmap;
  try
    FDevice.Clear(TPdfDeviceColor.Transparent);

    Native.ForceMaskClip := True;
    FillRect(0.5, 0.5, 9.5, 9.5, Red, TPdfComposite.Default);
    Assert.AreEqual(Ord(TTsClipKind.Mask), Ord(Native.ClipKind), 'the forced path clips with a mask');
    const MaskPath = FDevice.ToBitmap;
    try
      Assert.AreEqual(Length(FastPath.Pixels), Length(MaskPath.Pixels));
      Assert.IsTrue(CompareMem(Pointer(FastPath.Pixels), Pointer(MaskPath.Pixels), Length(FastPath.Pixels)), 'the two ways to clip give the same bytes');
      Assert.AreEqual(255, Integer(FastPath.GetPixel(4, 4).A), 'the clipped shape is drawn');
      Assert.AreEqual(0, Integer(FastPath.GetPixel(1, 4).A), 'left of the clip is empty');
      Assert.AreEqual(0, Integer(FastPath.GetPixel(7, 4).A), 'right of the clip is empty');
    finally
      MaskPath.Free;
    end;
  finally
    FastPath.Free;
  end;
end;

procedure TPdfNativeDeviceTests.TestRotatedClipUsesMask;
begin
  // The square (3,3)-(7,7) turned over 45 degrees around (5,5): a diamond with a half diagonal of 2.83
  const Path = NewRectPath(3, 3, 7, 7);
  const Turn = TPdfMatrix.Create(Cos45, Cos45, -Cos45, Cos45, 5, 5 - 10 * Cos45);
  FDevice.SetClip(NewPathClip(nil, Path, Turn));

  FillWholeDevice(Red, TPdfComposite.Default);

  Assert.AreEqual(Ord(TTsClipKind.Mask), Ord(Native.ClipKind));
  AssertPixel(5, 5, TPdfDeviceColor.Create(255, 0, 0));
  AssertPixel(5, 3, TPdfDeviceColor.Create(255, 0, 0));
  AssertTransparent(0, 0);
  AssertTransparent(9, 9);
  AssertTransparent(5, 1);
  AssertTransparent(2, 2);

  FSnapshot.Free;
  FSnapshot := FDevice.ToBitmap;
  for var Y := 0 to 9 do
  begin
    for var X := 0 to 9 do
    begin
      const Alpha = FSnapshot.GetPixel(X, Y).A;
      Assert.IsTrue((Alpha = 0) or (Alpha = 255), Format('Pixel (%d, %d) has the partial alpha %d', [X, Y, Alpha]));
    end;
  end;
end;

procedure TPdfNativeDeviceTests.TestClipMaskIsBuiltOncePerChain;
begin
  const Clip = NewClip(nil, 2, 2, 8, 8);
  FDevice.SetClip(Clip);
  for var Count := 1 to 10 do
  begin
    FillRect(0, 0, 10, 10, Red, NoAntiAlias);
  end;
  Assert.AreEqual(1, Native.ClipBuildCount);

  // The same geometry in a new chain is another chain
  FDevice.SetClip(NewClip(nil, 2, 2, 8, 8));
  FillRect(0, 0, 10, 10, Red, NoAntiAlias);
  Assert.AreEqual(2, Native.ClipBuildCount);

  // Going back to a chain that was applied before builds it again, a chain that is set again does not
  FDevice.SetClip(Clip);
  FDevice.SetClip(Clip);
  FillRect(0, 0, 10, 10, Red, NoAntiAlias);
  Assert.AreEqual(3, Native.ClipBuildCount);
end;

procedure TPdfNativeDeviceTests.TestClipOutsideDeviceDrawsNothing;
begin
  FDevice.SetClip(NewClip(nil, 20, 20, 30, 30));

  FillWholeDevice(Red, NoAntiAlias);
  AssertNothingIsDrawn;

  FillWholeDevice(Red, TPdfComposite.Default);
  AssertNothingIsDrawn;
  Assert.AreEqual(Ord(TTsClipKind.Empty), Ord(Native.ClipKind));
end;

procedure TPdfNativeDeviceTests.TestEmptyClipDrawsNothing;
begin
  // A clip of no area
  FDevice.SetClip(NewClip(nil, 3, 3, 3, 3));
  FillWholeDevice(Red, NoAntiAlias);
  AssertNothingIsDrawn;

  // A clip of a path without a segment
  FDevice.SetClip(NewPathClip(nil, TPdfPath.Create, TPdfMatrix.Identity));
  FillWholeDevice(Red, NoAntiAlias);
  AssertNothingIsDrawn;

  // A clip that leaves nothing of the clip before it
  FDevice.SetClip(NewClip(NewClip(nil, 0, 0, 4, 4), 6, 6, 9, 9));
  FillWholeDevice(Red, NoAntiAlias);
  AssertNothingIsDrawn;
end;

procedure TPdfNativeDeviceTests.TestClipOfTheWholeDeviceNeedsNoClip;
begin
  FDevice.SetClip(NewClip(nil, -5, -5, 20, 20));

  FillWholeDevice(Red, NoAntiAlias);

  Assert.AreEqual(Ord(TTsClipKind.None), Ord(Native.ClipKind));
  AssertPixel(0, 0, TPdfDeviceColor.Create(255, 0, 0));
  AssertPixel(9, 9, TPdfDeviceColor.Create(255, 0, 0));
end;

procedure TPdfNativeDeviceTests.TestRectAndMaskClipsIntersectInEitherOrder;
begin
  // The diamond has the pixels (3,5) and (7,5) inside; the rectangle keeps the left half of the device
  const Diamond = NewDiamondClip(nil);
  FDevice.SetClip(NewClip(Diamond, 0, 0, 5, 10));
  FillWholeDevice(Red, NoAntiAlias);
  AssertPixel(3, 5, TPdfDeviceColor.Create(255, 0, 0));
  AssertTransparent(7, 5);
  AssertTransparent(2, 0);
  Assert.AreEqual(Ord(TTsClipKind.Mask), Ord(Native.ClipKind));

  FDevice.Clear(TPdfDeviceColor.Transparent);
  FDevice.SetClip(NewDiamondClip(NewClip(nil, 0, 0, 5, 10)));
  FillWholeDevice(Red, NoAntiAlias);
  AssertPixel(3, 5, TPdfDeviceColor.Create(255, 0, 0));
  AssertTransparent(7, 5);
  AssertTransparent(2, 0);
  Assert.AreEqual(Ord(TTsClipKind.Mask), Ord(Native.ClipKind));
end;

procedure TPdfNativeDeviceTests.TestInvalidDashDrawsNothing;
begin
  var Stroke := NewStroke(2, TPdfLineCap.Butt);
  Stroke.Dashes := [Single.NaN, 1];
  StrokeLine(0, 5, 10, 5, TPdfMatrix.Identity, Stroke);
  AssertNothingIsDrawn;

  Stroke.Dashes := [0, 0];
  StrokeLine(0, 5, 10, 5, TPdfMatrix.Identity, Stroke);
  AssertNothingIsDrawn;

  Stroke.Dashes := [-1, 2];
  StrokeLine(0, 5, 10, 5, TPdfMatrix.Identity, Stroke);
  AssertNothingIsDrawn;
end;

procedure TPdfNativeDeviceTests.TestSingularStrokeTransformDrawsNothing;
begin
  StrokeLine(0, 5, 10, 5, TPdfMatrix.GetScaleInstance(0, 0), NewStroke(2, TPdfLineCap.Butt));
  AssertNothingIsDrawn;

  StrokeLine(0, 5, 10, 5, TPdfMatrix.Create(1, 2, 2, 4, 0, 0), NewStroke(2, TPdfLineCap.Butt));
  AssertNothingIsDrawn;
end;

procedure TPdfNativeDeviceTests.TestPathWithNonFinitePointDrawsNothing;
begin
  const Path = TPdfPath.Create;
  try
    Path.MoveTo(0, 0);
    Path.LineTo(Single.NaN, 5);
    Path.LineTo(10, Single.PositiveInfinity);
    Path.ClosePath;

    FDevice.FillPath(Path, TPdfMatrix.Identity, TPdfFillRule.NonZero, Red, NoAntiAlias);
    FDevice.FillPath(Path, TPdfMatrix.Identity, TPdfFillRule.NonZero, Red, TPdfComposite.Default);
    FDevice.StrokePath(Path, TPdfMatrix.Identity, NewStroke(2, TPdfLineCap.Butt), Red, TPdfComposite.Default);
  finally
    Path.Free;
  end;

  AssertNothingIsDrawn;
end;

procedure TPdfNativeDeviceTests.TestWideDeviceFillsAcrossTiles;
begin
  // The fixed point of the scan converters holds 8191 pixels: a wider device is drawn in tiles
  CreateDevice(9000, 4);

  FillRect(8000, 0, 8400, 4, Red, TPdfComposite.Default);

  AssertPixel(8190, 1, TPdfDeviceColor.Create(255, 0, 0));
  AssertPixel(8195, 1, TPdfDeviceColor.Create(255, 0, 0));
  AssertTransparent(7999, 1);
  AssertTransparent(8400, 1);

  FDevice.Clear(TPdfDeviceColor.Transparent);
  FillRect(8000, 0, 8400, 4, Red, NoAntiAlias);

  AssertPixel(8190, 1, TPdfDeviceColor.Create(255, 0, 0));
  AssertPixel(8195, 1, TPdfDeviceColor.Create(255, 0, 0));
  AssertTransparent(7999, 1);
  AssertTransparent(8400, 1);
end;

procedure TPdfNativeDeviceTests.TestRectClipAcrossTiles;
begin
  CreateDevice(9000, 4);
  FDevice.SetClip(NewClip(nil, 8100, 0, 8300, 3));

  FillWholeDevice(Red, NoAntiAlias);

  Assert.AreEqual(Ord(TTsClipKind.Rect), Ord(Native.ClipKind));
  AssertRowIsRed(1, 8100, 8299);
  AssertRowIsRed(2, 8190, 8192);
  AssertTransparent(8099, 1);
  AssertTransparent(8300, 1);
  AssertTransparent(8150, 3);
end;

procedure TPdfNativeDeviceTests.TestThinRectClipStillDrawsHairlines;
begin
  // tiny-skia draws no hairline in a clip of less than 3 pixels in one direction, so such a clip is applied as a mask
  FDevice.SetClip(NewClip(nil, 0, 4, 10, 5));

  StrokeLine(0, 4.5, 10, 4.5, TPdfMatrix.Identity, NewStroke(0, TPdfLineCap.Butt));

  Assert.AreEqual(Ord(TTsClipKind.Mask), Ord(Native.ClipKind));
  AssertRowIsRed(4, 1, 8);
  AssertTransparent(3, 3);
  AssertTransparent(3, 5);
end;

procedure TPdfNativeDeviceTests.TestDrawBitmapRespectsRectClip;
begin
  FDevice.SetClip(NewClip(nil, 3, 3, 6, 6));
  const Bitmap = TPdfBitmap.Create(2, 2);
  try
    for var Y := 0 to 1 do
    begin
      for var X := 0 to 1 do
      begin
        Bitmap.SetPixel(X, Y, TPdfDeviceColor.Create(255, 0, 0));
      end;
    end;

    FDevice.DrawBitmap(Bitmap, TPdfMatrix.GetScaleInstance(5, 5), TPdfImageFilter.Nearest, NoAntiAlias);
  finally
    Bitmap.Free;
  end;

  AssertPixel(3, 3, TPdfDeviceColor.Create(255, 0, 0));
  AssertPixel(5, 5, TPdfDeviceColor.Create(255, 0, 0));
  AssertTransparent(2, 3);
  AssertTransparent(6, 5);
  AssertTransparent(4, 2);
  AssertTransparent(4, 6);
end;

end.
