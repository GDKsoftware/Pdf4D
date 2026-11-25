// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.Cache.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  DUnitX.TestFramework,
  Pdf4D.Viewer.Cache;

type
  IProbe = interface
    ['{5E0B7C41-93A2-4D6F-8B1E-2A7D4C9F0E35}']
    function Name: string;
  end;

  [TestFixture]
  TPdfLruCacheTests = class
  private
    FCache: TPdfLruCache<string, Integer>;

    procedure CreateCache(const MaxCost: Int64);
    class procedure AddProbe(const Cache: TPdfLruCache<string, IProbe>; const Key: string; const Cost: Int64); static;

  public
    [Teardown]
    procedure Teardown;

    [Test]
    procedure TestLruEvictsLeastRecentlyUsed;
    [Test]
    procedure TestContainsDoesNotMarkAsUsed;
    [Test]
    procedure TestAddReplacesAndRecountsCost;
    [Test]
    procedure TestReplacingEvictsOthersWhenCostGrows;
    [Test]
    procedure TestItemLargerThanMaxIsNotKept;
    [Test]
    procedure TestLargeReplacementRemovesTheOldValue;
    [Test]
    procedure TestRemove;
    [Test]
    procedure TestRemoveWhere;
    [Test]
    procedure TestClear;
    [Test]
    procedure TestLoweringMaxCostEvicts;
    [Test]
    procedure TestInvalidArgumentsRaise;
    [Test]
    procedure TestInterfaceValuesAreReleased;
  end;

implementation

uses
  System.SysUtils;

type
  TProbe = class(TInterfacedObject, IProbe)
  private
    FName: string;

  public
    class var Alive: Integer;

    constructor Create(const Name: string);
    destructor Destroy; override;

    function Name: string;
  end;

{ TProbe }

constructor TProbe.Create(const Name: string);
begin
  inherited Create;
  FName := Name;
  Inc(Alive);
end;

destructor TProbe.Destroy;
begin
  Dec(Alive);
  inherited Destroy;
end;

function TProbe.Name: string;
begin
  Result := FName;
end;

{ TPdfLruCacheTests }

// A separate routine, so that the temporary interface of the new probe is released when it returns
class procedure TPdfLruCacheTests.AddProbe(const Cache: TPdfLruCache<string, IProbe>; const Key: string; const Cost: Int64);
begin
  var Probe: IProbe := TProbe.Create(Key);
  Cache.Add(Key, Probe, Cost);
  Probe := nil;
end;

procedure TPdfLruCacheTests.CreateCache(const MaxCost: Int64);
begin
  FCache.Free;
  FCache := TPdfLruCache<string, Integer>.Create(MaxCost);
end;

procedure TPdfLruCacheTests.Teardown;
begin
  FreeAndNil(FCache);
end;

procedure TPdfLruCacheTests.TestLruEvictsLeastRecentlyUsed;
begin
  CreateCache(3);
  FCache.Add('A', 1, 1);
  FCache.Add('B', 2, 1);
  FCache.Add('C', 3, 1);

  var Value: Integer;
  Assert.IsTrue(FCache.TryGet('A', Value));
  Assert.AreEqual(1, Value);
  FCache.Add('D', 4, 1);

  Assert.IsFalse(FCache.Contains('B'), 'B is the least recently used');
  Assert.IsTrue(FCache.Contains('A'));
  Assert.IsTrue(FCache.Contains('C'));
  Assert.IsTrue(FCache.Contains('D'));
  Assert.AreEqual(3, FCache.Count);
  Assert.AreEqual(Int64(3), FCache.TotalCost);
end;

procedure TPdfLruCacheTests.TestContainsDoesNotMarkAsUsed;
begin
  CreateCache(2);
  FCache.Add('A', 1, 1);
  FCache.Add('B', 2, 1);

  Assert.IsTrue(FCache.Contains('A'));
  FCache.Add('C', 3, 1);

  Assert.IsFalse(FCache.Contains('A'), 'Contains must not refresh A');
  Assert.IsTrue(FCache.Contains('B'));
end;

procedure TPdfLruCacheTests.TestAddReplacesAndRecountsCost;
begin
  CreateCache(10);
  FCache.Add('A', 1, 4);
  FCache.Add('A', 2, 6);

  Assert.AreEqual(1, FCache.Count);
  Assert.AreEqual(Int64(6), FCache.TotalCost);
  var Value: Integer;
  Assert.IsTrue(FCache.TryGet('A', Value));
  Assert.AreEqual(2, Value);
end;

