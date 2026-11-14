// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/text/PDFTextStripper.java (3.0.8): the characterListMapping of the
// suppression of duplicate overlapping text
unit Pdf4D.Text.OverlapColumn;

interface

uses
  System.SysUtils,
  Pdf4D.Text.ChunkedSortedList;

type
  // The y values of the characters that were shown at one x position
  TOverlapYValues = class
  private
    FValues: TChunkedSortedList<Single>;

    class function CompareValues(const Left, Right: Single): Integer; static;

  public
    constructor Create;
    destructor Destroy; override;

    // The values are kept in the order of Float.compare, without doubles (a TreeSet of Float)
    procedure Add(const Value: Single);
    function HasValueIn(const From, Till: Single): Boolean;
  end;

  // The positions where one character was shown, as x with its y values (a TreeMap of Float to a TreeSet of Float)
  TOverlapColumn = class
  public
    // The most x positions that HasNear looks at. A page that crams more of one character into the tolerance of one position
    // is hostile, and the work for one character stays bounded; the character then counts as not shown before.
    const MaxColumnsScanned = 256;

  private type
    TColumnEntry = record
      X: Single;
      YValues: TOverlapYValues;
    end;

  private
    FColumns: TChunkedSortedList<TColumnEntry>;

    class function CompareEntries(const Left, Right: TColumnEntry): Integer; static;
    function FindOrAddEntry(const X: Single): TOverlapYValues;

  public
    constructor Create;
    destructor Destroy; override;

    procedure Add(const X, Y: Single);
    // Whether a position with x in [X - Tolerance, X + Tolerance) has a y in [Y - Tolerance, Y + Tolerance). Java throws when
    // the range runs backwards (a negative tolerance); here that is an empty range.
    function HasNear(const X, Y, Tolerance: Single): Boolean;
  end;

implementation

uses
  Pdf4D.Text.TextPosition;

{ TOverlapYValues }

constructor TOverlapYValues.Create;
begin
  inherited Create;
  FValues := TChunkedSortedList<Single>.Create(CompareValues);
end;

destructor TOverlapYValues.Destroy;
begin
  FValues.Free;
  inherited;
end;

class function TOverlapYValues.CompareValues(const Left, Right: Single): Integer;
begin
  Result := TJavaFloat.Compare(Left, Right);
end;

procedure TOverlapYValues.Add(const Value: Single);
begin
  const Cursor = FValues.FindLowerBound(Value);
  if FValues.IsEnd(Cursor) then
  begin
    FValues.Insert(Cursor, Value);
    Exit;
  end;

  const Stored = FValues.Item(Cursor);
  if not TJavaFloat.IsSame(Stored, Value) then
  begin
    FValues.Insert(Cursor, Value);
  end;
end;

function TOverlapYValues.HasValueIn(const From, Till: Single): Boolean;
begin
  const Cursor = FValues.FindLowerBound(From);
  if FValues.IsEnd(Cursor) then
  begin
    Exit(False);
  end;

  const Stored = FValues.Item(Cursor);
  Result := (TJavaFloat.Compare(Stored, Till) < 0);
end;

{ TOverlapColumn }

constructor TOverlapColumn.Create;
begin
  inherited Create;
  FColumns := TChunkedSortedList<TColumnEntry>.Create(CompareEntries);
end;

destructor TOverlapColumn.Destroy;
begin
  var Cursor := FColumns.Start;
  while not FColumns.IsEnd(Cursor) do
  begin
    const Entry = FColumns.Item(Cursor);
    Entry.YValues.Free;
    Cursor := FColumns.Next(Cursor);
  end;
  FColumns.Free;
  inherited;
end;

class function TOverlapColumn.CompareEntries(const Left, Right: TColumnEntry): Integer;
begin
  Result := TJavaFloat.Compare(Left.X, Right.X);
end;

function TOverlapColumn.FindOrAddEntry(const X: Single): TOverlapYValues;
begin
  var Probe: TColumnEntry;
  Probe.X := X;
  Probe.YValues := nil;
  const Cursor = FColumns.FindLowerBound(Probe);
  if not FColumns.IsEnd(Cursor) then
  begin
    const Entry = FColumns.Item(Cursor);
    if TJavaFloat.IsSame(Entry.X, X) then
    begin
      Exit(Entry.YValues);
    end;
  end;

  Probe.YValues := TOverlapYValues.Create;
  FColumns.Insert(Cursor, Probe);
  Result := Probe.YValues;
end;

procedure TOverlapColumn.Add(const X, Y: Single);
begin
  FindOrAddEntry(X).Add(Y);
end;

function TOverlapColumn.HasNear(const X, Y, Tolerance: Single): Boolean;
begin
  Result := False;
  const XFrom: Single = X - Tolerance;
  const XTill: Single = X + Tolerance;
  const YFrom: Single = Y - Tolerance;
  const YTill: Single = Y + Tolerance;
  if (TJavaFloat.Compare(XFrom, XTill) > 0) or (TJavaFloat.Compare(YFrom, YTill) > 0) then
  begin
    Exit;
  end;

  var Probe: TColumnEntry;
  Probe.X := XFrom;
  Probe.YValues := nil;
  var Cursor := FColumns.FindLowerBound(Probe);
  var Scanned := 0;
  while (not FColumns.IsEnd(Cursor)) and (Scanned < MaxColumnsScanned) do
  begin
    const Entry = FColumns.Item(Cursor);
    if TJavaFloat.Compare(Entry.X, XTill) >= 0 then
    begin
      Exit;
    end;
    if Entry.YValues.HasValueIn(YFrom, YTill) then
    begin
      Exit(True);
    end;
    Cursor := FColumns.Next(Cursor);
    Inc(Scanned);
  end;
end;

end.
