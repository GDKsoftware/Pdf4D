// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Vcl.PrintDialog;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.SysUtils,
  Vcl.Controls,
  Vcl.ComCtrls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.Document,
  Pdf4D.Viewer.Print;

const
  MaxPrintCopies = 999;

type
  TPdfPrintFailedEvent = procedure(Sender: TObject; const ErrorMessage: string) of object;

  // The form of the print dialog. It is built in code, without a .dfm. Its settings are those of the user's choice: the maximum
  // resolution and the title are not on it.
  TPdf4DPrintDialogForm = class(TForm)
  private
    FPageCount: Integer;
    FCurrentPage: Integer;
    FLabelPrinter: TLabel;
    FGroupBoxRange: TGroupBox;
    FLabelTo: TLabel;
    FGroupBoxScale: TGroupBox;
    FLabelCopies: TLabel;
    FIsLoading: Boolean;

    function AddRadioButton(const Parent: TWinControl; const Name, Caption: string; const Top: Integer): TRadioButton;
    function AddEdit(const Parent: TWinControl; const Name: string; const Left, Top, Width: Integer): TEdit;
    procedure BuildPrinterRow;
    procedure BuildRangeGroup;
    procedure BuildScaleGroup;
    procedure BuildCopiesRow;
    procedure BuildButtons;
    procedure LoadPrinters;
    procedure HandleInputChange(Sender: TObject);
    procedure HandlePropertiesClick(Sender: TObject);
    function TryReadNumber(const Edit: TEdit; out Value: Integer): Boolean;

  public
    ComboBoxPrinter: TComboBox;
    ButtonProperties: TButton;
    RadioButtonAll: TRadioButton;
    RadioButtonCurrent: TRadioButton;
    RadioButtonPages: TRadioButton;
    EditFromPage: TEdit;
    EditToPage: TEdit;
    RadioButtonFit: TRadioButton;
    RadioButtonActualSize: TRadioButton;
    EditCopies: TEdit;
    UpDownCopies: TUpDown;
    ButtonOk: TButton;
    ButtonCancel: TButton;

    // CurrentPage is 0-based
    constructor CreateFor(const PageCount, CurrentPage: Integer);

    procedure Load(const Settings: TPdfPrintSettings);
    // What the user has chosen. MaxDpi and Title are the defaults.
    function ReadSettings: TPdfPrintSettings;
    // Whether the range and the number of copies can be printed
    function IsInputValid: Boolean;
    // Enables the page edits and OK to what is chosen
    procedure UpdateState;
    // Makes the printer of the list the printer to print on
    procedure ApplyPrinter;
  end;

  // The window that shows the progress of a print job and lets the user cancel it
  TPdf4DPrintProgressForm = class(TForm)
  private
    FOnCancel: TNotifyEvent;
    FIsDismissed: Boolean;

    procedure HandleCancelClick(Sender: TObject);
    procedure HandleCloseQuery(Sender: TObject; var CanClose: Boolean);

  public
    LabelStatus: TLabel;
    ProgressBar: TProgressBar;
    ButtonCancel: TButton;

    constructor CreateFor(const OnCancel: TNotifyEvent);

    procedure SetProgress(const Printed, Total: Integer);
    // Closes the window; safe inside one of its own events
    procedure Dismiss;
  end;

  // Asks the user what to print and prints a document with a progress window. UI thread only.
  TPdf4DPrintDialog = class(TComponent)
  private
    FDocument: TPdf4DCustomDocument;
    FSettings: TPdfPrintSettings;
    FShowProgress: Boolean;
    FMaxBandPixels: Int64;
    FOnPrinted: TNotifyEvent;
    FOnPrintFailed: TPdfPrintFailedEvent;
    FJob: TPdfPrintJob;
    FProgressForm: TPdf4DPrintProgressForm;
    FIsFreeWhenDone: Boolean;
{$IFDEF PDF4D_TESTS}
    class var FModalRunner: TFunc<TPdf4DPrintDialogForm, TModalResult>;
{$ENDIF}

    procedure SetDocument(const Value: TPdf4DCustomDocument);
    function GetCopies: Integer;
    procedure SetCopies(const Value: Integer);
    function GetMaxDpi: Integer;
    procedure SetMaxDpi(const Value: Integer);
    function GetRangeKind: TPdfPrintRangeKind;
    procedure SetRangeKind(const Value: TPdfPrintRangeKind);
    function GetScale: TPdfPrintScale;
    procedure SetScale(const Value: TPdfPrintScale);
    procedure CheckCanPrint;
    function RunModal(const Form: TPdf4DPrintDialogForm): TModalResult;
    procedure ShowProgressForm;
    procedure CloseProgressForm;
    procedure HandleProgress(const Printed, Total: Integer);
    procedure HandleDone(const Status: TPdfPrintStatus; const ErrorMessage: string);
    procedure HandleCancelRequest(Sender: TObject);
    procedure ReportFailure(const ErrorMessage: string);

  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    // Where the pages go: the printer of Vcl.Printers
    function CreateTarget: IPdfPrintTarget; virtual;

  public
    constructor Create(Owner: TComponent); override;
    // A running job is cancelled without a callback
    destructor Destroy; override;

    // Shows the dialog modally; when the user confirms, Settings holds the choice and the document is printed (see Print)
    function Execute: Boolean;
    // Prints without the dialog. The job runs on: this returns at once, and OnPrinted or OnPrintFailed come when it is over; a job
    // that is cancelled gives neither. Raises EInvalidOpException while a job runs, or when the document may not be printed.
    procedure Print(const Settings: TPdfPrintSettings);
    function IsPrinting: Boolean;

