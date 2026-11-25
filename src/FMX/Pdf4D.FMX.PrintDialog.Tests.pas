// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.FMX.PrintDialog.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.Types,
  System.SysUtils,
  System.UITypes,
  FMX.Controls,
  FMX.Forms,
  FMX.StdCtrls,
  DUnitX.TestFramework,
  Pdf4D.Tests.FmxHost,
  Pdf4D.Tests.FmxBitmapPrintTarget,
  Pdf4D.FMX.Document,
  Pdf4D.FMX.PrintDialog;

type
  // Gives the tests the click of a button, as a press of the mouse does
  TPrintButtonCracker = class(TButton);
  TPrintSpeedButtonCracker = class(TSpeedButton);

  // What the stand-in for the modal dialog does with the form
  TModalMode = (Confirm, Cancel, ChooseCurrentActualSizeTwoCopies);

  [TestFixture]
  TPdf4DPrintDialogTests = class
  private
    FHost: TFmxTestHost;
    FDialog: TFmxBitmapPrintDialog;
    FFolder: string;
    FPrintedCount: Integer;
    FFailure: string;
    FMode: TModalMode;
    FShown: Integer;
    FSawPages: Boolean;
    FSawActualSize: Boolean;
    FSawFromText: string;
    FSawToText: string;
    FSawCopies: Integer;
    FSawCurrentText: string;
    FSecond: TPdf4DDocument;

    procedure HandlePrinted(Sender: TObject);
    procedure HandleFailed(Sender: TObject; const ErrorMessage: string);
    // The stand-in for the modal dialog: records what the form shows, then does what FMode says
    function RunForm(const Form: TPdf4DPrintDialogForm): TModalResult;
    procedure UseRunner(const Mode: TModalMode);
    function IsJobOver: Boolean;
    function HasTwoPages: Boolean;
    function IsSecondOpen: Boolean;
    procedure WaitUntilDone;
    procedure PrintNow;
    procedure ExecuteNow;
    procedure OpenLongDocument;
    class procedure AssertInside(const Control: TControl; const Form: TCommonCustomForm; const Name: string); static;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestDialogValidatesRange;

    [Test]
    procedure TestDialogKeepsCopiesInRange;

    [Test]
    procedure TestDialogShowsAndReadsSettings;

    [Test]
    procedure TestDialogListsThePrinters;

    [Test]
    procedure TestExecutePrintsWhenConfirmed;

    [Test]
    procedure TestExecuteDoesNotPrintWhenCancelled;

    [Test]
    procedure TestPrintActionOpensDialog;

    [Test]
    procedure TestPrintActionWithoutDialogMakesItsOwn;

    [Test]
    procedure TestToolbarPrintButtonOpensTheDialog;

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

    [Test]
    procedure TestExecuteRaisesBeforeTheDialogWhenItCannotPrint;

    [Test]
    procedure TestDialogControlsAreOnTheForm;

    [Test]
    procedure TestProgressWindowControlsAreOnTheWindow;

    [Test]
    procedure TestPrintActionGivesItsDocumentToTheDialog;
  end;

implementation

uses
  System.IOUtils,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.Print,
  Pdf4D.FMX.Actions,
  Pdf4D.FMX.Toolbar,
  Pdf4D.Tests.ViewerDocuments,
  Pdf4D.Tests.RestrictedDocument;

const
  ViewWidth = 800;
  ViewHeight = 600;
  WaitMs = 30000;
  LongDocumentPages = 20;
  PageDelayMs = 30;
  SlowPagesBeforeCancel = 2;
  SettleMs = 300;
  DialogClientWidth = 420;
  DialogClientHeight = 330;
  ProgressClientWidth = 360;
  ProgressClientHeight = 110;

{ TPdf4DPrintDialogTests }

procedure TPdf4DPrintDialogTests.Setup;
begin
  FHost := TFmxTestHost.Create(ViewWidth, ViewHeight);
  FFolder := TPath.Combine(TPath.GetTempPath, 'Pdf4DFmxPrintDialogTests-' + TGUID.NewGuid.ToString);
  FPrintedCount := 0;
  FFailure := '';
  FShown := 0;
  FMode := TModalMode.Cancel;
  FDialog := TFmxBitmapPrintDialog.Create(FHost.Form);
  FDialog.Document := FHost.Document;
  FDialog.Folder := FFolder;
  FDialog.OnPrinted := HandlePrinted;
end;

procedure TPdf4DPrintDialogTests.TearDown;
begin
  TPdf4DPrintDialog.ModalRunner := nil;
  // The job of the dialog and a window that is dismissed go away from the queues
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

