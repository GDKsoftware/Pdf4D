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
  Pdf4D.FontBox.TrueType.Tables,
  Pdf4D.FontBox.TrueType.Cmap,
  Pdf4D.FontBox.TrueType.Post,
  Pdf4D.FontBox.TrueType.Vertical;

type
  // Tables are read when they are first asked for, as in PDFBox. That makes the font a single-threaded object until
  // ReadAllTables has run: after it the tables, the cached counts and the glyph name lookup are all filled, AddTable and Version
  // refuse changes, and a font on a memory stream can be shared between threads (its table bytes are copied from immutable data).
  // A font on a random-access stream stays single-threaded, because that stream has one position. The parser calls ReadAllTables
  // before it hands out a font.
  // The font owns its tables and its data stream.
  TTrueTypeFont = class(TTTFTableHost)
  private
    const DefaultAdvanceWidth = 250;
    const NotParseTimeMessage = 'The font is read-only after its tables have been read';
    const UnicodeNameLength = 7;

  private
    FData: TTTFDataStream;
    FTables: TObjectDictionary<string, TTTFTable>;
    FVersion: Single;
    FNumberOfGlyphs: Integer;
    FUnitsPerEm: Integer;
    FPostScriptNames: TDictionary<string, Integer>;
    FIsReadOnly: Boolean;

    class function TryParseUnicodeName(const Name: string; out CodePoint: Integer): Boolean; static;
    class function TryParseHexNumber(const Text: string; out Value: Integer): Boolean; static;
    class function TryParseGlyphIdName(const Name: string; out GID: Integer): Boolean; static;

    function RequiredTable(const Tag: string): TTTFTable;
    function BoxScale: Single;
    procedure ReadTable(const Table: TTTFTable);
    procedure GuardTableRange(const Table: TTTFTable);
    procedure ReadPostScriptNames;
    function TryGetPreferredUnicodeSubtable(const Cmap: TCmapTable; out Subtable: TCmapSubtable): Boolean;

  protected
    procedure SetVersion(const Value: Single); virtual;

  public
    // Takes ownership of the data stream
    constructor Create(const Data: TTTFDataStream);
    destructor Destroy; override;

    // Only while the font is parsed
    procedure AddTable(const Table: TTTFTable);
    function TableTags: TArray<string>;
    // Whether the font has the table; the table is not read
    function HasTable(const Tag: string): Boolean;
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
    function TryGetCmap(out Cmap: TCmapTable): Boolean;
    function TryGetPostScript(out PostScript: TPostScriptTable): Boolean;
    function TryGetVerticalHeader(out VerticalHeader: TVerticalHeaderTable): Boolean;
    function TryGetVerticalMetrics(out VerticalMetrics: TVerticalMetricsTable): Boolean;

    // The best Unicode cmap of the font, in the order of PDFBox: Unicode full, Windows full, Unicode BMP, Windows BMP, Windows symbol,
    // Unicode 1.1. When there is none a strict lookup fails; a lenient one takes the first subtable of the cmap, whatever its encoding.
    function TryGetUnicodeCmapLookup(const IsStrict: Boolean; out Lookup: TCmapSubtable): Boolean;
    // The strict lookup; raises EPdfParseException when the font has no Unicode cmap
    function GetUnicodeCmapLookup: TCmapSubtable;
    // The glyph for a PostScript name: the post table first, then uniXXXX through the Unicode cmap, then gNNN. 0 when there is none.
    function NameToGID(const Name: string): Integer;

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

    // Set by the parser only
    property Version: Single read FVersion write SetVersion;
  end;

implementation

uses
  System.Generics.Defaults,
  Pdf4D.Common.Defines;

type
  TCmapPreference = record
    PlatformId: Integer;
    EncodingId: Integer;
  end;

const
  UnicodePreferences: array[0..5] of TCmapPreference = (
    (PlatformId: TCmapTable.PlatformUnicode; EncodingId: TCmapTable.EncodingUnicode20Full),
    (PlatformId: TCmapTable.PlatformWindows; EncodingId: TCmapTable.EncodingWinUnicodeFull),
    (PlatformId: TCmapTable.PlatformUnicode; EncodingId: TCmapTable.EncodingUnicode20Bmp),
    (PlatformId: TCmapTable.PlatformWindows; EncodingId: TCmapTable.EncodingWinUnicodeBmp),
    // Microsoft calls "Symbol" a Unicode encoding with a non-standard character set
    (PlatformId: TCmapTable.PlatformWindows; EncodingId: TCmapTable.EncodingWinSymbol),
    // PDFBOX-6015
    (PlatformId: TCmapTable.PlatformUnicode; EncodingId: TCmapTable.EncodingUnicode11)
  );

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
  FPostScriptNames.Free;
  FTables.Free;
  FData.Free;
  inherited Destroy;
