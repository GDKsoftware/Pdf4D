// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Vcl.Toolbar;

{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

uses
  System.Classes,
  System.Generics.Collections,
  Vcl.ActnList,
  Vcl.ComCtrls,
  Vcl.Controls,
  Vcl.ImgList,
  Vcl.StdCtrls,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.Document,
  Pdf4D.Vcl.PageView,
  Pdf4D.Vcl.SearchBar,
  Pdf4D.Vcl.PrintDialog,
  Pdf4D.Vcl.Actions;

type
  TPdf4DToolbarButton = (Navigation, PageNumber, Zoom, Rotate, Search, Print);
  TPdf4DToolbarButtons = set of TPdf4DToolbarButton;

  // A toolbar for a viewer: page navigation, a page number field, zoom, rotation, search and print. Its buttons run on actions of its
  // own that work on Document, PageView and SearchBar; the icons come from an image list that the toolbar makes, unless Images is set
  // to another list before the buttons are made.
  TPdf4DToolbar = class(TToolBar)
  private
    FDocument: TPdf4DCustomDocument;
    FPageView: TPdf4DPageView;
    FSearchBar: TPdf4DSearchBar;
    FButtons: TPdf4DToolbarButtons;
    FLink: TPdfDocumentLink;
    FIcons: TImageList;
    FIsBuilt: Boolean;
    FUsesOwnIcons: Boolean;

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

    // What the last build made
    FToolButtons: TList<TToolButton>;
    FPlaceholders: TList<TToolButton>;
    FEmbedded: TList<TControl>;
    FButtonFirst: TToolButton;
    FButtonPrior: TToolButton;
    FButtonNext: TToolButton;
    FButtonLast: TToolButton;
    FButtonZoomOut: TToolButton;
    FButtonZoomIn: TToolButton;
    FButtonRotateCounterclockwise: TToolButton;
    FButtonRotateClockwise: TToolButton;
    FButtonSearch: TToolButton;
    FButtonPrint: TToolButton;
    FEditPage: TEdit;
    FLabelPages: TLabel;
    FComboZoom: TComboBox;

    procedure SetDocument(const Value: TPdf4DCustomDocument);
    procedure SetPageView(const Value: TPdf4DPageView);
    procedure SetSearchBar(const Value: TPdf4DSearchBar);
    function GetPrintDialog: TPdf4DPrintDialog;
    procedure SetPrintDialog(const Value: TPdf4DPrintDialog);
    procedure SetButtons(const Value: TPdf4DToolbarButtons);

    procedure CreateActions;
    procedure CreateIcons;
    // Without them the actions have no icon: an image list of the application does not have these
    procedure UseOwnIcons(const IsUsed: Boolean);
    procedure Build;
    procedure ClearButtons;
    function NewButton(const Action: TCustomAction): TToolButton;
    function NewSeparator(const Width: Integer): TToolButton;
    procedure AddEmbedded(const Control: TControl; const Placeholder: TToolButton);
    procedure BuildNavigation;
    procedure BuildPageNumber;
    procedure BuildZoom;
    procedure BuildRotate;
    procedure BuildSearch;
    procedure BuildPrint;
    procedure PlaceEmbedded;
    procedure UpdateState;
    procedure UpdatePageNumber;
    procedure UpdateZoom;
    procedure HandleDocumentChange(const Change: TPdfDocumentChange);
    procedure HandleZoomChanged(Sender: TObject);

    procedure HandlePageKeyPress(Sender: TObject; var Key: Char);
    procedure HandlePageExit(Sender: TObject);
    procedure CommitPageNumber;
    procedure HandleZoomSelect(Sender: TObject);
    procedure HandleZoomKeyPress(Sender: TObject; var Key: Char);
    procedure ApplyZoomText(const Text: string);

  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure CreateWnd; override;
    procedure Loaded; override;
    procedure Resize; override;

  public
    constructor Create(Owner: TComponent); override;
    destructor Destroy; override;

    // The controls that the last build made; nil for a part that Buttons leaves out
    property ButtonFirst: TToolButton read FButtonFirst;
    property ButtonPrior: TToolButton read FButtonPrior;
    property ButtonNext: TToolButton read FButtonNext;
    property ButtonLast: TToolButton read FButtonLast;
    property ButtonZoomOut: TToolButton read FButtonZoomOut;
    property ButtonZoomIn: TToolButton read FButtonZoomIn;
    property ButtonRotateCounterclockwise: TToolButton read FButtonRotateCounterclockwise;
    property ButtonRotateClockwise: TToolButton read FButtonRotateClockwise;
    property ButtonSearch: TToolButton read FButtonSearch;
    property ButtonPrint: TToolButton read FButtonPrint;
    property EditPage: TEdit read FEditPage;
    property LabelPages: TLabel read FLabelPages;
    property ComboZoom: TComboBox read FComboZoom;

  published
    property Document: TPdf4DCustomDocument read FDocument write SetDocument;
    property PageView: TPdf4DPageView read FPageView write SetPageView;
    property SearchBar: TPdf4DSearchBar read FSearchBar write SetSearchBar;
    // The dialog that the print button shows; nil: the print action makes one of its own
    property PrintDialog: TPdf4DPrintDialog read GetPrintDialog write SetPrintDialog;
    property Buttons: TPdf4DToolbarButtons read FButtons write SetButtons default [Low(TPdf4DToolbarButton)..High(TPdf4DToolbarButton)];
  end;

implementation

{$R Icons\Pdf4D.Vcl.Icons.res}

uses
  System.Math,
  System.SysUtils,
  System.Types,
  Vcl.Graphics,
  Vcl.Imaging.pngimage,
  Winapi.Windows,
  Pdf4D.Viewer.ResourceStrings;

type
  // The order of the icons in the image list of the toolbar
  TToolbarIcon = (First, Prior, Next, Last, ZoomIn, ZoomOut, FitWidth, FitPage, RotateClockwise, RotateCounterclockwise, Search, Print, Copy);

const
  IconSize = 16;
  IconResourcePrefix = 'PDF4D_ICON_';
  PageEditWidth = 40;
  PageLabelWidth = 56;
  ZoomComboWidth = 96;
  EnterKey = #13;
  EscapeKey = #27;
  FirstZoomItems = 2;
  ZoomItemFitWidth = 0;
  ZoomItemFitPage = 1;
  // The same steps as the zoom commands of the page view
  ZoomPercentages: array[0..11] of Integer = (10, 25, 50, 75, 100, 125, 150, 200, 300, 400, 600, 800);
  PercentSign = '%';

function IconResourceName(const Icon: TToolbarIcon): string;
const
  Names: array[TToolbarIcon] of string = ('FIRST', 'PRIOR', 'NEXT', 'LAST', 'ZOOMIN', 'ZOOMOUT', 'FITWIDTH', 'FITPAGE',
                                          'ROTATECLOCKWISE', 'ROTATECOUNTERCLOCKWISE', 'SEARCH', 'PRINT', 'COPY');
begin
  Result := IconResourcePrefix + Names[Icon];
end;

function IndexOfPercentage(const Percentage: Integer): Integer;
begin
  Result := -1;
  for var Index := Low(ZoomPercentages) to High(ZoomPercentages) do
  begin
    if ZoomPercentages[Index] = Percentage then
    begin
      Exit(Index);
    end;
  end;
end;

{ TPdf4DToolbar }

constructor TPdf4DToolbar.Create(Owner: TComponent);
begin
  inherited Create(Owner);
  FButtons := [Low(TPdf4DToolbarButton)..High(TPdf4DToolbarButton)];
  FToolButtons := TList<TToolButton>.Create;
  FPlaceholders := TList<TToolButton>.Create;
  FEmbedded := TList<TControl>.Create;
  FLink := TPdfDocumentLink.Create(HandleDocumentChange);
  CreateIcons;
  CreateActions;
end;

destructor TPdf4DToolbar.Destroy;
begin
  if Assigned(FPageView) then
  begin
    FPageView.RemoveZoomListener(HandleZoomChanged);
  end;

  FLink.Free;
  FEmbedded.Free;
  FPlaceholders.Free;
  FToolButtons.Free;
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

procedure TPdf4DToolbar.CreateWnd;
begin
  inherited;
  if not FIsBuilt then
  begin
    Build;
  end;
end;

procedure TPdf4DToolbar.Loaded;
begin
  inherited;
  if (not FIsBuilt) and HandleAllocated then
  begin
    Build;
  end;
end;

procedure TPdf4DToolbar.Resize;
begin
  inherited;
  PlaceEmbedded;
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
  if FIsBuilt then
  begin
    Build;
  end;
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
  UseOwnIcons(True);
end;

procedure TPdf4DToolbar.CreateIcons;
begin
  FIcons := TImageList.Create(Self);
  FIcons.ColorDepth := cd32Bit;
  FIcons.Width := IconSize;
  FIcons.Height := IconSize;

  for var Icon := Low(TToolbarIcon) to High(TToolbarIcon) do
  begin
    const Png = TPngImage.Create;
    try
      Png.LoadFromResourceName(HInstance, IconResourceName(Icon));
      const Bitmap = Vcl.Graphics.TBitmap.Create;
      try
        Bitmap.PixelFormat := pf32bit;
        Bitmap.AlphaFormat := TAlphaFormat.afDefined;
        Bitmap.SetSize(IconSize, IconSize);
        for var Y := 0 to IconSize - 1 do
        begin
          const Pixels = PRGBQuad(Bitmap.ScanLine[Y]);
          const Colors = PByte(Png.Scanline[Y]);
          for var X := 0 to IconSize - 1 do
          begin
            const Alpha = Png.AlphaScanline[Y][X];
            // The image list wants the colors multiplied with the alpha
            const Pixel = PRGBQuad(PByte(Pixels) + X * SizeOf(TRGBQuad));
            Pixel.rgbBlue := (Colors[X * 3] * Alpha) div High(Byte);
            Pixel.rgbGreen := (Colors[X * 3 + 1] * Alpha) div High(Byte);
            Pixel.rgbRed := (Colors[X * 3 + 2] * Alpha) div High(Byte);
            Pixel.rgbReserved := Alpha;
          end;
        end;
        FIcons.Add(Bitmap, nil);
      finally
        Bitmap.Free;
      end;
    finally
      Png.Free;
    end;
  end;
end;

procedure TPdf4DToolbar.UseOwnIcons(const IsUsed: Boolean);
begin
  FUsesOwnIcons := IsUsed;
  const Unused = -1;
  FActionFirst.ImageIndex := IfThen(IsUsed, Ord(TToolbarIcon.First), Unused);
  FActionPrior.ImageIndex := IfThen(IsUsed, Ord(TToolbarIcon.Prior), Unused);
  FActionNext.ImageIndex := IfThen(IsUsed, Ord(TToolbarIcon.Next), Unused);
  FActionLast.ImageIndex := IfThen(IsUsed, Ord(TToolbarIcon.Last), Unused);
  FActionZoomIn.ImageIndex := IfThen(IsUsed, Ord(TToolbarIcon.ZoomIn), Unused);
  FActionZoomOut.ImageIndex := IfThen(IsUsed, Ord(TToolbarIcon.ZoomOut), Unused);
  FActionRotateClockwise.ImageIndex := IfThen(IsUsed, Ord(TToolbarIcon.RotateClockwise), Unused);
  FActionRotateCounterclockwise.ImageIndex := IfThen(IsUsed, Ord(TToolbarIcon.RotateCounterclockwise), Unused);
  FActionSearch.ImageIndex := IfThen(IsUsed, Ord(TToolbarIcon.Search), Unused);
  FActionPrint.ImageIndex := IfThen(IsUsed, Ord(TToolbarIcon.Print), Unused);
end;

{ Building }

procedure TPdf4DToolbar.ClearButtons;
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

  for var Control in FEmbedded do
  begin
    Control.Free;
  end;
  FEmbedded.Clear;

  for var Button in FToolButtons do
  begin
    Button.Free;
  end;
  FToolButtons.Clear;
  FPlaceholders.Clear;
end;

function TPdf4DToolbar.NewButton(const Action: TCustomAction): TToolButton;
begin
  Result := TToolButton.Create(Self);
  Result.Parent := Self;
  // Without the icons of the toolbar a button shows its text
  if not FUsesOwnIcons then
  begin
    Result.Style := tbsTextButton;
  end;
  Result.Action := Action;
  FToolButtons.Add(Result);
end;

function TPdf4DToolbar.NewSeparator(const Width: Integer): TToolButton;
begin
  Result := TToolButton.Create(Self);
  Result.Parent := Self;
  Result.Style := tbsSeparator;
  Result.Width := Width;
  FToolButtons.Add(Result);
end;

// A control sits on the separator that keeps its room in the row; both lists run in the order of the row
procedure TPdf4DToolbar.AddEmbedded(const Control: TControl; const Placeholder: TToolButton);
begin
  FEmbedded.Insert(0, Control);
  FPlaceholders.Insert(0, Placeholder);
end;

procedure TPdf4DToolbar.Build;
begin
  if not Assigned(Images) then
  begin
    Images := FIcons;
  end;
  UseOwnIcons(Images = FIcons);

  DisableAlign;
  try
    ClearButtons;
    // A new button goes to the front of the others, so the last one is made first
    if TPdf4DToolbarButton.Print in FButtons then
    begin
      BuildPrint;
    end;
    if TPdf4DToolbarButton.Search in FButtons then
    begin
      BuildSearch;
    end;
    if TPdf4DToolbarButton.Rotate in FButtons then
    begin
      BuildRotate;
    end;
    if TPdf4DToolbarButton.Zoom in FButtons then
    begin
      BuildZoom;
    end;
    if TPdf4DToolbarButton.PageNumber in FButtons then
    begin
      BuildPageNumber;
    end;
    if TPdf4DToolbarButton.Navigation in FButtons then
    begin
      BuildNavigation;
    end;
  finally
    EnableAlign;
  end;

  FIsBuilt := True;
  PlaceEmbedded;
  UpdateState;
end;

procedure TPdf4DToolbar.BuildNavigation;
begin
  FButtonLast := NewButton(FActionLast);
  FButtonNext := NewButton(FActionNext);
  FButtonPrior := NewButton(FActionPrior);
  FButtonFirst := NewButton(FActionFirst);
end;

procedure TPdf4DToolbar.BuildPageNumber;
begin
  FLabelPages := TLabel.Create(Self);
  FLabelPages.Parent := Self;
  FLabelPages.AutoSize := False;
  FLabelPages.Width := PageLabelWidth;
  FLabelPages.Layout := TTextLayout.tlCenter;
  AddEmbedded(FLabelPages, NewSeparator(FLabelPages.Width));

  FEditPage := TEdit.Create(Self);
  FEditPage.Parent := Self;
  FEditPage.Width := PageEditWidth;
  FEditPage.Alignment := taRightJustify;
  FEditPage.Hint := SPageNumberHint;
  FEditPage.ShowHint := True;
  FEditPage.OnKeyPress := HandlePageKeyPress;
  FEditPage.OnExit := HandlePageExit;
  AddEmbedded(FEditPage, NewSeparator(FEditPage.Width));
end;

procedure TPdf4DToolbar.BuildZoom;
begin
  FButtonZoomIn := NewButton(FActionZoomIn);

  FComboZoom := TComboBox.Create(Self);
  FComboZoom.Parent := Self;
  FComboZoom.Width := ZoomComboWidth;
  FComboZoom.Style := csDropDown;
  FComboZoom.Hint := SZoomHint;
  FComboZoom.ShowHint := True;
  FComboZoom.Items.Add(SZoomFitWidth);
  FComboZoom.Items.Add(SZoomFitPage);
  for var Percentage in ZoomPercentages do
  begin
    FComboZoom.Items.Add(Percentage.ToString + PercentSign);
  end;
  FComboZoom.OnSelect := HandleZoomSelect;
  FComboZoom.OnKeyPress := HandleZoomKeyPress;
  AddEmbedded(FComboZoom, NewSeparator(FComboZoom.Width));

  FButtonZoomOut := NewButton(FActionZoomOut);
end;

procedure TPdf4DToolbar.BuildRotate;
begin
  FButtonRotateClockwise := NewButton(FActionRotateClockwise);
  FButtonRotateCounterclockwise := NewButton(FActionRotateCounterclockwise);
  NewSeparator(ButtonWidth div 2);
end;

procedure TPdf4DToolbar.BuildSearch;
begin
  FButtonSearch := NewButton(FActionSearch);
end;

procedure TPdf4DToolbar.BuildPrint;
begin
  FButtonPrint := NewButton(FActionPrint);
end;

// The controls sit on the separators that keep their room in the row of buttons
procedure TPdf4DToolbar.PlaceEmbedded;
begin
  if (not FIsBuilt) or (FEmbedded.Count <> FPlaceholders.Count) then
  begin
    Exit;
  end;

  for var Index := 0 to FEmbedded.Count - 1 do
  begin
    const Control = FEmbedded[Index];
    const Placeholder = FPlaceholders[Index];
    Control.SetBounds(Placeholder.Left, Placeholder.Top + (Placeholder.Height - Control.Height) div 2, Control.Width, Control.Height);
  end;
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
  if not FIsBuilt then
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
  UpdatePageNumber;
  UpdateZoom;
end;

procedure TPdf4DToolbar.UpdatePageNumber;
begin
  if not Assigned(FEditPage) then
  begin
    Exit;
  end;

  const IsOpen = Assigned(FDocument) and (FDocument.State = TPdfDocumentState.Open);
  FEditPage.Enabled := IsOpen;
  if IsOpen then
  begin
    FEditPage.Text := (FDocument.CurrentPage + 1).ToString;
    FLabelPages.Caption := Format(SPageCountOf, [FDocument.PageCount]);
  end
  else
  begin
    FEditPage.Text := '';
    FLabelPages.Caption := Format(SPageCountOf, [0]);
  end;
end;

procedure TPdf4DToolbar.UpdateZoom;
begin
  if not Assigned(FComboZoom) then
  begin
    Exit;
  end;

  const HasView = Assigned(FPageView);
  FComboZoom.Enabled := HasView and Assigned(FPageView.Document) and (FPageView.Document.State = TPdfDocumentState.Open);
  if not HasView then
  begin
    FComboZoom.ItemIndex := -1;
    FComboZoom.Text := '';
    Exit;
  end;

  case FPageView.ZoomMode of
    TPdfZoomMode.FitWidth:
      FComboZoom.ItemIndex := ZoomItemFitWidth;
    TPdfZoomMode.FitPage:
      FComboZoom.ItemIndex := ZoomItemFitPage;
  else
    begin
      const Percentage = Round(FPageView.Zoom * 100);
      const Step = IndexOfPercentage(Percentage);
      // A zoom between the steps has no item
      if Step >= 0 then
      begin
        FComboZoom.ItemIndex := FirstZoomItems + Step;
      end
      else
      begin
        FComboZoom.ItemIndex := -1;
      end;
      FComboZoom.Text := Percentage.ToString + PercentSign;
    end;
  end;
end;

{ Page number }

procedure TPdf4DToolbar.HandlePageKeyPress(Sender: TObject; var Key: Char);
begin
  case Key of
    EnterKey:
      begin
        Key := #0;
        CommitPageNumber;
      end;
    EscapeKey:
      begin
        Key := #0;
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
  var Number := 0;
  var IsPage := Assigned(FDocument) and (FDocument.State = TPdfDocumentState.Open);
  if IsPage then
  begin
    IsPage := TryStrToInt(Trim(FEditPage.Text), Number) and InRange(Number, 1, FDocument.PageCount);
  end;

  if IsPage then
  begin
    FDocument.CurrentPage := Number - 1;
  end;

  // A valid number shows as it is written in the field; what is not a page of the document goes back to the current page
  UpdatePageNumber;
end;

{ Zoom }

procedure TPdf4DToolbar.HandleZoomSelect(Sender: TObject);
begin
  if FComboZoom.ItemIndex >= 0 then
  begin
    ApplyZoomText(FComboZoom.Items[FComboZoom.ItemIndex]);
  end;
end;

procedure TPdf4DToolbar.HandleZoomKeyPress(Sender: TObject; var Key: Char);
begin
  case Key of
    EnterKey:
      begin
        Key := #0;
        ApplyZoomText(FComboZoom.Text);
      end;
    EscapeKey:
      begin
        Key := #0;
        UpdateZoom;
      end;
  end;
end;

procedure TPdf4DToolbar.ApplyZoomText(const Text: string);
begin
  var Percentage: Double;
  const Trimmed = Text.Trim.TrimRight([PercentSign]).Trim;
  if not Assigned(FPageView) then
  begin
    UpdateZoom;
    Exit;
  end;

  if SameText(Text.Trim, SZoomFitWidth) then
  begin
    FPageView.ZoomMode := TPdfZoomMode.FitWidth;
  end
  else if SameText(Text.Trim, SZoomFitPage) then
  begin
    FPageView.ZoomMode := TPdfZoomMode.FitPage;
  end
  else if TryStrToFloat(Trimmed, Percentage) and (Percentage > 0) then
  begin
    FPageView.Zoom := Percentage / 100;
  end;

  // The page view tells a change of zoom, but not a change of mode, and not a text that was not valid
  UpdateZoom;
end;

end.
