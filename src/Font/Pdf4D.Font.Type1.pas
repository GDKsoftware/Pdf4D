// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/font/PDType1Font.java (3.0.8)
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/font/PDMMType1Font.java (3.0.8)
unit Pdf4D.Font.Type1;

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
  Pdf4D.FontBox.FontBoxFont,
  Pdf4D.FontBox.Type1.Font,
  Pdf4D.Model.DocumentContext;

type
  // A Type 1 or MMType1 font: an embedded /FontFile, one of the standard 14 fonts, or a font from the font mapper. Also
  // used for a Type1C font that has no /FontFile3 and for fonts of an unknown subtype.
  TPDType1Font = class(TPDSimpleFont)
  private
    const PfbStartMarker = $80;

  private
    FType1Font: TType1Font;
    FGenericFont: TFontBoxFont;
    FIsEmbedded: Boolean;
    FIsDamaged: Boolean;
    FHasFontMatrix: Boolean;
    FFontMatrix: TPdfMatrix;
    FHasBoundingBox: Boolean;
    FBoundingBox: TBoundingBox;

    procedure LoadEmbeddedFont;
    procedure LoadFontFile(const FontFile: TCosStream);
    function ReadType1Font(const FontFile: TCosStream): TType1Font;
    function CreateFromSegments(const Bytes: TBytes; const Length1, Length2: Int64): TType1Font;
    function RepairLength1(const Bytes: TBytes; const Length1: Int64): Int64;
    function RepairLength2(const Bytes: TBytes; const Length1, Length2: Int64): Int64;
    class function FindBinaryOffsetAfterExec(const Bytes: TBytes; const StartOffset: Int64): Int64; static;
    procedure LoadMappedFont;
    function GetNameInFont(const GlyphName: string): string;
    function TryGetAlternativeName(const GlyphName: string; out AlternativeName: string): Boolean;
    function TryGetUnicodeName(const GlyphName: string; out UniName: string): Boolean;
    function TryGetSymbolName(const GlyphName: string; out SymbolName: string): Boolean;
    function ReadFontMatrix: TPdfMatrix;
    function GenerateBoundingBox: TBoundingBox;
    function EncodingName(const Code: Integer): string;
    function TryGetPathOfName(const GlyphName: string; out Path: TPdfPath): Boolean;

  protected
    function ReadEncodingFromFont: TPdfEncoding; override;
    function TryEncode(const CodePoint: Integer; out Bytes: TBytes): Boolean; override;

  public
    // Does not own Dictionary or Context. An embedded font program belongs to the font; a font from the font mapper is
    // shared and stays with the mapper.
    constructor Create(const Dictionary: TCosDictionary; const Context: TPDDocumentContext);
    destructor Destroy; override;

    function GetWidthFromFont(const Code: Integer): Single; override;
    function GetAverageFontWidth: Single; override;
    function GetFontMatrix: TPdfMatrix; override;
    function GetBoundingBox: TBoundingBox; override;
    function IsEmbedded: Boolean; override;
    function IsDamaged: Boolean; override;
    // The glyph name of the code, as the font program calls it
    function CodeToName(const Code: Integer): string; override;
    function GetFontBoxFont: TFontBoxFont; override;
    // The embedded font program, or nil
    function GetType1Font: TType1Font;
    // PDType1Font.getPath(int): the glyph name of the encoding, found in the font program under the name that GetNameInFont
    // gives. A substitute font draws no .notdef, as Acrobat does not.
    function TryGetPath(const Code: Integer; out Path: TPdfPath): Boolean; override;
    function TryGetNormalizedPath(const Code: Integer; out Path: TPdfPath): Boolean; override;
    // PDType1Font.hasGlyph(int): the encoding names the code
    function HasGlyph(const Code: Integer): Boolean; overload; override;
    // PDType1Font.hasGlyph(String)
    function HasGlyph(const GlyphName: string): Boolean; overload;
  end;

implementation

