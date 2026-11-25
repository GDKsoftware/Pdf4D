// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/IndexToLocationTable.java (3.0.8)
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/GlyphTable.java (3.0.8)
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/GlyphData.java (3.0.8)
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/GlyfDescript.java (3.0.8)
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/GlyfSimpleDescript.java (3.0.8)
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/GlyfCompositeDescript.java (3.0.8)
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/GlyfCompositeComp.java (3.0.8)
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/GlyphRenderer.java (3.0.8)
unit Pdf4D.FontBox.TrueType.Glyph;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.Log,
  Pdf4D.Common.Path,
  Pdf4D.FontBox.TrueType.DataStream,
  Pdf4D.FontBox.TrueType.Tables;

type
  // The offsets of the glyphs inside the glyf table. A damaged table is logged and leaves the font without outlines;
  // it never stops the font from loading.
  TIndexToLocationTable = class(TTTFTable)
  public
    const TableTag = 'loca';

  private
    const ShortOffsets = 0;
    const LongOffsets = 1;

  private
    FOffsets: TArray<Int64>;

    procedure ReadOffsets(const Host: TTTFTableHost; const Data: TTTFDataStream);

  public
    procedure Read(const Host: TTTFTableHost; const Data: TTTFDataStream); override;

    // The start of the glyph and the start of the next one. False when the table has no entry for the glyph.
    function TryGetGlyphRange(const GID: Integer; out StartOffset, EndOffset: Int64): Boolean;
  end;

  TGlyphPoint = record
    X: Integer;
    Y: Integer;
    OnCurve: Boolean;
    EndOfContour: Boolean;
  end;

  // One component of a composite glyph
  TGlyphComponent = record
    GlyphIndex: Integer;
    XScale: Double;
    YScale: Double;
    Scale01: Double;
    Scale10: Double;
    XTranslate: Integer;
    YTranslate: Integer;
    HasMoreComponents: Boolean;
  end;

  // The points of a glyph in font units. The coordinates have the 16-bit wrap-around of the short values of PDFBox.
  TGlyphOutline = record
  public
    Points: TArray<TGlyphPoint>;
    // The index of the last point of each contour
    EndPoints: TArray<Integer>;

  private
    class function MidPoint(const First, Second: TGlyphPoint): TGlyphPoint; static;
    class function ContourOf(const Points: TArray<TGlyphPoint>; const StartIndex, StopIndex: Integer): TArray<TGlyphPoint>; static;
    class procedure AddContour(const Path: TPdfPath; const Points: TArray<TGlyphPoint>; const StartIndex, StopIndex: Integer); static;
    function DescribedPoints: TArray<TGlyphPoint>;

  public
    // The 16-bit wrap-around of a Java short
    class function Wrap16(const Value: Integer): Integer; static;

    // Adds the points of a component, moved and scaled by its transformation
    procedure AppendComponent(const Component: TGlyphComponent; const Part: TGlyphOutline);
    // The contours as lines and quadratic curves, as PDFBox draws them. The caller owns the path.
    function ToPath: TPdfPath;
  end;

  // Reads big-endian glyph data and raises EPdfParseException past its end
  TGlyphReader = class
  private
    FBytes: TBytes;
    FPosition: Integer;

    procedure GuardAvailable(const Count: Integer);

  public
    constructor Create(const Bytes: TBytes);

    function ReadUnsignedByte: Integer;
    function ReadSignedByte: Integer;
    function ReadUnsignedShort: Integer;
    function ReadSignedShort: Integer;
    procedure Skip(const Count: Integer);
  end;

  // What one request for a glyph path needs besides the table: the log, the glyphs that are being read and how many
  // glyphs it may still read. A request of its own keeps the table free of changing state, so a shared font stays shareable.
  TGlyphReadContext = class
  private
    FLog: TPdfLog;
    FActiveGlyphs: TList<Integer>;
    FReadsLeft: Integer;

  public
    constructor Create(const Log: TPdfLog; const MaximumReads: Integer);
    destructor Destroy; override;

    procedure Warn(const Fmt: string; const Args: array of const);
    function IsActive(const GID: Integer): Boolean;
    procedure Enter(const GID: Integer);
    procedure Leave;
    // False when the request has read its share of glyphs
    function TryTakeRead: Boolean;
  end;

  // The glyph outlines. The glyphs are read when a path is asked for, from the data of the font, without moving its read position.
  // A glyph that cannot be read gives no path; a composite glyph with a component that cannot be read keeps the other
  // components. PDFBox does the same, except that it then loses the whole glyph when the last component is the one that is missing.
  TGlyphTable = class(TTTFTable)
  public
    const TableTag = 'glyf';
    const MaximumPointCount = 65535;
    // The depth of PDFBox is the one of the maxp table; this is the largest depth that is believed
    const MaximumCompositeDepth = 16;
    // The glyphs one path request may read; a composite glyph can refer to the same glyphs again and again
    const MaximumGlyphReads = 1024;

  private
    const ArgumentsAreWords = $0001;
    const ArgumentsAreXYValues = $0002;
    const HasScale = $0008;
    const MoreComponents = $0020;
    const HasXAndYScale = $0040;
    const HasTwoByTwo = $0080;
    const OnCurveFlag = $01;
    const XShortVector = $02;
    const YShortVector = $04;
    const RepeatFlag = $08;
    const XDual = $10;
    const YDual = $20;
    const UnitsOfScale = 16384.0;

  private
    // Not owned: the data of the font that holds this table, the tables of that font and the log are only borrowed
    FData: TTTFDataStream;
    FLocation: TIndexToLocationTable;
    FMetrics: THorizontalMetricsTable;
    FGlyphCount: Integer;
    FMaximumDepth: Integer;
    FIsUsable: Boolean;

    class function TryReadComponent(const Reader: TGlyphReader; out Component: TGlyphComponent): Boolean; static;
    class function ReadComponent(const Reader: TGlyphReader): TGlyphComponent; static;
    class function ReadFlags(const Reader: TGlyphReader; const PointCount: Integer): TBytes; static;
    class function ReadCoordinates(const Reader: TGlyphReader; const Flags: TBytes; const Start: Integer;
                                   const ShortMask, DualMask: Integer): TArray<Integer>; static;
    class function ReadSimpleOutline(const Reader: TGlyphReader; const ContourCount, FirstX: Integer): TGlyphOutline; static;

    procedure ReadDependencies(const Host: TTTFTableHost);
    function TryGetGlyphBytes(const GID: Integer; const Context: TGlyphReadContext; out Bytes: TBytes): Boolean;
    function TryReadOutline(const GID, Level: Integer; const Context: TGlyphReadContext; out Outline: TGlyphOutline): Boolean;
    function ReadOutline(const GID, Level: Integer; const Context: TGlyphReadContext; const Bytes: TBytes): TGlyphOutline;
    function ReadCompositeOutline(const Reader: TGlyphReader; const Level: Integer; const Context: TGlyphReadContext): TGlyphOutline;
    function LeftSideBearing(const GID: Integer): Integer;

  public
    procedure Read(const Host: TTTFTableHost; const Data: TTTFDataStream); override;

    // The outline of the glyph in font units. A glyph without contours gives an empty path, and so does a glyph beyond the
    // number of glyphs, as in PDFBox. False, with a warning in the log, when the glyph cannot be read. The caller owns the path.
    function TryGetPath(const GID: Integer; out Path: TPdfPath; const Log: TPdfLog = nil): Boolean;
  end;

