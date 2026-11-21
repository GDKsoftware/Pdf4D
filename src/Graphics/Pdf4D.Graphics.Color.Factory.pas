// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: PDColorSpace.create (pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/color/PDColorSpace.java, 3.0.8) and the
// colour space part of PDResources.getColorSpace, with the reading of the arrays of PDIndexed, PDSeparation, PDDeviceN,
// PDDeviceNAttributes and PDDeviceNProcess.
unit Pdf4D.Graphics.Color.Factory;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Graphics.&Function,
  Pdf4D.Graphics.Color,
  Pdf4D.Graphics.Color.Special,
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
    class function CreateFromDictionary(const Wrapper: TCosDictionary; const Context: TPDDocumentContext; const Resources: TPDResources;
                                        const WasDefault: Boolean; const Depth: Integer): TPDColorSpace; static;
    class function CreateFromName(const Name: string; const Context: TPDDocumentContext; const Resources: TPDResources; const WasDefault: Boolean;
                                  const Depth: Integer): TPDColorSpace; static;
    class function CreateFromArray(const Items: TCosArray; const Context: TPDDocumentContext; const Resources: TPDResources;
                                   const Depth: Integer): TPDColorSpace; static;
    class function CreateFromKind(const Kind: string; const Items: TCosArray; const Context: TPDDocumentContext; const Resources: TPDResources;
                                  const Depth: Integer): TPDColorSpace; static;
    class function TryGetDefaultName(const Name: string; out DefaultName: string): Boolean; static;
    class function TryCreateDevice(const Name: string; out Space: TPDColorSpace): Boolean; static;
    class function CreateIccBased(const Items: TCosArray; const Context: TPDDocumentContext; const Depth: Integer): TPDColorSpace; static;
    class function CreateCieBased(const Kind: string; const Items: TCosArray; const Context: TPDDocumentContext): TPDColorSpace; static;
    class function BuildIndexed(const Items: TCosArray; const Context: TPDDocumentContext; const Resources: TPDResources;
                                const Depth: Integer): TPDColorSpace; static;
    class function CreateIndexed(const Items: TCosArray; const Context: TPDDocumentContext; const Resources: TPDResources;
                                 const Depth: Integer): TPDColorSpace; static;
    class function CreateSeparation(const Items: TCosArray; const Context: TPDDocumentContext; const Resources: TPDResources;
                                    const Depth: Integer): TPDColorSpace; static;
    class function CreateDeviceN(const Items: TCosArray; const Context: TPDDocumentContext; const Resources: TPDResources;
                                 const Depth: Integer): TPDColorSpace; static;
    class function ReadLookupData(const Items: TCosArray): TBytes; static;
    class function ReadColorantNames(const Items: TCosArray): TArray<string>; static;
    class function ReadNameList(const Value: TCosBase; const Description: string): TArray<string>; static;
    class function ReadDeviceNAttributes(const Attributes: TCosDictionary; const ColorantNames: TArray<string>; const Context: TPDDocumentContext;
                                         const Resources: TPDResources; const Depth: Integer): TPDDeviceNAttributes; static;
    class procedure ReadProcess(const Process: TCosDictionary; const Context: TPDDocumentContext; const Depth: Integer;
                                var Attributes: TPDDeviceNAttributes); static;
    class function ReadColorants(const Colorants: TCosDictionary; const ColorantNames: TArray<string>; const Context: TPDDocumentContext;
                                 const Resources: TPDResources; const Depth: Integer): TArray<TPDDeviceNColorant>; static;
    class function CreateTintTransform(const Items: TCosArray; const Context: TPDDocumentContext): TPDFunction; static;
    // Makes the context the owner of Space under Items, unless the context has a space for Items by now
    class function StoreInContext(const Items: TCosArray; const Context: TPDDocumentContext; const Space: TPDColorSpace): TPDColorSpace; static;
    class function CreatePattern(const Items: TCosArray; const Context: TPDDocumentContext; const Depth: Integer): TPDColorSpace; static;
    class function CreateNamedResource(const Name: string; const Context: TPDDocumentContext; const Resources: TPDResources; const WasDefault: Boolean;
                                       const Depth: Integer): TPDColorSpace; static;
    class function IsDeviceKind(const Kind: string; out DeviceName: string): Boolean; static;

  public
    // Value is a name or an array, as the colour space operators and the /ColorSpace entries of images have them, or an
    // indirect reference to one. The device names give the shared spaces, a name of /ColorSpace in the resources gives that
    // space, and /DefaultGray, /DefaultRGB and /DefaultCMYK replace the device spaces unless WasDefault says that the value is the
    // default itself. A space that is not shared is made once per document (the context owns it): the same object (the same
    // array, the same name in the resources) gives the same colour space. Raises EPdfParseException for a value that is no
    // colour space, a colour space that is incomplete, one that leads back to itself and spaces that are nested deeper than
    // MaxColorSpaceDepth. Resources may not be nil.
    class function Create(const Value: TCosBase; const Resources: TPDResources; const WasDefault: Boolean = False): TPDColorSpace; static;
    // An Indexed colour space of an array that does not live as long as the document (the array of an inline image). The caller owns the space,
    // which keeps no reference to Items, and the context never sees the array. Raises like Create. Resources may not be nil.
    class function CreateUncachedIndexed(const Items: TCosArray; const Resources: TPDResources): TPDColorSpace; static;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.Null,
  Pdf4D.Cos.Number,
  Pdf4D.Cos.PdfString,
  Pdf4D.Cos.PdfObject,
  Pdf4D.Graphics.Color.Cie,
  Pdf4D.Graphics.Color.Device,
  Pdf4D.Graphics.Color.IccBased,
  Pdf4D.Graphics.Color.Pattern;

