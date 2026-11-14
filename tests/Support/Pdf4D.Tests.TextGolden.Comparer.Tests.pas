// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.TextGolden.Comparer.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextGoldenComparerTests = class
  public
    [Test]
    procedure TestExactMatch;

    [Test]
    procedure TestWhitespaceOnlyDifferenceIsLenientPass;

    [Test]
    procedure TestMissingWordSpaceIsDifference;

    [Test]
    procedure TestDifferenceNamesSectionAndLineNumber;

    [Test]
    procedure TestKnownSectionSkipped;

    [Test]
    procedure TestKnownEntryMatchesTheWholeHeading;

    [Test]
    procedure TestPlatformQualifiedEntryOnlyOnThatPlatform;

    [Test]
    procedure TestMissingSectionIsDifference;

    [Test]
    procedure TestExtraSectionIsDifference;

    [Test]
    procedure TestSectionOrderIsCompared;

    [Test]
    procedure TestBlankLinesAndIndentationAreLenient;

    [Test]
    procedure TestEscapesAreUndone;

    [Test]
    procedure TestNoBreakSpaceIsData;

    [Test]
    procedure TestTrailingEscapedSpaceIsLenient;

    [Test]
    procedure TestErrorLineMustMatch;

    [Test]
    procedure TestLoadErrorLineIsCompared;

    [Test]
    procedure TestCommentsAndEmptyLinesOfKnownDifferencesAreIgnored;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Pdf4D.Tests.TextGolden;

const
  LineFeed = #10;
  Heading = 'text: default page 1';

function CountOf(const Items: TArray<string>): Integer;
begin
  Result := Length(Items);
end;

function Section(const Name: string; const Lines: array of string): string;
begin
  Result := Name + LineFeed;
  for var Line in Lines do
  begin
    Result := Result + Line + LineFeed;
  end;
end;

{ TTextGoldenComparerTests }

procedure TTextGoldenComparerTests.TestExactMatch;
begin
  const Text = Section(Heading, ['| a b', '|', '| c']);
  const Comparison = TTextGoldenComparer.Compare(Text, Text, nil, 'Win64');
  Assert.AreEqual(0, CountOf(Comparison.Differences));
  Assert.AreEqual(0, Comparison.LenientSections);
end;

procedure TTextGoldenComparerTests.TestWhitespaceOnlyDifferenceIsLenientPass;
begin
  const Comparison = TTextGoldenComparer.Compare('| a  b', '| a b', nil, 'Win64');
  Assert.AreEqual(0, CountOf(Comparison.Differences));
  Assert.AreEqual(1, Comparison.LenientSections);
end;

procedure TTextGoldenComparerTests.TestMissingWordSpaceIsDifference;
begin
  const Comparison = TTextGoldenComparer.Compare('| ab', '| a b', nil, 'Win64');
  Assert.AreEqual(1, CountOf(Comparison.Differences));
  Assert.AreEqual(0, Comparison.LenientSections);
end;

procedure TTextGoldenComparerTests.TestDifferenceNamesSectionAndLineNumber;
begin
  const Expected = Section(Heading, ['| one', '| two']);
  const Actual = Section(Heading, ['| one', '| tow']);
  const Comparison = TTextGoldenComparer.Compare(Expected, Actual, nil, 'Win64');
  Assert.AreEqual(1, CountOf(Comparison.Differences));
  Assert.Contains(Comparison.Differences[0], Heading);
  Assert.Contains(Comparison.Differences[0], 'line 2');
end;

procedure TTextGoldenComparerTests.TestKnownSectionSkipped;
begin
  const Expected = Section(Heading, ['| a']);
  const Actual = Section(Heading, ['| b']);
  const Comparison = TTextGoldenComparer.Compare(Expected, Actual, [Heading + ' # reason'], 'Win64');
  Assert.AreEqual(0, CountOf(Comparison.Differences));
end;

procedure TTextGoldenComparerTests.TestKnownEntryMatchesTheWholeHeading;
begin
  const Expected = Section('text: default page 10', ['| a']);
  const Actual = Section('text: default page 10', ['| b']);
  const Comparison = TTextGoldenComparer.Compare(Expected, Actual, ['text: default page 1 # reason'], 'Win64');
  Assert.AreEqual(1, CountOf(Comparison.Differences));
end;

procedure TTextGoldenComparerTests.TestPlatformQualifiedEntryOnlyOnThatPlatform;
begin
  const Known: TArray<string> = ['text: sorted page 2 [Win32] # x'];
  const Expected = Section('text: sorted page 2', ['| a']);
  const Actual = Section('text: sorted page 2', ['| b']);
  Assert.AreEqual(0, CountOf(TTextGoldenComparer.Compare(Expected, Actual, Known, 'Win32').Differences));
  Assert.AreEqual(1, CountOf(TTextGoldenComparer.Compare(Expected, Actual, Known, 'Win64').Differences));
