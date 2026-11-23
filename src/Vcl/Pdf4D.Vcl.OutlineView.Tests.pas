// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Vcl.OutlineView.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Tests.VclHost;

type
  [TestFixture]
  TPdf4DOutlineViewTests = class
  private
    FHost: TVclTestHost;

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
  end;

implementation

uses
  Winapi.Windows,
  Pdf4D.Tests.ViewerDocuments;

const
  ViewWidth = 800;
  ViewHeight = 600;
  OutlineWidth = 200;
  ItemCount = 3;

{ TPdf4DOutlineViewTests }

procedure TPdf4DOutlineViewTests.Setup;
begin
  FHost := TVclTestHost.Create(ViewWidth, ViewHeight);
  FHost.AddOutlineView(OutlineWidth);
end;

procedure TPdf4DOutlineViewTests.TearDown;
begin
  FreeAndNil(FHost);
end;

procedure TPdf4DOutlineViewTests.TestOutlineFillsAndNavigates;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Outlined), 'the document opens: ' + FHost.OpenErrorMessage);

  const Items = FHost.OutlineView.Items;
  Assert.AreEqual(ItemCount, Items.Count, 'one node per entry');
  Assert.AreEqual('Chapter 1', Items[0].Text);
  Assert.AreEqual('Section 1.1', Items[1].Text);
  Assert.AreEqual('Chapter 2', Items[2].Text);
  Assert.IsTrue(Items[1].Parent = Items[0], 'the section hangs under its chapter');
  Assert.IsTrue(Items[0].Parent = nil, 'a chapter is at the top');
  Assert.IsTrue(Items[2].Parent = nil, 'the second chapter is at the top');
  Assert.AreEqual(1, Integer(NativeInt(Items[1].Data)), 'the data of a node is the index of its entry');

  Items[1].Selected := True;
  Assert.AreEqual(1, FHost.Document.CurrentPage, 'selecting the section shows its page');

  Items[0].Selected := True;
  Assert.AreEqual(0, FHost.Document.CurrentPage, 'selecting the chapter shows its page');
end;

procedure TPdf4DOutlineViewTests.TestEnterNavigates;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Outlined), 'the document opens: ' + FHost.OpenErrorMessage);
  FHost.OutlineView.Items[2].Selected := True;
  FHost.Document.CurrentPage := 0;

  FHost.PressKeyOn(FHost.OutlineView, VK_RETURN);

  Assert.AreEqual(1, FHost.Document.CurrentPage, 'Enter shows the page of the selected item');
end;

procedure TPdf4DOutlineViewTests.TestOutlineClearsOnClose;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Outlined), 'the document opens: ' + FHost.OpenErrorMessage);
  Assert.AreEqual(ItemCount, FHost.OutlineView.Items.Count);

  FHost.Document.Close;

  Assert.AreEqual(0, FHost.OutlineView.Items.Count, 'the view is empty');
end;

procedure TPdf4DOutlineViewTests.TestDocumentThatIsOpenAlreadyFillsTheView;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Outlined), 'the document opens: ' + FHost.OpenErrorMessage);
  FHost.OutlineView.Document := nil;
  Assert.AreEqual(0, FHost.OutlineView.Items.Count, 'unlinking empties the view');

  FHost.OutlineView.Document := FHost.Document;

  Assert.AreEqual(ItemCount, FHost.OutlineView.Items.Count, 'the items of the open document are shown at once');
end;

end.
