// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.Session.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.Types,
  System.SysUtils,
  System.SyncObjs,
  System.Diagnostics,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Common.Defines,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.Dispatcher,
  Pdf4D.Viewer.PageText,
  Pdf4D.Viewer.Session,
  Pdf4D.Tests.ManualDispatcher,
  Pdf4D.Tests.RecordingDevice;

type
  TTileEvent = record
    Tile: TPoint;
    Succeeded: Boolean;
    Width: Integer;
    Height: Integer;
  end;

  [TestFixture]
  TPdfViewerSessionTests = class
  private
    FDispatcher: TManualDispatcher;
    FDispatcherReference: IPdfViewerDispatcher;
    FBackend: TRecordingBackend;
    FBackendReference: IPdfRenderBackend;
    FSession: IPdfViewerSession;
    FLogLines: TStringList;
    FFatalMessages: TStringList;

    procedure CreateSession;
    // Waits, without running anything on the dispatcher, until the worker has posted something
    procedure WaitForPostedResult;
    // Makes every text extraction of the document raise an access violation, until TearDown
    procedure FailTextExtractionFatally;
    // Opens the document and runs the dispatcher until OnDone came
    function OpenData(const Data: TBytes; const Password: string = ''): TPdfOpenResult;
    function OpenFile(const FileName, Password: string): TPdfOpenResult;
    procedure OpenOrFail(const Data: TBytes);
    procedure WaitUntil(const Condition: TFunc<Boolean>; const Description: string);
    // Runs a request of the same priority after the ones in the queue and waits for it: whatever was posted before it has been posted
    procedure WaitForQueueToDrain;
    function RequestAllTiles(const PageIndex: Integer; const Scale: Single; const Events: TList<TTileEvent>): IPdfViewerRequest;
    function LogContains(const Fragment: string): Boolean;
    // Makes every text extraction of the document fail, until TearDown
    procedure FailTextExtraction;

  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestOpenFromBytes;
    [Test]
    procedure TestOpenFromFile;
    [Test]
    procedure TestOpenWrongPassword;
    [Test]
    procedure TestOpenMissingFile;
    [Test]
    procedure TestOpenGarbage;
    [Test]
    procedure TestZeroPagesOpens;
    [Test]
    procedure TestOutlineIsFlattened;
    [Test]
    procedure TestOutlineIsCapped;
    [Test]
    procedure TestPermissionsAreCopied;
    [Test]
    procedure TestRequestTilesRendersOnce;
    [Test]
    procedure TestRequestTilesSplitsHugeBatch;
    [Test]
    procedure TestRequestRenderDeliversTheRegion;
    [Test]
    procedure TestCancelledRequestDeliversNothing;
    [Test]
    procedure TestRenderFailureIsReportedNotRaised;
    [Test]
    procedure TestTilesFailureIsReportedPerTile;
    [Test]
    procedure TestTileOutsideThePageFailsOnlyThatTile;
    [Test]
    procedure TestPageTextAndLinks;
    [Test]
    procedure TestPageTextFailureGivesEmptyTextAndALogLine;
    [Test]
    procedure TestSearchStreamsHitsPerPage;
    [Test]
    procedure TestSearchFailureEndsAsNotCompleted;
    [Test]
    procedure TestSearchCancelDeliversNothing;
    [Test]
    procedure TestSearchWithoutQueryCompletesAtOnce;
    [Test]
    procedure TestOpenTwiceDeliversOnlySecond;
    [Test]
    procedure TestCloseDeliversNothing;
    [Test]
    procedure TestDestroyWithPendingResultsDeliversNothing;
    [Test]
    procedure TestDocumentIsReleasedOnWorker;
    [Test]
    procedure TestRequestWhileClosedRaises;
    [Test]
    procedure TestArgumentsAreChecked;
    [Test]
    procedure TestSessionOpensAgainAfterClose;
    [Test]
    procedure TestFatalFailureGivesEveryRequestItsFailure;
    [Test]
    procedure TestFatalFailureFailsTheSessionAndOpenStartsAgain;
    [Test]
    procedure TestFatalFailureWhileOpeningFailsTheOpen;
    [Test]
    procedure TestCreateWithoutBackendRaises;
    [Test]
    procedure TestCreateWithoutDispatcherRaises;
    [Test]
    procedure TestFailureWhileReleasingAtTheEndIsLogged;
    [Test]
    procedure TestOpenResultInTheQueueDoesNotReopenAClosedSession;
    [Test]
    procedure TestResultInTheQueueIsDroppedByCancel;
    [Test]
    procedure TestResultInTheQueueIsDroppedByClose;
    [Test]
    procedure TestResultInTheQueueIsDroppedByDestroy;
  end;

  [TestFixture]
  TFakeViewerSessionTests = class
  public
    [Test]
    procedure TestRecordsRequestsAndCompletesTiles;
    [Test]
    procedure TestCancelledRequestIsNotCompleted;
    [Test]
    procedure TestFailRenderCallsEveryTile;
  end;

implementation

uses
  System.UITypes,
  Pdf4D.Model.Rectangle,
  Pdf4D.Api.Page.Interfaces,
  Pdf4D.Api.DocumentHandle,
  Pdf4D.Render.Bitmap,
  Pdf4D.Viewer.Tiles,
  Pdf4D.Viewer.ViewTransform,
  Pdf4D.Tests.Corpus,
  Pdf4D.Tests.ViewerDocuments,
  Pdf4D.Tests.FakeSession;

const
  // Upper bound for every wait; a test that reaches it fails with a message
  WaitMs = 20000;
  EncryptedFile = 'generated/encrypted/aes-128-user.pdf';
  GarbageSize = 1024;
  OutlineLimit = 100000;
  OutlineTestItems = 200000;
  OutlineBudgetMs = 5000;
  DestroyBudgetMs = 2000;
  HugeBatchScale = 8;
  HugeBatchTiles = 500;

function CropSize(const Info: TPdfPageInfo): TSize;
begin
  Result := TSize.Create(Round(Info.CropBox.UpperRightX - Info.CropBox.LowerLeftX),
                         Round(Info.CropBox.UpperRightY - Info.CropBox.LowerLeftY));
