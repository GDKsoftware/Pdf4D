// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.RenderCompare;

{$EXCESSPRECISION OFF}
{$POINTERMATH ON}

interface

uses
  System.SysUtils,
  Pdf4D.Render.Bitmap;

type
  TRenderComparison = record
    HasSameSize: Boolean;
    DifferentPixels: Int64;
    TotalPixels: Int64;
    // The largest difference of one channel over the whole bitmap
    MaxDifference: Integer;

    function DifferentFraction: Double;
    function IsEqual: Boolean;
    function Describe: string;
  end;

  TRenderVerdict = record
    IsFailure: Boolean;
    Message: string;
  end;

  // Compares a render with a reference image of PDFBox under the rules of docs/golden-format.md ("Render reference files")
  TRenderCompare = record
  public const
    // A pixel differs when a channel differs by more than this
    PixelTolerance = 16;
    // A page is equal when at most this share of its pixels differs
    MaxDifferentFraction = 0.01;

  strict private
    class function ChannelDifference(const Actual, Expected: PByte): Integer; static;

  public
    class function Compare(const Actual, Expected: TPdfBitmap): TRenderComparison; static;
    // Red where a pixel differs, the reference dimmed elsewhere; the Actual render alone when the sizes differ
    class procedure WriteDifference(const Actual, Expected: TPdfBitmap; const FileName: string); static;

    // The entries "page <n> [<platform>] # <reason>" of a render-known-differences file say that a page is skipped, on one platform or on all
    class function IsKnownDifference(const Entries: TArray<string>; const Page: Integer; const PlatformName: string): Boolean; static;
    // The files of a pending.txt ("<corpus file> # Task <n>: <subject>"); a missing file gives none
    class function PendingFiles(const FileName: string): TArray<string>; static;
    // The result for one file: Differences describe the pages that differ and are not known differences
    class function Judge(const IsPending: Boolean; const Differences: TArray<string>): TRenderVerdict; static;
  end;

implementation

uses
  System.IOUtils,
  Pdf4D.Tests.Png;

const
  CommentMarker = '#';
  PageMarker = 'page ';
  BytesPerPixel = 4;
  RedChannel = 0;
  GreenChannel = 1;
  BlueChannel = 2;
  AlphaChannel = 3;
  Opaque = 255;
  DimmedDivisor = 3;
  DimmedOffset = 170;

{ TRenderComparison }

function TRenderComparison.DifferentFraction: Double;
begin
  if TotalPixels = 0 then
  begin
    Result := 0;
  end
  else
  begin
    Result := DifferentPixels / TotalPixels;
  end;
end;

function TRenderComparison.IsEqual: Boolean;
begin
  Result := HasSameSize and (DifferentFraction <= TRenderCompare.MaxDifferentFraction);
end;

function TRenderComparison.Describe: string;
begin
  if not HasSameSize then
  begin
    Result := 'different size';
  end
  else
  begin
    Result := Format('%.3f%% of the pixels differ, largest difference %d', [DifferentFraction * 100, MaxDifference]);
  end;
end;

{ TRenderCompare }

class function TRenderCompare.ChannelDifference(const Actual, Expected: PByte): Integer;
begin
  Result := 0;
  for var Channel := RedChannel to AlphaChannel do
  begin
    const Difference = Abs(Integer(Actual[Channel]) - Integer(Expected[Channel]));
    if Difference > Result then
    begin
      Result := Difference;
    end;
  end;
end;

class function TRenderCompare.Compare(const Actual, Expected: TPdfBitmap): TRenderComparison;
begin
  Result := Default(TRenderComparison);
  Result.HasSameSize := (Actual.Width = Expected.Width) and (Actual.Height = Expected.Height);
  if not Result.HasSameSize then
  begin
    Exit;
  end;

  Result.TotalPixels := Int64(Actual.Width) * Actual.Height;
  for var Y := 0 to Actual.Height - 1 do
  begin
    const ActualRow = Actual.ScanLine(Y);
    const ExpectedRow = Expected.ScanLine(Y);
    for var X := 0 to Actual.Width - 1 do
    begin
      const Difference = ChannelDifference(@ActualRow[X * BytesPerPixel], @ExpectedRow[X * BytesPerPixel]);
      if Difference > Result.MaxDifference then
      begin
        Result.MaxDifference := Difference;
      end;
      if Difference > PixelTolerance then
      begin
        Inc(Result.DifferentPixels);
      end;
    end;
  end;
