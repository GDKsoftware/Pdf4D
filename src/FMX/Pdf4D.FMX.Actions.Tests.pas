// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.FMX.Actions.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Tests.FmxHost,
  Pdf4D.FMX.Actions;

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
    FHost: TFmxTestHost;

    procedure OpenPages(const PageCount: Integer);
    procedure OpenInvoice;
    // Selects the invoice number by a click on it
    procedure SelectInvoiceNumber;

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

    [Test]
    procedure TestSearchShortCutNeedsTheFocusScope;
  end;

implementation

uses
  System.Types,
  System.UITypes,
  FMX.ActnList,
  FMX.Controls,
  FMX.Edit,
  FMX.Forms,
  Pdf4D.Viewer.Types,
  Pdf4D.FMX.Document,
  Pdf4D.Tests.ViewerDocuments,
  Pdf4D.Tests.RestrictedDocument;

const
  ViewWidth = 800;
  ViewHeight = 600;
  InvoiceNumber = '2024-0815';
  PageWidth = 612;
  PageHeight = 792;
  Tolerance = 0.0001;
  // The flags of a shortcut: the key code is in the low byte
  CtrlFlag = $4000;
  PlusKeyCode = $BB;
  MinusKeyCode = $BD;

{ TCallCounter }

procedure TCallCounter.Handle(Sender: TObject);
begin
  Inc(FCalls);
end;

{ TPdf4DActionsTests }

procedure TPdf4DActionsTests.Setup;
begin
  FHost := TFmxTestHost.Create(ViewWidth, ViewHeight);
  FHost.AddPageView;
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

procedure TPdf4DActionsTests.SelectInvoiceNumber;
begin
  FHost.Click(FHost.CenterOfWord(0, InvoiceNumber, 1));
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

  Assert.IsTrue(FHost.Open(TRestrictedDocument.Build), FHost.OpenErrorMessage);
  Assert.IsFalse(FHost.Document.CanPrint, 'the document does not allow printing');
  Print.Update;
  Assert.IsFalse(Print.Enabled, 'printing is not allowed');

  FHost.Document.IgnorePermissions := True;
  Assert.IsTrue(FHost.Open(TRestrictedDocument.Build), FHost.OpenErrorMessage);
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

  SelectInvoiceNumber;
  Copy.Update;
  Assert.IsTrue(Copy.Enabled, 'a word is selected');

  Assert.IsTrue(Copy.Execute);
  Assert.AreEqual<Integer>(1, FHost.PageView.CopiedTexts.Count);
  Assert.AreEqual(InvoiceNumber, FHost.PageView.CopiedTexts[0]);

  Assert.IsTrue(FHost.Open(TRestrictedDocument.Build), FHost.OpenErrorMessage);
  Assert.IsTrue(FHost.WaitForPageText(0));
  Assert.IsTrue(FHost.WaitForVisibleTiles);
  SelectInvoiceNumber;
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
  Assert.IsTrue(Bar.EditQuery.IsFocused, 'the cursor is in the query field');
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

  Assert.AreEqual(CtrlFlag or PlusKeyCode, Integer(ZoomIn.ShortCut), 'Ctrl and the plus key');
  Assert.AreEqual(CtrlFlag or MinusKeyCode, Integer(ZoomOut.ShortCut), 'Ctrl and the minus key');
  Assert.AreEqual(CtrlFlag or Ord('P'), Integer(Print.ShortCut));
  Assert.AreEqual(CtrlFlag or Ord('F'), Integer(Search.ShortCut));
  Assert.AreEqual(CtrlFlag or Ord('C'), Integer(Copy.ShortCut));
  Assert.AreEqual(0, Integer(Prior.ShortCut), 'PageUp is only in the hint');
  const PageUpText = TPdfActionShortCuts.ToText(TPdfActionShortCuts.Plain(vkPrior));
  Assert.IsNotEmpty(PageUpText, 'the platform has a text for PageUp');
  Assert.IsTrue(Prior.Hint.Contains(PageUpText), Prior.Hint);
  Assert.IsTrue(Print.Hint.Contains(TPdfActionShortCuts.ToText(Print.ShortCut)), Print.Hint);
  for var Action in TArray<TCustomAction>.Create(ZoomIn, ZoomOut, Print, Search, Copy, Prior) do
  begin
    Assert.IsNotEmpty(Action.Text, Action.ClassName);
    Assert.IsNotEmpty(Action.Hint, Action.ClassName);
  end;
end;

