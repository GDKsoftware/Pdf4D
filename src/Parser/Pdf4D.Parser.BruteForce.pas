// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdfparser/BruteForceParser.java (3.0.8)
// The last resort for a file whose xref cannot be used: it searches the file itself for objects, xref sections, trailers
// and object streams. TCosParser calls it at the places where COSParser does.
unit Pdf4D.Parser.BruteForce;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Document,
  Pdf4D.Cos.ObjectKey,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Cos.PdfObject,
  Pdf4D.Parser.Base,
  Pdf4D.Parser.Security.Interfaces,
  Pdf4D.Parser.StreamObject,
  Pdf4D.Parser.XrefStream,
  Pdf4D.Parser.XrefTrailerResolver;

type
  TBruteForceParser = class(TBaseParser)
  public
    // The most objects a search keeps: the highest object number a PDF can address, as for an xref stream
    const MaxFoundObjects = TXrefStreamParser.MaxEntries;

  private
    const MinimumSearchOffset = 6;
    // The search backwards for the start of an object looks at windows of ten bytes, up to 390 bytes in front
    const WindowLength = 10;
    const WindowCount = 40;
    const XrefTableMarker = 'xref';
    const XrefStreamMarker = '/XRef';
    const EofMarker = '%%EOF';
    const ObjMarker = 'obj';
    const SpaceObjMarker = ' obj';
    const TrailerMarker = 'trailer';
    const ObjStreamMarker = '/ObjStm';
    // "endo" and not "endobj": the file may be cut off in the middle of the word (PDFBOX-3936)
    const EndObjStart = 'ndo';
    const EndObjRest = 'bj';

  private
    FDocument: TCosDocument;
    FStreamReader: TStreamObjectReader;
    FPrepareDecryption: TDecryptionPreparer;
    FSecurityHandler: ISecurityHandler;
    FObjectOffsets: TDictionary<TCosObjectKey, Int64>;
    FSearchTriggered: Boolean;
    FLimitLogged: Boolean;
    FXrefTableOffsets: TArray<Int64>;
    FXrefStreamOffsets: TArray<Int64>;
    FHasXrefOffsets: Boolean;
    // The state of the search for objects
    FCurrentOffset: Int64;
    FLastObjectId: Int64;
    FLastGenerationId: Integer;
    FLastObjectOffset: Int64;
    FEndOfObjectFound: Boolean;

    class function IsDataFailure(const Failure: Exception): Boolean; static;
    class function IsInfo(const Dictionary: TCosDictionary): Boolean; static;
    class function IsCatalog(const Dictionary: TCosDictionary): Boolean; static;
    class function GetCosObject(const Dictionary: TCosDictionary; const Key: string): TCosObject; static;
    class function IsCatalogObject(const Value: TCosObject): Boolean; static;
    class function IsInfoObject(const Value: TCosObject): Boolean; static;
    class function SearchNearestValue(const Values: TArray<Int64>; const Offset: Int64): Int64; static;
    class function MatchesAt(const Window: TBytes; const WindowLength: Integer; const Position: Integer; const Text: string): Boolean; static;

    function IsString(const Text: string): Boolean;
    function FindString(const Text: string): Int64;
    function TryStoreOffset(const Key: TCosObjectKey; const Offset: Int64): Boolean;

    procedure BfSearchForObjects;
    function BfSearchForLastEOFMarker: Int64;
    function IsGarbageAfterEofMarker: Boolean;
    procedure ScanForObjects(const LastEofMarker: Int64);
    procedure ScanForObjectStart;
    procedure ScanForObjectEnd;
    function TryFindObjectNumber(out ObjectId: Int64; out ObjectOffset: Int64; out GenerationId: Integer): Boolean;
    procedure RegisterObject(const ObjectId: Int64; const GenerationId: Integer; const ObjectOffset: Int64);
    procedure StoreLastObject;

    procedure SearchForXrefOffsets;
    function BfSearchForXRefTables: TArray<Int64>;
    function BfSearchForXRefStreams: TArray<Int64>;
    function BfSearchForObjStreamOffsets: TDictionary<Int64, TCosObjectKey>;
    function TryFindObjectStartBefore(const Position: Int64; out ObjectStart: Int64): Boolean;
    function FindObjectMarkerBefore(const Position: Int64): Int64;
    function TryFindDigitsBefore(const MarkerOffset: Int64; out ObjectStart: Int64): Boolean;

    procedure ParseObjectStreams(const ObjStreamOffsets: TDictionary<Int64, TCosObjectKey>; const Resolver: TXrefTrailerResolver);
    function CollectCompleteObjectStreams(const ObjStreamOffsets: TDictionary<Int64, TCosObjectKey>): TArray<Int64>;
    procedure AddCompressedObjects(const Resolver: TXrefTrailerResolver; const StreamOffset: Int64);
    procedure RegisterCompressedObjects(const Resolver: TXrefTrailerResolver; const StreamOffset: Int64; const StreamObjectNumber: Int64; const ObjectNumbers: TDictionary<Int64, Integer>);

    procedure TransferXrefTable(const Resolver: TXrefTrailerResolver);
    procedure ClearTrailer(const Trailer: TCosDictionary);
    function BfSearchForTrailer(const Trailer: TCosDictionary): Boolean;
    function TryUseTrailerAtPosition(const Trailer: TCosDictionary): Boolean;
    function TryTakeTrailerEntries(const TrailerDictionary, Trailer: TCosDictionary): Boolean;
    procedure TakeOptionalTrailerEntries(const TrailerDictionary, Trailer: TCosDictionary);
    function SearchForTrailerItems(const Trailer: TCosDictionary): Boolean;
    function CompareCosObjects(const NewObject: TCosObject; const NewOffset: Int64; const CurrentObject: TCosObject): TCosObject;

  public
    // PrepareDecryption reads the encryption of the document once the trailer is rebuilt: the object streams are decrypted
    // with its result
    constructor Create(const Document: TCosDocument; const PrepareDecryption: TDecryptionPreparer);
    destructor Destroy; override;

    // Port of getBFCOSObjectOffsets: the offset of every object found in the file, or the number of the object stream
    // as a negative number. The first call searches the file. Owned by the parser.
    function GetBFCOSObjectOffsets: TDictionary<TCosObjectKey, Int64>;

    // Port of bfSearchForXRef: the offset of the xref table or xref stream that is nearest to XrefOffset, or -1
    function BfSearchForXRef(const XrefOffset: Int64): Int64;

    // Port of bfSearchForObjStreams: adds the objects of all object streams to the offsets of the search and to the
    // xref table of the resolver
    procedure BfSearchForObjStreams(const Resolver: TXrefTrailerResolver; const SecurityHandler: ISecurityHandler);

    // Port of rebuildTrailer: makes the xref table of the document from the objects found in the file and fills the
    // trailer of the document with the /Root, /Info, /Encrypt and /ID that it finds. Gives the trailer of the document.
    function RebuildTrailer(const Resolver: TXrefTrailerResolver): TCosDictionary;

    property SearchTriggered: Boolean read FSearchTriggered;
  end;

