// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.ThumbnailsController;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  System.UITypes,
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.Cache,
  Pdf4D.Viewer.Tiles,
  Pdf4D.Viewer.ViewTransform,
  Pdf4D.Viewer.Session,
  Pdf4D.Viewer.Document,
  Pdf4D.Viewer.Painter.Interfaces;

const
  // Logical pixels
  DefaultThumbnailWidth = 120;
  DefaultSelectedColor: TAlphaColor = $FF1E90FF;
  DefaultThumbnailsBackgroundColor: TAlphaColor = $FFE0E0E0;

type
  // Shows the pages of a document as small pictures in one column, each with its page label, and marks the current page. It renders
  // only the thumbnails that are in view, in the order of the view, and keeps them in a bounded cache. Like the page view controller it
  // works in device pixels of the viewport and draws through IPdfViewPainter. UI thread only.
  TPdfThumbnailsController = class
  private
    type
      // Where the thumbnail of a page lies in the content, and what it is rendered at
      TCell = record
        // The top of the thumbnail in content pixels
        Top: Integer;
        // The pixels of the whole page at Scale
        Size: TSize;
        Scale: Single;
      end;

  private
    FHost: IPdfViewHost;
    FLink: TPdfDocumentLink;
    FPages: TArray<TPdfPageInfo>;
    FCells: TArray<TCell>;
    FIsAttached: Boolean;
    FContent: TSize;
    FViewport: TSize;
    FPixelsPerInch: Single;
    FScroll: TPoint;
    FThumbnailWidth: Integer;
    FCacheBytes: Int64;
    FSelectedColor: TAlphaColor;
    FBackgroundColor: TAlphaColor;
    FImages: TPdfLruCache<TPdfTileKey, IPdfViewImage>;
    FPending: TDictionary<Integer, IPdfViewerRequest>;
    FFailed: TDictionary<Integer, Boolean>;
    // The document was attached or its current page changed before the viewport was known: show the current page when it is
    FIsRevealPending: Boolean;

    function GetDocument: TPdf4DCustomDocument;
    procedure SetDocument(const Value: TPdf4DCustomDocument);
    procedure SetThumbnailWidth(const Value: Integer);
    procedure SetCacheBytes(const Value: Int64);
    procedure SetSelectedColor(const Value: TAlphaColor);
    procedure SetBackgroundColor(const Value: TAlphaColor);

    procedure HandleDocumentChange(const Change: TPdfDocumentChange);
    procedure AttachOpenDocument;
    procedure DetachDocumentState;
    procedure HandleCurrentPageChanged;

    function ScaledPixels(const LogicalPixels: Integer): Integer;
    function GapPixels: Integer;
    function LabelPixels: Integer;
    function ThumbnailPixels: Integer;
    function HasViewport: Boolean;
    function CenteringOffset: Integer;
    function TransformFor(const Page: TPdfPageInfo; const WidthPixels: Integer): TPdfViewTransform;
    // Shrinks a page of an extreme shape until its thumbnail is within the height, and the pixels that one thumbnail may take
    function LimitedTransform(const Page: TPdfPageInfo; const Transform: TPdfViewTransform; const Zoom: Single;
                              const WidthPixels: Integer): TPdfViewTransform;
    function MaxThumbnailPixels: Int64;
    procedure BuildLayout;
    procedure Relayout(const IsScaleChanged: Boolean);
    function ClampedScroll(const Position: TPoint): TPoint;
    function RevealPosition(const PageIndex: Integer): TPoint;

    // The thumbnail and the cell (thumbnail and label) of a page, in viewport pixels
    function ThumbRect(const PageIndex: Integer): TRect;
    function LabelRect(const PageIndex: Integer): TRect;
    function CellBottom(const PageIndex: Integer): Integer;
    function LabelOf(const PageIndex: Integer): string;
    // The pages whose cells overlap the content rows TopY..BottomY; False when there are none
    function TryFindPageRange(const TopY, BottomY: Integer; out FirstPage, LastPage: Integer): Boolean;
    function KeyOf(const PageIndex: Integer): TPdfTileKey;
    procedure InvalidateViewport;
    procedure InvalidatePage(const PageIndex: Integer);

    procedure RefreshRequests;
    procedure RequestThumbnail(const PageIndex: Integer);
    function RenderDoneEvent(const PageIndex: Integer; const Scale: Single): TPdfRenderDoneEvent;
    procedure HandleRender(const PageIndex: Integer; const Scale: Single; const Outcome: TPdfRenderResult);
    procedure CancelAllRequests;

    procedure PaintCell(const Painter: IPdfViewPainter; const PageIndex: Integer);

  public
    constructor Create(const Host: IPdfViewHost);
    destructor Destroy; override;

    procedure SetViewport(const Size: TSize; const PixelsPerInch: Single);
    // Clamped
    procedure ScrollTo(const Position: TPoint);
    procedure ScrollBy(const DeltaX, DeltaY: Integer);
    // Sets Document.CurrentPage to the page at Point; nothing when there is no page there
    procedure Click(const Point: TPointF);
    function TryFindPageAt(const Point: TPointF; out PageIndex: Integer): Boolean;
    procedure Paint(const Painter: IPdfViewPainter; const ClipRect: TRect);
    function ContentSize: TSize;
    function ScrollPosition: TPoint;
    // The bytes that the cached thumbnails take
    function CacheCost: Int64;

    // Through an internal link; a document that is open already is shown at once
    property Document: TPdf4DCustomDocument read GetDocument write SetDocument;
    // Logical pixels; the thumbnails are rendered this wide, times PixelsPerInch / 96
    property ThumbnailWidth: Integer read FThumbnailWidth write SetThumbnailWidth;
    property CacheBytes: Int64 read FCacheBytes write SetCacheBytes;
    // The frame around the thumbnail of the current page
    property SelectedColor: TAlphaColor read FSelectedColor write SetSelectedColor;
    // Around and between the thumbnails
    property BackgroundColor: TAlphaColor read FBackgroundColor write SetBackgroundColor;
  end;

