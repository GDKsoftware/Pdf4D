// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Tests of Pdf4D for the functions of type 0, 2 and 3 and the identity of PDFBox (3.0.8); the reference values
// (tests/reference/functions) come from PDFBox
unit Pdf4D.Graphics.&Function.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Graphics.&Function,
  Pdf4D.Model.Tests.Support,
  Pdf4D.Tests.Functions;

type
  [TestFixture]
  TFunctionTests = class
  private
    FBuilder: TFunctionTestBuilder;
    FFunctions: TObjectList<TPDFunction>;
    FDocuments: TModelTestDocuments;

    class procedure AssertCount(const Expected: Integer; const Actual: Int64; const Message: string = ''); static;
    class procedure AssertNear(const Expected: Double; const Actual: Single; const Tolerance: Double; const Message: string = ''); static;
    function Make(const Value: TCosBase): TPDFunction;
    function Eval(const Value: TCosBase; const Input: array of Single): TArray<Single>;
    function NewType0(const Domain, Range, Size: string; const BitsPerSample: Integer; const Samples: TBytes): TCosStream;
    function OpenFunction(const Objects: array of string): TPDFunction;
    class function SameValue(const Expected, Actual: Single): Boolean; static;
    class function Describe(const Values: TArray<Single>): string; static;
    class function Repeated(const Text: string; const Count: Integer): string; static;
    procedure CheckCase(const FileName: string; const FunctionCase: TFunctionCase);
    procedure CheckEvaluation(const Context: string; const Reference: TPDFunction; const Evaluation: TFunctionEvaluation);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestType2Exponential;

    [Test]
    procedure TestType2ClipsToRangeButNotToDomain;

    [Test]
    procedure TestType2TakesTheShorterOfC0AndC1;

    [Test]
    procedure TestType2DefaultsAreThoseOfPdfBox;

    [Test]
    procedure TestType2ParameterCounts;

    [Test]
    procedure TestType0LinearInterpolation;

    [Test]
    procedure TestType0TwoInputsMultilinear;

    [Test]
    procedure TestType0EncodeAndDecode;

    [Test]
    procedure TestType0ShortDataGivesZeros;

    [Test]
    procedure TestType0MoreSamplesThanTheLimitGivesOneWarning;

    [Test]
    procedure TestType0MoreInputsThanTheLimitRaises;

    [Test]
    procedure TestType0SizeThatDoesNotMatchTheDomainRaises;

    [Test]
    procedure TestType0WithoutRangeOrBitsPerSampleRaises;

    [Test]
    procedure TestType0NeedsAStream;

    [Test]
    procedure TestType3Stitching;

    [Test]
    procedure TestType3OutsideEveryPartitionGivesZeros;

    [Test]
    procedure TestType3WithoutFunctionsOrBoundsRaises;

    [Test]
    procedure TestType3ParameterCounts;

    [Test]
    procedure TestStitchingRecursionStops;

    [Test]
    procedure TestStitchingOfEightLevelsWorksAndNineRaises;

    [Test]
    procedure TestStitchingFanOutIsBounded;

    [Test]
    procedure TestSampleTablesOfOneTreeAreBoundedTogether;

    [Test]
    procedure TestIdentityGivesItsInput;

    [Test]
    procedure TestCreateRaisesForWhatIsNoFunction;

    [Test]
    procedure TestEvalNeverRaises;

    [Test]
    procedure TestFunctionsMatchPdfBox;
  end;

implementation

uses
  System.Math,
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.ObjectKey,
  Pdf4D.Tests.PdfBuilder;

const
  OutputTolerance = 0.0001;
  SingleRelativeTolerance = 0.000001;
  TwoByTwoSamples: array[0..3] of Byte = ($00, $FF, $80, $20);

{ TFunctionTests }

class procedure TFunctionTests.AssertCount(const Expected: Integer; const Actual: Int64; const Message: string);
begin
  Assert.AreEqual(Int64(Expected), Actual, Message);
