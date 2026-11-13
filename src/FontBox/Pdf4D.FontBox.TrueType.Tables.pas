// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/TTFTable.java (3.0.8)
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/HeaderTable.java (3.0.8)
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/HorizontalHeaderTable.java (3.0.8)
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/MaximumProfileTable.java (3.0.8)
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/HorizontalMetricsTable.java (3.0.8)
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/NameRecord.java (3.0.8)
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/NamingTable.java (3.0.8)
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/OS2WindowsMetricsTable.java (3.0.8)
unit Pdf4D.FontBox.TrueType.Tables;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.Log,
  Pdf4D.FontBox.FontBoxFont,
  Pdf4D.FontBox.TrueType.DataStream;

type
  TTTFTableHost = class;

  // A table that is not parsed (yet) has no fields of its own; its bytes stay available through the font
  TTTFTable = class
  private
    FTag: string;
    FCheckSum: Int64;
    FOffset: Int64;
    FLength: Int64;

  protected
    FInitialized: Boolean;

  public
    constructor Create(const Tag: string; const CheckSum, Offset, Length: Int64);

    procedure Read(const Host: TTTFTableHost; const Data: TTTFDataStream); virtual;

    property Tag: string read FTag;
    property CheckSum: Int64 read FCheckSum;
    property Offset: Int64 read FOffset;
    property Length: Int64 read FLength;
    property Initialized: Boolean read FInitialized;
  end;

  THeaderTable = class(TTTFTable)
  public
    const TableTag = 'head';
    const MacStyleBold = 1;
    const MacStyleItalic = 2;

  private
    FVersion: Single;
    FFontRevision: Single;
    FCheckSumAdjustment: Int64;
    FMagicNumber: Int64;
    FFlags: Integer;
    FUnitsPerEm: Integer;
    FCreated: TDateTime;
    FModified: TDateTime;
    FXMin: SmallInt;
    FYMin: SmallInt;
    FXMax: SmallInt;
    FYMax: SmallInt;
    FMacStyle: Integer;
    FLowestRecPPEM: Integer;
    FFontDirectionHint: SmallInt;
    FIndexToLocFormat: SmallInt;
    FGlyphDataFormat: SmallInt;

  public
    procedure Read(const Host: TTTFTableHost; const Data: TTTFDataStream); override;

    property Version: Single read FVersion;
    property FontRevision: Single read FFontRevision;
    property CheckSumAdjustment: Int64 read FCheckSumAdjustment;
    property MagicNumber: Int64 read FMagicNumber;
    property Flags: Integer read FFlags;
    property UnitsPerEm: Integer read FUnitsPerEm;
    property Created: TDateTime read FCreated;
    property Modified: TDateTime read FModified;
    property XMin: SmallInt read FXMin;
    property YMin: SmallInt read FYMin;
    property XMax: SmallInt read FXMax;
    property YMax: SmallInt read FYMax;
    property MacStyle: Integer read FMacStyle;
    property LowestRecPPEM: Integer read FLowestRecPPEM;
    property FontDirectionHint: SmallInt read FFontDirectionHint;
    property IndexToLocFormat: SmallInt read FIndexToLocFormat;
    property GlyphDataFormat: SmallInt read FGlyphDataFormat;
  end;

  THorizontalHeaderTable = class(TTTFTable)
  public
    const TableTag = 'hhea';

  private
    FVersion: Single;
    FAscender: SmallInt;
    FDescender: SmallInt;
    FLineGap: SmallInt;
    FAdvanceWidthMax: Integer;
    FMinLeftSideBearing: SmallInt;
    FMinRightSideBearing: SmallInt;
    FXMaxExtent: SmallInt;
    FCaretSlopeRise: SmallInt;
    FCaretSlopeRun: SmallInt;
    FMetricDataFormat: SmallInt;
    FNumberOfHMetrics: Integer;

  public
    procedure Read(const Host: TTTFTableHost; const Data: TTTFDataStream); override;

    property Version: Single read FVersion;
    property Ascender: SmallInt read FAscender;
    property Descender: SmallInt read FDescender;
    property LineGap: SmallInt read FLineGap;
    property AdvanceWidthMax: Integer read FAdvanceWidthMax;
    property MinLeftSideBearing: SmallInt read FMinLeftSideBearing;
    property MinRightSideBearing: SmallInt read FMinRightSideBearing;
    property XMaxExtent: SmallInt read FXMaxExtent;
    property CaretSlopeRise: SmallInt read FCaretSlopeRise;
    property CaretSlopeRun: SmallInt read FCaretSlopeRun;
    property MetricDataFormat: SmallInt read FMetricDataFormat;
    property NumberOfHMetrics: Integer read FNumberOfHMetrics;
  end;

  TMaximumProfileTable = class(TTTFTable)
  public
    const TableTag = 'maxp';

  private
    FVersion: Single;
    FNumGlyphs: Integer;
    FMaxPoints: Integer;
    FMaxContours: Integer;
    FMaxCompositePoints: Integer;
    FMaxCompositeContours: Integer;
    FMaxZones: Integer;
    FMaxTwilightPoints: Integer;
    FMaxStorage: Integer;
    FMaxFunctionDefs: Integer;
    FMaxInstructionDefs: Integer;
    FMaxStackElements: Integer;
    FMaxSizeOfInstructions: Integer;
    FMaxComponentElements: Integer;
    FMaxComponentDepth: Integer;

  public
    procedure Read(const Host: TTTFTableHost; const Data: TTTFDataStream); override;

    property Version: Single read FVersion;
    property NumGlyphs: Integer read FNumGlyphs;
    property MaxPoints: Integer read FMaxPoints;
    property MaxContours: Integer read FMaxContours;
    property MaxCompositePoints: Integer read FMaxCompositePoints;
    property MaxCompositeContours: Integer read FMaxCompositeContours;
    property MaxZones: Integer read FMaxZones;
    property MaxTwilightPoints: Integer read FMaxTwilightPoints;
    property MaxStorage: Integer read FMaxStorage;
    property MaxFunctionDefs: Integer read FMaxFunctionDefs;
    property MaxInstructionDefs: Integer read FMaxInstructionDefs;
    property MaxStackElements: Integer read FMaxStackElements;
    property MaxSizeOfInstructions: Integer read FMaxSizeOfInstructions;
    property MaxComponentElements: Integer read FMaxComponentElements;
    property MaxComponentDepth: Integer read FMaxComponentDepth;
  end;

  // What a table needs from the font that holds it while it is being read. Later tables go through TryGetTable.
  TTTFTableHost = class abstract(TFontBoxFont)
  private
    FLog: TPdfLog;

  public
    function NumberOfGlyphs: Integer; virtual; abstract;
    function HorizontalHeader: THorizontalHeaderTable; virtual; abstract;
    function TryGetTable(const Tag: string; out Table: TTTFTable): Boolean; virtual; abstract;

    procedure LogWarning(const Message: string);

    // Not owned. Only set while the font is parsed, because the log may be gone when a table is read later.
    property Log: TPdfLog read FLog write FLog;
  end;

  THorizontalMetricsTable = class(TTTFTable)
  public
    const TableTag = 'hmtx';

  private
    const DefaultAdvanceWidth = 250;

  private
    FAdvanceWidth: TArray<Integer>;
    FLeftSideBearing: TArray<SmallInt>;
    FNonHorizontalLeftSideBearing: TArray<SmallInt>;
    FNumHMetrics: Integer;

  public
    procedure Read(const Host: TTTFTableHost; const Data: TTTFDataStream); override;

    // A glyph beyond the explicit metrics gets the last advance width, as in PDFBox
    function GetAdvanceWidth(const GID: Integer): Integer;
    function GetLeftSideBearing(const GID: Integer): Integer;
  end;

  TNameRecord = record
  public
    const PlatformUnicode = 0;
    const PlatformMacintosh = 1;
    const PlatformIso = 2;
    const PlatformWindows = 3;

    const EncodingUnicode10 = 0;
    const EncodingUnicode11 = 1;
    const EncodingUnicode20Bmp = 3;
    const EncodingUnicode20Full = 4;
    const LanguageUnicode = 0;

    const EncodingWindowsSymbol = 0;
    const EncodingWindowsUnicodeBmp = 1;
    const EncodingWindowsUnicodeUcs4 = 10;
    const LanguageWindowsEnUs = $0409;

    const EncodingMacintoshRoman = 0;
    const LanguageMacintoshEnglish = 0;

    const NameCopyright = 0;
    const NameFontFamilyName = 1;
    const NameFontSubFamilyName = 2;
    const NameUniqueFontId = 3;
    const NameFullFontName = 4;
    const NameVersion = 5;
    const NamePostScriptName = 6;
    const NameTrademark = 7;

  public
    PlatformId: Integer;
    PlatformEncodingId: Integer;
    LanguageId: Integer;
    NameId: Integer;
    StringLength: Integer;
    StringOffset: Integer;
    HasValue: Boolean;
    Value: string;
  end;

  // The strings of the table are skipped (and logged) when they do not lie inside the table or exceed the string budget
  TNamingTable = class(TTTFTable)
  public
    const TableTag = 'name';

  private
    const MaximumTotalStringBytes = 16 * 1024 * 1024;
    const BomBigEndian = $FEFF;
    const BomLittleEndian = $FFFE;
    const RecordSize = 12;
    const HeaderSize = 6;

  private
    FNameRecords: TList<TNameRecord>;
    FLookup: TDictionary<UInt64, Integer>;
    FFontFamily: string;
    FFontSubFamily: string;
    FPostScriptName: string;

    class function LookupKey(const NameId, PlatformId, EncodingId, LanguageId: Integer): UInt64; static;
    class function DecodeUtf16WithByteOrderMark(const Bytes: TBytes): string; static;
    class function IsUtf16(const NameRecord: TNameRecord): Boolean; static;

    procedure ReadRecords(const Data: TTTFDataStream; const NumberOfNameRecords: Integer);
    procedure ReadStrings(const Host: TTTFTableHost; const Data: TTTFDataStream);
    function ReadString(const Data: TTTFDataStream; const NameRecord: TNameRecord): string;
    procedure FillLookup;
    procedure ReadInterestingStrings;
    function TryGetEnglishName(const NameId: Integer; out Name: string): Boolean;

  public
    destructor Destroy; override;

    procedure Read(const Host: TTTFTableHost; const Data: TTTFDataStream); override;

    function TryGetName(const NameId, PlatformId, EncodingId, LanguageId: Integer; out Name: string): Boolean;
    // Raises EPdfParseException when the font has no such name
    function GetName(const NameId, PlatformId, EncodingId, LanguageId: Integer): string;

    property NameRecords: TList<TNameRecord> read FNameRecords;
    // Empty when the font has no such name
    property FontFamily: string read FFontFamily;
    property FontSubFamily: string read FFontSubFamily;
    property PostScriptName: string read FPostScriptName;
  end;

  TOS2WindowsMetricsTable = class(TTTFTable)
  public
    const TableTag = 'OS/2';

    const WeightClassThin = 100;
    const WeightClassUltraLight = 200;
    const WeightClassLight = 300;
    const WeightClassNormal = 400;
    const WeightClassMedium = 500;
    const WeightClassSemiBold = 600;
    const WeightClassBold = 700;
    const WeightClassExtraBold = 800;
    const WeightClassBlack = 900;

    const WidthClassUltraCondensed = 1;
    const WidthClassExtraCondensed = 2;
    const WidthClassCondensed = 3;
    const WidthClassSemiCondensed = 4;
    const WidthClassMedium = 5;
    const WidthClassSemiExpanded = 6;
    const WidthClassExpanded = 7;
    const WidthClassExtraExpanded = 8;
    const WidthClassUltraExpanded = 9;

    const FamilyClassNoClassification = 0;
    const FamilyClassOldstyleSerifs = 1;
    const FamilyClassTransitionalSerifs = 2;
    const FamilyClassModernSerifs = 3;
    const FamilyClassClaredonSerifs = 4;
    const FamilyClassSlabSerifs = 5;
    const FamilyClassFreeformSerifs = 7;
    const FamilyClassSansSerif = 8;
    const FamilyClassOrnamentals = 9;
    const FamilyClassScripts = 10;
    const FamilyClassSymbolic = 12;

    const FsTypeRestricted = $0002;
    const FsTypePreviewAndPrint = $0004;
    const FsTypeEditable = $0008;
    const FsTypeNoSubsetting = $0100;
    const FsTypeBitmapOnly = $0200;

  private
    const PanoseLength = 10;

  private
    FVersion: Integer;
    FAverageCharWidth: SmallInt;
    FWeightClass: Integer;
    FWidthClass: Integer;
    FFsType: SmallInt;
    FSubscriptXSize: SmallInt;
    FSubscriptYSize: SmallInt;
    FSubscriptXOffset: SmallInt;
    FSubscriptYOffset: SmallInt;
    FSuperscriptXSize: SmallInt;
    FSuperscriptYSize: SmallInt;
    FSuperscriptXOffset: SmallInt;
    FSuperscriptYOffset: SmallInt;
    FStrikeoutSize: SmallInt;
    FStrikeoutPosition: SmallInt;
    FFamilyClass: Integer;
    FPanose: TBytes;
    FUnicodeRange1: Int64;
    FUnicodeRange2: Int64;
    FUnicodeRange3: Int64;
    FUnicodeRange4: Int64;
    FAchVendId: string;
    FFsSelection: Integer;
    FFirstCharIndex: Integer;
    FLastCharIndex: Integer;
    FTypoAscender: Integer;
    FTypoDescender: Integer;
    FTypoLineGap: Integer;
    FWinAscent: Integer;
    FWinDescent: Integer;
    FCodePageRange1: Int64;
    FCodePageRange2: Int64;
    FXHeight: Integer;
    FCapHeight: Integer;
    FDefaultChar: Integer;
    FBreakChar: Integer;
    FMaxContext: Integer;

    procedure ReadBasics(const Data: TTTFDataStream);
    function TryReadMetrics(const Data: TTTFDataStream): Boolean;
    function TryReadCodePageRanges(const Host: TTTFTableHost; const Data: TTTFDataStream): Boolean;
    function TryReadHeights(const Host: TTTFTableHost; const Data: TTTFDataStream): Boolean;

  public
    constructor Create(const Tag: string; const CheckSum, Offset, Length: Int64);

    procedure Read(const Host: TTTFTableHost; const Data: TTTFDataStream); override;

    property Version: Integer read FVersion;
    property AverageCharWidth: SmallInt read FAverageCharWidth;
    property WeightClass: Integer read FWeightClass;
    property WidthClass: Integer read FWidthClass;
    property FsType: SmallInt read FFsType;
    property SubscriptXSize: SmallInt read FSubscriptXSize;
    property SubscriptYSize: SmallInt read FSubscriptYSize;
    property SubscriptXOffset: SmallInt read FSubscriptXOffset;
    property SubscriptYOffset: SmallInt read FSubscriptYOffset;
    property SuperscriptXSize: SmallInt read FSuperscriptXSize;
    property SuperscriptYSize: SmallInt read FSuperscriptYSize;
    property SuperscriptXOffset: SmallInt read FSuperscriptXOffset;
    property SuperscriptYOffset: SmallInt read FSuperscriptYOffset;
    property StrikeoutSize: SmallInt read FStrikeoutSize;
    property StrikeoutPosition: SmallInt read FStrikeoutPosition;
    property FamilyClass: Integer read FFamilyClass;
    property Panose: TBytes read FPanose;
    property UnicodeRange1: Int64 read FUnicodeRange1;
    property UnicodeRange2: Int64 read FUnicodeRange2;
    property UnicodeRange3: Int64 read FUnicodeRange3;
    property UnicodeRange4: Int64 read FUnicodeRange4;
    property AchVendId: string read FAchVendId;
    property FsSelection: Integer read FFsSelection;
    property FirstCharIndex: Integer read FFirstCharIndex;
    property LastCharIndex: Integer read FLastCharIndex;
    property TypoAscender: Integer read FTypoAscender;
    property TypoDescender: Integer read FTypoDescender;
    property TypoLineGap: Integer read FTypoLineGap;
    property WinAscent: Integer read FWinAscent;
    property WinDescent: Integer read FWinDescent;
    property CodePageRange1: Int64 read FCodePageRange1;
    property CodePageRange2: Int64 read FCodePageRange2;
    property XHeight: Integer read FXHeight;
    property CapHeight: Integer read FCapHeight;
    property DefaultChar: Integer read FDefaultChar;
    property BreakChar: Integer read FBreakChar;
    property MaxContext: Integer read FMaxContext;
  end;

