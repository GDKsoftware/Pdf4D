// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/VerticalHeaderTable.java (3.0.8)
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/VerticalMetricsTable.java (3.0.8)
unit Pdf4D.FontBox.TrueType.Vertical;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.FontBox.TrueType.DataStream,
  Pdf4D.FontBox.TrueType.Tables;

type
  TVerticalHeaderTable = class(TTTFTable)
  public
    const TableTag = 'vhea';

  private
    FVersion: Single;
    FAscender: SmallInt;
    FDescender: SmallInt;
    FLineGap: SmallInt;
    FAdvanceHeightMax: Integer;
    FMinTopSideBearing: SmallInt;
    FMinBottomSideBearing: SmallInt;
    FYMaxExtent: SmallInt;
    FCaretSlopeRise: SmallInt;
    FCaretSlopeRun: SmallInt;
    FCaretOffset: SmallInt;
    FMetricDataFormat: SmallInt;
    FNumberOfVMetrics: Integer;

  public
    procedure Read(const Host: TTTFTableHost; const Data: TTTFDataStream); override;

    property Version: Single read FVersion;
    property Ascender: SmallInt read FAscender;
    property Descender: SmallInt read FDescender;
    property LineGap: SmallInt read FLineGap;
    property AdvanceHeightMax: Integer read FAdvanceHeightMax;
    property MinTopSideBearing: SmallInt read FMinTopSideBearing;
    property MinBottomSideBearing: SmallInt read FMinBottomSideBearing;
    property YMaxExtent: SmallInt read FYMaxExtent;
    property CaretSlopeRise: SmallInt read FCaretSlopeRise;
    property CaretSlopeRun: SmallInt read FCaretSlopeRun;
    property CaretOffset: SmallInt read FCaretOffset;
    property MetricDataFormat: SmallInt read FMetricDataFormat;
    property NumberOfVMetrics: Integer read FNumberOfVMetrics;
  end;

  // The vmtx table needs the vhea table: a font that has the one without the other cannot be read, as in PDFBox
  TVerticalMetricsTable = class(TTTFTable)
  public
    const TableTag = 'vmtx';

  private
    FAdvanceHeight: TArray<Integer>;
    FTopSideBearing: TArray<SmallInt>;
    FAdditionalTopSideBearing: TArray<SmallInt>;
    FNumVMetrics: Integer;

    procedure ReadAdditionalBearings(const Data: TTTFDataStream; const NumGlyphs: Integer; const BytesRead: Int64);

  public
    procedure Read(const Host: TTTFTableHost; const Data: TTTFDataStream); override;

    // A glyph without a bearing has 0
    function GetTopSideBearing(const GID: Integer): Integer;
    // A glyph beyond the explicit metrics gets the last advance height. A table without metrics gives 0.
    function GetAdvanceHeight(const GID: Integer): Integer;
  end;

implementation

uses
  Pdf4D.Common.Defines;

{ TVerticalHeaderTable }

procedure TVerticalHeaderTable.Read(const Host: TTTFTableHost; const Data: TTTFDataStream);
begin
  FVersion := Data.Read32Fixed;
  FAscender := Data.ReadSignedShort;
  FDescender := Data.ReadSignedShort;
  FLineGap := Data.ReadSignedShort;
  FAdvanceHeightMax := Data.ReadUnsignedShort;
  FMinTopSideBearing := Data.ReadSignedShort;
  FMinBottomSideBearing := Data.ReadSignedShort;
  FYMaxExtent := Data.ReadSignedShort;
  FCaretSlopeRise := Data.ReadSignedShort;
  FCaretSlopeRun := Data.ReadSignedShort;
  FCaretOffset := Data.ReadSignedShort;
  // Four reserved fields
  for var Reserved := 1 to 4 do
  begin
    Data.ReadSignedShort;
  end;
  FMetricDataFormat := Data.ReadSignedShort;
  FNumberOfVMetrics := Data.ReadUnsignedShort;
  FInitialized := True;
end;

{ TVerticalMetricsTable }

procedure TVerticalMetricsTable.Read(const Host: TTTFTableHost; const Data: TTTFDataStream);
begin
  var HeaderTable: TTTFTable;
  if not Host.TryGetTable(TVerticalHeaderTable.TableTag, HeaderTable) then
  begin
    raise EPdfParseException.Create('Could not get vhea table');
  end;

  FNumVMetrics := (HeaderTable as TVerticalHeaderTable).NumberOfVMetrics;
  const NumGlyphs = Host.NumberOfGlyphs;

  SetLength(FAdvanceHeight, FNumVMetrics);
  SetLength(FTopSideBearing, FNumVMetrics);
  var BytesRead: Int64 := 0;
  for var Index := 0 to FNumVMetrics - 1 do
  begin
    FAdvanceHeight[Index] := Data.ReadUnsignedShort;
    FTopSideBearing[Index] := Data.ReadSignedShort;
    Inc(BytesRead, 4);
  end;

  if BytesRead < Length then
  begin
    ReadAdditionalBearings(Data, NumGlyphs, BytesRead);
  end;
  FInitialized := True;
end;

procedure TVerticalMetricsTable.ReadAdditionalBearings(const Data: TTTFDataStream; const NumGlyphs: Integer; const BytesRead: Int64);
begin
  var NumberNonVertical := NumGlyphs - FNumVMetrics;
  // Bad fonts have too many vmetrics
  if NumberNonVertical < 0 then
  begin
    NumberNonVertical := NumGlyphs;
  end;

  var Consumed := BytesRead;
  SetLength(FAdditionalTopSideBearing, NumberNonVertical);
  for var Index := 0 to NumberNonVertical - 1 do
  begin
    if Consumed < Length then
    begin
      FAdditionalTopSideBearing[Index] := Data.ReadSignedShort;
      Inc(Consumed, 2);
    end;
  end;
end;

function TVerticalMetricsTable.GetTopSideBearing(const GID: Integer): Integer;
begin
  if GID < 0 then
  begin
    raise EPdfParseException.CreateFmt('Invalid glyph id %d', [GID]);
  end;

  if GID < FNumVMetrics then
  begin
    Exit(FTopSideBearing[GID]);
  end;

  const AdditionalIndex = GID - FNumVMetrics;
  const HasBearing = (AdditionalIndex < System.Length(FAdditionalTopSideBearing));
  if HasBearing then
  begin
    Result := FAdditionalTopSideBearing[AdditionalIndex];
  end
  else
  begin
    Result := 0;
  end;
end;

function TVerticalMetricsTable.GetAdvanceHeight(const GID: Integer): Integer;
begin
  if GID < 0 then
  begin
    raise EPdfParseException.CreateFmt('Invalid glyph id %d', [GID]);
  end;

  const MetricCount = System.Length(FAdvanceHeight);
  if MetricCount = 0 then
  begin
    Exit(0);
  end;

  // Monospaced fonts may not have a height for every glyph; the last one holds for the rest
  if GID < FNumVMetrics then
  begin
    Result := FAdvanceHeight[GID];
  end
  else
  begin
    Result := FAdvanceHeight[MetricCount - 1];
  end;
end;

end.
