// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of the text part of PageDrawer (PDFBox 3.0.8): glyph outlines in all rendering modes and Type 3 fonts, through the recording device
unit Pdf4D.Render.PageDrawer.Text.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Render.Renderer.Interfaces,
  Pdf4D.Tests.GraphicsDocuments,
  Pdf4D.Tests.PdfBuilder,
  Pdf4D.Tests.RecordingDevice;

type
  [TestFixture]
  TPageDrawerTextTests = class
  private
    const Tolerance: Single = 0.01;
    const HelveticaResources = '/Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >>';
    const FirstType3Code = 65;
    const Type3Font = '<< /Type /Font /Subtype /Type3 /FontBBox [0 0 100 100] /FontMatrix [0.01 0 0 0.01 0 0] /FirstChar 65 /LastChar %d ' +
                      '/Widths [%s] /Encoding << /Differences [65 %s] >> /CharProcs << %s >> /Resources << /Font << /F1 5 0 R >> >> >>';
    const VerticalResources = '/Font << /F1 << /Type /Font /Subtype /Type0 /BaseFont /Test /Encoding /Identity-V /DescendantFonts [5 0 R] >> ' +
                              '/F2 << /Type /Font /Subtype /Type0 /BaseFont /Test /Encoding /Identity-H /DescendantFonts [5 0 R] >> >>';
    const Descendant = '<< /Type /Font /Subtype /CIDFontType2 /BaseFont /Test /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) ' +
                       '/Supplement 0 >> /DW 500 >>';

  private
    FDocuments: TGraphicsDocuments;
    FDocument: IPdfDocument;
    FRenderer: IPdfRenderer;
    FDevice: TRecordingDevice;
    FDeviceReference: IPdfRasterDevice;

    procedure RenderBuilt(const Builder: TTestPdfBuilder);
    procedure Render(const Content: string; const Resources: string = HelveticaResources);
    // A Type 3 font (object 5) with the glyphs A, B, C ...; a glyph with an empty procedure has no entry in /CharProcs
    procedure RenderType3(const Content: string; const CharProcs: TArray<string>);
    procedure RenderVertical(const Content: string);
    function CallsOf(const Kind: TRecordedCallKind): TArray<TRecordedCall>;
    function CountLogLines(const Fragment: string): Integer;
    procedure AssertNear(const Expected, Actual: Single);
    procedure AssertBounds(const Left, Top, Right, Bottom: Single; const Actual: TRectF);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestHelveticaGlyphIsFilledPath;

    [Test]
    procedure TestStrokeModeStrokesGlyph;

    [Test]
    procedure TestFillStrokeModeDoesBoth;

    [Test]
    procedure TestInvisibleModeDrawsNothing;

    [Test]
    procedure TestClipModesClipAtEndText;

    [Test]
    procedure TestInvisibleClipModeClipsWithoutDrawing;

    [Test]
    procedure TestSecondGlyphFollowsTheAdvance;

    [Test]
    procedure TestType3GlyphRunsCharProc;

    [Test]
    procedure TestType3MissingCharProcSkipsGlyph;

    [Test]
    procedure TestType3InvisibleModeDrawsNothing;

    [Test]
    procedure TestType3GlyphUsingOwnFontStops;

    [Test]
    procedure TestType3NestingStopsAtMaxType3Depth;

    [Test]
    procedure TestVerticalCidFont;

    [Test]
    procedure TestStandard14AliasIsNotStretched;

    [Test]
    procedure TestZeroPdfWidthIsNotStretched;
  end;

implementation

uses
  Pdf4D.Common.Path,
  Pdf4D.Render.Renderer;

{ TPageDrawerTextTests }

procedure TPageDrawerTextTests.AssertNear(const Expected, Actual: Single);
begin
  Assert.AreEqual(Double(Expected), Double(Actual), Double(Tolerance));
end;

procedure TPageDrawerTextTests.AssertBounds(const Left, Top, Right, Bottom: Single; const Actual: TRectF);
begin
  AssertNear(Left, Actual.Left);
  AssertNear(Top, Actual.Top);
  AssertNear(Right, Actual.Right);
  AssertNear(Bottom, Actual.Bottom);
end;

