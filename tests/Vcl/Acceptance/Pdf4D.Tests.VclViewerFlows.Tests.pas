// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.VclViewerFlows.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.Generics.Collections,
  System.SysUtils,
  System.Types,
  DUnitX.TestFramework,
  Pdf4D.Api.TextLayout.Interfaces,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.PageText,
  Pdf4D.Tests.FlowEvents,
  Pdf4D.Tests.VclHost,
  Pdf4D.Vcl.Viewer;

type
  [TestFixture]
  TVclViewerFlowTests = class
  private
    FHost: TVclTestHost;
    FViewer: TPdf4DViewer;
    FSelectedTexts: TList<string>;
    FHoverCount: Integer;
    FEvents: TFlowEventLog;

    procedure HandleTextSelected(Sender: TObject; const Selection: TPdfTextSelection);
    procedure HandleHoverChanged(Sender: TObject; const HasSegment: Boolean; const Segment: TPdfTextFragment);
    function TilesArrived: Boolean;
    // The client pixels of the middle of an occurrence of a word on the first page, in the page view of the viewer
    function CenterOfWord(const Text: string; const Occurrence: Integer): TPoint;
    function QuadsOfWord(const Text: string; const Occurrence: Integer): TArray<TPdfQuad>;
    // Moves the mouse to the middle of the invoice number and clicks it; the number is scrolled into view first
    procedure ClickOnInvoiceNumber;

  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    // A person's way through a document, in one run: open, look, hover, click, mark, scroll to it, zoom, rotate, search, print to
    // bitmaps and close. Nothing may raise, the events must come, and the test program checks that nothing leaks.
    [Test]
    procedure TestEndToEndFlow;
  end;

implementation

uses
  System.Math,
  System.UITypes,
  Vcl.Controls,
  Winapi.Messages,
  Pdf4D.Common.Quad,
  Pdf4D.Viewer.Print,
  Pdf4D.Vcl.Print,
  Pdf4D.Tests.BitmapPrintTarget,
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

{ TVclViewerFlowTests }

procedure TVclViewerFlowTests.Setup;
begin
  FSelectedTexts := TList<string>.Create;
  FEvents := TFlowEventLog.Create;
  FHoverCount := 0;

  FHost := TVclTestHost.Create(ViewWidth, ViewHeight);
  // The viewer has a page view of its own
  FHost.PageView.Visible := False;

  FViewer := TPdf4DViewer.Create(FHost.Form);
  FViewer.Parent := FHost.Form;
  FViewer.Align := TAlign.alClient;
  FViewer.Document := FHost.Document;
  FViewer.OnTextSelected := HandleTextSelected;
  FViewer.OnHoverChanged := HandleHoverChanged;
  FHost.Pump(1);
end;

procedure TVclViewerFlowTests.TearDown;
begin
  FreeAndNil(FHost);
  FEvents.Free;
  FSelectedTexts.Free;
end;

procedure TVclViewerFlowTests.HandleTextSelected(Sender: TObject; const Selection: TPdfTextSelection);
begin
  FSelectedTexts.Add(Selection.Text);
  FEvents.AddSelection(Selection);
end;

procedure TVclViewerFlowTests.HandleHoverChanged(Sender: TObject; const HasSegment: Boolean; const Segment: TPdfTextFragment);
begin
  Inc(FHoverCount);
  FEvents.AddHover(HasSegment, Segment);
end;

function TVclViewerFlowTests.TilesArrived: Boolean;
begin
  const Controller = FViewer.PageView.Controller;
  Result := ((Controller.PendingTileCount = 0) and (Controller.TileCacheCost > 0));
end;

function TVclViewerFlowTests.QuadsOfWord(const Text: string; const Occurrence: Integer): TArray<TPdfQuad>;
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

function TVclViewerFlowTests.CenterOfWord(const Text: string; const Occurrence: Integer): TPoint;
begin
  var Sum := TPoint.Zero;
  var Count := 0;
  for var Quad in QuadsOfWord(Text, Occurrence) do
  begin
    for var Corner in [Quad.P1, Quad.P2, Quad.P3, Quad.P4] do
    begin
      var ViewPoint: TPointF;
      Assert.IsTrue(FViewer.PageView.Controller.TryPageToViewport(0, Corner, ViewPoint), 'the page is laid out');
      Inc(Sum.X, Round(ViewPoint.X));
      Inc(Sum.Y, Round(ViewPoint.Y));
      Inc(Count);
    end;
  end;
  Result := TPoint.Create(Sum.X div Count, Sum.Y div Count);
end;

procedure TVclViewerFlowTests.ClickOnInvoiceNumber;
begin
  FViewer.PageView.ScrollIntoView(0, QuadsOfWord(InvoiceNumber, 1));
  const Number = CenterOfWord(InvoiceNumber, 1);
  FHost.ClickOn(FViewer.PageView, Number.X, Number.Y);
