// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/image/PDImage.java, PDImageXObject.java (getImage, applyMask,
// scaleImage, extractMatte, getMask, getSoftMask) and PDInlineImage.java (3.0.8), and of the use of DCTFilter.java and CCITTFaxFilter.java
// (the decoders themselves are Pdf4D.Codec.Jpeg and Pdf4D.Codec.CCITTFax). JPEG 2000 and JBIG2 are not supported, with the message of
// PDFBox for a missing plugin.
unit Pdf4D.Graphics.Image;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Common.Log,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Graphics.Color,
  Pdf4D.Graphics.Image.SampledReader,
  Pdf4D.Model.Resources,
  Pdf4D.Render.Bitmap;

type
  // PDImage: an image XObject or an inline image. Not thread safe. The image does not own its dictionary, its resources or the stream.
  TPDImage = class abstract
  private
    FParameters: TCosDictionary;
    FResources: TPDResources;
    FColorSpace: TPDColorSpace;

    function Lookup(const Name: string; out Value: TCosBase): Boolean;
    function BooleanOf(const Name: string): Boolean;
    function IntegerOf(const Name: string; const Default: Integer): Integer;
    function EffectiveColorSpace: TPDColorSpace;
    function DecodeEntries(const Decoded: TCosBase): TArray<Single>;
    function BuildSource(const ForOpaque: Boolean): TSampledImageSource;
    function ReadSamples: TBytes;
    class procedure RaiseForImageFilter(const FilterName: string); static;
    function FilterCount: Integer;
    function FilterParametersOf(const FilterIndex: Integer): TCosDictionary;
    function DctColorTransform(const FilterIndex: Integer): Integer;
    function DecodeJpeg(const Data: TBytes; const FilterIndex: Integer): TBytes;
    function DecodeCcitt(const Data: TBytes; const FilterIndex: Integer): TBytes;

  protected
    constructor Create(const Parameters: TCosDictionary; const Resources: TPDResources);

    // The abbreviation of the key in an inline image, empty when it has none
    function AbbreviationOf(const Name: string): string; virtual;
    // The data of the stream with the filters applied up to the first image filter, and the filters that are left
    function DecodeSamples(out RemainingFilters: TArray<string>): TBytes; virtual; abstract;
    function CreateColorSpace(const Value: TCosBase): TPDColorSpace; virtual;
    // Not a stencil: the RGB image with the colour key mask applied. Straight alpha, see TSampledImageReader.ReadRgb.
    function ReadStraightRgb(const Subsampling: Integer; const UseColorKey: Boolean): TPdfBitmap;
    // The subsampling for this image under MaxImagePixels
    function SubsamplingFor(const MaxImagePixels: Int64): Integer;
    function Log: TPdfLog;
    procedure LogWarning(const Fmt: string; const Args: array of const);
    procedure LogError(const Fmt: string; const Args: array of const);
    // The errors of an image that make it skipped rather than failing the page
    class function IsRecoverable(const Error: Exception): Boolean; static;

    property Parameters: TCosDictionary read FParameters;
    property Resources: TPDResources read FResources;

  public
    function Width: Integer;
    function Height: Integer;
    function BitsPerComponent: Integer;
    function IsStencil: Boolean;
    function Interpolate: Boolean;
    // nil for a stencil. Raises EPdfParseException for an image without a colour space and the exceptions of the colour space
    // factory for one that cannot be made.
    function ColorSpace: TPDColorSpace;
    // The decode array as PDFBox repairs it: two values per component, the default of the colour space when the entry is missing
    // or does not fit
    function Decode: TArray<Single>;
    function HasMaskOrSMask: Boolean; virtual;

    // getImage: RGBA with /Mask and /SMask applied, premultiplied. Subsampled (every Nth pixel, like the subsampling of PDFBox) when
    // Width * Height exceeds MaxImagePixels, with a log line. Caller owns it. False when the image cannot be decoded (logged).
    function TryGetImage(const MaxImagePixels: Int64; out Bitmap: TPdfBitmap): Boolean; virtual;
    // getStencilImage as a mask: alpha 255 where the stencil paints, 0 where it does not, colour 0. Caller owns it. False when the
    // image is no stencil or cannot be decoded (logged).
    function TryGetStencilMask(const MaxImagePixels: Int64; out Mask: TPdfBitmap): Boolean;
  end;

  // PDImageXObject
  TPDImageXObject = class(TPDImage)
  private
    FStream: TCosStream;
    FOwnedResources: TPDResources;

    // The soft mask and the mask of PDFBox are images of their own, with no resources: their colour space is DeviceGray
    class function CreateMask(const Stream: TCosStream; const Parent: TPDResources): TPDImageXObject; static;
    function BuildImage(const MaxImagePixels: Int64): TPdfBitmap;
    function TryExtractMatte(const SoftMask: TPDImageXObject; out Matte: TArray<Single>): Boolean;
    procedure ApplyMask(var Image: TPdfBitmap; const Mask: TPdfBitmap; const InterpolateMask, IsSoft: Boolean; const Matte: TArray<Single>);

  protected
    function AbbreviationOf(const Name: string): string; override;
    function DecodeSamples(out RemainingFilters: TArray<string>): TBytes; override;

  public
    // Stream and Resources are not owned and must outlive the image
    constructor Create(const Stream: TCosStream; const Resources: TPDResources);
    destructor Destroy; override;

    function HasMaskOrSMask: Boolean; override;
    function TryGetImage(const MaxImagePixels: Int64; out Bitmap: TPdfBitmap): Boolean; override;
  end;

  // PDInlineImage: the parameters of the BI operator (with the abbreviated keys) and the data between ID and EI
  TPDInlineImage = class(TPDImage)
  private
    FData: TBytes;

    function FilterNames: TArray<string>;

  protected
    function AbbreviationOf(const Name: string): string; override;
    function DecodeSamples(out RemainingFilters: TArray<string>): TBytes; override;
    function CreateColorSpace(const Value: TCosBase): TPDColorSpace; override;

  public
    // Parameters, Data and Resources are not owned and must outlive the image
    constructor Create(const Parameters: TCosDictionary; const Data: TBytes; const Resources: TPDResources);
  end;