implementation

uses
  System.Math,
  Pdf4D.Common.Defines;

{ TIndexToLocationTable }

procedure TIndexToLocationTable.Read(const Host: TTTFTableHost; const Data: TTTFDataStream);
begin
  try
    ReadOffsets(Host, Data);
  except
    on Failure: Exception do
    begin
      const IsDamagedData = ((Failure is EPdfParseException) or TPdfFailure.IsInputFailure(Failure));
      if not IsDamagedData then
      begin
        raise;
      end;
      FOffsets := nil;
      Host.LogWarning(Format('The loca table cannot be read, the font has no glyph outlines: %s', [Failure.Message]));
    end;
  end;
  inherited Read(Host, Data);
end;

procedure TIndexToLocationTable.ReadOffsets(const Host: TTTFTableHost; const Data: TTTFDataStream);
begin
  var Table: TTTFTable;
  if not Host.TryGetTable(THeaderTable.TableTag, Table) then
  begin
    raise EPdfParseException.Create('Could not get head table');
  end;

  const OffsetFormat = (Table as THeaderTable).IndexToLocFormat;
  const IsKnownFormat = ((OffsetFormat = ShortOffsets) or (OffsetFormat = LongOffsets));
  if not IsKnownFormat then
  begin
    raise EPdfParseException.CreateFmt('Error:TTF.loca unknown offset format: %d', [OffsetFormat]);
  end;

  const Count = Host.NumberOfGlyphs + 1;
  var Offsets: TArray<Int64>;
  SetLength(Offsets, Count);
  for var Index := 0 to Count - 1 do
  begin
    if OffsetFormat = ShortOffsets then
    begin
      Offsets[Index] := Int64(Data.ReadUnsignedShort) * 2;
    end
    else
    begin
      Offsets[Index] := Data.ReadUnsignedInt;
    end;
  end;
  FOffsets := Offsets;
