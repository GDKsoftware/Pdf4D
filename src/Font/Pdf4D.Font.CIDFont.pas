// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/font/PDCIDFont.java (3.0.8)
unit Pdf4D.Font.CIDFont;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.Log,
  Pdf4D.Common.Matrix,
  Pdf4D.Common.Path,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Font.Base,
  Pdf4D.Font.Descriptor,
  Pdf4D.FontBox.BoundingBox,
  Pdf4D.FontBox.CMap;

type
  // The composite font that owns a CID font. PDFBox types the parent as PDType0Font; here the CID font units come before
  // the Type 0 unit, so the part of PDType0Font that a CID font needs is this class, which TPDType0Font extends.
  TPDCIDFontParent = class abstract(TPDFont)
  public
    // The CMap of /Encoding. False when the font has none.
    function TryGetCMap(out CMap: TCMap): Boolean; virtual; abstract;
    // The UCS2 CMap that goes with a predefined CMap or a CJK character collection. False when there is none.
    function TryGetCMapUCS2(out CMap: TCMap): Boolean; virtual; abstract;
  end;

  // A CIDFont dictionary: the widths (/W, /DW), the vertical metrics (/W2, /DW2) and the CIDSystemInfo. The subclasses add
  // the font program and the mapping from CID to glyph. The font does not own its dictionary or its parent; both stay
  // alive for as long as the font does.
  //
  // PDFBox keeps one map entry per CID of a /W range. A range of at most WidthRangeExpandLimit CIDs is expanded in the
  // same way; a longer one (the file can name two billion CIDs) is kept as a range, and so are the ranges that no longer
  // fit in the table of widths. A range or an entry that comes later overrides an earlier one, like a put into a HashMap.
  TPDCIDFont = class abstract
  private
    type
      TWidthEntry = record
        Width: Single;
        Sequence: Integer;
      end;

      TWidthRange = record
        First: Integer;
        Last: Integer;
        Width: Single;
        Sequence: Integer;
      end;

      TDisplacementRange = record
        First: Integer;
        Last: Integer;
        PositionVector: TPdfVector;
        Displacement: Single;
      end;

    const WidthRangeExpandLimit = 65536;
    const MaxWidthEntries = 262144;
    const MaxWidthRanges = 1024;
    const MaxDisplacementRanges = 4096;
    const MaxCIDToGIDBytes = 2 * 1048576;
    const DefaultDisplacementY = 880;
    const DefaultDisplacementVectorY = -1000;
    const DefaultCIDWidth = 1000;

  private
    FDictionary: TCosDictionary;
    FParent: TPDCIDFontParent;
    FFontDescriptor: TPDFontDescriptor;
    FWidths: TDictionary<Integer, TWidthEntry>;
    FWidthRanges: TList<TWidthRange>;
    FSequence: Integer;
    FDefaultWidth: Single;
    FAverageWidth: Single;
    FDw2: array[0..1] of Single;
    FVerticalDisplacementY: TDictionary<Integer, Single>;
    FPositionVectors: TDictionary<Integer, TPdfVector>;
    FDisplacementRanges: TList<TDisplacementRange>;

    procedure ReadWidths;
    procedure ReadWidthArray(const StartRange: Integer; const Values: TCosArray);
    procedure PutWidth(const CID: Int64; const Width: Single);
    procedure PutWidthRange(const FirstCID, LastCID: Integer; const Width: Single);
    procedure ReadVerticalDisplacements;
    procedure ReadDefaultDisplacements;
    procedure ReadDisplacementEntries(const Entries: TCosArray);
    procedure ReadDisplacementArray(const FirstCID: Integer; const Values: TCosArray);
    procedure AddDisplacementRange(const FirstCID, LastCID: Integer; const Displacement: Single; const PositionVector: TPdfVector);
    function TryGetNumberAt(const Values: TCosArray; const Index: Integer; out Number: TCosBase): Boolean;
    function TryGetWidthForCID(const CID: Integer; out Width: Single): Boolean;
    function TryGetDisplacementRange(const CID: Integer; out Range: TDisplacementRange): Boolean;
    function GetDefaultWidth: Single;
    function GetWidthForCID(const CID: Integer): Single;
    function CalculateAverageWidth: Single;
    class function DescribeObject(const Item: TCosBase): string; static;

  protected
    // The log of the document, or nil
    function DocumentLog: TPdfLog;
    procedure LogWarning(const Fmt: string; const Args: array of const);
    // The bytes of a font file stream, decoded. Raises an EPdfException when it cannot be decoded.
    class function ReadStreamBytes(const Stream: TCosStream): TBytes; static;
    // True for the failures that a damaged font file can cause: they are logged and the font falls back
    class function IsRecoverableFailure(const Failure: Exception): Boolean; static;
    // PDCIDFont.readCIDToGIDMap. False when /CIDToGIDMap is not a stream. The map is the stream as it is, big endian pairs,
    // cut off at MaxCIDToGIDBytes (a CID beyond the map has glyph 0, as for a stream that is too short); an odd last byte is
    // dropped.
    function TryReadCIDToGIDMap(out Map: TBytes): Boolean;
    // The glyph of a CID in a map from TryReadCIDToGIDMap; 0 beyond the end of the map
    class function MapCIDToGID(const Map: TBytes; const CID: Integer): Integer; static;

  public
    // Does not own Dictionary or Parent
    constructor Create(const Dictionary: TCosDictionary; const Parent: TPDCIDFontParent);
    destructor Destroy; override;

    function TryGetFontDescriptor(out Descriptor: TPDFontDescriptor): Boolean;
    // False when there is no /CIDSystemInfo dictionary
    function TryGetCIDSystemInfo(out Info: TPDCIDSystemInfo): Boolean;
    function GetBaseFont: string;

    function CodeToCID(const Code: Integer): Integer; virtual; abstract;
    function CodeToGID(const Code: Integer): Integer; virtual; abstract;
    function GetWidthFromFont(const Code: Integer): Single; virtual; abstract;
    function GetFontMatrix: TPdfMatrix; virtual; abstract;
    function GetBoundingBox: TBoundingBox; virtual; abstract;
    function GetHeight(const Code: Integer): Single; virtual; abstract;
    function IsEmbedded: Boolean; virtual; abstract;
    function IsDamaged: Boolean; virtual; abstract;
    // PDFont.encode for one code point, which a CID font can do for some cases. False when it cannot (PDFBox throws).
    function TryEncode(const CodePoint: Integer; out Bytes: TBytes): Boolean; virtual; abstract;

    // PDVectorFont of the composite font that owns the CID font; see TPDFont. The caller owns the path.
    function TryGetPath(const Code: Integer; out Path: TPdfPath): Boolean; virtual; abstract;
    function TryGetNormalizedPath(const Code: Integer; out Path: TPdfPath): Boolean; virtual; abstract;
    function HasGlyph(const Code: Integer): Boolean; virtual; abstract;

    // The /W width of the CID of the code, else /DW (default 1000), in thousandths of text space. Acrobat prefers it to the
    // widths in the font program (PDFBOX-563).
    function GetWidth(const Code: Integer): Single;
    function HasExplicitWidth(const Code: Integer): Boolean;
    function GetAverageFontWidth: Single; virtual;
    // The position vector of the CID: /W2, else the default of /DW2 (half the width, /DW2 first value)
    function GetPositionVector(const Code: Integer): TPdfVector;
    // The vertical displacement of the CID: /W2, else the second value of /DW2 (default -1000)
    function GetVerticalDisplacementVectorY(const Code: Integer): Single;

    property CosObject: TCosDictionary read FDictionary;
    property Parent: TPDCIDFontParent read FParent;
    property Name: string read GetBaseFont;
  end;

