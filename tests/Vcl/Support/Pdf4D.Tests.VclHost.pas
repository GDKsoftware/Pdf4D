// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.VclHost;

{$EXCESSPRECISION OFF}
{$POINTERMATH ON}

interface

uses
  System.Classes,
  System.Types,
  System.SysUtils,
  System.Generics.Collections,
  System.UITypes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Graphics,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Viewer.Types,
  Pdf4D.Vcl.Document,
  Pdf4D.Vcl.PageView,
  Pdf4D.Vcl.Thumbnails,
  Pdf4D.Vcl.OutlineView,
  Pdf4D.Vcl.SearchBar,
  Pdf4D.Vcl.Toolbar;

type
  TVclPixel = record
    R, G, B: Byte;
  end;

  // The page view of the tests: it remembers what was copied and does not fail when the session does not give access to the
  // clipboard of the window system
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

  // Follows the zoom of a page view as the toolbar does, and lets go of it in the free notification. It records how many zoom listeners
  // the page view had at that moment: the list has to be alive while the page view tells the others that it goes.
  TZoomListenerProbe = class(TComponent)
  private
    FPageView: TPdf4DPageView;
    FListenerCountAtRemoval: Integer;

    procedure HandleZoomChanged(Sender: TObject);

  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;

  public
    constructor Create(const PageView: TPdf4DPageView); reintroduce;
    destructor Destroy; override;

    // -1 until the page view was freed
    property ListenerCountAtRemoval: Integer read FListenerCountAtRemoval;
  end;

  // A form with a document and a page view, made in the test process. Input goes through Perform, so that no desktop session tool is
  // needed, and the form is shown outside the visible desktop.
  TVclTestHost = class
  private
    FForm: TForm;
    FDocument: TPdf4DDocument;
    FPageView: TTestPageView;
    FThumbnails: TPdf4DThumbnails;
    FOutlineView: TPdf4DOutlineView;
    FSearchBar: TPdf4DSearchBar;
    FToolbar: TPdf4DToolbar;
    FOpenErrorMessage: string;

    procedure HandleOpenError(Sender: TObject; const Kind: TPdfOpenErrorKind; const Message: string);
    procedure Send(const Control: TWinControl; const Message: Cardinal; const WParam: NativeUInt; const X, Y: Integer);
    // The result of the message
    function SendKey(const Control: TWinControl; const Message: Cardinal; const Key: Word; const Shift: TShiftState): NativeInt;

  public
    // A form of 96 PPI whose client area is ClientWidth x ClientHeight, with a document that renders with Skia
    constructor Create(const ClientWidth, ClientHeight: Integer);
    destructor Destroy; override;

    // The document renders with Skia by default; without a backend Open raises EPdfViewerException
    procedure RemoveBackend;
    procedure RestoreBackend;
    // The render backend of the tests, for a second document
    class function NewRenderBackend: IPdfRenderBackend; static;
    // Whether the test process may use the clipboard of the window system; some sessions refuse it
    function IsClipboardAvailable: Boolean;
    // The message of the last failed open
    function OpenErrorMessage: string;
    // Waits until the document is Open or Failed, at most 5 seconds
    function Open(const Data: TBytes): Boolean;
    // Handles the queue of the main thread and the window messages until Condition holds
    function WaitUntil(const Condition: TFunc<Boolean>; const TimeoutMs: Integer = 5000): Boolean;
    // Until the controller has no tiles outstanding
    function WaitForVisibleTiles: Boolean;
    // Until the text of the page is in the cache of the document
    function WaitForPageText(const PageIndex: Integer): Boolean;
    // Handles what is queued for a while, for tests that wait for something that must not happen
    procedure Pump(const Milliseconds: Integer);

    procedure MouseMove(const X, Y: Integer);
    procedure Click(const X, Y: Integer);
    procedure Drag(const FromX, FromY, ToX, ToY: Integer);
    // A key down message; Ctrl makes the control see the Ctrl key as pressed
    procedure PressKey(const Key: Word; const Ctrl: Boolean = False);
    // The same for another control; the keys of Shift are seen as pressed
    procedure PressKeyOn(const Control: TWinControl; const Key: Word; const Shift: TShiftState = []);
    // The key as the message loop gives it to the form to find a shortcut among its actions: the control tells its form first. True when
    // a shortcut took the key, so that the control does not get it.
    function PressShortCutOn(const Control: TWinControl; const Key: Word; const Shift: TShiftState): Boolean;
    // A click with the left button on another control
    procedure ClickOn(const Control: TWinControl; const X, Y: Integer);

    // Put thumbnails, an outline view or a search bar next to the page view, linked to the document of the host
    function AddThumbnails(const Width: Integer): TPdf4DThumbnails;
    function AddOutlineView(const Width: Integer): TPdf4DOutlineView;
    function AddSearchBar: TPdf4DSearchBar;
    // A toolbar at the top, linked to the document, the page view and the search bar if there is one
    function AddToolbar: TPdf4DToolbar;
    // The client pixels of the middle of an occurrence of a word of the page text; the page must be laid out
    function CenterOfWord(const PageIndex: Integer; const Text: string; const Occurrence: Integer = 0): TPoint;

    // What the page view paints; the caller owns the bitmap
    function Snapshot: Vcl.Graphics.TBitmap;
    // What any control paints
    function SnapshotOf(const Control: TWinControl): Vcl.Graphics.TBitmap;
    // The pixel of a bitmap of 24 bits
    class function PixelAt(const Bitmap: Vcl.Graphics.TBitmap; const X, Y: Integer): TVclPixel; static;
    // Client pixels of a point in PDF user space of a page; the page must be laid out
    function PagePointToClient(const PageIndex: Integer; const Point: TPointF): TPoint;

    property Form: TForm read FForm;
    property Document: TPdf4DDocument read FDocument;
    property PageView: TTestPageView read FPageView;
    property Thumbnails: TPdf4DThumbnails read FThumbnails;
    property OutlineView: TPdf4DOutlineView read FOutlineView;
    property SearchBar: TPdf4DSearchBar read FSearchBar;
    property Toolbar: TPdf4DToolbar read FToolbar;
  end;

  // Documents that only the tests of the VCL components need
  TVclTestDocuments = class
  public
    // The first page of the invoice, protected so that the user may neither print nor copy; the content is not encrypted
    class function Restricted: TBytes; static;
  end;

