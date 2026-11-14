// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: java.util.TimSort (OpenJDK 21), the sort behind Collections.sort that PDFTextStripper.writePage calls first
unit Pdf4D.Text.TimSort;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults;

type
  EComparisonViolation = class(Exception);

  // The stable merge sort of the JDK (Collections.sort). PDFBox sorts its text positions with it before it falls back to its
  // own merge sort, and with a comparison that is not transitive (TextPositionComparator) the two give different orders, so
  // the output of PDFBox is only reproduced by running the same algorithm first. The items are sorted by index, so that a
  // list that owns them does not free them.
  TTimSort = class
  private
    const MinMerge = 32;
    const MinGallopStart = 7;
    const InitialTmpStorageLength = 256;
    const MaxStackLength = 49;
    const ContractViolationMessage = 'Comparison method violates its general contract';

  private
    FItems: TArray<Integer>;
    FComparison: TComparison<Integer>;
    FMinGallop: Integer;
    FTmp: TArray<Integer>;
    FStackSize: Integer;
    FRunBase: TArray<Integer>;
    FRunLen: TArray<Integer>;

    constructor Create(const Items: TArray<Integer>; const Comparison: TComparison<Integer>);

    class procedure Copy(const Source: TArray<Integer>; const SourcePosition: Integer; const Target: TArray<Integer>; const TargetPosition, Count: Integer); static;
    class procedure ReverseRange(const Items: TArray<Integer>; const First, Till: Integer); static;
    class function MinRunLength(const Count: Integer): Integer; static;
    class procedure RaiseContractViolation; static;

    function CountRunAndMakeAscending(const First, Till: Integer): Integer;
    procedure BinarySort(const First, Till, Start: Integer);
    function GallopLeft(const Key: Integer; const Source: TArray<Integer>; const Base, Len, Hint: Integer): Integer;
    function GallopRight(const Key: Integer; const Source: TArray<Integer>; const Base, Len, Hint: Integer): Integer;
    procedure PushRun(const Base, Len: Integer);
    procedure MergeCollapse;
    procedure MergeForceCollapse;
    procedure MergeAt(const Index: Integer);
    procedure MergeLo(const Base1, Len1Start, Base2, Len2Start: Integer);
    procedure MergeHi(const Base1, Len1Start, Base2, Len2Start: Integer);
    procedure EnsureCapacity(const MinCapacity: Integer);
    procedure Run;
    function RunSafely: Boolean;

  public
    // Sorts the list. False when the comparison violated its contract (IllegalArgumentException in Java): the list is then
    // partly sorted, as the Java list is, and the caller sorts it again.
    class function Sort<T>(const List: TList<T>; const Comparison: TComparison<T>): Boolean; static;
  end;

implementation

uses
  Pdf4D.Text.IterativeMergeSort;

{ TTimSort }

constructor TTimSort.Create(const Items: TArray<Integer>; const Comparison: TComparison<Integer>);
begin
  inherited Create;
  FItems := Items;
  FComparison := Comparison;
  FMinGallop := MinGallopStart;
  const Count = Length(Items);
  if Count < 2 * InitialTmpStorageLength then
  begin
    SetLength(FTmp, Count shr 1);
  end
  else
  begin
    SetLength(FTmp, InitialTmpStorageLength);
  end;
  SetLength(FRunBase, MaxStackLength);
  SetLength(FRunLen, MaxStackLength);
end;

class function TTimSort.Sort<T>(const List: TList<T>; const Comparison: TComparison<T>): Boolean;
begin
  Result := True;
  if List.Count < 2 then
  begin
    Exit;
  end;

  var Items: TArray<Integer>;
  SetLength(Items, List.Count);
  for var Index := 0 to High(Items) do
  begin
    Items[Index] := Index;
  end;

  const Sorter = TTimSort.Create(Items,
    function(const Left, Right: Integer): Integer
    begin
      Result := Comparison(List[Left], List[Right]);
    end);
  try
    Result := Sorter.RunSafely;
    TIterativeMergeSort.ApplyOrder<T>(List, Sorter.FItems);
  finally
    Sorter.Free;
  end;