end;

function TIndexToLocationTable.TryGetGlyphRange(const GID: Integer; out StartOffset, EndOffset: Int64): Boolean;
begin
  StartOffset := 0;
  EndOffset := 0;
  const HasEntry = ((GID >= 0) and (GID + 1 < System.Length(FOffsets)));
  if not HasEntry then
  begin
    Exit(False);
  end;

  StartOffset := FOffsets[GID];
  EndOffset := FOffsets[GID + 1];
  Result := True;
end;

{ TGlyphOutline }

class function TGlyphOutline.Wrap16(const Value: Integer): Integer;
begin
  Result := SmallInt(Value and $FFFF);
end;

class function TGlyphOutline.MidPoint(const First, Second: TGlyphPoint): TGlyphPoint;
begin
  Result.X := First.X + ((Second.X - First.X) div 2);
  Result.Y := First.Y + ((Second.Y - First.Y) div 2);
  Result.OnCurve := True;
  Result.EndOfContour := False;
end;

// The points of the contour with the extra points that make it start and end on the curve
class function TGlyphOutline.ContourOf(const Points: TArray<TGlyphPoint>; const StartIndex, StopIndex: Integer): TArray<TGlyphPoint>;
begin
  const First = Points[StartIndex];
  const Last = Points[StopIndex];
  const OwnPoints = Copy(Points, StartIndex, (StopIndex - StartIndex) + 1);

  if First.OnCurve then
  begin
    Result := OwnPoints + [First];
  end
  else if Last.OnCurve then
  begin
    Result := [Last] + OwnPoints;
  end
  else
  begin
    const Middle = MidPoint(First, Last);
    Result := [Middle] + OwnPoints + [Middle];
  end;
end;

class procedure TGlyphOutline.AddContour(const Path: TPdfPath; const Points: TArray<TGlyphPoint>; const StartIndex, StopIndex: Integer);
begin
  const Contour = ContourOf(Points, StartIndex, StopIndex);
  Path.MoveTo(Contour[0].X, Contour[0].Y);

  var Index := 1;
  while Index < System.Length(Contour) do
  begin
    const Current = Contour[Index];
    if Current.OnCurve then
    begin
      Path.LineTo(Current.X, Current.Y);
    end
    else if Contour[Index + 1].OnCurve then
    begin
      Path.QuadTo(Current.X, Current.Y, Contour[Index + 1].X, Contour[Index + 1].Y);
      Inc(Index);
    end
    else
    begin
      const Middle = MidPoint(Current, Contour[Index + 1]);
      Path.QuadTo(Current.X, Current.Y, Middle.X, Middle.Y);
    end;
    Inc(Index);
  end;
  Path.ClosePath;
