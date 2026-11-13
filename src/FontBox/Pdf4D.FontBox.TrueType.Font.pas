// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/TrueTypeFont.java (3.0.8)
unit Pdf4D.FontBox.TrueType.Font;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.FontBox.BoundingBox,
  Pdf4D.FontBox.TrueType.DataStream,
  Pdf4D.FontBox.TrueType.Tables;

type
  // Tables are read when they are first asked for, as in PDFBox. That makes the font a single-threaded object until
  // ReadAllTables has run: after it nothing changes any more and the font can be shared.
  // The font owns its tables and its data stream.
  TTrueTypeFont = class(TTTFTableHost)
  private
    const DefaultAdvanceWidth = 250;
    const FontUnitsPerThousand = 1000.0;

  private
    FData: TTTFDataStream;
    FTables: TObjectDictionary<string, TTTFTable>;
    FVersion: Single;
    FNumberOfGlyphs: Integer;
    FUnitsPerEm: Integer;

    function RequiredTable(const Tag: string): TTTFTable;
    function BoxScale: Single;
    procedure ReadTable(const Table: TTTFTable);
    procedure GuardTableRange(const Table: TTTFTable);

  public
    // Takes ownership of the data stream
    constructor Create(const Data: TTTFDataStream);
    destructor Destroy; override;

    procedure AddTable(const Table: TTTFTable);
    function TableTags: TArray<string>;
    function GetTableBytes(const Tag: string): TBytes;
    function TryGetTable(const Tag: string; out Table: TTTFTable): Boolean; override;
    procedure ReadAllTables;

    // The four mandatory tables raise EPdfParseException when the font has none
    function Header: THeaderTable;
    function HorizontalHeader: THorizontalHeaderTable; override;
    function MaximumProfile: TMaximumProfileTable;
    function HorizontalMetrics: THorizontalMetricsTable;
    function TryGetNaming(out Naming: TNamingTable): Boolean;
    function TryGetOS2Windows(out OS2Windows: TOS2WindowsMetricsTable): Boolean;

    function NumberOfGlyphs: Integer; override;
    function UnitsPerEm: Integer;
    function GetAdvanceWidth(const GID: Integer): Integer;
    function OriginalDataSize: Int64;
    function OriginalData: TBytes;

    function Name: string; override;
    function FontBBox: TBoundingBox; override;
    function FontMatrix: TArray<Single>; override;
    function GetWidth(const GlyphName: string): Single; override;
    function HasGlyph(const GlyphName: string): Boolean; override;

    property Version: Single read FVersion write FVersion;
  end;

implementation

uses
  System.Generics.Defaults,
  Pdf4D.Common.Defines;

{ TTrueTypeFont }

constructor TTrueTypeFont.Create(const Data: TTTFDataStream);
begin
  inherited Create;
  FData := Data;
  FTables := TObjectDictionary<string, TTTFTable>.Create([doOwnsValues]);
  FNumberOfGlyphs := -1;
  FUnitsPerEm := -1;
end;

destructor TTrueTypeFont.Destroy;
begin
  FTables.Free;
  FData.Free;
  inherited Destroy;
end;

procedure TTrueTypeFont.AddTable(const Table: TTTFTable);
begin
  FTables.AddOrSetValue(Table.Tag, Table);
end;

function TTrueTypeFont.TableTags: TArray<string>;
begin
  Result := FTables.Keys.ToArray;
  TArray.Sort<string>(Result, TStringComparer.Ordinal);
end;

procedure TTrueTypeFont.GuardTableRange(const Table: TTTFTable);
begin
  const Size = FData.OriginalDataSize;
  const IsInsideData = ((Table.Length <= Size) and (Table.Offset <= Size - Table.Length));
  const FitsInArray = (Table.Length <= MaxInt);
  if not (IsInsideData and FitsInArray) then
  begin
    raise EPdfParseException.CreateFmt('Table "%s" (offset %d, length %d) lies outside the font data of %d bytes',
                                       [Table.Tag, Table.Offset, Table.Length, Size]);
  end;
end;

function TTrueTypeFont.GetTableBytes(const Tag: string): TBytes;
begin
  var Table: TTTFTable;
  if not FTables.TryGetValue(Tag, Table) then
  begin
    raise EPdfParseException.CreateFmt('The font has no table "%s"', [Tag]);
  end;

  GuardTableRange(Table);

  const SavedPosition = FData.CurrentPosition;
  try
    FData.Seek(Table.Offset);
    Result := FData.ReadBytes(Integer(Table.Length));
  finally
    FData.Seek(SavedPosition);
  end;
end;

procedure TTrueTypeFont.ReadTable(const Table: TTTFTable);
begin
  GuardTableRange(Table);

  const SavedPosition = FData.CurrentPosition;
  try
    try
      FData.Seek(Table.Offset);
      Table.Read(Self, FData);
    except
      on Failure: Exception do
      begin
        if TPdfFailure.IsInputFailure(Failure) then
        begin
          raise EPdfParseException.CreateFmt('Cannot read table "%s": %s', [Table.Tag, Failure.Message]);
        end;
        raise;
      end;
    end;
  finally
    FData.Seek(SavedPosition);
  end;
end;

