// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Font.Descriptor.Tests;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Font.Descriptor;

type
  [TestFixture]
  TFontDescriptorTests = class
  private
    FDictionary: TCosDictionary;

    function FlagNames(const Descriptor: TPDFontDescriptor): string;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    [TestCase('NonSymbolic', '32,NonSymbolic')]
    [TestCase('Symbolic', '4,Symbolic')]
    [TestCase('ForceBold', '262144,ForceBold')]
    [TestCase('FixedPitchItalic', '65,FixedPitch+Italic')]
    [TestCase('SerifScript', '10,Serif+Script')]
    [TestCase('AllCapSmallCap', '196608,AllCap+SmallCap')]
    [TestCase('NoFlags', '0,')]
    procedure TestDescriptorFlags(const Flags: Integer; const Expected: string);

    [Test]
    procedure TestMissingFlagsAreZero;

    [Test]
    procedure TestNamesAndNumbers;

    [Test]
    procedure TestMissingValuesHaveDefaults;

    [Test]
    procedure TestNegativeCapHeightAndXHeightAreMadePositive;

    [Test]
    procedure TestMissingWidth;

    [Test]
    procedure TestFontBoundingBox;

    [Test]
    procedure TestFontFiles;

    [Test]
    procedure TestPanose;

    [Test]
    procedure TestPanoseWithTooFewBytesIsNotThere;

    [Test]
    procedure TestPanoseBytesAreSigned;

    [Test]
    procedure TestCIDSystemInfoFromDictionary;

    [Test]
    procedure TestCIDSystemInfoWithoutDictionary;

    [Test]
    procedure TestCosObjectIsTheDictionary;
  end;

implementation

uses
  Pdf4D.Cos.Float,
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Cos.PdfString,
  Pdf4D.Model.Rectangle;

{ TFontDescriptorTests }

procedure TFontDescriptorTests.Setup;
begin
  FDictionary := TCosDictionary.Create;
end;

procedure TFontDescriptorTests.TearDown;
begin
  FDictionary.Free;
end;

function TFontDescriptorTests.FlagNames(const Descriptor: TPDFontDescriptor): string;
begin
  var Names: TArray<string>;
  if Descriptor.IsFixedPitch then
  begin
    Names := Names + ['FixedPitch'];
  end;
  if Descriptor.IsSerif then
  begin
    Names := Names + ['Serif'];
  end;
  if Descriptor.IsSymbolic then
  begin
    Names := Names + ['Symbolic'];
  end;
  if Descriptor.IsScript then
  begin
    Names := Names + ['Script'];
  end;
  if Descriptor.IsNonSymbolic then
  begin
    Names := Names + ['NonSymbolic'];
  end;
  if Descriptor.IsItalic then
  begin
    Names := Names + ['Italic'];
  end;
  if Descriptor.IsAllCap then
  begin
    Names := Names + ['AllCap'];
  end;
  if Descriptor.IsSmallCap then
  begin
    Names := Names + ['SmallCap'];
  end;
  if Descriptor.IsForceBold then
  begin
    Names := Names + ['ForceBold'];
  end;
  Result := string.Join('+', Names);
end;

procedure TFontDescriptorTests.TestDescriptorFlags(const Flags: Integer; const Expected: string);
begin
  FDictionary.SetItem(TCosNames.Flags, TCosInteger.Create(Flags));
  const Descriptor = TPDFontDescriptor.Create(FDictionary);
  try
    Assert.AreEqual(Expected, FlagNames(Descriptor));
    Assert.AreEqual(Flags, Descriptor.Flags);
  finally
    Descriptor.Free;
  end;
end;

procedure TFontDescriptorTests.TestMissingFlagsAreZero;
begin
  const Descriptor = TPDFontDescriptor.Create(FDictionary);
  try
    Assert.AreEqual(0, Descriptor.Flags);
    Assert.AreEqual('', FlagNames(Descriptor));
  finally
    Descriptor.Free;
  end;
end;

