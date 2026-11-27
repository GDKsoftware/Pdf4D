// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Pixel tests of the tiling patterns: the cell repeats over the area that is painted, as PDFBox 3.0.8 draws it
unit Pdf4D.Tests.RenderTiling.Base;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Tests.PatternDocuments;

type
  TRenderTilingTestsBase = class abstract
  protected
    function CreateBackend: IPdfRenderBackend; virtual; abstract;

  private
    const UncoloredSpace = '/ColorSpace << /CsU [/Pattern /DeviceRGB] >>';
    // A dot of 4 x 4 points in a cell of 10 x 10
    const RedDot = '1 0 0 rg 3 3 4 4 re f';

  private
    FDocuments: TPatternDocuments;
    FDocument: IPdfDocument;

    function Render(const PageContent: string; const Patterns: array of TTilingSource; const ExtraResources: string = ''): TPdfBitmap;
    procedure AssertPixel(const Bitmap: TPdfBitmap; const X, Y: Integer; const Expected: TPdfDeviceColor);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestColoredTilingRepeatsCell;

    [Test]
    procedure TestUncoloredPatternUsesFillColor;

    [Test]
    procedure TestPatternMatrixIsApplied;

    [Test]
    procedure TestStepSmallerThanCellOverlaps;

    [Test]
    procedure TestStepLargerThanCellLeavesGaps;

    [Test]
    procedure TestPatternAsStrokeColor;
  end;

implementation

uses
  Pdf4D.Render.Renderer,
  Pdf4D.Render.Renderer.Interfaces,
  Pdf4D.Tests.GraphicsDocuments;


const
  PageSize = TGraphicsDocuments.PageSize;
  Tolerance = 2;
  Red: TPdfDeviceColor = (R: 255; G: 0; B: 0; A: 255);

{ TRenderTilingTestsBase }

procedure TRenderTilingTestsBase.Setup;
begin
  FDocuments := TPatternDocuments.Create;
end;

procedure TRenderTilingTestsBase.TearDown;
begin
  FDocument := nil;
  FreeAndNil(FDocuments);
end;

function TRenderTilingTestsBase.Render(const PageContent: string; const Patterns: array of TTilingSource; const ExtraResources: string): TPdfBitmap;
begin
  FDocument := FDocuments.OpenWithPatterns(PageContent, Patterns, ExtraResources);

  const Renderer: IPdfRenderer = TPdfRenderer.Create(FDocument, CreateBackend);
  Assert.AreEqual(TPdfRenderStatus.Completed, Renderer.RenderToBitmap(0, TPdfRenderParams.Create(1), Result));
end;

// The page row of a point is PageSize - Y: the pixel that is tested is the one just under the point
procedure TRenderTilingTestsBase.AssertPixel(const Bitmap: TPdfBitmap; const X, Y: Integer; const Expected: TPdfDeviceColor);
begin
  const Actual = Bitmap.GetPixel(X, PageSize - Y);
  Assert.AreEqual(Double(Expected.R), Double(Actual.R), Tolerance, Format('R at (%d, %d)', [X, Y]));
  Assert.AreEqual(Double(Expected.G), Double(Actual.G), Tolerance, Format('G at (%d, %d)', [X, Y]));
  Assert.AreEqual(Double(Expected.B), Double(Actual.B), Tolerance, Format('B at (%d, %d)', [X, Y]));
end;

procedure TRenderTilingTestsBase.TestColoredTilingRepeatsCell;
begin
  const Bitmap = Render('/Pattern cs /P1 scn 0 0 100 100 re f', [TTilingSource.Square(1, '10', RedDot)]);
  try
    AssertPixel(Bitmap, 5, 5, Red);
    AssertPixel(Bitmap, 15, 5, Red);
    AssertPixel(Bitmap, 55, 75, Red);
    AssertPixel(Bitmap, 95, 95, Red);
    AssertPixel(Bitmap, 1, 1, TPdfDeviceColor.White);
    AssertPixel(Bitmap, 8, 12, TPdfDeviceColor.White);
    AssertPixel(Bitmap, 150, 150, TPdfDeviceColor.White);
  finally
    Bitmap.Free;
  end;
