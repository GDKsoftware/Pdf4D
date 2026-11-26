// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.Document.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Common.Quad,
  Pdf4D.Common.Defines,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.PageText,
  Pdf4D.Viewer.Document,
  Pdf4D.Tests.TestDocument;

type
  [TestFixture]
  TPdf4DCustomDocumentTests = class
  private
    FBench: TDocumentBench;
    FOpenErrorKind: TPdfOpenErrorKind;
    FOpenErrorMessage: string;
    FLogText: string;
    FOpenedCount: Integer;
    FClosedCount: Integer;

    class function Square: TPdfQuad; static;
    procedure OpenInvoice;
    // Renders the first page of the open document at half scale and returns how many of its pixels are not white
    function RenderedInkPixels: Integer;
    // Requests the text of a page and waits for it
    procedure RequestPageTextAndWait(const PageIndex: Integer);
    procedure SearchAndWait(const Query: string);
    procedure HandleOpenError(Sender: TObject; const Kind: TPdfOpenErrorKind; const Message: string);
    procedure HandleOpenedCloses(Sender: TObject);
    procedure HandleOpenedCounts(Sender: TObject);
    procedure HandleClosedCounts(Sender: TObject);
    procedure HandleChangeRaises(const Change: TPdfDocumentChange);
    procedure HandleLogRaises(Sender: TObject; const Level: TPdfLogLevel; const Message: string);
    procedure HandleLogRecords(Sender: TObject; const Level: TPdfLogLevel; const Message: string);

  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestDefaultBackendIsNative;
    [Test]
    procedure TestDocumentWithoutBackendRendersWithTheNativeRasterizer;
    [Test]
    procedure TestExplicitBackendIsKept;
    [Test]
    procedure TestBackendComponentIsUsed;
    [Test]
    procedure TestRenderBackendWinsOverComponent;
    [Test]
    procedure TestLinksGetChanges;
    [Test]
    procedure TestFailingLinkDoesNotSilenceTheOthers;
    [Test]
    procedure TestFailingLogHandlerDoesNotLeakTheFirstFailure;
    [Test]
    procedure TestFreedLinkGetsNothing;
    [Test]
    procedure TestOpenErrorEvent;
    [Test]
    procedure TestFatalFailureFailsTheDocumentAndOpenStartsAgain;
    [Test]
    procedure TestOpenFromStreamCopiesData;
    [Test]
    procedure TestOpenFromStreamStartsAtItsPosition;
    [Test]
    procedure TestCurrentPageIsClamped;
    [Test]
    procedure TestCloseInsideOnOpened;
    [Test]
    procedure TestOpenTwiceDeliversOnlySecond;
    [Test]
    procedure TestEventsOpenedAndClosed;
    [Test]
    procedure TestFreeWhileOpening;
    [Test]
    procedure TestFreeWaitsForAWorkerThatIsBusy;
    [Test]
    procedure TestFreedDocumentLetsGoOfItsLinks;
    [Test]
    procedure TestPageTextCache;
    [Test]
    procedure TestCloseClearsEverything;
    [Test]
    procedure TestSearchNavigation;
    [Test]
    procedure TestSearchHitOnLaterPageSetsCurrentPage;
    [Test]
    procedure TestManyHitsAreAskedForPerPage;
    [Test]
    procedure TestHitsOnOnePageKeepTheirPlace;
    [Test]
    procedure TestSearchStopsAtTheHitLimit;
    [Test]
    procedure TestAnExactFitIsNotCapped;
    [Test]
    procedure TestNoHitsAllowedMeansNoHits;
    [Test]
    procedure TestNewSearchCancelsOld;
    [Test]
    procedure TestEmptyQueryClearsResults;
    [Test]
    procedure TestCancelSearchStopsIt;
    [Test]
    procedure TestSearchWhileClosedRaises;
    [Test]
    procedure TestPermissions;
    [Test]
    procedure TestSessionIsNilWhileClosed;
  end;

implementation

uses
  System.Types,
  System.SyncObjs,
  System.Diagnostics,
  System.Generics.Collections,
  Pdf4D.Api.DocumentHandle,
  Pdf4D.Viewer.Session,
  Pdf4D.Viewer.Backend,
  Pdf4D.Viewer.ResourceStrings,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Tests.Corpus,
  Pdf4D.Tests.ViewerDocuments;