implementation

uses
  System.Math,
  Pdf4D.Common.Defines;

{ TTTFTable }

constructor TTTFTable.Create(const Tag: string; const CheckSum, Offset, Length: Int64);
begin
  inherited Create;
  FTag := Tag;
  FCheckSum := CheckSum;
  FOffset := Offset;
  FLength := Length;
end;

procedure TTTFTable.Read(const Host: TTTFTableHost; const Data: TTTFDataStream);
begin
  FInitialized := True;
end;

{ THeaderTable }

procedure THeaderTable.Read(const Host: TTTFTableHost; const Data: TTTFDataStream);
begin
  FVersion := Data.Read32Fixed;
  FFontRevision := Data.Read32Fixed;
  FCheckSumAdjustment := Data.ReadUnsignedInt;
  FMagicNumber := Data.ReadUnsignedInt;
  FFlags := Data.ReadUnsignedShort;
  FUnitsPerEm := Data.ReadUnsignedShort;
  FCreated := Data.ReadLongDateTime;
  FModified := Data.ReadLongDateTime;
  FXMin := Data.ReadSignedShort;
  FYMin := Data.ReadSignedShort;
  FXMax := Data.ReadSignedShort;
  FYMax := Data.ReadSignedShort;
  FMacStyle := Data.ReadUnsignedShort;
  FLowestRecPPEM := Data.ReadUnsignedShort;
  FFontDirectionHint := Data.ReadSignedShort;
  FIndexToLocFormat := Data.ReadSignedShort;
  FGlyphDataFormat := Data.ReadSignedShort;
  FInitialized := True;
