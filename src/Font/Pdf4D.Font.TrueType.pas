// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/font/PDTrueTypeFont.java (3.0.8)
unit Pdf4D.Font.TrueType;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.SharedInstance,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Font.Encoding,
  Pdf4D.Font.Simple,
  Pdf4D.FontBox.BoundingBox,
  Pdf4D.FontBox.FontBoxFont,
  Pdf4D.FontBox.TrueType.Cmap,
  Pdf4D.FontBox.TrueType.Font,
  Pdf4D.Model.DocumentContext;

type
  // A TrueType font with an embedded /FontFile2, or a substitute from the font mapper. The embedded font belongs to this font;
  // a substitute is shared and stays with the mapper, so it is never changed and never gets the log of a document.
  TPDTrueTypeFont = class(TPDSimpleFont)
  private
    const StartRangeF000 = $F000;
    const StartRangeF100 = $F100;
    const StartRangeF200 = $F200;
    const MaximumByteCode = 255;
    const OpenTypeTag = 'OTTO';

  private
    class var FInvertedMacOSRoman: TPdfSharedInstance<TDictionary<string, Integer>>;

  private
    FTtf: TTrueTypeFont;
    FOwnsTtf: Boolean;
    FIsEmbedded: Boolean;
    FIsDamaged: Boolean;
    FCmapWinUnicode: TCmapSubtable;
    FCmapWinSymbol: TCmapSubtable;
    FCmapMacRoman: TCmapSubtable;
    FCmapInitialized: Boolean;
    FGidToCode: TDictionary<Integer, Integer>;
    FHasBoundingBox: Boolean;
    FBoundingBox: TBoundingBox;

    procedure LoadEmbeddedFont;
    procedure LoadFontFile(const FontFile: TCosStream);
    function ParseFontData(const Data: TBytes): TTrueTypeFont;
    procedure LoadMappedFont;

    procedure ExtractCmapTable;
    procedure ExtractSubtable(const Subtable: TCmapSubtable);
    function UnicodeToGID(const GlyphName: string; out GID: Integer): Boolean;
    function NonSymbolicCodeToGID(const Code: Integer): Integer;
    function SymbolicCodeToGID(const Code: Integer): Integer;
    function SymbolicGIDFromWinUnicode(const Code: Integer; out IsNotDef: Boolean): Integer;
    function SymbolicGIDFromWinSymbol(const Code: Integer): Integer;
    function EncodingIsWinAnsiOrMacRoman: Boolean;
    class function FirstCodePoint(const Text: string): Integer; static;
    class function MacCodeOfName(const GlyphName: string; out MacCode: Integer): Boolean; static;
    class function InvertedMacOSRoman: TDictionary<string, Integer>; static;
    class function BuildInvertedMacOSRoman: TDictionary<string, Integer>; static;
    class destructor Destroy;

    function SynthesizeEncoding: TPdfEncoding;
    function PostNameOrGID(const GID: Integer): string;
    function GetGIDToCode: TDictionary<Integer, Integer>;
    function GenerateBoundingBox: TBoundingBox;
    function EncodeWithEncoding(const Encoding: TPdfEncoding; const CodePoint: Integer; out Bytes: TBytes): Boolean;
    function EncodeWithBuiltInEncoding(const CodePoint: Integer; out Bytes: TBytes): Boolean;

  protected
    function ReadEncodingFromFont: TPdfEncoding; override;
    function TryEncode(const CodePoint: Integer; out Bytes: TBytes): Boolean; override;

  public
    // Does not own Dictionary or Context
    constructor Create(const Dictionary: TCosDictionary; const Context: TPDDocumentContext);
    destructor Destroy; override;

    // The glyph for a character code, by the rules of PDFBox: 0 when the font has no glyph for it
    function CodeToGID(const Code: Integer): Integer;
    function GetWidthFromFont(const Code: Integer): Single; override;
    function GetBoundingBox: TBoundingBox; override;
    function IsEmbedded: Boolean; override;
    function IsDamaged: Boolean; override;
    // The embedded or substituted font; the font of the mapper is shared
    function GetTrueTypeFont: TTrueTypeFont;
    function GetFontBoxFont: TFontBoxFont; override;
    function HasGlyph(const GlyphName: string): Boolean; overload;
    function HasGlyph(const Code: Integer): Boolean; overload;
  end;

implementation

