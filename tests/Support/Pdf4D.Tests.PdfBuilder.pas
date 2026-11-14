// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Builds small synthetic PDF files with exact offsets, for the tests of the parser.
unit Pdf4D.Tests.PdfBuilder;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections;

type
  {$SCOPEDENUMS ON}
  TXrefStyle = (Table, Stream, Hybrid);
  // How the data of an xref stream or object stream is stored: as is, deflated, or deflated with the PNG Up predictor
  TStreamFilter = (None, Flate, FlatePredictor);
  {$SCOPEDENUMS OFF}

  TTestPdfBuilder = class
  private
    type
      TBuilderObject = record
        Number: Integer;
        Body: string;
        Data: TBytes;
        HasData: Boolean;
        ObjectStreamNumber: Integer;
      end;

  private
    FObjects: TList<TBuilderObject>;
    FOffsets: TDictionary<Integer, Int64>;
    FCorruptions: TDictionary<Integer, Int64>;
    FRoot: Integer;
    FTrailerExtra: string;
    FWidths: TArray<Integer>;
    FIndex: TArray<Int64>;
    FXrefStreamNumber: Integer;
    FXrefStreamFilter: TStreamFilter;
    FObjectStreamFilter: TStreamFilter;
    FMinimumSize: Integer;

    class function Latin1(const Text: string): TBytes; static;
    class procedure Append(var Target: TBytes; const Addition: TBytes); static;
    class function Deflate(const Data: TBytes): TBytes; static;
    class function ApplyUpPredictor(const Data: TBytes; const RowLength: Integer): TBytes; static;

    function FindIndex(const Number: Integer; out Position: Integer): Boolean;
    function HighestNumber: Integer;
    function HasCompressedObjects: Boolean;
    function ObjectStreamNumbers: TArray<Integer>;
    function MembersOf(const ObjectStreamNumber: Integer): TArray<TBuilderObject>;
    function Encode(const Data: TBytes; const Filter: TStreamFilter; const RowLength: Integer; out FilterEntry: string): TBytes;
    function ObjectStreamBytes(const ObjectStreamNumber: Integer; out Dictionary: string): TBytes;
    function IndirectObject(const Number: Integer; const Dictionary: string; const Data: TBytes): TBytes;
    function WriteObjects(var Output: TBytes; const BaseOffset: Int64): Integer;
    function WrittenOffset(const Number: Integer): Int64;
    function IndexRanges(const Size: Integer): TArray<Int64>;
    function XrefStreamBytes(const Size: Integer; const Hybrid: Boolean; out Dictionary: string): TBytes;
    function EntryBytes(const Number: Integer; const Hybrid: Boolean): TBytes;
    function XrefTableBytes(const Size: Integer; const Hybrid: Boolean): TBytes;
    function TrailerEntries(const Size: Integer; const Prev: Int64): string;
    function BuildAfter(const Previous: TBytes; const Style: TXrefStyle; const Prev: Int64): TBytes;
    class function LastStartXref(const Previous: TBytes): Int64; static;

  public
    constructor Create;
    destructor Destroy; override;

    // Body is the text between "obj" and "endobj", for example '<< /Type /Catalog >>'
    procedure AddObject(const Number: Integer; const Body: string);

    // Dictionary is the text of the entries, without << >> and without /Length: the builder adds the length
    procedure AddStreamObject(const Number: Integer; const Dictionary: string; const Data: TBytes);

    // The object is stored inside the object stream of that number (written as /Type /ObjStm) and gets a type 2
    // entry in an xref stream. Needs the Stream or Hybrid style.
    procedure AddCompressedObject(const Number: Integer; const Body: string; const ObjectStreamNumber: Integer);

    // The number of the catalog, written as /Root in the trailer
    procedure SetRoot(const Number: Integer);

    // Moves the xref entry of an object by Delta bytes, to give a file with a wrong offset
    procedure CorruptOffset(const Number: Integer; const Delta: Int64);

    function Build(const Style: TXrefStyle): TBytes;

    // The objects of this builder are the update: appended to Previous with a new xref section whose /Prev points to
    // the last startxref of Previous. Set MinimumSize to the /Size of the older file.
    function AppendIncrementalUpdate(const Previous: TBytes; const Style: TXrefStyle): TBytes;

    // The offset of the object in the last built file
    function OffsetOf(const Number: Integer): Int64;

    property TrailerExtra: string read FTrailerExtra write FTrailerExtra;
    // The /W of an xref stream, [1 4 2] by default
    property Widths: TArray<Integer> read FWidths write FWidths;
    // The /Index of an xref stream as pairs (first, count), by default one range over all objects
    property Index: TArray<Int64> read FIndex write FIndex;
    // The object number of the xref stream, by default the number after the highest object
    property XrefStreamNumber: Integer read FXrefStreamNumber write FXrefStreamNumber;
    property XrefStreamFilter: TStreamFilter read FXrefStreamFilter write FXrefStreamFilter;
    property ObjectStreamFilter: TStreamFilter read FObjectStreamFilter write FObjectStreamFilter;
    property MinimumSize: Integer read FMinimumSize write FMinimumSize;
  end;