end;

procedure TTrueTypeFont.SetVersion(const Value: Single);
begin
  if FIsReadOnly then
  begin
    raise EInvalidOpException.Create(NotParseTimeMessage);
  end;
  FVersion := Value;
end;

procedure TTrueTypeFont.AddTable(const Table: TTTFTable);
begin
  if FIsReadOnly then
  begin
    raise EInvalidOpException.Create(NotParseTimeMessage);
  end;
  FTables.AddOrSetValue(Table.Tag, Table);
end;

function TTrueTypeFont.HasTable(const Tag: string): Boolean;
begin
  Result := FTables.ContainsKey(Tag);
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

  Result := FData.ReadRange(Table.Offset, Integer(Table.Length));
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

  // These fill the cached counts and the glyph name lookup, so a shared font never changes after this
  NumberOfGlyphs;
  UnitsPerEm;
  ReadPostScriptNames;
  FIsReadOnly := True;
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

function TTrueTypeFont.TryGetCmap(out Cmap: TCmapTable): Boolean;
begin
  var Table: TTTFTable;
  Result := TryGetTable(TCmapTable.TableTag, Table);
  if Result then
  begin
    Cmap := Table as TCmapTable;
  end
  else
  begin
    Cmap := nil;
  end;
end;

function TTrueTypeFont.TryGetPostScript(out PostScript: TPostScriptTable): Boolean;
begin
  var Table: TTTFTable;
  Result := TryGetTable(TPostScriptTable.TableTag, Table);
  if Result then
  begin
    PostScript := Table as TPostScriptTable;
  end
  else
  begin
    PostScript := nil;
  end;
end;

function TTrueTypeFont.TryGetVerticalHeader(out VerticalHeader: TVerticalHeaderTable): Boolean;
begin
  var Table: TTTFTable;
  Result := TryGetTable(TVerticalHeaderTable.TableTag, Table);
  if Result then
  begin
    VerticalHeader := Table as TVerticalHeaderTable;
  end
  else
  begin
    VerticalHeader := nil;
  end;
end;

function TTrueTypeFont.TryGetVerticalMetrics(out VerticalMetrics: TVerticalMetricsTable): Boolean;
begin
  var Table: TTTFTable;
  Result := TryGetTable(TVerticalMetricsTable.TableTag, Table);
  if Result then
  begin
    VerticalMetrics := Table as TVerticalMetricsTable;
  end
  else
  begin
    VerticalMetrics := nil;
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

  Result := Single(1000) / Units;
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
  Result := [Single(0.001) * Scale, 0, 0, Single(0.001) * Scale, 0, 0];
end;

procedure TTrueTypeFont.ReadPostScriptNames;
begin
  if Assigned(FPostScriptNames) then
  begin
    Exit;
  end;

  // Only a complete lookup is published; a failing post table leaves the font without one
  const Names = TDictionary<string, Integer>.Create;
  try
    var PostScript: TPostScriptTable;
    if TryGetPostScript(PostScript) then
    begin
      for var GID := 0 to PostScript.GlyphNameCount - 1 do
      begin
        var GlyphName: string;
        if PostScript.TryGetName(GID, GlyphName) then
        begin
          Names.AddOrSetValue(GlyphName, GID);
        end;
      end;
    end;
  except
    Names.Free;
    raise;
  end;
  FPostScriptNames := Names;
end;

function TTrueTypeFont.TryGetPreferredUnicodeSubtable(const Cmap: TCmapTable; out Subtable: TCmapSubtable): Boolean;
begin
  for var Preference in UnicodePreferences do
  begin
    if Cmap.TryGetSubtable(Preference.PlatformId, Preference.EncodingId, Subtable) then
    begin
      Exit(True);
    end;
  end;

  Subtable := nil;
  Result := False;
end;

function TTrueTypeFont.TryGetUnicodeCmapLookup(const IsStrict: Boolean; out Lookup: TCmapSubtable): Boolean;
begin
  Lookup := nil;
  var Cmap: TCmapTable;
  if not TryGetCmap(Cmap) then
  begin
    Exit(False);
  end;

  if TryGetPreferredUnicodeSubtable(Cmap, Lookup) then
  begin
    Exit(True);
  end;

  // Falling back to the first subtable may give poor results, because it need not be Unicode
  const CanFallBack = ((not IsStrict) and (Cmap.Subtables.Count > 0));
  if CanFallBack then
  begin
    Lookup := Cmap.Subtables[0];
  end;
  Result := CanFallBack;
