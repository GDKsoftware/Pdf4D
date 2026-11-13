// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Common.SharedInstance;

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections;

type
  // One lazily made object that all threads share. It is meant as a class var of the owning class, which frees it from
  // a class destructor. The record must start zeroed, so keep it in a class var or global, or assign Default() first.
  // What is published must not change afterwards.
  TPdfSharedInstance<T: class> = record
  private
    FValue: T;

  public
    // The published instance; creates it with Factory on first use. When two threads race, one candidate is published
    // and the other is freed. Factory may raise: nothing is published then.
    function Get(const Factory: TFunc<T>): T;
    // Frees the published instance. Only called from a class destructor.
    procedure Release;
  end;

  // Values by key that all threads share. The cache owns the values. A value is made outside the lock, so two threads
  // can make the same one; the first one that is added stays and the other is freed.
  TPdfSharedCache<TKey; TValue: class> = class
  private
    FLock: TLightweightMREW;
    FItems: TObjectDictionary<TKey, TValue>;

  public
    constructor Create;
    destructor Destroy; override;

    function GetOrAdd(const Key: TKey; const Factory: TFunc<TKey, TValue>): TValue;
    function TryGet(const Key: TKey; out Value: TValue): Boolean;
  end;

implementation

{ TPdfSharedInstance<T> }

function TPdfSharedInstance<T>.Get(const Factory: TFunc<T>): T;
begin
  Result := TInterlocked.CompareExchange<T>(FValue, nil, nil);
  if Assigned(Result) then
  begin
    Exit;
  end;

  const Candidate = Factory();
  if not Assigned(Candidate) then
  begin
    raise EArgumentException.Create('The factory of a shared instance returned nil');
  end;

  Result := TInterlocked.CompareExchange<T>(FValue, Candidate, nil);
  if Assigned(Result) then
  begin
    Candidate.Free;
  end
  else
  begin
    Result := Candidate;
  end;
end;

procedure TPdfSharedInstance<T>.Release;
begin
  const Published = TInterlocked.Exchange<T>(FValue, nil);
  Published.Free;
end;

{ TPdfSharedCache<TKey, TValue> }

constructor TPdfSharedCache<TKey, TValue>.Create;
begin
  inherited Create;
  FItems := TObjectDictionary<TKey, TValue>.Create([doOwnsValues]);
end;

destructor TPdfSharedCache<TKey, TValue>.Destroy;
begin
  FItems.Free;
  inherited;
end;

function TPdfSharedCache<TKey, TValue>.TryGet(const Key: TKey; out Value: TValue): Boolean;
begin
  FLock.BeginRead;
  try
    Result := FItems.TryGetValue(Key, Value);
  finally
    FLock.EndRead;
  end;
end;

function TPdfSharedCache<TKey, TValue>.GetOrAdd(const Key: TKey; const Factory: TFunc<TKey, TValue>): TValue;
begin
  if TryGet(Key, Result) then
  begin
    Exit;
  end;

  const Candidate = Factory(Key);
  if Candidate = nil then
  begin
    raise EArgumentException.Create('The factory of a shared cache must not return nil');
  end;

  FLock.BeginWrite;
  try
    if FItems.TryGetValue(Key, Result) then
    begin
      if Candidate <> Result then
      begin
        Candidate.Free;
      end;
    end
    else
    begin
      try
        FItems.Add(Key, Candidate);
      except
        Candidate.Free;
        raise;
      end;
      Result := Candidate;
    end;
  finally
    FLock.EndWrite;
  end;
end;

end.