{$IFDEF PDF4D_TESTS}
    // For tests only, compiled when PDF4D_TESTS is defined: runs in place of ShowModal. Set before use, reset to nil afterwards.
    class property ModalRunner: TFunc<TPdf4DPrintDialogForm, TModalResult> read FModalRunner write FModalRunner;
{$ENDIF}

    property Settings: TPdfPrintSettings read FSettings write FSettings;
    // The most pixels of one render of a band; DefaultMaxBandPixels
    property MaxBandPixels: Int64 read FMaxBandPixels write FMaxBandPixels;
    // The progress window of the running job; nil when there is none
    property ProgressForm: TPdf4DPrintProgressForm read FProgressForm;
    // Frees the dialog when the running job is over, after its events; for a dialog that nobody else holds
    property FreeWhenDone: Boolean read FIsFreeWhenDone write FIsFreeWhenDone;

  published
    property Document: TPdf4DCustomDocument read FDocument write SetDocument;
    property RangeKind: TPdfPrintRangeKind read GetRangeKind write SetRangeKind default TPdfPrintRangeKind.All;
    property Scale: TPdfPrintScale read GetScale write SetScale default TPdfPrintScale.Fit;
    property Copies: Integer read GetCopies write SetCopies default 1;
    property MaxDpi: Integer read GetMaxDpi write SetMaxDpi default DefaultMaxPrintDpi;
    property ShowProgress: Boolean read FShowProgress write FShowProgress default True;
    property OnPrinted: TNotifyEvent read FOnPrinted write FOnPrinted;
    property OnPrintFailed: TPdfPrintFailedEvent read FOnPrintFailed write FOnPrintFailed;
  end;

implementation

uses
  System.IOUtils,
  System.Math,
  System.UITypes,
  Winapi.Windows,
  Vcl.Dialogs,
  Vcl.Printers,
  Pdf4D.Viewer.ResourceStrings,
  Pdf4D.Vcl.Print;

type
  // Gives access to the protected file name of the document
  TDocumentCracker = class(TPdf4DCustomDocument);

const
  FormClientWidth = 400;
  FormClientHeight = 336;
  Margin = 12;
  RowHeight = 22;
  PageEditWidth = 48;
  ProgressClientWidth = 360;
  ProgressClientHeight = 110;

{ TPdf4DPrintDialogForm }

