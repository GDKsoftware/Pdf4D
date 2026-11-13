// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/cff/CFFFont.java, CFFType1Font.java and CFFCIDFont.java (3.0.8)
// Port of: fontbox/src/main/java/org/apache/fontbox/cff/FDSelect.java and the FDSelect classes inside CFFParser.java (3.0.8)
unit Pdf4D.FontBox.Cff.Font;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.Log,
  Pdf4D.FontBox.BoundingBox,
  Pdf4D.FontBox.FontBoxFont,
  Pdf4D.FontBox.Cff.Charset,
  Pdf4D.FontBox.Cff.Encoding;

type
  // The DICT keys that the parser and the fonts both use
  TCFFKeys = record
  public
    const FontMatrix = 'FontMatrix';
    const FontBBox = 'FontBBox';
    const Private_ = 'Private';
    const SyntheticBase = 'SyntheticBase';
  end;

  // A font DICT or private DICT of a CID-keyed font: numbers, strings and local subroutines by key. The parser fills it.
  TCFFDictionary = class
  private
    FNumbers: TDictionary<string, TArray<Double>>;
    FStrings: TDictionary<string, string>;
    FSubrs: TArray<TBytes>;

  public
    constructor Create;
    destructor Destroy; override;

    procedure AddNumbers(const Key: string; const Values: TArray<Double>);
    procedure AddString(const Key, Value: string);
    procedure SetSubrs(const Subrs: TArray<TBytes>);

    // The first number of the entry, or Default when there is none
    function GetNumber(const Key: string; const Default: Double): Double;
    function TryGetNumbers(const Key: string; out Values: TArray<Double>): Boolean;
    function TryGetString(const Key: string; out Value: string): Boolean;

    // Empty when the dictionary has no local subroutines
    property Subrs: TArray<TBytes> read FSubrs;
  end;

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
    // The charstring of the glyph, or the .notdef charstring for a GID beyond the CharStrings (as PDFBox). False when the font
    // has no charstrings.
    function TryGetCharString(const GID: Integer; out CharString: TBytes): Boolean;

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
    FPrivateDict: TCFFDictionary;
    FEncoding: TCFFEncoding;
    FOwnsEncoding: Boolean;
    FLocalSubrs: TArray<TBytes>;

    function GetPropertyNumber(const Key: string; const Default: Integer): Integer;

  public
    constructor Create;
    destructor Destroy; override;

    // Takes ownership of the encoding when OwnsEncoding is true
    procedure SetEncoding(const Encoding: TCFFEncoding; const OwnsEncoding: Boolean);
    procedure SetLocalSubrs(const LocalSubrs: TArray<TBytes>);

    // The width of the glyph; the .notdef width for a name that the charset does not have
    function GetWidth(const GlyphName: string): Single; override;
    // A font does not keep a log, because fonts can be shared and outlive the log of a document. The warnings about a damaged
    // charstring go to the log of the call, which may be nil.
    function GetWidthForGID(const GID: Integer; const Log: TPdfLog = nil): Single;
    function HasGlyph(const GlyphName: string): Boolean; override;

    // 0 (.notdef) when the charset has no glyph with this name
    function NameToGID(const Name: string): Integer;
    function GetPrivateDictNumber(const Key: string; const Default: Double): Double;
    function TryGetPrivateDictArray(const Key: string; out Values: TArray<Double>): Boolean;
    function DefaultWidthX: Integer;
    function NominalWidthX: Integer;

    property Encoding: TCFFEncoding read FEncoding;
    property LocalSubrs: TArray<TBytes> read FLocalSubrs;
    // The parser fills it
    property PrivateDict: TCFFDictionary read FPrivateDict;
  end;

  // Tells which font DICT (and so which private DICT) a glyph belongs to
  TCFFFDSelect = class abstract
  public
    // The index of the font DICT for the glyph; -1 when a format 3 sentinel ends before the glyph
    function GetFDIndex(const GID: Integer): Integer; virtual; abstract;
    // The highest index that GetFDIndex can give; -1 when there is none
    function MaxFDIndex: Integer; virtual; abstract;
  end;

  TCFFFormat0FDSelect = class(TCFFFDSelect)
  private
    FFDs: TArray<Byte>;

  public
    // One index per glyph
    constructor Create(const FDs: TArray<Byte>);

    function GetFDIndex(const GID: Integer): Integer; override;
    function MaxFDIndex: Integer; override;
  end;

  TCFFFormat3Range = record
    First: Integer;
    FD: Integer;
  end;

  TCFFFormat3FDSelect = class(TCFFFDSelect)
  private
    FRanges: TArray<TCFFFormat3Range>;
    FSentinel: Integer;
    // The ranges start in ascending order, so a binary search finds the same range as the linear one
    FIsSorted: Boolean;

    function GetFDIndexLinear(const GID: Integer): Integer;
    function GetFDIndexSorted(const GID: Integer): Integer;
    function RangeResult(const RangeIndex, GID: Integer): Integer;

  public
    constructor Create(const Ranges: TArray<TCFFFormat3Range>; const Sentinel: Integer);

    function GetFDIndex(const GID: Integer): Integer; override;
    function MaxFDIndex: Integer; override;

    property Sentinel: Integer read FSentinel;
  end;

  // A CID-keyed CFF font. The font owns its font DICTs, private DICTs and FDSelect.
  TCFFCIDFont = class(TCFFFont)
  private
    const DefaultDefaultWidthX = 1000;
    const DefaultNominalWidthX = 0;
    const SelectorPrefix = Char(92);

  private
    FRegistry: string;
    FOrdering: string;
    FSupplement: Integer;
    FFontDicts: TObjectList<TCFFDictionary>;
    FPrivDicts: TObjectList<TCFFDictionary>;
    FFdSelect: TCFFFDSelect;

    class function TryParseSelector(const Selector: string; out CID: Integer): Boolean; static;

    function TryGetPrivateDict(const GID: Integer; out PrivateDict: TCFFDictionary): Boolean;
    function PrivateWidth(const GID: Integer; const Key: string; const Default: Integer): Integer;

  public
    constructor Create;
    destructor Destroy; override;

    procedure SetROS(const Registry, Ordering: string; const Supplement: Integer);
    // Takes ownership of the lists and of the FDSelect
    procedure SetFontDicts(const FontDicts: TObjectList<TCFFDictionary>);
    procedure SetPrivDicts(const PrivDicts: TObjectList<TCFFDictionary>);
    procedure SetFdSelect(const FdSelect: TCFFFDSelect);

    // 0 (.notdef) when the charset has no glyph for the CID. The result is not checked against the CharStrings.
    function CIDToGID(const CID: Integer): Integer;
    // 1000 when the glyph has no private DICT, as PDFBox
    function GetDefaultWidthX(const GID: Integer): Integer;
    // 0 when the glyph has no private DICT
    function GetNominalWidthX(const GID: Integer): Integer;
    // Empty when the glyph has no private DICT or the DICT has no local subroutines
    function GetLocalSubrs(const GID: Integer): TArray<TBytes>;

    // The selector is a CID in the form \ddddd. A selector that has another form raises EPdfParseException.
    function GetWidth(const Selector: string): Single; override;
    // The width of the glyph of the CID. A CID whose glyph is beyond the CharStrings gets the .notdef charstring and the widths
    // of the private DICT of that glyph. The log gets the warnings about a damaged charstring and may be nil.
    function GetWidthForCID(const CID: Integer; const Log: TPdfLog = nil): Single;
    function HasGlyph(const Selector: string): Boolean; override;

    property Registry: string read FRegistry;
    property Ordering: string read FOrdering;
    property Supplement: Integer read FSupplement;
    property FontDicts: TObjectList<TCFFDictionary> read FFontDicts;
    property PrivDicts: TObjectList<TCFFDictionary> read FPrivDicts;
    property FdSelect: TCFFFDSelect read FFdSelect;
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
  Pdf4D.Common.Defines,
  Pdf4D.FontBox.CharStringWidth;

