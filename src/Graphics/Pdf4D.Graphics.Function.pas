// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/common/function/PDFunction.java, PDFunctionType0.java,
// PDFunctionType2.java, PDFunctionType3.java, PDFunctionType4.java and PDFunctionTypeIdentity.java (3.0.8)
unit Pdf4D.Graphics.&Function;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Model.DocumentContext,
  Pdf4D.Graphics.&Function.PostScript;

const
  // Inputs of a sampled (type 0) function
  MaxSampledFunctionInputs = 16;
  // Sample values (the product of Size and the outputs) that a sampled function reads
  MaxSampledFunctionSamples = 16777216;
  // Levels of stitching (type 3) functions inside each other
  MaxStitchingDepth = 8;
  // Functions that one call of TPDFunction.Create may build, the nested ones included
  MaxFunctionsPerCreate = 10000;

type
  // A PDF function: numbers in, numbers out. The functions copy what they need from the dictionary, so the dictionary may go
  // once the function exists. A function is not thread safe, like the objects of a document.
  TPDFunction = class abstract
  private
    FContext: TPDDocumentContext;
    FDomain: TArray<Single>;
    FRange: TArray<Single>;
    FIsWarningGiven: Boolean;

  protected
    // Dictionary may be nil: the identity has none
    constructor Initialize(const Context: TPDDocumentContext; const Dictionary: TCosDictionary);

    function Calculate(const Input: TArray<Single>): TArray<Single>; virtual; abstract;

    function ClipToDomain(const Input: TArray<Single>): TArray<Single>;
    function ClipToRange(const Values: TArray<Single>): TArray<Single>;
    // Gives one warning per function, however often it is called
    procedure WarnOnce(const Fmt: string; const Args: array of const);

    class function ReadFloats(const Dictionary: TCosDictionary; const Key: string): TArray<Single>; static;
    // The bytes of the stream with the filters applied; raises EPdfParseException when that fails
    class function ReadStreamBytes(const Stream: TCosStream): TBytes; static;
    // PDFBox clips like this: a NaN stays a NaN
    class function ClipValue(const Value, Minimum, Maximum: Single): Single; static;
    class function Interpolate(const X, XMinimum, XMaximum, YMinimum, YMaximum: Single): Single; static;

    property Context: TPDDocumentContext read FContext;
    property Domain: TArray<Single> read FDomain;
    property Range: TArray<Single> read FRange;

  public
    // Port of PDFunction.create: Value is a function dictionary or stream, or the name /Identity. Raises EPdfParseException for
    // a value that is no function, a missing or inconsistent entry, an unsupported type and a limit that is exceeded (the
    // limits above). The caller owns the result.
    class function Create(const Value: TCosBase; const Context: TPDDocumentContext): TPDFunction; static;

    function FunctionType: Integer; virtual; abstract;
    function NumberOfInputParameters: Integer; virtual;
    function NumberOfOutputParameters: Integer; virtual;

    // Clips Input to the Domain and the result to the Range, like PDFBox. Never raises: an Input that is too short is
    // filled with zeros and one that is too long loses its tail, a NaN or infinity goes through the function, and a function
    // that stops halfway (see TPDFunctionType4) gives the values it has.
    function Eval(const Input: TArray<Single>): TArray<Single>;
  end;

  // Builds a function and the functions inside it, and counts them
  TPDFunctionBuilder = class
  private
    FContext: TPDDocumentContext;
    FCount: Integer;

    function BuildFromDictionary(const Dictionary: TCosDictionary; const StitchingDepth: Integer): TPDFunction;

  public
    constructor Create(const Context: TPDDocumentContext);

    function Build(const Value: TCosBase; const StitchingDepth: Integer): TPDFunction;
  end;

  // Type 0: a table of samples with multilinear interpolation
  TPDFunctionType0 = class(TPDFunction)
  private
    FSizes: TArray<Integer>;
    FStrides: TArray<Int64>;
    FEncode: TArray<Single>;
    FDecode: TArray<Single>;
    FSamples: TArray<Integer>;
    FOutputCount: Integer;
    FSampleMaximum: Single;

    procedure ReadSizes(const Dictionary: TCosDictionary);
    procedure ReadEncodeAndDecode(const Dictionary: TCosDictionary);
    procedure ReadSamples(const Stream: TCosStream; const BitsPerSample: Integer);
    function SampleValue(const Coordinates: TArray<Integer>; const OutputIndex: Integer): Integer;
    function InterpolateSamples(const Position: TArray<Single>; const Previous, Next, Coordinates: TArray<Integer>;
                                const Step: Integer): TArray<Single>;

  protected
    constructor Initialize(const Context: TPDDocumentContext; const Dictionary: TCosDictionary);

    function Calculate(const Input: TArray<Single>): TArray<Single>; override;

  public
    function FunctionType: Integer; override;
  end;

  // Type 2: exponential interpolation between C0 and C1
  TPDFunctionType2 = class(TPDFunction)
  private
    FC0: TArray<Single>;
    FC1: TArray<Single>;
    FExponent: Single;

  protected
    constructor Initialize(const Context: TPDDocumentContext; const Dictionary: TCosDictionary);

    function Calculate(const Input: TArray<Single>): TArray<Single>; override;

  public
    function FunctionType: Integer; override;
    function NumberOfInputParameters: Integer; override;
    function NumberOfOutputParameters: Integer; override;
  end;

  // Type 3: stitches functions together over sub domains
  TPDFunctionType3 = class(TPDFunction)
  private
    FFunctions: TObjectList<TPDFunction>;
    FBounds: TArray<Single>;
    FEncode: TArray<Single>;

    function EncodeMinimum(const FunctionIndex: Integer): Single;
    function EncodeMaximum(const FunctionIndex: Integer): Single;
    function PartitionValues: TArray<Single>;
    function TryFindPartition(const X: Single; out FunctionIndex: Integer; out EncodedX: Single): Boolean;

  protected
    constructor Initialize(const Context: TPDDocumentContext; const Dictionary: TCosDictionary; const Builder: TPDFunctionBuilder;
                           const StitchingDepth: Integer);

    function Calculate(const Input: TArray<Single>): TArray<Single>; override;

  public
    destructor Destroy; override;

    function FunctionType: Integer; override;
    function NumberOfOutputParameters: Integer; override;
  end;

  // Type 4: a PostScript calculator. A program that stops halfway (a stack underflow, a value of the wrong type, a limit of
  // TPsProgram) gives the values that are on its stack then, and one warning in the log of the document.
  TPDFunctionType4 = class(TPDFunction)
  private
    FProgram: TPsProgram;

    function OutputsFrom(const Stack: TArray<TPsValue>): TArray<Single>;
    procedure WarnAboutOutcome(const Outcome: TPsOutcome);

  protected
    constructor Initialize(const Context: TPDDocumentContext; const Dictionary: TCosDictionary);

    function Calculate(const Input: TArray<Single>): TArray<Single>; override;

  public
    destructor Destroy; override;

    function FunctionType: Integer; override;
  end;

  // The name /Identity: the output is the input
  TPDFunctionTypeIdentity = class(TPDFunction)
  protected
    function Calculate(const Input: TArray<Single>): TArray<Single>; override;

  public
    // -1, like PDFBox: the identity has no function type
    function FunctionType: Integer; override;
    // 0: the identity takes and gives any number of values
    function NumberOfInputParameters: Integer; override;
    function NumberOfOutputParameters: Integer; override;
  end;

