// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/test/java/org/apache/fontbox/afm/AFMParserTest.java, FontMetricsTest.java and CharMetricTest.java (3.0.8)
unit Pdf4D.FontBox.AfmParser.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.FontBox.BoundingBox,
  Pdf4D.FontBox.Afm,
  Pdf4D.FontBox.AfmParser;

type
  [TestFixture]
  TAfmParserTests = class
  private
    function HelveticaData: TBytes;
    function ParseText(const Text: string; const ReducedDataset: Boolean = False): TFontMetrics;
    function IsParseFailure(const Text: string; const ReducedDataset: Boolean = False): Boolean;
    procedure CheckSingle(const Expected, Actual: Single);
    procedure CheckBoundingBox(const Box: TBoundingBox; const LowerX, LowerY, UpperX, UpperY: Single);
    procedure CheckHelveticaFontMetrics(const Metrics: TFontMetrics);
    procedure CheckHelveticaCharMetrics(const Metrics: TFontMetrics);
    function FindKernPair(const Metrics: TFontMetrics; const First, Second: string; out Pair: TKernPair): Boolean;

  public
    [Test]
    procedure TestStartFontMetrics;

    [Test]
    procedure TestEndFontMetrics;

    [Test]
    procedure TestMalformedFloat;

    [Test]
    procedure TestMalformedInteger;

    [Test]
    procedure TestHelveticaFontMetrics;

    [Test]
    procedure TestHelveticaCharMetrics;

    [Test]
    procedure TestHelveticaKernPairs;

    [Test]
    procedure TestHelveticaFontMetricsReducedDataset;

    [Test]
    procedure TestHelveticaCharMetricsReducedDataset;

    [Test]
    procedure TestHelveticaKernPairsReducedDataset;

    [Test]
    procedure TestKernDataCompositesAndLigatures;

    [Test]
    procedure TestParseCanRunTwice;

    [Test]
    procedure TestTruncatedDataRaisesParseError;

    [Test]
    procedure TestHugeCountsEndAtTheEndOfTheData;

    [Test]
    procedure TestMalformedPartsRaiseParseError;

    [Test]
    procedure TestFontMetricsNames;

    [Test]
    procedure TestFontMetricsSimpleValues;

    [Test]
    procedure TestFontMetricsComplexValues;

    [Test]
    procedure TestMetricSets;

    [Test]
    procedure TestCharMetricsAndWidths;

    [Test]
    procedure TestCharMetricSimpleValues;

    [Test]
    procedure TestCharMetricArrayValues;

    [Test]
    procedure TestCharMetricComplexValues;
  end;

implementation

uses
  System.Classes,
  Pdf4D.Common.Defines,
  Pdf4D.Resources.Afm;

const
  MalformedFloatAfm   = 'StartFontMetrics 4,1ab' + #10;
  MalformedIntegerAfm = 'StartFontMetrics 4.1' + #10 + #10 + 'Characters 3.4' + #10;
  NoEndFontMetricsAfm = 'StartFontMetrics 13.2' + #10 + #10 +
                        'Comment This is a fake copyright notice for an AFM test file' + #10 + #10 +
                        'Comment Creation Date: Thu Nov 13 06:30:00 2020' + #10 + #10 +
                        'Comment Some more text' + #10;
  StartCharMetricsAfm = 'StartFontMetrics 4.1' + #10 + 'StartCharMetrics ';

  // Kern pairs of every kind, track kerning, composites and ligatures
  FullAfm = 'StartFontMetrics 4.1' + #10 +
            'FontName Test' + #10 +
            'IsFixedV false' + #10 +
            'StartCharMetrics 2' + #10 +
            'C 102 ; WX 278 ; N f ; B 14 0 273 728 ; L i fi ; L l fl ;' + #10 +
            'CH 41 ; WX 667 ; N A ; W0 1 2 ; VV 3 4 ;' + #10 +
            'EndCharMetrics' + #10 +
            'StartKernData' + #10 +
            'StartTrackKern 1' + #10 +
            '-1 6 -0.5 18 -1' + #10 +
            'EndTrackKern' + #10 +
            'StartKernPairs 3' + #10 +
            'KP A V -70 5' + #10 +
            'KPH <41> <56> -60 0' + #10 +
            'KPY A W 7' + #10 +
            'EndKernPairs' + #10 +
            'StartKernPairs0 1' + #10 +
            'KPX A T -30' + #10 +
            'EndKernPairs' + #10 +
            'StartKernPairs1 1' + #10 +
            'KPX A Y -20' + #10 +
            'EndKernPairs' + #10 +
            'EndKernData' + #10 +
            'StartComposites 1' + #10 +
            'CC Aacute 2 ; PCC A 0 0 ; PCC acute 195 224 ;' + #10 +
            'EndComposites' + #10 +
            'EndFontMetrics' + #10;

