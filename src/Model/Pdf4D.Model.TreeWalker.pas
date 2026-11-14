// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/common/PDNameTreeNode.java and PDNumberTreeNode.java (3.0.8),
// the shared part: the walk through /Kids
unit Pdf4D.Model.TreeWalker;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.Log,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.PdfArray;

const
  // A node deeper than this is not looked at. It is the depth that the oracle of the golden files stops at.
  MaxTreeDepth = 64;

type
  TTreeFrame = record
    Kids: TCosArray;
    Index: Integer;
    Depth: Integer;
  end;

  // The walk through name trees and number trees without recursion. Each dictionary is looked at once, so a tree with
  // a cycle (or the same node under two parents) cannot make the work grow beyond the size of the file.
  TPDTreeWalker = record
    class procedure Warn(const Log: TPdfLog; const Message: string); static;

    // The nodes without a /Kids array, in the order of the walk: the kids of a node in array order. A node with /Kids
    // is walked through its kids only, its own /Names or /Nums is ignored. A kid that is no dictionary gives a
    // warning and nothing else, as it is an empty node in PDFBox.
    class function CollectLeaves(const Root: TCosDictionary; const Log: TPdfLog): TArray<TCosDictionary>; static;

    // Port of COSArray.getString(index) for the /Limits: the raw item must be a string
    class function TryGetLimitString(const Node: TCosDictionary; const Index: Integer; out Value: string): Boolean; static;
    // Port of COSArray.getInt(index, -1) for the /Limits. False when /Limits is no array, is too short or the item
    // is no number.
    class function TryGetLimitInt(const Node: TCosDictionary; const Index: Integer; out Value: Integer): Boolean; static;
  end;

implementation

uses
  Pdf4D.Cos.Names,
  Pdf4D.Cos.Number,
  Pdf4D.Cos.PdfString;

{ TPDTreeWalker }

class procedure TPDTreeWalker.Warn(const Log: TPdfLog; const Message: string);
begin
  if Assigned(Log) then
  begin
    Log.Warning(Message);
  end;
end;

class function TPDTreeWalker.CollectLeaves(const Root: TCosDictionary; const Log: TPdfLog): TArray<TCosDictionary>;
begin
  const Leaves = TList<TCosDictionary>.Create;
  const Visited = TDictionary<TCosDictionary, Boolean>.Create;
  const Stack = TList<TTreeFrame>.Create;
  try
    var Frame: TTreeFrame;
    Frame.Index := 0;
    Visited.Add(Root, True);
    if Root.TryGetCosArray(TCosNames.Kids, Frame.Kids) then
    begin
      Frame.Depth := 0;
      Stack.Add(Frame);
    end
    else
    begin
      Leaves.Add(Root);
    end;

    while Stack.Count > 0 do
    begin
      Frame := Stack[Stack.Count - 1];
      if Frame.Index >= Frame.Kids.Count then
      begin
        Stack.Delete(Stack.Count - 1);
        Continue;
      end;

      const KidIndex = Frame.Index;
      Inc(Frame.Index);
      Stack[Stack.Count - 1] := Frame;

      const Kid = Frame.Kids.GetObject(KidIndex);
      if not (Kid is TCosDictionary) then
      begin
        Warn(Log, Format('Bad child node at position %d', [KidIndex]));
        Continue;
      end;

      const KidNode = TCosDictionary(Kid);
      if Visited.ContainsKey(KidNode) then
      begin
        Warn(Log, 'A node of the tree is met a second time and skipped');
        Continue;
      end;
      Visited.Add(KidNode, True);

      if Frame.Depth + 1 > MaxTreeDepth then
      begin
        Warn(Log, 'The tree is too deep, a node is skipped');
        Continue;
      end;

      var KidFrame: TTreeFrame;
      if KidNode.TryGetCosArray(TCosNames.Kids, KidFrame.Kids) then
      begin
        KidFrame.Index := 0;
        KidFrame.Depth := Frame.Depth + 1;
        Stack.Add(KidFrame);
      end
      else
      begin
        Leaves.Add(KidNode);
      end;
    end;

    Result := Leaves.ToArray;
  finally
    Stack.Free;
    Visited.Free;
    Leaves.Free;
  end;
end;

class function TPDTreeWalker.TryGetLimitString(const Node: TCosDictionary; const Index: Integer; out Value: string): Boolean;
begin
  Value := '';
  var Limits: TCosArray;
  Result := (Node.TryGetCosArray(TCosNames.Limits, Limits) and (Index < Limits.Count) and (Limits.Get(Index) is TCosString));
  if Result then
  begin
    Value := TCosString(Limits.Get(Index)).GetString;
  end;
end;

class function TPDTreeWalker.TryGetLimitInt(const Node: TCosDictionary; const Index: Integer; out Value: Integer): Boolean;
begin
  Value := -1;
  var Limits: TCosArray;
  Result := (Node.TryGetCosArray(TCosNames.Limits, Limits) and (Index < Limits.Count) and (Limits.Get(Index) is TCosNumber));
  if Result then
  begin
    Value := TCosNumber(Limits.Get(Index)).IntValue;
  end;
end;

end.
