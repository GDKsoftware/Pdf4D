// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.Session;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.Types,
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.Defines,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Api.Outline.Interfaces,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.CancelToken,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Render.Options,
  Pdf4D.Render.Renderer.Interfaces,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.Dispatcher,
  Pdf4D.Viewer.PageText,
  Pdf4D.Viewer.Worker;

type
  IPdfViewerRequest = interface
    ['{D84E19B2-7C06-4A3F-B5E1-0C9A2F6D4E87}']
    // UI thread; no callback after this call
    procedure Cancel;
    // Delivered, failed or cancelled
    function IsDone: Boolean;
  end;

  TPdfOpenResult = record
    Succeeded: Boolean;
    // When not Succeeded
    ErrorKind: TPdfOpenErrorKind;
    ErrorMessage: string;
  end;

  TPdfRenderResult = record
    Succeeded: Boolean;
    // Opaque, flattened on white; owned by the session and valid during the callback only; nil when not Succeeded
    Bitmap: TPdfBitmap;
    ErrorMessage: string;
  end;

  TPdfOpenDoneEvent = reference to procedure(const Result: TPdfOpenResult);
  TPdfRenderDoneEvent = reference to procedure(const Result: TPdfRenderResult);
  TPdfTileDoneEvent = reference to procedure(const Tile: TPoint; const Result: TPdfRenderResult);
  // A failure gives TPdfPageText.Empty and a log line
  TPdfPageTextDoneEvent = reference to procedure(const PageText: IPdfPageText);
  // Per page that has hits, in page order
  TPdfSearchHitsEvent = reference to procedure(const Hits: TArray<TPdfSearchHit>);
  // False when a page failed; there is no call after the request was cancelled
  TPdfSearchDoneEvent = reference to procedure(const Completed: Boolean);

  // All the work on a document is done by the worker of its session. The callbacks run on the UI thread, through the dispatcher, and never
  // after Cancel of their request or after Close or Destroy of the session. A job that fails reports the failure (a failed result, or
  // False for a search) and logs it; nothing vanishes silently.
  IPdfViewerSession = interface
    ['{3F7A5C92-1E48-4B6D-A0C3-8D2E6B9F1A74}']
    // Open closes a previous document first. OnDone always comes, unless the session is closed or destroyed first.
    procedure Open(const FileName, Password: string; const OnDone: TPdfOpenDoneEvent); overload;
    procedure Open(const Data: TBytes; const Password: string; const OnDone: TPdfOpenDoneEvent); overload;
    // Cancels everything; returns at once; the worker releases the document
    procedure Close;
    function State: TPdfDocumentState;
    function Pages: TArray<TPdfPageInfo>;
    function PageCount: Integer;
    function Outline: TArray<TPdfOutlineEntry>;
    function Permissions: TPdfViewerPermissions;
    // Region: pixels of the whole page at Scale, as TPdfRenderParams.Region
    function RequestRender(const PageIndex: Integer; const Scale: Single; const ViewRotation: Integer; const Region: TRect;
                           const Priority: TPdfJobPriority; const OnDone: TPdfRenderDoneEvent): IPdfViewerRequest;
    // One render of the bounding region of Tiles (split in bands of at most MaxTileBatchPixels), cut into tiles of PdfTileSize
    function RequestTiles(const PageIndex: Integer; const Scale: Single; const ViewRotation: Integer; const Tiles: TArray<TPoint>;
                          const Priority: TPdfJobPriority; const OnTile: TPdfTileDoneEvent): IPdfViewerRequest;
    function RequestPageText(const PageIndex: Integer; const Priority: TPdfJobPriority;
                             const OnDone: TPdfPageTextDoneEvent): IPdfViewerRequest;
    function Search(const Query: string; const MatchCase: Boolean; const OnHits: TPdfSearchHitsEvent;
                    const OnDone: TPdfSearchDoneEvent): IPdfViewerRequest;
  end;

  {$IFDEF PDF4D_TESTS}
  // For tests only, compiled when PDF4D_TESTS is defined: called on the worker thread when the document is loaded (IsRelease = False) and
  // when it is released (IsRelease = True). Set before use, reset to nil afterwards.
  TPdfSessionDocumentHook = reference to procedure(const IsRelease: Boolean; const ThreadId: TThreadID);
  {$ENDIF}

  // ---- What the session is made of. These types are public only because the session holds them; nothing outside this unit uses them. ----

  // Shared by a session and the jobs and results that it started: Close and Destroy switch it off, and nothing that has it off is delivered
  ISessionAlive = interface
    ['{0B4A7E15-9C32-4D68-8F01-5A6D3E2C9B47}']
    function IsAlive: Boolean;
    procedure Kill;
  end;

  TSessionAlive = class(TInterfacedObject, ISessionAlive)
  private
    FAlive: Integer;

  public
    constructor Create;
    // Thread safe
    function IsAlive: Boolean;
    procedure Kill;
  end;

  TRequestCallbacks = record
    OnOpen: TPdfOpenDoneEvent;
    OnRender: TPdfRenderDoneEvent;
    OnTile: TPdfTileDoneEvent;
    OnPageText: TPdfPageTextDoneEvent;
    OnHits: TPdfSearchHitsEvent;
    OnSearchDone: TPdfSearchDoneEvent;
  end;

  // What the jobs and the delivery procedures need of a request. The callbacks are used and released on the UI thread only: a closure
  // that captures a reference must not be freed by the worker.
  IPdfRequestState = interface(IPdfViewerRequest)
    ['{6C1F9D40-2A57-4E83-B7D0-E4A8C5F31B69}']
    // Thread safe
    function IsCancelled: Boolean;
    procedure MarkDone;
    function Callbacks: TRequestCallbacks;
    procedure ReleaseCallbacks;
    // Thread safe; a token that is bound after Cancel is cancelled at once
    procedure BindToken(const Token: TPdfCancelToken);
  end;

  TPdfViewerRequest = class(TInterfacedObject, IPdfViewerRequest, IPdfRequestState)
  private
    FLock: TObject;
    FCancelled: Integer;
    FDone: Integer;
    FToken: TPdfCancelToken;
    // Keeps the token alive after its job is gone
    FTokenReference: IPdfCancelToken;
    FCallbacks: TRequestCallbacks;

  public
    constructor Create;
    destructor Destroy; override;

    procedure Cancel;
    function IsDone: Boolean;
    function IsCancelled: Boolean;
    procedure MarkDone;
    function Callbacks: TRequestCallbacks;
    procedure ReleaseCallbacks;
    procedure BindToken(const Token: TPdfCancelToken);

    property OnOpen: TPdfOpenDoneEvent write FCallbacks.OnOpen;
    property OnRender: TPdfRenderDoneEvent write FCallbacks.OnRender;
    property OnTile: TPdfTileDoneEvent write FCallbacks.OnTile;
    property OnPageText: TPdfPageTextDoneEvent write FCallbacks.OnPageText;
    property OnHits: TPdfSearchHitsEvent write FCallbacks.OnHits;
    property OnSearchDone: TPdfSearchDoneEvent write FCallbacks.OnSearchDone;
  end;

  TDocumentEvent = reference to procedure(const IsRelease: Boolean; const ThreadId: TThreadID);

  // The document, its stream and its renderer. Only the worker thread uses it, and releases it.
  TDocumentSlot = class
  private
    FBackend: IPdfRenderBackend;
    FOnEvent: TDocumentEvent;
    FStream: TBytesStream;
    FDocument: IPdfDocument;
    FRenderer: IPdfRenderer;

  public
    constructor Create(const Backend: IPdfRenderBackend; const OnEvent: TDocumentEvent);
    destructor Destroy; override;

    procedure LoadFile(const FileName: string; const Options: TPdfLoadOptions);
    procedure LoadBytes(const Data: TBytes; const Options: TPdfLoadOptions);
    // Releases the renderer, the document and the stream, in that order; nothing happens when there is no document
    procedure Release;

    property Document: IPdfDocument read FDocument;
    property Renderer: IPdfRenderer read FRenderer;
  end;

  TSessionEnvironment = class
  private
    FSlot: TDocumentSlot;
    FDispatcher: IPdfViewerDispatcher;
    FOnLog: TPdfLogEvent;
    FWorker: TPdfDocumentWorker;

  public
    constructor Create(const Backend: IPdfRenderBackend; const Dispatcher: IPdfViewerDispatcher; const OnLog: TPdfLogEvent;
                       const OnDocumentEvent: TDocumentEvent);
    destructor Destroy; override;

    // From the worker thread; the line reaches OnLog on the UI thread, unless the session is closed by then
    procedure Log(const Alive: ISessionAlive; const Level: TPdfLogLevel; const Message: string);
    function LogCallback(const Alive: ISessionAlive): TPdfLogEvent;

    property Slot: TDocumentSlot read FSlot;
    property Dispatcher: IPdfViewerDispatcher read FDispatcher;
    property Worker: TPdfDocumentWorker read FWorker write FWorker;
  end;

  // What a finished open hands to the session
  TOpenOutcome = record
    Succeeded: Boolean;
    ErrorKind: TPdfOpenErrorKind;
    ErrorMessage: string;
    Pages: TArray<TPdfPageInfo>;
    Outline: TArray<TPdfOutlineEntry>;
    Permissions: TPdfViewerPermissions;
  end;

  TOpenOutcomeProc = reference to procedure(const Outcome: TOpenOutcome);

  // The base of the jobs of a session: it catches what the job raises and reports it, and it delivers results to the UI thread only while
  // the request is alive and the session is not closed.
  TSessionJob = class(TPdfWorkerJob)
  private
    FEnvironment: TSessionEnvironment;
    FAlive: ISessionAlive;
    FRequest: IPdfRequestState;

  protected
    procedure Perform(const Cancel: IPdfCancelToken); virtual; abstract;
    // The job raised Failure (the base class logged it): hand the failure to whoever waits for the result. Runs on the worker thread.
    procedure Fail(const Failure: Exception); virtual; abstract;
    function Describe: string; virtual; abstract;
    // Runs Proc on the UI thread, unless the request was cancelled or the session was closed before this call or before Proc runs
    procedure PostToUi(const Proc: TProc);

    property Environment: TSessionEnvironment read FEnvironment;
    property Alive: ISessionAlive read FAlive;
    property Request: IPdfRequestState read FRequest;

  public
    constructor Create(const Environment: TSessionEnvironment; const Alive: ISessionAlive; const Request: IPdfRequestState;
                       const Priority: TPdfJobPriority);
    procedure Execute(const Cancel: IPdfCancelToken); override;
  end;

  TPdfViewerSession = class(TInterfacedObject, IPdfViewerSession)
  private
    FEnvironment: TSessionEnvironment;
    FWorker: TPdfDocumentWorker;
    FAlive: ISessionAlive;
    FState: TPdfDocumentState;
    FPages: TArray<TPdfPageInfo>;
    FOutline: TArray<TPdfOutlineEntry>;
    FPermissions: TPdfViewerPermissions;
    // The requests that may still deliver; the done ones are removed when a request is added
    FRequests: TList<IPdfRequestState>;

    function NewRequest: TPdfViewerRequest;
    procedure CancelRequests;
    // Everything that belongs to the document that goes: requests, results that are on their way, and what the session shows of it
    procedure DropDocument;
    procedure BeginOpen(const FileName: string; const Data: TBytes; const IsFile: Boolean; const Password: string;
                        const OnDone: TPdfOpenDoneEvent);
    procedure ApplyOutcome(const Request: IPdfRequestState; const Outcome: TOpenOutcome);
    procedure CheckOpen;
    procedure CheckPage(const PageIndex: Integer);
    class procedure CheckView(const Scale: Single; const ViewRotation: Integer); static;

  public
    // The session does all its work for the document on its own worker thread; Dispatcher delivers the results to the UI thread, and OnLog
    // gets the log lines of the document and of failed jobs there.
    constructor Create(const Backend: IPdfRenderBackend; const Dispatcher: IPdfViewerDispatcher; const OnLog: TPdfLogEvent);
    // Cancels everything and waits for the worker, which releases the document on its own thread
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
  end;

  {$IFDEF PDF4D_TESTS}
