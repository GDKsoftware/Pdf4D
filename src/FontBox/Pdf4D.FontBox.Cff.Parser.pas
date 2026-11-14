// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/cff/CFFParser.java and CFFOperator.java (3.0.8)
unit Pdf4D.FontBox.Cff.Parser;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.Log,
  Pdf4D.FontBox.Cff.Charset,
  Pdf4D.FontBox.Cff.DataInput,
  Pdf4D.FontBox.Cff.Encoding,
  Pdf4D.FontBox.Cff.Font;

type
  // One DICT operand. Integers stay recognisable because "Subrs" is only used when it is one.
  TCFFOperand = record
    Value: Double;
    IsInteger: Boolean;
  end;

  TCFFDictEntry = record
    OperatorName: string;
    Operands: TArray<TCFFOperand>;

    function HasOperands: Boolean;
    function IntValue(const Index: Integer): Integer;
    // Not a boolean (0 or 1): Default
    function GetBoolean(const Index: Integer; const Default: Boolean; const Log: TPdfLog): Boolean;
    function Values: TArray<Double>;
    // The operands as differences from the previous one
    function Delta: TArray<Double>;
  end;

  TCFFDictData = class
  private
    FEntries: TDictionary<string, TCFFDictEntry>;

  public
    constructor Create;
    destructor Destroy; override;

    // An entry without a known operator is dropped
    procedure Add(const Entry: TCFFDictEntry);
    function TryGetEntry(const Name: string; out Entry: TCFFDictEntry): Boolean;
    function GetNumber(const Name: string; const Default: Double): Double;
    function GetBoolean(const Name: string; const Default: Boolean; const Log: TPdfLog): Boolean;
    function TryGetArray(const Name: string; out Values: TArray<Double>): Boolean;
    function TryGetDelta(const Name: string; out Values: TArray<Double>): Boolean;
  end;

  // Reads the font set of CFF data, or of an OpenType font that carries CFF data. Everything that comes out of a
  // malformed font is an EPdfParseException.
  TCFFParser = class
  private
    const MaxDictOperands = 512;
    const MaxRealNumberLength = 128;
    const FirstCustomSID = 391;
    const NotDefName = '.notdef';
    // The FD index is one byte in FDSelect formats 0 and 3, so a font cannot use more font DICTs than this
    const MaxFontDicts = 256;
    // A private DICT is a few hundred bytes; this keeps the cost of reading one per font DICT bounded
    const MaxCIDPrivateDictSize = 65535;
    // A font set holds one font; this is far more than a real one has and keeps the work for a damaged name INDEX bounded
    const MaxFonts = 256;
    // The work of one parse is limited to what the data can hold, with some room for the DICTs that are read twice
    const BudgetFactor = 2;
    const BudgetSlack = 4096;

  private
    FLog: TPdfLog;
    FStringIndex: TArray<string>;
    // What one parse may still read: INDEX entries (and glyph tables) and bytes, shared by all fonts and font DICTs
    FEntriesLeft: Int64;
    FBytesLeft: Int64;
    // INDEXes that were read already, by position. Font DICTs and fonts that point to the same INDEX share it.
    FIndexCache: TDictionary<Integer, TArray<TBytes>>;

    procedure StartBudget(const DataLength: Integer);
    procedure ChargeEntries(const Count: Int64);
    procedure ChargeBytes(const Count: Int64);

    class function Latin1String(const Bytes: TBytes): string; static;
    class function ResolveCffData(const Data: TBytes): TBytes; static;
    class function FindCffTable(const Input: TCFFDataInput): TBytes; static;
    class function ReadTagName(const Input: TCFFDataInput): string; static;
    class function ReadTableField(const Input: TCFFDataInput): Int64; static;
    class function ReadOffSize(const Input: TCFFDataInput): Integer; static;
    class procedure ReadHeader(const Input: TCFFDataInput); static;

    function ReadIndexDataOffsets(const Input: TCFFDataInput): TArray<Int64>;
    function ReadIndexData(const Input: TCFFDataInput): TArray<TBytes>;
    // Reads the INDEX at the position of the input, or hands out the one that was read there before
    function ReadSharedIndexData(const Input: TCFFDataInput): TArray<TBytes>;
    function ReadStringIndexData(const Input: TCFFDataInput): TArray<string>;

    class function OperatorName(const B0, B1: Integer): string; static;
    class function ReadOperator(const Input: TCFFDataInput; const B0: Integer): string; static;
    class function ReadIntegerNumber(const Input: TCFFDataInput; const B0: Integer): Integer; static;
    class function ReadRealNumber(const Input: TCFFDataInput; const Log: TPdfLog): Double; static;
    class function ReadEntry(const Input: TCFFDataInput; const Log: TPdfLog): TCFFDictEntry; static;
    class function ReadDictData(const Input: TCFFDataInput; const Log: TPdfLog): TCFFDictData; overload; static;
    function ReadDictData(const Input: TCFFDataInput; const Offset, DictSize: Integer;
                          const Log: TPdfLog): TCFFDictData; overload;

    function ReadString(const Index: Integer): string;
    function TryGetString(const Dict: TCFFDictData; const Name: string; out Value: string): Boolean;

    function TryReadFirstROS(const TopDictBytes: TBytes; out Registry, Ordering: string; out Supplement: Integer): Boolean;
    function ParseFont(const Input: TCFFDataInput; const Name: string; const TopDictBytes: TBytes): TCFFFont;
    function CreateFont(const TopDict: TCFFDictData): TCFFFont;
    function TryReadROS(const TopDict: TCFFDictData; out Registry, Ordering: string; out Supplement: Integer): Boolean;
    procedure FillFont(const Input: TCFFDataInput; const Name: string; const TopDict: TCFFDictData; const Font: TCFFFont);
    procedure AddTopDictValues(const Font: TCFFFont; const TopDict: TCFFDictData);
    function ReadCharStrings(const Input: TCFFDataInput; const TopDict: TCFFDictData): TArray<TBytes>;
    procedure ReadFontCharset(const Input: TCFFDataInput; const TopDict: TCFFDictData; const CharStringCount: Integer;
                              const Font: TCFFFont; const IsCIDFont: Boolean);
    procedure ParseType1Dicts(const Input: TCFFDataInput; const TopDict: TCFFDictData; const Font: TCFFType1Font);
    procedure ReadFontEncoding(const Input: TCFFDataInput; const TopDict: TCFFDictData; const Font: TCFFType1Font);
    procedure ReadPrivateDict(const PrivateDict: TCFFDictData; const Target: TCFFDictionary);
    procedure AddDeltaNumbers(const PrivateDict: TCFFDictData; const Target: TCFFDictionary; const Name: string);
    procedure AddNumber(const PrivateDict: TCFFDictData; const Target: TCFFDictionary; const Name: string;
                        const Default: Double);
    procedure AddOptionalNumber(const PrivateDict: TCFFDictData; const Target: TCFFDictionary; const Name: string);
    function ReadLocalSubrs(const Input: TCFFDataInput; const PrivateDict: TCFFDictData; const PrivateOffset: Integer): TArray<TBytes>;

    procedure ParseCIDFontDicts(const Input: TCFFDataInput; const TopDict: TCFFDictData; const Font: TCFFCIDFont;
                                const GlyphCount: Integer);
    procedure ReadCIDDicts(const Input: TCFFDataInput; const FontDictBytes: TArray<TBytes>;
                           const FontDicts, PrivateDicts: TObjectList<TCFFDictionary>);
    function ReadCIDFontDict(const FontDict: TCFFDictData): TCFFDictionary;
    function ReadCIDPrivateDict(const Input: TCFFDataInput; const PrivateEntry: TCFFDictEntry): TCFFDictionary;
    function ReadFDSelect(const Input: TCFFDataInput; const GlyphCount: Integer): TCFFFDSelect;
    function ReadFormat0FDSelect(const Input: TCFFDataInput; const GlyphCount: Integer): TCFFFormat0FDSelect;
    function ReadFormat3FDSelect(const Input: TCFFDataInput): TCFFFormat3FDSelect;
    procedure WarnAboutUnknownFDs(const FdSelect: TCFFFDSelect; const FontDictCount: Integer);
    procedure ApplyCIDFontMatrix(const TopDict: TCFFDictData; const Font: TCFFCIDFont);
    procedure ConcatenateFontMatrix(const Font: TCFFCIDFont; const Matrix, FontDictMatrix: TArray<Double>);

    function ReadCharset(const Input: TCFFDataInput; const GlyphCount: Integer; const IsCIDFont: Boolean): TCFFCharset;
    function ReadType1Charset(const Input: TCFFDataInput; const GlyphCount, Format: Integer): TCFFCharsetType1;
    function ReadCIDCharset(const Input: TCFFDataInput; const GlyphCount, Format: Integer): TCFFCharsetCID;
    procedure ReadCIDRanges(const Input: TCFFDataInput; const GlyphCount: Integer; const IsLeftOneByte: Boolean;
                            const Charset: TCFFRangeCharsetCID);
    class function CreateEmptyCIDCharset(const GlyphCount: Integer): TCFFCharsetCID; static;
    class function CreateEmptyCharset(const IsCIDFont: Boolean): TCFFCharset; static;
    procedure ReadFormat0Charset(const Input: TCFFDataInput; const GlyphCount: Integer; const Charset: TCFFCharsetType1);
    procedure ReadFormat1Charset(const Input: TCFFDataInput; const GlyphCount: Integer; const Charset: TCFFCharsetType1);
    procedure ReadFormat2Charset(const Input: TCFFDataInput; const GlyphCount: Integer; const Charset: TCFFCharsetType1);
    procedure AddRangeToCharset(const Charset: TCFFCharsetType1; const FirstGID, FirstSID, Count, GlyphCount: Integer);

    function ReadEncoding(const Input: TCFFDataInput; const Charset: TCFFCharset): TCFFBuiltInEncoding;
    procedure ReadFormat0Encoding(const Input: TCFFDataInput; const Charset: TCFFCharset;
                                  const Encoding: TCFFFormat0Encoding);
    procedure ReadFormat1Encoding(const Input: TCFFDataInput; const Charset: TCFFCharset;
                                  const Encoding: TCFFFormat1Encoding);
    procedure ReadSupplement(const Input: TCFFDataInput; const Encoding: TCFFBuiltInEncoding);

  public
    // The log may be nil
    constructor Create(const Log: TPdfLog = nil);
    destructor Destroy; override;

    // The caller owns the list and the fonts in it. A CID-keyed font comes out as a TCFFCIDFont.
    function Parse(const Data: TBytes): TObjectList<TCFFFont>; overload;
    // Only the first FontLimit fonts are read. A caller that needs one font does not pay for the others.
    function Parse(const Data: TBytes; const FontLimit: Integer): TObjectList<TCFFFont>; overload;
    // The registry, ordering and supplement of the first font, which only reads as much of the data as that needs. False
    // when that font is not CID-keyed, and for the cases where PDFBox records an error in its font headers (no names, no
    // top DICT, a synthetic font). Malformed data raises EPdfParseException.
    function ParseFirstSubFontROS(const Data: TBytes; out Registry, Ordering: string; out Supplement: Integer): Boolean;
  end;

