// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Vcl.Actions;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  Vcl.ActnList,
  Vcl.Controls,
  Pdf4D.Viewer.Document,
  Pdf4D.Viewer.Commands,
  Pdf4D.Vcl.PageView,
  Pdf4D.Vcl.SearchBar,
  Pdf4D.Vcl.PrintDialog;

type
  // An action on a page view: the one of PageView, or the page view that has the focus when PageView is nil. Enabled follows the
  // document of that page view when the action is updated. An OnExecute handler takes the place of the standard behavior. When the
  // command applies and what it does is in TPdfViewerCommands.
  TPdf4DPageViewAction = class(TCustomAction)
  private
    FPageView: TPdf4DPageView;

    // The page view that has the focus in the active form, or nil
    class function FocusedPageView: TPdf4DPageView; static;
    procedure SetPageView(const Value: TPdf4DPageView);
    // The page view to act on, or nil when there is none
    function ResolveView: TPdf4DPageView;
    function ViewOf(const Target: TObject): TPdf4DPageView;

  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;

    function Command: TPdfViewerCommand; virtual; abstract;
    // The standard behavior of the action: the command on the page view
    procedure Perform(const View: TPdf4DPageView); virtual;
    // Whether the command applies to the page view in its current state
    function IsApplicable(const View: TPdf4DPageView): Boolean;
    // A hook to set more of the state than Enabled, such as Checked
    procedure ApplyState(const View: TPdf4DPageView); virtual;

  public
    constructor Create(Owner: TComponent); override;
    function HandlesTarget(Target: TObject): Boolean; override;
    procedure ExecuteTarget(Target: TObject); override;
    procedure UpdateTarget(Target: TObject); override;
    function Execute: Boolean; override;
    function Update: Boolean; override;

  published
    property PageView: TPdf4DPageView read FPageView write SetPageView;
    property Caption;
    property Checked;
    property Enabled;
    property Hint;
    property ImageIndex;
    property ShortCut;
    property SecondaryShortCuts;
    property Visible;
    property OnExecute;
    property OnUpdate;
  end;

  TPdf4DZoomInAction = class(TPdf4DPageViewAction)
  protected
    function Command: TPdfViewerCommand; override;
  public
    constructor Create(Owner: TComponent); override;
  end;

  TPdf4DZoomOutAction = class(TPdf4DPageViewAction)
  protected
    function Command: TPdfViewerCommand; override;
  public
    constructor Create(Owner: TComponent); override;
  end;

  TPdf4DZoomFitWidthAction = class(TPdf4DPageViewAction)
  protected
    function Command: TPdfViewerCommand; override;
    procedure ApplyState(const View: TPdf4DPageView); override;
  public
    constructor Create(Owner: TComponent); override;
  end;

  TPdf4DZoomFitPageAction = class(TPdf4DPageViewAction)
  protected
    function Command: TPdfViewerCommand; override;
    procedure ApplyState(const View: TPdf4DPageView); override;
  public
    constructor Create(Owner: TComponent); override;
  end;

  TPdf4DRotateClockwiseAction = class(TPdf4DPageViewAction)
  protected
    function Command: TPdfViewerCommand; override;
  public
    constructor Create(Owner: TComponent); override;
  end;

  TPdf4DRotateCounterclockwiseAction = class(TPdf4DPageViewAction)
  protected
    function Command: TPdfViewerCommand; override;
  public
    constructor Create(Owner: TComponent); override;
  end;

  // Copies the selected text; enabled when there is a selection and the document allows copying. Its shortcut (Ctrl+C) works only while
  // the page view has the focus, so that Ctrl+C in an edit of the form copies the text of the edit.
  TPdf4DCopyAction = class(TPdf4DPageViewAction)
  protected
    function Command: TPdfViewerCommand; override;
    procedure Perform(const View: TPdf4DPageView); override;
  public
    constructor Create(Owner: TComponent); override;
    function HandleShortCut: Boolean; override;
  end;

  // An action on a document. It is disabled while Document is nil or not open.
  TPdf4DDocumentAction = class(TCustomAction)
  private
    FDocument: TPdf4DCustomDocument;

    procedure SetDocument(const Value: TPdf4DCustomDocument);

  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;

    function Command: TPdfViewerCommand; virtual; abstract;
    // The standard behavior of the action: the command on the document
    procedure Perform(const Document: TPdf4DCustomDocument); virtual;
    function IsApplicable(const Document: TPdf4DCustomDocument): Boolean;

  public
    function Execute: Boolean; override;
    function Update: Boolean; override;

  published
    property Document: TPdf4DCustomDocument read FDocument write SetDocument;
    property Caption;
    property Enabled;
    property Hint;
    property ImageIndex;
    property ShortCut;
    property SecondaryShortCuts;
    property Visible;
    property OnExecute;
    property OnUpdate;
  end;

  TPdf4DFirstPageAction = class(TPdf4DDocumentAction)
  protected
    function Command: TPdfViewerCommand; override;
  public
    constructor Create(Owner: TComponent); override;
  end;

  TPdf4DPriorPageAction = class(TPdf4DDocumentAction)
  protected
    function Command: TPdfViewerCommand; override;
  public
    constructor Create(Owner: TComponent); override;
  end;

  TPdf4DNextPageAction = class(TPdf4DDocumentAction)
  protected
    function Command: TPdfViewerCommand; override;
  public
    constructor Create(Owner: TComponent); override;
  end;

  TPdf4DLastPageAction = class(TPdf4DDocumentAction)
  protected
    function Command: TPdfViewerCommand; override;
  public
    constructor Create(Owner: TComponent); override;
  end;

  // Enabled when the document may be printed. It shows the print dialog of PrintDialog, or a print dialog of its own when that is nil, and
  // prints what the user chooses.
  TPdf4DPrintAction = class(TPdf4DDocumentAction)
  private
    FPrintDialog: TPdf4DPrintDialog;
    // The document that the action gave FPrintDialog; it is compared, never used
    FGivenDocument: TPdf4DCustomDocument;
    FFocusScope: TWinControl;

    procedure SetPrintDialog(const Value: TPdf4DPrintDialog);

  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    function Command: TPdfViewerCommand; override;
    procedure Perform(const Document: TPdf4DCustomDocument); override;

  public
    constructor Create(Owner: TComponent); override;
    function HandleShortCut: Boolean; override;

    // When set, the shortcut works only while the focus is inside this control. It must live as long as the action, as the viewer that
    // owns its actions does.
    property FocusScope: TWinControl read FFocusScope write FFocusScope;

  published
    property PrintDialog: TPdf4DPrintDialog read FPrintDialog write SetPrintDialog;
  end;

  // Shows the search bar and puts the cursor in its query field
  TPdf4DSearchAction = class(TCustomAction)
  private
    FSearchBar: TPdf4DSearchBar;
    FFocusScope: TWinControl;

    procedure SetSearchBar(const Value: TPdf4DSearchBar);

  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;

  public
    constructor Create(Owner: TComponent); override;
    function Execute: Boolean; override;
    function Update: Boolean; override;
    function HandleShortCut: Boolean; override;

    // When set, the shortcut works only while the focus is inside this control. It must live as long as the action, as the viewer that
    // owns its actions does.
    property FocusScope: TWinControl read FFocusScope write FFocusScope;

  published
    property SearchBar: TPdf4DSearchBar read FSearchBar write SetSearchBar;
    property Caption;
    property Enabled;
    property Hint;
    property ImageIndex;
    property ShortCut;
    property SecondaryShortCuts;
    property Visible;
    property OnExecute;
    property OnUpdate;
  end;