const
  InvalidSelectorMessage = 'Invalid selector "%s"';
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

{ TCFFDictionary }

constructor TCFFDictionary.Create;
begin
  inherited Create;
  FNumbers := TDictionary<string, TArray<Double>>.Create;
  FStrings := TDictionary<string, string>.Create;
end;

destructor TCFFDictionary.Destroy;
begin
  FStrings.Free;
  FNumbers.Free;
  inherited;
end;

procedure TCFFDictionary.AddNumbers(const Key: string; const Values: TArray<Double>);
begin
  FNumbers.AddOrSetValue(Key, Values);
end;

procedure TCFFDictionary.AddString(const Key, Value: string);
begin
  FStrings.AddOrSetValue(Key, Value);
end;

procedure TCFFDictionary.SetSubrs(const Subrs: TArray<TBytes>);
begin
  FSubrs := Subrs;
end;

function TCFFDictionary.GetNumber(const Key: string; const Default: Double): Double;
begin
  var Values: TArray<Double>;
  if FNumbers.TryGetValue(Key, Values) and (System.Length(Values) > 0) then
  begin
    Result := Values[0];
  end
  else
  begin
    Result := Default;
  end;
end;

function TCFFDictionary.TryGetNumbers(const Key: string; out Values: TArray<Double>): Boolean;
begin
  Result := FNumbers.TryGetValue(Key, Values);