var
  PdfSessionDocumentHook: TPdfSessionDocumentHook;
  {$ENDIF}

implementation

uses
  System.Math,
  System.SyncObjs,
  System.Generics.Defaults,
  Pdf4D.Api.Document,
  Pdf4D.Api.Page.Interfaces,
  Pdf4D.Api.TextLayout.Interfaces,
  Pdf4D.Common.Quad,
  Pdf4D.Render.Renderer,
  Pdf4D.Viewer.TextMatcher,
  Pdf4D.Viewer.Tiles;

const
  MaxOutlineEntries = 100000;
  MaxOutlineDepth = 64;
  BytesPerPixel = 4;
  ValidRotationStep = 90;
  LastRotation = 270;

type
  IBitmapHolder = interface
    ['{9E2D5B73-4F18-4A06-8C94-D1B7A3E60F52}']
    function Bitmap: TPdfBitmap;
  end;

  // Owns a bitmap that is on its way to the UI thread: the bitmap is freed when the delivery is done or dropped, wherever that happens
  TBitmapHolder = class(TInterfacedObject, IBitmapHolder)
  private
    FBitmap: TPdfBitmap;

  public
    constructor Create(const Bitmap: TPdfBitmap);
    destructor Destroy; override;

    function Bitmap: TPdfBitmap;
  end;

  TOutlineFrame = record
    Items: TArray<IPdfOutlineItem>;
    Next: Integer;
  end;

  TOpenJob = class(TSessionJob)
  private
    FFileName: string;
    FData: TBytes;
    FIsFile: Boolean;
    FPassword: string;
    FApply: TOpenOutcomeProc;

    class function KindOf(const Failure: Exception): TPdfOpenErrorKind; static;
    class function CopyPages(const Document: IPdfDocument): TArray<TPdfPageInfo>; static;
    class function FlattenOutline(const Roots: TArray<IPdfOutlineItem>): TArray<TPdfOutlineEntry>; static;
    class function EntryOf(const Item: IPdfOutlineItem; const Level: Integer): TPdfOutlineEntry; static;

  protected
    procedure Perform(const Cancel: IPdfCancelToken); override;
    procedure Fail(const Failure: Exception); override;
    function Describe: string; override;

  public
    constructor Create(const Environment: TSessionEnvironment; const Alive: ISessionAlive; const Request: IPdfRequestState;
                       const FileName: string; const Data: TBytes; const IsFile: Boolean; const Password: string;
                       const Apply: TOpenOutcomeProc);
  end;

  // Releases the document of the slot, on the worker
  TReleaseJob = class(TSessionJob)
  protected
    procedure Perform(const Cancel: IPdfCancelToken); override;
    procedure Fail(const Failure: Exception); override;
    function Describe: string; override;

  public
    constructor Create(const Environment: TSessionEnvironment; const Alive: ISessionAlive; const Request: IPdfRequestState);
  end;

  TRenderJob = class(TSessionJob)
  private
    FPageIndex: Integer;
    FScale: Single;
    FViewRotation: Integer;
    FRegion: TRect;

    procedure Deliver(const Succeeded: Boolean; const Holder: IBitmapHolder; const Message: string);

  protected
    procedure Perform(const Cancel: IPdfCancelToken); override;
    procedure Fail(const Failure: Exception); override;
    function Describe: string; override;

  public
    constructor Create(const Environment: TSessionEnvironment; const Alive: ISessionAlive; const Request: IPdfRequestState;
                       const Priority: TPdfJobPriority; const PageIndex: Integer; const Scale: Single; const ViewRotation: Integer;
                       const Region: TRect);
  end;

  TTilesJob = class(TSessionJob)
  private
    FPageIndex: Integer;
    FScale: Single;
    FViewRotation: Integer;
    // The tiles in the order that they are rendered: row by row
    FTiles: TArray<TPoint>;
    FIsPosted: TArray<Boolean>;
    FPostedCount: Integer;

    class function Ordered(const Tiles: TArray<TPoint>): TArray<TPoint>; static;
    class function CropBitmap(const Source: TPdfBitmap; const Area: TRect): TPdfBitmap; static;
    class function PixelsOf(const Area: TRect): Int64; static;
    procedure PostTile(const Index: Integer; const Holder: IBitmapHolder; const Message: string);
    // Renders Area once and posts the tiles of Indexes; False when the render was cancelled
    function RenderBand(const Indexes: TArray<Integer>; const Area: TRect; const PageSize: TSize; const Cancel: IPdfCancelToken): Boolean;

  protected
    procedure Perform(const Cancel: IPdfCancelToken); override;
    procedure Fail(const Failure: Exception); override;
    function Describe: string; override;

  public
    constructor Create(const Environment: TSessionEnvironment; const Alive: ISessionAlive; const Request: IPdfRequestState;
                       const Priority: TPdfJobPriority; const PageIndex: Integer; const Scale: Single; const ViewRotation: Integer;
                       const Tiles: TArray<TPoint>);
  end;

  TPageTextJob = class(TSessionJob)
  private
    FPageIndex: Integer;

    procedure Deliver(const PageText: IPdfPageText);

  protected
    procedure Perform(const Cancel: IPdfCancelToken); override;
    procedure Fail(const Failure: Exception); override;
    function Describe: string; override;

  public
    constructor Create(const Environment: TSessionEnvironment; const Alive: ISessionAlive; const Request: IPdfRequestState;
                       const Priority: TPdfJobPriority; const PageIndex: Integer);
  end;

  // Searches one page, then queues the job for the next one: work that the user sees can go in between
  TSearchJob = class(TSessionJob)
  private
    FQuery: string;
    FMatchCase: Boolean;
    FPageIndex: Integer;
    FPageCount: Integer;
    FFailed: Boolean;

    function FindHits: TArray<TPdfSearchHit>;
    procedure PostHits(const Hits: TArray<TPdfSearchHit>);
    procedure PostDone(const Completed: Boolean);

  protected
    procedure Perform(const Cancel: IPdfCancelToken); override;
    procedure Fail(const Failure: Exception); override;
    function Describe: string; override;

  public
    // PageCount = 0 makes a job that only completes the search
    constructor Create(const Environment: TSessionEnvironment; const Alive: ISessionAlive; const Request: IPdfRequestState;
                       const Query: string; const MatchCase: Boolean; const PageIndex, PageCount: Integer; const Failed: Boolean);
  end;

