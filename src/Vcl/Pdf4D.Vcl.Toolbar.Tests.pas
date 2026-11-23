// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Vcl.Toolbar.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.SysUtils,
  Vcl.StdCtrls,
  DUnitX.TestFramework,
  Pdf4D.Tests.VclHost,
  Pdf4D.Vcl.Toolbar;

type
  [TestFixture]
  TPdf4DToolbarTests = class
  private
    FHost: TVclTestHost;
    FToolbar: TPdf4DToolbar;

    procedure OpenPages(const PageCount: Integer);
    // Types the text in the page number field and presses Enter
    procedure EnterPageNumber(const Text: string);
    // Chooses an item of the zoom list as a user does
    procedure ChooseZoom(const Item: string);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestToolbarPageNumber;

    [Test]
    procedure TestToolbarPageNumberFollowsTheDocument;

    [Test]
    procedure TestToolbarZoomCombo;

    [Test]
    procedure TestToolbarZoomComboTypedValue;

    [Test]
    procedure TestToolbarButtonsOption;

    [Test]
    procedure TestToolbarButtonsRunTheActions;

    [Test]
    procedure TestToolbarButtonsFollowTheDocument;

    [Test]
    procedure TestToolbarIcons;

    [Test]
    procedure TestToolbarKeepsAnImageListOfTheApplication;

    [Test]
    procedure TestToolbarSearchButton;

    [Test]
    procedure TestToolbarLetsGoOfFreedComponents;
  end;

implementation

uses
  Vcl.ComCtrls,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.ImgList,
  Winapi.Messages,
  Winapi.Windows,
  Pdf4D.Viewer.Types,
  Pdf4D.Tests.ViewerDocuments;

const
  ViewWidth = 800;
  ViewHeight = 600;
  PageWidth = 612;
  PageHeight = 792;
  Tolerance = 0.0001;
  IconCount = 13;
  EnterCharacter = 13;

{ TPdf4DToolbarTests }

procedure TPdf4DToolbarTests.Setup;
begin
  FHost := TVclTestHost.Create(ViewWidth, ViewHeight);
  FHost.AddSearchBar;
  FToolbar := FHost.AddToolbar;
end;

procedure TPdf4DToolbarTests.TearDown;
begin
  FreeAndNil(FHost);
end;

procedure TPdf4DToolbarTests.OpenPages(const PageCount: Integer);
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Pages(PageCount, PageWidth, PageHeight, 0)), 'the document opens: ' + FHost.OpenErrorMessage);
  FHost.Pump(1);
end;

procedure TPdf4DToolbarTests.EnterPageNumber(const Text: string);
begin
  FToolbar.EditPage.Text := Text;
  FToolbar.EditPage.Perform(WM_CHAR, EnterCharacter, 0);
  FHost.Pump(1);
end;

procedure TPdf4DToolbarTests.ChooseZoom(const Item: string);
begin
  const Index = FToolbar.ComboZoom.Items.IndexOf(Item);
  Assert.IsTrue(Index >= 0, 'the list has ' + Item);
  FToolbar.ComboZoom.ItemIndex := Index;
  FToolbar.ComboZoom.Perform(CN_COMMAND, MakeWParam(0, CBN_SELCHANGE), FToolbar.ComboZoom.Handle);
  FHost.Pump(1);
end;

procedure TPdf4DToolbarTests.TestToolbarPageNumber;
begin
  OpenPages(3);
  Assert.AreEqual('1', FToolbar.EditPage.Text);
  Assert.AreEqual(' / 3', FToolbar.LabelPages.Caption);

  EnterPageNumber('2');
  Assert.AreEqual(1, FHost.Document.CurrentPage, 'Enter goes to the page');
  Assert.AreEqual('2', FToolbar.EditPage.Text);

  EnterPageNumber('3 ');
  Assert.AreEqual(2, FHost.Document.CurrentPage, 'spaces do not matter');

  EnterPageNumber('abc');
  Assert.AreEqual(2, FHost.Document.CurrentPage, 'not a number');
  Assert.AreEqual('3', FToolbar.EditPage.Text, 'the text goes back');

  EnterPageNumber('4');
  Assert.AreEqual(2, FHost.Document.CurrentPage, 'after the last page');
  Assert.AreEqual('3', FToolbar.EditPage.Text, 'the text goes back');

  EnterPageNumber('0');
  Assert.AreEqual(2, FHost.Document.CurrentPage, 'before the first page');
  Assert.AreEqual('3', FToolbar.EditPage.Text, 'the text goes back');

  EnterPageNumber('');
  Assert.AreEqual('3', FToolbar.EditPage.Text, 'empty goes back');
