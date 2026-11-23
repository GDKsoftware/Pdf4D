// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.PageViewController.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Common.Quad,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.Session,
  Pdf4D.Viewer.PageViewController,
  Pdf4D.Viewer.Painter.Interfaces,
  Pdf4D.Tests.TestDocument,
  Pdf4D.Tests.FakeSession,
  Pdf4D.Tests.RecordingPainter;

type
  [TestFixture]
  TPdfPageViewControllerTests = class
  private
    FFake: TFakeViewerSession;
    FSession: IPdfViewerSession;
    FDocument: TTestDocument;
    FHost: TRecordingHost;
    FHostReference: IPdfViewHost;
    FController: TPdfPageViewController;
    FZoomEvents: Integer;

    class function LetterPage(const Rotation: Integer): TPdfPageInfo; static;
    class function Square: TPdfQuad; static;
    procedure OpenPages(const Pages: TArray<TPdfPageInfo>);
    // Opens PageCount Letter pages in a viewport of 832 x 600 at 96 PPI and zoom 1
    procedure Start(const PageCount: Integer);
    procedure HandleZoomChanged(Sender: TObject);
    function Painted: TRecordingPainter;
    function TileRequests: TArray<TFakeRequest>;
    function FindTiles(const PageIndex: Integer; const Priority: TPdfJobPriority): TFakeRequest;
    // Completes every request that is still open
    procedure CompleteOpenTileRequests;
    function FindSearchRequestIndex: Integer;

  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestInitialViewRequestsVisibleTilesOfPageZero;
    [Test]
    procedure TestCompletedTilesArePainted;
    [Test]
    procedure TestScrollRequestsOnlyMissingTiles;
    [Test]
    procedure TestFastScrollCancelsInvisibleTiles;
    [Test]
    procedure TestZoomInUsesPreviousTilesUntilNewArrive;
    [Test]
    procedure TestScaleChangeCancelsPendingTiles;
    [Test]
    procedure TestFitWidthFollowsViewport;
    [Test]
    procedure TestZoomStepsAndClamp;
    [Test]
    procedure TestRotateClockwiseRerenders;
    [Test]
    procedure TestCurrentPageFollowsScroll;
    [Test]
    procedure TestGoToPageScrollsToTop;
    [Test]
    procedure TestOverlayIsPaintedInViewSpace;
    [Test]
    procedure TestOverlayOnRotatedCroppedPage;
    [Test]
    procedure TestOverlayChangeRepaintsWithoutRender;
    [Test]
    procedure TestRenderFailureLeavesPageWhite;
    [Test]
    procedure TestCachesStayWithinTileBudget;
    [Test]
    procedure TestAttachToOpenDocumentUsesItsCurrentPage;
    [Test]
    procedure TestClosingTheDocumentEmptiesTheView;
    [Test]
    procedure TestSearchHitsArePainted;
    [Test]
    procedure TestNarrowPageIsCentred;
    [Test]
    procedure TestViewportToPageUsesTheScroll;
    [Test]
    procedure TestSinglePageShowsOnlyTheCurrentPage;
    [Test]
    procedure TestScrollModeBackToContinuousScrollsToCurrentPage;
  end;

implementation

uses
  System.Math,
  System.UITypes,
  System.Generics.Collections,
  Pdf4D.Model.Rectangle,
  Pdf4D.Render.PageTransform,
  Pdf4D.Viewer.Tiles;

const
  ViewportWidth = 832;
  ViewportHeight = 600;
  // A Letter page at 96 PPI
  PageWidth = 816;
  PageHeight = 1056;
  Gap = 8;
  Scale96 = 96 / 72;
  OneMebibyte = 1024 * 1024;

{ TPdfPageViewControllerTests }

procedure TPdfPageViewControllerTests.Setup;
begin
  FFake := TFakeViewerSession.Create;
  FSession := FFake;
  FDocument := TTestDocument.Create(nil);
  FHost := TRecordingHost.Create;
  FHostReference := FHost;
  FZoomEvents := 0;
end;

procedure TPdfPageViewControllerTests.TearDown;
begin
  FController.Free;
  FController := nil;
  FDocument.Free;
  FSession := nil;
  FHostReference := nil;
end;

class function TPdfPageViewControllerTests.LetterPage(const Rotation: Integer): TPdfPageInfo;
begin
  Result.CropBox := TPdfRectangle.Letter;
  Result.Rotation := Rotation;
  Result.Label_ := '';
end;

