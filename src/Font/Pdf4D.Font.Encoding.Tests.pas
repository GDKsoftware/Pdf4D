// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Font.Encoding.Tests;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.PdfArray;

type
  [TestFixture]
  TEncodingTests = class
  private
    // Builds << /BaseEncoding <BaseName> /Differences [...] >>; the items are numbers (Integer) and names (string)
    function CreateEncodingDictionary(const BaseName: string; const Differences: array of const): TCosDictionary;
    function CreateDifferences(const Items: array of const): TCosArray;
    procedure CreateSymbolicWithoutBuiltIn;

  public
    [Test]
    procedure TestWinAnsiEuro;

    [Test]
    procedure TestWinAnsiUnusedCodesAreBullet;

    [Test]
    procedure TestWinAnsiKeepsFirstNameOfCode;

    [Test]
    procedure TestPredefinedTablesSpotChecks;

    [Test]
    procedure TestMacOSRomanAddsToMacRoman;

    [Test]
    procedure TestTryGetInstanceByName;

    [Test]
    procedure TestTryGetInstanceUnknownNameFails;

    [Test]
    procedure TestSharedInstanceIsTheSame;

    [Test]
    procedure TestUnknownCodeIsNotDef;

    [Test]
    procedure TestDifferencesOverrideBase;

    [Test]
    procedure TestDifferencesUpdateReverseMapping;

    [Test]
    procedure TestDifferencesWithoutBaseUseStandardWhenNonSymbolic;

    [Test]
    procedure TestInvalidBaseEncodingNameFallsBackToStandard;

    [Test]
    procedure TestSymbolicFontUsesBuiltInEncoding;

    [Test]
    procedure TestSymbolicFontWithoutBuiltInRaises;

    [Test]
    procedure TestDifferencesBeforeFirstNumberStartAtMinusOne;

    [Test]
    procedure TestDifferencesAtMaxIntWrap;

    [Test]
    procedure TestType3EncodingHasNoBase;

    [Test]
    procedure TestType3EncodingWithBaseEncoding;

    [Test]
    procedure TestEncodingNames;

    [Test]
    procedure TestBuiltInEncodingCopiesMapping;

    [Test]
    procedure TestType1EncodingFromFontBox;

    [Test]
    procedure TestFontBoxStandardEncoding;

    [Test]
    procedure TestFontBoxMacRomanEncoding;

    [Test]
    procedure TestFontBoxBuiltInEncoding;
  end;

implementation

uses
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Common.Defines,
  Pdf4D.Font.Encoding,
  Pdf4D.Font.Encoding.Tables,
  Pdf4D.FontBox.Encoding;

{ TEncodingTests }

function TEncodingTests.CreateDifferences(const Items: array of const): TCosArray;
begin
  Result := TCosArray.Create;
  try
    for var Item in Items do
    begin
      if Item.VType = vtInteger then
      begin
        Result.Add(TCosInteger.Create(Item.VInteger));
      end
      else
      begin
        Result.Add(TCosName.Create(string(Item.VUnicodeString)));
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TEncodingTests.CreateEncodingDictionary(const BaseName: string; const Differences: array of const): TCosDictionary;
begin
  Result := TCosDictionary.Create;
  try
    if BaseName <> '' then
    begin
      Result.SetItem(TCosNames.BaseEncoding, TCosName.Create(BaseName));
    end;
    Result.SetItem(TCosNames.Differences, CreateDifferences(Differences));
  except
    Result.Free;
    raise;
  end;
end;

procedure TEncodingTests.TestWinAnsiEuro;
begin
  Assert.AreEqual('Euro', TWinAnsiEncoding.Instance.GetName(128));
  Assert.AreEqual('bullet', TWinAnsiEncoding.Instance.GetName(129));
end;