end;

procedure TPdf4DToolbarTests.TestToolbarPageNumberFollowsTheDocument;
begin
  Assert.IsFalse(FToolbar.EditPage.Enabled, 'nothing is open');
  Assert.AreEqual('', FToolbar.EditPage.Text);

  OpenPages(5);
  Assert.IsTrue(FToolbar.EditPage.Enabled);
  FHost.Document.CurrentPage := 3;
  Assert.AreEqual('4', FToolbar.EditPage.Text, 'the page of the document shows');
  Assert.AreEqual(' / 5', FToolbar.LabelPages.Caption);

  FHost.Document.Close;
  Assert.IsFalse(FToolbar.EditPage.Enabled, 'closed again');
  Assert.AreEqual('', FToolbar.EditPage.Text);
end;

procedure TPdf4DToolbarTests.TestToolbarZoomCombo;
begin
  OpenPages(2);
  Assert.AreEqual('Fit width', FToolbar.ComboZoom.Text, 'the default zoom mode');
  Assert.IsTrue(FToolbar.ComboZoom.Enabled);

  ChooseZoom('200%');
  Assert.AreEqual(Double(2), Double(FHost.PageView.Zoom), Tolerance);
  Assert.AreEqual(Ord(TPdfZoomMode.Factor), Ord(FHost.PageView.ZoomMode));

  ChooseZoom('Fit page');
  Assert.AreEqual(Ord(TPdfZoomMode.FitPage), Ord(FHost.PageView.ZoomMode));
  ChooseZoom('Fit width');
  Assert.AreEqual(Ord(TPdfZoomMode.FitWidth), Ord(FHost.PageView.ZoomMode));

  FHost.PageView.Zoom := 1;
  Assert.AreEqual('100%', FToolbar.ComboZoom.Text, 'a zoom of the page view shows in the combo');
  FHost.PageView.ZoomIn;
  Assert.AreEqual('125%', FToolbar.ComboZoom.Text);
  FHost.PageView.Zoom := 1.33;
  Assert.AreEqual('133%', FToolbar.ComboZoom.Text, 'a zoom between the steps shows as it is');
end;

procedure TPdf4DToolbarTests.TestToolbarZoomComboTypedValue;
begin
  OpenPages(2);

  FToolbar.ComboZoom.Text := '150';
  FToolbar.ComboZoom.Perform(WM_CHAR, EnterCharacter, 0);
  Assert.AreEqual(Double(1.5), Double(FHost.PageView.Zoom), Tolerance, 'a number without a percent sign');
  Assert.AreEqual('150%', FToolbar.ComboZoom.Text);

  FToolbar.ComboZoom.Text := 'wide';
  FToolbar.ComboZoom.Perform(WM_CHAR, EnterCharacter, 0);
  Assert.AreEqual(Double(1.5), Double(FHost.PageView.Zoom), Tolerance, 'not a number');
  Assert.AreEqual('150%', FToolbar.ComboZoom.Text, 'the text goes back');
end;

