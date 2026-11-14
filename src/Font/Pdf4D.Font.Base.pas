// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/font/PDFont.java (3.0.8)
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/font/PDFontLike.java (3.0.8)
// Port of: PDSimpleFont.hasExplicitWidth (3.0.8), because every font that has /Widths answers it the same way
// Port of: PDType1FontEmbedder.buildFontDescriptor(FontMetrics) (3.0.8), for the descriptor of a standard 14 font
unit Pdf4D.Font.Base;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.Matrix,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Font.Descriptor,
  Pdf4D.Font.GlyphList,
  Pdf4D.FontBox.Afm,
  Pdf4D.FontBox.BoundingBox,
  Pdf4D.FontBox.CMap,
  Pdf4D.Model.DocumentContext;

type
  // The parsed ToUnicode CMap of one stream, kept by the document context so that fonts that share the stream parse and
  // charge it once. CMap is nil for a stream that could not be parsed (a failure is not tried again either).
  TToUnicodeCacheEntry = class
  private
    FCMap: TCMap;

  public
    constructor Create(const CMap: TCMap);
    destructor Destroy; override;

    property CMap: TCMap read FCMap;
  end;

  // The font dictionary, its widths and its /ToUnicode CMap. The subclasses (simple fonts, Type 3 and composite fonts)
  // add the encoding and the font program. A font belongs to the document context that cached it; it is not thread
  // safe, like the document.
  TPDFont = class abstract
  private
    const WidthCacheLimit = 65536;
    const SpaceCode = 32;
    const FallbackSpaceWidth = 250;
    const IdentityPrefix = 'Identity-';
    const FlagSymbolic = 4;
    const FlagNonSymbolic = 32;

  private
    FDictionary: TCosDictionary;
    FOwnsDictionary: Boolean;
    FContext: TPDDocumentContext;
    FStandard14AFM: TFontMetrics;
    FFontDescriptor: TPDFontDescriptor;
    FBuiltDescriptorDictionary: TCosDictionary;
    FToUnicodeCMap: TCMap;
    FOwnsToUnicodeCMap: Boolean;
    FWidths: TArray<Single>;
    FHasWidths: Boolean;
    FAverageFontWidth: Single;
    FSpaceWidth: Single;
    FHasSpaceWidth: Boolean;
    FCodeToWidth: TDictionary<Integer, Single>;
    FIsScaleWarningGiven: Boolean;

    procedure LoadFontDescriptor;
    function BuildDescriptorDictionary(const Metrics: TFontMetrics): TCosDictionary;
    procedure LoadUnicodeCMap;
    procedure LoadStreamUnicodeCMap(const Stream: TCosStream);
    procedure LoadOtherUnicodeCMap(const Source: TCosBase);
    procedure UseToUnicodeCMap(const CMap: TCMap; const OwnsCMap: Boolean);
    function TryReadToUnicodeCMap(const Source: TCosBase; out CMap: TCMap; out OwnsCMap: Boolean): Boolean;
    function TryChargeToUnicodeBudget(const CMap: TCMap): Boolean;
    procedure ReplaceToUnicodeCMap(const CMap: TCMap; const OwnsCMap: Boolean);
    procedure WarnAboutEmptyToUnicodeCMap;
    function TryUseIdentityInstead: Boolean;
    function IsIdentityToUnicode(const CMap: TCMap): Boolean;
    function IsIdentityEncoding: Boolean;
    function HasDifferences: Boolean;

    function TryGetNameEntry(const Key: string; out Value: string): Boolean;

    function HasWidthsOrMissingWidth: Boolean;
    function TryGetWidthFromWidthsArray(const Code: Integer; out Width: Single): Boolean;
    function ReadWidth(const Code: Integer): Single;
    procedure CacheWidth(const Code: Integer; const Width: Single);

    function CalculateAverageFontWidth: Single;
    function ReadSpaceWidth: Single;
    function GetSpaceWidthFromToUnicode: Single;
    function GetSpaceWidthFromEncoding: Single;
    function TryGetStringWidthOfSpace(out Width: Single): Boolean;

  protected
    // PDFont.getStandard14Width. Only simple fonts have the AFM of a standard 14 font; the default raises, like
    // PDType0Font.
    function GetStandard14Width(const Code: Integer): Single; virtual;
    // PDFont.encode for one code point. False when the font cannot encode it (PDFBox throws IllegalArgumentException or
    // UnsupportedOperationException); the default is False.
    function TryEncode(const CodePoint: Integer; out Bytes: TBytes): Boolean; virtual;
    // PDFont checks "this instanceof PDType0Font" when it asks the ToUnicode CMap for a code below 256
    function IsType0Font: Boolean; virtual;

    // PDFont.readCMap: a name is a predefined CMap (shared, OwnsCMap is False), a stream an embedded CMap that the
    // caller owns (OwnsCMap is True). Raises EPdfParseException for anything else and for an unknown name.
    function ReadCMap(const Source: TCosBase; out OwnsCMap: Boolean): TCMap;
    // A glyph width of the font program in thousandths of text space: width times the 1000 scale of the font matrix.
    // Java calculates that in double. A font matrix or a width that cannot be scaled to a finite value gives 0 and one
    // warning per font, where PDFBox continues with an infinity or NaN.
    function ScaleToTextSpace(const Width: Single): Single;
    // The CMap of /ToUnicode, owned by the font. False when there is none.
    function TryGetToUnicodeCMap(out CMap: TCMap): Boolean;
    // The font becomes the owner of Descriptor and frees the one it had
    procedure SetFontDescriptor(const Descriptor: TPDFontDescriptor);
    // Go to the log of the document, when there is one
    procedure LogWarning(const Fmt: string; const Args: array of const);
    procedure LogError(const Fmt: string; const Args: array of const);

    // The /Widths entry as floats (0 for a member that is no number), empty when there is none
    function GetWidths: TArray<Single>;
    function GetName: string; virtual;
    function GetSubType: string;

  public
    // Does not own Dictionary, which stays with the document. Context is not owned and may be nil, which turns off the log
    // and the ToUnicode budget.
    constructor Create(const Dictionary: TCosDictionary; const Context: TPDDocumentContext);
    destructor Destroy; override;

    // For a font that was made from a dictionary of its own (the default font): the font frees Dictionary with itself
    procedure OwnDictionary;

    function TryGetFontDescriptor(out Descriptor: TPDFontDescriptor): Boolean; virtual;
    // The shared AFM when the font is one of the standard 14, otherwise False. The caller does not own it.
    function TryGetStandardAFM(out Metrics: TFontMetrics): Boolean;
    function IsStandard14: Boolean; virtual;

    // Reads the next code at Position and moves Position behind it
    function ReadCode(const Data: TBytes; var Position: Integer): Integer; virtual; abstract;

    // The /Widths entry (or /MissingWidth, the standard 14 AFM or the font program) in thousandths of text space
    function GetWidth(const Code: Integer): Single; virtual;
    function GetWidthFromFont(const Code: Integer): Single; virtual; abstract;
    function HasExplicitWidth(const Code: Integer): Boolean; virtual;
    function GetAverageFontWidth: Single; virtual;
    function GetSpaceWidth: Single;

    function GetDisplacement(const Code: Integer): TPdfVector; virtual;
    // Raises EPdfUnsupportedFeatureException: horizontal fonts have no position vector
    function GetPositionVector(const Code: Integer): TPdfVector; virtual;
    function IsVertical: Boolean; virtual; abstract;

    // Only the /ToUnicode CMap. False when the font has none or the CMap has no mapping for the code. The subclasses
    // add the glyph names of their encoding.
    function TryToUnicode(const Code: Integer; out Value: string): Boolean; overload; virtual;
    function TryToUnicode(const Code: Integer; const CustomGlyphList: TGlyphList; out Value: string): Boolean; overload; virtual;

    function GetFontMatrix: TPdfMatrix; virtual;
    function GetBoundingBox: TBoundingBox; virtual; abstract;
    function IsEmbedded: Boolean; virtual; abstract;
    function IsDamaged: Boolean; virtual; abstract;

    property CosObject: TCosDictionary read FDictionary;
    property Context: TPDDocumentContext read FContext;
    // The /BaseFont; empty when there is none
    property Name: string read GetName;
    property SubType: string read GetSubType;
  end;

