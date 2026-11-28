// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/examples/util/PrintImageLocations.java (3.0.8), the idea of collecting image places
// with a subclass of PDFGraphicsStreamEngine
unit Pdf4D.Extract.GraphicsCollector;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Content.Operator,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.ObjectKey,
  Pdf4D.Extract.Images.Interfaces,
  Pdf4D.Extract.PageSpace,
  Pdf4D.Graphics.Image,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Model.Page,
  Pdf4D.Render.GraphicsEngine,
  Pdf4D.Render.Operators.Image;

type
  // Internal. Walks the content of a page (forms included, annotation appearances not) and records what it draws, in page
  // coordinates. Nothing is painted and no image is decoded to find it. Text is ignored.
  TPdfGraphicsCollector = class(TPdfGraphicsEngine)
  public
    const
      NoDecode = -1;
      DecodeAll = -2;

  private
    FPageIndex: Integer;
    FSpace: TPdfPageSpace;
    FImages: TList<TPdfImageInfo>;
    FHasXObjectKey: Boolean;
    FXObjectKey: TCosObjectKey;
    FCollectImages: Boolean;
    FCollectShapes: Boolean;
    FDecodeIndex: Integer;

    class function SpelledOut(const FilterName: string): string; static;
    class procedure DescribeColorSpace(const Image: TPDImage; var Info: TPdfImageInfo); static;
    function DescribeImage(const Image: TPDImage): TPdfImageInfo;
    function TryPlace(var Info: TPdfImageInfo): Boolean;

  protected
    procedure PrepareEngineForPage(const Page: TPDPage); override;

  public
    constructor Create(const PageIndex: Integer);
    destructor Destroy; override;

    // The Do operator tells which indirect object the XObject that it draws is; ClearXObjectKey follows when it is drawn
    procedure NoteXObjectKey(const Key: TCosObjectKey);
    procedure ClearXObjectKey;

    // The placements found, in the order of drawing
    function Images: TArray<TPdfImageInfo>;

    procedure DrawImage(const Image: TPDImage); override;
    procedure AppendRectangle(const P0, P1, P2, P3: TPointF); override;
    procedure Clip(const FillRule: TPdfFillRule); override;
    procedure MoveTo(const X, Y: Single); override;
    procedure LineTo(const X, Y: Single); override;
    procedure CurveTo(const X1, Y1, X2, Y2, X3, Y3: Single); override;
    function TryGetCurrentPoint(out Point: TPointF): Boolean; override;
    procedure ClosePath; override;
    procedure EndPath; override;
    procedure StrokePath; override;
    procedure FillPath(const FillRule: TPdfFillRule); override;
    procedure FillAndStrokePath(const FillRule: TPdfFillRule); override;
    procedure ShadingFill(const ShadingName: string); override;

    property CollectImages: Boolean read FCollectImages write FCollectImages;
    // Not used yet: the shapes of a page are collected by a later step
    property CollectShapes: Boolean read FCollectShapes write FCollectShapes;
    // NoDecode (-1): nothing is decoded; >= 0: the placement with this index is decoded; DecodeAll (-2): all placements are decoded
    property DecodeIndex: Integer read FDecodeIndex write FDecodeIndex;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Content.GraphicsState,
  Pdf4D.Common.Matrix,
  Pdf4D.Common.Quad,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.PdfObject,
  Pdf4D.Cos.Name;

type
  // Do: finds the indirect object of the image before the engine draws it, which is where its stable key comes from
  TCollectingDrawObjectOperator = class(TDrawObjectGraphicsOperator)
  public
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

{ TCollectingDrawObjectOperator }

procedure TCollectingDrawObjectOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  const Collector = (Engine as TPdfGraphicsCollector);
  const IsName = ((Length(Operands) > 0) and (Operands[0] is TCosName));
  if IsName and Assigned(Engine.Resources.CosObject) then
  begin
    var Entries: TCosDictionary;
    if Engine.Resources.CosObject.TryGetCosDictionary(TCosNames.XObject, Entries) then
    begin
      const Entry = Entries.GetItem(TCosName(Operands[0]).Name);
      if Entry is TCosObject then
      begin
        Collector.NoteXObjectKey(TCosObject(Entry).Key);
      end;
    end;
  end;

  try
    inherited Process(Operator, Operands);
  finally
    Collector.ClearXObjectKey;
  end;
end;

{ TPdfGraphicsCollector }

constructor TPdfGraphicsCollector.Create(const PageIndex: Integer);
begin
  inherited Create;
  FPageIndex := PageIndex;
  FImages := TList<TPdfImageInfo>.Create;
  FCollectImages := True;
  FDecodeIndex := NoDecode;
  AddOperator(TCollectingDrawObjectOperator.Create(Self));
end;

destructor TPdfGraphicsCollector.Destroy;
begin
  FImages.Free;
  inherited;
end;

procedure TPdfGraphicsCollector.PrepareEngineForPage(const Page: TPDPage);
begin
  inherited;
  FSpace := TPdfPageSpace.Create(Page.CropBox, Page.Rotation);
end;

procedure TPdfGraphicsCollector.NoteXObjectKey(const Key: TCosObjectKey);
begin
  FXObjectKey := Key;
  FHasXObjectKey := True;
