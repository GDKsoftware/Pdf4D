// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.FMX.PageView;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.Generics.Collections,
  System.Types,
  System.UITypes,
  FMX.Controls,
  FMX.Graphics,
  FMX.StdCtrls,
  FMX.Types,
  Pdf4D.Common.Quad,
  Pdf4D.Api.Page.Interfaces,
  Pdf4D.Api.TextLayout.Interfaces,
  Pdf4D.Render.Bitmap,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.Document,
  Pdf4D.Viewer.Painter.Interfaces,
  Pdf4D.Viewer.PageViewController,
  Pdf4D.FMX.ViewSupport;

type
  // Shows the pages of a document in a form. A thin shell around TPdfPageViewController: it turns the input of FMX into calls on the
  // controller and the calls of the controller into scroll bars, cursors and painting. FMX works in logical units; the controller works
  // in device pixels, so every position is multiplied by the scale of the form on its way in, and the painter divides by it on the way out.
  TPdf4DPageView = class(TPdfFmxViewControl, IPdfViewHost)
  private
    FController: TPdfPageViewController;
    FDocument: TPdf4DCustomDocument;
    FVScrollBar: TScrollBar;
    FHScrollBar: TScrollBar;
    FFont: FMX.Graphics.TFont;
    // The part of the control that shows pages: the control without the scroll bars that are visible, in device pixels
    FViewport: TSize;
    FIsUpdatingScrollBars: Boolean;
    FScrollBarsDirty: Boolean;
    FOnTextSelected: TPdfTextSelectedEvent;
    FOnHoverChanged: TPdfHoverChangedEvent;
    FOnLinkClick: TPdfLinkClickEvent;
    FOnZoomChanged: TNotifyEvent;
    FZoomListeners: TList<TNotifyEvent>;

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
    function GetHoverColor: TAlphaColor;
    procedure SetHoverColor(const Value: TAlphaColor);
    function GetSelectionColor: TAlphaColor;
    procedure SetSelectionColor(const Value: TAlphaColor);
    function GetSearchHitColor: TAlphaColor;
    procedure SetSearchHitColor(const Value: TAlphaColor);
    function GetCurrentSearchHitColor: TAlphaColor;
    procedure SetCurrentSearchHitColor(const Value: TAlphaColor);
    function GetBackgroundColor: TAlphaColor;
    procedure SetBackgroundColor(const Value: TAlphaColor);

    procedure CreateScrollBars;
    procedure UpdateScrollBars;
    function ShowBarsForContent: Boolean;
    procedure ApplyBarValues;
    procedure HandleScrollBarChange(Sender: TObject);
    procedure PaintDesignPlaceholder(const Painter: IPdfViewPainter);
    class function TryGetViewerKey(const Key: Word; out ViewerKey: TPdfViewerKey): Boolean; static;
    class function TryGetControlKey(const Key: Word; const KeyChar: Char; out ViewerKey: TPdfViewerKey): Boolean; static;
    function MouseInLocal: TPointF;

    procedure HandleTextSelected(Sender: TObject; const Selection: TPdfTextSelection);
    procedure HandleHoverChanged(Sender: TObject; const HasSegment: Boolean; const Segment: TPdfTextFragment);
    procedure HandleLinkClick(Sender: TObject; const Link: TPdfLink);
    procedure HandleZoomChanged(Sender: TObject);
    // Scrolls sideways by a number of notches of the wheel; a positive number goes to the right
    procedure ScrollSideways(const Notches: Single);

    // IPdfViewHost
    procedure HostInvalidate(const Rect: TRect);
    procedure HostScrollStateChanged;
    procedure HostCursorChanged;
    function HostCreateImage(const Bitmap: TPdfBitmap): IPdfViewImage;
    procedure IPdfViewHost.Invalidate = HostInvalidate;
    procedure IPdfViewHost.ScrollStateChanged = HostScrollStateChanged;
    procedure IPdfViewHost.CursorChanged = HostCursorChanged;
    function IPdfViewHost.CreateImage = HostCreateImage;

  protected
    function GetDefaultSize: TSizeF; override;
    procedure UpdateViewport; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Loaded; override;
    procedure Resize; override;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean); override;
    procedure DoMouseLeave; override;
    procedure KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState); override;
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
    function TryGetSelection(out Selection: TPdfTextSelection): Boolean;
    // Several parties can follow the zoom, where OnZoomChanged is for the owner of the page view alone
    procedure AddZoomListener(const Listener: TNotifyEvent);
    procedure RemoveZoomListener(const Listener: TNotifyEvent);
{$IFDEF PDF4D_TESTS}
    // For tests only, compiled when PDF4D_TESTS is defined
    function ZoomListenerCount: Integer;
{$ENDIF}

    // One method per user action, so that gestures can call them later. Positions are local, in logical units.
    procedure HandleMouseMove(const LocalPoint: TPointF);
    procedure HandleMouseDown(const LocalPoint: TPointF);
    procedure HandleMouseUp(const LocalPoint: TPointF);
    procedure HandleMouseLeave;
    // 120 per notch; the wheel up is positive
    procedure HandleWheel(const WheelDelta: Integer; const Ctrl: Boolean; const LocalPoint: TPointF);
    // Shift and the wheel: the wheel up goes to the left
    procedure HandleSidewaysWheel(const WheelDelta: Integer);
    // True when the key was used
    function HandleKey(const Key: Word; const KeyChar: Char; const Shift: TShiftState): Boolean;

    // Owned
    property Controller: TPdfPageViewController read FController;
    property VScrollBar: TScrollBar read FVScrollBar;
    property HScrollBar: TScrollBar read FHScrollBar;

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
    property HoverColor: TAlphaColor read GetHoverColor write SetHoverColor default $FF1E90FF;
    property SelectionColor: TAlphaColor read GetSelectionColor write SetSelectionColor default $663399FF;
    property SearchHitColor: TAlphaColor read GetSearchHitColor write SetSearchHitColor default $66FFD700;
    property CurrentSearchHitColor: TAlphaColor read GetCurrentSearchHitColor write SetCurrentSearchHitColor default $99FF8C00;
    property BackgroundColor: TAlphaColor read GetBackgroundColor write SetBackgroundColor default $FFE0E0E0;
    property OnTextSelected: TPdfTextSelectedEvent read FOnTextSelected write FOnTextSelected;
    property OnHoverChanged: TPdfHoverChangedEvent read FOnHoverChanged write FOnHoverChanged;
    property OnLinkClick: TPdfLinkClickEvent read FOnLinkClick write FOnLinkClick;
    property OnZoomChanged: TNotifyEvent read FOnZoomChanged write FOnZoomChanged;
    property Align;
    property Anchors;
    property Enabled;
    property Height;
    property HitTest default True;
    property Margins;
    property Padding;
    property PopupMenu;
    property Position;
    property Size;
    property TabOrder;
    property TabStop;
    property Visible;
    property Width;
    property OnEnter;
    property OnExit;
  end;

