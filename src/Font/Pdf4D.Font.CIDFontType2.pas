// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/font/PDCIDFontType2.java (3.0.8)
unit Pdf4D.Font.CIDFontType2;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.Matrix,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Font.CIDFont,
  Pdf4D.FontBox.BoundingBox,
  Pdf4D.FontBox.OpenType,
  Pdf4D.FontBox.TrueType.Cmap,
  Pdf4D.FontBox.TrueType.Font;

type
  // A CID-keyed TrueType (or OpenType) font. An embedded font program belongs to this font; a substitute from the font
  // mapper is shared and stays with the mapper, so it is never changed and never gets the log of a document. Without
  // GSUB and the embedder, which this port leaves out.
  TPDCIDFontType2 = class(TPDCIDFont)
  private
    const OpenTypeTag = 'OTTO';
    const MaximumByteValue = 255;
    const MaxNoMappingWarnings = 65536;

  private
    FTtf: TTrueTypeFont;
    FOwnsTtf: Boolean;
    FOtf: TOpenTypeFont;
    FCIDToGID: TBytes;
    FHasCIDToGIDMap: Boolean;
    FIsEmbedded: Boolean;
    FIsDamaged: Boolean;
    FCmap: TCmapSubtable;
    FHasBoundingBox: Boolean;
    FBoundingBox: TBoundingBox;
    FNoMapping: TDictionary<Integer, Boolean>;

    procedure LoadFontProgram;
    function TryGetEmbeddedFontFile(out FontFile: TCosStream): Boolean;
    procedure LoadEmbeddedFont(const FontFile: TCosStream);
    function ParseFontData(const Data: TBytes): TTrueTypeFont;
    procedure FindFontOrSubstitute;
    function GetOpenTypeFont(const Font: TTrueTypeFont): TOpenTypeFont;
    function GenerateBoundingBox: TBoundingBox;
    function CodeToGIDOfEmbeddedFont(const Code: Integer): Integer;
    function CodeToGIDOfSubstitute(const Code: Integer): Integer;
    function TryGetGIDOfUnicode(const Code: Integer; out GID: Integer): Boolean;
    procedure WarnAboutMissingMapping(const Code: Integer);
    function EncodeEmbeddedToCID(const CodePoint: Integer): Integer;
    class function FirstCodePoint(const Text: string): Integer; static;

  public
    // Does not own Dictionary or Parent
    constructor Create(const Dictionary: TCosDictionary; const Parent: TPDCIDFontParent);
    destructor Destroy; override;

    function CodeToCID(const Code: Integer): Integer; override;
    function CodeToGID(const Code: Integer): Integer; override;
    function GetWidthFromFont(const Code: Integer): Single; override;
    function GetFontMatrix: TPdfMatrix; override;
    function GetBoundingBox: TBoundingBox; override;
    function GetHeight(const Code: Integer): Single; override;
    function IsEmbedded: Boolean; override;
    function IsDamaged: Boolean; override;
    // Without the reverse lookup in the /ToUnicode CMap, which PDFBox tries for an embedded font whose CID it cannot find
    // otherwise
    function TryEncode(const CodePoint: Integer; out Bytes: TBytes): Boolean; override;

    // The embedded or substituted font; a substitute is shared
    function GetTrueTypeFont: TTrueTypeFont;
  end;

implementation

uses
  System.Classes,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Names,
  Pdf4D.Font.Descriptor,
  Pdf4D.Font.Mapper,
  Pdf4D.FontBox.CMap,
  Pdf4D.FontBox.TrueType.Parser,
  Pdf4D.Model.Rectangle;

const
  ByteShift = 8;
  CMapIdentityPrefix = 'Identity-';

{ TPDCIDFontType2 }

constructor TPDCIDFontType2.Create(const Dictionary: TCosDictionary; const Parent: TPDCIDFontParent);
begin
  inherited Create(Dictionary, Parent);
  FNoMapping := TDictionary<Integer, Boolean>.Create;
  LoadFontProgram;
  FOtf := GetOpenTypeFont(FTtf);
  if not FTtf.TryGetUnicodeCmapLookup(False, FCmap) then
  begin
    FCmap := nil;
  end;
  FHasCIDToGIDMap := TryReadCIDToGIDMap(FCIDToGID);
