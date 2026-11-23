// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Vcl.PrintDialog.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.Types,
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Tests.VclHost,
  Pdf4D.Tests.BitmapPrintTarget;

type
  [TestFixture]
  TPdf4DPrintDialogTests = class
  private
    FHost: TVclTestHost;
    FDialog: TBitmapPrintDialog;
    FFolder: string;
    FPrintedCount: Integer;
    FFailure: string;

    procedure HandlePrinted(Sender: TObject);
    procedure HandleFailed(Sender: TObject; const ErrorMessage: string);
    procedure WaitUntilDone;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestDialogValidatesRange;

    [Test]
    procedure TestDialogValidatesCopies;

    [Test]
    procedure TestDialogShowsAndReadsSettings;

    [Test]
    procedure TestExecutePrintsWhenConfirmed;

    [Test]
    procedure TestExecuteDoesNotPrintWhenCancelled;

    [Test]
    procedure TestPrintActionOpensDialog;

    [Test]
    procedure TestPrintActionWithoutDialogMakesItsOwn;

    [Test]
    procedure TestCancelFromProgressWindow;

    [Test]
    procedure TestProgressWindowGoesAwayWhenDone;

    [Test]
    procedure TestPrintRaisesWhenNotAllowed;

    [Test]
    procedure TestPrintRaisesWhileRunning;

    [Test]
    procedure TestFailureIsReported;
  end;

implementation

uses
  System.IOUtils,
  System.UITypes,
  Vcl.Forms,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.Print,
  Pdf4D.Vcl.Actions,
  Pdf4D.Vcl.PrintDialog,
  Pdf4D.Tests.ViewerDocuments;

const
  ViewWidth = 800;
  ViewHeight = 600;
  WaitMs = 30000;
  LongDocumentPages = 20;
  PageDelayMs = 30;
  SlowPagesBeforeCancel = 2;
  SettleMs = 300;

{ TPdf4DPrintDialogTests }

procedure TPdf4DPrintDialogTests.Setup;
begin
  FHost := TVclTestHost.Create(ViewWidth, ViewHeight);
  FFolder := TPath.Combine(TPath.GetTempPath, 'Pdf4DPrintDialogTests-' + TGUID.NewGuid.ToString);
  FPrintedCount := 0;
  FDialog := TBitmapPrintDialog.Create(FHost.Form);
  FDialog.Document := FHost.Document;
  FDialog.Folder := FFolder;
  FDialog.OnPrinted := HandlePrinted;
end;

procedure TPdf4DPrintDialogTests.TearDown;
begin
  TPdf4DPrintDialog.ModalRunner := nil;
  // The job of the dialog and a window that is released go away from the queues
  FHost.Pump(30);
  FreeAndNil(FHost);
  if TDirectory.Exists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
end;

procedure TPdf4DPrintDialogTests.HandlePrinted(Sender: TObject);
begin
  Inc(FPrintedCount);
end;

procedure TPdf4DPrintDialogTests.HandleFailed(Sender: TObject; const ErrorMessage: string);
begin
  FFailure := ErrorMessage;
end;

procedure TPdf4DPrintDialogTests.WaitUntilDone;
begin
  Assert.IsTrue(FHost.WaitUntil(
    function: Boolean
    begin
      Result := not FDialog.IsPrinting;
    end, WaitMs), 'the job ends');
end;

procedure TPdf4DPrintDialogTests.TestDialogValidatesRange;
begin
  const Form = TPdf4DPrintDialogForm.CreateFor(5, 0);
  try
    Assert.IsTrue(Form.ButtonOk.Enabled, 'all pages is valid');

    Form.RadioButtonPages.Checked := True;
    Form.EditFromPage.Text := '3';
    Form.EditToPage.Text := '2';
    Assert.IsFalse(Form.ButtonOk.Enabled, 'from 3 to 2 is not a range');

    Form.EditFromPage.Text := '1';
    Form.EditToPage.Text := '2';
    Assert.IsTrue(Form.ButtonOk.Enabled, 'from 1 to 2 is a range');
    Assert.AreEqual(TPdfPrintRangeKind.Pages, Form.ReadSettings.RangeKind);
    Assert.AreEqual(1, Form.ReadSettings.FromPage);
    Assert.AreEqual(2, Form.ReadSettings.ToPage);

    Form.EditToPage.Text := '6';
    Assert.IsFalse(Form.ButtonOk.Enabled, 'page 6 is not in a document of 5 pages');

    Form.EditToPage.Text := '';
    Assert.IsFalse(Form.ButtonOk.Enabled, 'an empty page number is not valid');

    Form.RadioButtonAll.Checked := True;
    Assert.IsTrue(Form.ButtonOk.Enabled, 'the range does not matter when all pages are printed');
    Assert.IsFalse(Form.EditFromPage.Enabled, 'the page edits are off then');
  finally
    Form.Free;
  end;
end;