implementation

uses
  System.SysUtils,
  System.UITypes,
  Vcl.Forms,
  Vcl.Menus,
  Pdf4D.Viewer.ResourceStrings;

const
  // The code of the plus and minus key of the main keyboard
  PlusKey = $BB;
  MinusKey = $BD;
  PriorKey = $21;
  NextKey = $22;

type
  // What TCustomAction.Execute checks before it runs an action. A shortcut reaches Execute without these checks, and an action that does
  // not run returns False, so that the key goes on to the control that has the focus.
  TActionGate = class
  public
    class function MayRun(const Action: TCustomAction): Boolean; static;
    // True without a scope; else when the control with the focus is the scope or lies inside it
    class function IsFocusInside(const Scope: TWinControl): Boolean; static;
  end;

{ TActionGate }

class function TActionGate.MayRun(const Action: TCustomAction): Boolean;
begin
  if Action.Suspended then
  begin
    Exit(False);
  end;

  Action.Update;
  Result := Action.Enabled;
end;

class function TActionGate.IsFocusInside(const Scope: TWinControl): Boolean;
begin
  if not Assigned(Scope) then
  begin
    Exit(True);
  end;

  const Focused = Screen.ActiveControl;
  Result := Assigned(Focused) and ((Focused = Scope) or Scope.ContainsControl(Focused));
