// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Not a port of PDFBox, which leaves ICC profiles to the Java colour management. Written from the specification
// ICC.1:2010 (profile version 4.3), which also covers the version 2 profiles: the header, the tag table and the types curv,
// para, XYZ, lut8 (mft1), lut16 (mft2) and lutAToB (mAB). The parser decodes what the conversion to sRGB needs
// (Pdf4D.Graphics.Icc.Transform) and gives EPdfParseException for everything else.
unit Pdf4D.Graphics.Icc.Profile;

{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  System.Generics.Collections;

const
  // The size of a profile
  MaxIccProfileSize = 16777216;
  // Input channels of a CLUT
  MaxIccClutInputs = 16;
  // Grid points of a CLUT (the product of the grid points per input)
  MaxIccClutPoints = 16777216;
  // Entries of the tag table
  MaxIccTags = 4096;
  // Entries of a curve table
  MaxIccCurveEntries = 65536;

type
  // The colour space of the device side of a profile; Other has the NumberOfComponents of its own
  TIccColorSpace = (Gray, Rgb, Cmyk, Lab, Other);

  // The profile connection space
  TIccPcs = (Xyz, Lab);

  // What the profile converts with
  TIccSourceKind = (Lut, MatrixTrc, GrayTrc);

  // How the Lab values of a LUT are encoded: Legacy16 is the encoding of lut16 (L* 100 is 0xFF00), Normal that of lut8 and
  // lutAToB (L* 100 is the maximum)
  TIccLabEncoding = (Normal, Legacy16);

  TIccCurveKind = (Identity, Gamma, Table, Parametric);

  // Reads the numbers of one tag; a read outside the tag gives EPdfParseException
  TIccTagReader = record
  private
    FData: TBytes;
    FStart: Int64;
    FSize: Int64;

  public
    constructor Create(const Data: TBytes; const Start, Size: Int64);

    // Raises EPdfParseException unless Count bytes at Position are inside the tag
    procedure Require(const Position, Count: Int64);
    function U8(const Position: Int64): Cardinal;
    function U16(const Position: Int64): Cardinal;
    function U32(const Position: Int64): Cardinal;
    function S15Fixed16(const Position: Int64): Double;

    property Size: Int64 read FSize;
  end;

  // A one-dimensional curve of a profile: a table, a gamma or a parametric function. Input and output are 0..1.
  TIccCurve = class
  private
    FKind: TIccCurveKind;
    FGamma: Double;
    FFunctionType: Integer;
    FParameters: array[0..6] of Double;
    FTable: TArray<Single>;

    function IsAboveBreak(const X: Double): Boolean;
    function EvaluateParametric(const X: Double): Double;
    function EvaluateTable(const X: Double): Double;

  public
    // Reads a 'curv' or 'para' at Position of the tag; Size is what the curve takes
    class function Parse(const Reader: TIccTagReader; const Position: Int64; out Size: Int64): TIccCurve; static;
    class function FromTable(const Entries: TArray<Single>): TIccCurve; static;
    // Base to the power of Exponent for a base of 0 or more, without a floating point exception
    class function SafePower(const Base, Exponent: Double): Double; static;
    // Not a number is 0
    class function ClampToUnit(const Value: Double): Double; static;

    function Evaluate(const Value: Single): Single;
  end;

  // The A2B table of a profile: device values to the PCS. lut8, lut16 and lutAToB are all this: the curves A, a CLUT, the
  // curves M, a matrix and the curves B, each of which may be absent.
  TIccLut = class
  private
    FInputCount: Integer;
    FLabEncoding: TIccLabEncoding;
    FACurves: TObjectList<TIccCurve>;
    FMCurves: TObjectList<TIccCurve>;
    FBCurves: TObjectList<TIccCurve>;
    FMatrix: TArray<Double>;
    FGridPoints: TArray<Integer>;
    FStrides: TArray<Integer>;
    FClut: TArray<Word>;

    class function CountClutPoints(const GridPoints: TArray<Integer>): Int64; static;
    procedure ReadClut(const Reader: TIccTagReader; const Position: Int64; const BytesPerEntry: Integer);
    procedure BuildStrides;
    procedure ReadCurves(const Reader: TIccTagReader; const Position: Int64; const Count: Integer; const Target: TObjectList<TIccCurve>);
    procedure ReadTableCurves(const Reader: TIccTagReader; const Position: Int64; const Count, Entries: Integer; const Is16Bit: Boolean;
                              const Target: TObjectList<TIccCurve>);
    procedure ReadLut8Or16(const Reader: TIccTagReader; const Is16Bit: Boolean);
    procedure ReadLutAToB(const Reader: TIccTagReader);
    procedure ReadClutOfLutAToB(const Reader: TIccTagReader; const ClutOffset, CurvesAOffset: Int64);
    procedure ReadStagesAfterClut(const Reader: TIccTagReader; const MatrixOffset, CurvesMOffset, CurvesBOffset: Int64);
    class procedure CheckStageOffset(const Reader: TIccTagReader; const Offset: Int64); static;

  public
    constructor Create;
    destructor Destroy; override;

    // Raises EPdfParseException for a tag that is not usable; the type is the signature of the tag ('mft1', 'mft2' or 'mAB ')
    class function Parse(const Reader: TIccTagReader; const TypeSignature: Cardinal): TIccLut; static;

    property InputCount: Integer read FInputCount;
    property LabEncoding: TIccLabEncoding read FLabEncoding;
    // Empty when the table has no such stage
    property ACurves: TObjectList<TIccCurve> read FACurves;
    property MCurves: TObjectList<TIccCurve> read FMCurves;
    property BCurves: TObjectList<TIccCurve> read FBCurves;
    // 12 numbers (3x3 row by row, then the 3 offsets), or empty
    property Matrix: TArray<Double> read FMatrix;
    // Per input, empty without a CLUT
    property GridPoints: TArray<Integer> read FGridPoints;
    // Entries of the CLUT between two points of each input; the first input changes slowest
    property Strides: TArray<Integer> read FStrides;
    // Three entries per grid point, 0..65535
    property Clut: TArray<Word> read FClut;
  end;

  TIccTag = record
    Offset: Int64;
    Size: Int64;
    TypeSignature: Cardinal;
  end;

  // A parsed ICC profile. The object owns its curves and tables. Parse raises EPdfParseException for a profile that is not
  // usable, and nothing else.
  TIccProfile = class
  private
    FColorSpace: TIccColorSpace;
    FNumberOfComponents: Integer;
    FPcs: TIccPcs;
    FIsSRGB: Boolean;
    FSourceKind: TIccSourceKind;
    FLut: TIccLut;
    FCurves: TObjectList<TIccCurve>;
    FColorants: TArray<Double>;
    FTags: TDictionary<Cardinal, TIccTag>;

    constructor Create;

    class function DeviceModel(const Header: TIccTagReader): string; static;
    procedure Load(const Data: TBytes);
    procedure ReadHeader(const Data: TBytes);
    procedure ReadColorSpace(const Signature: Cardinal);
    procedure ReadPcs(const Signature: Cardinal);
    procedure ReadTagTable(const Data: TBytes);
    procedure ChooseSource(const Data: TBytes);
    function HasTags(const Signatures: array of string): Boolean;
    function TryFindLutTag(out Signature: string): Boolean;
    function ReaderOf(const Data: TBytes; const Signature: string): TIccTagReader;
    procedure LoadLut(const Data: TBytes; const Signature: string);
    procedure LoadMatrixTrc(const Data: TBytes);
    procedure LoadGrayTrc(const Data: TBytes);
    function ReadColorant(const Data: TBytes; const Signature: string): TArray<Double>;
    function ReadTagCurve(const Data: TBytes; const Signature: string): TIccCurve;

  public
    destructor Destroy; override;

    // Raises EPdfParseException for a profile that is not usable: the header, the tag table or the tags the profile needs
    class function Parse(const Data: TBytes): TIccProfile; static;
    class function SignatureOf(const Text: string): Cardinal; static;
    class function SignatureText(const Signature: Cardinal): string; static;

    function ColorSpace: TIccColorSpace;
    function NumberOfComponents: Integer;
    // Like PDICCBased.is_sRGB: the device model in the header is "sRGB"
    function IsSRGB: Boolean;
    function Pcs: TIccPcs;
    function SourceKind: TIccSourceKind;
    // The type signature of a tag, such as 'mft2'; False when the profile has no such tag
    function TryGetTagType(const Signature: string; out TypeSignature: string): Boolean;

    // The A2B table, for a profile whose SourceKind is Lut
    property Lut: TIccLut read FLut;
    // The curves of the device channels: 3 for MatrixTrc, 1 for GrayTrc
    property Curves: TObjectList<TIccCurve> read FCurves;
    // The colorants of a MatrixTrc profile in the PCS: 9 numbers, X Y Z of red, then of green, then of blue
    property Colorants: TArray<Double> read FColorants;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  Pdf4D.Common.Defines;

const
  HeaderSize = 128;
  TagTableEntrySize = 12;
  MinTagSize = 8;
  MaxMajorVersion = 4;
  VersionOffset = 8;
  ColorSpaceOffset = 16;
  PcsOffset = 20;
  AcspOffset = 36;
  ModelOffset = 52;
  ModelLength = 7;
  SrgbModel = 'sRGB';
  LutHeaderSize = 32;
  OutputChannels = 3;
  CurveHeaderSize = 12;
  ClutHeaderSizeOfLutAToB = 20;
  Lut8TableEntries = 256;
  MaxExponent = 700.0;
  ColorSpaceNames: array[0..10] of string = ('GRAY', 'RGB ', 'CMYK', 'Lab ', 'XYZ ', 'Luv ', 'YCbr', 'Yxy ', 'HSV ', 'HLS ', 'CMY ');

resourcestring
  IccOutsideTag = 'ICC tag data at %d (%d bytes) is outside the tag of %d bytes';
  IccBadCurve = 'ICC curve type %s is not supported';
  IccBadCurveTable = 'ICC curve table of %d entries is not supported';
  IccBadParametricType = 'ICC parametric curve of function type %d is not supported';
  IccBadLutChannels = 'ICC lookup table with %d input and %d output channels is not supported';
  IccBadGridPoints = 'ICC lookup table with %d grid points is not supported';
  IccTooManyGridPoints = 'ICC lookup table with more than %d grid points';
  IccBadLutType = 'ICC lookup table type %s is not supported';
  IccBadTableEntries = 'ICC lookup table with %d table entries is not supported';
  IccBadClutPrecision = 'ICC lookup table with %d bytes per entry is not supported';
  IccBadStageOffset = 'ICC lookup table stage at offset %d is outside the tag';
  IccProfileTooLarge = 'ICC profile of %d bytes is larger than the limit of %d bytes';
  IccProfileTooSmall = 'ICC profile of %d bytes has no header and tag table';
  IccNoSignature = 'ICC profile without the acsp signature';
  IccBadVersion = 'ICC profile version %d is not supported';
  IccBadColorSpace = 'ICC colour space %s is not supported';
  IccBadPcs = 'ICC profile connection space %s is not supported';
  IccTooManyTags = 'ICC profile with %d tags';
  IccTagTableTooLarge = 'ICC tag table of %d tags does not fit the profile of %d bytes';
  IccTagOutsideProfile = 'ICC tag %s (offset %d, %d bytes) is outside the profile';
  IccMissingTag = 'ICC profile has no tag %s';
  IccBadLutInput = 'ICC lookup table has %d input channels where the profile has %d components';
  IccNoTransform = 'ICC profile has no tags to convert its colours';
  IccBadMatrixPcs = 'ICC profile with colorants and a PCS other than XYZ';
  IccBadXyzTag = 'ICC tag %s is not an XYZ tag';
  IccBadSignatureText = 'An ICC signature has 4 characters, not "%s"';
  IccFailure = 'ICC profile cannot be read: %s';

{ TIccTagReader }

constructor TIccTagReader.Create(const Data: TBytes; const Start, Size: Int64);
begin
  FData := Data;
  FStart := Start;
  FSize := Size;
end;

procedure TIccTagReader.Require(const Position, Count: Int64);
begin
  const IsInside = ((Position >= 0) and (Count >= 0) and (Position <= FSize) and (Count <= FSize - Position));
  if not IsInside then
  begin
    raise EPdfParseException.CreateFmt(IccOutsideTag, [Position, Count, FSize]);
  end;
end;

function TIccTagReader.U8(const Position: Int64): Cardinal;
begin
  Require(Position, 1);
  Result := FData[FStart + Position];
end;

function TIccTagReader.U16(const Position: Int64): Cardinal;
begin
  Require(Position, 2);
  Result := (Cardinal(FData[FStart + Position]) shl 8) or FData[FStart + Position + 1];
end;

function TIccTagReader.U32(const Position: Int64): Cardinal;
begin
  Require(Position, 4);
  Result := (Cardinal(FData[FStart + Position]) shl 24) or (Cardinal(FData[FStart + Position + 1]) shl 16) or
            (Cardinal(FData[FStart + Position + 2]) shl 8) or FData[FStart + Position + 3];
end;

function TIccTagReader.S15Fixed16(const Position: Int64): Double;
begin
  Result := Integer(U32(Position)) / 65536.0;
end;

{ TIccCurve }

class function TIccCurve.Parse(const Reader: TIccTagReader; const Position: Int64; out Size: Int64): TIccCurve;
begin
  const CurvType = $63757276;
  const ParaType = $70617261;

  const CurveSignature = Reader.U32(Position);
  if CurveSignature = CurvType then
  begin
    Result := TIccCurve.Create;
    try
      Size := CurveHeaderSize;
      const Count = Reader.U32(Position + 8);
      const IsTooLong = (Count > MaxIccCurveEntries);
      if IsTooLong then
      begin
        raise EPdfParseException.CreateFmt(IccBadCurveTable, [Int64(Count)]);
      end;
      Reader.Require(Position + CurveHeaderSize, Int64(Count) * 2);
      Size := CurveHeaderSize + Int64(Count) * 2;

      if Count = 0 then
      begin
        Result.FKind := TIccCurveKind.Identity;
      end
      else if Count = 1 then
      begin
        Result.FKind := TIccCurveKind.Gamma;
        Result.FGamma := Reader.U16(Position + CurveHeaderSize) / 256.0;
      end
      else
      begin
        Result.FKind := TIccCurveKind.Table;
        SetLength(Result.FTable, Count);
        for var Index := 0 to Integer(Count) - 1 do
        begin
          Result.FTable[Index] := Reader.U16(Position + CurveHeaderSize + Int64(Index) * 2) / 65535.0;
        end;
      end;
    except
      Result.Free;
      raise;
    end;
  end
  else if CurveSignature = ParaType then
  begin
    const FunctionType = Reader.U16(Position + 8);
    var ParameterCount: Integer;
    case FunctionType of
      0 : ParameterCount := 1;
      1 : ParameterCount := 3;
      2 : ParameterCount := 4;
      3 : ParameterCount := 5;
      4 : ParameterCount := 7;
    else
      raise EPdfParseException.CreateFmt(IccBadParametricType, [Int64(FunctionType)]);
    end;
    Reader.Require(Position + CurveHeaderSize, Int64(ParameterCount) * 4);

    Result := TIccCurve.Create;
    Size := CurveHeaderSize + Int64(ParameterCount) * 4;
    Result.FKind := TIccCurveKind.Parametric;
    Result.FFunctionType := Integer(FunctionType);
    for var Index := 0 to ParameterCount - 1 do
    begin
      Result.FParameters[Index] := Reader.S15Fixed16(Position + CurveHeaderSize + Int64(Index) * 4);
    end;
  end
  else
  begin
    raise EPdfParseException.CreateFmt(IccBadCurve, [TIccProfile.SignatureText(CurveSignature)]);
  end;
end;

class function TIccCurve.FromTable(const Entries: TArray<Single>): TIccCurve;
begin
  Result := TIccCurve.Create;
  Result.FKind := TIccCurveKind.Table;
  Result.FTable := Entries;
end;

class function TIccCurve.SafePower(const Base, Exponent: Double): Double;
begin
  const IsPositive = (Base > 0.0);
  if not IsPositive then
  begin
    Exit(0.0);
  end;

  const Logarithm = Ln(Base) * Exponent;
  if Logarithm > MaxExponent then
  begin
    Result := Exp(MaxExponent);
  end
  else if Logarithm < -MaxExponent then
  begin
    Result := 0.0;
  end
  else
  begin
    Result := Exp(Logarithm);
  end;
end;

class function TIccCurve.ClampToUnit(const Value: Double): Double;
begin
  // Not (Value > 0) catches NaN as well
  if not (Value > 0.0) then
  begin
    Result := 0.0;
  end
  else if Value > 1.0 then
  begin
    Result := 1.0;
  end
  else
  begin
    Result := Value;
  end;
end;

function TIccCurve.Evaluate(const Value: Single): Single;
begin
  const Input = ClampToUnit(Value);

  var Output: Double;
  case FKind of
    TIccCurveKind.Identity   : Output := Input;
    TIccCurveKind.Gamma      : Output := SafePower(Input, FGamma);
    TIccCurveKind.Table      : Output := EvaluateTable(Input);
    TIccCurveKind.Parametric : Output := EvaluateParametric(Input);
  else
    raise ENotSupportedException.CreateFmt('Unsupported curve kind: %d', [Ord(FKind)]);
  end;
  Result := ClampToUnit(Output);
end;

function TIccCurve.EvaluateTable(const X: Double): Double;
begin
  const LastIndex = High(FTable);
  const Scaled = X * LastIndex;
  const Index = Min(Trunc(Scaled), LastIndex - 1);
  const Fraction = Scaled - Index;
  Result := FTable[Index] + (FTable[Index + 1] - FTable[Index]) * Fraction;
end;

function TIccCurve.IsAboveBreak(const X: Double): Boolean;
begin
  const A = FParameters[1];
  const B = FParameters[2];
  Result := ((A <> 0.0) and (X >= -B / A));
end;

// The functions of the specification; the parameters are g, a, b, c, d, e and f in that order
function TIccCurve.EvaluateParametric(const X: Double): Double;
begin
  const G = FParameters[0];
  const A = FParameters[1];
  const B = FParameters[2];
  const C = FParameters[3];
  const D = FParameters[4];
  const E = FParameters[5];
  const F = FParameters[6];

  case FFunctionType of
    0 : Result := SafePower(X, G);
    1 :
      begin
        if IsAboveBreak(X) then
        begin
          Result := SafePower(A * X + B, G);
        end
        else
        begin
          Result := 0.0;
        end;
      end;
    2 :
      begin
        if IsAboveBreak(X) then
        begin
          Result := SafePower(A * X + B, G) + C;
        end
        else
        begin
          Result := C;
        end;
      end;
    3 :
      begin
        if X >= D then
        begin
          Result := SafePower(A * X + B, G);
        end
        else
        begin
          Result := C * X;
        end;
      end;
    4 :
      begin
        if X >= D then
        begin
          Result := SafePower(A * X + B, G) + E;
        end
        else
        begin
          Result := C * X + F;
        end;
      end;
  else
    raise ENotSupportedException.CreateFmt('Unsupported parametric function type: %d', [FFunctionType]);
  end;
end;

{ TIccLut }

constructor TIccLut.Create;
begin
  inherited Create;
  FACurves := TObjectList<TIccCurve>.Create;
  FMCurves := TObjectList<TIccCurve>.Create;
  FBCurves := TObjectList<TIccCurve>.Create;
end;

destructor TIccLut.Destroy;
begin
  FBCurves.Free;
  FMCurves.Free;
  FACurves.Free;
  inherited Destroy;
end;

class function TIccLut.Parse(const Reader: TIccTagReader; const TypeSignature: Cardinal): TIccLut;
begin
  const Lut8Type = $6D667431;
  const Lut16Type = $6D667432;
  const LutAToBType = $6D414220;

  if (TypeSignature <> Lut8Type) and (TypeSignature <> Lut16Type) and (TypeSignature <> LutAToBType) then
  begin
    raise EPdfParseException.CreateFmt(IccBadLutType, [TIccProfile.SignatureText(TypeSignature)]);
  end;

  Result := TIccLut.Create;
  try
    if TypeSignature = LutAToBType then
    begin
      Result.ReadLutAToB(Reader);
    end
    else
    begin
      Result.ReadLut8Or16(Reader, (TypeSignature = Lut16Type));
    end;
  except
    Result.Free;
    raise;
  end;
end;

class function TIccLut.CountClutPoints(const GridPoints: TArray<Integer>): Int64;
begin
  Result := 1;
  for var Points in GridPoints do
  begin
    const IsDegenerate = (Points < 2);
    if IsDegenerate then
    begin
      raise EPdfParseException.CreateFmt(IccBadGridPoints, [Points]);
    end;

    // The grid points of one input are one byte, so the product cannot overflow before the check
    Result := Result * Points;
    const IsTooLarge = (Result > MaxIccClutPoints);
    if IsTooLarge then
    begin
      raise EPdfParseException.CreateFmt(IccTooManyGridPoints, [MaxIccClutPoints]);
    end;
  end;
end;

procedure TIccLut.ReadClut(const Reader: TIccTagReader; const Position: Int64; const BytesPerEntry: Integer);
begin
  const EntryCount = CountClutPoints(FGridPoints) * OutputChannels;
  Reader.Require(Position, EntryCount * BytesPerEntry);

  SetLength(FClut, EntryCount);
  for var Index := 0 to EntryCount - 1 do
  begin
    if BytesPerEntry = 1 then
    begin
      FClut[Index] := Word(Reader.U8(Position + Index) * 257);
    end
    else
    begin
      FClut[Index] := Reader.U16(Position + Int64(Index) * 2);
    end;
  end;
  BuildStrides;
end;

procedure TIccLut.BuildStrides;
begin
  SetLength(FStrides, Length(FGridPoints));
  var Stride := OutputChannels;
  for var Index := High(FGridPoints) downto 0 do
  begin
    FStrides[Index] := Stride;
    Stride := Stride * FGridPoints[Index];
  end;
end;

procedure TIccLut.ReadCurves(const Reader: TIccTagReader; const Position: Int64; const Count: Integer; const Target: TObjectList<TIccCurve>);
begin
  var CurvePosition := Position;
  for var Index := 1 to Count do
  begin
    var Size: Int64;
    Target.Add(TIccCurve.Parse(Reader, CurvePosition, Size));
    // Every curve starts at a multiple of 4 bytes
    CurvePosition := CurvePosition + ((Size + 3) and not Int64(3));
  end;
end;

procedure TIccLut.ReadTableCurves(const Reader: TIccTagReader; const Position: Int64; const Count, Entries: Integer; const Is16Bit: Boolean;
                                  const Target: TObjectList<TIccCurve>);
begin
  const BytesPerEntry = IfThen(Is16Bit, 2, 1);
  Reader.Require(Position, Int64(Count) * Entries * BytesPerEntry);

  for var Curve := 0 to Count - 1 do
  begin
    var Table: TArray<Single>;
    SetLength(Table, Entries);
    for var Index := 0 to Entries - 1 do
    begin
      const EntryPosition = Position + (Int64(Curve) * Entries + Index) * BytesPerEntry;
      if Is16Bit then
      begin
        Table[Index] := Reader.U16(EntryPosition) / 65535.0;
      end
      else
      begin
        Table[Index] := Reader.U8(EntryPosition) / 255.0;
      end;
    end;
    Target.Add(TIccCurve.FromTable(Table));
  end;
end;

// lut8 and lut16: header, matrix (not used, it only applies to an XYZ input), input tables, CLUT, output tables
procedure TIccLut.ReadLut8Or16(const Reader: TIccTagReader; const Is16Bit: Boolean);
begin
  const Inputs = Reader.U8(8);
  const Outputs = Reader.U8(9);
  const Grid = Reader.U8(10);
  const IsUsable = ((Inputs >= 1) and (Inputs <= MaxIccClutInputs) and (Outputs = OutputChannels));
  if not IsUsable then
  begin
    raise EPdfParseException.CreateFmt(IccBadLutChannels, [Int64(Inputs), Int64(Outputs)]);
  end;

  var InputEntries := Lut8TableEntries;
  var OutputEntries := Lut8TableEntries;
  var TablesPosition := 48;
  var BytesPerEntry := 1;
  FLabEncoding := TIccLabEncoding.Normal;
  if Is16Bit then
  begin
    InputEntries := Integer(Reader.U16(48));
    OutputEntries := Integer(Reader.U16(50));
    TablesPosition := 52;
    BytesPerEntry := 2;
    FLabEncoding := TIccLabEncoding.Legacy16;
    const AreEntriesUsable = ((InputEntries >= 2) and (OutputEntries >= 2));
    if not AreEntriesUsable then
    begin
      raise EPdfParseException.CreateFmt(IccBadTableEntries, [Min(InputEntries, OutputEntries)]);
    end;
  end;

  FInputCount := Integer(Inputs);
  SetLength(FGridPoints, FInputCount);
  for var Index := 0 to FInputCount - 1 do
  begin
    FGridPoints[Index] := Integer(Grid);
  end;

  const ClutPosition = TablesPosition + Int64(FInputCount) * InputEntries * BytesPerEntry;
  const OutputPosition = ClutPosition + CountClutPoints(FGridPoints) * OutputChannels * BytesPerEntry;
  ReadTableCurves(Reader, TablesPosition, FInputCount, InputEntries, Is16Bit, FACurves);
  ReadClut(Reader, ClutPosition, BytesPerEntry);
  ReadTableCurves(Reader, OutputPosition, OutputChannels, OutputEntries, Is16Bit, FBCurves);
end;

class procedure TIccLut.CheckStageOffset(const Reader: TIccTagReader; const Offset: Int64);
begin
  const IsInside = ((Offset >= LutHeaderSize) and (Offset < Reader.Size));
  if not IsInside then
  begin
    raise EPdfParseException.CreateFmt(IccBadStageOffset, [Offset]);
  end;
end;

procedure TIccLut.ReadClutOfLutAToB(const Reader: TIccTagReader; const ClutOffset, CurvesAOffset: Int64);
begin
  SetLength(FGridPoints, FInputCount);
  for var Index := 0 to FInputCount - 1 do
  begin
    FGridPoints[Index] := Integer(Reader.U8(ClutOffset + Index));
  end;

  const BytesPerEntry = Integer(Reader.U8(ClutOffset + 16));
  const IsPrecisionUsable = ((BytesPerEntry = 1) or (BytesPerEntry = 2));
  if not IsPrecisionUsable then
  begin
    raise EPdfParseException.CreateFmt(IccBadClutPrecision, [BytesPerEntry]);
  end;
  ReadClut(Reader, ClutOffset + ClutHeaderSizeOfLutAToB, BytesPerEntry);

  const HasCurvesA = (CurvesAOffset <> 0);
  if HasCurvesA then
  begin
    CheckStageOffset(Reader, CurvesAOffset);
    ReadCurves(Reader, CurvesAOffset, FInputCount, FACurves);
  end;
end;

procedure TIccLut.ReadStagesAfterClut(const Reader: TIccTagReader; const MatrixOffset, CurvesMOffset, CurvesBOffset: Int64);
begin
  const HasCurvesM = (CurvesMOffset <> 0);
  if HasCurvesM then
  begin
    CheckStageOffset(Reader, CurvesMOffset);
    ReadCurves(Reader, CurvesMOffset, OutputChannels, FMCurves);
  end;

  const HasMatrix = (MatrixOffset <> 0);
  if HasMatrix then
  begin
    CheckStageOffset(Reader, MatrixOffset);
    SetLength(FMatrix, 12);
    for var Index := 0 to 11 do
    begin
      FMatrix[Index] := Reader.S15Fixed16(MatrixOffset + Int64(Index) * 4);
    end;
  end;

  const HasCurvesB = (CurvesBOffset <> 0);
  if HasCurvesB then
  begin
    CheckStageOffset(Reader, CurvesBOffset);
    ReadCurves(Reader, CurvesBOffset, OutputChannels, FBCurves);
  end;
end;

// lutAToB: A curves, CLUT, M curves, matrix and B curves, at the offsets of the header (from the start of the tag)
procedure TIccLut.ReadLutAToB(const Reader: TIccTagReader);
begin
  const Inputs = Reader.U8(8);
  const Outputs = Reader.U8(9);
  const CurvesBOffset = Int64(Reader.U32(12));
  const MatrixOffset = Int64(Reader.U32(16));
  const CurvesMOffset = Int64(Reader.U32(20));
  const ClutOffset = Int64(Reader.U32(24));
  const CurvesAOffset = Int64(Reader.U32(28));

  const HasClut = (ClutOffset <> 0);
  const IsUsable = ((Inputs >= 1) and (Inputs <= MaxIccClutInputs) and (Outputs = OutputChannels) and (HasClut or (Inputs = Outputs)));
  if not IsUsable then
  begin
    raise EPdfParseException.CreateFmt(IccBadLutChannels, [Int64(Inputs), Int64(Outputs)]);
  end;

  FInputCount := Integer(Inputs);
  FLabEncoding := TIccLabEncoding.Normal;
  if HasClut then
  begin
    CheckStageOffset(Reader, ClutOffset);
    ReadClutOfLutAToB(Reader, ClutOffset, CurvesAOffset);
  end;
  ReadStagesAfterClut(Reader, MatrixOffset, CurvesMOffset, CurvesBOffset);
end;

{ TIccProfile }

constructor TIccProfile.Create;
begin
  inherited Create;
  FCurves := TObjectList<TIccCurve>.Create;
  FTags := TDictionary<Cardinal, TIccTag>.Create;
end;

destructor TIccProfile.Destroy;
begin
  FTags.Free;
  FCurves.Free;
  FLut.Free;
  inherited Destroy;
end;

class function TIccProfile.Parse(const Data: TBytes): TIccProfile;
begin
  Result := TIccProfile.Create;
  try
    Result.Load(Data);
  except
    on Failure: Exception do
    begin
      Result.Free;
      if TPdfFailure.IsInputFailure(Failure) then
      begin
        raise EPdfParseException.CreateFmt(IccFailure, [Failure.Message]);
      end;
      raise;
    end;
  end;
end;

class function TIccProfile.SignatureOf(const Text: string): Cardinal;
begin
  if Length(Text) <> 4 then
  begin
    raise EArgumentException.CreateFmt(IccBadSignatureText, [Text]);
  end;
  Result := (Cardinal(Ord(Text[1])) shl 24) or (Cardinal(Ord(Text[2])) shl 16) or (Cardinal(Ord(Text[3])) shl 8) or Cardinal(Ord(Text[4]));
end;

class function TIccProfile.SignatureText(const Signature: Cardinal): string;
begin
  Result := '';
  for var Shift := 3 downto 0 do
  begin
    const Code = (Signature shr (Shift * 8)) and $FF;
    const IsPrintable = ((Code >= 32) and (Code < 127));
    if IsPrintable then
    begin
      Result := Result + Char(Code);
    end
    else
    begin
      Result := Result + '?';
    end;
  end;
end;

procedure TIccProfile.Load(const Data: TBytes);
begin
  const IsTooLarge = (Length(Data) > MaxIccProfileSize);
  if IsTooLarge then
  begin
    raise EPdfParseException.CreateFmt(IccProfileTooLarge, [Length(Data), MaxIccProfileSize]);
  end;
  const IsTooSmall = (Length(Data) < HeaderSize + 4);
  if IsTooSmall then
  begin
    raise EPdfParseException.CreateFmt(IccProfileTooSmall, [Length(Data)]);
  end;

  ReadHeader(Data);
  ReadTagTable(Data);
  ChooseSource(Data);
end;

procedure TIccProfile.ReadHeader(const Data: TBytes);
begin
  const Reader = TIccTagReader.Create(Data, 0, HeaderSize);
  const HasSignature = (Reader.U32(AcspOffset) = SignatureOf('acsp'));
  if not HasSignature then
  begin
    raise EPdfParseException.Create(IccNoSignature);
  end;

  const MajorVersion = Reader.U8(VersionOffset);
  const IsVersionSupported = (MajorVersion <= MaxMajorVersion);
  if not IsVersionSupported then
  begin
    raise EPdfParseException.CreateFmt(IccBadVersion, [Int64(MajorVersion)]);
  end;

  ReadColorSpace(Reader.U32(ColorSpaceOffset));
  ReadPcs(Reader.U32(PcsOffset));

  FIsSRGB := (DeviceModel(Reader) = SrgbModel);
end;

// Like PDICCBased: the first 7 bytes of the device model as text, without the characters up to the space at both ends
// (what Java's String.trim removes)
class function TIccProfile.DeviceModel(const Header: TIccTagReader): string;
begin
  var First := 0;
  var Last := ModelLength - 1;
  while (First <= Last) and (Header.U8(ModelOffset + First) <= Ord(' ')) do
  begin
    Inc(First);
  end;
  while (Last >= First) and (Header.U8(ModelOffset + Last) <= Ord(' ')) do
  begin
    Dec(Last);
  end;

  Result := '';
  for var Index := First to Last do
  begin
    Result := Result + Char(Header.U8(ModelOffset + Index));
  end;
end;

procedure TIccProfile.ReadColorSpace(const Signature: Cardinal);
begin
  const Text = SignatureText(Signature);

  FColorSpace := TIccColorSpace.Other;
  FNumberOfComponents := 3;
  case IndexStr(Text, ColorSpaceNames) of
    0 :
      begin
        FColorSpace := TIccColorSpace.Gray;
        FNumberOfComponents := 1;
      end;
    1 : FColorSpace := TIccColorSpace.Rgb;
    2 :
      begin
        FColorSpace := TIccColorSpace.Cmyk;
        FNumberOfComponents := 4;
      end;
    3 : FColorSpace := TIccColorSpace.Lab;
    4..10 : ;
  else
    const IsColorList = (Text.EndsWith('CLR') and CharInSet(Text[1], ['2'..'9', 'A'..'F']));
    if not IsColorList then
    begin
      raise EPdfParseException.CreateFmt(IccBadColorSpace, [Text]);
    end;
    FNumberOfComponents := StrToInt('$' + Text[1]);
  end;
end;

procedure TIccProfile.ReadPcs(const Signature: Cardinal);
begin
  if Signature = SignatureOf('XYZ ') then
  begin
    FPcs := TIccPcs.Xyz;
  end
  else if Signature = SignatureOf('Lab ') then
  begin
    FPcs := TIccPcs.Lab;
  end
  else
  begin
    raise EPdfParseException.CreateFmt(IccBadPcs, [SignatureText(Signature)]);
  end;
end;

procedure TIccProfile.ReadTagTable(const Data: TBytes);
begin
  const Reader = TIccTagReader.Create(Data, 0, Length(Data));
  const TagCount = Reader.U32(HeaderSize);
  const TooManyTags = (TagCount > MaxIccTags);
  if TooManyTags then
  begin
    raise EPdfParseException.CreateFmt(IccTooManyTags, [Int64(TagCount)]);
  end;
  const TableEnd = Int64(HeaderSize) + 4 + Int64(TagCount) * TagTableEntrySize;
  const IsTableInside = (TableEnd <= Length(Data));
  if not IsTableInside then
  begin
    raise EPdfParseException.CreateFmt(IccTagTableTooLarge, [Int64(TagCount), Length(Data)]);
  end;

  for var Index := 0 to Integer(TagCount) - 1 do
  begin
    const EntryPosition = Int64(HeaderSize) + 4 + Int64(Index) * TagTableEntrySize;
    const Signature = Reader.U32(EntryPosition);
    var Tag: TIccTag;
    Tag.Offset := Reader.U32(EntryPosition + 4);
    Tag.Size := Reader.U32(EntryPosition + 8);
    const IsInside = ((Tag.Size >= MinTagSize) and (Tag.Offset + Tag.Size <= Length(Data)));
    if not IsInside then
    begin
      raise EPdfParseException.CreateFmt(IccTagOutsideProfile, [SignatureText(Signature), Tag.Offset, Tag.Size]);
    end;
    Tag.TypeSignature := TIccTagReader.Create(Data, Tag.Offset, Tag.Size).U32(0);
    // The first of two tags with one signature counts
    FTags.TryAdd(Signature, Tag);
  end;
end;

function TIccProfile.HasTags(const Signatures: array of string): Boolean;
begin
  Result := True;
  for var Signature in Signatures do
  begin
    if not FTags.ContainsKey(SignatureOf(Signature)) then
    begin
      Exit(False);
    end;
  end;
end;

// The tag for the perceptual intent when it exists; Java's colour management picks it whatever the header says
function TIccProfile.TryFindLutTag(out Signature: string): Boolean;
begin
  Result := False;
  for var Candidate in ['A2B0', 'A2B1', 'A2B2'] do
  begin
    if HasTags([Candidate]) then
    begin
      Signature := Candidate;
      Exit(True);
    end;
  end;
end;

procedure TIccProfile.ChooseSource(const Data: TBytes);
begin
  var LutSignature: string;
  if TryFindLutTag(LutSignature) then
  begin
    LoadLut(Data, LutSignature);
  end
  else if (FColorSpace = TIccColorSpace.Rgb) and HasTags(['rXYZ', 'gXYZ', 'bXYZ', 'rTRC', 'gTRC', 'bTRC']) then
  begin
    LoadMatrixTrc(Data);
  end
  else if (FColorSpace = TIccColorSpace.Gray) and HasTags(['kTRC']) then
  begin
    LoadGrayTrc(Data);
  end
  else
  begin
    raise EPdfParseException.Create(IccNoTransform);
  end;
end;

function TIccProfile.ReaderOf(const Data: TBytes; const Signature: string): TIccTagReader;
begin
  var Tag: TIccTag;
  if not FTags.TryGetValue(SignatureOf(Signature), Tag) then
  begin
    raise EPdfParseException.CreateFmt(IccMissingTag, [Signature]);
  end;
  Result := TIccTagReader.Create(Data, Tag.Offset, Tag.Size);
end;

procedure TIccProfile.LoadLut(const Data: TBytes; const Signature: string);
begin
  FSourceKind := TIccSourceKind.Lut;
  var Tag: TIccTag;
  FTags.TryGetValue(SignatureOf(Signature), Tag);
  FLut := TIccLut.Parse(ReaderOf(Data, Signature), Tag.TypeSignature);

  const IsInputMatching = (FLut.InputCount = FNumberOfComponents);
  if not IsInputMatching then
  begin
    raise EPdfParseException.CreateFmt(IccBadLutInput, [FLut.InputCount, FNumberOfComponents]);
  end;
end;

procedure TIccProfile.LoadMatrixTrc(const Data: TBytes);
begin
  const IsXyz = (FPcs = TIccPcs.Xyz);
  if not IsXyz then
  begin
    raise EPdfParseException.Create(IccBadMatrixPcs);
  end;

  FSourceKind := TIccSourceKind.MatrixTrc;
  FColorants := TArray.Concat<Double>([ReadColorant(Data, 'rXYZ'), ReadColorant(Data, 'gXYZ'), ReadColorant(Data, 'bXYZ')]);
  FCurves.Add(ReadTagCurve(Data, 'rTRC'));
  FCurves.Add(ReadTagCurve(Data, 'gTRC'));
  FCurves.Add(ReadTagCurve(Data, 'bTRC'));
end;

procedure TIccProfile.LoadGrayTrc(const Data: TBytes);
begin
  FSourceKind := TIccSourceKind.GrayTrc;
  FCurves.Add(ReadTagCurve(Data, 'kTRC'));
end;

function TIccProfile.ReadColorant(const Data: TBytes; const Signature: string): TArray<Double>;
begin
  const Reader = ReaderOf(Data, Signature);
  const IsXyzType = (Reader.U32(0) = SignatureOf('XYZ '));
  if not IsXyzType then
  begin
    raise EPdfParseException.CreateFmt(IccBadXyzTag, [Signature]);
  end;

  Result := [Reader.S15Fixed16(8), Reader.S15Fixed16(12), Reader.S15Fixed16(16)];
end;

function TIccProfile.ReadTagCurve(const Data: TBytes; const Signature: string): TIccCurve;
begin
  var Size: Int64;
  Result := TIccCurve.Parse(ReaderOf(Data, Signature), 0, Size);
end;

function TIccProfile.ColorSpace: TIccColorSpace;
begin
  Result := FColorSpace;
end;

function TIccProfile.NumberOfComponents: Integer;
begin
  Result := FNumberOfComponents;
end;

function TIccProfile.IsSRGB: Boolean;
begin
  Result := FIsSRGB;
end;

function TIccProfile.Pcs: TIccPcs;
begin
  Result := FPcs;
end;

function TIccProfile.SourceKind: TIccSourceKind;
begin
  Result := FSourceKind;
end;

function TIccProfile.TryGetTagType(const Signature: string; out TypeSignature: string): Boolean;
begin
  var Tag: TIccTag;
  Result := FTags.TryGetValue(SignatureOf(Signature), Tag);
  if Result then
  begin
    TypeSignature := SignatureText(Tag.TypeSignature);
  end
  else
  begin
    TypeSignature := '';
  end;
end;

end.