resourcestring
  ColorSpaceNil = 'The colour space is missing';
  ColorSpaceMissing = 'Missing colour space: %s';
  ColorSpaceEmptyArray = 'The colour space array is empty';
  ColorSpaceBadKind = 'Invalid colour space kind: %s';
  ColorSpaceBadValue = 'A colour space is a name or an array, not %s';
  ColorSpaceTooDeep = 'Colour spaces are nested deeper than %d levels';
  IndexedTooShort = 'An Indexed colour space array needs a base, a hival and a lookup table';
  IndexedHivalNotANumber = 'The hival of an Indexed colour space is no number';
  IndexedBadLookup = 'The lookup table of an Indexed colour space is no string or stream: %s';
  IndexedLookupUnreadable = 'The lookup table of an Indexed colour space cannot be read: %s';
  SeparationTooShort = 'A Separation colour space array needs a name, an alternate colour space and a tint transform';
  DeviceNTooShort = 'A DeviceN colour space array needs colorant names, an alternate colour space and a tint transform';
  DeviceNBadNames = 'The colorant names of a DeviceN colour space are no array of names';
  ProcessBadComponents = 'The components of the /Process of a DeviceN colour space are no array of names';
  ColorantNotSeparation = 'The colorant %s of a DeviceN colour space is no Separation colour space';
  IccNeedsStream = 'An ICCBased colour space array must have a stream as second element';
  ColorSpaceRefersToItself = 'A colour space is being made while one of its parts asks for it again';

const
  IccElementCount = 2;
  IccStreamIndex = 1;
  IndexedBaseIndex = 1;
  IndexedHivalIndex = 2;
  IndexedLookupIndex = 3;
  ColorantNameIndex = 1;
  AlternateIndex = 2;
  TintTransformIndex = 3;
  DeviceNAttributesIndex = 4;

type
  // The colour space arrays that this thread is making, innermost last. Colour spaces nest at most MaxColorSpaceDepth + 1 deep.
  TColorSpaceArraysInProgress = record
    Items: array[0..MaxColorSpaceDepth + 1] of TCosArray;
    Count: Integer;

    function Contains(const ColorSpaceArray: TCosArray): Boolean;
    procedure Push(const ColorSpaceArray: TCosArray);
    procedure Pop;
  end;

threadvar
  ArraysInProgress: TColorSpaceArraysInProgress;

function TColorSpaceArraysInProgress.Contains(const ColorSpaceArray: TCosArray): Boolean;
begin
  Result := False;
  for var Index := 0 to Count - 1 do
  begin
    Result := (Result or (Items[Index] = ColorSpaceArray));
  end;
end;

procedure TColorSpaceArraysInProgress.Push(const ColorSpaceArray: TCosArray);
begin
  Items[Count] := ColorSpaceArray;
  Inc(Count);
end;

procedure TColorSpaceArraysInProgress.Pop;
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

  if (Resolved is TCosDictionary) and TCosDictionary(Resolved).ContainsKey(TCosNames.ColorSpace) then
  begin
    Exit(CreateFromDictionary(TCosDictionary(Resolved), Context, Resources, WasDefault, Depth));
  end;

  raise EPdfParseException.CreateFmt(ColorSpaceBadValue, [Resolved.ClassName]);
end;

