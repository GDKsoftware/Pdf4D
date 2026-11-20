// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Builds small ICC profiles for the tests (ICC.1:2010) and finds the profiles and reference files in tests/icc and
// tests/reference/color
unit Pdf4D.Tests.IccBuilder;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections;

type
  // Writes the big-endian fields of an ICC profile
  TIccTestWriter = class
  private
    FStream: TBytesStream;

  public
    constructor Create;
    destructor Destroy; override;

    function U8(const Value: Cardinal): TIccTestWriter;
    function U16(const Value: Cardinal): TIccTestWriter;
    function U32(const Value: Cardinal): TIccTestWriter;
    function S15Fixed16(const Value: Double): TIccTestWriter;
    function Signature(const Text: string): TIccTestWriter;
    function Zeros(const Count: Integer): TIccTestWriter;
    function Append(const Bytes: TBytes): TIccTestWriter;
    function Size: Integer;
    function Bytes: TBytes;
  end;

  // A profile with a header and a list of tags
  TIccTestProfile = class
  private
    FDeviceClass: string;
    FColorSpace: string;
    FPcs: string;
    FModel: string;
    FMajorVersion: Integer;
    FTagSignatures: TList<string>;
    FTagContents: TList<TBytes>;

  public
    constructor Create(const DeviceClass, ColorSpace, Pcs: string);
    destructor Destroy; override;

    procedure AddTag(const Signature: string; const Content: TBytes);
    function Build: TBytes;

    property Model: string read FModel write FModel;
    property MajorVersion: Integer read FMajorVersion write FMajorVersion;
  end;

  // The content of tags
  TIccTestTags = class
  public
    // 'curv' with one entry: a gamma
    class function CurveGamma(const Gamma: Double): TBytes; static;
    // 'curv' with a table of 16-bit entries (an empty table is the identity)
    class function CurveTable(const Entries: array of Word): TBytes; static;
    // 'para' of a function type with its parameters in the order of the specification
    class function Parametric(const FunctionType: Integer; const Parameters: array of Double): TBytes; static;
    class function Xyz(const X, Y, Z: Double): TBytes; static;
    // The curve with the parameters of the sRGB transfer function, in the 'para' encoding of function type 3
    class function SrgbCurve: TBytes; static;
    // 'mft1' (lut8): 256 entries per table, the CLUT has GridPoints per input
    class function Lut8(const InputChannels, OutputChannels, GridPoints: Integer; const InputTables, Clut, OutputTables: array of Byte): TBytes; static;
    // 'mft2' (lut16): InputEntries per input table, OutputEntries per output table
    class function Lut16(const InputChannels, OutputChannels, GridPoints, InputEntries, OutputEntries: Integer;
                         const InputTables, Clut, OutputTables: array of Word): TBytes; static;
    // 'mAB ': every curve is a complete 'curv' or 'para' tag; Matrix is empty or has 12 numbers (3x3 and the 3 offsets);
    // GridPoints is empty without a CLUT; ClutBytes is 1 or 2
    class function LutAToB(const InputChannels, OutputChannels: Integer; const BCurves: TArray<TBytes>; const Matrix: array of Double;
                           const MCurves: TArray<TBytes>; const GridPoints: array of Byte; const ClutBytes: Integer; const Clut: array of Word;
                           const ACurves: TArray<TBytes>): TBytes; static;
  end;

  // Where the profiles and reference files are
  TIccTestFiles = class
  public
    class function IccFolder: string; static;
    class function ReferenceFolder: string; static;
    class function ReadProfile(const FileName: string): TBytes; static;
  end;

implementation

uses
  System.IOUtils,
  System.Math;

{ TIccTestWriter }

constructor TIccTestWriter.Create;
begin
  inherited Create;
  FStream := TBytesStream.Create;
end;

destructor TIccTestWriter.Destroy;
begin
  FStream.Free;
  inherited Destroy;
end;

function TIccTestWriter.U8(const Value: Cardinal): TIccTestWriter;
begin
  const Content = Byte(Value);
  FStream.WriteBuffer(Content, 1);
  Result := Self;
end;

function TIccTestWriter.U16(const Value: Cardinal): TIccTestWriter;
begin
  U8(Value shr 8);
  U8(Value and $FF);
  Result := Self;
end;

function TIccTestWriter.U32(const Value: Cardinal): TIccTestWriter;
begin
  U16(Value shr 16);
  U16(Value and $FFFF);
  Result := Self;
end;

function TIccTestWriter.S15Fixed16(const Value: Double): TIccTestWriter;
begin
  U32(Cardinal(Integer(Round(Value * 65536.0))));
  Result := Self;
end;

function TIccTestWriter.Signature(const Text: string): TIccTestWriter;
begin
  for var Index := 1 to 4 do
  begin
    U8(Ord(Text[Index]));
  end;
  Result := Self;
end;

function TIccTestWriter.Zeros(const Count: Integer): TIccTestWriter;
begin
  for var Index := 1 to Count do
  begin
    U8(0);
  end;
  Result := Self;
end;

