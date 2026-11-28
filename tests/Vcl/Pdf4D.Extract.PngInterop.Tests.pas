// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Extract.PngInterop.Tests;

interface

uses
  System.SysUtils,
  Vcl.Imaging.pngimage,
  DUnitX.TestFramework,
  Pdf4D.Extract.Png;

type
  // The PNG decoder of the VCL is independent of the one of the test support, so it checks the encoder output
  [TestFixture]
  TPdfPngInteropTests = class
  private
    function Pattern(const Width, Height: Integer): TBytes;
    function Decode(const Png: TBytes): TPngImage;
    procedure CheckVclPixels(const Pixels: TBytes; const Width, Height: Integer; const ColorType: TPdfPngColorType);

  public
    [Test]
    procedure TestVclPngImageDecodesOurOutput;
  end;

implementation

uses
  System.Classes;

function TPdfPngInteropTests.Pattern(const Width, Height: Integer): TBytes;
begin
  Result := nil;
  SetLength(Result, Width * Height * 4);
  for var Y := 0 to Height - 1 do
  begin
    for var X := 0 to Width - 1 do
    begin
      const Offset = (Y * Width + X) * 4;
      Result[Offset] := Byte(X * 11 + Y * 3);
      Result[Offset + 1] := Byte(Y * 17 + X);
      Result[Offset + 2] := Byte(X * Y + 40);
      Result[Offset + 3] := Byte(255 - X * 6 - Y * 2);
    end;
  end;
end;

function TPdfPngInteropTests.Decode(const Png: TBytes): TPngImage;
begin
  const Stream = TBytesStream.Create(Png);
  try
    Result := TPngImage.Create;
    try
      Result.LoadFromStream(Stream);
    except
      Result.Free;
      raise;
    end;
  finally
    Stream.Free;
  end;
end;

procedure TPdfPngInteropTests.CheckVclPixels(const Pixels: TBytes; const Width, Height: Integer; const ColorType: TPdfPngColorType);
begin
  const Image = Decode(TPdfPngEncoder.Encode(Width, Height, Pixels, ColorType));
  try
    Assert.AreEqual(Width, Image.Width);
    Assert.AreEqual(Height, Image.Height);
    const ExpectedHasAlpha = (ColorType = TPdfPngColorType.Rgba);
    Assert.AreEqual(ExpectedHasAlpha, Image.Header.ColorType = COLOR_RGBALPHA);

    for var Y := 0 to Height - 1 do
    begin
      for var X := 0 to Width - 1 do
      begin
        const Offset = (Y * Width + X) * 4;
        const Color = Cardinal(Image.Pixels[X, Y]);
        Assert.AreEqual<Byte>(Pixels[Offset], Byte(Color and $FF), 'R');
        Assert.AreEqual<Byte>(Pixels[Offset + 1], Byte((Color shr 8) and $FF), 'G');
        Assert.AreEqual<Byte>(Pixels[Offset + 2], Byte((Color shr 16) and $FF), 'B');
        if ExpectedHasAlpha then
        begin
          Assert.AreEqual<Byte>(Pixels[Offset + 3], Image.AlphaScanline[Y][X], 'A');
        end;
      end;
    end;
  finally
    Image.Free;
  end;
end;

procedure TPdfPngInteropTests.TestVclPngImageDecodesOurOutput;
begin
  const Pixels = Pattern(23, 17);

  CheckVclPixels(Pixels, 23, 17, TPdfPngColorType.Rgba);
  CheckVclPixels(Pixels, 23, 17, TPdfPngColorType.Rgb);
end;

end.
