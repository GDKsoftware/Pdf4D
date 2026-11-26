// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Vcl.PageView.Tests;

{$EXCESSPRECISION OFF}
{$POINTERMATH ON}

interface

uses
  System.Classes,
  System.Types,
  System.SysUtils,
  System.Generics.Collections,
  Vcl.Graphics,
  DUnitX.TestFramework,
  Pdf4D.Common.Defines,
  Pdf4D.Common.Quad,
  Pdf4D.Api.TextLayout.Interfaces,
  Pdf4D.Viewer.Types,
  Pdf4D.Vcl.Document,
  Pdf4D.Vcl.PageView,
  Pdf4D.Tests.VclHost;

type
  // A page view whose clipboard is held by another program
  TBusyClipboardPageView = class(TPdf4DPageView)
  protected
    procedure WriteClipboardText(const Text: string); override;
  end;

  TPixel = record
    R, G, B: Byte;
  end;

  [TestFixture]
  TPdf4DPageViewTests = class
  private
    FHost: TVclTestHost;
    FSelections: TList<TPdfTextSelection>;
    FHoverTexts: TList<string>;
    FLogLines: TList<string>;

    procedure HandleTextSelected(Sender: TObject; const Selection: TPdfTextSelection);
    procedure HandleHoverChanged(Sender: TObject; const HasSegment: Boolean; const Segment: TPdfTextFragment);
    procedure HandleLog(Sender: TObject; const Level: TPdfLogLevel; const Message: string);

    // Opens the data and waits until the first page is painted with its text known
    procedure OpenAndSettle(const Data: TBytes);
    function WordOf(const PageIndex: Integer; const Text: string; const Occurrence: Integer = 0): TPdfTextFragment;
    function ClientBoundsOf(const PageIndex: Integer; const Quads: TArray<TPdfQuad>): TRect;
    function CenterOf(const Bounds: TRect): TPoint;
    function StemWidthOfF(const Word: TPdfTextFragment): Double;
    procedure AssertOverlayCoversText(const Data: TBytes);
    class function PixelAt(const Bitmap: Vcl.Graphics.TBitmap; const X, Y: Integer): TPixel; static;
    class function RowDarkness(const Bitmap: Vcl.Graphics.TBitmap; const Y, Left, Right: Integer): Double; static;
    class function IsRed(const Pixel: TPixel): Boolean; static;
    class function IsBluish(const Pixel: TPixel): Boolean; static;
    class procedure PumpFor(const Milliseconds: Integer); static;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestOpenShowsFirstPage;

    [Test]
    procedure TestZoomInEnlargesContent;

    [Test]
    procedure TestHorizontalWheelAndShiftWheelScrollSideways;

    [Test]
    procedure TestHoverDrawsFrame;

    [Test]
    procedure TestClickRaisesTextSelected;

    [Test]
    procedure TestDragAndCopy;

    [Test]
    procedure TestCopyRespectsPermissions;

    [Test]
    procedure TestOverlayCoversRenderedText;

    [Test]
    procedure TestOverlayOnRotatedPage;

    [Test]
    procedure TestDpiChangeRerendersAtNewScale;

    [Test]
    procedure TestFreeFormWhileRendering;

    [Test]
    procedure TestDocumentSwitchDoesNotLeak;

    [Test]
    procedure TestNoBackendRendersWithTheNativeRasterizer;

    [Test]
    procedure TestFreeTellsZoomListenersWhileTheyAreRegistered;

    [Test]
    procedure TestBusyClipboardIsLoggedNotRaised;

    [Test]
    procedure TestDesignTimeShowsAPlaceholder;
  end;

implementation

uses
  System.Math,
  System.Diagnostics,
  Vcl.Forms,
  Vcl.Clipbrd,
  Winapi.Messages,
  Winapi.Windows,
  Pdf4D.Viewer.PageText,
  Pdf4D.Tests.ViewerDocuments;

const
  ViewWidth = 800;
  ViewHeight = 600;
  InvoiceNumber = '2024-0815';
  DarkSum = 300;
  Sentinel = 'sentinel text';
  InkThreshold = 0.3;
  StemRowsAbove = 2;
  FullDarkness = 255;
  OverlayMargin = 2;
  SearchMargin = 8;
  BluishRange = 70;
  HoverBlue: TPixel = (R: 30; G: 144; B: 255);
  DpiFactor = 1.5;
  HighDpi = 144;
  StemTolerance = 1.0;
  SwitchRounds = 10;
  LargeDocumentPages = 200;
  ScrollAway = 20000;
  QuietPeriodMs = 500;
  BackgroundGray = 224;
  DarkLimit = 100;
  BusyClipboard = 'the clipboard is busy';
  DesignGray = 240;
  DesignInkContrast = 60;
  ClassNameBand = 20;