end;

procedure TVclViewerFlowTests.TestEndToEndFlow;
begin
  const Document = FHost.Document;
  const PageView = FViewer.PageView;

  // Open and wait for the first tiles
  Assert.IsTrue(FHost.Open(TViewerDocuments.Invoice), 'the invoice opens: ' + FHost.OpenErrorMessage);
  Assert.IsTrue(FHost.WaitUntil(TilesArrived, WaitMs), 'the tiles of the first page arrive');
  Assert.IsTrue(FHost.WaitForPageText(0), 'the text of the first page arrives');

  // Hover on the number, and click it: the click selects it
  FEvents.AddStep('click');
  const Number = CenterOfWord(InvoiceNumber, 1);
  FHost.ClickOn(PageView, Number.X, Number.Y);
  Assert.IsTrue(FHoverCount > 0, 'the hover is reported');
  Assert.AreEqual<Integer>(1, FSelectedTexts.Count, 'one selection');
  Assert.AreEqual(InvoiceNumber, FSelectedTexts[0]);

  // Mark the label and scroll it into view
  var PageText: IPdfPageText;
  Assert.IsTrue(Document.TryGetPageText(0, PageText), 'the text of the first page is known');
  var LabelQuads: TArray<TPdfQuad> := nil;
  for var Word in PageText.Words do
  begin
    if (Word.Text = InvoiceNumberLabel) and (Length(LabelQuads) = 0) then
    begin
      LabelQuads := Word.Quads;
    end;
  end;
  Assert.IsTrue(Length(LabelQuads) > 0, 'the label is on the page');
  Document.Overlays.Add(0, LabelQuads, TPdfOverlayStyle.Frame, TAlphaColor(MarkAlpha shl 24 or $FF0000));
  Assert.AreEqual<Integer>(1, Length(Document.Overlays.Items), 'the overlay is there');
  PageView.ScrollIntoView(0, LabelQuads);
  var LabelCorner: TPointF;
  Assert.IsTrue(PageView.Controller.TryPageToViewport(0, LabelQuads[0].P1, LabelCorner), 'the page is laid out');
  const IsInView = (LabelCorner.X >= 0) and (LabelCorner.Y >= 0) and (LabelCorner.X <= PageView.ClientWidth) and
                   (LabelCorner.Y <= PageView.ClientHeight);
  Assert.IsTrue(IsInView, 'the marked label is scrolled into view');

  // Zoom, rotate, with the mouse away from the page; then hover on the number again and click it, at a place that the test computes
  PageView.Perform(CM_MOUSELEAVE, 0, 0);
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
  // The mouse leaves again, by hand: a window that got mouse messages from Perform has asked Windows to tell it when the pointer leaves, and
  // Windows does that at the next pump, which would put a hover event at a moment that the test does not choose
  FEvents.AddStep('mouse leaves');
  PageView.Perform(CM_MOUSELEAVE, 0, 0);
  FEvents.AddStep('search');

  // Search
  Document.Search(InvoiceNumberLabel, False);
  Assert.IsTrue(FHost.WaitUntil(
    function: Boolean
    begin
      Result := not Document.IsSearching;
    end, WaitMs), 'the search ends');
  Assert.IsTrue(Length(Document.SearchHits) > 0, 'the search found the label');
  FEvents.AddSearchHits(Document.SearchHits);

  // Print to bitmaps, with a print job of the document (the print dialog of the viewer needs a printer)
  const Target = TBitmapPrintTarget.Create(TSize.Create(PaperWidth, PaperHeight), TPointF.Create(PaperDpi, PaperDpi), '');
  const TargetReference: IPdfPrintTarget = Target;
  const Job = TPdfPrintJob.Create(Document, TargetReference, TPdfPrintSettings.Default);
  try
    var Status := TPdfPrintStatus.Failed;
    var IsPrinted := False;
    var PrintMessage := '';
    Job.Start(nil,
      procedure(const DoneStatus: TPdfPrintStatus; const ErrorMessage: string)
      begin
        Status := DoneStatus;
        PrintMessage := ErrorMessage;
        IsPrinted := True;
      end);
    Assert.IsTrue(FHost.WaitUntil(
      function: Boolean
      begin
        Result := IsPrinted;
      end, WaitMs), 'the print job ends');
    Assert.AreEqual(Ord(TPdfPrintStatus.Completed), Ord(Status), PrintMessage);
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

  // The events are the same in the FMX viewer: the file in the source tree holds them (PDF4D_RECORD_FLOW_EVENTS=1 writes it)
  Assert.AreEqual('', FEvents.Verify(True), 'the events of the flow equal the reference file');
end;

end.
