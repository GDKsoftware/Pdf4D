// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.TrueTypeBuilder;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.FontBox.BoundingBox,
  Pdf4D.FontBox.TrueType.Tables;

type
  // Writes big-endian font data
  TTestByteWriter = class
  private
    FBytes: TBytes;
    FLength: Integer;

    procedure Reserve(const Count: Integer);

  public
    procedure U8(const Value: Integer);
    procedure U16(const Value: Integer);
    procedure U32(const Value: Int64);
    procedure Zeros(const Count: Integer);
    procedure Append(const Bytes: TBytes);

    function ToBytes: TBytes;
  end;

  // The font a table needs while it is read, with the tables the test hands it
  TTestTableHost = class(TTTFTableHost)
  private
    FTables: TObjectDictionary<string, TTTFTable>;
    FNumberOfGlyphs: Integer;
    FHeader: THorizontalHeaderTable;

  public
    constructor Create(const NumberOfGlyphs: Integer);
    destructor Destroy; override;

    // The host owns the table
    procedure AddTable(const Table: TTTFTable);

    function NumberOfGlyphs: Integer; override;
    function HorizontalHeader: THorizontalHeaderTable; override;
    function TryGetTable(const Tag: string; out Table: TTTFTable): Boolean; override;
    function Name: string; override;
    function FontBBox: TBoundingBox; override;
    function FontMatrix: TArray<Single>; override;
    function GetWidth(const GlyphName: string): Single; override;
    function HasGlyph(const GlyphName: string): Boolean; override;
  end;

  // Patches the bytes of a real font and builds collections out of them
  TTrueTypeTestData = class
  public
    const DirectoryHeaderSize = 12;
    const DirectoryEntrySize = 16;

  public
    class function Unsigned16(const Data: TBytes; const Position: Integer): Integer; static;
    class function Unsigned32(const Data: TBytes; const Position: Integer): Int64; static;
    class procedure Write16(const Data: TBytes; const Position, Value: Integer); static;
    class procedure Write32(const Data: TBytes; const Position: Integer; const Value: UInt32); static;

    // The position of the directory entry of a table
    class function DirectoryEntry(const Data: TBytes; const Tag: string): Integer; static;
    class function TableOffset(const Data: TBytes; const Tag: string): Integer; static;
    class function TableLength(const Data: TBytes; const Tag: string): Integer; static;
    // Puts the bytes where the table was, under a new tag. The new table has to fit in the old one.
    class procedure ReplaceTable(const Data: TBytes; const OldTag, NewTag: string; const NewBytes: TBytes); static;

    // A ttcf file with the fonts after the header. The table offsets of each font are moved to match.
    class function BuildCollection(const Fonts: array of TBytes; const Version: Single = 1.0): TBytes; static;
  end;

implementation

uses
  System.Math;

{ TTestByteWriter }

procedure TTestByteWriter.Reserve(const Count: Integer);
begin
  if FLength + Count > System.Length(FBytes) then
  begin
    SetLength(FBytes, Max(FLength + Count, System.Length(FBytes) * 2));
  end;
end;

procedure TTestByteWriter.U8(const Value: Integer);
begin
  Reserve(1);
  FBytes[FLength] := Byte(Value);
  Inc(FLength);
end;

procedure TTestByteWriter.U16(const Value: Integer);
begin
  U8(Value shr 8);
  U8(Value);
end;

procedure TTestByteWriter.U32(const Value: Int64);
begin
  U16(Integer(Value shr 16));
  U16(Integer(Value and $FFFF));
end;

procedure TTestByteWriter.Zeros(const Count: Integer);
begin
  for var Index := 1 to Count do
  begin
    U8(0);
  end;
end;

procedure TTestByteWriter.Append(const Bytes: TBytes);
begin
  for var Value in Bytes do
  begin
    U8(Value);
  end;
end;

function TTestByteWriter.ToBytes: TBytes;
begin
  Result := Copy(FBytes, 0, FLength);
end;

{ TTestTableHost }

constructor TTestTableHost.Create(const NumberOfGlyphs: Integer);
begin
  inherited Create;
  FTables := TObjectDictionary<string, TTTFTable>.Create([doOwnsValues]);
  FNumberOfGlyphs := NumberOfGlyphs;
end;

destructor TTestTableHost.Destroy;
begin
  FHeader.Free;
  FTables.Free;
  inherited Destroy;
end;

procedure TTestTableHost.AddTable(const Table: TTTFTable);
begin
  FTables.AddOrSetValue(Table.Tag, Table);
end;

function TTestTableHost.NumberOfGlyphs: Integer;
begin
  Result := FNumberOfGlyphs;
end;

function TTestTableHost.HorizontalHeader: THorizontalHeaderTable;
begin
  if not Assigned(FHeader) then
  begin
    FHeader := THorizontalHeaderTable.Create(THorizontalHeaderTable.TableTag, 0, 0, 0);
  end;
  Result := FHeader;
end;

function TTestTableHost.TryGetTable(const Tag: string; out Table: TTTFTable): Boolean;
begin
  Result := FTables.TryGetValue(Tag, Table);
