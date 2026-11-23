// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.Document;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.Defines,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.Dispatcher,
  Pdf4D.Viewer.Cache,
  Pdf4D.Viewer.PageText,
  Pdf4D.Viewer.Session,
  Pdf4D.Viewer.Backend,
  Pdf4D.Viewer.Overlay;

type
  TPdfDocumentChangeEvent = procedure(const Change: TPdfDocumentChange) of object;

  TPdf4DCustomDocument = class;

  // What a view holds to follow a document, like a TDataLink: the document tells every registered link what changed. The link is owned
  // by the view; freeing it unregisters it, and a document that is freed first lets go of its links.
  TPdfDocumentLink = class
  private
    FDocument: TPdf4DCustomDocument;
    FOnChange: TPdfDocumentChangeEvent;

    procedure SetDocument(const Value: TPdf4DCustomDocument);
    procedure Notify(const Change: TPdfDocumentChange);

  public
    constructor Create(const OnChange: TPdfDocumentChangeEvent);
    // Unregisters
    destructor Destroy; override;

    // Setting it registers with the new document and unregisters from the old one
    property Document: TPdf4DCustomDocument read FDocument write SetDocument;
  end;

  // The document that the views show, without a framework: it opens, closes and searches, and tells its links what changes. All its
  // methods belong to the UI thread; the work on the document itself is done by the worker of its session.
  TPdf4DCustomDocument = class(TComponent)
  private
    FFileName: string;
    FPassword: string;
    FBackend: TPdf4DRenderBackend;
    FIgnorePermissions: Boolean;
    FPageTextCacheCount: Integer;
    FOnOpened: TNotifyEvent;
    FOnOpenError: TPdfOpenErrorEvent;
    FOnClosed: TNotifyEvent;
    FOnLog: TPdfLogNotifyEvent;
    FRenderBackend: IPdfRenderBackend;
    FDispatcher: IPdfViewerDispatcher;
    FLinks: TList<TPdfDocumentLink>;
    FOverlays: TPdfOverlayList;
    FPageTextCache: TPdfLruCache<Integer, IPdfPageText>;
    FSession: IPdfViewerSession;
    // What FSession was made with: the next Open makes a new session when one of them changed
    FSessionBackend: IPdfRenderBackend;
    FSessionDispatcher: IPdfViewerDispatcher;
    FState: TPdfDocumentState;
    FCurrentPage: Integer;
    // Counts the opens and closes: a notification that finds it changed stops, because a handler closed or reopened the document
    FSerial: Integer;
    FSearchRequest: IPdfViewerRequest;
    FSearching: Boolean;
    FSearchHits: TList<TPdfSearchHit>;
    FCurrentSearchHit: Integer;
    FOpenErrorKind: TPdfOpenErrorKind;

    procedure SetBackend(const Value: TPdf4DRenderBackend);
    procedure SetPageTextCacheCount(const Value: Integer);
    procedure SetCurrentPage(const Value: Integer);
    procedure SetDispatcher(const Value: IPdfViewerDispatcher);

    function ResolveBackend: IPdfRenderBackend;
    // Closes the document that is open and leaves the document Opening on a session that is ready; nil when a handler closed it again
    function BeginOpen: IPdfViewerSession;
    procedure UseSession(const NewBackend: IPdfRenderBackend);
    function OpenDoneEvent: TPdfOpenDoneEvent;
    procedure OpenFinished(const Outcome: TPdfOpenResult);
    procedure HandleOpened;
    procedure HandleOpenFailed(const Outcome: TPdfOpenResult);
    // The worker of the open document stopped after a fatal error; the session has logged it
    procedure HandleSessionFatal(const Message: string);
    procedure Log(const Level: TPdfLogLevel; const Message: string);
    procedure Notify(const Change: TPdfDocumentChange);
    procedure OverlaysChanged;
    procedure CheckOpen;
    function ClampPage(const PageIndex: Integer): Integer;

    procedure StopSearchRequest;
    procedure ForgetSearchResults;
    procedure AddSearchHits(const Hits: TArray<TPdfSearchHit>);
    procedure SearchFinished;
    procedure GoToSearchHit(const Index: Integer);

  protected
    procedure Notification(Component: TComponent; Operation: TOperation); override;

    property FileName: string read FFileName write FFileName;
    property Password: string read FPassword write FPassword;
    property Backend: TPdf4DRenderBackend read FBackend write SetBackend;
    // False: printing and copying follow the permissions of the document
    property IgnorePermissions: Boolean read FIgnorePermissions write FIgnorePermissions;
    property PageTextCacheCount: Integer read FPageTextCacheCount write SetPageTextCacheCount;
    property OnOpened: TNotifyEvent read FOnOpened write FOnOpened;
    property OnOpenError: TPdfOpenErrorEvent read FOnOpenError write FOnOpenError;
    property OnClosed: TNotifyEvent read FOnClosed write FOnClosed;
    // On the UI thread
    property OnLog: TPdfLogNotifyEvent read FOnLog write FOnLog;

  public
    constructor Create(Owner: TComponent); override;
    destructor Destroy; override;

    // Does nothing while the component is being designed. Resolves the backend: RenderBackend, else Backend.CreateBackend, else
    // TPdfViewerDefaults.CreateBackend. A failure of the document itself is not raised: the state becomes Failed, the links get OpenFailed
    // and OnOpenError is called.
    procedure Open; overload;
    // Copies Stream from its position to its end; the stream is not used afterwards
    procedure Open(const Stream: TStream); overload;
    procedure Close;
    function State: TPdfDocumentState;
    // Nil while Closed
    function Session: IPdfViewerSession;
    function PageCount: Integer;
    function Pages: TArray<TPdfPageInfo>;
    function Outline: TArray<TPdfOutlineEntry>;
    // Open and (IgnorePermissions or the document allows printing)
    function CanPrint: Boolean;
    function CanCopy: Boolean;
    // From the cache of page texts
    function TryGetPageText(const PageIndex: Integer; out PageText: IPdfPageText): Boolean;
    // Fills the cache; OnDone may be nil
    function RequestPageText(const PageIndex: Integer; const Priority: TPdfJobPriority; const OnDone: TPdfPageTextDoneEvent): IPdfViewerRequest;
    // Replaces the previous search; an empty Query clears the results. The first hit becomes the current hit and the current page.
    procedure Search(const Query: string; const MatchCase: Boolean);
    // Stops searching and keeps the hits found so far
    procedure CancelSearch;
    function IsSearching: Boolean;
    function SearchHits: TArray<TPdfSearchHit>;
    function TryGetCurrentSearchHit(out Index: Integer; out Hit: TPdfSearchHit): Boolean;
    // Wraps around; sets CurrentPage
    procedure NextSearchHit;
    procedure PriorSearchHit;
    procedure RegisterLink(const Link: TPdfDocumentLink);
    procedure UnregisterLink(const Link: TPdfDocumentLink);
    {$IFDEF PDF4D_TESTS}
    // For tests: shows the document of a session that was made by the test
    procedure OpenWithSession(const Session: IPdfViewerSession);
    {$ENDIF}

    // The 0-based cursor, clamped to the pages; 0 while Closed
    property CurrentPage: Integer read FCurrentPage write SetCurrentPage;
    // Owned; cleared on Close
    property Overlays: TPdfOverlayList read FOverlays;
    // Why the last open failed; valid while the state is Failed, and already so when the links hear OpenFailed
    property OpenErrorKind: TPdfOpenErrorKind read FOpenErrorKind;
    property RenderBackend: IPdfRenderBackend read FRenderBackend write FRenderBackend;
    // A TPdfQueueDispatcher by default; set before Open
    property Dispatcher: IPdfViewerDispatcher read FDispatcher write SetDispatcher;
  end;