implementation

uses
  System.Classes,
  System.Math,
  Pdf4D.Common.Defines,
  Pdf4D.Common.FloatGuard,
  Pdf4D.Common.Log,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Cos.PdfObject;

const
  TypeSampled = 0;
  TypeExponential = 2;
  TypeStitching = 3;
  TypePostScript = 4;
  // Past this a stride exceeds every table that can be read, so the exact value does not matter
  MaxStride = 1 shl 30;
  // A function without N in PDFBox: getFloat gives -1
  DefaultExponent = -1;

type
  // Reads the samples of a type 0 function, the most significant bit first
  TSampleBitReader = record
  private
    FBytes: TBytes;
    FPosition: Int64;
  public
    constructor Create(const Bytes: TBytes);
    function CanRead(const BitCount: Integer): Boolean;
    function Read(const BitCount: Integer): Cardinal;
  end;

{ TSampleBitReader }

constructor TSampleBitReader.Create(const Bytes: TBytes);
begin
  FBytes := Bytes;
  FPosition := 0;
end;

function TSampleBitReader.CanRead(const BitCount: Integer): Boolean;
begin
  Result := (FPosition + BitCount) <= (Int64(Length(FBytes)) * 8);
end;

function TSampleBitReader.Read(const BitCount: Integer): Cardinal;
begin
  var Value: UInt64 := 0;
  var Remaining := BitCount;
  while Remaining > 0 do
  begin
    const ByteIndex = FPosition shr 3;
    const BitsLeftInByte = 8 - Integer(FPosition and 7);
    const Take = Min(Remaining, BitsLeftInByte);
    const Shifted = (FBytes[ByteIndex] shr (BitsLeftInByte - Take)) and ((1 shl Take) - 1);
    Value := (Value shl Take) or Shifted;
    Inc(FPosition, Take);
    Dec(Remaining, Take);
  end;
  Result := Cardinal(Value);
