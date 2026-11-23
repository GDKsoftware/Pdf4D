// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.VclPerformance.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.SysUtils,
  System.Types,
  DUnitX.TestFramework,
  Pdf4D.Api.TextLayout.Interfaces,
  Pdf4D.Viewer.Types,
  Pdf4D.Tests.VclHost;

type
  // What a person feels: the first page of an invoice, the hover, the scroll. The limits are in milliseconds, measured with the Skia
  // backend in a Release build; the measurements are written to the output of the run. In a Debug build the tests are skipped, because
  // the unoptimised code says nothing about what a user gets.
  [TestFixture]
  TVclPerformanceTests = class
  private
    FHost: TVclTestHost;
    FHoverCount: Integer;

    procedure HandleHoverChanged(Sender: TObject; const HasSegment: Boolean; const Segment: TPdfTextFragment);
    class function IsMeasured: Boolean; static;
    // To the output of the run and to the file pdf4d-vcl-performance.txt in the temporary folder, where the console of the test run does
    // not show it
    class procedure Note(const Line: string); static;
    class function Median(const Values: TArray<Double>): Double; static;
    class function MillisecondsOf(const Ticks: Int64): Double; static;
    function TilesArrived: Boolean;
    // From Open to the tiles of the visible part of the first page, in milliseconds; the document is closed afterwards
    function MeasureFirstPage(const Data: TBytes): Double;
    function InvoiceFolder: string;
    // The centers (client pixels) of the distinct words of the first page, at most Count
    function WordCenters(const Count: Integer): TArray<TPoint>;

  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestFirstInvoicePageIsQuick;
    [Test]
    procedure TestHoverIsImmediate;
    [Test]
    procedure TestScrollStaysResponsive;
    // The tiles are DIB sections: the GDI objects of the process stay within a budget while a long document is scrolled through
    [Test]
    procedure TestGdiObjectsStayWithinBudget;
  end;

implementation

uses
  System.Diagnostics,
  System.Generics.Collections,
  System.IOUtils,
  System.Math,
  Winapi.Messages,
  Winapi.Windows,
  Pdf4D.Viewer.PageText,
  Pdf4D.Tests.Corpus,
  Pdf4D.Tests.ViewerDocuments;

const
  ViewportWidth = 1000;
  ViewportHeight = 800;
  InvoiceFolderName = 'generated/invoices';
  FirstPageRuns = 5;
  // Started at 500; about four times the slowest median that was measured (50 ms), see docs/assumptions.md
  FirstPageLimitMs = 200;
  HoverMoves = 200;
  HoverLimitMs = 5;
  RepaintRuns = 20;
  RepaintLimitMs = 16;
  HoverWords = 20;
  ScrollPages = 200;
  ScrollMessages = 20;
  ScrollLimitMs = 16;
  PageWidth = 612;
  PageHeight = 792;
  GdiScrollSteps = 60;
  // 128 MiB of tiles of 256 KiB are 512 DIB sections; the rest is the window and the fonts
  GdiBudget = 1000;
  WaitMs = 20000;
  PumpAfterMessageMs = 20;

{ TVclPerformanceTests }

procedure TVclPerformanceTests.Setup;
begin
  FHoverCount := 0;
  FHost := TVclTestHost.Create(ViewportWidth, ViewportHeight);
  FHost.PageView.OnHoverChanged := HandleHoverChanged;
end;

procedure TVclPerformanceTests.TearDown;
begin
  FreeAndNil(FHost);
end;

procedure TVclPerformanceTests.HandleHoverChanged(Sender: TObject; const HasSegment: Boolean; const Segment: TPdfTextFragment);
begin
  Inc(FHoverCount);
end;

class function TVclPerformanceTests.IsMeasured: Boolean;
begin
  {$IFDEF DEBUG}
  Result := False;
  {$ELSE}
  Result := True;
  {$ENDIF}
end;

class procedure TVclPerformanceTests.Note(const Line: string);
begin
  System.IOUtils.TFile.AppendAllText(System.IOUtils.TPath.Combine(System.IOUtils.TPath.GetTempPath, 'pdf4d-vcl-performance.txt'), Line + sLineBreak);
  TFile.AppendAllText(TPath.Combine(TPath.GetTempPath, 'pdf4d-vcl-performance.txt'), Line + sLineBreak);
