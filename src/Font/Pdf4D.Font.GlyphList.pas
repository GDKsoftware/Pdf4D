// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/font/encoding/GlyphList.java (3.0.8)
unit Pdf4D.Font.GlyphList;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.Log,
  Pdf4D.Common.SharedInstance;

type
  // A PostScript glyph list: maps glyph names to sequences of Unicode characters. A list does not change after it is
  // made, so the shared lists can be used from every thread. Unlike PDFBox it keeps no cache of uniXXXX names.
  TGlyphList = class
  private
    class var FAdobe: TPdfSharedInstance<TGlyphList>;
    class var FZapfDingbats: TPdfSharedInstance<TGlyphList>;
    class var FTextExtraction: TPdfSharedInstance<TGlyphList>;

    class destructor Destroy;

    class function LoadAdobe: TGlyphList; static;
    class function LoadZapfDingbats: TGlyphList; static;
    class function LoadTextExtraction: TGlyphList; static;
    class function Latin1ToString(const Data: TBytes): string; static;
    class function CodePointsToString(const CodePoints: TArray<Integer>): string; static;
    class function TryParseHex(const Text: string; out Value: Integer): Boolean; static;
    class function TryUniName(const Name: string; const Log: TPdfLog; out Value: string): Boolean; static;

  private
    FNameToUnicode: TDictionary<string, string>;
    FUnicodeToName: TDictionary<string, string>;

    procedure LoadList(const Data: TBytes);
    procedure AddLine(const Line: string);
    procedure AddEntry(const Name: string; const Value: string);
    function IsCanonicalName(const Name: string): Boolean;

  public
    // A list from the text of a glyph list in Adobe format
    constructor Create(const Data: TBytes); overload;
    // A copy of Base with the entries of Data on top
    constructor Create(const Base: TGlyphList; const Data: TBytes); overload;
    destructor Destroy; override;

    // The Adobe Glyph List (4281 entries). Shared, the caller does not own it.
    class function AdobeGlyphList: TGlyphList; static;
    // The Zapf Dingbats glyph list (202 entries). Shared.
    class function ZapfDingbats: TGlyphList; static;
    // The Adobe list plus the additional list, as the text extraction of PDFBox uses it. Shared.
    class function TextExtraction: TGlyphList; static;

    // The Unicode text of a glyph name, also for uniXXXX, uXXXX and names with a suffix after a dot. False when
    // there is none.
    function TryToUnicode(const Name: string; out Value: string): Boolean; overload;
    // As above; a name that looks like uniXXXX but is not valid is reported to Log, which may be nil
    function TryToUnicode(const Name: string; const Log: TPdfLog; out Value: string): Boolean; overload;
    // The name of the code point, or .notdef
    function CodePointToName(const CodePoint: Integer): string;
    // The name of a sequence of Unicode characters, or .notdef
    function SequenceToName(const Sequence: string): string;
    function Count: Integer;
  end;

implementation

uses
  System.Character,
  Pdf4D.Common.Defines,
  Pdf4D.Font.Encoding.Tables,
  Pdf4D.Resources.GlyphList;

const
  NotDefName = '.notdef';
  MaxCodePoint = $10FFFF;

{ TGlyphList }

class destructor TGlyphList.Destroy;
begin
  FTextExtraction.Release;
  FZapfDingbats.Release;
  FAdobe.Release;
end;

constructor TGlyphList.Create(const Data: TBytes);
begin
  inherited Create;
  FNameToUnicode := TDictionary<string, string>.Create(4300);
  FUnicodeToName := TDictionary<string, string>.Create(4300);
  LoadList(Data);
end;

constructor TGlyphList.Create(const Base: TGlyphList; const Data: TBytes);
begin
  inherited Create;
  FNameToUnicode := TDictionary<string, string>.Create(Base.FNameToUnicode);
  FUnicodeToName := TDictionary<string, string>.Create(Base.FUnicodeToName);
  LoadList(Data);
end;