{ TSessionAlive }

constructor TSessionAlive.Create;
begin
  inherited Create;
  FAlive := 1;
end;

function TSessionAlive.IsAlive: Boolean;
begin
  Result := (TInterlocked.CompareExchange(FAlive, 0, 0) = 1);
end;

procedure TSessionAlive.Kill;
begin
  TInterlocked.Exchange(FAlive, 0);
end;

{ TPdfViewerRequest }

constructor TPdfViewerRequest.Create;
begin
  inherited Create;
  FLock := TObject.Create;
end;

destructor TPdfViewerRequest.Destroy;
begin
  FLock.Free;
  inherited;
end;

procedure TPdfViewerRequest.Cancel;
begin
  TInterlocked.Exchange(FCancelled, 1);
  TInterlocked.Exchange(FDone, 1);

  TMonitor.Enter(FLock);
  try
    if Assigned(FToken) then
    begin
      FToken.Cancel;
    end;
  finally
    TMonitor.Exit(FLock);
  end;

  ReleaseCallbacks;
end;

function TPdfViewerRequest.IsDone: Boolean;
begin
  Result := (TInterlocked.CompareExchange(FDone, 0, 0) = 1);
end;

function TPdfViewerRequest.IsCancelled: Boolean;
begin
  Result := (TInterlocked.CompareExchange(FCancelled, 0, 0) = 1);