implementation

uses
  System.Classes,
  System.Math,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.Number;

{ TPDCIDFont }

constructor TPDCIDFont.Create(const Dictionary: TCosDictionary; const Parent: TPDCIDFontParent);
begin
  inherited Create;
  if (not Assigned(Dictionary)) or (not Assigned(Parent)) then
  begin
    raise EArgumentNilException.Create('A CID font needs a font dictionary and a parent font');
  end;

  FDictionary := Dictionary;
  FParent := Parent;
  FWidths := TDictionary<Integer, TWidthEntry>.Create;
  FWidthRanges := TList<TWidthRange>.Create;
  FVerticalDisplacementY := TDictionary<Integer, Single>.Create;
  FPositionVectors := TDictionary<Integer, TPdfVector>.Create;
  FDisplacementRanges := TList<TDisplacementRange>.Create;
  FDw2[0] := DefaultDisplacementY;
  FDw2[1] := DefaultDisplacementVectorY;
  ReadWidths;
  ReadVerticalDisplacements;
end;

destructor TPDCIDFont.Destroy;
begin
  FDisplacementRanges.Free;
  FPositionVectors.Free;
  FVerticalDisplacementY.Free;
  FWidthRanges.Free;
  FWidths.Free;
  FFontDescriptor.Free;
  inherited;
