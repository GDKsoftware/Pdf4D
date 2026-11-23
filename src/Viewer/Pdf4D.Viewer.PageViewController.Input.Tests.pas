// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.PageViewController.Input.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.Types,
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Api.Page.Interfaces,
  Pdf4D.Api.TextLayout.Interfaces,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.PageText,
  Pdf4D.Viewer.Session,
  Pdf4D.Viewer.PageViewController,
  Pdf4D.Viewer.ViewTransform,
  Pdf4D.Viewer.Painter.Interfaces,
  Pdf4D.Tests.TestDocument,
  Pdf4D.Tests.FakeSession,
  Pdf4D.Tests.RecordingPainter;

type
  [TestFixture]
  TPdfPageViewControllerInputTests = class
  private
    FFake: TFakeViewerSession;
    FSession: IPdfViewerSession;
    FDocument: TTestDocument;
    FHost: TRecordingHost;
    FHostReference: IPdfViewHost;
    FController: TPdfPageViewController;
    FStreams: TObjectList<TStream>;
    FSelections: TList<TPdfTextSelection>;
    FHovers: TList<TPdfTextFragment>;
    FHoverFlags: TList<Boolean>;
    FLinks: TList<TPdfLink>;

    procedure HandleTextSelected(Sender: TObject; const Selection: TPdfTextSelection);
    procedure HandleHoverChanged(Sender: TObject; const HasSegment: Boolean; const Segment: TPdfTextFragment);
    procedure HandleLinkClick(Sender: TObject; const Link: TPdfLink);

    // Opens PageCount Letter pages in a viewport of 832 x 600 at 96 PPI and zoom 1
    procedure Start(const PageCount: Integer); overload;
    procedure Start(const PageCount, PageRotation: Integer); overload;
    // A point of the page as the viewer shows it, for a page that is centred in the viewport and starts one gap from its top
    class function RotatedViewPoint(const PdfX, PdfY: Single; const PageRotation, ViewRotation: Integer; const Zoom: Single): TPointF; static;
    function TextOf(const Data: TBytes; const PageIndex: Integer): IPdfPageText;
    procedure DeliverText(const PageIndex: Integer; const PageText: IPdfPageText);
    procedure DeliverInvoiceText;
    // The viewport point of a PDF point on page 0 of the unscrolled view
    class function ViewPoint(const PdfX, PdfY: Single): TPointF; static;
    procedure Click(const Point: TPointF);
    function Painted: TRecordingPainter;
    class function SameQuad(const Left, Right: TPdfQuad): Boolean; static;
    class function Square: TPdfQuad; static;

  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestHoverHighlightsSegment;
    [Test]
    procedure TestHoverIsSynchronous;
    [Test]
    procedure TestMovingWithinSegmentDoesNotRepaint;
    [Test]
    procedure TestLeavingTheSegmentClearsTheHover;
    [Test]
    procedure TestHoverWithoutPageTextDoesNothing;
    [Test]
    procedure TestHoverOnScannedPageDoesNothing;
    [Test]
    procedure TestHoverDisabled;
    [Test]
    procedure TestClickRaisesTextSelected;
    [Test]
    procedure TestClickBesideTextClearsTheSelection;
    [Test]
    procedure TestSelectionIsPaintedBelowTheHover;
    [Test]
    procedure TestDragSelectsWords;
    [Test]
    procedure TestDragAcrossLinesAndBeyondPage;
    [Test]
    procedure TestDragOnScannedPageSelectsNothing;
    [Test]
    procedure TestDragBeyondPageOnRotatedView;
    [Test]
    procedure TestDragBeyondPageOfARotatedPage;
    [Test]
    procedure TestDragBeyondTheSideOfAPageThatIsTurnedSideways;
    [Test]
    procedure TestClickOnLinkRaisesLinkAndNavigates;
    [Test]
    procedure TestUriLinkIsOnlyReported;
    [Test]
    procedure TestCursorKinds;
    [Test]
    procedure TestKeyboardNavigation;
    [Test]
    procedure TestWheelScrolls;
    [Test]
    procedure TestCtrlWheelZoomsAroundPoint;
    [Test]
    procedure TestCtrlWheelAccumulatesSmallDeltas;
    [Test]
    procedure TestScrollIntoView;
    [Test]
    procedure TestSelectAll;
  end;