type
  // Opens the protected state of a component: a test hook for the design state
  TDesignAccess = class(TComponent);

{ TBusyClipboardPageView }

procedure TBusyClipboardPageView.WriteClipboardText(const Text: string);
begin
  raise EClipboardException.Create(BusyClipboard);
end;

{ TPdf4DPageViewTests }

procedure TPdf4DPageViewTests.Setup;
begin
  FSelections := TList<TPdfTextSelection>.Create;
  FHoverTexts := TList<string>.Create;
  FLogLines := TList<string>.Create;
  FHost := TVclTestHost.Create(ViewWidth, ViewHeight);
  FHost.PageView.OnTextSelected := HandleTextSelected;
  FHost.PageView.OnHoverChanged := HandleHoverChanged;
end;

procedure TPdf4DPageViewTests.TearDown;
begin
  FreeAndNil(FHost);
  FHoverTexts.Free;
  FLogLines.Free;
  FSelections.Free;
end;

procedure TPdf4DPageViewTests.HandleTextSelected(Sender: TObject; const Selection: TPdfTextSelection);
begin
  FSelections.Add(Selection);
end;

procedure TPdf4DPageViewTests.HandleHoverChanged(Sender: TObject; const HasSegment: Boolean; const Segment: TPdfTextFragment);
begin
  if HasSegment then
  begin
    FHoverTexts.Add(Segment.Text);
  end;
end;

class procedure TPdf4DPageViewTests.PumpFor(const Milliseconds: Integer);
begin
  const Watch = TStopwatch.StartNew;
  repeat
    CheckSynchronize(1);
    Application.ProcessMessages;
  until Watch.ElapsedMilliseconds >= Milliseconds;
end;

procedure TPdf4DPageViewTests.OpenAndSettle(const Data: TBytes);
begin
  Assert.IsTrue(FHost.Open(Data), 'the document opens: ' + FHost.OpenErrorMessage);
  Assert.IsTrue(FHost.WaitForPageText(0), 'the text of the first page arrives');
  Assert.IsTrue(FHost.WaitForVisibleTiles, 'the tiles arrive');
end;

function TPdf4DPageViewTests.WordOf(const PageIndex: Integer; const Text: string; const Occurrence: Integer): TPdfTextFragment;
begin
  var PageText: IPdfPageText;
  Assert.IsTrue(FHost.Document.TryGetPageText(PageIndex, PageText), 'the page text is known');

  var Seen := 0;
  for var Word in PageText.Words do
  begin
    if Word.Text = Text then
    begin
      if Seen = Occurrence then
      begin
        Exit(Word);
      end;
      Inc(Seen);
    end;
  end;
  Assert.Fail(Format('The word %s (%d) is not on page %d', [Text, Occurrence, PageIndex]));
  Result := Default(TPdfTextFragment);
end;

function TPdf4DPageViewTests.ClientBoundsOf(const PageIndex: Integer; const Quads: TArray<TPdfQuad>): TRect;
begin
  var IsFirst := True;
  Result := TRect.Empty;
  for var Quad in Quads do
  begin
    for var Corner in [Quad.P1, Quad.P2, Quad.P3, Quad.P4] do
    begin
      const Point = FHost.PagePointToClient(PageIndex, Corner);
      if IsFirst then
      begin
        Result := TRect.Create(Point, Point);
        IsFirst := False;
      end
      else
      begin
        Result.Left := Min(Result.Left, Point.X);
        Result.Top := Min(Result.Top, Point.Y);
        Result.Right := Max(Result.Right, Point.X);
        Result.Bottom := Max(Result.Bottom, Point.Y);
      end;
    end;
  end;
end;

function TPdf4DPageViewTests.CenterOf(const Bounds: TRect): TPoint;
begin
  Result := TPoint.Create((Bounds.Left + Bounds.Right) div 2, (Bounds.Top + Bounds.Bottom) div 2);
end;

