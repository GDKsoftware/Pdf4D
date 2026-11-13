// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/font/FontMapperImpl.java (3.0.8)
unit Pdf4D.Font.MapperImpl;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.SharedInstance,
  Pdf4D.FontBox.FontBoxFont,
  Pdf4D.FontBox.TrueType.Font,
  Pdf4D.Font.Descriptor,
  Pdf4D.Font.Provider,
  Pdf4D.Font.Mapper;

type
  // Finds non-embedded fonts through a font provider. The provider is read when the first font is asked for. The fonts that
  // come out are shared: they belong to the provider's infos, or, for the last resort, to the process (LiberationSans,
  // parsed once). The mapper can be used from several threads, except for AddSubstitute, which is meant for right after
  // construction.
  TFontMapperImpl = class(TInterfacedObject, IPdfFontMapper)
  private
    type
      // The infos by lower case PostScript name, in the order in which the names were first added
      TFontIndex = class
      private
        FInfoByName: TDictionary<string, TFontInfo>;
        FNames: TList<string>;

      public
        constructor Create;
        destructor Destroy; override;

        procedure Add(const Name: string; const Info: TFontInfo);
        function TryGetInfo(const Name: string; out Info: TFontInfo): Boolean;

        property Names: TList<string> read FNames;
      end;

  private
    class var FLastResortFont: TPdfSharedInstance<TTrueTypeFont>;

    class destructor Destroy;
    class function CreateLastResortFont: TTrueTypeFont; static;
    class function PostScriptNamesOf(const PostScriptName: string): TArray<string>; static;
    class function NormalizeSubstituteKey(const PostScriptName: string): string; static;
    class function FallbackFontNameOf(const Descriptor: TPDFontDescriptor): string; static;
    class function IsBoldName(const FontName: string): Boolean; static;
    class function FixedPitchFallback(const Descriptor: TPDFontDescriptor; const IsBold: Boolean): string; static;
    class function SerifFallback(const Descriptor: TPDFontDescriptor; const IsBold: Boolean): string; static;
    class function SansSerifFallback(const Descriptor: TPDFontDescriptor; const IsBold: Boolean): string; static;
    class function CandidateNamesOf(const PostScriptName: string; const Substitutes: TArray<string>): TArray<string>; static;
    class function IsCharacterCollectionSubstitutable(const CIDSystemInfo: TPDCIDSystemInfo): Boolean; static;
    class function IsProbablyBarcodeFont(const Descriptor: TPDFontDescriptor): Boolean; static;
    class function IsCharSetMatch(const CIDSystemInfo: TPDCIDSystemInfo; const Info: TFontInfo): Boolean; static;
    class function PanoseScore(const Wanted, Actual: TPDPanoseClassification; const Info: TFontInfo): Double; static;
    class function SerifScore(const Wanted, Actual: TPDPanoseClassification): Double; static;
    class function WeightScore(const Wanted, Actual: TPDPanoseClassification; const Info: TFontInfo): Double; static;

  private
    FProvider: IPdfFontProvider;
    FIndex: TPdfSharedInstance<TFontIndex>;
    // Lower case PostScript name to the PostScript names of its substitutes, in priority order
    FSubstitutes: TDictionary<string, TArray<string>>;

    procedure AddStandardSubstitutes;
    procedure AddSubstitutes(const Match: string; const Replacements: TArray<string>);
    procedure AddAcrobatSubstitutes;
    function GetSubstitutes(const PostScriptName: string): TArray<string>;
    function CreateFontIndex: TFontIndex;
    function Index: TFontIndex;

    function TryFindFontInfo(const Format: TFontFormat; const PostScriptName: string; out Info: TFontInfo): Boolean;
    function TryGetFontInfo(const Format: TFontFormat; const PostScriptName: string; out Info: TFontInfo): Boolean;
    function TryFindFont(const Format: TFontFormat; const PostScriptName: string; out Font: TFontBoxFont): Boolean;
    function TryFindTrueTypeFont(const PostScriptName: string; out Font: TTrueTypeFont): Boolean;
    function TryFindOpenTypeFont(const PostScriptName: string; out Font: TFontBoxFont): Boolean;
    function TryFindFontBoxFont(const PostScriptName: string; out Font: TFontBoxFont): Boolean;

    function TryScoreFont(const Descriptor: TPDFontDescriptor; const CIDSystemInfo: TPDCIDSystemInfo; const Info: TFontInfo;
                          out Score: Double): Boolean;
    function TryFindBestMatch(const Descriptor: TPDFontDescriptor; const CIDSystemInfo: TPDCIDSystemInfo; out Info: TFontInfo): Boolean;
    function TryMapByCharacterCollection(const Descriptor: TPDFontDescriptor; const CIDSystemInfo: TPDCIDSystemInfo;
                                         out Mapping: TCIDFontMapping): Boolean;

  public
    constructor Create(const Provider: IPdfFontProvider);
    destructor Destroy; override;

    // Adds a substitute for the font with the given PostScript name, after the ones that are already there
    procedure AddSubstitute(const Match, Replace: string);

    function GetTrueTypeFont(const BaseFont: string; const Descriptor: TPDFontDescriptor): TFontMapping<TTrueTypeFont>;
    function GetFontBoxFont(const BaseFont: string; const Descriptor: TPDFontDescriptor): TFontMapping<TFontBoxFont>;
    function GetCIDFont(const BaseFont: string; const Descriptor: TPDFontDescriptor; const HasCIDSystemInfo: Boolean;
                        const CIDSystemInfo: TPDCIDSystemInfo): TCIDFontMapping;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.FontBox.OpenType,
  Pdf4D.FontBox.TrueType.Parser,
  Pdf4D.Resources.Fonts,
  Pdf4D.Font.Standard14;

