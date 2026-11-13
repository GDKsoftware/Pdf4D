// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdfparser/COSParser.java (3.0.8)
// The xref parsing methods of COSParser are in Pdf4D.Parser.Xref and the stream parsing methods (parseCOSStream and
// its helpers) in Pdf4D.Parser.StreamObject: this class uses both.
unit Pdf4D.Parser.Cos;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Document,
  Pdf4D.Cos.ObjectKey,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Cos.Resolver.Interfaces,
  Pdf4D.Parser.Base,
  Pdf4D.Parser.BruteForce,
  Pdf4D.Encryption.Dictionary,
  Pdf4D.Encryption.SecurityHandler,
  Pdf4D.Encryption.StandardSecurityHandler,
  Pdf4D.Parser.Security.Interfaces,
  Pdf4D.Parser.StreamObject,
  Pdf4D.Parser.Xref,
  Pdf4D.Parser.XrefTrailerResolver;

type
  // Loads the objects of a document on demand. The parser belongs to the document (see TCosDocument.SetResolver),
  // so the interface does not count references.
  TCosParser = class(TBaseParser, ICosObjectResolver)
  private
    const PdfHeader = '%PDF-';
    const FdfHeader = '%FDF-';
    const PdfDefaultVersion = '1.4';
    const FdfDefaultVersion = '1.0';
    const DefaultHeaderVersion = 1.7;
    const HeaderVersionLength = 3;
    const ObjMarker = 'obj';
    const StreamKeyword = 'stream';
    const EndObjKeyword = 'endobj';
    const EndStreamKeyword = 'endstream';
    // Each level of the chain of loading objects (a /Length that refers to an object whose /Length refers to ...) takes
    // stack. A file does not need more than a few.
    const MaxResolveDepth = 100;
    const PublicKeyFilterName = 'Adobe.PubSec';

  private
    FDocument: TCosDocument;
    FStreamReader: TStreamObjectReader;
    FXrefResolver: TXrefTrailerResolver;
    FXrefParser: TXrefParser;
    FDecompressedObjects: TObjectDictionary<Int64, TObjectDictionary<TCosObjectKey, TCosBase>>;
    FLimitFailures: TDictionary<Int64, string>;
    FBruteForceParser: TBruteForceParser;
    FSecurityHandler: ISecurityHandler;
    FSecurityHandlerOwner: TSecurityHandler;
    FResolveDepth: Integer;
    FTrailerWasRebuilt: Boolean;

    class function IsHeaderVersionPattern(const Header: string; const Marker: string): Boolean; static;
    class function TryParseHeaderVersion(const Header: string; out Version: Single): Boolean; static;

    function ReadHeaderLine(const HeaderMarker: string): string;
    function TrimToHeader(const Header, HeaderMarker, DefaultVersion: string): string;

    function ParseObjectDynamically(const Key: TCosObjectKey; const RequireExistingNotCompressedObject: Boolean): TCosBase;
    function ParseStreamOrObjectEnd(var ParsedObject: TCosBase; const ObjectOffset: Int64; const Key: TCosObjectKey): string;
    function ReadEndOfStreamObject: string;
    procedure LogMissingEndObj(const ObjectKey, ObjectOffset: Int64; const Generation: Integer; const EndObjectKey: string);
    function TakeFromObjectStream(const StreamObjects: TObjectDictionary<TCosObjectKey, TCosBase>; const Key: TCosObjectKey): TCosBase;
    function ParseObjectStreamObjects(const ObjectStreamNumber: Int64; const Key: TCosObjectKey; const StreamObjects: TObjectDictionary<TCosObjectKey, TCosBase>): TCosBase;
    function LoadObjectStream(const ObjectStreamNumber: Int64): TCosStream;
    procedure KeepOtherObjects(const AllObjects, StreamObjects: TObjectDictionary<TCosObjectKey, TCosBase>);

    function GetBruteForceParser: TBruteForceParser;
    function PrepareBruteForceDecryption: ISecurityHandler;
    function CreateSecurityHandler(const Encryption: TPdfEncryption): TStandardSecurityHandler;
    function GetDocumentIdBytes: TBytes;
    function TryParseXref(out Message: string): Boolean;
    procedure FinishXrefParsing(const Rebuilt: Boolean);
    procedure DiscardXrefParsing;
    function CheckPagesDictionary(const PagesDictionary: TCosDictionary; const Visited: TDictionary<TCosBase, Boolean>; const Depth: Integer): Integer;
    function CheckPagesKid(const Kid: TCosBase; const Visited: TDictionary<TCosBase, Boolean>; const Removed: TList<TCosBase>; const Depth: Integer): Integer;

  protected
    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;

    // Port of parseObjectDynamically: the object that Key stands for, or nil when there is none. The caller owns it.
    function GetObjectOffset(const Key: TCosObjectKey; const RequireExistingNotCompressedObject: Boolean; out OffsetOrObjectStream: Int64): Boolean;
    function ParseFileObject(const ObjectOffset: Int64; const Key: TCosObjectKey): TCosBase;
    function ParseObjectStreamObject(const ObjectStreamNumber: Int64; const Key: TCosObjectKey): TCosBase;
    function ParseCosStream(const Dictionary: TCosDictionary): TCosStream;

    // Port of retrieveTrailer: reads the xref chain, or rebuilds the trailer, and gives the trailer of the document
    function RetrieveTrailer: TCosDictionary;

    // Port of prepareDecryption: reads /Encrypt from the trailer, checks the password of the load options and sets the security
    // handler. Raises EPdfInvalidPasswordException for a wrong password.
    procedure PrepareDecryption;

    // Port of checkPages. Raises when the page tree root is not a dictionary.
    procedure CheckPages(const Root: TCosDictionary);

    property TrailerWasRebuilt: Boolean read FTrailerWasRebuilt;
    property Document: TCosDocument read FDocument;

  public
    // The document owns the parser (it is set as its resolver by the creator) and gives the source and the log.
    constructor Create(const Document: TCosDocument);
    destructor Destroy; override;

    // The object for the key, for the TCosObject that stands for it. A load that fails is logged and gives nil, like
    // COSObject.getObject does with an IOException. The position of the source is the same afterwards.
    function ResolveObject(const Key: TCosObjectKey): TCosBase;

    // Port of parseHeader: looks for the marker in the first lines, takes the version from there and sets the version of the
    // document. False when the marker is not there.
    function ParseHeader(const HeaderMarker, DefaultVersion: string): Boolean;
    function ParsePdfHeader: Boolean;
    function ParseFdfHeader: Boolean;

    // The offset of the word "startxref" in the last 2048 bytes. Raises EPdfParseException without one.
    function GetStartxrefOffset: Int64;

    // Called before an object is decrypted, set when the file is encrypted
    property SecurityHandler: ISecurityHandler read FSecurityHandler write FSecurityHandler;
  end;