end;

{ TPDFunction }

class function TPDFunction.Create(const Value: TCosBase; const Context: TPDDocumentContext): TPDFunction;
begin
  const Builder = TPDFunctionBuilder.Create(Context);
  try
    Result := Builder.Build(Value, 0);
  finally
    Builder.Free;
  end;
end;

constructor TPDFunction.Initialize(const Context: TPDDocumentContext; const Dictionary: TCosDictionary);
begin
  inherited Create;
  FContext := Context;
  if Assigned(Dictionary) then
  begin
    FDomain := ReadFloats(Dictionary, TCosNames.Domain);
    FRange := ReadFloats(Dictionary, TCosNames.Range);
  end;
end;

function TPDFunction.NumberOfInputParameters: Integer;
begin
  Result := Length(FDomain) div 2;
end;

function TPDFunction.NumberOfOutputParameters: Integer;
begin
  Result := Length(FRange) div 2;
end;

function TPDFunction.Eval(const Input: TArray<Single>): TArray<Single>;
begin
  var Fitted := Input;
  const Expected = NumberOfInputParameters;
  if (Expected > 0) and (Length(Input) <> Expected) then
  begin
    SetLength(Fitted, Expected);
    for var Index := 0 to Expected - 1 do
    begin
      if Index < Length(Input) then
      begin
        Fitted[Index] := Input[Index];
      end
      else
      begin
        Fitted[Index] := 0;
      end;
    end;
  end;

  const PreviousMask = TPdfFloatGuard.Enter;
  try
    Result := Calculate(Fitted);
  finally
    TPdfFloatGuard.Leave(PreviousMask);
  end;
end;

function TPDFunction.ClipToDomain(const Input: TArray<Single>): TArray<Single>;
begin
  Result := Copy(Input);
  const Pairs = Length(FDomain) div 2;
  for var Index := 0 to Min(Length(Result), Pairs) - 1 do
  begin
    Result[Index] := ClipValue(Result[Index], FDomain[2 * Index], FDomain[(2 * Index) + 1]);
  end;
end;

// Without a Range the values stay as they are; with one the result has a value for every pair
function TPDFunction.ClipToRange(const Values: TArray<Single>): TArray<Single>;
begin
  const Pairs = Length(FRange) div 2;
  if Pairs = 0 then
  begin
    Exit(Values);
  end;

  SetLength(Result, Pairs);
  for var Index := 0 to Pairs - 1 do
  begin
    var Value: Single := 0;
    if Index < Length(Values) then
    begin
      Value := Values[Index];
    end;
    Result[Index] := ClipValue(Value, FRange[2 * Index], FRange[(2 * Index) + 1]);
  end;
end;

procedure TPDFunction.WarnOnce(const Fmt: string; const Args: array of const);
begin
  if FIsWarningGiven then
  begin
    Exit;
  end;
  FIsWarningGiven := True;
  if Assigned(FContext) and Assigned(FContext.Log) then
  begin
    FContext.Log.Warning(Fmt, Args);
  end;
end;

class function TPDFunction.ReadFloats(const Dictionary: TCosDictionary; const Key: string): TArray<Single>;
begin
  var Items: TCosArray;
  if Dictionary.TryGetCosArray(Key, Items) then
  begin
    Result := Items.ToFloatArray;
  end
  else
  begin
    Result := nil;
  end;
end;