end;

class procedure TFunctionTests.AssertNear(const Expected: Double; const Actual: Single; const Tolerance: Double; const Message: string);
begin
  Assert.AreEqual(Expected, Double(Actual), Tolerance, Message);
end;

procedure TFunctionTests.Setup;
begin
  FBuilder := TFunctionTestBuilder.Create;
  FFunctions := TObjectList<TPDFunction>.Create(True);
  FDocuments := TModelTestDocuments.Create;
end;

procedure TFunctionTests.TearDown;
begin
  FFunctions.Free;
  FDocuments.Free;
  FBuilder.Free;
end;

function TFunctionTests.Make(const Value: TCosBase): TPDFunction;
begin
  Result := TPDFunction.Create(Value, FBuilder.Context);
  FFunctions.Add(Result);
end;

function TFunctionTests.Eval(const Value: TCosBase; const Input: array of Single): TArray<Single>;
begin
  var Values: TArray<Single>;
  SetLength(Values, Length(Input));
  for var Index := 0 to Length(Input) - 1 do
  begin
    Values[Index] := Input[Index];
  end;
  Result := Make(Value).Eval(Values);
end;

function TFunctionTests.NewType0(const Domain, Range, Size: string; const BitsPerSample: Integer; const Samples: TBytes): TCosStream;
begin
  Result := FBuilder.NewStream(0, [TCosNames.Domain, Domain, TCosNames.Range, Range, TCosNames.Size, Size], Samples);
  Result.SetItem(TCosNames.BitsPerSample, TCosInteger.Create(BitsPerSample));
end;

// The objects are the bodies of the objects 3, 4 and so on; the function is object 3
function TFunctionTests.OpenFunction(const Objects: array of string): TPDFunction;
begin
  const PdfBuilder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [] /Count 0 >>');
  try
    for var Index := 0 to Length(Objects) - 1 do
    begin
      PdfBuilder.AddObject(3 + Index, Objects[Index]);
    end;
    const Document = FDocuments.Open(PdfBuilder);
    const FunctionObject = Document.CosDocument.GetObjectFromPool(TCosObjectKey.Make(3, 0));
    Result := TPDFunction.Create(FunctionObject, Document.Context);
    FFunctions.Add(Result);
  finally
    PdfBuilder.Free;
  end;
end;

class function TFunctionTests.Repeated(const Text: string; const Count: Integer): string;
begin
  const Builder = TStringBuilder.Create;
  try
    for var Index := 1 to Count do
    begin
      Builder.Append(Text);
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TFunctionTests.SameValue(const Expected, Actual: Single): Boolean;
begin
  if IsNaN(Expected) or IsNaN(Actual) then
  begin
    Exit(IsNaN(Expected) and IsNaN(Actual));
  end;
  if IsInfinite(Expected) or IsInfinite(Actual) then
  begin
    Exit(Expected = Actual);
  end;
  Result := Abs(Expected - Actual) <= Max(OutputTolerance, Abs(Expected) * SingleRelativeTolerance);
end;

class function TFunctionTests.Describe(const Values: TArray<Single>): string;
begin
  Result := '';
  for var Value in Values do
  begin
    Result := Result + ' ' + FloatToStr(Value, TFormatSettings.Invariant);
  end;
end;

procedure TFunctionTests.TestType2Exponential;
begin
  const Values = Eval(FBuilder.NewType2('0 1', '0', '1', 2), [0.5]);

  AssertCount(1, Length(Values));
  AssertNear(0.25, Values[0], 0.0000001);
end;