uses
  System.Generics.Collections,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Names,
  Pdf4D.Font.Descriptor,
  Pdf4D.Font.Encoding.Tables,
  Pdf4D.Font.Mapper,
  Pdf4D.FontBox.Afm,
  Pdf4D.FontBox.Cff.Encoding,
  Pdf4D.FontBox.Cff.Font,
  Pdf4D.FontBox.Encoding,
  Pdf4D.Model.Rectangle;

const
  NotDefName = '.notdef';

type
  // The shared table of alternative names for glyphs that are commonly encountered
  TAlternativeNames = class
  public
    class function TryGet(const GlyphName: string; out AlternativeName: string): Boolean; static;
  end;

{ TAlternativeNames }

class function TAlternativeNames.TryGet(const GlyphName: string; out AlternativeName: string): Boolean;
begin
  Result := True;
  if GlyphName = 'ff' then
  begin
    AlternativeName := 'f_f';
  end
  else if GlyphName = 'ffi' then
  begin
    AlternativeName := 'f_f_i';
  end
  else if GlyphName = 'ffl' then
  begin
    AlternativeName := 'f_f_l';
  end
  else if GlyphName = 'fi' then
  begin
    AlternativeName := 'f_i';
  end
  else if GlyphName = 'fl' then
  begin
    AlternativeName := 'f_l';
  end
  else if GlyphName = 'st' then
  begin
    AlternativeName := 's_t';
  end
  else if GlyphName = 'IJ' then
  begin
    AlternativeName := 'I_J';
  end
  else if GlyphName = 'ij' then
  begin
    AlternativeName := 'i_j';
  end
  else if GlyphName = 'ellipsis' then
  begin
    // Misspelled in ArialMT
    AlternativeName := 'elipsis';
  end
  else
  begin
    AlternativeName := '';
    Result := False;
  end;
end;

{ TPDType1Font }

constructor TPDType1Font.Create(const Dictionary: TCosDictionary; const Context: TPDDocumentContext);
begin
  inherited Create(Dictionary, Context);
  LoadEmbeddedFont;
  if Assigned(FType1Font) then
  begin
    FGenericFont := FType1Font;
  end
  else
  begin
    LoadMappedFont;
  end;
  ReadEncoding;
end;

destructor TPDType1Font.Destroy;
begin
  // A generic font that is not the embedded one is shared and belongs to the font mapper
  FType1Font.Free;
  inherited;
end;

procedure TPDType1Font.LoadEmbeddedFont;
begin
  var Descriptor: TPDFontDescriptor;
  if not TryGetFontDescriptor(Descriptor) then
  begin
    Exit;
  end;

  // A Type 1 font may contain a Type 1C font
  var FontFile3: TCosStream;
  if Descriptor.TryGetFontFile3(FontFile3) then
  begin
    LogWarning('/FontFile3 for Type1 font not supported', []);
  end;

  // Or it may contain a PFB
  var FontFile: TCosStream;
  if Descriptor.TryGetFontFile(FontFile) then
  begin
    LoadFontFile(FontFile);
  end;
end;

procedure TPDType1Font.LoadFontFile(const FontFile: TCosStream);
begin
  try
    FType1Font := ReadType1Font(FontFile);
  except
    on Failure: Exception do
    begin
      if not IsRecoverableFailure(Failure) then
      begin
        raise;
      end;

      if Failure is EPdfParseException then
      begin
        LogWarning('Can''t read damaged embedded Type1 font %s: %s', [Name, Failure.Message]);
      end
      else
      begin
        LogError('Can''t read the embedded Type1 font %s: %s', [Name, Failure.Message]);
      end;
      FType1Font := nil;
      FIsDamaged := True;
    end;
  end;
  FIsEmbedded := Assigned(FType1Font);
end;