class function TPDFunction.ReadStreamBytes(const Stream: TCosStream): TBytes;
begin
  var Decoded: TStream;
  try
    Decoded := Stream.CreateDecodedStream;
  except
    on Failure: Exception do
    begin
      if TPdfFailure.IsInputFailure(Failure) then
      begin
        raise EPdfParseException.CreateFmt('The data of a function cannot be read: %s', [Failure.Message]);
      end;
      raise;
    end;
  end;

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

class function TPDFunction.ClipValue(const Value, Minimum, Maximum: Single): Single;
begin
  if Value < Minimum then
  begin
    Exit(Minimum);
  end;
  if Value > Maximum then
  begin
    Exit(Maximum);
  end;
  Result := Value;
end;

// A zero width of the source range gives the start of the target range
class function TPDFunction.Interpolate(const X, XMinimum, XMaximum, YMinimum, YMaximum: Single): Single;
begin
  const Divisor = XMaximum - XMinimum;
  if Divisor = 0 then
  begin
    Exit(YMinimum);
  end;
  Result := YMinimum + (((X - XMinimum) * (YMaximum - YMinimum)) / Divisor);
end;

{ TPDFunctionBuilder }

constructor TPDFunctionBuilder.Create(const Context: TPDDocumentContext);
begin
  inherited Create;
  FContext := Context;
end;

function TPDFunctionBuilder.Build(const Value: TCosBase; const StitchingDepth: Integer): TPDFunction;
begin
  Inc(FCount);
  if FCount > MaxFunctionsPerCreate then
  begin
    raise EPdfParseException.CreateFmt('A function holds more than %d functions', [MaxFunctionsPerCreate]);
  end;

  var Resolved := Value;
  if Resolved is TCosObject then
  begin
    Resolved := TCosObject(Resolved).GetObject;
  end;

  if Resolved is TCosName then
  begin
    if TCosName(Resolved).Name <> TCosNames.Identity then
    begin
      raise EPdfParseException.CreateFmt('The name /%s is no function', [TCosName(Resolved).Name]);
    end;
    Exit(TPDFunctionTypeIdentity.Initialize(FContext, nil));
  end;
  if Resolved is TCosDictionary then
  begin
    Exit(BuildFromDictionary(TCosDictionary(Resolved), StitchingDepth));
  end;
  raise EPdfParseException.Create('A function must be a dictionary, a stream or the name /Identity');
end;

function TPDFunctionBuilder.BuildFromDictionary(const Dictionary: TCosDictionary; const StitchingDepth: Integer): TPDFunction;
begin
  const FunctionType = Dictionary.GetInt(TCosNames.FunctionType, -1);
  case FunctionType of
    TypeSampled:
    begin
      Result := TPDFunctionType0.Initialize(FContext, Dictionary);
    end;
    TypeExponential:
    begin
      Result := TPDFunctionType2.Initialize(FContext, Dictionary);
    end;
    TypeStitching:
    begin
      Result := TPDFunctionType3.Initialize(FContext, Dictionary, Self, StitchingDepth);
    end;
    TypePostScript:
    begin
      Result := TPDFunctionType4.Initialize(FContext, Dictionary);
    end;
    else
    begin
      raise EPdfParseException.CreateFmt('The function type %d is not supported', [FunctionType]);
    end;
  end;
end;

{ TPDFunctionType0 }

constructor TPDFunctionType0.Initialize(const Context: TPDDocumentContext; const Dictionary: TCosDictionary);
begin
  inherited Initialize(Context, Dictionary);
  const InputCount = NumberOfInputParameters;
  FOutputCount := NumberOfOutputParameters;
  if (InputCount < 1) or (InputCount > MaxSampledFunctionInputs) then
  begin
    raise EPdfParseException.CreateFmt('A type 0 function needs 1 to %d inputs in its Domain', [MaxSampledFunctionInputs]);
  end;
  if FOutputCount < 1 then
  begin
    raise EPdfParseException.Create('A type 0 function needs a Range');
  end;
  if not (Dictionary is TCosStream) then
  begin
    raise EPdfParseException.Create('A type 0 function must be a stream');
  end;
  const BitsPerSample = Dictionary.GetInt(TCosNames.BitsPerSample, 0);
  if (BitsPerSample < 1) or (BitsPerSample > 32) then
  begin
    raise EPdfParseException.CreateFmt('A type 0 function has %d bits per sample', [BitsPerSample]);
  end;

  ReadSizes(Dictionary);
  ReadEncodeAndDecode(Dictionary);
  ReadSamples(TCosStream(Dictionary), BitsPerSample);
  FSampleMaximum := Power(2, BitsPerSample) - 1;
