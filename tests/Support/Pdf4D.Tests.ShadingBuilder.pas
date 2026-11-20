// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.ShadingBuilder;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.Defines,
  Pdf4D.Common.Log,
  Pdf4D.Graphics.Shading,
  Pdf4D.Model.Document,
  Pdf4D.Model.DocumentContext,
  Pdf4D.Model.Page,
  Pdf4D.Model.Resources,
  Pdf4D.Model.Tests.Support,
  Pdf4D.Render.Bitmap;

type
  // A document whose page has the shading /Sh1 in its resources, for the tests of the shadings and their rasterizer. Object 5 is a stream
  // that a shading can use as its function.
  TShadingTestDocument = class
  private
    FModels: TModelTestDocuments;
    FLines: TList<string>;
    FLog: TPdfLog;
    FContext: TPDDocumentContext;
    FPage: TPDPage;

    function GetResources: TPDResources;

  public
    // ShadingBody is the text between << >> of the dictionary of /Sh1; StreamEntries and StreamData make object 5 (no stream without data)
    constructor Create(const ShadingBody: string; const StreamEntries: string = ''; const StreamData: string = '');
    destructor Destroy; override;

    // A new shading of /Sh1; the caller owns it. It needs this document to stay.
    function NewShading: TPDShading;
    function HasLogLine(const Fragment: string): Boolean;

    property Resources: TPDResources read GetResources;
  end;

  // Pixel access for the tests of the rasterizer
  TShadingPixels = record
    // The color of the pixel (X, Y) of a bitmap, as straight RGBA
    class function At(const Bitmap: TPdfBitmap; const X, Y: Integer): TPdfDeviceColor; static;
    class function AreNear(const Actual: TPdfDeviceColor; const Red, Green, Blue, Alpha, Tolerance: Integer): Boolean; static;
    class function Describe(const Color: TPdfDeviceColor): string; static;
  end;

implementation

uses
  Pdf4D.Cos.Base,
  Pdf4D.Tests.PdfBuilder;

const
  PageObject = 3;
  StreamObject = 5;
  PageText = '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Resources << /Shading << /Sh1 << %s >> >> >> >>';

{ TShadingTestDocument }

constructor TShadingTestDocument.Create(const ShadingBody, StreamEntries, StreamData: string);
begin
  inherited Create;
  FModels := TModelTestDocuments.Create;
  FLines := TList<string>.Create;
  FLog := TPdfLog.Create(
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      FLines.Add(Message);
    end);

  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  try
    Builder.AddObject(PageObject, Format(PageText, [ShadingBody]));
    if StreamData <> '' then
    begin
      Builder.AddStreamObject(StreamObject, StreamEntries, TEncoding.ASCII.GetBytes(StreamData));
    end;

    const Document = FModels.Open(Builder);
    FContext := TPDDocumentContext.Create(FLog, TPdfLoadOptions.Default);
    FPage := TPDPage.Create(Document.Pages.Get(0).CosObject, FContext);
  finally
    Builder.Free;
  end;
end;

destructor TShadingTestDocument.Destroy;
begin
  FPage.Free;
  FContext.Free;
  FLog.Free;
  FLines.Free;
  FModels.Free;
  inherited;
end;

function TShadingTestDocument.GetResources: TPDResources;
begin
  Result := FPage.Resources;
end;

function TShadingTestDocument.NewShading: TPDShading;
begin
  var Value: TCosBase;
  if not Resources.TryGetShading('Sh1', Value) then
  begin
    raise EPdfParseException.Create('The test document has no shading /Sh1');
  end;

  Result := TPDShading.Create(Value, Resources);
end;

function TShadingTestDocument.HasLogLine(const Fragment: string): Boolean;
begin
  Result := False;
  for var Line in FLines do
  begin
    Result := (Result or Line.Contains(Fragment));
  end;
end;

{ TShadingPixels }

class function TShadingPixels.At(const Bitmap: TPdfBitmap; const X, Y: Integer): TPdfDeviceColor;
begin
  Result := Bitmap.GetPixel(X, Y);
end;

class function TShadingPixels.AreNear(const Actual: TPdfDeviceColor; const Red, Green, Blue, Alpha, Tolerance: Integer): Boolean;
begin
  Result := ((Abs(Actual.R - Red) <= Tolerance) and (Abs(Actual.G - Green) <= Tolerance) and (Abs(Actual.B - Blue) <= Tolerance) and
             (Abs(Actual.A - Alpha) <= Tolerance));
end;

class function TShadingPixels.Describe(const Color: TPdfDeviceColor): string;
begin
  Result := Format('(%d, %d, %d, %d)', [Color.R, Color.G, Color.B, Color.A]);
end;

end.
