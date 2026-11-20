// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/font/PDType0Font.java (3.0.8)
unit Pdf4D.Font.Type0;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.Matrix,
  Pdf4D.Common.Path,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Font.CIDFont,
  Pdf4D.Font.Descriptor,
  Pdf4D.Font.GlyphList,
  Pdf4D.FontBox.BoundingBox,
  Pdf4D.FontBox.CMap,
  Pdf4D.FontBox.TrueType.Font,
  Pdf4D.Model.DocumentContext;

type
  // A composite (Type 0) font: codes are read with the CMap of /Encoding and turned into CIDs, and the descendant CID font
  // has the widths and the glyphs. The font owns its descendant and an /Encoding CMap that is a stream; a predefined CMap
  // is shared. Without the part of PDType0Font that embeds fonts (loading, subsetting, GSUB).
  TPDType0Font = class(TPDCIDFontParent)
  private
    const MaxNoUnicodeWarnings = 65536;
    const NegativeThousandth: Single = -0.001;
    const Thousand: Single = 1000;
    const MinimumDescendantCount = 1;
    const AdobeRegistry = 'Adobe';
    const WModeVertical = 1;

  private
    FDescendantFont: TPDCIDFont;
    FNoUnicode: TDictionary<Integer, Boolean>;
    FCMap: TCMap;
    FOwnsCMap: Boolean;
    FCMapUCS2: TCMap;
    FIsCMapPredefined: Boolean;
    FIsDescendantCJK: Boolean;

    procedure CreateDescendantFont;
    function GetDescendantDictionary: TCosDictionary;
    procedure ReadEncoding;
    procedure ReadEncodingName(const EncodingName: string);
    procedure ReadEncodingStream(const Encoding: TCosBase);
    function TryChargeBudget(const CMap: TCMap): Boolean;
    procedure DetectCJKDescendant;
    procedure FetchCMapUCS2;
    function TryGetEncodingName(out EncodingName: string): Boolean;
    function TryGetUCS2SourceName(const EncodingName: string; const HasEncodingName: Boolean; out SourceName: string): Boolean;
    procedure LoadUCS2CMap(const SourceName: string);
    function TryToUnicodeOfUCS2(const Code: Integer; out Value: string): Boolean;
    function TryToUnicodeOfFontCmap(const Code: Integer; out Value: string): Boolean;
    function TryToUnicodeOfTrueType(const Ttf: TTrueTypeFont; const Code: Integer; out Value: string): Boolean;
    procedure WarnAboutMissingUnicode(const Code: Integer);

  protected
    function IsType0Font: Boolean; override;
    function TryEncode(const CodePoint: Integer; out Bytes: TBytes): Boolean; override;

  public
    // Does not own Dictionary or Context. Raises EPdfParseException when the descendant font is missing or invalid, like
    // the IOException of PDFBox.
    constructor Create(const Dictionary: TCosDictionary; const Context: TPDDocumentContext);
    destructor Destroy; override;

    // The code at Position by the codespace of the CMap. Raises EPdfParseException when the font has no CMap.
    function ReadCode(const Data: TBytes; var Position: Integer): Integer; override;

    // The /ToUnicode CMap; then the identity for a ToUnicode CMap that has no mapping (but not with a predefined CMap);
    // then the UCS2 CMap of a predefined CMap or CJK collection; then the cmap of a TrueType descendant. False when
    // there is none, so the text engine skips the code.
    function TryToUnicode(const Code: Integer; out Value: string): Boolean; overload; override;
    function TryToUnicode(const Code: Integer; const CustomGlyphList: TGlyphList; out Value: string): Boolean; overload; override;

    function TryGetCMap(out CMap: TCMap): Boolean; override;
    function TryGetCMapUCS2(out CMap: TCMap): Boolean; override;
    function TryGetFontDescriptor(out Descriptor: TPDFontDescriptor): Boolean; override;

    function IsVertical: Boolean; override;
    function IsStandard14: Boolean; override;
    function IsEmbedded: Boolean; override;
    function IsDamaged: Boolean; override;

    function GetWidth(const Code: Integer): Single; override;
    function GetWidthFromFont(const Code: Integer): Single; override;
    function HasExplicitWidth(const Code: Integer): Boolean; override;
    function GetAverageFontWidth: Single; override;
    function GetHeight(const Code: Integer): Single;
    function GetDisplacement(const Code: Integer): TPdfVector; override;
    function GetPositionVector(const Code: Integer): TPdfVector; override;
    function GetFontMatrix: TPdfMatrix; override;
    function GetBoundingBox: TBoundingBox; override;

    // PDType0Font.getPath, getNormalizedPath and hasGlyph: the descendant font answers
    function TryGetPath(const Code: Integer; out Path: TPdfPath): Boolean; override;
    function TryGetNormalizedPath(const Code: Integer; out Path: TPdfPath): Boolean; override;
    function HasGlyph(const Code: Integer): Boolean; override;

    // The CID of the code, 0 when the CMap has no mapping
    function CodeToCID(const Code: Integer): Integer;
    // The glyph of the code in the font program of the descendant, by the rules of PDFBox
    function CodeToGID(const Code: Integer): Integer;

    property DescendantFont: TPDCIDFont read FDescendantFont;
  end;