end;

class procedure TTimSort.Copy(const Source: TArray<Integer>; const SourcePosition: Integer; const Target: TArray<Integer>; const TargetPosition, Count: Integer);
begin
  // Move copes with a source and a target that overlap, as System.arraycopy does
  if Count > 0 then
  begin
    Move(Source[SourcePosition], Target[TargetPosition], Count * SizeOf(Integer));
  end;
end;

class procedure TTimSort.ReverseRange(const Items: TArray<Integer>; const First, Till: Integer);
begin
  var Low := First;
  var High := Till - 1;
  while Low < High do
  begin
    const Swapped = Items[Low];
    Items[Low] := Items[High];
    Items[High] := Swapped;
    Inc(Low);
    Dec(High);
  end;
end;

class procedure TTimSort.RaiseContractViolation;
begin
  raise EComparisonViolation.Create(ContractViolationMessage);
end;

class function TTimSort.MinRunLength(const Count: Integer): Integer;
begin
  var Remaining := Count;
  var Carry := 0;
  while Remaining >= MinMerge do
  begin
    Carry := Carry or (Remaining and 1);
    Remaining := Remaining shr 1;
  end;
  Result := Remaining + Carry;
end;

function TTimSort.RunSafely: Boolean;
begin
  try
    Run;
    Result := True;
  except
    on EComparisonViolation do
    begin
      Result := False;
    end;
  end;
end;

procedure TTimSort.Run;
begin
  var Remaining := Length(FItems);
  if Remaining < 2 then
  begin
    Exit;
  end;

  // A small array gets a "mini-TimSort" without merges
  if Remaining < MinMerge then
  begin
    const InitialRunLength = CountRunAndMakeAscending(0, Remaining);
    BinarySort(0, Remaining, InitialRunLength);
    Exit;
  end;

  var First := 0;
  const MinRun = MinRunLength(Remaining);
  repeat
    var RunLength := CountRunAndMakeAscending(First, Length(FItems));
    if RunLength < MinRun then
    begin
      var Force := MinRun;
      if Remaining <= MinRun then
      begin
        Force := Remaining;
      end;
      BinarySort(First, First + Force, First + RunLength);
      RunLength := Force;
    end;

    PushRun(First, RunLength);
    MergeCollapse;

    Inc(First, RunLength);
    Dec(Remaining, RunLength);
  until Remaining = 0;

  MergeForceCollapse;
end;

function TTimSort.CountRunAndMakeAscending(const First, Till: Integer): Integer;
begin
  var RunHigh := First + 1;
  if RunHigh = Till then
  begin
    Exit(1);
  end;

  Inc(RunHigh);
  if FComparison(FItems[RunHigh - 1], FItems[First]) < 0 then
  begin
    // Descending
    while (RunHigh < Till) and (FComparison(FItems[RunHigh], FItems[RunHigh - 1]) < 0) do
    begin
      Inc(RunHigh);
    end;
    ReverseRange(FItems, First, RunHigh);
  end
  else
  begin
    while (RunHigh < Till) and (FComparison(FItems[RunHigh], FItems[RunHigh - 1]) >= 0) do
    begin
      Inc(RunHigh);
    end;
  end;
  Result := RunHigh - First;
end;

procedure TTimSort.BinarySort(const First, Till, Start: Integer);
begin
  var Current := Start;
  if Current = First then
  begin
    Inc(Current);
  end;

  while Current < Till do
  begin
    const Pivot = FItems[Current];
    var Left := First;
    var Right := Current;
    while Left < Right do
    begin
      const Middle = (Left + Right) shr 1;
      if FComparison(Pivot, FItems[Middle]) < 0 then
      begin
        Right := Middle;
      end
      else
      begin
        Left := Middle + 1;
      end;
    end;

    // Slide the items over to make room for the pivot
    Copy(FItems, Left, FItems, Left + 1, Current - Left);
    FItems[Left] := Pivot;
    Inc(Current);
  end;
