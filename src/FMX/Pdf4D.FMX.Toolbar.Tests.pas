// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.FMX.Toolbar.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.SysUtils,
  FMX.StdCtrls,
  DUnitX.TestFramework,
  Pdf4D.Tests.FmxHost,
  Pdf4D.FMX.Toolbar;

type
  // Gives the tests the click of a button, as a press of the mouse does
  TButtonCracker = class(TSpeedButton);

  [TestFixture]
  TPdf4DToolbarTests = class
  private
    FHost: TFmxTestHost;
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
    procedure TestPageNumberEditKeepsArrowKeys;

    [Test]
    procedure TestToolbarZoomCombo;

    [Test]
    procedure TestToolbarButtonsOption;

    [Test]
    procedure TestToolbarButtonsRunTheActions;

    [Test]
    procedure TestToolbarButtonsFollowTheDocument;

    [Test]
    procedure TestToolbarIcons;

    [Test]
    procedure TestToolbarButtonsShowTheirIcons;

    [Test]
    procedure TestToolbarSearchButton;

    [Test]
    procedure TestToolbarLetsGoOfFreedComponents;

    [Test]
    procedure TestToolbarRowKeepsItsOrderWithoutOverlap;

    [Test]
    procedure TestToolbarDoesNotTakeShortCutsOfTheForm;
  end;

implementation

uses
  System.Math,
  System.Types,
  System.UITypes,
  FMX.Controls,
  FMX.Graphics,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.Commands,
  Pdf4D.Tests.ViewerDocuments,
  Pdf4D.Tests.RestrictedDocument;

const
  ViewWidth = 800;
  ViewHeight = 600;
  PageWidth = 612;
  PageHeight = 792;
  Tolerance = 0.0001;
  IconCount = 13;
  // How much a pixel may differ from the background before it counts as drawn
  DrawnDifference = 40;
  MinimumDrawnPixels = 8;

{ TPdf4DToolbarTests }

