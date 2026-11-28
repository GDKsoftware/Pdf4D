// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Extract.Images;

interface

uses
  Pdf4D.Api.Page.Interfaces,
  Pdf4D.Extract.Images.Interfaces;

type
  TPdfImages = class
  public
    // The images of a page with their place. The result keeps the page, and so its document, alive. The page must come from this
    // library; anything else raises EArgumentException.
    class function OfPage(const Page: IPdfPage): IPdfPageImages; static;
  end;

implementation

uses
  System.SysUtils,
  Pdf4D.Api.DocumentModel.Interfaces,
  Pdf4D.Extract.GraphicsCollector,
  Pdf4D.Model.Page;

type
  TPdfPageImages = class(TInterfacedObject, IPdfPageImages)
  private
    FPage: IPdfPage;
    FModelPage: IPdfPageModel;
    FImages: TArray<TPdfImageInfo>;
    FIsListed: Boolean;

    procedure List;
    procedure CheckIndex(const Index: Integer);

  public
    constructor Create(const Page: IPdfPage; const ModelPage: IPdfPageModel);

    function Images: TArray<TPdfImageInfo>;
    function GetData(const Index: Integer): TPdfImageData;
    function GetAllData: TArray<TPdfImageData>;
  end;

resourcestring
  DataNotAvailable = 'The data of an image is not available';

{ TPdfImages }

class function TPdfImages.OfPage(const Page: IPdfPage): IPdfPageImages;
begin
  if not Assigned(Page) then
  begin
    raise EArgumentNilException.Create('Page');
  end;

  var ModelPage: IPdfPageModel;
  if not Supports(Page, IPdfPageModel, ModelPage) then
  begin
    raise EArgumentException.Create('The page does not come from this library');
  end;

  Result := TPdfPageImages.Create(Page, ModelPage);
end;

{ TPdfPageImages }

constructor TPdfPageImages.Create(const Page: IPdfPage; const ModelPage: IPdfPageModel);
begin
  inherited Create;
  FPage := Page;
  FModelPage := ModelPage;
end;

procedure TPdfPageImages.List;
begin
  if FIsListed then
  begin
    Exit;
  end;

  const Collector = TPdfGraphicsCollector.Create(FPage.Index);
  try
    Collector.ProcessPage(FModelPage.ModelPage);
    FImages := Collector.Images;
  finally
    Collector.Free;
  end;
  FIsListed := True;
end;

procedure TPdfPageImages.CheckIndex(const Index: Integer);
begin
  List;
  const IsInRange = ((Index >= 0) and (Index < Length(FImages)));
  if not IsInRange then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('Image index %d is outside the %d images of the page', [Index, Length(FImages)]);
  end;
end;

function TPdfPageImages.Images: TArray<TPdfImageInfo>;
begin
  List;
  Result := Copy(FImages);
end;

// The data is made by a later step; until then every image answers that there is none
function TPdfPageImages.GetData(const Index: Integer): TPdfImageData;
begin
  CheckIndex(Index);
  Result := Default(TPdfImageData);
  Result.Format := TPdfImageDataFormat.None;
  Result.Error := DataNotAvailable;
end;

function TPdfPageImages.GetAllData: TArray<TPdfImageData>;
begin
  List;
  Result := nil;
  SetLength(Result, Length(FImages));
  for var Index := 0 to High(Result) do
  begin
    Result[Index] := GetData(Index);
  end;
end;

end.