end;

procedure TPDFunctionType0.ReadSizes(const Dictionary: TCosDictionary);
begin
  const Sizes = ReadFloats(Dictionary, TCosNames.Size);
  if Length(Sizes) <> NumberOfInputParameters then
  begin
    raise EPdfParseException.Create('The Size of a type 0 function does not match its Domain');
  end;

  SetLength(FSizes, Length(Sizes));
  SetLength(FStrides, Length(Sizes));
  var Stride: Int64 := 1;
  for var Index := 0 to Length(Sizes) - 1 do
  begin
    FSizes[Index] := TFunctionMath.ToInteger(Sizes[Index]);
    if FSizes[Index] < 1 then
    begin
      raise EPdfParseException.Create('The Size of a type 0 function has a value below 1');
    end;
    FStrides[Index] := Stride;
    Stride := Min(Stride * FSizes[Index], Int64(MaxStride));
  end;
end;

// An entry that is missing or too short gets its default: the whole table for Encode, the Range for Decode
procedure TPDFunctionType0.ReadEncodeAndDecode(const Dictionary: TCosDictionary);
begin
  const GivenEncode = ReadFloats(Dictionary, TCosNames.Encode);
  SetLength(FEncode, Length(FSizes) * 2);
  for var Index := 0 to Length(FSizes) - 1 do
  begin
    if Length(GivenEncode) >= ((2 * Index) + 2) then
    begin
      FEncode[2 * Index] := GivenEncode[2 * Index];
      FEncode[(2 * Index) + 1] := GivenEncode[(2 * Index) + 1];
    end
    else
    begin
      FEncode[2 * Index] := 0;
      FEncode[(2 * Index) + 1] := FSizes[Index] - 1;
    end;
  end;

  const GivenDecode = ReadFloats(Dictionary, TCosNames.Decode);
  SetLength(FDecode, FOutputCount * 2);
  for var Index := 0 to FOutputCount - 1 do
  begin
    if Length(GivenDecode) >= ((2 * Index) + 2) then
    begin
      FDecode[2 * Index] := GivenDecode[2 * Index];
      FDecode[(2 * Index) + 1] := GivenDecode[(2 * Index) + 1];
    end
    else
    begin
      FDecode[2 * Index] := Range[2 * Index];
      FDecode[(2 * Index) + 1] := Range[(2 * Index) + 1];
    end;
  end;
end;

// A table that is cut short has zeros after its last whole sample, as in PDFBox. A table that needs more than
// MaxSampledFunctionSamples values is read up to that number, and the function warns.
procedure TPDFunctionType0.ReadSamples(const Stream: TCosStream; const BitsPerSample: Integer);
begin
  var Wanted: Int64 := FOutputCount;
  for var Size in FSizes do
  begin
    if Wanted <= MaxSampledFunctionSamples then
    begin
      Wanted := Wanted * Size;
    end;
  end;
  if Wanted > MaxSampledFunctionSamples then
  begin
    WarnOnce('A type 0 function has more than %d sample values; only the first ones are used', [MaxSampledFunctionSamples]);
    Wanted := MaxSampledFunctionSamples;
  end;

  const Bytes = ReadStreamBytes(Stream);
  const Available = (Int64(Length(Bytes)) * 8) div BitsPerSample;
  SetLength(FSamples, Min(Wanted, Available));
  var Reader := TSampleBitReader.Create(Bytes);
  for var Index := 0 to Length(FSamples) - 1 do
  begin
    FSamples[Index] := Integer(Reader.Read(BitsPerSample));
  end;
end;

// A sample outside the table is 0, like the samples that the data of the stream does not reach
function TPDFunctionType0.SampleValue(const Coordinates: TArray<Integer>; const OutputIndex: Integer): Integer;
begin
  var Position: Int64 := 0;
  for var Index := 0 to Length(Coordinates) - 1 do
  begin
    Position := Position + (Int64(Coordinates[Index]) * FStrides[Index]);
    if Position >= Length(FSamples) then
    begin
      Exit(0);
    end;
  end;

  const ValueIndex = (Position * FOutputCount) + OutputIndex;
  if ValueIndex >= Length(FSamples) then
  begin
    Exit(0);
  end;
  Result := FSamples[ValueIndex];