implementation

uses
  System.Math,
  System.Generics.Defaults,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Parser.ObjectStream;

const
  ByteLowerE = Ord('e');
  AsciiZero = 48;
  NoOffset = -1;

{ TBruteForceParser }

constructor TBruteForceParser.Create(const Document: TCosDocument; const PrepareDecryption: TDecryptionPreparer);
begin
  inherited Create(Document.Source, Document);
  FDocument := Document;
  FPrepareDecryption := PrepareDecryption;
  FStreamReader := TStreamObjectReader.Create(Self, Document);
  FObjectOffsets := TDictionary<TCosObjectKey, Int64>.Create(TCosObjectKeyComparer.Create);
end;

destructor TBruteForceParser.Destroy;
begin
  FObjectOffsets.Free;
  FStreamReader.Free;
  inherited;
end;

class function TBruteForceParser.IsDataFailure(const Failure: Exception): Boolean;
begin
  Result := ((Failure is EPdfParseException) or TPdfFailure.IsInputFailure(Failure));
end;

{ reading helpers }

function TBruteForceParser.IsString(const Text: string): Boolean;
begin
  Result := True;
  const OriginOffset = Source.GetPosition;
  for var Position := 1 to Text.Length do
  begin
    if Source.Read <> Ord(Text[Position]) then
    begin
      Result := False;
      Break;
    end;
  end;
  Source.Seek(OriginOffset);
end;

// Gives the start of the text and leaves the position at its end. A text that is cut off by the end of the file counts as
// found, like in PDFBox: the position of its first character is given.
function TBruteForceParser.FindString(const Text: string): Int64;
begin
  var Position: Int64 := NoOffset;
  var Counter := 0;
  var ReadChar := Source.Read;
  while ReadChar <> -1 do
  begin
    if ReadChar = Ord(Text[Counter + 1]) then
    begin
      if Counter = 0 then
      begin
        Position := Source.GetPosition - 1;
      end;
      Inc(Counter);
      if Counter = Text.Length then
      begin
        Exit(Position);
      end;
    end
    else if Counter > 0 then
    begin
      Counter := 0;
      Position := NoOffset;
      Continue;
    end;
    ReadChar := Source.Read;
  end;
  Result := Position;
end;

