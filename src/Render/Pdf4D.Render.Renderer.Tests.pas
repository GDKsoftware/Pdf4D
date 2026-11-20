// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of the public render API: regions, limits, cancelling, the background and the arguments (PDFRenderer 3.0.8)
unit Pdf4D.Render.Renderer.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Common.Matrix,
  Pdf4D.Common.Path,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Render.Renderer.Interfaces,
  Pdf4D.Tests.GraphicsDocuments,
  Pdf4D.Tests.RecordingDevice;

type
  // Says cancelled from the check after Limit checks on, and counts the checks
  TCountingCancelToken = class(TInterfacedObject, IPdfCancelToken)
  private
    FLimit: Integer;
    FChecks: Integer;

  public
    constructor Create(const Limit: Integer);

    function IsCancelled: Boolean;

    property Checks: Integer read FChecks;
  end;

  // A recording device that is slow to fill, so that a page with many fills takes a long time on any machine
  TSlowRasterDevice = class(TInterfacedObject, IPdfRasterDevice)
  private
    FInner: IPdfRasterDevice;

  public
    constructor Create(const Inner: IPdfRasterDevice);

    function Width: Integer;
    function Height: Integer;
    procedure SetClip(const Clip: IPdfClipPath);
    procedure FillPath(const Path: TPdfPath; const Transform: TPdfMatrix; const FillRule: TPdfFillRule; const Paint: TPdfPaint;
                       const Composite: TPdfComposite);
    procedure StrokePath(const Path: TPdfPath; const Transform: TPdfMatrix; const Stroke: TPdfStrokeStyle; const Paint: TPdfPaint;
                         const Composite: TPdfComposite);
    procedure DrawBitmap(const Bitmap: TPdfBitmap; const BitmapToDevice: TPdfMatrix; const Filter: TPdfImageFilter;
                         const Composite: TPdfComposite);
    procedure Clear(const Color: TPdfDeviceColor);
    function CreateLayer(const Width, Height: Integer): IPdfRasterDevice;
    function TryReadPixels(const Area: TRect; out Bitmap: TPdfBitmap): Boolean;
    function ToBitmap: TPdfBitmap;
  end;

  TSlowBackend = class(TInterfacedObject, IPdfRenderBackend)
  public
    function Name: string;
    function CreateRasterDevice(const Width, Height: Integer): IPdfRasterDevice;
  end;

  [TestFixture]
  TPdfRendererTests = class
  private
    const Tolerance: Single = 0.001;
    const Rectangle = '10 10 100 50 re f';

  private
    FDocuments: TGraphicsDocuments;
    FDocument: IPdfDocument;
    FRenderer: IPdfRenderer;
    FBackend: TRecordingBackend;
    FBackendReference: IPdfRenderBackend;

    procedure AssertNear(const Expected, Actual: Single);
    procedure Open(const Content: string; const Resources: string = ''; const PageEntries: string = '');
    function FillsOf(const Device: TRecordingDevice): TArray<TRecordedCall>;
    function RenderRegion(const Content: string; const Region: TRect; const DeviceWidth, DeviceHeight: Integer): TArray<TRecordedCall>;
    function ManyRectangles(const Count: Integer): string;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestBackendIsTheBackendOfTheRenderer;

    [Test]
    procedure TestRegionTranslatesDevice;

    [Test]
    procedure TestRegionPartlyOutsidePage;

    [Test]
    procedure TestTooLargeRegionRaisesBeforeDrawing;

    [Test]
    procedure TestTooLargeBitmapRaisesBeforeDrawing;

    [Test]
    procedure TestCancelBeforeStart;

    [Test]
    procedure TestCancelAfterThreeChecks;

    [Test]
    procedure TestCancelFromOtherThreadStopsRender;

    [Test]
    procedure TestRenderToBitmapClearsWithBackground;

    [Test]
    procedure TestRenderToBitmapUsesTheRegionSize;

    [Test]
    procedure TestBlendModePageIsRenderedTransparentAndFlattened;

    [Test]
    procedure TestPageTransformAddsExtraRotation;

    [Test]
    procedure TestRotatedPageSwapsTheBitmapSize;

    [Test]
    procedure TestInvalidArgumentsRaise;

    [Test]
    procedure TestOtherDocumentImplementationRaises;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Diagnostics,
  Pdf4D.Api.Attachment.Interfaces,
  Pdf4D.Api.Field.Interfaces,
  Pdf4D.Api.Outline.Interfaces,
  Pdf4D.Api.Page.Interfaces,
  Pdf4D.Api.TextLayout.Interfaces,
  Pdf4D.Api.TextOptions,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Document,
  Pdf4D.Render.CancelToken,
  Pdf4D.Render.Renderer;

