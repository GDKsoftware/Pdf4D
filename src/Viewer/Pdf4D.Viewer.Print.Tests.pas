// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.Print.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  System.SysUtils,
  System.Classes,
  DUnitX.TestFramework,
  Pdf4D.Render.Bitmap,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.Session,
  Pdf4D.Viewer.Print,
  Pdf4D.Tests.TestDocument,
  Pdf4D.Tests.FakeSession;

type
  [TestFixture]
  TPdfPrintSettingsTests = class
  public
    [Test]
    procedure TestDefault;
    [Test]
    procedure TestPageIndexes;
    [Test]
    procedure TestInvalidRangesRaise;
  end;

  [TestFixture]
  TPdfPrintPlannerTests = class
  private
    class function PageOf(const Width, Height: Single; const Rotation: Integer): TPdfPageInfo; static;
    class function SettingsOf(const Scale: TPdfPrintScale): TPdfPrintSettings; static;

  public
    [Test]
    procedure TestActualSizeLetterOn600DpiA4;
    [Test]
    procedure TestFitScalesUp;
    [Test]
    procedure TestFitScalesDown;
    [Test]
    procedure TestLandscapePageRotatesOnPortraitPaper;
    [Test]
    procedure TestPortraitPageOnLandscapePaperRotates;
    [Test]
    procedure TestRotatedPageCountsItsRotation;
    [Test]
    procedure TestBandsCoverRenderExactly;
    [Test]
    procedure TestBandOfOneRowWhenThePageIsWiderThanTheBudget;
    [Test]
    procedure TestBandDestMapsProportionally;
    [Test]
    procedure TestBandDestOfClippedPageKeepsTheScale;
    [Test]
    procedure TestDifferentDpiXY;
    [Test]
    procedure TestMaxDpiLimitsTheRender;
    [Test]
    procedure TestPixelCountsBeyondIntegerDoNotOverflow;
    [Test]
    procedure TestInvalidArgumentsRaise;
  end;

  // Writes down what the job does to it
  TRecordingPrintTarget = class(TInterfacedObject, IPdfPrintTarget)
  private
    FLog: TStringList;
    FPrintable: TSize;
    FDpi: TPointF;
    FFailOnDrawBand: Boolean;

  public
    constructor Create(const Printable: TSize; const Dpi: TPointF);
    destructor Destroy; override;

    function PrintableSize: TSize;
    function Dpi: TPointF;
    procedure BeginDocument(const Title: string; const Copies: Integer);
    procedure BeginPage;
    procedure DrawBand(const Band: TPdfBitmap; const Dest: TRect);
    procedure EndDocument;
    procedure AbortDocument;

    property Calls: TStringList read FLog;
    property FailOnDrawBand: Boolean read FFailOnDrawBand write FFailOnDrawBand;
  end;

  [TestFixture]
  TPdfPrintJobTests = class
  private
    FFake: TFakeViewerSession;
    FSession: IPdfViewerSession;
    FDocument: TTestDocument;
    FTarget: TRecordingPrintTarget;
    FTargetReference: IPdfPrintTarget;
    FJob: TPdfPrintJob;
    FProgress: TStringList;
    FDoneCount: Integer;
    FStatus: TPdfPrintStatus;
    FMessage: string;

    procedure OpenLetterPages(const PageCount: Integer; const CanPrint: Boolean);
    function NewJob(const Settings: TPdfPrintSettings): TPdfPrintJob;
    procedure StartJob;
    function LogText: string;

  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestJobPrintsPagesInBands;
    [Test]
    procedure TestCancelAbortsDocument;
    [Test]
    procedure TestRenderFailureFailsJob;
    [Test]
    procedure TestDrawFailureFailsJob;
    [Test]
    procedure TestJobWithoutPrintPermissionRaises;
    [Test]
    procedure TestIgnorePermissionsAllowsPrinting;
    [Test]
    procedure TestDestroyWhileRunningAborts;
    [Test]
    procedure TestRangeCurrentPrintsTheCurrentPage;
    [Test]
    procedure TestClosingTheDocumentFailsTheJob;
    [Test]
    procedure TestBandsOutsideThePaperAreNotRendered;
    [Test]
    procedure TestInvalidRangeRaisesInCreate;
  end;