procedure TEncodingTests.TestWinAnsiUnusedCodesAreBullet;
begin
  const Encoding = TWinAnsiEncoding.Instance;
  Assert.AreEqual('bullet', Encoding.GetName(141));
  Assert.AreEqual('bullet', Encoding.GetName(143));
  Assert.AreEqual('bullet', Encoding.GetName(144));
  Assert.AreEqual('bullet', Encoding.GetName(157));
  // Codes up to 040 (octal) stay unmapped
  Assert.AreEqual('.notdef', Encoding.GetName(31));
  Assert.AreEqual('.notdef', Encoding.GetName(0));
  Assert.AreEqual('space', Encoding.GetName(32));
  Assert.AreEqual('.notdef', Encoding.GetName(256));
end;

procedure TEncodingTests.TestWinAnsiKeepsFirstNameOfCode;
begin
  // The additional mappings of Appendix D of the PDF specification
  const Encoding = TWinAnsiEncoding.Instance;
  Assert.AreEqual('nbspace', Encoding.GetName(160));
  Assert.AreEqual('sfthyphen', Encoding.GetName(173));
  var Code: Integer;
  Assert.IsTrue(Encoding.NameToCodeMap.TryGetValue('bullet', Code));
  // The reverse mapping keeps the first code that was added: the table entry at 149, not a filled-in one
  Assert.AreEqual(149, Code);
end;

procedure TEncodingTests.TestPredefinedTablesSpotChecks;
begin
  Assert.AreEqual('fi', TStandardEncoding.Instance.GetName(174));
  Assert.AreEqual('quoteright', TStandardEncoding.Instance.GetName(39));
  Assert.AreEqual('quotesingle', TStandardEncoding.Instance.GetName(169));
  Assert.AreEqual('Adieresis', TMacRomanEncoding.Instance.GetName(128));
  Assert.AreEqual('nbspace', TMacRomanEncoding.Instance.GetName(202));
  Assert.AreEqual('alpha', TSymbolEncoding.Instance.GetName(97));
  Assert.AreEqual('a1', TZapfDingbatsEncoding.Instance.GetName(33));
  Assert.AreEqual('Asmall', TMacExpertEncoding.Instance.GetName(97));
end;

procedure TEncodingTests.TestMacOSRomanAddsToMacRoman;
begin
  const MacOS = TMacOSRomanEncoding.Instance;
  Assert.AreEqual('notequal', MacOS.GetName(173));
  Assert.AreEqual('apple', MacOS.GetName(240));
  Assert.AreEqual('Adieresis', MacOS.GetName(128));
  Assert.IsFalse(TMacRomanEncoding.Instance.Contains('apple'));
end;

procedure TEncodingTests.TestTryGetInstanceByName;
begin
  var Encoding: TPdfEncoding;
  Assert.IsTrue(TPdfEncoding.TryGetInstance(TCosNames.StandardEncoding, Encoding));
  Assert.AreSame(TStandardEncoding.Instance, Encoding);
  Assert.IsTrue(TPdfEncoding.TryGetInstance(TCosNames.WinAnsiEncoding, Encoding));
  Assert.AreSame(TWinAnsiEncoding.Instance, Encoding);
  Assert.IsTrue(TPdfEncoding.TryGetInstance(TCosNames.MacRomanEncoding, Encoding));
  Assert.AreSame(TMacRomanEncoding.Instance, Encoding);
  Assert.IsTrue(TPdfEncoding.TryGetInstance(TCosNames.MacExpertEncoding, Encoding));
  Assert.AreSame(TMacExpertEncoding.Instance, Encoding);
end;

procedure TEncodingTests.TestTryGetInstanceUnknownNameFails;
begin
  var Encoding: TPdfEncoding;
  Assert.IsFalse(TPdfEncoding.TryGetInstance('SymbolEncoding', Encoding));
  Assert.IsNull(Encoding);
  Assert.IsFalse(TPdfEncoding.TryGetInstance('Identity-H', Encoding));
  Assert.IsFalse(TPdfEncoding.TryGetInstance('', Encoding));
end;

