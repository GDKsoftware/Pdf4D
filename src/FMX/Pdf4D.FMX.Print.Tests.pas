// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.FMX.Print.Tests;

{$EXCESSPRECISION OFF}
{$POINTERMATH ON}

interface

uses
  System.Classes,
  System.Types,
  System.SysUtils,
  System.Generics.Collections,
  System.Diagnostics,
  FMX.Graphics,
  Pdf4D.Viewer.Print,
  DUnitX.TestFramework,
  Pdf4D.Tests.FmxHost,
  Pdf4D.Tests.FmxBitmapPrintTarget,
  Pdf4D.FMX.PrintDialog;

type
  [TestFixture]
  TPdfFmxPrintTests = class
  private
    FHost: TFmxTestHost;
    FFolder: string;
    FDialog: TFmxBitmapPrintDialog;
    FPrintedCount: Integer;
    FFailure: string;
    FLastTick: TStopwatch;
    FLongestGap: Int64;
    FTicks: Integer;
    FRealDialog: TPdf4DPrintDialog;

    procedure HandleTick(Sender: TObject);
    procedure OpenDocument(const Data: TBytes);
    procedure NewDialog;
    procedure HandlePrinted(Sender: TObject);
    procedure HandleFailed(Sender: TObject; const ErrorMessage: string);
    function IsJobOver: Boolean;
    function HasPrintedPagesBeforeClosing: Boolean;
    function IsRealJobOver: Boolean;
    // Prints with the settings and waits until the job is over
    procedure PrintAndWait(const RangeKind: TPdfPrintRangeKind; const Scale: TPdfPrintScale);
    function CopyPages(const Pages: TObjectList<TBitmap>): TObjectList<TBitmap>;
    function CountDark(const Page: TBitmap; const Area: TRect): Integer;
    procedure AssertPagesEqual(const Expected, Actual: TBitmap; const Message: string);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestPrintToBitmapTarget;

    [Test]
    procedure TestPrintInBands;

    [Test]
    procedure TestPrintRangeCurrentPage;

    [Test]
    procedure TestUiStaysResponsiveWhilePrinting;

    [Test]
    procedure TestCloseFormWhilePrinting;

    [Test]
    procedure TestDrawerClipsToTheClipRectangle;

    [Test]
    procedure TestDrawerShowsTransparencyAsWhitePaper;

    [Test]
    procedure TestActualSizeOnSmallPaperStaysInsideThePaper;

    [Test]
    procedure TestPrinterTargetReportsTheGeometry;

    [Test]
    procedure TestRealPrinter;
  end;

implementation

uses
  System.IOUtils,
  System.Math,
  System.UITypes,
  FMX.Forms,
  FMX.Printer,
  FMX.Types,
  Pdf4D.Render.Bitmap,
  Pdf4D.Viewer.Types,
  Pdf4D.FMX.Print,
  Pdf4D.Tests.ViewerDocuments;

const
  ViewWidth = 800;
  ViewHeight = 600;
  PageSeconds = 1000;
  DarkLimit = 128;
  PixelTolerance = 2;
  TickMs = 50;
  MaxTickGapMs = 250;
  SmallBandPixels = 100000;
  LongDocumentPages = 20;
  PageDelayMs = 30;
  PagesBeforeClosing = 2;
  PdfPointsToPixels150 = 150 / 72;
  PrinterEnvironmentVariable = 'PDF4D_TEST_PRINTER';

{ TPdfFmxPrintTests }

procedure TPdfFmxPrintTests.Setup;
begin
  FHost := TFmxTestHost.Create(ViewWidth, ViewHeight);
  FFolder := TPath.Combine(TPath.GetTempPath, 'Pdf4DFmxPrintTests-' + TGUID.NewGuid.ToString);
  FPrintedCount := 0;
  FFailure := '';
  FLongestGap := 0;
  FTicks := 0;
  NewDialog;
end;

procedure TPdfFmxPrintTests.TearDown;
begin
  if Assigned(FHost) then
  begin
    // The job of the dialog is freed from the queue of the main thread
    FHost.Pump(20);
    FreeAndNil(FHost);
  end;
  if TDirectory.Exists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
