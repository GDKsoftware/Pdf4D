// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/cmap/CMap.java (3.0.8)
// Port of: fontbox/src/main/java/org/apache/fontbox/cmap/CodespaceRange.java (3.0.8)
// Port of: fontbox/src/main/java/org/apache/fontbox/cmap/CIDRange.java (3.0.8)
// Port of: fontbox/src/main/java/org/apache/fontbox/cmap/CMapStrings.java (3.0.8)
unit Pdf4D.FontBox.CMap;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.Log;

const
  // The most mappings (character, CID and CID range entries) that one CMap takes. PDFBox has no limit; this one keeps
  // a hostile bfrange or cidrange from using all memory.
  MaxCMapMappings = 4194304;

type
  // Codes of one length, each byte in its own range
  TCodespaceRange = record
  private
    FStart: TArray<Integer>;
    FEnd: TArray<Integer>;
    FCodeLength: Integer;

  public
    // Raises EArgumentException when the lengths differ, except for a start of <00> (PDFBOX-4923)
    constructor Create(const StartBytes, EndBytes: TBytes);

    function Matches(const Code: TBytes): Boolean;
    function IsFullMatch(const Code: TBytes; const CodeLen: Integer): Boolean;

    property CodeLength: Integer read FCodeLength;
  end;

  // A range of continuous CIDs for a range of codes of one length
  TCIDRange = record
  private
    FFromCode: Integer;
    FToCode: Integer;
    FCID: Integer;
    FCodeLength: Integer;

  public
    constructor Create(const FromCode, ToCode, CID, CodeLength: Integer);

    // The CID of the code, or -1 when the code is not in the range
    function Map(const Code: TBytes): Integer; overload;
    function Map(const Code, CodeLen: Integer): Integer; overload;
    // The code of the CID, or -1 when the CID is not in the range
    function Unmap(const CID: Integer): Integer;
    // Appends the next range when it continues this one
    function Extend(const NewFrom, NewTo, NewCID, CodeLen: Integer): Boolean;

    property CodeLength: Integer read FCodeLength;
  end;

  // The strings of codes of one and two bytes. PDFBox keeps them in lists of 256 and 65536 shared strings; here they
  // are made when asked for.
  TCMapStrings = class
  public
    // A code of one byte is the ISO-8859-1 character, a code of two bytes the UTF-16BE character (a lone surrogate
    // becomes U+FFFD, as in Java). False for more than two bytes.
    class function TryGetMapping(const Bytes: TBytes; out Value: string): Boolean; static;
    class function TryGetIndexValue(const Bytes: TBytes; out Value: Integer): Boolean; static;
    // A copy of the bytes
    class function TryGetByteValue(const Bytes: TBytes; out Value: TBytes): Boolean; static;
    // As new String(bytes, UTF_16BE) in Java: a malformed unit becomes U+FFFD
    class function DecodeUtf16BigEndian(const Bytes: TBytes): string; static;
  end;

  // A CMap maps character codes to CIDs or to Unicode. It is filled by TCMapParser; the Add methods are for the parser
  // and a CMap does not change after it is shared.
  TCMap = class
  private
    FWMode: Integer;
    FName: string;
    FVersion: string;
    FCMapType: Integer;
    FRegistry: string;
    FOrdering: string;
    FSupplement: Integer;
    FMinCodeLength: Integer;
    FMaxCodeLength: Integer;
    FMinCidLength: Integer;
    FMaxCidLength: Integer;
    FCodespaceRanges: TList<TCodespaceRange>;
    FCharToUnicodeOneByte: TDictionary<Integer, string>;
    FCharToUnicodeTwoBytes: TDictionary<Integer, string>;
    FCharToUnicodeMoreBytes: TDictionary<Integer, string>;
    FCodeToCid: TObjectDictionary<Integer, TDictionary<Integer, Integer>>;
    FCodeToCidRanges: TList<TCIDRange>;
    FSpaceMapping: Integer;
    FMappingCount: Integer;

    function IsCodespaceFullMatch(const Bytes: TBytes; const ByteCount: Integer): Boolean;
    function ReadCodeWithoutCodespace(const Data: TBytes; var Position: Integer): Integer;
    function ToCIDFromRanges(const Code, CodeLen: Integer): Integer; overload;
    function ToCIDFromRanges(const Code: TBytes): Integer; overload;
    procedure AddCIDRange(const Range: TCIDRange);
    procedure CopyCharMappings(const Source: TDictionary<Integer, string>; const Target: TDictionary<Integer, string>);
    procedure CopyCIDMappings(const Other: TCMap);
    procedure CopyCIDRanges(const Other: TCMap);
    procedure WarnInvalidSequence(const Bytes: TBytes; const Log: TPdfLog);

  public
    constructor Create;
    destructor Destroy; override;

    // The big-endian value of the first Count bytes; a code of more than four bytes keeps its last four bytes
    class function ToInt(const Data: TBytes; const Count: Integer): Integer; overload; static;
    class function ToInt(const Data: TBytes): Integer; overload; static;

    function HasCIDMappings: Boolean;
    function HasUnicodeMappings: Boolean;

    // The Unicode text of the code, whatever its length
    function TryToUnicode(const Code: Integer; out Value: string): Boolean; overload;
    function TryToUnicode(const Code, CodeLength: Integer; out Value: string): Boolean; overload;
    function TryToUnicode(const Code: TBytes; out Value: string): Boolean; overload;

    // Reads the next code at Position and moves Position behind it. At the end of the data it gives 0 and does not
    // move; otherwise it moves at least one byte. A sequence that is in no codespace range gives the code of the
    // shortest length, like Adobe Reader.
    function ReadCode(const Data: TBytes; var Position: Integer): Integer; overload;
    // As above; reports an invalid sequence to Log, which may be nil
    function ReadCode(const Data: TBytes; var Position: Integer; const Log: TPdfLog): Integer; overload;

    // The CID of the code, or 0 when there is none
    function ToCID(const Code: TBytes): Integer; overload;
    function ToCID(const Code: Integer): Integer; overload;
    function ToCID(const Code, CodeLen: Integer): Integer; overload;

    function TryGetSpaceMapping(out Code: Integer): Boolean;

    // For the parser. They ignore a mapping once the CMap holds MaxCMapMappings mappings.
    procedure AddCharMapping(const Codes: TBytes; const Unicode: string);
    procedure AddCIDMapping(const Code: TBytes; const CID: Integer);
    procedure AddCIDRangeMapping(const FromCode, ToCode: TBytes; const CID: Integer);
    // A range without bytes is ignored: it would match without consuming anything
    procedure AddCodespaceRange(const Range: TCodespaceRange);
    // Copies everything from Other, as usecmap does. Other itself stays as it is.
    procedure UseCMap(const Other: TCMap);
    function IsFull: Boolean;

    property Name: string read FName write FName;
    property Version: string read FVersion write FVersion;
    property CMapType: Integer read FCMapType write FCMapType;
    property WMode: Integer read FWMode write FWMode;
    property Registry: string read FRegistry write FRegistry;
    property Ordering: string read FOrdering write FOrdering;
    property Supplement: Integer read FSupplement write FSupplement;
    property MappingCount: Integer read FMappingCount;
  end;

