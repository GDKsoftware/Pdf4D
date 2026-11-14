// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/font/PDCIDFontType0.java (3.0.8)
unit Pdf4D.Font.CIDFontType0;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Common.Matrix,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Font.CIDFont,
  Pdf4D.FontBox.BoundingBox,
  Pdf4D.FontBox.Cff.Font,
  Pdf4D.FontBox.FontBoxFont;

type
  // A CID-keyed font with CFF outlines. The embedded font program belongs to this font. A substitute from the font mapper is
  // shared and stays with the mapper, so it is never changed and never gets the log of a document. The embedded program is a
  // CID-keyed CFF font, or a Type 1-equivalent CFF font in a CID container (the CID is then the glyph). Glyph paths and the
  // CIDToGIDMap, which PDFBox only uses for paths, are left out.
  TPDCIDFontType0 = class(TPDCIDFont)
  private
    const PfbStart = Ord('%');
    const AverageCharacterWidth = 500;

  private
    // The program of the font: one of the two, or the TrueType substitute in FType1Font
    FCIDFont: TCFFCIDFont;
    FType1Font: TFontBoxFont;
    FOwnsFontProgram: Boolean;
    FIsEmbedded: Boolean;
    FIsDamaged: Boolean;
    FHasFontMatrix: Boolean;
    FFontMatrix: TPdfMatrix;
    FHasBoundingBox: Boolean;
    FBoundingBox: TBoundingBox;
    FIsScaleWarningGiven: Boolean;

    procedure LoadFontProgram;
    function TryLoadEmbeddedFont: Boolean;
    function TryReadEmbeddedFont(const FontFile: TCosStream; out Font: TCFFFont): Boolean;
    procedure UseEmbeddedFont(const Font: TCFFFont);
    procedure FindFontOrSubstitute;
    procedure UseMappedOpenTypeFont(const Font: TFontBoxFont);
    procedure LogError(const Fmt: string; const Args: array of const);
    function ReadFontMatrix: TPdfMatrix;
    function TryGetProgramMatrix(out Numbers: TArray<Single>): Boolean;
    function GenerateBoundingBox: TBoundingBox;
    function TryGetProgramBoundingBox(out Box: TBoundingBox): Boolean;
    function GetGlyphName(const Code: Integer): string;
    function ReadGlyphWidth(const Code: Integer): Single;
    function ScaleToTextSpace(const Width: Single): Single;
    class function ClampToGlyph(const CID: Integer): Integer; static;

  public
    // Does not own Dictionary or Parent
    constructor Create(const Dictionary: TCosDictionary; const Parent: TPDCIDFontParent);
    destructor Destroy; override;

    function CodeToCID(const Code: Integer): Integer; override;
    function CodeToGID(const Code: Integer): Integer; override;
    function GetWidthFromFont(const Code: Integer): Single; override;
    function GetFontMatrix: TPdfMatrix; override;
    function GetBoundingBox: TBoundingBox; override;
    // PDFBox takes the height of the charstring, which needs the glyph outline; this port answers the height of the font
    // bounding box. Nothing in text extraction asks for it.
    function GetHeight(const Code: Integer): Single; override;
    // PDFBox has no real average width for a CFF CID font: it answers 500
    function GetAverageFontWidth: Single; override;
    function IsEmbedded: Boolean; override;
    function IsDamaged: Boolean; override;
    // PDFBox throws UnsupportedOperationException
    function TryEncode(const CodePoint: Integer; out Bytes: TBytes): Boolean; override;

    // The CID-keyed CFF font, embedded or from the mapper; nil when there is none
    function GetCIDKeyedFont: TCFFCIDFont;
    // The embedded or substituted font program
    function GetFontBoxFont: TFontBoxFont;
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  System.Math,
  Pdf4D.Common.Defines,
  Pdf4D.Font.Descriptor,
  Pdf4D.Font.Mapper,
  Pdf4D.FontBox.CMap,
  Pdf4D.FontBox.Cff.Parser,
  Pdf4D.FontBox.OpenType,
  Pdf4D.FontBox.TrueType.Font,
  Pdf4D.Model.Rectangle;