const
  EncryptedFile = 'generated/encrypted/aes-128-user.pdf';
  RestrictedFile = 'pdfbox/org/apache/pdfbox/encryption/PasswordSample-128bit.pdf';
  InvoiceNumber = '2024-0815';
  LinkFailure = 'the link failed';
  ManyPages = 65;
  PageSize = 612;
  PageHeight = 792;
  WorkerWaitMs = 20000;
  HitPages = 200;
  HitLimit = 10;
  BusyMs = 300;
  BusyMargin = 50;

{ TPdf4DCustomDocumentTests }

procedure TPdf4DCustomDocumentTests.Setup;
begin
  FBench := TDocumentBench.Create;
  FOpenErrorMessage := '';
  FLogText := '';
  FOpenedCount := 0;
  FClosedCount := 0;
end;

procedure TPdf4DCustomDocumentTests.TearDown;
begin
  {$IFDEF PDF4D_TESTS}
  TPdfDocumentHandle.StripperHook := nil;
  {$ENDIF}
  FBench.Free;
end;

class function TPdf4DCustomDocumentTests.Square: TPdfQuad;
begin
  Result := TPdfQuad.Create(TPointF.Create(100, 100), TPointF.Create(200, 100), TPointF.Create(200, 120), TPointF.Create(100, 120));
end;

procedure TPdf4DCustomDocumentTests.OpenInvoice;
begin
  FBench.OpenData(TViewerDocuments.Invoice);
  Assert.AreEqual(Ord(TPdfDocumentState.Open), Ord(FBench.Document.State));
end;

procedure TPdf4DCustomDocumentTests.RequestPageTextAndWait(const PageIndex: Integer);
begin
  var Done := False;
  FBench.Document.RequestPageText(PageIndex, TPdfJobPriority.Visible,
    procedure(const PageText: IPdfPageText)
    begin
      Done := True;
    end);
  FBench.WaitUntil(
    function: Boolean
    begin
      Result := Done;
    end,
    'the page text');
end;

procedure TPdf4DCustomDocumentTests.SearchAndWait(const Query: string);
begin
  FBench.Document.Search(Query, False);
  FBench.WaitUntil(
    function: Boolean
    begin
      Result := not FBench.Document.IsSearching;
    end,
    'the search');
end;

procedure TPdf4DCustomDocumentTests.HandleOpenError(Sender: TObject; const Kind: TPdfOpenErrorKind; const Message: string);
begin
  FOpenErrorKind := Kind;
  FOpenErrorMessage := Message;
end;

procedure TPdf4DCustomDocumentTests.HandleLogRecords(Sender: TObject; const Level: TPdfLogLevel; const Message: string);
begin
  FLogText := FLogText + Message + sLineBreak;
end;

procedure TPdf4DCustomDocumentTests.HandleOpenedCloses(Sender: TObject);
begin
  FBench.Document.Close;
end;

procedure TPdf4DCustomDocumentTests.HandleOpenedCounts(Sender: TObject);
begin
  Inc(FOpenedCount);
end;

procedure TPdf4DCustomDocumentTests.HandleClosedCounts(Sender: TObject);
begin
  Inc(FClosedCount);
end;

function TPdf4DCustomDocumentTests.RenderedInkPixels: Integer;
begin
  var Ink := 0;
  var Done := False;
  FBench.Document.Session.RequestRender(0, 0.5, 0, TRect.Empty, TPdfJobPriority.Visible,
    procedure(const Outcome: TPdfRenderResult)
    begin
      if Outcome.Succeeded then
      begin
        for var Y := 0 to Outcome.Bitmap.Height - 1 do
        begin
          for var X := 0 to Outcome.Bitmap.Width - 1 do
          begin
            const Pixel = Outcome.Bitmap.GetPixel(X, Y);
            if (Pixel.R < 128) or (Pixel.G < 128) or (Pixel.B < 128) then
            begin
              Inc(Ink);
            end;
          end;
        end;
      end;
      Done := True;
    end);
  FBench.WaitUntil(
    function: Boolean
    begin
      Result := Done;
    end,
    'the render');
  Result := Ink;
end;

procedure TPdf4DCustomDocumentTests.TestDefaultBackendIsNative;
begin
  Assert.AreEqual('Native', TPdfViewerDefaults.CreateBackend.Name);
end;

procedure TPdf4DCustomDocumentTests.TestDocumentWithoutBackendRendersWithTheNativeRasterizer;
begin
  FBench.Document.RenderBackend := nil;
  Assert.IsNull(FBench.Document.Backend);

  OpenInvoice;

  Assert.AreEqual(0, FBench.Backend.DeviceCount, 'the recording backend of the bench is not used');
  Assert.IsTrue(RenderedInkPixels > 0, 'the page has text and lines');
