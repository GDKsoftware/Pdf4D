// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Text.PositionedText.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Text.PositionedText;

type
  [TestFixture]
  TPdfPositionedTextTests = class
  private
    FText: TPdfPositionedText;

    class function Box(const PageIndex, LineIndex: Integer; const Left: Single): TPdfGlyphBox; static;
    // 'ab', a line separator, 'cd': the glyphs a and b are on line 0, c and d on line 1, and c and d are on page SecondPage
    procedure CreateTwoLines(const SecondPage: Integer);

  public
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestLocateAcrossLinesGivesQuadPerLine;

    [Test]
    procedure TestLocateAcrossPagesGivesFragmentPerPage;

    [Test]
    procedure TestLocateOnlySeparatorsIsEmpty;

    [Test]
    procedure TestLocateEmptyRangeIsEmpty;

    [Test]
    procedure TestLocateTrimsSeparatorsAtBothEnds;

    [Test]
    [TestCase('StartZero', '0,1')]
    [TestCase('NegativeLength', '1,-1')]
    [TestCase('PastTheEnd', '4,3')]
    [TestCase('MaxInt', '2147483647,2147483647')]
    procedure TestLocateOutOfRangeRaises(const Start, Length: Integer);

    [Test]
    procedure TestGlyphOfCharOutOfRangeRaises;

    [Test]
    procedure TestLocateOfHugeQuadsDoesNotRaise;

    [Test]
    procedure TestLocateActualTextTakesAllGlyphsOfTheSequence;

    [Test]
    procedure TestLocateGlyphsInReverseOrderOfARunGiveQuadPerRun;

    [Test]
    procedure TestLocateRightToLeftGlyphsInLogicalOrderGiveOneQuad;

    [Test]
    procedure TestLocateRunDrawnLaterOnTheLeftDoesNotInvertTheQuad;

    [Test]
    procedure TestLocateActualTextSequenceAcrossPagesGivesNoTextOnThePageWithoutCharacters;

    [Test]
    procedure TestLocateWholeLargeTextWithActualTextIsFast;
  end;

implementation

uses
  System.Types,
  System.Diagnostics,
  Pdf4D.Common.Quad;

const
  Tolerance = 0.001;

{ TPdfPositionedTextTests }

class function TPdfPositionedTextTests.Box(const PageIndex, LineIndex: Integer; const Left: Single): TPdfGlyphBox;
begin
  Result.PageIndex := PageIndex;
  Result.LineIndex := LineIndex;
  Result.WordIndex := LineIndex;
  Result.WidthOfSpace := 3;
  Result.ActualTextSpan := 0;
  Result.Quad := TPdfQuad.Create(TPointF.Create(Left, 0), TPointF.Create(Left + 10, 0), TPointF.Create(Left + 10, 10), TPointF.Create(Left, 10));
end;