implementation

uses
  System.Math;

const
  LogicalPixelsPerInch = 96;
  PointsPerInch = 72;
  // Logical pixels
  LabelHeight = 20;
  Spacing = 8;
  FrameWidth = 2;
  BytesPerPixel = 4;
  PageColor: TAlphaColor = $FFFFFFFF;
  LabelColor: TAlphaColor = $FF202020;
  // A thumbnail is at most this many times as high as it is wide: a tall page gets a narrower one
  MaxHeightFactor = 4;
  // A thumbnail that the rounding of a size left above its pixel budget is shrunk again; this many times at most
  MaxShrinkAttempts = 4;
  ShrinkMargin = 0.999;
  // The layout is added up in Int64 and kept far below the largest Integer, so that a position plus a size is still an Integer
  MaxContentPixels = High(Integer) div 4;
  // A scale that gives a page the width of exactly 1 pixel less than asked, because of the rounding down of a size, is made a little larger
  ScaleNudge = 1.000001;

{ TPdfThumbnailsController }

constructor TPdfThumbnailsController.Create(const Host: IPdfViewHost);
begin
  inherited Create;
  FHost := Host;
  FPixelsPerInch := LogicalPixelsPerInch;
  FThumbnailWidth := DefaultThumbnailWidth;
  FCacheBytes := DefaultThumbnailCacheBytes;
  FSelectedColor := DefaultSelectedColor;
  FBackgroundColor := DefaultThumbnailsBackgroundColor;
  FImages := TPdfLruCache<TPdfTileKey, IPdfViewImage>.Create(FCacheBytes);
  FPending := TDictionary<Integer, IPdfViewerRequest>.Create;
  FFailed := TDictionary<Integer, Boolean>.Create;
  FLink := TPdfDocumentLink.Create(HandleDocumentChange);
end;

destructor TPdfThumbnailsController.Destroy;
begin
  FLink.Free;
  CancelAllRequests;
  FFailed.Free;
  FPending.Free;
  FImages.Free;
  inherited;
end;

function TPdfThumbnailsController.GetDocument: TPdf4DCustomDocument;
begin
  Result := FLink.Document;
end;

