// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/color/PDPattern.java (the array [/Pattern base]), PDIndexed.java,
// PDSeparation.java, PDDeviceN.java, PDDeviceNAttributes.java and PDDeviceNProcess.java (3.0.8). The classes make their colour spaces
// from what the factory (Pdf4D.Graphics.Color.Factory) read from the arrays.
unit Pdf4D.Graphics.Color.Special;

{$EXCESSPRECISION OFF}
{$POINTERMATH ON}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Graphics.&Function,
  Pdf4D.Graphics.Color,
  Pdf4D.Graphics.Color.Pattern,
  Pdf4D.Render.Bitmap;

const
  // Entries of the lookup table of an Indexed colour space: hival is limited to 255
  MaxIndexedEntries = 256;
  // The colour of a colorant is one of at most this many (a raster has MaxRasterComponents components)
  MaxDeviceNColorants = MaxRasterComponents;

type
  // The Pattern colour space of an array: the components of a colour are those of the underlying space, and the name of the pattern comes
  // with them. The space belongs to the document context, which also owns the underlying space when that is no shared one.
  TPDPatternColorSpace = class(TPDPattern)
  private
    FUnderlyingColorSpace: TPDColorSpace;

  public
    // UnderlyingColorSpace is not owned; nil for [/Pattern] without one
    constructor Create(const UnderlyingColorSpace: TPDColorSpace);

    // Nil for a pattern space without underlying space, whose patterns are coloured
    property UnderlyingColorSpace: TPDColorSpace read FUnderlyingColorSpace;
  end;

  // [/Indexed base hival lookup]: a table of at most 256 colours of the base space. The table is turned into RGB once.
  TPDIndexed = class(TPDColorSpace)
  private
    FBaseColorSpace: TPDColorSpace;
    FActualMaxIndex: Integer;
    FRgbColorTable: TBytes;

    procedure InitRgbColorTable(const LookupData: TBytes; const BaseComponents: Integer);
    function ReadBaseSamples(const LookupData: TBytes; const BaseComponents: Integer): TPdfRaster;
    function IndexOfSample(const Sample: Single): Integer;
    function GetColorCount: Integer;

  public
    // BaseColorSpace is not owned. The table has Min(Hival, 255) + 1 colours of the base space, or as many complete colours as LookupData
    // holds when that is less. Raises EPdfParseException for a Hival under 0, a base without components and a lookup without a colour.
    constructor Create(const BaseColorSpace: TPDColorSpace; const Hival: Integer; const LookupData: TBytes);

    function Name: string; override;
    function NumberOfComponents: Integer; override;
    function GetDefaultDecode(const BitsPerComponent: Integer): TArray<Single>; override;
    function InitialColor: TPDColor; override;
    function ToRgb(const Components: TArray<Single>): TPdfRgb; override;
    // The raster holds the indexes (PDFBox reads them from the image without decoding)
    function ToRgbImage(const Raster: TPdfRaster): TPdfBitmap; override;

    property BaseColorSpace: TPDColorSpace read FBaseColorSpace;
    // The number of colours that the table really has
    property ColorCount: Integer read GetColorCount;
  end;

  // [/Separation name alternate tintTransform]
  TPDSeparation = class(TPDColorSpace)
  private
    const MaxCachedColors = 4096;

  private
    FColorantName: string;
    FAlternateColorSpace: TPDColorSpace;
    FTintTransform: TPDFunction;
    // toRGBMap: the colours by (int)(value * 255)
    FColorCache: TDictionary<Integer, TPdfRgb>;

    function IsLabAlternate: Boolean;
    function AlternateSamplesOf(const Sample: Integer): TArray<Byte>;
    function RgbBytesOf(const Sample: Integer): TArray<Byte>;
    function ToRgbImageThroughAlternate(const Raster: TPdfRaster): TPdfBitmap;
    function ToRgbImageWithoutAlternateImage(const Raster: TPdfRaster): TPdfBitmap;

  public
    // Takes over TintTransform (also when this raises). Raises EPdfParseException when the function has fewer outputs than the alternate
    // has components. The alternate is not owned.
    constructor Create(const ColorantName: string; const AlternateColorSpace: TPDColorSpace; const TintTransform: TPDFunction);
    destructor Destroy; override;

    function Name: string; override;
    function NumberOfComponents: Integer; override;
    function GetDefaultDecode(const BitsPerComponent: Integer): TArray<Single>; override;
    function InitialColor: TPDColor; override;
    function ToRgb(const Components: TArray<Single>): TPdfRgb; override;
    function ToRgbImage(const Raster: TPdfRaster): TPdfBitmap; override;

    // The colorant "None" shows nothing: the renderer paints it with a transparent colour (PDFBOX-4900)
    function IsNone: Boolean;

    property ColorantName: string read FColorantName;
    property AlternateColorSpace: TPDColorSpace read FAlternateColorSpace;
  end;

  // A spot colour of the /Colorants of the attributes of a DeviceN space
  TPDDeviceNColorant = record
    Name: string;
    // Not owned
    Separation: TPDSeparation;
  end;

  // PDDeviceNAttributes and its /Process (PDDeviceNProcess). The spaces are not owned.
  TPDDeviceNAttributes = record
    // /Subtype /NChannel
    IsNChannel: Boolean;
    HasProcess: Boolean;
    // The names of the components of the process colour space
    ProcessComponents: TArray<string>;
    // Nil when /Process has no /ColorSpace
    ProcessColorSpace: TPDColorSpace;
    Colorants: TArray<TPDDeviceNColorant>;
  end;

  // The colours of the last pixels that a DeviceN image had, by the samples of the pixel
  TDeviceNColorCache = class
  private
    const Slots = 4096;

  private
    FSampleCount: Integer;
    FSamples: TBytes;
    FValues: TArray<Cardinal>;
    FIsUsed: TArray<Boolean>;

    function SlotOf(const Pixel: PByte): Integer;

  public
    constructor Create(const SampleCount: Integer);

    function TryGet(const Pixel: PByte; out Value: Cardinal): Boolean;
    procedure Add(const Pixel: PByte; const Value: Cardinal);
  end;

  // [/DeviceN names alternate tintTransform attributes]
  TPDDeviceN = class(TPDColorSpace)
  private
    FColorantNames: TArray<string>;
    FAlternateColorSpace: TPDColorSpace;
    FTintTransform: TPDFunction;
    FAttributes: TPDDeviceNAttributes;
    FHasAttributes: Boolean;
    // For each colorant the component of the process colour space, or -1 for a spot colorant
    FColorantToComponent: TArray<Integer>;
    FSpotColorSpaces: TArray<TPDSeparation>;
    // False when a colorant has neither a process component nor a spot colour space: the tint transform does the whole conversion
    FCanUseAttributes: Boolean;

    procedure InitColorConversionCache;
    class function IndexOfName(const Names: TArray<string>; const Name: string): Integer; static;
    function CanConvertColorant(const Colorant: Integer): Boolean;
    function ComponentSpaceOf(const Colorant: Integer): TPDColorSpace;
    function IsProcessColorant(const Colorant: Integer): Boolean;
    function ToRgbWithAttributes(const Values: TArray<Single>): TPdfRgb;
    function ToRgbWithTintTransform(const Values: TArray<Single>): TPdfRgb;
    function ToRgbImageWithAttributes(const Raster: TPdfRaster): TPdfBitmap;
    function ToRgbImageWithTintTransform(const Raster: TPdfRaster): TPdfBitmap;
    function ColorantImage(const Raster: TPdfRaster; const Colorant: Integer): TPdfBitmap;
    function ConvertPixelWithTintTransform(const Pixel: PByte): Cardinal;

  public
    // Raises EPdfParseException for no colorant and for more than MaxDeviceNColorants; the factory asks before it builds anything else
    class procedure CheckColorantCount(const ColorantCount: Integer); static;

    // Takes over TintTransform (also when this raises). The colour spaces are not owned. Raises EPdfParseException like CheckColorantCount.
    constructor Create(const ColorantNames: TArray<string>; const AlternateColorSpace: TPDColorSpace; const TintTransform: TPDFunction;
                       const HasAttributes: Boolean; const Attributes: TPDDeviceNAttributes);
    destructor Destroy; override;

    function Name: string; override;
    function NumberOfComponents: Integer; override;
    function GetDefaultDecode(const BitsPerComponent: Integer): TArray<Single>; override;
    function InitialColor: TPDColor; override;
    function ToRgb(const Components: TArray<Single>): TPdfRgb; override;
    function ToRgbImage(const Raster: TPdfRaster): TPdfBitmap; override;

    function IsNChannel: Boolean;

    property ColorantNames: TArray<string> read FColorantNames;
    property AlternateColorSpace: TPDColorSpace read FAlternateColorSpace;
  end;

