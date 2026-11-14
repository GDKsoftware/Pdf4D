// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/common/PDNameTreeNode.java (3.0.8), the read side
unit Pdf4D.Model.NameTree;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.Log,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.PdfArray;

type
  // Port of the convertCOSToPD of the subclasses of PDNameTreeNode. It gets the resolved value (nil for a null) and
  // gives what the tree hands out, which can be nil. A value that cannot be converted raises EPdfParseException, as
  // PDFBox throws an IOException. The result belongs to the document, like everything below a dictionary.
  TPDNameTreeConverter = reference to function(const Value: TCosBase): TCosBase;

  // A name tree, read only. The node does not own the dictionary. As in PDFBox all values of a leaf are converted
  // when a leaf is read, so one bad value spoils the lookups in its leaf. The leaves that a lookup has used are kept,
  // so many lookups in a wide tree do not read the same leaf again and again.
  TPDNameTreeNode = class
  private
    type
      TLeafMap = class
      private
        FKeys: TList<string>;
        FValues: TList<TCosBase>;
        FPositions: TDictionary<string, Integer>;

      public
        FailureMessage: string;

        constructor Create;
        destructor Destroy; override;

        // A key that is there already keeps its place and gets the new value, like LinkedHashMap.put
        procedure Put(const Key: string; const Value: TCosBase);
        function TryGetValue(const Key: string; out Value: TCosBase): Boolean;

        property Keys: TList<string> read FKeys;
        property Values: TList<TCosBase> read FValues;
      end;

  private
    FRoot: TCosDictionary;
    FConverter: TPDNameTreeConverter;
    FLog: TPdfLog;
    FLeafCache: TObjectDictionary<TCosDictionary, TLeafMap>;

    function ConvertValue(const Value: TCosBase): TCosBase;
    function TryBuildLeafMap(const Leaf: TCosDictionary; out Map: TLeafMap): Boolean;
    function GetCachedLeafMap(const Leaf: TCosDictionary): TLeafMap;
    function TryFindFirstMatchingKid(const Kids: TCosArray; const Name: string; out Kid: TCosDictionary): Boolean;
    class function KidMatches(const Kid: TCosDictionary; const Name: string): Boolean; static;

  public
    // Root is not owned. Converter may be nil, then the values are given as they are. Log may be nil.
    constructor Create(const Root: TCosDictionary; const Converter: TPDNameTreeConverter; const Log: TPdfLog);
    destructor Destroy; override;

    // Port of PDNameTreeNode.getValue, with a loop instead of the recursion: the leaf is read when it has /Names, the
    // first kid whose /Limits fit the name is followed otherwise. False when the name is not there, or when its
    // value is nil. Raises EPdfParseException when the leaf holds a bad key or a value that cannot be converted.
    function TryGetValue(const Name: string; out Value: TCosBase): Boolean;

    // All names of the tree in the order of the walk: through the kids of a node in array order, a node with /Kids
    // is not read for its own /Names, and the pairs of a leaf in array order. This is not sorted: the oracle of the
    // golden files does not sort either. The values can be nil. Raises EPdfParseException like TryGetValue.
    function GetAll: TArray<TPair<string, TCosBase>>;

    property CosObject: TCosDictionary read FRoot;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.Null,
  Pdf4D.Cos.PdfString,
  Pdf4D.Model.TreeWalker;

{ TPDNameTreeNode.TLeafMap }

constructor TPDNameTreeNode.TLeafMap.Create;
begin
  inherited Create;
  FKeys := TList<string>.Create;
  FValues := TList<TCosBase>.Create;
  FPositions := TDictionary<string, Integer>.Create;
end;

destructor TPDNameTreeNode.TLeafMap.Destroy;
begin
  FPositions.Free;
  FValues.Free;
  FKeys.Free;
  inherited;
end;

procedure TPDNameTreeNode.TLeafMap.Put(const Key: string; const Value: TCosBase);
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

function TPDNameTreeNode.TLeafMap.TryGetValue(const Key: string; out Value: TCosBase): Boolean;
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

{ TPDNameTreeNode }

constructor TPDNameTreeNode.Create(const Root: TCosDictionary; const Converter: TPDNameTreeConverter; const Log: TPdfLog);
begin
  inherited Create;
  FRoot := Root;
  FConverter := Converter;
  FLog := Log;
  FLeafCache := TObjectDictionary<TCosDictionary, TLeafMap>.Create([doOwnsValues]);
end;

destructor TPDNameTreeNode.Destroy;
begin
  FLeafCache.Free;
  inherited;
end;

function TPDNameTreeNode.ConvertValue(const Value: TCosBase): TCosBase;
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

