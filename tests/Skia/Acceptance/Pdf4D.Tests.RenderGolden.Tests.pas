// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.RenderGolden.Tests;

{$EXCESSPRECISION OFF}
{$POINTERMATH ON}

interface

uses
  System.SysUtils,
  System.Rtti,
  System.Types,
  DUnitX.Types,
  DUnitX.InternalDataProvider,
  DUnitX.TestDataProvider,
  DUnitX.TestFramework,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Font.Mapper,
  Pdf4D.Render.Bitmap,
  Pdf4D.Tests.RenderCompare;

type
  TRenderCorpusCaseProvider = class(TTestDataProvider)
  strict private
    FFiles: TArray<string>;

  public
    constructor Create; override;

    function GetCaseCount(const MethodName: string): Integer; override;
    function GetCaseName(const MethodName: string; const CaseNumber: Integer): string; override;
    function GetCaseParams(const MethodName: string; const CaseNumber: Integer): TValueArray; override;
  end;

  // Every page of the corpus, rendered at 72 DPI, must equal the render of PDFBox 3.0.8 (tests/reference/render/72) under the
  // rules of docs/golden-format.md ("Render reference files")
  [TestFixture]
  TRenderGoldenTests = class
  strict private
    // One mapper for all runs: a mapper that has been replaced stays in memory until the process ends
    class var FHermeticMapper: IPdfFontMapper;

    class function RenderFolder: string; static;
    class function ReferenceFolder(const Dpi: Integer): string; static;
    class function ListedPages(const RenderListing: string): TArray<Integer>; static;
    class function OutputName(const RelativePath: string; const Page: Integer): string; static;
    class procedure LogComparison(const RelativePath: string; const Page: Integer; const Comparison: TRenderComparison); static;
    class function CropOf(const Source: TPdfBitmap; const Region: TRect): TPdfBitmap; static;
    class procedure SaveRegionOutput(const RelativePath: string; const Page: Integer; const Region, Full: TPdfBitmap); static;
    class procedure SaveOutput(const RelativePath: string; const Page: Integer; const Actual, Expected: TPdfBitmap); static;
    class function Differences(const RelativePath: string; const Document: IPdfDocument; const ListedPages: TArray<Integer>): TArray<string>; static;
    class function PageDifference(const RelativePath: string; const Document: IPdfDocument; const Page: Integer): string; static;

  public
    [Setup]
    procedure SetUp;

    [TearDown]
    procedure TearDown;

    [Test]
    [TestCaseProvider('Pdf4DRenderCorpus')]
    procedure TestCorpus72Dpi(const RelativePath: string);

    // The viewer renders regions of a page; a region must equal the same crop of the whole page
    [Test]
    [TestCase('Paths', 'generated/render/paths.pdf,1')]
    [TestCase('Clip', 'generated/render/clip.pdf,1')]
    [TestCase('TextModes', 'generated/render/text-modes.pdf,1')]
    [TestCase('Images', 'generated/render/images.pdf,1')]
    [TestCase('Survey', 'pdfbox/input/rendering/survey.pdf,1')]
    procedure TestRegionEqualsCropOfFullPage(const RelativePath: string; const Page: Integer);

    class constructor Create;

  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  Pdf4D.Api.Document,
  Pdf4D.Common.Defines,
  Pdf4D.Font.MapperImpl,
  Pdf4D.Render.Renderer,
  Pdf4D.Render.Renderer.Interfaces,
  Pdf4D.Tests.Corpus,
  Pdf4D.Tests.FontProvider,
  Pdf4D.Tests.Png,
  Pdf4D.Tests.ReferenceBackends,
  Pdf4D.Tests.TextGolden;

const
  ProviderName = 'Pdf4DRenderCorpus';
  OutputEnvironmentVariable = 'PDF4D_RENDER_OUTPUT';
  ReferenceDpi = 72;
  MaxReportedDifferences = 10;
  PageMarker = 'page ';
  OkMarker = ' ok';
  RegionLeft = 37;
  RegionTop = 53;
  RegionRight = 237;
  RegionBottom = 253;
  // Skia puts the pixels on an exact sample boundary and the edge of a path at the border of the device on either side, depending on
  // where the device starts, so a region is equal to the crop of the page up to those few pixels
  MaxRegionDifferentFraction = 0.02;
  BytesPerPixel = 4;

{ TRenderCorpusCaseProvider }

constructor TRenderCorpusCaseProvider.Create;
begin
  FFiles := TCorpus.Files;
end;

function TRenderCorpusCaseProvider.GetCaseCount(const MethodName: string): Integer;
begin
  // Without a corpus there is one case that reports it
  Result := Length(FFiles);
  if Result = 0 then
  begin
    Result := 1;
  end;
end;

function TRenderCorpusCaseProvider.GetCaseName(const MethodName: string; const CaseNumber: Integer): string;
begin
  if Length(FFiles) = 0 then
  begin
    Result := 'NoCorpus';
  end
  else
  begin
    Result := FFiles[CaseNumber];
  end;
end;

