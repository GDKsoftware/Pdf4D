// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.GraphicsDocuments;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Tests.PdfBuilder;

type
  // Small documents with one page of 200 x 200 pt, for the tests of the renderer. The object keeps the streams of the documents
  // it opened, so release every document (and renderer) before freeing it.
  TGraphicsDocuments = class
  private
    FStreams: TObjectList<TBytesStream>;

  public
    const PageSize = 200;

    constructor Create;
    destructor Destroy; override;

    // Resources is the text between << >> of /Resources, for instance '/ExtGState << /GS1 << /ca 0.5 >> >>'. PageEntries is added to
    // the page dictionary, for instance '/Rotate 90'.
    function Open(const Content, Resources: string; const PageEntries: string = ''): IPdfDocument; overload;
    function Open(const Content: TBytes; const Resources: string; const PageEntries: string = ''): IPdfDocument; overload;
    // The builder of such a document, for a test that adds objects (from number 5). The caller owns the builder.
    class function NewBuilder(const Content: TBytes; const Resources: string; const PageEntries: string = ''): TTestPdfBuilder; static;
    // Loads what the builder makes. The caller still owns the builder.
    function Open(const Builder: TTestPdfBuilder): IPdfDocument; overload;
  end;

implementation

uses
  Pdf4D.Api.Document,
  Pdf4D.Common.Defines,
  Pdf4D.Model.Tests.Support;

const
  PageBody = '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %d %d] /Contents 4 0 R /Resources << %s >> %s >>';
  ContentObject = 4;

{ TGraphicsDocuments }

constructor TGraphicsDocuments.Create;
begin
  inherited Create;
  FStreams := TObjectList<TBytesStream>.Create(True);
end;

destructor TGraphicsDocuments.Destroy;
begin
  FStreams.Free;
  inherited;
end;

function TGraphicsDocuments.Open(const Content, Resources: string; const PageEntries: string): IPdfDocument;
begin
  Result := Open(TEncoding.ASCII.GetBytes(Content), Resources, PageEntries);
end;

function TGraphicsDocuments.Open(const Content: TBytes; const Resources: string; const PageEntries: string): IPdfDocument;
begin
  const Builder = NewBuilder(Content, Resources, PageEntries);
  try
    Result := Open(Builder);
  finally
    Builder.Free;
  end;
end;

class function TGraphicsDocuments.NewBuilder(const Content: TBytes; const Resources: string; const PageEntries: string): TTestPdfBuilder;
begin
  Result := TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  try
    Result.AddObject(3, Format(PageBody, [PageSize, PageSize, Resources, PageEntries]));
    Result.AddStreamObject(ContentObject, '', Content);
  except
    Result.Free;
    raise;
  end;
end;

function TGraphicsDocuments.Open(const Builder: TTestPdfBuilder): IPdfDocument;
begin
  const Stream = TBytesStream.Create(Builder.Build(TXrefStyle.Table));
  FStreams.Add(Stream);
  Result := TPdfDocument.Load(Stream, TPdfLoadOptions.Default);
end;

end.