type
  TUnrelatedDocument = class(TInterfacedObject, IPdfDocument)
  public
    function PageCount: Integer;
    function Pages: TArray<IPdfPage>;
    function Page(const Index: Integer): IPdfPage;
    function Version: Single;
    function IsEncrypted: Boolean;
    function Permissions: IPdfPermissions;
    function Info: IPdfDocumentInfo;
    function XmpMetadata: TBytes;
    function Outline: TArray<IPdfOutlineItem>;
    function Fields: TArray<IPdfField>;
    function Attachments: TArray<IPdfAttachment>;
    function ExtractText: string; overload;
    function ExtractText(const Options: TPdfTextOptions): string; overload;
    procedure WriteText(const Writer: TTextWriter; const Options: TPdfTextOptions);
    function ExtractTextWithPositions: IPdfPositionedText; overload;
    function ExtractTextWithPositions(const Options: TPdfTextOptions): IPdfPositionedText; overload;
    function CosDocument: TCosDocument;
  end;

{ TCountingCancelToken }

constructor TCountingCancelToken.Create(const Limit: Integer);
begin
  inherited Create;
  FLimit := Limit;
end;

function TCountingCancelToken.IsCancelled: Boolean;
begin
  Inc(FChecks);
  Result := (FChecks > FLimit);
end;

{ TSlowRasterDevice }

constructor TSlowRasterDevice.Create(const Inner: IPdfRasterDevice);
begin
  inherited Create;
  FInner := Inner;
end;

function TSlowRasterDevice.Width: Integer;
begin
  Result := FInner.Width;
end;

function TSlowRasterDevice.Height: Integer;
begin
  Result := FInner.Height;
end;

procedure TSlowRasterDevice.SetClip(const Clip: IPdfClipPath);
begin
  FInner.SetClip(Clip);
end;

procedure TSlowRasterDevice.FillPath(const Path: TPdfPath; const Transform: TPdfMatrix; const FillRule: TPdfFillRule; const Paint: TPdfPaint;
                                     const Composite: TPdfComposite);
begin
  Sleep(1);
  FInner.FillPath(Path, Transform, FillRule, Paint, Composite);
end;

procedure TSlowRasterDevice.StrokePath(const Path: TPdfPath; const Transform: TPdfMatrix; const Stroke: TPdfStrokeStyle; const Paint: TPdfPaint;
                                       const Composite: TPdfComposite);
begin
  FInner.StrokePath(Path, Transform, Stroke, Paint, Composite);
end;

procedure TSlowRasterDevice.DrawBitmap(const Bitmap: TPdfBitmap; const BitmapToDevice: TPdfMatrix; const Filter: TPdfImageFilter;
                                       const Composite: TPdfComposite);
begin
  FInner.DrawBitmap(Bitmap, BitmapToDevice, Filter, Composite);
end;

procedure TSlowRasterDevice.Clear(const Color: TPdfDeviceColor);
begin
  FInner.Clear(Color);
end;

function TSlowRasterDevice.CreateLayer(const Width, Height: Integer): IPdfRasterDevice;
begin
  Result := FInner.CreateLayer(Width, Height);
end;

function TSlowRasterDevice.TryReadPixels(const Area: TRect; out Bitmap: TPdfBitmap): Boolean;
begin
  Result := FInner.TryReadPixels(Area, Bitmap);
end;

