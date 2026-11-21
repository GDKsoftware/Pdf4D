// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.ClipPath.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  DUnitX.TestFramework,
  Pdf4D.Common.Matrix,
  Pdf4D.Common.Path,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Render.ClipPath;

type
  [TestFixture]
  TPdfClipPathTests = class
  private
    function NewClip(const Parent: IPdfClipPath; const FillRule: TPdfFillRule): IPdfClipPath;

  public
    [Test]
    procedure TestClipChainKeepsParents;

    [Test]
    procedure TestClipExposesItsValues;

    [Test]
    procedure TestClipOwnsItsPath;

    [Test]
    procedure TestVeryLongChainIsReleasedWithoutRecursion;

    [Test]
    procedure TestSharedParentSurvivesReleaseOfItsChild;

    [Test]
    procedure TestDepthCountsThePathsOfTheChain;

    [Test]
    procedure TestBoundsAreTheIntersectionOfTheChain;

    [Test]
    procedure TestFlattenedChainIsTheRectangleOfItsBounds;
  end;

implementation

{ TPdfClipPathTests }

function TPdfClipPathTests.NewClip(const Parent: IPdfClipPath; const FillRule: TPdfFillRule): IPdfClipPath;
begin
  const Path = TPdfPath.Create;
  Path.MoveTo(0, 0);
  Path.LineTo(10, 0);
  Path.LineTo(10, 10);
  Path.ClosePath;
  Result := TPdfClipPath.Create(Parent, Path, TPdfMatrix.Identity, FillRule);
end;

procedure TPdfClipPathTests.TestDepthCountsThePathsOfTheChain;
begin
  const First = NewClip(nil, TPdfFillRule.NonZero);
  const Second = NewClip(First, TPdfFillRule.NonZero);

  Assert.AreEqual(1, First.Depth);
  Assert.AreEqual(2, Second.Depth);
  Assert.AreEqual(3, NewClip(Second, TPdfFillRule.NonZero).Depth);
end;

function RectangleClip(const Parent: IPdfClipPath; const Left, Top, Right, Bottom: Single; const Transform: TPdfMatrix): IPdfClipPath;
begin
  const Path = TPdfPath.Create;
  Path.MoveTo(Left, Top);
  Path.LineTo(Right, Top);
  Path.LineTo(Right, Bottom);
  Path.LineTo(Left, Bottom);
  Path.ClosePath;
  Result := TPdfClipPath.Create(Parent, Path, Transform, TPdfFillRule.NonZero);
end;

procedure TPdfClipPathTests.TestBoundsAreTheIntersectionOfTheChain;
begin
  const First = RectangleClip(nil, 0, 0, 10, 10, TPdfMatrix.Identity);
  const Second = RectangleClip(First, 2, 3, 20, 20, TPdfMatrix.Identity);
  const Moved = RectangleClip(Second, 0, 0, 4, 4, TPdfMatrix.GetTranslateInstance(5, 5));

  Assert.IsTrue(First.Bounds = TRectF.Create(0, 0, 10, 10));
  Assert.IsTrue(Second.Bounds = TRectF.Create(2, 3, 10, 10));
  Assert.IsTrue(Moved.Bounds = TRectF.Create(5, 5, 9, 9));
end;

procedure TPdfClipPathTests.TestFlattenedChainIsTheRectangleOfItsBounds;
begin
  const First = RectangleClip(nil, 0, 0, 10, 10, TPdfMatrix.Identity);
  const Second = RectangleClip(First, 2, 3, 20, 20, TPdfMatrix.Identity);

  const Flat = TPdfClipPath.Flattened(Second);

  Assert.AreEqual(1, Flat.Depth);
  Assert.IsNull(Flat.Parent);
  Assert.IsTrue(Flat.Bounds = TRectF.Create(2, 3, 10, 10));
end;

procedure TPdfClipPathTests.TestClipChainKeepsParents;
begin
  var Last: IPdfClipPath;
  var First: IPdfClipPath := NewClip(nil, TPdfFillRule.NonZero);
  var Second: IPdfClipPath := NewClip(First, TPdfFillRule.EvenOdd);
  Last := NewClip(Second, TPdfFillRule.NonZero);

  First := nil;
  Second := nil;

  Assert.IsNotNull(Last.Parent);
  Assert.IsNotNull(Last.Parent.Parent);
  Assert.IsNull(Last.Parent.Parent.Parent);
  Assert.AreEqual(TPdfFillRule.NonZero, Last.Parent.Parent.FillRule);
  Assert.AreEqual(TPdfFillRule.EvenOdd, Last.Parent.FillRule);

  // The memory check of the test program reports a clip or path that is not freed with the last reference
  Last := nil;
end;

procedure TPdfClipPathTests.TestClipExposesItsValues;
begin
  const Path = TPdfPath.Create;
  Path.MoveTo(1, 2);
  const Transform = TPdfMatrix.GetScaleInstance(2, 3);

  const Clip: IPdfClipPath = TPdfClipPath.Create(nil, Path, Transform, TPdfFillRule.EvenOdd);

  Assert.AreSame(Path, Clip.Path);
  Assert.IsTrue(Transform.IsEqual(Clip.Transform));
  Assert.AreEqual(TPdfFillRule.EvenOdd, Clip.FillRule);
  Assert.IsNull(Clip.Parent);
end;

procedure TPdfClipPathTests.TestClipOwnsItsPath;
begin
  const Clip = NewClip(nil, TPdfFillRule.NonZero);

  Assert.AreEqual(3, Clip.Path.PointCount);
end;

procedure TPdfClipPathTests.TestVeryLongChainIsReleasedWithoutRecursion;
begin
  var Last: IPdfClipPath;
  for var Index := 1 to 100000 do
  begin
    Last := NewClip(Last, TPdfFillRule.NonZero);
  end;

  Assert.IsNotNull(Last);
  Last := nil;
  Assert.IsNull(Last);
end;

procedure TPdfClipPathTests.TestSharedParentSurvivesReleaseOfItsChild;
begin
  const Shared = NewClip(nil, TPdfFillRule.EvenOdd);
  var Child: IPdfClipPath := NewClip(Shared, TPdfFillRule.NonZero);
  var Grandchild: IPdfClipPath := NewClip(Child, TPdfFillRule.NonZero);

  Child := nil;
  Grandchild := nil;

  Assert.AreEqual(TPdfFillRule.EvenOdd, Shared.FillRule);
  Assert.IsNotNull(Shared.Path);
end;

end.