end;

class function TVclPerformanceTests.Median(const Values: TArray<Double>): Double;
begin
  var Sorted := Copy(Values);
  TArray.Sort<Double>(Sorted);
  Result := Sorted[Length(Sorted) div 2];
end;

class function TVclPerformanceTests.MillisecondsOf(const Ticks: Int64): Double;
begin
  Result := Ticks * 1000 / TStopwatch.Frequency;
end;

function TVclPerformanceTests.TilesArrived: Boolean;
begin
  const Controller = FHost.PageView.Controller;
  Result := ((Controller.PendingTileCount = 0) and (Controller.TileCacheCost > 0));
end;

function TVclPerformanceTests.MeasureFirstPage(const Data: TBytes): Double;
begin
  const Watch = TStopwatch.StartNew;
  Assert.IsTrue(FHost.Open(Data), 'the invoice opens: ' + FHost.OpenErrorMessage);
  Assert.IsTrue(FHost.WaitUntil(TilesArrived, WaitMs), 'the visible tiles arrive');
  Result := MillisecondsOf(Watch.ElapsedTicks);

  FHost.Document.Close;
  FHost.Pump(1);
end;

function TVclPerformanceTests.InvoiceFolder: string;
begin
  Result := TCorpus.PdfPath(InvoiceFolderName);
end;

function TVclPerformanceTests.WordCenters(const Count: Integer): TArray<TPoint>;
begin
  Assert.IsTrue(FHost.WaitForPageText(0), 'the text of the first page arrives');
  var PageText: IPdfPageText;
  Assert.IsTrue(FHost.Document.TryGetPageText(0, PageText), 'the text of the first page is known');

  const Centers = TList<TPoint>.Create;
  try
    const Seen = TList<string>.Create;
    try
      for var Word in PageText.Words do
      begin
        if (Centers.Count < Count) and (not Seen.Contains(Word.Text)) then
        begin
          Seen.Add(Word.Text);
          Centers.Add(FHost.CenterOfWord(0, Word.Text, 0));
        end;
      end;
    finally
      Seen.Free;
    end;
    Result := Centers.ToArray;
  finally
    Centers.Free;
  end;
end;

procedure TVclPerformanceTests.TestFirstInvoicePageIsQuick;
begin
  if not IsMeasured then
  begin
    Assert.Pass('Performance is measured in a Release build');
  end;

  const Files = TDirectory.GetFiles(InvoiceFolder, '*.pdf');
  Assert.IsTrue(Length(Files) > 0, 'there are invoices in the corpus');
  for var FileName in Files do
  begin
    const Data = TFile.ReadAllBytes(FileName);
    var Runs: TArray<Double>;
    SetLength(Runs, FirstPageRuns);
    for var Run := 0 to FirstPageRuns - 1 do
    begin
      Runs[Run] := MeasureFirstPage(Data);
    end;

    const RunMedian = Median(Runs);
    Note(Format('First page of %s: median %.0f ms of %d runs (first %.0f ms)', [TPath.GetFileName(FileName), RunMedian, FirstPageRuns, Runs[0]]));
    Assert.IsTrue(RunMedian <= FirstPageLimitMs, Format('%s: the first page takes %.0f ms (median of %d runs), the limit is %d ms',
                                                    [TPath.GetFileName(FileName), RunMedian, FirstPageRuns, FirstPageLimitMs]));
  end;
end;