implementation

uses
  System.Classes,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Float,
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Cos.PdfString,
  Pdf4D.Font.CMapManager,
  Pdf4D.Font.Standard14,
  Pdf4D.IO.RandomAccessRead;

{ TToUnicodeCacheEntry }

constructor TToUnicodeCacheEntry.Create(const CMap: TCMap);
begin
  inherited Create;
  FCMap := CMap;
end;

destructor TToUnicodeCacheEntry.Destroy;
begin
  FCMap.Free;
  inherited;
end;

{ TPDFont }

constructor TPDFont.Create(const Dictionary: TCosDictionary; const Context: TPDDocumentContext);
begin
  inherited Create;
  if not Assigned(Dictionary) then
  begin
    raise EArgumentNilException.Create('A font needs a font dictionary');
  end;

  FDictionary := Dictionary;
  FContext := Context;
  FCodeToWidth := TDictionary<Integer, Single>.Create;
  FSpaceWidth := -1;

  // The AFM is only there for the standard 14 fonts: for any other name TryGetAFM gives False
  TStandard14Fonts.TryGetAFM(Name, FStandard14AFM);
  LoadFontDescriptor;
  LoadUnicodeCMap;
end;

destructor TPDFont.Destroy;
begin
  if FOwnsToUnicodeCMap then
  begin
    FToUnicodeCMap.Free;
  end;
  FFontDescriptor.Free;
  FBuiltDescriptorDictionary.Free;
  FCodeToWidth.Free;
  if FOwnsDictionary then
  begin
    FDictionary.Free;
  end;
  inherited;