implementation

uses
  System.Math,
  Pdf4D.Common.Defines,
  Pdf4D.FontBox.Cff.StandardStrings;

const
  OpenTypeTag = 'OTTO';
  CollectionTag = 'ttcf';
  TrueTypeTag = #0#1#0#0;
  CffTableTag = 'CFF ';
  IsFixedPitchKey = 'isFixedPitch';
  FDSelectTooShortMessage = 'The FDSelect needs %d bytes, the data has %d left';
  BudgetExceededMessage = 'The CFF font needs more work than its size allows';

  // A DICT operator with a second byte starts with this one
  EscapeOperator = 12;

type
  TOperatorEntry = record
    B0: Integer;
    B1: Integer;
    Name: string;
  end;

const
  Operators: array[0..51] of TOperatorEntry = (
    (B0: 0; B1: 0; Name: 'version'),
    (B0: 1; B1: 0; Name: 'Notice'),
    (B0: 12; B1: 0; Name: 'Copyright'),
    (B0: 2; B1: 0; Name: 'FullName'),
    (B0: 3; B1: 0; Name: 'FamilyName'),
    (B0: 4; B1: 0; Name: 'Weight'),
    (B0: 12; B1: 1; Name: 'isFixedPitch'),
    (B0: 12; B1: 2; Name: 'ItalicAngle'),
    (B0: 12; B1: 3; Name: 'UnderlinePosition'),
    (B0: 12; B1: 4; Name: 'UnderlineThickness'),
    (B0: 12; B1: 5; Name: 'PaintType'),
    (B0: 12; B1: 6; Name: 'CharstringType'),
    (B0: 12; B1: 7; Name: 'FontMatrix'),
    (B0: 13; B1: 0; Name: 'UniqueID'),
    (B0: 5; B1: 0; Name: 'FontBBox'),
    (B0: 12; B1: 8; Name: 'StrokeWidth'),
    (B0: 14; B1: 0; Name: 'XUID'),
    (B0: 15; B1: 0; Name: 'charset'),
    (B0: 16; B1: 0; Name: 'Encoding'),
    (B0: 17; B1: 0; Name: 'CharStrings'),
    (B0: 18; B1: 0; Name: 'Private'),
    (B0: 12; B1: 20; Name: 'SyntheticBase'),
    (B0: 12; B1: 21; Name: 'PostScript'),
    (B0: 12; B1: 22; Name: 'BaseFontName'),
    (B0: 12; B1: 23; Name: 'BaseFontBlend'),
    (B0: 12; B1: 30; Name: 'ROS'),
    (B0: 12; B1: 31; Name: 'CIDFontVersion'),
    (B0: 12; B1: 32; Name: 'CIDFontRevision'),
    (B0: 12; B1: 33; Name: 'CIDFontType'),
    (B0: 12; B1: 34; Name: 'CIDCount'),
    (B0: 12; B1: 35; Name: 'UIDBase'),
    (B0: 12; B1: 36; Name: 'FDArray'),
    (B0: 12; B1: 37; Name: 'FDSelect'),
    (B0: 12; B1: 38; Name: 'FontName'),
    (B0: 6; B1: 0; Name: 'BlueValues'),
    (B0: 7; B1: 0; Name: 'OtherBlues'),
    (B0: 8; B1: 0; Name: 'FamilyBlues'),
    (B0: 9; B1: 0; Name: 'FamilyOtherBlues'),
    (B0: 12; B1: 9; Name: 'BlueScale'),
    (B0: 12; B1: 10; Name: 'BlueShift'),
    (B0: 12; B1: 11; Name: 'BlueFuzz'),
    (B0: 10; B1: 0; Name: 'StdHW'),
    (B0: 11; B1: 0; Name: 'StdVW'),
    (B0: 12; B1: 12; Name: 'StemSnapH'),
    (B0: 12; B1: 13; Name: 'StemSnapV'),
    (B0: 12; B1: 14; Name: 'ForceBold'),
    (B0: 12; B1: 15; Name: 'LanguageGroup'),
    (B0: 12; B1: 16; Name: 'ExpansionFactor'),
    (B0: 12; B1: 17; Name: 'initialRandomSeed'),
    (B0: 19; B1: 0; Name: 'Subrs'),
    (B0: 20; B1: 0; Name: 'defaultWidthX'),
    (B0: 21; B1: 0; Name: 'nominalWidthX')
  );

{ TCFFDictEntry }

function TCFFDictEntry.HasOperands: Boolean;
begin
  Result := Length(Operands) > 0;
end;

function TCFFDictEntry.IntValue(const Index: Integer): Integer;
begin
  Result := TCFFNumber.ToInt(Operands[Index].Value);
end;

function TCFFDictEntry.GetBoolean(const Index: Integer; const Default: Boolean; const Log: TPdfLog): Boolean;
begin
  const Operand = Operands[Index];
  if Operand.IsInteger and (Operand.Value = 0) then
  begin
    Exit(False);
  end;
  if Operand.IsInteger and (Operand.Value = 1) then
  begin
    Exit(True);
  end;

  if Assigned(Log) then
  begin
    Log.Warning('Expected boolean, got %g, returning default %s', [Operand.Value, BoolToStr(Default, True)]);
  end;
  Result := Default;
end;

function TCFFDictEntry.Values: TArray<Double>;
begin
  SetLength(Result, Length(Operands));
  for var Index := 0 to High(Operands) do
  begin
    Result[Index] := Operands[Index].Value;
  end;