class function TPdf4DPageViewTests.PixelAt(const Bitmap: Vcl.Graphics.TBitmap; const X, Y: Integer): TPixel;
begin
  const Line = PByte(Bitmap.ScanLine[Y]) + X * 3;
  Result.B := Line[0];
  Result.G := Line[1];
  Result.R := Line[2];
end;

class function TPdf4DPageViewTests.IsRed(const Pixel: TPixel): Boolean;
begin
  Result := (Pixel.R > 200) and (Pixel.G < 80) and (Pixel.B < 80);
end;

class function TPdf4DPageViewTests.IsBluish(const Pixel: TPixel): Boolean;
begin
  Result := (Abs(Pixel.R - HoverBlue.R) + Abs(Pixel.G - HoverBlue.G) + Abs(Pixel.B - HoverBlue.B)) < BluishRange;
end;

procedure TPdf4DPageViewTests.TestOpenShowsFirstPage;
begin
  OpenAndSettle(TViewerDocuments.Invoice);

  const Bitmap = FHost.Snapshot;
  try
    const Center = CenterOf(ClientBoundsOf(0, WordOf(0, 'Factuur').Quads));
    var HasDark := False;
    for var Y := Center.Y - 4 to Center.Y + 4 do
    begin
      for var X := Center.X - 4 to Center.X + 4 do
      begin
        const Pixel = PixelAt(Bitmap, X, Y);
        HasDark := HasDark or ((Pixel.R + Pixel.G + Pixel.B) < DarkSum);
      end;
    end;
    Assert.IsTrue(HasDark, 'the word Factuur is drawn');

    const Empty = FHost.PagePointToClient(0, TPointF.Create(500, 700));
    const Pixel = PixelAt(Bitmap, Empty.X, Empty.Y);
    Assert.AreEqual(3 * 255, Integer(Pixel.R) + Integer(Pixel.G) + Integer(Pixel.B), 'an empty place of the page is white');
    Assert.IsTrue(FHost.PageView.Controller.TileCacheCost > 0, 'tiles are cached');
  finally
    Bitmap.Free;
  end;
end;

procedure TPdf4DPageViewTests.TestZoomInEnlargesContent;
begin
  OpenAndSettle(TViewerDocuments.Invoice);
  FHost.PageView.Zoom := 1;
  FHost.Pump(1);
  const Before = FHost.PageView.Controller.ContentSize;

  FHost.PageView.ZoomIn;
  FHost.Pump(1);
  const After = FHost.PageView.Controller.ContentSize;

  Assert.IsTrue(After.cy > Before.cy, 'the content is taller');
  Assert.IsTrue(After.cx > Before.cx, 'the content is wider');
  const Style = GetWindowLong(FHost.PageView.Handle, GWL_STYLE);
  Assert.IsTrue((Style and WS_VSCROLL) <> 0, 'the vertical scroll bar is visible');
end;

procedure TPdf4DPageViewTests.TestHorizontalWheelAndShiftWheelScrollSideways;
begin
  OpenAndSettle(TViewerDocuments.Invoice);
  FHost.PageView.Zoom := 4;
  FHost.Pump(1);
  const Start = FHost.PageView.Controller.ScrollPosition.X;

  // The message of the tilt wheel: a notch to the right
  FHost.PageView.Perform(WM_MOUSEHWHEEL, MakeWParam(0, WHEEL_DELTA), 0);
  const Right = FHost.PageView.Controller.ScrollPosition.X;
  Assert.IsTrue(Right > Start, 'the tilt wheel scrolls to the right');

  // Shift and the wheel up: to the left
  const Screen = FHost.PageView.ClientToScreen(TPoint.Create(10, 10));
  FHost.PageView.Perform(WM_MOUSEWHEEL, MakeWParam(MK_SHIFT, WHEEL_DELTA), MakeLParam(Word(Screen.X), Word(Screen.Y)));
  Assert.IsTrue(FHost.PageView.Controller.ScrollPosition.X < Right, 'shift and the wheel scroll sideways');
end;

