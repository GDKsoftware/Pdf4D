// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Api.TextLayout.Interfaces;

interface

uses
  System.Types,
  Pdf4D.Common.Quad,
  Pdf4D.Text.Layout;

type
  TPdfQuad = Pdf4D.Common.Quad.TPdfQuad;
  TPdfTextLayoutOptions = Pdf4D.Text.Layout.TPdfLayoutOptions;

  // A piece of text with its place on a page. Coordinates are in PDF user space: absolute (the lower left corner of the crop box
  // is added), and not rotated by /Rotate.
  TPdfTextFragment = record
    PageIndex: Integer;
    Text: string;
    Quads: TArray<TPdfQuad>;
    // The 1-based range of the fragment in the text it came from, in UTF-16 code units. For a word, segment or line of a text layout
    // that is IPdfTextLayout.Text. Both are 0 for the result of Locate.
    Start, Length: Integer;
  end;

  // The text of the document, or of a page, with the place of every character. The result is a copy: it does not depend on the
  // document and stays valid after it is released.
  IPdfPositionedText = interface
    ['{3E7A91C4-5B28-4D60-9F13-A8C2D6E04B57}']

    // The same text as ExtractText gives with the same options
    function Text: string;
    // The places of the characters Start to Start + Length - 1 (1-based), one fragment per page and one quad per line. A range outside
    // the text raises EArgumentOutOfRangeException.
    function Locate(const Start, Length: Integer): TArray<TPdfTextFragment>;
  end;

  // The words, segments and lines of one page, in reading order. The layout is a copy and does not depend on the document.
  IPdfTextLayout = interface
    ['{C41B8E27-0D95-4A3F-B6E8-72F5A1D9C360}']

    function PageIndex: Integer;
    // The text of the page (read with SortByPosition set) that Start and Length of the words, segments and lines refer to
    function Text: string;
    function Words: TArray<TPdfTextFragment>;
    function Segments: TArray<TPdfTextFragment>;
    function Lines: TArray<TPdfTextFragment>;
    // The segment or word whose quad contains the point (PDF user space), for hover
    function TryFindSegmentAt(const Point: TPointF; out Fragment: TPdfTextFragment): Boolean;
    function TryFindWordAt(const Point: TPointF; out Fragment: TPdfTextFragment): Boolean;
  end;

implementation

end.