procedure TFunctionTests.TestType2ClipsToRangeButNotToDomain;
begin
  const Dictionary = FBuilder.NewType2('0 1', '0 0', '1 2', 1);
  Dictionary.SetItem(TCosNames.Range, TFunctionTestBuilder.NewArray('0 0.5'));
  const Function_ = Make(Dictionary);

  AssertNear(0.1, Function_.Eval([0.1])[0], 0.0000001, 'inside the range');
  AssertNear(0.5, Function_.Eval([0.7])[0], 0.0000001, 'clipped to the range');
  AssertCount(1, Length(Function_.Eval([0.7])), 'the range has one pair, so there is one output');
  const Plain = Make(FBuilder.NewType2('0 1', '0', '1', 2));
  AssertNear(4.0, Plain.Eval([2])[0], 0.0000001, 'PDFBox does not clip the input to the domain of a type 2 function');
end;

procedure TFunctionTests.TestType2TakesTheShorterOfC0AndC1;
begin
  const Values = Eval(FBuilder.NewType2('0 1', '0 5 7', '1 6', 1), [0.5]);

  AssertCount(2, Length(Values));
  AssertNear(0.5, Values[0], 0.0000001);
  AssertNear(5.5, Values[1], 0.0000001);
end;

procedure TFunctionTests.TestType2DefaultsAreThoseOfPdfBox;
begin
  const Dictionary = FBuilder.NewDictionary(2, [TCosNames.Domain, '0 1']);

  const Values = Eval(Dictionary, [0.5]);

  AssertCount(1, Length(Values), 'C0 is [0] and C1 is [1]');
  AssertNear(2.0, Values[0], 0.0000001, 'N is -1 when it is missing');
end;

procedure TFunctionTests.TestType2ParameterCounts;
begin
  const WithRange = Make(FBuilder.NewType2('0 1', '0 0', '1 1', 1));
  const WithoutDomain = Make(FBuilder.NewDictionary(2, [TCosNames.C0, '0 0 0', TCosNames.C1, '1 1 1']));

  Assert.AreEqual(2, WithRange.FunctionType);
  Assert.AreEqual(1, WithRange.NumberOfInputParameters);
  Assert.AreEqual(2, WithRange.NumberOfOutputParameters);
  Assert.AreEqual(1, WithoutDomain.NumberOfInputParameters, 'a type 2 function has one input also without a Domain');
  Assert.AreEqual(3, WithoutDomain.NumberOfOutputParameters, 'the outputs follow C0 and C1 when there is no Range');
end;

procedure TFunctionTests.TestType0LinearInterpolation;
begin
  const Stream = NewType0('0 1', '0 1', '2', 8, [$00, $FF]);
  const Function_ = Make(Stream);

  AssertNear(0.5, Function_.Eval([0.5])[0], 0.002);
  AssertNear(0.0, Function_.Eval([0])[0], 0.0000001);
  AssertNear(1.0, Function_.Eval([1])[0], 0.0000001);
  AssertNear(1.0, Function_.Eval([2])[0], 0.0000001, 'the input is clipped to the domain');
  AssertNear(0.0, Function_.Eval([-1])[0], 0.0000001, 'the input is clipped to the domain');
  Assert.AreEqual(0, Function_.FunctionType);
end;

procedure TFunctionTests.TestType0TwoInputsMultilinear;
begin
  const Stream = NewType0('0 1 0 1', '0 1', '2 2', 8, [$00, $FF, $80, $20]);
  const Function_ = Make(Stream);

  AssertNear(0.40686274, Function_.Eval([0.5, 0.5])[0], OutputTolerance, 'the centre, from PDFBox');
  AssertNear(1.0, Function_.Eval([1, 0])[0], OutputTolerance, 'the first input runs fastest');
  AssertNear(0.5019608, Function_.Eval([0, 1])[0], OutputTolerance);
  AssertNear(0.1254902, Function_.Eval([1, 1])[0], OutputTolerance);
  AssertNear(0.36838236, Function_.Eval([0.25, 0.75])[0], OutputTolerance);
  Assert.AreEqual(2, Function_.NumberOfInputParameters);
end;

