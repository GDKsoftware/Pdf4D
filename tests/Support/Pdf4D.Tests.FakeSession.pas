// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.FakeSession;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  System.SysUtils,
  System.UITypes,
  System.Generics.Collections,
  Pdf4D.Render.Bitmap,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.PageText,
  Pdf4D.Viewer.Session;

type
  {$SCOPEDENUMS ON}
  TFakeRequestKind = (Render, Tiles, PageText, Search);
  {$SCOPEDENUMS OFF}

  // One request that TFakeViewerSession received. It is recorded and nothing happens until the test completes it.
  TFakeRequest = class(TInterfacedObject, IPdfViewerRequest)
  private
    FKind: TFakeRequestKind;
    FPageIndex: Integer;
    FScale: Single;
    FViewRotation: Integer;
    FRegion: TRect;
    FTiles: TArray<TPoint>;
    FPriority: TPdfJobPriority;
    FQuery: string;
    FMatchCase: Boolean;
    FCancelled: Boolean;
    FIsDone: Boolean;
    FOnRender: TPdfRenderDoneEvent;
    FOnTile: TPdfTileDoneEvent;
    FOnPageText: TPdfPageTextDoneEvent;
    FOnHits: TPdfSearchHitsEvent;
    FOnSearchDone: TPdfSearchDoneEvent;

    // As the real request does: a request that is cancelled or done lets go of its callbacks, so that a closure that captured the
    // request is not kept alive by it
    procedure ReleaseCallbacks;

  public
    procedure Cancel;
    function IsDone: Boolean;

    property Kind: TFakeRequestKind read FKind;
    property PageIndex: Integer read FPageIndex;
    property Scale: Single read FScale;
    property ViewRotation: Integer read FViewRotation;
    property Region: TRect read FRegion;
    property Tiles: TArray<TPoint> read FTiles;
    property Priority: TPdfJobPriority read FPriority;
    property Query: string read FQuery;
    property MatchCase: Boolean read FMatchCase;
    property Cancelled: Boolean read FCancelled;
  end;

  // IPdfViewerSession without a worker: the test plays the worker. Callbacks run on the calling thread, in the call that completes a
  // request, and not at all for a request that was cancelled.
  TFakeViewerSession = class(TInterfacedObject, IPdfViewerSession)
  private
    FState: TPdfDocumentState;
    FPages: TArray<TPdfPageInfo>;
    FOutline: TArray<TPdfOutlineEntry>;
    FPermissions: TPdfViewerPermissions;
    // In the order of the calls; the interfaces in FRequestReferences own the requests
    FRequests: TList<TFakeRequest>;
    FRequestReferences: TList<IPdfViewerRequest>;
    FOnOpenDone: TPdfOpenDoneEvent;
    FOpenCount: Integer;
    FLastFileName: string;
    FLastPassword: string;

    procedure CheckOpen;
    procedure CheckPage(const PageIndex: Integer);
    function NewRequest(const Kind: TFakeRequestKind; const PageIndex: Integer; const Priority: TPdfJobPriority): TFakeRequest;
    function RequestAt(const Index: Integer; const Kind: TFakeRequestKind): TFakeRequest;
    class function ColorBitmap(const Width, Height: Integer; const Color: TAlphaColor): TPdfBitmap; static;

  public
    constructor Create;
    destructor Destroy; override;

    procedure Open(const FileName, Password: string; const OnDone: TPdfOpenDoneEvent); overload;
    procedure Open(const Data: TBytes; const Password: string; const OnDone: TPdfOpenDoneEvent); overload;
    procedure Close;
    function State: TPdfDocumentState;
    function Pages: TArray<TPdfPageInfo>;
    function PageCount: Integer;
    function Outline: TArray<TPdfOutlineEntry>;
    function Permissions: TPdfViewerPermissions;
    function RequestRender(const PageIndex: Integer; const Scale: Single; const ViewRotation: Integer; const Region: TRect;
                           const Priority: TPdfJobPriority; const OnDone: TPdfRenderDoneEvent): IPdfViewerRequest;
    function RequestTiles(const PageIndex: Integer; const Scale: Single; const ViewRotation: Integer; const Tiles: TArray<TPoint>;
                          const Priority: TPdfJobPriority; const OnTile: TPdfTileDoneEvent): IPdfViewerRequest;
    function RequestPageText(const PageIndex: Integer; const Priority: TPdfJobPriority;
                             const OnDone: TPdfPageTextDoneEvent): IPdfViewerRequest;
    function Search(const Query: string; const MatchCase: Boolean; const OnHits: TPdfSearchHitsEvent;
                    const OnDone: TPdfSearchDoneEvent): IPdfViewerRequest;

    // Makes the session Open at once, with these pages, outline and permissions, and without an OnDone
    procedure SetOpened(const Pages: TArray<TPdfPageInfo>; const Outline: TArray<TPdfOutlineEntry>; const Permissions: TPdfViewerPermissions);
    // Completes the last Open: the state becomes Open (and the pages are those of SetOpened) or Failed; OnDone is called
    procedure CompleteOpen(const Result: TPdfOpenResult);
    // One callback per tile of the request, each with a bitmap of the size of that tile (edge tiles are smaller) in Color
    procedure CompleteTiles(const Index: Integer; const Color: TAlphaColor);
    // One callback with a bitmap of the size of the region (the page at the scale when the region is empty) in Color
    procedure CompleteRender(const Index: Integer; const Color: TAlphaColor);
    procedure CompletePageText(const Index: Integer; const PageText: IPdfPageText);
    // Fails a render or tiles request: every tile gets the callback with Succeeded = False
    procedure FailRender(const Index: Integer; const Message: string);
    procedure DeliverHits(const Index: Integer; const Hits: TArray<TPdfSearchHit>);
    procedure CompleteSearch(const Index: Integer; const Completed: Boolean);
    // Completes every request that is not done, in Color (page text without words, a search without hits), also the ones that come
    // while it does
    procedure CompleteOutstanding(const Color: TAlphaColor);

    // In the order of the calls; the session keeps them alive
    property Requests: TList<TFakeRequest> read FRequests;
    property OpenCount: Integer read FOpenCount;
    property LastFileName: string read FLastFileName;
    property LastPassword: string read FLastPassword;
  end;

