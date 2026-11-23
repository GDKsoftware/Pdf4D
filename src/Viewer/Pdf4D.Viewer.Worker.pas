// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.Worker;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  Pdf4D.Render.Renderer.Interfaces,
  Pdf4D.Render.CancelToken,
  Pdf4D.Viewer.Types;

type
{$SCOPEDENUMS ON}
  // What a worker tells its owner, on the worker thread, about something that it cannot handle itself
  TPdfWorkerReportKind = (JobFatal, AbandonFailed, EndProcedureFailed);
{$SCOPEDENUMS OFF}

  TPdfWorkerReportEvent = reference to procedure(const Kind: TPdfWorkerReportKind; const Message: string);

  // One unit of work for the worker thread. The job owns its cancel token; the worker passes it to Execute.
  TPdfWorkerJob = class abstract
  private
    FPriority: TPdfJobPriority;
    FCancel: TPdfCancelToken;
    FCancelIntf: IPdfCancelToken;

  public
    constructor Create(const Priority: TPdfJobPriority);

    // Runs on the worker thread
    procedure Execute(const Cancel: IPdfCancelToken); virtual; abstract;
    // Runs on the worker thread instead of Execute when the worker is in its failed state: tell whoever waits for the result that it
    // will not come
    procedure Abandon; virtual;

    property Priority: TPdfJobPriority read FPriority;
    // Thread safe
    property Cancel: TPdfCancelToken read FCancel;
  end;

  // The one thread of a document. Jobs run one at a time, the most urgent first and first in first out within one priority.
  // An exception in a job is swallowed, except a fatal one (see TPdfFailure.IsFatal): that is reported and puts the worker in a failed
  // state, in which it hands every job that was queued, and every job that comes, to Abandon instead of Execute.
  TPdfDocumentWorker = class(TThread)
  private
    FLock: TObject;
    FWake: TEvent;
    FQueue: TList<TPdfWorkerJob>;
    FRunning: TPdfWorkerJob;
    FFailed: Boolean;
    FStopped: Boolean;
    FOnEnd: TProc;
    FOnReport: TPdfWorkerReportEvent;
    FReportFailure: Exception;

    // Waits for a job and takes it out of the queue; nil when the thread must end
    function TakeNext: TPdfWorkerJob;
    function IndexOfMostUrgent: Integer;
    function IsStopped: Boolean;
    procedure Run(const Job: TPdfWorkerJob);
    procedure RunKeepingFailure(const Job: TPdfWorkerJob);
    procedure AbandonJob(const Job: TPdfWorkerJob);
    procedure RunEndProc;
    procedure Report(const Kind: TPdfWorkerReportKind; const Message: string);

  protected
    procedure Execute; override;

  public
    constructor Create; overload;
    // OnEnd runs on the worker thread when it ends (after Stop), also when a fatal exception put the worker in its failed state. The
    // owner of the document releases it there, on the thread that uses it. An exception in OnEnd goes to OnReport.
    constructor Create(const OnEnd: TProc); overload;
    // OnReport is called on the worker thread: with the message of a fatal job exception, and with the message of an exception that
    // Abandon or OnEnd raised, because nobody else is left to hear it.
    constructor Create(const OnEnd: TProc; const OnReport: TPdfWorkerReportEvent); overload;
    destructor Destroy; override;

    // Takes ownership of Job; from any thread. After Stop the job is freed unexecuted.
    procedure Enqueue(const Job: TPdfWorkerJob);
    // Cancels the running job and every job in the queue
    procedure CancelAll;
    // Not on the worker thread. Cancels all, ends the thread and waits for it; jobs that have not started are freed unexecuted
    procedure Stop;
    // Thread safe; true after a fatal exception in a job. An exception that OnReport raised ends the thread and stays in FatalException
    function IsFailed: Boolean;
  end;

implementation

uses
  Pdf4D.Common.Defines;

{ TPdfWorkerJob }

constructor TPdfWorkerJob.Create(const Priority: TPdfJobPriority);
begin
  inherited Create;
  FPriority := Priority;
  FCancel := TPdfCancelToken.Create;
  // The interface reference owns the token
  FCancelIntf := FCancel;
end;

procedure TPdfWorkerJob.Abandon;
begin
  // Nobody waits for the result of a plain job
  Exit;
end;

{ TPdfDocumentWorker }

constructor TPdfDocumentWorker.Create;
begin
  Create(nil, nil);
end;

constructor TPdfDocumentWorker.Create(const OnEnd: TProc);
begin
  Create(OnEnd, nil);
end;

constructor TPdfDocumentWorker.Create(const OnEnd: TProc; const OnReport: TPdfWorkerReportEvent);
begin
  // Everything the thread uses exists before it starts
  FOnEnd := OnEnd;
  FOnReport := OnReport;
  FLock := TObject.Create;
  FWake := TEvent.Create(nil, True, False, '');
  FQueue := TList<TPdfWorkerJob>.Create;
  inherited Create(False);
end;

destructor TPdfDocumentWorker.Destroy;
begin
  Stop;
  // Only set when Execute did not get to raise it
  FReportFailure.Free;
  FQueue.Free;
  FWake.Free;
  FLock.Free;
  inherited;
end;

procedure TPdfDocumentWorker.Enqueue(const Job: TPdfWorkerJob);
begin
  var Accepted: Boolean;

  TMonitor.Enter(FLock);
  try
    Accepted := (not FStopped);
    if Accepted then
    begin
      FQueue.Add(Job);
    end;
  finally
    TMonitor.Exit(FLock);
  end;

  if Accepted then
  begin
    FWake.SetEvent;
  end
  else
  begin
    Job.Free;
  end;