procedure TPdf4DPrintDialogTests.TestDialogValidatesCopies;
begin
  const Form = TPdf4DPrintDialogForm.CreateFor(5, 0);
  try
    Form.EditCopies.Text := '0';
    Assert.IsFalse(Form.ButtonOk.Enabled, 'no copies is not valid');
    Form.EditCopies.Text := '3';
    Assert.IsTrue(Form.ButtonOk.Enabled);
    Assert.AreEqual(3, Form.ReadSettings.Copies);
  finally
    Form.Free;
  end;
end;

procedure TPdf4DPrintDialogTests.TestDialogShowsAndReadsSettings;
begin
  const Form = TPdf4DPrintDialogForm.CreateFor(5, 2);
  try
    var Settings := TPdfPrintSettings.Default;
    Settings.RangeKind := TPdfPrintRangeKind.Current;
    Settings.Scale := TPdfPrintScale.ActualSize;
    Settings.Copies := 4;
    Form.Load(Settings);

    Assert.IsTrue(Form.RadioButtonCurrent.Checked);
    Assert.IsTrue(Form.RadioButtonActualSize.Checked);
    Assert.AreEqual('4', Form.EditCopies.Text);
    Assert.IsTrue(string(Form.RadioButtonCurrent.Caption).Contains('3'), 'the current page is shown 1-based');

    const Read = Form.ReadSettings;
    Assert.AreEqual(TPdfPrintRangeKind.Current, Read.RangeKind);
    Assert.AreEqual(TPdfPrintScale.ActualSize, Read.Scale);
    Assert.AreEqual(4, Read.Copies);
  finally
    Form.Free;
  end;
end;

procedure TPdf4DPrintDialogTests.TestExecutePrintsWhenConfirmed;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Invoice), 'the document opens');
  TPdf4DPrintDialog.ModalRunner :=
    function(Form: TPdf4DPrintDialogForm): TModalResult
    begin
      Form.RadioButtonCurrent.Checked := True;
      Form.RadioButtonActualSize.Checked := True;
      Form.EditCopies.Text := '2';
      Result := mrOk;
    end;

  FHost.Document.CurrentPage := 1;
  Assert.IsTrue(FDialog.Execute, 'the user confirms');
  WaitUntilDone;

  Assert.AreEqual(TPdfPrintRangeKind.Current, FDialog.RangeKind);
  Assert.AreEqual(TPdfPrintScale.ActualSize, FDialog.Scale);
  Assert.AreEqual(2, FDialog.Copies);
  Assert.AreEqual(1, Integer(FDialog.Target.Pages.Count), 'the current page');
  Assert.AreEqual(2, FDialog.Target.Copies, 'the copies reach the target');
  Assert.AreEqual(1, FPrintedCount);
end;

procedure TPdf4DPrintDialogTests.TestExecuteDoesNotPrintWhenCancelled;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Invoice), 'the document opens');
  TPdf4DPrintDialog.ModalRunner :=
    function(Form: TPdf4DPrintDialogForm): TModalResult
    begin
      Form.RadioButtonCurrent.Checked := True;
      Result := mrCancel;
    end;

  Assert.IsFalse(FDialog.Execute, 'the user cancels');
  Assert.IsFalse(FDialog.IsPrinting);
  Assert.IsNull(FDialog.Target, 'nothing is printed');
  Assert.AreEqual(TPdfPrintRangeKind.All, FDialog.RangeKind, 'the settings are as they were');
end;

procedure TPdf4DPrintDialogTests.TestPrintActionOpensDialog;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Invoice), 'the document opens');
  var Settings := TPdfPrintSettings.Default;
  Settings.RangeKind := TPdfPrintRangeKind.Pages;
  Settings.FromPage := 2;
  Settings.ToPage := 2;
  Settings.Scale := TPdfPrintScale.ActualSize;
  Settings.Copies := 3;
  FDialog.Settings := Settings;

  const Action = TPdf4DPrintAction.Create(FHost.Form);
  Action.Document := FHost.Document;
  Action.PrintDialog := FDialog;
  Action.Update;
  Assert.IsTrue(Action.Enabled, 'the document may be printed');

  var Shown := 0;
  var WasPages, WasActualSize: Boolean;
  var FromText, ToText, CopiesText: string;
  TPdf4DPrintDialog.ModalRunner :=
    function(Form: TPdf4DPrintDialogForm): TModalResult
    begin
      Inc(Shown);
      WasPages := Form.RadioButtonPages.Checked;
      WasActualSize := Form.RadioButtonActualSize.Checked;
      FromText := Form.EditFromPage.Text;
      ToText := Form.EditToPage.Text;
      CopiesText := Form.EditCopies.Text;
      Result := mrCancel;
    end;

  Assert.IsTrue(Action.Execute);
  Assert.AreEqual(1, Shown, 'the dialog is shown');
  Assert.IsTrue(WasPages, 'the range is passed to the dialog');
  Assert.IsTrue(WasActualSize, 'the scale is passed to the dialog');
  Assert.AreEqual('2', FromText);
  Assert.AreEqual('2', ToText);
  Assert.AreEqual('3', CopiesText);
  Assert.IsNull(FDialog.Target, 'cancelling prints nothing');

  // Confirming prints with the dialog of the action
  TPdf4DPrintDialog.ModalRunner :=
    function(Form: TPdf4DPrintDialogForm): TModalResult
    begin
      Result := mrOk;
    end;
  Assert.IsTrue(Action.Execute);
  WaitUntilDone;
  Assert.AreEqual(1, Integer(FDialog.Target.Pages.Count), 'page 2 is printed');
  Assert.AreEqual(3, FDialog.Target.Copies);
  Assert.AreEqual(1, FPrintedCount);
