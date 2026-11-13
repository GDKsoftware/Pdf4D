// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Common.SharedInstance.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  DUnitX.TestFramework,
  Pdf4D.Common.SharedInstance;

type
  ETestFactoryFailure = class(Exception);

  // Counts how many are made and freed
  TTrackedObject = class
  public
    class var Created: Integer;
    class var Freed: Integer;

    constructor Create;
    destructor Destroy; override;

    class procedure ResetCounters; static;
  end;

  TTrackedInstance = TPdfSharedInstance<TTrackedObject>;
  TTrackedCache = TPdfSharedCache<string, TTrackedObject>;

  // The pattern as the production code uses it: a class var and a class destructor, nothing at start up
  TSharedCacheOwner = class
  private
    class var FCache: TPdfSharedInstance<TTrackedCache>;

    class destructor Destroy;
  public
    class function Cache: TTrackedCache; static;
  end;

  // Waits for the start signal and then runs the body
  TTestWorker = class(TThread)
  private
    FStartSignal: TEvent;
    FBody: TProc<Integer>;
    FIndex: Integer;
    FFailure: string;

  protected
    procedure Execute; override;

  public
    constructor Create(const StartSignal: TEvent; const Body: TProc<Integer>; const Index: Integer);

    property Failure: string read FFailure;
  end;

  [TestFixture]
  TSharedInstanceTests = class
  private
    // Runs Body on ThreadCount threads that all start at the same moment. The first failure is raised afterwards.
    class procedure RunConcurrently(const ThreadCount: Integer; const Body: TProc<Integer>); static;
    // Blocks until ThreadCount threads have arrived, so all of them are inside a factory at the same time
    class procedure WaitForAllThreads(var Arrived: Integer; const ThreadCount: Integer); static;

  public
    [Setup]
    procedure Setup;

    [Test]
    procedure TestSharedInstanceCreatedOnceUnderContention;

    [Test]
    procedure TestEveryThreadMakesACandidateAndOneSurvives;

    [Test]
    procedure TestFactoryExceptionPublishesNothing;

    [Test]
    procedure TestNilFromFactoryRaises;

    [Test]
    procedure TestSharedCacheKeepsFirstValue;

    [Test]
    procedure TestSharedCacheUnderContention;

    [Test]
    procedure TestSharedCacheTryGetAndDestructorFreesValues;

    [Test]
    procedure TestClassVarOwnerGivesTheSameCache;
  end;

implementation

{ TTrackedObject }

constructor TTrackedObject.Create;
begin
  inherited Create;
  TInterlocked.Increment(Created);
end;

destructor TTrackedObject.Destroy;
begin
  TInterlocked.Increment(Freed);
  inherited;
end;

class procedure TTrackedObject.ResetCounters;
begin
  Created := 0;
  Freed := 0;
end;

{ TSharedCacheOwner }

class destructor TSharedCacheOwner.Destroy;
begin
  FCache.Release;
end;

class function TSharedCacheOwner.Cache: TTrackedCache;
begin
  Result := FCache.Get(
    function: TTrackedCache
    begin
      Result := TTrackedCache.Create;
    end);
end;

{ TTestWorker }

constructor TTestWorker.Create(const StartSignal: TEvent; const Body: TProc<Integer>; const Index: Integer);
begin
  inherited Create(False);
  FStartSignal := StartSignal;
  FBody := Body;
  FIndex := Index;
end;

procedure TTestWorker.Execute;
begin
  FStartSignal.WaitFor(INFINITE);
  try
    FBody(FIndex);
  except
    on Caught: Exception do
    begin
      FFailure := Caught.ClassName + ': ' + Caught.Message;
    end;
  end;
end;

{ TSharedInstanceTests }

procedure TSharedInstanceTests.Setup;
begin
  TTrackedObject.ResetCounters;
end;

class procedure TSharedInstanceTests.WaitForAllThreads(var Arrived: Integer; const ThreadCount: Integer);
begin
  TInterlocked.Increment(Arrived);
  const Deadline = TThread.GetTickCount64 + 10000;
  while (TInterlocked.CompareExchange(Arrived, 0, 0) < ThreadCount) and (TThread.GetTickCount64 < Deadline) do
  begin
    TThread.Yield;
  end;
end;

class procedure TSharedInstanceTests.RunConcurrently(const ThreadCount: Integer; const Body: TProc<Integer>);
begin
  const StartSignal = TEvent.Create(nil, True, False, '');
  var Workers: TArray<TTestWorker>;
  SetLength(Workers, ThreadCount);
  try
    for var Index := 0 to ThreadCount - 1 do
    begin
      Workers[Index] := TTestWorker.Create(StartSignal, Body, Index);
    end;

    StartSignal.SetEvent;
    var Failure := '';
    for var Worker in Workers do
    begin
      Worker.WaitFor;
      Failure := Failure + Worker.Failure;
    end;
    Assert.AreEqual('', Failure);
  finally
    for var Worker in Workers do
    begin
      Worker.Free;
    end;
    StartSignal.Free;
  end;
end;

procedure TSharedInstanceTests.TestSharedInstanceCreatedOnceUnderContention;
begin
  const ThreadCount = 8;
  const Rounds = 200;
  for var Round := 1 to Rounds do
  begin
    var Shared: TTrackedInstance;
    Shared := Default(TTrackedInstance);
    var Results: TArray<TObject>;
    SetLength(Results, ThreadCount);
    TTrackedObject.ResetCounters;

    RunConcurrently(ThreadCount,
      procedure(Index: Integer)
      begin
        Results[Index] := Shared.Get(
          function: TTrackedObject
          begin
            Result := TTrackedObject.Create;
          end);
      end);

    for var Index := 1 to ThreadCount - 1 do
    begin
      Assert.AreSame(Results[0], Results[Index]);
    end;
    Assert.IsTrue(TTrackedObject.Created >= 1);
    Assert.AreEqual(TTrackedObject.Created - 1, TTrackedObject.Freed, 'Every loser is freed, the winner stays');

    Shared.Release;
    Assert.AreEqual(TTrackedObject.Created, TTrackedObject.Freed, 'Release frees the published instance');
  end;
