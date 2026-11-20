// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of the image part of PageDrawer (PDFBox 3.0.8): drawImage and drawBufferedImage for image XObjects, stencil masks and inline
// images, through the recording device
unit Pdf4D.Render.PageDrawer.Images.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Render.Renderer.Interfaces,
  Pdf4D.Tests.GraphicsDocuments,
  Pdf4D.Tests.PdfBuilder,
  Pdf4D.Tests.RecordingDevice;

type
  [TestFixture]
  TPageDrawerImageTests = class
  private
    const Tolerance: Single = 0.01;
    const ImageResources = '/XObject << /Im1 5 0 R >> /ExtGState << /GS1 << /ca 0.5 >> >>';
    const GrayEntries = '/Width %d /Height %d /ColorSpace /DeviceGray /BitsPerComponent 8';

  private
    FDocuments: TGraphicsDocuments;
    FDocument: IPdfDocument;
    FRenderer: IPdfRenderer;
    FDevice: TRecordingDevice;
    FDeviceReference: IPdfRasterDevice;

    procedure RenderBytes(const Content: TBytes; const Resources, ImageEntries: string; const ImageData: TBytes);
    // The image is object 5 of the document, resource /Im1
    procedure RenderImage(const Content, ImageEntries: string; const ImageData: TBytes);
    function BitmapCalls: TArray<TRecordedCall>;
    function CountLogLines(const Fragment: string): Integer;
    function Gray(const Width, Height: Integer): TBytes;
    procedure AssertPixel(const Call: TRecordedCall; const X, Y: Integer; const R, G, B, A: Byte);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestImageDrawnWithCtm;

    [Test]
    procedure TestUpscaledImageWithoutInterpolateUsesNearest;

    [Test]
    procedure TestDownscaledImageUsesBicubic;

    [Test]
    procedure TestUpscaledImageWithInterpolateUsesBicubic;

    [Test]
    procedure TestStencilMaskUsesFillColor;

    [Test]
    procedure TestInlineImage;

    [Test]
    procedure TestInlineImageWithAbbreviatedColorSpaceAndFilter;

    [Test]
    procedure TestInlineStencilWithDecode;

    [Test]
    procedure TestImageUsesNonStrokingAlpha;

    [Test]
    procedure TestBrokenImageIsSkippedWithLog;

    [Test]
    procedure TestImageIsClippedLikeOtherPaint;

    [Test]
    procedure TestRotatedImageCtm;
  end;

implementation

uses
  Pdf4D.Common.Matrix,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Renderer;

{ TPageDrawerImageTests }

procedure TPageDrawerImageTests.Setup;
begin
  FDocuments := TGraphicsDocuments.Create;
  FDevice := TRecordingDevice.Create(TGraphicsDocuments.PageSize, TGraphicsDocuments.PageSize);
  FDeviceReference := FDevice;
end;

procedure TPageDrawerImageTests.TearDown;
begin
  FDeviceReference := nil;
  FRenderer := nil;
  FDocument := nil;
  FreeAndNil(FDocuments);
end;

procedure TPageDrawerImageTests.RenderBytes(const Content: TBytes; const Resources, ImageEntries: string; const ImageData: TBytes);
begin
  const Builder = TGraphicsDocuments.NewBuilder(Content, Resources);
  try
    if ImageEntries <> '' then
    begin
      Builder.AddStreamObject(5, '/Type /XObject /Subtype /Image ' + ImageEntries, ImageData);
    end;
    FDocument := FDocuments.Open(Builder);
  finally
    Builder.Free;
  end;
  FRenderer := TPdfRenderer.Create(FDocument, TRecordingBackend.Create);

  const Status = FRenderer.RenderPage(0, FDeviceReference, TPdfRenderParams.Create(1));

  Assert.AreEqual(TPdfRenderStatus.Completed, Status);
end;

procedure TPageDrawerImageTests.RenderImage(const Content, ImageEntries: string; const ImageData: TBytes);
begin
  RenderBytes(TEncoding.ASCII.GetBytes(Content), ImageResources, ImageEntries, ImageData);
end;

function TPageDrawerImageTests.BitmapCalls: TArray<TRecordedCall>;
begin
  const Found = TList<TRecordedCall>.Create;
  try
    for var Call in FDevice.Calls do
    begin
      if Call.Kind = TRecordedCallKind.Bitmap then
      begin
        Found.Add(Call);
      end;
    end;
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

function TPageDrawerImageTests.CountLogLines(const Fragment: string): Integer;
begin
  Result := 0;
  for var Line in FDocuments.LogLines do
  begin
    if Line.Contains(Fragment) then
    begin
      Inc(Result);
    end;
  end;
