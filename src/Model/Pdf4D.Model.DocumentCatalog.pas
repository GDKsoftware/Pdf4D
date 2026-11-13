// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/PDDocumentCatalog.java (3.0.8), the read side
unit Pdf4D.Model.DocumentCatalog;

interface

uses
  System.SysUtils,
  Pdf4D.Common.Log,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Model.AcroForm,
  Pdf4D.Model.DestinationResolver,
  Pdf4D.Model.Outline,
  Pdf4D.Model.PageTree;

type
  // The catalog (/Root). It holds the dictionary and does not own it. It owns what it gives out: the page tree, the
  // destination resolver, the outline and the form. The other entries are given as the dictionary or stream they are.
  TPDDocumentCatalog = class
  private
    FRoot: TCosDictionary;
    FLog: TPdfLog;
    FPages: TPDPageTree;
    FResolver: TPDDestinationResolver;
    FOutline: TPDDocumentOutline;
    FAcroForm: TPDAcroForm;

    function GetPages: TPDPageTree;
    function GetDestinationResolver: TPDDestinationResolver;

  public
    // Log may be nil
    constructor Create(const Root: TCosDictionary; const Log: TPdfLog);
    destructor Destroy; override;

    // The page tree, which the catalog owns. Raises EPdfParseException when /Pages is no dictionary.
    property Pages: TPDPageTree read GetPages;

    // Port of getDocumentOutline. The outline belongs to the catalog. False when /Outlines is no dictionary.
    function TryGetOutline(out Outline: TPDDocumentOutline): Boolean;
    function TryGetPageLabels(out PageLabels: TCosDictionary): Boolean;
    // Port of getAcroForm(null), without fix ups. The form belongs to the catalog. False when /AcroForm is no dictionary.
    function TryGetAcroForm(out AcroForm: TPDAcroForm): Boolean;
    function TryGetNames(out Names: TCosDictionary): Boolean;
    function TryGetDests(out Dests: TCosDictionary): Boolean;
    function TryGetMetadata(out Metadata: TCosStream): Boolean;

    // The /Version name of the catalog, empty when there is none
    function Version: string;

    // Finds the pages of destinations and the named destinations of the document, which the catalog owns
    property DestinationResolver: TPDDestinationResolver read GetDestinationResolver;

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
  FAcroForm.Free;
  FOutline.Free;
  FResolver.Free;
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

function TPDDocumentCatalog.GetDestinationResolver: TPDDestinationResolver;
begin
  if not Assigned(FResolver) then
  begin
    FResolver := TPDDestinationResolver.Create(FRoot,
      function: TPDPageTree
      begin
        Result := Pages;
      end, FLog);
  end;
  Result := FResolver;
end;

function TPDDocumentCatalog.TryGetOutline(out Outline: TPDDocumentOutline): Boolean;
begin
  if not Assigned(FOutline) then
  begin
    var Root: TCosDictionary;
    if FRoot.TryGetCosDictionary(TCosNames.Outlines, Root) then
    begin
      FOutline := TPDDocumentOutline.Create(Root, DestinationResolver);
    end;
  end;
  Outline := FOutline;
  Result := Assigned(FOutline);
end;

function TPDDocumentCatalog.TryGetPageLabels(out PageLabels: TCosDictionary): Boolean;
begin
  Result := FRoot.TryGetCosDictionary(TCosNames.PageLabels, PageLabels);
end;

function TPDDocumentCatalog.TryGetAcroForm(out AcroForm: TPDAcroForm): Boolean;
begin
  if not Assigned(FAcroForm) then
  begin
    var Dictionary: TCosDictionary;
    if FRoot.TryGetCosDictionary(TCosNames.AcroForm, Dictionary) then
    begin
      FAcroForm := TPDAcroForm.Create(Dictionary, FLog);
    end;
  end;
  AcroForm := FAcroForm;
  Result := Assigned(FAcroForm);
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
