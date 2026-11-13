// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/cff/CFFFont.java and CFFType1Font.java (3.0.8)
unit Pdf4D.FontBox.Cff.Font;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.FontBox.BoundingBox,
  Pdf4D.FontBox.FontBoxFont,
  Pdf4D.FontBox.Cff.Charset,
  Pdf4D.FontBox.Cff.Encoding;

type
  // A font of a CFF font set. The parser makes it and fills it through the Set and Add methods; after that it does not
  // change. The font owns an embedded charset (not a predefined, shared one).
  TCFFFont = class abstract(TFontBoxFont)
  private
    FName: string;
    FCharset: TCFFCharset;
    FOwnsCharset: Boolean;
    FTopDictNumbers: TDictionary<string, TArray<Double>>;
    FTopDictStrings: TDictionary<string, string>;
    FCharStrings: TArray<TBytes>;
    FGlobalSubrs: TArray<TBytes>;

  public
    constructor Create;
    destructor Destroy; override;

    procedure SetName(const Name: string);
    procedure AddTopDictNumbers(const Key: string; const Values: TArray<Double>);
    procedure AddTopDictString(const Key, Value: string);
    // Takes ownership of the charset when OwnsCharset is true
    procedure SetCharset(const Charset: TCFFCharset; const OwnsCharset: Boolean);
    procedure SetCharStrings(const CharStrings: TArray<TBytes>);
    procedure SetGlobalSubrs(const GlobalSubrs: TArray<TBytes>);

    function Name: string; override;
    // Raises EPdfParseException when the font has fewer than four numbers
    function FontBBox: TBoundingBox; override;
    // The top DICT FontMatrix, 0.001 0 0 0.001 0 0 when the font has none
    function FontMatrix: TArray<Single>; override;

    // The first number of the top DICT entry, or Default when there is none
    function GetTopDictNumber(const Key: string; const Default: Double): Double;
    function TryGetTopDictArray(const Key: string; out Values: TArray<Double>): Boolean;
    function TryGetTopDictString(const Key: string; out Value: string): Boolean;

    property Charset: TCFFCharset read FCharset;
    property CharStrings: TArray<TBytes> read FCharStrings;
    property GlobalSubrs: TArray<TBytes> read FGlobalSubrs;
  end;

  // A Type 1-equivalent CFF font
  TCFFType1Font = class(TCFFFont)
  private
    const DefaultDefaultWidthX = 1000;
    const DefaultNominalWidthX = 0;

  private
    FPrivateDictNumbers: TDictionary<string, TArray<Double>>;
    FEncoding: TCFFEncoding;
    FOwnsEncoding: Boolean;
    FLocalSubrs: TArray<TBytes>;

    function GetPropertyNumber(const Key: string; const Default: Integer): Integer;

  public
    constructor Create;
    destructor Destroy; override;

    procedure AddPrivateDictNumbers(const Key: string; const Values: TArray<Double>);
    // Takes ownership of the encoding when OwnsEncoding is true
    procedure SetEncoding(const Encoding: TCFFEncoding; const OwnsEncoding: Boolean);
    procedure SetLocalSubrs(const LocalSubrs: TArray<TBytes>);

    // Widths follow with the charstring interpreter
    function GetWidth(const GlyphName: string): Single; override;
    function HasGlyph(const GlyphName: string): Boolean; override;

    // 0 (.notdef) when the charset has no glyph with this name
    function NameToGID(const Name: string): Integer;
    function GetPrivateDictNumber(const Key: string; const Default: Double): Double;
    function TryGetPrivateDictArray(const Key: string; out Values: TArray<Double>): Boolean;
    function DefaultWidthX: Integer;
    function NominalWidthX: Integer;

    property Encoding: TCFFEncoding read FEncoding;
    property LocalSubrs: TArray<TBytes> read FLocalSubrs;
  end;

  // Java's conversions of a double
  TCFFNumber = record
    // The int value: truncated and limited to the range of an Integer
    class function ToInt(const Value: Double): Integer; static;
    // The float value; a value beyond the range of a Single becomes an infinity
    class function ToSingle(const Value: Double): Single; static;
  end;

implementation

uses
  System.Math,
  Pdf4D.Common.Defines;

const
  FontMatrixKey = 'FontMatrix';
  FontBBoxKey = 'FontBBox';
  DefaultWidthXKey = 'defaultWidthX';
  NominalWidthXKey = 'nominalWidthX';
  BBoxNumberCount = 4;

{ TCFFNumber }

class function TCFFNumber.ToInt(const Value: Double): Integer;
begin
  if IsNaN(Value) then
  begin
    Exit(0);
  end;
  if Value >= MaxInt then
  begin
    Exit(MaxInt);
  end;
  if Value <= Integer.MinValue then
  begin
    Exit(Integer.MinValue);
  end;
  Result := Trunc(Value);
end;

class function TCFFNumber.ToSingle(const Value: Double): Single;
begin
  if IsNaN(Value) then
  begin
    Exit(0);
  end;
  if Value > MaxSingle then
  begin
    Exit(Single.PositiveInfinity);
  end;
  if Value < -MaxSingle then
  begin
    Exit(Single.NegativeInfinity);
  end;
  Result := Value;
end;

{ TCFFFont }

constructor TCFFFont.Create;
begin
  inherited Create;
  FTopDictNumbers := TDictionary<string, TArray<Double>>.Create;
  FTopDictStrings := TDictionary<string, string>.Create;
end;

destructor TCFFFont.Destroy;
begin
  if FOwnsCharset then
  begin
    FCharset.Free;
  end;
  FTopDictStrings.Free;
  FTopDictNumbers.Free;
  inherited;
end;

procedure TCFFFont.SetName(const Name: string);
begin
  FName := Name;
end;

