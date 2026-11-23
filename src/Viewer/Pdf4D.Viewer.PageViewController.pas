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
  Pdf4D.Viewer.Types,
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
    // What the last layout was made with: failed tiles are tried again only when this changes
    FLaidOutZoom: Single;
    FLaidOutPixelsPerInch: Single;
    FLaidOutRotation: Integer;
    FNotifiedZoom: Single;

    function GetDocument: TPdf4DCustomDocument;
    procedure SetDocument(const Value: TPdf4DCustomDocument);
    procedure SetZoom(const Value: Single);
    procedure SetZoomMode(const Value: TPdfZoomMode);
    procedure SetViewRotation(const Value: Integer);
    procedure SetScrollMode(const Value: TPdfScrollMode);
    procedure SetTileCacheBytes(const Value: Int64);

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
    procedure CancelUnneeded(const Wants: TList<TPageWant>; const VisiblePages: TArray<Integer>);
    class function IsPageIn(const Pages: TArray<Integer>; const PageIndex: Integer): Boolean; static;
    procedure CancelTileRequest(const Request: TTileRequest);
    procedure CancelAllRequests;
    procedure RequestMissingTiles(const Want: TPageWant);
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
    class function IsUsableLayer(const Layer: TTileLayer; const Transform: TPdfViewTransform): Boolean; static;
    function TryGetFallbackLayer(const PageIndex: Integer; const Transform: TPdfViewTransform; out Layer: TTileLayer): Boolean;
    procedure PaintSearchHits(const Painter: IPdfViewPainter; const Placements: TArray<TPlacement>);
    procedure PaintQuads(const Painter: IPdfViewPainter; const Placement: TPlacement; const Quads: TArray<TPdfQuad>; const Color: TAlphaColor);
    procedure PaintOverlays(const Painter: IPdfViewPainter; const Placements: TArray<TPlacement>);
    procedure PaintOverlay(const Painter: IPdfViewPainter; const Placement: TPlacement; const Overlay: TPdfOverlay);
    procedure PaintEllipseOverlay(const Painter: IPdfViewPainter; const Placement: TPlacement; const Overlay: TPdfOverlay);
    class function OffsetPoints(const Points: TArray<TPointF>; const Origin: TPointF): TArray<TPointF>; static;

  public
    constructor Create(const Host: IPdfViewHost);
    destructor Destroy; override;

    // A change of PixelsPerInch re-renders at the new scale and keeps the page in view
    procedure SetViewport(const Size: TSize; const PixelsPerInch: Single);
    // Clamped
    procedure ScrollTo(const Position: TPoint);
    procedure ScrollBy(const DeltaX, DeltaY: Integer);
    procedure GoToPage(const PageIndex: Integer);
    procedure ZoomIn;
    procedure ZoomOut;
    // Keeps the PDF point under ViewportPoint in place
    procedure ZoomAt(const Zoom: Single; const ViewportPoint: TPointF);
    procedure RotateClockwise;
    procedure RotateCounterclockwise;
    procedure Paint(const Painter: IPdfViewPainter; const ClipRect: TRect);
    function ContentSize: TSize;
    function ScrollPosition: TPoint;
    // The bytes that the cached tiles take
    function TileCacheCost: Int64;
    // PagePoint is in PDF user space
    function ViewportToPage(const Point: TPointF; out PageIndex: Integer; out PagePoint: TPointF): Boolean;

    // Through an internal link; a document that is already open is shown at once
    property Document: TPdf4DCustomDocument read GetDocument write SetDocument;
    // Setting it sets ZoomMode to Factor; clamped to MinZoom..MaxZoom
    property Zoom: Single read FZoom write SetZoom;
    property ZoomMode: TPdfZoomMode read FZoomMode write SetZoomMode;
    // 0, 90, 180 or 270
    property ViewRotation: Integer read FViewRotation write SetViewRotation;
    property ScrollMode: TPdfScrollMode read FScrollMode write SetScrollMode;
    property TileCacheBytes: Int64 read FTileCacheBytes write SetTileCacheBytes;
    property HoverColor: TAlphaColor read FHoverColor write FHoverColor;
    property SelectionColor: TAlphaColor read FSelectionColor write FSelectionColor;
    property SearchHitColor: TAlphaColor read FSearchHitColor write FSearchHitColor;
    property CurrentSearchHitColor: TAlphaColor read FCurrentSearchHitColor write FCurrentSearchHitColor;
    property BackgroundColor: TAlphaColor read FBackgroundColor write FBackgroundColor;
    property OnZoomChanged: TNotifyEvent read FOnZoomChanged write FOnZoomChanged;
  end;

implementation

uses
  System.Math,
  Pdf4D.Viewer.PageText;

