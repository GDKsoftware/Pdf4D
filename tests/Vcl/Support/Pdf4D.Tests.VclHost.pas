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
  Pdf4D.Viewer.Types,
  Pdf4D.Vcl.Document,
  Pdf4D.Vcl.PageView,
  Pdf4D.Vcl.Thumbnails,
  Pdf4D.Vcl.OutlineView,
  Pdf4D.Vcl.SearchBar;

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
    FOpenErrorMessage: string;

    procedure HandleOpenError(Sender: TObject; const Kind: TPdfOpenErrorKind; const Message: string);
    procedure Send(const Control: TWinControl; const Message: Cardinal; const WParam: NativeUInt; const X, Y: Integer);

  public
    // A form of 96 PPI whose client area is ClientWidth x ClientHeight, with a document that renders with Skia
    constructor Create(const ClientWidth, ClientHeight: Integer);
    destructor Destroy; override;

    // The document renders with Skia by default; without a backend Open raises EPdfViewerException
    procedure RemoveBackend;
    procedure RestoreBackend;
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
    // A click with the left button on another control
    procedure ClickOn(const Control: TWinControl; const X, Y: Integer);

    // Put thumbnails, an outline view or a search bar next to the page view, linked to the document of the host
    function AddThumbnails(const Width: Integer): TPdf4DThumbnails;
    function AddOutlineView(const Width: Integer): TPdf4DOutlineView;
    function AddSearchBar: TPdf4DSearchBar;

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
  System.Hash,
  Vcl.Clipbrd,
  Winapi.Windows,
  Winapi.Messages,
  Pdf4D.Render.Skia.Backend,
  Pdf4D.Crypto.RC4,
  Pdf4D.Viewer.PageText,
  Pdf4D.Tests.PdfBuilder,
  Pdf4D.Model.Tests.Support;

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
    Control.Perform(WM_KEYDOWN, Key, 0);
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
const
  PasswordPadding: array[0..31] of Byte = ($28, $BF, $4E, $5E, $4E, $75, $8A, $41, $64, $00, $4E, $56, $FF, $FA, $01, $08,
                                           $2E, $2E, $00, $B6, $D0, $68, $3E, $80, $2F, $0C, $A9, $FE, $64, $53, $69, $7A);
  // Bits 3 (print) and 5 (copy) are cleared from the default of all permissions
  Permissions = -24;
  KeyLength = 16;
  AdditionalKeyRounds = 50;
  AdditionalUserRounds = 19;
  OwnerEntry = $11;
  DocumentIdByte = $42;
  PageContent = 'BT /F1 12 Tf 100 700 Td (Factuur 2024-0815) Tj 0 -20 Td (Nummer: 2024-0815) Tj ET';

  function Md5Of(const Data: TBytes): TBytes;
  begin
    const Hash = THashMD5.Create;
    Hash.Update(Data);
    Result := Hash.HashAsBytes;
  end;

  function ToHex(const Data: TBytes): string;
  begin
    Result := '';
    for var Value in Data do
    begin
      Result := Result + IntToHex(Value, 2);
    end;
  end;

begin
  var Padding: TBytes;
  SetLength(Padding, Length(PasswordPadding));
  Move(PasswordPadding[0], Padding[0], Length(PasswordPadding));

  var OwnerKey: TBytes;
  SetLength(OwnerKey, 32);
  FillChar(OwnerKey[0], Length(OwnerKey), OwnerEntry);

  var DocumentId: TBytes;
  SetLength(DocumentId, 16);
  FillChar(DocumentId[0], Length(DocumentId), DocumentIdByte);

  // Algorithm 2 of ISO 32000-1 for an empty user password, revision 4
  var Permission := Permissions;
  var PermissionBytes: TBytes;
  SetLength(PermissionBytes, SizeOf(Permission));
  Move(Permission, PermissionBytes[0], SizeOf(Permission));
  var Key := Md5Of(Padding + OwnerKey + PermissionBytes + DocumentId);
  for var Pass := 1 to AdditionalKeyRounds do
  begin
    Key := Md5Of(Copy(Key, 0, KeyLength));
  end;
  Key := Copy(Key, 0, KeyLength);

  // Algorithm 5: the user entry
  var UserEntry := TRC4Cipher.Process(Key, Md5Of(Padding + DocumentId));
  for var Pass := 1 to AdditionalUserRounds do
  begin
    var RoundKey := Copy(Key, 0, Length(Key));
    for var Index := 0 to High(RoundKey) do
    begin
      RoundKey[Index] := RoundKey[Index] xor Byte(Pass);
    end;
    UserEntry := TRC4Cipher.Process(RoundKey, UserEntry);
  end;
  SetLength(UserEntry, 32);

  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  try
    Builder.AddObject(3, '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 10 0 R >> >> >>');
    Builder.AddStreamObject(4, '', TEncoding.ASCII.GetBytes(PageContent));
    Builder.AddObject(10, '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>');
    Builder.AddObject(20, Format('<< /Filter /Standard /V 4 /R 4 /Length 128 /CF << /StdCF << /CFM /AESV2 /AuthEvent /DocOpen /Length 16 >> >> ' +
                                 '/StmF /Identity /StrF /Identity /O <%s> /U <%s> /P %d >>', [ToHex(OwnerKey), ToHex(UserEntry), Permissions]));
    Builder.TrailerExtra := Format('/Encrypt 20 0 R /ID [<%s> <%s>]', [ToHex(DocumentId), ToHex(DocumentId)]);
    Result := Builder.Build(TXrefStyle.Table);
  finally
    Builder.Free;
  end;
end;

end.
