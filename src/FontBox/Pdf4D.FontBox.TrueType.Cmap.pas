// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/CmapTable.java (3.0.8)
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/CmapSubtable.java (3.0.8)
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/CmapLookup.java (3.0.8)
unit Pdf4D.FontBox.TrueType.Cmap;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.FontBox.TrueType.DataStream,
  Pdf4D.FontBox.TrueType.Tables;

type
  TCmapTable = class;

  // One subtable of the cmap table (formats 0, 2, 4, 6, 8, 10, 12, 13 and 14). It is filled by TCmapTable while the table is read
  // and does not change afterwards. A code without a glyph gives glyph 0.
  TCmapSubtable = class
  private
    const LeadOffset = $D800 - ($10000 shr 10);
    const SurrogateOffset = $10000 - ($D800 shl 10) - $DC00;
    const FirstSurrogate = $D800;
    const LastSurrogate = $DFFF;
    const MaximumCharacterCode = $10FFFF;
    const MaximumGroupsFormat8 = 65536;
    const Format8FlagBytes = 8192;
    const Format0Entries = 256;
    const GroupSize = 12;
    const UnusedSegmentCode = $FFFF;
    const GlyphIdModulus = 65536;
    const MaximumLoggedBadGlyphIds = 10;
    const EmptyCode = -1;
    const MultipleCodes = Low(Integer);

  private
    type
      TSubHeader = record
        FirstCode: Integer;
        EntryCount: Integer;
        IdDelta: Integer;
        IdRangeOffset: Integer;
      end;

  private
    FPlatformId: Integer;
    FPlatformEncodingId: Integer;
    FSubTableOffset: Int64;
    FGlyphIdToCharacterCode: TArray<Integer>;
    FGlyphIdToCharacterCodeMultiple: TObjectDictionary<Integer, TList<Integer>>;
    FCharacterCodeToGlyphId: TDictionary<Integer, Integer>;

    class function NewGlyphIdToCharacterCode(const Size: Integer): TArray<Integer>; static;
    class function IsSurrogate(const Code: Int64): Boolean; static;
    class procedure GuardGroupCount(const Data: TTTFDataStream; const GroupCount: Int64); static;

    function GetCharCode(const GID: Integer): Integer;
    procedure BuildGlyphIdToCharacterCodeLookup(const MaxGlyphId: Integer);
    procedure AddMultipleMapping(const GlyphId, CharacterCode: Integer);
    procedure MapCharacter(const CharacterCode, GlyphId: Integer);

    procedure ProcessFormat0(const Data: TTTFDataStream);
    procedure ProcessFormat2(const Cmap: TCmapTable; const Data: TTTFDataStream; const NumGlyphs: Integer);
    procedure ReadFormat2Entries(const Cmap: TCmapTable; const Data: TTTFDataStream; const NumGlyphs: Integer; const SubHeaders: TArray<TSubHeader>;
                                 const StartGlyphIndexOffset: Int64);
    procedure ProcessFormat4(const Cmap: TCmapTable; const Data: TTTFDataStream);
    procedure ReadFormat4Segment(const Data: TTTFDataStream; const FirstCode, LastCode, Delta, RangeOffset: Integer; const SegmentRangeOffset: Int64;
                                 var MaxGlyphId: Integer);
    procedure ProcessFormat6(const Cmap: TCmapTable; const Data: TTTFDataStream);
    procedure ProcessFormat8(const Cmap: TCmapTable; const Data: TTTFDataStream; const NumGlyphs: Integer);
    function Format8CharacterCode(const Is32: TBytes; const Code: Int64): Integer;
    procedure ProcessFormat10(const Data: TTTFDataStream);
    procedure ProcessFormat12(const Cmap: TCmapTable; const Data: TTTFDataStream; const NumGlyphs: Integer);
    procedure ProcessFormat13(const Cmap: TCmapTable; const Data: TTTFDataStream; const NumGlyphs: Integer);

  public
    constructor Create;
    destructor Destroy; override;

    procedure InitData(const Data: TTTFDataStream);
    procedure InitSubtable(const Cmap: TCmapTable; const NumGlyphs: Integer; const Data: TTTFDataStream);

    function GetGlyphId(const CharacterCode: Integer): Integer;
    // All codes that map to the glyph, ascending. Empty when there is none.
    function GetCharCodes(const GID: Integer): TArray<Integer>;

    property PlatformId: Integer read FPlatformId;
    property PlatformEncodingId: Integer read FPlatformEncodingId;
  end;

  // The subtables of one font are read under a shared work budget, so a hostile table with thousands of subtables that point
  // at the same huge range cannot keep the parser busy. A subtable that no longer fits stays empty.
  TCmapTable = class(TTTFTable)
  public
    const TableTag = 'cmap';

    const PlatformUnicode = 0;
    const PlatformMacintosh = 1;
    const PlatformWindows = 3;

    const EncodingMacRoman = 0;

    const EncodingWinSymbol = 0;
    const EncodingWinUnicodeBmp = 1;
    const EncodingWinShiftJis = 2;
    const EncodingWinBig5 = 3;
    const EncodingWinPrc = 4;
    const EncodingWinWansung = 5;
    const EncodingWinJohab = 6;
    const EncodingWinUnicodeFull = 10;

    const EncodingUnicode10 = 0;
    const EncodingUnicode11 = 1;
    const EncodingUnicode20Bmp = 3;
    const EncodingUnicode20Full = 4;

    // Mappings and array entries that all subtables of one cmap table may produce together
    const MaximumWork = 4194304;

  private
    FSubtables: TObjectList<TCmapSubtable>;
    FHost: TTTFTableHost;
    FRemainingWork: Int64;
    FWorkLimitLogged: Boolean;

  public
    constructor Create(const Tag: string; const CheckSum, Offset, Length: Int64);
    destructor Destroy; override;

    procedure Read(const Host: TTTFTableHost; const Data: TTTFDataStream); override;

    // Only meant for the subtables while the table is read. False (and one log line) when the budget is used up.
    function TryCharge(const Count: Int64): Boolean;
    procedure LogWarning(const Message: string);

    function TryGetSubtable(const PlatformId, EncodingId: Integer; out Subtable: TCmapSubtable): Boolean;

    // The table owns the subtables
    property Subtables: TObjectList<TCmapSubtable> read FSubtables;
  end;