end;

function TPageDrawerImageTests.Gray(const Width, Height: Integer): TBytes;
begin
  SetLength(Result, Width * Height);
  for var Index := 0 to High(Result) do
  begin
    Result[Index] := Byte(Index * 7);
  end;
end;

procedure TPageDrawerImageTests.AssertPixel(const Call: TRecordedCall; const X, Y: Integer; const R, G, B, A: Byte);
begin
  const Offset = (Y * Call.BitmapWidth + X) * 4;
  Assert.AreEqual<Integer>(R, Call.BitmapPixels[Offset], Format('R of (%d, %d)', [X, Y]));
  Assert.AreEqual<Integer>(G, Call.BitmapPixels[Offset + 1], Format('G of (%d, %d)', [X, Y]));
  Assert.AreEqual<Integer>(B, Call.BitmapPixels[Offset + 2], Format('B of (%d, %d)', [X, Y]));
  Assert.AreEqual<Integer>(A, Call.BitmapPixels[Offset + 3], Format('A of (%d, %d)', [X, Y]));
end;

// The image is the unit square under the CTM: its top left corner is (10, 60) in the page and (10, 200 - 60) on the device
procedure TPageDrawerImageTests.TestImageDrawnWithCtm;
begin
  RenderImage('100 0 0 50 10 10 cm /Im1 Do', Format(GrayEntries, [4, 2]), Gray(4, 2));

  const Calls = BitmapCalls;
  Assert.AreEqual<Integer>(1, Length(Calls));
  const Call = Calls[0];
  Assert.AreEqual(4, Call.BitmapWidth);
  Assert.AreEqual(2, Call.BitmapHeight);
  const TopLeft = Call.Paint.BitmapToDevice.TransformPoint(0, 0);
  const BottomRight = Call.Paint.BitmapToDevice.TransformPoint(4, 2);
  Assert.AreEqual(Double(10), Double(TopLeft.X), Double(Tolerance));
  Assert.AreEqual(Double(140), Double(TopLeft.Y), Double(Tolerance));
  Assert.AreEqual(Double(110), Double(BottomRight.X), Double(Tolerance));
  Assert.AreEqual(Double(190), Double(BottomRight.Y), Double(Tolerance));
  Assert.AreEqual(Double(10), Double(Call.DeviceBounds.Left), Double(Tolerance));
  Assert.AreEqual(Double(190), Double(Call.DeviceBounds.Bottom), Double(Tolerance));
  AssertPixel(Call, 1, 0, 7, 7, 7, 255);
end;

procedure TPageDrawerImageTests.TestUpscaledImageWithoutInterpolateUsesNearest;
begin
  RenderImage('100 0 0 50 10 10 cm /Im1 Do', Format(GrayEntries, [4, 2]), Gray(4, 2));

  Assert.AreEqual(TPdfImageFilter.Nearest, BitmapCalls[0].Paint.Filter);
end;

procedure TPageDrawerImageTests.TestDownscaledImageUsesBicubic;
begin
  RenderImage('20 0 0 20 10 10 cm /Im1 Do', Format(GrayEntries, [64, 64]), Gray(64, 64));

  Assert.AreEqual(TPdfImageFilter.Bicubic, BitmapCalls[0].Paint.Filter);
end;

procedure TPageDrawerImageTests.TestUpscaledImageWithInterpolateUsesBicubic;
begin
  RenderImage('100 0 0 50 10 10 cm /Im1 Do', Format(GrayEntries, [4, 2]) + ' /Interpolate true', Gray(4, 2));

  Assert.AreEqual(TPdfImageFilter.Bicubic, BitmapCalls[0].Paint.Filter);
end;

// 11110000: with the default /Decode a sample of 0 paints, so the right half is red and the left half stays clear
procedure TPageDrawerImageTests.TestStencilMaskUsesFillColor;
begin
  RenderImage('1 0 0 rg 80 0 0 10 10 10 cm /Im1 Do', '/Width 8 /Height 1 /ImageMask true', [$F0]);

  const Calls = BitmapCalls;
  Assert.AreEqual<Integer>(1, Length(Calls));
  AssertPixel(Calls[0], 0, 0, 0, 0, 0, 0);
  AssertPixel(Calls[0], 3, 0, 0, 0, 0, 0);
  AssertPixel(Calls[0], 4, 0, 255, 0, 0, 255);
  AssertPixel(Calls[0], 7, 0, 255, 0, 0, 255);
end;

