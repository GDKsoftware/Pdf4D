// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.Robustness.Tests;

interface

uses
  System.SysUtils,
  System.IOUtils,
  DUnitX.TestFramework,
  Pdf4D.Tests.Corpus,
  Pdf4D.Tests.Fuzz;

type
  [TestFixture]
  TRobustnessTests = class
  strict private
    class function GlyphTableMutation(const Font: TBytes; const Offset, Size, Index: Integer): TBytes; static;
    class procedure RunMutatedInput(const Campaign: TFuzzCampaign; const What: string; const Source: TBytes; const Work: TFuzzWork;
                                    const Seed: Integer); static;

  public
    // Every mutation runs on a worker thread with a time limit and with the strict dump: success or an EPdfException, never another
    // exception and never a hang
    [Test]
    procedure TestMutatedCorpusFailsCleanlyInTime;
    [Test]
    procedure TestAllCorpusFilesLoadWithoutLeak;
    // The decoders of the images, the colour profiles, the functions and the outlines are given mutations of valid input: success or
    // an EPdfException, never another exception and never a hang
    [Test]
    procedure TestMutatedDecoderInputs;
    // The mutated corpus (the seeds of the first test) goes through a viewer session: tiles at scale 0.5, the text and a hit test of every
    // page and one search. A document that does not open or a render that fails is fine; an exception that is not a PDF exception, a
    // hang or a leak is not.
    [Test]
    procedure TestMutatedCorpusInViewer;
    // A document of 1000 pages is scrolled through and zoomed: the tile cache, the thumbnail cache and the cache of page texts stay
    // within their maximum
    [Test]
    procedure TestCachesStayWithinBudget;
  end;

implementation

uses
  System.Math,
  System.Types,
  System.UITypes,
  System.Generics.Collections,
  Pdf4D.Model.Rectangle,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.Session,
  Pdf4D.Viewer.PageViewController,
  Pdf4D.Viewer.ThumbnailsController,
  Pdf4D.Viewer.PageText,
  Pdf4D.Viewer.Painter.Interfaces,
  Pdf4D.Tests.TestFonts,
  Pdf4D.Tests.TestDocument,
  Pdf4D.Tests.FakeSession,
  Pdf4D.Tests.RecordingPainter,
  Pdf4D.Tests.ViewerFuzz;

const
  DecoderSeed = 9753;
  MutationsPerInput = 300;
  GlyphTableWindow = 16384;
  LiberationSansFile = 'LiberationSans-Regular.ttf';
  GlyphTableTag = 'glyf';
  KindNames: array[TMutationKind] of string = ('overwrite', 'truncate', 'duplicate', 'object-header');
  BudgetPageCount = 1000;
  BudgetScrollSteps = 150;
  BudgetViewportWidth = 832;
  BudgetViewportHeight = 600;
  BudgetPixelsPerInch = 96;
  OneMebibyte = 1024 * 1024;
  // Small, so that the caches have to evict
  BudgetTileCacheBytes = 4 * OneMebibyte;
  BudgetThumbnailCacheBytes = OneMebibyte;
  BudgetPageTextCacheCount = 20;
  BudgetPageScrollPixels = 700;
  BudgetThumbnailScrollPixels = 200;
  BudgetZoomSteps = 3;

{ TRobustnessTests }

procedure TRobustnessTests.TestMutatedCorpusFailsCleanlyInTime;
begin
  TFuzzCampaign.RunMutatedCorpus(TFuzzWork.Structure);
end;

procedure TRobustnessTests.TestAllCorpusFilesLoadWithoutLeak;
begin
  const Files = TCorpus.Files;
  if Length(Files) = 0 then
  begin
    Assert.Fail('The corpus was not found: set PDF4D_CORPUS or run the test program below the tests folder');
  end;

  for var FileName in Files do
  begin
    const Run = TMutationRun.Create(TFile.ReadAllBytes(TCorpus.PdfPath(FileName)), TCorpus.PasswordFor(FileName));
    try
      const Outcome = Run.RunHere;
      // Files that PDFBox cannot open either end in a PDF exception
      if (Outcome.Failure <> '') and not Outcome.IsPdfException then
      begin
        Assert.Fail(Format('%s: %s', [FileName, Outcome.Failure]));
      end;
    finally
      Run.Free;
    end;
  end;