implementation

uses
  System.Math,
  Pdf4D.Common.Defines;

{ TCmapSubtable }

constructor TCmapSubtable.Create;
begin
  inherited Create;
  FCharacterCodeToGlyphId := TDictionary<Integer, Integer>.Create;
end;

destructor TCmapSubtable.Destroy;
begin
  FGlyphIdToCharacterCodeMultiple.Free;
  FCharacterCodeToGlyphId.Free;
  inherited Destroy;
end;

class function TCmapSubtable.NewGlyphIdToCharacterCode(const Size: Integer): TArray<Integer>;
begin
  SetLength(Result, Size);
  for var Index := 0 to Size - 1 do
  begin
    Result[Index] := EmptyCode;
  end;
end;

class function TCmapSubtable.IsSurrogate(const Code: Int64): Boolean;
begin
  Result := ((Code >= FirstSurrogate) and (Code <= LastSurrogate));
end;

// A group count that the rest of the data cannot hold is a broken table. Raising at once is what the read of the missing group
// would do, without first spending time on the groups that are there.
class procedure TCmapSubtable.GuardGroupCount(const Data: TTTFDataStream; const GroupCount: Int64);
begin
  const Remaining = Data.OriginalDataSize - Data.CurrentPosition;
  const IsBeyondEnd = (GroupCount * GroupSize > Remaining);
  if IsBeyondEnd then
  begin
    raise EPdfParseException.CreateFmt('The cmap subtable announces %d groups but the data holds %d bytes', [GroupCount, Remaining]);
  end;
