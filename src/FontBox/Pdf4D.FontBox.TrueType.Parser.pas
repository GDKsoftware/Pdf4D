// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/TTFParser.java (3.0.8)
unit Pdf4D.FontBox.TrueType.Parser;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Common.Log,
  Pdf4D.IO.RandomAccessRead,
  Pdf4D.FontBox.TrueType.DataStream,
  Pdf4D.FontBox.TrueType.Tables,
  Pdf4D.FontBox.TrueType.Font,
  Pdf4D.FontBox.TrueType.Glyph,
  Pdf4D.FontBox.TrueType.Headers;

type
  // Parses a TrueType font with glyf outlines. A broken font raises EPdfParseException. The font that comes out has read all its
  // tables (ReadAllTables), so it can be shared. The glyf table keeps its glyph data and reads a glyph when its path is asked for.
  // The OpenType parser (TOTFParser) is a descendant that accepts CFF outlines.
  TTTFParser = class
  private
    const CffTag = 'CFF ';
    const LocaTag = 'loca';
    const GlyfTag = 'glyf';
    const GcidTag = 'gcid';

  private
    FIsEmbedded: Boolean;
    FLog: TPdfLog;
    // The headers that ParseTableHeaders is collecting
    FHeaders: TFontHeaders;

    function TryReadTableDirectoryEntry(const Data: TTTFDataStream; out Table: TTTFTable): Boolean;
    procedure ReadTableDirectory(const Font: TTrueTypeFont; const Data: TTTFDataStream; const DirectoryOffset: Int64);
    procedure AddTableInsideData(const Font: TTrueTypeFont; const Table: TTTFTable);
    procedure GuardMandatoryTable(const Font: TTrueTypeFont; const Tag: string);

    function ReadTableHeaders(const Source: TRandomAccessRead; const DirectoryOffset: Int64): TFontHeaders;
    procedure ReadNameHeaders(const Font: TTrueTypeFont);
    procedure ReadMacStyleHeader(const Font: TTrueTypeFont);
    procedure ReadOS2Headers(const Font: TTrueTypeFont);
    procedure ReadCidSystemInfoHeaders(const Font: TTrueTypeFont);
    procedure ReadGcidHeader(const Font: TTrueTypeFont);
    function IsOutlineKindSupported(const Font: TTrueTypeFont): Boolean;
    procedure CheckMandatoryTableHeaders(const Font: TTrueTypeFont);
    function MandatoryTableTags(const IsOpenTypePostScript: Boolean): TArray<string>;

  protected
    function NewFont(const Data: TTTFDataStream): TTrueTypeFont; virtual;
    // A table of a known type, or a table that is only kept as bytes
    function CreateTable(const Tag: string; const CheckSum, Offset, Length: Int64): TTTFTable; virtual;
    function AllowCFF: Boolean; virtual;
    function IsPostScript(const Font: TTrueTypeFont): Boolean; virtual;
    // False for an OpenType font with CFF2 outlines only
    function IsSupportedPostScript(const Font: TTrueTypeFont): Boolean; virtual;
    procedure GuardMandatoryTables(const Font: TTrueTypeFont); virtual;

  public
    // The log is not owned and only used while Parse runs
    constructor Create(const IsEmbedded: Boolean = False; const Log: TPdfLog = nil);

    function Parse(const Data: TBytes): TTrueTypeFont; overload;
    // For a font inside a collection: the table directory starts at DirectoryOffset and the table offsets count from the start of Data
    function Parse(const Data: TBytes; const DirectoryOffset: Int64): TTrueTypeFont; overload;

    // Reads only what a font scan needs: the "name", "head" and "OS/2" tables and the ROS of a CFF table. The source belongs to the
    // caller. A font that cannot be used comes back with an Error; a stream that cannot be read raises EPdfParseException.
    function ParseTableHeaders(const Source: TRandomAccessRead): TFontHeaders; overload;
    // For a font inside a collection: the table directory starts at DirectoryOffset and the table offsets count from the start
    function ParseTableHeaders(const Source: TRandomAccessRead; const DirectoryOffset: Int64): TFontHeaders; overload;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.FontBox.Cff.Parser,
  Pdf4D.FontBox.TrueType.Cmap,
  Pdf4D.FontBox.TrueType.Post,
  Pdf4D.FontBox.TrueType.Vertical;

