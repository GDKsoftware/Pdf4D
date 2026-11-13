// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/text/PDFTextStripper.java (normalizeWord) and
// pdfbox/src/main/java/org/apache/pdfbox/text/TextPosition.java (isDiacritic, combineDiacritic) (3.0.8), as data
unit Pdf4D.Text.UnicodeTables;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.SharedInstance;

type
  // The Unicode data that PDFBox takes from the JDK (java.text.Normalizer and Character.getType). The tables were made
  // with the JDK of the oracle (Java 21, Unicode 15.0) and are shared and immutable.
  TPdfUnicodeText = class
  private
    type
      TCharRange = record
        First: Char;
        Last: Char;
      end;

    class var FShared: TPdfSharedInstance<TPdfUnicodeText>;

  private
    FPresentation: TDictionary<Char, string>;
    FNfkc: TDictionary<Char, string>;
    FDiacritics: TArray<TCharRange>;

    constructor Create(const Data: TBytes);

    procedure Parse(const Data: TBytes);
    procedure ParseLine(const Section, Line: string);
    procedure AddEntry(const Target: TDictionary<Char, string>; const Line: string);
    procedure AddRange(const Line: string);

    class function ParseCodePoint(const Text: string): Char; static;

  public
    class destructor Destroy;
    class function Instance: TPdfUnicodeText; static;

    destructor Destroy; override;

    // Normalizer.normalize(c, NFKC).trim() for c in U+FB00-U+FDFF and U+FE70-U+FEFF, when that differs from c
    function TryGetPresentationForm(const C: Char; out Normalized: string): Boolean;
    // Character.getType(c) is NON_SPACING_MARK, MODIFIER_SYMBOL or MODIFIER_LETTER
    function IsDiacriticCategory(const C: Char): Boolean;
    // Normalizer.normalize(c, NFKC).trim() for a diacritic character, when that differs from c
    function TryGetNfkc(const C: Char; out Normalized: string): Boolean;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Resources.Unicode;

const
  SectionPresentation = '[presentation]';
  SectionDiacritic = '[diacritic]';
  SectionNfkc = '[nfkc]';

{ TPdfUnicodeText }

class destructor TPdfUnicodeText.Destroy;
begin
  FShared.Release;
end;

class function TPdfUnicodeText.Instance: TPdfUnicodeText;
begin
  Result := FShared.Get(
    function: TPdfUnicodeText
    begin
      Result := TPdfUnicodeText.Create(TPdfUnicodeResources.TextTables);
    end);
end;

constructor TPdfUnicodeText.Create(const Data: TBytes);
begin
  inherited Create;
  FPresentation := TDictionary<Char, string>.Create;
  FNfkc := TDictionary<Char, string>.Create;
  Parse(Data);
end;

destructor TPdfUnicodeText.Destroy;
begin
  FNfkc.Free;
  FPresentation.Free;
  inherited Destroy;
end;

function TPdfUnicodeText.TryGetPresentationForm(const C: Char; out Normalized: string): Boolean;
begin
  Result := FPresentation.TryGetValue(C, Normalized);
end;

function TPdfUnicodeText.IsDiacriticCategory(const C: Char): Boolean;
begin
  var Low := 0;
  var High := Length(FDiacritics) - 1;
  while Low <= High do
  begin
    const Middle = Low + (High - Low) div 2;
    if C < FDiacritics[Middle].First then
    begin
      High := Middle - 1;
    end
    else if C > FDiacritics[Middle].Last then
    begin
      Low := Middle + 1;
    end
    else
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TPdfUnicodeText.TryGetNfkc(const C: Char; out Normalized: string): Boolean;
begin
  Result := FNfkc.TryGetValue(C, Normalized);
end;

procedure TPdfUnicodeText.Parse(const Data: TBytes);
begin
  var Section := '';
  for var RawLine in TEncoding.UTF8.GetString(Data).Split([#10]) do
  begin
    const Line = RawLine.Trim;
    if (Line = '') or Line.StartsWith('#') then
    begin
      Continue;
    end;

    if Line.StartsWith('[') then
    begin
      Section := Line;
    end
    else
    begin
      ParseLine(Section, Line);
    end;
  end;
end;

procedure TPdfUnicodeText.ParseLine(const Section, Line: string);
begin
  if Section = SectionPresentation then
  begin
    AddEntry(FPresentation, Line);
  end
  else if Section = SectionNfkc then
  begin
    AddEntry(FNfkc, Line);
  end
  else if Section = SectionDiacritic then
  begin
    AddRange(Line);
  end
  else
  begin
    raise EPdfException.CreateFmt('Unknown section in the Unicode text tables: %s', [Section]);
  end;
end;

procedure TPdfUnicodeText.AddEntry(const Target: TDictionary<Char, string>; const Line: string);
begin
  const Parts = Line.Split([';']);
  if Length(Parts) <> 2 then
  begin
    raise EPdfException.CreateFmt('Malformed line in the Unicode text tables: %s', [Line]);
  end;

  var Value := '';
  for var Part in Parts[1].Split([' '], TStringSplitOptions.ExcludeEmpty) do
  begin
    Value := Value + ParseCodePoint(Part);
  end;
  Target.AddOrSetValue(ParseCodePoint(Parts[0]), Value);
end;

procedure TPdfUnicodeText.AddRange(const Line: string);
begin
  const Parts = Line.Split(['-']);
  if Length(Parts) <> 2 then
  begin
    raise EPdfException.CreateFmt('Malformed range in the Unicode text tables: %s', [Line]);
  end;

  var Range: TCharRange;
  Range.First := ParseCodePoint(Parts[0]);
  Range.Last := ParseCodePoint(Parts[1]);
  if Range.Last < Range.First then
  begin
    raise EPdfException.CreateFmt('Malformed range in the Unicode text tables: %s', [Line]);
  end;
  if (Length(FDiacritics) > 0) and (Range.First <= FDiacritics[High(FDiacritics)].Last) then
  begin
    raise EPdfException.CreateFmt('Range out of order in the Unicode text tables: %s', [Line]);
  end;
  FDiacritics := FDiacritics + [Range];
end;

class function TPdfUnicodeText.ParseCodePoint(const Text: string): Char;
begin
  var Value: Integer;
  if (Text = '') or (Length(Text) > 4) or not TryStrToInt('$' + Text, Value) or (Value < 0) or (Value > $FFFF) then
  begin
    raise EPdfException.CreateFmt('Malformed code point in the Unicode text tables: %s', [Text]);
  end;
  Result := Char(Value);
end;

end.