end;

function TCFFDictionary.TryGetString(const Key: string; out Value: string): Boolean;
begin
  Result := FStrings.TryGetValue(Key, Value);
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
  if (not TryGetTopDictArray(TCFFKeys.FontBBox, Numbers)) or (Length(Numbers) < BBoxNumberCount) then
  begin
    raise EPdfParseException.Create('FontBBox must have 4 numbers');
  end;
  Result := TBoundingBox.Create(TCFFNumber.ToSingle(Numbers[0]), TCFFNumber.ToSingle(Numbers[1]),
                                TCFFNumber.ToSingle(Numbers[2]), TCFFNumber.ToSingle(Numbers[3]));
end;

function TCFFFont.FontMatrix: TArray<Single>;
begin
  var Numbers: TArray<Double>;
  if not TryGetTopDictArray(TCFFKeys.FontMatrix, Numbers) then
  begin
    Numbers := [0.001, 0, 0, 0.001, 0, 0];
  end;

  SetLength(Result, Length(Numbers));
  for var Index := 0 to High(Numbers) do
  begin
    Result[Index] := TCFFNumber.ToSingle(Numbers[Index]);
  end;
end;

function TCFFFont.TryGetCharString(const GID: Integer; out CharString: TBytes): Boolean;
begin
  CharString := nil;
  Result := (Length(FCharStrings) > 0);
  if Result then
  begin
    const IsInRange = ((GID >= 0) and (GID < Length(FCharStrings)));
    if IsInRange then
    begin
      CharString := FCharStrings[GID];
    end
    else
    begin
      CharString := FCharStrings[0];
    end;
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
  FPrivateDict := TCFFDictionary.Create;
end;

destructor TCFFType1Font.Destroy;
begin
  if FOwnsEncoding then
  begin
    FEncoding.Free;
  end;
  FPrivateDict.Free;
  inherited;
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
  Result := GetWidthForGID(NameToGID(GlyphName));
end;

function TCFFType1Font.GetWidthForGID(const GID: Integer; const Log: TPdfLog): Single;
begin
  var CharString: TBytes;
  if TryGetCharString(GID, CharString) then
  begin
    Result := TCharStringWidth.Type2Width(CharString, GlobalSubrs, LocalSubrs, DefaultWidthX, NominalWidthX, Log);
  end
  else
  begin
    Result := DefaultWidthX;
  end;
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
  Result := FPrivateDict.GetNumber(Key, Default);
end;

function TCFFType1Font.TryGetPrivateDictArray(const Key: string; out Values: TArray<Double>): Boolean;
begin
  Result := FPrivateDict.TryGetNumbers(Key, Values);
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

{ TCFFFormat0FDSelect }

constructor TCFFFormat0FDSelect.Create(const FDs: TArray<Byte>);
begin
  inherited Create;
  FFDs := FDs;
end;

function TCFFFormat0FDSelect.GetFDIndex(const GID: Integer): Integer;
begin
  const IsInTable = ((GID >= 0) and (GID < System.Length(FFDs)));
  if IsInTable then
  begin
    Result := FFDs[GID];
  end
  else
  begin
    Result := 0;
  end;
end;

function TCFFFormat0FDSelect.MaxFDIndex: Integer;
begin
  Result := -1;
  for var FD in FFDs do
  begin
    Result := Max(Result, Integer(FD));
  end;