end;

function TTrueTypeFont.GetUnicodeCmapLookup: TCmapSubtable;
begin
  var Cmap: TCmapTable;
  if not TryGetCmap(Cmap) then
  begin
    raise EPdfParseException.CreateFmt('The TrueType font %s does not contain a ''cmap'' table', [Name]);
  end;

  if not TryGetUnicodeCmapLookup(True, Result) then
  begin
    raise EPdfParseException.Create('The TrueType font does not contain a Unicode cmap');
  end;
end;

// Java's Integer.parseInt(text, 16): an optional sign and hexadecimal digits
class function TTrueTypeFont.TryParseHexNumber(const Text: string; out Value: Integer): Boolean;
begin
  Value := 0;
  const HasSign = ((Text.Length > 0) and ((Text[1] = '-') or (Text[1] = '+')));
  const IsNegative = ((Text.Length > 0) and (Text[1] = '-'));
  var FirstDigit := 1;
  if HasSign then
  begin
    FirstDigit := 2;
  end;

  if FirstDigit > Text.Length then
  begin
    Exit(False);
  end;

  for var Position := FirstDigit to Text.Length do
  begin
    const Digit = Pos(UpCase(Text[Position]), '0123456789ABCDEF') - 1;
    if Digit < 0 then
    begin
      Exit(False);
    end;
    Value := (Value * 16) + Digit;
  end;

  if IsNegative then
  begin
    Value := -Value;
  end;
  Result := True;
end;

// uniXXXX with exactly one four-digit number, the form PDFBox accepts
class function TTrueTypeFont.TryParseUnicodeName(const Name: string; out CodePoint: Integer): Boolean;
begin
  CodePoint := -1;
  const HasUnicodeForm = ((Name.Length = UnicodeNameLength) and (Copy(Name, 1, 3) = 'uni'));
  if not HasUnicodeForm then
  begin
    Exit(False);
  end;

  var Number: Integer;
  if not TryParseHexNumber(Copy(Name, 4, 4), Number) then
  begin
    Exit(False);
  end;

  // The disallowed code area (the surrogates) gives an empty result
  const IsDisallowed = ((Number > $D7FF) and (Number < $E000));
  if IsDisallowed then
  begin
    Exit(False);
  end;

  CodePoint := Number and $FFFF;
  Result := True;
end;

// PDFBOX-5604: gNNN is a glyph id. Java's "g\d+" and Integer.parseInt; a number that does not fit is no match.
class function TTrueTypeFont.TryParseGlyphIdName(const Name: string; out GID: Integer): Boolean;
begin
  GID := 0;
  const HasGlyphIdForm = ((Name.Length > 1) and (Name[1] = 'g'));
  if not HasGlyphIdForm then
  begin
    Exit(False);
  end;

  for var Position := 2 to Name.Length do
  begin
    if (Name[Position] < '0') or (Name[Position] > '9') then
    begin
      Exit(False);
    end;
  end;

  Result := TryStrToInt(Copy(Name, 2, Name.Length - 1), GID);
end;

function TTrueTypeFont.NameToGID(const Name: string): Integer;
begin
  ReadPostScriptNames;
  var GID: Integer;
  const IsInPostTable = (FPostScriptNames.TryGetValue(Name, GID) and (GID > 0) and (GID < NumberOfGlyphs));
  if IsInPostTable then
  begin
    Exit(GID);
  end;

  var CodePoint: Integer;
  if TryParseUnicodeName(Name, CodePoint) then
  begin
    // PDFBox fails on a missing cmap here; the glyph is then simply not there
    var Lookup: TCmapSubtable;
    if TryGetUnicodeCmapLookup(False, Lookup) then
    begin
      Exit(Lookup.GetGlyphId(CodePoint));
    end;
    Exit(0);
  end;

  if TryParseGlyphIdName(Name, GID) then
  begin
    Exit(GID);
  end;

  Result := 0;
end;

function TTrueTypeFont.GetWidth(const GlyphName: string): Single;
begin
  Result := GetAdvanceWidth(NameToGID(GlyphName));
end;

function TTrueTypeFont.HasGlyph(const GlyphName: string): Boolean;
begin
  Result := (NameToGID(GlyphName) <> 0);
end;

end.