end;

procedure TPdf4DCustomDocumentTests.TestExplicitBackendIsKept;
begin
  OpenInvoice;

  RenderedInkPixels;

  Assert.IsTrue(FBench.Backend.DeviceCount > 0, 'the explicit backend made the devices');
end;

procedure TPdf4DCustomDocumentTests.TestBackendComponentIsUsed;
begin
  const Component = TTestBackendComponent.Create(nil);
  try
    FBench.Document.RenderBackend := nil;
    FBench.Document.Backend := Component;

    FBench.OpenData(TViewerDocuments.Invoice);

    Assert.AreEqual(1, Component.CreateCount);
    Assert.AreEqual(Ord(TPdfDocumentState.Open), Ord(FBench.Document.State));
  finally
    Component.Free;
  end;

  Assert.IsNull(FBench.Document.Backend);
end;

procedure TPdf4DCustomDocumentTests.TestRenderBackendWinsOverComponent;
begin
  const Component = TTestBackendComponent.Create(nil);
  try
    FBench.Document.Backend := Component;

    FBench.OpenData(TViewerDocuments.Invoice);

    Assert.AreEqual(0, Component.CreateCount);
    Assert.AreEqual(Ord(TPdfDocumentState.Open), Ord(FBench.Document.State));
  finally
    FBench.Document.Backend := nil;
    Component.Free;
  end;
end;

procedure TPdf4DCustomDocumentTests.TestLinksGetChanges;
begin
  const Second = TChangeRecorder.Create(FBench.Document);
  try
    OpenInvoice;

    Assert.AreEqual('Opening,Opened', FBench.Recorder.Describe);
    Assert.AreEqual('Opening,Opened', Second.Describe);

    FBench.Document.CurrentPage := 1;

    Assert.AreEqual('Opening,Opened,CurrentPage', FBench.Recorder.Describe);
    Assert.AreEqual('Opening,Opened,CurrentPage', Second.Describe);

    FBench.Document.Close;

    Assert.AreEqual('Opening,Opened,CurrentPage,Closed', FBench.Recorder.Describe);
    Assert.AreEqual('Opening,Opened,CurrentPage,Closed', Second.Describe);
  finally
    Second.Free;
  end;
end;

procedure TPdf4DCustomDocumentTests.HandleChangeRaises(const Change: TPdfDocumentChange);
begin
  raise EPdfViewerException.Create(LinkFailure);
end;

procedure TPdf4DCustomDocumentTests.HandleLogRaises(Sender: TObject; const Level: TPdfLogLevel; const Message: string);
begin
  raise EInvalidOpException.Create('Raised by the log handler');
end;

// The links after a link that raises still hear the change, and the exception still reaches the caller
procedure TPdf4DCustomDocumentTests.TestFailingLinkDoesNotSilenceTheOthers;
begin
  OpenInvoice;
  const Failing = TPdfDocumentLink.Create(HandleChangeRaises);
  const Second = TChangeRecorder.Create(FBench.Document);
  try
    Failing.Document := FBench.Document;
    const Third = TChangeRecorder.Create(FBench.Document);
    try
      Assert.WillRaiseWithMessage(
        procedure
        begin
          FBench.Document.CurrentPage := 1;
        end,
        EPdfViewerException,
        LinkFailure);

      Assert.AreEqual('CurrentPage', Second.Describe, 'a link before the failing one');
      Assert.AreEqual('CurrentPage', Third.Describe, 'a link after the failing one');
      Assert.AreEqual(1, FBench.Document.CurrentPage);
    finally
      Third.Free;
    end;
  finally
    Second.Free;
    Failing.Free;
  end;
end;

// The log handler of the application raises while the second failure is logged: that exception goes on, and the first one is freed
// (the leak check of the test program fails otherwise)
procedure TPdf4DCustomDocumentTests.TestFailingLogHandlerDoesNotLeakTheFirstFailure;
begin
  OpenInvoice;
  FBench.Document.OnLog := HandleLogRaises;
  const First = TPdfDocumentLink.Create(HandleChangeRaises);
  const Second = TPdfDocumentLink.Create(HandleChangeRaises);
  try
    First.Document := FBench.Document;
    Second.Document := FBench.Document;

    Assert.WillRaiseWithMessage(
      procedure
      begin
        FBench.Document.CurrentPage := 1;
      end,
      EInvalidOpException,
      'Raised by the log handler');
  finally
    Second.Free;
    First.Free;
    FBench.Document.OnLog := nil;
  end;
end;

