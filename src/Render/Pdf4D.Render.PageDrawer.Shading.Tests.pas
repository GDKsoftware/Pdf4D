// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of the shadings in PageDrawer (PDFBox 3.0.8): shadingFill, the shading patterns of getPaint and intersectShadingBBox, through the
// recording device
unit Pdf4D.Render.PageDrawer.Shading.Tests;

{$EXCESSPRECISION OFF}

interface

uses
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
  TPageDrawerShadingTests = class
  private
    const Tolerance = 0.0001;
    const Axial = '/ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 100 0] /Function << /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >>';
    const FormObject = 5;
    const Resources =
      '/Shading << /Sh1 << %0:s >> /Sh2 << %0:s /BBox [0 0 50 50] >> >> ' +
      '/Pattern << /P1 << /PatternType 2 /Shading << %0:s >> >> ' +
      '/P2 << /PatternType 2 /Shading << %0:s /BBox [10 10 40 40] >> >> ' +
      '/P3 << /PatternType 2 /Shading << %0:s >> /Matrix [1 0 0 1 20 0] >> ' +
      '/PTiling << /PatternType 1 >> >> ' +
      '/XObject << /Fm1 5 0 R >> /ExtGState << /GsHalf << /ca 0.5 >> >>';

  private
    FDocuments: TGraphicsDocuments;
    FDocument: IPdfDocument;
    FRenderer: IPdfRenderer;
    FDevice: TRecordingDevice;
    FDeviceReference: IPdfRasterDevice;

    procedure Render(const Content: string);
    procedure RenderWithForm(const Content, FormContent: string);
    function PageResources: string;
    function CallsOfKind(const Kind: TRecordedCallKind): TArray<TRecordedCall>;
    function CountLogLines(const Fragment: string): Integer;
    class function PixelOf(const Call: TRecordedCall; const X, Y: Integer): TArray<Byte>; static;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestShFillsClipArea;

    [Test]
    procedure TestShadingPatternAsFillColor;

    [Test]
    procedure TestShadingBBoxIntersectsClip;

    [Test]
    procedure TestShadingPatternBBoxIsOneMoreLinkOfTheClip;

    [Test]
    procedure TestShadingPatternWithoutNamePaintsNothing;

    [Test]
    procedure TestMissingShadingIsLogged;

    [Test]
    procedure TestMissingPatternPaintsNothing;

    [Test]
    procedure TestShUsesTheNonStrokingAlpha;

    [Test]
    procedure TestShadingPatternAsStrokeColor;

    [Test]
    procedure TestPatternMatrixPlacesTheShading;

    [Test]
    procedure TestPatternMatrixFollowsTheMatrixOfTheForm;

    [Test]
    procedure TestTilingPatternIsLoggedOnceAndPaintsNothing;

    [Test]
    procedure TestShadingIsMadeOnceForManyFills;
  end;

implementation

uses
  Pdf4D.Common.Matrix,
  Pdf4D.Render.Renderer;

{ TPageDrawerShadingTests }

procedure TPageDrawerShadingTests.Setup;
begin
  FDocuments := TGraphicsDocuments.Create;
  FDevice := TRecordingDevice.Create(TGraphicsDocuments.PageSize, TGraphicsDocuments.PageSize);
  FDeviceReference := FDevice;
end;

procedure TPageDrawerShadingTests.TearDown;
begin
  FDeviceReference := nil;
  FRenderer := nil;
  FDocument := nil;
  FreeAndNil(FDocuments);
end;

function TPageDrawerShadingTests.PageResources: string;
begin
  Result := Format(Resources, [Axial]);
end;

procedure TPageDrawerShadingTests.Render(const Content: string);
begin
  FDocument := FDocuments.Open(Content, PageResources);
  FRenderer := TPdfRenderer.Create(FDocument, TRecordingBackend.Create);

  const Status = FRenderer.RenderPage(0, FDeviceReference, TPdfRenderParams.Create(1));

  Assert.AreEqual(TPdfRenderStatus.Completed, Status);
end;

// The form /Fm1 (object 5) moves its content 50 points to the right and has the pattern /P4 of its own
procedure TPageDrawerShadingTests.RenderWithForm(const Content, FormContent: string);
begin
  const Builder = TGraphicsDocuments.NewBuilder(TEncoding.ASCII.GetBytes(Content), PageResources);
  try
    const FormEntries = '/Type /XObject /Subtype /Form /BBox [0 0 200 200] /Matrix [1 0 0 1 50 0] ' +
      '/Resources << /Pattern << /P4 << /PatternType 2 /Shading << /ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 40 0] ' +
      '/Function << /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >> >> >> >> >>';
    Builder.AddStreamObject(FormObject, FormEntries, TEncoding.ASCII.GetBytes(FormContent));

    FDocument := FDocuments.Open(Builder);
    FRenderer := TPdfRenderer.Create(FDocument, TRecordingBackend.Create);
    const Status = FRenderer.RenderPage(0, FDeviceReference, TPdfRenderParams.Create(1));
    Assert.AreEqual(TPdfRenderStatus.Completed, Status);
  finally
    Builder.Free;
  end;