end;

function TTestTableHost.Name: string;
begin
  Result := 'TestHost';
end;

function TTestTableHost.FontBBox: TBoundingBox;
begin
  Result := TBoundingBox.Create(0, 0, 0, 0);
end;

function TTestTableHost.FontMatrix: TArray<Single>;
begin
  Result := [0.001, 0, 0, 0.001, 0, 0];
end;

function TTestTableHost.GetWidth(const GlyphName: string): Single;
begin
  Result := 0;
end;

function TTestTableHost.HasGlyph(const GlyphName: string): Boolean;
begin
  Result := False;
end;

{ TTrueTypeTestData }

class function TTrueTypeTestData.Unsigned16(const Data: TBytes; const Position: Integer): Integer;
begin
  Result := (Data[Position] shl 8) or Data[Position + 1];
end;

class function TTrueTypeTestData.Unsigned32(const Data: TBytes; const Position: Integer): Int64;
begin
  Result := (Int64(Unsigned16(Data, Position)) shl 16) or Unsigned16(Data, Position + 2);
end;

class procedure TTrueTypeTestData.Write16(const Data: TBytes; const Position, Value: Integer);
begin
  Data[Position] := Byte(Value shr 8);
  Data[Position + 1] := Byte(Value);
end;

class procedure TTrueTypeTestData.Write32(const Data: TBytes; const Position: Integer; const Value: UInt32);
begin
  Write16(Data, Position, Integer(Value shr 16));
  Write16(Data, Position + 2, Integer(Value and $FFFF));
end;

class function TTrueTypeTestData.DirectoryEntry(const Data: TBytes; const Tag: string): Integer;
begin
  const NumberOfTables = Unsigned16(Data, 4);
  for var Index := 0 to NumberOfTables - 1 do
  begin
    const Position = DirectoryHeaderSize + (Index * DirectoryEntrySize);
    const EntryTag = string.Create([Char(Data[Position]), Char(Data[Position + 1]), Char(Data[Position + 2]), Char(Data[Position + 3])]);
    if EntryTag = Tag then
    begin
      Exit(Position);
    end;
  end;
  raise EArgumentException.CreateFmt('Test font has no table %s', [Tag]);
end;

class function TTrueTypeTestData.TableOffset(const Data: TBytes; const Tag: string): Integer;
begin
  Result := Integer(Unsigned32(Data, DirectoryEntry(Data, Tag) + 8));
end;

class function TTrueTypeTestData.TableLength(const Data: TBytes; const Tag: string): Integer;
begin
  Result := Integer(Unsigned32(Data, DirectoryEntry(Data, Tag) + 12));
end;

class procedure TTrueTypeTestData.ReplaceTable(const Data: TBytes; const OldTag, NewTag: string; const NewBytes: TBytes);
begin
  const Entry = DirectoryEntry(Data, OldTag);
  const Offset = Integer(Unsigned32(Data, Entry + 8));
  const OldLength = Integer(Unsigned32(Data, Entry + 12));
  if System.Length(NewBytes) > OldLength then
  begin
    raise EArgumentException.CreateFmt('The new %s table (%d bytes) does not fit in the old %s table (%d bytes)',
                                       [NewTag, System.Length(NewBytes), OldTag, OldLength]);
  end;

  for var Index := 0 to 3 do
  begin
    Data[Entry + Index] := Byte(NewTag[Index + 1]);
  end;
  Write32(Data, Entry + 12, UInt32(System.Length(NewBytes)));
  FillChar(Data[Offset], OldLength, 0);
  if System.Length(NewBytes) > 0 then
  begin
    Move(NewBytes[0], Data[Offset], System.Length(NewBytes));
  end;
end;

class function TTrueTypeTestData.BuildCollection(const Fonts: array of TBytes; const Version: Single): TBytes;
begin
  const HeaderSize = 12 + (4 * System.Length(Fonts)) + 6;
  const Writer = TTestByteWriter.Create;
  try
    Writer.U8(Ord('t'));
    Writer.U8(Ord('t'));
    Writer.U8(Ord('c'));
    Writer.U8(Ord('f'));
    Writer.U16(Trunc(Version));
    Writer.U16(Round(Frac(Version) * 65536));
    Writer.U32(System.Length(Fonts));

    var Start := HeaderSize;
    for var Font in Fonts do
    begin
      Writer.U32(Start);
      Inc(Start, System.Length(Font));
    end;
    Writer.Zeros(6);

    Start := HeaderSize;
    for var Font in Fonts do
    begin
      const Moved = Copy(Font, 0, System.Length(Font));
      const NumberOfTables = Unsigned16(Moved, 4);
      for var Index := 0 to NumberOfTables - 1 do
      begin
        const OffsetField = DirectoryHeaderSize + (Index * DirectoryEntrySize) + 8;
        Write32(Moved, OffsetField, UInt32(Unsigned32(Moved, OffsetField) + Start));
      end;
      Writer.Append(Moved);
      Inc(Start, System.Length(Moved));
    end;
    Result := Writer.ToBytes;
  finally
    Writer.Free;
  end;
end;

end.