end;

{ TPdf4DPageViewAction }

class function TPdf4DPageViewAction.FocusedPageView: TPdf4DPageView;
begin
  Result := nil;
  const ActiveForm = Screen.ActiveCustomForm;
  if Assigned(ActiveForm) and (ActiveForm.ActiveControl is TPdf4DPageView) then
  begin
    Result := TPdf4DPageView(ActiveForm.ActiveControl);
  end;
end;

constructor TPdf4DPageViewAction.Create(Owner: TComponent);
begin
  inherited Create(Owner);
  DisableIfNoHandler := False;
end;

procedure TPdf4DPageViewAction.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = TOperation.opRemove) and (AComponent = FPageView) then
  begin
    FPageView := nil;
  end;
end;

procedure TPdf4DPageViewAction.SetPageView(const Value: TPdf4DPageView);
begin
  if Value = FPageView then
  begin
    Exit;
  end;

  if Assigned(FPageView) then
  begin
    FPageView.RemoveFreeNotification(Self);
  end;

  FPageView := Value;

  if Assigned(FPageView) then
  begin
    FPageView.FreeNotification(Self);
  end;
end;

function TPdf4DPageViewAction.ResolveView: TPdf4DPageView;
begin
  Result := FPageView;
  if not Assigned(Result) then
  begin
    Result := FocusedPageView;
  end;
end;

function TPdf4DPageViewAction.ViewOf(const Target: TObject): TPdf4DPageView;
begin
  Result := FPageView;
  if (not Assigned(Result)) and (Target is TPdf4DPageView) then
  begin
    Result := TPdf4DPageView(Target);
  end;
end;

function TPdf4DPageViewAction.HandlesTarget(Target: TObject): Boolean;
begin
  Result := Assigned(ViewOf(Target));
end;

procedure TPdf4DPageViewAction.ExecuteTarget(Target: TObject);
begin
  const View = ViewOf(Target);
  if Assigned(View) then
  begin
    Perform(View);
  end;
end;

procedure TPdf4DPageViewAction.UpdateTarget(Target: TObject);
begin
  const View = ViewOf(Target);
  if Assigned(View) then
  begin
    Enabled := IsApplicable(View);
    ApplyState(View);
  end;
end;

function TPdf4DPageViewAction.IsApplicable(const View: TPdf4DPageView): Boolean;
begin
  Result := TPdfViewerCommands.CanExecute(Command, View.Document, View.Controller);
end;

procedure TPdf4DPageViewAction.Perform(const View: TPdf4DPageView);
begin
  // An OnUpdate of the application may enable the action where the command does not apply
  if IsApplicable(View) then
  begin
    TPdfViewerCommands.Execute(Command, View.Document, View.Controller);
  end;
end;

procedure TPdf4DPageViewAction.ApplyState(const View: TPdf4DPageView);
begin
  // Nothing more by default
end;

function TPdf4DPageViewAction.Execute: Boolean;
begin
  if not TActionGate.MayRun(Self) then
  begin
    Exit(False);
  end;

  const View = ResolveView;
  if Assigned(OnExecute) or (not Assigned(View)) then
  begin
    Exit(inherited Execute);
  end;

  Perform(View);
  Result := True;
