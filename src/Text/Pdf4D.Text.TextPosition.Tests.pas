// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Tests for Pdf4D.Text.TextPosition, Pdf4D.Text.TextPositionComparator and Pdf4D.Text.IterativeMergeSort
unit Pdf4D.Text.TextPosition.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Common.Matrix,
  Pdf4D.Text.TextPosition;

type
  TKeyedItem = record
    Key: Integer;
    Sequence: Integer;
  end;

  [TestFixture]
  TTextPositionTests = class
  private
    FPositions: TObjectList<TTextPosition>;

    function NewPosition(const Unicode: string; const X, Y, Width: Single): TTextPosition;
    function NewMatrixPosition(const Unicode: string; const Matrix: TPdfMatrix): TTextPosition;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestXAndYAreInDisplayUnitsFromTheUpperLeft;

    [Test]
    procedure TestWidthFollowsEndX;

    [Test]
    [TestCase('Right', '12,0,0,12,0')]
    [TestCase('Up', '0,12,-12,0,90')]
    [TestCase('UpsideDown', '-12,0,0,-12,180')]
    [TestCase('Down', '0,-12,12,0,270')]
    procedure TestDirection(const A, B, C, D, Expected: Single);

    [Test]
    procedure TestDiacriticMerge;

    [Test]
    procedure TestDiacriticMergeBehindBaseCharacterWhenItDoesNotOverlap;

    [Test]
    procedure TestDiacriticTableCharacterUsesCombiningMark;

    [Test]
    [TestCase('Acute', '180,True')]
    [TestCase('Letter', '101,False')]
    [TestCase('ProlongedSoundMark', '12540,False')]
    procedure TestIsDiacritic(const CodePoint: Integer; const Expected: Boolean);

    [Test]
    procedure TestContainsNeedsMoreThanFifteenPercentOverlap;

    [Test]
    procedure TestCompletelyContains;

    [Test]
    procedure TestEqualsIgnoresUnicode;

    [Test]
    procedure TestJavaFloatCompare;

    [Test]
    procedure TestJavaFloatToIntSaturates;

    [Test]
    procedure TestComparatorSortsByLineThenX;

    [Test]
    procedure TestComparatorGroupsByDirection;

    [Test]
    procedure TestMergeSortIsStable;

    [Test]
    procedure TestMergeSortWithInconsistentComparatorKeepsEveryItem;

    [Test]
    procedure TestMergeSortLeavesListAloneWhenComparisonRaises;

    [Test]
    procedure TestMergeSortDoesNotFreeOwnedItems;
  end;

implementation

uses
  Pdf4D.Text.IterativeMergeSort,
  Pdf4D.Text.TextPositionComparator;

const
  PageWidth = 612;
  PageHeight = 792;
  Tolerance = 0.001;
  CharHeight = 10;

{ TTextPositionTests }

procedure TTextPositionTests.Setup;
begin
  FPositions := TObjectList<TTextPosition>.Create(True);
end;

procedure TTextPositionTests.TearDown;
begin
  FreeAndNil(FPositions);
end;

function TTextPositionTests.NewMatrixPosition(const Unicode: string; const Matrix: TPdfMatrix): TTextPosition;
begin
  Result := TTextPosition.Create(0, PageWidth, PageHeight, Matrix, Matrix.TranslateX + 6, Matrix.TranslateY, CharHeight, 6, 3, Unicode,
                                 [Ord(Unicode[1])], nil, 12, 12);
  FPositions.Add(Result);
end;

function TTextPositionTests.NewPosition(const Unicode: string; const X, Y, Width: Single): TTextPosition;
begin
  Result := TTextPosition.Create(0, PageWidth, PageHeight, TPdfMatrix.Create(12, 0, 0, 12, X, Y), X + Width, Y, CharHeight, Width, 3, Unicode,
                                 [Ord(Unicode[1])], nil, 12, 12);
  FPositions.Add(Result);
end;

procedure TTextPositionTests.TestXAndYAreInDisplayUnitsFromTheUpperLeft;
begin
  const Position = NewPosition('A', 100, 700, 6);

  Assert.AreEqual(Double(100), Double(Position.X), Tolerance);
  Assert.AreEqual(Double(92), Double(Position.Y), Tolerance);
  Assert.AreEqual(Double(100), Double(Position.XDirAdj), Tolerance);
  Assert.AreEqual(Double(92), Double(Position.YDirAdj), Tolerance);
  Assert.AreEqual(Double(12), Double(Position.XScale), Tolerance);
end;

procedure TTextPositionTests.TestWidthFollowsEndX;
begin
  const Position = NewPosition('A', 100, 700, 6.5);

  Assert.AreEqual(Double(6.5), Double(Position.Width), Tolerance);
  Assert.AreEqual(Double(6.5), Double(Position.WidthDirAdj), Tolerance);
  Assert.AreEqual<Integer>(1, Length(Position.IndividualWidths));
