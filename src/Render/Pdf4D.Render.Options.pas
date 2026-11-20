// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.Options;

{$EXCESSPRECISION OFF}

interface

uses
  Pdf4D.Render.Bitmap;

const
  DefaultMaxRenderPixels: Int64          = 64 * 1024 * 1024;
  DefaultMaxImagePixels: Int64           = 64 * 1024 * 1024;
  DefaultMaxPatternDepth                 = 8;
  DefaultMaxSoftMaskDepth                = 8;
  DefaultMaxTransparencyGroupDepth       = 16;
  DefaultMaxType3Depth                   = 8;
  DefaultMaxTilingCells: Int64           = 1048576;
  // TilingPaint.MAXEDGE of PDFBox
  DefaultMaxTileEdge                     = 3000;

type
  {$SCOPEDENUMS ON}
  // RenderDestination of PDFBox; Export is the PDFRenderer.renderImage default
  TPdfRenderDestination = (Export, View, Print);
  {$SCOPEDENUMS OFF}

  TPdfRenderOptions = record
    Destination: TPdfRenderDestination;
    // Used by RenderToBitmap only
    Background: TPdfDeviceColor;
    AntiAlias: Boolean;
    RenderAnnotations: Boolean;
    // Width * height of one render target
    MaxRenderPixels: Int64;
    // A larger image is subsampled until it fits
    MaxImagePixels: Int64;
    MaxPatternDepth: Integer;
    MaxSoftMaskDepth: Integer;
    MaxTransparencyGroupDepth: Integer;
    MaxType3Depth: Integer;
    // Pattern cells per fill
    MaxTilingCells: Int64;
    MaxTileEdge: Integer;

    // Export, opaque white background, anti-aliasing on, annotations on, and the limits above
    class function Default: TPdfRenderOptions; static;
  end;

implementation

{ TPdfRenderOptions }

class function TPdfRenderOptions.Default: TPdfRenderOptions;
begin
  Result.Destination := TPdfRenderDestination.Export;
  Result.Background := TPdfDeviceColor.White;
  Result.AntiAlias := True;
  Result.RenderAnnotations := True;
  Result.MaxRenderPixels := DefaultMaxRenderPixels;
  Result.MaxImagePixels := DefaultMaxImagePixels;
  Result.MaxPatternDepth := DefaultMaxPatternDepth;
  Result.MaxSoftMaskDepth := DefaultMaxSoftMaskDepth;
  Result.MaxTransparencyGroupDepth := DefaultMaxTransparencyGroupDepth;
  Result.MaxType3Depth := DefaultMaxType3Depth;
  Result.MaxTilingCells := DefaultMaxTilingCells;
  Result.MaxTileEdge := DefaultMaxTileEdge;
end;

end.