end;

procedure TCmapSubtable.InitData(const Data: TTTFDataStream);
begin
  FPlatformId := Data.ReadUnsignedShort;
  FPlatformEncodingId := Data.ReadUnsignedShort;
  FSubTableOffset := Data.ReadUnsignedInt;
end;

procedure TCmapSubtable.InitSubtable(const Cmap: TCmapTable; const NumGlyphs: Integer; const Data: TTTFDataStream);
begin
  Data.Seek(Cmap.Offset + FSubTableOffset);
  const SubtableFormat = Data.ReadUnsignedShort;
  if SubtableFormat < 8 then
  begin
    Data.ReadUnsignedShort; // length
    Data.ReadUnsignedShort; // version
  end
  else
  begin
    Data.ReadUnsignedShort; // the second half of the Fixed32 version
    Data.ReadUnsignedInt; // length
    Data.ReadUnsignedInt; // version
  end;

  case SubtableFormat of
    0 : ProcessFormat0(Data);
    2 : ProcessFormat2(Cmap, Data, NumGlyphs);
    4 : ProcessFormat4(Cmap, Data);
    6 : ProcessFormat6(Cmap, Data);
    8 : ProcessFormat8(Cmap, Data, NumGlyphs);
    10: ProcessFormat10(Data);
    12: ProcessFormat12(Cmap, Data, NumGlyphs);
    13: ProcessFormat13(Cmap, Data, NumGlyphs);
    14: Cmap.LogWarning('Format 14 cmap table is not supported and will be ignored');
  else
    raise EPdfParseException.CreateFmt('Unknown cmap format: %d', [SubtableFormat]);
  end;
end;

procedure TCmapSubtable.MapCharacter(const CharacterCode, GlyphId: Integer);
begin
  FCharacterCodeToGlyphId.AddOrSetValue(CharacterCode, GlyphId);
end;

procedure TCmapSubtable.ProcessFormat0(const Data: TTTFDataStream);
begin
  const GlyphMapping = Data.ReadBytes(Format0Entries);
  FGlyphIdToCharacterCode := NewGlyphIdToCharacterCode(Format0Entries);
  for var Code := 0 to High(GlyphMapping) do
  begin
    const GlyphIndex = GlyphMapping[Code];
    FGlyphIdToCharacterCode[GlyphIndex] := Code;
    MapCharacter(Code, GlyphIndex);
  end;
end;

procedure TCmapSubtable.ProcessFormat2(const Cmap: TCmapTable; const Data: TTTFDataStream; const NumGlyphs: Integer);
begin
  var MaxSubHeaderIndex := 0;
  for var Key := 0 to 255 do
  begin
    MaxSubHeaderIndex := Max(MaxSubHeaderIndex, Data.ReadUnsignedShort div 8);
  end;

  if not Cmap.TryCharge(MaxSubHeaderIndex + 1) then
  begin
    Exit;
  end;

  var SubHeaders: TArray<TSubHeader>;
  SetLength(SubHeaders, MaxSubHeaderIndex + 1);
  for var Index := 0 to MaxSubHeaderIndex do
  begin
    SubHeaders[Index].FirstCode := Data.ReadUnsignedShort;
    SubHeaders[Index].EntryCount := Data.ReadUnsignedShort;
    SubHeaders[Index].IdDelta := Data.ReadSignedShort;
    SubHeaders[Index].IdRangeOffset := Data.ReadUnsignedShort - ((MaxSubHeaderIndex + 1 - Index - 1) * 8) - 2;
  end;

  const StartGlyphIndexOffset = Data.CurrentPosition;
  FGlyphIdToCharacterCode := NewGlyphIdToCharacterCode(NumGlyphs);
  if NumGlyphs = 0 then
  begin
    Cmap.LogWarning('subtable has no glyphs');
    Exit;
  end;

  ReadFormat2Entries(Cmap, Data, NumGlyphs, SubHeaders, StartGlyphIndexOffset);