const
  ZoomSteps: array[0..11] of Single = (0.1, 0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 3, 4, 6, 8);
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

{ TPdfPageViewController }

constructor TPdfPageViewController.Create(const Host: IPdfViewHost);
begin
  inherited Create;
  FHost := Host;
  FPixelsPerInch := LogicalPixelsPerInch;
  FZoom := 1;
  FNotifiedZoom := 1;
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

  const IsOurOwnChange = (FPageSyncLock > 0);
  const IsAlreadyThere = (Document.CurrentPage = FLayout.MostVisiblePage(ViewportContentRect));
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
    Result := Max(0, (FViewport.cx - FLayout.ContentSize.cx) div 2);
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
  var PageIndex: Integer;
  const IsOnPage = FLayout.TryFindPageAt(TPoint.Create(Floor(Content.X), Floor(Content.Y)), PageIndex);
  if not IsOnPage then
  begin
    PageIndex := FLayout.MostVisiblePage(ViewportContentRect);
  end;

  var Rect: TRect;
  if not FLayout.TryGetPageRect(PageIndex, Rect) then
  begin
    Exit;
  end;

  Result.IsValid := True;
  Result.PageIndex := PageIndex;
  Result.ViewportPoint := ViewportPoint;
  Result.PdfPoint := FLayout.Transform(PageIndex).ViewToPage(TPointF.Create(Content.X - Rect.Left, Content.Y - Rect.Top));
end;

procedure TPdfPageViewController.RestoreAnchor(const Anchor: TAnchor);
begin
  var Rect: TRect;
  if (not Anchor.IsValid) or (not FLayout.TryGetPageRect(Anchor.PageIndex, Rect)) then
  begin
    Exit;
  end;

  const View = FLayout.Transform(Anchor.PageIndex).PageToView(Anchor.PdfPoint);
  const ScrollX = Rect.Left + View.X + CenteringOffset - Anchor.ViewportPoint.X;
  const ScrollY = Rect.Top + View.Y - Anchor.ViewportPoint.Y;
  FScroll.X := Round(EnsureRange(ScrollX, -MaxScrollValue, MaxScrollValue));
  FScroll.Y := Round(EnsureRange(ScrollY, -MaxScrollValue, MaxScrollValue));
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
  if FZoom = FNotifiedZoom then
  begin
    Exit;
  end;

  FNotifiedZoom := FZoom;
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

  const MostVisible = FLayout.MostVisiblePage(ViewportContentRect);
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
  ZoomToFactor(NextZoomStep(True), ViewportCenter);
end;

procedure TPdfPageViewController.ZoomOut;
begin
  ZoomToFactor(NextZoomStep(False), ViewportCenter);
end;

procedure TPdfPageViewController.ZoomAt(const Zoom: Single; const ViewportPoint: TPointF);
begin
  ZoomToFactor(Zoom, ViewportPoint);
end;

