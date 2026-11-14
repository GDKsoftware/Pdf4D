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
  Pdf4D.Content.StreamEngine,
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
  end;

  // Registers the operators and records every glyph
  TRecordingEngine = class(TPdfStreamEngine)
  private
    FGlyphs: TList<TRecordedGlyph>;

  public
    constructor Create;
    destructor Destroy; override;

    procedure ShowGlyph(const TextRenderingMatrix: TPdfMatrix; const Font: TPDFont; const Code: Integer; const Displacement: TPdfVector); override;

    property Glyphs: TList<TRecordedGlyph> read FGlyphs;
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

    function NewBuilder(const Content: string; const FormCount: Integer = 0): TTestPdfBuilder;
    procedure AddForm(const Builder: TTestPdfBuilder; const Index: Integer; const Dictionary, Content, Resources: string);
    procedure Run(const Builder: TTestPdfBuilder); overload;
    procedure Run(const Builder: TTestPdfBuilder; const Options: TPdfLoadOptions); overload;
    function HasLogLine(const Fragment: string): Boolean;
    function Glyph(const Index: Integer): TRecordedGlyph;
    procedure AssertNear(const Expected, Actual: Single);
    procedure RunContent(const Content: string);
    function FormResources(const NextIndex: Integer): string;

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
  end;

implementation

uses
  System.Diagnostics,
  Pdf4D.Content.Operators.DrawObject,
  Pdf4D.Content.Operators.State,
  Pdf4D.Content.Operators.Text;

const
  PageHeader = '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 10 0 R /F2 11 0 R >> %s >> >>';
  HelveticaBody = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>';
  Type0Body = '<< /Type /Font /Subtype /Type0 /BaseFont /Test /Encoding /Identity-H /DescendantFonts [12 0 R] >>';
  DescendantBody = '<< /Type /Font /Subtype /CIDFontType2 /BaseFont /Test /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /DW 500 >>';
  Tolerance = 0.001;

{ TRecordingEngine }

constructor TRecordingEngine.Create;
begin
  inherited Create;
  FGlyphs := TList<TRecordedGlyph>.Create;
  TTextOperators.Register(Self);
  TStateOperators.Register(Self);
  TDrawObjectOperators.Register(Self);
end;

destructor TRecordingEngine.Destroy;
begin
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
  FGlyphs.Add(Item);
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
      Result.AddObject(3, Format(PageHeader, ['/XObject << ' + XObjects.ToString + '>>']));
    finally
      XObjects.Free;
    end;
    Result.AddStreamObject(4, '', TEncoding.ASCII.GetBytes(Content));
    Result.AddObject(10, HelveticaBody);
    Result.AddObject(11, Type0Body);
    Result.AddObject(12, DescendantBody);
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

end.