implementation

uses
  System.Math,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Names,
  Pdf4D.Graphics.Color.Cie,
  Pdf4D.Graphics.Color.IccBased;

resourcestring
  IndexedNegativeHival = 'The hival of an Indexed colour space is %d, it may not be negative';
  IndexedBaseWithoutComponents = 'The base of an Indexed colour space has no components';
  IndexedWithoutColors = 'The lookup table of an Indexed colour space holds no colour';
  SeparationTooFewOutputs = 'The tint transform function has less output parameters (%d) than the alternate colour space %s (%d)';
  DeviceNColorantCount = 'A DeviceN colour space has 1 to %d colorants, not %d';

const
  ByteScale = 255.0;
  BytesPerRgbPixel = 3;
  WhiteChannel = 255;
  ChannelShift = 8;
  PackedGreenShift = 8;
  PackedBlueShift = 16;
  ByteMask = $FF;

{ TPDPatternColorSpace }

constructor TPDPatternColorSpace.Create(const UnderlyingColorSpace: TPDColorSpace);
begin
  inherited Create;
  FUnderlyingColorSpace := UnderlyingColorSpace;
end;

{ TPDIndexed }

constructor TPDIndexed.Create(const BaseColorSpace: TPDColorSpace; const Hival: Integer; const LookupData: TBytes);
begin
  inherited Create;
  if Hival < 0 then
  begin
    raise EPdfParseException.CreateFmt(IndexedNegativeHival, [Hival]);
  end;

  const BaseComponents = BaseColorSpace.NumberOfComponents;
  if BaseComponents < 1 then
  begin
    raise EPdfParseException.Create(IndexedBaseWithoutComponents);
  end;

  FBaseColorSpace := BaseColorSpace;
  // readColorTable: some tables are too short
  FActualMaxIndex := Min(Hival, MaxIndexedEntries - 1);
  const CompleteColors = Length(LookupData) div BaseComponents;
  if CompleteColors < FActualMaxIndex + 1 then
  begin
    FActualMaxIndex := CompleteColors - 1;
  end;

  if FActualMaxIndex < 0 then
  begin
    raise EPdfParseException.Create(IndexedWithoutColors);
  end;

  InitRgbColorTable(LookupData, BaseComponents);
