// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Tests of Pdf4D for the colour, the device colour spaces and the factory of PDColorSpace, PDColor, PDDeviceGray, PDDeviceRGB
// and PDDeviceCMYK (3.0.8); the reference values (tests/reference/color) come from the Java used by PDFBox
unit Pdf4D.Graphics.Color.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Graphics.Color,
  Pdf4D.Tests.ColorBuilder;

type
  [TestFixture]
  TColorTests = class
  private
    FBuilder: TColorTestBuilder;

    function SpaceOf(const Name: string): TPDColorSpace;
    class procedure AssertRgb(const Expected: array of Single; const Actual: TPdfRgb; const Tolerance: Single; const Message: string = ''); static;
    class procedure AssertByte(const Expected, Actual: Integer; const Tolerance: Integer; const Message: string); static;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestDeviceGrayHalf;

    [Test]
    procedure TestDeviceRgbClamps;

    [Test]
    procedure TestDeviceCmykMatchesJava;

    [Test]
    procedure TestDeviceCmykImageMatchesPointConversion;

    [Test]
    procedure TestDeviceGrayAndRgbImages;

    [Test]
    procedure TestDefaultRgbResourceReplacesDeviceRgb;

    [Test]
    procedure TestDefaultResourceThatNamesTheDeviceSpaceDoesNotRecurse;

    [Test]
    procedure TestColorSpaceIsCachedPerDocument;

    [Test]
    procedure TestWrongComponentCountIsHandledLikePdfBox;

    [Test]
    procedure TestInitialColors;

    [Test]
    procedure TestDefaultDecode;

    [Test]
    procedure TestDeviceSpacesAreSharedAcrossResources;

    [Test]
    procedure TestRgbToDeviceColorRoundsLikeJava;

    [Test]
    procedure TestRasterWithWrongComponentsRaises;

    [Test]
    procedure TestUnsupportedColorSpacesRaiseUnsupported;

    [Test]
    procedure TestInvalidColorSpacesRaiseParseException;

    [Test]
    procedure TestTryGetColorSpace;

    [Test]
    procedure TestDeviceSpaceInArrayIsAccepted;

    [Test]
    procedure TestNamedResourceIsResolved;
  end;

implementation

uses
  System.IOUtils,
  System.Math,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Cos.Name,
  Pdf4D.Graphics.Color.Device,
  Pdf4D.Graphics.Color.Factory,
  Pdf4D.Render.Bitmap,
  Pdf4D.Tests.Functions,
  Pdf4D.Tests.IccBuilder;

const
  // The difference to Java that the tests accept per channel (see the tests of the ICC transform)
  MaxDifferenceToJava = 0.25 / 255.0;

{ TColorTests }

procedure TColorTests.Setup;
begin
  FBuilder := TColorTestBuilder.Create;
end;

procedure TColorTests.TearDown;
begin
  FBuilder.Free;
end;

function TColorTests.SpaceOf(const Name: string): TPDColorSpace;
begin
  Result := FBuilder.CreateSpace(FBuilder.NewName(Name));
end;

class procedure TColorTests.AssertRgb(const Expected: array of Single; const Actual: TPdfRgb; const Tolerance: Single; const Message: string);
begin
  Assert.AreEqual(Expected[0], Actual.R, Tolerance, Message + ' red');
  Assert.AreEqual(Expected[1], Actual.G, Tolerance, Message + ' green');
  Assert.AreEqual(Expected[2], Actual.B, Tolerance, Message + ' blue');
end;

class procedure TColorTests.AssertByte(const Expected, Actual: Integer; const Tolerance: Integer; const Message: string);
begin
  Assert.IsTrue(Abs(Expected - Actual) <= Tolerance, Format('%s: expected %d, got %d', [Message, Expected, Actual]));
end;

procedure TColorTests.TestDeviceGrayHalf;
begin
  const Space = SpaceOf('DeviceGray');

  const Rgb = Space.ToRgb([0.5]);
  const Device = Rgb.ToDeviceColor;

  AssertRgb([0.5, 0.5, 0.5], Rgb, 0.0);
  Assert.AreEqual(128, Integer(Device.R));
  Assert.AreEqual(128, Integer(Device.G));
  Assert.AreEqual(128, Integer(Device.B));
  Assert.AreEqual(255, Integer(Device.A));
end;

