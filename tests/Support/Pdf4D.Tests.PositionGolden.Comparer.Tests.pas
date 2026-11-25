// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.PositionGolden.Comparer.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPositionGoldenComparerTests = class
  strict private
    const
      Golden = 'page 1'#10'line: 10.00 20.00 30.00 20.00 5'#10'line: 10.00 8.00 25.50 8.00 3'#10'page 2'#10'line: 1.00 2.00 3.00 4.00 2'#10;
      Win64 = 'Win64';

  public
    [Test]
    procedure TestEqualTextHasNoDifference;

    [Test]
    procedure TestNumbersWithinTheToleranceAreEqual;

    [Test]
    procedure TestNumberBeyondTheToleranceIsDifference;

    [Test]
    procedure TestGlyphCountMustBeExact;

    [Test]
    procedure TestMissingLineIsDifference;

    [Test]
    procedure TestExtraPageIsDifference;

    [Test]
    procedure TestKnownPageIsSkipped;

    [Test]
    procedure TestPlatformEntryOnlyAppliesToThatPlatform;

    [Test]
    procedure TestLoadErrorMustMatch;

    [Test]
    procedure TestEmptyGoldenEqualsEmptyText;
  end;

implementation

uses
  System.SysUtils,
  Pdf4D.Tests.PositionGolden;

{ TPositionGoldenComparerTests }

procedure TPositionGoldenComparerTests.TestEqualTextHasNoDifference;
begin
  const Differences = TPositionGoldenComparer.Compare(Golden, Golden, nil, Win64);

  Assert.AreEqual<NativeInt>(0, Length(Differences));
end;

procedure TPositionGoldenComparerTests.TestNumbersWithinTheToleranceAreEqual;
begin
  const Actual = Golden.Replace('30.00 20.00 5', '30.02 19.98 5');

  const Differences = TPositionGoldenComparer.Compare(Golden, Actual, nil, Win64);

  Assert.AreEqual<NativeInt>(0, Length(Differences));
end;

procedure TPositionGoldenComparerTests.TestNumberBeyondTheToleranceIsDifference;
begin
  const Actual = Golden.Replace('30.00 20.00 5', '30.03 20.00 5');

  const Differences = TPositionGoldenComparer.Compare(Golden, Actual, nil, Win64);

  Assert.AreEqual<NativeInt>(1, Length(Differences));
  Assert.IsTrue(Differences[0].StartsWith('page 1, line 2:'), Differences[0]);
end;

procedure TPositionGoldenComparerTests.TestGlyphCountMustBeExact;
begin
  const Actual = Golden.Replace('20.00 5', '20.00 6');

  const Differences = TPositionGoldenComparer.Compare(Golden, Actual, nil, Win64);

  Assert.AreEqual<NativeInt>(1, Length(Differences));
end;

procedure TPositionGoldenComparerTests.TestMissingLineIsDifference;
begin
  const Actual = Golden.Replace('line: 10.00 8.00 25.50 8.00 3'#10, '');

  const Differences = TPositionGoldenComparer.Compare(Golden, Actual, nil, Win64);

  Assert.IsTrue(Length(Differences) > 0);
end;

procedure TPositionGoldenComparerTests.TestExtraPageIsDifference;
begin
  const Actual = Golden + 'page 3'#10;

  const Differences = TPositionGoldenComparer.Compare(Golden, Actual, nil, Win64);

  Assert.AreEqual<NativeInt>(1, Length(Differences));
  Assert.IsTrue(Differences[0].StartsWith('extra line'), Differences[0]);
end;

procedure TPositionGoldenComparerTests.TestKnownPageIsSkipped;
begin
  const Actual = Golden.Replace('1.00 2.00 3.00 4.00 2', '1.00 2.00 3.00 9.00 7');

  const Differences = TPositionGoldenComparer.Compare(Golden, Actual, ['2 # another order of the glyphs'], Win64);

  Assert.AreEqual<NativeInt>(0, Length(Differences));
end;

procedure TPositionGoldenComparerTests.TestPlatformEntryOnlyAppliesToThatPlatform;
begin
  const Actual = Golden.Replace('1.00 2.00 3.00 4.00 2', '1.00 2.00 3.00 9.00 7');
  const Known: TArray<string> = ['2 [Linux64] # differs on Linux64 only'];

  Assert.AreEqual<NativeInt>(0, Length(TPositionGoldenComparer.Compare(Golden, Actual, Known, 'Linux64')));
  Assert.AreEqual<NativeInt>(1, Length(TPositionGoldenComparer.Compare(Golden, Actual, Known, Win64)));
end;

procedure TPositionGoldenComparerTests.TestLoadErrorMustMatch;
begin
  const Differences = TPositionGoldenComparer.Compare('load-error: unsupported'#10, Golden, nil, Win64);

  Assert.IsTrue(Length(Differences) > 0);
end;

procedure TPositionGoldenComparerTests.TestEmptyGoldenEqualsEmptyText;
begin
  Assert.AreEqual<NativeInt>(0, Length(TPositionGoldenComparer.Compare('', '', nil, Win64)));
  Assert.IsTrue(Length(TPositionGoldenComparer.Compare('', Golden, nil, Win64)) > 0);
end;

end.
