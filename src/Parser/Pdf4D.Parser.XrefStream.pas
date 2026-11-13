// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdfparser/PDFXrefStreamParser.java (3.0.8)
unit Pdf4D.Parser.XrefStream;

interface

uses
  System.SysUtils,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Document,
  Pdf4D.Parser.XrefTrailerResolver;

type
  // Reads the entries of a cross reference stream (/W, /Index and /Size) into a TXrefTrailerResolver
  TXrefStreamParser = class
  private
    const MaxTotalWidth = 20;
    // Far above the 8388607 objects that a PDF can have in practice. Stops a stream of tiny entries from filling memory.
    const MaxEntries = 16777216;

  private
    FStream: TCosStream;
    FDocument: TCosDocument;
    FWidths: array[0..2] of Integer;
    FRangeStart: TArray<Int64>;
    FRangeEnd: TArray<Int64>;
    FCurrentRange: Integer;
    FCurrentEnd: Int64;
    FCurrentNumber: Int64;

    procedure ReadWidths;
    procedure ReadRanges;
    function IndexArrayOrDefault: TArray<Int64>;
    procedure StartRanges(const Pairs: TArray<Int64>);
    function HasNextObjectNumber: Boolean;
    function NextObjectNumber: Int64;
    function DecodeEntries: TBytes;
    function ParseValue(const Data: TBytes; const Start, Width: Integer): Int64;
    procedure ParseEntry(const Data: TBytes; const Offset: Integer; const Resolver: TXrefTrailerResolver);
    procedure LogWarning(const Fmt: string; const Args: array of const);

  public
    // Raises EPdfParseException for a stream without a usable /W or /Index. The document gives the log and the
    // decoded size limit and may be nil.
    constructor Create(const Stream: TCosStream; const Document: TCosDocument);

    procedure Parse(const Resolver: TXrefTrailerResolver);
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.Number,
  Pdf4D.Cos.ObjectKey,
  Pdf4D.Cos.PdfArray,
  System.Classes;

const
  ByteBits = 8;
  JavaShiftMask = 63;
  EntryTypeFree = 0;
  EntryTypeOffset = 1;

{ TXrefStreamParser }

constructor TXrefStreamParser.Create(const Stream: TCosStream; const Document: TCosDocument);
begin
  inherited Create;
  FStream := Stream;
  FDocument := Document;
  ReadWidths;
  ReadRanges;
end;

procedure TXrefStreamParser.ReadWidths;
begin
  var WidthArray: TCosArray;
  if not FStream.TryGetCosArray(TCosNames.W, WidthArray) then
  begin
    raise EPdfParseException.Create('/W array is missing in Xref stream');
  end;

  if WidthArray.Count <> 3 then
  begin
    raise EPdfParseException.CreateFmt('Wrong number of values for /W array in XRef: %d', [WidthArray.Count]);
  end;

  for var Position := 0 to 2 do
  begin
    const Item = WidthArray.GetObject(Position);
    FWidths[Position] := 0;
    if Item is TCosNumber then
    begin
      FWidths[Position] := TCosNumber(Item).IntValue;
    end;
  end;

  const IsNegative = ((FWidths[0] < 0) or (FWidths[1] < 0) or (FWidths[2] < 0));
  if IsNegative then
  begin
    raise EPdfParseException.CreateFmt('Incorrect /W array in XRef: [%d %d %d]', [FWidths[0], FWidths[1], FWidths[2]]);
  end;

  // Each width is at most High(Integer), so the sum is taken in an Int64
  const TotalWidth = Int64(FWidths[0]) + FWidths[1] + FWidths[2];
  if TotalWidth > MaxTotalWidth then
  begin
    raise EPdfParseException.CreateFmt('Incorrect /W array in XRef: [%d %d %d]', [FWidths[0], FWidths[1], FWidths[2]]);
  end;
end;

// Without /Index the default is [0 /Size]
function TXrefStreamParser.IndexArrayOrDefault: TArray<Int64>;
begin
  Result := nil;
  var IndexArray: TCosArray;
  if not FStream.TryGetCosArray(TCosNames.Index, IndexArray) then
  begin
    SetLength(Result, 2);
    Result[0] := 0;
    Result[1] := FStream.GetInt(TCosNames.Size, 0);
    Exit;
  end;

  const IsInvalidLength = ((IndexArray.Count = 0) or (IndexArray.Count mod 2 = 1));
  if IsInvalidLength then
  begin
    raise EPdfParseException.CreateFmt('Wrong number of values for /Index array in XRef: %d', [IndexArray.Count]);
  end;

  SetLength(Result, IndexArray.Count);
  for var Position := 0 to IndexArray.Count - 1 do
  begin
    // The type is checked on the item as stored: a reference to a number is not accepted, like in PDFBox
    const Item = IndexArray.Get(Position);
    if not (Item is TCosInteger) then
    begin
      raise EPdfParseException.Create('Xref stream must have integer in /Index array');
    end;
    Result[Position] := TCosInteger(Item).LongValue;
  end;
