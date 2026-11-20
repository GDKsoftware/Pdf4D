// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/OpenTypeFont.java, OTFParser.java and CFFTable.java (3.0.8)
unit Pdf4D.FontBox.OpenType;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Common.Log,
  Pdf4D.Common.Path,
  Pdf4D.FontBox.Cff.Font,
  Pdf4D.FontBox.TrueType.DataStream,
  Pdf4D.FontBox.TrueType.Tables,
  Pdf4D.FontBox.TrueType.Font,
  Pdf4D.FontBox.TrueType.Parser;

type
  // The CFF table of an OpenType font. It holds the first font of the CFF font set and owns it.
  TCFFTable = class(TTTFTable)
  public
    const TableTag = 'CFF ';

  private
    FFont: TCFFFont;

  public
    destructor Destroy; override;

    procedure Read(const Host: TTTFTableHost; const Data: TTTFDataStream); override;

    property Font: TCFFFont read FFont;
  end;

  // An OpenType font: a TrueType font with glyf outlines, or with CFF outlines when its version is OTTO. Like every font that
  // comes out of a parser, it has read all its tables and can be shared.
  TOpenTypeFont = class(TTrueTypeFont)
  private
    const Cff2Tag = 'CFF2';
    const LayoutTags: array[0..4] of string = ('BASE', 'GDEF', 'GPOS', 'GSUB', 'JSTF');

  private
    FHasPostScriptTag: Boolean;

  protected
    procedure SetVersion(const Value: Single); override;

  public
    // The CFF font, owned by the table. Raises EPdfUnsupportedFeatureException for a font without CFF outlines.
    function CFF: TCFFFont;
    // The CFF font of a font with CFF outlines, as TryGetGlyphPath finds it; False, and no exception, for a font without
    function TryGetCFF(out Font: TCFFFont): Boolean;
    // The version says OTTO, or the font has a CFF or CFF2 table
    function IsPostScript: Boolean;
    // False for a font with CFF2 outlines and no CFF table
    function IsSupportedOTF: Boolean;
    function HasLayoutTables: Boolean;

    // A font with CFF outlines gives the path of the glyph (the glyph id, as for a name-keyed font) from its CFF table;
    // any other font reads its glyf table
    function TryGetGlyphPath(const GID: Integer; out Path: TPdfPath; const Log: TPdfLog = nil): Boolean; override;
  end;

  // Parses an OpenType font. A font with CFF2 outlines raises EPdfUnsupportedFeatureException, any other broken font
  // EPdfParseException.
  TOTFParser = class(TTTFParser)
  protected
    function NewFont(const Data: TTTFDataStream): TTrueTypeFont; override;
    function CreateTable(const Tag: string; const CheckSum, Offset, Length: Int64): TTTFTable; override;
    function AllowCFF: Boolean; override;
    function IsPostScript(const Font: TTrueTypeFont): Boolean; override;
    function IsSupportedPostScript(const Font: TTrueTypeFont): Boolean; override;
    procedure GuardMandatoryTables(const Font: TTrueTypeFont); override;

  public
    function Parse(const Data: TBytes): TOpenTypeFont; reintroduce; overload;
    function Parse(const Data: TBytes; const DirectoryOffset: Int64): TOpenTypeFont; reintroduce; overload;
  end;

implementation

uses
  System.Generics.Collections,
  Pdf4D.Common.Defines,
  Pdf4D.FontBox.Cff.Parser;

const
  // The version of a font that starts with OTTO, read as a 16.16 fixed number: 20308 + 21583 / 65536
  OpenTypeVersion: Single = 20308 + (21583 / 65536);

{ TCFFTable }

destructor TCFFTable.Destroy;
begin
  FFont.Free;
  inherited;
end;

procedure TCFFTable.Read(const Host: TTTFTableHost; const Data: TTTFDataStream);
begin
  const Bytes = Data.ReadBytes(Integer(Length));
  const Parser = TCFFParser.Create(Host.Log);
  try
    // Only the first font is used, so the others are not read
    const Fonts = Parser.Parse(Bytes, 1);
    try
      if Fonts.Count = 0 then
      begin
        raise EPdfParseException.Create('The CFF table holds no font');
      end;
      // The first font is the one of the OpenType font; Extract keeps the list from freeing it
      FFont := Fonts.Extract(Fonts[0]);
    finally
      Fonts.Free;
    end;
  finally
    Parser.Free;
  end;
  inherited Read(Host, Data);