end;

function TPDCIDFont.DocumentLog: TPdfLog;
begin
  Result := nil;
  if Assigned(FParent.Context) then
  begin
    Result := FParent.Context.Log;
  end;
end;

procedure TPDCIDFont.LogWarning(const Fmt: string; const Args: array of const);
begin
  const Log = DocumentLog;
  if Assigned(Log) then
  begin
    Log.Warning(Fmt, Args);
  end;
end;

class function TPDCIDFont.DescribeObject(const Item: TCosBase): string;
begin
  if Assigned(Item) then
  begin
    Result := Item.ClassName;
  end
  else
  begin
    Result := 'null';
  end;
end;

class function TPDCIDFont.ReadStreamBytes(const Stream: TCosStream): TBytes;
begin
  const Decoded = Stream.CreateDecodedStream;
  try
    if Decoded.Size > MaxInt then
    begin
      raise EPdfLimitExceededException.Create('The font file is too large');
    end;
    SetLength(Result, Decoded.Size);
    Decoded.Position := 0;
    if Length(Result) > 0 then
    begin
      Decoded.ReadBuffer(Result, Length(Result));
    end;
  finally
    Decoded.Free;
  end;
end;

class function TPDCIDFont.IsRecoverableFailure(const Failure: Exception): Boolean;
begin
  Result := ((Failure is EPdfException) or TPdfFailure.IsInputFailure(Failure));
end;

function TPDCIDFont.TryGetNumberAt(const Values: TCosArray; const Index: Integer; out Number: TCosBase): Boolean;
begin
  Number := nil;
  Result := ((Index >= 0) and (Index < Values.Count));
  if Result then
  begin
    Number := Values.GetObject(Index);
    Result := (Number is TCosNumber);
  end;
end;

procedure TPDCIDFont.ReadWidths;
begin
  // See 9.7.4.3, "Glyph Metrics in CIDFonts"
  var WArray: TCosArray;
  if not FDictionary.TryGetCosArray(TCosNames.W, WArray) then
  begin
    Exit;
  end;

  const Size = WArray.Count;
  var Counter := 0;
  while Counter < (Size - 1) do
  begin
    const FirstCodeBase = WArray.GetObject(Counter);
    Inc(Counter);
    if not (FirstCodeBase is TCosNumber) then
    begin
      LogWarning('Expected a number array member, got %s', [DescribeObject(FirstCodeBase)]);
      Continue;
    end;

    const FirstCode = TCosNumber(FirstCodeBase).IntValue;
    const Next = WArray.GetObject(Counter);
    Inc(Counter);
    if Next is TCosArray then
    begin
      ReadWidthArray(FirstCode, TCosArray(Next));
      Continue;
    end;

    if Counter >= Size then
    begin
      LogWarning('premature end of widths array', []);
      Break;
    end;

    const RangeWidthBase = WArray.GetObject(Counter);
    Inc(Counter);
    if not ((Next is TCosNumber) and (RangeWidthBase is TCosNumber)) then
    begin
      LogWarning('Expected two numbers, got %s and %s', [DescribeObject(Next), DescribeObject(RangeWidthBase)]);
      Continue;
    end;
    PutWidthRange(FirstCode, TCosNumber(Next).IntValue, TCosNumber(RangeWidthBase).FloatValue);
  end;
end;

procedure TPDCIDFont.ReadWidthArray(const StartRange: Integer; const Values: TCosArray);
begin
  for var Index := 0 to Values.Count - 1 do
  begin
    const WidthBase = Values.GetObject(Index);
    if WidthBase is TCosNumber then
    begin
      PutWidth(Int64(StartRange) + Index, TCosNumber(WidthBase).FloatValue);
    end
    else
    begin
      LogWarning('Expected a number array member, got %s', [DescribeObject(WidthBase)]);
    end;
  end;
end;