function TIccTestWriter.Append(const Bytes: TBytes): TIccTestWriter;
begin
  if Length(Bytes) > 0 then
  begin
    FStream.WriteBuffer(Bytes[0], Length(Bytes));
  end;
  Result := Self;
end;

function TIccTestWriter.Size: Integer;
begin
  Result := Integer(FStream.Size);
end;

function TIccTestWriter.Bytes: TBytes;
begin
  Result := Copy(FStream.Bytes, 0, Integer(FStream.Size));
end;

{ TIccTestProfile }

constructor TIccTestProfile.Create(const DeviceClass, ColorSpace, Pcs: string);
begin
  inherited Create;
  FDeviceClass := DeviceClass;
  FColorSpace := ColorSpace;
  FPcs := Pcs;
  FModel := '';
  FMajorVersion := 4;
  FTagSignatures := TList<string>.Create;
  FTagContents := TList<TBytes>.Create;
end;

destructor TIccTestProfile.Destroy;
begin
  FTagContents.Free;
  FTagSignatures.Free;
  inherited Destroy;
end;

procedure TIccTestProfile.AddTag(const Signature: string; const Content: TBytes);
begin
  FTagSignatures.Add(Signature);
  FTagContents.Add(Content);
end;

function TIccTestProfile.Build: TBytes;
begin
  const TagTableSize = 4 + 12 * FTagSignatures.Count;
  var Offsets := TList<Integer>.Create;
  try
    var Position := 128 + TagTableSize;
    for var Content in FTagContents do
    begin
      Offsets.Add(Position);
      Position := Position + ((Length(Content) + 3) and not 3);
    end;

    const Writer = TIccTestWriter.Create;
    try
      Writer.U32(Position).Zeros(4).U32(Cardinal(FMajorVersion) shl 24).Signature(FDeviceClass).Signature(FColorSpace).Signature(FPcs);
      Writer.Zeros(12).Signature('acsp').Zeros(4).Zeros(4).Zeros(4);
      const ModelPadded = FModel + '    ';
      Writer.Signature(ModelPadded);
      Writer.Zeros(128 - Writer.Size);
      Writer.U32(FTagSignatures.Count);
      for var Index := 0 to FTagSignatures.Count - 1 do
      begin
        Writer.Signature(FTagSignatures[Index]).U32(Offsets[Index]).U32(Length(FTagContents[Index]));
      end;
      for var Content in FTagContents do
      begin
        Writer.Append(Content).Zeros(((Length(Content) + 3) and not 3) - Length(Content));
      end;
      Result := Writer.Bytes;
    finally
      Writer.Free;
    end;
  finally
    Offsets.Free;
  end;
end;

{ TIccTestTags }

class function TIccTestTags.CurveGamma(const Gamma: Double): TBytes;
begin
  const Writer = TIccTestWriter.Create;
  try
    Writer.Signature('curv').Zeros(4).U32(1).U16(Round(Gamma * 256.0));
    Result := Writer.Bytes;
  finally
    Writer.Free;
  end;
end;

class function TIccTestTags.CurveTable(const Entries: array of Word): TBytes;
begin
  const Writer = TIccTestWriter.Create;
  try
    Writer.Signature('curv').Zeros(4).U32(Length(Entries));
    for var Entry in Entries do
    begin
      Writer.U16(Entry);
    end;
    Result := Writer.Bytes;
  finally
    Writer.Free;
  end;
end;

class function TIccTestTags.Parametric(const FunctionType: Integer; const Parameters: array of Double): TBytes;
begin
  const Writer = TIccTestWriter.Create;
  try
    Writer.Signature('para').Zeros(4).U16(FunctionType).Zeros(2);
    for var Parameter in Parameters do
    begin
      Writer.S15Fixed16(Parameter);
    end;
    Result := Writer.Bytes;
  finally
    Writer.Free;
  end;
end;

class function TIccTestTags.Xyz(const X, Y, Z: Double): TBytes;
begin
  const Writer = TIccTestWriter.Create;
  try
    Writer.Signature('XYZ ').Zeros(4).S15Fixed16(X).S15Fixed16(Y).S15Fixed16(Z);
    Result := Writer.Bytes;
  finally
    Writer.Free;
  end;
end;

class function TIccTestTags.SrgbCurve: TBytes;
begin
  Result := Parametric(3, [2.4, 1.0 / 1.055, 0.055 / 1.055, 1.0 / 12.92, 0.04045]);
end;

class function TIccTestTags.Lut8(const InputChannels, OutputChannels, GridPoints: Integer; const InputTables, Clut, OutputTables: array of Byte): TBytes;
begin
  const Writer = TIccTestWriter.Create;
  try
    Writer.Signature('mft1').Zeros(4).U8(InputChannels).U8(OutputChannels).U8(GridPoints).U8(0);
    for var Index := 0 to 8 do
    begin
      Writer.S15Fixed16(IfThen(Index mod 4 = 0, 1.0, 0.0));
    end;
    for var Value in InputTables do
    begin
      Writer.U8(Value);
    end;
    for var Value in Clut do
    begin
      Writer.U8(Value);
    end;
    for var Value in OutputTables do
    begin
      Writer.U8(Value);
    end;
    Result := Writer.Bytes;
  finally
    Writer.Free;
  end;
