// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.Renderer.Interfaces;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Types,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Render.Options,
  Pdf4D.Render.PageTransform;

type
  IPdfCancelToken = interface
    ['{7D20B6C3-5E19-4A8F-8C47-1F9B3E6D0A24}']
    // Thread safe
    function IsCancelled: Boolean;
  end;

  {$SCOPEDENUMS ON}
  TPdfRenderStatus = (Completed, Cancelled);
  {$SCOPEDENUMS OFF}

  TPdfRenderParams = record
    // Pixels per point (DPI / 72), > 0
    Scale: Single;
    // 0, 90, 180 or 270, clockwise, added to /Rotate
    ExtraRotation: Integer;
    // Pixels of the whole page at Scale; empty: the whole page
    Region: TRect;
    Options: TPdfRenderOptions;
    // Nil: cannot be cancelled
    Cancel: IPdfCancelToken;

    // The whole page with default options; raises EArgumentOutOfRangeException when Scale <= 0
    class function Create(const Scale: Single): TPdfRenderParams; static;
    class function FromDpi(const Dpi: Single): TPdfRenderParams; static;
  end;

  // One renderer per document; not thread safe, it is used by the thread that uses the document. Input problems that end a page raise
  // EPdfException descendants, problems inside a page are logged to the document log. Invalid arguments raise EArgument* exceptions.
  IPdfRenderer = interface
    ['{E6A43C90-2F7B-4D15-B8E0-94C1D5A7F362}']
    function Backend: IPdfRenderBackend;
    // The size and the matrix of the page as RenderToBitmap uses them, for the page at PageIndex with ExtraRotation added to /Rotate
    function PageTransform(const PageIndex: Integer; const Scale: Single; const ExtraRotation: Integer = 0): TPdfPageTransform;
    // Draws into Device without clearing it. Device pixel (0, 0) is pixel Params.Region.TopLeft of the whole page.
    // Raises EPdfLimitExceededException before drawing when Device.Width * Device.Height > Params.Options.MaxRenderPixels.
    function RenderPage(const PageIndex: Integer; const Device: IPdfGraphicsDevice; const Params: TPdfRenderParams): TPdfRenderStatus;
    // A new raster device of Backend with the size of the region (or page), cleared with Params.Options.Background, rendered like
    // PDFRenderer.renderImage (transparent first and flattened afterwards when the page uses blend modes, PDFBOX-4095).
    // Bitmap is nil when the result is Cancelled; the caller owns it otherwise.
    function RenderToBitmap(const PageIndex: Integer; const Params: TPdfRenderParams; out Bitmap: TPdfBitmap): TPdfRenderStatus;
  end;

implementation

const
  PointsPerInch = 72;

{ TPdfRenderParams }

class function TPdfRenderParams.Create(const Scale: Single): TPdfRenderParams;
begin
  const IsPositive = (Scale > 0);
  if not IsPositive then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('Render scale %g is not positive', [Scale]);
  end;

  Result := Default(TPdfRenderParams);
  Result.Scale := Scale;
  Result.Region := TRect.Empty;
  Result.Options := TPdfRenderOptions.Default;
end;

class function TPdfRenderParams.FromDpi(const Dpi: Single): TPdfRenderParams;
begin
  Result := Create(Dpi / PointsPerInch);
end;

end.
