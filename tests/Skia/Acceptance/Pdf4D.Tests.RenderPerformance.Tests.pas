// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.RenderPerformance.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.Types,
  DUnitX.TestFramework,
  Pdf4D.Font.Mapper;

type
  // Spec section 8: a page renders "within a fraction of a second". The first page of every generated invoice is rendered at 96 DPI
  // (scale 4/3) with Skia, five times, and the median must stay under the threshold. Only a Release build on Win64 is measured: a
  // Debug build (the Debug configuration defines DEBUG) is several times slower and Win32 and Linux64 are not the platform that the
  // figure is for. Elsewhere the test passes without measuring: DUnitX has no way to ignore a test at run time.
  [TestFixture]
  TRenderPerformanceTests = class
  strict private
    // The mapper that the fixture found, put back by TearDown (the test program installs its own for all fixtures)
    FFoundMapper: IPdfFontMapper;
    // One mapper for all runs: a mapper that has been replaced stays in memory until the process ends
    class var FHermeticMapper: IPdfFontMapper;

    class function InvoiceFiles: TArray<string>; static;
    class function MedianMilliseconds(const Timings: TArray<Double>): Double; static;
    class function RenderTimings(const RelativePath: string): TArray<Double>; static;

  public
    [Setup]
    procedure SetUp;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestInvoicesRenderWithinTheThreshold;

    [Test]
    procedure TestMedianTakesTheMiddleValue;
  end;

implementation

uses
  System.Diagnostics,
  System.Generics.Collections,
  System.IOUtils,
  Pdf4D.Api.Document,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Common.Defines,
  Pdf4D.Font.MapperImpl,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Renderer,
  Pdf4D.Render.Renderer.Interfaces,
  Pdf4D.Tests.Corpus,
  Pdf4D.Tests.FontProvider,
  Pdf4D.Tests.ReferenceBackends;

const
  InvoiceFolder = 'generated/invoices/';
  OutputEnvironmentVariable = 'PDF4D_RENDER_OUTPUT';
  RunsPerInvoice = 5;
  // 96 DPI is the scale 4 / 3 of the 72 points of an inch
  ViewerScale: Single = 4 / 3;
  // Measured on the invoices of the corpus in a Release build on Win64: the medians are 10 to
  // 33 ms. The threshold is three times the slowest, so a slower machine or a busy build server passes, and it still catches a renderer
  // that has become an order of magnitude slower.
  MaxMedianMilliseconds = 100;
  {$IFDEF DEBUG}
  IsMeasured = False;
  {$ELSEIF Defined(WIN64)}
  IsMeasured = True;
  {$ELSE}
  IsMeasured = False;
  {$ENDIF}

{ TRenderPerformanceTests }

procedure TRenderPerformanceTests.SetUp;
begin
  // The same fonts as the reference renders: embedded fonts, the standard 14 and the built-in LiberationSans
  if not Assigned(FHermeticMapper) then
  begin
    FHermeticMapper := TFontMapperImpl.Create(TTestFontProvider.Empty);
  end;
  FFoundMapper := TPdfFontMappers.Instance;
  TPdfFontMappers.SetInstance(FHermeticMapper);
end;

procedure TRenderPerformanceTests.TearDown;
begin
  TPdfFontMappers.SetInstance(FFoundMapper);
  FFoundMapper := nil;
end;

class function TRenderPerformanceTests.InvoiceFiles: TArray<string>;
begin
  Result := nil;
  for var RelativePath in TCorpus.Files do
  begin
    if RelativePath.StartsWith(InvoiceFolder) then
    begin
      Result := Result + [RelativePath];
    end;
  end;
end;

class function TRenderPerformanceTests.MedianMilliseconds(const Timings: TArray<Double>): Double;
begin
  var Sorted := Copy(Timings);
  TArray.Sort<Double>(Sorted);
  Result := Sorted[Length(Sorted) div 2];
end;

// The milliseconds of each run; the document is loaded once, and the first page is rendered each time
class function TRenderPerformanceTests.RenderTimings(const RelativePath: string): TArray<Double>;
begin
  var Options := TPdfLoadOptions.Default;
  Options.Password := TCorpus.PasswordFor(RelativePath);
  const Document: IPdfDocument = TPdfDocument.Load(TCorpus.PdfPath(RelativePath), Options);
  const Renderer: IPdfRenderer = TPdfRenderer.Create(Document, TReferenceBackends.Create);

  SetLength(Result, RunsPerInvoice);
  for var Run := 0 to RunsPerInvoice - 1 do
  begin
    var Bitmap: TPdfBitmap := nil;
    try
      const Watch = TStopwatch.StartNew;
      Renderer.RenderToBitmap(0, TPdfRenderParams.Create(ViewerScale), Bitmap);
      Result[Run] := Watch.Elapsed.TotalMilliseconds;
    finally
      Bitmap.Free;
    end;
  end;
end;

procedure TRenderPerformanceTests.TestMedianTakesTheMiddleValue;
begin
  Assert.AreEqual(Double(30), MedianMilliseconds([50, 10, 30, 90, 20]));
  Assert.AreEqual(Double(7), MedianMilliseconds([7]));
end;

procedure TRenderPerformanceTests.TestInvoicesRenderWithinTheThreshold;
begin
  if not IsMeasured then
  begin
    Assert.Pass('Measured in a Release build on Win64 only');
  end;

  const Invoices = InvoiceFiles;
  Assert.IsTrue(Length(Invoices) > 0, 'The invoices were not found: set PDF4D_CORPUS or run the test program below the tests folder');

  var TooSlow: TArray<string> := nil;
  var Report := '';
  for var RelativePath in Invoices do
  begin
    const Median = MedianMilliseconds(RenderTimings(RelativePath));
    Report := Report + Format('%s %.1f ms; ', [TPath.GetFileName(RelativePath), Median]);
    if Median > MaxMedianMilliseconds then
    begin
      TooSlow := TooSlow + [Format('%s: %.1f ms', [RelativePath, Median])];
    end;
  end;
  TDUnitX.CurrentRunner.Log(TLogLevel.Information, 'Median render time of the first page at 96 DPI: ' + Report);
  // With PDF4D_RENDER_OUTPUT set the medians also go to performance.txt in that folder
  const Folder = GetEnvironmentVariable(OutputEnvironmentVariable);
  if Folder <> '' then
  begin
    TDirectory.CreateDirectory(Folder);
    TFile.AppendAllText(TPath.Combine(Folder, 'performance.txt'), Report + sLineBreak);
  end;

  Assert.AreEqual<Integer>(0, Length(TooSlow), Format('The median is over %d ms for: %s', [MaxMedianMilliseconds, string.Join(', ', TooSlow)]));
end;

end.