// Port of PDNameTreeNode.getNames. False when the node has no /Names array.
function TPDNameTreeNode.TryBuildLeafMap(const Leaf: TCosDictionary; out Map: TLeafMap): Boolean;
begin
  Map := nil;
  var Pairs: TCosArray;
  if not Leaf.TryGetCosArray(TCosNames.Names, Pairs) then
  begin
    Exit(False);
  end;

  if Pairs.Count mod 2 <> 0 then
  begin
    TPDTreeWalker.Warn(FLog, Format('Names array has odd size: %d', [Pairs.Count]));
  end;

  const Built = TLeafMap.Create;
  try
    var Index := 0;
    while Index + 1 < Pairs.Count do
    begin
      const Key = Pairs.GetObject(Index);
      if not (Key is TCosString) then
      begin
        raise EPdfParseException.CreateFmt('Expected a string as name in a name tree at index %d', [Index]);
      end;

      var Value := Pairs.GetObject(Index + 1);
      if Value is TCosNull then
      begin
        Value := nil;
      end;
      Built.Put(TCosString(Key).GetString, ConvertValue(Value));
      Inc(Index, 2);
    end;
  except
    Built.Free;
    raise;
  end;

  Map := Built;
  Result := True;
end;

// A failure is kept too, so a leaf that cannot be read is not tried again for each lookup
function TPDNameTreeNode.GetCachedLeafMap(const Leaf: TCosDictionary): TLeafMap;
begin
  if FLeafCache.TryGetValue(Leaf, Result) then
  begin
    if Result.FailureMessage <> '' then
    begin
      raise EPdfParseException.Create(Result.FailureMessage);
    end;
    Exit;
  end;

  try
    TryBuildLeafMap(Leaf, Result);
    if not Assigned(Result) then
    begin
      Result := TLeafMap.Create;
    end;
  except
    on Error: EPdfParseException do
    begin
      Result := TLeafMap.Create;
      Result.FailureMessage := Error.Message;
      FLeafCache.Add(Leaf, Result);
      raise;
    end;
  end;
  FLeafCache.Add(Leaf, Result);
end;

class function TPDNameTreeNode.KidMatches(const Kid: TCosDictionary; const Name: string): Boolean;
begin
  var Upper: string;
  var Lower: string;
  if not (TPDTreeWalker.TryGetLimitString(Kid, 1, Upper) and TPDTreeWalker.TryGetLimitString(Kid, 0, Lower)) then
  begin
    Exit(True);
  end;

  Result := ((string.CompareOrdinal(Upper, Lower) < 0) or
             ((string.CompareOrdinal(Lower, Name) <= 0) and (string.CompareOrdinal(Upper, Name) >= 0)));
end;

function TPDNameTreeNode.TryFindFirstMatchingKid(const Kids: TCosArray; const Name: string; out Kid: TCosDictionary): Boolean;
begin
  Kid := nil;
  for var Index := 0 to Kids.Count - 1 do
  begin
    const Item = Kids.GetObject(Index);
    if not (Item is TCosDictionary) then
    begin
      // PDFBox makes an empty node of it, which has no limits and so is the one to follow: it finds nothing
      TPDTreeWalker.Warn(FLog, Format('Bad child node at position %d', [Index]));
      Exit(False);
    end;

    if KidMatches(TCosDictionary(Item), Name) then
    begin
      Kid := TCosDictionary(Item);
      Exit(True);
    end;
  end;
  Result := False;
end;

function TPDNameTreeNode.TryGetValue(const Name: string; out Value: TCosBase): Boolean;
begin
  Value := nil;
  var Node := FRoot;
  for var Depth := 0 to MaxTreeDepth do
  begin
    var Pairs: TCosArray;
    if Node.TryGetCosArray(TCosNames.Names, Pairs) then
    begin
      Exit(GetCachedLeafMap(Node).TryGetValue(Name, Value) and Assigned(Value));
    end;

    var Kids: TCosArray;
    if not Node.TryGetCosArray(TCosNames.Kids, Kids) then
    begin
      TPDTreeWalker.Warn(FLog, 'NameTreeNode does not have "names" nor "kids" objects.');
      Exit(False);
    end;

    // PDFBox makes the nodes of all kids first (getKids), which loads every kid object. That decides which objects of
    // a damaged file are found by recovery, so it is done here too.
    for var Index := 0 to Kids.Count - 1 do
    begin
      Kids.GetObject(Index);
    end;

    var Kid: TCosDictionary;
    if not TryFindFirstMatchingKid(Kids, Name, Kid) then
    begin
      Exit(False);
    end;
    Node := Kid;
  end;

  TPDTreeWalker.Warn(FLog, 'The name tree is too deep, the lookup stops');
  Result := False;
end;

function TPDNameTreeNode.GetAll: TArray<TPair<string, TCosBase>>;
begin
  const Found = TList<TPair<string, TCosBase>>.Create;
  try
    for var Leaf in TPDTreeWalker.CollectLeaves(FRoot, FLog) do
    begin
      var Map: TLeafMap;
      if TryBuildLeafMap(Leaf, Map) then
      begin
        try
          for var Index := 0 to Map.Keys.Count - 1 do
          begin
            Found.Add(TPair<string, TCosBase>.Create(Map.Keys[Index], Map.Values[Index]));
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
