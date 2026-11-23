// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Vcl.Viewer;

{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

uses
  System.Actions,
  System.Classes,
  System.SysUtils,
  Vcl.ActnList,
  Vcl.ComCtrls,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.Document,
  Pdf4D.Vcl.PageView,
  Pdf4D.Vcl.Thumbnails,
  Pdf4D.Vcl.OutlineView,
  Pdf4D.Vcl.SearchBar,
  Pdf4D.Vcl.Toolbar,
  Pdf4D.Vcl.Actions,
  Pdf4D.Vcl.PrintDialog;

type
  TPdf4DViewerOption = (Toolbar, Thumbnails, Outline, Search, Print);
  TPdf4DViewerOptions = set of TPdf4DViewerOption;

{$IFDEF PDF4D_TESTS}
  // For tests only: answers the question for the password. False: the user cancels.
  TPdf4DPasswordAsker = reference to function(out Password: string): Boolean;
{$ENDIF}

  // The whole viewer in one component: a toolbar on top, under it a search bar that is hidden until Ctrl+F, at the left a side panel
  // with the thumbnails and the outline, and the page view in the rest. Every part follows Document.
  TPdf4DViewer = class(TCustomPanel)
  private
    FDocument: TPdf4DCustomDocument;
    FOptions: TPdf4DViewerOptions;
    FAskPassword: Boolean;
    FPasswordAttempts: Integer;
    FIsReopening: Boolean;
    FLink: TPdfDocumentLink;
    FToolbar: TPdf4DToolbar;
    FSearchBar: TPdf4DSearchBar;
    FSidePanel: TPanel;
    FPageControl: TPageControl;
    FTabSheetPages: TTabSheet;
    FTabSheetBookmarks: TTabSheet;
    FThumbnails: TPdf4DThumbnails;
    FOutlineView: TPdf4DOutlineView;
    FSplitter: TSplitter;
    FPageView: TPdf4DPageView;
    FPrintDialog: TPdf4DPrintDialog;
    FActions: TActionList;
    FSearchAction: TPdf4DSearchAction;
{$IFDEF PDF4D_TESTS}
    class var FPasswordAsker: TPdf4DPasswordAsker;
{$ENDIF}

    procedure SetDocument(const Value: TPdf4DCustomDocument);
    procedure SetOptions(const Value: TPdf4DViewerOptions);
    function GetSidePanelWidth: Integer;
    procedure SetSidePanelWidth(const Value: Integer);
    function GetOnTextSelected: TPdfTextSelectedEvent;
    procedure SetOnTextSelected(const Value: TPdfTextSelectedEvent);
    function GetOnHoverChanged: TPdfHoverChangedEvent;
    procedure SetOnHoverChanged(const Value: TPdfHoverChangedEvent);
    function GetOnLinkClick: TPdfLinkClickEvent;
    procedure SetOnLinkClick(const Value: TPdfLinkClickEvent);

    procedure CreateParts;
    procedure CreateToolbar;
    procedure CreateSearchBar;
    procedure CreateSidePanel;
    procedure CreatePageView;
    procedure CreateSearchAction;
    procedure BuildTabs;
    procedure ApplyOptions;
    function ToolbarButtons: TPdf4DToolbarButtons;
    function HasOutline: Boolean;
    procedure UpdateSidePanel;
    procedure HandleDocumentChange(const Change: TPdfDocumentChange);
    function CanAskPassword: Boolean;
    procedure RequestPassword;
    function TryQueryPassword(out Password: string): Boolean;

  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure CreateWnd; override;
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
    // The side panel and its tabs
    property SidePanel: TPanel read FSidePanel;
    property PageControl: TPageControl read FPageControl;
    property TabSheetPages: TTabSheet read FTabSheetPages;
    property TabSheetBookmarks: TTabSheet read FTabSheetBookmarks;

  published
    property Document: TPdf4DCustomDocument read FDocument write SetDocument;
    property Options: TPdf4DViewerOptions read FOptions write SetOptions default [Low(TPdf4DViewerOption)..High(TPdf4DViewerOption)];
    // Pixels of the viewer, as Width is: a form from a .dfm scales it with the rest, a value set in code is not scaled
    property SidePanelWidth: Integer read GetSidePanelWidth write SetSidePanelWidth default 180;
    // True: a document that needs a password asks for it, at most three times
    property AskPassword: Boolean read FAskPassword write FAskPassword default True;
    // The events of the page view; their Sender is the page view
    property OnTextSelected: TPdfTextSelectedEvent read GetOnTextSelected write SetOnTextSelected;
    property OnHoverChanged: TPdfHoverChangedEvent read GetOnHoverChanged write SetOnHoverChanged;
    property OnLinkClick: TPdfLinkClickEvent read GetOnLinkClick write SetOnLinkClick;
    property Align;
    property Anchors;
    property TabOrder;
    property Visible;
  end;

implementation

uses
  Vcl.Dialogs,
  Pdf4D.Viewer.ResourceStrings;

type
  // The file name and the password of a document are for the owner of the document, and the viewer sets them to open it again
  TDocumentAccess = class(TPdf4DCustomDocument);

const
  DefaultSidePanelWidth = 180;
  SplitterWidth = 5;
  MinSidePanelWidth = 80;
  // Under the toolbar, whatever else is on top
  SearchBarTop = 10000;
  MaxPasswordAttempts = 3;
  // A prompt that starts with this makes InputQuery mask what is typed
  PasswordMask = #31;

{ TPdf4DViewer }

constructor TPdf4DViewer.Create(Owner: TComponent);
begin
  inherited Create(Owner);
  FOptions := [Low(TPdf4DViewerOption)..High(TPdf4DViewerOption)];
  FAskPassword := True;
  // The parts are its only controls: a designer does not drop others into it
  ControlStyle := ControlStyle - [csAcceptsControls, csSetCaption];
  BevelOuter := TBevelCut.bvNone;
  ShowCaption := False;
  Caption := '';
  Width := 640;
  Height := 480;

  FLink := TPdfDocumentLink.Create(HandleDocumentChange);
  CreateParts;
end;

destructor TPdf4DViewer.Destroy;
begin
  FLink.Free;
  inherited;
end;

{ Parts }

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
  CreateSearchAction;
end;

procedure TPdf4DViewer.CreateToolbar;
begin
  FToolbar := TPdf4DToolbar.Create(Self);
  FToolbar.Name := 'Toolbar';
  FToolbar.Parent := Self;
  FToolbar.Align := TAlign.alTop;
  FToolbar.Top := 0;
  FToolbar.SetSubComponent(True);
end;

procedure TPdf4DViewer.CreateSearchBar;
begin
  FSearchBar := TPdf4DSearchBar.Create(Self);
  FSearchBar.Name := 'SearchBar';
  FSearchBar.Parent := Self;
  FSearchBar.Align := TAlign.alTop;
  FSearchBar.Top := SearchBarTop;
  FSearchBar.Visible := False;
  FSearchBar.SetSubComponent(True);
end;

procedure TPdf4DViewer.CreateSidePanel;
begin
  FSidePanel := TPanel.Create(Self);
  FSidePanel.Parent := Self;
  FSidePanel.Align := TAlign.alLeft;
  FSidePanel.Width := DefaultSidePanelWidth;
  FSidePanel.BevelOuter := TBevelCut.bvNone;
  FSidePanel.ShowCaption := False;
  FSidePanel.Caption := '';

  FSplitter := TSplitter.Create(Self);
  FSplitter.Parent := Self;
  FSplitter.Align := TAlign.alLeft;
  FSplitter.Left := DefaultSidePanelWidth;
  FSplitter.Width := SplitterWidth;
  FSplitter.MinSize := MinSidePanelWidth;

  FPageControl := TPageControl.Create(Self);
  FPageControl.Parent := FSidePanel;
  FPageControl.Align := TAlign.alClient;

  FThumbnails := TPdf4DThumbnails.Create(Self);
  FThumbnails.Name := 'Thumbnails';
  FThumbnails.SetSubComponent(True);

  FOutlineView := TPdf4DOutlineView.Create(Self);
  FOutlineView.Name := 'OutlineView';
  FOutlineView.SetSubComponent(True);
end;

// A tab can be added to a page control only when it has a window, and that needs a window of the viewer
procedure TPdf4DViewer.BuildTabs;
begin
  if Assigned(FTabSheetPages) then
  begin
    Exit;
  end;

  FTabSheetPages := TTabSheet.Create(Self);
  FTabSheetPages.PageControl := FPageControl;
  FTabSheetPages.Caption := SViewerTabPages;
  FTabSheetBookmarks := TTabSheet.Create(Self);
  FTabSheetBookmarks.PageControl := FPageControl;
  FTabSheetBookmarks.Caption := SViewerTabBookmarks;

  FThumbnails.Parent := FTabSheetPages;
  FThumbnails.Align := TAlign.alClient;
  FOutlineView.Parent := FTabSheetBookmarks;
  FOutlineView.Align := TAlign.alClient;
end;

procedure TPdf4DViewer.CreatePageView;
begin
  FPageView := TPdf4DPageView.Create(Self);
  FPageView.Name := 'PageView';
  FPageView.Parent := Self;
  FPageView.Align := TAlign.alClient;
  FPageView.SetSubComponent(True);
end;

// The toolbar has actions of its own that know no shortcut keys, because they are in no action list: this one makes Ctrl+F work
// wherever the focus is in the form
procedure TPdf4DViewer.CreateSearchAction;
begin
  FActions := TActionList.Create(Self);
  FSearchAction := TPdf4DSearchAction.Create(Self);
  FSearchAction.ActionList := FActions;
  FSearchAction.SearchBar := FSearchBar;
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

// The parts need a window of the viewer to show and hide their tabs and buttons: CreateWnd does what was set before it
procedure TPdf4DViewer.ApplyOptions;
begin
  if not HandleAllocated then
  begin
    Exit;
  end;

  FToolbar.Visible := TPdf4DViewerOption.Toolbar in FOptions;
  FToolbar.Buttons := ToolbarButtons;

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
  if not HandleAllocated then
  begin
    Exit;
  end;

  const HasPages = TPdf4DViewerOption.Thumbnails in FOptions;
  const HasBookmarks = (TPdf4DViewerOption.Outline in FOptions) and HasOutline;

  FTabSheetPages.TabVisible := HasPages;
  FTabSheetBookmarks.TabVisible := HasBookmarks;
  if HasBookmarks and (not HasPages) then
  begin
    FPageControl.ActivePage := FTabSheetBookmarks;
  end
  else if HasPages and (not HasBookmarks) then
  begin
    FPageControl.ActivePage := FTabSheetPages;
  end;

  FSidePanel.Visible := HasPages or HasBookmarks;
  FSplitter.Visible := FSidePanel.Visible;
end;

function TPdf4DViewer.GetSidePanelWidth: Integer;
begin
  Result := FSidePanel.Width;
end;

procedure TPdf4DViewer.SetSidePanelWidth(const Value: Integer);
begin
  FSidePanel.Width := Value;
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
  FPageView.Document := Value;
  FToolbar.Document := Value;
  FThumbnails.Document := Value;
  FOutlineView.Document := Value;
  FSearchBar.Document := Value;
  FPrintDialog.Document := Value;
  FPasswordAttempts := 0;
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
  end;
end;

procedure TPdf4DViewer.CreateWnd;
begin
  inherited;
  BuildTabs;
  ApplyOptions;
end;

procedure TPdf4DViewer.Loaded;
begin
  inherited;
  ApplyOptions;
end;

procedure TPdf4DViewer.HandleDocumentChange(const Change: TPdfDocumentChange);
begin
  case Change of
    TPdfDocumentChange.Opening:
      begin
        if not FIsReopening then
        begin
          FPasswordAttempts := 0;
        end;
      end;
    TPdfDocumentChange.Opened:
      FPasswordAttempts := 0;
  end;

  case Change of
    TPdfDocumentChange.Opening, TPdfDocumentChange.Opened, TPdfDocumentChange.OpenFailed, TPdfDocumentChange.Closed:
      begin
        UpdateSidePanel;
        FSearchAction.Update;
      end;
  end;

  if (Change = TPdfDocumentChange.OpenFailed) and CanAskPassword then
  begin
    RequestPassword;
  end;
end;

{ Password }

// A document that was opened from a stream is gone once it has failed, so only a file can be opened again
function TPdf4DViewer.CanAskPassword: Boolean;
begin
  Result := FAskPassword and Assigned(FDocument) and (FDocument.OpenErrorKind = TPdfOpenErrorKind.InvalidPassword) and
            (FPasswordAttempts < MaxPasswordAttempts) and (not TDocumentAccess(FDocument).FileName.IsEmpty);
end;

function TPdf4DViewer.TryQueryPassword(out Password: string): Boolean;
begin
{$IFDEF PDF4D_TESTS}
  if Assigned(FPasswordAsker) then
  begin
    Exit(FPasswordAsker(Password));
  end;
{$ENDIF}
  Password := '';
  Result := InputQuery(SPasswordCaption, PasswordMask + SPasswordPrompt, Password);
end;

procedure TPdf4DViewer.RequestPassword;
begin
  Inc(FPasswordAttempts);

  var Password: string;
  if not TryQueryPassword(Password) then
  begin
    // The user does not want to open it: no more questions, and the failure stands
    FPasswordAttempts := MaxPasswordAttempts;
    Exit;
  end;

  // The failure of this attempt is not told to the owner of the document: this open takes its place
  TDocumentAccess(FDocument).Password := Password;
  FIsReopening := True;
  try
    FDocument.Open;
  finally
    FIsReopening := False;
  end;
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
