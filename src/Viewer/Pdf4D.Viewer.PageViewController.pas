// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.PageViewController;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.Types,
  System.UITypes,
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.Quad,
  Pdf4D.Api.Page.Interfaces,
  Pdf4D.Api.TextLayout.Interfaces,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.PageText,
  Pdf4D.Viewer.Cache,
  Pdf4D.Viewer.Tiles,
  Pdf4D.Viewer.ViewTransform,
  Pdf4D.Viewer.ViewLayout,
  Pdf4D.Viewer.Session,
  Pdf4D.Viewer.Document,
  Pdf4D.Viewer.Painter.Interfaces;

const
  DefaultHoverColor: TAlphaColor = $FF1E90FF;
  DefaultSelectionColor: TAlphaColor = $663399FF;
  DefaultSearchHitColor: TAlphaColor = $66FFD700;
  DefaultCurrentSearchHitColor: TAlphaColor = $99FF8C00;
  DefaultBackgroundColor: TAlphaColor = $FFE0E0E0;

type
  // Shows the pages of a document in a viewport: it places the pages, asks the session for the tiles that the viewport needs, keeps
  // them in a bounded cache and paints them with the overlays and search hits over them. It knows the viewport only in device pixels
  // and draws through IPdfViewPainter, so a framework shell is a thin layer around it. UI thread only.
  TPdfPageViewController = class
  private
    type
      // One RequestTiles call and the tiles of it that have not arrived
      TTileRequest = class
      public
        Request: IPdfViewerRequest;
        PageIndex: Integer;
        Rotation: Integer;
        Scale: Single;
        Keys: TArray<TPdfTileKey>;
        Remaining: Integer;
      end;

      TTileLayer = record
        IsValid: Boolean;
        Scale: Single;
        Rotation: Integer;
      end;

      // The scales at which tiles of a page arrived last; the older one is what a page shows until the tiles of a new scale arrive
      TPageLayers = record
        Latest: TTileLayer;
        Previous: TTileLayer;
      end;

      // The PDF point that stays at the same place in the viewport when the layout changes
      TAnchor = record
        IsValid: Boolean;
        PageIndex: Integer;
        PdfPoint: TPointF;
        ViewportPoint: TPointF;
      end;

      TPageWant = record
        PageIndex: Integer;
        Scale: Single;
        Rotation: Integer;
        Tiles: TArray<TPoint>;
        Priority: TPdfJobPriority;
      end;

      // Where a visible page lies in the viewport
      TPlacement = record
        PageIndex: Integer;
        Origin: TPointF;
        Transform: TPdfViewTransform;
      end;

  private
    FHost: IPdfViewHost;
    FLink: TPdfDocumentLink;
    FPages: TArray<TPdfPageInfo>;
    FLayout: TPdfViewLayout;
    FViewport: TSize;
    FPixelsPerInch: Single;
    FScroll: TPoint;
    FZoom: Single;
    FZoomMode: TPdfZoomMode;
    FViewRotation: Integer;
    FScrollMode: TPdfScrollMode;
    FTileCacheBytes: Int64;
    FTiles: TPdfLruCache<TPdfTileKey, IPdfViewImage>;
    FTileRequests: TObjectList<TTileRequest>;
    FPendingTiles: TDictionary<TPdfTileKey, TTileRequest>;
    FFailedTiles: TDictionary<TPdfTileKey, Boolean>;
    FTextRequests: TDictionary<Integer, IPdfViewerRequest>;
    FPageLayers: TDictionary<Integer, TPageLayers>;
    // The document tells the page that it is at the cursor, or the controller moves the cursor itself: either way it must not scroll
    FPageSyncLock: Integer;
    FInitialScrollPending: Boolean;
    FHoverColor: TAlphaColor;
    FSelectionColor: TAlphaColor;
    FSearchHitColor: TAlphaColor;
    FCurrentSearchHitColor: TAlphaColor;
    FBackgroundColor: TAlphaColor;
    FOnZoomChanged: TNotifyEvent;
    FHoverEnabled: Boolean;
    FSelectionEnabled: Boolean;
    FFollowInternalLinks: Boolean;
    FOnTextSelected: TPdfTextSelectedEvent;
    FOnHoverChanged: TPdfHoverChangedEvent;
    FOnLinkClick: TPdfLinkClickEvent;
    FHasHover: Boolean;
    FHoverPage: Integer;
    FHoverSegment: TPdfTextFragment;
    FCursor: TPdfCursorKind;
    FHasSelection: Boolean;
    FSelection: TPdfTextSelection;
    FIsPressed: Boolean;
    FIsDragging: Boolean;
    FDownPoint: TPointF;
    // The text of the page where a press started, and the word it started at; nil when the press can select nothing
    FAnchorText: IPdfPageText;
    FAnchorPage: Integer;
    FAnchorWord: Integer;
    // What the last layout was made with: failed tiles are tried again only when this changes
    FLaidOutZoom: Single;
    FLaidOutPixelsPerInch: Single;
    FLaidOutRotation: Integer;
    FNotifiedZoom: Single;
    FNotifiedZoomMode: TPdfZoomMode;
    // The part of a notch of the wheel that has not made a zoom step yet; the sign is the direction
    FWheelRemainder: Integer;

    function GetDocument: TPdf4DCustomDocument;
    procedure SetDocument(const Value: TPdf4DCustomDocument);
    procedure SetZoom(const Value: Single);
    procedure SetZoomMode(const Value: TPdfZoomMode);
    procedure SetViewRotation(const Value: Integer);
    procedure SetScrollMode(const Value: TPdfScrollMode);
    procedure SetTileCacheBytes(const Value: Int64);
    procedure SetHoverEnabled(const Value: Boolean);
    procedure SetSelectionEnabled(const Value: Boolean);

    procedure HandleDocumentChange(const Change: TPdfDocumentChange);
    procedure AttachOpenDocument;
    procedure DetachDocumentState;
    procedure HandleCurrentPageChanged;

    function HasViewport: Boolean;
    function ViewportContentRect: TRect;
    function CenteringOffset: Integer;
    function ViewportCenter: TPointF;
    function ViewportToContent(const Point: TPointF): TPointF;
    function ClampedScroll(const Position: TPoint): TPoint;
    function PageRectInViewport(const PageIndex: Integer; out Rect: TRect): Boolean;

    function CaptureAnchor(const ViewportPoint: TPointF): TAnchor;
    procedure RestoreAnchor(const Anchor: TAnchor);
    procedure Relayout(const Anchor: TAnchor);
    procedure UpdateLayoutAndFit;
    procedure ApplyInitialScroll;
    procedure ScrollToPage(const PageIndex: Integer);
    procedure SyncCurrentPage;
    procedure InvalidateViewport;
    procedure ZoomToFactor(const NewZoom: Single; const ViewportPoint: TPointF);
    procedure NotifyZoomChanged;
    function NextZoomStep(const Upwards: Boolean): Single;

    procedure RefreshRequests;
    function WantOf(const PageIndex: Integer; const AreaInPage: TRect; const Priority: TPdfJobPriority): TPageWant;
    function VisibleWant(const PageIndex: Integer): TPageWant;
    function PrefetchWant(const PageIndex: Integer; const IsBelow: Boolean): TPageWant;
    procedure CollectWants(const VisiblePages: TArray<Integer>; const Wants: TList<TPageWant>);
    procedure RequestWants(const Wants: TList<TPageWant>; const Priority: TPdfJobPriority);
    procedure CancelUnneeded(const Wants: TList<TPageWant>; const VisiblePages: TArray<Integer>);
    procedure CancelUnneededTiles(const Wants: TList<TPageWant>);
    procedure CancelUnneededTexts(const VisiblePages: TArray<Integer>);
    function IsRequestNeeded(const Request: TTileRequest; const Needed: TDictionary<TPdfTileKey, Boolean>): Boolean;
    class function IsPageIn(const Pages: TArray<Integer>; const PageIndex: Integer): Boolean; static;
    procedure CancelTileRequest(const Request: TTileRequest);
    procedure CancelAllRequests;
    procedure RequestMissingTiles(const Want: TPageWant);
    procedure StartTileRequest(const Want: TPageWant; const Missing: TList<TPoint>; const Keys: TList<TPdfTileKey>);
    function TileDoneEvent(const Request: TTileRequest): TPdfTileDoneEvent;
    procedure HandleTile(const Request: TTileRequest; const Tile: TPoint; const Outcome: TPdfRenderResult);
    procedure StoreTile(const Key: TPdfTileKey; const Outcome: TPdfRenderResult);
    procedure RememberLayer(const Key: TPdfTileKey);
    procedure InvalidateTile(const Key: TPdfTileKey);
    procedure RequestPageTexts(const VisiblePages: TArray<Integer>);

    function PlacementsOf(const Pages: TArray<Integer>): TArray<TPlacement>;
    procedure PaintPage(const Painter: IPdfViewPainter; const Placement: TPlacement; const ClipRect: TRect);
    procedure PaintTile(const Painter: IPdfViewPainter; const Placement: TPlacement; const Column, Row: Integer);
    procedure PaintFallback(const Painter: IPdfViewPainter; const Placement: TPlacement; const TileRect: TRect);
    procedure PaintFallbackTile(const Painter: IPdfViewPainter; const Placement: TPlacement; const Layer: TTileLayer; const OldTile: TPoint;
                                const Source: TRect; const Ratio: TPointF);
    class function IsUsableLayer(const Layer: TTileLayer; const Transform: TPdfViewTransform): Boolean; static;
    function TryGetFallbackLayer(const PageIndex: Integer; const Transform: TPdfViewTransform; out Layer: TTileLayer): Boolean;
    procedure PaintSearchHits(const Painter: IPdfViewPainter; const Placements: TArray<TPlacement>);
    procedure PaintQuads(const Painter: IPdfViewPainter; const Placement: TPlacement; const Quads: TArray<TPdfQuad>; const Color: TAlphaColor);
    class function TryFindPlacement(const Placements: TArray<TPlacement>; const PageIndex: Integer; out Placement: TPlacement): Boolean; static;
    procedure PaintSelection(const Painter: IPdfViewPainter; const Placements: TArray<TPlacement>);
    procedure PaintHover(const Painter: IPdfViewPainter; const Placements: TArray<TPlacement>);
    procedure PaintOverlays(const Painter: IPdfViewPainter; const Placements: TArray<TPlacement>);
    procedure PaintOverlay(const Painter: IPdfViewPainter; const Placement: TPlacement; const Overlay: TPdfOverlay);
    procedure PaintEllipseOverlay(const Painter: IPdfViewPainter; const Placement: TPlacement; const Overlay: TPdfOverlay);
    class function OffsetPoints(const Points: TArray<TPointF>; const Origin: TPointF): TArray<TPointF>; static;
    // The corners of the quad in viewport pixels
    class function ViewPolygonOf(const Placement: TPlacement; const Quad: TPdfQuad): TArray<TPointF>; static;
    // The points of all quads of a page in viewport pixels
    class function ViewPointsOf(const Placement: TPlacement; const Quads: TArray<TPdfQuad>): TArray<TPointF>; static;
    // False without points
    class function TryGetBoundsOf(const Points: TArray<TPointF>; out Bounds: TRectF): Boolean; static;

    function ScaledPixels(const LogicalPixels: Single): Single;
    function TryGetViewBounds(const PageIndex: Integer; const Quads: TArray<TPdfQuad>; out Bounds: TRectF): Boolean;
    function TryGetTextAt(const Point: TPointF; out PageIndex: Integer; out PagePoint: TPointF; out PageText: IPdfPageText): Boolean;
    procedure InvalidateQuads(const PageIndex: Integer; const Quads: TArray<TPdfQuad>);
    procedure UpdateHover(const Point: TPointF);
    procedure SetHover(const PageIndex: Integer; const Segment: TPdfTextFragment);
    procedure ClearHover;
    procedure UpdateCursor(const Point: TPointF);
    procedure ChangeCursor(const Kind: TPdfCursorKind);
    procedure SetSelection(const Selection: TPdfTextSelection);
    procedure BeginPress(const Point: TPointF);
    procedure UpdateDrag(const Point: TPointF);
    function TryGetFocusWord(const Point: TPointF; out WordIndex: Integer): Boolean;
    procedure FinishClick(const Point: TPointF);
    procedure SelectSegment(const PageIndex: Integer; const Segment: TPdfTextFragment);
    procedure RaiseLinkClick(const Link: TPdfLink);
    procedure ResetInput;
    procedure ZoomByWheel(const WheelDelta: Integer; const Point: TPointF);
    procedure SelectAllOnCurrentPage;

  public
    constructor Create(const Host: IPdfViewHost);
    destructor Destroy; override;

    // A change of PixelsPerInch re-renders at the new scale and keeps the page in view
    procedure SetViewport(const Size: TSize; const PixelsPerInch: Single);
    // Clamped
    procedure ScrollTo(const Position: TPoint);
    procedure ScrollBy(const DeltaX, DeltaY: Integer);
    procedure GoToPage(const PageIndex: Integer);
    // Nothing when the quads are fully in view; else centred, as far as the content allows
    procedure ScrollIntoView(const PageIndex: Integer; const Quads: TArray<TPdfQuad>);
    procedure ZoomIn;
    procedure ZoomOut;
    // Keeps the PDF point under ViewportPoint in place
    procedure ZoomAt(const Zoom: Single; const ViewportPoint: TPointF);
    procedure RotateClockwise;
    procedure RotateCounterclockwise;
    // Pointer input in viewport pixels. Nothing here requests anything: hover, selection and links use the page text that is cached.
    procedure MouseMove(const Point: TPointF);
    // Left button
    procedure MouseDown(const Point: TPointF);
    procedure MouseUp(const Point: TPointF);
    procedure MouseLeave;
    // 120 per notch
    procedure MouseWheel(const WheelDelta: Integer; const Ctrl: Boolean; const Point: TPointF);
    // True when handled
    function KeyDown(const Key: TPdfViewerKey): Boolean;
    procedure ClearSelection;
    function TryGetSelection(out Selection: TPdfTextSelection): Boolean;
    function TryGetHoverSegment(out Segment: TPdfTextFragment): Boolean;
    function CursorKind: TPdfCursorKind;
    procedure Paint(const Painter: IPdfViewPainter; const ClipRect: TRect);
    function ContentSize: TSize;
    function ScrollPosition: TPoint;
    // The bytes that the cached tiles take
    function TileCacheCost: Int64;
    // PagePoint is in PDF user space
    function ViewportToPage(const Point: TPointF; out PageIndex: Integer; out PagePoint: TPointF): Boolean;
    // The inverse of ViewportToPage for a page that is laid out; the point may lie outside the viewport
    function TryPageToViewport(const PageIndex: Integer; const PagePoint: TPointF; out Point: TPointF): Boolean;
    // The tiles that were asked for and have not arrived
    function PendingTileCount: Integer;

    // Through an internal link; a document that is already open is shown at once
    property Document: TPdf4DCustomDocument read GetDocument write SetDocument;
    // Setting it sets ZoomMode to Factor; clamped to MinZoom..MaxZoom
    property Zoom: Single read FZoom write SetZoom;
    property ZoomMode: TPdfZoomMode read FZoomMode write SetZoomMode;
    // 0, 90, 180 or 270
    property ViewRotation: Integer read FViewRotation write SetViewRotation;
    property ScrollMode: TPdfScrollMode read FScrollMode write SetScrollMode;
    property TileCacheBytes: Int64 read FTileCacheBytes write SetTileCacheBytes;
    property HoverEnabled: Boolean read FHoverEnabled write SetHoverEnabled;
    property SelectionEnabled: Boolean read FSelectionEnabled write SetSelectionEnabled;
    // A GoTo link sets Document.CurrentPage
    property FollowInternalLinks: Boolean read FFollowInternalLinks write FFollowInternalLinks;
    property HoverColor: TAlphaColor read FHoverColor write FHoverColor;
    property SelectionColor: TAlphaColor read FSelectionColor write FSelectionColor;
    property SearchHitColor: TAlphaColor read FSearchHitColor write FSearchHitColor;
    property CurrentSearchHitColor: TAlphaColor read FCurrentSearchHitColor write FCurrentSearchHitColor;
    property BackgroundColor: TAlphaColor read FBackgroundColor write FBackgroundColor;
    property OnTextSelected: TPdfTextSelectedEvent read FOnTextSelected write FOnTextSelected;
    property OnHoverChanged: TPdfHoverChangedEvent read FOnHoverChanged write FOnHoverChanged;
    property OnLinkClick: TPdfLinkClickEvent read FOnLinkClick write FOnLinkClick;
    // A change of Zoom or of ZoomMode
    property OnZoomChanged: TNotifyEvent read FOnZoomChanged write FOnZoomChanged;
  end;