end;

function TTimSort.GallopLeft(const Key: Integer; const Source: TArray<Integer>; const Base, Len, Hint: Integer): Integer;
begin
  var LastOffset := 0;
  var Offset := 1;
  if FComparison(Key, Source[Base + Hint]) > 0 then
  begin
    // Gallop right until Source[Base + Hint + LastOffset] < Key <= Source[Base + Hint + Offset]
    const MaxOffset = Len - Hint;
    while (Offset < MaxOffset) and (FComparison(Key, Source[Base + Hint + Offset]) > 0) do
    begin
      LastOffset := Offset;
      Offset := (Offset shl 1) + 1;
      if Offset <= 0 then
      begin
        Offset := MaxOffset;
      end;
    end;
    if Offset > MaxOffset then
    begin
      Offset := MaxOffset;
    end;

    Inc(LastOffset, Hint);
    Inc(Offset, Hint);
  end
  else
  begin
    // Gallop left until Source[Base + Hint - Offset] < Key <= Source[Base + Hint - LastOffset]
    const MaxOffset = Hint + 1;
    while (Offset < MaxOffset) and (FComparison(Key, Source[Base + Hint - Offset]) <= 0) do
    begin
      LastOffset := Offset;
      Offset := (Offset shl 1) + 1;
      if Offset <= 0 then
      begin
        Offset := MaxOffset;
      end;
    end;
    if Offset > MaxOffset then
    begin
      Offset := MaxOffset;
    end;

    const Previous = LastOffset;
    LastOffset := Hint - Offset;
    Offset := Hint - Previous;
  end;

  // Source[Base + LastOffset] < Key <= Source[Base + Offset]: a binary search finishes it
  Inc(LastOffset);
  while LastOffset < Offset do
  begin
    const Middle = LastOffset + ((Offset - LastOffset) shr 1);
    if FComparison(Key, Source[Base + Middle]) > 0 then
    begin
      LastOffset := Middle + 1;
    end
    else
    begin
      Offset := Middle;
    end;
  end;
  Result := Offset;
end;

function TTimSort.GallopRight(const Key: Integer; const Source: TArray<Integer>; const Base, Len, Hint: Integer): Integer;
begin
  var Offset := 1;
  var LastOffset := 0;
  if FComparison(Key, Source[Base + Hint]) < 0 then
  begin
    // Gallop left until Source[Base + Hint - Offset] <= Key < Source[Base + Hint - LastOffset]
    const MaxOffset = Hint + 1;
    while (Offset < MaxOffset) and (FComparison(Key, Source[Base + Hint - Offset]) < 0) do
    begin
      LastOffset := Offset;
      Offset := (Offset shl 1) + 1;
      if Offset <= 0 then
      begin
        Offset := MaxOffset;
      end;
    end;
    if Offset > MaxOffset then
    begin
      Offset := MaxOffset;
    end;

    const Previous = LastOffset;
    LastOffset := Hint - Offset;
    Offset := Hint - Previous;
  end
  else
  begin
    // Gallop right until Source[Base + Hint + LastOffset] <= Key < Source[Base + Hint + Offset]
    const MaxOffset = Len - Hint;
    while (Offset < MaxOffset) and (FComparison(Key, Source[Base + Hint + Offset]) >= 0) do
    begin
      LastOffset := Offset;
      Offset := (Offset shl 1) + 1;
      if Offset <= 0 then
      begin
        Offset := MaxOffset;
      end;
    end;
    if Offset > MaxOffset then
    begin
      Offset := MaxOffset;
    end;

    Inc(LastOffset, Hint);
    Inc(Offset, Hint);
  end;

  Inc(LastOffset);
  while LastOffset < Offset do
  begin
    const Middle = LastOffset + ((Offset - LastOffset) shr 1);
    if FComparison(Key, Source[Base + Middle]) < 0 then
    begin
      Offset := Middle;
    end
    else
    begin
      LastOffset := Middle + 1;
    end;
  end;
  Result := Offset;
