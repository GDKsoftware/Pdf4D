// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.FMX.PageView.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.Types,
  System.SysUtils,
  System.UITypes,
  System.Generics.Collections,
  FMX.Graphics,
  DUnitX.TestFramework,
  Pdf4D.Common.Quad,
  Pdf4D.Render.Bitmap,
  Pdf4D.Api.TextLayout.Interfaces,
  Pdf4D.Viewer.Types,
  Pdf4D.Tests.FmxHost;

type
  // Reads the pixels of a bitmap of FMX; the bitmap stays mapped for as long as the reader lives
  TPixelReader = class
  private
    FBitmap: FMX.Graphics.TBitmap;
    FData: TBitmapData;

  public
    constructor Create(const Bitmap: FMX.Graphics.TBitmap);
    destructor Destroy; override;

    function Pixel(const X, Y: Integer): TAlphaColorRec;
  end;

  [TestFixture]
  TPdf4DPageViewTests = class
  private
    FHost: TFmxTestHost;
    FSelections: TList<TPdfTextSelection>;
    FHoverTexts: TList<string>;

    procedure MakeHost(const Scale: Single);
    procedure HandleTextSelected(Sender: TObject; const Selection: TPdfTextSelection);
    procedure HandleHoverChanged(Sender: TObject; const HasSegment: Boolean; const Segment: TPdfTextFragment);

    // Opens the data and waits until the first page is painted with its text known
    procedure OpenAndSettle(const Data: TBytes);
    function WordOf(const PageIndex: Integer; const Text: string; const Occurrence: Integer = 0): TPdfTextFragment;
    function DeviceBoundsOf(const PageIndex: Integer; const Quads: TArray<TPdfQuad>): TRect;
    function CenterOf(const Bounds: TRect): TPoint;
    procedure AssertOverlayCoversText(const Scale: Single);
    // The page at a zoom that leaves room beside it, compared with what the renderer makes of the same region
    procedure AssertTilesEqualRenderer(const Zoom: Single; const Image: FMX.Graphics.TBitmap; const Offset: TPoint; const ViewDevice: TSize);
    procedure CompareWithRenderer(const Image: FMX.Graphics.TBitmap; const Expected: TPdfBitmap; const Corner: TPoint);
    procedure AssertTilesEqualRendererInSnapshot(const Zoom: Single);
    class function IsRed(const Pixel: TAlphaColorRec): Boolean; static;
    class function IsBluish(const Pixel: TAlphaColorRec): Boolean; static;
    class function MaxChannelDifference(const Pixel: TAlphaColorRec; const Red, Green, Blue: Byte): Integer; static;
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
    procedure TestOverlayCoversRenderedTextAt150Percent;
    [Test]
    procedure TestTilesArePixelExactAt150Percent;
    [Test]
    procedure TestTilesAreOnWholeDevicePixelsAtAFractionalOffset;
    [Test]
    procedure TestScaleChangeRerenders;
    [Test]
    procedure TestShiftWheelScrollsSideways;
    [Test]
    procedure TestZoomListenersAreToldUntilTheyAreRemoved;
    [Test]
    procedure TestFreeTellsZoomListenersWhileTheyAreRegistered;
    [Test]
    procedure TestKeysNeedFocus;
    [Test]
    procedure TestScrollBarsFollowContent;
    [Test]
    procedure TestFreeFormWhileRendering;
    [Test]
    procedure TestDocumentSwitchDoesNotLeak;
  end;

implementation

uses
  System.Math,
  System.Diagnostics,
  FMX.Controls,
  FMX.Forms,
  FMX.Types,
  Pdf4D.Render.Renderer,
  Pdf4D.Render.Renderer.Interfaces,
  Pdf4D.Api.Document,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Common.Defines,
  Pdf4D.Viewer.Document,
  Pdf4D.Viewer.PageText,
  Pdf4D.Tests.ViewerDocuments,
  Pdf4D.Tests.RestrictedDocument;