implementation

uses
  System.Math;

const
  // Two steps are the same when they differ less than this
  ZoomStepTolerance = 0.0001;
  PageColor: TAlphaColor = $FFFFFFFF;
  LogicalPixelsPerInch = 96;
  BytesPerPixel = 4;
  // The width of the frame of an overlay, in logical pixels
  OverlayFrameWidth = 2;
  // A circle through the corners of a square is this much wider than the square
  EllipseEnlargement = 1.41421356237;
  // What a scroll position may reach, far below what an Integer holds
  MaxScrollValue = 1.0E9;
  RightAngle = 90;
  FullTurn = 360;
  // Logical pixels
  KeyScrollStep = 40;
  ClickTolerance = 4;
  WheelNotch = 120;
  WheelLinesPerNotch = 3;
  // The scale of a tile layer is pixels per point, so its size is that of a page at 72 pixels per inch
  LayerPixelsPerInch = 72;

{ TPdfPageViewController }

constructor TPdfPageViewController.Create(const Host: IPdfViewHost);
begin
  inherited Create;
  FHost := Host;
  FPixelsPerInch := LogicalPixelsPerInch;
  FZoom := 1;
  FNotifiedZoom := 1;
  FNotifiedZoomMode := TPdfZoomMode.FitWidth;
  FLaidOutZoom := 1;
  FLaidOutPixelsPerInch := LogicalPixelsPerInch;
  FZoomMode := TPdfZoomMode.FitWidth;
  FScrollMode := TPdfScrollMode.Continuous;
  FTileCacheBytes := DefaultTileCacheBytes;
  FHoverColor := DefaultHoverColor;
  FSelectionColor := DefaultSelectionColor;
  FSearchHitColor := DefaultSearchHitColor;
  FCurrentSearchHitColor := DefaultCurrentSearchHitColor;
  FBackgroundColor := DefaultBackgroundColor;
  FHoverEnabled := True;
  FSelectionEnabled := True;
  FFollowInternalLinks := True;
  FCursor := TPdfCursorKind.Default;
  FTiles := TPdfLruCache<TPdfTileKey, IPdfViewImage>.Create(FTileCacheBytes);
  FTileRequests := TObjectList<TTileRequest>.Create(True);
  FPendingTiles := TDictionary<TPdfTileKey, TTileRequest>.Create;
  FFailedTiles := TDictionary<TPdfTileKey, Boolean>.Create;
  FTextRequests := TDictionary<Integer, IPdfViewerRequest>.Create;
  FPageLayers := TDictionary<Integer, TPageLayers>.Create;
  FLink := TPdfDocumentLink.Create(HandleDocumentChange);
end;

destructor TPdfPageViewController.Destroy;
begin
  FLink.Free;
  CancelAllRequests;
  FLayout.Free;
  FPageLayers.Free;
  FTextRequests.Free;
  FFailedTiles.Free;
  FPendingTiles.Free;
  FTileRequests.Free;
  FTiles.Free;
  inherited;
end;

function TPdfPageViewController.GetDocument: TPdf4DCustomDocument;
begin
  Result := FLink.Document;