destructor TGlyphList.Destroy;
begin
  FUnicodeToName.Free;
  FNameToUnicode.Free;
  inherited;
end;

class function TGlyphList.AdobeGlyphList: TGlyphList;
begin
  Result := FAdobe.Get(LoadAdobe);
end;

class function TGlyphList.ZapfDingbats: TGlyphList;
begin
  Result := FZapfDingbats.Get(LoadZapfDingbats);
end;

class function TGlyphList.TextExtraction: TGlyphList;
begin
  Result := FTextExtraction.Get(LoadTextExtraction);
end;

class function TGlyphList.LoadAdobe: TGlyphList;
begin
  Result := TGlyphList.Create(TPdfGlyphListResources.Load('glyphlist'));
end;

class function TGlyphList.LoadZapfDingbats: TGlyphList;
begin
  Result := TGlyphList.Create(TPdfGlyphListResources.Load('zapfdingbats'));
end;

class function TGlyphList.LoadTextExtraction: TGlyphList;
begin
  Result := TGlyphList.Create(AdobeGlyphList, TPdfGlyphListResources.Load('additional'));
end;

procedure TGlyphList.LoadList(const Data: TBytes);
begin
  const Text = Latin1ToString(Data);
  var Start := 1;
  while Start <= Length(Text) do
  begin
    var Finish := Start;
    while (Finish <= Length(Text)) and (Text[Finish] <> #10) and (Text[Finish] <> #13) do
    begin
      Inc(Finish);
    end;
    AddLine(Copy(Text, Start, Finish - Start));
    Start := Finish + 1;
  end;
end;

procedure TGlyphList.AddLine(const Line: string);
begin
  if (Line = '') or Line.StartsWith('#') then
  begin
    Exit;
  end;

  const Parts = Line.Split([';']);
  if Length(Parts) < 2 then
  begin
    raise EPdfParseException.CreateFmt('Invalid glyph list entry: %s', [Line]);
  end;

  const Hexes = Parts[1].Split([' ']);
  var CodePoints: TArray<Integer>;
  SetLength(CodePoints, Length(Hexes));
  for var Index := 0 to High(Hexes) do
  begin
    if not TryParseHex(Hexes[Index], CodePoints[Index]) then
    begin
      raise EPdfParseException.CreateFmt('Invalid glyph list entry: %s', [Line]);
    end;
  end;
  AddEntry(Parts[0], CodePointsToString(CodePoints));
end;

procedure TGlyphList.AddEntry(const Name: string; const Value: string);
begin
  FNameToUnicode.AddOrSetValue(Name, Value);
  // PDFBOX-3884: the standard encodings are canonical, for example tilde over ilde
  if IsCanonicalName(Name) then
  begin
    FUnicodeToName.AddOrSetValue(Value, Name);
  end
  else
  begin
    FUnicodeToName.TryAdd(Value, Name);
  end;
end;

function TGlyphList.IsCanonicalName(const Name: string): Boolean;
begin
  Result := TWinAnsiEncoding.Instance.Contains(Name) or
            TMacRomanEncoding.Instance.Contains(Name) or
            TMacExpertEncoding.Instance.Contains(Name) or
            TSymbolEncoding.Instance.Contains(Name) or
            TZapfDingbatsEncoding.Instance.Contains(Name);
end;

// The glyph list files are ISO-8859-1, whose bytes are the first 256 code points
class function TGlyphList.Latin1ToString(const Data: TBytes): string;
begin
  SetLength(Result, Length(Data));
  for var Index := 0 to High(Data) do
  begin
    Result[Index + 1] := Char(Data[Index]);
  end;
end;

class function TGlyphList.CodePointsToString(const CodePoints: TArray<Integer>): string;
begin
  Result := '';
  for var CodePoint in CodePoints do
  begin
    if (CodePoint < 0) or (CodePoint > MaxCodePoint) then
    begin
      raise EPdfParseException.CreateFmt('Invalid code point in a glyph list: %d', [CodePoint]);
    end;

    if CodePoint <= $FFFF then
    begin
      Result := Result + Char(CodePoint);
    end
    else
    begin
      const Offset = CodePoint - $10000;
      Result := Result + Char($D800 + (Offset shr 10)) + Char($DC00 + (Offset and $3FF));
    end;
  end;
end;

// Like Java's Integer.parseInt(Text, 16): an optional sign, then hexadecimal digits
class function TGlyphList.TryParseHex(const Text: string; out Value: Integer): Boolean;
begin
  Value := 0;
  var Start := 1;
  var Negative := False;
  if (Text <> '') and ((Text[1] = '+') or (Text[1] = '-')) then
  begin
    Negative := Text[1] = '-';
    Start := 2;
  end;

  // At most seven digits, so the value stays below $10000000 and no glyph list entry or glyph name is longer
  if (Start > Length(Text)) or (Length(Text) - Start + 1 > 7) then
  begin
    Exit(False);
  end;

  for var Position := Start to Length(Text) do
  begin
    const Character = Text[Position];
    var Digit: Integer;
    case Character of
      '0'..'9':
        Digit := Ord(Character) - Ord('0');
      'a'..'f':
        Digit := Ord(Character) - Ord('a') + 10;
      'A'..'F':
        Digit := Ord(Character) - Ord('A') + 10;
    else
      Exit(False);
    end;
    Value := (Value shl 4) or Digit;
  end;

  if Negative then
  begin
    Value := -Value;
  end;
  Result := True;
end;

function TGlyphList.TryToUnicode(const Name: string; out Value: string): Boolean;
begin
  Result := TryToUnicode(Name, nil, Value);
end;

function TGlyphList.TryToUnicode(const Name: string; const Log: TPdfLog; out Value: string): Boolean;
begin
  if FNameToUnicode.TryGetValue(Name, Value) then
  begin
    Exit(True);
  end;

  // A suffix after a dot is ignored
  const DotPosition = Name.IndexOf('.');
  if DotPosition > 0 then
  begin
    Exit(TryToUnicode(Name.Substring(0, DotPosition), Log, Value));
  end;

  Result := TryUniName(Name, Log, Value);
end;

// The format uniXXXX or uXXXX, where X is a hexadecimal digit
class function TGlyphList.TryUniName(const Name: string; const Log: TPdfLog; out Value: string): Boolean;
begin
  Value := '';
  const IsUni = (Length(Name) = 7) and Name.StartsWith('uni');
  const IsShortUni = (Length(Name) = 5) and Name.StartsWith('u');
  if not (IsUni or IsShortUni) then
  begin
    Exit(False);
  end;

  var CodePoint: Integer;
  const Start = Length(Name) - 4 + 1;
  if not TryParseHex(Copy(Name, Start, 4), CodePoint) then
  begin
    if Assigned(Log) then
    begin
      Log.Warning('Not a number in Unicode character name: %s', [Name]);
    end;
    Exit(False);
  end;

  if (CodePoint > $D7FF) and (CodePoint < $E000) then
  begin
    if Assigned(Log) then
    begin
      Log.Warning('Unicode character name with disallowed code area: %s', [Name]);
    end;
    Exit(False);
  end;

  // Java casts to char, so a sign leaves only the low 16 bits
  Value := Char(CodePoint and $FFFF);
  Result := True;
end;

function TGlyphList.CodePointToName(const CodePoint: Integer): string;
begin
  if (CodePoint < 0) or (CodePoint > MaxCodePoint) then
  begin
    Exit(NotDefName);
  end;

  if not FUnicodeToName.TryGetValue(CodePointsToString([CodePoint]), Result) then
  begin
    Result := NotDefName;
  end;
end;

function TGlyphList.SequenceToName(const Sequence: string): string;
begin
  if not FUnicodeToName.TryGetValue(Sequence, Result) then
  begin
    Result := NotDefName;
  end;
end;

function TGlyphList.Count: Integer;
begin
  Result := FNameToUnicode.Count;
end;

end.
