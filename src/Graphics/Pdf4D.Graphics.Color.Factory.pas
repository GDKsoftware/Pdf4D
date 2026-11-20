// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: PDColorSpace.create (pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/color/PDColorSpace.java, 3.0.8) and the
// colour space part of PDResources.getColorSpace. The colour spaces besides the device spaces and ICCBased give an
// EPdfUnsupportedFeatureException until they are ported.
unit Pdf4D.Graphics.Color.Factory;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Graphics.Color,
  Pdf4D.Model.DocumentContext,
  Pdf4D.Model.Resources;

const
  // Colour spaces inside each other (the alternate of an ICCBased space, for one)
  MaxColorSpaceDepth = 8;

type
  TPDColorSpaceFactory = class
  private
    class function Resolve(const Value: TCosBase): TCosBase; static;
    class function CreateAt(const Value: TCosBase; const Context: TPDDocumentContext; const Resources: TPDResources; const WasDefault: Boolean;
                            const Depth: Integer): TPDColorSpace; static;
    class function CreateFromName(const Name: string; const Context: TPDDocumentContext; const Resources: TPDResources; const WasDefault: Boolean;
                                  const Depth: Integer): TPDColorSpace; static;
    class function CreateFromArray(const Items: TCosArray; const Context: TPDDocumentContext; const Resources: TPDResources;
                                   const Depth: Integer): TPDColorSpace; static;
    class function CreateFromKind(const Kind: string; const Items: TCosArray; const Context: TPDDocumentContext; const Resources: TPDResources;
                                  const Depth: Integer): TPDColorSpace; static;
    class function TryGetDefaultName(const Name: string; out DefaultName: string): Boolean; static;
    class function TryCreateDevice(const Name: string; out Space: TPDColorSpace): Boolean; static;
    class function CreateIccBased(const Items: TCosArray; const Context: TPDDocumentContext; const Depth: Integer): TPDColorSpace; static;
    class function CreateNamedResource(const Name: string; const Context: TPDDocumentContext; const Resources: TPDResources; const WasDefault: Boolean;
                                       const Depth: Integer): TPDColorSpace; static;
    class function IsDeviceKind(const Kind: string; out DeviceName: string): Boolean; static;

  public
    // Value is a name or an array, as the colour space operators and the /ColorSpace entries of images have them, or an
    // indirect reference to one. The device names give the shared spaces, a name of /ColorSpace in the resources gives that
    // space, and /DefaultGray, /DefaultRGB and /DefaultCMYK replace the device spaces unless WasDefault says that the value is the
    // default itself. A space that is not shared is made once per document (the context owns it): the same object (the same
    // array, the same name in the resources) gives the same colour space. Raises EPdfParseException for a value that is no
    // colour space and EPdfUnsupportedFeatureException for one that is not ported yet. Resources may not be nil.
    class function Create(const Value: TCosBase; const Resources: TPDResources; const WasDefault: Boolean = False): TPDColorSpace; static;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.PdfObject,
  Pdf4D.Graphics.Color.Device,
  Pdf4D.Graphics.Color.IccBased;

resourcestring
  ColorSpaceNil = 'The colour space is missing';
  ColorSpaceMissing = 'Missing colour space: %s';
  ColorSpaceEmptyArray = 'The colour space array is empty';
  ColorSpaceBadKind = 'Invalid colour space kind: %s';
  ColorSpaceBadValue = 'A colour space is a name or an array, not %s';
  ColorSpaceTooDeep = 'Colour spaces are nested deeper than %d levels';
  ColorSpaceNotPorted = 'The colour space %s is not supported yet';
  IccNeedsStream = 'An ICCBased colour space array must have a stream as second element';
  IccRefersToItself = 'An ICCBased colour space is being made while its alternate asks for it again';

const
  IccElementCount = 2;
  IccStreamIndex = 1;

type
  // The ICCBased arrays that this thread is making, innermost last. Colour spaces nest at most MaxColorSpaceDepth + 1 deep.
  TIccArraysInProgress = record
    Items: array[0..MaxColorSpaceDepth + 1] of TCosArray;
    Count: Integer;

    function Contains(const IccArray: TCosArray): Boolean;
    procedure Push(const IccArray: TCosArray);
    procedure Pop;
  end;

threadvar
  IccInProgress: TIccArraysInProgress;

function TIccArraysInProgress.Contains(const IccArray: TCosArray): Boolean;
begin
  Result := False;
  for var Index := 0 to Count - 1 do
  begin
    Result := (Result or (Items[Index] = IccArray));
  end;
end;

procedure TIccArraysInProgress.Push(const IccArray: TCosArray);
begin
  Items[Count] := IccArray;
  Inc(Count);
