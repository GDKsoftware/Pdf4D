// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.ViewLayout.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  DUnitX.TestFramework,
  Pdf4D.Model.Rectangle,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.ViewLayout;

type
  [TestFixture]
  TPdfViewLayoutTests = class
  private
    FLayout: TPdfViewLayout;

    class function PageInfo(const CropBox: TPdfRectangle): TPdfPageInfo; static;
    class function Box(const Width, Height: Single): TPdfRectangle; static;
    class function LetterPages(const Count: Integer): TArray<TPdfPageInfo>; static;
    function LetterSize: TSize;
    function PageRect(const PageIndex: Integer): TRect;
    procedure CreateLayout(const Pages: TArray<TPdfPageInfo>);
    procedure UpdateDefault(const Mode: TPdfScrollMode; const CurrentPage: Integer);

  public
    [Teardown]
    procedure Teardown;

    [Test]
    procedure TestContinuousStacksPages;
    [Test]
    procedure TestNarrowPageIsCentred;
    [Test]
    procedure TestSinglePageHasOnlyCurrent;
    [Test]
    procedure TestVisiblePagesBinarySearch;
    [Test]
    procedure TestMostVisiblePage;
    [Test]
    procedure TestFitWidth;
    [Test]
    procedure TestFitPage;
    [Test]
    procedure TestRotationSwapsSize;
    [Test]
    procedure TestZoomIsClampedForHugePages;
    [Test]
    procedure TestZeroPages;
    [Test]
    procedure TestGapScalesWithPixelsPerInch;
    [Test]
    procedure TestTryFindPageAt;
    [Test]
    procedure TestSinglePageVisibleAndMostVisible;
    [Test]
    procedure TestInvalidArgumentsRaise;
    [Test]
    procedure TestContentSizeIsClampedForManyHugePages;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

const
  Gap96 = 8;
  Tolerance = 0.001;

{ TPdfViewLayoutTests }

class function TPdfViewLayoutTests.Box(const Width, Height: Single): TPdfRectangle;
begin
  Result.LowerLeftX := 0;
  Result.LowerLeftY := 0;
  Result.UpperRightX := Width;
  Result.UpperRightY := Height;
end;

class function TPdfViewLayoutTests.PageInfo(const CropBox: TPdfRectangle): TPdfPageInfo;
begin
  Result.CropBox := CropBox;
  Result.Rotation := 0;
  Result.Label_ := '';
end;

class function TPdfViewLayoutTests.LetterPages(const Count: Integer): TArray<TPdfPageInfo>;
begin
  SetLength(Result, Count);
  for var Index := 0 to Count - 1 do
  begin
    Result[Index] := PageInfo(TPdfRectangle.Letter);
  end;
end;

procedure TPdfViewLayoutTests.CreateLayout(const Pages: TArray<TPdfPageInfo>);
begin
  FLayout.Free;
  FLayout := TPdfViewLayout.Create(Pages);
end;

procedure TPdfViewLayoutTests.UpdateDefault(const Mode: TPdfScrollMode; const CurrentPage: Integer);
begin
  FLayout.Update(0, 1, 96, Mode, CurrentPage);
end;

function TPdfViewLayoutTests.LetterSize: TSize;
begin
  Result := FLayout.Transform(0).Size;
end;

function TPdfViewLayoutTests.PageRect(const PageIndex: Integer): TRect;
begin
  Assert.IsTrue(FLayout.TryGetPageRect(PageIndex, Result), 'page has a rectangle');
end;

procedure TPdfViewLayoutTests.Teardown;
begin
  FreeAndNil(FLayout);
end;

procedure TPdfViewLayoutTests.TestContinuousStacksPages;
begin
  CreateLayout(LetterPages(3));
  UpdateDefault(TPdfScrollMode.Continuous, 0);
  const PageSize = LetterSize;

  Assert.AreEqual<Integer>(Gap96, PageRect(0).Top);
  Assert.AreEqual<Integer>(Gap96 + PageSize.cy + Gap96, PageRect(1).Top);
  Assert.AreEqual<Integer>(PageSize.cx + 2 * Gap96, FLayout.ContentSize.cx);
  Assert.AreEqual<Integer>(3 * PageSize.cy + 4 * Gap96, FLayout.ContentSize.cy);
  Assert.AreEqual<Integer>(Gap96, FLayout.Gap);
end;

procedure TPdfViewLayoutTests.TestNarrowPageIsCentred;
begin
  const Pages: TArray<TPdfPageInfo> = [PageInfo(TPdfRectangle.Letter), PageInfo(Box(420, 595)), PageInfo(TPdfRectangle.Letter)];
  CreateLayout(Pages);
  UpdateDefault(TPdfScrollMode.Continuous, 0);

  const NarrowWidth = FLayout.Transform(1).Size.cx;

  Assert.AreEqual<Integer>((FLayout.ContentSize.cx - NarrowWidth) div 2, PageRect(1).Left);
  Assert.AreEqual<Integer>(NarrowWidth, PageRect(1).Width);
  Assert.AreEqual<Integer>(Gap96, PageRect(0).Left);
