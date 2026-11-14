// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Model.Tests.Support;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Pdf4D.Common.Defines,
  Pdf4D.Model.Document,
  Pdf4D.Tests.PdfBuilder;

type
  // Makes small documents for the tests of the model and collects what the loader logs
  TModelTestDocuments = class
  private
    FLogLines: TList<string>;
    FDocument: TPDDocument;
    FMaxDecodedStreamSize: Int64;

  public
    constructor Create;
    destructor Destroy; override;

    // The builder holds a catalog as object 1, /Pages 2 0 R is the page tree root. The caller owns the builder.
    class function NewBuilder(const PagesBody: string): TTestPdfBuilder; static;

    // A builder with PageCount pages, the objects 10 and up, and a catalog that has CatalogExtra behind /Pages. The objects
    // 3 to 9 are free for the test. The caller owns the builder.
    class function NewBuilderWithPages(const PageCount: Integer; const CatalogExtra: string): TTestPdfBuilder; static;

    // Loads the file that the builder makes. HeaderMinor is the digit after "1." in the header.
    function Open(const Builder: TTestPdfBuilder; const HeaderMinor: Char = '7'): TPDDocument;

    function HasLogLine(const Fragment: string): Boolean;

    // Zero keeps the default limit on the size of decoded streams
    property MaxDecodedStreamSize: Int64 read FMaxDecodedStreamSize write FMaxDecodedStreamSize;
    property Document: TPDDocument read FDocument;
    property LogLines: TList<string> read FLogLines;
  end;

implementation

{ TModelTestDocuments }

constructor TModelTestDocuments.Create;
begin
  inherited Create;
  FLogLines := TList<string>.Create;
end;

destructor TModelTestDocuments.Destroy;
begin
  FDocument.Free;
  FLogLines.Free;
  inherited;
end;

class function TModelTestDocuments.NewBuilder(const PagesBody: string): TTestPdfBuilder;
begin
  Result := TTestPdfBuilder.Create;
  try
    Result.AddObject(1, '<< /Type /Catalog /Pages 2 0 R >>');
    Result.AddObject(2, PagesBody);
    Result.SetRoot(1);
  except
    Result.Free;
    raise;
  end;
end;

class function TModelTestDocuments.NewBuilderWithPages(const PageCount: Integer; const CatalogExtra: string): TTestPdfBuilder;
begin
  Result := TTestPdfBuilder.Create;
  try
    const Kids = TStringBuilder.Create;
    try
      for var Index := 0 to PageCount - 1 do
      begin
        Kids.Append(10 + Index).Append(' 0 R ');
        Result.AddObject(10 + Index, '<< /Type /Page /Parent 2 0 R >>');
      end;
      Result.AddObject(2, Format('<< /Type /Pages /Kids [%s] /Count %d >>', [Kids.ToString, PageCount]));
    finally
      Kids.Free;
    end;
    Result.AddObject(1, Format('<< /Type /Catalog /Pages 2 0 R %s >>', [CatalogExtra]));
    Result.SetRoot(1);
  except
    Result.Free;
    raise;
  end;
end;

function TModelTestDocuments.Open(const Builder: TTestPdfBuilder; const HeaderMinor: Char): TPDDocument;
begin
  var Data := Builder.Build(TXrefStyle.Table);
  // "%PDF-1.7" is the first line
  Data[7] := Ord(HeaderMinor);

  var Options := TPdfLoadOptions.Default;
  if FMaxDecodedStreamSize > 0 then
  begin
    Options.MaxDecodedStreamSize := FMaxDecodedStreamSize;
  end;
  Options.OnLog :=
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      FLogLines.Add(Message);
    end;

  FDocument.Free;
  FDocument := nil;
  FDocument := TPDDocument.Load(TBytesStream.Create(Data), True, Options);
  Result := FDocument;
end;

function TModelTestDocuments.HasLogLine(const Fragment: string): Boolean;
begin
  Result := False;
  for var Line in FLogLines do
  begin
    Result := (Result or Line.Contains(Fragment));
  end;
end;

end.
