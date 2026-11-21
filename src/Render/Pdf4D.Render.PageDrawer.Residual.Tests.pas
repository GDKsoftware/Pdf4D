// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of the translation residual of PageDrawer: what the Single translation of the page matrix lacks of the double one of PDFBox
// decides the pixel that a stroke is moved to (Java2D normalizes strokes on the double matrix), through the recording device
unit Pdf4D.Render.PageDrawer.Residual.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Types,
  DUnitX.TestFramework,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Render.Renderer.Interfaces,
  Pdf4D.Tests.RecordingDevice,
  Pdf4D.Tests.PatternDocuments;

type
  // The page is 200 pt high and the scale is 150 / 72 (a Single). A stroke at y = 188 is 12 points from the top: exactly
  // 12 * Double(Scale) = 24.999999046 pixels in double precision, but 25.000004768 with the Single translation of the matrix (416.66665649
  // instead of 416.66665077). Java2D puts the line in pixel 24 (centre 24.5); without the residual it would be in pixel 25.
  [TestFixture]
  TPageDrawerResidualTests = class
  private
    const Scale: Single = 150 / 72;
    const StrokeAtTwelvePoints = '1 w 0 188 m 100 188 l S';
    const Tolerance = 0.001;

  private
    FDocuments: TPatternDocuments;
    FDocument: IPdfDocument;
    FRenderer: IPdfRenderer;
    FDevice: TRecordingDevice;
    FDeviceReference: IPdfRasterDevice;

    procedure RenderWith(const Params: TPdfRenderParams);
    function Strokes(const Device: TRecordingDevice): TArray<TRecordedCall>;
    function TopOfOnlyStroke(const Device: TRecordingDevice): Single;
    function GroupDocument(const PageContent, GroupContent: string): IPdfDocument;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestPageStrokeIsNormalizedOnTheDoubleTranslation;

    [Test]
    procedure TestRegionOffsetKeepsTheResidual;

    [Test]
    procedure TestGroupContentHasNoResidual;

    [Test]
    procedure TestResidualIsRestoredAfterAGroup;

    [Test]
    procedure TestResidualIsRestoredAfterATilingPattern;
  end;

implementation

uses
  System.Generics.Collections,
  Pdf4D.Render.Renderer,
  Pdf4D.Tests.GraphicsDocuments;

{ TPageDrawerResidualTests }

procedure TPageDrawerResidualTests.Setup;
begin
  FDocuments := TPatternDocuments.Create;
end;

procedure TPageDrawerResidualTests.TearDown;
begin
  FDeviceReference := nil;
  FRenderer := nil;
  FDocument := nil;
  FreeAndNil(FDocuments);
end;

procedure TPageDrawerResidualTests.RenderWith(const Params: TPdfRenderParams);
begin
  FRenderer := TPdfRenderer.Create(FDocument, TRecordingBackend.Create);

  const Status = FRenderer.RenderPage(0, FDeviceReference, Params);

  Assert.AreEqual(TPdfRenderStatus.Completed, Status);
end;

function TPageDrawerResidualTests.Strokes(const Device: TRecordingDevice): TArray<TRecordedCall>;
begin
  const Found = TList<TRecordedCall>.Create;
  try
    for var Call in Device.Calls do
    begin
      if Call.Kind = TRecordedCallKind.Stroke then
      begin
        Found.Add(Call);
      end;
    end;
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

function TPageDrawerResidualTests.TopOfOnlyStroke(const Device: TRecordingDevice): Single;
begin
  const Found = Strokes(Device);
  Assert.AreEqual<Integer>(1, Length(Found));
  Result := Found[0].DeviceBounds.Top;
end;

function TPageDrawerResidualTests.GroupDocument(const PageContent, GroupContent: string): IPdfDocument;
begin
  const Builder = TGraphicsDocuments.NewBuilder(TEncoding.ASCII.GetBytes(PageContent), '/XObject << /G1 5 0 R >>');
  try
    Builder.AddStreamObject(5, '/Type /XObject /Subtype /Form /BBox [0 0 200 200] /Group << /S /Transparency /I true >> /Resources << >>',
                            TEncoding.ASCII.GetBytes(GroupContent));
    Result := FDocuments.Open(Builder);
  finally
    Builder.Free;
  end;
end;

procedure TPageDrawerResidualTests.TestPageStrokeIsNormalizedOnTheDoubleTranslation;
begin
  FDevice := TRecordingDevice.Create(417, 417);
  FDeviceReference := FDevice;
  FDocument := FDocuments.Open(StrokeAtTwelvePoints, '');

  RenderWith(TPdfRenderParams.Create(Scale));

  Assert.AreEqual(Double(24.5), Double(TopOfOnlyStroke(FDevice)), Tolerance);
end;

// The region moves the page by whole pixels: the line is 10 pixels higher and still in the pixel that Java2D picks
procedure TPageDrawerResidualTests.TestRegionOffsetKeepsTheResidual;
begin
  FDevice := TRecordingDevice.Create(300, 300);
  FDeviceReference := FDevice;
  FDocument := FDocuments.Open(StrokeAtTwelvePoints, '');
  var Params := TPdfRenderParams.Create(Scale);
  Params.Region := TRect.Create(0, 10, 300, 310);

  RenderWith(Params);

  Assert.AreEqual(Double(14.5), Double(TopOfOnlyStroke(FDevice)), Tolerance);
end;

// PDFBox draws a group in a space with the scale only, so the translation of the page is not in it: the group has no residual and the
// Single translation decides (25.5), as it does for the pixel grid of the group
procedure TPageDrawerResidualTests.TestGroupContentHasNoResidual;
begin
  FDevice := TRecordingDevice.Create(417, 417);
  FDeviceReference := FDevice;
  FDocument := GroupDocument('/G1 Do', StrokeAtTwelvePoints);

  RenderWith(TPdfRenderParams.Create(Scale));

  Assert.AreEqual<Integer>(1, FDevice.LayerCount);
  Assert.AreEqual(Double(25.5), Double(TopOfOnlyStroke(FDevice.Layers[0])), Tolerance);
end;

procedure TPageDrawerResidualTests.TestResidualIsRestoredAfterAGroup;
begin
  FDevice := TRecordingDevice.Create(417, 417);
  FDeviceReference := FDevice;
  FDocument := GroupDocument('/G1 Do ' + StrokeAtTwelvePoints, '0 0 m 1 1 l S');

  RenderWith(TPdfRenderParams.Create(Scale));

  Assert.AreEqual(Double(24.5), Double(TopOfOnlyStroke(FDevice)), Tolerance);
end;

procedure TPageDrawerResidualTests.TestResidualIsRestoredAfterATilingPattern;
begin
  FDevice := TRecordingDevice.Create(417, 417);
  FDeviceReference := FDevice;
  FDocument := FDocuments.OpenWithPatterns('/Pattern cs /P1 scn 0 0 50 50 re f ' + StrokeAtTwelvePoints,
                                           [TTilingSource.Square(1, '10', '0 1 0 rg 0 0 5 5 re f 1 w 0 5 m 10 5 l S')]);

  RenderWith(TPdfRenderParams.Create(Scale));

  Assert.AreEqual(Double(24.5), Double(TopOfOnlyStroke(FDevice)), Tolerance);
end;

end.
