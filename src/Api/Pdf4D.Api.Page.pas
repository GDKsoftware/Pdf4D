// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Api.Page;

interface

uses
  Pdf4D.Api.DocumentHandle,
  Pdf4D.Api.Page.Interfaces,
  Pdf4D.Api.TextLayout.Interfaces,
  Pdf4D.Api.TextOptions,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Model.Page,
  Pdf4D.Model.Rectangle;

type
  TPdfPage = class(TInterfacedObject, IPdfPage)
  private
    FHandle: IPdfDocumentHandle;
    FPage: TPDPage;
    FIndex: Integer;

    function OptionsOfPage: TPdfTextOptions;

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
    function ExtractText: string;
    function ExtractTextWithPositions: IPdfPositionedText;
    function TextLayout: IPdfTextLayout; overload;
    function TextLayout(const Options: TPdfTextLayoutOptions): IPdfTextLayout; overload;
    function Links: TArray<TPdfLink>;
    function CosObject: TCosDictionary;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Pdf4D.Api.TextLayout,
  Pdf4D.Text.Layout;

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

function TPdfPage.ExtractText: string;
begin
  const Options = OptionsOfPage;

  const Writer = TStringWriter.Create;
  try
    FHandle.WriteText(Writer, Options);
    Result := Writer.ToString;
  finally
    Writer.Free;
  end;
end;

function TPdfPage.OptionsOfPage: TPdfTextOptions;
begin
  Result := TPdfTextOptions.Default;
  Result.StartPage := FIndex + 1;
  Result.EndPage := FIndex + 1;
end;

function TPdfPage.ExtractTextWithPositions: IPdfPositionedText;
begin
  Result := TPdfPositionedTextResult.Create(FHandle.ExtractPositioned(OptionsOfPage));
end;

function TPdfPage.TextLayout: IPdfTextLayout;
begin
  Result := TextLayout(TPdfTextLayoutOptions.Default);
end;

function TPdfPage.TextLayout(const Options: TPdfTextLayoutOptions): IPdfTextLayout;
begin
  var TextOptions := OptionsOfPage;
  TextOptions.SortByPosition := True;

  const Positioned = FHandle.ExtractPositioned(TextOptions);
  try
    Result := TPdfTextLayout.Create(TPdfTextLayoutBuilder.Build(Positioned, FIndex, Options), Positioned.Text);
  finally
    Positioned.Free;
  end;
end;

function TPdfPage.Links: TArray<TPdfLink>;
begin
  Result := FHandle.ReadLinks(FPage, FIndex);
end;

function TPdfPage.CosObject: TCosDictionary;
begin
  Result := FPage.CosObject;
end;

end.