uses
  System.Classes,
  Pdf4D.Common.Defines,
  Pdf4D.Font.Descriptor,
  Pdf4D.Font.Encoding.Tables,
  Pdf4D.Font.GlyphList,
  Pdf4D.Font.Mapper,
  Pdf4D.Font.Standard14,
  Pdf4D.FontBox.Afm,
  Pdf4D.FontBox.OpenType,
  Pdf4D.FontBox.TrueType.Parser,
  Pdf4D.FontBox.TrueType.Post,
  Pdf4D.Model.Rectangle;

const
  NotDefName = '.notdef';
  FirstUnusedCode = 257;

{ TPDTrueTypeFont }

class destructor TPDTrueTypeFont.Destroy;
begin
  FInvertedMacOSRoman.Release;
end;

constructor TPDTrueTypeFont.Create(const Dictionary: TCosDictionary; const Context: TPDDocumentContext);
begin
  inherited Create(Dictionary, Context);
  FGidToCode := TDictionary<Integer, Integer>.Create;
  LoadEmbeddedFont;
  FIsEmbedded := Assigned(FTtf);
  FOwnsTtf := FIsEmbedded;
  if not FIsEmbedded then
  begin
    LoadMappedFont;
  end;
  ReadEncoding;
end;

destructor TPDTrueTypeFont.Destroy;
begin
  // A substitute is shared and belongs to the font mapper
  if FOwnsTtf then
  begin
    FTtf.Free;
  end;
  FGidToCode.Free;
  inherited;
end;

procedure TPDTrueTypeFont.LoadEmbeddedFont;
begin
  var Descriptor: TPDFontDescriptor;
  var FontFile: TCosStream;
  if TryGetFontDescriptor(Descriptor) and Descriptor.TryGetFontFile2(FontFile) then
  begin
    LoadFontFile(FontFile);
  end;
end;

procedure TPDTrueTypeFont.LoadFontFile(const FontFile: TCosStream);
begin
  try
    FTtf := ParseFontData(ReadStreamBytes(FontFile));
  except
    on Failure: Exception do
    begin
      if not IsRecoverableFailure(Failure) then
      begin
        raise;
      end;
      LogWarning('Could not read embedded TTF for font %s: %s', [Name, Failure.Message]);
      FTtf := nil;
      FIsDamaged := True;
    end;
  end;
end;

function TPDTrueTypeFont.ParseFontData(const Data: TBytes): TTrueTypeFont;
begin
  // The OpenType parser is chosen by the tag, as PDFBox does
  const IsOpenType = ((Length(Data) >= 4) and (TEncoding.ASCII.GetString(Data, 0, 4) = OpenTypeTag));
  if IsOpenType then
  begin
    const OpenTypeParser = TOTFParser.Create(True, DocumentLog);
    try
      Result := OpenTypeParser.Parse(Data);
    finally
      OpenTypeParser.Free;
    end;
  end
  else
  begin
    const TrueTypeParser = TTTFParser.Create(True, DocumentLog);
    try
      Result := TrueTypeParser.Parse(Data);
    finally
      TrueTypeParser.Free;
    end;
  end;
end;

procedure TPDTrueTypeFont.LoadMappedFont;
begin
  var Descriptor: TPDFontDescriptor;
  if not TryGetFontDescriptor(Descriptor) then
  begin
    Descriptor := nil;
  end;

  const Mapping = TPdfFontMappers.Instance.GetTrueTypeFont(Name, Descriptor);
  FTtf := Mapping.Font;
  const Log = DocumentLog;
  if Mapping.IsFallback and Assigned(Log) then
  begin
    Log.Debug('Using fallback font %s for %s', [FTtf.Name, Name]);
  end;
end;

procedure TPDTrueTypeFont.ExtractCmapTable;
begin
  if FCmapInitialized then
  begin
    Exit;
  end;

  var Cmap: TCmapTable;
  if FTtf.TryGetCmap(Cmap) then
  begin
    // Every relevant subtable is looked at; a later one of the same kind wins, as in PDFBox
    for var Subtable in Cmap.Subtables do
    begin
      ExtractSubtable(Subtable);
    end;
  end;
  FCmapInitialized := True;
end;