end;

procedure TPdfPageViewController.SetDocument(const Value: TPdf4DCustomDocument);
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

procedure TPdfPageViewController.SetZoom(const Value: Single);
begin
  ZoomToFactor(Value, ViewportCenter);
end;

procedure TPdfPageViewController.SetZoomMode(const Value: TPdfZoomMode);
begin
  if Value = FZoomMode then
  begin
    Exit;
  end;

  const Anchor = CaptureAnchor(ViewportCenter);
  FZoomMode := Value;
  Relayout(Anchor);
end;

procedure TPdfPageViewController.SetViewRotation(const Value: Integer);
begin
  TPdfViewTransform.ValidateArguments(Value, 1, 1);
  if Value = FViewRotation then
  begin
    Exit;
  end;

  const Anchor = CaptureAnchor(ViewportCenter);
  FViewRotation := Value;
  Relayout(Anchor);
end;

procedure TPdfPageViewController.SetScrollMode(const Value: TPdfScrollMode);
begin
  if Value = FScrollMode then
  begin
    Exit;
  end;

  FScrollMode := Value;
  FInitialScrollPending := True;
  Relayout(Default(TAnchor));
end;

procedure TPdfPageViewController.SetTileCacheBytes(const Value: Int64);
begin
  FTiles.MaxCost := Value;
  FTileCacheBytes := Value;
end;

procedure TPdfPageViewController.SetHoverEnabled(const Value: Boolean);
begin
  FHoverEnabled := Value;
  if not Value then
  begin
    ClearHover;
  end;
end;

procedure TPdfPageViewController.SetSelectionEnabled(const Value: Boolean);
begin
  FSelectionEnabled := Value;
  if not Value then
  begin
    ClearSelection;
  end;
end;

procedure TPdfPageViewController.HandleDocumentChange(const Change: TPdfDocumentChange);
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
      InvalidateViewport;
  else
    raise ENotSupportedException.CreateFmt('Unsupported document change: %d', [Ord(Change)]);
  end;
end;

procedure TPdfPageViewController.AttachOpenDocument;
begin
  DetachDocumentState;

  FPages := Document.Pages;
  FLayout := TPdfViewLayout.Create(FPages);
  FInitialScrollPending := True;
  Relayout(Default(TAnchor));
end;

procedure TPdfPageViewController.DetachDocumentState;
begin
  ResetInput;
  CancelAllRequests;
  FTiles.Clear;
  FFailedTiles.Clear;
  FPageLayers.Clear;
  FreeAndNil(FLayout);
  FPages := nil;
  FScroll := TPoint.Zero;

  InvalidateViewport;
  FHost.ScrollStateChanged;
end;

procedure TPdfPageViewController.HandleCurrentPageChanged;
begin
  if not Assigned(FLayout) then
  begin
    Exit;
  end;

  if FScrollMode = TPdfScrollMode.SinglePage then
  begin
    FInitialScrollPending := True;
    Relayout(Default(TAnchor));
    Exit;
  end;

  const ContentRect = ViewportContentRect;
  const MostVisible = FLayout.MostVisiblePage(ContentRect);
  const IsOurOwnChange = (FPageSyncLock > 0);
  const IsAlreadyThere = (Document.CurrentPage = MostVisible);
  if IsOurOwnChange or IsAlreadyThere then
  begin
    Exit;
  end;

  ScrollToPage(Document.CurrentPage);
end;

function TPdfPageViewController.HasViewport: Boolean;
begin
  Result := (FViewport.cx > 0) and (FViewport.cy > 0);
end;

function TPdfPageViewController.ViewportContentRect: TRect;
begin
  Result := TRect.Create(FScroll.X, FScroll.Y, FScroll.X + FViewport.cx, FScroll.Y + FViewport.cy);
end;

// A page that is narrower than the viewport is centred in it
function TPdfPageViewController.CenteringOffset: Integer;
begin
  Result := 0;
  if Assigned(FLayout) then
  begin
    const Content = FLayout.ContentSize;
    Result := Max(0, (FViewport.cx - Content.cx) div 2);
  end;
end;

function TPdfPageViewController.ViewportCenter: TPointF;
begin
  Result := TPointF.Create(FViewport.cx / 2, FViewport.cy / 2);
end;

function TPdfPageViewController.ViewportToContent(const Point: TPointF): TPointF;
begin
  Result := TPointF.Create(Point.X + FScroll.X - CenteringOffset, Point.Y + FScroll.Y);
end;

function TPdfPageViewController.ClampedScroll(const Position: TPoint): TPoint;
begin
  var Content := TSize.Create(0, 0);
  if Assigned(FLayout) then
  begin
    Content := FLayout.ContentSize;
  end;

  Result.X := EnsureRange(Position.X, 0, Max(0, Content.cx - FViewport.cx));
  Result.Y := EnsureRange(Position.Y, 0, Max(0, Content.cy - FViewport.cy));
end;

function TPdfPageViewController.PageRectInViewport(const PageIndex: Integer; out Rect: TRect): Boolean;
begin
  Result := Assigned(FLayout) and FLayout.TryGetPageRect(PageIndex, Rect);
  if Result then
  begin
    Rect.Offset(CenteringOffset - FScroll.X, -FScroll.Y);
  end;
end;

function TPdfPageViewController.CaptureAnchor(const ViewportPoint: TPointF): TAnchor;
begin
  Result := Default(TAnchor);
  if (not Assigned(FLayout)) or (not HasViewport) then
  begin
    Exit;
  end;

  const Content = ViewportToContent(ViewportPoint);
  const ContentPoint = TPoint.Create(Floor(Content.X), Floor(Content.Y));
  var PageIndex: Integer;
  const IsOnPage = FLayout.TryFindPageAt(ContentPoint, PageIndex);
  if not IsOnPage then
  begin
    const ContentRect = ViewportContentRect;
    PageIndex := FLayout.MostVisiblePage(ContentRect);
  end;

  var Rect: TRect;
  if not FLayout.TryGetPageRect(PageIndex, Rect) then
  begin
    Exit;
  end;

  Result.IsValid := True;
  Result.PageIndex := PageIndex;
  Result.ViewportPoint := ViewportPoint;

  const Transform = FLayout.Transform(PageIndex);
  const OnPage = TPointF.Create(Content.X - Rect.Left, Content.Y - Rect.Top);
  Result.PdfPoint := Transform.ViewToPage(OnPage);
end;

procedure TPdfPageViewController.RestoreAnchor(const Anchor: TAnchor);
begin
  var Rect: TRect;
  if (not Anchor.IsValid) or (not FLayout.TryGetPageRect(Anchor.PageIndex, Rect)) then
  begin
    Exit;
  end;

  const Transform = FLayout.Transform(Anchor.PageIndex);
  const View = Transform.PageToView(Anchor.PdfPoint);
  const ScrollX = Rect.Left + View.X + CenteringOffset - Anchor.ViewportPoint.X;
  const ScrollY = Rect.Top + View.Y - Anchor.ViewportPoint.Y;
  const LimitedX = EnsureRange(ScrollX, -MaxScrollValue, MaxScrollValue);
  const LimitedY = EnsureRange(ScrollY, -MaxScrollValue, MaxScrollValue);
  FScroll.X := Round(LimitedX);
  FScroll.Y := Round(LimitedY);
end;

// The one place that changes the layout: zoom, rotation, mode, pixels per inch and viewport size all come here
procedure TPdfPageViewController.Relayout(const Anchor: TAnchor);
begin
  if not Assigned(FLayout) then
  begin
    Exit;
  end;

  const OldContent = FLayout.ContentSize;
  const OldScroll = FScroll;

  UpdateLayoutAndFit;
  const IsScaleChanged = (FZoom <> FLaidOutZoom) or (FPixelsPerInch <> FLaidOutPixelsPerInch) or (FViewRotation <> FLaidOutRotation);
  if IsScaleChanged then
  begin
    FFailedTiles.Clear;
    FLaidOutZoom := FZoom;
    FLaidOutPixelsPerInch := FPixelsPerInch;
    FLaidOutRotation := FViewRotation;
  end;

  RestoreAnchor(Anchor);
  ApplyInitialScroll;
  FScroll := ClampedScroll(FScroll);

  InvalidateViewport;
  RefreshRequests;

  const IsScrollStateChanged = (FLayout.ContentSize <> OldContent) or (FScroll <> OldScroll);
  if IsScrollStateChanged then
  begin
    FHost.ScrollStateChanged;
  end;

  NotifyZoomChanged;
end;

procedure TPdfPageViewController.NotifyZoomChanged;
begin
  const IsTold = (FZoom = FNotifiedZoom) and (FZoomMode = FNotifiedZoomMode);
  if IsTold then
  begin
    Exit;
  end;

  FNotifiedZoom := FZoom;
  FNotifiedZoomMode := FZoomMode;
  if Assigned(FOnZoomChanged) then
  begin
    FOnZoomChanged(Self);
  end;
end;

procedure TPdfPageViewController.UpdateLayoutAndFit;
begin
  const CurrentPage = Document.CurrentPage;
  FLayout.Update(FViewRotation, FZoom, FPixelsPerInch, FScrollMode, CurrentPage);
  if (FZoomMode = TPdfZoomMode.Factor) or (not HasViewport) or (Length(FPages) = 0) then
  begin
    Exit;
  end;

  // The fit needs the page size at the new rotation and PixelsPerInch, which the layout has now
  const FitZoom = FLayout.ZoomToFit(FZoomMode, FViewport, CurrentPage);
  if FitZoom <> FZoom then
  begin
    FZoom := FitZoom;
    FLayout.Update(FViewRotation, FZoom, FPixelsPerInch, FScrollMode, CurrentPage);
  end;
end;

procedure TPdfPageViewController.ApplyInitialScroll;
begin
  if (not FInitialScrollPending) or (not HasViewport) then
  begin
    Exit;
  end;

  FInitialScrollPending := False;
  FScroll := TPoint.Zero;

  var Rect: TRect;
  const IsContinuous = (FScrollMode = TPdfScrollMode.Continuous);
  if IsContinuous and FLayout.TryGetPageRect(Document.CurrentPage, Rect) then
  begin
    FScroll.Y := Max(0, Rect.Top - FLayout.Gap);
  end;
