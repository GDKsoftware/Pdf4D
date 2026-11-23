// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Vcl.SearchBar.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.Types,
  System.SysUtils,
  System.UITypes,
  Vcl.Graphics,
  DUnitX.TestFramework,
  Pdf4D.Viewer.Types,
  Pdf4D.Tests.VclHost;

type
  TColorPredicate = reference to function(const Pixel: TVclPixel): Boolean;

  [TestFixture]
  TPdf4DSearchBarTests = class
  private
    FHost: TVclTestHost;

    // Types the query and presses Enter
    procedure Search(const Query: string);
    function WaitForCaption(const Caption: string): Boolean;
    // The pixels that the page view paints around the quads of a hit
    function HitBounds(const Hit: TPdfSearchHit): TRect;
    function HasPixel(const Bitmap: Vcl.Graphics.TBitmap; const Area: TRect; const Predicate: TColorPredicate): Boolean;
    class function IsHitColor(const Pixel: TVclPixel): Boolean; static;
    class function IsCurrentHitColor(const Pixel: TVclPixel): Boolean; static;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestSearchBarFindsAndCounts;

    [Test]
    procedure TestSearchBarNoResults;

    [Test]
    procedure TestEscapeClearsSearch;

    [Test]
    procedure TestShiftEnterGoesBack;

    [Test]
    procedure TestSearchBarScrollsToHit;

    [Test]
    procedure TestButtonsStepThroughHits;

    [Test]
    procedure TestEmptyQueryClearsSearch;

    [Test]
    procedure TestSearchBarMadeInCodeScalesWithItsParent;
  end;

implementation

uses
  System.Math,
  Winapi.Windows,
  Vcl.Controls,
  Pdf4D.Vcl.SearchBar,
  Pdf4D.Viewer.ResourceStrings,
  Pdf4D.Tests.ViewerDocuments;

const
  ViewWidth = 800;
  ViewHeight = 600;
  HighDpi = 144;
  LogicalPixelsPerInch = 96;
  LogicalEditWidth = 200;
  LogicalBarHeight = 28;
  InvoiceNumber = '2024-0815';
  HitMargin = 2;
  // 40 percent of $FFD700 over white
  HitGreenLow = 225;
  HitBlueLow = 140;
  HitBlueHigh = 175;
  // 60 percent of $FF8C00 over white
  CurrentGreenLow = 170;
  CurrentGreenHigh = 200;
  CurrentBlueLow = 90;
  CurrentBlueHigh = 120;
  RedHigh = 250;

{ TPdf4DSearchBarTests }

procedure TPdf4DSearchBarTests.Setup;
begin
  FHost := TVclTestHost.Create(ViewWidth, ViewHeight);
  FHost.AddSearchBar;
end;

procedure TPdf4DSearchBarTests.TearDown;
begin
  FreeAndNil(FHost);
end;

procedure TPdf4DSearchBarTests.Search(const Query: string);
begin
  FHost.SearchBar.EditQuery.Text := Query;
  FHost.PressKeyOn(FHost.SearchBar.EditQuery, VK_RETURN);
end;

function TPdf4DSearchBarTests.WaitForCaption(const Caption: string): Boolean;
begin
  Result := FHost.WaitUntil(
    function: Boolean
    begin
      Result := (FHost.SearchBar.LabelResult.Caption = Caption);
    end);
end;

function TPdf4DSearchBarTests.HitBounds(const Hit: TPdfSearchHit): TRect;
begin
  var IsFirst := True;
  Result := TRect.Empty;
  for var Quad in Hit.Quads do
  begin
    for var Corner in [Quad.P1, Quad.P2, Quad.P3, Quad.P4] do
    begin
      const Point = FHost.PagePointToClient(Hit.PageIndex, Corner);
      if IsFirst then
      begin
        Result := TRect.Create(Point, Point);
        IsFirst := False;
      end
      else
      begin
        Result.Left := Min(Result.Left, Point.X);
        Result.Top := Min(Result.Top, Point.Y);
        Result.Right := Max(Result.Right, Point.X);
        Result.Bottom := Max(Result.Bottom, Point.Y);
      end;
    end;
  end;
  Result.Inflate(HitMargin, HitMargin);
