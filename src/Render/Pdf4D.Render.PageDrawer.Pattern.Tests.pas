// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of the tiling patterns in PageDrawer (PDFBox 3.0.8): getPaint for a pattern colour, the pattern as fill and stroke colour and the
// colours of an uncoloured pattern, through the recording device
unit Pdf4D.Render.PageDrawer.Pattern.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Render.Renderer.Interfaces,
  Pdf4D.Tests.PatternDocuments,
  Pdf4D.Tests.RecordingDevice;

type
  [TestFixture]
  TPageDrawerPatternTests = class
  private
    const Tolerance = 0.0001;
    const SamplingTolerance = 0.01;

  private
    FDocuments: TPatternDocuments;
    FDocument: IPdfDocument;
    FRenderer: IPdfRenderer;
    FDevice: TRecordingDevice;
    FDeviceReference: IPdfRasterDevice;

    procedure Render(const PageContent: string; const Patterns: array of TTilingSource; const ExtraResources: string = '');
    function CallsOfKind(const Calls: TArray<TRecordedCall>; const Kind: TRecordedCallKind): TArray<TRecordedCall>;
    function CellFills: TArray<TRecordedCall>;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestUncoloredPatternUsesTheColorOfTheOperator;

    [Test]
    procedure TestColoredPatternKeepsItsOwnColors;

    [Test]
    procedure TestPatternAsStrokeColor;

    [Test]
    procedure TestPatternMatrixIsApplied;

    [Test]
    procedure TestPatternWithoutBoxPaintsNothing;

    [Test]
    procedure TestMissingPatternPaintsNothing;

    [Test]
    procedure TestPatternAsTextFillColor;
  end;

implementation

uses
  System.Generics.Collections,
  Pdf4D.Render.Renderer,
  Pdf4D.Tests.GraphicsDocuments;

const
  UncoloredSpace = '/ColorSpace << /CsU [/Pattern /DeviceRGB] >>';
  Dot = '0 0 5 5 re f';

{ TPageDrawerPatternTests }

procedure TPageDrawerPatternTests.Setup;
begin
  FDocuments := TPatternDocuments.Create;
  FDevice := TRecordingDevice.Create(TGraphicsDocuments.PageSize, TGraphicsDocuments.PageSize);
  FDeviceReference := FDevice;
end;

procedure TPageDrawerPatternTests.TearDown;
begin
  FDeviceReference := nil;
  FRenderer := nil;
  FDocument := nil;
  FreeAndNil(FDocuments);
end;

procedure TPageDrawerPatternTests.Render(const PageContent: string; const Patterns: array of TTilingSource; const ExtraResources: string);
begin
  FDocument := FDocuments.OpenWithPatterns(PageContent, Patterns, ExtraResources);
  FRenderer := TPdfRenderer.Create(FDocument, TRecordingBackend.Create);

  const Status = FRenderer.RenderPage(0, FDeviceReference, TPdfRenderParams.Create(1));

  Assert.AreEqual(TPdfRenderStatus.Completed, Status);
end;

function TPageDrawerPatternTests.CallsOfKind(const Calls: TArray<TRecordedCall>; const Kind: TRecordedCallKind): TArray<TRecordedCall>;
begin
  const Found = TList<TRecordedCall>.Create;
  try
    for var Call in Calls do
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

// The fills on the layer of the first cell
function TPageDrawerPatternTests.CellFills: TArray<TRecordedCall>;
begin
  Assert.IsTrue(FDevice.LayerCount > 0, 'a cell was made');
  Result := CallsOfKind(FDevice.Layers[0].Calls.ToArray, TRecordedCallKind.Fill);
end;

procedure TPageDrawerPatternTests.TestUncoloredPatternUsesTheColorOfTheOperator;
begin
  Render('/CsU cs 1 0 0 /P1 scn 0 0 100 100 re f', [TTilingSource.Square(2, '10', Dot)], UncoloredSpace);

  const Fills = CellFills;
  Assert.AreEqual<Integer>(1, Length(Fills));
  Assert.AreEqual(TPdfPaintKind.Solid, Fills[0].Paint.Kind);
  Assert.AreEqual<Integer>(255, Fills[0].Paint.Color.R);
  Assert.AreEqual<Integer>(0, Fills[0].Paint.Color.G);
  Assert.AreEqual<Integer>(0, Fills[0].Paint.Color.B);