end;

procedure TPdfViewerRequest.MarkDone;
begin
  TInterlocked.Exchange(FDone, 1);
end;

function TPdfViewerRequest.Callbacks: TRequestCallbacks;
begin
  Result := FCallbacks;
end;

procedure TPdfViewerRequest.ReleaseCallbacks;
begin
  FCallbacks := Default(TRequestCallbacks);
end;

procedure TPdfViewerRequest.BindToken(const Token: TPdfCancelToken);
begin
  TMonitor.Enter(FLock);
  try
    FToken := Token;
    FTokenReference := Token;
    if IsCancelled then
    begin
      Token.Cancel;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

{ TBitmapHolder }

constructor TBitmapHolder.Create(const Bitmap: TPdfBitmap);
begin
  inherited Create;
  FBitmap := Bitmap;
end;

destructor TBitmapHolder.Destroy;
begin
  FBitmap.Free;
  inherited;
end;

function TBitmapHolder.Bitmap: TPdfBitmap;
begin
  Result := FBitmap;
end;

{ TDocumentSlot }

constructor TDocumentSlot.Create(const Backend: IPdfRenderBackend; const OnEvent: TDocumentEvent);
begin
  inherited Create;
  FBackend := Backend;
  FOnEvent := OnEvent;
end;

destructor TDocumentSlot.Destroy;
begin
  // Normally the worker released the document already, on its own thread
  Release;
  inherited;
end;

procedure TDocumentSlot.LoadFile(const FileName: string; const Options: TPdfLoadOptions);
begin
  FDocument := TPdfDocument.Load(FileName, Options);
  FRenderer := TPdfRenderer.Create(FDocument, FBackend);
  FOnEvent(False, TThread.CurrentThread.ThreadID);
end;

procedure TDocumentSlot.LoadBytes(const Data: TBytes; const Options: TPdfLoadOptions);
begin
  // The document reads from the stream for as long as it lives
  FStream := TBytesStream.Create(Data);
  try
    FDocument := TPdfDocument.Load(FStream, Options);
    FRenderer := TPdfRenderer.Create(FDocument, FBackend);
  except
    FDocument := nil;
    FreeAndNil(FStream);
    raise;
  end;
  FOnEvent(False, TThread.CurrentThread.ThreadID);
end;

procedure TDocumentSlot.Release;
begin
  const HasDocument = Assigned(FDocument);
  FRenderer := nil;
  FDocument := nil;
  FreeAndNil(FStream);

  if HasDocument then
  begin
    FOnEvent(True, TThread.CurrentThread.ThreadID);
  end;
end;

{ TSessionEnvironment }

constructor TSessionEnvironment.Create(const Backend: IPdfRenderBackend; const Dispatcher: IPdfViewerDispatcher; const OnLog: TPdfLogEvent;
                                       const OnDocumentEvent: TDocumentEvent);
begin
  inherited Create;
  FSlot := TDocumentSlot.Create(Backend, OnDocumentEvent);
  FDispatcher := Dispatcher;
  FOnLog := OnLog;
end;

destructor TSessionEnvironment.Destroy;
begin
  FSlot.Free;
  inherited;
end;

procedure TSessionEnvironment.Log(const Alive: ISessionAlive; const Level: TPdfLogLevel; const Message: string);
begin
  const OnLog = FOnLog;
  if (not Assigned(OnLog)) or (not Alive.IsAlive) then
  begin
    Exit;
  end;

  FDispatcher.Post(
    procedure
    begin
      if Alive.IsAlive then
      begin
        OnLog(Level, Message);
      end;
    end);
end;

function TSessionEnvironment.LogCallback(const Alive: ISessionAlive): TPdfLogEvent;
begin
  Result :=
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      Log(Alive, Level, Message);
    end;
end;

{ TSessionJob }

constructor TSessionJob.Create(const Environment: TSessionEnvironment; const Alive: ISessionAlive; const Request: IPdfRequestState;
                               const Priority: TPdfJobPriority);
begin
  inherited Create(Priority);
  FEnvironment := Environment;
  FAlive := Alive;
  FRequest := Request;
  Request.BindToken(Cancel);
end;

procedure TSessionJob.PostToUi(const Proc: TProc);
begin
  const State = FRequest;
  const SessionAlive = FAlive;
  const IsDropped = (State.IsCancelled or (not SessionAlive.IsAlive));
  if IsDropped then
  begin
    Exit;
  end;

  FEnvironment.Dispatcher.Post(
    procedure
    begin
      const MustDeliver = ((not State.IsCancelled) and SessionAlive.IsAlive);
      if MustDeliver then
      begin
        Proc();
      end;
    end);
end;

procedure TSessionJob.Execute(const Cancel: IPdfCancelToken);
begin
  try
    Perform(Cancel);
  except
    on Failure: Exception do
    begin
      // The worker swallows what a job raises, so the job tells about it itself
      FEnvironment.Log(FAlive, TPdfLogLevel.Error, Format('%s failed: %s', [Describe, Failure.Message]));
      Fail(Failure);
      if TPdfFailure.IsFatal(Failure) then
      begin
        raise;
      end;
    end;
  end;
end;

{ TOpenJob }

constructor TOpenJob.Create(const Environment: TSessionEnvironment; const Alive: ISessionAlive; const Request: IPdfRequestState;
                            const FileName: string; const Data: TBytes; const IsFile: Boolean; const Password: string;
                            const Apply: TOpenOutcomeProc);
begin
  inherited Create(Environment, Alive, Request, TPdfJobPriority.Open);
  FFileName := FileName;
  FData := Data;
  FIsFile := IsFile;
  FPassword := Password;
  FApply := Apply;
end;

function TOpenJob.Describe: string;
begin
  Result := 'Opening the document';
end;

class function TOpenJob.KindOf(const Failure: Exception): TPdfOpenErrorKind;
begin
  if Failure is EPdfInvalidPasswordException then
  begin
    Result := TPdfOpenErrorKind.InvalidPassword;
  end
  else if Failure is EPdfFileException then
  begin
    Result := TPdfOpenErrorKind.FileError;
  end
  else if Failure is EPdfParseException then
  begin
    Result := TPdfOpenErrorKind.ParseError;
  end
  else if Failure is EPdfLimitExceededException then
  begin
    Result := TPdfOpenErrorKind.LimitExceeded;
  end
  else
  begin
    Result := TPdfOpenErrorKind.Other;
  end;
