// Port of: pdfbox/src/main/java/org/apache/pdfbox/cos/COSDictionary.java and COSStream.java (3.0.8)
// TCosStream lives in this unit because TCosDictionary.TryGetCosStream needs the type and Delphi cannot
// forward declare a class across units.
unit Pdf4D.Cos.Dictionary;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Pdf4D.Common.Log,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Cos.Base,
  Pdf4D.IO.RandomAccessRead;

type
  TCosStream = class;

  // Keeps the order of insertion. Owns its values, except TCosObject values: those belong to the document.
  TCosDictionary = class(TCosBase)
  private
    type
      // Ownership is decided when a value is stored. A destructor must not look at a TCosObject value again:
      // the document may have freed that proxy already.
      TEntry = record
        Key: string;
        Value: TCosBase;
        Owned: Boolean;
      end;

  private
    FItems: TList<TEntry>;
    FIndex: TDictionary<string, Integer>;

    function GetCount: Integer;
    function NewEntry(const Key: string; const Value: TCosBase): TEntry;
    procedure RebuildIndex;
    procedure ReplaceValue(const Position: Integer; const Value: TCosBase);

  public
    constructor Create;
    destructor Destroy; override;

    // The dictionary takes ownership, except of a TCosObject. A nil removes the key, like COSDictionary.setItem.
    // A replaced value is freed.
    procedure SetItem(const Key: string; const Value: TCosBase);

    // The raw value, a TCosObject is not resolved. This is the only getter that gives nil: for a missing key,
    // like COSDictionary.getItem.
    function GetItem(const Key: string): TCosBase;

    // The value with an indirect reference resolved. A TCosNull counts as absent.
    function TryGetDictionaryObject(const Key: string; out Value: TCosBase): Boolean;

    function GetInt(const Key: string; const Default: Integer): Integer;
    function GetLong(const Key: string; const Default: Int64): Int64;
    function GetFloat(const Key: string; const Default: Single): Single;
    function GetBoolean(const Key: string; const Default: Boolean): Boolean;
    function GetNameAsString(const Key: string; const Default: string): string;
    function GetString(const Key: string; const Default: string): string;

    function TryGetCosArray(const Key: string; out Value: TCosArray): Boolean;
    // A stream is a dictionary too, like COSStream extends COSDictionary
    function TryGetCosDictionary(const Key: string; out Value: TCosDictionary): Boolean;
    function TryGetCosStream(const Key: string; out Value: TCosStream): Boolean;

    function ContainsKey(const Key: string): Boolean;
    procedure RemoveItem(const Key: string);

    // Removes all entries and frees the values the dictionary owns
    procedure Clear;
    function Keys: TArray<string>;

    property Count: Integer read GetCount;
  end;

  TPdfDecodedData = record
    Data: TBytes;
    RemainingFilters: TArray<string>;
  end;

  // The raw bytes come from the data of the document (the source is not owned) or from bytes set directly.
  TCosStream = class(TCosDictionary)
  private
    FSource: TRandomAccessRead;
    FOffset: Int64;
    FLength: Int64;
    FRawData: TBytes;
    FHasRawData: Boolean;
    FDecryptor: TFunc<TBytes, TBytes>;
    FDocument: TObject;

    function ReadSourceBytes: TBytes;
    function GetRawBytes: TBytes;
    function MaxDecodedSize: Int64;
    function DocumentLog: TPdfLog;
    procedure SetDocument(const Value: TObject);

  public
    // The source belongs to the document and has to outlive the stream
    procedure SetRawSource(const Source: TRandomAccessRead; const Offset, Length: Int64);
    procedure SetRawData(const Data: TBytes);

    // The bytes as stored in the file, decrypted but not decoded. A copy: the caller owns the stream and
    // it stays valid after the document is freed.
    function CreateRawStream: TStream;

    // The first MaxCount bytes (or fewer when the stream is shorter) as stored in the file, without decryption. Reads only
    // those bytes.
    function ReadRawPrefix(const MaxCount: Integer): TBytes;

    // The names in /Filter, in order: empty without a filter. The names are as written, so an abbreviation stays one.
    function GetFilterNames: TArray<string>;

    // The data with all filters applied, for the caller to own. An image filter and an unknown filter raise
    // EPdfUnsupportedFeatureException, a result over the decoded size limit of the document raises
    // EPdfLimitExceededException.
    function CreateDecodedStream: TStream;

    // The data decoded up to the first image filter, with the names of the filters that are left. Without an
    // image filter nothing is left. Raises like CreateDecodedStream for an unknown filter.
    function DecodeUntilImageFilter: TPdfDecodedData;

    // The document (a TCosDocument) whose options give the limit on the decoded size and whose log receives the
    // problems of decoding. Not owned, may be nil: the default limit applies and nothing is logged.
    property Document: TObject read FDocument write SetDocument;

    // Applied to the bytes read from the source, set by the security handler. Not applied to SetRawData.
    property Decryptor: TFunc<TBytes, TBytes> read FDecryptor write FDecryptor;
  end;