end;

procedure TCmapSubtable.ReadFormat2Entries(const Cmap: TCmapTable; const Data: TTTFDataStream; const NumGlyphs: Integer;
                                           const SubHeaders: TArray<TSubHeader>; const StartGlyphIndexOffset: Int64);
begin
  const LoggedGlyphIds = TDictionary<Integer, Boolean>.Create;
  try
    var MaxLoggingReached := False;
    for var Index := 0 to High(SubHeaders) do
    begin
      const SubHeader = SubHeaders[Index];
      const GlyphArrayPosition = StartGlyphIndexOffset + SubHeader.IdRangeOffset;
      if GlyphArrayPosition < 0 then
      begin
        raise EPdfParseException.CreateFmt('Subheader %d of the cmap format 2 subtable points before its glyph array', [Index]);
      end;

      if not Cmap.TryCharge(SubHeader.EntryCount) then
      begin
        Exit;
      end;

      Data.Seek(GlyphArrayPosition);
      for var Entry := 0 to SubHeader.EntryCount - 1 do
      begin
        const CharacterCode = (Index shl 8) + (SubHeader.FirstCode + Entry);
        var GlyphId := Data.ReadUnsignedShort;
        if GlyphId > 0 then
        begin
          GlyphId := (GlyphId + SubHeader.IdDelta) mod GlyphIdModulus;
          if GlyphId < 0 then
          begin
            Inc(GlyphId, GlyphIdModulus);
          end;
        end;

        if GlyphId >= NumGlyphs then
        begin
          if not MaxLoggingReached and not LoggedGlyphIds.ContainsKey(GlyphId) then
          begin
            Cmap.LogWarning(Format('glyphId %d for charcode %d ignored, numGlyphs is %d', [GlyphId, CharacterCode, NumGlyphs]));
            LoggedGlyphIds.Add(GlyphId, True);
            if LoggedGlyphIds.Count > MaximumLoggedBadGlyphIds then
            begin
              Cmap.LogWarning('too many bad glyphIds, more won''t be reported for this table');
              MaxLoggingReached := True;
            end;
          end;
          Continue;
        end;

        FGlyphIdToCharacterCode[GlyphId] := CharacterCode;
        MapCharacter(CharacterCode, GlyphId);
      end;
    end;
  finally
    LoggedGlyphIds.Free;
  end;
end;

// A segment whose glyph array lies beyond the data raises, as in PDFBox
procedure TCmapSubtable.ReadFormat4Segment(const Data: TTTFDataStream; const FirstCode, LastCode, Delta, RangeOffset: Integer;
                                           const SegmentRangeOffset: Int64; var MaxGlyphId: Integer);
begin
  for var Code := FirstCode to LastCode do
  begin
    if RangeOffset = 0 then
    begin
      const GlyphId = (Code + Delta) and $FFFF;
      MaxGlyphId := Max(GlyphId, MaxGlyphId);
      MapCharacter(Code, GlyphId);
    end
    else
    begin
      const GlyphOffset = SegmentRangeOffset + (Int64(Code - FirstCode) * 2);
      Data.Seek(GlyphOffset);
      var GlyphIndex := Data.ReadUnsignedShort;
      if GlyphIndex <> 0 then
      begin
        GlyphIndex := (GlyphIndex + Delta) and $FFFF;
        MaxGlyphId := Max(GlyphIndex, MaxGlyphId);
        MapCharacter(Code, GlyphIndex);
      end;
    end;
  end;
end;