end;

// Marks the last point of each contour. A point list that has more points than contours leaves the rest without an end.
function TGlyphOutline.DescribedPoints: TArray<TGlyphPoint>;
begin
  Result := Copy(Points);
  var EndPointIndex := 0;
  var EndPointOfContour := -1;
  for var Index := 0 to System.Length(Result) - 1 do
  begin
    const HasMoreContours = (EndPointIndex < System.Length(EndPoints));
    if (EndPointOfContour = -1) and HasMoreContours then
    begin
      EndPointOfContour := EndPoints[EndPointIndex];
    end;

    const IsEnd = (EndPointOfContour = Index);
    Result[Index].EndOfContour := IsEnd;
    if IsEnd then
    begin
      Inc(EndPointIndex);
      EndPointOfContour := -1;
    end;
  end;
end;

// The points of the component go through its transformation, rounded as Math.round of a float does
procedure TGlyphOutline.AppendComponent(const Component: TGlyphComponent; const Part: TGlyphOutline);
begin
  const FirstIndex = System.Length(Points);
  const FirstContour = System.Length(EndPoints);
  SetLength(Points, FirstIndex + System.Length(Part.Points));
  SetLength(EndPoints, FirstContour + System.Length(Part.EndPoints));

  for var Index := 0 to System.Length(Part.Points) - 1 do
  begin
    const Source = Part.Points[Index];
    const ScaledX = Floor(Double(Single((Source.X * Component.XScale) + (Source.Y * Component.Scale10))) + 0.5);
    const ScaledY = Floor(Double(Single((Source.X * Component.Scale01) + (Source.Y * Component.YScale))) + 0.5);
    Points[FirstIndex + Index].X := Wrap16(ScaledX + Component.XTranslate);
    Points[FirstIndex + Index].Y := Wrap16(ScaledY + Component.YTranslate);
    Points[FirstIndex + Index].OnCurve := Source.OnCurve;
    Points[FirstIndex + Index].EndOfContour := False;
  end;

  for var Index := 0 to System.Length(Part.EndPoints) - 1 do
  begin
    EndPoints[FirstContour + Index] := Part.EndPoints[Index] + FirstIndex;
  end;
end;

function TGlyphOutline.ToPath: TPdfPath;
begin
  Result := TPdfPath.Create;
  try
    const Described = DescribedPoints;
    var StartIndex := 0;
    for var Index := 0 to System.Length(Described) - 1 do
    begin
      if Described[Index].EndOfContour then
      begin
        AddContour(Result, Described, StartIndex, Index);
        StartIndex := Index + 1;
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

{ TGlyphReader }

constructor TGlyphReader.Create(const Bytes: TBytes);
begin
  inherited Create;
  FBytes := Bytes;
end;

procedure TGlyphReader.GuardAvailable(const Count: Integer);
begin
  const IsAvailable = ((Count >= 0) and (Count <= System.Length(FBytes) - FPosition));
  if not IsAvailable then
  begin
    raise EPdfParseException.CreateFmt('Unexpected end of glyph data: %d bytes requested at offset %d of %d',
                                       [Count, FPosition, System.Length(FBytes)]);
  end;
end;

function TGlyphReader.ReadUnsignedByte: Integer;
begin
  GuardAvailable(1);
  Result := FBytes[FPosition];
  Inc(FPosition);
end;

function TGlyphReader.ReadSignedByte: Integer;
begin
  Result := ShortInt(ReadUnsignedByte);