procedure TFunctionTests.TestType0EncodeAndDecode;
begin
  const Reversed = NewType0('0 1', '0 1', '2', 8, [$00, $FF]);
  Reversed.SetItem(TCosNames.Decode, TFunctionTestBuilder.NewArray('1 0'));
  const Encoded = NewType0('0 1', '0 1', '3', 8, [$00, $80, $FF]);
  Encoded.SetItem(TCosNames.Encode, TFunctionTestBuilder.NewArray('2 0'));

  AssertNear(0.75, Make(Reversed).Eval([0.25])[0], OutputTolerance, 'Decode 1 0 turns the samples around');
  AssertNear(0.7509804, Make(Encoded).Eval([0.25])[0], OutputTolerance, 'Encode 2 0 runs through the table backwards');
end;

procedure TFunctionTests.TestType0ShortDataGivesZeros;
begin
  const Stream = NewType0('0 1', '0 1', '4', 8, [$00, $FF]);
  const Function_ = Make(Stream);

  AssertNear(0.5, Function_.Eval([0.5])[0], OutputTolerance, 'the second sample is there, the third is not');
  AssertNear(0.0, Function_.Eval([0.9])[0], OutputTolerance, 'both samples are missing');
end;

procedure TFunctionTests.TestType0MoreSamplesThanTheLimitGivesOneWarning;
begin
  const Stream = NewType0('0 1 0 1', '0 1', '4097 4097', 8, [$FF]);
  const Function_ = Make(Stream);

  const First = Function_.Eval([0, 0]);
  const Second = Function_.Eval([1, 1]);

  AssertNear(1.0, First[0], OutputTolerance, 'the first sample is there');
  AssertNear(0.0, Second[0], OutputTolerance, 'the samples past the data are zero');
  Assert.AreEqual(1, FBuilder.WarningCount, 'one warning for the function, however often it is used');
end;

procedure TFunctionTests.TestType0MoreInputsThanTheLimitRaises;
begin
  const Stream = NewType0(Repeated('0 1 ', 17), '0 1', Repeated('2 ', 17), 8, [$00]);
  const Allowed = NewType0(Repeated('0 1 ', 16), '0 1', Repeated('1 ', 16), 8, [$80]);

  Assert.WillRaise(
    procedure
    begin
      TPDFunction.Create(Stream, FBuilder.Context).Free;
    end, EPdfParseException);
  AssertNear(0.50196, Make(Allowed).Eval(TFunctionTestBuilder.ParseSingles(Repeated('0.5 ', 16)))[0], OutputTolerance);
end;

procedure TFunctionTests.TestType0SizeThatDoesNotMatchTheDomainRaises;
begin
  const TooFew = NewType0('0 1 0 1', '0 1', '2', 8, [$00, $FF, $80, $20]);
  const Zero = NewType0('0 1', '0 1', '0', 8, [$00]);

  Assert.WillRaise(
    procedure
    begin
      TPDFunction.Create(TooFew, FBuilder.Context).Free;
    end, EPdfParseException);
  Assert.WillRaise(
    procedure
    begin
      TPDFunction.Create(Zero, FBuilder.Context).Free;
    end, EPdfParseException);
end;

procedure TFunctionTests.TestType0WithoutRangeOrBitsPerSampleRaises;
begin
  const NoRange = FBuilder.NewStream(0, [TCosNames.Domain, '0 1', TCosNames.Size, '2'], [$00, $FF]);
  NoRange.SetItem(TCosNames.BitsPerSample, TCosInteger.Create(8));
  const NoBits = FBuilder.NewStream(0, [TCosNames.Domain, '0 1', TCosNames.Range, '0 1', TCosNames.Size, '2'], [$00, $FF]);
  const ZeroBits = NewType0('0 1', '0 1', '2', 0, [$00, $FF]);
  const TooManyBits = NewType0('0 1', '0 1', '2', 33, [$00, $FF]);

  var Broken: TArray<TCosDictionary> := [NoRange, NoBits, ZeroBits, TooManyBits];
  for var Invalid in Broken do
  begin
    Assert.WillRaise(
      procedure
      begin
        TPDFunction.Create(Invalid, FBuilder.Context).Free;
      end, EPdfParseException);
  end;
