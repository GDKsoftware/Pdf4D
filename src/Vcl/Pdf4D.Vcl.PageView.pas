// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Vcl.PageView;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.Generics.Collections,
  System.Types,
  System.UITypes,
  Winapi.Messages,
  Vcl.Controls,
  Vcl.Graphics,
  Pdf4D.Common.Quad,
  Pdf4D.Api.Page.Interfaces,
  Pdf4D.Api.TextLayout.Interfaces,
  Pdf4D.Render.Bitmap,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.Document,
  Pdf4D.Viewer.Painter.Interfaces,
  Pdf4D.Viewer.PageViewController;

const
  DefaultHoverTColor: TColor = $00FF901E;
  DefaultHoverOpacity = $FF;
  DefaultSelectionTColor: TColor = $00FF9933;
  DefaultSelectionOpacity = $66;

type
  // Shows the pages of a document in a window. A thin shell around TPdfPageViewController: it turns window messages into calls on the
  // controller and the calls of the controller into scroll bars, cursors and painting.
  TPdf4DPageView = class(TCustomControl, IPdfViewHost)
  private
    FController: TPdfPageViewController;
    FDocument: TPdf4DCustomDocument;
    FHoverColor: TColor;
    FHoverOpacity: Byte;
    FSelectionColor: TColor;
    FSelectionOpacity: Byte;
    FOnTextSelected: TPdfTextSelectedEvent;
    FOnHoverChanged: TPdfHoverChangedEvent;
    FOnLinkClick: TPdfLinkClickEvent;
    FOnZoomChanged: TNotifyEvent;
    FZoomListeners: TList<TNotifyEvent>;
    // The pixels per inch that the last change of scale gave; 0 until there was one
    FScalePixelsPerInch: Integer;
    FIsUpdatingScrollBars: Boolean;
    FScrollBarsDirty: Boolean;

    procedure SetDocument(const Value: TPdf4DCustomDocument);
    function GetZoom: Single;
    procedure SetZoom(const Value: Single);
    function IsZoomStored: Boolean;
    function GetZoomMode: TPdfZoomMode;
    procedure SetZoomMode(const Value: TPdfZoomMode);
    function GetViewRotation: Integer;
    procedure SetViewRotation(const Value: Integer);
    function GetScrollMode: TPdfScrollMode;
    procedure SetScrollMode(const Value: TPdfScrollMode);
    function GetHoverEnabled: Boolean;
    procedure SetHoverEnabled(const Value: Boolean);
    function GetSelectionEnabled: Boolean;
    procedure SetSelectionEnabled(const Value: Boolean);
    function GetFollowInternalLinks: Boolean;
    procedure SetFollowInternalLinks(const Value: Boolean);
    procedure SetHoverColor(const Value: TColor);
    procedure SetHoverOpacity(const Value: Byte);
    procedure SetSelectionColor(const Value: TColor);
    procedure SetSelectionOpacity(const Value: Byte);

    class function ToAlphaColor(const Color: TColor; const Opacity: Byte): TAlphaColor; static;
    procedure ApplyColors;
    function PixelsPerInch: Integer;
    procedure UpdateViewport;
    procedure UpdateScrollBars;
    procedure ApplyScrollBar(const Bar: Integer; const ContentLength, ViewLength, Position: Integer);
    procedure HandleScroll(const Bar: Integer; const ScrollCode: Integer);
    function HandleKey(const Key: Word; const Shift: TShiftState): Boolean;
    class function ToViewerKey(const Key: Word; out ViewerKey: TPdfViewerKey): Boolean; static;

    procedure HandleTextSelected(Sender: TObject; const Selection: TPdfTextSelection);
    procedure HandleHoverChanged(Sender: TObject; const HasSegment: Boolean; const Segment: TPdfTextFragment);
    procedure HandleLinkClick(Sender: TObject; const Link: TPdfLink);
    procedure HandleZoomChanged(Sender: TObject);

    // IPdfViewHost
    procedure HostInvalidate(const Rect: TRect);
    procedure HostScrollStateChanged;
    procedure HostCursorChanged;
    function HostCreateImage(const Bitmap: TPdfBitmap): IPdfViewImage;
    procedure IPdfViewHost.Invalidate = HostInvalidate;
    procedure IPdfViewHost.ScrollStateChanged = HostScrollStateChanged;
    procedure IPdfViewHost.CursorChanged = HostCursorChanged;
    function IPdfViewHost.CreateImage = HostCreateImage;

    procedure WMHScroll(var Message: TWMHScroll); message WM_HSCROLL;
    procedure WMVScroll(var Message: TWMVScroll); message WM_VSCROLL;
    procedure WMGetDlgCode(var Message: TWMGetDlgCode); message WM_GETDLGCODE;
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;

  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure CreateWnd; override;
    procedure Loaded; override;
    procedure Paint; override;
    procedure Resize; override;
    procedure ChangeScale(M, D: Integer; isDpiChange: Boolean); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    // Puts text on the clipboard of the window system
    procedure WriteClipboardText(const Text: string); virtual;

  public
    constructor Create(Owner: TComponent); override;
    destructor Destroy; override;

    procedure ZoomIn;
    procedure ZoomOut;
    procedure RotateClockwise;
    procedure RotateCounterclockwise;
    procedure GoToPage(const PageIndex: Integer);
    procedure ScrollIntoView(const PageIndex: Integer; const Quads: TArray<TPdfQuad>);
    // The selected text; nothing without a selection or when the document does not allow copying
    procedure CopyToClipboard;
    // Several parties can follow the zoom, where OnZoomChanged is for the owner of the page view alone
    procedure AddZoomListener(const Listener: TNotifyEvent);
    procedure RemoveZoomListener(const Listener: TNotifyEvent);
    function TryGetSelection(out Selection: TPdfTextSelection): Boolean;

    // Owned
    property Controller: TPdfPageViewController read FController;

  published
    property Document: TPdf4DCustomDocument read FDocument write SetDocument;
    property ZoomMode: TPdfZoomMode read GetZoomMode write SetZoomMode default TPdfZoomMode.FitWidth;
    // 1.0 is the real size
    property Zoom: Single read GetZoom write SetZoom stored IsZoomStored;
    property ViewRotation: Integer read GetViewRotation write SetViewRotation default 0;
    property ScrollMode: TPdfScrollMode read GetScrollMode write SetScrollMode default TPdfScrollMode.Continuous;
    property HoverEnabled: Boolean read GetHoverEnabled write SetHoverEnabled default True;
    property SelectionEnabled: Boolean read GetSelectionEnabled write SetSelectionEnabled default True;
    property FollowInternalLinks: Boolean read GetFollowInternalLinks write SetFollowInternalLinks default True;
    property HoverColor: TColor read FHoverColor write SetHoverColor default $00FF901E;
    property HoverOpacity: Byte read FHoverOpacity write SetHoverOpacity default DefaultHoverOpacity;
    property SelectionColor: TColor read FSelectionColor write SetSelectionColor default $00FF9933;
    property SelectionOpacity: Byte read FSelectionOpacity write SetSelectionOpacity default DefaultSelectionOpacity;
    property OnTextSelected: TPdfTextSelectedEvent read FOnTextSelected write FOnTextSelected;
    property OnHoverChanged: TPdfHoverChangedEvent read FOnHoverChanged write FOnHoverChanged;
    property OnLinkClick: TPdfLinkClickEvent read FOnLinkClick write FOnLinkClick;
    property OnZoomChanged: TNotifyEvent read FOnZoomChanged write FOnZoomChanged;
    property Align;
    property Anchors;
    property TabOrder;
    property TabStop default True;
    property Visible;
    property PopupMenu;
    property OnEnter;
    property OnExit;
  end;

