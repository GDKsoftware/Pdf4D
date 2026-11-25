// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of the transparency groups of PageDrawer (PDFBox 3.0.8): showTransparencyGroup and the layers it draws on, through the
// recording device
unit Pdf4D.Render.PageDrawer.Groups.Tests;

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
  TPageDrawerGroupTests = class
  private
    const Tolerance = 0.0001;
    const GroupBox = '/BBox [0 0 100 100]';
    const IsolatedGroup = '/Group << /S /Transparency /I true >>';
    const Resources = '/XObject << /G1 5 0 R >> /ExtGState << /GsOne << /ca 1 >> /GsHalf << /ca 0.5 >> /GsMultiply << /BM /Multiply /ca 0.5 >> >>';
    const TwoRectangles = '/GsHalf gs 1 0 0 rg 10 10 50 50 re f 0 0 1 rg 40 40 50 50 re f';

  private
    FDocuments: TGraphicsDocuments;
    FDocument: IPdfDocument;
    FRenderer: IPdfRenderer;
    FDevice: TRecordingDevice;
    FDeviceReference: IPdfRasterDevice;

    // The group is object 5 of the document, resource /G1; GroupEntries come after the BBox
    procedure RenderGroup(const PageContent, GroupEntries, GroupContent: string);
    procedure RenderBuilder(const Builder: TTestPdfBuilder);
    function CallsOfKind(const Device: TRecordingDevice; const Kind: TRecordedCallKind): TArray<TRecordedCall>;
    function CountLogLines(const Fragment: string): Integer;
    function NestedGroups(const Depth: Integer): TTestPdfBuilder;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestIsolatedGroupDrawnAsOneImage;

    [Test]
    procedure TestGroupIsDrawnWithTheAlphaAndBlendModeOfTheGraphicsState;

    [Test]
    procedure TestGroupContentStartsWithNormalBlendingAndFullAlpha;

    [Test]
    procedure TestGroupBoundsAreDeviceClipped;

    [Test]
    procedure TestGroupBoundsAreClippedToTheDevice;

    [Test]
    procedure TestGroupIsDrawnLowerLikePdfBox;

    [Test]
    procedure TestGroupShiftFollowsTheFractionOfTheBounds;

    [Test]
    procedure TestGroupOutsideTheClipDrawsNothing;

    [Test]
    procedure TestGroupContentIsDrawnInLayerPixels;

    [Test]
    procedure TestClipOfTheGroupContentIsInLayerPixels;

    [Test]
    procedure TestNonIsolatedGroupWithoutBlendModeHasNoBackdropLayer;

    [Test]
    procedure TestGroupDepthLimit;

    [Test]
    procedure TestFormWithoutGroupIsDrawnOnTheDevice;
  end;

implementation

uses
  Pdf4D.Common.Matrix,
  Pdf4D.Render.Renderer;

const
  FirstNestedObject = 5;

{ TPageDrawerGroupTests }

procedure TPageDrawerGroupTests.Setup;
begin
  FDocuments := TGraphicsDocuments.Create;
  FDevice := TRecordingDevice.Create(TGraphicsDocuments.PageSize, TGraphicsDocuments.PageSize);
  FDeviceReference := FDevice;
end;

procedure TPageDrawerGroupTests.TearDown;
begin
  FDeviceReference := nil;
  FRenderer := nil;
  FDocument := nil;
  FreeAndNil(FDocuments);
end;

procedure TPageDrawerGroupTests.RenderBuilder(const Builder: TTestPdfBuilder);
begin
  FDocument := FDocuments.Open(Builder);
  FRenderer := TPdfRenderer.Create(FDocument, TRecordingBackend.Create);

  const Status = FRenderer.RenderPage(0, FDeviceReference, TPdfRenderParams.Create(1));

  Assert.AreEqual(TPdfRenderStatus.Completed, Status);
end;

