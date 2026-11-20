// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: java.awt.image.AreaAveragingScaleFilter (OpenJDK 21), the filter behind Image.getScaledInstance(w, h, SCALE_SMOOTH) that
// PageDrawer.drawBufferedImage of PDFBox 3.0.8 uses to scale an image down before it draws it
unit Pdf4D.Render.ImageScaler;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Render.Bitmap;

type
  TPdfImageScaler = record
    // A new bitmap of Width x Height pixels in which every pixel is the average of the source pixels that it covers, weighted by the
    // area that it covers of each (the alpha weighs the colour). The source and the result are premultiplied; the computation is the
    // one of the JDK, on the straight values, in single precision. Raises EArgumentOutOfRangeException for a size that
    // TPdfBitmap.CheckSize does not allow.
    class function ScaleSmooth(const Source: TPdfBitmap; const Width, Height: Integer): TPdfBitmap; static;
  end;

implementation

uses
  System.Math;

const
  ChannelMax = 255;
  BytesPerPixel = 4;
  Half = 0.5;

type
  // The state of AreaAveragingScaleFilter while the rows of the source are delivered from the top to the bottom
  TAreaAveraging = class
  private
    FSource: TPdfBitmap;
    FTarget: TPdfBitmap;
    FSourceWidth: Integer;
    FSourceHeight: Integer;
    FDestWidth: Integer;
    FDestHeight: Integer;
    FReds: TArray<Single>;
    FGreens: TArray<Single>;
    FBlues: TArray<Single>;
    FAlphas: TArray<Single>;
    FSavedY: Integer;
    FSavedYRemainder: Integer;

    procedure ClearAccumulators;
    class function RoundHalfUp(const Value: Single): Integer; static;
    class function ClampChannel(const Value: Integer): Integer; static;
    procedure WriteRow(const Row: Integer);
    procedure AccumulateRow(const Y: Integer);

  public
    constructor Create(const Source, Target: TPdfBitmap);

    procedure Run;
  end;

{ TAreaAveraging }

constructor TAreaAveraging.Create(const Source, Target: TPdfBitmap);
begin
  inherited Create;
  FSource := Source;
  FTarget := Target;
  FSourceWidth := Source.Width;
  FSourceHeight := Source.Height;
  FDestWidth := Target.Width;
  FDestHeight := Target.Height;
  SetLength(FReds, FDestWidth);
  SetLength(FGreens, FDestWidth);
  SetLength(FBlues, FDestWidth);
  SetLength(FAlphas, FDestWidth);
end;

procedure TAreaAveraging.ClearAccumulators;
begin
  for var Index := 0 to FDestWidth - 1 do
  begin
    FAlphas[Index] := 0;
    FReds[Index] := 0;
    FGreens[Index] := 0;
    FBlues[Index] := 0;
  end;
end;

// Math.round(float) of Java
class function TAreaAveraging.RoundHalfUp(const Value: Single): Integer;
begin
  if IsNan(Value) then
  begin
    Exit(0);
  end;
  const Shifted = Double(Value) + Half;
  if Shifted >= Double(High(Integer)) then
  begin
    Exit(High(Integer));
  end;
  if Shifted <= Double(Low(Integer)) then
  begin
    Exit(Low(Integer));
  end;
  Result := Floor(Shifted);
end;

class function TAreaAveraging.ClampChannel(const Value: Integer): Integer;
begin
  Result := EnsureRange(Value, 0, ChannelMax);
end;

// calcRow and the delivery of the finished row: the accumulated values become straight colour, stored premultiplied
procedure TAreaAveraging.WriteRow(const Row: Integer);
begin
  if Row >= FDestHeight then
  begin
    Exit;
  end;

  const OriginalMultiplier = Single(FSourceWidth) * FSourceHeight;
  const Target = FTarget.ScanLine(Row);
  for var X := 0 to FDestWidth - 1 do
  begin
    var Multiplier := OriginalMultiplier;
    var Alpha := RoundHalfUp(FAlphas[X] / Multiplier);
    if Alpha <= 0 then
    begin
      Alpha := 0;
    end
    else if Alpha >= ChannelMax then
    begin
      Alpha := ChannelMax;
    end
    else
    begin
      // un-premultiply: dividing by the multiplier and by the alpha in one step
      Multiplier := FAlphas[X] / ChannelMax;
    end;
    const Red = ClampChannel(RoundHalfUp(FReds[X] / Multiplier));
    const Green = ClampChannel(RoundHalfUp(FGreens[X] / Multiplier));
    const Blue = ClampChannel(RoundHalfUp(FBlues[X] / Multiplier));

    Target[X * BytesPerPixel] := Byte((Red * Alpha + 127) div ChannelMax);
    Target[X * BytesPerPixel + 1] := Byte((Green * Alpha + 127) div ChannelMax);
    Target[X * BytesPerPixel + 2] := Byte((Blue * Alpha + 127) div ChannelMax);
    Target[X * BytesPerPixel + 3] := Byte(Alpha);
  end;
