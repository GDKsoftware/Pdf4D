// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.Native.Device.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Common.Defines,
  Pdf4D.Common.Matrix,
  Pdf4D.Common.Path,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.ClipPath,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Render.Native.ClipMask,
  Pdf4D.Render.Native.Backend,
  Pdf4D.Render.Native.Device,
  Pdf4D.Tests.DeviceContract;

type
  // The contract tests of the device come from the base class
  [TestFixture]
  TPdfNativeDeviceTests = class(TPdfDeviceContractTests)
  private
    function Native: TPdfNativeDevice;
    function NewDiamondClip(const Parent: IPdfClipPath): IPdfClipPath;
    function NewPathClip(const Parent: IPdfClipPath; const Path: TPdfPath; const Transform: TPdfMatrix): IPdfClipPath;
    // A rectangle that is a path of five points (a vertex in the middle of the top edge), which is not taken for a rectangle
    function NewSplitRectClip(const Left, Top, Right, Bottom: Single; const Transform: TPdfMatrix): IPdfClipPath;
    function BytesFilledWithClip(const Clip: IPdfClipPath): TBytes;
    function FillRaisesTheLimit(const Device: IPdfRasterDevice; const Path: TPdfPath): Boolean;
    procedure AssertRowIsRed(const Row, FromX, ToX: Integer);
    function FreshBytesFilledWithClip(const Clip: IPdfClipPath): TBytes;
    procedure AssertSameBytes(const Expected, Actual: TBytes; const Message: string);
    procedure FillWholeDeviceOf(const Device: IPdfRasterDevice);
    procedure FillTheDeviceUnderTest;

  protected
    function CreateBackend: IPdfRenderBackend; override;
    function AppliedClipWork: Integer; override;

  private
    FDeviceUnderTest: IPdfRasterDevice;

  public
    [Test]
    procedure TestBackendNameIsNative;

    [Test]
    procedure TestRectClipFastPathEqualsMaskPath;

    // The edges 2.5, 2.49, 7.5, -0.6 and 9.999 at another scale, as a rectangle and as a path of five points that goes through the scan converter
    [Test]
    procedure TestRectClipEqualsTheSamePathThatIsNotARectangle;

    [Test]
    procedure TestRotatedClipUsesMask;

    [Test]
    procedure TestClipMaskIsBuiltOncePerChain;

    // Work in proportion to the length of a chain, counted in applied paths and not in time
    [Test]
    procedure TestLongClipChainAppliesEveryPathOnce;

    [Test]
    procedure TestSwitchingBetweenBranchesAppliesOnlyTheNewPaths;

    // Only the masks of the last 8 levels are kept: a chain that goes back below them is applied again and still right
    [Test]
    procedure TestGoingBackBelowTheKeptMasksGivesTheSameClip;

    // 200 diamonds on a device of a million pixels: every path is applied once, whatever the clock says
    [Test]
    procedure TestLongChainOfDiamondClipsAppliesEveryPathOnce;

    // A non-rectangular level is popped (the chain returns to its parent) and the parent is extended by another path
    [Test]
    procedure TestNonRectLevelPoppedThenExtended;

    // SetClip(nil) drops the applied levels: the same chain afterwards is applied again, with the same result
    [Test]
    procedure TestSameChainAfterSetClipNilIsAppliedAgain;

    // A path over the verb limit in the middle of a chain: the draw raises, the levels before it stay, and a chain with the same prefix
    // and another path goes on from there
    [Test]
    procedure TestVerbLimitFailureInTheMiddleOfAChain;

    // The levels hold masks of one size; Update with another size applies the chain again on the new size
    [Test]
    procedure TestClipMaskDropsItsLevelsWhenTheSizeChanges;

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

    // tiny-skia draws no hairline on an area of less than 3 pixels in one direction; Pdf4D does
    [Test]
    procedure TestHairlineOnADeviceTwoPixelsWideIsDrawn;

    [Test]
    procedure TestHairlineOnADeviceOnePixelHighIsDrawn;

    [Test]
    procedure TestHairlineInASmallLayerIsDrawn;

    [Test]
    procedure TestHairlineInATileSliceOfTwoPixelsIsDrawn;

    [Test]
    procedure TestDrawBitmapRespectsRectClip;

    [Test]
    procedure TestSoftMaskPartlyOutsideDevice;

    [Test]
    procedure TestSoftMaskAndClipMultiply;

    [Test]
    procedure TestCoverageMaskEqualsAlphaForMultiply;

    [Test]
    procedure TestAlphaOnBitmapPaint;

    [Test]
    procedure TestSoftMaskOnBitmapPaint;

    [Test]
    procedure TestSoftMaskIsRebuiltWhenItsValuesChange;

    [Test]
    procedure TestSoftMaskOutsideTheClipDrawsNothing;

    [Test]
    procedure TestLayerHasSameLimits;
  end;