procedure TPdf4DCustomDocumentTests.TestFreedLinkGetsNothing;
begin
  const Second = TChangeRecorder.Create(FBench.Document);
  Second.Free;

  OpenInvoice;
  FBench.Document.Close;

  Assert.AreEqual('Opening,Opened,Closed', FBench.Recorder.Describe);
end;

procedure TPdf4DCustomDocumentTests.TestOpenErrorEvent;
begin
  FBench.Document.OnOpenError := HandleOpenError;

  FBench.OpenFile(TCorpus.PdfPath(EncryptedFile), 'not the password');

  Assert.AreEqual(Ord(TPdfDocumentState.Failed), Ord(FBench.Document.State));
  Assert.AreEqual(Ord(TPdfOpenErrorKind.InvalidPassword), Ord(FOpenErrorKind));
  Assert.AreEqual(Ord(TPdfOpenErrorKind.InvalidPassword), Ord(FBench.Document.OpenErrorKind), 'the document tells why it failed');
  Assert.IsFalse(FOpenErrorMessage.IsEmpty);
  Assert.AreEqual('Opening,OpenFailed', FBench.Recorder.Describe);
  Assert.AreEqual(0, FBench.Document.PageCount);
end;

procedure TPdf4DCustomDocumentTests.TestFatalFailureFailsTheDocumentAndOpenStartsAgain;
begin
  {$IFDEF PDF4D_TESTS}
  OpenInvoice;
  FBench.Document.OnOpenError := HandleOpenError;
  TPdfDocumentHandle.StripperHook :=
    procedure
    begin
      raise EAccessViolation.Create('Injected access violation');
    end;

  FBench.Document.RequestPageText(0, TPdfJobPriority.Visible, nil);
  FBench.WaitUntil(
    function: Boolean
    begin
      Result := (FBench.Document.State = TPdfDocumentState.Failed);
    end,
    'the document to fail');

  Assert.AreEqual(Ord(TPdfOpenErrorKind.Other), Ord(FOpenErrorKind));
  Assert.AreEqual(Ord(TPdfOpenErrorKind.Other), Ord(FBench.Document.OpenErrorKind), 'the document tells why it failed');
  Assert.AreEqual('Injected access violation', FOpenErrorMessage);
  Assert.IsTrue(FBench.Recorder.Describe.EndsWith('OpenFailed'), FBench.Recorder.Describe);
  Assert.AreEqual(0, FBench.Document.PageCount);

  TPdfDocumentHandle.StripperHook := nil;
  OpenInvoice;
  RequestPageTextAndWait(0);
  {$ELSE}
  Assert.Pass('The hook exists in the test build only');
  {$ENDIF}
end;

procedure TPdf4DCustomDocumentTests.TestOpenFromStreamCopiesData;
begin
  const Stream = TBytesStream.Create(TViewerDocuments.Invoice);
  FBench.Document.Open(Stream);
  Stream.Free;

  FBench.WaitUntil(
    function: Boolean
    begin
      Result := (FBench.Document.State <> TPdfDocumentState.Opening);
    end,
    'the document to open');

  Assert.AreEqual(Ord(TPdfDocumentState.Open), Ord(FBench.Document.State));
  Assert.AreEqual(2, FBench.Document.PageCount);
end;

procedure TPdf4DCustomDocumentTests.TestOpenFromStreamStartsAtItsPosition;
begin
  const Document = TViewerDocuments.Invoice;
  const Stream = TBytesStream.Create;
  try
    const Prefix: TBytes = [1, 2, 3];
    Stream.WriteBuffer(Prefix[0], Length(Prefix));
    Stream.WriteBuffer(Document[0], Length(Document));
    Stream.Position := Length(Prefix);

    FBench.Document.Open(Stream);
  finally
    Stream.Free;
  end;

  FBench.WaitUntil(
    function: Boolean
    begin
      Result := (FBench.Document.State <> TPdfDocumentState.Opening);
    end,
    'the document to open');

  Assert.AreEqual(Ord(TPdfDocumentState.Open), Ord(FBench.Document.State));
end;

procedure TPdf4DCustomDocumentTests.TestCurrentPageIsClamped;
begin
  Assert.AreEqual(0, FBench.Document.CurrentPage);
  OpenInvoice;

  FBench.Document.CurrentPage := 99;
  Assert.AreEqual(1, FBench.Document.CurrentPage);

  FBench.Document.CurrentPage := -1;
  Assert.AreEqual(0, FBench.Document.CurrentPage);
end;

