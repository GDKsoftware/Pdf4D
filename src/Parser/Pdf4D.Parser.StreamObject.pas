// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdfparser/COSParser.java (3.0.8): parseCOSStream, getLength,
// validateStreamLength and readUntilEndStream, and pdfbox/src/main/java/org/apache/pdfbox/pdfparser/EndstreamFilterStream.java (3.0.8)
unit Pdf4D.Parser.StreamObject;

interface

uses
  System.SysUtils,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Document,
  Pdf4D.IO.RandomAccessRead,
  Pdf4D.Parser.Base;

type
  // The part of COSParser that the xref parsing needs: it reads the stream that follows a dictionary. The document
  // parser absorbs this class.
  TStreamObjectReader = class
  private
    const MaxLengthOfEndstreamFilterCheck = 10;

  private
    FParser: TBaseParser;
    FSource: TRandomAccessRead;
    FDocument: TCosDocument;

    class function IsString(const Source: TRandomAccessRead; const Text: string): Boolean; static;
    function TryGetLength(const Dictionary: TCosDictionary; out StreamLength: Int64): Boolean;
    function IsStreamLengthValid(const StreamLength: Int64): Boolean;
    function ReadUntilEndStream: Int64;
    function FilteredLength(const StartPosition, ContentLength: Int64): Int64;
    procedure ReadEndStreamKeyword;
    procedure LogWarning(const Fmt: string; const Args: array of const);

  public
    constructor Create(const Parser: TBaseParser; const Document: TCosDocument);

    // The parser stands after the dictionary, at the word "stream". Gives a new stream with a copy of the entries of
    // Dictionary (which stays the caller's) that reads its bytes from the source of the document. A missing or wrong
    // /Length in Dictionary is set to the length found.
    function ParseCosStream(const Dictionary: TCosDictionary): TCosStream;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.Null,
  Pdf4D.Cos.Number,
  Pdf4D.Cos.PdfObject,
  Pdf4D.Parser.XrefTrailerResolver;

const
  EndStreamKeyword = 'endstream';
  EndObjKeyword = 'endobj';
  StreamKeyword = 'stream';
  ByteLinefeed = 10;
  ByteCarriageReturn = 13;
  FirstControlByte = $09;
  LastControlByteOfText = $0A;
  FirstPrintableByte = $20;

{ TStreamObjectReader }

constructor TStreamObjectReader.Create(const Parser: TBaseParser; const Document: TCosDocument);
begin
  inherited Create;
  FParser := Parser;
  FSource := Parser.Source;
  FDocument := Document;
end;

procedure TStreamObjectReader.LogWarning(const Fmt: string; const Args: array of const);
begin
  if Assigned(FDocument) then
  begin
    FDocument.Log.Warning(Fmt, Args);
  end;
end;

class function TStreamObjectReader.IsString(const Source: TRandomAccessRead; const Text: string): Boolean;
begin
  const Origin = Source.GetPosition;
  Result := True;
  for var Character in Text do
  begin
    if Source.Read <> Ord(Character) then
    begin
      Result := False;
      Break;
    end;
  end;
  Source.Seek(Origin);
end;

// The length as a number, or False when it is missing or the object it refers to is not there
function TStreamObjectReader.TryGetLength(const Dictionary: TCosDictionary; out StreamLength: Int64): Boolean;
begin
  StreamLength := 0;
  var LengthValue := Dictionary.GetItem(TCosNames.Length);
  if not Assigned(LengthValue) then
  begin
    Exit(False);
  end;

  if LengthValue is TCosObject then
  begin
    const LengthObject = TCosObject(LengthValue);
    LengthValue := LengthObject.GetObject;
    if LengthValue is TCosNull then
    begin
      LogWarning('Length object (%s) not found', [LengthObject.Key.ToString]);
      Exit(False);
    end;
  end;

  if not (LengthValue is TCosNumber) then
  begin
    raise EPdfParseException.CreateFmt('Wrong type of length object: %s', [LengthValue.ClassName]);
  end;

  StreamLength := TCosNumber(LengthValue).LongValue;
  Result := True;
end;

function TStreamObjectReader.IsStreamLengthValid(const StreamLength: Int64): Boolean;
begin
  const OriginOffset = FSource.GetPosition;
  if StreamLength = 0 then
  begin
    // This may be valid (PDFBOX-5954), or not (PDFBOX-5880)
    Exit(False);
  end;

  if StreamLength < 0 then
  begin
    LogWarning('Invalid stream length: %d, start position: %d', [StreamLength, OriginOffset]);
    Exit(False);
  end;

  const IsOutOfRange = (StreamLength > FSource.Length - OriginOffset);
  if IsOutOfRange then
  begin
    LogWarning('The end of the stream is out of range, using workaround to read the stream, stream start position: %d, length: %d', [OriginOffset, StreamLength]);
    Exit(False);
  end;

  FSource.Seek(OriginOffset + StreamLength);
  FParser.SkipSpaces;
  const EndStreamFound = IsString(FSource, EndStreamKeyword);
  FSource.Seek(OriginOffset);
  if not EndStreamFound then
  begin
    LogWarning('The end of the stream doesn''t point to the correct offset, using workaround to read the stream, stream start position: %d, length: %d', [OriginOffset, StreamLength]);
  end;
  Result := EndStreamFound;
end;

