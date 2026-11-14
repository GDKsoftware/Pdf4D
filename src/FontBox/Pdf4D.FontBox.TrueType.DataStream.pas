// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/TTFDataStream.java (3.0.8)
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/RandomAccessReadDataStream.java (3.0.8)
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/RandomAccessReadUnbufferedDataStream.java (3.0.8)
unit Pdf4D.FontBox.TrueType.DataStream;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.IO.RandomAccessRead;

type
  {$SCOPEDENUMS ON}
  TTTFStringEncoding = (Latin1, Utf16BE);
  {$SCOPEDENUMS OFF}

  // Font data is big-endian. A typed read past the end of the data raises EPdfParseException (Read and ReadInto return -1, as in
  // PDFBox), and a read never allocates more than the data still holds.
  // A stream has one read position, so it is not thread-safe while it is read through Seek and the Read methods. ReadRange and
  // OriginalData of the memory stream only read the immutable data and may be called from several threads.
  TTTFDataStream = class abstract
  private
    function Remaining: Int64;
    procedure GuardAvailable(const Count: Int64);

  public
    // The UTF-16 text of the bytes from Offset on. A last byte that is no whole unit becomes U+FFFD, as in Java (the RTL raises
    // EEncodingError for such a byte).
    class function DecodeUtf16(const Bytes: TBytes; const Offset: Integer; const IsBigEndian: Boolean): string; static;

    // The next byte, or -1 at the end of the data
    function Read: Integer; virtual; abstract;
    // Number of bytes read, or -1 at the end of the data
    function ReadInto(const Buffer: TBytes; const Offset, Count: Integer): Integer; virtual; abstract;
    procedure Seek(const Position: Int64); virtual; abstract;
    function CurrentPosition: Int64; virtual; abstract;
    function OriginalDataSize: Int64; virtual; abstract;
    function OriginalData: TBytes; virtual; abstract;
    // A copy of the bytes from Offset on. Does not change the read position of a memory stream.
    function ReadRange(const Offset: Int64; const Count: Integer): TBytes; virtual; abstract;

    function ReadBytes(const Count: Integer): TBytes;
    function ReadUnsignedByte: Integer;
    function ReadSignedByte: Integer;
    function ReadUnsignedShort: Integer;
    function ReadSignedShort: SmallInt;
    function ReadUnsignedInt: Int64;
    function ReadLong: Int64;
    function Read32Fixed: Single;
    function ReadString(const Length: Integer; const Encoding: TTTFStringEncoding): string;
    function ReadTag: string;
    function ReadLongDateTime: TDateTime;
    function ReadUnsignedShortArray(const Length: Integer): TArray<Integer>;
  end;

  TTTFMemoryDataStream = class(TTTFDataStream)
  private
    FData: TBytes;
    FPosition: Integer;

  public
    constructor Create(const Data: TBytes);

    function Read: Integer; override;
    function ReadInto(const Buffer: TBytes; const Offset, Count: Integer): Integer; override;
    procedure Seek(const Position: Int64); override;
    function CurrentPosition: Int64; override;
    function OriginalDataSize: Int64; override;
    function OriginalData: TBytes; override;
    function ReadRange(const Offset: Int64; const Count: Integer): TBytes; override;
  end;

  // Reads from a source without copying it. The source belongs to the caller and has to outlive the stream.
  // The source has one position that ReadRange and OriginalData move and restore, so a font on this stream is single-threaded.
  TTTFRandomAccessDataStream = class(TTTFDataStream)
  private
    FSource: TRandomAccessRead;
    FSize: Int64;

  public
    constructor Create(const Source: TRandomAccessRead);

    function Read: Integer; override;
    function ReadInto(const Buffer: TBytes; const Offset, Count: Integer): Integer; override;
    procedure Seek(const Position: Int64); override;
    function CurrentPosition: Int64; override;
    function OriginalDataSize: Int64; override;
    function OriginalData: TBytes; override;
    function ReadRange(const Offset: Int64; const Count: Integer): TBytes; override;
  end;

implementation

uses
  System.Math,
  Pdf4D.Common.Defines;

const
  SecondsPerDay = 86400.0;
  FixedPointDivisor = 65536;
  ReplacementCharacter = #$FFFD;
  // PDFBox limit for the size of an array in RandomAccessReadDataStream
  MaximumDataSize = Int64(MaxInt) - 8;

{ TTTFDataStream }

function TTTFDataStream.Remaining: Int64;
begin
  Result := Max(OriginalDataSize - CurrentPosition, 0);
end;

