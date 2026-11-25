// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.FMX.OutlineView;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.UITypes,
  FMX.TreeView,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.Document;

type
  // Shows the outline (the bookmarks) of a document as a tree; choosing an item that has a page shows that page. The Tag of an item is the
  // index of its entry in the outline of the document.
  TPdf4DOutlineView = class(TTreeView)
  private
    FDocument: TPdf4DCustomDocument;
    FLink: TPdfDocumentLink;
    FEntries: TArray<TPdfOutlineEntry>;
    FIsFilling: Boolean;

    procedure SetDocument(const Value: TPdf4DCustomDocument);
    procedure HandleDocumentChange(const Change: TPdfDocumentChange);
    procedure Fill;
    procedure Clear;
    procedure NavigateToSelected;

  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure DoChange; override;
    procedure Click; override;
    procedure KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState); override;

  public
    constructor Create(Owner: TComponent); override;
    destructor Destroy; override;

  published
    property Document: TPdf4DCustomDocument read FDocument write SetDocument;
  end;

implementation

uses
  System.Generics.Collections,
  System.Math,
  System.SysUtils;

{ TPdf4DOutlineView }

constructor TPdf4DOutlineView.Create(Owner: TComponent);
begin
  inherited Create(Owner);
  FLink := TPdfDocumentLink.Create(HandleDocumentChange);
end;

destructor TPdf4DOutlineView.Destroy;
begin
  FreeAndNil(FLink);
  inherited;
end;

procedure TPdf4DOutlineView.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = TOperation.opRemove) and (AComponent = FDocument) then
  begin
    FDocument := nil;
    if Assigned(FLink) then
    begin
      FLink.Document := nil;
      Clear;
    end;
  end;
end;

procedure TPdf4DOutlineView.SetDocument(const Value: TPdf4DCustomDocument);
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
  Clear;

  if Assigned(FDocument) then
  begin
    FDocument.FreeNotification(Self);
  end;

  FLink.Document := Value;

  // A document that is open already gives no change to catch up on
  const IsOpen = Assigned(Value) and (Value.State = TPdfDocumentState.Open);
  if IsOpen then
  begin
    Fill;
  end;
end;

procedure TPdf4DOutlineView.HandleDocumentChange(const Change: TPdfDocumentChange);
begin
  case Change of
    TPdfDocumentChange.Opened:
      Fill;
    TPdfDocumentChange.Opening,
    TPdfDocumentChange.OpenFailed,
    TPdfDocumentChange.Closed:
      Clear;
    TPdfDocumentChange.CurrentPage,
    TPdfDocumentChange.Overlays,
    TPdfDocumentChange.SearchResults,
    TPdfDocumentChange.CurrentSearchHit:
      begin
        // The outline does not follow these
      end;
  else
    raise ENotSupportedException.CreateFmt('Unsupported document change: %d', [Ord(Change)]);
  end;
end;

procedure TPdf4DOutlineView.Clear;
begin
  FIsFilling := True;
  try
    inherited Clear;
    FEntries := nil;
  finally
    FIsFilling := False;
  end;
end;

// The entries come in document order with their depth; an entry that is deeper than its predecessor allows hangs under the deepest
// node that there is
procedure TPdf4DOutlineView.Fill;
begin
  Clear;
  FEntries := FDocument.Outline;

  FIsFilling := True;
  BeginUpdate;
  try
    const Parents = TList<TTreeViewItem>.Create;
    try
      for var Index := 0 to High(FEntries) do
      begin
        const Item = TTreeViewItem.Create(Self);
        Item.Text := FEntries[Index].Title;
        Item.Tag := Index;

        const Level = Min(Max(FEntries[Index].Level, 0), Parents.Count);
        if Level = 0 then
        begin
          Item.Parent := Self;
        end
        else
        begin
          Item.Parent := Parents[Level - 1];
        end;

        Parents.Count := Level;
        Parents.Add(Item);
      end;
    finally
      Parents.Free;
    end;
  finally
    EndUpdate;
    FIsFilling := False;
  end;
end;

procedure TPdf4DOutlineView.NavigateToSelected;
begin
  const Item = Selected;
  if FIsFilling or (not Assigned(Item)) or (not Assigned(FDocument)) then
  begin
    Exit;
  end;

  const Index = Integer(Item.Tag);
  const HasEntry = (Index >= 0) and (Index < Length(FEntries));
  if HasEntry and FEntries[Index].HasPage then
  begin
    FDocument.CurrentPage := FEntries[Index].PageIndex;
  end;
end;

procedure TPdf4DOutlineView.DoChange;
begin
  inherited;
  NavigateToSelected;
end;

procedure TPdf4DOutlineView.Click;
begin
  inherited;
  NavigateToSelected;
end;

procedure TPdf4DOutlineView.KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
begin
  inherited;
  if Key = vkReturn then
  begin
    NavigateToSelected;
    Key := 0;
    KeyChar := #0;
  end;
end;

end.
