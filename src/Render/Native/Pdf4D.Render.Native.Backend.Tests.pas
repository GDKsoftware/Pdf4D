// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.Native.Backend.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Classes,
  DUnitX.TestFramework,
  Pdf4D.Common.Matrix,
  Pdf4D.Common.Path,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.ClipPath,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Render.Native.Backend;

type
  // Renders page 1 of a file with a backend that other threads use as well
  TPageRenderThread = class(TThread)
  private
    FBackend: IPdfRenderBackend;
    FPath: string;
    FBitmap: TPdfBitmap;
    FFailure: string;

  protected
    procedure Execute; override;

  public
    constructor Create(const Backend: IPdfRenderBackend; const Path: string);
    destructor Destroy; override;

    property Bitmap: TPdfBitmap read FBitmap;
    property Failure: string read FFailure;
  end;

  [TestFixture]
  TPdfNativeBackendTests = class
  private
    function NewLongPath(const VerbCount: Integer): TPdfPath;
    function NewDevice(const MaxPathVerbs: Integer): IPdfRasterDevice;
    function FillRaisesTheLimit(const Device: IPdfRasterDevice; const Path: TPdfPath): Boolean;
    function StrokeRaisesTheLimit(const Device: IPdfRasterDevice; const Path: TPdfPath): Boolean;
    function IsDeviceUntouched(const Device: IPdfRasterDevice): Boolean;

  public
    [Test]
    procedure TestNameIsNative;

    [Test]
    procedure TestTooLargeDeviceRaises;

    [Test]
    procedure TestLimitsWithoutVerbsAreRefused;

    [Test]
    procedure TestPathVerbLimitRaisesBeforeDrawing;

    [Test]
    procedure TestClipPathOverTheLimitRaisesAtTheNextDraw;

    [Test]
    procedure TestBackendCanBeSharedAcrossThreads;

    [Test]
    procedure TestRendererWithNativeBackendRendersPage;

    // The backend is made for the call and nothing else holds it: the renderer that is refused has to free it (the runner reports a leak)
    [Test]
    procedure TestRendererWithoutDocumentReleasesTheBackend;
  end;

implementation

uses
  System.Types,
  Pdf4D.Api.Document,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Common.Defines,
  Pdf4D.Render.Renderer,
  Pdf4D.Render.Renderer.Interfaces,
  Pdf4D.Tests.Corpus;

const
  PathsFile = 'generated/render/paths.pdf';

function RenderPage(const Backend: IPdfRenderBackend; const Path: string): TPdfBitmap;
begin
  const Document: IPdfDocument = TPdfDocument.Load(Path, TPdfLoadOptions.Default);
  const Renderer: IPdfRenderer = TPdfRenderer.Create(Document, Backend);
  Result := nil;
  const Status = Renderer.RenderToBitmap(0, TPdfRenderParams.FromDpi(72), Result);
  if Status <> TPdfRenderStatus.Completed then
  begin
    FreeAndNil(Result);
    raise EInvalidOpException.CreateFmt('The render of %s ended with status %d', [Path, Ord(Status)]);
  end;
end;

{ TPageRenderThread }

constructor TPageRenderThread.Create(const Backend: IPdfRenderBackend; const Path: string);
begin
  inherited Create(True);
  FBackend := Backend;
  FPath := Path;
end;

destructor TPageRenderThread.Destroy;
begin
  FBitmap.Free;
  inherited Destroy;
end;

procedure TPageRenderThread.Execute;
begin
  try
    FBitmap := RenderPage(FBackend, FPath);
  except
    on Failure: Exception do
    begin
      FFailure := Failure.ClassName + ': ' + Failure.Message;
    end;
  end;
end;

{ TPdfNativeBackendTests }

function TPdfNativeBackendTests.NewLongPath(const VerbCount: Integer): TPdfPath;
begin
  Result := TPdfPath.Create;
  Result.MoveTo(0, 0);
  for var Index := 1 to VerbCount - 1 do
  begin
    Result.LineTo(Index mod 10, (Index div 10) mod 10);
  end;
end;

