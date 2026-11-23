// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Vcl.ViewSupport;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  System.UITypes,
  Winapi.Windows,
  Vcl.Controls,
  Vcl.Graphics;

type
  // The window that the page view and the thumbnails have in common: the scale that the window has now, and the invalidation of the host
  // of a controller
  TPdfVclViewControl = class(TCustomControl)
  private
    // The pixels per inch that the last change of scale gave; 0 until there was one
    FScalePixelsPerInch: Integer;

  protected
    // What the last change of scale gave, else what the window reports
    function PixelsPerInch: Integer;
    // Gives the controller its viewport and scale
    procedure UpdateViewport; virtual; abstract;
    procedure ChangeScale(M, D: Integer; isDpiChange: Boolean); override;
    procedure HostInvalidate(const Rect: TRect);
  end;

  // What the page view and the thumbnails share of their window: the colors for the controller and the scroll bars
  TPdfVclViewSupport = class
  public
    // The color of the VCL with an opacity, as the controllers take it
    class function ToAlphaColor(const Color: TColor; const Opacity: Byte): TAlphaColor; static;
    // Puts the range, the page and the position of the bar of the window; a bar that has nothing to scroll is hidden by Windows
    class procedure ApplyScrollBar(const Handle: HWND; const Bar, ContentLength, ViewLength, Position: Integer); static;
    // Where the bar goes for a scroll message: False for a code that moves nothing. LineStep is in pixels.
    class function TryScrollTarget(const Handle: HWND; const Bar, ScrollCode, LineStep: Integer; out Target: Integer): Boolean; static;
  end;

implementation

uses
  System.Math;

const
  LogicalPixelsPerInch = 96;
  AlphaShift = 24;
  RedShift = 16;
  GreenShift = 8;

{ TPdfVclViewControl }

function TPdfVclViewControl.PixelsPerInch: Integer;
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

procedure TPdfVclViewControl.ChangeScale(M, D: Integer; isDpiChange: Boolean);
begin
  if isDpiChange then
  begin
    // Before the size changes, so that the viewport gets the new size together with the new scale
    FScalePixelsPerInch := M;
  end;

  inherited;
  UpdateViewport;
end;

procedure TPdfVclViewControl.HostInvalidate(const Rect: TRect);
begin
  if HandleAllocated then
  begin
    var Area := Rect;
    InvalidateRect(Handle, @Area, False);
  end;
end;

{ TPdfVclViewSupport }

class function TPdfVclViewSupport.ToAlphaColor(const Color: TColor; const Opacity: Byte): TAlphaColor;
begin
  const Rgb = ColorToRGB(Color);
  Result := (TAlphaColor(Opacity) shl AlphaShift) or
            (TAlphaColor(GetRValue(Rgb)) shl RedShift) or
            (TAlphaColor(GetGValue(Rgb)) shl GreenShift) or
            TAlphaColor(GetBValue(Rgb));
end;

class procedure TPdfVclViewSupport.ApplyScrollBar(const Handle: HWND; const Bar, ContentLength, ViewLength, Position: Integer);
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

class function TPdfVclViewSupport.TryScrollTarget(const Handle: HWND; const Bar, ScrollCode, LineStep: Integer; out Target: Integer): Boolean;
begin
  Target := 0;

  var Info: TScrollInfo;
  Info := Default(TScrollInfo);
  Info.cbSize := SizeOf(Info);
  Info.fMask := SIF_ALL;
  if not GetScrollInfo(Handle, Bar, Info) then
  begin
    Exit(False);
  end;

  const LastPosition = Max(0, Info.nMax - Integer(Info.nPage) + 1);
  Target := Info.nPos;
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
    Exit(False);
  end;

  Target := EnsureRange(Target, 0, LastPosition);
  Result := True;
end;

end.