{ TAfmParserTests }

function TAfmParserTests.HelveticaData: TBytes;
begin
  Result := TPdfAfmResources.Load('Helvetica');
end;

function TAfmParserTests.ParseText(const Text: string; const ReducedDataset: Boolean): TFontMetrics;
begin
  const Parser = TAFMParser.Create(TEncoding.ASCII.GetBytes(Text));
  try
    Result := Parser.Parse(ReducedDataset);
  finally
    Parser.Free;
  end;
end;

function TAfmParserTests.IsParseFailure(const Text: string; const ReducedDataset: Boolean): Boolean;
begin
  try
    ParseText(Text, ReducedDataset).Free;
    Result := False;
  except
    on EPdfParseException do
    begin
      Result := True;
    end;
  end;
end;

procedure TAfmParserTests.CheckSingle(const Expected, Actual: Single);
begin
  Assert.AreEqual(Double(Expected), Double(Actual), 0.0);
end;

procedure TAfmParserTests.CheckBoundingBox(const Box: TBoundingBox; const LowerX, LowerY, UpperX, UpperY: Single);
begin
  CheckSingle(LowerX, Box.LowerLeftX);
  CheckSingle(LowerY, Box.LowerLeftY);
  CheckSingle(UpperX, Box.UpperRightX);
  CheckSingle(UpperY, Box.UpperRightY);
end;

function TAfmParserTests.FindKernPair(const Metrics: TFontMetrics; const First, Second: string; out Pair: TKernPair): Boolean;
begin
  for var Candidate in Metrics.KernPairs do
  begin
    if (Candidate.FirstKernCharacter = First) and (Candidate.SecondKernCharacter = Second) then
    begin
      Pair := Candidate;
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TAfmParserTests.CheckHelveticaFontMetrics(const Metrics: TFontMetrics);
begin
  CheckSingle(4.1, Metrics.AFMVersion);
  Assert.AreEqual('Helvetica', Metrics.FontName);
  Assert.AreEqual('Helvetica', Metrics.FullName);
  Assert.AreEqual('Helvetica', Metrics.FamilyName);
  Assert.AreEqual('Medium', Metrics.Weight);
  Assert.IsTrue(Metrics.HasFontBBox);
  CheckBoundingBox(Metrics.FontBBox, -166, -225, 1000, 931);
  Assert.AreEqual('002.000', Metrics.FontVersion);
  Assert.AreEqual('Copyright (c) 1985, 1987, 1989, 1990, 1997 Adobe Systems Incorporated.  All Rights Reserved.' +
                  'Helvetica is a trademark of Linotype-Hell AG and/or its subsidiaries.', Metrics.Notice);
  Assert.AreEqual('AdobeStandardEncoding', Metrics.EncodingScheme);
  Assert.AreEqual<Integer>(0, Metrics.MappingScheme);
  Assert.AreEqual<Integer>(0, Metrics.EscChar);
  Assert.AreEqual('ExtendedRoman', Metrics.CharacterSet);
  Assert.AreEqual<Integer>(0, Metrics.Characters);
  Assert.IsTrue(Metrics.IsBaseFont);
  Assert.AreEqual<Integer>(0, Length(Metrics.VVector));
  Assert.IsFalse(Metrics.IsFixedV);
  CheckSingle(718, Metrics.CapHeight);
  CheckSingle(523, Metrics.XHeight);
  CheckSingle(718, Metrics.Ascender);
  CheckSingle(-207, Metrics.Descender);
  CheckSingle(76, Metrics.StandardHorizontalWidth);
  CheckSingle(88, Metrics.StandardVerticalWidth);
  Assert.AreEqual<Integer>(4, Metrics.Comments.Count);
  Assert.AreEqual('Copyright (c) 1985, 1987, 1989, 1990, 1997 Adobe Systems Incorporated.  All Rights Reserved.', Metrics.Comments[0]);
  Assert.AreEqual('UniqueID 43054', Metrics.Comments[2]);
  CheckSingle(-100, Metrics.UnderlinePosition);
  CheckSingle(50, Metrics.UnderlineThickness);
  CheckSingle(0, Metrics.ItalicAngle);
  Assert.AreEqual<Integer>(0, Length(Metrics.CharWidth));
  Assert.IsFalse(Metrics.IsFixedPitch);