implementation

uses
  System.Math;

const
  MaxByteValue = $FF;
  FirstSurrogate = $D800;
  LastHighSurrogate = $DBFF;
  LastSurrogate = $DFFF;
  ReplacementCharacter = #$FFFD;
  DefaultMinLength = 4;
  SpaceText = ' ';

function WrapToInteger(const Value: Int64): Integer;
begin
  Result := Integer(Cardinal(Value and $FFFFFFFF));
end;

function IsLowSurrogateAt(const Bytes: TBytes; const Index: Integer): Boolean;
begin
  const Unit16 = (Bytes[Index] shl 8) or Bytes[Index + 1];
  Result := ((Unit16 > LastHighSurrogate) and (Unit16 <= LastSurrogate));
end;

{ TCodespaceRange }

constructor TCodespaceRange.Create(const StartBytes, EndBytes: TBytes);
begin
  const HasSameLength = (Length(StartBytes) = Length(EndBytes));
  const IsLeadingZero = ((Length(StartBytes) = 1) and (StartBytes[0] = 0));
  if (not HasSameLength) and (not IsLeadingZero) then
  begin
    raise EArgumentException.Create('The start and the end values must not have different lengths.');
  end;

  FCodeLength := Length(EndBytes);
  SetLength(FStart, FCodeLength);
  SetLength(FEnd, FCodeLength);
  for var Index := 0 to FCodeLength - 1 do
  begin
    if HasSameLength then
    begin
      FStart[Index] := StartBytes[Index];
    end
    else
    begin
      FStart[Index] := 0;
    end;
    FEnd[Index] := EndBytes[Index];
  end;