end;

class procedure TRenderCompare.WriteDifference(const Actual, Expected: TPdfBitmap; const FileName: string);
begin
  const HasSameSize = (Actual.Width = Expected.Width) and (Actual.Height = Expected.Height);
  if not HasSameSize then
  begin
    TPng.Write(Actual, FileName);
    Exit;
  end;

  const Image = TPdfBitmap.Create(Actual.Width, Actual.Height);
  try
    for var Y := 0 to Actual.Height - 1 do
    begin
      const ActualRow = Actual.ScanLine(Y);
      const ExpectedRow = Expected.ScanLine(Y);
      const ImageRow = Image.ScanLine(Y);
      for var X := 0 to Actual.Width - 1 do
      begin
        const Offset = X * BytesPerPixel;
        if ChannelDifference(@ActualRow[Offset], @ExpectedRow[Offset]) > PixelTolerance then
        begin
          ImageRow[Offset + RedChannel] := Opaque;
          ImageRow[Offset + GreenChannel] := 0;
          ImageRow[Offset + BlueChannel] := 0;
        end
        else
        begin
          ImageRow[Offset + RedChannel] := DimmedOffset + ExpectedRow[Offset + RedChannel] div DimmedDivisor;
          ImageRow[Offset + GreenChannel] := DimmedOffset + ExpectedRow[Offset + GreenChannel] div DimmedDivisor;
          ImageRow[Offset + BlueChannel] := DimmedOffset + ExpectedRow[Offset + BlueChannel] div DimmedDivisor;
        end;
        ImageRow[Offset + AlphaChannel] := Opaque;
      end;
    end;
    TPng.Write(Image, FileName);
  finally
    Image.Free;
  end;
end;

class function TRenderCompare.IsKnownDifference(const Entries: TArray<string>; const Page: Integer; const PlatformName: string): Boolean;
begin
  Result := False;
  for var Entry in Entries do
  begin
    var Head := Entry;
    const Hash = Head.IndexOf(CommentMarker);
    if Hash >= 0 then
    begin
      Head := Head.Substring(0, Hash);
    end;
    Head := Head.Trim;
    if not Head.StartsWith(PageMarker) then
    begin
      Continue;
    end;

    var EntryPlatform := '';
    var PageText := Head.Substring(PageMarker.Length).Trim;
    const Space = PageText.IndexOf(' ');
    if Space >= 0 then
    begin
      EntryPlatform := PageText.Substring(Space + 1).Trim.Trim(['[', ']']);
      PageText := PageText.Substring(0, Space);
    end;

    const IsOnThisPlatform = (EntryPlatform = '') or (EntryPlatform = PlatformName);
    if (StrToIntDef(PageText, -1) = Page) and IsOnThisPlatform then
    begin
      Exit(True);
    end;
  end;
end;

class function TRenderCompare.PendingFiles(const FileName: string): TArray<string>;
begin
  Result := nil;
  if not TFile.Exists(FileName) then
  begin
    Exit;
  end;

  for var Line in TFile.ReadAllLines(FileName, TEncoding.UTF8) do
  begin
    const Trimmed = Line.Trim;
    if (Trimmed = '') or Trimmed.StartsWith(CommentMarker) then
    begin
      Continue;
    end;

    const Hash = Trimmed.IndexOf(' ' + CommentMarker);
    if Hash >= 0 then
    begin
      Result := Result + [Trimmed.Substring(0, Hash).Trim];
    end
    else
    begin
      Result := Result + [Trimmed];
    end;
  end;
end;

class function TRenderCompare.Judge(const IsPending: Boolean; const Differences: TArray<string>): TRenderVerdict;
begin
  Result := Default(TRenderVerdict);
  const HasDifferences = Length(Differences) > 0;
  if IsPending then
  begin
    Result.IsFailure := not HasDifferences;
    if Result.IsFailure then
    begin
      Result.Message := 'every page is equal to the reference: remove from pending.txt';
    end;
  end
  else
  begin
    Result.IsFailure := HasDifferences;
    if HasDifferences then
    begin
      Result.Message := string.Join(sLineBreak, Differences);
    end;
  end;
end;

end.
