// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.ViewLayout;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.ViewTransform;

type
  // Places the pages of a document in content coordinates (pixels, origin top left): below each other and centred horizontally in
  // continuous mode, or only the current page in single page mode. Not thread safe; used on the UI thread.
  TPdfViewLayout = class
  private
    FPages: TArray<TPdfPageInfo>;
    FViewRotation: Integer;
    FZoom: Single;
    FPixelsPerInch: Single;
    FMode: TPdfScrollMode;
    FCurrentPage: Integer;
    FGap: Integer;
    FSizes: TArray<TSize>;
    // Top of each page; in single page mode only the entry of the current page is used. Ascending in continuous mode, which the
    // binary searches rely on.
    FTops: TArray<Integer>;
    FContentSize: TSize;

    class procedure ValidateArguments(const ViewRotation: Integer; const Zoom, PixelsPerInch: Single); static;
    class function ClampToInteger(const Value: Int64): Integer; static;

    function EffectiveZoom(const PageIndex: Integer): Single;
    function UprightSize(const PageIndex: Integer): TSize;
    procedure ComputeSizes;
    procedure PlaceContinuous;
    procedure PlaceCurrentPage;
    function PageRectOf(const PageIndex: Integer): TRect;
    function HasRect(const PageIndex: Integer): Boolean;
    function FirstPageBelow(const Y: Integer): Integer;
    function VisibleHeight(const PageIndex: Integer; const Viewport: TRect): Integer;
    procedure CheckPageIndex(const PageIndex: Integer);

  public
    constructor Create(const Pages: TArray<TPdfPageInfo>);

    procedure Update(const ViewRotation: Integer; const Zoom, PixelsPerInch: Single; const Mode: TPdfScrollMode; const CurrentPage: Integer);
    function ContentSize: TSize;
    // Content coordinates. SinglePage: only CurrentPage has a rectangle, the others give False.
    function TryGetPageRect(const PageIndex: Integer; out Rect: TRect): Boolean;
    // The transform of the page at the zoom of the last Update, clamped so that no side of the page exceeds MaxPageEdgePixels.
    // Raises EArgumentOutOfRangeException for an index outside the pages.
    function Transform(const PageIndex: Integer): TPdfViewTransform;
    function TryFindPageAt(const ContentPoint: TPoint; out PageIndex: Integer): Boolean;
    // Ascending; only the vertical extent of the viewport counts
    function VisiblePages(const Viewport: TRect): TArray<Integer>;
    // The page with the largest visible height, the lowest index on a tie; 0 without pages
    function MostVisiblePage(const Viewport: TRect): Integer;
    // Factor gives the zoom of the last Update. FitWidth and FitPage are clamped to MinZoom..MaxZoom.
    function ZoomToFit(const Mode: TPdfZoomMode; const ViewportSize: TSize; const PageIndex: Integer): Single;
    function Gap: Integer;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Pdf4D.Render.PageTransform;

const
  PointsPerInch = 72;
  LogicalPixelsPerInch = 96;
  FullTurn = 360;
  RightAngle = 90;

{ TPdfViewLayout }

constructor TPdfViewLayout.Create(const Pages: TArray<TPdfPageInfo>);
begin
  inherited Create;
  FPages := Copy(Pages);
  Update(0, 1, LogicalPixelsPerInch, TPdfScrollMode.Continuous, 0);
end;

class procedure TPdfViewLayout.ValidateArguments(const ViewRotation: Integer; const Zoom, PixelsPerInch: Single);
begin
  const IsRotationValid = (((ViewRotation mod RightAngle) = 0) and (ViewRotation >= 0) and (ViewRotation < FullTurn));
  if not IsRotationValid then
  begin
    raise EArgumentException.CreateFmt('View rotation %d is not 0, 90, 180 or 270', [ViewRotation]);
  end;

  const IsZoomValid = ((Zoom > 0) and not IsInfinite(Zoom));
  if not IsZoomValid then
  begin
    raise EArgumentException.CreateFmt('Zoom %g is not above zero', [Double(Zoom)]);
  end;

  const IsPixelsPerInchValid = ((PixelsPerInch > 0) and not IsInfinite(PixelsPerInch));
  if not IsPixelsPerInchValid then
  begin
    raise EArgumentException.CreateFmt('Pixels per inch %g is not above zero', [Double(PixelsPerInch)]);
  end;
end;

class function TPdfViewLayout.ClampToInteger(const Value: Int64): Integer;
begin
  Result := Integer(Min(Value, Int64(MaxInt)));
end;