end;

procedure TPDFont.LoadFontDescriptor;
begin
  var DescriptorDictionary: TCosDictionary;
  if FDictionary.TryGetCosDictionary(TCosNames.FontDescriptor, DescriptorDictionary) then
  begin
    FFontDescriptor := TPDFontDescriptor.Create(DescriptorDictionary);
  end
  else if Assigned(FStandard14AFM) then
  begin
    FBuiltDescriptorDictionary := BuildDescriptorDictionary(FStandard14AFM);
    FFontDescriptor := TPDFontDescriptor.Create(FBuiltDescriptorDictionary);
  end;
end;

function TPDFont.BuildDescriptorDictionary(const Metrics: TFontMetrics): TCosDictionary;
begin
  const IsSymbolic = (Metrics.EncodingScheme = 'FontSpecific');
  var Flags: Integer;
  if IsSymbolic then
  begin
    Flags := FlagSymbolic;
  end
  else
  begin
    Flags := FlagNonSymbolic;
  end;

  Result := TCosDictionary.Create;
  try
    Result.SetItem(TCosNames.FontName, TCosName.Create(Metrics.FontName));
    Result.SetItem(TCosNames.FontFamily, TCosString.Create(TEncoding.ASCII.GetBytes(Metrics.FamilyName), False));
    Result.SetItem(TCosNames.Flags, TCosInteger.Create(Flags));
    if Metrics.HasFontBBox then
    begin
      const Box = TCosArray.Create;
      Result.SetItem(TCosNames.FontBBox, Box);
      Box.Add(TCosFloat.Create(Metrics.FontBBox.LowerLeftX));
      Box.Add(TCosFloat.Create(Metrics.FontBBox.LowerLeftY));
      Box.Add(TCosFloat.Create(Metrics.FontBBox.UpperRightX));
      Box.Add(TCosFloat.Create(Metrics.FontBBox.UpperRightY));
    end;
    Result.SetItem(TCosNames.ItalicAngle, TCosFloat.Create(Metrics.ItalicAngle));
    Result.SetItem(TCosNames.Ascent, TCosFloat.Create(Metrics.Ascender));
    Result.SetItem(TCosNames.Descent, TCosFloat.Create(Metrics.Descender));
    Result.SetItem(TCosNames.CapHeight, TCosFloat.Create(Metrics.CapHeight));
    Result.SetItem(TCosNames.XHeight, TCosFloat.Create(Metrics.XHeight));
    Result.SetItem(TCosNames.AvgWidth, TCosFloat.Create(Metrics.GetAverageCharacterWidth));
    Result.SetItem(TCosNames.CharSet, TCosString.Create(TEncoding.ASCII.GetBytes(Metrics.CharacterSet), False));
    // For PDF/A
    Result.SetItem(TCosNames.StemV, TCosFloat.Create(0));
  except
    Result.Free;
    raise;
  end;