implementation

uses
  System.Math,
  Winapi.Windows,
  Vcl.Clipbrd,
  Vcl.Forms,
  Pdf4D.Vcl.Painter;

const
  InitialSize = 200;
  LogicalPixelsPerInch = 96;
  // Logical pixels
  LineScrollStep = 40;
  MaxScrollBarRounds = 4;
  ColorByteMask = $FF;
  AlphaShift = 24;
  RedShift = 16;
  GreenShift = 8;
  VkZero = Ord('0');
  VkLetterA = Ord('A');
  VkLetterC = Ord('C');

{ TPdf4DPageView }

constructor TPdf4DPageView.Create(Owner: TComponent);
begin
  inherited Create(Owner);
  ControlStyle := ControlStyle + [csOpaque];
  TabStop := True;
  DoubleBuffered := True;
  Width := InitialSize;
  Height := InitialSize;

  FHoverColor := DefaultHoverTColor;
  FHoverOpacity := DefaultHoverOpacity;
  FSelectionColor := DefaultSelectionTColor;
  FSelectionOpacity := DefaultSelectionOpacity;

  FZoomListeners := TList<TNotifyEvent>.Create;
  FController := TPdfPageViewController.Create(Self);
  FController.OnTextSelected := HandleTextSelected;
  FController.OnHoverChanged := HandleHoverChanged;
  FController.OnLinkClick := HandleLinkClick;
  FController.OnZoomChanged := HandleZoomChanged;
  ApplyColors;