procedure TPDCIDFont.PutWidth(const CID: Int64; const Width: Single);
begin
  // A CID outside the range of Integer cannot be looked up, since the CMaps give Integer CIDs
  if (CID < Low(Integer)) or (CID > High(Integer)) then
  begin
    Exit;
  end;

  const Entry = FWidths.ContainsKey(Integer(CID));
  if (not Entry) and (FWidths.Count >= MaxWidthEntries) then
  begin
    LogWarning('Too many widths in the /W array of font %s, ignoring the rest', [GetBaseFont]);
    Exit;
  end;

  Inc(FSequence);
  var Value: TWidthEntry;
  Value.Width := Width;
  Value.Sequence := FSequence;
  FWidths.AddOrSetValue(Integer(CID), Value);
end;

procedure TPDCIDFont.PutWidthRange(const FirstCID, LastCID: Integer; const Width: Single);
begin
  if FirstCID > LastCID then
  begin
    Exit;
  end;

  const Count = Int64(LastCID) - FirstCID + 1;
  const IsSmall = ((Count <= WidthRangeExpandLimit) and ((FWidths.Count + Count) <= MaxWidthEntries));
  if IsSmall then
  begin
    for var CID := FirstCID to LastCID do
    begin
      PutWidth(CID, Width);
    end;
    Exit;
  end;

  if FWidthRanges.Count >= MaxWidthRanges then
  begin
    LogWarning('Too many width ranges in the /W array of font %s, ignoring the rest', [GetBaseFont]);
    Exit;
  end;

  Inc(FSequence);
  var Range: TWidthRange;
  Range.First := FirstCID;
  Range.Last := LastCID;
  Range.Width := Width;
  Range.Sequence := FSequence;
  FWidthRanges.Add(Range);
end;

procedure TPDCIDFont.ReadVerticalDisplacements;
begin
  // Default position vector and vertical displacement vector
  ReadDefaultDisplacements;

  // Vertical metrics for individual CIDs
  var Entries: TCosArray;
  if FDictionary.TryGetCosArray(TCosNames.W2, Entries) then
  begin
    ReadDisplacementEntries(Entries);
  end;
end;

procedure TPDCIDFont.ReadDefaultDisplacements;
begin
  var Dw2Array: TCosArray;
  if not FDictionary.TryGetCosArray(TCosNames.DW2, Dw2Array) then
  begin
    Exit;
  end;

  var First: TCosBase;
  var Second: TCosBase;
  if TryGetNumberAt(Dw2Array, 0, First) and TryGetNumberAt(Dw2Array, 1, Second) then
  begin
    FDw2[0] := TCosNumber(First).FloatValue;
    FDw2[1] := TCosNumber(Second).FloatValue;
  end;
end;

procedure TPDCIDFont.ReadDisplacementEntries(const Entries: TCosArray);
begin
  // PDFBox fails with a ClassCastException on an entry that is not a number; the entries that were read stay
  var Index := 0;
  while Index < Entries.Count do
  begin
    var FirstBase: TCosBase;
    if not TryGetNumberAt(Entries, Index, FirstBase) then
    begin
      LogWarning('Invalid /W2 array in font %s', [GetBaseFont]);
      Exit;
    end;

    const FirstCID = TCosNumber(FirstBase).IntValue;
    const Next = Entries.GetObject(Index + 1);
    if Next is TCosArray then
    begin
      ReadDisplacementArray(FirstCID, TCosArray(Next));
      Inc(Index, 2);
      Continue;
    end;

    var LastBase: TCosBase;
    var Displacement: TCosBase;
    var VectorX: TCosBase;
    var VectorY: TCosBase;
    const IsComplete = (TryGetNumberAt(Entries, Index + 1, LastBase) and TryGetNumberAt(Entries, Index + 2, Displacement) and
                        TryGetNumberAt(Entries, Index + 3, VectorX) and TryGetNumberAt(Entries, Index + 4, VectorY));
    if not IsComplete then
    begin
      LogWarning('Invalid /W2 array in font %s', [GetBaseFont]);
      Exit;
    end;

    AddDisplacementRange(FirstCID, TCosNumber(LastBase).IntValue, TCosNumber(Displacement).FloatValue,
                         TPdfVector.Create(TCosNumber(VectorX).FloatValue, TCosNumber(VectorY).FloatValue));
    Inc(Index, 5);
  end;
end;

