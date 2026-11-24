// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.FMX.Thumbnails;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.Types,
  System.UITypes,
  FMX.Controls,
  FMX.Graphics,
  FMX.StdCtrls,
  FMX.Types,
  Pdf4D.Render.Bitmap,
  Pdf4D.Viewer.Document,
  Pdf4D.Viewer.Painter.Interfaces,
  Pdf4D.Viewer.ThumbnailsController,
  Pdf4D.FMX.ViewSupport;

type
  // Shows the pages of a document as small pictures in a column, and marks the current page. A thin shell around
  // TPdfThumbnailsController: it turns the input of FMX into calls on the controller and the calls of the controller into a scroll bar and
  // painting. FMX works in logical units; the controller works in device pixels.
  TPdf4DThumbnails = class(TPdfFmxViewControl, IPdfViewHost)
  private
    FController: TPdfThumbnailsController;
    FDocument: TPdf4DCustomDocument;
    FVScrollBar: TScrollBar;
    FFont: FMX.Graphics.TFont;
    // The part of the control that shows thumbnails: the control without the scroll bar when it is visible, in device pixels
    FViewport: TSize;
    FIsUpdatingScrollBar: Boolean;
    FScrollBarDirty: Boolean;
    // The height of the content that the bar was last set for
    FBarContentHeight: Integer;

    procedure SetDocument(const Value: TPdf4DCustomDocument);
    function GetThumbnailWidth: Integer;
    procedure SetThumbnailWidth(const Value: Integer);
    function GetSelectedColor: TAlphaColor;
    procedure SetSelectedColor(const Value: TAlphaColor);
    function GetBackgroundColor: TAlphaColor;
    procedure SetBackgroundColor(const Value: TAlphaColor);

    procedure UpdateScrollBar;
    // True when the bar appeared or went
    function ShowBarForContent: Boolean;
    procedure ApplyBarValues;
    procedure HandleScrollBarChange(Sender: TObject);
    function LineStep: Integer;

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
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure UpdateViewport; override;
    procedure Loaded; override;
    procedure Resize; override;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean); override;

  public
    constructor Create(Owner: TComponent); override;
    destructor Destroy; override;

    // One method per user action, so that gestures can call them later. Positions are local, in logical units.
    procedure HandleClick(const LocalPoint: TPointF);
    // 120 per notch; the wheel up is positive
    procedure HandleWheel(const WheelDelta: Integer);

    // Owned
    property Controller: TPdfThumbnailsController read FController;
    property VScrollBar: TScrollBar read FVScrollBar;

  published
    property Document: TPdf4DCustomDocument read FDocument write SetDocument;
    // Logical units
    property ThumbnailWidth: Integer read GetThumbnailWidth write SetThumbnailWidth default DefaultThumbnailWidth;
    // The frame around the thumbnail of the current page
    property SelectedColor: TAlphaColor read GetSelectedColor write SetSelectedColor default $FF1E90FF;
    // Around and between the thumbnails
    property BackgroundColor: TAlphaColor read GetBackgroundColor write SetBackgroundColor default $FFE0E0E0;
    property Align;
    property Anchors;
    property Enabled;
    property Height;
    property HitTest default True;
    property Margins;
    property Padding;
    property Position;
    property Size;
    property Visible;
    property Width;
  end;

implementation

uses
  System.Math,
  System.SysUtils,
  Pdf4D.FMX.Painter;

const
  InitialWidth = 150;
  InitialHeight = 200;
  LogicalPixelsPerInch = 96;
  // Logical units; a notch of the wheel scrolls this many lines
  ScrollBarThickness = 16;
  LineScrollStep = 40;
  LinesPerWheelNotch = 3;
  WheelNotch = 120;
  MaxScrollBarRounds = 4;

{ TPdf4DThumbnails }

constructor TPdf4DThumbnails.Create(Owner: TComponent);
begin
  inherited Create(Owner);
  HitTest := True;
  FFont := FMX.Graphics.TFont.Create;

  FController := TPdfThumbnailsController.Create(Self);
  FVScrollBar := TPdfFmxViewSupport.NewScrollBar(Self, TOrientation.Vertical, TAlignLayout.Right, ScrollBarThickness, LineScrollStep,
                                                 HandleScrollBarChange);
end;

destructor TPdf4DThumbnails.Destroy;
begin
  SetDocument(nil);
  // The controller asks the host for nothing while the control is being destroyed, so it can go before the children
  FreeAndNil(FController);
  FreeAndNil(FFont);
  inherited;
end;

function TPdf4DThumbnails.GetDefaultSize: TSizeF;
begin
  Result := TSizeF.Create(InitialWidth, InitialHeight);
end;

procedure TPdf4DThumbnails.Notification(AComponent: TComponent; Operation: TOperation);
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

function TPdf4DThumbnails.GetSelectedColor: TAlphaColor;
begin
  Result := FController.SelectedColor;
end;