procedure TFontDescriptorTests.TestNamesAndNumbers;
begin
  FDictionary.SetItem(TCosNames.FontName, TCosName.Create('ABCDEF+Arial-BoldMT'));
  FDictionary.SetItem(TCosNames.FontFamily, TCosString.Create(TEncoding.ASCII.GetBytes('Arial'), False));
  FDictionary.SetItem(TCosNames.FontStretch, TCosName.Create('Condensed'));
  FDictionary.SetItem(TCosNames.FontWeight, TCosInteger.Create(700));
  FDictionary.SetItem(TCosNames.ItalicAngle, TCosFloat.Create(-12.5));
  FDictionary.SetItem(TCosNames.Ascent, TCosInteger.Create(905));
  FDictionary.SetItem(TCosNames.Descent, TCosInteger.Create(-212));
  FDictionary.SetItem(TCosNames.Leading, TCosInteger.Create(33));
  FDictionary.SetItem(TCosNames.CapHeight, TCosInteger.Create(716));
  FDictionary.SetItem(TCosNames.XHeight, TCosInteger.Create(519));
  FDictionary.SetItem(TCosNames.StemV, TCosInteger.Create(80));
  FDictionary.SetItem(TCosNames.StemH, TCosInteger.Create(40));
  FDictionary.SetItem(TCosNames.AvgWidth, TCosInteger.Create(441));
  FDictionary.SetItem(TCosNames.MaxWidth, TCosInteger.Create(2000));
  const Descriptor = TPDFontDescriptor.Create(FDictionary);
  try
    Assert.AreEqual('ABCDEF+Arial-BoldMT', Descriptor.FontName);
    Assert.AreEqual('Arial', Descriptor.FontFamily);
    Assert.AreEqual('Condensed', Descriptor.FontStretch);
    Assert.AreEqual(Single(700), Descriptor.FontWeight);
    Assert.AreEqual(Single(-12.5), Descriptor.ItalicAngle);
    Assert.AreEqual(Single(905), Descriptor.Ascent);
    Assert.AreEqual(Single(-212), Descriptor.Descent);
    Assert.AreEqual(Single(33), Descriptor.Leading);
    Assert.AreEqual(Single(716), Descriptor.CapHeight);
    Assert.AreEqual(Single(519), Descriptor.XHeight);
    Assert.AreEqual(Single(80), Descriptor.StemV);
    Assert.AreEqual(Single(40), Descriptor.StemH);
    Assert.AreEqual(Single(441), Descriptor.AverageWidth);
    Assert.AreEqual(Single(2000), Descriptor.MaxWidth);
  finally
    Descriptor.Free;
  end;
end;

procedure TFontDescriptorTests.TestMissingValuesHaveDefaults;
begin
  const Descriptor = TPDFontDescriptor.Create(FDictionary);
  try
    Assert.AreEqual('', Descriptor.FontName);
    Assert.AreEqual('', Descriptor.FontFamily);
    Assert.AreEqual(Single(0), Descriptor.FontWeight);
    Assert.AreEqual(Single(0), Descriptor.StemV);
    Assert.AreEqual(Single(0), Descriptor.MaxWidth);
    Assert.IsFalse(Descriptor.HasWidths);
  finally
    Descriptor.Free;
  end;
end;

procedure TFontDescriptorTests.TestNegativeCapHeightAndXHeightAreMadePositive;
begin
  FDictionary.SetItem(TCosNames.CapHeight, TCosInteger.Create(-700));
  FDictionary.SetItem(TCosNames.XHeight, TCosFloat.Create(-500.5));
  const Descriptor = TPDFontDescriptor.Create(FDictionary);
  try
    Assert.AreEqual(Single(700), Descriptor.CapHeight);
    Assert.AreEqual(Single(500.5), Descriptor.XHeight);
  finally
    Descriptor.Free;
  end;
end;

procedure TFontDescriptorTests.TestMissingWidth;
begin
  const Descriptor = TPDFontDescriptor.Create(FDictionary);
  try
    Assert.IsFalse(Descriptor.HasMissingWidth);
    Assert.AreEqual(Single(0), Descriptor.MissingWidth);

    FDictionary.SetItem(TCosNames.MissingWidth, TCosInteger.Create(278));

    Assert.IsTrue(Descriptor.HasMissingWidth);
    Assert.IsTrue(Descriptor.HasWidths);
    Assert.AreEqual(Single(278), Descriptor.MissingWidth);
  finally
    Descriptor.Free;
  end;
end;

procedure TFontDescriptorTests.TestFontBoundingBox;
begin
  var Box: TPdfRectangle;
  const Descriptor = TPDFontDescriptor.Create(FDictionary);
  try
    Assert.IsFalse(Descriptor.TryGetFontBoundingBox(Box));

    const Values = TCosArray.Create;
    Values.Add(TCosInteger.Create(-100));
    Values.Add(TCosInteger.Create(-200));
    Values.Add(TCosInteger.Create(1000));
    Values.Add(TCosInteger.Create(900));
    FDictionary.SetItem(TCosNames.FontBBox, Values);

    Assert.IsTrue(Descriptor.TryGetFontBoundingBox(Box));
    Assert.AreEqual(Single(-100), Box.LowerLeftX);
    Assert.AreEqual(Single(-200), Box.LowerLeftY);
    Assert.AreEqual(Single(1000), Box.UpperRightX);
    Assert.AreEqual(Single(900), Box.UpperRightY);
  finally
    Descriptor.Free;
  end;
end;