function TTrueTypeFont.TryGetTable(const Tag: string; out Table: TTTFTable): Boolean;
begin
  Result := FTables.TryGetValue(Tag, Table);
  if Result and not Table.Initialized then
  begin
    ReadTable(Table);
  end;
end;

procedure TTrueTypeFont.ReadAllTables;
begin
  for var Table in FTables.Values.ToArray do
  begin
    if not Table.Initialized then
    begin
      ReadTable(Table);
    end;
  end;
end;

function TTrueTypeFont.RequiredTable(const Tag: string): TTTFTable;
begin
  if not TryGetTable(Tag, Result) then
  begin
    raise EPdfParseException.CreateFmt('The font has no "%s" table', [Tag]);
  end;
end;

function TTrueTypeFont.Header: THeaderTable;
begin
  Result := RequiredTable(THeaderTable.TableTag) as THeaderTable;
end;

function TTrueTypeFont.HorizontalHeader: THorizontalHeaderTable;
begin
  Result := RequiredTable(THorizontalHeaderTable.TableTag) as THorizontalHeaderTable;
end;

function TTrueTypeFont.MaximumProfile: TMaximumProfileTable;
begin
  Result := RequiredTable(TMaximumProfileTable.TableTag) as TMaximumProfileTable;
end;

function TTrueTypeFont.HorizontalMetrics: THorizontalMetricsTable;
begin
  Result := RequiredTable(THorizontalMetricsTable.TableTag) as THorizontalMetricsTable;
end;

function TTrueTypeFont.TryGetNaming(out Naming: TNamingTable): Boolean;
begin
  var Table: TTTFTable;
  Result := TryGetTable(TNamingTable.TableTag, Table);
  if Result then
  begin
    Naming := Table as TNamingTable;
  end
  else
  begin
    Naming := nil;
  end;
end;

function TTrueTypeFont.TryGetOS2Windows(out OS2Windows: TOS2WindowsMetricsTable): Boolean;
begin
  var Table: TTTFTable;
  Result := TryGetTable(TOS2WindowsMetricsTable.TableTag, Table);
  if Result then
  begin
    OS2Windows := Table as TOS2WindowsMetricsTable;
  end
  else
  begin
    OS2Windows := nil;
  end;
end;

function TTrueTypeFont.NumberOfGlyphs: Integer;
begin
  if FNumberOfGlyphs = -1 then
  begin
    var Table: TTTFTable;
    if TryGetTable(TMaximumProfileTable.TableTag, Table) then
    begin
      FNumberOfGlyphs := (Table as TMaximumProfileTable).NumGlyphs;
    end
    else
    begin
      FNumberOfGlyphs := 0;
    end;
  end;
  Result := FNumberOfGlyphs;
end;

function TTrueTypeFont.UnitsPerEm: Integer;
begin
  if FUnitsPerEm = -1 then
  begin
    var Table: TTTFTable;
    if TryGetTable(THeaderTable.TableTag, Table) then
    begin
      FUnitsPerEm := (Table as THeaderTable).UnitsPerEm;
    end
    else
    begin
      FUnitsPerEm := 0;
    end;
  end;
  Result := FUnitsPerEm;
end;

function TTrueTypeFont.GetAdvanceWidth(const GID: Integer): Integer;
begin
  var Table: TTTFTable;
  if TryGetTable(THorizontalMetricsTable.TableTag, Table) then
  begin
    Result := (Table as THorizontalMetricsTable).GetAdvanceWidth(GID);
  end
  else
  begin
    Result := DefaultAdvanceWidth;
  end;
end;

function TTrueTypeFont.OriginalDataSize: Int64;
begin
  Result := FData.OriginalDataSize;
end;

function TTrueTypeFont.OriginalData: TBytes;
begin
  Result := FData.OriginalData;
end;

function TTrueTypeFont.Name: string;
begin
  var Naming: TNamingTable;
  if TryGetNaming(Naming) then
  begin
    Result := Naming.PostScriptName;
  end
  else
  begin
    Result := '';
  end;
end;

// PDFBox divides by unitsPerEm without a check and gets infinity for 0; a font without units uses scale 1
function TTrueTypeFont.BoxScale: Single;
begin
  const Units = UnitsPerEm;
  if Units = 0 then
  begin
    Exit(1);
  end;

  Result := FontUnitsPerThousand / Units;
end;

function TTrueTypeFont.FontBBox: TBoundingBox;
begin
  const HeaderTable = Header;
  const Scale = BoxScale;
  Result := TBoundingBox.Create(HeaderTable.XMin * Scale, HeaderTable.YMin * Scale, HeaderTable.XMax * Scale, HeaderTable.YMax * Scale);
end;

function TTrueTypeFont.FontMatrix: TArray<Single>;
begin
  const Scale = BoxScale;
  Result := [0.001 * Scale, 0, 0, 0.001 * Scale, 0, 0];
end;

function TTrueTypeFont.GetWidth(const GlyphName: string): Single;
begin
  raise ENotImplemented.Create('Glyph names of a TrueType font need the post table, which is not ported yet');
end;

function TTrueTypeFont.HasGlyph(const GlyphName: string): Boolean;
begin
  raise ENotImplemented.Create('Glyph names of a TrueType font need the post table, which is not ported yet');
end;

end.