implementation

uses
  System.Classes,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Font.CIDFontType2,
  Pdf4D.Font.CMapManager,
  Pdf4D.Font.Factory,
  Pdf4D.FontBox.TrueType.Cmap;

const
  CJKOrderings: array[0..3] of string = ('GB1', 'CNS1', 'Japan1', 'Korea1');
  UCS2Suffix = 'UCS2';

{ TPDType0Font }

constructor TPDType0Font.Create(const Dictionary: TCosDictionary; const Context: TPDDocumentContext);
begin
  inherited Create(Dictionary, Context);
  FNoUnicode := TDictionary<Integer, Boolean>.Create;
  CreateDescendantFont;
  ReadEncoding;
  FetchCMapUCS2;
end;

destructor TPDType0Font.Destroy;
begin
  FDescendantFont.Free;
  if FOwnsCMap then
  begin
    FCMap.Free;
  end;
  FNoUnicode.Free;
  inherited;
end;

function TPDType0Font.GetDescendantDictionary: TCosDictionary;
begin
  var DescendantFonts: TCosArray;
  if not CosObject.TryGetCosArray(TCosNames.DescendantFonts, DescendantFonts) then
  begin
    raise EPdfParseException.Create('Missing descendant font array');
  end;
  if DescendantFonts.Count < MinimumDescendantCount then
  begin
    raise EPdfParseException.Create('Descendant font array is empty');
  end;

  const Base = DescendantFonts.GetObject(0);
  if not (Base is TCosDictionary) then
  begin
    raise EPdfParseException.Create('Missing descendant font dictionary');
  end;

  Result := TCosDictionary(Base);
  if Result.GetNameAsString(TCosNames.Type_, TCosNames.Font) <> TCosNames.Font then
  begin
    raise EPdfParseException.Create('Missing or wrong type in descendant font dictionary');
  end;
end;

procedure TPDType0Font.CreateDescendantFont;
begin
  FDescendantFont := TPDFontFactory.CreateDescendantFont(GetDescendantDictionary, Self);
end;

function TPDType0Font.TryChargeBudget(const CMap: TCMap): Boolean;
begin
  // The mappings of an /Encoding CMap that is a stream count against the same budget as the ToUnicode CMaps of the document
  Result := ((not Assigned(Context)) or Context.TryChargeToUnicodeMappings(CMap.MappingCount));
end;

procedure TPDType0Font.ReadEncodingName(const EncodingName: string);
begin
  // Predefined CMap
  if not TCMapManager.TryGetPredefinedCMap(EncodingName, FCMap) then
  begin
    raise EPdfParseException.CreateFmt('Could not find predefined CMap file for ''%s''', [EncodingName]);
  end;
  FIsCMapPredefined := True;
end;

procedure TPDType0Font.ReadEncodingStream(const Encoding: TCosBase);
begin
  if (Encoding is TCosStream) and Assigned(Context) and Context.IsToUnicodeBudgetExhausted then
  begin
    LogWarning('The CMap budget of the document is used up, ignoring the Encoding CMap of font %s', [Name]);
    Exit;
  end;

  var OwnsCMap: Boolean;
  const CMap = ReadCMap(Encoding, OwnsCMap);
  if OwnsCMap and (not TryChargeBudget(CMap)) then
  begin
    CMap.Free;
    Exit;
  end;

  FCMap := CMap;
  FOwnsCMap := OwnsCMap;
  if not FCMap.HasCIDMappings then
  begin
    LogWarning('Invalid Encoding CMap in font %s', [Name]);
  end;