implementation

uses
  System.Math,
  System.UITypes,
  Pdf4D.Model.Rectangle,
  Pdf4D.Common.Quad,
  Pdf4D.Api.Document,
  Pdf4D.Common.Defines,
  Pdf4D.Tests.ViewerDocuments;

const
  ViewportWidth = 832;
  ViewportHeight = 600;
  PageHeight = 1056;
  Gap = 8;
  Scale96 = 96 / 72;
  PageHeightPoints = 792;
  WheelNotch = 120;
  InvoiceNumber = '2024-0815';

{ TPdfPageViewControllerInputTests }

procedure TPdfPageViewControllerInputTests.Setup;
begin
  FFake := TFakeViewerSession.Create;
  FSession := FFake;
  FDocument := TTestDocument.Create(nil);
  FHost := TRecordingHost.Create;
  FHostReference := FHost;
  FStreams := TObjectList<TStream>.Create(True);
  FSelections := TList<TPdfTextSelection>.Create;
  FHovers := TList<TPdfTextFragment>.Create;
  FHoverFlags := TList<Boolean>.Create;
  FLinks := TList<TPdfLink>.Create;
end;

procedure TPdfPageViewControllerInputTests.TearDown;
begin
  FController.Free;
  FController := nil;
  FDocument.Free;
  FSession := nil;
  FHostReference := nil;
  FLinks.Free;
  FHoverFlags.Free;
  FHovers.Free;
  FSelections.Free;
  FStreams.Free;
end;

procedure TPdfPageViewControllerInputTests.HandleTextSelected(Sender: TObject; const Selection: TPdfTextSelection);
begin
  FSelections.Add(Selection);
end;

procedure TPdfPageViewControllerInputTests.HandleHoverChanged(Sender: TObject; const HasSegment: Boolean; const Segment: TPdfTextFragment);
begin
  FHoverFlags.Add(HasSegment);
  FHovers.Add(Segment);
end;

procedure TPdfPageViewControllerInputTests.HandleLinkClick(Sender: TObject; const Link: TPdfLink);
begin
  FLinks.Add(Link);
end;

procedure TPdfPageViewControllerInputTests.Start(const PageCount: Integer);
begin
  Start(PageCount, 0);
end;

procedure TPdfPageViewControllerInputTests.Start(const PageCount, PageRotation: Integer);
begin
  var Pages: TArray<TPdfPageInfo>;
  SetLength(Pages, PageCount);
  for var Index := 0 to PageCount - 1 do
  begin
    Pages[Index].CropBox := TPdfRectangle.Letter;
    Pages[Index].Rotation := PageRotation;
    Pages[Index].Label_ := '';
  end;

  var Permissions: TPdfViewerPermissions;
  Permissions.CanPrint := True;
  Permissions.CanCopy := True;
  FFake.SetOpened(Pages, nil, Permissions);
  FDocument.OpenWithSession(FSession);

  FController := TPdfPageViewController.Create(FHostReference);
  FController.OnTextSelected := HandleTextSelected;
  FController.OnHoverChanged := HandleHoverChanged;
  FController.OnLinkClick := HandleLinkClick;
  FController.Document := FDocument;
  FController.Zoom := 1;
  FController.SetViewport(TSize.Create(ViewportWidth, ViewportHeight), 96);
end;

function TPdfPageViewControllerInputTests.TextOf(const Data: TBytes; const PageIndex: Integer): IPdfPageText;
begin
  const Stream = TBytesStream.Create(Data);
  FStreams.Add(Stream);

  const Page = TPdfDocument.Load(Stream, TPdfLoadOptions.Default).Page(PageIndex);
  Result := TPdfPageText.Create(Page.TextLayout, Page.Links);