end;

destructor TPdf4DPageView.Destroy;
begin
  FOnTextSelected := nil;
  FOnHoverChanged := nil;
  FOnLinkClick := nil;
  FOnZoomChanged := nil;
  SetDocument(nil);
  FController.Free;
  FZoomListeners.Free;
  inherited;
end;

procedure TPdf4DPageView.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = TOperation.opRemove) and (AComponent = FDocument) then
  begin
    FDocument := nil;
    FController.Document := nil;
  end;
end;

procedure TPdf4DPageView.SetDocument(const Value: TPdf4DCustomDocument);
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

  FController.Document := Value;
end;

function TPdf4DPageView.GetZoom: Single;
begin
  Result := FController.Zoom;
end;

procedure TPdf4DPageView.SetZoom(const Value: Single);
begin
  FController.Zoom := Value;
end;

function TPdf4DPageView.IsZoomStored: Boolean;
begin
  Result := (FController.ZoomMode = TPdfZoomMode.Factor);
end;

function TPdf4DPageView.GetZoomMode: TPdfZoomMode;
begin
  Result := FController.ZoomMode;
end;

procedure TPdf4DPageView.SetZoomMode(const Value: TPdfZoomMode);
begin
  FController.ZoomMode := Value;
end;

function TPdf4DPageView.GetViewRotation: Integer;
begin
  Result := FController.ViewRotation;
end;

procedure TPdf4DPageView.SetViewRotation(const Value: Integer);
begin
  FController.ViewRotation := Value;
end;

function TPdf4DPageView.GetScrollMode: TPdfScrollMode;
begin
  Result := FController.ScrollMode;
end;

procedure TPdf4DPageView.SetScrollMode(const Value: TPdfScrollMode);
begin
  FController.ScrollMode := Value;
end;

function TPdf4DPageView.GetHoverEnabled: Boolean;
begin
  Result := FController.HoverEnabled;
end;

procedure TPdf4DPageView.SetHoverEnabled(const Value: Boolean);
begin
  FController.HoverEnabled := Value;
end;

function TPdf4DPageView.GetSelectionEnabled: Boolean;
begin
  Result := FController.SelectionEnabled;
end;

procedure TPdf4DPageView.SetSelectionEnabled(const Value: Boolean);
begin
  FController.SelectionEnabled := Value;
end;

function TPdf4DPageView.GetFollowInternalLinks: Boolean;
begin
  Result := FController.FollowInternalLinks;
end;

procedure TPdf4DPageView.SetFollowInternalLinks(const Value: Boolean);
begin
  FController.FollowInternalLinks := Value;
end;

procedure TPdf4DPageView.SetHoverColor(const Value: TColor);
begin
  FHoverColor := Value;
  ApplyColors;
end;

procedure TPdf4DPageView.SetHoverOpacity(const Value: Byte);
begin
  FHoverOpacity := Value;
  ApplyColors;
end;

procedure TPdf4DPageView.SetSelectionColor(const Value: TColor);
begin
  FSelectionColor := Value;
  ApplyColors;
end;

procedure TPdf4DPageView.SetSelectionOpacity(const Value: Byte);
begin
  FSelectionOpacity := Value;
  ApplyColors;
end;

class function TPdf4DPageView.ToAlphaColor(const Color: TColor; const Opacity: Byte): TAlphaColor;
begin
  const Rgb = ColorToRGB(Color);
  Result := (TAlphaColor(Opacity) shl AlphaShift) or
            (TAlphaColor(GetRValue(Rgb)) shl RedShift) or
            (TAlphaColor(GetGValue(Rgb)) shl GreenShift) or
            TAlphaColor(GetBValue(Rgb));