constructor TPdf4DPrintDialogForm.CreateFor(const PageCount, CurrentPage: Integer);
begin
  inherited CreateNew(nil);
  FPageCount := PageCount;
  FCurrentPage := CurrentPage;

  BorderStyle := bsDialog;
  Position := poScreenCenter;
  Caption := SPrintDialogCaption;
  ClientWidth := FormClientWidth;
  ClientHeight := FormClientHeight;

  // The controls change each other while they are made; the state is set when they all exist
  FIsLoading := True;
  try
    BuildPrinterRow;
    BuildRangeGroup;
    BuildScaleGroup;
    BuildCopiesRow;
    BuildButtons;
    LoadPrinters;
    RadioButtonAll.Checked := True;
    RadioButtonFit.Checked := True;
    EditFromPage.Text := '1';
    EditToPage.Text := '1';
    EditCopies.Text := '1';
  finally
    FIsLoading := False;
  end;
  UpdateState;
end;

function TPdf4DPrintDialogForm.AddRadioButton(const Parent: TWinControl; const Name, Caption: string; const Top: Integer): TRadioButton;
begin
  Result := TRadioButton.Create(Self);
  Result.Name := Name;
  Result.Parent := Parent;
  Result.SetBounds(Margin, Top, 100, RowHeight - 2);
  Result.Caption := Caption;
  Result.OnClick := HandleInputChange;
end;

function TPdf4DPrintDialogForm.AddEdit(const Parent: TWinControl; const Name: string; const Left, Top, Width: Integer): TEdit;
begin
  Result := TEdit.Create(Self);
  Result.Name := Name;
  Result.Parent := Parent;
  Result.SetBounds(Left, Top, Width, RowHeight);
  Result.NumbersOnly := True;
  Result.OnChange := HandleInputChange;
end;

procedure TPdf4DPrintDialogForm.BuildPrinterRow;
begin
  FLabelPrinter := TLabel.Create(Self);
  FLabelPrinter.Parent := Self;
  FLabelPrinter.SetBounds(Margin, Margin, 200, 16);
  FLabelPrinter.Caption := SPrintPrinterLabel;

  ComboBoxPrinter := TComboBox.Create(Self);
  ComboBoxPrinter.Name := 'ComboBoxPrinter';
  ComboBoxPrinter.Parent := Self;
  ComboBoxPrinter.Style := csDropDownList;
  ComboBoxPrinter.SetBounds(Margin, Margin + 18, 268, RowHeight);

  ButtonProperties := TButton.Create(Self);
  ButtonProperties.Name := 'ButtonProperties';
  ButtonProperties.Parent := Self;
  ButtonProperties.SetBounds(ComboBoxPrinter.Left + ComboBoxPrinter.Width + 8, ComboBoxPrinter.Top - 1, 96, RowHeight + 2);
  ButtonProperties.Caption := SPrintProperties;
  ButtonProperties.OnClick := HandlePropertiesClick;
end;

procedure TPdf4DPrintDialogForm.BuildRangeGroup;
begin
  FGroupBoxRange := TGroupBox.Create(Self);
  FGroupBoxRange.Parent := Self;
  FGroupBoxRange.SetBounds(Margin, 64, FormClientWidth - 2 * Margin, 112);
  FGroupBoxRange.Caption := SPrintRangeGroup;

  RadioButtonAll := AddRadioButton(FGroupBoxRange, 'RadioButtonAll', SPrintRangeAll, 20);
  RadioButtonAll.Width := 200;
  RadioButtonCurrent := AddRadioButton(FGroupBoxRange, 'RadioButtonCurrent', Format(SPrintRangeCurrent, [FCurrentPage + 1]), 44);
  RadioButtonCurrent.Width := 200;
  RadioButtonPages := AddRadioButton(FGroupBoxRange, 'RadioButtonPages', SPrintRangePages, 68);

  EditFromPage := AddEdit(FGroupBoxRange, 'EditFromPage', 120, 66, PageEditWidth);
  FLabelTo := TLabel.Create(Self);
  FLabelTo.Parent := FGroupBoxRange;
  FLabelTo.SetBounds(EditFromPage.Left + PageEditWidth + 8, 70, 24, 16);
  FLabelTo.Caption := SPrintRangeTo;
  EditToPage := AddEdit(FGroupBoxRange, 'EditToPage', FLabelTo.Left + 28, 66, PageEditWidth);