implementation

uses
  System.Classes,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Null,
  Pdf4D.Cos.PdfObject,
  Pdf4D.Cos.PdfString,
  Pdf4D.IO.RandomAccessRead,
  Pdf4D.Parser.ObjectStream;

{ TCosParser }

constructor TCosParser.Create(const Document: TCosDocument);
begin
  inherited Create(Document.Source, Document);
  FDocument := Document;
  FStreamReader := TStreamObjectReader.Create(Self, Document);
  FDecompressedObjects := TObjectDictionary<Int64, TObjectDictionary<TCosObjectKey, TCosBase>>.Create([doOwnsValues]);
  FLimitFailures := TDictionary<Int64, string>.Create;
end;

destructor TCosParser.Destroy;
begin
  DiscardXrefParsing;
  FBruteForceParser.Free;
  FSecurityHandler := nil;
  FSecurityHandlerOwner.Free;
  FDecompressedObjects.Free;
  FLimitFailures.Free;
  FStreamReader.Free;
  inherited;
end;

function TCosParser.QueryInterface(const IID: TGUID; out Obj): HResult;
begin
  if GetInterface(IID, Obj) then
  begin
    Result := 0;
  end
  else
  begin
    Result := HResult($80004002);
  end;
end;

function TCosParser._AddRef: Integer;
begin
  Result := -1;
