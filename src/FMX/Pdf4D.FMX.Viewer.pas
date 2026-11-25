// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.FMX.Viewer;

{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

uses
  System.Classes,
  System.SysUtils,
  System.UITypes,
  FMX.ActnList,
  FMX.Controls,
  FMX.Layouts,
  FMX.StdCtrls,
  FMX.TabControl,
  FMX.Types,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.Document,
  Pdf4D.Viewer.PasswordRetry,
  Pdf4D.FMX.PageView,
  Pdf4D.FMX.Thumbnails,
  Pdf4D.FMX.OutlineView,
  Pdf4D.FMX.SearchBar,
  Pdf4D.FMX.Toolbar,
  Pdf4D.FMX.Actions,
  Pdf4D.FMX.PrintDialog;

type
  TPdf4DViewerOption = (Toolbar, Thumbnails, Outline, Search, Print);
  TPdf4DViewerOptions = set of TPdf4DViewerOption;

{$IFDEF PDF4D_TESTS}
  // For tests only: answers the question for the password. False: the user cancels.
  TPdf4DPasswordAsker = function(out Password: string): Boolean of object;
{$ENDIF}

  // The whole viewer in one component: a toolbar on top, under it a search bar that is hidden until Ctrl+F, at the left a side panel
  // with the thumbnails and the outline, and the page view in the rest. Every part follows Document.
  TPdf4DViewer = class(TLayout)
  private
    FDocument: TPdf4DCustomDocument;
    FOptions: TPdf4DViewerOptions;
    FLink: TPdfDocumentLink;
    FPasswordRetry: TPdfPasswordRetry;
    FToolbar: TPdf4DToolbar;
    FSearchBar: TPdf4DSearchBar;
    FTabControl: TTabControl;
    FTabItemPages: TTabItem;
    FTabItemBookmarks: TTabItem;
    FThumbnails: TPdf4DThumbnails;
    FOutlineView: TPdf4DOutlineView;
    FSplitter: TSplitter;
    FPageView: TPdf4DPageView;
    FPrintDialog: TPdf4DPrintDialog;
    FActions: TActionList;
    FSearchAction: TPdf4DSearchAction;
    FPrintAction: TPdf4DPrintAction;
    // The key that the print action has while the print option is set
    FPrintShortCut: TShortCut;
{$IFDEF PDF4D_TESTS}
    class var FPasswordAsker: TPdf4DPasswordAsker;
{$ENDIF}

    procedure SetDocument(const Value: TPdf4DCustomDocument);
    procedure SetOptions(const Value: TPdf4DViewerOptions);
    function GetAskPassword: Boolean;
    procedure SetAskPassword(const Value: Boolean);
    function GetSidePanelWidth: Integer;
    procedure SetSidePanelWidth(const Value: Integer);
    function GetOnTextSelected: TPdfTextSelectedEvent;
    procedure SetOnTextSelected(const Value: TPdfTextSelectedEvent);
    function GetOnHoverChanged: TPdfHoverChangedEvent;
    procedure SetOnHoverChanged(const Value: TPdfHoverChangedEvent);
    function GetOnLinkClick: TPdfLinkClickEvent;
    procedure SetOnLinkClick(const Value: TPdfLinkClickEvent);

    // Makes a part of the viewer: owned by it, a child of Parent and not stored in a form file, because the constructor makes it
    function NewPart<T: TControl>(const Parent: TControl; const Name: string; const Align: TAlignLayout): T;
    procedure CreateParts;
    procedure CreateToolbar;
    procedure CreateSearchBar;
    procedure CreateSidePanel;
    procedure CreatePageView;
    procedure CreateActions;
    procedure ApplyOptions;
    function ToolbarButtons: TPdf4DToolbarButtons;
    function HasOutline: Boolean;
    procedure UpdateSidePanel;
    procedure HandleDocumentChange(const Change: TPdfDocumentChange);
    function TryQueryPassword(out Password: string): Boolean;

  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Loaded; override;

  public
    constructor Create(Owner: TComponent); override;
    destructor Destroy; override;

{$IFDEF PDF4D_TESTS}
    // For tests only, compiled when PDF4D_TESTS is defined: runs in place of the question for the password. Reset to nil afterwards.
    class property PasswordAsker: TPdf4DPasswordAsker read FPasswordAsker write FPasswordAsker;
{$ENDIF}

    // The parts, made by the constructor
    property PageView: TPdf4DPageView read FPageView;
    property Toolbar: TPdf4DToolbar read FToolbar;
    property Thumbnails: TPdf4DThumbnails read FThumbnails;
    property OutlineView: TPdf4DOutlineView read FOutlineView;
    property SearchBar: TPdf4DSearchBar read FSearchBar;
    property PrintDialog: TPdf4DPrintDialog read FPrintDialog;
    // The side panel with its tabs, and the splitter between it and the page view
    property TabControl: TTabControl read FTabControl;
    property TabItemPages: TTabItem read FTabItemPages;
    property TabItemBookmarks: TTabItem read FTabItemBookmarks;
    property Splitter: TSplitter read FSplitter;

  published
    property Document: TPdf4DCustomDocument read FDocument write SetDocument;
    property Options: TPdf4DViewerOptions read FOptions write SetOptions default [Low(TPdf4DViewerOption)..High(TPdf4DViewerOption)];
    // Logical units
    property SidePanelWidth: Integer read GetSidePanelWidth write SetSidePanelWidth default 180;
    // True: a document that needs a password asks for it, at most three times
    property AskPassword: Boolean read GetAskPassword write SetAskPassword default True;
    // The events of the page view; their Sender is the page view
    property OnTextSelected: TPdfTextSelectedEvent read GetOnTextSelected write SetOnTextSelected;
    property OnHoverChanged: TPdfHoverChangedEvent read GetOnHoverChanged write SetOnHoverChanged;
    property OnLinkClick: TPdfLinkClickEvent read GetOnLinkClick write SetOnLinkClick;
  end;

implementation

uses
  FMX.DialogService.Sync,
  Pdf4D.Viewer.ResourceStrings;

const
  DefaultSidePanelWidth = 180;
  SplitterWidth = 5;
  MinSidePanelWidth = 80;
  DefaultViewerWidth = 640;
  DefaultViewerHeight = 480;
  // A prompt that starts with this makes InputQuery mask what is typed
  PasswordMask = #31;

{ TPdf4DViewer }

constructor TPdf4DViewer.Create(Owner: TComponent);
begin
  inherited Create(Owner);
  FOptions := [Low(TPdf4DViewerOption)..High(TPdf4DViewerOption)];
  Width := DefaultViewerWidth;
  Height := DefaultViewerHeight;

  FLink := TPdfDocumentLink.Create(HandleDocumentChange);
  // The question of the retry runs inside the OpenFailed notification of the document
  FPasswordRetry := TPdfPasswordRetry.Create(
    function(out Password: string): Boolean
    begin
      Result := TryQueryPassword(Password);
    end);
  CreateParts;
  UpdateSidePanel;
end;

destructor TPdf4DViewer.Destroy;
begin
  FPasswordRetry.Free;
  FLink.Free;
  inherited;
end;

{ Parts }

function TPdf4DViewer.NewPart<T>(const Parent: TControl; const Name: string; const Align: TAlignLayout): T;
begin
  Result := T.Create(Self);
  if Name <> '' then
  begin
    Result.Name := Name;
  end;
  Result.Stored := False;
  Result.Parent := Parent;
  Result.Align := Align;
end;

// The order of creation is the order of alignment: the toolbar, the search bar under it, the side panel and the page view in the rest
procedure TPdf4DViewer.CreateParts;
begin
  CreateToolbar;
  CreateSearchBar;
  CreateSidePanel;
  CreatePageView;

  FPrintDialog := TPdf4DPrintDialog.Create(Self);
  FPrintDialog.Name := 'PrintDialog';
  FPrintDialog.SetSubComponent(True);

  FToolbar.PageView := FPageView;
  FToolbar.SearchBar := FSearchBar;
  FToolbar.PrintDialog := FPrintDialog;
  CreateActions;
end;

procedure TPdf4DViewer.CreateToolbar;
begin
  FToolbar := NewPart<TPdf4DToolbar>(Self, 'Toolbar', TAlignLayout.Top);
  FToolbar.SetSubComponent(True);
end;

procedure TPdf4DViewer.CreateSearchBar;
begin
  FSearchBar := NewPart<TPdf4DSearchBar>(Self, 'SearchBar', TAlignLayout.Top);
  FSearchBar.Visible := False;
  FSearchBar.SetSubComponent(True);
end;

procedure TPdf4DViewer.CreateSidePanel;
begin
  FTabControl := NewPart<TTabControl>(Self, '', TAlignLayout.Left);
  FTabControl.Width := DefaultSidePanelWidth;

  FSplitter := NewPart<TSplitter>(Self, '', TAlignLayout.Left);
  FSplitter.Width := SplitterWidth;
  FSplitter.MinSize := MinSidePanelWidth;

  FTabItemPages := TTabItem.Create(Self);
  FTabItemPages.Stored := False;
  FTabControl.AddObject(FTabItemPages);
  FTabItemPages.Text := SViewerTabPages;
  FTabItemBookmarks := TTabItem.Create(Self);
  FTabItemBookmarks.Stored := False;
  FTabControl.AddObject(FTabItemBookmarks);
  FTabItemBookmarks.Text := SViewerTabBookmarks;

  FThumbnails := NewPart<TPdf4DThumbnails>(FTabItemPages, 'Thumbnails', TAlignLayout.Client);
  FThumbnails.SetSubComponent(True);
  FOutlineView := NewPart<TPdf4DOutlineView>(FTabItemBookmarks, 'OutlineView', TAlignLayout.Client);
  FOutlineView.SetSubComponent(True);
end;

procedure TPdf4DViewer.CreatePageView;
begin
  FPageView := NewPart<TPdf4DPageView>(Self, 'PageView', TAlignLayout.Client);
  FPageView.SetSubComponent(True);
end;

// The toolbar has actions of its own that know no shortcut keys, because they are in no action list: these make Ctrl+F and Ctrl+P work
// while the focus is inside the viewer, so that two viewers on a form do not both react
procedure TPdf4DViewer.CreateActions;
begin
  FActions := TActionList.Create(Self);
  FSearchAction := TPdf4DSearchAction.Create(Self);
  FSearchAction.ActionList := FActions;
  FSearchAction.SearchBar := FSearchBar;
  FSearchAction.FocusScope := Self;

  FPrintAction := TPdf4DPrintAction.Create(Self);
  FPrintAction.ActionList := FActions;
  FPrintAction.PrintDialog := FPrintDialog;
  FPrintAction.FocusScope := Self;
  FPrintShortCut := FPrintAction.ShortCut;
end;

{ Options }

procedure TPdf4DViewer.SetOptions(const Value: TPdf4DViewerOptions);
begin
  if Value = FOptions then
  begin
    Exit;
  end;

  FOptions := Value;
  ApplyOptions;
end;

function TPdf4DViewer.ToolbarButtons: TPdf4DToolbarButtons;
begin
  Result := [Low(TPdf4DToolbarButton)..High(TPdf4DToolbarButton)];
  if not (TPdf4DViewerOption.Search in FOptions) then
  begin
    Exclude(Result, TPdf4DToolbarButton.Search);
  end;
  if not (TPdf4DViewerOption.Print in FOptions) then
  begin
    Exclude(Result, TPdf4DToolbarButton.Print);
  end;
end;

procedure TPdf4DViewer.ApplyOptions;
begin
  FToolbar.Visible := TPdf4DViewerOption.Toolbar in FOptions;
  FToolbar.Buttons := ToolbarButtons;
  if TPdf4DViewerOption.Print in FOptions then
  begin
    FPrintAction.ShortCut := FPrintShortCut;
  end
  else
  begin
    FPrintAction.ShortCut := 0;
  end;

  if TPdf4DViewerOption.Search in FOptions then
  begin
    FToolbar.SearchBar := FSearchBar;
    FSearchAction.SearchBar := FSearchBar;
  end
  else
  begin
    FToolbar.SearchBar := nil;
    FSearchAction.SearchBar := nil;
    FSearchBar.Visible := False;
  end;
  FSearchAction.Update;

  UpdateSidePanel;
end;

function TPdf4DViewer.HasOutline: Boolean;
begin
  Result := Assigned(FDocument) and (Length(FDocument.Outline) > 0);
end;

procedure TPdf4DViewer.UpdateSidePanel;
begin
  const HasPages = TPdf4DViewerOption.Thumbnails in FOptions;
  const HasBookmarks = (TPdf4DViewerOption.Outline in FOptions) and HasOutline;

  FTabItemPages.Visible := HasPages;
  FTabItemBookmarks.Visible := HasBookmarks;
  if HasBookmarks and (not HasPages) then
  begin
    FTabControl.ActiveTab := FTabItemBookmarks;
  end
  else if HasPages and (not HasBookmarks) then
  begin
    FTabControl.ActiveTab := FTabItemPages;
  end;

  FTabControl.Visible := HasPages or HasBookmarks;
  FSplitter.Visible := FTabControl.Visible;
end;

function TPdf4DViewer.GetSidePanelWidth: Integer;
begin
  Result := Round(FTabControl.Width);
end;

procedure TPdf4DViewer.SetSidePanelWidth(const Value: Integer);
begin
  FTabControl.Width := Value;
end;

{ Document }

procedure TPdf4DViewer.SetDocument(const Value: TPdf4DCustomDocument);
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
  // Before the parts: an attempt that fails for want of the password is retried before they hear of it
  FPasswordRetry.Document := Value;
  FPageView.Document := Value;
  FToolbar.Document := Value;
  FThumbnails.Document := Value;
  FOutlineView.Document := Value;
  FSearchBar.Document := Value;
  FPrintDialog.Document := Value;
  FPrintAction.Document := Value;
  UpdateSidePanel;
  FSearchAction.Update;
end;

procedure TPdf4DViewer.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = TOperation.opRemove) and (AComponent = FDocument) then
  begin
    FDocument := nil;
    FLink.Document := nil;
    FPasswordRetry.Document := nil;
  end;
