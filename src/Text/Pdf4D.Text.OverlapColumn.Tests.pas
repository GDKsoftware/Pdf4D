// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests for Pdf4D.Text.ChunkedSortedList and Pdf4D.Text.OverlapColumn: the order of a TreeMap, and the time on hostile input
unit Pdf4D.Text.OverlapColumn.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Diagnostics,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Text.ChunkedSortedList,
  Pdf4D.Text.OverlapColumn;

type
  TKnownPosition = record
    X: Single;
    Y: Single;
  end;

  [TestFixture]
  TOverlapColumnTests = class
  private
    class function CompareIntegers(const Left, Right: Integer): Integer; static;
    class function HasNearInList(const Known: TList<TKnownPosition>; const X, Y, Tolerance: Single): Boolean; static;
    class function NextRandom(const Seed: Cardinal): Cardinal; static;

  public
    [Test]
    procedure TestChunkedListKeepsOrderAcrossSplits;

    [Test]
    procedure TestChunkedListInsertsAtTheEnd;

    [Test]
    procedure TestYValuesIgnoreDuplicates;

    [Test]
    procedure TestHasNearMatchesTheTreeMapRange;

    [Test]
    procedure TestHasNearGivesTheSameAnswersAsAPlainList;

    [Test]
    procedure TestNegativeToleranceFindsNothing;

    [Test]
    procedure TestScanOfNeighbouringColumnsIsBounded;

    [Test]
    procedure TestScatteredPositionsAreInsertedInTime;
  end;

implementation

uses
  Pdf4D.Text.TextPosition;

const
  MaxSecondsForHostileInput = 20;
  ScatteredPositionCount = 500000;
  RandomMultiplier = 1103515245;
  RandomIncrement = 12345;
  RandomMask = $7FFFFFFF;

{ TOverlapColumnTests }

class function TOverlapColumnTests.CompareIntegers(const Left, Right: Integer): Integer;
begin
  Result := Left - Right;
end;

class function TOverlapColumnTests.NextRandom(const Seed: Cardinal): Cardinal;
begin
  Result := Cardinal((Int64(Seed) * RandomMultiplier + RandomIncrement) and RandomMask);
end;

class function TOverlapColumnTests.HasNearInList(const Known: TList<TKnownPosition>; const X, Y, Tolerance: Single): Boolean;
begin
  const XFrom: Single = X - Tolerance;
  const XTill: Single = X + Tolerance;
  const YFrom: Single = Y - Tolerance;
  const YTill: Single = Y + Tolerance;
  Result := False;
  for var Position in Known do
  begin
    const IsInX = (TJavaFloat.Compare(Position.X, XFrom) >= 0) and (TJavaFloat.Compare(Position.X, XTill) < 0);
    const IsInY = (TJavaFloat.Compare(Position.Y, YFrom) >= 0) and (TJavaFloat.Compare(Position.Y, YTill) < 0);
    if IsInX and IsInY then
    begin
      Exit(True);
    end;
  end;
end;

procedure TOverlapColumnTests.TestChunkedListKeepsOrderAcrossSplits;
begin
  const List = TChunkedSortedList<Integer>.Create(CompareIntegers);
  try
    var Seed: Cardinal := 7;
    var Expected := TList<Integer>.Create;
    try
      for var Index := 1 to 5000 do
      begin
        Seed := NextRandom(Seed);
        const Value = Integer(Seed mod 100000);
        List.Insert(List.FindLowerBound(Value), Value);
        Expected.Add(Value);
      end;
      Expected.Sort;

      Assert.AreEqual<Integer>(Expected.Count, List.Count);
      var Cursor := List.Start;
      for var Value in Expected do
      begin
        Assert.IsFalse(List.IsEnd(Cursor));
        Assert.AreEqual<Integer>(Value, List.Item(Cursor));
        Cursor := List.Next(Cursor);
      end;
      Assert.IsTrue(List.IsEnd(Cursor));
    finally
      Expected.Free;
    end;
  finally
    List.Free;
  end;
end;

procedure TOverlapColumnTests.TestChunkedListInsertsAtTheEnd;
begin
  const List = TChunkedSortedList<Integer>.Create(CompareIntegers);
  try
    Assert.IsTrue(List.IsEnd(List.Start));
    for var Value := 1 to 1000 do
    begin
      List.Insert(List.FindLowerBound(Value), Value);
    end;

    Assert.AreEqual<Integer>(1000, List.Count);
    Assert.AreEqual<Integer>(1, List.Item(List.FindLowerBound(0)));
    Assert.AreEqual<Integer>(1000, List.Item(List.FindLowerBound(1000)));
    Assert.IsTrue(List.IsEnd(List.FindLowerBound(1001)));
  finally
    List.Free;
  end;
