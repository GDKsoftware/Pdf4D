// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Vcl.Actions.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.SysUtils,
  Vcl.ActnList,
  Vcl.StdCtrls,
  DUnitX.TestFramework,
  Pdf4D.Tests.VclHost,
  Pdf4D.Vcl.Actions;

type
  // Counts what a handler of an action is called
  TCallCounter = class
  private
    FCalls: Integer;

  public
    procedure Handle(Sender: TObject);

    property Calls: Integer read FCalls;
  end;

  [TestFixture]
  TPdf4DActionsTests = class
  private
    FHost: TVclTestHost;

    procedure OpenPages(const PageCount: Integer);
    procedure OpenInvoice;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestNavigationActionsEnableAndMove;

    [Test]
    procedure TestZoomActionsTargetPageView;

    [Test]
    procedure TestRotateActionsTurnTheView;

    [Test]
    procedure TestActionFindsFocusedPageView;

    [Test]
    procedure TestPrintActionDisabledWithoutPermission;

    [Test]
    procedure TestCopyActionNeedsSelection;

    [Test]
    procedure TestSearchActionShowsTheBar;

    [Test]
    procedure TestOnExecuteTakesThePlaceOfTheBehavior;

    [Test]
    procedure TestActionsLetGoOfFreedComponents;

    [Test]
    procedure TestStandardTexts;

    [Test]
    procedure TestDisabledActionsDoNotRun;

    [Test]
    procedure TestDisabledActionsLeaveTheirShortCut;

    [Test]
    procedure TestCopyShortCutBelongsToTheFocusedPageView;
  end;

implementation

uses
  System.Actions,
  System.UITypes,
  Vcl.Forms,
  Vcl.Menus,
  Winapi.Windows,
  Pdf4D.Viewer.Types,
  Pdf4D.Vcl.Document,
  Pdf4D.Vcl.PrintDialog,
  Pdf4D.Tests.ViewerDocuments;

const
  ViewWidth = 800;
  ViewHeight = 600;
  InvoiceNumber = '2024-0815';
  PageWidth = 612;
  PageHeight = 792;
  Tolerance = 0.0001;

{ TCallCounter }

procedure TCallCounter.Handle(Sender: TObject);
begin
  Inc(FCalls);
end;

{ TPdf4DActionsTests }

procedure TPdf4DActionsTests.Setup;
begin
  FHost := TVclTestHost.Create(ViewWidth, ViewHeight);
end;

procedure TPdf4DActionsTests.TearDown;
begin
  FreeAndNil(FHost);
end;

procedure TPdf4DActionsTests.OpenPages(const PageCount: Integer);
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Pages(PageCount, PageWidth, PageHeight, 0)), 'the document opens: ' + FHost.OpenErrorMessage);
end;

procedure TPdf4DActionsTests.OpenInvoice;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Invoice), 'the document opens: ' + FHost.OpenErrorMessage);
  Assert.IsTrue(FHost.WaitForPageText(0), 'the text of the first page arrives');
  Assert.IsTrue(FHost.WaitForVisibleTiles, 'the tiles arrive');
end;