implementation

uses
  System.Diagnostics,
  Vcl.Clipbrd,
  Winapi.Windows,
  Winapi.Messages,
  Pdf4D.Render.Skia.Backend,
  Pdf4D.Viewer.PageText,
  Pdf4D.Tests.RestrictedDocument;

const
  OffDesktopPosition = -30000;
  PollMilliseconds = 5;
  OpenTimeoutMs = 5000;
  ClipboardProbe = 'clipboard probe';
  LogicalPixelsPerInch = 96;
  BytesPerPixel24 = 3;

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
  try
    inherited;
  except
    on EClipboardException do
    begin
      // The session does not allow it; IsClipboardAvailable tells the tests
    end;
  end;
end;

{ TZoomListenerProbe }

constructor TZoomListenerProbe.Create(const PageView: TPdf4DPageView);
begin
  inherited Create(nil);
  FListenerCountAtRemoval := -1;
  FPageView := PageView;
  FPageView.FreeNotification(Self);
  FPageView.AddZoomListener(HandleZoomChanged);
end;

destructor TZoomListenerProbe.Destroy;
begin
  if Assigned(FPageView) then
  begin
    FPageView.RemoveZoomListener(HandleZoomChanged);
    FPageView.RemoveFreeNotification(Self);
  end;
  inherited;
end;

procedure TZoomListenerProbe.HandleZoomChanged(Sender: TObject);
begin
  // Only the registration matters
end;

procedure TZoomListenerProbe.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = TOperation.opRemove) and (AComponent = FPageView) then
  begin
    FListenerCountAtRemoval := FPageView.ZoomListenerCount;
    FPageView.RemoveZoomListener(HandleZoomChanged);
    FPageView := nil;
  end;
end;

{ TVclTestHost }

constructor TVclTestHost.Create(const ClientWidth, ClientHeight: Integer);
begin
  inherited Create;
  FForm := TForm.CreateNew(nil);
  FForm.PixelsPerInch := LogicalPixelsPerInch;
  FForm.Position := TPosition.poDesigned;
  FForm.Left := OffDesktopPosition;
  FForm.Top := OffDesktopPosition;
  FForm.ClientWidth := ClientWidth;
  FForm.ClientHeight := ClientHeight;

  FDocument := TPdf4DDocument.Create(FForm);
  FDocument.OnOpenError := HandleOpenError;
  RestoreBackend;

  FPageView := TTestPageView.Create(FForm);
  FPageView.Parent := FForm;
  FPageView.Align := TAlign.alClient;
  FPageView.Document := FDocument;

  FForm.Show;
  Pump(1);
end;

destructor TVclTestHost.Destroy;
begin
  FForm.Free;
  inherited;
end;

function TVclTestHost.IsClipboardAvailable: Boolean;
begin
  try
    Clipboard.AsText := ClipboardProbe;
    Result := (Clipboard.AsText = ClipboardProbe);
  except
    on EClipboardException do
    begin
      Result := False;
    end;
  end;
