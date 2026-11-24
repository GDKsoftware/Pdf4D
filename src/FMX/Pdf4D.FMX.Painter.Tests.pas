// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.FMX.Painter.Tests;

{$EXCESSPRECISION OFF}
{$POINTERMATH ON}

interface

uses
  System.Types,
  System.SysUtils,
  System.UITypes,
  FMX.Graphics,
  DUnitX.TestFramework,
  Pdf4D.Viewer.Painter.Interfaces;

type
  [TestFixture]
  TPdfFmxPainterTests = class
  private
    // A white bitmap of LogicalSize logical units on the given scale, on which Draw has painted; the caller owns it
    class function PaintOnBitmap(const LogicalSize: Integer; const Scale: Single; const Draw: TProc<IPdfViewPainter>): FMX.Graphics.TBitmap; static;
    class function PixelAt(const Bitmap: FMX.Graphics.TBitmap; const X, Y: Integer): TAlphaColor; static;
    class function IsDark(const Bitmap: FMX.Graphics.TBitmap; const X, Y: Integer): Boolean; static;

  public
    [Test]
    procedure TestImageColorsAreExact;
    [Test]
    procedure TestImageHandlesRgbaPixelFormat;
    [Test]
    procedure TestImageHandlesBgraPixelFormat;
    [Test]
    procedure TestImageRejectsOtherPixelFormats;
    [Test]
    procedure TestPainterMapsDevicePixels;
    [Test]
    procedure TestDrawImageSameSizeIsPixelExactAtScale;
    [Test]
    procedure TestDrawImageScales;
    [Test]
    procedure TestFillPolygonWithAlpha;
    [Test]
    procedure TestFrameEllipse;
    [Test]
    procedure TestDrawTextIsCentred;
    [Test]
    procedure TestScaleMustBePositive;
  end;

implementation

uses
  System.Math,
  FMX.Types,
  Pdf4D.Render.Bitmap,
  Pdf4D.FMX.Painter;

const
  ColorTolerance = 2;
  RoughTolerance = 60;
  DarkLimit = 128;
  FontSize = 20;

{ TPdfFmxPainterTests }

class function TPdfFmxPainterTests.PaintOnBitmap(const LogicalSize: Integer; const Scale: Single;
                                                 const Draw: TProc<IPdfViewPainter>): FMX.Graphics.TBitmap;
begin
  const Pixels = Round(LogicalSize * Scale);
  Result := FMX.Graphics.TBitmap.Create(Pixels, Pixels);
  try
    Result.BitmapScale := Scale;

    const Font = TFont.Create;
    try
      Font.Size := FontSize / Scale;
      const Canvas = Result.Canvas;
      Assert.IsTrue(Canvas.BeginScene, 'the canvas of the bitmap accepts a scene');
      try
        Canvas.Clear(TAlphaColors.White);
        const Painter: IPdfViewPainter = TPdfFmxPainter.Create(Canvas, Scale, Font);
        Draw(Painter);
      finally
        Canvas.EndScene;
      end;
    finally
      Font.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

class function TPdfFmxPainterTests.PixelAt(const Bitmap: FMX.Graphics.TBitmap; const X, Y: Integer): TAlphaColor;
begin
  var Data: TBitmapData;
  Assert.IsTrue(Bitmap.Map(TMapAccess.Read, Data), 'the bitmap can be read');
  try
    Result := Data.GetPixel(X, Y);
  finally
    Bitmap.Unmap(Data);
  end;
end;

class function TPdfFmxPainterTests.IsDark(const Bitmap: FMX.Graphics.TBitmap; const X, Y: Integer): Boolean;
begin
  Result := TAlphaColorRec(PixelAt(Bitmap, X, Y)).R < DarkLimit;
end;

procedure TPdfFmxPainterTests.TestImageColorsAreExact;
begin
  const Source = TPdfBitmap.Create(2, 1);
  try
    // Premultiplied values, as the renderer stores them
    Source.SetPixel(0, 0, TPdfDeviceColor.Create(10, 20, 30, 255));
    Source.SetPixel(1, 0, TPdfDeviceColor.Create(64, 0, 0, 128));

    const Image = TPdfFmxImage.Create(Source);
    const Reference: IInterface = Image;
    Assert.AreEqual(2, Image.Width);
    Assert.AreEqual(1, Image.Height);

    var Data: TBitmapData;
    Assert.IsTrue(Image.Bitmap.Map(TMapAccess.Read, Data));
    try
      // GetPixel reads the stored values in the pixel format of the bitmap, without a conversion of the alpha
      Assert.AreEqual(Cardinal($FF0A141E), Cardinal(Data.GetPixel(0, 0)), 'opaque');
      Assert.AreEqual(Cardinal($80400000), Cardinal(Data.GetPixel(1, 0)), 'translucent, still premultiplied');
    finally
      Image.Bitmap.Unmap(Data);
    end;
    Assert.IsNotNull(Reference);
  finally
    Source.Free;
  end;
