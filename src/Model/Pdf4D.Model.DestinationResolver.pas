// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/interactive/documentnavigation/destination/PDDestination.java,
// PDNamedDestination.java and PDPageDestination.java, pdfbox/src/main/java/org/apache/pdfbox/pdmodel/PDDocumentCatalog.java
// (findNamedDestinationPage), PDDestinationNameTreeNode.java, PDDocumentNameDictionary.java and
// PDDocumentNameDestinationDictionary.java (3.0.8), the read side
unit Pdf4D.Model.DestinationResolver;

interface

uses
  System.SysUtils,
  Pdf4D.Common.Log,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Model.NameTree,
  Pdf4D.Model.PageTree;

type
  TPDPageTreeProvider = reference to function: TPDPageTree;

  // What PDDestination.create makes of a value
  TPDDestinationKind = (None, Page, Named);

  // Finds the page that a destination points to. The catalog owns it: it lives as long as the document and keeps the
  // name tree of the named destinations, so many lookups do not read the same leaf of the tree again and again. This
  // is a separate unit, and not part of Pdf4D.Model.Destination, because the catalog needs it and that unit needs
  // the document.
  TPDDestinationResolver = class
  private
    FCatalog: TCosDictionary;
    FPageTree: TPDPageTreeProvider;
    FLog: TPdfLog;
    FDestinationsTree: TPDNameTreeNode;
    FIsTreeLooked: Boolean;

    function GetDestinationsTree: TPDNameTreeNode;
    function TryFindInDestsDictionary(const Name: string; out Destination: TCosArray): Boolean;
    function TryGetPageIndexOfArray(const Destination: TCosArray; const NotInTreeIsMinusOne: Boolean; out PageIndex: Integer): Boolean;
    class function IndexInTree(const Tree: TPDPageTree; const Page: TCosDictionary; const NotInTreeIsMinusOne: Boolean): Integer; static;
    class function ConvertTreeValue(const Value: TCosBase): TCosBase; static;

  public
    // The catalog is not owned, PageTree gives the page tree of the document. Log may be nil.
    constructor Create(const Catalog: TCosDictionary; const PageTree: TPDPageTreeProvider; const Log: TPdfLog);
    destructor Destroy; override;

    // Port of PDDestination.create. Kind is None for a null. The array is the explicit destination of a page
    // destination, Name the name of a named destination. Raises EPdfParseException for an array with a type that is not
    // a destination type, an array that is too short and any value that is not an array, string or name (IOException in
    // PDFBox). A dictionary is no destination here, only the value of a named destination can be one.
    class function Classify(const Value: TCosBase; out Destination: TCosArray; out Name: string): TPDDestinationKind; static;

    // Port of PDDocumentCatalog.findNamedDestinationPage: the name tree /Names /Dests (or /Dests of the catalog as a
    // tree) first, then /Dests of the catalog as a dictionary of destinations. The destination is the array of a page
    // destination. False when there is none. Raises EPdfParseException like Classify and like TPDNameTreeNode.
    function TryFindNamedDestination(const Name: string; out Destination: TCosArray): Boolean;

    // Port of PDOutlineItem.findDestinationPage for a destination value, and the index of the page in the page tree
    // that it gives. The value is an explicit destination (an array, the page is a page dictionary or a page number
    // that counts from 0), a name or a string, which name a destination of the document. False when there is no
    // page, the page is not in the page tree or anything is wrong with the value (PDFBox throws then).
    function TryResolvePageIndex(const Value: TCosBase; out PageIndex: Integer): Boolean; overload;
    // With NotInTreeIsMinusOne a page that is not in the page tree gives True and index -1, as PDPageTree.indexOf does
    function TryResolvePageIndex(const Value: TCosBase; const NotInTreeIsMinusOne: Boolean; out PageIndex: Integer): Boolean; overload;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.Null,
  Pdf4D.Cos.Number,
  Pdf4D.Cos.PdfString;

