// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Tests for Pdf4D.Text.LegacyStreamEngine. The expected values of the Helvetica and embedded font cases were confirmed with
// PDFBox 3.0.8 (a PDFTextStripper subclass that prints every TextPosition).
unit Pdf4D.Text.LegacyStreamEngine.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Common.Defines,
  Pdf4D.Common.Log,
  Pdf4D.Model.DocumentContext,
  Pdf4D.Model.Page,
  Pdf4D.Model.Tests.Support,
  Pdf4D.Tests.PdfBuilder,
  Pdf4D.Text.LegacyStreamEngine,
  Pdf4D.Text.TextPosition;

type
  // Collects the positions
  TCollectingEngine = class(TLegacyPdfStreamEngine)
  private
    FPositions: TObjectList<TTextPosition>;

  protected
    procedure ProcessTextPosition(const Text: TTextPosition); override;

  public
    constructor Create;
    destructor Destroy; override;

    property Positions: TObjectList<TTextPosition> read FPositions;
  end;

  [TestFixture]
  TLegacyStreamEngineTests = class
  private
    FModels: TModelTestDocuments;
    FLog: TPdfLog;
    FContext: TPDDocumentContext;
    FPage: TPDPage;
    FEngine: TCollectingEngine;

    function NewBuilder(const PageEntries, Content, FontBody: string): TTestPdfBuilder;
    procedure Run(const Builder: TTestPdfBuilder);
    procedure RunHelvetica(const Content: string; const PageEntries: string = '');
    function Position(const Index: Integer): TTextPosition;
    procedure AssertNear(const Expected, Actual: Single);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestHelveticaPositions;

    [Test]
    procedure TestEmbeddedTrueTypePositions;

    [Test]
    procedure TestCropBoxTranslation;

    [Test]
    procedure TestRotatedText;

    [Test]
    procedure TestRotatedPage;

    [Test]
    procedure TestUnmappedCodeInSimpleFontIsCoerced;

    [Test]
    procedure TestUnmappedCodeInCompositeFontIsSkipped;

    [Test]
    procedure TestType3CharProcIsNotRun;

    [Test]
    procedure TestFontHeightIsComputedOncePerFont;

    [Test]
    procedure TestDiacriticMergeOfPositionsFromAPage;
  end;

implementation

uses
  Pdf4D.Tests.TestFonts,
  Pdf4D.Tests.TextDocuments;

const
  Tolerance = 0.001;
  HelveticaBody = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>';
  PageStart = '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 10 0 R >> >> ';
  Type0Body = '<< /Type /Font /Subtype /Type0 /BaseFont /Test /Encoding /Identity-H /DescendantFonts [11 0 R] >>';
  DescendantBody = '<< /Type /Font /Subtype /CIDFontType2 /BaseFont /Test /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /DW 500 >>';
  Type3Body = '<< /Type /Font /Subtype /Type3 /FontBBox [0 0 100 100] /FontMatrix [0.001 0 0 0.001 0 0] /CharProcs << /A 30 0 R >> ' +
              '/Encoding << /Differences [65 /A] >> /FirstChar 65 /LastChar 200 /Widths [500]>>';
  EmbeddedFontBody = '<< /Type /Font /Subtype /TrueType /BaseFont /LiberationSans /Encoding /WinAnsiEncoding /FontDescriptor 20 0 R >>';

{ TCollectingEngine }

constructor TCollectingEngine.Create;
begin
  inherited Create;
  FPositions := TObjectList<TTextPosition>.Create(True);
end;

destructor TCollectingEngine.Destroy;
begin
  FPositions.Free;
  inherited;
end;

procedure TCollectingEngine.ProcessTextPosition(const Text: TTextPosition);
begin
  FPositions.Add(Text);
end;

{ TLegacyStreamEngineTests }

procedure TLegacyStreamEngineTests.Setup;
begin
  FModels := TModelTestDocuments.Create;
  FLog := TPdfLog.Create(nil);
  FEngine := TCollectingEngine.Create;
end;

procedure TLegacyStreamEngineTests.TearDown;
begin
  FreeAndNil(FEngine);
  FreeAndNil(FPage);
  FreeAndNil(FContext);
  FreeAndNil(FLog);
  FreeAndNil(FModels);