end;

procedure TTimSort.PushRun(const Base, Len: Integer);
begin
  FRunBase[FStackSize] := Base;
  FRunLen[FStackSize] := Len;
  Inc(FStackSize);
end;

procedure TTimSort.MergeCollapse;
begin
  while FStackSize > 1 do
  begin
    var RunIndex := FStackSize - 2;
    if ((RunIndex > 0) and (FRunLen[RunIndex - 1] <= FRunLen[RunIndex] + FRunLen[RunIndex + 1])) or
       ((RunIndex > 1) and (FRunLen[RunIndex - 2] <= FRunLen[RunIndex] + FRunLen[RunIndex - 1])) then
    begin
      if FRunLen[RunIndex - 1] < FRunLen[RunIndex + 1] then
      begin
        Dec(RunIndex);
      end;
    end
    else if (RunIndex < 0) or (FRunLen[RunIndex] > FRunLen[RunIndex + 1]) then
    begin
      // The invariant holds
      Break;
    end;
    MergeAt(RunIndex);
  end;
end;

procedure TTimSort.MergeForceCollapse;
begin
  while FStackSize > 1 do
  begin
    var RunIndex := FStackSize - 2;
    if (RunIndex > 0) and (FRunLen[RunIndex - 1] < FRunLen[RunIndex + 1]) then
    begin
      Dec(RunIndex);
    end;
    MergeAt(RunIndex);
  end;
end;

procedure TTimSort.MergeAt(const Index: Integer);
begin
  var Base1 := FRunBase[Index];
  var Len1 := FRunLen[Index];
  const Base2 = FRunBase[Index + 1];
  var Len2 := FRunLen[Index + 1];

  // The current run goes away. If Index is the third last run, the last one slides over.
  FRunLen[Index] := Len1 + Len2;
  if Index = FStackSize - 3 then
  begin
    FRunBase[Index + 1] := FRunBase[Index + 2];
    FRunLen[Index + 1] := FRunLen[Index + 2];
  end;
  Dec(FStackSize);

  // Where the first item of run 2 goes in run 1: the items before it are in place
  const SkippedCount = GallopRight(FItems[Base2], FItems, Base1, Len1, 0);
  Inc(Base1, SkippedCount);
  Dec(Len1, SkippedCount);
  if Len1 = 0 then
  begin
    Exit;
  end;

  // Where the last item of run 1 goes in run 2: the items after it are in place
  Len2 := GallopLeft(FItems[Base1 + Len1 - 1], FItems, Base2, Len2, Len2 - 1);
  if Len2 = 0 then
  begin
    Exit;
  end;

  if Len1 <= Len2 then
  begin
    MergeLo(Base1, Len1, Base2, Len2);
  end
  else
  begin
    MergeHi(Base1, Len1, Base2, Len2);
  end;
end;

procedure TTimSort.EnsureCapacity(const MinCapacity: Integer);
begin
  if Length(FTmp) < MinCapacity then
  begin
    // The smallest power of two above the capacity, but not above half of the items
    var NewSize := 1;
    while (NewSize <= MinCapacity) and (NewSize > 0) do
    begin
      NewSize := NewSize shl 1;
    end;
    if (NewSize <= 0) or (NewSize > Length(FItems) shr 1) then
    begin
      NewSize := Length(FItems) shr 1;
    end;
    if NewSize < MinCapacity then
    begin
      NewSize := MinCapacity;
    end;
    SetLength(FTmp, NewSize);
  end;
end;