end;

procedure TAfmParserTests.CheckHelveticaCharMetrics(const Metrics: TFontMetrics);
begin
  Assert.AreEqual<Integer>(315, Metrics.CharMetrics.Count);
  var Space: TCharMetric := nil;
  var Ring: TCharMetric := nil;
  for var Metric in Metrics.CharMetrics do
  begin
    if Metric.Name = 'space' then
    begin
      Space := Metric;
    end
    else if Metric.Name = 'ring' then
    begin
      Ring := Metric;
    end;
  end;

  Assert.IsNotNull(Space);
  CheckSingle(278, Space.Wx);
  Assert.AreEqual<Integer>(32, Space.CharacterCode);
  Assert.IsTrue(Space.HasBoundingBox);
  CheckBoundingBox(Space.BoundingBox, 0, 0, 0, 0);
  Assert.AreEqual<Integer>(0, Space.Ligatures.Count);
  Assert.AreEqual<Integer>(0, Length(Space.W));
  Assert.AreEqual<Integer>(0, Length(Space.W0));
  Assert.AreEqual<Integer>(0, Length(Space.W1));
  Assert.AreEqual<Integer>(0, Length(Space.Vv));

  Assert.IsNotNull(Ring);
  CheckSingle(333, Ring.Wx);
  Assert.AreEqual<Integer>(202, Ring.CharacterCode);
  CheckBoundingBox(Ring.BoundingBox, 75, 572, 259, 756);
  Assert.AreEqual<Integer>(0, Ring.Ligatures.Count);
end;

procedure TAfmParserTests.TestStartFontMetrics;
begin
  Assert.IsTrue(IsParseFailure('huhu'), 'A missing StartFontMetrics must raise a parse error');
end;

procedure TAfmParserTests.TestEndFontMetrics;
begin
  var Message := '';
  try
    ParseText(NoEndFontMetricsAfm).Free;
  except
    on E: EPdfParseException do
    begin
      Message := E.Message;
    end;
  end;

  Assert.Contains(Message, 'Unknown AFM key');
end;

procedure TAfmParserTests.TestMalformedFloat;
begin
  var Message := '';
  try
    ParseText(MalformedFloatAfm).Free;
  except
    on E: EPdfParseException do
    begin
      Message := E.Message;
    end;
  end;

  Assert.Contains(Message, '4,1ab');
end;

procedure TAfmParserTests.TestMalformedInteger;
begin
  var Message := '';
  try
    ParseText(MalformedIntegerAfm).Free;
  except
    on E: EPdfParseException do
    begin
      Message := E.Message;
    end;
  end;

  Assert.Contains(Message, '3.4');
end;

procedure TAfmParserTests.TestHelveticaFontMetrics;
begin
  const Parser = TAFMParser.Create(HelveticaData);
  try
    const Metrics = Parser.Parse(False);
    try
      CheckHelveticaFontMetrics(Metrics);
    finally
      Metrics.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TAfmParserTests.TestHelveticaCharMetrics;
begin
  const Parser = TAFMParser.Create(HelveticaData);
  try
    const Metrics = Parser.Parse(False);
    try
      CheckHelveticaCharMetrics(Metrics);
    finally
      Metrics.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TAfmParserTests.TestHelveticaKernPairs;
begin
  const Parser = TAFMParser.Create(HelveticaData);
  try
    const Metrics = Parser.Parse(False);
    try
      Assert.AreEqual<Integer>(2705, Metrics.KernPairs.Count);
      var Pair: TKernPair;
      Assert.IsTrue(FindKernPair(Metrics, 'A', 'Ucircumflex', Pair));
      CheckSingle(-50, Pair.X);
      CheckSingle(0, Pair.Y);
      Assert.IsTrue(FindKernPair(Metrics, 'W', 'agrave', Pair));
      CheckSingle(-40, Pair.X);
      Assert.IsTrue(FindKernPair(Metrics, 'A', 'V', Pair));
      CheckSingle(-70, Pair.X);
      Assert.AreEqual<Integer>(0, Metrics.KernPairs0.Count);
      Assert.AreEqual<Integer>(0, Metrics.KernPairs1.Count);
      Assert.AreEqual<Integer>(0, Metrics.Composites.Count);
    finally
      Metrics.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TAfmParserTests.TestHelveticaFontMetricsReducedDataset;
