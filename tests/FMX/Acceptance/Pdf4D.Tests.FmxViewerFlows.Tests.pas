// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.FmxViewerFlows.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.Generics.Collections,
  System.SysUtils,
  System.Types,
  System.UITypes,
  DUnitX.TestFramework,
  Pdf4D.Api.TextLayout.Interfaces,
  Pdf4D.Common.Quad,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.PageText,
  Pdf4D.Viewer.Print,
  Pdf4D.Tests.FlowEvents,
  Pdf4D.Tests.FmxHost,
  Pdf4D.FMX.PageView,
  Pdf4D.FMX.Viewer;

type
  // Gives the tests the mouse entry points of the control, as the window system calls them
  TPageViewCracker = class(TPdf4DPageView);

  [TestFixture]
  TFmxViewerFlowTests = class
  private
    FHost: TFmxTestHost;
    FViewer: TPdf4DViewer;
    FSelectedTexts: TList<string>;
    FHoverCount: Integer;
    FEvents: TFlowEventLog;
    FPrintStatus: TPdfPrintStatus;
    FPrintMessage: string;
    FIsPrinted: Boolean;

    procedure HandleTextSelected(Sender: TObject; const Selection: TPdfTextSelection);
    procedure HandleHoverChanged(Sender: TObject; const HasSegment: Boolean; const Segment: TPdfTextFragment);
    function TilesArrived: Boolean;
    function IsSearchEnded: Boolean;
    function IsPrintDone: Boolean;
    procedure HandlePrintDone(const Status: TPdfPrintStatus; const ErrorMessage: string);
    // The quads of an occurrence of a word on the first page, in PDF user space
    function QuadsOfWord(const Text: string; const Occurrence: Integer): TArray<TPdfQuad>;
    // The logical position (in the form) of the middle of an occurrence of a word on the first page
    function CenterOfWord(const Text: string; const Occurrence: Integer): TPointF;
    // The mouse as the window system gives it: through the overrides of the control
    procedure MouseClickAt(const Point: TPointF);
    // Scrolls the invoice number into view, moves the mouse to the middle of it and clicks
    procedure ClickOnInvoiceNumber;
    // Makes the form of the scale, with the viewer
    procedure MakeHost(const Scale: Single);
    // Runs the flow of a person on a form of the scale and records the events
    procedure RunFlow(const Scale: Single);
    // Runs the flow and compares the events with the reference file
    procedure CheckEventsOnScale(const Scale: Single);

  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    // The same way through a document as in the VCL viewer: open, look, hover, click, mark, scroll to it, zoom, rotate, click again,
    // search, print to bitmaps and close. Nothing may raise, the events must come, and the test program checks that nothing leaks.
    [Test]
    procedure TestEndToEndFlow;
    // The events of the flow are those of the VCL viewer, which wrote them to tests/reference/viewer/flow-events.txt
    [Test]
    procedure TestEventsEqualVcl;
    // The same file on a screen of 150 %: the quads are in PDF user space, so the events do not depend on the scale; what depends on it is
    // the conversion from logical units to device pixels that the clicks go through
    [Test]
    procedure TestEventsEqualVclOnScale150;
  end;

implementation

uses
  System.Math,
  FMX.Types,
  Pdf4D.Tests.FmxBitmapPrintTarget,
  Pdf4D.Tests.ViewerDocuments;

const
  ViewWidth = 900;
  ViewHeight = 700;
  InvoiceNumber = '2024-0815';
  InvoiceNumberLabel = 'Nummer:';
  WaitMs = 20000;
  // A4 at 96 PPI
  PaperWidth = 794;
  PaperHeight = 1123;
  PaperDpi = 96;
  MarkAlpha = $80;
  ZoomStepsIn = 2;
  ScaleOfScreen = 1.5;

{ TFmxViewerFlowTests }

procedure TFmxViewerFlowTests.Setup;
begin
  FSelectedTexts := TList<string>.Create;
  FEvents := TFlowEventLog.Create;
  FHoverCount := 0;
  FIsPrinted := False;
  FPrintStatus := TPdfPrintStatus.Failed;
  FPrintMessage := '';
end;

procedure TFmxViewerFlowTests.TearDown;
begin
  FreeAndNil(FHost);
  FEvents.Free;
  FSelectedTexts.Free;
end;

procedure TFmxViewerFlowTests.MakeHost(const Scale: Single);
begin
  FHost := TFmxTestHost.Create(ViewWidth, ViewHeight, Scale);

  FViewer := TPdf4DViewer.Create(FHost.Form);
  FViewer.Parent := FHost.Form;
  FViewer.Align := TAlignLayout.Client;
  FViewer.Document := FHost.Document;
  FViewer.OnTextSelected := HandleTextSelected;
  FViewer.OnHoverChanged := HandleHoverChanged;
  FHost.Pump(1);