end;

procedure TPdfPageViewControllerInputTests.DeliverText(const PageIndex: Integer; const PageText: IPdfPageText);
begin
  for var Index := 0 to FFake.Requests.Count - 1 do
  begin
    const Request = FFake.Requests[Index];
    const IsOpenTextRequest = (Request.Kind = TFakeRequestKind.PageText) and (Request.PageIndex = PageIndex) and (not Request.IsDone);
    if IsOpenTextRequest then
    begin
      FFake.CompletePageText(Index, PageText);
    end;
  end;
end;

procedure TPdfPageViewControllerInputTests.DeliverInvoiceText;
begin
  DeliverText(0, TextOf(TViewerDocuments.Invoice, 0));
end;

class function TPdfPageViewControllerInputTests.RotatedViewPoint(const PdfX, PdfY: Single; const PageRotation, ViewRotation: Integer;
                                                                 const Zoom: Single): TPointF;
begin
  var Page: TPdfPageInfo;
  Page.CropBox := TPdfRectangle.Letter;
  Page.Rotation := PageRotation;
  const Transform = TPdfViewTransform.Create(Page, ViewRotation, Zoom, 96);

  const Left = Max(Gap, (ViewportWidth - Transform.Size.cx) div 2);
  const OnPage = Transform.PageToView(TPointF.Create(PdfX, PdfY));
  Result := TPointF.Create(Left + OnPage.X, Gap + OnPage.Y);
end;

class function TPdfPageViewControllerInputTests.ViewPoint(const PdfX, PdfY: Single): TPointF;
begin
  Result := TPointF.Create(Gap + PdfX * Scale96, Gap + (PageHeightPoints - PdfY) * Scale96);
end;

procedure TPdfPageViewControllerInputTests.Click(const Point: TPointF);
begin
  FController.MouseDown(Point);
  FController.MouseUp(Point);
end;

function TPdfPageViewControllerInputTests.Painted: TRecordingPainter;
begin
  const Painter = TRecordingPainter.Create;
  const Reference: IPdfViewPainter = Painter;
  FController.Paint(Reference, TRect.Create(0, 0, ViewportWidth, ViewportHeight));
  Result := TRecordingPainter.Create;
  Result.Calls.AddRange(Painter.Calls);
end;

class function TPdfPageViewControllerInputTests.SameQuad(const Left, Right: TPdfQuad): Boolean;
begin
  Result := (Left.P1 = Right.P1) and (Left.P2 = Right.P2) and (Left.P3 = Right.P3) and (Left.P4 = Right.P4);
end;

class function TPdfPageViewControllerInputTests.Square: TPdfQuad;
begin
  Result := TPdfQuad.Create(TPointF.Create(100, 700), TPointF.Create(160, 700), TPointF.Create(160, 712), TPointF.Create(100, 712));
end;

procedure TPdfPageViewControllerInputTests.TestHoverHighlightsSegment;
begin
  Start(2);
  DeliverInvoiceText;
  const RequestsBefore = Integer(FFake.Requests.Count);

  FController.MouseMove(ViewPoint(160, 683));

  var Segment: TPdfTextFragment;
  Assert.IsTrue(FController.TryGetHoverSegment(Segment));
  Assert.AreEqual(InvoiceNumber, Segment.Text);
  Assert.AreEqual(1, Integer(FHovers.Count));
  Assert.IsTrue(FHoverFlags[0]);
  Assert.AreEqual(InvoiceNumber, FHovers[0].Text);
  Assert.AreEqual(RequestsBefore, Integer(FFake.Requests.Count), 'no request from MouseMove');

  const Painter = Painted;
  try
    const Frames = Painter.Of_(TPaintKind.FramePolygon);
    Assert.AreEqual(1, Integer(Length(Frames)));
    Assert.AreEqual(Cardinal(DefaultHoverColor), Cardinal(Frames[0].Color));
    Assert.AreEqual(2.0, Double(Frames[0].Width), 0.0001);
  finally
    Painter.Free;
  end;
