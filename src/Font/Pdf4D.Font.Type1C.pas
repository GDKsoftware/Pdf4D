// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/font/PDType1CFont.java (3.0.8)
unit Pdf4D.Font.Type1C;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Common.Matrix,
  Pdf4D.Common.Path,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Font.Encoding,
  Pdf4D.Font.Simple,
  Pdf4D.FontBox.BoundingBox,
  Pdf4D.FontBox.Cff.Font,
  Pdf4D.FontBox.FontBoxFont,
  Pdf4D.Model.DocumentContext;

type
  // A Type 1 font with a /FontFile3 (a CFF font, or an OpenType font with CFF data). Without a usable font file the
  // font mapper gives a substitute.
  TPDType1CFont = class(TPDSimpleFont)
  private
    FCffFont: TCFFType1Font;
    FGenericFont: TFontBoxFont;
    FIsEmbedded: Boolean;
    FIsDamaged: Boolean;
    FHasFontMatrix: Boolean;
    FFontMatrix: TPdfMatrix;
    FHasBoundingBox: Boolean;
    FBoundingBox: TBoundingBox;

    procedure LoadEmbeddedFont;
    procedure LoadFontFile(const FontFile: TCosStream);
    function ParseFirstFont(const Data: TBytes): TCFFType1Font;
    procedure LoadMappedFont;
    function GetNameInFont(const GlyphName: string): string;
    function ReadFontMatrix: TPdfMatrix;
    function GenerateBoundingBox: TBoundingBox;
    function ReadGlyphWidth(const GlyphName: string): Single;
    function EncodingName(const Code: Integer): string;
    function TryGetGenericPath(const GlyphName: string; out Path: TPdfPath): Boolean;
    function TryGetPathOfName(const GlyphName: string; out Path: TPdfPath): Boolean;

  protected
    function ReadEncodingFromFont: TPdfEncoding; override;
    function TryEncode(const CodePoint: Integer; out Bytes: TBytes): Boolean; override;

  public
    // Does not own Dictionary or Context. The embedded CFF font belongs to the font; a font from the font mapper is
    // shared and stays with the mapper.
    constructor Create(const Dictionary: TCosDictionary; const Context: TPDDocumentContext);
    destructor Destroy; override;

    function GetWidthFromFont(const Code: Integer): Single; override;
    // PDFBox has no real average width for a Type 1C font: it answers 500
    function GetAverageFontWidth: Single; override;
    function GetFontMatrix: TPdfMatrix; override;
    function GetBoundingBox: TBoundingBox; override;
    function IsEmbedded: Boolean; override;
    function IsDamaged: Boolean; override;
    function GetFontBoxFont: TFontBoxFont; override;
    // The embedded font program, or nil
    function GetCFFType1Font: TCFFType1Font;

    // PDType1CFont.getPath(int): the glyph name of the encoding as GetNameInFont gives it, with sfthyphen drawn as hyphen and
    // nbspace as space. A substitute that is not one of the standard 14 draws no .notdef.
    function TryGetPath(const Code: Integer; out Path: TPdfPath): Boolean; override;
    function TryGetNormalizedPath(const Code: Integer; out Path: TPdfPath): Boolean; override;
    function HasGlyph(const Code: Integer): Boolean; overload; override;
    function HasGlyph(const GlyphName: string): Boolean; overload;
  end;

implementation

uses
  System.Generics.Collections,
  Pdf4D.Common.Defines,
  Pdf4D.Font.Descriptor,
  Pdf4D.Font.Encoding.Tables,
  Pdf4D.Font.Mapper,
  Pdf4D.FontBox.Afm,
  Pdf4D.FontBox.Cff.Parser,
  Pdf4D.FontBox.Type1.Font,
  Pdf4D.Model.Rectangle;

const
  AverageCharacterWidth = 500;
  NotDefName = '.notdef';
  SoftHyphenName = 'sfthyphen';
  HyphenName = 'hyphen';
  NoBreakSpaceName = 'nbspace';
  SpaceName = 'space';