procedure TPdf4DActionsTests.TestDisabledActionsDoNotRun;
begin
  const Counter = TCallCounter.Create;
  try
    Assert.IsTrue(FHost.Open(TRestrictedDocument.Build), FHost.OpenErrorMessage);
    const Print = TPdf4DPrintAction.Create(FHost.Form);
    Print.Document := FHost.Document;
    Print.OnExecute := Counter.Handle;
    const ZoomIn = TPdf4DZoomInAction.Create(FHost.Form);
    ZoomIn.PageView := FHost.PageView;
    const Copy = TPdf4DCopyAction.Create(FHost.Form);
    Copy.PageView := FHost.PageView;
    FHost.Document.Close;
    const ZoomBefore = FHost.PageView.Zoom;

    Assert.IsFalse(Print.Execute, 'a document that may not be printed');
    Assert.AreEqual(0, Counter.Calls, 'the handler did not run');
    Assert.IsFalse(ZoomIn.Execute, 'no open document in the page view');
    Assert.AreEqual(Double(ZoomBefore), Double(FHost.PageView.Zoom), Tolerance);
    Assert.IsFalse(Copy.Execute, 'nothing is selected');
    Assert.AreEqual<Integer>(0, FHost.PageView.CopiedTexts.Count);
  finally
    Counter.Free;
  end;
end;

// In an action list of the form: a disabled action lets the key through to the control that has the focus
procedure TPdf4DActionsTests.TestDisabledActionsLeaveTheirShortCut;
begin
  const Counter = TCallCounter.Create;
  try
    Assert.IsTrue(FHost.Open(TRestrictedDocument.Build), FHost.OpenErrorMessage);
    const Actions = TActionList.Create(FHost.Form);
    const Print = TPdf4DPrintAction.Create(FHost.Form);
    Print.ActionList := Actions;
    Print.Document := FHost.Document;
    Print.OnExecute := Counter.Handle;
    const Copy = TPdf4DCopyAction.Create(FHost.Form);
    Copy.ActionList := Actions;
    Copy.PageView := FHost.PageView;
    const Edit = TEdit.Create(FHost.Form);
    Edit.Parent := FHost.Form;

    Assert.IsFalse(FHost.PressKeyOn(Edit, vkP, [ssCtrl]), 'Ctrl+P goes on to the edit, which has no use for it');
    Assert.AreEqual(0, Counter.Calls, 'the print action did not run');
    FHost.PressKeyOn(Edit, vkC, [ssCtrl]);
    Assert.AreEqual<Integer>(0, FHost.PageView.CopiedTexts.Count, 'the copy action did not run');
  finally
    Counter.Free;
  end;
end;

procedure TPdf4DActionsTests.TestCopyShortCutBelongsToTheFocusedPageView;
begin
  OpenInvoice;
  const Actions = TActionList.Create(FHost.Form);
  const Copy = TPdf4DCopyAction.Create(FHost.Form);
  Copy.ActionList := Actions;
  Copy.PageView := FHost.PageView;
  const Edit = TEdit.Create(FHost.Form);
  Edit.Parent := FHost.Form;

  SelectInvoiceNumber;
  Copy.Update;
  Assert.IsTrue(Copy.Enabled, 'a word is selected');

  FHost.PressKeyOn(Edit, vkC, [ssCtrl]);
  Assert.AreEqual<Integer>(0, FHost.PageView.CopiedTexts.Count, 'the selection of the page view is not copied');

  Assert.IsTrue(FHost.PressKeyOn(FHost.PageView, vkC, [ssCtrl]), 'the action takes Ctrl+C in the page view');
  Assert.AreEqual<Integer>(1, FHost.PageView.CopiedTexts.Count, 'copied once');
end;

procedure TPdf4DActionsTests.TestSearchShortCutNeedsTheFocusScope;
begin
  OpenPages(1);
  const Bar = FHost.AddSearchBar;
  Bar.Visible := False;
  const Actions = TActionList.Create(FHost.Form);
  const Search = TPdf4DSearchAction.Create(FHost.Form);
  Search.ActionList := Actions;
  Search.SearchBar := Bar;
  Search.FocusScope := FHost.PageView;
  const Edit = TEdit.Create(FHost.Form);
  Edit.Parent := FHost.Form;

  Edit.SetFocus;
  FHost.PressKey(vkF, [ssCtrl]);
  Assert.IsFalse(Bar.Visible, 'the focus is outside the scope');

  FHost.PageView.SetFocus;
  Assert.IsTrue(FHost.PressKey(vkF, [ssCtrl]), 'the action takes Ctrl+F inside the scope');
  Assert.IsTrue(Bar.Visible, 'the bar is shown');
  Assert.IsTrue(Bar.EditQuery.IsFocused, 'the cursor is in the query field');
end;

end.