implementation

uses
  System.Math,
  System.SysUtils,
  System.Rtti,
  FMX.Forms,
  FMX.Platform,
  Pdf4D.Common.Defines,
  Pdf4D.Viewer.ResourceStrings,
  Pdf4D.FMX.Painter;

resourcestring
  SFmxNoClipboardService = 'the platform has no clipboard service';

const
  InitialSize = 200;
  LogicalPixelsPerInch = 96;
  // Logical units
  ScrollBarThickness = 16;
  LineScrollStep = 40;
  LinesPerWheelNotch = 3;
  WheelNotch = 120;
  MaxScrollBarRounds = 4;
  DesignBackgroundColor = $FFF0F0F0;
  DesignTextColor = $FF808080;

{ TPdf4DPageView }

constructor TPdf4DPageView.Create(Owner: TComponent);
begin
  inherited Create(Owner);
  CanFocus := True;
  TabStop := True;
  AutoCapture := True;
  HitTest := True;
  FFont := FMX.Graphics.TFont.Create;
  FZoomListeners := TList<TNotifyEvent>.Create;

  FController := TPdfPageViewController.Create(Self);
  FController.OnTextSelected := HandleTextSelected;
  FController.OnHoverChanged := HandleHoverChanged;
  FController.OnLinkClick := HandleLinkClick;
  FController.OnZoomChanged := HandleZoomChanged;

  CreateScrollBars;
end;

destructor TPdf4DPageView.Destroy;
begin
  FOnTextSelected := nil;
  FOnHoverChanged := nil;
  FOnLinkClick := nil;
  FOnZoomChanged := nil;
  SetDocument(nil);
  // The inherited destructor tells the components that follow this one that it goes, and a zoom listener lets go of it then: the list
  // and the controller stay until after that. The controller asks the host for nothing while the control is being destroyed.
  inherited;
  FreeAndNil(FController);
  FreeAndNil(FZoomListeners);
  FreeAndNil(FFont);
end;

