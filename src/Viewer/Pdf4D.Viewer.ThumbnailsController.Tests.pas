// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.ThumbnailsController.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.Session,
  Pdf4D.Viewer.ThumbnailsController,
  Pdf4D.Viewer.Painter.Interfaces,
  Pdf4D.Tests.TestDocument,
  Pdf4D.Tests.FakeSession,
  Pdf4D.Tests.RecordingPainter;

type
  [TestFixture]
  TPdfThumbnailsControllerTests = class
  private
    FFake: TFakeViewerSession;
    FSession: IPdfViewerSession;
    FDocument: TTestDocument;
    FHost: TRecordingHost;
    FHostReference: IPdfViewHost;
    FController: TPdfThumbnailsController;

    class function LetterPage(const Rotation: Integer; const PageLabel: string): TPdfPageInfo; static;
    procedure OpenPages(const Pages: TArray<TPdfPageInfo>);
    // Opens PageCount Letter pages without labels and shows them in a viewport that holds four cells exactly, at 96 PPI
    procedure Start(const PageCount: Integer);
    procedure StartWith(const Pages: TArray<TPdfPageInfo>);
    function Painted: TRecordingPainter;
    function RenderRequests: TArray<TFakeRequest>;
    function OpenRenderRequests: TArray<TFakeRequest>;
    function CountRequestsOfPage(const PageIndex: Integer): Integer;
    function IndexOfOpenRender(const PageIndex: Integer): Integer;
    // The top of the thumbnail of a page in the content at 96 PPI
    class function ThumbTop(const PageIndex: Integer): Integer; static;

  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestLayoutOfThreePages;
    [Test]
    procedure TestLayoutOfARotatedPage;
    [Test]
    procedure TestOnlyVisibleThumbnailsAreRendered;
    [Test]
    procedure TestCompletedThumbnailIsPainted;
    [Test]
    procedure TestCachedThumbnailIsNotRequestedAgain;
    [Test]
    procedure TestRenderFailureLeavesPageWhiteAndIsNotRepeated;
    [Test]
    procedure TestCurrentPageIsFramed;
    [Test]
    procedure TestClickSetsCurrentPage;
    [Test]
    procedure TestLabelsAreDrawn;
    [Test]
    procedure TestPageNumbersAreDrawnWithoutLabels;
    [Test]
    procedure TestScrollCancelsInvisible;
    [Test]
    procedure TestCurrentPageChangeScrollsIntoView;
    [Test]
    procedure TestPixelsPerInchChangeRerendersAtTheNewWidth;
    [Test]
    procedure TestCacheStaysWithinBudget;
    [Test]
    procedure TestClosingTheDocumentEmptiesTheView;
    [Test]
    procedure TestExtremelyTallPageGetsAThumbnailThatFitsTheCache;
    [Test]
    procedure TestThumbnailLargerThanTheCacheIsShrunk;
    [Test]
    procedure TestManyTallPagesKeepAPositiveLayout;
    [Test]
    procedure TestLayoutIsClampedBelowTheLargestInteger;
  end;

implementation

uses
  System.Math,
  System.UITypes,
  System.Generics.Collections,
  Pdf4D.Model.Rectangle;

const
  // Four cells exactly: the gap, then four times the thumbnail, the label and the gap
  CellHeight = 155 + 20 + 8;
  // The column and a gap on each side: a wider viewport would centre it
  ViewportWidth = 120 + 2 * 8;
  ViewportHeight = 8 + 4 * CellHeight;
  ThumbnailWidthPixels = 120;
  OneKibibyte = 1024;

{ TPdfThumbnailsControllerTests }

procedure TPdfThumbnailsControllerTests.Setup;
begin
  FFake := TFakeViewerSession.Create;
  FSession := FFake;
  FDocument := TTestDocument.Create(nil);
  FHost := TRecordingHost.Create;
  FHostReference := FHost;
end;

procedure TPdfThumbnailsControllerTests.TearDown;
begin
  FController.Free;
  FController := nil;
  FDocument.Free;
  FSession := nil;
  FHostReference := nil;
