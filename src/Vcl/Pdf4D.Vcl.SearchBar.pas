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
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.Document;

type
  // A query field with buttons to step through the hits, and the number of the current hit. Enter searches, or goes to the next hit
  // when the query did not change; Shift+Enter goes to the previous hit; Escape clears the search.
  TPdf4DSearchBar = class(TCustomPanel)
  private
    FDocument: TPdf4DCustomDocument;
    FLink: TPdfDocumentLink;
    FEditQuery: TEdit;
    FButtonPrior: TSpeedButton;
    FButtonNext: TSpeedButton;
    FCheckBoxMatchCase: TCheckBox;
    FLabelResult: TLabel;
    // What the last search looked for; a search was done when FHasSearched
    FHasSearched: Boolean;
    FLastQuery: string;
    FLastMatchCase: Boolean;

    procedure SetDocument(const Value: TPdf4DCustomDocument);
    procedure CreateControls;
    function NewButton(const Caption, Hint: string; const Left: Integer): TSpeedButton;
    procedure HandleDocumentChange(const Change: TPdfDocumentChange);

    procedure HandleQueryKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure HandleQueryKeyPress(Sender: TObject; var Key: Char);
    procedure HandlePriorClick(Sender: TObject);
    procedure HandleNextClick(Sender: TObject);
    procedure HandleMatchCaseClick(Sender: TObject);

    function CanSearch: Boolean;
    function IsSameSearch: Boolean;
    procedure StartSearch;
    // Goes to the next or previous hit of the search of the query, or starts that search
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
  System.Math,
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

  FLink := TPdfDocumentLink.Create(HandleDocumentChange);
  CreateControls;
end;

destructor TPdf4DSearchBar.Destroy;
begin
  FLink.Free;
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
    FLink.Document := nil;
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
  FHasSearched := False;

  if Assigned(FDocument) then
  begin
    FDocument.FreeNotification(Self);
  end;

  FLink.Document := Value;
  UpdateResult;
end;

procedure TPdf4DSearchBar.HandleDocumentChange(const Change: TPdfDocumentChange);
begin
  case Change of
    TPdfDocumentChange.Opening,
    TPdfDocumentChange.Opened,
    TPdfDocumentChange.OpenFailed,
    TPdfDocumentChange.Closed:
      begin
        // The search belongs to the document that was open
        FHasSearched := False;
        UpdateResult;
      end;
    TPdfDocumentChange.SearchResults,
    TPdfDocumentChange.CurrentSearchHit:
      UpdateResult;
    TPdfDocumentChange.CurrentPage,
    TPdfDocumentChange.Overlays:
      begin
        // Not of interest
      end;
  end;
end;

function TPdf4DSearchBar.CanSearch: Boolean;
begin
  Result := Assigned(FDocument) and (FDocument.State = TPdfDocumentState.Open);
end;

function TPdf4DSearchBar.IsSameSearch: Boolean;
begin
  Result := FHasSearched and (FEditQuery.Text = FLastQuery) and (FCheckBoxMatchCase.Checked = FLastMatchCase);
end;

procedure TPdf4DSearchBar.StartSearch;
begin
  FHasSearched := True;
  FLastQuery := FEditQuery.Text;
  FLastMatchCase := FCheckBoxMatchCase.Checked;
  FDocument.Search(FLastQuery, FLastMatchCase);
  UpdateResult;
end;

procedure TPdf4DSearchBar.Advance(const IsForward: Boolean);
begin
  if not CanSearch then
  begin
    Exit;
  end;

  if FEditQuery.Text = '' then
  begin
    ClearSearch;
  end
  else if IsSameSearch then
  begin
    if IsForward then
    begin
      FDocument.NextSearchHit;
    end
    else
    begin
      FDocument.PriorSearchHit;
    end;
  end
  else
  begin
    StartSearch;
  end;
end;

procedure TPdf4DSearchBar.ClearSearch;
begin
  FEditQuery.Clear;
  FHasSearched := False;
  FLastQuery := '';
  if Assigned(FDocument) then
  begin
    // An empty query takes the hits away and stops a search that is running
    FDocument.Search('', False);
  end;
  UpdateResult;
end;

procedure TPdf4DSearchBar.UpdateResult;
begin
  var Text := '';
  if Assigned(FDocument) and FHasSearched then
  begin
    const Count = Length(FDocument.SearchHits);
    if Count > 0 then
    begin
      var Index: Integer;
      var Hit: TPdfSearchHit;
      FDocument.TryGetCurrentSearchHit(Index, Hit);
      Text := Format(SSearchResultCount, [Max(Index, 0) + 1, Count]);
    end
    else if FDocument.IsSearching then
    begin
      Text := SSearching;
    end
    else
    begin
      Text := SSearchNoResults;
    end;
  end;
  FLabelResult.Caption := Text;
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
  if CanSearch and FHasSearched and (FEditQuery.Text <> '') then
  begin
    StartSearch;
  end;
end;

end.