{ TTTFParser }

constructor TTTFParser.Create(const IsEmbedded: Boolean; const Log: TPdfLog);
begin
  inherited Create;
  FIsEmbedded := IsEmbedded;
  FLog := Log;
end;

function TTTFParser.CreateTable(const Tag: string; const CheckSum, Offset, Length: Int64): TTTFTable;
begin
  if Tag = THeaderTable.TableTag then
  begin
    Result := THeaderTable.Create(Tag, CheckSum, Offset, Length);
  end
  else if Tag = THorizontalHeaderTable.TableTag then
  begin
    Result := THorizontalHeaderTable.Create(Tag, CheckSum, Offset, Length);
  end
  else if Tag = TMaximumProfileTable.TableTag then
  begin
    Result := TMaximumProfileTable.Create(Tag, CheckSum, Offset, Length);
  end
  else if Tag = THorizontalMetricsTable.TableTag then
  begin
    Result := THorizontalMetricsTable.Create(Tag, CheckSum, Offset, Length);
  end
  else if Tag = TNamingTable.TableTag then
  begin
    Result := TNamingTable.Create(Tag, CheckSum, Offset, Length);
  end
  else if Tag = TOS2WindowsMetricsTable.TableTag then
  begin
    Result := TOS2WindowsMetricsTable.Create(Tag, CheckSum, Offset, Length);
  end
  else if Tag = TCmapTable.TableTag then
  begin
    Result := TCmapTable.Create(Tag, CheckSum, Offset, Length);
  end
  else if Tag = TPostScriptTable.TableTag then
  begin
    Result := TPostScriptTable.Create(Tag, CheckSum, Offset, Length);
  end
  else if Tag = TVerticalHeaderTable.TableTag then
  begin
    Result := TVerticalHeaderTable.Create(Tag, CheckSum, Offset, Length);
  end
  else if Tag = TVerticalMetricsTable.TableTag then
  begin
    Result := TVerticalMetricsTable.Create(Tag, CheckSum, Offset, Length);
  end
  else if Tag = TIndexToLocationTable.TableTag then
  begin
    Result := TIndexToLocationTable.Create(Tag, CheckSum, Offset, Length);
  end
  else if Tag = TGlyphTable.TableTag then
  begin
    Result := TGlyphTable.Create(Tag, CheckSum, Offset, Length);
  end
  else
  begin
    Result := TTTFTable.Create(Tag, CheckSum, Offset, Length);
  end;
end;

function TTTFParser.NewFont(const Data: TTTFDataStream): TTrueTypeFont;
begin
  Result := TTrueTypeFont.Create(Data);
end;

function TTTFParser.AllowCFF: Boolean;
begin
  Result := False;
end;

function TTTFParser.IsPostScript(const Font: TTrueTypeFont): Boolean;
begin
  var CffTable: TTTFTable;
  Result := Font.TryGetTable(CffTag, CffTable);
end;

function TTTFParser.IsSupportedPostScript(const Font: TTrueTypeFont): Boolean;
begin
  Result := True;
end;

// An empty table is dropped, except glyf: a font without outlines is valid
function TTTFParser.TryReadTableDirectoryEntry(const Data: TTTFDataStream; out Table: TTTFTable): Boolean;
begin
  const Tag = Data.ReadTag;
  const CheckSum = Data.ReadUnsignedInt;
  const Offset = Data.ReadUnsignedInt;
  const Length = Data.ReadUnsignedInt;

  const IsEmpty = ((Length = 0) and (Tag <> GlyfTag));
  if IsEmpty then
  begin
    Table := nil;
    Exit(False);
  end;

  Table := CreateTable(Tag, CheckSum, Offset, Length);
  Result := True;
end;

procedure TTTFParser.AddTableInsideData(const Font: TTrueTypeFont; const Table: TTTFTable);
begin
  const Size = Font.OriginalDataSize;
  const IsInsideData = (Table.Offset <= Size - Table.Length);
  if IsInsideData then
  begin
    Font.AddTable(Table);
  end
  else
  begin
    if Assigned(FLog) then
    begin
      FLog.Warning(Format('Skip table ''%s'' which goes past the file size; offset: %d, size: %d, font size: %d',
                          [Table.Tag, Table.Offset, Table.Length, Size]));
    end;
    Table.Free;
  end;