end;

procedure TPDType0Font.ReadEncoding;
begin
  // The font's Encoding entry should be a CMap name or stream
  var Encoding: TCosBase;
  if CosObject.TryGetDictionaryObject(TCosNames.Encoding, Encoding) then
  begin
    if Encoding is TCosName then
    begin
      ReadEncodingName(TCosName(Encoding).Name);
    end
    else
    begin
      ReadEncodingStream(Encoding);
    end;
  end;

  DetectCJKDescendant;
end;

procedure TPDType0Font.DetectCJKDescendant;
begin
  // Check if the descendant font is CJK
  var Info: TPDCIDSystemInfo;
  if not FDescendantFont.TryGetCIDSystemInfo(Info) then
  begin
    Exit;
  end;

  if Info.Registry <> AdobeRegistry then
  begin
    Exit;
  end;
  for var Ordering in CJKOrderings do
  begin
    if Info.Ordering = Ordering then
    begin
      FIsDescendantCJK := True;
      Exit;
    end;
  end;
end;

function TPDType0Font.TryGetEncodingName(out EncodingName: string): Boolean;
begin
  EncodingName := '';
  var Encoding: TCosBase;
  Result := (CosObject.TryGetDictionaryObject(TCosNames.Encoding, Encoding) and (Encoding is TCosName));
  if Result then
  begin
    EncodingName := TCosName(Encoding).Name;
  end;
end;

function TPDType0Font.TryGetUCS2SourceName(const EncodingName: string; const HasEncodingName: Boolean; out SourceName: string): Boolean;
begin
  SourceName := '';
  if FIsDescendantCJK then
  begin
    var Info: TPDCIDSystemInfo;
    if FDescendantFont.TryGetCIDSystemInfo(Info) then
    begin
      SourceName := Info.ToString;
    end;
  end
  else if HasEncodingName then
  begin
    SourceName := EncodingName;
  end;
  Result := (SourceName <> '');
end;

procedure TPDType0Font.LoadUCS2CMap(const SourceName: string);
begin
  // Try to find the corresponding Unicode (UCS2) CMap
  var Predefined: TCMap;
  if not TCMapManager.TryGetPredefinedCMap(SourceName, Predefined) then
  begin
    LogWarning('Could not get %s UC2 map for font %s: Could not find predefined CMap file for ''%s''', [SourceName, Name, SourceName]);
    Exit;
  end;

  const UCS2Name = Format('%s-%s-%s', [Predefined.Registry, Predefined.Ordering, UCS2Suffix]);
  if not TCMapManager.TryGetPredefinedCMap(UCS2Name, FCMapUCS2) then
  begin
    FCMapUCS2 := nil;
    LogWarning('Could not get %s UC2 map for font %s: Could not find predefined CMap file for ''%s''', [SourceName, Name, UCS2Name]);
  end;
end;

procedure TPDType0Font.FetchCMapUCS2;
begin
  // If the font is composite and uses a predefined cmap (excluding Identity-H/V) or whose descendant CIDFont uses the
  // Adobe-GB1, Adobe-CNS1, Adobe-Japan1, or Adobe-Korea1 character collection: map the character code to a CID using the
  // font's CMap, build the name "R-O-UCS2" from the ROS of the CIDSystemInfo and map the CID with that CMap
  var EncodingName: string;
  const HasEncodingName = TryGetEncodingName(EncodingName);
  const IsIdentity = (HasEncodingName and ((EncodingName = TCosNames.IdentityH) or (EncodingName = TCosNames.IdentityV)));
  if not ((FIsCMapPredefined and (not IsIdentity)) or FIsDescendantCJK) then
  begin
    Exit;
  end;

  var SourceName: string;
  if TryGetUCS2SourceName(EncodingName, HasEncodingName, SourceName) then
  begin
    LoadUCS2CMap(SourceName);
  end;