procedure TColorTests.TestDeviceRgbClamps;
begin
  const Space = SpaceOf('DeviceRGB');

  AssertRgb([1, 0, 0.5], Space.ToRgb([1.5, -1, 0.5]), 0.0);
end;

procedure TColorTests.TestDeviceCmykMatchesJava;
begin
  const Space = SpaceOf('DeviceCMYK');
  var Lines: TArray<string> := [];
  for var Line in TFile.ReadAllLines(TPath.Combine(TIccTestFiles.ReferenceFolder, 'DeviceCMYK.txt')) do
  begin
    if Line.StartsWith('in:') then
    begin
      Lines := Lines + [Line];
    end;
  end;
  Assert.IsTrue(Length(Lines) >= 5, 'the reference file has too few points');

  for var Step := 0 to 4 do
  begin
    const Line = Lines[(Step * (Length(Lines) - 1)) div 4];
    const Parts = Line.Substring(3).Split([' out:']);
    const Input = TFunctionTestBuilder.ParseSingles(Parts[0]);
    const Expected = TFunctionTestBuilder.ParseSingles(Parts[1]);

    AssertRgb(Expected, Space.ToRgb(Input), MaxDifferenceToJava, Line);
  end;
end;

procedure TColorTests.TestDeviceCmykImageMatchesPointConversion;
begin
  const Space = SpaceOf('DeviceCMYK');
  const Samples: TArray<Byte> = [0, 0, 0, 0, 255, 0, 0, 0, 0, 128, 255, 64, 10, 200, 30, 255];
  const Raster = TPdfRaster.Create(2, 2, 4);
  try
    Move(Samples[0], Raster.Samples[0], Length(Samples));

    const Image = Space.ToRgbImage(Raster);
    try
      Assert.AreEqual(2, Image.Width);
      Assert.AreEqual(2, Image.Height);
      for var Pixel := 0 to 3 do
      begin
        const Input: TArray<Single> = [Samples[Pixel * 4] / 255, Samples[Pixel * 4 + 1] / 255, Samples[Pixel * 4 + 2] / 255, Samples[Pixel * 4 + 3] / 255];
        const Expected = Space.ToRgb(Input).ToDeviceColor;
        const Actual = Image.GetPixel(Pixel mod 2, Pixel div 2);

        AssertByte(Expected.R, Actual.R, 1, Format('red of pixel %d', [Pixel]));
        AssertByte(Expected.G, Actual.G, 1, Format('green of pixel %d', [Pixel]));
        AssertByte(Expected.B, Actual.B, 1, Format('blue of pixel %d', [Pixel]));
        Assert.AreEqual(255, Integer(Actual.A));
      end;
    finally
      Image.Free;
    end;
  finally
    Raster.Free;
  end;
end;

procedure TColorTests.TestDeviceGrayAndRgbImages;
begin
  const GrayRaster = TPdfRaster.Create(3, 1, 1);
  const RgbRaster = TPdfRaster.Create(2, 1, 3);
  try
    GrayRaster.Samples[0] := 0;
    GrayRaster.Samples[1] := 100;
    GrayRaster.Samples[2] := 255;
    const RgbSamples: TArray<Byte> = [10, 20, 30, 255, 128, 0];
    Move(RgbSamples[0], RgbRaster.Samples[0], Length(RgbSamples));

    const GrayImage = SpaceOf('DeviceGray').ToRgbImage(GrayRaster);
    try
      const RgbImage = SpaceOf('DeviceRGB').ToRgbImage(RgbRaster);
      try
        Assert.AreEqual(100, Integer(GrayImage.GetPixel(1, 0).G));
        Assert.AreEqual(255, Integer(GrayImage.GetPixel(2, 0).B));
        Assert.AreEqual(255, Integer(GrayImage.GetPixel(0, 0).A));
        Assert.AreEqual(20, Integer(RgbImage.GetPixel(0, 0).G));
        Assert.AreEqual(128, Integer(RgbImage.GetPixel(1, 0).G));
        Assert.AreEqual(255, Integer(RgbImage.GetPixel(1, 0).A));
      finally
        RgbImage.Free;
      end;
    finally
      GrayImage.Free;
    end;
  finally
    RgbRaster.Free;
    GrayRaster.Free;
  end;
end;

