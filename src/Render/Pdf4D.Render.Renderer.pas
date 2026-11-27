// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/rendering/PDFRenderer.java (3.0.8), renderImage and hasBlendMode
unit Pdf4D.Render.Renderer;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Types,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Model.Document,
  Pdf4D.Model.OptionalContent,
  Pdf4D.Model.Page,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Render.GlyphCache,
  Pdf4D.Render.PageTransform,
  Pdf4D.Render.Renderer.Interfaces;

type
  TPdfRenderer = class(TInterfacedObject, IPdfRenderer)
  private
    // Keeps the document, and with it the model document and its pages, alive
    FDocument: IPdfDocument;
    FModel: TPDDocument;
    FBackend: IPdfRenderBackend;
    FGlyphCache: TPdfGlyphCache;

    class procedure CheckParams(const Params: TPdfRenderParams); static;
    class procedure CheckScaleAndRotation(const Scale: Single; const ExtraRotation: Integer); static;
    class function IsCancelled(const Params: TPdfRenderParams): Boolean; static;
    class function RegionOf(const Transform: TPdfPageTransform; const Params: TPdfRenderParams): TRect; static;
    class procedure RaiseTranslated(const Failure: Exception); static;
    function PageAt(const PageIndex: Integer): TPDPage;
    function TransformOf(const Page: TPDPage; const Params: TPdfRenderParams): TPdfPageTransform;
    function HasBlendMode(const Page: TPDPage): Boolean;
    function DrawOnDevice(const Page: TPDPage; const Device: IPdfGraphicsDevice; const Params: TPdfRenderParams): TPdfRenderStatus;
    function RenderBitmap(const Page: TPDPage; const Params: TPdfRenderParams; out Bitmap: TPdfBitmap): TPdfRenderStatus;

  public
    // Document must be made by this library (a TPdfDocument): the renderer reads its model. Raises EArgumentNilException for nil and
    // EArgumentException for another implementation of IPdfDocument.
    constructor Create(const Document: IPdfDocument; const Backend: IPdfRenderBackend);
    destructor Destroy; override;

    function Backend: IPdfRenderBackend;
    // The optional content configuration of the document (PDFRenderer.isGroupEnabled asks it); False when there is none
    function TryGetOptionalContentProperties(out Properties: TPDOptionalContentProperties): Boolean;
    function PageTransform(const PageIndex: Integer; const Scale: Single; const ExtraRotation: Integer = 0): TPdfPageTransform;
    function RenderPage(const PageIndex: Integer; const Device: IPdfGraphicsDevice; const Params: TPdfRenderParams): TPdfRenderStatus;
    function RenderToBitmap(const PageIndex: Integer; const Params: TPdfRenderParams; out Bitmap: TPdfBitmap): TPdfRenderStatus;

    // The glyph outlines of the pages that this renderer has drawn
    property GlyphCache: TPdfGlyphCache read FGlyphCache;
  end;

implementation

uses
  System.Math,
  Pdf4D.Api.DocumentModel.Interfaces,
  Pdf4D.Common.Defines,
  Pdf4D.Common.FloatGuard,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Names,
  Pdf4D.Model.ExtendedGraphicsState,
  Pdf4D.Render.PageDrawer;

const
  ValidRotations: array[0..3] of Integer = (0, 90, 180, 270);
  FullTurn = 360;

{ TPdfRenderer }

constructor TPdfRenderer.Create(const Document: IPdfDocument; const Backend: IPdfRenderBackend);
begin
  // Take the reference first: a backend that was made for this call (a const parameter holds no reference) is freed when a check fails
  FBackend := Backend;

  if not Assigned(Document) then
  begin
    raise EArgumentNilException.Create('Document');
  end;
  if not Assigned(Backend) then
  begin
    raise EArgumentNilException.Create('Backend');
  end;

  var Model: IPdfDocumentModel;
  if not Supports(Document, IPdfDocumentModel, Model) then
  begin
    raise EArgumentException.Create('The document does not come from this library');
  end;

  inherited Create;
  FDocument := Document;
  FModel := Model.ModelDocument;
  FGlyphCache := TPdfGlyphCache.Create(FModel.Context.Log);
end;

destructor TPdfRenderer.Destroy;
begin
  FGlyphCache.Free;
  inherited;
end;

