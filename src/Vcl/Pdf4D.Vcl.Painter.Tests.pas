// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Vcl.Painter.Tests;

{$EXCESSPRECISION OFF}
{$POINTERMATH ON}

interface

uses
  System.Types,
  System.SysUtils,
  Vcl.Graphics,
  DUnitX.TestFramework,
  Pdf4D.Render.Bitmap,
  Pdf4D.Vcl.Painter;

type
  [TestFixture]
  TPdfVclPainterTests = class
  private
    class function WhiteBitmap(const Size: Integer): Vcl.Graphics.TBitmap; static;
    class function PixelAt(const Bitmap: Vcl.Graphics.TBitmap; const X, Y: Integer): TPdfDeviceColor; static;

  public
    [Test]
    procedure TestImageSwapsToBgra;

    [Test]
    procedure TestFillPolygonWithAlpha;

    [Test]
    procedure TestFrameEllipseIsAntiAliased;

    [Test]
    procedure TestDrawImageScales;
  end;

implementation

uses
  System.UITypes;

const
  ColorTolerance = 2;
  RoughTolerance = 60;

{ TPdfVclPainterTests }

class function TPdfVclPainterTests.WhiteBitmap(const Size: Integer): Vcl.Graphics.TBitmap;
begin
  Result := Vcl.Graphics.TBitmap.Create;
  try
    Result.PixelFormat := pf24bit;
    Result.SetSize(Size, Size);
    Result.Canvas.Brush.Color := clWhite;
    Result.Canvas.FillRect(Rect(0, 0, Size, Size));
  except
    Result.Free;
    raise;
  end;
end;

class function TPdfVclPainterTests.PixelAt(const Bitmap: Vcl.Graphics.TBitmap; const X, Y: Integer): TPdfDeviceColor;
begin
  // A 24 bit bitmap holds B, G, R
  const Line = PByte(Bitmap.ScanLine[Y]) + X * 3;
  Result := TPdfDeviceColor.Create(Line[2], Line[1], Line[0]);
end;

procedure TPdfVclPainterTests.TestImageSwapsToBgra;
begin
  const Source = TPdfBitmap.Create(1, 1);
  try
    Source.SetPixel(0, 0, TPdfDeviceColor.Create(10, 20, 30, 255));

    const Image = TPdfVclImage.Create(Source);
    const Reference: IInterface = Image;
    const Line = PByte(Image.Bitmap.ScanLine[0]);

    Assert.AreEqual(1, Image.Width);
    Assert.AreEqual(1, Image.Height);
    Assert.AreEqual(30, Integer(Line[0]), 'blue');
    Assert.AreEqual(20, Integer(Line[1]), 'green');
    Assert.AreEqual(10, Integer(Line[2]), 'red');
    Assert.AreEqual(255, Integer(Line[3]), 'alpha');
    Assert.IsNotNull(Reference);
  finally
    Source.Free;
  end;
end;

procedure TPdfVclPainterTests.TestFillPolygonWithAlpha;
begin
  const Target = WhiteBitmap(20);
  try
    const Painter = TPdfVclPainter.Create(Target.Canvas);
    const Reference: IInterface = Painter;
    Painter.FillPolygon([TPointF.Create(-5, -5), TPointF.Create(25, -5), TPointF.Create(25, 25), TPointF.Create(-5, 25)], $80FF0000);

    const Pixel = PixelAt(Target, 10, 10);
    Assert.AreEqual(Double(255), Double(Pixel.R), ColorTolerance, 'red');
    Assert.AreEqual(Double(128), Double(Pixel.G), ColorTolerance, 'green');
    Assert.AreEqual(Double(128), Double(Pixel.B), ColorTolerance, 'blue');
    Assert.IsNotNull(Reference);
  finally
    Target.Free;
  end;
end;

procedure TPdfVclPainterTests.TestFrameEllipseIsAntiAliased;
begin
  const Target = WhiteBitmap(40);
  try
    const Painter = TPdfVclPainter.Create(Target.Canvas);
    const Reference: IInterface = Painter;
    Painter.FrameEllipse(TRectF.Create(5, 5, 35, 35), $FF000000, 2);

    var HasGray := False;
    var HasDark := False;
    for var Y := 0 to Target.Height - 1 do
    begin
      for var X := 0 to Target.Width - 1 do
      begin
        const Pixel = PixelAt(Target, X, Y);
        HasGray := HasGray or ((Pixel.R > 20) and (Pixel.R < 235));
        HasDark := HasDark or (Pixel.R < 20);
      end;
    end;

    Assert.IsTrue(HasDark, 'the frame is drawn');
    Assert.IsTrue(HasGray, 'the edge has partly covered pixels');
    Assert.AreEqual(255, Integer(PixelAt(Target, 20, 20).R), 'the inside stays empty');
    Assert.IsNotNull(Reference);
  finally
    Target.Free;
  end;
end;

procedure TPdfVclPainterTests.TestDrawImageScales;
begin
  const Source = TPdfBitmap.Create(2, 2);
  try
    Source.SetPixel(0, 0, TPdfDeviceColor.Create(255, 0, 0));
    Source.SetPixel(1, 0, TPdfDeviceColor.Create(0, 255, 0));
    Source.SetPixel(0, 1, TPdfDeviceColor.Create(0, 0, 255));
    Source.SetPixel(1, 1, TPdfDeviceColor.Create(0, 0, 0));

    const Target = WhiteBitmap(4);
    try
      const Painter = TPdfVclPainter.Create(Target.Canvas);
      const Reference: IInterface = Painter;
      const Image = TPdfVclImage.Create(Source);
      const ImageReference: IInterface = Image;
      Painter.DrawImage(Image, Rect(0, 0, 2, 2), TRectF.Create(0, 0, 4, 4));

      const Red = PixelAt(Target, 0, 0);
      const Green = PixelAt(Target, 3, 0);
      const Blue = PixelAt(Target, 0, 3);
      const Black = PixelAt(Target, 3, 3);
      Assert.IsTrue((Red.R > 255 - RoughTolerance) and (Red.G < RoughTolerance) and (Red.B < RoughTolerance), 'upper left is red');
      Assert.IsTrue((Green.G > 255 - RoughTolerance) and (Green.R < RoughTolerance) and (Green.B < RoughTolerance), 'upper right is green');
      Assert.IsTrue((Blue.B > 255 - RoughTolerance) and (Blue.R < RoughTolerance) and (Blue.G < RoughTolerance), 'lower left is blue');
      Assert.IsTrue((Black.R < RoughTolerance) and (Black.G < RoughTolerance) and (Black.B < RoughTolerance), 'lower right is black');
      Assert.IsNotNull(Reference);
      Assert.IsNotNull(ImageReference);
    finally
      Target.Free;
    end;
  finally
    Source.Free;
  end;
end;

end.
