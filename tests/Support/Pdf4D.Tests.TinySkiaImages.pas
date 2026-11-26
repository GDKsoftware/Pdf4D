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
  Pdf4D.Render.Native.Pixmap,
  Pdf4D.Render.Native.Mask;

type
  // What a known difference allows: Tolerance is the largest difference of a channel that every pixel may have. With a pixel limit
  // (the Pixels and Steps of an entry), at most Pixels pixels may differ by up to Steps, and all other pixels must be equal.
  TTinySkiaAllowance = record
    Tolerance: Integer;
    Pixels: Integer;
    Steps: Integer;
  end;

  // The reference images of tiny-skia (tests/reference/tiny-skia, the tests/images folder of the tiny-skia source) and their comparison
  TTinySkiaImages = record
  strict private
    const ReferenceEnvironmentVariable = 'PDF4D_TINYSKIA_REFERENCE';
    const OutputEnvironmentVariable = 'PDF4D_RENDER_OUTPUT';
    const KnownDifferencesName = 'known-differences.txt';
    // The largest difference of a channel that a known difference may have
    const KnownDifferenceTolerance = 2;

    class function Folder: string; static;
    class function LoadPremultiplied(const RelativePng: string; out Width, Height: Integer): TBytes; static;
    class procedure WriteOutput(const Pixmap: TTsPixmap; const RelativePng: string); static;

  public
    // The full name of a file below tests/reference/tiny-skia
    class function ReferenceFile(const RelativePath: string): string; static;

    // The name of the platform in the entries of known-differences.txt: Win32, Win64 or Linux64
    class function PlatformName: string; static;

    // What the lines of known-differences.txt allow for the PNG on a platform. The first line that names the PNG (and the platform, or no
    // platform) counts. A PNG that is not listed gets the allowance 0. The line format is documented in docs/golden-format.md; a line that
    // does not follow it fails the test.
    class function AllowanceFor(const Lines: TArray<string>; const RelativePng, Platform: string): TTinySkiaAllowance; static;

    // Loads tests/reference/tiny-skia/<RelativePng> and premultiplies it like Pixmap::load_png does; the pixmap must be byte equal. When
    // the PNG is listed in known-differences.txt ("<path> [<platform>] # reason"), every channel may differ by 2; an entry with a pixel
    // limit ("<path> [Win32] pixels=<n> steps=<m> # reason") instead lets at most n pixels differ by up to m steps. A failed comparison
    // writes the pixmap to the folder of PDF4D_RENDER_OUTPUT when that is set.
    class procedure AssertMatches(const Pixmap: TTsPixmap; const RelativePng: string); static;

    // The same for a mask and a grayscale PNG (Mask::load_png): the data must be byte equal
    class procedure AssertMaskMatches(const Mask: TTsMask; const RelativePng: string); static;
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
    // The sum of all bytes of the pixmap and the number of pixels with an alpha above zero, for the tests that only have to not panic: the
    // expected values come from a run of the tiny-skia source
    class procedure AssertTotals(const Pixmap: TTsPixmap; const ByteSum: Int64; const DrawnPixels: Integer); static;
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

class procedure TTinySkiaFixtures.AssertTotals(const Pixmap: TTsPixmap; const ByteSum: Int64; const DrawnPixels: Integer);
begin
  var ActualSum: Int64 := 0;
  for var Value in Pixmap.Data do
  begin
    Inc(ActualSum, Value);
  end;

  var ActualDrawn := 0;
  for var I := 0 to Integer(Pixmap.Width * Pixmap.Height) - 1 do
  begin
    if Pixmap.Data[I * 4 + 3] <> 0 then
    begin
      Inc(ActualDrawn);
    end;
  end;

  Assert.AreEqual<Int64>(ByteSum, ActualSum, 'the sum of all bytes');
  Assert.AreEqual<Integer>(DrawnPixels, ActualDrawn, 'the number of pixels with an alpha above zero');
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

class function TTinySkiaImages.ReferenceFile(const RelativePath: string): string;
begin
  Result := TPath.Combine(Folder, RelativePath);
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