const
  ViewWidth = 800;
  ViewHeight = 600;
  InvoiceNumber = '2024-0815';
  DarkSum = 300;
  Sentinel = 'sentinel text';
  OverlayMargin = 2;
  SearchMargin = 8;
  BluishRange = 70;
  HoverRed = 30;
  HoverGreen = 144;
  HoverBlue = 255;
  HighScale = 1.5;
  PixelTolerance = 2;
  UncoveredTolerance = 0;
  SwitchRounds = 10;
  LargeDocumentPages = 200;
  ScrollAway = 20000;
  QuietPeriodMs = 500;
  PageWidth = 612;
  PageHeight = 792;
  ZoomForTiles = 0.6;
  OffsetLeft = 1.2;
  OffsetTop = 0.8;
  ScrollBarMargin = 24;
  PointsPerInch = 72;
  LogicalPixelsPerInch = 96;
  TileBoundaries: array[0..1] of Integer = (256, 512);
  ScrollStep = 100;
  WideZoom = 4;
  WheelNotch = 120;

{ TPixelReader }

constructor TPixelReader.Create(const Bitmap: FMX.Graphics.TBitmap);
begin
  inherited Create;
  FBitmap := Bitmap;
  if not FBitmap.Map(TMapAccess.Read, FData) then
  begin
    raise EInvalidOpException.Create('The bitmap cannot be read.');
  end;
end;

destructor TPixelReader.Destroy;
begin
  FBitmap.Unmap(FData);
  inherited;
end;

function TPixelReader.Pixel(const X, Y: Integer): TAlphaColorRec;
begin
  Result.Color := FData.GetPixel(X, Y);
end;

{ TPdf4DPageViewTests }

procedure TPdf4DPageViewTests.MakeHost(const Scale: Single);
begin
  FreeAndNil(FHost);
  FSelections.Clear;
  FHoverTexts.Clear;
  FHost := TFmxTestHost.Create(ViewWidth, ViewHeight, Scale);
  const View = FHost.AddPageView;
  View.OnTextSelected := HandleTextSelected;
  View.OnHoverChanged := HandleHoverChanged;
end;

procedure TPdf4DPageViewTests.Setup;
begin
  FSelections := TList<TPdfTextSelection>.Create;
  FHoverTexts := TList<string>.Create;
  MakeHost(1);
end;

procedure TPdf4DPageViewTests.TearDown;
begin
  FreeAndNil(FHost);
  FreeAndNil(FHoverTexts);
  FreeAndNil(FSelections);
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

function TPdf4DPageViewTests.DeviceBoundsOf(const PageIndex: Integer; const Quads: TArray<TPdfQuad>): TRect;
begin
  var IsFirst := True;
  Result := TRect.Empty;
  for var Quad in Quads do
  begin
    for var Corner in [Quad.P1, Quad.P2, Quad.P3, Quad.P4] do
    begin
      const Point = FHost.PagePointToDevice(PageIndex, Corner);
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

class function TPdf4DPageViewTests.IsRed(const Pixel: TAlphaColorRec): Boolean;
begin
  Result := (Pixel.R > 200) and (Pixel.G < 80) and (Pixel.B < 80);
end;

class function TPdf4DPageViewTests.MaxChannelDifference(const Pixel: TAlphaColorRec; const Red, Green, Blue: Byte): Integer;
begin
  Result := Max(Abs(Pixel.R - Red), Max(Abs(Pixel.G - Green), Abs(Pixel.B - Blue)));
end;

class function TPdf4DPageViewTests.IsBluish(const Pixel: TAlphaColorRec): Boolean;
begin
  Result := (Abs(Pixel.R - HoverRed) + Abs(Pixel.G - HoverGreen) + Abs(Pixel.B - HoverBlue)) < BluishRange;
end;

procedure TPdf4DPageViewTests.TestOpenShowsFirstPage;
begin
  OpenAndSettle(TViewerDocuments.Invoice);

  const Bitmap = FHost.Snapshot;
  try
    const Reader = TPixelReader.Create(Bitmap);
    try
      const Center = CenterOf(DeviceBoundsOf(0, WordOf(0, 'Factuur').Quads));
      var HasDark := False;
      for var Y := Center.Y - 4 to Center.Y + 4 do
      begin
        for var X := Center.X - 4 to Center.X + 4 do
        begin
          const Pixel = Reader.Pixel(X, Y);
          HasDark := HasDark or ((Pixel.R + Pixel.G + Pixel.B) < DarkSum);
        end;
      end;
      Assert.IsTrue(HasDark, 'the word Factuur is drawn');

      const Empty = FHost.PagePointToDevice(0, TPointF.Create(500, 700));
      const Pixel = Reader.Pixel(Empty.X, Empty.Y);
      Assert.AreEqual(3 * 255, Integer(Pixel.R) + Integer(Pixel.G) + Integer(Pixel.B), 'an empty place of the page is white');
    finally
      Reader.Free;
    end;
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
  Assert.IsTrue(FHost.PageView.VScrollBar.Visible, 'the vertical scroll bar is visible');