procedure TCmapSubtable.ProcessFormat4(const Cmap: TCmapTable; const Data: TTTFDataStream);
begin
  const SegCount = Data.ReadUnsignedShort div 2;
  Data.ReadUnsignedShort; // search range
  Data.ReadUnsignedShort; // entry selector
  Data.ReadUnsignedShort; // range shift

  const ArrayCount = 4;
  if not Cmap.TryCharge(Int64(SegCount) * ArrayCount) then
  begin
    Exit;
  end;

  const EndCount = Data.ReadUnsignedShortArray(SegCount);
  Data.ReadUnsignedShort; // reserved pad
  const StartCount = Data.ReadUnsignedShortArray(SegCount);
  const IdDelta = Data.ReadUnsignedShortArray(SegCount);
  const IdRangeOffsetPosition = Data.CurrentPosition;
  const IdRangeOffset = Data.ReadUnsignedShortArray(SegCount);

  var MaxGlyphId := 0;
  for var Index := 0 to SegCount - 1 do
  begin
    const FirstCode = StartCount[Index];
    const LastCode = EndCount[Index];
    const IsUsable = ((FirstCode <> UnusedSegmentCode) and (LastCode <> UnusedSegmentCode) and (FirstCode <= LastCode));
    if not IsUsable then
    begin
      Continue;
    end;

    if not Cmap.TryCharge(LastCode - FirstCode + 1) then
    begin
      Break;
    end;

    const SegmentRangeOffset = IdRangeOffsetPosition + (Int64(Index) * 2) + IdRangeOffset[Index];
    ReadFormat4Segment(Data, FirstCode, LastCode, IdDelta[Index], IdRangeOffset[Index], SegmentRangeOffset, MaxGlyphId);
  end;

  if FCharacterCodeToGlyphId.Count = 0 then
  begin
    Cmap.LogWarning('cmap format 4 subtable is empty');
    Exit;
  end;

  BuildGlyphIdToCharacterCodeLookup(MaxGlyphId);
end;

procedure TCmapSubtable.ProcessFormat6(const Cmap: TCmapTable; const Data: TTTFDataStream);
begin
  const FirstCode = Data.ReadUnsignedShort;
  const EntryCount = Data.ReadUnsignedShort;
  if (EntryCount = 0) or not Cmap.TryCharge(EntryCount) then
  begin
    Exit;
  end;

  const GlyphIdArray = Data.ReadUnsignedShortArray(EntryCount);
  var MaxGlyphId := 0;
  for var Index := 0 to EntryCount - 1 do
  begin
    MaxGlyphId := Max(MaxGlyphId, GlyphIdArray[Index]);
    MapCharacter(FirstCode + Index, GlyphIdArray[Index]);
  end;
  BuildGlyphIdToCharacterCodeLookup(MaxGlyphId);
end;

function TCmapSubtable.Format8CharacterCode(const Is32: TBytes; const Code: Int64): Integer;
begin
  const FlagMask = 1 shl (Code mod 8);
  const Uses32Bits = ((Is32[Integer(Code div 8)] and FlagMask) <> 0);
  if not Uses32Bits then
  begin
    Exit(Integer(Code));
  end;

  const Lead = LeadOffset + (Code shr 10);
  const Trail = $DC00 + (Code and $3FF);
  const CodePoint = (Lead shl 10) + Trail + SurrogateOffset;
  if CodePoint > MaxInt then
  begin
    raise EPdfParseException.CreateFmt('[Sub Format 8] Invalid character code %d', [CodePoint]);
  end;
  Result := Integer(CodePoint);
end;