{ TPDCIDFontType0 }

constructor TPDCIDFontType0.Create(const Dictionary: TCosDictionary; const Parent: TPDCIDFontParent);
begin
  inherited Create(Dictionary, Parent);
  LoadFontProgram;
end;

destructor TPDCIDFontType0.Destroy;
begin
  // A substitute is shared and belongs to the font mapper
  if FOwnsFontProgram then
  begin
    FCIDFont.Free;
    FType1Font.Free;
  end;
  inherited;
end;

procedure TPDCIDFontType0.LogError(const Fmt: string; const Args: array of const);
begin
  const Log = DocumentLog;
  if Assigned(Log) then
  begin
    Log.Error(Fmt, Args);
  end;
end;

procedure TPDCIDFontType0.LoadFontProgram;
begin
  if TryLoadEmbeddedFont then
  begin
    FIsEmbedded := True;
    FOwnsFontProgram := True;
    Exit;
  end;
  FindFontOrSubstitute;
end;

function TPDCIDFontType0.TryLoadEmbeddedFont: Boolean;
begin
  Result := False;
  var Descriptor: TPDFontDescriptor;
  var FontFile: TCosStream;
  if not (TryGetFontDescriptor(Descriptor) and Descriptor.TryGetFontFile3(FontFile)) then
  begin
    Exit;
  end;

  var Font: TCFFFont;
  if TryReadEmbeddedFont(FontFile, Font) then
  begin
    UseEmbeddedFont(Font);
    Result := True;
  end;
end;

function TPDCIDFontType0.TryReadEmbeddedFont(const FontFile: TCosStream; out Font: TCFFFont): Boolean;
begin
  Font := nil;
  try
    const Data = ReadStreamBytes(FontFile);
    // PDFBOX-2642 contains a corrupt PFB font instead of a CFF
    if (Length(Data) > 0) and (Data[0] = PfbStart) then
    begin
      LogWarning('Found PFB but expected embedded CFF font %s', [GetBaseFont]);
      FIsDamaged := True;
      Exit(False);
    end;

    const Parser = TCFFParser.Create(DocumentLog);
    try
      const Fonts = Parser.Parse(Data, 1);
      try
        if Fonts.Count = 0 then
        begin
          raise EPdfParseException.Create('The CFF data has no font');
        end;
        Font := Fonts.Extract(Fonts[0]);
      finally
        Fonts.Free;
      end;
    finally
      Parser.Free;
    end;
  except
    on Failure: Exception do
    begin
      if not IsRecoverableFailure(Failure) then
      begin
        raise;
      end;
      LogError('Can''t read the embedded CFF font %s: %s', [GetBaseFont, Failure.Message]);
      FIsDamaged := True;
      Exit(False);
    end;
  end;
  Result := True;
end;

procedure TPDCIDFontType0.UseEmbeddedFont(const Font: TCFFFont);
begin
  if Font is TCFFCIDFont then
  begin
    FCIDFont := TCFFCIDFont(Font);
  end
  else
  begin
    FType1Font := Font;
  end;
end;

procedure TPDCIDFontType0.FindFontOrSubstitute;
begin
  var Descriptor: TPDFontDescriptor;
  if not TryGetFontDescriptor(Descriptor) then
  begin
    Descriptor := nil;
  end;
  var Info: TPDCIDSystemInfo;
  const HasInfo = TryGetCIDSystemInfo(Info);

  const Mapping = TPdfFontMappers.Instance.GetCIDFont(GetBaseFont, Descriptor, HasInfo, Info);
  var Font: TFontBoxFont;
  if Mapping.IsCIDFont then
  begin
    UseMappedOpenTypeFont(Mapping.Font);
    Font := Mapping.Font;
  end
  else
  begin
    FType1Font := Mapping.TrueTypeFont;
    Font := FType1Font;
  end;

  if Mapping.IsFallback then
  begin
    LogWarning('Using fallback %s for CID-keyed font %s', [Font.Name, GetBaseFont]);
  end;