end;

procedure TPdf4DPageViewTests.TestHoverDrawsFrame;
begin
  OpenAndSettle(TViewerDocuments.Invoice);
  const Bounds = DeviceBoundsOf(0, WordOf(0, InvoiceNumber).Quads);
  const Center = CenterOf(Bounds);

  FHost.MouseMove(FHost.DeviceToLocal(Center));

  Assert.AreEqual<Integer>(1, FHoverTexts.Count, 'one hover event');
  Assert.IsTrue(FHoverTexts[0].Contains(InvoiceNumber), 'the segment holds the number');
  FHost.PageView.Repaint;
  FHost.Pump(1);
  const Bitmap = FHost.Snapshot;
  try
    const Reader = TPixelReader.Create(Bitmap);
    try
      var HasBlue := False;
      var Area := Bounds;
      Area.Inflate(SearchMargin, SearchMargin);
      for var Y := Area.Top to Area.Bottom do
      begin
        for var X := Area.Left to Area.Right do
        begin
          HasBlue := HasBlue or IsBluish(Reader.Pixel(X, Y));
        end;
      end;
      Assert.IsTrue(HasBlue, 'the frame of the hover colour is drawn around the segment');
    finally
      Reader.Free;
    end;
  finally
    Bitmap.Free;
  end;
end;

procedure TPdf4DPageViewTests.TestClickRaisesTextSelected;
begin
  OpenAndSettle(TViewerDocuments.Invoice);
  // On the second line the number is a segment of its own
  const Center = CenterOf(DeviceBoundsOf(0, WordOf(0, InvoiceNumber, 1).Quads));

  FHost.Click(FHost.DeviceToLocal(Center));

  Assert.AreEqual<Integer>(1, FSelections.Count, 'one event');
  Assert.AreEqual(InvoiceNumber, FSelections[0].Text);
  Assert.AreEqual(0, FSelections[0].PageIndex);
end;

procedure TPdf4DPageViewTests.TestDragAndCopy;
begin
  OpenAndSettle(TViewerDocuments.Invoice);
  const First = DeviceBoundsOf(0, WordOf(0, 'Nummer:').Quads);
  const Last = DeviceBoundsOf(0, WordOf(0, InvoiceNumber, 1).Quads);
  const Y = CenterOf(First).Y;

  const HasClipboard = FHost.PutClipboardText(Sentinel);
  FHost.Drag(FHost.DeviceToLocal(TPoint.Create(First.Left + 1, Y)), FHost.DeviceToLocal(TPoint.Create(Last.Right - 1, Y)));
  FHost.PageView.SetFocus;
  Assert.IsTrue(FHost.PressKey(vkC, [ssCtrl]), 'the page view takes Ctrl+C');

  Assert.AreEqual<Integer>(1, FHost.PageView.CopiedTexts.Count, 'Ctrl+C copies once');
  Assert.AreEqual('Nummer: ' + InvoiceNumber, FHost.PageView.CopiedTexts[0]);
  var ClipboardText: string;
  if HasClipboard and FHost.TryGetClipboardText(ClipboardText) then
  begin
    Assert.AreEqual('Nummer: ' + InvoiceNumber, ClipboardText);
  end;
end;

procedure TPdf4DPageViewTests.TestCopyRespectsPermissions;
begin
  OpenAndSettle(TRestrictedDocument.Build);
  Assert.IsFalse(FHost.Document.CanCopy, 'the document does not allow copying');
  const Center = CenterOf(DeviceBoundsOf(0, WordOf(0, InvoiceNumber).Quads));

  const HasClipboard = FHost.PutClipboardText(Sentinel);
  FHost.Click(FHost.DeviceToLocal(Center));
  FHost.PageView.SetFocus;
  FHost.PressKey(vkC, [ssCtrl]);

  Assert.AreEqual<Integer>(1, FSelections.Count, 'the event comes all the same');
  Assert.AreEqual<Integer>(0, FHost.PageView.CopiedTexts.Count, 'nothing is copied');
  var ClipboardText: string;
  if HasClipboard and FHost.TryGetClipboardText(ClipboardText) then
  begin
    Assert.AreEqual(Sentinel, ClipboardText, 'the clipboard is not touched');
  end;
