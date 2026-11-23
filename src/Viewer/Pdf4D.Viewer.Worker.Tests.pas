// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.Worker.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.SysUtils,
  System.SyncObjs,
  System.Diagnostics,
  DUnitX.TestFramework,
  Pdf4D.Common.Defines,
  Pdf4D.Render.Renderer.Interfaces,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.Dispatcher,
  Pdf4D.Viewer.Worker;

type
  // What the jobs of a test report, from the worker thread, and what the test thread waits for
  TJobLog = class
  private
    FLock: TObject;
    FChanged: TEvent;
    FRelease: TEvent;
    FStarted: TEvent;
    FExecuted: TStringList;
    FFreed: Integer;

    function FreedCount: Integer;
    function ExecutedNames: string;
    // Waits until Condition holds (checked under the lock); False after TimeoutMs
    function WaitUntil(const Condition: TFunc<Boolean>; const TimeoutMs: Integer): Boolean;

  public
    constructor Create;
    destructor Destroy; override;

    procedure AddExecuted(const Name: string);
    procedure AddFreed;
    function WaitForExecuted(const Count, TimeoutMs: Integer): Boolean;
    function WaitForFreed(const Count, TimeoutMs: Integer): Boolean;
    // Holds a blocker job until the test opens the gate
    property Gate: TEvent read FRelease;
    // Set by a blocker job when it runs
    property Started: TEvent read FStarted;
  end;

  TLoggedJob = class(TPdfWorkerJob)
  private
    FLog: TJobLog;

  protected
    property JobLog: TJobLog read FLog;

  public
    constructor Create(const Log: TJobLog; const Priority: TPdfJobPriority);
    destructor Destroy; override;
  end;

  TRecordingJob = class(TLoggedJob)
  private
    FName: string;

  public
    constructor Create(const Log: TJobLog; const Priority: TPdfJobPriority; const Name: string);
    procedure Execute(const Cancel: IPdfCancelToken); override;
  end;

  // Runs until the test releases it or the job is cancelled
  TBlockerJob = class(TLoggedJob)
  public
    constructor Create(const Log: TJobLog);
    procedure Execute(const Cancel: IPdfCancelToken); override;
  end;

  // Signals Started and waits for its cancellation; records what it saw
  TWatchingJob = class(TLoggedJob)
  public
    constructor Create(const Log: TJobLog);
    procedure Execute(const Cancel: IPdfCancelToken); override;
  end;

  TFailingJob = class(TLoggedJob)
  private
    FFailureClass: ExceptClass;

  public
    constructor Create(const Log: TJobLog; const FailureClass: ExceptClass);
    procedure Execute(const Cancel: IPdfCancelToken); override;
  end;

  [TestFixture]
  TPdfDocumentWorkerTests = class
  private
    FLog: TJobLog;
    FWorker: TPdfDocumentWorker;

    // Runs a blocker job and returns when the worker is busy with it
    procedure BlockWorker;
    procedure AssertExecuted(const Count: Integer);
    procedure AssertFreed(const Count: Integer);

  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestJobsRunInPriorityOrder;
    [Test]
    procedure TestCancelledJobIsSkipped;
    [Test]
    procedure TestCancelAllWhileRunningSetsToken;
    [Test]
    procedure TestCancelAllSkipsQueuedJobs;
    [Test]
    procedure TestStopFreesPendingJobs;
    [Test]
    procedure TestEnqueueAfterStopFreesTheJob;
    [Test]
    procedure TestExceptionInJobDoesNotKillWorker;
    [Test]
    procedure TestFatalExceptionStopsExecution;
    [Test]
    procedure TestEndProcRunsOnTheWorkerThreadAfterStop;
    [Test]
    procedure TestEndProcRunsAfterAFatalException;
  end;

  [TestFixture]
  TPdfDispatcherTests = class
  public
    [Test]
    procedure TestQueueDispatcherRunsOnMainThread;
    [Test]
    procedure TestManualDispatcherRunsInPostingOrder;
    [Test]
    procedure TestManualDispatcherRunUntilTimesOut;
    [Test]
    procedure TestManualDispatcherRunsPostsFromAnotherThread;
  end;

