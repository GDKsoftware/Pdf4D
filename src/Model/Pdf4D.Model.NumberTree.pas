// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/common/PDNumberTreeNode.java (3.0.8), the read side
unit Pdf4D.Model.NumberTree;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.Log,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Model.NameTree;

type
  // Same as TPDNameTreeConverter: the value of an entry is converted when its leaf is read, and the converter is not
  // called for a null value (PDNumberTreeNode.getNumbers does not call it either).
  TPDNumberTreeConverter = TPDNameTreeConverter;

  // A number tree, read only. The node does not own the dictionary.
  TPDNumberTreeNode = class
  private
    type
      TNumberMap = class
      private
        FKeys: TList<Integer>;
        FValues: TList<TCosBase>;
        FPositions: TDictionary<Integer, Integer>;

      public
        constructor Create;
        destructor Destroy; override;

        // A key that is there already keeps its place and gets the new value
        procedure Put(const Key: Integer; const Value: TCosBase);
        function TryGetValue(const Key: Integer; out Value: TCosBase): Boolean;

        property Keys: TList<Integer> read FKeys;
        property Values: TList<TCosBase> read FValues;
      end;

  private
    FRoot: TCosDictionary;
    FConverter: TPDNumberTreeConverter;
    FLog: TPdfLog;

    function ConvertValue(const Value: TCosBase): TCosBase;
    function TryBuildNumberMap(const Leaf: TCosDictionary; out Map: TNumberMap): Boolean;
    class function KidMatches(const Kid: TCosDictionary; const Number: Integer): Boolean; static;

  public
    // Root is not owned. Converter may be nil, then the values are given as they are. Log may be nil.
    constructor Create(const Root: TCosDictionary; const Converter: TPDNumberTreeConverter; const Log: TPdfLog);

    // Port of PDNumberTreeNode.getValue, without recursion. As in PDFBox a leaf with /Nums answers for the node and the
    // kids are tried in order until one has the number. A kid without usable /Limits raises EPdfParseException (a
    // NullPointerException in PDFBox). False when the number is not there or its value is nil.
    function TryGetValue(const Number: Integer; out Value: TCosBase): Boolean;

    // All numbers of the tree in the order of the walk, with the pairs of a leaf in array order. A leaf whose /Nums has a
    // key that is no integer is left out (PDFBox logs "page labels ignored" and returns null for it). The values can
    // be nil. Raises EPdfParseException when a value cannot be converted.
    function GetAll: TArray<TPair<Integer, TCosBase>>;

    property CosObject: TCosDictionary read FRoot;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.Null,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Model.TreeWalker;

{ TPDNumberTreeNode.TNumberMap }

constructor TPDNumberTreeNode.TNumberMap.Create;
begin
  inherited Create;
  FKeys := TList<Integer>.Create;
  FValues := TList<TCosBase>.Create;
  FPositions := TDictionary<Integer, Integer>.Create;
end;

destructor TPDNumberTreeNode.TNumberMap.Destroy;
begin
  FPositions.Free;
  FValues.Free;
  FKeys.Free;
  inherited;
end;

procedure TPDNumberTreeNode.TNumberMap.Put(const Key: Integer; const Value: TCosBase);
begin
  var Position: Integer;
  if FPositions.TryGetValue(Key, Position) then
  begin
    FValues[Position] := Value;
    Exit;
  end;

  FPositions.Add(Key, FKeys.Count);
  FKeys.Add(Key);
  FValues.Add(Value);
end;

function TPDNumberTreeNode.TNumberMap.TryGetValue(const Key: Integer; out Value: TCosBase): Boolean;
begin
  var Position: Integer;
  Result := FPositions.TryGetValue(Key, Position);
  if Result then
  begin
    Value := FValues[Position];
  end
  else
  begin
    Value := nil;
  end;
end;

{ TPDNumberTreeNode }

constructor TPDNumberTreeNode.Create(const Root: TCosDictionary; const Converter: TPDNumberTreeConverter; const Log: TPdfLog);
begin
  inherited Create;
  FRoot := Root;
  FConverter := Converter;
  FLog := Log;
end;

function TPDNumberTreeNode.ConvertValue(const Value: TCosBase): TCosBase;
begin
  if Assigned(FConverter) then
  begin
    Result := FConverter(Value);
  end
  else
  begin
    Result := Value;
  end;
end;

