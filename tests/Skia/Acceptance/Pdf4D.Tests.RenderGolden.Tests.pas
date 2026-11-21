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
  // A line of selection.txt: a corpus file and one of its pages
  TSelectedPage = record
    RelativePath: string;
    Page: Integer;
  end;

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
    class function HistogramText(const Counts: array of Int64): string; static;
    class function OutputName(const RelativePath: string; const Page: Integer; const Dpi: Integer): string; static;
    class procedure LogComparison(const RelativePath: string; const Page: Integer; const Dpi: Integer; const Comparison: TRenderComparison); static;
    class function CropOf(const Source: TPdfBitmap; const Region: TRect): TPdfBitmap; static;
    class procedure LogRegion(const RelativePath: string; const Page: Integer; const Region, Crop: TPdfBitmap; const Compared: Int64); static;
    class procedure SaveRegionOutput(const RelativePath: string; const Page: Integer; const Region, Full: TPdfBitmap); static;
    class procedure SaveOutput(const RelativePath: string; const Page: Integer; const Dpi: Integer; const Actual, Expected: TPdfBitmap); static;
    class function Differences(const RelativePath: string; const IsPending: Boolean; const Document: IPdfDocument; const Dpi: Integer; const ListedPages: TArray<Integer>): TArray<string>; static;
    class function KnownDifferencesPath(const RelativePath: string; const Dpi: Integer): string; static;
    class function SelectedPages(const SelectionPath: string): TArray<TSelectedPage>; static;
    class function FileDifference(const RelativePath: string; const Dpi: Integer; const Pages: TArray<Integer>): TArray<string>; static;
    class function PageLineCount(const RenderListing: string): Integer; static;
    class function HasNoReference(const RenderListing: string): Boolean; static;
    class function PageDifference(const RelativePath: string; const Document: IPdfDocument; const Page: Integer; const Dpi: Integer; const Expected: TPdfBitmap): string; static;

  public
    [Setup]
    procedure SetUp;

    [TearDown]
    procedure TearDown;

    [Test]
    [TestCaseProvider('Pdf4DRenderCorpus')]
    procedure TestCorpus72Dpi(const RelativePath: string);

    // The files that PDFBox could not render are the ones in no-reference.txt, no more and no fewer, so that a truncated or timed-out
    // listing cannot make a file pass unseen
    [Test]
    procedure TestFilesWithoutReferenceAreListed;

    // The pages of tests/reference/render/150/selection.txt (fine details: thin lines, small text, patterns, the invoices), rendered at
    // 150 DPI, must equal the render of PDFBox under the same rules. The selection, the listings and the images must agree: a missing
    // reference, a missing listing or an image without a selection line fails.
    [Test]
    procedure TestSelection150Dpi;

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
  System.Math,
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
  FilterEnvironmentVariable = 'PDF4D_RENDER_FILTER';
  SaveAllEnvironmentVariable = 'PDF4D_RENDER_SAVE_ALL';
  ReferenceDpi = 72;
  SelectionDpi = 150;
  SelectionFileName = 'selection.txt';
  PngExtension = '.png';
  MaxReportedDifferences = 10;
  // tools/oracle/generate-render.ps1 renders pages 1 to min(pages, 50) of a file
  MaxRenderedPages = 50;
  PageMarker = 'page ';
  OkMarker = ' ok';
  RegionLeft = 37;
  RegionTop = 53;
  RegionRight = 237;
  RegionBottom = 253;
  // A region is rendered on a device of its own, with the page moved by a whole number of pixels, so it should be the crop of the full
  // page. Two things of Skia (not of the renderer; checked on the pixels) make it differ:
  // 1. along the border of the device, the coverage of a path or a glyph that the border cuts is another one (up to 60 levels in the
  //    last three pixels), so the pixels along the border are left out;
  // 2. Skia works in single precision, and where a sample lies exactly on the boundary of two texels of an image that is drawn with
  //    the nearest neighbour (generated/render/images.pdf puts 4 x 4 images on whole points at 50 points: every 12.5 points a pixel
  //    centre is on a boundary), the rounding of the matrix decides which texel it takes, and the matrix has other rounding errors
  //    on another translation. That moves whole columns of pixels (1.2% of the region); no other file has it.
  // What is left is held to a tolerance of 8 and 0.06% of the pixels, and nothing else. Measured on the five regions (PDF4D_RENDER_OUTPUT
  // gets region.txt), pixels that differ by more than 8: paths.pdf 19 of 36864 (0.052%), clip.pdf 3, text-modes.pdf 0, survey.pdf 0 and
  // images.pdf 455 (1.23%, the nearest tie). At 4 paths.pdf has 25 (0.068%) and over 0.06%.
  RegionTolerance = 8;
  RegionBorder = 4;
  MaxRegionDifferentFraction = 0.0006;
  MaxRegionNearestTieFraction = 0.0135;
  NearestTieFile = 'generated/render/images.pdf';
  BytesPerPixel = 4;