end;

destructor TPDCIDFontType2.Destroy;
begin
  // A substitute is shared and belongs to the font mapper
  if FOwnsTtf then
  begin
    FTtf.Free;
  end;
  FNoMapping.Free;
  inherited;
end;

procedure TPDCIDFontType2.LoadFontProgram;
begin
  var FontFile: TCosStream;
  if TryGetEmbeddedFontFile(FontFile) then
  begin
    LoadEmbeddedFont(FontFile);
  end;

  FIsEmbedded := Assigned(FTtf);
  FOwnsTtf := FIsEmbedded;
  if not FIsEmbedded then
  begin
    FindFontOrSubstitute;
  end;
end;

function TPDCIDFontType2.TryGetEmbeddedFontFile(out FontFile: TCosStream): Boolean;
begin
  FontFile := nil;
  var Descriptor: TPDFontDescriptor;
  if not TryGetFontDescriptor(Descriptor) then
  begin
    Exit(False);
  end;

  // Acrobat looks in FontFile too, even though it is not in the spec, see PDFBOX-2599
  Result := (Descriptor.TryGetFontFile2(FontFile) or Descriptor.TryGetFontFile3(FontFile) or Descriptor.TryGetFontFile(FontFile));
end;

procedure TPDCIDFontType2.LoadEmbeddedFont(const FontFile: TCosStream);
begin
  try
    // Embedded OTF or TTF
    FTtf := ParseFontData(ReadStreamBytes(FontFile));
  except
    on Failure: Exception do
    begin
      if not IsRecoverableFailure(Failure) then
      begin
        raise;
      end;
      FIsDamaged := True;
      FTtf := nil;
      LogWarning('Could not read embedded OTF for font %s: %s', [GetBaseFont, Failure.Message]);
      Exit;
    end;
  end;

  if (FTtf is TOpenTypeFont) and (not TOpenTypeFont(FTtf).IsSupportedOTF) then
  begin
    // The OpenType font contains CFF2 outlines, which are not supported yet
    FreeAndNil(FTtf);
    FIsDamaged := True;
    LogWarning('Found an OpenType font using CFF2 outlines which are not supported %s', [GetBaseFont]);
  end;
end;

function TPDCIDFontType2.ParseFontData(const Data: TBytes): TTrueTypeFont;
begin
  // The OpenType parser is chosen by the tag, as PDFBox does
  const IsOpenType = ((Length(Data) >= Length(OpenTypeTag)) and (TEncoding.ASCII.GetString(Data, 0, Length(OpenTypeTag)) = OpenTypeTag));
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

procedure TPDCIDFontType2.FindFontOrSubstitute;
begin
  var Descriptor: TPDFontDescriptor;
  if not TryGetFontDescriptor(Descriptor) then
  begin
    Descriptor := nil;
  end;
  var Info: TPDCIDSystemInfo;
  const HasInfo = TryGetCIDSystemInfo(Info);

  const Mapping = TPdfFontMappers.Instance.GetCIDFont(GetBaseFont, Descriptor, HasInfo, Info);
  if Mapping.IsCIDFont then
  begin
    if not (Mapping.Font is TTrueTypeFont) then
    begin
      raise EPdfUnsupportedFeatureException.CreateFmt('The substitute for the CID-keyed font %s is not an OpenType font with TrueType tables', [GetBaseFont]);
    end;
    FTtf := TTrueTypeFont(Mapping.Font);
  end
  else
  begin
    FTtf := Mapping.TrueTypeFont;
  end;

  if not Assigned(FTtf) then
  begin
    // Shouldn't happen
    raise EPdfParseException.Create('mapping.getTrueTypeFont() returns null, please report');
  end;
  if Mapping.IsFallback then
  begin
    LogWarning('Using fallback font %s for CID-keyed TrueType font %s', [FTtf.Name, GetBaseFont]);
  end;
end;

function TPDCIDFontType2.GetOpenTypeFont(const Font: TTrueTypeFont): TOpenTypeFont;
begin
  Result := nil;
  if (Font is TOpenTypeFont) and TOpenTypeFont(Font).IsSupportedOTF then
  begin
    Result := TOpenTypeFont(Font);
  end;