procedure TEncodingTests.TestSharedInstanceIsTheSame;
begin
  Assert.AreSame(TWinAnsiEncoding.Instance, TWinAnsiEncoding.Instance);
  Assert.AreSame(TMacOSRomanEncoding.Instance, TMacOSRomanEncoding.Instance);
  Assert.AreNotSame(TMacRomanEncoding.Instance, TMacOSRomanEncoding.Instance);
end;

procedure TEncodingTests.TestUnknownCodeIsNotDef;
begin
  Assert.AreEqual('.notdef', TStandardEncoding.Instance.GetName(0));
  Assert.AreEqual('.notdef', TStandardEncoding.Instance.GetName(-5));
  Assert.IsFalse(TStandardEncoding.Instance.Contains(0));
  Assert.IsTrue(TStandardEncoding.Instance.Contains(65));
  Assert.IsTrue(TStandardEncoding.Instance.Contains('A'));
  Assert.IsFalse(TStandardEncoding.Instance.Contains('nosuchglyph'));
end;

procedure TEncodingTests.TestDifferencesOverrideBase;
begin
  const Dictionary = CreateEncodingDictionary(TCosNames.WinAnsiEncoding, [65, 'fi', 'fl', 128, 'Adieresis']);
  try
    const Encoding = TDictionaryEncoding.Create(Dictionary, True, nil);
    try
      Assert.AreEqual('fi', Encoding.GetName(65));
      Assert.AreEqual('fl', Encoding.GetName(66));
      Assert.AreEqual('Adieresis', Encoding.GetName(128));
      Assert.AreEqual('C', Encoding.GetName(67));
      Assert.AreSame(TWinAnsiEncoding.Instance, Encoding.BaseEncoding);
      Assert.AreEqual<Integer>(3, Encoding.Differences.Count);
      // The shared base encoding is not changed
      Assert.AreEqual('A', TWinAnsiEncoding.Instance.GetName(65));
    finally
      Encoding.Free;
    end;
  finally
    Dictionary.Free;
  end;
end;

procedure TEncodingTests.TestDifferencesUpdateReverseMapping;
begin
  const Dictionary = CreateEncodingDictionary(TCosNames.WinAnsiEncoding, [65, 'fi']);
  try
    const Encoding = TDictionaryEncoding.Create(Dictionary, True, nil);
    try
      Assert.IsFalse(Encoding.Contains('A'));
      Assert.IsTrue(Encoding.Contains('fi'));
      var Code: Integer;
      Assert.IsTrue(Encoding.NameToCodeMap.TryGetValue('fi', Code));
      Assert.AreEqual(65, Code);
    finally
      Encoding.Free;
    end;
  finally
    Dictionary.Free;
  end;
end;

procedure TEncodingTests.TestDifferencesWithoutBaseUseStandardWhenNonSymbolic;
begin
  const Dictionary = CreateEncodingDictionary('', [200, 'bullet']);
  try
    const Encoding = TDictionaryEncoding.Create(Dictionary, True, nil);
    try
      Assert.AreEqual('quoteright', Encoding.GetName(39));
      Assert.AreEqual('bullet', Encoding.GetName(200));
      Assert.AreSame(TStandardEncoding.Instance, Encoding.BaseEncoding);
    finally
      Encoding.Free;
    end;
  finally
    Dictionary.Free;
  end;
end;

procedure TEncodingTests.TestInvalidBaseEncodingNameFallsBackToStandard;
begin
  const Dictionary = CreateEncodingDictionary('NoSuchEncoding', [65, 'fi']);
  try
    const Encoding = TDictionaryEncoding.Create(Dictionary, True, nil);
    try
      Assert.AreSame(TStandardEncoding.Instance, Encoding.BaseEncoding);
      Assert.AreEqual('quoteright', Encoding.GetName(39));
    finally
      Encoding.Free;
    end;
  finally
    Dictionary.Free;
  end;
end;