function TPdf4DPrintDialogTests.RunForm(const Form: TPdf4DPrintDialogForm): TModalResult;
begin
  Inc(FShown);
  FSawPages := Form.RadioButtonPages.IsChecked;
  FSawActualSize := Form.RadioButtonActualSize.IsChecked;
  FSawFromText := Form.EditFromPage.Text;
  FSawToText := Form.EditToPage.Text;
  FSawCopies := Integer(Round(Form.EditCopies.Value));
  FSawCurrentText := Form.RadioButtonCurrent.Text;

  case FMode of
    TModalMode.Confirm:
      Result := mrOk;
    TModalMode.Cancel:
      Result := mrCancel;
    TModalMode.ChooseCurrentActualSizeTwoCopies:
      begin
        Form.RadioButtonCurrent.IsChecked := True;
        Form.RadioButtonActualSize.IsChecked := True;
        Form.EditCopies.Value := 2;
        Result := mrOk;
      end;
  else
    raise ENotSupportedException.CreateFmt('Unsupported mode: %d', [Ord(FMode)]);
  end;
end;

procedure TPdf4DPrintDialogTests.UseRunner(const Mode: TModalMode);
begin
  FMode := Mode;
  TPdf4DPrintDialog.ModalRunner := RunForm;
end;

function TPdf4DPrintDialogTests.IsJobOver: Boolean;
begin
  Result := not FDialog.IsPrinting;
end;

function TPdf4DPrintDialogTests.HasTwoPages: Boolean;
begin
  Result := Assigned(FDialog.Target) and (FDialog.Target.Pages.Count >= SlowPagesBeforeCancel);
end;

function TPdf4DPrintDialogTests.IsSecondOpen: Boolean;
begin
  Result := (FSecond.State = TPdfDocumentState.Open);
end;

procedure TPdf4DPrintDialogTests.WaitUntilDone;
begin
  Assert.IsTrue(FHost.WaitUntil(IsJobOver, WaitMs), 'the job ends');
end;

procedure TPdf4DPrintDialogTests.PrintNow;
begin
  FDialog.Print(TPdfPrintSettings.Default);
end;

procedure TPdf4DPrintDialogTests.ExecuteNow;
begin
  FDialog.Execute;
end;

procedure TPdf4DPrintDialogTests.OpenLongDocument;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Pages(LongDocumentPages, 612, 792, 0)), 'the document opens');
end;

procedure TPdf4DPrintDialogTests.TestDialogValidatesRange;
begin
  const Form = TPdf4DPrintDialogForm.CreateFor(5, 0);
  try
    Assert.IsTrue(Form.ButtonOk.Enabled, 'all pages is valid');

    Form.RadioButtonPages.IsChecked := True;
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

    Form.RadioButtonAll.IsChecked := True;
    Assert.IsTrue(Form.ButtonOk.Enabled, 'the range does not matter when all pages are printed');
    Assert.IsFalse(Form.EditFromPage.Enabled, 'the page edits are off then');
  finally
    Form.Free;
  end;
end;

// The spin box does not leave the range: a number outside it is taken back, so OK stays on
procedure TPdf4DPrintDialogTests.TestDialogKeepsCopiesInRange;
begin
  const Form = TPdf4DPrintDialogForm.CreateFor(5, 0);
  try
    Form.EditCopies.Value := 0;
    Assert.AreEqual(1, Form.ReadSettings.Copies, 'no copies becomes one');
    Assert.IsTrue(Form.ButtonOk.Enabled);

    Form.EditCopies.Value := 3;
    Assert.IsTrue(Form.ButtonOk.Enabled);
    Assert.AreEqual(3, Form.ReadSettings.Copies);

    Form.EditCopies.Value := MaxPrintCopies + 1;
    Assert.AreEqual(MaxPrintCopies, Form.ReadSettings.Copies, 'too many copies becomes the most');
    Assert.IsTrue(Form.ButtonOk.Enabled);
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

    Assert.IsTrue(Form.RadioButtonCurrent.IsChecked);
    Assert.IsTrue(Form.RadioButtonActualSize.IsChecked);
    Assert.IsFalse(Form.RadioButtonAll.IsChecked, 'one range at a time');
    Assert.IsFalse(Form.RadioButtonFit.IsChecked, 'one size at a time');
    Assert.AreEqual(4, Integer(Round(Form.EditCopies.Value)));
    Assert.IsTrue(Form.RadioButtonCurrent.Text.Contains('3'), 'the current page is shown 1-based');

    const Read = Form.ReadSettings;
    Assert.AreEqual(TPdfPrintRangeKind.Current, Read.RangeKind);
    Assert.AreEqual(TPdfPrintScale.ActualSize, Read.Scale);
    Assert.AreEqual(4, Read.Copies);
  finally
    Form.Free;
  end;
end;