end;

function TPDCIDFontType2.GetFontMatrix: TPdfMatrix;
begin
  // 1000 upem, this is not strictly true
  Result := TPdfMatrix.Create(0.001, 0, 0, 0.001, 0, 0);
end;

function TPDCIDFontType2.GenerateBoundingBox: TBoundingBox;
begin
  var Descriptor: TPDFontDescriptor;
  var Box: TPdfRectangle;
  if TryGetFontDescriptor(Descriptor) and Descriptor.TryGetFontBoundingBox(Box) then
  begin
    const IsNonZero = ((Box.LowerLeftX <> 0) or (Box.LowerLeftY <> 0) or (Box.UpperRightX <> 0) or (Box.UpperRightY <> 0));
    if IsNonZero then
    begin
      Exit(TBoundingBox.Create(Box.LowerLeftX, Box.LowerLeftY, Box.UpperRightX, Box.UpperRightY));
    end;
  end;
  Result := FTtf.FontBBox;
end;

function TPDCIDFontType2.GetBoundingBox: TBoundingBox;
begin
  if not FHasBoundingBox then
  begin
    FBoundingBox := GenerateBoundingBox;
    FHasBoundingBox := True;
  end;
  Result := FBoundingBox;
end;

class function TPDCIDFontType2.FirstCodePoint(const Text: string): Integer;
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

function TPDCIDFontType2.CodeToCID(const Code: Integer): Integer;
begin
  var CMap: TCMap;
  if not Parent.TryGetCMap(CMap) then
  begin
    // PDFBox fails with a NullPointerException; reading a code fails already
    Exit(0);
  end;

  // Acrobat allows bad PDFs to use Unicode CMaps here instead of CID CMaps, see PDFBOX-1283
  var Unicode: string;
  if (not CMap.HasCIDMappings) and CMap.HasUnicodeMappings and CMap.TryToUnicode(Code, Unicode) and (Unicode <> '') then
  begin
    // Actually: code -> CID
    Exit(FirstCodePoint(Unicode));
  end;
  Result := CMap.ToCID(Code);
end;

function TPDCIDFontType2.TryGetGIDOfUnicode(const Code: Integer; out GID: Integer): Boolean;
begin
  GID := 0;
  var Unicode: string;
  if not Parent.TryToUnicode(Code, Unicode) then
  begin
    Exit(False);
  end;
  if Length(Unicode) > 1 then
  begin
    LogWarning('Trying to map multi-byte character using ''cmap'', result will be poor', []);
  end;

  // A non-embedded font always has a cmap (otherwise the font mapper does not load it)
  if Assigned(FCmap) and (Unicode <> '') then
  begin
    GID := FCmap.GetGlyphId(FirstCodePoint(Unicode));
  end;
  Result := True;
end;

procedure TPDCIDFontType2.WarnAboutMissingMapping(const Code: Integer);
begin
  // We keep track of which warnings have been issued, so we don't log multiple times
  if (FNoMapping.Count < MaxNoMappingWarnings) and FNoMapping.TryAdd(Code, True) then
  begin
    LogWarning('Failed to find a character mapping for %d in %s', [Code, GetBaseFont]);
  end;
end;

function TPDCIDFontType2.CodeToGIDOfSubstitute(const Code: Integer): Integer;
begin
  // The conforming reader shall select glyphs by translating characters from the encoding specified by the predefined CMap
  // to one of the encodings in the TrueType font's 'cmap' table. The means by which this is accomplished are
  // implementation-dependent. The CIDToGIDMap is left out when the embedded font is replaced by an external font.
  const IsSameFont = (FHasCIDToGIDMap and (not FIsDamaged) and (GetBaseFont = FTtf.Name));
  if IsSameFont then
  begin
    // Acrobat allows non-embedded GIDs. PDFBOX-5612: should happen only if it's really the same font
    LogWarning('Using non-embedded GIDs in font %s', [GetBaseFont]);
    Exit(MapCIDToGID(FCIDToGID, CodeToCID(Code)));
  end;

  // Fall back to the ToUnicode CMap, test with PDFBOX-1422 and PDFBOX-2560
  if not TryGetGIDOfUnicode(Code, Result) then
  begin
    WarnAboutMissingMapping(Code);
    // Acrobat is willing to use the CID as a GID, even when the font isn't embedded, see PDFBOX-2599
    Result := CodeToCID(Code);
  end;