procedure TPageDrawerImageTests.TestInlineImage;
begin
  var Content := TEncoding.ASCII.GetBytes('q 40 0 0 40 20 20 cm BI /W 2 /H 2 /BPC 8 /CS /G ID ');
  Content := Content + [10, 20, 30, 40] + TEncoding.ASCII.GetBytes(' EI Q');
  RenderBytes(Content, ImageResources, '', nil);

  const Calls = BitmapCalls;
  Assert.AreEqual<Integer>(1, Length(Calls));
  Assert.AreEqual(2, Calls[0].BitmapWidth);
  Assert.AreEqual(2, Calls[0].BitmapHeight);
  AssertPixel(Calls[0], 0, 0, 10, 10, 10, 255);
  AssertPixel(Calls[0], 1, 1, 40, 40, 40, 255);
  Assert.AreEqual(Double(20), Double(Calls[0].Paint.BitmapToDevice.TransformPoint(0, 0).X), Double(Tolerance));
  Assert.AreEqual(Double(140), Double(Calls[0].Paint.BitmapToDevice.TransformPoint(0, 0).Y), Double(Tolerance));
end;

procedure TPageDrawerImageTests.TestInlineImageWithAbbreviatedColorSpaceAndFilter;
begin
  RenderBytes(TEncoding.ASCII.GetBytes('q 40 0 0 40 20 20 cm BI /W 2 /H 1 /BPC 8 /CS /RGB /F /AHx ID FF0000 0000FF > EI Q'), ImageResources, '', nil);

  const Calls = BitmapCalls;
  Assert.AreEqual<Integer>(1, Length(Calls));
  AssertPixel(Calls[0], 0, 0, 255, 0, 0, 255);
  AssertPixel(Calls[0], 1, 0, 0, 0, 255, 255);
end;

procedure TPageDrawerImageTests.TestInlineStencilWithDecode;
begin
  var Content := TEncoding.ASCII.GetBytes('0 0 1 rg q 80 0 0 10 20 20 cm BI /W 8 /H 1 /IM true /BPC 1 /D [1 0] ID ');
  Content := Content + [$F0] + TEncoding.ASCII.GetBytes(' EI Q');
  RenderBytes(Content, ImageResources, '', nil);

  const Calls = BitmapCalls;
  Assert.AreEqual<Integer>(1, Length(Calls));
  // /D [1 0]: a sample of 1 paints
  AssertPixel(Calls[0], 0, 0, 0, 0, 255, 255);
  AssertPixel(Calls[0], 7, 0, 0, 0, 0, 0);
end;

procedure TPageDrawerImageTests.TestImageUsesNonStrokingAlpha;
begin
  RenderImage('/GS1 gs 100 0 0 50 10 10 cm /Im1 Do', Format(GrayEntries, [2, 2]), Gray(2, 2));

  const Calls = BitmapCalls;
  Assert.AreEqual<Integer>(1, Length(Calls));
  Assert.AreEqual(Double(0.5), Double(Calls[0].Composite.Alpha), Double(Tolerance));
end;

procedure TPageDrawerImageTests.TestBrokenImageIsSkippedWithLog;
begin
  RenderImage('100 0 0 50 10 10 cm /Im1 Do', '/Width 0 /Height 4 /ColorSpace /DeviceGray /BitsPerComponent 8', [1, 2, 3, 4]);

  Assert.AreEqual<Integer>(0, Length(BitmapCalls));
  Assert.AreEqual(1, CountLogLines('Image skipped'));
end;

procedure TPageDrawerImageTests.TestImageIsClippedLikeOtherPaint;
begin
  RenderImage('20 20 30 30 re W n 100 0 0 50 10 10 cm /Im1 Do', Format(GrayEntries, [2, 2]), Gray(2, 2));

  const Calls = BitmapCalls;
  Assert.AreEqual<Integer>(1, Length(Calls));
  // The page clip and the rectangle
  Assert.AreEqual(2, Calls[0].ClipDepth);
end;

// A quarter turn: the left edge of the bitmap becomes the bottom edge in the page
procedure TPageDrawerImageTests.TestRotatedImageCtm;
begin
  RenderImage('0 50 -50 0 100 10 cm /Im1 Do', Format(GrayEntries, [2, 2]), Gray(2, 2));

  const Calls = BitmapCalls;
  Assert.AreEqual<Integer>(1, Length(Calls));
  // The top left pixel corner (0, 0) is the unit point (0, 1): (100 - 50, 10 + 0) in the page, y flipped on the device
  const Corner = Calls[0].Paint.BitmapToDevice.TransformPoint(0, 0);
  Assert.AreEqual(Double(50), Double(Corner.X), Double(Tolerance));
  Assert.AreEqual(Double(190), Double(Corner.Y), Double(Tolerance));
end;

end.