procedure TTimSort.MergeLo(const Base1, Len1Start, Base2, Len2Start: Integer);
begin
  var Len1 := Len1Start;
  var Len2 := Len2Start;

  // The first run goes into the temporary array
  EnsureCapacity(Len1);
  var Cursor1 := 0;
  var Cursor2 := Base2;
  var Dest := Base1;
  Copy(FItems, Base1, FTmp, 0, Len1);

  // The first item of the second run moves, and the degenerate cases end here
  FItems[Dest] := FItems[Cursor2];
  Inc(Dest);
  Inc(Cursor2);
  Dec(Len2);
  if Len2 = 0 then
  begin
    Copy(FTmp, Cursor1, FItems, Dest, Len1);
    Exit;
  end;
  if Len1 = 1 then
  begin
    Copy(FItems, Cursor2, FItems, Dest, Len2);
    FItems[Dest + Len2] := FTmp[Cursor1];
    Exit;
  end;

  var MinGallop := FMinGallop;
  var Finished := False;
  while not Finished do
  begin
    var Count1 := 0;
    var Count2 := 0;

    // The straightforward way, until a run starts to win consistently
    repeat
      if FComparison(FItems[Cursor2], FTmp[Cursor1]) < 0 then
      begin
        FItems[Dest] := FItems[Cursor2];
        Inc(Dest);
        Inc(Cursor2);
        Inc(Count2);
        Count1 := 0;
        Dec(Len2);
        if Len2 = 0 then
        begin
          Finished := True;
          Break;
        end;
      end
      else
      begin
        FItems[Dest] := FTmp[Cursor1];
        Inc(Dest);
        Inc(Cursor1);
        Inc(Count1);
        Count2 := 0;
        Dec(Len1);
        if Len1 = 1 then
        begin
          Finished := True;
          Break;
        end;
      end;
    until (Count1 or Count2) >= MinGallop;
    if Finished then
    begin
      Break;
    end;

    // One run wins so consistently that galloping may pay: continue until neither wins consistently any more
    repeat
      Count1 := GallopRight(FItems[Cursor2], FTmp, Cursor1, Len1, 0);
      if Count1 <> 0 then
      begin
        Copy(FTmp, Cursor1, FItems, Dest, Count1);
        Inc(Dest, Count1);
        Inc(Cursor1, Count1);
        Dec(Len1, Count1);
        if Len1 <= 1 then
        begin
          Finished := True;
          Break;
        end;
      end;
      FItems[Dest] := FItems[Cursor2];
      Inc(Dest);
      Inc(Cursor2);
      Dec(Len2);
      if Len2 = 0 then
      begin
        Finished := True;
        Break;
      end;

      Count2 := GallopLeft(FTmp[Cursor1], FItems, Cursor2, Len2, 0);
      if Count2 <> 0 then
      begin
        Copy(FItems, Cursor2, FItems, Dest, Count2);
        Inc(Dest, Count2);
        Inc(Cursor2, Count2);
        Dec(Len2, Count2);
        if Len2 = 0 then
        begin
          Finished := True;
          Break;
        end;
      end;
      FItems[Dest] := FTmp[Cursor1];
      Inc(Dest);
      Inc(Cursor1);
      Dec(Len1);
      if Len1 = 1 then
      begin
        Finished := True;
        Break;
      end;
      Dec(MinGallop);
    until not ((Count1 >= MinGallopStart) or (Count2 >= MinGallopStart));
    if Finished then
    begin
      Break;
    end;

    if MinGallop < 0 then
    begin
      MinGallop := 0;
    end;
    // Penalty for leaving the gallop mode
    Inc(MinGallop, 2);
  end;

  if MinGallop < 1 then
  begin
    FMinGallop := 1;
  end
  else
  begin
    FMinGallop := MinGallop;
  end;

  if Len1 = 1 then
  begin
    Copy(FItems, Cursor2, FItems, Dest, Len2);
    FItems[Dest + Len2] := FTmp[Cursor1];
  end
  else if Len1 = 0 then
  begin
    RaiseContractViolation;
  end
  else
  begin
    Copy(FTmp, Cursor1, FItems, Dest, Len1);
  end;
end;