end;

procedure TPdfPageViewControllerInputTests.TestHoverIsSynchronous;
begin
  Start(2);
  DeliverInvoiceText;

  FController.MouseMove(ViewPoint(160, 683));

  var Segment: TPdfTextFragment;
  Assert.IsTrue(FController.TryGetHoverSegment(Segment), 'no dispatcher ran');
end;

procedure TPdfPageViewControllerInputTests.TestMovingWithinSegmentDoesNotRepaint;
begin
  Start(2);
  DeliverInvoiceText;
  FController.MouseMove(ViewPoint(160, 683));
  FHost.Reset;

  FController.MouseMove(ViewPoint(170, 684));

  Assert.AreEqual(0, Integer(FHost.Invalidated.Count));
  Assert.AreEqual(0, FHost.CursorChanges);
  Assert.AreEqual(1, Integer(FHovers.Count));
end;

procedure TPdfPageViewControllerInputTests.TestLeavingTheSegmentClearsTheHover;
begin
  Start(2);
  DeliverInvoiceText;
  FController.MouseMove(ViewPoint(160, 683));
  FHost.Reset;

  FController.MouseMove(ViewPoint(400, 300));

  var Segment: TPdfTextFragment;
  Assert.IsFalse(FController.TryGetHoverSegment(Segment));
  Assert.AreEqual(2, Integer(FHovers.Count));
  Assert.IsFalse(FHoverFlags[1]);
  Assert.IsTrue(FHost.Invalidated.Count > 0, 'the old frame is repainted');

  FController.MouseMove(ViewPoint(160, 683));
  FController.MouseLeave;
  Assert.IsFalse(FController.TryGetHoverSegment(Segment));
  Assert.AreEqual(4, Integer(FHovers.Count));
end;

procedure TPdfPageViewControllerInputTests.TestHoverWithoutPageTextDoesNothing;
begin
  Start(2);
  const RequestsBefore = Integer(FFake.Requests.Count);

  FController.MouseMove(ViewPoint(160, 683));

  var Segment: TPdfTextFragment;
  Assert.IsFalse(FController.TryGetHoverSegment(Segment));
  Assert.AreEqual(0, Integer(FHovers.Count));
  Assert.AreEqual(RequestsBefore, Integer(FFake.Requests.Count));
end;

procedure TPdfPageViewControllerInputTests.TestHoverOnScannedPageDoesNothing;
begin
  Start(1);
  DeliverText(0, TextOf(TViewerDocuments.Scanned, 0));

  FController.MouseMove(ViewPoint(300, 400));

  var Segment: TPdfTextFragment;
  Assert.IsFalse(FController.TryGetHoverSegment(Segment));
  Assert.AreEqual(0, Integer(FHovers.Count));
end;

procedure TPdfPageViewControllerInputTests.TestHoverDisabled;
begin
  Start(2);
  DeliverInvoiceText;
  FController.HoverEnabled := False;

  FController.MouseMove(ViewPoint(160, 683));

  var Segment: TPdfTextFragment;
  Assert.IsFalse(FController.TryGetHoverSegment(Segment));
  Assert.AreEqual(0, Integer(FHovers.Count));
end;

procedure TPdfPageViewControllerInputTests.TestClickRaisesTextSelected;
begin
  Start(2);
  DeliverInvoiceText;

  Click(ViewPoint(160, 683));

  Assert.AreEqual(1, Integer(FSelections.Count));
  Assert.AreEqual(Ord(TPdfSelectionKind.Click), Ord(FSelections[0].Kind));
  Assert.AreEqual(0, FSelections[0].PageIndex);
  Assert.AreEqual(InvoiceNumber, FSelections[0].Text);
  Assert.AreEqual(1, Integer(Length(FSelections[0].Quads)));

  var Segment: TPdfTextFragment;
  Assert.IsTrue(TextOf(TViewerDocuments.Invoice, 0).TryFindSegmentAt(TPointF.Create(160, 683), Segment));
  Assert.IsTrue(SameQuad(Segment.Quads[0], FSelections[0].Quads[0]));

  var Selection: TPdfTextSelection;
  Assert.IsTrue(FController.TryGetSelection(Selection));
  Assert.AreEqual(InvoiceNumber, Selection.Text);
