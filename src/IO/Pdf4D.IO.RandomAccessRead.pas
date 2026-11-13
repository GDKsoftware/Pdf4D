// Port of: pdfbox-io/src/main/java/org/apache/pdfbox/io/RandomAccessRead.java (3.0.8)
// Port of: pdfbox-io/src/main/java/org/apache/pdfbox/io/RandomAccessReadBuffer.java (3.0.8)
// Port of: pdfbox-io/src/main/java/org/apache/pdfbox/io/RandomAccessReadBufferedFile.java (3.0.8)
unit Pdf4D.IO.RandomAccessRead;

interface

uses
  System.SysUtils,
  System.Classes;

type
  TRandomAccessRead = class
  private
    const BufferSize = 64 * 1024;

  private
    FSource: TStream;
    FOwnsSource: Boolean;
    FRangeStart: Int64;
    FRangeLength: Int64;
    FPosition: Int64;
    FBuffer: TBytes;
    FBufferStart: Int64;
    FBufferLength: Integer;

    constructor CreateRange(const Source: TStream; const RangeStart, RangeLength: Int64);

    function IsBuffered(const Position: Int64): Boolean;
    procedure FillBuffer;
    procedure GuardBufferRange(const Buffer: TBytes; const Offset, Count: Integer);

  public
    class function FromBytes(const Data: TBytes): TRandomAccessRead;
    class function FromFile(const FileName: string): TRandomAccessRead;

    constructor Create(const Source: TStream; const OwnsSource: Boolean);
    destructor Destroy; override;

    function Read: Integer; overload;
    function Read(var Buffer: TBytes; const Offset, Count: Integer): Integer; overload;
    function Peek: Integer;
    procedure Rewind(const Bytes: Integer);
    procedure Seek(const Position: Int64);
    function GetPosition: Int64;
    function Length: Int64;
    function IsEOF: Boolean;
    function ReadFully(const Count: Integer): TBytes;

    // The view reads from the same source and does not own it: free the view before this reader.
    function CreateView(const Start, Count: Int64): TRandomAccessRead;
  end;

implementation

uses
  System.Math,
  Pdf4D.Common.Defines;

{ TRandomAccessRead }

class function TRandomAccessRead.FromBytes(const Data: TBytes): TRandomAccessRead;
begin
  Result := TRandomAccessRead.Create(TBytesStream.Create(Data), True);
end;

class function TRandomAccessRead.FromFile(const FileName: string): TRandomAccessRead;
begin
  Result := TRandomAccessRead.Create(TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite), True);
end;

constructor TRandomAccessRead.Create(const Source: TStream; const OwnsSource: Boolean);
begin
  CreateRange(Source, 0, Source.Size);
  FOwnsSource := OwnsSource;
end;

constructor TRandomAccessRead.CreateRange(const Source: TStream; const RangeStart, RangeLength: Int64);
begin
  inherited Create;
  FSource := Source;
  FOwnsSource := False;
  FRangeStart := RangeStart;
  FRangeLength := RangeLength;
  FPosition := 0;
  SetLength(FBuffer, BufferSize);
  FBufferStart := 0;
  FBufferLength := 0;
end;

destructor TRandomAccessRead.Destroy;
begin
  if FOwnsSource then
  begin
    FSource.Free;
  end;
  inherited;
end;

function TRandomAccessRead.Read: Integer;
begin
  if IsEOF then
  begin
    Exit(-1);
  end;

  if not IsBuffered(FPosition) then
  begin
    FillBuffer;
  end;

  Result := FBuffer[FPosition - FBufferStart];
  Inc(FPosition);
end;