end;

{ TPdfViewerSessionTests }

procedure TPdfViewerSessionTests.Setup;
begin
  FDispatcher := TManualDispatcher.Create;
  FDispatcherReference := FDispatcher;
  FBackend := TRecordingBackend.Create;
  FBackendReference := FBackend;
  FLogLines := TStringList.Create;
  FFatalMessages := TStringList.Create;
  CreateSession;
end;

procedure TPdfViewerSessionTests.TearDown;
begin
  {$IFDEF PDF4D_TESTS}
  PdfSessionDocumentHook := nil;
  TPdfDocumentHandle.StripperHook := nil;
  {$ENDIF}
  // The session first: it waits for its worker, which may still post
  FSession := nil;
  FFatalMessages.Free;
  FLogLines.Free;
  FBackendReference := nil;
  FDispatcherReference := nil;
end;

procedure TPdfViewerSessionTests.CreateSession;
begin
  FSession := TPdfViewerSession.Create(FBackendReference, FDispatcherReference,
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      // The dispatcher runs this on the test thread
      FLogLines.Add(Message);
    end,
    procedure(const Message: string)
    begin
      FFatalMessages.Add(Message);
    end);
end;

procedure TPdfViewerSessionTests.WaitForPostedResult;
begin
  const Watch = TStopwatch.StartNew;
  while (FDispatcher.PendingCount = 0) and (Watch.ElapsedMilliseconds < WaitMs) do
  begin
    TThread.Sleep(1);
  end;
  Assert.IsTrue(FDispatcher.PendingCount > 0, 'The worker posted nothing');
end;

procedure TPdfViewerSessionTests.FailTextExtractionFatally;
begin
  {$IFDEF PDF4D_TESTS}
  TPdfDocumentHandle.StripperHook :=
    procedure
    begin
      raise EAccessViolation.Create('Injected access violation');
    end;
  {$ENDIF}
end;

procedure TPdfViewerSessionTests.WaitUntil(const Condition: TFunc<Boolean>; const Description: string);
begin
  Assert.IsTrue(FDispatcher.RunUntil(Condition, WaitMs), 'Timed out waiting for ' + Description);
end;

function TPdfViewerSessionTests.OpenData(const Data: TBytes; const Password: string): TPdfOpenResult;
begin
  var Received: TPdfOpenResult;
  var Done := False;
  FSession.Open(Data, Password,
    procedure(const Outcome: TPdfOpenResult)
    begin
      Received := Outcome;
      Done := True;
    end);
  WaitUntil(
    function: Boolean
    begin
      Result := Done;
    end,
    'the document to open');
  Result := Received;
end;

function TPdfViewerSessionTests.OpenFile(const FileName, Password: string): TPdfOpenResult;
begin
  var Received: TPdfOpenResult;
  var Done := False;
  FSession.Open(FileName, Password,
    procedure(const Outcome: TPdfOpenResult)
    begin
      Received := Outcome;
      Done := True;
    end);
  WaitUntil(
    function: Boolean
    begin
      Result := Done;
    end,
    'the file to open');
  Result := Received;
end;

procedure TPdfViewerSessionTests.OpenOrFail(const Data: TBytes);
begin
  const Outcome = OpenData(Data);
  Assert.IsTrue(Outcome.Succeeded, 'Open failed: ' + Outcome.ErrorMessage);
end;

procedure TPdfViewerSessionTests.WaitForQueueToDrain;
begin
  var Done := False;
  FSession.RequestPageText(0, TPdfJobPriority.Visible,
    procedure(const PageText: IPdfPageText)
    begin
      Done := True;
    end);
  WaitUntil(
    function: Boolean
    begin
      Result := Done;
    end,
    'the marker request');
end;

function TPdfViewerSessionTests.RequestAllTiles(const PageIndex: Integer; const Scale: Single;
                                                const Events: TList<TTileEvent>): IPdfViewerRequest;
begin
  const Size = TPdfViewTransform.Create(FSession.Pages[PageIndex], 0, Scale, 72).Size;
  const Tiles = TPdfTileGrid.TilesIn(Size, TRect.Create(0, 0, Size.cx, Size.cy));
  Result := FSession.RequestTiles(PageIndex, Scale, 0, Tiles, TPdfJobPriority.Visible,
    procedure(const Tile: TPoint; const Outcome: TPdfRenderResult)
    begin
      var Event: TTileEvent;
      Event.Tile := Tile;
      Event.Succeeded := Outcome.Succeeded;
      Event.Width := 0;
      Event.Height := 0;
      if Assigned(Outcome.Bitmap) then
      begin
        Event.Width := Outcome.Bitmap.Width;
        Event.Height := Outcome.Bitmap.Height;
      end;
      Events.Add(Event);
    end);
end;

procedure TPdfViewerSessionTests.FailTextExtraction;
begin
  {$IFDEF PDF4D_TESTS}
  TPdfDocumentHandle.StripperHook :=
    procedure
    begin
      raise EPdfParseException.Create('Injected text failure');
    end;
  {$ENDIF}
end;

function TPdfViewerSessionTests.LogContains(const Fragment: string): Boolean;
begin
  Result := False;
  for var Line in FLogLines do
  begin
    Result := (Result or Line.Contains(Fragment));
  end;
end;

procedure TPdfViewerSessionTests.TestOpenFromBytes;
begin
  Assert.AreEqual(Ord(TPdfDocumentState.Closed), Ord(FSession.State));

  const Outcome = OpenData(TViewerDocuments.Invoice);

  Assert.IsTrue(Outcome.Succeeded, Outcome.ErrorMessage);
  Assert.AreEqual(2, FSession.PageCount);
  Assert.AreEqual(2, Integer(Length(FSession.Pages)));
  Assert.AreEqual(Ord(TPdfDocumentState.Open), Ord(FSession.State));
  const Size = CropSize(FSession.Pages[0]);
  Assert.AreEqual(612, Size.cx);
  Assert.AreEqual(792, Size.cy);
  Assert.AreEqual(0, FSession.Pages[0].Rotation);
end;