end;

procedure TRenderTilingTestsBase.TestUncoloredPatternUsesFillColor;
begin
  const Bitmap = Render('/CsU cs 1 0 0 /P1 scn 0 0 100 100 re f 0 0 1 /P1 scn 100 100 100 100 re f',
                        [TTilingSource.Square(2, '10', '3 3 4 4 re f')], UncoloredSpace);
  try
    AssertPixel(Bitmap, 5, 5, Red);
    AssertPixel(Bitmap, 45, 45, Red);
    AssertPixel(Bitmap, 105, 105, TPdfDeviceColor.Create(0, 0, 255));
    AssertPixel(Bitmap, 1, 1, TPdfDeviceColor.White);
  finally
    Bitmap.Free;
  end;
end;

// The matrix moves the cell by 3 points: the dot that was on 3 to 7 is on 6 to 10, and the pixel at 4 is empty
procedure TRenderTilingTestsBase.TestPatternMatrixIsApplied;
begin
  const Bitmap = Render('/Pattern cs /P1 scn 0 0 100 100 re f',
                        [TTilingSource.Create('/PaintType 1 /TilingType 1 /BBox [0 0 10 10] /XStep 10 /YStep 10 /Matrix [1 0 0 1 3 0] /Resources << >>', RedDot)]);
  try
    AssertPixel(Bitmap, 8, 5, Red);
    AssertPixel(Bitmap, 18, 5, Red);
    AssertPixel(Bitmap, 4, 5, TPdfDeviceColor.White);
    AssertPixel(Bitmap, 14, 5, TPdfDeviceColor.White);
  finally
    Bitmap.Free;
  end;
end;

// PDFBox makes the cell as large as the step, so what lies beyond the step in the box is not in the cell
procedure TRenderTilingTestsBase.TestStepSmallerThanCellOverlaps;
begin
  const Bitmap = Render('/Pattern cs /P1 scn 0 0 100 100 re f',
                        [TTilingSource.Create('/PaintType 1 /TilingType 2 /BBox [0 0 20 20] /XStep 10 /YStep 10 /Resources << >>',
                                              '1 0 0 rg 0 0 20 20 re f 0 0 1 rg 15 15 5 5 re f')]);
  try
    AssertPixel(Bitmap, 5, 5, Red);
    AssertPixel(Bitmap, 17, 17, Red);
    AssertPixel(Bitmap, 95, 95, Red);
  finally
    Bitmap.Free;
  end;
end;

procedure TRenderTilingTestsBase.TestStepLargerThanCellLeavesGaps;
begin
  const Bitmap = Render('/Pattern cs /P1 scn 0 0 100 100 re f',
                        [TTilingSource.Create('/PaintType 1 /TilingType 3 /BBox [0 0 10 10] /XStep 25 /YStep 25 /Resources << >>', '1 0 0 rg 0 0 10 10 re f')]);
  try
    AssertPixel(Bitmap, 5, 5, Red);
    AssertPixel(Bitmap, 30, 5, Red);
    AssertPixel(Bitmap, 15, 5, TPdfDeviceColor.White);
    AssertPixel(Bitmap, 15, 15, TPdfDeviceColor.White);
  finally
    Bitmap.Free;
  end;
end;

procedure TRenderTilingTestsBase.TestPatternAsStrokeColor;
begin
  const Bitmap = Render('/Pattern CS /P1 SCN 20 w 10 50 m 190 50 l S', [TTilingSource.Square(1, '10', '1 0 0 rg 0 0 10 10 re f')]);
  try
    AssertPixel(Bitmap, 100, 50, Red);
    AssertPixel(Bitmap, 100, 70, TPdfDeviceColor.White);
  finally
    Bitmap.Free;
  end;
end;

end.
