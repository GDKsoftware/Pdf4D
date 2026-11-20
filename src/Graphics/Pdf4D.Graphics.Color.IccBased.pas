// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/color/PDICCBased.java (3.0.8). The colours go through
// Pdf4D.Graphics.Icc.Transform where PDFBox uses the Java colour management. A profile that cannot be used makes the space fall
// back to its alternate (PDICCBased.fallbackToAlternateColorSpace). PDFBox patches the class of a profile to "display"
// (ensureDisplayProfile) because the Java colour management only converts the colours of display profiles; the transform here reads
// no profile class, so that patch has nothing to do (docs/assumptions.md).
unit Pdf4D.Graphics.Color.IccBased;

{$EXCESSPRECISION OFF}
{$POINTERMATH ON}

interface

uses
  System.SysUtils,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Graphics.Color,
  Pdf4D.Graphics.Icc.Profile,
  Pdf4D.Graphics.Icc.Transform,
  Pdf4D.Model.DocumentContext,
  Pdf4D.Render.Bitmap;

type
  // Makes the colour space of an /Alternate value; raises EPdfParseException or EPdfUnsupportedFeatureException when it cannot
  TPDAlternateResolver = reference to function(const Value: TCosBase): TPDColorSpace;

  // The colour space [/ICCBased stream]. The alternate is not owned: the document context or the process owns it.
  TPDICCBased = class(TPDColorSpace)
  private
    FContext: TPDDocumentContext;
    FStream: TCosStream;
    FResolveAlternate: TPDAlternateResolver;
    FNumberOfComponents: Integer;
    FRange: TArray<Single>;
    FProfile: TIccProfile;
    FTransform: TIccTransform;
    FIsSRGB: Boolean;
    FAlternate: TPDColorSpace;
    FIsAlternateKnown: Boolean;

    procedure ReadRange;
    procedure LoadProfile;
    function ReadProfileBytes: TBytes;
    procedure UseProfile(const Profile: TIccProfile);
    procedure FallBackToAlternate(const Reason: string);
    function ResolveAlternateOfStream: TPDColorSpace;
    function ResolveDeviceSpaceOfN: TPDColorSpace;
    function GetAlternate: TPDColorSpace;
    procedure LogWarning(const Fmt: string; const Args: array of const);

  public
    // Stream is the second element of the array. Raises EPdfParseException when the profile cannot be used and the alternate
    // cannot be found either (a profile that is broken is no reason to raise). The stream has to outlive the colour space.
    constructor Create(const Stream: TCosStream; const Context: TPDDocumentContext; const ResolveAlternate: TPDAlternateResolver);
    destructor Destroy; override;

    function Name: string; override;
    function NumberOfComponents: Integer; override;
    function GetDefaultDecode(const BitsPerComponent: Integer): TArray<Single>; override;
    function InitialColor: TPDColor; override;
    function ToRgb(const Components: TArray<Single>): TPdfRgb; override;
    function ToRgbImage(const Raster: TPdfRaster): TPdfBitmap; override;

    // True when the profile could not be used and the alternate does the work
    function UsesAlternate: Boolean;
    // PDICCBased.is_sRGB: the device model in the header of the profile is sRGB, so the values are sRGB already
    function IsSRGB: Boolean;
    // The alternate colour space, from /Alternate or else the device space of /N; nil when there is none
    property Alternate: TPDColorSpace read GetAlternate;
  end;

implementation

uses
  System.Math,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Graphics.Color.Device;

resourcestring
  IccUnknownComponents = 'The ICC based colour space has %d components, which no device colour space has';
  IccFallbackWarning = 'Cannot read the embedded ICC profile (%s), using the alternate colour space %s';
  IccComponentsDiffer = 'the profile has %d components and /N says %d';

const
  GrayComponents = 1;
  RgbComponents = 3;
  CmykComponents = 4;

{ TPDICCBased }

constructor TPDICCBased.Create(const Stream: TCosStream; const Context: TPDDocumentContext; const ResolveAlternate: TPDAlternateResolver);
begin
  inherited Create;
  FStream := Stream;
  FContext := Context;
  FResolveAlternate := ResolveAlternate;
  FNumberOfComponents := Stream.GetInt(TCosNames.N, 0);
  LoadProfile;
  ReadRange;
end;

destructor TPDICCBased.Destroy;
begin
  FTransform.Free;
  FProfile.Free;
  inherited;
end;

procedure TPDICCBased.LogWarning(const Fmt: string; const Args: array of const);
begin
  if Assigned(FContext) and Assigned(FContext.Log) then
  begin
    FContext.Log.Warning(Fmt, Args);
  end;
end;

procedure TPDICCBased.ReadRange;
begin
  var Values: TCosArray;
  const IsRangeGiven = FStream.TryGetCosArray(TCosNames.Range, Values);
  if IsRangeGiven then
  begin
    FRange := Values.ToFloatArray;
  end;

  const IsRangeComplete = (Length(FRange) = FNumberOfComponents * 2);
  if IsRangeComplete then
  begin
    Exit;
  end;

  SetLength(FRange, FNumberOfComponents * 2);
  for var Index := 0 to FNumberOfComponents - 1 do
  begin
    FRange[Index * 2] := 0.0;
    FRange[Index * 2 + 1] := 1.0;
  end;
end;

function TPDICCBased.ReadProfileBytes: TBytes;
begin
  const Decoded = FStream.CreateDecodedStream;
  try
    SetLength(Result, Decoded.Size);
    if Length(Result) > 0 then
    begin
      Decoded.ReadBuffer(Result[0], Length(Result));
    end;
  finally
    Decoded.Free;
  end;
end;