procedure TPdf4DPageViewTests.TestHoverDrawsFrame;
begin
  OpenAndSettle(TViewerDocuments.Invoice);
  const Bounds = ClientBoundsOf(0, WordOf(0, InvoiceNumber).Quads);
  const Center = CenterOf(Bounds);

  FHost.MouseMove(Center.X, Center.Y);

  Assert.AreEqual<Integer>(1, FHoverTexts.Count, 'one hover event');
  Assert.IsTrue(FHoverTexts[0].Contains(InvoiceNumber), 'the segment holds the number');
  const Bitmap = FHost.Snapshot;
  try
    var HasBlue := False;
    var Area := Bounds;
    Area.Inflate(SearchMargin, SearchMargin);
    for var Y := Area.Top to Area.Bottom do
    begin
      for var X := Area.Left to Area.Right do
      begin
        HasBlue := HasBlue or IsBluish(PixelAt(Bitmap, X, Y));
      end;
    end;
    Assert.IsTrue(HasBlue, 'the frame of the hover colour is drawn around the segment');
  finally
    Bitmap.Free;
  end;
end;

procedure TPdf4DPageViewTests.TestClickRaisesTextSelected;
begin
  OpenAndSettle(TViewerDocuments.Invoice);
  // On the second line the number is a segment of its own
  const Center = CenterOf(ClientBoundsOf(0, WordOf(0, InvoiceNumber, 1).Quads));

  FHost.Click(Center.X, Center.Y);

  Assert.AreEqual<Integer>(1, FSelections.Count, 'one event');
  Assert.AreEqual(InvoiceNumber, FSelections[0].Text);
  Assert.AreEqual(0, FSelections[0].PageIndex);
end;

procedure TPdf4DPageViewTests.TestDragAndCopy;
begin
  OpenAndSettle(TViewerDocuments.Invoice);
  const First = ClientBoundsOf(0, WordOf(0, 'Nummer:').Quads);
  const Last = ClientBoundsOf(0, WordOf(0, InvoiceNumber, 1).Quads);
  const Y = CenterOf(First).Y;

  const HasClipboard = FHost.IsClipboardAvailable;
  if HasClipboard then
  begin
    Clipboard.AsText := Sentinel;
  end;
  FHost.Drag(First.Left + 1, Y, Last.Right - 1, Y);
  FHost.PressKey(Ord('C'), True);

  Assert.AreEqual<Integer>(1, FHost.PageView.CopiedTexts.Count, 'Ctrl+C copies once');
  Assert.AreEqual('Nummer: ' + InvoiceNumber, FHost.PageView.CopiedTexts[0]);
  if HasClipboard then
  begin
    Assert.AreEqual('Nummer: ' + InvoiceNumber, Clipboard.AsText);
  end;
end;

procedure TPdf4DPageViewTests.TestCopyRespectsPermissions;
begin
  OpenAndSettle(TVclTestDocuments.Restricted);
  Assert.IsFalse(FHost.Document.CanCopy, 'the document does not allow copying');
  const Center = CenterOf(ClientBoundsOf(0, WordOf(0, InvoiceNumber).Quads));

  const HasClipboard = FHost.IsClipboardAvailable;
  if HasClipboard then
  begin
    Clipboard.AsText := Sentinel;
  end;
  FHost.Click(Center.X, Center.Y);
  FHost.PressKey(Ord('C'), True);

  Assert.AreEqual<Integer>(1, FSelections.Count, 'the event comes all the same');
  Assert.AreEqual<Integer>(0, FHost.PageView.CopiedTexts.Count, 'nothing is copied');
  if HasClipboard then
  begin
    Assert.AreEqual(Sentinel, Clipboard.AsText, 'the clipboard is not touched');
  end;
end;

procedure TPdf4DPageViewTests.AssertOverlayCoversText(const Data: TBytes);
begin
  OpenAndSettle(Data);
  const Word = WordOf(0, InvoiceNumber);
  FHost.Document.Overlays.Add(0, Word.Quads, TPdfOverlayStyle.Fill, $FFFF0000);
  FHost.Pump(1);

  const Bounds = ClientBoundsOf(0, Word.Quads);
  var Covered := Bounds;
  Covered.Inflate(-1, -1);
  var Allowed := Bounds;
  Allowed.Inflate(OverlayMargin, OverlayMargin);
  var Search := Bounds;
  Search.Inflate(SearchMargin, SearchMargin);

  const Bitmap = FHost.Snapshot;
  try
    var Uncovered := 0;
    var Spilled := 0;
    for var Y := Search.Top to Search.Bottom do
    begin
      for var X := Search.Left to Search.Right do
      begin
        const IsRedPixel = IsRed(PixelAt(Bitmap, X, Y));
        if Covered.Contains(TPoint.Create(X, Y)) and (not IsRedPixel) then
        begin
          Inc(Uncovered);
        end;
        if (not Allowed.Contains(TPoint.Create(X, Y))) and IsRedPixel then
        begin
          Inc(Spilled);
        end;
      end;
    end;

    Assert.AreEqual(0, Uncovered, 'every pixel inside the rectangle of the quad is covered');
    Assert.AreEqual(0, Spilled, 'nothing outside the rectangle is covered');
  finally
    Bitmap.Free;
  end;