function TRandomAccessRead.Read(var Buffer: TBytes; const Offset, Count: Integer): Integer;
begin
  GuardBufferRange(Buffer, Offset, Count);

  if Count = 0 then
  begin
    Exit(0);
  end;

  if IsEOF then
  begin
    Exit(-1);
  end;

  Result := 0;
  while (Result < Count) and not IsEOF do
  begin
    if not IsBuffered(FPosition) then
    begin
      FillBuffer;
    end;

    const BufferOffset = Integer(FPosition - FBufferStart);
    const ChunkSize = Min(Count - Result, FBufferLength - BufferOffset);
    Move(FBuffer[BufferOffset], Buffer[Offset + Result], ChunkSize);
    Inc(FPosition, ChunkSize);
    Inc(Result, ChunkSize);
  end;
end;

function TRandomAccessRead.Peek: Integer;
begin
  Result := Read;
  if Result >= 0 then
  begin
    Rewind(1);
  end;
end;

procedure TRandomAccessRead.Rewind(const Bytes: Integer);
begin
  const RewindsBeforeStart = ((Bytes < 0) or (Bytes > FPosition));
  if RewindsBeforeStart then
  begin
    raise EPdfParseException.CreateFmt('Cannot rewind %d bytes from position %d', [Bytes, FPosition]);
  end;

  Dec(FPosition, Bytes);
end;

procedure TRandomAccessRead.Seek(const Position: Int64);
begin
  if Position < 0 then
  begin
    raise EPdfParseException.CreateFmt('Invalid negative seek position %d', [Position]);
  end;

  FPosition := Position;
end;

function TRandomAccessRead.GetPosition: Int64;
begin
  Result := FPosition;
end;

function TRandomAccessRead.Length: Int64;
begin
  Result := FRangeLength;
end;

function TRandomAccessRead.IsEOF: Boolean;
begin
  Result := (FPosition >= FRangeLength);
end;

function TRandomAccessRead.ReadFully(const Count: Integer): TBytes;
begin
  const IsInvalidCount = (Count < 0);
  if IsInvalidCount then
  begin
    raise EPdfParseException.CreateFmt('Invalid byte count %d', [Count]);
  end;

  const Available = Max(FRangeLength - FPosition, 0);
  if Count > Available then
  begin
    raise EPdfParseException.CreateFmt('Unexpected end of data: %d bytes requested at position %d, %d available',
                                       [Count, FPosition, Available]);
  end;

  SetLength(Result, Count);
  Read(Result, 0, Count);
end;

function TRandomAccessRead.CreateView(const Start, Count: Int64): TRandomAccessRead;
begin
  const IsOutsideRange = ((Start < 0) or (Count < 0) or (Start + Count > FRangeLength));
  if IsOutsideRange then
  begin
    raise EPdfParseException.CreateFmt('View of %d bytes at %d lies outside the data of %d bytes',
                                       [Count, Start, FRangeLength]);
  end;

  Result := TRandomAccessRead.CreateRange(FSource, FRangeStart + Start, Count);
end;

function TRandomAccessRead.IsBuffered(const Position: Int64): Boolean;
begin
  Result := ((Position >= FBufferStart) and (Position < FBufferStart + FBufferLength));
end;

procedure TRandomAccessRead.FillBuffer;
begin
  const WantedCount = Integer(Min(Int64(BufferSize), FRangeLength - FPosition));

  FSource.Position := FRangeStart + FPosition;
  const ReadCount = FSource.Read(FBuffer, 0, WantedCount);
  if ReadCount <= 0 then
  begin
    raise EPdfParseException.CreateFmt('Source ended unexpectedly at position %d', [FRangeStart + FPosition]);
  end;

  FBufferStart := FPosition;
  FBufferLength := ReadCount;
end;

procedure TRandomAccessRead.GuardBufferRange(const Buffer: TBytes; const Offset, Count: Integer);
begin
  const IsOutsideBuffer = ((Offset < 0) or (Count < 0) or (Offset + Count > System.Length(Buffer)));
  if IsOutsideBuffer then
  begin
    raise EPdfParseException.CreateFmt('Range of %d bytes at offset %d lies outside a buffer of %d bytes',
                                       [Count, Offset, System.Length(Buffer)]);
  end;
end;

end.