end;

procedure TPdfPageViewController.ScrollToPage(const PageIndex: Integer);
begin
  var Rect: TRect;
  if not FLayout.TryGetPageRect(PageIndex, Rect) then
  begin
    Exit;
  end;

  Inc(FPageSyncLock);
  try
    ScrollTo(TPoint.Create(FScroll.X, Rect.Top - FLayout.Gap));
  finally
    Dec(FPageSyncLock);
  end;
end;

// The cursor of the document follows the page that is most in view
procedure TPdfPageViewController.SyncCurrentPage;
begin
  const IsSynchronised = (FScrollMode = TPdfScrollMode.Continuous) and (FPageSyncLock = 0);
  if (not Assigned(FLayout)) or (not IsSynchronised) then
  begin
    Exit;
  end;

  const ContentRect = ViewportContentRect;
  const MostVisible = FLayout.MostVisiblePage(ContentRect);
  if MostVisible = Document.CurrentPage then
  begin
    Exit;
  end;

  Inc(FPageSyncLock);
  try
    Document.CurrentPage := MostVisible;
  finally
    Dec(FPageSyncLock);
  end;
end;

procedure TPdfPageViewController.InvalidateViewport;
begin
  if HasViewport then
  begin
    FHost.Invalidate(TRect.Create(0, 0, FViewport.cx, FViewport.cy));
  end;
end;

procedure TPdfPageViewController.SetViewport(const Size: TSize; const PixelsPerInch: Single);
begin
  TPdfViewTransform.ValidateArguments(0, 1, PixelsPerInch);

  const Anchor = CaptureAnchor(ViewportCenter);
  FViewport := TSize.Create(Max(0, Size.cx), Max(0, Size.cy));
  FPixelsPerInch := PixelsPerInch;
  Relayout(Anchor);
end;

procedure TPdfPageViewController.ScrollTo(const Position: TPoint);
begin
  if not Assigned(FLayout) then
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
  SyncCurrentPage;
end;

procedure TPdfPageViewController.ScrollBy(const DeltaX, DeltaY: Integer);
begin
  ScrollTo(TPoint.Create(FScroll.X + DeltaX, FScroll.Y + DeltaY));
end;

procedure TPdfPageViewController.GoToPage(const PageIndex: Integer);
begin
  if not Assigned(FLayout) then
  begin
    Exit;
  end;

  const Page = EnsureRange(PageIndex, 0, Length(FPages) - 1);
  if FScrollMode = TPdfScrollMode.SinglePage then
  begin
    Document.CurrentPage := Page;
    Exit;
  end;

  ScrollToPage(Page);
  Inc(FPageSyncLock);
  try
    Document.CurrentPage := Page;
  finally
    Dec(FPageSyncLock);
  end;
end;

procedure TPdfPageViewController.ZoomIn;
begin
  const Step = NextZoomStep(True);
  ZoomToFactor(Step, ViewportCenter);
end;

procedure TPdfPageViewController.ZoomOut;
begin
  const Step = NextZoomStep(False);
  ZoomToFactor(Step, ViewportCenter);
end;

procedure TPdfPageViewController.ZoomAt(const Zoom: Single; const ViewportPoint: TPointF);
begin
  ZoomToFactor(Zoom, ViewportPoint);
end;

function TPdfPageViewController.NextZoomStep(const Upwards: Boolean): Single;
begin
  if Upwards then
  begin
    for var Percentage in PdfZoomSteps do
    begin
      const Step: Single = Percentage / PercentPerFactor;
      if Step > FZoom + ZoomStepTolerance then
      begin
        Exit(Step);
      end;
    end;
    Exit(MaxZoom);
  end;

  for var Index := High(PdfZoomSteps) downto Low(PdfZoomSteps) do
  begin
    const Step: Single = PdfZoomSteps[Index] / PercentPerFactor;
    if Step < FZoom - ZoomStepTolerance then
    begin
      Exit(Step);
    end;
  end;
  Result := MinZoom;
end;

procedure TPdfPageViewController.ZoomToFactor(const NewZoom: Single; const ViewportPoint: TPointF);
begin
  const Anchor = CaptureAnchor(ViewportPoint);
  FZoomMode := TPdfZoomMode.Factor;
  FZoom := EnsureRange(NewZoom, MinZoom, MaxZoom);

  if Assigned(FLayout) then
  begin
    Relayout(Anchor);
  end
  else
  begin
    NotifyZoomChanged;
  end;
end;

procedure TPdfPageViewController.RotateClockwise;
begin
  ViewRotation := (FViewRotation + RightAngle) mod FullTurn;
end;

procedure TPdfPageViewController.RotateCounterclockwise;
begin
  ViewRotation := (FViewRotation + FullTurn - RightAngle) mod FullTurn;
end;

function TPdfPageViewController.ContentSize: TSize;
begin
  Result := TSize.Create(0, 0);
  if Assigned(FLayout) then
  begin
    Result := FLayout.ContentSize;
  end;
end;

function TPdfPageViewController.ScrollPosition: TPoint;
begin
  Result := FScroll;
end;

function TPdfPageViewController.TileCacheCost: Int64;
begin
  Result := FTiles.TotalCost;
end;

function TPdfPageViewController.ViewportToPage(const Point: TPointF; out PageIndex: Integer; out PagePoint: TPointF): Boolean;
begin
  PageIndex := 0;
  PagePoint := TPointF.Create(0, 0);
  Result := False;
  if not Assigned(FLayout) then
  begin
    Exit;
  end;

  const Content = ViewportToContent(Point);
  const ContentPoint = TPoint.Create(Floor(Content.X), Floor(Content.Y));
  var Rect: TRect;
  const IsOnPage = FLayout.TryFindPageAt(ContentPoint, PageIndex) and FLayout.TryGetPageRect(PageIndex, Rect);
  if IsOnPage then
  begin
    const Transform = FLayout.Transform(PageIndex);
    const OnPage = TPointF.Create(Content.X - Rect.Left, Content.Y - Rect.Top);
    PagePoint := Transform.ViewToPage(OnPage);
    Result := True;
  end;
end;

function TPdfPageViewController.TryPageToViewport(const PageIndex: Integer; const PagePoint: TPointF; out Point: TPointF): Boolean;
begin
  Point := TPointF.Create(0, 0);
  var PageRect: TRect;
  Result := PageRectInViewport(PageIndex, PageRect);
  if Result then
  begin
    const Transform = FLayout.Transform(PageIndex);
    const InPage = Transform.PageToView(PagePoint);
    Point := TPointF.Create(PageRect.Left + InPage.X, PageRect.Top + InPage.Y);
  end;
end;

function TPdfPageViewController.PendingTileCount: Integer;
begin
  Result := FPendingTiles.Count;
end;

{ Input }

function TPdfPageViewController.ScaledPixels(const LogicalPixels: Single): Single;
begin
  Result := LogicalPixels * FPixelsPerInch / LogicalPixelsPerInch;
end;

// The page text must be in the cache already: the input methods never request anything
function TPdfPageViewController.TryGetTextAt(const Point: TPointF; out PageIndex: Integer; out PagePoint: TPointF;
                                             out PageText: IPdfPageText): Boolean;
begin
  PageText := nil;
  Result := ViewportToPage(Point, PageIndex, PagePoint) and Document.TryGetPageText(PageIndex, PageText);
end;

// The bounds of the quads in viewport pixels
function TPdfPageViewController.TryGetViewBounds(const PageIndex: Integer; const Quads: TArray<TPdfQuad>; out Bounds: TRectF): Boolean;
begin
  Bounds := TRectF.Empty;
  var PageRect: TRect;
  if not PageRectInViewport(PageIndex, PageRect) then
  begin
    Exit(False);
  end;

  var Placement: TPlacement;
  Placement.PageIndex := PageIndex;
  Placement.Origin := TPointF.Create(PageRect.Left, PageRect.Top);
  Placement.Transform := FLayout.Transform(PageIndex);
  const Points = ViewPointsOf(Placement, Quads);
  Result := TryGetBoundsOf(Points, Bounds);
end;

procedure TPdfPageViewController.InvalidateQuads(const PageIndex: Integer; const Quads: TArray<TPdfQuad>);
begin
  const Margin = Ceil(ScaledPixels(OverlayFrameWidth)) + 1;
  for var Quad in Quads do
  begin
    var Bounds: TRectF;
    if TryGetViewBounds(PageIndex, [Quad], Bounds) then
    begin
      const Left = Floor(Bounds.Left) - Margin;
      const Top = Floor(Bounds.Top) - Margin;
      const Right = Ceil(Bounds.Right) + Margin;
      const Bottom = Ceil(Bounds.Bottom) + Margin;
      const Area = TRect.Create(Left, Top, Right, Bottom);
      const ViewportRect = TRect.Create(0, 0, FViewport.cx, FViewport.cy);
      const Visible = TRect.Intersect(Area, ViewportRect);
      if not Visible.IsEmpty then
      begin
        FHost.Invalidate(Visible);
      end;
    end;
  end;
end;

procedure TPdfPageViewController.UpdateHover(const Point: TPointF);
begin
  if not FHoverEnabled then
  begin
    Exit;
  end;

  var PageIndex: Integer;
  var PagePoint: TPointF;
  var PageText: IPdfPageText;
  var Segment: TPdfTextFragment;
  if TryGetTextAt(Point, PageIndex, PagePoint, PageText) and PageText.TryFindSegmentAt(PagePoint, Segment) then
  begin
    SetHover(PageIndex, Segment);
  end
  else
  begin
    ClearHover;
  end;
end;

