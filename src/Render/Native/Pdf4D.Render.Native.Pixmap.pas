// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: tiny-skia v0.12.0 src/pixmap.rs (without PNG)
// Copyright (c) 2020 Yevhenii Reizner. BSD-3-Clause, see licenses/tiny-skia-BSD-3-Clause.txt.
unit Pdf4D.Render.Native.Pixmap;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.Color,
  Pdf4D.Render.Bitmap;

// A pixmap holds premultiplied RGBA bytes, rows top to bottom, stride Width * 4: the same bytes as TPdfBitmap. A Rust slice of the data is
// the array and the byte offset where the slice starts; a TBytes is a reference, so a copy of a record writes the same bytes.
//
// PixmapRef and PixmapMut of Rust are TTsPixmapRef and the TTsSubPixmapMut that covers the whole pixmap. Rust panics (unwrap) that input can
// reach are Try-functions here.

type
  PTsPixmapRef = ^TTsPixmapRef;
  PTsSubPixmapMut = ^TTsSubPixmapMut;

  // PixmapRef: Width * Height pixels, the data holds at least that many bytes
  TTsPixmapRef = record
    Data: TBytes;
    Width: Cardinal;
    Height: Cardinal;

    // PixmapRef::from_bytes: a zero size, a width above i32::MAX / 4 or too few bytes give False
    class function TryFromBytes(const Data: TBytes; const Width, Height: Cardinal; out Pixmap: TTsPixmapRef): Boolean; static;

    // The pixel at Index, in the order of the bytes. False when the data does not hold the pixel.
    function TryReadPixel(const Index: Int64; out R, G, B, A: Byte): Boolean;
  end;

  // SubPixmapMut: a region of a parent pixmap. Data is the whole data of the parent, Offset the byte offset where the region starts, so
  // that the pixel (X, Y) of the region is the pixel Offset div 4 + RealWidth * Y + X of Data.
  TTsSubPixmapMut = record
    Data: TBytes;
    Offset: NativeInt;
    Width: Cardinal;
    Height: Cardinal;
    RealWidth: NativeUInt;

    // as_subpixmap: the region is the whole pixmap
    class function Whole(const Data: TBytes; const Width, Height: Cardinal): TTsSubPixmapMut; static;

    // offset(): the index, in pixels from the start of Data, of the pixel (DX, DY) of the region
    function PixelIndex(const DX, DY: Int64): Int64;

    // True when Data holds the pixels from the first pixel of the region up to Right pixels in each of the Bottom rows
    function HoldsRegion(const Right, Bottom: Cardinal): Boolean;

    // The same for a pixmap of one byte per pixel (the A8 pixmap of a mask): the byte of the pixel (DX, DY), counted from Offset
    function MaskIndex(const DX, DY: Int64): Int64;
    function HoldsMaskRegion(const Right, Bottom: Cardinal): Boolean;
  end;

  TTsPixmap = record
    Data: TBytes;
    Width: Cardinal;
    Height: Cardinal;

    // A pixmap filled with transparent black. A zero size or a width above i32::MAX / 4 gives False, as does a size that does not fit an array.
    class function TryCreate(const Width, Height: Cardinal; out Pixmap: TTsPixmap): Boolean; static;

    // Pixmap::from_vec: the data length must match the size
    class function TryFromBytes(const Data: TBytes; const Width, Height: Cardinal; out Pixmap: TTsPixmap): Boolean; static;

    // A pixmap over the pixels of the bitmap, without a copy: drawing in the pixmap changes the bitmap
    class function CreateOver(const Bitmap: TPdfBitmap): TTsPixmap; static;

    // Fills the entire pixmap with a specified color
    procedure Fill(const Color: TTsColor);

    // False when the position is out of bounds
    function TryPixel(const X, Y: Cardinal; out Color: TTsPremultipliedColorU8): Boolean;

    // A copy of the part of the pixmap that intersects the rect; False when they do not intersect
    function TryCloneRect(const Rect: TTsIntRect; out Clone: TTsPixmap): Boolean;

    function AsRef: TTsPixmapRef;
    // as_subpixmap
    function SubPixmap: TTsSubPixmapMut;
    // subpixmap(rect): the region that intersects the rect; False when they do not intersect
    function TrySubPixmap(const Rect: TTsIntRect; out Region: TTsSubPixmapMut): Boolean;
  end;