end;

function TCodespaceRange.Matches(const Code: TBytes): Boolean;
begin
  Result := IsFullMatch(Code, Length(Code));
end;

function TCodespaceRange.IsFullMatch(const Code: TBytes; const CodeLen: Integer): Boolean;
begin
  const HasOtherLength = ((FCodeLength <> CodeLen) or (CodeLen > Length(Code)));
  if HasOtherLength then
  begin
    Exit(False);
  end;

  for var Index := 0 to FCodeLength - 1 do
  begin
    const IsOutOfRange = ((Code[Index] < FStart[Index]) or (Code[Index] > FEnd[Index]));
    if IsOutOfRange then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

{ TCIDRange }

constructor TCIDRange.Create(const FromCode, ToCode, CID, CodeLength: Integer);
begin
  FFromCode := FromCode;
  FToCode := ToCode;
  FCID := CID;
  FCodeLength := CodeLength;
end;

function TCIDRange.Map(const Code: TBytes): Integer;
begin
  if Length(Code) <> FCodeLength then
  begin
    Exit(-1);
  end;

  Result := Map(TCMap.ToInt(Code), FCodeLength);
end;

function TCIDRange.Map(const Code, CodeLen: Integer): Integer;
begin
  const IsInRange = ((CodeLen = FCodeLength) and (FFromCode <= Code) and (Code <= FToCode));
  if IsInRange then
  begin
    Result := WrapToInteger(Int64(FCID) + (Int64(Code) - FFromCode));
  end
  else
  begin
    Result := -1;
  end;
end;

function TCIDRange.Unmap(const CID: Integer): Integer;
begin
  const LastCID = Int64(FCID) + (Int64(FToCode) - FFromCode);
  const IsInRange = ((FCID <= CID) and (CID <= LastCID));
  if IsInRange then
  begin
    Result := WrapToInteger(Int64(FFromCode) + (Int64(CID) - FCID));
  end
  else
  begin
    Result := -1;
  end;
end;

function TCIDRange.Extend(const NewFrom, NewTo, NewCID, CodeLen: Integer): Boolean;
begin
  const NextCode = Int64(FToCode) + 1;
  const NextCID = Int64(FCID) + FToCode - FFromCode + 1;
  Result := ((FCodeLength = CodeLen) and (NewFrom = NextCode) and (NewCID = NextCID));
  if Result then
  begin
    FToCode := NewTo;
  end;
end;

{ TCMapStrings }

class function TCMapStrings.TryGetMapping(const Bytes: TBytes; out Value: string): Boolean;
begin
  Result := (Length(Bytes) <= 2);
  if not Result then
  begin
    Value := '';
    Exit;
  end;

  if Length(Bytes) = 1 then
  begin
    Value := Char(Bytes[0]);
    Exit;
  end;

  const Code = TCMap.ToInt(Bytes);
  const IsSurrogate = ((Code >= FirstSurrogate) and (Code <= LastSurrogate));
  if IsSurrogate then
  begin
    Value := ReplacementCharacter;
  end
  else
  begin
    Value := Char(Code);
  end;