procedure TColorTests.TestDefaultRgbResourceReplacesDeviceRgb;
begin
  const Plain = SpaceOf('DeviceRGB');
  Assert.AreEqual('DeviceRGB', Plain.Name);
  const Profile = TIccTestFiles.ReadProfile('sRGB.icc');
  FBuilder.AddColorSpace('DefaultRGB', FBuilder.NewIccArray(Profile, 3));

  const Replaced = SpaceOf('DeviceRGB');
  const Forced = FBuilder.CreateSpace(FBuilder.NewName('DeviceRGB'), True);

  Assert.AreEqual('ICCBased', Replaced.Name);
  Assert.AreEqual('DeviceRGB', Forced.Name);
end;

procedure TColorTests.TestDefaultResourceThatNamesTheDeviceSpaceDoesNotRecurse;
begin
  FBuilder.AddColorSpace('DefaultGray', TCosName.Create('DeviceGray'));
  FBuilder.AddColorSpace('DefaultCMYK', TCosName.Create('DeviceCMYK'));

  Assert.AreEqual('DeviceGray', SpaceOf('DeviceGray').Name);
  Assert.AreEqual('DeviceCMYK', SpaceOf('DeviceCMYK').Name);
end;

procedure TColorTests.TestColorSpaceIsCachedPerDocument;
begin
  const Profile = TIccTestFiles.ReadProfile('gray-gamma.icc');
  const IccArray = FBuilder.NewIccArray(Profile, 1);

  const First = FBuilder.CreateSpace(IccArray);
  const Second = FBuilder.CreateSpace(IccArray);

  Assert.AreSame(First, Second);
  Assert.AreSame(SpaceOf('DeviceGray'), SpaceOf('DeviceGray'));
end;

procedure TColorTests.TestWrongComponentCountIsHandledLikePdfBox;
begin
  const Gray = TPDColor.Create(SpaceOf('DeviceGray'), [0.5, 0.2]);
  const Rgb = TPDColor.Create(SpaceOf('DeviceRGB'), [1]);
  const Empty = TPDColor.Create(SpaceOf('DeviceGray'), []);
  const Outside = TPDColor.Create(SpaceOf('DeviceGray'), [2]);
  const NotANumber = TPDColor.Create(SpaceOf('DeviceGray'), [NaN]);

  AssertRgb([0.5, 0.5, 0.5], Gray.ToRgb, 0.0, 'extra component is ignored');
  AssertRgb([1, 0, 0], Rgb.ToRgb, 0.0, 'missing components are 0');
  AssertRgb([0, 0, 0], Empty.ToRgb, 0.0, 'no components');
  AssertRgb([1, 1, 1], Outside.ToRgb, 0.0, 'above 1');
  AssertRgb([0, 0, 0], NotANumber.ToRgb, 0.0, 'not a number');
end;

procedure TColorTests.TestInitialColors;
begin
  const Gray = SpaceOf('DeviceGray').InitialColor;
  const Rgb = SpaceOf('DeviceRGB').InitialColor;
  const Cmyk = SpaceOf('DeviceCMYK').InitialColor;

  Assert.AreEqual<Integer>(1, Length(Gray.Components));
  Assert.AreEqual(0.0, Gray.Components[0], 0.0);
  Assert.AreEqual<Integer>(3, Length(Rgb.Components));
  Assert.AreEqual<Integer>(4, Length(Cmyk.Components));
  Assert.AreEqual(1.0, Cmyk.Components[3], 0.0);
  Assert.AreEqual(0.0, Cmyk.Components[0], 0.0);
  Assert.AreSame(SpaceOf('DeviceCMYK'), Cmyk.ColorSpace);
  Assert.AreEqual('', Cmyk.PatternName);
end;

procedure TColorTests.TestDefaultDecode;
begin
  const Rgb = SpaceOf('DeviceRGB').GetDefaultDecode(8);
  const Gray = SpaceOf('DeviceGray').GetDefaultDecode(1);

  Assert.AreEqual<Integer>(6, Length(Rgb));
  Assert.AreEqual(1.0, Rgb[5], 0.0);
  Assert.AreEqual(0.0, Rgb[4], 0.0);
  Assert.AreEqual<Integer>(2, Length(Gray));
  Assert.AreEqual(1.0, Gray[1], 0.0);
end;

procedure TColorTests.TestDeviceSpacesAreSharedAcrossResources;
begin
  const OtherBuilder = TColorTestBuilder.Create;
  try
    const Other = OtherBuilder.CreateSpace(OtherBuilder.NewName('DeviceCMYK'));

    Assert.AreSame(SpaceOf('DeviceCMYK'), Other);
    Assert.AreSame(TPDDeviceCMYK.Instance, Other);
  finally
    OtherBuilder.Free;
  end;