end;

procedure TPdfPageViewControllerInputTests.TestClickBesideTextClearsTheSelection;
begin
  Start(2);
  DeliverInvoiceText;
  Click(ViewPoint(160, 683));

  Click(ViewPoint(400, 300));

  var Selection: TPdfTextSelection;
  Assert.IsFalse(FController.TryGetSelection(Selection));
  Assert.AreEqual(1, Integer(FSelections.Count), 'clearing raises no event');
end;

procedure TPdfPageViewControllerInputTests.TestSelectionIsPaintedBelowTheHover;
begin
  Start(2);
  DeliverInvoiceText;
  FController.MouseMove(ViewPoint(160, 683));
  Click(ViewPoint(160, 683));

  const Painter = Painted;
  try
    var FillIndex := -1;
    var FrameIndex := -1;
    for var Index := 0 to Painter.Calls.Count - 1 do
    begin
      const Call = Painter.Calls[Index];
      if (Call.Kind = TPaintKind.FillPolygon) and (Call.Color = DefaultSelectionColor) then
      begin
        FillIndex := Index;
      end;
      if (Call.Kind = TPaintKind.FramePolygon) and (Call.Color = DefaultHoverColor) then
      begin
        FrameIndex := Index;
      end;
    end;
    Assert.IsTrue(FillIndex >= 0, 'the selection is painted');
    Assert.IsTrue(FrameIndex > FillIndex, 'the hover frame is on top');
  finally
    Painter.Free;
  end;
end;

procedure TPdfPageViewControllerInputTests.TestDragSelectsWords;
begin
  Start(2);
  DeliverInvoiceText;

  FController.MouseDown(ViewPoint(110, 683));
  FController.MouseMove(ViewPoint(160, 683));

  var Selection: TPdfTextSelection;
  Assert.IsTrue(FController.TryGetSelection(Selection), 'the selection follows the pointer');
  Assert.AreEqual(0, Integer(FSelections.Count), 'no event before the button is released');
  FHost.Reset;
  const Painter = Painted;
  try
    Assert.IsTrue(Painter.Count(TPaintKind.FillPolygon) > 0);
  finally
    Painter.Free;
  end;

  FController.MouseUp(ViewPoint(160, 683));

  Assert.AreEqual(1, Integer(FSelections.Count));
  Assert.AreEqual(Ord(TPdfSelectionKind.Drag), Ord(FSelections[0].Kind));
  Assert.AreEqual('Nummer: ' + InvoiceNumber, FSelections[0].Text);
end;

procedure TPdfPageViewControllerInputTests.TestDragAcrossLinesAndBeyondPage;
begin
  Start(2);
  DeliverInvoiceText;

  FController.MouseDown(ViewPoint(110, 703));
  FController.MouseMove(TPointF.Create(300, Gap + PageHeight + 40));
  FController.MouseUp(TPointF.Create(300, Gap + PageHeight + 40));

  const PageText = TextOf(TViewerDocuments.Invoice, 0);
  const Expected = PageText.Select(0, Length(PageText.Words) - 1, TPdfSelectionKind.Drag);
  Assert.AreEqual(1, Integer(FSelections.Count));
  Assert.AreEqual(Expected.Text, FSelections[0].Text, 'the focus is clamped to the last word of the page');
  Assert.IsTrue(Pos(sLineBreak, FSelections[0].Text) > 0, 'it spans lines');
end;

