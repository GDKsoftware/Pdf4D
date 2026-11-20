// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of the conversion of ICC profiles to sRGB (ICC.1:2010); the reference values (tests/reference/color) come from
// ICC_ColorSpace.toRGB of the Java used by PDFBox (3.0.8)
unit Pdf4D.Graphics.Icc.Transform.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Math,
  DUnitX.TestFramework,
  Pdf4D.Graphics.Icc.Profile,
  Pdf4D.Graphics.Icc.Transform,
  Pdf4D.Resources.Icc,
  Pdf4D.Tests.IccBuilder;

type
  [TestFixture]
  TIccTransformTests = class
  private
    class function ProfileOfReference(const Name: string): TBytes; static;
    class function Convert(const Data: TBytes; const Input: array of Double): TArray<Single>; static;
    class function SrgbEncode(const Linear: Double): Double; static;
    class function LabToGray(const L: Double): Double; static;
    class procedure AssertColor(const Expected: array of Double; const Actual: TArray<Single>; const Tolerance: Double; const Message: string); static;
    class function GrayProfile(const Tag: TBytes): TBytes; static;
    class function LabLutProfile(const ColorSpace: string; const Lut: TBytes): TBytes; static;
    class function XyzLutProfile(const Lut: TBytes): TBytes; static;
    class function CheckReferenceFile(const FilePath: string): Double; static;
    class function FromBits(const Bits: Cardinal): Single; static;
    procedure CheckGrayCurve(const Tag: TBytes; const Curve: TFunc<Double, Double>; const Message: string);
    procedure TestGammaCurve;
    procedure TestParametricCurveTypes;
    procedure TestLut8;
    procedure TestLut16;
    procedure TestLutAToBWithClutAndCurves;
    procedure TestLutAToBWithMatrixAndMCurves;
    procedure TestLutAToBWithMatrixOnly;

  public
    [Test]
    procedure TestSrgbProfileMapsPrimaries;

    [Test]
    procedure TestCmykMatchesJava;

    [Test]
    procedure TestSrgbMatchesJava;

    [Test]
    procedure TestCorpusProfilesMatchJava;

    [Test]
    procedure TestCurvParaAndLutTypes;

    [Test]
    procedure TestToRgbClampsInvalidInput;

    [Test]
    procedure TestToRgbRowMatchesToRgb;

    [Test]
    procedure TestToRgbRowOfGrayAndRgb;
  end;

implementation

uses
  System.IOUtils;

const
  // The difference to Java that the tests accept per channel: Java's colour management (Little CMS) works with 16 bits
  // integers and an optimised table where this code uses floating point. The measured maximum (0.05 / 255) is in docs/assumptions.md.
  MaxDifferenceToJava = 0.25 / 255.0;

  // The D50 white of the PCS
  WhiteX = 0.9642;
  WhiteZ = 0.8249;

{ TIccTransformTests }

class function TIccTransformTests.ProfileOfReference(const Name: string): TBytes;
begin
  if Name = 'DeviceCMYK' then
  begin
    Result := TPdfIccResources.CmykProfile;
  end
  else
  begin
    Result := TIccTestFiles.ReadProfile(Name + '.icc');
  end;
end;

class function TIccTransformTests.Convert(const Data: TBytes; const Input: array of Double): TArray<Single>;
begin
  const Profile = TIccProfile.Parse(Data);
  try
    const Transform = TIccTransform.Create(Profile);
    try
      var Source: array[0..15] of Single;
      for var Index := 0 to High(Input) do
      begin
        Source[Index] := Input[Index];
      end;
      SetLength(Result, 3);
      Transform.ToRgb(@Source[0], @Result[0]);
    finally
      Transform.Free;
    end;
  finally
    Profile.Free;
  end;
end;

class function TIccTransformTests.SrgbEncode(const Linear: Double): Double;
begin
  const Clamped = Min(1.0, Max(0.0, Linear));
  if Clamped <= 0.0031308 then
  begin
    Result := 12.92 * Clamped;
  end
  else
  begin
    Result := 1.055 * Power(Clamped, 1.0 / 2.4) - 0.055;
  end;
end;

// The grey that CIE L* = L gives on an sRGB screen: Y from L*, then the sRGB curve
class function TIccTransformTests.LabToGray(const L: Double): Double;
begin
  var Y: Double;
  if L > 8.0 then
  begin
    Y := Power((L + 16.0) / 116.0, 3.0);
  end
  else
  begin
    Y := L / 903.2963;
  end;
  Result := SrgbEncode(Y);
