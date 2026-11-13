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
  Pdf4D.IO.RandomAccessRead,
  Pdf4D.Parser.Base,
  Pdf4D.Parser.XrefTrailerResolver;

type
  // Gives the offset of the xref table or stream that a brute force search finds for the offset that was expected, or -1
  TXrefOffsetSearch = reference to function(const ExpectedOffset: Int64): Int64;

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
  Pdf4D.Cos.ObjectKey,
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

{ TXrefParser }

constructor TXrefParser.Create(const Resolver: TXrefTrailerResolver);
begin
  inherited Create;
  FResolver := Resolver;
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
    CopyResultToDocument;
    Result := Document.Trailer;
  finally
    FreeAndNil(FParser);
  end;
end;

end.