// PDColorSpace.create: a dictionary with a /ColorSpace entry is the space of that entry (PDFBOX-4833); one that points to itself raises (PDFBOX-5315)
class function TPDColorSpaceFactory.CreateFromDictionary(const Wrapper: TCosDictionary; const Context: TPDDocumentContext;
                                                         const Resources: TPDResources; const WasDefault: Boolean;
                                                         const Depth: Integer): TPDColorSpace;
begin
  var Entry: TCosBase;
  const IsFound = Wrapper.TryGetDictionaryObject(TCosNames.ColorSpace, Entry);
  if (not IsFound) or (Resolve(Entry) = Wrapper) then
  begin
    raise EPdfParseException.Create(ColorSpaceRefersToItself);
  end;

  Result := CreateAt(Entry, Context, Resources, WasDefault, Depth + 1);
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
    Exit(TPDPattern.Instance);
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

  // A part of the array that leads back to the array itself would make it for ever (the depth limit stops that as well, but only
  // after every part has been made at every level)
  if ArraysInProgress.Contains(Items) then
  begin
    raise EPdfParseException.Create(ColorSpaceRefersToItself);
  end;

  ArraysInProgress.Push(Items);
  try
    Result := CreateFromKind(TCosName(First).Name, Items, Context, Resources, Depth);
  finally
    ArraysInProgress.Pop;
  end;
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

  if Kind = TCosNames.Pattern then
  begin
    Exit(CreatePattern(Items, Context, Depth));
  end;

  const IsCieBased = ((Kind = TCosNames.CalGray) or (Kind = TCosNames.CalRGB) or (Kind = TCosNames.Lab));
  if IsCieBased then
  begin
    Exit(CreateCieBased(Kind, Items, Context));
  end;

  if Kind = TCosNames.Indexed then
  begin
    Exit(CreateIndexed(Items, Context, Resources, Depth));
  end;

  if Kind = TCosNames.Separation then
  begin
    Exit(CreateSeparation(Items, Context, Resources, Depth));
  end;

  if Kind = TCosNames.DeviceN then
  begin
    Exit(CreateDeviceN(Items, Context, Resources, Depth));
  end;

  raise EPdfParseException.CreateFmt(ColorSpaceBadKind, [Kind]);
end;

// PDColorSpace.create for [/Pattern] and [/Pattern base]: the underlying space has no resources of its own, as in PDFBox
class function TPDColorSpaceFactory.CreatePattern(const Items: TCosArray; const Context: TPDDocumentContext; const Depth: Integer): TPDColorSpace;
begin
  const HasUnderlyingSpace = (Items.Count > 1);
  if not HasUnderlyingSpace then
  begin
    Exit(TPDPattern.Instance);
  end;

  const UnderlyingSpace = CreateAt(Items.GetObject(1), Context, nil, False, Depth + 1);
  Result := StoreInContext(Items, Context, TPDPatternColorSpace.Create(UnderlyingSpace));
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

  // A profile that cannot be used makes the space ask for its alternate, which may be an array that leads back to this one:
  // CreateFromArray raises for that, and the alternate counts as absent (the space falls back to the device space of N)
  Result := StoreInContext(Items, Context, TPDICCBased.Create(TCosStream(Resolve(Items.GetObject(IccStreamIndex))), Context, ResolveAlternate));
end;

class function TPDColorSpaceFactory.StoreInContext(const Items: TCosArray; const Context: TPDDocumentContext; const Space: TPDColorSpace): TPDColorSpace;
begin
  // Made meanwhile through another way in: keep the space that the context knows
  var Cached: TObject;
  if Context.TryGetCachedObject(TPDCacheScope.ColorSpace, Items, Cached) then
  begin
    Space.Free;
    Exit(TPDColorSpace(Cached));
  end;

  Context.AddCachedObject(TPDCacheScope.ColorSpace, Items, Space);
  Result := Space;
end;

class function TPDColorSpaceFactory.CreateCieBased(const Kind: string; const Items: TCosArray; const Context: TPDDocumentContext): TPDColorSpace;
begin
  var Space: TPDColorSpace;
  if Kind = TCosNames.CalGray then
  begin
    Space := TPDCalGray.Create(Items);
  end
  else if Kind = TCosNames.CalRGB then
  begin
    Space := TPDCalRGB.Create(Items);
  end
  else
  begin
    Space := TPDLab.Create(Items);
  end;

  Result := StoreInContext(Items, Context, Space);
end;