end;

procedure TPdfFmxPainterTests.TestImageHandlesRgbaPixelFormat;
begin
  const Source = TPdfBitmap.Create(2, 1);
  try
    Source.SetPixel(0, 0, TPdfDeviceColor.Create(10, 20, 30, 255));
    Source.SetPixel(1, 0, TPdfDeviceColor.Create(64, 0, 0, 128));

    var Target := TBitmapData.Create(2, 1, TPixelFormat.RGBA);
    var Memory: array[0..7] of Byte;
    Target.Data := @Memory[0];
    Target.Pitch := 8;
    TPdfFmxImage.CopyPixels(Source, Target);

    Assert.AreEqual(10, Integer(Memory[0]), 'red');
    Assert.AreEqual(20, Integer(Memory[1]), 'green');
    Assert.AreEqual(30, Integer(Memory[2]), 'blue');
    Assert.AreEqual(255, Integer(Memory[3]), 'alpha');
    Assert.AreEqual(64, Integer(Memory[4]), 'red of the translucent pixel');
    Assert.AreEqual(128, Integer(Memory[7]), 'alpha of the translucent pixel');
    Assert.AreEqual(Cardinal($FF0A141E), Cardinal(Target.GetPixel(0, 0)), 'no swap of channels');
    Assert.AreEqual(Cardinal($80400000), Cardinal(Target.GetPixel(1, 0)));
  finally
    Source.Free;
  end;
end;

procedure TPdfFmxPainterTests.TestImageHandlesBgraPixelFormat;
begin
  const Source = TPdfBitmap.Create(1, 1);
  try
    Source.SetPixel(0, 0, TPdfDeviceColor.Create(10, 20, 30, 255));

    var Target := TBitmapData.Create(1, 1, TPixelFormat.BGRA);
    var Memory: array[0..3] of Byte;
    Target.Data := @Memory[0];
    Target.Pitch := 4;
    TPdfFmxImage.CopyPixels(Source, Target);

    Assert.AreEqual(30, Integer(Memory[0]), 'blue');
    Assert.AreEqual(20, Integer(Memory[1]), 'green');
    Assert.AreEqual(10, Integer(Memory[2]), 'red');
    Assert.AreEqual(255, Integer(Memory[3]), 'alpha');
    Assert.AreEqual(Cardinal($FF0A141E), Cardinal(Target.GetPixel(0, 0)));
  finally
    Source.Free;
  end;
end;

procedure TPdfFmxPainterTests.TestImageRejectsOtherPixelFormats;
begin
  const Source = TPdfBitmap.Create(1, 1);
  try
    var Target := TBitmapData.Create(1, 1, TPixelFormat.L);
    var Memory: array[0..3] of Byte;
    Target.Data := @Memory[0];
    Target.Pitch := 1;

    Assert.WillRaise(
      procedure
      begin
        TPdfFmxImage.CopyPixels(Source, Target);
      end,
      ENotSupportedException);

    var Small := TBitmapData.Create(1, 1, TPixelFormat.RGBA);
    Small.Data := @Memory[0];
    Small.Pitch := 4;
    const Larger = TPdfBitmap.Create(2, 2);
    try
      Assert.WillRaise(
        procedure
        begin
          TPdfFmxImage.CopyPixels(Larger, Small);
        end,
        EArgumentException);
    finally
      Larger.Free;
    end;
  finally
    Source.Free;
  end;
end;