function TRenderCorpusCaseProvider.GetCaseParams(const MethodName: string; const CaseNumber: Integer): TValueArray;
begin
  SetLength(Result, 1);
  if Length(FFiles) = 0 then
  begin
    Result[0] := '';
  end
  else
  begin
    Result[0] := FFiles[CaseNumber];
  end;
end;

{ TRenderGoldenTests }

class constructor TRenderGoldenTests.Create;
begin
  TestDataProviderManager.RegisterProvider(ProviderName, TRenderCorpusCaseProvider);
end;

procedure TRenderGoldenTests.SetUp;
begin
  // The reference renders use no font of the machine: embedded fonts, the standard 14 and the built-in LiberationSans
  if not Assigned(FHermeticMapper) then
  begin
    FHermeticMapper := TFontMapperImpl.Create(TTestFontProvider.Empty);
  end;
  TPdfFontMappers.SetInstance(FHermeticMapper);
end;

procedure TRenderGoldenTests.TearDown;
begin
  TPdfFontMappers.SetInstance(nil);
end;

class function TRenderGoldenTests.RenderFolder: string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.GetDirectoryName(TCorpus.Folder), 'reference'), 'render');
end;

class function TRenderGoldenTests.ReferenceFolder(const Dpi: Integer): string;
begin
  Result := TPath.Combine(RenderFolder, IntToStr(Dpi));
end;