end;

function TCFFDictEntry.Delta: TArray<Double>;
begin
  Result := Values;
  for var Index := 1 to High(Result) do
  begin
    // Java adds the two int values and wraps around
    const Sum = Int64(TCFFNumber.ToInt(Result[Index - 1])) + Int64(TCFFNumber.ToInt(Result[Index]));
    Result[Index] := Integer(UInt32(Sum and $FFFFFFFF));
  end;
end;

{ TCFFDictData }

constructor TCFFDictData.Create;
begin
  inherited Create;
  FEntries := TDictionary<string, TCFFDictEntry>.Create;
end;

destructor TCFFDictData.Destroy;
begin
  FEntries.Free;
  inherited;
end;

procedure TCFFDictData.Add(const Entry: TCFFDictEntry);
begin
  if Entry.OperatorName <> '' then
  begin
    FEntries.AddOrSetValue(Entry.OperatorName, Entry);
  end;
end;

function TCFFDictData.TryGetEntry(const Name: string; out Entry: TCFFDictEntry): Boolean;
begin
  Result := FEntries.TryGetValue(Name, Entry);
end;

function TCFFDictData.GetNumber(const Name: string; const Default: Double): Double;
begin
  var Entry: TCFFDictEntry;
  if TryGetEntry(Name, Entry) and Entry.HasOperands then
  begin
    Result := Entry.Operands[0].Value;
  end
  else
  begin
    Result := Default;
  end;
end;

function TCFFDictData.GetBoolean(const Name: string; const Default: Boolean; const Log: TPdfLog): Boolean;
begin
  var Entry: TCFFDictEntry;
  if TryGetEntry(Name, Entry) and Entry.HasOperands then
  begin
    Result := Entry.GetBoolean(0, Default, Log);
  end
  else
  begin
    Result := Default;
  end;
end;

function TCFFDictData.TryGetArray(const Name: string; out Values: TArray<Double>): Boolean;
begin
  var Entry: TCFFDictEntry;
  Result := TryGetEntry(Name, Entry) and Entry.HasOperands;
  if Result then
  begin
    Values := Entry.Values;
  end;
end;

function TCFFDictData.TryGetDelta(const Name: string; out Values: TArray<Double>): Boolean;
begin
  var Entry: TCFFDictEntry;
  Result := TryGetEntry(Name, Entry) and Entry.HasOperands;
  if Result then
  begin
    Values := Entry.Delta;
  end;
end;

{ TCFFParser }

constructor TCFFParser.Create(const Log: TPdfLog);
begin
  inherited Create;
  FLog := Log;
  FIndexCache := TDictionary<Integer, TArray<TBytes>>.Create;
end;

destructor TCFFParser.Destroy;
begin
  FIndexCache.Free;
  inherited;
end;

procedure TCFFParser.StartBudget(const DataLength: Integer);
begin
  FIndexCache.Clear;
  FEntriesLeft := (Int64(DataLength) * BudgetFactor) + BudgetSlack;
  FBytesLeft := (Int64(DataLength) * BudgetFactor) + BudgetSlack;
end;

procedure TCFFParser.ChargeEntries(const Count: Int64);
begin
  Dec(FEntriesLeft, Count);
  if FEntriesLeft < 0 then
  begin
    raise EPdfParseException.Create(BudgetExceededMessage);
  end;
end;

procedure TCFFParser.ChargeBytes(const Count: Int64);
begin
  Dec(FBytesLeft, Count);
  if FBytesLeft < 0 then
  begin
    raise EPdfParseException.Create(BudgetExceededMessage);
  end;
end;

class function TCFFParser.Latin1String(const Bytes: TBytes): string;
begin
  SetLength(Result, Length(Bytes));
  for var Index := 0 to High(Bytes) do
  begin
    Result[Index + 1] := Char(Bytes[Index]);
  end;
end;

function TCFFParser.Parse(const Data: TBytes): TObjectList<TCFFFont>;
begin
  Result := Parse(Data, MaxFonts);
end;

function TCFFParser.Parse(const Data: TBytes; const FontLimit: Integer): TObjectList<TCFFFont>;
begin
  const Input = TCFFDataInput.Create(ResolveCffData(Data));
  try
    StartBudget(Input.GetLength);
    ReadHeader(Input);
    const NameIndex = ReadStringIndexData(Input);
    if Length(NameIndex) = 0 then
    begin
      raise EPdfParseException.Create('Name index missing in CFF font');
    end;
    const TopDictIndex = ReadIndexData(Input);
    if Length(TopDictIndex) = 0 then
    begin
      raise EPdfParseException.Create('Top DICT INDEX missing in CFF font');
    end;
    if Length(TopDictIndex) < Length(NameIndex) then
    begin
      raise EPdfParseException.Create('The CFF font has fewer Top DICTs than names');
    end;

    FStringIndex := ReadStringIndexData(Input);
    const GlobalSubrs = ReadIndexData(Input);

    const FontCount = Min(Length(NameIndex), Min(FontLimit, MaxFonts));
    if (FontCount < Length(NameIndex)) and Assigned(FLog) then
    begin
      FLog.Warning('Only the first %d of the %d fonts of the CFF font set are read', [FontCount, Length(NameIndex)]);
    end;

    Result := TObjectList<TCFFFont>.Create(True);
    try
      for var Index := 0 to FontCount - 1 do
      begin
        const Font = ParseFont(Input, NameIndex[Index], TopDictIndex[Index]);
        Result.Add(Font);
        Font.SetGlobalSubrs(GlobalSubrs);
      end;
    except
      Result.Free;
      raise;
    end;
  finally
    Input.Free;
  end;
end;

function TCFFParser.ParseFirstSubFontROS(const Data: TBytes; out Registry, Ordering: string;
                                         out Supplement: Integer): Boolean;
begin
  Registry := '';
  Ordering := '';
  Supplement := 0;

  const Input = TCFFDataInput.Create(ResolveCffData(Data));
  try
    StartBudget(Input.GetLength);
    ReadHeader(Input);
    const NameIndex = ReadStringIndexData(Input);
    if Length(NameIndex) = 0 then
    begin
      Exit(False);
    end;
    const TopDictIndex = ReadIndexData(Input);
    if Length(TopDictIndex) = 0 then
    begin
      Exit(False);
    end;

    // The strings are needed to read the registry and the ordering
    FStringIndex := ReadStringIndexData(Input);
    Result := TryReadFirstROS(TopDictIndex[0], Registry, Ordering, Supplement);
  finally
    Input.Free;
  end;
end;

function TCFFParser.TryReadFirstROS(const TopDictBytes: TBytes; out Registry, Ordering: string;
                                    out Supplement: Integer): Boolean;
begin
  const TopDictInput = TCFFDataInput.Create(TopDictBytes);
  try
    const TopDict = ReadDictData(TopDictInput, FLog);
    try
      var Entry: TCFFDictEntry;
      if TopDict.TryGetEntry(TCFFKeys.SyntheticBase, Entry) then
      begin
        Registry := '';
        Ordering := '';
        Supplement := 0;
        Exit(False);
      end;
      Result := TryReadROS(TopDict, Registry, Ordering, Supplement);
    finally
      TopDict.Free;
    end;
  finally
    TopDictInput.Free;
  end;
end;

class function TCFFParser.ResolveCffData(const Data: TBytes): TBytes;
begin
  const Input = TCFFDataInput.Create(Data);
  try
    const FirstTag = ReadTagName(Input);
    if FirstTag = OpenTypeTag then
    begin
      Exit(FindCffTable(Input));
    end;
    if FirstTag = CollectionTag then
    begin
      raise EPdfParseException.Create('True Type Collection fonts are not supported.');
    end;
    if FirstTag = TrueTypeTag then
    begin
      raise EPdfParseException.Create('OpenType fonts containing a true type font are not supported.');
    end;
    Result := Data;
  finally
    Input.Free;
  end;
end;

