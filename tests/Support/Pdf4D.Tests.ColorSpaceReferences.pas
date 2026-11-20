// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// The colour spaces of tests/reference/color-spaces/colorspaces.pdf and the PDFBox 3.0.8 results for them (colorspaces.txt, written by
// tools/oracle/generate-color-spaces.ps1)
unit Pdf4D.Tests.ColorSpaceReferences;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Graphics.Color,
  Pdf4D.Model.Document,
  Pdf4D.Model.Resources;

type
  // "in:" line: the colour that goes into toRGB and the RGB that comes out
  TColorReference = record
    Input: TArray<Single>;
    Expected: TArray<Single>;
  end;

  // "img:" line: one row of 8-bit samples that goes into toRGBImage and the RGB bytes that come out
  TImageReference = record
    Components: Integer;
    Samples: TBytes;
    Expected: TBytes;
  end;

  // The "space:" block of one colour space
  TColorSpaceReference = class
  private
    FName: string;
    FColors: TList<TColorReference>;
    FImages: TList<TImageReference>;

  public
    constructor Create(const Name: string);
    destructor Destroy; override;

    property Name: string read FName;
    property Colors: TList<TColorReference> read FColors;
    property Images: TList<TImageReference> read FImages;
  end;

  // Opens colorspaces.pdf and reads colorspaces.txt; the colour spaces are those of the resources of its page
  TColorSpaceReferences = class
  private
    FDocument: TPDDocument;
    FResources: TPDResources;
    FReferences: TObjectList<TColorSpaceReference>;

    function ReferenceOf(const SpaceName: string): TColorSpaceReference;
    procedure ReadReferences(const FileName: string);
    class function ParseBytes(const Text: string): TBytes; static;

  public
    constructor Create;
    destructor Destroy; override;

    class function Folder: string; static;
    class function PdfPath: string; static;

    function SpaceOf(const SpaceName: string): TPDColorSpace;
    // The colours of the reference file through ToRgb, within Tolerance (0..1) per channel
    procedure CheckColors(const SpaceName: string; const Tolerance: Single);
    // The rows of samples of the reference file through ToRgbImage, within Tolerance (0..255) per channel
    procedure CheckImages(const SpaceName: string; const Tolerance: Integer);

    property Resources: TPDResources read FResources;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  DUnitX.TestFramework,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Name,
  Pdf4D.Graphics.Color.Factory,
  Pdf4D.Model.Page,
  Pdf4D.Render.Bitmap,
  Pdf4D.Tests.Functions,
  Pdf4D.Tests.IccBuilder;

const
  FolderName = 'color-spaces';
  ReferenceFileName = 'colorspaces.txt';
  PdfFileName = 'colorspaces.pdf';
  OutMarker = ' out:';

{ TColorSpaceReference }

constructor TColorSpaceReference.Create(const Name: string);
begin
  inherited Create;
  FName := Name;
  FColors := TList<TColorReference>.Create;
  FImages := TList<TImageReference>.Create;
end;

destructor TColorSpaceReference.Destroy;
begin
  FImages.Free;
  FColors.Free;
  inherited;
end;

{ TColorSpaceReferences }

constructor TColorSpaceReferences.Create;
begin
  inherited Create;
  FReferences := TObjectList<TColorSpaceReference>.Create(True);
  ReadReferences(TPath.Combine(Folder, ReferenceFileName));
  FDocument := TPDDocument.Load(TFileStream.Create(PdfPath, fmOpenRead or fmShareDenyWrite), True, TPdfLoadOptions.Default);
  FResources := FDocument.Pages.Get(0).Resources;
end;

destructor TColorSpaceReferences.Destroy;
begin
  FDocument.Free;
  FReferences.Free;
  inherited;
end;

class function TColorSpaceReferences.Folder: string;
begin
  Result := TPath.Combine(TPath.GetDirectoryName(TIccTestFiles.ReferenceFolder), FolderName);
end;

class function TColorSpaceReferences.PdfPath: string;
begin
  Result := TPath.Combine(Folder, PdfFileName);
end;

class function TColorSpaceReferences.ParseBytes(const Text: string): TBytes;
begin
  const Values = TFunctionTestBuilder.ParseSingles(Text);
  SetLength(Result, Length(Values));
  for var Index := 0 to High(Values) do
  begin
    Result[Index] := Byte(Round(Values[Index]));
  end;
end;