end;

procedure TPDFont.LoadUnicodeCMap;
begin
  var ToUnicode: TCosBase;
  if not FDictionary.TryGetDictionaryObject(TCosNames.ToUnicode, ToUnicode) then
  begin
    Exit;
  end;

  // A stream is parsed only while the document has budget left; a predefined CMap is shared and costs nothing
  if (ToUnicode is TCosStream) and Assigned(FContext) then
  begin
    LoadStreamUnicodeCMap(TCosStream(ToUnicode));
  end
  else
  begin
    LoadOtherUnicodeCMap(ToUnicode);
  end;
end;

procedure TPDFont.LoadStreamUnicodeCMap(const Stream: TCosStream);
begin
  var Cached: TObject;
  if FContext.TryGetCachedObject(TPDCacheScope.ToUnicode, Stream, Cached) then
  begin
    const CachedCMap = TToUnicodeCacheEntry(Cached).CMap;
    if Assigned(CachedCMap) then
    begin
      UseToUnicodeCMap(CachedCMap, False);
    end;
    Exit;
  end;

  if FContext.IsToUnicodeBudgetExhausted then
  begin
    Exit;
  end;

  var CMap: TCMap;
  var OwnsCMap: Boolean;
  const IsRead = TryReadToUnicodeCMap(Stream, CMap, OwnsCMap);
  if (not IsRead) and FContext.IsToUnicodeBudgetExhausted then
  begin
    // Over budget: the document drops every further ToUnicode CMap anyway, so nothing is worth keeping
    Exit;
  end;

  FContext.AddCachedObject(TPDCacheScope.ToUnicode, Stream, TToUnicodeCacheEntry.Create(CMap));
  if IsRead then
  begin
    UseToUnicodeCMap(CMap, False);
  end;
end;

procedure TPDFont.LoadOtherUnicodeCMap(const Source: TCosBase);
begin
  var CMap: TCMap;
  var OwnsCMap: Boolean;
  if TryReadToUnicodeCMap(Source, CMap, OwnsCMap) then
  begin
    UseToUnicodeCMap(CMap, OwnsCMap);
  end;
end;

procedure TPDFont.UseToUnicodeCMap(const CMap: TCMap; const OwnsCMap: Boolean);
begin
  ReplaceToUnicodeCMap(CMap, OwnsCMap);

  const IsInvalid = (Assigned(FToUnicodeCMap) and (not FToUnicodeCMap.HasUnicodeMappings));
  if IsInvalid then
  begin
    WarnAboutEmptyToUnicodeCMap;
  end;
end;

function TPDFont.TryReadToUnicodeCMap(const Source: TCosBase; out CMap: TCMap; out OwnsCMap: Boolean): Boolean;
begin
  CMap := nil;
  OwnsCMap := False;
  try
    CMap := ReadCMap(Source, OwnsCMap);
  except
    on Failure: Exception do
    begin
      const IsInputFailure = ((Failure is EPdfException) or TPdfFailure.IsInputFailure(Failure));
      if not IsInputFailure then
      begin
        raise;
      end;
      LogError('Could not read ToUnicode CMap in font %s: %s', [Name, Failure.Message]);
      Exit(False);
    end;
  end;

  if OwnsCMap and (not TryChargeToUnicodeBudget(CMap)) then
  begin
    CMap.Free;
    CMap := nil;
    Exit(False);
  end;
  Result := True;