end;

procedure TPdfFmxPrintTests.NewDialog;
begin
  FDialog := TFmxBitmapPrintDialog.Create(FHost.Form);
  FDialog.Document := FHost.Document;
  FDialog.Folder := FFolder;
  FDialog.OnPrinted := HandlePrinted;
  FDialog.OnPrintFailed := HandleFailed;
end;

procedure TPdfFmxPrintTests.OpenDocument(const Data: TBytes);
begin
  Assert.IsTrue(FHost.Open(Data), 'the document opens: ' + FHost.OpenErrorMessage);
end;

procedure TPdfFmxPrintTests.HandlePrinted(Sender: TObject);
begin
  Inc(FPrintedCount);
end;

procedure TPdfFmxPrintTests.HandleFailed(Sender: TObject; const ErrorMessage: string);
begin
  FFailure := ErrorMessage;
end;

function TPdfFmxPrintTests.IsJobOver: Boolean;
begin
  Result := not FDialog.IsPrinting;
end;

function TPdfFmxPrintTests.HasPrintedPagesBeforeClosing: Boolean;
begin
  Result := Assigned(FDialog.Target) and (FDialog.Target.Pages.Count >= PagesBeforeClosing);
end;

function TPdfFmxPrintTests.IsRealJobOver: Boolean;
begin
  Result := not FRealDialog.IsPrinting;
end;

function TPdfFmxPrintTests.CopyPages(const Pages: TObjectList<TBitmap>): TObjectList<TBitmap>;
begin
  Result := TObjectList<TBitmap>.Create(True);
  try
    for var Page in Pages do
    begin
      const Copy = TBitmap.Create;
      Result.Add(Copy);
      Copy.Assign(Page);
    end;
  except
    Result.Free;
    raise;
  end;
end;

procedure TPdfFmxPrintTests.PrintAndWait(const RangeKind: TPdfPrintRangeKind; const Scale: TPdfPrintScale);
begin
  var Settings := TPdfPrintSettings.Default;
  Settings.RangeKind := RangeKind;
  Settings.Scale := Scale;
  FDialog.Print(Settings);
  Assert.IsTrue(FHost.WaitUntil(IsJobOver, 30 * PageSeconds), 'the job ends');
  Assert.AreEqual('', FFailure, 'the job does not fail');
end;

function TPdfFmxPrintTests.CountDark(const Page: TBitmap; const Area: TRect): Integer;
begin
  Result := 0;
  for var Y := Area.Top to Area.Bottom - 1 do
  begin
    for var X := Area.Left to Area.Right - 1 do
    begin
      const Pixel = TAlphaColorRec(TFmxTestHost.PixelAt(Page, X, Y));
      if (Pixel.R < DarkLimit) and (Pixel.G < DarkLimit) and (Pixel.B < DarkLimit) then
      begin
        Inc(Result);
      end;
    end;
  end;
end;

procedure TPdfFmxPrintTests.AssertPagesEqual(const Expected, Actual: TBitmap; const Message: string);
begin
  Assert.AreEqual(Expected.Width, Actual.Width, Message + ': width');
  Assert.AreEqual(Expected.Height, Actual.Height, Message + ': height');

  var Left, Right: TBitmapData;
  Assert.IsTrue(Expected.Map(TMapAccess.Read, Left), Message + ': the first page is readable');
  try
    Assert.IsTrue(Actual.Map(TMapAccess.Read, Right), Message + ': the second page is readable');
    try
      var Worst := 0;
      for var Y := 0 to Expected.Height - 1 do
      begin
        const LeftRow = PByte(Left.GetScanline(Y));
        const RightRow = PByte(Right.GetScanline(Y));
        for var Offset := 0 to Expected.Width * Left.BytesPerPixel - 1 do
        begin
          Worst := Max(Worst, Abs(Integer(LeftRow[Offset]) - Integer(RightRow[Offset])));
        end;
      end;
      Assert.IsTrue(Worst <= PixelTolerance, Format('%s: the pages differ by %d', [Message, Worst]));
    finally
      Actual.Unmap(Right);
    end;
  finally
    Expected.Unmap(Left);
  end;
