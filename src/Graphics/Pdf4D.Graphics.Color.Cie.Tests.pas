// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Tests of Pdf4D for the CIE-based colour spaces of PDFBox (PDCIEDictionaryBasedColorSpace, PDCalGray, PDCalRGB and PDLab, 3.0.8); the
// reference values (tests/reference/color-spaces/colorspaces.txt) come from PDFBox itself
unit Pdf4D.Graphics.Color.Cie.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Graphics.Color,
  Pdf4D.Tests.ColorBuilder,
  Pdf4D.Tests.ColorSpaceReferences;

type
  [TestFixture]
  TCieColorSpaceTests = class
  private
    FBuilder: TColorTestBuilder;
    FReferences: TColorSpaceReferences;

    // [/Kind dictionary] with the dictionary that Entries fills; each entry is a key and the numbers of its array
    function NewCieArray(const Kind: string; const Entries: array of string): TCosArray;
    function CieSpace(const Kind: string; const Entries: array of string): TPDColorSpace;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestCalRgbMatchesPdfBox;

    [Test]
    procedure TestCalGrayMatchesPdfBox;

    [Test]
    procedure TestLabMatchesPdfBox;

    [Test]
    procedure TestCalGrayWithoutWhitePointUsesTheUnitWhitePoint;

    [Test]
    procedure TestCalRgbWithAnotherWhitePointSkipsTheCalibration;

    [Test]
    procedure TestNamesAndComponentCounts;

    [Test]
    procedure TestInitialColors;

    [Test]
    procedure TestLabInitialColorUsesTheRange;

    [Test]
    procedure TestDefaultDecode;

    [Test]
    procedure TestNotANumberGivesBlack;

    [Test]
    procedure TestSecondElementThatIsNoDictionaryRaises;

    [Test]
    procedure TestWhitePointWithTooFewNumbersRaises;

    [Test]
    procedure TestCalRgbWithTooFewGammasOrMatrixValuesRaises;

    [Test]
    procedure TestLabRangeWithTooFewNumbersRaises;
  end;

implementation

uses
  System.Math,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Name,
  Pdf4D.Tests.Functions;

const
  // PDFBox converts through a 16-bit colour management; the reference points are within 2 of 255
  ColorTolerance = 2.0 / 255.0;
  ImageTolerance = 2;

{ TCieColorSpaceTests }

procedure TCieColorSpaceTests.Setup;
begin
  FBuilder := TColorTestBuilder.Create;
  FReferences := TColorSpaceReferences.Create;
end;

procedure TCieColorSpaceTests.TearDown;
begin
  FReferences.Free;
  FBuilder.Free;
end;

function TCieColorSpaceTests.NewCieArray(const Kind: string; const Entries: array of string): TCosArray;
begin
  const Dictionary = TCosDictionary.Create;
  for var Index := 0 to (Length(Entries) div 2) - 1 do
  begin
    Dictionary.SetItem(Entries[Index * 2], TFunctionTestBuilder.NewArray(Entries[Index * 2 + 1]));
  end;

  Result := TCosArray.Create;
  Result.Add(TCosName.Create(Kind));
  Result.Add(Dictionary);
end;

function TCieColorSpaceTests.CieSpace(const Kind: string; const Entries: array of string): TPDColorSpace;
begin
  const Items = NewCieArray(Kind, Entries);
  FBuilder.AddColorSpace('CieSpace', Items);
  Result := FBuilder.CreateSpace(FBuilder.NewName('CieSpace'));
end;

procedure TCieColorSpaceTests.TestCalRgbMatchesPdfBox;
begin
  for var SpaceName in ['CalRgbOne', 'CalRgbPlain', 'CalRgb65'] do
  begin
    FReferences.CheckColors(SpaceName, ColorTolerance);
    FReferences.CheckImages(SpaceName, ImageTolerance);
  end;
end;

procedure TCieColorSpaceTests.TestCalGrayMatchesPdfBox;
begin
  for var SpaceName in ['CalGrayDefault', 'CalGrayOne', 'CalGray65'] do
  begin
    FReferences.CheckColors(SpaceName, ColorTolerance);
    FReferences.CheckImages(SpaceName, ImageTolerance);
  end;
end;

procedure TCieColorSpaceTests.TestLabMatchesPdfBox;
begin
  for var SpaceName in ['LabD50', 'LabD65', 'LabOne'] do
  begin
    FReferences.CheckColors(SpaceName, ColorTolerance);
    FReferences.CheckImages(SpaceName, ImageTolerance);
  end;
end;

procedure TCieColorSpaceTests.TestCalGrayWithoutWhitePointUsesTheUnitWhitePoint;
begin
  // The default white point is 1 1 1, which PDFBox treats as the white point that gets the calibration: not the gray itself
  const Space = CieSpace('CalGray', ['Gamma', '1']);

  const Rgb = Space.ToRgb([0.5]);

  Assert.IsTrue(Abs(Rgb.R - Rgb.B) > 0.01, 'the XYZ conversion of 1 1 1 is not neutral');
end;

procedure TCieColorSpaceTests.TestCalRgbWithAnotherWhitePointSkipsTheCalibration;
begin
  const Space = CieSpace('CalRGB', ['WhitePoint', '0.9505 1 1.089', 'Gamma', '2.2 2.2 2.2']);

  const Rgb = Space.ToRgb([0.2, 0.4, 0.6]);

  Assert.AreEqual(Single(0.2), Rgb.R, 0.0);
  Assert.AreEqual(Single(0.4), Rgb.G, 0.0);
  Assert.AreEqual(Single(0.6), Rgb.B, 0.0);
