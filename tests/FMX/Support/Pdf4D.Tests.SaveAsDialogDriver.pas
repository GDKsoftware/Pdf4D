// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.SaveAsDialogDriver;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.SysUtils,
  Winapi.Messages,
  Winapi.Windows;

type
  // A printer that prints to a file (Microsoft Print to PDF) asks for the name of the file in a dialog of its own, in the thread of the
  // program, at the start of the document, and FMX gives no way to name the file. This thread waits for that dialog among the windows of
  // the thread that prints, puts the path in its file name box and presses Save, and keeps watching until that dialog is gone. It sends
  // window messages to the windows of its own process only; no input is synthesised. After the timeout it cancels (IDCANCEL, then WM_CLOSE)
  // every dialog and message box that is still open on that thread, so that a dialog it cannot answer ends the print as a failure and the
  // test fails; without that the thread that prints would wait for the dialog for ever. Thread.Terminate after the job is over ends it
  // without any cancel.
  TSaveAsDialogDriver = class(TThread)
  private
    FFilePath: string;
    FTargetThreadId: Cardinal;
    FTimeoutMs: Integer;
    FIsDialogHandled: Boolean;
    FHandledDialog: HWND;
    FDescription: string;

    function TryFindDialog(out Dialog: HWND): Boolean;
    function TryHandle(const Dialog: HWND): Boolean;
    procedure CancelOpenDialogs;

  protected
    procedure Execute; override;

  public
    // TargetThreadId is the thread that prints (the main thread of the test program)
    constructor Create(const FilePath: string; const TargetThreadId: Cardinal; const TimeoutMs: Integer);

    // True when a dialog was found and Save was pressed
    property IsDialogHandled: Boolean read FIsDialogHandled;
    // What the thread did or saw, for the message of a failing test
    property Description: string read FDescription;
  end;

implementation

const
  DialogClassName = '#32770';
  EditClassName = 'Edit';
  PollMs = 50;
  SendTimeoutMs = 2000;
  SaveButtonId = IDOK;
  CancelPasses = 5;
  CancelWaitMs = 200;

type
  TFindState = record
    Edit: HWND;
    Dialog: HWND;
  end;
  PFindState = ^TFindState;

function ClassNameOf(const Window: HWND): string;
begin
  var Buffer: array[0..255] of Char;
  const Length = GetClassName(Window, Buffer, Length(Buffer));
  SetString(Result, Buffer, Length);
end;

function CollectEdit(Window: HWND; Param: LPARAM): BOOL; stdcall;
begin
  const State = PFindState(Param);
  Result := True;
  if (State.Edit = 0) and IsWindowVisible(Window) and SameText(ClassNameOf(Window), EditClassName) then
  begin
    State.Edit := Window;
    Result := False;
  end;
end;

function CollectDialog(Window: HWND; Param: LPARAM): BOOL; stdcall;
begin
  const State = PFindState(Param);
  Result := True;
  if IsWindowVisible(Window) and SameText(ClassNameOf(Window), DialogClassName) then
  begin
    State.Dialog := Window;
    Result := False;
  end;
end;

{ TSaveAsDialogDriver }

constructor TSaveAsDialogDriver.Create(const FilePath: string; const TargetThreadId: Cardinal; const TimeoutMs: Integer);
begin
  inherited Create(False);
  FFilePath := FilePath;
  FTargetThreadId := TargetThreadId;
  FTimeoutMs := TimeoutMs;
  FDescription := 'no dialog was seen';
end;

function TSaveAsDialogDriver.TryFindDialog(out Dialog: HWND): Boolean;
begin
  var State: TFindState;
  State.Edit := 0;
  State.Dialog := 0;
  EnumThreadWindows(FTargetThreadId, @CollectDialog, LPARAM(@State));
  Dialog := State.Dialog;
  Result := (Dialog <> 0);
end;

function TSaveAsDialogDriver.TryHandle(const Dialog: HWND): Boolean;
begin
  var State: TFindState;
  State.Edit := 0;
  State.Dialog := Dialog;
  EnumChildWindows(Dialog, @CollectEdit, LPARAM(@State));

  const SaveButton = GetDlgItem(Dialog, SaveButtonId);
  const IsReady = (State.Edit <> 0) and (SaveButton <> 0);
  if not IsReady then
  begin
    FDescription := Format('a dialog was seen but it has no file name box or no Save button (edit %d, button %d)', [State.Edit, SaveButton]);
    Exit(False);
  end;

  var SendResult: DWORD_PTR := 0;
  const IsTextSet = SendMessageTimeout(State.Edit, WM_SETTEXT, 0, LPARAM(PChar(FFilePath)), SMTO_ABORTIFHUNG, SendTimeoutMs, @SendResult) <> 0;
  if not IsTextSet then
  begin
    FDescription := 'the dialog did not take the file name';
    Exit(False);
  end;

  // Posted, so that a second dialog (to overwrite a file) cannot block this thread
  PostMessage(SaveButton, BM_CLICK, 0, 0);
  FDescription := 'Save was pressed';
  Result := True;
end;

procedure TSaveAsDialogDriver.CancelOpenDialogs;
begin
  for var Pass := 1 to CancelPasses do
  begin
    var Dialog: HWND;
    if not TryFindDialog(Dialog) then
    begin
      Exit;
    end;

    FDescription := FDescription + '; the dialog that was still open was cancelled';
    PostMessage(Dialog, WM_COMMAND, IDCANCEL, 0);
    PostMessage(Dialog, WM_CLOSE, 0, 0);
    Sleep(CancelWaitMs);
  end;
end;

procedure TSaveAsDialogDriver.Execute;
begin
  const Started = GetTickCount64;
  while (not Terminated) and (GetTickCount64 - Started < Cardinal(FTimeoutMs)) do
  begin
    if not FIsDialogHandled then
    begin
      var Dialog: HWND;
      if TryFindDialog(Dialog) and TryHandle(Dialog) then
      begin
        FIsDialogHandled := True;
        FHandledDialog := Dialog;
      end;
    end
    else if not IsWindow(FHandledDialog) then
    begin
      // The dialog took the name and closed: the document goes on without this thread
      Exit;
    end;
    Sleep(PollMs);
  end;

  if not Terminated then
  begin
    FDescription := FDescription + ' (timed out)';
    CancelOpenDialogs;
  end;
end;

end.