end;

procedure TPdfFmxPrintTests.TestPrintToBitmapTarget;
begin
  OpenDocument(TViewerDocuments.Invoice);
  PrintAndWait(TPdfPrintRangeKind.All, TPdfPrintScale.Fit);

  const Target = FDialog.Target;
  Assert.AreEqual(2, Integer(Target.Pages.Count), 'two pages');
  Assert.IsTrue(Target.IsEnded, 'the document is ended');
  Assert.IsFalse(Target.IsAborted, 'the document is not aborted');
  Assert.AreEqual(1, FPrintedCount, 'OnPrinted once');

  // "Factuur 2024-0815" stands on the baseline at (100,700) of the page; the page is 150 dpi on this paper
  const Left = Round(100 * PdfPointsToPixels150);
  const Baseline = Round((792 - 700) * PdfPointsToPixels150);
  const Text = TRect.Create(Left, Baseline - 25, Left + 200, Baseline + 5);
  Assert.IsTrue(CountDark(Target.Pages[0], Text) > 30, 'the text of the first page is dark on the paper');
  Assert.AreEqual(0, CountDark(Target.Pages[0], TRect.Create(800, 900, 1200, 1200)), 'the rest of the page is white');

  for var Index := 1 to 2 do
  begin
    Assert.IsTrue(TFile.Exists(TPath.Combine(FFolder, Format('page-%d.png', [Index]))), Format('the PNG of page %d is in the folder', [Index]));
  end;
end;

// Letter paper at 150 dpi, the paper of the test dialog: every band is copied to its printer rows pixel for pixel, so the pages in bands
// are the pages in one piece
procedure TPdfFmxPrintTests.TestPrintInBands;
begin
  OpenDocument(TViewerDocuments.Invoice);
  PrintAndWait(TPdfPrintRangeKind.All, TPdfPrintScale.Fit);
  const SingleBandPages = CopyPages(FDialog.Target.Pages);
  try
    Assert.AreEqual(2, FDialog.Target.DrawBandCount, 'one band per page by default');

    NewDialog;
    FDialog.Folder := '';
    FDialog.MaxBandPixels := SmallBandPixels;
    PrintAndWait(TPdfPrintRangeKind.All, TPdfPrintScale.Fit);

    Assert.IsTrue(FDialog.Target.DrawBandCount > 2 * 2, 'more than one band per page');
    Assert.AreEqual(2, Integer(FDialog.Target.Pages.Count));
    for var Index := 0 to 1 do
    begin
      AssertPagesEqual(SingleBandPages[Index], FDialog.Target.Pages[Index], Format('page %d', [Index + 1]));
    end;
  finally
    SingleBandPages.Free;
  end;
end;

procedure TPdfFmxPrintTests.TestPrintRangeCurrentPage;
begin
  OpenDocument(TViewerDocuments.Invoice);
  PrintAndWait(TPdfPrintRangeKind.All, TPdfPrintScale.Fit);
  const AllPages = CopyPages(FDialog.Target.Pages);
  try
    FHost.Document.CurrentPage := 1;
    NewDialog;
    PrintAndWait(TPdfPrintRangeKind.Current, TPdfPrintScale.Fit);

    Assert.AreEqual(1, Integer(FDialog.Target.Pages.Count), 'only the current page');
    AssertPagesEqual(AllPages[1], FDialog.Target.Pages[0], 'the second page');
  finally
    AllPages.Free;
  end;
end;

procedure TPdfFmxPrintTests.HandleTick(Sender: TObject);
begin
  FLongestGap := Max(FLongestGap, FLastTick.ElapsedMilliseconds);
  FLastTick := TStopwatch.StartNew;
  Inc(FTicks);
end;