procedure TVclPerformanceTests.TestHoverIsImmediate;
begin
  if not IsMeasured then
  begin
    Assert.Pass('Performance is measured in a Release build');
  end;

  const Files = TDirectory.GetFiles(InvoiceFolder, '*.pdf');
  Assert.IsTrue(Length(Files) > 0, 'there are invoices in the corpus');
  Assert.IsTrue(FHost.Open(TFile.ReadAllBytes(Files[0])), 'the invoice opens: ' + FHost.OpenErrorMessage);
  Assert.IsTrue(FHost.WaitUntil(TilesArrived, WaitMs), 'the visible tiles arrive');
  const Centers = WordCenters(HoverWords);
  Assert.IsTrue(Length(Centers) > 1, 'the invoice has words to hover on');

  var Moves: TArray<Double>;
  SetLength(Moves, HoverMoves);
  for var Move := 0 to HoverMoves - 1 do
  begin
    // From word to word, and a little off center, so that the hover changes and the hit test works
    const Center = Centers[Move mod Length(Centers)];
    const Offset = (Move div Length(Centers)) mod 3;
    const Watch = TStopwatch.StartNew;
    FHost.MouseMove(Center.X + Offset, Center.Y);
    Moves[Move] := MillisecondsOf(Watch.ElapsedTicks);
  end;
  const MoveMedian = Median(Moves);
  Assert.IsTrue(FHoverCount > 0, 'the hover changed');

  var Repaints: TArray<Double>;
  SetLength(Repaints, RepaintRuns);
  for var Run := 0 to RepaintRuns - 1 do
  begin
    // The form lies outside the desktop, where Repaint paints nothing: the window paints itself into a bitmap, with its hover frame
    const Watch = TStopwatch.StartNew;
    const Painted = FHost.Snapshot;
    Repaints[Run] := MillisecondsOf(Watch.ElapsedTicks);
    Painted.Free;
  end;
  const RepaintMedian = Median(Repaints);

  Note(Format('Hover: median %.2f ms of %d moves; paint with the hover frame: median %.2f ms of %d', [MoveMedian, HoverMoves, RepaintMedian, RepaintRuns]));
  Assert.IsTrue(MoveMedian <= HoverLimitMs, Format('A mouse move takes %.2f ms (median), the limit is %d ms', [MoveMedian, HoverLimitMs]));
  Assert.IsTrue(RepaintMedian <= RepaintLimitMs, Format('A repaint takes %.2f ms (median), the limit is %d ms', [RepaintMedian, RepaintLimitMs]));
end;

procedure TVclPerformanceTests.TestScrollStaysResponsive;
begin
  if not IsMeasured then
  begin
    Assert.Pass('Performance is measured in a Release build');
  end;

  Assert.IsTrue(FHost.Open(TViewerDocuments.Pages(ScrollPages, PageWidth, PageHeight, 0)), 'the document opens: ' + FHost.OpenErrorMessage);
  Assert.IsTrue(FHost.WaitUntil(TilesArrived, WaitMs), 'the visible tiles arrive');

  var Longest := 0.0;
  var Total := 0.0;
  for var Message := 1 to ScrollMessages do
  begin
    const Watch = TStopwatch.StartNew;
    FHost.PageView.Perform(WM_VSCROLL, SB_PAGEDOWN, 0);
    const Elapsed = MillisecondsOf(Watch.ElapsedTicks);
    Longest := Max(Longest, Elapsed);
    Total := Total + Elapsed;
    // The renders run on the worker; what they deliver is handled between the messages, as the message loop would
    FHost.Pump(PumpAfterMessageMs);
  end;

  Note(Format('Scroll: longest of %d WM_VSCROLL messages %.2f ms (mean %.2f ms)', [ScrollMessages, Longest, Total / ScrollMessages]));
  Assert.IsTrue(Longest <= ScrollLimitMs, Format('A scroll message takes %.2f ms, the limit is %d ms', [Longest, ScrollLimitMs]));
end;

procedure TVclPerformanceTests.TestGdiObjectsStayWithinBudget;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Pages(ScrollPages, PageWidth, PageHeight, 0)), 'the document opens: ' + FHost.OpenErrorMessage);
  Assert.IsTrue(FHost.WaitUntil(TilesArrived, WaitMs), 'the visible tiles arrive');

  const Before = GetGuiResources(GetCurrentProcess, GR_GDIOBJECTS);
  for var Step := 1 to GdiScrollSteps do
  begin
    FHost.PageView.Perform(WM_VSCROLL, SB_PAGEDOWN, 0);
    FHost.WaitUntil(TilesArrived, WaitMs);
  end;
  const After = GetGuiResources(GetCurrentProcess, GR_GDIOBJECTS);

  Note(Format('GDI objects: %d before the scroll, %d after %d page downs', [Before, After, GdiScrollSteps]));
  Assert.IsTrue(After - Before <= GdiBudget, Format('The scroll made %d GDI objects, the budget is %d', [After - Before, GdiBudget]));
end;

end.