procedure TPdfPageViewController.SetHover(const PageIndex: Integer; const Segment: TPdfTextFragment);
begin
  const IsSame = FHasHover and (FHoverPage = PageIndex) and (FHoverSegment.Start = Segment.Start) and (FHoverSegment.Length = Segment.Length);
  if IsSame then
  begin
    Exit;
  end;

  if FHasHover then
  begin
    InvalidateQuads(FHoverPage, FHoverSegment.Quads);
  end;
  FHasHover := True;
  FHoverPage := PageIndex;
  FHoverSegment := Segment;
  InvalidateQuads(PageIndex, Segment.Quads);

  if Assigned(FOnHoverChanged) then
  begin
    FOnHoverChanged(Self, True, Segment);
  end;
end;

procedure TPdfPageViewController.ClearHover;
begin
  if not FHasHover then
  begin
    Exit;
  end;

  InvalidateQuads(FHoverPage, FHoverSegment.Quads);
  FHasHover := False;
  FHoverSegment := Default(TPdfTextFragment);

  if Assigned(FOnHoverChanged) then
  begin
    FOnHoverChanged(Self, False, FHoverSegment);
  end;
end;

procedure TPdfPageViewController.UpdateCursor(const Point: TPointF);
begin
  var Kind := TPdfCursorKind.Default;
  if FIsDragging and Assigned(FAnchorText) then
  begin
    Kind := TPdfCursorKind.Text;
  end
  else
  begin
    var PageIndex: Integer;
    var PagePoint: TPointF;
    var PageText: IPdfPageText;
    var Link: TPdfLink;
    var Segment: TPdfTextFragment;
    if TryGetTextAt(Point, PageIndex, PagePoint, PageText) then
    begin
      if PageText.TryFindLinkAt(PagePoint, Link) then
      begin
        Kind := TPdfCursorKind.Link;
      end
      else if FSelectionEnabled and PageText.TryFindSegmentAt(PagePoint, Segment) then
      begin
        Kind := TPdfCursorKind.Text;
      end;
    end;
  end;
  ChangeCursor(Kind);
end;

procedure TPdfPageViewController.ChangeCursor(const Kind: TPdfCursorKind);
begin
  if Kind = FCursor then
  begin
    Exit;
  end;

  FCursor := Kind;
  FHost.CursorChanged;
end;

procedure TPdfPageViewController.SetSelection(const Selection: TPdfTextSelection);
begin
  if FHasSelection then
  begin
    InvalidateQuads(FSelection.PageIndex, FSelection.Quads);
  end;
  FSelection := Selection;
  FHasSelection := True;
  InvalidateQuads(Selection.PageIndex, Selection.Quads);
end;

procedure TPdfPageViewController.ClearSelection;
begin
  FAnchorText := nil;
  if not FHasSelection then
  begin
    Exit;
  end;

  InvalidateQuads(FSelection.PageIndex, FSelection.Quads);
  FHasSelection := False;
  FSelection := Default(TPdfTextSelection);
end;

function TPdfPageViewController.TryGetSelection(out Selection: TPdfTextSelection): Boolean;
begin
  Selection := FSelection;
  Result := FHasSelection;
end;

function TPdfPageViewController.TryGetHoverSegment(out Segment: TPdfTextFragment): Boolean;
begin
  Segment := FHoverSegment;
  Result := FHasHover;
end;

function TPdfPageViewController.CursorKind: TPdfCursorKind;
begin
  Result := FCursor;
end;

procedure TPdfPageViewController.ResetInput;
begin
  ClearHover;
  ClearSelection;
  FIsPressed := False;
  FIsDragging := False;
  // What was left of a notch belongs to the document that was shown
  FWheelRemainder := 0;
  ChangeCursor(TPdfCursorKind.Default);
end;

procedure TPdfPageViewController.MouseMove(const Point: TPointF);
begin
  if not Assigned(FLayout) then
  begin
    Exit;
  end;

  if FIsPressed then
  begin
    UpdateDrag(Point);
  end
  else
  begin
    UpdateHover(Point);
  end;
  UpdateCursor(Point);
end;

procedure TPdfPageViewController.MouseDown(const Point: TPointF);
begin
  if Assigned(FLayout) then
  begin
    BeginPress(Point);
  end;
end;

procedure TPdfPageViewController.MouseUp(const Point: TPointF);
begin
  if not FIsPressed then
  begin
    Exit;
  end;
  FIsPressed := False;

  if not FIsDragging then
  begin
    FAnchorText := nil;
    FinishClick(Point);
    Exit;
  end;

  UpdateDrag(Point);
  const IsSelecting = Assigned(FAnchorText) and FHasSelection;
  const Selection = FSelection;
  FIsDragging := False;
  FAnchorText := nil;
  UpdateCursor(Point);

  if IsSelecting and Assigned(FOnTextSelected) then
  begin
    FOnTextSelected(Self, Selection);
  end;
end;

procedure TPdfPageViewController.MouseLeave;
begin
  ClearHover;
  ChangeCursor(TPdfCursorKind.Default);
end;

procedure TPdfPageViewController.MouseWheel(const WheelDelta: Integer; const Ctrl: Boolean; const Point: TPointF);
begin
  if (not Assigned(FLayout)) or (WheelDelta = 0) then
  begin
    Exit;
  end;

  if Ctrl then
  begin
    ZoomByWheel(WheelDelta, Point);
    Exit;
  end;

  const Distance = WheelDelta / WheelNotch * WheelLinesPerNotch * ScaledPixels(KeyScrollStep);
  ScrollBy(0, -Round(Distance));
end;

procedure TPdfPageViewController.ZoomByWheel(const WheelDelta: Integer; const Point: TPointF);
begin
  const IsUpwards = (WheelDelta > 0);

  // A wheel with fine steps (a touchpad, a macOS wheel) sends parts of a notch: they add up to one zoom step per notch, and what is
  // left from the other direction does not count
  if (FWheelRemainder <> 0) and ((FWheelRemainder > 0) <> IsUpwards) then
  begin
    FWheelRemainder := 0;
  end;
  Inc(FWheelRemainder, WheelDelta);

  const Notches = Abs(FWheelRemainder) div WheelNotch;
  FWheelRemainder := FWheelRemainder - Sign(FWheelRemainder) * Notches * WheelNotch;
  for var Notch := 1 to Notches do
  begin
    const Step = NextZoomStep(IsUpwards);
    ZoomAt(Step, Point);
  end;
end;

function TPdfPageViewController.KeyDown(const Key: TPdfViewerKey): Boolean;
begin
  Result := Assigned(FLayout);
  if not Result then
  begin
    Exit;
  end;

  const Step = Round(ScaledPixels(KeyScrollStep));
  case Key of
    TPdfViewerKey.Up:
      ScrollBy(0, -Step);
    TPdfViewerKey.Down:
      ScrollBy(0, Step);
    TPdfViewerKey.Left:
      ScrollBy(-Step, 0);
    TPdfViewerKey.Right:
      ScrollBy(Step, 0);
    TPdfViewerKey.PageUp:
      ScrollBy(0, -Max(0, FViewport.cy - Step));
    TPdfViewerKey.PageDown:
      ScrollBy(0, Max(0, FViewport.cy - Step));
    TPdfViewerKey.Home:
      ScrollTo(TPoint.Create(FScroll.X, 0));
    TPdfViewerKey.End_:
      ScrollTo(TPoint.Create(FScroll.X, ContentSize.cy));
    TPdfViewerKey.ZoomIn:
      ZoomIn;
    TPdfViewerKey.ZoomOut:
      ZoomOut;
    TPdfViewerKey.ZoomReset:
      Zoom := 1;
    TPdfViewerKey.SelectAll:
      begin
        Result := FSelectionEnabled;
        if Result then
        begin
          SelectAllOnCurrentPage;
        end;
      end;
  else
    raise ENotSupportedException.CreateFmt('Unsupported key: %d', [Ord(Key)]);
  end;
end;

procedure TPdfPageViewController.SelectAllOnCurrentPage;
begin
  var PageText: IPdfPageText;
  if Document.TryGetPageText(Document.CurrentPage, PageText) and (not PageText.IsEmpty) then
  begin
    SetSelection(PageText.SelectAll);
  end;
end;

procedure TPdfPageViewController.ScrollIntoView(const PageIndex: Integer; const Quads: TArray<TPdfQuad>);
begin
  if not Assigned(FLayout) then
  begin
    Exit;
  end;

  // Only the current page has a place in this mode
  const IsOtherPageOfSinglePage = (FScrollMode = TPdfScrollMode.SinglePage) and (PageIndex >= 0) and (PageIndex < Length(FPages)) and
                                  (PageIndex <> Document.CurrentPage);
  if IsOtherPageOfSinglePage then
  begin
    Document.CurrentPage := PageIndex;
  end;

  var Bounds: TRectF;
  if not TryGetViewBounds(PageIndex, Quads, Bounds) then
  begin
    Exit;
  end;

  const IsInView = (Bounds.Left >= 0) and (Bounds.Top >= 0) and (Bounds.Right <= FViewport.cx) and (Bounds.Bottom <= FViewport.cy);
  if not IsInView then
  begin
    const Center = Bounds.CenterPoint;
    const DeltaX = Round(Center.X - FViewport.cx / 2);
    const DeltaY = Round(Center.Y - FViewport.cy / 2);
    ScrollBy(DeltaX, DeltaY);
  end;
end;

// The anchor is the word at or nearest to the start of the press, found in the cached text of the page there
procedure TPdfPageViewController.BeginPress(const Point: TPointF);
begin
  FIsPressed := True;
  FIsDragging := False;
  FDownPoint := Point;
  FAnchorText := nil;

  var PageIndex: Integer;
  var PagePoint: TPointF;
  var PageText: IPdfPageText;
  var Word: Integer;
  const IsOnText = FSelectionEnabled and TryGetTextAt(Point, PageIndex, PagePoint, PageText);
  if IsOnText and (PageText.TryFindWordAt(PagePoint, Word) or PageText.TryFindNearestWord(PagePoint, Word)) then
  begin
    FAnchorText := PageText;
    FAnchorPage := PageIndex;
    FAnchorWord := Word;
  end;