function TPdfRenderer.Backend: IPdfRenderBackend;
begin
  Result := FBackend;
end;

function TPdfRenderer.TryGetOptionalContentProperties(out Properties: TPDOptionalContentProperties): Boolean;
begin
  Result := FModel.Catalog.TryGetOptionalContentProperties(Properties);
end;

class procedure TPdfRenderer.CheckScaleAndRotation(const Scale: Single; const ExtraRotation: Integer);
begin
  const IsScaleValid = ((Scale > 0) and (not Scale.IsInfinity));
  if not IsScaleValid then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('Render scale %g is not a positive number', [Scale]);
  end;

  var IsRotationValid := False;
  for var Rotation in ValidRotations do
  begin
    IsRotationValid := (IsRotationValid or (Rotation = ExtraRotation));
  end;
  if not IsRotationValid then
  begin
    raise EArgumentException.CreateFmt('Extra rotation %d is not 0, 90, 180 or 270', [ExtraRotation]);
  end;
end;

class procedure TPdfRenderer.CheckParams(const Params: TPdfRenderParams);
begin
  CheckScaleAndRotation(Params.Scale, Params.ExtraRotation);
end;

class function TPdfRenderer.IsCancelled(const Params: TPdfRenderParams): Boolean;
begin
  Result := (Assigned(Params.Cancel) and Params.Cancel.IsCancelled);
end;

function TPdfRenderer.PageAt(const PageIndex: Integer): TPDPage;
begin
  const Count = FModel.Pages.EnumeratedCount;
  const IsInRange = ((PageIndex >= 0) and (PageIndex < Count));
  if not IsInRange then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('Page index %d is outside the %d pages of the document', [PageIndex, Count]);
  end;

  Result := FModel.Pages.Get(PageIndex);
end;

function TPdfRenderer.TransformOf(const Page: TPDPage; const Params: TPdfRenderParams): TPdfPageTransform;
begin
  Result := TPdfPageTransform.Create(Page.CropBox, Page.Rotation + Params.ExtraRotation, Params.Scale);
end;

// The pixels of the whole page that the render covers: the region, or the whole page when there is none
class function TPdfRenderer.RegionOf(const Transform: TPdfPageTransform; const Params: TPdfRenderParams): TRect;
begin
  if Params.Region.IsEmpty then
  begin
    Result := TRect.Create(0, 0, Transform.Size.cx, Transform.Size.cy);
  end
  else
  begin
    Result := Params.Region;
  end;
end;

// A failure of the file that is no EPdfException becomes one, as the document handle does for the text
class procedure TPdfRenderer.RaiseTranslated(const Failure: Exception);
begin
  const IsTranslated = ((not (Failure is EPdfException)) and TPdfFailure.IsInputFailure(Failure));
  if IsTranslated then
  begin
    raise EPdfParseException.CreateFmt('The page cannot be rendered: %s', [Failure.Message]);
  end;
end;

// PDFRenderer.hasBlendMode: only the ExtGState resources of the page itself count
function TPdfRenderer.HasBlendMode(const Page: TPDPage): Boolean;
begin
  Result := False;
  const Resources = Page.Resources.CosObject;
  var States: TCosDictionary;
  if not (Assigned(Resources) and Resources.TryGetCosDictionary(TCosNames.ExtGState, States)) then
  begin
    Exit;
  end;

  for var Key in States.Keys do
  begin
    var Dictionary: TCosDictionary;
    if States.TryGetCosDictionary(Key, Dictionary) then
    begin
      const State = TPDExtendedGraphicsState.Create(Dictionary);
      try
        Result := (Result or (State.GetBlendModeName <> TCosNames.Normal));
      finally
        State.Free;
      end;
    end;
  end;
end;

function TPdfRenderer.PageTransform(const PageIndex: Integer; const Scale: Single; const ExtraRotation: Integer): TPdfPageTransform;
begin
  CheckScaleAndRotation(Scale, ExtraRotation);
  const Page = PageAt(PageIndex);

  try
    Result := TPdfPageTransform.Create(Page.CropBox, Page.Rotation + ExtraRotation, Scale);
  except
    on Failure: EPdfException do
    begin
      raise;
    end;
    on Failure: Exception do
    begin
      RaiseTranslated(Failure);
      raise;
    end;
  end;
end;