function TSlowRasterDevice.ToBitmap: TPdfBitmap;
begin
  Result := FInner.ToBitmap;
end;

{ TSlowBackend }

function TSlowBackend.Name: string;
begin
  Result := 'Slow';
end;

function TSlowBackend.CreateRasterDevice(const Width, Height: Integer): IPdfRasterDevice;
begin
  Result := TSlowRasterDevice.Create(TRecordingDevice.Create(Width, Height));
end;

{ TUnrelatedDocument }

function TUnrelatedDocument.PageCount: Integer;
begin
  Result := 0;
end;

function TUnrelatedDocument.Pages: TArray<IPdfPage>;
begin
  Result := nil;
end;

function TUnrelatedDocument.Page(const Index: Integer): IPdfPage;
begin
  Result := nil;
end;

function TUnrelatedDocument.Version: Single;
begin
  Result := 1.7;
end;

function TUnrelatedDocument.IsEncrypted: Boolean;
begin
  Result := False;
end;

function TUnrelatedDocument.Permissions: IPdfPermissions;
begin
  Result := nil;
end;

function TUnrelatedDocument.Info: IPdfDocumentInfo;
begin
  Result := nil;
end;

function TUnrelatedDocument.XmpMetadata: TBytes;
begin
  Result := nil;
end;

function TUnrelatedDocument.Outline: TArray<IPdfOutlineItem>;
begin
  Result := nil;
end;

function TUnrelatedDocument.Fields: TArray<IPdfField>;
begin
  Result := nil;
end;

function TUnrelatedDocument.Attachments: TArray<IPdfAttachment>;
begin
  Result := nil;
end;

function TUnrelatedDocument.ExtractText: string;
begin
  Result := '';
end;

function TUnrelatedDocument.ExtractText(const Options: TPdfTextOptions): string;
begin
  Result := '';
end;

procedure TUnrelatedDocument.WriteText(const Writer: TTextWriter; const Options: TPdfTextOptions);
begin
end;

function TUnrelatedDocument.ExtractTextWithPositions: IPdfPositionedText;
begin
  Result := nil;
end;

function TUnrelatedDocument.ExtractTextWithPositions(const Options: TPdfTextOptions): IPdfPositionedText;
begin
  Result := nil;
end;

function TUnrelatedDocument.CosDocument: TCosDocument;
begin
  Result := nil;
end;

{ TPdfRendererTests }

procedure TPdfRendererTests.AssertNear(const Expected, Actual: Single);
begin
  Assert.AreEqual(Double(Expected), Double(Actual), Double(Tolerance));
end;

procedure TPdfRendererTests.Setup;
begin
  FDocuments := TGraphicsDocuments.Create;
  FBackend := TRecordingBackend.Create;
  FBackendReference := FBackend;
end;

procedure TPdfRendererTests.TearDown;
begin
  FRenderer := nil;
  FDocument := nil;
  FBackendReference := nil;
  FreeAndNil(FDocuments);
end;

procedure TPdfRendererTests.Open(const Content: string; const Resources: string; const PageEntries: string);
begin
  FDocument := FDocuments.Open(Content, Resources, PageEntries);
  FRenderer := TPdfRenderer.Create(FDocument, FBackendReference);
end;

function TPdfRendererTests.FillsOf(const Device: TRecordingDevice): TArray<TRecordedCall>;
begin
  const Found = TList<TRecordedCall>.Create;
  try
    for var Call in Device.Calls do
    begin
      if Call.Kind = TRecordedCallKind.Fill then
      begin
        Found.Add(Call);
      end;
    end;
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

function TPdfRendererTests.RenderRegion(const Content: string; const Region: TRect; const DeviceWidth, DeviceHeight: Integer): TArray<TRecordedCall>;
begin
  Open(Content);
  const Device = TRecordingDevice.Create(DeviceWidth, DeviceHeight);
  const Reference: IPdfRasterDevice = Device;
  var Params := TPdfRenderParams.Create(1);
  Params.Region := Region;

  FRenderer.RenderPage(0, Reference, Params);

  Result := FillsOf(Device);
end;