procedure TPdf4DActionsTests.TestNavigationActionsEnableAndMove;
begin
  const First = TPdf4DFirstPageAction.Create(FHost.Form);
  const Prior = TPdf4DPriorPageAction.Create(FHost.Form);
  const Next = TPdf4DNextPageAction.Create(FHost.Form);
  const Last = TPdf4DLastPageAction.Create(FHost.Form);
  for var Action in TArray<TPdf4DDocumentAction>.Create(First, Prior, Next, Last) do
  begin
    Action.Document := FHost.Document;
    Action.Update;
    Assert.IsFalse(Action.Enabled, 'nothing is open yet: ' + Action.ClassName);
  end;

  OpenPages(3);
  for var Action in TArray<TPdf4DDocumentAction>.Create(First, Prior, Next, Last) do
  begin
    Action.Update;
  end;
  Assert.IsFalse(First.Enabled, 'on the first page');
  Assert.IsFalse(Prior.Enabled, 'on the first page');
  Assert.IsTrue(Next.Enabled);
  Assert.IsTrue(Last.Enabled);

  Assert.IsTrue(Next.Execute);
  Assert.AreEqual(1, FHost.Document.CurrentPage);
  Prior.Update;
  First.Update;
  Assert.IsTrue(Prior.Enabled);
  Assert.IsTrue(First.Enabled);

  Assert.IsTrue(Last.Execute);
  Assert.AreEqual(2, FHost.Document.CurrentPage);
  Next.Update;
  Last.Update;
  Assert.IsFalse(Next.Enabled, 'on the last page');
  Assert.IsFalse(Last.Enabled, 'on the last page');

  Assert.IsTrue(Prior.Execute);
  Assert.AreEqual(1, FHost.Document.CurrentPage);
  Assert.IsTrue(First.Execute);
  Assert.AreEqual(0, FHost.Document.CurrentPage);

  FHost.Document.Close;
  Next.Update;
  Assert.IsFalse(Next.Enabled, 'closed again');
end;

procedure TPdf4DActionsTests.TestZoomActionsTargetPageView;
begin
  OpenPages(2);
  const ZoomIn = TPdf4DZoomInAction.Create(FHost.Form);
  const ZoomOut = TPdf4DZoomOutAction.Create(FHost.Form);
  const FitWidth = TPdf4DZoomFitWidthAction.Create(FHost.Form);
  const FitPage = TPdf4DZoomFitPageAction.Create(FHost.Form);
  for var Action in TArray<TPdf4DPageViewAction>.Create(ZoomIn, ZoomOut, FitWidth, FitPage) do
  begin
    Action.PageView := FHost.PageView;
    Action.Update;
    Assert.IsTrue(Action.Enabled, Action.ClassName);
  end;

  FHost.PageView.Zoom := 1;
  Assert.IsTrue(ZoomIn.Execute);
  Assert.AreEqual(Double(1.25), Double(FHost.PageView.Zoom), Tolerance, 'one step up');
  Assert.IsTrue(ZoomOut.Execute);
  Assert.AreEqual(Double(1), Double(FHost.PageView.Zoom), Tolerance, 'one step down');

  Assert.IsTrue(FitPage.Execute);
  Assert.AreEqual(Ord(TPdfZoomMode.FitPage), Ord(FHost.PageView.ZoomMode));
  FitPage.Update;
  FitWidth.Update;
  Assert.IsTrue(FitPage.Checked);
  Assert.IsFalse(FitWidth.Checked);

  Assert.IsTrue(FitWidth.Execute);
  Assert.AreEqual(Ord(TPdfZoomMode.FitWidth), Ord(FHost.PageView.ZoomMode));
  FitPage.Update;
  FitWidth.Update;
  Assert.IsTrue(FitWidth.Checked);
  Assert.IsFalse(FitPage.Checked);
end;

procedure TPdf4DActionsTests.TestRotateActionsTurnTheView;
begin
  OpenPages(1);
  const Clockwise = TPdf4DRotateClockwiseAction.Create(FHost.Form);
  const Counterclockwise = TPdf4DRotateCounterclockwiseAction.Create(FHost.Form);
  Clockwise.PageView := FHost.PageView;
  Counterclockwise.PageView := FHost.PageView;

  Assert.IsTrue(Clockwise.Execute);
  Assert.AreEqual(90, FHost.PageView.ViewRotation);
  Assert.IsTrue(Counterclockwise.Execute);
  Assert.AreEqual(0, FHost.PageView.ViewRotation);
  Assert.IsTrue(Counterclockwise.Execute);
  Assert.AreEqual(270, FHost.PageView.ViewRotation);
end;