procedure TPdfThumbnailsController.SetDocument(const Value: TPdf4DCustomDocument);
begin
  FLink.Document := Value;
  DetachDocumentState;

  // A document that is open already gives no change to catch up on
  const IsOpen = Assigned(Value) and (Value.State = TPdfDocumentState.Open);
  if IsOpen then
  begin
    AttachOpenDocument;
  end;
end;

procedure TPdfThumbnailsController.SetThumbnailWidth(const Value: Integer);
begin
  if Value < 1 then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('Thumbnail width %d is not above zero', [Value]);
  end;

  if Value = FThumbnailWidth then
  begin
    Exit;
  end;

  FThumbnailWidth := Value;
  Relayout(True);
end;

procedure TPdfThumbnailsController.SetCacheBytes(const Value: Int64);
begin
  if Value = FCacheBytes then
  begin
    Exit;
  end;

  FImages.MaxCost := Value;
  FCacheBytes := Value;
  // What one thumbnail may take depends on it
  Relayout(True);
end;

procedure TPdfThumbnailsController.SetBackgroundColor(const Value: TAlphaColor);
begin
  if Value = FBackgroundColor then
  begin
    Exit;
  end;

  FBackgroundColor := Value;
  InvalidateViewport;
end;

procedure TPdfThumbnailsController.SetSelectedColor(const Value: TAlphaColor);
begin
  if Value = FSelectedColor then
  begin
    Exit;
  end;

  FSelectedColor := Value;
  InvalidateViewport;
end;

procedure TPdfThumbnailsController.HandleDocumentChange(const Change: TPdfDocumentChange);
begin
  case Change of
    TPdfDocumentChange.Opened:
      AttachOpenDocument;
    TPdfDocumentChange.Opening,
    TPdfDocumentChange.OpenFailed,
    TPdfDocumentChange.Closed:
      DetachDocumentState;
    TPdfDocumentChange.CurrentPage:
      HandleCurrentPageChanged;
    TPdfDocumentChange.Overlays,
    TPdfDocumentChange.SearchResults,
    TPdfDocumentChange.CurrentSearchHit:
      // Nothing of these is shown on a thumbnail
      Exit;
  else
    raise ENotSupportedException.CreateFmt('Unsupported document change: %d', [Ord(Change)]);
  end;
end;

procedure TPdfThumbnailsController.AttachOpenDocument;
begin
  DetachDocumentState;

  FPages := Document.Pages;
  FIsAttached := True;
  FIsRevealPending := True;
  BuildLayout;
  Relayout(False);
  // Relayout reads the old content after BuildLayout has set the new one, so it sees no change: the shell learns of the content here
  FHost.ScrollStateChanged;
end;

procedure TPdfThumbnailsController.DetachDocumentState;
begin
  CancelAllRequests;
  FImages.Clear;
  FFailed.Clear;
  FIsAttached := False;
  FIsRevealPending := False;
  FPages := nil;
  FCells := nil;
  FContent := TSize.Create(0, 0);
  FScroll := TPoint.Zero;

  InvalidateViewport;
  FHost.ScrollStateChanged;
end;

procedure TPdfThumbnailsController.HandleCurrentPageChanged;
begin
  if not FIsAttached then
  begin
    Exit;
  end;

  if HasViewport then
  begin
    InvalidateViewport;
    ScrollTo(RevealPosition(Document.CurrentPage));
  end
  else
  begin
    FIsRevealPending := True;
  end;
end;

function TPdfThumbnailsController.ScaledPixels(const LogicalPixels: Integer): Integer;
begin
  Result := Round(LogicalPixels * FPixelsPerInch / LogicalPixelsPerInch);
end;

function TPdfThumbnailsController.GapPixels: Integer;
begin
  Result := ScaledPixels(Spacing);
end;

function TPdfThumbnailsController.LabelPixels: Integer;
begin
  Result := ScaledPixels(LabelHeight);
end;

function TPdfThumbnailsController.ThumbnailPixels: Integer;
begin
  Result := Max(1, ScaledPixels(FThumbnailWidth));
end;

function TPdfThumbnailsController.HasViewport: Boolean;
begin
  Result := (FViewport.cx > 0) and (FViewport.cy > 0);