{ TPDType1CFont }

constructor TPDType1CFont.Create(const Dictionary: TCosDictionary; const Context: TPDDocumentContext);
begin
  inherited Create(Dictionary, Context);
  LoadEmbeddedFont;
  if Assigned(FCffFont) then
  begin
    FGenericFont := FCffFont;
    FIsEmbedded := True;
  end
  else
  begin
    LoadMappedFont;
  end;
  ReadEncoding;
end;

destructor TPDType1CFont.Destroy;
begin
  // A generic font that is not the embedded one is shared and belongs to the font mapper
  FCffFont.Free;
  inherited;
end;

procedure TPDType1CFont.LoadEmbeddedFont;
begin
  var Descriptor: TPDFontDescriptor;
  var FontFile: TCosStream;
  if TryGetFontDescriptor(Descriptor) and Descriptor.TryGetFontFile3(FontFile) then
  begin
    LoadFontFile(FontFile);
  end;
end;

procedure TPDType1CFont.LoadFontFile(const FontFile: TCosStream);
begin
  try
    const Data = ReadStreamBytes(FontFile);
    if Length(Data) = 0 then
    begin
      LogError('Invalid data for embedded Type1C font %s', [Name]);
    end
    else
    begin
      FCffFont := ParseFirstFont(Data);
    end;
  except
    on Failure: Exception do
    begin
      if not IsRecoverableFailure(Failure) then
      begin
        raise;
      end;
      LogError('Can''t read the embedded Type1C font %s: %s', [Name, Failure.Message]);
      FCffFont := nil;
      FIsDamaged := True;
    end;
  end;
end;

function TPDType1CFont.ParseFirstFont(const Data: TBytes): TCFFType1Font;
begin
  Result := nil;
  // Note: this could be an OpenType file, fortunately the CFF parser can handle that
  const Parser = TCFFParser.Create(DocumentLog);
  try
    const Fonts = Parser.Parse(Data, 1);
    try
      if Fonts.Count = 0 then
      begin
        raise EPdfParseException.Create('The CFF data has no font');
      end;

      const Parsed = Fonts.Extract(Fonts[0]);
      if Parsed is TCFFType1Font then
      begin
        Result := TCFFType1Font(Parsed);
      end
      else
      begin
        LogError('Expected CFFType1Font, got %s', [Parsed.ClassName]);
        Parsed.Free;
        FIsDamaged := True;
      end;
    finally
      Fonts.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TPDType1CFont.LoadMappedFont;
begin
  var Descriptor: TPDFontDescriptor;
  if not TryGetFontDescriptor(Descriptor) then
  begin
    Descriptor := nil;
  end;

  const Mapping = TPdfFontMappers.Instance.GetFontBoxFont(Name, Descriptor);
  FGenericFont := Mapping.Font;
  if Mapping.IsFallback then
  begin
    LogWarning('Using fallback font %s for %s', [FGenericFont.Name, Name]);
  end;
end;

function TPDType1CFont.ReadEncodingFromFont: TPdfEncoding;
begin
  var Metrics: TFontMetrics;
  if (not IsEmbedded) and TryGetStandardAFM(Metrics) then
  begin
    // Read from AFM
    Exit(AdoptEncoding(TType1Encoding.FromMetrics(Metrics)));
  end;

  // Extract from the Type 1 font or the substitute
  if FGenericFont is TCFFType1Font then
  begin
    const FontEncoding = TCFFType1Font(FGenericFont).Encoding;
    if Assigned(FontEncoding) then
    begin
      Exit(AdoptEncoding(TType1Encoding.FromFontBox(FontEncoding)));
    end;
  end
  else if FGenericFont is TType1Font then
  begin
    const FontEncoding = TType1Font(FGenericFont).Encoding;
    if Assigned(FontEncoding) then
    begin
      Exit(AdoptEncoding(TType1Encoding.FromFontBox(FontEncoding)));
    end;
  end;

  // Default (only happens with TTFs)
  Result := TStandardEncoding.Instance;
