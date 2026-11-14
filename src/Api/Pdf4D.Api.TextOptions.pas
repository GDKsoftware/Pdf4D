// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Api.TextOptions;

interface

uses
  Pdf4D.Api.Outline.Interfaces;

type
  // The settings of the text extraction. They are the settings of PDFTextStripper in PDFBox, with the same defaults: use
  // Default and change what you need.
  TPdfTextOptions = record
    // Sort the text by its position on the page
    SortByPosition: Boolean;
    // The first and the last page, one based and inclusive
    StartPage: Integer;
    EndPage: Integer;
    // When set, the text starts at the page of the bookmark or ends at it. The bookmark must come from the same document.
    StartBookmark: IPdfOutlineItem;
    EndBookmark: IPdfOutlineItem;
    // Skip a character that repeats another one at (nearly) the same place, which is how some producers fake bold text
    SuppressDuplicateOverlappingText: Boolean;
    // Write the text of the articles (threads) of a page separately
    ShouldSeparateByBeads: Boolean;
    // Use the line separator for the paragraph end, the page start and the article start and end
    AddMoreFormatting: Boolean;
    IgnoreContentStreamSpaceGlyphs: Boolean;
    LineSeparator: string;
    WordSeparator: string;
    ParagraphStart: string;
    ParagraphEnd: string;
    PageStart: string;
    PageEnd: string;
    ArticleStart: string;
    ArticleEnd: string;
    SpacingTolerance: Single;
    AverageCharTolerance: Single;
    IndentThreshold: Single;
    DropThreshold: Single;

    class function Default: TPdfTextOptions; static;
  end;

implementation

uses
  System.SysUtils;

{ TPdfTextOptions }

class function TPdfTextOptions.Default: TPdfTextOptions;
begin
  Result.SortByPosition := False;
  Result.StartPage := 1;
  Result.EndPage := MaxInt;
  Result.StartBookmark := nil;
  Result.EndBookmark := nil;
  Result.SuppressDuplicateOverlappingText := True;
  Result.ShouldSeparateByBeads := True;
  Result.AddMoreFormatting := False;
  Result.IgnoreContentStreamSpaceGlyphs := False;
  Result.LineSeparator := sLineBreak;
  Result.WordSeparator := ' ';
  Result.ParagraphStart := '';
  Result.ParagraphEnd := '';
  Result.PageStart := '';
  Result.PageEnd := sLineBreak;
  Result.ArticleStart := '';
  Result.ArticleEnd := '';
  Result.SpacingTolerance := 0.5;
  Result.AverageCharTolerance := 0.3;
  Result.IndentThreshold := 2.0;
  Result.DropThreshold := 2.5;
end;

end.