end;

// The samples of the colour table as the raster of a 1-row image in the base space: (int)(byte / 255f * 255f), which can be one less
function TPDIndexed.ReadBaseSamples(const LookupData: TBytes; const BaseComponents: Integer): TPdfRaster;
begin
  Result := TPdfRaster.Create(FActualMaxIndex + 1, 1, BaseComponents);
  try
    const Target = Result.RowStart(0);
    for var Position := 0 to (FActualMaxIndex + 1) * BaseComponents - 1 do
    begin
      const Entry: Single = Single(LookupData[Position]) / Single(ByteScale);
      const Scaled: Single = Entry * Single(ByteScale);
      Target[Position] := Byte(TruncateToInteger(Scaled));
    end;
  except
    Result.Free;
    raise;
  end;
end;

// initRgbColorTable
procedure TPDIndexed.InitRgbColorTable(const LookupData: TBytes; const BaseComponents: Integer);
begin
  const BaseRaster = ReadBaseSamples(LookupData, BaseComponents);
  try
    const RgbImage = FBaseColorSpace.ToRgbImage(BaseRaster);
    try
      SetLength(FRgbColorTable, (FActualMaxIndex + 1) * BytesPerRgbPixel);
      for var Index := 0 to FActualMaxIndex do
      begin
        const Pixel = RgbImage.GetPixel(Index, 0);
        FRgbColorTable[Index * BytesPerRgbPixel] := Pixel.R;
        FRgbColorTable[Index * BytesPerRgbPixel + 1] := Pixel.G;
        FRgbColorTable[Index * BytesPerRgbPixel + 2] := Pixel.B;
      end;
    finally
      RgbImage.Free;
    end;
  finally
    BaseRaster.Free;
  end;
end;