procedure TPdfPageViewControllerInputTests.TestDragBeyondPageOnRotatedView;
begin
  Start(2);
  FController.ViewRotation := 180;
  // A new rotation keeps the same part of the page in view: the helper counts from the top of the content
  FController.ScrollTo(TPoint.Zero);
  DeliverInvoiceText;

  // Turned upside down, the bottom of the screen is the top of the page
  const Down = RotatedViewPoint(110, 703, 0, 180, 1);
  FController.MouseDown(Down);
  FController.MouseMove(TPointF.Create(300, Gap + PageHeight + 40));
  FController.MouseUp(TPointF.Create(300, Gap + PageHeight + 40));

  const PageText = TextOf(TViewerDocuments.Invoice, 0);
  var Anchor: Integer;
  Assert.IsTrue(PageText.TryFindWordAt(TPointF.Create(110, 703), Anchor) or PageText.TryFindNearestWord(TPointF.Create(110, 703), Anchor));
  Assert.AreEqual(1, Integer(FSelections.Count));
  Assert.AreEqual(PageText.Select(Anchor, 0, TPdfSelectionKind.Drag).Text, FSelections[0].Text, 'the focus is the first word of the page');
end;

procedure TPdfPageViewControllerInputTests.TestDragBeyondPageOfARotatedPage;
begin
  Start(2, 180);
  DeliverInvoiceText;

  const Down = RotatedViewPoint(110, 703, 180, 0, 1);
  FController.MouseDown(Down);
  FController.MouseMove(TPointF.Create(300, Gap + PageHeight + 40));
  FController.MouseUp(TPointF.Create(300, Gap + PageHeight + 40));

  const PageText = TextOf(TViewerDocuments.Invoice, 0);
  var Anchor: Integer;
  Assert.IsTrue(PageText.TryFindWordAt(TPointF.Create(110, 703), Anchor) or PageText.TryFindNearestWord(TPointF.Create(110, 703), Anchor));
  Assert.AreEqual(1, Integer(FSelections.Count));
  Assert.AreEqual(PageText.Select(Anchor, 0, TPdfSelectionKind.Drag).Text, FSelections[0].Text, 'the focus is the first word of the page');
end;

procedure TPdfPageViewControllerInputTests.TestDragBeyondTheSideOfAPageThatIsTurnedSideways;
begin
  Start(2);
  FController.Zoom := 0.5;
  FController.ViewRotation := 90;
  FController.ScrollTo(TPoint.Zero);
  DeliverInvoiceText;

  // Turned a quarter, the right of the screen is the top of the page: the pointer lies beyond it, level with the right of the page
  const Down = RotatedViewPoint(110, 703, 0, 90, 0.5);
  const Beyond = RotatedViewPoint(500, 900, 0, 90, 0.5);
  FController.MouseDown(Down);
  FController.MouseMove(Beyond);
  FController.MouseUp(Beyond);

  const PageText = TextOf(TViewerDocuments.Invoice, 0);
  var Anchor: Integer;
  Assert.IsTrue(PageText.TryFindWordAt(TPointF.Create(110, 703), Anchor) or PageText.TryFindNearestWord(TPointF.Create(110, 703), Anchor));
  Assert.AreEqual(1, Integer(FSelections.Count));
  Assert.AreEqual(PageText.Select(Anchor, 0, TPdfSelectionKind.Drag).Text, FSelections[0].Text, 'the focus is the first word of the page');
end;

procedure TPdfPageViewControllerInputTests.TestDragOnScannedPageSelectsNothing;
begin
  Start(1);
  DeliverText(0, TextOf(TViewerDocuments.Scanned, 0));

  FController.MouseDown(ViewPoint(300, 400));
  FController.MouseMove(ViewPoint(200, 300));
  FController.MouseUp(ViewPoint(200, 300));

  var Selection: TPdfTextSelection;
  Assert.IsFalse(FController.TryGetSelection(Selection));
  Assert.AreEqual(0, Integer(FSelections.Count));
end;

