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
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.PageText,
  Pdf4D.Tests.TestDocument;

type
  [TestFixture]
  TPdf4DCustomDocumentTests = class
  private
    FBench: TDocumentBench;
    FOpenErrorKind: TPdfOpenErrorKind;
    FOpenErrorMessage: string;
    FOpenedCount: Integer;
    FClosedCount: Integer;

    class function Square: TPdfQuad; static;
    procedure OpenInvoice;
    // Requests the text of a page and waits for it
    procedure RequestPageTextAndWait(const PageIndex: Integer);
    procedure SearchAndWait(const Query: string);
    procedure HandleOpenError(Sender: TObject; const Kind: TPdfOpenErrorKind; const Message: string);
    procedure HandleOpenedCloses(Sender: TObject);
    procedure HandleOpenedCounts(Sender: TObject);
    procedure HandleClosedCounts(Sender: TObject);

  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestOpenWithoutBackendRaises;
    [Test]
    procedure TestBackendComponentIsUsed;
    [Test]
    procedure TestRenderBackendWinsOverComponent;
    [Test]
    procedure TestLinksGetChanges;
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
  System.Generics.Collections,
  Pdf4D.Common.Defines,
  Pdf4D.Api.DocumentHandle,
  Pdf4D.Viewer.Session,
  Pdf4D.Viewer.ResourceStrings,
  Pdf4D.Tests.Corpus,
  Pdf4D.Tests.ViewerDocuments;

const
  EncryptedFile = 'generated/encrypted/aes-128-user.pdf';
  RestrictedFile = 'pdfbox/org/apache/pdfbox/encryption/PasswordSample-128bit.pdf';
  InvoiceNumber = '2024-0815';
  ManyPages = 65;
  PageSize = 612;
  PageHeight = 792;

{ TPdf4DCustomDocumentTests }

procedure TPdf4DCustomDocumentTests.Setup;
begin
  FBench := TDocumentBench.Create;
  FOpenErrorMessage := '';
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

procedure TPdf4DCustomDocumentTests.TestOpenWithoutBackendRaises;
begin
  const Document = TTestDocument.Create(nil);
  try
    Document.FileName := TCorpus.PdfPath(EncryptedFile);

    Assert.WillRaiseWithMessage(
      procedure
      begin
        Document.Open;
      end,
      EPdfViewerException,
      SNoRenderBackend);

    Assert.AreEqual(Ord(TPdfDocumentState.Closed), Ord(Document.State));
  finally
    Document.Free;
  end;
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