end;

class function TOpenJob.CopyPages(const Document: IPdfDocument): TArray<TPdfPageInfo>;
begin
  SetLength(Result, Document.PageCount);
  for var Index := 0 to High(Result) do
  begin
    const Page = Document.Page(Index);
    Result[Index].CropBox := Page.CropBox;
    Result[Index].Rotation := Page.Rotation;
    Result[Index].Label_ := Page.Label_;
  end;
end;

class function TOpenJob.EntryOf(const Item: IPdfOutlineItem; const Level: Integer): TPdfOutlineEntry;
begin
  Result.Title := Item.Title;
  Result.Level := Level;
  Result.PageIndex := 0;
  Result.HasPage := Item.TryGetPageIndex(Result.PageIndex);
end;

// Pre-order without recursion: the stack holds the items that are still to come on each level
class function TOpenJob.FlattenOutline(const Roots: TArray<IPdfOutlineItem>): TArray<TPdfOutlineEntry>;
begin
  const Entries = TList<TPdfOutlineEntry>.Create;
  const Frames = TList<TOutlineFrame>.Create;
  try
    var Root: TOutlineFrame;
    Root.Items := Roots;
    Root.Next := 0;
    Frames.Add(Root);

    while (Frames.Count > 0) and (Entries.Count < MaxOutlineEntries) do
    begin
      const Top = Frames.Count - 1;
      var Frame := Frames[Top];
      if Frame.Next >= Length(Frame.Items) then
      begin
        Frames.Delete(Top);
        Continue;
      end;

      const Item = Frame.Items[Frame.Next];
      Inc(Frame.Next);
      Frames[Top] := Frame;
      Entries.Add(EntryOf(Item, Top));

      // The children are one level deeper: levels 0 to MaxOutlineDepth - 1 exist
      if Frames.Count < MaxOutlineDepth then
      begin
        var Child: TOutlineFrame;
        Child.Items := Item.Children;
        Child.Next := 0;
        if Length(Child.Items) > 0 then
        begin
          Frames.Add(Child);
        end;
      end;
    end;

    Result := Entries.ToArray;
  finally
    Frames.Free;
    Entries.Free;
  end;
end;

procedure TOpenJob.Perform(const Cancel: IPdfCancelToken);
begin
  // The previous document goes first, on this thread
  Environment.Slot.Release;

  var Options := TPdfLoadOptions.Default;
  Options.Password := FPassword;
  Options.OnLog := Environment.LogCallback(Alive);
  if FIsFile then
  begin
    Environment.Slot.LoadFile(FFileName, Options);
  end
  else
  begin
    Environment.Slot.LoadBytes(FData, Options);
  end;
  FData := nil;

  if Request.IsCancelled then
  begin
    Environment.Slot.Release;
    Exit;
  end;

  const Document = Environment.Slot.Document;
  var Outcome: TOpenOutcome;
  Outcome.Succeeded := True;
  Outcome.ErrorKind := TPdfOpenErrorKind.Other;
  Outcome.ErrorMessage := '';
  Outcome.Pages := CopyPages(Document);
  Outcome.Outline := FlattenOutline(Document.Outline);
  Outcome.Permissions.CanPrint := Document.Permissions.CanPrint;
  Outcome.Permissions.CanCopy := Document.Permissions.CanExtractContent;

  const Apply = FApply;
  PostToUi(
    procedure
    begin
      Apply(Outcome);
    end);
end;

procedure TOpenJob.Fail(const Failure: Exception);
begin
  Environment.Slot.Release;

  var Outcome: TOpenOutcome;
  Outcome.Succeeded := False;
  Outcome.ErrorKind := KindOf(Failure);
  Outcome.ErrorMessage := Failure.Message;
  Outcome.Pages := nil;
  Outcome.Outline := nil;
  Outcome.Permissions := Default(TPdfViewerPermissions);

  const Apply = FApply;
  PostToUi(
    procedure
    begin
      Apply(Outcome);
    end);
end;

{ TReleaseJob }

constructor TReleaseJob.Create(const Environment: TSessionEnvironment; const Alive: ISessionAlive; const Request: IPdfRequestState);
begin
  inherited Create(Environment, Alive, Request, TPdfJobPriority.Open);
end;

function TReleaseJob.Describe: string;
begin
  Result := 'Releasing the document';
end;

procedure TReleaseJob.Perform(const Cancel: IPdfCancelToken);
begin
  Environment.Slot.Release;
end;

procedure TReleaseJob.Fail(const Failure: Exception);
begin
  // Nobody waits for the release; the base class logged it
end;

{ TRenderJob }

constructor TRenderJob.Create(const Environment: TSessionEnvironment; const Alive: ISessionAlive; const Request: IPdfRequestState;
                              const Priority: TPdfJobPriority; const PageIndex: Integer; const Scale: Single;
                              const ViewRotation: Integer; const Region: TRect);
begin
  inherited Create(Environment, Alive, Request, Priority);
  FPageIndex := PageIndex;
  FScale := Scale;
  FViewRotation := ViewRotation;
  FRegion := Region;
end;

function TRenderJob.Describe: string;
begin
  Result := Format('Rendering page %d', [FPageIndex]);
end;

procedure TRenderJob.Deliver(const Succeeded: Boolean; const Holder: IBitmapHolder; const Message: string);
begin
  const State = Request;
  PostToUi(
    procedure
    begin
      var Outcome: TPdfRenderResult;
      Outcome.Succeeded := Succeeded;
      Outcome.Bitmap := nil;
      if Assigned(Holder) then
      begin
        Outcome.Bitmap := Holder.Bitmap;
      end;
      Outcome.ErrorMessage := Message;

      // A callback may cancel its own request, and with it release the callbacks
      const Callbacks = State.Callbacks;
      State.MarkDone;
      State.ReleaseCallbacks;
      if Assigned(Callbacks.OnRender) then
      begin
        Callbacks.OnRender(Outcome);
      end;
    end);
end;

procedure TRenderJob.Perform(const Cancel: IPdfCancelToken);
begin
  var Params := TPdfRenderParams.Create(FScale);
  Params.ExtraRotation := FViewRotation;
  Params.Region := FRegion;
  Params.Options.Destination := TPdfRenderDestination.View;
  Params.Cancel := Cancel;

  var Bitmap: TPdfBitmap;
  const Status = Environment.Slot.Renderer.RenderToBitmap(FPageIndex, Params, Bitmap);
  if Status = TPdfRenderStatus.Completed then
  begin
    Deliver(True, TBitmapHolder.Create(Bitmap), '');
  end;
