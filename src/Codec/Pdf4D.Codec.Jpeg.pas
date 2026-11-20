// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from pdf.js, Copyright 2014 Mozilla Foundation, licensed under the Apache License, Version 2.0; see the NOTICE
// file. pdf.js forked the code from https://github.com/notmasteryet/jpgjs.
// Port of: src/core/jpg.js (JpegImage, decodeScan, quantizeAndInverse, buildComponentData, getData) of pdf.js, release tag v6.5.438
// (tools/fetch-pdfjs-src.ps1). The deviations from jpg.js are listed in docs/porting.md.
unit Pdf4D.Codec.Jpeg;

{$EXCESSPRECISION OFF}
// jpg.js stores 16 bit values in Int16Array and wraps 32 bit integer arithmetic; the port relies on the same wrap
{$RANGECHECKS OFF}
{$OVERFLOWCHECKS OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Common.Log;

type
  TJpegDecodeOptions = record
    // /ColorTransform of the DCTDecode filter: -1 when absent (jpg.js colorTransform)
    ColorTransform: Integer;
    // True for a JPEG that comes from a PDF file: CMYK is not inverted (jpg.js isSourcePDF)
    IsSourcePdf: Boolean;
    // A JPEG of more pixels raises EPdfParseException, and so does one whose block buffers would take far more samples
    MaxPixels: Int64;

    class function ForPdf(const ColorTransform: Integer; const MaxPixels: Int64): TJpegDecodeOptions; static;
  end;

  TJpegImage = class
  private
    FWidth: Integer;
    FHeight: Integer;
    FComponents: Integer;
    FSamples: TBytes;

  public
    // Raises EPdfParseException for data that is not a JPEG that the decoder supports (Huffman coded baseline, extended and
    // progressive DCT with 8 bit samples and 1, 3 or 4 components). Truncated data keeps the rows that were decoded, with one
    // warning in the log; the rest of the image is what all coefficients 0 give (mid gray). Log may be nil.
    class function Decode(const Data: TBytes; const Options: TJpegDecodeOptions; const Log: TPdfLog): TJpegImage; static;

    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
    property Components: Integer read FComponents;
    // Component samples as PDFBox DCTFilter returns them: gray, RGB or CMYK (after the Adobe transform), 8 bit, interleaved
    property Samples: TBytes read FSamples;
  end;

implementation

uses
  System.Math,
  System.Generics.Collections,
  Pdf4D.Common.Defines;

type
  // The end of the data inside a scan: jpg.js reads undefined bytes there, the port ends the scan like at an EOI marker
  EJpegDataEnd = class(Exception);
  EJpegEoiMarker = class(Exception);

  EJpegDnlMarker = class(Exception)
  private
    FScanLines: Integer;

  public
    constructor Create(const Message: string; const ScanLines: Integer);

    property ScanLines: Integer read FScanLines;
  end;

  TJpegBlockData = TArray<SmallInt>;

  TJpegFileMarker = record
    IsFound: Boolean;
    // The two bytes at the current position when they are no marker, -1 when they are one
    InvalidMarker: Integer;
    Marker: Integer;
    Offset: Integer;
  end;

  TJpegBytes = record
    // Raises EPdfParseException when the two bytes are not in the data
    class function UInt16At(const Data: TBytes; const Position: Integer): Integer; static;
    class function IsValidMarker(const Marker: Integer): Boolean; static;
    // findNextFileMarker
    class function FindNextFileMarker(const Data: TBytes; const CurrentPos, StartPos: Integer): TJpegFileMarker; static;
  end;

  // buildHuffmanTable: the canonical code of the JPEG specification instead of the nested arrays of jpg.js; it decodes the same values
  TJpegHuffmanTable = class
  private
    FMinCode: array[1..16] of Integer;
    FMaxCode: array[1..16] of Integer;
    FValuePointer: array[1..16] of Integer;
    FValues: TBytes;

  public
    constructor Create(const CodeLengths: TBytes; const Values: TBytes);

    // True when Code of CodeLength bits is a code of the table; Value is then its value
    function TryDecode(const CodeLength, Code: Integer; out Value: Integer): Boolean;
  end;

  TJpegComponent = class
  private
    FH: Integer;
    FV: Integer;
    FQuantizationId: Integer;
    FQuantizationTable: TArray<Word>;
    FBlockData: TJpegBlockData;
    FBlocksPerLine: Integer;
    FBlocksPerColumn: Integer;
    FPred: Integer;
    FIndex: Integer;
    FHuffmanTableDC: TJpegHuffmanTable;
    FHuffmanTableAC: TJpegHuffmanTable;

  public
    constructor Create(const H, V, QuantizationId: Integer);

    property H: Integer read FH;
    property V: Integer read FV;
    property QuantizationId: Integer read FQuantizationId;
    property QuantizationTable: TArray<Word> read FQuantizationTable write FQuantizationTable;
    property BlockData: TJpegBlockData read FBlockData write FBlockData;
    property BlocksPerLine: Integer read FBlocksPerLine write FBlocksPerLine;
    property BlocksPerColumn: Integer read FBlocksPerColumn write FBlocksPerColumn;
    property Pred: Integer read FPred write FPred;
    // The component id that a scan header named, -1 until a scan has named the component
    property Index: Integer read FIndex write FIndex;
    property HuffmanTableDC: TJpegHuffmanTable read FHuffmanTableDC write FHuffmanTableDC;
    property HuffmanTableAC: TJpegHuffmanTable read FHuffmanTableAC write FHuffmanTableAC;
  end;

  TJpegFrame = class
  private
    FComponents: TObjectList<TJpegComponent>;
    FComponentIndexOfId: array[0..255] of Integer;
    FProgressive: Boolean;
    FPrecision: Integer;
    FScanLines: Integer;
    FSamplesPerLine: Integer;
    FMaxH: Integer;
    FMaxV: Integer;
    FMcusPerLine: Integer;
    FMcusPerColumn: Integer;

  public
    constructor Create;
    destructor Destroy; override;

    function TryGetComponentOfId(const Id: Integer; out Component: TJpegComponent): Boolean;
    procedure SetComponentId(const Id, ComponentIndex: Integer);

    property Components: TObjectList<TJpegComponent> read FComponents;
    property Progressive: Boolean read FProgressive write FProgressive;
    property Precision: Integer read FPrecision write FPrecision;
    property ScanLines: Integer read FScanLines write FScanLines;
    property SamplesPerLine: Integer read FSamplesPerLine write FSamplesPerLine;
    property MaxH: Integer read FMaxH write FMaxH;
    property MaxV: Integer read FMaxV write FMaxV;
    property McusPerLine: Integer read FMcusPerLine write FMcusPerLine;
    property McusPerColumn: Integer read FMcusPerColumn write FMcusPerColumn;
  end;

  // decodeScan and the functions nested in it
  TJpegScanDecoder = class
  private
    FData: TBytes;
    FOffset: Integer;
    FFrame: TJpegFrame;
    FComponents: TArray<TJpegComponent>;
    FResetInterval: Integer;
    FSpectralStart: Integer;
    FSpectralEnd: Integer;
    FSuccessivePrev: Integer;
    FSuccessive: Integer;
    FParseDnlMarker: Boolean;
    FLog: TPdfLog;
    FBitsData: Integer;
    FBitsCount: Integer;
    FEobrun: Integer;
    FSuccessiveAcState: Integer;
    FSuccessiveAcNextValue: Integer;
    FBlockRow: Integer;

    function NextByte: Integer;
    function ReadBit: Integer;
    procedure RaiseForMarkerInScan(const NextMarkerByte: Integer);
    procedure RaiseForDnlMarker;
    procedure RaiseForEoiMarker;
    function DecodeHuffman(const Table: TJpegHuffmanTable): Integer;
    function Receive(const BitCount: Integer): Integer;
    function ReceiveAndExtend(const BitCount: Integer): Integer;
    procedure StoreCoefficient(const Component: TJpegComponent; const BlockOffset, ZigZagIndex, Value: Integer);
    procedure DecodeBaseline(const Component: TJpegComponent; const BlockOffset: Integer);
    procedure DecodeDcFirst(const Component: TJpegComponent; const BlockOffset: Integer);
    procedure DecodeDcSuccessive(const Component: TJpegComponent; const BlockOffset: Integer);
    procedure DecodeAcFirst(const Component: TJpegComponent; const BlockOffset: Integer);
    procedure DecodeAcSuccessive(const Component: TJpegComponent; const BlockOffset: Integer);
    procedure StartAcSuccessiveRun(const Component: TJpegComponent; var Run: Integer);
    procedure AddRefinementBit(const Component: TJpegComponent; const OffsetZ: Integer);
    procedure DecodeBlockData(const Component: TJpegComponent; const BlockOffset: Integer);
    procedure DecodeMcu(const Component: TJpegComponent; const Mcu, Row, Col: Integer);
    procedure DecodeBlock(const Component: TJpegComponent; const Mcu: Integer);
    function BlockOffsetOf(const Component: TJpegComponent; const Row, Col: Integer): Integer;
    function ExpectedMcus: Integer;
    procedure DecodeMcus(const Count: Integer; var Mcu: Integer);
    procedure Warn(const Fmt: string; const Args: array of const);

  public
    constructor Create(const Data: TBytes; const Offset: Integer; const Frame: TJpegFrame; const Components: TArray<TJpegComponent>;
                       const ResetInterval, SpectralStart, SpectralEnd, SuccessivePrev, Successive: Integer;
                       const ParseDnlMarker: Boolean; const Log: TPdfLog);

    // Decodes the scan and returns how many bytes it took
    function Run: Integer;
  end;

  // JpegImage: the parser, the reconstruction of the components and the colour conversion
  TJpegDecoder = class
  private
    FData: TBytes;
    FOptions: TJpegDecodeOptions;
    FLog: TPdfLog;
    FOffset: Integer;
    FFrame: TJpegFrame;
    FHasAdobe: Boolean;
    FAdobeTransformCode: Integer;
    FResetInterval: Integer;
    FScanCount: Integer;
    FDnlScanLines: Integer;
    FQuantizationTables: array[0..15] of TArray<Word>;
    FHuffmanTablesDC: array[0..15] of TJpegHuffmanTable;
    FHuffmanTablesAC: array[0..15] of TJpegHuffmanTable;
    FHuffmanTables: TObjectList<TJpegHuffmanTable>;
    FInverseBuffer: array[0..63] of SmallInt;

    function ReadByte(const Position: Integer): Integer;
    function ReadDataBlock: TBytes;
    procedure ResetState(const DnlScanLines: Integer);
    function ReadStartMarker: Integer;
    function ParseSegment(const FileMarker: Integer): Boolean;
    procedure ReadApplicationSegment(const FileMarker: Integer);
    procedure ReadQuantizationTables;
    procedure ReadFrame(const FileMarker: Integer);
    procedure ReadFrameComponents(const Count: Integer);
    procedure CheckFrameSize;
    procedure PrepareComponents;
    procedure ReadHuffmanTables;
    procedure ReadRestartInterval;
    function ReadScan: Boolean;
    function ReadScanComponents: TArray<TJpegComponent>;
    function ParseUnknownSegment: Boolean;
    procedure BuildComponentData;
    procedure QuantizeAndInverse(const Component: TJpegComponent; const BlockBufferOffset: Integer);
    procedure InverseRows(const Component: TJpegComponent; const BlockBufferOffset: Integer);
    procedure InverseColumns(const Component: TJpegComponent; const BlockBufferOffset: Integer);
    function LinearizeBlockData: TBytes;
    function ComponentCount: Integer;
    function IsColorConversionNeeded: Boolean;
    procedure ConvertYccToRgb(const Data: TBytes);
    procedure ConvertYcckToCmyk(const Data: TBytes);
    procedure InvertSamples(const Data: TBytes);

  public
    constructor Create(const Data: TBytes; const Options: TJpegDecodeOptions; const Log: TPdfLog);
    destructor Destroy; override;

    procedure Warn(const Fmt: string; const Args: array of const);
    procedure Parse(const DnlScanLines: Integer);
    function BuildImage: TJpegImage;
  end;

const
  MarkerSoi = $FFD8;
  MarkerEoi = $FFD9;
  MarkerApp0 = $FFE0;
  MarkerApp14 = $FFEE;
  MarkerApp15 = $FFEF;
  MarkerCom = $FFFE;
  MarkerDqt = $FFDB;
  MarkerSof0 = $FFC0;
  MarkerSof1 = $FFC1;
  MarkerSof2 = $FFC2;
  MarkerSof3 = $FFC3;
  MarkerDht = $FFC4;
  MarkerSof5 = $FFC5;
  MarkerSof7 = $FFC7;
  MarkerSof9 = $FFC9;
  MarkerSof11 = $FFCB;
  MarkerSof13 = $FFCD;
  MarkerSof15 = $FFCF;
  MarkerDri = $FFDD;
  MarkerSos = $FFDA;
  MarkerDnl = $FFDC;
  MarkerFill = $FFFF;
  MarkerRst0 = $FFD0;
  MarkerRst7 = $FFD7;
  MarkerFirstValid = $FFC0;
  MarkerLastValid = $FFFE;
  DnlMarkerLow = $DC;
  EoiMarkerLow = $D9;
  AdobeSignatureLength = 5;
  AdobeTransformPosition = 11;
  EndOfImageProbableLines = 5;

  MaxScans = 1000;
  MaxComponents = 4;
  MaxSamplingFactor = 4;
  ComponentsOfColor = 3;
  ComponentsOfCmyk = 4;
  CodeLengthCount = 16;
  BlockSize = 64;
  BlockSide = 8;
  MaxSampleBytes = 256 * 1024 * 1024;
  MaxBlockElements = 128 * 1024 * 1024;
  BlockBufferSlack = 1024 * 1024;
  BlockBufferPixelFactor = 4;
  MaxPixelsLimit = Int64(1) shl 40;

  DctSqrt2 = 5793;
  DctCos1 = 4017;
  DctSin1 = 799;
  DctCos3 = 3406;
  DctSin3 = 2276;
  DctCos6 = 1567;
  DctSin6 = 3784;
  DctSqrt1d2 = 2896;

  IdRed = $52;
  IdGreen = $47;
  IdBlue = $42;
  ByteMax = 255;

  DctZigZag: array[0..63] of Byte = (
    0,
    1, 8,
    16, 9, 2,
    3, 10, 17, 24,
    32, 25, 18, 11, 4,
    5, 12, 19, 26, 33, 40,
    48, 41, 34, 27, 20, 13, 6,
    7, 14, 21, 28, 35, 42, 49, 56,
    57, 50, 43, 36, 29, 22, 15,
    23, 30, 37, 44, 51, 58,
    59, 52, 45, 38, 31,
    39, 46, 53, 60,
    61, 54, 47,
    55, 62,
    63);

resourcestring
  SoiNotFound = 'SOI not found';
  NoFrameData = 'JpegImage.parse - no frame data found.';
  DataEndsUnexpectedly = 'JPEG data ends unexpectedly';
  UnexpectedMarker = 'unexpected marker %x';
  InvalidHuffmanSequence = 'invalid huffman sequence';
  MissingHuffmanTable = 'missing required Huffman table';
  MissingQuantizationTable = 'missing required Quantization Table.';
  InvalidAcEncoding = 'invalid ACn encoding';
  InvalidQuantizationSpec = 'DQT - invalid table spec';
  SingleFrameOnly = 'Only single frame JPEGs supported';
  UnknownMarker = 'JpegImage.parse - unknown marker: %x';
  UnsupportedCodingProcess = 'Unsupported JPEG coding process (marker %x): only Huffman coded baseline, extended and progressive DCT are supported';
  UnsupportedPrecision = 'Unsupported JPEG sample precision: %d bits';
  UnsupportedColorMode = 'Unsupported color mode: %d components';
  InvalidSamplingFactors = 'Invalid JPEG sampling factors: %d x %d';
  InvalidDimensions = 'Invalid JPEG dimensions: %d x %d';
  TooManyPixels = 'JPEG of %d x %d pixels is over the limit of %d pixels';
  BlockBufferTooLarge = 'JPEG of %d x %d pixels needs too many block buffers';
  TooManyScans = 'JPEG has more than %d scans';
  InvalidScan = 'Invalid JPEG scan header';
  UnknownScanComponent = 'JPEG scan names the unknown component %d';
  BlockOutsideBuffer = 'JPEG block lies outside the block buffer';
  EoiInScan = 'Found EOI marker (0xFFD9) while parsing scan data';
  DataEndInScan = 'Reached the end of the data while parsing scan data';
  DnlInScan = 'Found DNL marker (0xFFDC) while parsing scan data';
  DnlGuess = 'Found EOI marker (0xFFD9) while parsing scan data, possibly caused by incorrect scanLines parameter';

// The >> of JavaScript: an arithmetic shift of a 32 bit integer
function ShiftRight(const Value: Integer; const Bits: Integer): Integer; inline;
begin
  if Value >= 0 then
  begin
    Result := Value shr Bits;
  end
  else
  begin
    Result := not ((not Value) shr Bits);
  end;
end;

// A store into an Int16Array
function ToInt16(const Value: Integer): SmallInt; inline;
begin
  Result := SmallInt(Word(Value and $FFFF));
end;

// The last step of the inverse DCT: the value with 4 fraction bits as a sample
function ToSample(const Value: Integer): Integer; inline;
begin
  if Value < 16 then
  begin
    Result := 0;
  end
  else if Value >= 4080 then
  begin
    Result := ByteMax;
  end
  else
  begin
    Result := Value shr 4;
  end;
end;

// A store into a Uint8ClampedArray: clamped, rounded half to even
function ToByteClamped(const Value: Double): Byte;
begin
  if IsNan(Value) or (Value <= 0) then
  begin
    Exit(0);
  end;
  if Value >= ByteMax then
  begin
    Exit(ByteMax);
  end;

  const Whole = Trunc(Value);
  const Fraction = Value - Whole;
  if Fraction > 0.5 then
  begin
    Result := Byte(Whole + 1);
  end
  else if Fraction < 0.5 then
  begin
    Result := Byte(Whole);
  end
  else
  begin
    Result := Byte(Whole + (Whole and 1));
  end;
end;

// Math.ceil(Value / Divisor) for positive integers
function CeilDiv(const Value, Divisor: Int64): Int64; inline;
begin
  Result := (Value + Divisor - 1) div Divisor;
end;

{ EJpegDnlMarker }

constructor EJpegDnlMarker.Create(const Message: string; const ScanLines: Integer);
begin
  inherited Create(Message);
  FScanLines := ScanLines;
end;

{ TJpegDecodeOptions }

class function TJpegDecodeOptions.ForPdf(const ColorTransform: Integer; const MaxPixels: Int64): TJpegDecodeOptions;
begin
  Result.ColorTransform := ColorTransform;
  Result.IsSourcePdf := True;
  Result.MaxPixels := MaxPixels;
end;

{ TJpegBytes }

class function TJpegBytes.UInt16At(const Data: TBytes; const Position: Integer): Integer;
begin
  const IsInside = ((Position >= 0) and ((Int64(Position) + 1) < Length(Data)));
  if not IsInside then
  begin
    raise EPdfParseException.Create(DataEndsUnexpectedly);
  end;
  Result := (Integer(Data[Position]) shl 8) or Data[Position + 1];
end;

class function TJpegBytes.IsValidMarker(const Marker: Integer): Boolean;
begin
  Result := ((Marker >= MarkerFirstValid) and (Marker <= MarkerLastValid));
end;

class function TJpegBytes.FindNextFileMarker(const Data: TBytes; const CurrentPos, StartPos: Integer): TJpegFileMarker;
begin
  Result := Default(TJpegFileMarker);
  const MaxPos = Length(Data) - 1;
  var NewPos := CurrentPos;
  if StartPos < CurrentPos then
  begin
    NewPos := StartPos;
  end;

  const IsPastTheData = ((CurrentPos >= MaxPos) or (CurrentPos < 0) or (NewPos < 0));
  if IsPastTheData then
  begin
    Exit;
  end;

  const CurrentMarker = UInt16At(Data, CurrentPos);
  if IsValidMarker(CurrentMarker) then
  begin
    Result.IsFound := True;
    Result.InvalidMarker := -1;
    Result.Marker := CurrentMarker;
    Result.Offset := CurrentPos;
    Exit;
  end;

  var NewMarker := UInt16At(Data, NewPos);
  while not IsValidMarker(NewMarker) do
  begin
    Inc(NewPos);
    if NewPos >= MaxPos then
    begin
      Exit;
    end;
    NewMarker := UInt16At(Data, NewPos);
  end;
  Result.IsFound := True;
  Result.InvalidMarker := CurrentMarker;
  Result.Marker := NewMarker;
  Result.Offset := NewPos;
end;

{ TJpegHuffmanTable }

constructor TJpegHuffmanTable.Create(const CodeLengths: TBytes; const Values: TBytes);
begin
  inherited Create;
  FValues := Values;

  var Code := 0;
  var ValueIndex := 0;
  for var CodeLength := 1 to CodeLengthCount do
  begin
    const Count = CodeLengths[CodeLength - 1];
    FValuePointer[CodeLength] := ValueIndex;
    FMinCode[CodeLength] := Code;
    Inc(Code, Count);
    Inc(ValueIndex, Count);
    if Count > 0 then
    begin
      FMaxCode[CodeLength] := Code - 1;
    end
    else
    begin
      FMaxCode[CodeLength] := -1;
    end;
    Code := Code shl 1;
  end;
end;

function TJpegHuffmanTable.TryDecode(const CodeLength, Code: Integer; out Value: Integer): Boolean;
begin
  Value := 0;
  const IsCode = ((FMaxCode[CodeLength] >= 0) and (Code <= FMaxCode[CodeLength]) and (Code >= FMinCode[CodeLength]));
  if not IsCode then
  begin
    Exit(False);
  end;

  const ValueIndex = FValuePointer[CodeLength] + Code - FMinCode[CodeLength];
  const IsValueKnown = ((ValueIndex >= 0) and (ValueIndex < Length(FValues)));
  if not IsValueKnown then
  begin
    raise EPdfParseException.Create(InvalidHuffmanSequence);
  end;
  Value := FValues[ValueIndex];
  Result := True;
end;

{ TJpegComponent }

constructor TJpegComponent.Create(const H, V, QuantizationId: Integer);
begin
  inherited Create;
  FH := H;
  FV := V;
  FQuantizationId := QuantizationId;
  FIndex := -1;
end;

{ TJpegFrame }

constructor TJpegFrame.Create;
begin
  inherited Create;
  FComponents := TObjectList<TJpegComponent>.Create(True);
  for var Id := 0 to High(FComponentIndexOfId) do
  begin
    FComponentIndexOfId[Id] := -1;
  end;
end;

destructor TJpegFrame.Destroy;
begin
  FComponents.Free;
  inherited;
end;

function TJpegFrame.TryGetComponentOfId(const Id: Integer; out Component: TJpegComponent): Boolean;
begin
  Component := nil;
  const IsKnown = ((Id >= 0) and (Id <= High(FComponentIndexOfId)) and (FComponentIndexOfId[Id] >= 0));
  if IsKnown then
  begin
    Component := FComponents[FComponentIndexOfId[Id]];
  end;
  Result := IsKnown;
end;

procedure TJpegFrame.SetComponentId(const Id, ComponentIndex: Integer);
begin
  FComponentIndexOfId[Id] := ComponentIndex;
end;

{ TJpegScanDecoder }

constructor TJpegScanDecoder.Create(const Data: TBytes; const Offset: Integer; const Frame: TJpegFrame; const Components: TArray<TJpegComponent>;
                                    const ResetInterval, SpectralStart, SpectralEnd, SuccessivePrev, Successive: Integer;
                                    const ParseDnlMarker: Boolean; const Log: TPdfLog);
begin
  inherited Create;
  FData := Data;
  FOffset := Offset;
  FFrame := Frame;
  FComponents := Components;
  FResetInterval := ResetInterval;
  FSpectralStart := SpectralStart;
  FSpectralEnd := Min(SpectralEnd, BlockSize - 1);
  FSuccessivePrev := SuccessivePrev;
  FSuccessive := Successive;
  FParseDnlMarker := ParseDnlMarker;
  FLog := Log;
end;

procedure TJpegScanDecoder.Warn(const Fmt: string; const Args: array of const);
begin
  if Assigned(FLog) then
  begin
    FLog.Warning(Fmt, Args);
  end;
end;

function TJpegScanDecoder.NextByte: Integer;
begin
  if FOffset >= Length(FData) then
  begin
    raise EJpegDataEnd.Create(DataEndInScan);
  end;
  Result := FData[FOffset];
  Inc(FOffset);
end;

function TJpegScanDecoder.ReadBit: Integer;
begin
  if FBitsCount > 0 then
  begin
    Dec(FBitsCount);
    Exit((FBitsData shr FBitsCount) and 1);
  end;

  FBitsData := NextByte;
  if FBitsData = ByteMax then
  begin
    const NextMarkerByte = NextByte;
    if NextMarkerByte <> 0 then
    begin
      RaiseForMarkerInScan(NextMarkerByte);
    end;
  end;
  FBitsCount := 7;
  Result := FBitsData shr 7;
end;

// A marker in the middle of the entropy coded data. A DNL marker, or an EOI marker that shows that the number of lines is wrong, ends
// the parse with the number of lines to try instead; an EOI marker ends the scan; any other marker is an error.
procedure TJpegScanDecoder.RaiseForMarkerInScan(const NextMarkerByte: Integer);
begin
  if (NextMarkerByte = DnlMarkerLow) and FParseDnlMarker then
  begin
    RaiseForDnlMarker;
  end
  else if NextMarkerByte = EoiMarkerLow then
  begin
    RaiseForEoiMarker;
  end;
  raise EPdfParseException.CreateFmt(UnexpectedMarker, [(FBitsData shl 8) or NextMarkerByte]);
end;

procedure TJpegScanDecoder.RaiseForDnlMarker;
begin
  Inc(FOffset, 2);
  const ScanLines = TJpegBytes.UInt16At(FData, FOffset);
  Inc(FOffset, 2);
  const IsDifferent = ((ScanLines > 0) and (ScanLines <> FFrame.ScanLines));
  if IsDifferent then
  begin
    raise EJpegDnlMarker.Create(DnlInScan, ScanLines);
  end;
end;

procedure TJpegScanDecoder.RaiseForEoiMarker;
begin
  if FParseDnlMarker then
  begin
    var RowsDecoded := 0;
    if FFrame.Precision = BlockSide then
    begin
      RowsDecoded := FBlockRow * BlockSide;
    end;
    const IsFarSmaller = ((RowsDecoded > 0) and (Floor((FFrame.ScanLines / RowsDecoded) + 0.5) >= EndOfImageProbableLines));
    if IsFarSmaller then
    begin
      raise EJpegDnlMarker.Create(DnlGuess, RowsDecoded);
    end;
  end;
  raise EJpegEoiMarker.Create(EoiInScan);
end;

function TJpegScanDecoder.DecodeHuffman(const Table: TJpegHuffmanTable): Integer;
begin
  if not Assigned(Table) then
  begin
    raise EPdfParseException.Create(MissingHuffmanTable);
  end;

  var Code := 0;
  for var CodeLength := 1 to CodeLengthCount do
  begin
    Code := (Code shl 1) or ReadBit;
    var Value: Integer;
    if Table.TryDecode(CodeLength, Code, Value) then
    begin
      Exit(Value);
    end;
  end;
  raise EPdfParseException.Create(InvalidHuffmanSequence);
end;

function TJpegScanDecoder.Receive(const BitCount: Integer): Integer;
begin
  Result := 0;
  for var Counter := 1 to BitCount do
  begin
    Result := (Result shl 1) or ReadBit;
  end;
end;

function TJpegScanDecoder.ReceiveAndExtend(const BitCount: Integer): Integer;
begin
  if BitCount = 1 then
  begin
    if ReadBit = 1 then
    begin
      Exit(1);
    end;
    Exit(-1);
  end;

  // JavaScript takes the shift count modulo 32
  const Received = Receive(BitCount);
  if Received >= (1 shl ((BitCount - 1) and 31)) then
  begin
    Result := Received;
  end
  else
  begin
    Result := Received + (-1 shl (BitCount and 31)) + 1;
  end;
end;

// blockData[blockOffset + zigzag[k]] = value; a k past the 64 coefficients is an undefined index in jpg.js, which stores nothing
procedure TJpegScanDecoder.StoreCoefficient(const Component: TJpegComponent; const BlockOffset, ZigZagIndex, Value: Integer);
begin
  if ZigZagIndex < BlockSize then
  begin
    Component.BlockData[BlockOffset + DctZigZag[ZigZagIndex]] := ToInt16(Value);
  end;
end;

procedure TJpegScanDecoder.DecodeBaseline(const Component: TJpegComponent; const BlockOffset: Integer);
begin
  const Category = DecodeHuffman(Component.HuffmanTableDC);
  var Diff := 0;
  if Category <> 0 then
  begin
    Diff := ReceiveAndExtend(Category);
  end;
  Component.Pred := Component.Pred + Diff;
  Component.BlockData[BlockOffset] := ToInt16(Component.Pred);

  var K := 1;
  while K < BlockSize do
  begin
    const RunSize = DecodeHuffman(Component.HuffmanTableAC);
    const Size = RunSize and 15;
    const Run = RunSize shr 4;
    if Size = 0 then
    begin
      if Run < 15 then
      begin
        Break;
      end;
      Inc(K, 16);
      Continue;
    end;
    Inc(K, Run);
    StoreCoefficient(Component, BlockOffset, K, ReceiveAndExtend(Size));
    Inc(K);
  end;
end;

procedure TJpegScanDecoder.DecodeDcFirst(const Component: TJpegComponent; const BlockOffset: Integer);
begin
  const Category = DecodeHuffman(Component.HuffmanTableDC);
  var Diff := 0;
  if Category <> 0 then
  begin
    Diff := ReceiveAndExtend(Category) shl FSuccessive;
  end;
  Component.Pred := Component.Pred + Diff;
  Component.BlockData[BlockOffset] := ToInt16(Component.Pred);
end;

procedure TJpegScanDecoder.DecodeDcSuccessive(const Component: TJpegComponent; const BlockOffset: Integer);
begin
  const Current = Integer(Component.BlockData[BlockOffset]);
  Component.BlockData[BlockOffset] := ToInt16(Current or (ReadBit shl FSuccessive));
end;

procedure TJpegScanDecoder.DecodeAcFirst(const Component: TJpegComponent; const BlockOffset: Integer);
begin
  if FEobrun > 0 then
  begin
    Dec(FEobrun);
    Exit;
  end;

  var K := FSpectralStart;
  while K <= FSpectralEnd do
  begin
    const RunSize = DecodeHuffman(Component.HuffmanTableAC);
    const Size = RunSize and 15;
    const Run = RunSize shr 4;
    if Size = 0 then
    begin
      if Run < 15 then
      begin
        FEobrun := Receive(Run) + (1 shl Run) - 1;
        Break;
      end;
      Inc(K, 16);
      Continue;
    end;
    Inc(K, Run);
    StoreCoefficient(Component, BlockOffset, K, ReceiveAndExtend(Size) * (1 shl FSuccessive));
    Inc(K);
  end;
end;

procedure TJpegScanDecoder.AddRefinementBit(const Component: TJpegComponent; const OffsetZ: Integer);
begin
  const Current = Integer(Component.BlockData[OffsetZ]);
  var Sign := 1;
  if Current < 0 then
  begin
    Sign := -1;
  end;
  Component.BlockData[OffsetZ] := ToInt16(Current + (Sign * (ReadBit shl FSuccessive)));
end;

// State 0 of the refinement state machine: reads the run and size of the next coefficient
procedure TJpegScanDecoder.StartAcSuccessiveRun(const Component: TJpegComponent; var Run: Integer);
begin
  const RunSize = DecodeHuffman(Component.HuffmanTableAC);
  const Size = RunSize and 15;
  Run := RunSize shr 4;
  if Size = 0 then
  begin
    if Run < 15 then
    begin
      FEobrun := Receive(Run) + (1 shl Run);
      FSuccessiveAcState := 4;
    end
    else
    begin
      Run := 16;
      FSuccessiveAcState := 1;
    end;
    Exit;
  end;

  if Size <> 1 then
  begin
    raise EPdfParseException.Create(InvalidAcEncoding);
  end;
  FSuccessiveAcNextValue := ReceiveAndExtend(Size);
  if Run <> 0 then
  begin
    FSuccessiveAcState := 2;
  end
  else
  begin
    FSuccessiveAcState := 3;
  end;
end;

// The refinement scan of a progressive AC band, with the state machine of jpg.js. The run is local to a block, as in jpg.js.
procedure TJpegScanDecoder.DecodeAcSuccessive(const Component: TJpegComponent; const BlockOffset: Integer);
begin
  var K := FSpectralStart;
  var Run := 0;
  while K <= FSpectralEnd do
  begin
    const OffsetZ = BlockOffset + DctZigZag[K];
    const HasValue = (Component.BlockData[OffsetZ] <> 0);

    case FSuccessiveAcState of
      0:
        begin
          StartAcSuccessiveRun(Component, Run);
          Continue;
        end;
      1, 2:
        begin
          if HasValue then
          begin
            AddRefinementBit(Component, OffsetZ);
          end
          else
          begin
            Dec(Run);
            if Run = 0 then
            begin
              if FSuccessiveAcState = 2 then
              begin
                FSuccessiveAcState := 3;
              end
              else
              begin
                FSuccessiveAcState := 0;
              end;
            end;
          end;
        end;
      3:
        begin
          if HasValue then
          begin
            AddRefinementBit(Component, OffsetZ);
          end
          else
          begin
            Component.BlockData[OffsetZ] := ToInt16(FSuccessiveAcNextValue shl FSuccessive);
            FSuccessiveAcState := 0;
          end;
        end;
      4:
        begin
          if HasValue then
          begin
            AddRefinementBit(Component, OffsetZ);
          end;
        end;
    else
      raise EPdfParseException.Create(InvalidAcEncoding);
    end;
    Inc(K);
  end;

  if FSuccessiveAcState = 4 then
  begin
    Dec(FEobrun);
    if FEobrun = 0 then
    begin
      FSuccessiveAcState := 0;
    end;
  end;
end;

procedure TJpegScanDecoder.DecodeBlockData(const Component: TJpegComponent; const BlockOffset: Integer);
begin
  const IsOutside = ((BlockOffset < 0) or ((Int64(BlockOffset) + BlockSize) > Length(Component.BlockData)));
  if IsOutside then
  begin
    raise EPdfParseException.Create(BlockOutsideBuffer);
  end;

  if not FFrame.Progressive then
  begin
    DecodeBaseline(Component, BlockOffset);
  end
  else if FSpectralStart = 0 then
  begin
    if FSuccessivePrev = 0 then
    begin
      DecodeDcFirst(Component, BlockOffset);
    end
    else
    begin
      DecodeDcSuccessive(Component, BlockOffset);
    end;
  end
  else if FSuccessivePrev = 0 then
  begin
    DecodeAcFirst(Component, BlockOffset);
  end
  else
  begin
    DecodeAcSuccessive(Component, BlockOffset);
  end;
end;

// getBlockBufferOffset
function TJpegScanDecoder.BlockOffsetOf(const Component: TJpegComponent; const Row, Col: Integer): Integer;
begin
  const Offset = Int64(BlockSize) * ((Int64(Component.BlocksPerLine) + 1) * Row + Col);
  Result := Integer(Min(Offset, High(Integer)));
end;

procedure TJpegScanDecoder.DecodeMcu(const Component: TJpegComponent; const Mcu, Row, Col: Integer);
begin
  const McuRow = Mcu div FFrame.McusPerLine;
  const McuCol = Mcu mod FFrame.McusPerLine;
  FBlockRow := (McuRow * Component.V) + Row;
  const BlockCol = (McuCol * Component.H) + Col;
  DecodeBlockData(Component, BlockOffsetOf(Component, FBlockRow, BlockCol));
end;

procedure TJpegScanDecoder.DecodeBlock(const Component: TJpegComponent; const Mcu: Integer);
begin
  FBlockRow := Mcu div Component.BlocksPerLine;
  const BlockCol = Mcu mod Component.BlocksPerLine;
  DecodeBlockData(Component, BlockOffsetOf(Component, FBlockRow, BlockCol));
end;

function TJpegScanDecoder.ExpectedMcus: Integer;
begin
  if Length(FComponents) = 1 then
  begin
    Result := FComponents[0].BlocksPerLine * FComponents[0].BlocksPerColumn;
  end
  else
  begin
    Result := FFrame.McusPerLine * FFrame.McusPerColumn;
  end;
end;

// The MCUs between two restart markers
procedure TJpegScanDecoder.DecodeMcus(const Count: Integer; var Mcu: Integer);
begin
  for var Component in FComponents do
  begin
    Component.Pred := 0;
  end;
  FEobrun := 0;

  for var Counter := 1 to Count do
  begin
    if Length(FComponents) = 1 then
    begin
      DecodeBlock(FComponents[0], Mcu);
    end
    else
    begin
      for var Component in FComponents do
      begin
        for var Row := 0 to Component.V - 1 do
        begin
          for var Col := 0 to Component.H - 1 do
          begin
            DecodeMcu(Component, Mcu, Row, Col);
          end;
        end;
      end;
    end;
    Inc(Mcu);
  end;
end;

function TJpegScanDecoder.Run: Integer;
begin
  const StartOffset = FOffset;
  var Mcu := 0;
  const McuExpected = ExpectedMcus;

  while Mcu <= McuExpected do
  begin
    // jpg.js reads the whole scan again after the first interval when the file has no restart interval and stray restart
    // markers follow the scan; the port never decodes more MCUs than the frame has
    var McuToRead := McuExpected - Mcu;
    if FResetInterval > 0 then
    begin
      McuToRead := Min(McuToRead, FResetInterval);
    end;
    if McuToRead > 0 then
    begin
      DecodeMcus(McuToRead, Mcu);
    end;

    FBitsCount := 0;
    const FileMarker = TJpegBytes.FindNextFileMarker(FData, FOffset, FOffset);
    if not FileMarker.IsFound then
    begin
      Break;
    end;
    if FileMarker.InvalidMarker >= 0 then
    begin
      var Kind := 'excessive';
      if McuToRead > 0 then
      begin
        Kind := 'unexpected';
      end;
      Warn('decodeScan - %s MCU data, current marker is: %x', [Kind, FileMarker.InvalidMarker]);
      FOffset := FileMarker.Offset;
    end;

    const IsRestartMarker = ((FileMarker.Marker >= MarkerRst0) and (FileMarker.Marker <= MarkerRst7));
    if not IsRestartMarker then
    begin
      Break;
    end;
    Inc(FOffset, 2);
  end;
  Result := FOffset - StartOffset;
end;

{ TJpegDecoder }

constructor TJpegDecoder.Create(const Data: TBytes; const Options: TJpegDecodeOptions; const Log: TPdfLog);
begin
  inherited Create;
  FData := Data;
  FOptions := Options;
  FLog := Log;
  FHuffmanTables := TObjectList<TJpegHuffmanTable>.Create(True);
end;

destructor TJpegDecoder.Destroy;
begin
  FFrame.Free;
  FHuffmanTables.Free;
  inherited;
end;

procedure TJpegDecoder.Warn(const Fmt: string; const Args: array of const);
begin
  if Assigned(FLog) then
  begin
    FLog.Warning(Fmt, Args);
  end;
end;

function TJpegDecoder.ReadByte(const Position: Integer): Integer;
begin
  const IsInside = ((Position >= 0) and (Position < Length(FData)));
  if not IsInside then
  begin
    raise EPdfParseException.Create(DataEndsUnexpectedly);
  end;
  Result := FData[Position];
end;

procedure TJpegDecoder.ResetState(const DnlScanLines: Integer);
begin
  FreeAndNil(FFrame);
  FHuffmanTables.Clear;
  for var Index := 0 to High(FQuantizationTables) do
  begin
    FQuantizationTables[Index] := nil;
    FHuffmanTablesDC[Index] := nil;
    FHuffmanTablesAC[Index] := nil;
  end;
  FOffset := 0;
  FHasAdobe := False;
  FAdobeTransformCode := 0;
  FResetInterval := 0;
  FScanCount := 0;
  FDnlScanLines := DnlScanLines;
end;

function TJpegDecoder.ReadStartMarker: Integer;
begin
  const HasSignature = ((Length(FData) >= 2) and (TJpegBytes.UInt16At(FData, 0) = MarkerSoi));
  if not HasSignature then
  begin
    raise EPdfParseException.Create(SoiNotFound);
  end;
  FOffset := 2;
  Result := TJpegBytes.UInt16At(FData, FOffset);
  Inc(FOffset, 2);
end;

// JpegImage.parse
procedure TJpegDecoder.Parse(const DnlScanLines: Integer);
begin
  ResetState(DnlScanLines);
  const MaxOffset = Length(FData) - 1;
  var FileMarker := ReadStartMarker;

  while FileMarker <> MarkerEoi do
  begin
    if ParseSegment(FileMarker) then
    begin
      Break;
    end;

    if FOffset < MaxOffset then
    begin
      FileMarker := TJpegBytes.UInt16At(FData, FOffset);
      Inc(FOffset, 2);
    end
    else
    begin
      FileMarker := 0;
    end;
  end;

  if not Assigned(FFrame) then
  begin
    raise EPdfParseException.Create(NoFrameData);
  end;
  BuildComponentData;
end;

// True when the parse has to stop
function TJpegDecoder.ParseSegment(const FileMarker: Integer): Boolean;
begin
  Result := False;
  case FileMarker of
    MarkerApp0..MarkerApp15, MarkerCom:
      begin
        ReadApplicationSegment(FileMarker);
      end;
    MarkerDqt:
      begin
        ReadQuantizationTables;
      end;
    MarkerSof0..MarkerSof2:
      begin
        ReadFrame(FileMarker);
      end;
    MarkerSof3, MarkerSof5..MarkerSof7, MarkerSof9..MarkerSof11, MarkerSof13..MarkerSof15:
      begin
        raise EPdfParseException.CreateFmt(UnsupportedCodingProcess, [FileMarker]);
      end;
    MarkerDht:
      begin
        ReadHuffmanTables;
      end;
    MarkerDri:
      begin
        ReadRestartInterval;
      end;
    MarkerSos:
      begin
        Result := ReadScan;
      end;
    MarkerDnl:
      begin
        Inc(FOffset, 4);
      end;
    MarkerFill:
      begin
        const IsAnotherFillByte = ((FOffset < Length(FData)) and (FData[FOffset] = ByteMax));
        if not IsAnotherFillByte then
        begin
          Dec(FOffset);
        end;
      end;
  else
    Result := ParseUnknownSegment;
  end;
end;

// readDataBlock: the data of a segment; a segment that is too short for the marker after it ends at that marker
function TJpegDecoder.ReadDataBlock: TBytes;
begin
  const SegmentLength = TJpegBytes.UInt16At(FData, FOffset);
  Inc(FOffset, 2);
  var EndOffset := FOffset + SegmentLength - 2;

  const FileMarker = TJpegBytes.FindNextFileMarker(FData, EndOffset, FOffset);
  if FileMarker.IsFound and (FileMarker.InvalidMarker >= 0) then
  begin
    Warn('readDataBlock - incorrect length, current marker is: %x', [FileMarker.InvalidMarker]);
    EndOffset := FileMarker.Offset;
  end;

  const Count = Max(0, Min(EndOffset, Length(FData)) - FOffset);
  Result := Copy(FData, FOffset, Count);
  Inc(FOffset, Count);
end;

procedure TJpegDecoder.ReadApplicationSegment(const FileMarker: Integer);
begin
  const AppData = ReadDataBlock;
  if FileMarker <> MarkerApp14 then
  begin
    Exit;
  end;

  const HasAdobeSignature = ((Length(AppData) >= AdobeSignatureLength) and (AppData[0] = $41) and (AppData[1] = $64) and
                             (AppData[2] = $6F) and (AppData[3] = $62) and (AppData[4] = $65));
  if HasAdobeSignature then
  begin
    FHasAdobe := True;
    FAdobeTransformCode := 0;
    if Length(AppData) > AdobeTransformPosition then
    begin
      FAdobeTransformCode := AppData[AdobeTransformPosition];
    end;
  end;
end;

procedure TJpegDecoder.ReadQuantizationTables;
begin
  const TablesLength = TJpegBytes.UInt16At(FData, FOffset);
  Inc(FOffset, 2);
  const TablesEnd = TablesLength + FOffset - 2;

  while FOffset < TablesEnd do
  begin
    const Spec = ReadByte(FOffset);
    Inc(FOffset);
    const IsEightBit = ((Spec shr 4) = 0);
    const IsSixteenBit = ((Spec shr 4) = 1);
    if not (IsEightBit or IsSixteenBit) then
    begin
      raise EPdfParseException.Create(InvalidQuantizationSpec);
    end;

    var Table: TArray<Word>;
    SetLength(Table, BlockSize);
    for var Index := 0 to BlockSize - 1 do
    begin
      if IsEightBit then
      begin
        Table[DctZigZag[Index]] := ReadByte(FOffset);
        Inc(FOffset);
      end
      else
      begin
        Table[DctZigZag[Index]] := TJpegBytes.UInt16At(FData, FOffset);
        Inc(FOffset, 2);
      end;
    end;
    FQuantizationTables[Spec and 15] := Table;
  end;
end;

procedure TJpegDecoder.ReadFrame(const FileMarker: Integer);
begin
  if Assigned(FFrame) then
  begin
    raise EPdfParseException.Create(SingleFrameOnly);
  end;
  Inc(FOffset, 2);

  FFrame := TJpegFrame.Create;
  FFrame.Progressive := (FileMarker = MarkerSof2);
  FFrame.Precision := ReadByte(FOffset);
  Inc(FOffset);
  if FFrame.Precision <> BlockSide then
  begin
    raise EPdfParseException.CreateFmt(UnsupportedPrecision, [FFrame.Precision]);
  end;

  const SofScanLines = TJpegBytes.UInt16At(FData, FOffset);
  Inc(FOffset, 2);
  FFrame.ScanLines := SofScanLines;
  if FDnlScanLines <> 0 then
  begin
    FFrame.ScanLines := FDnlScanLines;
  end;
  FFrame.SamplesPerLine := TJpegBytes.UInt16At(FData, FOffset);
  Inc(FOffset, 2);

  const ComponentsInFrame = ReadByte(FOffset);
  Inc(FOffset);
  const IsSupportedCount = ((ComponentsInFrame = 1) or (ComponentsInFrame = ComponentsOfColor) or (ComponentsInFrame = ComponentsOfCmyk));
  if not IsSupportedCount then
  begin
    raise EPdfParseException.CreateFmt(UnsupportedColorMode, [ComponentsInFrame]);
  end;

  ReadFrameComponents(ComponentsInFrame);
  CheckFrameSize;
  PrepareComponents;
end;

procedure TJpegDecoder.ReadFrameComponents(const Count: Integer);
begin
  var MaxH := 0;
  var MaxV := 0;
  for var Counter := 1 to Count do
  begin
    const ComponentId = ReadByte(FOffset);
    const Sampling = ReadByte(FOffset + 1);
    const QuantizationId = ReadByte(FOffset + 2);
    const H = Sampling shr 4;
    const V = Sampling and 15;
    const IsValidSampling = ((H >= 1) and (H <= MaxSamplingFactor) and (V >= 1) and (V <= MaxSamplingFactor));
    if not IsValidSampling then
    begin
      raise EPdfParseException.CreateFmt(InvalidSamplingFactors, [H, V]);
    end;

    MaxH := Max(MaxH, H);
    MaxV := Max(MaxV, V);
    FFrame.Components.Add(TJpegComponent.Create(H, V, QuantizationId));
    FFrame.SetComponentId(ComponentId, FFrame.Components.Count - 1);
    Inc(FOffset, 3);
  end;
  FFrame.MaxH := MaxH;
  FFrame.MaxV := MaxV;
end;

// The pixels and the block buffers stay within MaxPixels (all arithmetic in Int64): the buffers hold a few samples per pixel at most,
// with some slack for the padding to whole MCUs
procedure TJpegDecoder.CheckFrameSize;
begin
  const Width = FFrame.SamplesPerLine;
  const Height = FFrame.ScanLines;
  if (Width < 1) or (Height < 1) then
  begin
    raise EPdfParseException.CreateFmt(InvalidDimensions, [Width, Height]);
  end;

  const Count = FFrame.Components.Count;
  const PixelLimit = Min(Min(FOptions.MaxPixels, MaxPixelsLimit), Int64(MaxSampleBytes div Count));
  const Pixels = Int64(Width) * Height;
  if Pixels > PixelLimit then
  begin
    raise EPdfParseException.CreateFmt(TooManyPixels, [Width, Height, PixelLimit]);
  end;

  const McusPerLine = CeilDiv(Width, Int64(BlockSide) * FFrame.MaxH);
  const McusPerColumn = CeilDiv(Height, Int64(BlockSide) * FFrame.MaxV);
  var BufferElements: Int64 := 0;
  for var Component in FFrame.Components do
  begin
    const BlocksPerLineForMcu = McusPerLine * Component.H;
    const BlocksPerColumnForMcu = McusPerColumn * Component.V;
    Inc(BufferElements, Int64(BlockSize) * BlocksPerColumnForMcu * (BlocksPerLineForMcu + 1));
  end;

  const ElementLimit = Min(Int64(MaxBlockElements), (Int64(BlockBufferPixelFactor) * PixelLimit * Count) + BlockBufferSlack);
  if BufferElements > ElementLimit then
  begin
    raise EPdfParseException.CreateFmt(BlockBufferTooLarge, [Width, Height]);
  end;
end;

// prepareComponents
procedure TJpegDecoder.PrepareComponents;
begin
  const Width = FFrame.SamplesPerLine;
  const Height = FFrame.ScanLines;
  const McusPerLine = CeilDiv(Width, Int64(BlockSide) * FFrame.MaxH);
  const McusPerColumn = CeilDiv(Height, Int64(BlockSide) * FFrame.MaxV);

  for var Component in FFrame.Components do
  begin
    const BlocksPerLine = CeilDiv(CeilDiv(Width, BlockSide) * Component.H, FFrame.MaxH);
    const BlocksPerColumn = CeilDiv(CeilDiv(Height, BlockSide) * Component.V, FFrame.MaxV);
    const BlocksPerLineForMcu = McusPerLine * Component.H;
    const BlocksPerColumnForMcu = McusPerColumn * Component.V;
    var Buffer: TJpegBlockData;
    SetLength(Buffer, Int64(BlockSize) * BlocksPerColumnForMcu * (BlocksPerLineForMcu + 1));
    Component.BlockData := Buffer;
    Component.BlocksPerLine := BlocksPerLine;
    Component.BlocksPerColumn := BlocksPerColumn;
  end;
  FFrame.McusPerLine := McusPerLine;
  FFrame.McusPerColumn := McusPerColumn;
end;

procedure TJpegDecoder.ReadHuffmanTables;
begin
  const TablesLength = TJpegBytes.UInt16At(FData, FOffset);
  Inc(FOffset, 2);

  var Consumed := 2;
  while Consumed < TablesLength do
  begin
    const Spec = ReadByte(FOffset);
    Inc(FOffset);

    var CodeLengths: TBytes;
    SetLength(CodeLengths, CodeLengthCount);
    var CodeLengthSum := 0;
    for var Index := 0 to CodeLengthCount - 1 do
    begin
      CodeLengths[Index] := ReadByte(FOffset);
      Inc(CodeLengthSum, CodeLengths[Index]);
      Inc(FOffset);
    end;

    var Values: TBytes;
    SetLength(Values, CodeLengthSum);
    for var Index := 0 to CodeLengthSum - 1 do
    begin
      Values[Index] := ReadByte(FOffset);
      Inc(FOffset);
    end;
    Inc(Consumed, 1 + CodeLengthCount + CodeLengthSum);

    const Table = TJpegHuffmanTable.Create(CodeLengths, Values);
    FHuffmanTables.Add(Table);
    if (Spec shr 4) = 0 then
    begin
      FHuffmanTablesDC[Spec and 15] := Table;
    end
    else
    begin
      FHuffmanTablesAC[Spec and 15] := Table;
    end;
  end;
end;

procedure TJpegDecoder.ReadRestartInterval;
begin
  Inc(FOffset, 2);
  FResetInterval := TJpegBytes.UInt16At(FData, FOffset);
  Inc(FOffset, 2);
end;

function TJpegDecoder.ReadScanComponents: TArray<TJpegComponent>;
begin
  const SelectorsCount = ReadByte(FOffset);
  Inc(FOffset);
  const IsValidCount = ((SelectorsCount >= 1) and (SelectorsCount <= MaxComponents));
  if not IsValidCount then
  begin
    raise EPdfParseException.Create(InvalidScan);
  end;

  SetLength(Result, SelectorsCount);
  for var Position := 0 to SelectorsCount - 1 do
  begin
    const Index = ReadByte(FOffset);
    const TableSpec = ReadByte(FOffset + 1);
    Inc(FOffset, 2);

    var Component: TJpegComponent;
    if not FFrame.TryGetComponentOfId(Index, Component) then
    begin
      raise EPdfParseException.CreateFmt(UnknownScanComponent, [Index]);
    end;
    Component.Index := Index;
    Component.HuffmanTableDC := FHuffmanTablesDC[TableSpec shr 4];
    Component.HuffmanTableAC := FHuffmanTablesAC[TableSpec and 15];
    Result[Position] := Component;
  end;
end;

// SOS; True when the parse has to stop because the data of the scan ended
function TJpegDecoder.ReadScan: Boolean;
begin
  Result := False;
  Inc(FScanCount);
  if FScanCount > MaxScans then
  begin
    raise EPdfParseException.CreateFmt(TooManyScans, [MaxScans]);
  end;
  if not Assigned(FFrame) then
  begin
    raise EPdfParseException.Create(NoFrameData);
  end;

  const ParseDnlMarker = ((FScanCount = 1) and (FDnlScanLines = 0));
  Inc(FOffset, 2);
  const Components = ReadScanComponents;
  const SpectralStart = ReadByte(FOffset);
  const SpectralEnd = ReadByte(FOffset + 1);
  const SuccessiveApproximation = ReadByte(FOffset + 2);
  Inc(FOffset, 3);

  const Scan = TJpegScanDecoder.Create(FData, FOffset, FFrame, Components, FResetInterval, SpectralStart, SpectralEnd,
                                       SuccessiveApproximation shr 4, SuccessiveApproximation and 15, ParseDnlMarker, FLog);
  try
    try
      Inc(FOffset, Scan.Run);
    except
      on Error: EJpegEoiMarker do
      begin
        Warn('%s -- ignoring the rest of the image data.', [Error.Message]);
        Result := True;
      end;
      on Error: EJpegDataEnd do
      begin
        Warn('%s -- ignoring the rest of the image data.', [Error.Message]);
        Result := True;
      end;
    end;
  finally
    Scan.Free;
  end;
end;

// The default case of the marker switch: a marker that jpg.js does not know
function TJpegDecoder.ParseUnknownSegment: Boolean;
begin
  Result := False;
  const NextMarker = TJpegBytes.FindNextFileMarker(FData, FOffset - 2, FOffset - 3);
  if NextMarker.IsFound and (NextMarker.InvalidMarker >= 0) then
  begin
    Warn('JpegImage.parse - unexpected data, current marker is: %x', [NextMarker.InvalidMarker]);
    FOffset := NextMarker.Offset;
    Exit;
  end;

  if (not NextMarker.IsFound) or (FOffset >= Length(FData) - 1) then
  begin
    Warn('JpegImage.parse - reached the end of the image data without finding an EOI marker (0xFFD9).', []);
    Exit(True);
  end;
  raise EPdfParseException.CreateFmt(UnknownMarker, [TJpegBytes.UInt16At(FData, FOffset - 2)]);
end;

// buildComponentData for every component, with the quantization tables that the whole file defined
procedure TJpegDecoder.BuildComponentData;
begin
  for var Component in FFrame.Components do
  begin
    const TableId = Component.QuantizationId;
    if (TableId >= 0) and (TableId <= High(FQuantizationTables)) and (Length(FQuantizationTables[TableId]) > 0) then
    begin
      Component.QuantizationTable := FQuantizationTables[TableId];
    end;

    if Length(Component.QuantizationTable) = 0 then
    begin
      raise EPdfParseException.Create(MissingQuantizationTable);
    end;

    for var BlockRow := 0 to Component.BlocksPerColumn - 1 do
    begin
      for var BlockCol := 0 to Component.BlocksPerLine - 1 do
      begin
        const Offset = BlockSize * ((Component.BlocksPerLine + 1) * BlockRow + BlockCol);
        QuantizeAndInverse(Component, Offset);
      end;
    end;
  end;
end;

// A port of the IDCT of poppler, which is taken from Loeffler, Ligtenberg and Moschytz, 'Practical Fast 1-D DCT Algorithms with 11
// Multiplications', 1989
procedure TJpegDecoder.QuantizeAndInverse(const Component: TJpegComponent; const BlockBufferOffset: Integer);
begin
  InverseRows(Component, BlockBufferOffset);
  InverseColumns(Component, BlockBufferOffset);
end;

procedure TJpegDecoder.InverseRows(const Component: TJpegComponent; const BlockBufferOffset: Integer);
begin
  const Table = Component.QuantizationTable;
  const Block = Component.BlockData;

  for var RowStep := 0 to BlockSide - 1 do
  begin
    const Row = RowStep * BlockSide;
    const At = BlockBufferOffset + Row;
    var P0 := Integer(Block[At]);
    var P1 := Integer(Block[At + 1]);
    var P2 := Integer(Block[At + 2]);
    var P3 := Integer(Block[At + 3]);
    var P4 := Integer(Block[At + 4]);
    var P5 := Integer(Block[At + 5]);
    var P6 := Integer(Block[At + 6]);
    var P7 := Integer(Block[At + 7]);

    P0 := P0 * Table[Row];

    const HasNoAc = ((P1 or P2 or P3 or P4 or P5 or P6 or P7) = 0);
    if HasNoAc then
    begin
      const Flat = ToInt16(ShiftRight((DctSqrt2 * P0) + 512, 10));
      for var Column := 0 to BlockSide - 1 do
      begin
        FInverseBuffer[Row + Column] := Flat;
      end;
      Continue;
    end;

    P1 := P1 * Table[Row + 1];
    P2 := P2 * Table[Row + 2];
    P3 := P3 * Table[Row + 3];
    P4 := P4 * Table[Row + 4];
    P5 := P5 * Table[Row + 5];
    P6 := P6 * Table[Row + 6];
    P7 := P7 * Table[Row + 7];

    // stage 4
    var V0 := ShiftRight((DctSqrt2 * P0) + 128, 8);
    var V1 := ShiftRight((DctSqrt2 * P4) + 128, 8);
    var V2 := P2;
    var V3 := P6;
    var V4 := ShiftRight((DctSqrt1d2 * (P1 - P7)) + 128, 8);
    var V7 := ShiftRight((DctSqrt1d2 * (P1 + P7)) + 128, 8);
    var V5 := P3 shl 4;
    var V6 := P5 shl 4;

    // stage 3
    V0 := ShiftRight(V0 + V1 + 1, 1);
    V1 := V0 - V1;
    var T := ShiftRight((V2 * DctSin6) + (V3 * DctCos6) + 128, 8);
    V2 := ShiftRight((V2 * DctCos6) - (V3 * DctSin6) + 128, 8);
    V3 := T;
    V4 := ShiftRight(V4 + V6 + 1, 1);
    V6 := V4 - V6;
    V7 := ShiftRight(V7 + V5 + 1, 1);
    V5 := V7 - V5;

    // stage 2
    V0 := ShiftRight(V0 + V3 + 1, 1);
    V3 := V0 - V3;
    V1 := ShiftRight(V1 + V2 + 1, 1);
    V2 := V1 - V2;
    T := ShiftRight((V4 * DctSin3) + (V7 * DctCos3) + 2048, 12);
    V4 := ShiftRight((V4 * DctCos3) - (V7 * DctSin3) + 2048, 12);
    V7 := T;
    T := ShiftRight((V5 * DctSin1) + (V6 * DctCos1) + 2048, 12);
    V5 := ShiftRight((V5 * DctCos1) - (V6 * DctSin1) + 2048, 12);
    V6 := T;

    // stage 1
    FInverseBuffer[Row] := ToInt16(V0 + V7);
    FInverseBuffer[Row + 7] := ToInt16(V0 - V7);
    FInverseBuffer[Row + 1] := ToInt16(V1 + V6);
    FInverseBuffer[Row + 6] := ToInt16(V1 - V6);
    FInverseBuffer[Row + 2] := ToInt16(V2 + V5);
    FInverseBuffer[Row + 5] := ToInt16(V2 - V5);
    FInverseBuffer[Row + 3] := ToInt16(V3 + V4);
    FInverseBuffer[Row + 4] := ToInt16(V3 - V4);
  end;
end;

procedure TJpegDecoder.InverseColumns(const Component: TJpegComponent; const BlockBufferOffset: Integer);
begin
  var Block := Component.BlockData;

  for var Col := 0 to BlockSide - 1 do
  begin
    var P0 := Integer(FInverseBuffer[Col]);
    var P1 := Integer(FInverseBuffer[Col + 8]);
    var P2 := Integer(FInverseBuffer[Col + 16]);
    var P3 := Integer(FInverseBuffer[Col + 24]);
    var P4 := Integer(FInverseBuffer[Col + 32]);
    var P5 := Integer(FInverseBuffer[Col + 40]);
    var P6 := Integer(FInverseBuffer[Col + 48]);
    var P7 := Integer(FInverseBuffer[Col + 56]);

    const HasNoAc = ((P1 or P2 or P3 or P4 or P5 or P6 or P7) = 0);
    if HasNoAc then
    begin
      var Flat := ShiftRight((DctSqrt2 * P0) + 8192, 14);
      if Flat < -2040 then
      begin
        Flat := 0;
      end
      else if Flat >= 2024 then
      begin
        Flat := ByteMax;
      end
      else
      begin
        Flat := ShiftRight(Flat + 2056, 4);
      end;
      for var RowStep := 0 to BlockSide - 1 do
      begin
        Block[BlockBufferOffset + Col + (RowStep * BlockSide)] := ToInt16(Flat);
      end;
      Continue;
    end;

    // stage 4
    var V0 := ShiftRight((DctSqrt2 * P0) + 2048, 12);
    var V1 := ShiftRight((DctSqrt2 * P4) + 2048, 12);
    var V2 := P2;
    var V3 := P6;
    var V4 := ShiftRight((DctSqrt1d2 * (P1 - P7)) + 2048, 12);
    var V7 := ShiftRight((DctSqrt1d2 * (P1 + P7)) + 2048, 12);
    var V5 := P3;
    var V6 := P5;

    // stage 3; v0 is shifted by 128.5 << 5 here, so the final conversion needs no shift of the inputs
    V0 := ShiftRight(V0 + V1 + 1, 1) + 4112;
    V1 := V0 - V1;
    var T := ShiftRight((V2 * DctSin6) + (V3 * DctCos6) + 2048, 12);
    V2 := ShiftRight((V2 * DctCos6) - (V3 * DctSin6) + 2048, 12);
    V3 := T;
    V4 := ShiftRight(V4 + V6 + 1, 1);
    V6 := V4 - V6;
    V7 := ShiftRight(V7 + V5 + 1, 1);
    V5 := V7 - V5;

    // stage 2
    V0 := ShiftRight(V0 + V3 + 1, 1);
    V3 := V0 - V3;
    V1 := ShiftRight(V1 + V2 + 1, 1);
    V2 := V1 - V2;
    T := ShiftRight((V4 * DctSin3) + (V7 * DctCos3) + 2048, 12);
    V4 := ShiftRight((V4 * DctCos3) - (V7 * DctSin3) + 2048, 12);
    V7 := T;
    T := ShiftRight((V5 * DctSin1) + (V6 * DctCos1) + 2048, 12);
    V5 := ShiftRight((V5 * DctCos1) - (V6 * DctSin1) + 2048, 12);
    V6 := T;

    // stage 1 and the conversion to 8 bit integers
    const At = BlockBufferOffset + Col;
    Block[At] := ToInt16(ToSample(V0 + V7));
    Block[At + 56] := ToInt16(ToSample(V0 - V7));
    Block[At + 8] := ToInt16(ToSample(V1 + V6));
    Block[At + 48] := ToInt16(ToSample(V1 - V6));
    Block[At + 16] := ToInt16(ToSample(V2 + V5));
    Block[At + 40] := ToInt16(ToSample(V2 - V5));
    Block[At + 24] := ToInt16(ToSample(V3 + V4));
    Block[At + 32] := ToInt16(ToSample(V3 - V4));
  end;
end;

function TJpegDecoder.ComponentCount: Integer;
begin
  Result := FFrame.Components.Count;
end;

// #getLinearizedBlockData for the size of the image: every sample is that of the block that holds it, the samples of a subsampled
// component repeated
function TJpegDecoder.LinearizeBlockData: TBytes;
begin
  const Width = FFrame.SamplesPerLine;
  const Height = FFrame.ScanLines;
  const Count = ComponentCount;
  SetLength(Result, Int64(Width) * Height * Count);

  var XOffsets: TArray<Integer>;
  SetLength(XOffsets, Width);
  for var Position := 0 to Count - 1 do
  begin
    const Component = FFrame.Components[Position];
    const ScaleX = Component.H / FFrame.MaxH;
    const ScaleY = Component.V / FFrame.MaxV;
    const BlocksPerScanline = (Component.BlocksPerLine + 1) shl 3;
    const Output = Component.BlockData;

    var MaxXOffset := 0;
    for var X := 0 to Width - 1 do
    begin
      const J = Trunc(X * ScaleX);
      XOffsets[X] := ((J and not 7) shl 3) or (J and 7);
      MaxXOffset := Max(MaxXOffset, XOffsets[X]);
    end;

    var Target := Position;
    for var Y := 0 to Height - 1 do
    begin
      const J = Trunc(Y * ScaleY);
      const Index = (BlocksPerScanline * (J and not 7)) or ((J and 7) shl 3);
      if (Int64(Index) + MaxXOffset) >= Length(Output) then
      begin
        raise EPdfParseException.Create(BlockOutsideBuffer);
      end;

      for var X := 0 to Width - 1 do
      begin
        Result[Target] := Byte(Output[Index + XOffsets[X]]);
        Inc(Target, Count);
      end;
    end;
  end;
end;

// _isColorConversionNeeded
function TJpegDecoder.IsColorConversionNeeded: Boolean;
begin
  if FHasAdobe then
  begin
    Exit(FAdobeTransformCode <> 0);
  end;

  if ComponentCount = ComponentsOfColor then
  begin
    if FOptions.ColorTransform = 0 then
    begin
      Exit(False);
    end;

    const IsRgbById = ((FFrame.Components[0].Index = IdRed) and (FFrame.Components[1].Index = IdGreen) and (FFrame.Components[2].Index = IdBlue));
    Exit(not IsRgbById);
  end;
  Result := (FOptions.ColorTransform = 1);
end;

procedure TJpegDecoder.ConvertYccToRgb(const Data: TBytes);
begin
  var Position := 0;
  while Position < Length(Data) do
  begin
    const Y = Data[Position];
    const Cb = Data[Position + 1];
    const Cr = Data[Position + 2];
    Data[Position] := ToByteClamped(Y - 179.456 + (1.402 * Cr));
    Data[Position + 1] := ToByteClamped(Y + 135.459 - (0.344 * Cb) - (0.714 * Cr));
    Data[Position + 2] := ToByteClamped(Y - 226.816 + (1.772 * Cb));
    Inc(Position, 3);
  end;
end;

procedure TJpegDecoder.ConvertYcckToCmyk(const Data: TBytes);
begin
  var Position := 0;
  while Position < Length(Data) do
  begin
    const Y = Data[Position];
    const Cb = Data[Position + 1];
    const Cr = Data[Position + 2];
    Data[Position] := ToByteClamped(434.456 - Y - (1.402 * Cr));
    Data[Position + 1] := ToByteClamped(119.541 - Y + (0.344 * Cb) + (0.714 * Cr));
    Data[Position + 2] := ToByteClamped(481.816 - Y - (1.772 * Cb));
    Inc(Position, 4);
  end;
end;

// The decodeTransform that jpg.js applies to 4 component data that does not come from a PDF file
procedure TJpegDecoder.InvertSamples(const Data: TBytes);
begin
  for var Position := 0 to Length(Data) - 1 do
  begin
    Data[Position] := ByteMax - Data[Position];
  end;
end;

// getData
function TJpegDecoder.BuildImage: TJpegImage;
begin
  var Samples := LinearizeBlockData;
  const Count = ComponentCount;
  if (not FOptions.IsSourcePdf) and (Count = ComponentsOfCmyk) then
  begin
    InvertSamples(Samples);
  end;

  if (Count = ComponentsOfColor) and IsColorConversionNeeded then
  begin
    ConvertYccToRgb(Samples);
  end
  else if (Count = ComponentsOfCmyk) and IsColorConversionNeeded then
  begin
    ConvertYcckToCmyk(Samples);
  end;

  Result := TJpegImage.Create;
  Result.FWidth := FFrame.SamplesPerLine;
  Result.FHeight := FFrame.ScanLines;
  Result.FComponents := Count;
  Result.FSamples := Samples;
end;

{ TJpegImage }

class function TJpegImage.Decode(const Data: TBytes; const Options: TJpegDecodeOptions; const Log: TPdfLog): TJpegImage;
begin
  const Decoder = TJpegDecoder.Create(Data, Options, Log);
  try
    try
      Decoder.Parse(0);
    except
      on Error: EJpegDnlMarker do
      begin
        Decoder.Warn('%s -- attempting to re-parse the JPEG image.', [Error.Message]);
        Decoder.Parse(Error.ScanLines);
      end;
    end;
    Result := Decoder.BuildImage;
  finally
    Decoder.Free;
  end;
end;

end.
