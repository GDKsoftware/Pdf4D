// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Api.Page.Interfaces;

interface

uses
  Pdf4D.Api.TextLayout.Interfaces,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Model.Rectangle;

type
  // A page of a document. The page keeps its document alive.
  IPdfPage = interface
    ['{4B1D6C52-7A0E-4F8B-9D35-1E6A2C8F5B01}']

    // Zero based position in the page tree
    function Index: Integer;
    // The page label ('1', 'iv', 'A-3'), empty when the document has no /PageLabels or the label cannot be made
    function Label_: string;

    function MediaBox: TPdfRectangle;
    function CropBox: TPdfRectangle;
    function BleedBox: TPdfRectangle;
    function TrimBox: TPdfRectangle;
    function ArtBox: TPdfRectangle;
    function Rotation: Integer;

    // The text of this page only, with the default options
    function ExtractText: string;
    // The text of this page with the place of every character, with the default options
    function ExtractTextWithPositions: IPdfPositionedText;
    // The words, segments and lines of this page. The text is read with SortByPosition set, whatever the order in the file.
    function TextLayout: IPdfTextLayout; overload;
    function TextLayout(const Options: TPdfTextLayoutOptions): IPdfTextLayout; overload;

    // The page dictionary of the inner layer. It stays valid only as long as this interface (or any other interface
    // of the same document) is alive.
    function CosObject: TCosDictionary;
  end;

implementation

end.