end;

procedure TTextPositionTests.TestDirection(const A, B, C, D, Expected: Single);
begin
  const Position = NewMatrixPosition('A', TPdfMatrix.Create(A, B, C, D, 300, 300));

  Assert.AreEqual(Double(Expected), Double(Position.Dir), Tolerance);
end;

procedure TTextPositionTests.TestDiacriticMerge;
begin
  const Base = NewPosition('e', 100, 700, 6);
  const Diacritic = NewPosition(#$00B4, 101, 700, 3);

  Assert.IsTrue(Base.Contains(Diacritic));
  Base.MergeDiacritic(Diacritic);

  Assert.AreEqual('e'#$0301, Base.Unicode);
  Assert.AreEqual<Integer>(2, Length(Base.IndividualWidths));
  Assert.AreEqual(Double(0), Double(Base.IndividualWidths[1]), Tolerance);
end;

procedure TTextPositionTests.TestDiacriticMergeBehindBaseCharacterWhenItDoesNotOverlap;
begin
  const Base = NewPosition('e', 100, 700, 6);
  const Diacritic = NewPosition(#$00B4, 110, 700, 3);

  Base.MergeDiacritic(Diacritic);

  Assert.AreEqual('e'#$0301, Base.Unicode);
end;

procedure TTextPositionTests.TestDiacriticTableCharacterUsesCombiningMark;
begin
  const Base = NewPosition('o', 100, 700, 6);
  const Diacritic = NewPosition('^', 101, 700, 3);

  Base.MergeDiacritic(Diacritic);

  Assert.AreEqual('o'#$0302, Base.Unicode);
end;

procedure TTextPositionTests.TestIsDiacritic(const CodePoint: Integer; const Expected: Boolean);
begin
  Assert.AreEqual(Expected, NewPosition(Char(CodePoint), 0, 0, 1).IsDiacritic);
end;

procedure TTextPositionTests.TestContainsNeedsMoreThanFifteenPercentOverlap;
begin
  const Position = NewPosition('A', 100, 700, 10);

  Assert.IsTrue(Position.Contains(NewPosition('B', 105, 700, 10)), 'half of the width');
  Assert.IsFalse(Position.Contains(NewPosition('B', 109, 700, 10)), 'a tenth of the width');
  Assert.IsFalse(Position.Contains(NewPosition('B', 120, 700, 10)), 'no overlap');
  Assert.IsFalse(Position.Contains(NewPosition('B', 100, 600, 10)), 'another line');
end;

procedure TTextPositionTests.TestCompletelyContains;
begin
  const Outer = NewPosition('A', 100, 700, 10);

  Assert.IsTrue(Outer.CompletelyContains(NewPosition('B', 102, 700, 5)));
  Assert.IsFalse(Outer.CompletelyContains(NewPosition('B', 105, 700, 10)));
end;

procedure TTextPositionTests.TestEqualsIgnoresUnicode;
begin
  const First = NewPosition('A', 100, 700, 10);
  const Second = NewPosition('A', 100, 700, 10);
  Second.SetUnicode('B');

  Assert.IsTrue(First.Equals(Second), 'only the fixed fields are compared');
  Assert.IsFalse(First.Equals(NewPosition('A', 101, 700, 10)));
  Assert.IsFalse(First.Equals(nil));
end;

procedure TTextPositionTests.TestJavaFloatCompare;
begin
  const Zero: Single = 0;
  const NegativeZero: Single = -Zero;
  Assert.AreEqual<Integer>(-1, TJavaFloat.Compare(NegativeZero, Zero));
  Assert.AreEqual<Integer>(1, TJavaFloat.Compare(Zero, NegativeZero));
  Assert.AreEqual<Integer>(0, TJavaFloat.Compare(Zero, Zero));
  Assert.AreEqual<Integer>(-1, TJavaFloat.Compare(1, 2));
  Assert.IsFalse(TJavaFloat.IsSame(NegativeZero, Zero));

  const NotANumber: Single = Single.NaN;
  Assert.AreEqual<Integer>(0, TJavaFloat.Compare(NotANumber, NotANumber));
  Assert.AreEqual<Integer>(1, TJavaFloat.Compare(NotANumber, 1));
  Assert.AreEqual<Integer>(-1, TJavaFloat.Compare(1, NotANumber));
end;

procedure TTextPositionTests.TestJavaFloatToIntSaturates;
begin
  Assert.AreEqual<Integer>(12, TJavaFloat.ToInt(12.9));
  Assert.AreEqual<Integer>(-12, TJavaFloat.ToInt(-12.9));
  Assert.AreEqual<Integer>(High(Integer), TJavaFloat.ToInt(1E20));
  Assert.AreEqual<Integer>(Low(Integer), TJavaFloat.ToInt(-1E20));
  Assert.AreEqual<Integer>(0, TJavaFloat.ToInt(Single.NaN));
end;

procedure TTextPositionTests.TestComparatorSortsByLineThenX;
begin
  const List = TList<TTextPosition>.Create;
  try
    // The second line (lower on the page) first, then the first line right to left
    List.Add(NewPosition('C', 50, 680, 6));
    List.Add(NewPosition('B', 200, 700, 6));
    List.Add(NewPosition('A', 100, 700.05, 6));

    TIterativeMergeSort.Sort<TTextPosition>(List, TTextPositionComparator.AsComparison());

    Assert.AreEqual('A', List[0].Unicode, 'the same line within 0.1');
    Assert.AreEqual('B', List[1].Unicode);
    Assert.AreEqual('C', List[2].Unicode);
  finally
    List.Free;
  end;
end;

procedure TTextPositionTests.TestComparatorGroupsByDirection;
begin
  const Horizontal = NewPosition('A', 100, 700, 6);
  const Rotated = NewMatrixPosition('B', TPdfMatrix.Create(0, 12, -12, 0, 50, 50));

  Assert.IsTrue(TTextPositionComparator.Compare(Horizontal, Rotated) < 0);
  Assert.IsTrue(TTextPositionComparator.Compare(Rotated, Horizontal) > 0);
end;

procedure TTextPositionTests.TestMergeSortIsStable;
begin
  const List = TList<TKeyedItem>.Create;
  try
    for var Index := 0 to 99 do
    begin
      var Item: TKeyedItem;
      Item.Key := (Index * 7) mod 3;
      Item.Sequence := Index;
      List.Add(Item);
    end;

    TIterativeMergeSort.Sort<TKeyedItem>(List,
      function(const Left, Right: TKeyedItem): Integer
      begin
        Result := Left.Key - Right.Key;
      end);

    for var Index := 1 to List.Count - 1 do
    begin
      Assert.IsTrue(List[Index - 1].Key <= List[Index].Key, 'sorted by key');
      if List[Index - 1].Key = List[Index].Key then
      begin
        Assert.IsTrue(List[Index - 1].Sequence < List[Index].Sequence, 'equal keys keep their order');
      end;
    end;
  finally
    List.Free;
  end;
end;

procedure TTextPositionTests.TestMergeSortWithInconsistentComparatorKeepsEveryItem;
begin
  const List = TList<Integer>.Create;
  try
    for var Index := 0 to 999 do
    begin
      List.Add(Index);
    end;

    var Seed := 12345;
    TIterativeMergeSort.Sort<Integer>(List,
      function(const Left, Right: Integer): Integer
      begin
        Seed := (Seed * 75 + 74) mod 65537;
        Result := (Seed mod 3) - 1;
      end);

    Assert.AreEqual<Integer>(1000, List.Count);
    List.Sort;
    for var Index := 0 to 999 do
    begin
      Assert.AreEqual<Integer>(Index, List[Index]);
    end;
  finally
    List.Free;
  end;
end;

procedure TTextPositionTests.TestMergeSortLeavesListAloneWhenComparisonRaises;
begin
  const List = TList<Integer>.Create;
  try
    List.AddRange([3, 1, 2]);

    Assert.WillRaise(
      procedure
      begin
        TIterativeMergeSort.Sort<Integer>(List,
          function(const Left, Right: Integer): Integer
          begin
            raise EInvalidOpException.Create('Comparison failed');
          end);
      end, EInvalidOpException);

    Assert.AreEqual<Integer>(3, List[0]);
    Assert.AreEqual<Integer>(1, List[1]);
    Assert.AreEqual<Integer>(2, List[2]);
  finally
    List.Free;
  end;
end;

procedure TTextPositionTests.TestMergeSortDoesNotFreeOwnedItems;
begin
  // A list that owns its items must not lose them when it is sorted: the leak check and the access to List[] would show it
  const Owned = TObjectList<TTextPosition>.Create(True);
  try
    Owned.Add(TTextPosition.Create(0, PageWidth, PageHeight, TPdfMatrix.Create(12, 0, 0, 12, 200, 700), 206, 700, CharHeight, 6, 3, 'B', [66], nil, 12, 12));
    Owned.Add(TTextPosition.Create(0, PageWidth, PageHeight, TPdfMatrix.Create(12, 0, 0, 12, 100, 700), 106, 700, CharHeight, 6, 3, 'A', [65], nil, 12, 12));

    TIterativeMergeSort.Sort<TTextPosition>(Owned, TTextPositionComparator.AsComparison());

    Assert.AreEqual('A', Owned[0].Unicode);
    Assert.AreEqual('B', Owned[1].Unicode);
  finally
    Owned.Free;
  end;
end;

end.