end;

function TPDFont.TryChargeToUnicodeBudget(const CMap: TCMap): Boolean;
begin
  Result := ((not Assigned(FContext)) or FContext.TryChargeToUnicodeMappings(CMap.MappingCount));
end;

procedure TPDFont.ReplaceToUnicodeCMap(const CMap: TCMap; const OwnsCMap: Boolean);
begin
  if FOwnsToUnicodeCMap then
  begin
    FToUnicodeCMap.Free;
  end;
  FToUnicodeCMap := CMap;
  FOwnsToUnicodeCMap := OwnsCMap;
end;

procedure TPDFont.WarnAboutEmptyToUnicodeCMap;
begin
  LogWarning('Invalid ToUnicode CMap in font %s', [Name]);
  if IsIdentityToUnicode(FToUnicodeCMap) and (not HasDifferences) then
  begin
    // Assume that if the encoding is identity, then the reverse is also true
    if TryUseIdentityInstead then
    begin
      LogWarning('Using predefined identity CMap instead', []);
    end;
  end;
end;

function TPDFont.TryUseIdentityInstead: Boolean;
begin
  var Identity: TCMap;
  Result := TCMapManager.TryGetPredefinedCMap(TCosNames.IdentityH, Identity);
  if Result then
  begin
    ReplaceToUnicodeCMap(Identity, False);
  end
  else
  begin
    LogError('Could not read ToUnicode CMap in font %s: the predefined CMap %s is missing', [Name, TCosNames.IdentityH]);
  end;
end;

function TPDFont.IsIdentityToUnicode(const CMap: TCMap): Boolean;
begin
  Result := (CMap.Name.Contains('Identity') or CMap.Ordering.Contains('Identity') or IsIdentityEncoding);
end;

function TPDFont.IsIdentityEncoding: Boolean;
begin
  var EncodingName: string;
  Result := (TryGetNameEntry(TCosNames.Encoding, EncodingName) and
             ((EncodingName = TCosNames.IdentityH) or (EncodingName = TCosNames.IdentityV)));
end;

function TPDFont.HasDifferences: Boolean;
begin
  var EncodingDictionary: TCosDictionary;
  Result := (FDictionary.TryGetCosDictionary(TCosNames.Encoding, EncodingDictionary) and
             EncodingDictionary.ContainsKey(TCosNames.Differences));
end;

function TPDFont.TryGetNameEntry(const Key: string; out Value: string): Boolean;
begin
  Value := '';
  var Entry: TCosBase;
  Result := (FDictionary.TryGetDictionaryObject(Key, Entry) and (Entry is TCosName));
  if Result then
  begin
    Value := TCosName(Entry).Name;
  end;
end;

procedure TPDFont.LogWarning(const Fmt: string; const Args: array of const);
begin
  if Assigned(FContext) and Assigned(FContext.Log) then
  begin
    FContext.Log.Warning(Fmt, Args);
  end;
end;

procedure TPDFont.LogError(const Fmt: string; const Args: array of const);
begin
  if Assigned(FContext) and Assigned(FContext.Log) then
  begin
    FContext.Log.Error(Fmt, Args);
  end;
end;