const
  ChineseSimplified = Int64(1) shl 18;
  JisJapan = Int64(1) shl 17;
  KoreanWansung = Int64(1) shl 19;
  ChineseTraditional = Int64(1) shl 20;
  KoreanJohab = Int64(1) shl 21;
  MalgunGothicSemilight = 'MalgunGothic-Semilight';

{ TFontMapperImpl.TFontIndex }

constructor TFontMapperImpl.TFontIndex.Create;
begin
  inherited Create;
  FInfoByName := TDictionary<string, TFontInfo>.Create;
  FNames := TList<string>.Create;
end;

destructor TFontMapperImpl.TFontIndex.Destroy;
begin
  FNames.Free;
  FInfoByName.Free;
  inherited;
end;

procedure TFontMapperImpl.TFontIndex.Add(const Name: string; const Info: TFontInfo);
begin
  const IsNew = not FInfoByName.ContainsKey(Name);
  FInfoByName.AddOrSetValue(Name, Info);
  if IsNew then
  begin
    FNames.Add(Name);
  end;
end;

function TFontMapperImpl.TFontIndex.TryGetInfo(const Name: string; out Info: TFontInfo): Boolean;
begin
  Result := FInfoByName.TryGetValue(Name, Info);
end;

{ TFontMapperImpl }

class destructor TFontMapperImpl.Destroy;
begin
  FLastResortFont.Release;
end;

class function TFontMapperImpl.CreateLastResortFont: TTrueTypeFont;
begin
  const Parser = TTTFParser.Create;
  try
    Result := Parser.Parse(TPdfFontResources.LiberationSans);
  finally
    Parser.Free;
  end;
end;

constructor TFontMapperImpl.Create(const Provider: IPdfFontProvider);
begin
  inherited Create;
  if not Assigned(Provider) then
  begin
    raise EArgumentNilException.Create('The font mapper needs a font provider');
  end;

  FProvider := Provider;
  FSubstitutes := TDictionary<string, TArray<string>>.Create;
  AddStandardSubstitutes;
  AddAcrobatSubstitutes;
