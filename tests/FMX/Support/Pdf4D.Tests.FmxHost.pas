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
  System.Generics.Collections,
  FMX.Controls,
  FMX.Forms,
  FMX.Graphics,
  FMX.Objects,
  FMX.Types,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Viewer.Types,
  Pdf4D.FMX.Document,
  Pdf4D.FMX.PageView,
  Pdf4D.FMX.Thumbnails,
  Pdf4D.FMX.OutlineView,
  Pdf4D.FMX.SearchBar;

type
  // The page view of the tests: it remembers what was copied, so that a session without a clipboard does not hide a copy
  TTestPageView = class(TPdf4DPageView)
  private
    FCopiedTexts: TList<string>;

  protected
    procedure WriteClipboardText(const Text: string); override;

  public
    constructor Create(Owner: TComponent); override;
    destructor Destroy; override;

    property CopiedTexts: TList<string> read FCopiedTexts;
  end;

  // A form with a document, made in the test process, on a scale that the test chooses. The form is shown outside the visible desktop.
  // What it draws is read back with Snapshot, in device pixels. Input goes through the Handle... methods of the shell, so that no desktop
  // session tool is needed.
  TFmxTestHost = class
  private
    FForm: TForm;
    FDocument: TPdf4DDocument;
    FContent: TRectangle;
    FPageView: TTestPageView;
    FThumbnails: TPdf4DThumbnails;
    FOutlineView: TPdf4DOutlineView;
    FSearchBar: TPdf4DSearchBar;
    FScale: Single;
    FOpenErrorMessage: string;

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
    // Puts a page view over the whole client area, linked to the document; Snapshot paints it from then on
    function AddPageView: TTestPageView;
    // Put thumbnails (left), an outline view (right) or a search bar (top) in the form, linked to the document. Add them before the page
    // view, which takes what is left of the client area.
    function AddThumbnails(const Width: Integer): TPdf4DThumbnails;
    function AddOutlineView(const Width: Integer): TPdf4DOutlineView;
    function AddSearchBar: TPdf4DSearchBar;
    // Another scale for the form, as when it moves to another screen; the logical size of the client area stays
    procedure ChangeScale(const NewScale: Single);
    // Until the controller has no tiles outstanding
    function WaitForVisibleTiles: Boolean;
    // Until the text of the page is in the cache of the document
    function WaitForPageText(const PageIndex: Integer): Boolean;
    // The text of the clipboard of the window system; False when the session gives no access to it
    function TryGetClipboardText(out Text: string): Boolean;
    // True when the session lets the process use the clipboard: what was put there can be read back
    function PutClipboardText(const Text: string): Boolean;
    // Input for the page view, in logical units
    procedure MouseMove(const Point: TPointF);
    procedure Click(const Point: TPointF);
    procedure Drag(const FromPoint, ToPoint: TPointF);
    // A key as the form gets it from the window system; it reaches the control that has the focus. True when the control used it.
    function PressKey(const Key: Word; const Shift: TShiftState = []; const KeyChar: Char = #0): Boolean;
    // Gives the control the focus and presses the key on the form
    function PressKeyOn(const Control: TControl; const Key: Word; const Shift: TShiftState = []; const KeyChar: Char = #0): Boolean;
    // Device pixels of a point in PDF user space of a page; the page must be laid out
    function PagePointToDevice(const PageIndex: Integer; const Point: TPointF): TPoint;
    // The logical position of a device pixel of the form
    function DeviceToLocal(const Point: TPoint): TPointF;
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
    property PageView: TTestPageView read FPageView;
    // The scale of the form: device pixels per logical unit
    property Scale: Single read FScale;
    property Thumbnails: TPdf4DThumbnails read FThumbnails;
    property OutlineView: TPdf4DOutlineView read FOutlineView;
    property SearchBar: TPdf4DSearchBar read FSearchBar;
  end;

implementation

uses
  System.Diagnostics,
  System.Math,
  System.Rtti,
  FMX.Platform,
  FMX.Platform.Win,
  Pdf4D.Render.Skia.Backend,
  Pdf4D.Viewer.PageText,
  Pdf4D.Viewer.Document,
  Pdf4D.FMX.Backend.Skia;

const
  OffDesktopPosition = -30000;
  PollMilliseconds = 5;
  OpenTimeoutMs = 5000;

{ TTestPageView }

constructor TTestPageView.Create(Owner: TComponent);
begin
  inherited Create(Owner);
  FCopiedTexts := TList<string>.Create;
end;

destructor TTestPageView.Destroy;
begin
  FCopiedTexts.Free;
  inherited;
end;

procedure TTestPageView.WriteClipboardText(const Text: string);
begin
  FCopiedTexts.Add(Text);
  inherited;
end;

{ TFmxTestHost }

constructor TFmxTestHost.Create(const ClientWidth, ClientHeight: Integer; const Scale: Single);
begin
  inherited Create;
  FScale := Scale;
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

function TFmxTestHost.AddPageView: TTestPageView;
begin
  FPageView := TTestPageView.Create(FForm);
  FPageView.Parent := FForm;
  FPageView.Align := TAlignLayout.Client;
  FPageView.Document := FDocument;
  Pump(1);
  Result := FPageView;
end;

function TFmxTestHost.AddThumbnails(const Width: Integer): TPdf4DThumbnails;
begin
  FThumbnails := TPdf4DThumbnails.Create(FForm);
  FThumbnails.Parent := FForm;
  FThumbnails.Align := TAlignLayout.Left;
  FThumbnails.Width := Width;
  FThumbnails.Document := FDocument;
  Pump(1);
  Result := FThumbnails;
end;

function TFmxTestHost.AddOutlineView(const Width: Integer): TPdf4DOutlineView;
begin
  FOutlineView := TPdf4DOutlineView.Create(FForm);
  FOutlineView.Parent := FForm;
  FOutlineView.Align := TAlignLayout.Right;
  FOutlineView.Width := Width;
  FOutlineView.Document := FDocument;
  Pump(1);
  Result := FOutlineView;
end;

function TFmxTestHost.AddSearchBar: TPdf4DSearchBar;
begin
  FSearchBar := TPdf4DSearchBar.Create(FForm);
  FSearchBar.Parent := FForm;
  FSearchBar.Align := TAlignLayout.Top;
  FSearchBar.Document := FDocument;
  Pump(1);
  Result := FSearchBar;
end;

procedure TFmxTestHost.ChangeScale(const NewScale: Single);
begin
  const ClientWidth = FForm.ClientWidth;
  const ClientHeight = FForm.ClientHeight;
  FScale := NewScale;
  (FForm.Handle as TWinWindowHandle).SetForcedScaleForForm(NewScale);
  FForm.ClientWidth := ClientWidth;
  FForm.ClientHeight := ClientHeight;
  Pump(1);
end;

function TFmxTestHost.WaitForVisibleTiles: Boolean;
begin
  Result := WaitUntil(
    function: Boolean
    begin
      Result := (FPageView.Controller.PendingTileCount = 0);
    end);
  // The tiles that arrived last are painted by the next paint
  FPageView.Repaint;
  Pump(1);
end;

function TFmxTestHost.WaitForPageText(const PageIndex: Integer): Boolean;
begin
  Result := WaitUntil(
    function: Boolean
    begin
      var PageText: IPdfPageText;
      Result := FDocument.TryGetPageText(PageIndex, PageText);
    end);
end;

function TFmxTestHost.TryGetClipboardText(out Text: string): Boolean;
begin
  Text := '';
  var Service: IFMXClipboardService;
  Result := TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Service);
  if Result then
  begin
    const Value = Service.GetClipboard;
    Result := Value.IsType<string>;
    if Result then
    begin
      Text := Value.AsString;
    end;
  end;
end;

function TFmxTestHost.PutClipboardText(const Text: string): Boolean;
begin
  Result := False;
  var Service: IFMXClipboardService;
  if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Service) then
  begin
    Service.SetClipboard(Text);
    var ReadBack: string;
    Result := TryGetClipboardText(ReadBack) and (ReadBack = Text);
  end;
