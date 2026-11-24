// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.FmxHost;

{$EXCESSPRECISION OFF}
{$POINTERMATH ON}

interface

uses
  System.Classes,
  System.Types,
  System.SysUtils,
  System.UITypes,
  FMX.Controls,
  FMX.Forms,
  FMX.Graphics,
  FMX.Objects,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Viewer.Types,
  Pdf4D.FMX.Document;

type
  // A form with a document, made in the test process, on a scale that the test chooses. The form is shown outside the visible desktop.
  // What it draws is read back with Snapshot, in device pixels. Input goes through the Handle... methods of the shell, so that no desktop
  // session tool is needed.
  TFmxTestHost = class
  private
    FForm: TForm;
    FDocument: TPdf4DDocument;
    FContent: TRectangle;
    FScale: Single;
    FOpenErrorMessage: string;

    class var FWindowsMade: Integer;

    procedure HandleOpenError(Sender: TObject; const Kind: TPdfOpenErrorKind; const Message: string);

  public
    // A form whose client area is ClientWidth x ClientHeight logical units on the given scale (device pixels per logical unit; 1.5 is
    // 150 %), with a document that renders with Skia. Content fills the client area.
    constructor Create(const ClientWidth, ClientHeight: Integer; const Scale: Single = 1);
    destructor Destroy; override;

    // The document renders with Skia by default; without a backend Open raises EPdfViewerException
    procedure RemoveBackend;
    procedure RestoreBackend;
    // The render backend of the tests, for a second document
    class function NewRenderBackend: IPdfRenderBackend; static;
    // The message of the last failed open
    function OpenErrorMessage: string;
    // Waits until the document is Open or Failed, at most 5 seconds
    function Open(const Data: TBytes): Boolean;
    // Handles the queue of the main thread and the window messages until Condition holds
    function WaitUntil(const Condition: TFunc<Boolean>; const TimeoutMs: Integer = 5000): Boolean;
    // Handles what is queued for a while, for tests that wait for something that must not happen
    procedure Pump(const Milliseconds: Integer);

    // What the content area paints, in device pixels (BitmapScale is the scale of the form); the caller owns the bitmap
    function Snapshot: FMX.Graphics.TBitmap;
    // What any control of the form paints
    class function SnapshotOf(const Control: TControl): FMX.Graphics.TBitmap; static;
    // The colour of a pixel of a bitmap, as FMX reads it
    class function PixelAt(const Bitmap: FMX.Graphics.TBitmap; const X, Y: Integer): TAlphaColor; static;

    property Form: TForm read FForm;
    property Document: TPdf4DDocument read FDocument;
    // The control that Snapshot paints: a filled rectangle over the whole client area
    property Content: TRectangle read FContent;
    // The scale of the form: device pixels per logical unit
    property Scale: Single read FScale;

    // How many forms the process made so far; the leak check of the test program needs it (see there)
    class property WindowsMade: Integer read FWindowsMade;
  end;

implementation

uses
  System.Diagnostics,
  System.Math,
  FMX.Types,
  FMX.Platform.Win,
  Pdf4D.Render.Skia.Backend,
  Pdf4D.Viewer.Document,
  Pdf4D.FMX.Backend.Skia;

const
  OffDesktopPosition = -30000;
  PollMilliseconds = 5;
  OpenTimeoutMs = 5000;

{ TFmxTestHost }

constructor TFmxTestHost.Create(const ClientWidth, ClientHeight: Integer; const Scale: Single);
begin
  inherited Create;
  FScale := Scale;
  Inc(FWindowsMade);
  FForm := TForm.CreateNew(nil);
  FForm.Left := OffDesktopPosition;
  FForm.Top := OffDesktopPosition;
  // The scale of the window is the one of its monitor; the tests need a fixed one. The setting holds for the process, so every host sets
  // it, also the ones on scale 1.
  FForm.Show;
  (FForm.Handle as TWinWindowHandle).SetForcedScaleForForm(Scale);
  FForm.ClientWidth := ClientWidth;
  FForm.ClientHeight := ClientHeight;

  FDocument := TPdf4DDocument.Create(FForm);
  FDocument.OnOpenError := HandleOpenError;
  RestoreBackend;

  FContent := TRectangle.Create(FForm);
  FContent.Parent := FForm;
  FContent.Align := TAlignLayout.Client;
  FContent.Fill.Color := TAlphaColors.White;
  FContent.Stroke.Kind := TBrushKind.None;

  Pump(1);
end;

destructor TFmxTestHost.Destroy;
begin
  FForm.Free;
  inherited;
end;

procedure TFmxTestHost.HandleOpenError(Sender: TObject; const Kind: TPdfOpenErrorKind; const Message: string);
begin
  FOpenErrorMessage := Message;
end;

function TFmxTestHost.OpenErrorMessage: string;
begin
  Result := FOpenErrorMessage;
end;

procedure TFmxTestHost.RemoveBackend;
begin
  FDocument.RenderBackend := nil;
end;

class function TFmxTestHost.NewRenderBackend: IPdfRenderBackend;
begin
  Result := TPdfSkiaBackend.Create;
end;

procedure TFmxTestHost.RestoreBackend;
begin
  FDocument.RenderBackend := TPdfSkiaBackend.Create;
end;

procedure TFmxTestHost.Pump(const Milliseconds: Integer);
begin
  const Watch = TStopwatch.StartNew;
  repeat
    CheckSynchronize(PollMilliseconds);
    Application.ProcessMessages;
  until Watch.ElapsedMilliseconds >= Milliseconds;
end;

function TFmxTestHost.WaitUntil(const Condition: TFunc<Boolean>; const TimeoutMs: Integer): Boolean;
begin
  const Watch = TStopwatch.StartNew;
  repeat
    CheckSynchronize(PollMilliseconds);
    Application.ProcessMessages;
    Result := Condition();
  until Result or (Watch.ElapsedMilliseconds >= TimeoutMs);
end;

function TFmxTestHost.Open(const Data: TBytes): Boolean;
begin
  const Stream = TBytesStream.Create(Data);
  try
    FDocument.Open(Stream);
  finally
    Stream.Free;
  end;

  WaitUntil(
    function: Boolean
    begin
      Result := FDocument.State in [TPdfDocumentState.Open, TPdfDocumentState.Failed];
    end,
    OpenTimeoutMs);
  Result := (FDocument.State = TPdfDocumentState.Open);
end;

function TFmxTestHost.Snapshot: FMX.Graphics.TBitmap;
begin
  Result := SnapshotOf(FContent);
end;

class function TFmxTestHost.SnapshotOf(const Control: TControl): FMX.Graphics.TBitmap;
begin
  Result := Control.MakeScreenshot;
end;

class function TFmxTestHost.PixelAt(const Bitmap: FMX.Graphics.TBitmap; const X, Y: Integer): TAlphaColor;
begin
  var Data: TBitmapData;
  if not Bitmap.Map(TMapAccess.Read, Data) then
  begin
    raise EInvalidOpException.Create('The bitmap cannot be read.');
  end;

  try
    Result := Data.GetPixel(X, Y);
  finally
    Bitmap.Unmap(Data);
  end;
end;

end.