end;

procedure TTTFParser.ReadTableDirectory(const Font: TTrueTypeFont; const Data: TTTFDataStream; const DirectoryOffset: Int64);
begin
  Data.Seek(DirectoryOffset);
  Font.Version := Data.Read32Fixed;
  const NumberOfTables = Data.ReadUnsignedShort;
  Data.ReadUnsignedShort; // search range
  Data.ReadUnsignedShort; // entry selector
  Data.ReadUnsignedShort; // range shift

  for var Index := 1 to NumberOfTables do
  begin
    var Table: TTTFTable;
    if TryReadTableDirectoryEntry(Data, Table) then
    begin
      AddTableInsideData(Font, Table);
    end;
  end;
end;

procedure TTTFParser.GuardMandatoryTable(const Font: TTrueTypeFont; const Tag: string);
begin
  var Table: TTTFTable;
  if not Font.TryGetTable(Tag, Table) then
  begin
    raise EPdfParseException.CreateFmt('''%s'' table is mandatory', [Tag]);
  end;
end;

procedure TTTFParser.GuardMandatoryTables(const Font: TTrueTypeFont);
begin
  GuardMandatoryTable(Font, THeaderTable.TableTag);
  GuardMandatoryTable(Font, THorizontalHeaderTable.TableTag);
  GuardMandatoryTable(Font, TMaximumProfileTable.TableTag);
  if not FIsEmbedded then
  begin
    GuardMandatoryTable(Font, TPostScriptTable.TableTag);
  end;

  if not IsPostScript(Font) then
  begin
    GuardMandatoryTable(Font, LocaTag);
    GuardMandatoryTable(Font, GlyfTag);
  end
  else if not AllowCFF then
  begin
    raise EPdfParseException.Create('True Type fonts using CFF outlines are not supported');
  end;

  if not FIsEmbedded then
  begin
    GuardMandatoryTable(Font, TNamingTable.TableTag);
  end;

  GuardMandatoryTable(Font, THorizontalMetricsTable.TableTag);
  if not FIsEmbedded then
  begin
    GuardMandatoryTable(Font, TCmapTable.TableTag);
  end;
end;

function TTTFParser.Parse(const Data: TBytes): TTrueTypeFont;
begin
  Result := Parse(Data, 0);
end;

function TTTFParser.Parse(const Data: TBytes; const DirectoryOffset: Int64): TTrueTypeFont;
begin
  const Stream = TTTFMemoryDataStream.Create(Data);
  // The font owns the stream from here on
  Result := NewFont(Stream);
  try
    Result.Log := FLog;
    try
      ReadTableDirectory(Result, Stream, DirectoryOffset);
      Result.ReadAllTables;
      GuardMandatoryTables(Result);
    finally
      Result.Log := nil;
    end;
  except
    on Failure: Exception do
    begin
      Result.Free;
      if TPdfFailure.IsInputFailure(Failure) then
      begin
        raise EPdfParseException.CreateFmt('Cannot parse the TrueType font: %s', [Failure.Message]);
      end;
      raise;
    end;
  end;
end;

function TTTFParser.ParseTableHeaders(const Source: TRandomAccessRead): TFontHeaders;
begin
  Result := ParseTableHeaders(Source, 0);
end;

function TTTFParser.ParseTableHeaders(const Source: TRandomAccessRead; const DirectoryOffset: Int64): TFontHeaders;
begin
  try
    Result := ReadTableHeaders(Source, DirectoryOffset);
  except
    on Failure: Exception do
    begin
      if TPdfFailure.IsInputFailure(Failure) then
      begin
        raise EPdfParseException.CreateFmt('Cannot read the TrueType font headers: %s', [Failure.Message]);
      end;
      raise;
    end;
  end;
end;

function TTTFParser.ReadTableHeaders(const Source: TRandomAccessRead; const DirectoryOffset: Int64): TFontHeaders;
begin
  FHeaders := Default(TFontHeaders);
  const Stream = TTTFRandomAccessDataStream.Create(Source);
  // The font owns the stream, not the source
  const Font = NewFont(Stream);
  try
    ReadTableDirectory(Font, Stream, DirectoryOffset);
    ReadNameHeaders(Font);
    ReadMacStyleHeader(Font);
    ReadOS2Headers(Font);

    if IsOutlineKindSupported(Font) then
    begin
      CheckMandatoryTableHeaders(Font);
    end;
    Result := FHeaders;
  finally
    Font.Free;
  end;
end;

procedure TTTFParser.ReadNameHeaders(const Font: TTrueTypeFont);
begin
  var Naming: TNamingTable;
  if Font.TryGetNaming(Naming) then
  begin
    FHeaders.Name := Naming.PostScriptName;
    FHeaders.FontFamily := Naming.FontFamily;
    FHeaders.FontSubFamily := Naming.FontSubFamily;
  end;
end;

procedure TTTFParser.ReadMacStyleHeader(const Font: TTrueTypeFont);
begin
  if Font.HasTable(THeaderTable.TableTag) then
  begin
    FHeaders.HasMacStyle := True;
    FHeaders.MacStyle := Font.Header.MacStyle;
  end;
end;

procedure TTTFParser.ReadOS2Headers(const Font: TTrueTypeFont);
begin
  var OS2Windows: TOS2WindowsMetricsTable;
  if Font.TryGetOS2Windows(OS2Windows) then
  begin
    FHeaders.HasOS2Windows := True;
    FHeaders.FamilyClass := OS2Windows.FamilyClass;
    FHeaders.WeightClass := OS2Windows.WeightClass;
    FHeaders.CodePageRange1 := Integer(Cardinal(OS2Windows.CodePageRange1 and $FFFFFFFF));
    FHeaders.CodePageRange2 := Integer(Cardinal(OS2Windows.CodePageRange2 and $FFFFFFFF));
    FHeaders.Panose := Copy(OS2Windows.Panose);
  end;
end;

procedure TTTFParser.ReadCidSystemInfoHeaders(const Font: TTrueTypeFont);
begin
  const CffData = Font.GetTableBytes(CffTag);
  const CffParser = TCFFParser.Create(nil);
  try
    FHeaders.HasCIDSystemInfo := CffParser.ParseFirstSubFontROS(CffData, FHeaders.Registry, FHeaders.Ordering, FHeaders.Supplement);
  finally
    CffParser.Free;
  end;
end;

procedure TTTFParser.ReadGcidHeader(const Font: TTrueTypeFont);
begin
  var Table: TTTFTable;
  const HasGcid = (Font.TryGetTable(GcidTag, Table) and (Table.Length >= TFontHeaders.GcidLength));
  if HasGcid then
  begin
    FHeaders.Gcid := Copy(Font.GetTableBytes(GcidTag), 0, TFontHeaders.GcidLength);
  end;
end;

// Sets the error and returns False for outlines that Pdf4D does not read
function TTTFParser.IsOutlineKindSupported(const Font: TTrueTypeFont): Boolean;
begin
  Result := True;
  if AllowCFF and IsPostScript(Font) then
  begin
    if IsSupportedPostScript(Font) then
    begin
      FHeaders.IsOpenTypePostScript := True;
      ReadCidSystemInfoHeaders(Font);
    end
    else
    begin
      FHeaders.Error := 'OpenType fonts using CFF2 outlines are not supported';
      Result := False;
    end;
  end
  else if (not AllowCFF) and Font.HasTable(CffTag) then
  begin
    FHeaders.Error := 'True Type fonts using CFF outlines are not supported';
    Result := False;
  end
  else
  begin
    ReadGcidHeader(Font);
  end;
end;

function TTTFParser.MandatoryTableTags(const IsOpenTypePostScript: Boolean): TArray<string>;
begin
  Result := [THeaderTable.TableTag, THorizontalHeaderTable.TableTag, TMaximumProfileTable.TableTag, THorizontalMetricsTable.TableTag];
  if not FIsEmbedded then
  begin
    Result := Result + [TPostScriptTable.TableTag, TNamingTable.TableTag, TCmapTable.TableTag];
  end;
  if not IsOpenTypePostScript then
  begin
    Result := Result + [LocaTag, GlyfTag];
  end;
end;

procedure TTTFParser.CheckMandatoryTableHeaders(const Font: TTrueTypeFont);
begin
  for var Tag in MandatoryTableTags(FHeaders.IsOpenTypePostScript) do
  begin
    if not Font.HasTable(Tag) then
    begin
      FHeaders.Error := Format('''%s'' table is mandatory', [Tag]);
      Exit;
    end;
  end;
end;

end.