// Device pixels in, logical units out: on a scale of 1.5 a rectangle of 30 device pixels is 20 logical units, and it must still cover
// the device pixels 0 to 29 and not pixel 30
procedure TPdfFmxPainterTests.TestPainterMapsDevicePixels;
begin
  const Target = PaintOnBitmap(40, 1.5,
    procedure(Painter: IPdfViewPainter)
    begin
      Painter.FillRect(TRectF.Create(0, 0, 30, 30), TAlphaColors.Black);
    end);
  try
    Assert.AreEqual(60, Target.Width, 'the bitmap is in device pixels');
    Assert.IsTrue(IsDark(Target, 0, 0), 'first pixel');
    Assert.IsTrue(IsDark(Target, 29, 29), 'last pixel');
    Assert.IsTrue(IsDark(Target, 29, 0));
    Assert.IsFalse(IsDark(Target, 30, 5), 'one pixel to the right is empty');
    Assert.IsFalse(IsDark(Target, 5, 30), 'one pixel below is empty');
    Assert.IsFalse(IsDark(Target, 30, 30));
    Assert.AreEqual(Cardinal(TAlphaColors.Black), Cardinal(PixelAt(Target, 15, 15)), 'solid inside, no edge blending');
    Assert.AreEqual(Cardinal(TAlphaColors.White), Cardinal(PixelAt(Target, 45, 45)));
  finally
    Target.Free;
  end;
end;

// Two tiles that touch in device pixels must not leave a seam on a scale that is not 1, and a picture that is not scaled is copied pixel
// for pixel
procedure TPdfFmxPainterTests.TestDrawImageSameSizeIsPixelExactAtScale;
begin
  const Source = TPdfBitmap.Create(3, 3);
  try
    Source.SetPixel(0, 0, TPdfDeviceColor.Create(255, 0, 0));
    Source.SetPixel(1, 1, TPdfDeviceColor.Create(0, 255, 0));
    Source.SetPixel(2, 2, TPdfDeviceColor.Create(0, 0, 255));
    const Image = TPdfFmxImage.Create(Source);
    const Reference: IInterface = Image;

    const Target = PaintOnBitmap(40, 1.5,
      procedure(Painter: IPdfViewPainter)
      begin
        Painter.DrawImage(Image, Rect(0, 0, 3, 3), TRectF.Create(7, 7, 10, 10));
      end);
    try
      Assert.AreEqual(Cardinal(TAlphaColors.Red), Cardinal(PixelAt(Target, 7, 7)));
      Assert.AreEqual(Cardinal(TAlphaColors.Lime), Cardinal(PixelAt(Target, 8, 8)));
      Assert.AreEqual(Cardinal(TAlphaColors.Blue), Cardinal(PixelAt(Target, 9, 9)));
      Assert.AreEqual(Cardinal(TAlphaColors.White), Cardinal(PixelAt(Target, 6, 6)), 'before the picture');
      Assert.AreEqual(Cardinal(TAlphaColors.White), Cardinal(PixelAt(Target, 10, 10)), 'after the picture');
      Assert.AreEqual(Cardinal(TAlphaColors.White), Cardinal(PixelAt(Target, 8, 7)), 'a pixel of the picture that is white');
    finally
      Target.Free;
    end;
    Assert.IsNotNull(Reference);
  finally
    Source.Free;
  end;
end;

procedure TPdfFmxPainterTests.TestDrawImageScales;
begin
  const Source = TPdfBitmap.Create(2, 2);
  try
    Source.SetPixel(0, 0, TPdfDeviceColor.Create(255, 0, 0));
    Source.SetPixel(1, 0, TPdfDeviceColor.Create(0, 255, 0));
    Source.SetPixel(0, 1, TPdfDeviceColor.Create(0, 0, 255));
    Source.SetPixel(1, 1, TPdfDeviceColor.Create(0, 0, 0));
    const Image = TPdfFmxImage.Create(Source);
    const Reference: IInterface = Image;

    const Target = PaintOnBitmap(4, 1,
      procedure(Painter: IPdfViewPainter)
      begin
        Painter.DrawImage(Image, Rect(0, 0, 2, 2), TRectF.Create(0, 0, 4, 4));
      end);
    try
      const Red = TAlphaColorRec(PixelAt(Target, 0, 0));
      const Green = TAlphaColorRec(PixelAt(Target, 3, 0));
      const Blue = TAlphaColorRec(PixelAt(Target, 0, 3));
      const Black = TAlphaColorRec(PixelAt(Target, 3, 3));
      Assert.IsTrue((Red.R > 255 - RoughTolerance) and (Red.G < RoughTolerance) and (Red.B < RoughTolerance), 'upper left is red');
      Assert.IsTrue((Green.G > 255 - RoughTolerance) and (Green.R < RoughTolerance) and (Green.B < RoughTolerance), 'upper right is green');
      Assert.IsTrue((Blue.B > 255 - RoughTolerance) and (Blue.R < RoughTolerance) and (Blue.G < RoughTolerance), 'lower left is blue');
      Assert.IsTrue((Black.R < RoughTolerance) and (Black.G < RoughTolerance) and (Black.B < RoughTolerance), 'lower right is black');
    finally
      Target.Free;
    end;
    Assert.IsNotNull(Reference);
  finally
    Source.Free;
  end;