end;

procedure TPdf4DPageViewTests.AssertOverlayCoversText(const Scale: Single);
begin
  MakeHost(Scale);
  OpenAndSettle(TViewerDocuments.Invoice);
  const Word = WordOf(0, InvoiceNumber);
  FHost.Document.Overlays.Add(0, Word.Quads, TPdfOverlayStyle.Fill, $FFFF0000);
  FHost.PageView.Repaint;
  FHost.Pump(1);

  const Bounds = DeviceBoundsOf(0, Word.Quads);
  var Covered := Bounds;
  Covered.Inflate(-1, -1);
  // A device pixel at a higher scale is a smaller part of the text, so the margin is in device pixels of the scale
  const Margin = Ceil(OverlayMargin * Scale);
  var Allowed := Bounds;
  Allowed.Inflate(Margin, Margin);
  var Search := Bounds;
  Search.Inflate(SearchMargin, SearchMargin);

  const Bitmap = FHost.Snapshot;
  try
    const Reader = TPixelReader.Create(Bitmap);
    try
      var Uncovered := 0;
      var Spilled := 0;
      for var Y := Search.Top to Search.Bottom do
      begin
        for var X := Search.Left to Search.Right do
        begin
          const IsRedPixel = IsRed(Reader.Pixel(X, Y));
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

      Assert.AreEqual(UncoveredTolerance, Uncovered, 'every pixel inside the rectangle of the quad is covered');
      Assert.AreEqual(0, Spilled, 'nothing outside the rectangle is covered');
    finally
      Reader.Free;
    end;
  finally
    Bitmap.Free;
  end;
end;

procedure TPdf4DPageViewTests.TestOverlayCoversRenderedText;
begin
  AssertOverlayCoversText(1);
end;

procedure TPdf4DPageViewTests.TestOverlayCoversRenderedTextAt150Percent;
begin
  AssertOverlayCoversText(HighScale);
end;

procedure TPdf4DPageViewTests.AssertTilesEqualRenderer(const Zoom: Single; const Image: FMX.Graphics.TBitmap; const Offset: TPoint;
                                                       const ViewDevice: TSize);
begin
  const PixelsPerPoint = Zoom * LogicalPixelsPerInch * FHost.Scale / PointsPerInch;
  const Origin = FHost.PagePointToDevice(0, TPointF.Create(0, PageHeight));
  const BarMargin = Ceil(ScrollBarMargin * FHost.Scale);
  const CompareWidth = Min(Round(PageWidth * PixelsPerPoint), ViewDevice.cx - Origin.X - BarMargin);
  const CompareHeight = Min(Round(PageHeight * PixelsPerPoint), ViewDevice.cy - Origin.Y - BarMargin);
  Assert.IsTrue((CompareWidth > 256 * 2) and (CompareHeight > 256), 'the region covers the tile boundaries');

  const Stream = TBytesStream.Create(TViewerDocuments.Invoice);
  try
    const Document = TPdfDocument.Load(Stream, TPdfLoadOptions.Default);
    const Renderer: IPdfRenderer = TPdfRenderer.Create(Document, TFmxTestHost.NewRenderBackend);
    var Params := TPdfRenderParams.Create(PixelsPerPoint);
    Params.Region := TRect.Create(0, 0, CompareWidth, CompareHeight);
    var Expected: TPdfBitmap;
    Assert.AreEqual(Ord(TPdfRenderStatus.Completed), Ord(Renderer.RenderToBitmap(0, Params, Expected)));
    try
      CompareWithRenderer(Image, Expected, Offset + Origin);
    finally
      Expected.Free;
    end;
  finally
    Stream.Free;
  end;
end;

