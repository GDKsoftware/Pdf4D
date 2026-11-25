// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.SearchBarModel.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Viewer.SearchBarModel,
  Pdf4D.Tests.TestDocument;

type
  [TestFixture]
  TPdfSearchBarModelTests = class
  private
    FBench: TDocumentBench;
    FModel: TPdfSearchBarModel;
    FChanges: Integer;

    procedure HandleChanged(Sender: TObject);
    procedure OpenInvoice;
    procedure WaitForSearch;

  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestEnterSearchesThenSteps;
    [Test]
    procedure TestNoResults;
    [Test]
    procedure TestACappedSearchShowsAPlus;
    [Test]
    procedure TestEmptyQueryClears;
    [Test]
    procedure TestOtherCaseSearchesAgain;
    [Test]
    procedure TestChangedQuerySearchesAgain;
    [Test]
    procedure TestClosingTheDocumentForgetsTheSearch;
    [Test]
    procedure TestNothingWhileClosed;
  end;

implementation

uses
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.ResourceStrings,
  Pdf4D.Tests.ViewerDocuments;

const
  InvoiceNumber = '2024-0815';
  InvoiceNumberHits = 2;
  Missing = 'zzzz';
  CapPages = 20;
  CapPageSize = 612;
  CapPageHeight = 792;
  CapLimit = 5;

{ TPdfSearchBarModelTests }

procedure TPdfSearchBarModelTests.Setup;
begin
  FBench := TDocumentBench.Create;
  FModel := TPdfSearchBarModel.Create;
  FModel.OnChanged := HandleChanged;
  FChanges := 0;
end;

procedure TPdfSearchBarModelTests.TearDown;
begin
  FreeAndNil(FModel);
  FreeAndNil(FBench);
end;

procedure TPdfSearchBarModelTests.HandleChanged(Sender: TObject);
begin
  Inc(FChanges);
end;

procedure TPdfSearchBarModelTests.OpenInvoice;
begin
  FBench.OpenData(TViewerDocuments.Invoice);
  Assert.AreEqual(Ord(TPdfDocumentState.Open), Ord(FBench.Document.State));
  FModel.Document := FBench.Document;
end;

procedure TPdfSearchBarModelTests.WaitForSearch;
begin
  FBench.WaitUntil(
    function: Boolean
    begin
      Result := not FBench.Document.IsSearching;
    end,
    'the search');
end;

procedure TPdfSearchBarModelTests.TestEnterSearchesThenSteps;
begin
  OpenInvoice;
  Assert.IsTrue(FModel.CanSearch);
  Assert.AreEqual('', FModel.ResultText, 'nothing before a search');

  FModel.Advance(InvoiceNumber, False, True);
  Assert.IsTrue(FModel.HasSearched);
  WaitForSearch;
  Assert.AreEqual(Format(SSearchResultCount, [1, InvoiceNumberHits]), FModel.ResultText);

  FChanges := 0;
  FModel.Advance(InvoiceNumber, False, True);
  Assert.AreEqual(Format(SSearchResultCount, [2, InvoiceNumberHits]), FModel.ResultText, 'the same query goes to the next hit');
  Assert.IsTrue(FChanges > 0, 'the bar hears of it');

  FModel.Advance(InvoiceNumber, False, False);
  Assert.AreEqual(Format(SSearchResultCount, [1, InvoiceNumberHits]), FModel.ResultText, 'backwards');
end;

procedure TPdfSearchBarModelTests.TestACappedSearchShowsAPlus;
begin
  FBench.OpenData(TViewerDocuments.Pages(CapPages, CapPageSize, CapPageHeight, 0));
  FModel.Document := FBench.Document;
  FBench.Document.MaxSearchHits := CapLimit;

  FModel.Advance('Page', False, True);
  WaitForSearch;

  Assert.AreEqual(Format(SSearchResultCountCapped, [1, CapLimit]), FModel.ResultText);
  Assert.IsTrue(FModel.ResultText.EndsWith('+'));
end;

procedure TPdfSearchBarModelTests.TestNoResults;
begin
  OpenInvoice;
  FModel.Advance(Missing, False, True);
  WaitForSearch;
  Assert.AreEqual(SSearchNoResults, FModel.ResultText);
end;

procedure TPdfSearchBarModelTests.TestEmptyQueryClears;
begin
  OpenInvoice;
  FModel.Advance(InvoiceNumber, False, True);
  WaitForSearch;

  FModel.Advance('', False, True);

  Assert.IsFalse(FModel.HasSearched);
  Assert.AreEqual('', FModel.ResultText);
  Assert.AreEqual<Integer>(0, Length(FBench.Document.SearchHits), 'the hits are gone');
end;

procedure TPdfSearchBarModelTests.TestOtherCaseSearchesAgain;
begin
  OpenInvoice;
  FModel.MatchCaseChanged('factuur', True);
  Assert.IsFalse(FModel.HasSearched, 'no search before the first one');

  FModel.Advance('factuur', False, True);
  WaitForSearch;
  Assert.AreEqual(Format(SSearchResultCount, [1, 1]), FModel.ResultText);

  FModel.MatchCaseChanged('factuur', True);
  WaitForSearch;
  Assert.AreEqual(SSearchNoResults, FModel.ResultText, 'the case counts now');
end;

procedure TPdfSearchBarModelTests.TestChangedQuerySearchesAgain;
begin
  OpenInvoice;
  FModel.Advance(InvoiceNumber, False, True);
  WaitForSearch;
  FModel.Advance(InvoiceNumber, False, True);

  FModel.Advance(Missing, False, True);
  WaitForSearch;
  Assert.AreEqual(SSearchNoResults, FModel.ResultText, 'a new query is a new search');
end;

procedure TPdfSearchBarModelTests.TestClosingTheDocumentForgetsTheSearch;
begin
  OpenInvoice;
  FModel.Advance(InvoiceNumber, False, True);
  WaitForSearch;

  FBench.Document.Close;

  Assert.IsFalse(FModel.HasSearched);
  Assert.AreEqual('', FModel.ResultText);
  Assert.IsFalse(FModel.CanSearch);
end;

procedure TPdfSearchBarModelTests.TestNothingWhileClosed;
begin
  FModel.Document := FBench.Document;
  FModel.Advance(InvoiceNumber, False, True);
  Assert.IsFalse(FModel.HasSearched);
  Assert.AreEqual('', FModel.ResultText);
end;

end.