end;

function TPDType0Font.IsType0Font: Boolean;
begin
  Result := True;
end;

function TPDType0Font.TryEncode(const CodePoint: Integer; out Bytes: TBytes): Boolean;
begin
  Result := FDescendantFont.TryEncode(CodePoint, Bytes);
end;

function TPDType0Font.ReadCode(const Data: TBytes; var Position: Integer): Integer;
begin
  if not Assigned(FCMap) then
  begin
    raise EPdfParseException.Create('required cmap is null');
  end;

  if Assigned(Context) then
  begin
    Result := FCMap.ReadCode(Data, Position, Context.Log);
  end
  else
  begin
    Result := FCMap.ReadCode(Data, Position);
  end;
end;

procedure TPDType0Font.WarnAboutMissingUnicode(const Code: Integer);
begin
  // We keep track of which warnings have been issued, so we don't log multiple times
  if (FNoUnicode.Count < MaxNoUnicodeWarnings) and FNoUnicode.TryAdd(Code, True) then
  begin
    LogWarning('No Unicode mapping for CID+%d (%d) in font %s', [CodeToCID(Code), Code, Name]);
  end;
end;

function TPDType0Font.TryToUnicodeOfUCS2(const Code: Integer; out Value: string): Boolean;
begin
  // The font is composite and uses a predefined cmap (excluding Identity-H/V), or its descendant font uses
  // Adobe-GB1/CNS1/Japan1/Korea1. Map the code to a CID through the font's CMap, then the CID through the UCS2 CMap.
  Result := FCMapUCS2.TryToUnicode(CodeToCID(Code), Value);
end;

function TPDType0Font.TryToUnicodeOfTrueType(const Ttf: TTrueTypeFont; const Code: Integer; out Value: string): Boolean;
begin
  Value := '';
  Result := False;
  try
    var Lookup: TCmapSubtable;
    if not Ttf.TryGetUnicodeCmapLookup(False, Lookup) then
    begin
      Exit;
    end;

    var GID: Integer;
    if FDescendantFont.IsEmbedded then
    begin
      // Original PDFBOX-5324 supported only embedded fonts
      GID := FDescendantFont.CodeToGID(Code);
    end
    else
    begin
      // PDFBOX-5331: this bypasses the fallback attempt in codeToGID, which would bring a stack overflow
      GID := FDescendantFont.CodeToCID(Code);
    end;

    const Codes = Lookup.GetCharCodes(GID);
    if Length(Codes) > 0 then
    begin
      Value := Char(Word(Codes[0] and $FFFF));
      Result := True;
    end;
  except
    on Failure: Exception do
    begin
      if not ((Failure is EPdfException) or TPdfFailure.IsInputFailure(Failure)) then
      begin
        raise;
      end;
      LogWarning('get unicode from font cmap fail: %s', [Failure.Message]);
    end;
  end;
end;

function TPDType0Font.TryToUnicodeOfFontCmap(const Code: Integer; out Value: string): Boolean;
begin
  Value := '';
  // PDFBOX-5324: try to get unicode from the cmap of the font
  if not (FDescendantFont is TPDCIDFontType2) then
  begin
    Exit(False);
  end;

  const Font = TPDCIDFontType2(FDescendantFont).GetTrueTypeFont;
  Result := (Assigned(Font) and TryToUnicodeOfTrueType(Font, Code, Value));
end;

function TPDType0Font.TryToUnicode(const Code: Integer; out Value: string): Boolean;
begin
  // Try to use a ToUnicode CMap
  if inherited TryToUnicode(Code, Value) then
  begin
    Exit(True);
  end;

  // Use identity mapping if the given ToUnicode CMap doesn't provide any valid mapping. A predefined map shall only be
  // used if there isn't any ToUnicode CMap. PDFBOX-6022: not when there's a predefined cmap.
  var ToUnicodeCMap: TCMap;
  if TryGetToUnicodeCMap(ToUnicodeCMap) and (not FIsCMapPredefined) then
  begin
    Value := Char(Word(Code and $FFFF));
    Exit(True);
  end;

  if (FIsCMapPredefined or FIsDescendantCJK) and Assigned(FCMapUCS2) then
  begin
    Exit(TryToUnicodeOfUCS2(Code, Value));
  end;

  if TryToUnicodeOfFontCmap(Code, Value) then
  begin
    Exit(True);
  end;

  // If no value has been produced, there is no way to obtain Unicode for the character
  WarnAboutMissingUnicode(Code);
  Value := '';
  Result := False;
