// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.TestDocument;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.Backend,
  Pdf4D.Viewer.Document,
  Pdf4D.Viewer.Dispatcher,
  Pdf4D.Tests.ManualDispatcher,
  Pdf4D.Tests.RecordingDevice;

type
  // The document with its protected properties in the open
  TTestDocument = class(TPdf4DCustomDocument)
  public
    property FileName;
    property Password;
    property Backend;
    property IgnorePermissions;
    property PageTextCacheCount;
    property OnOpened;
    property OnOpenError;
    property OnClosed;
    property OnLog;
  end;

  // A backend component that hands out a recording backend and counts the requests
  TTestBackendComponent = class(TPdf4DRenderBackend)
  private
    FCreateCount: Integer;

  public
    function CreateBackend: IPdfRenderBackend; override;

    property CreateCount: Integer read FCreateCount;
  end;

  // A link that writes down what the document tells it
  TChangeRecorder = class
  private
    FLink: TPdfDocumentLink;
    FChanges: TList<TPdfDocumentChange>;

    procedure DocumentChanged(const Change: TPdfDocumentChange);

  public
    constructor Create(const Document: TPdf4DCustomDocument);
    destructor Destroy; override;

    function Count(const Change: TPdfDocumentChange): Integer;
    // The changes in order, by name: 'Opening,Opened'
    function Describe: string;
    procedure Reset;

    property Link: TPdfDocumentLink read FLink;
  end;

  // A document on a recording backend and a manual dispatcher, with a recorder on it: what the tests of the document need
  TDocumentBench = class
  private
    FDispatcher: TManualDispatcher;
    FDispatcherReference: IPdfViewerDispatcher;
    FBackend: TRecordingBackend;
    FBackendReference: IPdfRenderBackend;
    FDocument: TTestDocument;
    FRecorder: TChangeRecorder;

  public
    constructor Create;
    destructor Destroy; override;

    // For a test that frees the document itself
    procedure FreeDocument;
    // Runs the dispatcher until Condition holds
    procedure WaitUntil(const Condition: TFunc<Boolean>; const Description: string);
    // Opens from a stream and waits until the document is no longer Opening
    procedure OpenData(const Data: TBytes; const Password: string = '');
    procedure OpenFile(const FileName, Password: string);

    property Dispatcher: TManualDispatcher read FDispatcher;
    property Backend: TRecordingBackend read FBackend;
    property Document: TTestDocument read FDocument;
    property Recorder: TChangeRecorder read FRecorder;
  end;

implementation

uses
  System.TypInfo,
  DUnitX.TestFramework;

const
  // Upper bound for every wait; a test that reaches it fails with a message
  WaitMs = 20000;

{ TTestBackendComponent }

function TTestBackendComponent.CreateBackend: IPdfRenderBackend;
begin
  Inc(FCreateCount);
  Result := TRecordingBackend.Create;
end;

{ TChangeRecorder }

constructor TChangeRecorder.Create(const Document: TPdf4DCustomDocument);
begin
  inherited Create;
  FChanges := TList<TPdfDocumentChange>.Create;
  FLink := TPdfDocumentLink.Create(DocumentChanged);
  FLink.Document := Document;
end;

destructor TChangeRecorder.Destroy;
begin
  FLink.Free;
  FChanges.Free;
  inherited;
end;

procedure TChangeRecorder.DocumentChanged(const Change: TPdfDocumentChange);
begin
  FChanges.Add(Change);
end;

function TChangeRecorder.Count(const Change: TPdfDocumentChange): Integer;
begin
  Result := 0;
  for var Recorded in FChanges do
  begin
    if Recorded = Change then
    begin
      Inc(Result);
    end;
  end;
end;

function TChangeRecorder.Describe: string;
begin
  Result := '';
  for var Recorded in FChanges do
  begin
    if not Result.IsEmpty then
    begin
      Result := Result + ',';
    end;
    Result := Result + GetEnumName(TypeInfo(TPdfDocumentChange), Ord(Recorded));
  end;
end;

procedure TChangeRecorder.Reset;
begin
  FChanges.Clear;
end;

{ TDocumentBench }

constructor TDocumentBench.Create;
begin
  inherited Create;
  FDispatcher := TManualDispatcher.Create;
  FDispatcherReference := FDispatcher;
  FBackend := TRecordingBackend.Create;
  FBackendReference := FBackend;
  FDocument := TTestDocument.Create(nil);
  FDocument.RenderBackend := FBackendReference;
  FDocument.Dispatcher := FDispatcherReference;
  FRecorder := TChangeRecorder.Create(FDocument);
end;

destructor TDocumentBench.Destroy;
begin
  FRecorder.Free;
  // The document first: its session waits for its worker, which may still post
  FDocument.Free;
  FBackendReference := nil;
  FDispatcherReference := nil;
  inherited;
end;

procedure TDocumentBench.FreeDocument;
begin
  FreeAndNil(FDocument);
end;

procedure TDocumentBench.WaitUntil(const Condition: TFunc<Boolean>; const Description: string);
begin
  Assert.IsTrue(FDispatcher.RunUntil(Condition, WaitMs), 'Timed out waiting for ' + Description);
end;

procedure TDocumentBench.OpenData(const Data: TBytes; const Password: string);
begin
  const Stream = TBytesStream.Create(Data);
  try
    FDocument.Password := Password;
    FDocument.Open(Stream);
  finally
    Stream.Free;
  end;

  WaitUntil(
    function: Boolean
    begin
      Result := (FDocument.State <> TPdfDocumentState.Opening);
    end,
    'the document to open');
end;

procedure TDocumentBench.OpenFile(const FileName, Password: string);
begin
  FDocument.FileName := FileName;
  FDocument.Password := Password;
  FDocument.Open;

  WaitUntil(
    function: Boolean
    begin
      Result := (FDocument.State <> TPdfDocumentState.Opening);
    end,
    'the file to open');
end;

end.
