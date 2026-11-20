// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of the ICC profile parser (ICC.1:2010): the header, the tag table, the transforms of a profile and hostile data
unit Pdf4D.Graphics.Icc.Profile.Tests;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Common.Defines,
  Pdf4D.Graphics.Icc.Profile,
  Pdf4D.Graphics.Icc.Transform,
  Pdf4D.Resources.Icc,
  Pdf4D.Tests.IccBuilder;

type
  [TestFixture]
  TIccProfileTests = class
  private
    class function RgbProfile(const Model: string): TBytes; static;
    class function SimpleLutProfile(const Signature: string; const Inputs: Integer): TBytes; static;
    class function LutProfile(const DeviceClass, ColorSpace, Pcs: string; const Lut: TBytes; const TagSignature: string = 'A2B0'): TBytes; static;
    class procedure AssertParseRaises(const Data: TBytes; const Message: string); static;
    class procedure AssertOnlyParseErrors(const Data: TBytes; const Mutations: Integer; const Seed: Cardinal); static;
    class procedure UseProfile(const Data: TBytes); static;

  public
    [Test]
    procedure TestParseCmykProfile;

    [Test]
    procedure TestParseRgbMatrixProfile;

    [Test]
    procedure TestParseGrayProfile;

    [Test]
    [TestCase('Gray', 'GRAY,1,Gray')]
    [TestCase('Rgb', 'RGB ,3,Rgb')]
    [TestCase('Cmyk', 'CMYK,4,Cmyk')]
    [TestCase('Lab', 'Lab ,3,Lab')]
    [TestCase('Xyz', 'XYZ ,3,Other')]
    [TestCase('ThreeColours', '3CLR,3,Other')]
    [TestCase('FiveColours', '5CLR,5,Other')]
    [TestCase('FifteenColours', 'FCLR,15,Other')]
    procedure TestColorSpaceOfTheHeader(const Signature: string; const ExpectedComponents: Integer; const ExpectedSpace: string);

    [Test]
    procedure TestIsSrgbReadsTheDeviceModelOfTheHeader;

    [Test]
    procedure TestProfileWithoutSignatureRaisesParseError;

    [Test]
    procedure TestProfileOfAnUnknownColorSpaceRaisesParseError;

    [Test]
    procedure TestProfileOfAnUnknownPcsRaisesParseError;

    [Test]
    procedure TestProfileWithoutTagsForItsClassRaisesParseError;

    [Test]
    procedure TestTagOutsideTheDataRaisesParseError;

    [Test]
    procedure TestTagTableLargerThanTheDataRaisesParseError;

    [Test]
    procedure TestTruncatedProfileRaisesParseError;

    [Test]
    procedure TestProfileOverTheSizeLimitRaisesParseError;

    [Test]
    procedure TestHugeClutIsRejected;

    [Test]
    procedure TestMoreThanSixteenInputChannelsAreRejected;

    [Test]
    procedure TestCurveWithMoreEntriesThanItsTagRaisesParseError;

    [Test]
    procedure TestCorruptedProfilesOnlyRaiseParseErrors;
  end;

implementation

uses
  System.Math,
  System.TypInfo;

{ TIccProfileTests }

class function TIccProfileTests.RgbProfile(const Model: string): TBytes;
begin
  const Profile = TIccTestProfile.Create('mntr', 'RGB ', 'XYZ ');
  try
    Profile.Model := Model;
    Profile.AddTag('rXYZ', TIccTestTags.Xyz(0.4358521, 0.2223816, 0.0139160));
    Profile.AddTag('gXYZ', TIccTestTags.Xyz(0.3853302, 0.7170410, 0.0971375));
    Profile.AddTag('bXYZ', TIccTestTags.Xyz(0.1430206, 0.0605927, 0.7138367));
    Profile.AddTag('rTRC', TIccTestTags.SrgbCurve);
    Profile.AddTag('gTRC', TIccTestTags.SrgbCurve);
    Profile.AddTag('bTRC', TIccTestTags.SrgbCurve);
    Result := Profile.Build;
  finally
    Profile.Free;
  end;
end;

