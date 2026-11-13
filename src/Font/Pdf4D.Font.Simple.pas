// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/font/PDSimpleFont.java (3.0.8)
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/font/UniUtil.java (3.0.8)
unit Pdf4D.Font.Simple;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.Log,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Font.Base,
  Pdf4D.Font.Encoding,
  Pdf4D.Font.GlyphList,
  Pdf4D.FontBox.FontBoxFont,
  Pdf4D.Model.DocumentContext,
  Pdf4D.Model.Rectangle;

type
  // A font with one byte codes: Type 1, MMType1, TrueType. The subclasses read the font program; this class has the
  // encoding and the Unicode mapping through the glyph list.
  TPDSimpleFont = class abstract(TPDFont)
  private
    FEncoding: TPdfEncoding;
    FOwnedEncodings: TObjectList<TPdfEncoding>;
    FGlyphList: TGlyphList;
    FHasSymbolic: Boolean;
    FIsSymbolic: Boolean;
    FNoUnicode: TList<Integer>;

    procedure ReadEncodingFromName(const EncodingName: string);
    procedure ReadEncodingFromDictionary(const EncodingDictionary: TCosDictionary);
    function HasValidBaseEncoding(const EncodingDictionary: TCosDictionary): Boolean;
    procedure AssignGlyphList(const IsZapfDingbats: Boolean);
    procedure AssignGlyphListOfName;
    function TryIsFontSymbolic(out Symbolic: Boolean): Boolean;
    function DifferencesAreLatin(const Dictionary: TDictionaryEncoding): Boolean;
    function SelectGlyphList(const CustomGlyphList: TGlyphList): TGlyphList;
    function TryEncodingToUnicode(const Code: Integer; const UnicodeGlyphList: TGlyphList; out Value: string): Boolean;
    procedure WarnAboutMissingUnicode(const Code: Integer; const GlyphName: string; const HasGlyphName: Boolean);

  protected
    // PDSimpleFont.readEncoding. The subclass calls it when the font program is known.
    procedure ReadEncoding; virtual;
    // A new encoding from the font program or the AFM. The subclass has to Adopt it when it is not shared.
    function ReadEncodingFromFont: TPdfEncoding; virtual; abstract;
    // The font owns Encoding from now on, and returns it
    function AdoptEncoding(const Encoding: TPdfEncoding): TPdfEncoding;

    // PDSimpleFont.getSymbolicFlag: the flag of the descriptor. False when there is no descriptor.
    function TryGetSymbolicFlag(out Symbolic: Boolean): Boolean;
    function GetStandard14Width(const Code: Integer): Single; override;
    // The log of the document, or nil
    function DocumentLog: TPdfLog;
    // The bytes of a font file stream, decoded. Raises an EPdfException when it cannot be decoded.
    function ReadStreamBytes(const Stream: TCosStream): TBytes;
    // True for the failures that a damaged font file can cause: they are logged and the font falls back
    class function IsRecoverableFailure(const Failure: Exception): Boolean; static;
    class function IsNonZeroBoundingBox(const Box: TPdfRectangle): Boolean; static;
    // UniUtil.getUniNameOfCodePoint
    class function GetUniNameOfCodePoint(const CodePoint: Integer): string; static;

  public
    constructor Create(const Dictionary: TCosDictionary; const Context: TPDDocumentContext);
    destructor Destroy; override;

    // The encoding, or False when the font has none
    function TryGetEncoding(out Encoding: TPdfEncoding): Boolean;
    function GlyphList: TGlyphList;
    // PDSimpleFont.isSymbolic: a font is symbolic unless it is proven not to be
    function IsSymbolic: Boolean;

    function ReadCode(const Data: TBytes; var Position: Integer): Integer; override;
    function IsVertical: Boolean; override;
    function IsStandard14: Boolean; override;
    // The glyph name of the encoding, or .notdef
    function CodeToName(const Code: Integer): string; virtual;

    // ToUnicode first, then the glyph name of the code through the glyph list. False when there is no Unicode for the code;
    // the text engine then uses the code itself, as LegacyPDFStreamEngine does for a simple font.
    function TryToUnicode(const Code: Integer; out Value: string): Boolean; overload; override;
    function TryToUnicode(const Code: Integer; const CustomGlyphList: TGlyphList; out Value: string): Boolean; overload; override;

    // The font program (embedded, or shared from the font mapper). The font does not own a shared one.
    function GetFontBoxFont: TFontBoxFont; virtual; abstract;
  end;

implementation