function TPDFont.ReadCMap(const Source: TCosBase; out OwnsCMap: Boolean): TCMap;
begin
  OwnsCMap := False;
  if Source is TCosName then
  begin
    const CMapName = TCosName(Source).Name;
    if not TCMapManager.TryGetPredefinedCMap(CMapName, Result) then
    begin
      raise EPdfParseException.CreateFmt('Could not find the predefined CMap %s', [CMapName]);
    end;
    Exit;
  end;

  if not (Source is TCosStream) then
  begin
    raise EPdfParseException.Create('Expected Name or Stream');
  end;

  var Data: TBytes;
  const Decoded = TCosStream(Source).CreateDecodedStream;
  try
    if Decoded.Size > MaxInt then
    begin
      raise EPdfLimitExceededException.Create('The CMap stream is too large');
    end;
    SetLength(Data, Decoded.Size);
    Decoded.Position := 0;
    Decoded.ReadBuffer(Data, Length(Data));
  finally
    Decoded.Free;
  end;

  const Input = TRandomAccessRead.FromBytes(Data);
  try
    Result := TCMapManager.ParseCMap(Input);
    OwnsCMap := True;
  finally
    Input.Free;
  end;
end;

function TPDFont.TryGetToUnicodeCMap(out CMap: TCMap): Boolean;
begin
  CMap := FToUnicodeCMap;
  Result := Assigned(FToUnicodeCMap);
end;

procedure TPDFont.SetFontDescriptor(const Descriptor: TPDFontDescriptor);
begin
  if Descriptor <> FFontDescriptor then
  begin
    FFontDescriptor.Free;
    FFontDescriptor := Descriptor;
  end;
end;

function TPDFont.GetName: string;
begin
  Result := FDictionary.GetNameAsString(TCosNames.BaseFont, '');
end;

function TPDFont.GetSubType: string;
begin
  Result := FDictionary.GetNameAsString(TCosNames.Subtype, '');
end;

procedure TPDFont.OwnDictionary;
begin
  FOwnsDictionary := True;
end;

function TPDFont.TryGetFontDescriptor(out Descriptor: TPDFontDescriptor): Boolean;
begin
  Descriptor := FFontDescriptor;
  Result := Assigned(FFontDescriptor);
end;

function TPDFont.TryGetStandardAFM(out Metrics: TFontMetrics): Boolean;
begin
  Metrics := FStandard14AFM;
  Result := Assigned(FStandard14AFM);
end;

function TPDFont.IsStandard14: Boolean;
begin
  // Based on the behaviour of Acrobat (PDFBOX-2372): an embedded font never gets special treatment
  if IsEmbedded then
  begin
    Exit(False);
  end;
  Result := TStandard14Fonts.ContainsName(Name);
end;

function TPDFont.GetStandard14Width(const Code: Integer): Single;
begin
  raise EPdfUnsupportedFeatureException.CreateFmt('The font %s has no standard 14 widths', [Name]);
end;

function TPDFont.TryEncode(const CodePoint: Integer; out Bytes: TBytes): Boolean;
begin
  Bytes := nil;
  Result := False;
end;

function TPDFont.IsType0Font: Boolean;
begin
  Result := False;
end;

function TPDFont.ScaleToTextSpace(const Width: Single): Single;
begin
  if GetFontMatrix.TryScaleWidthToTextSpace(Width, Result) then
  begin
    Exit;
  end;

  if not FIsScaleWarningGiven then
  begin
    FIsScaleWarningGiven := True;
    LogWarning('The font matrix of %s gives a glyph width that is out of range', [Name]);
  end;
  Result := 0;
end;

function TPDFont.GetWidths: TArray<Single>;
begin
  if not FHasWidths then
  begin
    var Values: TCosArray;
    if FDictionary.TryGetCosArray(TCosNames.Widths, Values) then
    begin
      FWidths := Values.ToFloatArray;
    end
    else
    begin
      FWidths := nil;
    end;
    FHasWidths := True;
  end;
  Result := FWidths;
end;

function TPDFont.HasWidthsOrMissingWidth: Boolean;
begin
  var Widths: TCosBase;
  Result := (FDictionary.TryGetDictionaryObject(TCosNames.Widths, Widths) or FDictionary.ContainsKey(TCosNames.MissingWidth));
end;