end;

procedure TPdfPageViewController.UpdateDrag(const Point: TPointF);
begin
  if not FIsDragging then
  begin
    const Distance = Point.Distance(FDownPoint);
    const Tolerance = ScaledPixels(ClickTolerance);
    if Distance <= Tolerance then
    begin
      Exit;
    end;

    FIsDragging := True;
    ClearHover;
  end;

  if not Assigned(FAnchorText) then
  begin
    Exit;
  end;

  var Focus: Integer;
  if TryGetFocusWord(Point, Focus) then
  begin
    const Selection = FAnchorText.Select(FAnchorWord, Focus, TPdfSelectionKind.Drag);
    SetSelection(Selection);
  end;
end;

// The word nearest to the point on the page of the anchor. A point beyond the top of the page gives its first word and one beyond the
// bottom its last word, where top and bottom are those of the page itself: with a rotated page or view they are not the top and bottom
// of the screen.
function TPdfPageViewController.TryGetFocusWord(const Point: TPointF; out WordIndex: Integer): Boolean;
begin
  WordIndex := 0;
  var PageRect: TRect;
  if not PageRectInViewport(FAnchorPage, PageRect) then
  begin
    Exit(False);
  end;

  const Transform = FLayout.Transform(FAnchorPage);
  const PageBox = FPages[FAnchorPage].CropBox;
  const OnPage = TPointF.Create(Point.X - PageRect.Left, Point.Y - PageRect.Top);

  const PdfPoint = Transform.ViewToPage(OnPage);
  const IsAboveThePage = (PdfPoint.Y > PageBox.UpperRightY);
  if IsAboveThePage then
  begin
    Exit(True);
  end;

  const IsBelowThePage = (PdfPoint.Y < PageBox.LowerLeftY);
  if IsBelowThePage then
  begin
    const Words = FAnchorText.Words;
    WordIndex := Length(Words) - 1;
    Exit(True);
  end;

  // Beyond a side of the page, the word nearest to the edge
  const OnEdge = TPointF.Create(EnsureRange(OnPage.X, 0, PageRect.Width), EnsureRange(OnPage.Y, 0, PageRect.Height));
  const PdfEdgePoint = Transform.ViewToPage(OnEdge);
  Result := FAnchorText.TryFindNearestWord(PdfEdgePoint, WordIndex);
end;

procedure TPdfPageViewController.FinishClick(const Point: TPointF);
begin
  var PageIndex: Integer;
  var PagePoint: TPointF;
  var PageText: IPdfPageText;
  var Link: TPdfLink;
  var Segment: TPdfTextFragment;
  if TryGetTextAt(Point, PageIndex, PagePoint, PageText) then
  begin
    if PageText.TryFindLinkAt(PagePoint, Link) then
    begin
      ClearSelection;
      RaiseLinkClick(Link);
      Exit;
    end;

    if FSelectionEnabled and PageText.TryFindSegmentAt(PagePoint, Segment) then
    begin
      SelectSegment(PageIndex, Segment);
      Exit;
    end;
  end;

  ClearSelection;
end;

procedure TPdfPageViewController.SelectSegment(const PageIndex: Integer; const Segment: TPdfTextFragment);
begin
  var Selection: TPdfTextSelection;
  Selection.Kind := TPdfSelectionKind.Click;
  Selection.PageIndex := PageIndex;
  Selection.Text := Segment.Text;
  Selection.Quads := Copy(Segment.Quads);
  SetSelection(Selection);

  if Assigned(FOnTextSelected) then
  begin
    FOnTextSelected(Self, Selection);
  end;
end;

procedure TPdfPageViewController.RaiseLinkClick(const Link: TPdfLink);
begin
  if Assigned(FOnLinkClick) then
  begin
    FOnLinkClick(Self, Link);
  end;

  const IsFollowed = FFollowInternalLinks and (Link.Kind = TPdfLinkKind.GoTo) and Assigned(Document);
  if IsFollowed then
  begin
    Document.CurrentPage := Link.TargetPageIndex;
  end;
end;

{ Requests }

procedure TPdfPageViewController.RefreshRequests;
begin
  if (not Assigned(FLayout)) or (not HasViewport) then
  begin
    CancelAllRequests;
    Exit;
  end;

  const ContentRect = ViewportContentRect;
  const VisiblePages = FLayout.VisiblePages(ContentRect);
  const Wants = TList<TPageWant>.Create;
  try
    CollectWants(VisiblePages, Wants);
    CancelUnneeded(Wants, VisiblePages);
    RequestWants(Wants, TPdfJobPriority.Visible);
    RequestPageTexts(VisiblePages);
    RequestWants(Wants, TPdfJobPriority.Prefetch);
  finally
    Wants.Free;
  end;
end;

// The visible pages, and in continuous mode the part of the page before and after them that lies one viewport height away
procedure TPdfPageViewController.CollectWants(const VisiblePages: TArray<Integer>; const Wants: TList<TPageWant>);
begin
  for var PageIndex in VisiblePages do
  begin
    const Want = VisibleWant(PageIndex);
    Wants.Add(Want);
  end;

  const HasVisiblePages = (Length(VisiblePages) > 0);
  const IsPrefetching = HasVisiblePages and (FScrollMode = TPdfScrollMode.Continuous);
  if not IsPrefetching then
  begin
    Exit;
  end;

  const PageBefore = VisiblePages[0] - 1;
  const PageAfter = VisiblePages[High(VisiblePages)] + 1;
  if PageBefore >= 0 then
  begin
    const Want = PrefetchWant(PageBefore, False);
    Wants.Add(Want);
  end;
  if PageAfter < Length(FPages) then
  begin
    const Want = PrefetchWant(PageAfter, True);
    Wants.Add(Want);
  end;
end;

procedure TPdfPageViewController.RequestWants(const Wants: TList<TPageWant>; const Priority: TPdfJobPriority);
begin
  for var Want in Wants do
  begin
    if Want.Priority = Priority then
    begin
      RequestMissingTiles(Want);
    end;
  end;
end;

function TPdfPageViewController.WantOf(const PageIndex: Integer; const AreaInPage: TRect; const Priority: TPdfJobPriority): TPageWant;
begin
  const Transform = FLayout.Transform(PageIndex);
  Result.PageIndex := PageIndex;
  Result.Scale := Transform.Scale;
  Result.Rotation := Transform.ViewRotation;
  Result.Priority := Priority;
  Result.Tiles := TPdfTileGrid.TilesIn(Transform.Size, AreaInPage);
end;

function TPdfPageViewController.VisibleWant(const PageIndex: Integer): TPageWant;
begin
  var Rect: TRect;
  var Area := TRect.Empty;
  if FLayout.TryGetPageRect(PageIndex, Rect) then
  begin
    const ContentRect = ViewportContentRect;
    Area := TRect.Intersect(ContentRect, Rect);
    Area.Offset(-Rect.Left, -Rect.Top);
  end;
  Result := WantOf(PageIndex, Area, TPdfJobPriority.Visible);
end;

// The part of a neighbouring page that lies one viewport height away from the visible pages
function TPdfPageViewController.PrefetchWant(const PageIndex: Integer; const IsBelow: Boolean): TPageWant;
begin
  var Rect: TRect;
  var Area := TRect.Empty;
  if FLayout.TryGetPageRect(PageIndex, Rect) then
  begin
    const Left = FScroll.X - Rect.Left;
    if IsBelow then
    begin
      Area := TRect.Create(Left, 0, Left + FViewport.cx, FViewport.cy);
    end
    else
    begin
      Area := TRect.Create(Left, Rect.Height - FViewport.cy, Left + FViewport.cx, Rect.Height);
    end;
  end;
  Result := WantOf(PageIndex, Area, TPdfJobPriority.Prefetch);
end;

procedure TPdfPageViewController.CancelUnneeded(const Wants: TList<TPageWant>; const VisiblePages: TArray<Integer>);
begin
  CancelUnneededTiles(Wants);
  CancelUnneededTexts(VisiblePages);
end;

procedure TPdfPageViewController.CancelUnneededTiles(const Wants: TList<TPageWant>);
begin
  const Needed = TDictionary<TPdfTileKey, Boolean>.Create;
  try
    for var Want in Wants do
    begin
      for var Tile in Want.Tiles do
      begin
        const Key = TPdfTileKey.Create(Want.PageIndex, Want.Rotation, Want.Scale, Tile.X, Tile.Y);
        Needed.AddOrSetValue(Key, True);
      end;
    end;

    for var Index := FTileRequests.Count - 1 downto 0 do
    begin
      const Request = FTileRequests[Index];
      if not IsRequestNeeded(Request, Needed) then
      begin
        CancelTileRequest(Request);
      end;
    end;
  finally
    Needed.Free;
  end;
end;

// A request is needed while one of its tiles is still pending for it and is wanted
function TPdfPageViewController.IsRequestNeeded(const Request: TTileRequest; const Needed: TDictionary<TPdfTileKey, Boolean>): Boolean;
begin
  for var Key in Request.Keys do
  begin
    var Pending: TTileRequest;
    const IsPending = FPendingTiles.TryGetValue(Key, Pending) and (Pending = Request);
    if IsPending and Needed.ContainsKey(Key) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TPdfPageViewController.CancelUnneededTexts(const VisiblePages: TArray<Integer>);
begin
  for var Page in FTextRequests.Keys.ToArray do
  begin
    if not IsPageIn(VisiblePages, Page) then
    begin
      const TextRequest = FTextRequests[Page];
      TextRequest.Cancel;
      FTextRequests.Remove(Page);
    end;
  end;
end;

class function TPdfPageViewController.IsPageIn(const Pages: TArray<Integer>; const PageIndex: Integer): Boolean;
begin
  Result := False;
  for var Page in Pages do
  begin
    if Page = PageIndex then
    begin
      Exit(True);
    end;
  end;
end;

