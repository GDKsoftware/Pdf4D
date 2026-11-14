// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Tests for Pdf4D.Text.TimSort. The expected hashes are what java.util.Arrays.sort (JDK 21) gives for the same data.
unit Pdf4D.Text.TimSort.Tests;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Text.TimSort;

type
  [TestFixture]
  TTimSortTests = class
  private
    function Values(const Count: Integer): TArray<Integer>;
    // Sorts the indices 0..Count-1 by the values with a comparison that treats values closer than 60 as equal (not transitive)
    function SortByTolerance(const Count: Integer; out Completed: Boolean): Int64;
    // The same for the keys of one of the block patterns (0 to 3) of 5000 items, with a tolerance that is not 60
    function SortPattern(const Pattern, Tolerance: Integer; out Completed: Boolean): Int64;
    class function PatternKey(const Pattern, Index: Integer): Integer; static;
    class function IndexHash(const Indices: TList<Integer>): Int64; static;

  public
    [Test]
    procedure TestSmallListUsesBinaryInsertion;

    [Test]
    procedure TestMergingMatchesJdk;

    [Test]
    procedure TestInconsistentComparisonIsReportedWithPartialOrder;

    [Test]
    procedure TestLongRunsMatchJdk;

    [Test]
    procedure TestConsistentComparisonSortsStably;

    [Test]
    procedure TestOwnedItemsAreNotFreed;
  end;

implementation

type
  TItem = class
    Key: Integer;
    Position: Integer;
  end;

const
  PatternItemCount = 5000;
  HashModulus = 1000000007;
  // From java.util.Collections.sort (JDK 21) on the same keys and comparison; every sort completed
  JdkHashesForToleranceOne: array[0..3] of Int64 = (600998443, 160199627, 618583199, 414318878);
  JdkHashesForToleranceTwentyFive: array[0..3] of Int64 = (600998443, 600998443, 211293410, 710172078);

{ TTimSortTests }

function TTimSortTests.Values(const Count: Integer): TArray<Integer>;
begin
  SetLength(Result, Count);
  var Seed: Int64 := 12345;
  for var Index := 0 to Count - 1 do
  begin
    Seed := (Seed * 1103515245 + 12345) and $7FFFFFFF;
    Result[Index] := Integer(Seed mod 1000);
  end;
end;

function TTimSortTests.SortByTolerance(const Count: Integer; out Completed: Boolean): Int64;
begin
  const Data = Values(Count);
  const Indices = TList<Integer>.Create;
  try
    for var Index := 0 to Count - 1 do
    begin
      Indices.Add(Index);
    end;

    Completed := TTimSort.Sort<Integer>(Indices,
      function(const Left, Right: Integer): Integer
      begin
        const Difference = Data[Left] - Data[Right];
        if Abs(Difference) < 60 then
        begin
          Result := 0;
        end
        else if Difference < 0 then
        begin
          Result := -1;
        end
        else
        begin
          Result := 1;
        end;
      end);

    Result := IndexHash(Indices);
  finally
    Indices.Free;
  end;
end;

class function TTimSortTests.IndexHash(const Indices: TList<Integer>): Int64;
begin
  Result := 0;
  for var Index in Indices do
  begin
    Result := (Result * 31 + Index) mod HashModulus;
  end;
end;

// Pattern 0: ascending blocks in scrambled order, 1: descending blocks, 2: two interleaving series of ascending blocks,
// 3: alternating ascending and descending blocks with overlapping ranges. The runs are long, so the merges gallop.
class function TTimSortTests.PatternKey(const Pattern, Index: Integer): Integer;
begin
  case Pattern of
    0: Result := (((Index div 500) * 7) mod 10) * 10000 + (Index mod 500) * 3;
    1: Result := (((Index div 500) * 7) mod 10) * 10000 + (499 - (Index mod 500)) * 3;
    2: Result := (Index mod 250) * 8 + ((Index div 250) mod 2) * 1000 + ((Index div 250) div 2) * 37;
  else
    begin
      const Block = Index div 100;
      const Offset = (Block * 13) mod 200;
      if Block mod 2 = 0 then
      begin
        Result := (Index mod 100) * 10 + Offset;
      end
      else
      begin
        Result := (99 - (Index mod 100)) * 10 + Offset;
      end;
    end;
  end;