procedure TPdf4DPageView.CreateScrollBars;
begin
  FVScrollBar := TPdfFmxViewSupport.NewScrollBar(Self, TOrientation.Vertical, TAlignLayout.Right, ScrollBarThickness, LineScrollStep,
                                                 HandleScrollBarChange);
  FHScrollBar := TPdfFmxViewSupport.NewScrollBar(Self, TOrientation.Horizontal, TAlignLayout.Bottom, ScrollBarThickness, LineScrollStep,
                                                 HandleScrollBarChange);
end;

function TPdf4DPageView.GetDefaultSize: TSizeF;
begin
  Result := TSizeF.Create(InitialSize, InitialSize);
end;

procedure TPdf4DPageView.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = TOperation.opRemove) and (AComponent = FDocument) then
  begin
    FDocument := nil;
    if Assigned(FController) then
    begin
      FController.Document := nil;
    end;
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

function TPdf4DPageView.GetHoverColor: TAlphaColor;
begin
  Result := FController.HoverColor;
end;

procedure TPdf4DPageView.SetHoverColor(const Value: TAlphaColor);
begin
  FController.HoverColor := Value;
  Repaint;
end;

function TPdf4DPageView.GetSelectionColor: TAlphaColor;
begin
  Result := FController.SelectionColor;
end;

procedure TPdf4DPageView.SetSelectionColor(const Value: TAlphaColor);
begin
  FController.SelectionColor := Value;
  Repaint;
end;

function TPdf4DPageView.GetSearchHitColor: TAlphaColor;
begin
  Result := FController.SearchHitColor;
end;

procedure TPdf4DPageView.SetSearchHitColor(const Value: TAlphaColor);
begin
  FController.SearchHitColor := Value;
  Repaint;
end;

function TPdf4DPageView.GetCurrentSearchHitColor: TAlphaColor;
begin
  Result := FController.CurrentSearchHitColor;
end;

procedure TPdf4DPageView.SetCurrentSearchHitColor(const Value: TAlphaColor);
begin
  FController.CurrentSearchHitColor := Value;
  Repaint;
end;

function TPdf4DPageView.GetBackgroundColor: TAlphaColor;
begin
  Result := FController.BackgroundColor;
end;

procedure TPdf4DPageView.SetBackgroundColor(const Value: TAlphaColor);
begin
  FController.BackgroundColor := Value;
  Repaint;
end;

{ Scale and viewport }

procedure TPdf4DPageView.UpdateViewport;
begin
  if not Assigned(FController) then
  begin
    Exit;
  end;

  RefreshScale;
  var ViewWidth := Width;
  var ViewHeight := Height;
  if FVScrollBar.Visible then
  begin
    ViewWidth := ViewWidth - FVScrollBar.Width;
  end;
  if FHScrollBar.Visible then
  begin
    ViewHeight := ViewHeight - FHScrollBar.Height;
  end;

  FViewport := TSize.Create(ToDeviceLength(ViewWidth), ToDeviceLength(ViewHeight));
  FController.SetViewport(FViewport, LogicalPixelsPerInch * Scale);
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

{ Painting }

procedure TPdf4DPageView.PaintDesignPlaceholder(const Painter: IPdfViewPainter);
begin
  const Area = TRectF.Create(0, 0, ToDeviceLength(Width), ToDeviceLength(Height));
  Painter.FillRect(Area, DesignBackgroundColor);
  Painter.DrawText(ClassName, Area, DesignTextColor);
end;

procedure TPdf4DPageView.Paint;
begin
  // The scale of the form can have changed without a message that reached this control
  if IsScaleStale then
  begin
    UpdateViewport;
  end;

  const Painter: IPdfViewPainter = TPdfFmxPainter.Create(Canvas, Scale, FFont, PaintOrigin);
  if csDesigning in ComponentState then
  begin
    PaintDesignPlaceholder(Painter);
    Exit;
  end;

  // What lies under the scroll bars is not part of the viewport
  Painter.FillRect(TRectF.Create(0, 0, ToDeviceLength(Width), ToDeviceLength(Height)), FController.BackgroundColor);
  FController.Paint(Painter, TRect.Create(0, 0, FViewport.cx, FViewport.cy));
end;

{ Scroll bars }

// The bars that are needed are those for the content that is laid out now; showing or hiding one changes the viewport, and with it the
// layout, so it repeats until the bars and the viewport agree, at most a few rounds
procedure TPdf4DPageView.UpdateScrollBars;
begin
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

      if ShowBarsForContent then
      begin
        FScrollBarsDirty := True;
        UpdateViewport;
      end;
      ApplyBarValues;
    until (not FScrollBarsDirty) or (Pass >= MaxScrollBarRounds);
  finally
    FIsUpdatingScrollBars := False;
  end;