end;

function TGlyphReader.ReadUnsignedShort: Integer;
begin
  GuardAvailable(2);
  Result := (FBytes[FPosition] shl 8) or FBytes[FPosition + 1];
  Inc(FPosition, 2);
end;

function TGlyphReader.ReadSignedShort: Integer;
begin
  Result := SmallInt(ReadUnsignedShort);
end;

procedure TGlyphReader.Skip(const Count: Integer);
begin
  GuardAvailable(Count);
  Inc(FPosition, Count);
end;

{ TGlyphReadContext }

constructor TGlyphReadContext.Create(const Log: TPdfLog; const MaximumReads: Integer);
begin
  inherited Create;
  FLog := Log;
  FActiveGlyphs := TList<Integer>.Create;
  FReadsLeft := MaximumReads;
end;

destructor TGlyphReadContext.Destroy;
begin
  FActiveGlyphs.Free;
  inherited Destroy;
end;

procedure TGlyphReadContext.Warn(const Fmt: string; const Args: array of const);
begin
  if Assigned(FLog) then
  begin
    FLog.Warning(Fmt, Args);
  end;
end;

function TGlyphReadContext.IsActive(const GID: Integer): Boolean;
begin
  Result := FActiveGlyphs.Contains(GID);
end;

procedure TGlyphReadContext.Enter(const GID: Integer);
begin
  FActiveGlyphs.Add(GID);
end;

procedure TGlyphReadContext.Leave;
begin
  FActiveGlyphs.Delete(FActiveGlyphs.Count - 1);
end;

function TGlyphReadContext.TryTakeRead: Boolean;
begin
  Result := (FReadsLeft > 0);
  if Result then
  begin
    Dec(FReadsLeft);
  end;
end;

{ TGlyphTable }

procedure TGlyphTable.Read(const Host: TTTFTableHost; const Data: TTTFDataStream);
begin
  try
    ReadDependencies(Host);
    FData := Data;
    FIsUsable := True;
  except
    on Failure: Exception do
    begin
      const IsDamagedData = ((Failure is EPdfParseException) or TPdfFailure.IsInputFailure(Failure));
      if not IsDamagedData then
      begin
        raise;
      end;
      FIsUsable := False;
      Host.LogWarning(Format('The glyf table cannot be used, the font has no glyph outlines: %s', [Failure.Message]));
    end;
  end;
  inherited Read(Host, Data);
end;

procedure TGlyphTable.ReadDependencies(const Host: TTTFTableHost);
begin
  var Table: TTTFTable;
  if not Host.TryGetTable(TIndexToLocationTable.TableTag, Table) then
  begin
    raise EPdfParseException.Create('The font has no loca table');
  end;
  FLocation := Table as TIndexToLocationTable;

  FGlyphCount := Host.NumberOfGlyphs;

  FMetrics := nil;
  if Host.TryGetTable(THorizontalMetricsTable.TableTag, Table) then
  begin
    FMetrics := Table as THorizontalMetricsTable;
  end;

  FMaximumDepth := 0;
  if Host.TryGetTable(TMaximumProfileTable.TableTag, Table) then
  begin
    FMaximumDepth := Min((Table as TMaximumProfileTable).MaxComponentDepth, MaximumCompositeDepth);
  end;
end;

function TGlyphTable.LeftSideBearing(const GID: Integer): Integer;
begin
  if Assigned(FMetrics) then
  begin
    Result := FMetrics.GetLeftSideBearing(GID);
  end
  else
  begin
    Result := 0;
  end;
end;