end;

function TPageDrawerShadingTests.CallsOfKind(const Kind: TRecordedCallKind): TArray<TRecordedCall>;
begin
  const Found = TList<TRecordedCall>.Create;
  try
    for var Call in FDevice.Calls do
    begin
      if Call.Kind = Kind then
      begin
        Found.Add(Call);
      end;
    end;
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

function TPageDrawerShadingTests.CountLogLines(const Fragment: string): Integer;
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

// The four bytes of the pixel (X, Y) of the bitmap of a call: red, green, blue and alpha, premultiplied
class function TPageDrawerShadingTests.PixelOf(const Call: TRecordedCall; const X, Y: Integer): TArray<Byte>;
begin
  const Start = (Y * Call.BitmapWidth + X) * 4;
  Result := Copy(Call.BitmapPixels, Start, 4);
end;

procedure TPageDrawerShadingTests.TestShFillsClipArea;
begin
  Render('0 0 10 10 re W n /Sh1 sh');

  const Fills = CallsOfKind(TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(1, Length(Fills));
  Assert.AreEqual(TPdfPaintKind.Bitmap, Fills[0].Paint.Kind);
  Assert.AreEqual(TPdfTileMode.Decal, Fills[0].Paint.TileMode);
  Assert.AreEqual(Double(0), Double(Fills[0].DeviceBounds.Left), Tolerance);
  Assert.AreEqual(Double(190), Double(Fills[0].DeviceBounds.Top), Tolerance);
  Assert.AreEqual(Double(10), Double(Fills[0].DeviceBounds.Right), Tolerance);
  Assert.AreEqual(Double(200), Double(Fills[0].DeviceBounds.Bottom), Tolerance);
  Assert.AreEqual<Integer>(10, Fills[0].BitmapWidth);
  Assert.AreEqual<Integer>(10, Fills[0].BitmapHeight);
  Assert.AreEqual(Double(190), Double(Fills[0].Paint.BitmapToDevice.TranslateY), Tolerance);
end;

procedure TPageDrawerShadingTests.TestShadingPatternAsFillColor;
begin
  Render('/Pattern cs /P1 scn 0 0 50 50 re f');

  const Fills = CallsOfKind(TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(1, Length(Fills));
  Assert.AreEqual(TPdfPaintKind.Bitmap, Fills[0].Paint.Kind);
  Assert.AreEqual(TPdfTileMode.Decal, Fills[0].Paint.TileMode);
  Assert.AreEqual<Integer>(50, Fills[0].BitmapWidth);
  Assert.AreEqual<Integer>(50, Fills[0].BitmapHeight);
  Assert.AreEqual<Integer>(1, Fills[0].ClipDepth, 'a pattern without BBox adds no clip');
  const FirstPixel = PixelOf(Fills[0], 0, 0);
  Assert.AreEqual<Integer>(255, FirstPixel[0]);
  Assert.AreEqual<Integer>(255, FirstPixel[3]);
end;

procedure TPageDrawerShadingTests.TestShadingBBoxIntersectsClip;
begin
  Render('20 20 100 100 re W n /Sh2 sh');

  const Fills = CallsOfKind(TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(1, Length(Fills));
  // The fill is the BBox (0, 0, 50, 50), the bitmap is the part of it that the clip leaves: x 20 to 50, y 150 to 180 of the device
  Assert.AreEqual(Double(0), Double(Fills[0].DeviceBounds.Left), Tolerance);
  Assert.AreEqual(Double(50), Double(Fills[0].DeviceBounds.Right), Tolerance);
  Assert.AreEqual<Integer>(30, Fills[0].BitmapWidth);
  Assert.AreEqual<Integer>(30, Fills[0].BitmapHeight);
  Assert.AreEqual(Double(20), Double(Fills[0].Paint.BitmapToDevice.TranslateX), Tolerance);
  Assert.AreEqual(Double(150), Double(Fills[0].Paint.BitmapToDevice.TranslateY), Tolerance);
end;

procedure TPageDrawerShadingTests.TestShadingPatternBBoxIsOneMoreLinkOfTheClip;
begin
  Render('/Pattern cs /P2 scn 0 0 50 50 re f');

  const Fills = CallsOfKind(TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(1, Length(Fills));
  Assert.AreEqual<Integer>(2, Fills[0].ClipDepth, 'the page clip and the BBox of the shading');
  Assert.AreEqual<Integer>(30, Fills[0].BitmapWidth);
  Assert.AreEqual<Integer>(30, Fills[0].BitmapHeight);
end;

// The Pattern space without a pattern: PDFBox fails to find the pattern and the operator paints nothing
procedure TPageDrawerShadingTests.TestShadingPatternWithoutNamePaintsNothing;
begin
  Render('/Pattern cs 0 0 50 50 re f');

  Assert.AreEqual<Integer>(0, Length(CallsOfKind(TRecordedCallKind.Fill)));
  Assert.AreEqual<Integer>(1, CountLogLines('was not found'));
end;

procedure TPageDrawerShadingTests.TestMissingShadingIsLogged;
begin
  Render('/Nope sh');

  Assert.AreEqual<Integer>(0, Length(CallsOfKind(TRecordedCallKind.Fill)));
  Assert.AreEqual<Integer>(1, CountLogLines('does not exist in resources dictionary'));
end;

procedure TPageDrawerShadingTests.TestMissingPatternPaintsNothing;
begin
  Render('/Pattern cs /Nope scn 0 0 50 50 re f');

  Assert.AreEqual<Integer>(0, Length(CallsOfKind(TRecordedCallKind.Fill)));
  Assert.AreEqual<Integer>(1, CountLogLines('was not found'));
end;

procedure TPageDrawerShadingTests.TestShUsesTheNonStrokingAlpha;
begin
  Render('/GsHalf gs 0 0 10 10 re W n /Sh1 sh');

  const Fills = CallsOfKind(TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(1, Length(Fills));
  Assert.AreEqual(Double(0.5), Double(Fills[0].Composite.Alpha), Tolerance);
end;

procedure TPageDrawerShadingTests.TestShadingPatternAsStrokeColor;
begin
  Render('/Pattern CS /P1 SCN 8 w 10 10 m 100 10 l S');

  const Strokes = CallsOfKind(TRecordedCallKind.Stroke);
  Assert.AreEqual<Integer>(1, Length(Strokes));
  Assert.AreEqual(TPdfPaintKind.Bitmap, Strokes[0].Paint.Kind);
  Assert.AreEqual(TPdfTileMode.Decal, Strokes[0].Paint.TileMode);
end;

// P3 has the matrix [1 0 0 1 20 0]: the axis of its shading starts at x = 20, so the bitmap, which starts at x = 0, is transparent
// for 20 pixels and has the start colour at pixel 20
procedure TPageDrawerShadingTests.TestPatternMatrixPlacesTheShading;
begin
  Render('/Pattern cs /P3 scn 0 0 100 50 re f');

  const Fills = CallsOfKind(TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(1, Length(Fills));
  Assert.AreEqual<Integer>(0, PixelOf(Fills[0], 5, 0)[3], 'before the start of the axis');
  const AtStart = PixelOf(Fills[0], 20, 0);
  Assert.AreEqual<Integer>(255, AtStart[0]);
  Assert.AreEqual<Integer>(255, AtStart[3]);
end;

// A pattern of a form is placed in the space of the form: the matrix of the form is part of the initial matrix
procedure TPageDrawerShadingTests.TestPatternMatrixFollowsTheMatrixOfTheForm;
begin
  RenderWithForm('/Fm1 Do', '/Pattern cs /P4 scn 0 0 40 40 re f');

  const Fills = CallsOfKind(TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(1, Length(Fills));
  Assert.AreEqual(Double(50), Double(Fills[0].DeviceBounds.Left), Tolerance);
  const AtStart = PixelOf(Fills[0], 0, 0);
  Assert.AreEqual<Integer>(255, AtStart[0]);
  Assert.AreEqual<Integer>(255, AtStart[3]);
end;

procedure TPageDrawerShadingTests.TestTilingPatternIsLoggedOnceAndPaintsNothing;
begin
  Render('/Pattern cs /PTiling scn 0 0 50 50 re f 60 0 50 50 re f');

  Assert.AreEqual<Integer>(0, Length(CallsOfKind(TRecordedCallKind.Fill)));
  Assert.AreEqual<Integer>(1, CountLogLines('is skipped'));
end;

procedure TPageDrawerShadingTests.TestShadingIsMadeOnceForManyFills;
begin
  Render('/Pattern cs /P1 scn 0 0 10 10 re f 20 0 10 10 re f 40 0 10 10 re f');

  Assert.AreEqual<Integer>(3, Length(CallsOfKind(TRecordedCallKind.Fill)));
  Assert.AreEqual<Integer>(0, CountLogLines('skipped'));
end;

end.