end;

procedure TPdfFmxPainterTests.TestFillPolygonWithAlpha;
begin
  const Target = PaintOnBitmap(20, 1.5,
    procedure(Painter: IPdfViewPainter)
    begin
      Painter.FillPolygon([TPointF.Create(-5, -5), TPointF.Create(45, -5), TPointF.Create(45, 45), TPointF.Create(-5, 45)], $80FF0000);
    end);
  try
    const Pixel = TAlphaColorRec(PixelAt(Target, 15, 15));
    Assert.AreEqual(Double(255), Double(Pixel.R), ColorTolerance, 'red');
    Assert.AreEqual(Double(127), Double(Pixel.G), ColorTolerance + 1, 'green');
    Assert.AreEqual(Double(127), Double(Pixel.B), ColorTolerance + 1, 'blue');
  finally
    Target.Free;
  end;
end;

procedure TPdfFmxPainterTests.TestFrameEllipse;
begin
  const Target = PaintOnBitmap(40, 1.5,
    procedure(Painter: IPdfViewPainter)
    begin
      Painter.FrameEllipse(TRectF.Create(8, 8, 52, 52), TAlphaColors.Black, 3);
    end);
  try
    var HasGray := False;
    var HasDark := False;
    for var Y := 0 to Target.Height - 1 do
    begin
      for var X := 0 to Target.Width - 1 do
      begin
        const Red = TAlphaColorRec(PixelAt(Target, X, Y)).R;
        HasGray := HasGray or ((Red > 20) and (Red < 235));
        HasDark := HasDark or (Red < 20);
      end;
    end;

    Assert.IsTrue(HasDark, 'the frame is drawn');
    Assert.IsTrue(HasGray, 'the edge has partly covered pixels');
    Assert.AreEqual(255, Integer(TAlphaColorRec(PixelAt(Target, 30, 30)).R), 'the inside stays empty');
    Assert.AreEqual(255, Integer(TAlphaColorRec(PixelAt(Target, 1, 1)).R), 'the corner stays empty');
  finally
    Target.Free;
  end;
end;

procedure TPdfFmxPainterTests.TestDrawTextIsCentred;
begin
  const Area = TRectF.Create(15, 15, 105, 75);
  const Target = PaintOnBitmap(80, 1.5,
    procedure(Painter: IPdfViewPainter)
    begin
      Painter.DrawText('HIH', Area, TAlphaColors.Black);
    end);
  try
    var Left := Target.Width;
    var Top := Target.Height;
    var Right := -1;
    var Bottom := -1;
    for var Y := 0 to Target.Height - 1 do
    begin
      for var X := 0 to Target.Width - 1 do
      begin
        if IsDark(Target, X, Y) then
        begin
          Left := Min(Left, X);
          Right := Max(Right, X);
          Top := Min(Top, Y);
          Bottom := Max(Bottom, Y);
        end;
      end;
    end;

    Assert.IsTrue(Right >= 0, 'the text is drawn');
    Assert.IsTrue((Left >= Area.Left) and (Right < Area.Right) and (Top >= Area.Top) and (Bottom < Area.Bottom), 'inside the rectangle');
    const CentreX = (Left + Right) / 2;
    const CentreY = (Top + Bottom) / 2;
    Assert.AreEqual(Double(Area.CenterPoint.X), Double(CentreX), 3, 'centred horizontally');
    Assert.AreEqual(Double(Area.CenterPoint.Y), Double(CentreY), 6, 'centred vertically');
  finally
    Target.Free;
  end;
end;

procedure TPdfFmxPainterTests.TestScaleMustBePositive;
begin
  const Target = FMX.Graphics.TBitmap.Create(4, 4);
  try
    Assert.WillRaise(
      procedure
      begin
        const Painter: IPdfViewPainter = TPdfFmxPainter.Create(Target.Canvas, 0, nil);
        Assert.IsNotNull(Painter);
      end,
      EArgumentOutOfRangeException);
  finally
    Target.Free;
  end;
end;

end.
