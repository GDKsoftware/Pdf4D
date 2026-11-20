// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/shading/PDShading.java, PDShadingType1.java, PDShadingType2.java and
// PDShadingType3.java (3.0.8), and pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/pattern/PDShadingPattern.java. The types 4 to
// 7 are made as shadings without data of their own: the renderer paints nothing for them yet.
unit Pdf4D.Graphics.Shading;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.Matrix,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Graphics.Color,
  Pdf4D.Graphics.&Function,
  Pdf4D.Model.DocumentContext,
  Pdf4D.Model.Rectangle,
  Pdf4D.Model.Resources;

const
  // Functions of a shading that has one function for each component of its colour
  MaxShadingFunctions = 32;

type
  // A shading dictionary or stream. The dictionary belongs to the document, the colour space to the document context or the process; the
  // functions belong to the shading. Not thread safe, like the objects of a document.
  TPDShading = class abstract
  private
    FDictionary: TCosDictionary;
    FColorSpace: TPDColorSpace;
    FFunctions: TObjectList<TPDFunction>;

    class function CreateOfType(const ShadingType: Integer; const Dictionary: TCosDictionary): TPDShading; static;
    class function MakeColorSpace(const Dictionary: TCosDictionary; const Resources: TPDResources): TPDColorSpace; static;
    class procedure AddFunctions(const Dictionary: TCosDictionary; const Context: TPDDocumentContext; const Functions: TObjectList<TPDFunction>); static;

  protected
    constructor Initialize(const Dictionary: TCosDictionary);

    // The entry as numbers; Count is the number it must have at least. Raises EPdfParseException when the entry is missing or short.
    function RequiredFloats(const Key: string; const Count: Integer): TArray<Single>;
    // The entry when it has at least Count numbers, else Default
    function FloatsOrDefault(const Key: string; const Count: Integer; const Default: TArray<Single>): TArray<Single>;
    // The two booleans of /Extend; both False without it
    procedure ReadExtend(out ExtendStart, ExtendEnd: Boolean);
    // A subclass reads the entries that it needs here, after the colour space and the functions are known
    procedure ReadEntries; virtual;
    // True when the type needs a function
    function NeedsFunction: Boolean; virtual;

    property Dictionary: TCosDictionary read FDictionary;

  public
    destructor Destroy; override;

    // PDShading.create: Value is a shading dictionary or stream. Raises EPdfParseException for a value that is no shading, a missing
    // /ColorSpace, a missing entry that the type needs and an unknown type, and whatever the colour space or a function raises. The
    // caller owns the result.
    class function Create(const Value: TCosBase; const Resources: TPDResources): TPDShading; static;

    function ShadingType: Integer; virtual; abstract;
    function ColorSpace: TPDColorSpace;
    function TryGetBBox(out BBox: TPdfRectangle): Boolean;
    function TryGetBackground(out Components: TArray<Single>): Boolean;
    function AntiAlias: Boolean;
    // PDShading.evalFunction: the function, or for an array of functions one for each component
    function EvalFunction(const Input: TArray<Single>): TArray<Single>;
  end;

  // Types 4 to 7: the type only
  TPDShadingMesh = class(TPDShading)
  private
    FType: Integer;

  protected
    constructor InitializeMesh(const ShadingType: Integer; const Dictionary: TCosDictionary);

    function NeedsFunction: Boolean; override;

  public
    function ShadingType: Integer; override;
  end;

  // Type 1, function-based: a function of (x, y) over the Domain, placed by Matrix
  TPDShadingType1 = class(TPDShading)
  private
    FDomain: TArray<Single>;
    FMatrix: TPdfMatrix;

  protected
    procedure ReadEntries; override;

  public
    function ShadingType: Integer; override;
    // x0, x1, y0, y1; [0 1 0 1] without /Domain
    function Domain: TArray<Single>;
    // The identity without /Matrix
    function Matrix: TPdfMatrix;
  end;

  // Type 2, axial
  TPDShadingType2 = class(TPDShading)
  private
    FCoords: TArray<Single>;
    FDomain: TArray<Single>;
    FExtendStart: Boolean;
    FExtendEnd: Boolean;

  protected
    procedure ReadEntries; override;

  public
    function ShadingType: Integer; override;
    // x0, y0, x1, y1
    function Coords: TArray<Single>;
    // t0, t1; [0 1] without /Domain
    function Domain: TArray<Single>;
    property ExtendStart: Boolean read FExtendStart;
    property ExtendEnd: Boolean read FExtendEnd;
  end;

  // Type 3, radial
  TPDShadingType3 = class(TPDShading)
  private
    FCoords: TArray<Single>;
    FDomain: TArray<Single>;
    FExtendStart: Boolean;
    FExtendEnd: Boolean;

  protected
    procedure ReadEntries; override;

  public
    function ShadingType: Integer; override;
    // x0, y0, r0, x1, y1, r1
    function Coords: TArray<Single>;
    // t0, t1; [0 1] without /Domain
    function Domain: TArray<Single>;
    property ExtendStart: Boolean read FExtendStart;
    property ExtendEnd: Boolean read FExtendEnd;
  end;

  // PDShadingPattern (PatternType 2): the shading and the matrix that places it in the default space of the stream that uses the pattern
  TPDShadingPattern = class
  private
    FDictionary: TCosDictionary;
    FShading: TPDShading;
    FMatrix: TPdfMatrix;

  public
    // Value is a pattern dictionary of PatternType 2. Raises EPdfParseException for another value, a missing /Shading and whatever
    // TPDShading.Create raises. The caller owns the result.
    constructor Create(const Value: TCosBase; const Resources: TPDResources);
    destructor Destroy; override;

    // The /ExtGState entry, nil without one; not owned
    function ExtendedGraphicsState: TCosDictionary;

    // The shading belongs to the pattern
    property Shading: TPDShading read FShading;
    // The identity without /Matrix
    property Matrix: TPdfMatrix read FMatrix;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Boolean,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Graphics.Color.Factory,
  Pdf4D.Graphics.Color.Pattern;