end;

function TCosParser._Release: Integer;
begin
  Result := -1;
end;

{ header }

// A line that has the marker, the first line that starts with a digit (the data begins there) or the last line read
function TCosParser.ReadHeaderLine(const HeaderMarker: string): string;
begin
  Result := ReadLine;
  // Some PDF documents are broken and the version is in one of the following lines
  if Result.Contains(HeaderMarker) then
  begin
    Exit;
  end;

  Result := ReadLine;
  while not Result.Contains(HeaderMarker) do
  begin
    // A line that starts with a digit has to be the first one with data in it
    if (Result.Length > 0) and CharInSet(Result[1], ['0'..'9']) then
    begin
      Break;
    end;
    Result := ReadLine;
  end;
end;

// Java: header.matches(marker + "\d.\d"), where the dot is any character
class function TCosParser.IsHeaderVersionPattern(const Header: string; const Marker: string): Boolean;
begin
  const VersionStart = Marker.Length + 1;
  Result := ((Header.Length = Marker.Length + HeaderVersionLength) and
             CharInSet(Header[VersionStart], ['0'..'9']) and CharInSet(Header[VersionStart + 2], ['0'..'9']));
end;

// Port of: header.split("-") with two parts, and Float.parseFloat of the second
class function TCosParser.TryParseHeaderVersion(const Header: string; out Version: Single): Boolean;
begin
  Version := -1;
  var Parts := Header.Split(['-']);
  // Java drops the empty strings at the end
  var PartCount := Length(Parts);
  while (PartCount > 0) and (Parts[PartCount - 1] = '') do
  begin
    Dec(PartCount);
  end;

  Result := False;
  if PartCount = 2 then
  begin
    var Parsed: Double;
    Result := TryStrToFloat(Trim(Parts[1]), Parsed, TFormatSettings.Invariant);
    if Result then
    begin
      Version := Parsed;
    end;
  end;
end;

// Cuts garbage in front of the marker, and the garbage behind the version
function TCosParser.TrimToHeader(const Header, HeaderMarker, DefaultVersion: string): string;
begin
  Result := Header;
  const HeaderStart = Result.IndexOf(HeaderMarker);
  if HeaderStart > 0 then
  begin
    Result := Result.Substring(HeaderStart);
  end;

  // Garbage after the header on the same line
  if Result.StartsWith(HeaderMarker) and not IsHeaderVersionPattern(Result, HeaderMarker) then
  begin
    if Result.Length < HeaderMarker.Length + HeaderVersionLength then
    begin
      // No version number at all: 1.4 is the default
      Result := HeaderMarker + DefaultVersion;
      FDocument.Log.Debug('No version found, set to %s as default.', [DefaultVersion]);
    end
    else
    begin
      Result := Result.Substring(0, HeaderMarker.Length + HeaderVersionLength);
    end;
  end;
end;

function TCosParser.ParseHeader(const HeaderMarker, DefaultVersion: string): Boolean;
begin
  var Header := ReadHeaderLine(HeaderMarker);
  if not Header.Contains(HeaderMarker) then
  begin
    Source.Seek(0);
    Exit(False);
  end;

  Header := TrimToHeader(Header, HeaderMarker, DefaultVersion);

  var HeaderVersion: Single;
  if not TryParseHeaderVersion(Header, HeaderVersion) then
  begin
    FDocument.Log.Debug('Can''t parse the header version.');
  end;
  if HeaderVersion < 0 then
  begin
    HeaderVersion := DefaultHeaderVersion;
  end;

  FDocument.Version := HeaderVersion;
  Source.Seek(0);
  Result := True;
end;

function TCosParser.ParsePdfHeader: Boolean;
begin
  Result := ParseHeader(PdfHeader, PdfDefaultVersion);