end;

destructor TFontMapperImpl.Destroy;
begin
  FIndex.Release;
  FSubstitutes.Free;
  inherited;
end;

procedure TFontMapperImpl.AddStandardSubstitutes;
begin
  AddSubstitutes('Courier', ['CourierNew', 'CourierNewPSMT', 'LiberationMono', 'NimbusMonL-Regu']);
  AddSubstitutes('Courier-Bold', ['CourierNewPS-BoldMT', 'CourierNew-Bold', 'LiberationMono-Bold', 'NimbusMonL-Bold']);
  AddSubstitutes('Courier-Oblique', ['CourierNewPS-ItalicMT', 'CourierNew-Italic', 'LiberationMono-Italic', 'NimbusMonL-ReguObli']);
  AddSubstitutes('Courier-BoldOblique', ['CourierNewPS-BoldItalicMT', 'CourierNew-BoldItalic', 'LiberationMono-BoldItalic',
                                         'NimbusMonL-BoldObli']);
  AddSubstitutes('Helvetica', ['ArialMT', 'Arial', 'LiberationSans', 'NimbusSanL-Regu']);
  AddSubstitutes('Helvetica-Bold', ['Arial-BoldMT', 'Arial-Bold', 'LiberationSans-Bold', 'NimbusSanL-Bold']);
  AddSubstitutes('Helvetica-Oblique', ['Arial-ItalicMT', 'Arial-Italic', 'Helvetica-Italic', 'LiberationSans-Italic',
                                       'NimbusSanL-ReguItal']);
  AddSubstitutes('Helvetica-BoldOblique', ['Arial-BoldItalicMT', 'Helvetica-BoldItalic', 'LiberationSans-BoldItalic',
                                           'NimbusSanL-BoldItal']);
  AddSubstitutes('Times-Roman', ['TimesNewRomanPSMT', 'TimesNewRoman', 'TimesNewRomanPS', 'LiberationSerif', 'NimbusRomNo9L-Regu']);
  AddSubstitutes('Times-Bold', ['TimesNewRomanPS-BoldMT', 'TimesNewRomanPS-Bold', 'TimesNewRoman-Bold', 'LiberationSerif-Bold',
                                'NimbusRomNo9L-Medi']);
  AddSubstitutes('Times-Italic', ['TimesNewRomanPS-ItalicMT', 'TimesNewRomanPS-Italic', 'TimesNewRoman-Italic',
                                  'LiberationSerif-Italic', 'NimbusRomNo9L-ReguItal']);
  AddSubstitutes('Times-BoldItalic', ['TimesNewRomanPS-BoldItalicMT', 'TimesNewRomanPS-BoldItalic', 'TimesNewRoman-BoldItalic',
                                      'LiberationSerif-BoldItalic', 'NimbusRomNo9L-MediItal']);
  AddSubstitutes('Symbol', ['Symbol', 'SymbolMT', 'StandardSymL']);
  AddSubstitutes('ZapfDingbats', ['ZapfDingbatsITCbyBT-Regular', 'ZapfDingbatsITC', 'Dingbats', 'MS-Gothic', 'DejaVuSans']);
end;

// Acrobat also uses other names for the standard 14 fonts, such as Arial and TimesNewRoman. They get the substitutes of the
// font that they stand for.
procedure TFontMapperImpl.AddAcrobatSubstitutes;
begin
  for var BaseName in TStandard14Fonts.Names do
  begin
    const HasSubstitutes = (Length(GetSubstitutes(BaseName)) > 0);
    if HasSubstitutes then
    begin
      Continue;
    end;

    var MappedName: TStandard14FontName;
    if TStandard14Fonts.TryGetMappedFontName(BaseName, MappedName) then
    begin
      AddSubstitutes(BaseName, Copy(GetSubstitutes(TStandard14Fonts.PostScriptName(MappedName))));
    end;
  end;
