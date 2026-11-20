// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.PatternDocuments;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Tests.GraphicsDocuments;

type
  // A tiling pattern of a test: the entries of its dictionary besides /Type and /PatternType, and its content stream
  TTilingSource = record
    Entries: string;
    Content: string;

    class function Create(const Entries, Content: string): TTilingSource; static;
    // /PaintType, a square /BBox of Size points at the origin and the same step
    class function Square(const PaintType: Integer; const Size: string; const Content: string): TTilingSource; static;
  end;

  // Pages of 200 x 200 pt whose resources name the tiling patterns /P1, /P2, ... (objects 5, 6, ...)
  TPatternDocuments = class(TGraphicsDocuments)
  public
    const FirstPatternObject = 5;

    // ExtraResources is added to the page resources, for instance '/ColorSpace << /CsU [/Pattern /DeviceRGB] >>'
    function OpenWithPatterns(const PageContent: string; const Patterns: array of TTilingSource; const ExtraResources: string = ''): IPdfDocument;
  end;

implementation

uses
  Pdf4D.Tests.PdfBuilder;

{ TTilingSource }

class function TTilingSource.Create(const Entries, Content: string): TTilingSource;
begin
  Result.Entries := Entries;
  Result.Content := Content;
end;

class function TTilingSource.Square(const PaintType: Integer; const Size: string; const Content: string): TTilingSource;
begin
  Result.Entries := Format('/PaintType %d /TilingType 1 /BBox [0 0 %s %s] /XStep %s /YStep %s /Resources << >>', [PaintType, Size, Size, Size, Size]);
  Result.Content := Content;
end;

{ TPatternDocuments }

function TPatternDocuments.OpenWithPatterns(const PageContent: string; const Patterns: array of TTilingSource; const ExtraResources: string): IPdfDocument;
begin
  var Names := '';
  for var Index := 0 to High(Patterns) do
  begin
    Names := Names + Format('/P%d %d 0 R ', [Index + 1, FirstPatternObject + Index]);
  end;

  const Builder = TGraphicsDocuments.NewBuilder(TEncoding.ASCII.GetBytes(PageContent), Format('/Pattern << %s >> %s', [Names, ExtraResources]));
  try
    for var Index := 0 to High(Patterns) do
    begin
      Builder.AddStreamObject(FirstPatternObject + Index, '/Type /Pattern /PatternType 1 ' + Patterns[Index].Entries,
                              TEncoding.ASCII.GetBytes(Patterns[Index].Content));
    end;
    Result := Open(Builder);
  finally
    Builder.Free;
  end;
end;

end.