implementation

uses
  Pdf4D.Tests.ManualDispatcher;

const
  // Upper bound for every wait; a test that reaches it fails with a message
  WaitMs = 10000;
  PollMs = 2;

{ TJobLog }

constructor TJobLog.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FChanged := TEvent.Create(nil, True, False, '');
  FRelease := TEvent.Create(nil, True, False, '');
  FStarted := TEvent.Create(nil, True, False, '');
  FExecuted := TStringList.Create;
end;

destructor TJobLog.Destroy;
begin
  FExecuted.Free;
  FStarted.Free;
  FRelease.Free;
  FChanged.Free;
  FLock.Free;
  inherited;
end;

procedure TJobLog.AddExecuted(const Name: string);
begin
  TMonitor.Enter(FLock);
  try
    FExecuted.Add(Name);
  finally
    TMonitor.Exit(FLock);
  end;

  FChanged.SetEvent;
end;

procedure TJobLog.AddFreed;
begin
  TMonitor.Enter(FLock);
  try
    Inc(FFreed);
  finally
    TMonitor.Exit(FLock);
  end;

  FChanged.SetEvent;
end;

function TJobLog.FreedCount: Integer;
begin
  Result := FFreed;
end;

function TJobLog.ExecutedNames: string;
begin
  TMonitor.Enter(FLock);
  try
    Result := FExecuted.CommaText;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TJobLog.WaitUntil(const Condition: TFunc<Boolean>; const TimeoutMs: Integer): Boolean;
begin
  const Watch = TStopwatch.StartNew;

  repeat
    TMonitor.Enter(FLock);
    try
      Result := Condition();
      if not Result then
      begin
        // Reset under the lock that the writers change under: a change after this check sets the event again
        FChanged.ResetEvent;
      end;
    finally
      TMonitor.Exit(FLock);
    end;

    if Result then
    begin
      Exit;
    end;

    const RemainingMs = TimeoutMs - Watch.ElapsedMilliseconds;
    if RemainingMs > 0 then
    begin
      FChanged.WaitFor(Cardinal(RemainingMs));
    end;
  until (Watch.ElapsedMilliseconds >= TimeoutMs);
end;

function TJobLog.WaitForExecuted(const Count, TimeoutMs: Integer): Boolean;
begin
  Result := WaitUntil(
    function: Boolean
    begin
      Result := (FExecuted.Count >= Count);
    end,
    TimeoutMs);
end;

function TJobLog.WaitForFreed(const Count, TimeoutMs: Integer): Boolean;
begin
  Result := WaitUntil(
    function: Boolean
    begin
      Result := (FFreed >= Count);
    end,
    TimeoutMs);
end;

{ TLoggedJob }

constructor TLoggedJob.Create(const Log: TJobLog; const Priority: TPdfJobPriority);
begin
  inherited Create(Priority);
  FLog := Log;
end;

destructor TLoggedJob.Destroy;
begin
  FLog.AddFreed;
  inherited;
end;

{ TRecordingJob }

constructor TRecordingJob.Create(const Log: TJobLog; const Priority: TPdfJobPriority; const Name: string);
begin
  inherited Create(Log, Priority);
  FName := Name;
end;

procedure TRecordingJob.Execute(const Cancel: IPdfCancelToken);
begin
  JobLog.AddExecuted(FName);
end;

{ TBlockerJob }

constructor TBlockerJob.Create(const Log: TJobLog);
begin
  inherited Create(Log, TPdfJobPriority.Open);
end;

procedure TBlockerJob.Execute(const Cancel: IPdfCancelToken);
begin
  JobLog.Started.SetEvent;

  const Watch = TStopwatch.StartNew;
  var Released := False;
  while (not Released) and (not Cancel.IsCancelled) and (Watch.ElapsedMilliseconds < WaitMs) do
  begin
    Released := (JobLog.Gate.WaitFor(PollMs) = wrSignaled);
  end;