procedure TPdf4DActionsTests.TestActionFindsFocusedPageView;
begin
  OpenPages(2);
  const Other = TEdit.Create(FHost.Form);
  Other.Parent := FHost.Form;
  const ZoomIn = TPdf4DZoomInAction.Create(FHost.Form);
  Assert.IsNull(ZoomIn.PageView, 'no page view is set');
  FHost.PageView.Zoom := 1;

  Other.SetFocus;
  ZoomIn.Update;
  Assert.IsFalse(ZoomIn.Enabled, 'no page view has the focus');
  ZoomIn.Execute;
  Assert.AreEqual(Double(1), Double(FHost.PageView.Zoom), Tolerance, 'nothing was zoomed');

  FHost.PageView.SetFocus;
  ZoomIn.Update;
  Assert.IsTrue(ZoomIn.Enabled, 'the focused page view is used');
  Assert.IsTrue(ZoomIn.Execute);
  Assert.AreEqual(Double(1.25), Double(FHost.PageView.Zoom), Tolerance);
end;

procedure TPdf4DActionsTests.TestPrintActionDisabledWithoutPermission;
begin
  const Print = TPdf4DPrintAction.Create(FHost.Form);
  Print.Document := FHost.Document;
  Print.Update;
  Assert.IsFalse(Print.Enabled, 'nothing is open');

  Assert.IsTrue(FHost.Open(TVclTestDocuments.Restricted), FHost.OpenErrorMessage);
  Assert.IsFalse(FHost.Document.CanPrint, 'the document does not allow printing');
  Print.Update;
  Assert.IsFalse(Print.Enabled, 'printing is not allowed');

  FHost.Document.IgnorePermissions := True;
  Assert.IsTrue(FHost.Open(TVclTestDocuments.Restricted), FHost.OpenErrorMessage);
  Print.Update;
  Assert.IsTrue(Print.Enabled, 'the application ignores the permissions');

  FHost.Document.IgnorePermissions := False;
  OpenInvoice;
  Print.Update;
  Assert.IsTrue(Print.Enabled, 'printing is allowed');
end;

procedure TPdf4DActionsTests.TestCopyActionNeedsSelection;
begin
  OpenInvoice;
  const Copy = TPdf4DCopyAction.Create(FHost.Form);
  Copy.PageView := FHost.PageView;
  Copy.Update;
  Assert.IsFalse(Copy.Enabled, 'nothing is selected');

  const Center = FHost.CenterOfWord(0, InvoiceNumber, 1);
  FHost.Click(Center.X, Center.Y);
  Copy.Update;
  Assert.IsTrue(Copy.Enabled, 'a word is selected');

  Assert.IsTrue(Copy.Execute);
  Assert.AreEqual<Integer>(1, FHost.PageView.CopiedTexts.Count);
  Assert.AreEqual(InvoiceNumber, FHost.PageView.CopiedTexts[0]);

  Assert.IsTrue(FHost.Open(TVclTestDocuments.Restricted), FHost.OpenErrorMessage);
  Assert.IsTrue(FHost.WaitForPageText(0));
  Assert.IsTrue(FHost.WaitForVisibleTiles);
  const RestrictedCenter = FHost.CenterOfWord(0, InvoiceNumber, 1);
  FHost.Click(RestrictedCenter.X, RestrictedCenter.Y);
  Copy.Update;
  Assert.IsFalse(Copy.Enabled, 'the document does not allow copying');
end;

procedure TPdf4DActionsTests.TestSearchActionShowsTheBar;
begin
  const Bar = FHost.AddSearchBar;
  Bar.Visible := False;
  const Search = TPdf4DSearchAction.Create(FHost.Form);
  Search.SearchBar := Bar;
  Search.Update;
  Assert.IsFalse(Search.Enabled, 'nothing is open');

  OpenPages(1);
  Search.Update;
  Assert.IsTrue(Search.Enabled);

  Assert.IsTrue(Search.Execute);
  Assert.IsTrue(Bar.Visible, 'the bar is shown');
  Assert.IsTrue(Bar.EditQuery.Focused, 'the cursor is in the query field');