end;

procedure TPdfViewLayoutTests.TestSinglePageHasOnlyCurrent;
begin
  CreateLayout(LetterPages(3));
  UpdateDefault(TPdfScrollMode.SinglePage, 1);
  const PageSize = LetterSize;
  var Rect: TRect;

  Assert.IsFalse(FLayout.TryGetPageRect(0, Rect), 'page 0');
  Assert.IsTrue(FLayout.TryGetPageRect(1, Rect), 'page 1');
  Assert.IsFalse(FLayout.TryGetPageRect(2, Rect), 'page 2');
  Assert.AreEqual<Integer>(Gap96, PageRect(1).Top);
  Assert.AreEqual<Integer>(PageSize.cy + 2 * Gap96, FLayout.ContentSize.cy);
  Assert.AreEqual<Integer>(PageSize.cx + 2 * Gap96, FLayout.ContentSize.cx);
end;

procedure TPdfViewLayoutTests.TestVisiblePagesBinarySearch;
begin
  CreateLayout(LetterPages(1000));
  UpdateDefault(TPdfScrollMode.Continuous, 0);
  const Width = FLayout.ContentSize.cx;

  const Single500 = FLayout.VisiblePages(TRect.Create(0, PageRect(500).Top, Width, PageRect(500).Top + 100));
  const Pair = FLayout.VisiblePages(TRect.Create(0, PageRect(10).Bottom - 50, Width, PageRect(11).Top + 50));

  Assert.AreEqual<Integer>(1, Length(Single500));
  Assert.AreEqual<Integer>(500, Single500[0]);
  Assert.AreEqual<Integer>(2, Length(Pair));
  Assert.AreEqual<Integer>(10, Pair[0]);
  Assert.AreEqual<Integer>(11, Pair[1]);
end;

procedure TPdfViewLayoutTests.TestMostVisiblePage;
begin
  CreateLayout(LetterPages(8));
  UpdateDefault(TPdfScrollMode.Continuous, 0);
  const Width = FLayout.ContentSize.cx;
  const Unequal = TRect.Create(0, PageRect(3).Bottom - 300, Width, PageRect(4).Top + 500);
  const Equal = TRect.Create(0, PageRect(3).Bottom - 300, Width, PageRect(4).Top + 300);

  Assert.AreEqual<Integer>(4, FLayout.MostVisiblePage(Unequal));
  Assert.AreEqual<Integer>(3, FLayout.MostVisiblePage(Equal));
end;

procedure TPdfViewLayoutTests.TestFitWidth;
begin
  CreateLayout(LetterPages(3));
  UpdateDefault(TPdfScrollMode.Continuous, 0);
  const Viewport = TSize.Create(LetterSize.cx + 2 * Gap96, 600);

  Assert.AreEqual(Double(1), Double(FLayout.ZoomToFit(TPdfZoomMode.FitWidth, Viewport, 0)), Tolerance);
end;

procedure TPdfViewLayoutTests.TestFitPage;
begin
  CreateLayout(LetterPages(3));
  UpdateDefault(TPdfScrollMode.Continuous, 0);
  const Viewport = TSize.Create(2000, LetterSize.cy + 2 * Gap96);

  Assert.AreEqual(Double(1), Double(FLayout.ZoomToFit(TPdfZoomMode.FitPage, Viewport, 0)), Tolerance);
  Assert.AreEqual(Double(1), Double(FLayout.ZoomToFit(TPdfZoomMode.Factor, Viewport, 0)), Tolerance);
end;

procedure TPdfViewLayoutTests.TestRotationSwapsSize;
begin
  CreateLayout(LetterPages(2));
  UpdateDefault(TPdfScrollMode.Continuous, 0);
  const Upright = FLayout.Transform(1).Size;

  FLayout.Update(90, 1, 96, TPdfScrollMode.Continuous, 0);

  for var PageIndex := 0 to 1 do
  begin
    Assert.AreEqual<Integer>(Upright.cy, FLayout.Transform(PageIndex).Size.cx);
    Assert.AreEqual<Integer>(Upright.cx, FLayout.Transform(PageIndex).Size.cy);
    Assert.AreEqual<Integer>(Upright.cy, PageRect(PageIndex).Width);
  end;
end;

procedure TPdfViewLayoutTests.TestZoomIsClampedForHugePages;
begin
  CreateLayout([PageInfo(Box(14400, 14400))]);

  FLayout.Update(0, 8, 192, TPdfScrollMode.Continuous, 0);

  const PageSize = FLayout.Transform(0).Size;
  Assert.IsTrue(PageSize.cx <= MaxPageEdgePixels, 'width');
  Assert.IsTrue(PageSize.cy <= MaxPageEdgePixels, 'height');
  Assert.IsTrue(PageSize.cx >= MaxPageEdgePixels - 1, 'clamped, not smaller than needed');
  Assert.AreEqual(Double(MaxPageEdgePixels / 14400), Double(FLayout.Transform(0).Scale), 0.0001);
  Assert.IsTrue(FLayout.ContentSize.cx > 0, 'content width');
  Assert.IsTrue(FLayout.ContentSize.cy > 0, 'content height');