end;

procedure TVclTestHost.HandleOpenError(Sender: TObject; const Kind: TPdfOpenErrorKind; const Message: string);
begin
  FOpenErrorMessage := Message;
end;

function TVclTestHost.OpenErrorMessage: string;
begin
  Result := FOpenErrorMessage;
end;

procedure TVclTestHost.RemoveBackend;
begin
  FDocument.RenderBackend := nil;
end;

class function TVclTestHost.NewRenderBackend: IPdfRenderBackend;
begin
  Result := TPdfSkiaBackend.Create;
end;

procedure TVclTestHost.RestoreBackend;
begin
  FDocument.RenderBackend := TPdfSkiaBackend.Create;
end;

procedure TVclTestHost.Pump(const Milliseconds: Integer);
begin
  const Watch = TStopwatch.StartNew;
  repeat
    CheckSynchronize(PollMilliseconds);
    Application.ProcessMessages;
  until Watch.ElapsedMilliseconds >= Milliseconds;
end;

function TVclTestHost.WaitUntil(const Condition: TFunc<Boolean>; const TimeoutMs: Integer): Boolean;
begin
  const Watch = TStopwatch.StartNew;
  repeat
    CheckSynchronize(PollMilliseconds);
    Application.ProcessMessages;
    Result := Condition();
  until Result or (Watch.ElapsedMilliseconds >= TimeoutMs);
end;

function TVclTestHost.Open(const Data: TBytes): Boolean;
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

function TVclTestHost.WaitForVisibleTiles: Boolean;
begin
  Result := WaitUntil(
    function: Boolean
    begin
      Result := (FPageView.Controller.PendingTileCount = 0);
    end);
  // The tiles that arrived last are painted by the next paint message
  Pump(1);
end;

function TVclTestHost.WaitForPageText(const PageIndex: Integer): Boolean;
begin
  Result := WaitUntil(
    function: Boolean
    begin
      var PageText: IPdfPageText;
      Result := FDocument.TryGetPageText(PageIndex, PageText);
    end);
end;

procedure TVclTestHost.Send(const Control: TWinControl; const Message: Cardinal; const WParam: NativeUInt; const X, Y: Integer);
begin
  Control.Perform(Message, WParam, MakeLong(Word(X), Word(Y)));
end;

procedure TVclTestHost.MouseMove(const X, Y: Integer);
begin
  Send(FPageView, WM_MOUSEMOVE, 0, X, Y);
end;

procedure TVclTestHost.Click(const X, Y: Integer);
begin
  ClickOn(FPageView, X, Y);
end;

procedure TVclTestHost.ClickOn(const Control: TWinControl; const X, Y: Integer);
begin
  Send(Control, WM_MOUSEMOVE, 0, X, Y);
  Send(Control, WM_LBUTTONDOWN, MK_LBUTTON, X, Y);
  Send(Control, WM_LBUTTONUP, 0, X, Y);
end;

procedure TVclTestHost.Drag(const FromX, FromY, ToX, ToY: Integer);
begin
  Send(FPageView, WM_MOUSEMOVE, 0, FromX, FromY);
  Send(FPageView, WM_LBUTTONDOWN, MK_LBUTTON, FromX, FromY);
  Send(FPageView, WM_MOUSEMOVE, MK_LBUTTON, (FromX + ToX) div 2, (FromY + ToY) div 2);
  Send(FPageView, WM_MOUSEMOVE, MK_LBUTTON, ToX, ToY);
  Send(FPageView, WM_LBUTTONUP, 0, ToX, ToY);
end;

procedure TVclTestHost.PressKey(const Key: Word; const Ctrl: Boolean);
begin
  if Ctrl then
  begin
    PressKeyOn(FPageView, Key, [ssCtrl]);
  end
  else
  begin
    PressKeyOn(FPageView, Key);
  end;
end;

procedure TVclTestHost.PressKeyOn(const Control: TWinControl; const Key: Word; const Shift: TShiftState);
begin
  SendKey(Control, WM_KEYDOWN, Key, Shift);
end;

function TVclTestHost.PressShortCutOn(const Control: TWinControl; const Key: Word; const Shift: TShiftState): Boolean;
begin
  Result := (SendKey(Control, CN_KEYDOWN, Key, Shift) <> 0);
end;