end;

function TPDCIDFontType2.CodeToGIDOfEmbeddedFont(const Code: Integer): Integer;
begin
  // If the TrueType font program is embedded, the Type 2 CIDFont dictionary shall contain a CIDToGIDMap entry that maps
  // CIDs to the glyph indices for the appropriate glyph descriptions in that font program.
  const CID = CodeToCID(Code);
  if FHasCIDToGIDMap then
  begin
    Exit(MapCIDToGID(FCIDToGID, CID));
  end;

  // "Identity" is the default for CFF-based OpenTypeFonts
  if Assigned(FOtf) and FOtf.IsPostScript then
  begin
    Exit(CID);
  end;
  // "Identity" is the default for TrueTypeFonts if the CID is within the range
  Result := 0;
  if (CID >= 0) and (CID < FTtf.NumberOfGlyphs) then
  begin
    Result := CID;
  end;
end;

function TPDCIDFontType2.CodeToGID(const Code: Integer): Integer;
begin
  if FIsEmbedded then
  begin
    Result := CodeToGIDOfEmbeddedFont(Code);
  end
  else
  begin
    Result := CodeToGIDOfSubstitute(Code);
  end;
end;

function TPDCIDFontType2.GetHeight(const Code: Integer): Single;
begin
  // Really we want the BBox (for text extraction); shouldn't this be the yMax/yMin?
  const Header = FTtf.HorizontalHeader;
  Result := Single(Header.Ascender + (-Header.Descender)) / Single(FTtf.UnitsPerEm);
end;

function TPDCIDFontType2.GetWidthFromFont(const Code: Integer): Single;
begin
  const GID = CodeToGID(Code);
  Result := FTtf.GetAdvanceWidth(GID);
  const UnitsPerEm = Single(FTtf.UnitsPerEm);
  if UnitsPerEm <> 1000 then
  begin
    Result := Result * (Single(1000) / UnitsPerEm);
  end;
end;

function TPDCIDFontType2.EncodeEmbeddedToCID(const CodePoint: Integer): Integer;
begin
  // Embedded fonts always use CIDToGIDMap, with Identity as the default
  Result := -1;
  var CMap: TCMap;
  var UCS2: TCMap;
  if Parent.TryGetCMap(CMap) and CMap.Name.StartsWith(CMapIdentityPrefix) then
  begin
    if Assigned(FCmap) then
    begin
      Result := FCmap.GetGlyphId(CodePoint);
    end;
  end
  else if Parent.TryGetCMapUCS2(UCS2) then
  begin
    // If the CMap is predefined then there will be a UCS-2 CMap
    Result := UCS2.ToCID(CodePoint);
  end;

  // Otherwise PDFBox requires an explicit ToUnicode CMap, which is not used here
  if Result = -1 then
  begin
    Result := 0;
  end;
end;

function TPDCIDFontType2.TryEncode(const CodePoint: Integer; out Bytes: TBytes): Boolean;
begin
  Bytes := nil;
  var CID: Integer;
  if FIsEmbedded then
  begin
    CID := EncodeEmbeddedToCID(CodePoint);
  end
  else if Assigned(FCmap) then
  begin
    // A non-embedded font always has a cmap
    CID := FCmap.GetGlyphId(CodePoint);
  end
  else
  begin
    Exit(False);
  end;

  // No glyph for this code point; the CID is always two bytes (16 bits) for TrueType
  if CID = 0 then
  begin
    Exit(False);
  end;
  Bytes := [Byte((CID shr ByteShift) and MaximumByteValue), Byte(CID and MaximumByteValue)];
  Result := True;
end;

function TPDCIDFontType2.IsEmbedded: Boolean;
begin
  Result := FIsEmbedded;
end;

function TPDCIDFontType2.IsDamaged: Boolean;
begin
  Result := FIsDamaged;
end;

function TPDCIDFontType2.GetTrueTypeFont: TTrueTypeFont;
begin
  Result := FTtf;
end;

end.