class function TPDColorSpaceFactory.ReadLookupData(const Items: TCosArray): TBytes;
begin
  var Lookup: TCosBase := nil;
  if Items.Count > IndexedLookupIndex then
  begin
    Lookup := Resolve(Items.GetObject(IndexedLookupIndex));
  end;

  if (not Assigned(Lookup)) or (Lookup is TCosNull) then
  begin
    Exit(nil);
  end;

  if Lookup is TCosString then
  begin
    Exit(TCosString(Lookup).Bytes);
  end;

  if not (Lookup is TCosStream) then
  begin
    raise EPdfParseException.CreateFmt(IndexedBadLookup, [Lookup.ClassName]);
  end;

  try
    Result := TCosStream(Lookup).DecodePrefix(MaxIndexedEntries * MaxRasterComponents);
  except
    on Failure: Exception do
    begin
      if TPdfFailure.IsInputFailure(Failure) then
      begin
        raise EPdfParseException.CreateFmt(IndexedLookupUnreadable, [Failure.Message]);
      end;
      raise;
    end;
  end;
end;

// PDIndexed(COSArray, PDResources): the base comes from the reference where there is one, the table from a string or a stream
class function TPDColorSpaceFactory.BuildIndexed(const Items: TCosArray; const Context: TPDDocumentContext; const Resources: TPDResources;
                                                 const Depth: Integer): TPDColorSpace;
begin
  const HasParts = (Items.Count > IndexedHivalIndex);
  if not HasParts then
  begin
    raise EPdfParseException.Create(IndexedTooShort);
  end;

  const Base = CreateAt(Items.Get(IndexedBaseIndex), Context, Resources, False, Depth + 1);
  const Hival = Resolve(Items.GetObject(IndexedHivalIndex));
  if not (Hival is TCosNumber) then
  begin
    raise EPdfParseException.Create(IndexedHivalNotANumber);
  end;

  Result := TPDIndexed.Create(Base, TCosNumber(Hival).IntValue, ReadLookupData(Items));
end;

class function TPDColorSpaceFactory.CreateIndexed(const Items: TCosArray; const Context: TPDDocumentContext; const Resources: TPDResources;
                                                  const Depth: Integer): TPDColorSpace;
begin
  Result := StoreInContext(Items, Context, BuildIndexed(Items, Context, Resources, Depth));
end;

class function TPDColorSpaceFactory.CreateUncachedIndexed(const Items: TCosArray; const Resources: TPDResources): TPDColorSpace;
begin
  if not Assigned(Resources) then
  begin
    raise EArgumentNilException.Create('Resources');
  end;

  Result := BuildIndexed(Items, Resources.Context, Resources, 0);
end;

class function TPDColorSpaceFactory.CreateTintTransform(const Items: TCosArray; const Context: TPDDocumentContext): TPDFunction;
begin
  Result := TPDFunction.Create(Items.GetObject(TintTransformIndex), Context);
end;

// PDSeparation(COSArray, PDResources); the colorant name is only read as a name (a value that is no name gives the empty name)
class function TPDColorSpaceFactory.CreateSeparation(const Items: TCosArray; const Context: TPDDocumentContext; const Resources: TPDResources;
                                                     const Depth: Integer): TPDColorSpace;
begin
  const HasParts = (Items.Count > TintTransformIndex);
  if not HasParts then
  begin
    raise EPdfParseException.Create(SeparationTooShort);
  end;

  var ColorantName := '';
  const ColorantValue = Resolve(Items.GetObject(ColorantNameIndex));
  if ColorantValue is TCosName then
  begin
    ColorantName := TCosName(ColorantValue).Name;
  end;

  const Alternate = CreateAt(Items.Get(AlternateIndex), Context, Resources, False, Depth + 1);
  Result := StoreInContext(Items, Context, TPDSeparation.Create(ColorantName, Alternate, CreateTintTransform(Items, Context)));
end;

class function TPDColorSpaceFactory.ReadNameList(const Value: TCosBase; const Description: string): TArray<string>;
begin
  if not (Value is TCosArray) then
  begin
    raise EPdfParseException.Create(Description);
  end;

  const Names = TCosArray(Value);
  SetLength(Result, Names.Count);
  for var Index := 0 to Names.Count - 1 do
  begin
    const Item = Resolve(Names.GetObject(Index));
    if not (Item is TCosName) then
    begin
      raise EPdfParseException.Create(Description);
    end;
    Result[Index] := TCosName(Item).Name;
  end;
end;