end;

function TCosParser.ParseFdfHeader: Boolean;
begin
  Result := ParseHeader(FdfHeader, FdfDefaultVersion);
end;

function TCosParser.GetStartxrefOffset: Int64;
begin
  try
    Result := TXrefParser.FindStartXrefOffset(Source);
  finally
    Source.Seek(0);
  end;
end;

{ loading objects }

function TCosParser.ResolveObject(const Key: TCosObjectKey): TCosBase;
begin
  Result := nil;
  if FResolveDepth >= MaxResolveDepth then
  begin
    FDocument.Log.Error('Can''t dereference %s: too many objects are being loaded at once', [Key.ToString]);
    Exit;
  end;

  const CurrentPosition = Source.GetPosition;
  Inc(FResolveDepth);
  try
    try
      Result := ParseObjectDynamically(Key, False);
    except
      on Failure: Exception do
      begin
        const IsFailureOfData = ((Failure is EPdfParseException) or TPdfFailure.IsInputFailure(Failure));
        if not IsFailureOfData then
        begin
          raise;
        end;
        FDocument.Log.Error('Can''t dereference %s: %s', [Key.ToString, Failure.Message]);
        Result := nil;
      end;
    end;
  finally
    Dec(FResolveDepth);
    if CurrentPosition > 0 then
    begin
      Source.Seek(CurrentPosition);
    end;
  end;
end;

function TCosParser.GetObjectOffset(const Key: TCosObjectKey; const RequireExistingNotCompressedObject: Boolean; out OffsetOrObjectStream: Int64): Boolean;
begin
  // The offset, or the number of the object stream that holds the object as a negative number
  Result := FDocument.XrefTable.TryGetValue(Key, OffsetOrObjectStream);

  // Maybe something is wrong with the xref table: use the result of a brute force search of all objects
  if (not Result) and GetBruteForceParser.GetBFCOSObjectOffsets.TryGetValue(Key, OffsetOrObjectStream) then
  begin
    Result := True;
    FDocument.Log.Debug('Set missing offset %d for object %s', [OffsetOrObjectStream, Key.ToString]);
    FDocument.XrefTable.AddOrSetValue(Key, OffsetOrObjectStream);
  end;

  // Circumvents loops with broken documents
  if RequireExistingNotCompressedObject and ((not Result) or (OffsetOrObjectStream <= 0)) then
  begin
    raise EPdfParseException.CreateFmt('Object must be defined and must not be compressed object: %d:%d', [Key.Number, Key.Generation]);
  end;
end;

function TCosParser.ParseObjectDynamically(const Key: TCosObjectKey; const RequireExistingNotCompressedObject: Boolean): TCosBase;
begin
  Result := nil;
  var OffsetOrObjectStream: Int64;
  if not GetObjectOffset(Key, RequireExistingNotCompressedObject, OffsetOrObjectStream) then
  begin
    Exit;
  end;

  if OffsetOrObjectStream > 0 then
  begin
    Result := ParseFileObject(OffsetOrObjectStream, Key);
  end
  else
  begin
    // The value is the number of the object stream that holds the object. The object was not found yet, so the stream
    // was not parsed so far.
    Result := ParseObjectStreamObject(-OffsetOrObjectStream, Key);
  end;

  // An object that is not defined is a null object (PDF 1.7, 3.2.9)
  if Result is TCosNull then
  begin
    FreeAndNil(Result);
  end;
end;

procedure TCosParser.LogMissingEndObj(const ObjectKey, ObjectOffset: Int64; const Generation: Integer; const EndObjectKey: string);
begin
  FDocument.Log.Warning('Object (%d:%d) at offset %d does not end with ''endobj'' but with ''%s''', [ObjectKey, Generation, ObjectOffset, EndObjectKey]);
end;

