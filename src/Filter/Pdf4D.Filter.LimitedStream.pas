// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Filter.LimitedStream;

interface

uses
  System.SysUtils,
  System.Classes;

type
  // A write-only stream in front of another stream (not owned). Stops a decoder that produces more than the
  // limit, so a small hostile stream cannot fill the memory.
  TLimitedStream = class(TStream)
  private
    FTarget: TStream;
    FLimit: Int64;
    FWritten: Int64;

  public
    constructor Create(const Target: TStream; const Limit: Int64);

    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;

    property Written: Int64 read FWritten;
    property Limit: Int64 read FLimit;
  end;

implementation

uses
  Pdf4D.Common.Defines;

{ TLimitedStream }

constructor TLimitedStream.Create(const Target: TStream; const Limit: Int64);
begin
  inherited Create;
  FTarget := Target;
  FLimit := Limit;
end;

function TLimitedStream.Read(var Buffer; Count: Longint): Longint;
begin
  raise ENotSupportedException.Create('A limited stream is write-only');
end;

function TLimitedStream.Write(const Buffer; Count: Longint): Longint;
begin
  // Written never exceeds the limit, so the subtraction cannot overflow
  if Count > FLimit - FWritten then
  begin
    raise EPdfLimitExceededException.CreateFmt('Decoded data exceeds the limit of %d bytes', [FLimit]);
  end;

  FTarget.WriteBuffer(Buffer, Count);
  Inc(FWritten, Count);
  Result := Count;
end;

function TLimitedStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  // TStream.Size and Position ask for the current position through Seek
  if (Offset = 0) and (Origin = TSeekOrigin.soCurrent) then
  begin
    Exit(FWritten);
  end;

  raise ENotSupportedException.Create('A limited stream cannot seek');
end;

end.