end;

// Step is the input that is interpolated; past the last input the samples of the corner are read. A coordinate that is a
// whole number needs no second corner.
function TPDFunctionType0.InterpolateSamples(const Position: TArray<Single>; const Previous, Next, Coordinates: TArray<Integer>;
                                             const Step: Integer): TArray<Single>;
begin
  SetLength(Result, FOutputCount);
  if Step = Length(Previous) then
  begin
    for var OutputIndex := 0 to FOutputCount - 1 do
    begin
      Result[OutputIndex] := SampleValue(Coordinates, OutputIndex);
    end;
    Exit;
  end;

  Coordinates[Step] := Previous[Step];
  const Lower = InterpolateSamples(Position, Previous, Next, Coordinates, Step + 1);
  if Previous[Step] = Next[Step] then
  begin
    Exit(Lower);
  end;

  Coordinates[Step] := Next[Step];
  const Upper = InterpolateSamples(Position, Previous, Next, Coordinates, Step + 1);
  for var OutputIndex := 0 to FOutputCount - 1 do
  begin
    Result[OutputIndex] := Interpolate(Position[Step], Previous[Step], Next[Step], Lower[OutputIndex], Upper[OutputIndex]);
  end;
end;

function TPDFunctionType0.Calculate(const Input: TArray<Single>): TArray<Single>;
begin
  const Clipped = ClipToDomain(Input);
  const InputCount = Length(FSizes);
  var Position: TArray<Single>;
  var Previous: TArray<Integer>;
  var Next: TArray<Integer>;
  var Coordinates: TArray<Integer>;
  SetLength(Position, InputCount);
  SetLength(Previous, InputCount);
  SetLength(Next, InputCount);
  SetLength(Coordinates, InputCount);
  for var Index := 0 to InputCount - 1 do
  begin
    const Encoded = Interpolate(Clipped[Index], Domain[2 * Index], Domain[(2 * Index) + 1], FEncode[2 * Index], FEncode[(2 * Index) + 1]);
    Position[Index] := ClipValue(Encoded, 0, FSizes[Index] - 1);
    Previous[Index] := TFunctionMath.ToInteger(TFunctionMath.FloorOf(Position[Index]));
    Next[Index] := TFunctionMath.ToInteger(TFunctionMath.CeilOf(Position[Index]));
  end;

  const Samples = InterpolateSamples(Position, Previous, Next, Coordinates, 0);
  SetLength(Result, FOutputCount);
  for var Index := 0 to FOutputCount - 1 do
  begin
    const Decoded = Interpolate(Samples[Index], 0, FSampleMaximum, FDecode[2 * Index], FDecode[(2 * Index) + 1]);
    Result[Index] := ClipValue(Decoded, Range[2 * Index], Range[(2 * Index) + 1]);
  end;
end;

function TPDFunctionType0.FunctionType: Integer;
begin
  Result := TypeSampled;
end;

{ TPDFunctionType2 }

constructor TPDFunctionType2.Initialize(const Context: TPDDocumentContext; const Dictionary: TCosDictionary);
begin
  inherited Initialize(Context, Dictionary);
  FC0 := ReadFloats(Dictionary, TCosNames.C0);
  if Length(FC0) = 0 then
  begin
    FC0 := [0];
  end;
  FC1 := ReadFloats(Dictionary, TCosNames.C1);
  if Length(FC1) = 0 then
  begin
    FC1 := [1];
  end;
  FExponent := Dictionary.GetFloat(TCosNames.N, DefaultExponent);
end;

// PDFBox does not clip the input to the Domain here, and neither do we
function TPDFunctionType2.Calculate(const Input: TArray<Single>): TArray<Single>;
begin
  const Scaled: Single = TFunctionMath.Power(Input[0], FExponent);
  var Values: TArray<Single>;
  SetLength(Values, Min(Length(FC0), Length(FC1)));
  for var Index := 0 to Length(Values) - 1 do
  begin
    Values[Index] := FC0[Index] + (Scaled * (FC1[Index] - FC0[Index]));
  end;
  Result := ClipToRange(Values);
