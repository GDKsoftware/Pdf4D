// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Vcl.OutlineView;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.Generics.Collections,
  Vcl.ComCtrls,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.Document;

type
  // Shows the outline (the bookmarks) of a document as a tree; choosing an item that has a page shows that page.
  TPdf4DOutlineView = class(TCustomTreeView)
  private
    FDocument: TPdf4DCustomDocument;
    FLink: TPdfDocumentLink;
    FEntries: TArray<TPdfOutlineEntry>;
    FIsFilling: Boolean;
    // The document was open while the view had no window; CreateWnd fills it
    FIsFillPending: Boolean;

    procedure SetDocument(const Value: TPdf4DCustomDocument);
    procedure HandleDocumentChange(const Change: TPdfDocumentChange);
    // Fills the tree now when it can have a window, else when it gets one
    procedure RequestFill;
    function CanHaveWindow: Boolean;
    procedure Fill;
    procedure Clear;
    procedure NavigateToSelected;

  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure CreateWnd; override;
    procedure Change(Node: TTreeNode); override;
    procedure Click; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;

  public
    constructor Create(Owner: TComponent); override;
    destructor Destroy; override;

    property Items;

  published
    property Document: TPdf4DCustomDocument read FDocument write SetDocument;
    property Align;
    property Anchors;
    property BorderStyle;
    property Color;
    property Enabled;
    property Font;
    property HideSelection default False;
    property Indent;
    property ParentColor default False;
    property ParentFont;
    property PopupMenu;
    property ReadOnly default True;
    property RowSelect;
    property ShowButtons;
    property ShowLines;
    property ShowRoot;
    property TabOrder;
    property TabStop default True;
    property Visible;
    property OnEnter;
    property OnExit;
  end;

implementation

uses
  System.Math,
  System.SysUtils,
  Winapi.Windows,
  Vcl.Controls,
  Vcl.Forms;

{ TPdf4DOutlineView }

constructor TPdf4DOutlineView.Create(Owner: TComponent);
begin
  inherited Create(Owner);
  ReadOnly := True;
  HideSelection := False;
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
    FLink.Document := nil;
    Clear;
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
    RequestFill;
  end;
end;

procedure TPdf4DOutlineView.HandleDocumentChange(const Change: TPdfDocumentChange);
begin
  case Change of
    TPdfDocumentChange.Opened:
      RequestFill;
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

procedure TPdf4DOutlineView.CreateWnd;
begin
  inherited;
  if FIsFillPending and Assigned(FDocument) and (FDocument.State = TPdfDocumentState.Open) then
  begin
    Fill;
  end;
end;

// A tree view adds its nodes through its window, which needs a parent chain that ends in a form or a parent window
function TPdf4DOutlineView.CanHaveWindow: Boolean;
begin
  if HandleAllocated then
  begin
    Exit(True);
  end;

  var Top: TWinControl := Self;
  while Assigned(Top.Parent) do
  begin
    Top := Top.Parent;
  end;
  Result := (Top is TCustomForm) or (Top.ParentWindow <> 0);
end;

procedure TPdf4DOutlineView.RequestFill;
begin
  if CanHaveWindow then
  begin
    Fill;
  end
  else
  begin
    Clear;
    FIsFillPending := True;
  end;
end;

procedure TPdf4DOutlineView.Clear;
begin
  FIsFillPending := False;
  FIsFilling := True;
  try
    Items.Clear;
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
  Items.BeginUpdate;
  try
    const Parents = TList<TTreeNode>.Create;
    try
      for var Index := 0 to High(FEntries) do
      begin
        const Level = Min(Max(FEntries[Index].Level, 0), Parents.Count);
        var Node: TTreeNode;
        if Level = 0 then
        begin
          Node := Items.Add(nil, FEntries[Index].Title);
        end
        else
        begin
          Node := Items.AddChild(Parents[Level - 1], FEntries[Index].Title);
        end;
        Node.Data := Pointer(NativeInt(Index));

        Parents.Count := Level;
        Parents.Add(Node);
      end;
    finally
      Parents.Free;
    end;
  finally
    Items.EndUpdate;
    FIsFilling := False;
  end;
end;

procedure TPdf4DOutlineView.NavigateToSelected;
begin
  const Node = Selected;
  if FIsFilling or (not Assigned(Node)) or (not Assigned(FDocument)) then
  begin
    Exit;
  end;

  const Index = Integer(NativeInt(Node.Data));
  const HasEntry = (Index >= 0) and (Index < Length(FEntries));
  if HasEntry and FEntries[Index].HasPage then
  begin
    FDocument.CurrentPage := FEntries[Index].PageIndex;
  end;
end;

procedure TPdf4DOutlineView.Change(Node: TTreeNode);
begin
  inherited;
  NavigateToSelected;
end;

procedure TPdf4DOutlineView.Click;
begin
  inherited;
  NavigateToSelected;
end;

procedure TPdf4DOutlineView.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited;
  if Key = VK_RETURN then
  begin
    NavigateToSelected;
    Key := 0;
  end;
end;

end.