end;

procedure TFunctionTests.TestType0NeedsAStream;
begin
  const Dictionary = FBuilder.NewDictionary(0, [TCosNames.Domain, '0 1', TCosNames.Range, '0 1', TCosNames.Size, '2']);
  Dictionary.SetItem(TCosNames.BitsPerSample, TCosInteger.Create(8));

  Assert.WillRaise(
    procedure
    begin
      TPDFunction.Create(Dictionary, FBuilder.Context).Free;
    end, EPdfParseException);
end;

procedure TFunctionTests.TestType3Stitching;
begin
  const Dictionary = FBuilder.NewType3('0 1', '0.5', '0 1 0 1',
                              [FBuilder.NewType2('0 1', '0', '1', 1), FBuilder.NewType2('0 1', '1', '0', 1)]);
  const Function_ = Make(Dictionary);

  AssertNear(0.5, Function_.Eval([0.75])[0], OutputTolerance, '0.75 is half way the second function');
  AssertNear(0.5, Function_.Eval([0.25])[0], OutputTolerance, '0.25 is half way the first function');
  AssertNear(1.0, Function_.Eval([0.5])[0], OutputTolerance, 'a bound belongs to the function after it');
  AssertNear(0.0, Function_.Eval([1])[0], OutputTolerance, 'the end of the domain belongs to the last function');
  AssertNear(0.0, Function_.Eval([2])[0], OutputTolerance, 'the input is clipped to the domain');
  Assert.AreEqual(3, Function_.FunctionType);
end;

procedure TFunctionTests.TestType3OutsideEveryPartitionGivesZeros;
begin
  const Dictionary = FBuilder.NewType3('0 1', '0.5', '0 1 0 1',
                              [FBuilder.NewType2('0 1', '0 0', '1 1', 1), FBuilder.NewType2('0 1', '1 1', '0 0', 1)]);
  const Function_ = Make(Dictionary);

  const Values = Function_.Eval([NaN]);

  AssertCount(2, Length(Values));
  AssertNear(0.0, Values[0], OutputTolerance);
  AssertNear(0.0, Values[1], OutputTolerance);
end;

procedure TFunctionTests.TestType3WithoutFunctionsOrBoundsRaises;
begin
  var Broken: TArray<TCosDictionary> := [
    FBuilder.NewType3('0 1', '0.5', '0 1 0 1', []),
    FBuilder.NewType3('0 1', '', '0 1 0 1', [FBuilder.NewType2('0 1', '0', '1', 1), FBuilder.NewType2('0 1', '1', '0', 1)]),
    FBuilder.NewType3('', '', '0 1', [FBuilder.NewType2('0 1', '0', '1', 1)])];

  for var Invalid in Broken do
  begin
    Assert.WillRaise(
      procedure
      begin
        TPDFunction.Create(Invalid, FBuilder.Context).Free;
      end, EPdfParseException);
  end;
end;

procedure TFunctionTests.TestType3ParameterCounts;
begin
  const Dictionary = FBuilder.NewType3('0 1', '', '0 1', [FBuilder.NewType2('0 1', '0 0', '1 1', 1)]);
  const Function_ = Make(Dictionary);

  Assert.AreEqual(1, Function_.NumberOfInputParameters);
  Assert.AreEqual(2, Function_.NumberOfOutputParameters, 'without a Range the first function says');
end;

procedure TFunctionTests.TestStitchingRecursionStops;
begin
  const Document: string = '<< /FunctionType 3 /Domain [0 1] /Functions [3 0 R] /Bounds [] /Encode [0 1] >>';

  Assert.WillRaise(
    procedure
    begin
      OpenFunction([Document]);
    end, EPdfParseException);