class function TPDColorSpaceFactory.ReadColorantNames(const Items: TCosArray): TArray<string>;
begin
  Result := ReadNameList(Resolve(Items.GetObject(ColorantNameIndex)), DeviceNBadNames);
end;

// PDDeviceNProcess.getColorSpace (without resources) and getComponents
class procedure TPDColorSpaceFactory.ReadProcess(const Process: TCosDictionary; const Context: TPDDocumentContext; const Depth: Integer;
                                                 var Attributes: TPDDeviceNAttributes);
begin
  Attributes.HasProcess := True;
  var ComponentNames: TCosArray;
  if Process.TryGetCosArray(TCosNames.Components, ComponentNames) then
  begin
    Attributes.ProcessComponents := ReadNameList(ComponentNames, ProcessBadComponents);
  end;

  var SpaceValue: TCosBase;
  if Process.TryGetDictionaryObject(TCosNames.ColorSpace, SpaceValue) then
  begin
    Attributes.ProcessColorSpace := CreateAt(SpaceValue, Context, nil, False, Depth + 1);
  end;
end;

// PDDeviceNAttributes.getColorants: only the colorants that the space names are made (the others are never looked at)
class function TPDColorSpaceFactory.ReadColorants(const Colorants: TCosDictionary; const ColorantNames: TArray<string>;
                                                  const Context: TPDDocumentContext; const Resources: TPDResources;
                                                  const Depth: Integer): TArray<TPDDeviceNColorant>;
begin
  Result := nil;
  SetLength(Result, Length(ColorantNames));
  var Count := 0;
  for var ColorantName in ColorantNames do
  begin
    var Value: TCosBase;
    if not Colorants.TryGetDictionaryObject(ColorantName, Value) then
    begin
      Continue;
    end;

    const Space = CreateAt(Value, Context, Resources, False, Depth + 1);
    if not (Space is TPDSeparation) then
    begin
      raise EPdfParseException.CreateFmt(ColorantNotSeparation, [ColorantName]);
    end;

    var Colorant: TPDDeviceNColorant;
    Colorant.Name := ColorantName;
    Colorant.Separation := TPDSeparation(Space);
    Result[Count] := Colorant;
    Inc(Count);
  end;
  SetLength(Result, Count);
end;

class function TPDColorSpaceFactory.ReadDeviceNAttributes(const Attributes: TCosDictionary; const ColorantNames: TArray<string>;
                                                          const Context: TPDDocumentContext; const Resources: TPDResources;
                                                          const Depth: Integer): TPDDeviceNAttributes;
begin
  Result := Default(TPDDeviceNAttributes);
  Result.IsNChannel := (Attributes.GetNameAsString(TCosNames.Subtype, '') = TCosNames.NChannel);

  var Process: TCosDictionary;
  if Attributes.TryGetCosDictionary(TCosNames.Process, Process) then
  begin
    ReadProcess(Process, Context, Depth, Result);
  end;

  var Colorants: TCosDictionary;
  if Attributes.TryGetCosDictionary(TCosNames.Colorants, Colorants) then
  begin
    Result.Colorants := ReadColorants(Colorants, ColorantNames, Context, Resources, Depth);
  end;
end;

// PDDeviceN(COSArray, PDResources); attributes that are no dictionary count as absent
class function TPDColorSpaceFactory.CreateDeviceN(const Items: TCosArray; const Context: TPDDocumentContext; const Resources: TPDResources;
                                                  const Depth: Integer): TPDColorSpace;
begin
  const HasParts = (Items.Count > TintTransformIndex);
  if not HasParts then
  begin
    raise EPdfParseException.Create(DeviceNTooShort);
  end;

  const ColorantNames = ReadColorantNames(Items);
  TPDDeviceN.CheckColorantCount(Length(ColorantNames));
  const Alternate = CreateAt(Items.Get(AlternateIndex), Context, Resources, False, Depth + 1);

  var AttributesValue: TCosBase := nil;
  if Items.Count > DeviceNAttributesIndex then
  begin
    AttributesValue := Resolve(Items.GetObject(DeviceNAttributesIndex));
  end;

  const HasAttributes = (AttributesValue is TCosDictionary);
  var Attributes := Default(TPDDeviceNAttributes);
  if HasAttributes then
  begin
    Attributes := ReadDeviceNAttributes(TCosDictionary(AttributesValue), ColorantNames, Context, Resources, Depth);
  end;

  Result := StoreInContext(Items, Context, TPDDeviceN.Create(ColorantNames, Alternate, CreateTintTransform(Items, Context), HasAttributes, Attributes));
end;

end.