end;

class function TPdfThumbnailsControllerTests.LetterPage(const Rotation: Integer; const PageLabel: string): TPdfPageInfo;
begin
  Result.CropBox := TPdfRectangle.Letter;
  Result.Rotation := Rotation;
  Result.Label_ := PageLabel;
end;

class function TPdfThumbnailsControllerTests.ThumbTop(const PageIndex: Integer): Integer;
begin
  Result := 8 + PageIndex * CellHeight;
end;

procedure TPdfThumbnailsControllerTests.OpenPages(const Pages: TArray<TPdfPageInfo>);
begin
  var Permissions: TPdfViewerPermissions;
  Permissions.CanPrint := True;
  Permissions.CanCopy := True;
  FFake.SetOpened(Pages, nil, Permissions);
  FDocument.OpenWithSession(FSession);
end;

procedure TPdfThumbnailsControllerTests.StartWith(const Pages: TArray<TPdfPageInfo>);
begin
  OpenPages(Pages);
  FController := TPdfThumbnailsController.Create(FHostReference);
  FController.Document := FDocument;
  FController.SetViewport(TSize.Create(ViewportWidth, ViewportHeight), 96);
end;

procedure TPdfThumbnailsControllerTests.Start(const PageCount: Integer);
begin
  const Pages = TList<TPdfPageInfo>.Create;
  try
    for var Index := 1 to PageCount do
    begin
      Pages.Add(LetterPage(0, ''));
    end;
    StartWith(Pages.ToArray);
  finally
    Pages.Free;
  end;
end;

function TPdfThumbnailsControllerTests.Painted: TRecordingPainter;
begin
  const Painter = TRecordingPainter.Create;
  const Reference: IPdfViewPainter = Painter;
  FController.Paint(Reference, TRect.Create(0, 0, ViewportWidth, ViewportHeight));
  // The calls stay valid after the painter is released by the caller: copy them into a painter that lives on
  Result := TRecordingPainter.Create;
  Result.Calls.AddRange(Painter.Calls);
end;

function TPdfThumbnailsControllerTests.RenderRequests: TArray<TFakeRequest>;
begin
  const Found = TList<TFakeRequest>.Create;
  try
    for var Request in FFake.Requests do
    begin
      if Request.Kind = TFakeRequestKind.Render then
      begin
        Found.Add(Request);
      end;
    end;
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

// The renders that are neither cancelled nor completed
function TPdfThumbnailsControllerTests.OpenRenderRequests: TArray<TFakeRequest>;
begin
  const Found = TList<TFakeRequest>.Create;
  try
    for var Request in RenderRequests do
    begin
      if not Request.IsDone then
      begin
        Found.Add(Request);
      end;
    end;
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

function TPdfThumbnailsControllerTests.CountRequestsOfPage(const PageIndex: Integer): Integer;
begin
  Result := 0;
  for var Request in RenderRequests do
  begin
    if Request.PageIndex = PageIndex then
    begin
      Inc(Result);
    end;
  end;
end;

// The index in FFake.Requests of the render of a page that is still open; -1 when there is none
function TPdfThumbnailsControllerTests.IndexOfOpenRender(const PageIndex: Integer): Integer;
begin
  Result := -1;
  for var Index := 0 to FFake.Requests.Count - 1 do
  begin
    const Request = FFake.Requests[Index];
    if (Request.Kind = TFakeRequestKind.Render) and (Request.PageIndex = PageIndex) and (not Request.IsDone) then
    begin
      Result := Index;
    end;
  end;
end;

procedure TPdfThumbnailsControllerTests.TestLayoutOfThreePages;
begin
  Start(3);

  // The gap, then per page the thumbnail (a Letter page at a width of 120), the label of 20 and the gap of 8
  Assert.AreEqual(3 * (Round(120 * 792 / 612) + 20 + 8) + 8, Integer(FController.ContentSize.cy));
  Assert.AreEqual(ThumbnailWidthPixels + 2 * 8, Integer(FController.ContentSize.cx));
