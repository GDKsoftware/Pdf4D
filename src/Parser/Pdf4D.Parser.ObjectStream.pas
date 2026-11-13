// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdfparser/PDFObjectStreamParser.java (3.0.8)
unit Pdf4D.Parser.ObjectStream;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Document,
  Pdf4D.Cos.ObjectKey,
  Pdf4D.Parser.Base,
  Pdf4D.IO.RandomAccessRead;

type
  // Reads the objects of an object stream (/Type /ObjStm). The stream is decoded on every call, so the parser can be used more than once.
  TObjectStreamParser = class
  private
    FStream: TCosStream;
    FDocument: TCosDocument;
    FObjectCount: Integer;
    FFirstObject: Integer;
    FDecoded: TBytes;
    FHasDecoded: Boolean;
    FSource: TRandomAccessRead;
    FParser: TBaseParser;

    procedure ReadHeaderValues;
    procedure StartReading;
    procedure StopReading;
    function ReadObjectNumbersOfHeader: TDictionary<Int64, Integer>;
    function ReadObjectOffsetsOfHeader: TDictionary<Integer, Int64>;
    procedure SkipToFirstObject;
    procedure SkipTo(const Position: Int64);
    function ParseObjectHere(out ParsedObject: TCosBase): Boolean;
    function CollectXrefKeys: TDictionary<Int64, TCosObjectKey>;
    function KeyOf(const XrefKeys: TDictionary<Int64, TCosObjectKey>; const ObjectNumber: Int64): TCosObjectKey;
    function SortedOffsets(const Offsets: TDictionary<Integer, Int64>): TArray<Integer>;
    function IsIndexNeeded(const Offsets: TDictionary<Integer, Int64>): Boolean;
    procedure ParseEntriesWithKeys(const Offsets: TDictionary<Integer, Int64>; const XrefKeys: TDictionary<Int64, TCosObjectKey>; const IndexNeeded: Boolean; const Objects: TObjectDictionary<TCosObjectKey, TCosBase>);
    procedure ParseEntries(const Offsets: TDictionary<Integer, Int64>; const Objects: TObjectDictionary<TCosObjectKey, TCosBase>);
    procedure LogWarning(const Fmt: string; const Args: array of const);

  public
    // Raises EPdfParseException when /N or /First is missing or negative. The document may be nil.
    constructor Create(const Stream: TCosStream; const Document: TCosDocument);

    // The object with that number, or False when the stream does not hold it. The caller owns the object.
    function TryParseObject(const ObjectNumber: Int64; out ParsedObject: TCosBase): Boolean;

    // All objects by key (the number, generation 0 and, when the xref table knows it, the index in the stream).
    // The result owns the objects: take one out with ExtractPair to keep it.
    function ParseAllObjects: TObjectDictionary<TCosObjectKey, TCosBase>;

    // The object numbers of the header with their offsets relative to /First. The caller frees the result.
    function ReadObjectNumbers: TDictionary<Int64, Integer>;
  end;

implementation

uses
  System.Classes,
  System.Generics.Defaults,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.PdfObject;

const
  MissingNumber = -1;

{ TObjectStreamParser }

constructor TObjectStreamParser.Create(const Stream: TCosStream; const Document: TCosDocument);
begin
  inherited Create;
  FStream := Stream;
  FDocument := Document;
  ReadHeaderValues;
end;

procedure TObjectStreamParser.ReadHeaderValues;
begin
  FObjectCount := FStream.GetInt(TCosNames.N, MissingNumber);
  if FObjectCount = MissingNumber then
  begin
    raise EPdfParseException.Create('/N entry missing in object stream');
  end;
  if FObjectCount < 0 then
  begin
    raise EPdfParseException.CreateFmt('Illegal /N entry in object stream: %d', [FObjectCount]);
  end;

  FFirstObject := FStream.GetInt(TCosNames.First, MissingNumber);
  if FFirstObject = MissingNumber then
  begin
    raise EPdfParseException.Create('/First entry missing in object stream');
  end;
  if FFirstObject < 0 then
  begin
    raise EPdfParseException.CreateFmt('Illegal /First entry in object stream: %d', [FFirstObject]);
  end;