end;

class function TCMapStrings.TryGetIndexValue(const Bytes: TBytes; out Value: Integer): Boolean;
begin
  Result := (Length(Bytes) <= 2);
  if Result then
  begin
    Value := TCMap.ToInt(Bytes);
  end
  else
  begin
    Value := 0;
  end;
end;

class function TCMapStrings.TryGetByteValue(const Bytes: TBytes; out Value: TBytes): Boolean;
begin
  Result := (Length(Bytes) <= 2);
  if Result then
  begin
    Value := Copy(Bytes);
  end
  else
  begin
    Value := nil;
  end;
end;

class function TCMapStrings.DecodeUtf16BigEndian(const Bytes: TBytes): string;
begin
  const Builder = TStringBuilder.Create(Length(Bytes) div 2 + 1);
  try
    var Index := 0;
    while Index < Length(Bytes) do
    begin
      const HasFullUnit = (Index <= Length(Bytes) - 2);
      if not HasFullUnit then
      begin
        Builder.Append(ReplacementCharacter);
        Break;
      end;

      const Unit16 = (Bytes[Index] shl 8) or Bytes[Index + 1];
      const IsSurrogate = ((Unit16 >= FirstSurrogate) and (Unit16 <= LastSurrogate));
      if not IsSurrogate then
      begin
        Builder.Append(Char(Unit16));
        Inc(Index, 2);
        Continue;
      end;

      const IsHighSurrogate = (Unit16 <= LastHighSurrogate);
      const HasLowSurrogateBytes = (IsHighSurrogate and (Index <= Length(Bytes) - 4));
      if IsHighSurrogate and (not HasLowSurrogateBytes) then
      begin
        // A high surrogate at the end: Java drops it with all bytes that are left
        Builder.Append(ReplacementCharacter);
        Break;
      end;

      if HasLowSurrogateBytes and IsLowSurrogateAt(Bytes, Index + 2) then
      begin
        Builder.Append(Char(Unit16));
        Builder.Append(Char((Bytes[Index + 2] shl 8) or Bytes[Index + 3]));
        Inc(Index, 4);
      end
      else
      begin
        Builder.Append(ReplacementCharacter);
        Inc(Index, 2);
      end;
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

{ TCMap }

constructor TCMap.Create;
begin
  inherited Create;
  FCMapType := -1;
  FSpaceMapping := -1;
  FMinCodeLength := DefaultMinLength;
  FMinCidLength := DefaultMinLength;
  FCodespaceRanges := TList<TCodespaceRange>.Create;
  FCharToUnicodeOneByte := TDictionary<Integer, string>.Create;
  FCharToUnicodeTwoBytes := TDictionary<Integer, string>.Create;
  FCharToUnicodeMoreBytes := TDictionary<Integer, string>.Create;
  FCodeToCid := TObjectDictionary<Integer, TDictionary<Integer, Integer>>.Create([doOwnsValues]);
  FCodeToCidRanges := TList<TCIDRange>.Create;
end;

destructor TCMap.Destroy;
begin
  FCodeToCidRanges.Free;
  FCodeToCid.Free;
  FCharToUnicodeMoreBytes.Free;
  FCharToUnicodeTwoBytes.Free;
  FCharToUnicodeOneByte.Free;
  FCodespaceRanges.Free;
  inherited;
end;

class function TCMap.ToInt(const Data: TBytes; const Count: Integer): Integer;
begin
  Result := 0;
  const ByteCount = Min(Count, Length(Data));
  for var Index := 0 to ByteCount - 1 do
  begin
    Result := (Result shl 8) or Data[Index];
  end;
end;

class function TCMap.ToInt(const Data: TBytes): Integer;
begin
  Result := ToInt(Data, Length(Data));
end;

function TCMap.HasCIDMappings: Boolean;
begin
  Result := ((FCodeToCid.Count > 0) or (FCodeToCidRanges.Count > 0));