implementation

uses
  System.Math,
  System.Generics.Collections,
  Pdf4D.Model.Rectangle;

const
  LetterWidth = 612;
  LetterHeight = 792;
  Unlimited: Int64 = 1000 * 1000 * 1000;
  PointsPerInch = 72;
  Tolerance = 0.0001;

function Join(const Values: TArray<Integer>): string;
begin
  Result := '';
  for var Value in Values do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + IntToStr(Value);
  end;
end;

{ TPdfPrintSettingsTests }

procedure TPdfPrintSettingsTests.TestDefault;
begin
  const Settings = TPdfPrintSettings.Default;

  Assert.AreEqual(Ord(TPdfPrintRangeKind.All), Ord(Settings.RangeKind));
  Assert.AreEqual(Ord(TPdfPrintScale.Fit), Ord(Settings.Scale));
  Assert.AreEqual(1, Settings.Copies);
  Assert.AreEqual(300, Settings.MaxDpi);
  Assert.AreEqual(DefaultMaxPrintDpi, Settings.MaxDpi);
  Assert.AreEqual('', Settings.Title);
end;

procedure TPdfPrintSettingsTests.TestPageIndexes;
begin
  var Settings := TPdfPrintSettings.Default;
  Assert.AreEqual('0,1,2,3,4', Join(Settings.PageIndexes(5, 2)));

  Settings.RangeKind := TPdfPrintRangeKind.Current;
  Assert.AreEqual('2', Join(Settings.PageIndexes(5, 2)));

  Settings.RangeKind := TPdfPrintRangeKind.Pages;
  Settings.FromPage := 2;
  Settings.ToPage := 4;
  Assert.AreEqual('1,2,3', Join(Settings.PageIndexes(5, 2)));

  Settings.FromPage := 5;
  Settings.ToPage := 5;
  Assert.AreEqual('4', Join(Settings.PageIndexes(5, 2)));
end;

procedure TPdfPrintSettingsTests.TestInvalidRangesRaise;
begin
  var Settings := TPdfPrintSettings.Default;
  Settings.RangeKind := TPdfPrintRangeKind.Pages;

  var Check: TProc<Integer, Integer> :=
    procedure(FromPage, ToPage: Integer)
    begin
      Settings.FromPage := FromPage;
      Settings.ToPage := ToPage;
      Assert.WillRaise(
        procedure
        begin
          Settings.PageIndexes(5, 0);
        end,
        EArgumentOutOfRangeException);
    end;

  // Reversed, below the first page and beyond the last
  Check(4, 2);
  Check(0, 1);
  Check(5, 9);

  // No pages at all
  Settings.RangeKind := TPdfPrintRangeKind.All;
  Assert.WillRaise(
    procedure
    begin
      Settings.PageIndexes(0, 0);
    end,
    EArgumentOutOfRangeException);
end;

{ TPdfPrintPlannerTests }

class function TPdfPrintPlannerTests.PageOf(const Width, Height: Single; const Rotation: Integer): TPdfPageInfo;
begin
  Result.CropBox.LowerLeftX := 0;
  Result.CropBox.LowerLeftY := 0;
  Result.CropBox.UpperRightX := Width;
  Result.CropBox.UpperRightY := Height;
  Result.Rotation := Rotation;
  Result.Label_ := '';
end;

class function TPdfPrintPlannerTests.SettingsOf(const Scale: TPdfPrintScale): TPdfPrintSettings;
begin
  Result := TPdfPrintSettings.Default;
  Result.Scale := Scale;
end;