end;

procedure TPdf4DPrintDialogTests.TestPrintActionWithoutDialogMakesItsOwn;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Invoice), 'the document opens');
  FHost.Document.CurrentPage := 1;

  const Action = TPdf4DPrintAction.Create(FHost.Form);
  Action.Document := FHost.Document;
  var Shown := 0;
  var CurrentCaption := '';
  TPdf4DPrintDialog.ModalRunner :=
    function(Form: TPdf4DPrintDialogForm): TModalResult
    begin
      Inc(Shown);
      CurrentCaption := string(Form.RadioButtonCurrent.Caption);
      Result := mrCancel;
    end;

  Assert.IsTrue(Action.Execute);
  Assert.AreEqual(1, Shown, 'the dialog is shown');
  Assert.IsTrue(CurrentCaption.Contains('2'), 'the dialog knows the document');
end;

procedure TPdf4DPrintDialogTests.TestCancelFromProgressWindow;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Pages(LongDocumentPages, 612, 792, 0)), 'the document opens');
  FDialog.ShowProgress := True;
  FDialog.DrawDelayMs := PageDelayMs;
  FDialog.Print(TPdfPrintSettings.Default);

  Assert.IsNotNull(FDialog.ProgressForm, 'the progress window is shown');
  Assert.IsTrue(FHost.WaitUntil(
    function: Boolean
    begin
      Result := Assigned(FDialog.Target) and (FDialog.Target.Pages.Count >= SlowPagesBeforeCancel);
    end, WaitMs), 'the job prints');
  Assert.IsTrue(FDialog.IsPrinting, 'the job is still running');

  FDialog.ProgressForm.ButtonCancel.Click;

  const Target = FDialog.Target;
  Assert.IsTrue(Target.IsAborted, 'the document is aborted');
  Assert.IsFalse(Target.IsEnded, 'the document is not ended');
  Assert.IsFalse(FDialog.IsPrinting, 'the job is over');
  var PagesAtCancel: Integer;
  PagesAtCancel := Target.Pages.Count;
  Assert.IsTrue(PagesAtCancel < LongDocumentPages, 'not all pages are printed');

  FHost.Pump(SettleMs);
  Assert.AreEqual(PagesAtCancel, Integer(Target.Pages.Count), 'no bitmaps after the cancel');
  Assert.AreEqual(0, FPrintedCount, 'a cancelled job is not printed');
  Assert.IsFalse(TDirectory.Exists(FFolder), 'no pages are written');
  Assert.IsNull(FDialog.ProgressForm, 'the progress window is gone');
end;

procedure TPdf4DPrintDialogTests.TestProgressWindowGoesAwayWhenDone;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Invoice), 'the document opens');
  FDialog.ShowProgress := True;
  FDialog.Print(TPdfPrintSettings.Default);
  Assert.IsNotNull(FDialog.ProgressForm, 'the progress window is shown');

  WaitUntilDone;
  Assert.IsNull(FDialog.ProgressForm, 'the progress window is gone');
  Assert.AreEqual(1, FPrintedCount);
end;

procedure TPdf4DPrintDialogTests.TestPrintRaisesWhenNotAllowed;
begin
  Assert.IsTrue(FHost.Open(TVclTestDocuments.Restricted), 'the document opens');
  Assert.IsFalse(FHost.Document.CanPrint, 'the document does not allow printing');
  Assert.WillRaise(
    procedure
    begin
      FDialog.Print(TPdfPrintSettings.Default);
    end,
    System.SysUtils.EInvalidOpException);
  Assert.IsFalse(FDialog.IsPrinting);
end;

procedure TPdf4DPrintDialogTests.TestPrintRaisesWhileRunning;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Pages(LongDocumentPages, 612, 792, 0)), 'the document opens');
  FDialog.DrawDelayMs := PageDelayMs;
  FDialog.Print(TPdfPrintSettings.Default);
  Assert.IsTrue(FDialog.IsPrinting);
  Assert.WillRaise(
    procedure
    begin
      FDialog.Print(TPdfPrintSettings.Default);
    end,
    System.SysUtils.EInvalidOpException);
  // The dialog is freed with the form while its job runs: the job is cancelled without a callback
end;

procedure TPdf4DPrintDialogTests.TestFailureIsReported;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Invoice), 'the document opens');
  // A paper without area makes the plan of the first page fail
  FDialog.Printable := TSize.Create(0, 0);
  FDialog.OnPrintFailed := HandleFailed;

  FDialog.Print(TPdfPrintSettings.Default);
  WaitUntilDone;

  Assert.IsTrue(FFailure <> '', 'the failure is reported');
  Assert.AreEqual(0, FPrintedCount);
  Assert.IsTrue(FDialog.Target.IsAborted, 'the document is aborted');
end;

end.
