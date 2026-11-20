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
    TotalPixels: Int64;
    // Pixels whose 3 x 3 neighbourhood in the reference is flat (the inside of a shape, the background) and those that have an edge
    // in it, and how many of each differ by more than the tolerance of their kind
    FlatPixels: Int64;
    DifferentFlatPixels: Int64;
    EdgePixels: Int64;
    DifferentEdgePixels: Int64;
    // The largest difference of one channel over the whole bitmap
    MaxDifference: Integer;

    function DifferentPixels: Int64;
    function DifferentFraction: Double;
    function DifferentFlatFraction: Double;
    function DifferentEdgeFraction: Double;
    function IsEqual: Boolean;
    function Describe: string;
  end;

  TRenderVerdict = record
    IsFailure: Boolean;
    Message: string;
  end;

  // Compares a render with a reference image of PDFBox under the rules of docs/golden-format.md ("Render reference files"). The
  // reference decides what a pixel is: in a flat area the two renders must agree closely, because a wrong colour or a missing shape
  // shows there; at an edge the coverage of the rasterizers (Marlin of Java2D, Skia) differs, so the tolerance is wide and the
  // share that may differ is measured against the edge pixels. All numbers are here, and Task 29 tunes them.
  TRenderCompare = record
  public const
    // A pixel is an edge pixel when, in the 3 x 3 pixels around it in the reference, one channel differs by more than this
    FlatRange = 8;
    // A flat pixel differs when a channel differs by more than this ...
    FlatTolerance = 16;
    // ... and a page needs at most this share of its flat pixels to differ
    MaxFlatDifferentFraction: Double = 0.001;
    // An edge pixel differs when a channel differs by more than this (Marlin and Skia coverage differ at the edge of a glyph by that
    // much; a missing or misplaced shape differs by far more) ...
    EdgeTolerance = 96;
    // ... and a page needs at most this share of its edge pixels to differ. Measured on the corpus: the pages without a known
    // difference stay under 5.6%; the most are generated/render/clip.pdf (5.5%) and text-modes.pdf page 2 (5.2%), where a hard clip
    // follows a line that passes exactly through pixel centres and Skia and Java2D break the tie differently. Pages with a missing
    // annotation or form field are at 10% and more.
    MaxEdgeDifferentFraction: Double = 0.06;

  strict private
    class function ChannelDifference(const Actual, Expected: PByte): Integer; static;
    class function IsPixelDifferent(const Difference: Integer; const IsEdge: Boolean): Boolean; static;

  public
    class function Compare(const Actual, Expected: TPdfBitmap): TRenderComparison; static;
    // How many pixels have a channel that differs by more than Tolerance, not counting the Margin pixels along each side. For two renders
    // of the same renderer, where the classes of the pixels do not matter. The bitmaps must have the same size.
    class function CountAbove(const Actual, Expected: TPdfBitmap; const Tolerance, Margin: Integer): Int64; static;
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
  System.Math,
  Pdf4D.Tests.Png;

const
  CommentMarker = '#';
  PageMarker = 'page ';
  BytesPerPixel = 4;
  ColorChannels = 3;
  RedChannel = 0;
  GreenChannel = 1;
  BlueChannel = 2;
  AlphaChannel = 3;
  Opaque = 255;
  DimmedDivisor = 3;
  DimmedOffset = 170;
  PercentFactor = 100;

type
  // Tells for the rows of the reference which pixels have an edge in their 3 x 3 neighbourhood. The minimum and the maximum of the
  // three pixels of each row are kept for three rows, so the memory is a few rows, not the image.
  TEdgeMap = class
  private
    FReference: TPdfBitmap;
    FRowMinimum: array[0..2] of TArray<Byte>;
    FRowMaximum: array[0..2] of TArray<Byte>;
    FCachedRows: array[0..2] of Integer;

    procedure LoadRow(const Slot, Y: Integer);
    function SlotOf(const Y: Integer): Integer;

  public
    constructor Create(const Reference: TPdfBitmap);

    // IsEdge[X] for the row Y
    procedure Classify(const Y: Integer; var IsEdge: TArray<Boolean>);
  end;

{ TEdgeMap }

constructor TEdgeMap.Create(const Reference: TPdfBitmap);
begin
  inherited Create;
  FReference := Reference;
  for var Slot := 0 to 2 do
  begin
    SetLength(FRowMinimum[Slot], Reference.Width * ColorChannels);
    SetLength(FRowMaximum[Slot], Reference.Width * ColorChannels);
    FCachedRows[Slot] := -1;
  end;
end;

// The minimum and maximum over the pixel and its left and right neighbour, for every colour channel
procedure TEdgeMap.LoadRow(const Slot, Y: Integer);
begin
  FCachedRows[Slot] := Y;
  const Row = FReference.ScanLine(Y);
  const Last = FReference.Width - 1;
  for var X := 0 to Last do
  begin
    for var Channel := 0 to ColorChannels - 1 do
    begin
      const Value = Row[X * BytesPerPixel + Channel];
      const Left = Row[Max(X - 1, 0) * BytesPerPixel + Channel];
      const Right = Row[Min(X + 1, Last) * BytesPerPixel + Channel];
      FRowMinimum[Slot][X * ColorChannels + Channel] := Min(Value, Min(Left, Right));
      FRowMaximum[Slot][X * ColorChannels + Channel] := Max(Value, Max(Left, Right));
    end;
  end;
end;

