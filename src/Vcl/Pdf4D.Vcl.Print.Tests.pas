// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Vcl.Print.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.Types,
  System.SysUtils,
  System.Generics.Collections,
  System.Diagnostics,
  Vcl.Graphics,
  Pdf4D.Viewer.Print,
  DUnitX.TestFramework,
  Pdf4D.Tests.VclHost,
  Pdf4D.Tests.BitmapPrintTarget;

type
  [TestFixture]
  TPdfVclPrintTests = class
  private
    FHost: TVclTestHost;
    FFolder: string;
    FDialog: TBitmapPrintDialog;
    FPrintedCount: Integer;
    FFailure: string;
    FLastTick: TStopwatch;
    FLongestGap: Int64;
    FTicks: Integer;

    procedure HandleTick(Sender: TObject);
    procedure OpenDocument(const Data: TBytes);
    procedure NewDialog;
    // Paper of the size of a Letter page at 2 pixels to the point, so that a page renders without rounding
    procedure HandlePrinted(Sender: TObject);
    procedure HandleFailed(Sender: TObject; const ErrorMessage: string);
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
  Vcl.ExtCtrls,
  Vcl.Printers,
  Pdf4D.Render.Bitmap,
  Pdf4D.Viewer.Types,
  Pdf4D.Vcl.Print,
  Pdf4D.Vcl.PrintDialog,
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
  PdfPointsToPixels150 = 150 / 72;
  PrinterEnvironmentVariable = 'PDF4D_TEST_PRINTER';

{ TPdfVclPrintTests }

procedure TPdfVclPrintTests.Setup;
begin
  FHost := TVclTestHost.Create(ViewWidth, ViewHeight);
  FFolder := TPath.Combine(TPath.GetTempPath, 'Pdf4DPrintTests-' + TGUID.NewGuid.ToString);
  FPrintedCount := 0;
  FFailure := '';
  FLongestGap := 0;
  FTicks := 0;
  NewDialog;
end;

procedure TPdfVclPrintTests.TearDown;
begin
  // The job of the dialog is freed from the queue of the main thread
  FHost.Pump(20);
  FreeAndNil(FHost);
  if TDirectory.Exists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
end;

procedure TPdfVclPrintTests.NewDialog;
begin
  FDialog := TBitmapPrintDialog.Create(FHost.Form);
  FDialog.Document := FHost.Document;
  FDialog.Folder := FFolder;
  FDialog.OnPrinted := HandlePrinted;
  FDialog.OnPrintFailed := HandleFailed;
end;


procedure TPdfVclPrintTests.OpenDocument(const Data: TBytes);
begin
  Assert.IsTrue(FHost.Open(Data), 'the document opens: ' + FHost.OpenErrorMessage);
end;

procedure TPdfVclPrintTests.HandlePrinted(Sender: TObject);
begin
  Inc(FPrintedCount);
end;

procedure TPdfVclPrintTests.HandleFailed(Sender: TObject; const ErrorMessage: string);
begin
  FFailure := ErrorMessage;
end;

function TPdfVclPrintTests.CopyPages(const Pages: TObjectList<TBitmap>): TObjectList<TBitmap>;
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

procedure TPdfVclPrintTests.PrintAndWait(const RangeKind: TPdfPrintRangeKind; const Scale: TPdfPrintScale);
begin
  var Settings := TPdfPrintSettings.Default;
  Settings.RangeKind := RangeKind;
  Settings.Scale := Scale;
  FDialog.Print(Settings);
  Assert.IsTrue(FHost.WaitUntil(
    function: Boolean
    begin
      Result := not FDialog.IsPrinting;
    end, 30 * PageSeconds), 'the job ends');
  Assert.AreEqual('', FFailure, 'the job does not fail');
end;

function TPdfVclPrintTests.CountDark(const Page: TBitmap; const Area: TRect): Integer;
begin
  Result := 0;
  for var Y := Area.Top to Area.Bottom - 1 do
  begin
    for var X := Area.Left to Area.Right - 1 do
    begin
      const Pixel = TVclTestHost.PixelAt(Page, X, Y);
      if (Pixel.R < DarkLimit) and (Pixel.G < DarkLimit) and (Pixel.B < DarkLimit) then
      begin
        Inc(Result);
      end;
    end;
  end;
end;

procedure TPdfVclPrintTests.AssertPagesEqual(const Expected, Actual: TBitmap; const Message: string);
begin
  Assert.AreEqual(Expected.Width, Actual.Width, Message + ': width');
  Assert.AreEqual(Expected.Height, Actual.Height, Message + ': height');
  var Worst := 0;
  for var Y := 0 to Expected.Height - 1 do
  begin
    const Left = PByte(Expected.ScanLine[Y]);
    const Right = PByte(Actual.ScanLine[Y]);
    for var Offset := 0 to Expected.Width * 3 - 1 do
    begin
      Worst := Max(Worst, Abs(Integer(Left[Offset]) - Integer(Right[Offset])));
    end;
  end;
  Assert.IsTrue(Worst <= PixelTolerance, Format('%s: the pages differ by %d', [Message, Worst]));
end;

procedure TPdfVclPrintTests.TestPrintToBitmapTarget;
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
procedure TPdfVclPrintTests.TestPrintInBands;
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