begin
  const Parser = TAFMParser.Create(HelveticaData);
  try
    const Metrics = Parser.Parse(True);
    try
      CheckHelveticaFontMetrics(Metrics);
    finally
      Metrics.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TAfmParserTests.TestHelveticaCharMetricsReducedDataset;
begin
  const Parser = TAFMParser.Create(HelveticaData);
  try
    const Metrics = Parser.Parse(True);
    try
      CheckHelveticaCharMetrics(Metrics);
    finally
      Metrics.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TAfmParserTests.TestHelveticaKernPairsReducedDataset;
begin
  const Parser = TAFMParser.Create(HelveticaData);
  try
    const Metrics = Parser.Parse(True);
    try
      Assert.AreEqual<Integer>(0, Metrics.KernPairs.Count);
      Assert.AreEqual<Integer>(0, Metrics.KernPairs0.Count);
      Assert.AreEqual<Integer>(0, Metrics.KernPairs1.Count);
      Assert.AreEqual<Integer>(0, Metrics.Composites.Count);
    finally
      Metrics.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TAfmParserTests.TestKernDataCompositesAndLigatures;
begin
  const Metrics = ParseText(FullAfm);
  try
    Assert.IsFalse(Metrics.IsFixedV);
    Assert.AreEqual<Integer>(2, Metrics.CharMetrics.Count);
    const FirstMetric = Metrics.CharMetrics[0];
    Assert.AreEqual<Integer>(2, FirstMetric.Ligatures.Count);
    Assert.AreEqual('i', FirstMetric.Ligatures[0].Successor);
    Assert.AreEqual('fl', FirstMetric.Ligatures[1].Ligature);
    CheckBoundingBox(FirstMetric.BoundingBox, 14, 0, 273, 728);
    const SecondMetric = Metrics.CharMetrics[1];
    Assert.AreEqual<Integer>(65, SecondMetric.CharacterCode);
    Assert.AreEqual<Integer>(2, Length(SecondMetric.W0));
    CheckSingle(2, SecondMetric.W0[1]);
    CheckSingle(4, SecondMetric.Vv[1]);

    Assert.AreEqual<Integer>(1, Metrics.TrackKern.Count);
    Assert.AreEqual<Integer>(-1, Metrics.TrackKern[0].Degree);
    CheckSingle(-0.5, Metrics.TrackKern[0].MinKern);
    CheckSingle(18, Metrics.TrackKern[0].MaxPointSize);

    Assert.AreEqual<Integer>(3, Metrics.KernPairs.Count);
    CheckSingle(5, Metrics.KernPairs[0].Y);
    Assert.AreEqual('V', Metrics.KernPairs[1].SecondKernCharacter);
    Assert.AreEqual('A', Metrics.KernPairs[1].FirstKernCharacter);
    CheckSingle(7, Metrics.KernPairs[2].Y);
    CheckSingle(0, Metrics.KernPairs[2].X);
    Assert.AreEqual<Integer>(1, Metrics.KernPairs0.Count);
    CheckSingle(-30, Metrics.KernPairs0[0].X);
    Assert.AreEqual<Integer>(1, Metrics.KernPairs1.Count);
    CheckSingle(-20, Metrics.KernPairs1[0].X);

    Assert.AreEqual<Integer>(1, Metrics.Composites.Count);
    Assert.AreEqual('Aacute', Metrics.Composites[0].Name);
    Assert.AreEqual<Integer>(2, Metrics.Composites[0].Parts.Count);
    Assert.AreEqual('acute', Metrics.Composites[0].Parts[1].Name);
    Assert.AreEqual<Integer>(195, Metrics.Composites[0].Parts[1].XDisplacement);
    Assert.AreEqual<Integer>(224, Metrics.Composites[0].Parts[1].YDisplacement);
  finally
    Metrics.Free;
  end;
end;