procedure TPdf4DToolbarTests.Setup;
begin
  FHost := TFmxTestHost.Create(ViewWidth, ViewHeight);
  FHost.AddSearchBar;
  FHost.AddPageView;
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
  FHost.PressKeyOn(FToolbar.EditPage, vkReturn, [], #13);
  FHost.Pump(1);
end;

procedure TPdf4DToolbarTests.ChooseZoom(const Item: string);
begin
  const Index = FToolbar.ComboZoom.Items.IndexOf(Item);
  Assert.IsTrue(Index >= 0, 'the list has ' + Item);
  FToolbar.ComboZoom.ItemIndex := Index;
  FHost.Pump(1);
end;

procedure TPdf4DToolbarTests.TestToolbarPageNumber;
begin
  OpenPages(3);
  Assert.AreEqual('1', FToolbar.EditPage.Text);
  Assert.AreEqual(' / 3', FToolbar.LabelPages.Text);

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
  Assert.AreEqual(' / 5', FToolbar.LabelPages.Text);

  FHost.Document.Close;
  Assert.IsFalse(FToolbar.EditPage.Enabled, 'closed again');
  Assert.AreEqual('', FToolbar.EditPage.Text);
end;

// With the focus in the page number the arrow keys move the cursor of the field; the page view does not scroll
procedure TPdf4DToolbarTests.TestPageNumberEditKeepsArrowKeys;
begin
  OpenPages(5);
  FHost.PageView.Zoom := 2;
  FHost.Pump(1);
  Assert.IsTrue(FHost.PageView.VScrollBar.Visible, 'the page view can scroll');
  FToolbar.EditPage.Text := '12';
  FHost.PressKeyOn(FToolbar.EditPage, vkEnd);
  Assert.AreEqual(2, FToolbar.EditPage.CaretPosition, 'the cursor is at the end');
  const ScrollBefore = FHost.PageView.VScrollBar.Value;

  FHost.PressKey(vkLeft);
  Assert.AreEqual(1, FToolbar.EditPage.CaretPosition, 'Left moves the cursor of the field');
  FHost.PressKey(vkHome);
  Assert.AreEqual(0, FToolbar.EditPage.CaretPosition, 'Home moves the cursor of the field');
  FHost.PressKey(vkRight);
  Assert.AreEqual(1, FToolbar.EditPage.CaretPosition, 'Right moves the cursor of the field');
  FHost.PressKey(vkDown);
  FHost.PressKey(vkNext);
  FHost.PressKey(vkEnd);
  FHost.Pump(1);
  Assert.AreEqual(Double(ScrollBefore), Double(FHost.PageView.VScrollBar.Value), Tolerance, 'the page view did not scroll');

  // The same keys do scroll the page view when it has the focus
  FHost.PressKeyOn(FHost.PageView, vkNext);
  FHost.Pump(1);
  Assert.IsTrue(FHost.PageView.VScrollBar.Value > ScrollBefore, 'PageDown scrolls the page view');
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

  const StepCount: Integer = Length(TPdfZoomText.Items);
  FHost.PageView.Zoom := 1.33;
  Assert.AreEqual('133%', FToolbar.ComboZoom.Text, 'a zoom between the steps shows as it is');
  Assert.AreEqual(StepCount + 1, FToolbar.ComboZoom.Items.Count, 'as an extra item');
  FHost.PageView.Zoom := 1.5;
  Assert.AreEqual('150%', FToolbar.ComboZoom.Text);
  Assert.AreEqual(StepCount, FToolbar.ComboZoom.Items.Count, 'the extra item went');
  Assert.AreEqual(Double(1.5), Double(FHost.PageView.Zoom), Tolerance, 'showing the zoom did not change it');
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
  const Layout = Format('first %.0f, prior %.0f, next %.0f, last %.0f, page %.0f, zoom list %.0f, zoom in %.0f',
                        [FToolbar.ButtonFirst.Position.X, FToolbar.ButtonPrior.Position.X, FToolbar.ButtonNext.Position.X,
                         FToolbar.ButtonLast.Position.X, FToolbar.EditPage.Position.X, FToolbar.ComboZoom.Position.X,
                         FToolbar.ButtonZoomIn.Position.X]);
  Assert.IsTrue(FToolbar.ButtonPrior.Position.X > FToolbar.ButtonFirst.Position.X, 'in order: ' + Layout);
  Assert.IsTrue(FToolbar.ButtonNext.Position.X > FToolbar.ButtonPrior.Position.X, 'in order: ' + Layout);
  Assert.IsTrue(FToolbar.ButtonLast.Position.X > FToolbar.ButtonNext.Position.X, 'in order: ' + Layout);
  Assert.IsTrue(FToolbar.EditPage.Position.X > FToolbar.ButtonLast.Position.X, 'the page number is after the navigation: ' + Layout);
  Assert.IsTrue(FToolbar.ComboZoom.Position.X > FToolbar.EditPage.Position.X, 'in order: ' + Layout);
  Assert.IsTrue(FToolbar.ButtonZoomIn.Position.X > FToolbar.ComboZoom.Position.X, 'zoom in is after the list: ' + Layout);

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
  Assert.AreEqual(4, FToolbar.RowCount, 'only the four buttons of the navigation');

  FToolbar.Buttons := [TPdf4DToolbarButton.Zoom, TPdf4DToolbarButton.Print];
  Assert.IsNull(FToolbar.ButtonFirst);
  Assert.IsNotNull(FToolbar.ComboZoom);
  Assert.IsNotNull(FToolbar.ButtonPrint);

  FToolbar.Buttons := [];
  Assert.AreEqual(0, FToolbar.RowCount);
  Assert.IsNull(FToolbar.ComboZoom);

  FToolbar.Buttons := [Low(TPdf4DToolbarButton)..High(TPdf4DToolbarButton)];
  Assert.IsNotNull(FToolbar.ButtonFirst);
  Assert.IsNotNull(FToolbar.EditPage);
end;

procedure TPdf4DToolbarTests.TestToolbarButtonsRunTheActions;
begin
  OpenPages(3);
  FHost.PageView.Zoom := 1;

  TButtonCracker(FToolbar.ButtonNext).Click;
  Assert.AreEqual(1, FHost.Document.CurrentPage);
  TButtonCracker(FToolbar.ButtonLast).Click;
  Assert.AreEqual(2, FHost.Document.CurrentPage);
  TButtonCracker(FToolbar.ButtonFirst).Click;
  Assert.AreEqual(0, FHost.Document.CurrentPage);

  TButtonCracker(FToolbar.ButtonZoomIn).Click;
  Assert.AreEqual(Double(1.25), Double(FHost.PageView.Zoom), Tolerance);
  TButtonCracker(FToolbar.ButtonZoomOut).Click;
  Assert.AreEqual(Double(1), Double(FHost.PageView.Zoom), Tolerance);

  TButtonCracker(FToolbar.ButtonRotateClockwise).Click;
  Assert.AreEqual(90, FHost.PageView.ViewRotation);
  TButtonCracker(FToolbar.ButtonRotateCounterclockwise).Click;
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

  Assert.IsTrue(FHost.Open(TRestrictedDocument.Build), FHost.OpenErrorMessage);
  Assert.IsFalse(FToolbar.ButtonPrint.Enabled, 'printing is not allowed');
end;

procedure TPdf4DToolbarTests.TestToolbarIcons;
begin
  Assert.IsNotNull(FToolbar.Icons, 'the toolbar made an image list');
  Assert.AreEqual(IconCount, FToolbar.Icons.Count);
  for var Button in [FToolbar.ButtonFirst, FToolbar.ButtonPrior, FToolbar.ButtonNext, FToolbar.ButtonLast, FToolbar.ButtonZoomIn,
                     FToolbar.ButtonZoomOut, FToolbar.ButtonRotateClockwise, FToolbar.ButtonRotateCounterclockwise,
                     FToolbar.ButtonSearch, FToolbar.ButtonPrint] do
  begin
    Assert.IsTrue(Button.Images = FToolbar.Icons, 'uses the icons of the toolbar: ' + Button.Name);
    Assert.IsTrue(Button.ImageIndex >= 0, 'has an icon: ' + Button.Name);
    Assert.IsTrue(Button.ImageIndex < FToolbar.Icons.Count, 'in the list: ' + Button.Name);
    Assert.IsNotEmpty(Button.Hint, Button.Name);
  end;
end;

// The icons come out of the resource and are drawn on the button, also after the state of the button changed
procedure TPdf4DToolbarTests.TestToolbarButtonsShowTheirIcons;
begin
  OpenPages(3);
  FHost.Pump(1);
  for var Button in [FToolbar.ButtonNext, FToolbar.ButtonZoomIn, FToolbar.ButtonSearch] do
  begin
    const Bitmap = TFmxTestHost.SnapshotOf(Button);
    try
      const Background = TFmxTestHost.PixelAt(Bitmap, 1, 1);
      var Drawn := 0;
      for var Y := 0 to Bitmap.Height - 1 do
      begin
        for var X := 0 to Bitmap.Width - 1 do
        begin
          const Pixel = TAlphaColorRec(TFmxTestHost.PixelAt(Bitmap, X, Y));
          const Reference = TAlphaColorRec(Background);
          if Max(Abs(Pixel.R - Reference.R), Max(Abs(Pixel.G - Reference.G), Abs(Pixel.B - Reference.B))) >= DrawnDifference then
          begin
            Inc(Drawn);
          end;
        end;
      end;
      Assert.IsTrue(Drawn >= MinimumDrawnPixels, Format('%s draws its icon (%d pixels differ from the background)', [Button.Name, Drawn]));
    finally
      Bitmap.Free;
    end;
  end;
end;

procedure TPdf4DToolbarTests.TestToolbarSearchButton;
begin
  OpenPages(1);
  FHost.SearchBar.Visible := False;

  TButtonCracker(FToolbar.ButtonSearch).Click;

  Assert.IsTrue(FHost.SearchBar.Visible, 'the bar is shown');
  Assert.IsTrue(FHost.SearchBar.EditQuery.IsFocused, 'the cursor is in the query field');
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

procedure TPdf4DToolbarTests.TestToolbarRowKeepsItsOrderWithoutOverlap;
begin
  const Row: TArray<TControl> = [FToolbar.ButtonFirst, FToolbar.ButtonPrior, FToolbar.ButtonNext, FToolbar.ButtonLast, FToolbar.EditPage,
                                 FToolbar.LabelPages, FToolbar.ButtonZoomOut, FToolbar.ComboZoom, FToolbar.ButtonZoomIn,
                                 FToolbar.ButtonRotateCounterclockwise, FToolbar.ButtonRotateClockwise, FToolbar.ButtonSearch,
                                 FToolbar.ButtonPrint];
  for var Index := 1 to High(Row) do
  begin
    const Before = Row[Index - 1];
    const After = Row[Index];
    Assert.IsTrue(Before.Position.X + Before.Width <= After.Position.X,
                  Format('%s (%.0f..%.0f) comes before %s (%.0f)', [Before.ClassName, Before.Position.X, Before.Position.X + Before.Width,
                                                                    After.ClassName, After.Position.X]));
    Assert.IsTrue((After.Position.Y >= 0) and (After.Position.Y + After.Height <= FToolbar.Height), 'inside the toolbar: ' + After.ClassName);
  end;
end;

// The actions of the toolbar are its own: their shortcuts are not taken from the form, which has its own actions for those
procedure TPdf4DToolbarTests.TestToolbarDoesNotTakeShortCutsOfTheForm;
begin
  OpenPages(1);
  FHost.SearchBar.Visible := False;
  FHost.PageView.SetFocus;

  FHost.PressKey(vkF, [ssCtrl]);

  Assert.IsFalse(FHost.SearchBar.Visible, 'Ctrl+F is not an action of the form');
end;

end.