procedure TPdfViewerSessionTests.TestOpenFromFile;
begin
  const Outcome = OpenFile(TCorpus.PdfPath(EncryptedFile), TCorpus.PasswordFor(EncryptedFile));

  Assert.IsTrue(Outcome.Succeeded, Outcome.ErrorMessage);
  Assert.IsTrue(FSession.PageCount > 0);
end;

procedure TPdfViewerSessionTests.TestOpenWrongPassword;
begin
  const Path = TCorpus.PdfPath(EncryptedFile);

  const Wrong = OpenFile(Path, 'not the password');

  Assert.IsFalse(Wrong.Succeeded);
  Assert.AreEqual(Ord(TPdfOpenErrorKind.InvalidPassword), Ord(Wrong.ErrorKind));
  Assert.IsFalse(Wrong.ErrorMessage.IsEmpty);
  Assert.AreEqual(Ord(TPdfDocumentState.Failed), Ord(FSession.State));
  Assert.AreEqual(0, FSession.PageCount);

  const Right = OpenFile(Path, TCorpus.PasswordFor(EncryptedFile));

  Assert.IsTrue(Right.Succeeded, Right.ErrorMessage);
  Assert.AreEqual(Ord(TPdfDocumentState.Open), Ord(FSession.State));
end;

procedure TPdfViewerSessionTests.TestOpenMissingFile;
begin
  const Outcome = OpenFile(TCorpus.PdfPath('no-such-folder/no-such-file.pdf'), '');

  Assert.IsFalse(Outcome.Succeeded);
  Assert.AreEqual(Ord(TPdfOpenErrorKind.FileError), Ord(Outcome.ErrorKind));
  Assert.AreEqual(Ord(TPdfDocumentState.Failed), Ord(FSession.State));
end;

procedure TPdfViewerSessionTests.TestOpenGarbage;
begin
  var Data: TBytes;
  SetLength(Data, GarbageSize);
  // A fixed sequence that is no PDF file
  for var Index := 0 to GarbageSize - 1 do
  begin
    Data[Index] := Byte((Index * 131 + 17) mod 251);
  end;

  const Outcome = OpenData(Data);

  Assert.IsFalse(Outcome.Succeeded);
  Assert.AreEqual(Ord(TPdfOpenErrorKind.ParseError), Ord(Outcome.ErrorKind));
  Assert.AreEqual(Ord(TPdfDocumentState.Failed), Ord(FSession.State));
end;

procedure TPdfViewerSessionTests.TestZeroPagesOpens;
begin
  const Outcome = OpenData(TViewerDocuments.ZeroPages);

  Assert.IsTrue(Outcome.Succeeded, Outcome.ErrorMessage);
  Assert.AreEqual(0, FSession.PageCount);
  Assert.AreEqual(Ord(TPdfDocumentState.Open), Ord(FSession.State));
end;

procedure TPdfViewerSessionTests.TestOutlineIsFlattened;
begin
  OpenOrFail(TViewerDocuments.Outlined);

  const Outline = FSession.Outline;

  Assert.AreEqual(3, Integer(Length(Outline)));
  Assert.AreEqual('Chapter 1', Outline[0].Title);
  Assert.AreEqual(0, Outline[0].Level);
  Assert.IsTrue(Outline[0].HasPage);
  Assert.AreEqual(0, Outline[0].PageIndex);
  Assert.AreEqual('Section 1.1', Outline[1].Title);
  Assert.AreEqual(1, Outline[1].Level);
  Assert.AreEqual(1, Outline[1].PageIndex);
  Assert.AreEqual('Chapter 2', Outline[2].Title);
  Assert.AreEqual(0, Outline[2].Level);
  Assert.AreEqual(1, Outline[2].PageIndex);
end;

procedure TPdfViewerSessionTests.TestOutlineIsCapped;
begin
  const Data = TViewerDocuments.LargeOutline(OutlineTestItems);

  const Watch = TStopwatch.StartNew;
  const Outcome = OpenData(Data);
  Watch.Stop;

  Assert.IsTrue(Outcome.Succeeded, Outcome.ErrorMessage);
  Assert.AreEqual(OutlineLimit, Integer(Length(FSession.Outline)));
  Assert.IsTrue(Watch.ElapsedMilliseconds < OutlineBudgetMs, Format('Open took %d ms', [Watch.ElapsedMilliseconds]));
end;

procedure TPdfViewerSessionTests.TestPermissionsAreCopied;
begin
  OpenOrFail(TViewerDocuments.Invoice);

  Assert.IsTrue(FSession.Permissions.CanPrint);
  Assert.IsTrue(FSession.Permissions.CanCopy);
end;

procedure TPdfViewerSessionTests.TestRequestTilesRendersOnce;
begin
  OpenOrFail(TViewerDocuments.Invoice);
  const Events = TList<TTileEvent>.Create;
  try
    const Request = RequestAllTiles(0, 1, Events);

    WaitUntil(
      function: Boolean
      begin
        Result := Request.IsDone;
      end,
      'the tiles');

    Assert.AreEqual(12, Integer(Events.Count));
    Assert.AreEqual(1, FBackend.DeviceCount);
    const Size = TPdfViewTransform.Create(FSession.Pages[0], 0, 1, 72).Size;
    for var Event in Events do
    begin
      Assert.IsTrue(Event.Succeeded);
      const Rect = TPdfTileGrid.TileRect(Size, Event.Tile.X, Event.Tile.Y);
      Assert.AreEqual(Rect.Width, Event.Width);
      Assert.AreEqual(Rect.Height, Event.Height);
    end;
    // An edge tile is smaller than the others
    Assert.AreEqual(PdfTileSize, Events[0].Width);
    Assert.IsTrue(Events[Events.Count - 1].Width < PdfTileSize);
  finally
    Events.Free;
  end;
end;

