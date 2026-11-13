// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdfparser/XrefTrailerResolver.java (3.0.8)
unit Pdf4D.Parser.XrefTrailerResolver;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Pdf4D.Common.Log,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Number,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Cos.ObjectKey;

type
  {$SCOPEDENUMS ON}
  TXrefType = (Table, Stream);
  {$SCOPEDENUMS OFF}

  // A deep copy of a direct COS value, for a value that has to live in two places with a single owner each
  TCosValueCopier = class
  private
    class function CopyArray(const Source: TCosArray): TCosArray; static;
    class function CopyDictionary(const Source: TCosDictionary): TCosDictionary; static;
    class function CopyNumber(const Source: TCosNumber): TCosBase; static;

  public
    // A TCosObject is returned as it is: the document owns it. A stream is not a direct value and raises.
    class function Copy(const Value: TCosBase): TCosBase; static;
  end;

  // Collects the xref sections and trailers of a file and resolves them into one xref table and one trailer by
  // following /Prev from the last startxref. Owns the trailers it is given.
  TXrefTrailerResolver = class
  private
    type
      TXrefSection = class
      private
        FTrailer: TCosDictionary;

      public
        XrefType: TXrefType;
        Table: TDictionary<TCosObjectKey, Int64>;

        constructor Create(const KeyComparer: IEqualityComparer<TCosObjectKey>);
        destructor Destroy; override;

        procedure SetTrailer(const Trailer: TCosDictionary);

        property Trailer: TCosDictionary read FTrailer;
      end;

  private
    FKeyComparer: IEqualityComparer<TCosObjectKey>;
    FLog: TPdfLog;
    FSections: TObjectDictionary<Int64, TXrefSection>;
    FCurrent: TXrefSection;
    FResolved: TXrefSection;
    FIsResolved: Boolean;

    function SortedPositions: TArray<Int64>;
    function ChainPositions(const StartPosition: Int64): TArray<Int64>;
    procedure MergeSections(const Positions: TArray<Int64>);
    procedure Warn(const Fmt: string; const Args: array of const);

  public
    // A deep copy of the entries of Source into Target (an existing key is replaced). A TCosObject value is shared,
    // as the document owns it. PDFBox adds the same instances to both dictionaries; with owned values a copy is needed.
    class procedure CopyEntries(const Source, Target: TCosDictionary); static;

    // The log may be nil
    constructor Create(const Log: TPdfLog);
    destructor Destroy; override;

    // Starts the section found at StartBytePosition. A section at the same position replaces the earlier one.
    procedure NextXrefObj(const StartBytePosition: Int64; const XrefType: TXrefType);

    // Only the first entry for a key counts within a section
    procedure SetXref(const Key: TCosObjectKey; const Offset: Int64);

    // The trailer belongs to the resolver from now on
    procedure SetTrailer(const Trailer: TCosDictionary);

    // Resolves the chain that starts at the last startxref. Meant to be called once.
    procedure SetStartxref(const StartxrefBytePosition: Int64);

    function TryGetFirstTrailer(out Trailer: TCosDictionary): Boolean;
    function TryGetLastTrailer(out Trailer: TCosDictionary): Boolean;
    function GetTrailerCount: Integer;

    // The trailer of the section being read. Raises when no section was started. Nil when the section has no trailer yet.
    function GetCurrentTrailer: TCosDictionary;

    // The type of the resolved chain, raises before SetStartxref
    function GetXrefType: TXrefType;

    // The resolved trailer and table belong to the resolver. They raise before SetStartxref, like a null in PDFBox.
    function GetTrailer: TCosDictionary;
    function GetXrefTable: TDictionary<TCosObjectKey, Int64>;
    function GetContainedObjectNumbers(const ObjectStreamNumber: Int64): TArray<Int64>;

    // Clears the tables and the resolved state; the trailers of the sections stay, like in PDFBox
    procedure Reset;

    property IsResolved: Boolean read FIsResolved;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Boolean,
  Pdf4D.Cos.Float,
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.Null,
  Pdf4D.Cos.PdfObject,
  Pdf4D.Cos.PdfString;

{ TCosValueCopier }

class function TCosValueCopier.Copy(const Value: TCosBase): TCosBase;
begin
  if Value is TCosObject then
  begin
    Exit(Value);
  end;

  if Value is TCosNumber then
  begin
    Result := CopyNumber(TCosNumber(Value));
  end
  else if Value is TCosName then
  begin
    Result := TCosName.Create(TCosName(Value).Name);
  end
  else if Value is TCosString then
  begin
    Result := TCosString.Create(TCosString(Value).Bytes, TCosString(Value).IsHex);
  end
  else if Value is TCosBoolean then
  begin
    Result := TCosBoolean.Create(TCosBoolean(Value).Value);
  end
  else if Value is TCosNull then
  begin
    Result := TCosNull.Create;
  end
  else if Value is TCosArray then
  begin
    Result := CopyArray(TCosArray(Value));
  end
  else if (Value is TCosDictionary) and not (Value is TCosStream) then
  begin
    Result := CopyDictionary(TCosDictionary(Value));
  end
  else
  begin
    raise EPdfParseException.CreateFmt('A value of type %s cannot be copied', [Value.ClassName]);
  end;
  Result.Direct := Value.Direct;