class function TPdfPageViewControllerTests.Square: TPdfQuad;
begin
  Result := TPdfQuad.Create(TPointF.Create(100, 700), TPointF.Create(160, 700), TPointF.Create(160, 712), TPointF.Create(100, 712));
end;

procedure TPdfPageViewControllerTests.OpenPages(const Pages: TArray<TPdfPageInfo>);
begin
  var Permissions: TPdfViewerPermissions;
  Permissions.CanPrint := True;
  Permissions.CanCopy := True;
  FFake.SetOpened(Pages, nil, Permissions);
  FDocument.OpenWithSession(FSession);
end;

procedure TPdfPageViewControllerTests.Start(const PageCount: Integer);
begin
  const Pages = TList<TPdfPageInfo>.Create;
  try
    for var Index := 1 to PageCount do
    begin
      Pages.Add(LetterPage(0));
    end;
    OpenPages(Pages.ToArray);
  finally
    Pages.Free;
  end;

  FController := TPdfPageViewController.Create(FHostReference);
  FController.OnZoomChanged := HandleZoomChanged;
  FController.Document := FDocument;
  FController.Zoom := 1;
  FController.SetViewport(TSize.Create(ViewportWidth, ViewportHeight), 96);
  FZoomEvents := 0;
end;

procedure TPdfPageViewControllerTests.HandleZoomChanged(Sender: TObject);
begin
  Inc(FZoomEvents);
end;

function TPdfPageViewControllerTests.Painted: TRecordingPainter;
begin
  const Painter = TRecordingPainter.Create;
  const Reference: IPdfViewPainter = Painter;
  FController.Paint(Reference, TRect.Create(0, 0, ViewportWidth, ViewportHeight));
  // The calls stay valid after the painter is released by the caller: copy them into a painter that lives on
  Result := TRecordingPainter.Create;
  Result.Calls.AddRange(Painter.Calls);
end;

function TPdfPageViewControllerTests.TileRequests: TArray<TFakeRequest>;
begin
  const Found = TList<TFakeRequest>.Create;
  try
    for var Request in FFake.Requests do
    begin
      if Request.Kind = TFakeRequestKind.Tiles then
      begin
        Found.Add(Request);
      end;
    end;
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

// The most recent request that is not cancelled
function TPdfPageViewControllerTests.FindTiles(const PageIndex: Integer; const Priority: TPdfJobPriority): TFakeRequest;
begin
  Result := nil;
  for var Request in TileRequests do
  begin
    if (Request.PageIndex = PageIndex) and (Request.Priority = Priority) and (not Request.Cancelled) then
    begin
      Result := Request;
    end;
  end;
end;

function TPdfPageViewControllerTests.FindSearchRequestIndex: Integer;
begin
  Result := -1;
  for var Index := 0 to FFake.Requests.Count - 1 do
  begin
    if FFake.Requests[Index].Kind = TFakeRequestKind.Search then
    begin
      Result := Index;
    end;
  end;
end;

procedure TPdfPageViewControllerTests.CompleteOpenTileRequests;
begin
  for var Index := 0 to FFake.Requests.Count - 1 do
  begin
    const Request = FFake.Requests[Index];
    if (Request.Kind = TFakeRequestKind.Tiles) and (not Request.IsDone) then
    begin
      FFake.CompleteTiles(Index, TAlphaColors.Red);
    end;
  end;
end;

procedure TPdfPageViewControllerTests.TestInitialViewRequestsVisibleTilesOfPageZero;
begin
  Start(3);

  Assert.AreEqual(3, Integer(FFake.Requests.Count), 'tiles, text, prefetch');

  const Visible = FFake.Requests[0];
  Assert.AreEqual(Ord(TFakeRequestKind.Tiles), Ord(Visible.Kind));
  Assert.AreEqual(0, Visible.PageIndex);
  Assert.AreEqual(Ord(TPdfJobPriority.Visible), Ord(Visible.Priority));
  Assert.AreEqual(Double(Scale96), Double(Visible.Scale), 0.00001);
  Assert.AreEqual(12, Integer(Length(Visible.Tiles)));
  Assert.AreEqual(0, Visible.Tiles[0].X);
  Assert.AreEqual(0, Visible.Tiles[0].Y);
  Assert.AreEqual(3, Visible.Tiles[11].X);
  Assert.AreEqual(2, Visible.Tiles[11].Y);

  Assert.AreEqual(Ord(TFakeRequestKind.PageText), Ord(FFake.Requests[1].Kind));
  Assert.AreEqual(0, FFake.Requests[1].PageIndex);

  const Prefetch = FFake.Requests[2];
  Assert.AreEqual(Ord(TFakeRequestKind.Tiles), Ord(Prefetch.Kind));
  Assert.AreEqual(1, Prefetch.PageIndex);
  Assert.AreEqual(Ord(TPdfJobPriority.Prefetch), Ord(Prefetch.Priority));