class function TTinySkiaImages.AllowanceFor(const Lines: TArray<string>; const RelativePng, Platform: string): TTinySkiaAllowance;
begin
  Result := Default(TTinySkiaAllowance);

  for var Line in Lines do
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

    var Platforms := '';
    var Limits := '';
    const OpenBracket = Pos('[', Entry);
    if OpenBracket > 0 then
    begin
      // A line with an opening bracket but no closing one would silently hold on every platform
      const CloseBracket = Pos(']', Entry);
      Assert.IsTrue(CloseBracket > OpenBracket, Format('%s: the line "%s" has no closing bracket', [KnownDifferencesName, Line]));
      Platforms := Copy(Entry, OpenBracket + 1, CloseBracket - OpenBracket - 1);
      Limits := Trim(Copy(Entry, CloseBracket + 1, MaxInt));
      Entry := Trim(Copy(Entry, 1, OpenBracket - 1));
    end
    else
    begin
      // The limits of a line without a platform are read as well, so that they fail below instead of being ignored
      const Space = Pos(' ', Entry);
      if Space > 0 then
      begin
        Limits := Trim(Copy(Entry, Space + 1, MaxInt));
        Entry := Copy(Entry, 1, Space - 1);
      end;
    end;

    var Pixels := 0;
    var Steps := 0;
    for var Token in SplitString(Limits, ' ') do
    begin
      if Token = '' then
      begin
        Continue;
      end;

      if Token.StartsWith('pixels=') then
      begin
        Pixels := StrToIntDef(Copy(Token, 8, MaxInt), 0);
      end
      else if Token.StartsWith('steps=') then
      begin
        Steps := StrToIntDef(Copy(Token, 7, MaxInt), 0);
      end
      else
      begin
        Assert.Fail(Format('%s: the line "%s" has the unknown text "%s" after the platform', [KnownDifferencesName, Line, Token]));
      end;
    end;

    // A pixel limit needs both numbers and a platform: without a platform it would also loosen the platforms that match exactly
    Assert.IsTrue((Pixels > 0) = (Steps > 0), Format('%s: the line "%s" needs both pixels=<n> and steps=<m>', [KnownDifferencesName, Line]));
    Assert.IsTrue((Pixels = 0) or (Platforms <> ''), Format('%s: the line "%s" has a pixel limit without a platform', [KnownDifferencesName, Line]));
    Assert.IsTrue((Steps = 0) or (Steps > KnownDifferenceTolerance), Format('%s: the line "%s" needs steps above %d', [KnownDifferencesName, Line, KnownDifferenceTolerance]));

    if SameText(Entry, RelativePng) and ((Platforms = '') or ContainsText(Platforms, Platform)) then
    begin
      if Pixels > 0 then
      begin
        Result.Pixels := Pixels;
        Result.Steps := Steps;
      end
      else
      begin
        Result.Tolerance := KnownDifferenceTolerance;
      end;
      Exit;
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

  var Lines: TArray<string> := nil;
  const KnownDifferences = TPath.Combine(Folder, KnownDifferencesName);
  if TFile.Exists(KnownDifferences) then
  begin
    Lines := TFile.ReadAllLines(KnownDifferences);
  end;

  const Allowance = AllowanceFor(Lines, RelativePng, PlatformName);
  const Tolerance = Allowance.Tolerance;

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

  if (DifferentPixels > Allowance.Pixels) or (MaxDifference > Max(Allowance.Steps, Tolerance)) then
  begin
    WriteOutput(Pixmap, RelativePng);
    Assert.Fail(Format('%s: %d pixels differ by at most %d channel steps; the first at (%d, %d): got %d,%d,%d,%d expected %d,%d,%d,%d',
      [RelativePng, DifferentPixels, MaxDifference, FirstDifferent mod Width, FirstDifferent div Width,
       Pixmap.Data[FirstDifferent * 4], Pixmap.Data[FirstDifferent * 4 + 1], Pixmap.Data[FirstDifferent * 4 + 2],
       Pixmap.Data[FirstDifferent * 4 + 3], Expected[FirstDifferent * 4], Expected[FirstDifferent * 4 + 1],
       Expected[FirstDifferent * 4 + 2], Expected[FirstDifferent * 4 + 3]]));
  end;
end;

class procedure TTinySkiaImages.AssertMaskMatches(const Mask: TTsMask; const RelativePng: string);
begin
  var Width, Height: Integer;
  const Straight = TPng.ReadStraight(TPath.Combine(Folder, RelativePng), Width, Height);

  Assert.IsTrue((Integer(Mask.Width) = Width) and (Integer(Mask.Height) = Height),
    Format('%s: the size is %d x %d, expected %d x %d', [RelativePng, Mask.Width, Mask.Height, Width, Height]));

  var DifferentBytes := 0;
  var FirstDifferent := -1;
  for var I := 0 to Width * Height - 1 do
  begin
    if Mask.Data[I] <> Straight[I * 4] then
    begin
      Inc(DifferentBytes);
      if FirstDifferent < 0 then
      begin
        FirstDifferent := I;
      end;
    end;
  end;

  if DifferentBytes > 0 then
  begin
    Assert.Fail(Format('%s: %d mask bytes differ; the first at (%d, %d): got %d expected %d',
      [RelativePng, DifferentBytes, FirstDifferent mod Width, FirstDifferent div Width, Mask.Data[FirstDifferent],
       Straight[FirstDifferent * 4]]));
  end;
end;

end.