end;

class function TCosValueCopier.CopyNumber(const Source: TCosNumber): TCosBase;
begin
  if Source is TCosInteger then
  begin
    const IntegerNumber = TCosInteger(Source);
    if IntegerNumber.IsValid then
    begin
      Result := TCosInteger.Create(IntegerNumber.Value);
    end
    else
    begin
      Result := TCosInteger.CreateOutOfRange(IntegerNumber.Value > 0);
    end;
  end
  else
  begin
    Result := TCosFloat.Create(Source.FloatValue);
  end;
end;

class function TCosValueCopier.CopyArray(const Source: TCosArray): TCosArray;
begin
  Result := TCosArray.Create;
  try
    for var Item in Source do
    begin
      Result.Add(Copy(Item));
    end;
  except
    Result.Free;
    raise;
  end;
end;

class function TCosValueCopier.CopyDictionary(const Source: TCosDictionary): TCosDictionary;
begin
  Result := TCosDictionary.Create;
  try
    TXrefTrailerResolver.CopyEntries(Source, Result);
  except
    Result.Free;
    raise;
  end;
end;

{ TXrefTrailerResolver.TXrefSection }

constructor TXrefTrailerResolver.TXrefSection.Create(const KeyComparer: IEqualityComparer<TCosObjectKey>);
begin
  inherited Create;
  XrefType := TXrefType.Table;
  Table := TDictionary<TCosObjectKey, Int64>.Create(KeyComparer);
end;

destructor TXrefTrailerResolver.TXrefSection.Destroy;
begin
  Table.Free;
  FTrailer.Free;
  inherited;
end;

procedure TXrefTrailerResolver.TXrefSection.SetTrailer(const Trailer: TCosDictionary);
begin
  if FTrailer <> Trailer then
  begin
    FTrailer.Free;
    FTrailer := Trailer;
  end;
end;

{ TXrefTrailerResolver }

class procedure TXrefTrailerResolver.CopyEntries(const Source, Target: TCosDictionary);
begin
  for var Key in Source.Keys do
  begin
    const Value = Source.GetItem(Key);
    Target.SetItem(Key, TCosValueCopier.Copy(Value));
  end;
end;

constructor TXrefTrailerResolver.Create(const Log: TPdfLog);
begin
  inherited Create;
  FLog := Log;
  FKeyComparer := TCosObjectKeyComparer.Create;
  FSections := TObjectDictionary<Int64, TXrefSection>.Create([doOwnsValues]);
end;

destructor TXrefTrailerResolver.Destroy;
begin
  FResolved.Free;
  FSections.Free;
  inherited;
end;

procedure TXrefTrailerResolver.Warn(const Fmt: string; const Args: array of const);
begin
  if Assigned(FLog) then
  begin
    FLog.Warning(Fmt, Args);
  end;
end;

procedure TXrefTrailerResolver.NextXrefObj(const StartBytePosition: Int64; const XrefType: TXrefType);
begin
  const Section = TXrefSection.Create(FKeyComparer);
  Section.XrefType := XrefType;
  FSections.AddOrSetValue(StartBytePosition, Section);
  FCurrent := Section;
end;

procedure TXrefTrailerResolver.SetXref(const Key: TCosObjectKey; const Offset: Int64);
begin
  if not Assigned(FCurrent) then
  begin
    Warn('Cannot add XRef entry for ''%d'' because XRef start was not signalled.', [Key.Number]);
    Exit;
  end;

  FCurrent.Table.TryAdd(Key, Offset);
end;

procedure TXrefTrailerResolver.SetTrailer(const Trailer: TCosDictionary);
begin
  if not Assigned(FCurrent) then
  begin
    Warn('Cannot add trailer because XRef start was not signalled.', []);
    Trailer.Free;
    Exit;
  end;

  FCurrent.SetTrailer(Trailer);
end;

function TXrefTrailerResolver.SortedPositions: TArray<Int64>;
begin
  Result := FSections.Keys.ToArray;
  TArray.Sort<Int64>(Result);
end;

function TXrefTrailerResolver.TryGetFirstTrailer(out Trailer: TCosDictionary): Boolean;
begin
  Trailer := nil;
  if FSections.Count = 0 then
  begin
    Exit(False);
  end;

  Trailer := FSections[SortedPositions[0]].Trailer;
  Result := True;