class function TCFFParser.FindCffTable(const Input: TCFFDataInput): TBytes;
begin
  const NumTables = Input.ReadShort;
  Input.ReadShort;
  Input.ReadShort;
  Input.ReadShort;
  for var Table := 1 to NumTables do
  begin
    const TagName = ReadTagName(Input);
    ReadTableField(Input);
    const Offset = ReadTableField(Input);
    const Size = ReadTableField(Input);
    if TagName = CffTableTag then
    begin
      if (Offset >= Input.GetLength) or (Size > Input.GetLength) then
      begin
        raise EPdfParseException.Create('The CFF table lies outside the OpenType font');
      end;
      Input.SetPosition(Integer(Offset));
      Exit(Input.ReadBytes(Integer(Size)));
    end;
  end;
  raise EPdfParseException.Create('CFF tag not found in this OpenType font.');
end;

class function TCFFParser.ReadTagName(const Input: TCFFDataInput): string;
begin
  Result := Latin1String(Input.ReadBytes(4));
end;

class function TCFFParser.ReadTableField(const Input: TCFFDataInput): Int64;
begin
  Result := Int64(UInt32(Input.ReadInt));
end;

class function TCFFParser.ReadOffSize(const Input: TCFFDataInput): Integer;
begin
  Result := Input.ReadUnsignedByte;
  if (Result < 1) or (Result > 4) then
  begin
    raise EPdfParseException.CreateFmt('Illegal (< 1 or > 4) offSize value %d in CFF font at position %d',
                                       [Result, Input.GetPosition - 1]);
  end;
end;

class procedure TCFFParser.ReadHeader(const Input: TCFFDataInput);
begin
  Input.ReadUnsignedByte;
  Input.ReadUnsignedByte;
  Input.ReadUnsignedByte;
  ReadOffSize(Input);
end;

function TCFFParser.ReadIndexDataOffsets(const Input: TCFFDataInput): TArray<Int64>;
begin
  const Count = Input.ReadUnsignedShort;
  if Count = 0 then
  begin
    Exit(nil);
  end;

  const OffSize = ReadOffSize(Input);
  // An INDEX has Count + 1 offsets. Check that they are there before an array is made for them.
  const OffsetBytes = (Count + 1) * OffSize;
  if OffsetBytes > Input.GetLength - Input.GetPosition then
  begin
    raise EPdfParseException.CreateFmt('The CFF INDEX of %d entries is longer than the data', [Count]);
  end;

  ChargeEntries(Count);
  SetLength(Result, Count + 1);
  for var Index := 0 to Count do
  begin
    const Offset = Input.ReadOffset(OffSize);
    if Offset > Input.GetLength then
    begin
      raise EPdfParseException.CreateFmt('illegal offset value %d in CFF font', [Offset]);
    end;
    Result[Index] := Offset;
  end;
end;

function TCFFParser.ReadIndexData(const Input: TCFFDataInput): TArray<TBytes>;
begin
  const Offsets = ReadIndexDataOffsets(Input);
  if Length(Offsets) = 0 then
  begin
    Exit(nil);
  end;

  const Count = Length(Offsets) - 1;
  // The entries are read one after the other, so the sum of their lengths is what the INDEX takes from the data
  ChargeBytes(Min(Int64(Input.GetLength - Input.GetPosition), Max(Int64(0), Offsets[Count] - Offsets[0])));
  SetLength(Result, Count);
  for var Index := 0 to Count - 1 do
  begin
    const EntryLength = Offsets[Index + 1] - Offsets[Index];
    if EntryLength < 0 then
    begin
      raise EPdfParseException.CreateFmt('Negative index data length %d at %d', [EntryLength, Index]);
    end;
    Result[Index] := Input.ReadBytes(Integer(EntryLength));
  end;
end;

function TCFFParser.ReadSharedIndexData(const Input: TCFFDataInput): TArray<TBytes>;
begin
  const Position = Input.GetPosition;
  if FIndexCache.TryGetValue(Position, Result) then
  begin
    Exit;
  end;

  Result := ReadIndexData(Input);
  FIndexCache.Add(Position, Result);
end;

function TCFFParser.ReadStringIndexData(const Input: TCFFDataInput): TArray<string>;
begin
  const Entries = ReadIndexData(Input);
  SetLength(Result, Length(Entries));
  for var Index := 0 to High(Entries) do
  begin
    Result[Index] := Latin1String(Entries[Index]);
  end;
end;

class function TCFFParser.OperatorName(const B0, B1: Integer): string;
begin
  for var Entry in Operators do
  begin
    if (Entry.B0 = B0) and (Entry.B1 = B1) then
    begin
      Exit(Entry.Name);
    end;
  end;
  Result := '';
end;

class function TCFFParser.ReadOperator(const Input: TCFFDataInput; const B0: Integer): string;
begin
  if B0 = EscapeOperator then
  begin
    Result := OperatorName(B0, Input.ReadUnsignedByte);
  end
  else
  begin
    Result := OperatorName(B0, 0);
  end;
end;

class function TCFFParser.ReadIntegerNumber(const Input: TCFFDataInput; const B0: Integer): Integer;
begin
  if B0 = 28 then
  begin
    Exit(Input.ReadShort);
  end;
  if B0 = 29 then
  begin
    Exit(Input.ReadInt);
  end;
  if (B0 >= 32) and (B0 <= 246) then
  begin
    Exit(B0 - 139);
  end;
  if (B0 >= 247) and (B0 <= 250) then
  begin
    Exit((B0 - 247) * 256 + Input.ReadUnsignedByte + 108);
  end;
  if (B0 >= 251) and (B0 <= 254) then
  begin
    Exit(-(B0 - 251) * 256 - Input.ReadUnsignedByte - 108);
  end;
  raise EPdfParseException.CreateFmt('invalid DICT integer b0 byte: %d', [B0]);
end;

class function TCFFParser.ReadRealNumber(const Input: TCFFDataInput; const Log: TPdfLog): Double;
begin
  const Builder = TStringBuilder.Create;
  try
    var Done := False;
    var ExponentMissing := False;
    var HasExponent := False;
    while not Done do
    begin
      const Value = Input.ReadUnsignedByte;
      for var Half := 0 to 1 do
      begin
        const Nibble = IfThen(Half = 0, Value div 16, Value mod 16);
        case Nibble of
          0..9:
            begin
              Builder.Append(Nibble);
              ExponentMissing := False;
            end;
          $A:
            Builder.Append('.');
          $B, $C:
            begin
              if HasExponent then
              begin
                if Assigned(Log) then
                begin
                  Log.Warning('duplicate ''E'' ignored after %s', [Builder.ToString]);
                end;
              end
              else
              begin
                Builder.Append('E');
                if Nibble = $C then
                begin
                  Builder.Append('-');
                end;
                ExponentMissing := True;
                HasExponent := True;
              end;
            end;
          $D:
            ;
          $E:
            Builder.Append('-');
          else
            Done := True;
        end;
      end;
      if Builder.Length > MaxRealNumberLength then
      begin
        raise EPdfParseException.Create('A real number in a CFF DICT is too long');
      end;
    end;

    // A missing exponent is read as 0, as PDFBox does (PDFBOX-1522)
    if ExponentMissing then
    begin
      Builder.Append('0');
    end;
    if Builder.Length = 0 then
    begin
      Exit(0);
    end;
    if not TryStrToFloat(Builder.ToString, Result, TFormatSettings.Invariant) then
    begin
      raise EPdfParseException.CreateFmt('Invalid real number %s in a CFF DICT', [Builder.ToString]);
    end;
  finally
    Builder.Free;
  end;
end;

class function TCFFParser.ReadEntry(const Input: TCFFDataInput; const Log: TPdfLog): TCFFDictEntry;
begin
  Result := Default(TCFFDictEntry);
  // The operands are collected here and copied once at the operator; growing the result per operand would cost
  // quadratic time for an entry of many operands
  var Collected: array[0..MaxDictOperands - 1] of TCFFOperand;
  var Count := 0;
  var Operand: TCFFOperand;
  while True do
  begin
    const B0 = Input.ReadUnsignedByte;
    if B0 <= 21 then
    begin
      Result.OperatorName := ReadOperator(Input, B0);
      SetLength(Result.Operands, Count);
      for var Index := 0 to Count - 1 do
      begin
        Result.Operands[Index] := Collected[Index];
      end;
      Exit;
    end;

    if Count >= MaxDictOperands then
    begin
      raise EPdfParseException.Create('Too many operands in a CFF DICT entry');
    end;
    if B0 = 30 then
    begin
      Operand.Value := ReadRealNumber(Input, Log);
      Operand.IsInteger := False;
    end
    else if (B0 = 28) or (B0 = 29) or ((B0 >= 32) and (B0 <= 254)) then
    begin
      Operand.Value := ReadIntegerNumber(Input, B0);
      Operand.IsInteger := True;
    end
    else
    begin
      raise EPdfParseException.CreateFmt('invalid DICT data b0 byte: %d', [B0]);
    end;
    Collected[Count] := Operand;
    Inc(Count);
  end;
