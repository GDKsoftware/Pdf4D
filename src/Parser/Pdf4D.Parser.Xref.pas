// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdfparser/COSParser.java (3.0.8): parseXref, parseXrefTable,
// parseXrefObjStream, parseTrailer, parseStartXref, getStartxrefOffset, checkXRefOffset, checkXRefStreamOffset and
// calculateXRefFixedOffset. PDFBox 3.0.8 has no class XrefParser: this one holds those methods of COSParser.
unit Pdf4D.Parser.Xref;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Document,
  Pdf4D.Cos.ObjectKey,
  Pdf4D.IO.RandomAccessRead,
  Pdf4D.Parser.Base,
  Pdf4D.Parser.XrefTrailerResolver;

type
  // Gives the offset of the xref table or stream that a brute force search finds for the offset that was expected, or -1
  TXrefOffsetSearch = reference to function(const ExpectedOffset: Int64): Int64;

  // Gives the offsets of all objects that a brute force search of the file finds, or nil. Not owned by the caller.
  TBruteForceOffsetsProvider = reference to function: TDictionary<TCosObjectKey, Int64>;

  // Reads the chain of xref tables, xref streams and trailers of a file into a TXrefTrailerResolver and copies the
  // result to the document
  TXrefParser = class
  private
    const DefaultTrailByteCount = 2048;
    const StartXrefMarker = 'startxref';
    const EofMarker = '%%EOF';
    const XrefMarker = 'xref';
    const TrailerMarker = 'trailer';
    const ObjMarker = 'obj';

  private
    FResolver: TXrefTrailerResolver;
    FOnSearchXRef: TXrefOffsetSearch;
    FOnGetBruteForceOffsets: TBruteForceOffsetsProvider;
    FValidateOffsets: Boolean;
    FDocument: TCosDocument;
    FSource: TRandomAccessRead;
    FParser: TBaseParser;
    FStartXref: Int64;
    FIsXRefStream: Boolean;
    FHasHybridXRef: Boolean;
    FHighestXRefObjectNumber: Int64;

    class function LastIndexOf(const Pattern: string; const Buffer: TBytes; const EndOffset: Integer): Integer; static;
    class function SplitOnSpace(const Line: string): TArray<string>; static;
    class function TryParseJavaLong(const Text: string; out Value: Int64): Boolean; static;
    class function TryParseJavaInt(const Text: string; out Value: Integer): Boolean; static;

    function IsString(const Text: string): Boolean;
    function ParseStartXref: Int64;
    function CheckXRefOffset(const StartXRefOffset: Int64): Int64;
    function CheckXRefStreamOffset(const StartXRefOffset: Int64): Boolean;
    function IsXRefStreamAt: Boolean;
    function CalculateXRefFixedOffset(const ObjectOffset: Int64): Int64;

    function ParseXrefTable(const StartByteOffset: Int64): Boolean;
    function ParseXrefTableEntries: Boolean;
    procedure ParseXrefSubsection(const FirstObjectNumber: Int64; const Count: Integer);
    procedure ParseXrefEntry(const ObjectNumber: Int64; const Fields: TArray<string>);
    function ParseTrailer: Boolean;
    function SkipExtraXrefEntries: Boolean;
    function ParseXrefObjStream(const ObjectOffset: Int64; const IsStandalone: Boolean): Int64;
    procedure ParseXrefStreamOf(const Stream: TCosStream; const ObjectOffset: Int64; const IsStandalone: Boolean);
    procedure ParseHybridXrefStream(const TrailerOfTable: TCosDictionary; const TableOffset: Int64);
    procedure ParseChain(const FirstOffset: Int64);
    function ParseChainSection(const Prev: Int64): Int64;
    procedure CopyResultToDocument;

    function ValidateXrefOffsets(const XrefOffsets: TDictionary<TCosObjectKey, Int64>): Boolean;
    function CollectCorrections(const XrefOffsets: TDictionary<TCosObjectKey, Int64>; const CorrectedKeys: TDictionary<TCosObjectKey, TCosObjectKey>; const ValidKeys: TDictionary<TCosObjectKey, Boolean>): Boolean;
    procedure ApplyCorrections(const XrefOffsets: TDictionary<TCosObjectKey, Int64>; const CorrectedKeys: TDictionary<TCosObjectKey, TCosObjectKey>; const ValidKeys: TDictionary<TCosObjectKey, Boolean>);
    procedure CheckXrefOffsets;
    function FindObjectKey(const ObjectKey: TCosObjectKey; const Offset: Int64; const XrefOffsets: TDictionary<TCosObjectKey, Int64>; out FoundKey: TCosObjectKey): Boolean;
    function SkipGarbageBeforeObject(const ObjectKey: TCosObjectKey; const Offset: Int64; const XrefOffsets: TDictionary<TCosObjectKey, Int64>): Boolean;
    function IsNearbyObjectBefore(const ObjectKey: TCosObjectKey; const Offset: Int64; const XrefOffsets: TDictionary<TCosObjectKey, Int64>): Boolean;

  public
    // The resolver is not owned: the brute force recovery shares it. It collects the sections and keeps them until Reset.
    constructor Create(const Resolver: TXrefTrailerResolver);

    // Port of getStartxrefOffset: the offset of the last "startxref" in the last TrailByteCount bytes. Raises
    // EPdfParseException without one.
    class function FindStartXrefOffset(const Source: TRandomAccessRead; const TrailByteCount: Integer = DefaultTrailByteCount): Int64; static;

    // StartXrefKeywordOffset is where the word "startxref" is (see FindStartXrefOffset). Follows the value after it, the
    // /Prev chain and /XRefStm, resolves the sections, copies the xref table to the document and the trailer to the
    // document's trailer, which it returns. A /Prev loop raises EPdfParseException. Document.Source has to stay valid
    // as long as the resolver lives: the trailer of an xref stream is a stream.
    function ParseXref(const Document: TCosDocument; const StartXrefKeywordOffset: Int64): TCosDictionary;

    // Called with the offset where a table or stream was expected and not found, to find where it really is
    property OnSearchXRef: TXrefOffsetSearch read FOnSearchXRef write FOnSearchXRef;

    // Called when the offsets of the xref table do not match the objects in the file, for the result of a brute force
    // search that replaces the table
    property OnGetBruteForceOffsets: TBruteForceOffsetsProvider read FOnGetBruteForceOffsets write FOnGetBruteForceOffsets;

    // PDFBox checks every offset of the table against the file (checkXrefOffsets) when it is lenient, which it always
    // is here. False skips that, to test the reading of the sections on its own.
    property ValidateOffsets: Boolean read FValidateOffsets write FValidateOffsets;

    // The values of the document that PDFBox sets while parsing: the first xref position, whether the last one is an
    // xref stream, whether a /XRefStm was read and the highest object number of the xref table
    property StartXref: Int64 read FStartXref;
    property IsXRefStream: Boolean read FIsXRefStream;
    property HasHybridXRef: Boolean read FHasHybridXRef;
    property HighestXRefObjectNumber: Int64 read FHighestXRefObjectNumber;
  end;