function TPdfRenderer.DrawOnDevice(const Page: TPDPage; const Device: IPdfGraphicsDevice; const Params: TPdfRenderParams): TPdfRenderStatus;
begin
  const Drawer = TPdfPageDrawer.Create(Self, Page, Device, Params);
  try
    Drawer.DrawPage;
    if Drawer.IsCancelled then
    begin
      Result := TPdfRenderStatus.Cancelled;
    end
    else
    begin
      Result := TPdfRenderStatus.Completed;
    end;
  finally
    Drawer.Free;
  end;
end;

function TPdfRenderer.RenderPage(const PageIndex: Integer; const Device: IPdfGraphicsDevice; const Params: TPdfRenderParams): TPdfRenderStatus;
begin
  if not Assigned(Device) then
  begin
    raise EArgumentNilException.Create('Device');
  end;
  CheckParams(Params);
  const Page = PageAt(PageIndex);

  const Pixels = Int64(Device.Width) * Device.Height;
  if Pixels > Params.Options.MaxRenderPixels then
  begin
    raise EPdfLimitExceededException.CreateFmt('The render target of %d x %d pixels is larger than the limit of %d pixels',
                                               [Device.Width, Device.Height, Params.Options.MaxRenderPixels]);
  end;

  if IsCancelled(Params) then
  begin
    Exit(TPdfRenderStatus.Cancelled);
  end;

  const PreviousMask = TPdfFloatGuard.Enter;
  try
    try
      Result := DrawOnDevice(Page, Device, Params);
    except
      on Failure: EPdfException do
      begin
        raise;
      end;
      on Failure: Exception do
      begin
        RaiseTranslated(Failure);
        raise;
      end;
    end;
  finally
    TPdfFloatGuard.Leave(PreviousMask);
  end;
end;

function TPdfRenderer.RenderBitmap(const Page: TPDPage; const Params: TPdfRenderParams; out Bitmap: TPdfBitmap): TPdfRenderStatus;
begin
  Bitmap := nil;
  const Transform = TransformOf(Page, Params);
  const Region = RegionOf(Transform, Params);
  const Width = Int64(Region.Right) - Region.Left;
  const Height = Int64(Region.Bottom) - Region.Top;
  const IsTooLarge = ((Width > High(Integer)) or (Height > High(Integer)) or (Width * Height > Params.Options.MaxRenderPixels) or
                      (Width * Height > MaxBitmapPixels));
  if IsTooLarge then
  begin
    raise EPdfLimitExceededException.CreateFmt('The render target of %d x %d pixels is larger than the limit of %d pixels',
                                               [Width, Height, Min(Params.Options.MaxRenderPixels, MaxBitmapPixels)]);
  end;

  // PDFBOX-4095: a page with blend modes at the top level is drawn on a transparent background and flattened afterwards
  const IsFlattened = HasBlendMode(Page);
  const Device = FBackend.CreateRasterDevice(Integer(Width), Integer(Height));
  if IsFlattened then
  begin
    Device.Clear(TPdfDeviceColor.Transparent);
  end
  else
  begin
    Device.Clear(Params.Options.Background);
  end;

  Result := DrawOnDevice(Page, Device, Params);
  if Result = TPdfRenderStatus.Completed then
  begin
    Bitmap := Device.ToBitmap;
    if IsFlattened then
    begin
      Bitmap.FlattenOn(Params.Options.Background);
    end;
  end;
end;

function TPdfRenderer.RenderToBitmap(const PageIndex: Integer; const Params: TPdfRenderParams; out Bitmap: TPdfBitmap): TPdfRenderStatus;
begin
  Bitmap := nil;
  CheckParams(Params);
  const Page = PageAt(PageIndex);

  if IsCancelled(Params) then
  begin
    Exit(TPdfRenderStatus.Cancelled);
  end;

  const PreviousMask = TPdfFloatGuard.Enter;
  try
    try
      Result := RenderBitmap(Page, Params, Bitmap);
    except
      on Failure: EPdfException do
      begin
        FreeAndNil(Bitmap);
        raise;
      end;
      on Failure: Exception do
      begin
        FreeAndNil(Bitmap);
        RaiseTranslated(Failure);
        raise;
      end;
    end;
  finally
    TPdfFloatGuard.Leave(PreviousMask);
  end;
end;

end.
