// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/font/Standard14Fonts.java (3.0.8), the names and the metrics
unit Pdf4D.Font.Standard14;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.SharedInstance,
  Pdf4D.FontBox.Afm;

type
  {$SCOPEDENUMS ON}
  TStandard14FontName = (TimesRoman, TimesBold, TimesItalic, TimesBoldItalic, Helvetica, HelveticaBold, HelveticaOblique,
                         HelveticaBoldOblique, Courier, CourierBold, CourierOblique, CourierBoldOblique, Symbol, ZapfDingbats);
  {$SCOPEDENUMS OFF}

  // The names and the metrics (AFM) of the standard 14 fonts. The AFM of a font is parsed on first use and shared by
  // all threads and documents; it does not change afterwards.
  TStandard14Fonts = class
  private
    class var FAliases: TPdfSharedInstance<TDictionary<string, TStandard14FontName>>;
    class var FMetrics: TPdfSharedInstance<TPdfSharedCache<TStandard14FontName, TFontMetrics>>;

    class destructor Destroy;

    class function CreateAliases: TDictionary<string, TStandard14FontName>; static;
    class function CreateMetricsCache: TPdfSharedCache<TStandard14FontName, TFontMetrics>; static;
    // Not const: the signature has to be the one of TFunc<TStandard14FontName, TFontMetrics>
    class function LoadMetrics(FontName: TStandard14FontName): TFontMetrics; static;
    class procedure AddStandardNames(const Aliases: TDictionary<string, TStandard14FontName>); static;
    class procedure AddAdobeSupplementNames(const Aliases: TDictionary<string, TStandard14FontName>); static;
    class procedure AddAcrobatNames(const Aliases: TDictionary<string, TStandard14FontName>); static;

  public
    // The 14 names and all their aliases
    class function Names: TArray<string>; static;
    // True for the 14 names and all their aliases
    class function ContainsName(const Name: string): Boolean; static;
    // The standard font behind a name or alias
    class function TryGetMappedFontName(const Name: string; out FontName: TStandard14FontName): Boolean; static;
    // The PostScript name, for example Helvetica-BoldOblique
    class function PostScriptName(const FontName: TStandard14FontName): string; static;
    // The shared metrics (without kerning and composites, as PDFBox loads them); the caller does not own them. False
    // when the name is not a standard 14 name or alias.
    class function TryGetAFM(const Name: string; out Metrics: TFontMetrics): Boolean; static;
  end;

implementation

uses
  Pdf4D.FontBox.AfmParser,
  Pdf4D.Resources.Afm;

{ TStandard14Fonts }

class destructor TStandard14Fonts.Destroy;
begin
  FMetrics.Release;
  FAliases.Release;
end;

class function TStandard14Fonts.CreateAliases: TDictionary<string, TStandard14FontName>;
begin
  Result := TDictionary<string, TStandard14FontName>.Create;
  try
    AddStandardNames(Result);
    AddAdobeSupplementNames(Result);
    AddAcrobatNames(Result);
  except
    Result.Free;
    raise;
  end;
end;

class procedure TStandard14Fonts.AddStandardNames(const Aliases: TDictionary<string, TStandard14FontName>);
begin
  for var FontName := Low(TStandard14FontName) to High(TStandard14FontName) do
  begin
    Aliases.AddOrSetValue(PostScriptName(FontName), FontName);
  end;
end;

// Alternative names from the Adobe Supplement to ISO 32000
class procedure TStandard14Fonts.AddAdobeSupplementNames(const Aliases: TDictionary<string, TStandard14FontName>);
begin
  Aliases.AddOrSetValue('CourierCourierNew', TStandard14FontName.Courier);
  Aliases.AddOrSetValue('CourierNew', TStandard14FontName.Courier);
  Aliases.AddOrSetValue('CourierNew,Italic', TStandard14FontName.CourierOblique);
  Aliases.AddOrSetValue('CourierNew,Bold', TStandard14FontName.CourierBold);
  Aliases.AddOrSetValue('CourierNew,BoldItalic', TStandard14FontName.CourierBoldOblique);
  Aliases.AddOrSetValue('Arial', TStandard14FontName.Helvetica);
  Aliases.AddOrSetValue('Arial,Italic', TStandard14FontName.HelveticaOblique);
  Aliases.AddOrSetValue('Arial,Bold', TStandard14FontName.HelveticaBold);
  Aliases.AddOrSetValue('Arial,BoldItalic', TStandard14FontName.HelveticaBoldOblique);
  Aliases.AddOrSetValue('TimesNewRoman', TStandard14FontName.TimesRoman);
  Aliases.AddOrSetValue('TimesNewRoman,Italic', TStandard14FontName.TimesItalic);
  Aliases.AddOrSetValue('TimesNewRoman,Bold', TStandard14FontName.TimesBold);
  Aliases.AddOrSetValue('TimesNewRoman,BoldItalic', TStandard14FontName.TimesBoldItalic);