end;

function TPDType1CFont.GetNameInFont(const GlyphName: string): string;
begin
  if IsEmbedded or FGenericFont.HasGlyph(GlyphName) then
  begin
    Exit(GlyphName);
  end;

  // Try a Unicode name
  var Unicodes: string;
  if GlyphList.TryToUnicode(GlyphName, Unicodes) and (Length(Unicodes) = 1) then
  begin
    const UniName = GetUniNameOfCodePoint(Ord(Unicodes[1]));
    if FGenericFont.HasGlyph(UniName) then
    begin
      Exit(UniName);
    end;
  end;
  Result := NotDefName;
end;

function TPDType1CFont.ReadGlyphWidth(const GlyphName: string): Single;
begin
  if not Assigned(FCffFont) then
  begin
    Exit(FGenericFont.GetWidth(GlyphName));
  end;

  // The embedded font is not shared, so the damaged charstrings are reported to the log of the document
  Result := FCffFont.GetWidthForGID(FCffFont.NameToGID(GlyphName), DocumentLog);
end;

function TPDType1CFont.GetWidthFromFont(const Code: Integer): Single;
begin
  var Encoding: TPdfEncoding;
  var GlyphName := NotDefName;
  if TryGetEncoding(Encoding) then
  begin
    GlyphName := Encoding.GetName(Code);
  end;
  Result := ScaleToTextSpace(ReadGlyphWidth(GetNameInFont(GlyphName)));
end;

function TPDType1CFont.GetAverageFontWidth: Single;
begin
  // Not implemented in PDFBox, highly suspect
  Result := AverageCharacterWidth;
end;

function TPDType1CFont.ReadFontMatrix: TPdfMatrix;
begin
  const Numbers = FGenericFont.FontMatrix;
  if Length(Numbers) = 6 then
  begin
    Result := TPdfMatrix.Create(Numbers[0], Numbers[1], Numbers[2], Numbers[3], Numbers[4], Numbers[5]);
  end
  else
  begin
    Result := inherited GetFontMatrix;
  end;
end;

function TPDType1CFont.GetFontMatrix: TPdfMatrix;
begin
  if not FHasFontMatrix then
  begin
    FFontMatrix := ReadFontMatrix;
    FHasFontMatrix := True;
  end;
  Result := FFontMatrix;
end;

function TPDType1CFont.GenerateBoundingBox: TBoundingBox;
begin
  var Descriptor: TPDFontDescriptor;
  var Box: TPdfRectangle;
  if TryGetFontDescriptor(Descriptor) and Descriptor.TryGetFontBoundingBox(Box) and IsNonZeroBoundingBox(Box) then
  begin
    Exit(TBoundingBox.Create(Box.LowerLeftX, Box.LowerLeftY, Box.UpperRightX, Box.UpperRightY));
  end;
  Result := FGenericFont.FontBBox;
end;

function TPDType1CFont.GetBoundingBox: TBoundingBox;
begin
  if not FHasBoundingBox then
  begin
    FBoundingBox := GenerateBoundingBox;
    FHasBoundingBox := True;
  end;
  Result := FBoundingBox;
end;

function TPDType1CFont.IsEmbedded: Boolean;
begin
  Result := FIsEmbedded;
end;

function TPDType1CFont.IsDamaged: Boolean;
begin
  Result := FIsDamaged;
end;

function TPDType1CFont.GetFontBoxFont: TFontBoxFont;
begin
  Result := FGenericFont;
end;

function TPDType1CFont.GetCFFType1Font: TCFFType1Font;
begin
  Result := FCffFont;
end;

function TPDType1CFont.HasGlyph(const GlyphName: string): Boolean;
begin
  Result := FGenericFont.HasGlyph(GlyphName);
