// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Determinism and speed of the native backend: the same page renders to the same bytes, the pixels of every page of the generated render
// files and the invoices equal tests/reference/render/native-hashes.txt, and the first page of an invoice renders within a fraction of a
// second.
unit Pdf4D.Tests.RenderPerformance.Native.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Font.Mapper,
  Pdf4D.Render.Bitmap,
  DUnitX.TestFramework;

type
  // The SHA-256 of the pixels of every page at 72 DPI. A line is "<corpus file> page <n> <sha256>". A line that starts with [Linux64] is
  // the hash for Linux64 alone, with the reason after the hash (a difference that comes from the transcendental functions of the platform).
  [TestFixture]
  TNativeRenderDeterminismTests = class
  strict private
    // One mapper for all runs: a mapper that has been replaced stays in memory until the process ends
    class var FHermeticMapper: IPdfFontMapper;

    class function HashFilePath: string; static;
    class function IsHashedFile(const RelativePath: string): Boolean; static;
    class function HashOf(const Bitmap: TPdfBitmap): string; static;
    class function RenderPage(const RelativePath: string; const Document: IPdfDocument; const Page: Integer): TPdfBitmap; static;

  public
    [Setup]
    procedure SetUp;

    [TearDown]
    procedure TearDown;

    [Test]
    [TestCase('Paths', 'generated/render/paths.pdf')]
    [TestCase('Clip', 'generated/render/clip.pdf')]
    [TestCase('TextModes', 'generated/render/text-modes.pdf')]
    [TestCase('Transparency', 'generated/render/transparency.pdf')]
    [TestCase('Shadings', 'generated/render/shadings.pdf')]
    procedure TestRenderTwiceIsByteIdentical(const RelativePath: string);

    // On Win64 and Linux64 the hashes are those of the file; on Win32 (x87) a difference is reported and does not fail. With
    // PDF4D_NATIVE_HASHES_WRITE=1 on Win64 the test writes the file instead of reading it.
    [Test]
    procedure TestNativeHashesMatch;
  end;

  // Spec section 8: a page renders "within a fraction of a second". The first page of every generated invoice is rendered at 96 DPI (scale
  // 4/3) with the native backend, five times, and the median must stay under the threshold. Only a Release build on Win64 is measured:
  // elsewhere the test passes without measuring.
  [TestFixture]
  TRenderPerformanceNativeTests = class
  strict private
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
    procedure TestInvoiceFirstPage;

    [Test]
    procedure TestMedianTakesTheMiddleValue;
  end;

implementation

uses
  System.Classes,
  System.Diagnostics,
  System.Generics.Collections,
  System.Hash,
  System.IOUtils,
  System.Math,
  DUnitX.Types,
  Pdf4D.Api.Document,
  Pdf4D.Common.Defines,
  Pdf4D.Font.MapperImpl,
  Pdf4D.Render.Native.Backend,
  Pdf4D.Render.Renderer,
  Pdf4D.Render.Renderer.Interfaces,
  Pdf4D.Tests.Corpus,
  Pdf4D.Tests.FontProvider;

const
  RenderFolder = 'generated/render/';
  InvoiceFolder = 'generated/invoices/';
  HashesFileName = 'native-hashes.txt';
  WriteEnvironmentVariable = 'PDF4D_NATIVE_HASHES_WRITE';
  OutputEnvironmentVariable = 'PDF4D_RENDER_OUTPUT';
  HashDpi = 72;
  PageMarker = ' page ';
  LinuxMarker = '[Linux64] ';
  MaxHashedPages = 50;
  RunsPerInvoice = 5;
  // 96 DPI is the scale 4 / 3 of the 72 points of an inch
  ViewerScale: Single = 4 / 3;
  MaxMedianMilliseconds = 150;
  {$IFDEF DEBUG}
  IsMeasured = False;
  {$ELSEIF Defined(WIN64)}
  IsMeasured = True;
  {$ELSE}
  IsMeasured = False;
  {$ENDIF}
  {$IFDEF WIN64}
  IsWin64 = True;
  {$ELSE}
  IsWin64 = False;
  {$ENDIF}
  {$IFDEF LINUX64}
  IsLinux64 = True;
  {$ELSE}
  IsLinux64 = False;
  {$ENDIF}

{ TNativeRenderDeterminismTests }

procedure TNativeRenderDeterminismTests.SetUp;
begin
  // The same fonts as the reference renders: embedded fonts, the standard 14 and the built-in LiberationSans
  if not Assigned(FHermeticMapper) then
  begin
    FHermeticMapper := TFontMapperImpl.Create(TTestFontProvider.Empty);
  end;
  TPdfFontMappers.SetInstance(FHermeticMapper);
end;

procedure TNativeRenderDeterminismTests.TearDown;
begin
  TPdfFontMappers.SetInstance(nil);
end;