procedure TPdfViewLayout.Update(const ViewRotation: Integer; const Zoom, PixelsPerInch: Single; const Mode: TPdfScrollMode;
                                const CurrentPage: Integer);
begin
  ValidateArguments(ViewRotation, Zoom, PixelsPerInch);

  FViewRotation := ViewRotation;
  FZoom := Zoom;
  FPixelsPerInch := PixelsPerInch;
  FMode := Mode;
  FCurrentPage := Max(0, Min(CurrentPage, Length(FPages) - 1));
  // A gap beyond the largest page side would only make the sums overflow
  FGap := Round(Min(PageGap * Double(PixelsPerInch) / LogicalPixelsPerInch, Double(MaxPageEdgePixels)));

  ComputeSizes;
  if FMode = TPdfScrollMode.Continuous then
  begin
    PlaceContinuous;
  end
  else
  begin
    PlaceCurrentPage;
  end;
end;

function TPdfViewLayout.EffectiveZoom(const PageIndex: Integer): Single;
begin
  Result := FZoom;

  const CropBox = FPages[PageIndex].CropBox;
  const LongestSide = Max(CropBox.Width, CropBox.Height);
  const HasArea = (LongestSide > 0);
  if not HasArea then
  begin
    Exit;
  end;

  const LargestZoom = MaxPageEdgePixels * Double(PointsPerInch) / (Double(FPixelsPerInch) * LongestSide);
  if LargestZoom < FZoom then
  begin
    Result := LargestZoom;
  end;
end;

function TPdfViewLayout.UprightSize(const PageIndex: Integer): TSize;
begin
  Result := TPdfPageTransform.Create(FPages[PageIndex].CropBox, (FPages[PageIndex].Rotation + FViewRotation) mod FullTurn,
                                     FPixelsPerInch / PointsPerInch).Size;
end;

procedure TPdfViewLayout.ComputeSizes;
begin
  SetLength(FSizes, Length(FPages));
  for var PageIndex := 0 to High(FPages) do
  begin
    FSizes[PageIndex] := Transform(PageIndex).Size;
  end;
end;

procedure TPdfViewLayout.PlaceContinuous;
begin
  SetLength(FTops, Length(FPages));

  var Top: Int64 := FGap;
  var WidestPage: Int64 := 0;
  for var PageIndex := 0 to High(FPages) do
  begin
    FTops[PageIndex] := ClampToInteger(Top);
    Top := Top + FSizes[PageIndex].cy + FGap;
    WidestPage := Max(WidestPage, Int64(FSizes[PageIndex].cx));
  end;

  const HasPages = (Length(FPages) > 0);
  if HasPages then
  begin
    FContentSize := TSize.Create(ClampToInteger(WidestPage + 2 * Int64(FGap)), ClampToInteger(Top));
  end
  else
  begin
    FContentSize := TSize.Create(0, 0);
  end;
end;

procedure TPdfViewLayout.PlaceCurrentPage;
begin
  SetLength(FTops, Length(FPages));

  const HasPages = (Length(FPages) > 0);
  if not HasPages then
  begin
    FContentSize := TSize.Create(0, 0);
    Exit;
  end;

  FTops[FCurrentPage] := FGap;
  const Current = FSizes[FCurrentPage];
  FContentSize := TSize.Create(ClampToInteger(Int64(Current.cx) + 2 * Int64(FGap)), ClampToInteger(Int64(Current.cy) + 2 * Int64(FGap)));
end;

function TPdfViewLayout.HasRect(const PageIndex: Integer): Boolean;
begin
  const IsInRange = ((PageIndex >= 0) and (PageIndex < Length(FPages)));
  Result := (IsInRange and ((FMode = TPdfScrollMode.Continuous) or (PageIndex = FCurrentPage)));
end;

function TPdfViewLayout.PageRectOf(const PageIndex: Integer): TRect;
begin
  const PageSize = FSizes[PageIndex];
  const Left = (FContentSize.cx - PageSize.cx) div 2;
  const Top = FTops[PageIndex];
  Result := TRect.Create(Left, Top, Left + PageSize.cx, ClampToInteger(Int64(Top) + PageSize.cy));
end;

procedure TPdfViewLayout.CheckPageIndex(const PageIndex: Integer);
begin
  const IsInRange = ((PageIndex >= 0) and (PageIndex < Length(FPages)));
  if not IsInRange then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('Page index %d is outside the %d pages', [PageIndex, Length(FPages)]);
  end;
end;

function TPdfViewLayout.ContentSize: TSize;
begin
  Result := FContentSize;
end;

function TPdfViewLayout.Gap: Integer;
begin
  Result := FGap;