implementation

uses
  System.Math,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Boolean,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.Number,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Codec.CCITTFax,
  Pdf4D.Codec.Jpeg,
  Pdf4D.Filter.Chain,
  Pdf4D.Filter.Factory,
  Pdf4D.Graphics.Color.Device,
  Pdf4D.Graphics.Color.Factory;

resourcestring
  JpxNotInstalled = 'Cannot read JPEG2000 image: Java Advanced Imaging (JAI) Image I/O Tools are not installed';
  Jbig2NotInstalled = 'Cannot read JBIG2 image: jbig2-imageio is not installed';
  UnsupportedImageFilter = 'Cannot read an image with the filter %s';
  NoColorSpace = 'could not determine color space';
  InlineIndexedNotSupported = 'Inline images with an abbreviated Indexed colour space are not supported yet';
  InlineColorSpaceIllegal = 'Illegal type of inline image color space';

const
  ByteMax = 255;
  LineFeed = 10;
  MaxJpegComponents = 4;
  BitsPerByte = 8;
  ExtraBitsOfGray = 8;
  GrayRed = 77;
  GrayGreen = 150;
  GrayBlue = 29;
  MatteFraction = 15;
  MatteRoundingHalf = 1 shl (MatteFraction - 1);
  MatteFactor = ByteMax shl MatteFraction;
  RgbComponents = 3;

  // The keys of an inline image and their abbreviations
  InlineAbbreviations: array[0..8, 0..1] of string = (
    ('BitsPerComponent', 'BPC'), ('ColorSpace', 'CS'), ('Decode', 'D'), ('DecodeParms', 'DP'), ('Filter', 'F'),
    ('Height', 'H'), ('ImageMask', 'IM'), ('Interpolate', 'I'), ('Width', 'W'));

{ TPDImage }

constructor TPDImage.Create(const Parameters: TCosDictionary; const Resources: TPDResources);
begin
  inherited Create;
  FParameters := Parameters;
  FResources := Resources;
end;

function TPDImage.AbbreviationOf(const Name: string): string;
begin
  Result := '';
end;

function TPDImage.Lookup(const Name: string; out Value: TCosBase): Boolean;
begin
  Result := FParameters.TryGetDictionaryObject(Name, Value);
  if not Result then
  begin
    const Abbreviation = AbbreviationOf(Name);
    Result := ((Abbreviation <> '') and FParameters.TryGetDictionaryObject(Abbreviation, Value));
  end;
end;

function TPDImage.BooleanOf(const Name: string): Boolean;
begin
  var Value: TCosBase;
  Result := (Lookup(Name, Value) and (Value is TCosBoolean) and TCosBoolean(Value).Value);
end;

function TPDImage.IntegerOf(const Name: string; const Default: Integer): Integer;
begin
  var Value: TCosBase;
  if Lookup(Name, Value) and (Value is TCosNumber) then
  begin
    Result := TCosNumber(Value).IntValue;
  end
  else
  begin
    Result := Default;
  end;
end;