procedure TPdf4DCustomDocumentTests.TestCloseInsideOnOpened;
begin
  FBench.Document.OnOpened := HandleOpenedCloses;

  FBench.OpenData(TViewerDocuments.Invoice);
  FBench.Dispatcher.RunPending;

  Assert.AreEqual(Ord(TPdfDocumentState.Closed), Ord(FBench.Document.State));
  Assert.AreEqual(0, FBench.Document.PageCount);
  Assert.AreEqual('Opening,Opened,Closed', FBench.Recorder.Describe);
end;

procedure TPdf4DCustomDocumentTests.TestOpenTwiceDeliversOnlySecond;
begin
  FBench.Document.OnOpened := HandleOpenedCounts;
  FBench.Document.OnClosed := HandleClosedCounts;
  const Stream = TBytesStream.Create(TViewerDocuments.Invoice);
  try
    FBench.Document.Open(Stream);
    Stream.Position := 0;
    FBench.Document.Open(Stream);
  finally
    Stream.Free;
  end;

  FBench.WaitUntil(
    function: Boolean
    begin
      Result := (FBench.Document.State <> TPdfDocumentState.Opening);
    end,
    'the second open');
  FBench.Dispatcher.RunPending;

  Assert.AreEqual(1, FOpenedCount);
  Assert.AreEqual(1, FClosedCount);
  Assert.AreEqual('Opening,Closed,Opening,Opened', FBench.Recorder.Describe);
end;

procedure TPdf4DCustomDocumentTests.TestEventsOpenedAndClosed;
begin
  FBench.Document.OnOpened := HandleOpenedCounts;
  FBench.Document.OnClosed := HandleClosedCounts;

  OpenInvoice;
  Assert.AreEqual(1, FOpenedCount);
  Assert.AreEqual(0, FClosedCount);

  FBench.Document.Close;
  FBench.Document.Close;

  Assert.AreEqual(1, FClosedCount);
end;

procedure TPdf4DCustomDocumentTests.TestFreeWhileOpening;
begin
  const Stream = TBytesStream.Create(TViewerDocuments.Invoice);
  try
    FBench.Document.Open(Stream);
  finally
    Stream.Free;
  end;

  // The result is on its way to a document that goes: nothing may be called on it
  FBench.FreeDocument;
  FBench.Dispatcher.RunPending;

  Assert.IsNull(FBench.Recorder.Link.Document);
end;

// Pins what is so today: a job on the worker cannot be stopped, so freeing the document waits for it. Nothing may be called on the
// freed document meanwhile or afterwards (the leak check of the test program and the open request catch that).
procedure TPdf4DCustomDocumentTests.TestFreeWaitsForAWorkerThatIsBusy;
begin
  {$IFDEF PDF4D_TESTS}
  const Entered = TEvent.Create(nil, True, False, '');
  const Gate = TEvent.Create(nil, True, False, '');
  try
    PdfSessionDocumentHook :=
      procedure(const IsRelease: Boolean; const ThreadId: TThreadID)
      begin
        if not IsRelease then
        begin
          Entered.SetEvent;
          Gate.WaitFor(WorkerWaitMs);
        end;
      end;

    const Stream = TBytesStream.Create(TViewerDocuments.Invoice);
    try
      FBench.Document.Open(Stream);
    finally
      Stream.Free;
    end;
    Assert.AreEqual(TWaitResult.wrSignaled, Entered.WaitFor(WorkerWaitMs), 'the worker is busy with the load');

    // Lets go of the worker after a while, from another thread
    TThread.CreateAnonymousThread(
      procedure
      begin
        Sleep(BusyMs);
        Gate.SetEvent;
      end).Start;

    const Watch = TStopwatch.StartNew;
    FBench.FreeDocument;
    Watch.Stop;
    PdfSessionDocumentHook := nil;

    Assert.IsTrue(Watch.ElapsedMilliseconds >= BusyMs - BusyMargin, Format('freeing waited for the worker: %d ms', [Watch.ElapsedMilliseconds]));
    Assert.IsNull(FBench.Recorder.Link.Document);
    Assert.AreEqual('Opening,Closed', FBench.Recorder.Describe, 'the load never reached the document');
  finally
    PdfSessionDocumentHook := nil;
    Gate.SetEvent;
    Gate.Free;
    Entered.Free;
  end;
  {$ELSE}
  Assert.Pass('The hook exists in the test build only');
  {$ENDIF}
end;

procedure TPdf4DCustomDocumentTests.TestFreedDocumentLetsGoOfItsLinks;
begin
  OpenInvoice;

  FBench.FreeDocument;

  Assert.IsNull(FBench.Recorder.Link.Document);
  Assert.AreEqual('Opening,Opened,Closed', FBench.Recorder.Describe);