procedure TPdfViewerSessionTests.TestRequestTilesSplitsHugeBatch;
begin
  OpenOrFail(TViewerDocuments.Invoice);
  const Events = TList<TTileEvent>.Create;
  try
    const Request = RequestAllTiles(0, HugeBatchScale, Events);

    WaitUntil(
      function: Boolean
      begin
        Result := Request.IsDone;
      end,
      'the tiles of the huge page');

    Assert.AreEqual(HugeBatchTiles, Integer(Events.Count));
    Assert.IsTrue(FBackend.DeviceCount > 1, 'The batch was not split');
    Assert.IsTrue(FBackend.LargestPixels <= MaxTileBatchPixels, 'A render was larger than the limit');
    for var Event in Events do
    begin
      Assert.IsTrue(Event.Succeeded);
    end;
  finally
    Events.Free;
  end;
end;

procedure TPdfViewerSessionTests.TestRequestRenderDeliversTheRegion;
begin
  OpenOrFail(TViewerDocuments.Invoice);
  var Width := 0;
  var Height := 0;
  var Done := False;

  const Request = FSession.RequestRender(0, 1, 0, TRect.Create(100, 200, 300, 260), TPdfJobPriority.Visible,
    procedure(const Outcome: TPdfRenderResult)
    begin
      if Outcome.Succeeded then
      begin
        Width := Outcome.Bitmap.Width;
        Height := Outcome.Bitmap.Height;
      end;
      Done := True;
    end);
  WaitUntil(
    function: Boolean
    begin
      Result := Done;
    end,
    'the render');

  Assert.AreEqual(200, Width);
  Assert.AreEqual(60, Height);
  Assert.IsTrue(Request.IsDone);
end;

procedure TPdfViewerSessionTests.TestCancelledRequestDeliversNothing;
begin
  OpenOrFail(TViewerDocuments.Invoice);
  const Events = TList<TTileEvent>.Create;
  try
    const Request = RequestAllTiles(0, 1, Events);
    Request.Cancel;
    Assert.IsTrue(Request.IsDone);

    // The marker comes after the cancelled request in the queue, so what the worker posted for it has been posted by now
    WaitForQueueToDrain;
    FDispatcher.RunPending;

    Assert.AreEqual(0, Integer(Events.Count));
  finally
    Events.Free;
  end;
end;

procedure TPdfViewerSessionTests.TestRenderFailureIsReportedNotRaised;
begin
  OpenOrFail(TViewerDocuments.Invoice);
  FBackend.CreateFailure := 'The backend failed';
  var Received: TPdfRenderResult;
  var Done := False;

  FSession.RequestRender(0, 1, 0, TRect.Empty, TPdfJobPriority.Visible,
    procedure(const Outcome: TPdfRenderResult)
    begin
      Received := Outcome;
      Done := True;
    end);
  WaitUntil(
    function: Boolean
    begin
      Result := Done;
    end,
    'the failed render');

  Assert.IsFalse(Received.Succeeded);
  Assert.IsFalse(Assigned(Received.Bitmap));
  Assert.IsTrue(Received.ErrorMessage.Contains('The backend failed'), Received.ErrorMessage);
  Assert.IsTrue(LogContains('failed'), 'The failure was not logged');
  // The session is still usable
  Assert.AreEqual(Ord(TPdfDocumentState.Open), Ord(FSession.State));
  FBackend.CreateFailure := '';
  Done := False;
  FSession.RequestRender(0, 1, 0, TRect.Empty, TPdfJobPriority.Visible,
    procedure(const Outcome: TPdfRenderResult)
    begin
      Received := Outcome;
      Done := True;
    end);
  WaitUntil(
    function: Boolean
    begin
      Result := Done;
    end,
    'the render after a failed render');
  Assert.IsTrue(Received.Succeeded, Received.ErrorMessage);
end;

procedure TPdfViewerSessionTests.TestTilesFailureIsReportedPerTile;
begin
  OpenOrFail(TViewerDocuments.Invoice);
  FBackend.CreateFailure := 'The backend failed';
  const Events = TList<TTileEvent>.Create;
  try
    const Request = RequestAllTiles(0, 1, Events);

    WaitUntil(
      function: Boolean
      begin
        Result := Request.IsDone;
      end,
      'the failed tiles');

    Assert.AreEqual(12, Integer(Events.Count));
    for var Event in Events do
    begin
      Assert.IsFalse(Event.Succeeded);
    end;
    Assert.IsTrue(LogContains('failed'), 'The failure was not logged');
  finally
    Events.Free;
  end;
end;

procedure TPdfViewerSessionTests.TestTileOutsideThePageFailsOnlyThatTile;
begin
  OpenOrFail(TViewerDocuments.Invoice);
  const Events = TList<TTileEvent>.Create;
  try
    const Request = FSession.RequestTiles(0, 1, 0, [TPoint.Create(0, 0), TPoint.Create(50, 50)], TPdfJobPriority.Visible,
      procedure(const Tile: TPoint; const Outcome: TPdfRenderResult)
      begin
        var Event: TTileEvent;
        Event.Tile := Tile;
        Event.Succeeded := Outcome.Succeeded;
        Event.Width := 0;
        Event.Height := 0;
        Events.Add(Event);
      end);

    WaitUntil(
      function: Boolean
      begin
        Result := Request.IsDone;
      end,
      'the tiles');

    Assert.AreEqual(2, Integer(Events.Count));
    var Failed := 0;
    for var Event in Events do
    begin
      if not Event.Succeeded then
      begin
        Inc(Failed);
        Assert.AreEqual(50, Event.Tile.X);
      end;
    end;
    Assert.AreEqual(1, Failed);
  finally
    Events.Free;
  end;
end;

procedure TPdfViewerSessionTests.TestPageTextAndLinks;
begin
  OpenOrFail(TViewerDocuments.Invoice);
  var Text: IPdfPageText := nil;

  FSession.RequestPageText(0, TPdfJobPriority.PageText,
    procedure(const PageText: IPdfPageText)
    begin
      Text := PageText;
    end);
  WaitUntil(
    function: Boolean
    begin
      Result := Assigned(Text);
    end,
    'the page text');

  Assert.AreEqual(0, Text.PageIndex);
  Assert.IsFalse(Text.IsEmpty);
  Assert.AreEqual(4, Integer(Length(Text.Words)));
  Assert.AreEqual('Factuur', Text.Words[0].Text);
  Assert.AreEqual('2024-0815', Text.Words[1].Text);
  Assert.AreEqual(2, Integer(Length(Text.Links)));
  Assert.AreEqual(Ord(TPdfLinkKind.GoTo), Ord(Text.Links[0].Kind));
  Assert.AreEqual(1, Text.Links[0].TargetPageIndex);
  Assert.AreEqual(Ord(TPdfLinkKind.Uri), Ord(Text.Links[1].Kind));
  Assert.AreEqual('https://example.com/', Text.Links[1].Uri);