procedure TCFFFont.AddTopDictNumbers(const Key: string; const Values: TArray<Double>);
begin
  FTopDictNumbers.AddOrSetValue(Key, Values);
end;

procedure TCFFFont.AddTopDictString(const Key, Value: string);
begin
  FTopDictStrings.AddOrSetValue(Key, Value);
end;

procedure TCFFFont.SetCharset(const Charset: TCFFCharset; const OwnsCharset: Boolean);
begin
  if FOwnsCharset and (FCharset <> Charset) then
  begin
    FCharset.Free;
  end;
  FCharset := Charset;
  FOwnsCharset := OwnsCharset;
end;

procedure TCFFFont.SetCharStrings(const CharStrings: TArray<TBytes>);
begin
  FCharStrings := CharStrings;
end;

procedure TCFFFont.SetGlobalSubrs(const GlobalSubrs: TArray<TBytes>);
begin
  FGlobalSubrs := GlobalSubrs;
end;

function TCFFFont.Name: string;
begin
  Result := FName;
end;

function TCFFFont.FontBBox: TBoundingBox;
begin
  var Numbers: TArray<Double>;
  if (not TryGetTopDictArray(FontBBoxKey, Numbers)) or (Length(Numbers) < BBoxNumberCount) then
  begin
    raise EPdfParseException.Create('FontBBox must have 4 numbers');
  end;
  Result := TBoundingBox.Create(TCFFNumber.ToSingle(Numbers[0]), TCFFNumber.ToSingle(Numbers[1]),
                                TCFFNumber.ToSingle(Numbers[2]), TCFFNumber.ToSingle(Numbers[3]));
end;

function TCFFFont.FontMatrix: TArray<Single>;
begin
  var Numbers: TArray<Double>;
  if not TryGetTopDictArray(FontMatrixKey, Numbers) then
  begin
    Numbers := [0.001, 0, 0, 0.001, 0, 0];
  end;

  SetLength(Result, Length(Numbers));
  for var Index := 0 to High(Numbers) do
  begin
    Result[Index] := TCFFNumber.ToSingle(Numbers[Index]);
  end;
end;

function TCFFFont.GetTopDictNumber(const Key: string; const Default: Double): Double;
begin
  var Values: TArray<Double>;
  if FTopDictNumbers.TryGetValue(Key, Values) and (Length(Values) > 0) then
  begin
    Result := Values[0];
  end
  else
  begin
    Result := Default;
  end;
end;

function TCFFFont.TryGetTopDictArray(const Key: string; out Values: TArray<Double>): Boolean;
begin
  Result := FTopDictNumbers.TryGetValue(Key, Values);
end;

function TCFFFont.TryGetTopDictString(const Key: string; out Value: string): Boolean;
begin
  Result := FTopDictStrings.TryGetValue(Key, Value);
end;

{ TCFFType1Font }

constructor TCFFType1Font.Create;
begin
  inherited Create;
  FPrivateDictNumbers := TDictionary<string, TArray<Double>>.Create;
end;

destructor TCFFType1Font.Destroy;
begin
  if FOwnsEncoding then
  begin
    FEncoding.Free;
  end;
  FPrivateDictNumbers.Free;
  inherited;
end;

procedure TCFFType1Font.AddPrivateDictNumbers(const Key: string; const Values: TArray<Double>);
begin
  FPrivateDictNumbers.AddOrSetValue(Key, Values);
end;

procedure TCFFType1Font.SetEncoding(const Encoding: TCFFEncoding; const OwnsEncoding: Boolean);
begin
  if FOwnsEncoding and (FEncoding <> Encoding) then
  begin
    FEncoding.Free;
  end;
  FEncoding := Encoding;
  FOwnsEncoding := OwnsEncoding;
end;

procedure TCFFType1Font.SetLocalSubrs(const LocalSubrs: TArray<TBytes>);
begin
  FLocalSubrs := LocalSubrs;
end;

function TCFFType1Font.GetWidth(const GlyphName: string): Single;
begin
  raise EPdfUnsupportedFeatureException.Create('Glyph widths of CFF fonts are not available yet');
end;

function TCFFType1Font.HasGlyph(const GlyphName: string): Boolean;
begin
  Result := NameToGID(GlyphName) <> 0;
end;

function TCFFType1Font.NameToGID(const Name: string): Integer;
begin
  // Some fonts have glyphs beyond their encoding, so this looks up the SID in the charset
  Result := Charset.GetGIDForSID(Charset.GetSID(Name));
end;

function TCFFType1Font.GetPrivateDictNumber(const Key: string; const Default: Double): Double;
begin
  var Values: TArray<Double>;
  if FPrivateDictNumbers.TryGetValue(Key, Values) and (Length(Values) > 0) then
  begin
    Result := Values[0];
  end
  else
  begin
    Result := Default;
  end;
end;

function TCFFType1Font.TryGetPrivateDictArray(const Key: string; out Values: TArray<Double>): Boolean;
begin
  Result := FPrivateDictNumbers.TryGetValue(Key, Values);
end;

function TCFFType1Font.GetPropertyNumber(const Key: string; const Default: Integer): Integer;
begin
  var Values: TArray<Double>;
  if (TryGetTopDictArray(Key, Values) or TryGetPrivateDictArray(Key, Values)) and (Length(Values) > 0) then
  begin
    Result := TCFFNumber.ToInt(Values[0]);
  end
  else
  begin
    Result := Default;
  end;
end;

function TCFFType1Font.DefaultWidthX: Integer;
begin
  Result := GetPropertyNumber(DefaultWidthXKey, DefaultDefaultWidthX);
end;

function TCFFType1Font.NominalWidthX: Integer;
begin
  Result := GetPropertyNumber(NominalWidthXKey, DefaultNominalWidthX);
end;

end.
