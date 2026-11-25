// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Vcl.SearchBar;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.StdCtrls,
  Vcl.Buttons,
  Pdf4D.Viewer.Document,
  Pdf4D.Viewer.SearchBarModel;

type
  // A query field with buttons to step through the hits, and the number of the current hit. Enter searches, or goes to the next hit
  // when the query did not change; Shift+Enter goes to the previous hit; Escape clears the search. A shell around TPdfSearchBarModel.
  TPdf4DSearchBar = class(TCustomPanel)
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
    function NewButton(const Caption, Hint: string; const Left: Integer): TSpeedButton;
    procedure HandleModelChanged(Sender: TObject);

    procedure HandleQueryKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure HandleQueryKeyPress(Sender: TObject; var Key: Char);
    procedure HandlePriorClick(Sender: TObject);
    procedure HandleNextClick(Sender: TObject);
    procedure HandleMatchCaseClick(Sender: TObject);

    procedure Advance(const IsForward: Boolean);
    procedure ClearSearch;
    procedure UpdateResult;

  protected
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
    property Align;
    property Anchors;
    property Visible;
  end;

implementation

uses
  System.SysUtils,
  Winapi.Windows,
  Pdf4D.Viewer.ResourceStrings;

const
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
  EscapeKey = #27;
  EnterKey = #13;

{ TPdf4DSearchBar }

constructor TPdf4DSearchBar.Create(Owner: TComponent);
begin
  inherited Create(Owner);
  BevelOuter := bvNone;
  Caption := '';
  ShowCaption := False;
  Height := BarHeight;
  Width := EditLeft + EditWidth + Gap + 2 * (ButtonWidth + Gap) + CheckBoxWidth + Gap + ResultWidth;

  CreateControls;
  FModel := TPdfSearchBarModel.Create;
  FModel.OnChanged := HandleModelChanged;
end;

destructor TPdf4DSearchBar.Destroy;
begin
  FModel.Free;
  inherited;
end;

function TPdf4DSearchBar.NewButton(const Caption, Hint: string; const Left: Integer): TSpeedButton;
begin
  Result := TSpeedButton.Create(Self);
  Result.Parent := Self;
  Result.SetBounds(Left, ControlTop, ButtonWidth, EditHeight);
  Result.Caption := Caption;
  Result.Hint := Hint;
  Result.ShowHint := True;
  Result.Flat := True;
  Result.SetSubComponent(True);
end;

procedure TPdf4DSearchBar.CreateControls;
begin
  FEditQuery := TEdit.Create(Self);
  FEditQuery.Parent := Self;
  FEditQuery.Name := 'EditQuery';
  FEditQuery.SetBounds(EditLeft, ControlTop, EditWidth, EditHeight);
  FEditQuery.OnKeyDown := HandleQueryKeyDown;
  FEditQuery.OnKeyPress := HandleQueryKeyPress;
  FEditQuery.SetSubComponent(True);

  var Left := EditLeft + EditWidth + Gap;
  FButtonPrior := NewButton(PriorCaption, SSearchPriorHint, Left);
  FButtonPrior.Name := 'ButtonPrior';
  FButtonPrior.OnClick := HandlePriorClick;

  Inc(Left, ButtonWidth + Gap);
  FButtonNext := NewButton(NextCaption, SSearchNextHint, Left);
  FButtonNext.Name := 'ButtonNext';
  FButtonNext.OnClick := HandleNextClick;

  Inc(Left, ButtonWidth + Gap);
  FCheckBoxMatchCase := TCheckBox.Create(Self);
  FCheckBoxMatchCase.Parent := Self;
  FCheckBoxMatchCase.Name := 'CheckBoxMatchCase';
  FCheckBoxMatchCase.SetBounds(Left, ControlTop, CheckBoxWidth, EditHeight);
  FCheckBoxMatchCase.Caption := SSearchMatchCase;
  FCheckBoxMatchCase.OnClick := HandleMatchCaseClick;
  FCheckBoxMatchCase.SetSubComponent(True);

  Inc(Left, CheckBoxWidth + Gap);
  FLabelResult := TLabel.Create(Self);
  FLabelResult.Parent := Self;
  FLabelResult.Name := 'LabelResult';
  FLabelResult.AutoSize := False;
  FLabelResult.Layout := tlCenter;
  FLabelResult.SetBounds(Left, ControlTop, ResultWidth, EditHeight);
  FLabelResult.Caption := '';
  FLabelResult.SetSubComponent(True);
end;

procedure TPdf4DSearchBar.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = TOperation.opRemove) and (AComponent = FDocument) then
  begin
    FDocument := nil;
    FModel.Document := nil;
    ClearSearch;
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
  FModel.Advance(FEditQuery.Text, FCheckBoxMatchCase.Checked, IsForward);
end;

procedure TPdf4DSearchBar.ClearSearch;
begin
  FEditQuery.Clear;
  FModel.Clear;
end;

procedure TPdf4DSearchBar.UpdateResult;
begin
  FLabelResult.Caption := FModel.ResultText;
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

procedure TPdf4DSearchBar.HandleQueryKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_RETURN:
      begin
        Advance(not (ssShift in Shift));
        Key := 0;
      end;
    VK_ESCAPE:
      begin
        ClearSearch;
        Key := 0;
      end;
  end;
end;

// The edit would beep at the characters that the keys already handled
procedure TPdf4DSearchBar.HandleQueryKeyPress(Sender: TObject; var Key: Char);
begin
  if (Key = EnterKey) or (Key = EscapeKey) then
  begin
    Key := #0;
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

procedure TPdf4DSearchBar.HandleMatchCaseClick(Sender: TObject);
begin
  FModel.MatchCaseChanged(FEditQuery.Text, FCheckBoxMatchCase.Checked);
end;

end.