end;

class procedure TIccTransformTests.AssertColor(const Expected: array of Double; const Actual: TArray<Single>; const Tolerance: Double; const Message: string);
begin
  for var Index := 0 to High(Expected) do
  begin
    Assert.IsTrue(Abs(Expected[Index] - Actual[Index]) <= Tolerance,
                  Format('%s: channel %d is %.5f, expected %.5f', [Message, Index, Actual[Index], Expected[Index]]));
  end;
end;

class function TIccTransformTests.FromBits(const Bits: Cardinal): Single;
begin
  Move(Bits, Result, SizeOf(Result));
end;

class function TIccTransformTests.GrayProfile(const Tag: TBytes): TBytes;
begin
  const Profile = TIccTestProfile.Create('mntr', 'GRAY', 'XYZ ');
  try
    Profile.AddTag('kTRC', Tag);
    Result := Profile.Build;
  finally
    Profile.Free;
  end;
end;

class function TIccTransformTests.LabLutProfile(const ColorSpace: string; const Lut: TBytes): TBytes;
begin
  const Profile = TIccTestProfile.Create('scnr', ColorSpace, 'Lab ');
  try
    Profile.AddTag('A2B0', Lut);
    Result := Profile.Build;
  finally
    Profile.Free;
  end;
end;

class function TIccTransformTests.XyzLutProfile(const Lut: TBytes): TBytes;
begin
  const Profile = TIccTestProfile.Create('mntr', 'RGB ', 'XYZ ');
  try
    Profile.AddTag('A2B0', Lut);
    Result := Profile.Build;
  finally
    Profile.Free;
  end;
end;

// Grey device value X goes through the curve of the kTRC tag to Y, and Y of the D50 white is a grey on screen
procedure TIccTransformTests.CheckGrayCurve(const Tag: TBytes; const Curve: TFunc<Double, Double>; const Message: string);
begin
  const Data = GrayProfile(Tag);

  for var Value in [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0] do
  begin
    const Actual = Convert(Data, [Value]);

    const Expected = SrgbEncode(Curve(Value));
    AssertColor([Expected, Expected, Expected], Actual, 0.002, Format('%s at %.2f', [Message, Value]));
  end;
end;

procedure TIccTransformTests.TestSrgbProfileMapsPrimaries;
begin
  const Data = TIccTestFiles.ReadProfile('sRGB.icc');
  const Tolerance = 1.0 / 255.0;

  AssertColor([1, 0, 0], Convert(Data, [1, 0, 0]), Tolerance, 'red');
  AssertColor([0, 1, 0], Convert(Data, [0, 1, 0]), Tolerance, 'green');
  AssertColor([0, 0, 1], Convert(Data, [0, 0, 1]), Tolerance, 'blue');
  AssertColor([1, 1, 1], Convert(Data, [1, 1, 1]), Tolerance, 'white');
  AssertColor([0, 0, 0], Convert(Data, [0, 0, 0]), Tolerance, 'black');
  AssertColor([0.5, 0.25, 0.75], Convert(Data, [0.5, 0.25, 0.75]), Tolerance, 'mixed');
end;

class function TIccTransformTests.CheckReferenceFile(const FilePath: string): Double;
begin
  Result := 0;
  const Name = TPath.GetFileNameWithoutExtension(FilePath);
  const Profile = TIccProfile.Parse(ProfileOfReference(Name));
  try
    const Transform = TIccTransform.Create(Profile);
    try
      var Source: array[0..15] of Single;
      var Actual: array[0..2] of Single;
      var Count := 0;
      for var Line in TFile.ReadAllLines(FilePath) do
      begin
        const OutMarker = ' out:';
        if not Line.StartsWith('in:') then
        begin
          Continue;
        end;
        const MarkerAt = Line.IndexOf(OutMarker);
        const Inputs = Line.Substring(3, MarkerAt - 3).Split([' '], TStringSplitOptions.ExcludeEmpty);
        const Outputs = Line.Substring(MarkerAt + Length(OutMarker)).Split([' '], TStringSplitOptions.ExcludeEmpty);
        Assert.AreEqual(Profile.NumberOfComponents, Integer(Length(Inputs)), Name);
        Assert.AreEqual(3, Integer(Length(Outputs)), Format('%s: PDFBox gives no colour for %s', [Name, Line]));

        for var Index := 0 to High(Inputs) do
        begin
          Source[Index] := StrToFloat(Inputs[Index], TFormatSettings.Invariant);
        end;
        Transform.ToRgb(@Source[0], @Actual[0]);
        for var Index := 0 to 2 do
        begin
          const Difference = Abs(Actual[Index] - StrToFloat(Outputs[Index], TFormatSettings.Invariant));
          Result := Max(Result, Difference);
          Assert.IsTrue(Difference <= MaxDifferenceToJava,
                        Format('%s: %s gives %.5f for channel %d, Java gives %s', [Name, Line.Substring(0, MarkerAt), Actual[Index], Index, Outputs[Index]]));
        end;
        Inc(Count);
      end;
      Assert.AreEqual(200, Count, Name);
    finally
      Transform.Free;
    end;
  finally
    Profile.Free;
  end;