class function TGlyphTable.ReadFlags(const Reader: TGlyphReader; const PointCount: Integer): TBytes;
begin
  SetLength(Result, PointCount);
  var Index := 0;
  while Index < PointCount do
  begin
    const Flag = Byte(Reader.ReadUnsignedByte);
    Result[Index] := Flag;

    const HasRepeats = ((Flag and RepeatFlag) <> 0);
    if HasRepeats then
    begin
      const Repeats = Reader.ReadUnsignedByte;
      if Index + Repeats >= PointCount then
      begin
        raise EPdfParseException.CreateFmt('repeat count (%d) higher than remaining space', [Repeats]);
      end;
      for var RepeatIndex := 1 to Repeats do
      begin
        Result[Index + RepeatIndex] := Flag;
      end;
      Inc(Index, Repeats);
    end;
    Inc(Index);
  end;
end;

// The x or the y coordinates: every coordinate is a change of the one before it
class function TGlyphTable.ReadCoordinates(const Reader: TGlyphReader; const Flags: TBytes; const Start: Integer;
                                           const ShortMask, DualMask: Integer): TArray<Integer>;
begin
  SetLength(Result, System.Length(Flags));
  var Value := Start;
  for var Index := 0 to System.Length(Flags) - 1 do
  begin
    const IsShort = ((Flags[Index] and ShortMask) <> 0);
    const IsDual = ((Flags[Index] and DualMask) <> 0);
    if IsDual then
    begin
      if IsShort then
      begin
        Value := TGlyphOutline.Wrap16(Value + Reader.ReadUnsignedByte);
      end;
    end
    else if IsShort then
    begin
      Value := TGlyphOutline.Wrap16(Value - Reader.ReadUnsignedByte);
    end
    else
    begin
      Value := TGlyphOutline.Wrap16(Value + Reader.ReadSignedShort);
    end;
    Result[Index] := Value;
  end;
end;

class function TGlyphTable.ReadSimpleOutline(const Reader: TGlyphReader; const ContourCount, FirstX: Integer): TGlyphOutline;
begin
  Result.Points := nil;
  Result.EndPoints := nil;
  if ContourCount = 0 then
  begin
    Exit;
  end;

  var EndPoints: TArray<Integer>;
  SetLength(EndPoints, ContourCount);
  for var Index := 0 to ContourCount - 1 do
  begin
    EndPoints[Index] := Reader.ReadUnsignedShort;
  end;

  const LastEndPoint = EndPoints[ContourCount - 1];
  const HasNoPoints = ((ContourCount = 1) and (LastEndPoint = $FFFF));
  if HasNoPoints then
  begin
    Exit;
  end;

  const PointCount = LastEndPoint + 1;
  if PointCount > MaximumPointCount then
  begin
    raise EPdfParseException.CreateFmt('The glyph has %d points, more than the %d that are read', [PointCount, MaximumPointCount]);
  end;

  const InstructionCount = Reader.ReadUnsignedShort;
  Reader.Skip(InstructionCount);
  const Flags = ReadFlags(Reader, PointCount);
  const XCoordinates = ReadCoordinates(Reader, Flags, FirstX, XShortVector, XDual);
  const YCoordinates = ReadCoordinates(Reader, Flags, 0, YShortVector, YDual);

  SetLength(Result.Points, PointCount);
  for var Index := 0 to PointCount - 1 do
  begin
    Result.Points[Index].X := XCoordinates[Index];
    Result.Points[Index].Y := YCoordinates[Index];
    Result.Points[Index].OnCurve := ((Flags[Index] and OnCurveFlag) <> 0);
    Result.Points[Index].EndOfContour := False;
  end;
  Result.EndPoints := EndPoints;
end;