implementation

uses
  Pdf4D.Viewer.Tiles,
  Pdf4D.Viewer.ViewTransform;

{ TFakeRequest }

procedure TFakeRequest.Cancel;
begin
  FCancelled := True;
  FIsDone := True;
  ReleaseCallbacks;
end;

procedure TFakeRequest.ReleaseCallbacks;
begin
  FOnRender := nil;
  FOnTile := nil;
  FOnPageText := nil;
  FOnHits := nil;
  FOnSearchDone := nil;
end;

function TFakeRequest.IsDone: Boolean;
begin
  Result := FIsDone;
end;

{ TFakeViewerSession }

constructor TFakeViewerSession.Create;
begin
  inherited Create;
  FState := TPdfDocumentState.Closed;
  FRequests := TList<TFakeRequest>.Create;
  FRequestReferences := TList<IPdfViewerRequest>.Create;
end;

destructor TFakeViewerSession.Destroy;
begin
  FRequests.Free;
  // Releasing the interfaces frees the requests
  FRequestReferences.Free;
  inherited;
end;

procedure TFakeViewerSession.CheckOpen;
begin
  if FState <> TPdfDocumentState.Open then
  begin
    raise EInvalidOpException.Create('The document is not open');
  end;
end;

procedure TFakeViewerSession.CheckPage(const PageIndex: Integer);
begin
  if (PageIndex < 0) or (PageIndex >= Length(FPages)) then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('Page index %d is outside the %d pages', [PageIndex, Length(FPages)]);
  end;
end;

function TFakeViewerSession.NewRequest(const Kind: TFakeRequestKind; const PageIndex: Integer;
                                       const Priority: TPdfJobPriority): TFakeRequest;
begin
  Result := TFakeRequest.Create;
  Result.FKind := Kind;
  Result.FPageIndex := PageIndex;
  Result.FPriority := Priority;
  FRequests.Add(Result);
  FRequestReferences.Add(Result);
end;

function TFakeViewerSession.RequestAt(const Index: Integer; const Kind: TFakeRequestKind): TFakeRequest;
begin
  Result := FRequests[Index];
  if Result.Kind <> Kind then
  begin
    raise EInvalidOpException.CreateFmt('Request %d is not of the kind that this call completes', [Index]);
  end;
end;

class function TFakeViewerSession.ColorBitmap(const Width, Height: Integer; const Color: TAlphaColor): TPdfBitmap;
begin
  Result := TPdfBitmap.Create(Width, Height);
  try
    const Value = TPdfDeviceColor.Create(TAlphaColorRec(Color).R, TAlphaColorRec(Color).G, TAlphaColorRec(Color).B, TAlphaColorRec(Color).A);
    for var Y := 0 to Height - 1 do
    begin
      for var X := 0 to Width - 1 do
      begin
        Result.SetPixel(X, Y, Value);
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

procedure TFakeViewerSession.Open(const FileName, Password: string; const OnDone: TPdfOpenDoneEvent);
begin
  Inc(FOpenCount);
  FLastFileName := FileName;
  FLastPassword := Password;
  FOnOpenDone := OnDone;
  FState := TPdfDocumentState.Opening;