end;

function TTimSortTests.SortPattern(const Pattern, Tolerance: Integer; out Completed: Boolean): Int64;
begin
  const Indices = TList<Integer>.Create;
  try
    for var Index := 0 to PatternItemCount - 1 do
    begin
      Indices.Add(Index);
    end;

    Completed := TTimSort.Sort<Integer>(Indices,
      function(const Left, Right: Integer): Integer
      begin
        const Difference = PatternKey(Pattern, Left) - PatternKey(Pattern, Right);
        if Abs(Difference) < Tolerance then
        begin
          Result := 0;
        end
        else if Difference < 0 then
        begin
          Result := -1;
        end
        else
        begin
          Result := 1;
        end;
      end);
    Result := IndexHash(Indices);
  finally
    Indices.Free;
  end;
end;

procedure TTimSortTests.TestSmallListUsesBinaryInsertion;
begin
  var Completed: Boolean;
  Assert.AreEqual<Int64>(436872985, SortByTolerance(20, Completed));
  Assert.IsTrue(Completed);
end;

procedure TTimSortTests.TestMergingMatchesJdk;
begin
  var Completed: Boolean;
  Assert.AreEqual<Int64>(230746772, SortByTolerance(100, Completed));
  Assert.IsTrue(Completed);
end;

procedure TTimSortTests.TestInconsistentComparisonIsReportedWithPartialOrder;
begin
  // The JDK throws "Comparison method violates its general contract" here and leaves the array partly merged
  var Completed: Boolean;
  Assert.AreEqual<Int64>(219308268, SortByTolerance(2000, Completed));
  Assert.IsFalse(Completed);
end;

procedure TTimSortTests.TestLongRunsMatchJdk;
begin
  for var Pattern := 0 to 3 do
  begin
    var Completed: Boolean;
    Assert.AreEqual<Int64>(JdkHashesForToleranceOne[Pattern], SortPattern(Pattern, 1, Completed), Format('Pattern %d, tolerance 1', [Pattern]));
    Assert.IsTrue(Completed);
    Assert.AreEqual<Int64>(JdkHashesForToleranceTwentyFive[Pattern], SortPattern(Pattern, 25, Completed), Format('Pattern %d, tolerance 25', [Pattern]));
    Assert.IsTrue(Completed);
  end;
end;

procedure TTimSortTests.TestConsistentComparisonSortsStably;
begin
  const Data = Values(5000);
  const Items = TObjectList<TItem>.Create(True);
  try
    for var Index := 0 to High(Data) do
    begin
      const Item = TItem.Create;
      Item.Key := Data[Index] div 10;
      Item.Position := Index;
      Items.Add(Item);
    end;

    Assert.IsTrue(TTimSort.Sort<TItem>(Items,
      function(const Left, Right: TItem): Integer
      begin
        Result := Left.Key - Right.Key;
      end));

    for var Index := 1 to Items.Count - 1 do
    begin
      Assert.IsTrue((Items[Index - 1].Key < Items[Index].Key) or
                    ((Items[Index - 1].Key = Items[Index].Key) and (Items[Index - 1].Position < Items[Index].Position)));
    end;
  finally
    Items.Free;
  end;
end;

procedure TTimSortTests.TestOwnedItemsAreNotFreed;
begin
  const Items = TObjectList<TItem>.Create(True);
  try
    for var Index := 0 to 99 do
    begin
      const Item = TItem.Create;
      Item.Key := 100 - Index;
      Items.Add(Item);
    end;

    TTimSort.Sort<TItem>(Items,
      function(const Left, Right: TItem): Integer
      begin
        Result := Left.Key - Right.Key;
      end);
    Assert.AreEqual<Integer>(100, Items.Count);
    Assert.AreEqual<Integer>(1, Items[0].Key);
  finally
    Items.Free;
  end;
end;

end.
