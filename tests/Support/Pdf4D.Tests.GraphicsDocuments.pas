// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.GraphicsDocuments;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Common.Defines,
  Pdf4D.Tests.PdfBuilder;

type
  // Small documents with one page of 200 x 200 pt, for the tests of the renderer. The object keeps the streams of the documents
  // it opened, so release every document (and renderer) before freeing it.
  TGraphicsDocuments = class
  private
    FStreams: TObjectList<TBytesStream>;
    FLogLines: TList<string>;
    FAllLogLines: TList<string>;

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
    // The same with the load limits of LoadOptions; its OnLog is replaced by the log of this object
    function Open(const Builder: TTestPdfBuilder; const LoadOptions: TPdfLoadOptions): IPdfDocument; overload;

    // The warnings and errors that the documents opened by this object logged, as 'Warning: text'
    property LogLines: TList<string> read FLogLines;
    // Every line that the documents logged, debug lines included, as 'Debug: text'
    property AllLogLines: TList<string> read FAllLogLines;
  end;

implementation

uses
  Pdf4D.Api.Document,
  Pdf4D.Model.Tests.Support;

const
  PageBody = '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %d %d] /Contents 4 0 R /Resources << %s >> %s >>';
  ContentObject = 4;
  LevelNames: array[TPdfLogLevel] of string = ('Debug', 'Info', 'Warning', 'Error');

{ TGraphicsDocuments }

constructor TGraphicsDocuments.Create;
begin
  inherited Create;
  FStreams := TObjectList<TBytesStream>.Create(True);
  FLogLines := TList<string>.Create;
  FAllLogLines := TList<string>.Create;
end;

destructor TGraphicsDocuments.Destroy;
begin
  FAllLogLines.Free;
  FLogLines.Free;
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
  Result := Open(Builder, TPdfLoadOptions.Default);
end;

function TGraphicsDocuments.Open(const Builder: TTestPdfBuilder; const LoadOptions: TPdfLoadOptions): IPdfDocument;
begin
  const Stream = TBytesStream.Create(Builder.Build(TXrefStyle.Table));
  FStreams.Add(Stream);
  var Options := LoadOptions;
  Options.OnLog := procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      const Line = Format('%s: %s', [LevelNames[Level], Message]);
      FAllLogLines.Add(Line);
      if Level >= TPdfLogLevel.Warning then
      begin
        FLogLines.Add(Line);
      end;
    end;
  Result := TPdfDocument.Load(Stream, Options);
end;

end.