implementation

uses
  System.Generics.Defaults,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Names,
  Pdf4D.Parser.StreamObject,
  Pdf4D.Parser.XrefStream;

const
  ByteLowerX = Ord('x');
  ByteLowerT = Ord('t');
  NoOffset = -1;
  NotFoundOffset = 0;
  EntryInUse = 'n';
  EntryFree = 'f';
  MinimumEntryFields = 3;
  SectionHeaderFields = 2;
  MaxJavaIntDigits = 10;
  MinimumSearchOffset = 6;

{ TXrefParser }

constructor TXrefParser.Create(const Resolver: TXrefTrailerResolver);
begin
  inherited Create;
  FResolver := Resolver;
  FValidateOffsets := True;
end;

class function TXrefParser.LastIndexOf(const Pattern: string; const Buffer: TBytes; const EndOffset: Integer): Integer;
begin
  const LastPatternPosition = Pattern.Length - 1;
  var BufferOffset := EndOffset;
  var PatternOffset := LastPatternPosition;
  var LookupChar := Ord(Pattern[PatternOffset + 1]);

  Dec(BufferOffset);
  while BufferOffset >= 0 do
  begin
    if Buffer[BufferOffset] = LookupChar then
    begin
      Dec(PatternOffset);
      if PatternOffset < 0 then
      begin
        Exit(BufferOffset);
      end;
      LookupChar := Ord(Pattern[PatternOffset + 1]);
    end
    else if PatternOffset < LastPatternPosition then
    begin
      // No match, but some characters were matched already: start again
      PatternOffset := LastPatternPosition;
      LookupChar := Ord(Pattern[PatternOffset + 1]);
    end;
    Dec(BufferOffset);
  end;
  Result := -1;
end;