end;

procedure TPdf4DPageViewTests.TestOverlayCoversRenderedText;
begin
  AssertOverlayCoversText(TViewerDocuments.Invoice);
end;

procedure TPdf4DPageViewTests.TestOverlayOnRotatedPage;
begin
  AssertOverlayCoversText(TViewerDocuments.RotatedCropped);
end;

// The darkness across the stem of the F of Factuur, in pixels: measured on the row two pixels above the lowest row with ink, where
// only the stem of the letter is
function TPdf4DPageViewTests.StemWidthOfF(const Word: TPdfTextFragment): Double;
begin
  const Origin = Word.Quads[0].P1;
  const Top = FHost.PagePointToClient(0, Word.Quads[0].P4).Y;
  const Bottom = FHost.PagePointToClient(0, Word.Quads[0].P1).Y;
  const Left = FHost.PagePointToClient(0, TPointF.Create(Origin.X - 0.5, Origin.Y)).X;
  const Right = FHost.PagePointToClient(0, TPointF.Create(Origin.X + 3.5, Origin.Y)).X;

  const Bitmap = FHost.Snapshot;
  try
    var LastInkRow := -1;
    for var Y := Top to Bottom do
    begin
      if RowDarkness(Bitmap, Y, Left, Right) > InkThreshold then
      begin
        LastInkRow := Y;
      end;
    end;
    Assert.IsTrue(LastInkRow >= 0, 'the letter F has ink');

    Result := RowDarkness(Bitmap, LastInkRow - StemRowsAbove, Left, Right);
  finally
    Bitmap.Free;
  end;
end;

class function TPdf4DPageViewTests.RowDarkness(const Bitmap: Vcl.Graphics.TBitmap; const Y, Left, Right: Integer): Double;
begin
  Result := 0;
  for var X := Left to Right do
  begin
    Result := Result + (FullDarkness - PixelAt(Bitmap, X, Y).R) / FullDarkness;
  end;
end;

procedure TPdf4DPageViewTests.TestDpiChangeRerendersAtNewScale;
begin
  OpenAndSettle(TViewerDocuments.Invoice);
  FHost.PageView.Zoom := 1;
  Assert.IsTrue(FHost.WaitForVisibleTiles, 'tiles at zoom 1');
  const Word = WordOf(0, 'Factuur');
  const StemBefore = StemWidthOfF(Word);
  const ContentBefore = FHost.PageView.Controller.ContentSize;
  const PageBefore = FHost.Document.CurrentPage;
  Assert.IsTrue(StemBefore > 0, 'the stem is drawn');

  FHost.Form.ScaleForPPI(HighDpi);
  FHost.Pump(1);
  Assert.IsTrue(FHost.WaitForVisibleTiles, 'tiles at the new scale');

  const ContentAfter = FHost.PageView.Controller.ContentSize;
  Assert.AreEqual(Double(ContentBefore.cx * DpiFactor), Double(ContentAfter.cx), 2.0, 'the content is 1.5 times wider');
  Assert.AreEqual(PageBefore, FHost.Document.CurrentPage, 'the current page stays');
  const StemAfter = StemWidthOfF(Word);
  Assert.AreEqual(StemBefore * DpiFactor, StemAfter, StemTolerance, 'the stem is sharp at the new scale');
end;

procedure TPdf4DPageViewTests.TestFreeFormWhileRendering;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Pages(LargeDocumentPages, 612, 792, 0)), 'the large document opens');
  FHost.PageView.Controller.ScrollBy(0, ScrollAway);
  // The form goes while tiles are on their way, not after they came
  Assert.IsTrue(FHost.PageView.Controller.PendingTileCount > 0, 'tiles are pending when the form is freed');

  FreeAndNil(FHost);
  PumpFor(QuietPeriodMs);

  Assert.IsNull(FHost, 'the form is gone and the queue was handled without a failure');