end;

function TPdf4DPageViewAction.Update: Boolean;
begin
  if Assigned(OnUpdate) then
  begin
    Exit(inherited Update);
  end;

  const View = ResolveView;
  if Assigned(View) then
  begin
    UpdateTarget(View);
  end
  else
  begin
    Enabled := False;
  end;
  Result := True;
end;

{ TPdf4DZoomInAction }

constructor TPdf4DZoomInAction.Create(Owner: TComponent);
begin
  inherited Create(Owner);
  Caption := SActionZoomIn;
  ShortCut := Vcl.Menus.ShortCut(PlusKey, [ssCtrl]);
  Hint := Format(SActionHintWithKey, [SActionZoomIn, ShortCutToText(ShortCut)]);
end;

function TPdf4DZoomInAction.Command: TPdfViewerCommand;
begin
  Result := TPdfViewerCommand.ZoomIn;
end;

{ TPdf4DZoomOutAction }

constructor TPdf4DZoomOutAction.Create(Owner: TComponent);
begin
  inherited Create(Owner);
  Caption := SActionZoomOut;
  ShortCut := Vcl.Menus.ShortCut(MinusKey, [ssCtrl]);
  Hint := Format(SActionHintWithKey, [SActionZoomOut, ShortCutToText(ShortCut)]);
end;

function TPdf4DZoomOutAction.Command: TPdfViewerCommand;
begin
  Result := TPdfViewerCommand.ZoomOut;
end;

{ TPdf4DZoomFitWidthAction }

constructor TPdf4DZoomFitWidthAction.Create(Owner: TComponent);
begin
  inherited Create(Owner);
  Caption := SZoomFitWidth;
  Hint := SActionFitWidthHint;
end;

function TPdf4DZoomFitWidthAction.Command: TPdfViewerCommand;
begin
  Result := TPdfViewerCommand.ZoomFitWidth;
end;

procedure TPdf4DZoomFitWidthAction.ApplyState(const View: TPdf4DPageView);
begin
  Checked := TPdfViewerCommands.IsChecked(Command, View.Controller);
end;

{ TPdf4DZoomFitPageAction }

constructor TPdf4DZoomFitPageAction.Create(Owner: TComponent);
begin
  inherited Create(Owner);
  Caption := SZoomFitPage;
  Hint := SActionFitPageHint;
end;

function TPdf4DZoomFitPageAction.Command: TPdfViewerCommand;
begin
  Result := TPdfViewerCommand.ZoomFitPage;
end;

procedure TPdf4DZoomFitPageAction.ApplyState(const View: TPdf4DPageView);
begin
  Checked := TPdfViewerCommands.IsChecked(Command, View.Controller);
end;

{ TPdf4DRotateClockwiseAction }

constructor TPdf4DRotateClockwiseAction.Create(Owner: TComponent);
begin
  inherited Create(Owner);
  Caption := SActionRotateClockwise;
  Hint := SActionRotateClockwise;
end;

function TPdf4DRotateClockwiseAction.Command: TPdfViewerCommand;
begin
  Result := TPdfViewerCommand.RotateClockwise;
end;

{ TPdf4DRotateCounterclockwiseAction }

constructor TPdf4DRotateCounterclockwiseAction.Create(Owner: TComponent);
begin
  inherited Create(Owner);
  Caption := SActionRotateCounterclockwise;
  Hint := SActionRotateCounterclockwise;
end;

function TPdf4DRotateCounterclockwiseAction.Command: TPdfViewerCommand;
begin
  Result := TPdfViewerCommand.RotateCounterclockwise;
end;

{ TPdf4DCopyAction }

constructor TPdf4DCopyAction.Create(Owner: TComponent);
begin
  inherited Create(Owner);
  Caption := SActionCopy;
  ShortCut := Vcl.Menus.ShortCut(Ord('C'), [ssCtrl]);
  Hint := Format(SActionHintWithKey, [SActionCopy, ShortCutToText(ShortCut)]);