procedure TPdfPageViewController.CancelTileRequest(const Request: TTileRequest);
begin
  const SessionRequest = Request.Request;
  SessionRequest.Cancel;
  for var Key in Request.Keys do
  begin
    var Pending: TTileRequest;
    if FPendingTiles.TryGetValue(Key, Pending) and (Pending = Request) then
    begin
      FPendingTiles.Remove(Key);
    end;
  end;
  // Frees the request
  FTileRequests.Remove(Request);
end;

procedure TPdfPageViewController.CancelAllRequests;
begin
  for var Request in FTileRequests do
  begin
    const SessionRequest = Request.Request;
    SessionRequest.Cancel;
  end;
  FTileRequests.Clear;
  FPendingTiles.Clear;

  for var Request in FTextRequests.Values do
  begin
    Request.Cancel;
  end;
  FTextRequests.Clear;
end;

procedure TPdfPageViewController.RequestMissingTiles(const Want: TPageWant);
begin
  const Missing = TList<TPoint>.Create;
  const Keys = TList<TPdfTileKey>.Create;
  try
    for var Tile in Want.Tiles do
    begin
      const Key = TPdfTileKey.Create(Want.PageIndex, Want.Rotation, Want.Scale, Tile.X, Tile.Y);
      const IsKnown = FTiles.Contains(Key) or FPendingTiles.ContainsKey(Key) or FFailedTiles.ContainsKey(Key);
      if not IsKnown then
      begin
        Missing.Add(Tile);
        Keys.Add(Key);
      end;
    end;

    if Missing.Count > 0 then
    begin
      StartTileRequest(Want, Missing, Keys);
    end;
  finally
    Keys.Free;
    Missing.Free;
  end;
end;

procedure TPdfPageViewController.StartTileRequest(const Want: TPageWant; const Missing: TList<TPoint>; const Keys: TList<TPdfTileKey>);
begin
  const Request = TTileRequest.Create;
  try
    Request.PageIndex := Want.PageIndex;
    Request.Rotation := Want.Rotation;
    Request.Scale := Want.Scale;
    Request.Keys := Keys.ToArray;
    Request.Remaining := Keys.Count;

    const Session = Document.Session;
    const Tiles = Missing.ToArray;
    const OnTile = TileDoneEvent(Request);
    Request.Request := Session.RequestTiles(Want.PageIndex, Want.Scale, Want.Rotation, Tiles, Want.Priority, OnTile);
  except
    Request.Free;
    raise;
  end;

  FTileRequests.Add(Request);
  for var Key in Request.Keys do
  begin
    FPendingTiles.Add(Key, Request);
  end;
end;

function TPdfPageViewController.TileDoneEvent(const Request: TTileRequest): TPdfTileDoneEvent;
begin
  Result :=
    procedure(const Tile: TPoint; const Outcome: TPdfRenderResult)
    begin
      HandleTile(Request, Tile, Outcome);
    end;
end;

procedure TPdfPageViewController.HandleTile(const Request: TTileRequest; const Tile: TPoint; const Outcome: TPdfRenderResult);
begin
  const Key = TPdfTileKey.Create(Request.PageIndex, Request.Rotation, Request.Scale, Tile.X, Tile.Y);
  var Pending: TTileRequest;
  if FPendingTiles.TryGetValue(Key, Pending) and (Pending = Request) then
  begin
    FPendingTiles.Remove(Key);
    Dec(Request.Remaining);
  end;

  if Outcome.Succeeded then
  begin
    StoreTile(Key, Outcome);
  end
  else
  begin
    FFailedTiles.AddOrSetValue(Key, True);
  end;

  if Request.Remaining <= 0 then
  begin
    // Frees the request, which is done
    FTileRequests.Remove(Request);
  end;
end;

procedure TPdfPageViewController.StoreTile(const Key: TPdfTileKey; const Outcome: TPdfRenderResult);
begin
  const Image = FHost.CreateImage(Outcome.Bitmap);
  const Cost = Int64(Outcome.Bitmap.Width) * Outcome.Bitmap.Height * BytesPerPixel;
  FTiles.Add(Key, Image, Cost);
  RememberLayer(Key);
  InvalidateTile(Key);
end;

procedure TPdfPageViewController.RememberLayer(const Key: TPdfTileKey);
begin
  var Layers := Default(TPageLayers);
  FPageLayers.TryGetValue(Key.PageIndex, Layers);

  const IsLatest = Layers.Latest.IsValid and (Layers.Latest.Scale = Key.Scale) and (Layers.Latest.Rotation = Key.ViewRotation);
  if IsLatest then
  begin
    Exit;
  end;

  Layers.Previous := Layers.Latest;
  Layers.Latest.IsValid := True;
  Layers.Latest.Scale := Key.Scale;
  Layers.Latest.Rotation := Key.ViewRotation;
  FPageLayers.AddOrSetValue(Key.PageIndex, Layers);
end;

procedure TPdfPageViewController.InvalidateTile(const Key: TPdfTileKey);
begin
  var PageRect: TRect;
  if not PageRectInViewport(Key.PageIndex, PageRect) then
  begin
    Exit;
  end;

  const Transform = FLayout.Transform(Key.PageIndex);
  const IsCurrentScale = (Transform.Scale = Key.Scale) and (Transform.ViewRotation = Key.ViewRotation);
  if not IsCurrentScale then
  begin
    Exit;
  end;

  var TileRect := TPdfTileGrid.TileRect(Transform.Size, Key.Column, Key.Row);
  TileRect.Offset(PageRect.Left, PageRect.Top);
  const Visible = TRect.Intersect(TileRect, TRect.Create(0, 0, FViewport.cx, FViewport.cy));
  if not Visible.IsEmpty then
  begin
    FHost.Invalidate(Visible);
  end;
end;

procedure TPdfPageViewController.RequestPageTexts(const VisiblePages: TArray<Integer>);
begin
  for var PageIndex in VisiblePages do
  begin
    var PageText: IPdfPageText;
    const IsKnown = Document.TryGetPageText(PageIndex, PageText) or FTextRequests.ContainsKey(PageIndex);
    if not IsKnown then
    begin
      const Page = PageIndex;
      const TextRequest = Document.RequestPageText(Page, TPdfJobPriority.PageText,
        procedure(const Text: IPdfPageText)
        begin
          FTextRequests.Remove(Page);
        end);
      FTextRequests.Add(Page, TextRequest);
    end;
  end;
end;

{ Painting }

function TPdfPageViewController.PlacementsOf(const Pages: TArray<Integer>): TArray<TPlacement>;
begin
  SetLength(Result, 0);
  for var PageIndex in Pages do
  begin
    var Rect: TRect;
    if PageRectInViewport(PageIndex, Rect) then
    begin
      var Placement: TPlacement;
      Placement.PageIndex := PageIndex;
      Placement.Origin := TPointF.Create(Rect.Left, Rect.Top);
      Placement.Transform := FLayout.Transform(PageIndex);
      Result := Result + [Placement];
    end;
  end;
end;

procedure TPdfPageViewController.Paint(const Painter: IPdfViewPainter; const ClipRect: TRect);
begin
  const Background = TRectF.Create(ClipRect);
  Painter.FillRect(Background, FBackgroundColor);
  if not Assigned(FLayout) then
  begin
    Exit;
  end;

  var ContentClip := ClipRect;
  ContentClip.Offset(FScroll.X - CenteringOffset, FScroll.Y);
  const VisiblePages = FLayout.VisiblePages(ContentClip);
  const Placements = PlacementsOf(VisiblePages);

  for var Placement in Placements do
  begin
    PaintPage(Painter, Placement, ClipRect);
  end;

  PaintSearchHits(Painter, Placements);
  PaintSelection(Painter, Placements);
  PaintOverlays(Painter, Placements);
  PaintHover(Painter, Placements);
end;

class function TPdfPageViewController.TryFindPlacement(const Placements: TArray<TPlacement>; const PageIndex: Integer;
                                                       out Placement: TPlacement): Boolean;
begin
  Placement := Default(TPlacement);
  for var Candidate in Placements do
  begin
    if Candidate.PageIndex = PageIndex then
    begin
      Placement := Candidate;
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TPdfPageViewController.PaintSelection(const Painter: IPdfViewPainter; const Placements: TArray<TPlacement>);
begin
  var Placement: TPlacement;
  if FHasSelection and TryFindPlacement(Placements, FSelection.PageIndex, Placement) then
  begin
    PaintQuads(Painter, Placement, FSelection.Quads, FSelectionColor);
  end;
end;

procedure TPdfPageViewController.PaintHover(const Painter: IPdfViewPainter; const Placements: TArray<TPlacement>);
begin
  var Placement: TPlacement;
  if not (FHasHover and TryFindPlacement(Placements, FHoverPage, Placement)) then
  begin
    Exit;
  end;

  const FrameWidth = ScaledPixels(OverlayFrameWidth);
  for var Quad in FHoverSegment.Quads do
  begin
    const Polygon = ViewPolygonOf(Placement, Quad);
    Painter.FramePolygon(Polygon, FHoverColor, FrameWidth);
  end;
end;

procedure TPdfPageViewController.PaintPage(const Painter: IPdfViewPainter; const Placement: TPlacement; const ClipRect: TRect);
begin
  const Size = Placement.Transform.Size;
  const PageRect = TRect.Create(Round(Placement.Origin.X), Round(Placement.Origin.Y), Round(Placement.Origin.X) + Size.cx,
                                Round(Placement.Origin.Y) + Size.cy);
  var Visible := TRect.Intersect(PageRect, ClipRect);
  if Visible.IsEmpty then
  begin
    Exit;
  end;

  const PaperRect = TRectF.Create(Visible);
  Painter.FillRect(PaperRect, PageColor);

  Visible.Offset(-PageRect.Left, -PageRect.Top);
  const Tiles = TPdfTileGrid.TilesIn(Size, Visible);
  for var Tile in Tiles do
  begin
    PaintTile(Painter, Placement, Tile.X, Tile.Y);
  end;
end;