implementation

uses
  Pdf4D.Render.Native.Scalar;

const
  Cos45: Single = 0.70710678;

{ TPdfNativeDeviceTests }

function TPdfNativeDeviceTests.CreateBackend: IPdfRenderBackend;
begin
  Result := TPdfNativeBackend.Create;
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
function TPdfNativeDeviceTests.NewSplitRectClip(const Left, Top, Right, Bottom: Single; const Transform: TPdfMatrix): IPdfClipPath;
begin
  const Path = TPdfPath.Create;
  Path.MoveTo(Left, Top);
  Path.LineTo((Left + Right) / 2, Top);
  Path.LineTo(Right, Top);
  Path.LineTo(Right, Bottom);
  Path.LineTo(Left, Bottom);
  Path.ClosePath;

  Result := NewPathClip(nil, Path, Transform);
end;

function TPdfNativeDeviceTests.BytesFilledWithClip(const Clip: IPdfClipPath): TBytes;
begin
  FDevice.Clear(TPdfDeviceColor.Transparent);
  FDevice.SetClip(Clip);
  FillWholeDevice(Red, NoAntiAlias);

  const Bitmap = FDevice.ToBitmap;
  try
    Result := Copy(Bitmap.Pixels);
  finally
    Bitmap.Free;
  end;
end;

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

procedure TPdfNativeDeviceTests.TestRectClipEqualsTheSamePathThatIsNotARectangle;
begin
  // The path is in half pixels and the clip scales it by 2; the fast path rounds an edge of the rectangle as the scan converter does
  var Edges: TArray<Single> := [2.5, 2.49, 7.5, -0.6, 9.999];
  const Scale = TPdfMatrix.GetScaleInstance(2, 2);

  for var LeftIndex := 0 to High(Edges) do
  begin
    for var RightIndex := 0 to High(Edges) do
    begin
      // A rectangle of less than a pixel can come to nothing
      if Edges[RightIndex] - Edges[LeftIndex] < 1 then
      begin
        Continue;
      end;

      const Message = Format('edges %g and %g', [Edges[LeftIndex], Edges[RightIndex]]);
      const Left = Edges[LeftIndex] / 2;
      const Right = Edges[RightIndex] / 2;
      const AsRect = BytesFilledWithClip(TPdfClipPath.Create(nil, NewRectPath(Left, Left, Right, Right), Scale, TPdfFillRule.NonZero));
      // A rectangle that holds the whole device needs no clip at all
      Assert.IsTrue(Native.ClipKind in [TTsClipKind.Rect, TTsClipKind.None], 'a rectangle clips with a rectangle: ' + Message);

      const AsPath = BytesFilledWithClip(NewSplitRectClip(Left, Left, Right, Right, Scale));
      Assert.AreEqual(Ord(TTsClipKind.Mask), Ord(Native.ClipKind), 'a path of five points clips with a mask: ' + Message);

      Assert.AreEqual(Length(AsRect), Length(AsPath));
      Assert.IsTrue(CompareMem(Pointer(AsRect), Pointer(AsPath), Length(AsRect)), 'the same pixels: ' + Message);
    end;
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