const
  FunctionBasedType = 1;
  AxialType = 2;
  RadialType = 3;
  FirstMeshType = 4;
  LastMeshType = 7;
  FunctionBasedDomainCount = 4;
  DomainCount = 2;
  AxialCoordsCount = 4;
  RadialCoordsCount = 6;
  ExtendCount = 2;
  ShadingPatternType = 2;

resourcestring
  ShadingIsNoDictionary = 'A shading is a dictionary or a stream, not %s';
  ShadingTypeUnknown = 'Unknown shading type %d';
  ShadingColorSpaceMissing = 'The shading has no /ColorSpace';
  ShadingColorSpaceIsPattern = 'The colour space of a shading cannot be Pattern';
  ShadingFunctionMissing = 'The shading of type %d has no /Function';
  ShadingTooManyFunctions = 'The shading has more than %d functions';
  ShadingEntryMissing = 'The shading has no /%s with %d numbers';
  PatternIsNoDictionary = 'A shading pattern is a dictionary, not %s';
  PatternTypeWrong = 'The pattern is of type %d, not a shading pattern';
  PatternShadingMissing = 'The shading pattern has no /Shading';

function ClassNameOf(const Value: TCosBase): string;
begin
  if Assigned(Value) then
  begin
    Result := Value.ClassName;
  end
  else
  begin
    Result := 'nothing';
  end;
end;

{ TPDShading }

class function TPDShading.Create(const Value: TCosBase; const Resources: TPDResources): TPDShading;
begin
  if not (Value is TCosDictionary) then
  begin
    raise EPdfParseException.CreateFmt(ShadingIsNoDictionary, [ClassNameOf(Value)]);
  end;

  const Dictionary = TCosDictionary(Value);
  Result := CreateOfType(Dictionary.GetInt(TCosNames.ShadingType, 0), Dictionary);
  try
    Result.FColorSpace := MakeColorSpace(Dictionary, Resources);
    AddFunctions(Dictionary, Resources.Context, Result.FFunctions);
    if Result.NeedsFunction and (Result.FFunctions.Count = 0) then
    begin
      raise EPdfParseException.CreateFmt(ShadingFunctionMissing, [Result.ShadingType]);
    end;
    Result.ReadEntries;
  except
    Result.Free;
    raise;
  end;
end;

class function TPDShading.CreateOfType(const ShadingType: Integer; const Dictionary: TCosDictionary): TPDShading;
begin
  case ShadingType of
    FunctionBasedType           : Result := TPDShadingType1.Initialize(Dictionary);
    AxialType                   : Result := TPDShadingType2.Initialize(Dictionary);
    RadialType                  : Result := TPDShadingType3.Initialize(Dictionary);
    FirstMeshType..LastMeshType : Result := TPDShadingMesh.InitializeMesh(ShadingType, Dictionary);
  else
    raise EPdfParseException.CreateFmt(ShadingTypeUnknown, [ShadingType]);
  end;
