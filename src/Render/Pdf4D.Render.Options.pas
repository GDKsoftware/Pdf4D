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
  // The work of all mesh shadings of one page together, in the units that MaxMeshWork counts for one shading
  DefaultMaxShadingWork: Int64           = 400000000;
  // Paths in the chain of clips of one page, forms and groups; more are replaced by the rectangle of their bounds
  DefaultMaxClipDepth                    = 1000;
  // Instructions of all type 4 functions of one page together (about ten seconds of work)
  DefaultMaxPostScriptWork: Int64        = 500000000;

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
    // Annotations drawn per page; the rest is skipped with a warning
    MaxAnnotations: Integer;
    // What all shadings of one page may do together (their pixels, steps of a line, pixels tested against a triangle, triangles, and a fixed
    // amount per shading that is painted); when it is spent, further shadings of the page are skipped with a warning
    MaxShadingWork: Int64;
    // How many clipping paths (W and W*, the clips of forms and groups) the clip of one page may chain. A longer chain makes every clip
    // change and every shading or group walk over all of it; beyond the limit the chain is replaced by the rectangle of its bounds
    // (the shapes of the paths are lost) and the page logs one warning.
    MaxClipDepth: Integer;
    // The instructions that all type 4 (PostScript calculator) functions of one page may execute together: shadings run one for every
    // pixel, and DeviceN and Separation images for every colour that is not in the cache of the colour space. When the budget is spent
    // the page logs one warning and the functions give the start of their range (a shading is then a flat colour, an image keeps its
    // tint).
    MaxPostScriptWork: Int64;

    // Export, opaque white background, anti-aliasing on, annotations on, and the limits above
    class function Default: TPdfRenderOptions; static;
  end;

implementation

uses
  Pdf4D.Model.Page;

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
  Result.MaxAnnotations := DefaultMaxAnnotations;
  Result.MaxShadingWork := DefaultMaxShadingWork;
  Result.MaxClipDepth := DefaultMaxClipDepth;
  Result.MaxPostScriptWork := DefaultMaxPostScriptWork;
end;

end.