end;

procedure TPdf4DPrintDialogForm.BuildScaleGroup;
begin
  FGroupBoxScale := TGroupBox.Create(Self);
  FGroupBoxScale.Parent := Self;
  FGroupBoxScale.SetBounds(Margin, 184, FormClientWidth - 2 * Margin, 72);
  FGroupBoxScale.Caption := SPrintScaleGroup;

  RadioButtonFit := AddRadioButton(FGroupBoxScale, 'RadioButtonFit', SPrintScaleFit, 20);
  RadioButtonFit.Width := 200;
  RadioButtonActualSize := AddRadioButton(FGroupBoxScale, 'RadioButtonActualSize', SPrintScaleActualSize, 44);
  RadioButtonActualSize.Width := 200;
end;

procedure TPdf4DPrintDialogForm.BuildCopiesRow;
begin
  FLabelCopies := TLabel.Create(Self);
  FLabelCopies.Parent := Self;
  FLabelCopies.SetBounds(Margin, 268, 64, 16);
  FLabelCopies.Caption := SPrintCopiesLabel;

  EditCopies := AddEdit(Self, 'EditCopies', 80, 264, 56);

  UpDownCopies := TUpDown.Create(Self);
  UpDownCopies.Name := 'UpDownCopies';
  UpDownCopies.Parent := Self;
  UpDownCopies.Min := 1;
  UpDownCopies.Max := MaxPrintCopies;
  UpDownCopies.Associate := EditCopies;
  UpDownCopies.Position := 1;
end;

procedure TPdf4DPrintDialogForm.BuildButtons;
begin
  ButtonOk := TButton.Create(Self);
  ButtonOk.Name := 'ButtonOk';
  ButtonOk.Parent := Self;
  ButtonOk.SetBounds(FormClientWidth - 2 * 82 - Margin, FormClientHeight - 36, 75, 25);
  ButtonOk.Caption := SPrintOk;
  ButtonOk.Default := True;
  ButtonOk.ModalResult := mrOk;

  ButtonCancel := TButton.Create(Self);
  ButtonCancel.Name := 'ButtonCancel';
  ButtonCancel.Parent := Self;
  ButtonCancel.SetBounds(FormClientWidth - 82 - 5, FormClientHeight - 36, 75, 25);
  ButtonCancel.Caption := SPrintCancel;
  ButtonCancel.Cancel := True;
  ButtonCancel.ModalResult := mrCancel;
end;

procedure TPdf4DPrintDialogForm.LoadPrinters;
begin
  ComboBoxPrinter.Items.Clear;
  try
    ComboBoxPrinter.Items.Assign(Printer.Printers);
    ComboBoxPrinter.ItemIndex := Printer.PrinterIndex;
  except
    on EPrinter do
    begin
      // The machine has no printer: the list stays empty and printing reports the failure
      ComboBoxPrinter.Items.Clear;
    end;
  end;
  ComboBoxPrinter.Enabled := (ComboBoxPrinter.Items.Count > 0);
  ButtonProperties.Enabled := ComboBoxPrinter.Enabled;
end;

procedure TPdf4DPrintDialogForm.ApplyPrinter;
begin
  const HasChoice = (ComboBoxPrinter.ItemIndex >= 0);
  if HasChoice and (ComboBoxPrinter.ItemIndex <> Printer.PrinterIndex) then
  begin
    Printer.PrinterIndex := ComboBoxPrinter.ItemIndex;
  end;
end;

procedure TPdf4DPrintDialogForm.HandlePropertiesClick(Sender: TObject);
begin
  ApplyPrinter;

  const SetupDialog = TPrinterSetupDialog.Create(nil);
  try
    SetupDialog.Execute;
  finally
    SetupDialog.Free;
  end;

  LoadPrinters;
end;

procedure TPdf4DPrintDialogForm.HandleInputChange(Sender: TObject);
begin
  if not FIsLoading then
  begin
    UpdateState;
  end;
end;