procedure TPdf4DPrintDialogTests.TestDialogListsThePrinters;
begin
  const Form = TPdf4DPrintDialogForm.CreateFor(5, 0);
  try
    Assert.AreEqual(Form.ComboBoxPrinter.Items.Count > 0, Form.ComboBoxPrinter.Enabled, 'the list is on when there are printers');
    Assert.AreEqual(Form.ComboBoxPrinter.Enabled, Form.ButtonProperties.Enabled, 'the properties follow the list');
  finally
    Form.Free;
  end;
end;

procedure TPdf4DPrintDialogTests.TestExecutePrintsWhenConfirmed;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Invoice), 'the document opens');
  UseRunner(TModalMode.ChooseCurrentActualSizeTwoCopies);

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
  UseRunner(TModalMode.Cancel);

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

  UseRunner(TModalMode.Cancel);
  Assert.IsTrue(Action.Execute);
  Assert.AreEqual(1, FShown, 'the dialog is shown');
  Assert.IsTrue(FSawPages, 'the range is passed to the dialog');
  Assert.IsTrue(FSawActualSize, 'the scale is passed to the dialog');
  Assert.AreEqual('2', FSawFromText);
  Assert.AreEqual('2', FSawToText);
  Assert.AreEqual(3, FSawCopies);
  Assert.IsNull(FDialog.Target, 'cancelling prints nothing');

  // Confirming prints with the dialog of the action
  UseRunner(TModalMode.Confirm);
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
  UseRunner(TModalMode.Cancel);

  Assert.IsTrue(Action.Execute);
  Assert.AreEqual(1, FShown, 'the dialog is shown');
  Assert.IsTrue(FSawCurrentText.Contains('2'), 'the dialog knows the document');
end;

procedure TPdf4DPrintDialogTests.TestToolbarPrintButtonOpensTheDialog;
begin
  FHost.AddSearchBar;
  FHost.AddPageView;
  const Toolbar = FHost.AddToolbar;
  Assert.IsTrue(FHost.Open(TViewerDocuments.Invoice), 'the document opens');
  Toolbar.PrintDialog := FDialog;
  Assert.AreSame(FDialog, Toolbar.PrintDialog);
  UseRunner(TModalMode.Confirm);

  TPrintSpeedButtonCracker(Toolbar.ButtonPrint).Click;
  Assert.AreEqual(1, FShown, 'the print button shows the dialog');
  WaitUntilDone;
  Assert.AreEqual(2, Integer(FDialog.Target.Pages.Count), 'the document is printed');

  FreeAndNil(FDialog);
  Assert.IsNull(Toolbar.PrintDialog, 'the toolbar lets go of a dialog that is freed');
end;

procedure TPdf4DPrintDialogTests.TestCancelFromProgressWindow;
begin
  OpenLongDocument;
  FDialog.ShowProgress := True;
  FDialog.DrawDelayMs := PageDelayMs;
  FDialog.Print(TPdfPrintSettings.Default);

  Assert.IsNotNull(FDialog.ProgressForm, 'the progress window is shown');
  Assert.IsTrue(FHost.WaitUntil(HasTwoPages, WaitMs), 'the job prints');
  Assert.IsTrue(FDialog.IsPrinting, 'the job is still running');

  TPrintButtonCracker(FDialog.ProgressForm.ButtonCancel).Click;

  const Target = FDialog.Target;
  Assert.IsTrue(Target.IsAborted, 'the document is aborted');
  Assert.IsFalse(Target.IsEnded, 'the document is not ended');
  Assert.IsFalse(FDialog.IsPrinting, 'the job is over');
  const PagesAtCancel: Integer = Target.Pages.Count;
  Assert.IsTrue(PagesAtCancel < LongDocumentPages, 'not all pages are printed');

  FHost.Pump(SettleMs);
  Assert.AreEqual<Integer>(PagesAtCancel, Target.Pages.Count, 'no bitmaps after the cancel');
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
  Assert.IsTrue(FHost.Open(TRestrictedDocument.Build), 'the document opens');
  Assert.IsFalse(FHost.Document.CanPrint, 'the document does not allow printing');
  Assert.WillRaise(PrintNow, EInvalidOpException);
  Assert.IsFalse(FDialog.IsPrinting);
end;

procedure TPdf4DPrintDialogTests.TestPrintRaisesWhileRunning;
begin
  OpenLongDocument;
  FDialog.DrawDelayMs := PageDelayMs;
  FDialog.Print(TPdfPrintSettings.Default);
  Assert.IsTrue(FDialog.IsPrinting);
  Assert.WillRaise(PrintNow, EInvalidOpException);
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