end;

{ TCFFFormat3FDSelect }

constructor TCFFFormat3FDSelect.Create(const Ranges: TArray<TCFFFormat3Range>; const Sentinel: Integer);
begin
  inherited Create;
  FRanges := Ranges;
  FSentinel := Sentinel;
  FIsSorted := True;
  for var Index := 1 to High(Ranges) do
  begin
    if Ranges[Index].First < Ranges[Index - 1].First then
    begin
      FIsSorted := False;
      Break;
    end;
  end;
end;

function TCFFFormat3FDSelect.GetFDIndex(const GID: Integer): Integer;
begin
  if FIsSorted then
  begin
    Result := GetFDIndexSorted(GID);
  end
  else
  begin
    Result := GetFDIndexLinear(GID);
  end;
end;

// The range that holds the glyph is the last one that starts at or before it
function TCFFFormat3FDSelect.GetFDIndexSorted(const GID: Integer): Integer;
begin
  var Low := 0;
  var Top := High(FRanges);
  var Found := -1;
  while Low <= Top do
  begin
    const Middle = Low + ((Top - Low) div 2);
    if FRanges[Middle].First <= GID then
    begin
      Found := Middle;
      Low := Middle + 1;
    end
    else
    begin
      Top := Middle - 1;
    end;
  end;

  if Found < 0 then
  begin
    Exit(0);
  end;
  Result := RangeResult(Found, GID);
end;

function TCFFFormat3FDSelect.RangeResult(const RangeIndex, GID: Integer): Integer;
begin
  const IsLastRange = (RangeIndex + 1 = System.Length(FRanges));
  if not IsLastRange then
  begin
    Exit(FRanges[RangeIndex].FD);
  end;
  // The sentinel must be greater than the glyph
  if FSentinel > GID then
  begin
    Exit(FRanges[RangeIndex].FD);
  end;
  Result := -1;
end;

function TCFFFormat3FDSelect.GetFDIndexLinear(const GID: Integer): Integer;
begin
  for var Index := 0 to High(FRanges) do
  begin
    if FRanges[Index].First <= GID then
    begin
      const IsLastRange = (Index + 1 = System.Length(FRanges));
      if not IsLastRange then
      begin
        if FRanges[Index + 1].First > GID then
        begin
          Exit(FRanges[Index].FD);
        end;
      end
      else
      begin
        // The sentinel must be greater than the glyph
        if FSentinel > GID then
        begin
          Exit(FRanges[Index].FD);
        end;
        Exit(-1);
      end;
    end;
  end;
  Result := 0;
end;

function TCFFFormat3FDSelect.MaxFDIndex: Integer;
begin
  Result := -1;
  for var Range in FRanges do
  begin
    Result := Max(Result, Range.FD);
  end;
end;

{ TCFFCIDFont }

constructor TCFFCIDFont.Create;
begin
  inherited Create;
  FFontDicts := TObjectList<TCFFDictionary>.Create(True);
  FPrivDicts := TObjectList<TCFFDictionary>.Create(True);
end;

destructor TCFFCIDFont.Destroy;
begin
  FFdSelect.Free;
  FPrivDicts.Free;
  FFontDicts.Free;
  inherited;
end;

procedure TCFFCIDFont.SetROS(const Registry, Ordering: string; const Supplement: Integer);
begin
  FRegistry := Registry;
  FOrdering := Ordering;
  FSupplement := Supplement;
end;

procedure TCFFCIDFont.SetFontDicts(const FontDicts: TObjectList<TCFFDictionary>);
begin
  if FFontDicts <> FontDicts then
  begin
    FFontDicts.Free;
    FFontDicts := FontDicts;
  end;
end;

procedure TCFFCIDFont.SetPrivDicts(const PrivDicts: TObjectList<TCFFDictionary>);
begin
  if FPrivDicts <> PrivDicts then
  begin
    FPrivDicts.Free;
    FPrivDicts := PrivDicts;
  end;
end;

procedure TCFFCIDFont.SetFdSelect(const FdSelect: TCFFFDSelect);
begin
  if FFdSelect <> FdSelect then
  begin
    FFdSelect.Free;
    FFdSelect := FdSelect;
  end;
end;