{ TRenderCorpusCaseProvider }

constructor TRenderCorpusCaseProvider.Create;
begin
  // PDF4D_RENDER_FILTER (substrings of corpus paths, separated by semicolons) limits the run to the matching files, for looking at one
  // difference without the whole corpus
  const Filter = GetEnvironmentVariable(FilterEnvironmentVariable);
  if Filter = '' then
  begin
    FFiles := TCorpus.Files;
    Exit;
  end;

  FFiles := nil;
  for var RelativePath in TCorpus.Files do
  begin
    for var Part in Filter.Split([';']) do
    begin
      if (Part <> '') and RelativePath.Contains(Part) then
      begin
        FFiles := FFiles + [RelativePath];
        Break;
      end;
    end;
  end;
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

class function TRenderGoldenTests.OutputName(const RelativePath: string; const Page: Integer; const Dpi: Integer): string;
begin
  Result := Format('%s.p%.3d', [TCorpus.GoldenName(RelativePath), Page]);
  if Dpi <> ReferenceDpi then
  begin
    Result := Result + Format('.%ddpi', [Dpi]);
  end;
end;

// The values of a histogram that have pixels, as value:count separated by spaces
class function TRenderGoldenTests.HistogramText(const Counts: array of Int64): string;
begin
  Result := '';
  for var Value := 0 to High(Counts) do
  begin
    if Counts[Value] > 0 then
    begin
      Result := Result + Format('%d:%d ', [Value, Counts[Value]]);
    end;
  end;
  Result := Result.Trim;
end;

// With PDF4D_RENDER_OUTPUT set, summary.txt in that folder gets one line per compared page: file, page, share of different pixels, largest
// difference, whether the sizes are equal, share of the flat pixels that differ, share of the edge pixels that differ;
// distribution.txt has the flat pixels and the histogram of their differences, and the same for the edge pixels, for tuning the tolerances
class procedure TRenderGoldenTests.LogComparison(const RelativePath: string; const Page: Integer; const Dpi: Integer; const Comparison: TRenderComparison);
begin
  const Folder = GetEnvironmentVariable(OutputEnvironmentVariable);
  if Folder <> '' then
  begin
    TDirectory.CreateDirectory(Folder);
    TFile.AppendAllText(TPath.Combine(Folder, 'summary.txt'), Format('%s;%d;%.5f;%d;%s;%.5f;%.5f%s', [IfThen(Dpi = ReferenceDpi, RelativePath, Format('%s@%d', [RelativePath, Dpi])), Page, Comparison.DifferentFraction, Comparison.MaxDifference,
                                                                                               BoolToStr(Comparison.HasSameSize, True), Comparison.DifferentFlatFraction, Comparison.DifferentEdgeFraction, sLineBreak]));
    TFile.AppendAllText(TPath.Combine(Folder, 'distribution.txt'), Format('%s;%d;%d;%s;%d;%s%s', [IfThen(Dpi = ReferenceDpi, RelativePath, Format('%s@%d', [RelativePath, Dpi])), Page, Comparison.FlatPixels,
                                                                                                    HistogramText(Comparison.FlatDifferences), Comparison.EdgePixels, HistogramText(Comparison.EdgeDifferences), sLineBreak]));
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

