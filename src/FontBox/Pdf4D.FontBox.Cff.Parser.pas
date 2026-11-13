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

  private
    FLog: TPdfLog;
    FStringIndex: TArray<string>;

    class function Latin1String(const Bytes: TBytes): string; static;
    class function ResolveCffData(const Data: TBytes): TBytes; static;
    class function FindCffTable(const Input: TCFFDataInput): TBytes; static;
    class function ReadTagName(const Input: TCFFDataInput): string; static;
    class function ReadTableField(const Input: TCFFDataInput): Int64; static;
    class function ReadOffSize(const Input: TCFFDataInput): Integer; static;
    class procedure ReadHeader(const Input: TCFFDataInput); static;

    class function ReadIndexDataOffsets(const Input: TCFFDataInput): TArray<Int64>; static;
    class function ReadIndexData(const Input: TCFFDataInput): TArray<TBytes>; static;
    class function ReadStringIndexData(const Input: TCFFDataInput): TArray<string>; static;

    class function OperatorName(const B0, B1: Integer): string; static;
    class function ReadOperator(const Input: TCFFDataInput; const B0: Integer): string; static;
    class function ReadIntegerNumber(const Input: TCFFDataInput; const B0: Integer): Integer; static;
    class function ReadRealNumber(const Input: TCFFDataInput; const Log: TPdfLog): Double; static;
    class function ReadEntry(const Input: TCFFDataInput; const Log: TPdfLog): TCFFDictEntry; static;
    class function ReadDictData(const Input: TCFFDataInput; const Log: TPdfLog): TCFFDictData; overload; static;
    class function ReadDictData(const Input: TCFFDataInput; const Offset, DictSize: Integer;
                                const Log: TPdfLog): TCFFDictData; overload; static;

    function ReadString(const Index: Integer): string;
    function TryGetString(const Dict: TCFFDictData; const Name: string; out Value: string): Boolean;

    function ParseFont(const Input: TCFFDataInput; const Name: string; const TopDictBytes: TBytes): TCFFFont;
    procedure RejectCIDFont(const TopDict: TCFFDictData);
    procedure AddTopDictValues(const Font: TCFFFont; const TopDict: TCFFDictData);
    function ReadCharStrings(const Input: TCFFDataInput; const TopDict: TCFFDictData): TArray<TBytes>;
    procedure ReadFontCharset(const Input: TCFFDataInput; const TopDict: TCFFDictData; const CharStringCount: Integer;
                              const Font: TCFFFont);
    procedure ParseType1Dicts(const Input: TCFFDataInput; const TopDict: TCFFDictData; const Font: TCFFType1Font);
    procedure ReadFontEncoding(const Input: TCFFDataInput; const TopDict: TCFFDictData; const Font: TCFFType1Font);
    procedure ReadPrivateDict(const PrivateDict: TCFFDictData; const Font: TCFFType1Font);
    procedure AddDeltaNumbers(const PrivateDict: TCFFDictData; const Font: TCFFType1Font; const Name: string);
    procedure AddNumber(const PrivateDict: TCFFDictData; const Font: TCFFType1Font; const Name: string;
                        const Default: Double);
    procedure AddOptionalNumber(const PrivateDict: TCFFDictData; const Font: TCFFType1Font; const Name: string);

    function ReadCharset(const Input: TCFFDataInput; const GlyphCount: Integer): TCFFCharsetType1;
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

    // The caller owns the list and the fonts in it. A CID-keyed font raises EPdfUnsupportedFeatureException.
    function Parse(const Data: TBytes): TObjectList<TCFFFont>;
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
  const Input = TCFFDataInput.Create(ResolveCffData(Data));
  try
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

    Result := TObjectList<TCFFFont>.Create(True);
    try
      for var Index := 0 to High(NameIndex) do
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

class function TCFFParser.ReadIndexDataOffsets(const Input: TCFFDataInput): TArray<Int64>;
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

class function TCFFParser.ReadIndexData(const Input: TCFFDataInput): TArray<TBytes>;
begin
  const Offsets = ReadIndexDataOffsets(Input);
  if Length(Offsets) = 0 then
  begin
    Exit(nil);
  end;

  const Count = Length(Offsets) - 1;
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