procedure TPdfLruCacheTests.TestReplacingEvictsOthersWhenCostGrows;
begin
  CreateCache(5);
  FCache.Add('A', 1, 2);
  FCache.Add('B', 2, 2);
  FCache.Add('A', 3, 4);

  Assert.IsFalse(FCache.Contains('B'));
  Assert.IsTrue(FCache.Contains('A'));
  Assert.AreEqual(Int64(4), FCache.TotalCost);
end;

procedure TPdfLruCacheTests.TestItemLargerThanMaxIsNotKept;
begin
  CreateCache(3);
  FCache.Add('A', 1, 5);

  Assert.AreEqual(0, FCache.Count);
  Assert.AreEqual(Int64(0), FCache.TotalCost);
  Assert.IsFalse(FCache.Contains('A'));
end;

procedure TPdfLruCacheTests.TestLargeReplacementRemovesTheOldValue;
begin
  CreateCache(3);
  FCache.Add('A', 1, 2);
  FCache.Add('A', 2, 5);

  Assert.IsFalse(FCache.Contains('A'), 'the stale value must not survive');
  Assert.AreEqual(Int64(0), FCache.TotalCost);
end;

procedure TPdfLruCacheTests.TestRemove;
begin
  CreateCache(10);
  FCache.Add('A', 1, 2);
  FCache.Add('B', 2, 3);
  FCache.Remove('A');
  FCache.Remove('unknown');

  Assert.AreEqual(1, FCache.Count);
  Assert.AreEqual(Int64(3), FCache.TotalCost);
end;

procedure TPdfLruCacheTests.TestRemoveWhere;
begin
  CreateCache(100);
  FCache.Add('1:a', 1, 1);
  FCache.Add('2:a', 2, 2);
  FCache.Add('1:b', 3, 4);
  FCache.Add('2:b', 4, 8);

  FCache.RemoveWhere(
    function(Key: string): Boolean
    begin
      Result := Key.StartsWith('2:');
    end);

  Assert.AreEqual(2, FCache.Count);
  Assert.AreEqual(Int64(5), FCache.TotalCost);
  Assert.IsTrue(FCache.Contains('1:a'));
  Assert.IsTrue(FCache.Contains('1:b'));
end;

procedure TPdfLruCacheTests.TestClear;
begin
  CreateCache(10);
  FCache.Add('A', 1, 2);
  FCache.Clear;

  Assert.AreEqual(0, FCache.Count);
  Assert.AreEqual(Int64(0), FCache.TotalCost);
  FCache.Add('B', 2, 2);
  Assert.AreEqual(1, FCache.Count);
end;

procedure TPdfLruCacheTests.TestLoweringMaxCostEvicts;
begin
  CreateCache(10);
  FCache.Add('A', 1, 4);
  FCache.Add('B', 2, 4);
  FCache.MaxCost := 5;

  Assert.IsFalse(FCache.Contains('A'));
  Assert.IsTrue(FCache.Contains('B'));
  Assert.AreEqual(Int64(4), FCache.TotalCost);
end;

procedure TPdfLruCacheTests.TestInvalidArgumentsRaise;
begin
  Assert.WillRaise(
    procedure
    begin
      TPdfLruCache<string, Integer>.Create(-1).Free;
    end,
    EArgumentOutOfRangeException);

  CreateCache(10);
  Assert.WillRaise(
    procedure
    begin
      FCache.Add('A', 1, -1);
    end,
    EArgumentOutOfRangeException);
end;

procedure TPdfLruCacheTests.TestInterfaceValuesAreReleased;
begin
  TProbe.Alive := 0;
  const Cache = TPdfLruCache<string, IProbe>.Create(2);
  try
    AddProbe(Cache, 'A', 1);
    AddProbe(Cache, 'B', 1);
    Assert.AreEqual(2, TProbe.Alive);

    AddProbe(Cache, 'C', 1);
    Assert.AreEqual(2, TProbe.Alive, 'eviction releases the value');

    AddProbe(Cache, 'C', 1);
    Assert.AreEqual(2, TProbe.Alive, 'replacing releases the old value');

    Cache.Clear;
    Assert.AreEqual(0, TProbe.Alive, 'Clear releases the values');

    AddProbe(Cache, 'D', 1);
    AddProbe(Cache, 'E', 5);
    Assert.AreEqual(1, Cache.Count, 'count');
    Assert.AreEqual(1, TProbe.Alive, 'an item that is too large is not kept');
  finally
    Cache.Free;
  end;

  Assert.AreEqual(0, TProbe.Alive, 'Free releases the values');
end;

end.