end;

procedure TPdf4DPageView.ApplyColors;
begin
  FController.HoverColor := ToAlphaColor(FHoverColor, FHoverOpacity);
  FController.SelectionColor := ToAlphaColor(FSelectionColor, FSelectionOpacity);
  Invalidate;
end;

// The scale that the window has now: what the last change of scale gave, else what the window reports
function TPdf4DPageView.PixelsPerInch: Integer;
begin
  Result := FScalePixelsPerInch;
  if Result <= 0 then
  begin
    Result := CurrentPPI;
  end;
  if Result <= 0 then
  begin
    Result := LogicalPixelsPerInch;
  end;
end;

procedure TPdf4DPageView.UpdateViewport;
begin
  FController.SetViewport(TSize.Create(ClientWidth, ClientHeight), PixelsPerInch);
end;

procedure TPdf4DPageView.CreateWnd;
begin
  inherited;
  UpdateViewport;
  UpdateScrollBars;
end;

procedure TPdf4DPageView.Loaded;
begin
  inherited;
  UpdateViewport;
end;

procedure TPdf4DPageView.Resize;
begin
  inherited;
  UpdateViewport;
end;

procedure TPdf4DPageView.ChangeScale(M, D: Integer; isDpiChange: Boolean);
begin
  if isDpiChange then
  begin
    // Before the size changes, so that the viewport gets the new size together with the new scale
    FScalePixelsPerInch := M;
  end;

  inherited;
  UpdateViewport;
end;

procedure TPdf4DPageView.Paint;
begin
  Canvas.Font.Assign(Font);
  const Painter: IPdfViewPainter = TPdfVclPainter.Create(Canvas);
  var Clip := Canvas.ClipRect;
  if Clip.IsEmpty then
  begin
    Clip := ClientRect;
  end;
  FController.Paint(Painter, Clip);
end;

{ Scroll bars }

procedure TPdf4DPageView.ApplyScrollBar(const Bar: Integer; const ContentLength, ViewLength, Position: Integer);
begin
  var Info: TScrollInfo;
  Info := Default(TScrollInfo);
  Info.cbSize := SizeOf(Info);
  Info.fMask := SIF_RANGE or SIF_PAGE or SIF_POS;
  Info.nMin := 0;
  Info.nMax := Max(0, ContentLength - 1);
  Info.nPage := Max(0, ViewLength);
  Info.nPos := Position;
  // Without SIF_DISABLENOSCROLL Windows hides a bar that has nothing to scroll
  SetScrollInfo(Handle, Bar, Info, True);
end;

// Showing or hiding a bar changes the client size, which resizes the viewport and asks for another update; so it repeats until the
// bars and the viewport agree, at most a few rounds
procedure TPdf4DPageView.UpdateScrollBars;
begin
  if not HandleAllocated then
  begin
    Exit;
  end;

  if FIsUpdatingScrollBars then
  begin
    FScrollBarsDirty := True;
    Exit;
  end;

  FIsUpdatingScrollBars := True;
  try
    var Pass := 0;
    repeat
      FScrollBarsDirty := False;
      Inc(Pass);

      const Content = FController.ContentSize;
      const Position = FController.ScrollPosition;
      ApplyScrollBar(SB_HORZ, Content.cx, ClientWidth, Position.X);
      ApplyScrollBar(SB_VERT, Content.cy, ClientHeight, Position.Y);
    until (not FScrollBarsDirty) or (Pass >= MaxScrollBarRounds);
  finally
    FIsUpdatingScrollBars := False;
  end;
end;