end;

function TLegacyStreamEngineTests.NewBuilder(const PageEntries, Content, FontBody: string): TTestPdfBuilder;
begin
  Result := TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  try
    Result.AddObject(3, PageStart + PageEntries + ' >>');
    Result.AddStreamObject(4, '', TEncoding.ASCII.GetBytes(Content));
    Result.AddObject(10, FontBody);
  except
    Result.Free;
    raise;
  end;
end;

procedure TLegacyStreamEngineTests.Run(const Builder: TTestPdfBuilder);
begin
  try
    const Document = FModels.Open(Builder);
    FContext := TPDDocumentContext.Create(FLog, TPdfLoadOptions.Default);
    FPage := TPDPage.Create(Document.Pages.Get(0).CosObject, FContext);
    FEngine.ProcessPage(FPage);
  finally
    Builder.Free;
  end;
end;

procedure TLegacyStreamEngineTests.RunHelvetica(const Content: string; const PageEntries: string);
begin
  Run(NewBuilder(PageEntries, Content, HelveticaBody));
end;

function TLegacyStreamEngineTests.Position(const Index: Integer): TTextPosition;
begin
  Result := FEngine.Positions[Index];
end;

procedure TLegacyStreamEngineTests.AssertNear(const Expected, Actual: Single);
begin
  Assert.IsTrue(Abs(Expected - Actual) < Tolerance, Format('Expected %g but was %g', [Expected, Actual]));
end;

procedure TLegacyStreamEngineTests.TestHelveticaPositions;
begin
  RunHelvetica('BT /F1 12 Tf 100 700 Td (Hi) Tj ET');

  Assert.AreEqual<Integer>(2, FEngine.Positions.Count);
  AssertNear(100, Position(0).XDirAdj);
  AssertNear(92, Position(0).YDirAdj);
  AssertNear(8.664, Position(0).WidthDirAdj);
  AssertNear(3.336, Position(0).WidthOfSpace);
  AssertNear(6.936, Position(0).Height);
  Assert.AreEqual('H', Position(0).Unicode);
  AssertNear(12, Position(0).FontSize);
  AssertNear(12, Position(0).FontSizeInPt);
  AssertNear(108.664, Position(1).XDirAdj);
  AssertNear(2.664, Position(1).WidthDirAdj);
  Assert.AreEqual('i', Position(1).Unicode);
  Assert.AreEqual<Integer>(72, Position(0).CharacterCodes[0]);
end;

procedure TLegacyStreamEngineTests.TestEmbeddedTrueTypePositions;
begin
  const FontFile = TTestFonts.Bytes('LiberationSans-Regular.ttf');
  const Builder = NewBuilder('', 'BT /F1 12 Tf 100 700 Td (Hi) Tj ET', EmbeddedFontBody);
  try
    Builder.AddObject(20, '<< /Type /FontDescriptor /FontName /LiberationSans /Flags 32 /FontBBox [-203 -303 1050 910] /ItalicAngle 0 ' +
                          '/Ascent 905 /Descent -212 /CapHeight 729 /StemV 80 /FontFile2 21 0 R >>');
    TTextTestDocuments.AddFontFile(Builder, 21, Format('/Length1 %d', [Length(FontFile)]), FontFile);
  except
    Builder.Free;
    raise;
  end;
  Run(Builder);

  Assert.AreEqual<Integer>(2, FEngine.Positions.Count);
  AssertNear(8.666, Position(0).WidthDirAdj);
  AssertNear(3.334, Position(0).WidthOfSpace);
  // Half of the bounding box height (606.5) is smaller than the cap height, so it stays
  AssertNear(7.278, Position(0).Height);
  AssertNear(108.666, Position(1).XDirAdj);
  AssertNear(2.666, Position(1).WidthDirAdj);
end;

procedure TLegacyStreamEngineTests.TestCropBoxTranslation;
begin
  RunHelvetica('BT /F1 12 Tf 100 700 Td (Hi) Tj ET', '/CropBox [50 50 562 742]');

  AssertNear(50, Position(0).XDirAdj);
  AssertNear(42, Position(0).YDirAdj);
  AssertNear(512, Position(0).PageWidth);
  AssertNear(692, Position(0).PageHeight);
  AssertNear(58.664, Position(1).XDirAdj);