end;

function TCMap.HasUnicodeMappings: Boolean;
begin
  Result := ((FCharToUnicodeOneByte.Count > 0) or (FCharToUnicodeTwoBytes.Count > 0) or (FCharToUnicodeMoreBytes.Count > 0));
end;

function TCMap.TryToUnicode(const Code: Integer; out Value: string): Boolean;
begin
  Result := ((Code < 256) and TryToUnicode(Code, 1, Value));
  if Result then
  begin
    Exit;
  end;

  if Code <= $FFFF then
  begin
    Exit(TryToUnicode(Code, 2, Value));
  end;
  if Code <= $FFFFFF then
  begin
    Exit(TryToUnicode(Code, 3, Value));
  end;
  Result := TryToUnicode(Code, 4, Value);
end;

function TCMap.TryToUnicode(const Code, CodeLength: Integer; out Value: string): Boolean;
begin
  case CodeLength of
    1: Result := FCharToUnicodeOneByte.TryGetValue(Code, Value);
    2: Result := FCharToUnicodeTwoBytes.TryGetValue(Code, Value);
  else
    Result := FCharToUnicodeMoreBytes.TryGetValue(Code, Value);
  end;
end;

function TCMap.TryToUnicode(const Code: TBytes; out Value: string): Boolean;
begin
  Result := TryToUnicode(ToInt(Code), Length(Code), Value);
end;

function TCMap.ReadCode(const Data: TBytes; var Position: Integer): Integer;
begin
  Result := ReadCode(Data, Position, nil);
end;

function TCMap.ReadCode(const Data: TBytes; var Position: Integer; const Log: TPdfLog): Integer;
begin
  if Position < 0 then
  begin
    Position := 0;
  end;

  const Available = Length(Data) - Position;
  if Available <= 0 then
  begin
    Exit(0);
  end;

  const HasNoCodespace = (FMaxCodeLength <= 0);
  if HasNoCodespace then
  begin
    Exit(ReadCodeWithoutCodespace(Data, Position));
  end;

  // Like PDFBox: bytes that are not there read as zero for the first MinCodeLength and as $FF after that
  var Bytes: TBytes;
  SetLength(Bytes, FMaxCodeLength);
  const FirstRead = Min(FMinCodeLength, Available);
  Move(Data[Position], Bytes[0], FirstRead);

  var Consumed := FirstRead;
  for var ByteCount := FMinCodeLength to FMaxCodeLength do
  begin
    if IsCodespaceFullMatch(Bytes, ByteCount) then
    begin
      Inc(Position, Consumed);
      Exit(ToInt(Bytes, ByteCount));
    end;

    if ByteCount < FMaxCodeLength then
    begin
      if Consumed < Available then
      begin
        Bytes[ByteCount] := Data[Position + Consumed];
        Inc(Consumed);
      end
      else
      begin
        Bytes[ByteCount] := MaxByteValue;
      end;
    end;
  end;

  WarnInvalidSequence(Bytes, Log);
  Inc(Position, FirstRead);
  Result := ToInt(Bytes, FMinCodeLength);
end;

function TCMap.ReadCodeWithoutCodespace(const Data: TBytes; var Position: Integer): Integer;
begin
  Result := Data[Position];
  Inc(Position);
end;

function TCMap.IsCodespaceFullMatch(const Bytes: TBytes; const ByteCount: Integer): Boolean;
begin
  for var Range in FCodespaceRanges do
  begin
    if Range.IsFullMatch(Bytes, ByteCount) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TCMap.WarnInvalidSequence(const Bytes: TBytes; const Log: TPdfLog);
begin
  if not Assigned(Log) then
  begin
    Exit;
  end;

  const Builder = TStringBuilder.Create;
  try
    for var Value in Bytes do
    begin
      Builder.AppendFormat('0x%.2X ', [Value]);
    end;
    Log.Warning('Invalid character code sequence %sin CMap %s', [Builder.ToString, FName]);
  finally
    Builder.Free;
  end;
