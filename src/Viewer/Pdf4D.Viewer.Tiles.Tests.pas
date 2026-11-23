// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.Tiles.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  DUnitX.TestFramework,
  Pdf4D.Viewer.Tiles;

type
  [TestFixture]
  TPdfTileGridTests = class
  private
    class procedure CheckTiles(const Expected: array of TPoint; const Actual: TArray<TPoint>); static;
    class function TileCount(const PageSize: TSize; const Area: TRect): Integer; static;

  public
    [Test]
    procedure TestTileRectIsClipped;
    [Test]
    procedure TestTileRectInsidePageIsFullTile;
    [Test]
    procedure TestTilesInArea;
    [Test]
    procedure TestTilesInAreaOutsidePage;
    [Test]
    procedure TestTilesInAreaPartlyOutsidePage;
    [Test]
    procedure TestTilesInAreaOnTileBorder;
    [Test]
    procedure TestTilesInEmptyAreaOrPage;
    [Test]
    procedure TestTileKeyEqualityAndHash;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections;

{ TPdfTileGridTests }

class function TPdfTileGridTests.TileCount(const PageSize: TSize; const Area: TRect): Integer;
begin
  Result := Length(TPdfTileGrid.TilesIn(PageSize, Area));
end;

class procedure TPdfTileGridTests.CheckTiles(const Expected: array of TPoint; const Actual: TArray<TPoint>);
begin
  Assert.AreEqual(Length(Expected), Length(Actual), 'tile count');
  for var Index := 0 to High(Expected) do
  begin
    Assert.AreEqual(Expected[Index].X, Actual[Index].X, Format('column of tile %d', [Index]));
    Assert.AreEqual(Expected[Index].Y, Actual[Index].Y, Format('row of tile %d', [Index]));
  end;
end;

procedure TPdfTileGridTests.TestTileRectIsClipped;
begin
  const Rect = TPdfTileGrid.TileRect(TSize.Create(816, 1056), 3, 4);

  Assert.AreEqual(768, Rect.Left);
  Assert.AreEqual(1024, Rect.Top);
  Assert.AreEqual(816, Rect.Right);
  Assert.AreEqual(1056, Rect.Bottom);
end;

procedure TPdfTileGridTests.TestTileRectInsidePageIsFullTile;
begin
  const Rect = TPdfTileGrid.TileRect(TSize.Create(816, 1056), 1, 2);

  Assert.AreEqual(256, Rect.Left);
  Assert.AreEqual(512, Rect.Top);
  Assert.AreEqual(512, Rect.Right);
  Assert.AreEqual(768, Rect.Bottom);
end;

procedure TPdfTileGridTests.TestTilesInArea;
begin
  const Tiles = TPdfTileGrid.TilesIn(TSize.Create(816, 1056), TRect.Create(300, 300, 600, 600));

  CheckTiles([Point(1, 1), Point(2, 1), Point(1, 2), Point(2, 2)], Tiles);
end;

procedure TPdfTileGridTests.TestTilesInAreaOutsidePage;
begin
  const PageSize = TSize.Create(816, 1056);

  Assert.AreEqual(0, TileCount(PageSize, TRect.Create(900, 0, 1000, 100)), 'right of the page');
  Assert.AreEqual(0, TileCount(PageSize, TRect.Create(-200, -200, -10, -10)), 'above left of the page');
  Assert.AreEqual(0, TileCount(PageSize, TRect.Create(0, 1056, 100, 1200)), 'below the page');
end;

procedure TPdfTileGridTests.TestTilesInAreaPartlyOutsidePage;
begin
  const Tiles = TPdfTileGrid.TilesIn(TSize.Create(816, 1056), TRect.Create(-100, -100, 100, 100));

  CheckTiles([Point(0, 0)], Tiles);
end;

procedure TPdfTileGridTests.TestTilesInAreaOnTileBorder;
begin
  const Tiles = TPdfTileGrid.TilesIn(TSize.Create(816, 1056), TRect.Create(0, 0, 256, 256));

  CheckTiles([Point(0, 0)], Tiles);
end;

procedure TPdfTileGridTests.TestTilesInEmptyAreaOrPage;
begin
  Assert.AreEqual(0, TileCount(TSize.Create(816, 1056), TRect.Create(10, 10, 10, 50)), 'empty area');
  Assert.AreEqual(0, TileCount(TSize.Create(0, 0), TRect.Create(0, 0, 50, 50)), 'empty page');
end;

procedure TPdfTileGridTests.TestTileKeyEqualityAndHash;
begin
  const Keys = TDictionary<TPdfTileKey, Integer>.Create;
  try
    Keys.Add(TPdfTileKey.Create(2, 90, 1.5, 3, 4), 7);

    Assert.IsTrue(Keys.ContainsKey(TPdfTileKey.Create(2, 90, 1.5, 3, 4)), 'same fields');
    Assert.AreEqual(7, Keys[TPdfTileKey.Create(2, 90, 1.5, 3, 4)]);
    Assert.IsFalse(Keys.ContainsKey(TPdfTileKey.Create(2, 90, 1.25, 3, 4)), 'other scale');
    Assert.IsFalse(Keys.ContainsKey(TPdfTileKey.Create(2, 0, 1.5, 3, 4)), 'other rotation');
    Assert.IsFalse(Keys.ContainsKey(TPdfTileKey.Create(2, 90, 1.5, 4, 3)), 'other column and row');
  finally
    Keys.Free;
  end;
end;

end.