end;

function TPdf4DSearchBarTests.HasPixel(const Bitmap: Vcl.Graphics.TBitmap; const Area: TRect; const Predicate: TColorPredicate): Boolean;
begin
  Result := False;
  for var Y := Max(Area.Top, 0) to Min(Area.Bottom, Bitmap.Height - 1) do
  begin
    for var X := Max(Area.Left, 0) to Min(Area.Right, Bitmap.Width - 1) do
    begin
      if Predicate(TVclTestHost.PixelAt(Bitmap, X, Y)) then
      begin
        Exit(True);
      end;
    end;
  end;
end;

class function TPdf4DSearchBarTests.IsHitColor(const Pixel: TVclPixel): Boolean;
begin
  Result := (Pixel.R >= RedHigh) and (Pixel.G >= HitGreenLow) and (Pixel.G < RedHigh) and
            (Pixel.B >= HitBlueLow) and (Pixel.B <= HitBlueHigh);
end;

class function TPdf4DSearchBarTests.IsCurrentHitColor(const Pixel: TVclPixel): Boolean;
begin
  Result := (Pixel.R >= RedHigh) and (Pixel.G >= CurrentGreenLow) and (Pixel.G <= CurrentGreenHigh) and
            (Pixel.B >= CurrentBlueLow) and (Pixel.B <= CurrentBlueHigh);
end;

procedure TPdf4DSearchBarTests.TestSearchBarFindsAndCounts;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Invoice), 'the document opens: ' + FHost.OpenErrorMessage);
  Assert.IsTrue(FHost.WaitForVisibleTiles, 'the tiles arrive');

  Search(InvoiceNumber);

  Assert.IsTrue(WaitForCaption(Format(SSearchResultCount, [1, 2])), 'one of two: ' + FHost.SearchBar.LabelResult.Caption);
  Assert.IsTrue(FHost.WaitUntil(
    function: Boolean
    begin
      Result := not FHost.Document.IsSearching;
    end), 'the search ends');

  FHost.PressKeyOn(FHost.SearchBar.EditQuery, VK_RETURN);
  Assert.AreEqual(Format(SSearchResultCount, [2, 2]), FHost.SearchBar.LabelResult.Caption, 'Enter goes to the next hit');

  Assert.IsTrue(FHost.WaitForVisibleTiles, 'the tiles arrive');
  const Hits = FHost.Document.SearchHits;
  Assert.AreEqual<Integer>(2, Length(Hits));
  const Bitmap = FHost.Snapshot;
  try
    Assert.IsTrue(HasPixel(Bitmap, HitBounds(Hits[0]), IsHitColor), 'the first hit has the colour of a hit');
    Assert.IsTrue(HasPixel(Bitmap, HitBounds(Hits[1]), IsCurrentHitColor), 'the current hit has its own colour');
  finally
    Bitmap.Free;
  end;
end;

procedure TPdf4DSearchBarTests.TestSearchBarNoResults;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Invoice), 'the document opens: ' + FHost.OpenErrorMessage);

  Search('xyz');

  Assert.IsTrue(WaitForCaption(SSearchNoResults), 'no results: ' + FHost.SearchBar.LabelResult.Caption);
end;

procedure TPdf4DSearchBarTests.TestEscapeClearsSearch;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Invoice), 'the document opens: ' + FHost.OpenErrorMessage);
  Assert.IsTrue(FHost.WaitForVisibleTiles, 'the tiles arrive');
  Search(InvoiceNumber);
  Assert.IsTrue(WaitForCaption(Format(SSearchResultCount, [1, 2])), 'the hits arrive');
  const Hits = FHost.Document.SearchHits;
  const Area = HitBounds(Hits[0]);

  FHost.PressKeyOn(FHost.SearchBar.EditQuery, VK_ESCAPE);
  FHost.Pump(1);

  Assert.AreEqual('', FHost.SearchBar.EditQuery.Text, 'the query is gone');
  Assert.AreEqual('', FHost.SearchBar.LabelResult.Caption, 'the result is gone');
  Assert.AreEqual<Integer>(0, Length(FHost.Document.SearchHits), 'the document has no hits');
  const Bitmap = FHost.Snapshot;
  try
    Assert.IsFalse(HasPixel(Bitmap, Area, IsHitColor) or HasPixel(Bitmap, Area, IsCurrentHitColor), 'the page view draws no hits');
  finally
    Bitmap.Free;
  end;
