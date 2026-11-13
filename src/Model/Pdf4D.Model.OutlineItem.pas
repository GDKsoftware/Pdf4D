// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/interactive/documentnavigation/outline/PDOutlineNode.java,
// PDOutlineItem.java and PDOutlineItemIterator.java (3.0.8), the read side
unit Pdf4D.Model.OutlineItem;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Model.DestinationResolver;

type
  TPDOutlineItem = class;
  TPDOutlineItems = class;

  // The enumerator of the children of a node: the first child and then the /Next siblings. It stops at a sibling that it
  // had already given, so a cycle in /Next cannot make it run for ever. A for in loop frees it.
  TPDOutlineItemEnumerator = class
  private
    FStart: TPDOutlineItem;
    FCurrent: TPDOutlineItem;
    FVisited: TDictionary<TCosDictionary, Boolean>;

  public
    constructor Create(const Start: TPDOutlineItem);
    destructor Destroy; override;

    function MoveNext: Boolean;

    property Current: TPDOutlineItem read FCurrent;
  end;

  // Port of PDOutlineNode. A node does not own its dictionary, and the items that it gives out belong to the outline
  // that it is a part of.
  TPDOutlineNode = class
  private
    FDictionary: TCosDictionary;
    FItems: TPDOutlineItems;

  protected
    function TryGetItem(const Key: string; out Item: TPDOutlineItem): Boolean;

  public
    constructor Create(const Dictionary: TCosDictionary; const Items: TPDOutlineItems);

    // Port of hasChildren
    function HasChildren: Boolean;
    function TryGetFirstChild(out Item: TPDOutlineItem): Boolean;
    function TryGetLastChild(out Item: TPDOutlineItem): Boolean;

    // The /Count entry, 0 when it is missing
    function GetOpenCount: Integer;
    // Port of isNodeOpen: the /Count is above 0
    function IsNodeOpen: Boolean; virtual;

    // Port of children()
    function GetEnumerator: TPDOutlineItemEnumerator;
    function Children: TArray<TPDOutlineItem>;

    property CosObject: TCosDictionary read FDictionary;
  end;

  TPDOutlineItem = class(TPDOutlineNode)
  public
    // Port of getTitle. False when there is no /Title string.
    function TryGetTitle(out Title: string): Boolean;
    // The title, empty when there is none
    function Title: string;

    function TryGetNextSibling(out Item: TPDOutlineItem): Boolean;
    function TryGetPreviousSibling(out Item: TPDOutlineItem): Boolean;

    // Port of findDestinationPage with the index of the page in the page tree: through /Dest, or when there is none
    // through the destination /D of an action /A with /S /GoTo. The destination is an explicit destination or a named
    // destination. False when there is no destination, no page, the page is not in the page tree or anything is
    // wrong (PDFBox throws then).
    function TryGetPageIndex(out PageIndex: Integer): Boolean;
  end;

  // The items of one outline: one object for each dictionary, so an item that is met again is the same object. It owns
  // them and it knows where destinations are resolved.
  TPDOutlineItems = class
  private
    FItems: TObjectDictionary<TCosDictionary, TPDOutlineItem>;
    FResolver: TPDDestinationResolver;

  public
    // The resolver is not owned
    constructor Create(const Resolver: TPDDestinationResolver);
    destructor Destroy; override;

    function GetItem(const Dictionary: TCosDictionary): TPDOutlineItem;

    property Resolver: TPDDestinationResolver read FResolver;
  end;

implementation

uses
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Names;

{ TPDOutlineItemEnumerator }

constructor TPDOutlineItemEnumerator.Create(const Start: TPDOutlineItem);
begin
  inherited Create;
  FStart := Start;
  FVisited := TDictionary<TCosDictionary, Boolean>.Create;
end;

destructor TPDOutlineItemEnumerator.Destroy;
begin
  FVisited.Free;
  inherited;
end;

function TPDOutlineItemEnumerator.MoveNext: Boolean;
begin
  if not Assigned(FStart) then
  begin
    Exit(False);
  end;

  if not Assigned(FCurrent) then
  begin
    FCurrent := FStart;
  end
  else
  begin
    var Sibling: TPDOutlineItem;
    if not (FCurrent.TryGetNextSibling(Sibling) and not FVisited.ContainsKey(Sibling.CosObject)) then
    begin
      Exit(False);
    end;
    FCurrent := Sibling;
  end;

  FVisited.Add(FCurrent.CosObject, True);
  Result := True;
