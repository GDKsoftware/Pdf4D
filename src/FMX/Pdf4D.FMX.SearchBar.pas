// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.FMX.SearchBar;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.Types,
  System.UITypes,
  FMX.Edit,
  FMX.Layouts,
  FMX.StdCtrls,
  Pdf4D.Viewer.Document,
  Pdf4D.Viewer.SearchBarModel;

type
  // A query field with buttons to step through the hits, and the number of the current hit. Enter searches, or goes to the next hit
  // when the query did not change; Shift+Enter goes to the previous hit; Escape clears the search. A shell around TPdfSearchBarModel.
  TPdf4DSearchBar = class(TLayout)
  private
    FDocument: TPdf4DCustomDocument;
    FModel: TPdfSearchBarModel;
    FEditQuery: TEdit;
    FButtonPrior: TSpeedButton;
    FButtonNext: TSpeedButton;
    FCheckBoxMatchCase: TCheckBox;
    FLabelResult: TLabel;

    procedure SetDocument(const Value: TPdf4DCustomDocument);
    procedure CreateControls;
    function NewButton(const Name, Text, Hint: string; const Left: Single; const OnClick: TNotifyEvent): TSpeedButton;
    procedure HandleModelChanged(Sender: TObject);

    procedure HandleQueryKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
    procedure HandlePriorClick(Sender: TObject);
    procedure HandleNextClick(Sender: TObject);
    procedure HandleMatchCaseChange(Sender: TObject);

    procedure Advance(const IsForward: Boolean);
    procedure ClearSearch;
    procedure UpdateResult;

  protected
    function GetDefaultSize: TSizeF; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;

  public
    constructor Create(Owner: TComponent); override;
    destructor Destroy; override;

    procedure FocusQuery;

    property EditQuery: TEdit read FEditQuery;
    property ButtonPrior: TSpeedButton read FButtonPrior;
    property ButtonNext: TSpeedButton read FButtonNext;
    property CheckBoxMatchCase: TCheckBox read FCheckBoxMatchCase;
    property LabelResult: TLabel read FLabelResult;

  published
    property Document: TPdf4DCustomDocument read FDocument write SetDocument;
  end;

implementation

uses
  System.SysUtils,
  FMX.Types,
  Pdf4D.Viewer.ResourceStrings;

const
  // Logical units
  BarHeight = 28;
  ControlTop = 3;
  EditLeft = 4;
  EditWidth = 200;
  EditHeight = 22;
  ButtonWidth = 24;
  Gap = 4;
  CheckBoxWidth = 90;
  ResultWidth = 100;
  PriorCaption = '<';
  NextCaption = '>';
  BarWidth = EditLeft + EditWidth + Gap + 2 * (ButtonWidth + Gap) + CheckBoxWidth + Gap + ResultWidth;

{ TPdf4DSearchBar }

constructor TPdf4DSearchBar.Create(Owner: TComponent);
begin
  inherited Create(Owner);
  CreateControls;
  FModel := TPdfSearchBarModel.Create;
  FModel.OnChanged := HandleModelChanged;
end;

destructor TPdf4DSearchBar.Destroy;
begin
  SetDocument(nil);
  FreeAndNil(FModel);
  inherited;
end;

function TPdf4DSearchBar.GetDefaultSize: TSizeF;
begin
  Result := TSizeF.Create(BarWidth, BarHeight);
end;

function TPdf4DSearchBar.NewButton(const Name, Text, Hint: string; const Left: Single; const OnClick: TNotifyEvent): TSpeedButton;
begin
  Result := TSpeedButton.Create(Self);
  Result.Name := Name;
  Result.Stored := False;
  Result.SetSubComponent(True);
  Result.Parent := Self;
  Result.SetBounds(Left, ControlTop, ButtonWidth, EditHeight);
  Result.Text := Text;
  Result.Hint := Hint;
  Result.ShowHint := True;
  Result.OnClick := OnClick;
end;