end;

procedure TPdfPageViewControllerTests.TestCompletedTilesArePainted;
begin
  Start(3);
  FHost.Reset;

  FFake.CompleteTiles(0, TAlphaColors.Red);
  const Painter = Painted;
  try
    const Images = Painter.Of_(TPaintKind.DrawImage);
    Assert.AreEqual(12, Integer(Length(Images)));

    var Found := False;
    for var Call in Images do
    begin
      if (Call.Rect.Left = Gap + PdfTileSize) and (Call.Rect.Top = Gap) and (Call.Rect.Width = PdfTileSize) then
      begin
        Found := True;
      end;
    end;
    Assert.IsTrue(Found, 'tile (1,0) at (8 + 256, 8)');
    Assert.IsTrue(FHost.Covers(TRect.Create(Gap + PdfTileSize, Gap, Gap + 2 * PdfTileSize, Gap + PdfTileSize)), 'the tile was invalidated');
  finally
    Painter.Free;
  end;
end;

procedure TPdfPageViewControllerTests.TestScrollRequestsOnlyMissingTiles;
begin
  Start(3);
  const Before = Integer(FFake.Requests.Count);

  FController.ScrollBy(0, 200);

  Assert.AreEqual(Before + 1, Integer(FFake.Requests.Count));
  const Request = FFake.Requests[Before];
  Assert.AreEqual(Ord(TFakeRequestKind.Tiles), Ord(Request.Kind));
  Assert.AreEqual(4, Integer(Length(Request.Tiles)));
  for var Tile in Request.Tiles do
  begin
    Assert.AreEqual(3, Tile.Y, 'only row 3');
  end;
end;

procedure TPdfPageViewControllerTests.TestFastScrollCancelsInvisibleTiles;
begin
  Start(1000);
  const Step = (Gap + 900 * (PageHeight + Gap) - Gap) div 10;

  for var Index := 1 to 9 do
  begin
    FController.ScrollTo(TPoint.Create(0, Index * Step));
  end;
  FController.GoToPage(900);

  for var Request in FFake.Requests do
  begin
    if Request.Kind = TFakeRequestKind.Search then
    begin
      Continue;
    end;

    const IsLastViewport = (Request.PageIndex >= 899) and (Request.PageIndex <= 901);
    Assert.AreEqual(not IsLastViewport, Request.Cancelled, Format('page %d', [Request.PageIndex]));
  end;
  Assert.IsNotNull(FindTiles(900, TPdfJobPriority.Visible));
  Assert.AreEqual(900, FDocument.CurrentPage);
end;

procedure TPdfPageViewControllerTests.TestZoomInUsesPreviousTilesUntilNewArrive;
begin
  Start(3);
  FFake.CompleteTiles(0, TAlphaColors.Red);

  FController.ZoomIn;
  const Painter = Painted;
  try
    const Images = Painter.Of_(TPaintKind.DrawImage);
    Assert.IsTrue(Length(Images) > 0, 'old tiles are drawn');
    for var Call in Images do
    begin
      Assert.IsTrue(Call.Rect.Width > Call.Source.Width, 'scaled up');
    end;
  finally
    Painter.Free;
  end;

  const Request = FindTiles(0, TPdfJobPriority.Visible);
  Assert.IsNotNull(Request);
  Assert.AreEqual(Double(1.25 * Scale96), Double(Request.Scale), 0.00001);
end;

procedure TPdfPageViewControllerTests.TestScaleChangeCancelsPendingTiles;
begin
  Start(3);

  FController.SetViewport(TSize.Create(ViewportWidth, ViewportHeight), 144);

  const Old = FFake.Requests[0];
  Assert.IsTrue(Old.Cancelled);
  Assert.IsTrue(FFake.Requests[2].Cancelled);
  const Request = FindTiles(0, TPdfJobPriority.Visible);
  Assert.IsNotNull(Request);
  Assert.AreEqual(2.0, Double(Request.Scale), 0.00001);
  Assert.AreEqual(0, FDocument.CurrentPage);
end;