function TPDType1Font.ReadType1Font(const FontFile: TCosStream): TType1Font;
begin
  const Length1 = FontFile.GetInt(TCosNames.Length1, 0);
  const Length2 = FontFile.GetInt(TCosNames.Length2, 0);
  const Bytes = ReadStreamBytes(FontFile);
  if Length(Bytes) = 0 then
  begin
    raise EPdfParseException.Create('Font data unavailable');
  end;

  // Repair Length1 and Length2 if necessary
  const RepairedLength1 = RepairLength1(Bytes, Length1);
  const RepairedLength2 = RepairLength2(Bytes, RepairedLength1, Length2);
  if Bytes[0] = PfbStartMarker then
  begin
    // Some bad files embed the entire PFB, see PDFBOX-2607
    Result := TType1Font.CreateWithPFB(Bytes, DocumentLog);
  end
  else
  begin
    Result := CreateFromSegments(Bytes, RepairedLength1, RepairedLength2);
  end;
end;

function TPDType1Font.CreateFromSegments(const Bytes: TBytes; const Length1, Length2: Int64): TType1Font;
begin
  // The PFB embedded as two segments back-to-back
  if (Length1 < 0) or (Length1 > Length1 + Length2) or (Length1 + Length2 > Length(Bytes)) then
  begin
    raise EPdfParseException.CreateFmt('Invalid length data, actual length: %d, /Length1: %d, /Length2: %d',
                                       [Length(Bytes), Length1, Length2]);
  end;

  // Empty streams are simply ignored
  Result := nil;
  if (Length1 > 0) and (Length2 > 0) then
  begin
    const Segment1 = Copy(Bytes, 0, Integer(Length1));
    const Segment2 = Copy(Bytes, Integer(Length1), Integer(Length2));
    Result := TType1Font.CreateWithSegments(Segment1, Segment2, DocumentLog);
  end;
end;

function TPDType1Font.RepairLength1(const Bytes: TBytes; const Length1: Int64): Int64;
begin
  // Scan backwards from the end of the first segment to find 'exec'
  var Offset := Length1 - 4;
  if Offset < 0 then
  begin
    Offset := 0;
  end;
  if (Offset <= 0) or (Offset > Length(Bytes) - 4) then
  begin
    Offset := Length(Bytes) - 4;
  end;

  Offset := FindBinaryOffsetAfterExec(Bytes, Offset);
  if (Offset = 0) and (Length1 > 0) then
  begin
    // 2nd try with brute force
    Offset := FindBinaryOffsetAfterExec(Bytes, Length(Bytes) - 4);
  end;

  if (Length1 - Offset <> 0) and (Offset > 0) then
  begin
    LogWarning('Ignored invalid Length1 %d for Type 1 font %s', [Length1, Name]);
    Exit(Offset);
  end;
  Result := Length1;
end;

class function TPDType1Font.FindBinaryOffsetAfterExec(const Bytes: TBytes; const StartOffset: Int64): Int64;
begin
  Result := StartOffset;
  while Result > 0 do
  begin
    const IsExec = ((Result + 3 < Length(Bytes)) and (Bytes[Result] = Ord('e')) and (Bytes[Result + 1] = Ord('x')) and
                    (Bytes[Result + 2] = Ord('e')) and (Bytes[Result + 3] = Ord('c')));
    if IsExec then
    begin
      Inc(Result, 4);
      // Skip additional CR LF space characters
      while (Result < Length(Bytes)) and (Bytes[Result] in [13, 10, 32, 9]) do
      begin
        Inc(Result);
      end;
      Break;
    end;
    Dec(Result);
  end;
end;

function TPDType1Font.RepairLength2(const Bytes: TBytes; const Length1, Length2: Int64): Int64;
begin
  if (Length2 < 0) or (Length2 > Length(Bytes) - Length1) then
  begin
    LogWarning('Ignored invalid Length2 %d for Type 1 font %s', [Length2, Name]);
    Exit(Length(Bytes) - Length1);
  end;
  Result := Length2;
end;

procedure TPDType1Font.LoadMappedFont;
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
    LogWarning('Using fallback font %s for base font %s', [FGenericFont.Name, Name]);
  end;
end;