end;

class function TCFFParser.ReadDictData(const Input: TCFFDataInput; const Log: TPdfLog): TCFFDictData;
begin
  Result := TCFFDictData.Create;
  try
    while Input.HasRemaining do
    begin
      const Entry = ReadEntry(Input, Log);
      Result.Add(Entry);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TCFFParser.ReadDictData(const Input: TCFFDataInput; const Offset, DictSize: Integer;
                                 const Log: TPdfLog): TCFFDictData;
begin
  Result := TCFFDictData.Create;
  try
    if DictSize > 0 then
    begin
      ChargeBytes(DictSize);
      Input.SetPosition(Offset);
      const EndPosition = Int64(Offset) + DictSize;
      while Input.GetPosition < EndPosition do
      begin
        const Entry = ReadEntry(Input, Log);
        Result.Add(Entry);
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TCFFParser.ReadString(const Index: Integer): string;
begin
  if Index < 0 then
  begin
    raise EPdfParseException.Create('Invalid negative index when reading a string');
  end;
  if Index < FirstCustomSID then
  begin
    Exit(TCFFStandardString.GetName(Index));
  end;
  if Index - FirstCustomSID < Length(FStringIndex) then
  begin
    Exit(FStringIndex[Index - FirstCustomSID]);
  end;
  // Technically this maps to .notdef, but a unique name is needed
  Result := 'SID' + IntToStr(Index);
end;

function TCFFParser.TryGetString(const Dict: TCFFDictData; const Name: string; out Value: string): Boolean;
begin
  var Entry: TCFFDictEntry;
  Result := Dict.TryGetEntry(Name, Entry) and Entry.HasOperands;
  if Result then
  begin
    Value := ReadString(Entry.IntValue(0));
  end;
end;

function TCFFParser.ParseFont(const Input: TCFFDataInput; const Name: string; const TopDictBytes: TBytes): TCFFFont;
begin
  // Fonts may share a top DICT, so every one of them pays for reading it
  ChargeBytes(Length(TopDictBytes));
  const TopDictInput = TCFFDataInput.Create(TopDictBytes);
  try
    const TopDict = ReadDictData(TopDictInput, FLog);
    try
      var Entry: TCFFDictEntry;
      if TopDict.TryGetEntry(TCFFKeys.SyntheticBase, Entry) then
      begin
        raise EPdfParseException.Create('Synthetic Fonts are not supported');
      end;

      Result := CreateFont(TopDict);
      try
        FillFont(Input, Name, TopDict, Result);
      except
        Result.Free;
        raise;
      end;
    finally
      TopDict.Free;
    end;
  finally
    TopDictInput.Free;
  end;
end;

// A top DICT with a ROS entry is a CID-keyed font
function TCFFParser.CreateFont(const TopDict: TCFFDictData): TCFFFont;
begin
  var Registry: string;
  var Ordering: string;
  var Supplement: Integer;
  if TryReadROS(TopDict, Registry, Ordering, Supplement) then
  begin
    const CIDFont = TCFFCIDFont.Create;
    CIDFont.SetROS(Registry, Ordering, Supplement);
    Result := CIDFont;
  end
  else
  begin
    Result := TCFFType1Font.Create;
  end;
end;

function TCFFParser.TryReadROS(const TopDict: TCFFDictData; out Registry, Ordering: string;
                               out Supplement: Integer): Boolean;
begin
  Registry := '';
  Ordering := '';
  Supplement := 0;

  var Entry: TCFFDictEntry;
  Result := TopDict.TryGetEntry('ROS', Entry);
  if Result then
  begin
    if Length(Entry.Operands) < 3 then
    begin
      raise EPdfParseException.Create('ROS entry must have 3 elements');
    end;
    Registry := ReadString(Entry.IntValue(0));
    Ordering := ReadString(Entry.IntValue(1));
    Supplement := Entry.IntValue(2);
  end;
end;

procedure TCFFParser.FillFont(const Input: TCFFDataInput; const Name: string; const TopDict: TCFFDictData;
                              const Font: TCFFFont);
begin
  const IsCIDFont = Font is TCFFCIDFont;
  Font.SetName(Name);
  AddTopDictValues(Font, TopDict);
  const CharStrings = ReadCharStrings(Input, TopDict);
  ReadFontCharset(Input, TopDict, Length(CharStrings), Font, IsCIDFont);
  Font.SetCharStrings(CharStrings);
  if IsCIDFont then
  begin
    ParseCIDFontDicts(Input, TopDict, TCFFCIDFont(Font), Length(CharStrings));
  end
  else
  begin
    ParseType1Dicts(Input, TopDict, TCFFType1Font(Font));
  end;
end;

procedure TCFFParser.AddTopDictValues(const Font: TCFFFont; const TopDict: TCFFDictData);
begin
  for var Key in ['version', 'Notice', 'Copyright', 'FullName', 'FamilyName', 'Weight'] do
  begin
    var Text: string;
    if TryGetString(TopDict, Key, Text) then
    begin
      Font.AddTopDictString(Key, Text);
    end;
  end;

  const FixedPitch: Double = Ord(TopDict.GetBoolean(IsFixedPitchKey, False, FLog));
  Font.AddTopDictNumbers(IsFixedPitchKey, [FixedPitch]);
  Font.AddTopDictNumbers('ItalicAngle', [TopDict.GetNumber('ItalicAngle', 0)]);
  Font.AddTopDictNumbers('UnderlinePosition', [TopDict.GetNumber('UnderlinePosition', -100)]);
  Font.AddTopDictNumbers('UnderlineThickness', [TopDict.GetNumber('UnderlineThickness', 50)]);
  Font.AddTopDictNumbers('PaintType', [TopDict.GetNumber('PaintType', 0)]);
  Font.AddTopDictNumbers('CharstringType', [TopDict.GetNumber('CharstringType', 2)]);
  Font.AddTopDictNumbers('StrokeWidth', [TopDict.GetNumber('StrokeWidth', 0)]);

  var Values: TArray<Double>;
  if not TopDict.TryGetArray(TCFFKeys.FontMatrix, Values) then
  begin
    Values := [0.001, 0, 0, 0.001, 0, 0];
  end;
  Font.AddTopDictNumbers(TCFFKeys.FontMatrix, Values);

  if not TopDict.TryGetArray(TCFFKeys.FontBBox, Values) then
  begin
    Values := [0, 0, 0, 0];
  end;
  Font.AddTopDictNumbers(TCFFKeys.FontBBox, Values);

  var Entry: TCFFDictEntry;
  if TopDict.TryGetEntry('UniqueID', Entry) and Entry.HasOperands then
  begin
    Font.AddTopDictNumbers('UniqueID', [Entry.Operands[0].Value]);
  end;
  if TopDict.TryGetArray('XUID', Values) then
  begin
    Font.AddTopDictNumbers('XUID', Values);
  end;
end;

function TCFFParser.ReadCharStrings(const Input: TCFFDataInput; const TopDict: TCFFDictData): TArray<TBytes>;
begin
  var Entry: TCFFDictEntry;
  if (not TopDict.TryGetEntry('CharStrings', Entry)) or (not Entry.HasOperands) then
  begin
    raise EPdfParseException.Create('CharStrings is missing or empty');
  end;
  Input.SetPosition(Entry.IntValue(0));
  Result := ReadSharedIndexData(Input);
end;

class function TCFFParser.CreateEmptyCIDCharset(const GlyphCount: Integer): TCFFCharsetCID;
begin
  Result := TCFFCharsetCID.Create;
  Result.AddCID(0, 0);
  // Adobe Reader treats the CID as the GID (PDFBOX-2571)
  for var GID := 1 to GlyphCount do
  begin
    Result.AddCID(GID, GID);
  end;
end;