class function TNativeRenderDeterminismTests.HashFilePath: string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.Combine(TPath.GetDirectoryName(TCorpus.Folder), 'reference'), 'render'), HashesFileName);
end;

class function TNativeRenderDeterminismTests.IsHashedFile(const RelativePath: string): Boolean;
begin
  Result := RelativePath.StartsWith(InvoiceFolder) or (RelativePath.StartsWith(RenderFolder) and RelativePath.EndsWith('.pdf'));
end;

class function TNativeRenderDeterminismTests.HashOf(const Bitmap: TPdfBitmap): string;
begin
  const Hash = THashSHA2.Create(THashSHA2.TSHA2Version.SHA256);
  Hash.Update(Bitmap.Pixels);
  Result := Hash.HashAsString;
end;

class function TNativeRenderDeterminismTests.RenderPage(const RelativePath: string; const Document: IPdfDocument; const Page: Integer): TPdfBitmap;
begin
  Result := nil;
  const Renderer: IPdfRenderer = TPdfRenderer.Create(Document, TPdfNativeBackend.Create);
  Renderer.RenderToBitmap(Page, TPdfRenderParams.FromDpi(HashDpi), Result);
end;

procedure TNativeRenderDeterminismTests.TestRenderTwiceIsByteIdentical(const RelativePath: string);
begin
  var Options := TPdfLoadOptions.Default;
  Options.Password := TCorpus.PasswordFor(RelativePath);
  const Document: IPdfDocument = TPdfDocument.Load(TCorpus.PdfPath(RelativePath), Options);

  var First: TPdfBitmap := nil;
  var Other: TPdfBitmap := nil;
  var Again: TPdfBitmap := nil;
  try
    First := RenderPage(RelativePath, Document, 0);
    // Another page in between, so that no state of the first render can be what the third one reuses
    if Document.PageCount > 1 then
    begin
      Other := RenderPage(RelativePath, Document, 1);
    end
    else
    begin
      Other := RenderPage(RelativePath, Document, 0);
    end;
    Again := RenderPage(RelativePath, Document, 0);

    Assert.AreEqual<Integer>(Length(First.Pixels), Length(Again.Pixels), RelativePath + ': the renders have the same size');
    Assert.IsTrue(CompareMem(@First.Pixels[0], @Again.Pixels[0], Length(First.Pixels)), RelativePath + ': the second render of page 1 differs from the first');
  finally
    Again.Free;
    Other.Free;
    First.Free;
  end;
end;