function TPDType1Font.ReadEncodingFromFont: TPdfEncoding;
begin
  var Metrics: TFontMetrics;
  if (not IsEmbedded) and TryGetStandardAFM(Metrics) then
  begin
    // Read from AFM
    Exit(AdoptEncoding(TType1Encoding.FromMetrics(Metrics)));
  end;

  // Extract from the Type 1 font or the substitute
  if FGenericFont is TType1Font then
  begin
    const FontEncoding = TType1Font(FGenericFont).Encoding;
    if Assigned(FontEncoding) then
    begin
      Exit(AdoptEncoding(TType1Encoding.FromFontBox(FontEncoding)));
    end;
  end
  else if FGenericFont is TCFFType1Font then
  begin
    const FontEncoding = TCFFType1Font(FGenericFont).Encoding;
    if Assigned(FontEncoding) then
    begin
      Exit(AdoptEncoding(TType1Encoding.FromFontBox(FontEncoding)));
    end;
  end;

  // Default (only happens with TTFs)
  Result := TStandardEncoding.Instance;
end;

function TPDType1Font.CodeToName(const Code: Integer): string;
begin
  Result := GetNameInFont(inherited CodeToName(Code));
end;

function TPDType1Font.TryGetAlternativeName(const GlyphName: string; out AlternativeName: string): Boolean;
begin
  Result := (TAlternativeNames.TryGet(GlyphName, AlternativeName) and (GlyphName <> NotDefName) and
             FGenericFont.HasGlyph(AlternativeName));
end;

function TPDType1Font.TryGetUnicodeName(const GlyphName: string; out UniName: string): Boolean;
begin
  UniName := '';
  var Unicodes: string;
  if (not GlyphList.TryToUnicode(GlyphName, Unicodes)) or (Length(Unicodes) <> 1) then
  begin
    Exit(False);
  end;

  UniName := GetUniNameOfCodePoint(Ord(Unicodes[1]));
  Result := FGenericFont.HasGlyph(UniName);
end;

function TPDType1Font.TryGetSymbolName(const GlyphName: string; out SymbolName: string): Boolean;
begin
  // PDFBOX-4017: no postscript table on Windows 10, and the low uni00NN names are not found in the Symbol font. What
  // works is using the PDF code plus 0xF000 while disregarding the encoding from the PDF (because of the file from
  // PDFBOX-1606; it makes sense because this is about finding the name in a standard font).
  SymbolName := '';
  var Code: Integer;
  Result := ((FGenericFont.Name = 'SymbolMT') and TSymbolEncoding.Instance.NameToCodeMap.TryGetValue(GlyphName, Code));
  if Result then
  begin
    SymbolName := GetUniNameOfCodePoint(Code + $F000);
    Result := FGenericFont.HasGlyph(SymbolName);
  end;
end;

function TPDType1Font.GetNameInFont(const GlyphName: string): string;
begin
  if IsEmbedded or FGenericFont.HasGlyph(GlyphName) then
  begin
    Exit(GlyphName);
  end;

  // Try an alternative name
  var FoundName: string;
  if TryGetAlternativeName(GlyphName, FoundName) then
  begin
    Exit(FoundName);
  end;

  // Try a Unicode name
  if TryGetUnicodeName(GlyphName, FoundName) then
  begin
    Exit(FoundName);
  end;

  var Unicodes: string;
  if GlyphList.TryToUnicode(GlyphName, Unicodes) and (Length(Unicodes) = 1) and TryGetSymbolName(GlyphName, FoundName) then
  begin
    Exit(FoundName);
  end;
  Result := NotDefName;
end;

function TPDType1Font.GetWidthFromFont(const Code: Integer): Single;
begin
  const GlyphName = CodeToName(Code);
  // The width of .notdef is ignored for substitutes, see PDFBOX-1900
  if (not IsEmbedded) and (GlyphName = NotDefName) then
  begin
    Exit(250);
  end;

  Result := ScaleToTextSpace(FGenericFont.GetWidth(GlyphName));
end;

function TPDType1Font.IsEmbedded: Boolean;
begin
  Result := FIsEmbedded;
end;