// Port of PDNumberTreeNode.getNumbers. False when the node has no /Nums array, or a key that is no integer.
function TPDNumberTreeNode.TryBuildNumberMap(const Leaf: TCosDictionary; out Map: TNumberMap): Boolean;
begin
  Map := nil;
  var Pairs: TCosArray;
  if not Leaf.TryGetCosArray(TCosNames.Nums, Pairs) then
  begin
    Exit(False);
  end;

  if Pairs.Count mod 2 <> 0 then
  begin
    TPDTreeWalker.Warn(FLog, Format('Numbers array has odd size: %d', [Pairs.Count]));
  end;

  const Built = TNumberMap.Create;
  try
    var Index := 0;
    while Index + 1 < Pairs.Count do
    begin
      const Key = Pairs.GetObject(Index);
      if not (Key is TCosInteger) then
      begin
        if Assigned(FLog) then
        begin
          FLog.Error(Format('page labels ignored, index %d should be a number', [Index]));
        end;
        Built.Free;
        Exit(False);
      end;

      var Value := Pairs.GetObject(Index + 1);
      if Value is TCosNull then
      begin
        Built.Put(TCosInteger(Key).IntValue, nil);
      end
      else
      begin
        Built.Put(TCosInteger(Key).IntValue, ConvertValue(Value));
      end;
      Inc(Index, 2);
    end;
  except
    Built.Free;
    raise;
  end;

  Map := Built;
  Result := True;
end;

class function TPDNumberTreeNode.KidMatches(const Kid: TCosDictionary; const Number: Integer): Boolean;
begin
  var Lower: Integer;
  var Upper: Integer;
  if not (TPDTreeWalker.TryGetLimitInt(Kid, 0, Lower) and TPDTreeWalker.TryGetLimitInt(Kid, 1, Upper)) then
  begin
    raise EPdfParseException.Create('A node of a number tree has no usable /Limits');
  end;

  Result := ((Lower <= Number) and (Upper >= Number));
end;

function TPDNumberTreeNode.TryGetValue(const Number: Integer; out Value: TCosBase): Boolean;
begin
  Value := nil;
  const Visited = TDictionary<TCosDictionary, Boolean>.Create;
  const Stack = TList<TTreeFrame>.Create;
  try
    // The node that is entered: its /Nums answer for it, otherwise its kids are put on the stack
    var Entering: TCosDictionary := FRoot;
    var EnteringDepth := 0;
    while True do
    begin
      if Assigned(Entering) then
      begin
        Visited.Add(Entering, True);
        var Map: TNumberMap;
        if TryBuildNumberMap(Entering, Map) then
        begin
          try
            if Map.TryGetValue(Number, Value) and Assigned(Value) then
            begin
              Exit(True);
            end;
          finally
            Map.Free;
          end;
        end
        else
        begin
          var Frame: TTreeFrame;
          if Entering.TryGetCosArray(TCosNames.Kids, Frame.Kids) then
          begin
            Frame.Index := 0;
            Frame.Depth := EnteringDepth;
            Stack.Add(Frame);
          end
          else
          begin
            TPDTreeWalker.Warn(FLog, 'NumberTreeNode does not have "nums" nor "kids" objects.');
          end;
        end;
        Entering := nil;
      end;

      if Stack.Count = 0 then
      begin
        Exit(False);
      end;

      var Top := Stack[Stack.Count - 1];
      if Top.Index >= Top.Kids.Count then
      begin
        Stack.Delete(Stack.Count - 1);
        Continue;
      end;

      const KidIndex = Top.Index;
      Inc(Top.Index);
      Stack[Stack.Count - 1] := Top;

      const Kid = Top.Kids.GetObject(KidIndex);
      if not (Kid is TCosDictionary) then
      begin
        raise EPdfParseException.Create('A kid of a number tree is no dictionary');
      end;

      if not Visited.ContainsKey(TCosDictionary(Kid)) and KidMatches(TCosDictionary(Kid), Number) and
         (Top.Depth + 1 <= MaxTreeDepth) then
      begin
        Entering := TCosDictionary(Kid);
        EnteringDepth := Top.Depth + 1;
      end;
    end;
  finally
    Stack.Free;
    Visited.Free;
  end;
end;

function TPDNumberTreeNode.GetAll: TArray<TPair<Integer, TCosBase>>;
begin
  const Found = TList<TPair<Integer, TCosBase>>.Create;
  try
    for var Leaf in TPDTreeWalker.CollectLeaves(FRoot, FLog) do
    begin
      var Map: TNumberMap;
      if TryBuildNumberMap(Leaf, Map) then
      begin
        try
          for var Index := 0 to Map.Keys.Count - 1 do
          begin
            Found.Add(TPair<Integer, TCosBase>.Create(Map.Keys[Index], Map.Values[Index]));
          end;
        finally
          Map.Free;
        end;
      end;
    end;
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

end.