end;

procedure TObjectStreamParser.LogWarning(const Fmt: string; const Args: array of const);
begin
  if Assigned(FDocument) then
  begin
    FDocument.Log.Warning(Fmt, Args);
  end;
end;

procedure TObjectStreamParser.StartReading;
begin
  if not FHasDecoded then
  begin
    const Decoded = FStream.CreateDecodedStream;
    try
      SetLength(FDecoded, Decoded.Size);
      if Decoded.Size > 0 then
      begin
        Decoded.Position := 0;
        Decoded.ReadBuffer(FDecoded[0], Decoded.Size);
      end;
    finally
      Decoded.Free;
    end;
    FHasDecoded := True;
  end;

  FSource := TRandomAccessRead.FromBytes(FDecoded);
  FParser := TBaseParser.Create(FSource, FDocument);
end;

procedure TObjectStreamParser.StopReading;
begin
  FreeAndNil(FParser);
  FreeAndNil(FSource);
end;

// The header: pairs of an object number and an offset. Stops at the part of the stream reserved for them.
function TObjectStreamParser.ReadObjectNumbersOfHeader: TDictionary<Int64, Integer>;
begin
  // Not sized by /N: there can be fewer object numbers than expected
  Result := TDictionary<Int64, Integer>.Create;
  try
    const FirstObjectPosition = FSource.GetPosition + FFirstObject - 1;
    for var Counter := 1 to FObjectCount do
    begin
      if FSource.GetPosition >= FirstObjectPosition then
      begin
        Break;
      end;

      const ObjectNumber = FParser.ReadObjectNumber;
      const Offset = Integer(FParser.ReadLong);
      Result.AddOrSetValue(ObjectNumber, Offset);
    end;
  except
    Result.Free;
    raise;
  end;
end;

// The offsets are not sorted in every file, and a sequential parser needs them in order (PDFBOX-4927)
function TObjectStreamParser.ReadObjectOffsetsOfHeader: TDictionary<Integer, Int64>;
begin
  Result := TDictionary<Integer, Int64>.Create;
  try
    const FirstObjectPosition = FSource.GetPosition + FFirstObject - 1;
    for var Counter := 1 to FObjectCount do
    begin
      if FSource.GetPosition >= FirstObjectPosition then
      begin
        Break;
      end;

      const ObjectNumber = FParser.ReadObjectNumber;
      const Offset = Integer(FParser.ReadLong);
      Result.AddOrSetValue(Offset, ObjectNumber);
    end;
  except
    Result.Free;
    raise;
  end;
end;

procedure TObjectStreamParser.SkipTo(const Position: Int64);
begin
  if FSource.GetPosition < Position then
  begin
    FSource.Seek(Position);
  end;
end;

procedure TObjectStreamParser.SkipToFirstObject;
begin
  if FFirstObject > 0 then
  begin
    SkipTo(FFirstObject);
  end;
end;

// Gives False for no object at the position and for a reference, which is not a value of its own
function TObjectStreamParser.ParseObjectHere(out ParsedObject: TCosBase): Boolean;
begin
  ParsedObject := FParser.ParseDirObject;
  Result := Assigned(ParsedObject);
  if Result and (ParsedObject is TCosObject) then
  begin
    LogWarning('Object stream contains a reference at offset %d, ignored', [FSource.GetPosition]);
    ParsedObject := nil;
    Exit(False);
  end;

  if Result then
  begin
    ParsedObject.Direct := False;
  end;
end;

function TObjectStreamParser.TryParseObject(const ObjectNumber: Int64; out ParsedObject: TCosBase): Boolean;
begin
  ParsedObject := nil;
  StartReading;
  try
    const Numbers = ReadObjectNumbersOfHeader;
    try
      var Offset: Integer;
      if not Numbers.TryGetValue(ObjectNumber, Offset) then
      begin
        Exit(False);
      end;

      SkipToFirstObject;
      FSource.Seek(FSource.GetPosition + Offset);
      Result := ParseObjectHere(ParsedObject);
    finally
      Numbers.Free;
    end;
  finally
    StopReading;
  end;