end;

procedure TPdfThumbnailsControllerTests.TestLayoutOfARotatedPage;
begin
  StartWith([LetterPage(90, '')]);

  // A page that is turned shows its height as its width: 792 x 612 points at a width of 120 is 120 x 92 pixels
  Assert.AreEqual(8 + (92 + 20 + 8), Integer(FController.ContentSize.cy));
  Assert.AreEqual(1, Integer(Length(RenderRequests)));
  Assert.AreEqual(ThumbnailWidthPixels, RenderRequests[0].Region.Width);
  Assert.AreEqual(92, RenderRequests[0].Region.Height);
end;

procedure TPdfThumbnailsControllerTests.TestOnlyVisibleThumbnailsAreRendered;
begin
  Start(100);

  const Requests = RenderRequests;
  Assert.AreEqual(4, Integer(Length(Requests)));
  for var Index := 0 to High(Requests) do
  begin
    const Request = Requests[Index];
    Assert.AreEqual(Integer(Index), Request.PageIndex);
    Assert.AreEqual(Ord(TPdfJobPriority.Thumbnail), Ord(Request.Priority));
    Assert.AreEqual(0, Request.ViewRotation);
    Assert.AreEqual(ThumbnailWidthPixels, Request.Region.Width, 'the width of the thumbnail');
    Assert.AreEqual(155, Request.Region.Height);
    Assert.AreEqual(Double(ThumbnailWidthPixels / 612), Double(Request.Scale), 0.00001);
  end;
  // Nothing else is asked for: no text, no prefetch
  Assert.AreEqual(4, Integer(FFake.Requests.Count));
  Assert.AreEqual(4, Integer(Length(OpenRenderRequests)));
end;

procedure TPdfThumbnailsControllerTests.TestCompletedThumbnailIsPainted;
begin
  Start(100);
  FHost.Reset;

  FFake.CompleteRender(IndexOfOpenRender(0), TAlphaColors.Red);
  const Painter = Painted;
  try
    const Images = Painter.Of_(TPaintKind.DrawImage);
    Assert.AreEqual(1, Integer(Length(Images)));
    Assert.AreEqual(8, Integer(Round(Images[0].Rect.Left)));
    Assert.AreEqual(8, Integer(Round(Images[0].Rect.Top)));
    Assert.AreEqual(ThumbnailWidthPixels, Integer(Round(Images[0].Rect.Width)));
    Assert.AreEqual(155, Integer(Round(Images[0].Rect.Height)));
    Assert.IsTrue(FHost.Covers(TRect.Create(8, 8, 8 + ThumbnailWidthPixels, 8 + 155)), 'the thumbnail was invalidated');
  finally
    Painter.Free;
  end;
end;

procedure TPdfThumbnailsControllerTests.TestCachedThumbnailIsNotRequestedAgain;
begin
  Start(100);
  FFake.CompleteRender(IndexOfOpenRender(0), TAlphaColors.Red);

  FController.ScrollTo(TPoint.Create(0, 20 * CellHeight));
  FController.ScrollTo(TPoint.Zero);

  Assert.AreEqual(1, CountRequestsOfPage(0), 'the thumbnail came from the cache');
  Assert.AreEqual(2, CountRequestsOfPage(1), 'a thumbnail that never arrived is asked for again');
end;

procedure TPdfThumbnailsControllerTests.TestRenderFailureLeavesPageWhiteAndIsNotRepeated;
begin
  Start(100);

  FFake.FailRender(IndexOfOpenRender(0), 'Injected failure');
  const Before = Integer(FFake.Requests.Count);
  // The view is refreshed without a change of what is in it
  FController.SetViewport(TSize.Create(ViewportWidth, ViewportHeight), 96);

  Assert.AreEqual(1, CountRequestsOfPage(0));
  Assert.AreEqual(Before, Integer(FFake.Requests.Count), 'nothing new is needed');
  const Painter = Painted;
  try
    Assert.AreEqual(0, Painter.Count(TPaintKind.DrawImage));
    // The page is there: white, with its label
    Assert.IsTrue(Painter.Count(TPaintKind.FillRect) >= 2);
    Assert.IsTrue(Painter.Count(TPaintKind.DrawText) >= 1);
  finally
    Painter.Free;
  end;