end;

{ TOpenTypeFont }

procedure TOpenTypeFont.SetVersion(const Value: Single);
begin
  FHasPostScriptTag := (Value = OpenTypeVersion);
  inherited SetVersion(Value);
end;

function TOpenTypeFont.CFF: TCFFFont;
begin
  if not FHasPostScriptTag then
  begin
    raise EPdfUnsupportedFeatureException.Create('TrueType fonts do not have a CFF table');
  end;

  var Table: TTTFTable;
  if not TryGetTable(TCFFTable.TableTag, Table) then
  begin
    raise EPdfUnsupportedFeatureException.Create('The OpenType font has no CFF table');
  end;
  Result := (Table as TCFFTable).Font;
end;

function TOpenTypeFont.TryGetCFF(out Font: TCFFFont): Boolean;
begin
  var Table: TTTFTable;
  Font := nil;
  Result := (IsPostScript and TryGetTable(TCFFTable.TableTag, Table));
  if Result then
  begin
    Font := (Table as TCFFTable).Font;
  end;
end;

function TOpenTypeFont.IsPostScript: Boolean;
begin
  Result := (FHasPostScriptTag or HasTable(TCFFTable.TableTag) or HasTable(Cff2Tag));
end;

function TOpenTypeFont.IsSupportedOTF: Boolean;
begin
  Result := not (FHasPostScriptTag and (not HasTable(TCFFTable.TableTag)) and HasTable(Cff2Tag));
end;

function TOpenTypeFont.HasLayoutTables: Boolean;
begin
  for var Tag in LayoutTags do
  begin
    if HasTable(Tag) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TOpenTypeFont.TryGetGlyphPath(const GID: Integer; out Path: TPdfPath; const Log: TPdfLog): Boolean;
begin
  var Table: TTTFTable;
  const HasCffOutlines = (IsPostScript and TryGetTable(TCFFTable.TableTag, Table));
  if HasCffOutlines then
  begin
    Result := (Table as TCFFTable).Font.TryGetPathByGid(GID, Path, Log);
  end
  else
  begin
    Result := inherited TryGetGlyphPath(GID, Path, Log);
  end;
end;

{ TOTFParser }

function TOTFParser.NewFont(const Data: TTTFDataStream): TTrueTypeFont;
begin
  Result := TOpenTypeFont.Create(Data);
end;

// The layout tables are only kept as bytes, like any other table that is not read
function TOTFParser.CreateTable(const Tag: string; const CheckSum, Offset, Length: Int64): TTTFTable;
begin
  if Tag = TCFFTable.TableTag then
  begin
    Result := TCFFTable.Create(Tag, CheckSum, Offset, Length);
  end
  else
  begin
    Result := inherited CreateTable(Tag, CheckSum, Offset, Length);
  end;
end;

function TOTFParser.AllowCFF: Boolean;
begin
  Result := True;
end;

function TOTFParser.IsPostScript(const Font: TTrueTypeFont): Boolean;
begin
  Result := (Font as TOpenTypeFont).IsPostScript;
end;

function TOTFParser.IsSupportedPostScript(const Font: TTrueTypeFont): Boolean;
begin
  Result := (Font as TOpenTypeFont).IsSupportedOTF;
end;

procedure TOTFParser.GuardMandatoryTables(const Font: TTrueTypeFont);
begin
  if not (Font as TOpenTypeFont).IsSupportedOTF then
  begin
    raise EPdfUnsupportedFeatureException.Create('OpenType fonts using CFF2 outlines are not supported');
  end;
  inherited GuardMandatoryTables(Font);
end;

function TOTFParser.Parse(const Data: TBytes): TOpenTypeFont;
begin
  Result := Parse(Data, 0);
end;

function TOTFParser.Parse(const Data: TBytes; const DirectoryOffset: Int64): TOpenTypeFont;
begin
  Result := inherited Parse(Data, DirectoryOffset) as TOpenTypeFont;
end;

end.