function TPDFont.TryGetWidthFromWidthsArray(const Code: Integer; out Width: Single): Boolean;
begin
  Width := 0;
  const FirstChar = FDictionary.GetInt(TCosNames.FirstChar, -1);
  const LastChar = FDictionary.GetInt(TCosNames.LastChar, -1);
  const Values = GetWidths;
  const Index = Int64(Code) - FirstChar;
  const IsInRange = ((Length(Values) > 0) and (Code >= FirstChar) and (Code <= LastChar) and (Index < Length(Values)));
  Result := IsInRange;
  if IsInRange then
  begin
    Width := Values[Index];
  end;
end;

function TPDFont.ReadWidth(const Code: Integer): Single;
begin
  // Acrobat overrides the widths in the font program on the conforming reader's system with the widths specified in the
  // font dictionary (Adobe Supplement to the ISO 32000). PDFBOX-427 shows that it also applies to embedded fonts.
  if HasWidthsOrMissingWidth then
  begin
    if TryGetWidthFromWidthsArray(Code, Result) then
    begin
      Exit;
    end;

    var Descriptor: TPDFontDescriptor;
    if TryGetFontDescriptor(Descriptor) then
    begin
      Exit(Descriptor.MissingWidth);
    end;
  end;

  if IsStandard14 then
  begin
    Exit(GetStandard14Width(Code));
  end;

  // Nothing to override with, so fall back to the font
  Result := GetWidthFromFont(Code);
end;

procedure TPDFont.CacheWidth(const Code: Integer; const Width: Single);
begin
  // PDFBox keeps every width; here a file with endless distinct codes cannot grow the map without limit
  if FCodeToWidth.Count < WidthCacheLimit then
  begin
    FCodeToWidth.Add(Code, Width);
  end;
end;

function TPDFont.GetWidth(const Code: Integer): Single;
begin
  if FCodeToWidth.TryGetValue(Code, Result) then
  begin
    Exit;
  end;

  Result := ReadWidth(Code);
  CacheWidth(Code, Result);
end;

function TPDFont.HasExplicitWidth(const Code: Integer): Boolean;
begin
  Result := False;
  if not FDictionary.ContainsKey(TCosNames.Widths) then
  begin
    Exit;
  end;

  const FirstChar = FDictionary.GetInt(TCosNames.FirstChar, -1);
  Result := ((Code >= FirstChar) and ((Int64(Code) - FirstChar) < Length(GetWidths)));
end;

function TPDFont.GetAverageFontWidth: Single;
begin
  if FAverageFontWidth <> 0 then
  begin
    Exit(FAverageFontWidth);
  end;

  FAverageFontWidth := CalculateAverageFontWidth;
  Result := FAverageFontWidth;
end;

function TPDFont.CalculateAverageFontWidth: Single;
begin
  var TotalWidth: Single := 0;
  var CharacterCount: Single := 0;
  try
    for var Width in GetWidths do
    begin
      if Width > 0 then
      begin
        TotalWidth := TotalWidth + Width;
        CharacterCount := CharacterCount + 1;
      end;
    end;

    if TotalWidth > 0 then
    begin
      Exit(TotalWidth / CharacterCount);
    end;
    Result := 0;
  except
    // Java float arithmetic gives Infinity here, and this does the same on every platform
    on EMathError do
    begin
      Result := Single.PositiveInfinity;
    end;
  end;
end;

function TPDFont.GetSpaceWidth: Single;
begin
  if not FHasSpaceWidth then
  begin
    FSpaceWidth := ReadSpaceWidth;
    FHasSpaceWidth := True;
  end;
  Result := FSpaceWidth;
end;

function TPDFont.ReadSpaceWidth: Single;
begin
  try
    var Width: Single;
    if Assigned(FToUnicodeCMap) and FDictionary.ContainsKey(TCosNames.ToUnicode) then
    begin
      Width := GetSpaceWidthFromToUnicode;
    end
    else
    begin
      Width := GetSpaceWidthFromEncoding;
    end;

    // Try to get it from the font itself, and use the average font width as the last resort
    if Width <= 0 then
    begin
      Width := GetWidthFromFont(SpaceCode);
      if Width <= 0 then
      begin
        Width := GetAverageFontWidth;
      end;
    end;
    Result := Width;
  except
    on Failure: Exception do
    begin
      LogError('Can''t determine the width of the space character for font %s, assuming %d: %s', [Name, FallbackSpaceWidth, Failure.Message]);
      Result := FallbackSpaceWidth;
    end;
  end;