end;

{ THorizontalHeaderTable }

procedure THorizontalHeaderTable.Read(const Host: TTTFTableHost; const Data: TTTFDataStream);
begin
  FVersion := Data.Read32Fixed;
  FAscender := Data.ReadSignedShort;
  FDescender := Data.ReadSignedShort;
  FLineGap := Data.ReadSignedShort;
  FAdvanceWidthMax := Data.ReadUnsignedShort;
  FMinLeftSideBearing := Data.ReadSignedShort;
  FMinRightSideBearing := Data.ReadSignedShort;
  FXMaxExtent := Data.ReadSignedShort;
  FCaretSlopeRise := Data.ReadSignedShort;
  FCaretSlopeRun := Data.ReadSignedShort;
  // Five reserved fields
  for var Reserved := 1 to 5 do
  begin
    Data.ReadSignedShort;
  end;
  FMetricDataFormat := Data.ReadSignedShort;
  FNumberOfHMetrics := Data.ReadUnsignedShort;
  FInitialized := True;
end;

{ TMaximumProfileTable }

procedure TMaximumProfileTable.Read(const Host: TTTFTableHost; const Data: TTTFDataStream);
begin
  FVersion := Data.Read32Fixed;
  FNumGlyphs := Data.ReadUnsignedShort;
  if FVersion >= 1.0 then
  begin
    FMaxPoints := Data.ReadUnsignedShort;
    FMaxContours := Data.ReadUnsignedShort;
    FMaxCompositePoints := Data.ReadUnsignedShort;
    FMaxCompositeContours := Data.ReadUnsignedShort;
    FMaxZones := Data.ReadUnsignedShort;
    FMaxTwilightPoints := Data.ReadUnsignedShort;
    FMaxStorage := Data.ReadUnsignedShort;
    FMaxFunctionDefs := Data.ReadUnsignedShort;
    FMaxInstructionDefs := Data.ReadUnsignedShort;
    FMaxStackElements := Data.ReadUnsignedShort;
    FMaxSizeOfInstructions := Data.ReadUnsignedShort;
    FMaxComponentElements := Data.ReadUnsignedShort;
    FMaxComponentDepth := Data.ReadUnsignedShort;
    if FMaxComponentDepth = 0 then
    begin
      FMaxComponentDepth := 1;
    end;
  end;
  FInitialized := True;