end;

procedure TPdfDocumentWorker.CancelAll;
begin
  TMonitor.Enter(FLock);
  try
    for var Job in FQueue do
    begin
      Job.Cancel.Cancel;
    end;

    if Assigned(FRunning) then
    begin
      FRunning.Cancel.Cancel;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TPdfDocumentWorker.Stop;
begin
  // WaitFor on the own thread would wait for itself
  if TThread.CurrentThread.ThreadID = ThreadID then
  begin
    raise EInvalidOpException.Create('Stop cannot run on the worker thread');
  end;

  var Pending: TArray<TPdfWorkerJob>;

  TMonitor.Enter(FLock);
  try
    FStopped := True;
  finally
    TMonitor.Exit(FLock);
  end;

  CancelAll;
  // Not Terminate: a thread that is terminated before it starts never runs Execute, and with it never runs the end procedure
  FWake.SetEvent;
  WaitFor;

  // The thread has ended, so nothing else touches the queue
  TMonitor.Enter(FLock);
  try
    Pending := FQueue.ToArray;
    FQueue.Clear;
  finally
    TMonitor.Exit(FLock);
  end;

  for var Job in Pending do
  begin
    Job.Free;
  end;
end;

function TPdfDocumentWorker.IsFailed: Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := FFailed;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TPdfDocumentWorker.IsStopped: Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := FStopped;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TPdfDocumentWorker.IndexOfMostUrgent: Integer;
begin
  Result := -1;

  for var Index := 0 to FQueue.Count - 1 do
  begin
    // Strictly lower only: a job that was queued earlier wins a tie
    const IsMoreUrgent = ((Result < 0) or (Ord(FQueue[Index].Priority) < Ord(FQueue[Result].Priority)));
    if IsMoreUrgent then
    begin
      Result := Index;
    end;
  end;
end;

function TPdfDocumentWorker.TakeNext: TPdfWorkerJob;
begin
  Result := nil;

  while (not IsStopped) and (not Assigned(Result)) do
  begin
    TMonitor.Enter(FLock);
    try
      const Index = IndexOfMostUrgent;
      if Index >= 0 then
      begin
        Result := FQueue[Index];
        FQueue.Delete(Index);
        FRunning := Result;
      end
      else
      begin
        // Reset under the lock that Enqueue adds under: a job that arrives after this check sets the event again
        FWake.ResetEvent;
      end;
    finally
      TMonitor.Exit(FLock);
    end;

    if not Assigned(Result) then
    begin
      FWake.WaitFor(INFINITE);
    end;
  end;
end;

procedure TPdfDocumentWorker.Report(const Kind: TPdfWorkerReportKind; const Message: string);
begin
  if Assigned(FOnReport) then
  begin
    FOnReport(Kind, Message);
  end;
end;

procedure TPdfDocumentWorker.AbandonJob(const Job: TPdfWorkerJob);
begin
  try
    Job.Abandon;
  except
    on Failure: Exception do
    begin
      Report(TPdfWorkerReportKind.AbandonFailed, Failure.Message);
    end;
  end;
end;

procedure TPdfDocumentWorker.Run(const Job: TPdfWorkerJob);
begin
  if IsStopped then
  begin
    Exit;
  end;

  if IsFailed then
  begin
    AbandonJob(Job);
    Exit;
  end;

  if Job.Cancel.IsCancelled then
  begin
    Exit;
  end;

  try
    Job.Execute(Job.Cancel);
  except
    on Failure: Exception do
    begin
      if TPdfFailure.IsFatal(Failure) then
      begin
        TMonitor.Enter(FLock);
        try
          FFailed := True;
        finally
          TMonitor.Exit(FLock);
        end;
        Report(TPdfWorkerReportKind.JobFatal, Failure.Message);
      end;
    end;
  end;
end;

procedure TPdfDocumentWorker.Execute;
begin
  // The end procedure releases the document on this thread, so it runs even when the loop raises
  try
    while not IsStopped do
    begin
      const Job = TakeNext;
      if not Assigned(Job) then
      begin
        Break;
      end;

      try
        RunKeepingFailure(Job);
      finally
        TMonitor.Enter(FLock);
        try
          FRunning := nil;
        finally
          TMonitor.Exit(FLock);
        end;
        Job.Free;
      end;
    end;
  finally
    RunEndProc;
  end;

  // What a report callback raised is left to the owner of the thread: it stays in FatalException
  if Assigned(FReportFailure) then
  begin
    const Failure = FReportFailure;
    FReportFailure := nil;
    raise Failure;
  end;
end;

procedure TPdfDocumentWorker.RunKeepingFailure(const Job: TPdfWorkerJob);
begin
  // Only OnReport can raise out of Run. The worker keeps working, so that every queued job still gets its Abandon, and the first
  // exception ends the thread afterwards
  try
    Run(Job);
  except
    on Failure: Exception do
    begin
      if Assigned(FReportFailure) then
      begin
        // One exception is enough to end the thread; the later ones are the same callback failing again
        Exit;
      end;
      FReportFailure := Exception(AcquireExceptionObject);
    end;
  end;
end;

procedure TPdfDocumentWorker.RunEndProc;
begin
  if not Assigned(FOnEnd) then
  begin
    Exit;
  end;

  try
    FOnEnd();
  except
    on Failure: Exception do
    begin
      Report(TPdfWorkerReportKind.EndProcedureFailed, Failure.Message);
    end;
  end;
end;

end.