end;

procedure TFakeViewerSession.Open(const Data: TBytes; const Password: string; const OnDone: TPdfOpenDoneEvent);
begin
  Open('', Password, OnDone);
end;

procedure TFakeViewerSession.Close;
begin
  for var Request in FRequests do
  begin
    Request.Cancel;
  end;

  FOnOpenDone := nil;
  FState := TPdfDocumentState.Closed;
end;

function TFakeViewerSession.State: TPdfDocumentState;
begin
  Result := FState;
end;

function TFakeViewerSession.Pages: TArray<TPdfPageInfo>;
begin
  Result := FPages;
end;

function TFakeViewerSession.PageCount: Integer;
begin
  Result := Length(FPages);
end;

function TFakeViewerSession.Outline: TArray<TPdfOutlineEntry>;
begin
  Result := FOutline;
end;

function TFakeViewerSession.Permissions: TPdfViewerPermissions;
begin
  Result := FPermissions;
end;

function TFakeViewerSession.RequestRender(const PageIndex: Integer; const Scale: Single; const ViewRotation: Integer; const Region: TRect;
                                          const Priority: TPdfJobPriority; const OnDone: TPdfRenderDoneEvent): IPdfViewerRequest;
begin
  CheckOpen;
  CheckPage(PageIndex);

  const Request = NewRequest(TFakeRequestKind.Render, PageIndex, Priority);
  Request.FScale := Scale;
  Request.FViewRotation := ViewRotation;
  Request.FRegion := Region;
  Request.FOnRender := OnDone;
  Result := Request;
end;

function TFakeViewerSession.RequestTiles(const PageIndex: Integer; const Scale: Single; const ViewRotation: Integer;
                                         const Tiles: TArray<TPoint>; const Priority: TPdfJobPriority;
                                         const OnTile: TPdfTileDoneEvent): IPdfViewerRequest;
begin
  CheckOpen;
  CheckPage(PageIndex);

  const Request = NewRequest(TFakeRequestKind.Tiles, PageIndex, Priority);
  Request.FScale := Scale;
  Request.FViewRotation := ViewRotation;
  Request.FTiles := Copy(Tiles);
  Request.FOnTile := OnTile;
  Result := Request;
end;

function TFakeViewerSession.RequestPageText(const PageIndex: Integer; const Priority: TPdfJobPriority;
                                            const OnDone: TPdfPageTextDoneEvent): IPdfViewerRequest;
begin
  CheckOpen;
  CheckPage(PageIndex);

  const Request = NewRequest(TFakeRequestKind.PageText, PageIndex, Priority);
  Request.FOnPageText := OnDone;
  Result := Request;
end;

function TFakeViewerSession.Search(const Query: string; const MatchCase: Boolean; const OnHits: TPdfSearchHitsEvent;
                                   const OnDone: TPdfSearchDoneEvent): IPdfViewerRequest;
begin
  CheckOpen;

  const Request = NewRequest(TFakeRequestKind.Search, 0, TPdfJobPriority.Search);
  Request.FQuery := Query;
  Request.FMatchCase := MatchCase;
  Request.FOnHits := OnHits;
  Request.FOnSearchDone := OnDone;
  Result := Request;
end;

procedure TFakeViewerSession.SetOpened(const Pages: TArray<TPdfPageInfo>; const Outline: TArray<TPdfOutlineEntry>;
                                       const Permissions: TPdfViewerPermissions);
begin
  FPages := Copy(Pages);
  FOutline := Copy(Outline);
  FPermissions := Permissions;
  FState := TPdfDocumentState.Open;
end;

procedure TFakeViewerSession.CompleteOpen(const Result: TPdfOpenResult);
begin
  if Result.Succeeded then
  begin
    FState := TPdfDocumentState.Open;
  end
  else
  begin
    FState := TPdfDocumentState.Failed;
  end;

  const OnDone = FOnOpenDone;
  FOnOpenDone := nil;
  if Assigned(OnDone) then
  begin
    OnDone(Result);
  end;
end;

procedure TFakeViewerSession.CompleteTiles(const Index: Integer; const Color: TAlphaColor);
begin
  const Request = RequestAt(Index, TFakeRequestKind.Tiles);
  if Request.Cancelled or (not Assigned(Request.FOnTile)) then
  begin
    Exit;
  end;

  // A callback may cancel the request, which releases its callbacks
  const OnTile = Request.FOnTile;
  const Transform = TPdfViewTransform.Create(FPages[Request.PageIndex], Request.ViewRotation, Request.Scale, 72);
  for var Tile in Request.Tiles do
  begin
    if Request.Cancelled then
    begin
      Break;
    end;

    const Rect = TPdfTileGrid.TileRect(Transform.Size, Tile.X, Tile.Y);
    const Bitmap = ColorBitmap(Rect.Width, Rect.Height, Color);
    try
      var Result: TPdfRenderResult;
      Result.Succeeded := True;
      Result.Bitmap := Bitmap;
      Result.ErrorMessage := '';
      OnTile(Tile, Result);
    finally
      Bitmap.Free;
    end;
  end;

  Request.FIsDone := True;
  Request.ReleaseCallbacks;