end;

procedure TTextGoldenComparerTests.TestMissingSectionIsDifference;
begin
  const Expected = Section('text: default page 1', ['| a']) + Section('text: default page 2', ['| b']);
  const Actual = Section('text: default page 1', ['| a']);
  const Comparison = TTextGoldenComparer.Compare(Expected, Actual, nil, 'Win64');
  Assert.AreEqual(1, CountOf(Comparison.Differences));
  Assert.Contains(Comparison.Differences[0], 'text: default page 2');
end;

procedure TTextGoldenComparerTests.TestExtraSectionIsDifference;
begin
  const Expected = Section('text: default page 1', ['| a']);
  const Actual = Expected + Section('text: default page 2', ['| b']);
  const Comparison = TTextGoldenComparer.Compare(Expected, Actual, nil, 'Win64');
  Assert.AreEqual(1, CountOf(Comparison.Differences));
end;

procedure TTextGoldenComparerTests.TestSectionOrderIsCompared;
begin
  const Expected = Section('text: default page 1', ['| a']) + Section('text: default page 2', ['| b']);
  const Actual = Section('text: default page 2', ['| b']) + Section('text: default page 1', ['| a']);
  Assert.AreEqual(1, CountOf(TTextGoldenComparer.Compare(Expected, Actual, nil, 'Win64').Differences));
end;

procedure TTextGoldenComparerTests.TestBlankLinesAndIndentationAreLenient;
begin
  const Expected = Section(Heading, ['| a', '|', '|', '| b']);
  const Actual = Section(Heading, ['|   a', '| b', '|']);
  const Comparison = TTextGoldenComparer.Compare(Expected, Actual, nil, 'Win64');
  Assert.AreEqual(0, CountOf(Comparison.Differences));
  Assert.AreEqual(1, Comparison.LenientSections);
end;

procedure TTextGoldenComparerTests.TestEscapesAreUndone;
begin
  // A TAB written as \t and a space are the same after collapsing; \x41 is the letter A
  const Comparison = TTextGoldenComparer.Compare('| a\tb \x41', '| a b A', nil, 'Win64');
  Assert.AreEqual(0, CountOf(Comparison.Differences));
  Assert.AreEqual(1, Comparison.LenientSections);
end;

procedure TTextGoldenComparerTests.TestNoBreakSpaceIsData;
begin
  const Comparison = TTextGoldenComparer.Compare('| a' + #$00A0 + 'b', '| a b', nil, 'Win64');
  Assert.AreEqual(1, CountOf(Comparison.Differences));
end;

procedure TTextGoldenComparerTests.TestTrailingEscapedSpaceIsLenient;
begin
  const Comparison = TTextGoldenComparer.Compare('| a\x20', '| a', nil, 'Win64');
  Assert.AreEqual(0, CountOf(Comparison.Differences));
  Assert.AreEqual(1, Comparison.LenientSections);
end;

procedure TTextGoldenComparerTests.TestErrorLineMustMatch;
begin
  const Expected = Section(Heading, ['error']);
  const Actual = Section(Heading, ['| text']);
  Assert.AreEqual(1, CountOf(TTextGoldenComparer.Compare(Expected, Actual, nil, 'Win64').Differences));
  Assert.AreEqual(0, CountOf(TTextGoldenComparer.Compare(Expected, Expected, nil, 'Win64').Differences));
end;

procedure TTextGoldenComparerTests.TestLoadErrorLineIsCompared;
begin
  Assert.AreEqual(0, CountOf(TTextGoldenComparer.Compare('load-error: parse' + LineFeed, 'load-error: parse' + LineFeed, nil, 'Win64').Differences));
  Assert.AreEqual(1, CountOf(TTextGoldenComparer.Compare('load-error: parse' + LineFeed, 'load-error: wrong-password' + LineFeed, nil, 'Win64').Differences));
  // The timeout marker is never produced by Pdf4D, so it can only be a known difference or a failure
  Assert.IsTrue(CountOf(TTextGoldenComparer.Compare('load-error: timeout' + LineFeed, Section(Heading, []), nil, 'Win64').Differences) > 0);
end;

procedure TTextGoldenComparerTests.TestCommentsAndEmptyLinesOfKnownDifferencesAreIgnored;
begin
  const FileName = TPath.Combine(TPath.GetTempPath, 'pdf4d-text-known.txt');
  TFile.WriteAllText(FileName, '# comment' + LineFeed + LineFeed + Heading + ' # reason' + LineFeed, TEncoding.UTF8);
  try
    const Entries = TTextGoldenComparer.LoadKnownDifferences(FileName);
    Assert.AreEqual(1, CountOf(Entries));
  finally
    TFile.Delete(FileName);
  end;
  Assert.AreEqual(0, CountOf(TTextGoldenComparer.LoadKnownDifferences(FileName)));
end;

end.