end;

class function TIccTestTags.Lut16(const InputChannels, OutputChannels, GridPoints, InputEntries, OutputEntries: Integer;
                                  const InputTables, Clut, OutputTables: array of Word): TBytes;
begin
  const Writer = TIccTestWriter.Create;
  try
    Writer.Signature('mft2').Zeros(4).U8(InputChannels).U8(OutputChannels).U8(GridPoints).U8(0);
    for var Index := 0 to 8 do
    begin
      Writer.S15Fixed16(IfThen(Index mod 4 = 0, 1.0, 0.0));
    end;
    Writer.U16(InputEntries).U16(OutputEntries);
    for var Value in InputTables do
    begin
      Writer.U16(Value);
    end;
    for var Value in Clut do
    begin
      Writer.U16(Value);
    end;
    for var Value in OutputTables do
    begin
      Writer.U16(Value);
    end;
    Result := Writer.Bytes;
  finally
    Writer.Free;
  end;
end;

class function TIccTestTags.LutAToB(const InputChannels, OutputChannels: Integer; const BCurves: TArray<TBytes>; const Matrix: array of Double;
                                    const MCurves: TArray<TBytes>; const GridPoints: array of Byte; const ClutBytes: Integer; const Clut: array of Word;
                                    const ACurves: TArray<TBytes>): TBytes;
begin
  const Body = TIccTestWriter.Create;
  try
    // Offsets are from the start of the tag; the header of the tag takes 32 bytes
    var BOffset := 0;
    var MatrixOffset := 0;
    var MOffset := 0;
    var ClutOffset := 0;
    var AOffset := 0;

    if Length(BCurves) > 0 then
    begin
      BOffset := 32 + Body.Size;
      for var Curve in BCurves do
      begin
        Body.Append(Curve).Zeros(((Length(Curve) + 3) and not 3) - Length(Curve));
      end;
    end;
    if Length(Matrix) > 0 then
    begin
      MatrixOffset := 32 + Body.Size;
      for var Value in Matrix do
      begin
        Body.S15Fixed16(Value);
      end;
    end;
    if Length(MCurves) > 0 then
    begin
      MOffset := 32 + Body.Size;
      for var Curve in MCurves do
      begin
        Body.Append(Curve).Zeros(((Length(Curve) + 3) and not 3) - Length(Curve));
      end;
    end;
    if Length(GridPoints) > 0 then
    begin
      ClutOffset := 32 + Body.Size;
      for var Index := 0 to 15 do
      begin
        if Index < Length(GridPoints) then
        begin
          Body.U8(GridPoints[Index]);
        end
        else
        begin
          Body.U8(0);
        end;
      end;
      Body.U8(ClutBytes).Zeros(3);
      for var Value in Clut do
      begin
        if ClutBytes = 1 then
        begin
          Body.U8(Value);
        end
        else
        begin
          Body.U16(Value);
        end;
      end;
      Body.Zeros(((Body.Size + 3) and not 3) - Body.Size);
    end;
    if Length(ACurves) > 0 then
    begin
      AOffset := 32 + Body.Size;
      for var Curve in ACurves do
      begin
        Body.Append(Curve).Zeros(((Length(Curve) + 3) and not 3) - Length(Curve));
      end;
    end;

    const Writer = TIccTestWriter.Create;
    try
      Writer.Signature('mAB ').Zeros(4).U8(InputChannels).U8(OutputChannels).Zeros(2);
      Writer.U32(BOffset).U32(MatrixOffset).U32(MOffset).U32(ClutOffset).U32(AOffset);
      Writer.Append(Body.Bytes);
      Result := Writer.Bytes;
    finally
      Writer.Free;
    end;
  finally
    Body.Free;
  end;
end;

{ TIccTestFiles }

class function TIccTestFiles.IccFolder: string;
begin
  var Current := TPath.GetDirectoryName(ParamStr(0));
  while Current <> '' do
  begin
    for var Candidate in [TPath.Combine(Current, 'icc'), TPath.Combine(TPath.Combine(Current, 'tests'), 'icc')] do
    begin
      if TFile.Exists(TPath.Combine(Candidate, 'sRGB.icc')) then
      begin
        Exit(Candidate);
      end;
    end;

    const Parent = TPath.GetDirectoryName(Current);
    if Parent = Current then
    begin
      Break;
    end;
    Current := Parent;
  end;
  raise EFileNotFoundException.Create('The folder tests/icc was not found');
end;

class function TIccTestFiles.ReferenceFolder: string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.GetDirectoryName(IccFolder), 'reference'), 'color');
  if not TDirectory.Exists(Result) then
  begin
    raise EFileNotFoundException.Create('The folder tests/reference/color was not found');
  end;
end;

class function TIccTestFiles.ReadProfile(const FileName: string): TBytes;
begin
  Result := TFile.ReadAllBytes(TPath.Combine(IccFolder, FileName));
end;

end.