end;

procedure TFmxTestHost.MouseMove(const Point: TPointF);
begin
  FPageView.HandleMouseMove(Point);
end;

procedure TFmxTestHost.Click(const Point: TPointF);
begin
  FPageView.HandleMouseMove(Point);
  FPageView.HandleMouseDown(Point);
  FPageView.HandleMouseUp(Point);
end;

procedure TFmxTestHost.Drag(const FromPoint, ToPoint: TPointF);
begin
  FPageView.HandleMouseMove(FromPoint);
  FPageView.HandleMouseDown(FromPoint);
  FPageView.HandleMouseMove((FromPoint + ToPoint) / 2);
  FPageView.HandleMouseMove(ToPoint);
  FPageView.HandleMouseUp(ToPoint);
end;

function TFmxTestHost.PressKey(const Key: Word; const Shift: TShiftState; const KeyChar: Char): Boolean;
begin
  var PressedKey := Key;
  var PressedChar := KeyChar;
  FForm.KeyDown(PressedKey, PressedChar, Shift);
  Result := (PressedKey = 0) and (PressedChar = #0);
end;

function TFmxTestHost.PressKeyOn(const Control: TControl; const Key: Word; const Shift: TShiftState; const KeyChar: Char): Boolean;
begin
  Control.SetFocus;
  Result := PressKey(Key, Shift, KeyChar);
end;

function TFmxTestHost.PagePointToDevice(const PageIndex: Integer; const Point: TPointF): TPoint;
begin
  var ViewPoint: TPointF;
  if not FPageView.Controller.TryPageToViewport(PageIndex, Point, ViewPoint) then
  begin
    raise EArgumentException.CreateFmt('Page %d is not laid out', [PageIndex]);
  end;
  Result := TPoint.Create(Round(ViewPoint.X), Round(ViewPoint.Y));
end;

function TFmxTestHost.DeviceToLocal(const Point: TPoint): TPointF;
begin
  Result := TPointF.Create(Point.X / FScale, Point.Y / FScale);
end;

function TFmxTestHost.Snapshot: FMX.Graphics.TBitmap;
begin
  if Assigned(FPageView) then
  begin
    Exit(SnapshotOf(FPageView));
  end;
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