class function TCFFParser.ReadStringIndexData(const Input: TCFFDataInput): TArray<string>;
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
  var Operand: TCFFOperand;
  while True do
  begin
    const B0 = Input.ReadUnsignedByte;
    if B0 <= 21 then
    begin
      Result.OperatorName := ReadOperator(Input, B0);
      Exit;
    end;

    if Length(Result.Operands) >= MaxDictOperands then
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
    Result.Operands := Result.Operands + [Operand];
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

class function TCFFParser.ReadDictData(const Input: TCFFDataInput; const Offset, DictSize: Integer;
                                       const Log: TPdfLog): TCFFDictData;
begin
  Result := TCFFDictData.Create;
  try
    if DictSize > 0 then
    begin
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
  const TopDictInput = TCFFDataInput.Create(TopDictBytes);
  try
    const TopDict = ReadDictData(TopDictInput, FLog);
    try
      var Entry: TCFFDictEntry;
      if TopDict.TryGetEntry('SyntheticBase', Entry) then
      begin
        raise EPdfParseException.Create('Synthetic Fonts are not supported');
      end;
      RejectCIDFont(TopDict);

      const Font = TCFFType1Font.Create;
      try
        Font.SetName(Name);
        AddTopDictValues(Font, TopDict);
        const CharStrings = ReadCharStrings(Input, TopDict);
        ReadFontCharset(Input, TopDict, Length(CharStrings), Font);
        Font.SetCharStrings(CharStrings);
        ParseType1Dicts(Input, TopDict, Font);
      except
        Font.Free;
        raise;
      end;
      Result := Font;
    finally
      TopDict.Free;
    end;
  finally
    TopDictInput.Free;
  end;
end;

procedure TCFFParser.RejectCIDFont(const TopDict: TCFFDictData);
begin
  var Entry: TCFFDictEntry;
  if TopDict.TryGetEntry('ROS', Entry) then
  begin
    if Length(Entry.Operands) < 3 then
    begin
      raise EPdfParseException.Create('ROS entry must have 3 elements');
    end;
    raise EPdfUnsupportedFeatureException.Create('CID-keyed CFF fonts are not supported');
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
  if not TopDict.TryGetArray('FontMatrix', Values) then
  begin
    Values := [0.001, 0, 0, 0.001, 0, 0];
  end;
  Font.AddTopDictNumbers('FontMatrix', Values);

  if not TopDict.TryGetArray('FontBBox', Values) then
  begin
    Values := [0, 0, 0, 0];
  end;
  Font.AddTopDictNumbers('FontBBox', Values);

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
  Result := ReadIndexData(Input);
end;

procedure TCFFParser.ReadFontCharset(const Input: TCFFDataInput; const TopDict: TCFFDictData;
                                     const CharStringCount: Integer; const Font: TCFFFont);
begin
  var Entry: TCFFDictEntry;
  if (not TopDict.TryGetEntry('charset', Entry)) or (not Entry.HasOperands) then
  begin
    Font.SetCharset(TCFFISOAdobeCharset.Instance, False);
    Exit;
  end;

  const CharsetId = Entry.IntValue(0);
  case CharsetId of
    0:
      Font.SetCharset(TCFFISOAdobeCharset.Instance, False);
    1:
      Font.SetCharset(TCFFExpertCharset.Instance, False);
    2:
      Font.SetCharset(TCFFExpertSubsetCharset.Instance, False);
    else
      begin
        if CharStringCount > 0 then
        begin
          Input.SetPosition(CharsetId);
          Font.SetCharset(ReadCharset(Input, CharStringCount), True);
        end
        else
        begin
          if Assigned(FLog) then
          begin
            FLog.Debug('Couldn''t read CharStrings index - returning empty charset instead');
          end;
          const Empty = TCFFCharsetType1.Create;
          Empty.AddSID(0, 0, NotDefName);
          Font.SetCharset(Empty, True);
        end;
      end;
  end;
end;

procedure TCFFParser.ParseType1Dicts(const Input: TCFFDataInput; const TopDict: TCFFDictData;
                                     const Font: TCFFType1Font);
