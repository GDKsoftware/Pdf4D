// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Independent implementation of the stable natural merge sort that Java's Collections.sort uses (the sort that PDFTextStripper.writePage
// calls first), following the public description of the algorithm in listsort.txt by Tim Peters (runs, minrun, galloping with
// MIN_GALLOP 7, merge_lo and merge_hi), the corrected merge-collapse rule of JDK-8072909 / JDK-8203864 (de Gouw et al., "OpenJDK's
// java.utils.Collection.sort() is broken", 2015) and the documented constants and behaviour of the Java variant (MIN_MERGE 32,
// IllegalArgumentException for a comparison that violates its contract).
unit Pdf4D.Text.TimSort;

interface

uses
  System.SysUtils,
  System.Math,
  System.Generics.Collections,
  System.Generics.Defaults;

type
  EComparisonViolation = class(Exception);

  // A stable merge sort. PDFBox sorts its text positions with Collections.sort before it falls back to its own merge sort, and with
  // a comparison that is not transitive (TextPositionComparator) the two give different orders, so the output of PDFBox is only
  // reproduced by running the same algorithm first. The items are sorted by index, so that a list that owns them does not free them.
  TTimSort = class
  private
    const MinMerge = 32;
    const InitialGallopThreshold = 7;
    const ContractViolationMessage = 'Comparison method violates its general contract!';

  private
    FItems: TArray<Integer>;
    FComparison: TComparison<Integer>;
    FGallopThreshold: Integer;
    FScratch: TArray<Integer>;
    FRunStarts: TList<Integer>;
    FRunLengths: TList<Integer>;

    constructor Create(const Items: TArray<Integer>; const Comparison: TComparison<Integer>);
    class function MinimumRunLength(const Count: Integer): Integer; static;
    class procedure RaiseContractViolation; static;

    procedure SortAll;
    procedure SortSmall;
    procedure SortLarge;
    function RunLengthAt(const Start, Till: Integer): Integer;
    procedure ReverseRange(const First, Till: Integer);
    procedure InsertionSortRange(const First, Till, SortedTill: Integer);
    procedure PushRun(const Start, Length: Integer);
    procedure CollapseRuns;
    procedure CollapseAllRuns;
    procedure MergeRunPair(const Index: Integer);
    procedure LoadScratch(const Start, Count: Integer);
    function GallopBefore(const Key: Integer; const Start, Count, Hint: Integer; const Source: TArray<Integer>): Integer;
    function GallopAfter(const Key: Integer; const Start, Count, Hint: Integer; const Source: TArray<Integer>): Integer;
    procedure MergeFromLeft(const Start1, Count1, Start2, Count2: Integer);
    procedure MergeFromRight(const Start1, Count1, Start2, Count2: Integer);
    procedure MoveBlock(const Source: TArray<Integer>; const SourceStart: Integer; const Target: TArray<Integer>; const TargetStart, Count: Integer);
    procedure StoreGallopThreshold(const Value: Integer);

  public
    destructor Destroy; override;

    // Sorts the list. False when the comparison violated its contract (IllegalArgumentException in Java): the list is then
    // partly sorted, as the Java list is, and the caller sorts it again.
    class function Sort<T>(const List: TList<T>; const Comparison: TComparison<T>): Boolean; static;
  end;

implementation

{ TTimSort }

constructor TTimSort.Create(const Items: TArray<Integer>; const Comparison: TComparison<Integer>);
begin
  inherited Create;
  FItems := Items;
  FComparison := Comparison;
  FGallopThreshold := InitialGallopThreshold;
  FRunStarts := TList<Integer>.Create;
  FRunLengths := TList<Integer>.Create;
end;

destructor TTimSort.Destroy;
begin
  FRunLengths.Free;
  FRunStarts.Free;
  inherited;
end;