// Where the pixels of Expected lie in Image: from Corner on. The tile boundaries must not show as a column that deviates.
procedure TPdf4DPageViewTests.CompareWithRenderer(const Image: FMX.Graphics.TBitmap; const Expected: TPdfBitmap; const Corner: TPoint);
begin
  const Reader = TPixelReader.Create(Image);
  try
    var Differences := 0;
    const DifferentColumns = TList<Integer>.Create;
    try
      for var Y := 0 to Expected.Height - 1 do
      begin
        for var X := 0 to Expected.Width - 1 do
        begin
          const Want = Expected.GetPixel(X, Y);
          if MaxChannelDifference(Reader.Pixel(Corner.X + X, Corner.Y + Y), Want.R, Want.G, Want.B) > PixelTolerance then
          begin
            Inc(Differences);
            DifferentColumns.Add(X);
          end;
        end;
      end;
      Assert.AreEqual(0, Differences, 'the tiles are drawn pixel for pixel as the renderer made them');
      for var Boundary in TileBoundaries do
      begin
        Assert.IsFalse(DifferentColumns.Contains(Boundary), Format('no deviating column at x = %d', [Boundary]));
      end;
    finally
      DifferentColumns.Free;
    end;
  finally
    Reader.Free;
  end;
end;

procedure TPdf4DPageViewTests.AssertTilesEqualRendererInSnapshot(const Zoom: Single);
begin
  const Image = FHost.Snapshot;
  try
    AssertTilesEqualRenderer(Zoom, Image, TPoint.Zero, TSize.Create(Round(ViewWidth * FHost.Scale), Round(ViewHeight * FHost.Scale)));
  finally
    Image.Free;
  end;
end;

procedure TPdf4DPageViewTests.TestTilesArePixelExactAt150Percent;
begin
  MakeHost(HighScale);
  OpenAndSettle(TViewerDocuments.Invoice);
  FHost.PageView.Zoom := ZoomForTiles;
  Assert.IsTrue(FHost.WaitForVisibleTiles, 'tiles at the zoom');

  AssertTilesEqualRendererInSnapshot(ZoomForTiles);
end;

// A page view beside other controls sits at an offset that is no whole number of device pixels: the tiles must still lie on whole device
// pixels of the screen, so the snapshot of the parent equals what the renderer made, moved by the whole pixels that the offset rounds to
procedure TPdf4DPageViewTests.TestTilesAreOnWholeDevicePixelsAtAFractionalOffset;
begin
  MakeHost(HighScale);
  OpenAndSettle(TViewerDocuments.Invoice);
  FHost.PageView.Parent := FHost.Content;
  FHost.PageView.Align := TAlignLayout.None;
  FHost.PageView.SetBounds(OffsetLeft, OffsetTop, ViewWidth - 4, ViewHeight - 4);
  FHost.PageView.Zoom := ZoomForTiles;
  Assert.IsTrue(FHost.WaitForVisibleTiles, 'tiles at the zoom');
  // The point of this test: the offset is not on the device grid
  Assert.IsTrue(Abs(Frac(OffsetLeft * HighScale)) > 0.1, 'the left edge is between two device pixels');

  const Image = TFmxTestHost.SnapshotOf(FHost.Content);
  try
    const Offset = TPoint.Create(Round(OffsetLeft * HighScale), Round(OffsetTop * HighScale));
    const ViewDevice = TSize.Create(Round((ViewWidth - 4) * HighScale), Round((ViewHeight - 4) * HighScale));
    AssertTilesEqualRenderer(ZoomForTiles, Image, Offset, ViewDevice);
  finally
    Image.Free;
  end;
end;

procedure TPdf4DPageViewTests.TestScaleChangeRerenders;
begin
  OpenAndSettle(TViewerDocuments.Invoice);
  FHost.PageView.Zoom := ZoomForTiles;
  Assert.IsTrue(FHost.WaitForVisibleTiles, 'tiles at scale 1');
  const ContentBefore = FHost.PageView.Controller.ContentSize;
  const PageBefore = FHost.Document.CurrentPage;

  FHost.ChangeScale(HighScale);
  Assert.IsTrue(FHost.WaitForVisibleTiles, 'tiles at the new scale');

  const ContentAfter = FHost.PageView.Controller.ContentSize;
  Assert.AreEqual(Double(ContentBefore.cx * HighScale), Double(ContentAfter.cx), 2.0, 'the content is 1.5 times wider');
  Assert.AreEqual(Double(ContentBefore.cy * HighScale), Double(ContentAfter.cy), 4.0, 'the content is 1.5 times taller');
  Assert.AreEqual(PageBefore, FHost.Document.CurrentPage, 'the current page stays');
  // New tiles were asked for at the new scale: the page is as sharp as the renderer makes it, not the old tiles stretched. The page keeps its
  // place in the view, which can be partly above it now, so the comparison starts at the top.
  FHost.PageView.Controller.ScrollTo(TPoint.Zero);
  Assert.IsTrue(FHost.WaitForVisibleTiles, 'tiles at the top of the page');
  AssertTilesEqualRendererInSnapshot(ZoomForTiles);