end;

procedure TCieColorSpaceTests.TestNamesAndComponentCounts;
begin
  Assert.AreEqual('CalGray', FReferences.SpaceOf('CalGrayOne').Name);
  Assert.AreEqual(1, FReferences.SpaceOf('CalGrayOne').NumberOfComponents);
  Assert.AreEqual('CalRGB', FReferences.SpaceOf('CalRgbOne').Name);
  Assert.AreEqual(3, FReferences.SpaceOf('CalRgbOne').NumberOfComponents);
  Assert.AreEqual('Lab', FReferences.SpaceOf('LabD50').Name);
  Assert.AreEqual(3, FReferences.SpaceOf('LabD50').NumberOfComponents);
  Assert.AreSame(FReferences.SpaceOf('LabD50'), FReferences.SpaceOf('LabD50'), 'one space per array');
end;

procedure TCieColorSpaceTests.TestInitialColors;
begin
  Assert.AreEqual<Integer>(1, Length(FReferences.SpaceOf('CalGrayOne').InitialColor.Components));
  Assert.AreEqual(Single(0), FReferences.SpaceOf('CalGrayOne').InitialColor.Components[0], 0.0);
  Assert.AreEqual<Integer>(3, Length(FReferences.SpaceOf('CalRgbOne').InitialColor.Components));
  Assert.AreEqual(Single(0), FReferences.SpaceOf('CalRgbOne').InitialColor.Components[2], 0.0);
end;

procedure TCieColorSpaceTests.TestLabInitialColorUsesTheRange;
begin
  // max(0, minimum of the range) for a and b
  const Space = CieSpace('Lab', ['Range', '10 50 -30 20']);

  const Initial = Space.InitialColor.Components;

  Assert.AreEqual<Integer>(3, Length(Initial));
  Assert.AreEqual(Single(0), Initial[0], 0.0);
  Assert.AreEqual(Single(10), Initial[1], 0.0);
  Assert.AreEqual(Single(0), Initial[2], 0.0);
end;

procedure TCieColorSpaceTests.TestDefaultDecode;
begin
  const Gray = FReferences.SpaceOf('CalGrayOne').GetDefaultDecode(8);
  const Rgb = FReferences.SpaceOf('CalRgbOne').GetDefaultDecode(8);
  const Lab = FReferences.SpaceOf('LabD50').GetDefaultDecode(8);
  const DefaultRangeLab = CieSpace('Lab', ['WhitePoint', '1 1 1']).GetDefaultDecode(8);

  Assert.AreEqual<Integer>(2, Length(Gray));
  Assert.AreEqual(Single(1), Gray[1], 0.0);
  Assert.AreEqual<Integer>(6, Length(Rgb));
  Assert.AreEqual(Single(1), Rgb[5], 0.0);
  Assert.AreEqual<Integer>(6, Length(Lab));
  Assert.AreEqual(Single(100), Lab[1], 0.0);
  Assert.AreEqual(Single(-128), Lab[2], 0.0);
  Assert.AreEqual(Single(127), Lab[3], 0.0);
  Assert.AreEqual(Single(-100), DefaultRangeLab[4], 0.0);
  Assert.AreEqual(Single(100), DefaultRangeLab[5], 0.0);
end;

procedure TCieColorSpaceTests.TestNotANumberGivesBlack;
begin
  const Space = FReferences.SpaceOf('CalGrayDefault');

  const Rgb = Space.ToRgb([-0.5]);

  Assert.IsFalse(IsNan(Rgb.R), 'no not-a-number in the result');
  Assert.IsFalse(IsNan(Rgb.G));
  Assert.IsFalse(IsNan(Rgb.B));
end;

procedure TCieColorSpaceTests.TestSecondElementThatIsNoDictionaryRaises;
begin
  const Items = TCosArray.Create;
  Items.Add(TCosName.Create('CalRGB'));
  Items.Add(TCosName.Create('NoDictionary'));
  FBuilder.AddColorSpace('CieBad', Items);

  Assert.WillRaise(
    procedure
    begin
      FBuilder.CreateSpace(FBuilder.NewName('CieBad'));
    end,
    EPdfParseException);

  const OnlyKind = TCosArray.Create;
  OnlyKind.Add(TCosName.Create('Lab'));
  FBuilder.AddColorSpace('CieShort', OnlyKind);

  Assert.WillRaise(
    procedure
    begin
      FBuilder.CreateSpace(FBuilder.NewName('CieShort'));
    end,
    EPdfParseException);
end;

procedure TCieColorSpaceTests.TestWhitePointWithTooFewNumbersRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      CieSpace('CalGray', ['WhitePoint', '0.9 1']);
    end,
    EPdfParseException);
end;

procedure TCieColorSpaceTests.TestCalRgbWithTooFewGammasOrMatrixValuesRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      CieSpace('CalRGB', ['Gamma', '2.2 2.2']);
    end,
    EPdfParseException,
    'two gammas');

  Assert.WillRaise(
    procedure
    begin
      CieSpace('CalRGB', ['Matrix', '1 0 0 0 1 0 0 0']);
    end,
    EPdfParseException,
    'eight matrix values');
end;

procedure TCieColorSpaceTests.TestLabRangeWithTooFewNumbersRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      CieSpace('Lab', ['Range', '-128 127 -128']);
    end,
    EPdfParseException);
end;

end.