end;

procedure TPageDrawerPatternTests.TestColoredPatternKeepsItsOwnColors;
begin
  Render('0 0 1 rg /Pattern cs /P1 scn 0 0 100 100 re f', [TTilingSource.Square(1, '10', '0 1 0 rg ' + Dot)]);

  const Fills = CellFills;
  Assert.AreEqual<Integer>(1, Length(Fills));
  Assert.AreEqual<Integer>(255, Fills[0].Paint.Color.G);
  Assert.AreEqual<Integer>(0, Fills[0].Paint.Color.B);
end;

procedure TPageDrawerPatternTests.TestPatternAsStrokeColor;
begin
  Render('/Pattern CS /P1 SCN 8 w 10 10 m 90 10 l S', [TTilingSource.Square(1, '10', '1 0 0 rg ' + Dot)]);

  const Strokes = CallsOfKind(FDevice.Calls.ToArray, TRecordedCallKind.Stroke);
  Assert.AreEqual<Integer>(1, Length(Strokes));
  Assert.AreEqual(TPdfPaintKind.Bitmap, Strokes[0].Paint.Kind);
  Assert.AreEqual(TPdfTileMode.&Repeat, Strokes[0].Paint.TileMode);
end;

// The cell pixel (0, 0) is the lower left corner of the box, which the pattern matrix moves to (5, 7) of the page: pixel (5, 193). The paint
// samples at the centre of a pixel, where Java takes the corner, so the matrix has half a pixel more (and a bias of a few thousandths).
procedure TPageDrawerPatternTests.TestPatternMatrixIsApplied;
begin
  Render('/Pattern cs /P1 scn 0 0 100 100 re f',
         [TTilingSource.Create('/PaintType 1 /TilingType 1 /BBox [0 0 10 10] /XStep 10 /YStep 10 /Matrix [1 0 0 1 5 7] /Resources << >>', Dot)]);

  const Fills = CallsOfKind(FDevice.Calls.ToArray, TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(1, Length(Fills));
  const ToDevice = Fills[0].Paint.BitmapToDevice;
  Assert.AreEqual(Double(5.5), Double(ToDevice.TranslateX), SamplingTolerance);
  Assert.AreEqual(Double(193.5), Double(ToDevice.TranslateY), SamplingTolerance);
  Assert.AreEqual(Double(1), Double(ToDevice.ScaleX), Tolerance);
  Assert.AreEqual(Double(-1), Double(ToDevice.ScaleY), Tolerance);
end;

procedure TPageDrawerPatternTests.TestPatternWithoutBoxPaintsNothing;
begin
  Render('/Pattern cs /P1 scn 0 0 100 100 re f',
         [TTilingSource.Create('/PaintType 1 /TilingType 1 /XStep 10 /YStep 10 /Resources << >>', Dot)]);

  Assert.AreEqual<Integer>(0, Length(CallsOfKind(FDevice.Calls.ToArray, TRecordedCallKind.Fill)));
end;

procedure TPageDrawerPatternTests.TestMissingPatternPaintsNothing;
begin
  Render('/Pattern cs /P9 scn 0 0 100 100 re f', [TTilingSource.Square(1, '10', Dot)]);

  Assert.AreEqual<Integer>(0, Length(CallsOfKind(FDevice.Calls.ToArray, TRecordedCallKind.Fill)));
end;

procedure TPageDrawerPatternTests.TestPatternAsTextFillColor;
begin
  Render('/Pattern cs /P1 scn BT /F1 40 Tf 10 10 Td (A) Tj ET', [TTilingSource.Square(1, '10', '1 0 0 rg ' + Dot)],
         '/Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >>');

  const Fills = CallsOfKind(FDevice.Calls.ToArray, TRecordedCallKind.Fill);
  Assert.IsTrue(Length(Fills) > 0, 'the glyph is filled');
  Assert.AreEqual(TPdfTileMode.&Repeat, Fills[0].Paint.TileMode);
end;

end.