end;

class function TPDShading.MakeColorSpace(const Dictionary: TCosDictionary; const Resources: TPDResources): TPDColorSpace;
begin
  var Value: TCosBase;
  if not Dictionary.TryGetDictionaryObject(TCosNames.ColorSpace, Value) then
  begin
    raise EPdfParseException.Create(ShadingColorSpaceMissing);
  end;

  Result := TPDColorSpaceFactory.Create(Value, Resources);
  if Result is TPDPattern then
  begin
    raise EPdfParseException.Create(ShadingColorSpaceIsPattern);
  end;
end;

class procedure TPDShading.AddFunctions(const Dictionary: TCosDictionary; const Context: TPDDocumentContext;
                                        const Functions: TObjectList<TPDFunction>);
begin
  var Value: TCosBase;
  if not Dictionary.TryGetDictionaryObject(TCosNames.Function_, Value) then
  begin
    Exit;
  end;

  if not (Value is TCosArray) then
  begin
    Functions.Add(TPDFunction.Create(Value, Context));
    Exit;
  end;

  const Items = TCosArray(Value);
  if Items.Count > MaxShadingFunctions then
  begin
    raise EPdfParseException.CreateFmt(ShadingTooManyFunctions, [MaxShadingFunctions]);
  end;

  for var Index := 0 to Items.Count - 1 do
  begin
    Functions.Add(TPDFunction.Create(Items.GetObject(Index), Context));
  end;
end;

constructor TPDShading.Initialize(const Dictionary: TCosDictionary);
begin
  inherited Create;
  FDictionary := Dictionary;
  FFunctions := TObjectList<TPDFunction>.Create(True);
end;

destructor TPDShading.Destroy;
begin
  FFunctions.Free;
  inherited;
end;

procedure TPDShading.ReadEntries;
begin
end;

function TPDShading.NeedsFunction: Boolean;
begin
  Result := True;
end;

function TPDShading.RequiredFloats(const Key: string; const Count: Integer): TArray<Single>;
begin
  var Items: TCosArray;
  const IsComplete = (FDictionary.TryGetCosArray(Key, Items) and (Items.Count >= Count));
  if not IsComplete then
  begin
    raise EPdfParseException.CreateFmt(ShadingEntryMissing, [Key, Count]);
  end;

  Result := Items.ToFloatArray;
end;

function TPDShading.FloatsOrDefault(const Key: string; const Count: Integer; const Default: TArray<Single>): TArray<Single>;
begin
  var Items: TCosArray;
  const IsComplete = (FDictionary.TryGetCosArray(Key, Items) and (Items.Count >= Count));
  if IsComplete then
  begin
    Result := Items.ToFloatArray;
  end
  else
  begin
    Result := Default;
  end;
end;

procedure TPDShading.ReadExtend(out ExtendStart, ExtendEnd: Boolean);
begin
  ExtendStart := False;
  ExtendEnd := False;
  var Items: TCosArray;
  const IsComplete = (FDictionary.TryGetCosArray(TCosNames.Extend, Items) and (Items.Count >= ExtendCount));
  if not IsComplete then
  begin
    Exit;
  end;

  const First = Items.GetObject(0);
  const Second = Items.GetObject(1);
  ExtendStart := ((First is TCosBoolean) and TCosBoolean(First).Value);
  ExtendEnd := ((Second is TCosBoolean) and TCosBoolean(Second).Value);
end;

function TPDShading.ColorSpace: TPDColorSpace;
begin
  Result := FColorSpace;
end;

function TPDShading.TryGetBBox(out BBox: TPdfRectangle): Boolean;
begin
  BBox := Default(TPdfRectangle);
  var Items: TCosArray;
  Result := FDictionary.TryGetCosArray(TCosNames.BBox, Items);
  if Result then
  begin
    BBox := TPdfRectangle.FromCosArray(Items);
  end;
end;

function TPDShading.TryGetBackground(out Components: TArray<Single>): Boolean;
begin
  Components := nil;
  var Items: TCosArray;
  Result := FDictionary.TryGetCosArray(TCosNames.Background, Items);
  if Result then
  begin
    Components := Items.ToFloatArray;
  end;
end;

function TPDShading.AntiAlias: Boolean;
begin
  Result := FDictionary.GetBoolean(TCosNames.AntiAlias, False);
end;