end;

procedure TPdf4DActionsTests.TestOnExecuteTakesThePlaceOfTheBehavior;
begin
  OpenPages(2);
  const Counter = TCallCounter.Create;
  try
    const Next = TPdf4DNextPageAction.Create(FHost.Form);
    Next.Document := FHost.Document;
    Next.OnExecute := Counter.Handle;

    Assert.IsTrue(Next.Execute);
    Assert.AreEqual(1, Counter.Calls);
    Assert.AreEqual(0, FHost.Document.CurrentPage, 'the handler decides');

    const Print = TPdf4DPrintAction.Create(FHost.Form);
    Print.Document := FHost.Document;
    Print.OnExecute := Counter.Handle;
    Assert.IsTrue(Print.Execute);
    Assert.AreEqual(2, Counter.Calls);
  finally
    Counter.Free;
  end;
end;

procedure TPdf4DActionsTests.TestActionsLetGoOfFreedComponents;
begin
  const Form = TForm.CreateNew(nil);
  try
    const Document = TPdf4DDocument.Create(Form);
    const View = TTestPageView.Create(Form);
    View.Parent := Form;
    const Next = TPdf4DNextPageAction.Create(Form);
    const ZoomIn = TPdf4DZoomInAction.Create(Form);
    Next.Document := Document;
    ZoomIn.PageView := View;

    Document.Free;
    View.Free;
    Assert.IsNull(Next.Document);
    Assert.IsNull(ZoomIn.PageView);
    Next.Execute;
    Next.Update;
    Assert.IsFalse(Next.Enabled);
  finally
    Form.Free;
  end;
end;

procedure TPdf4DActionsTests.TestStandardTexts;
begin
  const ZoomIn = TPdf4DZoomInAction.Create(FHost.Form);
  const ZoomOut = TPdf4DZoomOutAction.Create(FHost.Form);
  const Print = TPdf4DPrintAction.Create(FHost.Form);
  const Search = TPdf4DSearchAction.Create(FHost.Form);
  const Copy = TPdf4DCopyAction.Create(FHost.Form);
  const Prior = TPdf4DPriorPageAction.Create(FHost.Form);

  Assert.AreEqual(ShortCut(VK_OEM_PLUS, [ssCtrl]), ZoomIn.ShortCut);
  Assert.AreEqual(ShortCut(VK_OEM_MINUS, [ssCtrl]), ZoomOut.ShortCut);
  Assert.AreEqual(ShortCut(Ord('P'), [ssCtrl]), Print.ShortCut);
  Assert.AreEqual(ShortCut(Ord('F'), [ssCtrl]), Search.ShortCut);
  Assert.AreEqual(ShortCut(Ord('C'), [ssCtrl]), Copy.ShortCut);
  Assert.AreEqual(0, Integer(Prior.ShortCut), 'PageUp is only in the hint');
  Assert.IsTrue(Prior.Hint.Contains(ShortCutToText(ShortCut(VK_PRIOR, []))), Prior.Hint);
  for var Action in TArray<TCustomAction>.Create(ZoomIn, ZoomOut, Print, Search, Copy, Prior) do
  begin
    Assert.IsNotEmpty(Action.Caption, Action.ClassName);
    Assert.IsNotEmpty(Action.Hint, Action.ClassName);
  end;
end;