// The pages that PDFBox rendered: the lines "page <n> <width> <height> ok"
class function TRenderGoldenTests.ListedPages(const RenderListing: string): TArray<Integer>;
begin
  Result := nil;
  for var Line in RenderListing.Split([#10]) do
  begin
    const Trimmed = Line.Trim;
    if Trimmed.StartsWith(PageMarker) and Trimmed.EndsWith(OkMarker) then
    begin
      const Number = Trimmed.Substring(PageMarker.Length).Split([' '])[0];
      Result := Result + [StrToInt(Number)];
    end;
  end;
end;

class function TRenderGoldenTests.OutputName(const RelativePath: string; const Page: Integer): string;
begin
  Result := Format('%s.p%.3d', [TCorpus.GoldenName(RelativePath), Page]);
end;

// With PDF4D_RENDER_OUTPUT set, summary.txt in that folder gets one line per compared page: file, page, share of different pixels, largest difference
class procedure TRenderGoldenTests.LogComparison(const RelativePath: string; const Page: Integer; const Comparison: TRenderComparison);
begin
  const Folder = GetEnvironmentVariable(OutputEnvironmentVariable);
  if Folder <> '' then
  begin
    TDirectory.CreateDirectory(Folder);
    TFile.AppendAllText(TPath.Combine(Folder, 'summary.txt'), Format('%s;%d;%.5f;%d;%s%s', [RelativePath, Page, Comparison.DifferentFraction, Comparison.MaxDifference,
                                                                                               BoolToStr(Comparison.HasSameSize, True), sLineBreak]));
  end;
end;

class function TRenderGoldenTests.CropOf(const Source: TPdfBitmap; const Region: TRect): TPdfBitmap;
begin
  Result := TPdfBitmap.Create(Region.Width, Region.Height);
  for var Y := 0 to Region.Height - 1 do
  begin
    Move((Source.ScanLine(Y + Region.Top) + Region.Left * BytesPerPixel)^, Result.ScanLine(Y)^, Region.Width * BytesPerPixel);
  end;
end;

class procedure TRenderGoldenTests.SaveRegionOutput(const RelativePath: string; const Page: Integer; const Region, Full: TPdfBitmap);
begin
  const Folder = GetEnvironmentVariable(OutputEnvironmentVariable);
  if Folder <> '' then
  begin
    TDirectory.CreateDirectory(Folder);
    TPng.Write(Region, TPath.Combine(Folder, OutputName(RelativePath, Page) + '.region.png'));
    TPng.Write(Full, TPath.Combine(Folder, OutputName(RelativePath, Page) + '.full.png'));
  end;
end;

// For looking at a difference: the render and an image of the differences go to the folder in PDF4D_RENDER_OUTPUT
class procedure TRenderGoldenTests.SaveOutput(const RelativePath: string; const Page: Integer; const Actual, Expected: TPdfBitmap);
begin
  const Folder = GetEnvironmentVariable(OutputEnvironmentVariable);
  if Folder = '' then
  begin
    Exit;
  end;

  TDirectory.CreateDirectory(Folder);
  const Name = OutputName(RelativePath, Page);
  TPng.Write(Actual, TPath.Combine(Folder, Name + '.png'));
  TRenderCompare.WriteDifference(Actual, Expected, TPath.Combine(Folder, Name + '.diff.png'));
end;

// Empty when the page equals its reference, otherwise what differs
class function TRenderGoldenTests.PageDifference(const RelativePath: string; const Document: IPdfDocument; const Page: Integer): string;
begin
  const Expected = TPng.Read(TPath.Combine(ReferenceFolder(ReferenceDpi), OutputName(RelativePath, Page) + '.png'));
  try
    var Actual: TPdfBitmap := nil;
    try
      const Renderer: IPdfRenderer = TPdfRenderer.Create(Document, TReferenceBackends.Create);
      Renderer.RenderToBitmap(Page - 1, TPdfRenderParams.FromDpi(ReferenceDpi), Actual);

      const Comparison = TRenderCompare.Compare(Actual, Expected);
      LogComparison(RelativePath, Page, Comparison);
      if Comparison.IsEqual then
      begin
        Exit('');
      end;

      SaveOutput(RelativePath, Page, Actual, Expected);
      Result := Format('page %d: %s', [Page, Comparison.Describe]);
    finally
      Actual.Free;
    end;
  finally
    Expected.Free;
  end;
end;

class function TRenderGoldenTests.Differences(const RelativePath: string; const Document: IPdfDocument; const ListedPages: TArray<Integer>): TArray<string>;
begin
  Result := nil;
  const Known = TTextGoldenComparer.LoadKnownDifferences(TPath.Combine(RenderFolder, TCorpus.GoldenName(RelativePath) + '.render-known-differences.txt'));
  for var Page in ListedPages do
  begin
    if TRenderCompare.IsKnownDifference(Known, Page, TTextGoldenComparer.CurrentPlatform) then
    begin
      Continue;
    end;

    var Difference: string;
    try
      Difference := PageDifference(RelativePath, Document, Page);
    except
      on Failure: Exception do
      begin
        Difference := Format('page %d: %s: %s', [Page, Failure.ClassName, Failure.Message]);
      end;
    end;

    if Difference <> '' then
    begin
      Result := Result + [Difference];
    end;
  end;
end;

procedure TRenderGoldenTests.TestCorpus72Dpi(const RelativePath: string);
begin
  if RelativePath = '' then
  begin
    Assert.Fail('The corpus was not found: set PDF4D_CORPUS or run the test program below the tests folder');
  end;

  const Listing = TFile.ReadAllText(TPath.Combine(ReferenceFolder(ReferenceDpi), TCorpus.GoldenName(RelativePath) + '.render.txt'), TEncoding.UTF8);
  const Pages = ListedPages(Listing);
  if Length(Pages) = 0 then
  begin
    // PDFBox cannot render the file; the robustness tests cover that Pdf4D does not crash on it
    Exit;
  end;

  var Options := TPdfLoadOptions.Default;
  Options.Password := TCorpus.PasswordFor(RelativePath);
  const Document: IPdfDocument = TPdfDocument.Load(TCorpus.PdfPath(RelativePath), Options);

  const IsPending = MatchStr(RelativePath, TRenderCompare.PendingFiles(TPath.Combine(RenderFolder, 'pending.txt')));
  const Found = Differences(RelativePath, Document, Pages);
  const Verdict = TRenderCompare.Judge(IsPending, Found);
  if IsPending and (Length(Found) > 0) then
  begin
    TDUnitX.CurrentRunner.Log(TLogLevel.Information, Format('pending %s: %s', [RelativePath, Found[0]]));
  end;
  if Verdict.IsFailure then
  begin
    const Reported = Copy(Found, 0, MaxReportedDifferences);
    Assert.Fail(Format('%s: %d pages differ from PDFBox, the first %d:%s%s%s',
                       [RelativePath, Length(Found), Length(Reported), sLineBreak, string.Join(sLineBreak, Reported), Verdict.Message]));
  end;
end;

procedure TRenderGoldenTests.TestRegionEqualsCropOfFullPage(const RelativePath: string; const Page: Integer);
begin
  var Options := TPdfLoadOptions.Default;
  Options.Password := TCorpus.PasswordFor(RelativePath);
  const Document: IPdfDocument = TPdfDocument.Load(TCorpus.PdfPath(RelativePath), Options);
  const Renderer: IPdfRenderer = TPdfRenderer.Create(Document, TReferenceBackends.Create);

  var Full: TPdfBitmap := nil;
  var Region: TPdfBitmap := nil;
  var Crop: TPdfBitmap := nil;
  try
    Renderer.RenderToBitmap(Page - 1, TPdfRenderParams.FromDpi(ReferenceDpi), Full);
    var Params := TPdfRenderParams.FromDpi(ReferenceDpi);
    Params.Region := TRect.Create(RegionLeft, RegionTop, RegionRight, RegionBottom);
    Renderer.RenderToBitmap(Page - 1, Params, Region);

    Assert.AreEqual<Integer>(RegionRight - RegionLeft, Region.Width);
    Assert.AreEqual<Integer>(RegionBottom - RegionTop, Region.Height);
    Crop := CropOf(Full, Params.Region);
    const Comparison = TRenderCompare.Compare(Region, Crop);
    if not Comparison.IsEqual then
    begin
      SaveRegionOutput(RelativePath, Page, Region, Full);
    end;
    Assert.IsTrue(Comparison.DifferentFraction <= MaxRegionDifferentFraction, Format('%s page %d: the region differs from the crop, %s', [RelativePath, Page, Comparison.Describe]));
  finally
    Crop.Free;
    Region.Free;
    Full.Free;
  end;
end;

end.