procedure TColorSpaceReferences.ReadReferences(const FileName: string);
begin
  var Current: TColorSpaceReference := nil;
  for var Line in TFile.ReadAllLines(FileName, TEncoding.UTF8) do
  begin
    const Colon = Line.IndexOf(':');
    if (Line.Trim = '') or Line.StartsWith('#') or (Colon < 0) then
    begin
      Continue;
    end;

    const Key = Line.Substring(0, Colon).Trim;
    const Value = Line.Substring(Colon + 1).Trim;
    if Key = 'space' then
    begin
      Current := TColorSpaceReference.Create(Value);
      FReferences.Add(Current);
    end
    else if Key = 'in' then
    begin
      const MarkerPosition = Value.IndexOf(OutMarker);
      var Reference: TColorReference;
      Reference.Input := TFunctionTestBuilder.ParseSingles(Value.Substring(0, MarkerPosition));
      Reference.Expected := TFunctionTestBuilder.ParseSingles(Value.Substring(MarkerPosition + Length(OutMarker)));
      Current.Colors.Add(Reference);
    end
    else if Key = 'img' then
    begin
      const MarkerPosition = Value.IndexOf(OutMarker);
      const Samples = Value.Substring(0, MarkerPosition).Trim;
      const FirstBlank = Samples.IndexOf(' ');
      var Reference: TImageReference;
      Reference.Components := StrToInt(Samples.Substring(0, FirstBlank));
      Reference.Samples := ParseBytes(Samples.Substring(FirstBlank + 1));
      Reference.Expected := ParseBytes(Value.Substring(MarkerPosition + Length(OutMarker)));
      Current.Images.Add(Reference);
    end;
  end;
end;

function TColorSpaceReferences.ReferenceOf(const SpaceName: string): TColorSpaceReference;
begin
  for var Reference in FReferences do
  begin
    if Reference.Name = SpaceName then
    begin
      Exit(Reference);
    end;
  end;
  raise EArgumentException.CreateFmt('The reference file has no colour space %s', [SpaceName]);
end;

function TColorSpaceReferences.SpaceOf(const SpaceName: string): TPDColorSpace;
begin
  const NameOperand = TCosName.Create(SpaceName);
  try
    Result := TPDColorSpaceFactory.Create(NameOperand, FResources);
  finally
    NameOperand.Free;
  end;
end;

procedure TColorSpaceReferences.CheckColors(const SpaceName: string; const Tolerance: Single);
begin
  const Space = SpaceOf(SpaceName);
  for var Reference in ReferenceOf(SpaceName).Colors do
  begin
    var Input := '';
    for var Value in Reference.Input do
    begin
      Input := Format('%s %g', [Input, Value]);
    end;

    const Rgb = Space.ToRgb(Reference.Input);
    Assert.AreEqual(Reference.Expected[0], Rgb.R, Tolerance, Format('%s red of%s', [SpaceName, Input]));
    Assert.AreEqual(Reference.Expected[1], Rgb.G, Tolerance, Format('%s green of%s', [SpaceName, Input]));
    Assert.AreEqual(Reference.Expected[2], Rgb.B, Tolerance, Format('%s blue of%s', [SpaceName, Input]));
  end;
end;

procedure TColorSpaceReferences.CheckImages(const SpaceName: string; const Tolerance: Integer);
begin
  const Space = SpaceOf(SpaceName);
  for var Reference in ReferenceOf(SpaceName).Images do
  begin
    const Width = Length(Reference.Samples) div Reference.Components;
    const Raster = TPdfRaster.Create(Width, 1, Reference.Components);
    try
      Move(Reference.Samples[0], Raster.Samples[0], Length(Reference.Samples));
      const Image = Space.ToRgbImage(Raster);
      try
        for var X := 0 to Width - 1 do
        begin
          const Pixel = Image.GetPixel(X, 0);
          Assert.AreEqual(Double(Reference.Expected[X * 3]), Double(Pixel.R), Tolerance, Format('%s red of pixel %d', [SpaceName, X]));
          Assert.AreEqual(Double(Reference.Expected[X * 3 + 1]), Double(Pixel.G), Tolerance, Format('%s green of pixel %d', [SpaceName, X]));
          Assert.AreEqual(Double(Reference.Expected[X * 3 + 2]), Double(Pixel.B), Tolerance, Format('%s blue of pixel %d', [SpaceName, X]));
        end;
      finally
        Image.Free;
      end;
    finally
      Raster.Free;
    end;
  end;
end;

end.
