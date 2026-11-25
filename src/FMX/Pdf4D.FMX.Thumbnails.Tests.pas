// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.FMX.Thumbnails.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  System.SysUtils,
  System.UITypes,
  FMX.Graphics,
  DUnitX.TestFramework,
  Pdf4D.Tests.FmxHost;

type
  [TestFixture]
  TPdf4DThumbnailsTests = class
  private
    FHost: TFmxTestHost;

    procedure MakeHost(const Scale: Single);
    function CountFramePixels(const Bitmap: FMX.Graphics.TBitmap; const Top, Bottom: Integer): Integer;
    // Until the first thumbnails are in the cache and no more arrive
    function WaitForThumbnails: Boolean;
    function CacheCostAt(const Scale: Single): Int64;
    // The longest row of white pixels in the rows from Top: the width of a thumbnail
    function WidestWhiteRun(const Bitmap: FMX.Graphics.TBitmap; const Top: Integer): Integer;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestThumbnailClickNavigates;

    [Test]
    procedure TestThumbnailsFollowCurrentPage;

    [Test]
    procedure TestBackgroundColorIsTheBackground;

    [Test]
    procedure TestThumbnailsAt150Percent;

    [Test]
    procedure TestScrollBarFollowsContent;
  end;

implementation

uses
  System.Math,
  System.Diagnostics,
  FMX.Types,
  Pdf4D.Tests.ViewerDocuments;

const
  ViewWidth = 800;
  ViewHeight = 600;
  ThumbnailsWidth = 150;
  LogicalThumbnailWidth = 120;
  Scale150 = 1.5;
  // The first thumbnail of a Letter page 120 units wide takes the rows up to this one, label included; the second begins after it
  FirstCellBottom = 180;
  SecondThumbnailRow = 250;
  FrameRed = 30;
  FrameGreen = 144;
  FrameBlue = 255;
  FrameTolerance = 40;
  BackgroundRed = TAlphaColors.Red;
  WhiteChannel = 250;
  WidthTolerance = 2;
  // Rendered at 1.5 times the width and the height, the pixels of a thumbnail are 2.25 times as many
  CostRatioLow = 2.15;
  CostRatioHigh = 2.35;
  StableMilliseconds = 200;
  ManyPages = 40;
  PageWidth = 612;
  PageHeight = 792;

{ TPdf4DThumbnailsTests }

procedure TPdf4DThumbnailsTests.MakeHost(const Scale: Single);
begin
  FreeAndNil(FHost);
  FHost := TFmxTestHost.Create(ViewWidth, ViewHeight, Scale);
  FHost.AddThumbnails(ThumbnailsWidth);
  FHost.AddPageView;
end;

procedure TPdf4DThumbnailsTests.Setup;
begin
  MakeHost(1);
end;

procedure TPdf4DThumbnailsTests.TearDown;
begin
  FreeAndNil(FHost);
end;

function TPdf4DThumbnailsTests.CountFramePixels(const Bitmap: FMX.Graphics.TBitmap; const Top, Bottom: Integer): Integer;
begin
  Result := 0;
  for var Y := Top to Min(Bottom, Bitmap.Height - 1) do
  begin
    for var X := 0 to Bitmap.Width - 1 do
    begin
      const Pixel = TAlphaColorRec(TFmxTestHost.PixelAt(Bitmap, X, Y));
      const Distance = Abs(Pixel.R - FrameRed) + Abs(Pixel.G - FrameGreen) + Abs(Pixel.B - FrameBlue);
      if Distance < FrameTolerance then
      begin
        Inc(Result);
      end;
    end;
  end;
end;

function TPdf4DThumbnailsTests.WaitForThumbnails: Boolean;
begin
  Result := FHost.WaitUntil(
    function: Boolean
    begin
      Result := FHost.Thumbnails.Controller.CacheCost > 0;
    end);

  // The next thumbnails come after the first
  var Cost := FHost.Thumbnails.Controller.CacheCost;
  var Watch := TStopwatch.StartNew;
  while Watch.ElapsedMilliseconds < StableMilliseconds do
  begin
    FHost.Pump(1);
    if FHost.Thumbnails.Controller.CacheCost <> Cost then
    begin
      Cost := FHost.Thumbnails.Controller.CacheCost;
      Watch := TStopwatch.StartNew;
    end;
  end;
end;

function TPdf4DThumbnailsTests.CacheCostAt(const Scale: Single): Int64;
begin
  MakeHost(Scale);
  Assert.IsTrue(FHost.Open(TViewerDocuments.Invoice), 'the document opens: ' + FHost.OpenErrorMessage);
  Assert.IsTrue(WaitForThumbnails, 'the thumbnails arrive');
  Result := FHost.Thumbnails.Controller.CacheCost;
end;

function TPdf4DThumbnailsTests.WidestWhiteRun(const Bitmap: FMX.Graphics.TBitmap; const Top: Integer): Integer;
begin
  Result := 0;
  for var Y := Top to Bitmap.Height - 1 do
  begin
    var Run := 0;
    for var X := 0 to Bitmap.Width - 1 do
    begin
      const Pixel = TAlphaColorRec(TFmxTestHost.PixelAt(Bitmap, X, Y));
      if (Pixel.R >= WhiteChannel) and (Pixel.G >= WhiteChannel) and (Pixel.B >= WhiteChannel) then
      begin
        Inc(Run);
        Result := Max(Result, Run);
      end
      else
      begin
        Run := 0;
      end;
    end;
  end;