class function TTimSort.Sort<T>(const List: TList<T>; const Comparison: TComparison<T>): Boolean;
begin
  Result := True;
  const Count = List.Count;
  if Count < 2 then
  begin
    Exit;
  end;

  var Order: TArray<Integer>;
  SetLength(Order, Count);
  for var Index := 0 to Count - 1 do
  begin
    Order[Index] := Index;
  end;

  const Sorter = TTimSort.Create(Order,
    function(const Left, Right: Integer): Integer
    begin
      Result := Comparison(List[Left], List[Right]);
    end);
  try
    try
      Sorter.SortAll;
    except
      on EComparisonViolation do
      begin
        Result := False;
      end;
    end;
  finally
    Sorter.Free;
  end;

  // The order is a permutation also after a violation; swapping applies it without freeing owned items
  var CurrentAt: TArray<Integer>;
  var PositionOf: TArray<Integer>;
  SetLength(CurrentAt, Count);
  SetLength(PositionOf, Count);
  for var Index := 0 to Count - 1 do
  begin
    CurrentAt[Index] := Index;
    PositionOf[Index] := Index;
  end;

  for var Target := 0 to Count - 1 do
  begin
    const Wanted = Order[Target];
    const Source = PositionOf[Wanted];
    if Source <> Target then
    begin
      List.Exchange(Target, Source);
      const Displaced = CurrentAt[Target];
      CurrentAt[Source] := Displaced;
      PositionOf[Displaced] := Source;
      CurrentAt[Target] := Wanted;
      PositionOf[Wanted] := Target;
    end;
  end;
end;

class function TTimSort.MinimumRunLength(const Count: Integer): Integer;
begin
  // The first bits of Count, plus one when any lower bit is set, so that Count / result is close to a power of two
  var Remaining := Count;
  var LowerBitSet := 0;
  while Remaining >= MinMerge do
  begin
    LowerBitSet := LowerBitSet or (Remaining and 1);
    Remaining := Remaining shr 1;
  end;
  Result := Remaining + LowerBitSet;
end;

class procedure TTimSort.RaiseContractViolation;
begin
  raise EComparisonViolation.Create(ContractViolationMessage);
end;

procedure TTimSort.SortAll;
begin
  if Length(FItems) < MinMerge then
  begin
    SortSmall;
  end
  else
  begin
    SortLarge;
  end;
end;

procedure TTimSort.SortSmall;
begin
  const Count = Length(FItems);
  InsertionSortRange(0, Count, RunLengthAt(0, Count));
end;

procedure TTimSort.SortLarge;
begin
  var Start := 0;
  var Remaining := Length(FItems);
  const MinRun = MinimumRunLength(Remaining);
  repeat
    var RunLength := RunLengthAt(Start, Start + Remaining);
    if RunLength < MinRun then
    begin
      const Forced = Min(Remaining, MinRun);
      InsertionSortRange(Start, Start + Forced, Start + RunLength);
      RunLength := Forced;
    end;

    PushRun(Start, RunLength);
    CollapseRuns;
    Inc(Start, RunLength);
    Dec(Remaining, RunLength);
  until Remaining = 0;

  CollapseAllRuns;
end;

// The length of the run that starts at Start: a strictly descending run is reversed, a run that does not descend is kept
function TTimSort.RunLengthAt(const Start, Till: Integer): Integer;
begin
  if Start + 1 = Till then
  begin
    Exit(1);
  end;

  var Next := Start + 2;
  if FComparison(FItems[Start + 1], FItems[Start]) < 0 then
  begin
    while (Next < Till) and (FComparison(FItems[Next], FItems[Next - 1]) < 0) do
    begin
      Inc(Next);
    end;
    ReverseRange(Start, Next);
  end
  else
  begin
    while (Next < Till) and (FComparison(FItems[Next], FItems[Next - 1]) >= 0) do
    begin
      Inc(Next);
    end;
  end;
  Result := Next - Start;
end;