procedure TEncodingTests.TestSymbolicFontUsesBuiltInEncoding;
begin
  const Mapping = TDictionary<Integer, string>.Create;
  try
    Mapping.Add(1, 'one');
    Mapping.Add(2, 'two');
    const BuiltIn = TBuiltInEncoding.Create(Mapping);
    try
      const Dictionary = CreateEncodingDictionary('', [2, 'zwei']);
      try
        const Encoding = TDictionaryEncoding.Create(Dictionary, False, BuiltIn);
        try
          Assert.AreEqual('one', Encoding.GetName(1));
          Assert.AreEqual('zwei', Encoding.GetName(2));
          Assert.AreSame(TPdfEncoding(BuiltIn), Encoding.BaseEncoding);
          // The built-in encoding is not changed
          Assert.AreEqual('two', BuiltIn.GetName(2));
        finally
          Encoding.Free;
        end;
      finally
        Dictionary.Free;
      end;
    finally
      BuiltIn.Free;
    end;
  finally
    Mapping.Free;
  end;
end;

procedure TEncodingTests.CreateSymbolicWithoutBuiltIn;
begin
  const Dictionary = CreateEncodingDictionary('', [65, 'fi']);
  try
    TDictionaryEncoding.Create(Dictionary, False, nil).Free;
  finally
    Dictionary.Free;
  end;
end;

procedure TEncodingTests.TestSymbolicFontWithoutBuiltInRaises;
begin
  Assert.WillRaise(CreateSymbolicWithoutBuiltIn, EPdfException);
end;

procedure TEncodingTests.TestDifferencesBeforeFirstNumberStartAtMinusOne;
begin
  const Dictionary = CreateEncodingDictionary(TCosNames.WinAnsiEncoding, ['fi', 'fl']);
  try
    const Encoding = TDictionaryEncoding.Create(Dictionary, True, nil);
    try
      Assert.AreEqual('fi', Encoding.GetName(-1));
      Assert.AreEqual('fl', Encoding.GetName(0));
    finally
      Encoding.Free;
    end;
  finally
    Dictionary.Free;
  end;
end;

procedure TEncodingTests.TestDifferencesAtMaxIntWrap;
begin
  const Dictionary = CreateEncodingDictionary(TCosNames.WinAnsiEncoding, [High(Integer), 'fi', 'fl']);
  try
    const Encoding = TDictionaryEncoding.Create(Dictionary, True, nil);
    try
      Assert.AreEqual('fi', Encoding.GetName(High(Integer)));
      Assert.AreEqual('fl', Encoding.GetName(Low(Integer)));
    finally
      Encoding.Free;
    end;
  finally
    Dictionary.Free;
  end;
end;

procedure TEncodingTests.TestType3EncodingHasNoBase;
begin
  const Dictionary = CreateEncodingDictionary('', [65, 'square', 'circle']);
  try
    const Encoding = TDictionaryEncoding.CreateForType3(Dictionary);
    try
      Assert.IsNull(Encoding.BaseEncoding);
      Assert.AreEqual('differences', Encoding.EncodingName);
      Assert.AreEqual('square', Encoding.GetName(65));
      Assert.AreEqual('circle', Encoding.GetName(66));
      Assert.AreEqual('.notdef', Encoding.GetName(67));
    finally
      Encoding.Free;
    end;
  finally
    Dictionary.Free;
  end;
end;

procedure TEncodingTests.TestType3EncodingWithBaseEncoding;
begin
  const Dictionary = CreateEncodingDictionary(TCosNames.WinAnsiEncoding, [65, 'square']);
  try
    const Encoding = TDictionaryEncoding.CreateForType3(Dictionary);
    try
      Assert.AreSame(TWinAnsiEncoding.Instance, Encoding.BaseEncoding);
      Assert.AreEqual('square', Encoding.GetName(65));
      Assert.AreEqual('B', Encoding.GetName(66));
    finally
      Encoding.Free;
    end;
  finally
    Dictionary.Free;
  end;
end;