end;

procedure TFakeViewerSession.CompleteRender(const Index: Integer; const Color: TAlphaColor);
begin
  const Request = RequestAt(Index, TFakeRequestKind.Render);
  if Request.Cancelled or (not Assigned(Request.FOnRender)) then
  begin
    Exit;
  end;

  var Size: TSize;
  if Request.Region.IsEmpty then
  begin
    Size := TPdfViewTransform.Create(FPages[Request.PageIndex], Request.ViewRotation, Request.Scale, 72).Size;
  end
  else
  begin
    Size := TSize.Create(Request.Region.Width, Request.Region.Height);
  end;

  const Bitmap = ColorBitmap(Size.cx, Size.cy, Color);
  try
    var Result: TPdfRenderResult;
    Result.Succeeded := True;
    Result.Bitmap := Bitmap;
    Result.ErrorMessage := '';
    const OnRender = Request.FOnRender;
    Request.FIsDone := True;
    Request.ReleaseCallbacks;
    OnRender(Result);
  finally
    Bitmap.Free;
  end;
end;

procedure TFakeViewerSession.CompletePageText(const Index: Integer; const PageText: IPdfPageText);
begin
  const Request = RequestAt(Index, TFakeRequestKind.PageText);
  if Request.Cancelled or (not Assigned(Request.FOnPageText)) then
  begin
    Exit;
  end;

  const OnPageText = Request.FOnPageText;
  Request.FIsDone := True;
  Request.ReleaseCallbacks;
  OnPageText(PageText);
end;

procedure TFakeViewerSession.FailRender(const Index: Integer; const Message: string);
begin
  const Request = FRequests[Index];
  if Request.Cancelled then
  begin
    Exit;
  end;

  var Result: TPdfRenderResult;
  Result.Succeeded := False;
  Result.Bitmap := nil;
  Result.ErrorMessage := Message;

  case Request.Kind of
    TFakeRequestKind.Render:
      begin
        const OnRender = Request.FOnRender;
        Request.FIsDone := True;
        Request.ReleaseCallbacks;
        if Assigned(OnRender) then
        begin
          OnRender(Result);
        end;
      end;
    TFakeRequestKind.Tiles:
      begin
        const OnTile = Request.FOnTile;
        for var Tile in Request.Tiles do
        begin
          if (not Request.Cancelled) and Assigned(OnTile) then
          begin
            OnTile(Tile, Result);
          end;
        end;
        Request.FIsDone := True;
        Request.ReleaseCallbacks;
      end;
  else
    raise EInvalidOpException.CreateFmt('Request %d is not a render or tiles request', [Index]);
  end;
end;

procedure TFakeViewerSession.DeliverHits(const Index: Integer; const Hits: TArray<TPdfSearchHit>);
begin
  const Request = RequestAt(Index, TFakeRequestKind.Search);
  const OnHits = Request.FOnHits;
  if (not Request.Cancelled) and Assigned(OnHits) then
  begin
    OnHits(Hits);
  end;
end;

procedure TFakeViewerSession.CompleteSearch(const Index: Integer; const Completed: Boolean);
begin
  const Request = RequestAt(Index, TFakeRequestKind.Search);
  if Request.Cancelled then
  begin
    Exit;
  end;

  const OnDone = Request.FOnSearchDone;
  Request.FIsDone := True;
  Request.ReleaseCallbacks;
  if Assigned(OnDone) then
  begin
    OnDone(Completed);
  end;
end;

procedure TFakeViewerSession.CompleteOutstanding(const Color: TAlphaColor);
begin
  // What a completed request asks for next is completed as well
  var Index := 0;
  while Index < FRequests.Count do
  begin
    const Request = FRequests[Index];
    if not Request.IsDone then
    begin
      case Request.Kind of
        TFakeRequestKind.Render: CompleteRender(Index, Color);
        TFakeRequestKind.Tiles: CompleteTiles(Index, Color);
        TFakeRequestKind.PageText: CompletePageText(Index, TPdfPageText.Empty(Request.PageIndex));
        TFakeRequestKind.Search: CompleteSearch(Index, True);
      else
        raise EInvalidOpException.CreateFmt('Unsupported request kind: %d', [Ord(Request.Kind)]);
      end;
    end;
    Inc(Index);
  end;
end;

end.