end;

procedure TPdfViewerSessionTests.TestPageTextFailureGivesEmptyTextAndALogLine;
begin
  OpenOrFail(TViewerDocuments.Invoice);
  var Text: IPdfPageText := nil;
  FailTextExtraction;

  FSession.RequestPageText(1, TPdfJobPriority.PageText,
    procedure(const PageText: IPdfPageText)
    begin
      Text := PageText;
    end);
  WaitUntil(
    function: Boolean
    begin
      Result := Assigned(Text);
    end,
    'the page text after a failure');

  Assert.IsTrue(Text.IsEmpty);
  Assert.AreEqual(1, Text.PageIndex);
  Assert.IsTrue(LogContains('Injected text failure'), 'The failure was not logged');
end;

procedure TPdfViewerSessionTests.TestSearchStreamsHitsPerPage;
begin
  OpenOrFail(TViewerDocuments.Invoice);
  const Events = TStringList.Create;
  try
    var Hits: TArray<TPdfSearchHit>;
    var Done := False;
    FSession.Search('2024-0815', False,
      procedure(const PageHits: TArray<TPdfSearchHit>)
      begin
        Events.Add(Format('hits:%d:%d', [PageHits[0].PageIndex, Length(PageHits)]));
        Hits := PageHits;
      end,
      procedure(const Completed: Boolean)
      begin
        Events.Add('done:' + BoolToStr(Completed, True));
        Done := True;
      end);
    WaitUntil(
      function: Boolean
      begin
        Result := Done;
      end,
      'the search');

    Assert.AreEqual('hits:0:2,done:True', Events.CommaText);
    Assert.AreEqual('2024-0815', Hits[0].Text);
    Assert.AreEqual(1, Integer(Length(Hits[0].Quads)));
    Assert.AreEqual(0, Hits[0].PageIndex);

    Events.Clear;
    Done := False;
    FSession.Search(Char($20AC) + ' 12', False,
      procedure(const PageHits: TArray<TPdfSearchHit>)
      begin
        Events.Add(Format('hits:%d:%d', [PageHits[0].PageIndex, Length(PageHits)]));
      end,
      procedure(const Completed: Boolean)
      begin
        Events.Add('done:' + BoolToStr(Completed, True));
        Done := True;
      end);
    WaitUntil(
      function: Boolean
      begin
        Result := Done;
      end,
      'the second search');

    Assert.AreEqual('hits:1:1,done:True', Events.CommaText);
  finally
    Events.Free;
  end;
end;

procedure TPdfViewerSessionTests.TestSearchFailureEndsAsNotCompleted;
begin
  OpenOrFail(TViewerDocuments.Invoice);
  FailTextExtraction;
  var Hits := 0;
  var Completed := True;
  var Done := False;

  FSession.Search('Factuur', False,
    procedure(const PageHits: TArray<TPdfSearchHit>)
    begin
      Inc(Hits);
    end,
    procedure(const Outcome: Boolean)
    begin
      Completed := Outcome;
      Done := True;
    end);
  WaitUntil(
    function: Boolean
    begin
      Result := Done;
    end,
    'the failed search');

  Assert.AreEqual(0, Hits);
  Assert.IsFalse(Completed);
  Assert.IsTrue(LogContains('Injected text failure'), 'The failure was not logged');
end;

procedure TPdfViewerSessionTests.TestSearchCancelDeliversNothing;
begin
  OpenOrFail(TViewerDocuments.Pages(20, 612, 792, 0));
  var Calls := 0;

  const Request = FSession.Search('Page', False,
    procedure(const PageHits: TArray<TPdfSearchHit>)
    begin
      Inc(Calls);
    end,
    procedure(const Completed: Boolean)
    begin
      Inc(Calls);
    end);
  Request.Cancel;

  WaitForQueueToDrain;
  FDispatcher.RunPending;

  Assert.AreEqual(0, Calls);
  Assert.IsTrue(Request.IsDone);
end;

procedure TPdfViewerSessionTests.TestSearchWithoutQueryCompletesAtOnce;
begin
  OpenOrFail(TViewerDocuments.Invoice);
  var Hits := 0;
  var Completed := False;
  var Done := False;

  FSession.Search('   ', False,
    procedure(const PageHits: TArray<TPdfSearchHit>)
    begin
      Inc(Hits);
    end,
    procedure(const Outcome: Boolean)
    begin
      Completed := Outcome;
      Done := True;
    end);
  WaitUntil(
    function: Boolean
    begin
      Result := Done;
    end,
    'the empty search');

  Assert.AreEqual(0, Hits);
  Assert.IsTrue(Completed);
end;

procedure TPdfViewerSessionTests.TestOpenTwiceDeliversOnlySecond;
begin
  var FirstCalls := 0;
  var SecondCalls := 0;
  const FirstDocument = TViewerDocuments.Invoice;
  const SecondDocument = TViewerDocuments.Pages(5, 200, 300, 0);
  FSession.Open(FirstDocument, '',
    procedure(const Outcome: TPdfOpenResult)
    begin
      Inc(FirstCalls);
    end);
  FSession.Open(SecondDocument, '',
    procedure(const Outcome: TPdfOpenResult)
    begin
      Inc(SecondCalls);
    end);

  WaitUntil(
    function: Boolean
    begin
      Result := (SecondCalls > 0);
    end,
    'the second open');
  FDispatcher.RunPending;

  Assert.AreEqual(0, FirstCalls);
  Assert.AreEqual(1, SecondCalls);
  Assert.AreEqual(5, FSession.PageCount);
end;

