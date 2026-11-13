// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/PDPageTree.java (3.0.8), the read side
unit Pdf4D.Model.PageTree;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Model.DocumentContext,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Model.Page;

const
  MaxInheritanceDepth = 1000;

type
  TPDPageTree = class;

  TPDPageTreeEnumerator = record
  private
    FTree: TPDPageTree;
    FIndex: Integer;

    function GetCurrent: TPDPage;

  public
    constructor Create(const Tree: TPDPageTree);

    function MoveNext: Boolean;

    property Current: TPDPage read GetCurrent;
  end;

  TKidsFrame = TPair<TArray<TCosDictionary>, Integer>;

  // Gives the pages in the order of the tree. The tree owns the TPDPage objects and creates each at its first use.
  // It works through the tree without recursion, so a very deep tree is no risk for the stack.
  //
  // Where it differs from PDPageTree: the list of pages is made once, by the walk of PDPageTree's iterator, and
  // Get(Index) reads that list. PDPageTree.get follows the /Count entries instead, which can give another page or
  // fail when a /Count is wrong, and costs a pass over the /Kids per call. Count is the /Count of the root as in PDFBox.
  TPDPageTree = class
  private
    FRoot: TCosDictionary;
    FContext: TPDDocumentContext;
    FIsSinglePage: Boolean;
    FIsListBuilt: Boolean;
    FDictionaries: TList<TCosDictionary>;
    FPages: TObjectList<TPDPage>;
    FEmptyPages: TObjectList<TCosDictionary>;
    FIndexes: TDictionary<TCosDictionary, Integer>;

    class function IsPageTreeNode(const Node: TCosDictionary): Boolean; static;
    class function HasTypeName(const Node: TCosDictionary; const TypeName: string): Boolean; static;

    procedure LogWarning(const Message: string);
    procedure LogError(const Message: string);
    procedure EnsureList;
    procedure BuildList;
    procedure Enqueue(const Node: TCosDictionary; const Stack: TStack<TKidsFrame>);
    function GetKids(const Node: TCosDictionary): TArray<TCosDictionary>;
    function GetCount: Integer;
    function GetEnumeratedCount: Integer;

  public
    // The tree does not own Root or Context
    constructor Create(const Root: TCosDictionary; const Context: TPDDocumentContext);
    destructor Destroy; override;

    // Port of PDPageTree.getInheritableAttribute: the value of Key on the node or on the nearest ancestor that is a page
    // tree node, with indirect references resolved. The walk stops after MaxInheritanceDepth nodes, which also ends a cycle.
    class function TryGetInheritableAttribute(const Node: TCosDictionary; const Key: string; out Value: TCosBase): Boolean; static;

    // Zero based. Raises EArgumentOutOfRangeException beyond the pages that the walk found.
    function Get(const Index: Integer): TPDPage;

    // The index of the page with this dictionary. Raises EPdfParseException when the tree does not hold it.
    function IndexOf(const Page: TCosDictionary): Integer;

    function GetEnumerator: TPDPageTreeEnumerator;

    // The /Count entry of the root, 0 when it is missing, like PDPageTree.getCount. This may differ from the number
    // of pages that the walk finds: EnumeratedCount is that number.
    property Count: Integer read GetCount;
    property EnumeratedCount: Integer read GetEnumeratedCount;
    property CosObject: TCosDictionary read FRoot;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.Null,
  Pdf4D.Cos.PdfArray;

{ TPDPageTreeEnumerator }

constructor TPDPageTreeEnumerator.Create(const Tree: TPDPageTree);
begin
  FTree := Tree;
  FIndex := -1;
end;

function TPDPageTreeEnumerator.MoveNext: Boolean;
begin
  Inc(FIndex);
  Result := (FIndex < FTree.EnumeratedCount);
end;

function TPDPageTreeEnumerator.GetCurrent: TPDPage;
begin
  Result := FTree.Get(FIndex);
end;

{ TPDPageTree }

constructor TPDPageTree.Create(const Root: TCosDictionary; const Context: TPDDocumentContext);
begin
  inherited Create;
  FRoot := Root;
  FContext := Context;
  // PDFBOX-3154: a page dictionary instead of a page tree
  FIsSinglePage := HasTypeName(Root, TCosNames.Page);
  FDictionaries := TList<TCosDictionary>.Create;
  FPages := TObjectList<TPDPage>.Create(True);
  FEmptyPages := TObjectList<TCosDictionary>.Create(True);
end;

destructor TPDPageTree.Destroy;
begin
  FIndexes.Free;
  FEmptyPages.Free;
  FPages.Free;
  FDictionaries.Free;
  inherited;
end;

class function TPDPageTree.HasTypeName(const Node: TCosDictionary; const TypeName: string): Boolean;
begin
  var Value: TCosBase;
  Result := (Assigned(Node) and Node.TryGetDictionaryObject(TCosNames.Type_, Value) and (Value is TCosName) and
             (TCosName(Value).Name = TypeName));
end;

// Some files do not have Pages as the type, so the presence of Kids counts too
class function TPDPageTree.IsPageTreeNode(const Node: TCosDictionary): Boolean;
begin
  Result := (Assigned(Node) and (HasTypeName(Node, TCosNames.Pages) or Node.ContainsKey(TCosNames.Kids)));
end;