implementation

uses
  System.Math,
  Pdf4D.Viewer.ResourceStrings;

{ TPdfDocumentLink }

constructor TPdfDocumentLink.Create(const OnChange: TPdfDocumentChangeEvent);
begin
  inherited Create;
  FOnChange := OnChange;
end;

destructor TPdfDocumentLink.Destroy;
begin
  Document := nil;
  inherited;
end;

procedure TPdfDocumentLink.SetDocument(const Value: TPdf4DCustomDocument);
begin
  if Value = FDocument then
  begin
    Exit;
  end;

  if Assigned(FDocument) then
  begin
    FDocument.UnregisterLink(Self);
  end;

  FDocument := Value;

  if Assigned(FDocument) then
  begin
    FDocument.RegisterLink(Self);
  end;
end;

procedure TPdfDocumentLink.Notify(const Change: TPdfDocumentChange);
begin
  if Assigned(FOnChange) then
  begin
    FOnChange(Change);
  end;
end;

{ TPdf4DCustomDocument }

constructor TPdf4DCustomDocument.Create(Owner: TComponent);
begin
  inherited Create(Owner);
  FLinks := TList<TPdfDocumentLink>.Create;
  FPageTextCacheCount := DefaultPageTextCacheCount;
  FPageTextCache := TPdfLruCache<Integer, IPdfPageText>.Create(FPageTextCacheCount);
  FSearchHits := TList<TPdfSearchHit>.Create;
  FCurrentSearchHit := -1;
  FDispatcher := TPdfQueueDispatcher.Create;
  FState := TPdfDocumentState.Closed;
  FOverlays := TPdfOverlayList.Create(
    function: Boolean
    begin
      Result := (FState = TPdfDocumentState.Open);
    end,
    function: Integer
    begin
      Result := PageCount;
    end,
    OverlaysChanged);