function TPdfRendererTests.ManyRectangles(const Count: Integer): string;
begin
  const Builder = TStringBuilder.Create;
  try
    for var Index := 1 to Count do
    begin
      Builder.Append('0 0 10 10 re f ');
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

procedure TPdfRendererTests.TestBackendIsTheBackendOfTheRenderer;
begin
  Open('');

  Assert.IsTrue(FRenderer.Backend = FBackendReference);
end;

procedure TPdfRendererTests.TestRegionTranslatesDevice;
begin
  const Whole = RenderRegion(Rectangle, TRect.Empty, 200, 200);
  const Part = RenderRegion(Rectangle, TRect.Create(50, 50, 150, 150), 100, 100);

  Assert.AreEqual<Integer>(1, Length(Whole));
  Assert.AreEqual<Integer>(1, Length(Part));
  AssertNear(Whole[0].DeviceBounds.Left - 50, Part[0].DeviceBounds.Left);
  AssertNear(Whole[0].DeviceBounds.Top - 50, Part[0].DeviceBounds.Top);
  AssertNear(Whole[0].DeviceBounds.Right - 50, Part[0].DeviceBounds.Right);
  AssertNear(Whole[0].DeviceBounds.Bottom - 50, Part[0].DeviceBounds.Bottom);
end;

procedure TPdfRendererTests.TestRegionPartlyOutsidePage;
begin
  Open('0 0 200 200 re f');
  const Device = TRecordingDevice.Create(100, 100);
  const Reference: IPdfRasterDevice = Device;
  var Params := TPdfRenderParams.Create(1);
  Params.Region := TRect.Create(150, 150, 250, 250);

  const Status = FRenderer.RenderPage(0, Reference, Params);

  Assert.AreEqual(TPdfRenderStatus.Completed, Status);
  Assert.AreEqual<Integer>(1, Length(FillsOf(Device)));
  // The page ends at the 50th pixel of the device: nothing beyond it is page
  const PageClip = Device.Clip.Path.Clone;
  try
    PageClip.Transform(Device.Clip.Transform);
    AssertNear(-150, PageClip.Bounds.Left);
    AssertNear(50, PageClip.Bounds.Right);
    AssertNear(50, PageClip.Bounds.Bottom);
  finally
    PageClip.Free;
  end;
end;

procedure TPdfRendererTests.TestTooLargeRegionRaisesBeforeDrawing;
begin
  Open(Rectangle);
  const Device = TRecordingDevice.Create(10000, 10000);
  const Reference: IPdfRasterDevice = Device;

  Assert.WillRaise(
    procedure
    begin
      FRenderer.RenderPage(0, Reference, TPdfRenderParams.Create(1));
    end,
    EPdfLimitExceededException);
  Assert.AreEqual<Integer>(0, Device.Calls.Count);
end;

procedure TPdfRendererTests.TestTooLargeBitmapRaisesBeforeDrawing;
begin
  Open(Rectangle);
  var Params := TPdfRenderParams.Create(1);
  Params.Region := TRect.Create(0, 0, 10000, 10000);
  var Bitmap: TPdfBitmap;

  Assert.WillRaise(
    procedure
    begin
      FRenderer.RenderToBitmap(0, Params, Bitmap);
    end,
    EPdfLimitExceededException);
  Assert.IsNull(FBackend.LastDevice);
end;

procedure TPdfRendererTests.TestCancelBeforeStart;
begin
  Open(ManyRectangles(5));
  const Token = TPdfCancelToken.Create;
  const Reference: IPdfCancelToken = Token;
  Token.Cancel;
  const Device = TRecordingDevice.Create(200, 200);
  const DeviceReference: IPdfRasterDevice = Device;
  var Params := TPdfRenderParams.Create(1);
  Params.Cancel := Reference;

  const Status = FRenderer.RenderPage(0, DeviceReference, Params);

  Assert.AreEqual(TPdfRenderStatus.Cancelled, Status);
  Assert.AreEqual<Integer>(0, Length(FillsOf(Device)));
end;