end;

procedure TPdf4DCustomDocumentTests.TestPageTextCache;
begin
  FBench.OpenData(TViewerDocuments.Pages(ManyPages, PageSize, PageHeight, 0));
  Assert.AreEqual(ManyPages, FBench.Document.PageCount);
  Assert.AreEqual(64, FBench.Document.PageTextCacheCount);

  var PageText: IPdfPageText;
  Assert.IsFalse(FBench.Document.TryGetPageText(0, PageText));

  RequestPageTextAndWait(0);
  Assert.IsTrue(FBench.Document.TryGetPageText(0, PageText));
  Assert.AreEqual(0, PageText.PageIndex);

  for var PageIndex := 1 to ManyPages - 1 do
  begin
    RequestPageTextAndWait(PageIndex);
  end;

  Assert.IsFalse(FBench.Document.TryGetPageText(0, PageText), 'the oldest page is out');
  Assert.IsTrue(FBench.Document.TryGetPageText(1, PageText));
  Assert.IsTrue(FBench.Document.TryGetPageText(ManyPages - 1, PageText));
end;

procedure TPdf4DCustomDocumentTests.TestCloseClearsEverything;
begin
  OpenInvoice;
  RequestPageTextAndWait(0);
  SearchAndWait(InvoiceNumber);
  FBench.Document.Overlays.Add(0, [Square], TPdfOverlayStyle.Fill, $66FF0000);
  FBench.Document.CurrentPage := 1;

  FBench.Document.Close;

  var PageText: IPdfPageText;
  Assert.IsFalse(FBench.Document.TryGetPageText(0, PageText));
  Assert.AreEqual(0, Integer(Length(FBench.Document.SearchHits)));
  Assert.AreEqual(0, Integer(Length(FBench.Document.Overlays.Items)));
  Assert.AreEqual(0, FBench.Document.CurrentPage);
  Assert.IsFalse(FBench.Document.IsSearching);

  // A new open starts from nothing, too
  OpenInvoice;
  Assert.AreEqual(0, Integer(Length(FBench.Document.SearchHits)));
  Assert.AreEqual(0, Integer(Length(FBench.Document.Overlays.Items)));
  Assert.IsFalse(FBench.Document.TryGetPageText(0, PageText));
  Assert.AreEqual(0, FBench.Document.CurrentPage);
end;

procedure TPdf4DCustomDocumentTests.TestSearchNavigation;
begin
  OpenInvoice;
  FBench.Recorder.Reset;

  SearchAndWait(InvoiceNumber);

  Assert.AreEqual(2, Integer(Length(FBench.Document.SearchHits)));
  var Index: Integer;
  var Hit: TPdfSearchHit;
  Assert.IsTrue(FBench.Document.TryGetCurrentSearchHit(Index, Hit));
  Assert.AreEqual(0, Index);
  Assert.AreEqual(InvoiceNumber, Hit.Text);
  Assert.IsTrue(FBench.Recorder.Count(TPdfDocumentChange.SearchResults) > 0);
  Assert.AreEqual(1, FBench.Recorder.Count(TPdfDocumentChange.CurrentSearchHit));

  FBench.Document.NextSearchHit;
  Assert.IsTrue(FBench.Document.TryGetCurrentSearchHit(Index, Hit));
  Assert.AreEqual(1, Index);
  Assert.AreEqual(2, FBench.Recorder.Count(TPdfDocumentChange.CurrentSearchHit));

  FBench.Document.NextSearchHit;
  Assert.IsTrue(FBench.Document.TryGetCurrentSearchHit(Index, Hit));
  Assert.AreEqual(0, Index);

  FBench.Document.PriorSearchHit;
  Assert.IsTrue(FBench.Document.TryGetCurrentSearchHit(Index, Hit));
  Assert.AreEqual(1, Index);
end;

procedure TPdf4DCustomDocumentTests.TestSearchHitOnLaterPageSetsCurrentPage;
begin
  OpenInvoice;
  Assert.AreEqual(0, FBench.Document.CurrentPage);
  FBench.Recorder.Reset;

  SearchAndWait('Bedrag');

  Assert.AreEqual(1, Integer(Length(FBench.Document.SearchHits)));
  Assert.AreEqual(1, FBench.Document.CurrentPage);
  Assert.AreEqual(1, FBench.Recorder.Count(TPdfDocumentChange.CurrentPage));

  FBench.Document.CurrentPage := 0;
  FBench.Document.NextSearchHit;

  Assert.AreEqual(1, FBench.Document.CurrentPage);