implementation

const
  BytesPerPixel = 4;
  // i32::MAX / 4: the largest width a pixmap can have
  MaxPixmapWidth: Cardinal = 536870911;

{ TTsPixmapRef }

class function TTsPixmapRef.TryFromBytes(const Data: TBytes; const Width, Height: Cardinal; out Pixmap: TTsPixmapRef): Boolean;
begin
  Pixmap := Default(TTsPixmapRef);

  if (Width = 0) or (Height = 0) or (Width > MaxPixmapWidth) then
  begin
    Exit(False);
  end;

  if Int64(Length(Data)) < Int64(Width) * Int64(Height) * BytesPerPixel then
  begin
    Exit(False);
  end;

  Pixmap.Data := Data;
  Pixmap.Width := Width;
  Pixmap.Height := Height;
  Result := True;
end;

function TTsPixmapRef.TryReadPixel(const Index: Int64; out R, G, B, A: Byte): Boolean;
begin
  R := 0;
  G := 0;
  B := 0;
  A := 0;

  if (Index < 0) or ((Index + 1) * BytesPerPixel > Length(Data)) then
  begin
    Exit(False);
  end;

  const Start = Index * BytesPerPixel;
  R := Data[Start];
  G := Data[Start + 1];
  B := Data[Start + 2];
  A := Data[Start + 3];
  Result := True;
end;

{ TTsSubPixmapMut }

class function TTsSubPixmapMut.Whole(const Data: TBytes; const Width, Height: Cardinal): TTsSubPixmapMut;
begin
  Result.Data := Data;
  Result.Offset := 0;
  Result.Width := Width;
  Result.Height := Height;
  Result.RealWidth := Width;
end;

function TTsSubPixmapMut.PixelIndex(const DX, DY: Int64): Int64;
begin
  Result := Offset div BytesPerPixel + Int64(RealWidth) * DY + DX;
end;

function TTsSubPixmapMut.HoldsRegion(const Right, Bottom: Cardinal): Boolean;
begin
  if (Offset < 0) or (Right = 0) or (Bottom = 0) then
  begin
    Exit(False);
  end;

  const LastPixel = PixelIndex(Int64(Right) - 1, Int64(Bottom) - 1);
  Result := ((LastPixel + 1) * BytesPerPixel <= Length(Data));
end;

function TTsSubPixmapMut.MaskIndex(const DX, DY: Int64): Int64;
begin
  Result := Offset + Int64(RealWidth) * DY + DX;
end;

function TTsSubPixmapMut.HoldsMaskRegion(const Right, Bottom: Cardinal): Boolean;
begin
  if (Offset < 0) or (Right = 0) or (Bottom = 0) then
  begin
    Exit(False);
  end;

  Result := (MaskIndex(Int64(Right) - 1, Int64(Bottom) - 1) < Length(Data));
end;

{ TTsPixmap }

class function TTsPixmap.TryCreate(const Width, Height: Cardinal; out Pixmap: TTsPixmap): Boolean;
begin
  Pixmap := Default(TTsPixmap);

  if (Width = 0) or (Height = 0) or (Width > MaxPixmapWidth) then
  begin
    Exit(False);
  end;

  const ByteCount = Int64(Width) * Int64(Height) * BytesPerPixel;
  if ByteCount > MaxInt then
  begin
    Exit(False);
  end;

  SetLength(Pixmap.Data, ByteCount);
  Pixmap.Width := Width;
  Pixmap.Height := Height;
  Result := True;
end;