{ TPDDestinationResolver }

constructor TPDDestinationResolver.Create(const Catalog: TCosDictionary; const PageTree: TPDPageTreeProvider; const Log: TPdfLog);
begin
  inherited Create;
  FCatalog := Catalog;
  FPageTree := PageTree;
  FLog := Log;
end;

destructor TPDDestinationResolver.Destroy;
begin
  FDestinationsTree.Free;
  inherited;
end;

class function TPDDestinationResolver.Classify(const Value: TCosBase; out Destination: TCosArray; out Name: string): TPDDestinationKind;
begin
  Destination := nil;
  Name := '';
  if (not Assigned(Value)) or (Value is TCosNull) then
  begin
    Exit(TPDDestinationKind.None);
  end;

  if (Value is TCosArray) and (TCosArray(Value).Count > 1) and (TCosArray(Value).GetObject(1) is TCosName) then
  begin
    const TypeName = TCosName(TCosArray(Value).GetObject(1)).Name;
    if (TypeName <> TCosNames.Fit) and (TypeName <> TCosNames.FitB) and (TypeName <> TCosNames.FitH) and
       (TypeName <> TCosNames.FitBH) and (TypeName <> TCosNames.FitV) and (TypeName <> TCosNames.FitBV) and
       (TypeName <> TCosNames.FitR) and (TypeName <> TCosNames.XYZ) then
    begin
      raise EPdfParseException.CreateFmt('Unknown destination type: %s', [TypeName]);
    end;
    Destination := TCosArray(Value);
    Exit(TPDDestinationKind.Page);
  end;

  if Value is TCosString then
  begin
    Name := TCosString(Value).GetString;
    Exit(TPDDestinationKind.Named);
  end;

  if Value is TCosName then
  begin
    Name := TCosName(Value).Name;
    Exit(TPDDestinationKind.Named);
  end;

  raise EPdfParseException.Create('Error: can''t convert the value to a destination');
end;

// Port of PDDestinationNameTreeNode.convertCOSToPD
class function TPDDestinationResolver.ConvertTreeValue(const Value: TCosBase): TCosBase;
begin
  var Destination := Value;
  if Value is TCosDictionary then
  begin
    // The destination is sometimes stored in /D of a dictionary
    if not TCosDictionary(Value).TryGetDictionaryObject(TCosNames.D, Destination) then
    begin
      Destination := nil;
    end;
  end;

  var PageArray: TCosArray;
  var Name: string;
  if Classify(Destination, PageArray, Name) = TPDDestinationKind.Page then
  begin
    Result := PageArray;
  end
  else
  begin
    // PDFBOX-5975: an entry that is no page destination is no value
    Result := nil;
  end;
end;

function TPDDestinationResolver.GetDestinationsTree: TPDNameTreeNode;
begin
  if not FIsTreeLooked then
  begin
    FIsTreeLooked := True;
    var NamesDictionary: TCosDictionary;
    if FCatalog.TryGetCosDictionary(TCosNames.Names, NamesDictionary) then
    begin
      // The catalog has /Dests as well sometimes
      var Root: TCosDictionary;
      if NamesDictionary.TryGetCosDictionary(TCosNames.Dests, Root) or FCatalog.TryGetCosDictionary(TCosNames.Dests, Root) then
      begin
        FDestinationsTree := TPDNameTreeNode.Create(Root, ConvertTreeValue, FLog);
      end;
    end;
  end;
  Result := FDestinationsTree;
end;