end;

procedure TPdfThumbnailsControllerTests.TestCurrentPageIsFramed;
begin
  Start(3);
  FDocument.CurrentPage := 1;

  const Painter = Painted;
  try
    const Frames = Painter.Of_(TPaintKind.FramePolygon);
    Assert.AreEqual(1, Integer(Length(Frames)));
    Assert.AreEqual(Cardinal(DefaultSelectedColor), Cardinal(Frames[0].Color));
    Assert.AreEqual(4, Integer(Length(Frames[0].Points)));
    Assert.AreEqual(2.0, Double(Frames[0].Width), 0.001);

    var Bounds := TRectF.Create(Frames[0].Points[0], Frames[0].Points[0]);
    for var Point in Frames[0].Points do
    begin
      Bounds.Left := Min(Bounds.Left, Point.X);
      Bounds.Top := Min(Bounds.Top, Point.Y);
      Bounds.Right := Max(Bounds.Right, Point.X);
      Bounds.Bottom := Max(Bounds.Bottom, Point.Y);
    end;
    // Around the thumbnail of page 1, on the line that is half the width outside of it
    Assert.AreEqual(Double(8 - 1), Double(Bounds.Left), 0.001);
    Assert.AreEqual(Double(ThumbTop(1) - 1), Double(Bounds.Top), 0.001);
    Assert.AreEqual(Double(8 + ThumbnailWidthPixels + 1), Double(Bounds.Right), 0.001);
    Assert.AreEqual(Double(ThumbTop(1) + 155 + 1), Double(Bounds.Bottom), 0.001);
  finally
    Painter.Free;
  end;
end;

procedure TPdfThumbnailsControllerTests.TestClickSetsCurrentPage;
begin
  Start(3);
  Assert.AreEqual(0, FDocument.CurrentPage);

  FController.Click(TPointF.Create(50, ThumbTop(1) + 10));
  Assert.AreEqual(1, FDocument.CurrentPage, 'on the thumbnail');

  FController.Click(TPointF.Create(50, ThumbTop(2) + 155 + 10));
  Assert.AreEqual(2, FDocument.CurrentPage, 'on the label');

  FController.Click(TPointF.Create(50, ThumbTop(1) - 4));
  Assert.AreEqual(2, FDocument.CurrentPage, 'in the gap');

  FController.Click(TPointF.Create(2, ThumbTop(0) + 10));
  Assert.AreEqual(2, FDocument.CurrentPage, 'beside the column');

  FController.Click(TPointF.Create(50, ThumbTop(3) + 10));
  Assert.AreEqual(2, FDocument.CurrentPage, 'below the last page');
end;

procedure TPdfThumbnailsControllerTests.TestLabelsAreDrawn;
begin
  StartWith([LetterPage(0, 'i'), LetterPage(0, 'ii'), LetterPage(0, 'iii')]);

  const Painter = Painted;
  try
    const Texts = Painter.Of_(TPaintKind.DrawText);
    Assert.AreEqual(3, Integer(Length(Texts)));
    Assert.AreEqual('i', Texts[0].Text);
    Assert.AreEqual('ii', Texts[1].Text);
    Assert.AreEqual('iii', Texts[2].Text);
    // Under its thumbnail, 20 pixels high
    Assert.AreEqual(Double(ThumbTop(1) + 155), Double(Texts[1].Rect.Top), 0.001);
    Assert.AreEqual(20.0, Double(Texts[1].Rect.Height), 0.001);
  finally
    Painter.Free;
  end;
end;

procedure TPdfThumbnailsControllerTests.TestPageNumbersAreDrawnWithoutLabels;
begin
  Start(3);

  const Painter = Painted;
  try
    const Texts = Painter.Of_(TPaintKind.DrawText);
    Assert.AreEqual(3, Integer(Length(Texts)));
    Assert.AreEqual('1', Texts[0].Text);
    Assert.AreEqual('3', Texts[2].Text);
  finally
    Painter.Free;
  end;