procedure TPageDrawerGroupTests.RenderGroup(const PageContent, GroupEntries, GroupContent: string);
begin
  const Builder = TGraphicsDocuments.NewBuilder(TEncoding.ASCII.GetBytes(PageContent), Resources);
  try
    const Entries = Format('/Type /XObject /Subtype /Form %s %s /Resources << /ExtGState << /GsHalf << /ca 0.5 >> /GsMultiply << /BM /Multiply >> >> >>',
                           [GroupBox, GroupEntries]);
    Builder.AddStreamObject(FirstNestedObject, Entries, TEncoding.ASCII.GetBytes(GroupContent));
    RenderBuilder(Builder);
  finally
    Builder.Free;
  end;
end;

function TPageDrawerGroupTests.CallsOfKind(const Device: TRecordingDevice; const Kind: TRecordedCallKind): TArray<TRecordedCall>;
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

function TPageDrawerGroupTests.CountLogLines(const Fragment: string): Integer;
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

// Object 5 + Index is a group that draws object 5 + Index + 1; the last one draws a rectangle
function TPageDrawerGroupTests.NestedGroups(const Depth: Integer): TTestPdfBuilder;
begin
  Result := TGraphicsDocuments.NewBuilder(TEncoding.ASCII.GetBytes('/G1 Do'), '/XObject << /G1 5 0 R >>');
  try
    for var Index := 0 to Depth - 1 do
    begin
      const Number = FirstNestedObject + Index;
      var Content := '0 0 1 rg 0 0 10 10 re f';
      var NestedResources := '';
      if Index < Depth - 1 then
      begin
        Content := '/G1 Do';
        NestedResources := Format('/Resources << /XObject << /G1 %d 0 R >> >>', [Number + 1]);
      end;
      Result.AddStreamObject(Number, Format('/Type /XObject /Subtype /Form %s %s %s', [GroupBox, IsolatedGroup, NestedResources]),
                             TEncoding.ASCII.GetBytes(Content));
    end;
  except
    Result.Free;
    raise;
  end;
end;