class function TXrefParser.FindStartXrefOffset(const Source: TRandomAccessRead; const TrailByteCount: Integer): Int64;
begin
  const FileLength = Source.Length;
  var TrailCount := TrailByteCount;
  if FileLength < TrailByteCount then
  begin
    TrailCount := Integer(FileLength);
  end;

  const SkipBytes = FileLength - TrailCount;
  var Buffer: TBytes;
  try
    Source.Seek(SkipBytes);
    Buffer := Source.ReadFully(TrailCount);
  finally
    Source.Seek(0);
  end;

  // The end of file marker is not required: without it the whole buffer is searched
  var BufferOffset := LastIndexOf(EofMarker, Buffer, Length(Buffer));
  if BufferOffset < 0 then
  begin
    BufferOffset := Length(Buffer);
  end;

  BufferOffset := LastIndexOf(StartXrefMarker, Buffer, BufferOffset);
  if BufferOffset < 0 then
  begin
    raise EPdfParseException.Create('Missing ''startxref'' marker.');
  end;
  Result := SkipBytes + BufferOffset;
end;

// Splits like String.split("\s") of Java: every white space character separates and trailing empty parts are dropped.
// A line without white space is returned as it is.
class function TXrefParser.SplitOnSpace(const Line: string): TArray<string>;
begin
  const Parts = TList<string>.Create;
  try
    var Start := 1;
    for var Position := 1 to Line.Length do
    begin
      const Character = Line[Position];
      const IsSeparator = ((Character = ' ') or (Character = #9) or (Character = #10) or (Character = #11) or (Character = #12) or (Character = #13));
      if IsSeparator then
      begin
        Parts.Add(Line.Substring(Start - 1, Position - Start));
        Start := Position + 1;
      end;
    end;

    if Parts.Count = 0 then
    begin
      SetLength(Result, 1);
      Result[0] := Line;
      Exit;
    end;

    Parts.Add(Line.Substring(Start - 1));
    while (Parts.Count > 0) and (Parts[Parts.Count - 1] = '') do
    begin
      Parts.Delete(Parts.Count - 1);
    end;
    Result := Parts.ToArray;
  finally
    Parts.Free;
  end;
end;

// Like Long.parseLong: an optional sign and decimal digits only
class function TXrefParser.TryParseJavaLong(const Text: string; out Value: Int64): Boolean;
begin
  Value := 0;
  var Position := 1;
  var IsNegative := False;
  if (Text.Length > 0) and ((Text[1] = '-') or (Text[1] = '+')) then
  begin
    IsNegative := (Text[1] = '-');
    Inc(Position);
  end;

  if Position > Text.Length then
  begin
    Exit(False);
  end;

  var Magnitude: UInt64 := 0;
  var Limit: UInt64 := High(Int64);
  if IsNegative then
  begin
    Inc(Limit);
  end;
  while Position <= Text.Length do
  begin
    const Character = Text[Position];
    const IsDigit = ((Character >= '0') and (Character <= '9'));
    if not IsDigit then
    begin
      Exit(False);
    end;

    const Digit: UInt64 = Ord(Character) - Ord('0');
    if Magnitude > (Limit - Digit) div 10 then
    begin
      Exit(False);
    end;
    Magnitude := Magnitude * 10 + Digit;
    Inc(Position);
  end;

  if IsNegative then
  begin
    Value := -Int64(Magnitude - 1) - 1;
  end
  else
  begin
    Value := Int64(Magnitude);
  end;
  Result := True;
end;

class function TXrefParser.TryParseJavaInt(const Text: string; out Value: Integer): Boolean;
begin
  Value := 0;
  var Parsed: Int64;
  Result := (TryParseJavaLong(Text, Parsed) and (Parsed >= Low(Integer)) and (Parsed <= High(Integer)));
  if Result then
  begin
    Value := Integer(Parsed);
  end;
end;

function TXrefParser.IsString(const Text: string): Boolean;
begin
  const Origin = FSource.GetPosition;
  Result := True;
  for var Character in Text do
  begin
    if FSource.Read <> Ord(Character) then
    begin
      Result := False;
      Break;
    end;
  end;
  FSource.Seek(Origin);
end;

// The value after the word startxref, or -1 when the word is not there. The word may be followed by a number only.
function TXrefParser.ParseStartXref: Int64;
begin
  Result := NoOffset;
  if IsString(StartXrefMarker) then
  begin
    FParser.ReadString;
    FParser.SkipSpaces;
    Result := FParser.ReadLong;
  end;
end;

function TXrefParser.IsXRefStreamAt: Boolean;
begin
  FParser.ReadObjectNumber;
  FParser.ReadGenerationNumber;
  FParser.ReadExpectedString(ObjMarker);

  const Dictionary = FParser.ParseCosDictionary(False);
  try
    Result := (Dictionary.GetNameAsString(TCosNames.Type_, '') = TCosNames.XRef);
  finally
    Dictionary.Free;
  end;
end;

// The offset has to be preceded by white space and an object number, and the object has to be an xref stream
function TXrefParser.CheckXRefStreamOffset(const StartXRefOffset: Int64): Boolean;
begin
  Result := False;
  if StartXRefOffset = 0 then
  begin
    Exit(True);
  end;

  FSource.Seek(StartXRefOffset - 1);
  const PrecedingByte = FSource.Read;
  if not TBaseParser.IsWhitespace(PrecedingByte) then
  begin
    Exit;
  end;

  FParser.SkipSpaces;
  if not TBaseParser.IsDigit(FSource.Peek) then
  begin
    Exit;
  end;

  try
    Result := IsXRefStreamAt;
    FSource.Seek(StartXRefOffset);
  except
    on EPdfParseException do
    begin
      FDocument.Log.Debug('No Xref stream at given location %d', [StartXRefOffset]);
      FSource.Seek(StartXRefOffset);
    end;
  end;
end;

function TXrefParser.CalculateXRefFixedOffset(const ObjectOffset: Int64): Int64;
begin
  if ObjectOffset < 0 then
  begin
    FDocument.Log.Error('Invalid object offset %d when searching for a xref table/stream', [ObjectOffset]);
    Exit(NotFoundOffset);
  end;

  var NewOffset: Int64 := NoOffset;
  if Assigned(FOnSearchXRef) then
  begin
    NewOffset := FOnSearchXRef(ObjectOffset);
  end;

  if NewOffset > NoOffset then
  begin
    FDocument.Log.Debug('Fixed reference for xref table/stream %d -> %d', [ObjectOffset, NewOffset]);
    Exit(NewOffset);
  end;

  FDocument.Log.Error('Can''t find the object xref table/stream at offset %d', [ObjectOffset]);
  Result := NotFoundOffset;
end;

// Checks that a table or a stream is at the offset; gives the offset to use instead when it is not, or -1
function TXrefParser.CheckXRefOffset(const StartXRefOffset: Int64): Int64;
begin
  FSource.Seek(StartXRefOffset);
  FParser.SkipSpaces;
  if IsString(XrefMarker) then
  begin
    Exit(StartXRefOffset);
  end;

  if StartXRefOffset > 0 then
  begin
    if CheckXRefStreamOffset(StartXRefOffset) then
    begin
      Exit(StartXRefOffset);
    end;
    Exit(CalculateXRefFixedOffset(StartXRefOffset));
  end;
  Result := NoOffset;
end;

procedure TXrefParser.ParseXrefEntry(const ObjectNumber: Int64; const Fields: TArray<string>);
begin
  if Fields[High(Fields)] = EntryInUse then
  begin
    var Offset: Int64;
    if not TryParseJavaLong(Fields[0], Offset) then
    begin
      raise EPdfParseException.CreateFmt('Invalid offset ''%s'' in XRefTable entry of object %d', [Fields[0], ObjectNumber]);
    end;

    // An offset of 0 is skipped
    if Offset > 0 then
    begin
      var Generation: Integer;
      if not TryParseJavaInt(Fields[1], Generation) then
      begin
        raise EPdfParseException.CreateFmt('Invalid generation ''%s'' in XRefTable entry of object %d', [Fields[1], ObjectNumber]);
      end;
      FResolver.SetXref(TCosObjectKey.Make(ObjectNumber, Generation), Offset);
    end;
  end
  else if Fields[2] <> EntryFree then
  begin
    raise EPdfParseException.CreateFmt('Corrupt XRefTable Entry - ObjID:%d', [ObjectNumber]);
  end;
end;

procedure TXrefParser.ParseXrefSubsection(const FirstObjectNumber: Int64; const Count: Integer);
begin
  var ObjectNumber := FirstObjectNumber;
  FParser.SkipSpaces;
  for var Counter := 1 to Count do
  begin
    const IsAtEnd = (FSource.IsEOF or TBaseParser.IsEndOfName(FSource.Peek));
    if IsAtEnd or (FSource.Peek = ByteLowerT) then
    begin
      Break;
    end;

    const Line = FParser.ReadLine;
    const Fields = SplitOnSpace(Line);
    if Length(Fields) < MinimumEntryFields then
    begin
      FDocument.Log.Warning('invalid xref line: %s', [Line]);
      Break;
    end;

    ParseXrefEntry(ObjectNumber, Fields);
    Inc(ObjectNumber);
    FParser.SkipSpaces;
  end;
end;

// Each subsection starts with the first object number and the count
function TXrefParser.ParseXrefTableEntries: Boolean;
begin
  repeat
    const Line = FParser.ReadLine;
    const Fields = SplitOnSpace(Line);
    if Length(Fields) <> SectionHeaderFields then
    begin
      FDocument.Log.Warning('Unexpected XRefTable Entry: %s', [Line]);
      Exit(False);
    end;

    var FirstObjectNumber: Int64;
    if not TryParseJavaLong(Fields[0], FirstObjectNumber) then
    begin
      FDocument.Log.Warning('XRefTable: invalid ID for the first object: %s', [Line]);
      Exit(False);
    end;

    var Count: Integer;
    if not TryParseJavaInt(Fields[1], Count) then
    begin
      FDocument.Log.Warning('XRefTable: invalid number of objects: %s', [Line]);
      Exit(False);
    end;

    ParseXrefSubsection(FirstObjectNumber, Count);
    FParser.SkipSpaces;
  until not TBaseParser.IsDigit(FSource.Peek);
  Result := True;
end;

function TXrefParser.ParseXrefTable(const StartByteOffset: Int64): Boolean;
begin
  if FSource.Peek <> ByteLowerX then
  begin
    Exit(False);
  end;

  if FParser.ReadString.Trim <> XrefMarker then
  begin
    Exit(False);
  end;

  // A trailer straight after the keyword is an empty table
  const NextWord = FParser.ReadString;
  FSource.Rewind(NextWord.Length);

  FResolver.NextXrefObj(StartByteOffset, TXrefType.Table);

  if NextWord.StartsWith(TrailerMarker) then
  begin
    FDocument.Log.Warning('skipping empty xref table', []);
    Exit(False);
  end;

  Result := ParseXrefTableEntries;
end;

// Some files have xref entries after the table that the table does not count (PDFBOX-1739)
function TXrefParser.SkipExtraXrefEntries: Boolean;
begin
  const TrailerOffset = FSource.GetPosition;
  var NextCharacter := FSource.Peek;
  while (NextCharacter <> ByteLowerT) and TBaseParser.IsDigit(NextCharacter) do
  begin
    if FSource.GetPosition = TrailerOffset then
    begin
      FDocument.Log.Warning('Expected trailer object at offset %d, keep trying', [TrailerOffset]);
    end;
    FParser.ReadLine;
    NextCharacter := FSource.Peek;
  end;
  Result := (FSource.Peek = ByteLowerT);
end;

function TXrefParser.ParseTrailer: Boolean;
begin
  if not SkipExtraXrefEntries then
  begin
    Exit(False);
  end;

  const CurrentOffset = FSource.GetPosition;
  const NextLine = FParser.ReadLine;
  if NextLine.Trim <> TrailerMarker then
  begin
    // The line break may be missing, the dictionary then follows the word at once
    if not NextLine.StartsWith(TrailerMarker) then
    begin
      Exit(False);
    end;
    FSource.Seek(CurrentOffset + TrailerMarker.Length);
  end;

  FParser.SkipSpaces;
  FResolver.SetTrailer(FParser.ParseCosDictionary(True));
  FParser.SkipSpaces;
  Result := True;
end;

procedure TXrefParser.ParseXrefStreamOf(const Stream: TCosStream; const ObjectOffset: Int64; const IsStandalone: Boolean);
begin
  // The cross reference stream of a hybrid file is added to the table that exists, without a new section or trailer
  if IsStandalone then
  begin
    FResolver.NextXrefObj(ObjectOffset, TXrefType.Stream);
    FResolver.SetTrailer(Stream);
  end;

  const StreamParser = TXrefStreamParser.Create(Stream, FDocument);
  try
    StreamParser.Parse(FResolver);
  finally
    StreamParser.Free;
  end;
end;

// The object that holds the xref stream. Gives the value of /Prev, or -1.
function TXrefParser.ParseXrefObjStream(const ObjectOffset: Int64; const IsStandalone: Boolean): Int64;
begin
  FParser.ReadObjectNumber;
  FParser.ReadGenerationNumber;
  FParser.ReadExpectedString(ObjMarker);

  const Dictionary = FParser.ParseCosDictionary(False);
  try
    const StreamReader = TStreamObjectReader.Create(FParser, FDocument);
    try
      const Stream = StreamReader.ParseCosStream(Dictionary);
      if IsStandalone then
      begin
        // The resolver owns the stream from the first thing ParseXrefStreamOf does
        ParseXrefStreamOf(Stream, ObjectOffset, IsStandalone);
      end
      else
      begin
        try
          ParseXrefStreamOf(Stream, ObjectOffset, IsStandalone);
        finally
          Stream.Free;
        end;
      end;
    finally
      StreamReader.Free;
    end;
    Result := Dictionary.GetLong(TCosNames.Prev, NoOffset);
  finally
    Dictionary.Free;
  end;
end;

// The xref stream of a hybrid file: its entries join the table that was read. A damaged one is only logged.
procedure TXrefParser.ParseHybridXrefStream(const TrailerOfTable: TCosDictionary; const TableOffset: Int64);
begin
  var StreamOffset := Int64(TrailerOfTable.GetInt(TCosNames.XRefStm, NoOffset));
  const FixedOffset = CheckXRefOffset(StreamOffset);
  if (FixedOffset > NoOffset) and (FixedOffset <> StreamOffset) then
  begin
    FDocument.Log.Warning('/XRefStm offset %d is incorrect, corrected to %d', [StreamOffset, FixedOffset]);
    StreamOffset := FixedOffset;
    TrailerOfTable.SetItem(TCosNames.XRefStm, TCosInteger.Create(StreamOffset));
  end;

  if StreamOffset <= 0 then
  begin
    FDocument.Log.Error('Skipped XRef stream due to a corrupt offset:%d', [StreamOffset]);
    Exit;
  end;

  FSource.Seek(StreamOffset);
  FParser.SkipSpaces;
  try
    ParseXrefObjStream(TableOffset, False);
    FHasHybridXRef := True;
  except
    on Failure: EPdfException do
    begin
      FDocument.Log.Error('Failed to parse /XRefStm at offset %d: %s', [StreamOffset, Failure.Message]);
    end;
  end;
end;

// Reads the section at Prev (a table with its trailer or an xref stream) and gives the /Prev it points to
function TXrefParser.ParseChainSection(const Prev: Int64): Int64;
begin
  var Trailer: TCosDictionary;
  if FSource.Peek = ByteLowerX then
  begin
    if (not ParseXrefTable(Prev)) or (not ParseTrailer) then
    begin
      raise EPdfParseException.CreateFmt('Expected trailer object at offset %d', [FSource.GetPosition]);
    end;

    Trailer := FResolver.GetCurrentTrailer;
    if Trailer.ContainsKey(TCosNames.XRefStm) then
    begin
      ParseHybridXrefStream(Trailer, Prev);
    end;
    Result := Trailer.GetLong(TCosNames.Prev, NoOffset);
  end
  else
  begin
    Result := ParseXrefObjStream(Prev, True);
    Trailer := FResolver.GetCurrentTrailer;
  end;

  if Result > 0 then
  begin
    const FixedOffset = CheckXRefOffset(Result);
    if (FixedOffset > NoOffset) and (FixedOffset <> Result) then
    begin
      Result := FixedOffset;
      Trailer.SetItem(TCosNames.Prev, TCosInteger.Create(Result));
    end;
  end;
end;

// Follows /Prev from the first section. A section that is read twice raises, which ends a loop.
procedure TXrefParser.ParseChain(const FirstOffset: Int64);
begin
  const SeenOffsets = TDictionary<Int64, Boolean>.Create;
  try
    var Prev := FirstOffset;
    while Prev > 0 do
    begin
      SeenOffsets.AddOrSetValue(Prev, True);
      FSource.Seek(Prev);
      FParser.SkipSpaces;
      SeenOffsets.AddOrSetValue(FSource.GetPosition, True);

      Prev := ParseChainSection(Prev);
      if SeenOffsets.ContainsKey(Prev) then
      begin
        FDocument.Log.Warning('/Prev loop at offset %d', [Prev]);
        raise EPdfParseException.CreateFmt('/Prev loop at offset %d', [Prev]);
      end;
    end;
  finally
    SeenOffsets.Free;
  end;
end;

procedure TXrefParser.CopyResultToDocument;
begin
  FDocument.StartXref := FStartXref;
  FDocument.HasHybridXRef := FHasHybridXRef;
  TXrefTrailerResolver.CopyEntries(FResolver.GetTrailer, FDocument.Trailer);
  FIsXRefStream := (FResolver.GetXrefType = TXrefType.Stream);

  FHighestXRefObjectNumber := 0;
  for var Entry in FResolver.GetXrefTable do
  begin
    FDocument.XrefTable.AddOrSetValue(Entry.Key, Entry.Value);
    if Entry.Key.Number > FHighestXRefObjectNumber then
    begin
      FHighestXRefObjectNumber := Entry.Key.Number;
    end;
  end;
  FDocument.IsXRefStream := FIsXRefStream;
  FDocument.HighestXRefObjectNumber := FHighestXRefObjectNumber;
end;

function TXrefParser.IsNearbyObjectBefore(const ObjectKey: TCosObjectKey; const Offset: Int64; const XrefOffsets: TDictionary<TCosObjectKey, Int64>): Boolean;
begin
  var Current := FSource.GetPosition;
  Dec(Current);
  FSource.Seek(Current);
  while TBaseParser.IsDigit(FSource.Peek) do
  begin
    Dec(Current);
    FSource.Seek(Current);
  end;

  const NewObjectNumber = FParser.ReadObjectNumber;
  const NewGenerationNumber = FParser.ReadGenerationNumber;
  const NewKey = TCosObjectKey.Make(NewObjectNumber, NewGenerationNumber);
  var ExistingOffset: Int64;
  // The found object number belongs to another uncompressed object at the same or nearby offset: something has to be wrong
  Result := (XrefOffsets.TryGetValue(NewKey, ExistingOffset) and (ExistingOffset > 0) and (Abs(Offset - ExistingOffset) < 10));
  if Result then
  begin
    FDocument.Log.Debug('Found the object %s instead of %s at offset %d - ignoring', [NewKey.ToString, ObjectKey.ToString, Offset]);
  end
  else
  begin
    // Something seems to be wrong but it is hard to determine what exactly: simply continue
    FSource.Seek(Offset);
  end;
end;

// At least one white space has to be in front of the object number. False when another object is found there.
function TXrefParser.SkipGarbageBeforeObject(const ObjectKey: TCosObjectKey; const Offset: Int64; const XrefOffsets: TDictionary<TCosObjectKey, Int64>): Boolean;
begin
  Result := True;
  FSource.Seek(Offset - 1);
  if FSource.GetPosition >= Offset then
  begin
    Exit;
  end;

  if not TBaseParser.IsDigit(FSource.Peek) then
  begin
    // Anything else but a digit may be some garbage of the previous object: just ignore it
    FSource.Read;
  end
  else
  begin
    Result := not IsNearbyObjectBefore(ObjectKey, Offset, XrefOffsets);
  end;
end;

// Port of findObjectKey: gives the key of the object that is at the offset, which differs from ObjectKey when the
// generation or the number is not the one of the xref entry
function TXrefParser.FindObjectKey(const ObjectKey: TCosObjectKey; const Offset: Int64; const XrefOffsets: TDictionary<TCosObjectKey, Int64>; out FoundKey: TCosObjectKey): Boolean;
begin
  FoundKey := ObjectKey;
  Result := False;
  // There cannot be any object at the very beginning of a PDF
  if Offset < MinimumSearchOffset then
  begin
    Exit;
  end;

  try
    FSource.Seek(Offset);
    FParser.SkipWhiteSpaces;
    if (FSource.GetPosition = Offset) and not SkipGarbageBeforeObject(ObjectKey, Offset, XrefOffsets) then
    begin
      Exit;
    end;

    const FoundObjectNumber = FParser.ReadObjectNumber;
    var ExpectedKey := ObjectKey;
    if ObjectKey.Number <> FoundObjectNumber then
    begin
      FDocument.Log.Warning('found wrong object number. expected [%d] found [%d]', [ObjectKey.Number, FoundObjectNumber]);
      ExpectedKey := TCosObjectKey.Make(FoundObjectNumber, ObjectKey.Generation);
    end;

    const GenerationNumber = FParser.ReadGenerationNumber;
    FParser.ReadExpectedString(ObjMarker);
    if GenerationNumber = ExpectedKey.Generation then
    begin
      FoundKey := ExpectedKey;
      Result := True;
    end
    else if GenerationNumber > ExpectedKey.Generation then
    begin
      FoundKey := TCosObjectKey.Make(ExpectedKey.Number, GenerationNumber);
      Result := True;
    end;
  except
    on EPdfParseException do
    begin
      // Obviously there is no valid object number
      FDocument.Log.Debug('No valid object at given location %d - ignoring', [Offset]);
    end;
  end;
end;

// False as soon as one entry cannot be dereferenced: the table is not usable then
function TXrefParser.CollectCorrections(const XrefOffsets: TDictionary<TCosObjectKey, Int64>; const CorrectedKeys: TDictionary<TCosObjectKey, TCosObjectKey>; const ValidKeys: TDictionary<TCosObjectKey, Boolean>): Boolean;
begin
  Result := True;
  for var Entry in XrefOffsets.ToArray do
  begin
    // A negative offset stands for the number of an object stream: the entry is of type 2
    if Entry.Value < 0 then
    begin
      Continue;
    end;

    var FoundKey: TCosObjectKey;
    if not FindObjectKey(Entry.Key, Entry.Value, XrefOffsets, FoundKey) then
    begin
      FDocument.Log.Debug('Stop checking xref offsets as at least one (%s) couldn''t be dereferenced', [Entry.Key.ToString]);
      Exit(False);
    end;

    if FoundKey <> Entry.Key then
    begin
      CorrectedKeys.AddOrSetValue(Entry.Key, FoundKey);
    end
    else
    begin
      ValidKeys.AddOrSetValue(Entry.Key, True);
    end;
  end;
end;

procedure TXrefParser.ApplyCorrections(const XrefOffsets: TDictionary<TCosObjectKey, Int64>; const CorrectedKeys: TDictionary<TCosObjectKey, TCosObjectKey>; const ValidKeys: TDictionary<TCosObjectKey, Boolean>);
begin
  const CorrectedPointers = TDictionary<TCosObjectKey, Int64>.Create(TCosObjectKeyComparer.Create);
  try
    for var Correction in CorrectedKeys do
    begin
      // Only replace entries if the original entry does not point to a valid object
      if not ValidKeys.ContainsKey(Correction.Value) then
      begin
        CorrectedPointers.AddOrSetValue(Correction.Value, XrefOffsets[Correction.Key]);
      end;
    end;

    // Remove the old invalid entries, as some might not be replaced
    for var Correction in CorrectedKeys do
    begin
      XrefOffsets.Remove(Correction.Key);
    end;

    for var Pointer in CorrectedPointers do
    begin
      XrefOffsets.AddOrSetValue(Pointer.Key, Pointer.Value);
    end;
  finally
    CorrectedPointers.Free;
  end;
end;

function TXrefParser.ValidateXrefOffsets(const XrefOffsets: TDictionary<TCosObjectKey, Int64>): Boolean;
begin
  const CorrectedKeys = TDictionary<TCosObjectKey, TCosObjectKey>.Create(TCosObjectKeyComparer.Create);
  const ValidKeys = TDictionary<TCosObjectKey, Boolean>.Create(TCosObjectKeyComparer.Create);
  try
    Result := CollectCorrections(XrefOffsets, CorrectedKeys, ValidKeys);
    if Result then
    begin
      ApplyCorrections(XrefOffsets, CorrectedKeys, ValidKeys);
    end;
  finally
    ValidKeys.Free;
    CorrectedKeys.Free;
  end;
end;

// Port of checkXrefOffsets: dereferences all objects of the table and fixes the offsets. A table that cannot be fixed
// is replaced by the result of a brute force search, when there is one.
procedure TXrefParser.CheckXrefOffsets;
begin
  const XrefOffsets = FResolver.GetXrefTable;
  if ValidateXrefOffsets(XrefOffsets) or not Assigned(FOnGetBruteForceOffsets) then
  begin
    Exit;
  end;

  const SearchResult = FOnGetBruteForceOffsets();
  if Assigned(SearchResult) and (SearchResult.Count > 0) then
  begin
    FDocument.Log.Debug('Replaced read xref table with the results of a brute force search');
    const Found = SearchResult.ToArray;
    XrefOffsets.Clear;
    for var Entry in Found do
    begin
      XrefOffsets.AddOrSetValue(Entry.Key, Entry.Value);
    end;
  end;
end;

function TXrefParser.ParseXref(const Document: TCosDocument; const StartXrefKeywordOffset: Int64): TCosDictionary;
begin
  FDocument := Document;
  FSource := Document.Source;
  FHasHybridXRef := False;
  FParser := TBaseParser.Create(FSource, Document);
  try
    FSource.Seek(StartXrefKeywordOffset);
    var StartXrefOffset := Int64(0);
    const ParsedOffset = ParseStartXref;
    if ParsedOffset > 0 then
    begin
      StartXrefOffset := ParsedOffset;
    end;

    const FixedOffset = CheckXRefOffset(StartXrefOffset);
    if FixedOffset > NoOffset then
    begin
      StartXrefOffset := FixedOffset;
    end;
    FStartXref := StartXrefOffset;

    ParseChain(StartXrefOffset);

    FResolver.SetStartxref(StartXrefOffset);
    if FValidateOffsets then
    begin
      CheckXrefOffsets;
    end;
    CopyResultToDocument;
    Result := Document.Trailer;
  finally
    FreeAndNil(FParser);
  end;
end;

end.