end;

procedure TIccTransformTests.TestCmykMatchesJava;
begin
  CheckReferenceFile(TPath.Combine(TIccTestFiles.ReferenceFolder, 'DeviceCMYK.txt'));
end;

procedure TIccTransformTests.TestSrgbMatchesJava;
begin
  CheckReferenceFile(TPath.Combine(TIccTestFiles.ReferenceFolder, 'sRGB.txt'));
end;

procedure TIccTransformTests.TestCorpusProfilesMatchJava;
begin
  var FileCount := 0;
  for var FilePath in TDirectory.GetFiles(TIccTestFiles.ReferenceFolder, '*.txt') do
  begin
    const Name = TPath.GetFileNameWithoutExtension(FilePath);
    if (Name = 'DeviceCMYK') or (Name = 'sRGB') then
    begin
      Continue;
    end;
    CheckReferenceFile(FilePath);
    Inc(FileCount);
  end;

  Assert.IsTrue(FileCount >= 3, 'the reference files of the corpus profiles were not found');
end;

procedure TIccTransformTests.TestGammaCurve;
begin
  CheckGrayCurve(TIccTestTags.CurveGamma(2.0),
                 function(Value: Double): Double
                 begin
                   Result := Power(Value, 2.0);
                 end, 'gamma 2.0');
end;

procedure TIccTransformTests.TestParametricCurveTypes;
begin
  CheckGrayCurve(TIccTestTags.Parametric(0, [1.8]),
                 function(Value: Double): Double
                 begin
                   Result := Power(Value, 1.8);
                 end, 'para type 0');

  CheckGrayCurve(TIccTestTags.Parametric(1, [2.0, 0.8, 0.1]),
                 function(Value: Double): Double
                 begin
                   const Base = 0.8 * Value + 0.1;
                   if Value >= -0.1 / 0.8 then
                   begin
                     Result := Power(Base, 2.0);
                   end
                   else
                   begin
                     Result := 0;
                   end;
                 end, 'para type 1');

  CheckGrayCurve(TIccTestTags.Parametric(2, [2.0, 0.8, 0.1, 0.05]),
                 function(Value: Double): Double
                 begin
                   Result := Power(0.8 * Value + 0.1, 2.0) + 0.05;
                 end, 'para type 2');

  CheckGrayCurve(TIccTestTags.Parametric(3, [2.4, 1.0 / 1.055, 0.055 / 1.055, 1.0 / 12.92, 0.04045]),
                 function(Value: Double): Double
                 begin
                   if Value >= 0.04045 then
                   begin
                     Result := Power(Value / 1.055 + 0.055 / 1.055, 2.4);
                   end
                   else
                   begin
                     Result := Value / 12.92;
                   end;
                 end, 'para type 3');

  CheckGrayCurve(TIccTestTags.Parametric(4, [2.0, 0.9, 0.05, 0.2, 0.3, 0.02, 0.01]),
                 function(Value: Double): Double
                 begin
                   if Value >= 0.3 then
                   begin
                     Result := Power(0.9 * Value + 0.05, 2.0) + 0.02;
                   end
                   else
                   begin
                     Result := 0.2 * Value + 0.01;
                   end;
                 end, 'para type 4');

  CheckGrayCurve(TIccTestTags.CurveTable([0, 8192, 65535]),
                 function(Value: Double): Double
                 begin
                   if Value <= 0.5 then
                   begin
                     Result := Value * 2.0 * (8192.0 / 65535.0);
                   end
                   else
                   begin
                     Result := (8192.0 + (Value - 0.5) * 2.0 * (65535.0 - 8192.0)) / 65535.0;
                   end;
                 end, 'curv table of 3 entries');

  CheckGrayCurve(TIccTestTags.CurveTable([]),
                 function(Value: Double): Double
                 begin
                   Result := Value;
                 end, 'curv identity');