function TPDIndexed.GetColorCount: Integer;
begin
  Result := FActualMaxIndex + 1;
end;

function TPDIndexed.Name: string;
begin
  Result := TCosNames.Indexed;
end;

function TPDIndexed.NumberOfComponents: Integer;
begin
  Result := 1;
end;

function TPDIndexed.GetDefaultDecode(const BitsPerComponent: Integer): TArray<Single>;
begin
  Result := [0, Single(Power(2, BitsPerComponent)) - 1];
end;

function TPDIndexed.InitialColor: TPDColor;
begin
  Result := TPDColor.Create(Self, [0.0]);
end;

// Math.round of Java, then the index is clamped to the table
function TPDIndexed.IndexOfSample(const Sample: Single): Integer;
begin
  if IsNan(Sample) then
  begin
    Exit(0);
  end;

  const Shifted = Double(Sample) + 0.5;
  if Shifted < 1.0 then
  begin
    Exit(0);
  end;

  if Shifted >= FActualMaxIndex then
  begin
    Exit(FActualMaxIndex);
  end;

  Result := Trunc(Shifted);
end;

function TPDIndexed.ToRgb(const Components: TArray<Single>): TPdfRgb;
begin
  const Index = IndexOfSample(NormalizeComponents(Components)[0]);
  const Position = Index * BytesPerRgbPixel;
  Result := TPdfRgb.Create(Single(FRgbColorTable[Position]) / Single(ByteScale), Single(FRgbColorTable[Position + 1]) / Single(ByteScale),
                           Single(FRgbColorTable[Position + 2]) / Single(ByteScale));
end;

function TPDIndexed.ToRgbImage(const Raster: TPdfRaster): TPdfBitmap;
begin
  CheckRaster(Raster);
  Result := TPdfBitmap.Create(Raster.Width, Raster.Height);
  try
    var Row: TBytes;
    SetLength(Row, Raster.Width * BytesPerRgbPixel);
    for var Y := 0 to Raster.Height - 1 do
    begin
      const Source = Raster.RowStart(Y);
      for var X := 0 to Raster.Width - 1 do
      begin
        const Position = Min(Integer(Source[X]), FActualMaxIndex) * BytesPerRgbPixel;
        Row[X * BytesPerRgbPixel] := FRgbColorTable[Position];
        Row[X * BytesPerRgbPixel + 1] := FRgbColorTable[Position + 1];
        Row[X * BytesPerRgbPixel + 2] := FRgbColorTable[Position + 2];
      end;
      StoreRgbRow(Result, Y, @Row[0]);
    end;
  except
    Result.Free;
    raise;
  end;
end;

{ TPDSeparation }

constructor TPDSeparation.Create(const ColorantName: string; const AlternateColorSpace: TPDColorSpace; const TintTransform: TPDFunction);
begin
  inherited Create;
  FTintTransform := TintTransform;
  FColorantName := ColorantName;
  FAlternateColorSpace := AlternateColorSpace;
  FColorCache := TDictionary<Integer, TPdfRgb>.Create;

  const OutputCount = TintTransform.NumberOfOutputParameters;
  const HasTooFewOutputs = ((OutputCount > 0) and (OutputCount < AlternateColorSpace.NumberOfComponents));
  if HasTooFewOutputs then
  begin
    raise EPdfParseException.CreateFmt(SeparationTooFewOutputs, [OutputCount, AlternateColorSpace.Name, AlternateColorSpace.NumberOfComponents]);
  end;
end;

destructor TPDSeparation.Destroy;
begin
  FColorCache.Free;
  FTintTransform.Free;
  inherited;
end;

function TPDSeparation.Name: string;
begin
  Result := TCosNames.Separation;
end;

function TPDSeparation.NumberOfComponents: Integer;
begin
  Result := 1;
end;

function TPDSeparation.GetDefaultDecode(const BitsPerComponent: Integer): TArray<Single>;
begin
  Result := [0, 1];
end;

function TPDSeparation.InitialColor: TPDColor;
begin
  Result := TPDColor.Create(Self, [1.0]);
end;

function TPDSeparation.IsNone: Boolean;
begin
  Result := (FColorantName = TCosNames.None);
end;