end;

function TXrefTrailerResolver.TryGetLastTrailer(out Trailer: TCosDictionary): Boolean;
begin
  Trailer := nil;
  if FSections.Count = 0 then
  begin
    Exit(False);
  end;

  const Positions = SortedPositions;
  Trailer := FSections[Positions[High(Positions)]].Trailer;
  Result := True;
end;

function TXrefTrailerResolver.GetTrailerCount: Integer;
begin
  Result := FSections.Count;
end;

function TXrefTrailerResolver.GetCurrentTrailer: TCosDictionary;
begin
  if not Assigned(FCurrent) then
  begin
    raise EInvalidOpException.Create('No XRef section was started');
  end;
  Result := FCurrent.Trailer;
end;

// The positions of the chain, oldest first. Follows /Prev and stops when a section is missing or when the chain
// is as long as the number of sections, which ends a /Prev loop.
function TXrefTrailerResolver.ChainPositions(const StartPosition: Int64): TArray<Int64>;
begin
  Result := [StartPosition];
  var Section := FSections[StartPosition];
  while Assigned(Section.Trailer) do
  begin
    const PreviousPosition = Section.Trailer.GetLong(TCosNames.Prev, -1);
    if PreviousPosition = -1 then
    begin
      Break;
    end;

    if not FSections.TryGetValue(PreviousPosition, Section) then
    begin
      Warn('Did not found XRef object pointed to by ''Prev'' key at position %d', [PreviousPosition]);
      Break;
    end;

    Result := Result + [PreviousPosition];
    if Length(Result) >= FSections.Count then
    begin
      Break;
    end;
  end;
  for var Position := 0 to (Length(Result) div 2) - 1 do
  begin
    const Mirror = High(Result) - Position;
    const Swapped = Result[Position];
    Result[Position] := Result[Mirror];
    Result[Mirror] := Swapped;
  end;
end;

procedure TXrefTrailerResolver.MergeSections(const Positions: TArray<Int64>);
begin
  for var Position in Positions do
  begin
    const Section = FSections[Position];
    if Assigned(Section.Trailer) then
    begin
      CopyEntries(Section.Trailer, FResolved.Trailer);
    end;
    for var Entry in Section.Table do
    begin
      FResolved.Table.AddOrSetValue(Entry.Key, Entry.Value);
    end;
  end;
end;

procedure TXrefTrailerResolver.SetStartxref(const StartxrefBytePosition: Int64);
begin
  if FIsResolved then
  begin
    Warn('Method must be called only ones with last startxref value.', []);
    Exit;
  end;

  FResolved := TXrefSection.Create(FKeyComparer);
  FResolved.SetTrailer(TCosDictionary.Create);
  FIsResolved := True;

  var Positions: TArray<Int64>;
  if FSections.ContainsKey(StartxrefBytePosition) then
  begin
    FResolved.XrefType := FSections[StartxrefBytePosition].XrefType;
    Positions := ChainPositions(StartxrefBytePosition);
  end
  else
  begin
    Warn('Did not found XRef object at specified startxref position %d', [StartxrefBytePosition]);
    Positions := SortedPositions;
  end;

  MergeSections(Positions);
end;

function TXrefTrailerResolver.GetXrefType: TXrefType;
begin
  if not FIsResolved then
  begin
    raise EInvalidOpException.Create('The XRef sections are not resolved yet');
  end;
  Result := FResolved.XrefType;
end;

function TXrefTrailerResolver.GetTrailer: TCosDictionary;
begin
  if not FIsResolved then
  begin
    raise EInvalidOpException.Create('The XRef sections are not resolved yet');
  end;
  Result := FResolved.Trailer;
end;

function TXrefTrailerResolver.GetXrefTable: TDictionary<TCosObjectKey, Int64>;
begin
  if not FIsResolved then
  begin
    raise EInvalidOpException.Create('The XRef sections are not resolved yet');
  end;
  Result := FResolved.Table;
end;

function TXrefTrailerResolver.GetContainedObjectNumbers(const ObjectStreamNumber: Int64): TArray<Int64>;
begin
  const Table = GetXrefTable;
  const ObjectStreamMarker = -ObjectStreamNumber;
  const Numbers = TList<Int64>.Create;
  try
    for var Entry in Table do
    begin
      if Entry.Value = ObjectStreamMarker then
      begin
        Numbers.Add(Entry.Key.Number);
      end;
    end;
    Result := Numbers.ToArray;
  finally
    Numbers.Free;
  end;
end;

procedure TXrefTrailerResolver.Reset;
begin
  for var Section in FSections.Values do
  begin
    Section.Table.Clear;
  end;
  FCurrent := nil;
  FreeAndNil(FResolved);
  FIsResolved := False;
end;

end.
