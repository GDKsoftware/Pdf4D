// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of the tiling paint (TilingPaint and TilingPaintFactory of PDFBox 3.0.8) through the recording device: the size of the cell, the
// limits on untrusted patterns and the cache
unit Pdf4D.Render.TilingPaint.Tests;

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
  TTilingPaintTests = class
  private
    const RedDot = '1 0 0 rg 0 0 5 5 re f';
    const ChainLength = 12;

  private
    FDocuments: TPatternDocuments;
    FDocument: IPdfDocument;
    FRenderer: IPdfRenderer;
    FDevice: TRecordingDevice;
    FDeviceReference: IPdfRasterDevice;

    procedure Render(const PageContent: string; const Patterns: array of TTilingSource; const ExtraResources: string = '');
    function CountLogLines(const Fragment: string): Integer;
    function FillCount: Integer;
    // The number of cells that lie inside each other: the first layer of the device, the first layer of that one, and so on
    function NestedCellDepth: Integer;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestCellHasTheSizeOfTheStepInPixels;

    [Test]
    procedure TestCellIsPaintedWithARepeatingBitmapPaint;

    [Test]
    procedure TestZeroStepUsesTheBoxAndWarns;

    [Test]
    procedure TestHugeTileIsClampedToMaxEdge;

    [Test]
    procedure TestTooManyCellsIsSkipped;

    [Test]
    procedure TestHugeStepWithTinyOtherStepStaysBounded;

    [Test]
    procedure TestSelfReferencingPatternStops;

    [Test]
    procedure TestPatternsInsidePatternsStopAtTheDepthLimit;

    [Test]
    procedure TestPaintIsCachedPerColor;

    [Test]
    procedure TestColoredPaintIsMadeOnceForManyFills;
  end;

implementation

uses
  System.Diagnostics,
  Pdf4D.Render.Renderer,
  Pdf4D.Tests.GraphicsDocuments;

const
  UncoloredSpace = '/ColorSpace << /CsU [/Pattern /DeviceRGB] >>';

{ TTilingPaintTests }

procedure TTilingPaintTests.Setup;
begin
  FDocuments := TPatternDocuments.Create;
  FDevice := TRecordingDevice.Create(TGraphicsDocuments.PageSize, TGraphicsDocuments.PageSize);
  FDeviceReference := FDevice;
end;

procedure TTilingPaintTests.TearDown;
begin
  FDeviceReference := nil;
  FRenderer := nil;
  FDocument := nil;
  FreeAndNil(FDocuments);
end;

procedure TTilingPaintTests.Render(const PageContent: string; const Patterns: array of TTilingSource; const ExtraResources: string);
begin
  FDocument := FDocuments.OpenWithPatterns(PageContent, Patterns, ExtraResources);
  FRenderer := TPdfRenderer.Create(FDocument, TRecordingBackend.Create);

  const Status = FRenderer.RenderPage(0, FDeviceReference, TPdfRenderParams.Create(1));

  Assert.AreEqual(TPdfRenderStatus.Completed, Status);
end;

function TTilingPaintTests.CountLogLines(const Fragment: string): Integer;
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

function TTilingPaintTests.FillCount: Integer;
begin
  Result := 0;
  for var Call in FDevice.Calls do
  begin
    if Call.Kind = TRecordedCallKind.Fill then
    begin
      Inc(Result);
    end;
  end;
end;

function TTilingPaintTests.NestedCellDepth: Integer;
begin
  Result := 0;
  var Device := FDevice;
  while Device.LayerCount > 0 do
  begin
    Inc(Result);
    Device := Device.Layers[0];
  end;
end;

procedure TTilingPaintTests.TestCellHasTheSizeOfTheStepInPixels;
begin
  Render('/Pattern cs /P1 scn 0 0 100 100 re f', [TTilingSource.Square(1, '10', RedDot)]);

  Assert.AreEqual<Integer>(1, FDevice.LayerCount);
  Assert.AreEqual<Integer>(10, FDevice.Layers[0].Width);
  Assert.AreEqual<Integer>(10, FDevice.Layers[0].Height);
end;

procedure TTilingPaintTests.TestCellIsPaintedWithARepeatingBitmapPaint;
begin
  Render('/Pattern cs /P1 scn 0 0 100 100 re f', [TTilingSource.Square(1, '10', RedDot)]);

  Assert.AreEqual<Integer>(1, FillCount);
  const Paint = FDevice.Calls[FDevice.Calls.Count - 1].Paint;
  Assert.AreEqual(TPdfPaintKind.Bitmap, Paint.Kind);
  Assert.AreEqual(TPdfTileMode.&Repeat, Paint.TileMode);
  Assert.IsTrue(FDevice.Layers[0].Calls.Count > 0, 'the content of the pattern is drawn on the layer of the cell');
end;

procedure TTilingPaintTests.TestZeroStepUsesTheBoxAndWarns;
begin
  Render('/Pattern cs /P1 scn 0 0 100 100 re f',
         [TTilingSource.Create('/PaintType 1 /TilingType 1 /BBox [0 0 8 6] /XStep 0 /YStep 0 /Resources << >>', RedDot)]);

  Assert.AreEqual<Integer>(8, FDevice.Layers[0].Width);
  Assert.AreEqual<Integer>(6, FDevice.Layers[0].Height);
  Assert.AreEqual<Integer>(1, CountLogLines('/XStep is 0'));
  Assert.AreEqual<Integer>(1, CountLogLines('/YStep is 0'));