// After a stream: the line that should be endobj. A second endstream in front of it is skipped.
function TCosParser.ReadEndOfStreamObject: string;
begin
  SkipSpaces;
  Result := ReadLine;

  // A case with a second 'endstream' before endobj
  if (not Result.StartsWith(EndObjKeyword)) and Result.StartsWith(EndStreamKeyword) then
  begin
    Result := Trim(Result.Substring(EndStreamKeyword.Length));
    if Result.Length = 0 then
    begin
      // No other characters in the extra endstream line: read the next line
      Result := ReadLine;
    end;
  end;
end;

// ParsedObject is read already and is followed by the word that ends it. The object is replaced by a stream when that
// word is "stream". Gives the word that ends the object.
function TCosParser.ParseStreamOrObjectEnd(var ParsedObject: TCosBase; const ObjectOffset: Int64; const Key: TCosObjectKey): string;
begin
  Result := ReadString;
  if Result = StreamKeyword then
  begin
    Source.Rewind(Result.Length);
    if not (ParsedObject is TCosDictionary) then
    begin
      // The combination of a dictionary and the stream and endstream forms a complete stream object
      raise EPdfParseException.CreateFmt('Stream not preceded by dictionary (offset: %d).', [ObjectOffset]);
    end;

    const Dictionary = TCosDictionary(ParsedObject);
    const Stream = ParseCosStream(Dictionary);
    ParsedObject := Stream;
    Dictionary.Free;

    if Assigned(FSecurityHandler) then
    begin
      FSecurityHandler.DecryptStream(Stream, Key.Number, Key.Generation);
    end;
    Result := ReadEndOfStreamObject;
  end
  else if Assigned(FSecurityHandler) then
  begin
    FSecurityHandler.Decrypt(ParsedObject, Key.Number, Key.Generation);
  end;
end;

function TCosParser.ParseFileObject(const ObjectOffset: Int64; const Key: TCosObjectKey): TCosBase;
begin
  // Jump to the object start: an indirect object starts with the object number and the generation number
  Source.Seek(ObjectOffset);
  const FoundNumber = ReadObjectNumber;
  const FoundGeneration = ReadGenerationNumber;
  ReadExpectedString(ObjMarker);

  if (FoundNumber <> Key.Number) or (FoundGeneration <> Key.Generation) then
  begin
    raise EPdfParseException.CreateFmt('XREF for %d:%d points to wrong object: %d:%d at offset %d',
                                       [Key.Number, Key.Generation, FoundNumber, FoundGeneration, ObjectOffset]);
  end;

  SkipSpaces;
  Result := ParseDirObject;
  try
    const EndObjectKey = ParseStreamOrObjectEnd(Result, ObjectOffset, Key);
    if not EndObjectKey.StartsWith(EndObjKeyword) then
    begin
      LogMissingEndObj(FoundNumber, ObjectOffset, FoundGeneration, EndObjectKey);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TCosParser.ParseCosStream(const Dictionary: TCosDictionary): TCosStream;
begin
  Result := FStreamReader.ParseCosStream(Dictionary);
end;

{ object streams }

function TCosParser.LoadObjectStream(const ObjectStreamNumber: Int64): TCosStream;
begin
  Result := nil;
  const ObjectStreamKey = TCosObjectKey.Make(ObjectStreamNumber, 0);
  const ObjectStreamBase = FDocument.GetObjectFromPool(ObjectStreamKey).GetObject;
  if ObjectStreamBase is TCosStream then
  begin
    Result := TCosStream(ObjectStreamBase);
  end;
end;

// The objects that were not asked for yet are kept, until the other objects of the stream are dereferenced
procedure TCosParser.KeepOtherObjects(const AllObjects, StreamObjects: TObjectDictionary<TCosObjectKey, TCosBase>);
begin
  for var OtherKey in AllObjects.Keys.ToArray do
  begin
    if not StreamObjects.ContainsKey(OtherKey) then
    begin
      StreamObjects.Add(OtherKey, AllObjects.ExtractPair(OtherKey).Value);
    end;
  end;
end;