end;

// A column that is narrower than the viewport is centred in it
function TPdfThumbnailsController.CenteringOffset: Integer;
begin
  Result := Max(0, (FViewport.cx - FContent.cx) div 2);
end;

// The most pixels of one thumbnail: it fits the cache, and one render of it respects the budget of a tile batch
function TPdfThumbnailsController.MaxThumbnailPixels: Int64;
begin
  Result := Max(Int64(1), Min(MaxTileBatchPixels, FCacheBytes div BytesPerPixel));
end;

// The transform of the page at the width in pixels: the scale is a render scale (72 pixels per inch is a scale of 1), so the transform
// and the render agree on the size
function TPdfThumbnailsController.TransformFor(const Page: TPdfPageInfo; const WidthPixels: Integer): TPdfViewTransform;
begin
  const IsSideways = ((Page.Rotation = 90) or (Page.Rotation = 270));
  var PageWidth := Page.CropBox.Width;
  if IsSideways then
  begin
    PageWidth := Page.CropBox.Height;
  end;

  var Zoom: Single := WidthPixels / Max(PageWidth, Single(1));
  Result := TPdfViewTransform.Create(Page, 0, Zoom, PointsPerInch);
  if Result.Size.cx < WidthPixels then
  begin
    Zoom := Zoom * ScaleNudge;
    Result := TPdfViewTransform.Create(Page, 0, Zoom, PointsPerInch);
  end;

  Result := LimitedTransform(Page, Result, Zoom, WidthPixels);
end;

function TPdfThumbnailsController.LimitedTransform(const Page: TPdfPageInfo; const Transform: TPdfViewTransform; const Zoom: Single;
                                                   const WidthPixels: Integer): TPdfViewTransform;
begin
  Result := Transform;
  var LimitedZoom := Zoom;

  const MaxHeight = Min(MaxPageEdgePixels, MaxHeightFactor * WidthPixels);
  if Result.Size.cy > MaxHeight then
  begin
    LimitedZoom := LimitedZoom * MaxHeight / Result.Size.cy;
    Result := TPdfViewTransform.Create(Page, 0, LimitedZoom, PointsPerInch);
  end;

  const MaxPixels = MaxThumbnailPixels;
  for var Attempt := 1 to MaxShrinkAttempts do
  begin
    const Pixels = Int64(Result.Size.cx) * Result.Size.cy;
    if Pixels <= MaxPixels then
    begin
      Break;
    end;

    LimitedZoom := LimitedZoom * Sqrt(MaxPixels / Pixels) * ShrinkMargin;
    Result := TPdfViewTransform.Create(Page, 0, LimitedZoom, PointsPerInch);
  end;
end;

procedure TPdfThumbnailsController.BuildLayout;
begin
  SetLength(FCells, Length(FPages));

  const Gap = GapPixels;
  var Top: Int64 := Gap;
  for var Index := 0 to High(FPages) do
  begin
    const Transform = TransformFor(FPages[Index], ThumbnailPixels);
    FCells[Index].Top := Integer(Min(Top, Int64(MaxContentPixels)));
    FCells[Index].Size := Transform.Size;
    FCells[Index].Scale := Transform.Scale;
    Top := Min(Top + Transform.Size.cy + LabelPixels + Gap, Int64(MaxContentPixels));
  end;

  FContent := TSize.Create(ThumbnailPixels + 2 * Gap, Integer(Top));
end;

// The one place that changes what the layout depends on: the document, the width of the thumbnails and the pixels per inch come here
procedure TPdfThumbnailsController.Relayout(const IsScaleChanged: Boolean);
begin
  if not FIsAttached then
  begin
    InvalidateViewport;
    Exit;
  end;

  const OldContent = FContent;
  const OldScroll = FScroll;

  if IsScaleChanged then
  begin
    CancelAllRequests;
    FImages.Clear;
    FFailed.Clear;
    BuildLayout;
    // The same part of the column stays in view
    if OldContent.cy > 0 then
    begin
      FScroll.Y := Round(Int64(FScroll.Y) * FContent.cy / OldContent.cy);
    end;
  end;

  if FIsRevealPending and HasViewport then
  begin
    FIsRevealPending := False;
    FScroll := RevealPosition(Document.CurrentPage);
  end;
  FScroll := ClampedScroll(FScroll);

  InvalidateViewport;
  RefreshRequests;

  const IsScrollStateChanged = (FContent <> OldContent) or (FScroll <> OldScroll);
  if IsScrollStateChanged then
  begin
    FHost.ScrollStateChanged;
  end;