end;

function TPDFunctionType2.FunctionType: Integer;
begin
  Result := TypeExponential;
end;

function TPDFunctionType2.NumberOfInputParameters: Integer;
begin
  Result := Max(inherited NumberOfInputParameters, 1);
end;

function TPDFunctionType2.NumberOfOutputParameters: Integer;
begin
  Result := inherited NumberOfOutputParameters;
  if Result = 0 then
  begin
    Result := Min(Length(FC0), Length(FC1));
  end;
end;

{ TPDFunctionType3 }

constructor TPDFunctionType3.Initialize(const Context: TPDDocumentContext; const Dictionary: TCosDictionary; const Builder: TPDFunctionBuilder;
                                        const StitchingDepth: Integer);
begin
  inherited Initialize(Context, Dictionary);
  if StitchingDepth >= MaxStitchingDepth then
  begin
    raise EPdfParseException.CreateFmt('Stitching functions nest deeper than %d levels', [MaxStitchingDepth]);
  end;
  if Length(Domain) < 2 then
  begin
    raise EPdfParseException.Create('A type 3 function needs a Domain');
  end;

  var Items: TCosArray;
  if not Dictionary.TryGetCosArray(TCosNames.Functions, Items) or (Items.Count = 0) then
  begin
    raise EPdfParseException.Create('A type 3 function needs a list of Functions');
  end;
  FFunctions := TObjectList<TPDFunction>.Create(True);
  for var Index := 0 to Items.Count - 1 do
  begin
    FFunctions.Add(Builder.Build(Items.GetObject(Index), StitchingDepth + 1));
  end;

  FBounds := ReadFloats(Dictionary, TCosNames.Bounds);
  FEncode := ReadFloats(Dictionary, TCosNames.Encode);
  if (FFunctions.Count > 1) and (Length(FBounds) < (FFunctions.Count - 1)) then
  begin
    raise EPdfParseException.Create('A type 3 function has fewer Bounds than it needs');
  end;
end;

destructor TPDFunctionType3.Destroy;
begin
  FFunctions.Free;
  inherited;
end;

// A pair that Encode lacks is 0 and 1
function TPDFunctionType3.EncodeMinimum(const FunctionIndex: Integer): Single;
begin
  if Length(FEncode) >= ((2 * FunctionIndex) + 2) then
  begin
    Exit(FEncode[2 * FunctionIndex]);
  end;
  Result := 0;
end;

function TPDFunctionType3.EncodeMaximum(const FunctionIndex: Integer): Single;
begin
  if Length(FEncode) >= ((2 * FunctionIndex) + 2) then
  begin
    Exit(FEncode[(2 * FunctionIndex) + 1]);
  end;
  Result := 1;
end;

// The start of the Domain, all Bounds in the order they are given, the end of the Domain
function TPDFunctionType3.PartitionValues: TArray<Single>;
begin
  SetLength(Result, Length(FBounds) + 2);
  Result[0] := Domain[0];
  for var Index := 0 to Length(FBounds) - 1 do
  begin
    Result[Index + 1] := FBounds[Index];
  end;
  Result[High(Result)] := Domain[1];
end;

// False for a value that is in no partition (a NaN, or Bounds that do not cover it) and for a partition without a function
function TPDFunctionType3.TryFindPartition(const X: Single; out FunctionIndex: Integer; out EncodedX: Single): Boolean;
begin
  FunctionIndex := 0;
  EncodedX := X;
  if FFunctions.Count = 1 then
  begin
    EncodedX := Interpolate(X, Domain[0], Domain[1], EncodeMinimum(0), EncodeMaximum(0));
    Exit(True);
  end;

  const Partitions = PartitionValues;
  const LastPartition = Length(Partitions) - 2;
  for var Index := 0 to LastPartition do
  begin
    const IsInside = (X >= Partitions[Index]) and ((X < Partitions[Index + 1]) or ((Index = LastPartition) and (X = Partitions[Index + 1])));
    if IsInside then
    begin
      FunctionIndex := Index;
      EncodedX := Interpolate(X, Partitions[Index], Partitions[Index + 1], EncodeMinimum(Index), EncodeMaximum(Index));
      Exit(Index < FFunctions.Count);
    end;
  end;
  Result := False;
end;