function TCosParser.ParseObjectStreamObjects(const ObjectStreamNumber: Int64; const Key: TCosObjectKey; const StreamObjects: TObjectDictionary<TCosObjectKey, TCosBase>): TCosBase;
begin
  Result := nil;
  const ObjectStream = LoadObjectStream(ObjectStreamNumber);
  if not Assigned(ObjectStream) then
  begin
    Exit;
  end;

  try
    const StreamParser = TObjectStreamParser.Create(ObjectStream, FDocument);
    try
      const AllObjects = StreamParser.ParseAllObjects;
      try
        if AllObjects.ContainsKey(Key) then
        begin
          Result := AllObjects.ExtractPair(Key).Value;
        end;
        KeepOtherObjects(AllObjects, StreamObjects);
      finally
        AllObjects.Free;
      end;
    finally
      StreamParser.Free;
    end;
  except
    on Failure: Exception do
    begin
      const IsFailureOfData = ((Failure is EPdfParseException) or (Failure is EPdfUnsupportedFeatureException) or TPdfFailure.IsInputFailure(Failure));
      if not IsFailureOfData then
      begin
        raise;
      end;
      FDocument.Log.Error('object stream %d could not be parsed due to an exception: %s', [ObjectStreamNumber, Failure.Message]);
    end;
  end;
end;

function TCosParser.TakeFromObjectStream(const StreamObjects: TObjectDictionary<TCosObjectKey, TCosBase>; const Key: TCosObjectKey): TCosBase;
begin
  Result := nil;
  if StreamObjects.ContainsKey(Key) then
  begin
    Result := StreamObjects.ExtractPair(Key).Value;
  end;
end;

function TCosParser.ParseObjectStreamObject(const ObjectStreamNumber: Int64; const Key: TCosObjectKey): TCosBase;
begin
  // A stream that is over the limit stays over it: each of its keys raises, not only the first
  var LimitMessage: string;
  if FLimitFailures.TryGetValue(ObjectStreamNumber, LimitMessage) then
  begin
    raise EPdfLimitExceededException.Create(LimitMessage);
  end;

  var StreamObjects: TObjectDictionary<TCosObjectKey, TCosBase>;
  if FDecompressedObjects.TryGetValue(ObjectStreamNumber, StreamObjects) then
  begin
    // The stream was read already, or could not be read: what it holds is kept in StreamObjects. A key that is not
    // there is not in the stream, and parsing it again for each such key would be quadratic.
    Result := TakeFromObjectStream(StreamObjects, Key);
    Exit;
  end;

  StreamObjects := TObjectDictionary<TCosObjectKey, TCosBase>.Create([doOwnsValues], TCosObjectKeyComparer.Create);
  FDecompressedObjects.Add(ObjectStreamNumber, StreamObjects);
  try
    Result := ParseObjectStreamObjects(ObjectStreamNumber, Key, StreamObjects);
  except
    on Failure: EPdfLimitExceededException do
    begin
      FLimitFailures.AddOrSetValue(ObjectStreamNumber, Failure.Message);
      raise;
    end;
  end;
end;

{ trailer }

function TCosParser.GetDocumentIdBytes: TBytes;
begin
  // Some documents have no ID
  var Ids: TCosArray;
  if (not FDocument.Trailer.TryGetCosArray(TCosNames.ID, Ids)) or (Ids.Count < 1) then
  begin
    Exit(nil);
  end;

  const Id = Ids.GetObject(0);
  if not (Id is TCosString) then
  begin
    raise EPdfParseException.Create('The first item of the document ID is not a string');
  end;
  const IdString = TCosString(Id);
  Result := Copy(IdString.Bytes);
end;

function TCosParser.CreateSecurityHandler(const Encryption: TPdfEncryption): TStandardSecurityHandler;
begin
  var Filter: string;
  const HasFilter = Encryption.TryGetFilter(Filter);
  if HasFilter and (Filter = PublicKeyFilterName) then
  begin
    raise EPdfUnsupportedFeatureException.Create('Public key security is not supported');
  end;
  if (not HasFilter) or (Filter <> StandardSecurityFilterName) then
  begin
    raise EPdfUnsupportedFeatureException.CreateFmt('No security handler for filter %s', [Filter]);
  end;

  Result := TStandardSecurityHandler.Create(FDocument.Log);