// Keeps the number of objects that a search finds within the limit. False when the object is not kept.
function TBruteForceParser.TryStoreOffset(const Key: TCosObjectKey; const Offset: Int64): Boolean;
begin
  Result := (FObjectOffsets.Count < MaxFoundObjects) or FObjectOffsets.ContainsKey(Key);
  if Result then
  begin
    FObjectOffsets.AddOrSetValue(Key, Offset);
  end
  else if not FLimitLogged then
  begin
    FLimitLogged := True;
    FDocument.Log.Warning('The brute force search found more than %d objects, the rest is ignored', [MaxFoundObjects]);
  end;
end;

function TBruteForceParser.GetBFCOSObjectOffsets: TDictionary<TCosObjectKey, Int64>;
begin
  if not FSearchTriggered then
  begin
    FSearchTriggered := True;
    BfSearchForObjects;
  end;
  Result := FObjectOffsets;
end;

{ search for objects }

procedure TBruteForceParser.BfSearchForObjects;
begin
  const LastEofMarker = BfSearchForLastEOFMarker;
  const OriginOffset = Source.GetPosition;
  FCurrentOffset := MinimumSearchOffset;
  FLastObjectId := Low(Int64);
  FLastGenerationId := Low(Integer);
  FLastObjectOffset := Low(Int64);
  FEndOfObjectFound := False;

  ScanForObjects(LastEofMarker);

  // If the file was not cut off in the middle or if the last object ends with "endobj", the last object has to be added
  // here: no object follows that would add it
  if ((LastEofMarker < High(Int64)) or FEndOfObjectFound) and (FLastObjectOffset > 0) then
  begin
    StoreLastObject;
  end;
  Source.Seek(OriginOffset);
end;

// True when what follows the EOF marker is not the start of an object or an xref table: garbage, or no more data
function TBruteForceParser.IsGarbageAfterEofMarker: Boolean;
begin
  try
    // Valid pdf content after the marker indicates a linearized or updated file, or one that is cut off somewhere
    SkipSpaces;
    if not IsString(XrefTableMarker) then
    begin
      ReadObjectNumber;
      ReadGenerationNumber;
    end;
    Result := False;
  except
    on Failure: Exception do
    begin
      if not IsDataFailure(Failure) then
      begin
        raise;
      end;
      FDocument.Log.Debug('An exception occurred during brute force for last EOF - ignoring: %s', [Failure.Message]);
      Result := True;
    end;
  end;
end;

function TBruteForceParser.BfSearchForLastEOFMarker: Int64;
begin
  var LastEofMarker: Int64 := NoOffset;
  const OriginOffset = Source.GetPosition;
  Source.Seek(MinimumSearchOffset);
  var TempMarker := FindString(EofMarker);
  while TempMarker <> NoOffset do
  begin
    if IsGarbageAfterEofMarker then
    begin
      LastEofMarker := TempMarker;
    end;
    TempMarker := FindString(EofMarker);
  end;
  Source.Seek(OriginOffset);

  if LastEofMarker = NoOffset then
  begin
    Result := High(Int64);
  end
  else
  begin
    Result := LastEofMarker;
  end;
end;

procedure TBruteForceParser.ScanForObjects(const LastEofMarker: Int64);
begin
  repeat
    Source.Seek(FCurrentOffset);
    const NextChar = Source.Read;
    Inc(FCurrentOffset);
    if IsWhitespace(NextChar) and IsString(ObjMarker) then
    begin
      ScanForObjectStart;
    end
    else if (NextChar = ByteLowerE) and IsString(EndObjStart) then
    begin
      ScanForObjectEnd;
    end;
  until (FCurrentOffset >= LastEofMarker) or Source.IsEOF or (FObjectOffsets.Count >= MaxFoundObjects);
end;

// An "obj" follows a whitespace: look backwards for the generation and the object number
procedure TBruteForceParser.ScanForObjectStart;
begin
  var ObjectId: Int64;
  var ObjectOffset: Int64;
  var GenerationId: Integer;
  if TryFindObjectNumber(ObjectId, ObjectOffset, GenerationId) then
  begin
    RegisterObject(ObjectId, GenerationId, ObjectOffset);
  end;
end;

function TBruteForceParser.TryFindObjectNumber(out ObjectId: Int64; out ObjectOffset: Int64; out GenerationId: Integer): Boolean;
begin
  Result := False;
  ObjectId := 0;
  ObjectOffset := 0;
  var TempOffset := FCurrentOffset - 2;
  Source.Seek(TempOffset);
  GenerationId := Source.Peek;
  // Is the next char a digit?
  if not IsDigit(GenerationId) then
  begin
    Exit;
  end;

  Dec(GenerationId, AsciiZero);
  Dec(TempOffset);
  Source.Seek(TempOffset);
  if not IsWhitespace(Source.Peek) then
  begin
    Exit;
  end;

  while (TempOffset > MinimumSearchOffset) and IsWhitespace(Source.Peek) do
  begin
    Dec(TempOffset);
    Source.Seek(TempOffset);
  end;

  var ObjectIdFound := False;
  while (TempOffset > MinimumSearchOffset) and IsDigit(Source.Peek) do
  begin
    Dec(TempOffset);
    Source.Seek(TempOffset);
    ObjectIdFound := True;
  end;

  if ObjectIdFound then
  begin
    Source.Read;
    ObjectId := ReadObjectNumber;
    ObjectOffset := TempOffset + 1;
    Result := True;
  end;