function TPDImage.Log: TPdfLog;
begin
  Result := FResources.Context.Log;
end;

procedure TPDImage.LogWarning(const Fmt: string; const Args: array of const);
begin
  const Target = Log;
  if Assigned(Target) then
  begin
    Target.Warning(Fmt, Args);
  end;
end;

procedure TPDImage.LogError(const Fmt: string; const Args: array of const);
begin
  const Target = Log;
  if Assigned(Target) then
  begin
    Target.Error(Fmt, Args);
  end;
end;

class function TPDImage.IsRecoverable(const Error: Exception): Boolean;
begin
  Result := ((Error is EPdfException) or TPdfFailure.IsInputFailure(Error) or (Error is EArgumentException) or (Error is EInvalidOpException));
end;

function TPDImage.Width: Integer;
begin
  Result := IntegerOf(TCosNames.Width, -1);
end;

function TPDImage.Height: Integer;
begin
  Result := IntegerOf(TCosNames.Height, -1);
end;

function TPDImage.IsStencil: Boolean;
begin
  Result := BooleanOf(TCosNames.ImageMask);
end;

function TPDImage.BitsPerComponent: Integer;
begin
  if IsStencil then
  begin
    Exit(1);
  end;
  Result := IntegerOf(TCosNames.BitsPerComponent, -1);
end;

function TPDImage.Interpolate: Boolean;
begin
  Result := BooleanOf(TCosNames.Interpolate);
end;

function TPDImage.HasMaskOrSMask: Boolean;
begin
  Result := False;
end;

function TPDImage.CreateColorSpace(const Value: TCosBase): TPDColorSpace;
begin
  Result := TPDColorSpaceFactory.Create(Value, FResources);
end;

// getColorSpace: a stencil without a colour space is DeviceGray, "often missing"
function TPDImage.EffectiveColorSpace: TPDColorSpace;
begin
  if Assigned(FColorSpace) then
  begin
    Exit(FColorSpace);
  end;

  var Value: TCosBase;
  if Lookup(TCosNames.ColorSpace, Value) then
  begin
    FColorSpace := CreateColorSpace(Value);
  end
  else if IsStencil then
  begin
    FColorSpace := TPDDeviceGray.Instance;
  end;

  if not Assigned(FColorSpace) then
  begin
    raise EPdfParseException.Create(NoColorSpace);
  end;
  Result := FColorSpace;
end;

function TPDImage.ColorSpace: TPDColorSpace;
begin
  if IsStencil then
  begin
    Exit(nil);
  end;
  Result := EffectiveColorSpace;
end;

function TPDImage.DecodeEntries(const Decoded: TCosBase): TArray<Single>;
begin
  Result := nil;
  if not (Decoded is TCosArray) then
  begin
    Exit;
  end;

  const Items = TCosArray(Decoded);
  const Needed = EffectiveColorSpace.NumberOfComponents * 2;
  if Items.Count < Needed then
  begin
    Exit;
  end;

  SetLength(Result, Needed);
  for var Index := 0 to Needed - 1 do
  begin
    const Item = Items.GetObject(Index);
    if not (Item is TCosNumber) then
    begin
      Exit(nil);
    end;
    Result[Index] := TCosNumber(Item).FloatValue;
  end;

  const IsOutsideOfStencil = ((Result[0] < 0) or (Result[0] > 1) or (Result[1] < 0) or (Result[1] > 1));
  if IsStencil and IsOutsideOfStencil then
  begin
    Result := nil;
  end;
end;

// getDecodeArray
function TPDImage.Decode: TArray<Single>;
begin
  var Value: TCosBase;
  if Lookup(TCosNames.Decode, Value) then
  begin
    Result := DecodeEntries(Value);
    if Length(Result) > 0 then
    begin
      Exit;
    end;
    LogError('decode array is not compatible with color space, using default', []);
  end;

  Result := EffectiveColorSpace.GetDefaultDecode(BitsPerComponent);
end;

class procedure TPDImage.RaiseForImageFilter(const FilterName: string);
begin
  const CanonicalName = TFilterFactory.CanonicalName(FilterName);
  if CanonicalName = TCosNames.JPXDecode then
  begin
    raise EPdfUnsupportedFeatureException.Create(JpxNotInstalled);
  end;
  if CanonicalName = TCosNames.JBIG2Decode then
  begin
    raise EPdfUnsupportedFeatureException.Create(Jbig2NotInstalled);
  end;
  raise EPdfUnsupportedFeatureException.CreateFmt(UnsupportedImageFilter, [FilterName]);
end;