procedure TPdfViewerSessionTests.TestCloseDeliversNothing;
begin
  OpenOrFail(TViewerDocuments.Invoice);
  const Events = TList<TTileEvent>.Create;
  try
    RequestAllTiles(0, 1, Events);
    var OpenCalls := 0;
    FSession.Close;
    Assert.AreEqual(Ord(TPdfDocumentState.Closed), Ord(FSession.State));
    Assert.AreEqual(0, FSession.PageCount);

    // A new document, and the queue drained behind everything that the closed one left
    const Document = TViewerDocuments.Invoice;
    FSession.Open(Document, '',
      procedure(const Outcome: TPdfOpenResult)
      begin
        Inc(OpenCalls);
      end);
    WaitUntil(
      function: Boolean
      begin
        Result := (OpenCalls > 0);
      end,
      'the reopened document');
    FDispatcher.RunPending;

    Assert.AreEqual(0, Integer(Events.Count));
  finally
    Events.Free;
  end;
end;

procedure TPdfViewerSessionTests.TestDestroyWithPendingResultsDeliversNothing;
begin
  OpenOrFail(TViewerDocuments.Invoice);
  var Calls := 0;
  const Events = TList<TTileEvent>.Create;
  try
    RequestAllTiles(0, 1, Events);
    FSession.RequestPageText(0, TPdfJobPriority.PageText,
      procedure(const PageText: IPdfPageText)
      begin
        Inc(Calls);
      end);
    FSession.Search('Factuur', False,
      procedure(const PageHits: TArray<TPdfSearchHit>)
      begin
        Inc(Calls);
      end,
      procedure(const Completed: Boolean)
      begin
        Inc(Calls);
      end);
    const Document = TViewerDocuments.Invoice;
    FSession.Open(Document, '',
      procedure(const Outcome: TPdfOpenResult)
      begin
        Inc(Calls);
      end);

    const Watch = TStopwatch.StartNew;
    FSession := nil;
    Watch.Stop;
    FDispatcher.RunPending;

    Assert.AreEqual(0, Calls);
    Assert.AreEqual(0, Integer(Events.Count));
    Assert.IsTrue(Watch.ElapsedMilliseconds < DestroyBudgetMs, Format('Destroy took %d ms', [Watch.ElapsedMilliseconds]));
  finally
    Events.Free;
  end;
end;

procedure TPdfViewerSessionTests.TestFatalFailureGivesEveryRequestItsFailure;
begin
  OpenOrFail(TViewerDocuments.Invoice);
  FailTextExtractionFatally;
  var TextCalls := 0;
  var TextWasEmpty := True;
  var SearchDone := 0;
  var SearchCompleted := True;
  var TileEvents := 0;
  var TileFailed := True;

  // The dispatcher does not run until all are queued, so the session is still open: some are queued behind the fatal one, others come after
  const FirstText = FSession.RequestPageText(0, TPdfJobPriority.Visible,
    procedure(const PageText: IPdfPageText)
    begin
      Inc(TextCalls);
      TextWasEmpty := (TextWasEmpty and PageText.IsEmpty);
    end);
  const SecondText = FSession.RequestPageText(1, TPdfJobPriority.PageText,
    procedure(const PageText: IPdfPageText)
    begin
      Inc(TextCalls);
      TextWasEmpty := (TextWasEmpty and PageText.IsEmpty);
    end);
  const SearchRequest = FSession.Search('Factuur', False, nil,
    procedure(const Completed: Boolean)
    begin
      Inc(SearchDone);
      SearchCompleted := Completed;
    end);
  const Size = TPdfViewTransform.Create(FSession.Pages[0], 0, 1, 72).Size;
  const Tiles = TPdfTileGrid.TilesIn(Size, TRect.Create(0, 0, Size.cx, Size.cy));
  const TilesRequest = FSession.RequestTiles(0, 1, 0, Tiles, TPdfJobPriority.Prefetch,
    procedure(const Tile: TPoint; const Outcome: TPdfRenderResult)
    begin
      Inc(TileEvents);
      TileFailed := (TileFailed and (not Outcome.Succeeded));
    end);

  WaitUntil(
    function: Boolean
    begin
      Result := (TextCalls = 2) and (SearchDone = 1) and (TileEvents > 0);
    end,
    'the failures of the abandoned requests');
  // Whatever is still queued runs now: nothing may arrive twice
  FDispatcher.RunPending;

  Assert.AreEqual(2, TextCalls);
  Assert.AreEqual(1, SearchDone);
  Assert.AreEqual(Integer(Length(Tiles)), TileEvents);
  Assert.IsTrue(TextWasEmpty);
  Assert.IsFalse(SearchCompleted);
  Assert.IsTrue(TileFailed);
  Assert.IsTrue(FirstText.IsDone);
  Assert.IsTrue(SecondText.IsDone);
  Assert.IsTrue(SearchRequest.IsDone);
  Assert.IsTrue(TilesRequest.IsDone);
end;

procedure TPdfViewerSessionTests.TestFatalFailureFailsTheSessionAndOpenStartsAgain;
begin
  OpenOrFail(TViewerDocuments.Invoice);
  FailTextExtractionFatally;
  FSession.RequestPageText(0, TPdfJobPriority.Visible, nil);

  WaitUntil(
    function: Boolean
    begin
      Result := (FSession.State = TPdfDocumentState.Failed);
    end,
    'the session to fail');
  Assert.AreEqual(1, Integer(FFatalMessages.Count));
  Assert.AreEqual('Injected access violation', FFatalMessages[0]);
  Assert.IsTrue(LogContains('fatal error'), 'The fatal error was not logged');
  Assert.WillRaise(
    procedure
    begin
      FSession.RequestPageText(0, TPdfJobPriority.Visible, nil);
    end,
    EInvalidOpException);

  {$IFDEF PDF4D_TESTS}
  TPdfDocumentHandle.StripperHook := nil;
  {$ENDIF}
  OpenOrFail(TViewerDocuments.Invoice);
  Assert.AreEqual(Ord(TPdfDocumentState.Open), Ord(FSession.State));
  var Text: IPdfPageText := nil;
  FSession.RequestPageText(0, TPdfJobPriority.Visible,
    procedure(const PageText: IPdfPageText)
    begin
      Text := PageText;
    end);
  WaitUntil(
    function: Boolean
    begin
      Result := Assigned(Text);
    end,
    'the page text of the new worker');
  Assert.IsFalse(Text.IsEmpty);
  Assert.AreEqual(1, Integer(FFatalMessages.Count));