end;

procedure TPdfThumbnailsControllerTests.TestScrollCancelsInvisible;
begin
  Start(100);
  Assert.AreEqual(4, Integer(Length(OpenRenderRequests)));

  FController.ScrollTo(TPoint.Create(0, 50 * CellHeight));

  // The first four are cancelled before they were rendered, and the thumbnails in view are asked for
  Assert.AreEqual(4, Integer(Length(OpenRenderRequests)));
  for var Request in OpenRenderRequests do
  begin
    Assert.IsTrue(Request.PageIndex >= 49, 'a page in view');
    Assert.IsTrue(Request.PageIndex <= 54, 'a page in view');
  end;
  for var Index := 0 to 3 do
  begin
    for var Request in RenderRequests do
    begin
      if Request.PageIndex = Index then
      begin
        Assert.IsTrue(Request.Cancelled);
      end;
    end;
  end;
end;

procedure TPdfThumbnailsControllerTests.TestCurrentPageChangeScrollsIntoView;
begin
  Start(100);

  FDocument.CurrentPage := 80;

  // Its cell, with the gap around it, is in view: the bottom of the cell is at the bottom of the viewport
  const Position = FController.ScrollPosition;
  Assert.AreEqual(ThumbTop(80) + 155 + 20 + 8 - ViewportHeight, Position.Y);
  var PageIndex: Integer;
  Assert.IsTrue(FController.TryFindPageAt(TPointF.Create(50, ThumbTop(80) - Position.Y + 10), PageIndex));
  Assert.AreEqual(80, PageIndex);
  Assert.IsTrue(IndexOfOpenRender(80) >= 0, 'the thumbnail of the page is asked for');

  // Going back shows the top of the cell
  FDocument.CurrentPage := 2;
  Assert.AreEqual(ThumbTop(2) - 8, FController.ScrollPosition.Y);
end;

procedure TPdfThumbnailsControllerTests.TestPixelsPerInchChangeRerendersAtTheNewWidth;
begin
  Start(100);
  const Before = Integer(Length(RenderRequests));

  FController.SetViewport(TSize.Create(ViewportWidth, ViewportHeight), 144);

  // 180 pixels wide: 120 logical pixels at 144 PPI
  Assert.AreEqual(ThumbnailWidthPixels * 3 div 2 + 2 * 12, Integer(FController.ContentSize.cx));
  const Open = OpenRenderRequests;
  Assert.IsTrue(Length(Open) > 0);
  Assert.IsTrue(Integer(Length(RenderRequests)) > Before);
  for var Request in Open do
  begin
    Assert.AreEqual(180, Request.Region.Width);
    Assert.AreEqual(Double(180 / 612), Double(Request.Scale), 0.00001);
  end;
end;

procedure TPdfThumbnailsControllerTests.TestCacheStaysWithinBudget;
begin
  Start(100);
  // What a thumbnail of 120 x 155 takes is 74400 bytes: room for two
  FController.CacheBytes := 2 * 120 * 155 * 4 + OneKibibyte;

  for var Page := 0 to 3 do
  begin
    FFake.CompleteRender(IndexOfOpenRender(Page), TAlphaColors.Red);
  end;

  Assert.IsTrue(FController.CacheCost <= FController.CacheBytes);
  Assert.AreEqual(Int64(2 * 120 * 155 * 4), FController.CacheCost);
end;