end;

// True when a bar appeared or went
function TPdf4DPageView.ShowBarsForContent: Boolean;
begin
  const Content = FController.ContentSize;
  const FullWidth = ToDeviceLength(Width);
  const FullHeight = ToDeviceLength(Height);
  // The same sums as the viewport makes
  const WidthWithBar = ToDeviceLength(Width - FVScrollBar.Width);
  const HeightWithBar = ToDeviceLength(Height - FHScrollBar.Height);

  var NeedVertical := (Content.cy > FullHeight);
  var NeedHorizontal := (Content.cx > FullWidth);
  if NeedVertical and (not NeedHorizontal) then
  begin
    NeedHorizontal := (Content.cx > WidthWithBar);
  end
  else if NeedHorizontal and (not NeedVertical) then
  begin
    NeedVertical := (Content.cy > HeightWithBar);
  end;

  Result := (NeedVertical <> FVScrollBar.Visible) or (NeedHorizontal <> FHScrollBar.Visible);
  FVScrollBar.Visible := NeedVertical;
  FHScrollBar.Visible := NeedHorizontal;
end;

procedure TPdf4DPageView.ApplyBarValues;
begin
  const Content = FController.ContentSize;
  const Position = FController.ScrollPosition;

  FVScrollBar.Max := Content.cy / Scale;
  FVScrollBar.ViewportSize := FViewport.cy / Scale;
  FVScrollBar.Value := Position.Y / Scale;
  FHScrollBar.Max := Content.cx / Scale;
  FHScrollBar.ViewportSize := FViewport.cx / Scale;
  FHScrollBar.Value := Position.X / Scale;
end;

procedure TPdf4DPageView.HandleScrollBarChange(Sender: TObject);
begin
  if FIsUpdatingScrollBars then
  begin
    Exit;
  end;

  const Left = Round(FHScrollBar.Value * Scale);
  const Top = Round(FVScrollBar.Value * Scale);
  FController.ScrollTo(TPoint.Create(Left, Top));
end;

{ IPdfViewHost }

procedure TPdf4DPageView.HostInvalidate(const Rect: TRect);
begin
  // FMX repaints a control as a whole
  if not (csDestroying in ComponentState) then
  begin
    Repaint;
  end;
end;

procedure TPdf4DPageView.HostScrollStateChanged;
begin
  if not (csDestroying in ComponentState) then
  begin
    UpdateScrollBars;
  end;
end;

procedure TPdf4DPageView.HostCursorChanged;
begin
  if csDestroying in ComponentState then
  begin
    Exit;
  end;

  case FController.CursorKind of
    TPdfCursorKind.Text:
      Cursor := crIBeam;
    TPdfCursorKind.Link:
      Cursor := crHandPoint;
  else
    Cursor := crDefault;
  end;

  // The form asks for the cursor when the pointer moves; it changes here too when the text arrives under a pointer that does not move
  var Service: IFMXCursorService;
  if IsMouseOver and TPlatformServices.Current.SupportsPlatformService(IFMXCursorService, Service) then
  begin
    Service.SetCursor(Cursor);
  end;
end;

function TPdf4DPageView.HostCreateImage(const Bitmap: TPdfBitmap): IPdfViewImage;
begin
  Result := TPdfFmxImage.Create(Bitmap);
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

{$IFDEF PDF4D_TESTS}
function TPdf4DPageView.ZoomListenerCount: Integer;
begin
  Result := FZoomListeners.Count;
end;
{$ENDIF}

{ Input }

procedure TPdf4DPageView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  if Button = TMouseButton.mbLeft then
  begin
    HandleMouseDown(TPointF.Create(X, Y));
  end;
end;

procedure TPdf4DPageView.MouseMove(Shift: TShiftState; X, Y: Single);
begin
  inherited;
  HandleMouseMove(TPointF.Create(X, Y));
end;

procedure TPdf4DPageView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  if Button = TMouseButton.mbLeft then
  begin
    HandleMouseUp(TPointF.Create(X, Y));
  end;
end;

procedure TPdf4DPageView.DoMouseLeave;
begin
  inherited;
  HandleMouseLeave;
end;

// FMX gives the wheel no position: it is where the pointer is
function TPdf4DPageView.MouseInLocal: TPointF;
begin
  Result := ScreenToLocal(Screen.MousePos);
end;