end;

class function TFontMapperImpl.NormalizeSubstituteKey(const PostScriptName: string): string;
begin
  Result := PostScriptName.Replace(' ', '').ToLowerInvariant;
end;

procedure TFontMapperImpl.AddSubstitutes(const Match: string; const Replacements: TArray<string>);
begin
  FSubstitutes.AddOrSetValue(Match.ToLowerInvariant, Replacements);
end;

procedure TFontMapperImpl.AddSubstitute(const Match, Replace: string);
begin
  const Key = Match.ToLowerInvariant;
  var Replacements: TArray<string>;
  FSubstitutes.TryGetValue(Key, Replacements);
  Replacements := Replacements + [Replace];
  FSubstitutes.AddOrSetValue(Key, Replacements);
end;

function TFontMapperImpl.GetSubstitutes(const PostScriptName: string): TArray<string>;
begin
  if not FSubstitutes.TryGetValue(NormalizeSubstituteKey(PostScriptName), Result) then
  begin
    Result := nil;
  end;
end;

class function TFontMapperImpl.PostScriptNamesOf(const PostScriptName: string): TArray<string>;
begin
  // The built-in PostScript name, and without hyphens (Arial-Black becomes ArialBlack)
  Result := [PostScriptName, PostScriptName.Replace('-', '')];
end;

function TFontMapperImpl.CreateFontIndex: TFontIndex;
begin
  Result := TFontIndex.Create;
  try
    for var Info in FProvider.FontInfos do
    begin
      if not Assigned(Info) then
      begin
        Continue;
      end;

      for var Name in PostScriptNamesOf(Info.PostScriptName) do
      begin
        Result.Add(Name.ToLowerInvariant, Info);
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TFontMapperImpl.Index: TFontIndex;
begin
  Result := FIndex.Get(CreateFontIndex);
end;

class function TFontMapperImpl.IsBoldName(const FontName: string): Boolean;
begin
  const Lower = FontName.ToLowerInvariant;
  Result := (Lower.Contains('bold') or Lower.Contains('black') or Lower.Contains('heavy'));
end;

class function TFontMapperImpl.FixedPitchFallback(const Descriptor: TPDFontDescriptor; const IsBold: Boolean): string;
begin
  const IsItalic = Descriptor.IsItalic;
  if IsBold and IsItalic then
  begin
    Result := 'Courier-BoldOblique';
  end
  else if IsBold then
  begin
    Result := 'Courier-Bold';
  end
  else if IsItalic then
  begin
    Result := 'Courier-Oblique';
  end
  else
  begin
    Result := 'Courier';
  end;
end;

class function TFontMapperImpl.SerifFallback(const Descriptor: TPDFontDescriptor; const IsBold: Boolean): string;
begin
  const IsItalic = Descriptor.IsItalic;
  if IsBold and IsItalic then
  begin
    Result := 'Times-BoldItalic';
  end
  else if IsBold then
  begin
    Result := 'Times-Bold';
  end
  else if IsItalic then
  begin
    Result := 'Times-Italic';
  end
  else
  begin
    Result := 'Times-Roman';
  end;
end;

class function TFontMapperImpl.SansSerifFallback(const Descriptor: TPDFontDescriptor; const IsBold: Boolean): string;
begin
  const IsItalic = Descriptor.IsItalic;
  if IsBold and IsItalic then
  begin
    Result := 'Helvetica-BoldOblique';
  end
  else if IsBold then
  begin
    Result := 'Helvetica-Bold';
  end
  else if IsItalic then
  begin
    Result := 'Helvetica-Oblique';
  end
  else
  begin
    Result := 'Helvetica';
  end;
end;