end;

{ TTTFTableHost }

procedure TTTFTableHost.LogWarning(const Message: string);
begin
  if Assigned(FLog) then
  begin
    FLog.Warning(Message);
  end;
end;

{ THorizontalMetricsTable }

procedure THorizontalMetricsTable.Read(const Host: TTTFTableHost; const Data: TTTFDataStream);
begin
  FNumHMetrics := Host.HorizontalHeader.NumberOfHMetrics;
  const NumGlyphs = Host.NumberOfGlyphs;

  SetLength(FAdvanceWidth, FNumHMetrics);
  SetLength(FLeftSideBearing, FNumHMetrics);
  var BytesRead: Int64 := 0;
  for var Index := 0 to FNumHMetrics - 1 do
  begin
    FAdvanceWidth[Index] := Data.ReadUnsignedShort;
    FLeftSideBearing[Index] := Data.ReadSignedShort;
    Inc(BytesRead, 4);
  end;

  var NumberNonHorizontal := NumGlyphs - FNumHMetrics;
  if NumberNonHorizontal < 0 then
  begin
    NumberNonHorizontal := NumGlyphs;
  end;

  SetLength(FNonHorizontalLeftSideBearing, NumberNonHorizontal);
  for var Index := 0 to NumberNonHorizontal - 1 do
  begin
    const IsInsideTable = (BytesRead < Length);
    if not IsInsideTable then
    begin
      Break;
    end;

    FNonHorizontalLeftSideBearing[Index] := Data.ReadSignedShort;
    Inc(BytesRead, 2);
  end;
  FInitialized := True;