end;

procedure TPdf4DThumbnailsTests.TestThumbnailClickNavigates;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Invoice), 'the document opens: ' + FHost.OpenErrorMessage);
  Assert.IsTrue(FHost.WaitForVisibleTiles, 'the tiles arrive');
  Assert.AreEqual(0, FHost.Document.CurrentPage, 'the first page is current');
  Assert.AreEqual(0, FHost.PageView.Controller.ScrollPosition.Y, 'the page view is at the top');

  FHost.Thumbnails.HandleClick(TPointF.Create(ThumbnailsWidth div 2, SecondThumbnailRow));
  FHost.Pump(1);

  Assert.AreEqual(1, FHost.Document.CurrentPage, 'the page of the thumbnail is current');
  Assert.IsTrue(FHost.PageView.Controller.ScrollPosition.Y > 0, 'the page view scrolled to the second page');
end;

procedure TPdf4DThumbnailsTests.TestThumbnailsFollowCurrentPage;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Invoice), 'the document opens: ' + FHost.OpenErrorMessage);
  FHost.Pump(1);

  var Bitmap := TFmxTestHost.SnapshotOf(FHost.Thumbnails);
  try
    Assert.IsTrue(CountFramePixels(Bitmap, 0, FirstCellBottom - 1) > 0, 'the first thumbnail has the frame');
    Assert.AreEqual(0, CountFramePixels(Bitmap, FirstCellBottom, Bitmap.Height), 'the second thumbnail has none');
  finally
    Bitmap.Free;
  end;

  FHost.Document.CurrentPage := 1;
  FHost.Pump(1);

  Bitmap := TFmxTestHost.SnapshotOf(FHost.Thumbnails);
  try
    Assert.AreEqual(0, CountFramePixels(Bitmap, 0, FirstCellBottom - 1), 'the first thumbnail lost the frame');
    Assert.IsTrue(CountFramePixels(Bitmap, FirstCellBottom, Bitmap.Height) > 0, 'the second thumbnail has the frame');
  finally
    Bitmap.Free;
  end;
end;

procedure TPdf4DThumbnailsTests.TestBackgroundColorIsTheBackground;
begin
  FHost.Thumbnails.BackgroundColor := BackgroundRed;
  FHost.Pump(1);

  const Bitmap = TFmxTestHost.SnapshotOf(FHost.Thumbnails);
  try
    const Pixel = TAlphaColorRec(TFmxTestHost.PixelAt(Bitmap, 1, 1));
    Assert.AreEqual(255, Integer(Pixel.R), 'red');
    Assert.AreEqual(0, Integer(Pixel.G), 'no green');
    Assert.AreEqual(0, Integer(Pixel.B), 'no blue');
  finally
    Bitmap.Free;
  end;
end;

// The thumbnails are rendered for the pixels of the screen: 120 units wide are 180 pixels on 150 percent
procedure TPdf4DThumbnailsTests.TestThumbnailsAt150Percent;
begin
  const CostAtOne = CacheCostAt(1);
  const CostAtOneAndAHalf = CacheCostAt(Scale150);
  Assert.IsTrue(CostAtOne > 0, 'thumbnails at 100 percent');
  const Ratio = CostAtOneAndAHalf / CostAtOne;
  Assert.IsTrue((Ratio >= CostRatioLow) and (Ratio <= CostRatioHigh), Format('the images take 2.25 times the pixels, got %.2f', [Ratio]));

  // The second thumbnail has no frame: its white page is as wide as the thumbnail
  const Bitmap = TFmxTestHost.SnapshotOf(FHost.Thumbnails);
  try
    const ExpectedWidth = Round(LogicalThumbnailWidth * Scale150);
    const Width = WidestWhiteRun(Bitmap, Round(FirstCellBottom * Scale150));
    Assert.IsTrue(Abs(Width - ExpectedWidth) <= WidthTolerance, Format('a thumbnail is %d pixels wide, got %d', [ExpectedWidth, Width]));
  finally
    Bitmap.Free;
  end;
end;

procedure TPdf4DThumbnailsTests.TestScrollBarFollowsContent;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Pages(ManyPages, PageWidth, PageHeight, 0)), 'the document opens: ' + FHost.OpenErrorMessage);
  FHost.Pump(1);
  Assert.IsTrue(FHost.Thumbnails.VScrollBar.Visible, Format('max %f vp %f c %d', [FHost.Thumbnails.VScrollBar.Max, FHost.Thumbnails.VScrollBar.ViewportSize, FHost.Thumbnails.Controller.ContentSize.cy]));
  Assert.IsTrue(FHost.Thumbnails.VScrollBar.Max > ViewHeight, 'the range is the content');

  FHost.Thumbnails.VScrollBar.Value := SecondThumbnailRow;
  Assert.AreEqual(SecondThumbnailRow, FHost.Thumbnails.Controller.ScrollPosition.Y, 'dragging the bar scrolls the thumbnails');

  FHost.Thumbnails.HandleWheel(-120);
  Assert.IsTrue(FHost.Thumbnails.Controller.ScrollPosition.Y > SecondThumbnailRow, 'the wheel scrolls down');
end;

end.