function TPdf4DPrintDialogForm.TryReadNumber(const Edit: TEdit; out Value: Integer): Boolean;
begin
  Result := TryStrToInt(Trim(Edit.Text), Value);
end;

procedure TPdf4DPrintDialogForm.Load(const Settings: TPdfPrintSettings);
begin
  FIsLoading := True;
  try
    RadioButtonAll.Checked := (Settings.RangeKind = TPdfPrintRangeKind.All);
    RadioButtonCurrent.Checked := (Settings.RangeKind = TPdfPrintRangeKind.Current);
    RadioButtonPages.Checked := (Settings.RangeKind = TPdfPrintRangeKind.Pages);
    EditFromPage.Text := IntToStr(Settings.FromPage);
    EditToPage.Text := IntToStr(Settings.ToPage);
    RadioButtonFit.Checked := (Settings.Scale = TPdfPrintScale.Fit);
    RadioButtonActualSize.Checked := (Settings.Scale = TPdfPrintScale.ActualSize);
    EditCopies.Text := IntToStr(Settings.Copies);
    UpDownCopies.Position := Settings.Copies;
  finally
    FIsLoading := False;
  end;
  UpdateState;
end;

function TPdf4DPrintDialogForm.ReadSettings: TPdfPrintSettings;
begin
  Result := TPdfPrintSettings.Default;

  if RadioButtonCurrent.Checked then
  begin
    Result.RangeKind := TPdfPrintRangeKind.Current;
  end
  else if RadioButtonPages.Checked then
  begin
    Result.RangeKind := TPdfPrintRangeKind.Pages;
  end;

  var Number: Integer;
  if TryReadNumber(EditFromPage, Number) then
  begin
    Result.FromPage := Number;
  end;
  if TryReadNumber(EditToPage, Number) then
  begin
    Result.ToPage := Number;
  end;

  if RadioButtonActualSize.Checked then
  begin
    Result.Scale := TPdfPrintScale.ActualSize;
  end;

  if TryReadNumber(EditCopies, Number) then
  begin
    Result.Copies := Number;
  end;
end;

function TPdf4DPrintDialogForm.IsInputValid: Boolean;
begin
  var Copies: Integer;
  Result := TryReadNumber(EditCopies, Copies) and (Copies >= 1) and (Copies <= MaxPrintCopies);

  if Result and RadioButtonPages.Checked then
  begin
    var FromPage, ToPage: Integer;
    Result := TryReadNumber(EditFromPage, FromPage) and TryReadNumber(EditToPage, ToPage) and
              (FromPage >= 1) and (FromPage <= ToPage) and (ToPage <= FPageCount);
  end;
end;

procedure TPdf4DPrintDialogForm.UpdateState;
begin
  EditFromPage.Enabled := RadioButtonPages.Checked;
  EditToPage.Enabled := RadioButtonPages.Checked;
  ButtonOk.Enabled := IsInputValid;
end;

{ TPdf4DPrintProgressForm }

constructor TPdf4DPrintProgressForm.CreateFor(const OnCancel: TNotifyEvent);
begin
  inherited CreateNew(nil);
  FOnCancel := OnCancel;

  BorderStyle := bsDialog;
  Position := poScreenCenter;
  Caption := SPrintProgressCaption;
  ClientWidth := ProgressClientWidth;
  ClientHeight := ProgressClientHeight;
  OnCloseQuery := HandleCloseQuery;

  LabelStatus := TLabel.Create(Self);
  LabelStatus.Name := 'LabelStatus';
  LabelStatus.Parent := Self;
  LabelStatus.SetBounds(Margin, Margin, ProgressClientWidth - 2 * Margin, 16);
  LabelStatus.Caption := SPrintProgressStarting;

  ProgressBar := TProgressBar.Create(Self);
  ProgressBar.Name := 'ProgressBar';
  ProgressBar.Parent := Self;
  ProgressBar.SetBounds(Margin, 36, ProgressClientWidth - 2 * Margin, 20);

  ButtonCancel := TButton.Create(Self);
  ButtonCancel.Name := 'ButtonCancel';
  ButtonCancel.Parent := Self;
  ButtonCancel.SetBounds((ProgressClientWidth - 75) div 2, ProgressClientHeight - 38, 75, 25);
  ButtonCancel.Caption := SPrintCancel;
  ButtonCancel.OnClick := HandleCancelClick;