end;

procedure TXrefStreamParser.ReadRanges;
begin
  StartRanges(IndexArrayOrDefault);
end;

procedure TXrefStreamParser.StartRanges(const Pairs: TArray<Int64>);
begin
  const RangeCount = Length(Pairs) div 2;
  SetLength(FRangeStart, RangeCount);
  SetLength(FRangeEnd, RangeCount);
  for var Range := 0 to RangeCount - 1 do
  begin
    const First = Pairs[Range * 2];
    const Count = Pairs[Range * 2 + 1];
    FRangeStart[Range] := First;
    // The end saturates: a /Index that overflows must not wrap around. A negative count gives an empty range.
    if Count <= 0 then
    begin
      FRangeEnd[Range] := First;
    end
    else if First > High(Int64) - Count then
    begin
      FRangeEnd[Range] := High(Int64);
    end
    else
    begin
      FRangeEnd[Range] := First + Count;
    end;
  end;

  FCurrentRange := 0;
  FCurrentNumber := FRangeStart[0];
  FCurrentEnd := FRangeEnd[0];
end;

// Port of the iterator ObjectNumbers: another range is entered without a check on its size, like PDFBox
function TXrefStreamParser.HasNextObjectNumber: Boolean;
begin
  if Length(FRangeStart) = 1 then
  begin
    Exit(FCurrentNumber < FCurrentEnd);
  end;
  Result := ((FCurrentRange < Length(FRangeStart) - 1) or (FCurrentNumber < FCurrentEnd));
end;

function TXrefStreamParser.NextObjectNumber: Int64;
begin
  if FCurrentNumber < FCurrentEnd then
  begin
    Result := FCurrentNumber;
    Inc(FCurrentNumber);
    Exit;
  end;

  Inc(FCurrentRange);
  FCurrentNumber := FRangeStart[FCurrentRange];
  FCurrentEnd := FRangeEnd[FCurrentRange];
  Result := FCurrentNumber;
  Inc(FCurrentNumber);
end;

function TXrefStreamParser.DecodeEntries: TBytes;
begin
  const Decoded = FStream.CreateDecodedStream;
  try
    const Count = Decoded.Size;
    SetLength(Result, Count);
    if Count > 0 then
    begin
      Decoded.Position := 0;
      Decoded.ReadBuffer(Result[0], Count);
    end;
  finally
    Decoded.Free;
  end;
end;

// The shift counts of Java wrap at 64: a field wider than 8 bytes is read in the same way
function TXrefStreamParser.ParseValue(const Data: TBytes; const Start, Width: Integer): Int64;
begin
  Result := 0;
  for var Position := 0 to Width - 1 do
  begin
    const ShiftCount = ((Width - Position - 1) * ByteBits) and JavaShiftMask;
    Result := Result + (Int64(Data[Position + Start]) shl ShiftCount);
  end;
end;

procedure TXrefStreamParser.LogWarning(const Fmt: string; const Args: array of const);
begin
  if Assigned(FDocument) then
  begin
    FDocument.Log.Warning(Fmt, Args);
  end;
end;

procedure TXrefStreamParser.ParseEntry(const Data: TBytes; const Offset: Integer; const Resolver: TXrefTrailerResolver);
begin
  const ObjectId = NextObjectNumber;

  // The default type is 1 when the first field has no width
  var EntryType := 1;
  if FWidths[0] <> 0 then
  begin
    EntryType := Integer(ParseValue(Data, Offset, FWidths[0]));
  end;

  if EntryType = EntryTypeFree then
  begin
    Exit;
  end;

  const SecondValue = ParseValue(Data, Offset + FWidths[0], FWidths[1]);
  const ThirdValue = Integer(ParseValue(Data, Offset + FWidths[0] + FWidths[1], FWidths[2]));
  if EntryType = EntryTypeOffset then
  begin
    Resolver.SetXref(TCosObjectKey.Make(ObjectId, ThirdValue), SecondValue);
  end
  else
  begin
    // An object in an object stream: the number of that stream is stored with a minus sign, to tell it from an offset
    Resolver.SetXref(TCosObjectKey.MakeInObjectStream(ObjectId, ThirdValue), -SecondValue);
  end;
end;

procedure TXrefStreamParser.Parse(const Resolver: TXrefTrailerResolver);
begin
  const EntryLength = FWidths[0] + FWidths[1] + FWidths[2];
  if EntryLength = 0 then
  begin
    LogWarning('Xref stream with entries of no width ignored', []);
    Exit;
  end;

  const Data = DecodeEntries;
  var Offset := 0;
  var EntryCount := 0;
  while HasNextObjectNumber and (Length(Data) - Offset >= EntryLength) do
  begin
    if EntryCount >= MaxEntries then
    begin
      LogWarning('Xref stream has more than %d entries, the rest is ignored', [MaxEntries]);
      Exit;
    end;

    ParseEntry(Data, Offset, Resolver);
    Inc(Offset, EntryLength);
    Inc(EntryCount);
  end;
end;

end.