end;

// accumPixels for the row Y of the source (the filter is given one row at a time)
procedure TAreaAveraging.AccumulateRow(const Y: Integer);
begin
  const Row = FSource.ScanLine(Y);
  var SourceY := Y;
  var SourceYRemainder := FDestHeight;
  var DestY := 0;
  var DestYRemainder := 0;
  if SourceY <> 0 then
  begin
    DestY := FSavedY;
    DestYRemainder := FSavedYRemainder;
  end;

  while SourceY < Y + 1 do
  begin
    if DestYRemainder = 0 then
    begin
      ClearAccumulators;
      DestYRemainder := FSourceHeight;
    end;
    const AmountY = Min(SourceYRemainder, DestYRemainder);

    var SourceX := 0;
    var DestX := 0;
    var SourceXRemainder := 0;
    var DestXRemainder := FSourceWidth;
    var Alpha: Single := 0;
    var Red: Single := 0;
    var Green: Single := 0;
    var Blue: Single := 0;
    while SourceX < FSourceWidth do
    begin
      if SourceXRemainder = 0 then
      begin
        SourceXRemainder := FDestWidth;
        // The source is premultiplied; the filter works on the straight values and premultiplies in float
        const Offset = SourceX * BytesPerPixel;
        const AlphaByte = Row[Offset + 3];
        var StraightRed := 0;
        var StraightGreen := 0;
        var StraightBlue := 0;
        if AlphaByte <> 0 then
        begin
          StraightRed := Min((Row[Offset] * ChannelMax + AlphaByte div 2) div AlphaByte, ChannelMax);
          StraightGreen := Min((Row[Offset + 1] * ChannelMax + AlphaByte div 2) div AlphaByte, ChannelMax);
          StraightBlue := Min((Row[Offset + 2] * ChannelMax + AlphaByte div 2) div AlphaByte, ChannelMax);
        end;
        Alpha := AlphaByte;
        Red := StraightRed;
        Green := StraightGreen;
        Blue := StraightBlue;
        if Alpha <> ChannelMax then
        begin
          const AlphaScale: Single = Alpha / ChannelMax;
          Red := Red * AlphaScale;
          Green := Green * AlphaScale;
          Blue := Blue * AlphaScale;
        end;
      end;

      const AmountX = Min(SourceXRemainder, DestXRemainder);
      const Multiplier = Single(AmountX) * AmountY;
      FAlphas[DestX] := FAlphas[DestX] + Multiplier * Alpha;
      FReds[DestX] := FReds[DestX] + Multiplier * Red;
      FGreens[DestX] := FGreens[DestX] + Multiplier * Green;
      FBlues[DestX] := FBlues[DestX] + Multiplier * Blue;
      Dec(SourceXRemainder, AmountX);
      if SourceXRemainder = 0 then
      begin
        Inc(SourceX);
      end;
      Dec(DestXRemainder, AmountX);
      if DestXRemainder = 0 then
      begin
        Inc(DestX);
        DestXRemainder := FSourceWidth;
      end;
    end;

    Dec(DestYRemainder, AmountY);
    if DestYRemainder = 0 then
    begin
      repeat
        WriteRow(DestY);
        Inc(DestY);
        Dec(SourceYRemainder, AmountY);
      until not ((SourceYRemainder >= AmountY) and (AmountY = FSourceHeight));
    end
    else
    begin
      Dec(SourceYRemainder, AmountY);
    end;
    if SourceYRemainder = 0 then
    begin
      SourceYRemainder := FDestHeight;
      Inc(SourceY);
    end;
  end;
  FSavedYRemainder := DestYRemainder;
  FSavedY := DestY;
end;

procedure TAreaAveraging.Run;
begin
  for var Y := 0 to FSourceHeight - 1 do
  begin
    AccumulateRow(Y);
  end;
end;

{ TPdfImageScaler }

class function TPdfImageScaler.ScaleSmooth(const Source: TPdfBitmap; const Width, Height: Integer): TPdfBitmap;
begin
  Result := TPdfBitmap.Create(Width, Height);
  try
    const Scaler = TAreaAveraging.Create(Source, Result);
    try
      Scaler.Run;
    finally
      Scaler.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.