procedure TPdf4DToolbarTests.TestToolbarButtonsOption;
begin
  Assert.IsTrue(FToolbar.Buttons = [Low(TPdf4DToolbarButton)..High(TPdf4DToolbarButton)], 'all by default');
  Assert.IsNotNull(FToolbar.ButtonFirst);
  Assert.IsNotNull(FToolbar.ButtonLast);
  Assert.IsNotNull(FToolbar.EditPage);
  Assert.IsNotNull(FToolbar.ComboZoom);
  Assert.IsNotNull(FToolbar.ButtonZoomIn);
  Assert.IsNotNull(FToolbar.ButtonRotateClockwise);
  Assert.IsNotNull(FToolbar.ButtonSearch);
  Assert.IsNotNull(FToolbar.ButtonPrint);
  const Layout = Format('first %d, prior %d, next %d, last %d, page %d, zoom list %d, zoom in %d',
                        [FToolbar.ButtonFirst.Left, FToolbar.ButtonPrior.Left, FToolbar.ButtonNext.Left, FToolbar.ButtonLast.Left,
                         FToolbar.EditPage.Left, FToolbar.ComboZoom.Left, FToolbar.ButtonZoomIn.Left]);
  Assert.IsTrue(FToolbar.ButtonPrior.Left > FToolbar.ButtonFirst.Left, 'in order: ' + Layout);
  Assert.IsTrue(FToolbar.ButtonNext.Left > FToolbar.ButtonPrior.Left, 'in order: ' + Layout);
  Assert.IsTrue(FToolbar.ButtonLast.Left > FToolbar.ButtonNext.Left, 'in order: ' + Layout);
  Assert.IsTrue(FToolbar.EditPage.Left > FToolbar.ButtonLast.Left, 'the page number is after the navigation: ' + Layout);
  Assert.IsTrue(FToolbar.ComboZoom.Left > FToolbar.EditPage.Left, 'in order: ' + Layout);
  Assert.IsTrue(FToolbar.ButtonZoomIn.Left > FToolbar.ComboZoom.Left, 'zoom in is after the list: ' + Layout);

  FToolbar.Buttons := [TPdf4DToolbarButton.Navigation];
  Assert.IsNotNull(FToolbar.ButtonFirst);
  Assert.IsNotNull(FToolbar.ButtonPrior);
  Assert.IsNotNull(FToolbar.ButtonNext);
  Assert.IsNotNull(FToolbar.ButtonLast);
  Assert.IsNull(FToolbar.EditPage);
  Assert.IsNull(FToolbar.LabelPages);
  Assert.IsNull(FToolbar.ComboZoom);
  Assert.IsNull(FToolbar.ButtonZoomIn);
  Assert.IsNull(FToolbar.ButtonZoomOut);
  Assert.IsNull(FToolbar.ButtonRotateClockwise);
  Assert.IsNull(FToolbar.ButtonRotateCounterclockwise);
  Assert.IsNull(FToolbar.ButtonSearch);
  Assert.IsNull(FToolbar.ButtonPrint);
  Assert.AreEqual(4, FToolbar.ButtonCount, 'only the four buttons of the navigation');

  FToolbar.Buttons := [TPdf4DToolbarButton.Zoom, TPdf4DToolbarButton.Print];
  Assert.IsNull(FToolbar.ButtonFirst);
  Assert.IsNotNull(FToolbar.ComboZoom);
  Assert.IsNotNull(FToolbar.ButtonPrint);

  FToolbar.Buttons := [];
  Assert.AreEqual(0, FToolbar.ButtonCount);
  Assert.IsNull(FToolbar.ComboZoom);

  FToolbar.Buttons := [Low(TPdf4DToolbarButton)..High(TPdf4DToolbarButton)];
  Assert.IsNotNull(FToolbar.ButtonFirst);
  Assert.IsNotNull(FToolbar.EditPage);
end;

procedure TPdf4DToolbarTests.TestToolbarButtonsRunTheActions;
begin
  OpenPages(3);
  FHost.PageView.Zoom := 1;

  FToolbar.ButtonNext.Click;
  Assert.AreEqual(1, FHost.Document.CurrentPage);
  FToolbar.ButtonLast.Click;
  Assert.AreEqual(2, FHost.Document.CurrentPage);
  FToolbar.ButtonFirst.Click;
  Assert.AreEqual(0, FHost.Document.CurrentPage);

  FToolbar.ButtonZoomIn.Click;
  Assert.AreEqual(Double(1.25), Double(FHost.PageView.Zoom), Tolerance);
  FToolbar.ButtonZoomOut.Click;
  Assert.AreEqual(Double(1), Double(FHost.PageView.Zoom), Tolerance);

  FToolbar.ButtonRotateClockwise.Click;
  Assert.AreEqual(90, FHost.PageView.ViewRotation);
  FToolbar.ButtonRotateCounterclockwise.Click;
  Assert.AreEqual(0, FHost.PageView.ViewRotation);
end;