end;

// The wheel with Shift scrolls sideways: the wheel down goes to the right, the wheel up to the left
procedure TPdf4DPageViewTests.TestShiftWheelScrollsSideways;
begin
  OpenAndSettle(TViewerDocuments.Invoice);
  FHost.PageView.Zoom := WideZoom;
  FHost.Pump(1);
  var Handled := False;

  (FHost.PageView as IControl).MouseWheel([ssShift], -WheelNotch, Handled);
  const Right = FHost.PageView.Controller.ScrollPosition.X;
  Assert.IsTrue(Handled, 'the wheel is used');
  Assert.IsTrue(Right > 0, 'the wheel down with Shift scrolls to the right');

  Handled := False;
  (FHost.PageView as IControl).MouseWheel([ssShift], WheelNotch, Handled);
  Assert.IsTrue(FHost.PageView.Controller.ScrollPosition.X < Right, 'the wheel up with Shift scrolls to the left');
end;

procedure TPdf4DPageViewTests.TestZoomListenersAreToldUntilTheyAreRemoved;
begin
  OpenAndSettle(TViewerDocuments.Invoice);
  const Probe = TZoomListenerProbe.Create(FHost.PageView);
  try
    FHost.PageView.ZoomIn;
    Assert.AreEqual(1, Probe.ZoomChanges, 'a listener is told of a change of the zoom');

    FHost.PageView.RemoveZoomListener(Probe.HandleZoomChangedForTest());
    FHost.PageView.ZoomIn;
    Assert.AreEqual(1, Probe.ZoomChanges, 'a listener that was removed hears nothing more');
  finally
    Probe.Free;
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

procedure TPdf4DPageViewTests.TestKeysNeedFocus;
begin
  OpenAndSettle(TViewerDocuments.Pages(3, PageWidth, PageHeight, 0));
  FHost.PageView.Zoom := 1;
  FHost.Pump(1);
  FHost.Form.Focused := nil;
  const Start = FHost.PageView.Controller.ScrollPosition.Y;

  FHost.PressKey(vkNext);
  Assert.AreEqual(Start, FHost.PageView.Controller.ScrollPosition.Y, 'without focus the key does nothing');

  FHost.PageView.SetFocus;
  Assert.IsTrue(FHost.PressKey(vkNext), 'with focus the page view takes the key');
  Assert.IsTrue(FHost.PageView.Controller.ScrollPosition.Y > Start, 'with focus it scrolls');
end;

procedure TPdf4DPageViewTests.TestScrollBarsFollowContent;
begin
  OpenAndSettle(TViewerDocuments.Invoice);
  FHost.PageView.Zoom := 1;
  FHost.Pump(1);
  const MaxBefore = FHost.PageView.VScrollBar.Max;

  FHost.PageView.ZoomIn;
  FHost.Pump(1);
  Assert.IsTrue(FHost.PageView.VScrollBar.Max > MaxBefore, 'the range of the bar follows the content');

  FHost.PageView.VScrollBar.Value := ScrollStep;
  Assert.AreEqual(Integer(Round(ScrollStep * FHost.Scale)), FHost.PageView.Controller.ScrollPosition.Y, 'dragging the bar scrolls the view');
end;

procedure TPdf4DPageViewTests.TestFreeFormWhileRendering;
begin
  OpenAndSettle(TViewerDocuments.Invoice);
  Assert.IsTrue(FHost.Open(TViewerDocuments.Pages(LargeDocumentPages, PageWidth, PageHeight, 0)), 'the large document opens');
  FHost.PageView.Controller.ScrollBy(0, ScrollAway);
  // The form goes while tiles are on their way, not after they came
  Assert.IsTrue(FHost.PageView.Controller.PendingTileCount > 0, 'tiles are pending when the form is freed');

  FreeAndNil(FHost);
  PumpFor(QuietPeriodMs);

  Assert.IsNull(FHost, 'the form is gone and the queue was handled without a failure');
end;

procedure TPdf4DPageViewTests.TestDocumentSwitchDoesNotLeak;
begin
  OpenAndSettle(TViewerDocuments.Invoice);
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

end.