procedure TPdfNativeDeviceTests.TestLongClipChainAppliesEveryPathOnce;
begin
  const PathCount = 3000;
  var Clip: IPdfClipPath := nil;
  for var Index := 1 to PathCount do
  begin
    Clip := NewClip(Clip, Index * 0.001, 0, 10, 10);
    FDevice.SetClip(Clip);
    FillRect(8, 5, 9, 6, Red, NoAntiAlias);
  end;

  Assert.AreEqual(PathCount, Native.ClipBuildCount, 'a chain is built for every change');
  Assert.AreEqual(PathCount, Native.ClipLinkCount, 'and every path is applied once');
  AssertPixel(8, 5, TPdfDeviceColor.Create(255, 0, 0));
end;

procedure TPdfNativeDeviceTests.TestSwitchingBetweenBranchesAppliesOnlyTheNewPaths;
begin
  const Root = NewClip(nil, 0, 0, 10, 10);
  const Left = NewClip(Root, 0, 0, 5, 10);
  const Right = NewClip(Root, 5, 0, 10, 10);
  const UpperLeft = NewClip(Left, 0, 0, 5, 5);

  FDevice.SetClip(UpperLeft);
  FillWholeDevice(Red, NoAntiAlias);
  Assert.AreEqual(3, Native.ClipLinkCount, 'root, left and upper left');

  // Right has the root in common
  FDevice.SetClip(Right);
  FillWholeDevice(Red, NoAntiAlias);
  Assert.AreEqual(4, Native.ClipLinkCount, 'right only');

  // Back to the left: the stack holds root and right, so left is applied on the root
  FDevice.SetClip(Left);
  FillWholeDevice(Red, NoAntiAlias);
  Assert.AreEqual(5, Native.ClipLinkCount, 'left only');

  // The parent of what is applied adds nothing
  FDevice.SetClip(Root);
  FillWholeDevice(Red, NoAntiAlias);
  Assert.AreEqual(5, Native.ClipLinkCount, 'a parent of the applied chain');
  Assert.AreEqual(Ord(TTsClipKind.None), Ord(Native.ClipKind), 'the root covers the whole device');
end;

procedure TPdfNativeDeviceTests.TestGoingBackBelowTheKeptMasksGivesTheSameClip;
begin
  CreateDevice(100, 100);

  // 20 nested diamonds on the middle row, the half diagonal of the nth is 48 - 2n
  var Links: TArray<IPdfClipPath>;
  SetLength(Links, 21);
  for var Index := 1 to 20 do
  begin
    Links[Index] := NewDiamondClipAround(Links[Index - 1], 50, 50, 48 - 2 * Index);
    FDevice.SetClip(Links[Index]);
    FillRect(50, 50, 51, 51, Red, NoAntiAlias);
  end;
  Assert.AreEqual(20, Native.ClipLinkCount);

  // The mask of the 18th diamond (half diagonal 12) is kept: nothing is applied again
  FDevice.Clear(TPdfDeviceColor.Transparent);
  FDevice.SetClip(Links[18]);
  FillRect(0, 50, 100, 51, Red, NoAntiAlias);
  Assert.AreEqual(20, Native.ClipLinkCount, 'a level whose mask is kept');
  AssertPixel(60, 50, TPdfDeviceColor.Create(255, 0, 0));
  AssertTransparent(64, 50);

  // The mask of the second diamond (half diagonal 44) is gone by now: the first two paths are applied again. Pixel 94 lies in the first
  // diamond (half diagonal 46) but not in the second.
  FDevice.Clear(TPdfDeviceColor.Transparent);
  FDevice.SetClip(Links[2]);
  FillRect(0, 50, 100, 51, Red, NoAntiAlias);
  Assert.AreEqual(22, Native.ClipLinkCount, 'the first two paths again');
  AssertPixel(90, 50, TPdfDeviceColor.Create(255, 0, 0));
  AssertTransparent(94, 50);
  AssertTransparent(5, 50);