end;

procedure TPdfViewerSessionTests.TestFatalFailureWhileOpeningFailsTheOpen;
begin
  {$IFDEF PDF4D_TESTS}
  PdfSessionDocumentHook :=
    procedure(const IsRelease: Boolean; const ThreadId: TThreadID)
    begin
      if not IsRelease then
      begin
        raise EAccessViolation.Create('Injected load failure');
      end;
    end;

  const Outcome = OpenData(TViewerDocuments.Invoice);

  Assert.IsFalse(Outcome.Succeeded);
  Assert.AreEqual(Ord(TPdfDocumentState.Failed), Ord(FSession.State));
  FDispatcher.RunPending;
  // The open reported it itself
  Assert.AreEqual(0, Integer(FFatalMessages.Count));

  PdfSessionDocumentHook := nil;
  OpenOrFail(TViewerDocuments.Invoice);
  Assert.AreEqual(Ord(TPdfDocumentState.Open), Ord(FSession.State));
  {$ELSE}
  Assert.Pass('The hook exists in the test build only');
  {$ENDIF}
end;

procedure TPdfViewerSessionTests.TestCreateWithoutBackendRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      TPdfViewerSession.Create(nil, FDispatcherReference, nil);
    end,
    EArgumentNilException);
end;

procedure TPdfViewerSessionTests.TestCreateWithoutDispatcherRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      TPdfViewerSession.Create(FBackendReference, nil, nil);
    end,
    EArgumentNilException);
end;

procedure TPdfViewerSessionTests.TestFailureWhileReleasingAtTheEndIsLogged;
begin
  {$IFDEF PDF4D_TESTS}
  PdfSessionDocumentHook :=
    procedure(const IsRelease: Boolean; const ThreadId: TThreadID)
    begin
      if IsRelease then
      begin
        raise EInvalidOpException.Create('Injected release failure');
      end;
    end;
  OpenOrFail(TViewerDocuments.Invoice);

  FSession := nil;

  Assert.IsTrue(LogContains('Injected release failure'), 'The failure of the release was not logged');
  {$ELSE}
  Assert.Pass('The hook exists in the test build only');
  {$ENDIF}
end;

procedure TPdfViewerSessionTests.TestResultInTheQueueIsDroppedByCancel;
begin
  OpenOrFail(TViewerDocuments.Invoice);
  const Events = TList<TTileEvent>.Create;
  try
    const Request = RequestAllTiles(0, 1, Events);
    // Pins that no callback runs after Cancel, Close or Destroy for a result that is already queued. The check inside the posted procedure
    // itself is pinned by TestOpenResultInTheQueueDoesNotReopenAClosedSession.
    WaitForPostedResult;
    Request.Cancel;
    FDispatcher.RunPending;

    Assert.AreEqual(0, Integer(Events.Count));
  finally
    Events.Free;
  end;
end;

procedure TPdfViewerSessionTests.TestResultInTheQueueIsDroppedByClose;
begin
  OpenOrFail(TViewerDocuments.Invoice);
  const Events = TList<TTileEvent>.Create;
  try
    RequestAllTiles(0, 1, Events);
    WaitForPostedResult;
    FSession.Close;
    FDispatcher.RunPending;

    Assert.AreEqual(0, Integer(Events.Count));
  finally
    Events.Free;
  end;
end;

procedure TPdfViewerSessionTests.TestResultInTheQueueIsDroppedByDestroy;
begin
  OpenOrFail(TViewerDocuments.Invoice);
  const Events = TList<TTileEvent>.Create;
  try
    RequestAllTiles(0, 1, Events);
    WaitForPostedResult;
    FSession := nil;
    FDispatcher.RunPending;

    Assert.AreEqual(0, Integer(Events.Count));
  finally
    Events.Free;
  end;
end;

procedure TPdfViewerSessionTests.TestOpenResultInTheQueueDoesNotReopenAClosedSession;
begin
  var Calls := 0;
  FSession.Open(TViewerDocuments.Invoice, '',
    procedure(const Outcome: TPdfOpenResult)
    begin
      Inc(Calls);
    end);
  // The result of the open is in the dispatcher queue when the session is closed: it changes the state of the session, so the check
  // inside the posted procedure is the only thing that keeps the closed session closed
  WaitForPostedResult;
  FSession.Close;
  FDispatcher.RunPending;

  Assert.AreEqual(Ord(TPdfDocumentState.Closed), Ord(FSession.State));
  Assert.AreEqual(0, FSession.PageCount);
  Assert.AreEqual(0, Calls);
end;

procedure TPdfViewerSessionTests.TestDocumentIsReleasedOnWorker;
begin
  {$IFDEF PDF4D_TESTS}
  const Released = TEvent.Create(nil, True, False, '');
  try
    var LoadedThread: TThreadID := 0;
    var ReleasedThread: TThreadID := 0;
    PdfSessionDocumentHook :=
      procedure(const IsRelease: Boolean; const ThreadId: TThreadID)
      begin
        if IsRelease then
        begin
          ReleasedThread := ThreadId;
          Released.SetEvent;
        end
        else
        begin
          LoadedThread := ThreadId;
        end;
      end;

    OpenOrFail(TViewerDocuments.Invoice);
    FSession.Close;

    Assert.AreEqual(TWaitResult.wrSignaled, Released.WaitFor(WaitMs), 'The document was not released');
    Assert.AreNotEqual(TThreadID(0), LoadedThread);
    Assert.AreNotEqual(MainThreadID, LoadedThread);
    Assert.AreEqual(LoadedThread, ReleasedThread);
  finally
    PdfSessionDocumentHook := nil;
    Released.Free;
  end;
  {$ELSE}
  Assert.Pass('The hook exists in the test build only');
  {$ENDIF}
end;