end;

procedure TColorTests.TestRgbToDeviceColorRoundsLikeJava;
begin
  const Color = TPdfRgb.Create(0.2, 0.4, 1.0).ToDeviceColor;
  const Beyond = TPdfRgb.Create(-0.5, 2.0, 0.5).ToDeviceColor;

  Assert.AreEqual(51, Integer(Color.R));
  Assert.AreEqual(102, Integer(Color.G));
  Assert.AreEqual(255, Integer(Color.B));
  Assert.AreEqual(0, Integer(Beyond.R));
  Assert.AreEqual(255, Integer(Beyond.G));
  Assert.AreEqual(128, Integer(Beyond.B));
end;

procedure TColorTests.TestRasterWithWrongComponentsRaises;
begin
  const Raster = TPdfRaster.Create(1, 1, 3);
  try
    Assert.WillRaise(
      procedure
      begin
        SpaceOf('DeviceCMYK').ToRgbImage(Raster).Free;
      end,
      EArgumentException);
    Assert.WillRaise(
      procedure
      begin
        TPdfRaster.Create(0, 1, 3).Free;
      end,
      EArgumentOutOfRangeException);
  finally
    Raster.Free;
  end;
end;

procedure TColorTests.TestUnsupportedColorSpacesRaiseUnsupported;
begin
  Assert.WillRaise(
    procedure
    begin
      SpaceOf('Pattern');
    end,
    EPdfUnsupportedFeatureException);

  const LabArray = TCosArray.Create;
  LabArray.Add(TCosName.Create('Lab'));
  LabArray.Add(TCosDictionary.Create);
  FBuilder.AddColorSpace('CSLab', LabArray);
  Assert.WillRaise(
    procedure
    begin
      SpaceOf('CSLab');
    end,
    EPdfUnsupportedFeatureException);
end;

procedure TColorTests.TestInvalidColorSpacesRaiseParseException;
begin
  Assert.WillRaise(
    procedure
    begin
      SpaceOf('NoSuchResource');
    end,
    EPdfParseException,
    'a name that is no colour space and has no resource');

  const EmptyArray = TCosArray.Create;
  FBuilder.AddColorSpace('CSEmpty', EmptyArray);
  Assert.WillRaise(
    procedure
    begin
      SpaceOf('CSEmpty');
    end,
    EPdfParseException,
    'an empty array');

  const UnknownKind = TCosArray.Create;
  UnknownKind.Add(TCosName.Create('Foo'));
  FBuilder.AddColorSpace('CSFoo', UnknownKind);
  Assert.WillRaise(
    procedure
    begin
      SpaceOf('CSFoo');
    end,
    EPdfParseException,
    'an unknown kind');

  Assert.WillRaise(
    procedure
    begin
      TPDColorSpaceFactory.Create(nil, FBuilder.Resources);
    end,
    EPdfParseException,
    'nil');
end;

procedure TColorTests.TestTryGetColorSpace;
begin
  FBuilder.AddColorSpace('CS0', TCosName.Create('DeviceRGB'));
  var Value: TCosBase;

  Assert.IsTrue(FBuilder.Resources.TryGetColorSpace('CS0', Value));
  Assert.IsTrue(Value is TCosName);
  Assert.IsFalse(FBuilder.Resources.TryGetColorSpace('CS1', Value));
  Assert.IsNull(Value);
end;

procedure TColorTests.TestDeviceSpaceInArrayIsAccepted;
begin
  const Wrapped = TCosArray.Create;
  Wrapped.Add(TCosName.Create('DeviceRGB'));
  FBuilder.AddColorSpace('CSWrapped', Wrapped);

  Assert.AreEqual('DeviceRGB', FBuilder.CreateSpace(Wrapped).Name);

  const Abbreviated = TCosArray.Create;
  Abbreviated.Add(TCosName.Create('G'));
  FBuilder.AddColorSpace('CSG', Abbreviated);
  Assert.AreEqual('DeviceGray', FBuilder.CreateSpace(Abbreviated).Name);
end;

procedure TColorTests.TestNamedResourceIsResolved;
begin
  FBuilder.AddColorSpace('CS0', TCosName.Create('DeviceCMYK'));

  const Space = SpaceOf('CS0');

  Assert.AreEqual('DeviceCMYK', Space.Name);
  Assert.AreEqual(4, Space.NumberOfComponents);
end;

end.