// A profile with an A2B0 of type lut16 that has Inputs inputs, 2 grid points and Lab as PCS
class function TIccProfileTests.SimpleLutProfile(const Signature: string; const Inputs: Integer): TBytes;
begin
  var InputTables: TArray<Word>;
  SetLength(InputTables, Inputs * 2);
  for var Index := 0 to Inputs - 1 do
  begin
    InputTables[Index * 2 + 1] := 65535;
  end;
  var Clut: TArray<Word>;
  SetLength(Clut, (1 shl Inputs) * 3);
  const OutputTables = TArray<Word>.Create(0, 65535, 0, 65535, 0, 65535);

  Result := LutProfile('scnr', Signature, 'Lab ', TIccTestTags.Lut16(Inputs, 3, 2, 2, 2, InputTables, Clut, OutputTables));
end;

class function TIccProfileTests.LutProfile(const DeviceClass, ColorSpace, Pcs: string; const Lut: TBytes; const TagSignature: string): TBytes;
begin
  const Profile = TIccTestProfile.Create(DeviceClass, ColorSpace, Pcs);
  try
    Profile.AddTag(TagSignature, Lut);
    Result := Profile.Build;
  finally
    Profile.Free;
  end;
end;

class procedure TIccProfileTests.AssertParseRaises(const Data: TBytes; const Message: string);
begin
  Assert.WillRaise(
    procedure
    begin
      TIccProfile.Parse(Data).Free;
    end, EPdfParseException, Message);
end;

class procedure TIccProfileTests.UseProfile(const Data: TBytes);
begin
  const Profile = TIccProfile.Parse(Data);
  try
    const Transform = TIccTransform.Create(Profile);
    try
      var Input: array[0..15] of Single;
      var Output: array[0..2] of Single;
      for var Value in [0.0, 0.3, 1.0, 7.0] do
      begin
        for var Index := 0 to High(Input) do
        begin
          Input[Index] := Value;
        end;
        Transform.ToRgb(@Input[0], @Output[0]);
      end;
    finally
      Transform.Free;
    end;
  finally
    Profile.Free;
  end;
end;

// A profile that was changed in a few places either parses or gives EPdfParseException; any other exception is a failure
class procedure TIccProfileTests.AssertOnlyParseErrors(const Data: TBytes; const Mutations: Integer; const Seed: Cardinal);
begin
  var State := Seed;
  for var Round := 1 to Mutations do
  begin
    var Changed := Copy(Data);
    const Changes = 1 + (Round mod 4);
    for var Change := 1 to Changes do
    begin
      State := Cardinal((UInt64(State) * 1103515245 + 12345) and $FFFFFFFF);
      // The header and the tag table are the interesting part, so half of the changes land in the first 400 bytes
      var Position: Integer;
      if (State shr 30) = 0 then
      begin
        Position := Integer((State shr 4) mod Cardinal(Length(Changed)));
      end
      else
      begin
        Position := Integer((State shr 4) mod Cardinal(Min(400, Length(Changed))));
      end;
      State := Cardinal((UInt64(State) * 1103515245 + 12345) and $FFFFFFFF);
      Changed[Position] := Byte(State shr 16);
    end;

    try
      UseProfile(Changed);
    except
      on EPdfParseException do
      begin
        // an unusable profile is the expected outcome
      end;
    end;
  end;
end;

procedure TIccProfileTests.TestParseCmykProfile;
begin
  const Profile = TIccProfile.Parse(TPdfIccResources.CmykProfile);
  try
    var TypeSignature: string;
    const HasA2B0 = Profile.TryGetTagType('A2B0', TypeSignature);

    Assert.AreEqual<TIccColorSpace>(TIccColorSpace.Cmyk, Profile.ColorSpace);
    Assert.AreEqual(4, Profile.NumberOfComponents);
    Assert.IsTrue(HasA2B0);
    Assert.AreEqual('mft2', TypeSignature);
    Assert.IsFalse(Profile.IsSRGB);
  finally
    Profile.Free;
  end;
end;

procedure TIccProfileTests.TestParseRgbMatrixProfile;
begin
  const Profile = TIccProfile.Parse(RgbProfile('sRGB'));
  try
    Assert.AreEqual<TIccColorSpace>(TIccColorSpace.Rgb, Profile.ColorSpace);
    Assert.AreEqual(3, Profile.NumberOfComponents);
  finally
    Profile.Free;
  end;
end;