function TPDImage.FilterCount: Integer;
begin
  Result := 0;
  var Value: TCosBase;
  if not Lookup(TCosNames.Filter, Value) then
  begin
    Exit;
  end;

  if Value is TCosArray then
  begin
    Result := TCosArray(Value).Count;
  end
  else if Value is TCosName then
  begin
    Result := 1;
  end;
end;

// getDecodeParams: the decode parameters of the filter at FilterIndex, nil when there are none
function TPDImage.FilterParametersOf(const FilterIndex: Integer): TCosDictionary;
begin
  Result := nil;
  var Entry: TCosBase;
  const HasParameters = (Lookup(TCosNames.DecodeParms, Entry) or Parameters.TryGetDictionaryObject(TCosNames.DP, Entry));
  if not HasParameters then
  begin
    Exit;
  end;

  if Entry is TCosDictionary then
  begin
    Result := TCosDictionary(Entry);
  end
  else if (Entry is TCosArray) and (FilterIndex < TCosArray(Entry).Count) then
  begin
    const Item = TCosArray(Entry).GetObject(FilterIndex);
    if Item is TCosDictionary then
    begin
      Result := TCosDictionary(Item);
    end;
  end;
end;

// The /ColorTransform of the decode parameters of the filter at FilterIndex, -1 when there is none
function TPDImage.DctColorTransform(const FilterIndex: Integer): Integer;
begin
  Result := -1;
  const FilterParameters = FilterParametersOf(FilterIndex);
  var Transform: TCosBase;
  const HasTransform = (Assigned(FilterParameters) and FilterParameters.TryGetDictionaryObject(TCosNames.ColorTransform, Transform));
  if HasTransform and (Transform is TCosNumber) then
  begin
    Result := TCosNumber(Transform).IntValue;
  end;
end;

// DCTFilter: the samples of the JPEG as gray, RGB or CMYK. A line feed before the data is skipped, like PDFBox does.
function TPDImage.DecodeJpeg(const Data: TBytes; const FilterIndex: Integer): TBytes;
begin
  var JpegData := Data;
  const StartsWithLineFeed = ((Length(Data) > 0) and (Data[0] = LineFeed));
  if StartsWithLineFeed then
  begin
    JpegData := Copy(Data, 1, Length(Data) - 1);
  end;

  const MaxPixels = Min(MaxBitmapPixels, Resources.Context.Options.MaxDecodedStreamSize div MaxJpegComponents);
  const Options = TJpegDecodeOptions.ForPdf(DctColorTransform(FilterIndex), MaxPixels);
  const Decoded = TJpegImage.Decode(JpegData, Options, Log);
  try
    Result := Decoded.Samples;
  finally
    Decoded.Free;
  end;
end;

// CCITTFaxFilter: the rows of the image as 1 bit per pixel
function TPDImage.DecodeCcitt(const Data: TBytes; const FilterIndex: Integer): TBytes;
begin
  const Options = TCCITTFaxParameters.FromDictionary(FilterParametersOf(FilterIndex), Height);
  const MaxPixels = Min(MaxBitmapPixels, Resources.Context.Options.MaxDecodedStreamSize * BitsPerByte);
  Result := TCCITTFaxDecoder.Decode(Data, Options, MaxPixels, Log);
end;

// The sample bytes: the filters up to an image filter, then that filter
function TPDImage.ReadSamples: TBytes;
begin
  var Remaining: TArray<string>;
  Result := DecodeSamples(Remaining);
  if Length(Remaining) = 0 then
  begin
    Exit;
  end;

  const CanonicalName = TFilterFactory.CanonicalName(Remaining[0]);
  const IsJpeg = (CanonicalName = TCosNames.DCTDecode);
  const IsCcitt = (CanonicalName = TCosNames.CCITTFaxDecode);
  if not (IsJpeg or IsCcitt) then
  begin
    RaiseForImageFilter(Remaining[0]);
  end;

  if Length(Remaining) > 1 then
  begin
    LogWarning('The filters after %s are ignored', [CanonicalName]);
  end;

  const FilterIndex = FilterCount - Length(Remaining);
  if IsJpeg then
  begin
    Result := DecodeJpeg(Result, FilterIndex);
  end
  else
  begin
    Result := DecodeCcitt(Result, FilterIndex);
  end;
end;

function TPDImage.BuildSource(const ForOpaque: Boolean): TSampledImageSource;
begin
  Result := Default(TSampledImageSource);
  Result.Width := Width;
  Result.Height := Height;
  Result.BitsPerComponent := BitsPerComponent;
  Result.ColorSpace := EffectiveColorSpace;
  Result.Decode := Decode;
  Result.Log := Log;

  var Key: TCosBase;
  if (not ForOpaque) and Lookup(TCosNames.Mask, Key) and (Key is TCosArray) then
  begin
    Result.HasColorKey := True;
    Result.ColorKey := TCosArray(Key).ToFloatArray;
  end;
  Result.Data := ReadSamples;