end;

procedure TPdf4DPrintProgressForm.SetProgress(const Printed, Total: Integer);
begin
  ProgressBar.Max := Total;
  ProgressBar.Position := Printed;
  LabelStatus.Caption := Format(SPrintProgressPage, [Min(Printed + 1, Total), Total]);
end;

procedure TPdf4DPrintProgressForm.HandleCancelClick(Sender: TObject);
begin
  ButtonCancel.Enabled := False;
  if Assigned(FOnCancel) then
  begin
    FOnCancel(Self);
  end;
end;

// The close button of the window is a cancel
procedure TPdf4DPrintProgressForm.HandleCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := FIsDismissed;
  if not FIsDismissed then
  begin
    HandleCancelClick(Self);
  end;
end;

procedure TPdf4DPrintProgressForm.Dismiss;
begin
  FIsDismissed := True;
  FOnCancel := nil;
  Release;
end;

{ TPdf4DPrintDialog }

constructor TPdf4DPrintDialog.Create(Owner: TComponent);
begin
  inherited Create(Owner);
  FSettings := TPdfPrintSettings.Default;
  FShowProgress := True;
  FMaxBandPixels := DefaultMaxBandPixels;
end;

destructor TPdf4DPrintDialog.Destroy;
begin
  // The job is cancelled by its destructor, without a callback
  FreeAndNil(FJob);
  FreeAndNil(FProgressForm);
  inherited;
end;

procedure TPdf4DPrintDialog.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = TOperation.opRemove) and (AComponent = FDocument) then
  begin
    FDocument := nil;
  end;
end;

procedure TPdf4DPrintDialog.SetDocument(const Value: TPdf4DCustomDocument);
begin
  if Value = FDocument then
  begin
    Exit;
  end;

  if Assigned(FDocument) then
  begin
    FDocument.RemoveFreeNotification(Self);
  end;

  FDocument := Value;

  if Assigned(FDocument) then
  begin
    FDocument.FreeNotification(Self);
  end;
end;

function TPdf4DPrintDialog.GetCopies: Integer;
begin
  Result := FSettings.Copies;
end;

procedure TPdf4DPrintDialog.SetCopies(const Value: Integer);
begin
  FSettings.Copies := Value;
end;

function TPdf4DPrintDialog.GetMaxDpi: Integer;
begin
  Result := FSettings.MaxDpi;
end;

procedure TPdf4DPrintDialog.SetMaxDpi(const Value: Integer);
begin
  FSettings.MaxDpi := Value;
end;

function TPdf4DPrintDialog.GetRangeKind: TPdfPrintRangeKind;
begin
  Result := FSettings.RangeKind;
end;

procedure TPdf4DPrintDialog.SetRangeKind(const Value: TPdfPrintRangeKind);
begin
  FSettings.RangeKind := Value;
end;

function TPdf4DPrintDialog.GetScale: TPdfPrintScale;
begin
  Result := FSettings.Scale;
end;

procedure TPdf4DPrintDialog.SetScale(const Value: TPdfPrintScale);
begin
  FSettings.Scale := Value;
end;

procedure TPdf4DPrintDialog.CheckCanPrint;
begin
  if not Assigned(FDocument) then
  begin
    raise EInvalidOpException.Create(SPrintNeedsDocument);
  end;
end;

function TPdf4DPrintDialog.CreateTarget: IPdfPrintTarget;
begin
  Result := TPdfVclPrinterTarget.Create(Printer);
end;

function TPdf4DPrintDialog.RunModal(const Form: TPdf4DPrintDialogForm): TModalResult;
begin
{$IFDEF PDF4D_TESTS}
  if Assigned(FModalRunner) then
  begin
    Exit(FModalRunner(Form));
  end;
{$ENDIF}
  Result := Form.ShowModal;
end;

