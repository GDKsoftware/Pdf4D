// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.ManualDispatcher;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  Pdf4D.Viewer.Dispatcher;

type
  // A dispatcher for tests: the test thread plays the UI thread and decides when the posted procedures run
  TManualDispatcher = class(TInterfacedObject, IPdfViewerDispatcher)
  private
    FLock: TObject;
    FPosted: TEvent;
    FQueue: TQueue<TProc>;

    function TakeNext(out Proc: TProc): Boolean;

  public
    constructor Create;
    destructor Destroy; override;

    // Thread safe
    procedure Post(const Proc: TProc);
    // Runs what is posted now and what these procedures post meanwhile; returns the number of procedures that ran
    function RunPending: Integer;
    // Runs posted procedures until Condition is True; False when it is still False after TimeoutMs
    function RunUntil(const Condition: TFunc<Boolean>; const TimeoutMs: Integer): Boolean;
  end;

implementation

uses
  System.Math,
  System.Diagnostics;

const
  // The longest wait between two checks of the condition, for a condition that another thread changes without posting
  CheckIntervalMs = 5;

{ TManualDispatcher }

constructor TManualDispatcher.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FPosted := TEvent.Create(nil, True, False, '');
  FQueue := TQueue<TProc>.Create;
end;

destructor TManualDispatcher.Destroy;
begin
  FQueue.Free;
  FPosted.Free;
  FLock.Free;
  inherited;
end;

procedure TManualDispatcher.Post(const Proc: TProc);
begin
  TMonitor.Enter(FLock);
  try
    FQueue.Enqueue(Proc);
  finally
    TMonitor.Exit(FLock);
  end;

  FPosted.SetEvent;
end;

function TManualDispatcher.TakeNext(out Proc: TProc): Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := (FQueue.Count > 0);
    if Result then
    begin
      Proc := FQueue.Dequeue();
    end
    else
    begin
      Proc := nil;
      FPosted.ResetEvent;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TManualDispatcher.RunPending: Integer;
begin
  Result := 0;

  var Proc: TProc;
  while TakeNext(Proc) do
  begin
    Proc();
    Inc(Result);
  end;
end;

function TManualDispatcher.RunUntil(const Condition: TFunc<Boolean>; const TimeoutMs: Integer): Boolean;
begin
  const Watch = TStopwatch.StartNew;

  repeat
    RunPending;
    Result := Condition();
    if Result then
    begin
      Exit;
    end;

    const RemainingMs = TimeoutMs - Watch.ElapsedMilliseconds;
    if RemainingMs > 0 then
    begin
      FPosted.WaitFor(Cardinal(Min(RemainingMs, CheckIntervalMs)));
    end;
  until (Watch.ElapsedMilliseconds >= TimeoutMs);

  RunPending;
  Result := Condition();
end;

end.