procedure TPdf4DPageView.HandleScroll(const Bar: Integer; const ScrollCode: Integer);
begin
  var Info: TScrollInfo;
  Info := Default(TScrollInfo);
  Info.cbSize := SizeOf(Info);
  Info.fMask := SIF_ALL;
  if not GetScrollInfo(Handle, Bar, Info) then
  begin
    Exit;
  end;

  const LineStep = MulDiv(LineScrollStep, PixelsPerInch, LogicalPixelsPerInch);
  const LastPosition = Max(0, Info.nMax - Integer(Info.nPage) + 1);
  var Target := Info.nPos;
  case ScrollCode of
    SB_LINEUP:
      Dec(Target, LineStep);
    SB_LINEDOWN:
      Inc(Target, LineStep);
    SB_PAGEUP:
      Dec(Target, Integer(Info.nPage));
    SB_PAGEDOWN:
      Inc(Target, Integer(Info.nPage));
    SB_THUMBTRACK, SB_THUMBPOSITION:
      Target := Info.nTrackPos;
    SB_TOP:
      Target := 0;
    SB_BOTTOM:
      Target := LastPosition;
  else
    Exit;
  end;

  Target := EnsureRange(Target, 0, LastPosition);
  const Current = FController.ScrollPosition;
  if Bar = SB_HORZ then
  begin
    FController.ScrollTo(TPoint.Create(Target, Current.Y));
  end
  else
  begin
    FController.ScrollTo(TPoint.Create(Current.X, Target));
  end;
end;

procedure TPdf4DPageView.WMHScroll(var Message: TWMHScroll);
begin
  HandleScroll(SB_HORZ, Message.ScrollCode);
  Message.Result := 0;
end;

procedure TPdf4DPageView.WMVScroll(var Message: TWMVScroll);
begin
  HandleScroll(SB_VERT, Message.ScrollCode);
  Message.Result := 0;
end;

{ IPdfViewHost }

procedure TPdf4DPageView.HostInvalidate(const Rect: TRect);
begin
  if HandleAllocated then
  begin
    var Area := Rect;
    InvalidateRect(Handle, @Area, False);
  end;
end;

procedure TPdf4DPageView.HostScrollStateChanged;
begin
  UpdateScrollBars;
end;

procedure TPdf4DPageView.HostCursorChanged;
begin
  case FController.CursorKind of
    TPdfCursorKind.Text:
      Cursor := crIBeam;
    TPdfCursorKind.Link:
      Cursor := crHandPoint;
  else
    Cursor := crDefault;
  end;

  // Windows asked for the cursor before the controller knew where the pointer is: show the new one now
  if HandleAllocated and ClientRect.Contains(ScreenToClient(Mouse.CursorPos)) then
  begin
    SetCursor(Screen.Cursors[Cursor]);
  end;
end;

function TPdf4DPageView.HostCreateImage(const Bitmap: TPdfBitmap): IPdfViewImage;
begin
  Result := TPdfVclImage.Create(Bitmap);
end;

{ Events of the controller }

procedure TPdf4DPageView.HandleTextSelected(Sender: TObject; const Selection: TPdfTextSelection);
begin
  if Assigned(FOnTextSelected) then
  begin
    FOnTextSelected(Self, Selection);
  end;
end;

procedure TPdf4DPageView.HandleHoverChanged(Sender: TObject; const HasSegment: Boolean; const Segment: TPdfTextFragment);
begin
  if Assigned(FOnHoverChanged) then
  begin
    FOnHoverChanged(Self, HasSegment, Segment);
  end;
end;

procedure TPdf4DPageView.HandleLinkClick(Sender: TObject; const Link: TPdfLink);
begin
  if Assigned(FOnLinkClick) then
  begin
    FOnLinkClick(Self, Link);
  end;
end;

procedure TPdf4DPageView.HandleZoomChanged(Sender: TObject);
begin
  if Assigned(FOnZoomChanged) then
  begin
    FOnZoomChanged(Self);
  end;

  // A listener may remove itself while it is told
  for var Index := FZoomListeners.Count - 1 downto 0 do
  begin
    if Index < FZoomListeners.Count then
    begin
      FZoomListeners[Index](Self);
    end;
  end;
end;

procedure TPdf4DPageView.AddZoomListener(const Listener: TNotifyEvent);
begin
  FZoomListeners.Add(Listener);
end;

procedure TPdf4DPageView.RemoveZoomListener(const Listener: TNotifyEvent);
begin
  FZoomListeners.Remove(Listener);
end;

{ Input }

procedure TPdf4DPageView.WMGetDlgCode(var Message: TWMGetDlgCode);
begin
  inherited;
  Message.Result := Message.Result or DLGC_WANTARROWS;
end;

procedure TPdf4DPageView.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  FController.MouseLeave;
end;