// With PDF4D_RENDER_OUTPUT set, region.txt gets the share of the pixels of the region that differ from the crop for a range of tolerances
class procedure TRenderGoldenTests.LogRegion(const RelativePath: string; const Page: Integer; const Region, Crop: TPdfBitmap; const Compared: Int64);
begin
  const Folder = GetEnvironmentVariable(OutputEnvironmentVariable);
  if Folder = '' then
  begin
    Exit;
  end;

  var Line := Format('%s;%d;%d', [RelativePath, Page, Compared]);
  for var Tolerance in [0, 1, 2, 4, 8, 16, 32] do
  begin
    Line := Line + Format(';%d:%d', [Tolerance, TRenderCompare.CountAbove(Region, Crop, Tolerance, RegionBorder)]);
  end;
  TDirectory.CreateDirectory(Folder);
  TFile.AppendAllText(TPath.Combine(Folder, 'region.txt'), Line + sLineBreak);
end;

class procedure TRenderGoldenTests.SaveRegionOutput(const RelativePath: string; const Page: Integer; const Region, Full: TPdfBitmap);
begin
  const Folder = GetEnvironmentVariable(OutputEnvironmentVariable);
  if Folder <> '' then
  begin
    TDirectory.CreateDirectory(Folder);
    TPng.Write(Region, TPath.Combine(Folder, OutputName(RelativePath, Page, ReferenceDpi) + '.region.png'));
    TPng.Write(Full, TPath.Combine(Folder, OutputName(RelativePath, Page, ReferenceDpi) + '.full.png'));
  end;
end;

// For looking at a difference: the render and an image of the differences go to the folder in PDF4D_RENDER_OUTPUT
class procedure TRenderGoldenTests.SaveOutput(const RelativePath: string; const Page: Integer; const Dpi: Integer; const Actual, Expected: TPdfBitmap);
begin
  const Folder = GetEnvironmentVariable(OutputEnvironmentVariable);
  if Folder = '' then
  begin
    Exit;
  end;

  TDirectory.CreateDirectory(Folder);
  const Name = OutputName(RelativePath, Page, Dpi);
  TPng.Write(Actual, TPath.Combine(Folder, Name + '.png'));
  TRenderCompare.WriteDifference(Actual, Expected, TPath.Combine(Folder, Name + '.diff.png'));
end;

// Empty when the page equals its reference, otherwise what differs
class function TRenderGoldenTests.PageDifference(const RelativePath: string; const Document: IPdfDocument; const Page: Integer; const Dpi: Integer; const Expected: TPdfBitmap): string;
begin
  var Actual: TPdfBitmap := nil;
  try
    const Renderer: IPdfRenderer = TPdfRenderer.Create(Document, TReferenceBackends.Create);
    Renderer.RenderToBitmap(Page - 1, TPdfRenderParams.FromDpi(Dpi), Actual);

    const Comparison = TRenderCompare.Compare(Actual, Expected);
    LogComparison(RelativePath, Page, Dpi, Comparison);
    if Comparison.IsEqual then
    begin
      // PDF4D_RENDER_SAVE_ALL=1 also writes the pages that are equal, for looking at the largest differences within the limits
      if GetEnvironmentVariable(SaveAllEnvironmentVariable) <> '' then
      begin
        SaveOutput(RelativePath, Page, Dpi, Actual, Expected);
      end;
      Exit('');
    end;

    SaveOutput(RelativePath, Page, Dpi, Actual, Expected);
    Result := Format('page %d: %s', [Page, Comparison.Describe]);
  finally
    Actual.Free;
  end;
end;

// The known differences of the 72 DPI renders are in <name>.render-known-differences.txt, those of another DPI in
// <name>.render-<dpi>dpi-known-differences.txt: a page that is only different at 150 DPI must not hide its 72 DPI comparison
class function TRenderGoldenTests.KnownDifferencesPath(const RelativePath: string; const Dpi: Integer): string;
begin
  if Dpi = ReferenceDpi then
  begin
    Result := TCorpus.GoldenName(RelativePath) + '.render-known-differences.txt';
  end
  else
  begin
    Result := Format('%s.render-%ddpi-known-differences.txt', [TCorpus.GoldenName(RelativePath), Dpi]);
  end;
  Result := TPath.Combine(RenderFolder, Result);