procedure TPdfThumbnailsControllerTests.TestExtremelyTallPageGetsAThumbnailThatFitsTheCache;
begin
  var Page := LetterPage(0, '');
  Page.CropBox := TPdfRectangle.Letter;
  Page.CropBox.UpperRightX := 1;
  Page.CropBox.UpperRightY := 1000;
  StartWith([Page]);

  const Requests = OpenRenderRequests;
  Assert.AreEqual(1, Integer(Length(Requests)));
  const Pixels = Int64(Requests[0].Region.Width) * Requests[0].Region.Height;
  Assert.IsTrue(Pixels <= MaxTileBatchPixels, 'one render stays within the budget of a batch');
  Assert.IsTrue(Pixels * 4 <= FController.CacheBytes, 'one thumbnail fits the cache');
  FFake.CompleteRender(IndexOfOpenRender(0), TAlphaColors.Red);

  Assert.IsTrue(FController.CacheCost > 0, 'the thumbnail is kept');
  Assert.AreEqual(1, CountRequestsOfPage(0));
end;

procedure TPdfThumbnailsControllerTests.TestThumbnailLargerThanTheCacheIsShrunk;
begin
  StartWith([LetterPage(0, '')]);
  // A Letter thumbnail of 120 x 155 takes 74400 bytes
  FController.CacheBytes := 40 * OneKibibyte;

  const Requests = OpenRenderRequests;
  Assert.AreEqual(1, Integer(Length(Requests)));
  FFake.CompleteRender(IndexOfOpenRender(0), TAlphaColors.Red);

  Assert.IsTrue(FController.CacheCost > 0, 'the thumbnail is kept');
  Assert.IsTrue(FController.CacheCost <= FController.CacheBytes);
end;

procedure TPdfThumbnailsControllerTests.TestManyTallPagesKeepAPositiveLayout;
begin
  var Page := LetterPage(0, '');
  Page.CropBox := TPdfRectangle.Letter;
  Page.CropBox.UpperRightX := 1;
  Page.CropBox.UpperRightY := 14400;
  const Pages = TList<TPdfPageInfo>.Create;
  try
    // 30000 thumbnails of the largest size that a page may have would add up beyond an Integer
    for var Index := 1 to 30000 do
    begin
      Pages.Add(Page);
    end;
    StartWith(Pages.ToArray);
  finally
    Pages.Free;
  end;

  Assert.IsTrue(FController.ContentSize.cy > 30000 * (20 + 8));
  FController.ScrollTo(TPoint.Create(0, FController.ContentSize.cy));
  Assert.IsTrue(FController.ScrollPosition.Y > 0);
  const Requests = OpenRenderRequests;
  Assert.IsTrue(Length(Requests) > 0);
end;

procedure TPdfThumbnailsControllerTests.TestLayoutIsClampedBelowTheLargestInteger;
begin
  var Page := LetterPage(0, '');
  Page.CropBox := TPdfRectangle.Letter;
  Page.CropBox.UpperRightX := 1;
  Page.CropBox.UpperRightY := 14400;
  const Pages = TList<TPdfPageInfo>.Create;
  try
    // With wide thumbnails (a cell is about 5600 px high) the sum of the cells goes far beyond the largest Integer: the cap of
    // 4 x the width alone does not keep it below that, only the clamp of the sum does
    for var Index := 1 to 400000 do
    begin
      Pages.Add(Page);
    end;
    StartWith(Pages.ToArray);
  finally
    Pages.Free;
  end;
  FController.CacheBytes := 256 * OneKibibyte * OneKibibyte;
  FController.ThumbnailWidth := 1400;

  Assert.AreEqual(High(Integer) div 4, Integer(FController.ContentSize.cy), 'the layout is clamped');
  FController.ScrollTo(TPoint.Create(0, FController.ContentSize.cy));
  Assert.IsTrue(FController.ScrollPosition.Y > 0, 'the end of the clamped layout can be scrolled to');
end;

procedure TPdfThumbnailsControllerTests.TestClosingTheDocumentEmptiesTheView;
begin
  Start(100);

  FDocument.Close;

  Assert.AreEqual(0, Integer(FController.ContentSize.cx));
  Assert.AreEqual(0, Integer(FController.ContentSize.cy));
  Assert.AreEqual(0, Integer(Length(OpenRenderRequests)), 'the renders were cancelled');
  const Painter = Painted;
  try
    Assert.AreEqual(1, Integer(Painter.Calls.Count), 'the background only');
  finally
    Painter.Free;
  end;
end;

end.