procedure TPdfPageViewControllerInputTests.TestClickOnLinkRaisesLinkAndNavigates;
begin
  Start(2);
  DeliverInvoiceText;

  Click(ViewPoint(150, 610));

  Assert.AreEqual(1, Integer(FLinks.Count));
  Assert.AreEqual(Ord(TPdfLinkKind.GoTo), Ord(FLinks[0].Kind));
  Assert.AreEqual(1, FLinks[0].TargetPageIndex);
  Assert.AreEqual(1, FDocument.CurrentPage);
  Assert.AreEqual(0, Integer(FSelections.Count));

  FDocument.CurrentPage := 0;
  FController.FollowInternalLinks := False;
  FController.ScrollTo(TPoint.Zero);
  Click(ViewPoint(150, 610));

  Assert.AreEqual(2, Integer(FLinks.Count));
  Assert.AreEqual(0, FDocument.CurrentPage, 'the event only');
end;

procedure TPdfPageViewControllerInputTests.TestUriLinkIsOnlyReported;
begin
  Start(2);
  DeliverInvoiceText;

  Click(ViewPoint(150, 570));

  Assert.AreEqual(1, Integer(FLinks.Count));
  Assert.AreEqual(Ord(TPdfLinkKind.Uri), Ord(FLinks[0].Kind));
  Assert.AreEqual('https://example.com/', FLinks[0].Uri);
  Assert.AreEqual(0, FDocument.CurrentPage);
end;

procedure TPdfPageViewControllerInputTests.TestCursorKinds;
begin
  Start(2);
  DeliverInvoiceText;
  Assert.AreEqual(Ord(TPdfCursorKind.Default), Ord(FController.CursorKind));
  FHost.Reset;

  FController.MouseMove(ViewPoint(160, 683));
  Assert.AreEqual(Ord(TPdfCursorKind.Text), Ord(FController.CursorKind));
  Assert.AreEqual(1, FHost.CursorChanges);

  FController.MouseMove(ViewPoint(170, 683));
  Assert.AreEqual(1, FHost.CursorChanges, 'no change, no notification');

  FController.MouseMove(ViewPoint(150, 610));
  Assert.AreEqual(Ord(TPdfCursorKind.Link), Ord(FController.CursorKind));
  Assert.AreEqual(2, FHost.CursorChanges);

  FController.MouseMove(ViewPoint(400, 300));
  Assert.AreEqual(Ord(TPdfCursorKind.Default), Ord(FController.CursorKind));
  Assert.AreEqual(3, FHost.CursorChanges);
end;

procedure TPdfPageViewControllerInputTests.TestKeyboardNavigation;
begin
  Start(3);

  Assert.IsTrue(FController.KeyDown(TPdfViewerKey.PageDown));
  Assert.AreEqual(ViewportHeight - 40, FController.ScrollPosition.Y);

  FController.KeyDown(TPdfViewerKey.Down);
  Assert.AreEqual(ViewportHeight, FController.ScrollPosition.Y);
  FController.KeyDown(TPdfViewerKey.Up);
  Assert.AreEqual(ViewportHeight - 40, FController.ScrollPosition.Y);

  FController.KeyDown(TPdfViewerKey.PageUp);
  Assert.AreEqual(0, FController.ScrollPosition.Y);

  FController.KeyDown(TPdfViewerKey.End_);
  Assert.AreEqual(FController.ContentSize.cy - ViewportHeight, FController.ScrollPosition.Y);

  FController.KeyDown(TPdfViewerKey.Home);
  Assert.AreEqual(0, FController.ScrollPosition.Y);

  FController.KeyDown(TPdfViewerKey.ZoomIn);
  Assert.AreEqual(1.25, Double(FController.Zoom), 0.0001);
  FController.KeyDown(TPdfViewerKey.ZoomOut);
  FController.KeyDown(TPdfViewerKey.ZoomOut);
  Assert.AreEqual(0.75, Double(FController.Zoom), 0.0001);
  FController.KeyDown(TPdfViewerKey.ZoomReset);
  Assert.AreEqual(1.0, Double(FController.Zoom), 0.0001);
end;