end;

function TCMap.ToCID(const Code: TBytes): Integer;
begin
  const IsOutsideLengths = ((not HasCIDMappings) or (Length(Code) < FMinCidLength) or (Length(Code) > FMaxCidLength));
  if IsOutsideLengths then
  begin
    Exit(0);
  end;

  var CodeToCidMap: TDictionary<Integer, Integer>;
  if FCodeToCid.TryGetValue(Length(Code), CodeToCidMap) and CodeToCidMap.TryGetValue(ToInt(Code), Result) then
  begin
    Exit;
  end;
  Result := ToCIDFromRanges(Code);
end;

function TCMap.ToCID(const Code: Integer): Integer;
begin
  Result := 0;
  if not HasCIDMappings then
  begin
    Exit;
  end;

  var CodeLen := FMinCidLength;
  while (Result = 0) and (CodeLen <= FMaxCidLength) do
  begin
    Result := ToCID(Code, CodeLen);
    Inc(CodeLen);
  end;
end;

function TCMap.ToCID(const Code, CodeLen: Integer): Integer;
begin
  const IsOutsideLengths = ((not HasCIDMappings) or (CodeLen < FMinCidLength) or (CodeLen > FMaxCidLength));
  if IsOutsideLengths then
  begin
    Exit(0);
  end;

  var CodeToCidMap: TDictionary<Integer, Integer>;
  if FCodeToCid.TryGetValue(CodeLen, CodeToCidMap) and CodeToCidMap.TryGetValue(Code, Result) then
  begin
    Exit;
  end;
  Result := ToCIDFromRanges(Code, CodeLen);
end;

function TCMap.ToCIDFromRanges(const Code, CodeLen: Integer): Integer;
begin
  for var Range in FCodeToCidRanges do
  begin
    Result := Range.Map(Code, CodeLen);
    if Result <> -1 then
    begin
      Exit;
    end;
  end;
  Result := 0;
end;

function TCMap.ToCIDFromRanges(const Code: TBytes): Integer;
begin
  for var Range in FCodeToCidRanges do
  begin
    Result := Range.Map(Code);
    if Result <> -1 then
    begin
      Exit;
    end;
  end;
  Result := 0;
end;

function TCMap.TryGetSpaceMapping(out Code: Integer): Boolean;
begin
  Code := FSpaceMapping;
  Result := (FSpaceMapping <> -1);
end;

function TCMap.IsFull: Boolean;
begin
  Result := (FMappingCount >= MaxCMapMappings);
end;

procedure TCMap.AddCharMapping(const Codes: TBytes; const Unicode: string);
begin
  if not IsFull then
  begin
    case Length(Codes) of
      1:
      begin
        FCharToUnicodeOneByte.AddOrSetValue(ToInt(Codes), Unicode);
        Inc(FMappingCount);
      end;
      2:
      begin
        FCharToUnicodeTwoBytes.AddOrSetValue(ToInt(Codes), Unicode);
        Inc(FMappingCount);
      end;
      3, 4:
      begin
        FCharToUnicodeMoreBytes.AddOrSetValue(ToInt(Codes), Unicode);
        Inc(FMappingCount);
      end;
    else
      // Not stored; the parser reports a code of another length
    end;
  end;

  // A hack of PDFBox that is kept as it is
  if Unicode = SpaceText then
  begin
    FSpaceMapping := ToInt(Codes);
  end;
end;

procedure TCMap.AddCIDMapping(const Code: TBytes; const CID: Integer);
begin
  if IsFull then
  begin
    Exit;
  end;

  var CodeToCidMap: TDictionary<Integer, Integer>;
  if not FCodeToCid.TryGetValue(Length(Code), CodeToCidMap) then
  begin
    CodeToCidMap := TDictionary<Integer, Integer>.Create;
    FCodeToCid.Add(Length(Code), CodeToCidMap);
    FMinCidLength := Min(FMinCidLength, Length(Code));
    FMaxCidLength := Max(FMaxCidLength, Length(Code));
  end;
  CodeToCidMap.AddOrSetValue(ToInt(Code), CID);
  Inc(FMappingCount);
