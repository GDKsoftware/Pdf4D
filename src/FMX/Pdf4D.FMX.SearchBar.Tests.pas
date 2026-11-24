// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.FMX.SearchBar.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.Types,
  System.SysUtils,
  System.UITypes,
  FMX.Graphics,
  FMX.StdCtrls,
  DUnitX.TestFramework,
  Pdf4D.Viewer.Types,
  Pdf4D.Tests.FmxHost;

type
  TColorPredicate = reference to function(const Pixel: TAlphaColorRec): Boolean;

  [TestFixture]
  TPdf4DSearchBarTests = class
  private
    FHost: TFmxTestHost;

    procedure MakeHost(const Scale: Single);
    // Types the query and presses Enter
    procedure Search(const Query: string);
    procedure ClickButton(const Button: TSpeedButton);
    function WaitForCaption(const Caption: string): Boolean;
    // The pixels that the page view paints around the quads of a hit
    function HitBounds(const Hit: TPdfSearchHit): TRect;
    function HasPixel(const Bitmap: FMX.Graphics.TBitmap; const Area: TRect; const Predicate: TColorPredicate): Boolean;
    class function IsHitColor(const Pixel: TAlphaColorRec): Boolean; static;
    class function IsCurrentHitColor(const Pixel: TAlphaColorRec): Boolean; static;

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
    procedure TestCappedSearchShowsAPlus;

    [Test]
    procedure TestFocusQueryFocusesTheEdit;

    [Test]
    procedure TestSearchBarAt150Percent;
  end;

implementation

uses
  System.Math,
  FMX.Types,
  Pdf4D.Viewer.ResourceStrings,
  Pdf4D.FMX.PageView.Tests,
  Pdf4D.Tests.ViewerDocuments;

type
  TButtonCracker = class(TSpeedButton);

const
  ViewWidth = 800;
  ViewHeight = 600;
  Scale150 = 1.5;
  InvoiceNumber = '2024-0815';
  HitMargin = 2;
  EnterChar = #13;
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

procedure TPdf4DSearchBarTests.MakeHost(const Scale: Single);
begin
  FreeAndNil(FHost);
  FHost := TFmxTestHost.Create(ViewWidth, ViewHeight, Scale);
  FHost.AddSearchBar;
  FHost.AddPageView;
end;

procedure TPdf4DSearchBarTests.Setup;
begin
  MakeHost(1);
end;

procedure TPdf4DSearchBarTests.TearDown;
begin
  FreeAndNil(FHost);
end;

// Click is protected; a click of the mouse comes down to it
procedure TPdf4DSearchBarTests.ClickButton(const Button: TSpeedButton);
begin
  TButtonCracker(Button).Click;
end;

procedure TPdf4DSearchBarTests.Search(const Query: string);
begin
  FHost.SearchBar.EditQuery.Text := Query;
  FHost.PressKeyOn(FHost.SearchBar.EditQuery, vkReturn, [], EnterChar);
end;

function TPdf4DSearchBarTests.WaitForCaption(const Caption: string): Boolean;
begin
  Result := FHost.WaitUntil(
    function: Boolean
    begin
      Result := (FHost.SearchBar.LabelResult.Text = Caption);
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
      const Point = FHost.PagePointToDevice(Hit.PageIndex, Corner);
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

function TPdf4DSearchBarTests.HasPixel(const Bitmap: FMX.Graphics.TBitmap; const Area: TRect; const Predicate: TColorPredicate): Boolean;
begin
  Result := False;
  const Reader = TPixelReader.Create(Bitmap);
  try
    for var Y := Max(Area.Top, 0) to Min(Area.Bottom, Bitmap.Height - 1) do
    begin
      for var X := Max(Area.Left, 0) to Min(Area.Right, Bitmap.Width - 1) do
      begin
        if Predicate(Reader.Pixel(X, Y)) then
        begin
          Exit(True);
        end;
      end;
    end;
  finally
    Reader.Free;
  end;
end;

class function TPdf4DSearchBarTests.IsHitColor(const Pixel: TAlphaColorRec): Boolean;
begin
  Result := (Pixel.R >= RedHigh) and (Pixel.G >= HitGreenLow) and (Pixel.G < RedHigh) and
            (Pixel.B >= HitBlueLow) and (Pixel.B <= HitBlueHigh);
end;

class function TPdf4DSearchBarTests.IsCurrentHitColor(const Pixel: TAlphaColorRec): Boolean;
begin
  Result := (Pixel.R >= RedHigh) and (Pixel.G >= CurrentGreenLow) and (Pixel.G <= CurrentGreenHigh) and
            (Pixel.B >= CurrentBlueLow) and (Pixel.B <= CurrentBlueHigh);
end;

procedure TPdf4DSearchBarTests.TestSearchBarFindsAndCounts;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Invoice), 'the document opens: ' + FHost.OpenErrorMessage);
  Assert.IsTrue(FHost.WaitForVisibleTiles, 'the tiles arrive');

  Search(InvoiceNumber);

  Assert.IsTrue(WaitForCaption(Format(SSearchResultCount, [1, 2])), 'one of two: ' + FHost.SearchBar.LabelResult.Text);
  Assert.IsTrue(FHost.WaitUntil(
    function: Boolean
    begin
      Result := not FHost.Document.IsSearching;
    end), 'the search ends');

  FHost.PressKeyOn(FHost.SearchBar.EditQuery, vkReturn, [], EnterChar);
  Assert.AreEqual(Format(SSearchResultCount, [2, 2]), FHost.SearchBar.LabelResult.Text, 'Enter goes to the next hit');

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

  Assert.IsTrue(WaitForCaption(SSearchNoResults), 'no results: ' + FHost.SearchBar.LabelResult.Text);