end;

// The reference of a listed page must be there and be a PNG, also for a file that is pending: nothing is compared without it, and
// that is a failure, not a difference. An exception of the render is a difference of a file that is not pending; in a pending file
// only a feature that is not supported yet (the one that made it pending) may raise, anything else fails the test.
class function TRenderGoldenTests.Differences(const RelativePath: string; const IsPending: Boolean; const Document: IPdfDocument; const Dpi: Integer;
                                               const ListedPages: TArray<Integer>): TArray<string>;
begin
  Result := nil;
  const Known = TTextGoldenComparer.LoadKnownDifferences(KnownDifferencesPath(RelativePath, Dpi));
  for var Page in ListedPages do
  begin
    if TRenderCompare.IsKnownDifference(Known, Page, TTextGoldenComparer.CurrentPlatform) then
    begin
      Continue;
    end;

    const PngPath = TPath.Combine(ReferenceFolder(Dpi), Format('%s.p%.3d', [TCorpus.GoldenName(RelativePath), Page]) + PngExtension);
    Assert.IsTrue(TFile.Exists(PngPath), Format('%s page %d: the reference image %s is missing', [RelativePath, Page, PngPath]));
    const Expected = TPng.Read(PngPath);
    try
      var Difference: string;
      try
        Difference := PageDifference(RelativePath, Document, Page, Dpi, Expected);
      except
        on Failure: Exception do
        begin
          if IsPending and (not (Failure is EPdfUnsupportedFeatureException)) then
          begin
            raise;
          end;
          Difference := Format('page %d: %s: %s', [Page, Failure.ClassName, Failure.Message]);
        end;
      end;

      if Difference <> '' then
      begin
        Result := Result + [Difference];
      end;
    finally
      Expected.Free;
    end;
  end;
end;