class function TGlyphTable.ReadComponent(const Reader: TGlyphReader): TGlyphComponent;
begin
  const Flags = Reader.ReadUnsignedShort;
  Result.GlyphIndex := Reader.ReadUnsignedShort;
  Result.HasMoreComponents := ((Flags and MoreComponents) <> 0);
  Result.XScale := 1.0;
  Result.YScale := 1.0;
  Result.Scale01 := 0.0;
  Result.Scale10 := 0.0;
  Result.XTranslate := 0;
  Result.YTranslate := 0;

  var Argument1: Integer;
  var Argument2: Integer;
  if (Flags and ArgumentsAreWords) <> 0 then
  begin
    Argument1 := Reader.ReadSignedShort;
    Argument2 := Reader.ReadSignedShort;
  end
  else
  begin
    Argument1 := Reader.ReadSignedByte;
    Argument2 := Reader.ReadSignedByte;
  end;

  // Arguments that are point numbers to match are not used, as in PDFBox
  if (Flags and ArgumentsAreXYValues) <> 0 then
  begin
    Result.XTranslate := Argument1;
    Result.YTranslate := Argument2;
  end;

  if (Flags and HasScale) <> 0 then
  begin
    Result.XScale := Reader.ReadSignedShort / UnitsOfScale;
    Result.YScale := Result.XScale;
  end
  else if (Flags and HasXAndYScale) <> 0 then
  begin
    Result.XScale := Reader.ReadSignedShort / UnitsOfScale;
    Result.YScale := Reader.ReadSignedShort / UnitsOfScale;
  end
  else if (Flags and HasTwoByTwo) <> 0 then
  begin
    Result.XScale := Reader.ReadSignedShort / UnitsOfScale;
    Result.Scale01 := Reader.ReadSignedShort / UnitsOfScale;
    Result.Scale10 := Reader.ReadSignedShort / UnitsOfScale;
    Result.YScale := Reader.ReadSignedShort / UnitsOfScale;
  end;
end;

class function TGlyphTable.TryReadComponent(const Reader: TGlyphReader; out Component: TGlyphComponent): Boolean;
begin
  try
    Component := ReadComponent(Reader);
    Result := True;
  except
    on EPdfParseException do
    begin
      Component := Default(TGlyphComponent);
      Result := False;
    end;
  end;
end;

// The bytes of a glyph; an empty array is a glyph without outline. False when the glyph lies outside the table.
function TGlyphTable.TryGetGlyphBytes(const GID: Integer; const Context: TGlyphReadContext; out Bytes: TBytes): Boolean;
begin
  Bytes := nil;
  var StartOffset: Int64;
  var EndOffset: Int64;
  if not FLocation.TryGetGlyphRange(GID, StartOffset, EndOffset) then
  begin
    Context.Warn('Glyph %d has no entry in the loca table', [GID]);
    Exit(False);
  end;

  const IsEmpty = ((StartOffset = EndOffset) or (StartOffset = Length));
  if IsEmpty then
  begin
    Exit(True);
  end;

  if StartOffset > Length then
  begin
    Context.Warn('Glyph %d starts at offset %d, beyond the glyf table of %d bytes', [GID, StartOffset, Length]);
    Exit(False);
  end;

  // A glyph that runs on into the next one, or a next offset that lies before it, is read up to the end of the table
  const StopOffset = IfThen((EndOffset > StartOffset) and (EndOffset <= Length), EndOffset, Length);
  Bytes := FData.ReadRange(Offset + StartOffset, Integer(StopOffset - StartOffset));
  Result := True;
end;

function TGlyphTable.ReadOutline(const GID, Level: Integer; const Context: TGlyphReadContext; const Bytes: TBytes): TGlyphOutline;
begin
  const Reader = TGlyphReader.Create(Bytes);
  try
    const ContourCount = Reader.ReadSignedShort;
    const MinimumX = Reader.ReadSignedShort;
    Reader.Skip(6);

    if ContourCount >= 0 then
    begin
      const FirstX = TGlyphOutline.Wrap16(LeftSideBearing(GID) - MinimumX);
      Result := ReadSimpleOutline(Reader, ContourCount, FirstX);
    end
    else
    begin
      Result := ReadCompositeOutline(Reader, Level + 1, Context);
    end;
  finally
    Reader.Free;
  end;
end;

