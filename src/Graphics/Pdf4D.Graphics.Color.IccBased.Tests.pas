// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Tests of Pdf4D for the ICCBased colour space of PDFBox (PDICCBased, 3.0.8) and its fall back to the alternate colour space
unit Pdf4D.Graphics.Color.IccBased.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Graphics.Color,
  Pdf4D.Tests.ColorBuilder;

type
  [TestFixture]
  TIccBasedTests = class
  private
    FBuilder: TColorTestBuilder;

    class function BrokenProfile: TBytes; static;
    class procedure AssertRgb(const Expected: array of Single; const Actual: TPdfRgb; const Tolerance: Single; const Message: string = ''); static;
    // The conversion of the profile itself, without a colour space around it
    class function ConvertWithProfile(const Data: TBytes; const Input: array of Single): TArray<Single>; static;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestIccBasedWithBrokenProfileUsesAlternate;

    [Test]
    procedure TestIccBasedSrgbShortcut;

    [Test]
    procedure TestSrgbImageCopiesTheSamples;

    [Test]
    procedure TestGrayProfileMatchesTheTransform;

    [Test]
    procedure TestCmykProfileMatchesTheTransform;

    [Test]
    procedure TestImageMatchesPointConversion;

    [Test]
    procedure TestComponentCountOfTheProfileThatDiffersFromNFallsBack;

    [Test]
    procedure TestBrokenProfileWithoutAlternateUsesTheDeviceSpaceOfN;

    [Test]
    procedure TestAlternateWithOtherComponentCountIsIgnored;

    [Test]
    procedure TestBrokenProfileWithUnknownComponentCountRaises;

    [Test]
    procedure TestSecondElementThatIsNoStreamRaises;

    [Test]
    procedure TestInitialColorUsesTheRange;

    [Test]
    procedure TestDefaultDecodeIsThatOfTheAlternate;

    [Test]
    procedure TestMissingNTakesTheComponentsOfTheProfile;
  end;

implementation

uses
  System.IOUtils,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Graphics.Color.IccBased,
  Pdf4D.Graphics.Icc.Profile,
  Pdf4D.Graphics.Icc.Transform,
  Pdf4D.Render.Bitmap,
  Pdf4D.Tests.Functions,
  Pdf4D.Tests.IccBuilder;

const
  MaxDifferenceToJava = 0.25 / 255.0;

{ TIccBasedTests }

procedure TIccBasedTests.Setup;
begin
  FBuilder := TColorTestBuilder.Create;
end;

procedure TIccBasedTests.TearDown;
begin
  FBuilder.Free;
end;

class function TIccBasedTests.BrokenProfile: TBytes;
begin
  SetLength(Result, 200);
  for var Index := 0 to Length(Result) - 1 do
  begin
    Result[Index] := Byte(Index * 7);
  end;
end;

class procedure TIccBasedTests.AssertRgb(const Expected: array of Single; const Actual: TPdfRgb; const Tolerance: Single; const Message: string);
begin
  Assert.AreEqual(Expected[0], Actual.R, Tolerance, Message + ' red');
  Assert.AreEqual(Expected[1], Actual.G, Tolerance, Message + ' green');
  Assert.AreEqual(Expected[2], Actual.B, Tolerance, Message + ' blue');
end;

class function TIccBasedTests.ConvertWithProfile(const Data: TBytes; const Input: array of Single): TArray<Single>;
begin
  const Profile = TIccProfile.Parse(Data);
  try
    const Transform = TIccTransform.Create(Profile);
    try
      SetLength(Result, 3);
      Transform.ToRgb(@Input[0], @Result[0]);
    finally
      Transform.Free;
    end;
  finally
    Profile.Free;
  end;
end;

procedure TIccBasedTests.TestIccBasedWithBrokenProfileUsesAlternate;
begin
  const IccArray = FBuilder.NewIccArray(BrokenProfile, 3, 'DeviceRGB');

  const Space = FBuilder.CreateSpace(IccArray);
  const Again = FBuilder.CreateSpace(IccArray);

  Assert.AreEqual('ICCBased', Space.Name);
  Assert.AreEqual(3, Space.NumberOfComponents);
  AssertRgb([0.2, 0.4, 0.6], Space.ToRgb([0.2, 0.4, 0.6]), 0.0);
  AssertRgb([1, 0, 0], Space.ToRgb([3, -1, 0]), 0.0);
  Assert.AreEqual(1, FBuilder.WarningCount, 'one warning');
  Assert.AreSame(Space, Again);
end;

