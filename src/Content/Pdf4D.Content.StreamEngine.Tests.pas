// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Tests for Pdf4D.Content.StreamEngine and the operator processors
unit Pdf4D.Content.StreamEngine.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Common.Defines,
  Pdf4D.Common.Log,
  Pdf4D.Common.Matrix,
  Pdf4D.Content.Operator,
  Pdf4D.Content.StreamEngine,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Font.Base,
  Pdf4D.Model.DocumentContext,
  Pdf4D.Model.Page,
  Pdf4D.Model.Tests.Support,
  Pdf4D.Tests.PdfBuilder;

type
  TRecordedGlyph = record
    Code: Integer;
    X: Single;
    Y: Single;
    ScaleX: Single;
    DisplacementX: Single;
    StackSize: Integer;
    RenderingMode: Integer;
    Rise: Single;
    FontName: string;
    FontSize: Single;
  end;

  // Registers the operators and records every glyph
  TRecordingEngine = class(TPdfStreamEngine)
  private
    FGlyphs: TList<TRecordedGlyph>;
    FEvents: TList<string>;

  public
    constructor Create;
    destructor Destroy; override;

    procedure ShowGlyph(const TextRenderingMatrix: TPdfMatrix; const Font: TPDFont; const Code: Integer; const Displacement: TPdfVector); override;
    procedure BeginMarkedContentSequence(const Tag: string; const Properties: TCosDictionary); override;
    procedure EndMarkedContentSequence; override;

    property Glyphs: TList<TRecordedGlyph> read FGlyphs;
    // The glyphs (G and the code) and the marked content calls, in the order they happened
    property Events: TList<string> read FEvents;
  end;

  // An operator that fails the way a mistake in the library would
  TFailingProcessor = class(TOperatorProcessorBase)
  private
    FFailureClass: ExceptClass;

  public
    constructor Create(const FailureClass: ExceptClass);
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // Fails outside the processors of the operators, as only the engine itself is guarded against
  TUnsupportedFailureEngine = class(TRecordingEngine)
  protected
    procedure UnsupportedOperator(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  [TestFixture]
  TStreamEngineTests = class
  private
    const FormObject = 20;

  private
    FModels: TModelTestDocuments;
    FLines: TList<string>;
    FLog: TPdfLog;
    FContext: TPDDocumentContext;
    FPage: TPDPage;
    FEngine: TRecordingEngine;
    FContentsEntry: string;
    FExtraResources: string;

    function NewBuilder(const Content: string; const FormCount: Integer = 0): TTestPdfBuilder;
    procedure AddForm(const Builder: TTestPdfBuilder; const Index: Integer; const Dictionary, Content, Resources: string);
    procedure Run(const Builder: TTestPdfBuilder); overload;
    procedure Run(const Builder: TTestPdfBuilder; const Options: TPdfLoadOptions); overload;
    function HasLogLine(const Fragment: string): Boolean;
    function Glyph(const Index: Integer): TRecordedGlyph;
    procedure AssertNear(const Expected, Actual: Single);
    procedure RunContent(const Content: string);
    function FormResources(const NextIndex: Integer): string;
    procedure AddFlateForm(const Builder: TTestPdfBuilder; const Index: Integer; const Content, Resources: string; const PaddingSize: Integer);
    function FlateWhitespace(const Size: Integer): TBytes;
    procedure AddBombStream(const Builder: TTestPdfBuilder; const Number: Integer);
    function EventsText: string;
    function CountLogLines(const Fragment: string): Integer;
    procedure RunAccessViolationCase;
    procedure RunUnsupportedFailureCase;
    procedure RunFailureProcessor(const FailureClass: ExceptClass; const Content: string);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestShowTextPositions;

    [Test]
    procedure TestTJAdjustment;

    [Test]
    procedure TestWordSpacingOnlyForSingleByte32;

    [Test]
    procedure TestQRestoresState;

    [Test]
    procedure TestUnbalancedQIsLogged;

    [Test]
    procedure TestMissingOperandIsLogged;

    [Test]
    procedure TestFormXObjectDrawn;

    [Test]
    procedure TestSelfReferencingFormTerminates;

    [Test]
    procedure TestFormFanOutHitsOperatorBudget;

    [Test]
    procedure TestGlyphBudgetEndsPage;

    [Test]
    procedure TestGraphicsStackDepthIsBounded;

    [Test]
    procedure TestNoFontUsesDefault;

    [Test]
    procedure TestMissingFontIsLoggedAndPageGoesOn;

    [Test]
    procedure TestNextLineUsesLeading;

    [Test]
    procedure TestFormDepthIsLimited;

    [Test]
    procedure TestMarkedContentSequences;

    [Test]
    procedure TestMarkedContentPropertiesFromResources;

    [Test]
    procedure TestMarkedContentWithoutOperandsIsLogged;

    [Test]
    procedure TestCharacterSpacing;

    [Test]
    procedure TestTextRise;

    [Test]
    procedure TestRenderingModeDoesNotHideGlyphs;

    [Test]
    procedure TestTDSetsLeading;

    [Test]
    procedure TestDoubleQuoteSetsSpacingAndMovesToNextLine;

    [Test]
    procedure TestHorizontalScalingInsideTJ;

    [Test]
    procedure TestVerticalFontShowText;

    [Test]
    procedure TestVerticalFontTJAdjustment;

    [Test]
    procedure TestVerticalFontTJWithHorizontalScaling;

    [Test]
    procedure TestExtGStateFontSetsFontAndSize;

    [Test]
    procedure TestImageXObjectIsSkipped;

    [Test]
    procedure TestMissingXObjectIsLogged;

    [Test]
    procedure TestGraphicsStateIsSeparateInsideAForm;

    [Test]
    procedure TestRestoreInsideAFormDoesNotPopThePageStack;

    [Test]
    procedure TestOperatorFailureOtherThanPdfExceptionIsLogged;

    [Test]
    procedure TestAccessViolationInAnOperatorIsRaised;

    [Test]
    procedure TestNonPdfExceptionAtThePageBoundaryBecomesParseException;

    [Test]
    procedure TestFloatMaskIsRestoredAfterException;

    [Test]
    procedure TestPageContentBytesBudgetKeepsTheTextSoFar;

    [Test]
    procedure TestFormBombDrawnManyTimesIsBounded;

    [Test]
    procedure TestFormBombFanOutIsBounded;

    [Test]
    procedure TestManySmallContentStreamsAreJoinedInLinearTime;

    [Test]
    procedure TestOperandsBeforeAnOperatorAreBounded;

    [Test]
    procedure TestHugeTJArrayIsBounded;
  end;

implementation

uses
  System.Diagnostics,
  Pdf4D.Common.FloatGuard,
  Pdf4D.Content.GraphicsState,
  Pdf4D.Content.Operators.DrawObject,
  Pdf4D.Content.Operators.MarkedContent,
  Pdf4D.Content.Operators.State,
  Pdf4D.Content.Operators.Text,
  Pdf4D.Cos.Names,
  System.Classes,
  System.Math,
  System.ZLib;

const
  PageHeader = '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents %s /Resources << /Font << /F1 10 0 R /F2 11 0 R /F3 13 0 R /F4 14 0 R >> %s >> >>';
  HelveticaBody = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>';
  Type0Body = '<< /Type /Font /Subtype /Type0 /BaseFont /Test /Encoding /Identity-H /DescendantFonts [12 0 R] >>';
  DescendantBody = '<< /Type /Font /Subtype /CIDFontType2 /BaseFont /Test /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /DW 500 >>';
  Tolerance = 0.001;
  // Fonts of the tests: 10 Helvetica, 11 Type 0 horizontal, 12 its descendant, 13 Type 0 vertical, 14 Times
  VerticalBody = '<< /Type /Font /Subtype /Type0 /BaseFont /Test /Encoding /Identity-V /DescendantFonts [12 0 R] >>';
  TimesBody = '<< /Type /Font /Subtype /Type1 /BaseFont /Times-Roman >>';
  BombSize = 600 * 1024;

{ TFailingProcessor }

constructor TFailingProcessor.Create(const FailureClass: ExceptClass);
begin
  inherited Create;
  FFailureClass := FailureClass;
end;

function TFailingProcessor.Name: string;
begin
  Result := 'XX';
end;

procedure TFailingProcessor.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  raise FFailureClass.Create('Test failure');
end;

{ TUnsupportedFailureEngine }

procedure TUnsupportedFailureEngine.UnsupportedOperator(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  if Operator.Name = 'XX' then
  begin
    raise EListError.Create('Test failure');
  end;
end;

{ TRecordingEngine }

constructor TRecordingEngine.Create;
begin
  inherited Create;
  FGlyphs := TList<TRecordedGlyph>.Create;
  FEvents := TList<string>.Create;
  TMarkedContentOperators.Register(Self);
  TTextOperators.Register(Self);
  TStateOperators.Register(Self);
  TDrawObjectOperators.Register(Self);
end;

destructor TRecordingEngine.Destroy;
begin
  FEvents.Free;
  FGlyphs.Free;
  inherited;
end;

procedure TRecordingEngine.ShowGlyph(const TextRenderingMatrix: TPdfMatrix; const Font: TPDFont; const Code: Integer; const Displacement: TPdfVector);
begin
  var Item: TRecordedGlyph;
  Item.Code := Code;
  Item.X := TextRenderingMatrix.TranslateX;
  Item.Y := TextRenderingMatrix.TranslateY;
  Item.ScaleX := TextRenderingMatrix.ScaleX;
  Item.DisplacementX := Displacement.X;
  Item.StackSize := GraphicsStackSize;
  Item.RenderingMode := GraphicsState.TextState.RenderingMode.IntValue;
  Item.Rise := GraphicsState.TextState.Rise;
  Item.FontName := Font.Name;
  Item.FontSize := GraphicsState.TextState.FontSize;
  FGlyphs.Add(Item);
  FEvents.Add(Format('G%d', [Code]));
end;

procedure TRecordingEngine.BeginMarkedContentSequence(const Tag: string; const Properties: TCosDictionary);
begin
  if Assigned(Properties) then
  begin
    FEvents.Add(Format('BDC %s mcid=%d text=%s', [Tag, Properties.GetInt(TCosNames.MCID, -1), Properties.GetString(TCosNames.ActualText, '')]));
  end
  else
  begin
    FEvents.Add('BMC ' + Tag);
  end;
end;

procedure TRecordingEngine.EndMarkedContentSequence;
begin
  FEvents.Add('EMC');
end;

{ TStreamEngineTests }

procedure TStreamEngineTests.Setup;
begin
  FModels := TModelTestDocuments.Create;
  FLines := TList<string>.Create;
  FLog := TPdfLog.Create(
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      FLines.Add(Message);
    end);
  FEngine := TRecordingEngine.Create;
  FContentsEntry := '4 0 R';
  FExtraResources := '';
end;

procedure TStreamEngineTests.TearDown;
begin
  FreeAndNil(FEngine);
  FreeAndNil(FPage);
  FreeAndNil(FContext);
  FreeAndNil(FLog);
  FreeAndNil(FLines);
  FreeAndNil(FModels);
end;

function TStreamEngineTests.FormResources(const NextIndex: Integer): string;
begin
  Result := Format('<< /Font << /F1 10 0 R >> /XObject << /Fm1 %d 0 R >> >>', [FormObject + NextIndex]);
end;

function TStreamEngineTests.NewBuilder(const Content: string; const FormCount: Integer): TTestPdfBuilder;
begin
  Result := TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  try
    const XObjects = TStringBuilder.Create;
    try
      for var Index := 0 to FormCount - 1 do
      begin
        XObjects.AppendFormat('/Fm%d %d 0 R ', [Index, FormObject + Index]);
      end;
      Result.AddObject(3, Format(PageHeader, [FContentsEntry, '/XObject << ' + XObjects.ToString + '>> ' + FExtraResources]));
    finally
      XObjects.Free;
    end;
    Result.AddStreamObject(4, '', TEncoding.ASCII.GetBytes(Content));
    Result.AddObject(10, HelveticaBody);
    Result.AddObject(11, Type0Body);
    Result.AddObject(12, DescendantBody);
    Result.AddObject(13, VerticalBody);
    Result.AddObject(14, TimesBody);
  except
    Result.Free;
    raise;
  end;
end;

procedure TStreamEngineTests.AddForm(const Builder: TTestPdfBuilder; const Index: Integer; const Dictionary, Content, Resources: string);
begin
  var Entries := '/Type /XObject /Subtype /Form /BBox [0 0 612 792] ' + Dictionary;
  if Resources <> '' then
  begin
    Entries := Entries + ' /Resources ' + Resources;
  end;
  Builder.AddStreamObject(FormObject + Index, Entries, TEncoding.ASCII.GetBytes(Content));
end;

procedure TStreamEngineTests.Run(const Builder: TTestPdfBuilder);
begin
  Run(Builder, TPdfLoadOptions.Default);
end;

procedure TStreamEngineTests.Run(const Builder: TTestPdfBuilder; const Options: TPdfLoadOptions);
begin
  try
    const Document = FModels.Open(Builder);
    FContext := TPDDocumentContext.Create(FLog, Options);
    FPage := TPDPage.Create(Document.Pages.Get(0).CosObject, FContext);
    FEngine.ProcessPage(FPage);
  finally
    Builder.Free;
  end;
end;

procedure TStreamEngineTests.RunContent(const Content: string);
begin
  Run(NewBuilder(Content));
end;

function TStreamEngineTests.HasLogLine(const Fragment: string): Boolean;
begin
  Result := False;
  for var Line in FLines do
  begin
    Result := (Result or Line.Contains(Fragment));
  end;
end;

procedure TStreamEngineTests.AssertNear(const Expected, Actual: Single);
begin
  Assert.IsTrue(Abs(Expected - Actual) < Tolerance, Format('Expected %g but was %g', [Expected, Actual]));
end;

function TStreamEngineTests.Glyph(const Index: Integer): TRecordedGlyph;
begin
  Result := FEngine.Glyphs[Index];
end;

procedure TStreamEngineTests.TestShowTextPositions;
begin
  RunContent('BT /F1 12 Tf 100 700 Td (AB) Tj ET');

  Assert.AreEqual<Integer>(2, FEngine.Glyphs.Count);
  Assert.AreEqual<Integer>(65, Glyph(0).Code);
  Assert.AreEqual<Integer>(66, Glyph(1).Code);
  AssertNear(100, Glyph(0).X);
  AssertNear(108.004, Glyph(1).X);
  AssertNear(700, Glyph(1).Y);
end;

procedure TStreamEngineTests.TestTJAdjustment;
begin
  RunContent('BT /F1 12 Tf 100 700 Td [(A) -1000 (B)] TJ ET');

  Assert.AreEqual<Integer>(2, FEngine.Glyphs.Count);
  AssertNear(120.004, Glyph(1).X);
end;

procedure TStreamEngineTests.TestWordSpacingOnlyForSingleByte32;
begin
  RunContent('BT /F1 12 Tf 100 700 Td 10 Tw (A B) Tj ET');
  Assert.AreEqual<Integer>(3, FEngine.Glyphs.Count);
  const WithSpacing = Glyph(2).X;
  FEngine.Glyphs.Clear;

  FreeAndNil(FPage);
  FreeAndNil(FContext);
  RunContent('BT /F1 12 Tf 100 700 Td (A B) Tj ET');
  AssertNear(10, WithSpacing - Glyph(2).X);
  FEngine.Glyphs.Clear;

  // A two-byte code 0020 in a Type 0 font is no word space
  FreeAndNil(FPage);
  FreeAndNil(FContext);
  RunContent('BT /F2 12 Tf 100 700 Td 10 Tw <00200020> Tj ET');
  Assert.AreEqual<Integer>(2, FEngine.Glyphs.Count);
  AssertNear(100 + 500 * 12 / 1000, Glyph(1).X);
end;

procedure TStreamEngineTests.TestQRestoresState;
begin
  RunContent('q 2 0 0 2 0 0 cm BT /F1 12 Tf (A) Tj ET Q BT /F1 12 Tf (A) Tj ET');

  Assert.AreEqual<Integer>(2, FEngine.Glyphs.Count);
  AssertNear(24, Glyph(0).ScaleX);
  AssertNear(12, Glyph(1).ScaleX);
end;

procedure TStreamEngineTests.TestUnbalancedQIsLogged;
begin
  RunContent('Q Q BT /F1 12 Tf (A) Tj ET');

  Assert.AreEqual<Integer>(1, FEngine.Glyphs.Count);
  Assert.IsTrue(HasLogLine('graphics stack is empty'));
end;

procedure TStreamEngineTests.TestMissingOperandIsLogged;
begin
  RunContent('BT /F1 12 Tf Tj ET');
  Assert.AreEqual<Integer>(0, FEngine.Glyphs.Count);
  Assert.IsTrue(FLines.Count > 0);

  FLines.Clear;
  FreeAndNil(FPage);
  FreeAndNil(FContext);
  RunContent('BT /F1 Tf (A) Tj ET');
  Assert.IsTrue(HasLogLine('too few operands'));
end;

procedure TStreamEngineTests.TestFormXObjectDrawn;
begin
  const Builder = NewBuilder('/Fm0 Do', 1);
  AddForm(Builder, 0, '/Matrix [1 0 0 1 50 0]', 'BT /F1 12 Tf (A) Tj ET', '');
  Run(Builder);

  Assert.AreEqual<Integer>(1, FEngine.Glyphs.Count);
  AssertNear(50, Glyph(0).X);
end;

procedure TStreamEngineTests.TestSelfReferencingFormTerminates;
begin
  const Builder = NewBuilder('/Fm0 Do', 1);
  AddForm(Builder, 0, '', 'BT /F1 12 Tf (A) Tj ET /Fm1 Do', '<< /Font << /F1 10 0 R >> /XObject << /Fm1 20 0 R >> >>');
  const Watch = TStopwatch.StartNew;
  Run(Builder);

  Assert.IsTrue(Watch.ElapsedMilliseconds < 2000);
  Assert.AreEqual<Integer>(1, FEngine.Glyphs.Count);
  Assert.IsTrue(HasLogLine('recursion'));
end;

procedure TStreamEngineTests.TestFormFanOutHitsOperatorBudget;
begin
  const FormCount = 20;
  const Builder = NewBuilder('/Fm0 Do', FormCount);
  for var Index := 0 to FormCount - 1 do
  begin
    if Index < FormCount - 1 then
    begin
      AddForm(Builder, Index, '', 'BT /F1 12 Tf (A) Tj ET /Fm1 Do /Fm1 Do', FormResources(Index + 1));
    end
    else
    begin
      AddForm(Builder, Index, '', 'BT /F1 12 Tf (A) Tj ET', FormResources(Index));
    end;
  end;

  var Options := TPdfLoadOptions.Default;
  Options.MaxOperatorsPerPage := 100000;
  const Watch = TStopwatch.StartNew;
  Run(Builder, Options);

  Assert.IsTrue(Watch.ElapsedMilliseconds < 5000, Format('Took %d ms', [Watch.ElapsedMilliseconds]));
  Assert.IsTrue(HasLogLine('operators'));
  Assert.IsTrue(FEngine.Glyphs.Count > 0);
end;

procedure TStreamEngineTests.TestGlyphBudgetEndsPage;
begin
  var Options := TPdfLoadOptions.Default;
  Options.MaxGlyphsPerPage := 1000;
  Run(NewBuilder('BT /F1 12 Tf (' + StringOfChar('A', 5000) + ') Tj ET'), Options);

  Assert.AreEqual<Integer>(1000, FEngine.Glyphs.Count);
  Assert.IsTrue(HasLogLine('glyphs'));
end;

procedure TStreamEngineTests.TestGraphicsStackDepthIsBounded;
begin
  const Watch = TStopwatch.StartNew;
  const Content = TStringBuilder.Create;
  try
    for var Index := 1 to 100000 do
    begin
      Content.Append('q ');
    end;
    Content.Append('BT /F1 12 Tf (A) Tj ET');
    RunContent(Content.ToString);
  finally
    Content.Free;
  end;

  Assert.IsTrue(Watch.ElapsedMilliseconds < 2000, Format('Took %d ms', [Watch.ElapsedMilliseconds]));
  Assert.AreEqual<Integer>(1, FEngine.Glyphs.Count);
  Assert.IsTrue(Glyph(0).StackSize <= 4096);
  Assert.IsTrue(HasLogLine('ignored'));
end;

procedure TStreamEngineTests.TestNoFontUsesDefault;
begin
  RunContent('BT 12 0 0 12 0 0 Tm (A) Tj ET');

  Assert.AreEqual<Integer>(1, FEngine.Glyphs.Count);
  AssertNear(0.667, Glyph(0).DisplacementX);
  Assert.IsTrue(HasLogLine('No current font'));
end;

procedure TStreamEngineTests.TestMissingFontIsLoggedAndPageGoesOn;
begin
  RunContent('BT /Nope 12 Tf (A) Tj ET BT /F1 12 Tf (B) Tj ET');

  Assert.AreEqual<Integer>(2, FEngine.Glyphs.Count);
  Assert.IsTrue(HasLogLine('not found in resources'));
end;

procedure TStreamEngineTests.TestNextLineUsesLeading;
begin
  RunContent('BT /F1 12 Tf 14 TL 100 700 Td (A) Tj T* (B) Tj (C) '' ET');

  Assert.AreEqual<Integer>(3, FEngine.Glyphs.Count);
  AssertNear(686, Glyph(1).Y);
  AssertNear(672, Glyph(2).Y);
end;

procedure TStreamEngineTests.TestFormDepthIsLimited;
begin
  const FormCount = 60;
  const Builder = NewBuilder('/Fm0 Do', FormCount);
  for var Index := 0 to FormCount - 1 do
  begin
    if Index < FormCount - 1 then
    begin
      AddForm(Builder, Index, '', 'BT /F1 12 Tf (A) Tj ET /Fm1 Do', FormResources(Index + 1));
    end
    else
    begin
      AddForm(Builder, Index, '', 'BT /F1 12 Tf (A) Tj ET', FormResources(Index));
    end;
  end;
  Run(Builder);

  Assert.AreEqual<Integer>(50, FEngine.Glyphs.Count);
  Assert.IsTrue(HasLogLine('recursion is too deep'));
end;

function TStreamEngineTests.EventsText: string;
begin
  Result := string.Join('|', FEngine.Events.ToArray);
end;

function TStreamEngineTests.CountLogLines(const Fragment: string): Integer;
begin
  Result := 0;
  for var Line in FLines do
  begin
    if Line.Contains(Fragment) then
    begin
      Inc(Result);
    end;
  end;
end;

procedure TStreamEngineTests.RunAccessViolationCase;
begin
  RunFailureProcessor(EAccessViolation, 'BT /F1 12 Tf XX (A) Tj ET');
end;

procedure TStreamEngineTests.RunUnsupportedFailureCase;
begin
  RunContent('BT /F1 12 Tf XX (A) Tj ET');
end;

procedure TStreamEngineTests.RunFailureProcessor(const FailureClass: ExceptClass; const Content: string);
begin
  FEngine.AddOperator(TFailingProcessor.Create(FailureClass));
  RunContent(Content);
end;

function TStreamEngineTests.FlateWhitespace(const Size: Integer): TBytes;
begin
  var Spaces: TBytes;
  SetLength(Spaces, Size);
  FillChar(Spaces[0], Size, Ord(' '));
  ZCompress(Spaces, Result);
end;

procedure TStreamEngineTests.AddFlateForm(const Builder: TTestPdfBuilder; const Index: Integer; const Content, Resources: string; const PaddingSize: Integer);
begin
  const Data = TEncoding.ASCII.GetBytes(Content + StringOfChar(' ', PaddingSize));
  var Compressed: TBytes;
  ZCompress(Data, Compressed);
  Builder.AddStreamObject(FormObject + Index, '/Type /XObject /Subtype /Form /BBox [0 0 612 792] /Filter /FlateDecode /Resources ' + Resources, Compressed);
end;

procedure TStreamEngineTests.AddBombStream(const Builder: TTestPdfBuilder; const Number: Integer);
begin
  Builder.AddStreamObject(Number, '/Filter /FlateDecode', FlateWhitespace(BombSize));
end;

procedure TStreamEngineTests.TestMarkedContentSequences;
begin
  RunContent('/P BMC /Span << /MCID 1 /ActualText (X) >> BDC BT /F1 12 Tf (A) Tj ET EMC EMC');

  Assert.AreEqual('BMC P|BDC Span mcid=1 text=X|G65|EMC|EMC', EventsText);
end;

procedure TStreamEngineTests.TestMarkedContentPropertiesFromResources;
begin
  FExtraResources := '/Properties << /MC0 << /MCID 7 >> >>';
  RunContent('/Span /MC0 BDC BT /F1 12 Tf (A) Tj ET EMC /Span /Missing BDC EMC');

  // A properties name that is not in the resources gives no sequence at all, as in PDFBox
  Assert.AreEqual('BDC Span mcid=7 text=|G65|EMC|EMC', EventsText);
end;

procedure TStreamEngineTests.TestMarkedContentWithoutOperandsIsLogged;
begin
  RunContent('/Span BDC BMC EMC');

  Assert.AreEqual('BMC |EMC', EventsText);
  Assert.IsTrue(HasLogLine('too few operands'));
end;

procedure TStreamEngineTests.TestCharacterSpacing;
begin
  // Confirmed with PDFBox 3.0.8: the second glyph is at x 110.004
  RunContent('BT /F1 12 Tf 2 Tc 100 700 Td (AB) Tj ET');

  Assert.AreEqual<Integer>(2, FEngine.Glyphs.Count);
  AssertNear(100, Glyph(0).X);
  AssertNear(110.004, Glyph(1).X);
end;

procedure TStreamEngineTests.TestTextRise;
begin
  // Confirmed with PDFBox 3.0.8: y is 705
  RunContent('BT /F1 12 Tf 5 Ts 100 700 Td (A) Tj ET');

  AssertNear(705, Glyph(0).Y);
  AssertNear(5, Glyph(0).Rise);
end;

procedure TStreamEngineTests.TestRenderingModeDoesNotHideGlyphs;
begin
  // Invisible text (mode 3) is still text. A mode outside 0..7 is ignored; PDFBox fails with a RuntimeException there.
  RunContent('BT /F1 12 Tf 100 700 Td 3 Tr (A) Tj 9 Tr (B) Tj ET');

  Assert.AreEqual<Integer>(2, FEngine.Glyphs.Count);
  Assert.AreEqual<Integer>(3, Glyph(0).RenderingMode);
  AssertNear(100, Glyph(0).X);
  Assert.AreEqual<Integer>(3, Glyph(1).RenderingMode);
end;

procedure TStreamEngineTests.TestTDSetsLeading;
begin
  // Confirmed with PDFBox 3.0.8: B at y 680, C at y 660 (TD sets the leading to 20, T* uses it)
  RunContent('BT /F1 12 Tf 5 TL 100 700 Td (A) Tj 0 -20 TD (B) Tj T* (C) Tj ET');

  Assert.AreEqual<Integer>(3, FEngine.Glyphs.Count);
  AssertNear(700, Glyph(0).Y);
  AssertNear(680, Glyph(1).Y);
  AssertNear(660, Glyph(2).Y);
end;

procedure TStreamEngineTests.TestDoubleQuoteSetsSpacingAndMovesToNextLine;
begin
  // Confirmed with PDFBox 3.0.8: y 686, the space at x 110.004 and B at x 118.34
  RunContent('BT /F1 12 Tf 14 TL 100 700 Td 3 2 (A B) " ET');

  Assert.AreEqual<Integer>(3, FEngine.Glyphs.Count);
  AssertNear(686, Glyph(0).Y);
  AssertNear(110.004, Glyph(1).X);
  AssertNear(118.34, Glyph(2).X);
end;

procedure TStreamEngineTests.TestHorizontalScalingInsideTJ;
begin
  // Confirmed with PDFBox 3.0.8: the adjustment and the width are both scaled to 50 percent, B at x 110.002
  RunContent('BT /F1 12 Tf 50 Tz 100 700 Td [(A) -1000 (B)] TJ ET');

  Assert.AreEqual<Integer>(2, FEngine.Glyphs.Count);
  AssertNear(110.002, Glyph(1).X);
end;

procedure TStreamEngineTests.TestVerticalFontShowText;
begin
  // Confirmed with PDFBox 3.0.8 (Identity-V, default DW2): the origin moves by the position vector (-3, -10.56) and every
  // glyph goes down by 12
  RunContent('BT /F3 12 Tf 100 700 Td <00410042> Tj ET');

  Assert.AreEqual<Integer>(2, FEngine.Glyphs.Count);
  AssertNear(97, Glyph(0).X);
  AssertNear(689.44, Glyph(0).Y);
  AssertNear(97, Glyph(1).X);
  AssertNear(677.44, Glyph(1).Y);
end;

procedure TStreamEngineTests.TestVerticalFontTJAdjustment;
begin
  // Confirmed with PDFBox 3.0.8: the adjustment moves along y, by 500 / 1000 * 12 = 6 upwards
  RunContent('BT /F3 12 Tf 100 700 Td [<0041> -500 <0042>] TJ ET');

  Assert.AreEqual<Integer>(2, FEngine.Glyphs.Count);
  AssertNear(689.44, Glyph(0).Y);
  AssertNear(683.44, Glyph(1).Y);
end;

procedure TStreamEngineTests.TestVerticalFontTJWithHorizontalScaling;
begin
  // Confirmed with PDFBox 3.0.8: the scaling applies to the position vector (x 98.5), not to the vertical adjustment (-6)
  RunContent('BT /F3 12 Tf 50 Tz 100 700 Td [<0041> 500 <0042>] TJ ET');

  Assert.AreEqual<Integer>(2, FEngine.Glyphs.Count);
  AssertNear(98.5, Glyph(0).X);
  AssertNear(98.5, Glyph(1).X);
  AssertNear(689.44, Glyph(0).Y);
  AssertNear(671.44, Glyph(1).Y);
end;

procedure TStreamEngineTests.TestExtGStateFontSetsFontAndSize;
begin
  FExtraResources := '/ExtGState << /GS1 << /Type /ExtGState /Font [14 0 R 20] >> >>';
  RunContent('BT /F1 12 Tf /GS1 gs 100 700 Td (A) Tj ET');

  Assert.AreEqual<Integer>(1, FEngine.Glyphs.Count);
  Assert.AreEqual('Times-Roman', Glyph(0).FontName);
  AssertNear(20, Glyph(0).FontSize);
end;

procedure TStreamEngineTests.TestImageXObjectIsSkipped;
begin
  const Builder = NewBuilder('/Fm0 Do BT /F1 12 Tf (A) Tj ET', 1);
  Builder.AddStreamObject(FormObject, '/Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace /DeviceGray /BitsPerComponent 8', [0]);
  Run(Builder);

  Assert.AreEqual<Integer>(1, FEngine.Glyphs.Count);
  Assert.IsFalse(HasLogLine('XObject'), 'An image is skipped without a message');
end;

procedure TStreamEngineTests.TestMissingXObjectIsLogged;
begin
  RunContent('/Nope Do BT /F1 12 Tf (A) Tj ET');

  Assert.AreEqual<Integer>(1, FEngine.Glyphs.Count);
  Assert.IsTrue(HasLogLine('Missing XObject: Nope'));
end;

procedure TStreamEngineTests.TestGraphicsStateIsSeparateInsideAForm;
begin
  const Builder = NewBuilder('BT /F1 12 Tf ET q 2 0 0 2 0 0 cm /Fm0 Do BT (A) Tj ET Q', 1);
  // The form has no q to match and sets its own CTM and font: none of it may reach the page
  AddForm(Builder, 0, '', 'q 3 0 0 3 0 0 cm BT /F4 20 Tf (B) Tj ET', '');
  Run(Builder);

  Assert.AreEqual<Integer>(2, FEngine.Glyphs.Count);
  Assert.AreEqual('Times-Roman', Glyph(0).FontName);
  AssertNear(120, Glyph(0).ScaleX);
  Assert.AreEqual('Helvetica', Glyph(1).FontName);
  AssertNear(12, Glyph(1).FontSize);
  AssertNear(24, Glyph(1).ScaleX);
end;

procedure TStreamEngineTests.TestRestoreInsideAFormDoesNotPopThePageStack;
begin
  const Builder = NewBuilder('q 2 0 0 2 0 0 cm /Fm0 Do Q BT /F1 12 Tf (A) Tj ET', 1);
  AddForm(Builder, 0, '', 'Q BT /F1 10 Tf (B) Tj ET', '');
  Run(Builder);

  Assert.AreEqual<Integer>(2, FEngine.Glyphs.Count);
  AssertNear(20, Glyph(0).ScaleX);
  // The Q of the page did its work: the state of the page is back at the CTM without the scale
  AssertNear(12, Glyph(1).ScaleX);
  Assert.AreEqual<Integer>(1, CountLogLines('graphics stack is empty'));
end;

procedure TStreamEngineTests.TestOperatorFailureOtherThanPdfExceptionIsLogged;
begin
  RunFailureProcessor(EListError, 'BT /F1 12 Tf XX (A) Tj ET');

  Assert.AreEqual<Integer>(1, FEngine.Glyphs.Count);
  Assert.IsTrue(HasLogLine('EListError'));
end;

procedure TStreamEngineTests.TestAccessViolationInAnOperatorIsRaised;
begin
  Assert.WillRaise(RunAccessViolationCase, EAccessViolation);
end;

procedure TStreamEngineTests.TestNonPdfExceptionAtThePageBoundaryBecomesParseException;
begin
  FreeAndNil(FEngine);
  FEngine := TUnsupportedFailureEngine.Create;

  Assert.WillRaise(RunUnsupportedFailureCase, EPdfParseException);
end;

procedure TStreamEngineTests.TestFloatMaskIsRestoredAfterException;
begin
  FreeAndNil(FEngine);
  FEngine := TUnsupportedFailureEngine.Create;
  const Before = GetExceptionMask;

  try
    RunContent('BT /F1 12 Tf XX (A) Tj ET');
  except
    on EPdfParseException do
    begin
    end;
  end;

  Assert.IsTrue(Before = GetExceptionMask);
end;

procedure TStreamEngineTests.TestPageContentBytesBudgetKeepsTheTextSoFar;
begin
  const Refs = TStringBuilder.Create;
  try
    Refs.Append('[4 0 R');
    for var Index := 1 to 1000 do
    begin
      Refs.Append(' 5 0 R');
    end;
    Refs.Append(']');
    FContentsEntry := Refs.ToString;
  finally
    Refs.Free;
  end;

  const Builder = NewBuilder('BT /F1 12 Tf (A) Tj ET');
  AddBombStream(Builder, 5);
  var Options := TPdfLoadOptions.Default;
  Options.MaxContentBytesPerPage := 1024 * 1024;
  const Watch = TStopwatch.StartNew;
  Run(Builder, Options);

  Assert.IsTrue(Watch.ElapsedMilliseconds < 5000, Format('Took %d ms', [Watch.ElapsedMilliseconds]));
  Assert.AreEqual<Integer>(1, FEngine.Glyphs.Count);
  Assert.IsTrue(HasLogLine('bytes of content'));
end;

procedure TStreamEngineTests.TestFormBombDrawnManyTimesIsBounded;
begin
  const Content = TStringBuilder.Create;
  try
    Content.Append('BT /F1 12 Tf (A) Tj ET');
    for var Index := 1 to 1000 do
    begin
      Content.Append(' /Fm0 Do');
    end;
    const Builder = NewBuilder(Content.ToString, 1);
    AddFlateForm(Builder, 0, 'BT /F1 12 Tf (B) Tj ET', FormResources(0), BombSize);
    var Options := TPdfLoadOptions.Default;
    Options.MaxContentBytesPerPage := 4 * 1024 * 1024;
    const Watch = TStopwatch.StartNew;
    Run(Builder, Options);

    Assert.IsTrue(Watch.ElapsedMilliseconds < 5000, Format('Took %d ms', [Watch.ElapsedMilliseconds]));
  finally
    Content.Free;
  end;

  // The page is 8 KB, a run of the form 600 KB: six runs fit in 4 MiB, the seventh ends the page
  Assert.AreEqual<Integer>(7, FEngine.Glyphs.Count);
  Assert.AreEqual('A', Chr(Glyph(0).Code));
  Assert.IsTrue(HasLogLine('bytes of content'));
end;

procedure TStreamEngineTests.TestFormBombFanOutIsBounded;
begin
  const FormCount = 20;
  const Builder = NewBuilder('/Fm0 Do', FormCount);
  for var Index := 0 to FormCount - 1 do
  begin
    if Index < FormCount - 1 then
    begin
      AddFlateForm(Builder, Index, 'BT /F1 12 Tf (A) Tj ET /Fm1 Do /Fm1 Do', FormResources(Index + 1), 200 * 1024);
    end
    else
    begin
      AddFlateForm(Builder, Index, 'BT /F1 12 Tf (A) Tj ET', FormResources(Index), 200 * 1024);
    end;
  end;

  var Options := TPdfLoadOptions.Default;
  Options.MaxContentBytesPerPage := 4 * 1024 * 1024;
  const Watch = TStopwatch.StartNew;
  Run(Builder, Options);

  Assert.IsTrue(Watch.ElapsedMilliseconds < 5000, Format('Took %d ms', [Watch.ElapsedMilliseconds]));
  Assert.IsTrue(HasLogLine('bytes of content'));
  Assert.IsTrue(FEngine.Glyphs.Count > 0);
end;

procedure TStreamEngineTests.TestManySmallContentStreamsAreJoinedInLinearTime;
begin
  const Refs = TStringBuilder.Create;
  try
    Refs.Append('[');
    for var Index := 1 to 100000 do
    begin
      Refs.Append('4 0 R ');
    end;
    Refs.Append(']');
    FContentsEntry := Refs.ToString;
  finally
    Refs.Free;
  end;

  const Watch = TStopwatch.StartNew;
  RunContent('BT ET');

  Assert.IsTrue(Watch.ElapsedMilliseconds < 5000, Format('Took %d ms', [Watch.ElapsedMilliseconds]));
  Assert.AreEqual<Integer>(0, FLines.Count);
end;

procedure TStreamEngineTests.TestOperandsBeforeAnOperatorAreBounded;
begin
  const Content = TStringBuilder.Create;
  try
    for var Index := 1 to 1000000 do
    begin
      Content.Append('1 ');
    end;
    Content.Append('BT /F1 12 Tf (A) Tj ET');
    const Watch = TStopwatch.StartNew;
    RunContent(Content.ToString);

    Assert.IsTrue(Watch.ElapsedMilliseconds < 5000, Format('Took %d ms', [Watch.ElapsedMilliseconds]));
  finally
    Content.Free;
  end;

  Assert.AreEqual<Integer>(1, FEngine.Glyphs.Count);
  Assert.AreEqual<Integer>(1, CountLogLines('operands'));
end;

procedure TStreamEngineTests.TestHugeTJArrayIsBounded;
begin
  const Content = TStringBuilder.Create;
  try
    Content.Append('BT /F1 12 Tf [(A) ');
    for var Index := 1 to 1000000 do
    begin
      Content.Append('1 ');
    end;
    Content.Append('] TJ ET');
    const Watch = TStopwatch.StartNew;
    RunContent(Content.ToString);

    Assert.IsTrue(Watch.ElapsedMilliseconds < 5000, Format('Took %d ms', [Watch.ElapsedMilliseconds]));
  finally
    Content.Free;
  end;

  Assert.AreEqual<Integer>(1, FEngine.Glyphs.Count);
  Assert.AreEqual<Integer>(1, CountLogLines('array has more than'));
end;

end.