implementation

uses
  System.Math,
  System.ZLib;

const
  FreeEntryOffset = 0;
  FreeGeneration = 65535;
  DefaultWidth1 = 1;
  DefaultWidth2 = 4;
  DefaultWidth3 = 2;
  PngUpPredictor = 12;
  PngUpRowTag = 2;

{ TTestPdfBuilder }

class function TTestPdfBuilder.Latin1(const Text: string): TBytes;
begin
  SetLength(Result, Length(Text));
  for var Position := 1 to Length(Text) do
  begin
    Result[Position - 1] := Byte(Ord(Text[Position]) and $FF);
  end;
end;

class procedure TTestPdfBuilder.Append(var Target: TBytes; const Addition: TBytes);
begin
  if Length(Addition) = 0 then
  begin
    Exit;
  end;

  const OldLength = Length(Target);
  SetLength(Target, OldLength + Length(Addition));
  Move(Addition[0], Target[OldLength], Length(Addition));
end;

class function TTestPdfBuilder.Deflate(const Data: TBytes): TBytes;
begin
  const Output = TBytesStream.Create;
  try
    const Compressor = TZCompressionStream.Create(Output);
    try
      if Length(Data) > 0 then
      begin
        Compressor.WriteBuffer(Data[0], Length(Data));
      end;
    finally
      Compressor.Free;
    end;
    Result := Copy(Output.Bytes, 0, Output.Size);
  finally
    Output.Free;
  end;
end;

class function TTestPdfBuilder.ApplyUpPredictor(const Data: TBytes; const RowLength: Integer): TBytes;
begin
  const RowCount = Length(Data) div RowLength;
  SetLength(Result, RowCount * (RowLength + 1));
  for var Row := 0 to RowCount - 1 do
  begin
    Result[Row * (RowLength + 1)] := PngUpRowTag;
    for var Column := 0 to RowLength - 1 do
    begin
      const Current = Data[Row * RowLength + Column];
      var Above: Byte := 0;
      if Row > 0 then
      begin
        Above := Data[(Row - 1) * RowLength + Column];
      end;
      Result[Row * (RowLength + 1) + 1 + Column] := Byte(Current - Above);
    end;
  end;
end;

constructor TTestPdfBuilder.Create;
begin
  inherited Create;
  FObjects := TList<TBuilderObject>.Create;
  FOffsets := TDictionary<Integer, Int64>.Create;
  FCorruptions := TDictionary<Integer, Int64>.Create;
  FWidths := [DefaultWidth1, DefaultWidth2, DefaultWidth3];
  FXrefStreamFilter := TStreamFilter.Flate;
  FObjectStreamFilter := TStreamFilter.Flate;
end;

destructor TTestPdfBuilder.Destroy;
begin
  FCorruptions.Free;
  FOffsets.Free;
  FObjects.Free;
  inherited;
end;

function TTestPdfBuilder.FindIndex(const Number: Integer; out Position: Integer): Boolean;
begin
  Position := -1;
  for var Candidate := 0 to FObjects.Count - 1 do
  begin
    if FObjects[Candidate].Number = Number then
    begin
      Position := Candidate;
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TTestPdfBuilder.AddObject(const Number: Integer; const Body: string);
begin
  var Item: TBuilderObject;
  Item.Number := Number;
  Item.Body := Body;
  Item.Data := nil;
  Item.HasData := False;
  Item.ObjectStreamNumber := 0;

  var Position: Integer;
  if FindIndex(Number, Position) then
  begin
    FObjects[Position] := Item;
  end
  else
  begin
    FObjects.Add(Item);
  end;
end;

procedure TTestPdfBuilder.AddStreamObject(const Number: Integer; const Dictionary: string; const Data: TBytes);
begin
  AddObject(Number, Dictionary);
  var Position: Integer;
  FindIndex(Number, Position);
  var Item := FObjects[Position];
  Item.Data := Copy(Data);
  Item.HasData := True;
  FObjects[Position] := Item;