procedure TFontDescriptorTests.TestFontFiles;
begin
  var Stream: TCosStream;
  const Descriptor = TPDFontDescriptor.Create(FDictionary);
  try
    Assert.IsFalse(Descriptor.TryGetFontFile(Stream));
    Assert.IsFalse(Descriptor.TryGetFontFile2(Stream));
    Assert.IsFalse(Descriptor.TryGetFontFile3(Stream));

    const FontFile2 = TCosStream.Create;
    FDictionary.SetItem(TCosNames.FontFile2, FontFile2);
    FDictionary.SetItem(TCosNames.FontFile3, TCosName.Create('NotAStream'));

    Assert.IsFalse(Descriptor.TryGetFontFile(Stream));
    Assert.IsTrue(Descriptor.TryGetFontFile2(Stream));
    Assert.IsTrue(Stream = FontFile2);
    Assert.IsFalse(Descriptor.TryGetFontFile3(Stream));
  finally
    Descriptor.Free;
  end;
end;

procedure TFontDescriptorTests.TestPanose;
begin
  const Bytes: TBytes = [$01, $02, 2, 11, 6, 4, 2, 2, 2, 2, 2, 4];
  const Style = TCosDictionary.Create;
  Style.SetItem(TCosNames.Panose, TCosString.Create(Bytes, False));
  FDictionary.SetItem(TCosNames.Style, Style);
  const Descriptor = TPDFontDescriptor.Create(FDictionary);
  try
    var Panose: TPDPanose;
    Assert.IsTrue(Descriptor.TryGetPanose(Panose));

    Assert.AreEqual($0102, Panose.FamilyClass);
    const Classification = Panose.Panose;
    Assert.AreEqual(2, Classification.FamilyKind);
    Assert.AreEqual(11, Classification.SerifStyle);
    Assert.AreEqual(6, Classification.Weight);
    Assert.AreEqual(4, Classification.Proportion);
    Assert.AreEqual(2, Classification.Contrast);
    Assert.AreEqual(2, Classification.StrokeVariation);
    Assert.AreEqual(2, Classification.ArmStyle);
    Assert.AreEqual(2, Classification.Letterform);
    Assert.AreEqual(2, Classification.Midline);
    Assert.AreEqual(4, Classification.XHeight);
  finally
    Descriptor.Free;
  end;
end;

procedure TFontDescriptorTests.TestPanoseWithTooFewBytesIsNotThere;
begin
  const Bytes: TBytes = [1, 2, 3];
  const Style = TCosDictionary.Create;
  Style.SetItem(TCosNames.Panose, TCosString.Create(Bytes, False));
  FDictionary.SetItem(TCosNames.Style, Style);
  const Descriptor = TPDFontDescriptor.Create(FDictionary);
  try
    var Panose: TPDPanose;
    Assert.IsFalse(Descriptor.TryGetPanose(Panose));
  finally
    Descriptor.Free;
  end;
end;

procedure TFontDescriptorTests.TestPanoseBytesAreSigned;
begin
  const Bytes: TBytes = [$FF, $01, $80, 0, 0, 0, 0, 0, 0, 0, 0, 0];
  const Style = TCosDictionary.Create;
  Style.SetItem(TCosNames.Panose, TCosString.Create(Bytes, False));
  FDictionary.SetItem(TCosNames.Style, Style);
  const Descriptor = TPDFontDescriptor.Create(FDictionary);
  try
    var Panose: TPDPanose;
    Assert.IsTrue(Descriptor.TryGetPanose(Panose));

    Assert.AreEqual(-255, Panose.FamilyClass);
    Assert.AreEqual(-128, Panose.Panose.FamilyKind);
  finally
    Descriptor.Free;
  end;
end;

procedure TFontDescriptorTests.TestCIDSystemInfoFromDictionary;
begin
  FDictionary.SetItem(TCosNames.Registry, TCosString.Create(TEncoding.ASCII.GetBytes('Adobe'), False));
  FDictionary.SetItem(TCosNames.Ordering, TCosString.Create(TEncoding.ASCII.GetBytes('Japan1'), False));
  FDictionary.SetItem(TCosNames.Supplement, TCosInteger.Create(6));

  var Info: TPDCIDSystemInfo;
  Assert.IsTrue(TPDCIDSystemInfo.TryFromDictionary(FDictionary, Info));

  Assert.AreEqual('Adobe', Info.Registry);
  Assert.AreEqual('Japan1', Info.Ordering);
  Assert.AreEqual(6, Info.Supplement);
  Assert.AreEqual('Adobe-Japan1-6', Info.ToString);
end;

procedure TFontDescriptorTests.TestCIDSystemInfoWithoutDictionary;
begin
  var Info: TPDCIDSystemInfo;
  Assert.IsFalse(TPDCIDSystemInfo.TryFromDictionary(nil, Info));

  Assert.IsTrue(TPDCIDSystemInfo.TryFromDictionary(FDictionary, Info));
  Assert.AreEqual('', Info.Registry);
  Assert.AreEqual('', Info.Ordering);
  Assert.AreEqual(-1, Info.Supplement);
end;

procedure TFontDescriptorTests.TestCosObjectIsTheDictionary;
begin
  const Descriptor = TPDFontDescriptor.Create(FDictionary);
  try
    Assert.IsTrue(Descriptor.CosObject = FDictionary);
  finally
    Descriptor.Free;
  end;
end;

end.
