// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/util/IterativeMergeSort.java (3.0.8)
unit Pdf4D.Text.IterativeMergeSort;

interface

uses
  System.SysUtils,
  System.Math,
  System.Generics.Collections,
  System.Generics.Defaults;

type
  // A stable bottom-up merge sort. Unlike a quicksort it never fails on a comparison that is not transitive: the result is
  // then some order, and every item is in it once. Items are only moved, never freed, so the list may own them. When the
  // comparison raises, the list is left as it was.
  TIterativeMergeSort = class
  private
    class procedure MergeRuns(Order, Auxiliary: TArray<Integer>; const From, Middle, Till: Int64; const Comparison: TComparison<Integer>); static;
    // Sorts the indices 0..Count-1, which is what the bottom-up sort of PDFBox does on its array of items
    class function SortedOrder(const Count: Integer; const Comparison: TComparison<Integer>): TArray<Integer>; static;

  public
    class procedure Sort<T>(const List: TList<T>; const Comparison: TComparison<T>); static;
    // Puts the items in the order of the indices (the item that ends at position N is the one that was at Order[N]). The list
    // keeps its items, so a list that owns them frees none.
    class procedure ApplyOrder<T>(const List: TList<T>; const Order: TArray<Integer>); static;
  end;

implementation

{ TIterativeMergeSort }

class procedure TIterativeMergeSort.Sort<T>(const List: TList<T>; const Comparison: TComparison<T>);
begin
  if List.Count < 2 then
  begin
    Exit;
  end;

  // The list is not touched until the order is known
  const Order = SortedOrder(List.Count,
    function(const Left, Right: Integer): Integer
    begin
      Result := Comparison(List[Left], List[Right]);
    end);
  ApplyOrder<T>(List, Order);
end;

class function TIterativeMergeSort.SortedOrder(const Count: Integer; const Comparison: TComparison<Integer>): TArray<Integer>;
begin
  SetLength(Result, Count);
  for var Index := 0 to Count - 1 do
  begin
    Result[Index] := Index;
  end;

  const Auxiliary = Copy(Result);
  var BlockSize: Int64 := 1;
  while BlockSize < Count do
  begin
    var Start: Int64 := 0;
    while Start < Count do
    begin
      MergeRuns(Result, Auxiliary, Start, Start + BlockSize, Start + BlockSize * 2, Comparison);
      Start := Start + BlockSize * 2;
    end;
    BlockSize := BlockSize * 2;
  end;
end;

class procedure TIterativeMergeSort.MergeRuns(Order, Auxiliary: TArray<Integer>; const From, Middle, Till: Int64; const Comparison: TComparison<Integer>);
begin
  if Middle >= Length(Order) then
  begin
    Exit;
  end;

  const Limit = Integer(Min(Till, Int64(Length(Order))));
  const MiddleIndex = Integer(Middle);
  var Left := Integer(From);
  var Right := MiddleIndex;
  for var Target := Integer(From) to Limit - 1 do
  begin
    if Left = MiddleIndex then
    begin
      Auxiliary[Target] := Order[Right];
      Inc(Right);
    end
    else if Right = Limit then
    begin
      Auxiliary[Target] := Order[Left];
      Inc(Left);
    end
    else if Comparison(Order[Right], Order[Left]) < 0 then
    begin
      Auxiliary[Target] := Order[Right];
      Inc(Right);
    end
    else
    begin
      Auxiliary[Target] := Order[Left];
      Inc(Left);
    end;
  end;

  for var Index := Integer(From) to Limit - 1 do
  begin
    Order[Index] := Auxiliary[Index];
  end;
end;

class procedure TIterativeMergeSort.ApplyOrder<T>(const List: TList<T>; const Order: TArray<Integer>);
begin
  // Exchange moves items without a notification, so a list that owns its items does not free them
  var ItemAt: TArray<Integer>;
  var PositionOf: TArray<Integer>;
  SetLength(ItemAt, Length(Order));
  SetLength(PositionOf, Length(Order));
  for var Index := 0 to High(Order) do
  begin
    ItemAt[Index] := Index;
    PositionOf[Index] := Index;
  end;

  for var Target := 0 to High(Order) do
  begin
    const Wanted = Order[Target];
    const Current = PositionOf[Wanted];
    if Current <> Target then
    begin
      const Displaced = ItemAt[Target];
      List.Exchange(Target, Current);
      ItemAt[Current] := Displaced;
      PositionOf[Displaced] := Current;
      ItemAt[Target] := Wanted;
      PositionOf[Wanted] := Target;
    end;
  end;
end;

end.