end;

{ TWatchingJob }

constructor TWatchingJob.Create(const Log: TJobLog);
begin
  inherited Create(Log, TPdfJobPriority.Visible);
end;

procedure TWatchingJob.Execute(const Cancel: IPdfCancelToken);
begin
  JobLog.Started.SetEvent;

  const Watch = TStopwatch.StartNew;
  while (not Cancel.IsCancelled) and (Watch.ElapsedMilliseconds < WaitMs) do
  begin
    JobLog.Gate.WaitFor(PollMs);
  end;

  if Cancel.IsCancelled then
  begin
    JobLog.AddExecuted('saw-cancel');
  end
  else
  begin
    JobLog.AddExecuted('timed-out');
  end;
end;

{ TFailingJob }

constructor TFailingJob.Create(const Log: TJobLog; const FailureClass: ExceptClass);
begin
  inherited Create(Log, TPdfJobPriority.Visible);
  FFailureClass := FailureClass;
end;

procedure TFailingJob.Execute(const Cancel: IPdfCancelToken);
begin
  JobLog.AddExecuted('failing');
  raise FFailureClass.Create('Raised by a test job');
end;

{ TPdfDocumentWorkerTests }

procedure TPdfDocumentWorkerTests.Setup;
begin
  FLog := TJobLog.Create;
  FWorker := TPdfDocumentWorker.Create;
end;

procedure TPdfDocumentWorkerTests.TearDown;
begin
  // Let a blocker go, so that Stop does not depend on its time limit
  FLog.Gate.SetEvent;
  FWorker.Free;
  FLog.Free;
end;

procedure TPdfDocumentWorkerTests.BlockWorker;
begin
  FWorker.Enqueue(TBlockerJob.Create(FLog));
  Assert.AreEqual<TWaitResult>(wrSignaled, FLog.Started.WaitFor(WaitMs), 'The worker did not start the blocker job');
end;

procedure TPdfDocumentWorkerTests.AssertExecuted(const Count: Integer);
begin
  Assert.IsTrue(FLog.WaitForExecuted(Count, WaitMs), Format('Expected %d executed jobs, got: %s', [Count, FLog.ExecutedNames]));
end;

procedure TPdfDocumentWorkerTests.AssertFreed(const Count: Integer);
begin
  Assert.IsTrue(FLog.WaitForFreed(Count, WaitMs), Format('Expected %d freed jobs, got %d', [Count, FLog.FreedCount]));
end;

procedure TPdfDocumentWorkerTests.TestJobsRunInPriorityOrder;
begin
  BlockWorker;
  FWorker.Enqueue(TRecordingJob.Create(FLog, TPdfJobPriority.Search, 'Search'));
  FWorker.Enqueue(TRecordingJob.Create(FLog, TPdfJobPriority.Visible, 'Visible1'));
  FWorker.Enqueue(TRecordingJob.Create(FLog, TPdfJobPriority.Prefetch, 'Prefetch'));
  FWorker.Enqueue(TRecordingJob.Create(FLog, TPdfJobPriority.Visible, 'Visible2'));

  FLog.Gate.SetEvent;

  AssertExecuted(4);
  Assert.AreEqual('Visible1,Visible2,Prefetch,Search', FLog.ExecutedNames);
end;

procedure TPdfDocumentWorkerTests.TestCancelledJobIsSkipped;
begin
  BlockWorker;
  const Skipped = TRecordingJob.Create(FLog, TPdfJobPriority.Visible, 'Skipped');
  FWorker.Enqueue(Skipped);
  FWorker.Enqueue(TRecordingJob.Create(FLog, TPdfJobPriority.Visible, 'Last'));
  // The blocker keeps the worker busy, so the skipped job is still in the queue
  Skipped.Cancel.Cancel;

  FLog.Gate.SetEvent;

  AssertExecuted(1);
  Assert.AreEqual('Last', FLog.ExecutedNames);
  // The blocker, the skipped job and the last job
  AssertFreed(3);