end;

procedure TPDCIDFontType0.UseMappedOpenTypeFont(const Font: TFontBoxFont);
begin
  if Font is TOpenTypeFont then
  begin
    try
      const CffFont = TOpenTypeFont(Font).CFF;
      if CffFont is TCFFCIDFont then
      begin
        FCIDFont := TCFFCIDFont(CffFont);
      end
      else
      begin
        // PDFBOX-3515: OpenType fonts are loaded as CFFType1Font
        FType1Font := CffFont;
      end;
      Exit;
    except
      on EPdfUnsupportedFeatureException do
      begin
        // PDFBox fails with an UnsupportedOperationException; an OpenType substitute with TrueType outlines is used as such
        FType1Font := Font;
        Exit;
      end;
    end;
  end;
  FType1Font := Font;
end;

function TPDCIDFontType0.TryGetProgramMatrix(out Numbers: TArray<Single>): Boolean;
begin
  Numbers := nil;
  try
    if Assigned(FCIDFont) then
    begin
      Numbers := FCIDFont.FontMatrix;
    end
    else
    begin
      Numbers := FType1Font.FontMatrix;
    end;
  except
    on EPdfException do
    begin
      // Couldn't get font matrix - returning default value
      Exit(False);
    end;
  end;
  Result := True;
end;

function TPDCIDFontType0.ReadFontMatrix: TPdfMatrix;
begin
  var Numbers: TArray<Single>;
  if TryGetProgramMatrix(Numbers) and (Length(Numbers) = 6) then
  begin
    Result := TPdfMatrix.Create(Numbers[0], Numbers[1], Numbers[2], Numbers[3], Numbers[4], Numbers[5]);
  end
  else
  begin
    Result := TPdfMatrix.Create(0.001, 0, 0, 0.001, 0, 0);
  end;
end;

function TPDCIDFontType0.GetFontMatrix: TPdfMatrix;
begin
  if not FHasFontMatrix then
  begin
    FFontMatrix := ReadFontMatrix;
    FHasFontMatrix := True;
  end;
  Result := FFontMatrix;
end;

function TPDCIDFontType0.TryGetProgramBoundingBox(out Box: TBoundingBox): Boolean;
begin
  Box := Default(TBoundingBox);
  try
    if Assigned(FCIDFont) then
    begin
      Box := FCIDFont.FontBBox;
    end
    else
    begin
      Box := FType1Font.FontBBox;
    end;
  except
    on EPdfException do
    begin
      // Couldn't get font bounding box - returning default value
      Exit(False);
    end;
  end;
  Result := True;
end;

function TPDCIDFontType0.GenerateBoundingBox: TBoundingBox;
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

  if not TryGetProgramBoundingBox(Result) then
  begin
    Result := Default(TBoundingBox);
  end;
end;

function TPDCIDFontType0.GetBoundingBox: TBoundingBox;
begin
  if not FHasBoundingBox then
  begin
    FBoundingBox := GenerateBoundingBox;
    FHasBoundingBox := True;
  end;
  Result := FBoundingBox;
end;

function TPDCIDFontType0.GetHeight(const Code: Integer): Single;
begin
  Result := GetBoundingBox.Height;
end;

function TPDCIDFontType0.GetAverageFontWidth: Single;
begin
  Result := AverageCharacterWidth;
end;

function TPDCIDFontType0.CodeToCID(const Code: Integer): Integer;
begin
  var CMap: TCMap;
  if Parent.TryGetCMap(CMap) then
  begin
    Result := CMap.ToCID(Code);
  end
  else
  begin
    // PDFBox fails with a NullPointerException; reading a code fails already
    Result := 0;
  end;