procedure TPDICCBased.LoadProfile;
begin
  var Profile: TIccProfile := nil;
  try
    Profile := TIccProfile.Parse(ReadProfileBytes);
    const IsNGiven = (FNumberOfComponents > 0);
    if IsNGiven and (Profile.NumberOfComponents <> FNumberOfComponents) then
    begin
      raise EPdfParseException.CreateFmt(IccComponentsDiffer, [Profile.NumberOfComponents, FNumberOfComponents]);
    end;
    UseProfile(Profile);
  except
    on Error: Exception do
    begin
      Profile.Free;
      const IsRecoverable = ((Error is EPdfException) or TPdfFailure.IsInputFailure(Error));
      if not IsRecoverable then
      begin
        raise;
      end;
      FallBackToAlternate(Error.Message);
    end;
  end;
end;

procedure TPDICCBased.UseProfile(const Profile: TIccProfile);
begin
  FProfile := Profile;
  FNumberOfComponents := Profile.NumberOfComponents;
  FIsSRGB := (Profile.IsSRGB and (FNumberOfComponents = RgbComponents));
  if not FIsSRGB then
  begin
    FTransform := TIccTransform.Create(Profile);
  end;
end;

function TPDICCBased.ResolveDeviceSpaceOfN: TPDColorSpace;
begin
  case FNumberOfComponents of
    GrayComponents : Result := TPDDeviceGray.Instance;
    RgbComponents  : Result := TPDDeviceRGB.Instance;
    CmykComponents : Result := TPDDeviceCMYK.Instance;
  else
    raise EPdfParseException.CreateFmt(IccUnknownComponents, [FNumberOfComponents]);
  end;
end;

// The alternate of PDICCBased.getAlternateColorSpace; one that does not fit /N or that cannot be made counts as absent
function TPDICCBased.ResolveAlternateOfStream: TPDColorSpace;
begin
  Result := nil;
  var Value: TCosBase;
  const IsAlternateGiven = FStream.TryGetDictionaryObject(TCosNames.Alternate, Value);
  if not (IsAlternateGiven and Assigned(FResolveAlternate)) then
  begin
    Exit;
  end;

  try
    Result := FResolveAlternate(Value);
  except
    on Error: Exception do
    begin
      const IsRecoverable = ((Error is EPdfException) or TPdfFailure.IsInputFailure(Error));
      if not IsRecoverable then
      begin
        raise;
      end;
      Result := nil;
    end;
  end;

  const IsMatching = (Assigned(Result) and (Result.NumberOfComponents = FNumberOfComponents));
  if not IsMatching then
  begin
    Result := nil;
  end;
end;

procedure TPDICCBased.FallBackToAlternate(const Reason: string);
begin
  FAlternate := ResolveAlternateOfStream;
  if not Assigned(FAlternate) then
  begin
    FAlternate := ResolveDeviceSpaceOfN;
  end;
  FIsAlternateKnown := True;
  LogWarning(IccFallbackWarning, [Reason, FAlternate.Name]);
end;

function TPDICCBased.GetAlternate: TPDColorSpace;
begin
  if not FIsAlternateKnown then
  begin
    FAlternate := ResolveAlternateOfStream;
    if not Assigned(FAlternate) then
    begin
      try
        FAlternate := ResolveDeviceSpaceOfN;
      except
        on Error: EPdfParseException do
        begin
          FAlternate := nil;
        end;
      end;
    end;
    FIsAlternateKnown := True;
  end;
  Result := FAlternate;
end;

function TPDICCBased.Name: string;
begin
  Result := TCosNames.ICCBased;
end;

function TPDICCBased.NumberOfComponents: Integer;
begin
  Result := FNumberOfComponents;
end;

function TPDICCBased.UsesAlternate: Boolean;
begin
  Result := not Assigned(FProfile);
end;

function TPDICCBased.IsSRGB: Boolean;
begin
  Result := FIsSRGB;
end;

function TPDICCBased.GetDefaultDecode(const BitsPerComponent: Integer): TArray<Single>;
begin
  const Space = GetAlternate;
  if Assigned(Space) then
  begin
    Exit(Space.GetDefaultDecode(BitsPerComponent));
  end;

  Result := inherited GetDefaultDecode(BitsPerComponent);
end;

function TPDICCBased.InitialColor: TPDColor;
begin
  var Components: TArray<Single>;
  SetLength(Components, FNumberOfComponents);
  for var Index := 0 to FNumberOfComponents - 1 do
  begin
    Components[Index] := Max(0.0, FRange[Index * 2]);
  end;
  Result := TPDColor.Create(Self, Components);
end;

function TPDICCBased.ToRgb(const Components: TArray<Single>): TPdfRgb;
begin
  if UsesAlternate then
  begin
    Exit(FAlternate.ToRgb(Components));
  end;

  const Values = NormalizeComponents(Components);
  if FIsSRGB then
  begin
    Exit(TPdfRgb.Create(ClampColor(Values[0]), ClampColor(Values[1]), ClampColor(Values[2])));
  end;

  var Rgb: array[0..2] of Single;
  FTransform.ToRgb(@Values[0], @Rgb[0]);
  Result := TPdfRgb.Create(Rgb[0], Rgb[1], Rgb[2]);
end;

function TPDICCBased.ToRgbImage(const Raster: TPdfRaster): TPdfBitmap;
begin
  if UsesAlternate then
  begin
    Exit(FAlternate.ToRgbImage(Raster));
  end;

  CheckRaster(Raster);
  if FIsSRGB then
  begin
    Exit(TPDDeviceRGB.Instance.ToRgbImage(Raster));
  end;

  // The cache of a transform belongs to one conversion, so the colour space (which a thread may share) keeps none
  const Transform = TIccTransform.Create(FProfile);
  try
    Result := ConvertWithTransform(Raster, Transform);
  finally
    Transform.Free;
  end;
end;

end.