end;

procedure TPdfDocumentWorkerTests.TestCancelAllWhileRunningSetsToken;
begin
  FWorker.Enqueue(TWatchingJob.Create(FLog));
  Assert.AreEqual<TWaitResult>(wrSignaled, FLog.Started.WaitFor(WaitMs), 'The worker did not start the job');

  FWorker.CancelAll;

  AssertExecuted(1);
  Assert.AreEqual('saw-cancel', FLog.ExecutedNames);
end;

procedure TPdfDocumentWorkerTests.TestCancelAllSkipsQueuedJobs;
begin
  BlockWorker;
  FWorker.Enqueue(TRecordingJob.Create(FLog, TPdfJobPriority.Visible, 'Queued1'));
  FWorker.Enqueue(TRecordingJob.Create(FLog, TPdfJobPriority.Prefetch, 'Queued2'));

  FWorker.CancelAll;

  // The blocker ends because of its cancellation; both queued jobs are freed without running
  AssertFreed(3);
  Assert.AreEqual('', FLog.ExecutedNames);
end;

procedure TPdfDocumentWorkerTests.TestStopFreesPendingJobs;
begin
  BlockWorker;
  for var Index := 1 to 10 do
  begin
    FWorker.Enqueue(TRecordingJob.Create(FLog, TPdfJobPriority.Visible, 'Pending'));
  end;

  const Watch = TStopwatch.StartNew;
  FWorker.Stop;

  Assert.IsTrue(Watch.ElapsedMilliseconds < 1000, Format('Stop took %d ms', [Watch.ElapsedMilliseconds]));
  Assert.AreEqual('', FLog.ExecutedNames);
  // The blocker and the ten pending jobs
  Assert.AreEqual(11, FLog.FreedCount);
end;

procedure TPdfDocumentWorkerTests.TestEnqueueAfterStopFreesTheJob;
begin
  FWorker.Stop;

  FWorker.Enqueue(TRecordingJob.Create(FLog, TPdfJobPriority.Visible, 'Late'));

  Assert.AreEqual(1, FLog.FreedCount);
  Assert.AreEqual('', FLog.ExecutedNames);
end;

procedure TPdfDocumentWorkerTests.TestExceptionInJobDoesNotKillWorker;
begin
  FWorker.Enqueue(TFailingJob.Create(FLog, EPdfParseException));
  FWorker.Enqueue(TRecordingJob.Create(FLog, TPdfJobPriority.Visible, 'Next'));

  AssertExecuted(2);
  Assert.AreEqual('failing,Next', FLog.ExecutedNames);
  AssertFreed(2);
end;

procedure TPdfDocumentWorkerTests.TestFatalExceptionStopsExecution;
begin
  BlockWorker;
  FWorker.Enqueue(TFailingJob.Create(FLog, EAccessViolation));
  FWorker.Enqueue(TRecordingJob.Create(FLog, TPdfJobPriority.Visible, 'After1'));
  FWorker.Enqueue(TRecordingJob.Create(FLog, TPdfJobPriority.Visible, 'After2'));
  FLog.Gate.SetEvent;

  // The blocker, the failing job and both jobs that follow it
  AssertFreed(4);
  FWorker.Enqueue(TRecordingJob.Create(FLog, TPdfJobPriority.Visible, 'After3'));
  AssertFreed(5);
  Assert.AreEqual('failing', FLog.ExecutedNames);
end;