procedure TAfmParserTests.TestParseCanRunTwice;
begin
  const Parser = TAFMParser.Create(TEncoding.ASCII.GetBytes(FullAfm));
  try
    Parser.Parse(False).Free;
    const Metrics = Parser.Parse(False);
    try
      Assert.AreEqual<Integer>(2, Metrics.CharMetrics.Count);
    finally
      Metrics.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TAfmParserTests.TestTruncatedDataRaisesParseError;
begin
  const Data = HelveticaData;
  const Step = 997;
  var Cut := 0;
  while Cut < Length(Data) do
  begin
    var Truncated := Copy(Data, 0, Cut);
    for var Reduced in [False, True] do
    begin
      const Parser = TAFMParser.Create(Truncated);
      try
        try
          Parser.Parse(Reduced).Free;
        except
          on EPdfParseException do
          begin
            // expected: only a parse error may come out of damaged data
          end;
        end;
      finally
        Parser.Free;
      end;
    end;
    Inc(Cut, Step);
  end;
  Assert.Pass;
end;

procedure TAfmParserTests.TestHugeCountsEndAtTheEndOfTheData;
begin
  Assert.IsTrue(IsParseFailure(StartCharMetricsAfm + '2000000000' + #10 + 'C 32 ; WX 278 ; N space ;' + #10));
  Assert.IsTrue(IsParseFailure(StartCharMetricsAfm + '2000000000' + #10, True));
  Assert.IsTrue(IsParseFailure('StartFontMetrics 4.1' + #10 + 'StartKernData' + #10 + 'StartKernPairs 2147483647' + #10 +
                               'KPX A V -70' + #10));
  Assert.IsTrue(IsParseFailure('StartFontMetrics 4.1' + #10 + 'StartComposites 2147483647' + #10 +
                               'CC Aacute 0 ;' + #10));
  Assert.IsTrue(IsParseFailure('StartFontMetrics 4.1' + #10 + 'StartKernData' + #10 + 'StartTrackKern 2147483647' + #10 +
                               '1 2 3 4 5' + #10));
  Assert.IsTrue(IsParseFailure('StartFontMetrics 4.1' + #10 + 'Characters 2147483648' + #10));
end;

procedure TAfmParserTests.TestMalformedPartsRaiseParseError;
begin
  const Header = 'StartFontMetrics 4.1' + #10;
  Assert.IsTrue(IsParseFailure(Header + 'StartCharMetrics 1' + #10 + 'C 32 ; WX 278 ; Q 5 ;' + #10 + 'EndCharMetrics' + #10));
  Assert.IsTrue(IsParseFailure(Header + 'StartCharMetrics 1' + #10 + 'C 32 WX 278 ;' + #10 + 'EndCharMetrics' + #10));
  Assert.IsTrue(IsParseFailure(Header + 'StartCharMetrics 1' + #10 + 'C 32 ;WX' + #10 + 'EndCharMetrics' + #10));
  Assert.IsTrue(IsParseFailure(Header + 'StartCharMetrics 1' + #10 + 'C 32' + #10 + 'EndCharMetrics' + #10));
  Assert.IsTrue(IsParseFailure(Header + 'StartKernData' + #10 + 'StartBogus' + #10));
  Assert.IsTrue(IsParseFailure(Header + 'StartKernData' + #10 + 'StartKernPairs 1' + #10 + 'KPH 41 56 -60 0' + #10 +
                               'EndKernPairs' + #10 + 'EndKernData' + #10));
  Assert.IsTrue(IsParseFailure(Header + 'StartKernData' + #10 + 'StartKernPairs 1' + #10 + 'KPH <4> <56> -60 0' + #10 +
                               'EndKernPairs' + #10 + 'EndKernData' + #10));
  Assert.IsTrue(IsParseFailure(Header + 'StartKernData' + #10 + 'StartKernPairs 1' + #10 + 'KPZ A V 1' + #10 +
                               'EndKernPairs' + #10 + 'EndKernData' + #10));
  Assert.IsTrue(IsParseFailure(Header + 'StartComposites 1' + #10 + 'XX Aacute 0 ;' + #10 + 'EndComposites' + #10));
  Assert.IsTrue(IsParseFailure(Header + 'StartComposites 1' + #10 + 'CC Aacute 1 ; XXX A 0 0 ;' + #10 + 'EndComposites' + #10));
  Assert.IsTrue(IsParseFailure(Header + 'UnknownKey 1' + #10 + 'EndFontMetrics' + #10));
end;

procedure TAfmParserTests.TestFontMetricsNames;
begin
  const Metrics = TFontMetrics.Create;
  try
    Metrics.FontName := 'fontName';
    Metrics.FamilyName := 'familyName';
    Metrics.FullName := 'fullName';
    Metrics.FontVersion := 'fontVersion';
    Metrics.Notice := 'notice';
    Assert.AreEqual('fontName', Metrics.FontName);
    Assert.AreEqual('familyName', Metrics.FamilyName);
    Assert.AreEqual('fullName', Metrics.FullName);
    Assert.AreEqual('fontVersion', Metrics.FontVersion);
    Assert.AreEqual('notice', Metrics.Notice);

    Assert.AreEqual<Integer>(0, Metrics.Comments.Count);
    Metrics.AddComment('comment');
    Assert.AreEqual<Integer>(1, Metrics.Comments.Count);
  finally
    Metrics.Free;
  end;
end;

procedure TAfmParserTests.TestFontMetricsSimpleValues;
begin
  const Metrics = TFontMetrics.Create;
  try
    Metrics.AFMVersion := 4.3;
    Metrics.Weight := 'weight';
    Metrics.EncodingScheme := 'encodingScheme';
    Metrics.MappingScheme := 0;
    Metrics.EscChar := 0;
    Metrics.CharacterSet := 'characterSet';
    Metrics.Characters := 10;
    Metrics.IsBaseFont := True;
    Metrics.IsFixedV := True;
    Metrics.CapHeight := 10;
    Metrics.XHeight := 20;
    Metrics.Ascender := 30;
    Metrics.Descender := 40;
    Metrics.StandardHorizontalWidth := 50;
    Metrics.StandardVerticalWidth := 60;
    Metrics.UnderlinePosition := 70;
    Metrics.UnderlineThickness := 80;
    Metrics.ItalicAngle := 90;
    Metrics.IsFixedPitch := True;

    CheckSingle(4.3, Metrics.AFMVersion);
    Assert.AreEqual('weight', Metrics.Weight);
    Assert.AreEqual('encodingScheme', Metrics.EncodingScheme);
    Assert.AreEqual<Integer>(0, Metrics.MappingScheme);
    Assert.AreEqual<Integer>(0, Metrics.EscChar);
    Assert.AreEqual('characterSet', Metrics.CharacterSet);
    Assert.AreEqual<Integer>(10, Metrics.Characters);
    Assert.IsTrue(Metrics.IsBaseFont);
    Assert.IsTrue(Metrics.IsFixedV);
    CheckSingle(10, Metrics.CapHeight);
    CheckSingle(20, Metrics.XHeight);
    CheckSingle(30, Metrics.Ascender);
    CheckSingle(40, Metrics.Descender);
    CheckSingle(50, Metrics.StandardHorizontalWidth);
    CheckSingle(60, Metrics.StandardVerticalWidth);
    CheckSingle(70, Metrics.UnderlinePosition);
    CheckSingle(80, Metrics.UnderlineThickness);
    CheckSingle(90, Metrics.ItalicAngle);
    Assert.IsTrue(Metrics.IsFixedPitch);
  finally
    Metrics.Free;
  end;
end;

procedure TAfmParserTests.TestFontMetricsComplexValues;
begin
  const Metrics = TFontMetrics.Create;
  try
    Assert.IsFalse(Metrics.HasFontBBox);
    Assert.IsFalse(Metrics.IsFixedV);
    Metrics.FontBBox := TBoundingBox.Create(10, 20, 30, 40);
    Metrics.VVector := [10, 20];
    Metrics.CharWidth := [30, 40];

    Assert.IsTrue(Metrics.HasFontBBox);
    CheckBoundingBox(Metrics.FontBBox, 10, 20, 30, 40);
    CheckSingle(10, Metrics.VVector[0]);
    CheckSingle(20, Metrics.VVector[1]);
    CheckSingle(30, Metrics.CharWidth[0]);
    CheckSingle(40, Metrics.CharWidth[1]);
    Assert.IsTrue(Metrics.IsFixedV, 'Without an explicit value IsFixedV follows the V vector');
  finally
    Metrics.Free;
  end;
end;

procedure TAfmParserTests.TestMetricSets;
begin
  const Metrics = TFontMetrics.Create;
  try
    Metrics.MetricSets := 1;
    Assert.AreEqual<Integer>(1, Metrics.MetricSets);
    Assert.WillRaise(
      procedure
      begin
        Metrics.MetricSets := -1;
      end,
      EArgumentOutOfRangeException);
    Assert.WillRaise(
      procedure
      begin
        Metrics.MetricSets := 3;
      end,
      EArgumentOutOfRangeException);
  finally
    Metrics.Free;
  end;
end;

procedure TAfmParserTests.TestCharMetricsAndWidths;
begin
  const Metrics = TFontMetrics.Create;
  try
    Assert.AreEqual<Integer>(0, Metrics.CharMetrics.Count);
    CheckSingle(0, Metrics.GetAverageCharacterWidth);
    CheckSingle(0, Metrics.GetCharacterWidth('A'));

    const First = TCharMetric.Create;
    First.Name := 'A';
    First.Wx := 600;
    First.BoundingBox := TBoundingBox.Create(0, 0, 500, 700);
    Metrics.AddCharMetric(First);
    const Second = TCharMetric.Create;
    Second.Name := 'B';
    Second.Wx := 800;
    Second.Wy := 25;
    Metrics.AddCharMetric(Second);
    Metrics.AddCharMetric(TCharMetric.Create);

    Assert.AreEqual<Integer>(3, Metrics.CharMetrics.Count);
    CheckSingle(600, Metrics.GetCharacterWidth('A'));
    CheckSingle(0, Metrics.GetCharacterWidth('Missing'));
    CheckSingle(700, Metrics.GetCharacterHeight('A'));
    CheckSingle(25, Metrics.GetCharacterHeight('B'));
    CheckSingle(0, Metrics.GetCharacterHeight('Missing'));
    CheckSingle(700, Metrics.GetAverageCharacterWidth);
  finally
    Metrics.Free;
  end;
end;

procedure TAfmParserTests.TestCharMetricSimpleValues;
begin
  const Metric = TCharMetric.Create;
  try
    Metric.CharacterCode := 0;
    Metric.Name := 'name';
    Metric.Wx := 10;
    Metric.W0x := 20;
    Metric.W1x := 30;
    Metric.Wy := 40;
    Metric.W0y := 50;
    Metric.W1y := 60;

    Assert.AreEqual<Integer>(0, Metric.CharacterCode);
    Assert.AreEqual('name', Metric.Name);
    CheckSingle(10, Metric.Wx);
    CheckSingle(20, Metric.W0x);
    CheckSingle(30, Metric.W1x);
    CheckSingle(40, Metric.Wy);
    CheckSingle(50, Metric.W0y);
    CheckSingle(60, Metric.W1y);
  finally
    Metric.Free;
  end;
end;

procedure TAfmParserTests.TestCharMetricArrayValues;
begin
  const Metric = TCharMetric.Create;
  try
    Metric.W := [10, 20];
    Metric.W0 := [30, 40];
    Metric.W1 := [50, 60];
    Metric.Vv := [70, 80];

    CheckSingle(10, Metric.W[0]);
    CheckSingle(20, Metric.W[1]);
    CheckSingle(30, Metric.W0[0]);
    CheckSingle(40, Metric.W0[1]);
    CheckSingle(50, Metric.W1[0]);
    CheckSingle(60, Metric.W1[1]);
    CheckSingle(70, Metric.Vv[0]);
    CheckSingle(80, Metric.Vv[1]);
  finally
    Metric.Free;
  end;
end;

procedure TAfmParserTests.TestCharMetricComplexValues;
begin
  const Metric = TCharMetric.Create;
  try
    Assert.IsFalse(Metric.HasBoundingBox);
    Metric.BoundingBox := TBoundingBox.Create(10, 20, 30, 40);
    CheckBoundingBox(Metric.BoundingBox, 10, 20, 30, 40);

    Assert.AreEqual<Integer>(0, Metric.Ligatures.Count);
    Metric.AddLigature(TLigature.Create('successor', 'ligature'));
    Assert.AreEqual<Integer>(1, Metric.Ligatures.Count);
    Assert.AreEqual('successor', Metric.Ligatures[0].Successor);
    Assert.AreEqual('ligature', Metric.Ligatures[0].Ligature);
  finally
    Metric.Free;
  end;
end;

end.