procedure TIccProfileTests.TestParseGrayProfile;
begin
  const Profile = TIccProfile.Parse(TIccTestFiles.ReadProfile('gray-small.icc'));
  try
    Assert.AreEqual<TIccColorSpace>(TIccColorSpace.Gray, Profile.ColorSpace);
    Assert.AreEqual(1, Profile.NumberOfComponents);
  finally
    Profile.Free;
  end;
end;

procedure TIccProfileTests.TestColorSpaceOfTheHeader(const Signature: string; const ExpectedComponents: Integer; const ExpectedSpace: string);
begin
  const Profile = TIccProfile.Parse(SimpleLutProfile(Signature, ExpectedComponents));
  try
    const SpaceName = GetEnumName(TypeInfo(TIccColorSpace), Ord(Profile.ColorSpace));

    Assert.AreEqual(ExpectedSpace, SpaceName);
    Assert.AreEqual(ExpectedComponents, Profile.NumberOfComponents);
  finally
    Profile.Free;
  end;
end;

procedure TIccProfileTests.TestIsSrgbReadsTheDeviceModelOfTheHeader;
begin
  const Srgb = TIccProfile.Parse(RgbProfile('sRGB'));
  const Other = TIccProfile.Parse(RgbProfile('Adobe'));
  try
    Assert.IsTrue(Srgb.IsSRGB, 'model sRGB');
    Assert.IsFalse(Other.IsSRGB, 'model Adobe');
  finally
    Other.Free;
    Srgb.Free;
  end;
end;

procedure TIccProfileTests.TestProfileWithoutSignatureRaisesParseError;
begin
  var Data := RgbProfile('sRGB');
  Data[36] := Ord('x');

  AssertParseRaises(Data, 'acsp missing');
end;

procedure TIccProfileTests.TestProfileOfAnUnknownColorSpaceRaisesParseError;
begin
  const Profile = TIccTestProfile.Create('mntr', 'QQQQ', 'XYZ ');
  try
    Profile.AddTag('rXYZ', TIccTestTags.Xyz(0.4, 0.2, 0.0));
    AssertParseRaises(Profile.Build, 'colour space QQQQ');
  finally
    Profile.Free;
  end;
end;

procedure TIccProfileTests.TestProfileOfAnUnknownPcsRaisesParseError;
begin
  const Profile = TIccTestProfile.Create('mntr', 'RGB ', 'RGB ');
  try
    AssertParseRaises(Profile.Build, 'PCS RGB');
  finally
    Profile.Free;
  end;
end;

procedure TIccProfileTests.TestProfileWithoutTagsForItsClassRaisesParseError;
begin
  const NoTags = TIccTestProfile.Create('mntr', 'RGB ', 'XYZ ');
  const NoCurves = TIccTestProfile.Create('mntr', 'RGB ', 'XYZ ');
  const NoLut = TIccTestProfile.Create('prtr', 'CMYK', 'Lab ');
  try
    NoCurves.AddTag('rXYZ', TIccTestTags.Xyz(0.4, 0.2, 0.0));
    NoCurves.AddTag('gXYZ', TIccTestTags.Xyz(0.4, 0.2, 0.0));
    NoCurves.AddTag('bXYZ', TIccTestTags.Xyz(0.4, 0.2, 0.0));
    NoLut.AddTag('wtpt', TIccTestTags.Xyz(0.96, 1.0, 0.82));

    AssertParseRaises(NoTags.Build, 'RGB without colorants');
    AssertParseRaises(NoCurves.Build, 'RGB without curves');
    AssertParseRaises(NoLut.Build, 'CMYK without A2B0');
  finally
    NoLut.Free;
    NoCurves.Free;
    NoTags.Free;
  end;
end;

procedure TIccProfileTests.TestTagOutsideTheDataRaisesParseError;
begin
  var Data := RgbProfile('sRGB');
  // The offset of the first tag, 128 + 4 + 8 = 140
  Data[140] := $7F;

  AssertParseRaises(Data, 'tag offset beyond the data');
end;

procedure TIccProfileTests.TestTagTableLargerThanTheDataRaisesParseError;
begin
  var Data := RgbProfile('sRGB');
  Data[128] := $FF;
  Data[129] := $FF;
  Data[130] := $FF;
  Data[131] := $FF;

  AssertParseRaises(Data, 'tag count beyond the data');