// Port of EndstreamFilterStream: a final line break belongs to the stream keyword and not to the data, unless the data
// looks like text, and a lone carriage return stays
function TStreamObjectReader.FilteredLength(const StartPosition, ContentLength: Int64): Int64;
begin
  Result := ContentLength;
  var MustFilter := True;
  if ContentLength > MaxLengthOfEndstreamFilterCheck then
  begin
    MustFilter := False;
    FSource.Seek(StartPosition);
    for var Index := 1 to MaxLengthOfEndstreamFilterCheck do
    begin
      const Value = FSource.Read;
      const IsBinary = ((Value < FirstControlByte) or ((Value > LastControlByteOfText) and (Value < FirstPrintableByte) and (Value <> ByteCarriageReturn)));
      if IsBinary then
      begin
        MustFilter := True;
        Break;
      end;
    end;
  end;

  if (not MustFilter) or (ContentLength = 0) then
  begin
    Exit;
  end;

  FSource.Seek(StartPosition + ContentLength - 1);
  if FSource.Read <> ByteLinefeed then
  begin
    Exit;
  end;

  Dec(Result);
  if Result > 0 then
  begin
    FSource.Seek(StartPosition + Result - 1);
    if FSource.Read = ByteCarriageReturn then
    begin
      Dec(Result);
    end;
  end;
end;

// Port of readUntilEndStream: looks for "endstream", or "endobj" when that is missing, and stands at the keyword
function TStreamObjectReader.ReadUntilEndStream: Int64;
begin
  const StartPosition = FSource.GetPosition;
  var Keyword := EndStreamKeyword;
  var MatchCount := 0;
  var Found := False;
  var NextByte := FSource.Read;
  while (NextByte <> -1) and not Found do
  begin
    if NextByte = Ord(Keyword[MatchCount + 1]) then
    begin
      Inc(MatchCount);
      Found := (MatchCount = Keyword.Length);
    end
    else if (MatchCount = 3) and (NextByte = Ord(EndObjKeyword[MatchCount + 1])) then
    begin
      // The stream keyword may be missing while the object end is there
      Keyword := EndObjKeyword;
      Inc(MatchCount);
    end
    else
    begin
      // Already matched characters can be the start of a new match
      if NextByte = Ord('e') then
      begin
        MatchCount := 1;
      end
      else if (NextByte = Ord('n')) and (MatchCount = 7) then
      begin
        MatchCount := 2;
      end
      else
      begin
        MatchCount := 0;
      end;
      Keyword := EndStreamKeyword;
    end;

    if not Found then
    begin
      NextByte := FSource.Read;
    end;
  end;

  var ContentEnd := FSource.GetPosition;
  if Found then
  begin
    Dec(ContentEnd, Keyword.Length);
  end
  else
  begin
    Dec(ContentEnd, MatchCount);
  end;

  Result := FilteredLength(StartPosition, ContentEnd - StartPosition);
  if Found then
  begin
    FSource.Seek(ContentEnd);
  end
  else
  begin
    FSource.Seek(FSource.Length);
  end;
end;

procedure TStreamObjectReader.ReadEndStreamKeyword;
begin
  const EndStream = FParser.ReadString;
  if EndStream = EndObjKeyword then
  begin
    LogWarning('stream ends with ''endobj'' instead of ''endstream'' at offset %d', [FSource.GetPosition]);
    // Avoids a follow-up warning about a missing endobj
    FSource.Rewind(EndObjKeyword.Length);
  end
  else if (EndStream.Length > EndStreamKeyword.Length) and EndStream.StartsWith(EndStreamKeyword) then
  begin
    LogWarning('stream ends with ''%s'' instead of ''endstream'' at offset %d', [EndStream, FSource.GetPosition]);
    FSource.Rewind(EndStream.Length - EndStreamKeyword.Length);
  end
  else if EndStream <> EndStreamKeyword then
  begin
    raise EPdfParseException.CreateFmt('Error reading stream, expected=''endstream'' actual=''%s'' at offset %d', [EndStream, FSource.GetPosition]);
  end;
end;

function TStreamObjectReader.ParseCosStream(const Dictionary: TCosDictionary): TCosStream;
begin
  const Keyword = FParser.ReadString;
  if Keyword <> StreamKeyword then
  begin
    raise EPdfParseException.CreateFmt('Expected ''stream'' but found ''%s'' at offset %d', [Keyword, FSource.GetPosition]);
  end;
  FParser.SkipWhiteSpaces;

  var DeclaredLength: Int64;
  const HasLength = TryGetLength(Dictionary, DeclaredLength);
  if not HasLength then
  begin
    LogWarning('The stream doesn''t provide any stream length, using fallback readUntilEnd, at offset %d', [FSource.GetPosition]);
  end;

  const StreamStart = FSource.GetPosition;
  var StreamLength: Int64;
  if HasLength and IsStreamLengthValid(DeclaredLength) then
  begin
    StreamLength := DeclaredLength;
    FSource.Seek(StreamStart + StreamLength);
  end
  else
  begin
    StreamLength := ReadUntilEndStream;
    if (not HasLength) or (DeclaredLength <> StreamLength) then
    begin
      Dictionary.SetItem(TCosNames.Length, TCosInteger.Create(StreamLength));
    end;
  end;

  ReadEndStreamKeyword;

  Result := TCosStream.Create;
  try
    TXrefTrailerResolver.CopyEntries(Dictionary, Result);
    Result.SetRawSource(FSource, StreamStart, StreamLength);
    Result.Document := FDocument;
  except
    Result.Free;
    raise;
  end;
end;

end.