end;

procedure TPdf4DPageViewTests.TestDocumentSwitchDoesNotLeak;
begin
  const First = TViewerDocuments.Invoice;
  const Second = TViewerDocuments.Pages(3, 400, 500, 0);

  for var Pass := 1 to SwitchRounds do
  begin
    Assert.IsTrue(FHost.Open(First), 'the invoice opens');
    Assert.IsTrue(FHost.WaitForVisibleTiles);
    Assert.IsTrue(FHost.Open(Second), 'the second document opens');
    Assert.IsTrue(FHost.WaitForVisibleTiles);
  end;

  Assert.AreEqual(3, FHost.Document.PageCount);
end;

procedure TPdf4DPageViewTests.TestNoBackendRendersWithTheNativeRasterizer;
begin
  FHost.RemoveBackend;
  const Data = TViewerDocuments.Invoice;

  Assert.IsTrue(FHost.Open(Data), 'the document opens without a backend: ' + FHost.OpenErrorMessage);
  Assert.IsTrue(FHost.WaitForVisibleTiles, 'the tiles are rendered');

  const Bitmap = FHost.Snapshot;
  try
    var DarkPixels := 0;
    for var Y := 0 to Bitmap.Height - 1 do
    begin
      for var X := 0 to Bitmap.Width - 1 do
      begin
        if PixelAt(Bitmap, X, Y).R < DarkLimit then
        begin
          Inc(DarkPixels);
        end;
      end;
    end;
    Assert.IsTrue(DarkPixels > 0, 'the page shows ink');
  finally
    Bitmap.Free;
  end;
end;

// A component that follows the zoom lets go of the page view in its free notification, as the toolbar does: the list of listeners must
// still be there then
procedure TPdf4DPageViewTests.TestFreeTellsZoomListenersWhileTheyAreRegistered;
begin
  const Probe = TZoomListenerProbe.Create(FHost.PageView);
  try
    FHost.PageView.Free;

    Assert.AreEqual(1, Probe.ListenerCountAtRemoval, 'the probe was still registered when it was told');
  finally
    Probe.Free;
  end;
end;

procedure TPdf4DPageViewTests.HandleLog(Sender: TObject; const Level: TPdfLogLevel; const Message: string);
begin
  FLogLines.Add(Message);
end;

procedure TPdf4DPageViewTests.TestBusyClipboardIsLoggedNotRaised;
begin
  OpenAndSettle(TViewerDocuments.Invoice);
  FHost.Document.OnLog := HandleLog;
  const View = TBusyClipboardPageView.Create(FHost.Form);
  View.Parent := FHost.Form;
  View.Document := FHost.Document;
  Assert.IsTrue(FHost.WaitForPageText(0));
  Assert.IsTrue(View.Controller.KeyDown(TPdfViewerKey.SelectAll), 'all text is selected');

  View.CopyToClipboard;

  var Lines := 0;
  for var Line in FLogLines do
  begin
    if Line.Contains(BusyClipboard) then
    begin
      Inc(Lines);
    end;
  end;
  Assert.AreEqual(1, Lines, 'the failure is in the log once');
end;

// The form designer shows a grey field with the name of the class, without a document, tiles or a worker
procedure TPdf4DPageViewTests.TestDesignTimeShowsAPlaceholder;
begin
  OpenAndSettle(TViewerDocuments.Invoice);
  TDesignAccess(FHost.PageView).SetDesigning(True);
  FHost.PageView.Invalidate;

  const Bitmap = FHost.Snapshot;
  try
    Assert.AreEqual(DesignGray, Integer(PixelAt(Bitmap, 1, 1).R), 'the background is the placeholder grey');
    Assert.AreEqual(DesignGray, Integer(PixelAt(Bitmap, ViewWidth - 2, ViewHeight - 2).G), 'all over the control');

    var Ink := 0;
    for var Y := ViewHeight div 2 - ClassNameBand to ViewHeight div 2 + ClassNameBand do
    begin
      for var X := 0 to ViewWidth - 1 do
      begin
        if PixelAt(Bitmap, X, Y).R < DesignGray - DesignInkContrast then
        begin
          Inc(Ink);
        end;
      end;
    end;
    Assert.IsTrue(Ink > 0, 'the class name is drawn in the middle');
  finally
    Bitmap.Free;
  end;
end;

end.