procedure TPdfFmxPrintTests.TestUiStaysResponsiveWhilePrinting;
begin
  OpenDocument(TViewerDocuments.Pages(LongDocumentPages, 612, 792, 0));

  // The PNG files are written by the end of the document, on this thread; the test is about the job
  FDialog.Folder := '';
  const Timer = TTimer.Create(FHost.Form);
  Timer.Interval := TickMs;
  Timer.OnTimer := HandleTick;

  FLastTick := TStopwatch.StartNew;
  PrintAndWait(TPdfPrintRangeKind.All, TPdfPrintScale.Fit);
  FLongestGap := Max(FLongestGap, FLastTick.ElapsedMilliseconds);
  Timer.Enabled := False;

  Assert.AreEqual(LongDocumentPages, Integer(FDialog.Target.Pages.Count), 'all pages are printed');
  Assert.IsTrue(FTicks > 0, 'the timer ticks while the job runs');
  Assert.IsTrue(FLongestGap <= MaxTickGapMs, Format('the longest gap between ticks is %d ms', [FLongestGap]));
end;

// The form goes while a job of twenty pages runs: the dialog, which the form owns, aborts the document, and nothing is left behind
procedure TPdfFmxPrintTests.TestCloseFormWhilePrinting;
begin
  OpenDocument(TViewerDocuments.Pages(LongDocumentPages, 612, 792, 0));
  FDialog.ShowProgress := True;
  FDialog.DrawDelayMs := PageDelayMs;
  FDialog.Folder := '';
  FDialog.Print(TPdfPrintSettings.Default);
  Assert.IsNotNull(FDialog.ProgressForm, 'the progress window is shown');

  Assert.IsTrue(FHost.WaitUntil(HasPrintedPagesBeforeClosing, 30 * PageSeconds), 'the job prints');
  const Target = FDialog.Target;
  // Holds the target beyond the dialog
  const Held: IPdfPrintTarget = Target;
  Assert.IsTrue(FDialog.IsPrinting, 'the job is still running');

  FreeAndNil(FHost);
  CheckSynchronize(PageDelayMs);

  Assert.IsTrue(Target.IsAborted, 'the document is aborted');
  Assert.IsFalse(Target.IsEnded, 'the document is not ended');
  Assert.IsTrue(Target.Pages.Count < LongDocumentPages, 'not all pages are printed');
  Assert.IsNotNull(Held);
  Assert.AreEqual(0, FPrintedCount, 'a job that is cut off is not printed');
end;

procedure TPdfFmxPrintTests.TestDrawerClipsToTheClipRectangle;
begin
  const Band = TPdfBitmap.Create(10, 10);
  const Paper = TBitmap.Create(100, 100);
  try
    for var Y := 0 to 9 do
    begin
      for var X := 0 to 9 do
      begin
        Band.SetPixel(X, Y, TPdfDeviceColor.Create(0, 0, 0));
      end;
    end;
    Assert.IsTrue(Paper.Canvas.BeginScene);
    try
      Paper.Canvas.Clear(TAlphaColors.White);
    finally
      Paper.Canvas.EndScene;
    end;

    // The destination reaches outside the clip area on the right and below
    TPdfFmxBandDrawer.Draw(Paper.Canvas, Band, TRect.Create(20, 20, 100, 100), TRect.Create(0, 0, 50, 50));

    Assert.AreEqual(Byte(0), TAlphaColorRec(TFmxTestHost.PixelAt(Paper, 30, 30)).R, 'inside the clip area the band is drawn');
    Assert.AreEqual(Byte(255), TAlphaColorRec(TFmxTestHost.PixelAt(Paper, 10, 10)).R, 'left of the destination stays white');
    Assert.AreEqual(Byte(255), TAlphaColorRec(TFmxTestHost.PixelAt(Paper, 60, 60)).R, 'outside the clip area nothing is drawn');
    Assert.AreEqual(Byte(255), TAlphaColorRec(TFmxTestHost.PixelAt(Paper, 90, 30)).R, 'right of the clip area nothing is drawn');
  finally
    Paper.Free;
    Band.Free;
  end;
end;