implementation

uses
  System.Math,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Boolean,
  Pdf4D.Cos.Document,
  Pdf4D.Filter.Chain,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.Null,
  Pdf4D.Cos.Number,
  Pdf4D.Cos.PdfObject,
  Pdf4D.Cos.PdfString;

{ TCosDictionary }

constructor TCosDictionary.Create;
begin
  inherited Create;
  FItems := TList<TEntry>.Create;
  FIndex := TDictionary<string, Integer>.Create;
end;

destructor TCosDictionary.Destroy;
begin
  for var Item in FItems do
  begin
    if Item.Owned then
    begin
      Item.Value.Free;
    end;
  end;
  FItems.Free;
  FIndex.Free;
  inherited;
end;

procedure TCosDictionary.SetItem(const Key: string; const Value: TCosBase);
begin
  if not Assigned(Value) then
  begin
    RemoveItem(Key);
    Exit;
  end;

  var Position: Integer;
  if FIndex.TryGetValue(Key, Position) then
  begin
    ReplaceValue(Position, Value);
    Exit;
  end;

  FItems.Add(NewEntry(Key, Value));
  FIndex.Add(Key, FItems.Count - 1);
end;

function TCosDictionary.GetItem(const Key: string): TCosBase;
begin
  var Position: Integer;
  if FIndex.TryGetValue(Key, Position) then
  begin
    Result := FItems[Position].Value;
  end
  else
  begin
    Result := nil;
  end;
end;

function TCosDictionary.TryGetDictionaryObject(const Key: string; out Value: TCosBase): Boolean;
begin
  Value := GetItem(Key);
  if Value is TCosObject then
  begin
    Value := TCosObject(Value).GetObject;
  end;

  Result := (Assigned(Value) and not (Value is TCosNull));
  if not Result then
  begin
    Value := nil;
  end;
end;

function TCosDictionary.GetInt(const Key: string; const Default: Integer): Integer;
begin
  var Value: TCosBase;
  if TryGetDictionaryObject(Key, Value) and (Value is TCosNumber) then
  begin
    Result := TCosNumber(Value).IntValue;
  end
  else
  begin
    Result := Default;
  end;
end;

function TCosDictionary.GetLong(const Key: string; const Default: Int64): Int64;
begin
  var Value: TCosBase;
  if TryGetDictionaryObject(Key, Value) and (Value is TCosNumber) then
  begin
    Result := TCosNumber(Value).LongValue;
  end
  else
  begin
    Result := Default;
  end;
end;

function TCosDictionary.GetFloat(const Key: string; const Default: Single): Single;
begin
  var Value: TCosBase;
  if TryGetDictionaryObject(Key, Value) and (Value is TCosNumber) then
  begin
    Result := TCosNumber(Value).FloatValue;
  end
  else
  begin
    Result := Default;
  end;
end;