// PDFBox gives a CID font an empty Type 1 charset here, whose CID lookups raise an exception; an empty CID charset is the
// same without the failure
class function TCFFParser.CreateEmptyCharset(const IsCIDFont: Boolean): TCFFCharset;
begin
  if IsCIDFont then
  begin
    Result := CreateEmptyCIDCharset(0);
  end
  else
  begin
    const Empty = TCFFCharsetType1.Create;
    Empty.AddSID(0, 0, NotDefName);
    Result := Empty;
  end;
end;

procedure TCFFParser.ReadFontCharset(const Input: TCFFDataInput; const TopDict: TCFFDictData;
                                     const CharStringCount: Integer; const Font: TCFFFont; const IsCIDFont: Boolean);
begin
  var Entry: TCFFDictEntry;
  if (not TopDict.TryGetEntry('charset', Entry)) or (not Entry.HasOperands) then
  begin
    if IsCIDFont then
    begin
      // A CID font with no charset does not default to any predefined charset
      ChargeEntries(CharStringCount);
      Font.SetCharset(CreateEmptyCIDCharset(CharStringCount), True);
    end
    else
    begin
      Font.SetCharset(TCFFISOAdobeCharset.Instance, False);
    end;
    Exit;
  end;

  const CharsetId = Entry.IntValue(0);
  if (not IsCIDFont) and (CharsetId = 0) then
  begin
    Font.SetCharset(TCFFISOAdobeCharset.Instance, False);
  end
  else if (not IsCIDFont) and (CharsetId = 1) then
  begin
    Font.SetCharset(TCFFExpertCharset.Instance, False);
  end
  else if (not IsCIDFont) and (CharsetId = 2) then
  begin
    Font.SetCharset(TCFFExpertSubsetCharset.Instance, False);
  end
  else if CharStringCount > 0 then
  begin
    Input.SetPosition(CharsetId);
    ChargeEntries(CharStringCount);
    const Charset = ReadCharset(Input, CharStringCount, IsCIDFont);
    Font.SetCharset(Charset, True);
  end
  else
  begin
    if Assigned(FLog) then
    begin
      FLog.Debug('Couldn''t read CharStrings index - returning empty charset instead');
    end;
    Font.SetCharset(CreateEmptyCharset(IsCIDFont), True);
  end;
end;

procedure TCFFParser.ParseType1Dicts(const Input: TCFFDataInput; const TopDict: TCFFDictData;
                                     const Font: TCFFType1Font);
begin
  ReadFontEncoding(Input, TopDict, Font);

  var PrivateEntry: TCFFDictEntry;
  if (not TopDict.TryGetEntry(TCFFKeys.Private_, PrivateEntry)) or (Length(PrivateEntry.Operands) < 2) then
  begin
    raise EPdfParseException.CreateFmt('Private dictionary entry missing for font %s', [Font.Name]);
  end;

  const PrivateOffset = PrivateEntry.IntValue(1);
  const PrivateSize = PrivateEntry.IntValue(0);
  const PrivateDict = ReadDictData(Input, PrivateOffset, PrivateSize, FLog);
  try
    ReadPrivateDict(PrivateDict, Font.PrivateDict);
    Font.SetLocalSubrs(ReadLocalSubrs(Input, PrivateDict, PrivateOffset));
  finally
    PrivateDict.Free;
  end;
end;

// The local subroutines of a private DICT; empty when it has none
function TCFFParser.ReadLocalSubrs(const Input: TCFFDataInput; const PrivateDict: TCFFDictData;
                                   const PrivateOffset: Integer): TArray<TBytes>;
begin
  Result := nil;
  var SubrsEntry: TCFFDictEntry;
  const HasSubrs = (PrivateDict.TryGetEntry('Subrs', SubrsEntry) and SubrsEntry.HasOperands and
                    SubrsEntry.Operands[0].IsInteger and (SubrsEntry.IntValue(0) > 0));
  if HasSubrs then
  begin
    const SubrsPosition = Int64(PrivateOffset) + SubrsEntry.IntValue(0);
    if SubrsPosition > MaxInt then
    begin
      raise EPdfParseException.Create('The local subroutines lie outside the CFF data');
    end;
    Input.SetPosition(Integer(SubrsPosition));
    Result := ReadSharedIndexData(Input);
  end;
end;

procedure TCFFParser.ReadFontEncoding(const Input: TCFFDataInput; const TopDict: TCFFDictData;
                                      const Font: TCFFType1Font);
begin
  var Entry: TCFFDictEntry;
  var EncodingId := 0;
  if TopDict.TryGetEntry('Encoding', Entry) and Entry.HasOperands then
  begin
    EncodingId := Entry.IntValue(0);
  end;

  case EncodingId of
    0:
      Font.SetEncoding(TCFFStandardEncoding.Instance, False);
    1:
      Font.SetEncoding(TCFFExpertEncoding.Instance, False);
    else
      begin
        Input.SetPosition(EncodingId);
        Font.SetEncoding(ReadEncoding(Input, Font.Charset), True);
      end;
  end;
end;

procedure TCFFParser.ReadPrivateDict(const PrivateDict: TCFFDictData; const Target: TCFFDictionary);
begin
  AddDeltaNumbers(PrivateDict, Target, 'BlueValues');
  AddDeltaNumbers(PrivateDict, Target, 'OtherBlues');
  AddDeltaNumbers(PrivateDict, Target, 'FamilyBlues');
  AddDeltaNumbers(PrivateDict, Target, 'FamilyOtherBlues');
  AddNumber(PrivateDict, Target, 'BlueScale', 0.039625);
  AddNumber(PrivateDict, Target, 'BlueShift', 7);
  AddNumber(PrivateDict, Target, 'BlueFuzz', 1);
  AddOptionalNumber(PrivateDict, Target, 'StdHW');
  AddOptionalNumber(PrivateDict, Target, 'StdVW');
  AddDeltaNumbers(PrivateDict, Target, 'StemSnapH');
  AddDeltaNumbers(PrivateDict, Target, 'StemSnapV');
  const ForceBold: Double = Ord(PrivateDict.GetBoolean('ForceBold', False, FLog));
  Target.AddNumbers('ForceBold', [ForceBold]);
  AddNumber(PrivateDict, Target, 'LanguageGroup', 0);
  AddNumber(PrivateDict, Target, 'ExpansionFactor', 0.06);
  AddNumber(PrivateDict, Target, 'initialRandomSeed', 0);
  AddNumber(PrivateDict, Target, 'defaultWidthX', 0);
  AddNumber(PrivateDict, Target, 'nominalWidthX', 0);
end;

procedure TCFFParser.AddDeltaNumbers(const PrivateDict: TCFFDictData; const Target: TCFFDictionary; const Name: string);
begin
  var Values: TArray<Double>;
  if PrivateDict.TryGetDelta(Name, Values) then
  begin
    Target.AddNumbers(Name, Values);
  end;
end;

procedure TCFFParser.AddNumber(const PrivateDict: TCFFDictData; const Target: TCFFDictionary; const Name: string;
                               const Default: Double);
begin
  Target.AddNumbers(Name, [PrivateDict.GetNumber(Name, Default)]);
end;

procedure TCFFParser.AddOptionalNumber(const PrivateDict: TCFFDictData; const Target: TCFFDictionary; const Name: string);
begin
  var Entry: TCFFDictEntry;
  if PrivateDict.TryGetEntry(Name, Entry) and Entry.HasOperands then
  begin
    Target.AddNumbers(Name, [Entry.Operands[0].Value]);
  end;
end;

procedure TCFFParser.ParseCIDFontDicts(const Input: TCFFDataInput; const TopDict: TCFFDictData;
                                       const Font: TCFFCIDFont; const GlyphCount: Integer);