function TPDSeparation.ToRgb(const Components: TArray<Single>): TPdfRgb;
begin
  const Values = NormalizeComponents(Components);
  const Key = TruncateToInteger(Values[0] * Single(ByteScale));
  if FColorCache.TryGetValue(Key, Result) then
  begin
    Exit;
  end;

  Result := FAlternateColorSpace.ToRgb(FTintTransform.Eval(Values));
  if FColorCache.Count < MaxCachedColors then
  begin
    FColorCache.Add(Key, Result);
  end;
end;

// PDFBOX-3622 and PDFBOX-5778: the regular conversion fails for an alternate in the Lab colour space
function TPDSeparation.IsLabAlternate: Boolean;
begin
  if FAlternateColorSpace is TPDLab then
  begin
    Exit(True);
  end;

  Result := ((FAlternateColorSpace is TPDICCBased) and (TPDICCBased(FAlternateColorSpace).Alternate is TPDLab));
end;

// tintTransform(samples, alt): the sample of 0..255 through the function, as the bytes of the alternate space
function TPDSeparation.AlternateSamplesOf(const Sample: Integer): TArray<Byte>;
begin
  const Fraction: Single = Single(Sample) / Single(ByteScale);
  const Output = FTintTransform.Eval([Fraction]);
  SetLength(Result, FAlternateColorSpace.NumberOfComponents);
  for var Component := 0 to High(Result) do
  begin
    const IsGiven = (Component < Length(Output));
    if IsGiven then
    begin
      Result[Component] := Byte(TruncateToInteger(Output[Component] * Single(ByteScale)) and ByteMask);
    end
    else
    begin
      Result[Component] := 0;
    end;
  end;
end;

function TPDSeparation.ToRgbImageThroughAlternate(const Raster: TPdfRaster): TPdfBitmap;
begin
  const AlternateComponents = FAlternateColorSpace.NumberOfComponents;
  const AlternateRaster = TPdfRaster.Create(Raster.Width, Raster.Height, AlternateComponents);
  try
    var Table: array[Byte] of TArray<Byte>;
    for var Y := 0 to Raster.Height - 1 do
    begin
      const Source = Raster.RowStart(Y);
      const Target = AlternateRaster.RowStart(Y);
      for var X := 0 to Raster.Width - 1 do
      begin
        if Table[Source[X]] = nil then
        begin
          Table[Source[X]] := AlternateSamplesOf(Source[X]);
        end;
        Move(Table[Source[X]][0], Target[X * AlternateComponents], AlternateComponents);
      end;
    end;

    Result := FAlternateColorSpace.ToRgbImage(AlternateRaster);
  finally
    AlternateRaster.Free;
  end;
end;

// toRGBImage2: the sample through the tint transform and the alternate space, one pixel at a time
function TPDSeparation.RgbBytesOf(const Sample: Integer): TArray<Byte>;
begin
  const Fraction: Single = Single(Sample) / Single(ByteScale);
  const Rgb = FAlternateColorSpace.ToRgb(FTintTransform.Eval([Fraction]));
  Result := [TruncateChannelToByte(Rgb.R), TruncateChannelToByte(Rgb.G), TruncateChannelToByte(Rgb.B)];
end;

function TPDSeparation.ToRgbImageWithoutAlternateImage(const Raster: TPdfRaster): TPdfBitmap;
begin
  Result := TPdfBitmap.Create(Raster.Width, Raster.Height);
  try
    var Table: array[Byte] of TArray<Byte>;
    var Row: TBytes;
    SetLength(Row, Raster.Width * BytesPerRgbPixel);
    for var Y := 0 to Raster.Height - 1 do
    begin
      const Source = Raster.RowStart(Y);
      for var X := 0 to Raster.Width - 1 do
      begin
        if Table[Source[X]] = nil then
        begin
          Table[Source[X]] := RgbBytesOf(Source[X]);
        end;
        Move(Table[Source[X]][0], Row[X * BytesPerRgbPixel], BytesPerRgbPixel);
      end;
      StoreRgbRow(Result, Y, @Row[0]);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TPDSeparation.ToRgbImage(const Raster: TPdfRaster): TPdfBitmap;
begin
  CheckRaster(Raster);
  if IsLabAlternate then
  begin
    Result := ToRgbImageWithoutAlternateImage(Raster);
  end
  else
  begin
    Result := ToRgbImageThroughAlternate(Raster);
  end;
end;

{ TDeviceNColorCache }

