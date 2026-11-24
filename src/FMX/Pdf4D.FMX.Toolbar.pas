// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.FMX.Toolbar;

{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

uses
  System.Classes,
  System.Generics.Collections,
  FMX.ActnList,
  FMX.Controls,
  FMX.ComboEdit,
  FMX.Edit,
  FMX.ImgList,
  FMX.ListBox,
  FMX.StdCtrls,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.Document,
  Pdf4D.FMX.PageView,
  Pdf4D.FMX.SearchBar,
  Pdf4D.FMX.PrintDialog,
  Pdf4D.FMX.Actions;

type
  TPdf4DToolbarButton = (Navigation, PageNumber, Zoom, Rotate, Search, Print);
  TPdf4DToolbarButtons = set of TPdf4DToolbarButton;

  // A toolbar for a viewer: page navigation, a page number field, zoom, rotation, search and print. Its buttons run on actions of its
  // own that work on Document, PageView and SearchBar; the icons come from an image list that the toolbar makes. The zoom box is an editable
  // combo box: a zoom between the steps of the list shows as its text, and a typed zoom applies on Enter.
  TPdf4DToolbar = class(TToolBar)
  private type
    // The order of the icons in the image list of the toolbar
    TToolbarIcon = (First, Prior, Next, Last, ZoomIn, ZoomOut, FitWidth, FitPage, RotateClockwise, RotateCounterclockwise, Search, Print,
                    Copy);

    // A control of the row, with the space before it
    TRowItem = record
      Control: TControl;
      Gap: Single;
    end;

  private
    FDocument: TPdf4DCustomDocument;
    FPageView: TPdf4DPageView;
    FSearchBar: TPdf4DSearchBar;
    FButtons: TPdf4DToolbarButtons;
    FLink: TPdfDocumentLink;
    FIcons: TImageList;
    FIsBuilt: Boolean;
    FIsUpdatingZoom: Boolean;

    FActionFirst: TPdf4DFirstPageAction;
    FActionPrior: TPdf4DPriorPageAction;
    FActionNext: TPdf4DNextPageAction;
    FActionLast: TPdf4DLastPageAction;
    FActionZoomIn: TPdf4DZoomInAction;
    FActionZoomOut: TPdf4DZoomOutAction;
    FActionRotateCounterclockwise: TPdf4DRotateCounterclockwiseAction;
    FActionRotateClockwise: TPdf4DRotateClockwiseAction;
    FActionSearch: TPdf4DSearchAction;
    FActionPrint: TPdf4DPrintAction;

    // What the last build made, in the order of the row
    FRow: TList<TRowItem>;
    // The buttons that run an action: the button is the client of the action through its TagObject
    FActionButtons: TList<TSpeedButton>;
    FButtonFirst: TSpeedButton;
    FButtonPrior: TSpeedButton;
    FButtonNext: TSpeedButton;
    FButtonLast: TSpeedButton;
    FButtonZoomOut: TSpeedButton;
    FButtonZoomIn: TSpeedButton;
    FButtonRotateCounterclockwise: TSpeedButton;
    FButtonRotateClockwise: TSpeedButton;
    FButtonSearch: TSpeedButton;
    FButtonPrint: TSpeedButton;
    FEditPage: TEdit;
    FLabelPages: TLabel;
    FComboZoom: TComboEdit;

    class function IconResourceName(const Icon: TToolbarIcon): string; static;
    procedure SetDocument(const Value: TPdf4DCustomDocument);
    procedure SetPageView(const Value: TPdf4DPageView);
    procedure SetSearchBar(const Value: TPdf4DSearchBar);
    function GetPrintDialog: TPdf4DPrintDialog;
    procedure SetPrintDialog(const Value: TPdf4DPrintDialog);
    procedure SetButtons(const Value: TPdf4DToolbarButtons);

    procedure CreateActions;
    procedure CreateIcons;
    procedure Build;
    procedure ClearRow;
    procedure AddToRow(const Control: TControl; const Gap: Single = 0);
    procedure LayoutRow;
    function NewButton(const Name: string; const Action: TCustomAction; const Gap: Single = 0): TSpeedButton;
    procedure BuildNavigation;
    procedure BuildPageNumber;
    procedure BuildZoom;
    procedure BuildRotate;
    procedure BuildSearch;
    procedure BuildPrint;
    procedure UpdateState;
    procedure UpdatePageNumber;
    procedure UpdateZoom;
    procedure HandleDocumentChange(const Change: TPdfDocumentChange);
    procedure HandleZoomChanged(Sender: TObject);

    procedure HandleButtonClick(Sender: TObject);
    procedure HandlePageKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
    procedure HandlePageExit(Sender: TObject);
    procedure CommitPageNumber;
    procedure HandleZoomChange(Sender: TObject);
    procedure HandleZoomKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
    procedure ApplyZoomText(const Text: string);

  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Loaded; override;
    procedure Resize; override;

  public
    constructor Create(Owner: TComponent); override;
    destructor Destroy; override;

    // The controls that the last build made; nil for a part that Buttons leaves out
    property ButtonFirst: TSpeedButton read FButtonFirst;
    property ButtonPrior: TSpeedButton read FButtonPrior;
    property ButtonNext: TSpeedButton read FButtonNext;
    property ButtonLast: TSpeedButton read FButtonLast;
    property ButtonZoomOut: TSpeedButton read FButtonZoomOut;
    property ButtonZoomIn: TSpeedButton read FButtonZoomIn;
    property ButtonRotateCounterclockwise: TSpeedButton read FButtonRotateCounterclockwise;
    property ButtonRotateClockwise: TSpeedButton read FButtonRotateClockwise;
    property ButtonSearch: TSpeedButton read FButtonSearch;
    property ButtonPrint: TSpeedButton read FButtonPrint;
    property EditPage: TEdit read FEditPage;
    property LabelPages: TLabel read FLabelPages;
    property ComboZoom: TComboEdit read FComboZoom;
    // The icons of the buttons
    property Icons: TImageList read FIcons;
    // The number of controls in the row of the toolbar
    function RowCount: Integer;

  published
    property Document: TPdf4DCustomDocument read FDocument write SetDocument;
    property PageView: TPdf4DPageView read FPageView write SetPageView;
    property SearchBar: TPdf4DSearchBar read FSearchBar write SetSearchBar;
    // The dialog that the print button shows; nil: the print action makes one of its own
    property PrintDialog: TPdf4DPrintDialog read GetPrintDialog write SetPrintDialog;
    property Buttons: TPdf4DToolbarButtons read FButtons write SetButtons default [Low(TPdf4DToolbarButton)..High(TPdf4DToolbarButton)];
  end;

implementation

{$R Icons\Pdf4D.FMX.Icons.res}

uses
  System.SysUtils,
  System.Types,
  System.UITypes,
  FMX.Types,
  Pdf4D.Viewer.Commands,
  Pdf4D.Viewer.ResourceStrings;

const
  // Logical units
  IconSize = 16;
  ButtonSize = 28;
  FieldHeight = 24;
  RowMargin = 4;
  RowSpacing = 2;
  GroupGap = 8;
  PageEditWidth = 44;
  PageLabelWidth = 56;
  ZoomComboWidth = 104;

{ TPdf4DToolbar }

class function TPdf4DToolbar.IconResourceName(const Icon: TToolbarIcon): string;
const
  Names: array[TToolbarIcon] of string = ('FIRST', 'PRIOR', 'NEXT', 'LAST', 'ZOOMIN', 'ZOOMOUT', 'FITWIDTH', 'FITPAGE',
                                          'ROTATECLOCKWISE', 'ROTATECOUNTERCLOCKWISE', 'SEARCH', 'PRINT', 'COPY');
begin
  Result := 'PDF4D_FMX_ICON_' + Names[Icon];
end;

constructor TPdf4DToolbar.Create(Owner: TComponent);
begin
  inherited Create(Owner);
  FButtons := [Low(TPdf4DToolbarButton)..High(TPdf4DToolbarButton)];
  FRow := TList<TRowItem>.Create;
  FActionButtons := TList<TSpeedButton>.Create;
  FLink := TPdfDocumentLink.Create(HandleDocumentChange);
  CreateIcons;
  CreateActions;
  Build;
end;

destructor TPdf4DToolbar.Destroy;
begin
  if Assigned(FPageView) then
  begin
    FPageView.RemoveZoomListener(HandleZoomChanged);
  end;

  FLink.Free;
  FActionButtons.Free;
  FRow.Free;
  inherited;
end;

procedure TPdf4DToolbar.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if Operation <> TOperation.opRemove then
  begin
    Exit;
  end;

  if AComponent = FDocument then
  begin
    FDocument := nil;
    FLink.Document := nil;
  end
  else if AComponent = FPageView then
  begin
    FPageView.RemoveZoomListener(HandleZoomChanged);
    FPageView := nil;
  end
  else if AComponent = FSearchBar then
  begin
    FSearchBar := nil;
  end;
end;

procedure TPdf4DToolbar.Loaded;
begin
  inherited;
  UpdateState;
end;

procedure TPdf4DToolbar.Resize;
begin
  inherited;
  LayoutRow;
end;

function TPdf4DToolbar.RowCount: Integer;
begin
  Result := FRow.Count;
end;

{ Properties }

procedure TPdf4DToolbar.SetDocument(const Value: TPdf4DCustomDocument);
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

  FLink.Document := Value;
  FActionFirst.Document := Value;
  FActionPrior.Document := Value;
  FActionNext.Document := Value;
  FActionLast.Document := Value;
  FActionPrint.Document := Value;
  UpdateState;
end;

procedure TPdf4DToolbar.SetPageView(const Value: TPdf4DPageView);
begin
  if Value = FPageView then
  begin
    Exit;
  end;

  if Assigned(FPageView) then
  begin
    FPageView.RemoveZoomListener(HandleZoomChanged);
    FPageView.RemoveFreeNotification(Self);
  end;

  FPageView := Value;

  if Assigned(FPageView) then
  begin
    FPageView.FreeNotification(Self);
    FPageView.AddZoomListener(HandleZoomChanged);
  end;

  FActionZoomIn.PageView := Value;
  FActionZoomOut.PageView := Value;
  FActionRotateClockwise.PageView := Value;
  FActionRotateCounterclockwise.PageView := Value;
  UpdateState;
end;

procedure TPdf4DToolbar.SetSearchBar(const Value: TPdf4DSearchBar);
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

  FActionSearch.SearchBar := Value;
  UpdateState;
end;

function TPdf4DToolbar.GetPrintDialog: TPdf4DPrintDialog;
begin
  Result := FActionPrint.PrintDialog;
end;

procedure TPdf4DToolbar.SetPrintDialog(const Value: TPdf4DPrintDialog);
begin
  FActionPrint.PrintDialog := Value;
end;

procedure TPdf4DToolbar.SetButtons(const Value: TPdf4DToolbarButtons);
begin
  if Value = FButtons then
  begin
    Exit;
  end;

  FButtons := Value;
  Build;
end;

{ Actions and icons }

procedure TPdf4DToolbar.CreateActions;
begin
  FActionFirst := TPdf4DFirstPageAction.Create(Self);
  FActionPrior := TPdf4DPriorPageAction.Create(Self);
  FActionNext := TPdf4DNextPageAction.Create(Self);
  FActionLast := TPdf4DLastPageAction.Create(Self);
  FActionZoomIn := TPdf4DZoomInAction.Create(Self);
  FActionZoomOut := TPdf4DZoomOutAction.Create(Self);
  FActionRotateClockwise := TPdf4DRotateClockwiseAction.Create(Self);
  FActionRotateCounterclockwise := TPdf4DRotateCounterclockwiseAction.Create(Self);
  FActionSearch := TPdf4DSearchAction.Create(Self);
  FActionPrint := TPdf4DPrintAction.Create(Self);

  FActionFirst.ImageIndex := Ord(TToolbarIcon.First);
  FActionPrior.ImageIndex := Ord(TToolbarIcon.Prior);
  FActionNext.ImageIndex := Ord(TToolbarIcon.Next);
  FActionLast.ImageIndex := Ord(TToolbarIcon.Last);
  FActionZoomIn.ImageIndex := Ord(TToolbarIcon.ZoomIn);
  FActionZoomOut.ImageIndex := Ord(TToolbarIcon.ZoomOut);
  FActionRotateClockwise.ImageIndex := Ord(TToolbarIcon.RotateClockwise);
  FActionRotateCounterclockwise.ImageIndex := Ord(TToolbarIcon.RotateCounterclockwise);
  FActionSearch.ImageIndex := Ord(TToolbarIcon.Search);
  FActionPrint.ImageIndex := Ord(TToolbarIcon.Print);
end;

// The icons are 16 by 16 pixels with alpha; the image list scales them to the scale of the form
procedure TPdf4DToolbar.CreateIcons;
begin
  FIcons := TImageList.Create(Self);
  for var Icon := Low(TToolbarIcon) to High(TToolbarIcon) do
  begin
    const Stream = TResourceStream.Create(HInstance, IconResourceName(Icon), RT_RCDATA);
    try
      const Source = FIcons.Source.Add;
      Source.Name := IconResourceName(Icon);
      const Item = Source.MultiResBitmap.Add;
      Item.Scale := 1;
      Item.Bitmap.LoadFromStream(Stream);

      const Layer = FIcons.Destination.Add.Layers.Add;
      Layer.Name := Source.Name;
      Layer.SourceRect.Rect := TRectF.Create(0, 0, IconSize, IconSize);
    finally
      Stream.Free;
    end;
  end;
end;

{ Building }

procedure TPdf4DToolbar.ClearRow;
begin
  FButtonFirst := nil;
  FButtonPrior := nil;
  FButtonNext := nil;
  FButtonLast := nil;
  FButtonZoomOut := nil;
  FButtonZoomIn := nil;
  FButtonRotateCounterclockwise := nil;
  FButtonRotateClockwise := nil;
  FButtonSearch := nil;
  FButtonPrint := nil;
  FEditPage := nil;
  FLabelPages := nil;
  FComboZoom := nil;

  for var Item in FRow do
  begin
    Item.Control.Free;
  end;
  FRow.Clear;
  FActionButtons.Clear;
end;

procedure TPdf4DToolbar.AddToRow(const Control: TControl; const Gap: Single);
begin
  Control.Stored := False;
  Control.SetSubComponent(True);
  Control.Parent := Self;

  var Item: TRowItem;
  Item.Control := Control;
  Item.Gap := Gap;
  FRow.Add(Item);
end;

procedure TPdf4DToolbar.LayoutRow;
begin
  var Left: Single := RowMargin;
  for var Item in FRow do
  begin
    Left := Left + Item.Gap;
    Item.Control.SetBounds(Left, (Height - Item.Control.Height) / 2, Item.Control.Width, Item.Control.Height);
    Left := Left + Item.Control.Width + RowSpacing;
  end;
end;

// A button shows the icon of its action, not its text; the action is what it runs. The state of the action reaches the button in UpdateState.
function TPdf4DToolbar.NewButton(const Name: string; const Action: TCustomAction; const Gap: Single): TSpeedButton;
begin
  Result := TSpeedButton.Create(Self);
  Result.Name := Name;
  Result.Width := ButtonSize;
  Result.Height := ButtonSize;
  Result.Images := FIcons;
  Result.ImageIndex := Action.ImageIndex;
  Result.Hint := Action.Hint;
  Result.ShowHint := True;
  Result.TagObject := Action;
  Result.OnClick := HandleButtonClick;
  AddToRow(Result, Gap);
  FActionButtons.Add(Result);
end;

procedure TPdf4DToolbar.Build;
begin
  ClearRow;
  if TPdf4DToolbarButton.Navigation in FButtons then
  begin
    BuildNavigation;
  end;
  if TPdf4DToolbarButton.PageNumber in FButtons then
  begin
    BuildPageNumber;
  end;
  if TPdf4DToolbarButton.Zoom in FButtons then
  begin
    BuildZoom;
  end;
  if TPdf4DToolbarButton.Rotate in FButtons then
  begin
    BuildRotate;
  end;
  if TPdf4DToolbarButton.Search in FButtons then
  begin
    BuildSearch;
  end;
  if TPdf4DToolbarButton.Print in FButtons then
  begin
    BuildPrint;
  end;

  LayoutRow;
  FIsBuilt := True;
  UpdateState;
end;

procedure TPdf4DToolbar.BuildNavigation;
begin
  FButtonFirst := NewButton('ButtonFirst', FActionFirst);
  FButtonPrior := NewButton('ButtonPrior', FActionPrior);
  FButtonNext := NewButton('ButtonNext', FActionNext);
  FButtonLast := NewButton('ButtonLast', FActionLast);
end;

procedure TPdf4DToolbar.BuildPageNumber;
begin
  FEditPage := TEdit.Create(Self);
  FEditPage.Name := 'EditPage';
  FEditPage.Width := PageEditWidth;
  FEditPage.Height := FieldHeight;
  FEditPage.TextAlign := TTextAlign.Trailing;
  FEditPage.Hint := SPageNumberHint;
  FEditPage.ShowHint := True;
  FEditPage.OnKeyDown := HandlePageKeyDown;
  FEditPage.OnExit := HandlePageExit;
  AddToRow(FEditPage, GroupGap);

  FLabelPages := TLabel.Create(Self);
  FLabelPages.Name := 'LabelPages';
  FLabelPages.Width := PageLabelWidth;
  FLabelPages.Height := FieldHeight;
  FLabelPages.AutoSize := False;
  FLabelPages.WordWrap := False;
  FLabelPages.TextAlign := TTextAlign.Leading;
  FLabelPages.VertTextAlign := TTextAlign.Center;
  AddToRow(FLabelPages);
end;

procedure TPdf4DToolbar.BuildZoom;
begin
  FButtonZoomOut := NewButton('ButtonZoomOut', FActionZoomOut, GroupGap);

  FComboZoom := TComboEdit.Create(Self);
  FComboZoom.Name := 'ComboZoom';
  FComboZoom.Width := ZoomComboWidth;
  FComboZoom.Height := FieldHeight;
  FComboZoom.Hint := SZoomHint;
  FComboZoom.ShowHint := True;
  FComboZoom.Items.AddStrings(TPdfZoomText.Items);
  FComboZoom.OnChange := HandleZoomChange;
  FComboZoom.OnKeyDown := HandleZoomKeyDown;
  AddToRow(FComboZoom);

  FButtonZoomIn := NewButton('ButtonZoomIn', FActionZoomIn);
end;

procedure TPdf4DToolbar.BuildRotate;
begin
  FButtonRotateCounterclockwise := NewButton('ButtonRotateCounterclockwise', FActionRotateCounterclockwise, GroupGap);
  FButtonRotateClockwise := NewButton('ButtonRotateClockwise', FActionRotateClockwise);
end;

procedure TPdf4DToolbar.BuildSearch;
begin
  FButtonSearch := NewButton('ButtonSearch', FActionSearch, GroupGap);
end;

procedure TPdf4DToolbar.BuildPrint;
begin
  FButtonPrint := NewButton('ButtonPrint', FActionPrint);
end;

{ State }

procedure TPdf4DToolbar.HandleDocumentChange(const Change: TPdfDocumentChange);
begin
  UpdateState;
end;

procedure TPdf4DToolbar.HandleZoomChanged(Sender: TObject);
begin
  UpdateZoom;
end;

procedure TPdf4DToolbar.UpdateState;
begin
  if (not FIsBuilt) or (csDestroying in ComponentState) then
  begin
    Exit;
  end;

  FActionFirst.Update;
  FActionPrior.Update;
  FActionNext.Update;
  FActionLast.Update;
  FActionZoomIn.Update;
  FActionZoomOut.Update;
  FActionRotateClockwise.Update;
  FActionRotateCounterclockwise.Update;
  FActionSearch.Update;
  FActionPrint.Update;

  for var Button in FActionButtons do
  begin
    Button.Enabled := TCustomAction(Button.TagObject).Enabled;
  end;
  UpdatePageNumber;
  UpdateZoom;
end;

procedure TPdf4DToolbar.UpdatePageNumber;
begin
  if not Assigned(FEditPage) then
  begin
    Exit;
  end;

  FEditPage.Enabled := TPdfViewerCommands.IsOpen(FDocument);
  FEditPage.Text := TPdfViewerCommands.PageNumberText(FDocument);
  FLabelPages.Text := TPdfViewerCommands.PageCountText(FDocument);
end;

procedure TPdf4DToolbar.UpdateZoom;
begin
  if not Assigned(FComboZoom) then
  begin
    Exit;
  end;

  FIsUpdatingZoom := True;
  try
    const HasView = Assigned(FPageView);
    FComboZoom.Enabled := HasView and TPdfViewerCommands.IsOpen(FPageView.Document);
    if not HasView then
    begin
      FComboZoom.ItemIndex := -1;
      FComboZoom.Text := '';
      Exit;
    end;

    // A zoom between the steps has no item, only its text
    FComboZoom.ItemIndex := TPdfZoomText.IndexOf(FPageView.ZoomMode, FPageView.Zoom);
    FComboZoom.Text := TPdfZoomText.Format(FPageView.ZoomMode, FPageView.Zoom);
  finally
    FIsUpdatingZoom := False;
  end;
end;

{ Buttons }

procedure TPdf4DToolbar.HandleButtonClick(Sender: TObject);
begin
  TCustomAction(TSpeedButton(Sender).TagObject).Execute;
end;

{ Page number }

procedure TPdf4DToolbar.HandlePageKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
begin
  case Key of
    vkReturn:
      begin
        Key := 0;
        KeyChar := #0;
        CommitPageNumber;
      end;
    vkEscape:
      begin
        Key := 0;
        KeyChar := #0;
        UpdatePageNumber;
      end;
  end;
end;

procedure TPdf4DToolbar.HandlePageExit(Sender: TObject);
begin
  UpdatePageNumber;
end;

procedure TPdf4DToolbar.CommitPageNumber;
begin
  TPdfViewerCommands.TryGoToPageNumber(FDocument, FEditPage.Text);
  // A valid number shows as it is written in the field; what is not a page of the document goes back to the current page
  UpdatePageNumber;
end;

{ Zoom }

// Choosing an item and leaving the box after typing both end here; Enter applies the text at once
procedure TPdf4DToolbar.HandleZoomChange(Sender: TObject);
begin
  if not FIsUpdatingZoom then
  begin
    ApplyZoomText(FComboZoom.Text);
  end;
end;

procedure TPdf4DToolbar.HandleZoomKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
begin
  case Key of
    vkReturn:
      begin
        Key := 0;
        KeyChar := #0;
        ApplyZoomText(FComboZoom.Text);
      end;
    vkEscape:
      begin
        Key := 0;
        KeyChar := #0;
        UpdateZoom;
      end;
  end;
end;

procedure TPdf4DToolbar.ApplyZoomText(const Text: string);
begin
  var Mode: TPdfZoomMode;
  var Zoom: Single;
  const IsValid = Assigned(FPageView) and TPdfZoomText.TryParse(Text, Mode, Zoom);
  if IsValid and (Mode = TPdfZoomMode.Factor) then
  begin
    FPageView.Zoom := Zoom;
  end
  else if IsValid then
  begin
    FPageView.ZoomMode := Mode;
  end;

  // The page view tells a change of zoom or of its mode, but not a text that was not valid
  UpdateZoom;
end;

end.