function TGlyphTable.ReadCompositeOutline(const Reader: TGlyphReader; const Level: Integer; const Context: TGlyphReadContext): TGlyphOutline;
begin
  Result.Points := nil;
  Result.EndPoints := nil;

  // The instructions after the last component are of no use for the outline and are not read
  var Components: TArray<TGlyphComponent>;
  var Component: TGlyphComponent;
  repeat
    if not TryReadComponent(Reader, Component) then
    begin
      Context.Warn('A composite glyph ends inside a component; the components before it are used', []);
      Break;
    end;
    Components := Components + [Component];
  until not Component.HasMoreComponents;

  for Component in Components do
  begin
    var Part: TGlyphOutline;
    if not TryReadOutline(Component.GlyphIndex, Level, Context, Part) then
    begin
      Continue;
    end;

    const PointTotal = System.Length(Result.Points) + System.Length(Part.Points);
    if PointTotal > MaximumPointCount then
    begin
      Context.Warn('A composite glyph has more than %d points; the components from glyph %d on are left out', [MaximumPointCount, Component.GlyphIndex]);
      Break;
    end;
    Result.AppendComponent(Component, Part);
  end;
end;

// False, with a warning, when the glyph is damaged. A component that is damaged is not used by its composite glyph.
function TGlyphTable.TryReadOutline(const GID, Level: Integer; const Context: TGlyphReadContext; out Outline: TGlyphOutline): Boolean;
begin
  Outline.Points := nil;
  Outline.EndPoints := nil;

  const IsOutsideFont = ((GID < 0) or (GID >= FGlyphCount));
  if IsOutsideFont then
  begin
    Context.Warn('Glyph %d does not exist; the font has %d glyphs', [GID, FGlyphCount]);
    Exit(False);
  end;

  if Context.IsActive(GID) then
  begin
    Context.Warn('Glyph %d is a component of itself', [GID]);
    Exit(False);
  end;

  if not Context.TryTakeRead then
  begin
    Context.Warn('Glyph %d is left out: the glyph refers to too many other glyphs', [GID]);
    Exit(False);
  end;

  var Bytes: TBytes;
  try
    if not TryGetGlyphBytes(GID, Context, Bytes) then
    begin
      Exit(False);
    end;
    if System.Length(Bytes) = 0 then
    begin
      Exit(True);
    end;

    if Level > FMaximumDepth then
    begin
      Context.Warn('Glyph %d is left out: composite glyph maximum level (%d) reached', [GID, FMaximumDepth]);
      Exit(False);
    end;

    Context.Enter(GID);
    try
      Outline := ReadOutline(GID, Level, Context, Bytes);
    finally
      Context.Leave;
    end;
    Result := True;
  except
    on Failure: Exception do
    begin
      const IsDamagedData = ((Failure is EPdfParseException) or TPdfFailure.IsInputFailure(Failure));
      if not IsDamagedData then
      begin
        raise;
      end;
      Outline.Points := nil;
      Outline.EndPoints := nil;
      Context.Warn('Glyph %d cannot be read: %s', [GID, Failure.Message]);
      Result := False;
    end;
  end;
end;

function TGlyphTable.TryGetPath(const GID: Integer; out Path: TPdfPath; const Log: TPdfLog): Boolean;
begin
  Path := nil;
  if not FIsUsable then
  begin
    if Assigned(Log) then
    begin
      Log.Warning('The font has no usable glyph outlines');
    end;
    Exit(False);
  end;

  const IsOutsideFont = ((GID < 0) or (GID >= FGlyphCount));
  if IsOutsideFont then
  begin
    Path := TPdfPath.Create;
    Exit(True);
  end;

  const Context = TGlyphReadContext.Create(Log, MaximumGlyphReads);
  try
    var Outline: TGlyphOutline;
    if not TryReadOutline(GID, 0, Context, Outline) then
    begin
      Exit(False);
    end;
    Path := Outline.ToPath;
    Result := True;
  finally
    Context.Free;
  end;
end;

end.