procedure TEncodingTests.TestEncodingNames;
begin
  Assert.AreEqual('StandardEncoding', TStandardEncoding.Instance.EncodingName);
  Assert.AreEqual('WinAnsiEncoding', TWinAnsiEncoding.Instance.EncodingName);
  Assert.AreEqual('MacRomanEncoding', TMacRomanEncoding.Instance.EncodingName);
  Assert.AreEqual('MacRomanEncoding', TMacOSRomanEncoding.Instance.EncodingName);
  Assert.AreEqual('MacExpertEncoding', TMacExpertEncoding.Instance.EncodingName);
  Assert.AreEqual('SymbolEncoding', TSymbolEncoding.Instance.EncodingName);
  Assert.AreEqual('ZapfDingbatsEncoding', TZapfDingbatsEncoding.Instance.EncodingName);

  const Dictionary = CreateEncodingDictionary(TCosNames.MacRomanEncoding, []);
  try
    const Encoding = TDictionaryEncoding.Create(Dictionary, True, nil);
    try
      Assert.AreEqual('MacRomanEncoding with differences', Encoding.EncodingName);
    finally
      Encoding.Free;
    end;
  finally
    Dictionary.Free;
  end;
end;

procedure TEncodingTests.TestBuiltInEncodingCopiesMapping;
begin
  const Mapping = TDictionary<Integer, string>.Create;
  try
    Mapping.Add(10, 'ten');
    const Encoding = TBuiltInEncoding.Create(Mapping);
    try
      Mapping.Add(11, 'eleven');
      Assert.AreEqual('ten', Encoding.GetName(10));
      Assert.AreEqual('.notdef', Encoding.GetName(11));
      Assert.AreEqual('built-in (TTF)', Encoding.EncodingName);
    finally
      Encoding.Free;
    end;
  finally
    Mapping.Free;
  end;
end;

procedure TEncodingTests.TestType1EncodingFromFontBox;
begin
  const Encoding = TType1Encoding.FromFontBox(TFontBoxStandardEncoding.Instance);
  try
    Assert.AreEqual('A', Encoding.GetName(65));
    Assert.AreEqual('fi', Encoding.GetName(174));
    Assert.AreEqual('built-in (Type 1)', Encoding.EncodingName);
    Assert.AreEqual(TFontBoxStandardEncoding.Instance.CodeToNameMap.Count, Encoding.CodeToNameMap.Count);
  finally
    Encoding.Free;
  end;
end;

procedure TEncodingTests.TestFontBoxStandardEncoding;
begin
  const Encoding = TFontBoxStandardEncoding.Instance;
  Assert.AreEqual('quoteright', Encoding.GetName(39));
  Assert.AreEqual('.notdef', Encoding.GetName(0));
  Assert.AreEqual<Integer>(149, Encoding.CodeToNameMap.Count);
  var Code: Integer;
  Assert.IsTrue(Encoding.GetCode('fi', Code));
  Assert.AreEqual(174, Code);
  Assert.IsFalse(Encoding.GetCode('nosuchglyph', Code));
  Assert.AreSame(Encoding, TFontBoxStandardEncoding.Instance);
end;

procedure TEncodingTests.TestFontBoxMacRomanEncoding;
begin
  const Encoding = TFontBoxMacRomanEncoding.Instance;
  Assert.AreEqual('Adieresis', Encoding.GetName(128));
  // Unlike the PDF encoding it has no nbspace
  Assert.AreEqual<Integer>(207, Encoding.CodeToNameMap.Count);
  var Code: Integer;
  Assert.IsFalse(Encoding.GetCode('nbspace', Code));
  Assert.AreSame(Encoding, TFontBoxMacRomanEncoding.Instance);
end;

procedure TEncodingTests.TestFontBoxBuiltInEncoding;
begin
  const Mapping = TDictionary<Integer, string>.Create;
  try
    Mapping.Add(3, 'three');
    const Encoding = TFontBoxBuiltInEncoding.Create(Mapping);
    try
      Assert.AreEqual('three', Encoding.GetName(3));
      var Code: Integer;
      Assert.IsTrue(Encoding.GetCode('three', Code));
      Assert.AreEqual(3, Code);
    finally
      Encoding.Free;
    end;
  finally
    Mapping.Free;
  end;
end;

end.