end;

procedure TFmxViewerFlowTests.HandleTextSelected(Sender: TObject; const Selection: TPdfTextSelection);
begin
  FSelectedTexts.Add(Selection.Text);
  FEvents.AddSelection(Selection);
end;

procedure TFmxViewerFlowTests.HandleHoverChanged(Sender: TObject; const HasSegment: Boolean; const Segment: TPdfTextFragment);
begin
  Inc(FHoverCount);
  FEvents.AddHover(HasSegment, Segment);
end;

function TFmxViewerFlowTests.TilesArrived: Boolean;
begin
  const Controller = FViewer.PageView.Controller;
  Result := ((Controller.PendingTileCount = 0) and (Controller.TileCacheCost > 0));
end;

function TFmxViewerFlowTests.IsSearchEnded: Boolean;
begin
  Result := not FHost.Document.IsSearching;
end;

function TFmxViewerFlowTests.IsPrintDone: Boolean;
begin
  Result := FIsPrinted;
end;

procedure TFmxViewerFlowTests.HandlePrintDone(const Status: TPdfPrintStatus; const ErrorMessage: string);
begin
  FPrintStatus := Status;
  FPrintMessage := ErrorMessage;
  FIsPrinted := True;
end;

function TFmxViewerFlowTests.QuadsOfWord(const Text: string; const Occurrence: Integer): TArray<TPdfQuad>;
begin
  var PageText: IPdfPageText;
  Assert.IsTrue(FHost.Document.TryGetPageText(0, PageText), 'the text of the first page is known');

  var Seen := 0;
  for var Word in PageText.Words do
  begin
    if Word.Text <> Text then
    begin
      Continue;
    end;

    if Seen = Occurrence then
    begin
      Exit(Word.Quads);
    end;
    Inc(Seen);
  end;

  Assert.Fail(Format('The word %s (%d) is not on the page', [Text, Occurrence]));
  Result := nil;
end;

function TFmxViewerFlowTests.CenterOfWord(const Text: string; const Occurrence: Integer): TPointF;
begin
  var Sum := TPointF.Create(0, 0);
  var Count := 0;
  for var Quad in QuadsOfWord(Text, Occurrence) do
  begin
    for var Corner in [Quad.P1, Quad.P2, Quad.P3, Quad.P4] do
    begin
      var ViewPoint: TPointF;
      Assert.IsTrue(FViewer.PageView.Controller.TryPageToViewport(0, Corner, ViewPoint), 'the page is laid out');
      Sum := Sum + ViewPoint;
      Inc(Count);
    end;
  end;

  // The middle of the corners in device pixels, rounded to a whole pixel, then in logical units of the page view (the VCL flow rounds each corner, which can differ by a pixel; the hit is the same word)
  const Device = TPointF.Create(Round(Sum.X / Count), Round(Sum.Y / Count));
  Result := TPointF.Create(Device.X / FHost.Scale, Device.Y / FHost.Scale);
end;

procedure TFmxViewerFlowTests.MouseClickAt(const Point: TPointF);
begin
  const PageView = TPageViewCracker(FViewer.PageView);
  PageView.MouseMove([], Point.X, Point.Y);
  PageView.MouseDown(TMouseButton.mbLeft, [ssLeft], Point.X, Point.Y);
  PageView.MouseUp(TMouseButton.mbLeft, [], Point.X, Point.Y);
end;

procedure TFmxViewerFlowTests.ClickOnInvoiceNumber;
begin
  FViewer.PageView.ScrollIntoView(0, QuadsOfWord(InvoiceNumber, 1));
  MouseClickAt(CenterOfWord(InvoiceNumber, 1));
end;

