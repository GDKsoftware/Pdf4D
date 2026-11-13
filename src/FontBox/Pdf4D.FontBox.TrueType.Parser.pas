// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/TTFParser.java (3.0.8)
unit Pdf4D.FontBox.TrueType.Parser;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Common.Log,
  Pdf4D.FontBox.TrueType.DataStream,
  Pdf4D.FontBox.TrueType.Tables,
  Pdf4D.FontBox.TrueType.Font;

type
  // Parses a TrueType font with glyf outlines. A broken font raises EPdfParseException. The tables the later tasks port
  // (cmap, post, loca, glyf) are only checked for presence here.
  TTTFParser = class
  private
    const CffTag = 'CFF ';
    const PostTag = 'post';
    const LocaTag = 'loca';
    const GlyfTag = 'glyf';
    const CmapTag = 'cmap';

  private
    FIsEmbedded: Boolean;
    FLog: TPdfLog;

    class function CreateTable(const Tag: string; const CheckSum, Offset, Length: Int64): TTTFTable; static;

    function TryReadTableDirectoryEntry(const Data: TTTFDataStream; out Table: TTTFTable): Boolean;
    procedure ReadTableDirectory(const Font: TTrueTypeFont; const Data: TTTFDataStream);
    procedure AddTableInsideData(const Font: TTrueTypeFont; const Table: TTTFTable);
    procedure GuardMandatoryTable(const Font: TTrueTypeFont; const Tag: string);
    procedure GuardMandatoryTables(const Font: TTrueTypeFont);

  public
    // The log is not owned and only used while Parse runs
    constructor Create(const IsEmbedded: Boolean = False; const Log: TPdfLog = nil);

    function Parse(const Data: TBytes): TTrueTypeFont;
  end;

implementation

uses
  Pdf4D.Common.Defines;

{ TTTFParser }

constructor TTTFParser.Create(const IsEmbedded: Boolean; const Log: TPdfLog);
begin
  inherited Create;
  FIsEmbedded := IsEmbedded;
  FLog := Log;
end;

class function TTTFParser.CreateTable(const Tag: string; const CheckSum, Offset, Length: Int64): TTTFTable;
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
  else
  begin
    Result := TTTFTable.Create(Tag, CheckSum, Offset, Length);
  end;
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

procedure TTTFParser.ReadTableDirectory(const Font: TTrueTypeFont; const Data: TTTFDataStream);
begin
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
  var CffTable: TTTFTable;
  const HasCff = Font.TryGetTable(CffTag, CffTable);
  if HasCff then
  begin
    raise EPdfParseException.Create('True Type fonts using CFF outlines are not supported');
  end;

  GuardMandatoryTable(Font, THeaderTable.TableTag);
  GuardMandatoryTable(Font, THorizontalHeaderTable.TableTag);
  GuardMandatoryTable(Font, TMaximumProfileTable.TableTag);
  if not FIsEmbedded then
  begin
    GuardMandatoryTable(Font, PostTag);
  end;

  GuardMandatoryTable(Font, LocaTag);
  GuardMandatoryTable(Font, GlyfTag);
  if not FIsEmbedded then
  begin
    GuardMandatoryTable(Font, TNamingTable.TableTag);
  end;

  GuardMandatoryTable(Font, THorizontalMetricsTable.TableTag);
  if not FIsEmbedded then
  begin
    GuardMandatoryTable(Font, CmapTag);
  end;
end;

function TTTFParser.Parse(const Data: TBytes): TTrueTypeFont;
begin
  const Stream = TTTFMemoryDataStream.Create(Data);
  // The font owns the stream from here on
  Result := TTrueTypeFont.Create(Stream);
  try
    Result.Log := FLog;
    try
      ReadTableDirectory(Result, Stream);
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

end.