end;

function TPdfThumbnailsController.ClampedScroll(const Position: TPoint): TPoint;
begin
  Result.X := EnsureRange(Position.X, 0, Max(0, FContent.cx - FViewport.cx));
  Result.Y := EnsureRange(Position.Y, 0, Max(0, FContent.cy - FViewport.cy));
end;

// The scroll position that shows the whole cell of a page with a gap around it; the current one when it is shown already
function TPdfThumbnailsController.RevealPosition(const PageIndex: Integer): TPoint;
begin
  Result := FScroll;
  const IsPage = (PageIndex >= 0) and (PageIndex < Length(FCells));
  if not IsPage then
  begin
    Exit;
  end;

  const Gap = GapPixels;
  const Top = FCells[PageIndex].Top - Gap;
  const Bottom = FCells[PageIndex].Top + FCells[PageIndex].Size.cy + LabelPixels + Gap;
  if Top < FScroll.Y then
  begin
    Result.Y := Top;
  end
  else if Bottom > FScroll.Y + FViewport.cy then
  begin
    // A cell that is taller than the viewport shows its top
    Result.Y := Min(Bottom - FViewport.cy, Top);
  end;
end;

function TPdfThumbnailsController.ThumbRect(const PageIndex: Integer): TRect;
begin
  const Cell = FCells[PageIndex];
  const Left = GapPixels + (ThumbnailPixels - Cell.Size.cx) div 2 + CenteringOffset - FScroll.X;
  const Top = Cell.Top - FScroll.Y;
  Result := TRect.Create(Left, Top, Left + Cell.Size.cx, Top + Cell.Size.cy);
end;

function TPdfThumbnailsController.LabelRect(const PageIndex: Integer): TRect;
begin
  const Thumb = ThumbRect(PageIndex);
  const Left = GapPixels + CenteringOffset - FScroll.X;
  Result := TRect.Create(Left, Thumb.Bottom, Left + ThumbnailPixels, Thumb.Bottom + LabelPixels);
end;

// In content pixels
function TPdfThumbnailsController.CellBottom(const PageIndex: Integer): Integer;
begin
  Result := FCells[PageIndex].Top + FCells[PageIndex].Size.cy + LabelPixels;
end;

function TPdfThumbnailsController.LabelOf(const PageIndex: Integer): string;
begin
  Result := FPages[PageIndex].Label_;
  if Result = '' then
  begin
    Result := IntToStr(PageIndex + 1);
  end;
end;

function TPdfThumbnailsController.TryFindPageRange(const TopY, BottomY: Integer; out FirstPage, LastPage: Integer): Boolean;
begin
  FirstPage := 0;
  LastPage := -1;

  // The first page whose cell ends below TopY: the cells are in order, so the bottoms are
  var LowIndex := 0;
  var HighIndex := Length(FCells);
  while LowIndex < HighIndex do
  begin
    const Middle = (LowIndex + HighIndex) div 2;
    if CellBottom(Middle) > TopY then
    begin
      HighIndex := Middle;
    end
    else
    begin
      LowIndex := Middle + 1;
    end;
  end;

  FirstPage := LowIndex;
  LastPage := FirstPage - 1;
  while (LastPage + 1 < Length(FCells)) and (FCells[LastPage + 1].Top < BottomY) do
  begin
    Inc(LastPage);
  end;
  Result := (LastPage >= FirstPage);
end;

function TPdfThumbnailsController.KeyOf(const PageIndex: Integer): TPdfTileKey;
begin
  Result := TPdfTileKey.Create(PageIndex, 0, FCells[PageIndex].Scale, 0, 0);
end;

procedure TPdfThumbnailsController.InvalidateViewport;
begin
  if HasViewport then
  begin
    FHost.Invalidate(TRect.Create(0, 0, FViewport.cx, FViewport.cy));
  end;