procedure TPageDrawerGroupTests.TestIsolatedGroupDrawnAsOneImage;
begin
  RenderGroup('/GsOne gs /G1 Do', IsolatedGroup, TwoRectangles);

  const Bitmaps = CallsOfKind(FDevice, TRecordedCallKind.Bitmap);
  Assert.AreEqual<Integer>(1, Length(Bitmaps));
  Assert.AreEqual<Integer>(0, Length(CallsOfKind(FDevice, TRecordedCallKind.Fill)));
  Assert.AreEqual(Double(1), Double(Bitmaps[0].Composite.Alpha), Tolerance);
  Assert.AreEqual(TPdfBlendMode.Normal, Bitmaps[0].Composite.BlendMode);

  // The rectangles went to the layer, each with its own alpha
  Assert.AreEqual<Integer>(1, FDevice.LayerCount);
  const Fills = CallsOfKind(FDevice.Layers[0], TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(2, Length(Fills));
  Assert.AreEqual(Double(0.5), Double(Fills[0].Composite.Alpha), Tolerance);
  Assert.AreEqual(Double(0.5), Double(Fills[1].Composite.Alpha), Tolerance);
end;

procedure TPageDrawerGroupTests.TestGroupIsDrawnWithTheAlphaAndBlendModeOfTheGraphicsState;
begin
  RenderGroup('/GsMultiply gs /G1 Do', IsolatedGroup, TwoRectangles);

  const Bitmaps = CallsOfKind(FDevice, TRecordedCallKind.Bitmap);
  Assert.AreEqual<Integer>(1, Length(Bitmaps));
  Assert.AreEqual(Double(0.5), Double(Bitmaps[0].Composite.Alpha), Tolerance);
  Assert.AreEqual(TPdfBlendMode.Multiply, Bitmaps[0].Composite.BlendMode);
end;

procedure TPageDrawerGroupTests.TestGroupContentStartsWithNormalBlendingAndFullAlpha;
begin
  RenderGroup('/GsMultiply gs /G1 Do', IsolatedGroup, '1 0 0 rg 10 10 50 50 re f');

  const Fills = CallsOfKind(FDevice.Layers[0], TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(1, Length(Fills));
  Assert.AreEqual(Double(1), Double(Fills[0].Composite.Alpha), Tolerance);
  Assert.AreEqual(TPdfBlendMode.Normal, Fills[0].Composite.BlendMode);
end;

// The clip is 60 x 40 pixels at (20, 140); the BBox is far larger
procedure TPageDrawerGroupTests.TestGroupBoundsAreDeviceClipped;
begin
  RenderGroup('20 100 60 40 re W n /G1 Do', '/BBox [-1000 -1000 1000 1000] ' + IsolatedGroup, TwoRectangles);

  Assert.AreEqual<Integer>(1, FDevice.LayerCount);
  Assert.AreEqual<Integer>(60, FDevice.Layers[0].Width);
  Assert.AreEqual<Integer>(40, FDevice.Layers[0].Height);
  const Bitmaps = CallsOfKind(FDevice, TRecordedCallKind.Bitmap);
  Assert.AreEqual(Double(20), Double(Bitmaps[0].DeviceBounds.Left), Tolerance);
  Assert.AreEqual(Double(80), Double(Bitmaps[0].DeviceBounds.Right), Tolerance);
  // 40 pixels high, lower by the shift of the next test
  Assert.AreEqual(Double(40), Double(Bitmaps[0].DeviceBounds.Height), Tolerance);
end;

// PageDrawer.showTransparencyGroupOnGraphics: the image of the group is one row higher than the box (its height is floor(maximum) + 1
// - floor(minimum) of the bounds in the page), and it is drawn with its top at the top of the box while the content is aligned to its
// bottom: the content lies one pixel lower than it should. The group of the page lies at (20, 60)-(80, 100) of the device.
procedure TPageDrawerGroupTests.TestGroupIsDrawnLowerLikePdfBox;
begin
  RenderGroup('20 100 60 40 re W n /G1 Do', '/BBox [-1000 -1000 1000 1000] ' + IsolatedGroup, TwoRectangles);

  const Bitmaps = CallsOfKind(FDevice, TRecordedCallKind.Bitmap);
  Assert.AreEqual(Double(61), Double(Bitmaps[0].DeviceBounds.Top), Tolerance);
  Assert.AreEqual(Double(101), Double(Bitmaps[0].DeviceBounds.Bottom), Tolerance);
  Assert.AreEqual(TPdfImageFilter.Nearest, Bitmaps[0].Paint.Filter, 'an integer shift copies the pixels');
end;

// A box from y = 100.25 to 140.5 has 40.25 pixels, and its image 141 - 100 = 41: the content is 0.75 lower
procedure TPageDrawerGroupTests.TestGroupShiftFollowsTheFractionOfTheBounds;
begin
  RenderGroup('20 100.25 60 40.25 re W n /G1 Do', '/BBox [-1000 -1000 1000 1000] ' + IsolatedGroup, TwoRectangles);

  const Bitmaps = CallsOfKind(FDevice, TRecordedCallKind.Bitmap);
  // the layer starts at floor(200 - 140.5) = 59
  Assert.AreEqual(Double(59.75), Double(Bitmaps[0].DeviceBounds.Top), Tolerance);
  Assert.AreEqual(TPdfImageFilter.Bicubic, Bitmaps[0].Paint.Filter, 'a fraction of a pixel is interpolated');
end;

procedure TPageDrawerGroupTests.TestGroupBoundsAreClippedToTheDevice;
begin
  RenderGroup('/G1 Do', '/BBox [-1000 -1000 1000 1000] ' + IsolatedGroup, TwoRectangles);

  Assert.AreEqual<Integer>(TGraphicsDocuments.PageSize, FDevice.Layers[0].Width);
  Assert.AreEqual<Integer>(TGraphicsDocuments.PageSize, FDevice.Layers[0].Height);
end;

procedure TPageDrawerGroupTests.TestGroupOutsideTheClipDrawsNothing;
begin
  RenderGroup('500 500 10 10 re W n /G1 Do', IsolatedGroup, TwoRectangles);

  Assert.AreEqual<Integer>(0, FDevice.LayerCount);
  Assert.AreEqual<Integer>(0, Length(CallsOfKind(FDevice, TRecordedCallKind.Bitmap)));
end;

// The group lies at (20, 140) of the device: its content moves by that corner
procedure TPageDrawerGroupTests.TestGroupContentIsDrawnInLayerPixels;
begin
  RenderGroup('20 20 60 40 re W n /G1 Do', IsolatedGroup, '1 0 0 rg 20 20 10 10 re f');

  const Fills = CallsOfKind(FDevice.Layers[0], TRecordedCallKind.Fill);
  Assert.AreEqual<Integer>(1, Length(Fills));
  // The rectangle (20, 20)-(30, 30) of the page is (20, 170)-(30, 180) of the device and the layer starts at (20, 140)
  Assert.AreEqual(Double(0), Double(Fills[0].DeviceBounds.Left), Tolerance);
  Assert.AreEqual(Double(30), Double(Fills[0].DeviceBounds.Top), Tolerance);
  Assert.AreEqual(Double(10), Double(Fills[0].DeviceBounds.Right), Tolerance);
  Assert.AreEqual(Double(40), Double(Fills[0].DeviceBounds.Bottom), Tolerance);
end;

procedure TPageDrawerGroupTests.TestClipOfTheGroupContentIsInLayerPixels;
begin
  RenderGroup('20 20 60 40 re W n /G1 Do', IsolatedGroup, '1 0 0 rg 0 0 100 100 re f');

  const Layer = FDevice.Layers[0];
  Assert.IsNotNull(Layer.Clip);
  var Link := Layer.Clip;
  while Assigned(Link.Parent) do
  begin
    Link := Link.Parent;
  end;
  // The first link is the crop box of the page: (0, 0)-(200, 200) of the device, (-20, -140) in the layer
  const Corner = Link.Transform.TransformPoint(0, 200);
  Assert.AreEqual(Double(-20), Double(Corner.X), Tolerance);
  Assert.AreEqual(Double(-140), Double(Corner.Y), Tolerance);
end;

procedure TPageDrawerGroupTests.TestNonIsolatedGroupWithoutBlendModeHasNoBackdropLayer;
begin
  RenderGroup('/G1 Do', '/Group << /S /Transparency /I false >>', TwoRectangles);

  // The layer of the group only: a backdrop needs a second layer for the alpha
  Assert.AreEqual<Integer>(1, FDevice.LayerCount);
end;

procedure TPageDrawerGroupTests.TestGroupDepthLimit;
begin
  const Builder = NestedGroups(40);
  try
    RenderBuilder(Builder);
  finally
    Builder.Free;
  end;

  Assert.AreEqual<Integer>(1, CountLogLines('Transparency groups are nested as deep as the limit of 16'));
  var Depth := 0;
  var Device := FDevice;
  while Device.LayerCount > 0 do
  begin
    Inc(Depth);
    Device := Device.Layers[0];
  end;
  Assert.AreEqual<Integer>(16, Depth);
end;

procedure TPageDrawerGroupTests.TestFormWithoutGroupIsDrawnOnTheDevice;
begin
  RenderGroup('/G1 Do', '', TwoRectangles);

  Assert.AreEqual<Integer>(0, FDevice.LayerCount);
  Assert.AreEqual<Integer>(2, Length(CallsOfKind(FDevice, TRecordedCallKind.Fill)));
end;

end.
