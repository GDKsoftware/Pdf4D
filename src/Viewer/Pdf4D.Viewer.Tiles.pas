// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.Tiles;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types;

const
  // Device pixels per side of a tile
  PdfTileSize = 256;

type
  // Compared and hashed as bytes by the default comparer of a TDictionary, so there is no padding and no managed field
  TPdfTileKey = packed record
    PageIndex: Integer;
    ViewRotation: Integer;
    Scale: Single;
    Column, Row: Integer;

    class function Create(const PageIndex, ViewRotation: Integer; const Scale: Single; const Column, Row: Integer): TPdfTileKey; static;
  end;

  TPdfTileGrid = record
    // Clipped to the page; empty for a tile outside it
    class function TileRect(const PageSize: TSize; const Column, Row: Integer): TRect; static;
    // The tiles that overlap Area inside the page: X = column, Y = row, row by row
    class function TilesIn(const PageSize: TSize; const Area: TRect): TArray<TPoint>; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

const
  MaxTileCount = MaxInt div SizeOf(TPoint);

{ TPdfTileKey }

class function TPdfTileKey.Create(const PageIndex, ViewRotation: Integer; const Scale: Single; const Column, Row: Integer): TPdfTileKey;
begin
  Result.PageIndex := PageIndex;
  Result.ViewRotation := ViewRotation;
  Result.Scale := Scale;
  Result.Column := Column;
  Result.Row := Row;
end;

{ TPdfTileGrid }

class function TPdfTileGrid.TileRect(const PageSize: TSize; const Column, Row: Integer): TRect;
begin
  const TileLeft = Int64(Column) * PdfTileSize;
  const TileTop = Int64(Row) * PdfTileSize;
  const Left = EnsureRange(TileLeft, Int64(0), Int64(PageSize.cx));
  const Top = EnsureRange(TileTop, Int64(0), Int64(PageSize.cy));
  const Right = EnsureRange(TileLeft + PdfTileSize, Int64(0), Int64(PageSize.cx));
  const Bottom = EnsureRange(TileTop + PdfTileSize, Int64(0), Int64(PageSize.cy));
  Result := TRect.Create(Integer(Left), Integer(Top), Integer(Right), Integer(Bottom));
end;

class function TPdfTileGrid.TilesIn(const PageSize: TSize; const Area: TRect): TArray<TPoint>;
begin
  Result := nil;
  const Visible = TRect.Intersect(Area, TRect.Create(0, 0, PageSize.cx, PageSize.cy));
  if Visible.IsEmpty then
  begin
    Exit;
  end;

  const FirstColumn = Visible.Left div PdfTileSize;
  const LastColumn = (Visible.Right - 1) div PdfTileSize;
  const FirstRow = Visible.Top div PdfTileSize;
  const LastRow = (Visible.Bottom - 1) div PdfTileSize;

  // Int64: a page side of 10 million pixels and more makes the product overflow an Integer
  const TileCount = Int64(LastColumn - FirstColumn + 1) * Int64(LastRow - FirstRow + 1);
  if TileCount > MaxTileCount then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('The area covers %d tiles, more than the %d that a list can hold', [TileCount, Int64(MaxTileCount)]);
  end;

  SetLength(Result, Integer(TileCount));
  var Index := 0;
  for var Row := FirstRow to LastRow do
  begin
    for var Column := FirstColumn to LastColumn do
    begin
      Result[Index] := Point(Column, Row);
      Inc(Index);
    end;
  end;
end;

end.
