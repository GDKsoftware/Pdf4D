// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.ViewerFuzz;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils;

type
  // The Viewer work of the fuzz runs: what a viewer does with a document, from the other side of the session
  TViewerFuzzProbe = class
  public
    // Opens the bytes in a session with a recording backend. When the document opens, every page (up to the first ViewedPages) gets its
    // tiles at scale 0.5, its text and a hit test on 20 points, and the document is searched once. A document that does not open, and a
    // render that fails, are fine; an exception that is not a PDF exception, a hang or a leak is not. Runs on the calling thread, which
    // plays the UI thread.
    class procedure Run(const Bytes: TBytes; const Password: string); static;
  end;

implementation

uses
  System.Types,
  System.Classes,
  System.Math,
  System.Generics.Collections,
  Pdf4D.Common.Defines,
  Pdf4D.Api.Page.Interfaces,
  Pdf4D.Api.TextLayout.Interfaces,
  Pdf4D.Common.Quad,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.Dispatcher,
  Pdf4D.Viewer.PageText,
  Pdf4D.Viewer.Session,
  Pdf4D.Viewer.Tiles,
  Pdf4D.Viewer.ViewTransform,
  Pdf4D.Tests.Fuzz,
  Pdf4D.Tests.ManualDispatcher,
  Pdf4D.Tests.RecordingDevice;

const
  ViewedPages = 10;
  TileScale = 0.5;
  PixelsPerInch = 72;
  // The part of a page that is asked for, in pixels: a hostile page size must not ask for millions of tiles
  MaxViewedPixels = 2048;
  HitColumns = 5;
  HitRows = 4;
  SearchQuery = 'a';
  MillisecondsPerSecond = 1000;

type
  TViewerFuzzRun = class
  strict private
    FDispatcher: TManualDispatcher;
    FDispatcherReference: IPdfViewerDispatcher;
    FSession: IPdfViewerSession;
    FRequests: TList<IPdfViewerRequest>;
    FIsOpenDone: Boolean;
    FIsOpened: Boolean;

    procedure RunUntil(const Condition: TFunc<Boolean>);
    procedure Open(const Bytes: TBytes; const Password: string);
    procedure ViewPage(const PageIndex: Integer);
    procedure RequestTiles(const PageIndex: Integer);
    procedure RequestTextAndHitTest(const PageIndex: Integer);
    procedure RequestSearch;
    function AreRequestsDone: Boolean;
    class procedure HitTest(const PageText: IPdfPageText; const Page: TPdfPageInfo); static;

  public
    constructor Create;
    destructor Destroy; override;

    procedure Execute(const Bytes: TBytes; const Password: string);
  end;

{ TViewerFuzzRun }

constructor TViewerFuzzRun.Create;
begin
  inherited Create;
  FDispatcher := TManualDispatcher.Create;
  FDispatcherReference := FDispatcher;
  FRequests := TList<IPdfViewerRequest>.Create;
  const Backend: IPdfRenderBackend = TRecordingBackend.Create;
  FSession := TPdfViewerSession.Create(Backend, FDispatcherReference, nil);
end;

destructor TViewerFuzzRun.Destroy;
begin
  // Cancel what is left, and wait for the worker
  for var Request in FRequests do
  begin
    Request.Cancel;
  end;
  FSession := nil;
  FRequests.Free;
  FDispatcherReference := nil;
  inherited;
end;

procedure TViewerFuzzRun.RunUntil(const Condition: TFunc<Boolean>);
begin
  if not FDispatcher.RunUntil(Condition, TFuzzSettings.TimeLimitSeconds * MillisecondsPerSecond) then
  begin
    raise EInvalidOpException.Create('The viewer session did not answer in time');
  end;
end;

procedure TViewerFuzzRun.Open(const Bytes: TBytes; const Password: string);
begin
  FSession.Open(Bytes, Password,
    procedure(const Result: TPdfOpenResult)
    begin
      FIsOpened := Result.Succeeded;
      FIsOpenDone := True;
    end);
  RunUntil(
    function: Boolean
    begin
      Result := FIsOpenDone;
    end);
end;

function TViewerFuzzRun.AreRequestsDone: Boolean;
begin
  Result := True;
  for var Request in FRequests do
  begin
    Result := (Result and Request.IsDone);
  end;
end;

class procedure TViewerFuzzRun.HitTest(const PageText: IPdfPageText; const Page: TPdfPageInfo);
begin
  const Box = Page.CropBox;
  for var Row := 0 to HitRows - 1 do
  begin
    for var Column := 0 to HitColumns - 1 do
    begin
      const Point = TPointF.Create(Box.LowerLeftX + (Column + 0.5) * Box.Width / HitColumns,
                                   Box.LowerLeftY + (Row + 0.5) * Box.Height / HitRows);
      var Segment: TPdfTextFragment;
      var WordIndex: Integer;
      var Link: TPdfLink;
      PageText.TryFindSegmentAt(Point, Segment);
      PageText.TryFindWordAt(Point, WordIndex);
      PageText.TryFindNearestWord(Point, WordIndex);
      PageText.TryFindLinkAt(Point, Link);
    end;
  end;
end;

procedure TViewerFuzzRun.RequestTiles(const PageIndex: Integer);
begin
  const Page = FSession.Pages[PageIndex];
  const Transform = TPdfViewTransform.Create(Page, 0, TileScale, PixelsPerInch);
  const PageSize = Transform.Size;
  const Area = TRect.Create(0, 0, Min(PageSize.cx, MaxViewedPixels), Min(PageSize.cy, MaxViewedPixels));
  const Tiles = TPdfTileGrid.TilesIn(PageSize, Area);
  const Request = FSession.RequestTiles(PageIndex, TileScale, 0, Tiles, TPdfJobPriority.Visible,
    procedure(const Tile: TPoint; const Result: TPdfRenderResult)
    begin
      // A tile that failed is fine
    end);
  FRequests.Add(Request);
end;

procedure TViewerFuzzRun.RequestTextAndHitTest(const PageIndex: Integer);
begin
  const Page = FSession.Pages[PageIndex];
  const Request = FSession.RequestPageText(PageIndex, TPdfJobPriority.Visible,
    procedure(const PageText: IPdfPageText)
    begin
      HitTest(PageText, Page);
    end);
  FRequests.Add(Request);
end;

procedure TViewerFuzzRun.RequestSearch;
begin
  const Request = FSession.Search(SearchQuery, False, nil,
    procedure(const Completed: Boolean)
    begin
      // A search that failed on a page is fine
    end);
  FRequests.Add(Request);
end;

procedure TViewerFuzzRun.ViewPage(const PageIndex: Integer);
begin
  RequestTiles(PageIndex);
  RequestTextAndHitTest(PageIndex);
end;

procedure TViewerFuzzRun.Execute(const Bytes: TBytes; const Password: string);
begin
  Open(Bytes, Password);
  if not FIsOpened then
  begin
    Exit;
  end;

  for var PageIndex := 0 to Min(FSession.PageCount, ViewedPages) - 1 do
  begin
    ViewPage(PageIndex);
  end;
  RequestSearch;

  RunUntil(AreRequestsDone);
end;

{ TViewerFuzzProbe }

class procedure TViewerFuzzProbe.Run(const Bytes: TBytes; const Password: string);
begin
  const Run = TViewerFuzzRun.Create;
  try
    Run.Execute(Bytes, Password);
  finally
    Run.Free;
  end;
end;

end.