end;

// A device with one input whose CLUT runs from L* 0 to L* 100 (a* and b* 0): L* of the input value
procedure TIccTransformTests.TestLut8;
begin
  var InputTable: TArray<Byte>;
  SetLength(InputTable, 256);
  for var Index := 0 to 255 do
  begin
    InputTable[Index] := Index;
  end;
  var OutputTable: TArray<Byte>;
  SetLength(OutputTable, 768);
  for var Index := 0 to 255 do
  begin
    OutputTable[Index] := Index;
    OutputTable[256 + Index] := Index;
    OutputTable[512 + Index] := Index;
  end;
  // Lab in 8 bits: L* = value / 255 * 100, a* = value - 128
  const Clut = TArray<Byte>.Create(0, 128, 128, 255, 128, 128);
  const Data = LabLutProfile('GRAY', TIccTestTags.Lut8(1, 3, 2, InputTable, Clut, OutputTable));

  for var Value in [0.0, 0.2, 0.5, 1.0] do
  begin
    const Expected = LabToGray(Value * 100.0);
    AssertColor([Expected, Expected, Expected], Convert(Data, [Value]), 0.003, Format('lut8 at %.1f', [Value]));
  end;
end;

procedure TIccTransformTests.TestLut16;
begin
  // Legacy 16 bits Lab: L* = value / 65280 * 100, a* = value / 256 - 128
  const InputTable = TArray<Word>.Create(0, 16384, 65535);
  const Clut = TArray<Word>.Create(0, 32768, 32768, 65280, 32768, 32768);
  const OutputTable = TArray<Word>.Create(0, 65535, 0, 65535, 0, 65535);
  const Data = LabLutProfile('GRAY', TIccTestTags.Lut16(1, 3, 2, 3, 2, InputTable, Clut, OutputTable));

  // The input curve maps 0.5 to 0.25 (a point of the table), and the CLUT runs from L* 0 to L* 100
  AssertColor([LabToGray(25.0), LabToGray(25.0), LabToGray(25.0)], Convert(Data, [0.5]), 0.003, 'lut16 at 0.5');
  AssertColor([LabToGray(100.0), LabToGray(100.0), LabToGray(100.0)], Convert(Data, [1.0]), 0.003, 'lut16 at 1');
  AssertColor([0, 0, 0], Convert(Data, [0.0]), 0.003, 'lut16 at 0');
end;

procedure TIccTransformTests.TestLutAToBWithClutAndCurves;
begin
  // A curves (one input) bend 0.5 to 0.25; the CLUT of 2 points runs L* 0 to 100 in 16 bits (v4: L* = value / 65535 * 100);
  // the B curves are identities
  const ACurve = TIccTestTags.CurveTable([0, 16384, 65535]);
  const BCurve = TIccTestTags.CurveTable([]);
  const Clut = TArray<Word>.Create(0, 32896, 32896, 65535, 32896, 32896);
  const Lut = TIccTestTags.LutAToB(1, 3, [BCurve, BCurve, BCurve], [], [], [2], 2, Clut, [ACurve]);
  const Data = LabLutProfile('GRAY', Lut);

  AssertColor([LabToGray(25.0), LabToGray(25.0), LabToGray(25.0)], Convert(Data, [0.5]), 0.003, 'mAB with CLUT at 0.5');
  AssertColor([LabToGray(100.0), LabToGray(100.0), LabToGray(100.0)], Convert(Data, [1.0]), 0.003, 'mAB with CLUT at 1');

  // The same CLUT with 8 bits per entry
  const Clut8 = TArray<Word>.Create(0, 128, 128, 255, 128, 128);
  const Data8 = LabLutProfile('GRAY', TIccTestTags.LutAToB(1, 3, [BCurve, BCurve, BCurve], [], [], [2], 1, Clut8, [ACurve]));

  AssertColor([LabToGray(25.0), LabToGray(25.0), LabToGray(25.0)], Convert(Data8, [0.5]), 0.01, 'mAB with an 8 bits CLUT at 0.5');