constructor TDeviceNColorCache.Create(const SampleCount: Integer);
begin
  inherited Create;
  FSampleCount := SampleCount;
  SetLength(FSamples, Slots * SampleCount);
  SetLength(FValues, Slots);
  SetLength(FIsUsed, Slots);
end;

// FNV-1a of the samples of the pixel
function TDeviceNColorCache.SlotOf(const Pixel: PByte): Integer;
begin
  var Hash: Cardinal := 2166136261;
  for var Index := 0 to FSampleCount - 1 do
  begin
    Hash := Cardinal((UInt64(Hash xor Pixel[Index]) * 16777619) and $FFFFFFFF);
  end;
  Result := Integer(Hash and (Slots - 1));
end;

function TDeviceNColorCache.TryGet(const Pixel: PByte; out Value: Cardinal): Boolean;
begin
  const Slot = SlotOf(Pixel);
  Result := (FIsUsed[Slot] and CompareMem(@FSamples[Slot * FSampleCount], Pixel, FSampleCount));
  if Result then
  begin
    Value := FValues[Slot];
  end
  else
  begin
    Value := 0;
  end;
end;

procedure TDeviceNColorCache.Add(const Pixel: PByte; const Value: Cardinal);
begin
  const Slot = SlotOf(Pixel);
  Move(Pixel^, FSamples[Slot * FSampleCount], FSampleCount);
  FValues[Slot] := Value;
  FIsUsed[Slot] := True;
end;

{ TPDDeviceN }

class procedure TPDDeviceN.CheckColorantCount(const ColorantCount: Integer);
begin
  const IsCountValid = ((ColorantCount >= 1) and (ColorantCount <= MaxDeviceNColorants));
  if not IsCountValid then
  begin
    raise EPdfParseException.CreateFmt(DeviceNColorantCount, [MaxDeviceNColorants, ColorantCount]);
  end;
end;

constructor TPDDeviceN.Create(const ColorantNames: TArray<string>; const AlternateColorSpace: TPDColorSpace; const TintTransform: TPDFunction;
                              const HasAttributes: Boolean; const Attributes: TPDDeviceNAttributes);
begin
  inherited Create;
  FTintTransform := TintTransform;
  FColorantNames := ColorantNames;
  FAlternateColorSpace := AlternateColorSpace;
  FHasAttributes := HasAttributes;
  FAttributes := Attributes;

  CheckColorantCount(Length(ColorantNames));

  InitColorConversionCache;
end;

destructor TPDDeviceN.Destroy;
begin
  FTintTransform.Free;
  inherited;
end;

// initColorConversionCache: there is nothing to cache for a space without attributes
procedure TPDDeviceN.InitColorConversionCache;
begin
  FCanUseAttributes := False;
  if not FHasAttributes then
  begin
    Exit;
  end;

  const ColorantCount = Length(FColorantNames);
  SetLength(FColorantToComponent, ColorantCount);
  SetLength(FSpotColorSpaces, ColorantCount);
  for var Colorant := 0 to ColorantCount - 1 do
  begin
    FColorantToComponent[Colorant] := -1;
    if FAttributes.HasProcess then
    begin
      FColorantToComponent[Colorant] := IndexOfName(FAttributes.ProcessComponents, FColorantNames[Colorant]);
    end;

    // Spot colours may replace process colours with the same name, if the subtype is not NChannel
    for var Spot in FAttributes.Colorants do
    begin
      if Spot.Name = FColorantNames[Colorant] then
      begin
        FSpotColorSpaces[Colorant] := Spot.Separation;
        if not FAttributes.IsNChannel then
        begin
          FColorantToComponent[Colorant] := -1;
        end;
      end;
    end;
  end;

  FCanUseAttributes := True;
  for var Colorant := 0 to ColorantCount - 1 do
  begin
    FCanUseAttributes := (FCanUseAttributes and CanConvertColorant(Colorant));
  end;
end;

// List.indexOf: the first of the names that is Name, or -1
class function TPDDeviceN.IndexOfName(const Names: TArray<string>; const Name: string): Integer;
begin
  for var Index := 0 to High(Names) do
  begin
    if Names[Index] = Name then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