procedure TPdfPrintPlannerTests.TestActualSizeLetterOn600DpiA4;
begin
  const Plan = TPdfPrintPlanner.PlanPage(PageOf(LetterWidth, LetterHeight, 0), 3, TSize.Create(4800, 6800), TPointF.Create(600, 600),
                                         SettingsOf(TPdfPrintScale.ActualSize), Unlimited);

  Assert.AreEqual(3, Plan.PageIndex);
  Assert.AreEqual(0, Plan.ViewRotation);
  // Clipped to the width, centred on the height
  Assert.AreEqual(0, Plan.Dest.Left);
  Assert.AreEqual(4800, Plan.Dest.Width);
  Assert.AreEqual(100, Plan.Dest.Top);
  Assert.AreEqual(6600, Plan.Dest.Height);
  // The whole page is 5100 wide, centred
  Assert.AreEqual(-150, Plan.FullDest.Left);
  Assert.AreEqual(5100, Plan.FullDest.Width);
  Assert.AreEqual(100, Plan.FullDest.Top);
  Assert.AreEqual(6600, Plan.FullDest.Height);
  // Limited by MaxDpi
  Assert.AreEqual(Double(300 / PointsPerInch), Double(Plan.RenderScale), Tolerance);
  Assert.AreEqual(2550, Integer(Plan.RenderSize.cx));
  // The size of a render is rounded down: one pixel less when the scale is a little below 300 / 72
  Assert.IsTrue(Abs(Plan.RenderSize.cy - 3300) <= 1);
end;

procedure TPdfPrintPlannerTests.TestFitScalesUp;
begin
  // A5 on A4 at 600 DPI
  const Plan = TPdfPrintPlanner.PlanPage(PageOf(420, 595, 0), 0, TSize.Create(4960, 7016), TPointF.Create(600, 600),
                                         SettingsOf(TPdfPrintScale.Fit), Unlimited);

  Assert.IsTrue((Plan.Dest.Width = 4960) or (Plan.Dest.Height = 7016), 'one side fills the paper');
  Assert.IsTrue((Plan.Dest.Width <= 4960) and (Plan.Dest.Height <= 7016), 'and the other one is inside it');
  Assert.IsTrue(Plan.Dest.Width > 3500, 'the page is larger than at actual size');
  Assert.AreEqual(Plan.FullDest, Plan.Dest);
  // Centred
  Assert.AreEqual((4960 - Plan.Dest.Width) div 2, Plan.Dest.Left);
  Assert.AreEqual((7016 - Plan.Dest.Height) div 2, Plan.Dest.Top);
end;

procedure TPdfPrintPlannerTests.TestFitScalesDown;
begin
  // Letter on a 3 by 4 inch label at 100 DPI
  const Plan = TPdfPrintPlanner.PlanPage(PageOf(LetterWidth, LetterHeight, 0), 0, TSize.Create(300, 400), TPointF.Create(100, 100),
                                         SettingsOf(TPdfPrintScale.Fit), Unlimited);

  Assert.AreEqual(300, Plan.Dest.Width);
  Assert.IsTrue(Plan.Dest.Height <= 400);
  // The render is no finer than the printer: 100 DPI times the factor of about 0.35
  Assert.IsTrue(Plan.RenderScale < 100 / PointsPerInch);
end;

procedure TPdfPrintPlannerTests.TestLandscapePageRotatesOnPortraitPaper;
begin
  const Plan = TPdfPrintPlanner.PlanPage(PageOf(LetterHeight, LetterWidth, 0), 0, TSize.Create(612, 792), TPointF.Create(72, 72),
                                         SettingsOf(TPdfPrintScale.Fit), Unlimited);

  Assert.AreEqual(90, Plan.ViewRotation);
  Assert.AreEqual(612, Plan.RenderSize.cx);
  Assert.AreEqual(792, Plan.RenderSize.cy);
  Assert.AreEqual(TRect.Create(0, 0, 612, 792), Plan.Dest);
end;

procedure TPdfPrintPlannerTests.TestPortraitPageOnLandscapePaperRotates;
begin
  const Plan = TPdfPrintPlanner.PlanPage(PageOf(LetterWidth, LetterHeight, 0), 0, TSize.Create(792, 612), TPointF.Create(72, 72),
                                         SettingsOf(TPdfPrintScale.Fit), Unlimited);

  Assert.AreEqual(90, Plan.ViewRotation);
  Assert.AreEqual(TRect.Create(0, 0, 792, 612), Plan.Dest);
end;

procedure TPdfPrintPlannerTests.TestRotatedPageCountsItsRotation;
begin
  // A portrait box with /Rotate 90 is a landscape page: on portrait paper it is turned back
  const Plan = TPdfPrintPlanner.PlanPage(PageOf(LetterWidth, LetterHeight, 90), 0, TSize.Create(612, 792), TPointF.Create(72, 72),
                                         SettingsOf(TPdfPrintScale.Fit), Unlimited);

  Assert.AreEqual(90, Plan.ViewRotation);
  Assert.AreEqual(612, Plan.RenderSize.cx);
  Assert.AreEqual(792, Plan.RenderSize.cy);