end;

procedure TBruteForceParser.RegisterObject(const ObjectId: Int64; const GenerationId: Integer; const ObjectOffset: Int64);
begin
  if FLastObjectOffset > 0 then
  begin
    // Add the former object ID only if there was a subsequent object ID
    StoreLastObject;
  end;
  FLastObjectId := ObjectId;
  FLastGenerationId := GenerationId;
  FLastObjectOffset := ObjectOffset;
  Inc(FCurrentOffset, ObjMarker.Length - 1);
  FEndOfObjectFound := False;
end;

procedure TBruteForceParser.StoreLastObject;
begin
  TryStoreOffset(TCosObjectKey.Make(FLastObjectId, FLastGenerationId), FLastObjectOffset);
end;

// "endo" was found: the file may be cut off in the middle of the keyword
procedure TBruteForceParser.ScanForObjectEnd;
begin
  Inc(FCurrentOffset, EndObjStart.Length);
  Source.Seek(FCurrentOffset);
  if Source.IsEOF then
  begin
    FEndOfObjectFound := True;
  end
  else if IsString(EndObjRest) then
  begin
    Inc(FCurrentOffset, EndObjRest.Length);
    FEndOfObjectFound := True;
  end;
end;

{ search for xref tables and streams }

class function TBruteForceParser.SearchNearestValue(const Values: TArray<Int64>; const Offset: Int64): Int64;
begin
  Result := NoOffset;
  var CurrentDifference: Int64 := 0;
  var IsFirst := True;
  for var Value in Values do
  begin
    const NewDifference = Abs(Offset - Value);
    if IsFirst or (CurrentDifference > NewDifference) then
    begin
      CurrentDifference := NewDifference;
      Result := Value;
      IsFirst := False;
    end;
  end;
end;

// The offsets are searched once: a file with many damaged xref sections is not scanned again for each of them
procedure TBruteForceParser.SearchForXrefOffsets;
begin
  if not FHasXrefOffsets then
  begin
    FXrefTableOffsets := BfSearchForXRefTables;
    FXrefStreamOffsets := BfSearchForXRefStreams;
    FHasXrefOffsets := True;
  end;
end;

function TBruteForceParser.BfSearchForXRef(const XrefOffset: Int64): Int64;
begin
  const OriginOffset = Source.GetPosition;
  try
    SearchForXrefOffsets;
  finally
    Source.Seek(OriginOffset);
  end;

  // This won't work in every case: it takes the nearest offset
  const NewOffsetTable = SearchNearestValue(FXrefTableOffsets, XrefOffset);
  const NewOffsetStream = SearchNearestValue(FXrefStreamOffsets, XrefOffset);

  if (NewOffsetTable > NoOffset) and (NewOffsetStream > NoOffset) then
  begin
    if Abs(XrefOffset - NewOffsetTable) > Abs(XrefOffset - NewOffsetStream) then
    begin
      Result := NewOffsetStream;
    end
    else
    begin
      Result := NewOffsetTable;
    end;
  end
  else if NewOffsetTable > NoOffset then
  begin
    Result := NewOffsetTable;
  end
  else
  begin
    Result := NewOffsetStream;
  end;
end;

function TBruteForceParser.BfSearchForXRefTables: TArray<Int64>;
begin
  const Offsets = TList<Int64>.Create;
  try
    // A pdf may contain more than one xref table
    Source.Seek(MinimumSearchOffset);
    var NewOffset := FindString(XrefTableMarker);
    while NewOffset <> NoOffset do
    begin
      Source.Seek(NewOffset - 1);
      // Ensure that we don't read "startxref" instead of "xref"
      if IsWhitespace(Source.Peek) then
      begin
        Offsets.Add(NewOffset);
      end;
      Source.Seek(NewOffset + XrefTableMarker.Length);
      NewOffset := FindString(XrefTableMarker);
    end;
    Result := Offsets.ToArray;
  finally
    Offsets.Free;
  end;
end;