procedure TPdfFmxPrintTests.TestDrawerShowsTransparencyAsWhitePaper;
begin
  const Band = TPdfBitmap.Create(4, 4);
  const Paper = TBitmap.Create(4, 4);
  try
    // Transparent black, and half transparent black (premultiplied: 0 with alpha 128)
    Band.SetPixel(1, 1, TPdfDeviceColor.Create(0, 0, 0, 128));
    Assert.IsTrue(Paper.Canvas.BeginScene);
    try
      Paper.Canvas.Clear(TAlphaColors.Blue);
    finally
      Paper.Canvas.EndScene;
    end;

    TPdfFmxBandDrawer.Draw(Paper.Canvas, Band, TRect.Create(0, 0, 4, 4), TRect.Create(0, 0, 4, 4));

    const Clear = TAlphaColorRec(TFmxTestHost.PixelAt(Paper, 3, 3));
    Assert.AreEqual(255, Integer(Clear.R), 'a transparent pixel is white paper (red)');
    Assert.AreEqual(255, Integer(Clear.B), 'a transparent pixel is white paper (blue)');
    const Half = TAlphaColorRec(TFmxTestHost.PixelAt(Paper, 1, 1));
    Assert.IsTrue(Abs(Integer(Half.G) - 127) <= 2, 'half black on white is mid grey');
  finally
    Paper.Free;
    Band.Free;
  end;
end;

procedure TPdfFmxPrintTests.TestActualSizeOnSmallPaperStaysInsideThePaper;
begin
  OpenDocument(TViewerDocuments.Invoice);
  // 4 by 4 inches at 150 dpi: a Letter page at actual size reaches far outside the paper
  FDialog.Printable := TSize.Create(600, 600);
  FDialog.MaxBandPixels := SmallBandPixels;
  PrintAndWait(TPdfPrintRangeKind.Current, TPdfPrintScale.ActualSize);

  Assert.AreEqual(1, Integer(FDialog.Target.Pages.Count));
  Assert.AreEqual(600, FDialog.Target.Pages[0].Width);
  Assert.IsTrue(FDialog.Target.DrawBandCount >= 1, 'bands on the paper are drawn');
end;

procedure TPdfFmxPrintTests.TestPrinterTargetReportsTheGeometry;
begin
  if Printer.Count = 0 then
  begin
    Assert.Pass('This machine has no printer');
  end;

  // Nothing is printed: only the device of the printer is asked
  const Target: IPdfPrintTarget = TPdfFmxPrinterTarget.Create(Printer);
  Assert.IsTrue((Target.PrintableSize.cx > 0) and (Target.PrintableSize.cy > 0), 'the page has a size');
  Assert.IsTrue((Target.Dpi.X > 0) and (Target.Dpi.Y > 0), 'the printer has a resolution');
end;

procedure TPdfFmxPrintTests.TestRealPrinter;
begin
  const PrinterName = GetEnvironmentVariable(PrinterEnvironmentVariable);
  if PrinterName = '' then
  begin
    Assert.Pass('Set ' + PrinterEnvironmentVariable + ' to the name of a printer to print on it for real');
  end;

  var Chosen := -1;
  for var Index := 0 to Printer.Count - 1 do
  begin
    if SameText(Printer.Printers[Index].Title, PrinterName) or SameText(Printer.Printers[Index].Device, PrinterName) then
    begin
      Chosen := Index;
    end;
  end;
  Assert.IsTrue(Chosen >= 0, 'the printer is installed: ' + PrinterName);
  Printer.ActivePrinter := Printer.Printers[Chosen];

  OpenDocument(TViewerDocuments.Invoice);
  // The plain dialog prints on the printer of FMX.Printer
  FRealDialog := TPdf4DPrintDialog.Create(FHost.Form);
  FRealDialog.Document := FHost.Document;
  FRealDialog.ShowProgress := False;
  FRealDialog.OnPrintFailed := HandleFailed;
  FRealDialog.Print(TPdfPrintSettings.Default);
  Assert.IsTrue(FHost.WaitUntil(IsRealJobOver, 60 * PageSeconds), 'the job ends');
  Assert.AreEqual('', FFailure, 'printing does not fail');
end;

end.