end;

procedure TPdf4DSearchBarTests.TestEscapeClearsSearch;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Invoice), 'the document opens: ' + FHost.OpenErrorMessage);
  Assert.IsTrue(FHost.WaitForVisibleTiles, 'the tiles arrive');
  Search(InvoiceNumber);
  Assert.IsTrue(WaitForCaption(Format(SSearchResultCount, [1, 2])), 'the hits arrive');
  const Hits = FHost.Document.SearchHits;
  const Area = HitBounds(Hits[0]);

  FHost.PressKeyOn(FHost.SearchBar.EditQuery, vkEscape, [], #27);
  FHost.Pump(1);

  Assert.AreEqual('', FHost.SearchBar.EditQuery.Text, 'the query is gone');
  Assert.AreEqual('', FHost.SearchBar.LabelResult.Text, 'the result is gone');
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

  FHost.PressKeyOn(FHost.SearchBar.EditQuery, vkReturn, [ssShift], EnterChar);

  Assert.AreEqual(Format(SSearchResultCount, [2, 2]), FHost.SearchBar.LabelResult.Text, 'Shift+Enter wraps to the last hit');
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

  ClickButton(FHost.SearchBar.ButtonNext);
  Assert.AreEqual(Format(SSearchResultCount, [2, 2]), FHost.SearchBar.LabelResult.Text, 'next');

  ClickButton(FHost.SearchBar.ButtonPrior);
  Assert.AreEqual(Format(SSearchResultCount, [1, 2]), FHost.SearchBar.LabelResult.Text, 'prior');
end;

procedure TPdf4DSearchBarTests.TestEmptyQueryClearsSearch;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Invoice), 'the document opens: ' + FHost.OpenErrorMessage);
  Search(InvoiceNumber);
  Assert.IsTrue(WaitForCaption(Format(SSearchResultCount, [1, 2])), 'the hits arrive');

  Search('');

  Assert.AreEqual('', FHost.SearchBar.LabelResult.Text, 'the result is gone');
  Assert.AreEqual<Integer>(0, Length(FHost.Document.SearchHits), 'the document has no hits');
end;

// The model gives the text; a search that stopped at the limit shows that there are more hits
procedure TPdf4DSearchBarTests.TestCappedSearchShowsAPlus;
begin
  Assert.IsTrue(FHost.Open(TViewerDocuments.Invoice), 'the document opens: ' + FHost.OpenErrorMessage);
  FHost.Document.MaxSearchHits := 1;

  Search(InvoiceNumber);

  Assert.IsTrue(WaitForCaption(Format(SSearchResultCountCapped, [1, 1])), 'one of one or more: ' + FHost.SearchBar.LabelResult.Text);
  Assert.IsTrue(FHost.Document.IsSearchCapped, 'the document says that the search is capped');
end;

procedure TPdf4DSearchBarTests.TestFocusQueryFocusesTheEdit;
begin
  FHost.Form.Focused := nil;

  FHost.SearchBar.FocusQuery;

  Assert.IsTrue(FHost.SearchBar.EditQuery.IsFocused, 'the query field has the focus');
end;

// The bar lays itself out in logical units, so it is as large in units on every scale
procedure TPdf4DSearchBarTests.TestSearchBarAt150Percent;
begin
  MakeHost(Scale150);
  Assert.IsTrue(FHost.Open(TViewerDocuments.Invoice), 'the document opens: ' + FHost.OpenErrorMessage);
  Assert.AreEqual(28, Integer(Round(FHost.SearchBar.Height)), 'the height of the bar in units');
  Assert.AreEqual(200, Integer(Round(FHost.SearchBar.EditQuery.Width)), 'the query field in units');

  Search(InvoiceNumber);

  Assert.IsTrue(WaitForCaption(Format(SSearchResultCount, [1, 2])), 'one of two: ' + FHost.SearchBar.LabelResult.Text);
end;

end.