function TBruteForceParser.BfSearchForXRefStreams: TArray<Int64>;
begin
  const Offsets = TList<Int64>.Create;
  try
    // A pdf may contain more than one /XRef entry
    Source.Seek(MinimumSearchOffset);
    var XrefOffset := FindString(XrefStreamMarker);
    while XrefOffset <> NoOffset do
    begin
      var ObjectStart: Int64;
      if TryFindObjectStartBefore(XrefOffset, ObjectStart) then
      begin
        FDocument.Log.Debug('Fixed reference for xref stream %d -> %d', [XrefOffset, ObjectStart]);
        Offsets.Add(ObjectStart);
      end;
      Source.Seek(XrefOffset + XrefStreamMarker.Length);
      XrefOffset := FindString(XrefStreamMarker);
    end;
    Result := Offsets.ToArray;
  finally
    Offsets.Free;
  end;
end;

class function TBruteForceParser.MatchesAt(const Window: TBytes; const WindowLength: Integer; const Position: Integer; const Text: string): Boolean;
begin
  Result := (Position >= 0) and (Text.Length <= WindowLength - Position);
  if Result then
  begin
    for var Index := 1 to Text.Length do
    begin
      if Window[Position + Index - 1] <> Ord(Text[Index]) then
      begin
        Exit(False);
      end;
    end;
  end;
end;

// The offset of the first " obj" in the windows in front of Position, or -1. The windows are looked at in the order of
// PDFBox: the one nearest to Position first. They are read at once, so the search costs a fixed number of steps for each
// position that is searched for.
function TBruteForceParser.FindObjectMarkerBefore(const Position: Int64): Int64;
begin
  Result := NoOffset;
  const ReadStart = Max(Position - (WindowCount - 1) * WindowLength, Int64(1));
  const ReadEnd = Position + SpaceObjMarker.Length;
  var Window: TBytes;
  SetLength(Window, Integer(ReadEnd - ReadStart));
  Source.Seek(ReadStart);
  var Available := Source.Read(Window, 0, Length(Window));
  if Available < 0 then
  begin
    Available := 0;
  end;

  for var Step := 1 to WindowCount - 1 do
  begin
    const CurrentOffset = Position - Step * WindowLength;
    if CurrentOffset > 0 then
    begin
      for var Index := 0 to WindowLength - 1 do
      begin
        if MatchesAt(Window, Available, CurrentOffset + Index - ReadStart, SpaceObjMarker) then
        begin
          Exit(CurrentOffset + Index);
        end;
      end;
    end;
  end;
end;

// The marker is found at MarkerOffset: look back for the digit of the generation, a space and the digits of the number
function TBruteForceParser.TryFindDigitsBefore(const MarkerOffset: Int64; out ObjectStart: Int64): Boolean;
begin
  Result := False;
  ObjectStart := NoOffset;
  var TempOffset := MarkerOffset - 1;
  Source.Seek(TempOffset);
  // Is the next char a digit?
  if not IsDigit(Source.Peek) then
  begin
    Exit;
  end;

  Dec(TempOffset);
  Source.Seek(TempOffset);
  if not IsSpace(Source.Peek) then
  begin
    Exit;
  end;

  var DigitCount := 0;
  Dec(TempOffset);
  Source.Seek(TempOffset);
  while (TempOffset > MinimumSearchOffset) and IsDigit(Source.Peek) do
  begin
    Dec(TempOffset);
    Source.Seek(TempOffset);
    Inc(DigitCount);
  end;

  if DigitCount > 0 then
  begin
    Source.Read;
    ObjectStart := Source.GetPosition;
    Result := True;
  end;
end;

// Searches backwards from the position of /XRef or /ObjStm for the start of the object: "<number> <generation> obj"
function TBruteForceParser.TryFindObjectStartBefore(const Position: Int64; out ObjectStart: Int64): Boolean;
begin
  ObjectStart := NoOffset;
  const MarkerOffset = FindObjectMarkerBefore(Position);
  Result := (MarkerOffset <> NoOffset) and TryFindDigitsBefore(MarkerOffset, ObjectStart);
end;

function TBruteForceParser.BfSearchForObjStreamOffsets: TDictionary<Int64, TCosObjectKey>;
begin
  Result := TDictionary<Int64, TCosObjectKey>.Create;
  try
    Source.Seek(MinimumSearchOffset);
    var PositionObjStream := FindString(ObjStreamMarker);
    while (PositionObjStream <> NoOffset) and (Result.Count < MaxFoundObjects) do
    begin
      var ObjectStart: Int64;
      if TryFindObjectStartBefore(PositionObjStream, ObjectStart) then
      begin
        Source.Seek(ObjectStart);
        const ObjectNumber = ReadObjectNumber;
        const GenerationNumber = ReadGenerationNumber;
        Result.AddOrSetValue(ObjectStart, TCosObjectKey.Make(ObjectNumber, GenerationNumber));
        FDocument.Log.Debug('Dictionary start for object stream -> %d', [ObjectStart]);
      end;
      Source.Seek(PositionObjStream + ObjStreamMarker.Length);
      PositionObjStream := FindString(ObjStreamMarker);
    end;
  except
    Result.Free;
    raise;
  end;