end;

procedure TRenderJob.Fail(const Failure: Exception);
begin
  Deliver(False, nil, Failure.Message);
end;

{ TTilesJob }

constructor TTilesJob.Create(const Environment: TSessionEnvironment; const Alive: ISessionAlive; const Request: IPdfRequestState;
                             const Priority: TPdfJobPriority; const PageIndex: Integer; const Scale: Single; const ViewRotation: Integer;
                             const Tiles: TArray<TPoint>);
begin
  inherited Create(Environment, Alive, Request, Priority);
  FPageIndex := PageIndex;
  FScale := Scale;
  FViewRotation := ViewRotation;
  FTiles := Ordered(Tiles);
  SetLength(FIsPosted, Length(FTiles));
end;

function TTilesJob.Describe: string;
begin
  Result := Format('Rendering tiles of page %d', [FPageIndex]);
end;

class function TTilesJob.Ordered(const Tiles: TArray<TPoint>): TArray<TPoint>;
begin
  Result := Copy(Tiles);
  TArray.Sort<TPoint>(Result, TComparer<TPoint>.Construct(
    function(const Left, Right: TPoint): Integer
    begin
      Result := CompareValue(Left.Y, Right.Y);
      if Result = 0 then
      begin
        Result := CompareValue(Left.X, Right.X);
      end;
    end));
end;

class function TTilesJob.PixelsOf(const Area: TRect): Int64;
begin
  Result := Int64(Area.Width) * Area.Height;
end;

class function TTilesJob.CropBitmap(const Source: TPdfBitmap; const Area: TRect): TPdfBitmap;
begin
  Result := TPdfBitmap.Create(Area.Width, Area.Height);
  try
    const RowBytes = Area.Width * BytesPerPixel;
    for var Row := 0 to Area.Height - 1 do
    begin
      const SourceRow = Source.ScanLine(Area.Top + Row) + (Area.Left * BytesPerPixel);
      Move(SourceRow^, Result.ScanLine(Row)^, RowBytes);
    end;
  except
    Result.Free;
    raise;
  end;
end;

procedure TTilesJob.PostTile(const Index: Integer; const Holder: IBitmapHolder; const Message: string);
begin
  FIsPosted[Index] := True;
  Inc(FPostedCount);

  const Tile = FTiles[Index];
  const IsLast = (FPostedCount = Length(FTiles));
  const State = Request;
  PostToUi(
    procedure
    begin
      var Outcome: TPdfRenderResult;
      Outcome.Succeeded := Assigned(Holder);
      Outcome.Bitmap := nil;
      if Assigned(Holder) then
      begin
        Outcome.Bitmap := Holder.Bitmap;
      end;
      Outcome.ErrorMessage := Message;

      const Callbacks = State.Callbacks;
      if IsLast then
      begin
        State.MarkDone;
      end;
      if Assigned(Callbacks.OnTile) then
      begin
        Callbacks.OnTile(Tile, Outcome);
      end;
      if IsLast then
      begin
        State.ReleaseCallbacks;
      end;
    end);
end;

function TTilesJob.RenderBand(const Indexes: TArray<Integer>; const Area: TRect; const PageSize: TSize;
                              const Cancel: IPdfCancelToken): Boolean;
begin
  var Params := TPdfRenderParams.Create(FScale);
  Params.ExtraRotation := FViewRotation;
  Params.Region := Area;
  Params.Options.Destination := TPdfRenderDestination.View;
  Params.Cancel := Cancel;

  var Bitmap: TPdfBitmap;
  Result := (Environment.Slot.Renderer.RenderToBitmap(FPageIndex, Params, Bitmap) = TPdfRenderStatus.Completed);
  if not Result then
  begin
    Exit;
  end;

  try
    for var Index in Indexes do
    begin
      const Tile = FTiles[Index];
      const Rect = TPdfTileGrid.TileRect(PageSize, Tile.X, Tile.Y);
      const Inside = TRect.Create(Rect.Left - Area.Left, Rect.Top - Area.Top, Rect.Right - Area.Left, Rect.Bottom - Area.Top);
      PostTile(Index, TBitmapHolder.Create(CropBitmap(Bitmap, Inside)), '');
    end;
  finally
    Bitmap.Free;
  end;
end;

procedure TTilesJob.Perform(const Cancel: IPdfCancelToken);
begin
  const PageSize = Environment.Slot.Renderer.PageTransform(FPageIndex, FScale, FViewRotation).Size;

  // The tiles go in bands: a band is the bounding region of its tiles, and one render makes it
  var Band: TArray<Integer> := nil;
  var BandArea := TRect.Empty;
  for var Index := 0 to High(FTiles) do
  begin
    if Cancel.IsCancelled then
    begin
      Exit;
    end;

    const Rect = TPdfTileGrid.TileRect(PageSize, FTiles[Index].X, FTiles[Index].Y);
    if Rect.IsEmpty then
    begin
      PostTile(Index, nil, 'The tile lies outside the page');
      Continue;
    end;

    const IsBandFull = (Length(Band) > 0) and (PixelsOf(TRect.Union(BandArea, Rect)) > MaxTileBatchPixels);
    if IsBandFull then
    begin
      if not RenderBand(Band, BandArea, PageSize, Cancel) then
      begin
        Exit;
      end;
      Band := nil;
    end;

    if Length(Band) = 0 then
    begin
      BandArea := Rect;
    end
    else
    begin
      BandArea := TRect.Union(BandArea, Rect);
    end;
    Band := Band + [Index];
  end;

  if Length(Band) > 0 then
  begin
    RenderBand(Band, BandArea, PageSize, Cancel);
  end;
end;

procedure TTilesJob.Fail(const Failure: Exception);
begin
  for var Index := 0 to High(FTiles) do
  begin
    if not FIsPosted[Index] then
    begin
      PostTile(Index, nil, Failure.Message);
    end;
  end;
end;

{ TPageTextJob }

constructor TPageTextJob.Create(const Environment: TSessionEnvironment; const Alive: ISessionAlive; const Request: IPdfRequestState;
                                const Priority: TPdfJobPriority; const PageIndex: Integer);
begin
  inherited Create(Environment, Alive, Request, Priority);
  FPageIndex := PageIndex;
end;

function TPageTextJob.Describe: string;
begin
  Result := Format('Reading the text of page %d', [FPageIndex]);
end;

procedure TPageTextJob.Deliver(const PageText: IPdfPageText);
begin
  const State = Request;
  PostToUi(
    procedure
    begin
      const Callbacks = State.Callbacks;
      State.MarkDone;
      State.ReleaseCallbacks;
      if Assigned(Callbacks.OnPageText) then
      begin
        Callbacks.OnPageText(PageText);
      end;
    end);