end;

procedure TCosParser.PrepareDecryption;
begin
  if Assigned(FDocument.Encryption) then
  begin
    Exit;
  end;

  var EncryptionDictionary: TCosDictionary;
  if not FDocument.Trailer.TryGetCosDictionary(TCosNames.Encrypt, EncryptionDictionary) then
  begin
    Exit;
  end;

  const Encryption = TPdfEncryption.Create(EncryptionDictionary);
  try
    const Handler = CreateSecurityHandler(Encryption);
    try
      Handler.PrepareForDecryption(Encryption, GetDocumentIdBytes, FDocument.Options.Password);
    except
      Handler.Free;
      raise;
    end;

    FSecurityHandlerOwner.Free;
    FSecurityHandlerOwner := Handler;
    FSecurityHandler := Handler;
    const Permission = Handler.CurrentAccessPermission.Clone;
    FDocument.SetAccessPermission(Permission);
  except
    Encryption.Free;
    raise;
  end;
  FDocument.SetEncryption(Encryption);
end;

procedure TCosParser.DiscardXrefParsing;
begin
  FreeAndNil(FXrefParser);
  FreeAndNil(FXrefResolver);
end;

function TCosParser.PrepareBruteForceDecryption: ISecurityHandler;
begin
  PrepareDecryption;
  Result := FSecurityHandler;
end;

// PDFBox creates its BruteForceParser at the first place that needs it
function TCosParser.GetBruteForceParser: TBruteForceParser;
begin
  if not Assigned(FBruteForceParser) then
  begin
    FBruteForceParser := TBruteForceParser.Create(FDocument, PrepareBruteForceDecryption);
  end;
  Result := FBruteForceParser;
end;

// The xref chain of the file. False with the reason when it cannot be used.
function TCosParser.TryParseXref(out Message: string): Boolean;
begin
  Message := '';
  FXrefResolver := TXrefTrailerResolver.Create(FDocument.Log);
  FXrefParser := TXrefParser.Create(FXrefResolver);
  FXrefParser.OnSearchXRef :=
    function(const ExpectedOffset: Int64): Int64
    begin
      Result := GetBruteForceParser.BfSearchForXRef(ExpectedOffset);
    end;
  FXrefParser.OnGetBruteForceOffsets :=
    function: TDictionary<TCosObjectKey, Int64>
    begin
      Result := GetBruteForceParser.GetBFCOSObjectOffsets;
    end;
  try
    const StartXrefOffset = GetStartxrefOffset;
    FXrefParser.ParseXref(FDocument, StartXrefOffset);
    Result := True;
  except
    on Failure: Exception do
    begin
      const IsFailureOfData = ((Failure is EPdfParseException) or TPdfFailure.IsInputFailure(Failure));
      if not IsFailureOfData then
      begin
        raise;
      end;
      Message := Failure.Message;
      Result := False;
    end;
  end;
end;

procedure TCosParser.FinishXrefParsing(const Rebuilt: Boolean);
begin
  if Rebuilt then
  begin
    Exit;
  end;

  // Prepare decryption if necessary
  PrepareDecryption;
  // The brute force parser is only there when it was needed: do not create it just to ask
  if Assigned(FBruteForceParser) and FBruteForceParser.SearchTriggered then
  begin
    FBruteForceParser.BfSearchForObjStreams(FXrefResolver, FSecurityHandler);
  end;
end;

function TCosParser.RetrieveTrailer: TCosDictionary;
begin
  var FailureMessage := '';
  try
    const IsParsed = TryParseXref(FailureMessage);
    // Check if the trailer contains a Root object
    const NeedsRebuild = (not IsParsed) or (not Assigned(FDocument.Trailer.GetItem(TCosNames.Root)));
    if NeedsRebuild then
    begin
      FDocument.Log.Debug('The xref cannot be used, the trailer is rebuilt: %s', [FailureMessage]);
      GetBruteForceParser.RebuildTrailer(FXrefResolver);
      FTrailerWasRebuilt := True;
    end;
    FinishXrefParsing(NeedsRebuild);
  finally
    // The resolver is not needed after the first parse
    DiscardXrefParsing;
  end;
  Result := FDocument.Trailer;