end;

function THorizontalMetricsTable.GetAdvanceWidth(const GID: Integer): Integer;
begin
  if GID < 0 then
  begin
    raise EPdfParseException.CreateFmt('Invalid glyph id %d', [GID]);
  end;

  const AdvanceCount = System.Length(FAdvanceWidth);
  if AdvanceCount = 0 then
  begin
    Exit(DefaultAdvanceWidth);
  end;

  if GID < FNumHMetrics then
  begin
    Result := FAdvanceWidth[GID];
  end
  else
  begin
    Result := FAdvanceWidth[AdvanceCount - 1];
  end;
end;

function THorizontalMetricsTable.GetLeftSideBearing(const GID: Integer): Integer;
begin
  if GID < 0 then
  begin
    raise EPdfParseException.CreateFmt('Invalid glyph id %d', [GID]);
  end;

  if System.Length(FLeftSideBearing) = 0 then
  begin
    Exit(0);
  end;

  if GID < FNumHMetrics then
  begin
    Exit(FLeftSideBearing[GID]);
  end;

  const NonHorizontalIndex = GID - FNumHMetrics;
  const HasBearing = (NonHorizontalIndex < System.Length(FNonHorizontalLeftSideBearing));
  if HasBearing then
  begin
    Result := FNonHorizontalLeftSideBearing[NonHorizontalIndex];
  end
  else
  begin
    Result := 0;
  end;
