// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.Painter.Interfaces;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  System.UITypes,
  Pdf4D.Render.Bitmap;

type
  // A picture that the framework shell made from a bitmap and keeps in its own format
  IPdfViewImage = interface
    ['{0C5E8A17-6F42-4D93-B2A8-E1D7C3F95B26}']
    function Width: Integer;
    function Height: Integer;
  end;

  // Draws in device pixels of the viewport. The framework shell implements it.
  IPdfViewPainter = interface
    ['{A92F4B60-3D1C-4E75-8B07-5C6E2D9A1F38}']
    procedure FillRect(const Rect: TRectF; const Color: TAlphaColor);
    // Scales when the sizes of Source and Dest differ
    procedure DrawImage(const Image: IPdfViewImage; const Source: TRect; const Dest: TRectF);
    procedure FillPolygon(const Points: TArray<TPointF>; const Color: TAlphaColor);
    procedure FramePolygon(const Points: TArray<TPointF>; const Color: TAlphaColor; const Width: Single);
    procedure FillEllipse(const Rect: TRectF; const Color: TAlphaColor);
    procedure FrameEllipse(const Rect: TRectF; const Color: TAlphaColor; const Width: Single);
    // One line, centred, in the font of the control
    procedure DrawText(const Text: string; const Rect: TRectF; const Color: TAlphaColor);
  end;

  // What the controllers need from the control that shows them
  IPdfViewHost = interface
    ['{47B1D0E9-8A26-4C5F-9E31-2F0A6B8C7D14}']
    // Viewport pixels
    procedure Invalidate(const Rect: TRect);
    // ContentSize or ScrollPosition changed: update the scroll bars
    procedure ScrollStateChanged;
    procedure CursorChanged;
    // UI thread; copies the pixels
    function CreateImage(const Bitmap: TPdfBitmap): IPdfViewImage;
  end;

implementation

end.