end;

procedure TPdfNativeDeviceTests.FillWholeDeviceOf(const Device: IPdfRasterDevice);
begin
  const Path = NewRectPath(0, 0, Device.Width, Device.Height);
  try
    Device.FillPath(Path, TPdfMatrix.Identity, TPdfFillRule.NonZero, Red, NoAntiAlias);
  finally
    Path.Free;
  end;
end;

procedure TPdfNativeDeviceTests.FillTheDeviceUnderTest;
begin
  FillWholeDeviceOf(FDeviceUnderTest);
end;

function TPdfNativeDeviceTests.AppliedClipWork: Integer;
begin
  Result := Native.ClipLinkCount;
end;

procedure TPdfNativeDeviceTests.TestLongChainOfDiamondClipsAppliesEveryPathOnce;
begin
  CreateDevice(1000, 1000);
  const LinkCount = 200;
  var Clip: IPdfClipPath := nil;
  for var Index := 1 to LinkCount do
  begin
    Clip := NewDiamondClipAround(Clip, 500, 500, 490 - Index);
    FDevice.SetClip(Clip);
    FillRect(500, 500, 501, 501, Red, NoAntiAlias);
  end;

  Assert.AreEqual(LinkCount, Native.ClipBuildCount, 'a chain is built for every change');
  Assert.AreEqual(LinkCount, Native.ClipLinkCount, 'and every path is applied once');
  AssertPixel(500, 500, TPdfDeviceColor.Create(255, 0, 0));
  AssertTransparent(5, 5);
end;

// What a fresh device draws when the whole device is filled under Clip
function TPdfNativeDeviceTests.FreshBytesFilledWithClip(const Clip: IPdfClipPath): TBytes;
begin
  const Device = FBackend.CreateRasterDevice(FDevice.Width, FDevice.Height);
  Device.SetClip(Clip);
  FillWholeDeviceOf(Device);

  const Bitmap = Device.ToBitmap;
  try
    Result := Copy(Bitmap.Pixels);
  finally
    Bitmap.Free;
  end;
end;

procedure TPdfNativeDeviceTests.AssertSameBytes(const Expected, Actual: TBytes; const Message: string);
begin
  Assert.AreEqual(Length(Expected), Length(Actual), Message);
  Assert.IsTrue(CompareMem(Pointer(Expected), Pointer(Actual), Length(Expected)), Message);
end;

procedure TPdfNativeDeviceTests.TestNonRectLevelPoppedThenExtended;
begin
  const Root = NewClip(nil, 0, 0, 10, 8);
  const First = NewDiamondClipAround(Root, 5, 5, 4.5);
  const Second = NewDiamondClipAround(First, 5, 5, 3.5);
  const Sibling = NewDiamondClipAround(First, 5, 4, 2.5);

  FDevice.SetClip(Second);
  FillWholeDevice(Red, NoAntiAlias);
  Assert.AreEqual(3, Native.ClipLinkCount, 'root, first and second');

  // The parent: nothing is applied, and the second level is discarded
  FDevice.Clear(TPdfDeviceColor.Transparent);
  FDevice.SetClip(First);
  FillWholeDevice(Red, NoAntiAlias);
  Assert.AreEqual(3, Native.ClipLinkCount, 'a parent of the applied chain');

  // Another child of the parent: only that path is applied, on the mask of the parent
  FDevice.Clear(TPdfDeviceColor.Transparent);
  FDevice.SetClip(Sibling);
  FillWholeDevice(Red, NoAntiAlias);
  Assert.AreEqual(4, Native.ClipLinkCount, 'the sibling only');
  Assert.AreEqual(Ord(TTsClipKind.Mask), Ord(Native.ClipKind));

  const Actual = FDevice.ToBitmap;
  try
    AssertSameBytes(FreshBytesFilledWithClip(Sibling), Actual.Pixels, 'the same pixels as on a fresh device');
  finally
    Actual.Free;
  end;
