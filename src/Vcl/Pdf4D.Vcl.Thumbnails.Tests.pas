// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Vcl.Thumbnails.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Vcl.Graphics,
  DUnitX.TestFramework,
  Pdf4D.Tests.VclHost;

type
  [TestFixture]
  TPdf4DThumbnailsTests = class
  private
    FHost: TVclTestHost;

    function CountFramePixels(const Bitmap: Vcl.Graphics.TBitmap; const Top, Bottom: Integer): Integer;

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
    procedure TestColorIsTheBackground;

    // A long document that opens while the thumbnails are shown gives them a scroll bar at once
    [Test]
    procedure TestScrollBarFollowsContent;
  end;

implementation

uses
  System.Math,
  System.UITypes,
  Winapi.Windows,
  Pdf4D.Tests.ViewerDocuments;

const
  ViewWidth = 800;
  ViewHeight = 600;
  ThumbnailsWidth = 150;
  // The first thumbnail of a Letter page 120 pixels wide takes the rows up to this one, label included; the second begins after it
  FirstCellBottom = 180;
  SecondThumbnailRow = 250;
  FrameBlue: TVclPixel = (R: 30; G: 144; B: 255);
  FrameTolerance = 40;
  BackgroundRed: TColor = $000000FF;
  LongDocumentPages = 50;
  PageWidth = 612;
  PageHeight = 792;

{ TPdf4DThumbnailsTests }

procedure TPdf4DThumbnailsTests.Setup;
begin
  FHost := TVclTestHost.Create(ViewWidth, ViewHeight);
  FHost.AddThumbnails(ThumbnailsWidth);
end;

procedure TPdf4DThumbnailsTests.TearDown;
begin
  FreeAndNil(FHost);
end;

function TPdf4DThumbnailsTests.CountFramePixels(const Bitmap: Vcl.Graphics.TBitmap; const Top, Bottom: Integer): Integer;
begin
  Result := 0;
  for var Y := Top to Min(Bottom, Bitmap.Height - 1) do
  begin
    for var X := 0 to Bitmap.Width - 1 do
    begin
      const Pixel = TVclTestHost.PixelAt(Bitmap, X, Y);
      const Distance = Abs(Pixel.R - FrameBlue.R) + Abs(Pixel.G - FrameBlue.G) + Abs(Pixel.B - FrameBlue.B);
      if Distance < FrameTolerance then
      begin
        Inc(Result);
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

  FHost.ClickOn(FHost.Thumbnails, ThumbnailsWidth div 2, SecondThumbnailRow);
  FHost.Pump(1);

  Assert.AreEqual(1, FHost.Document.CurrentPage, 'the page of the thumbnail is current');
  Assert.IsTrue(FHost.PageView.Controller.ScrollPosition.Y > 0, 'the page view scrolled to the second page');
end;

procedure TPdf4DThumbnailsTests.TestThumbnailsFollowCurrentPage;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Invoice), 'the document opens: ' + FHost.OpenErrorMessage);
  FHost.Pump(1);

  var Bitmap := FHost.SnapshotOf(FHost.Thumbnails);
  try
    Assert.IsTrue(CountFramePixels(Bitmap, 0, FirstCellBottom - 1) > 0, 'the first thumbnail has the frame');
    Assert.AreEqual(0, CountFramePixels(Bitmap, FirstCellBottom, Bitmap.Height), 'the second thumbnail has none');
  finally
    Bitmap.Free;
  end;

  FHost.Document.CurrentPage := 1;
  FHost.Pump(1);

  Bitmap := FHost.SnapshotOf(FHost.Thumbnails);
  try
    Assert.AreEqual(0, CountFramePixels(Bitmap, 0, FirstCellBottom - 1), 'the first thumbnail lost the frame');
    Assert.IsTrue(CountFramePixels(Bitmap, FirstCellBottom, Bitmap.Height) > 0, 'the second thumbnail has the frame');
  finally
    Bitmap.Free;
  end;
end;

procedure TPdf4DThumbnailsTests.TestColorIsTheBackground;
begin
  FHost.Thumbnails.Color := BackgroundRed;
  FHost.Pump(1);

  const Bitmap = FHost.SnapshotOf(FHost.Thumbnails);
  try
    const Pixel = TVclTestHost.PixelAt(Bitmap, 1, 1);
    Assert.AreEqual(255, Integer(Pixel.R), 'red');
    Assert.AreEqual(0, Integer(Pixel.G), 'no green');
    Assert.AreEqual(0, Integer(Pixel.B), 'no blue');
  finally
    Bitmap.Free;
  end;
end;

procedure TPdf4DThumbnailsTests.TestScrollBarFollowsContent;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Pages(LongDocumentPages, PageWidth, PageHeight, 0)), 'the document opens: ' + FHost.OpenErrorMessage);
  FHost.Pump(1);

  const Style = GetWindowLong(FHost.Thumbnails.Handle, GWL_STYLE);
  Assert.IsTrue((Style and WS_VSCROLL) <> 0, 'the thumbnails show their scroll bar for the pages of a long document');
end;

end.