procedure TPageDrawerTextTests.Setup;
begin
  FDocuments := TGraphicsDocuments.Create;
  FDevice := TRecordingDevice.Create(TGraphicsDocuments.PageSize, TGraphicsDocuments.PageSize);
  FDeviceReference := FDevice;
end;

procedure TPageDrawerTextTests.TearDown;
begin
  FDeviceReference := nil;
  FRenderer := nil;
  FDocument := nil;
  FreeAndNil(FDocuments);
end;

procedure TPageDrawerTextTests.RenderBuilt(const Builder: TTestPdfBuilder);
begin
  FDocument := FDocuments.Open(Builder);
  FRenderer := TPdfRenderer.Create(FDocument, TRecordingBackend.Create);

  const Status = FRenderer.RenderPage(0, FDeviceReference, TPdfRenderParams.Create(1));

  Assert.AreEqual(TPdfRenderStatus.Completed, Status);
end;

procedure TPageDrawerTextTests.Render(const Content: string; const Resources: string);
begin
  FDocument := FDocuments.Open(Content, Resources);
  FRenderer := TPdfRenderer.Create(FDocument, TRecordingBackend.Create);

  const Status = FRenderer.RenderPage(0, FDeviceReference, TPdfRenderParams.Create(1));

  Assert.AreEqual(TPdfRenderStatus.Completed, Status);
end;

procedure TPageDrawerTextTests.RenderType3(const Content: string; const CharProcs: TArray<string>);
begin
  const Names = TStringBuilder.Create;
  const Widths = TStringBuilder.Create;
  const Entries = TStringBuilder.Create;
  const Builder = TGraphicsDocuments.NewBuilder(TEncoding.ASCII.GetBytes(Content), '/Font << /F1 5 0 R >>');
  try
    for var Index := 0 to High(CharProcs) do
    begin
      const GlyphName = Char(Ord('A') + Index);
      Names.Append('/').Append(GlyphName).Append(' ');
      Widths.Append('50 ');
      if CharProcs[Index] <> '' then
      begin
        const Number = 30 + Index;
        Entries.AppendFormat('/%s %d 0 R ', [GlyphName, Number]);
        Builder.AddStreamObject(Number, '', TEncoding.ASCII.GetBytes(CharProcs[Index]));
      end;
    end;
    Builder.AddObject(5, Format(Type3Font, [FirstType3Code + High(CharProcs), Widths.ToString, Names.ToString, Entries.ToString]));
    RenderBuilt(Builder);
  finally
    Builder.Free;
    Entries.Free;
    Widths.Free;
    Names.Free;
  end;
end;

procedure TPageDrawerTextTests.RenderVertical(const Content: string);
begin
  const Builder = TGraphicsDocuments.NewBuilder(TEncoding.ASCII.GetBytes(Content), VerticalResources);
  try
    Builder.AddObject(5, Descendant);
    RenderBuilt(Builder);
  finally
    Builder.Free;
  end;
end;

function TPageDrawerTextTests.CallsOf(const Kind: TRecordedCallKind): TArray<TRecordedCall>;
begin
  const Found = TList<TRecordedCall>.Create;
  try
    for var Call in FDevice.Calls do
    begin
      if Call.Kind = Kind then
      begin
        Found.Add(Call);
      end;
    end;
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

function TPageDrawerTextTests.CountLogLines(const Fragment: string): Integer;
begin
  Result := 0;
  for var Line in FDocuments.LogLines do
  begin
    if Line.Contains(Fragment) then
    begin
      Inc(Result);
    end;
  end;
end;