uses
  System.Classes,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Font.Descriptor,
  Pdf4D.Font.Encoding.Tables,
  Pdf4D.Font.Standard14,
  Pdf4D.FontBox.Afm;

const
  NotDefName = '.notdef';
  ZapfDingbatsName = 'ZapfDingbats';
  FallbackNotDefWidth = 250;

{ TPDSimpleFont }

constructor TPDSimpleFont.Create(const Dictionary: TCosDictionary; const Context: TPDDocumentContext);
begin
  inherited Create(Dictionary, Context);
  FOwnedEncodings := TObjectList<TPdfEncoding>.Create(True);
  FNoUnicode := TList<Integer>.Create;
end;

destructor TPDSimpleFont.Destroy;
begin
  FNoUnicode.Free;
  FOwnedEncodings.Free;
  inherited;
end;

function TPDSimpleFont.AdoptEncoding(const Encoding: TPdfEncoding): TPdfEncoding;
begin
  FOwnedEncodings.Add(Encoding);
  Result := Encoding;
end;

procedure TPDSimpleFont.ReadEncoding;
begin
  var EncodingEntry: TCosBase;
  if not CosObject.TryGetDictionaryObject(TCosNames.Encoding, EncodingEntry) then
  begin
    FEncoding := ReadEncodingFromFont;
  end
  else if EncodingEntry is TCosName then
  begin
    ReadEncodingFromName(TCosName(EncodingEntry).Name);
  end
  else if EncodingEntry is TCosDictionary then
  begin
    ReadEncodingFromDictionary(TCosDictionary(EncodingEntry));
  end
  else
  begin
    FEncoding := ReadEncodingFromFont;
  end;

  // Normalise the standard 14 name, for instance Symbol,Italic gives Symbol
  AssignGlyphListOfName;
end;

procedure TPDSimpleFont.ReadEncodingFromName(const EncodingName: string);
begin
  if (Name = ZapfDingbatsName) and (not IsEmbedded) then
  begin
    // PDFBOX- and PDF.js issue 16464: ignore other encodings
    FEncoding := TZapfDingbatsEncoding.Instance;
    Exit;
  end;

  if not TPdfEncoding.TryGetInstance(EncodingName, FEncoding) then
  begin
    LogWarning('Unknown encoding: %s', [EncodingName]);
    FEncoding := ReadEncodingFromFont;
  end;
end;

function TPDSimpleFont.HasValidBaseEncoding(const EncodingDictionary: TCosDictionary): Boolean;
begin
  var BaseEncoding: TPdfEncoding;
  Result := TPdfEncoding.TryGetInstance(EncodingDictionary.GetNameAsString(TCosNames.BaseEncoding, ''), BaseEncoding);
end;

procedure TPDSimpleFont.ReadEncodingFromDictionary(const EncodingDictionary: TCosDictionary);
begin
  var BuiltIn: TPdfEncoding := nil;
  var Symbolic: Boolean;
  const HasFlag = TryGetSymbolicFlag(Symbolic);
  if (not HasValidBaseEncoding(EncodingDictionary)) and HasFlag and Symbolic then
  begin
    BuiltIn := ReadEncodingFromFont;
  end;

  // A font without a descriptor counts as non-symbolic here
  const IsNonSymbolic = (not (HasFlag and Symbolic));
  FEncoding := AdoptEncoding(TDictionaryEncoding.Create(EncodingDictionary, IsNonSymbolic, BuiltIn));
end;

procedure TPDSimpleFont.AssignGlyphListOfName;
begin
  var StandardName: TStandard14FontName;
  const IsZapfDingbats = (TStandard14Fonts.TryGetMappedFontName(Name, StandardName) and (StandardName = TStandard14FontName.ZapfDingbats));
  AssignGlyphList(IsZapfDingbats);
end;

procedure TPDSimpleFont.AssignGlyphList(const IsZapfDingbats: Boolean);
begin
  if IsZapfDingbats then
  begin
    FGlyphList := TGlyphList.ZapfDingbats;
  end
  else
  begin
    FGlyphList := TGlyphList.AdobeGlyphList;
  end;
end;

function TPDSimpleFont.TryGetEncoding(out Encoding: TPdfEncoding): Boolean;
begin
  Encoding := FEncoding;
  Result := Assigned(FEncoding);
end;

function TPDSimpleFont.GlyphList: TGlyphList;
begin
  // A font without a read encoding still needs a list for TryToUnicode
  if not Assigned(FGlyphList) then
  begin
    AssignGlyphListOfName;
  end;
  Result := FGlyphList;