procedure TTimSort.MergeHi(const Base1, Len1Start, Base2, Len2Start: Integer);
begin
  var Len1 := Len1Start;
  var Len2 := Len2Start;

  // The second run goes into the temporary array
  EnsureCapacity(Len2);
  Copy(FItems, Base2, FTmp, 0, Len2);

  var Cursor1 := Base1 + Len1 - 1;
  var Cursor2 := Len2 - 1;
  var Dest := Base2 + Len2 - 1;

  // The last item of the first run moves, and the degenerate cases end here
  FItems[Dest] := FItems[Cursor1];
  Dec(Dest);
  Dec(Cursor1);
  Dec(Len1);
  if Len1 = 0 then
  begin
    Copy(FTmp, 0, FItems, Dest - (Len2 - 1), Len2);
    Exit;
  end;
  if Len2 = 1 then
  begin
    Dec(Dest, Len1);
    Dec(Cursor1, Len1);
    Copy(FItems, Cursor1 + 1, FItems, Dest + 1, Len1);
    FItems[Dest] := FTmp[Cursor2];
    Exit;
  end;

  var MinGallop := FMinGallop;
  var Finished := False;
  while not Finished do
  begin
    var Count1 := 0;
    var Count2 := 0;

    repeat
      if FComparison(FTmp[Cursor2], FItems[Cursor1]) < 0 then
      begin
        FItems[Dest] := FItems[Cursor1];
        Dec(Dest);
        Dec(Cursor1);
        Inc(Count1);
        Count2 := 0;
        Dec(Len1);
        if Len1 = 0 then
        begin
          Finished := True;
          Break;
        end;
      end
      else
      begin
        FItems[Dest] := FTmp[Cursor2];
        Dec(Dest);
        Dec(Cursor2);
        Inc(Count2);
        Count1 := 0;
        Dec(Len2);
        if Len2 = 1 then
        begin
          Finished := True;
          Break;
        end;
      end;
    until (Count1 or Count2) >= MinGallop;
    if Finished then
    begin
      Break;
    end;

    repeat
      Count1 := Len1 - GallopRight(FTmp[Cursor2], FItems, Base1, Len1, Len1 - 1);
      if Count1 <> 0 then
      begin
        Dec(Dest, Count1);
        Dec(Cursor1, Count1);
        Dec(Len1, Count1);
        Copy(FItems, Cursor1 + 1, FItems, Dest + 1, Count1);
        if Len1 = 0 then
        begin
          Finished := True;
          Break;
        end;
      end;
      FItems[Dest] := FTmp[Cursor2];
      Dec(Dest);
      Dec(Cursor2);
      Dec(Len2);
      if Len2 = 1 then
      begin
        Finished := True;
        Break;
      end;

      Count2 := Len2 - GallopLeft(FItems[Cursor1], FTmp, 0, Len2, Len2 - 1);
      if Count2 <> 0 then
      begin
        Dec(Dest, Count2);
        Dec(Cursor2, Count2);
        Dec(Len2, Count2);
        Copy(FTmp, Cursor2 + 1, FItems, Dest + 1, Count2);
        if Len2 <= 1 then
        begin
          Finished := True;
          Break;
        end;
      end;
      FItems[Dest] := FItems[Cursor1];
      Dec(Dest);
      Dec(Cursor1);
      Dec(Len1);
      if Len1 = 0 then
      begin
        Finished := True;
        Break;
      end;
      Dec(MinGallop);
    until not ((Count1 >= MinGallopStart) or (Count2 >= MinGallopStart));
    if Finished then
    begin
      Break;
    end;

    if MinGallop < 0 then
    begin
      MinGallop := 0;
    end;
    Inc(MinGallop, 2);
  end;

  if MinGallop < 1 then
  begin
    FMinGallop := 1;
  end
  else
  begin
    FMinGallop := MinGallop;
  end;

  if Len2 = 1 then
  begin
    Dec(Dest, Len1);
    Dec(Cursor1, Len1);
    Copy(FItems, Cursor1 + 1, FItems, Dest + 1, Len1);
    FItems[Dest] := FTmp[Cursor2];
  end
  else if Len2 = 0 then
  begin
    RaiseContractViolation;
  end
  else
  begin
    Copy(FTmp, 0, FItems, Dest - (Len2 - 1), Len2);
  end;
end;

end.