// Port of PDDocumentNameDestinationDictionary.getDestination for /Dests of the catalog
function TPDDestinationResolver.TryFindInDestsDictionary(const Name: string; out Destination: TCosArray): Boolean;
begin
  Destination := nil;
  var Dests: TCosDictionary;
  var Item: TCosBase;
  if not (FCatalog.TryGetCosDictionary(TCosNames.Dests, Dests) and Dests.TryGetDictionaryObject(Name, Item)) then
  begin
    Exit(False);
  end;

  if Item is TCosDictionary then
  begin
    // "a dictionary with a D entry whose value is such an array"
    var Inner: TCosBase;
    if not (TCosDictionary(Item).ContainsKey(TCosNames.D) and TCosDictionary(Item).TryGetDictionaryObject(TCosNames.D, Inner)) then
    begin
      Exit(False);
    end;
    Item := Inner;
  end
  else if not (Item is TCosArray) then
  begin
    Exit(False);
  end;

  // A name or a string is a named destination, which PDFBox cannot cast to a page destination
  var Unused: string;
  Result := (Classify(Item, Destination, Unused) = TPDDestinationKind.Page);
end;

function TPDDestinationResolver.TryFindNamedDestination(const Name: string; out Destination: TCosArray): Boolean;
begin
  Destination := nil;
  const Tree = GetDestinationsTree;
  if Assigned(Tree) then
  begin
    var Found: TCosBase;
    if Tree.TryGetValue(Name, Found) then
    begin
      Destination := TCosArray(Found);
      Exit(True);
    end;
  end;
  Result := TryFindInDestsDictionary(Name, Destination);
end;

class function TPDDestinationResolver.IndexInTree(const Tree: TPDPageTree; const Page: TCosDictionary; const NotInTreeIsMinusOne: Boolean): Integer;
begin
  try
    Result := Tree.IndexOf(Page);
  except
    on EPdfParseException do
    begin
      if not NotInTreeIsMinusOne then
      begin
        raise;
      end;
      Result := -1;
    end;
  end;
end;

// Port of PDPageDestination.getPage and getPageNumber, and the lookup of the page in the page tree
function TPDDestinationResolver.TryGetPageIndexOfArray(const Destination: TCosArray; const NotInTreeIsMinusOne: Boolean; out PageIndex: Integer): Boolean;
begin
  PageIndex := -1;
  if Destination.Count = 0 then
  begin
    Exit(False);
  end;

  const Tree = FPageTree();
  const Page = Destination.GetObject(0);
  if Page is TCosDictionary then
  begin
    PageIndex := IndexInTree(Tree, TCosDictionary(Page), NotInTreeIsMinusOne);
    Exit(True);
  end;

  // Malformed, a local destination needs a page object: a page number is for a remote destination. PDFBox still
  // takes the page of that number, and -1 is the number that means no page.
  if Page is TCosNumber then
  begin
    const PageNumber = TCosNumber(Page).IntValue;
    if PageNumber <> -1 then
    begin
      PageIndex := Tree.IndexOf(Tree.Get(PageNumber).CosObject);
      Exit(True);
    end;
  end;
  Result := False;
end;

function TPDDestinationResolver.TryResolvePageIndex(const Value: TCosBase; out PageIndex: Integer): Boolean;
begin
  Result := TryResolvePageIndex(Value, False, PageIndex);
end;

function TPDDestinationResolver.TryResolvePageIndex(const Value: TCosBase; const NotInTreeIsMinusOne: Boolean; out PageIndex: Integer): Boolean;
begin
  PageIndex := -1;
  try
    var PageArray: TCosArray;
    var Name: string;
    case Classify(Value, PageArray, Name) of
      TPDDestinationKind.Page:
        Result := TryGetPageIndexOfArray(PageArray, NotInTreeIsMinusOne, PageIndex);
      TPDDestinationKind.Named:
        Result := (TryFindNamedDestination(Name, PageArray) and TryGetPageIndexOfArray(PageArray, NotInTreeIsMinusOne, PageIndex));
    else
      Result := False;
    end;
  except
    on EPdfParseException do
    begin
      Result := False;
    end;
    on EArgumentOutOfRangeException do
    begin
      Result := False;
    end;
  end;
end;

end.