end;

procedure TCMap.AddCIDRangeMapping(const FromCode, ToCode: TBytes; const CID: Integer);
begin
  const Range = TCIDRange.Create(ToInt(FromCode), ToInt(ToCode), CID, Length(FromCode));
  AddCIDRange(Range);
end;

procedure TCMap.AddCIDRange(const Range: TCIDRange);
begin
  if FCodeToCidRanges.Count > 0 then
  begin
    var LastRange := FCodeToCidRanges[FCodeToCidRanges.Count - 1];
    const IsExtended = LastRange.Extend(Range.FFromCode, Range.FToCode, Range.FCID, Range.FCodeLength);
    if IsExtended then
    begin
      FCodeToCidRanges[FCodeToCidRanges.Count - 1] := LastRange;
      Exit;
    end;
  end;

  if IsFull then
  begin
    Exit;
  end;
  FCodeToCidRanges.Add(Range);
  Inc(FMappingCount);
  FMinCidLength := Min(FMinCidLength, Range.FCodeLength);
  FMaxCidLength := Max(FMaxCidLength, Range.FCodeLength);
end;

procedure TCMap.AddCodespaceRange(const Range: TCodespaceRange);
begin
  if Range.CodeLength = 0 then
  begin
    Exit;
  end;

  FCodespaceRanges.Add(Range);
  FMaxCodeLength := Max(FMaxCodeLength, Range.CodeLength);
  FMinCodeLength := Min(FMinCodeLength, Range.CodeLength);
end;

procedure TCMap.UseCMap(const Other: TCMap);
begin
  for var Range in Other.FCodespaceRanges do
  begin
    AddCodespaceRange(Range);
  end;

  CopyCharMappings(Other.FCharToUnicodeOneByte, FCharToUnicodeOneByte);
  CopyCharMappings(Other.FCharToUnicodeTwoBytes, FCharToUnicodeTwoBytes);
  CopyCharMappings(Other.FCharToUnicodeMoreBytes, FCharToUnicodeMoreBytes);
  CopyCIDMappings(Other);
  CopyCIDRanges(Other);

  FMaxCodeLength := Max(FMaxCodeLength, Other.FMaxCodeLength);
  FMinCodeLength := Min(FMinCodeLength, Other.FMinCodeLength);
  FMaxCidLength := Max(FMaxCidLength, Other.FMaxCidLength);
  FMinCidLength := Min(FMinCidLength, Other.FMinCidLength);
end;

procedure TCMap.CopyCharMappings(const Source: TDictionary<Integer, string>; const Target: TDictionary<Integer, string>);
begin
  for var Pair in Source do
  begin
    if IsFull then
    begin
      Exit;
    end;
    Target.AddOrSetValue(Pair.Key, Pair.Value);
    Inc(FMappingCount);
  end;
end;

procedure TCMap.CopyCIDMappings(const Other: TCMap);
begin
  for var LengthPair in Other.FCodeToCid do
  begin
    var Target: TDictionary<Integer, Integer>;
    if not FCodeToCid.TryGetValue(LengthPair.Key, Target) then
    begin
      Target := TDictionary<Integer, Integer>.Create;
      FCodeToCid.Add(LengthPair.Key, Target);
    end;

    for var Pair in LengthPair.Value do
    begin
      if IsFull then
      begin
        Exit;
      end;
      Target.AddOrSetValue(Pair.Key, Pair.Value);
      Inc(FMappingCount);
    end;
  end;
end;

procedure TCMap.CopyCIDRanges(const Other: TCMap);
begin
  for var Range in Other.FCodeToCidRanges do
  begin
    if IsFull then
    begin
      Exit;
    end;
    FCodeToCidRanges.Add(Range);
    Inc(FMappingCount);
  end;
end;

end.