procedure TTTFDataStream.GuardAvailable(const Count: Int64);
begin
  const IsBeyondEnd = ((Count < 0) or (Count > Remaining));
  if IsBeyondEnd then
  begin
    raise EPdfParseException.CreateFmt('Unexpected end of TrueType data: %d bytes requested at position %d of %d',
                                       [Count, CurrentPosition, OriginalDataSize]);
  end;
end;

function TTTFDataStream.ReadBytes(const Count: Integer): TBytes;
begin
  GuardAvailable(Count);

  SetLength(Result, Count);
  var TotalRead := 0;
  while TotalRead < Count do
  begin
    const AmountRead = ReadInto(Result, TotalRead, Count - TotalRead);
    if AmountRead <= 0 then
    begin
      raise EPdfParseException.Create('Unexpected end of TrueType stream reached');
    end;
    Inc(TotalRead, AmountRead);
  end;
end;

function TTTFDataStream.ReadUnsignedByte: Integer;
begin
  Result := Read;
  if Result < 0 then
  begin
    raise EPdfParseException.CreateFmt('Unexpected end of TrueType data at position %d', [CurrentPosition]);
  end;
end;

function TTTFDataStream.ReadSignedByte: Integer;
begin
  Result := ReadUnsignedByte;
  if Result > 127 then
  begin
    Dec(Result, 256);
  end;
end;

function TTTFDataStream.ReadUnsignedShort: Integer;
begin
  GuardAvailable(2);

  const HighByte = ReadUnsignedByte;
  const LowByte = ReadUnsignedByte;
  Result := (HighByte shl 8) or LowByte;
end;

function TTTFDataStream.ReadSignedShort: SmallInt;
begin
  Result := SmallInt(Word(ReadUnsignedShort));
end;

function TTTFDataStream.ReadUnsignedInt: Int64;
begin
  GuardAvailable(4);

  const Byte1 = ReadUnsignedByte;
  const Byte2 = ReadUnsignedByte;
  const Byte3 = ReadUnsignedByte;
  const Byte4 = ReadUnsignedByte;
  Result := (Int64(Byte1) shl 24) or (Int64(Byte2) shl 16) or (Int64(Byte3) shl 8) or Int64(Byte4);
end;

function TTTFDataStream.ReadLong: Int64;
begin
  GuardAvailable(8);

  const HighPart = ReadUnsignedInt;
  const LowPart = ReadUnsignedInt;
  Result := Int64((UInt64(HighPart) shl 32) or UInt64(LowPart));
end;

function TTTFDataStream.Read32Fixed: Single;
begin
  const WholePart = ReadSignedShort;
  const FractionPart = ReadUnsignedShort;
  Result := WholePart;
  Result := Result + (FractionPart / FixedPointDivisor);
end;

class function TTTFDataStream.DecodeUtf16(const Bytes: TBytes; const Offset: Integer; const IsBigEndian: Boolean): string;
begin
  Result := '';
  const Count = Length(Bytes) - Offset;
  if Count <= 0 then
  begin
    Exit;
  end;

  const WholeUnitsSize = Count and not 1;
  if WholeUnitsSize > 0 then
  begin
    if IsBigEndian then
    begin
      Result := TEncoding.BigEndianUnicode.GetString(Bytes, Offset, WholeUnitsSize);
    end
    else
    begin
      Result := TEncoding.Unicode.GetString(Bytes, Offset, WholeUnitsSize);
    end;
  end;
  if Odd(Count) then
  begin
    Result := Result + ReplacementCharacter;
  end;
end;

function TTTFDataStream.ReadString(const Length: Integer; const Encoding: TTTFStringEncoding): string;
begin
  const Bytes = ReadBytes(Length);
  case Encoding of
    TTTFStringEncoding.Latin1:
    begin
      SetLength(Result, Length);
      for var Index := 0 to Length - 1 do
      begin
        Result[Index + 1] := Char(Bytes[Index]);
      end;
    end;
    TTTFStringEncoding.Utf16BE:
    begin
      Result := DecodeUtf16(Bytes, 0, True);
    end;
  else
    raise ENotSupportedException.CreateFmt('Unsupported string encoding: %d', [Ord(Encoding)]);
  end;
end;

function TTTFDataStream.ReadTag: string;
begin
  Result := ReadString(4, TTTFStringEncoding.Latin1);
end;

function TTTFDataStream.ReadLongDateTime: TDateTime;
begin
  const SecondsSince1904 = ReadLong;
  Result := EncodeDate(1904, 1, 1) + (SecondsSince1904 / SecondsPerDay);