end;

procedure TLegacyStreamEngineTests.TestRotatedText;
begin
  RunHelvetica('BT /F1 12 Tf 0 1 -1 0 300 300 Tm (A) Tj ET');

  Assert.AreEqual<Integer>(1, FEngine.Positions.Count);
  AssertNear(90, Position(0).Dir);
  AssertNear(300, Position(0).XDirAdj);
  AssertNear(300, Position(0).YDirAdj);
  AssertNear(8.004, Position(0).WidthDirAdj);
  AssertNear(0, Position(0).Width);
  AssertNear(492, Position(0).Y);
end;

procedure TLegacyStreamEngineTests.TestRotatedPage;
begin
  RunHelvetica('BT /F1 12 Tf 100 700 Td (Hi) Tj ET', '/Rotate 90');

  Assert.AreEqual<Integer>(90, Position(0).Rotation);
  AssertNear(700, Position(0).X);
  AssertNear(100, Position(0).Y);
  AssertNear(100, Position(0).XDirAdj);
  AssertNear(92, Position(0).YDirAdj);
  AssertNear(0, Position(0).Width);
  AssertNear(8.664, Position(0).WidthDirAdj);
end;

procedure TLegacyStreamEngineTests.TestUnmappedCodeInSimpleFontIsCoerced;
begin
  Run(NewBuilder('', 'BT /F1 12 Tf 100 700 Td <C8> Tj ET', Type3Body));

  Assert.AreEqual<Integer>(1, FEngine.Positions.Count);
  Assert.AreEqual(Char(200), Position(0).Unicode[1]);
  Assert.AreEqual<Integer>(1, Length(Position(0).Unicode));
end;

procedure TLegacyStreamEngineTests.TestUnmappedCodeInCompositeFontIsSkipped;
begin
  const Builder = NewBuilder('', 'BT /F1 12 Tf 100 700 Td <FFFF> Tj ET', Type0Body);
  try
    Builder.AddObject(11, DescendantBody);
  except
    Builder.Free;
    raise;
  end;
  Run(Builder);

  Assert.AreEqual<Integer>(0, FEngine.Positions.Count);
end;

procedure TLegacyStreamEngineTests.TestType3CharProcIsNotRun;
begin
  // PDFBox overrides showGlyph without running the glyph procedure: the text in it never shows up
  const Builder = NewBuilder('', 'BT /F1 12 Tf 100 700 Td (A) Tj ET', Type3Body);
  try
    Builder.AddStreamObject(30, '', TEncoding.ASCII.GetBytes('500 0 d0 BT /F1 12 Tf (Z) Tj ET'));
  except
    Builder.Free;
    raise;
  end;
  Run(Builder);

  Assert.AreEqual<Integer>(1, FEngine.Positions.Count);
  Assert.AreEqual('A', Position(0).Unicode);
  AssertNear(6, Position(0).WidthDirAdj);
end;

procedure TLegacyStreamEngineTests.TestFontHeightIsComputedOncePerFont;
begin
  RunHelvetica('BT /F1 12 Tf 100 700 Td (HiH) Tj 0 -20 Td (i) Tj ET');

  Assert.AreEqual<Integer>(4, FEngine.Positions.Count);
  for var Index := 0 to 3 do
  begin
    AssertNear(6.936, Position(Index).Height);
  end;
end;

procedure TLegacyStreamEngineTests.TestDiacriticMergeOfPositionsFromAPage;
begin
  // Acute accent (WinAnsi 180) printed over the e
  Run(NewBuilder('', 'BT /F1 12 Tf 100 700 Td (e) Tj -5 0 Td <B4> Tj ET', '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>'));

  Assert.AreEqual<Integer>(2, FEngine.Positions.Count);
  Assert.AreEqual(#$00B4, Position(1).Unicode);
  Assert.IsTrue(Position(1).IsDiacritic);
  Position(0).MergeDiacritic(Position(1));
  Assert.AreEqual('e'#$0301, Position(0).Unicode);
end;

end.