function TCosDictionary.GetBoolean(const Key: string; const Default: Boolean): Boolean;
begin
  var Value: TCosBase;
  if TryGetDictionaryObject(Key, Value) and (Value is TCosBoolean) then
  begin
    Result := TCosBoolean(Value).Value;
  end
  else
  begin
    Result := Default;
  end;
end;

function TCosDictionary.GetNameAsString(const Key: string; const Default: string): string;
begin
  var Value: TCosBase;
  Result := Default;
  if not TryGetDictionaryObject(Key, Value) then
  begin
    Exit;
  end;

  // Like COSDictionary.getNameAsString, a string is accepted as well
  if Value is TCosName then
  begin
    Result := TCosName(Value).Name;
  end
  else if Value is TCosString then
  begin
    Result := TCosString(Value).GetString;
  end;
end;

function TCosDictionary.GetString(const Key: string; const Default: string): string;
begin
  var Value: TCosBase;
  if TryGetDictionaryObject(Key, Value) and (Value is TCosString) then
  begin
    Result := TCosString(Value).GetString;
  end
  else
  begin
    Result := Default;
  end;
end;

function TCosDictionary.TryGetCosArray(const Key: string; out Value: TCosArray): Boolean;
begin
  var Item: TCosBase;
  Result := (TryGetDictionaryObject(Key, Item) and (Item is TCosArray));
  if Result then
  begin
    Value := TCosArray(Item);
  end
  else
  begin
    Value := nil;
  end;
end;

function TCosDictionary.TryGetCosDictionary(const Key: string; out Value: TCosDictionary): Boolean;
begin
  var Item: TCosBase;
  Result := (TryGetDictionaryObject(Key, Item) and (Item is TCosDictionary));
  if Result then
  begin
    Value := TCosDictionary(Item);
  end
  else
  begin
    Value := nil;
  end;
end;

function TCosDictionary.TryGetCosStream(const Key: string; out Value: TCosStream): Boolean;
begin
  var Item: TCosBase;
  Result := (TryGetDictionaryObject(Key, Item) and (Item is TCosStream));
  if Result then
  begin
    Value := TCosStream(Item);
  end
  else
  begin
    Value := nil;
  end;
end;

function TCosDictionary.ContainsKey(const Key: string): Boolean;
begin
  Result := FIndex.ContainsKey(Key);
end;

procedure TCosDictionary.RemoveItem(const Key: string);
begin
  var Position: Integer;
  if not FIndex.TryGetValue(Key, Position) then
  begin
    Exit;
  end;

  const Removed = FItems[Position];
  FItems.Delete(Position);
  RebuildIndex;
  if Removed.Owned then
  begin
    Removed.Value.Free;
  end;
end;

procedure TCosDictionary.Clear;
begin
  for var Item in FItems do
  begin
    if Item.Owned then
    begin
      Item.Value.Free;
    end;
  end;
  FItems.Clear;
  FIndex.Clear;
end;

function TCosDictionary.Keys: TArray<string>;
begin
  SetLength(Result, FItems.Count);
  for var Index := 0 to FItems.Count - 1 do
  begin
    Result[Index] := FItems[Index].Key;
  end;
end;

function TCosDictionary.GetCount: Integer;
begin
  Result := FItems.Count;
end;

function TCosDictionary.NewEntry(const Key: string; const Value: TCosBase): TEntry;
begin
  Result.Key := Key;
  Result.Value := Value;
  Result.Owned := not (Value is TCosObject);
end;

procedure TCosDictionary.RebuildIndex;
begin
  FIndex.Clear;
  for var Position := 0 to FItems.Count - 1 do
  begin
    FIndex.Add(FItems[Position].Key, Position);
  end;
end;

procedure TCosDictionary.ReplaceValue(const Position: Integer; const Value: TCosBase);
begin
  const Previous = FItems[Position];
  if Previous.Value = Value then
  begin
    Exit;
  end;

  FItems[Position] := NewEntry(Previous.Key, Value);
  if Previous.Owned then
  begin
    Previous.Value.Free;
  end;
end;

{ TCosStream }