end;

function TPDType1CFont.HasGlyph(const Code: Integer): Boolean;
begin
  const GlyphName = GetNameInFont(EncodingName(Code));
  if GlyphName = SoftHyphenName then
  begin
    Exit(HasGlyph(HyphenName));
  end;
  if GlyphName = NoBreakSpaceName then
  begin
    Exit(HasGlyph(SpaceName));
  end;
  Result := HasGlyph(GlyphName);
end;

function TPDType1CFont.EncodingName(const Code: Integer): string;
begin
  var Encoding: TPdfEncoding;
  if TryGetEncoding(Encoding) then
  begin
    Result := Encoding.GetName(Code);
  end
  else
  begin
    Result := NotDefName;
  end;
end;

function TPDType1CFont.TryGetGenericPath(const GlyphName: string; out Path: TPdfPath): Boolean;
begin
  if Assigned(FCffFont) then
  begin
    // The embedded font is not shared, so the damaged charstrings are reported to the log of the document
    Exit(FCffFont.TryGetPathByGid(FCffFont.NameToGID(GlyphName), Path, DocumentLog));
  end;

  Result := FGenericFont.TryGetPath(GlyphName, Path);
end;

function TPDType1CFont.TryGetPathOfName(const GlyphName: string; out Path: TPdfPath): Boolean;
begin
  // Acrobat only draws .notdef for embedded or standard 14 fonts, see PDFBOX-2372
  if (GlyphName = NotDefName) and (not IsEmbedded) and (not IsStandard14) then
  begin
    Path := TPdfPath.Create;
    Exit(True);
  end;
  if GlyphName = SoftHyphenName then
  begin
    Exit(TryGetGenericPath(HyphenName, Path));
  end;
  if GlyphName = NoBreakSpaceName then
  begin
    if not HasGlyph(SpaceName) then
    begin
      Path := TPdfPath.Create;
      Exit(True);
    end;
    Exit(TryGetGenericPath(SpaceName, Path));
  end;
  Result := TryGetGenericPath(GlyphName, Path);
end;

function TPDType1CFont.TryGetPath(const Code: Integer; out Path: TPdfPath): Boolean;
begin
  Result := TryGetPathOfName(GetNameInFont(EncodingName(Code)), Path);
end;

function TPDType1CFont.TryGetNormalizedPath(const Code: Integer; out Path: TPdfPath): Boolean;
begin
  var GlyphName := GetNameInFont(EncodingName(Code));
  if GlyphName = NoBreakSpaceName then
  begin
    if not HasGlyph(SpaceName) then
    begin
      Path := TPdfPath.Create;
      Exit(True);
    end;
    GlyphName := SpaceName;
  end
  else if GlyphName = SoftHyphenName then
  begin
    GlyphName := HyphenName;
  end;

  if TryGetPathOfName(GlyphName, Path) then
  begin
    Exit(True);
  end;
  Result := TryGetPathOfName(NotDefName, Path);
end;

function TPDType1CFont.TryEncode(const CodePoint: Integer; out Bytes: TBytes): Boolean;
begin
  Bytes := nil;
  var Encoding: TPdfEncoding;
  if not TryGetEncoding(Encoding) then
  begin
    Exit(False);
  end;

  const GlyphName = GlyphList.CodePointToName(CodePoint);
  if not Encoding.Contains(GlyphName) then
  begin
    Exit(False);
  end;

  const NameInFont = GetNameInFont(GlyphName);
  var Code: Integer;
  const HasGlyphInFont = ((NameInFont <> NotDefName) and FGenericFont.HasGlyph(NameInFont));
  if (not HasGlyphInFont) or (not Encoding.NameToCodeMap.TryGetValue(GlyphName, Code)) or (Code < 0) or (Code > High(Byte)) then
  begin
    Exit(False);
  end;
  Bytes := [Byte(Code)];
  Result := True;
end;

end.