end;

procedure TIccArraysInProgress.Pop;
begin
  Dec(Count);
end;

{ TPDColorSpaceFactory }

class function TPDColorSpaceFactory.Create(const Value: TCosBase; const Resources: TPDResources; const WasDefault: Boolean): TPDColorSpace;
begin
  if not Assigned(Resources) then
  begin
    raise EArgumentNilException.Create('Resources');
  end;

  Result := CreateAt(Value, Resources.Context, Resources, WasDefault, 0);
end;

class function TPDColorSpaceFactory.Resolve(const Value: TCosBase): TCosBase;
begin
  Result := Value;
  if Result is TCosObject then
  begin
    Result := TCosObject(Result).GetObject;
  end;
end;

class function TPDColorSpaceFactory.CreateAt(const Value: TCosBase; const Context: TPDDocumentContext; const Resources: TPDResources;
                                             const WasDefault: Boolean; const Depth: Integer): TPDColorSpace;
begin
  if Depth > MaxColorSpaceDepth then
  begin
    raise EPdfParseException.CreateFmt(ColorSpaceTooDeep, [MaxColorSpaceDepth]);
  end;

  const Resolved = Resolve(Value);
  if not Assigned(Resolved) then
  begin
    raise EPdfParseException.Create(ColorSpaceNil);
  end;

  if Resolved is TCosName then
  begin
    Exit(CreateFromName(TCosName(Resolved).Name, Context, Resources, WasDefault, Depth));
  end;

  if Resolved is TCosArray then
  begin
    Exit(CreateFromArray(TCosArray(Resolved), Context, Resources, Depth));
  end;

  raise EPdfParseException.CreateFmt(ColorSpaceBadValue, [Resolved.ClassName]);
end;

class function TPDColorSpaceFactory.TryGetDefaultName(const Name: string; out DefaultName: string): Boolean;
begin
  Result := True;
  if Name = TCosNames.DeviceCMYK then
  begin
    DefaultName := TCosNames.DefaultCMYK;
  end
  else if Name = TCosNames.DeviceRGB then
  begin
    DefaultName := TCosNames.DefaultRGB;
  end
  else if Name = TCosNames.DeviceGray then
  begin
    DefaultName := TCosNames.DefaultGray;
  end
  else
  begin
    DefaultName := '';
    Result := False;
  end;
end;

class function TPDColorSpaceFactory.TryCreateDevice(const Name: string; out Space: TPDColorSpace): Boolean;
begin
  Result := True;
  if Name = TCosNames.DeviceCMYK then
  begin
    Space := TPDDeviceCMYK.Instance;
  end
  else if Name = TCosNames.DeviceRGB then
  begin
    Space := TPDDeviceRGB.Instance;
  end
  else if Name = TCosNames.DeviceGray then
  begin
    Space := TPDDeviceGray.Instance;
  end
  else
  begin
    Space := nil;
    Result := False;
  end;
end;

class function TPDColorSpaceFactory.CreateNamedResource(const Name: string; const Context: TPDDocumentContext; const Resources: TPDResources;
                                                        const WasDefault: Boolean; const Depth: Integer): TPDColorSpace;
begin
  var Value: TCosBase;
  const IsFound = (Assigned(Resources) and Resources.TryGetColorSpace(Name, Value));
  if not IsFound then
  begin
    raise EPdfParseException.CreateFmt(ColorSpaceMissing, [Name]);
  end;

  Result := CreateAt(Value, Context, Resources, WasDefault, Depth + 1);
end;

class function TPDColorSpaceFactory.CreateFromName(const Name: string; const Context: TPDDocumentContext; const Resources: TPDResources;
                                                   const WasDefault: Boolean; const Depth: Integer): TPDColorSpace;
begin
  var DefaultName: string;
  var DefaultValue: TCosBase;
  const IsDeviceName = TryGetDefaultName(Name, DefaultName);
  const HasDefault = (IsDeviceName and (not WasDefault) and Assigned(Resources) and Resources.TryGetColorSpace(DefaultName, DefaultValue));
  if HasDefault then
  begin
    Exit(CreateAt(DefaultValue, Context, Resources, True, Depth + 1));
  end;

  var Device: TPDColorSpace;
  if TryCreateDevice(Name, Device) then
  begin
    Exit(Device);
  end;

  if Name = TCosNames.Pattern then
  begin
    raise EPdfUnsupportedFeatureException.CreateFmt(ColorSpaceNotPorted, [Name]);
  end;

  Result := CreateNamedResource(Name, Context, Resources, WasDefault, Depth);
end;