end;

function TTTFDataStream.ReadUnsignedShortArray(const Length: Integer): TArray<Integer>;
begin
  const IsBeyondEnd = ((Length < 0) or (Int64(Length) * 2 > Remaining));
  if IsBeyondEnd then
  begin
    raise EPdfParseException.CreateFmt('Unexpected end of TrueType data: %d shorts requested at position %d of %d',
                                       [Length, CurrentPosition, OriginalDataSize]);
  end;

  SetLength(Result, Length);
  for var Index := 0 to Length - 1 do
  begin
    Result[Index] := ReadUnsignedShort;
  end;
end;

{ TTTFMemoryDataStream }

constructor TTTFMemoryDataStream.Create(const Data: TBytes);
begin
  inherited Create;
  FData := Data;
end;

function TTTFMemoryDataStream.Read: Integer;
begin
  if FPosition >= System.Length(FData) then
  begin
    Exit(-1);
  end;

  Result := FData[FPosition];
  Inc(FPosition);
end;

function TTTFMemoryDataStream.ReadInto(const Buffer: TBytes; const Offset, Count: Integer): Integer;
begin
  const IsInvalidRange = ((Offset < 0) or (Count < 0) or (Offset > System.Length(Buffer) - Count));
  if IsInvalidRange then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('Invalid buffer range: offset %d, count %d', [Offset, Count]);
  end;

  if FPosition >= System.Length(FData) then
  begin
    Exit(-1);
  end;

  Result := Min(System.Length(FData) - FPosition, Count);
  if Result > 0 then
  begin
    Move(FData[FPosition], Buffer[Offset], Result);
    Inc(FPosition, Result);
  end;
end;

procedure TTTFMemoryDataStream.Seek(const Position: Int64);
begin
  if Position < 0 then
  begin
    raise EPdfParseException.CreateFmt('Invalid position %d', [Position]);
  end;

  FPosition := Integer(Min(Position, Int64(System.Length(FData))));
end;

function TTTFMemoryDataStream.CurrentPosition: Int64;
begin
  Result := FPosition;
end;

function TTTFMemoryDataStream.OriginalDataSize: Int64;
begin
  Result := System.Length(FData);
end;

function TTTFMemoryDataStream.OriginalData: TBytes;
begin
  Result := FData;
end;

function TTTFMemoryDataStream.ReadRange(const Offset: Int64; const Count: Integer): TBytes;
begin
  const IsOutside = ((Offset < 0) or (Count < 0) or (Offset > System.Length(FData)) or (Count > System.Length(FData) - Offset));
  if IsOutside then
  begin
    raise EPdfParseException.CreateFmt('Unexpected end of TrueType data: %d bytes requested at offset %d of %d', [Count, Offset, System.Length(FData)]);
  end;

  Result := Copy(FData, Integer(Offset), Count);
end;

{ TTTFRandomAccessDataStream }

constructor TTTFRandomAccessDataStream.Create(const Source: TRandomAccessRead);
begin
  inherited Create;
  FSource := Source;
  FSize := Source.Length;
end;

function TTTFRandomAccessDataStream.Read: Integer;
begin
  Result := FSource.Read;
end;

function TTTFRandomAccessDataStream.ReadInto(const Buffer: TBytes; const Offset, Count: Integer): Integer;
begin
  Result := FSource.Read(Buffer, Offset, Count);
end;

procedure TTTFRandomAccessDataStream.Seek(const Position: Int64);
begin
  FSource.Seek(Position);
end;

function TTTFRandomAccessDataStream.CurrentPosition: Int64;
begin
  Result := FSource.GetPosition;
end;

function TTTFRandomAccessDataStream.OriginalDataSize: Int64;
begin
  Result := FSize;
end;

function TTTFRandomAccessDataStream.ReadRange(const Offset: Int64; const Count: Integer): TBytes;
begin
  const SavedPosition = FSource.GetPosition;
  try
    Seek(Offset);
    Result := ReadBytes(Count);
  finally
    FSource.Seek(SavedPosition);
  end;
end;

function TTTFRandomAccessDataStream.OriginalData: TBytes;
begin
  if FSize > MaximumDataSize then
  begin
    raise EPdfParseException.CreateFmt('Stream is too long, size: %d', [FSize]);
  end;

  const SavedPosition = FSource.GetPosition;
  try
    FSource.Seek(0);
    Result := FSource.ReadFully(Integer(FSize));
  finally
    FSource.Seek(SavedPosition);
  end;
end;

end.