procedure TPdf4DThumbnails.SetSelectedColor(const Value: TAlphaColor);
begin
  FController.SelectedColor := Value;
  Repaint;
end;

function TPdf4DThumbnails.GetBackgroundColor: TAlphaColor;
begin
  Result := FController.BackgroundColor;
end;

procedure TPdf4DThumbnails.SetBackgroundColor(const Value: TAlphaColor);
begin
  FController.BackgroundColor := Value;
  Repaint;
end;

{ Scale and viewport }

procedure TPdf4DThumbnails.UpdateViewport;
begin
  if not Assigned(FController) then
  begin
    Exit;
  end;

  RefreshScale;
  var ViewWidth := Width;
  if FVScrollBar.Visible then
  begin
    ViewWidth := ViewWidth - FVScrollBar.Width;
  end;

  FViewport := TSize.Create(ToDeviceLength(ViewWidth), ToDeviceLength(Height));
  FController.SetViewport(FViewport, LogicalPixelsPerInch * Scale);
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

procedure TPdf4DThumbnails.Paint;
begin
  // The scale of the form can have changed without a message that reached this control
  if IsScaleStale then
  begin
    UpdateViewport;
  end;

  const Painter: IPdfViewPainter = TPdfFmxPainter.Create(Canvas, Scale, FFont);
  // What lies under the scroll bar is not part of the viewport
  Painter.FillRect(TRectF.Create(0, 0, ToDeviceLength(Width), ToDeviceLength(Height)), FController.BackgroundColor);
  FController.Paint(Painter, TRect.Create(0, 0, FViewport.cx, FViewport.cy));
end;

{ Scroll bar }

// Showing or hiding the bar changes the viewport, and with it the layout, so it repeats until the bar and the viewport agree, at most a
// few rounds
procedure TPdf4DThumbnails.UpdateScrollBar;
begin
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
      FBarContentHeight := FController.ContentSize.cy;
      Inc(Pass);

      if ShowBarForContent then
      begin
        FScrollBarDirty := True;
        UpdateViewport;
      end;
      ApplyBarValues;
    until (not FScrollBarDirty) or (Pass >= MaxScrollBarRounds);
  finally
    FIsUpdatingScrollBar := False;
  end;
end;

function TPdf4DThumbnails.ShowBarForContent: Boolean;
begin
  const NeedBar = (FController.ContentSize.cy > ToDeviceLength(Height));
  Result := (NeedBar <> FVScrollBar.Visible);
  FVScrollBar.Visible := NeedBar;
end;

procedure TPdf4DThumbnails.ApplyBarValues;
begin
  FVScrollBar.Max := FController.ContentSize.cy / Scale;
  FVScrollBar.ViewportSize := FViewport.cy / Scale;
  FVScrollBar.Value := FController.ScrollPosition.Y / Scale;
end;

procedure TPdf4DThumbnails.HandleScrollBarChange(Sender: TObject);
begin
  if FIsUpdatingScrollBar then
  begin
    Exit;
  end;

  FController.ScrollTo(TPoint.Create(0, Round(FVScrollBar.Value * Scale)));
end;

function TPdf4DThumbnails.LineStep: Integer;
begin
  Result := ToDeviceLength(LineScrollStep);
end;

{ IPdfViewHost }

procedure TPdf4DThumbnails.HostInvalidate(const Rect: TRect);
begin
  if csDestroying in ComponentState then
  begin
    Exit;
  end;

  // The controller does not report the content that a document gives it when it attaches, so the bar follows the content here
  if FController.ContentSize.cy <> FBarContentHeight then
  begin
    UpdateScrollBar;
  end;
  // FMX repaints a control as a whole
  Repaint;
end;

procedure TPdf4DThumbnails.HostScrollStateChanged;
begin
  if not (csDestroying in ComponentState) then
  begin
    UpdateScrollBar;
  end;
end;

procedure TPdf4DThumbnails.HostCursorChanged;
begin
  // The thumbnails keep the cursor of the control
end;

function TPdf4DThumbnails.HostCreateImage(const Bitmap: TPdfBitmap): IPdfViewImage;
begin
  Result := TPdfFmxImage.Create(Bitmap);
end;

{ Input }

procedure TPdf4DThumbnails.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  if Button = TMouseButton.mbLeft then
  begin
    HandleClick(TPointF.Create(X, Y));
  end;
end;

procedure TPdf4DThumbnails.MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean);
begin
  inherited;
  if not Handled then
  begin
    HandleWheel(WheelDelta);
    Handled := True;
  end;
end;

procedure TPdf4DThumbnails.HandleClick(const LocalPoint: TPointF);
begin
  FController.Click(ToDevice(LocalPoint));
end;

procedure TPdf4DThumbnails.HandleWheel(const WheelDelta: Integer);
begin
  FController.ScrollBy(0, -Round(WheelDelta * LineStep * LinesPerWheelNotch / WheelNotch));
end;

end.