end;

// Half of the mutations only touch the first bytes of the table, the glyphs that every run looks at
class function TRobustnessTests.GlyphTableMutation(const Font: TBytes; const Offset, Size, Index: Integer): TBytes;
begin
  const Kind = TMutationKind(Index mod (Ord(High(TMutationKind)) + 1));
  const Table = Copy(Font, Offset, Size);
  var Mutated: TBytes;
  const HeadOnly = ((Index div 4) mod 2 = 0) and (Kind <> TMutationKind.Truncate) and (Size > GlyphTableWindow);
  if HeadOnly then
  begin
    Mutated := TMutator.Mutate(Copy(Table, 0, GlyphTableWindow), Kind) + Copy(Table, GlyphTableWindow, Size - GlyphTableWindow);
  end
  else
  begin
    Mutated := TMutator.Mutate(Table, Kind);
  end;
  Result := Copy(Font, 0, Offset) + Mutated + Copy(Font, Offset + Size, Length(Font) - Offset - Size);
end;

class procedure TRobustnessTests.RunMutatedInput(const Campaign: TFuzzCampaign; const What: string; const Source: TBytes;
                                                 const Work: TFuzzWork; const Seed: Integer);
begin
  const FullSeed = Seed + TFuzzSettings.SeedOffset;
  RandSeed := FullSeed;
  for var Index := 0 to TFuzzSettings.Scale(MutationsPerInput) - 1 do
  begin
    const Kind = TMutationKind(Index mod (Ord(High(TMutationKind)) + 1));
    Campaign.Run(Format('%s seed %d mutation %d (%s)', [What, FullSeed, Index, KindNames[Kind]]), TMutator.Mutate(Source, Kind), '', Work);
  end;
end;

procedure TRobustnessTests.TestMutatedDecoderInputs;
begin
  const Campaign = TFuzzCampaign.Create;
  try
    RunMutatedInput(Campaign, 'jpeg.jpg', TDecoderInputs.Jpeg('pdfbox-jpeg.jpg'), TFuzzWork.JpegDecoder, DecoderSeed);
    RunMutatedInput(Campaign, 'jpegcmyk.jpg', TDecoderInputs.Jpeg('pdfbox-jpegcmyk.jpg'), TFuzzWork.JpegDecoder, DecoderSeed + 1);
    RunMutatedInput(Campaign, 'ccittg4.tif', TDecoderInputs.CcittData, TFuzzWork.CcittDecoder, DecoderSeed + 2);
    RunMutatedInput(Campaign, 'CMYK profile', TDecoderInputs.CmykProfile, TFuzzWork.IccProfile, DecoderSeed + 3);
    RunMutatedInput(Campaign, 'type 4 function', TDecoderInputs.PostScriptProgram, TFuzzWork.PostScriptFunction, DecoderSeed + 4);
    RunMutatedInput(Campaign, 'Type 1 charstring', TDecoderInputs.Type1CharString, TFuzzWork.Type1CharString, DecoderSeed + 5);
    RunMutatedInput(Campaign, 'CFF charstring', TDecoderInputs.CffCharString, TFuzzWork.CffCharString, DecoderSeed + 6);

    const Font = TTestFonts.Bytes(LiberationSansFile);
    var Offset, Size: Integer;
    Assert.IsTrue(TDecoderInputs.TryFindTable(Font, GlyphTableTag, Offset, Size), 'LiberationSans has a glyf table');
    const FullSeed = DecoderSeed + 7 + TFuzzSettings.SeedOffset;
    RandSeed := FullSeed;
    for var Index := 0 to TFuzzSettings.Scale(MutationsPerInput) - 1 do
    begin
      const Kind = TMutationKind(Index mod (Ord(High(TMutationKind)) + 1));
      Campaign.Run(Format('glyf table seed %d mutation %d (%s)', [FullSeed, Index, KindNames[Kind]]),
                   GlyphTableMutation(Font, Offset, Size, Index), '', TFuzzWork.GlyphOutlines);
    end;
    Campaign.AssertNoFailures;
  finally
    Campaign.Free;
  end;