end;

procedure TPageTextJob.Perform(const Cancel: IPdfCancelToken);
begin
  const Page = Environment.Slot.Document.Page(FPageIndex);
  Deliver(TPdfPageText.Create(Page.TextLayout, Page.Links));
end;

procedure TPageTextJob.Fail(const Failure: Exception);
begin
  Deliver(TPdfPageText.Empty(FPageIndex));
end;

{ TSearchJob }

constructor TSearchJob.Create(const Environment: TSessionEnvironment; const Alive: ISessionAlive; const Request: IPdfRequestState;
                              const Query: string; const MatchCase: Boolean; const PageIndex, PageCount: Integer; const Failed: Boolean);
begin
  inherited Create(Environment, Alive, Request, TPdfJobPriority.Search);
  FQuery := Query;
  FMatchCase := MatchCase;
  FPageIndex := PageIndex;
  FPageCount := PageCount;
  FFailed := Failed;
end;

function TSearchJob.Describe: string;
begin
  Result := Format('Searching page %d', [FPageIndex]);
end;

function TSearchJob.FindHits: TArray<TPdfSearchHit>;
begin
  Result := nil;

  const Positioned = Environment.Slot.Document.Page(FPageIndex).ExtractTextWithPositions;
  const Text = Positioned.Text;
  const Matches = TPdfTextMatcher.FindAll(Text, FQuery, FMatchCase);
  SetLength(Result, Length(Matches));
  for var Index := 0 to High(Matches) do
  begin
    Result[Index].PageIndex := FPageIndex;
    Result[Index].Text := Copy(Text, Matches[Index].Start, Matches[Index].Length);
    Result[Index].Quads := nil;
    for var Fragment in Positioned.Locate(Matches[Index].Start, Matches[Index].Length) do
    begin
      Result[Index].Quads := Result[Index].Quads + Fragment.Quads;
    end;
  end;
end;

procedure TSearchJob.PostHits(const Hits: TArray<TPdfSearchHit>);
begin
  const State = Request;
  PostToUi(
    procedure
    begin
      const Callbacks = State.Callbacks;
      if Assigned(Callbacks.OnHits) then
      begin
        Callbacks.OnHits(Hits);
      end;
    end);
end;

procedure TSearchJob.PostDone(const Completed: Boolean);
begin
  const State = Request;
  PostToUi(
    procedure
    begin
      const Callbacks = State.Callbacks;
      State.MarkDone;
      State.ReleaseCallbacks;
      if Assigned(Callbacks.OnSearchDone) then
      begin
        Callbacks.OnSearchDone(Completed);
      end;
    end);
end;

procedure TSearchJob.Perform(const Cancel: IPdfCancelToken);
begin
  const IsEnd = (FPageIndex >= FPageCount);
  if IsEnd then
  begin
    PostDone(not FFailed);
    Exit;
  end;

  try
    const Hits = FindHits;
    if Length(Hits) > 0 then
    begin
      PostHits(Hits);
    end;
  except
    on Failure: Exception do
    begin
      if TPdfFailure.IsFatal(Failure) then
      begin
        raise;
      end;

      // The other pages are still searched; the search ends as not completed
      FFailed := True;
      Environment.Log(Alive, TPdfLogLevel.Error, Format('%s failed: %s', [Describe, Failure.Message]));
    end;
  end;

  if Request.IsCancelled then
  begin
    Exit;
  end;

  const IsLastPage = (FPageIndex + 1 >= FPageCount);
  if IsLastPage then
  begin
    PostDone(not FFailed);
  end
  else
  begin
    Environment.Worker.Enqueue(TSearchJob.Create(Environment, Alive, Request, FQuery, FMatchCase, FPageIndex + 1, FPageCount, FFailed));
  end;
end;

procedure TSearchJob.Fail(const Failure: Exception);
begin
  PostDone(False);
end;

{ TPdfViewerSession }

constructor TPdfViewerSession.Create(const Backend: IPdfRenderBackend; const Dispatcher: IPdfViewerDispatcher; const OnLog: TPdfLogEvent);
begin
  if not Assigned(Backend) then
  begin
    raise EArgumentNilException.Create('Backend');
  end;
  if not Assigned(Dispatcher) then
  begin
    raise EArgumentNilException.Create('Dispatcher');
  end;

  inherited Create;
  FState := TPdfDocumentState.Closed;
  FAlive := TSessionAlive.Create;
  FRequests := TList<IPdfRequestState>.Create;
  FEnvironment := TSessionEnvironment.Create(Backend, Dispatcher, OnLog,
    procedure(const IsRelease: Boolean; const ThreadId: TThreadID)
    begin
      {$IFDEF PDF4D_TESTS}
      if Assigned(PdfSessionDocumentHook) then
      begin
        PdfSessionDocumentHook(IsRelease, ThreadId);
      end;
      {$ENDIF}
    end);
  // The worker releases the document when it ends, also when a fatal failure stopped it from running jobs
  const Environment = FEnvironment;
  FWorker := TPdfDocumentWorker.Create(
    procedure
    begin
      Environment.Slot.Release;
    end);
  FEnvironment.Worker := FWorker;
end;

destructor TPdfViewerSession.Destroy;
begin
  FAlive.Kill;
  CancelRequests;
  // Stops the worker, which releases the document on its own thread before it ends
  FWorker.Free;
  FEnvironment.Free;
  FRequests.Free;
  inherited;
end;

function TPdfViewerSession.NewRequest: TPdfViewerRequest;
begin
  for var Index := FRequests.Count - 1 downto 0 do
  begin
    if FRequests[Index].IsDone then
    begin
      FRequests.Delete(Index);
    end;
  end;

  Result := TPdfViewerRequest.Create;
  FRequests.Add(Result);
end;

procedure TPdfViewerSession.CancelRequests;
begin
  // Cancel also releases the callbacks, here on the UI thread
  for var Request in FRequests do
  begin
    Request.Cancel;
  end;
  FRequests.Clear;
end;

procedure TPdfViewerSession.DropDocument;
begin
  CancelRequests;
  // What was posted for the old document finds its session closed
  FAlive.Kill;
  FAlive := TSessionAlive.Create;
  FWorker.CancelAll;

  FPages := nil;
  FOutline := nil;
  FPermissions := Default(TPdfViewerPermissions);
end;

procedure TPdfViewerSession.BeginOpen(const FileName: string; const Data: TBytes; const IsFile: Boolean; const Password: string;
                                      const OnDone: TPdfOpenDoneEvent);
