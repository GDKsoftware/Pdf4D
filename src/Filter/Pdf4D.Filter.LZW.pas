// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/filter/LZWFilter.java (3.0.8)
unit Pdf4D.Filter.LZW;

interface

uses
  System.SysUtils,
  System.Classes,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Filter.Base,
  Pdf4D.Filter.ByteReader;

type
  TLZWFilter = class(TPdfFilter)
  private
    const ClearTable = 256;
    const EndOfData = 257;
    const FirstFreeCode = 258;
    // Codes have at most 12 bits. PDFBox lets the table grow past this, but those entries can never be used.
    const MaxTableSize = 4096;

  private
    class function CalculateChunk(const TableSize: Integer; const EarlyChange: Boolean): Integer; static;
    class procedure ResetTable(var Table: TArray<TBytes>; out TableSize: Integer); static;

    // Gives False when the data ends before a complete code
    class function TryReadBits(const Reader: TByteReader; var BitBuffer, BitCount: Integer; const Count: Integer; out Code: Integer): Boolean; static;

    procedure DoDecode(const Input, Output: TStream; const EarlyChange: Boolean);

  public
    procedure Decode(const Input, Output: TStream; const Parameters: TCosDictionary; const Index: Integer); override;
  end;

implementation

uses
  Pdf4D.Cos.Names,
  Pdf4D.Filter.Predictor;

{ TLZWFilter }

procedure TLZWFilter.Decode(const Input, Output: TStream; const Parameters: TCosDictionary; const Index: Integer);
begin
  const DecodeParams = GetDecodeParams(Parameters, Index);
  const EarlyChange = (DecodeParams.GetInt(TCosNames.EarlyChange, 1) <> 0);
  const PredictorStream = TPredictor.CreateDecodingStream(Output, DecodeParams, Log);
  if not Assigned(PredictorStream) then
  begin
    DoDecode(Input, Output, EarlyChange);
    Exit;
  end;

  try
    DoDecode(Input, PredictorStream, EarlyChange);
    PredictorStream.Finish;
  finally
    PredictorStream.Free;
  end;
end;

procedure TLZWFilter.DoDecode(const Input, Output: TStream; const EarlyChange: Boolean);
begin
  var Table: TArray<TBytes>;
  var TableSize: Integer;
  ResetTable(Table, TableSize);
  var Chunk := 9;
  var Previous: TBytes := nil;
  var HasPrevious := False;
  var BitBuffer := 0;
  var BitCount := 0;

  const Reader = TByteReader.Create(Input);
  try
    var Code: Integer;
    while TryReadBits(Reader, BitBuffer, BitCount, Chunk, Code) do
    begin
      if Code = EndOfData then
      begin
        Exit;
      end;

      if Code = ClearTable then
      begin
        Chunk := 9;
        ResetTable(Table, TableSize);
        HasPrevious := False;
        Continue;
      end;

      var Current: TBytes;
      if Code < TableSize then
      begin
        Current := Table[Code];
        Output.WriteBuffer(Current[0], Length(Current));
        if HasPrevious and (TableSize < MaxTableSize) then
        begin
          Table[TableSize] := Previous + [Current[0]];
          Inc(TableSize);
        end;
      end
      else if (Code = TableSize) and HasPrevious then
      begin
        // The code of the entry that is being made right now
        Current := Previous + [Previous[0]];
        Output.WriteBuffer(Current[0], Length(Current));
        if TableSize < MaxTableSize then
        begin
          Table[TableSize] := Current;
          Inc(TableSize);
        end;
      end
      else
      begin
        if Assigned(Log) then
        begin
          Log.Warning('Premature EOF in LZW stream, EOD code missing: invalid LZW code %d', [Code]);
        end;
        Exit;
      end;

      Previous := Current;
      HasPrevious := True;
      Chunk := CalculateChunk(TableSize, EarlyChange);
    end;

    if Assigned(Log) then
    begin
      Log.Warning('Premature EOF in LZW stream, EOD code missing');
    end;
  finally
    Reader.Free;
  end;
end;

class function TLZWFilter.TryReadBits(const Reader: TByteReader; var BitBuffer, BitCount: Integer; const Count: Integer; out Code: Integer): Boolean;
begin
  Code := 0;
  while BitCount < Count do
  begin
    const Next = Reader.ReadByte;
    if Next = -1 then
    begin
      Exit(False);
    end;

    BitBuffer := (BitBuffer shl 8) or Next;
    Inc(BitCount, 8);
  end;

  Dec(BitCount, Count);
  Code := (BitBuffer shr BitCount) and ((1 shl Count) - 1);
  // Only the bits not used yet stay in the buffer
  BitBuffer := BitBuffer and ((1 shl BitCount) - 1);
  Result := True;
end;

class function TLZWFilter.CalculateChunk(const TableSize: Integer; const EarlyChange: Boolean): Integer;
begin
  var Size := TableSize;
  if EarlyChange then
  begin
    Inc(Size);
  end;

  if Size >= 2048 then
  begin
    Result := 12;
  end
  else if Size >= 1024 then
  begin
    Result := 11;
  end
  else if Size >= 512 then
  begin
    Result := 10;
  end
  else
  begin
    Result := 9;
  end;
end;

class procedure TLZWFilter.ResetTable(var Table: TArray<TBytes>; out TableSize: Integer);
begin
  if Length(Table) = 0 then
  begin
    SetLength(Table, MaxTableSize);
    for var Value := 0 to 255 do
    begin
      Table[Value] := [Byte(Value)];
    end;
  end;

  TableSize := FirstFreeCode;
end;

end.