end;

function TPdfViewLayout.TryGetPageRect(const PageIndex: Integer; out Rect: TRect): Boolean;
begin
  Result := HasRect(PageIndex);
  if Result then
  begin
    Rect := PageRectOf(PageIndex);
  end
  else
  begin
    Rect := TRect.Empty;
  end;
end;

function TPdfViewLayout.Transform(const PageIndex: Integer): TPdfViewTransform;
begin
  CheckPageIndex(PageIndex);
  Result := TPdfViewTransform.Create(FPages[PageIndex], FViewRotation, EffectiveZoom(PageIndex), FPixelsPerInch);
end;

// The first page whose bottom lies below Y; the page count when there is none. Continuous mode only.
function TPdfViewLayout.FirstPageBelow(const Y: Integer): Integer;
begin
  var First := 0;
  var Past := Length(FPages);
  while First < Past do
  begin
    const Middle = First + (Past - First) div 2;
    const Bottom = Int64(FTops[Middle]) + FSizes[Middle].cy;
    if Bottom > Y then
    begin
      Past := Middle;
    end
    else
    begin
      First := Middle + 1;
    end;
  end;
  Result := First;
end;

function TPdfViewLayout.TryFindPageAt(const ContentPoint: TPoint; out PageIndex: Integer): Boolean;
begin
  PageIndex := 0;
  Result := False;

  const HasPages = (Length(FPages) > 0);
  if not HasPages then
  begin
    Exit;
  end;

  if FMode = TPdfScrollMode.SinglePage then
  begin
    PageIndex := FCurrentPage;
  end
  else
  begin
    PageIndex := FirstPageBelow(ContentPoint.Y);
    const IsBeyondLastPage = (PageIndex >= Length(FPages));
    if IsBeyondLastPage then
    begin
      Exit;
    end;
  end;

  Result := PageRectOf(PageIndex).Contains(ContentPoint);
end;

function TPdfViewLayout.VisiblePages(const Viewport: TRect): TArray<Integer>;
begin
  Result := nil;

  const IsViewportEmpty = (Viewport.Bottom <= Viewport.Top);
  const HasPages = (Length(FPages) > 0);
  if IsViewportEmpty or not HasPages then
  begin
    Exit;
  end;

  if FMode = TPdfScrollMode.SinglePage then
  begin
    const IsVisible = (VisibleHeight(FCurrentPage, Viewport) > 0);
    if IsVisible then
    begin
      Result := [FCurrentPage];
    end;
    Exit;
  end;

  var PageIndex := FirstPageBelow(Viewport.Top);
  while (PageIndex < Length(FPages)) and (FTops[PageIndex] < Viewport.Bottom) do
  begin
    Result := Result + [PageIndex];
    Inc(PageIndex);
  end;
end;

function TPdfViewLayout.VisibleHeight(const PageIndex: Integer; const Viewport: TRect): Integer;
begin
  const PageRect = PageRectOf(PageIndex);
  Result := Max(0, Min(PageRect.Bottom, Viewport.Bottom) - Max(PageRect.Top, Viewport.Top));
end;

function TPdfViewLayout.MostVisiblePage(const Viewport: TRect): Integer;
begin
  Result := 0;

  var LargestHeight := 0;
  for var PageIndex in VisiblePages(Viewport) do
  begin
    const Height = VisibleHeight(PageIndex, Viewport);
    const IsLarger = (Height > LargestHeight);
    if IsLarger then
    begin
      LargestHeight := Height;
      Result := PageIndex;
    end;
  end;
end;

function TPdfViewLayout.ZoomToFit(const Mode: TPdfZoomMode; const ViewportSize: TSize; const PageIndex: Integer): Single;
begin
  CheckPageIndex(PageIndex);

  const PageSize = UprightSize(PageIndex);
  const AvailableWidth = ViewportSize.cx - 2 * FGap;
  const AvailableHeight = ViewportSize.cy - 2 * FGap;
  const WidthZoom = AvailableWidth / PageSize.cx;
  const HeightZoom = AvailableHeight / PageSize.cy;

  case Mode of
    TPdfZoomMode.Factor   : Result := FZoom;
    TPdfZoomMode.FitWidth : Result := Max(MinZoom, Min(MaxZoom, WidthZoom));
    TPdfZoomMode.FitPage  : Result := Max(MinZoom, Min(MaxZoom, Min(WidthZoom, HeightZoom)));
  else
    raise ENotSupportedException.CreateFmt('Unsupported zoom mode: %d', [Ord(Mode)]);
  end;
end;

end.