procedure TIccBasedTests.TestIccBasedSrgbShortcut;
begin
  const Data = TColorTestBuilder.SrgbModelProfile;
  const Profile = TIccProfile.Parse(Data);
  try
    Assert.IsTrue(Profile.IsSRGB, 'the test profile has the model sRGB');
  finally
    Profile.Free;
  end;
  const Space = FBuilder.CreateSpace(FBuilder.NewIccArray(Data, 3));
  const Device = FBuilder.CreateSpace(FBuilder.NewName('DeviceRGB'));

  AssertRgb([0.3, 0.6, 0.9], Space.ToRgb([0.3, 0.6, 0.9]), 0.0);
  AssertRgb([0.2, 0.0, 1.0], Space.ToRgb([0.2, -3, 4]), 0.0);
  AssertRgb([0.3, 0.6, 0.9], Device.ToRgb([0.3, 0.6, 0.9]), 0.0);
  Assert.AreEqual(0, FBuilder.WarningCount);
end;

procedure TIccBasedTests.TestSrgbImageCopiesTheSamples;
begin
  const Space = FBuilder.CreateSpace(FBuilder.NewIccArray(TColorTestBuilder.SrgbModelProfile, 3));
  const Raster = TPdfRaster.Create(2, 1, 3);
  try
    const Samples: TArray<Byte> = [1, 2, 3, 250, 251, 252];
    Move(Samples[0], Raster.Samples[0], Length(Samples));

    const Image = Space.ToRgbImage(Raster);
    try
      Assert.AreEqual(1, Integer(Image.GetPixel(0, 0).R));
      Assert.AreEqual(3, Integer(Image.GetPixel(0, 0).B));
      Assert.AreEqual(251, Integer(Image.GetPixel(1, 0).G));
      Assert.AreEqual(255, Integer(Image.GetPixel(1, 0).A));
    finally
      Image.Free;
    end;
  finally
    Raster.Free;
  end;
end;

procedure TIccBasedTests.TestGrayProfileMatchesTheTransform;
begin
  const Data = TIccTestFiles.ReadProfile('gray-gamma.icc');
  const Space = FBuilder.CreateSpace(FBuilder.NewIccArray(Data, 1));

  for var Level in [0.0, 0.25, 0.5, 1.0] do
  begin
    const Expected = ConvertWithProfile(Data, [Level]);

    AssertRgb(Expected, Space.ToRgb([Level]), MaxDifferenceToJava, Format('level %g', [Level]));
  end;
  Assert.AreEqual(0, FBuilder.WarningCount);
end;

procedure TIccBasedTests.TestCmykProfileMatchesTheTransform;
begin
  const Data = TIccTestFiles.ReadProfile('cmyk-printer.icc');
  const Space = FBuilder.CreateSpace(FBuilder.NewIccArray(Data, 4));
  const Input: TArray<Single> = [0.1, 0.6, 0.3, 0.2];

  const Expected = ConvertWithProfile(Data, Input);

  AssertRgb(Expected, Space.ToRgb(Input), MaxDifferenceToJava);
  Assert.AreEqual(4, Space.NumberOfComponents);
end;

procedure TIccBasedTests.TestImageMatchesPointConversion;
begin
  const Space = FBuilder.CreateSpace(FBuilder.NewIccArray(TIccTestFiles.ReadProfile('cmyk-printer.icc'), 4));
  const Samples: TArray<Byte> = [0, 0, 0, 0, 255, 0, 0, 0, 0, 128, 255, 64, 10, 200, 30, 255];
  const Raster = TPdfRaster.Create(2, 2, 4);
  try
    Move(Samples[0], Raster.Samples[0], Length(Samples));

    const Image = Space.ToRgbImage(Raster);
    try
      for var Pixel := 0 to 3 do
      begin
        const Input: TArray<Single> = [Samples[Pixel * 4] / 255, Samples[Pixel * 4 + 1] / 255, Samples[Pixel * 4 + 2] / 255, Samples[Pixel * 4 + 3] / 255];
        const Expected = Space.ToRgb(Input).ToDeviceColor;
        const Actual = Image.GetPixel(Pixel mod 2, Pixel div 2);

        Assert.IsTrue(Abs(Integer(Expected.R) - Integer(Actual.R)) <= 1, Format('red of pixel %d', [Pixel]));
        Assert.IsTrue(Abs(Integer(Expected.G) - Integer(Actual.G)) <= 1, Format('green of pixel %d', [Pixel]));
        Assert.IsTrue(Abs(Integer(Expected.B) - Integer(Actual.B)) <= 1, Format('blue of pixel %d', [Pixel]));
        Assert.AreEqual(255, Integer(Actual.A));
      end;
    finally
      Image.Free;
    end;
  finally
    Raster.Free;
  end;
end;

procedure TIccBasedTests.TestComponentCountOfTheProfileThatDiffersFromNFallsBack;
begin
  const Space = FBuilder.CreateSpace(FBuilder.NewIccArray(TIccTestFiles.ReadProfile('gray-gamma.icc'), 3));

  AssertRgb([0.2, 0.4, 0.6], Space.ToRgb([0.2, 0.4, 0.6]), 0.0);
  Assert.AreEqual(3, Space.NumberOfComponents);
  Assert.AreEqual(1, FBuilder.WarningCount);