end;

destructor TPdf4DCustomDocument.Destroy;
begin
  // Nobody is told anything by a document that is being freed, except the views that must let go of it
  FOnOpened := nil;
  FOnOpenError := nil;
  FOnClosed := nil;
  FOnLog := nil;
  Close;

  for var Link in FLinks do
  begin
    Link.FDocument := nil;
  end;

  // The session waits for its worker, which must be done before what its callbacks use is freed
  FSession := nil;
  FSessionBackend := nil;
  FSessionDispatcher := nil;
  SetBackend(nil);
  FOverlays.Free;
  FSearchHits.Free;
  FPageTextCache.Free;
  FLinks.Free;
  inherited;
end;

procedure TPdf4DCustomDocument.Notification(Component: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = TOperation.opRemove) and (Component = FBackend) then
  begin
    FBackend := nil;
  end;
end;

procedure TPdf4DCustomDocument.SetBackend(const Value: TPdf4DRenderBackend);
begin
  if Value = FBackend then
  begin
    Exit;
  end;

  if Assigned(FBackend) then
  begin
    FBackend.RemoveFreeNotification(Self);
  end;

  FBackend := Value;

  if Assigned(FBackend) then
  begin
    FBackend.FreeNotification(Self);
  end;
end;

procedure TPdf4DCustomDocument.SetPageTextCacheCount(const Value: Integer);
begin
  FPageTextCache.MaxCost := Value;
  FPageTextCacheCount := Value;
end;

procedure TPdf4DCustomDocument.SetDispatcher(const Value: IPdfViewerDispatcher);
begin
  FDispatcher := Value;
  if not Assigned(FDispatcher) then
  begin
    FDispatcher := TPdfQueueDispatcher.Create;
  end;
end;

procedure TPdf4DCustomDocument.Open;
begin
  // The form designer shows the component only: no session and no worker
  if csDesigning in ComponentState then
  begin
    Exit;
  end;

  const OpenSession = BeginOpen;
  if Assigned(OpenSession) then
  begin
    OpenSession.Open(FFileName, FPassword, OpenDoneEvent());
  end;
end;

procedure TPdf4DCustomDocument.Open(const Stream: TStream);
begin
  if csDesigning in ComponentState then
  begin
    Exit;
  end;

  if not Assigned(Stream) then
  begin
    raise EArgumentNilException.Create(SNoStream);
  end;

  var Data: TBytes;
  SetLength(Data, Stream.Size - Stream.Position);
  if Length(Data) > 0 then
  begin
    Stream.ReadBuffer(Data[0], Length(Data));
  end;

  const OpenSession = BeginOpen;
  if Assigned(OpenSession) then
  begin
    OpenSession.Open(Data, FPassword, OpenDoneEvent());
  end;
end;

function TPdf4DCustomDocument.ResolveBackend: IPdfRenderBackend;
begin
  if Assigned(FRenderBackend) then
  begin
    Result := FRenderBackend;
  end
  else if Assigned(FBackend) then
  begin
    Result := FBackend.CreateBackend;
  end
  else
  begin
    Result := TPdfViewerDefaults.CreateBackend;
  end;
