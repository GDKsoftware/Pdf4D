// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdfparser/PDFParser.java (3.0.8)
unit Pdf4D.Parser.Pdf;

interface

uses
  System.SysUtils,
  System.Classes,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Document,
  Pdf4D.Parser.Cos;

type
  // Loads a document: the header, the xref chain and the trailer. The objects follow on demand.
  TPdfParser = class(TCosParser)
  private
    procedure InitialParse;
    procedure Load;

  public
    // Reads the document from Source. The document owns the source when OwnsSource is true, and owns the parser. The
    // caller owns the result. A file that cannot be loaded raises an EPdfException; the source is then freed when
    // OwnsSource is true.
    class function Parse(const Source: TStream; const OwnsSource: Boolean; const Options: TPdfLoadOptions): TCosDocument; static;
  end;

implementation

uses
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.IO.RandomAccessRead;

{ TPdfParser }

procedure TPdfParser.InitialParse;
begin
  const Trailer = RetrieveTrailer;

  var Root: TCosDictionary;
  if not Trailer.TryGetCosDictionary(TCosNames.Root, Root) then
  begin
    raise EPdfParseException.Create('Missing root object specification in trailer.');
  end;

  // In some PDFs the type value "Catalog" is missing in the root object
  if not Root.ContainsKey(TCosNames.Type_) then
  begin
    Root.SetItem(TCosNames.Type_, TCosName.Create(TCosNames.Catalog));
  end;

  CheckPages(Root);
end;

procedure TPdfParser.Load;
begin
  // PDFBOX-1922: read the version header and rewind
  if not (ParsePdfHeader or ParseFdfHeader) then
  begin
    Document.Log.Warning('Error: Header doesn''t contain versioninfo');
  end;
  InitialParse;
end;

class function TPdfParser.Parse(const Source: TStream; const OwnsSource: Boolean; const Options: TPdfLoadOptions): TCosDocument;
begin
  var Access: TRandomAccessRead;
  try
    Access := TRandomAccessRead.Create(Source, OwnsSource);
  except
    if OwnsSource then
    begin
      Source.Free;
    end;
    raise;
  end;

  Result := TCosDocument.Create(Access, Options);
  try
    const Parser = TPdfParser.Create(Result);
    Result.SetResolver(Parser, Parser);
    Parser.Load;
  except
    on Failure: Exception do
    begin
      FreeAndNil(Result);
      if TPdfFailure.IsInputFailure(Failure) then
      begin
        raise EPdfParseException.CreateFmt('The file could not be loaded: %s', [Failure.Message]);
      end;
      raise;
    end;
  end;
end;

end.