procedure TPdf4DSearchBar.CreateControls;
begin
  FEditQuery := TEdit.Create(Self);
  FEditQuery.Name := 'EditQuery';
  FEditQuery.Stored := False;
  FEditQuery.SetSubComponent(True);
  FEditQuery.Parent := Self;
  FEditQuery.SetBounds(EditLeft, ControlTop, EditWidth, EditHeight);
  FEditQuery.OnKeyDown := HandleQueryKeyDown;

  var Left: Single := EditLeft + EditWidth + Gap;
  FButtonPrior := NewButton('ButtonPrior', PriorCaption, SSearchPriorHint, Left, HandlePriorClick);

  Left := Left + ButtonWidth + Gap;
  FButtonNext := NewButton('ButtonNext', NextCaption, SSearchNextHint, Left, HandleNextClick);

  Left := Left + ButtonWidth + Gap;
  FCheckBoxMatchCase := TCheckBox.Create(Self);
  FCheckBoxMatchCase.Name := 'CheckBoxMatchCase';
  FCheckBoxMatchCase.Stored := False;
  FCheckBoxMatchCase.SetSubComponent(True);
  FCheckBoxMatchCase.Parent := Self;
  FCheckBoxMatchCase.SetBounds(Left, ControlTop, CheckBoxWidth, EditHeight);
  FCheckBoxMatchCase.Text := SSearchMatchCase;
  FCheckBoxMatchCase.OnChange := HandleMatchCaseChange;

  Left := Left + CheckBoxWidth + Gap;
  FLabelResult := TLabel.Create(Self);
  FLabelResult.Name := 'LabelResult';
  FLabelResult.Stored := False;
  FLabelResult.SetSubComponent(True);
  FLabelResult.Parent := Self;
  FLabelResult.SetBounds(Left, ControlTop, ResultWidth, EditHeight);
  FLabelResult.Text := '';
end;

procedure TPdf4DSearchBar.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = TOperation.opRemove) and (AComponent = FDocument) then
  begin
    FDocument := nil;
    if Assigned(FModel) then
    begin
      FModel.Document := nil;
      ClearSearch;
    end;
  end;
end;

procedure TPdf4DSearchBar.SetDocument(const Value: TPdf4DCustomDocument);
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

  FModel.Document := Value;
end;

procedure TPdf4DSearchBar.HandleModelChanged(Sender: TObject);
begin
  UpdateResult;
end;

procedure TPdf4DSearchBar.Advance(const IsForward: Boolean);
begin
  FModel.Advance(FEditQuery.Text, FCheckBoxMatchCase.IsChecked, IsForward);
end;

procedure TPdf4DSearchBar.ClearSearch;
begin
  FEditQuery.Text := '';
  FModel.Clear;
end;

procedure TPdf4DSearchBar.UpdateResult;
begin
  FLabelResult.Text := FModel.ResultText;
end;

procedure TPdf4DSearchBar.FocusQuery;
begin
  if FEditQuery.CanFocus then
  begin
    FEditQuery.SetFocus;
    FEditQuery.SelectAll;
  end;
end;

{ Input }

// The edit would handle the characters of the keys that are used here too, so the key char goes with the key
procedure TPdf4DSearchBar.HandleQueryKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
begin
  case Key of
    vkReturn:
      begin
        Advance(not (ssShift in Shift));
        Key := 0;
        KeyChar := #0;
      end;
    vkEscape:
      begin
        ClearSearch;
        Key := 0;
        KeyChar := #0;
      end;
  end;
end;

procedure TPdf4DSearchBar.HandlePriorClick(Sender: TObject);
begin
  Advance(False);
end;

procedure TPdf4DSearchBar.HandleNextClick(Sender: TObject);
begin
  Advance(True);
end;

procedure TPdf4DSearchBar.HandleMatchCaseChange(Sender: TObject);
begin
  FModel.MatchCaseChanged(FEditQuery.Text, FCheckBoxMatchCase.IsChecked);
end;

end.