procedure TTimSort.ReverseRange(const First, Till: Integer);
begin
  var Low := First;
  var High := Till - 1;
  while Low < High do
  begin
    const Swapped = FItems[Low];
    FItems[Low] := FItems[High];
    FItems[High] := Swapped;
    Inc(Low);
    Dec(High);
  end;
end;

// Sorts First..Till-1 of which First..SortedTill-1 is sorted already, by inserting each following item at the place that a binary
// search gives, after the items that are not greater
procedure TTimSort.InsertionSortRange(const First, Till, SortedTill: Integer);
begin
  var Next := SortedTill;
  if Next = First then
  begin
    Inc(Next);
  end;

  while Next < Till do
  begin
    const Pivot = FItems[Next];
    var Low := First;
    var High := Next;
    while Low < High do
    begin
      const Middle = (Low + High) shr 1;
      if FComparison(Pivot, FItems[Middle]) < 0 then
      begin
        High := Middle;
      end
      else
      begin
        Low := Middle + 1;
      end;
    end;

    for var Index := Next downto Low + 1 do
    begin
      FItems[Index] := FItems[Index - 1];
    end;
    FItems[Low] := Pivot;
    Inc(Next);
  end;
end;

procedure TTimSort.PushRun(const Start, Length: Integer);
begin
  FRunStarts.Add(Start);
  FRunLengths.Add(Length);
end;

// With the top runs X (third from the top), Y, Z and W (the top): the stack is merged until X > Y + Z and Y > Z hold for every
// triple, also for the triple below the top (the check on W that the first version of the rule lacked)
procedure TTimSort.CollapseRuns;
begin
  while FRunLengths.Count > 1 do
  begin
    var Index := FRunLengths.Count - 2;
    const BelowTopTooShort = (Index > 0) and (FRunLengths[Index - 1] <= FRunLengths[Index] + FRunLengths[Index + 1]);
    const TwoBelowTopTooShort = (Index > 1) and (FRunLengths[Index - 2] <= FRunLengths[Index] + FRunLengths[Index - 1]);
    if BelowTopTooShort or TwoBelowTopTooShort then
    begin
      if FRunLengths[Index - 1] < FRunLengths[Index + 1] then
      begin
        Dec(Index);
      end;
    end
    else if FRunLengths[Index] > FRunLengths[Index + 1] then
    begin
      Break;
    end;
    MergeRunPair(Index);
  end;
end;

procedure TTimSort.CollapseAllRuns;
begin
  while FRunLengths.Count > 1 do
  begin
    var Index := FRunLengths.Count - 2;
    if (Index > 0) and (FRunLengths[Index - 1] < FRunLengths[Index + 1]) then
    begin
      Dec(Index);
    end;
    MergeRunPair(Index);
  end;
end;

// Merges the runs Index and Index + 1, after the items of the first run that are in place and the items of the second run
// that are in place are left out
procedure TTimSort.MergeRunPair(const Index: Integer);
begin
  var Start1 := FRunStarts[Index];
  var Count1 := FRunLengths[Index];
  const Start2 = FRunStarts[Index + 1];
  var Count2 := FRunLengths[Index + 1];

  FRunLengths[Index] := Count1 + Count2;
  FRunStarts.Delete(Index + 1);
  FRunLengths.Delete(Index + 1);

  const FirstPlace = GallopAfter(FItems[Start2], Start1, Count1, 0, FItems);
  Inc(Start1, FirstPlace);
  Dec(Count1, FirstPlace);
  if Count1 = 0 then
  begin
    Exit;
  end;

  Count2 := GallopBefore(FItems[Start1 + Count1 - 1], Start2, Count2, Count2 - 1, FItems);
  if Count2 = 0 then
  begin
    Exit;
  end;

  if Count1 <= Count2 then
  begin
    MergeFromLeft(Start1, Count1, Start2, Count2);
  end
  else
  begin
    MergeFromRight(Start1, Count1, Start2, Count2);
  end;
end;