begin
  DropDocument;
  FState := TPdfDocumentState.Opening;

  const Request = NewRequest;
  Request.OnOpen := OnDone;
  const State: IPdfRequestState = Request;
  FWorker.Enqueue(TOpenJob.Create(FEnvironment, FAlive, State, FileName, Data, IsFile, Password,
    procedure(const Outcome: TOpenOutcome)
    begin
      // Runs on the UI thread, and only while the session is not closed
      ApplyOutcome(State, Outcome);
    end));
end;

procedure TPdfViewerSession.ApplyOutcome(const Request: IPdfRequestState; const Outcome: TOpenOutcome);
begin
  if Outcome.Succeeded then
  begin
    FPages := Outcome.Pages;
    FOutline := Outcome.Outline;
    FPermissions := Outcome.Permissions;
    FState := TPdfDocumentState.Open;
  end
  else
  begin
    FState := TPdfDocumentState.Failed;
  end;

  var Result: TPdfOpenResult;
  Result.Succeeded := Outcome.Succeeded;
  Result.ErrorKind := Outcome.ErrorKind;
  Result.ErrorMessage := Outcome.ErrorMessage;

  const Callbacks = Request.Callbacks;
  Request.MarkDone;
  Request.ReleaseCallbacks;
  if Assigned(Callbacks.OnOpen) then
  begin
    Callbacks.OnOpen(Result);
  end;
end;

procedure TPdfViewerSession.Open(const FileName, Password: string; const OnDone: TPdfOpenDoneEvent);
begin
  BeginOpen(FileName, nil, True, Password, OnDone);
end;

procedure TPdfViewerSession.Open(const Data: TBytes; const Password: string; const OnDone: TPdfOpenDoneEvent);
begin
  BeginOpen('', Data, False, Password, OnDone);
end;

procedure TPdfViewerSession.Close;
begin
  DropDocument;
  FState := TPdfDocumentState.Closed;

  // After the cancel of everything: this job must run
  const Request = TPdfViewerRequest.Create;
  const State: IPdfRequestState = Request;
  FWorker.Enqueue(TReleaseJob.Create(FEnvironment, FAlive, State));
end;

function TPdfViewerSession.State: TPdfDocumentState;
begin
  Result := FState;
end;

function TPdfViewerSession.Pages: TArray<TPdfPageInfo>;
begin
  Result := FPages;
end;

function TPdfViewerSession.PageCount: Integer;
begin
  Result := Length(FPages);
end;

function TPdfViewerSession.Outline: TArray<TPdfOutlineEntry>;
begin
  Result := FOutline;
end;

function TPdfViewerSession.Permissions: TPdfViewerPermissions;
begin
  Result := FPermissions;
end;

procedure TPdfViewerSession.CheckOpen;
begin
  if FState <> TPdfDocumentState.Open then
  begin
    raise EInvalidOpException.Create('The document is not open');
  end;
end;

procedure TPdfViewerSession.CheckPage(const PageIndex: Integer);
begin
  const IsOutside = ((PageIndex < 0) or (PageIndex >= Length(FPages)));
  if IsOutside then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('Page index %d is outside the %d pages of the document', [PageIndex, Length(FPages)]);
  end;
end;

class procedure TPdfViewerSession.CheckView(const Scale: Single; const ViewRotation: Integer);
begin
  const IsScaleValid = ((Scale > 0) and (not Scale.IsInfinity));
  if not IsScaleValid then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('Scale %g is not a positive number', [Scale]);
  end;

  const IsRotationValid = ((ViewRotation >= 0) and (ViewRotation <= LastRotation) and (ViewRotation mod ValidRotationStep = 0));
  if not IsRotationValid then
  begin
    raise EArgumentException.CreateFmt('View rotation %d is not 0, 90, 180 or 270', [ViewRotation]);
  end;
end;

function TPdfViewerSession.RequestRender(const PageIndex: Integer; const Scale: Single; const ViewRotation: Integer; const Region: TRect;
                                         const Priority: TPdfJobPriority; const OnDone: TPdfRenderDoneEvent): IPdfViewerRequest;
begin
  CheckOpen;
  CheckPage(PageIndex);
  CheckView(Scale, ViewRotation);

  const Request = NewRequest;
  Request.OnRender := OnDone;
  const State: IPdfRequestState = Request;
  FWorker.Enqueue(TRenderJob.Create(FEnvironment, FAlive, State, Priority, PageIndex, Scale, ViewRotation, Region));
  Result := Request;
end;

function TPdfViewerSession.RequestTiles(const PageIndex: Integer; const Scale: Single; const ViewRotation: Integer;
                                        const Tiles: TArray<TPoint>; const Priority: TPdfJobPriority;
                                        const OnTile: TPdfTileDoneEvent): IPdfViewerRequest;
begin
  CheckOpen;
  CheckPage(PageIndex);
  CheckView(Scale, ViewRotation);

  const Request = NewRequest;
  Result := Request;
  if Length(Tiles) = 0 then
  begin
    // Nothing to render
    Request.MarkDone;
    Exit;
  end;

  Request.OnTile := OnTile;
  const State: IPdfRequestState = Request;
  FWorker.Enqueue(TTilesJob.Create(FEnvironment, FAlive, State, Priority, PageIndex, Scale, ViewRotation, Tiles));
end;

function TPdfViewerSession.RequestPageText(const PageIndex: Integer; const Priority: TPdfJobPriority;
                                           const OnDone: TPdfPageTextDoneEvent): IPdfViewerRequest;
begin
  CheckOpen;
  CheckPage(PageIndex);

  const Request = NewRequest;
  Request.OnPageText := OnDone;
  const State: IPdfRequestState = Request;
  FWorker.Enqueue(TPageTextJob.Create(FEnvironment, FAlive, State, Priority, PageIndex));
  Result := Request;
end;

function TPdfViewerSession.Search(const Query: string; const MatchCase: Boolean; const OnHits: TPdfSearchHitsEvent;
                                  const OnDone: TPdfSearchDoneEvent): IPdfViewerRequest;
begin
  CheckOpen;

  const Request = NewRequest;
  Request.OnHits := OnHits;
  Request.OnSearchDone := OnDone;
  const State: IPdfRequestState = Request;

  // Without a query there is nothing to find: the first job completes the search
  var PagesToSearch := Length(FPages);
  if Query.Trim.IsEmpty then
  begin
    PagesToSearch := 0;
  end;
  FWorker.Enqueue(TSearchJob.Create(FEnvironment, FAlive, State, Query, MatchCase, 0, PagesToSearch, False));
  Result := Request;
end;

end.
