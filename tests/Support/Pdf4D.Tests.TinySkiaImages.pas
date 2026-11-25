// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.TinySkiaImages;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.Path,
  Pdf4D.Render.Native.Shader,
  Pdf4D.Render.Native.Pixmap;

type
  // The reference images of tiny-skia (tests/reference/tiny-skia, the tests/images folder of the tiny-skia source) and their comparison
  TTinySkiaImages = record
  strict private
    const ReferenceEnvironmentVariable = 'PDF4D_TINYSKIA_REFERENCE';
    const OutputEnvironmentVariable = 'PDF4D_RENDER_OUTPUT';
    const KnownDifferencesName = 'known-differences.txt';
    // The largest difference of a channel that a known difference may have
    const KnownDifferenceTolerance = 2;

    class function Folder: string; static;
    class function PlatformName: string; static;
    class function IsKnownDifference(const RelativePng: string): Boolean; static;
    class function LoadPremultiplied(const RelativePng: string; out Width, Height: Integer): TBytes; static;
    class procedure WriteOutput(const Pixmap: TTsPixmap; const RelativePng: string); static;

  public
    // Loads tests/reference/tiny-skia/<RelativePng> and premultiplies it like Pixmap::load_png does; the pixmap must be byte equal. When
    // the PNG is listed in known-differences.txt ("<path> [<platform>] # reason"), every channel may differ by 2. A failed comparison writes
    // the pixmap to the folder of PDF4D_RENDER_OUTPUT when that is set.
    class procedure AssertMatches(const Pixmap: TTsPixmap; const RelativePng: string); static;
  end;

  // The set-up that the integration tests of tiny-skia repeat: pixmaps, the paint rgba(50, 127, 150, 200), paths and rectangles that are known to be valid
  TTinySkiaFixtures = record
  public
    class function NewPixmap(const Width, Height: Cardinal): TTsPixmap; static;
    class function SolidPaint(const AntiAlias: Boolean): TTsPaint; static;
    class function FinishPath(var Builder: TTsPathBuilder): TTsPath; static;
    class function RectXYWH(const X, Y, Width, Height: Single): TTsRect; static;
    class function RectLTRB(const Left, Top, Right, Bottom: Single): TTsRect; static;
    // The pixel (X, Y) is the premultiplied color of the straight RGBA values
    class procedure AssertPixel(const Pixmap: TTsPixmap; const X, Y: Cardinal; const R, G, B, A: Byte); static;
  end;

implementation

uses
  System.Classes,
  System.Math,
  System.IOUtils,
  System.StrUtils,
  DUnitX.TestFramework,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Native.Color,
  Pdf4D.Tests.Png;

{ TTinySkiaFixtures }

class function TTinySkiaFixtures.NewPixmap(const Width, Height: Cardinal): TTsPixmap;
begin
  Assert.IsTrue(TTsPixmap.TryCreate(Width, Height, Result));
end;

class function TTinySkiaFixtures.SolidPaint(const AntiAlias: Boolean): TTsPaint;
begin
  Result := TTsPaint.Default;
  Result.Shader := TTsShader.NewSolidColor(TTsColor.FromRgba8(50, 127, 150, 200));
  Result.AntiAlias := AntiAlias;
end;

class function TTinySkiaFixtures.FinishPath(var Builder: TTsPathBuilder): TTsPath;
begin
  Assert.IsTrue(Builder.TryFinish(Result));
end;

class function TTinySkiaFixtures.RectXYWH(const X, Y, Width, Height: Single): TTsRect;
begin
  Assert.IsTrue(TTsRect.TryFromXYWH(X, Y, Width, Height, Result));
end;

class function TTinySkiaFixtures.RectLTRB(const Left, Top, Right, Bottom: Single): TTsRect;
begin
  Assert.IsTrue(TTsRect.TryFromLTRB(Left, Top, Right, Bottom, Result));
end;

class procedure TTinySkiaFixtures.AssertPixel(const Pixmap: TTsPixmap; const X, Y: Cardinal; const R, G, B, A: Byte);
begin
  var Actual: TTsPremultipliedColorU8;
  Assert.IsTrue(Pixmap.TryPixel(X, Y, Actual));

  const Expected = TTsColorU8.FromRgba(R, G, B, A).Premultiply;
  Assert.IsTrue(Actual = Expected, Format('pixel (%d, %d): got %d,%d,%d,%d expected %d,%d,%d,%d',
    [X, Y, Actual.Red, Actual.Green, Actual.Blue, Actual.Alpha, Expected.Red, Expected.Green, Expected.Blue, Expected.Alpha]));
end;

{ TTinySkiaImages }

class function TTinySkiaImages.Folder: string;
begin
  const FromEnvironment = GetEnvironmentVariable(ReferenceEnvironmentVariable);
  if FromEnvironment <> '' then
  begin
    Exit(FromEnvironment);
  end;

  var Current := TPath.GetDirectoryName(ParamStr(0));
  while Current <> '' do
  begin
    const Candidate = TPath.Combine(TPath.Combine(Current, 'reference'), 'tiny-skia');
    if TDirectory.Exists(Candidate) then
    begin
      Exit(Candidate);
    end;

    const Parent = TPath.GetDirectoryName(Current);
    if Parent = Current then
    begin
      Break;
    end;
    Current := Parent;
  end;
  raise EFileNotFoundException.Create('The tiny-skia reference folder (tests/reference/tiny-skia) was not found; set ' +
                                      ReferenceEnvironmentVariable);