function TCFFCIDFont.CIDToGID(const CID: Integer): Integer;
begin
  Result := Charset.GetGIDForCID(CID);
end;

// A glyph whose FD index is missing or beyond the private DICTs has none, as in PDFBox
function TCFFCIDFont.TryGetPrivateDict(const GID: Integer; out PrivateDict: TCFFDictionary): Boolean;
begin
  PrivateDict := nil;
  if not Assigned(FFdSelect) then
  begin
    Exit(False);
  end;

  const FDIndex = FFdSelect.GetFDIndex(GID);
  const IsIndexValid = ((FDIndex >= 0) and (FDIndex < FPrivDicts.Count));
  if IsIndexValid then
  begin
    PrivateDict := FPrivDicts[FDIndex];
  end;
  Result := IsIndexValid;
end;

function TCFFCIDFont.PrivateWidth(const GID: Integer; const Key: string; const Default: Integer): Integer;
begin
  var PrivateDict: TCFFDictionary;
  var Values: TArray<Double>;
  const HasNumber = (TryGetPrivateDict(GID, PrivateDict) and PrivateDict.TryGetNumbers(Key, Values) and
                     (System.Length(Values) > 0));
  if HasNumber then
  begin
    Result := TCFFNumber.ToInt(Values[0]);
  end
  else
  begin
    Result := Default;
  end;
end;

function TCFFCIDFont.GetDefaultWidthX(const GID: Integer): Integer;
begin
  Result := PrivateWidth(GID, DefaultWidthXKey, DefaultDefaultWidthX);
end;

function TCFFCIDFont.GetNominalWidthX(const GID: Integer): Integer;
begin
  Result := PrivateWidth(GID, NominalWidthXKey, DefaultNominalWidthX);
end;

function TCFFCIDFont.GetLocalSubrs(const GID: Integer): TArray<TBytes>;
begin
  var PrivateDict: TCFFDictionary;
  if TryGetPrivateDict(GID, PrivateDict) then
  begin
    Result := PrivateDict.Subrs;
  end
  else
  begin
    Result := nil;
  end;
end;

function TCFFCIDFont.GetWidth(const Selector: string): Single;
begin
  var CID: Integer;
  if not TryParseSelector(Selector, CID) then
  begin
    raise EPdfParseException.CreateFmt(InvalidSelectorMessage, [Selector]);
  end;
  Result := GetWidthForCID(CID);
end;

function TCFFCIDFont.GetWidthForCID(const CID: Integer; const Log: TPdfLog): Single;
begin
  const GID = CIDToGID(CID);
  var CharString: TBytes;
  if TryGetCharString(GID, CharString) then
  begin
    Result := TCharStringWidth.Type2Width(CharString, GlobalSubrs, GetLocalSubrs(GID), GetDefaultWidthX(GID),
                                          GetNominalWidthX(GID), Log);
  end
  else
  begin
    Result := GetDefaultWidthX(GID);
  end;
end;

// Java's Integer.parseInt of the text after the backslash: an optional sign and decimal digits
class function TCFFCIDFont.TryParseSelector(const Selector: string; out CID: Integer): Boolean;
begin
  CID := 0;
  const HasPrefix = ((Selector.Length > 1) and (Selector[1] = SelectorPrefix));
  if not HasPrefix then
  begin
    Exit(False);
  end;

  const Number = Selector.Substring(1);
  const HasSign = ((Number[1] = '-') or (Number[1] = '+'));
  var FirstDigit := 1;
  if HasSign then
  begin
    FirstDigit := 2;
  end;

  const HasDigits = (FirstDigit <= Number.Length);
  if not HasDigits then
  begin
    Exit(False);
  end;

  for var Position := FirstDigit to Number.Length do
  begin
    const IsDigit = ((Number[Position] >= '0') and (Number[Position] <= '9'));
    if not IsDigit then
    begin
      Exit(False);
    end;
  end;

  Result := TryStrToInt(Number, CID);
end;

function TCFFCIDFont.HasGlyph(const Selector: string): Boolean;
begin
  var CID: Integer;
  if not TryParseSelector(Selector, CID) then
  begin
    raise EPdfParseException.CreateFmt(InvalidSelectorMessage, [Selector]);
  end;
  Result := (CID <> 0);
end;

end.