end;

function TPDImage.SubsamplingFor(const MaxImagePixels: Int64): Integer;
begin
  Result := TSampledImageReader.Subsampling(Width, Height, EffectiveColorSpace.NumberOfComponents, MaxImagePixels);
end;

function TPDImage.ReadStraightRgb(const Subsampling: Integer; const UseColorKey: Boolean): TPdfBitmap;
begin
  Result := TSampledImageReader.ReadRgb(BuildSource(not UseColorKey), Subsampling);
end;

function TPDImage.TryGetImage(const MaxImagePixels: Int64; out Bitmap: TPdfBitmap): Boolean;
begin
  Bitmap := nil;
  try
    const Subsampling = SubsamplingFor(MaxImagePixels);
    if Subsampling > 1 then
    begin
      LogWarning('Image of %d x %d pixels is subsampled by %d to fit the limit of %d pixels', [Width, Height, Subsampling, MaxImagePixels]);
    end;
    Bitmap := ReadStraightRgb(Subsampling, True);
    TSampledImageReader.Premultiply(Bitmap);
    Result := True;
  except
    on Error: Exception do
    begin
      if not IsRecoverable(Error) then
      begin
        raise;
      end;
      Bitmap := nil;
      LogError('Image skipped: %s', [Error.Message]);
      Result := False;
    end;
  end;
end;

function TPDImage.TryGetStencilMask(const MaxImagePixels: Int64; out Mask: TPdfBitmap): Boolean;
begin
  Mask := nil;
  Result := False;
  if not IsStencil then
  begin
    LogError('Image is not a stencil', []);
    Exit;
  end;

  try
    const Subsampling = TSampledImageReader.Subsampling(Width, Height, 1, MaxImagePixels);
    if Subsampling > 1 then
    begin
      LogWarning('Stencil mask of %d x %d pixels is subsampled by %d to fit the limit of %d pixels', [Width, Height, Subsampling, MaxImagePixels]);
    end;

    var Source := Default(TSampledImageSource);
    Source.Width := Width;
    Source.Height := Height;
    Source.BitsPerComponent := 1;
    Source.ColorSpace := EffectiveColorSpace;
    Source.Decode := Decode;
    Source.Log := Log;
    Source.Data := ReadSamples;
    Mask := TSampledImageReader.ReadStencil(Source, Subsampling);
    Result := True;
  except
    on Error: Exception do
    begin
      if not IsRecoverable(Error) then
      begin
        raise;
      end;
      Mask := nil;
      LogError('Stencil mask skipped: %s', [Error.Message]);
    end;
  end;
end;

{ TPDImageXObject }

constructor TPDImageXObject.Create(const Stream: TCosStream; const Resources: TPDResources);
begin
  if not Assigned(Stream) then
  begin
    raise EArgumentNilException.Create('Stream');
  end;
  if not Assigned(Resources) then
  begin
    raise EArgumentNilException.Create('Resources');
  end;

  inherited Create(Stream, Resources);
  FStream := Stream;
end;

destructor TPDImageXObject.Destroy;
begin
  FOwnedResources.Free;
  inherited;
end;

class function TPDImageXObject.CreateMask(const Stream: TCosStream; const Parent: TPDResources): TPDImageXObject;
begin
  const Empty = TPDResources.Create(nil, Parent.Context);
  try
    Result := TPDImageXObject.Create(Stream, Empty);
  except
    Empty.Free;
    raise;
  end;
  Result.FOwnedResources := Empty;
end;

function TPDImageXObject.AbbreviationOf(const Name: string): string;
begin
  Result := '';
  if Name = TCosNames.BitsPerComponent then
  begin
    Result := TCosNames.BPC;
  end
  else if Name = TCosNames.ColorSpace then
  begin
    Result := TCosNames.CS;
  end;
end;

function TPDImageXObject.DecodeSamples(out RemainingFilters: TArray<string>): TBytes;
begin
  const Decoded = FStream.DecodeUntilImageFilter;
  RemainingFilters := Decoded.RemainingFilters;
  Result := Decoded.Data;
end;

function TPDImageXObject.HasMaskOrSMask: Boolean;
begin
  Result := (Parameters.ContainsKey(TCosNames.Mask) or Parameters.ContainsKey(TCosNames.SMask));
end;