function TPDShading.EvalFunction(const Input: TArray<Single>): TArray<Single>;
begin
  if FFunctions.Count = 1 then
  begin
    Exit(FFunctions[0].Eval(Input));
  end;

  SetLength(Result, FFunctions.Count);
  for var Index := 0 to FFunctions.Count - 1 do
  begin
    const Values = FFunctions[Index].Eval(Input);
    const HasValue = (Length(Values) > 0);
    if HasValue then
    begin
      Result[Index] := Values[0];
    end
    else
    begin
      Result[Index] := 0;
    end;
  end;
end;

{ TPDShadingMesh }

constructor TPDShadingMesh.InitializeMesh(const ShadingType: Integer; const Dictionary: TCosDictionary);
begin
  inherited Initialize(Dictionary);
  FType := ShadingType;
end;

function TPDShadingMesh.NeedsFunction: Boolean;
begin
  Result := False;
end;

function TPDShadingMesh.ShadingType: Integer;
begin
  Result := FType;
end;

{ TPDShadingType1 }

procedure TPDShadingType1.ReadEntries;
begin
  FDomain := FloatsOrDefault(TCosNames.Domain, FunctionBasedDomainCount, [0, 1, 0, 1]);
  var Items: TCosArray;
  if Dictionary.TryGetCosArray(TCosNames.Matrix, Items) then
  begin
    FMatrix := TPdfMatrix.FromCosArray(Items);
  end
  else
  begin
    FMatrix := TPdfMatrix.Identity;
  end;
end;

function TPDShadingType1.ShadingType: Integer;
begin
  Result := FunctionBasedType;
end;

function TPDShadingType1.Domain: TArray<Single>;
begin
  Result := FDomain;
end;

function TPDShadingType1.Matrix: TPdfMatrix;
begin
  Result := FMatrix;
end;

{ TPDShadingType2 }

procedure TPDShadingType2.ReadEntries;
begin
  FCoords := RequiredFloats(TCosNames.Coords, AxialCoordsCount);
  FDomain := FloatsOrDefault(TCosNames.Domain, DomainCount, [0, 1]);
  ReadExtend(FExtendStart, FExtendEnd);
end;

function TPDShadingType2.ShadingType: Integer;
begin
  Result := AxialType;
end;

function TPDShadingType2.Coords: TArray<Single>;
begin
  Result := FCoords;
end;

function TPDShadingType2.Domain: TArray<Single>;
begin
  Result := FDomain;
end;

{ TPDShadingType3 }

procedure TPDShadingType3.ReadEntries;
begin
  FCoords := RequiredFloats(TCosNames.Coords, RadialCoordsCount);
  FDomain := FloatsOrDefault(TCosNames.Domain, DomainCount, [0, 1]);
  ReadExtend(FExtendStart, FExtendEnd);
end;

function TPDShadingType3.ShadingType: Integer;
begin
  Result := RadialType;
end;

function TPDShadingType3.Coords: TArray<Single>;
begin
  Result := FCoords;
end;

function TPDShadingType3.Domain: TArray<Single>;
begin
  Result := FDomain;
end;

{ TPDShadingPattern }

constructor TPDShadingPattern.Create(const Value: TCosBase; const Resources: TPDResources);
begin
  if not (Value is TCosDictionary) then
  begin
    raise EPdfParseException.CreateFmt(PatternIsNoDictionary, [ClassNameOf(Value)]);
  end;

  inherited Create;
  FDictionary := TCosDictionary(Value);
  FMatrix := TPdfMatrix.Identity;

  const PatternType = FDictionary.GetInt(TCosNames.PatternType, 0);
  if PatternType <> ShadingPatternType then
  begin
    raise EPdfParseException.CreateFmt(PatternTypeWrong, [PatternType]);
  end;

  var ShadingValue: TCosBase;
  if not FDictionary.TryGetDictionaryObject(TCosNames.Shading, ShadingValue) then
  begin
    raise EPdfParseException.Create(PatternShadingMissing);
  end;
  FShading := TPDShading.Create(ShadingValue, Resources);

  var Items: TCosArray;
  if FDictionary.TryGetCosArray(TCosNames.Matrix, Items) then
  begin
    FMatrix := TPdfMatrix.FromCosArray(Items);
  end;
end;

destructor TPDShadingPattern.Destroy;
begin
  FShading.Free;
  inherited;
end;

function TPDShadingPattern.ExtendedGraphicsState: TCosDictionary;
begin
  if not FDictionary.TryGetCosDictionary(TCosNames.ExtGState, Result) then
  begin
    Result := nil;
  end;
end;

end.