// The style flags of the descriptor say which of the standard fonts comes closest. Without a descriptor it is Times-Roman.
class function TFontMapperImpl.FallbackFontNameOf(const Descriptor: TPDFontDescriptor): string;
begin
  if not Assigned(Descriptor) then
  begin
    Exit('Times-Roman');
  end;

  const IsBold = IsBoldName(Descriptor.FontName);
  if Descriptor.IsFixedPitch then
  begin
    Result := FixedPitchFallback(Descriptor, IsBold);
  end
  else if Descriptor.IsSerif then
  begin
    Result := SerifFallback(Descriptor, IsBold);
  end
  else
  begin
    Result := SansSerifFallback(Descriptor, IsBold);
  end;
end;

// The names to try, in the order of PDFBox: the name itself, without hyphens, the named substitutes, the Windows form
// (ArialNarrow,Bold becomes ArialNarrow-Bold), the name without its style, and the name with -Regular
class function TFontMapperImpl.CandidateNamesOf(const PostScriptName: string; const Substitutes: TArray<string>): TArray<string>;
begin
  Result := [PostScriptName, PostScriptName.Replace('-', '')];
  Result := Result + Substitutes;
  Result := Result + [PostScriptName.Replace(',', '-')];

  var BaseName := PostScriptName;
  const CommaIndex = PostScriptName.IndexOf(',');
  if CommaIndex >= 0 then
  begin
    // PDFBOX-5806: cut the style and get the base font
    BaseName := PostScriptName.Substring(0, CommaIndex);
    Result := Result + [BaseName];
  end;

  // Works for Wingdings on Windows
  Result := Result + [BaseName + '-Regular'];
end;

function TFontMapperImpl.TryGetFontInfo(const Format: TFontFormat; const PostScriptName: string; out Info: TFontInfo): Boolean;
begin
  var Name := PostScriptName;
  // Strip the subset tag (happens when a corrupt embedded font is substituted, PDFBOX-2642)
  const PlusIndex = Name.IndexOf('+');
  if PlusIndex >= 0 then
  begin
    Name := Name.Substring(PlusIndex + 1);
  end;

  Result := (Index.TryGetInfo(Name.ToLowerInvariant, Info) and (Info.Format = Format));
end;

function TFontMapperImpl.TryFindFontInfo(const Format: TFontFormat; const PostScriptName: string; out Info: TFontInfo): Boolean;
begin
  for var Candidate in CandidateNamesOf(PostScriptName, GetSubstitutes(PostScriptName)) do
  begin
    if TryGetFontInfo(Format, Candidate, Info) then
    begin
      Exit(True);
    end;
  end;

  Info := nil;
  Result := False;
end;

// A font file that cannot be read counts as not found, like PDFBox, where FontInfo.getFont gives null
function TFontMapperImpl.TryFindFont(const Format: TFontFormat; const PostScriptName: string; out Font: TFontBoxFont): Boolean;
begin
  Font := nil;
  var Info: TFontInfo;
  if not TryFindFontInfo(Format, PostScriptName, Info) then
  begin
    Exit(False);
  end;

  try
    Font := Info.GetFont;
  except
    on EPdfException do
    begin
      Font := nil;
    end;
  end;
  Result := Assigned(Font);
end;

function TFontMapperImpl.TryFindTrueTypeFont(const PostScriptName: string; out Font: TTrueTypeFont): Boolean;
begin
  Font := nil;
  var Found: TFontBoxFont;
  const IsTrueType = (TryFindFont(TFontFormat.TTF, PostScriptName, Found) and (Found is TTrueTypeFont));
  if IsTrueType then
  begin
    Font := TTrueTypeFont(Found);
  end;
  Result := Assigned(Font);
end;

function TFontMapperImpl.TryFindOpenTypeFont(const PostScriptName: string; out Font: TFontBoxFont): Boolean;
begin
  Font := nil;
  var Found: TFontBoxFont;
  const IsOpenType = (TryFindFont(TFontFormat.OTF, PostScriptName, Found) and (Found is TOpenTypeFont));
  if IsOpenType then
  begin
    Font := Found;
  end;
  Result := Assigned(Font);
end;