// LiberationSans stands for Helvetica: 2048 units per em, and the capital A spans x 4..1362 and y 0..1409 in them
procedure TPageDrawerTextTests.TestHelveticaGlyphIsFilledPath;
begin
  Render('BT /F1 12 Tf 100 100 Td (A) Tj ET');

  const Fills = CallsOf(TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(1, Length(Fills));
  Assert.AreEqual(TPdfPaintKind.Solid, Fills[0].Paint.Kind);
  Assert.AreEqual(Byte(0), Fills[0].Paint.Color.R);
  AssertBounds(100 + 4 * 12 / 2048, 200 - (100 + 1409 * 12 / 2048), 100 + 1362 * 12 / 2048, 100, Fills[0].DeviceBounds);
end;

procedure TPageDrawerTextTests.TestStrokeModeStrokesGlyph;
begin
  Render('BT /F1 12 Tf 1 Tr 100 100 Td (A) Tj ET');

  Assert.AreEqual<Integer>(0, Length(CallsOf(TRecordedCallKind.Fill)));
  Assert.AreEqual<Integer>(1, Length(CallsOf(TRecordedCallKind.Stroke)));
end;

procedure TPageDrawerTextTests.TestFillStrokeModeDoesBoth;
begin
  Render('BT /F1 12 Tf 2 Tr 100 100 Td (A) Tj ET');

  Assert.AreEqual<Integer>(1, Length(CallsOf(TRecordedCallKind.Fill)));
  Assert.AreEqual<Integer>(1, Length(CallsOf(TRecordedCallKind.Stroke)));
end;

procedure TPageDrawerTextTests.TestInvisibleModeDrawsNothing;
begin
  Render('BT /F1 12 Tf 3 Tr 100 100 Td (A) Tj ET');

  Assert.AreEqual<Integer>(0, Length(CallsOf(TRecordedCallKind.Fill)));
  Assert.AreEqual<Integer>(0, Length(CallsOf(TRecordedCallKind.Stroke)));
end;

procedure TPageDrawerTextTests.TestClipModesClipAtEndText;
begin
  Render('BT /F1 12 Tf 7 Tr 100 100 Td (A) Tj ET 0 0 200 200 re f');

  const Fills = CallsOf(TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(1, Length(Fills));
  Assert.AreEqual<Integer>(2, Fills[0].ClipDepth);
  const ClipPath = FDevice.Clip.Path.Clone;
  try
    ClipPath.Transform(FDevice.Clip.Transform);
    AssertBounds(100 + 4 * 12 / 2048, 200 - (100 + 1409 * 12 / 2048), 100 + 1362 * 12 / 2048, 100, ClipPath.Bounds);
  finally
    ClipPath.Free;
  end;
end;

// Mode 4 fills the glyph and clips to it
procedure TPageDrawerTextTests.TestInvisibleClipModeClipsWithoutDrawing;
begin
  Render('BT /F1 12 Tf 4 Tr 100 100 Td (A) Tj ET');

  Assert.AreEqual<Integer>(1, Length(CallsOf(TRecordedCallKind.Fill)));
  Assert.AreEqual<Integer>(0, Length(CallsOf(TRecordedCallKind.Stroke)));
end;

procedure TPageDrawerTextTests.TestSecondGlyphFollowsTheAdvance;
begin
  Render('BT /F1 12 Tf 100 100 Td (AA) Tj ET');

  const Fills = CallsOf(TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(2, Length(Fills));
  // The width of A in Helvetica is 667 thousandths
  AssertNear(Fills[0].DeviceBounds.Left + 667 * 12 / 1000, Fills[1].DeviceBounds.Left);
end;

procedure TPageDrawerTextTests.TestType3GlyphRunsCharProc;
begin
  RenderType3('BT /F1 10 Tf 100 100 Td (A) Tj ET', ['50 0 0 0 40 40 d1 0 0 40 40 re f']);

  const Fills = CallsOf(TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(1, Length(Fills));
  // 40 glyph units, 0.01 for the font matrix, 10 for the font size
  AssertBounds(100, 96, 104, 100, Fills[0].DeviceBounds);
end;

procedure TPageDrawerTextTests.TestType3MissingCharProcSkipsGlyph;
begin
  RenderType3('BT /F1 10 Tf 100 100 Td (BA) Tj ET', ['0 0 40 40 re f', '']);

  const Fills = CallsOf(TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(1, Length(Fills));
  // B is skipped, but its width of 50 glyph units (0.01 * 10 each) moves the next glyph
  AssertBounds(105, 96, 109, 100, Fills[0].DeviceBounds);
  Assert.AreEqual(1, CountLogLines('glyph procedure'));
end;

procedure TPageDrawerTextTests.TestType3InvisibleModeDrawsNothing;
begin
  RenderType3('BT /F1 10 Tf 3 Tr 100 100 Td (A) Tj ET', ['0 0 40 40 re f']);

  Assert.AreEqual<Integer>(0, Length(CallsOf(TRecordedCallKind.Fill)));
end;

procedure TPageDrawerTextTests.TestType3GlyphUsingOwnFontStops;
begin
  RenderType3('BT /F1 10 Tf 100 100 Td (AB) Tj ET', ['0 0 4 4 re f BT /F1 10 Tf (A) Tj ET', '0 0 40 40 re f']);

  // The recursion ends with a line in the log, and the glyph after it is drawn
  Assert.IsTrue(CountLogLines('recursion') + CountLogLines('Type 3') >= 1);
  Assert.IsTrue(Length(CallsOf(TRecordedCallKind.Fill)) >= 2);
end;

procedure TPageDrawerTextTests.TestType3NestingStopsAtMaxType3Depth;
begin
  // Glyph A shows B, B shows C and so on: no glyph uses itself, so only the depth limit stops it
  const GlyphCount = 12;
  var CharProcs: TArray<string>;
  SetLength(CharProcs, GlyphCount);
  for var Index := 0 to GlyphCount - 2 do
  begin
    CharProcs[Index] := Format('BT /F1 1 Tf (%s) Tj ET', [Char(Ord('B') + Index)]);
  end;
  CharProcs[GlyphCount - 1] := '0 0 40 40 re f';

  RenderType3('BT /F1 10 Tf 100 100 Td (A) Tj ET', CharProcs);

  Assert.AreEqual<Integer>(0, Length(CallsOf(TRecordedCallKind.Fill)));
  Assert.AreEqual(1, CountLogLines('Type 3'));
end;

// The position vector of a vertical glyph is (-w0 / 2, -0.88) in em, and w0 is the default width of 500
procedure TPageDrawerTextTests.TestVerticalCidFont;
begin
  RenderVertical('BT /F2 10 Tf 100 100 Td <0024> Tj ET BT /F1 10 Tf 100 100 Td <0024> Tj ET');

  const Fills = CallsOf(TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(2, Length(Fills));
  const Horizontal = Fills[0].DeviceBounds;
  const Vertical = Fills[1].DeviceBounds;
  AssertNear(Horizontal.Left - 500 / 2 / 1000 * 10, Vertical.Left);
  AssertNear(Horizontal.Top + 0.88 * 10, Vertical.Top);
  // Neither glyph is stretched: the horizontal one has no width of its own in /W, only the default /DW, and the vertical one has no
  // horizontal displacement
  AssertNear(Horizontal.Width, Vertical.Width);
end;

// drawGlyph stretches the glyph of a font that is not embedded, but not one that PDFBox counts as a standard 14 font: the name
// TimesNewRoman is an alias of Times-Roman. A font of another name is stretched to the width of the PDF.
procedure TPageDrawerTextTests.TestStandard14AliasIsNotStretched;
begin
  const Resources = '/Font << /F1 << /Type /Font /Subtype /TrueType /BaseFont /TimesNewRoman /FirstChar 105 /LastChar 105 /Widths [1000] >> ' +
                    '/F2 << /Type /Font /Subtype /TrueType /BaseFont /SomeOtherFont /FirstChar 105 /LastChar 105 /Widths [1000] >> >>';
  Render('BT /F1 10 Tf 100 100 Td (i) Tj ET BT /F2 10 Tf 100 100 Td (i) Tj ET', Resources);

  const Fills = CallsOf(TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(2, Length(Fills));
  Assert.IsTrue(Fills[0].DeviceBounds.Width < Fills[1].DeviceBounds.Width, 'the alias keeps the width of the glyph, the other font is stretched');
end;

// PDFBOX-5611: a glyph with a width of zero in the PDF is not stretched to nothing
procedure TPageDrawerTextTests.TestZeroPdfWidthIsNotStretched;
begin
  const Resources = '/Font << /F1 << /Type /Font /Subtype /TrueType /BaseFont /SomeOtherFont /FirstChar 105 /LastChar 105 /Widths [0] >> >>';
  Render('BT /F1 10 Tf 100 100 Td (i) Tj ET', Resources);

  const Fills = CallsOf(TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(1, Length(Fills));
  Assert.IsTrue(Fills[0].DeviceBounds.Width > 0.5);
end;

end.