function TPdfPageViewController.NextZoomStep(const Upwards: Boolean): Single;
begin
  if Upwards then
  begin
    for var Step in ZoomSteps do
    begin
      if Step > FZoom + ZoomStepTolerance then
      begin
        Exit(Step);
      end;
    end;
    Exit(MaxZoom);
  end;

  for var Index := High(ZoomSteps) downto Low(ZoomSteps) do
  begin
    if ZoomSteps[Index] < FZoom - ZoomStepTolerance then
    begin
      Exit(ZoomSteps[Index]);
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
  var Rect: TRect;
  const IsOnPage = FLayout.TryFindPageAt(TPoint.Create(Floor(Content.X), Floor(Content.Y)), PageIndex) and
                   FLayout.TryGetPageRect(PageIndex, Rect);
  if IsOnPage then
  begin
    PagePoint := FLayout.Transform(PageIndex).ViewToPage(TPointF.Create(Content.X - Rect.Left, Content.Y - Rect.Top));
    Result := True;
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

  const VisiblePages = FLayout.VisiblePages(ViewportContentRect);
  const Wants = TList<TPageWant>.Create;
  try
    for var PageIndex in VisiblePages do
    begin
      Wants.Add(VisibleWant(PageIndex));
    end;

    const HasVisiblePages = (Length(VisiblePages) > 0);
    if HasVisiblePages and (FScrollMode = TPdfScrollMode.Continuous) then
    begin
      const PageBefore = VisiblePages[0] - 1;
      const PageAfter = VisiblePages[High(VisiblePages)] + 1;
      if PageBefore >= 0 then
      begin
        Wants.Add(PrefetchWant(PageBefore, False));
      end;
      if PageAfter < Length(FPages) then
      begin
        Wants.Add(PrefetchWant(PageAfter, True));
      end;
    end;

    CancelUnneeded(Wants, VisiblePages);

    for var Want in Wants do
    begin
      if Want.Priority = TPdfJobPriority.Visible then
      begin
        RequestMissingTiles(Want);
      end;
    end;

    RequestPageTexts(VisiblePages);

    for var Want in Wants do
    begin
      if Want.Priority = TPdfJobPriority.Prefetch then
      begin
        RequestMissingTiles(Want);
      end;
    end;
  finally
    Wants.Free;
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
    Area := TRect.Intersect(ViewportContentRect, Rect);
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
  const Needed = TDictionary<TPdfTileKey, Boolean>.Create;
  try
    for var Want in Wants do
    begin
      for var Tile in Want.Tiles do
      begin
        Needed.AddOrSetValue(TPdfTileKey.Create(Want.PageIndex, Want.Rotation, Want.Scale, Tile.X, Tile.Y), True);
      end;
    end;

    for var Index := FTileRequests.Count - 1 downto 0 do
    begin
      const Request = FTileRequests[Index];
      var IsNeeded := False;
      for var Key in Request.Keys do
      begin
        var Pending: TTileRequest;
        const IsPending = FPendingTiles.TryGetValue(Key, Pending) and (Pending = Request);
        if IsPending and Needed.ContainsKey(Key) then
        begin
          IsNeeded := True;
          Break;
        end;
      end;

      if not IsNeeded then
      begin
        CancelTileRequest(Request);
      end;
    end;
  finally
    Needed.Free;
  end;

  for var Page in FTextRequests.Keys.ToArray do
  begin
    if not IsPageIn(VisiblePages, Page) then
    begin
      FTextRequests[Page].Cancel;
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
  Request.Request.Cancel;
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
    Request.Request.Cancel;
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

    if Missing.Count = 0 then
    begin
      Exit;
    end;

    const Request = TTileRequest.Create;
    try
      Request.PageIndex := Want.PageIndex;
      Request.Rotation := Want.Rotation;
      Request.Scale := Want.Scale;
      Request.Keys := Keys.ToArray;
      Request.Remaining := Keys.Count;
      Request.Request := Document.Session.RequestTiles(Want.PageIndex, Want.Scale, Want.Rotation, Missing.ToArray, Want.Priority,
                                                       TileDoneEvent(Request));
    except
      Request.Free;
      raise;
    end;

    FTileRequests.Add(Request);
    for var Key in Request.Keys do
    begin
      FPendingTiles.Add(Key, Request);
    end;
  finally
    Keys.Free;
    Missing.Free;
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
      FTextRequests.Add(Page, Document.RequestPageText(Page, TPdfJobPriority.PageText,
        procedure(const Text: IPdfPageText)
        begin
          FTextRequests.Remove(Page);
        end));
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
  Painter.FillRect(TRectF.Create(ClipRect), FBackgroundColor);
  if not Assigned(FLayout) then
  begin
    Exit;
  end;

  var ContentClip := ClipRect;
  ContentClip.Offset(FScroll.X - CenteringOffset, FScroll.Y);
  const Placements = PlacementsOf(FLayout.VisiblePages(ContentClip));

  for var Placement in Placements do
  begin
    PaintPage(Painter, Placement, ClipRect);
  end;

  PaintSearchHits(Painter, Placements);
  PaintOverlays(Painter, Placements);
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

  Painter.FillRect(TRectF.Create(Visible), PageColor);

  Visible.Offset(-PageRect.Left, -PageRect.Top);
  for var Tile in TPdfTileGrid.TilesIn(Size, Visible) do
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
  Painter.DrawImage(Image, TRect.Create(0, 0, Image.Width, Image.Height), Dest);
end;