begin
  // In a CID-keyed font the private DICT is not in the top DICT but in a font DICT, found through FDArray and FDSelect
  var Entry: TCFFDictEntry;
  if (not TopDict.TryGetEntry('FDArray', Entry)) or (not Entry.HasOperands) then
  begin
    raise EPdfParseException.Create('FDArray is missing for a CIDKeyed Font.');
  end;

  Input.SetPosition(Entry.IntValue(0));
  const FontDictBytes = ReadSharedIndexData(Input);
  if Length(FontDictBytes) = 0 then
  begin
    raise EPdfParseException.Create('Font dict index is missing for a CIDKeyed Font');
  end;
  if Length(FontDictBytes) > MaxFontDicts then
  begin
    raise EPdfParseException.CreateFmt('The font has %d font DICTs, more than the %d that FDSelect can select',
                                       [Length(FontDictBytes), MaxFontDicts]);
  end;

  const FontDicts = TObjectList<TCFFDictionary>.Create(True);
  const PrivateDicts = TObjectList<TCFFDictionary>.Create(True);
  var FdSelect: TCFFFDSelect := nil;
  try
    ReadCIDDicts(Input, FontDictBytes, FontDicts, PrivateDicts);

    if (not TopDict.TryGetEntry('FDSelect', Entry)) or (not Entry.HasOperands) then
    begin
      raise EPdfParseException.Create('FDSelect is missing or empty');
    end;
    Input.SetPosition(Entry.IntValue(0));
    FdSelect := ReadFDSelect(Input, GlyphCount);
    WarnAboutUnknownFDs(FdSelect, FontDicts.Count);
  except
    FdSelect.Free;
    PrivateDicts.Free;
    FontDicts.Free;
    raise;
  end;

  Font.SetFontDicts(FontDicts);
  Font.SetPrivDicts(PrivateDicts);
  Font.SetFdSelect(FdSelect);
  ApplyCIDFontMatrix(TopDict, Font);
end;

procedure TCFFParser.ReadCIDDicts(const Input: TCFFDataInput; const FontDictBytes: TArray<TBytes>;
                                  const FontDicts, PrivateDicts: TObjectList<TCFFDictionary>);
begin
  var IsPrivateDictPopulated := False;
  for var Bytes in FontDictBytes do
  begin
    const DictInput = TCFFDataInput.Create(Bytes);
    try
      const FontDict = ReadDictData(DictInput, FLog);
      try
        FontDicts.Add(ReadCIDFontDict(FontDict));

        var PrivateEntry: TCFFDictEntry;
        const HasPrivateDict = (FontDict.TryGetEntry(TCFFKeys.Private_, PrivateEntry) and (Length(PrivateEntry.Operands) >= 2));
        if HasPrivateDict then
        begin
          PrivateDicts.Add(ReadCIDPrivateDict(Input, PrivateEntry));
          IsPrivateDictPopulated := True;
        end
        else
        begin
          // PDFBOX-5843: no private DICT leaves an empty one, so the indexes of both lists stay together
          PrivateDicts.Add(TCFFDictionary.Create);
        end;
      finally
        FontDict.Free;
      end;
    finally
      DictInput.Free;
    end;
  end;

  if not IsPrivateDictPopulated then
  begin
    raise EPdfParseException.Create('Font DICT invalid without "Private" entry');
  end;
end;

function TCFFParser.ReadCIDFontDict(const FontDict: TCFFDictData): TCFFDictionary;
begin
  Result := TCFFDictionary.Create;
  try
    var Name: string;
    if TryGetString(FontDict, 'FontName', Name) then
    begin
      Result.AddString('FontName', Name);
    end;
    Result.AddNumbers('FontType', [FontDict.GetNumber('FontType', 0)]);

    var Values: TArray<Double>;
    if FontDict.TryGetArray(TCFFKeys.FontBBox, Values) then
    begin
      Result.AddNumbers(TCFFKeys.FontBBox, Values);
    end;
    if FontDict.TryGetArray(TCFFKeys.FontMatrix, Values) then
    begin
      Result.AddNumbers(TCFFKeys.FontMatrix, Values);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TCFFParser.ReadCIDPrivateDict(const Input: TCFFDataInput; const PrivateEntry: TCFFDictEntry): TCFFDictionary;
begin
  const PrivateOffset = PrivateEntry.IntValue(1);
  const PrivateSize = PrivateEntry.IntValue(0);
  if PrivateSize > MaxCIDPrivateDictSize then
  begin
    raise EPdfParseException.CreateFmt('The private DICT of %d bytes is too large', [PrivateSize]);
  end;

  const PrivateDict = ReadDictData(Input, PrivateOffset, PrivateSize, FLog);
  try
    Result := TCFFDictionary.Create;
    try
      ReadPrivateDict(PrivateDict, Result);
      Result.SetSubrs(ReadLocalSubrs(Input, PrivateDict, PrivateOffset));
    except
      Result.Free;
      raise;
    end;
  finally
    PrivateDict.Free;
  end;
end;

function TCFFParser.ReadFDSelect(const Input: TCFFDataInput; const GlyphCount: Integer): TCFFFDSelect;
begin
  const Format = Input.ReadUnsignedByte;
  case Format of
    0:
      Result := ReadFormat0FDSelect(Input, GlyphCount);
    3:
      Result := ReadFormat3FDSelect(Input);
    else
      raise EPdfParseException.CreateFmt('Unsupported FDSelect format %d', [Format]);
  end;
end;

function TCFFParser.ReadFormat0FDSelect(const Input: TCFFDataInput; const GlyphCount: Integer): TCFFFormat0FDSelect;
begin
  const Remaining = Input.GetLength - Input.GetPosition;
  if GlyphCount > Remaining then
  begin
    raise EPdfParseException.CreateFmt(FDSelectTooShortMessage, [GlyphCount, Remaining]);
  end;
  ChargeEntries(GlyphCount);
  Result := TCFFFormat0FDSelect.Create(Input.ReadBytes(GlyphCount));
end;

function TCFFParser.ReadFormat3FDSelect(const Input: TCFFDataInput): TCFFFormat3FDSelect;
begin
  const RangeCount = Input.ReadUnsignedShort;
  // Each range is three bytes and the sentinel two
  const Needed = (RangeCount * 3) + 2;
  const Remaining = Input.GetLength - Input.GetPosition;
  if Needed > Remaining then
  begin
    raise EPdfParseException.CreateFmt(FDSelectTooShortMessage, [Needed, Remaining]);
  end;
  ChargeEntries(RangeCount);

  var Ranges: TArray<TCFFFormat3Range>;
  SetLength(Ranges, RangeCount);
  for var Index := 0 to RangeCount - 1 do
  begin
    Ranges[Index].First := Input.ReadUnsignedShort;
    Ranges[Index].FD := Input.ReadUnsignedByte;
  end;
  const Sentinel = Input.ReadUnsignedShort;
  Result := TCFFFormat3FDSelect.Create(Ranges, Sentinel);
end;

procedure TCFFParser.WarnAboutUnknownFDs(const FdSelect: TCFFFDSelect; const FontDictCount: Integer);
begin
  const HighestFD = FdSelect.MaxFDIndex;
  if (HighestFD >= FontDictCount) and Assigned(FLog) then
  begin
    FLog.Warning('The FDSelect refers to font DICT %d, but the font has %d font DICTs; the glyphs get the default widths',
                 [HighestFD, FontDictCount]);
  end;
end;

// Some malformed fonts have the FontMatrix in their font DICT (PDFBOX-2495)
procedure TCFFParser.ApplyCIDFontMatrix(const TopDict: TCFFDictData; const Font: TCFFCIDFont);
begin
  var FontDictMatrix: TArray<Double>;
  const HasFontDictMatrix = ((Font.FontDicts.Count > 0) and Font.FontDicts[0].TryGetNumbers(TCFFKeys.FontMatrix, FontDictMatrix));
  if not HasFontDictMatrix then
  begin
    Exit;
  end;

  var Matrix: TArray<Double>;
  if TopDict.TryGetArray(TCFFKeys.FontMatrix, Matrix) then
  begin
    ConcatenateFontMatrix(Font, Matrix, FontDictMatrix);
  end
  else
  begin
    Font.AddTopDictNumbers(TCFFKeys.FontMatrix, FontDictMatrix);
  end;
end;