procedure TPDTrueTypeFont.ExtractSubtable(const Subtable: TCmapSubtable);
begin
  const PlatformId = Subtable.PlatformId;
  const EncodingId = Subtable.PlatformEncodingId;
  if PlatformId = TCmapTable.PlatformWindows then
  begin
    if EncodingId = TCmapTable.EncodingWinUnicodeBmp then
    begin
      FCmapWinUnicode := Subtable;
    end
    else if EncodingId = TCmapTable.EncodingWinSymbol then
    begin
      FCmapWinSymbol := Subtable;
    end;
  end
  else if (PlatformId = TCmapTable.PlatformMacintosh) and (EncodingId = TCmapTable.EncodingMacRoman) then
  begin
    FCmapMacRoman := Subtable;
  end
  else if (PlatformId = TCmapTable.PlatformUnicode) and (EncodingId = TCmapTable.EncodingUnicode10) then
  begin
    // PDFBOX-4755 / PDF.js #5501
    FCmapWinUnicode := Subtable;
  end
  else if (PlatformId = TCmapTable.PlatformUnicode) and (EncodingId = TCmapTable.EncodingUnicode20Bmp) then
  begin
    // PDFBOX-5484
    FCmapWinUnicode := Subtable;
  end;
end;

class function TPDTrueTypeFont.FirstCodePoint(const Text: string): Integer;
begin
  Result := Ord(Text[1]);
  if (Length(Text) > 1) and (Result >= $D800) and (Result <= $DBFF) then
  begin
    const Low = Ord(Text[2]);
    if (Low >= $DC00) and (Low <= $DFFF) then
    begin
      Result := $10000 + ((Result - $D800) shl 10) + (Low - $DC00);
    end;
  end;
end;

class function TPDTrueTypeFont.BuildInvertedMacOSRoman: TDictionary<string, Integer>;
begin
  // putIfAbsent over the codes in ascending order: the lowest code of a name wins
  Result := TDictionary<string, Integer>.Create;
  try
    const CodeToName = TMacOSRomanEncoding.Instance.CodeToNameMap;
    for var Code := 0 to MaximumByteCode do
    begin
      var GlyphName: string;
      if CodeToName.TryGetValue(Code, GlyphName) then
      begin
        Result.TryAdd(GlyphName, Code);
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

class function TPDTrueTypeFont.InvertedMacOSRoman: TDictionary<string, Integer>;
begin
  // The table is filled once and never changed after it is published
  Result := FInvertedMacOSRoman.Get(BuildInvertedMacOSRoman);
end;

class function TPDTrueTypeFont.MacCodeOfName(const GlyphName: string; out MacCode: Integer): Boolean;
begin
  Result := InvertedMacOSRoman.TryGetValue(GlyphName, MacCode);
end;

function TPDTrueTypeFont.UnicodeToGID(const GlyphName: string; out GID: Integer): Boolean;
begin
  GID := 0;
  var Unicode: string;
  Result := (TGlyphList.AdobeGlyphList.TryToUnicode(GlyphName, Unicode) and (Unicode <> ''));
  if Result then
  begin
    GID := FCmapWinUnicode.GetGlyphId(FirstCodePoint(Unicode));
  end;
end;

function TPDTrueTypeFont.EncodingIsWinAnsiOrMacRoman: Boolean;
begin
  var Encoding: TPdfEncoding;
  Result := (TryGetEncoding(Encoding) and ((Encoding is TWinAnsiEncoding) or (Encoding is TMacRomanEncoding)));
end;

function TPDTrueTypeFont.NonSymbolicCodeToGID(const Code: Integer): Integer;
begin
  Result := 0;
  var Encoding: TPdfEncoding;
  if not TryGetEncoding(Encoding) then
  begin
    Exit;
  end;

  const GlyphName = Encoding.GetName(Code);
  if GlyphName = NotDefName then
  begin
    Exit;
  end;

  // (3, 1) - (Windows, Unicode)
  if Assigned(FCmapWinUnicode) then
  begin
    UnicodeToGID(GlyphName, Result);
  end;

  // (1, 0) - (Macintosh, Roman)
  var MacCode: Integer;
  if (Result = 0) and Assigned(FCmapMacRoman) and MacCodeOfName(GlyphName, MacCode) then
  begin
    Result := FCmapMacRoman.GetGlyphId(MacCode);
  end;

  // 'post' table
  if Result = 0 then
  begin
    Result := FTtf.NameToGID(GlyphName);
  end;
end;

function TPDTrueTypeFont.SymbolicGIDFromWinUnicode(const Code: Integer; out IsNotDef: Boolean): Integer;
begin
  IsNotDef := False;
  Result := 0;
  if not EncodingIsWinAnsiOrMacRoman then
  begin
    Exit(FCmapWinUnicode.GetGlyphId(Code));
  end;

  var Encoding: TPdfEncoding;
  TryGetEncoding(Encoding);
  const GlyphName = Encoding.GetName(Code);
  if GlyphName = NotDefName then
  begin
    IsNotDef := True;
    Exit;
  end;
  UnicodeToGID(GlyphName, Result);