procedure TCmapSubtable.ProcessFormat8(const Cmap: TCmapTable; const Data: TTTFDataStream; const NumGlyphs: Integer);
begin
  const Is32 = Data.ReadBytes(Format8FlagBytes);
  const GroupCount = Data.ReadUnsignedInt;
  if GroupCount > MaximumGroupsFormat8 then
  begin
    raise EPdfParseException.Create('CMap (format 8) is invalid');
  end;

  FGlyphIdToCharacterCode := NewGlyphIdToCharacterCode(NumGlyphs);
  if NumGlyphs = 0 then
  begin
    Cmap.LogWarning('subtable has no glyphs');
    Exit;
  end;

  GuardGroupCount(Data, GroupCount);
  const FlaggedCodes = Int64(Format8FlagBytes) * 8;
  for var Group := 1 to Integer(GroupCount) do
  begin
    const FirstCode = Data.ReadUnsignedInt;
    const LastCode = Data.ReadUnsignedInt;
    const StartGlyph = Data.ReadUnsignedInt;
    if FirstCode > LastCode then
    begin
      raise EPdfParseException.Create('Range invalid');
    end;

    if LastCode >= FlaggedCodes then
    begin
      raise EPdfParseException.CreateFmt('[Sub Format 8] Invalid character code %d', [LastCode]);
    end;

    if not Cmap.TryCharge(LastCode - FirstCode + 1) then
    begin
      Exit;
    end;

    for var Code := Integer(FirstCode) to Integer(LastCode) do
    begin
      const CurrentCharCode = Format8CharacterCode(Is32, Code);
      const GlyphIndex = StartGlyph + (Code - FirstCode);
      // PDFBox accepts a glyph index equal to numGlyphs here and then fails on an unchecked array index
      if GlyphIndex >= NumGlyphs then
      begin
        raise EPdfParseException.Create('CMap contains an invalid glyph index');
      end;

      FGlyphIdToCharacterCode[GlyphIndex] := CurrentCharCode;
      MapCharacter(CurrentCharCode, Integer(GlyphIndex));
    end;
  end;
end;

procedure TCmapSubtable.ProcessFormat10(const Data: TTTFDataStream);
begin
  const StartCode = Data.ReadUnsignedInt;
  const NumChars = Data.ReadUnsignedInt;
  if NumChars > MaxInt then
  begin
    raise EPdfParseException.Create('Invalid number of Characters');
  end;

  const EndCode = StartCode + NumChars;
  const IsInvalid = ((StartCode > MaximumCharacterCode) or (EndCode > MaximumCharacterCode) or IsSurrogate(EndCode));
  if IsInvalid then
  begin
    raise EPdfParseException.CreateFmt('Invalid character codes, startCode: 0x%X, numChars: %d', [StartCode, NumChars]);
  end;
end;

procedure TCmapSubtable.ProcessFormat12(const Cmap: TCmapTable; const Data: TTTFDataStream; const NumGlyphs: Integer);
begin
  const GroupCount = Data.ReadUnsignedInt;
  FGlyphIdToCharacterCode := NewGlyphIdToCharacterCode(NumGlyphs);
  if NumGlyphs = 0 then
  begin
    Cmap.LogWarning('subtable has no glyphs');
    Exit;
  end;

  GuardGroupCount(Data, GroupCount);
  var MaxGlyphId := 0;
  for var Group := 1 to Integer(GroupCount) do
  begin
    const FirstCode = Data.ReadUnsignedInt;
    const LastCode = Data.ReadUnsignedInt;
    const StartGlyph = Data.ReadUnsignedInt;

    const IsFirstCodeInvalid = ((FirstCode > MaximumCharacterCode) or IsSurrogate(FirstCode));
    if IsFirstCodeInvalid then
    begin
      raise EPdfParseException.CreateFmt('Invalid character code 0x%X', [FirstCode]);
    end;

    const IsLastCodeInvalid = (((LastCode > 0) and (LastCode < FirstCode)) or (LastCode > MaximumCharacterCode) or IsSurrogate(LastCode));
    if IsLastCodeInvalid then
    begin
      raise EPdfParseException.CreateFmt('Invalid character code 0x%X', [LastCode]);
    end;

    // A group whose glyphs run past numGlyphs is cut short there
    var Count := 0;
    if (LastCode >= FirstCode) and (StartGlyph < NumGlyphs) then
    begin
      Count := Integer(Min(LastCode - FirstCode + 1, NumGlyphs - StartGlyph));
    end;

    const IsCutShort = (StartGlyph + (Int64(LastCode) - FirstCode) >= NumGlyphs) and (LastCode >= FirstCode);
    if IsCutShort then
    begin
      Cmap.LogWarning('Format 12 cmap contains an invalid glyph index');
    end;

    if not Cmap.TryCharge(Count + 1) then
    begin
      Exit;
    end;

    for var Offset := 0 to Count - 1 do
    begin
      const GlyphIndex = Integer(StartGlyph) + Offset;
      MaxGlyphId := Max(MaxGlyphId, GlyphIndex);
      MapCharacter(Integer(FirstCode) + Offset, GlyphIndex);
    end;
  end;
  BuildGlyphIdToCharacterCodeLookup(MaxGlyphId);