end;

procedure TSharedInstanceTests.TestEveryThreadMakesACandidateAndOneSurvives;
begin
  // The factories wait for each other, so every thread has made a candidate before any of them can publish
  const ThreadCount = 8;
  var Shared: TTrackedInstance;
  Shared := Default(TTrackedInstance);
  var Arrived := 0;
  var Results: TArray<TObject>;
  SetLength(Results, ThreadCount);

  RunConcurrently(ThreadCount,
    procedure(Index: Integer)
    begin
      Results[Index] := Shared.Get(
        function: TTrackedObject
        begin
          WaitForAllThreads(Arrived, ThreadCount);
          Result := TTrackedObject.Create;
        end);
    end);

  Assert.AreEqual(ThreadCount, TTrackedObject.Created, 'All threads raced with a candidate');
  Assert.AreEqual(ThreadCount - 1, TTrackedObject.Freed);
  for var Index := 1 to ThreadCount - 1 do
  begin
    Assert.AreSame(Results[0], Results[Index]);
  end;
  Shared.Release;
  Assert.AreEqual(ThreadCount, TTrackedObject.Freed);
end;

procedure TSharedInstanceTests.TestFactoryExceptionPublishesNothing;
begin
  var Shared: TTrackedInstance;
  Shared := Default(TTrackedInstance);

  Assert.WillRaise(
    procedure
    begin
      Shared.Get(
        function: TTrackedObject
        begin
          raise ETestFactoryFailure.Create('factory failed');
        end);
    end,
    ETestFactoryFailure);

  const Instance = Shared.Get(
    function: TTrackedObject
    begin
      Result := TTrackedObject.Create;
    end);
  Assert.IsNotNull(Instance);
  Assert.AreEqual(1, TTrackedObject.Created);
  Shared.Release;
  Assert.AreEqual(1, TTrackedObject.Freed);
end;

procedure TSharedInstanceTests.TestNilFromFactoryRaises;
begin
  var Shared: TTrackedInstance;
  Shared := Default(TTrackedInstance);

  Assert.WillRaise(
    procedure
    begin
      Shared.Get(
        function: TTrackedObject
        begin
          Result := nil;
        end);
    end,
    EArgumentException);
end;

procedure TSharedInstanceTests.TestSharedCacheKeepsFirstValue;
begin
  const Cache = TTrackedCache.Create;
  try
    const Factory: TFunc<string, TTrackedObject> =
      function(Key: string): TTrackedObject
      begin
        Result := TTrackedObject.Create;
      end;

    const First = Cache.GetOrAdd('a', Factory);
    const Second = Cache.GetOrAdd('a', Factory);

    Assert.AreSame(First, Second);
    Assert.AreEqual(1, TTrackedObject.Created, 'The second lookup finds the value without a factory call');
  finally
    Cache.Free;
  end;
  Assert.AreEqual(1, TTrackedObject.Freed);
end;

procedure TSharedInstanceTests.TestSharedCacheUnderContention;
begin
  const ThreadCount = 8;
  const Cache = TTrackedCache.Create;
  try
    var Arrived := 0;
    var Results: TArray<TObject>;
    SetLength(Results, ThreadCount);

    RunConcurrently(ThreadCount,
      procedure(Index: Integer)
      begin
        Results[Index] := Cache.GetOrAdd('key',
          function(Key: string): TTrackedObject
          begin
            WaitForAllThreads(Arrived, ThreadCount);
            Result := TTrackedObject.Create;
          end);
      end);

    for var Index := 1 to ThreadCount - 1 do
    begin
      Assert.AreSame(Results[0], Results[Index]);
    end;
    Assert.AreEqual(ThreadCount, TTrackedObject.Created);
    Assert.AreEqual(ThreadCount - 1, TTrackedObject.Freed);
  finally
    Cache.Free;
  end;
  Assert.AreEqual(ThreadCount, TTrackedObject.Freed);
end;

procedure TSharedInstanceTests.TestSharedCacheTryGetAndDestructorFreesValues;
begin
  const Cache = TTrackedCache.Create;
  try
    var Value: TTrackedObject;
    Assert.IsFalse(Cache.TryGet('missing', Value));

    const Added = Cache.GetOrAdd('b',
      function(Key: string): TTrackedObject
      begin
        Result := TTrackedObject.Create;
      end);

    Assert.IsTrue(Cache.TryGet('b', Value));
    Assert.AreSame(Added, Value);
  finally
    Cache.Free;
  end;
  Assert.AreEqual(1, TTrackedObject.Freed);
end;

procedure TSharedInstanceTests.TestClassVarOwnerGivesTheSameCache;
begin
  // The value stays in the cache until the class destructor runs at shutdown, which must not count as a leak
  const Factory: TFunc<string, TTrackedObject> =
    function(Key: string): TTrackedObject
    begin
      Result := TTrackedObject.Create;
    end;

  const First = TSharedCacheOwner.Cache.GetOrAdd('owner', Factory);
  const Second = TSharedCacheOwner.Cache.GetOrAdd('owner', Factory);

  Assert.AreSame(TSharedCacheOwner.Cache, TSharedCacheOwner.Cache);
  Assert.AreSame(First, Second);
end;

end.