end;

function TPDTrueTypeFont.SymbolicGIDFromWinSymbol(const Code: Integer): Integer;
begin
  Result := FCmapWinSymbol.GetGlyphId(Code);
  if (Code < 0) or (Code > MaximumByteCode) then
  begin
    Exit;
  end;

  // The cmap may use one of the code ranges F000, F100 or F200, so the high byte has to be added to get the mapped value
  if Result = 0 then
  begin
    Result := FCmapWinSymbol.GetGlyphId(Code + StartRangeF000);
  end;
  if Result = 0 then
  begin
    Result := FCmapWinSymbol.GetGlyphId(Code + StartRangeF100);
  end;
  if Result = 0 then
  begin
    Result := FCmapWinSymbol.GetGlyphId(Code + StartRangeF200);
  end;
end;

function TPDTrueTypeFont.SymbolicCodeToGID(const Code: Integer): Integer;
begin
  Result := 0;
  // PDFBOX-4755 / PDF.js #5501, PDFBOX-3965: a font that has the symbolic flag but is not
  if Assigned(FCmapWinUnicode) then
  begin
    var IsNotDef: Boolean;
    Result := SymbolicGIDFromWinUnicode(Code, IsNotDef);
    if IsNotDef then
    begin
      Exit(0);
    end;
  end;

  // (3, 0) - (Windows, Symbol)
  if (Result = 0) and Assigned(FCmapWinSymbol) then
  begin
    Result := SymbolicGIDFromWinSymbol(Code);
  end;

  // (1, 0) - (Mac, Roman)
  if (Result = 0) and Assigned(FCmapMacRoman) then
  begin
    Result := FCmapMacRoman.GetGlyphId(Code);
  end;
end;

function TPDTrueTypeFont.CodeToGID(const Code: Integer): Integer;
begin
  ExtractCmapTable;
  if IsSymbolic then
  begin
    Result := SymbolicCodeToGID(Code);
  end
  else
  begin
    Result := NonSymbolicCodeToGID(Code);
  end;
end;

function TPDTrueTypeFont.PostNameOrGID(const GID: Integer): string;
begin
  var Post: TPostScriptTable;
  if (not FTtf.TryGetPostScript(Post)) or (not Post.TryGetName(GID, Result)) then
  begin
    // GID pseudo-name
    Result := IntToStr(GID);
  end;
end;

function TPDTrueTypeFont.SynthesizeEncoding: TPdfEncoding;
begin
  // Synthesize an encoding, so that the encoding is always usable
  const CodeToName = TDictionary<Integer, string>.Create;
  try
    for var Code := 0 to FirstUnusedCode - 1 do
    begin
      const GID = CodeToGID(Code);
      if GID > 0 then
      begin
        CodeToName.AddOrSetValue(Code, PostNameOrGID(GID));
      end;
    end;
    Result := AdoptEncoding(TBuiltInEncoding.Create(CodeToName));
  finally
    CodeToName.Free;
  end;
end;

function TPDTrueTypeFont.ReadEncodingFromFont: TPdfEncoding;
begin
  var Metrics: TFontMetrics;
  if (not IsEmbedded) and TryGetStandardAFM(Metrics) then
  begin
    // Read from AFM
    Exit(AdoptEncoding(TType1Encoding.FromMetrics(Metrics)));
  end;

  // Non-symbolic fonts don't have a built-in encoding per se, but their encoding is assumed to be StandardEncoding by the PDF
  // spec unless an explicit Encoding is present which will override this anyway
  var Symbolic: Boolean;
  if TryGetSymbolicFlag(Symbolic) and (not Symbolic) then
  begin
    Exit(TStandardEncoding.Instance);
  end;

  // Normalise the standard 14 name, for instance Symbol,Italic gives Symbol. A font that is standard 14 is Standard Encoding,
  // except Symbol and ZapfDingbats.
  var StandardName: TStandard14FontName;
  const IsSymbolFont = (TStandard14Fonts.TryGetMappedFontName(Name, StandardName) and
                        ((StandardName = TStandard14FontName.Symbol) or (StandardName = TStandard14FontName.ZapfDingbats)));
  if IsStandard14 and (not IsSymbolFont) then
  begin
    Exit(TStandardEncoding.Instance);
  end;

  Result := SynthesizeEncoding;
end;