// An input that no function takes gives zeros
function TPDFunctionType3.Calculate(const Input: TArray<Single>): TArray<Single>;
begin
  const X = ClipValue(Input[0], Domain[0], Domain[1]);
  var FunctionIndex: Integer;
  var EncodedX: Single;
  if not TryFindPartition(X, FunctionIndex, EncodedX) then
  begin
    SetLength(Result, NumberOfOutputParameters);
    Exit;
  end;
  Result := ClipToRange(FFunctions[FunctionIndex].Eval([EncodedX]));
end;

function TPDFunctionType3.FunctionType: Integer;
begin
  Result := TypeStitching;
end;

function TPDFunctionType3.NumberOfOutputParameters: Integer;
begin
  Result := inherited NumberOfOutputParameters;
  if Result = 0 then
  begin
    Result := FFunctions[0].NumberOfOutputParameters;
  end;
end;

{ TPDFunctionType4 }

constructor TPDFunctionType4.Initialize(const Context: TPDDocumentContext; const Dictionary: TCosDictionary);
begin
  inherited Initialize(Context, Dictionary);
  if not (Dictionary is TCosStream) then
  begin
    raise EPdfParseException.Create('A type 4 function must be a stream');
  end;
  if (Length(Domain) < 2) or (Length(Range) < 2) then
  begin
    raise EPdfParseException.Create('A type 4 function needs a Domain and a Range');
  end;

  const Bytes = ReadStreamBytes(TCosStream(Dictionary));
  var Text: string;
  SetLength(Text, Length(Bytes));
  for var Index := 0 to Length(Bytes) - 1 do
  begin
    Text[Index + 1] := Char(Bytes[Index]);
  end;
  FProgram := TPsProgram.Parse(Text);
end;

destructor TPDFunctionType4.Destroy;
begin
  FProgram.Free;
  inherited;
end;

function TPDFunctionType4.Calculate(const Input: TArray<Single>): TArray<Single>;
begin
  var Outcome: TPsOutcome;
  const Stack = FProgram.Run(ClipToDomain(Input), Outcome);
  if Outcome <> TPsOutcome.Completed then
  begin
    WarnAboutOutcome(Outcome);
  end;
  Result := OutputsFrom(Stack);
end;

// The top of the stack holds the outputs, the last output on top. A stack with fewer values than outputs fills the first
// outputs and leaves the others at the start of their Range.
function TPDFunctionType4.OutputsFrom(const Stack: TArray<TPsValue>): TArray<Single>;
begin
  const OutputCount = NumberOfOutputParameters;
  const First = Max(Length(Stack) - OutputCount, 0);
  SetLength(Result, OutputCount);
  for var Index := 0 to OutputCount - 1 do
  begin
    var Value: Single := 0;
    if (First + Index) < Length(Stack) then
    begin
      Value := Stack[First + Index].AsSingle;
    end;
    Result[Index] := ClipValue(Value, Range[2 * Index], Range[(2 * Index) + 1]);
  end;
end;

procedure TPDFunctionType4.WarnAboutOutcome(const Outcome: TPsOutcome);
begin
  case Outcome of
    TPsOutcome.StackLimit:
    begin
      WarnOnce('A type 4 function needs a stack of more than %d values; the values on the stack are used', [MaxPostScriptStackSize]);
    end;
    TPsOutcome.OperationLimit:
    begin
      WarnOnce('A type 4 function runs more than %d operations; the values on the stack are used', [MaxPostScriptOperations]);
    end;
    else
    begin
      WarnOnce('A type 4 function stopped at an operator that cannot run (stack underflow, a value of the wrong type or an ' +
               'unknown operator); the values on the stack are used', []);
    end;
  end;
end;

function TPDFunctionType4.FunctionType: Integer;
begin
  Result := TypePostScript;
end;

{ TPDFunctionTypeIdentity }

function TPDFunctionTypeIdentity.Calculate(const Input: TArray<Single>): TArray<Single>;
begin
  Result := Copy(Input);
end;

function TPDFunctionTypeIdentity.FunctionType: Integer;
begin
  Result := -1;
end;

function TPDFunctionTypeIdentity.NumberOfInputParameters: Integer;
begin
  Result := 0;
end;

function TPDFunctionTypeIdentity.NumberOfOutputParameters: Integer;
begin
  Result := 0;
end;

end.