end;

procedure TPdfThumbnailsController.InvalidatePage(const PageIndex: Integer);
begin
  const IsPage = FIsAttached and (PageIndex >= 0) and (PageIndex < Length(FCells));
  if not IsPage then
  begin
    Exit;
  end;

  // The frame of the current page lies outside of the thumbnail
  var Area := ThumbRect(PageIndex);
  Area.Inflate(ScaledPixels(FrameWidth), ScaledPixels(FrameWidth));
  Area := TRect.Intersect(Area, TRect.Create(0, 0, FViewport.cx, FViewport.cy));
  if not Area.IsEmpty then
  begin
    FHost.Invalidate(Area);
  end;
end;

procedure TPdfThumbnailsController.SetViewport(const Size: TSize; const PixelsPerInch: Single);
begin
  TPdfViewTransform.ValidateArguments(0, 1, PixelsPerInch);

  const IsPixelsPerInchChanged = (PixelsPerInch <> FPixelsPerInch);
  FViewport := TSize.Create(Max(0, Size.cx), Max(0, Size.cy));
  FPixelsPerInch := PixelsPerInch;
  Relayout(IsPixelsPerInchChanged);
end;

procedure TPdfThumbnailsController.ScrollTo(const Position: TPoint);
begin
  if not FIsAttached then
  begin
    Exit;
  end;

  const NewScroll = ClampedScroll(Position);
  if NewScroll = FScroll then
  begin
    Exit;
  end;

  FScroll := NewScroll;
  FHost.ScrollStateChanged;
  InvalidateViewport;
  RefreshRequests;
end;

procedure TPdfThumbnailsController.ScrollBy(const DeltaX, DeltaY: Integer);
begin
  ScrollTo(TPoint.Create(FScroll.X + DeltaX, FScroll.Y + DeltaY));
end;

function TPdfThumbnailsController.TryFindPageAt(const Point: TPointF; out PageIndex: Integer): Boolean;
begin
  PageIndex := 0;
  Result := False;
  if not FIsAttached then
  begin
    Exit;
  end;

  const ContentX = Floor(Point.X) + FScroll.X - CenteringOffset;
  const ContentY = Floor(Point.Y) + FScroll.Y;
  var FirstPage: Integer;
  var LastPage: Integer;
  if not TryFindPageRange(ContentY, ContentY + 1, FirstPage, LastPage) then
  begin
    Exit;
  end;

  // The cell of a page runs from its top to the bottom of its label; the gap between two cells belongs to none
  const IsInRow = (ContentY >= FCells[FirstPage].Top);
  const IsInColumn = (ContentX >= GapPixels) and (ContentX < GapPixels + ThumbnailPixels);
  if IsInRow and IsInColumn then
  begin
    PageIndex := FirstPage;
    Result := True;
  end;
end;

procedure TPdfThumbnailsController.Click(const Point: TPointF);
begin
  var PageIndex: Integer;
  if Assigned(Document) and TryFindPageAt(Point, PageIndex) then
  begin
    Document.CurrentPage := PageIndex;
  end;
end;

function TPdfThumbnailsController.ContentSize: TSize;
begin
  Result := FContent;
end;

function TPdfThumbnailsController.ScrollPosition: TPoint;
begin
  Result := FScroll;
end;

function TPdfThumbnailsController.CacheCost: Int64;
begin
  Result := FImages.TotalCost;
end;

{ Requests }

// Cancels the renders of thumbnails that left the view and asks for those that are missing, the first in view first
procedure TPdfThumbnailsController.RefreshRequests;
begin
  var FirstPage: Integer;
  var LastPage: Integer;
  const IsAnyVisible = FIsAttached and HasViewport and TryFindPageRange(FScroll.Y, FScroll.Y + FViewport.cy, FirstPage, LastPage);
  if not IsAnyVisible then
  begin
    CancelAllRequests;
    Exit;
  end;

  for var PageIndex in FPending.Keys.ToArray do
  begin
    if (PageIndex < FirstPage) or (PageIndex > LastPage) then
    begin
      FPending[PageIndex].Cancel;
      FPending.Remove(PageIndex);
    end;
  end;

  for var PageIndex := FirstPage to LastPage do
  begin
    const IsKnown = FImages.Contains(KeyOf(PageIndex)) or FPending.ContainsKey(PageIndex) or FFailed.ContainsKey(PageIndex);
    if not IsKnown then
    begin
      RequestThumbnail(PageIndex);
    end;
  end;