end;

// XYZ as PCS: the colorants of sRGB scaled to the encoding of the PCS (1.0 is 32768/65535) and the sRGB curves as M curves
procedure TIccTransformTests.TestLutAToBWithMatrixAndMCurves;
begin
  const Scale = 32768.0 / 65535.0;
  const Identity = TIccTestTags.CurveTable([]);
  const Matrix: array of Double = [0.4358521 * Scale, 0.3853302 * Scale, 0.1430206 * Scale,
                                   0.2223816 * Scale, 0.7170410 * Scale, 0.0605927 * Scale,
                                   0.0139160 * Scale, 0.0971375 * Scale, 0.7138367 * Scale,
                                   0, 0, 0];
  const Lut = TIccTestTags.LutAToB(3, 3, [Identity, Identity, Identity], Matrix, [TIccTestTags.SrgbCurve, TIccTestTags.SrgbCurve, TIccTestTags.SrgbCurve], [], 2, [], []);
  const Data = XyzLutProfile(Lut);

  AssertColor([0.2, 0.5, 0.9], Convert(Data, [0.2, 0.5, 0.9]), 0.003, 'mAB with matrix and M curves');
  AssertColor([1, 0, 0], Convert(Data, [1, 0, 0]), 0.003, 'mAB with matrix and M curves, red');
end;

procedure TIccTransformTests.TestLutAToBWithMatrixOnly;
begin
  const Scale = 32768.0 / 65535.0;
  const Identity = TIccTestTags.CurveTable([]);
  // Every channel adds its share of the D50 white: grey v gives XYZ = v * D50
  const Matrix: array of Double = [0.4358521 * Scale, 0.3853302 * Scale, 0.1430206 * Scale,
                                   0.2223816 * Scale, 0.7170410 * Scale, 0.0605927 * Scale,
                                   0.0139160 * Scale, 0.0971375 * Scale, 0.7138367 * Scale,
                                   0, 0, 0];
  const Data = XyzLutProfile(TIccTestTags.LutAToB(3, 3, [Identity, Identity, Identity], Matrix, [], [], 2, [], []));

  const Expected = SrgbEncode(0.5);
  AssertColor([Expected, Expected, Expected], Convert(Data, [0.5, 0.5, 0.5]), 0.003, 'mAB with a matrix only');
  AssertColor([1, 1, 1], Convert(Data, [1, 1, 1]), 0.003, 'mAB with a matrix only, white');
end;

procedure TIccTransformTests.TestCurvParaAndLutTypes;
begin
  TestGammaCurve;
  TestParametricCurveTypes;
  TestLut8;
  TestLut16;
  TestLutAToBWithClutAndCurves;
  TestLutAToBWithMatrixAndMCurves;
  TestLutAToBWithMatrixOnly;
end;

procedure TIccTransformTests.TestToRgbClampsInvalidInput;
begin
  const CmykProfile = TIccProfile.Parse(TPdfIccResources.CmykProfile);
  const RgbProfile = TIccProfile.Parse(TIccTestFiles.ReadProfile('sRGB.icc'));
  try
    const CmykTransform = TIccTransform.Create(CmykProfile);
    const RgbTransform = TIccTransform.Create(RgbProfile);
    try
      const Values = TArray<Single>.Create(FromBits($7FC00000), FromBits($7F800000), FromBits($FF800000), -1, 2, 1E30, -1E30, 0.5);
      var Input: array[0..3] of Single;
      var Output: array[0..2] of Single;
      for var Value in Values do
      begin
        for var Index := 0 to 3 do
        begin
          Input[Index] := Value;
        end;

        CmykTransform.ToRgb(@Input[0], @Output[0]);
        for var Channel in Output do
        begin
          Assert.IsTrue((Channel >= 0.0) and (Channel <= 1.0), Format('CMYK of %g gives %g', [Double(Value), Double(Channel)]));
        end;

        RgbTransform.ToRgb(@Input[0], @Output[0]);
        for var Channel in Output do
        begin
          Assert.IsTrue((Channel >= 0.0) and (Channel <= 1.0), Format('RGB of %g gives %g', [Double(Value), Double(Channel)]));
        end;
      end;

      Input[0] := FromBits($7FC00000);
      Input[1] := 0;
      Input[2] := 0;
      Input[3] := 0;
      CmykTransform.ToRgb(@Input[0], @Output[0]);
      Assert.AreEqual(1.0, Double(Output[0]), 0.01, 'NaN is 0, so no ink: white');
    finally
      RgbTransform.Free;
      CmykTransform.Free;
    end;
  finally
    RgbProfile.Free;
    CmykProfile.Free;
  end;