class function TPDColorSpaceFactory.IsDeviceKind(const Kind: string; out DeviceName: string): Boolean;
begin
  // Not allowed in an array, but PDFBox takes them, and so do the abbreviations of inline images
  Result := True;
  if (Kind = TCosNames.DeviceGray) or (Kind = TCosNames.G) then
  begin
    DeviceName := TCosNames.DeviceGray;
  end
  else if (Kind = TCosNames.DeviceRGB) or (Kind = TCosNames.RGB) then
  begin
    DeviceName := TCosNames.DeviceRGB;
  end
  else if (Kind = TCosNames.DeviceCMYK) or (Kind = TCosNames.CMYK) then
  begin
    DeviceName := TCosNames.DeviceCMYK;
  end
  else
  begin
    DeviceName := '';
    Result := False;
  end;
end;

class function TPDColorSpaceFactory.CreateFromArray(const Items: TCosArray; const Context: TPDDocumentContext; const Resources: TPDResources;
                                                    const Depth: Integer): TPDColorSpace;
begin
  const IsEmpty = (Items.Count = 0);
  if IsEmpty then
  begin
    raise EPdfParseException.Create(ColorSpaceEmptyArray);
  end;

  var Cached: TObject;
  if Context.TryGetCachedObject(TPDCacheScope.ColorSpace, Items, Cached) then
  begin
    Exit(TPDColorSpace(Cached));
  end;

  const First = Resolve(Items.GetObject(0));
  if not (First is TCosName) then
  begin
    raise EPdfParseException.CreateFmt(ColorSpaceBadKind, [First.ClassName]);
  end;

  Result := CreateFromKind(TCosName(First).Name, Items, Context, Resources, Depth);
end;

class function TPDColorSpaceFactory.CreateFromKind(const Kind: string; const Items: TCosArray; const Context: TPDDocumentContext;
                                                   const Resources: TPDResources; const Depth: Integer): TPDColorSpace;
begin
  var DeviceName: string;
  if IsDeviceKind(Kind, DeviceName) then
  begin
    Exit(CreateFromName(DeviceName, Context, Resources, False, Depth + 1));
  end;

  if Kind = TCosNames.ICCBased then
  begin
    Exit(CreateIccBased(Items, Context, Depth));
  end;

  const IsPortLater = ((Kind = TCosNames.CalGray) or (Kind = TCosNames.CalRGB) or (Kind = TCosNames.Lab) or (Kind = TCosNames.Indexed) or
                       (Kind = TCosNames.I) or (Kind = TCosNames.Separation) or (Kind = TCosNames.DeviceN) or (Kind = TCosNames.Pattern));
  if IsPortLater then
  begin
    raise EPdfUnsupportedFeatureException.CreateFmt(ColorSpaceNotPorted, [Kind]);
  end;

  raise EPdfParseException.CreateFmt(ColorSpaceBadKind, [Kind]);
end;

class function TPDColorSpaceFactory.CreateIccBased(const Items: TCosArray; const Context: TPDDocumentContext; const Depth: Integer): TPDColorSpace;
begin
  const HasStream = ((Items.Count >= IccElementCount) and (Resolve(Items.GetObject(IccStreamIndex)) is TCosStream));
  if not HasStream then
  begin
    raise EPdfParseException.Create(IccNeedsStream);
  end;

  // The alternate has no resources of its own to look at, like PDColorSpace.create(alternate) without resources
  const NextDepth = Depth + 1;
  var ResolveAlternate: TPDAlternateResolver :=
    function(const Alternate: TCosBase): TPDColorSpace
    begin
      Result := CreateAt(Alternate, Context, nil, False, NextDepth);
    end;

  // A profile that cannot be used makes the space ask for its alternate, which may be an array that leads back to this one: that
  // alternate counts as absent (the caller falls back to the device space of N). Only the depth limit would stop it otherwise.
  if IccInProgress.Contains(Items) then
  begin
    raise EPdfParseException.Create(IccRefersToItself);
  end;

  var IccSpace: TPDICCBased;
  IccInProgress.Push(Items);
  try
    IccSpace := TPDICCBased.Create(TCosStream(Resolve(Items.GetObject(IccStreamIndex))), Context, ResolveAlternate);
  finally
    IccInProgress.Pop;
  end;

  // Made meanwhile through another way in: keep the space that the context knows
  var Cached: TObject;
  if Context.TryGetCachedObject(TPDCacheScope.ColorSpace, Items, Cached) then
  begin
    IccSpace.Free;
    Exit(TPDColorSpace(Cached));
  end;
  Context.AddCachedObject(TPDCacheScope.ColorSpace, Items, IccSpace);
  Result := IccSpace;
end;

end.