procedure TPdf4DToolbarTests.TestToolbarButtonsFollowTheDocument;
begin
  Assert.IsFalse(FToolbar.ButtonNext.Enabled, 'nothing is open');
  Assert.IsFalse(FToolbar.ButtonZoomIn.Enabled, 'nothing is open');
  Assert.IsFalse(FToolbar.ButtonPrint.Enabled, 'nothing is open');
  Assert.IsFalse(FToolbar.ButtonSearch.Enabled, 'nothing is open');

  OpenPages(2);
  Assert.IsFalse(FToolbar.ButtonPrior.Enabled, 'on the first page');
  Assert.IsTrue(FToolbar.ButtonNext.Enabled);
  Assert.IsTrue(FToolbar.ButtonZoomIn.Enabled);
  Assert.IsTrue(FToolbar.ButtonRotateClockwise.Enabled);
  Assert.IsTrue(FToolbar.ButtonPrint.Enabled);
  Assert.IsTrue(FToolbar.ButtonSearch.Enabled);

  FHost.Document.CurrentPage := 1;
  Assert.IsTrue(FToolbar.ButtonPrior.Enabled);
  Assert.IsFalse(FToolbar.ButtonNext.Enabled, 'on the last page');

  Assert.IsTrue(FHost.Open(TVclTestDocuments.Restricted), FHost.OpenErrorMessage);
  Assert.IsFalse(FToolbar.ButtonPrint.Enabled, 'printing is not allowed');
end;

procedure TPdf4DToolbarTests.TestToolbarIcons;
begin
  Assert.IsNotNull(FToolbar.Images, 'the toolbar made an image list');
  Assert.AreEqual(IconCount, FToolbar.Images.Count);
  Assert.AreEqual(16, FToolbar.Images.Width);
  for var Button in [FToolbar.ButtonFirst, FToolbar.ButtonPrior, FToolbar.ButtonNext, FToolbar.ButtonLast, FToolbar.ButtonZoomIn,
                     FToolbar.ButtonZoomOut, FToolbar.ButtonRotateClockwise, FToolbar.ButtonRotateCounterclockwise,
                     FToolbar.ButtonSearch, FToolbar.ButtonPrint] do
  begin
    Assert.IsTrue(Button.ImageIndex >= 0, 'has an icon: ' + Button.Caption);
    Assert.IsTrue(Button.ImageIndex < FToolbar.Images.Count, 'in the list: ' + Button.Caption);
  end;
  Assert.IsNotEmpty(FToolbar.ButtonNext.Hint);
end;

procedure TPdf4DToolbarTests.TestToolbarKeepsAnImageListOfTheApplication;
begin
  // A form that is not shown has no window yet, the state in which a form is loaded
  const Form = TForm.CreateNew(nil);
  try
    const Own = TImageList.Create(Form);
    const Toolbar = TPdf4DToolbar.Create(Form);
    Toolbar.Parent := Form;
    Toolbar.Images := Own;
    Toolbar.HandleNeeded;

    Assert.IsTrue(Toolbar.Images = Own, 'the list of the application stays');
    Assert.IsNotNull(Toolbar.ButtonNext, 'the buttons are made all the same');
    Assert.AreEqual(-1, Toolbar.ButtonNext.ImageIndex, 'the icons of the toolbar are not in that list');
    Assert.IsNotEmpty(Toolbar.ButtonNext.Caption);
  finally
    Form.Free;
  end;
end;

procedure TPdf4DToolbarTests.TestToolbarSearchButton;
begin
  OpenPages(1);
  FHost.SearchBar.Visible := False;

  FToolbar.ButtonSearch.Click;

  Assert.IsTrue(FHost.SearchBar.Visible, 'the bar is shown');
  Assert.IsTrue(FHost.SearchBar.EditQuery.Focused, 'the cursor is in the query field');
end;

procedure TPdf4DToolbarTests.TestToolbarLetsGoOfFreedComponents;
begin
  OpenPages(2);
  const Probe = TZoomListenerProbe.Create(FHost.PageView);
  try
    FHost.SearchBar.Free;
    FHost.PageView.Free;
    // The toolbar and the probe let go of the page view while it is freed: its list of listeners is still there then
    Assert.IsTrue(Probe.ListenerCountAtRemoval >= 1, 'the zoom listeners outlive the free notifications');
  finally
    Probe.Free;
  end;
  FHost.Document.Free;
  Assert.IsNull(FToolbar.SearchBar);
  Assert.IsNull(FToolbar.PageView);
  Assert.IsNull(FToolbar.Document);
  Assert.IsFalse(FToolbar.ButtonNext.Enabled);
end;

end.