// extractMatte
function TPDImageXObject.TryExtractMatte(const SoftMask: TPDImageXObject; out Matte: TArray<Single>): Boolean;
begin
  Matte := nil;
  Result := False;
  var Items: TCosArray;
  if not SoftMask.FStream.TryGetCosArray(TCosNames.Matte, Items) then
  begin
    Exit;
  end;

  const Values = Items.ToFloatArray;
  if Length(Values) < EffectiveColorSpace.NumberOfComponents then
  begin
    LogError('Image /Matte entry not long enough for colorspace, skipped', []);
    Exit;
  end;

  const Rgb = EffectiveColorSpace.ToRgb(Values);
  Matte := [Rgb.R, Rgb.G, Rgb.B];
  Result := True;
end;

// A copy of the channels of Source in Width x Height pixels; nearest neighbour like the default of drawImage, or bilinear (PDFBox
// scales with a bicubic transform when the image says /Interpolate)
function ScaleChannels(const Source: TBytes; const SourceWidth, SourceHeight, Channels, Width, Height: Integer;
                       const Interpolate: Boolean): TBytes;
begin
  TPdfBitmap.CheckSize(Width, Height);
  SetLength(Result, Integer(Int64(Width) * Height * Channels));
  for var Y := 0 to Height - 1 do
  begin
    for var X := 0 to Width - 1 do
    begin
      for var Channel := 0 to Channels - 1 do
      begin
        const Target = (Int64(Y) * Width + X) * Channels + Channel;
        if not Interpolate then
        begin
          const SourceX = Min(SourceWidth - 1, ((2 * Int64(X) + 1) * SourceWidth) div (2 * Int64(Width)));
          const SourceY = Min(SourceHeight - 1, ((2 * Int64(Y) + 1) * SourceHeight) div (2 * Int64(Height)));
          Result[Integer(Target)] := Source[Integer((SourceY * SourceWidth + SourceX) * Channels + Channel)];
          Continue;
        end;

        const Fx = Max(0.0, (X + 0.5) * SourceWidth / Width - 0.5);
        const Fy = Max(0.0, (Y + 0.5) * SourceHeight / Height - 0.5);
        const X0 = Min(Trunc(Fx), SourceWidth - 1);
        const Y0 = Min(Trunc(Fy), SourceHeight - 1);
        const X1 = Min(X0 + 1, SourceWidth - 1);
        const Y1 = Min(Y0 + 1, SourceHeight - 1);
        const Wx = Fx - X0;
        const Wy = Fy - Y0;
        const Top = Source[Integer((Int64(Y0) * SourceWidth + X0) * Channels + Channel)] * (1 - Wx) + Source[Integer((Int64(Y0) * SourceWidth + X1) * Channels + Channel)] * Wx;
        const Bottom = Source[Integer((Int64(Y1) * SourceWidth + X0) * Channels + Channel)] * (1 - Wx) + Source[Integer((Int64(Y1) * SourceWidth + X1) * Channels + Channel)] * Wx;
        Result[Integer(Target)] := Byte(Min(ByteMax, Round(Top * (1 - Wy) + Bottom * Wy)));
      end;
    end;
  end;
end;

function BitmapBytes(const Bitmap: TPdfBitmap): TBytes;
begin
  SetLength(Result, Integer(Int64(Bitmap.Width) * Bitmap.Height * 4));
  for var Y := 0 to Bitmap.Height - 1 do
  begin
    Move(Bitmap.ScanLine(Y)^, Result[Integer(Int64(Y) * Bitmap.Width * 4)], Bitmap.Width * 4);
  end;
end;

function ClampColor(const Value: Int64): Integer;
begin
  Result := Integer(Min(Max(Value, 0), ByteMax));
end;

// An arithmetic shift to the right, like >> of Java
function ShiftRight(const Value: Int64; const Count: Integer): Int64;
begin
  if Value >= 0 then
  begin
    Result := Value shr Count;
  end
  else
  begin
    Result := not ((not Value) shr Count);
  end;
end;

// applyMask: Image (straight alpha) gets the alpha of Mask. A stencil mask (not soft) is inverted. Both are scaled to the larger of the
// two sizes. Image is replaced by a new bitmap when its size changes.
procedure TPDImageXObject.ApplyMask(var Image: TPdfBitmap; const Mask: TPdfBitmap; const InterpolateMask, IsSoft: Boolean;
                                    const Matte: TArray<Single>);
