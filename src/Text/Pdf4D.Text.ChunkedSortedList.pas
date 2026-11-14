// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Replaces: the java.util.TreeMap and java.util.TreeSet that PDFTextStripper uses to find overlapping characters
unit Pdf4D.Text.ChunkedSortedList;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults;

type
  // A place in a TChunkedSortedList. It is valid until the next insert.
  TChunkCursor = record
    Chunk: Integer;
    Offset: Integer;
  end;

  // A sorted sequence that inserts in O(log n) comparisons plus the move of at most one chunk, where a plain sorted array
  // moves all items behind the new one. The items are kept in chunks of at most MaxChunkSize.
  TChunkedSortedList<T> = class
  private
    const MaxChunkSize = 128;
    const FirstChunkCapacity = 4;

  private type
    TChunk = class
    public
      Items: TArray<T>;
      Count: Integer;
    end;

  private
    FChunks: TObjectList<TChunk>;
    FComparison: TComparison<T>;
    FCount: Integer;

    function FindChunk(const Value: T): Integer;
    function FindOffset(const Chunk: TChunk; const Value: T): Integer;
    procedure SplitChunk(const ChunkIndex: Integer);
    procedure EnsureFirstChunk;
    function NormalizeCursor(const Cursor: TChunkCursor): TChunkCursor;
    function SplitFullChunk(const Place: TChunkCursor): TChunkCursor;
    class procedure InsertInChunk(const Chunk: TChunk; const Offset: Integer; const Value: T); static;

  public
    constructor Create(const Comparison: TComparison<T>);
    destructor Destroy; override;

    // The place of the first item, which is the end when the list is empty
    function Start: TChunkCursor;
    // The place of the first item that is not less than Value, or the end
    function FindLowerBound(const Value: T): TChunkCursor;
    function IsEnd(const Cursor: TChunkCursor): Boolean;
    function Item(const Cursor: TChunkCursor): T;
    function Next(const Cursor: TChunkCursor): TChunkCursor;
    // Inserts before the item at the cursor, so the cursor must come from FindLowerBound of the same value
    procedure Insert(const Cursor: TChunkCursor; const Value: T);

    property Count: Integer read FCount;
  end;

implementation

{ TChunkedSortedList<T> }

constructor TChunkedSortedList<T>.Create(const Comparison: TComparison<T>);
begin
  inherited Create;
  FChunks := TObjectList<TChunk>.Create(True);
  FComparison := Comparison;
end;

destructor TChunkedSortedList<T>.Destroy;
begin
  FChunks.Free;
  inherited;
end;

// The first chunk whose last item is not less than the value, or the number of chunks
function TChunkedSortedList<T>.FindChunk(const Value: T): Integer;
begin
  Result := 0;
  var UpperBound := FChunks.Count;
  while Result < UpperBound do
  begin
    const Middle = Result + (UpperBound - Result) div 2;
    const Chunk = FChunks[Middle];
    if FComparison(Chunk.Items[Chunk.Count - 1], Value) < 0 then
    begin
      Result := Middle + 1;
    end
    else
    begin
      UpperBound := Middle;
    end;
  end;
end;

function TChunkedSortedList<T>.FindOffset(const Chunk: TChunk; const Value: T): Integer;
begin
  Result := 0;
  var UpperBound := Chunk.Count;
  while Result < UpperBound do
  begin
    const Middle = Result + (UpperBound - Result) div 2;
    if FComparison(Chunk.Items[Middle], Value) < 0 then
    begin
      Result := Middle + 1;
    end
    else
    begin
      UpperBound := Middle;
    end;
  end;
end;

function TChunkedSortedList<T>.Start: TChunkCursor;
begin
  Result.Chunk := 0;
  Result.Offset := 0;
end;

function TChunkedSortedList<T>.FindLowerBound(const Value: T): TChunkCursor;
begin
  Result.Chunk := FindChunk(Value);
  Result.Offset := 0;
  if Result.Chunk < FChunks.Count then
  begin
    Result.Offset := FindOffset(FChunks[Result.Chunk], Value);
  end;
end;

function TChunkedSortedList<T>.IsEnd(const Cursor: TChunkCursor): Boolean;
begin
  Result := Cursor.Chunk >= FChunks.Count;
end;

function TChunkedSortedList<T>.Item(const Cursor: TChunkCursor): T;
begin
  Result := FChunks[Cursor.Chunk].Items[Cursor.Offset];
end;

function TChunkedSortedList<T>.Next(const Cursor: TChunkCursor): TChunkCursor;
begin
  Result := Cursor;
  Inc(Result.Offset);
  if Result.Offset >= FChunks[Result.Chunk].Count then
  begin
    Inc(Result.Chunk);
    Result.Offset := 0;
  end;
end;

procedure TChunkedSortedList<T>.SplitChunk(const ChunkIndex: Integer);
begin
  const Full = FChunks[ChunkIndex];
  const Half = Full.Count div 2;
  const Upper = TChunk.Create;
  SetLength(Upper.Items, MaxChunkSize);
  for var Index := Half to Full.Count - 1 do
  begin
    Upper.Items[Index - Half] := Full.Items[Index];
  end;
  Upper.Count := Full.Count - Half;
  Full.Count := Half;
  FChunks.Insert(ChunkIndex + 1, Upper);
end;

class procedure TChunkedSortedList<T>.InsertInChunk(const Chunk: TChunk; const Offset: Integer; const Value: T);
begin
  if Chunk.Count = Length(Chunk.Items) then
  begin
    SetLength(Chunk.Items, Length(Chunk.Items) * 2);
  end;

  for var Index := Chunk.Count downto Offset + 1 do
  begin
    Chunk.Items[Index] := Chunk.Items[Index - 1];
  end;
  Chunk.Items[Offset] := Value;
  Inc(Chunk.Count);
end;

procedure TChunkedSortedList<T>.EnsureFirstChunk;
begin
  if FChunks.Count > 0 then
  begin
    Exit;
  end;

  const First = TChunk.Create;
  SetLength(First.Items, FirstChunkCapacity);
  FChunks.Add(First);
end;

// The cursor of an empty list or of the end becomes the place after the last item of the last chunk
function TChunkedSortedList<T>.NormalizeCursor(const Cursor: TChunkCursor): TChunkCursor;
begin
  EnsureFirstChunk;
  if Cursor.Chunk < FChunks.Count then
  begin
    Exit(Cursor);
  end;

  Result.Chunk := FChunks.Count - 1;
  Result.Offset := FChunks[Result.Chunk].Count;
end;

function TChunkedSortedList<T>.SplitFullChunk(const Place: TChunkCursor): TChunkCursor;
begin
  Result := Place;
  if FChunks[Place.Chunk].Count < MaxChunkSize then
  begin
    Exit;
  end;

  SplitChunk(Place.Chunk);
  const LowerCount = FChunks[Place.Chunk].Count;
  if Place.Offset > LowerCount then
  begin
    Result.Offset := Place.Offset - LowerCount;
    Result.Chunk := Place.Chunk + 1;
  end;
end;

procedure TChunkedSortedList<T>.Insert(const Cursor: TChunkCursor; const Value: T);
begin
  const Place = SplitFullChunk(NormalizeCursor(Cursor));
  InsertInChunk(FChunks[Place.Chunk], Place.Offset, Value);
  Inc(FCount);
end;

end.