procedure TPdfDocumentWorkerTests.TestEndProcRunsOnTheWorkerThreadAfterStop;
begin
  var EndThread: TThreadID := 0;
  var Calls := 0;
  const Worker = TPdfDocumentWorker.Create(
    procedure
    begin
      EndThread := TThread.CurrentThread.ThreadID;
      Inc(Calls);
    end);
  try
    Worker.Stop;

    // Stop waits for the thread, so the procedure has run
    Assert.AreEqual(1, Calls);
    Assert.AreNotEqual(TThreadID(0), EndThread);
    Assert.AreNotEqual(MainThreadID, EndThread);
  finally
    Worker.Free;
  end;
  Assert.AreEqual(1, Calls);
end;

procedure TPdfDocumentWorkerTests.TestEndProcRunsAfterAFatalException;
begin
  var Calls := 0;
  const Worker = TPdfDocumentWorker.Create(
    procedure
    begin
      Inc(Calls);
      raise EInvalidOperation.Create('The end procedure fails');
    end);
  try
    Worker.Enqueue(TFailingJob.Create(FLog, EAccessViolation));
    AssertFreed(1);
    Worker.Stop;

    // The failure of the end procedure does not escape the thread
    Assert.AreEqual(1, Calls);
  finally
    Worker.Free;
  end;
end;

{ TPdfDispatcherTests }

procedure TPdfDispatcherTests.TestQueueDispatcherRunsOnMainThread;
begin
  const Dispatcher: IPdfViewerDispatcher = TPdfQueueDispatcher.Create;
  var RanOnThread: TThreadID := 0;
  var Ran := False;

  const Poster = TThread.CreateAnonymousThread(
    procedure
    begin
      Dispatcher.Post(
        procedure
        begin
          RanOnThread := TThread.CurrentThread.ThreadID;
          Ran := True;
        end);
    end);
  Poster.FreeOnTerminate := False;
  try
    Poster.Start;
    const Watch = TStopwatch.StartNew;
    while (not Ran) and (Watch.ElapsedMilliseconds < WaitMs) do
    begin
      CheckSynchronize(PollMs);
    end;
    Poster.WaitFor;
  finally
    Poster.Free;
  end;

  Assert.IsTrue(Ran, 'The posted procedure did not run after CheckSynchronize');
  Assert.AreEqual<TThreadID>(MainThreadID, RanOnThread);
end;

procedure TPdfDispatcherTests.TestManualDispatcherRunsInPostingOrder;
begin
  const Manual = TManualDispatcher.Create;
  const Dispatcher: IPdfViewerDispatcher = Manual;
  var Order := '';
  Dispatcher.Post(
    procedure
    begin
      Order := Order + 'a';
    end);
  Dispatcher.Post(
    procedure
    begin
      Order := Order + 'b';
    end);

  Assert.AreEqual('', Order);
  Assert.AreEqual(2, Manual.RunPending);
  Assert.AreEqual('ab', Order);
  Assert.AreEqual(0, Manual.RunPending);
end;

procedure TPdfDispatcherTests.TestManualDispatcherRunUntilTimesOut;
begin
  const Manual = TManualDispatcher.Create;
  const Dispatcher: IPdfViewerDispatcher = Manual;

  const Reached = Manual.RunUntil(
    function: Boolean
    begin
      Result := False;
    end,
    20);

  Assert.IsFalse(Reached);
  Assert.IsNotNull(Dispatcher);
end;

procedure TPdfDispatcherTests.TestManualDispatcherRunsPostsFromAnotherThread;
begin
  const Manual = TManualDispatcher.Create;
  const Dispatcher: IPdfViewerDispatcher = Manual;
  var Ran := False;

  const Poster = TThread.CreateAnonymousThread(
    procedure
    begin
      Dispatcher.Post(
        procedure
        begin
          Ran := True;
        end);
    end);
  Poster.FreeOnTerminate := False;
  try
    Poster.Start;
    const Reached = Manual.RunUntil(
      function: Boolean
      begin
        Result := Ran;
      end,
      WaitMs);
    Poster.WaitFor;

    Assert.IsTrue(Reached, 'The procedure posted by the thread did not run');
  finally
    Poster.Free;
  end;
end;

end.