procedure TPdfRendererTests.TestCancelAfterThreeChecks;
begin
  Open(ManyRectangles(10));
  const Token = TCountingCancelToken.Create(3);
  const Reference: IPdfCancelToken = Token;
  const Device = TRecordingDevice.Create(200, 200);
  const DeviceReference: IPdfRasterDevice = Device;
  var Params := TPdfRenderParams.Create(1);
  Params.Cancel := Reference;

  const Status = FRenderer.RenderPage(0, DeviceReference, Params);

  Assert.AreEqual(TPdfRenderStatus.Cancelled, Status);
  Assert.IsTrue(Length(FillsOf(Device)) <= 3, 'Fills: ' + Length(FillsOf(Device)).ToString);
end;

// 100000 fills of a millisecond each take far longer than the 50 ms before the cancel, on any machine
procedure TPdfRendererTests.TestCancelFromOtherThreadStopsRender;
begin
  FDocument := FDocuments.Open(ManyRectangles(100000), '');
  FRenderer := TPdfRenderer.Create(FDocument, TSlowBackend.Create);
  const Token = TPdfCancelToken.Create;
  const Reference: IPdfCancelToken = Token;
  var Params := TPdfRenderParams.Create(1);
  Params.Cancel := Reference;
  var CancelledAt: Int64 := 0;

  const Canceller = TThread.CreateAnonymousThread(
    procedure
    begin
      Sleep(50);
      CancelledAt := TStopwatch.GetTimeStamp;
      Token.Cancel;
    end);
  Canceller.FreeOnTerminate := False;
  var Bitmap: TPdfBitmap := nil;
  try
    Canceller.Start;
    const Status = FRenderer.RenderToBitmap(0, Params, Bitmap);
    const Elapsed = TStopwatch.GetTimeStamp - CancelledAt;

    Assert.AreEqual(TPdfRenderStatus.Cancelled, Status);
    Assert.IsNull(Bitmap);
    Assert.IsTrue(Elapsed < TStopwatch.Frequency, 'The render took more than a second to stop');
  finally
    Canceller.WaitFor;
    Canceller.Free;
    Bitmap.Free;
  end;
end;

procedure TPdfRendererTests.TestRenderToBitmapClearsWithBackground;
begin
  Open('');
  var Bitmap: TPdfBitmap;

  const Status = FRenderer.RenderToBitmap(0, TPdfRenderParams.Create(1), Bitmap);
  try
    Assert.AreEqual(TPdfRenderStatus.Completed, Status);
    Assert.IsNotNull(Bitmap);
    Assert.AreEqual<Integer>(200, Bitmap.Width);
    Assert.AreEqual<Integer>(200, Bitmap.Height);
    Assert.IsNotNull(FBackend.LastDevice);
    Assert.AreEqual(TRecordedCallKind.Clear, FBackend.LastDevice.Calls[0].Kind);
    Assert.AreEqual(Byte(255), FBackend.LastDevice.Calls[0].Paint.Color.R);
    Assert.AreEqual(Byte(255), FBackend.LastDevice.Calls[0].Paint.Color.A);
  finally
    Bitmap.Free;
  end;
end;

procedure TPdfRendererTests.TestRenderToBitmapUsesTheRegionSize;
begin
  Open(Rectangle);
  var Params := TPdfRenderParams.Create(1);
  Params.Region := TRect.Create(50, 50, 150, 100);
  var Bitmap: TPdfBitmap;

  FRenderer.RenderToBitmap(0, Params, Bitmap);
  try
    Assert.AreEqual<Integer>(100, Bitmap.Width);
    Assert.AreEqual<Integer>(50, Bitmap.Height);
  finally
    Bitmap.Free;
  end;
end;