end;

procedure TPdfPrintPlannerTests.TestBandsCoverRenderExactly;
begin
  const MaxBandPixels: Int64 = 1000 * 1000;
  const Plan = TPdfPrintPlanner.PlanPage(PageOf(LetterWidth, LetterHeight, 0), 0, TSize.Create(2550, 3300), TPointF.Create(300, 300),
                                         SettingsOf(TPdfPrintScale.Fit), MaxBandPixels);

  Assert.IsTrue(Length(Plan.Bands) > 1, 'more than one band');
  Assert.AreEqual(0, Plan.Bands[0].Top);
  Assert.AreEqual(Plan.RenderSize.cy, Plan.Bands[High(Plan.Bands)].Bottom);
  for var Index := 0 to High(Plan.Bands) do
  begin
    const Band = Plan.Bands[Index];
    Assert.AreEqual(0, Band.Left, 'full width');
    Assert.AreEqual(Plan.RenderSize.cx, Band.Right, 'full width');
    Assert.IsTrue(Band.Height >= 1);
    Assert.IsTrue(Int64(Band.Width) * Band.Height <= MaxBandPixels, 'within the budget');
    if Index > 0 then
    begin
      Assert.AreEqual(Plan.Bands[Index - 1].Bottom, Band.Top, 'no gap and no overlap');
    end;
  end;
end;

procedure TPdfPrintPlannerTests.TestBandOfOneRowWhenThePageIsWiderThanTheBudget;
begin
  const Plan = TPdfPrintPlanner.PlanPage(PageOf(LetterWidth, LetterHeight, 0), 0, TSize.Create(612, 792), TPointF.Create(72, 72),
                                         SettingsOf(TPdfPrintScale.Fit), 100);

  Assert.AreEqual(792, Integer(Length(Plan.Bands)));
  Assert.AreEqual(1, Plan.Bands[0].Height);
end;

procedure TPdfPrintPlannerTests.TestBandDestMapsProportionally;
begin
  const Plan = TPdfPrintPlanner.PlanPage(PageOf(LetterWidth, LetterHeight, 0), 0, TSize.Create(2550, 3300), TPointF.Create(300, 300),
                                         SettingsOf(TPdfPrintScale.Fit), 1000 * 1000);

  const First = TPdfPrintPlanner.BandDest(Plan, Plan.Bands[0]);
  const Last = TPdfPrintPlanner.BandDest(Plan, Plan.Bands[High(Plan.Bands)]);
  Assert.AreEqual(Plan.Dest.Top, First.Top);
  Assert.AreEqual(Plan.Dest.Bottom, Last.Bottom);
  Assert.AreEqual(Plan.Dest.Left, First.Left);
  Assert.AreEqual(Plan.Dest.Right, First.Right);

  for var Index := 1 to High(Plan.Bands) do
  begin
    Assert.AreEqual(TPdfPrintPlanner.BandDest(Plan, Plan.Bands[Index - 1]).Bottom, TPdfPrintPlanner.BandDest(Plan, Plan.Bands[Index]).Top);
  end;
end;

procedure TPdfPrintPlannerTests.TestBandDestOfClippedPageKeepsTheScale;
begin
  // The page is wider than the paper: the band is drawn at the scale of the whole page, and the target clips it
  const Plan = TPdfPrintPlanner.PlanPage(PageOf(LetterWidth, LetterHeight, 0), 0, TSize.Create(4800, 6800), TPointF.Create(600, 600),
                                         SettingsOf(TPdfPrintScale.ActualSize), Unlimited);

  Assert.AreEqual(1, Integer(Length(Plan.Bands)));
  Assert.AreEqual(Plan.FullDest, TPdfPrintPlanner.BandDest(Plan, Plan.Bands[0]));
end;