procedure TPdfPageViewControllerTests.TestFitWidthFollowsViewport;
begin
  Start(3);

  FController.ZoomMode := TPdfZoomMode.FitWidth;
  Assert.AreEqual(0, FZoomEvents, 'the viewport already fits');

  FController.SetViewport(TSize.Create(1200, ViewportHeight), 96);

  Assert.AreEqual((1200 - 2 * Gap) / PageWidth, Double(FController.Zoom), 0.0001);
  Assert.AreEqual(1, FZoomEvents);
  Assert.AreEqual(1200.0, Double(FController.ContentSize.cx), 2.0);
end;

procedure TPdfPageViewControllerTests.TestZoomStepsAndClamp;
begin
  Start(3);

  FController.Zoom := 1.1;
  FController.ZoomIn;
  Assert.AreEqual(1.25, Double(FController.Zoom), 0.0001);

  FController.Zoom := 0.1;
  FController.ZoomOut;
  Assert.AreEqual(0.1, Double(FController.Zoom), 0.0001);

  FController.Zoom := 20;
  Assert.AreEqual(8.0, Double(FController.Zoom), 0.0001);
  Assert.AreEqual(Ord(TPdfZoomMode.Factor), Ord(FController.ZoomMode));
end;

procedure TPdfPageViewControllerTests.TestRotateClockwiseRerenders;
begin
  Start(3);

  FController.RotateClockwise;

  Assert.AreEqual(90, FController.ViewRotation);
  Assert.AreEqual(PageHeight + 2 * Gap, Integer(FController.ContentSize.cx), 'the width of a rotated page is the height of a page');
  Assert.AreEqual(3 * (PageWidth + Gap) + Gap, Integer(FController.ContentSize.cy));
  Assert.IsTrue(FFake.Requests[0].Cancelled);
  const Request = FindTiles(0, TPdfJobPriority.Visible);
  Assert.IsNotNull(Request);
  Assert.AreEqual(90, Request.ViewRotation);
end;

procedure TPdfPageViewControllerTests.TestCurrentPageFollowsScroll;
begin
  Start(3);

  FController.ScrollTo(TPoint.Create(0, 1100));

  Assert.AreEqual(1, FDocument.CurrentPage);
  FController.ScrollTo(TPoint.Create(0, 0));
  Assert.AreEqual(0, FDocument.CurrentPage);
end;

procedure TPdfPageViewControllerTests.TestGoToPageScrollsToTop;
begin
  Start(3);
  const PageTop = Gap + 2 * (PageHeight + Gap);

  FDocument.CurrentPage := 2;

  Assert.AreEqual(PageTop - Gap, FController.ScrollPosition.Y);
  Assert.AreEqual(2, FDocument.CurrentPage, 'the scroll does not move the cursor back');

  FController.GoToPage(1);
  Assert.AreEqual(Gap + (PageHeight + Gap) - Gap, FController.ScrollPosition.Y);
  Assert.AreEqual(1, FDocument.CurrentPage);
end;

procedure TPdfPageViewControllerTests.TestOverlayIsPaintedInViewSpace;
begin
  Start(3);
  const Fill = FDocument.Overlays.Add(0, [Square], TPdfOverlayStyle.Fill, $80FF0000);
  FDocument.Overlays.Add(0, [Square], TPdfOverlayStyle.Frame, $FF00FF00);
  FDocument.Overlays.Add(0, [Square], TPdfOverlayStyle.Ellipse, $FF0000FF);
  Assert.IsTrue(Fill > 0);

  const Painter = Painted;
  try
    const Polygons = Painter.Of_(TPaintKind.FillPolygon);
    Assert.AreEqual(1, Integer(Length(Polygons)));
    Assert.AreEqual(4, Integer(Length(Polygons[0].Points)));
    Assert.AreEqual(Gap + 100 * Scale96, Double(Polygons[0].Points[0].X), 0.01);
    Assert.AreEqual(Gap + (792 - 700) * Scale96, Double(Polygons[0].Points[0].Y), 0.01);
    Assert.AreEqual(Gap + 160 * Scale96, Double(Polygons[0].Points[1].X), 0.01);
    Assert.AreEqual(Cardinal($80FF0000), Cardinal(Polygons[0].Color));

    const Frames = Painter.Of_(TPaintKind.FramePolygon);
    Assert.AreEqual(1, Integer(Length(Frames)));
    Assert.AreEqual(2.0, Double(Frames[0].Width), 0.0001);

    const Ellipses = Painter.Of_(TPaintKind.FillEllipse);
    Assert.AreEqual(1, Integer(Length(Ellipses)));
    const CenterX = Gap + 130 * Scale96;
    const CenterY = Gap + (792 - 706) * Scale96;
    Assert.AreEqual(CenterX, Double(Ellipses[0].Rect.CenterPoint.X), 0.05);
    Assert.AreEqual(CenterY, Double(Ellipses[0].Rect.CenterPoint.Y), 0.05);
    Assert.AreEqual(60 * Scale96 * Sqrt(2), Double(Ellipses[0].Rect.Width), 0.05);
    Assert.AreEqual(12 * Scale96 * Sqrt(2), Double(Ellipses[0].Rect.Height), 0.05);
  finally
    Painter.Free;
  end;