end;

function TPDSimpleFont.TryGetSymbolicFlag(out Symbolic: Boolean): Boolean;
begin
  var Descriptor: TPDFontDescriptor;
  Result := TryGetFontDescriptor(Descriptor);
  // The flag defaults to False when it is missing, so it cannot be trusted
  Symbolic := (Result and Descriptor.IsSymbolic);
end;

function TPDSimpleFont.IsSymbolic: Boolean;
begin
  if not FHasSymbolic then
  begin
    var Symbolic: Boolean;
    if TryIsFontSymbolic(Symbolic) then
    begin
      FIsSymbolic := Symbolic;
    end
    else
    begin
      // Unless we can prove that the font is non-symbolic, we assume that it is not
      FIsSymbolic := True;
    end;
    FHasSymbolic := True;
  end;
  Result := FIsSymbolic;
end;

function TPDSimpleFont.TryIsFontSymbolic(out Symbolic: Boolean): Boolean;
begin
  Symbolic := False;
  if TryGetSymbolicFlag(Symbolic) then
  begin
    Exit(True);
  end;

  if IsStandard14 then
  begin
    var StandardName: TStandard14FontName;
    Symbolic := (TStandard14Fonts.TryGetMappedFontName(Name, StandardName) and
                 ((StandardName = TStandard14FontName.Symbol) or (StandardName = TStandard14FontName.ZapfDingbats)));
    Exit(True);
  end;

  if not Assigned(FEncoding) then
  begin
    Exit(False);
  end;

  if (FEncoding is TWinAnsiEncoding) or (FEncoding is TMacRomanEncoding) or (FEncoding is TStandardEncoding) then
  begin
    Symbolic := False;
    Exit(True);
  end;

  if FEncoding is TDictionaryEncoding then
  begin
    Symbolic := (not DifferencesAreLatin(TDictionaryEncoding(FEncoding)));
    Exit(True);
  end;

  // We don't know
  Result := False;
end;

function TPDSimpleFont.DifferencesAreLatin(const Dictionary: TDictionaryEncoding): Boolean;
begin
  // Each name in the Differences array must also be in the latin character set
  for var GlyphName in Dictionary.Differences.Values do
  begin
    if GlyphName = NotDefName then
    begin
      Continue;
    end;

    const InAllLatinEncodings = (TWinAnsiEncoding.Instance.Contains(GlyphName) and TMacRomanEncoding.Instance.Contains(GlyphName) and
                                 TStandardEncoding.Instance.Contains(GlyphName));
    if not InAllLatinEncodings then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

function TPDSimpleFont.ReadCode(const Data: TBytes; var Position: Integer): Integer;
begin
  // The end of the data gives -1, like InputStream.read
  if (Position < 0) or (Position >= Length(Data)) then
  begin
    Exit(-1);
  end;

  Result := Data[Position];
  Inc(Position);
end;

function TPDSimpleFont.IsVertical: Boolean;
begin
  Result := False;
end;

function TPDSimpleFont.CodeToName(const Code: Integer): string;
begin
  if Assigned(FEncoding) then
  begin
    Result := FEncoding.GetName(Code);
  end
  else
  begin
    Result := NotDefName;
  end;
end;

function TPDSimpleFont.GetStandard14Width(const Code: Integer): Single;
begin
  var Metrics: TFontMetrics;
  if not TryGetStandardAFM(Metrics) then
  begin
    raise EPdfException.Create('No AFM');
  end;

  var NameInAFM := FEncoding.GetName(Code);
  // The Adobe AFMs don't include .notdef, but Acrobat uses 250, test with PDFBOX-2334
  if NameInAFM = NotDefName then
  begin
    Exit(FallbackNotDefWidth);
  end;

  if NameInAFM = 'nbspace' then
  begin
    // PDFBOX-4944: nbspace is missing in AFM files, but it shall be typographically the same as space
    NameInAFM := 'space';
  end
  else if NameInAFM = 'sfthyphen' then
  begin
    // PDFBOX-5115: sfthyphen is missing in AFM files, but it shall be typographically the same as hyphen
    NameInAFM := 'hyphen';
  end;
  Result := Metrics.GetCharacterWidth(NameInAFM);
end;