end;

procedure TTestPdfBuilder.AddCompressedObject(const Number: Integer; const Body: string; const ObjectStreamNumber: Integer);
begin
  AddObject(Number, Body);
  var Position: Integer;
  FindIndex(Number, Position);
  var Item := FObjects[Position];
  Item.ObjectStreamNumber := ObjectStreamNumber;
  FObjects[Position] := Item;
end;

procedure TTestPdfBuilder.SetRoot(const Number: Integer);
begin
  FRoot := Number;
end;

procedure TTestPdfBuilder.CorruptOffset(const Number: Integer; const Delta: Int64);
begin
  FCorruptions.AddOrSetValue(Number, Delta);
end;

function TTestPdfBuilder.OffsetOf(const Number: Integer): Int64;
begin
  if not FOffsets.TryGetValue(Number, Result) then
  begin
    raise EArgumentException.CreateFmt('Object %d was not written as a normal object', [Number]);
  end;
end;

function TTestPdfBuilder.HighestNumber: Integer;
begin
  Result := 0;
  for var Item in FObjects do
  begin
    Result := Max(Result, Item.Number);
  end;
  for var Number in ObjectStreamNumbers do
  begin
    Result := Max(Result, Number);
  end;
end;

function TTestPdfBuilder.HasCompressedObjects: Boolean;
begin
  Result := (Length(ObjectStreamNumbers) > 0);
end;

function TTestPdfBuilder.ObjectStreamNumbers: TArray<Integer>;
begin
  Result := nil;
  for var Item in FObjects do
  begin
    const IsCompressed = (Item.ObjectStreamNumber > 0);
    if IsCompressed and not TArray.Contains<Integer>(Result, Item.ObjectStreamNumber) then
    begin
      Result := Result + [Item.ObjectStreamNumber];
    end;
  end;
end;

function TTestPdfBuilder.MembersOf(const ObjectStreamNumber: Integer): TArray<TBuilderObject>;
begin
  Result := nil;
  for var Item in FObjects do
  begin
    if Item.ObjectStreamNumber = ObjectStreamNumber then
    begin
      Result := Result + [Item];
    end;
  end;
end;

function TTestPdfBuilder.Encode(const Data: TBytes; const Filter: TStreamFilter; const RowLength: Integer; out FilterEntry: string): TBytes;
begin
  case Filter of
    TStreamFilter.None :
      begin
        FilterEntry := '';
        Result := Data;
      end;
    TStreamFilter.Flate :
      begin
        FilterEntry := ' /Filter /FlateDecode';
        Result := Deflate(Data);
      end;
    TStreamFilter.FlatePredictor :
      begin
        FilterEntry := Format(' /Filter /FlateDecode /DecodeParms << /Predictor %d /Columns %d >>', [PngUpPredictor, RowLength]);
        Result := Deflate(ApplyUpPredictor(Data, RowLength));
      end;
  else
    raise EArgumentException.CreateFmt('Unsupported stream filter %d', [Ord(Filter)]);
  end;
end;

function TTestPdfBuilder.ObjectStreamBytes(const ObjectStreamNumber: Integer; out Dictionary: string): TBytes;
begin
  var Header := '';
  var Bodies := '';
  const Members = MembersOf(ObjectStreamNumber);
  for var Member in Members do
  begin
    Header := Header + Format('%d %d ', [Member.Number, Length(Bodies)]);
    Bodies := Bodies + Member.Body + ' ';
  end;

  var FilterEntry: string;
  const Encoded = Encode(Latin1(Header + Bodies), FObjectStreamFilter, 1, FilterEntry);
  Dictionary := Format('/Type /ObjStm /N %d /First %d%s', [Length(Members), Length(Header), FilterEntry]);
  Result := Encoded;
end;