end;

procedure TPdfNativeDeviceTests.TestSameChainAfterSetClipNilIsAppliedAgain;
begin
  const Root = NewClip(nil, 0, 0, 10, 8);
  const Chain = NewDiamondClipAround(NewDiamondClipAround(Root, 5, 5, 4.5), 5, 5, 3.5);
  const Expected = FreshBytesFilledWithClip(Chain);

  FDevice.SetClip(Chain);
  FillWholeDevice(Red, NoAntiAlias);
  Assert.AreEqual(3, Native.ClipLinkCount);

  FDevice.Clear(TPdfDeviceColor.Transparent);
  FDevice.SetClip(nil);
  FillWholeDevice(Red, NoAntiAlias);
  AssertPixel(0, 9, TPdfDeviceColor.Create(255, 0, 0));
  Assert.AreEqual(3, Native.ClipLinkCount, 'no clip applies nothing');

  FDevice.Clear(TPdfDeviceColor.Transparent);
  FDevice.SetClip(Chain);
  FillWholeDevice(Red, NoAntiAlias);
  Assert.AreEqual(6, Native.ClipLinkCount, 'all three paths again');

  const Actual = FDevice.ToBitmap;
  try
    AssertSameBytes(Expected, Actual.Pixels, 'the same pixels as the first time');
  finally
    Actual.Free;
  end;
end;

procedure TPdfNativeDeviceTests.TestVerbLimitFailureInTheMiddleOfAChain;
begin
  var Limits := TPdfNativeLimits.Default;
  Limits.MaxPathVerbs := 6;
  const Backend: IPdfRenderBackend = TPdfNativeBackend.Create(Limits);
  const Device = Backend.CreateRasterDevice(10, 10);

  // A path of 8 verbs, over the limit of 6; a rectangle has 5
  const BigPath = TPdfPath.Create;
  BigPath.MoveTo(0, 0);
  for var Index := 1 to 7 do
  begin
    BigPath.LineTo(Index, 10 - Index);
  end;

  const First = NewClip(nil, 0, 0, 10, 8);
  const Second = NewClip(First, 0, 0, 8, 10);
  const Bad = TPdfClipPath.Create(Second, BigPath, TPdfMatrix.Identity, TPdfFillRule.NonZero) as IPdfClipPath;
  const Good = NewClip(Second, 0, 0, 6, 10);

  FDeviceUnderTest := Device;
  Device.SetClip(Bad);
  Assert.WillRaise(FillTheDeviceUnderTest, EPdfLimitExceededException);
  const FailedLinkCount = (Device as TPdfNativeDevice).ClipLinkCount;
  Assert.AreEqual(3, FailedLinkCount, 'the two paths before the bad one and the attempt at it');

  // The same chain raises again, at the same path
  Assert.WillRaise(FillTheDeviceUnderTest, EPdfLimitExceededException);
  const RetriedLinkCount = (Device as TPdfNativeDevice).ClipLinkCount;

  Device.SetClip(Good);
  FillWholeDeviceOf(Device);
  Assert.AreEqual(RetriedLinkCount + 1, (Device as TPdfNativeDevice).ClipLinkCount, 'the good path goes on from the applied prefix: one path only');

  const Actual = Device.ToBitmap;
  try
    AssertSameBytes(FreshBytesFilledWithClip(Good), Actual.Pixels, 'the same pixels as on a fresh device');
  finally
    Actual.Free;
  end;
  FDeviceUnderTest := nil;
end;