procedure TPdfVclPrintTests.TestPrintRangeCurrentPage;
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

procedure TPdfVclPrintTests.HandleTick(Sender: TObject);
begin
  FLongestGap := Max(FLongestGap, FLastTick.ElapsedMilliseconds);
  FLastTick := TStopwatch.StartNew;
  Inc(FTicks);
end;

procedure TPdfVclPrintTests.TestUiStaysResponsiveWhilePrinting;
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

procedure TPdfVclPrintTests.TestDrawerClipsToTheClipRectangle;
begin
  const Band = TPdfBitmap.Create(10, 10);
  const Paper = TBitmap.Create;
  try
    for var Y := 0 to 9 do
    begin
      for var X := 0 to 9 do
      begin
        Band.SetPixel(X, Y, TPdfDeviceColor.Create(0, 0, 0));
      end;
    end;
    Paper.PixelFormat := pf24bit;
    Paper.SetSize(100, 100);
    Paper.Canvas.Brush.Color := clWhite;
    Paper.Canvas.FillRect(TRect.Create(0, 0, 100, 100));

    // The destination reaches outside the clip area on the right and below
    TPdfVclBandDrawer.Draw(Paper.Canvas.Handle, Band, TRect.Create(20, 20, 100, 100), TRect.Create(0, 0, 50, 50));

    Assert.AreEqual(Byte(0), TVclTestHost.PixelAt(Paper, 30, 30).R, 'inside the clip area the band is drawn');
    Assert.AreEqual(Byte(255), TVclTestHost.PixelAt(Paper, 10, 10).R, 'left of the destination stays white');
    Assert.AreEqual(Byte(255), TVclTestHost.PixelAt(Paper, 60, 60).R, 'outside the clip area nothing is drawn');
    Assert.AreEqual(Byte(255), TVclTestHost.PixelAt(Paper, 90, 30).R, 'right of the clip area nothing is drawn');
  finally
    Paper.Free;
    Band.Free;
  end;
end;

procedure TPdfVclPrintTests.TestDrawerShowsTransparencyAsWhitePaper;
begin
  const Band = TPdfBitmap.Create(4, 4);
  const Paper = TBitmap.Create;
  try
    // Transparent black, and half transparent black (premultiplied: 0 with alpha 128)
    Band.SetPixel(1, 1, TPdfDeviceColor.Create(0, 0, 0, 128));
    Paper.PixelFormat := pf24bit;
    Paper.SetSize(4, 4);
    Paper.Canvas.Brush.Color := clBlue;
    Paper.Canvas.FillRect(TRect.Create(0, 0, 4, 4));

    TPdfVclBandDrawer.Draw(Paper.Canvas.Handle, Band, TRect.Create(0, 0, 4, 4), TRect.Create(0, 0, 4, 4));

    const Clear = TVclTestHost.PixelAt(Paper, 3, 3);
    Assert.AreEqual(255, Integer(Clear.R) + 0, 'a transparent pixel is white paper (red)');
    Assert.AreEqual(255, Integer(Clear.B), 'a transparent pixel is white paper (blue)');
    const Half = TVclTestHost.PixelAt(Paper, 1, 1);
    Assert.IsTrue(Abs(Integer(Half.G) - 127) <= 2, 'half black on white is mid grey');
  finally
    Paper.Free;
    Band.Free;
  end;
end;

procedure TPdfVclPrintTests.TestActualSizeOnSmallPaperStaysInsideThePaper;
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

procedure TPdfVclPrintTests.TestPrinterTargetReportsTheGeometry;
begin
  if Printer.Printers.Count = 0 then
  begin
    Assert.Pass('This machine has no printer');
  end;

  // Nothing is printed: only the device of the printer is asked
  const Target: IPdfPrintTarget = TPdfVclPrinterTarget.Create(Printer);
  Assert.IsTrue((Target.PrintableSize.cx > 0) and (Target.PrintableSize.cy > 0), 'the page has a size');
  Assert.IsTrue((Target.Dpi.X > 0) and (Target.Dpi.Y > 0), 'the printer has a resolution');
end;

procedure TPdfVclPrintTests.TestRealPrinter;
begin
  const PrinterName = GetEnvironmentVariable(PrinterEnvironmentVariable);
  if PrinterName = '' then
  begin
    Assert.Pass('Set ' + PrinterEnvironmentVariable + ' to the name of a printer to print on it for real');
  end;

  const Index = Printer.Printers.IndexOf(PrinterName);
  Assert.IsTrue(Index >= 0, 'the printer is installed: ' + PrinterName);
  Printer.PrinterIndex := Index;

  OpenDocument(TViewerDocuments.Invoice);
  // The plain dialog prints on the printer of Vcl.Printers
  const Dialog = TPdf4DPrintDialog.Create(FHost.Form);
  Dialog.Document := FHost.Document;
  Dialog.ShowProgress := False;
  Dialog.OnPrintFailed := HandleFailed;
  Dialog.Print(TPdfPrintSettings.Default);
  Assert.IsTrue(FHost.WaitUntil(
    function: Boolean
    begin
      Result := not Dialog.IsPrinting;
    end, 60 * PageSeconds), 'the job ends');
  Assert.AreEqual('', FFailure, 'printing does not fail');
end;

end.