end;

function TPdf4DCustomDocument.BeginOpen: IPdfViewerSession;
begin
  Result := nil;

  // Before anything is closed: a document without a backend stays as it is
  const ResolvedBackend = ResolveBackend;
  Close;
  UseSession(ResolvedBackend);

  FState := TPdfDocumentState.Opening;
  Inc(FSerial);
  const Serial = FSerial;
  Notify(TPdfDocumentChange.Opening);

  if Serial = FSerial then
  begin
    Result := FSession;
  end;
end;

procedure TPdf4DCustomDocument.UseSession(const NewBackend: IPdfRenderBackend);
begin
  const IsCurrent = Assigned(FSession) and (FSessionBackend = NewBackend) and (FSessionDispatcher = FDispatcher);
  if IsCurrent then
  begin
    Exit;
  end;

  // The old session waits for its worker, which has been told to stop by Close
  FSession := nil;
  FSessionBackend := NewBackend;
  FSessionDispatcher := FDispatcher;
  FSession := TPdfViewerSession.Create(NewBackend, FDispatcher,
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      Log(Level, Message);
    end,
    procedure(const Message: string)
    begin
      HandleSessionFatal(Message);
    end);
end;

function TPdf4DCustomDocument.OpenDoneEvent: TPdfOpenDoneEvent;
begin
  Result :=
    procedure(const Outcome: TPdfOpenResult)
    begin
      OpenFinished(Outcome);
    end;
end;

procedure TPdf4DCustomDocument.OpenFinished(const Outcome: TPdfOpenResult);
begin
  if FState <> TPdfDocumentState.Opening then
  begin
    Exit;
  end;

  if Outcome.Succeeded then
  begin
    HandleOpened;
  end
  else
  begin
    HandleOpenFailed(Outcome);
  end;
end;

procedure TPdf4DCustomDocument.HandleOpened;
begin
  FState := TPdfDocumentState.Open;
  FCurrentPage := 0;

  const Serial = FSerial;
  Notify(TPdfDocumentChange.Opened);

  // A handler may have closed the document: then nobody hears that it opened
  if (Serial = FSerial) and Assigned(FOnOpened) then
  begin
    FOnOpened(Self);
  end;
end;

procedure TPdf4DCustomDocument.HandleOpenFailed(const Outcome: TPdfOpenResult);
begin
  FState := TPdfDocumentState.Failed;
  FOpenErrorKind := Outcome.ErrorKind;
  Log(TPdfLogLevel.Error, Outcome.ErrorMessage);

  const Serial = FSerial;
  Notify(TPdfDocumentChange.OpenFailed);

  if (Serial = FSerial) and Assigned(FOnOpenError) then
  begin
    FOnOpenError(Self, Outcome.ErrorKind, Outcome.ErrorMessage);
  end;
end;

procedure TPdf4DCustomDocument.HandleSessionFatal(const Message: string);
begin
  if FState <> TPdfDocumentState.Open then
  begin
    Exit;
  end;

  // The document cannot be used any more: what it showed goes, like on Close. The next Open starts a new worker.
  FState := TPdfDocumentState.Failed;
  StopSearchRequest;
  FPageTextCache.Clear;
  ForgetSearchResults;

  const Serial = FSerial;
  Notify(TPdfDocumentChange.OpenFailed);

  if (Serial = FSerial) and Assigned(FOnOpenError) then
  begin
    FOnOpenError(Self, TPdfOpenErrorKind.Other, Message);
  end;
end;

procedure TPdf4DCustomDocument.Close;
begin
  if FState = TPdfDocumentState.Closed then
  begin
    Exit;
  end;

  Inc(FSerial);
  StopSearchRequest;
  if Assigned(FSession) then
  begin
    FSession.Close;
  end;

  FState := TPdfDocumentState.Closed;
  FCurrentPage := 0;
  FPageTextCache.Clear;
  ForgetSearchResults;
  // The state is Closed, so this tells nobody; the Closed change below does
  FOverlays.Clear;

  Notify(TPdfDocumentChange.Closed);
  if Assigned(FOnClosed) then
  begin
    FOnClosed(Self);
  end;