end;

{ TNamingTable }

destructor TNamingTable.Destroy;
begin
  FLookup.Free;
  FNameRecords.Free;
  inherited Destroy;
end;

class function TNamingTable.LookupKey(const NameId, PlatformId, EncodingId, LanguageId: Integer): UInt64;
begin
  Result := (UInt64(Word(NameId)) shl 48) or (UInt64(Word(PlatformId)) shl 32) or (UInt64(Word(EncodingId)) shl 16) or UInt64(Word(LanguageId));
end;

class function TNamingTable.IsUtf16(const NameRecord: TNameRecord): Boolean;
begin
  const IsWindowsUnicode = ((NameRecord.PlatformId = TNameRecord.PlatformWindows) and
                            ((NameRecord.PlatformEncodingId = TNameRecord.EncodingWindowsSymbol) or
                             (NameRecord.PlatformEncodingId = TNameRecord.EncodingWindowsUnicodeBmp)));
  const IsUnicodePlatform = (NameRecord.PlatformId = TNameRecord.PlatformUnicode);
  Result := (IsWindowsUnicode or IsUnicodePlatform);
end;

// Java's UTF_16 charset: a byte order mark decides the order, big-endian without one
class function TNamingTable.DecodeUtf16WithByteOrderMark(const Bytes: TBytes): string;
begin
  var FirstUnit := 0;
  const HasMark = (System.Length(Bytes) >= 2);
  if HasMark then
  begin
    FirstUnit := (Bytes[0] shl 8) or Bytes[1];
  end;

  if HasMark and (FirstUnit = BomLittleEndian) then
  begin
    Result := TEncoding.Unicode.GetString(Bytes, 2, System.Length(Bytes) - 2);
  end
  else if HasMark and (FirstUnit = BomBigEndian) then
  begin
    Result := TEncoding.BigEndianUnicode.GetString(Bytes, 2, System.Length(Bytes) - 2);
  end
  else
  begin
    Result := TEncoding.BigEndianUnicode.GetString(Bytes);
  end;
end;

procedure TNamingTable.Read(const Host: TTTFTableHost; const Data: TTTFDataStream);
begin
  Data.ReadUnsignedShort; // format selector
  const NumberOfNameRecords = Data.ReadUnsignedShort;
  Data.ReadUnsignedShort; // offset to the start of the string storage

  ReadRecords(Data, NumberOfNameRecords);
  ReadStrings(Host, Data);
  FillLookup;
  ReadInterestingStrings;
  FInitialized := True;
end;

procedure TNamingTable.ReadRecords(const Data: TTTFDataStream; const NumberOfNameRecords: Integer);
begin
  FreeAndNil(FNameRecords);
  FNameRecords := TList<TNameRecord>.Create;
  for var Index := 1 to NumberOfNameRecords do
  begin
    var NameRecord: TNameRecord;
    NameRecord.PlatformId := Data.ReadUnsignedShort;
    NameRecord.PlatformEncodingId := Data.ReadUnsignedShort;
    NameRecord.LanguageId := Data.ReadUnsignedShort;
    NameRecord.NameId := Data.ReadUnsignedShort;
    NameRecord.StringLength := Data.ReadUnsignedShort;
    NameRecord.StringOffset := Data.ReadUnsignedShort;
    NameRecord.HasValue := False;
    NameRecord.Value := '';
    FNameRecords.Add(NameRecord);
  end;
end;