end;

{ object streams }

function TBruteForceParser.CollectCompleteObjectStreams(const ObjStreamOffsets: TDictionary<Int64, TCosObjectKey>): TArray<Int64>;
begin
  var Offsets := ObjStreamOffsets.Keys.ToArray;
  TArray.Sort<Int64>(Offsets);
  const Complete = TList<Int64>.Create;
  try
    for var Offset in Offsets do
    begin
      const StreamKey = ObjStreamOffsets[Offset];
      var FoundOffset: Int64;
      if not FObjectOffsets.TryGetValue(StreamKey, FoundOffset) then
      begin
        FDocument.Log.Warning('Skipped incomplete object stream:%s at %d', [StreamKey.ToString, Offset]);
      end
      else if FoundOffset = Offset then
      begin
        Complete.Add(Offset);
      end;
    end;
    Result := Complete.ToArray;
  finally
    Complete.Free;
  end;
end;

procedure TBruteForceParser.RegisterCompressedObjects(const Resolver: TXrefTrailerResolver; const StreamOffset: Int64; const StreamObjectNumber: Int64; const ObjectNumbers: TDictionary<Int64, Integer>);
begin
  const XrefTable = Resolver.GetXrefTable;
  for var ObjectNumber in ObjectNumbers.Keys do
  begin
    const ObjectKey = TCosObjectKey.Make(ObjectNumber, 0);
    var ExistingOffset: Int64;
    var HasExistingOffset := FObjectOffsets.TryGetValue(ObjectKey, ExistingOffset);
    if HasExistingOffset and (ExistingOffset < 0) then
    begin
      // Translate the stream object key to its offset
      HasExistingOffset := FObjectOffsets.TryGetValue(TCosObjectKey.Make(Abs(ExistingOffset), 0), ExistingOffset);
    end;

    if ((not HasExistingOffset) or (StreamOffset > ExistingOffset)) and TryStoreOffset(ObjectKey, -StreamObjectNumber) then
    begin
      XrefTable.AddOrSetValue(ObjectKey, -StreamObjectNumber);
    end;
  end;
end;

// The stream is at StreamOffset: its object numbers are added as objects in that object stream
procedure TBruteForceParser.AddCompressedObjects(const Resolver: TXrefTrailerResolver; const StreamOffset: Int64);
begin
  Source.Seek(StreamOffset);
  const StreamObjectNumber = ReadObjectNumber;
  const StreamGeneration = ReadGenerationNumber;
  ReadExpectedString(ObjMarker);
  try
    const Dictionary = ParseCosDictionary(False);
    var Stream: TCosStream;
    try
      Stream := FStreamReader.ParseCosStream(Dictionary);
    finally
      Dictionary.Free;
    end;

    try
      if Assigned(FSecurityHandler) then
      begin
        FSecurityHandler.DecryptStream(Stream, StreamObjectNumber, StreamGeneration);
      end;
      const StreamParser = TObjectStreamParser.Create(Stream, FDocument);
      try
        const ObjectNumbers = StreamParser.ReadObjectNumbers;
        try
          RegisterCompressedObjects(Resolver, StreamOffset, StreamObjectNumber, ObjectNumbers);
        finally
          ObjectNumbers.Free;
        end;
      finally
        StreamParser.Free;
      end;
    finally
      Stream.Free;
    end;
  except
    on Failure: Exception do
    begin
      const IsFailureOfData = (IsDataFailure(Failure) or (Failure is EPdfUnsupportedFeatureException));
      if not IsFailureOfData then
      begin
        raise;
      end;
      FDocument.Log.Debug('Skipped corrupt stream: (%d 0 at offset %d: %s', [StreamObjectNumber, StreamOffset, Failure.Message]);
    end;
  end;
end;

procedure TBruteForceParser.ParseObjectStreams(const ObjStreamOffsets: TDictionary<Int64, TCosObjectKey>; const Resolver: TXrefTrailerResolver);
begin
  GetBFCOSObjectOffsets;
  for var StreamOffset in CollectCompleteObjectStreams(ObjStreamOffsets) do
  begin
    AddCompressedObjects(Resolver, StreamOffset);
  end;
end;

procedure TBruteForceParser.BfSearchForObjStreams(const Resolver: TXrefTrailerResolver; const SecurityHandler: ISecurityHandler);
begin
  FSecurityHandler := SecurityHandler;
  const OriginOffset = Source.GetPosition;
  const ObjStreamOffsets = BfSearchForObjStreamOffsets;
  try
    ParseObjectStreams(ObjStreamOffsets, Resolver);
  finally
    ObjStreamOffsets.Free;
  end;
  Source.Seek(OriginOffset);
end;

{ trailer }