end;

procedure TPdfPageViewControllerTests.TestOverlayOnRotatedCroppedPage;
begin
  var Page := LetterPage(90);
  Page.CropBox.LowerLeftX := 50;
  Page.CropBox.LowerLeftY := 50;
  Page.CropBox.UpperRightX := 562;
  Page.CropBox.UpperRightY := 742;
  OpenPages([Page]);
  FController := TPdfPageViewController.Create(FHostReference);
  FController.Document := FDocument;
  FController.Zoom := 1;
  FController.SetViewport(TSize.Create(ViewportWidth, ViewportHeight), 96);
  FDocument.Overlays.Add(0, [Square], TPdfOverlayStyle.Fill, $80FF0000);

  const Painter = Painted;
  try
    const Polygons = Painter.Of_(TPaintKind.FillPolygon);
    Assert.AreEqual(1, Integer(Length(Polygons)));

    const Transform = TPdfPageTransform.Create(Page.CropBox, 90, Scale96);
    var Expected: TArray<TPointF>;
    Expected := [Square.P1, Square.P2, Square.P3, Square.P4];
    const Left = (FController.ContentSize.cx - Transform.Size.cx) div 2;
    for var Index := 0 to 3 do
    begin
      const Device = Transform.PageToDevice.TransformPoint(Expected[Index].X, Expected[Index].Y);
      Assert.AreEqual(Double(Left + Device.X), Double(Polygons[0].Points[Index].X), 0.5);
      Assert.AreEqual(Double(Gap + Device.Y), Double(Polygons[0].Points[Index].Y), 0.5);
    end;
  finally
    Painter.Free;
  end;
end;

procedure TPdfPageViewControllerTests.TestOverlayChangeRepaintsWithoutRender;
begin
  Start(3);
  const Before = Integer(FFake.Requests.Count);
  FHost.Reset;

  FDocument.Overlays.Add(0, [Square], TPdfOverlayStyle.Fill, $80FF0000);

  Assert.IsTrue(FHost.Invalidated.Count > 0);
  Assert.AreEqual(Before, Integer(FFake.Requests.Count));
end;

procedure TPdfPageViewControllerTests.TestRenderFailureLeavesPageWhite;
begin
  Start(3);
  const Before = Integer(FFake.Requests.Count);

  FFake.FailRender(0, 'broken');
  FController.ScrollBy(0, 1);
  const Painter = Painted;
  try
    Assert.AreEqual(0, Painter.Count(TPaintKind.DrawImage));
    Assert.IsTrue(Painter.Count(TPaintKind.FillRect) >= 2, 'background and the white page');
  finally
    Painter.Free;
  end;
  Assert.AreEqual(Before, Integer(FFake.Requests.Count), 'no new request for the failed tiles');

  FController.ZoomIn;
  Assert.IsNotNull(FindTiles(0, TPdfJobPriority.Visible), 'a new scale is tried again');
end;

procedure TPdfPageViewControllerTests.TestCachesStayWithinTileBudget;
begin
  Start(10);
  FController.TileCacheBytes := OneMebibyte;

  for var Step := 1 to 40 do
  begin
    FController.ScrollBy(0, 300);
    CompleteOpenTileRequests;
    Assert.IsTrue(FController.TileCacheCost <= OneMebibyte, Format('cost %d at step %d', [FController.TileCacheCost, Step]));
  end;
  Assert.IsTrue(FController.TileCacheCost > 0);
end;