function TNamingTable.ReadString(const Data: TTTFDataStream; const NameRecord: TNameRecord): string;
begin
  const Bytes = Data.ReadBytes(NameRecord.StringLength);
  if IsUtf16(NameRecord) then
  begin
    Result := DecodeUtf16WithByteOrderMark(Bytes);
  end
  else if (NameRecord.PlatformId = TNameRecord.PlatformIso) and (NameRecord.PlatformEncodingId = 1) then
  begin
    Result := TEncoding.BigEndianUnicode.GetString(Bytes);
  end
  else
  begin
    Result := '';
    SetLength(Result, System.Length(Bytes));
    for var Index := 0 to System.Length(Bytes) - 1 do
    begin
      Result[Index + 1] := Char(Bytes[Index]);
    end;
  end;
end;

procedure TNamingTable.ReadStrings(const Host: TTTFTableHost; const Data: TTTFDataStream);
begin
  const StorageStart = Offset + HeaderSize + (Int64(FNameRecords.Count) * RecordSize);
  const TableEnd = Offset + Length;
  var TotalStringBytes: Int64 := 0;
  for var Index := 0 to FNameRecords.Count - 1 do
  begin
    var NameRecord := FNameRecords[Index];

    const StringStart = StorageStart + NameRecord.StringOffset;
    const IsInsideTable = ((NameRecord.StringOffset <= Length) and (StringStart + NameRecord.StringLength <= TableEnd));
    const IsInsideBudget = (TotalStringBytes + NameRecord.StringLength <= MaximumTotalStringBytes);
    if not (IsInsideTable and IsInsideBudget) then
    begin
      Host.LogWarning(Format('Skip name record %d of the name table: its string does not fit', [Index]));
      Continue;
    end;

    Data.Seek(StringStart);
    NameRecord.Value := ReadString(Data, NameRecord);
    NameRecord.HasValue := True;
    FNameRecords[Index] := NameRecord;
    Inc(TotalStringBytes, NameRecord.StringLength);
  end;
end;

procedure TNamingTable.FillLookup;
begin
  FreeAndNil(FLookup);
  FLookup := TDictionary<UInt64, Integer>.Create;
  for var Index := 0 to FNameRecords.Count - 1 do
  begin
    const NameRecord = FNameRecords[Index];
    const Key = LookupKey(NameRecord.NameId, NameRecord.PlatformId, NameRecord.PlatformEncodingId, NameRecord.LanguageId);
    FLookup.AddOrSetValue(Key, Index);
  end;
end;

function TNamingTable.TryGetName(const NameId, PlatformId, EncodingId, LanguageId: Integer; out Name: string): Boolean;
begin
  Name := '';
  var Index: Integer;
  const Key = LookupKey(NameId, PlatformId, EncodingId, LanguageId);
  if not Assigned(FLookup) or not FLookup.TryGetValue(Key, Index) then
  begin
    Exit(False);
  end;

  const NameRecord = FNameRecords[Index];
  Result := NameRecord.HasValue;
  if Result then
  begin
    Name := NameRecord.Value;
  end;
end;

function TNamingTable.GetName(const NameId, PlatformId, EncodingId, LanguageId: Integer): string;
begin
  if not TryGetName(NameId, PlatformId, EncodingId, LanguageId, Result) then
  begin
    raise EPdfParseException.CreateFmt('The name table has no name %d for platform %d, encoding %d, language %d',
                                       [NameId, PlatformId, EncodingId, LanguageId]);
  end;
end;

function TNamingTable.TryGetEnglishName(const NameId: Integer; out Name: string): Boolean;
begin
  for var EncodingId := 4 downto 0 do
  begin
    if TryGetName(NameId, TNameRecord.PlatformUnicode, EncodingId, TNameRecord.LanguageUnicode, Name) then
    begin
      Exit(True);
    end;
  end;

  if TryGetName(NameId, TNameRecord.PlatformWindows, TNameRecord.EncodingWindowsUnicodeBmp, TNameRecord.LanguageWindowsEnUs, Name) then
  begin
    Exit(True);
  end;

  Result := TryGetName(NameId, TNameRecord.PlatformMacintosh, TNameRecord.EncodingMacintoshRoman, TNameRecord.LanguageMacintoshEnglish, Name);
end;

procedure TNamingTable.ReadInterestingStrings;
begin
  TryGetEnglishName(TNameRecord.NameFontFamilyName, FFontFamily);
  TryGetEnglishName(TNameRecord.NameFontSubFamilyName, FFontSubFamily);

  const HasMacintoshName = TryGetName(TNameRecord.NamePostScriptName, TNameRecord.PlatformMacintosh, TNameRecord.EncodingMacintoshRoman,
                                      TNameRecord.LanguageMacintoshEnglish, FPostScriptName);
  if not HasMacintoshName then
  begin
    TryGetName(TNameRecord.NamePostScriptName, TNameRecord.PlatformWindows, TNameRecord.EncodingWindowsUnicodeBmp,
               TNameRecord.LanguageWindowsEnUs, FPostScriptName);
  end;
  FPostScriptName := FPostScriptName.Trim;