end;

function TPdf4DCopyAction.Command: TPdfViewerCommand;
begin
  Result := TPdfViewerCommand.Copy;
end;

procedure TPdf4DCopyAction.Perform(const View: TPdf4DPageView);
begin
  View.CopyToClipboard;
end;

function TPdf4DCopyAction.HandleShortCut: Boolean;
begin
  const View = ResolveView;
  const HasFocus = Assigned(View) and View.Focused;
  Result := HasFocus and (inherited HandleShortCut);
end;

{ TPdf4DDocumentAction }

procedure TPdf4DDocumentAction.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = TOperation.opRemove) and (AComponent = FDocument) then
  begin
    FDocument := nil;
  end;
end;

procedure TPdf4DDocumentAction.SetDocument(const Value: TPdf4DCustomDocument);
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

function TPdf4DDocumentAction.IsApplicable(const Document: TPdf4DCustomDocument): Boolean;
begin
  Result := TPdfViewerCommands.CanExecute(Command, Document, nil);
end;

procedure TPdf4DDocumentAction.Perform(const Document: TPdf4DCustomDocument);
begin
  if IsApplicable(Document) then
  begin
    TPdfViewerCommands.Execute(Command, Document, nil);
  end;
end;

function TPdf4DDocumentAction.Execute: Boolean;
begin
  if not TActionGate.MayRun(Self) then
  begin
    Exit(False);
  end;

  if Assigned(OnExecute) or (not Assigned(FDocument)) then
  begin
    Exit(inherited Execute);
  end;

  Perform(FDocument);
  Result := True;
end;

function TPdf4DDocumentAction.Update: Boolean;
begin
  if Assigned(OnUpdate) then
  begin
    Exit(inherited Update);
  end;

  Enabled := IsApplicable(FDocument);
  Result := True;
end;

{ TPdf4DFirstPageAction }

constructor TPdf4DFirstPageAction.Create(Owner: TComponent);
begin
  inherited Create(Owner);
  Caption := SActionFirstPage;
  Hint := SActionFirstPage;
end;

function TPdf4DFirstPageAction.Command: TPdfViewerCommand;
begin
  Result := TPdfViewerCommand.FirstPage;
end;

{ TPdf4DPriorPageAction }

constructor TPdf4DPriorPageAction.Create(Owner: TComponent);
begin
  inherited Create(Owner);
  Caption := SActionPriorPage;
  Hint := Format(SActionHintWithKey, [SActionPriorPage, ShortCutToText(Vcl.Menus.ShortCut(PriorKey, []))]);
end;

function TPdf4DPriorPageAction.Command: TPdfViewerCommand;
begin
  Result := TPdfViewerCommand.PriorPage;
end;

{ TPdf4DNextPageAction }

constructor TPdf4DNextPageAction.Create(Owner: TComponent);
begin
  inherited Create(Owner);
  Caption := SActionNextPage;
  Hint := Format(SActionHintWithKey, [SActionNextPage, ShortCutToText(Vcl.Menus.ShortCut(NextKey, []))]);
end;

function TPdf4DNextPageAction.Command: TPdfViewerCommand;
begin
  Result := TPdfViewerCommand.NextPage;
end;

{ TPdf4DLastPageAction }

constructor TPdf4DLastPageAction.Create(Owner: TComponent);
begin
  inherited Create(Owner);
  Caption := SActionLastPage;
  Hint := SActionLastPage;
end;

function TPdf4DLastPageAction.Command: TPdfViewerCommand;
begin
  Result := TPdfViewerCommand.LastPage;
end;

{ TPdf4DPrintAction }

constructor TPdf4DPrintAction.Create(Owner: TComponent);
begin
  inherited Create(Owner);
  Caption := SActionPrint;
  ShortCut := Vcl.Menus.ShortCut(Ord('P'), [ssCtrl]);
  Hint := Format(SActionHintWithKey, [SActionPrint, ShortCutToText(ShortCut)]);
end;