end;

function TObjectStreamParser.ReadObjectNumbers: TDictionary<Int64, Integer>;
begin
  StartReading;
  try
    Result := ReadObjectNumbersOfHeader;
  finally
    StopReading;
  end;
end;

function TObjectStreamParser.SortedOffsets(const Offsets: TDictionary<Integer, Int64>): TArray<Integer>;
begin
  Result := Offsets.Keys.ToArray;
  TArray.Sort<Integer>(Result);
end;

// The index is only used when an object number is stored more than once: files exist where it would give wrong results
function TObjectStreamParser.IsIndexNeeded(const Offsets: TDictionary<Integer, Int64>): Boolean;
begin
  const DistinctNumbers = TDictionary<Int64, Boolean>.Create;
  try
    for var ObjectNumber in Offsets.Values do
    begin
      DistinctNumbers.AddOrSetValue(ObjectNumber, True);
    end;
    Result := (Offsets.Count > DistinctNumbers.Count);
  finally
    DistinctNumbers.Free;
  end;
end;

// The keys of the xref table with generation 0 by object number: those carry the index in the stream
function TObjectStreamParser.CollectXrefKeys: TDictionary<Int64, TCosObjectKey>;
begin
  Result := TDictionary<Int64, TCosObjectKey>.Create;
  if not Assigned(FDocument) then
  begin
    Exit;
  end;

  for var Key in FDocument.XrefTable.Keys do
  begin
    if Key.Generation = 0 then
    begin
      Result.AddOrSetValue(Key.Number, Key);
    end;
  end;
end;

function TObjectStreamParser.KeyOf(const XrefKeys: TDictionary<Int64, TCosObjectKey>; const ObjectNumber: Int64): TCosObjectKey;
begin
  if not XrefKeys.TryGetValue(ObjectNumber, Result) then
  begin
    Result := TCosObjectKey.Make(ObjectNumber, 0);
  end;
end;

procedure TObjectStreamParser.ParseEntries(const Offsets: TDictionary<Integer, Int64>; const Objects: TObjectDictionary<TCosObjectKey, TCosBase>);
begin
  const IndexNeeded = IsIndexNeeded(Offsets);
  const XrefKeys = CollectXrefKeys;
  try
    ParseEntriesWithKeys(Offsets, XrefKeys, IndexNeeded, Objects);
  finally
    XrefKeys.Free;
  end;
end;

procedure TObjectStreamParser.ParseEntriesWithKeys(const Offsets: TDictionary<Integer, Int64>; const XrefKeys: TDictionary<Int64, TCosObjectKey>; const IndexNeeded: Boolean; const Objects: TObjectDictionary<TCosObjectKey, TCosBase>);
begin
  var Index := 0;
  for var Offset in SortedOffsets(Offsets) do
  begin
    const ObjectKey = KeyOf(XrefKeys, Offsets[Offset]);
    const HasOtherIndex = (IndexNeeded and (ObjectKey.StreamIndex > -1) and (ObjectKey.StreamIndex <> Index));
    Inc(Index);
    if HasOtherIndex then
    begin
      Continue;
    end;

    const FinalPosition = Integer(Int64(FFirstObject) + Offset);
    if FinalPosition > 0 then
    begin
      SkipTo(FinalPosition);
    end;

    var ParsedObject: TCosBase;
    if ParseObjectHere(ParsedObject) then
    begin
      Objects.AddOrSetValue(ObjectKey, ParsedObject);
    end;
  end;
end;

function TObjectStreamParser.ParseAllObjects: TObjectDictionary<TCosObjectKey, TCosBase>;
begin
  Result := TObjectDictionary<TCosObjectKey, TCosBase>.Create([doOwnsValues], TCosObjectKeyComparer.Create);
  try
    StartReading;
    try
      const Offsets = ReadObjectOffsetsOfHeader;
      try
        SkipToFirstObject;
        ParseEntries(Offsets, Result);
      finally
        Offsets.Free;
      end;
    finally
      StopReading;
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.