// The matrix of the top DICT is multiplied by that of the font DICT (PDFBOX-3579). The second entry of the result uses
// d1 where a matrix product has d2; that is how PDFBox does it, so the widths and positions come out the same.
procedure TCFFParser.ConcatenateFontMatrix(const Font: TCFFCIDFont; const Matrix, FontDictMatrix: TArray<Double>);
begin
  const HasSixNumbers = ((Length(Matrix) >= 6) and (Length(FontDictMatrix) >= 6));
  if not HasSixNumbers then
  begin
    if Assigned(FLog) then
    begin
      FLog.Warning('A FontMatrix with fewer than 6 numbers is not combined with the FontMatrix of the font DICT');
    end;
    Exit;
  end;

  const A1 = Matrix[0];
  const B1 = Matrix[1];
  const C1 = Matrix[2];
  const D1 = Matrix[3];
  const X1 = Matrix[4];
  const Y1 = Matrix[5];
  const A2 = FontDictMatrix[0];
  const B2 = FontDictMatrix[1];
  const C2 = FontDictMatrix[2];
  const D2 = FontDictMatrix[3];
  const X2 = FontDictMatrix[4];
  const Y2 = FontDictMatrix[5];
  Font.AddTopDictNumbers(TCFFKeys.FontMatrix, [(A1 * A2) + (B1 * C2), (A1 * B2) + (B1 * D1), (C1 * A2) + (D1 * C2),
                                        (C1 * B2) + (D1 * D2), (X1 * A2) + (Y1 * C2) + X2, (X1 * B2) + (Y1 * D2) + Y2]);
end;

function TCFFParser.ReadCharset(const Input: TCFFDataInput; const GlyphCount: Integer;
                                const IsCIDFont: Boolean): TCFFCharset;
begin
  const Format = Input.ReadUnsignedByte;
  if Format > 2 then
  begin
    raise EPdfParseException.CreateFmt('Incorrect charset format %d', [Format]);
  end;

  if IsCIDFont then
  begin
    Result := ReadCIDCharset(Input, GlyphCount, Format);
  end
  else
  begin
    Result := ReadType1Charset(Input, GlyphCount, Format);
  end;
end;

function TCFFParser.ReadType1Charset(const Input: TCFFDataInput; const GlyphCount, Format: Integer): TCFFCharsetType1;
begin
  Result := TCFFCharsetType1.Create;
  try
    case Format of
      0:
        ReadFormat0Charset(Input, GlyphCount, Result);
      1:
        ReadFormat1Charset(Input, GlyphCount, Result);
      else
        ReadFormat2Charset(Input, GlyphCount, Result);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TCFFParser.ReadCIDCharset(const Input: TCFFDataInput; const GlyphCount, Format: Integer): TCFFCharsetCID;
begin
  if Format = 0 then
  begin
    Result := TCFFCharsetCID.Create;
  end
  else
  begin
    Result := TCFFRangeCharsetCID.Create;
  end;

  try
    Result.AddCID(0, 0);
    if Format = 0 then
    begin
      for var GID := 1 to GlyphCount - 1 do
      begin
        Result.AddCID(GID, Input.ReadUnsignedShort);
      end;
    end
    else
    begin
      ReadCIDRanges(Input, GlyphCount, Format = 1, TCFFRangeCharsetCID(Result));
    end;
  except
    Result.Free;
    raise;
  end;
end;

// Every range takes at least three bytes and covers at least one glyph, so the loop ends with the data or the glyphs
procedure TCFFParser.ReadCIDRanges(const Input: TCFFDataInput; const GlyphCount: Integer; const IsLeftOneByte: Boolean;
                                   const Charset: TCFFRangeCharsetCID);
begin
  var GID := 1;
  while GID < GlyphCount do
  begin
    const First = Input.ReadUnsignedShort;
    var Left: Integer;
    if IsLeftOneByte then
    begin
      Left := Input.ReadUnsignedByte;
    end
    else
    begin
      Left := Input.ReadUnsignedShort;
    end;
    ChargeEntries(1);
    Charset.AddRangeMapping(GID, First, Left);
    Inc(GID, Left + 1);
  end;
  Charset.Freeze;
end;

procedure TCFFParser.ReadFormat0Charset(const Input: TCFFDataInput; const GlyphCount: Integer;
                                        const Charset: TCFFCharsetType1);
begin
  Charset.AddSID(0, 0, NotDefName);
  for var GID := 1 to GlyphCount - 1 do
  begin
    const SID = Input.ReadUnsignedShort;
    Charset.AddSID(GID, SID, ReadString(SID));
  end;
end;

procedure TCFFParser.ReadFormat1Charset(const Input: TCFFDataInput; const GlyphCount: Integer;
                                        const Charset: TCFFCharsetType1);
begin
  Charset.AddSID(0, 0, NotDefName);
  var GID := 1;
  while GID < GlyphCount do
  begin
    const First = Input.ReadUnsignedShort;
    const Count = Input.ReadUnsignedByte + 1;
    AddRangeToCharset(Charset, GID, First, Count, GlyphCount);
    Inc(GID, Count);
  end;
end;

procedure TCFFParser.ReadFormat2Charset(const Input: TCFFDataInput; const GlyphCount: Integer;
                                        const Charset: TCFFCharsetType1);
begin
  Charset.AddSID(0, 0, NotDefName);
  var GID := 1;
  while GID < GlyphCount do
  begin
    const First = Input.ReadUnsignedShort;
    const Count = Input.ReadUnsignedShort + 1;
    AddRangeToCharset(Charset, GID, First, Count, GlyphCount);
    Inc(GID, Count);
  end;
end;

// PDFBox also maps the glyphs of a range beyond the last glyph. That would let a few bytes of data make 65536 entries per
// range, so the range stops at the glyph count.
procedure TCFFParser.AddRangeToCharset(const Charset: TCFFCharsetType1; const FirstGID, FirstSID, Count,
                                       GlyphCount: Integer);
begin
  const Fitting = Min(Count, GlyphCount - FirstGID);
  for var Offset := 0 to Fitting - 1 do
  begin
    const SID = FirstSID + Offset;
    Charset.AddSID(FirstGID + Offset, SID, ReadString(SID));
  end;
end;

function TCFFParser.ReadEncoding(const Input: TCFFDataInput; const Charset: TCFFCharset): TCFFBuiltInEncoding;
begin
  const Format = Input.ReadUnsignedByte;
  const BaseFormat = Format and $7F;
  if BaseFormat > 1 then
  begin
    raise EPdfParseException.CreateFmt('Invalid encoding base format %d', [BaseFormat]);
  end;

  if BaseFormat = 0 then
  begin
    const Format0 = TCFFFormat0Encoding.Create(Input.ReadUnsignedByte);
    Result := Format0;
    try
      ReadFormat0Encoding(Input, Charset, Format0);
    except
      Result.Free;
      raise;
    end;
  end
  else
  begin
    const Format1 = TCFFFormat1Encoding.Create(Input.ReadUnsignedByte);
    Result := Format1;
    try
      ReadFormat1Encoding(Input, Charset, Format1);
    except
      Result.Free;
      raise;
    end;
  end;

  if (Format and $80) <> 0 then
  begin
    try
      ReadSupplement(Input, Result);
    except
      Result.Free;
      raise;
    end;
  end;
end;

procedure TCFFParser.ReadFormat0Encoding(const Input: TCFFDataInput; const Charset: TCFFCharset;
                                         const Encoding: TCFFFormat0Encoding);
begin
  Encoding.Add(0, 0, NotDefName);
  for var GID := 1 to Encoding.NCodes do
  begin
    const Code = Input.ReadUnsignedByte;
    const SID = Charset.GetSIDForGID(GID);
    Encoding.Add(Code, SID, ReadString(SID));
  end;
end;

procedure TCFFParser.ReadFormat1Encoding(const Input: TCFFDataInput; const Charset: TCFFCharset;
                                         const Encoding: TCFFFormat1Encoding);
begin
  Encoding.Add(0, 0, NotDefName);
  var GID := 1;
  for var Range := 1 to Encoding.NRanges do
  begin
    const First = Input.ReadUnsignedByte;
    const Left = Input.ReadUnsignedByte;
    for var Offset := 0 to Left do
    begin
      const SID = Charset.GetSIDForGID(GID);
      Encoding.Add(First + Offset, SID, ReadString(SID));
      Inc(GID);
    end;
  end;
end;

procedure TCFFParser.ReadSupplement(const Input: TCFFDataInput; const Encoding: TCFFBuiltInEncoding);
begin
  const Count = Input.ReadUnsignedByte;
  var Supplement: TArray<TCFFSupplement>;
  SetLength(Supplement, Count);
  for var Index := 0 to Count - 1 do
  begin
    Supplement[Index].Code := Input.ReadUnsignedByte;
    Supplement[Index].SID := Input.ReadUnsignedShort;
    Supplement[Index].Name := ReadString(Supplement[Index].SID);
  end;
  Encoding.AddSupplement(Supplement);
end;

end.