procedure TPdfPageViewControllerInputTests.TestWheelScrolls;
begin
  Start(3);

  FController.MouseWheel(-WheelNotch, False, TPointF.Create(100, 100));
  Assert.AreEqual(3 * 40, FController.ScrollPosition.Y);

  FController.MouseWheel(WheelNotch, False, TPointF.Create(100, 100));
  Assert.AreEqual(0, FController.ScrollPosition.Y);
end;

procedure TPdfPageViewControllerInputTests.TestCtrlWheelZoomsAroundPoint;
begin
  Start(3);
  const Point = TPointF.Create(300, 300);
  var PageIndex: Integer;
  var Before: TPointF;
  Assert.IsTrue(FController.ViewportToPage(Point, PageIndex, Before));

  FController.MouseWheel(WheelNotch, True, Point);

  Assert.AreEqual(1.25, Double(FController.Zoom), 0.0001);
  var After: TPointF;
  Assert.IsTrue(FController.ViewportToPage(Point, PageIndex, After));
  Assert.AreEqual(Double(Before.X), Double(After.X), 1 / (1.25 * Scale96));
  Assert.AreEqual(Double(Before.Y), Double(After.Y), 1 / (1.25 * Scale96));
end;

// A touchpad or a macOS wheel sends deltas far below one notch: they add up to a step, and a change of direction starts again
procedure TPdfPageViewControllerInputTests.TestCtrlWheelAccumulatesSmallDeltas;
begin
  Start(3);
  const Point = TPointF.Create(300, 300);
  const SmallDelta = WheelNotch div 8;

  for var Event := 1 to 7 do
  begin
    FController.MouseWheel(SmallDelta, True, Point);
  end;
  Assert.AreEqual(1.0, Double(FController.Zoom), 0.0001, 'seven eighths of a notch is not a step');

  FController.MouseWheel(SmallDelta, True, Point);
  Assert.AreEqual(1.25, Double(FController.Zoom), 0.0001, 'the eighth event completes the notch');

  // The other direction does not inherit what was left
  FController.MouseWheel(SmallDelta, True, Point);
  FController.MouseWheel(-SmallDelta, True, Point);
  for var Event := 1 to 6 do
  begin
    FController.MouseWheel(-SmallDelta, True, Point);
  end;
  Assert.AreEqual(1.25, Double(FController.Zoom), 0.0001, 'seven events of the new direction are not enough');

  FController.MouseWheel(-SmallDelta, True, Point);
  Assert.AreEqual(1.0, Double(FController.Zoom), 0.0001);

  // Larger deltas still take as many steps as they hold notches
  FController.MouseWheel(2 * WheelNotch, True, Point);
  Assert.AreEqual(1.5, Double(FController.Zoom), 0.0001);
end;

procedure TPdfPageViewControllerInputTests.TestScrollIntoView;
begin
  Start(3);

  FController.ScrollIntoView(0, [Square]);
  Assert.AreEqual(0, FController.ScrollPosition.Y, 'already in view');

  FController.ScrollIntoView(2, [Square]);

  const Expected = Gap + 2 * (PageHeight + Gap) + (PageHeightPoints - 706) * Scale96 - ViewportHeight / 2;
  Assert.AreEqual(Double(Expected), Double(FController.ScrollPosition.Y), 1.0, 'centred');

  const Before = FController.ScrollPosition;
  FController.ScrollIntoView(2, [Square]);
  Assert.AreEqual(Before.Y, FController.ScrollPosition.Y, 'in view now');
end;

procedure TPdfPageViewControllerInputTests.TestSelectAll;
begin
  Start(2);
  DeliverInvoiceText;

  Assert.IsTrue(FController.KeyDown(TPdfViewerKey.SelectAll));

  var Selection: TPdfTextSelection;
  Assert.IsTrue(FController.TryGetSelection(Selection));
  Assert.AreEqual(TextOf(TViewerDocuments.Invoice, 0).SelectAll.Text, Selection.Text);
  Assert.AreEqual(0, Integer(FSelections.Count), 'no event');
end;

end.
