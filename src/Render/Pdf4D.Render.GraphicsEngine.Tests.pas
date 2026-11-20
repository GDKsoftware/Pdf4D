// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of the graphics state, the dash pattern and the path, colour and state operators of the graphics engine (PDFBox 3.0.8)
unit Pdf4D.Render.GraphicsEngine.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Common.Log,
  Pdf4D.Common.Matrix,
  Pdf4D.Content.Operator,
  Pdf4D.Cos.Base,
  Pdf4D.Common.Path,
  Pdf4D.Graphics.Image,
  Pdf4D.Graphics.State,
  Pdf4D.Model.DocumentContext,
  Pdf4D.Model.Page,
  Pdf4D.Model.Tests.Support,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Render.GraphicsEngine,
  Pdf4D.Tests.PdfBuilder;

type
  // Records what the operators report. The path is kept so that a clip can be made from it.
  TRecordingGraphicsEngine = class(TPdfGraphicsEngine)
  private
    FCalls: TList<string>;
    FClips: TList<IPdfClipPath>;
    FPath: TPdfPath;
    FLastState: TPdfRenderGraphicsState;

  public
    constructor Create;
    destructor Destroy; override;

    // The page runs on a copy of the state that is gone when the page is done, so the state after each operator is kept
    procedure ProcessOperator(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
    procedure AppendRectangle(const P0, P1, P2, P3: TPointF); override;
    procedure Clip(const FillRule: TPdfFillRule); override;
    procedure MoveTo(const X, Y: Single); override;
    procedure LineTo(const X, Y: Single); override;
    procedure CurveTo(const X1, Y1, X2, Y2, X3, Y3: Single); override;
    function TryGetCurrentPoint(out Point: TPointF): Boolean; override;
    procedure ClosePath; override;
    procedure EndPath; override;
    procedure StrokePath; override;
    procedure FillPath(const FillRule: TPdfFillRule); override;
    procedure FillAndStrokePath(const FillRule: TPdfFillRule); override;
    procedure ShadingFill(const ShadingName: string); override;
    procedure DrawImage(const Image: TPDImage); override;

    property Calls: TList<string> read FCalls;
    property Clips: TList<IPdfClipPath> read FClips;
    property LastState: TPdfRenderGraphicsState read FLastState;
  end;

  [TestFixture]
  TGraphicsEngineTests = class
  private
    const PageHeader = '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /ExtGState << %s >> /ColorSpace << /CSLab [/Lab << /WhitePoint [0.95 1 1.09] >>] >> >> >>';
    const FirstStateObject = 5;

  private
    FModels: TModelTestDocuments;
    FLines: TList<string>;
    FLog: TPdfLog;
    FContext: TPDDocumentContext;
    FPage: TPDPage;
    FEngine: TRecordingGraphicsEngine;

    procedure Run(const Content: string); overload;
    procedure Run(const Content: string; const ExtGStates: array of string); overload;
    function HasLogLine(const Fragment: string): Boolean;
    function CallsAsText: string;
    function State: TPdfRenderGraphicsState;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestRectangleAndFill;

    [Test]
    procedure TestPathOperatorsReportThePoints;

    [Test]
    procedure TestLineToWithoutMoveToStartsSubpath;

    [Test]
    procedure TestCloseAndStrokeClosesFirst;

    [Test]
    procedure TestPaintingOperatorsGiveTheirFillRule;

    [Test]
    procedure TestColorOperatorsSetSpaceAndComponents;

    [Test]
    procedure TestDeviceColorOperatorsSetTheSpace;

    [Test]
    procedure TestNonNumericColorOperandsGiveColorWithoutSpace;

    [Test]
    procedure TestPatternColorIsLoggedAndSkipped;

    [Test]
    procedure TestPatternNameIsTheColorInThePatternSpace;

    [Test]
    procedure TestUnsupportedColorSpaceFallsBackToGray;

    [Test]
    procedure TestLineStateOperators;

    [Test]
    procedure TestRenderingIntentAndFlatness;

    [Test]
    procedure TestUnknownRenderingIntentBecomesRelativeColorimetric;

    [Test]
    procedure TestExtGStateCopiesEverything;

    [Test]
    procedure TestExtGStateBlendModeArrayTakesFirstKnownName;

    [Test]
    procedure TestExtGStateLineStyleAndFlags;

    [Test]
    procedure TestExtGStateDefaultsForEntriesThatAreNoNumbers;

    [Test]
    procedure TestUnknownExtGStateIsLogged;

    [Test]
    procedure TestQRestoresClipAndColors;

    // The state keeps the 0; what the device makes of it is tested with the device
    [Test]
    procedure TestZeroLineWidthBecomesQuarterPoint;

    [Test]
    procedure TestAllZeroDashDrawsNothing;

    [Test]
    procedure TestDashArrayWithNonNumberIsEmpty;

    [Test]
    procedure TestNonFiniteCoordinatesAreSkipped;

    [Test]
    procedure TestMissingOperandsAreLoggedAndSkipped;

    [Test]
    procedure TestShadingFillReachesTheEngineWithTheName;
  end;

  [TestFixture]
  TRenderGraphicsStateTests = class
  public
    [Test]
    procedure TestInitialState;

    [Test]
    procedure TestCloneCopiesEveryField;

    [Test]
    procedure TestCloneIsIndependent;

    [Test]
    procedure TestIntersectClipChainsParents;

    [Test]
    procedure TestIntersectClipCopiesThePath;
  end;

  [TestFixture]
  TLineDashPatternTests = class
  public
    [Test]
    procedure TestEmptyPattern;

    [Test]
    procedure TestPositivePhaseIsKept;

    [TestCase('Small', '2,1,-1,5')]
    [TestCase('ExactlyOneCycle', '2,1,-6,6')]
    [TestCase('SeveralCycles', '2,1,-13,5')]
    procedure TestNegativePhaseIsMadePositive(const Dash, Gap, Phase, Expected: Integer);

    [Test]
    procedure TestNegativePhaseWithoutLengthIsZero;

    [Test]
    procedure TestNonNumberItemIsZero;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Float,
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Graphics.Color.Device,
  Pdf4D.Graphics.LineDash,
  Pdf4D.Cos.Name;

const
  FloatFormat = '%g,%g';

{ TRecordingGraphicsEngine }

constructor TRecordingGraphicsEngine.Create;
begin
  inherited Create;
  FCalls := TList<string>.Create;
  FClips := TList<IPdfClipPath>.Create;
  FPath := TPdfPath.Create;
end;

destructor TRecordingGraphicsEngine.Destroy;
begin
  FLastState.Free;
  FPath.Free;
  FClips.Free;
  FCalls.Free;
  inherited;
end;

procedure TRecordingGraphicsEngine.ProcessOperator(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  inherited ProcessOperator(Operator, Operands);
  FreeAndNil(FLastState);
  FLastState := (RenderState.Clone as TPdfRenderGraphicsState);
end;

procedure TRecordingGraphicsEngine.AppendRectangle(const P0, P1, P2, P3: TPointF);
begin
  FCalls.Add(Format('Rect %g,%g %g,%g %g,%g %g,%g', [P0.X, P0.Y, P1.X, P1.Y, P2.X, P2.Y, P3.X, P3.Y]));
  FPath.MoveTo(P0.X, P0.Y);
  FPath.LineTo(P1.X, P1.Y);
  FPath.LineTo(P2.X, P2.Y);
  FPath.LineTo(P3.X, P3.Y);
  FPath.ClosePath;
end;

procedure TRecordingGraphicsEngine.Clip(const FillRule: TPdfFillRule);
begin
  FCalls.Add(Format('Clip %d', [Ord(FillRule)]));
  RenderState.IntersectClip(FPath, TPdfMatrix.Identity, FillRule);
  FClips.Add(RenderState.Clip);
end;

procedure TRecordingGraphicsEngine.MoveTo(const X, Y: Single);
begin
  FCalls.Add(Format('Move ' + FloatFormat, [X, Y]));
  FPath.MoveTo(X, Y);
end;

procedure TRecordingGraphicsEngine.LineTo(const X, Y: Single);
begin
  FCalls.Add(Format('Line ' + FloatFormat, [X, Y]));
  FPath.LineTo(X, Y);
end;

procedure TRecordingGraphicsEngine.CurveTo(const X1, Y1, X2, Y2, X3, Y3: Single);
begin
  FCalls.Add(Format('Curve %g,%g %g,%g %g,%g', [X1, Y1, X2, Y2, X3, Y3]));
  FPath.CubicTo(X1, Y1, X2, Y2, X3, Y3);
end;

function TRecordingGraphicsEngine.TryGetCurrentPoint(out Point: TPointF): Boolean;
begin
  Result := FPath.HasCurrentPoint;
  if Result then
  begin
    Point := FPath.CurrentPoint;
  end
  else
  begin
    Point := TPointF.Zero;
  end;
end;

procedure TRecordingGraphicsEngine.ClosePath;
begin
  FCalls.Add('Close');
  FPath.ClosePath;
end;

procedure TRecordingGraphicsEngine.EndPath;
begin
  FCalls.Add('End');
  FPath.Clear;
end;

procedure TRecordingGraphicsEngine.StrokePath;
begin
  FCalls.Add('Stroke');
  FPath.Clear;
end;

procedure TRecordingGraphicsEngine.FillPath(const FillRule: TPdfFillRule);
begin
  FCalls.Add(Format('Fill %d', [Ord(FillRule)]));
  FPath.Clear;
end;

procedure TRecordingGraphicsEngine.FillAndStrokePath(const FillRule: TPdfFillRule);
begin
  FCalls.Add(Format('FillStroke %d', [Ord(FillRule)]));
  FPath.Clear;
end;

procedure TRecordingGraphicsEngine.ShadingFill(const ShadingName: string);
begin
  FCalls.Add('Shading ' + ShadingName);
end;

procedure TRecordingGraphicsEngine.DrawImage(const Image: TPDImage);
begin
  FCalls.Add(Format('Image %d x %d', [Image.Width, Image.Height]));
end;

{ TGraphicsEngineTests }

procedure TGraphicsEngineTests.Setup;
begin
  FModels := TModelTestDocuments.Create;
  FLines := TList<string>.Create;
  FLog := TPdfLog.Create(
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      FLines.Add(Message);
    end);
  FEngine := TRecordingGraphicsEngine.Create;
end;

procedure TGraphicsEngineTests.TearDown;
begin
  FreeAndNil(FEngine);
  FreeAndNil(FPage);
  FreeAndNil(FContext);
  FreeAndNil(FLog);
  FreeAndNil(FLines);
  FreeAndNil(FModels);
end;

procedure TGraphicsEngineTests.Run(const Content: string);
begin
  Run(Content, []);
end;

procedure TGraphicsEngineTests.Run(const Content: string; const ExtGStates: array of string);
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  try
    var References := '';
    for var Index := 0 to High(ExtGStates) do
    begin
      References := References + Format('/GS%d %d 0 R ', [Index + 1, FirstStateObject + Index]);
      Builder.AddObject(FirstStateObject + Index, ExtGStates[Index]);
    end;
    Builder.AddObject(3, Format(PageHeader, [References]));
    Builder.AddStreamObject(4, '', TEncoding.ASCII.GetBytes(Content));

    const Document = FModels.Open(Builder);
    FContext := TPDDocumentContext.Create(FLog, TPdfLoadOptions.Default);
    FPage := TPDPage.Create(Document.Pages.Get(0).CosObject, FContext);
    FEngine.ProcessPage(FPage);
  finally
    Builder.Free;
  end;
end;

function TGraphicsEngineTests.HasLogLine(const Fragment: string): Boolean;
begin
  Result := False;
  for var Line in FLines do
  begin
    Result := (Result or Line.Contains(Fragment));
  end;
end;

function TGraphicsEngineTests.CallsAsText: string;
begin
  Result := string.Join('|', FEngine.Calls.ToArray);
end;

function TGraphicsEngineTests.State: TPdfRenderGraphicsState;
begin
  Result := FEngine.LastState;
end;

procedure TGraphicsEngineTests.TestRectangleAndFill;
begin
  Run('2 0 0 2 5 5 cm 10 20 30 40 re f');

  Assert.AreEqual('Rect 25,45 85,45 85,125 25,125|Fill 0', CallsAsText);
end;

procedure TGraphicsEngineTests.TestPathOperatorsReportThePoints;
begin
  Run('1 0 0 1 10 0 cm 0 0 m 5 0 l 1 2 3 4 5 6 c 1 1 2 2 v 7 7 8 8 y n');

  Assert.AreEqual('Move 10,0|Line 15,0|Curve 11,2 13,4 15,6|Curve 15,6 11,1 12,2|Curve 17,7 18,8 18,8|End', CallsAsText);
end;

procedure TGraphicsEngineTests.TestLineToWithoutMoveToStartsSubpath;
begin
  Run('4 5 l 6 7 l');

  Assert.AreEqual('Move 4,5|Line 6,7', CallsAsText);
  Assert.IsTrue(HasLogLine('without initial MoveTo'), string.Join('|', FLines.ToArray));
end;

procedure TGraphicsEngineTests.TestCloseAndStrokeClosesFirst;
begin
  Run('0 0 m 5 5 l s h');

  Assert.AreEqual('Move 0,0|Line 5,5|Close|Stroke', CallsAsText);
  Assert.IsTrue(HasLogLine('ClosePath without initial MoveTo'));
end;

procedure TGraphicsEngineTests.TestPaintingOperatorsGiveTheirFillRule;
begin
  Run('0 0 m 1 1 l f F f* B B* b b* W W*');

  Assert.AreEqual('Move 0,0|Line 1,1|Fill 0|Fill 0|Fill 1|FillStroke 0|FillStroke 1|FillStroke 0|FillStroke 1|Clip 0|Clip 1', CallsAsText);
end;

procedure TGraphicsEngineTests.TestColorOperatorsSetSpaceAndComponents;
begin
  Run('/DeviceCMYK cs 0 0 0 1 sc 0.5 G');

  Assert.AreEqual('DeviceCMYK', State.NonStrokingColor.ColorSpace.Name);
  Assert.AreEqual<Integer>(4, Length(State.NonStrokingColor.Components));
  Assert.AreEqual<Single>(0, State.NonStrokingColor.Components[0]);
  Assert.AreEqual<Single>(1, State.NonStrokingColor.Components[3]);
  Assert.AreEqual('DeviceCMYK', State.NonStrokingColorSpace.Name);
  Assert.AreEqual('DeviceGray', State.StrokingColor.ColorSpace.Name);
  Assert.AreEqual<Single>(0.5, State.StrokingColor.Components[0]);
end;

procedure TGraphicsEngineTests.TestDeviceColorOperatorsSetTheSpace;
begin
  Run('0.1 0.2 0.3 rg 0.4 0.5 0.6 0.7 K');

  Assert.AreEqual('DeviceRGB', State.NonStrokingColor.ColorSpace.Name);
  Assert.AreEqual<Single>(0.3, State.NonStrokingColor.Components[2]);
  Assert.AreEqual('DeviceCMYK', State.StrokingColor.ColorSpace.Name);
  Assert.AreEqual<Single>(0.7, State.StrokingColor.Components[3]);
end;

procedure TGraphicsEngineTests.TestNonNumericColorOperandsGiveColorWithoutSpace;
begin
  Run('1 (x) 3 rg');

  Assert.IsNull(State.NonStrokingColor.ColorSpace);
  Assert.AreEqual<Integer>(0, Length(State.NonStrokingColor.Components));
  Assert.AreEqual('DeviceRGB', State.NonStrokingColorSpace.Name);
end;

procedure TGraphicsEngineTests.TestPatternColorIsLoggedAndSkipped;
begin
  Run('0.25 g /P1 scn');

  Assert.AreEqual<Single>(0.25, State.NonStrokingColor.Components[0]);
  Assert.IsTrue(HasLogLine('needs the Pattern colour space'));
end;

procedure TGraphicsEngineTests.TestPatternNameIsTheColorInThePatternSpace;
begin
  Run('/Pattern cs /P1 scn');

  Assert.AreEqual('Pattern', State.NonStrokingColor.ColorSpace.Name);
  Assert.AreEqual('P1', State.NonStrokingColor.PatternName);
  Assert.AreEqual('Pattern', State.NonStrokingColorSpace.Name);
end;

procedure TGraphicsEngineTests.TestUnsupportedColorSpaceFallsBackToGray;
begin
  Run('/CSLab cs');

  Assert.AreEqual('DeviceGray', State.NonStrokingColor.ColorSpace.Name);
  Assert.IsTrue(HasLogLine('not supported yet'));
end;

procedure TGraphicsEngineTests.TestLineStateOperators;
begin
  Run('3 w 1 J 2 j 4 M [2 1] 0 d');

  Assert.AreEqual<Single>(3, State.LineWidth);
  Assert.AreEqual<Integer>(1, State.LineCap);
  Assert.AreEqual<Integer>(2, State.LineJoin);
  Assert.AreEqual<Single>(4, State.MiterLimit);
  Assert.AreEqual<Integer>(2, Length(State.DashPattern.Dashes));
  Assert.AreEqual<Single>(2, State.DashPattern.Dashes[0]);
  Assert.AreEqual<Single>(1, State.DashPattern.Dashes[1]);
  Assert.AreEqual<Integer>(0, State.DashPattern.Phase);
end;

procedure TGraphicsEngineTests.TestRenderingIntentAndFlatness;
begin
  Run('/Saturation ri 2.5 i');

  Assert.AreEqual('Saturation', State.RenderingIntent);
  Assert.AreEqual<Single>(2.5, State.Flatness);
end;

procedure TGraphicsEngineTests.TestUnknownRenderingIntentBecomesRelativeColorimetric;
begin
  Run('/Foo ri');

  Assert.AreEqual('RelativeColorimetric', State.RenderingIntent);
end;

procedure TGraphicsEngineTests.TestExtGStateCopiesEverything;
begin
  Run('/GS1 gs', ['<< /LW 5 /CA 0.5 /ca 0.25 /BM /Multiply >>']);

  Assert.AreEqual<Single>(5, State.LineWidth);
  Assert.AreEqual<Single>(0.5, State.AlphaConstant);
  Assert.AreEqual<Single>(0.25, State.NonStrokeAlphaConstant);
  Assert.AreEqual<Integer>(Ord(TPdfBlendMode.Multiply), Ord(State.BlendMode));
end;

procedure TGraphicsEngineTests.TestExtGStateBlendModeArrayTakesFirstKnownName;
begin
  Run('/GS1 gs', ['<< /BM [/Foo /Screen /Multiply] >>']);

  Assert.AreEqual<Integer>(Ord(TPdfBlendMode.Screen), Ord(State.BlendMode));
end;

procedure TGraphicsEngineTests.TestExtGStateLineStyleAndFlags;
begin
  Run('/GS1 gs', ['<< /LC 2 /LJ 1 /ML 7 /D [[3 2] 1] /RI /Perceptual /SA true /AIS true /TK false /FL 4 /TR << >> >>']);

  Assert.AreEqual<Integer>(2, State.LineCap);
  Assert.AreEqual<Integer>(1, State.LineJoin);
  Assert.AreEqual<Single>(7, State.MiterLimit);
  Assert.AreEqual<Integer>(2, Length(State.DashPattern.Dashes));
  Assert.AreEqual<Integer>(1, State.DashPattern.Phase);
  Assert.AreEqual('Perceptual', State.RenderingIntent);
  Assert.IsTrue(State.StrokeAdjustment);
  Assert.IsTrue(State.AlphaSource);
  Assert.IsFalse(State.TextState.Knockout);
  Assert.AreEqual<Single>(4, State.Flatness);
  Assert.IsNotNull(State.Transfer);
end;

procedure TGraphicsEngineTests.TestExtGStateDefaultsForEntriesThatAreNoNumbers;
begin
  Run('7 w 3 M /GS1 gs', ['<< /LW /x /ML (y) /CA /z /D [1 2 3] >>']);

  Assert.AreEqual<Single>(1, State.LineWidth);
  Assert.AreEqual<Single>(10, State.MiterLimit);
  Assert.AreEqual<Single>(1, State.AlphaConstant);
  Assert.IsTrue(HasLogLine('/D entry'));
end;

procedure TGraphicsEngineTests.TestUnknownExtGStateIsLogged;
begin
  Run('/Missing gs 2 w');

  Assert.IsTrue(HasLogLine('not found in resources: /Missing'));
  Assert.AreEqual<Single>(2, State.LineWidth);
end;

procedure TGraphicsEngineTests.TestQRestoresClipAndColors;
begin
  Run('0 0 1 rg 0 0 5 5 re W n q 0 1 0 rg 0 0 10 10 re W n 1 0 0 RG Q');

  Assert.AreEqual<Integer>(2, FEngine.Clips.Count);
  Assert.IsTrue(FEngine.Clips[1].Parent = FEngine.Clips[0]);
  Assert.IsTrue(State.Clip = FEngine.Clips[0]);
  Assert.AreEqual('DeviceRGB', State.NonStrokingColor.ColorSpace.Name);
  Assert.AreEqual<Single>(1, State.NonStrokingColor.Components[2]);
  Assert.AreEqual<Single>(0, State.NonStrokingColor.Components[1]);
  Assert.AreEqual('DeviceGray', State.StrokingColor.ColorSpace.Name);
end;

procedure TGraphicsEngineTests.TestZeroLineWidthBecomesQuarterPoint;
begin
  Run('0 w');

  Assert.AreEqual<Single>(0, State.LineWidth);
end;

procedure TGraphicsEngineTests.TestAllZeroDashDrawsNothing;
begin
  Run('[0 0] 0 d');

  Assert.AreEqual<Integer>(2, Length(State.DashPattern.Dashes));
  Assert.AreEqual<Single>(0, State.DashPattern.Dashes[0]);
  Assert.AreEqual<Single>(0, State.DashPattern.Dashes[1]);
end;

procedure TGraphicsEngineTests.TestDashArrayWithNonNumberIsEmpty;
begin
  Run('[0 /x 3] 2 d');

  Assert.AreEqual<Integer>(0, Length(State.DashPattern.Dashes));
  Assert.AreEqual<Integer>(2, State.DashPattern.Phase);
  Assert.IsTrue(HasLogLine('dash array has a non number element'));
end;

procedure TGraphicsEngineTests.TestNonFiniteCoordinatesAreSkipped;
begin
  Run('100000000000000000000000000000000000000.0 0 0 100000000000000000000000000000000000000.0 0 0 cm 10 10 m 10 10 1 1 re 0 0 m');

  Assert.AreEqual('Move 0,0', CallsAsText);
  Assert.IsTrue(HasLogLine('finite'), string.Join('|', FLines.ToArray));
end;

procedure TGraphicsEngineTests.TestMissingOperandsAreLoggedAndSkipped;
begin
  Run('1 2 3 re 5 w 4 m');

  Assert.AreEqual('', CallsAsText);
  Assert.AreEqual<Single>(5, State.LineWidth);
  Assert.IsTrue(HasLogLine('too few operands'));
end;

procedure TGraphicsEngineTests.TestShadingFillReachesTheEngineWithTheName;
begin
  Run('/Sh1 sh');

  Assert.AreEqual('Shading Sh1', CallsAsText);
end;

{ TRenderGraphicsStateTests }

procedure TRenderGraphicsStateTests.TestInitialState;
begin
  const State = TPdfRenderGraphicsState.Create;
  try
    Assert.IsNull(State.Clip);
    Assert.AreEqual('DeviceGray', State.StrokingColor.ColorSpace.Name);
    Assert.AreEqual<Single>(0, State.NonStrokingColor.Components[0]);
    Assert.AreEqual<Single>(1, State.LineWidth);
    Assert.AreEqual<Integer>(0, State.LineCap);
    Assert.AreEqual<Integer>(0, State.LineJoin);
    Assert.AreEqual<Single>(10, State.MiterLimit);
    Assert.IsTrue(State.DashPattern.IsEmpty);
    Assert.AreEqual<Integer>(Ord(TPdfBlendMode.Normal), Ord(State.BlendMode));
    Assert.AreEqual<Single>(1, State.AlphaConstant);
    Assert.AreEqual<Single>(1, State.NonStrokeAlphaConstant);
    Assert.IsFalse(State.AlphaSource);
    Assert.IsFalse(State.StrokeAdjustment);
    Assert.AreEqual('', State.RenderingIntent);
    Assert.IsNull(State.Transfer);
  finally
    State.Free;
  end;
end;

procedure TRenderGraphicsStateTests.TestCloneCopiesEveryField;
begin
  const Original = TPdfRenderGraphicsState.Create;
  try
    const Path = TPdfPath.Create;
    try
      Path.MoveTo(0, 0);
      Original.IntersectClip(Path, TPdfMatrix.Identity, TPdfFillRule.EvenOdd);
    finally
      Path.Free;
    end;
    Original.NonStrokingColor := TPDDeviceRGB.Instance.InitialColor;
    Original.NonStrokingColorSpace := TPDDeviceRGB.Instance;
    Original.LineWidth := 3;
    Original.LineCap := 1;
    Original.LineJoin := 2;
    Original.MiterLimit := 4;
    Original.RenderingIntent := 'Saturation';
    Original.StrokeAdjustment := True;
    Original.Flatness := 5;
    Original.BlendMode := TPdfBlendMode.Screen;
    Original.AlphaConstant := 0.5;
    Original.NonStrokeAlphaConstant := 0.25;
    Original.AlphaSource := True;
    Original.TextState.FontSize := 12;

    const Copy = (Original.Clone as TPdfRenderGraphicsState);
    try
      Assert.IsTrue(Copy.Clip = Original.Clip);
      Assert.AreEqual('DeviceRGB', Copy.NonStrokingColor.ColorSpace.Name);
      Assert.AreEqual('DeviceRGB', Copy.NonStrokingColorSpace.Name);
      Assert.AreEqual<Single>(3, Copy.LineWidth);
      Assert.AreEqual<Integer>(1, Copy.LineCap);
      Assert.AreEqual<Integer>(2, Copy.LineJoin);
      Assert.AreEqual<Single>(4, Copy.MiterLimit);
      Assert.AreEqual('Saturation', Copy.RenderingIntent);
      Assert.IsTrue(Copy.StrokeAdjustment);
      Assert.AreEqual<Single>(5, Copy.Flatness);
      Assert.AreEqual<Integer>(Ord(TPdfBlendMode.Screen), Ord(Copy.BlendMode));
      Assert.AreEqual<Single>(0.5, Copy.AlphaConstant);
      Assert.AreEqual<Single>(0.25, Copy.NonStrokeAlphaConstant);
      Assert.IsTrue(Copy.AlphaSource);
      Assert.AreEqual<Single>(12, Copy.TextState.FontSize);
    finally
      Copy.Free;
    end;
  finally
    Original.Free;
  end;
end;

procedure TRenderGraphicsStateTests.TestCloneIsIndependent;
begin
  const Original = TPdfRenderGraphicsState.Create;
  try
    const Copy = (Original.Clone as TPdfRenderGraphicsState);
    try
      Copy.LineWidth := 9;
      Copy.StrokingColor := TPDDeviceRGB.Instance.InitialColor;

      Assert.AreEqual<Single>(1, Original.LineWidth);
      Assert.AreEqual('DeviceGray', Original.StrokingColor.ColorSpace.Name);
    finally
      Copy.Free;
    end;
  finally
    Original.Free;
  end;
end;

procedure TRenderGraphicsStateTests.TestIntersectClipChainsParents;
begin
  const State = TPdfRenderGraphicsState.Create;
  try
    const Path = TPdfPath.Create;
    try
      Path.MoveTo(0, 0);
      State.IntersectClip(Path, TPdfMatrix.Identity, TPdfFillRule.NonZero);
      const First = State.Clip;
      State.IntersectClip(Path, TPdfMatrix.GetScaleInstance(2, 2), TPdfFillRule.EvenOdd);

      Assert.IsNull(First.Parent);
      Assert.IsTrue(State.Clip.Parent = First);
      Assert.AreEqual<Integer>(Ord(TPdfFillRule.EvenOdd), Ord(State.Clip.FillRule));
      Assert.AreEqual<Single>(2, State.Clip.Transform.ScaleX);
    finally
      Path.Free;
    end;
  finally
    State.Free;
  end;
end;

procedure TRenderGraphicsStateTests.TestIntersectClipCopiesThePath;
begin
  const State = TPdfRenderGraphicsState.Create;
  try
    const Path = TPdfPath.Create;
    Path.MoveTo(1, 2);
    State.IntersectClip(Path, TPdfMatrix.Identity, TPdfFillRule.NonZero);
    Path.Free;

    Assert.AreEqual<Single>(1, State.Clip.Path.Point(0).X);
    Assert.AreEqual<Single>(2, State.Clip.Path.Point(0).Y);
  finally
    State.Free;
  end;
end;

{ TLineDashPatternTests }

procedure TLineDashPatternTests.TestEmptyPattern;
begin
  const Pattern = TPDLineDashPattern.Empty;

  Assert.IsTrue(Pattern.IsEmpty);
  Assert.AreEqual<Integer>(0, Pattern.Phase);
end;

procedure TLineDashPatternTests.TestPositivePhaseIsKept;
begin
  const Dashes = TCosArray.Create;
  try
    Dashes.Add(TCosInteger.Create(3));
    Dashes.Add(TCosFloat.Create(1.5));

    const Pattern = TPDLineDashPattern.Create(Dashes, 4);

    Assert.AreEqual<Integer>(2, Length(Pattern.Dashes));
    Assert.AreEqual<Single>(1.5, Pattern.Dashes[1]);
    Assert.AreEqual<Integer>(4, Pattern.Phase);
  finally
    Dashes.Free;
  end;
end;

procedure TLineDashPatternTests.TestNegativePhaseIsMadePositive(const Dash, Gap, Phase, Expected: Integer);
begin
  const Dashes = TCosArray.Create;
  try
    Dashes.Add(TCosInteger.Create(Dash));
    Dashes.Add(TCosInteger.Create(Gap));

    const Pattern = TPDLineDashPattern.Create(Dashes, Phase);

    Assert.AreEqual(Expected, Pattern.Phase);
  finally
    Dashes.Free;
  end;
end;

procedure TLineDashPatternTests.TestNegativePhaseWithoutLengthIsZero;
begin
  const Dashes = TCosArray.Create;
  try
    Dashes.Add(TCosInteger.Create(0));

    Assert.AreEqual<Integer>(0, TPDLineDashPattern.Create(Dashes, -3).Phase);
  finally
    Dashes.Free;
  end;
end;

procedure TLineDashPatternTests.TestNonNumberItemIsZero;
begin
  const Dashes = TCosArray.Create;
  try
    Dashes.Add(TCosName.Create('x'));
    Dashes.Add(TCosInteger.Create(2));

    const Pattern = TPDLineDashPattern.Create(Dashes, 0);

    Assert.AreEqual<Single>(0, Pattern.Dashes[0]);
    Assert.AreEqual<Single>(2, Pattern.Dashes[1]);
  finally
    Dashes.Free;
  end;
end;

end.