end;

procedure TIccBasedTests.TestBrokenProfileWithoutAlternateUsesTheDeviceSpaceOfN;
begin
  const Gray = FBuilder.CreateSpace(FBuilder.NewIccArray(BrokenProfile, 1));
  const Cmyk = FBuilder.CreateSpace(FBuilder.NewIccArray(BrokenProfile, 4));
  const DeviceCmyk = FBuilder.CreateSpace(FBuilder.NewName('DeviceCMYK'));
  const Input: TArray<Single> = [0.5, 0, 0.5, 0];

  AssertRgb([0.7, 0.7, 0.7], Gray.ToRgb([0.7]), 0.0);
  const Expected = DeviceCmyk.ToRgb(Input);
  AssertRgb([Expected.R, Expected.G, Expected.B], Cmyk.ToRgb(Input), 0.0);
  Assert.AreEqual(2, FBuilder.WarningCount);
end;

procedure TIccBasedTests.TestAlternateWithOtherComponentCountIsIgnored;
begin
  const Space = FBuilder.CreateSpace(FBuilder.NewIccArray(BrokenProfile, 3, 'DeviceGray'));

  Assert.AreEqual(3, Space.NumberOfComponents);
  AssertRgb([0.1, 0.2, 0.3], Space.ToRgb([0.1, 0.2, 0.3]), 0.0);
end;

procedure TIccBasedTests.TestBrokenProfileWithUnknownComponentCountRaises;
begin
  const IccArray = FBuilder.NewIccArray(BrokenProfile, 2);

  Assert.WillRaise(
    procedure
    begin
      FBuilder.CreateSpace(IccArray);
    end,
    EPdfParseException);
end;

procedure TIccBasedTests.TestSecondElementThatIsNoStreamRaises;
begin
  const WithName = TCosArray.Create;
  WithName.Add(TCosName.Create(TCosNames.ICCBased));
  WithName.Add(TCosName.Create('DeviceRGB'));
  FBuilder.AddColorSpace('CSName', WithName);
  const Short = TCosArray.Create;
  Short.Add(TCosName.Create(TCosNames.ICCBased));
  FBuilder.AddColorSpace('CSShort', Short);

  Assert.WillRaise(
    procedure
    begin
      FBuilder.CreateSpace(WithName);
    end,
    EPdfParseException,
    'second element is a name');
  Assert.WillRaise(
    procedure
    begin
      FBuilder.CreateSpace(Short);
    end,
    EPdfParseException,
    'only one element');
end;

procedure TIccBasedTests.TestInitialColorUsesTheRange;
begin
  const IccArray = FBuilder.NewIccArray(TIccTestFiles.ReadProfile('gray-gamma.icc'), 1);
  FBuilder.IccStreamOf(IccArray).SetItem(TCosNames.Range, TFunctionTestBuilder.NewArray('0.25 1'));
  const NegativeArray = FBuilder.NewIccArray(TIccTestFiles.ReadProfile('sRGB.icc'), 3);
  FBuilder.IccStreamOf(NegativeArray).SetItem(TCosNames.Range, TFunctionTestBuilder.NewArray('-1 1 0.5 1 0 1'));

  const Narrow = FBuilder.CreateSpace(IccArray).InitialColor;
  const Wide = FBuilder.CreateSpace(NegativeArray).InitialColor;

  Assert.AreEqual<Integer>(1, Length(Narrow.Components));
  Assert.AreEqual(0.25, Narrow.Components[0], 0.0);
  Assert.AreEqual<Integer>(3, Length(Wide.Components));
  Assert.AreEqual(0.0, Wide.Components[0], 0.0);
  Assert.AreEqual(0.5, Wide.Components[1], 0.0);
  Assert.AreEqual(0.0, Wide.Components[2], 0.0);
end;

procedure TIccBasedTests.TestDefaultDecodeIsThatOfTheAlternate;
begin
  const Space = FBuilder.CreateSpace(FBuilder.NewIccArray(TIccTestFiles.ReadProfile('sRGB.icc'), 3));

  const Decode = Space.GetDefaultDecode(8);

  Assert.AreEqual<Integer>(6, Length(Decode));
  Assert.AreEqual(0.0, Decode[0], 0.0);
  Assert.AreEqual(1.0, Decode[5], 0.0);
end;

procedure TIccBasedTests.TestMissingNTakesTheComponentsOfTheProfile;
begin
  const IccArray = FBuilder.NewIccArray(TIccTestFiles.ReadProfile('gray-gamma.icc'), 1);
  FBuilder.IccStreamOf(IccArray).RemoveItem(TCosNames.N);

  const Space = FBuilder.CreateSpace(IccArray);

  Assert.AreEqual(1, Space.NumberOfComponents);
  Assert.AreEqual(0, FBuilder.WarningCount);
end;

end.