procedure TCosStream.SetRawSource(const Source: TRandomAccessRead; const Offset, Length: Int64);
begin
  FSource := Source;
  FOffset := Offset;
  FLength := Length;
  FRawData := nil;
  FHasRawData := False;
end;

procedure TCosStream.SetRawData(const Data: TBytes);
begin
  FRawData := Copy(Data);
  FHasRawData := True;
  FSource := nil;
end;

function TCosStream.CreateRawStream: TStream;
begin
  const Stream = TBytesStream.Create(GetRawBytes);
  Result := Stream;
end;

function TCosStream.ReadRawPrefix(const MaxCount: Integer): TBytes;
begin
  if FHasRawData then
  begin
    Exit(Copy(FRawData, 0, MaxCount));
  end;
  if not Assigned(FSource) then
  begin
    Exit(nil);
  end;

  const Count = Min(Int64(MaxCount), FLength);
  const View = FSource.CreateView(FOffset, Count);
  try
    Result := View.ReadFully(Integer(Count));
  finally
    View.Free;
  end;
end;

procedure TCosStream.SetDocument(const Value: TObject);
begin
  if Assigned(Value) and not (Value is TCosDocument) then
  begin
    raise EArgumentException.Create('The document of a stream has to be a TCosDocument');
  end;
  FDocument := Value;
end;

function TCosStream.MaxDecodedSize: Int64;
begin
  if Assigned(FDocument) then
  begin
    Result := TCosDocument(FDocument).Options.MaxDecodedStreamSize;
  end
  else
  begin
    Result := TPdfLoadOptions.Default.MaxDecodedStreamSize;
  end;
end;

function TCosStream.DocumentLog: TPdfLog;
begin
  Result := nil;
  if Assigned(FDocument) then
  begin
    Result := TCosDocument(FDocument).Log;
  end;
end;

function TCosStream.GetFilterNames: TArray<string>;
begin
  Result := nil;
  var Filters: TCosBase;
  if not TryGetDictionaryObject(TCosNames.Filter, Filters) then
  begin
    Exit;
  end;

  if Filters is TCosName then
  begin
    Result := [TCosName(Filters).Name];
    Exit;
  end;

  if Filters is TCosArray then
  begin
    for var Item in TCosArray(Filters) do
    begin
      var Resolved := Item;
      if Resolved is TCosObject then
      begin
        Resolved := TCosObject(Resolved).GetObject;
      end;

      if not (Resolved is TCosName) then
      begin
        raise EPdfParseException.CreateFmt('Forbidden type in filter array: %s', [Resolved.ClassName]);
      end;
      Result := Result + [TCosName(Resolved).Name];
    end;
  end;
end;

function TCosStream.CreateDecodedStream: TStream;
begin
  var Remaining: TArray<string>;
  const Data = TFilterChain.Decode(GetRawBytes, GetFilterNames, Self, MaxDecodedSize, DocumentLog, False, Remaining);
  Result := TBytesStream.Create(Data);
end;

function TCosStream.DecodeUntilImageFilter: TPdfDecodedData;
begin
  Result.Data := TFilterChain.Decode(GetRawBytes, GetFilterNames, Self, MaxDecodedSize, DocumentLog, True, Result.RemainingFilters);
end;

function TCosStream.GetRawBytes: TBytes;
begin
  var Bytes: TBytes;
  if FHasRawData then
  begin
    Bytes := Copy(FRawData);
  end
  else if Assigned(FSource) then
  begin
    Bytes := ReadSourceBytes;
    if Assigned(FDecryptor) then
    begin
      Bytes := FDecryptor(Bytes);
    end;
  end;

  Result := Bytes;
end;

function TCosStream.ReadSourceBytes: TBytes;
begin
  if FLength > High(Integer) then
  begin
    raise EPdfLimitExceededException.CreateFmt('Stream of %d bytes is too large to read', [FLength]);
  end;

  // The view checks offset and length against the data
  const View = FSource.CreateView(FOffset, FLength);
  try
    Result := View.ReadFully(Integer(FLength));
  finally
    View.Free;
  end;
end;

end.
