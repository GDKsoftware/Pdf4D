// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Filter.ByteReader;

interface

uses
  System.SysUtils,
  System.Classes;

type
  // Reads a stream byte by byte through a buffer. The source is not owned.
  TByteReader = class
  private
    const BufferSize = 64 * 1024;

  private
    FSource: TStream;
    FBuffer: TBytes;
    FPosition: Integer;
    FCount: Integer;

    function Refill: Boolean;

  public
    constructor Create(const Source: TStream);

    // The next byte, or -1 at the end of the source
    function ReadByte: Integer;

    // Reads up to Count bytes into the start of Buffer and gives the number read: 0 at the end of the source
    function ReadBytes(var Buffer: TBytes; const Count: Integer): Integer;
  end;

implementation

{ TByteReader }

constructor TByteReader.Create(const Source: TStream);
begin
  inherited Create;
  FSource := Source;
  SetLength(FBuffer, BufferSize);
end;

function TByteReader.ReadByte: Integer;
begin
  if (FPosition >= FCount) and not Refill then
  begin
    Exit(-1);
  end;

  Result := FBuffer[FPosition];
  Inc(FPosition);
end;

function TByteReader.ReadBytes(var Buffer: TBytes; const Count: Integer): Integer;
begin
  if (FPosition >= FCount) and not Refill then
  begin
    Exit(0);
  end;

  Result := Count;
  if Result > FCount - FPosition then
  begin
    Result := FCount - FPosition;
  end;

  Move(FBuffer[FPosition], Buffer[0], Result);
  Inc(FPosition, Result);
end;

function TByteReader.Refill: Boolean;
begin
  FPosition := 0;
  FCount := FSource.Read(FBuffer[0], BufferSize);
  Result := (FCount > 0);
end;

end.