function TPDSimpleFont.IsStandard14: Boolean;
begin
  // This logic is based on Acrobat's behaviour, see PDFBOX-2372: the Encoding entry cannot have Differences if we want
  // standard 14 font handling
  if FEncoding is TDictionaryEncoding then
  begin
    const DictionaryEncoding = TDictionaryEncoding(FEncoding);
    const BaseEncoding = DictionaryEncoding.BaseEncoding;
    for var Difference in DictionaryEncoding.Differences do
    begin
      // The differences have to be actually different, see PDFBOX-1900 with the file from PDFBOX-2192 on Windows
      if (not Assigned(BaseEncoding)) or (Difference.Value <> BaseEncoding.GetName(Difference.Key)) then
      begin
        Exit(False);
      end;
    end;
  end;
  Result := inherited IsStandard14;
end;

function TPDSimpleFont.SelectGlyphList(const CustomGlyphList: TGlyphList): TGlyphList;
begin
  // The glyph list can be overridden for the purpose of extracting Unicode. This is only done when the glyph list of the
  // font is the AGL, to avoid breaking Zapf Dingbats.
  if (GlyphList = TGlyphList.AdobeGlyphList) and Assigned(CustomGlyphList) then
  begin
    Result := CustomGlyphList;
  end
  else
  begin
    Result := GlyphList;
  end;
end;

function TPDSimpleFont.TryToUnicode(const Code: Integer; out Value: string): Boolean;
begin
  Result := TryToUnicode(Code, TGlyphList.AdobeGlyphList, Value);
end;

function TPDSimpleFont.TryToUnicode(const Code: Integer; const CustomGlyphList: TGlyphList; out Value: string): Boolean;
begin
  // First try to use a ToUnicode CMap
  if inherited TryToUnicode(Code, Value) then
  begin
    Exit(True);
  end;

  // A simple font that uses MacRoman/MacExpert/WinAnsi[Encoding] or has Differences with names from only Adobe Standard
  // and/or Symbol: map the code to a name and look the name up in the glyph list
  var GlyphName := '';
  if Assigned(FEncoding) then
  begin
    GlyphName := FEncoding.GetName(Code);
    if TryEncodingToUnicode(Code, SelectGlyphList(CustomGlyphList), Value) then
    begin
      Exit(True);
    end;
  end;

  // If no value has been produced, there is no way to obtain Unicode for the character
  WarnAboutMissingUnicode(Code, GlyphName, Assigned(FEncoding));
  Value := '';
  Result := False;
end;

function TPDSimpleFont.TryEncodingToUnicode(const Code: Integer; const UnicodeGlyphList: TGlyphList; out Value: string): Boolean;
begin
  Result := UnicodeGlyphList.TryToUnicode(FEncoding.GetName(Code), DocumentLog, Value);
end;

procedure TPDSimpleFont.WarnAboutMissingUnicode(const Code: Integer; const GlyphName: string; const HasGlyphName: Boolean);
begin
  // The warnings that have been given are kept, so a code is only logged once
  if FNoUnicode.Contains(Code) then
  begin
    Exit;
  end;
  FNoUnicode.Add(Code);

  if HasGlyphName then
  begin
    LogWarning('No Unicode mapping for %s (%d) in font %s', [GlyphName, Code, Name]);
  end
  else
  begin
    LogWarning('No Unicode mapping for character code %d in font %s', [Code, Name]);
  end;
end;

function TPDSimpleFont.DocumentLog: TPdfLog;
begin
  Result := nil;
  if Assigned(Context) then
  begin
    Result := Context.Log;
  end;
end;

function TPDSimpleFont.ReadStreamBytes(const Stream: TCosStream): TBytes;
begin
  const Decoded = Stream.CreateDecodedStream;
  try
    if Decoded.Size > MaxInt then
    begin
      raise EPdfLimitExceededException.Create('The font file is too large');
    end;
    SetLength(Result, Decoded.Size);
    Decoded.Position := 0;
    if Length(Result) > 0 then
    begin
      Decoded.ReadBuffer(Result, Length(Result));
    end;
  finally
    Decoded.Free;
  end;
end;

class function TPDSimpleFont.IsRecoverableFailure(const Failure: Exception): Boolean;
begin
  Result := ((Failure is EPdfException) or TPdfFailure.IsInputFailure(Failure));
end;

class function TPDSimpleFont.IsNonZeroBoundingBox(const Box: TPdfRectangle): Boolean;
begin
  Result := ((Box.LowerLeftX <> 0) or (Box.LowerLeftY <> 0) or (Box.UpperRightX <> 0) or (Box.UpperRightY <> 0));
end;

class function TPDSimpleFont.GetUniNameOfCodePoint(const CodePoint: Integer): string;
begin
  Result := 'uni' + IntToHex(CodePoint, 4);
end;

end.