end;

procedure TFunctionTests.TestStitchingOfEightLevelsWorksAndNineRaises;
begin
  var Levels: TArray<Integer> := [8, 9];
  for var Count in Levels do
  begin
    var Objects: TArray<string>;
    SetLength(Objects, Count + 1);
    for var Index := 0 to Count - 1 do
    begin
      Objects[Index] := Format('<< /FunctionType 3 /Domain [0 1] /Functions [%d 0 R] /Bounds [] /Encode [0 1] >>', [4 + Index]);
    end;
    Objects[Count] := '<< /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [1] /N 1 >>';

    if Count <= MaxStitchingDepth then
    begin
      const Values = OpenFunction(Objects).Eval([0.25]);
      AssertNear(0.25, Values[0], OutputTolerance, Format('%d levels', [Count]));
    end
    else
    begin
      Assert.WillRaise(
        procedure
        begin
          OpenFunction(Objects);
        end, EPdfParseException, Format('%d levels', [Count]));
    end;
  end;
end;

procedure TFunctionTests.TestStitchingFanOutIsBounded;
begin
  const Bounds = Repeated('0.5 ', 149);
  const Functions = Repeated('4 0 R ', 150);
  const Leaves = Repeated('5 0 R ', 150);
  const Outer = Format('<< /FunctionType 3 /Domain [0 1] /Functions [%s] /Bounds [%s] /Encode [%s] >>', [Functions, Bounds, Repeated('0 1 ', 150)]);
  const Inner = Format('<< /FunctionType 3 /Domain [0 1] /Functions [%s] /Bounds [%s] /Encode [%s] >>', [Leaves, Bounds, Repeated('0 1 ', 150)]);

  Assert.WillRaise(
    procedure
    begin
      OpenFunction([Outer, Inner, '<< /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [1] /N 1 >>']);
    end, EPdfParseException);
end;

// Three tables of 6 million samples each (a 1 bit table is small as data, large once it is read) are over the limit together
procedure TFunctionTests.TestSampleTablesOfOneTreeAreBoundedTogether;
begin
  var Data: TBytes := nil;
  SetLength(Data, 750000);
  const Domain = '0 1';
  const TwoTables = FBuilder.NewType3(Domain, '0.5', '0 1 0 1',
    [NewType0(Domain, '0 1', '6000000', 1, Data), NewType0(Domain, '0 1', '6000000', 1, Data)]);
  const ThreeTables = FBuilder.NewType3(Domain, '0.3 0.6', '0 1 0 1 0 1',
    [NewType0(Domain, '0 1', '6000000', 1, Data), NewType0(Domain, '0 1', '6000000', 1, Data),
     NewType0(Domain, '0 1', '6000000', 1, Data)]);

  Make(TwoTables);
  Assert.WillRaise(
    procedure
    begin
      Make(ThreeTables);
    end, EPdfParseException);
end;

procedure TFunctionTests.TestIdentityGivesItsInput;
begin
  const Identity = TCosName.Create(TCosNames.Identity);
  try
    const Function_ = Make(Identity);

    const Values = Function_.Eval([0.25, 0.75, 3]);

    AssertCount(3, Length(Values));
    AssertNear(0.25, Values[0], 0.0000001);
    AssertNear(3.0, Values[2], 0.0000001);
    Assert.AreEqual(-1, Function_.FunctionType);
    AssertCount(0, Length(Function_.Eval([])), 'no input gives no output');
  finally
    Identity.Free;
  end;
end;