procedure TPdfPrintPlannerTests.TestDifferentDpiXY;
begin
  const Plan = TPdfPrintPlanner.PlanPage(PageOf(LetterWidth, LetterHeight, 0), 0, TSize.Create(5400, 6000), TPointF.Create(600, 300),
                                         SettingsOf(TPdfPrintScale.ActualSize), Unlimited);

  Assert.AreEqual(612 * 600 div PointsPerInch, Plan.Dest.Width);
  Assert.AreEqual(792 * 300 div PointsPerInch, Plan.Dest.Height);
  Assert.AreEqual((5400 - 5100) div 2, Plan.Dest.Left);
  Assert.AreEqual((6000 - 3300) div 2, Plan.Dest.Top);
end;

procedure TPdfPrintPlannerTests.TestMaxDpiLimitsTheRender;
begin
  var Settings := SettingsOf(TPdfPrintScale.ActualSize);
  Settings.MaxDpi := 150;
  const Plan = TPdfPrintPlanner.PlanPage(PageOf(LetterWidth, LetterHeight, 0), 0, TSize.Create(5100, 6600), TPointF.Create(600, 600),
                                         Settings, Unlimited);

  Assert.AreEqual(Double(150 / PointsPerInch), Double(Plan.RenderScale), Tolerance);
  Assert.AreEqual(1275, Plan.RenderSize.cx);
  // The render is stretched to the printer pixels
  Assert.AreEqual(5100, Plan.Dest.Width);
end;

procedure TPdfPrintPlannerTests.TestPixelCountsBeyondIntegerDoNotOverflow;
begin
  // A 5 by 5 metre poster at 300 DPI: 59000 by 59000 pixels, 3.5 billion in all
  const Plan = TPdfPrintPlanner.PlanPage(PageOf(14173, 14173, 0), 0, TSize.Create(59000, 59000), TPointF.Create(300, 300),
                                         SettingsOf(TPdfPrintScale.Fit), DefaultMaxBandPixels);

  Assert.IsTrue(Abs(Plan.RenderSize.cx - 59000) <= 1, 'the page fills the paper');
  Assert.IsTrue(Length(Plan.Bands) > 400, 'about 3.5 billion pixels in bands of at most 8 million');
  var Total: Int64 := 0;
  for var Band in Plan.Bands do
  begin
    Assert.IsTrue(Int64(Band.Width) * Band.Height <= DefaultMaxBandPixels);
    Inc(Total, Int64(Band.Width) * Band.Height);
  end;
  Assert.AreEqual(Int64(Plan.RenderSize.cx) * Plan.RenderSize.cy, Total);
end;

procedure TPdfPrintPlannerTests.TestInvalidArgumentsRaise;
begin
  const Page = PageOf(LetterWidth, LetterHeight, 0);
  const Settings = SettingsOf(TPdfPrintScale.Fit);

  Assert.WillRaise(
    procedure
    begin
      TPdfPrintPlanner.PlanPage(Page, 0, TSize.Create(0, 100), TPointF.Create(72, 72), Settings, Unlimited);
    end,
    EArgumentOutOfRangeException);
  Assert.WillRaise(
    procedure
    begin
      TPdfPrintPlanner.PlanPage(Page, 0, TSize.Create(100, 100), TPointF.Create(0, 72), Settings, Unlimited);
    end,
    EArgumentOutOfRangeException);
  Assert.WillRaise(
    procedure
    begin
      TPdfPrintPlanner.PlanPage(Page, 0, TSize.Create(100, 100), TPointF.Create(72, 72), Settings, 0);
    end,
    EArgumentOutOfRangeException);
end;

{ TRecordingPrintTarget }

constructor TRecordingPrintTarget.Create(const Printable: TSize; const Dpi: TPointF);
begin
  inherited Create;
  FLog := TStringList.Create;
  FPrintable := Printable;
  FDpi := Dpi;
end;

destructor TRecordingPrintTarget.Destroy;
begin
  FLog.Free;
  inherited;
end;

function TRecordingPrintTarget.PrintableSize: TSize;
begin
  Result := FPrintable;
end;

function TRecordingPrintTarget.Dpi: TPointF;
begin
  Result := FDpi;
end;

procedure TRecordingPrintTarget.BeginDocument(const Title: string; const Copies: Integer);
begin
  FLog.Add(Format('BeginDocument:%s:%d', [Title, Copies]));