procedure TPdfPageViewController.PaintTile(const Painter: IPdfViewPainter; const Placement: TPlacement; const Column, Row: Integer);
begin
  const Key = TPdfTileKey.Create(Placement.PageIndex, Placement.Transform.ViewRotation, Placement.Transform.Scale, Column, Row);
  const TileRect = TPdfTileGrid.TileRect(Placement.Transform.Size, Column, Row);

  var Image: IPdfViewImage;
  if not FTiles.TryGet(Key, Image) then
  begin
    PaintFallback(Painter, Placement, TileRect);
    Exit;
  end;

  const Dest = TRectF.Create(Placement.Origin.X + TileRect.Left, Placement.Origin.Y + TileRect.Top, Placement.Origin.X + TileRect.Right,
                             Placement.Origin.Y + TileRect.Bottom);
  const Source = TRect.Create(0, 0, Image.Width, Image.Height);
  Painter.DrawImage(Image, Source, Dest);
end;

// What a tile shows until it arrives: the tiles of the scale that the page showed before, scaled to this one
procedure TPdfPageViewController.PaintFallback(const Painter: IPdfViewPainter; const Placement: TPlacement; const TileRect: TRect);
begin
  var Layer: TTileLayer;
  if not TryGetFallbackLayer(Placement.PageIndex, Placement.Transform, Layer) then
  begin
    Exit;
  end;

  const OldTransform = TPdfViewTransform.Create(FPages[Placement.PageIndex], Layer.Rotation, Layer.Scale, LayerPixelsPerInch);
  const OldSize = OldTransform.Size;
  const NewSize = Placement.Transform.Size;
  const Ratio = TPointF.Create(OldSize.cx / NewSize.cx, OldSize.cy / NewSize.cy);
  const Source = TRect.Create(Floor(TileRect.Left * Ratio.X), Floor(TileRect.Top * Ratio.Y), Ceil(TileRect.Right * Ratio.X),
                              Ceil(TileRect.Bottom * Ratio.Y));

  const OldTiles = TPdfTileGrid.TilesIn(OldSize, Source);
  for var OldTile in OldTiles do
  begin
    PaintFallbackTile(Painter, Placement, Layer, OldTile, Source, Ratio);
  end;
end;

// The part of a tile of the old layer that lies in Source, drawn at the place it has in the page now
procedure TPdfPageViewController.PaintFallbackTile(const Painter: IPdfViewPainter; const Placement: TPlacement; const Layer: TTileLayer;
                                                   const OldTile: TPoint; const Source: TRect; const Ratio: TPointF);
begin
  const Key = TPdfTileKey.Create(Placement.PageIndex, Layer.Rotation, Layer.Scale, OldTile.X, OldTile.Y);
  var Image: IPdfViewImage;
  if not FTiles.TryGet(Key, Image) then
  begin
    Exit;
  end;

  const OldTransform = TPdfViewTransform.Create(FPages[Placement.PageIndex], Layer.Rotation, Layer.Scale, LayerPixelsPerInch);
  const OldTileRect = TPdfTileGrid.TileRect(OldTransform.Size, OldTile.X, OldTile.Y);
  const Part = TRect.Intersect(OldTileRect, Source);
  if Part.IsEmpty then
  begin
    Exit;
  end;

  const ImagePart = TRect.Create(Part.Left - OldTileRect.Left, Part.Top - OldTileRect.Top, Part.Right - OldTileRect.Left,
                                 Part.Bottom - OldTileRect.Top);
  const Dest = TRectF.Create(Placement.Origin.X + Part.Left / Ratio.X, Placement.Origin.Y + Part.Top / Ratio.Y,
                             Placement.Origin.X + Part.Right / Ratio.X, Placement.Origin.Y + Part.Bottom / Ratio.Y);
  Painter.DrawImage(Image, ImagePart, Dest);
end;

class function TPdfPageViewController.IsUsableLayer(const Layer: TTileLayer; const Transform: TPdfViewTransform): Boolean;
begin
  Result := Layer.IsValid and (Layer.Rotation = Transform.ViewRotation) and (Layer.Scale <> Transform.Scale);
end;

// Tiles of another scale can only be scaled to this one when the page has the same rotation
function TPdfPageViewController.TryGetFallbackLayer(const PageIndex: Integer; const Transform: TPdfViewTransform;
                                                    out Layer: TTileLayer): Boolean;
begin
  Layer := Default(TTileLayer);
  var Layers: TPageLayers;
  if not FPageLayers.TryGetValue(PageIndex, Layers) then
  begin
    Exit(False);
  end;

  if IsUsableLayer(Layers.Latest, Transform) then
  begin
    Layer := Layers.Latest;
    Exit(True);
  end;

  if IsUsableLayer(Layers.Previous, Transform) then
  begin
    Layer := Layers.Previous;
    Exit(True);
  end;
  Result := False;
end;

procedure TPdfPageViewController.PaintSearchHits(const Painter: IPdfViewPainter; const Placements: TArray<TPlacement>);
begin
  if Document.SearchHitCount = 0 then
  begin
    Exit;
  end;

  // Only the hits of the pages that are shown are fetched: a paint does not depend on how many hits the document has
  for var Placement in Placements do
  begin
    const Hits = Document.SearchHitsOnPage(Placement.PageIndex);
    const CurrentPosition = Document.CurrentSearchHitOnPage(Placement.PageIndex);
    for var Position := 0 to High(Hits) do
    begin
      var Color := FSearchHitColor;
      if Position = CurrentPosition then
      begin
        Color := FCurrentSearchHitColor;
      end;
      PaintQuads(Painter, Placement, Hits[Position].Quads, Color);
    end;
  end;
end;

procedure TPdfPageViewController.PaintQuads(const Painter: IPdfViewPainter; const Placement: TPlacement; const Quads: TArray<TPdfQuad>;
                                            const Color: TAlphaColor);
begin
  for var Quad in Quads do
  begin
    const Polygon = ViewPolygonOf(Placement, Quad);
    Painter.FillPolygon(Polygon, Color);
  end;
end;

procedure TPdfPageViewController.PaintOverlays(const Painter: IPdfViewPainter; const Placements: TArray<TPlacement>);
begin
  for var Placement in Placements do
  begin
    const Overlays = Document.Overlays.OnPage(Placement.PageIndex);
    for var Overlay in Overlays do
    begin
      PaintOverlay(Painter, Placement, Overlay);
    end;
  end;
end;

procedure TPdfPageViewController.PaintOverlay(const Painter: IPdfViewPainter; const Placement: TPlacement; const Overlay: TPdfOverlay);
begin
  case Overlay.Style of
    TPdfOverlayStyle.Fill:
      PaintQuads(Painter, Placement, Overlay.Quads, Overlay.Color);
    TPdfOverlayStyle.Frame:
      begin
        const FrameWidth = ScaledPixels(OverlayFrameWidth);
        for var Quad in Overlay.Quads do
        begin
          const Polygon = ViewPolygonOf(Placement, Quad);
          Painter.FramePolygon(Polygon, Overlay.Color, FrameWidth);
        end;
      end;
    TPdfOverlayStyle.Ellipse:
      PaintEllipseOverlay(Painter, Placement, Overlay);
  else
    raise ENotSupportedException.CreateFmt('Unsupported overlay style: %d', [Ord(Overlay.Style)]);
  end;
end;

// One ellipse around all quads: the bounding rectangle, enlarged so that the ellipse passes through its corners
procedure TPdfPageViewController.PaintEllipseOverlay(const Painter: IPdfViewPainter; const Placement: TPlacement; const Overlay: TPdfOverlay);
begin
  var Bounds: TRectF;
  const Points = ViewPointsOf(Placement, Overlay.Quads);
  if not TryGetBoundsOf(Points, Bounds) then
  begin
    Exit;
  end;

  const Center = TPointF.Create((Bounds.Left + Bounds.Right) / 2, (Bounds.Top + Bounds.Bottom) / 2);
  const HalfWidth = (Bounds.Right - Bounds.Left) / 2 * EllipseEnlargement;
  const HalfHeight = (Bounds.Bottom - Bounds.Top) / 2 * EllipseEnlargement;
  const EllipseRect = TRectF.Create(Center.X - HalfWidth, Center.Y - HalfHeight, Center.X + HalfWidth, Center.Y + HalfHeight);
  Painter.FillEllipse(EllipseRect, Overlay.Color);
end;

class function TPdfPageViewController.OffsetPoints(const Points: TArray<TPointF>; const Origin: TPointF): TArray<TPointF>;
begin
  SetLength(Result, Length(Points));
  for var Index := 0 to High(Points) do
  begin
    Result[Index] := TPointF.Create(Points[Index].X + Origin.X, Points[Index].Y + Origin.Y);
  end;
end;

class function TPdfPageViewController.ViewPolygonOf(const Placement: TPlacement; const Quad: TPdfQuad): TArray<TPointF>;
begin
  const Corners = Placement.Transform.QuadToView(Quad);
  Result := OffsetPoints(Corners, Placement.Origin);
end;

class function TPdfPageViewController.ViewPointsOf(const Placement: TPlacement; const Quads: TArray<TPdfQuad>): TArray<TPointF>;
begin
  Result := nil;
  for var Quad in Quads do
  begin
    const Polygon = ViewPolygonOf(Placement, Quad);
    Result := Result + Polygon;
  end;
end;

class function TPdfPageViewController.TryGetBoundsOf(const Points: TArray<TPointF>; out Bounds: TRectF): Boolean;
begin
  Bounds := TRectF.Empty;
  Result := (Length(Points) > 0);
  if not Result then
  begin
    Exit;
  end;

  Bounds := TRectF.Create(Points[0], Points[0]);
  for var Point in Points do
  begin
    Bounds.Left := Min(Bounds.Left, Point.X);
    Bounds.Top := Min(Bounds.Top, Point.Y);
    Bounds.Right := Max(Bounds.Right, Point.X);
    Bounds.Bottom := Max(Bounds.Bottom, Point.Y);
  end;
end;

end.