end;

function TPdf4DCustomDocument.State: TPdfDocumentState;
begin
  Result := FState;
end;

function TPdf4DCustomDocument.Session: IPdfViewerSession;
begin
  Result := nil;
  if FState <> TPdfDocumentState.Closed then
  begin
    Result := FSession;
  end;
end;

function TPdf4DCustomDocument.PageCount: Integer;
begin
  Result := 0;
  if FState = TPdfDocumentState.Open then
  begin
    Result := FSession.PageCount;
  end;
end;

function TPdf4DCustomDocument.Pages: TArray<TPdfPageInfo>;
begin
  Result := nil;
  if FState = TPdfDocumentState.Open then
  begin
    Result := FSession.Pages;
  end;
end;

function TPdf4DCustomDocument.Outline: TArray<TPdfOutlineEntry>;
begin
  Result := nil;
  if FState = TPdfDocumentState.Open then
  begin
    Result := FSession.Outline;
  end;
end;

function TPdf4DCustomDocument.CanPrint: Boolean;
begin
  Result := (FState = TPdfDocumentState.Open) and (FIgnorePermissions or FSession.Permissions.CanPrint);
end;

function TPdf4DCustomDocument.CanCopy: Boolean;
begin
  Result := (FState = TPdfDocumentState.Open) and (FIgnorePermissions or FSession.Permissions.CanCopy);
end;

function TPdf4DCustomDocument.TryGetPageText(const PageIndex: Integer; out PageText: IPdfPageText): Boolean;
begin
  Result := FPageTextCache.TryGet(PageIndex, PageText);
end;

function TPdf4DCustomDocument.RequestPageText(const PageIndex: Integer; const Priority: TPdfJobPriority;
                                              const OnDone: TPdfPageTextDoneEvent): IPdfViewerRequest;
begin
  CheckOpen;

  Result := FSession.RequestPageText(PageIndex, Priority,
    procedure(const PageText: IPdfPageText)
    begin
      FPageTextCache.Add(PageIndex, PageText, 1);
      if Assigned(OnDone) then
      begin
        OnDone(PageText);
      end;
    end);
end;

procedure TPdf4DCustomDocument.Search(const Query: string; const MatchCase: Boolean);
begin
  StopSearchRequest;

  const HadResults = (FSearchHits.Count > 0);
  ForgetSearchResults;
  if HadResults then
  begin
    Notify(TPdfDocumentChange.SearchResults);
  end;

  if Query.IsEmpty then
  begin
    Exit;
  end;

  CheckOpen;
  FSearching := True;
  const Request = FSession.Search(Query, MatchCase,
    procedure(const Hits: TArray<TPdfSearchHit>)
    begin
      AddSearchHits(Hits);
    end,
    procedure(const Completed: Boolean)
    begin
      SearchFinished;
    end);

  // A session that completes at once has finished before this point
  if FSearching then
  begin
    FSearchRequest := Request;
  end;
end;

procedure TPdf4DCustomDocument.CancelSearch;
begin
  if not FSearching then
  begin
    Exit;
  end;

  StopSearchRequest;
  Notify(TPdfDocumentChange.SearchResults);
end;

function TPdf4DCustomDocument.IsSearching: Boolean;
begin
  Result := FSearching;
end;

function TPdf4DCustomDocument.SearchHits: TArray<TPdfSearchHit>;
begin
  Result := FSearchHits.ToArray;
end;

function TPdf4DCustomDocument.TryGetCurrentSearchHit(out Index: Integer; out Hit: TPdfSearchHit): Boolean;
begin
  Result := (FCurrentSearchHit >= 0) and (FCurrentSearchHit < FSearchHits.Count);
  if Result then
  begin
    Index := FCurrentSearchHit;
    Hit := FSearchHits[FCurrentSearchHit];
  end
  else
  begin
    Index := -1;
    Hit := Default(TPdfSearchHit);
  end;
end;

procedure TPdf4DCustomDocument.NextSearchHit;
begin
  if FSearchHits.Count > 0 then
  begin
    GoToSearchHit((FCurrentSearchHit + 1) mod FSearchHits.Count);
  end;
end;