end;

procedure TCmapSubtable.ProcessFormat13(const Cmap: TCmapTable; const Data: TTTFDataStream; const NumGlyphs: Integer);
begin
  const GroupCount = Data.ReadUnsignedInt;
  FGlyphIdToCharacterCode := NewGlyphIdToCharacterCode(NumGlyphs);
  if NumGlyphs = 0 then
  begin
    Cmap.LogWarning('subtable has no glyphs');
    Exit;
  end;

  GuardGroupCount(Data, GroupCount);
  for var Group := 1 to Integer(GroupCount) do
  begin
    const FirstCode = Data.ReadUnsignedInt;
    const LastCode = Data.ReadUnsignedInt;
    const GlyphId = Data.ReadUnsignedInt;

    // PDFBox accepts a glyph id equal to numGlyphs here and then fails on an unchecked array index
    if GlyphId >= NumGlyphs then
    begin
      Cmap.LogWarning('Format 13 cmap contains an invalid glyph index');
      Break;
    end;

    const IsFirstCodeInvalid = ((FirstCode > MaximumCharacterCode) or IsSurrogate(FirstCode));
    if IsFirstCodeInvalid then
    begin
      raise EPdfParseException.CreateFmt('Invalid character code 0x%X', [FirstCode]);
    end;

    const IsLastCodeInvalid = (((LastCode > 0) and (LastCode < FirstCode)) or (LastCode > MaximumCharacterCode) or IsSurrogate(LastCode));
    if IsLastCodeInvalid then
    begin
      raise EPdfParseException.CreateFmt('Invalid character code 0x%X', [LastCode]);
    end;

    var Count := 0;
    if LastCode >= FirstCode then
    begin
      Count := Integer(LastCode - FirstCode + 1);
    end;

    if not Cmap.TryCharge(Count + 1) then
    begin
      Exit;
    end;

    for var Offset := 0 to Count - 1 do
    begin
      FGlyphIdToCharacterCode[GlyphId] := Integer(FirstCode) + Offset;
      MapCharacter(Integer(FirstCode) + Offset, Integer(GlyphId));
    end;
  end;
end;

procedure TCmapSubtable.AddMultipleMapping(const GlyphId, CharacterCode: Integer);
begin
  if not Assigned(FGlyphIdToCharacterCodeMultiple) then
  begin
    FGlyphIdToCharacterCodeMultiple := TObjectDictionary<Integer, TList<Integer>>.Create([doOwnsValues]);
  end;

  var MappedValues: TList<Integer>;
  if not FGlyphIdToCharacterCodeMultiple.TryGetValue(GlyphId, MappedValues) then
  begin
    MappedValues := TList<Integer>.Create;
    FGlyphIdToCharacterCodeMultiple.Add(GlyphId, MappedValues);
    MappedValues.Add(FGlyphIdToCharacterCode[GlyphId]);
    FGlyphIdToCharacterCode[GlyphId] := MultipleCodes;
  end;
  MappedValues.Add(CharacterCode);
end;

