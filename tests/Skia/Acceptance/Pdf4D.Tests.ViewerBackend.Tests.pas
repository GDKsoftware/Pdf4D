// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.ViewerBackend.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  DUnitX.TestFramework,
  Pdf4D.Render.Device.Interfaces;

type
  // A backend that hands everything to the Skia backend and counts the devices that were asked for
  TCountingSkiaBackend = class(TInterfacedObject, IPdfRenderBackend)
  private
    FInner: IPdfRenderBackend;
    FDeviceCount: Integer;

  public
    constructor Create;

    function Name: string;
    function CreateRasterDevice(const Width, Height: Integer): IPdfRasterDevice;

    property DeviceCount: Integer read FDeviceCount;
  end;

  // The viewer renders with the own rasterizer unless the application sets a backend: an explicit Skia backend is kept
  [TestFixture]
  TViewerBackendTests = class
  public
    [Test]
    procedure TestExplicitSkiaBackendIsKept;
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  System.SyncObjs,
  Pdf4D.Render.Skia.Backend,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.Session,
  Pdf4D.Viewer.Dispatcher,
  Pdf4D.Viewer.Document,
  Pdf4D.Tests.Corpus,
  Pdf4D.Tests.ManualDispatcher;

type
  // The document with FileName in the open
  TFileDocument = class(TPdf4DCustomDocument)
  public
    property FileName;
  end;

const
  ClipFile = 'generated/render/clip.pdf';
  WaitMilliseconds = 20000;

{ TCountingSkiaBackend }

constructor TCountingSkiaBackend.Create;
begin
  inherited Create;
  FInner := TPdfSkiaBackend.Create;
end;

function TCountingSkiaBackend.Name: string;
begin
  Result := FInner.Name;
end;

function TCountingSkiaBackend.CreateRasterDevice(const Width, Height: Integer): IPdfRasterDevice;
begin
  TInterlocked.Increment(FDeviceCount);
  Result := FInner.CreateRasterDevice(Width, Height);
end;

{ TViewerBackendTests }

procedure TViewerBackendTests.TestExplicitSkiaBackendIsKept;
begin
  const Backend = TCountingSkiaBackend.Create;
  const BackendReference: IPdfRenderBackend = Backend;
  const Dispatcher = TManualDispatcher.Create;
  const DispatcherReference: IPdfViewerDispatcher = Dispatcher;
  const Document = TFileDocument.Create(nil);
  try
    Document.RenderBackend := BackendReference;
    Document.Dispatcher := DispatcherReference;
    Document.FileName := TCorpus.PdfPath(ClipFile);

    Document.Open;
    Assert.IsTrue(Dispatcher.RunUntil(
      function: Boolean
      begin
        Result := Document.State <> TPdfDocumentState.Opening;
      end, WaitMilliseconds), 'the document opens');
    Assert.AreEqual(Ord(TPdfDocumentState.Open), Ord(Document.State), 'the document is open');

    var Done := False;
    var Succeeded := False;
    Document.Session.RequestRender(0, 0.5, 0, TRect.Empty, TPdfJobPriority.Visible,
      procedure(const Outcome: TPdfRenderResult)
      begin
        Succeeded := Outcome.Succeeded;
        Done := True;
      end);
    Assert.IsTrue(Dispatcher.RunUntil(
      function: Boolean
      begin
        Result := Done;
      end, WaitMilliseconds), 'the render is done');

    Assert.IsTrue(Succeeded, 'the page is rendered');
    Assert.AreEqual('Skia', BackendReference.Name);
    Assert.IsTrue(Backend.DeviceCount > 0, 'the explicit Skia backend made the devices');
  finally
    Document.Free;
  end;
end;

end.