function TFontMapperImpl.TryFindFontBoxFont(const PostScriptName: string; out Font: TFontBoxFont): Boolean;
begin
  Font := nil;
  var TrueTypeFont: TTrueTypeFont;
  if TryFindFont(TFontFormat.PFB, PostScriptName, Font) then
  begin
    Exit(True);
  end;

  if TryFindTrueTypeFont(PostScriptName, TrueTypeFont) then
  begin
    Font := TrueTypeFont;
    Exit(True);
  end;

  Result := TryFindOpenTypeFont(PostScriptName, Font);
end;

function TFontMapperImpl.GetTrueTypeFont(const BaseFont: string; const Descriptor: TPDFontDescriptor): TFontMapping<TTrueTypeFont>;
begin
  var Font: TTrueTypeFont;
  if TryFindTrueTypeFont(BaseFont, Font) then
  begin
    Result.Font := Font;
    Result.IsFallback := False;
    Exit;
  end;

  // Todo in PDFBox as well: a fuzzy match
  if not TryFindTrueTypeFont(FallbackFontNameOf(Descriptor), Font) then
  begin
    // Something has to be returned, as TrueType fonts are not required to be on the system
    Font := FLastResortFont.Get(CreateLastResortFont);
  end;
  Result.Font := Font;
  Result.IsFallback := True;
end;

function TFontMapperImpl.GetFontBoxFont(const BaseFont: string; const Descriptor: TPDFontDescriptor): TFontMapping<TFontBoxFont>;
begin
  var Font: TFontBoxFont;
  if TryFindFontBoxFont(BaseFont, Font) then
  begin
    Result.Font := Font;
    Result.IsFallback := False;
    Exit;
  end;

  if not TryFindFontBoxFont(FallbackFontNameOf(Descriptor), Font) then
  begin
    Font := FLastResortFont.Get(CreateLastResortFont);
  end;
  Result.Font := Font;
  Result.IsFallback := True;
end;

function TFontMapperImpl.GetCIDFont(const BaseFont: string; const Descriptor: TPDFontDescriptor; const HasCIDSystemInfo: Boolean;
                                    const CIDSystemInfo: TPDCIDSystemInfo): TCIDFontMapping;
begin
  Result := Default(TCIDFontMapping);

  // A name match or a substitute that is an OpenType font
  var OpenTypeFont: TFontBoxFont;
  if TryFindOpenTypeFont(BaseFont, OpenTypeFont) then
  begin
    Result.Font := OpenTypeFont;
    Exit;
  end;

  // A name match or a substitute that is a TrueType font
  var TrueTypeFont: TTrueTypeFont;
  if TryFindTrueTypeFont(BaseFont, TrueTypeFont) then
  begin
    Result.TrueTypeFont := TrueTypeFont;
    Exit;
  end;

  const CanMatchCharacterCollection = (HasCIDSystemInfo and Assigned(Descriptor));
  if CanMatchCharacterCollection and TryMapByCharacterCollection(Descriptor, CIDSystemInfo, Result) then
  begin
    Exit;
  end;

  Result.TrueTypeFont := FLastResortFont.Get(CreateLastResortFont);
  Result.IsFallback := True;
end;

// "In Acrobat 3.0.1 and later, Type 0 fonts that use a CMap whose CIDSystemInfo dictionary defines the Adobe-GB1, Adobe-CNS1
// Adobe-Japan1, or Adobe-Korea1 character collection can also be substituted." (Adobe Supplement to the ISO 32000)
class function TFontMapperImpl.IsCharacterCollectionSubstitutable(const CIDSystemInfo: TPDCIDSystemInfo): Boolean;
begin
  const Collection = CIDSystemInfo.Registry + '-' + CIDSystemInfo.Ordering;
  Result := ((Collection = 'Adobe-GB1') or (Collection = 'Adobe-CNS1') or (Collection = 'Adobe-Japan1') or (Collection = 'Adobe-Korea1'));