end;

procedure TPdf4DViewer.Loaded;
begin
  inherited;
  ApplyOptions;
end;

procedure TPdf4DViewer.HandleDocumentChange(const Change: TPdfDocumentChange);
begin
  case Change of
    TPdfDocumentChange.Opening, TPdfDocumentChange.Opened, TPdfDocumentChange.OpenFailed, TPdfDocumentChange.Closed:
      begin
        UpdateSidePanel;
        FSearchAction.Update;
      end;
    TPdfDocumentChange.CurrentPage,
    TPdfDocumentChange.Overlays,
    TPdfDocumentChange.SearchResults,
    TPdfDocumentChange.CurrentSearchHit:
      begin
        // The side panel and the search action do not follow these
      end;
  else
    raise ENotSupportedException.CreateFmt('Unsupported document change: %d', [Ord(Change)]);
  end;
end;

{ Password }

function TPdf4DViewer.GetAskPassword: Boolean;
begin
  Result := FPasswordRetry.IsEnabled;
end;

procedure TPdf4DViewer.SetAskPassword(const Value: Boolean);
begin
  FPasswordRetry.IsEnabled := Value;
end;

function TPdf4DViewer.TryQueryPassword(out Password: string): Boolean;
begin
{$IFDEF PDF4D_TESTS}
  if Assigned(FPasswordAsker) then
  begin
    Exit(FPasswordAsker(Password));
  end;
{$ENDIF}
  var Answers: array of string;
  SetLength(Answers, 1);
  Result := TDialogServiceSync.InputQuery(SPasswordCaption, [PasswordMask + SPasswordPrompt], Answers);
  Password := Answers[0];
end;

{ Events of the page view }

function TPdf4DViewer.GetOnTextSelected: TPdfTextSelectedEvent;
begin
  Result := FPageView.OnTextSelected;
end;

procedure TPdf4DViewer.SetOnTextSelected(const Value: TPdfTextSelectedEvent);
begin
  FPageView.OnTextSelected := Value;
end;

function TPdf4DViewer.GetOnHoverChanged: TPdfHoverChangedEvent;
begin
  Result := FPageView.OnHoverChanged;
end;

procedure TPdf4DViewer.SetOnHoverChanged(const Value: TPdfHoverChangedEvent);
begin
  FPageView.OnHoverChanged := Value;
end;

function TPdf4DViewer.GetOnLinkClick: TPdfLinkClickEvent;
begin
  Result := FPageView.OnLinkClick;
end;

procedure TPdf4DViewer.SetOnLinkClick(const Value: TPdfLinkClickEvent);
begin
  FPageView.OnLinkClick := Value;
end;

end.