begin
  const Width = Max(Image.Width, Mask.Width);
  const Height = Max(Image.Height, Mask.Height);

  // The mask as 8-bit gray: the gray of Java2D when it is converted from RGB
  var Alpha: TBytes;
  SetLength(Alpha, Integer(Int64(Mask.Width) * Mask.Height));
  for var Y := 0 to Mask.Height - 1 do
  begin
    const Row = Mask.ScanLine(Y);
    for var X := 0 to Mask.Width - 1 do
    begin
      const Red = Row[X * 4];
      const Green = Row[X * 4 + 1];
      const Blue = Row[X * 4 + 2];
      Alpha[Integer(Int64(Y) * Mask.Width + X)] := Byte((GrayRed * Red + GrayGreen * Green + GrayBlue * Blue + (1 shl (ExtraBitsOfGray - 1))) shr ExtraBitsOfGray);
    end;
  end;
  if (Mask.Width < Width) or (Mask.Height < Height) then
  begin
    Alpha := ScaleChannels(Alpha, Mask.Width, Mask.Height, 1, Width, Height, InterpolateMask);
  end;

  var Pixels := BitmapBytes(Image);
  if (Image.Width < Width) or (Image.Height < Height) then
  begin
    Pixels := ScaleChannels(Pixels, Image.Width, Image.Height, 4, Width, Height, Interpolate);
  end;

  const Hide = (not IsSoft);
  var MatteRed := 0;
  var MatteGreen := 0;
  var MatteBlue := 0;
  // The products wrap like the int arithmetic of Java
  if Length(Matte) = RgbComponents then
  begin
    MatteRed := Integer(Int64(TSampledImageReader.JavaRound(MatteFactor * Matte[0])) * ByteMax);
    MatteGreen := Integer(Int64(TSampledImageReader.JavaRound(MatteFactor * Matte[1])) * ByteMax);
    MatteBlue := Integer(Int64(TSampledImageReader.JavaRound(MatteFactor * Matte[2])) * ByteMax);
  end;

  for var Index := 0 to Integer(Int64(Width) * Height) - 1 do
  begin
    var Value := Alpha[Index];
    if Hide then
    begin
      Value := Byte(not Value);
    end;
    const Offset = Index * 4;
    if (Length(Matte) = RgbComponents) and (Value <> 0) then
    begin
      Pixels[Offset] := Byte(ClampColor(ShiftRight((Int64(Pixels[Offset]) * MatteFactor - MatteRed) div Value + MatteRed div ByteMax + MatteRoundingHalf, MatteFraction)));
      Pixels[Offset + 1] := Byte(ClampColor(ShiftRight((Int64(Pixels[Offset + 1]) * MatteFactor - MatteGreen) div Value + MatteGreen div ByteMax + MatteRoundingHalf, MatteFraction)));
      Pixels[Offset + 2] := Byte(ClampColor(ShiftRight((Int64(Pixels[Offset + 2]) * MatteFactor - MatteBlue) div Value + MatteBlue div ByteMax + MatteRoundingHalf, MatteFraction)));
    end;
    Pixels[Offset + 3] := Value;
  end;

  const Combined = TPdfBitmap.Create(Width, Height);
  try
    for var Y := 0 to Height - 1 do
    begin
      Move(Pixels[Integer(Int64(Y) * Width * 4)], Combined.ScanLine(Y)^, Width * 4);
    end;
  except
    Combined.Free;
    raise;
  end;
  Image.Free;
  Image := Combined;
end;

function TPDImageXObject.BuildImage(const MaxImagePixels: Int64): TPdfBitmap;
begin
  var SoftMask: TPDImageXObject := nil;
  var Mask: TPDImageXObject := nil;
  try
    var MaskStream: TCosStream;
    if Parameters.TryGetCosStream(TCosNames.SMask, MaskStream) then
    begin
      SoftMask := CreateMask(MaskStream, Resources);
    end
    else if Parameters.TryGetCosStream(TCosNames.Mask, MaskStream) then
    begin
      Mask := CreateMask(MaskStream, Resources);
      // An explicit mask is applied only when /ImageMask is true
      if not Mask.IsStencil then
      begin
        FreeAndNil(Mask);
      end;
    end;

    var Subsampling := SubsamplingFor(MaxImagePixels);
    var MaskImage := Mask;
    if Assigned(SoftMask) then
    begin
      MaskImage := SoftMask;
    end;
    if Assigned(MaskImage) then
    begin
      Subsampling := Max(Subsampling, MaskImage.SubsamplingFor(MaxImagePixels));
    end;
    if Subsampling > 1 then
    begin
      LogWarning('Image of %d x %d pixels is subsampled by %d to fit the limit of %d pixels', [Width, Height, Subsampling, MaxImagePixels]);
    end;

    Result := ReadStraightRgb(Subsampling, True);
    try
      if Assigned(MaskImage) then
      begin
        const MaskBitmap = MaskImage.ReadStraightRgb(Subsampling, False);
        try
          var Matte: TArray<Single> := nil;
          if Assigned(SoftMask) then
          begin
            TryExtractMatte(SoftMask, Matte);
          end;
          ApplyMask(Result, MaskBitmap, MaskImage.Interpolate, Assigned(SoftMask), Matte);
        finally
          MaskBitmap.Free;
        end;
      end;
      TSampledImageReader.Premultiply(Result);
    except
      Result.Free;
      raise;
    end;
  finally
    Mask.Free;
    SoftMask.Free;
  end;