procedure TPDCIDFont.ReadDisplacementArray(const FirstCID: Integer; const Values: TCosArray);
begin
  var Index := 0;
  while Index < Values.Count do
  begin
    var Displacement: TCosBase;
    var VectorX: TCosBase;
    var VectorY: TCosBase;
    const IsComplete = (TryGetNumberAt(Values, Index, Displacement) and TryGetNumberAt(Values, Index + 1, VectorX) and
                        TryGetNumberAt(Values, Index + 2, VectorY));
    if not IsComplete then
    begin
      LogWarning('Invalid /W2 array in font %s', [GetBaseFont]);
      Exit;
    end;

    const CID = Int64(FirstCID) + (Index div 3);
    if CID <= High(Integer) then
    begin
      FVerticalDisplacementY.AddOrSetValue(Integer(CID), TCosNumber(Displacement).FloatValue);
      FPositionVectors.AddOrSetValue(Integer(CID), TPdfVector.Create(TCosNumber(VectorX).FloatValue, TCosNumber(VectorY).FloatValue));
    end;
    Inc(Index, 3);
  end;
end;

procedure TPDCIDFont.AddDisplacementRange(const FirstCID, LastCID: Integer; const Displacement: Single; const PositionVector: TPdfVector);
begin
  if FDisplacementRanges.Count >= MaxDisplacementRanges then
  begin
    LogWarning('Too many ranges in the /W2 array of font %s, ignoring the rest', [GetBaseFont]);
    Exit;
  end;

  var Range: TDisplacementRange;
  Range.First := FirstCID;
  Range.Last := LastCID;
  Range.PositionVector := PositionVector;
  Range.Displacement := Displacement;
  FDisplacementRanges.Add(Range);
end;

function TPDCIDFont.TryGetFontDescriptor(out Descriptor: TPDFontDescriptor): Boolean;
begin
  if not Assigned(FFontDescriptor) then
  begin
    var DescriptorDictionary: TCosDictionary;
    if FDictionary.TryGetCosDictionary(TCosNames.FontDescriptor, DescriptorDictionary) then
    begin
      FFontDescriptor := TPDFontDescriptor.Create(DescriptorDictionary);
    end;
  end;
  Descriptor := FFontDescriptor;
  Result := Assigned(FFontDescriptor);
end;

function TPDCIDFont.TryGetCIDSystemInfo(out Info: TPDCIDSystemInfo): Boolean;
begin
  var InfoDictionary: TCosDictionary;
  if FDictionary.TryGetCosDictionary(TCosNames.CIDSystemInfo, InfoDictionary) then
  begin
    Exit(TPDCIDSystemInfo.TryFromDictionary(InfoDictionary, Info));
  end;
  Info := TPDCIDSystemInfo.Create('', '', -1);
  Result := False;
end;

function TPDCIDFont.GetBaseFont: string;
begin
  Result := FDictionary.GetNameAsString(TCosNames.BaseFont, '');
end;

function TPDCIDFont.GetDefaultWidth: Single;
begin
  // Like PDFBox, a /DW of zero is read again
  if FDefaultWidth = 0 then
  begin
    var Base: TCosBase;
    if FDictionary.TryGetDictionaryObject(TCosNames.DW, Base) and (Base is TCosNumber) then
    begin
      FDefaultWidth := TCosNumber(Base).FloatValue;
    end
    else
    begin
      FDefaultWidth := DefaultCIDWidth;
    end;
  end;
  Result := FDefaultWidth;
end;

function TPDCIDFont.TryGetWidthForCID(const CID: Integer; out Width: Single): Boolean;
begin
  Width := 0;
  var Entry: TWidthEntry;
  Result := FWidths.TryGetValue(CID, Entry);
  var BestSequence := -1;
  if Result then
  begin
    Width := Entry.Width;
    BestSequence := Entry.Sequence;
  end;

  // The sequence numbers rise along the list, so the last range that matches is the one that was put last
  for var Index := FWidthRanges.Count - 1 downto 0 do
  begin
    const Range = FWidthRanges[Index];
    const Matches = ((CID >= Range.First) and (CID <= Range.Last) and (Range.Sequence > BestSequence));
    if Matches then
    begin
      Width := Range.Width;
      Exit(True);
    end;
  end;
end;

function TPDCIDFont.GetWidthForCID(const CID: Integer): Single;
begin
  if not TryGetWidthForCID(CID, Result) then
  begin
    Result := GetDefaultWidth;
  end;
end;

function TPDCIDFont.GetWidth(const Code: Integer): Single;
begin
  // These widths are supposed to be consistent with the actual widths given in the CIDFont program, but PDFBOX-563 shows
  // that when they are not, Acrobat overrides the embedded font widths with the widths given in the font dictionary
  Result := GetWidthForCID(CodeToCID(Code));