end;

{ TOS2WindowsMetricsTable }

constructor TOS2WindowsMetricsTable.Create(const Tag: string; const CheckSum, Offset, Length: Int64);
begin
  inherited Create(Tag, CheckSum, Offset, Length);
  SetLength(FPanose, PanoseLength);
  FAchVendId := 'XXXX';
end;

procedure TOS2WindowsMetricsTable.ReadBasics(const Data: TTTFDataStream);
begin
  FVersion := Data.ReadUnsignedShort;
  FAverageCharWidth := Data.ReadSignedShort;
  FWeightClass := Data.ReadUnsignedShort;
  FWidthClass := Data.ReadUnsignedShort;
  FFsType := Data.ReadSignedShort;
  FSubscriptXSize := Data.ReadSignedShort;
  FSubscriptYSize := Data.ReadSignedShort;
  FSubscriptXOffset := Data.ReadSignedShort;
  FSubscriptYOffset := Data.ReadSignedShort;
  FSuperscriptXSize := Data.ReadSignedShort;
  FSuperscriptYSize := Data.ReadSignedShort;
  FSuperscriptXOffset := Data.ReadSignedShort;
  FSuperscriptYOffset := Data.ReadSignedShort;
  FStrikeoutSize := Data.ReadSignedShort;
  FStrikeoutPosition := Data.ReadSignedShort;
  FFamilyClass := Data.ReadSignedShort;
  FPanose := Data.ReadBytes(PanoseLength);
  FUnicodeRange1 := Data.ReadUnsignedInt;
  FUnicodeRange2 := Data.ReadUnsignedInt;
  FUnicodeRange3 := Data.ReadUnsignedInt;
  FUnicodeRange4 := Data.ReadUnsignedInt;
  FAchVendId := Data.ReadString(4, TTTFStringEncoding.Latin1);
  FFsSelection := Data.ReadUnsignedShort;
  FFirstCharIndex := Data.ReadUnsignedShort;
  FLastCharIndex := Data.ReadUnsignedShort;
end;

// Some legacy fonts end here
function TOS2WindowsMetricsTable.TryReadMetrics(const Data: TTTFDataStream): Boolean;
begin
  try
    FTypoAscender := Data.ReadSignedShort;
    FTypoDescender := Data.ReadSignedShort;
    FTypoLineGap := Data.ReadSignedShort;
    FWinAscent := Data.ReadUnsignedShort;
    FWinDescent := Data.ReadUnsignedShort;
    Result := True;
  except
    on EPdfParseException do
    begin
      Result := False;
    end;
  end;
end;

function TOS2WindowsMetricsTable.TryReadCodePageRanges(const Host: TTTFTableHost; const Data: TTTFDataStream): Boolean;
begin
  try
    FCodePageRange1 := Data.ReadUnsignedInt;
    FCodePageRange2 := Data.ReadUnsignedInt;
    Result := True;
  except
    on EPdfParseException do
    begin
      FVersion := 0;
      Host.LogWarning('Could not read all expected parts of OS/2 version >= 1, setting version to 0');
      Result := False;
    end;
  end;
end;

function TOS2WindowsMetricsTable.TryReadHeights(const Host: TTTFTableHost; const Data: TTTFDataStream): Boolean;
begin
  try
    FXHeight := Data.ReadSignedShort;
    FCapHeight := Data.ReadSignedShort;
    FDefaultChar := Data.ReadUnsignedShort;
    FBreakChar := Data.ReadUnsignedShort;
    FMaxContext := Data.ReadUnsignedShort;
    Result := True;
  except
    on EPdfParseException do
    begin
      FVersion := 1;
      Host.LogWarning('Could not read all expected parts of OS/2 version >= 2, setting version to 1');
      Result := False;
    end;
  end;
end;

procedure TOS2WindowsMetricsTable.Read(const Host: TTTFTableHost; const Data: TTTFDataStream);
begin
  ReadBasics(Data);

  FInitialized := True;
  if not TryReadMetrics(Data) then
  begin
    Exit;
  end;

  if (FVersion >= 1) and not TryReadCodePageRanges(Host, Data) then
  begin
    Exit;
  end;

  if (FVersion >= 2) and not TryReadHeights(Host, Data) then
  begin
    Exit;
  end;
end;

end.