function TPDTrueTypeFont.GetWidthFromFont(const Code: Integer): Single;
begin
  const GID = CodeToGID(Code);
  Result := FTtf.GetAdvanceWidth(GID);
  const UnitsPerEm = Single(FTtf.UnitsPerEm);
  // A font without units per em counts as 1000, like the bounding box of FontBox does
  if (UnitsPerEm <> 1000) and (UnitsPerEm <> 0) then
  begin
    Result := Result * (Single(1000) / UnitsPerEm);
  end;
end;

function TPDTrueTypeFont.GenerateBoundingBox: TBoundingBox;
begin
  var Descriptor: TPDFontDescriptor;
  var Box: TPdfRectangle;
  if TryGetFontDescriptor(Descriptor) and Descriptor.TryGetFontBoundingBox(Box) then
  begin
    Exit(TBoundingBox.Create(Box.LowerLeftX, Box.LowerLeftY, Box.UpperRightX, Box.UpperRightY));
  end;
  Result := FTtf.FontBBox;
end;

function TPDTrueTypeFont.GetBoundingBox: TBoundingBox;
begin
  if not FHasBoundingBox then
  begin
    FBoundingBox := GenerateBoundingBox;
    FHasBoundingBox := True;
  end;
  Result := FBoundingBox;
end;

function TPDTrueTypeFont.IsEmbedded: Boolean;
begin
  Result := FIsEmbedded;
end;

function TPDTrueTypeFont.IsDamaged: Boolean;
begin
  Result := FIsDamaged;
end;

function TPDTrueTypeFont.GetTrueTypeFont: TTrueTypeFont;
begin
  Result := FTtf;
end;

function TPDTrueTypeFont.GetFontBoxFont: TFontBoxFont;
begin
  Result := FTtf;
end;

function TPDTrueTypeFont.HasGlyph(const GlyphName: string): Boolean;
begin
  const GID = FTtf.NameToGID(GlyphName);
  Result := not ((GID = 0) or (GID >= FTtf.MaximumProfile.NumGlyphs));
end;

function TPDTrueTypeFont.HasGlyph(const Code: Integer): Boolean;
begin
  Result := (CodeToGID(Code) <> 0);
end;

function TPDTrueTypeFont.GetGIDToCode: TDictionary<Integer, Integer>;
begin
  // Inverts the code to GID mapping. A duplicate GID keeps the lowest code.
  if FGidToCode.Count = 0 then
  begin
    for var Code := 0 to MaximumByteCode do
    begin
      FGidToCode.TryAdd(CodeToGID(Code), Code);
    end;
  end;
  Result := FGidToCode;
end;

function TPDTrueTypeFont.EncodeWithEncoding(const Encoding: TPdfEncoding; const CodePoint: Integer; out Bytes: TBytes): Boolean;
begin
  Bytes := nil;
  const GlyphName = GlyphList.CodePointToName(CodePoint);
  if not Encoding.Contains(GlyphName) then
  begin
    Exit(False);
  end;

  if (not FTtf.HasGlyph(GlyphName)) and (not FTtf.HasGlyph(GetUniNameOfCodePoint(CodePoint))) then
  begin
    Exit(False);
  end;

  var Code: Integer;
  if (not Encoding.NameToCodeMap.TryGetValue(GlyphName, Code)) or (Code < 0) or (Code > MaximumByteCode) then
  begin
    Exit(False);
  end;
  Bytes := [Byte(Code)];
  Result := True;
end;

function TPDTrueTypeFont.EncodeWithBuiltInEncoding(const CodePoint: Integer; out Bytes: TBytes): Boolean;
begin
  // Use the built-in encoding of the TTF font
  Bytes := nil;
  const GlyphName = GlyphList.CodePointToName(CodePoint);
  if not FTtf.HasGlyph(GlyphName) then
  begin
    Exit(False);
  end;

  var Code: Integer;
  if not GetGIDToCode.TryGetValue(FTtf.NameToGID(GlyphName), Code) then
  begin
    Exit(False);
  end;
  Bytes := [Byte(Code)];
  Result := True;
end;

function TPDTrueTypeFont.TryEncode(const CodePoint: Integer; out Bytes: TBytes): Boolean;
begin
  var Encoding: TPdfEncoding;
  if TryGetEncoding(Encoding) then
  begin
    Result := EncodeWithEncoding(Encoding, CodePoint, Bytes);
  end
  else
  begin
    Result := EncodeWithBuiltInEncoding(CodePoint, Bytes);
  end;
end;

end.