class function TBruteForceParser.IsInfo(const Dictionary: TCosDictionary): Boolean;
begin
  Result := False;
  if Dictionary.ContainsKey(TCosNames.Parent) or Dictionary.ContainsKey(TCosNames.A) or Dictionary.ContainsKey(TCosNames.Dest) then
  begin
    Exit;
  end;

  Result := (Dictionary.ContainsKey(TCosNames.ModDate) or Dictionary.ContainsKey(TCosNames.Title) or
             Dictionary.ContainsKey(TCosNames.Author) or Dictionary.ContainsKey(TCosNames.Subject) or
             Dictionary.ContainsKey(TCosNames.Keywords) or Dictionary.ContainsKey(TCosNames.Creator) or
             Dictionary.ContainsKey(TCosNames.Producer) or Dictionary.ContainsKey(TCosNames.CreationDate));
end;

class function TBruteForceParser.IsCatalog(const Dictionary: TCosDictionary): Boolean;
begin
  var TypeValue: TCosBase;
  const IsCatalogType = (Dictionary.TryGetDictionaryObject(TCosNames.Type_, TypeValue) and (TypeValue is TCosName) and (TCosName(TypeValue).Name = TCosNames.Catalog));
  Result := (IsCatalogType or Dictionary.ContainsKey(TCosNames.FDF));
end;

class function TBruteForceParser.GetCosObject(const Dictionary: TCosDictionary; const Key: string): TCosObject;
begin
  Result := nil;
  const Item = Dictionary.GetItem(Key);
  if Item is TCosObject then
  begin
    Result := TCosObject(Item);
  end;
end;

// True when the object can be dereferenced to a catalog
class function TBruteForceParser.IsCatalogObject(const Value: TCosObject): Boolean;
begin
  const Content = Value.GetObject;
  Result := ((Content is TCosDictionary) and IsCatalog(TCosDictionary(Content)));
end;

// True when the object can be dereferenced to an info dictionary
class function TBruteForceParser.IsInfoObject(const Value: TCosObject): Boolean;
begin
  const Content = Value.GetObject;
  Result := ((Content is TCosDictionary) and IsInfo(TCosDictionary(Content)));
end;

procedure TBruteForceParser.ClearTrailer(const Trailer: TCosDictionary);
begin
  Trailer.Clear;
end;

procedure TBruteForceParser.TakeOptionalTrailerEntries(const TrailerDictionary, Trailer: TCosDictionary);
begin
  // The encryption dictionary is not checked beyond being a dictionary
  const EncryptObject = GetCosObject(TrailerDictionary, TCosNames.Encrypt);
  if Assigned(EncryptObject) and (EncryptObject.GetObject is TCosDictionary) then
  begin
    Trailer.SetItem(TCosNames.Encrypt, EncryptObject);
  end;

  const IdItem = TrailerDictionary.GetItem(TCosNames.ID);
  if IdItem is TCosArray then
  begin
    Trailer.SetItem(TCosNames.ID, TCosValueCopier.Copy(IdItem));
  end;
end;

function TBruteForceParser.TryTakeTrailerEntries(const TrailerDictionary, Trailer: TCosDictionary): Boolean;
begin
  // Check if the dictionaries can be dereferenced and are the ones we are looking for
  const RootObject = GetCosObject(TrailerDictionary, TCosNames.Root);
  const InfoObject = GetCosObject(TrailerDictionary, TCosNames.Info);
  const RootFound = Assigned(RootObject) and IsCatalogObject(RootObject);
  const InfoFound = Assigned(InfoObject) and IsInfoObject(InfoObject);

  Result := (RootFound and InfoFound);
  if Result then
  begin
    Trailer.SetItem(TCosNames.Root, RootObject);
    Trailer.SetItem(TCosNames.Info, InfoObject);
    TakeOptionalTrailerEntries(TrailerDictionary, Trailer);
  end;
end;

function TBruteForceParser.TryUseTrailerAtPosition(const Trailer: TCosDictionary): Boolean;
begin
  Result := False;
  try
    SkipSpaces;
    const TrailerDictionary = ParseCosDictionary(True);
    try
      Result := TryTakeTrailerEntries(TrailerDictionary, Trailer);
    finally
      TrailerDictionary.Free;
    end;
  except
    on Failure: Exception do
    begin
      if not IsDataFailure(Failure) then
      begin
        raise;
      end;
      FDocument.Log.Debug('An exception occurred during brute force search for trailer - ignoring: %s', [Failure.Message]);
    end;
  end;
end;