end;

// Acrobat treats these as standard 14 fonts too, and PDFBOX-3457 adds the MT names
class procedure TStandard14Fonts.AddAcrobatNames(const Aliases: TDictionary<string, TStandard14FontName>);
begin
  Aliases.AddOrSetValue('Symbol,Italic', TStandard14FontName.Symbol);
  Aliases.AddOrSetValue('Symbol,Bold', TStandard14FontName.Symbol);
  Aliases.AddOrSetValue('Symbol,BoldItalic', TStandard14FontName.Symbol);
  Aliases.AddOrSetValue('Times', TStandard14FontName.TimesRoman);
  Aliases.AddOrSetValue('Times,Italic', TStandard14FontName.TimesItalic);
  Aliases.AddOrSetValue('Times,Bold', TStandard14FontName.TimesBold);
  Aliases.AddOrSetValue('Times,BoldItalic', TStandard14FontName.TimesBoldItalic);
  Aliases.AddOrSetValue('ArialMT', TStandard14FontName.Helvetica);
  Aliases.AddOrSetValue('Arial-ItalicMT', TStandard14FontName.HelveticaOblique);
  Aliases.AddOrSetValue('Arial-BoldMT', TStandard14FontName.HelveticaBold);
  Aliases.AddOrSetValue('Arial-BoldItalicMT', TStandard14FontName.HelveticaBoldOblique);
end;

class function TStandard14Fonts.CreateMetricsCache: TPdfSharedCache<TStandard14FontName, TFontMetrics>;
begin
  Result := TPdfSharedCache<TStandard14FontName, TFontMetrics>.Create;
end;

class function TStandard14Fonts.LoadMetrics(FontName: TStandard14FontName): TFontMetrics;
begin
  const Data = TPdfAfmResources.Load(PostScriptName(FontName));
  const Parser = TAFMParser.Create(Data);
  try
    Result := Parser.Parse(True);
  finally
    Parser.Free;
  end;
end;

class function TStandard14Fonts.Names: TArray<string>;
begin
  Result := FAliases.Get(CreateAliases).Keys.ToArray;
end;

class function TStandard14Fonts.ContainsName(const Name: string): Boolean;
begin
  Result := FAliases.Get(CreateAliases).ContainsKey(Name);
end;

class function TStandard14Fonts.TryGetMappedFontName(const Name: string; out FontName: TStandard14FontName): Boolean;
begin
  Result := FAliases.Get(CreateAliases).TryGetValue(Name, FontName);
end;

class function TStandard14Fonts.PostScriptName(const FontName: TStandard14FontName): string;
begin
  case FontName of
    TStandard14FontName.TimesRoman            : Result := 'Times-Roman';
    TStandard14FontName.TimesBold             : Result := 'Times-Bold';
    TStandard14FontName.TimesItalic           : Result := 'Times-Italic';
    TStandard14FontName.TimesBoldItalic       : Result := 'Times-BoldItalic';
    TStandard14FontName.Helvetica             : Result := 'Helvetica';
    TStandard14FontName.HelveticaBold         : Result := 'Helvetica-Bold';
    TStandard14FontName.HelveticaOblique      : Result := 'Helvetica-Oblique';
    TStandard14FontName.HelveticaBoldOblique  : Result := 'Helvetica-BoldOblique';
    TStandard14FontName.Courier               : Result := 'Courier';
    TStandard14FontName.CourierBold           : Result := 'Courier-Bold';
    TStandard14FontName.CourierOblique        : Result := 'Courier-Oblique';
    TStandard14FontName.CourierBoldOblique    : Result := 'Courier-BoldOblique';
    TStandard14FontName.Symbol                : Result := 'Symbol';
    TStandard14FontName.ZapfDingbats          : Result := 'ZapfDingbats';
  else
    raise ENotSupportedException.CreateFmt('Unsupported standard 14 font: %d', [Ord(FontName)]);
  end;
end;

class function TStandard14Fonts.TryGetAFM(const Name: string; out Metrics: TFontMetrics): Boolean;
begin
  Metrics := nil;
  var FontName: TStandard14FontName;
  if not TryGetMappedFontName(Name, FontName) then
  begin
    Exit(False);
  end;

  const Cache = FMetrics.Get(CreateMetricsCache);
  Metrics := Cache.GetOrAdd(FontName, LoadMetrics);
  Result := True;
end;

end.