end;

procedure TIccProfileTests.TestTruncatedProfileRaisesParseError;
begin
  const Cmyk = TPdfIccResources.CmykProfile;
  const Srgb = TIccTestFiles.ReadProfile('sRGB.icc');

  for var Cut in [0, 1, 100, 127, 128, 131, 132, 200, 239, 240, 1000, Length(Cmyk) - 1] do
  begin
    AssertParseRaises(Copy(Cmyk, 0, Cut), Format('CMYK profile cut to %d bytes', [Cut]));
  end;
  for var Cut in [0, 64, 128, 400, 2000, 6900] do
  begin
    AssertParseRaises(Copy(Srgb, 0, Cut), Format('sRGB profile cut to %d bytes', [Cut]));
  end;
end;

procedure TIccProfileTests.TestProfileOverTheSizeLimitRaisesParseError;
begin
  var Data: TBytes;
  SetLength(Data, MaxIccProfileSize + 1);

  AssertParseRaises(Data, 'profile of 16 MB and a byte');
end;

procedure TIccProfileTests.TestHugeClutIsRejected;
begin
  // 255 grid points over 4 inputs is 4.2 billion points, and the tag holds none of them
  const Lut8 = TIccTestTags.Lut8(4, 3, 255, [], [], []);
  const Lut16 = TIccTestTags.Lut16(4, 3, 255, 2, 2, [], [], []);
  // 33 grid points over 4 inputs is 1.2 million points but the tag is too short for them
  const Short16 = TIccTestTags.Lut16(4, 3, 33, 2, 2, TArray<Word>.Create(0, 65535, 0, 65535, 0, 65535, 0, 65535), [], TArray<Word>.Create(0, 65535, 0, 65535, 0, 65535));
  // 16 inputs of 12 grid points
  const Wide = TIccTestTags.LutAToB(16, 3, [], [], [], [12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12], 2, [], []);

  AssertParseRaises(LutProfile('scnr', 'CMYK', 'Lab ', Lut8, 'A2B0'), 'lut8 with 255^4 points');
  AssertParseRaises(LutProfile('scnr', 'CMYK', 'Lab ', Lut16, 'A2B0'), 'lut16 with 255^4 points');
  AssertParseRaises(LutProfile('scnr', 'CMYK', 'Lab ', Short16, 'A2B0'), 'lut16 with a short CLUT');
  AssertParseRaises(LutProfile('scnr', 'FCLR', 'Lab ', Wide, 'A2B0'), 'mAB with 12^16 points');
end;

procedure TIccProfileTests.TestMoreThanSixteenInputChannelsAreRejected;
begin
  const Lut = TIccTestTags.Lut16(17, 3, 2, 2, 2, [], [], []);

  AssertParseRaises(LutProfile('scnr', 'CMYK', 'Lab ', Lut, 'A2B0'), 'lut16 with 17 inputs');
end;

procedure TIccProfileTests.TestCurveWithMoreEntriesThanItsTagRaisesParseError;
begin
  const Writer = TIccTestWriter.Create;
  try
    Writer.Signature('curv').Zeros(4).U32($FFFFFFFF).U16(0);
    const Profile = TIccTestProfile.Create('mntr', 'GRAY', 'XYZ ');
    try
      Profile.AddTag('kTRC', Writer.Bytes);
      AssertParseRaises(Profile.Build, 'curve of 4 billion entries');
    finally
      Profile.Free;
    end;
  finally
    Writer.Free;
  end;
end;

procedure TIccProfileTests.TestCorruptedProfilesOnlyRaiseParseErrors;
begin
  AssertOnlyParseErrors(TPdfIccResources.CmykProfile, 400, 1);
  AssertOnlyParseErrors(TIccTestFiles.ReadProfile('sRGB.icc'), 400, 2);
  AssertOnlyParseErrors(TIccTestFiles.ReadProfile('gray-small.icc'), 400, 3);
  AssertOnlyParseErrors(TIccTestFiles.ReadProfile('gray-gamma.icc'), 200, 4);
  AssertOnlyParseErrors(TIccTestFiles.ReadProfile('cmyk-printer.icc'), 12, 5);
end;

end.