function TVclTestHost.SendKey(const Control: TWinControl; const Message: Cardinal; const Key: Word; const Shift: TShiftState): NativeInt;
begin
  var State: TKeyboardState;
  GetKeyboardState(State);
  var Saved := State;

  if ssCtrl in Shift then
  begin
    State[VK_CONTROL] := $80;
  end;
  if ssShift in Shift then
  begin
    State[VK_SHIFT] := $80;
  end;
  SetKeyboardState(State);

  try
    Result := Control.Perform(Message, Key, 0);
  finally
    SetKeyboardState(Saved);
  end;
end;

function TVclTestHost.AddThumbnails(const Width: Integer): TPdf4DThumbnails;
begin
  FThumbnails := TPdf4DThumbnails.Create(FForm);
  FThumbnails.Parent := FForm;
  FThumbnails.Align := TAlign.alLeft;
  FThumbnails.Width := Width;
  FThumbnails.Document := FDocument;
  Pump(1);
  Result := FThumbnails;
end;

function TVclTestHost.AddOutlineView(const Width: Integer): TPdf4DOutlineView;
begin
  FOutlineView := TPdf4DOutlineView.Create(FForm);
  FOutlineView.Parent := FForm;
  FOutlineView.Align := TAlign.alRight;
  FOutlineView.Width := Width;
  FOutlineView.Document := FDocument;
  Pump(1);
  Result := FOutlineView;
end;

function TVclTestHost.AddSearchBar: TPdf4DSearchBar;
begin
  FSearchBar := TPdf4DSearchBar.Create(FForm);
  FSearchBar.Parent := FForm;
  FSearchBar.Align := TAlign.alTop;
  FSearchBar.Document := FDocument;
  Pump(1);
  Result := FSearchBar;
end;

function TVclTestHost.AddToolbar: TPdf4DToolbar;
begin
  FToolbar := TPdf4DToolbar.Create(FForm);
  FToolbar.Parent := FForm;
  FToolbar.Align := TAlign.alTop;
  FToolbar.Document := FDocument;
  FToolbar.PageView := FPageView;
  FToolbar.SearchBar := FSearchBar;
  Pump(1);
  Result := FToolbar;
end;

function TVclTestHost.CenterOfWord(const PageIndex: Integer; const Text: string; const Occurrence: Integer): TPoint;
begin
  var PageText: IPdfPageText;
  if not FDocument.TryGetPageText(PageIndex, PageText) then
  begin
    raise EArgumentException.CreateFmt('The text of page %d is not known', [PageIndex]);
  end;

  var Seen := 0;
  for var Word in PageText.Words do
  begin
    if (Word.Text = Text) and (Seen < Occurrence) then
    begin
      Inc(Seen);
    end
    else if Word.Text = Text then
    begin
      var Sum := TPoint.Zero;
      var Count := 0;
      for var Quad in Word.Quads do
      begin
        for var Corner in [Quad.P1, Quad.P2, Quad.P3, Quad.P4] do
        begin
          const Point = PagePointToClient(PageIndex, Corner);
          Inc(Sum.X, Point.X);
          Inc(Sum.Y, Point.Y);
          Inc(Count);
        end;
      end;
      Exit(TPoint.Create(Sum.X div Count, Sum.Y div Count));
    end;
  end;
  raise EArgumentException.CreateFmt('The word %s is not on page %d', [Text, PageIndex]);
end;

function TVclTestHost.Snapshot: Vcl.Graphics.TBitmap;
begin
  Result := SnapshotOf(FPageView);
end;

class function TVclTestHost.PixelAt(const Bitmap: Vcl.Graphics.TBitmap; const X, Y: Integer): TVclPixel;
begin
  const Line = PByte(Bitmap.ScanLine[Y]) + X * BytesPerPixel24;
  Result.B := Line[0];
  Result.G := Line[1];
  Result.R := Line[2];
end;

function TVclTestHost.SnapshotOf(const Control: TWinControl): Vcl.Graphics.TBitmap;
begin
  Result := Vcl.Graphics.TBitmap.Create;
  try
    Result.PixelFormat := pf24bit;
    Result.SetSize(Control.ClientWidth, Control.ClientHeight);
    Control.PaintTo(Result.Canvas, 0, 0);
  except
    Result.Free;
    raise;
  end;
end;

function TVclTestHost.PagePointToClient(const PageIndex: Integer; const Point: TPointF): TPoint;
begin
  var ViewPoint: TPointF;
  if not FPageView.Controller.TryPageToViewport(PageIndex, Point, ViewPoint) then
  begin
    raise EArgumentException.CreateFmt('Page %d is not laid out', [PageIndex]);
  end;
  Result := TPoint.Create(Round(ViewPoint.X), Round(ViewPoint.Y));
end;

{ TVclTestDocuments }

class function TVclTestDocuments.Restricted: TBytes;
begin
  Result := TRestrictedDocument.Build;
end;

end.
