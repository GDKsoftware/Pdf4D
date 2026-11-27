// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// The lines of tests/reference/tiny-skia/known-differences.txt (format in docs/golden-format.md)
unit Pdf4D.Tests.TinySkiaImages.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Exceptions,
  Pdf4D.Tests.TinySkiaImages;

type
  [TestFixture]
  TTinySkiaKnownDifferencesTests = class
  private
    FBadLines: TArray<string>;

    procedure ParseBadLines;

  public
    [Test]
    procedure TestUnlistedPngIsExact;

    [Test]
    procedure TestListedPngGetsTwoSteps;

    [Test]
    procedure TestPlatformEntryHoldsOnThatPlatformOnly;

    [Test]
    procedure TestPixelLimitEntryHasNoToleranceForTheOtherPixels;

    [Test]
    procedure TestPixelLimitEntryHoldsOnThatPlatformOnly;

    [Test]
    procedure TestFirstMatchingLineCounts;

    [Test]
    procedure TestCommentsAndEmptyLinesAreIgnored;

    [Test]
    procedure TestPixelLimitWithoutPlatformFails;

    [Test]
    procedure TestPixelLimitWithoutStepsFails;

    [Test]
    procedure TestStepsBelowTheToleranceFail;

    [Test]
    procedure TestUnknownTextAfterThePlatformFails;

    [Test]
    procedure TestMissingClosingBracketFails;
  end;

implementation

procedure TTinySkiaKnownDifferencesTests.ParseBadLines;
begin
  TTinySkiaImages.AllowanceFor(FBadLines, 'a.png', 'Win32');
end;

procedure TTinySkiaKnownDifferencesTests.TestUnlistedPngIsExact;
begin
  const Allowance = TTinySkiaImages.AllowanceFor(['b.png # reason'], 'a.png', 'Win64');
  Assert.AreEqual(0, Allowance.Tolerance);
  Assert.AreEqual(0, Allowance.Pixels);
  Assert.AreEqual(0, Allowance.Steps);
end;

procedure TTinySkiaKnownDifferencesTests.TestListedPngGetsTwoSteps;
begin
  const Allowance = TTinySkiaImages.AllowanceFor(['a.png # ArcCos differs'], 'a.png', 'Linux64');
  Assert.AreEqual(2, Allowance.Tolerance);
  Assert.AreEqual(0, Allowance.Pixels);
end;

procedure TTinySkiaKnownDifferencesTests.TestPlatformEntryHoldsOnThatPlatformOnly;
begin
  const Lines: TArray<string> = ['a.png [Linux64] # reason'];
  Assert.AreEqual(2, TTinySkiaImages.AllowanceFor(Lines, 'a.png', 'Linux64').Tolerance);
  Assert.AreEqual(0, TTinySkiaImages.AllowanceFor(Lines, 'a.png', 'Win64').Tolerance);
  Assert.AreEqual(0, TTinySkiaImages.AllowanceFor(Lines, 'a.png', 'Win32').Tolerance);
end;

procedure TTinySkiaKnownDifferencesTests.TestPixelLimitEntryHasNoToleranceForTheOtherPixels;
begin
  const Allowance = TTinySkiaImages.AllowanceFor(['a.png [Win32] pixels=1 steps=13 # one pixel flips'], 'a.png', 'Win32');
  Assert.AreEqual(0, Allowance.Tolerance, 'The other pixels must be equal');
  Assert.AreEqual(1, Allowance.Pixels);
  Assert.AreEqual(13, Allowance.Steps);
end;

procedure TTinySkiaKnownDifferencesTests.TestPixelLimitEntryHoldsOnThatPlatformOnly;
begin
  const Lines: TArray<string> = ['a.png [Win32] pixels=1 steps=13 # one pixel flips'];
  Assert.AreEqual(0, TTinySkiaImages.AllowanceFor(Lines, 'a.png', 'Win64').Pixels);
  Assert.AreEqual(0, TTinySkiaImages.AllowanceFor(Lines, 'a.png', 'Win64').Steps);
  Assert.AreEqual(0, TTinySkiaImages.AllowanceFor(Lines, 'a.png', 'Linux64').Pixels);
end;

procedure TTinySkiaKnownDifferencesTests.TestFirstMatchingLineCounts;
begin
  const Lines: TArray<string> = ['a.png [Win32] pixels=2 steps=9 # first', 'a.png # second'];
  Assert.AreEqual(2, TTinySkiaImages.AllowanceFor(Lines, 'a.png', 'Win32').Pixels);
  Assert.AreEqual(2, TTinySkiaImages.AllowanceFor(Lines, 'a.png', 'Win64').Tolerance, 'The first line does not match Win64');
end;

procedure TTinySkiaKnownDifferencesTests.TestCommentsAndEmptyLinesAreIgnored;
begin
  const Lines: TArray<string> = ['# a.png', '', '   ', 'a.png [Win32] pixels=1 steps=5'];
  Assert.AreEqual(5, TTinySkiaImages.AllowanceFor(Lines, 'a.png', 'Win32').Steps);
end;

procedure TTinySkiaKnownDifferencesTests.TestPixelLimitWithoutPlatformFails;
begin
  FBadLines := ['a.png pixels=1 steps=13 # no platform'];
  Assert.WillRaise(ParseBadLines, ETestFailure);

  // The same with brackets that name no platform
  FBadLines := ['a.png [] pixels=1 steps=13 # no platform'];
  Assert.WillRaise(ParseBadLines, ETestFailure);
end;

procedure TTinySkiaKnownDifferencesTests.TestPixelLimitWithoutStepsFails;
begin
  FBadLines := ['a.png [Win32] pixels=1 # no steps'];
  Assert.WillRaise(ParseBadLines, ETestFailure);

  FBadLines := ['a.png [Win32] steps=13 # no pixels'];
  Assert.WillRaise(ParseBadLines, ETestFailure);
end;

procedure TTinySkiaKnownDifferencesTests.TestStepsBelowTheToleranceFail;
begin
  FBadLines := ['a.png [Win32] pixels=1 steps=2 # a limit that is not larger than the plain tolerance'];
  Assert.WillRaise(ParseBadLines, ETestFailure);
end;

procedure TTinySkiaKnownDifferencesTests.TestUnknownTextAfterThePlatformFails;
begin
  FBadLines := ['a.png [Win32] pixel=1 steps=13 # a typo'];
  Assert.WillRaise(ParseBadLines, ETestFailure);
end;

procedure TTinySkiaKnownDifferencesTests.TestMissingClosingBracketFails;
begin
  FBadLines := ['a.png [Win32 pixels=1 steps=13 # reason'];
  Assert.WillRaise(ParseBadLines, ETestFailure);
end;

end.