end;

{ TPDOutlineNode }

constructor TPDOutlineNode.Create(const Dictionary: TCosDictionary; const Items: TPDOutlineItems);
begin
  inherited Create;
  FDictionary := Dictionary;
  FItems := Items;
end;

function TPDOutlineNode.TryGetItem(const Key: string; out Item: TPDOutlineItem): Boolean;
begin
  Item := nil;
  var Target: TCosDictionary;
  Result := FDictionary.TryGetCosDictionary(Key, Target);
  if Result then
  begin
    Item := FItems.GetItem(Target);
  end;
end;

function TPDOutlineNode.HasChildren: Boolean;
begin
  var Unused: TCosDictionary;
  Result := FDictionary.TryGetCosDictionary(TCosNames.First, Unused);
end;

function TPDOutlineNode.TryGetFirstChild(out Item: TPDOutlineItem): Boolean;
begin
  Result := TryGetItem(TCosNames.First, Item);
end;

function TPDOutlineNode.TryGetLastChild(out Item: TPDOutlineItem): Boolean;
begin
  Result := TryGetItem(TCosNames.Last, Item);
end;

function TPDOutlineNode.GetOpenCount: Integer;
begin
  Result := FDictionary.GetInt(TCosNames.Count, 0);
end;

function TPDOutlineNode.IsNodeOpen: Boolean;
begin
  Result := (GetOpenCount > 0);
end;

function TPDOutlineNode.GetEnumerator: TPDOutlineItemEnumerator;
begin
  var First: TPDOutlineItem;
  if not TryGetFirstChild(First) then
  begin
    First := nil;
  end;
  Result := TPDOutlineItemEnumerator.Create(First);
end;

function TPDOutlineNode.Children: TArray<TPDOutlineItem>;
begin
  const Found = TList<TPDOutlineItem>.Create;
  try
    for var Item in Self do
    begin
      Found.Add(Item);
    end;
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

{ TPDOutlineItem }

function TPDOutlineItem.TryGetTitle(out Title: string): Boolean;
begin
  Result := CosObject.TryGetString(TCosNames.Title, Title);
end;

function TPDOutlineItem.Title: string;
begin
  if not TryGetTitle(Result) then
  begin
    Result := '';
  end;
end;

function TPDOutlineItem.TryGetNextSibling(out Item: TPDOutlineItem): Boolean;
begin
  Result := TryGetItem(TCosNames.Next, Item);
end;

function TPDOutlineItem.TryGetPreviousSibling(out Item: TPDOutlineItem): Boolean;
begin
  Result := TryGetItem(TCosNames.Prev, Item);
end;

function TPDOutlineItem.TryGetPageIndex(out PageIndex: Integer): Boolean;
begin
  PageIndex := -1;
  var Destination: TCosBase;
  if not CosObject.TryGetDictionaryObject(TCosNames.Dest, Destination) then
  begin
    var Action: TCosDictionary;
    if not (CosObject.TryGetCosDictionary(TCosNames.A, Action) and
            (Action.GetNameAsString(TCosNames.S, '') = TCosNames.GoTo_) and
            Action.TryGetDictionaryObject(TCosNames.D, Destination)) then
    begin
      Exit(False);
    end;
  end;

  Result := FItems.Resolver.TryResolvePageIndex(Destination, PageIndex);
end;

{ TPDOutlineItems }

constructor TPDOutlineItems.Create(const Resolver: TPDDestinationResolver);
begin
  inherited Create;
  FResolver := Resolver;
  FItems := TObjectDictionary<TCosDictionary, TPDOutlineItem>.Create([doOwnsValues]);
end;

destructor TPDOutlineItems.Destroy;
begin
  FItems.Free;
  inherited;
end;

function TPDOutlineItems.GetItem(const Dictionary: TCosDictionary): TPDOutlineItem;
begin
  if not FItems.TryGetValue(Dictionary, Result) then
  begin
    Result := TPDOutlineItem.Create(Dictionary, Self);
    FItems.Add(Dictionary, Result);
  end;
end;

end.