end;

function TFontMapperImpl.TryMapByCharacterCollection(const Descriptor: TPDFontDescriptor; const CIDSystemInfo: TPDCIDSystemInfo;
                                                     out Mapping: TCIDFontMapping): Boolean;
begin
  Mapping := Default(TCIDFontMapping);
  Result := False;
  if not IsCharacterCollectionSubstitutable(CIDSystemInfo) then
  begin
    Exit;
  end;

  var BestInfo: TFontInfo;
  if not TryFindBestMatch(Descriptor, CIDSystemInfo, BestInfo) then
  begin
    Exit;
  end;

  var Font: TFontBoxFont;
  try
    Font := BestInfo.GetFont;
  except
    on EPdfException do
    begin
      Font := nil;
    end;
  end;

  if Font is TOpenTypeFont then
  begin
    Mapping.Font := Font;
    Mapping.IsFallback := True;
    Result := True;
  end
  else if Font is TTrueTypeFont then
  begin
    Mapping.TrueTypeFont := TTrueTypeFont(Font);
    Mapping.IsFallback := True;
    Result := True;
  end;
end;

// The best match is the first font with the highest score, as the PriorityQueue of PDFBox gives it
function TFontMapperImpl.TryFindBestMatch(const Descriptor: TPDFontDescriptor; const CIDSystemInfo: TPDCIDSystemInfo;
                                          out Info: TFontInfo): Boolean;
begin
  Info := nil;
  var BestScore: Double := 0;
  const FontIndex = Index;
  for var Name in FontIndex.Names do
  begin
    var Candidate: TFontInfo := nil;
    var Score: Double := 0;
    const IsScored = (FontIndex.TryGetInfo(Name, Candidate) and TryScoreFont(Descriptor, CIDSystemInfo, Candidate, Score));
    if IsScored and ((not Assigned(Info)) or (Score > BestScore)) then
    begin
      Info := Candidate;
      BestScore := Score;
    end;
  end;
  Result := Assigned(Info);
end;

// Positive scores indicate matches for certain attributes, negative scores mismatches. False when the font is left out.
function TFontMapperImpl.TryScoreFont(const Descriptor: TPDFontDescriptor; const CIDSystemInfo: TPDCIDSystemInfo;
                                      const Info: TFontInfo; out Score: Double): Boolean;
begin
  Score := 0;
  Result := IsCharSetMatch(CIDSystemInfo, Info);
  if not Result then
  begin
    Exit;
  end;

  var WantedPanose: TPDPanose;
  var ActualPanose: TPDPanoseClassification;
  const HasPanose = (Descriptor.TryGetPanose(WantedPanose) and Info.TryGetPanose(ActualPanose));
  if HasPanose then
  begin
    const Wanted = WantedPanose.Panose;
    if Wanted.FamilyKind <> ActualPanose.FamilyKind then
    begin
      Exit;
    end;

    const IsBarcodeFont = ((Info.PostScriptName.ToLowerInvariant.Contains('barcode')) or Info.PostScriptName.StartsWith('Code'));
    if (Wanted.FamilyKind = 0) and IsBarcodeFont and not IsProbablyBarcodeFont(Descriptor) then
    begin
      // PDFBOX-4268: ignore a barcode font when none is searched for
      Exit(False);
    end;

    Score := PanoseScore(Wanted, ActualPanose, Info);
  end
  else if (Descriptor.FontWeight > 0) and (Info.WeightClass > 0) then
  begin
    // usWeightClass is pretty reliable
    const Distance = Single(Abs(Descriptor.FontWeight - Info.WeightClass));
    Score := 1 - Single(Distance / 100) * 0.5;
  end;
end;

class function TFontMapperImpl.PanoseScore(const Wanted, Actual: TPDPanoseClassification; const Info: TFontInfo): Double;
begin
  Result := SerifScore(Wanted, Actual) + WeightScore(Wanted, Actual, Info);