end;

procedure TRecordingPrintTarget.BeginPage;
begin
  FLog.Add('BeginPage');
end;

procedure TRecordingPrintTarget.DrawBand(const Band: TPdfBitmap; const Dest: TRect);
begin
  FLog.Add(Format('DrawBand:%dx%d@%d,%d,%d,%d', [Band.Width, Band.Height, Dest.Left, Dest.Top, Dest.Right, Dest.Bottom]));
  if FFailOnDrawBand then
  begin
    raise EInvalidOpException.Create('The printer is gone');
  end;
end;

procedure TRecordingPrintTarget.EndDocument;
begin
  FLog.Add('EndDocument');
end;

procedure TRecordingPrintTarget.AbortDocument;
begin
  FLog.Add('AbortDocument');
end;

{ TPdfPrintJobTests }

procedure TPdfPrintJobTests.Setup;
begin
  FFake := TFakeViewerSession.Create;
  FSession := FFake;
  FDocument := TTestDocument.Create(nil);
  FTarget := TRecordingPrintTarget.Create(TSize.Create(LetterWidth, LetterHeight), TPointF.Create(PointsPerInch, PointsPerInch));
  FTargetReference := FTarget;
  FProgress := TStringList.Create;
  FDoneCount := 0;
end;

procedure TPdfPrintJobTests.TearDown;
begin
  FJob.Free;
  FJob := nil;
  FProgress.Free;
  FDocument.Free;
  FTargetReference := nil;
  FSession := nil;
end;

procedure TPdfPrintJobTests.OpenLetterPages(const PageCount: Integer; const CanPrint: Boolean);
begin
  var Pages: TArray<TPdfPageInfo>;
  SetLength(Pages, PageCount);
  for var Index := 0 to PageCount - 1 do
  begin
    Pages[Index].CropBox := TPdfRectangle.Letter;
    Pages[Index].Rotation := 0;
    Pages[Index].Label_ := '';
  end;

  var Permissions: TPdfViewerPermissions;
  Permissions.CanPrint := CanPrint;
  Permissions.CanCopy := True;
  FFake.SetOpened(Pages, nil, Permissions);
  FDocument.OpenWithSession(FSession);
end;

function TPdfPrintJobTests.NewJob(const Settings: TPdfPrintSettings): TPdfPrintJob;
begin
  FJob.Free;
  FJob := nil;
  FJob := TPdfPrintJob.Create(FDocument, FTargetReference, Settings);
  // Two bands per Letter page at 72 DPI: 612 by 490 and 612 by 302
  FJob.MaxBandPixels := 300000;
  Result := FJob;
end;

procedure TPdfPrintJobTests.StartJob;
begin
  FJob.Start(
    procedure(const Printed, Total: Integer)
    begin
      FProgress.Add(Format('%d/%d', [Printed, Total]));
    end,
    procedure(const Status: TPdfPrintStatus; const ErrorMessage: string)
    begin
      Inc(FDoneCount);
      FStatus := Status;
      FMessage := ErrorMessage;
    end);
end;

function TPdfPrintJobTests.LogText: string;
begin
  // Items hold commas themselves
  Result := string.Join(';', FTarget.Calls.ToStringArray);
end;

