// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of the soft masks and transfer functions of PageDrawer (PDFBox 3.0.8): applySoftMaskToPaint and applyTransferFunction, through
// the recording device. The recording layers have no pixels, so the values of the masks are tested in the SoftMaskPaint tests and on the
// Skia backend.
unit Pdf4D.Render.PageDrawer.SoftMask.Tests;

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
  TPageDrawerSoftMaskTests = class
  private
    const MaskGroupObject = 5;
    const MaskStateObject = 6;
    const MaskedFill = '/GsMask gs 0 0 1 rg 20 20 50 50 re f';
    const WhiteSquare = '1 g 0 0 100 100 re f';
    const GroupHead = '/Type /XObject /Subtype /Form /BBox [0 0 100 100] /Group << /S /Transparency /CS /DeviceGray >>';
    const GroupEntries = GroupHead + ' /Resources << >>';
    const PageResources = '/XObject << /G1 7 0 R /Im1 8 0 R /Im2 9 0 R >> /ExtGState << /GsMask 6 0 R /GsNone << /SMask /None >> /GsHalf << /ca 0.5 >> >>';
    const ImageEntries = '/Type /XObject /Subtype /Image /Width 1 /Height 1 /BitsPerComponent 8';

  private
    FDocuments: TGraphicsDocuments;
    FDocument: IPdfDocument;
    FRenderer: IPdfRenderer;
    FDevice: TRecordingDevice;
    FDeviceReference: IPdfRasterDevice;

    // The soft mask is the state in object 6, its group object 5 with GroupContent; Mask holds the entries of the soft mask after /G
    function NewBuilder(const PageContent: string): TTestPdfBuilder;
    procedure AddMask(const Builder: TTestPdfBuilder; const MaskEntries, MaskGroupEntries, GroupContent: string);
    procedure AddImages(const Builder: TTestPdfBuilder);
    procedure Render(const Builder: TTestPdfBuilder);
    procedure RenderMasked(const PageContent: string; const MaskEntries: string = '/S /Luminosity');
    function CallsOfKind(const Device: TRecordingDevice; const Kind: TRecordedCallKind): TArray<TRecordedCall>;
    function CountLogLines(const Fragment: string): Integer;
    function ImageGray(const PageContent, TransferEntry: string): TRecordedCall;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestFillGetsTheSoftMaskOfTheGraphicsState;

    [Test]
    procedure TestSoftMaskNoneRemovesTheMask;

    [Test]
    procedure TestMaskGroupIsDrawnOnALayerWithoutSoftMask;

    [Test]
    procedure TestMaskCoversTheBoxOfTheGroup;

    [Test]
    procedure TestBackdropColorOutsideBBox;

    [Test]
    procedure TestNoBackdropColorGivesBlackOutside;

    [Test]
    procedure TestAlphaMaskIgnoresTheBackdropColor;

    [Test]
    procedure TestTransferFunctionDoesNotMapTheBackdropOutside;

    [Test]
    procedure TestMaskGroupStartsWithBlackColours;

    [Test]
    procedure TestMaskGroupStartsWithBlackStrokeColour;

    [Test]
    procedure TestEmptySoftMaskIsIgnored;

    [Test]
    procedure TestSoftMaskWithoutGroupIsIgnoredWithAWarning;

    [Test]
    procedure TestSoftMaskReferencingItselfStops;

    [Test]
    procedure TestSoftMaskChainStopsAtTheDepthLimit;

    [Test]
    procedure TestSoftMaskIsMadeOnceForSeveralFills;

    [Test]
    procedure TestGroupContentHasNoSoftMaskAndTheGroupResultHasIt;

    [Test]
    procedure TestImageGetsTheSoftMask;

    [Test]
    procedure TestImageSMaskOverridesGraphicsStateMask;

    [Test]
    procedure TestTransferFunctionChangesTheImage;

    [Test]
    procedure TestTransferFunctionPerColourChangesOnlyThatColour;

    [Test]
    procedure TestTransferNamesLeaveTheImage;

    [Test]
    procedure TestTransferFunctionThatCannotBeMadeIsLogged;
  end;

implementation

uses
  System.Types,
  Pdf4D.Render.Renderer;

const
  AllowedDifference = 1;

{ TPageDrawerSoftMaskTests }

procedure TPageDrawerSoftMaskTests.Setup;
begin
  FDocuments := TGraphicsDocuments.Create;
  FDevice := TRecordingDevice.Create(TGraphicsDocuments.PageSize, TGraphicsDocuments.PageSize);
  FDeviceReference := FDevice;