end;

{ pages }

// Checks one kid of a pages dictionary. Gives the number of pages in it, and adds the kid to Removed when it has to go.
function TCosParser.CheckPagesKid(const Kid: TCosBase; const Visited: TDictionary<TCosBase, Boolean>; const Removed: TList<TCosBase>; const Depth: Integer): Integer;
begin
  Result := 0;
  const KidObject = TCosObject(Kid);
  const KidBase = KidObject.GetObject;
  if KidBase is TCosNull then
  begin
    // The object was not dereferenced: remove it
    FDocument.Log.Warning('Removed null object %s from pages dictionary', [KidObject.Key.ToString]);
    Removed.Add(Kid);
  end
  else if KidBase is TCosDictionary then
  begin
    const KidDictionary = TCosDictionary(KidBase);
    var TypeValue: TCosBase;
    var TypeName := '';
    if KidDictionary.TryGetDictionaryObject(TCosNames.Type_, TypeValue) and (TypeValue is TCosName) then
    begin
      TypeName := TCosName(TypeValue).Name;
    end;

    if TypeName = TCosNames.Pages then
    begin
      // Process nested pages dictionaries
      Visited.AddOrSetValue(Kid, True);
      Result := CheckPagesDictionary(KidDictionary, Visited, Depth + 1);
    end
    else if TypeName = TCosNames.Page then
    begin
      Result := 1;
    end;
  end;
end;

function TCosParser.CheckPagesDictionary(const PagesDictionary: TCosDictionary; const Visited: TDictionary<TCosBase, Boolean>; const Depth: Integer): Integer;
begin
  Result := 0;
  // A page tree that is nested deeper than a document can be is not followed: the parser recurses
  if Depth > MaximumNestingDepth then
  begin
    FDocument.Log.Warning('The page tree is nested too deep, the rest is not checked');
    Exit;
  end;

  var Kids: TCosArray;
  if PagesDictionary.TryGetCosArray(TCosNames.Kids, Kids) then
  begin
    // The kids that have to go are removed in one pass afterwards: removing them one by one is quadratic
    var Snapshot: TArray<TCosBase>;
    SetLength(Snapshot, Kids.Count);
    var SnapshotPosition := 0;
    for var Item in Kids do
    begin
      Snapshot[SnapshotPosition] := Item;
      Inc(SnapshotPosition);
    end;

    const Removed = TList<TCosBase>.Create;
    try
      for var Kid in Snapshot do
      begin
        if (not (Kid is TCosObject)) or Visited.ContainsKey(Kid) then
        begin
          Removed.Add(Kid);
        end
        else
        begin
          Inc(Result, CheckPagesKid(Kid, Visited, Removed, Depth));
        end;
      end;
      Kids.RemoveItems(Removed);
    finally
      Removed.Free;
    end;
  end;

  // Fix the counter
  PagesDictionary.SetItem(TCosNames.Count, TCosInteger.Create(Result));
end;

procedure TCosParser.CheckPages(const Root: TCosDictionary);
begin
  var Pages: TCosDictionary;
  if FTrailerWasRebuilt and Root.TryGetCosDictionary(TCosNames.Pages, Pages) then
  begin
    // Check if all page objects are dereferenced
    const Visited = TDictionary<TCosBase, Boolean>.Create;
    try
      CheckPagesDictionary(Pages, Visited, 0);
    finally
      Visited.Free;
    end;
  end;

  if not Root.TryGetCosDictionary(TCosNames.Pages, Pages) then
  begin
    raise EPdfParseException.Create('Page tree root must be a dictionary');
  end;
end;

end.
