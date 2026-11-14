// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Text.UnicodeTables.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPdfUnicodeTablesTests = class
  public
    [Test]
    procedure TestLigatureFi;

    [Test]
    procedure TestArabicPresentationForm;

    [Test]
    procedure TestTrimmedDecomposition;

    [Test]
    procedure TestOutsideRangeIsNotNormalized;

    [Test]
    procedure TestAcuteAccentIsDiacritic;

    [Test]
    procedure TestLetterIsNoDiacritic;

    [Test]
    procedure TestDiacriticCategories;

    [Test]
    procedure TestInstanceIsShared;
  end;

implementation

uses
  System.SysUtils,
  Pdf4D.Text.UnicodeTables;

{ TPdfUnicodeTablesTests }

procedure TPdfUnicodeTablesTests.TestLigatureFi;
begin
  var Normalized: string;

  Assert.IsTrue(TPdfUnicodeText.Instance.TryGetPresentationForm(#$FB01, Normalized));
  Assert.AreEqual('fi', Normalized);
end;

procedure TPdfUnicodeTablesTests.TestArabicPresentationForm;
begin
  var Normalized: string;

  Assert.IsTrue(TPdfUnicodeText.Instance.TryGetPresentationForm(#$FEDF, Normalized));
  Assert.AreEqual(#$0644, Normalized);
end;

procedure TPdfUnicodeTablesTests.TestTrimmedDecomposition;
begin
  var Normalized: string;

  // NFKC of U+FC5E is a space followed by U+064C U+0651; the space is trimmed like PDFBox does
  Assert.IsTrue(TPdfUnicodeText.Instance.TryGetPresentationForm(#$FC5E, Normalized));
  Assert.AreEqual(#$064C#$0651, Normalized);
end;

procedure TPdfUnicodeTablesTests.TestOutsideRangeIsNotNormalized;
begin
  var Normalized: string;

  Assert.IsFalse(TPdfUnicodeText.Instance.TryGetPresentationForm(#$00B5, Normalized));
  Assert.IsFalse(TPdfUnicodeText.Instance.TryGetPresentationForm('a', Normalized));
end;

procedure TPdfUnicodeTablesTests.TestAcuteAccentIsDiacritic;
begin
  var Normalized: string;

  Assert.IsTrue(TPdfUnicodeText.Instance.IsDiacriticCategory(#$00B4));
  Assert.IsTrue(TPdfUnicodeText.Instance.TryGetNfkc(#$00B4, Normalized));
  Assert.AreEqual(#$0301, Normalized);
end;

procedure TPdfUnicodeTablesTests.TestLetterIsNoDiacritic;
begin
  var Normalized: string;

  Assert.IsFalse(TPdfUnicodeText.Instance.IsDiacriticCategory('e'));
  Assert.IsFalse(TPdfUnicodeText.Instance.TryGetNfkc('e', Normalized));
end;

procedure TPdfUnicodeTablesTests.TestDiacriticCategories;
begin
  // Non-spacing mark, modifier symbol, modifier letter; a surrogate and the last BMP code point are none
  Assert.IsTrue(TPdfUnicodeText.Instance.IsDiacriticCategory(#$0301));
  Assert.IsTrue(TPdfUnicodeText.Instance.IsDiacriticCategory('^'));
  Assert.IsTrue(TPdfUnicodeText.Instance.IsDiacriticCategory(#$02B0));
  Assert.IsFalse(TPdfUnicodeText.Instance.IsDiacriticCategory(#$D800));
  Assert.IsFalse(TPdfUnicodeText.Instance.IsDiacriticCategory(#$FFFF));
  Assert.IsFalse(TPdfUnicodeText.Instance.IsDiacriticCategory(#$0000));
end;

procedure TPdfUnicodeTablesTests.TestInstanceIsShared;
begin
  Assert.AreSame(TPdfUnicodeText.Instance, TPdfUnicodeText.Instance);
end;

end.