procedure TPdf4DActionsTests.TestDisabledActionsDoNotRun;
begin
  var Shown := 0;
  TPdf4DPrintDialog.ModalRunner :=
    function(Form: TPdf4DPrintDialogForm): TModalResult
    begin
      Inc(Shown);
      Result := mrCancel;
    end;
  try
    Assert.IsTrue(FHost.Open(TVclTestDocuments.Restricted), FHost.OpenErrorMessage);
    const Print = TPdf4DPrintAction.Create(FHost.Form);
    Print.Document := FHost.Document;
    const ZoomIn = TPdf4DZoomInAction.Create(FHost.Form);
    const Copy = TPdf4DCopyAction.Create(FHost.Form);
    Copy.PageView := FHost.PageView;
    FHost.Document.Close;
    const ZoomBefore = FHost.PageView.Zoom;

    Assert.IsFalse(Print.Execute, 'a document that may not be printed');
    Assert.AreEqual(0, Shown, 'no print dialog');
    Assert.IsFalse(ZoomIn.Execute, 'no open document in the page view');
    Assert.AreEqual(Double(ZoomBefore), Double(FHost.PageView.Zoom), Tolerance);
    Assert.IsFalse(Copy.Execute, 'nothing is selected');
    Assert.AreEqual<Integer>(0, FHost.PageView.CopiedTexts.Count);
  finally
    TPdf4DPrintDialog.ModalRunner := nil;
  end;
end;

// In an action list of the form: a disabled action lets the key through to the control that has the focus
procedure TPdf4DActionsTests.TestDisabledActionsLeaveTheirShortCut;
begin
  var Shown := 0;
  TPdf4DPrintDialog.ModalRunner :=
    function(Form: TPdf4DPrintDialogForm): TModalResult
    begin
      Inc(Shown);
      Result := mrCancel;
    end;
  try
    Assert.IsTrue(FHost.Open(TVclTestDocuments.Restricted), FHost.OpenErrorMessage);
    const Actions = TActionList.Create(FHost.Form);
    const Print = TPdf4DPrintAction.Create(FHost.Form);
    Print.ActionList := Actions;
    Print.Document := FHost.Document;
    const Copy = TPdf4DCopyAction.Create(FHost.Form);
    Copy.ActionList := Actions;
    Copy.PageView := FHost.PageView;
    const Edit = TEdit.Create(FHost.Form);
    Edit.Parent := FHost.Form;
    Edit.SetFocus;

    Assert.IsFalse(FHost.PressShortCutOn(Edit, Ord('P'), [ssCtrl]), 'Ctrl+P goes on to the edit');
    Assert.AreEqual(0, Shown, 'no print dialog');
    Assert.IsFalse(FHost.PressShortCutOn(Edit, Ord('C'), [ssCtrl]), 'Ctrl+C goes on to the edit');
  finally
    TPdf4DPrintDialog.ModalRunner := nil;
  end;
end;

procedure TPdf4DActionsTests.TestCopyShortCutBelongsToTheFocusedPageView;
begin
  OpenInvoice;
  Assert.IsTrue(FHost.WaitForPageText(0));
  Assert.IsTrue(FHost.WaitForVisibleTiles);
  const Actions = TActionList.Create(FHost.Form);
  const Copy = TPdf4DCopyAction.Create(FHost.Form);
  Copy.ActionList := Actions;
  Copy.PageView := FHost.PageView;
  const Edit = TEdit.Create(FHost.Form);
  Edit.Parent := FHost.Form;

  const Center = FHost.CenterOfWord(0, InvoiceNumber, 1);
  FHost.Click(Center.X, Center.Y);
  Edit.SetFocus;
  Copy.Update;
  Assert.IsTrue(Copy.Enabled, 'a word is selected');

  Assert.IsFalse(FHost.PressShortCutOn(Edit, Ord('C'), [ssCtrl]), 'Ctrl+C in the edit goes on to the edit');
  Assert.AreEqual<Integer>(0, FHost.PageView.CopiedTexts.Count, 'the selection of the page view is not copied');

  FHost.PageView.SetFocus;
  Assert.IsTrue(FHost.PressShortCutOn(FHost.PageView, Ord('C'), [ssCtrl]), 'the action takes Ctrl+C in the page view');
  Assert.AreEqual<Integer>(1, FHost.PageView.CopiedTexts.Count, 'copied once');
end;

end.