function TPdfNativeBackendTests.NewDevice(const MaxPathVerbs: Integer): IPdfRasterDevice;
begin
  var Limits := TPdfNativeLimits.Default;
  Limits.MaxPathVerbs := MaxPathVerbs;
  const Backend: IPdfRenderBackend = TPdfNativeBackend.Create(Limits);
  Result := Backend.CreateRasterDevice(10, 10);
end;

function TPdfNativeBackendTests.FillRaisesTheLimit(const Device: IPdfRasterDevice; const Path: TPdfPath): Boolean;
begin
  Result := False;
  try
    Device.FillPath(Path, TPdfMatrix.Identity, TPdfFillRule.NonZero, TPdfPaint.Solid(TPdfDeviceColor.Create(255, 0, 0)), TPdfComposite.Default);
  except
    on EPdfLimitExceededException do
    begin
      Result := True;
    end;
  end;
end;

function TPdfNativeBackendTests.StrokeRaisesTheLimit(const Device: IPdfRasterDevice; const Path: TPdfPath): Boolean;
begin
  var Stroke := Default(TPdfStrokeStyle);
  Stroke.Width := 2;
  Stroke.MiterLimit := 4;

  Result := False;
  try
    Device.StrokePath(Path, TPdfMatrix.Identity, Stroke, TPdfPaint.Solid(TPdfDeviceColor.Create(255, 0, 0)), TPdfComposite.Default);
  except
    on EPdfLimitExceededException do
    begin
      Result := True;
    end;
  end;
end;

function TPdfNativeBackendTests.IsDeviceUntouched(const Device: IPdfRasterDevice): Boolean;
begin
  const Bitmap = Device.ToBitmap;
  try
    Result := True;
    for var Index := 0 to Length(Bitmap.Pixels) - 1 do
    begin
      if Bitmap.Pixels[Index] <> 0 then
      begin
        Exit(False);
      end;
    end;
  finally
    Bitmap.Free;
  end;
end;

procedure TPdfNativeBackendTests.TestNameIsNative;
begin
  const Backend: IPdfRenderBackend = TPdfNativeBackend.Create;
  Assert.AreEqual('Native', Backend.Name);
{$IFDEF CPUX86}
  Assert.AreEqual(1048576, TPdfNativeLimits.Default.MaxPathVerbs);
{$ELSE}
  Assert.AreEqual(4194304, TPdfNativeLimits.Default.MaxPathVerbs);
{$ENDIF}
end;

procedure TPdfNativeBackendTests.TestTooLargeDeviceRaises;
begin
  const Backend: IPdfRenderBackend = TPdfNativeBackend.Create;
  var Raised := False;
  try
    Backend.CreateRasterDevice(65536, 65536);
  except
    on EArgumentOutOfRangeException do
    begin
      Raised := True;
    end;
  end;
  Assert.IsTrue(Raised, '65536 * 65536');

  Raised := False;
  try
    Backend.CreateRasterDevice(0, 5);
  except
    on EArgumentOutOfRangeException do
    begin
      Raised := True;
    end;
  end;
  Assert.IsTrue(Raised, 'a width of 0');
end;

procedure TPdfNativeBackendTests.TestPathVerbLimitRaisesBeforeDrawing;
begin
  const Device = NewDevice(1000);
  const AtTheLimit = NewLongPath(1000);
  const OverTheLimit = NewLongPath(1001);
  try
    Assert.IsTrue(FillRaisesTheLimit(Device, OverTheLimit), 'FillPath with 1001 verbs');
    Assert.IsTrue(StrokeRaisesTheLimit(Device, OverTheLimit), 'StrokePath with 1001 verbs');
    Assert.IsTrue(IsDeviceUntouched(Device), 'no pixel changed');

    Assert.IsFalse(FillRaisesTheLimit(Device, AtTheLimit), 'FillPath with 1000 verbs');
    Assert.IsFalse(StrokeRaisesTheLimit(Device, AtTheLimit), 'StrokePath with 1000 verbs');
  finally
    AtTheLimit.Free;
    OverTheLimit.Free;
  end;
end;