begin
  ReadFontEncoding(Input, TopDict, Font);

  var PrivateEntry: TCFFDictEntry;
  if (not TopDict.TryGetEntry('Private', PrivateEntry)) or (Length(PrivateEntry.Operands) < 2) then
  begin
    raise EPdfParseException.CreateFmt('Private dictionary entry missing for font %s', [Font.Name]);
  end;

  const PrivateOffset = PrivateEntry.IntValue(1);
  const PrivateSize = PrivateEntry.IntValue(0);
  const PrivateDict = ReadDictData(Input, PrivateOffset, PrivateSize, FLog);
  try
    ReadPrivateDict(PrivateDict, Font);

    var SubrsEntry: TCFFDictEntry;
    if PrivateDict.TryGetEntry('Subrs', SubrsEntry) and SubrsEntry.HasOperands and SubrsEntry.Operands[0].IsInteger
       and (SubrsEntry.IntValue(0) > 0) then
    begin
      const SubrsPosition = Int64(PrivateOffset) + SubrsEntry.IntValue(0);
      if SubrsPosition > MaxInt then
      begin
        raise EPdfParseException.Create('The local subroutines lie outside the CFF data');
      end;
      Input.SetPosition(Integer(SubrsPosition));
      Font.SetLocalSubrs(ReadIndexData(Input));
    end;
  finally
    PrivateDict.Free;
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

procedure TCFFParser.ReadPrivateDict(const PrivateDict: TCFFDictData; const Font: TCFFType1Font);
begin
  AddDeltaNumbers(PrivateDict, Font, 'BlueValues');
  AddDeltaNumbers(PrivateDict, Font, 'OtherBlues');
  AddDeltaNumbers(PrivateDict, Font, 'FamilyBlues');
  AddDeltaNumbers(PrivateDict, Font, 'FamilyOtherBlues');
  AddNumber(PrivateDict, Font, 'BlueScale', 0.039625);
  AddNumber(PrivateDict, Font, 'BlueShift', 7);
  AddNumber(PrivateDict, Font, 'BlueFuzz', 1);
  AddOptionalNumber(PrivateDict, Font, 'StdHW');
  AddOptionalNumber(PrivateDict, Font, 'StdVW');
  AddDeltaNumbers(PrivateDict, Font, 'StemSnapH');
  AddDeltaNumbers(PrivateDict, Font, 'StemSnapV');
  const ForceBold: Double = Ord(PrivateDict.GetBoolean('ForceBold', False, FLog));
  Font.AddPrivateDictNumbers('ForceBold', [ForceBold]);
  AddNumber(PrivateDict, Font, 'LanguageGroup', 0);
  AddNumber(PrivateDict, Font, 'ExpansionFactor', 0.06);
  AddNumber(PrivateDict, Font, 'initialRandomSeed', 0);
  AddNumber(PrivateDict, Font, 'defaultWidthX', 0);
  AddNumber(PrivateDict, Font, 'nominalWidthX', 0);
end;

procedure TCFFParser.AddDeltaNumbers(const PrivateDict: TCFFDictData; const Font: TCFFType1Font; const Name: string);
begin
  var Values: TArray<Double>;
  if PrivateDict.TryGetDelta(Name, Values) then
  begin
    Font.AddPrivateDictNumbers(Name, Values);
  end;
end;

procedure TCFFParser.AddNumber(const PrivateDict: TCFFDictData; const Font: TCFFType1Font; const Name: string;
                               const Default: Double);
begin
  Font.AddPrivateDictNumbers(Name, [PrivateDict.GetNumber(Name, Default)]);
end;

procedure TCFFParser.AddOptionalNumber(const PrivateDict: TCFFDictData; const Font: TCFFType1Font; const Name: string);
begin
  var Entry: TCFFDictEntry;
  if PrivateDict.TryGetEntry(Name, Entry) and Entry.HasOperands then
  begin
    Font.AddPrivateDictNumbers(Name, [Entry.Operands[0].Value]);
  end;
end;

function TCFFParser.ReadCharset(const Input: TCFFDataInput; const GlyphCount: Integer): TCFFCharsetType1;
begin
  const Format = Input.ReadUnsignedByte;
  if Format > 2 then
  begin
    raise EPdfParseException.CreateFmt('Incorrect charset format %d', [Format]);
  end;

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