end;

// A view asks for the hits of the pages it shows, not for all of them: with many hits this is what keeps a paint cheap
procedure TPdf4DCustomDocumentTests.TestManyHitsAreAskedForPerPage;
begin
  FBench.OpenData(TViewerDocuments.Pages(HitPages, PageSize, PageHeight, 0));
  Assert.AreEqual(0, FBench.Document.SearchHitCount);
  Assert.AreEqual(0, Integer(Length(FBench.Document.SearchHitsOnPage(0))));
  Assert.AreEqual(-1, FBench.Document.CurrentSearchHitOnPage(0));

  SearchAndWait('Page');

  Assert.AreEqual(HitPages, FBench.Document.SearchHitCount, 'a hit on every page');
  Assert.AreEqual(HitPages, Integer(Length(FBench.Document.SearchHits)));
  const OnPage = FBench.Document.SearchHitsOnPage(HitPages div 2);
  Assert.AreEqual(1, Integer(Length(OnPage)));
  Assert.AreEqual(HitPages div 2, OnPage[0].PageIndex);
  Assert.AreEqual(0, Integer(Length(FBench.Document.SearchHitsOnPage(HitPages))), 'no page, no hits');
  Assert.AreEqual(0, FBench.Document.CurrentSearchHitOnPage(0), 'the first hit is the current one');
  Assert.AreEqual(-1, FBench.Document.CurrentSearchHitOnPage(1));

  for var Step := 1 to HitPages div 2 do
  begin
    FBench.Document.NextSearchHit;
  end;
  Assert.AreEqual(0, FBench.Document.CurrentSearchHitOnPage(HitPages div 2));
  Assert.AreEqual(-1, FBench.Document.CurrentSearchHitOnPage(0));

  FBench.Document.Close;
  Assert.AreEqual(0, FBench.Document.SearchHitCount);
  Assert.AreEqual(0, Integer(Length(FBench.Document.SearchHitsOnPage(HitPages div 2))));
  Assert.AreEqual(-1, FBench.Document.CurrentSearchHitOnPage(HitPages div 2));
end;

// Several hits on one page keep their order, and the current hit is found among them
procedure TPdf4DCustomDocumentTests.TestHitsOnOnePageKeepTheirPlace;
begin
  OpenInvoice;
  SearchAndWait(InvoiceNumber);
  Assert.AreEqual(2, FBench.Document.SearchHitCount);

  var Total := 0;
  for var PageIndex := 0 to FBench.Document.PageCount - 1 do
  begin
    const OnPage = FBench.Document.SearchHitsOnPage(PageIndex);
    Inc(Total, Length(OnPage));
    for var Hit in OnPage do
    begin
      Assert.AreEqual(PageIndex, Hit.PageIndex);
    end;
  end;
  Assert.AreEqual(2, Total, 'every hit is on a page');

  var Index: Integer;
  var Current: TPdfSearchHit;
  for var Step := 1 to 2 do
  begin
    Assert.IsTrue(FBench.Document.TryGetCurrentSearchHit(Index, Current));
    const Position = FBench.Document.CurrentSearchHitOnPage(Current.PageIndex);
    Assert.IsTrue(Position >= 0, 'the current hit has a place on its page');
    Assert.AreEqual(InvoiceNumber, FBench.Document.SearchHitsOnPage(Current.PageIndex)[Position].Text);
    FBench.Document.NextSearchHit;
  end;
end;

procedure TPdf4DCustomDocumentTests.TestSearchStopsAtTheHitLimit;
begin
  FBench.OpenData(TViewerDocuments.Pages(HitPages, PageSize, PageHeight, 0));
  FBench.Document.OnLog := HandleLogRecords;
  Assert.AreEqual(DefaultMaxSearchHits, FBench.Document.MaxSearchHits);
  FBench.Document.MaxSearchHits := HitLimit;

  SearchAndWait('Page');

  Assert.AreEqual(HitLimit, FBench.Document.SearchHitCount);
  Assert.IsFalse(FBench.Document.IsSearching, 'the search stopped');
  Assert.IsTrue(FLogText.Contains(Format(SSearchHitLimitReached, [HitLimit])), 'the limit is in the log: ' + FLogText);
  Assert.IsTrue(FBench.Document.IsSearchCapped, 'the count is a lower bound');

  // Nothing arrives later
  FBench.Dispatcher.RunPending;
  Assert.AreEqual(HitLimit, FBench.Document.SearchHitCount);
  FBench.Document.OnLog := nil;