procedure TPdfPrintJobTests.TestJobPrintsPagesInBands;
begin
  OpenLetterPages(2, True);
  var Settings := TPdfPrintSettings.Default;
  Settings.Title := 'Invoice';
  Settings.Copies := 2;
  NewJob(Settings);

  StartJob;
  Assert.IsTrue(FJob.IsRunning);
  // One band at a time
  Assert.AreEqual(1, Integer(FFake.Requests.Count));
  Assert.AreEqual(Ord(TFakeRequestKind.Render), Ord(FFake.Requests[0].Kind));
  Assert.AreEqual(Ord(TPdfJobPriority.Print), Ord(FFake.Requests[0].Priority));
  Assert.AreEqual(0, FFake.Requests[0].PageIndex);
  Assert.AreEqual(TRect.Create(0, 0, 612, 490), FFake.Requests[0].Region);
  Assert.AreEqual(Double(1), Double(FFake.Requests[0].Scale), Tolerance);
  Assert.AreEqual(0, FFake.Requests[0].ViewRotation);

  FFake.CompleteRender(0, $FFFFFFFF);
  Assert.AreEqual(2, Integer(FFake.Requests.Count));
  Assert.AreEqual(TRect.Create(0, 490, 612, 792), FFake.Requests[1].Region);
  FFake.CompleteRender(1, $FFFFFFFF);
  Assert.AreEqual('1/2', FProgress.CommaText);

  Assert.AreEqual(3, Integer(FFake.Requests.Count));
  Assert.AreEqual(1, FFake.Requests[2].PageIndex);
  Assert.AreEqual(Ord(TPdfJobPriority.Print), Ord(FFake.Requests[2].Priority));
  FFake.CompleteRender(2, $FFFFFFFF);
  Assert.IsTrue(FJob.IsRunning);
  FFake.CompleteRender(3, $FFFFFFFF);

  Assert.IsFalse(FJob.IsRunning);
  Assert.AreEqual('1/2,2/2', FProgress.CommaText);
  Assert.AreEqual(1, FDoneCount);
  Assert.AreEqual(Ord(TPdfPrintStatus.Completed), Ord(FStatus));
  Assert.AreEqual('BeginDocument:Invoice:2;BeginPage;DrawBand:612x490@0,0,612,490;DrawBand:612x302@0,490,612,792;' +
                  'BeginPage;DrawBand:612x490@0,0,612,490;DrawBand:612x302@0,490,612,792;EndDocument', LogText);
end;

procedure TPdfPrintJobTests.TestCancelAbortsDocument;
begin
  OpenLetterPages(2, True);
  NewJob(TPdfPrintSettings.Default);
  StartJob;
  FFake.CompleteRender(0, $FFFFFFFF);
  Assert.AreEqual(2, Integer(FFake.Requests.Count));

  FJob.Cancel;

  Assert.IsFalse(FJob.IsRunning);
  Assert.IsTrue(FFake.Requests[1].Cancelled, 'the running request is cancelled');
  Assert.AreEqual(1, FDoneCount);
  Assert.AreEqual(Ord(TPdfPrintStatus.Cancelled), Ord(FStatus));
  Assert.AreEqual('BeginDocument::1;BeginPage;DrawBand:612x490@0,0,612,490;AbortDocument', LogText);

  // Nothing happens afterwards
  FFake.CompleteRender(1, $FFFFFFFF);
  FJob.Cancel;
  Assert.AreEqual(1, FDoneCount);
  Assert.AreEqual(2, Integer(FFake.Requests.Count));
end;

procedure TPdfPrintJobTests.TestRenderFailureFailsJob;
begin
  OpenLetterPages(2, True);
  NewJob(TPdfPrintSettings.Default);
  StartJob;

  FFake.FailRender(0, 'out of memory');

  Assert.IsFalse(FJob.IsRunning);
  Assert.AreEqual(1, FDoneCount);
  Assert.AreEqual(Ord(TPdfPrintStatus.Failed), Ord(FStatus));
  Assert.AreEqual('out of memory', FMessage);
  Assert.AreEqual('BeginDocument::1;BeginPage;AbortDocument', LogText);
  Assert.AreEqual(1, Integer(FFake.Requests.Count), 'no further band is asked for');
  Assert.AreEqual('', FProgress.CommaText);
end;

procedure TPdfPrintJobTests.TestDrawFailureFailsJob;
begin
  OpenLetterPages(1, True);
  NewJob(TPdfPrintSettings.Default);
  FTarget.FailOnDrawBand := True;
  StartJob;

  FFake.CompleteRender(0, $FFFFFFFF);

  Assert.IsFalse(FJob.IsRunning);
  Assert.AreEqual(Ord(TPdfPrintStatus.Failed), Ord(FStatus));
  Assert.AreEqual('The printer is gone', FMessage);
  Assert.AreEqual('BeginDocument::1;BeginPage;DrawBand:612x490@0,0,612,490;AbortDocument', LogText);
  Assert.AreEqual(1, Integer(FFake.Requests.Count));
end;

