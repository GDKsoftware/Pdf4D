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

  public
    [Test]
    procedure TestSmallListUsesBinaryInsertion;

    [Test]
    procedure TestMergingMatchesJdk;

    [Test]
    procedure TestInconsistentComparisonIsReportedWithPartialOrder;

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

    Result := 0;
    for var Index in Indices do
    begin
      Result := (Result * 31 + Index) mod 1000000007;
    end;
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
