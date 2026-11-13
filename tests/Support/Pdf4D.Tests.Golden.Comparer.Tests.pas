// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.Golden.Comparer.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TGoldenComparerTests = class
  public
    [Test]
    procedure TestEqualTextsHaveNoDifferences;

    [Test]
    procedure TestOutlineIndentationIsCompared;

    [Test]
    procedure TestInnerSpacesAreCompared;

    [Test]
    procedure TestCarriageReturnAndTrailingSpacesAreIgnored;

    [Test]
    procedure TestFloatToleranceOnNumbers;

    [Test]
    procedure TestIgnoreKeyWithIntegerAndReference;

    [Test]
    procedure TestIgnoreKeyWithNameKeepsTheOtherKeys;

    [Test]
    procedure TestIgnoreKeyDoesNotMatchLongerKeyName;

    [Test]
    procedure TestDuplicateObjectLineIsReported;
  end;

implementation

uses
  System.SysUtils,
  Pdf4D.Tests.Golden;

const
  LineFeed = #10;

{ TGoldenComparerTests }

procedure TGoldenComparerTests.TestEqualTextsHaveNoDifferences;
begin
  const Text = 'pages: 1' + LineFeed + 'outline: A -> 1' + LineFeed + 'outline:   B -> 1' + LineFeed;

  Assert.AreEqual<Integer>(0, Length(TGoldenComparer.Compare(Text, Text, nil)));
end;

procedure TGoldenComparerTests.TestOutlineIndentationIsCompared;
begin
  const Expected = 'outline: A -> 1' + LineFeed + 'outline:   B -> 1' + LineFeed;
  const Actual = 'outline: A -> 1' + LineFeed + 'outline: B -> 1' + LineFeed;

  Assert.AreEqual<Integer>(1, Length(TGoldenComparer.Compare(Expected, Actual, nil)));
end;

procedure TGoldenComparerTests.TestInnerSpacesAreCompared;
begin
  Assert.AreEqual<Integer>(1, Length(TGoldenComparer.Compare('info Title: a  b' + LineFeed, 'info Title: a b' + LineFeed, nil)));
end;

procedure TGoldenComparerTests.TestCarriageReturnAndTrailingSpacesAreIgnored;
begin
  Assert.AreEqual<Integer>(0, Length(TGoldenComparer.Compare('pages: 1' + LineFeed, 'pages: 1 ' + #13 + LineFeed, nil)));
end;

procedure TGoldenComparerTests.TestFloatToleranceOnNumbers;
begin
  const Expected = 'page 1: media=[0 0 595.2756 841.89]' + LineFeed;

  Assert.AreEqual<Integer>(0, Length(TGoldenComparer.Compare(Expected, 'page 1: media=[0 0 595.2757 841.89]' + LineFeed, nil)));
  Assert.AreEqual<Integer>(1, Length(TGoldenComparer.Compare(Expected, 'page 1: media=[0 0 595.3 841.89]' + LineFeed, nil)));
end;

procedure TGoldenComparerTests.TestIgnoreKeyWithIntegerAndReference;
begin
  const Known: TArray<string> = ['object 4 0: ignore-key /Length', 'object 4 0: ignore-key /Parent'];
  const Expected = 'object 4 0: <</Length 10 /Parent 2 0 R /X 1>> stream sha256=aa' + LineFeed;
  const Actual = 'object 4 0: <</Length 12 /Parent 3 0 R /X 1>> stream sha256=aa' + LineFeed;
  const OtherHash = 'object 4 0: <</Length 12 /Parent 3 0 R /X 1>> stream sha256=bb' + LineFeed;

  Assert.AreEqual<Integer>(0, Length(TGoldenComparer.Compare(Expected, Actual, Known)));
  Assert.AreEqual<Integer>(1, Length(TGoldenComparer.Compare(Expected, OtherHash, Known)));
end;

procedure TGoldenComparerTests.TestIgnoreKeyWithNameKeepsTheOtherKeys;
begin
  const Known: TArray<string> = ['object 3 0: ignore-key /Type'];
  const Expected = 'object 3 0: <</Count 2 /First 4 0 R /Last 5 0 R /Type /Outlines>>' + LineFeed;

  Assert.AreEqual<Integer>(0, Length(TGoldenComparer.Compare(Expected, 'object 3 0: <</Count 2 /First 4 0 R /Last 5 0 R>>' + LineFeed, Known)));
  Assert.AreEqual<Integer>(1, Length(TGoldenComparer.Compare(Expected, 'object 3 0: <</Count 3 /First 4 0 R /Last 5 0 R>>' + LineFeed, Known)));
  Assert.AreEqual<Integer>(1, Length(TGoldenComparer.Compare(Expected, 'object 3 0: <</Count 2 /First 4 0 R /Last 6 0 R>>' + LineFeed, Known)));
end;

procedure TGoldenComparerTests.TestIgnoreKeyDoesNotMatchLongerKeyName;
begin
  const Known: TArray<string> = ['object 3 0: ignore-key /Type'];
  const Expected = 'object 3 0: <</Subtype /Form /Type /XObject>>' + LineFeed;

  Assert.AreEqual<Integer>(1, Length(TGoldenComparer.Compare(Expected, 'object 3 0: <</Subtype /Image /Type /XObject>>' + LineFeed, Known)));
end;

procedure TGoldenComparerTests.TestDuplicateObjectLineIsReported;
begin
  const Expected = 'object 1 0: 5' + LineFeed;
  const Actual = 'object 1 0: 5' + LineFeed + 'object 1 0: 5' + LineFeed;

  Assert.AreEqual<Integer>(1, Length(TGoldenComparer.Compare(Expected, Actual, nil)));
end;

end.
