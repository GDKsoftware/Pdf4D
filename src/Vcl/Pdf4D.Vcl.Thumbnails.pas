// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Vcl.Thumbnails;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.Types,
  System.UITypes,
  Winapi.Messages,
  Vcl.Controls,
  Vcl.Graphics,
  Pdf4D.Render.Bitmap,
  Pdf4D.Viewer.Document,
  Pdf4D.Viewer.Painter.Interfaces,
  Pdf4D.Viewer.ThumbnailsController;

const
  DefaultSelectedTColor: TColor = $00FF901E;

type
  // Shows the pages of a document as small pictures in a column, and marks the current page. A thin shell around
  // TPdfThumbnailsController: it turns window messages into calls on the controller and the calls of the controller into a scroll bar
  // and painting.
  TPdf4DThumbnails = class(TCustomControl, IPdfViewHost)
  private
    FController: TPdfThumbnailsController;
    FDocument: TPdf4DCustomDocument;
    FSelectedColor: TColor;
    // The pixels per inch that the last change of scale gave; 0 until there was one
    FScalePixelsPerInch: Integer;
    FIsUpdatingScrollBar: Boolean;
    FScrollBarDirty: Boolean;

    procedure SetDocument(const Value: TPdf4DCustomDocument);
    function GetThumbnailWidth: Integer;
    procedure SetThumbnailWidth(const Value: Integer);
    procedure SetSelectedColor(const Value: TColor);

    function PixelsPerInch: Integer;
    procedure UpdateViewport;
    procedure UpdateScrollBar;
    procedure HandleScroll(const ScrollCode: Integer);

    // IPdfViewHost
    procedure HostInvalidate(const Rect: TRect);
    procedure HostScrollStateChanged;
    procedure HostCursorChanged;
    function HostCreateImage(const Bitmap: TPdfBitmap): IPdfViewImage;
    procedure IPdfViewHost.Invalidate = HostInvalidate;
    procedure IPdfViewHost.ScrollStateChanged = HostScrollStateChanged;
    procedure IPdfViewHost.CursorChanged = HostCursorChanged;
    function IPdfViewHost.CreateImage = HostCreateImage;

    procedure WMVScroll(var Message: TWMVScroll); message WM_VSCROLL;
    procedure CMColorChanged(var Message: TMessage); message CM_COLORCHANGED;

  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure CreateWnd; override;
    procedure Loaded; override;
    procedure Paint; override;
    procedure Resize; override;
    procedure ChangeScale(M, D: Integer; isDpiChange: Boolean); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;

  public
    constructor Create(Owner: TComponent); override;
    destructor Destroy; override;

    // Owned
    property Controller: TPdfThumbnailsController read FController;

  published
    property Document: TPdf4DCustomDocument read FDocument write SetDocument;
    // Logical pixels
    property ThumbnailWidth: Integer read GetThumbnailWidth write SetThumbnailWidth default DefaultThumbnailWidth;
    // The frame around the thumbnail of the current page
    property SelectedColor: TColor read FSelectedColor write SetSelectedColor default $00FF901E;
    property Align;
    property Anchors;
    property Color default $00E0E0E0;
    property Font;
    property Visible;
  end;

implementation

uses
  System.Math,
  System.SysUtils,
  Winapi.Windows,
  Vcl.Forms,
  Pdf4D.Vcl.Painter,
  Pdf4D.Vcl.ViewSupport;

const
  InitialWidth = 150;
  InitialHeight = 200;
  LogicalPixelsPerInch = 96;
  // Logical pixels; a notch of the wheel scrolls this many lines
  LineScrollStep = 40;
  LinesPerWheelNotch = 3;
  WheelNotch = 120;
  MaxScrollBarRounds = 4;
  AlphaOpaque = $FF;

{ TPdf4DThumbnails }

constructor TPdf4DThumbnails.Create(Owner: TComponent);
begin
  inherited Create(Owner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  Width := InitialWidth;
  Height := InitialHeight;
  Color := $00E0E0E0;

  FSelectedColor := DefaultSelectedTColor;
  FController := TPdfThumbnailsController.Create(Self);
  FController.SelectedColor := TPdfVclViewSupport.ToAlphaColor(FSelectedColor, AlphaOpaque);
  FController.BackgroundColor := TPdfVclViewSupport.ToAlphaColor(Color, AlphaOpaque);
end;

destructor TPdf4DThumbnails.Destroy;
begin
  SetDocument(nil);
  // A message while the window goes (a resize, the mouse leaving) still reaches the controller
  inherited;
  FreeAndNil(FController);
end;

procedure TPdf4DThumbnails.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = TOperation.opRemove) and (AComponent = FDocument) then
  begin
    FDocument := nil;
    FController.Document := nil;
  end;
end;