class function TPDPageTree.TryGetInheritableAttribute(const Node: TCosDictionary; const Key: string; out Value: TCosBase): Boolean;
begin
  Value := nil;
  Result := False;
  // The number of steps bounds the work and ends a cycle of /Parent entries, without a set of the nodes seen
  var Current := Node;
  var Steps := 0;
  while Assigned(Current) and (Steps < MaxInheritanceDepth) do
  begin
    Inc(Steps);
    if Current.TryGetDictionaryObject(Key, Value) then
    begin
      Exit(True);
    end;

    // getCOSDictionary(PARENT, P): /P is only looked at when there is no /Parent
    var ParentValue: TCosBase;
    if not Current.TryGetDictionaryObject(TCosNames.Parent, ParentValue) then
    begin
      Current.TryGetDictionaryObject(TCosNames.P, ParentValue);
    end;

    if (ParentValue is TCosDictionary) and HasTypeName(TCosDictionary(ParentValue), TCosNames.Pages) then
    begin
      Current := TCosDictionary(ParentValue);
    end
    else
    begin
      Current := nil;
    end;
  end;
end;

procedure TPDPageTree.LogWarning(const Message: string);
begin
  if Assigned(FContext.Log) then
  begin
    FContext.Log.Warning(Message);
  end;
end;

procedure TPDPageTree.LogError(const Message: string);
begin
  if Assigned(FContext.Log) then
  begin
    FContext.Log.Error(Message);
  end;
end;

function TPDPageTree.GetKids(const Node: TCosDictionary): TArray<TCosDictionary>;
begin
  var Kids: TCosArray;
  if not Node.TryGetCosArray(TCosNames.Kids, Kids) then
  begin
    // Probably a malformed PDF
    Exit(nil);
  end;

  const Found = TList<TCosDictionary>.Create;
  try
    for var Index := 0 to Kids.Count - 1 do
    begin
      const Kid = Kids.GetObject(Index);
      if Kid is TCosDictionary then
      begin
        Found.Add(TCosDictionary(Kid));
      end
      else if Kid is TCosNull then
      begin
        LogWarning('replaced null entry with an empty page');
        const EmptyPage = TCosDictionary.Create;
        FEmptyPages.Add(EmptyPage);
        EmptyPage.SetItem(TCosNames.Type_, TCosName.Create(TCosNames.Page));
        Found.Add(EmptyPage);
      end
      else
      begin
        LogWarning('COSDictionary expected, but got ' + Kid.ClassName);
      end;
    end;
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

procedure TPDPageTree.Enqueue(const Node: TCosDictionary; const Stack: TStack<TKidsFrame>);
begin
  if IsPageTreeNode(Node) then
  begin
    Stack.Push(TKidsFrame.Create(GetKids(Node), 0));
  end
  else if HasTypeName(Node, TCosNames.Page) then
  begin
    FDictionaries.Add(Node);
  end
  else
  begin
    LogError('Page skipped due to an invalid or missing type');
  end;
end;

// Port of PageIterator.enqueueKids, with a stack in place of the recursion. A node that is met twice is skipped, also
// the root (PDFBox only knows the nodes below it), so a /Kids that points back to the root gives no page twice.
procedure TPDPageTree.BuildList;
begin
  if FIsSinglePage then
  begin
    FDictionaries.Add(FRoot);
    Exit;
  end;

  const Visited = TDictionary<TCosDictionary, Boolean>.Create;
  const Stack = TStack<TKidsFrame>.Create;
  try
    Visited.Add(FRoot, True);
    Enqueue(FRoot, Stack);
    while Stack.Count > 0 do
    begin
      var Frame := Stack.Pop;
      if Frame.Value >= Length(Frame.Key) then
      begin
        Continue;
      end;

      const Kid = Frame.Key[Frame.Value];
      Frame.Value := Frame.Value + 1;
      Stack.Push(Frame);

      if Visited.ContainsKey(Kid) then
      begin
        LogError('This page tree node has already been visited');
        Continue;
      end;

      if Kid.ContainsKey(TCosNames.Kids) then
      begin
        Visited.Add(Kid, True);
      end;
      Enqueue(Kid, Stack);
    end;
  finally
    Stack.Free;
    Visited.Free;
  end;
end;

procedure TPDPageTree.EnsureList;
begin
  if FIsListBuilt then
  begin
    Exit;
  end;

  FIsListBuilt := True;
  BuildList;
  FPages.Count := FDictionaries.Count;
end;

function TPDPageTree.GetCount: Integer;
begin
  if FIsSinglePage then
  begin
    Exit(1);
  end;
  Result := FRoot.GetInt(TCosNames.Count, 0);
end;

function TPDPageTree.GetEnumeratedCount: Integer;
begin
  EnsureList;
  Result := FDictionaries.Count;
end;

function TPDPageTree.Get(const Index: Integer): TPDPage;
begin
  EnsureList;
  if (Index < 0) or (Index >= FDictionaries.Count) then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('Page index %d is out of range, the page tree has %d pages', [Index, FDictionaries.Count]);
  end;

  Result := FPages[Index];
  if not Assigned(Result) then
  begin
    Result := TPDPage.Create(FDictionaries[Index], FContext);
    FPages[Index] := Result;
  end;
end;

function TPDPageTree.IndexOf(const Page: TCosDictionary): Integer;
begin
  EnsureList;
  if not Assigned(FIndexes) then
  begin
    FIndexes := TDictionary<TCosDictionary, Integer>.Create;
    for var Index := 0 to FDictionaries.Count - 1 do
    begin
      FIndexes.TryAdd(FDictionaries[Index], Index);
    end;
  end;

  if not FIndexes.TryGetValue(Page, Result) then
  begin
    raise EPdfParseException.Create('The page is not part of the page tree');
  end;
end;

function TPDPageTree.GetEnumerator: TPDPageTreeEnumerator;
begin
  Result := TPDPageTreeEnumerator.Create(Self);
end;

end.