procedure TTimSort.LoadScratch(const Start, Count: Integer);
begin
  if Length(FScratch) < Count then
  begin
    SetLength(FScratch, Count);
  end;
  MoveBlock(FItems, Start, FScratch, 0, Count);
end;

procedure TTimSort.MoveBlock(const Source: TArray<Integer>; const SourceStart: Integer; const Target: TArray<Integer>; const TargetStart, Count: Integer);
begin
  if Count > 0 then
  begin
    Move(Source[SourceStart], Target[TargetStart], Count * SizeOf(Integer));
  end;
end;

procedure TTimSort.StoreGallopThreshold(const Value: Integer);
begin
  FGallopThreshold := Max(Value, 1);
end;

// Where Key goes in Source[Start..Start+Count-1], before the items that equal it: the number of items that are less than Key.
// The search gallops from Hint with steps 1, 3, 7, ... and ends with a binary search.
function TTimSort.GallopBefore(const Key: Integer; const Start, Count, Hint: Integer; const Source: TArray<Integer>): Integer;
begin
  var Below := 0;
  var Above := 1;
  if FComparison(Key, Source[Start + Hint]) > 0 then
  begin
    const Limit = Count - Hint;
    while (Above < Limit) and (FComparison(Key, Source[Start + Hint + Above]) > 0) do
    begin
      Below := Above;
      Above := Above * 2 + 1;
      if Above <= 0 then
      begin
        Above := Limit;
      end;
    end;
    Above := Min(Above, Limit);
    Inc(Below, Hint);
    Inc(Above, Hint);
  end
  else
  begin
    const Limit = Hint + 1;
    while (Above < Limit) and (FComparison(Key, Source[Start + Hint - Above]) <= 0) do
    begin
      Below := Above;
      Above := Above * 2 + 1;
      if Above <= 0 then
      begin
        Above := Limit;
      end;
    end;
    Above := Min(Above, Limit);
    const OldBelow = Below;
    Below := Hint - Above;
    Above := Hint - OldBelow;
  end;

  Inc(Below);
  while Below < Above do
  begin
    const Middle = Below + ((Above - Below) shr 1);
    if FComparison(Key, Source[Start + Middle]) > 0 then
    begin
      Below := Middle + 1;
    end
    else
    begin
      Above := Middle;
    end;
  end;
  Result := Above;
end;

// Where Key goes in Source[Start..Start+Count-1], after the items that equal it: the number of items that are not greater than Key
function TTimSort.GallopAfter(const Key: Integer; const Start, Count, Hint: Integer; const Source: TArray<Integer>): Integer;
begin
  var Below := 0;
  var Above := 1;
  if FComparison(Key, Source[Start + Hint]) < 0 then
  begin
    const Limit = Hint + 1;
    while (Above < Limit) and (FComparison(Key, Source[Start + Hint - Above]) < 0) do
    begin
      Below := Above;
      Above := Above * 2 + 1;
      if Above <= 0 then
      begin
        Above := Limit;
      end;
    end;
    Above := Min(Above, Limit);
    const OldBelow = Below;
    Below := Hint - Above;
    Above := Hint - OldBelow;
  end
  else
  begin
    const Limit = Count - Hint;
    while (Above < Limit) and (FComparison(Key, Source[Start + Hint + Above]) >= 0) do
    begin
      Below := Above;
      Above := Above * 2 + 1;
      if Above <= 0 then
      begin
        Above := Limit;
      end;
    end;
    Above := Min(Above, Limit);
    Inc(Below, Hint);
    Inc(Above, Hint);
  end;

  Inc(Below);
  while Below < Above do
  begin
    const Middle = Below + ((Above - Below) shr 1);
    if FComparison(Key, Source[Start + Middle]) < 0 then
    begin
      Above := Middle;
    end
    else
    begin
      Below := Middle + 1;
    end;
  end;
  Result := Above;
end;