end;

procedure TPdf4DSearchBarTests.TestShiftEnterGoesBack;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Invoice), 'the document opens: ' + FHost.OpenErrorMessage);
  Search(InvoiceNumber);
  Assert.IsTrue(WaitForCaption(Format(SSearchResultCount, [1, 2])), 'the hits arrive');

  FHost.PressKeyOn(FHost.SearchBar.EditQuery, VK_RETURN, [ssShift]);

  Assert.AreEqual(Format(SSearchResultCount, [2, 2]), FHost.SearchBar.LabelResult.Caption, 'Shift+Enter wraps to the last hit');
end;

procedure TPdf4DSearchBarTests.TestSearchBarScrollsToHit;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Invoice), 'the document opens: ' + FHost.OpenErrorMessage);
  Assert.IsTrue(FHost.WaitForVisibleTiles, 'the tiles arrive');
  Assert.AreEqual(0, FHost.PageView.Controller.ScrollPosition.Y, 'the view is at the top');

  Search('Bedrag');

  Assert.IsTrue(WaitForCaption(Format(SSearchResultCount, [1, 1])), 'the hit arrives');
  Assert.AreEqual(1, FHost.Document.CurrentPage, 'the page of the hit is current');
  Assert.IsTrue(FHost.PageView.Controller.ScrollPosition.Y > 0, 'the page view scrolled to the hit');
end;

procedure TPdf4DSearchBarTests.TestButtonsStepThroughHits;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Invoice), 'the document opens: ' + FHost.OpenErrorMessage);
  Search(InvoiceNumber);
  Assert.IsTrue(WaitForCaption(Format(SSearchResultCount, [1, 2])), 'the hits arrive');

  FHost.SearchBar.ButtonNext.Click;
  Assert.AreEqual(Format(SSearchResultCount, [2, 2]), FHost.SearchBar.LabelResult.Caption, 'next');

  FHost.SearchBar.ButtonPrior.Click;
  Assert.AreEqual(Format(SSearchResultCount, [1, 2]), FHost.SearchBar.LabelResult.Caption, 'prior');
end;

procedure TPdf4DSearchBarTests.TestEmptyQueryClearsSearch;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Invoice), 'the document opens: ' + FHost.OpenErrorMessage);
  Search(InvoiceNumber);
  Assert.IsTrue(WaitForCaption(Format(SSearchResultCount, [1, 2])), 'the hits arrive');

  Search('');

  Assert.AreEqual('', FHost.SearchBar.LabelResult.Caption, 'the result is gone');
  Assert.AreEqual<Integer>(0, Length(FHost.Document.SearchHits), 'the document has no hits');
end;

// The bar lays itself out in logical pixels; VCL scales a control that gets a parent of another resolution
procedure TPdf4DSearchBarTests.TestSearchBarMadeInCodeScalesWithItsParent;
begin
  FHost.Form.ScaleForPPI(HighDpi);
  const Bar = TPdf4DSearchBar.Create(nil);
  try
    Bar.Parent := FHost.Form;

    Assert.AreEqual(MulDiv(LogicalBarHeight, HighDpi, LogicalPixelsPerInch), Bar.Height, 'the bar');
    Assert.AreEqual(MulDiv(LogicalEditWidth, HighDpi, LogicalPixelsPerInch), Bar.EditQuery.Width, 'the query field');
  finally
    Bar.Free;
  end;
end;

end.