function TPDType1Font.IsDamaged: Boolean;
begin
  Result := FIsDamaged;
end;

function TPDType1Font.GetAverageFontWidth: Single;
begin
  var Metrics: TFontMetrics;
  if TryGetStandardAFM(Metrics) then
  begin
    Result := Metrics.GetAverageCharacterWidth;
  end
  else
  begin
    Result := inherited GetAverageFontWidth;
  end;
end;

function TPDType1Font.ReadFontMatrix: TPdfMatrix;
begin
  // PDF specified that Type 1 fonts use a 1000upem matrix, but some fonts specify their own custom matrix anyway, for
  // example PDFBOX-2298
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

function TPDType1Font.GetFontMatrix: TPdfMatrix;
begin
  if not FHasFontMatrix then
  begin
    FFontMatrix := ReadFontMatrix;
    FHasFontMatrix := True;
  end;
  Result := FFontMatrix;
end;

function TPDType1Font.GenerateBoundingBox: TBoundingBox;
begin
  var Descriptor: TPDFontDescriptor;
  var Box: TPdfRectangle;
  if TryGetFontDescriptor(Descriptor) and Descriptor.TryGetFontBoundingBox(Box) and IsNonZeroBoundingBox(Box) then
  begin
    Exit(TBoundingBox.Create(Box.LowerLeftX, Box.LowerLeftY, Box.UpperRightX, Box.UpperRightY));
  end;
  Result := FGenericFont.FontBBox;
end;

function TPDType1Font.GetBoundingBox: TBoundingBox;
begin
  if not FHasBoundingBox then
  begin
    FBoundingBox := GenerateBoundingBox;
    FHasBoundingBox := True;
  end;
  Result := FBoundingBox;
end;

function TPDType1Font.GetFontBoxFont: TFontBoxFont;
begin
  Result := FGenericFont;
end;

function TPDType1Font.GetType1Font: TType1Font;
begin
  Result := FType1Font;
end;

function TPDType1Font.HasGlyph(const GlyphName: string): Boolean;
begin
  Result := FGenericFont.HasGlyph(GetNameInFont(GlyphName));
end;

function TPDType1Font.HasGlyph(const Code: Integer): Boolean;
begin
  Result := (EncodingName(Code) <> NotDefName);
end;

function TPDType1Font.EncodingName(const Code: Integer): string;
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

function TPDType1Font.TryGetPathOfName(const GlyphName: string; out Path: TPdfPath): Boolean;
begin
  if (GlyphName = NotDefName) and (not IsEmbedded) then
  begin
    Path := TPdfPath.Create;
    Exit(True);
  end;

  Result := FGenericFont.TryGetPath(GetNameInFont(GlyphName), Path);
end;

function TPDType1Font.TryGetPath(const Code: Integer; out Path: TPdfPath): Boolean;
begin
  Result := TryGetPathOfName(EncodingName(Code), Path);
end;

function TPDType1Font.TryGetNormalizedPath(const Code: Integer; out Path: TPdfPath): Boolean;
begin
  if TryGetPathOfName(EncodingName(Code), Path) then
  begin
    Exit(True);
  end;

  Result := TryGetPathOfName(NotDefName, Path);
end;

function TPDType1Font.TryEncode(const CodePoint: Integer; out Bytes: TBytes): Boolean;
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

  if IsStandard14 then
  begin
    // The generic font is not needed, which is important on systems with no installed fonts
    if GlyphName = NotDefName then
    begin
      Exit(False);
    end;
  end
  else
  begin
    const NameInFont = GetNameInFont(GlyphName);
    if (NameInFont = NotDefName) or (not FGenericFont.HasGlyph(NameInFont)) then
    begin
      Exit(False);
    end;
  end;

  var Code: Integer;
  if (not Encoding.NameToCodeMap.TryGetValue(GlyphName, Code)) or (Code < 0) or (Code > High(Byte)) then
  begin
    Exit(False);
  end;
  Bytes := [Byte(Code)];
  Result := True;
end;

end.
