// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: tiny-skia v0.12.0 src/mask.rs (without PNG; fill_path, intersect_path and the other painter methods follow with the painter)
// Copyright (c) 2020 Yevhenii Reizner. BSD-3-Clause, see licenses/tiny-skia-BSD-3-Clause.txt.
unit Pdf4D.Render.Native.Mask;

{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.Pixmap,
  Pdf4D.Render.Native.Pipeline.Context;

// A mask is a simple 8-bit alpha mask: during drawing over a pixmap the black (0) pixels block rendering and the white (255) pixels allow it.
// Like a pixmap, a region of a mask is the whole data and the byte offset where the region starts.

type
  PTsMask = ^TTsMask;

  TTsMaskType = (
    // Transfers only the alpha channel from the pixmap to the mask
    Alpha,
    // Transfers RGB channels as luminance from the pixmap to the mask: Y = 0.2126 * R + 0.7152 * G + 0.0722 * B
    Luminosity
  );

  // SubMaskRef; an empty record (Width = 0) stands for the Rust `None`
  TTsSubMaskRef = record
    Data: TBytes;
    Offset: NativeInt;
    Width: Cardinal;
    Height: Cardinal;
    RealWidth: Cardinal;

    function IsAssigned: Boolean;
    function MaskCtx: TTsMaskCtx;
  end;

  TTsMask = record
    Data: TBytes;
    Width: Cardinal;
    Height: Cardinal;

    // A mask of zeros; a zero size or a size that does not fit an array gives False
    class function TryCreate(const Width, Height: Cardinal; out Mask: TTsMask): Boolean; static;

    // Mask::from_vec: the data length must match the size
    class function TryFromBytes(const Data: TBytes; const Width, Height: Cardinal; out Mask: TTsMask): Boolean; static;

    class function FromPixmap(const Pixmap: TTsPixmapRef; const MaskType: TTsMaskType): TTsMask; static;

    // as_submask
    function AsSubMask: TTsSubMaskRef;
    // submask(rect): the region that intersects the rect; False when they do not intersect
    function TrySubMask(const Rect: TTsIntRect; out Region: TTsSubMaskRef): Boolean;

    // The mask as an A8 pixmap that a pipeline draws in
    function SubPixmap: TTsSubPixmapMut;
    function TrySubPixmap(const Rect: TTsIntRect; out Region: TTsSubPixmapMut): Boolean;
  end;

implementation

uses
  Pdf4D.Render.Native.Scalar;

const
  Scale255: Single = 255;
  RedWeight: Single = 0.2126;
  GreenWeight: Single = 0.7152;
  BlueWeight: Single = 0.0722;

{ TTsSubMaskRef }

function TTsSubMaskRef.IsAssigned: Boolean;
begin
  Result := (Width > 0);
end;

function TTsSubMaskRef.MaskCtx: TTsMaskCtx;
begin
  Result := Default(TTsMaskCtx);
  Result.Data := Data;
  Result.Offset := Offset;
  Result.RealWidth := RealWidth;
end;

{ TTsMask }

class function TTsMask.TryCreate(const Width, Height: Cardinal; out Mask: TTsMask): Boolean;
begin
  Mask := Default(TTsMask);

  if (Width = 0) or (Height = 0) then
  begin
    Exit(False);
  end;

  const ByteCount = Int64(Width) * Int64(Height);
  if ByteCount > MaxInt then
  begin
    Exit(False);
  end;

  SetLength(Mask.Data, ByteCount);
  Mask.Width := Width;
  Mask.Height := Height;
  Result := True;
end;

class function TTsMask.TryFromBytes(const Data: TBytes; const Width, Height: Cardinal; out Mask: TTsMask): Boolean;
begin
  Mask := Default(TTsMask);

  if (Width = 0) or (Height = 0) or (Int64(Length(Data)) <> Int64(Width) * Int64(Height)) then
  begin
    Exit(False);
  end;

  Mask.Data := Data;
  Mask.Width := Width;
  Mask.Height := Height;
  Result := True;
end;

class function TTsMask.FromPixmap(const Pixmap: TTsPixmapRef; const MaskType: TTsMaskType): TTsMask;
begin
  Result := Default(TTsMask);
  Result.Width := Pixmap.Width;
  Result.Height := Pixmap.Height;
  SetLength(Result.Data, Int64(Pixmap.Width) * Int64(Pixmap.Height));

  for var I := 0 to High(Result.Data) do
  begin
    var Red, Green, Blue, Alpha: Byte;
    Pixmap.TryReadPixel(I, Red, Green, Blue, Alpha);

    case MaskType of
      TTsMaskType.Alpha:
        Result.Data[I] := Alpha;

      TTsMaskType.Luminosity:
        begin
          // Normalize
          const RedValue: Single = Red;
          const GreenValue: Single = Green;
          const BlueValue: Single = Blue;
          const AlphaValue: Single = Alpha;
          var R: Single := RedValue / Scale255;
          var G: Single := GreenValue / Scale255;
          var B: Single := BlueValue / Scale255;
          const A: Single = AlphaValue / Scale255;

          // Demultiply
          if Alpha <> 0 then
          begin
            R := R / A;
            G := G / A;
            B := B / A;
          end;

          const RedPart: Single = R * RedWeight;
          const GreenPart: Single = G * GreenWeight;
          const BluePart: Single = B * BlueWeight;
          const Luma: Single = RedPart + GreenPart + BluePart;
          const Scaled: Single = Luma * A;
          const Level: Single = Scaled * Scale255;
          const Clamped: Single = TTsScalar.MaxF(0, TTsScalar.MinF(Level, Scale255));
          Result.Data[I] := Byte(TTsScalar.SaturateToInt32(TTsScalar.CeilF(Clamped)));
        end;
    else
      raise EInvalidOpException.CreateFmt('Unsupported mask type: %d', [Ord(MaskType)]);
    end;
  end;
end;

function TTsMask.AsSubMask: TTsSubMaskRef;
begin
  Result.Data := Data;
  Result.Offset := 0;
  Result.Width := Width;
  Result.Height := Height;
  Result.RealWidth := Width;
end;

function TTsMask.TrySubMask(const Rect: TTsIntRect; out Region: TTsSubMaskRef): Boolean;
begin
  Region := Default(TTsSubMaskRef);

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
  Region.Offset := Int64(Overlap.Top) * Width + Overlap.Left;
  Region.Width := Overlap.Width;
  Region.Height := Overlap.Height;
  Region.RealWidth := Width;
  Result := True;
end;

function TTsMask.SubPixmap: TTsSubPixmapMut;
begin
  Result := TTsSubPixmapMut.Whole(Data, Width, Height);
end;

function TTsMask.TrySubPixmap(const Rect: TTsIntRect; out Region: TTsSubPixmapMut): Boolean;
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
  Region.Offset := Int64(Overlap.Top) * Width + Overlap.Left;
  Region.Width := Overlap.Width;
  Region.Height := Overlap.Height;
  Region.RealWidth := Width;
  Result := True;
end;

end.