end;

procedure TPageDrawerSoftMaskTests.TearDown;
begin
  FDeviceReference := nil;
  FRenderer := nil;
  FDocument := nil;
  FreeAndNil(FDocuments);
end;

function TPageDrawerSoftMaskTests.NewBuilder(const PageContent: string): TTestPdfBuilder;
begin
  Result := TGraphicsDocuments.NewBuilder(TEncoding.ASCII.GetBytes(PageContent), PageResources);
end;

procedure TPageDrawerSoftMaskTests.AddMask(const Builder: TTestPdfBuilder; const MaskEntries, MaskGroupEntries, GroupContent: string);
begin
  Builder.AddObject(MaskStateObject, Format('<< /Type /ExtGState /SMask << /Type /Mask %s /G %d 0 R >> >>', [MaskEntries, MaskGroupObject]));
  Builder.AddStreamObject(MaskGroupObject, MaskGroupEntries, TEncoding.ASCII.GetBytes(GroupContent));
  Builder.AddStreamObject(7, GroupEntries, TEncoding.ASCII.GetBytes('1 0 0 rg 10 10 50 50 re f 0 1 0 rg 40 40 50 50 re f'));
end;

// Object 8 is an RGB image of one pixel (255, 128, 0), object 9 the same image with a soft mask image
procedure TPageDrawerSoftMaskTests.AddImages(const Builder: TTestPdfBuilder);
begin
  Builder.AddStreamObject(8, ImageEntries + ' /ColorSpace /DeviceRGB', [255, 128, 0]);
  Builder.AddStreamObject(9, ImageEntries + ' /ColorSpace /DeviceRGB /SMask 10 0 R', [255, 128, 0]);
  Builder.AddStreamObject(10, ImageEntries + ' /ColorSpace /DeviceGray', [255]);
end;

procedure TPageDrawerSoftMaskTests.Render(const Builder: TTestPdfBuilder);
begin
  FDocument := FDocuments.Open(Builder);
  FRenderer := TPdfRenderer.Create(FDocument, TRecordingBackend.Create);

  const Status = FRenderer.RenderPage(0, FDeviceReference, TPdfRenderParams.Create(1));

  Assert.AreEqual(TPdfRenderStatus.Completed, Status);
end;

procedure TPageDrawerSoftMaskTests.RenderMasked(const PageContent: string; const MaskEntries: string);
begin
  const Builder = NewBuilder(PageContent);
  try
    AddMask(Builder, MaskEntries, GroupEntries, WhiteSquare);
    Render(Builder);
  finally
    Builder.Free;
  end;
end;

function TPageDrawerSoftMaskTests.CallsOfKind(const Device: TRecordingDevice; const Kind: TRecordedCallKind): TArray<TRecordedCall>;
begin
  const Found = TList<TRecordedCall>.Create;
  try
    for var Call in Device.Calls do
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

function TPageDrawerSoftMaskTests.CountLogLines(const Fragment: string): Integer;
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

// The bitmap that the image Im1 (255, 128, 0) draws, after the state of PageContent
function TPageDrawerSoftMaskTests.ImageGray(const PageContent, TransferEntry: string): TRecordedCall;
begin
  const Builder = TGraphicsDocuments.NewBuilder(TEncoding.ASCII.GetBytes(PageContent), Format('/XObject << /Im1 8 0 R >> /ExtGState << /GsTransfer << %s >> >>', [TransferEntry]));
  try
    AddImages(Builder);
    Render(Builder);
  finally
    Builder.Free;
  end;

  const Calls = CallsOfKind(FDevice, TRecordedCallKind.Bitmap);
  Assert.AreEqual<Integer>(1, Length(Calls));
  Result := Calls[0];
end;