// The user does not fill in a dialog for a document that cannot be printed now
procedure TPdf4DPrintDialogTests.TestExecuteRaisesBeforeTheDialogWhenItCannotPrint;
begin
  UseRunner(TModalMode.Confirm);

  Assert.IsTrue(FHost.Open(TRestrictedDocument.Build), 'the document opens');
  Assert.WillRaise(ExecuteNow, EInvalidOpException);
  Assert.AreEqual(0, FShown, 'no dialog for a document that may not be printed');

  OpenLongDocument;
  FDialog.DrawDelayMs := PageDelayMs;
  FDialog.Print(TPdfPrintSettings.Default);
  Assert.WillRaise(ExecuteNow, EInvalidOpException);
  Assert.AreEqual(0, FShown, 'no dialog while a job runs');
  // The dialog is freed with the form while its job runs
end;

class procedure TPdf4DPrintDialogTests.AssertInside(const Control: TControl; const Form: TCommonCustomForm; const Name: string);
begin
  const Rect = Control.AbsoluteRect;
  const Message = Format('%s is on the form: %.0f,%.0f to %.0f,%.0f', [Name, Rect.Left, Rect.Top, Rect.Right, Rect.Bottom]);
  Assert.IsTrue((Rect.Left >= 0) and (Rect.Top >= 0) and (Rect.Right <= Form.ClientWidth) and (Rect.Bottom <= Form.ClientHeight), Message);
end;

procedure TPdf4DPrintDialogTests.TestDialogControlsAreOnTheForm;
begin
  const Form = TPdf4DPrintDialogForm.CreateFor(5, 0);
  try
    Assert.AreEqual(DialogClientWidth, Integer(Round(Form.ClientWidth)), 'the form');
    Assert.AreEqual(DialogClientHeight, Integer(Round(Form.ClientHeight)), 'the form');
    AssertInside(Form.ComboBoxPrinter, Form, 'the printer list');
    AssertInside(Form.ButtonProperties, Form, 'the properties button');
    AssertInside(Form.RadioButtonAll, Form, 'all pages');
    AssertInside(Form.RadioButtonCurrent, Form, 'current page');
    AssertInside(Form.RadioButtonPages, Form, 'pages');
    AssertInside(Form.EditFromPage, Form, 'from');
    AssertInside(Form.EditToPage, Form, 'to');
    AssertInside(Form.RadioButtonFit, Form, 'fit');
    AssertInside(Form.RadioButtonActualSize, Form, 'actual size');
    AssertInside(Form.EditCopies, Form, 'copies');
    AssertInside(Form.ButtonOk, Form, 'OK');
    AssertInside(Form.ButtonCancel, Form, 'cancel');
  finally
    Form.Free;
  end;
end;

procedure TPdf4DPrintDialogTests.TestProgressWindowControlsAreOnTheWindow;
begin
  const Form = TPdf4DPrintProgressForm.CreateFor(nil);
  try
    Assert.AreEqual(ProgressClientWidth, Integer(Round(Form.ClientWidth)), 'the window');
    Assert.AreEqual(ProgressClientHeight, Integer(Round(Form.ClientHeight)), 'the window');
    AssertInside(Form.LabelStatus, Form, 'the status');
    AssertInside(Form.ProgressBar, Form, 'the bar');
    AssertInside(Form.ButtonCancel, Form, 'cancel');
  finally
    Form.Free;
  end;
end;

// The action gives its document to a dialog without one, and follows its document when it changes; a document that the application gave
// the dialog stays
procedure TPdf4DPrintDialogTests.TestPrintActionGivesItsDocumentToTheDialog;
begin
  UseRunner(TModalMode.Cancel);

  Assert.IsTrue(FHost.Open(TViewerDocuments.Invoice), 'the document opens');
  FSecond := TPdf4DDocument.Create(FHost.Form);
  FSecond.RenderBackend := TFmxTestHost.NewRenderBackend;
  const Stream = TBytesStream.Create(TViewerDocuments.Pages(3, 612, 792, 0));
  try
    FSecond.Open(Stream);
  finally
    Stream.Free;
  end;
  Assert.IsTrue(FHost.WaitUntil(IsSecondOpen), 'the second document opens');

  const Dialog = TPdf4DPrintDialog.Create(FHost.Form);
  const Action = TPdf4DPrintAction.Create(FHost.Form);
  Action.PrintDialog := Dialog;
  Action.Document := FHost.Document;
  Action.Execute;
  Assert.AreSame(FHost.Document, Dialog.Document, 'the document of the action');

  Action.Document := FSecond;
  Action.Execute;
  Assert.AreSame(FSecond, Dialog.Document, 'the new document of the action');

  Dialog.Document := FHost.Document;
  Action.Execute;
  Assert.AreSame(FHost.Document, Dialog.Document, 'the document that the application chose');
end;

end.