end;

procedure TPdfThumbnailsController.RequestThumbnail(const PageIndex: Integer);
begin
  const Cell = FCells[PageIndex];
  const Region = TRect.Create(0, 0, Cell.Size.cx, Cell.Size.cy);
  FPending.Add(PageIndex, Document.Session.RequestRender(PageIndex, Cell.Scale, 0, Region, TPdfJobPriority.Thumbnail,
                                                         RenderDoneEvent(PageIndex, Cell.Scale)));
end;

function TPdfThumbnailsController.RenderDoneEvent(const PageIndex: Integer; const Scale: Single): TPdfRenderDoneEvent;
begin
  Result :=
    procedure(const Outcome: TPdfRenderResult)
    begin
      HandleRender(PageIndex, Scale, Outcome);
    end;
end;

procedure TPdfThumbnailsController.HandleRender(const PageIndex: Integer; const Scale: Single; const Outcome: TPdfRenderResult);
begin
  FPending.Remove(PageIndex);

  const IsCurrentScale = FIsAttached and (PageIndex < Length(FCells)) and (FCells[PageIndex].Scale = Scale);
  if not IsCurrentScale then
  begin
    Exit;
  end;

  if not Outcome.Succeeded then
  begin
    // The page stays white until the layout changes: asking again would fail again
    FFailed.AddOrSetValue(PageIndex, True);
    Exit;
  end;

  const Image = FHost.CreateImage(Outcome.Bitmap);
  const Cost = Int64(Outcome.Bitmap.Width) * Outcome.Bitmap.Height * BytesPerPixel;
  FImages.Add(KeyOf(PageIndex), Image, Cost);
  InvalidatePage(PageIndex);
end;

procedure TPdfThumbnailsController.CancelAllRequests;
begin
  for var Request in FPending.Values do
  begin
    Request.Cancel;
  end;
  FPending.Clear;
end;

{ Painting }

procedure TPdfThumbnailsController.Paint(const Painter: IPdfViewPainter; const ClipRect: TRect);
begin
  Painter.FillRect(TRectF.Create(ClipRect), FBackgroundColor);
  if not FIsAttached then
  begin
    Exit;
  end;

  var FirstPage: Integer;
  var LastPage: Integer;
  if not TryFindPageRange(ClipRect.Top + FScroll.Y, ClipRect.Bottom + FScroll.Y, FirstPage, LastPage) then
  begin
    Exit;
  end;

  for var PageIndex := FirstPage to LastPage do
  begin
    PaintCell(Painter, PageIndex);
  end;
end;

procedure TPdfThumbnailsController.PaintCell(const Painter: IPdfViewPainter; const PageIndex: Integer);
begin
  const Thumb = ThumbRect(PageIndex);
  Painter.FillRect(TRectF.Create(Thumb), PageColor);

  var Image: IPdfViewImage;
  if FImages.TryGet(KeyOf(PageIndex), Image) then
  begin
    Painter.DrawImage(Image, TRect.Create(0, 0, Image.Width, Image.Height), TRectF.Create(Thumb));
  end;

  Painter.DrawText(LabelOf(PageIndex), TRectF.Create(LabelRect(PageIndex)), LabelColor);

  if PageIndex = Document.CurrentPage then
  begin
    // The frame is drawn on the line that is half its width outside of the thumbnail
    const Width = ScaledPixels(FrameWidth);
    var Frame := TRectF.Create(Thumb);
    Frame.Inflate(Width / 2, Width / 2);
    Painter.FramePolygon([Frame.TopLeft, TPointF.Create(Frame.Right, Frame.Top), Frame.BottomRight,
                          TPointF.Create(Frame.Left, Frame.Bottom)], FSelectedColor, Width);
  end;
end;

end.