// PDFBox falls back to the tint transform for a colorant that is a spot colorant without spot colour space (Altona Visual); a process
// colorant without process colour space, or with a component that the space does not have, fails there and falls back here
function TPDDeviceN.CanConvertColorant(const Colorant: Integer): Boolean;
begin
  if FColorantToComponent[Colorant] >= 0 then
  begin
    const ProcessSpace = FAttributes.ProcessColorSpace;
    Exit(Assigned(ProcessSpace) and (FColorantToComponent[Colorant] < ProcessSpace.NumberOfComponents));
  end;

  Result := Assigned(FSpotColorSpaces[Colorant]);
end;

function TPDDeviceN.IsProcessColorant(const Colorant: Integer): Boolean;
begin
  Result := (FColorantToComponent[Colorant] >= 0);
end;

function TPDDeviceN.ComponentSpaceOf(const Colorant: Integer): TPDColorSpace;
begin
  if IsProcessColorant(Colorant) then
  begin
    Result := FAttributes.ProcessColorSpace;
  end
  else
  begin
    Result := FSpotColorSpaces[Colorant];
  end;
end;

function TPDDeviceN.Name: string;
begin
  Result := TCosNames.DeviceN;
end;

function TPDDeviceN.NumberOfComponents: Integer;
begin
  Result := Length(FColorantNames);
end;

function TPDDeviceN.GetDefaultDecode(const BitsPerComponent: Integer): TArray<Single>;
begin
  SetLength(Result, NumberOfComponents * 2);
  for var Component := 0 to NumberOfComponents - 1 do
  begin
    Result[Component * 2] := 0;
    Result[Component * 2 + 1] := 1;
  end;
end;

function TPDDeviceN.InitialColor: TPDColor;
begin
  var Initial: TArray<Single>;
  SetLength(Initial, NumberOfComponents);
  for var Component := 0 to High(Initial) do
  begin
    Initial[Component] := 1;
  end;
  Result := TPDColor.Create(Self, Initial);
end;

function TPDDeviceN.IsNChannel: Boolean;
begin
  Result := (FHasAttributes and FAttributes.IsNChannel);
end;

function TPDDeviceN.ToRgb(const Components: TArray<Single>): TPdfRgb;
begin
  const Values = NormalizeComponents(Components);
  if FCanUseAttributes then
  begin
    Result := ToRgbWithAttributes(Values);
  end
  else
  begin
    Result := ToRgbWithTintTransform(Values);
  end;
end;

function TPDDeviceN.ToRgbWithTintTransform(const Values: TArray<Single>): TPdfRgb;
begin
  Result := FAlternateColorSpace.ToRgb(FTintTransform.Eval(Values));
end;

// Every colorant on its own in its colour space, the colours multiplied
function TPDDeviceN.ToRgbWithAttributes(const Values: TArray<Single>): TPdfRgb;
begin
  var Red: Single := 1;
  var Green: Single := 1;
  var Blue: Single := 1;
  for var Colorant := 0 to High(FColorantNames) do
  begin
    const ComponentSpace = ComponentSpaceOf(Colorant);
    var Samples: TArray<Single>;
    SetLength(Samples, ComponentSpace.NumberOfComponents);
    if IsProcessColorant(Colorant) then
    begin
      Samples[FColorantToComponent[Colorant]] := Values[Colorant];
    end
    else
    begin
      Samples[0] := Values[Colorant];
    end;

    const Rgb = ComponentSpace.ToRgb(Samples);
    Red := Red * Rgb.R;
    Green := Green * Rgb.G;
    Blue := Blue * Rgb.B;
  end;

  Result := TPdfRgb.Create(Red, Green, Blue);
end;

function TPDDeviceN.ToRgbImage(const Raster: TPdfRaster): TPdfBitmap;
begin
  CheckRaster(Raster);
  if FCanUseAttributes then
  begin
    Result := ToRgbImageWithAttributes(Raster);
  end
  else
  begin
    Result := ToRgbImageWithTintTransform(Raster);
  end;
end;