// What a tile shows until it arrives: the tiles of the scale that the page showed before, scaled to this one
procedure TPdfPageViewController.PaintFallback(const Painter: IPdfViewPainter; const Placement: TPlacement; const TileRect: TRect);
begin
  var Layer: TTileLayer;
  if not TryGetFallbackLayer(Placement.PageIndex, Placement.Transform, Layer) then
  begin
    Exit;
  end;

  const OldSize = TPdfViewTransform.Create(FPages[Placement.PageIndex], Layer.Rotation, Layer.Scale, 72).Size;
  const NewSize = Placement.Transform.Size;
  const RatioX = OldSize.cx / NewSize.cx;
  const RatioY = OldSize.cy / NewSize.cy;
  const Source = TRect.Create(Floor(TileRect.Left * RatioX), Floor(TileRect.Top * RatioY), Ceil(TileRect.Right * RatioX),
                              Ceil(TileRect.Bottom * RatioY));

  for var OldTile in TPdfTileGrid.TilesIn(OldSize, Source) do
  begin
    var Image: IPdfViewImage;
    const Key = TPdfTileKey.Create(Placement.PageIndex, Layer.Rotation, Layer.Scale, OldTile.X, OldTile.Y);
    if not FTiles.TryGet(Key, Image) then
    begin
      Continue;
    end;

    const OldTileRect = TPdfTileGrid.TileRect(OldSize, OldTile.X, OldTile.Y);
    const Part = TRect.Intersect(OldTileRect, Source);
    if Part.IsEmpty then
    begin
      Continue;
    end;

    const ImagePart = TRect.Create(Part.Left - OldTileRect.Left, Part.Top - OldTileRect.Top, Part.Right - OldTileRect.Left,
                                   Part.Bottom - OldTileRect.Top);
    const Dest = TRectF.Create(Placement.Origin.X + Part.Left / RatioX, Placement.Origin.Y + Part.Top / RatioY,
                               Placement.Origin.X + Part.Right / RatioX, Placement.Origin.Y + Part.Bottom / RatioY);
    Painter.DrawImage(Image, ImagePart, Dest);
  end;
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
  const Hits = Document.SearchHits;
  if (Length(Hits) = 0) or (Length(Placements) = 0) then
  begin
    Exit;
  end;

  var CurrentIndex := -1;
  var CurrentHit: TPdfSearchHit;
  if not Document.TryGetCurrentSearchHit(CurrentIndex, CurrentHit) then
  begin
    CurrentIndex := -1;
  end;

  const FirstPage = Placements[0].PageIndex;
  for var Index := 0 to High(Hits) do
  begin
    const Slot = Hits[Index].PageIndex - FirstPage;
    const IsVisible = (Slot >= 0) and (Slot < Length(Placements));
    if IsVisible then
    begin
      var Color := FSearchHitColor;
      if Index = CurrentIndex then
      begin
        Color := FCurrentSearchHitColor;
      end;
      PaintQuads(Painter, Placements[Slot], Hits[Index].Quads, Color);
    end;
  end;
end;

procedure TPdfPageViewController.PaintQuads(const Painter: IPdfViewPainter; const Placement: TPlacement; const Quads: TArray<TPdfQuad>;
                                            const Color: TAlphaColor);
begin
  for var Quad in Quads do
  begin
    Painter.FillPolygon(OffsetPoints(Placement.Transform.QuadToView(Quad), Placement.Origin), Color);
  end;
end;

procedure TPdfPageViewController.PaintOverlays(const Painter: IPdfViewPainter; const Placements: TArray<TPlacement>);
begin
  for var Placement in Placements do
  begin
    for var Overlay in Document.Overlays.OnPage(Placement.PageIndex) do
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
      for var Quad in Overlay.Quads do
      begin
        Painter.FramePolygon(OffsetPoints(Placement.Transform.QuadToView(Quad), Placement.Origin), Overlay.Color,
                             OverlayFrameWidth * FPixelsPerInch / LogicalPixelsPerInch);
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
  var Bounds := TRectF.Empty;
  var IsFirst := True;
  for var Quad in Overlay.Quads do
  begin
    for var Point in OffsetPoints(Placement.Transform.QuadToView(Quad), Placement.Origin) do
    begin
      if IsFirst then
      begin
        Bounds := TRectF.Create(Point, Point);
        IsFirst := False;
      end
      else
      begin
        Bounds.Left := Min(Bounds.Left, Point.X);
        Bounds.Top := Min(Bounds.Top, Point.Y);
        Bounds.Right := Max(Bounds.Right, Point.X);
        Bounds.Bottom := Max(Bounds.Bottom, Point.Y);
      end;
    end;
  end;

  if IsFirst then
  begin
    Exit;
  end;

  const Center = TPointF.Create((Bounds.Left + Bounds.Right) / 2, (Bounds.Top + Bounds.Bottom) / 2);
  const HalfWidth = (Bounds.Right - Bounds.Left) / 2 * EllipseEnlargement;
  const HalfHeight = (Bounds.Bottom - Bounds.Top) / 2 * EllipseEnlargement;
  Painter.FillEllipse(TRectF.Create(Center.X - HalfWidth, Center.Y - HalfHeight, Center.X + HalfWidth, Center.Y + HalfHeight), Overlay.Color);
end;

class function TPdfPageViewController.OffsetPoints(const Points: TArray<TPointF>; const Origin: TPointF): TArray<TPointF>;
begin
  SetLength(Result, Length(Points));
  for var Index := 0 to High(Points) do
  begin
    Result[Index] := TPointF.Create(Points[Index].X + Origin.X, Points[Index].Y + Origin.Y);
  end;
end;

end.