function TTestPdfBuilder.IndirectObject(const Number: Integer; const Dictionary: string; const Data: TBytes): TBytes;
begin
  Result := nil;
  Append(Result, Latin1(Format('%d 0 obj'#10'<< %s /Length %d >>'#10'stream'#10, [Number, Dictionary, Length(Data)])));
  Append(Result, Data);
  Append(Result, Latin1(#10'endstream'#10'endobj'#10));
end;

// Writes every normal object and the object streams. Gives the number of objects written.
function TTestPdfBuilder.WriteObjects(var Output: TBytes; const BaseOffset: Int64): Integer;
begin
  Result := 0;
  FOffsets.Clear;
  for var Item in FObjects do
  begin
    if Item.ObjectStreamNumber > 0 then
    begin
      Continue;
    end;

    FOffsets.AddOrSetValue(Item.Number, BaseOffset + Length(Output));
    if Item.HasData then
    begin
      Append(Output, IndirectObject(Item.Number, Item.Body, Item.Data));
    end
    else
    begin
      Append(Output, Latin1(Format('%d 0 obj'#10'%s'#10'endobj'#10, [Item.Number, Item.Body])));
    end;
    Inc(Result);
  end;

  for var Number in ObjectStreamNumbers do
  begin
    var Dictionary: string;
    const Data = ObjectStreamBytes(Number, Dictionary);
    FOffsets.AddOrSetValue(Number, BaseOffset + Length(Output));
    Append(Output, IndirectObject(Number, Dictionary, Data));
    Inc(Result);
  end;
end;

function TTestPdfBuilder.WrittenOffset(const Number: Integer): Int64;
begin
  Result := FOffsets[Number];
  var Delta: Int64;
  if FCorruptions.TryGetValue(Number, Delta) then
  begin
    Result := Result + Delta;
  end;
end;

function TTestPdfBuilder.IndexRanges(const Size: Integer): TArray<Int64>;
begin
  if Length(FIndex) > 0 then
  begin
    Result := FIndex;
  end
  else
  begin
    Result := [0, Size];
  end;
end;

// One entry of an xref stream: type 0 free, 1 offset and generation, 2 object stream and index
function TTestPdfBuilder.EntryBytes(const Number: Integer; const Hybrid: Boolean): TBytes;
begin
  var EntryType: Int64 := 0;
  var Second: Int64 := 0;
  var Third: Int64 := 0;

  var Position: Integer;
  if FindIndex(Number, Position) then
  begin
    const Item = FObjects[Position];
    if Item.ObjectStreamNumber > 0 then
    begin
      EntryType := 2;
      Second := Item.ObjectStreamNumber;
      for var Member in MembersOf(Item.ObjectStreamNumber) do
      begin
        if Member.Number = Number then
        begin
          Break;
        end;
        Inc(Third);
      end;
    end
    else if not Hybrid then
    begin
      EntryType := 1;
      Second := WrittenOffset(Number);
    end;
  end
  else if FOffsets.ContainsKey(Number) and not Hybrid then
  begin
    EntryType := 1;
    Second := WrittenOffset(Number);
  end;

  const Fields: TArray<Int64> = [EntryType, Second, Third];
  Result := nil;
  for var Field := 0 to 2 do
  begin
    for var ByteIndex := FWidths[Field] - 1 downto 0 do
    begin
      Result := Result + [Byte((Fields[Field] shr (ByteIndex * 8)) and $FF)];
    end;
  end;
end;

function TTestPdfBuilder.XrefStreamBytes(const Size: Integer; const Hybrid: Boolean; out Dictionary: string): TBytes;
begin
  const Ranges = IndexRanges(Size);
  var Raw: TBytes := nil;
  var IndexText := '';
  var RangeIndex := 0;
  while RangeIndex < Length(Ranges) do
  begin
    IndexText := IndexText + Format('%d %d ', [Ranges[RangeIndex], Ranges[RangeIndex + 1]]);
    for var Offset := 0 to Ranges[RangeIndex + 1] - 1 do
    begin
      Append(Raw, EntryBytes(Ranges[RangeIndex] + Offset, Hybrid));
    end;
    Inc(RangeIndex, 2);
  end;

  const RowLength = FWidths[0] + FWidths[1] + FWidths[2];
  var FilterEntry: string;
  Result := Encode(Raw, FXrefStreamFilter, Max(RowLength, 1), FilterEntry);
  Dictionary := Format('/Type /XRef /W [%d %d %d] /Index [%s]%s', [FWidths[0], FWidths[1], FWidths[2], IndexText.Trim, FilterEntry]);
end;

function TTestPdfBuilder.XrefTableBytes(const Size: Integer; const Hybrid: Boolean): TBytes;
begin
  var Text := Format('xref'#10'0 %d'#10, [Size]);
  for var Number := 0 to Size - 1 do
  begin
    var Position: Integer;
    const IsListed = (FindIndex(Number, Position) and (FObjects[Position].ObjectStreamNumber = 0)) or FOffsets.ContainsKey(Number);
    if IsListed and not (Hybrid and FindIndex(Number, Position) and (FObjects[Position].ObjectStreamNumber > 0)) then
    begin
      Text := Text + Format('%.10d %.5d n '#10, [WrittenOffset(Number), 0]);
    end
    else
    begin
      Text := Text + Format('%.10d %.5d f '#10, [FreeEntryOffset, FreeGeneration]);
    end;
  end;
  Result := Latin1(Text);
end;

function TTestPdfBuilder.TrailerEntries(const Size: Integer; const Prev: Int64): string;
begin
  Result := Format('/Size %d', [Size]);
  if FRoot > 0 then
  begin
    Result := Result + Format(' /Root %d 0 R', [FRoot]);
  end;
  if Prev >= 0 then
  begin
    Result := Result + Format(' /Prev %d', [Prev]);
  end;
  if FTrailerExtra <> '' then
  begin
    Result := Result + ' ' + FTrailerExtra;
  end;
end;

class function TTestPdfBuilder.LastStartXref(const Previous: TBytes): Int64;
begin
  var Text := '';
  for var Value in Previous do
  begin
    Text := Text + Char(Value);
  end;
  const Position = Text.LastIndexOf('startxref');
  if Position < 0 then
  begin
    raise EArgumentException.Create('The previous file has no startxref');
  end;
  Result := StrToInt64(Text.Substring(Position + Length('startxref')).Trim.Split([#10, #13, ' '])[0]);
end;

function TTestPdfBuilder.BuildAfter(const Previous: TBytes; const Style: TXrefStyle; const Prev: Int64): TBytes;
begin
  if HasCompressedObjects and (Style = TXrefStyle.Table) then
  begin
    raise EInvalidOpException.Create('Compressed objects need the Stream or Hybrid style');
  end;

  Result := Copy(Previous);
  const BaseOffset: Int64 = 0;
  const FirstObjectLength = Length(Result);
  if FirstObjectLength = 0 then
  begin
    Append(Result, Latin1('%PDF-1.7'#10 + '%'#$E2#$E3#$CF#$D3#10));
  end;

  var Section: TBytes := nil;
  WriteObjects(Section, BaseOffset + Length(Result));
  Append(Result, Section);

  const Size = Max(Max(HighestNumber + 1, FMinimumSize), FXrefStreamNumber + 1);
  const StartXref: Int64 = Length(Result);
  case Style of
    TXrefStyle.Table :
      begin
        Append(Result, XrefTableBytes(Size, False));
        Append(Result, Latin1('trailer'#10'<< ' + TrailerEntries(Size, Prev) + ' >>'#10));
      end;
    TXrefStyle.Stream :
      begin
        const Number = Max(FXrefStreamNumber, HighestNumber + 1);
        FOffsets.AddOrSetValue(Number, StartXref);
        var Dictionary: string;
        const Data = XrefStreamBytes(Max(Size, Number + 1), False, Dictionary);
        Append(Result, IndirectObject(Number, Dictionary + ' ' + TrailerEntries(Max(Size, Number + 1), Prev), Data));
      end;
    TXrefStyle.Hybrid :
      begin
        const Number = Max(FXrefStreamNumber, HighestNumber + 1);
        FOffsets.AddOrSetValue(Number, StartXref);
        var Dictionary: string;
        const Data = XrefStreamBytes(Max(Size, Number + 1), True, Dictionary);
        Append(Result, IndirectObject(Number, Dictionary + ' /Size ' + IntToStr(Max(Size, Number + 1)), Data));
        const TableOffset: Int64 = Length(Result);
        Append(Result, XrefTableBytes(Size, True));
        Append(Result, Latin1(Format('trailer'#10'<< %s /XRefStm %d >>'#10, [TrailerEntries(Size, Prev), StartXref])));
        Append(Result, Latin1(Format('startxref'#10'%d'#10'%%EOF'#10, [TableOffset])));
        Exit;
      end;
  else
    raise EArgumentException.CreateFmt('Unsupported xref style %d', [Ord(Style)]);
  end;

  Append(Result, Latin1(Format('startxref'#10'%d'#10'%%EOF'#10, [StartXref])));
end;

function TTestPdfBuilder.Build(const Style: TXrefStyle): TBytes;
begin
  Result := BuildAfter(nil, Style, -1);
end;

function TTestPdfBuilder.AppendIncrementalUpdate(const Previous: TBytes; const Style: TXrefStyle): TBytes;
begin
  Result := BuildAfter(Previous, Style, LastStartXref(Previous));
end;

end.