procedure TPdfNativeDeviceTests.TestClipMaskDropsItsLevelsWhenTheSizeChanges;
begin
  const FloatState = TTsFloatMode.Enter;
  try
    const ClipMask = TTsClipMask.Create;
    try
      const Chain = NewDiamondClipAround(nil, 50, 50, 40);
      ClipMask.Update(Chain, 100, 100);
      Assert.AreEqual(Ord(TTsClipKind.Mask), Ord(ClipMask.Kind));
      Assert.AreEqual(100, Integer(ClipMask.Mask.Width));
      Assert.AreEqual(1, ClipMask.AppliedLinkCount);

      ClipMask.Update(Chain, 60, 60);
      Assert.AreEqual(Ord(TTsClipKind.Mask), Ord(ClipMask.Kind));
      Assert.AreEqual(60, Integer(ClipMask.Mask.Width), 'the mask has the new size');
      Assert.AreEqual(60, Integer(ClipMask.Mask.Height));
      Assert.AreEqual(2, ClipMask.AppliedLinkCount, 'the chain is applied again on the new size');
    finally
      ClipMask.Free;
    end;
  finally
    TTsFloatMode.Leave(FloatState);
  end;
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
  // The painter draws a hairline in a clip of less than 3 pixels in one direction, so such a clip needs no mask
  FDevice.SetClip(NewClip(nil, 0, 4, 10, 5));

  StrokeLine(0, 4.5, 10, 4.5, TPdfMatrix.Identity, NewStroke(0, TPdfLineCap.Butt));

  Assert.AreEqual(Ord(TTsClipKind.Rect), Ord(Native.ClipKind));
  AssertRowIsRed(4, 1, 8);
  AssertTransparent(3, 3);
  AssertTransparent(3, 5);
end;

procedure TPdfNativeDeviceTests.TestHairlineOnADeviceTwoPixelsWideIsDrawn;
begin
  CreateDevice(2, 10);

  StrokeLine(1.5, 0, 1.5, 10, TPdfMatrix.Identity, NewStroke(0, TPdfLineCap.Butt));

  AssertPixel(1, 4, TPdfDeviceColor.Create(255, 0, 0));
  AssertTransparent(0, 4);
end;

procedure TPdfNativeDeviceTests.TestHairlineOnADeviceOnePixelHighIsDrawn;
begin
  CreateDevice(10, 1);

  StrokeLine(0, 0.5, 10, 0.5, TPdfMatrix.Identity, NewStroke(0, TPdfLineCap.Butt));

  AssertRowIsRed(0, 1, 8);
end;

procedure TPdfNativeDeviceTests.TestHairlineInASmallLayerIsDrawn;
begin
  // A group of a thin rule gets a layer of the size of the group
  const Layer = FDevice.CreateLayer(10, 2);
  const Path = NewLinePath(0, 1.5, 10, 1.5);
  try
    Layer.StrokePath(Path, TPdfMatrix.Identity, NewStroke(0, TPdfLineCap.Butt), Red, NoAntiAlias);
  finally
    Path.Free;
  end;

  const Bitmap = Layer.ToBitmap;
  try
    Assert.AreEqual(255, Integer(Bitmap.GetPixel(5, 1).R));
    Assert.AreEqual(255, Integer(Bitmap.GetPixel(5, 1).A));
    Assert.AreEqual(0, Integer(Bitmap.GetPixel(5, 0).A));
  finally
    Bitmap.Free;
  end;
end;

procedure TPdfNativeDeviceTests.TestHairlineInATileSliceOfTwoPixelsIsDrawn;
begin
  // The last tile of a device that is 8193 pixels wide is 2 pixels wide (8191 and 8192)
  CreateDevice(8193, 4);

  StrokeLine(0, 1.5, 8193, 1.5, TPdfMatrix.Identity, NewStroke(0, TPdfLineCap.Butt));

  AssertPixel(8189, 1, TPdfDeviceColor.Create(255, 0, 0));
  AssertPixel(8191, 1, TPdfDeviceColor.Create(255, 0, 0));
  AssertPixel(8192, 1, TPdfDeviceColor.Create(255, 0, 0));
  AssertTransparent(8192, 0);
  AssertTransparent(8192, 2);
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

