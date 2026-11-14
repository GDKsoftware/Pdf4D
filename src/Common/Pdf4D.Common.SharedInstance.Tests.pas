// Copyright 2026 GDK Software
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

  // What every thread of one race does. The shared objects are fields, so no anonymous method that runs on another
  // thread captures an inline declaration of the test (a known problem of the Delphi 13 Win64 compiler).
  TRaceScenario = class
  private
    FThreadCount: Integer;
    FWaitForAll: Boolean;
    FArrived: Integer;
    FResults: TArray<TObject>;

    function GetResult(const Index: Integer): TObject;
  protected
    // Blocks until all threads have arrived, so all of them are inside a factory at the same time
    procedure WaitInFactory;
  public
    constructor Create(const ThreadCount: Integer; const WaitForAll: Boolean);

    procedure Run(const Index: Integer); virtual; abstract;

    property ThreadCount: Integer read FThreadCount;
    property Results[const Index: Integer]: TObject read GetResult;
  end;

  TInstanceRace = class(TRaceScenario)
  private
    FShared: TTrackedInstance;
  public
    procedure Run(const Index: Integer); override;
    procedure Release;
  end;

  TCacheRace = class(TRaceScenario)
  private
    FCache: TTrackedCache;
  public
    constructor Create(const Cache: TTrackedCache; const ThreadCount: Integer; const WaitForAll: Boolean);

    procedure Run(const Index: Integer); override;
  end;

  // Waits for the start signal and then runs its part of the scenario
  TTestWorker = class(TThread)
  private
    FStartSignal: TEvent;
    FScenario: TRaceScenario;
    FIndex: Integer;
    FFailure: string;

  protected
    procedure Execute; override;

  public
    constructor Create(const StartSignal: TEvent; const Scenario: TRaceScenario; const Index: Integer);

    property Failure: string read FFailure;
  end;

  [TestFixture]
  TSharedInstanceTests = class
  private
    // Runs the scenario on its ThreadCount threads that all start at the same moment. A failure is raised afterwards.
    class procedure RunConcurrently(const Scenario: TRaceScenario); static;

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
    procedure TestSharedCacheNilFromFactoryRaises;

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

{ TRaceScenario }

constructor TRaceScenario.Create(const ThreadCount: Integer; const WaitForAll: Boolean);
begin
  inherited Create;
  FThreadCount := ThreadCount;
  FWaitForAll := WaitForAll;
  SetLength(FResults, ThreadCount);
end;

function TRaceScenario.GetResult(const Index: Integer): TObject;
begin
  Result := FResults[Index];
end;

procedure TRaceScenario.WaitInFactory;
begin
  if not FWaitForAll then
  begin
    Exit;
  end;

  TInterlocked.Increment(FArrived);
  const Deadline = TThread.GetTickCount64 + 10000;
  while (TInterlocked.CompareExchange(FArrived, 0, 0) < FThreadCount) and (TThread.GetTickCount64 < Deadline) do
  begin
    TThread.Yield;
  end;
end;

{ TInstanceRace }

procedure TInstanceRace.Run(const Index: Integer);
begin
  FResults[Index] := FShared.Get(
    function: TTrackedObject
    begin
      WaitInFactory;
      Result := TTrackedObject.Create;
    end);
end;

procedure TInstanceRace.Release;
begin
  FShared.Release;
end;

{ TCacheRace }

constructor TCacheRace.Create(const Cache: TTrackedCache; const ThreadCount: Integer; const WaitForAll: Boolean);
begin
  inherited Create(ThreadCount, WaitForAll);
  FCache := Cache;
end;

procedure TCacheRace.Run(const Index: Integer);
begin
  FResults[Index] := FCache.GetOrAdd('key',
    function(Key: string): TTrackedObject
    begin
      WaitInFactory;
      Result := TTrackedObject.Create;
    end);
end;

{ TTestWorker }

constructor TTestWorker.Create(const StartSignal: TEvent; const Scenario: TRaceScenario; const Index: Integer);
begin
  inherited Create(False);
  FStartSignal := StartSignal;
  FScenario := Scenario;
  FIndex := Index;
end;

procedure TTestWorker.Execute;
begin
  FStartSignal.WaitFor(INFINITE);
  try
    FScenario.Run(FIndex);
  except
    on Caught: Exception do
    begin
      FFailure := Format('%s: %s', [Caught.ClassName, Caught.Message]);
    end;
  end;
end;

{ TSharedInstanceTests }

procedure TSharedInstanceTests.Setup;
begin
  TTrackedObject.ResetCounters;
end;

class procedure TSharedInstanceTests.RunConcurrently(const Scenario: TRaceScenario);
begin
  const StartSignal = TEvent.Create(nil, True, False, '');
  var Workers: TArray<TTestWorker>;
  SetLength(Workers, Scenario.ThreadCount);
  try
    for var Index := 0 to Scenario.ThreadCount - 1 do
    begin
      Workers[Index] := TTestWorker.Create(StartSignal, Scenario, Index);
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
    TTrackedObject.ResetCounters;
    const Race = TInstanceRace.Create(ThreadCount, False);
    try
      RunConcurrently(Race);

      for var Index := 1 to ThreadCount - 1 do
      begin
        Assert.AreSame(Race.Results[0], Race.Results[Index]);
      end;
      Assert.IsTrue(TTrackedObject.Created >= 1);
      Assert.AreEqual(TTrackedObject.Created - 1, TTrackedObject.Freed, 'Every loser is freed, the winner stays');

      Race.Release;
      Assert.AreEqual(TTrackedObject.Created, TTrackedObject.Freed, 'Release frees the published instance');
    finally
      Race.Free;
    end;
  end;
end;

procedure TSharedInstanceTests.TestEveryThreadMakesACandidateAndOneSurvives;
begin
  // The factories wait for each other, so every thread has made a candidate before any of them can publish
  const ThreadCount = 8;
  const Race = TInstanceRace.Create(ThreadCount, True);
  try
    RunConcurrently(Race);

    Assert.AreEqual(ThreadCount, TTrackedObject.Created, 'All threads raced with a candidate');
    Assert.AreEqual(ThreadCount - 1, TTrackedObject.Freed);
    for var Index := 1 to ThreadCount - 1 do
    begin
      Assert.AreSame(Race.Results[0], Race.Results[Index]);
    end;
    Race.Release;
    Assert.AreEqual(ThreadCount, TTrackedObject.Freed);
  finally
    Race.Free;
  end;
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
    const Race = TCacheRace.Create(Cache, ThreadCount, True);
    try
      RunConcurrently(Race);

      for var Index := 1 to ThreadCount - 1 do
      begin
        Assert.AreSame(Race.Results[0], Race.Results[Index]);
      end;
    finally
      Race.Free;
    end;
    Assert.AreEqual(ThreadCount, TTrackedObject.Created);
    Assert.AreEqual(ThreadCount - 1, TTrackedObject.Freed);
  finally
    Cache.Free;
  end;
  Assert.AreEqual(ThreadCount, TTrackedObject.Freed);
end;

procedure TSharedInstanceTests.TestSharedCacheNilFromFactoryRaises;
begin
  const Cache = TTrackedCache.Create;
  try
    Assert.WillRaise(
      procedure
      begin
        Cache.GetOrAdd('nil',
          function(Key: string): TTrackedObject
          begin
            Result := nil;
          end);
      end,
      EArgumentException);

    var Value: TTrackedObject;
    Assert.IsFalse(Cache.TryGet('nil', Value), 'A nil is never stored');
  finally
    Cache.Free;
  end;
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