end;

procedure TIccTransformTests.TestToRgbRowMatchesToRgb;
begin
  const Profile = TIccProfile.Parse(TPdfIccResources.CmykProfile);
  try
    const Transform = TIccTransform.Create(Profile);
    try
      const PixelCount = 600;
      var Input: TBytes;
      SetLength(Input, PixelCount * 4);
      var State: Cardinal := 77;
      for var Index := 0 to High(Input) do
      begin
        State := Cardinal((UInt64(State) * 1103515245 + 12345) and $FFFFFFFF);
        // Few distinct values, so the cache is hit as well as missed
        Input[Index] := Byte(((State shr 16) mod 5) * 63);
      end;
      var Output: TBytes;
      SetLength(Output, PixelCount * 3);

      Transform.ToRgbRow(@Input[0], @Output[0], PixelCount);
      Transform.ToRgbRow(@Input[0], @Output[0], PixelCount);

      for var Pixel := 0 to PixelCount - 1 do
      begin
        var Source: array[0..3] of Single;
        var Expected: array[0..2] of Single;
        for var Channel := 0 to 3 do
        begin
          Source[Channel] := Input[Pixel * 4 + Channel] / 255.0;
        end;
        Transform.ToRgb(@Source[0], @Expected[0]);
        for var Channel := 0 to 2 do
        begin
          const ExpectedByte = Round(Expected[Channel] * 255.0);
          Assert.IsTrue(Abs(ExpectedByte - Output[Pixel * 3 + Channel]) <= 1,
                        Format('pixel %d channel %d is %d, ToRgb gives %d', [Pixel, Channel, Output[Pixel * 3 + Channel], ExpectedByte]));
        end;
      end;
    finally
      Transform.Free;
    end;
  finally
    Profile.Free;
  end;
end;

procedure TIccTransformTests.TestToRgbRowOfGrayAndRgb;
begin
  const Gray = TIccProfile.Parse(TIccTestFiles.ReadProfile('gray-gamma.icc'));
  const Rgb = TIccProfile.Parse(TIccTestFiles.ReadProfile('sRGB.icc'));
  try
    const GrayTransform = TIccTransform.Create(Gray);
    const RgbTransform = TIccTransform.Create(Rgb);
    try
      var GrayInput: TBytes;
      SetLength(GrayInput, 256);
      for var Index := 0 to 255 do
      begin
        GrayInput[Index] := Index;
      end;
      var GrayOutput: TBytes;
      SetLength(GrayOutput, 256 * 3);
      GrayTransform.ToRgbRow(@GrayInput[0], @GrayOutput[0], 256);
      for var Index := 0 to 255 do
      begin
        var Source: Single := Index / 255.0;
        var Expected: array[0..2] of Single;
        GrayTransform.ToRgb(@Source, @Expected[0]);
        Assert.IsTrue(Abs(Round(Expected[0] * 255.0) - GrayOutput[Index * 3]) <= 1, Format('gray %d', [Index]));
        Assert.AreEqual(GrayOutput[Index * 3], GrayOutput[Index * 3 + 1], 'gray: R = G');
        Assert.AreEqual(GrayOutput[Index * 3], GrayOutput[Index * 3 + 2], 'gray: R = B');
      end;

      const RgbInput = TBytes.Create(255, 0, 0, 0, 255, 0, 0, 0, 255, 128, 128, 128);
      var RgbOutput: TBytes;
      SetLength(RgbOutput, 12);
      RgbTransform.ToRgbRow(@RgbInput[0], @RgbOutput[0], 4);
      for var Index := 0 to 11 do
      begin
        Assert.IsTrue(Abs(RgbInput[Index] - RgbOutput[Index]) <= 1, Format('sRGB byte %d', [Index]));
      end;
    finally
      RgbTransform.Free;
      GrayTransform.Free;
    end;
  finally
    Rgb.Free;
    Gray.Free;
  end;
end;

end.
