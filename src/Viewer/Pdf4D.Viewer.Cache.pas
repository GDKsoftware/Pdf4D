// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.Cache;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  // A cache bounded by the summed cost of its items; the least recently used items go first. A dictionary finds an item and a doubly
  // linked list keeps the order of use, so every operation except RemoveWhere and Clear is O(1). Not thread safe: UI thread only.
  TPdfLruCache<TKey, TValue> = class
  private
    type
      TNode = class
        Key: TKey;
        Value: TValue;
        Cost: Int64;
        Newer: TNode;
        Older: TNode;
      end;

  private
    FNodes: TDictionary<TKey, TNode>;
    // Most recently used
    FNewest: TNode;
    // Least recently used
    FOldest: TNode;
    FMaxCost: Int64;
    FTotalCost: Int64;

    class procedure CheckNotNegative(const Value: Int64; const Name: string); static;

    function GetCount: Integer;
    procedure SetMaxCost(const Value: Int64);
    procedure Unlink(const Node: TNode);
    procedure LinkAsNewest(const Node: TNode);
    procedure Drop(const Node: TNode);
    procedure EvictUntilWithinMax;

  public
    constructor Create(const MaxCost: Int64);
    destructor Destroy; override;

    // Replaces an existing item. An item that costs more than MaxCost is not kept.
    procedure Add(const Key: TKey; const Value: TValue; const Cost: Int64);
    // Marks the item as recently used
    function TryGet(const Key: TKey; out Value: TValue): Boolean;
    // Does not mark the item as recently used
    function Contains(const Key: TKey): Boolean;
    procedure Remove(const Key: TKey);
    procedure RemoveWhere(const Predicate: TPredicate<TKey>);
    procedure Clear;

    property MaxCost: Int64 read FMaxCost write SetMaxCost;
    property TotalCost: Int64 read FTotalCost;
    property Count: Integer read GetCount;
  end;

implementation

{ TPdfLruCache<TKey, TValue> }

constructor TPdfLruCache<TKey, TValue>.Create(const MaxCost: Int64);
begin
  inherited Create;
  // Created before the check: a constructor that raises still runs the destructor
  FNodes := TDictionary<TKey, TNode>.Create;
  CheckNotNegative(MaxCost, 'MaxCost');
  FMaxCost := MaxCost;
end;

destructor TPdfLruCache<TKey, TValue>.Destroy;
begin
  Clear;
  FNodes.Free;
  inherited Destroy;
end;

class procedure TPdfLruCache<TKey, TValue>.CheckNotNegative(const Value: Int64; const Name: string);
begin
  if Value < 0 then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('%s %d is negative', [Name, Value]);
  end;
end;

procedure TPdfLruCache<TKey, TValue>.SetMaxCost(const Value: Int64);
begin
  CheckNotNegative(Value, 'MaxCost');
  FMaxCost := Value;
  EvictUntilWithinMax;
end;

procedure TPdfLruCache<TKey, TValue>.Add(const Key: TKey; const Value: TValue; const Cost: Int64);
begin
  CheckNotNegative(Cost, 'Cost');
  Remove(Key);
  if Cost > FMaxCost then
  begin
    Exit;
  end;

  const Node = TNode.Create;
  Node.Key := Key;
  Node.Value := Value;
  Node.Cost := Cost;
  FNodes.Add(Key, Node);
  LinkAsNewest(Node);
  Inc(FTotalCost, Cost);
  EvictUntilWithinMax;
end;

function TPdfLruCache<TKey, TValue>.TryGet(const Key: TKey; out Value: TValue): Boolean;
begin
  var Node: TNode;
  Result := FNodes.TryGetValue(Key, Node);
  if not Result then
  begin
    Value := Default(TValue);
    Exit;
  end;

  if Node <> FNewest then
  begin
    Unlink(Node);
    LinkAsNewest(Node);
  end;
  Value := Node.Value;
end;

function TPdfLruCache<TKey, TValue>.Contains(const Key: TKey): Boolean;
begin
  Result := FNodes.ContainsKey(Key);
end;

procedure TPdfLruCache<TKey, TValue>.Remove(const Key: TKey);
begin
  var Node: TNode;
  if FNodes.TryGetValue(Key, Node) then
  begin
    Drop(Node);
  end;
end;

procedure TPdfLruCache<TKey, TValue>.RemoveWhere(const Predicate: TPredicate<TKey>);
begin
  var Node := FNewest;
  while Node <> nil do
  begin
    var Next: TNode := Node.Older;
    if Predicate(Node.Key) then
    begin
      Drop(Node);
    end;
    Node := Next;
  end;
end;

procedure TPdfLruCache<TKey, TValue>.Clear;
begin
  var Node := FNewest;
  while Node <> nil do
  begin
    var Next: TNode := Node.Older;
    Node.Free;
    Node := Next;
  end;
  FNewest := nil;
  FOldest := nil;
  FTotalCost := 0;
  FNodes.Clear;
end;

function TPdfLruCache<TKey, TValue>.GetCount: Integer;
begin
  Result := FNodes.Count;
end;

procedure TPdfLruCache<TKey, TValue>.Unlink(const Node: TNode);
begin
  if Node.Newer <> nil then
  begin
    Node.Newer.Older := Node.Older;
  end
  else
  begin
    FNewest := Node.Older;
  end;

  if Node.Older <> nil then
  begin
    Node.Older.Newer := Node.Newer;
  end
  else
  begin
    FOldest := Node.Newer;
  end;

  Node.Newer := nil;
  Node.Older := nil;
end;

procedure TPdfLruCache<TKey, TValue>.LinkAsNewest(const Node: TNode);
begin
  Node.Newer := nil;
  Node.Older := FNewest;
  if FNewest <> nil then
  begin
    FNewest.Newer := Node;
  end
  else
  begin
    FOldest := Node;
  end;
  FNewest := Node;
end;

procedure TPdfLruCache<TKey, TValue>.Drop(const Node: TNode);
begin
  Unlink(Node);
  FNodes.Remove(Node.Key);
  Dec(FTotalCost, Node.Cost);
  Node.Free;
end;

procedure TPdfLruCache<TKey, TValue>.EvictUntilWithinMax;
begin
  while (FTotalCost > FMaxCost) and (FOldest <> nil) do
  begin
    Drop(FOldest);
  end;
end;

end.