end;

function TPDCIDFont.HasExplicitWidth(const Code: Integer): Boolean;
begin
  var Width: Single;
  Result := TryGetWidthForCID(CodeToCID(Code), Width);
end;

function TPDCIDFont.CalculateAverageWidth: Single;
begin
  // PDFBox sums over the values of a HashMap, which for small CIDs is in order of the CID
  var CIDs := FWidths.Keys.ToArray;
  TArray.Sort<Integer>(CIDs);

  var TotalWidths: Single := 0;
  var CharacterCount: Int64 := 0;
  for var CID in CIDs do
  begin
    const Width = FWidths[CID].Width;
    if Width > 0 then
    begin
      TotalWidths := TotalWidths + Width;
      Inc(CharacterCount);
    end;
  end;

  // A range counts for every CID in it
  for var Range in FWidthRanges do
  begin
    if Range.Width > 0 then
    begin
      const Count = Int64(Range.Last) - Range.First + 1;
      TotalWidths := TotalWidths + (Range.Width * Count);
      Inc(CharacterCount, Count);
    end;
  end;

  Result := 0;
  if CharacterCount <> 0 then
  begin
    Result := TotalWidths / CharacterCount;
  end;
  if (Result <= 0) or IsNan(Result) then
  begin
    Result := GetDefaultWidth;
  end;
end;

function TPDCIDFont.GetAverageFontWidth: Single;
begin
  // This is highly suspicious: the average glyph width is not usually a good metric
  if FAverageWidth = 0 then
  begin
    FAverageWidth := CalculateAverageWidth;
  end;
  Result := FAverageWidth;
end;

function TPDCIDFont.TryGetDisplacementRange(const CID: Integer; out Range: TDisplacementRange): Boolean;
begin
  Range := Default(TDisplacementRange);
  for var Candidate in FDisplacementRanges do
  begin
    if (CID >= Candidate.First) and (CID <= Candidate.Last) then
    begin
      Range := Candidate;
      Exit(True);
    end;
  end;
  Result := False;
end;

function TPDCIDFont.GetPositionVector(const Code: Integer): TPdfVector;
begin
  const CID = CodeToCID(Code);
  if FPositionVectors.TryGetValue(CID, Result) then
  begin
    Exit;
  end;

  var Range: TDisplacementRange;
  if TryGetDisplacementRange(CID, Range) then
  begin
    Exit(Range.PositionVector);
  end;
  Result := TPdfVector.Create(GetWidthForCID(CID) / 2, FDw2[0]);
end;

function TPDCIDFont.GetVerticalDisplacementVectorY(const Code: Integer): Single;
begin
  const CID = CodeToCID(Code);
  if FVerticalDisplacementY.TryGetValue(CID, Result) then
  begin
    Exit;
  end;

  var Range: TDisplacementRange;
  if TryGetDisplacementRange(CID, Range) then
  begin
    Exit(Range.Displacement);
  end;
  Result := FDw2[1];
end;

function TPDCIDFont.TryReadCIDToGIDMap(out Map: TBytes): Boolean;
begin
  Map := nil;
  var Stream: TCosStream;
  if not FDictionary.TryGetCosStream(TCosNames.CIDToGIDMap, Stream) then
  begin
    Exit(False);
  end;

  const Decoded = Stream.CreateDecodedStream;
  try
    const Count = Min(Decoded.Size, Int64(MaxCIDToGIDBytes));
    if Count < Decoded.Size then
    begin
      LogWarning('The CIDToGIDMap of font %s is too large, only the first %d bytes are used', [GetBaseFont, MaxCIDToGIDBytes]);
    end;

    // An odd last byte makes no entry
    SetLength(Map, Integer(Count) and (not 1));
    Decoded.Position := 0;
    if Length(Map) > 0 then
    begin
      Decoded.ReadBuffer(Map, Length(Map));
    end;
  finally
    Decoded.Free;
  end;
  Result := True;
end;

class function TPDCIDFont.MapCIDToGID(const Map: TBytes; const CID: Integer): Integer;
begin
  Result := 0;
  if (CID >= 0) and (CID < (Length(Map) div 2)) then
  begin
    const Offset = CID * 2;
    Result := (Map[Offset] shl 8) or Map[Offset + 1];
  end;
end;

end.
