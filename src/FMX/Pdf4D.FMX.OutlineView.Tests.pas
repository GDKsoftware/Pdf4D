// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.FMX.OutlineView.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.FMX.OutlineView,
  Pdf4D.Tests.FmxHost;

type
  [TestFixture]
  TPdf4DOutlineViewTests = class
  private
    FHost: TFmxTestHost;

    // All items, those in collapsed branches too
    function ItemsIn(const View: TPdf4DOutlineView): Integer;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestOutlineFillsAndNavigates;

    [Test]
    procedure TestEnterNavigates;

    [Test]
    procedure TestOutlineClearsOnClose;

    [Test]
    procedure TestDocumentThatIsOpenAlreadyFillsTheView;

    [Test]
    procedure TestOutlineClearsWhenTheDocumentIsFreed;
  end;

implementation

uses
  System.UITypes,
  FMX.TreeView,
  Pdf4D.FMX.Document,
  Pdf4D.Tests.ViewerDocuments;

const
  ViewWidth = 800;
  ViewHeight = 600;
  OutlineWidth = 200;
  ItemCount = 3;
  EnterChar = #13;

{ TPdf4DOutlineViewTests }

function TPdf4DOutlineViewTests.ItemsIn(const View: TPdf4DOutlineView): Integer;
begin
  Result := 0;
  var CountBelow: TFunc<TTreeViewItem, Integer>;
  CountBelow :=
    function(Item: TTreeViewItem): Integer
    begin
      Result := 1;
      for var Index := 0 to Item.Count - 1 do
      begin
        Inc(Result, CountBelow(Item.Items[Index]));
      end;
    end;
  for var Index := 0 to View.Count - 1 do
  begin
    Inc(Result, CountBelow(View.Items[Index]));
  end;
  CountBelow := nil;
end;

procedure TPdf4DOutlineViewTests.Setup;
begin
  FHost := TFmxTestHost.Create(ViewWidth, ViewHeight);
  FHost.AddOutlineView(OutlineWidth);
  FHost.AddPageView;
end;

procedure TPdf4DOutlineViewTests.TearDown;
begin
  FreeAndNil(FHost);
end;

procedure TPdf4DOutlineViewTests.TestOutlineFillsAndNavigates;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Outlined), 'the document opens: ' + FHost.OpenErrorMessage);

  const View = FHost.OutlineView;
  Assert.AreEqual(ItemCount, ItemsIn(View), 'one item per entry');
  Assert.AreEqual(2, View.Count, 'two chapters at the top');
  const Chapter1 = View.Items[0];
  const Chapter2 = View.Items[1];
  Assert.AreEqual(1, Chapter1.Count, 'the first chapter has a section');
  const Section = Chapter1.Items[0];
  Assert.AreEqual('Chapter 1', Chapter1.Text);
  Assert.AreEqual('Section 1.1', Section.Text);
  Assert.AreEqual('Chapter 2', Chapter2.Text);
  Assert.AreEqual(1, Integer(Section.Tag), 'the tag of an item is the index of its entry');

  View.Selected := Section;
  Assert.AreEqual(1, FHost.Document.CurrentPage, 'selecting the section shows its page');

  View.Selected := Chapter1;
  Assert.AreEqual(0, FHost.Document.CurrentPage, 'selecting the chapter shows its page');
end;

procedure TPdf4DOutlineViewTests.TestEnterNavigates;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Outlined), 'the document opens: ' + FHost.OpenErrorMessage);
  FHost.OutlineView.Selected := FHost.OutlineView.Items[1];
  FHost.Document.CurrentPage := 0;

  FHost.PressKeyOn(FHost.OutlineView, vkReturn, [], EnterChar);

  Assert.AreEqual(1, FHost.Document.CurrentPage, 'Enter shows the page of the selected item');
end;

procedure TPdf4DOutlineViewTests.TestOutlineClearsOnClose;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Outlined), 'the document opens: ' + FHost.OpenErrorMessage);
  Assert.AreEqual(ItemCount, ItemsIn(FHost.OutlineView));

  FHost.Document.Close;

  Assert.AreEqual(0, ItemsIn(FHost.OutlineView), 'the view is empty');
end;

procedure TPdf4DOutlineViewTests.TestDocumentThatIsOpenAlreadyFillsTheView;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Outlined), 'the document opens: ' + FHost.OpenErrorMessage);
  FHost.OutlineView.Document := nil;
  Assert.AreEqual(0, ItemsIn(FHost.OutlineView), 'unlinking empties the view');

  FHost.OutlineView.Document := FHost.Document;

  Assert.AreEqual(ItemCount, ItemsIn(FHost.OutlineView), 'the items of the open document are shown at once');
end;

procedure TPdf4DOutlineViewTests.TestOutlineClearsWhenTheDocumentIsFreed;
begin
  const Document = TPdf4DDocument.Create(nil);
  const View = TPdf4DOutlineView.Create(nil);
  try
    View.Document := Document;
    Document.Free;

    Assert.IsNull(View.Document, 'the view lets go of the document');
    Assert.AreEqual(0, ItemsIn(View), 'and shows nothing');
  finally
    View.Free;
  end;
end;

end.