procedure TNativeRenderDeterminismTests.TestNativeHashesMatch;
begin
  const Folder = TCorpus.Folder;
  Assert.IsTrue(Folder <> '', 'The corpus was not found: set PDF4D_CORPUS or run the test program below the tests folder');

  const Writing = (GetEnvironmentVariable(WriteEnvironmentVariable) <> '') and IsWin64;
  var Expected := TDictionary<string, string>.Create;
  var ExpectedLinux := TDictionary<string, string>.Create;
  var Written := TStringList.Create;
  var Timings := TStringList.Create;
  try
    if not Writing then
    begin
      Assert.IsTrue(TFile.Exists(HashFilePath), 'Missing ' + HashFilePath);
      for var Line in TFile.ReadAllLines(HashFilePath, TEncoding.UTF8) do
      begin
        if (Line = '') or Line.StartsWith('#') then
        begin
          Continue;
        end;

        var Text := Line;
        var Target := Expected;
        if Text.StartsWith(LinuxMarker) then
        begin
          Text := Copy(Text, Length(LinuxMarker) + 1);
          Target := ExpectedLinux;
        end;
        const PageAt = Pos(PageMarker, Text);
        Assert.IsTrue(PageAt > 1, 'Malformed line: ' + Line);
        const Parts = Copy(Text, PageAt + Length(PageMarker)).Split([' ']);
        Assert.IsTrue(Length(Parts) >= 2, 'Malformed line: ' + Line);
        Target.AddOrSetValue(Copy(Text, 1, PageAt - 1) + PageMarker + Parts[0], Parts[1]);
      end;
    end;

    var Differences: TArray<string> := nil;
    var Seen := 0;
    for var RelativePath in TCorpus.Files do
    begin
      if not IsHashedFile(RelativePath) then
      begin
        Continue;
      end;

      var Options := TPdfLoadOptions.Default;
      Options.Password := TCorpus.PasswordFor(RelativePath);
      const Document: IPdfDocument = TPdfDocument.Load(TCorpus.PdfPath(RelativePath), Options);
      for var Page := 0 to Min(Document.PageCount, MaxHashedPages) - 1 do
      begin
        const Key = RelativePath + PageMarker + IntToStr(Page + 1);
        const Watch = TStopwatch.StartNew;
        const Bitmap = RenderPage(RelativePath, Document, Page);
        Timings.Add(Format('%8.1f ms %s', [Watch.Elapsed.TotalMilliseconds, Key]));
        try
          const Actual = HashOf(Bitmap);
          Inc(Seen);
          if Writing then
          begin
            Written.Add(Key + ' ' + Actual);
            Continue;
          end;

          var Want: string;
          if IsLinux64 and ExpectedLinux.TryGetValue(Key, Want) then
          begin
            // the own hash of the platform
          end
          else if not Expected.TryGetValue(Key, Want) then
          begin
            Differences := Differences + [Key + ': no hash in ' + HashesFileName];
            Continue;
          end;
          if Want <> Actual then
          begin
            Differences := Differences + [Format('%s: %s, expected %s', [Key, Actual, Want])];
          end;
        finally
          Bitmap.Free;
        end;
      end;
    end;

    if Timings.Count >= 3 then
    begin
      Timings.Sort;
      TDUnitX.CurrentRunner.Log(TLogLevel.Information, 'Slowest pages at 72 DPI: ' + Timings[Timings.Count - 1] + '; ' + Timings[Timings.Count - 2] + '; ' + Timings[Timings.Count - 3]);
      // With PDF4D_RENDER_OUTPUT set the time of every page also goes to native-page-times.txt in that folder
      const OutputFolder = GetEnvironmentVariable(OutputEnvironmentVariable);
      if OutputFolder <> '' then
      begin
        TDirectory.CreateDirectory(OutputFolder);
        Timings.SaveToFile(TPath.Combine(OutputFolder, 'native-page-times.txt'));
      end;
    end;

    if Writing then
    begin
      TFile.WriteAllBytes(HashFilePath, TEncoding.UTF8.GetBytes(string.Join(#10, Written.ToStringArray) + #10));
      Assert.IsTrue(Seen > 0, 'No page was hashed');
      Exit;
    end;

    Assert.IsTrue(Seen > 0, 'No page was hashed');
    if Length(Differences) > 0 then
    begin
      const Report = Format('%d of %d pages differ from %s: %s', [Length(Differences), Seen, HashesFileName, string.Join('; ', Copy(Differences, 0, 10))]);
      if IsWin64 or IsLinux64 then
      begin
        Assert.Fail(Report);
      end
      else
      begin
        TDUnitX.CurrentRunner.Log(TLogLevel.Warning, 'Not Win64 or Linux64, reported only: ' + Report);
      end;
    end;
  finally
    Timings.Free;
    Written.Free;
    ExpectedLinux.Free;
    Expected.Free;
  end;
end;

{ TRenderPerformanceNativeTests }

procedure TRenderPerformanceNativeTests.SetUp;
begin
  if not Assigned(FHermeticMapper) then
  begin
    FHermeticMapper := TFontMapperImpl.Create(TTestFontProvider.Empty);
  end;
  TPdfFontMappers.SetInstance(FHermeticMapper);
end;

procedure TRenderPerformanceNativeTests.TearDown;
begin
  TPdfFontMappers.SetInstance(nil);
end;

class function TRenderPerformanceNativeTests.InvoiceFiles: TArray<string>;
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

class function TRenderPerformanceNativeTests.MedianMilliseconds(const Timings: TArray<Double>): Double;
begin
  var Sorted := Copy(Timings);
  TArray.Sort<Double>(Sorted);
  Result := Sorted[Length(Sorted) div 2];
end;

// The milliseconds of each run; the document is loaded once, and the first page is rendered each time
class function TRenderPerformanceNativeTests.RenderTimings(const RelativePath: string): TArray<Double>;
begin
  var Options := TPdfLoadOptions.Default;
  Options.Password := TCorpus.PasswordFor(RelativePath);
  const Document: IPdfDocument = TPdfDocument.Load(TCorpus.PdfPath(RelativePath), Options);
  const Renderer: IPdfRenderer = TPdfRenderer.Create(Document, TPdfNativeBackend.Create);

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

procedure TRenderPerformanceNativeTests.TestMedianTakesTheMiddleValue;
begin
  Assert.AreEqual(Double(30), MedianMilliseconds([50, 10, 30, 90, 20]));
  Assert.AreEqual(Double(7), MedianMilliseconds([7]));
end;

procedure TRenderPerformanceNativeTests.TestInvoiceFirstPage;
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
  TDUnitX.CurrentRunner.Log(TLogLevel.Information, 'Native median render time of the first page at 96 DPI: ' + Report);
  const Folder = GetEnvironmentVariable(OutputEnvironmentVariable);
  if Folder <> '' then
  begin
    TDirectory.CreateDirectory(Folder);
    TFile.AppendAllText(TPath.Combine(Folder, 'performance-native.txt'), Report + sLineBreak);
  end;

  Assert.AreEqual<Integer>(0, Length(TooSlow), Format('The median is over %d ms for: %s', [MaxMedianMilliseconds, string.Join(', ', TooSlow)]));
end;

end.