procedure TPdfViewerSessionTests.TestRequestWhileClosedRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      FSession.RequestRender(0, 1, 0, TRect.Empty, TPdfJobPriority.Visible, nil);
    end,
    EInvalidOpException);
  Assert.WillRaise(
    procedure
    begin
      FSession.RequestTiles(0, 1, 0, [TPoint.Create(0, 0)], TPdfJobPriority.Visible, nil);
    end,
    EInvalidOpException);
  Assert.WillRaise(
    procedure
    begin
      FSession.RequestPageText(0, TPdfJobPriority.PageText, nil);
    end,
    EInvalidOpException);
  Assert.WillRaise(
    procedure
    begin
      FSession.Search('a', False, nil, nil);
    end,
    EInvalidOpException);
end;

procedure TPdfViewerSessionTests.TestArgumentsAreChecked;
begin
  OpenOrFail(TViewerDocuments.Invoice);

  Assert.WillRaise(
    procedure
    begin
      FSession.RequestPageText(2, TPdfJobPriority.PageText, nil);
    end,
    EArgumentOutOfRangeException);
  Assert.WillRaise(
    procedure
    begin
      FSession.RequestPageText(-1, TPdfJobPriority.PageText, nil);
    end,
    EArgumentOutOfRangeException);
  Assert.WillRaise(
    procedure
    begin
      FSession.RequestRender(5, 1, 0, TRect.Empty, TPdfJobPriority.Visible, nil);
    end,
    EArgumentOutOfRangeException);
  Assert.WillRaise(
    procedure
    begin
      FSession.RequestTiles(2, 1, 0, nil, TPdfJobPriority.Visible, nil);
    end,
    EArgumentOutOfRangeException);
  Assert.WillRaise(
    procedure
    begin
      FSession.RequestRender(0, 0, 0, TRect.Empty, TPdfJobPriority.Visible, nil);
    end,
    EArgumentOutOfRangeException);
  Assert.WillRaise(
    procedure
    begin
      FSession.RequestRender(0, 1, 45, TRect.Empty, TPdfJobPriority.Visible, nil);
    end,
    EArgumentException);
end;

procedure TPdfViewerSessionTests.TestSessionOpensAgainAfterClose;
begin
  OpenOrFail(TViewerDocuments.Invoice);
  FSession.Close;

  const Outcome = OpenData(TViewerDocuments.Pages(3, 100, 100, 90));

  Assert.IsTrue(Outcome.Succeeded, Outcome.ErrorMessage);
  Assert.AreEqual(3, FSession.PageCount);
  Assert.AreEqual(90, FSession.Pages[0].Rotation);
end;

{ TFakeViewerSessionTests }

procedure TFakeViewerSessionTests.TestRecordsRequestsAndCompletesTiles;
begin
  const Fake = TFakeViewerSession.Create;
  const Session: IPdfViewerSession = Fake;
  var Page: TPdfPageInfo;
  Page.CropBox := TPdfRectangle.Letter;
  Page.Rotation := 0;
  Page.Label_ := '';
  var Permissions: TPdfViewerPermissions;
  Permissions.CanPrint := True;
  Permissions.CanCopy := True;
  Fake.SetOpened([Page], nil, Permissions);
  var Sizes := '';

  Session.RequestTiles(0, 1, 0, [TPoint.Create(0, 0), TPoint.Create(2, 3)], TPdfJobPriority.Prefetch,
    procedure(const Tile: TPoint; const Outcome: TPdfRenderResult)
    begin
      Sizes := Sizes + Format('%d,%d:%dx%d;', [Tile.X, Tile.Y, Outcome.Bitmap.Width, Outcome.Bitmap.Height]);
    end);
  Fake.CompleteTiles(0, TAlphaColors.Red);

  Assert.AreEqual(1, Integer(Fake.Requests.Count));
  Assert.AreEqual(Ord(TFakeRequestKind.Tiles), Ord(Fake.Requests[0].Kind));
  Assert.AreEqual(Ord(TPdfJobPriority.Prefetch), Ord(Fake.Requests[0].Priority));
  Assert.AreEqual('0,0:256x256;2,3:100x24;', Sizes);
  Assert.IsTrue(Fake.Requests[0].IsDone);
end;

procedure TFakeViewerSessionTests.TestCancelledRequestIsNotCompleted;
begin
  const Fake = TFakeViewerSession.Create;
  const Session: IPdfViewerSession = Fake;
  var Page: TPdfPageInfo;
  Page.CropBox := TPdfRectangle.Letter;
  Page.Rotation := 0;
  Page.Label_ := '';
  var Permissions: TPdfViewerPermissions;
  Permissions.CanPrint := True;
  Permissions.CanCopy := True;
  Fake.SetOpened([Page], nil, Permissions);
  var Calls := 0;

  const Request = Session.RequestPageText(0, TPdfJobPriority.PageText,
    procedure(const PageText: IPdfPageText)
    begin
      Inc(Calls);
    end);
  Request.Cancel;
  Fake.CompletePageText(0, TPdfPageText.Empty(0));

  Assert.IsTrue(Fake.Requests[0].Cancelled);
  Assert.AreEqual(0, Calls);
end;

procedure TFakeViewerSessionTests.TestFailRenderCallsEveryTile;
begin
  const Fake = TFakeViewerSession.Create;
  const Session: IPdfViewerSession = Fake;
  var Page: TPdfPageInfo;
  Page.CropBox := TPdfRectangle.Letter;
  Page.Rotation := 0;
  Page.Label_ := '';
  var Permissions: TPdfViewerPermissions;
  Permissions.CanPrint := True;
  Permissions.CanCopy := True;
  Fake.SetOpened([Page], nil, Permissions);
  var Messages := '';

  Session.RequestTiles(0, 1, 0, [TPoint.Create(0, 0), TPoint.Create(1, 0)], TPdfJobPriority.Visible,
    procedure(const Tile: TPoint; const Outcome: TPdfRenderResult)
    begin
      Messages := Messages + Outcome.ErrorMessage + ';';
    end);
  Fake.FailRender(0, 'boom');

  Assert.AreEqual('boom;boom;', Messages);
end;

end.