procedure TPdf4DThumbnails.SetDocument(const Value: TPdf4DCustomDocument);
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

function TPdf4DThumbnails.GetThumbnailWidth: Integer;
begin
  Result := FController.ThumbnailWidth;
end;

procedure TPdf4DThumbnails.SetThumbnailWidth(const Value: Integer);
begin
  FController.ThumbnailWidth := Value;
end;

procedure TPdf4DThumbnails.SetSelectedColor(const Value: TColor);
begin
  FSelectedColor := Value;
  FController.SelectedColor := TPdfVclViewSupport.ToAlphaColor(Value, AlphaOpaque);
  Invalidate;
end;

// The scale that the window has now: what the last change of scale gave, else what the window reports
function TPdf4DThumbnails.PixelsPerInch: Integer;
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

procedure TPdf4DThumbnails.UpdateViewport;
begin
  FController.SetViewport(TSize.Create(ClientWidth, ClientHeight), PixelsPerInch);
end;

procedure TPdf4DThumbnails.CreateWnd;
begin
  inherited;
  UpdateViewport;
  UpdateScrollBar;
end;

procedure TPdf4DThumbnails.Loaded;
begin
  inherited;
  UpdateViewport;
end;

procedure TPdf4DThumbnails.Resize;
begin
  inherited;
  UpdateViewport;
end;

procedure TPdf4DThumbnails.ChangeScale(M, D: Integer; isDpiChange: Boolean);
begin
  if isDpiChange then
  begin
    // Before the size changes, so that the viewport gets the new size together with the new scale
    FScalePixelsPerInch := M;
  end;

  inherited;
  UpdateViewport;
end;

procedure TPdf4DThumbnails.Paint;
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

{ Scroll bar }

// Showing or hiding the bar changes the client size, which resizes the viewport and asks for another update; so it repeats until the
// bar and the viewport agree, at most a few rounds
procedure TPdf4DThumbnails.UpdateScrollBar;
begin
  if not HandleAllocated then
  begin
    Exit;
  end;

  if FIsUpdatingScrollBar then
  begin
    FScrollBarDirty := True;
    Exit;
  end;

  FIsUpdatingScrollBar := True;
  try
    var Pass := 0;
    repeat
      FScrollBarDirty := False;
      Inc(Pass);

      TPdfVclViewSupport.ApplyScrollBar(Handle, SB_VERT, FController.ContentSize.cy, ClientHeight, FController.ScrollPosition.Y);
    until (not FScrollBarDirty) or (Pass >= MaxScrollBarRounds);
  finally
    FIsUpdatingScrollBar := False;
  end;
end;

procedure TPdf4DThumbnails.HandleScroll(const ScrollCode: Integer);
begin
  const LineStep = MulDiv(LineScrollStep, PixelsPerInch, LogicalPixelsPerInch);
  var Target: Integer;
  if TPdfVclViewSupport.TryScrollTarget(Handle, SB_VERT, ScrollCode, LineStep, Target) then
  begin
    FController.ScrollTo(TPoint.Create(0, Target));
  end;
end;

procedure TPdf4DThumbnails.WMVScroll(var Message: TWMVScroll);
begin
  HandleScroll(Message.ScrollCode);
  Message.Result := 0;
end;

// The constructor sets the color before the controller exists
procedure TPdf4DThumbnails.CMColorChanged(var Message: TMessage);
begin
  inherited;
  if Assigned(FController) then
  begin
    FController.BackgroundColor := TPdfVclViewSupport.ToAlphaColor(Color, AlphaOpaque);
  end;
end;

{ IPdfViewHost }

procedure TPdf4DThumbnails.HostInvalidate(const Rect: TRect);
begin
  if HandleAllocated then
  begin
    var Area := Rect;
    InvalidateRect(Handle, @Area, False);
  end;
end;

procedure TPdf4DThumbnails.HostScrollStateChanged;
begin
  UpdateScrollBar;
end;

procedure TPdf4DThumbnails.HostCursorChanged;
begin
  // The thumbnails keep the cursor of the control
end;

function TPdf4DThumbnails.HostCreateImage(const Bitmap: TPdfBitmap): IPdfViewImage;
begin
  Result := TPdfVclImage.Create(Bitmap);
end;

{ Input }

procedure TPdf4DThumbnails.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if Button = TMouseButton.mbLeft then
  begin
    FController.Click(TPointF.Create(X, Y));
  end;
end;

function TPdf4DThumbnails.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := inherited;
  if not Result then
  begin
    const LineStep = MulDiv(LineScrollStep, PixelsPerInch, LogicalPixelsPerInch);
    FController.ScrollBy(0, -MulDiv(WheelDelta, LineStep * LinesPerWheelNotch, WheelNotch));
    Result := True;
  end;
end;

end.