end;

procedure TRobustnessTests.TestMutatedCorpusInViewer;
begin
  TFuzzViewing.Probe :=
    procedure(const Bytes: TBytes; const Password: string)
    begin
      TViewerFuzzProbe.Run(Bytes, Password);
    end;
  try
    TFuzzCampaign.RunMutatedCorpus(TFuzzWork.Viewer);
  finally
    TFuzzViewing.Probe := nil;
  end;
end;

procedure TRobustnessTests.TestCachesStayWithinBudget;
begin
  const Fake = TFakeViewerSession.Create;
  const Session: IPdfViewerSession = Fake;
  const Document = TTestDocument.Create(nil);
  const PageViewHost: IPdfViewHost = TRecordingHost.Create;
  const ThumbnailsHost: IPdfViewHost = TRecordingHost.Create;
  var View: TPdfPageViewController := nil;
  var Thumbnails: TPdfThumbnailsController := nil;
  try
    var Page: TPdfPageInfo;
    Page.CropBox := TPdfRectangle.Letter;
    Page.Rotation := 0;
    Page.Label_ := '';
    var Pages: TArray<TPdfPageInfo>;
    SetLength(Pages, BudgetPageCount);
    for var Index := 0 to High(Pages) do
    begin
      Pages[Index] := Page;
    end;
    var Permissions: TPdfViewerPermissions;
    Permissions.CanPrint := True;
    Permissions.CanCopy := True;
    Fake.SetOpened(Pages, nil, Permissions);
    Document.PageTextCacheCount := BudgetPageTextCacheCount;
    Document.OpenWithSession(Session);

    View := TPdfPageViewController.Create(PageViewHost);
    View.TileCacheBytes := BudgetTileCacheBytes;
    View.Document := Document;
    View.SetViewport(TSize.Create(BudgetViewportWidth, BudgetViewportHeight), BudgetPixelsPerInch);
    Thumbnails := TPdfThumbnailsController.Create(ThumbnailsHost);
    Thumbnails.CacheBytes := BudgetThumbnailCacheBytes;
    Thumbnails.Document := Document;
    Thumbnails.SetViewport(TSize.Create(BudgetViewportWidth div 4, BudgetViewportHeight), BudgetPixelsPerInch);

    for var Step := 1 to BudgetScrollSteps + BudgetZoomSteps do
    begin
      if Step <= BudgetScrollSteps then
      begin
        View.ScrollBy(0, BudgetPageScrollPixels);
        Thumbnails.ScrollBy(0, BudgetThumbnailScrollPixels);
      end
      else
      begin
        View.ZoomIn;
      end;
      Document.RequestPageText(Document.CurrentPage, TPdfJobPriority.Visible, nil);
      Fake.CompleteOutstanding(TAlphaColors.White);

      Assert.IsTrue(View.TileCacheCost <= BudgetTileCacheBytes, Format('The tile cache holds %d bytes at step %d', [View.TileCacheCost, Step]));
      Assert.IsTrue(Thumbnails.CacheCost <= BudgetThumbnailCacheBytes, Format('The thumbnail cache holds %d bytes at step %d', [Thumbnails.CacheCost, Step]));
    end;

    var CachedTexts := 0;
    for var PageIndex := 0 to BudgetPageCount - 1 do
    begin
      var PageText: IPdfPageText;
      if Document.TryGetPageText(PageIndex, PageText) then
      begin
        Inc(CachedTexts);
      end;
    end;
    Assert.IsTrue(CachedTexts > 0, 'the page texts were cached');
    Assert.IsTrue(CachedTexts <= BudgetPageTextCacheCount, Format('%d page texts are cached', [CachedTexts]));
    Assert.IsTrue(View.TileCacheCost > 0, 'the tiles were cached');
    Assert.IsTrue(Thumbnails.CacheCost > 0, 'the thumbnails were cached');
  finally
    Thumbnails.Free;
    View.Free;
    Document.Free;
  end;
end;

end.