// Merges two adjacent runs of which the first is not longer than the second: the first is copied aside and the merge
// fills the array from the left
procedure TTimSort.MergeFromLeft(const Start1, Count1, Start2, Count2: Integer);
begin
  LoadScratch(Start1, Count1);
  var Left := 0;
  var LeftCount := Count1;
  var Right := Start2;
  var RightCount := Count2;
  var Dest := Start1;
  var Threshold := FGallopThreshold;

  // The first item of the second run is known to precede the first of the first run
  FItems[Dest] := FItems[Right];
  Inc(Dest);
  Inc(Right);
  Dec(RightCount);
  if RightCount = 0 then
  begin
    MoveBlock(FScratch, Left, FItems, Dest, LeftCount);
    Exit;
  end;
  if LeftCount = 1 then
  begin
    MoveBlock(FItems, Right, FItems, Dest, RightCount);
    FItems[Dest + RightCount] := FScratch[Left];
    Exit;
  end;

  var Finished := False;
  while not Finished do
  begin
    var LeftWins := 0;
    var RightWins := 0;

    // One pair at a time, until one run has won Threshold times in a row
    repeat
      if FComparison(FItems[Right], FScratch[Left]) < 0 then
      begin
        FItems[Dest] := FItems[Right];
        Inc(Dest);
        Inc(Right);
        Inc(RightWins);
        LeftWins := 0;
        Dec(RightCount);
        if RightCount = 0 then
        begin
          Finished := True;
          Break;
        end;
      end
      else
      begin
        FItems[Dest] := FScratch[Left];
        Inc(Dest);
        Inc(Left);
        Inc(LeftWins);
        RightWins := 0;
        Dec(LeftCount);
        if LeftCount = 1 then
        begin
          Finished := True;
          Break;
        end;
      end;
    until (LeftWins or RightWins) >= Threshold;

    // Galloping, until neither search finds a block of at least the initial threshold
    if not Finished then
    begin
      repeat
        LeftWins := GallopAfter(FItems[Right], Left, LeftCount, 0, FScratch);
        if LeftWins <> 0 then
        begin
          MoveBlock(FScratch, Left, FItems, Dest, LeftWins);
          Inc(Dest, LeftWins);
          Inc(Left, LeftWins);
          Dec(LeftCount, LeftWins);
          if LeftCount <= 1 then
          begin
            Finished := True;
            Break;
          end;
        end;

        FItems[Dest] := FItems[Right];
        Inc(Dest);
        Inc(Right);
        Dec(RightCount);
        if RightCount = 0 then
        begin
          Finished := True;
          Break;
        end;

        RightWins := GallopBefore(FScratch[Left], Right, RightCount, 0, FItems);
        if RightWins <> 0 then
        begin
          MoveBlock(FItems, Right, FItems, Dest, RightWins);
          Inc(Dest, RightWins);
          Inc(Right, RightWins);
          Dec(RightCount, RightWins);
          if RightCount = 0 then
          begin
            Finished := True;
            Break;
          end;
        end;

        FItems[Dest] := FScratch[Left];
        Inc(Dest);
        Inc(Left);
        Dec(LeftCount);
        if LeftCount = 1 then
        begin
          Finished := True;
          Break;
        end;
        Dec(Threshold);
      until (LeftWins < InitialGallopThreshold) and (RightWins < InitialGallopThreshold);

      if not Finished then
      begin
        Threshold := Max(Threshold, 0) + 2;
      end;
    end;
  end;
  StoreGallopThreshold(Threshold);

  if LeftCount = 1 then
  begin
    MoveBlock(FItems, Right, FItems, Dest, RightCount);
    FItems[Dest + RightCount] := FScratch[Left];
  end
  else if LeftCount = 0 then
  begin
    RaiseContractViolation;
  end
  else
  begin
    MoveBlock(FScratch, Left, FItems, Dest, LeftCount);
  end;
end;