end;

function TPDFont.GetSpaceWidthFromToUnicode: Single;
begin
  Result := -1;
  var SpaceMapping: Integer;
  if FToUnicodeCMap.TryGetSpaceMapping(SpaceMapping) then
  begin
    Result := GetWidth(SpaceMapping);
  end;
end;

function TPDFont.GetSpaceWidthFromEncoding: Single;
begin
  // PDFBOX-5920: try with the encoding, which gets the correct code. A font that cannot encode the space goes on with 32.
  var Width: Single;
  if (not TryGetStringWidthOfSpace(Width)) or (Width <= 0) then
  begin
    Width := GetWidth(SpaceCode);
  end;
  Result := Width;
end;

function TPDFont.TryGetStringWidthOfSpace(out Width: Single): Boolean;
begin
  Width := 0;
  var Bytes: TBytes;
  if not TryEncode(SpaceCode, Bytes) then
  begin
    Exit(False);
  end;

  var Position := 0;
  while Position < Length(Bytes) do
  begin
    const Before = Position;
    const Code = ReadCode(Bytes, Position);
    Width := Width + GetWidth(Code);
    if Position <= Before then
    begin
      Position := Before + 1;
    end;
  end;
  Result := True;
end;

function TPDFont.GetDisplacement(const Code: Integer): TPdfVector;
begin
  const Thousand: Single = 1000;
  Result := TPdfVector.Create(GetWidth(Code) / Thousand, 0);
end;

function TPDFont.GetPositionVector(const Code: Integer): TPdfVector;
begin
  raise EPdfUnsupportedFeatureException.Create('Horizontal fonts have no position vector');
end;

function TPDFont.TryToUnicode(const Code: Integer; const CustomGlyphList: TGlyphList; out Value: string): Boolean;
begin
  Result := TryToUnicode(Code, Value);
end;

function TPDFont.TryToUnicode(const Code: Integer; out Value: string): Boolean;
begin
  Value := '';
  // Without a ToUnicode CMap there is no way to get Unicode here; the subclasses add their own sources
  if not Assigned(FToUnicodeCMap) then
  begin
    Exit(False);
  end;

  var EntryName: string;
  const IsIdentityName = FToUnicodeCMap.Name.StartsWith(IdentityPrefix);
  const IsNameEntry = TryGetNameEntry(TCosNames.ToUnicode, EntryName);
  if IsIdentityName and (IsNameEntry or (not FToUnicodeCMap.HasUnicodeMappings)) then
  begin
    // The undocumented case of an Identity-H/V CMap as ToUnicode CMap. It is no code to Unicode map, but the code
    // is the character (PDFBOX-3123: only when /ToUnicode is a name; PDFBOX-4322: identity streams are fine too).
    Value := Char(Word(Code and $FFFF));
    Exit(True);
  end;

  var Encoding: string;
  const LimitToOneByte = ((Code < 256) and (not IsType0Font) and TryGetNameEntry(TCosNames.Encoding, Encoding) and
                          (not Encoding.StartsWith(TCosNames.Identity)));
  if LimitToOneByte then
  begin
    // A simple font with a predefined encoding has one byte codes, so only the one byte mappings count
    Exit(FToUnicodeCMap.TryToUnicode(Code, 1, Value));
  end;
  Result := FToUnicodeCMap.TryToUnicode(Code, Value);
end;

function TPDFont.GetFontMatrix: TPdfMatrix;
begin
  Result := TPdfMatrix.Create(0.001, 0, 0, 0.001, 0, 0);
end;

end.