procedure TPdfPageViewControllerTests.TestAttachToOpenDocumentUsesItsCurrentPage;
begin
  OpenPages([LetterPage(0), LetterPage(0), LetterPage(0)]);
  FDocument.CurrentPage := 2;

  FController := TPdfPageViewController.Create(FHostReference);
  FController.Zoom := 1;
  FController.SetViewport(TSize.Create(ViewportWidth, ViewportHeight), 96);
  FController.Document := FDocument;

  Assert.AreEqual(Gap + 2 * (PageHeight + Gap) - Gap, FController.ScrollPosition.Y);
  Assert.AreEqual(2, FDocument.CurrentPage);
  Assert.IsNotNull(FindTiles(2, TPdfJobPriority.Visible));
end;

procedure TPdfPageViewControllerTests.TestClosingTheDocumentEmptiesTheView;
begin
  Start(3);

  FDocument.Close;

  Assert.AreEqual(0, Integer(FController.ContentSize.cx));
  Assert.AreEqual(0, Integer(FController.ContentSize.cy));
  const Painter = Painted;
  try
    Assert.AreEqual(1, Integer(Painter.Calls.Count), 'the background only');
  finally
    Painter.Free;
  end;
end;

procedure TPdfPageViewControllerTests.TestSearchHitsArePainted;
begin
  Start(3);
  FDocument.Search('2024', True);
  const SearchIndex = FindSearchRequestIndex;
  Assert.IsTrue(SearchIndex >= 0);

  var First: TPdfSearchHit;
  First.PageIndex := 0;
  First.Text := '2024';
  First.Quads := [Square];
  var Second := First;
  Second.PageIndex := 1;
  FFake.DeliverHits(SearchIndex, [First, Second]);

  const Painter = Painted;
  try
    const Polygons = Painter.Of_(TPaintKind.FillPolygon);
    Assert.AreEqual(1, Integer(Length(Polygons)), 'only page 0 is in view');
    Assert.AreEqual(Cardinal(DefaultCurrentSearchHitColor), Cardinal(Polygons[0].Color), 'the first hit is the current one');
  finally
    Painter.Free;
  end;
end;

procedure TPdfPageViewControllerTests.TestNarrowPageIsCentred;
begin
  Start(3);

  FController.Zoom := 0.5;
  const Painter = Painted;
  try
    const Pages = Painter.Of_(TPaintKind.FillRect);
    // Background, then the first page: 408 wide and centred in 832 together with its gaps
    Assert.IsTrue(Length(Pages) > 1);
    Assert.AreEqual(Double((ViewportWidth - PageWidth div 2) div 2), Double(Pages[1].Rect.Left), 1.0);
  finally
    Painter.Free;
  end;
end;

procedure TPdfPageViewControllerTests.TestViewportToPageUsesTheScroll;
begin
  Start(3);
  FController.ScrollTo(TPoint.Create(0, 1100));

  var PageIndex: Integer;
  var PagePoint: TPointF;
  // Page 1 starts at y = 1072 in the content, which is -28 in the viewport
  const Point = TPointF.Create(Gap + 100 * Scale96, 1072 - 1100 + (792 - 700) * Scale96);
  Assert.IsTrue(FController.ViewportToPage(Point, PageIndex, PagePoint));
  Assert.AreEqual(1, PageIndex);
  Assert.AreEqual(100.0, Double(PagePoint.X), 1.0);
  Assert.AreEqual(700.0, Double(PagePoint.Y), 1.0);
  Assert.IsFalse(FController.ViewportToPage(TPointF.Create(1, 1), PageIndex, PagePoint), 'the margin is no page');
end;

procedure TPdfPageViewControllerTests.TestSinglePageShowsOnlyTheCurrentPage;
begin
  Start(3);

  FController.ScrollMode := TPdfScrollMode.SinglePage;
  FDocument.CurrentPage := 1;

  Assert.AreEqual(PageHeight + 2 * Gap, Integer(FController.ContentSize.cy));
  Assert.AreEqual(0, FController.ScrollPosition.Y);
  Assert.IsNotNull(FindTiles(1, TPdfJobPriority.Visible));
  Assert.AreEqual(1, FDocument.CurrentPage);
end;

procedure TPdfPageViewControllerTests.TestScrollModeBackToContinuousScrollsToCurrentPage;
begin
  Start(3);
  FController.ScrollMode := TPdfScrollMode.SinglePage;
  FDocument.CurrentPage := 2;

  FController.ScrollMode := TPdfScrollMode.Continuous;

  Assert.AreEqual(Gap + 2 * (PageHeight + Gap) - Gap, FController.ScrollPosition.Y);
  Assert.AreEqual(2, FDocument.CurrentPage);
end;

end.