end;

procedure TOverlapColumnTests.TestYValuesIgnoreDuplicates;
begin
  const Values = TOverlapYValues.Create;
  try
    Values.Add(5);
    Values.Add(5);
    Values.Add(7);

    Assert.IsTrue(Values.HasValueIn(5, 6));
    Assert.IsFalse(Values.HasValueIn(5.5, 7));
    Assert.IsTrue(Values.HasValueIn(5.5, 7.5));
  finally
    Values.Free;
  end;
end;

procedure TOverlapColumnTests.TestHasNearMatchesTheTreeMapRange;
begin
  const Column = TOverlapColumn.Create;
  try
    Column.Add(10, 20);

    // subMap(x - tolerance, x + tolerance) has an inclusive start and an exclusive end, for x and for y
    Assert.IsTrue(Column.HasNear(11, 21, 1));
    Assert.IsFalse(Column.HasNear(9, 20, 1));
    Assert.IsFalse(Column.HasNear(10, 19, 1));
    Assert.IsTrue(Column.HasNear(10, 20, 1));
    Assert.IsFalse(Column.HasNear(30, 20, 1));
  finally
    Column.Free;
  end;
end;

procedure TOverlapColumnTests.TestHasNearGivesTheSameAnswersAsAPlainList;
begin
  const Column = TOverlapColumn.Create;
  const Known = TList<TKnownPosition>.Create;
  try
    var Seed: Cardinal := 99;
    var Found := 0;
    for var Index := 1 to 20000 do
    begin
      Seed := NextRandom(Seed);
      var Position: TKnownPosition;
      Position.X := Single((Seed shr 4) mod 100) / 2;
      Seed := NextRandom(Seed);
      Position.Y := Single((Seed shr 4) mod 100) / 2;

      const Expected = HasNearInList(Known, Position.X, Position.Y, 1);
      const Actual = Column.HasNear(Position.X, Position.Y, 1);
      Assert.AreEqual(Expected, Actual, Format('Position %d', [Index]));
      if Actual then
      begin
        Inc(Found);
      end
      else
      begin
        Column.Add(Position.X, Position.Y);
        Known.Add(Position);
      end;
    end;

    Assert.IsTrue(Found > 1000, 'The positions must repeat');
    Assert.IsTrue(Known.Count > 100, 'The positions must differ');
  finally
    Known.Free;
    Column.Free;
  end;
end;

procedure TOverlapColumnTests.TestNegativeToleranceFindsNothing;
begin
  const Column = TOverlapColumn.Create;
  try
    Column.Add(10, 20);

    Assert.IsFalse(Column.HasNear(10, 20, -1));
  finally
    Column.Free;
  end;
end;

procedure TOverlapColumnTests.TestScanOfNeighbouringColumnsIsBounded;
begin
  const Column = TOverlapColumn.Create;
  try
    const Count = TOverlapColumn.MaxColumnsScanned * 2;
    for var Index := 0 to Count - 2 do
    begin
      Column.Add(Index, 5000);
    end;
    // Only the last column has a y in the range, and it lies behind the columns that are scanned
    Column.Add(Count - 1, 500);

    Assert.IsFalse(Column.HasNear(Count / 2, 500, Count));
    // Within the bound the match is found
    Assert.IsTrue(Column.HasNear(Count - 1, 500, 1));
  finally
    Column.Free;
  end;
end;

procedure TOverlapColumnTests.TestScatteredPositionsAreInsertedInTime;
begin
  const Column = TOverlapColumn.Create;
  try
    const Watch = TStopwatch.StartNew;
    var Seed: Cardinal := 1;
    for var Index := 1 to ScatteredPositionCount do
    begin
      Seed := NextRandom(Seed);
      const X = Single(Seed mod 1000000);
      Seed := NextRandom(Seed);
      const Y = Single(Seed mod 1000000);
      if not Column.HasNear(X, Y, 0.1) then
      begin
        Column.Add(X, Y);
      end;
    end;

    Assert.IsTrue(Watch.Elapsed.TotalSeconds < MaxSecondsForHostileInput, Format('Took %.1f seconds', [Watch.Elapsed.TotalSeconds]));
  finally
    Column.Free;
  end;
end;

end.