end;

function TPDImageXObject.TryGetImage(const MaxImagePixels: Int64; out Bitmap: TPdfBitmap): Boolean;
begin
  Bitmap := nil;
  try
    Bitmap := BuildImage(MaxImagePixels);
    Result := True;
  except
    on Error: Exception do
    begin
      if not IsRecoverable(Error) then
      begin
        raise;
      end;
      Bitmap := nil;
      LogError('Image skipped: %s', [Error.Message]);
      Result := False;
    end;
  end;
end;

{ TPDInlineImage }

constructor TPDInlineImage.Create(const Parameters: TCosDictionary; const Data: TBytes; const Resources: TPDResources);
begin
  if not Assigned(Parameters) then
  begin
    raise EArgumentNilException.Create('Parameters');
  end;
  if not Assigned(Resources) then
  begin
    raise EArgumentNilException.Create('Resources');
  end;

  inherited Create(Parameters, Resources);
  FData := Data;
end;

function TPDInlineImage.AbbreviationOf(const Name: string): string;
begin
  Result := '';
  for var Index := 0 to High(InlineAbbreviations) do
  begin
    if InlineAbbreviations[Index, 0] = Name then
    begin
      Exit(InlineAbbreviations[Index, 1]);
    end;
  end;
end;

// getFilters
function TPDInlineImage.FilterNames: TArray<string>;
begin
  Result := nil;
  var Value: TCosBase;
  if not Lookup(TCosNames.Filter, Value) then
  begin
    Exit;
  end;

  if Value is TCosName then
  begin
    Result := [TCosName(Value).Name];
    Exit;
  end;

  if Value is TCosArray then
  begin
    const Items = TCosArray(Value);
    for var Index := 0 to Items.Count - 1 do
    begin
      const Item = Items.GetObject(Index);
      if Item is TCosName then
      begin
        Result := Result + [TCosName(Item).Name];
      end;
    end;
  end;
end;

function TPDInlineImage.DecodeSamples(out RemainingFilters: TArray<string>): TBytes;
begin
  RemainingFilters := nil;
  Result := FData;
  const Names = FilterNames;
  if Length(Names) > 0 then
  begin
    Result := TFilterChain.Decode(FData, Names, Parameters, Resources.Context.Options.MaxDecodedStreamSize, Log, True, RemainingFilters);
  end;
end;

// toLongName, createColorSpace
function TPDInlineImage.CreateColorSpace(const Value: TCosBase): TPDColorSpace;
begin
  if Value is TCosName then
  begin
    var LongName := TCosName(Value).Name;
    if LongName = TCosNames.RGB then
    begin
      LongName := 'DeviceRGB';
    end
    else if LongName = TCosNames.CMYK then
    begin
      LongName := 'DeviceCMYK';
    end
    else if LongName = TCosNames.G then
    begin
      LongName := TCosNames.DeviceGray;
    end;

    const LongValue = TCosName.Create(LongName);
    try
      Exit(TPDColorSpaceFactory.Create(LongValue, Resources));
    finally
      LongValue.Free;
    end;
  end;

  if (Value is TCosArray) and (TCosArray(Value).Count > 1) then
  begin
    const First = TCosArray(Value).GetObject(0);
    const IsIndexed = (First is TCosName) and ((TCosName(First).Name = TCosNames.I) or (TCosName(First).Name = TCosNames.Indexed));
    if not IsIndexed then
    begin
      raise EPdfParseException.Create(InlineColorSpaceIllegal);
    end;
    // The array as it is when it spells Indexed in full; the abbreviations of its base follow with the colour space Indexed
    if TCosName(First).Name = TCosNames.I then
    begin
      raise EPdfUnsupportedFeatureException.Create(InlineIndexedNotSupported);
    end;
    Exit(TPDColorSpaceFactory.Create(Value, Resources));
  end;

  raise EPdfParseException.Create(InlineColorSpaceIllegal);
end;

end.