end;

function TPDType0Font.TryToUnicode(const Code: Integer; const CustomGlyphList: TGlyphList; out Value: string): Boolean;
begin
  Result := TryToUnicode(Code, Value);
end;

function TPDType0Font.TryGetCMap(out CMap: TCMap): Boolean;
begin
  CMap := FCMap;
  Result := Assigned(FCMap);
end;

function TPDType0Font.TryGetCMapUCS2(out CMap: TCMap): Boolean;
begin
  CMap := FCMapUCS2;
  Result := Assigned(FCMapUCS2);
end;

function TPDType0Font.TryGetFontDescriptor(out Descriptor: TPDFontDescriptor): Boolean;
begin
  if Assigned(FDescendantFont) then
  begin
    Exit(FDescendantFont.TryGetFontDescriptor(Descriptor));
  end;
  Result := inherited TryGetFontDescriptor(Descriptor);
end;

function TPDType0Font.IsVertical: Boolean;
begin
  Result := (Assigned(FCMap) and (FCMap.WMode = WModeVertical));
end;

function TPDType0Font.IsStandard14: Boolean;
begin
  Result := False;
end;

function TPDType0Font.IsEmbedded: Boolean;
begin
  Result := FDescendantFont.IsEmbedded;
end;

function TPDType0Font.IsDamaged: Boolean;
begin
  Result := FDescendantFont.IsDamaged;
end;

function TPDType0Font.GetWidth(const Code: Integer): Single;
begin
  Result := FDescendantFont.GetWidth(Code);
end;

function TPDType0Font.GetWidthFromFont(const Code: Integer): Single;
begin
  Result := FDescendantFont.GetWidthFromFont(Code);
end;

function TPDType0Font.HasExplicitWidth(const Code: Integer): Boolean;
begin
  Result := FDescendantFont.HasExplicitWidth(Code);
end;

function TPDType0Font.GetAverageFontWidth: Single;
begin
  Result := FDescendantFont.GetAverageFontWidth;
end;

function TPDType0Font.GetHeight(const Code: Integer): Single;
begin
  Result := FDescendantFont.GetHeight(Code);
end;

function TPDType0Font.GetDisplacement(const Code: Integer): TPdfVector;
begin
  if IsVertical then
  begin
    Exit(TPdfVector.Create(0, FDescendantFont.GetVerticalDisplacementVectorY(Code) / Thousand));
  end;
  Result := inherited GetDisplacement(Code);
end;

function TPDType0Font.GetPositionVector(const Code: Integer): TPdfVector;
begin
  // Units are always 1/1000 text space, font matrix is not used, see FOP-2252
  Result := FDescendantFont.GetPositionVector(Code).Scale(NegativeThousandth);
end;

function TPDType0Font.GetFontMatrix: TPdfMatrix;
begin
  Result := FDescendantFont.GetFontMatrix;
end;

function TPDType0Font.GetBoundingBox: TBoundingBox;
begin
  // Will be cached by the underlying font
  Result := FDescendantFont.GetBoundingBox;
end;

function TPDType0Font.CodeToCID(const Code: Integer): Integer;
begin
  Result := FDescendantFont.CodeToCID(Code);
end;

function TPDType0Font.CodeToGID(const Code: Integer): Integer;
begin
  Result := FDescendantFont.CodeToGID(Code);
end;

function TPDType0Font.TryGetPath(const Code: Integer; out Path: TPdfPath): Boolean;
begin
  Result := FDescendantFont.TryGetPath(Code, Path);
end;

function TPDType0Font.TryGetNormalizedPath(const Code: Integer; out Path: TPdfPath): Boolean;
begin
  Result := FDescendantFont.TryGetNormalizedPath(Code, Path);
end;

function TPDType0Font.HasGlyph(const Code: Integer): Boolean;
begin
  Result := FDescendantFont.HasGlyph(Code);
end;

end.
