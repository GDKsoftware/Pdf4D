// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/PDDocument.java (3.0.8), the read side
unit Pdf4D.Model.Document;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Document,
  Pdf4D.Encryption.AccessPermission,
  Pdf4D.Model.DocumentCatalog,
  Pdf4D.Model.DocumentInformation,
  Pdf4D.Model.PageTree;

type
  // A loaded document. It owns the TCosDocument and, through it, the source stream when asked to. Everything that it
  // gives out (catalog, information, page tree, pages and the dictionaries below them) lives as long as the document.
  TPDDocument = class
  private
    FCosDocument: TCosDocument;
    FCatalog: TPDDocumentCatalog;
    FInformation: TPDDocumentInformation;
    // Stand ins for a trailer without /Root or /Info, as PDFBox creates them
    FSubstitutes: TObjectList<TCosDictionary>;

    constructor Create(const CosDocument: TCosDocument);

    function CreateSubstitute: TCosDictionary;
    function GetCatalog: TPDDocumentCatalog;
    function GetInformation: TPDDocumentInformation;
    function GetPages: TPDPageTree;
    function GetVersion: Single;
    function GetIsEncrypted: Boolean;
    function GetAccessPermission: TPdfAccessPermission;
    class function TryParseVersion(const Text: string; out Value: Single): Boolean; static;

  public
    destructor Destroy; override;

    // The caller owns the result. The document owns Source when OwnsSource is true, also when the load fails. A file
    // that cannot be loaded raises an EPdfException descendant.
    class function Load(const Source: TStream; const OwnsSource: Boolean; const Options: TPdfLoadOptions): TPDDocument; static;

    property CosDocument: TCosDocument read FCosDocument;
    property Catalog: TPDDocumentCatalog read GetCatalog;
    property DocumentInformation: TPDDocumentInformation read GetInformation;
    property Pages: TPDPageTree read GetPages;
    // Port of PDDocument.getVersion: the version of the header, or the /Version of the catalog when that is higher.
    // As in PDFBox the catalog is only looked at when the header says 1.4 or higher.
    property Version: Single read GetVersion;
    property IsEncrypted: Boolean read GetIsEncrypted;
    property AccessPermission: TPdfAccessPermission read GetAccessPermission;
  end;

implementation

uses
  System.Math,
  Pdf4D.Cos.Names,
  Pdf4D.Parser.Pdf;

const
  FirstVersionWithCatalogEntry: Single = 1.4;

{ TPDDocument }

constructor TPDDocument.Create(const CosDocument: TCosDocument);
begin
  inherited Create;
  FCosDocument := CosDocument;
  FSubstitutes := TObjectList<TCosDictionary>.Create(True);
end;

destructor TPDDocument.Destroy;
begin
  FInformation.Free;
  FCatalog.Free;
  FCosDocument.Free;
  FSubstitutes.Free;
  inherited;
end;

class function TPDDocument.Load(const Source: TStream; const OwnsSource: Boolean; const Options: TPdfLoadOptions): TPDDocument;
begin
  Result := TPDDocument.Create(TPdfParser.Parse(Source, OwnsSource, Options));
end;

function TPDDocument.CreateSubstitute: TCosDictionary;
begin
  Result := TCosDictionary.Create;
  FSubstitutes.Add(Result);
end;

function TPDDocument.GetCatalog: TPDDocumentCatalog;
begin
  if not Assigned(FCatalog) then
  begin
    var Root: TCosDictionary;
    if not FCosDocument.Trailer.TryGetCosDictionary(TCosNames.Root, Root) then
    begin
      Root := CreateSubstitute;
    end;
    FCatalog := TPDDocumentCatalog.Create(Root, FCosDocument.Log);
  end;
  Result := FCatalog;
end;

function TPDDocument.GetInformation: TPDDocumentInformation;
begin
  if not Assigned(FInformation) then
  begin
    var Info: TCosDictionary;
    if not FCosDocument.Trailer.TryGetCosDictionary(TCosNames.Info, Info) then
    begin
      Info := CreateSubstitute;
    end;
    FInformation := TPDDocumentInformation.Create(Info);
  end;
  Result := FInformation;
end;

function TPDDocument.GetPages: TPDPageTree;
begin
  Result := Catalog.Pages;
end;

function TPDDocument.GetIsEncrypted: Boolean;
begin
  Result := Assigned(FCosDocument.Encryption);
end;

function TPDDocument.GetAccessPermission: TPdfAccessPermission;
begin
  Result := FCosDocument.AccessPermission;
end;

// Port of Float.parseFloat for the values that can be a version
class function TPDDocument.TryParseVersion(const Text: string; out Value: Single): Boolean;
begin
  var Trimmed := Text.Trim;
  if (Trimmed <> '') and CharInSet(Trimmed[Trimmed.Length], ['f', 'F', 'd', 'D']) then
  begin
    Trimmed := Trimmed.Substring(0, Trimmed.Length - 1);
  end;

  Result := (Trimmed <> '');
  for var Character in Trimmed do
  begin
    Result := (Result and CharInSet(Character, ['0'..'9', '.', '+', '-', 'e', 'E']));
  end;

  var Parsed: Double;
  Result := (Result and TryStrToFloat(Trimmed, Parsed, TFormatSettings.Invariant));
  if Result then
  begin
    Value := Parsed;
  end;
end;

function TPDDocument.GetVersion: Single;
begin
  const HeaderVersion = FCosDocument.Version;
  if HeaderVersion < FirstVersionWithCatalogEntry then
  begin
    Exit(HeaderVersion);
  end;

  // There may be a second version in the catalog, and the most recent one is the right one
  var CatalogVersion: Single := -1;
  const CatalogText = Catalog.Version;
  if (CatalogText <> '') and not TryParseVersion(CatalogText, CatalogVersion) then
  begin
    CatalogVersion := -1;
    FCosDocument.Log.Error('Can''t extract the version number of the document catalog.');
  end;
  Result := Max(CatalogVersion, HeaderVersion);
end;

end.