end;

// Exactly as many hits as the limit allows: nothing was cut off, so nothing is logged and the count is exact
procedure TPdf4DCustomDocumentTests.TestAnExactFitIsNotCapped;
begin
  FBench.OpenData(TViewerDocuments.Pages(HitPages, PageSize, PageHeight, 0));
  FBench.Document.OnLog := HandleLogRecords;
  FBench.Document.MaxSearchHits := HitPages;

  SearchAndWait('Page');

  Assert.AreEqual(HitPages, FBench.Document.SearchHitCount);
  Assert.IsFalse(FBench.Document.IsSearchCapped);
  Assert.IsFalse(FLogText.Contains(Format(SSearchHitLimitReached, [HitPages])), 'no limit line: ' + FLogText);
  FBench.Document.OnLog := nil;
end;

procedure TPdf4DCustomDocumentTests.TestNoHitsAllowedMeansNoHits;
begin
  FBench.OpenData(TViewerDocuments.Pages(HitPages, PageSize, PageHeight, 0));
  FBench.Document.MaxSearchHits := 0;

  SearchAndWait('Page');

  Assert.AreEqual(0, FBench.Document.SearchHitCount);
  Assert.IsTrue(FBench.Document.IsSearchCapped);

  FBench.Document.Search('', False);
  Assert.IsFalse(FBench.Document.IsSearchCapped, 'a new search starts uncapped');
end;

procedure TPdf4DCustomDocumentTests.TestNewSearchCancelsOld;
begin
  OpenInvoice;

  FBench.Document.Search('Bedrag', False);
  SearchAndWait(InvoiceNumber);
  FBench.Dispatcher.RunPending;

  Assert.AreEqual(2, Integer(Length(FBench.Document.SearchHits)));
  for var Hit in FBench.Document.SearchHits do
  begin
    Assert.AreEqual(InvoiceNumber, Hit.Text);
  end;
end;

procedure TPdf4DCustomDocumentTests.TestEmptyQueryClearsResults;
begin
  OpenInvoice;
  SearchAndWait(InvoiceNumber);
  FBench.Recorder.Reset;

  FBench.Document.Search('', False);

  Assert.AreEqual(0, Integer(Length(FBench.Document.SearchHits)));
  Assert.IsFalse(FBench.Document.IsSearching);
  var Index: Integer;
  var Hit: TPdfSearchHit;
  Assert.IsFalse(FBench.Document.TryGetCurrentSearchHit(Index, Hit));
  Assert.AreEqual(1, FBench.Recorder.Count(TPdfDocumentChange.SearchResults));
end;

procedure TPdf4DCustomDocumentTests.TestCancelSearchStopsIt;
begin
  OpenInvoice;
  FBench.Document.Search(InvoiceNumber, False);
  Assert.IsTrue(FBench.Document.IsSearching);
  FBench.Recorder.Reset;

  FBench.Document.CancelSearch;
  FBench.Dispatcher.RunPending;

  Assert.IsFalse(FBench.Document.IsSearching);
  Assert.AreEqual(0, Integer(Length(FBench.Document.SearchHits)), 'a cancelled search delivers nothing');
  Assert.AreEqual('SearchResults', FBench.Recorder.Describe);
end;

procedure TPdf4DCustomDocumentTests.TestSearchWhileClosedRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      FBench.Document.Search(InvoiceNumber, False);
    end,
    EInvalidOpException);

  // Clearing needs no document
  FBench.Document.Search('', False);
end;

procedure TPdf4DCustomDocumentTests.TestPermissions;
begin
  Assert.IsFalse(FBench.Document.CanPrint);
  Assert.IsFalse(FBench.Document.CanCopy);

  FBench.OpenFile(TCorpus.PdfPath(RestrictedFile), TCorpus.PasswordFor(RestrictedFile));
  Assert.AreEqual(Ord(TPdfDocumentState.Open), Ord(FBench.Document.State));

  Assert.IsFalse(FBench.Document.CanPrint);
  Assert.IsFalse(FBench.Document.CanCopy);

  FBench.Document.IgnorePermissions := True;

  Assert.IsTrue(FBench.Document.CanPrint);
  Assert.IsTrue(FBench.Document.CanCopy);
end;

procedure TPdf4DCustomDocumentTests.TestSessionIsNilWhileClosed;
begin
  Assert.IsNull(FBench.Document.Session);

  OpenInvoice;
  Assert.IsNotNull(FBench.Document.Session);

  FBench.Document.Close;
  Assert.IsNull(FBench.Document.Session);
end;

end.