class function TTsPixmap.TryFromBytes(const Data: TBytes; const Width, Height: Cardinal; out Pixmap: TTsPixmap): Boolean;
begin
  Pixmap := Default(TTsPixmap);

  if (Width = 0) or (Height = 0) or (Width > MaxPixmapWidth) then
  begin
    Exit(False);
  end;

  if Int64(Length(Data)) <> Int64(Width) * Int64(Height) * BytesPerPixel then
  begin
    Exit(False);
  end;

  Pixmap.Data := Data;
  Pixmap.Width := Width;
  Pixmap.Height := Height;
  Result := True;
end;

class function TTsPixmap.CreateOver(const Bitmap: TPdfBitmap): TTsPixmap;
begin
  Result.Data := Bitmap.Pixels;
  Result.Width := Cardinal(Bitmap.Width);
  Result.Height := Cardinal(Bitmap.Height);
end;

procedure TTsPixmap.Fill(const Color: TTsColor);
begin
  const Premultiplied = Color.Premultiply.ToColorU8;

  for var I := 0 to Integer(Width * Height) - 1 do
  begin
    Data[I * BytesPerPixel] := Premultiplied.Red;
    Data[I * BytesPerPixel + 1] := Premultiplied.Green;
    Data[I * BytesPerPixel + 2] := Premultiplied.Blue;
    Data[I * BytesPerPixel + 3] := Premultiplied.Alpha;
  end;
end;

function TTsPixmap.TryPixel(const X, Y: Cardinal; out Color: TTsPremultipliedColorU8): Boolean;
begin
  Color := TTsPremultipliedColorU8.Transparent;

  if (X >= Width) or (Y >= Height) then
  begin
    Exit(False);
  end;

  const Start = (Int64(Y) * Width + X) * BytesPerPixel;
  Color := TTsPremultipliedColorU8.FromRgbaUnchecked(Data[Start], Data[Start + 1], Data[Start + 2], Data[Start + 3]);
  Result := True;
end;

function TTsPixmap.TryCloneRect(const Rect: TTsIntRect; out Clone: TTsPixmap): Boolean;
begin
  Clone := Default(TTsPixmap);

  var Whole: TTsIntRect;
  var Overlap: TTsIntRect;
  if not TTsIntRect.TryFromXYWH(0, 0, Width, Height, Whole) then
  begin
    Exit(False);
  end;

  if not Whole.TryIntersect(Rect, Overlap) then
  begin
    Exit(False);
  end;

  if not TTsPixmap.TryCreate(Overlap.Width, Overlap.Height, Clone) then
  begin
    Exit(False);
  end;

  for var Y := 0 to Integer(Overlap.Height) - 1 do
  begin
    const OldStart = (Int64(Y + Overlap.Y) * Width + Overlap.X) * BytesPerPixel;
    const NewStart = Int64(Y) * Overlap.Width * BytesPerPixel;
    Move(Data[OldStart], Clone.Data[NewStart], Int64(Overlap.Width) * BytesPerPixel);
  end;

  Result := True;
end;

function TTsPixmap.AsRef: TTsPixmapRef;
begin
  Result.Data := Data;
  Result.Width := Width;
  Result.Height := Height;
end;

function TTsPixmap.SubPixmap: TTsSubPixmapMut;
begin
  Result := TTsSubPixmapMut.Whole(Data, Width, Height);
end;

function TTsPixmap.TrySubPixmap(const Rect: TTsIntRect; out Region: TTsSubPixmapMut): Boolean;
begin
  Region := Default(TTsSubPixmapMut);

  var Whole: TTsIntRect;
  var Overlap: TTsIntRect;
  if not TTsIntRect.TryFromXYWH(0, 0, Width, Height, Whole) then
  begin
    Exit(False);
  end;

  if not Whole.TryIntersect(Rect, Overlap) then
  begin
    Exit(False);
  end;

  Region.Data := Data;
  Region.Offset := (Int64(Overlap.Top) * Width + Overlap.Left) * BytesPerPixel;
  Region.Width := Overlap.Width;
  Region.Height := Overlap.Height;
  Region.RealWidth := Width;
  Result := True;
end;

end.