procedure TPdfNativeDeviceTests.TestSoftMaskPartlyOutsideDevice;
begin
  const Mask = NewMask(-2, -2, 4, 4, 255, 0);
  try
    var Composite := NoAntiAlias;
    Composite.SoftMask := Mask;
    FillWholeDevice(Red, Composite);
  finally
    Mask.Free;
  end;

  AssertPixel(1, 1, TPdfDeviceColor.Create(255, 0, 0));
  AssertTransparent(2, 2);
  AssertTransparent(5, 5);
end;

procedure TPdfNativeDeviceTests.TestSoftMaskAndClipMultiply;
begin
  FDevice.SetClip(NewClip(nil, 0, 0, 5, 10));
  const Mask = NewMask(0, 0, 10, 10, 128, 0);
  try
    var Composite := NoAntiAlias;
    Composite.SoftMask := Mask;
    FillWholeDevice(Red, Composite);
  finally
    Mask.Free;
  end;

  AssertPixel(2, 5, TPdfDeviceColor.Create(128, 0, 0, 128), 1);
  AssertTransparent(7, 5);
end;

// The mask is the coverage of the draw, which tiny-skia mixes in with the destination; for an opaque destination that is the same as the
// alpha of the paint
procedure TPdfNativeDeviceTests.TestCoverageMaskEqualsAlphaForMultiply;
begin
  const Backdrop = TPdfDeviceColor.Create(50, 100, 200);
  const Source = TPdfDeviceColor.Create(200, 100, 50);

  FillOpaqueBackground(Backdrop);
  var WithAlpha := NoAntiAlias;
  WithAlpha.BlendMode := TPdfBlendMode.Multiply;
  WithAlpha.Alpha := 128 / 255;
  FillWholeDevice(TPdfPaint.Solid(Source), WithAlpha);
  const Expected = Pixel(5, 5);

  FillOpaqueBackground(Backdrop);
  const Mask = NewMask(0, 0, 10, 10, 128, 128);
  try
    var WithMask := NoAntiAlias;
    WithMask.BlendMode := TPdfBlendMode.Multiply;
    WithMask.SoftMask := Mask;
    FillWholeDevice(TPdfPaint.Solid(Source), WithMask);
  finally
    Mask.Free;
  end;

  AssertPixel(5, 5, Expected, 1);
end;

procedure TPdfNativeDeviceTests.TestAlphaOnBitmapPaint;
begin
  const Tile = TPdfBitmap.Create(2, 2);
  try
    for var Index := 0 to 3 do
    begin
      Tile.SetPixel(Index mod 2, Index div 2, TPdfDeviceColor.Create(255, 0, 0));
    end;

    var Composite := NoAntiAlias;
    Composite.Alpha := 0.5;
    FillWholeDevice(TPdfPaint.FromBitmap(Tile, TPdfMatrix.Identity, TPdfTileMode.&Repeat, TPdfImageFilter.Nearest), Composite);

    AssertPixel(5, 5, TPdfDeviceColor.Create(128, 0, 0, 128), 1);
    FDevice.Clear(TPdfDeviceColor.Transparent);

    var Drawn := NoAntiAlias;
    Drawn.Alpha := 0.5;
    FDevice.DrawBitmap(Tile, TPdfMatrix.GetScaleInstance(5, 5), TPdfImageFilter.Nearest, Drawn);
  finally
    Tile.Free;
  end;

  AssertPixel(5, 5, TPdfDeviceColor.Create(128, 0, 0, 128), 1);
end;

