// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.Device.Interfaces;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  Pdf4D.Common.Matrix,
  Pdf4D.Common.Path,
  Pdf4D.Render.Bitmap;

type
  {$SCOPEDENUMS ON}
  TPdfFillRule = (NonZero, EvenOdd);
  TPdfLineCap = (Butt, Round, Square);
  TPdfLineJoin = (Miter, Round, Bevel);
  TPdfBlendMode = (Normal, Multiply, Screen, Overlay, Darken, Lighten, ColorDodge, ColorBurn, HardLight, SoftLight,
                   Difference, Exclusion, Hue, Saturation, Color, Luminosity);
  TPdfPaintKind = (Solid, Bitmap);
  // Decal: transparent outside the bitmap
  TPdfTileMode = (Decal, &Repeat);
  TPdfImageFilter = (Nearest, Bilinear, Bicubic);
  {$SCOPEDENUMS OFF}

  TPdfStrokeStyle = record
    // In path space, > 0
    Width: Single;
    Cap: TPdfLineCap;
    Join: TPdfLineJoin;
    // >= 1
    MiterLimit: Single;
    // Empty: solid; else an even number of lengths >= 0, not all 0, in path space
    Dashes: TArray<Single>;
    DashPhase: Single;
  end;

  TPdfPaint = record
    Kind: TPdfPaintKind;
    // Solid
    Color: TPdfDeviceColor;
    // Bitmap: not owned, read during the call only
    Bitmap: TPdfBitmap;
    // Bitmap pixel space (origin top left, y down) to device pixels
    BitmapToDevice: TPdfMatrix;
    TileMode: TPdfTileMode;
    Filter: TPdfImageFilter;

    class function Solid(const Color: TPdfDeviceColor): TPdfPaint; static;
    class function FromBitmap(const Bitmap: TPdfBitmap; const BitmapToDevice: TPdfMatrix; const TileMode: TPdfTileMode;
                              const Filter: TPdfImageFilter): TPdfPaint; static;
  end;

  TPdfComposite = record
    // Constant alpha 0..1
    Alpha: Single;
    BlendMode: TPdfBlendMode;
    // Nil or a mask in device pixels; not owned
    SoftMask: TPdfAlphaMask;
    AntiAlias: Boolean;

    // Alpha 1, Normal, no soft mask, anti-aliased
    class function Default: TPdfComposite; static;
  end;

  // An immutable clip: the intersection of this path and all parents. Shared by graphics states, compared by identity.
  IPdfClipPath = interface
    ['{8E3C1F52-4B7A-4D69-9A0E-2C5D7B1F6A93}']
    // Nil for the first path
    function Parent: IPdfClipPath;
    // Owned by the clip
    function Path: TPdfPath;
    // Path space to device pixels
    function Transform: TPdfMatrix;
    function FillRule: TPdfFillRule;
  end;

  IPdfRasterDevice = interface;

  // What PageDrawer needs of Graphics2D. All geometry comes with its own transform to device pixels.
  IPdfGraphicsDevice = interface
    ['{2A7D5E14-9C3B-4F86-B1D2-7E0A4C9F3B58}']
    function Width: Integer;
    function Height: Integer;
    // Following operations are clipped to Clip (nil: no clip). Clipping is not anti-aliased, like Java2D.
    procedure SetClip(const Clip: IPdfClipPath);
    procedure FillPath(const Path: TPdfPath; const Transform: TPdfMatrix; const FillRule: TPdfFillRule; const Paint: TPdfPaint;
                       const Composite: TPdfComposite);
    // The stroke is built in path space and then transformed, like Java2D with a transform
    procedure StrokePath(const Path: TPdfPath; const Transform: TPdfMatrix; const Stroke: TPdfStrokeStyle; const Paint: TPdfPaint;
                         const Composite: TPdfComposite);
    // Pixel (i, j) of Bitmap covers [i, i + 1] x [j, j + 1] in bitmap space
    procedure DrawBitmap(const Bitmap: TPdfBitmap; const BitmapToDevice: TPdfMatrix; const Filter: TPdfImageFilter;
                         const Composite: TPdfComposite);
    // Every pixel becomes Color; the clip does not apply
    procedure Clear(const Color: TPdfDeviceColor);
    // A transparent offscreen device of the same backend (transparency groups, soft masks, pattern cells)
    function CreateLayer(const Width, Height: Integer): IPdfRasterDevice;
    // A copy of the pixels in Area, clipped to the device. False for a device without pixels (a vector backend).
    function TryReadPixels(const Area: TRect; out Bitmap: TPdfBitmap): Boolean;
  end;

  IPdfRasterDevice = interface(IPdfGraphicsDevice)
    ['{C41F7A08-3D6E-4B25-8F93-A6E2D05B1C77}']
    // A copy; the caller owns it
    function ToBitmap: TPdfBitmap;
  end;

  IPdfRenderBackend = interface
    ['{5B9E2D71-0A4C-4E38-9F16-D3C87A2B4E05}']
    // 'Skia', later 'Native'
    function Name: string;
    // Raises EArgumentOutOfRangeException when Width or Height < 1 or Width * Height > MaxBitmapPixels
    function CreateRasterDevice(const Width, Height: Integer): IPdfRasterDevice;
  end;

implementation

{ TPdfPaint }

class function TPdfPaint.Solid(const Color: TPdfDeviceColor): TPdfPaint;
begin
  Result := Default(TPdfPaint);
  Result.Kind := TPdfPaintKind.Solid;
  Result.Color := Color;
  Result.BitmapToDevice := TPdfMatrix.Identity;
end;

class function TPdfPaint.FromBitmap(const Bitmap: TPdfBitmap; const BitmapToDevice: TPdfMatrix; const TileMode: TPdfTileMode;
                                    const Filter: TPdfImageFilter): TPdfPaint;
begin
  Result := Default(TPdfPaint);
  Result.Kind := TPdfPaintKind.Bitmap;
  Result.Bitmap := Bitmap;
  Result.BitmapToDevice := BitmapToDevice;
  Result.TileMode := TileMode;
  Result.Filter := Filter;
end;

{ TPdfComposite }

class function TPdfComposite.Default: TPdfComposite;
begin
  Result.Alpha := 1;
  Result.BlendMode := TPdfBlendMode.Normal;
  Result.SoftMask := nil;
  Result.AntiAlias := True;
end;

end.