function TPdf4DPrintDialog.Execute: Boolean;
begin
  CheckCanPrint;

  const Form = TPdf4DPrintDialogForm.CreateFor(FDocument.PageCount, FDocument.CurrentPage);
  try
    Form.Load(FSettings);
    Result := (RunModal(Form) = mrOk);
    if Result then
    begin
      Form.ApplyPrinter;
      const Chosen = Form.ReadSettings;
      FSettings.RangeKind := Chosen.RangeKind;
      FSettings.FromPage := Chosen.FromPage;
      FSettings.ToPage := Chosen.ToPage;
      FSettings.Scale := Chosen.Scale;
      FSettings.Copies := Chosen.Copies;
    end;
  finally
    Form.Free;
  end;

  if Result then
  begin
    Print(FSettings);
  end;
end;

function TPdf4DPrintDialog.IsPrinting: Boolean;
begin
  Result := Assigned(FJob);
end;

procedure TPdf4DPrintDialog.Print(const Settings: TPdfPrintSettings);
begin
  CheckCanPrint;
  if Assigned(FJob) then
  begin
    raise EInvalidOpException.Create(SPrintAlreadyRunning);
  end;

  var Prepared := Settings;
  if Prepared.Title = '' then
  begin
    Prepared.Title := TPath.GetFileName(TDocumentCracker(FDocument).FileName);
  end;

  // The job raises for a document that may not be printed and for a range that is not in the document
  FJob := TPdfPrintJob.Create(FDocument, CreateTarget, Prepared);
  FJob.MaxBandPixels := FMaxBandPixels;
  if FShowProgress then
  begin
    ShowProgressForm;
  end;

  // The job may end before Start returns: HandleDone has run then
  FJob.Start(HandleProgress, HandleDone);
end;

procedure TPdf4DPrintDialog.ShowProgressForm;
begin
  FProgressForm := TPdf4DPrintProgressForm.CreateFor(HandleCancelRequest);
  if Assigned(Screen.ActiveForm) then
  begin
    FProgressForm.PopupParent := Screen.ActiveForm;
  end;
  FProgressForm.Show;
end;

procedure TPdf4DPrintDialog.CloseProgressForm;
begin
  if Assigned(FProgressForm) then
  begin
    const Form = FProgressForm;
    FProgressForm := nil;
    Form.Dismiss;
  end;
end;

procedure TPdf4DPrintDialog.HandleProgress(const Printed, Total: Integer);
begin
  if Assigned(FProgressForm) then
  begin
    FProgressForm.SetProgress(Printed, Total);
  end;
end;

procedure TPdf4DPrintDialog.HandleCancelRequest(Sender: TObject);
begin
  if Assigned(FJob) then
  begin
    FJob.Cancel;
  end;
end;

procedure TPdf4DPrintDialog.HandleDone(const Status: TPdfPrintStatus; const ErrorMessage: string);
begin
  // The job still runs code after this returns: it is freed from the queue of the main thread
  const Job = FJob;
  FJob := nil;
  CloseProgressForm;
  System.Classes.TThread.ForceQueue(nil,
    procedure
    begin
      Job.Free;
    end);

  // After the events of this call
  if FIsFreeWhenDone then
  begin
    const Dialog = Self;
    System.Classes.TThread.ForceQueue(nil,
      procedure
      begin
        Dialog.Free;
      end);
  end;

  case Status of
    TPdfPrintStatus.Completed:
      if Assigned(FOnPrinted) then
      begin
        FOnPrinted(Self);
      end;
    TPdfPrintStatus.Failed:
      ReportFailure(ErrorMessage);
    TPdfPrintStatus.Cancelled:
      begin
        // The user asked for it: nothing to report
      end;
  else
    raise ENotSupportedException.CreateFmt('Unsupported print status: %d', [Ord(Status)]);
  end;
end;

procedure TPdf4DPrintDialog.ReportFailure(const ErrorMessage: string);
begin
  if Assigned(FOnPrintFailed) then
  begin
    FOnPrintFailed(Self, ErrorMessage);
  end
  else if FShowProgress then
  begin
    MessageDlg(Format(SPrintFailedMessage, [ErrorMessage]), mtError, [mbOk], 0);
  end;
end;

end.