procedure TPdf4DPageView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if Button = TMouseButton.mbLeft then
  begin
    if CanFocus and (not Focused) then
    begin
      SetFocus;
    end;
    FController.MouseDown(TPointF.Create(X, Y));
  end;
end;

procedure TPdf4DPageView.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  FController.MouseMove(TPointF.Create(X, Y));
end;

procedure TPdf4DPageView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if Button = TMouseButton.mbLeft then
  begin
    FController.MouseUp(TPointF.Create(X, Y));
  end;
end;

// MousePos is in screen coordinates
function TPdf4DPageView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := inherited;
  if not Result then
  begin
    const Point = ScreenToClient(MousePos);
    FController.MouseWheel(WheelDelta, ssCtrl in Shift, TPointF.Create(Point.X, Point.Y));
    Result := True;
  end;
end;

class function TPdf4DPageView.ToViewerKey(const Key: Word; out ViewerKey: TPdfViewerKey): Boolean;
begin
  Result := True;
  case Key of
    VK_UP:
      ViewerKey := TPdfViewerKey.Up;
    VK_DOWN:
      ViewerKey := TPdfViewerKey.Down;
    VK_LEFT:
      ViewerKey := TPdfViewerKey.Left;
    VK_RIGHT:
      ViewerKey := TPdfViewerKey.Right;
    VK_PRIOR:
      ViewerKey := TPdfViewerKey.PageUp;
    VK_NEXT:
      ViewerKey := TPdfViewerKey.PageDown;
    VK_HOME:
      ViewerKey := TPdfViewerKey.Home;
    VK_END:
      ViewerKey := TPdfViewerKey.End_;
  else
    ViewerKey := TPdfViewerKey.Up;
    Result := False;
  end;
end;

function TPdf4DPageView.HandleKey(const Key: Word; const Shift: TShiftState): Boolean;
begin
  var ViewerKey: TPdfViewerKey;
  Result := False;

  if ssCtrl in Shift then
  begin
    case Key of
      VkLetterC:
        begin
          CopyToClipboard;
          Result := True;
        end;
      VkLetterA:
        Result := FController.KeyDown(TPdfViewerKey.SelectAll);
      VK_ADD, VK_OEM_PLUS:
        Result := FController.KeyDown(TPdfViewerKey.ZoomIn);
      VK_SUBTRACT, VK_OEM_MINUS:
        Result := FController.KeyDown(TPdfViewerKey.ZoomOut);
      VkZero, VK_NUMPAD0:
        Result := FController.KeyDown(TPdfViewerKey.ZoomReset);
    end;
  end
  else if ToViewerKey(Key, ViewerKey) then
  begin
    Result := FController.KeyDown(ViewerKey);
  end;
end;

procedure TPdf4DPageView.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited;
  if HandleKey(Key, Shift) then
  begin
    Key := 0;
  end;
end;

{ Commands }

procedure TPdf4DPageView.ZoomIn;
begin
  FController.ZoomIn;
end;

procedure TPdf4DPageView.ZoomOut;
begin
  FController.ZoomOut;
end;

procedure TPdf4DPageView.RotateClockwise;
begin
  FController.RotateClockwise;
end;

procedure TPdf4DPageView.RotateCounterclockwise;
begin
  FController.RotateCounterclockwise;
end;

procedure TPdf4DPageView.GoToPage(const PageIndex: Integer);
begin
  FController.GoToPage(PageIndex);
end;

procedure TPdf4DPageView.ScrollIntoView(const PageIndex: Integer; const Quads: TArray<TPdfQuad>);
begin
  FController.ScrollIntoView(PageIndex, Quads);
end;

function TPdf4DPageView.TryGetSelection(out Selection: TPdfTextSelection): Boolean;
begin
  Result := FController.TryGetSelection(Selection);
end;

procedure TPdf4DPageView.CopyToClipboard;
begin
  const MayCopy = Assigned(FDocument) and FDocument.CanCopy;
  if not MayCopy then
  begin
    Exit;
  end;

  var Selection: TPdfTextSelection;
  if FController.TryGetSelection(Selection) then
  begin
    WriteClipboardText(Selection.Text);
  end;
end;

procedure TPdf4DPageView.WriteClipboardText(const Text: string);
begin
  Clipboard.AsText := Text;
end;

end.