procedure TPdfPrintJobTests.TestJobWithoutPrintPermissionRaises;
begin
  OpenLetterPages(1, False);

  Assert.WillRaise(
    procedure
    begin
      TPdfPrintJob.Create(FDocument, FTargetReference, TPdfPrintSettings.Default).Free;
    end,
    EInvalidOpException);
  Assert.AreEqual(0, FTarget.Calls.Count);
end;

procedure TPdfPrintJobTests.TestIgnorePermissionsAllowsPrinting;
begin
  OpenLetterPages(1, False);
  FDocument.IgnorePermissions := True;

  NewJob(TPdfPrintSettings.Default);
  StartJob;

  Assert.IsTrue(FJob.IsRunning);
end;

procedure TPdfPrintJobTests.TestDestroyWhileRunningAborts;
begin
  OpenLetterPages(2, True);
  NewJob(TPdfPrintSettings.Default);
  StartJob;

  FJob.Free;
  FJob := nil;

  Assert.IsTrue(FFake.Requests[0].Cancelled);
  Assert.AreEqual('BeginDocument::1;BeginPage;AbortDocument', LogText);
  FFake.CompleteRender(0, $FFFFFFFF);
  Assert.AreEqual(0, FDoneCount, 'no callback');
  Assert.AreEqual('', FProgress.CommaText);
  Assert.AreEqual(1, Integer(FFake.Requests.Count));
end;

procedure TPdfPrintJobTests.TestRangeCurrentPrintsTheCurrentPage;
begin
  OpenLetterPages(3, True);
  FDocument.CurrentPage := 1;
  var Settings := TPdfPrintSettings.Default;
  Settings.RangeKind := TPdfPrintRangeKind.Current;
  NewJob(Settings);

  StartJob;

  Assert.AreEqual(1, FFake.Requests[0].PageIndex);
  FFake.CompleteRender(0, $FFFFFFFF);
  FFake.CompleteRender(1, $FFFFFFFF);
  Assert.AreEqual('1/1', FProgress.CommaText);
  Assert.AreEqual(Ord(TPdfPrintStatus.Completed), Ord(FStatus));
end;

procedure TPdfPrintJobTests.TestClosingTheDocumentFailsTheJob;
begin
  OpenLetterPages(2, True);
  NewJob(TPdfPrintSettings.Default);
  StartJob;

  FDocument.Close;

  Assert.IsFalse(FJob.IsRunning);
  Assert.AreEqual(1, FDoneCount);
  Assert.AreEqual(Ord(TPdfPrintStatus.Failed), Ord(FStatus));
  Assert.IsTrue(FMessage <> '');
  Assert.AreEqual('BeginDocument::1;BeginPage;AbortDocument', LogText);
end;

procedure TPdfPrintJobTests.TestBandsOutsideThePaperAreNotRendered;
begin
  // Letter at actual size on a paper that is 100 points wide and 300 points high: the bottom bands lie below the paper
  FTarget.FPrintable := TSize.Create(612, 300);
  OpenLetterPages(1, True);
  var Settings := TPdfPrintSettings.Default;
  Settings.Scale := TPdfPrintScale.ActualSize;
  NewJob(Settings);
  FJob.MaxBandPixels := 100 * 612;
  StartJob;

  // The page is centred at -246 .. 546: the bands with rows 0..99 and 100..199 are above the paper or on it
  var Count := 0;
  while FJob.IsRunning and (Count < 20) do
  begin
    FFake.CompleteRender(FFake.Requests.Count - 1, $FFFFFFFF);
    Inc(Count);
  end;

  Assert.AreEqual(Ord(TPdfPrintStatus.Completed), Ord(FStatus));
  // 8 bands of 100 rows; the paper shows page rows 246 to 546: bands 2 to 5
  Assert.AreEqual(4, Count);
end;

procedure TPdfPrintJobTests.TestInvalidRangeRaisesInCreate;
begin
  OpenLetterPages(2, True);
  var Settings := TPdfPrintSettings.Default;
  Settings.RangeKind := TPdfPrintRangeKind.Pages;
  Settings.FromPage := 1;
  Settings.ToPage := 3;

  Assert.WillRaise(
    procedure
    begin
      TPdfPrintJob.Create(FDocument, FTargetReference, Settings).Free;
    end,
    EArgumentOutOfRangeException);
end;

end.