procedure TFmxViewerFlowTests.RunFlow(const Scale: Single);
begin
  MakeHost(Scale);

  const Document = FHost.Document;
  const PageView = FViewer.PageView;

  // Open and wait for the first tiles
  Assert.IsTrue(FHost.Open(TViewerDocuments.Invoice), 'the invoice opens: ' + FHost.OpenErrorMessage);
  Assert.IsTrue(FHost.WaitUntil(TilesArrived, WaitMs), 'the tiles of the first page arrive');
  Assert.IsTrue(FHost.WaitForPageText(0), 'the text of the first page arrives');

  // Hover on the number, and click it: the click selects it
  FEvents.AddStep('click');
  MouseClickAt(CenterOfWord(InvoiceNumber, 1));
  Assert.IsTrue(FHoverCount > 0, 'the hover is reported');
  Assert.AreEqual<Integer>(1, FSelectedTexts.Count, 'one selection');
  Assert.AreEqual(InvoiceNumber, FSelectedTexts[0]);

  // Mark the label and scroll it into view
  const LabelQuads = QuadsOfWord(InvoiceNumberLabel, 0);
  Assert.IsTrue(Length(LabelQuads) > 0, 'the label is on the page');
  Document.Overlays.Add(0, LabelQuads, TPdfOverlayStyle.Frame, TAlphaColor(MarkAlpha shl 24 or $FF0000));
  Assert.AreEqual<Integer>(1, Length(Document.Overlays.Items), 'the overlay is there');
  PageView.ScrollIntoView(0, LabelQuads);
  var LabelCorner: TPointF;
  Assert.IsTrue(PageView.Controller.TryPageToViewport(0, LabelQuads[0].P1, LabelCorner), 'the page is laid out');
  const IsInView = (LabelCorner.X >= 0) and (LabelCorner.Y >= 0) and (LabelCorner.X <= PageView.Width * FHost.Scale) and
                   (LabelCorner.Y <= PageView.Height * FHost.Scale);
  Assert.IsTrue(IsInView, 'the marked label is scrolled into view');

  // Zoom, rotate, with the mouse away from the page; then hover on the number again and click it, at a place that the test computes
  TPageViewCracker(PageView).DoMouseLeave;
  const ZoomBefore = PageView.Zoom;
  for var Step := 1 to ZoomStepsIn do
  begin
    PageView.ZoomIn;
  end;
  Assert.IsTrue(PageView.Zoom > ZoomBefore, 'zoomed in');
  PageView.RotateClockwise;
  Assert.AreEqual(90, PageView.ViewRotation, 'rotated');
  Assert.IsTrue(FHost.WaitUntil(TilesArrived, WaitMs), 'the tiles arrive after the zoom and the rotation');
  FEvents.AddStep('click after zoom and rotation');
  const SelectionsBefore = FSelectedTexts.Count;
  ClickOnInvoiceNumber;
  Assert.AreEqual<Integer>(SelectionsBefore + 1, FSelectedTexts.Count, 'the click after the zoom and the rotation selects');
  Assert.AreEqual(InvoiceNumber, FSelectedTexts[FSelectedTexts.Count - 1]);
  FEvents.AddStep('mouse leaves');
  TPageViewCracker(PageView).DoMouseLeave;
  FEvents.AddStep('search');

  // Search
  Document.Search(InvoiceNumberLabel, False);
  Assert.IsTrue(FHost.WaitUntil(IsSearchEnded, WaitMs), 'the search ends');
  Assert.IsTrue(Length(Document.SearchHits) > 0, 'the search found the label');
  FEvents.AddSearchHits(Document.SearchHits);

  // Print to bitmaps, with a print job of the document (the print dialog of the viewer needs a printer)
  const Target = TFmxBitmapPrintTarget.Create(TSize.Create(PaperWidth, PaperHeight), TPointF.Create(PaperDpi, PaperDpi), '');
  const TargetReference: IPdfPrintTarget = Target;
  const Job = TPdfPrintJob.Create(Document, TargetReference, TPdfPrintSettings.Default);
  try
    Job.Start(nil, HandlePrintDone);
    Assert.IsTrue(FHost.WaitUntil(IsPrintDone, WaitMs), 'the print job ends');
    Assert.AreEqual(Ord(TPdfPrintStatus.Completed), Ord(FPrintStatus), FPrintMessage);
    Assert.IsTrue(Target.IsEnded, 'the print document is ended');
    Assert.AreEqual<Integer>(Document.PageCount, Target.Pages.Count, 'every page is printed');
  finally
    Job.Free;
  end;

  // Close
  Document.Close;
  FHost.Pump(1);
  Assert.AreEqual(Ord(TPdfDocumentState.Closed), Ord(Document.State));
  Assert.AreEqual<Integer>(0, Length(Document.Overlays.Items), 'the overlay goes with the document');
end;

procedure TFmxViewerFlowTests.CheckEventsOnScale(const Scale: Single);
begin
  RunFlow(Scale);

  Assert.AreEqual('', FEvents.Verify(False), Format('the events of the flow on scale %.2f equal those of the VCL viewer', [Scale]));
end;

procedure TFmxViewerFlowTests.TestEndToEndFlow;
begin
  RunFlow(1);
end;

procedure TFmxViewerFlowTests.TestEventsEqualVcl;
begin
  CheckEventsOnScale(1);
end;

procedure TFmxViewerFlowTests.TestEventsEqualVclOnScale150;
begin
  CheckEventsOnScale(ScaleOfScreen);
end;

end.
