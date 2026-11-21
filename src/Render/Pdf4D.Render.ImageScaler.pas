// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Independent implementation of area-averaging image scaling, following the public documentation of Image.SCALE_SMOOTH and
// AreaAveragingScaleFilter (each pixel of the result is the average of the source pixels that it covers, weighted by the covered
// area, with the colour weighted by the alpha). PageDrawer.drawBufferedImage of PDFBox 3.0.8 scales an image down this way
// (Image.getScaledInstance) before it draws it.
unit Pdf4D.Render.ImageScaler;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Math,
  Pdf4D.Render.Bitmap;

type
  TPdfImageScaler = record
  private
    type
      // The source pixels that one destination pixel covers along one axis, and how much of each it covers
      TAxisCover = record
        First: Integer;
        Weights: TArray<Single>;
        Total: Single;
      end;

  private
    class function CoverOfAxis(const SourceSize, TargetSize, TargetIndex: Integer): TAxisCover; static;
    class function CoversOfAxis(const SourceSize, TargetSize: Integer): TArray<TAxisCover>; static;
    class procedure ScalePixel(const Source: TPdfBitmap; const CoverX, CoverY: TAxisCover; const Target: PByte); static;

  public
    // A new bitmap of Width x Height pixels in which every pixel is the average of the source pixels that it covers, weighted by the
    // area that it covers of each (the alpha weighs the colour). The source and the result are premultiplied; the averaging is done
    // on the straight values, in single precision. Raises EArgumentOutOfRangeException for a size that
    // TPdfBitmap.CheckSize does not allow.
    class function ScaleSmooth(const Source: TPdfBitmap; const Width, Height: Integer): TPdfBitmap; static;
  end;

implementation

const
  MaxChannel = 255;

{ TPdfImageScaler }

class function TPdfImageScaler.ScaleSmooth(const Source: TPdfBitmap; const Width, Height: Integer): TPdfBitmap;
begin
  Result := TPdfBitmap.Create(Width, Height);
  try
    const CoversX = CoversOfAxis(Source.Width, Width);
    const CoversY = CoversOfAxis(Source.Height, Height);
    for var Y := 0 to Height - 1 do
    begin
      const Row = Result.ScanLine(Y);
      for var X := 0 to Width - 1 do
      begin
        ScalePixel(Source, CoversX[X], CoversY[Y], Row + X * 4);
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

class function TPdfImageScaler.CoversOfAxis(const SourceSize, TargetSize: Integer): TArray<TAxisCover>;
begin
  SetLength(Result, TargetSize);
  for var Index := 0 to TargetSize - 1 do
  begin
    Result[Index] := CoverOfAxis(SourceSize, TargetSize, Index);
  end;
end;

// The target pixel spans [Index * SourceSize / TargetSize, (Index + 1) * SourceSize / TargetSize) on the source axis
class function TPdfImageScaler.CoverOfAxis(const SourceSize, TargetSize, TargetIndex: Integer): TAxisCover;
begin
  const Start = (TargetIndex * Int64(SourceSize)) / TargetSize;
  const Finish = ((TargetIndex + 1) * Int64(SourceSize)) / TargetSize;
  Result.First := Trunc(Start);
  var Last := Trunc(Finish);
  if Last = Finish then
  begin
    Dec(Last);
  end;
  Last := Min(Last, SourceSize - 1);

  SetLength(Result.Weights, Last - Result.First + 1);
  Result.Total := 0;
  for var Index := Result.First to Last do
  begin
    const Weight: Single = Min(Finish, Double(Index + 1)) - Max(Start, Double(Index));
    Result.Weights[Index - Result.First] := Weight;
    Result.Total := Result.Total + Weight;
  end;
end;

class procedure TPdfImageScaler.ScalePixel(const Source: TPdfBitmap; const CoverX, CoverY: TAxisCover; const Target: PByte);
begin
  var SumAlpha: Single := 0;
  var SumRed: Single := 0;
  var SumGreen: Single := 0;
  var SumBlue: Single := 0;

  for var RowIndex := 0 to High(CoverY.Weights) do
  begin
    const Row = Source.ScanLine(CoverY.First + RowIndex);
    for var ColumnIndex := 0 to High(CoverX.Weights) do
    begin
      const Weight: Single = CoverX.Weights[ColumnIndex] * CoverY.Weights[RowIndex];
      const Pixel = Row + (CoverX.First + ColumnIndex) * 4;
      const Alpha = Pixel[3];
      if Alpha = 0 then
      begin
        Continue;
      end;

      // Straight colour of the premultiplied source pixel
      const AlphaWeight: Single = Alpha * Weight;
      SumAlpha := SumAlpha + AlphaWeight;
      SumRed := SumRed + Round(Pixel[0] * MaxChannel / Alpha) * AlphaWeight;
      SumGreen := SumGreen + Round(Pixel[1] * MaxChannel / Alpha) * AlphaWeight;
      SumBlue := SumBlue + Round(Pixel[2] * MaxChannel / Alpha) * AlphaWeight;
    end;
  end;

  if SumAlpha = 0 then
  begin
    Exit;
  end;

  const TotalWeight: Single = CoverX.Total * CoverY.Total;
  const Alpha = Min(Trunc(SumAlpha / TotalWeight + 0.5), MaxChannel);
  const Red = Min(Trunc(SumRed / SumAlpha + 0.5), MaxChannel);
  const Green = Min(Trunc(SumGreen / SumAlpha + 0.5), MaxChannel);
  const Blue = Min(Trunc(SumBlue / SumAlpha + 0.5), MaxChannel);
  Target[0] := Round(Red * Alpha / MaxChannel);
  Target[1] := Round(Green * Alpha / MaxChannel);
  Target[2] := Round(Blue * Alpha / MaxChannel);
  Target[3] := Alpha;
end;

end.