// PDFBOX-4095
procedure TPdfRendererTests.TestBlendModePageIsRenderedTransparentAndFlattened;
begin
  Open(Rectangle, '/ExtGState << /GS1 << /BM /Multiply >> >>');
  var Bitmap: TPdfBitmap;

  FRenderer.RenderToBitmap(0, TPdfRenderParams.Create(1), Bitmap);
  try
    Assert.AreEqual(TRecordedCallKind.Clear, FBackend.LastDevice.Calls[0].Kind);
    Assert.AreEqual(Byte(0), FBackend.LastDevice.Calls[0].Paint.Color.A);
    // The recording device draws nothing, so what is left after flattening is the background
    Assert.AreEqual(Byte(255), Bitmap.GetPixel(0, 0).A);
    Assert.AreEqual(Byte(255), Bitmap.GetPixel(0, 0).R);
  finally
    Bitmap.Free;
  end;
end;

procedure TPdfRendererTests.TestPageTransformAddsExtraRotation;
begin
  Open('', '', '/CropBox [0 0 100 200] /Rotate 90');

  const Plain = FRenderer.PageTransform(0, 1);
  const Extra = FRenderer.PageTransform(0, 1, 90);

  Assert.AreEqual<Integer>(200, Plain.Size.cx);
  Assert.AreEqual<Integer>(100, Plain.Size.cy);
  Assert.AreEqual<Integer>(100, Extra.Size.cx);
  Assert.AreEqual<Integer>(200, Extra.Size.cy);
end;

procedure TPdfRendererTests.TestRotatedPageSwapsTheBitmapSize;
begin
  Open('', '', '/CropBox [0 0 100 200] /Rotate 90');
  var Bitmap: TPdfBitmap;

  FRenderer.RenderToBitmap(0, TPdfRenderParams.Create(1), Bitmap);
  try
    Assert.AreEqual<Integer>(200, Bitmap.Width);
    Assert.AreEqual<Integer>(100, Bitmap.Height);
  finally
    Bitmap.Free;
  end;
end;

procedure TPdfRendererTests.TestInvalidArgumentsRaise;
begin
  Open(Rectangle);
  const Device = TRecordingDevice.Create(200, 200);
  const Reference: IPdfRasterDevice = Device;
  var Bitmap: TPdfBitmap;

  Assert.WillRaise(
    procedure
    begin
      FRenderer.RenderPage(-1, Reference, TPdfRenderParams.Create(1));
    end,
    EArgumentOutOfRangeException);
  Assert.WillRaise(
    procedure
    begin
      FRenderer.RenderPage(1, Reference, TPdfRenderParams.Create(1));
    end,
    EArgumentOutOfRangeException);
  Assert.WillRaise(
    procedure
    begin
      FRenderer.RenderToBitmap(-1, TPdfRenderParams.Create(1), Bitmap);
    end,
    EArgumentOutOfRangeException);
  Assert.WillRaise(
    procedure
    begin
      FRenderer.PageTransform(-1, 1);
    end,
    EArgumentOutOfRangeException);
  Assert.WillRaiseDescendant(
    procedure
    begin
      var Params := TPdfRenderParams.Create(1);
      Params.Scale := 0;
      FRenderer.RenderPage(0, Reference, Params);
    end,
    EArgumentException);
  Assert.WillRaise(
    procedure
    begin
      var Params := TPdfRenderParams.Create(1);
      Params.ExtraRotation := 45;
      FRenderer.RenderPage(0, Reference, Params);
    end,
    EArgumentException);
  Assert.WillRaise(
    procedure
    begin
      var Params := TPdfRenderParams.Create(1);
      Params.ExtraRotation := 45;
      FRenderer.RenderToBitmap(0, Params, Bitmap);
    end,
    EArgumentException);
  Assert.WillRaise(
    procedure
    begin
      FRenderer.RenderPage(0, nil, TPdfRenderParams.Create(1));
    end,
    EArgumentNilException);
  Assert.AreEqual<Integer>(0, Device.Calls.Count);
end;

procedure TPdfRendererTests.TestOtherDocumentImplementationRaises;
begin
  const Other: IPdfDocument = TUnrelatedDocument.Create;

  Assert.WillRaise(
    procedure
    begin
      TPdfRenderer.Create(Other, FBackendReference);
    end,
    EArgumentException);
  Assert.WillRaise(
    procedure
    begin
      TPdfRenderer.Create(nil, FBackendReference);
    end,
    EArgumentNilException);
end;

end.
