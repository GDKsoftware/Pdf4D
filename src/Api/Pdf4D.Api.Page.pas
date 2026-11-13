unit Pdf4D.Api.Page;

interface

uses
  Pdf4D.Api.DocumentHandle,
  Pdf4D.Api.Page.Interfaces,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Model.Page,
  Pdf4D.Model.Rectangle;

type
  TPdfPage = class(TInterfacedObject, IPdfPage)
  private
    FHandle: IPdfDocumentHandle;
    FPage: TPDPage;
    FIndex: Integer;

  public
    constructor Create(const Handle: IPdfDocumentHandle; const Page: TPDPage; const Index: Integer);

    function Index: Integer;
    function Label_: string;
    function MediaBox: TPdfRectangle;
    function CropBox: TPdfRectangle;
    function BleedBox: TPdfRectangle;
    function TrimBox: TPdfRectangle;
    function ArtBox: TPdfRectangle;
    function Rotation: Integer;
    function CosObject: TCosDictionary;
  end;

implementation

{ TPdfPage }

constructor TPdfPage.Create(const Handle: IPdfDocumentHandle; const Page: TPDPage; const Index: Integer);
begin
  inherited Create;
  FHandle := Handle;
  FPage := Page;
  FIndex := Index;
end;

function TPdfPage.Index: Integer;
begin
  Result := FIndex;
end;

function TPdfPage.Label_: string;
begin
  Result := FHandle.PageLabel(FIndex);
end;

function TPdfPage.MediaBox: TPdfRectangle;
begin
  Result := FPage.MediaBox;
end;

function TPdfPage.CropBox: TPdfRectangle;
begin
  Result := FPage.CropBox;
end;

function TPdfPage.BleedBox: TPdfRectangle;
begin
  Result := FPage.BleedBox;
end;

function TPdfPage.TrimBox: TPdfRectangle;
begin
  Result := FPage.TrimBox;
end;

function TPdfPage.ArtBox: TPdfRectangle;
begin
  Result := FPage.ArtBox;
end;

function TPdfPage.Rotation: Integer;
begin
  Result := FPage.Rotation;
end;

function TPdfPage.CosObject: TCosDictionary;
begin
  Result := FPage.CosObject;
end;

end.