// One colorant of the raster as a raster of its colour space
function TPDDeviceN.ColorantImage(const Raster: TPdfRaster; const Colorant: Integer): TPdfBitmap;
begin
  const ComponentSpace = ComponentSpaceOf(Colorant);
  const ComponentCount = ComponentSpace.NumberOfComponents;
  const ComponentIndex = Max(FColorantToComponent[Colorant], 0);
  const ComponentRaster = TPdfRaster.Create(Raster.Width, Raster.Height, ComponentCount);
  try
    for var Y := 0 to Raster.Height - 1 do
    begin
      const Source = Raster.RowStart(Y);
      const Target = ComponentRaster.RowStart(Y);
      for var X := 0 to Raster.Width - 1 do
      begin
        Target[X * ComponentCount + ComponentIndex] := Source[X * NumberOfComponents + Colorant];
      end;
    end;

    Result := ComponentSpace.ToRgbImage(ComponentRaster);
  finally
    ComponentRaster.Free;
  end;
end;

// toRGBWithAttributes: a white image, multiplied (>> 8, as PDFBox does) with the image of every colorant
function TPDDeviceN.ToRgbImageWithAttributes(const Raster: TPdfRaster): TPdfBitmap;
begin
  var Composite: TBytes;
  SetLength(Composite, Int64(Raster.Width) * Raster.Height * BytesPerRgbPixel);
  FillChar(Composite[0], Length(Composite), WhiteChannel);

  for var Colorant := 0 to High(FColorantNames) do
  begin
    const ColorantRgb = ColorantImage(Raster, Colorant);
    try
      for var Y := 0 to Raster.Height - 1 do
      begin
        for var X := 0 to Raster.Width - 1 do
        begin
          const Pixel = ColorantRgb.GetPixel(X, Y);
          const Position = (Int64(Y) * Raster.Width + X) * BytesPerRgbPixel;
          Composite[Position] := Byte((Pixel.R * Composite[Position]) shr ChannelShift);
          Composite[Position + 1] := Byte((Pixel.G * Composite[Position + 1]) shr ChannelShift);
          Composite[Position + 2] := Byte((Pixel.B * Composite[Position + 2]) shr ChannelShift);
        end;
      end;
    finally
      ColorantRgb.Free;
    end;
  end;

  Result := TPdfBitmap.Create(Raster.Width, Raster.Height);
  try
    for var Y := 0 to Raster.Height - 1 do
    begin
      StoreRgbRow(Result, Y, @Composite[Int64(Y) * Raster.Width * BytesPerRgbPixel]);
    end;
  except
    Result.Free;
    raise;
  end;
end;

// The pixel through the tint transform and the alternate space, as the RGB bytes in the low 24 bits
function TPDDeviceN.ConvertPixelWithTintTransform(const Pixel: PByte): Cardinal;
begin
  var Source: TArray<Single>;
  SetLength(Source, NumberOfComponents);
  for var Component := 0 to High(Source) do
  begin
    Source[Component] := Single(Pixel[Component]) / Single(ByteScale);
  end;

  const Rgb = ToRgbWithTintTransform(Source);
  Result := Cardinal(TruncateChannelToByte(Rgb.R)) or (Cardinal(TruncateChannelToByte(Rgb.G)) shl PackedGreenShift) or
            (Cardinal(TruncateChannelToByte(Rgb.B)) shl PackedBlueShift);
end;

// toRGBWithTintTransform
function TPDDeviceN.ToRgbImageWithTintTransform(const Raster: TPdfRaster): TPdfBitmap;
begin
  const Cache = TDeviceNColorCache.Create(NumberOfComponents);
  try
    Result := TPdfBitmap.Create(Raster.Width, Raster.Height);
    try
      var Row: TBytes;
      SetLength(Row, Raster.Width * BytesPerRgbPixel);
      for var Y := 0 to Raster.Height - 1 do
      begin
        const Source = Raster.RowStart(Y);
        for var X := 0 to Raster.Width - 1 do
        begin
          const Pixel = Source + X * NumberOfComponents;
          var PackedColor: Cardinal;
          if not Cache.TryGet(Pixel, PackedColor) then
          begin
            PackedColor := ConvertPixelWithTintTransform(Pixel);
            Cache.Add(Pixel, PackedColor);
          end;
          Row[X * BytesPerRgbPixel] := Byte(PackedColor);
          Row[X * BytesPerRgbPixel + 1] := Byte(PackedColor shr PackedGreenShift);
          Row[X * BytesPerRgbPixel + 2] := Byte(PackedColor shr PackedBlueShift);
        end;
        StoreRgbRow(Result, Y, @Row[0]);
      end;
    except
      Result.Free;
      raise;
    end;
  finally
    Cache.Free;
  end;
end;

end.