procedure TCmapSubtable.BuildGlyphIdToCharacterCodeLookup(const MaxGlyphId: Integer);
begin
  FGlyphIdToCharacterCode := NewGlyphIdToCharacterCode(MaxGlyphId + 1);
  for var Mapping in FCharacterCodeToGlyphId do
  begin
    const GlyphId = Mapping.Value;
    if FGlyphIdToCharacterCode[GlyphId] = EmptyCode then
    begin
      FGlyphIdToCharacterCode[GlyphId] := Mapping.Key;
    end
    else
    begin
      AddMultipleMapping(GlyphId, Mapping.Key);
    end;
  end;
end;

function TCmapSubtable.GetGlyphId(const CharacterCode: Integer): Integer;
begin
  if not FCharacterCodeToGlyphId.TryGetValue(CharacterCode, Result) then
  begin
    Result := 0;
  end;
end;

function TCmapSubtable.GetCharCode(const GID: Integer): Integer;
begin
  const IsOutside = ((GID < 0) or (GID >= System.Length(FGlyphIdToCharacterCode)));
  if IsOutside then
  begin
    Exit(EmptyCode);
  end;

  Result := FGlyphIdToCharacterCode[GID];
end;

function TCmapSubtable.GetCharCodes(const GID: Integer): TArray<Integer>;
begin
  const Code = GetCharCode(GID);
  if Code = EmptyCode then
  begin
    Exit(nil);
  end;

  if Code <> MultipleCodes then
  begin
    SetLength(Result, 1);
    Result[0] := Code;
    Exit;
  end;

  var MappedValues: TList<Integer>;
  const HasMultiple = Assigned(FGlyphIdToCharacterCodeMultiple) and FGlyphIdToCharacterCodeMultiple.TryGetValue(GID, MappedValues);
  if not HasMultiple then
  begin
    Exit(nil);
  end;

  Result := MappedValues.ToArray;
  TArray.Sort<Integer>(Result);
end;

{ TCmapTable }

constructor TCmapTable.Create(const Tag: string; const CheckSum, Offset, Length: Int64);
begin
  inherited Create(Tag, CheckSum, Offset, Length);
  FSubtables := TObjectList<TCmapSubtable>.Create;
end;

destructor TCmapTable.Destroy;
begin
  FSubtables.Free;
  inherited Destroy;
end;

procedure TCmapTable.Read(const Host: TTTFTableHost; const Data: TTTFDataStream);
begin
  Data.ReadUnsignedShort; // version
  const NumberOfTables = Data.ReadUnsignedShort;
  for var Index := 1 to NumberOfTables do
  begin
    const Subtable = TCmapSubtable.Create;
    FSubtables.Add(Subtable);
    Subtable.InitData(Data);
  end;

  const NumberOfGlyphs = Host.NumberOfGlyphs;
  FHost := Host;
  FRemainingWork := MaximumWork;
  FWorkLimitLogged := False;
  try
    for var Subtable in FSubtables do
    begin
      Subtable.InitSubtable(Self, NumberOfGlyphs, Data);
    end;
  finally
    FHost := nil;
  end;
  FInitialized := True;
end;

function TCmapTable.TryCharge(const Count: Int64): Boolean;
begin
  Result := ((Count >= 0) and (Count <= FRemainingWork));
  if Result then
  begin
    Dec(FRemainingWork, Count);
  end
  else if not FWorkLimitLogged then
  begin
    FWorkLimitLogged := True;
    LogWarning('The cmap table is too large; the subtables that do not fit are ignored');
  end;
end;

procedure TCmapTable.LogWarning(const Message: string);
begin
  if Assigned(FHost) then
  begin
    FHost.LogWarning(Message);
  end;
end;

function TCmapTable.TryGetSubtable(const PlatformId, EncodingId: Integer; out Subtable: TCmapSubtable): Boolean;
begin
  for var Candidate in FSubtables do
  begin
    const IsMatch = ((Candidate.PlatformId = PlatformId) and (Candidate.PlatformEncodingId = EncodingId));
    if IsMatch then
    begin
      Subtable := Candidate;
      Exit(True);
    end;
  end;

  Subtable := nil;
  Result := False;
end;

end.