// The lines "page <n> ..." of a listing, whatever they say about the page
class function TRenderGoldenTests.PageLineCount(const RenderListing: string): Integer;
begin
  Result := 0;
  for var Line in RenderListing.Split([#10]) do
  begin
    if Line.Trim.StartsWith(PageMarker) then
    begin
      Inc(Result);
    end;
  end;
end;

class function TRenderGoldenTests.HasNoReference(const RenderListing: string): Boolean;
begin
  Result := (Length(ListedPages(RenderListing)) = 0);
end;

procedure TRenderGoldenTests.TestCorpus72Dpi(const RelativePath: string);
begin
  if RelativePath = '' then
  begin
    Assert.Fail('The corpus was not found: set PDF4D_CORPUS or run the test program below the tests folder');
  end;

  const ListingPath = TPath.Combine(ReferenceFolder(ReferenceDpi), TCorpus.GoldenName(RelativePath) + '.render.txt');
  Assert.IsTrue(TFile.Exists(ListingPath), Format('%s: the render listing %s is missing', [RelativePath, ListingPath]));
  const Listing = TFile.ReadAllText(ListingPath, TEncoding.UTF8);
  Assert.IsTrue(Listing.Trim <> '', Format('%s: the render listing is empty', [RelativePath]));
  const Pages = ListedPages(Listing);
  if Length(Pages) = 0 then
  begin
    // PDFBox cannot render the file (TestFilesWithoutReferenceAreListed pins which files); the robustness tests cover that Pdf4D does
    // not crash on it
    Exit;
  end;

  var Options := TPdfLoadOptions.Default;
  Options.Password := TCorpus.PasswordFor(RelativePath);
  const Document: IPdfDocument = TPdfDocument.Load(TCorpus.PdfPath(RelativePath), Options);

  // PDFBox renders the first 50 pages, and the listing has a line for each of them; a shorter one is cut off
  Assert.AreEqual<Integer>(Min(Document.PageCount, MaxRenderedPages), PageLineCount(Listing), Format('%s: the render listing has another number of pages than the file', [RelativePath]));

  const IsPending = MatchStr(RelativePath, TRenderCompare.PendingFiles(TPath.Combine(RenderFolder, 'pending.txt')));
  const Found = Differences(RelativePath, IsPending, Document, ReferenceDpi, Pages);
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

// The lines "<corpus file>;<page>" of selection.txt; # starts a comment
class function TRenderGoldenTests.SelectedPages(const SelectionPath: string): TArray<TSelectedPage>;
begin
  Result := nil;
  for var Line in TFile.ReadAllLines(SelectionPath, TEncoding.UTF8) do
  begin
    const Trimmed = Line.Trim;
    if (Trimmed = '') or Trimmed.StartsWith('#') then
    begin
      Continue;
    end;

    const Columns = Trimmed.Split([';']);
    Assert.AreEqual<Integer>(2, Length(Columns), Format('selection.txt: the line "%s" is not "<corpus file>;<page>"', [Trimmed]));
    var Item: TSelectedPage;
    Item.RelativePath := Columns[0].Trim;
    Item.Page := StrToInt(Columns[1].Trim);
    Result := Result + [Item];
  end;
end;

// The differences of the selected pages of one file at the given DPI: empty when every page equals its reference or is a known difference
class function TRenderGoldenTests.FileDifference(const RelativePath: string; const Dpi: Integer; const Pages: TArray<Integer>): TArray<string>;
begin
  const ListingPath = TPath.Combine(ReferenceFolder(Dpi), TCorpus.GoldenName(RelativePath) + '.render.txt');
  Assert.IsTrue(TFile.Exists(ListingPath), Format('%s: the render listing %s is missing', [RelativePath, ListingPath]));
  const Listed = ListedPages(TFile.ReadAllText(ListingPath, TEncoding.UTF8));
  for var Page in Pages do
  begin
    var IsListed := False;
    for var ListedPage in Listed do
    begin
      IsListed := IsListed or (ListedPage = Page);
    end;
    Assert.IsTrue(IsListed, Format('%s: page %d is not rendered in the %d DPI listing', [RelativePath, Page, Dpi]));
  end;

  var Options := TPdfLoadOptions.Default;
  Options.Password := TCorpus.PasswordFor(RelativePath);
  const Document: IPdfDocument = TPdfDocument.Load(TCorpus.PdfPath(RelativePath), Options);
  const IsPending = MatchStr(RelativePath, TRenderCompare.PendingFiles(TPath.Combine(RenderFolder, 'pending.txt')));
  const Found = Differences(RelativePath, IsPending, Document, Dpi, Pages);
  const Verdict = TRenderCompare.Judge(IsPending, Found);
  Result := nil;
  if Verdict.IsFailure then
  begin
    Result := Found;
    if Length(Result) = 0 then
    begin
      Result := [Verdict.Message];
    end;
  end;
end;

procedure TRenderGoldenTests.TestSelection150Dpi;
begin
  Assert.IsTrue(Length(TCorpus.Files) > 0, 'The corpus was not found: set PDF4D_CORPUS or run the test program below the tests folder');

  const SelectionPath = TPath.Combine(ReferenceFolder(SelectionDpi), SelectionFileName);
  Assert.IsTrue(TFile.Exists(SelectionPath), Format('%s is missing', [SelectionPath]));
  const Selected = SelectedPages(SelectionPath);
  Assert.IsTrue(Length(Selected) > 0, 'selection.txt selects no page');

  // Every reference image of the folder belongs to a selection line
  var Expected: TArray<string> := nil;
  for var Item in Selected do
  begin
    Assert.IsTrue(MatchStr(Item.RelativePath, TCorpus.Files), Format('selection.txt: %s is not in the corpus', [Item.RelativePath]));
    Expected := Expected + [Format('%s.p%.3d%s', [TCorpus.GoldenName(Item.RelativePath), Item.Page, PngExtension])];
  end;
  var Orphans: TArray<string> := nil;
  for var ImagePath in TDirectory.GetFiles(ReferenceFolder(SelectionDpi), '*' + PngExtension) do
  begin
    if not MatchStr(TPath.GetFileName(ImagePath), Expected) then
    begin
      Orphans := Orphans + [TPath.GetFileName(ImagePath)];
    end;
  end;
  Assert.AreEqual<Integer>(0, Length(Orphans), Format('Reference images without a line in selection.txt: %s', [string.Join(', ', Orphans)]));

  var Failures: TArray<string> := nil;
  var Done: TArray<string> := nil;
  for var Item in Selected do
  begin
    if MatchStr(Item.RelativePath, Done) then
    begin
      Continue;
    end;
    Done := Done + [Item.RelativePath];

    var Pages: TArray<Integer> := nil;
    for var Other in Selected do
    begin
      if Other.RelativePath = Item.RelativePath then
      begin
        Pages := Pages + [Other.Page];
      end;
    end;
    for var Difference in FileDifference(Item.RelativePath, SelectionDpi, Pages) do
    begin
      Failures := Failures + [Format('%s: %s', [Item.RelativePath, Difference])];
    end;
  end;

  if Length(Failures) > 0 then
  begin
    const Reported = Copy(Failures, 0, MaxReportedDifferences);
    Assert.Fail(Format('%d selected pages differ from PDFBox at %d DPI, the first %d:%s%s', [Length(Failures), SelectionDpi, Length(Reported), sLineBreak, string.Join(sLineBreak, Reported)]));
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
    const Compared = Int64(Region.Width - 2 * RegionBorder) * (Region.Height - 2 * RegionBorder);
    const Different = TRenderCompare.CountAbove(Region, Crop, RegionTolerance, RegionBorder);
    LogRegion(RelativePath, Page, Region, Crop, Compared);
    var Allowed := MaxRegionDifferentFraction;
    if RelativePath = NearestTieFile then
    begin
      Allowed := MaxRegionNearestTieFraction;
    end;
    if Different > Allowed * Compared then
    begin
      SaveRegionOutput(RelativePath, Page, Region, Full);
    end;
    Assert.IsTrue(Different <= Allowed * Compared, Format('%s page %d: %d of %d pixels of the region differ from the crop by more than %d', [RelativePath, Page, Different, Compared, RegionTolerance]));
  finally
    Crop.Free;
    Region.Free;
    Full.Free;
  end;
end;

procedure TRenderGoldenTests.TestFilesWithoutReferenceAreListed;
begin
  Assert.IsTrue(Length(TCorpus.Files) > 0, 'The corpus was not found: set PDF4D_CORPUS or run the test program below the tests folder');

  const ListedPath = TPath.Combine(RenderFolder, 'no-reference.txt');
  Assert.IsTrue(TFile.Exists(ListedPath), 'tests/reference/render/no-reference.txt is missing');
  const Listed = TRenderCompare.PendingFiles(ListedPath);

  var Found: TArray<string> := nil;
  for var RelativePath in TCorpus.Files do
  begin
    const ListingPath = TPath.Combine(ReferenceFolder(ReferenceDpi), TCorpus.GoldenName(RelativePath) + '.render.txt');
    Assert.IsTrue(TFile.Exists(ListingPath), Format('%s: the render listing %s is missing', [RelativePath, ListingPath]));
    const Listing = TFile.ReadAllText(ListingPath, TEncoding.UTF8);
    Assert.IsTrue(Listing.Trim <> '', Format('%s: the render listing is empty', [RelativePath]));
    if HasNoReference(Listing) then
    begin
      Found := Found + [RelativePath];
    end;
  end;

  var Unexpected: TArray<string> := nil;
  for var RelativePath in Found do
  begin
    if not MatchStr(RelativePath, Listed) then
    begin
      Unexpected := Unexpected + [RelativePath];
    end;
  end;
  var Missing: TArray<string> := nil;
  for var RelativePath in Listed do
  begin
    if not MatchStr(RelativePath, Found) then
    begin
      Missing := Missing + [RelativePath];
    end;
  end;

  Assert.AreEqual<Integer>(0, Length(Unexpected) + Length(Missing),
                           Format('The files without a reference differ from no-reference.txt. Not in the list: %s. In the list, but with a reference: %s',
                                  [string.Join(', ', Unexpected), string.Join(', ', Missing)]));
end;

end.
