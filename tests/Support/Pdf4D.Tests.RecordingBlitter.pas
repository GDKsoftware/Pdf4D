// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.RecordingBlitter;

interface

uses
  System.SysUtils,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.AlphaRuns,
  Pdf4D.Render.Native.Blitter;

type
  // Counts per pixel the coverage that the scan converters blit, in the size of a clip. A blit that touches a pixel outside of that size is
  // counted in OutsideCount and not recorded: the scan converters must keep inside their clip.
  TRecordingBlitter = class(TTsBlitter)
  private
    FWidth: Integer;
    FHeight: Integer;
    FCoverage: TArray<Integer>;
    FComposited: TArray<Integer>;
    FOutsideCount: Integer;
    FCallCount: Integer;

    procedure Add(const X, Y: Int64; const Value: Integer);
    function ClampedCount(const Extent: Cardinal; const Size: Integer): Integer;

  public
    constructor Create(const Width, Height: Integer);

    procedure BlitH(const X, Y, Width: Cardinal); override;
    procedure BlitAntiH(const X, Y: Cardinal; const Antialias: TArray<Byte>; const Runs: TArray<TTsAlphaRun>; const Offset: Integer); override;
    procedure BlitV(const X, Y, Height: Cardinal; const Alpha: Byte); override;
    procedure BlitAntiH2(const X, Y: Cardinal; const Alpha0, Alpha1: Byte); override;
    procedure BlitAntiV2(const X, Y: Cardinal; const Alpha0, Alpha1: Byte); override;
    procedure BlitRect(const Rect: TTsScreenIntRect); override;

    // The summed coverage of a pixel; zero outside of the size
    function CoverageAt(const X, Y: Integer): Integer;
    function CountPixelsWithCoverage: Integer;
    function TotalCoverage: Int64;

    // The alpha that a black fill of full alpha leaves in the pixels, summed: what a pixmap of tiny-skia holds after the same blits
    function CompositedTotal: Int64;

    property Width: Integer read FWidth;
    property Height: Integer read FHeight;

    // The number of pixels that were blitted outside of the size
    property OutsideCount: Integer read FOutsideCount;

    // The number of blit calls
    property CallCount: Integer read FCallCount;
  end;

implementation

const
  FullCoverage = 255;

{ TRecordingBlitter }

constructor TRecordingBlitter.Create(const Width, Height: Integer);
begin
  inherited Create;

  FWidth := Width;
  FHeight := Height;
  SetLength(FCoverage, Width * Height);
  SetLength(FComposited, Width * Height);
end;

// A huge length is not a loop of billions: it is the size plus one pixel, which is outside, and one count for the rest
function TRecordingBlitter.ClampedCount(const Extent: Cardinal; const Size: Integer): Integer;
begin
  const Limit = Int64(Size) + 1;
  if Int64(Extent) > Limit then
  begin
    Inc(FOutsideCount);
    Exit(Integer(Limit));
  end;

  Result := Integer(Extent);
end;

procedure TRecordingBlitter.Add(const X, Y: Int64; const Value: Integer);
begin
  const IsInside = ((X >= 0) and (X < FWidth) and (Y >= 0) and (Y < FHeight));
  if not IsInside then
  begin
    Inc(FOutsideCount);
    Exit;
  end;

  FCoverage[Y * FWidth + X] := FCoverage[Y * FWidth + X] + Value;

  // Black at full alpha over what is there, lerped with the coverage as the lowp pipeline of tiny-skia does: div255(v) = (v + 255) >> 8
  FComposited[Y * FWidth + X] := (FComposited[Y * FWidth + X] * (FullCoverage - Value) + FullCoverage * Value + FullCoverage) shr 8;
end;

procedure TRecordingBlitter.BlitH(const X, Y, Width: Cardinal);
begin
  Inc(FCallCount);

  for var Offset := 0 to ClampedCount(Width, FWidth) - 1 do
  begin
    Add(Int64(X) + Offset, Y, FullCoverage);
  end;
end;

procedure TRecordingBlitter.BlitAntiH(const X, Y: Cardinal; const Antialias: TArray<Byte>; const Runs: TArray<TTsAlphaRun>;
                                      const Offset: Integer);
begin
  Inc(FCallCount);

  var Index := Offset;
  var Position := Int64(X);
  while Runs[Index] <> 0 do
  begin
    const Count = Runs[Index];
    for var Step := 0 to Count - 1 do
    begin
      Add(Position + Step, Y, Antialias[Index]);
    end;

    Inc(Position, Count);
    Inc(Index, Count);
  end;
end;

procedure TRecordingBlitter.BlitV(const X, Y, Height: Cardinal; const Alpha: Byte);
begin
  Inc(FCallCount);

  for var Offset := 0 to ClampedCount(Height, FHeight) - 1 do
  begin
    Add(X, Int64(Y) + Offset, Alpha);
  end;
end;

procedure TRecordingBlitter.BlitAntiH2(const X, Y: Cardinal; const Alpha0, Alpha1: Byte);
begin
  Inc(FCallCount);

  Add(X, Y, Alpha0);
  Add(Int64(X) + 1, Y, Alpha1);
end;

procedure TRecordingBlitter.BlitAntiV2(const X, Y: Cardinal; const Alpha0, Alpha1: Byte);
begin
  Inc(FCallCount);

  Add(X, Y, Alpha0);
  Add(X, Int64(Y) + 1, Alpha1);
end;

procedure TRecordingBlitter.BlitRect(const Rect: TTsScreenIntRect);
begin
  Inc(FCallCount);

  for var Row := 0 to ClampedCount(Rect.Height, FHeight) - 1 do
  begin
    for var Column := 0 to ClampedCount(Rect.Width, FWidth) - 1 do
    begin
      Add(Int64(Rect.Left) + Column, Int64(Rect.Top) + Row, FullCoverage);
    end;
  end;
end;

function TRecordingBlitter.CoverageAt(const X, Y: Integer): Integer;
begin
  const IsInside = ((X >= 0) and (X < FWidth) and (Y >= 0) and (Y < FHeight));
  if not IsInside then
  begin
    Exit(0);
  end;

  Result := FCoverage[Y * FWidth + X];
end;

function TRecordingBlitter.CountPixelsWithCoverage: Integer;
begin
  Result := 0;
  for var Value in FCoverage do
  begin
    if Value <> 0 then
    begin
      Inc(Result);
    end;
  end;
end;

function TRecordingBlitter.CompositedTotal: Int64;
begin
  Result := 0;
  for var Value in FComposited do
  begin
    Inc(Result, Value);
  end;
end;

function TRecordingBlitter.TotalCoverage: Int64;
begin
  Result := 0;
  for var Value in FCoverage do
  begin
    Inc(Result, Value);
  end;
end;

end.