procedure TPdf4DPrintAction.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = TOperation.opRemove) and (AComponent = FPrintDialog) then
  begin
    FPrintDialog := nil;
  end;
end;

procedure TPdf4DPrintAction.SetPrintDialog(const Value: TPdf4DPrintDialog);
begin
  if Value = FPrintDialog then
  begin
    Exit;
  end;

  if Assigned(FPrintDialog) then
  begin
    FPrintDialog.RemoveFreeNotification(Self);
  end;

  FPrintDialog := Value;

  if Assigned(FPrintDialog) then
  begin
    FPrintDialog.FreeNotification(Self);
  end;
end;

function TPdf4DPrintAction.HandleShortCut: Boolean;
begin
  Result := TActionGate.IsFocusInside(FFocusScope) and (inherited HandleShortCut);
end;

function TPdf4DPrintAction.Command: TPdfViewerCommand;
begin
  Result := TPdfViewerCommand.Print;
end;

procedure TPdf4DPrintAction.Perform(const Document: TPdf4DCustomDocument);
begin
  // A dialog of the application keeps the choices of the user for the next time. It prints the document of the action, unless the
  // application gave it another one.
  if Assigned(FPrintDialog) then
  begin
    const IsOurs = (not Assigned(FPrintDialog.Document)) or (FPrintDialog.Document = FGivenDocument);
    if IsOurs then
    begin
      FPrintDialog.Document := Document;
      FGivenDocument := Document;
    end;
    FPrintDialog.Execute;
    Exit;
  end;

  // The dialog of the action lives until its job is over, which is after this returns. The application owns it as well, so that a job
  // that still runs when the application ends does not leak.
  const Dialog = TPdf4DPrintDialog.Create(Application);
  var IsPrinting := False;
  try
    Dialog.Document := Document;
    if Dialog.Execute then
    begin
      IsPrinting := Dialog.IsPrinting;
    end;
  finally
    if IsPrinting then
    begin
      Dialog.FreeWhenDone := True;
    end
    else
    begin
      Dialog.Free;
    end;
  end;
end;

{ TPdf4DSearchAction }

constructor TPdf4DSearchAction.Create(Owner: TComponent);
begin
  inherited Create(Owner);
  DisableIfNoHandler := False;
  Caption := SActionSearch;
  ShortCut := Vcl.Menus.ShortCut(Ord('F'), [ssCtrl]);
  Hint := Format(SActionHintWithKey, [SActionSearch, ShortCutToText(ShortCut)]);
end;

procedure TPdf4DSearchAction.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = TOperation.opRemove) and (AComponent = FSearchBar) then
  begin
    FSearchBar := nil;
  end;
end;

procedure TPdf4DSearchAction.SetSearchBar(const Value: TPdf4DSearchBar);
begin
  if Value = FSearchBar then
  begin
    Exit;
  end;

  if Assigned(FSearchBar) then
  begin
    FSearchBar.RemoveFreeNotification(Self);
  end;

  FSearchBar := Value;

  if Assigned(FSearchBar) then
  begin
    FSearchBar.FreeNotification(Self);
  end;
end;

function TPdf4DSearchAction.Execute: Boolean;
begin
  if not TActionGate.MayRun(Self) then
  begin
    Exit(False);
  end;

  if Assigned(OnExecute) or (not Assigned(FSearchBar)) then
  begin
    Exit(inherited Execute);
  end;

  FSearchBar.Visible := True;
  FSearchBar.FocusQuery;
  Result := True;
end;

function TPdf4DSearchAction.HandleShortCut: Boolean;
begin
  Result := TActionGate.IsFocusInside(FFocusScope) and (inherited HandleShortCut);
end;

function TPdf4DSearchAction.Update: Boolean;
begin
  if Assigned(OnUpdate) then
  begin
    Exit(inherited Update);
  end;

  Enabled := Assigned(FSearchBar) and TPdfViewerCommands.CanExecute(TPdfViewerCommand.Search, FSearchBar.Document, nil);
  Result := True;
end;

end.