end;

class function TTinySkiaImages.PlatformName: string;
begin
  {$IF Defined(MSWINDOWS) and Defined(CPUX64)}
  Result := 'Win64';
  {$ELSEIF Defined(MSWINDOWS)}
  Result := 'Win32';
  {$ELSEIF Defined(LINUX)}
  Result := 'Linux64';
  {$ELSE}
  Result := '';
  {$ENDIF}
end;

class function TTinySkiaImages.IsKnownDifference(const RelativePng: string): Boolean;
begin
  Result := False;

  const FileName = TPath.Combine(Folder, KnownDifferencesName);
  if not TFile.Exists(FileName) then
  begin
    Exit;
  end;

  for var Line in TFile.ReadAllLines(FileName) do
  begin
    var Entry := Trim(Line);
    if (Entry = '') or Entry.StartsWith('#') then
    begin
      Continue;
    end;

    const Comment = Pos('#', Entry);
    if Comment > 0 then
    begin
      Entry := Trim(Copy(Entry, 1, Comment - 1));
    end;

    const Platform = Pos('[', Entry);
    var Platforms := '';
    if Platform > 0 then
    begin
      Platforms := Copy(Entry, Platform + 1, Pos(']', Entry) - Platform - 1);
      Entry := Trim(Copy(Entry, 1, Platform - 1));
    end;

    if SameText(Entry, RelativePng) and ((Platforms = '') or ContainsText(Platforms, PlatformName)) then
    begin
      Exit(True);
    end;
  end;
end;

class function TTinySkiaImages.LoadPremultiplied(const RelativePng: string; out Width, Height: Integer): TBytes;
begin
  const Straight = TPng.ReadStraight(TPath.Combine(Folder, RelativePng), Width, Height);

  SetLength(Result, Length(Straight));
  for var I := 0 to Width * Height - 1 do
  begin
    const Color = TTsColorU8.FromRgba(Straight[I * 4], Straight[I * 4 + 1], Straight[I * 4 + 2], Straight[I * 4 + 3]).Premultiply;
    Result[I * 4] := Color.Red;
    Result[I * 4 + 1] := Color.Green;
    Result[I * 4 + 2] := Color.Blue;
    Result[I * 4 + 3] := Color.Alpha;
  end;
end;

class procedure TTinySkiaImages.WriteOutput(const Pixmap: TTsPixmap; const RelativePng: string);
begin
  const Target = GetEnvironmentVariable(OutputEnvironmentVariable);
  if Target = '' then
  begin
    Exit;
  end;

  TDirectory.CreateDirectory(Target);
  const Bitmap = TPdfBitmap.Create(Integer(Pixmap.Width), Integer(Pixmap.Height));
  try
    Move(Pixmap.Data[0], Bitmap.Pixels[0], Length(Pixmap.Data));
    TPng.Write(Bitmap, TPath.Combine(Target, ReplaceStr(RelativePng, '/', '__')));
  finally
    Bitmap.Free;
  end;
end;

class procedure TTinySkiaImages.AssertMatches(const Pixmap: TTsPixmap; const RelativePng: string);
begin
  var Width, Height: Integer;
  const Expected = LoadPremultiplied(RelativePng, Width, Height);

  if (Integer(Pixmap.Width) <> Width) or (Integer(Pixmap.Height) <> Height) then
  begin
    WriteOutput(Pixmap, RelativePng);
    Assert.Fail(Format('%s: the size is %d x %d, expected %d x %d', [RelativePng, Pixmap.Width, Pixmap.Height, Width, Height]));
  end;

  const Tolerance = IfThen(IsKnownDifference(RelativePng), KnownDifferenceTolerance, 0);

  var DifferentPixels := 0;
  var MaxDifference := 0;
  var FirstDifferent := -1;
  for var I := 0 to Width * Height - 1 do
  begin
    var PixelDifference := 0;
    for var Channel := 0 to 3 do
    begin
      PixelDifference := Max(PixelDifference, Abs(Integer(Pixmap.Data[I * 4 + Channel]) - Integer(Expected[I * 4 + Channel])));
    end;

    if PixelDifference > Tolerance then
    begin
      Inc(DifferentPixels);
      MaxDifference := Max(MaxDifference, PixelDifference);
      if FirstDifferent < 0 then
      begin
        FirstDifferent := I;
      end;
    end;
  end;

  if DifferentPixels > 0 then
  begin
    WriteOutput(Pixmap, RelativePng);
    Assert.Fail(Format('%s: %d pixels differ by at most %d channel steps; the first at (%d, %d): got %d,%d,%d,%d expected %d,%d,%d,%d',
      [RelativePng, DifferentPixels, MaxDifference, FirstDifferent mod Width, FirstDifferent div Width,
       Pixmap.Data[FirstDifferent * 4], Pixmap.Data[FirstDifferent * 4 + 1], Pixmap.Data[FirstDifferent * 4 + 2],
       Pixmap.Data[FirstDifferent * 4 + 3], Expected[FirstDifferent * 4], Expected[FirstDifferent * 4 + 1],
       Expected[FirstDifferent * 4 + 2], Expected[FirstDifferent * 4 + 3]]));
  end;
end;

end.