end;

class function TFontMapperImpl.SerifScore(const Wanted, Actual: TPDPanoseClassification): Double;
begin
  const WantedStyle = Wanted.SerifStyle;
  const ActualStyle = Actual.SerifStyle;
  const AreBothCove = ((WantedStyle >= 2) and (WantedStyle <= 5) and (ActualStyle >= 2) and (ActualStyle <= 5));
  const AreBothSansSerif = ((WantedStyle >= 11) and (WantedStyle <= 13) and (ActualStyle >= 11) and (ActualStyle <= 13));
  const AreBothKnown = ((WantedStyle <> 0) and (ActualStyle <> 0));
  if WantedStyle = ActualStyle then
  begin
    Result := 2;
  end
  else if AreBothCove or AreBothSansSerif then
  begin
    Result := 1;
  end
  else if AreBothKnown then
  begin
    Result := -1;
  end
  else
  begin
    Result := 0;
  end;
end;

class function TFontMapperImpl.WeightScore(const Wanted, Actual: TPDPanoseClassification; const Info: TFontInfo): Double;
begin
  var Weight := Actual.Weight;
  const WeightClass = Info.WeightClassAsPanose;
  if Abs(Weight - WeightClass) > 2 then
  begin
    // Inconsistent data in a system font: usWeightClass wins
    Weight := WeightClass;
  end;

  if Wanted.Weight = Weight then
  begin
    Result := 2;
  end
  else if (Wanted.Weight > 1) and (Weight > 1) then
  begin
    const Distance = Single(Abs(Wanted.Weight - Weight));
    Result := 1 - Distance * 0.5;
  end
  else
  begin
    Result := 0;
  end;
end;

class function TFontMapperImpl.IsProbablyBarcodeFont(const Descriptor: TPDFontDescriptor): Boolean;
begin
  const Family = Descriptor.FontFamily;
  const Name = Descriptor.FontName;
  Result := (Family.StartsWith('Code') or Family.ToLowerInvariant.Contains('barcode') or
             Name.StartsWith('Code') or Name.ToLowerInvariant.Contains('barcode'));
end;

// True when the character set of the CIDSystemInfo is in the font. Only for Adobe-GB1, Adobe-CNS1, Adobe-Japan1 and
// Adobe-Korea1, as in the PDF specification.
class function TFontMapperImpl.IsCharSetMatch(const CIDSystemInfo: TPDCIDSystemInfo; const Info: TFontInfo): Boolean;
begin
  const Ordering = CIDSystemInfo.Ordering;
  if Ordering = '' then
  begin
    Exit(False);
  end;

  var FontSystemInfo: TPDCIDSystemInfo;
  if Info.TryGetCIDSystemInfo(FontSystemInfo) then
  begin
    Exit((FontSystemInfo.Registry = CIDSystemInfo.Registry) and (FontSystemInfo.Ordering = Ordering));
  end;

  var CodePageRange := Info.CodePageRange;
  if Info.PostScriptName = MalgunGothicSemilight then
  begin
    // PDFBOX-4793 and PDF.js 10699: this font has only Korean, but has bits 17-21 set
    CodePageRange := CodePageRange and not (JisJapan or ChineseSimplified or ChineseTraditional);
  end;

  if Ordering = 'GB1' then
  begin
    Result := ((CodePageRange and ChineseSimplified) = ChineseSimplified);
  end
  else if Ordering = 'CNS1' then
  begin
    Result := ((CodePageRange and ChineseTraditional) = ChineseTraditional);
  end
  else if Ordering = 'Japan1' then
  begin
    Result := ((CodePageRange and JisJapan) = JisJapan);
  end
  else
  begin
    Result := ((Ordering = 'Korea1') and (((CodePageRange and KoreanWansung) = KoreanWansung) or
                                          ((CodePageRange and KoreanJohab) = KoreanJohab)));
  end;
end;

end.