procedure TPdfPositionedTextTests.CreateTwoLines(const SecondPage: Integer);
begin
  const Glyphs: TArray<TPdfGlyphBox> = [Box(0, 0, 0), Box(0, 0, 10), Box(SecondPage, 1, 0), Box(SecondPage, 1, 10)];
  const CharToGlyph: TArray<Integer> = [0, 1, -1, 2, 3];

  FText := TPdfPositionedText.Create('ab'#10'cd', Glyphs, CharToGlyph);
end;

procedure TPdfPositionedTextTests.TearDown;
begin
  FreeAndNil(FText);
end;

procedure TPdfPositionedTextTests.TestLocateAcrossLinesGivesQuadPerLine;
begin
  CreateTwoLines(0);

  const Runs = FText.Locate(1, 5);

  Assert.AreEqual<Integer>(1, Length(Runs));
  Assert.AreEqual('ab'#10'cd', Runs[0].Text);
  Assert.AreEqual<Integer>(2, Length(Runs[0].Quads));
  Assert.AreEqual(Double(0), Double(Runs[0].Quads[0].P1.X), Tolerance);
  Assert.AreEqual(Double(20), Double(Runs[0].Quads[0].P2.X), Tolerance);
  Assert.AreEqual(Double(20), Double(Runs[0].Quads[1].P2.X), Tolerance);
end;

procedure TPdfPositionedTextTests.TestLocateAcrossPagesGivesFragmentPerPage;
begin
  CreateTwoLines(1);

  const Runs = FText.Locate(2, 3);

  Assert.AreEqual<Integer>(2, Length(Runs));
  Assert.AreEqual<Integer>(0, Runs[0].PageIndex);
  Assert.AreEqual('b', Runs[0].Text);
  Assert.AreEqual<Integer>(1, Runs[1].PageIndex);
  Assert.AreEqual('c', Runs[1].Text);
end;

procedure TPdfPositionedTextTests.TestLocateOnlySeparatorsIsEmpty;
begin
  CreateTwoLines(0);

  const Runs = FText.Locate(3, 1);

  Assert.AreEqual<Integer>(0, Length(Runs));
end;

procedure TPdfPositionedTextTests.TestLocateEmptyRangeIsEmpty;
begin
  CreateTwoLines(0);

  const Runs = FText.Locate(1, 0);

  Assert.AreEqual<Integer>(0, Length(Runs));
end;

procedure TPdfPositionedTextTests.TestLocateTrimsSeparatorsAtBothEnds;
begin
  CreateTwoLines(0);

  const Runs = FText.Locate(3, 2);

  Assert.AreEqual<Integer>(1, Length(Runs));
  Assert.AreEqual('c', Runs[0].Text);
  Assert.AreEqual<Integer>(1, Length(Runs[0].Quads));
end;

procedure TPdfPositionedTextTests.TestLocateOutOfRangeRaises(const Start, Length: Integer);
begin
  CreateTwoLines(0);

  Assert.WillRaise(
    procedure
    begin
      FText.Locate(Start, Length);
    end,
    EArgumentOutOfRangeException);
end;

procedure TPdfPositionedTextTests.TestGlyphOfCharOutOfRangeRaises;
begin
  CreateTwoLines(0);

  Assert.AreEqual<Integer>(-1, FText.GlyphOfChar(2));
  Assert.AreEqual<Integer>(2, FText.GlyphOfChar(3));
  Assert.WillRaise(
    procedure
    begin
      FText.GlyphOfChar(5);
    end,
    EArgumentOutOfRangeException);
end;

procedure TPdfPositionedTextTests.TestLocateOfHugeQuadsDoesNotRaise;
begin
  const Huge: Single = 1E30;
  var First := Box(0, 0, 0);
  var Second := Box(0, 0, 10);
  First.Quad := TPdfQuad.Create(TPointF.Create(0, 0), TPointF.Create(Huge, 0), TPointF.Create(Huge, Huge), TPointF.Create(0, Huge));
  Second.Quad := TPdfQuad.Create(TPointF.Create(Huge, 0), TPointF.Create(Huge, 0), TPointF.Create(Huge, Huge), TPointF.Create(Huge, Huge));
  FText := TPdfPositionedText.Create('ab', [First, Second], [0, 1]);
  var Runs: TArray<TPdfLocatedRun>;

  Assert.WillNotRaise(
    procedure
    begin
      Runs := FText.Locate(1, 2);
    end);

  Assert.AreEqual<Integer>(1, Length(Runs));
  Assert.AreEqual<Integer>(1, Length(Runs[0].Quads));
  Assert.IsTrue(Runs[0].Quads[0].IsFinite);
end;

procedure TPdfPositionedTextTests.TestLocateActualTextTakesAllGlyphsOfTheSequence;
begin
  var First := Box(0, 0, 0);
  var Second := Box(0, 0, 10);
  var Other := Box(0, 0, 20);
  First.ActualTextSpan := 1;
  Second.ActualTextSpan := 1;
  FText := TPdfPositionedText.Create('XYZ', [First, Second, Other], [0, 0, 2]);

  const Runs = FText.Locate(2, 1);

  Assert.AreEqual<Integer>(1, Length(Runs));
  Assert.AreEqual('Y', Runs[0].Text);
  Assert.AreEqual<Integer>(1, Length(Runs[0].Quads));
  Assert.AreEqual(Double(0), Double(Runs[0].Quads[0].P1.X), Tolerance);
  Assert.AreEqual(Double(20), Double(Runs[0].Quads[0].P2.X), Tolerance);
end;

procedure TPdfPositionedTextTests.TestLocateGlyphsInReverseOrderOfARunGiveQuadPerRun;
begin
  FText := TPdfPositionedText.Create('ab', [Box(0, 0, 40), Box(0, 0, 0)], [0, 1]);

  const Runs = FText.Locate(1, 2);

  Assert.AreEqual<Integer>(1, Length(Runs));
  Assert.AreEqual<Integer>(2, Length(Runs[0].Quads));
  Assert.AreEqual(Double(40), Double(Runs[0].Quads[0].P1.X), Tolerance);
  Assert.AreEqual(Double(50), Double(Runs[0].Quads[0].P2.X), Tolerance);
  Assert.AreEqual(Double(0), Double(Runs[0].Quads[1].P1.X), Tolerance);
  Assert.AreEqual(Double(10), Double(Runs[0].Quads[1].P2.X), Tolerance);
end;

procedure TPdfPositionedTextTests.TestLocateRightToLeftGlyphsInLogicalOrderGiveOneQuad;
begin
  FText := TPdfPositionedText.Create('abc', [Box(0, 0, 20), Box(0, 0, 10), Box(0, 0, 0)], [0, 1, 2]);

  const Runs = FText.Locate(1, 3);

  Assert.AreEqual<Integer>(1, Length(Runs));
  Assert.AreEqual<Integer>(1, Length(Runs[0].Quads));
  Assert.AreEqual(Double(0), Double(Runs[0].Quads[0].P1.X), Tolerance);
  Assert.AreEqual(Double(30), Double(Runs[0].Quads[0].P2.X), Tolerance);
  Assert.AreEqual(Double(30), Double(Runs[0].Quads[0].P3.X), Tolerance);
  Assert.AreEqual(Double(0), Double(Runs[0].Quads[0].P4.X), Tolerance);
end;

procedure TPdfPositionedTextTests.TestLocateRunDrawnLaterOnTheLeftDoesNotInvertTheQuad;
begin
  FText := TPdfPositionedText.Create('abc', [Box(0, 0, 50), Box(0, 0, 60), Box(0, 0, 0)], [0, 1, 2]);

  const Runs = FText.Locate(1, 3);

  Assert.AreEqual<Integer>(2, Length(Runs[0].Quads));
  for var Quad in Runs[0].Quads do
  begin
    Assert.IsTrue(Quad.P2.X > Quad.P1.X, 'the quad runs forwards');
  end;
  Assert.AreEqual(Double(50), Double(Runs[0].Quads[0].P1.X), Tolerance);
  Assert.AreEqual(Double(70), Double(Runs[0].Quads[0].P2.X), Tolerance);
  Assert.AreEqual(Double(0), Double(Runs[0].Quads[1].P1.X), Tolerance);
  Assert.AreEqual(Double(10), Double(Runs[0].Quads[1].P2.X), Tolerance);
end;

procedure TPdfPositionedTextTests.TestLocateActualTextSequenceAcrossPagesGivesNoTextOnThePageWithoutCharacters;
begin
  var First := Box(0, 0, 0);
  var Second := Box(1, 1, 0);
  First.ActualTextSpan := 1;
  Second.ActualTextSpan := 1;
  FText := TPdfPositionedText.Create('XQ', [First, Second, Box(1, 1, 10)], [0, 2]);

  const Runs = FText.Locate(1, 1);

  Assert.AreEqual<Integer>(2, Length(Runs));
  Assert.AreEqual<Integer>(0, Runs[0].PageIndex);
  Assert.AreEqual('X', Runs[0].Text);
  Assert.AreEqual<Integer>(1, Runs[1].PageIndex);
  Assert.AreEqual('', Runs[1].Text);
  Assert.AreEqual<Integer>(1, Length(Runs[1].Quads));
end;

procedure TPdfPositionedTextTests.TestLocateWholeLargeTextWithActualTextIsFast;
begin
  const PageCount = 200;
  const GlyphsPerPage = 2000;
  const GlyphsPerLine = 100;
  const GlyphsPerSequence = 10;
  const Total = PageCount * GlyphsPerPage;

  var Glyphs: TArray<TPdfGlyphBox>;
  var CharToGlyph: TArray<Integer>;
  SetLength(Glyphs, Total);
  SetLength(CharToGlyph, Total);
  for var Index := 0 to Total - 1 do
  begin
    const PageIndex = Index div GlyphsPerPage;
    const OnPage = Index mod GlyphsPerPage;
    Glyphs[Index] := Box(PageIndex, Index div GlyphsPerLine, (OnPage mod GlyphsPerLine) * 10);
    Glyphs[Index].ActualTextSpan := Index div GlyphsPerSequence + 1;
    CharToGlyph[Index] := Index;
  end;
  FText := TPdfPositionedText.Create(StringOfChar('a', Total), Glyphs, CharToGlyph);

  const Stopwatch = TStopwatch.StartNew;
  const Runs = FText.Locate(1, Total);
  const Elapsed = Stopwatch.ElapsedMilliseconds;

  Assert.AreEqual<Integer>(PageCount, Length(Runs));
  Assert.AreEqual<Integer>(GlyphsPerPage div GlyphsPerLine, Length(Runs[PageCount - 1].Quads));
  Assert.AreEqual<Integer>(GlyphsPerPage, Length(Runs[0].Text));
  // Quadratic work would take minutes; the bound leaves room for a slow machine
  Assert.IsTrue(Elapsed < 2000, Format('Locate took %d ms', [Elapsed]));
end;

end.
