// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.TextDocuments;

interface

uses
  System.SysUtils,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Model.Document,
  Pdf4D.Tests.PdfBuilder;

type
  // Small documents with one page, some fonts in its resources and a content stream, for the tests of fonts and text
  TTextTestDocuments = class
  public
    const HelveticaF1 = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>';
    // The object number of the first font, which is /F1. Further fonts are /F2 on 11, and so on.
    const FirstFontObject = 10;
    const ContentObject = 4;
    const Separator = '|';

    // The catalog is object 1, the page tree 2, the page 3 and its content stream 4. FontObjects holds the bodies of the
    // font objects, separated by Separator: the first is /F1 (object 10), the second /F2 (11) and so on. The builder has no
    // other objects, so a test can add descriptors and font files from number 20. The caller owns the builder.
    class function NewBuilder(const FontObjects, Content: string): TTestPdfBuilder; static;

    // A font file stream (object Number) with the entries of Dictionary, for instance '/Length1 10 /Length2 20'
    class procedure AddFontFile(const Builder: TTestPdfBuilder; const Number: Integer; const Dictionary: string; const Data: TBytes); static;

    // The font dictionary /Name of the first page. Raises when the page has no such font.
    class function FontDictionary(const Document: TPDDocument; const Name: string): TCosDictionary; static;
  end;

implementation

uses
  System.Classes,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Names,
  Pdf4D.Model.Page,
  Pdf4D.Model.Tests.Support;

{ TTextTestDocuments }

class function TTextTestDocuments.NewBuilder(const FontObjects, Content: string): TTestPdfBuilder;
begin
  const Bodies = FontObjects.Split([Separator]);
  const FontEntries = TStringBuilder.Create;
  try
    for var Index := 0 to High(Bodies) do
    begin
      FontEntries.AppendFormat('/F%d %d 0 R ', [Index + 1, FirstFontObject + Index]);
    end;

    Result := TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
    try
      Result.AddObject(3, Format('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents %d 0 R ' +
                                 '/Resources << /Font << %s >> >> >>', [ContentObject, FontEntries.ToString]));
      Result.AddStreamObject(ContentObject, '', TEncoding.ASCII.GetBytes(Content));
      for var Index := 0 to High(Bodies) do
      begin
        if Bodies[Index].Trim <> '' then
        begin
          Result.AddObject(FirstFontObject + Index, Bodies[Index]);
        end;
      end;
    except
      Result.Free;
      raise;
    end;
  finally
    FontEntries.Free;
  end;
end;

class procedure TTextTestDocuments.AddFontFile(const Builder: TTestPdfBuilder; const Number: Integer; const Dictionary: string; const Data: TBytes);
begin
  Builder.AddStreamObject(Number, Dictionary, Data);
end;

class function TTextTestDocuments.FontDictionary(const Document: TPDDocument; const Name: string): TCosDictionary;
begin
  var Resources: TCosDictionary;
  var Fonts: TCosDictionary;
  const Found = (Document.Pages.Get(0).TryGetResources(Resources) and Resources.TryGetCosDictionary(TCosNames.Font, Fonts) and
                 Fonts.TryGetCosDictionary(Name, Result));
  if not Found then
  begin
    raise EArgumentException.CreateFmt('The first page has no font %s', [Name]);
  end;
end;

end.