end;

function TPDCIDFontType0.CodeToGID(const Code: Integer): Integer;
begin
  const CID = CodeToCID(Code);
  if Assigned(FCIDFont) then
  begin
    // The CIDs shall be used to determine the GID value for the glyph procedure using the charset table in the CFF program
    Exit(FCIDFont.CIDToGID(CID));
  end;
  // The CIDs shall be used directly as GID values
  Result := CID;
end;

// The name of the glyph for a code, from the ToUnicode CMap of the parent: uniXXXX of its first code point
function TPDCIDFontType0.GetGlyphName(const Code: Integer): string;
begin
  var Unicode: string;
  if (not Parent.TryToUnicode(Code, Unicode)) or (Unicode = '') then
  begin
    Exit('.notdef');
  end;

  var CodePoint := Ord(Unicode[1]);
  const IsHighSurrogate = ((CodePoint >= $D800) and (CodePoint <= $DBFF));
  if IsHighSurrogate and (Length(Unicode) > 1) then
  begin
    const Low = Ord(Unicode[2]);
    if (Low >= $DC00) and (Low <= $DFFF) then
    begin
      CodePoint := $10000 + ((CodePoint - $D800) shl 10) + (Low - $DC00);
    end;
  end;
  Result := Format('uni%.4X', [CodePoint]);
end;

class function TPDCIDFontType0.ClampToGlyph(const CID: Integer): Integer;
begin
  // A negative CID has no charstring; PDFBox fails with an ArrayIndexOutOfBoundsException
  Result := Max(CID, 0);
end;

function TPDCIDFontType0.ReadGlyphWidth(const Code: Integer): Single;
begin
  const CID = CodeToCID(Code);
  if Assigned(FCIDFont) then
  begin
    Exit(FCIDFont.GetWidthForCID(ClampToGlyph(CID), DocumentLog));
  end;

  if FIsEmbedded and (FType1Font is TCFFType1Font) then
  begin
    Exit(TCFFType1Font(FType1Font).GetWidthForGID(ClampToGlyph(CID), DocumentLog));
  end;
  Result := FType1Font.GetWidth(GetGlyphName(Code));
end;

// The font matrix goes through an AffineTransform with the 1000 scale; Java calculates that in double. A font matrix or a width
// that cannot be scaled to a finite value gives no width, where PDFBox continues with an infinity or NaN.
function TPDCIDFontType0.ScaleToTextSpace(const Width: Single): Single;
begin
  if GetFontMatrix.TryScaleWidthToTextSpace(Width, Result) then
  begin
    Exit;
  end;

  if not FIsScaleWarningGiven then
  begin
    FIsScaleWarningGiven := True;
    LogWarning('The font matrix of %s gives a glyph width that is out of range', [GetBaseFont]);
  end;
  Result := 0;
end;

function TPDCIDFontType0.GetWidthFromFont(const Code: Integer): Single;
begin
  Result := ScaleToTextSpace(ReadGlyphWidth(Code));
end;

function TPDCIDFontType0.TryEncode(const CodePoint: Integer; out Bytes: TBytes): Boolean;
begin
  // todo in PDFBox: use a known character collection CMap for a CIDFont and an Encoding for Type 1-equivalent
  Bytes := nil;
  Result := False;
end;

function TPDCIDFontType0.IsEmbedded: Boolean;
begin
  Result := FIsEmbedded;
end;

function TPDCIDFontType0.IsDamaged: Boolean;
begin
  Result := FIsDamaged;
end;

function TPDCIDFontType0.GetCIDKeyedFont: TCFFCIDFont;
begin
  Result := FCIDFont;
end;

function TPDCIDFontType0.GetFontBoxFont: TFontBoxFont;
begin
  if Assigned(FCIDFont) then
  begin
    Result := FCIDFont;
  end
  else
  begin
    Result := FType1Font;
  end;
end;

end.