procedure TPdf4DCustomDocument.PriorSearchHit;
begin
  if FSearchHits.Count > 0 then
  begin
    GoToSearchHit((FCurrentSearchHit - 1 + FSearchHits.Count) mod FSearchHits.Count);
  end;
end;

procedure TPdf4DCustomDocument.StopSearchRequest;
begin
  if Assigned(FSearchRequest) then
  begin
    FSearchRequest.Cancel;
  end;
  FSearchRequest := nil;
  FSearching := False;
end;

procedure TPdf4DCustomDocument.ForgetSearchResults;
begin
  FSearchHits.Clear;
  FCurrentSearchHit := -1;
end;

procedure TPdf4DCustomDocument.AddSearchHits(const Hits: TArray<TPdfSearchHit>);
begin
  const IsFirst = (FSearchHits.Count = 0) and (Length(Hits) > 0);
  FSearchHits.AddRange(Hits);

  const Serial = FSerial;
  Notify(TPdfDocumentChange.SearchResults);

  // A handler may have closed the document or started another search, which took the results away
  if IsFirst and (Serial = FSerial) and (FSearchHits.Count > 0) then
  begin
    GoToSearchHit(0);
  end;
end;

procedure TPdf4DCustomDocument.SearchFinished;
begin
  FSearching := False;
  FSearchRequest := nil;
  Notify(TPdfDocumentChange.SearchResults);
end;

procedure TPdf4DCustomDocument.GoToSearchHit(const Index: Integer);
begin
  FCurrentSearchHit := Index;
  const Serial = FSerial;

  SetCurrentPage(FSearchHits[Index].PageIndex);

  if Serial = FSerial then
  begin
    Notify(TPdfDocumentChange.CurrentSearchHit);
  end;
end;

procedure TPdf4DCustomDocument.RegisterLink(const Link: TPdfDocumentLink);
begin
  if not FLinks.Contains(Link) then
  begin
    FLinks.Add(Link);
  end;
  Link.FDocument := Self;
end;

procedure TPdf4DCustomDocument.UnregisterLink(const Link: TPdfDocumentLink);
begin
  FLinks.Remove(Link);
  if Link.FDocument = Self then
  begin
    Link.FDocument := nil;
  end;
end;

{$IFDEF PDF4D_TESTS}
procedure TPdf4DCustomDocument.OpenWithSession(const Session: IPdfViewerSession);
begin
  Close;

  // Made by the test: the next Open makes a session of its own
  FSession := Session;
  FSessionBackend := nil;
  FSessionDispatcher := nil;
  FState := Session.State;
  Inc(FSerial);

  if FState = TPdfDocumentState.Open then
  begin
    HandleOpened;
  end;
end;
{$ENDIF}

procedure TPdf4DCustomDocument.SetCurrentPage(const Value: Integer);
begin
  const Page = ClampPage(Value);
  if Page = FCurrentPage then
  begin
    Exit;
  end;

  FCurrentPage := Page;
  Notify(TPdfDocumentChange.CurrentPage);
end;

function TPdf4DCustomDocument.ClampPage(const PageIndex: Integer): Integer;
begin
  Result := Max(0, Min(PageIndex, PageCount - 1));
end;

procedure TPdf4DCustomDocument.Log(const Level: TPdfLogLevel; const Message: string);
begin
  if Assigned(FOnLog) then
  begin
    FOnLog(Self, Level, Message);
  end;
end;

procedure TPdf4DCustomDocument.Notify(const Change: TPdfDocumentChange);
begin
  const Serial = FSerial;
  const Snapshot = FLinks.ToArray;

  for var Link in Snapshot do
  begin
    // A handler that closed or reopened the document made this change old news; a link that was freed meanwhile gets nothing
    if Serial <> FSerial then
    begin
      Exit;
    end;

    if FLinks.Contains(Link) then
    begin
      Link.Notify(Change);
    end;
  end;
end;

procedure TPdf4DCustomDocument.OverlaysChanged;
begin
  if FState = TPdfDocumentState.Open then
  begin
    Notify(TPdfDocumentChange.Overlays);
  end;
end;

procedure TPdf4DCustomDocument.CheckOpen;
begin
  if FState <> TPdfDocumentState.Open then
  begin
    raise EInvalidOpException.Create(SDocumentNotOpen);
  end;
end;

end.
