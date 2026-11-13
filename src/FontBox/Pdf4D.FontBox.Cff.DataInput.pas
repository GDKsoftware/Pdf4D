// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/cff/DataInput.java and DataInputByteArray.java (3.0.8)
unit Pdf4D.FontBox.Cff.DataInput;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils;

type
  // Reads CFF data, which is big-endian. Every read past the end of the data raises EPdfParseException, and a read never
  // allocates more than the data still holds.
  TCFFDataInput = class
  private
    FData: TBytes;
    FPosition: Integer;

    procedure GuardAvailable(const Count: Integer);

  public
    constructor Create(const Data: TBytes);

    function HasRemaining: Boolean;
    function GetPosition: Integer;
    // The position must lie inside the data
    procedure SetPosition(const Position: Integer);
    function GetLength: Integer;

    // The next byte as a signed value (-128 to 127)
    function ReadByte: ShortInt;
    function ReadUnsignedByte: Integer;
    function PeekUnsignedByte(const Offset: Integer): Integer;
    function ReadShort: SmallInt;
    function ReadUnsignedShort: Integer;
    function ReadInt: Integer;
    function ReadBytes(const Count: Integer): TBytes;
    // An offset of OffSize bytes (1 to 4) as an unsigned number
    function ReadOffset(const OffSize: Integer): Int64;
  end;

implementation

uses
  Pdf4D.Common.Defines;

{ TCFFDataInput }

constructor TCFFDataInput.Create(const Data: TBytes);
begin
  inherited Create;
  FData := Data;
end;

procedure TCFFDataInput.GuardAvailable(const Count: Integer);
begin
  if Count > System.Length(FData) - FPosition then
  begin
    raise EPdfParseException.Create('End of CFF data reached');
  end;
end;

function TCFFDataInput.HasRemaining: Boolean;
begin
  Result := FPosition < System.Length(FData);
end;

function TCFFDataInput.GetPosition: Integer;
begin
  Result := FPosition;
end;

procedure TCFFDataInput.SetPosition(const Position: Integer);
begin
  if Position < 0 then
  begin
    raise EPdfParseException.Create('The CFF position is negative');
  end;
  if Position >= System.Length(FData) then
  begin
    raise EPdfParseException.CreateFmt('The CFF position %d is out of range (length %d)', [Position, System.Length(FData)]);
  end;
  FPosition := Position;
end;

function TCFFDataInput.GetLength: Integer;
begin
  Result := System.Length(FData);
end;

function TCFFDataInput.ReadByte: ShortInt;
begin
  Result := ShortInt(ReadUnsignedByte);
end;

function TCFFDataInput.ReadUnsignedByte: Integer;
begin
  GuardAvailable(1);
  Result := FData[FPosition];
  Inc(FPosition);
end;

function TCFFDataInput.PeekUnsignedByte(const Offset: Integer): Integer;
begin
  if Offset < 0 then
  begin
    raise EPdfParseException.Create('The CFF peek offset is negative');
  end;
  if Offset >= System.Length(FData) - FPosition then
  begin
    raise EPdfParseException.Create('The CFF peek offset is out of range');
  end;
  Result := FData[FPosition + Offset];
end;

function TCFFDataInput.ReadShort: SmallInt;
begin
  Result := SmallInt(ReadUnsignedShort);
end;

function TCFFDataInput.ReadUnsignedShort: Integer;
begin
  const HighByte = ReadUnsignedByte;
  const LowByte = ReadUnsignedByte;
  Result := (HighByte shl 8) or LowByte;
end;

function TCFFDataInput.ReadInt: Integer;
begin
  const HighWord = UInt32(ReadUnsignedShort);
  const LowWord = UInt32(ReadUnsignedShort);
  Result := Integer((HighWord shl 16) or LowWord);
end;

function TCFFDataInput.ReadBytes(const Count: Integer): TBytes;
begin
  if Count < 0 then
  begin
    raise EPdfParseException.Create('The CFF length is negative');
  end;
  GuardAvailable(Count);
  SetLength(Result, Count);
  if Count > 0 then
  begin
    Move(FData[FPosition], Result[0], Count);
  end;
  Inc(FPosition, Count);
end;

function TCFFDataInput.ReadOffset(const OffSize: Integer): Int64;
begin
  Result := 0;
  for var Index := 1 to OffSize do
  begin
    Result := (Result shl 8) or ReadUnsignedByte;
  end;
end;

end.