// A bitmap paint with a soft mask runs the stage that applies the mask on the high precision pipeline; the expected pixel is the premultiplied
// pixel of the bitmap times the value of the mask
procedure TPdfNativeDeviceTests.TestSoftMaskOnBitmapPaint;
begin
  const Tile = TPdfBitmap.Create(2, 2);
  const Mask = NewMask(0, 0, 10, 10, 128, 128);
  try
    for var Index := 0 to 3 do
    begin
      Tile.SetPixel(Index mod 2, Index div 2, TPdfDeviceColor.Create(100, 50, 20, 128));
    end;

    var Composite := NoAntiAlias;
    Composite.SoftMask := Mask;
    FillWholeDevice(TPdfPaint.FromBitmap(Tile, TPdfMatrix.Identity, TPdfTileMode.&Repeat, TPdfImageFilter.Nearest), Composite);
  finally
    Mask.Free;
    Tile.Free;
  end;

  const Expected = TPdfDeviceColor.Create(Round(100 * 128 / 255), Round(50 * 128 / 255), Round(20 * 128 / 255), Round(128 * 128 / 255));
  AssertPixel(5, 5, Expected, 1);
  AssertPixel(0, 0, Expected, 1);
  AssertPixel(9, 9, Expected, 1);
end;

// A mask object is freed and another one is made, perhaps at the same address: the combination is built from the values, not the identity
procedure TPdfNativeDeviceTests.TestSoftMaskIsRebuiltWhenItsValuesChange;
begin
  for var Value := 1 to 2 do
  begin
    FDevice.Clear(TPdfDeviceColor.Transparent);
    const Mask = NewMask(0, 0, 10, 10, Byte(Value * 100), 0);
    try
      var Composite := NoAntiAlias;
      Composite.SoftMask := Mask;
      FillWholeDevice(Red, Composite);
      AssertPixel(5, 5, TPdfDeviceColor.Create(Value * 100, 0, 0, Value * 100), 1);
    finally
      Mask.Free;
    end;
  end;
end;

procedure TPdfNativeDeviceTests.TestSoftMaskOutsideTheClipDrawsNothing;
begin
  FDevice.SetClip(NewClip(nil, 20, 20, 30, 30));
  const Mask = NewMask(0, 0, 10, 10, 255, 255);
  try
    var Composite := NoAntiAlias;
    Composite.SoftMask := Mask;
    FillWholeDevice(Red, Composite);
  finally
    Mask.Free;
  end;

  AssertNothingIsDrawn;
end;

function TPdfNativeDeviceTests.FillRaisesTheLimit(const Device: IPdfRasterDevice; const Path: TPdfPath): Boolean;
begin
  Result := False;
  try
    Device.FillPath(Path, TPdfMatrix.Identity, TPdfFillRule.NonZero, Red, NoAntiAlias);
  except
    on EPdfLimitExceededException do
    begin
      Result := True;
    end;
  end;
end;

procedure TPdfNativeDeviceTests.TestLayerHasSameLimits;
begin
  var Limits := TPdfNativeLimits.Default;
  Limits.MaxPathVerbs := 10;
  const Backend: IPdfRenderBackend = TPdfNativeBackend.Create(Limits);
  FDevice := Backend.CreateRasterDevice(10, 10);
  const Layer = FDevice.CreateLayer(4, 4);

  const Path = TPdfPath.Create;
  try
    Path.MoveTo(0, 0);
    for var Index := 1 to 10 do
    begin
      Path.LineTo(Index, Index mod 2);
    end;
    Assert.IsTrue(FillRaisesTheLimit(FDevice, Path), 'the device raises at 11 verbs');
    Assert.IsTrue(FillRaisesTheLimit(Layer, Path), 'the layer raises at 11 verbs');

    Path.Clear;
    Path.MoveTo(0, 0);
    for var Index := 1 to 9 do
    begin
      Path.LineTo(Index, Index mod 2);
    end;
    Assert.IsFalse(FillRaisesTheLimit(Layer, Path), 'the layer takes 10 verbs');
  finally
    Path.Free;
  end;
end;

end.