procedure TPdf4DPageView.MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean);
begin
  inherited;
  if not Handled then
  begin
    if ssShift in Shift then
    begin
      HandleSidewaysWheel(WheelDelta);
    end
    else
    begin
      HandleWheel(WheelDelta, ssCtrl in Shift, MouseInLocal);
    end;
    Handled := True;
  end;
end;

procedure TPdf4DPageView.KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
begin
  inherited;
  if HandleKey(Key, KeyChar, Shift) then
  begin
    Key := 0;
    KeyChar := #0;
  end;
end;

procedure TPdf4DPageView.HandleMouseMove(const LocalPoint: TPointF);
begin
  FController.MouseMove(ToDevice(LocalPoint));
end;

procedure TPdf4DPageView.HandleMouseDown(const LocalPoint: TPointF);
begin
  FController.MouseDown(ToDevice(LocalPoint));
end;

procedure TPdf4DPageView.HandleMouseUp(const LocalPoint: TPointF);
begin
  FController.MouseUp(ToDevice(LocalPoint));
end;

procedure TPdf4DPageView.HandleMouseLeave;
begin
  FController.MouseLeave;
end;

procedure TPdf4DPageView.HandleWheel(const WheelDelta: Integer; const Ctrl: Boolean; const LocalPoint: TPointF);
begin
  FController.MouseWheel(WheelDelta, Ctrl, ToDevice(LocalPoint));
end;

procedure TPdf4DPageView.HandleSidewaysWheel(const WheelDelta: Integer);
begin
  ScrollSideways(-WheelDelta / WheelNotch);
end;

procedure TPdf4DPageView.ScrollSideways(const Notches: Single);
begin
  FController.ScrollBy(Round(Notches * LinesPerWheelNotch * LineScrollStep * Scale), 0);
end;

class function TPdf4DPageView.TryGetViewerKey(const Key: Word; out ViewerKey: TPdfViewerKey): Boolean;
begin
  Result := True;
  case Key of
    vkUp:
      ViewerKey := TPdfViewerKey.Up;
    vkDown:
      ViewerKey := TPdfViewerKey.Down;
    vkLeft:
      ViewerKey := TPdfViewerKey.Left;
    vkRight:
      ViewerKey := TPdfViewerKey.Right;
    vkPrior:
      ViewerKey := TPdfViewerKey.PageUp;
    vkNext:
      ViewerKey := TPdfViewerKey.PageDown;
    vkHome:
      ViewerKey := TPdfViewerKey.Home;
    vkEnd:
      ViewerKey := TPdfViewerKey.End_;
  else
    ViewerKey := TPdfViewerKey.Up;
    Result := False;
  end;
end;

// The keys with Ctrl: the plus, minus and zero come as a key or, on some keyboards, only as a character
class function TPdf4DPageView.TryGetControlKey(const Key: Word; const KeyChar: Char; out ViewerKey: TPdfViewerKey): Boolean;
begin
  Result := True;
  if (Key = vkA) then
  begin
    ViewerKey := TPdfViewerKey.SelectAll;
  end
  else if (Key = vkAdd) or (Key = vkEqual) or (KeyChar = '+') or (KeyChar = '=') then
  begin
    ViewerKey := TPdfViewerKey.ZoomIn;
  end
  else if (Key = vkSubtract) or (Key = vkMinus) or (KeyChar = '-') then
  begin
    ViewerKey := TPdfViewerKey.ZoomOut;
  end
  else if (Key = vk0) or (Key = vkNumpad0) or (KeyChar = '0') then
  begin
    ViewerKey := TPdfViewerKey.ZoomReset;
  end
  else
  begin
    ViewerKey := TPdfViewerKey.Up;
    Result := False;
  end;
end;

function TPdf4DPageView.HandleKey(const Key: Word; const KeyChar: Char; const Shift: TShiftState): Boolean;
begin
  var ViewerKey: TPdfViewerKey;
  Result := False;

  if ssCtrl in Shift then
  begin
    if Key = vkC then
    begin
      CopyToClipboard;
      Result := True;
    end
    else if TryGetControlKey(Key, KeyChar, ViewerKey) then
    begin
      Result := FController.KeyDown(ViewerKey);
    end;
  end
  else if TryGetViewerKey(Key, ViewerKey) then
  begin
    Result := FController.KeyDown(ViewerKey);
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
  var Service: IFMXClipboardService;
  if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Service) then
  begin
    Service.SetClipboard(Text);
  end
  else
  begin
    // A copy that cannot be made is a line in the log, not an error for the user
    FDocument.Log(TPdfLogLevel.Warning, Format(SCopyFailed, [SFmxNoClipboardService]));
  end;
end;

end.