procedure TPdfNativeBackendTests.TestClipPathOverTheLimitRaisesAtTheNextDraw;
begin
  const Device = NewDevice(1000);
  const Square = TPdfPath.Create;
  try
    Square.MoveTo(0, 0);
    Square.LineTo(5, 0);
    Square.LineTo(5, 5);
    Square.LineTo(0, 5);
    Square.ClosePath;

    // The clip is taken when it is set; the draw that needs it raises
    Device.SetClip(TPdfClipPath.Create(nil, NewLongPath(1001), TPdfMatrix.Identity, TPdfFillRule.NonZero));
    Assert.IsTrue(FillRaisesTheLimit(Device, Square), 'a draw with a clip of 1001 verbs');
    Assert.IsTrue(IsDeviceUntouched(Device), 'no pixel changed');

    Device.SetClip(nil);
    Assert.IsFalse(FillRaisesTheLimit(Device, Square), 'without the clip the draw works');
  finally
    Square.Free;
  end;
end;

procedure TPdfNativeBackendTests.TestLimitsWithoutVerbsAreRefused;
begin
  var Limits := TPdfNativeLimits.Default;
  for var MaxPathVerbs in [0, -1, Low(Integer)] do
  begin
    Limits.MaxPathVerbs := MaxPathVerbs;
    var Raised := False;
    try
      TPdfNativeBackend.Create(Limits).Name;
    except
      on EArgumentOutOfRangeException do
      begin
        Raised := True;
      end;
    end;
    Assert.IsTrue(Raised, Format('MaxPathVerbs %d', [MaxPathVerbs]));
  end;

  Limits.MaxPathVerbs := 1;
  const Backend: IPdfRenderBackend = TPdfNativeBackend.Create(Limits);
  Assert.AreEqual('Native', Backend.Name);
end;

procedure TPdfNativeBackendTests.TestBackendCanBeSharedAcrossThreads;
begin
  const Backend: IPdfRenderBackend = TPdfNativeBackend.Create;
  const Path = TCorpus.PdfPath(PathsFile);
  const First = TPageRenderThread.Create(Backend, Path);
  const Second = TPageRenderThread.Create(Backend, Path);
  try
    First.Start;
    Second.Start;
    First.WaitFor;
    Second.WaitFor;

    Assert.AreEqual('', First.Failure);
    Assert.AreEqual('', Second.Failure);
    Assert.IsNotNull(First.Bitmap);
    Assert.IsNotNull(Second.Bitmap);
    Assert.AreEqual(Length(First.Bitmap.Pixels), Length(Second.Bitmap.Pixels));
    Assert.IsTrue(CompareMem(Pointer(First.Bitmap.Pixels), Pointer(Second.Bitmap.Pixels), Length(First.Bitmap.Pixels)),
                  'both threads render the same bytes');
  finally
    First.Free;
    Second.Free;
  end;
end;

procedure TPdfNativeBackendTests.TestRendererWithoutDocumentReleasesTheBackend;
begin
  Assert.WillRaise(
    procedure
    begin
      TPdfRenderer.Create(nil, TPdfNativeBackend.Create);
    end,
    EArgumentNilException);
end;

procedure TPdfNativeBackendTests.TestRendererWithNativeBackendRendersPage;
begin
  const Path = TCorpus.PdfPath(PathsFile);
  const Document: IPdfDocument = TPdfDocument.Load(Path, TPdfLoadOptions.Default);
  const Renderer: IPdfRenderer = TPdfRenderer.Create(Document, TPdfNativeBackend.Create);
  const PageSize = Renderer.PageTransform(0, 1).Size;

  var Bitmap: TPdfBitmap := nil;
  try
    Assert.AreEqual(Ord(TPdfRenderStatus.Completed), Ord(Renderer.RenderToBitmap(0, TPdfRenderParams.FromDpi(72), Bitmap)));
    Assert.AreEqual(Integer(PageSize.cx), Bitmap.Width);
    Assert.AreEqual(Integer(PageSize.cy), Bitmap.Height);

    var HasInk := False;
    for var Index := 0 to Length(Bitmap.Pixels) - 1 do
    begin
      if Bitmap.Pixels[Index] <> 255 then
      begin
        HasInk := True;
        Break;
      end;
    end;
    Assert.IsTrue(HasInk, 'the page is not all white');
  finally
    Bitmap.Free;
  end;
end;

end.