// Port of bfSearchForTrailer: looks at every "trailer" for a dictionary with a /Root and an /Info that are right
function TBruteForceParser.BfSearchForTrailer(const Trailer: TCosDictionary): Boolean;
begin
  const OriginOffset = Source.GetPosition;
  Source.Seek(MinimumSearchOffset);
  var TrailerOffset := FindString(TrailerMarker);
  while TrailerOffset <> NoOffset do
  begin
    if TryUseTrailerAtPosition(Trailer) then
    begin
      Exit(True);
    end;
    TrailerOffset := FindString(TrailerMarker);
  end;
  Source.Seek(OriginOffset);
  Result := False;
end;

function TBruteForceParser.CompareCosObjects(const NewObject: TCosObject; const NewOffset: Int64; const CurrentObject: TCosObject): TCosObject;
begin
  if not Assigned(CurrentObject) then
  begin
    Exit(NewObject);
  end;

  const CurrentKey = CurrentObject.Key;
  const NewKey = NewObject.Key;
  // Check if the current object is an updated version of the previous found object
  if CurrentKey.Number = NewKey.Number then
  begin
    if CurrentKey.Generation < NewKey.Generation then
    begin
      Exit(NewObject);
    end;
    Exit(CurrentObject);
  end;

  // Most likely the object with the bigger offset is the newer one
  var CurrentOffset: Int64;
  if FDocument.XrefTable.TryGetValue(CurrentKey, CurrentOffset) and (NewOffset > CurrentOffset) then
  begin
    Result := NewObject;
  end
  else
  begin
    Result := CurrentObject;
  end;
end;

// Port of searchForTrailerItems: the document catalog and the info dictionary among all objects that were found. The
// objects are looked at in the order of their offsets.
function TBruteForceParser.SearchForTrailerItems(const Trailer: TCosDictionary): Boolean;
begin
  var RootObject: TCosObject := nil;
  var InfoObject: TCosObject := nil;
  var Found := GetBFCOSObjectOffsets.ToArray;
  TArray.Sort<TPair<TCosObjectKey, Int64>>(Found, TComparer<TPair<TCosObjectKey, Int64>>.Construct(
    function(const Left, Right: TPair<TCosObjectKey, Int64>): Integer
    begin
      Result := TComparer<Int64>.Default.Compare(Left.Value, Right.Value);
    end));

  for var Entry in Found do
  begin
    const CosObject = FDocument.GetObjectFromPool(Entry.Key);
    const BaseObject = CosObject.GetObject;
    if BaseObject is TCosDictionary then
    begin
      const Dictionary = TCosDictionary(BaseObject);
      if IsCatalog(Dictionary) then
      begin
        RootObject := CompareCosObjects(CosObject, Entry.Value, RootObject);
      end
      else if IsInfo(Dictionary) then
      begin
        InfoObject := CompareCosObjects(CosObject, Entry.Value, InfoObject);
      end;
    end;
  end;

  if Assigned(RootObject) then
  begin
    Trailer.SetItem(TCosNames.Root, RootObject);
  end;
  if Assigned(InfoObject) then
  begin
    Trailer.SetItem(TCosNames.Info, InfoObject);
  end;
  Result := Assigned(RootObject);
end;

procedure TBruteForceParser.TransferXrefTable(const Resolver: TXrefTrailerResolver);
begin
  FDocument.XrefTable.Clear;
  var HighestNumber: Int64 := 0;
  for var Entry in Resolver.GetXrefTable do
  begin
    FDocument.XrefTable.AddOrSetValue(Entry.Key, Entry.Value);
    if Entry.Key.Number > HighestNumber then
    begin
      HighestNumber := Entry.Key.Number;
    end;
  end;
  // Remember the highest object number to avoid it being reused in incremental saving
  FDocument.HighestXRefObjectNumber := HighestNumber;
end;

function TBruteForceParser.RebuildTrailer(const Resolver: TXrefTrailerResolver): TCosDictionary;
begin
  FSecurityHandler := nil;
  // Use the found objects to rebuild the trailer resolver
  Resolver.Reset;
  Resolver.NextXrefObj(0, TXrefType.Table);
  for var Entry in GetBFCOSObjectOffsets do
  begin
    Resolver.SetXref(Entry.Key, Entry.Value);
  end;
  Resolver.SetStartxref(0);
  TransferXrefTable(Resolver);

  Result := FDocument.Trailer;
  ClearTrailer(Result);
  var ObjectStreamsDone := False;
  if not (BfSearchForTrailer(Result) or SearchForTrailerItems(Result)) then
  begin
    // The root entry wasn't found, maybe it is part of an object stream: search for all object streams
    BfSearchForObjStreams(Resolver, FSecurityHandler);
    ObjectStreamsDone := True;
    // Search again for the root entry
    SearchForTrailerItems(Result);
  end;

  // Prepare decryption if necessary
  FSecurityHandler := FPrepareDecryption();
  if not ObjectStreamsDone then
  begin
    BfSearchForObjStreams(Resolver, FSecurityHandler);
  end;
end;

end.