function TEdgeMap.SlotOf(const Y: Integer): Integer;
begin
  // The rows Y - 1, Y and Y + 1 are asked for in turn, so a row stays in the slot of its number modulo 3
  Result := Y mod 3;
  if FCachedRows[Result] <> Y then
  begin
    LoadRow(Result, Y);
  end;
end;

procedure TEdgeMap.Classify(const Y: Integer; var IsEdge: TArray<Boolean>);
begin
  const Above = SlotOf(Max(Y - 1, 0));
  const Current = SlotOf(Y);
  const Below = SlotOf(Min(Y + 1, FReference.Height - 1));
  for var X := 0 to FReference.Width - 1 do
  begin
    IsEdge[X] := False;
    for var Channel := 0 to ColorChannels - 1 do
    begin
      const Index = X * ColorChannels + Channel;
      const Highest = Max(FRowMaximum[Above][Index], Max(FRowMaximum[Current][Index], FRowMaximum[Below][Index]));
      const Lowest = Min(FRowMinimum[Above][Index], Min(FRowMinimum[Current][Index], FRowMinimum[Below][Index]));
      if Highest - Lowest > TRenderCompare.FlatRange then
      begin
        IsEdge[X] := True;
        Break;
      end;
    end;
  end;
end;

{ TRenderComparison }

function TRenderComparison.DifferentPixels: Int64;
begin
  Result := DifferentFlatPixels + DifferentEdgePixels;
end;

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

function TRenderComparison.DifferentFlatFraction: Double;
begin
  if FlatPixels = 0 then
  begin
    Result := 0;
  end
  else
  begin
    Result := DifferentFlatPixels / FlatPixels;
  end;
end;

function TRenderComparison.DifferentEdgeFraction: Double;
begin
  if EdgePixels = 0 then
  begin
    Result := 0;
  end
  else
  begin
    Result := DifferentEdgePixels / EdgePixels;
  end;
end;

function TRenderComparison.IsEqual: Boolean;
begin
  Result := HasSameSize and (DifferentFlatPixels <= TRenderCompare.MaxFlatDifferentFraction * FlatPixels) and
            (DifferentEdgePixels <= TRenderCompare.MaxEdgeDifferentFraction * EdgePixels);
end;

function TRenderComparison.Describe: string;
begin
  if not HasSameSize then
  begin
    Result := 'different size';
  end
  else
  begin
    Result := Format('%.3f%% of the flat pixels differ (%d of %d), %.3f%% of the edge pixels (%d of %d), largest difference %d',
                     [DifferentFlatFraction * PercentFactor, DifferentFlatPixels, FlatPixels, DifferentEdgeFraction * PercentFactor,
                      DifferentEdgePixels, EdgePixels, MaxDifference]);
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

class function TRenderCompare.IsPixelDifferent(const Difference: Integer; const IsEdge: Boolean): Boolean;
begin
  if IsEdge then
  begin
    Result := (Difference > EdgeTolerance);
  end
  else
  begin
    Result := (Difference > FlatTolerance);
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
  const Edges = TEdgeMap.Create(Expected);
  try
    var IsEdge: TArray<Boolean>;
    SetLength(IsEdge, Actual.Width);
    for var Y := 0 to Actual.Height - 1 do
    begin
      Edges.Classify(Y, IsEdge);
      const ActualRow = Actual.ScanLine(Y);
      const ExpectedRow = Expected.ScanLine(Y);
      for var X := 0 to Actual.Width - 1 do
      begin
        const Difference = ChannelDifference(@ActualRow[X * BytesPerPixel], @ExpectedRow[X * BytesPerPixel]);
        if Difference > Result.MaxDifference then
        begin
          Result.MaxDifference := Difference;
        end;

        if IsEdge[X] then
        begin
          Inc(Result.EdgePixels);
        end
        else
        begin
          Inc(Result.FlatPixels);
        end;
        if IsPixelDifferent(Difference, IsEdge[X]) then
        begin
          if IsEdge[X] then
          begin
            Inc(Result.DifferentEdgePixels);
          end
          else
          begin
            Inc(Result.DifferentFlatPixels);
          end;
        end;
      end;
    end;
  finally
    Edges.Free;
  end;
end;

class function TRenderCompare.CountAbove(const Actual, Expected: TPdfBitmap; const Tolerance, Margin: Integer): Int64;
begin
  Result := 0;
  for var Y := Margin to Actual.Height - 1 - Margin do
  begin
    const ActualRow = Actual.ScanLine(Y);
    const ExpectedRow = Expected.ScanLine(Y);
    for var X := Margin to Actual.Width - 1 - Margin do
    begin
      if ChannelDifference(@ActualRow[X * BytesPerPixel], @ExpectedRow[X * BytesPerPixel]) > Tolerance then
      begin
        Inc(Result);
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
  const Edges = TEdgeMap.Create(Expected);
  try
    var IsEdge: TArray<Boolean>;
    SetLength(IsEdge, Actual.Width);
    for var Y := 0 to Actual.Height - 1 do
    begin
      Edges.Classify(Y, IsEdge);
      const ActualRow = Actual.ScanLine(Y);
      const ExpectedRow = Expected.ScanLine(Y);
      const ImageRow = Image.ScanLine(Y);
      for var X := 0 to Actual.Width - 1 do
      begin
        const Offset = X * BytesPerPixel;
        if IsPixelDifferent(ChannelDifference(@ActualRow[Offset], @ExpectedRow[Offset]), IsEdge[X]) then
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
    Edges.Free;
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