procedure TPageDrawerSoftMaskTests.TestFillGetsTheSoftMaskOfTheGraphicsState;
begin
  RenderMasked(MaskedFill);

  const Fills = CallsOfKind(FDevice, TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(1, Length(Fills));
  Assert.IsTrue(Fills[0].HasSoftMask);
end;

procedure TPageDrawerSoftMaskTests.TestSoftMaskNoneRemovesTheMask;
begin
  RenderMasked('/GsMask gs /GsNone gs 0 0 1 rg 20 20 50 50 re f');

  const Fills = CallsOfKind(FDevice, TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(1, Length(Fills));
  Assert.IsFalse(Fills[0].HasSoftMask);
end;

procedure TPageDrawerSoftMaskTests.TestMaskGroupIsDrawnOnALayerWithoutSoftMask;
begin
  RenderMasked(MaskedFill);

  Assert.AreEqual<Integer>(1, FDevice.LayerCount);
  const Fills = CallsOfKind(FDevice.Layers[0], TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(1, Length(Fills));
  Assert.IsFalse(Fills[0].HasSoftMask);
end;

// The box (0, 0)-(100, 100) of the page is (0, 100)-(100, 200) of the device. A group that is drawn lies one pixel lower than its box (see
// the group tests); the references show that the mask of a soft mask does not.
procedure TPageDrawerSoftMaskTests.TestMaskCoversTheBoxOfTheGroup;
begin
  RenderMasked(MaskedFill);

  const Fills = CallsOfKind(FDevice, TRecordedCallKind.Fill);
  Assert.AreEqual(TRect.Create(0, 100, 100, 200), Fills[0].SoftMaskRectangle);
  Assert.AreEqual<Integer>(100 * 100, Length(Fills[0].SoftMaskValues));
end;

procedure TPageDrawerSoftMaskTests.TestBackdropColorOutsideBBox;
begin
  RenderMasked(MaskedFill, '/S /Luminosity /BC [0.5]');

  const Fills = CallsOfKind(FDevice, TRecordedCallKind.Fill);
  Assert.AreEqual(Double(128), Double(Fills[0].SoftMaskOutside), AllowedDifference);
  const Layers = CallsOfKind(FDevice.Layers[0], TRecordedCallKind.Clear);
  Assert.AreEqual<Integer>(1, Length(Layers), 'the layer of the group starts with the backdrop colour');
end;

procedure TPageDrawerSoftMaskTests.TestNoBackdropColorGivesBlackOutside;
begin
  RenderMasked(MaskedFill);

  const Fills = CallsOfKind(FDevice, TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(0, Fills[0].SoftMaskOutside);
end;

procedure TPageDrawerSoftMaskTests.TestAlphaMaskIgnoresTheBackdropColor;
begin
  RenderMasked(MaskedFill, '/S /Alpha /BC [0.5]');

  const Fills = CallsOfKind(FDevice, TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(0, Fills[0].SoftMaskOutside);
end;

// An inverting /TR does not map the value outside the box: PDFBox gives bc / 255 there, so black stays masked
procedure TPageDrawerSoftMaskTests.TestTransferFunctionDoesNotMapTheBackdropOutside;
begin
  RenderMasked(MaskedFill, '/S /Luminosity /TR << /FunctionType 2 /Domain [0 1] /C0 [1] /C1 [0] /N 1 >>');

  const Fills = CallsOfKind(FDevice, TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(0, Fills[0].SoftMaskOutside);
end;

// processSoftMask: the group starts with DeviceGray black as non-stroking colour, whatever the page has set
procedure TPageDrawerSoftMaskTests.TestMaskGroupStartsWithBlackColours;
begin
  const Builder = NewBuilder('1 0 0 rg /GsMask gs 20 20 50 50 re f');
  try
    AddMask(Builder, '/S /Luminosity', GroupEntries, '0 0 100 100 re f');
    Render(Builder);
  finally
    Builder.Free;
  end;

  const Fills = CallsOfKind(FDevice.Layers[0], TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(1, Length(Fills));
  Assert.AreEqual<Integer>(0, Fills[0].Paint.Color.R);
  Assert.AreEqual<Integer>(0, Fills[0].Paint.Color.G);
  Assert.AreEqual<Integer>(0, Fills[0].Paint.Color.B);
end;

procedure TPageDrawerSoftMaskTests.TestMaskGroupStartsWithBlackStrokeColour;
begin
  const Builder = NewBuilder('1 0 0 RG /GsMask gs 20 20 50 50 re f');
  try
    AddMask(Builder, '/S /Luminosity', GroupEntries, '10 10 80 80 re S');
    Render(Builder);
  finally
    Builder.Free;
  end;

  const Strokes = CallsOfKind(FDevice.Layers[0], TRecordedCallKind.Stroke);
  Assert.AreEqual<Integer>(1, Length(Strokes));
  Assert.AreEqual<Integer>(0, Strokes[0].Paint.Color.R);
  Assert.AreEqual<Integer>(0, Strokes[0].Paint.Color.G);
end;

// The box of the group lies outside of the page: nothing of it is drawn
procedure TPageDrawerSoftMaskTests.TestEmptySoftMaskIsIgnored;
begin
  const Builder = NewBuilder(MaskedFill);
  try
    AddMask(Builder, '/S /Luminosity', '/Type /XObject /Subtype /Form /BBox [300 300 400 400] /Group << /S /Transparency >> /Resources << >>', WhiteSquare);
    Render(Builder);
  finally
    Builder.Free;
  end;

  const Fills = CallsOfKind(FDevice, TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(1, Length(Fills));
  Assert.IsFalse(Fills[0].HasSoftMask);
  Assert.AreEqual<Integer>(0, FDevice.LayerCount);
end;

procedure TPageDrawerSoftMaskTests.TestSoftMaskWithoutGroupIsIgnoredWithAWarning;
begin
  const Builder = NewBuilder('/GsMask gs 0 0 1 rg 20 20 50 50 re f');
  try
    Builder.AddObject(MaskStateObject, '<< /Type /ExtGState /SMask << /Type /Mask /S /Luminosity >> >>');
    Render(Builder);
  finally
    Builder.Free;
  end;

  const Fills = CallsOfKind(FDevice, TRecordedCallKind.Fill);
  Assert.IsFalse(Fills[0].HasSoftMask);
  Assert.AreEqual<Integer>(1, CountLogLines('has no group stream'));
end;

// The group sets the same soft mask again and paints: the group is running already, so the second run is skipped like a form that draws itself
procedure TPageDrawerSoftMaskTests.TestSoftMaskReferencingItselfStops;
begin
  const Builder = NewBuilder(MaskedFill);
  try
    AddMask(Builder, '/S /Luminosity', GroupHead + ' /Resources << /ExtGState << /GsMask 6 0 R >> >>', '/GsMask gs ' + WhiteSquare);
    Render(Builder);
  finally
    Builder.Free;
  end;

  Assert.IsTrue(CountLogLines('draws itself (recursion)') > 0, string.Join(' / ', FDocuments.LogLines.ToArray));
  const Fills = CallsOfKind(FDevice, TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(1, Length(Fills));
  Assert.IsTrue(Fills[0].HasSoftMask);
end;

// Every group sets the soft mask of the next one, twelve in all: the soft masks are nested as deep as the limit allows
procedure TPageDrawerSoftMaskTests.TestSoftMaskChainStopsAtTheDepthLimit;
begin
  const ChainLength = 12;
  const FirstState = 20;
  const Builder = TGraphicsDocuments.NewBuilder(TEncoding.ASCII.GetBytes(MaskedFill), Format('/ExtGState << /GsMask %d 0 R >>', [FirstState]));
  try
    for var Index := 0 to ChainLength - 1 do
    begin
      const StateObject = FirstState + 2 * Index;
      const GroupObject = StateObject + 1;
      Builder.AddObject(StateObject, Format('<< /Type /ExtGState /SMask << /Type /Mask /S /Luminosity /G %d 0 R >> >>', [GroupObject]));
      const NextResources = Format('/Resources << /ExtGState << /GsMask %d 0 R >> >>', [StateObject + 2]);
      Builder.AddStreamObject(GroupObject, GroupHead + ' ' + NextResources, TEncoding.ASCII.GetBytes('/GsMask gs ' + WhiteSquare));
    end;
    Render(Builder);
  finally
    Builder.Free;
  end;

  Assert.AreEqual<Integer>(1, CountLogLines('Soft masks are nested as deep as the limit of 8'), string.Join(' / ', FDocuments.LogLines.ToArray));
  var Depth := 0;
  var Device := FDevice;
  while Device.LayerCount > 0 do
  begin
    Inc(Depth);
    Device := Device.Layers[Device.LayerCount - 1];
  end;
  Assert.AreEqual<Integer>(8, Depth);
end;

procedure TPageDrawerSoftMaskTests.TestSoftMaskIsMadeOnceForSeveralFills;
begin
  RenderMasked('/GsMask gs 0 0 1 rg 20 20 50 50 re f 1 0 0 rg 60 60 50 50 re f');

  Assert.AreEqual<Integer>(2, Length(CallsOfKind(FDevice, TRecordedCallKind.Fill)));
  Assert.AreEqual<Integer>(1, FDevice.LayerCount);
end;

// processTransparencyGroup resets the soft mask for the content of the group; the outer soft mask is applied to the result
procedure TPageDrawerSoftMaskTests.TestGroupContentHasNoSoftMaskAndTheGroupResultHasIt;
begin
  RenderMasked('/GsMask gs /G1 Do');

  const Bitmaps = CallsOfKind(FDevice, TRecordedCallKind.Bitmap);
  Assert.AreEqual<Integer>(1, Length(Bitmaps));
  Assert.IsTrue(Bitmaps[0].HasSoftMask, 'the result of the group');
  // The layer of the group is the first one, that of the soft mask the second
  Assert.AreEqual<Integer>(2, FDevice.LayerCount);
  const Fills = CallsOfKind(FDevice.Layers[0], TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(2, Length(Fills));
  Assert.IsFalse(Fills[0].HasSoftMask);
  Assert.IsFalse(Fills[1].HasSoftMask);
end;

procedure TPageDrawerSoftMaskTests.TestImageGetsTheSoftMask;
begin
  const Builder = NewBuilder('/GsMask gs 50 0 0 50 10 10 cm /Im1 Do');
  try
    AddMask(Builder, '/S /Luminosity', GroupEntries, WhiteSquare);
    AddImages(Builder);
    Render(Builder);
  finally
    Builder.Free;
  end;

  const Bitmaps = CallsOfKind(FDevice, TRecordedCallKind.Bitmap);
  Assert.AreEqual<Integer>(1, Length(Bitmaps));
  Assert.IsTrue(Bitmaps[0].HasSoftMask);
end;

// PDFBOX-5307
procedure TPageDrawerSoftMaskTests.TestImageSMaskOverridesGraphicsStateMask;
begin
  const Builder = NewBuilder('/GsMask gs 50 0 0 50 10 10 cm /Im2 Do');
  try
    AddMask(Builder, '/S /Luminosity', GroupEntries, WhiteSquare);
    AddImages(Builder);
    Render(Builder);
  finally
    Builder.Free;
  end;

  const Bitmaps = CallsOfKind(FDevice, TRecordedCallKind.Bitmap);
  Assert.AreEqual<Integer>(1, Length(Bitmaps));
  Assert.IsFalse(Bitmaps[0].HasSoftMask);
end;

// The function 1 - x on (255, 128, 0): (0, 127, 255); the value is truncated like (int) in Java
procedure TPageDrawerSoftMaskTests.TestTransferFunctionChangesTheImage;
begin
  const Call = ImageGray('/GsTransfer gs 50 0 0 50 10 10 cm /Im1 Do', '/TR2 << /FunctionType 2 /Domain [0 1] /C0 [1] /C1 [0] /N 1 >>');

  Assert.AreEqual(Double(0), Double(Call.BitmapPixels[0]), AllowedDifference);
  Assert.AreEqual(Double(127), Double(Call.BitmapPixels[1]), AllowedDifference);
  Assert.AreEqual(Double(255), Double(Call.BitmapPixels[2]), AllowedDifference);
  Assert.AreEqual<Integer>(255, Call.BitmapPixels[3]);
end;

procedure TPageDrawerSoftMaskTests.TestTransferFunctionPerColourChangesOnlyThatColour;
begin
  const Inverse = '<< /FunctionType 2 /Domain [0 1] /C0 [1] /C1 [0] /N 1 >>';
  const Same = '<< /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [1] /N 1 >>';
  const Call = ImageGray('/GsTransfer gs 50 0 0 50 10 10 cm /Im1 Do', Format('/TR2 [%s %s %s %s]', [Inverse, Same, Same, Same]));

  Assert.AreEqual(Double(0), Double(Call.BitmapPixels[0]), AllowedDifference);
  Assert.AreEqual(Double(128), Double(Call.BitmapPixels[1]), AllowedDifference);
  Assert.AreEqual(Double(0), Double(Call.BitmapPixels[2]), AllowedDifference);
end;

procedure TPageDrawerSoftMaskTests.TestTransferNamesLeaveTheImage;
begin
  const Identity = ImageGray('/GsTransfer gs 50 0 0 50 10 10 cm /Im1 Do', '/TR2 /Identity');

  Assert.AreEqual<Integer>(255, Identity.BitmapPixels[0]);
  Assert.AreEqual<Integer>(128, Identity.BitmapPixels[1]);
  Assert.AreEqual<Integer>(0, Identity.BitmapPixels[2]);
end;

procedure TPageDrawerSoftMaskTests.TestTransferFunctionThatCannotBeMadeIsLogged;
begin
  const Call = ImageGray('/GsTransfer gs 50 0 0 50 10 10 cm /Im1 Do', '/TR2 << /FunctionType 9 >>');

  Assert.AreEqual<Integer>(255, Call.BitmapPixels[0]);
  Assert.AreEqual<Integer>(1, CountLogLines('A transfer function is ignored'));
end;

end.
