// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.TextMatcher.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  DUnitX.TestFramework,
  Pdf4D.Viewer.TextMatcher;

type
  [TestFixture]
  TPdfTextMatcherTests = class
  private
    class function Describe(const Matches: TArray<TPdfTextMatch>): string; static;

  public
    [Test]
    procedure TestCaseInsensitiveByDefault;
    [Test]
    procedure TestMatchCaseRespectsCase;
    [Test]
    procedure TestWhitespaceInQueryMatchesAnyRun;
    [Test]
    procedure TestQueryIsTrimmedAndCollapsed;
    [Test]
    procedure TestNonOverlapping;
    [Test]
    [TestCase('Empty', '')]
    [TestCase('Blanks', '   ')]
    procedure TestEmptyQueryFindsNothing(const Query: string);
    [Test]
    procedure TestSurrogatePairs;
    [Test]
    procedure TestMultipleMatches;
    [Test]
    procedure TestMatchEndingAtEndOfText;
    [Test]
    procedure TestQueryLongerThanText;
    [Test]
    procedure TestNonBreakingSpaceAndTabCountAsWhitespace;
    [Test]
    procedure TestQueryWithoutSpaceDoesNotSpanWhitespace;
    [Test]
    procedure TestCaseFoldingIgnoresTurkishDottedI;
    [Test]
    procedure TestCaseFoldingOfNonAsciiLetters;
  end;

implementation

uses
  System.SysUtils;

{ TPdfTextMatcherTests }

class function TPdfTextMatcherTests.Describe(const Matches: TArray<TPdfTextMatch>): string;
begin
  Result := '';
  for var Match in Matches do
  begin
    Result := Result + Format('(%d,%d)', [Match.Start, Match.Length]);
  end;
end;

procedure TPdfTextMatcherTests.TestCaseInsensitiveByDefault;
begin
  const Matches = TPdfTextMatcher.FindAll('Factuur 2024-0815', 'factuur', False);

  Assert.AreEqual('(1,7)', Describe(Matches));
end;

procedure TPdfTextMatcherTests.TestMatchCaseRespectsCase;
begin
  const Matches = TPdfTextMatcher.FindAll('Factuur 2024-0815', 'factuur', True);

  Assert.AreEqual('', Describe(Matches));
end;

procedure TPdfTextMatcherTests.TestWhitespaceInQueryMatchesAnyRun;
begin
  const Matches = TPdfTextMatcher.FindAll('Bedrag'#13#10#$20AC' 12,50', 'bedrag '#$20AC' 12', False);

  Assert.AreEqual('(1,12)', Describe(Matches));
end;

procedure TPdfTextMatcherTests.TestQueryIsTrimmedAndCollapsed;
begin
  const Matches = TPdfTextMatcher.FindAll('2024 0815', '  2024   0815 ', False);

  Assert.AreEqual('(1,9)', Describe(Matches));
end;

procedure TPdfTextMatcherTests.TestNonOverlapping;
begin
  const Matches = TPdfTextMatcher.FindAll('aaa', 'aa', False);

  Assert.AreEqual('(1,2)', Describe(Matches));
end;

procedure TPdfTextMatcherTests.TestEmptyQueryFindsNothing(const Query: string);
begin
  const Matches = TPdfTextMatcher.FindAll('some text', Query, False);

  Assert.AreEqual('', Describe(Matches));
end;

procedure TPdfTextMatcherTests.TestSurrogatePairs;
begin
  const Emoji = #$D83D#$DE00;
  const Text = 'ab ' + Emoji + ' cd';

  const Matches = TPdfTextMatcher.FindAll(Text, 'b ' + Emoji + ' c', False);

  Assert.AreEqual('(2,6)', Describe(Matches));
  Assert.AreEqual('(4,2)', Describe(TPdfTextMatcher.FindAll(Text, Emoji, False)));
end;

procedure TPdfTextMatcherTests.TestMultipleMatches;
begin
  const Matches = TPdfTextMatcher.FindAll('one two one', 'ONE', False);

  Assert.AreEqual('(1,3)(9,3)', Describe(Matches));
end;

procedure TPdfTextMatcherTests.TestMatchEndingAtEndOfText;
begin
  const Matches = TPdfTextMatcher.FindAll('total 5', 'total 5', True);

  Assert.AreEqual('(1,7)', Describe(Matches));
end;

procedure TPdfTextMatcherTests.TestQueryLongerThanText;
begin
  const Matches = TPdfTextMatcher.FindAll('ab', 'abc', False);

  Assert.AreEqual('', Describe(Matches));
end;

procedure TPdfTextMatcherTests.TestNonBreakingSpaceAndTabCountAsWhitespace;
begin
  const Matches = TPdfTextMatcher.FindAll('a'#$00A0#9' b', 'a b', False);

  Assert.AreEqual('(1,5)', Describe(Matches));
end;

procedure TPdfTextMatcherTests.TestQueryWithoutSpaceDoesNotSpanWhitespace;
begin
  const Matches = TPdfTextMatcher.FindAll('a b', 'ab', False);

  Assert.AreEqual('', Describe(Matches));
end;

procedure TPdfTextMatcherTests.TestCaseFoldingIgnoresTurkishDottedI;
begin
  // The fold is invariant: i and I match each other and the dotted capital I (U+0130) is a different letter, as it would be in a
  // Turkish locale only (where i would fold to U+0130). The result must not depend on the locale of the user.
  Assert.AreEqual('(1,1)', Describe(TPdfTextMatcher.FindAll('I', 'i', False)));
  Assert.AreEqual('(1,1)', Describe(TPdfTextMatcher.FindAll('i', 'I', False)));
  Assert.AreEqual('', Describe(TPdfTextMatcher.FindAll(#$0130, 'i', False)));
  Assert.AreEqual('', Describe(TPdfTextMatcher.FindAll('i', #$0130, False)));
  Assert.AreEqual('(1,1)', Describe(TPdfTextMatcher.FindAll(#$0130, #$0130, False)));
end;

procedure TPdfTextMatcherTests.TestCaseFoldingOfNonAsciiLetters;
begin
  Assert.AreEqual('(1,4)', Describe(TPdfTextMatcher.FindAll('Caf'#$00E9' bar', 'CAF'#$00C9, False)));
  Assert.AreEqual('(1,5)', Describe(TPdfTextMatcher.FindAll(#$0394#$03B5#$03BB#$03C4#$03B1, #$03B4#$0395#$039B#$03A4#$0391, False)));
  Assert.AreEqual('', Describe(TPdfTextMatcher.FindAll(#$00E9, #$00C9, True)));
end;

end.