end;

procedure TTilingPaintTests.TestHugeTileIsClampedToMaxEdge;
begin
  Render('/Pattern cs /P1 scn 0 0 100 100 re f', [TTilingSource.Square(1, '10000', RedDot)]);

  Assert.AreEqual<Integer>(1, FDevice.LayerCount);
  Assert.IsTrue(FDevice.Layers[0].Width <= 3000, 'the cell is at most 3000 pixels wide');
  Assert.IsTrue(FDevice.Layers[0].Height <= 3000, 'the cell is at most 3000 pixels high');
  Assert.IsTrue(CountLogLines('Pattern surface larger than') > 0);
end;

procedure TTilingPaintTests.TestTooManyCellsIsSkipped;
begin
  const Watch = TStopwatch.StartNew;

  Render('/Pattern cs /P1 scn 0 0 200 200 re f',
         [TTilingSource.Create('/PaintType 1 /TilingType 1 /BBox [0 0 0.01 0.01] /XStep 0.01 /YStep 0.01 /Resources << >>', '0 0 0.01 0.01 re f')]);

  Assert.AreEqual<Integer>(0, FillCount, 'nothing is painted');
  Assert.IsTrue(CountLogLines('cells') > 0);
  Assert.IsTrue(Watch.ElapsedMilliseconds < 1000, 'skipped within a second');
end;

// One step that is far larger than the limit next to one that is tiny: the area of a cell is small, but one edge of it is not
procedure TTilingPaintTests.TestHugeStepWithTinyOtherStepStaysBounded;
begin
  Render('/Pattern cs /P1 scn 0 0 200 200 re f',
         [TTilingSource.Create('/PaintType 1 /TilingType 1 /BBox [0 0 1000000000 0.00001] /XStep 1000000000 /YStep 0.00001 /Resources << >>', RedDot)]);

  Assert.IsTrue(FDevice.LayerCount <= 1);
  for var Index := 0 to FDevice.LayerCount - 1 do
  begin
    Assert.IsTrue(FDevice.Layers[Index].Width <= 3000, 'the cell stays within the edge limit');
    Assert.IsTrue(FDevice.Layers[Index].Height <= 3000, 'the cell stays within the edge limit');
  end;
end;

procedure TTilingPaintTests.TestSelfReferencingPatternStops;
begin
  Render('/Pattern cs /P1 scn 0 0 100 100 re f',
         [TTilingSource.Create('/PaintType 1 /TilingType 1 /BBox [0 0 10 10] /XStep 10 /YStep 10 /Resources << /Pattern << /P1 5 0 R >> >>',
                               '/Pattern cs /P1 scn 0 0 10 10 re f')]);

  Assert.IsTrue(CountLogLines('itself') + CountLogLines('nested as deep') > 0, 'the recursion is logged');
  Assert.IsTrue(NestedCellDepth <= 8, 'no more cells inside each other than the depth limit');
end;

procedure TTilingPaintTests.TestPatternsInsidePatternsStopAtTheDepthLimit;
begin
  var Patterns: TArray<TTilingSource>;
  SetLength(Patterns, ChainLength);
  for var Index := 0 to ChainLength - 1 do
  begin
    const NextObject = TPatternDocuments.FirstPatternObject + Index + 1;
    const Entries = Format('/PaintType 1 /TilingType 1 /BBox [0 0 10 10] /XStep 10 /YStep 10 /Resources << /Pattern << /P1 %d 0 R >> >>', [NextObject]);
    Patterns[Index] := TTilingSource.Create(Entries, '0 0 1 rg 0 0 3 3 re f /Pattern cs /P1 scn 0 0 10 10 re f');
  end;

  Render('/Pattern cs /P1 scn 0 0 100 100 re f', Patterns);

  Assert.AreEqual<Integer>(1, CountLogLines('nested as deep'), 'the limit is logged once');
  Assert.AreEqual<Integer>(8, NestedCellDepth, 'MaxPatternDepth cells inside each other');
end;

procedure TTilingPaintTests.TestPaintIsCachedPerColor;
begin
  Render('/CsU cs 1 0 0 /P1 scn 0 0 10 10 re f 20 0 10 10 re f 0 1 0 /P1 scn 40 0 10 10 re f 60 0 10 10 re f',
         [TTilingSource.Square(2, '10', '0 0 5 5 re f')], UncoloredSpace);

  Assert.AreEqual<Integer>(4, FillCount);
  Assert.AreEqual<Integer>(2, FDevice.LayerCount, 'one cell for red and one for green');
end;

procedure TTilingPaintTests.TestColoredPaintIsMadeOnceForManyFills;
begin
  Render('/Pattern cs /P1 scn 0 0 10 10 re f 20 0 10 10 re f 40 0 10 10 re f', [TTilingSource.Square(1, '10', RedDot)]);

  Assert.AreEqual<Integer>(3, FillCount);
  Assert.AreEqual<Integer>(1, FDevice.LayerCount);
end;

end.