// The mirror image of MergeFromLeft for a first run that is longer than the second: the second is copied aside and the merge
// fills the array from the right
procedure TTimSort.MergeFromRight(const Start1, Count1, Start2, Count2: Integer);
begin
  LoadScratch(Start2, Count2);
  var Left := Start1 + Count1 - 1;
  var LeftCount := Count1;
  var Right := Count2 - 1;
  var RightCount := Count2;
  var Dest := Start2 + Count2 - 1;
  var Threshold := FGallopThreshold;

  // The last item of the first run is known to follow the last item of the second run
  FItems[Dest] := FItems[Left];
  Dec(Dest);
  Dec(Left);
  Dec(LeftCount);
  if LeftCount = 0 then
  begin
    MoveBlock(FScratch, 0, FItems, Dest - (RightCount - 1), RightCount);
    Exit;
  end;
  if RightCount = 1 then
  begin
    Dec(Dest, LeftCount);
    Dec(Left, LeftCount);
    MoveBlock(FItems, Left + 1, FItems, Dest + 1, LeftCount);
    FItems[Dest] := FScratch[Right];
    Exit;
  end;

  var Finished := False;
  while not Finished do
  begin
    var LeftWins := 0;
    var RightWins := 0;

    repeat
      if FComparison(FScratch[Right], FItems[Left]) < 0 then
      begin
        FItems[Dest] := FItems[Left];
        Dec(Dest);
        Dec(Left);
        Inc(LeftWins);
        RightWins := 0;
        Dec(LeftCount);
        if LeftCount = 0 then
        begin
          Finished := True;
          Break;
        end;
      end
      else
      begin
        FItems[Dest] := FScratch[Right];
        Dec(Dest);
        Dec(Right);
        Inc(RightWins);
        LeftWins := 0;
        Dec(RightCount);
        if RightCount = 1 then
        begin
          Finished := True;
          Break;
        end;
      end;
    until (LeftWins or RightWins) >= Threshold;

    if not Finished then
    begin
      repeat
        LeftWins := LeftCount - GallopAfter(FScratch[Right], Start1, LeftCount, LeftCount - 1, FItems);
        if LeftWins <> 0 then
        begin
          Dec(Dest, LeftWins);
          Dec(Left, LeftWins);
          Dec(LeftCount, LeftWins);
          MoveBlock(FItems, Left + 1, FItems, Dest + 1, LeftWins);
          if LeftCount = 0 then
          begin
            Finished := True;
            Break;
          end;
        end;

        FItems[Dest] := FScratch[Right];
        Dec(Dest);
        Dec(Right);
        Dec(RightCount);
        if RightCount = 1 then
        begin
          Finished := True;
          Break;
        end;

        RightWins := RightCount - GallopBefore(FItems[Left], 0, RightCount, RightCount - 1, FScratch);
        if RightWins <> 0 then
        begin
          Dec(Dest, RightWins);
          Dec(Right, RightWins);
          Dec(RightCount, RightWins);
          MoveBlock(FScratch, Right + 1, FItems, Dest + 1, RightWins);
          if RightCount <= 1 then
          begin
            Finished := True;
            Break;
          end;
        end;

        FItems[Dest] := FItems[Left];
        Dec(Dest);
        Dec(Left);
        Dec(LeftCount);
        if LeftCount = 0 then
        begin
          Finished := True;
          Break;
        end;
        Dec(Threshold);
      until (LeftWins < InitialGallopThreshold) and (RightWins < InitialGallopThreshold);

      if not Finished then
      begin
        Threshold := Max(Threshold, 0) + 2;
      end;
    end;
  end;
  StoreGallopThreshold(Threshold);

  if RightCount = 1 then
  begin
    Dec(Dest, LeftCount);
    Dec(Left, LeftCount);
    MoveBlock(FItems, Left + 1, FItems, Dest + 1, LeftCount);
    FItems[Dest] := FScratch[Right];
  end
  else if RightCount = 0 then
  begin
    RaiseContractViolation;
  end
  else
  begin
    MoveBlock(FScratch, 0, FItems, Dest - (RightCount - 1), RightCount);
  end;
end;

end.