end;

procedure TPdfViewLayoutTests.TestZeroPages;
begin
  CreateLayout(nil);
  UpdateDefault(TPdfScrollMode.Continuous, 0);
  const Viewport = TRect.Create(0, 0, 500, 500);

  Assert.AreEqual<Integer>(0, FLayout.ContentSize.cx);
  Assert.AreEqual<Integer>(0, FLayout.ContentSize.cy);
  Assert.AreEqual<Integer>(0, Length(FLayout.VisiblePages(Viewport)));
  Assert.AreEqual<Integer>(0, FLayout.MostVisiblePage(Viewport));

  UpdateDefault(TPdfScrollMode.SinglePage, 0);

  Assert.AreEqual<Integer>(0, FLayout.ContentSize.cy);
  Assert.AreEqual<Integer>(0, Length(FLayout.VisiblePages(Viewport)));
end;

procedure TPdfViewLayoutTests.TestGapScalesWithPixelsPerInch;
begin
  CreateLayout(LetterPages(2));

  FLayout.Update(0, 1, 144, TPdfScrollMode.Continuous, 0);

  Assert.AreEqual<Integer>(12, FLayout.Gap);
  Assert.AreEqual<Integer>(12, PageRect(0).Top);
end;

procedure TPdfViewLayoutTests.TestTryFindPageAt;
begin
  CreateLayout(LetterPages(3));
  UpdateDefault(TPdfScrollMode.Continuous, 0);
  const Second = PageRect(1);
  var PageIndex: Integer;

  Assert.IsTrue(FLayout.TryFindPageAt(Second.CenterPoint, PageIndex), 'inside page 1');
  Assert.AreEqual<Integer>(1, PageIndex);
  Assert.IsTrue(FLayout.TryFindPageAt(Second.TopLeft, PageIndex), 'top left corner');
  Assert.AreEqual<Integer>(1, PageIndex);
  Assert.IsFalse(FLayout.TryFindPageAt(TPoint.Create(Second.Left, Second.Top - 1), PageIndex), 'in the gap');
  Assert.IsFalse(FLayout.TryFindPageAt(TPoint.Create(Second.Left - 1, Second.Top + 10), PageIndex), 'left of the page');
  Assert.IsFalse(FLayout.TryFindPageAt(TPoint.Create(Second.Left, -5), PageIndex), 'above the content');
  Assert.IsFalse(FLayout.TryFindPageAt(TPoint.Create(Second.Left, FLayout.ContentSize.cy + 5), PageIndex), 'below the content');
end;

procedure TPdfViewLayoutTests.TestSinglePageVisibleAndMostVisible;
begin
  CreateLayout(LetterPages(3));
  UpdateDefault(TPdfScrollMode.SinglePage, 2);
  const Width = FLayout.ContentSize.cx;
  var PageIndex: Integer;

  const Visible = FLayout.VisiblePages(TRect.Create(0, 0, Width, 100));
  const Beyond = FLayout.VisiblePages(TRect.Create(0, FLayout.ContentSize.cy, Width, FLayout.ContentSize.cy + 100));

  Assert.AreEqual<Integer>(1, Length(Visible));
  Assert.AreEqual<Integer>(2, Visible[0]);
  Assert.AreEqual<Integer>(0, Length(Beyond));
  Assert.AreEqual<Integer>(2, FLayout.MostVisiblePage(TRect.Create(0, 0, Width, 100)));
  Assert.IsTrue(FLayout.TryFindPageAt(PageRect(2).CenterPoint, PageIndex), 'inside the current page');
  Assert.AreEqual<Integer>(2, PageIndex);
end;

procedure TPdfViewLayoutTests.TestInvalidArgumentsRaise;
begin
  CreateLayout(LetterPages(1));

  Assert.WillRaise(procedure begin FLayout.Update(45, 1, 96, TPdfScrollMode.Continuous, 0); end, EArgumentException);
  Assert.WillRaise(procedure begin FLayout.Update(0, 0, 96, TPdfScrollMode.Continuous, 0); end, EArgumentException);
  Assert.WillRaise(procedure begin FLayout.Update(0, 1, 0, TPdfScrollMode.Continuous, 0); end, EArgumentException);
  Assert.WillRaise(procedure begin FLayout.Transform(1); end, EArgumentOutOfRangeException);
end;

procedure TPdfViewLayoutTests.TestContentSizeIsClampedForManyHugePages;
begin
  const HugePage = PageInfo(Box(14400, 14400));
  var Many: TArray<TPdfPageInfo>;
  SetLength(Many, 30000);
  for var Index := 0 to High(Many) do
  begin
    Many[Index] := HugePage;
  end;
  CreateLayout(Many);

  FLayout.Update(0, 8, 192, TPdfScrollMode.Continuous, 0);

  Assert.AreEqual<Integer>(MaxInt, FLayout.ContentSize.cy);
  Assert.AreEqual<Integer>(MaxInt, PageRect(High(Many)).Bottom);
  Assert.IsTrue(PageRect(High(Many)).Top > 0, 'last page top');
end;

end.