procedure TFunctionTests.TestCreateRaisesForWhatIsNoFunction;
begin
  const Integer_ = TCosInteger.Create(3);
  const Other = TCosName.Create('Linear');
  const UnknownType = FBuilder.NewDictionary(1, [TCosNames.Domain, '0 1']);
  const NoType = FBuilder.NewDictionary(2, []);
  NoType.RemoveItem(TCosNames.FunctionType);
  try
    var Values: TArray<TCosBase> := [nil, Integer_, Other, UnknownType, NoType];
    for var Value in Values do
    begin
      Assert.WillRaise(
        procedure
        begin
          TPDFunction.Create(Value, FBuilder.Context).Free;
        end, EPdfParseException);
    end;
  finally
    Other.Free;
    Integer_.Free;
  end;
end;

procedure TFunctionTests.TestEvalNeverRaises;
begin
  var Subjects: TArray<TCosBase> := [
    FBuilder.NewType2('0 1', '0 0', '1 1', 0.5),
    NewType0('0 1 0 1', '0 1', '2 2', 8, [$00, $FF, $80, $20]),
    FBuilder.NewType3('0 1', '0.5', '0 1 0 1', [FBuilder.NewType2('0 1', '0', '1', -1), FBuilder.NewType2('0 1', '1', '0', 2)]),
    FBuilder.NewType4('0 1 0 1', '0 1', '{ add dup mul 2 exch div }'),
    FBuilder.NewType4('0 1', '0 1', '{ exch pop }')];
  var Inputs: TArray<TArray<Single>> := [[], [NaN], [Infinity], [NegInfinity], [3.0E38, -3.0E38, 3.0E38], [0.5, 0.5, 0.5, 0.5, 0.5]];

  for var Subject in Subjects do
  begin
    const Function_ = Make(Subject);
    for var Input in Inputs do
    begin
      Assert.WillNotRaiseAny(
        procedure
        begin
          Function_.Eval(Input);
        end, Format('type %d with %d values', [Function_.FunctionType, Length(Input)]));
    end;
  end;
end;

procedure TFunctionTests.CheckEvaluation(const Context: string; const Reference: TPDFunction; const Evaluation: TFunctionEvaluation);
begin
  const Actual = Reference.Eval(Evaluation.Input);
  if Evaluation.HasFailedInPdfBox then
  begin
    Exit;
  end;

  Assert.AreEqual(Length(Evaluation.Expected), Length(Actual), Format('%s: number of outputs (%s)', [Context, Describe(Actual)]));
  for var Index := 0 to Length(Actual) - 1 do
  begin
    Assert.IsTrue(SameValue(Evaluation.Expected[Index], Actual[Index]),
                  Format('%s: output %d is %s, PDFBox gives %s', [Context, Index, FloatToStr(Actual[Index], TFormatSettings.Invariant),
                                                                   FloatToStr(Evaluation.Expected[Index], TFormatSettings.Invariant)]));
  end;
end;

procedure TFunctionTests.CheckCase(const FileName: string; const FunctionCase: TFunctionCase);
begin
  const Dictionary = FBuilder.NewFromCase(FunctionCase);
  if FunctionCase.HasFailedToCreateInPdfBox then
  begin
    Assert.WillRaise(
      procedure
      begin
        TPDFunction.Create(Dictionary, FBuilder.Context).Free;
      end, EPdfParseException, Format('%s %s', [FileName, FunctionCase.Name]));
    Exit;
  end;

  const Reference = Make(Dictionary);
  for var Evaluation in FunctionCase.Evaluations do
  begin
    CheckEvaluation(Format('%s %s with %s', [FileName, FunctionCase.Name, Describe(Evaluation.Input)]), Reference, Evaluation);
  end;
end;

procedure TFunctionTests.TestFunctionsMatchPdfBox;
begin
  var CaseCount := 0;
  for var FileName in TFunctionReferences.Files do
  begin
    const Cases = TFunctionReferences.ReadCases(FileName);
    try
      for var FunctionCase in Cases do
      begin
        CheckCase(ExtractFileName(FileName), FunctionCase);
        Inc(CaseCount);
      end;
    finally
      Cases.Free;
    end;
  end;

  Assert.IsTrue(CaseCount > 0, 'no reference files were found');
end;

end.
