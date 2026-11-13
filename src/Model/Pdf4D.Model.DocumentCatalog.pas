// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/PDDocumentCatalog.java (3.0.8), the read side
unit Pdf4D.Model.DocumentCatalog;

interface

uses
  System.SysUtils,
  Pdf4D.Common.Log,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Model.PageTree;

type
  // The catalog (/Root). It holds the dictionary and does not own it. The sub dictionaries are given as they are,
  // the classes for outlines, forms and so on come with the tasks that need them.
  TPDDocumentCatalog = class
  private
    FRoot: TCosDictionary;
    FLog: TPdfLog;
    FPages: TPDPageTree;

    function GetPages: TPDPageTree;

  public
    // Log may be nil
    constructor Create(const Root: TCosDictionary; const Log: TPdfLog);
    destructor Destroy; override;

    // The page tree, which the catalog owns. Raises EPdfParseException when /Pages is no dictionary.
    property Pages: TPDPageTree read GetPages;

    function TryGetOutline(out Outline: TCosDictionary): Boolean;
    function TryGetPageLabels(out PageLabels: TCosDictionary): Boolean;
    function TryGetAcroForm(out AcroForm: TCosDictionary): Boolean;
    function TryGetNames(out Names: TCosDictionary): Boolean;
    function TryGetDests(out Dests: TCosDictionary): Boolean;
    function TryGetMetadata(out Metadata: TCosStream): Boolean;

    // The /Version name of the catalog, empty when there is none
    function Version: string;

    property CosObject: TCosDictionary read FRoot;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Names;

{ TPDDocumentCatalog }

constructor TPDDocumentCatalog.Create(const Root: TCosDictionary; const Log: TPdfLog);
begin
  inherited Create;
  FRoot := Root;
  FLog := Log;
end;

destructor TPDDocumentCatalog.Destroy;
begin
  FPages.Free;
  inherited;
end;

function TPDDocumentCatalog.GetPages: TPDPageTree;
begin
  if not Assigned(FPages) then
  begin
    var PagesRoot: TCosDictionary;
    if not FRoot.TryGetCosDictionary(TCosNames.Pages, PagesRoot) then
    begin
      raise EPdfParseException.Create('The document catalog has no page tree');
    end;
    FPages := TPDPageTree.Create(PagesRoot, FLog);
  end;
  Result := FPages;
end;

function TPDDocumentCatalog.TryGetOutline(out Outline: TCosDictionary): Boolean;
begin
  Result := FRoot.TryGetCosDictionary(TCosNames.Outlines, Outline);
end;

function TPDDocumentCatalog.TryGetPageLabels(out PageLabels: TCosDictionary): Boolean;
begin
  Result := FRoot.TryGetCosDictionary(TCosNames.PageLabels, PageLabels);
end;

function TPDDocumentCatalog.TryGetAcroForm(out AcroForm: TCosDictionary): Boolean;
begin
  Result := FRoot.TryGetCosDictionary(TCosNames.AcroForm, AcroForm);
end;

function TPDDocumentCatalog.TryGetNames(out Names: TCosDictionary): Boolean;
begin
  Result := FRoot.TryGetCosDictionary(TCosNames.Names, Names);
end;

function TPDDocumentCatalog.TryGetDests(out Dests: TCosDictionary): Boolean;
begin
  Result := FRoot.TryGetCosDictionary(TCosNames.Dests, Dests);
end;

function TPDDocumentCatalog.TryGetMetadata(out Metadata: TCosStream): Boolean;
begin
  Result := FRoot.TryGetCosStream(TCosNames.Metadata, Metadata);
end;

function TPDDocumentCatalog.Version: string;
begin
  Result := FRoot.GetNameAsString(TCosNames.Version, '');
end;

end.