end;

procedure TPdfGraphicsCollector.ClearXObjectKey;
begin
  FHasXObjectKey := False;
end;

function TPdfGraphicsCollector.Images: TArray<TPdfImageInfo>;
begin
  Result := FImages.ToArray;
end;

class function TPdfGraphicsCollector.SpelledOut(const FilterName: string): string;
begin
  Result := FilterName;
  if (FilterName = 'Fl') then
  begin
    Result := 'FlateDecode';
  end
  else if FilterName = 'AHx' then
  begin
    Result := 'ASCIIHexDecode';
  end
  else if FilterName = 'A85' then
  begin
    Result := 'ASCII85Decode';
  end
  else if FilterName = 'LZW' then
  begin
    Result := 'LZWDecode';
  end
  else if FilterName = 'RL' then
  begin
    Result := 'RunLengthDecode';
  end
  else if FilterName = 'CCF' then
  begin
    Result := 'CCITTFaxDecode';
  end
  else if FilterName = 'DCT' then
  begin
    Result := 'DCTDecode';
  end;
end;

// The colour space is made from its dictionary entry, which does not read any pixel. An image whose space cannot be made (none, or
// a damaged profile) is listed without it.
class procedure TPdfGraphicsCollector.DescribeColorSpace(const Image: TPDImage; var Info: TPdfImageInfo);
begin
  Info.ColorSpace := '';
  Info.ComponentCount := 0;
  if Image.IsStencil then
  begin
    Info.ComponentCount := 1;
    Exit;
  end;

  try
    const Space = Image.ColorSpace;
    Info.ColorSpace := Space.Name;
    Info.ComponentCount := Space.NumberOfComponents;
  except
    on Failure: Exception do
    begin
      if TPdfFailure.IsFatal(Failure) then
      begin
        raise;
      end;
    end;
  end;
end;

function TPdfGraphicsCollector.DescribeImage(const Image: TPDImage): TPdfImageInfo;
begin
  Result := Default(TPdfImageInfo);
  Result.PageIndex := FPageIndex;
  Result.Index := FImages.Count;
  Result.PixelWidth := Image.Width;
  Result.PixelHeight := Image.Height;
  Result.BitsPerComponent := Image.BitsPerComponent;
  Result.IsStencil := Image.IsStencil;
  Result.HasMask := Image.HasMaskOrSMask;
  Result.IsInline := (Image is TPDInlineImage);
  DescribeColorSpace(Image, Result);

  for var FilterName in Image.FilterChain do
  begin
    Result.Filters := Result.Filters + [SpelledOut(FilterName)];
  end;

  if (not Result.IsInline) and FHasXObjectKey then
  begin
    Result.ObjectNumber := Integer(FXObjectKey.Number);
    Result.Generation := FXObjectKey.Generation;
  end;
end;

// The unit square through the CTM, in page coordinates. False when a corner is not a finite number.
function TPdfGraphicsCollector.TryPlace(var Info: TPdfImageInfo): Boolean;
begin
  var Corner0, Corner1, Corner2, Corner3: TPointF;
  Result := (TryTransformPoint(0, 0, Corner0) and TryTransformPoint(1, 0, Corner1) and TryTransformPoint(1, 1, Corner2) and
             TryTransformPoint(0, 1, Corner3));
  if not Result then
  begin
    Exit;
  end;

  Info.Matrix := GraphicsState.CurrentTransformationMatrix;
  Info.Box := FSpace.BoundsOf(TPdfQuad.Create(Corner0, Corner1, Corner2, Corner3));
end;

procedure TPdfGraphicsCollector.DrawImage(const Image: TPDImage);
begin
  if not FCollectImages then
  begin
    Exit;
  end;

  var Info := DescribeImage(Image);
  if not TryPlace(Info) then
  begin
    LogWarning('An image is skipped: its place is not a finite number', []);
    Exit;
  end;
  FImages.Add(Info);
end;

procedure TPdfGraphicsCollector.AppendRectangle(const P0, P1, P2, P3: TPointF);
begin
end;

procedure TPdfGraphicsCollector.Clip(const FillRule: TPdfFillRule);
begin
end;

procedure TPdfGraphicsCollector.MoveTo(const X, Y: Single);
begin
end;

procedure TPdfGraphicsCollector.LineTo(const X, Y: Single);
begin
end;

procedure TPdfGraphicsCollector.CurveTo(const X1, Y1, X2, Y2, X3, Y3: Single);
begin
end;

function TPdfGraphicsCollector.TryGetCurrentPoint(out Point: TPointF): Boolean;
begin
  Point := TPointF.Create(0, 0);
  Result := False;
end;

procedure TPdfGraphicsCollector.ClosePath;
begin
end;

procedure TPdfGraphicsCollector.EndPath;
begin
end;

procedure TPdfGraphicsCollector.StrokePath;
begin
end;

procedure TPdfGraphicsCollector.FillPath(const FillRule: TPdfFillRule);
begin
end;

procedure TPdfGraphicsCollector.FillAndStrokePath(const FillRule: TPdfFillRule);
begin
end;

procedure TPdfGraphicsCollector.ShadingFill(const ShadingName: string);
begin
end;

end.
