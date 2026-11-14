// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/text/PDFTextStripper.java (3.0.8): pages, articles, actual text, the text
// positions, and the lines, words, paragraphs and normalisation of the written text
unit Pdf4D.Text.Stripper;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Model.Document,
  Pdf4D.Model.MarkedContent,
  Pdf4D.Model.OutlineItem,
  Pdf4D.Model.Page,
  Pdf4D.Model.PageTree,
  Pdf4D.Text.LegacyStreamEngine,
  Pdf4D.Text.OverlapColumn,
  Pdf4D.Text.TextPosition;

type
  // The ten list item formats of PDFTextStripper.LIST_ITEM_EXPRESSIONS, matched on the whole string and in the order of
  // PDFBox, without a regular expression engine
  TListItemPatterns = record
  private
    class function IsAsciiDigit(const Character: Char): Boolean; static;
    class function IsAllDigits(const Text: string; const First, Count: Integer): Boolean; static;
    class function IsAllIn(const Text: string; const First, Count: Integer; const Allowed: string): Boolean; static;
    class function IsSingleIn(const Text: string; const First, Count: Integer; const Lower, Upper: Char): Boolean; static;
    class function MatchesPattern(const Index: Integer; const Text: string): Boolean; static;

  public
    const NoMatch = -1;

    // The index of the first pattern that matches, or NoMatch
    class function IndexOf(const Text: string): Integer; static;
    class function Matches(const Text: string): Boolean; static;
  end;

  // The flags of a text position while the lines are written (PositionWrapper)
  TPositionWrapper = class
  private
    FPosition: TTextPosition;
    FIsLineStart: Boolean;
    FIsParagraphStart: Boolean;
    FIsHangingIndent: Boolean;
    FIsArticleStart: Boolean;

  public
    // The position is not owned
    constructor Create(const Position: TTextPosition);

    property Position: TTextPosition read FPosition;
    property IsLineStart: Boolean read FIsLineStart write FIsLineStart;
    property IsParagraphStart: Boolean read FIsParagraphStart write FIsParagraphStart;
    property IsHangingIndent: Boolean read FIsHangingIndent write FIsHangingIndent;
    property IsArticleStart: Boolean read FIsArticleStart write FIsArticleStart;
  end;

  // A text position of a line, or a word separator when Position is nil (LineItem)
  TLineItem = record
    Position: TTextPosition;
  end;

  TLine = TList<TLineItem>;

  // A word with the positions it was made of. The positions are not owned (WordWithTextPositions).
  TWordWithPositions = record
    Text: string;
    Positions: TArray<TTextPosition>;
  end;

  // What the word spacing rules of one position come to
  TPositionMetrics = record
    X: Single;
    Y: Single;
    Width: Single;
    Height: Single;
    WordSpacing: Single;
    DeltaSpace: Single;
    AverageCharWidth: Single;
  end;

  TPdfTextStripper = class(TLegacyPdfStreamEngine)
  private
    const MaxBeadsPerPage = 500;
    const MaxMarkedContentDepth = 1000;
    const SoftHyphen = #$00AD;

  private
    FLineSeparator: string;
    FWordSeparator: string;
    FParagraphStart: string;
    FParagraphEnd: string;
    FPageStart: string;
    FPageEnd: string;
    FArticleStart: string;
    FArticleEnd: string;
    FCurrentPageNo: Integer;
    FStartPage: Integer;
    FEndPage: Integer;
    FStartBookmark: TPDOutlineItem;
    FEndBookmark: TPDOutlineItem;
    FStartBookmarkPageNumber: Integer;
    FEndBookmarkPageNumber: Integer;
    FSuppressDuplicateOverlappingText: Boolean;
    FShouldSeparateByBeads: Boolean;
    FSortByPosition: Boolean;
    FAddMoreFormatting: Boolean;
    FIgnoreContentStreamSpaceGlyphs: Boolean;
    FIndentThreshold: Single;
    FDropThreshold: Single;
    FSpacingTolerance: Single;
    FAverageCharTolerance: Single;
    FBeadRectangles: TArray<TPDThreadBead>;
    FMarkedContents: TObjectList<TPDMarkedContent>;
    FUncountedMarkedContentDepth: Integer;
    FIsDepthLimitLogged: Boolean;
    FFirstActualTextPosition: Boolean;
    FHasActualText: Boolean;
    FActualText: string;
    FCharactersByArticle: TObjectList<TObjectList<TTextPosition>>;
    FCharacterListMapping: TObjectDictionary<string, TOverlapColumn>;
    FDocument: TPDDocument;
    FOutput: TTextWriter;
    FInParagraph: Boolean;
    FWrappers: TObjectList<TPositionWrapper>;
    FMaxYForLine: Single;
    FMinYTopForLine: Single;
    FEndOfLastTextX: Single;
    FLastWordSpacing: Single;
    FMaxHeightForLine: Single;
    FPreviousAveCharWidth: Single;
    FLastPosition: TPositionWrapper;
    FLastLineStartPosition: TPositionWrapper;
    FStartOfPage: Boolean;
    FStartOfArticle: Boolean;

    procedure ResetEngine;
    procedure WriteTextInGuard(const Document: TPDDocument; const Output: TTextWriter);
    procedure ApplyAddMoreFormatting;
    class function BookmarkPageNumber(const Bookmark: TPDOutlineItem): Integer; static;
    procedure DetermineBookmarkPages;
    function IsPageSelected: Boolean;
    procedure PrepareArticles(const Page: TPDPage);
    procedure FillBeadRectangles(const Page: TPDPage);
    procedure EnsureArticleLists(const NumberOfArticleSections: Integer);
    procedure ApplyActualText(const Text: TTextPosition);
    function IsOverlappingDuplicate(const Text: TTextPosition): Boolean;
    function FindArticleIndex(const X, Y: Single): Integer;
    procedure AddToArticle(const Text: TTextPosition; const ArticleIndex: Integer);
    class function BeadContains(const Bead: TPDThreadBead; const X, Y: Single): Boolean; static;

    class function JavaMin(const Left, Right: Single): Single; static;
    class function JavaMax(const Left, Right: Single): Single; static;
    // Math.round(value1 * value2 * 1000) / 1000f: the product with three decimals (multiplyFloat)
    class function MultiplyFloat(const Value1, Value2: Single): Single; static;
    class function Within(const First, Second, Variance: Single): Boolean; static;
    class function Overlap(const Y1, Height1, Y2, Height2: Single): Boolean; static;
    class function HasFontOrSizeChanged(const Current, Last: TTextPosition): Boolean; static;
    class procedure RemoveContainedSpaces(const TextList: TObjectList<TTextPosition>); static;
    class procedure SortPositions(const TextList: TObjectList<TTextPosition>); static;

    procedure ResetLineState;
    procedure WriteArticle(const TextList: TObjectList<TTextPosition>);
    procedure ProcessLinePosition(const Position: TTextPosition; const Line: TLine);
    function CalculateMetrics(const Position: TTextPosition): TPositionMetrics;
    function CalculateDeltaSpace(const WordSpacing: Single): Single;
    function CalculateAverageCharWidth(const Metrics: TPositionMetrics; const WordCharCount: Integer): Single;
    procedure StartNewLine(const Current: TPositionWrapper; const Line: TLine);
    function NeedsWordSeparator(const ExpectedStartOfNextWordX: Single; const Metrics: TPositionMetrics): Boolean;
    procedure ResetLineExtent;
    function CreateWord(const Text: string; const Positions: TArray<TTextPosition>): TWordWithPositions;
    function NormalizeWord(const Text: string): string;
    function Normalize(const Line: TLine): TArray<TWordWithPositions>;
    procedure WriteLine(const Line: TArray<TWordWithPositions>);
    function HandleLineSeparation(const Current, LastPosition, LastLineStartPosition: TPositionWrapper; const MaxHeightForLine: Single): TPositionWrapper;
    procedure IsParagraphSeparation(const Position, LastPosition, LastLineStartPosition: TPositionWrapper; const MaxHeightForLine: Single);
    function IsListItemRepeat(const Position, LastLineStartPosition: TPositionWrapper): Boolean;

  protected
    procedure StartDocument(const Document: TPDDocument); virtual;
    procedure EndDocument(const Document: TPDDocument); virtual;
    // PDFTextStripper.startPage. The properties StartPage and EndPage take the names of PDFBox's getters, so the hooks differ.
    procedure BeginPage(const Page: TPDPage); virtual;
    // PDFTextStripper.endPage
    procedure FinishPage(const Page: TPDPage); virtual;
    procedure StartArticle; overload; virtual;
    procedure StartArticle(const IsLeftToRight: Boolean); overload; virtual;
    procedure EndArticle; virtual;
    // Writes the text of the page that was processed: it sorts when asked, and it guesses where the line, word and paragraph
    // separators go from the positions
    procedure WritePage; virtual;
    procedure WriteLineSeparator; virtual;
    procedure WriteWordSeparator; virtual;
    procedure WriteCharacters(const Text: TTextPosition); virtual;
    procedure WriteString(const Text: string; const TextPositions: TArray<TTextPosition>); overload; virtual;
    procedure WriteString(const Text: string); overload; virtual;
    procedure WriteParagraphStart; virtual;
    procedure WriteParagraphEnd; virtual;
    procedure WriteParagraphSeparator; virtual;
    procedure WritePageStart; virtual;
    procedure WritePageEnd; virtual;
    // PDFBox runs bidi here. Pdf4D keeps the order of the file, so the word stays as it is.
    function HandleDirection(const Text: string): string; virtual;
    // Adds the position to the article that it lies in, unless it repeats a position that was shown already. The callee
    // becomes the owner of Text.
    procedure ProcessTextPosition(const Text: TTextPosition); override;

    // The text positions of the page, by article (the sections before, in and between the beads). Owned by the stripper.
    property CharactersByArticle: TObjectList<TObjectList<TTextPosition>> read FCharactersByArticle;
    property Document: TPDDocument read FDocument;
    property Output: TTextWriter read FOutput;

  public
    constructor Create;
    destructor Destroy; override;

    function GetText(const Document: TPDDocument): string;
    procedure WriteText(const Document: TPDDocument; const Output: TTextWriter);

    procedure ProcessPages(const Pages: TPDPageTree); virtual;
    procedure ProcessPage(const Page: TPDPage); override;
    procedure BeginMarkedContentSequence(const Tag: string; const Properties: TCosDictionary); override;
    procedure EndMarkedContentSequence; override;

    // 1-based, inclusive
    property StartPage: Integer read FStartPage write FStartPage;
    property EndPage: Integer read FEndPage write FEndPage;
    // Not owned. The pages from the page of the bookmark.
    property StartBookmark: TPDOutlineItem read FStartBookmark write FStartBookmark;
    property EndBookmark: TPDOutlineItem read FEndBookmark write FEndBookmark;
    property SortByPosition: Boolean read FSortByPosition write FSortByPosition;
    property ShouldSeparateByBeads: Boolean read FShouldSeparateByBeads write FShouldSeparateByBeads;
    property SuppressDuplicateOverlappingText: Boolean read FSuppressDuplicateOverlappingText write FSuppressDuplicateOverlappingText;
    property AddMoreFormatting: Boolean read FAddMoreFormatting write FAddMoreFormatting;
    property IgnoreContentStreamSpaceGlyphs: Boolean read FIgnoreContentStreamSpaceGlyphs write FIgnoreContentStreamSpaceGlyphs;
    property LineSeparator: string read FLineSeparator write FLineSeparator;
    property WordSeparator: string read FWordSeparator write FWordSeparator;
    property ParagraphStart: string read FParagraphStart write FParagraphStart;
    property ParagraphEnd: string read FParagraphEnd write FParagraphEnd;
    property PageStart: string read FPageStart write FPageStart;
    property PageEnd: string read FPageEnd write FPageEnd;
    property ArticleStart: string read FArticleStart write FArticleStart;
    property ArticleEnd: string read FArticleEnd write FArticleEnd;
    property SpacingTolerance: Single read FSpacingTolerance write FSpacingTolerance;
    property AverageCharTolerance: Single read FAverageCharTolerance write FAverageCharTolerance;
    property IndentThreshold: Single read FIndentThreshold write FIndentThreshold;
    property DropThreshold: Single read FDropThreshold write FDropThreshold;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  Pdf4D.Common.FloatGuard,
  Pdf4D.Content.Operators.MarkedContent,
  Pdf4D.Font.Base,
  Pdf4D.Text.IterativeMergeSort,
  Pdf4D.Text.TextPositionComparator,
  Pdf4D.Text.TimSort,
  Pdf4D.Text.UnicodeTables;

const
  DefaultIndentThreshold: Single = 2.0;
  DefaultDropThreshold: Single = 2.5;
  DefaultSpacingTolerance: Single = 0.5;
  DefaultAverageCharTolerance: Single = 0.3;
  NoPageNumber = -1;
  EndOfLastTextXResetValue: Single = -1;
  MaxYForLineResetValue: Single = -MaxSingle;
  ExpectedStartOfNextWordXResetValue: Single = -MaxSingle;
  MaxHeightForLineResetValue: Single = -1;
  MinYTopForLineResetValue: Single = MaxSingle;
  LastWordSpacingResetValue: Single = -1;
  SameLineTolerance: Single = 0.1;
  ListItemWidthFactor: Single = 0.25;
  RoundingFactor: Single = 1000;
  FirstPresentationForm = #$FB00;
  LastArabicPresentationFormA = #$FDFF;
  FirstArabicPresentationFormB = #$FE70;
  LastArabicPresentationFormB = #$FEFF;
  FirstHebrewForm = #$FB1D;
  ArabicLigatureAllah = #$FDF2;
  ArabicAlef = #$0627;
  ArabicAlefIsolated = #$FE8D;
  ArabicLamLamHeh = #$0644#$0644#$0647;
  ListItemPatternCount = 10;

{ TListItemPatterns }

class function TListItemPatterns.IsAsciiDigit(const Character: Char): Boolean;
begin
  Result := (Character >= '0') and (Character <= '9');
end;

class function TListItemPatterns.IsAllDigits(const Text: string; const First, Count: Integer): Boolean;
begin
  Result := Count > 0;
  for var Index := First to First + Count - 1 do
  begin
    if not IsAsciiDigit(Text[Index]) then
    begin
      Exit(False);
    end;
  end;
end;

class function TListItemPatterns.IsAllIn(const Text: string; const First, Count: Integer; const Allowed: string): Boolean;
begin
  Result := Count > 0;
  for var Index := First to First + Count - 1 do
  begin
    if Allowed.IndexOf(Text[Index]) < 0 then
    begin
      Exit(False);
    end;
  end;
end;

class function TListItemPatterns.IsSingleIn(const Text: string; const First, Count: Integer; const Lower, Upper: Char): Boolean;
begin
  Result := (Count = 1) and (Text[First] >= Lower) and (Text[First] <= Upper);
end;

class function TListItemPatterns.MatchesPattern(const Index: Integer; const Text: string): Boolean;
begin
  const Last = Text[Length(Text)];
  const BodyCount = Length(Text) - 1;
  case Index of
    0: Result := (Text = '.');
    1: Result := (Last = '.') and IsAllDigits(Text, 1, BodyCount);
    2: Result := (Length(Text) > 2) and (Text[1] = '[') and (Last = ']') and IsAllDigits(Text, 2, BodyCount - 1);
    3: Result := (Last = ')') and IsAllDigits(Text, 1, BodyCount);
    4: Result := (Last = '.') and IsSingleIn(Text, 1, BodyCount, 'A', 'Z');
    5: Result := (Last = '.') and IsSingleIn(Text, 1, BodyCount, 'a', 'z');
    6: Result := (Last = ')') and IsSingleIn(Text, 1, BodyCount, 'A', 'Z');
    7: Result := (Last = ')') and IsSingleIn(Text, 1, BodyCount, 'a', 'z');
    8: Result := (Last = '.') and IsAllIn(Text, 1, BodyCount, 'IVXL');
    9: Result := (Last = '.') and IsAllIn(Text, 1, BodyCount, 'ivxl');
  else
    Result := False;
  end;
end;

class function TListItemPatterns.IndexOf(const Text: string): Integer;
begin
  Result := NoMatch;
  if Text = '' then
  begin
    Exit;
  end;

  for var Index := 0 to ListItemPatternCount - 1 do
  begin
    if MatchesPattern(Index, Text) then
    begin
      Exit(Index);
    end;
  end;
end;

class function TListItemPatterns.Matches(const Text: string): Boolean;
begin
  Result := IndexOf(Text) <> NoMatch;
end;

{ TPositionWrapper }

constructor TPositionWrapper.Create(const Position: TTextPosition);
begin
  inherited Create;
  FPosition := Position;
end;

{ TPdfTextStripper }

constructor TPdfTextStripper.Create;
begin
  inherited Create;
  FLineSeparator := sLineBreak;
  FWordSeparator := ' ';
  FPageEnd := sLineBreak;
  FCurrentPageNo := 1;
  FStartPage := 1;
  FEndPage := MaxInt;
  FStartBookmarkPageNumber := NoPageNumber;
  FEndBookmarkPageNumber := NoPageNumber;
  FSuppressDuplicateOverlappingText := True;
  FShouldSeparateByBeads := True;
  FIndentThreshold := DefaultIndentThreshold;
  FDropThreshold := DefaultDropThreshold;
  FSpacingTolerance := DefaultSpacingTolerance;
  FAverageCharTolerance := DefaultAverageCharTolerance;
  FMarkedContents := TObjectList<TPDMarkedContent>.Create(True);
  FCharactersByArticle := TObjectList<TObjectList<TTextPosition>>.Create(True);
  FCharacterListMapping := TObjectDictionary<string, TOverlapColumn>.Create([doOwnsValues]);
  TMarkedContentOperators.Register(Self);
end;

destructor TPdfTextStripper.Destroy;
begin
  FCharacterListMapping.Free;
  FCharactersByArticle.Free;
  FMarkedContents.Free;
  inherited;
end;

function TPdfTextStripper.GetText(const Document: TPDDocument): string;
begin
  const Writer = TStringWriter.Create;
  try
    WriteText(Document, Writer);
    Result := Writer.ToString;
  finally
    Writer.Free;
  end;
end;

procedure TPdfTextStripper.ResetEngine;
begin
  FCurrentPageNo := 1;
  FDocument := nil;
  FCharactersByArticle.Clear;
  FCharacterListMapping.Clear;
  // PDFBox keeps these between runs, so that the state of an unbalanced BDC leaks into the next document
  FMarkedContents.Clear;
  FUncountedMarkedContentDepth := 0;
  FIsDepthLimitLogged := False;
  FHasActualText := False;
  FActualText := '';
  FFirstActualTextPosition := False;
end;

procedure TPdfTextStripper.WriteText(const Document: TPDDocument; const Output: TTextWriter);
begin
  const PreviousMask = TPdfFloatGuard.Enter;
  try
    WriteTextInGuard(Document, Output);
  finally
    TPdfFloatGuard.Leave(PreviousMask);
    FDocument := nil;
    FOutput := nil;
  end;
end;

procedure TPdfTextStripper.WriteTextInGuard(const Document: TPDDocument; const Output: TTextWriter);
begin
  ResetEngine;
  FDocument := Document;
  FOutput := Output;
  if FAddMoreFormatting then
  begin
    ApplyAddMoreFormatting;
  end;
  StartDocument(Document);
  ProcessPages(Document.Pages);
  EndDocument(Document);
end;

procedure TPdfTextStripper.ApplyAddMoreFormatting;
begin
  FParagraphEnd := FLineSeparator;
  FPageStart := FLineSeparator;
  FArticleStart := FLineSeparator;
  FArticleEnd := FLineSeparator;
end;

class function TPdfTextStripper.BookmarkPageNumber(const Bookmark: TPDOutlineItem): Integer;
begin
  var PageIndex: Integer;
  if Assigned(Bookmark) and Bookmark.TryGetPageIndex(PageIndex, True) then
  begin
    Result := PageIndex + 1;
  end
  else
  begin
    Result := NoPageNumber;
  end;
end;

procedure TPdfTextStripper.DetermineBookmarkPages;
begin
  FStartBookmarkPageNumber := BookmarkPageNumber(FStartBookmark);
  FEndBookmarkPageNumber := BookmarkPageNumber(FEndBookmark);

  const BothPointToNothing = ((FStartBookmarkPageNumber = NoPageNumber) and Assigned(FStartBookmark) and
                              (FEndBookmarkPageNumber = NoPageNumber) and Assigned(FEndBookmark));
  if BothPointToNothing and (FStartBookmark.CosObject = FEndBookmark.CosObject) then
  begin
    // The same bookmark twice that points nowhere: no text at all
    FStartBookmarkPageNumber := 0;
    FEndBookmarkPageNumber := 0;
  end;
end;

procedure TPdfTextStripper.ProcessPages(const Pages: TPDPageTree);
begin
  DetermineBookmarkPages;
  for var Page in Pages do
  begin
    if Page.HasContents then
    begin
      ProcessPage(Page);
    end;
    Inc(FCurrentPageNo);
  end;
end;

procedure TPdfTextStripper.StartDocument(const Document: TPDDocument);
begin
end;

procedure TPdfTextStripper.EndDocument(const Document: TPDDocument);
begin
end;

function TPdfTextStripper.IsPageSelected: Boolean;
begin
  Result := ((FCurrentPageNo >= FStartPage) and (FCurrentPageNo <= FEndPage) and
             ((FStartBookmarkPageNumber = NoPageNumber) or (FCurrentPageNo >= FStartBookmarkPageNumber)) and
             ((FEndBookmarkPageNumber = NoPageNumber) or (FCurrentPageNo <= FEndBookmarkPageNumber)));
end;

procedure TPdfTextStripper.ProcessPage(const Page: TPDPage);
begin
  if not Assigned(FOutput) then
  begin
    raise EInvalidOpException.Create('ProcessPage writes to the output of WriteText, so it cannot be called on its own');
  end;

  if not IsPageSelected then
  begin
    Exit;
  end;

  BeginPage(Page);
  PrepareArticles(Page);
  inherited ProcessPage(Page);
  WritePage;
  FinishPage(Page);
end;

procedure TPdfTextStripper.PrepareArticles(const Page: TPDPage);
begin
  var NumberOfArticleSections := 1;
  if FShouldSeparateByBeads then
  begin
    FillBeadRectangles(Page);
    Inc(NumberOfArticleSections, Length(FBeadRectangles) * 2);
  end;
  EnsureArticleLists(NumberOfArticleSections);
  FCharacterListMapping.Clear;
end;

procedure TPdfTextStripper.EnsureArticleLists(const NumberOfArticleSections: Integer);
begin
  // The lists of earlier pages are emptied and kept, also when this page needs fewer: the list never shrinks, which decides
  // the article of a character outside all beads
  for var ExistingArticle in FCharactersByArticle do
  begin
    ExistingArticle.Clear;
  end;

  while FCharactersByArticle.Count < NumberOfArticleSections do
  begin
    const Article = TObjectList<TTextPosition>.Create(True);
    FCharactersByArticle.Add(Article);
  end;
end;

procedure TPdfTextStripper.FillBeadRectangles(const Page: TPDPage);
begin
  const BeadCount = Page.ThreadBeadCount;
  const Log = Page.Context.Log;
  // The page is not the current page of the engine yet, so the engine cannot log for it
  if (BeadCount > MaxBeadsPerPage) and Assigned(Log) then
  begin
    Log.Warning('The page has %d article beads, only the first %d are used', [BeadCount, MaxBeadsPerPage]);
  end;
  FBeadRectangles := Page.ThreadBeads(MaxBeadsPerPage);

  const MediaBox = Page.MediaBox;
  const CropBox = Page.CropBox;
  const IsCropped = not (TJavaFloat.IsSame(CropBox.LowerLeftX, 0) and TJavaFloat.IsSame(CropBox.LowerLeftY, 0));
  for var Index := 0 to High(FBeadRectangles) do
  begin
    if not FBeadRectangles[Index].HasRectangle then
    begin
      // Cannot be skipped: the entry decides in ProcessTextPosition
      Continue;
    end;

    // The rectangle is in PDF coordinates (y = 0 at the bottom), the glyphs are in image coordinates (y = 0 at the top)
    var Rectangle := FBeadRectangles[Index].Rectangle;
    const UpperRightY: Single = MediaBox.UpperRightY - Rectangle.LowerLeftY;
    const LowerLeftY: Single = MediaBox.UpperRightY - Rectangle.UpperRightY;
    Rectangle.LowerLeftY := LowerLeftY;
    Rectangle.UpperRightY := UpperRightY;

    if IsCropped then
    begin
      Rectangle.LowerLeftX := Rectangle.LowerLeftX - CropBox.LowerLeftX;
      Rectangle.LowerLeftY := Rectangle.LowerLeftY - CropBox.LowerLeftY;
      Rectangle.UpperRightX := Rectangle.UpperRightX - CropBox.LowerLeftX;
      Rectangle.UpperRightY := Rectangle.UpperRightY - CropBox.LowerLeftY;
    end;
    FBeadRectangles[Index].Rectangle := Rectangle;
  end;
end;

procedure TPdfTextStripper.StartArticle;
begin
  StartArticle(True);
end;

procedure TPdfTextStripper.StartArticle(const IsLeftToRight: Boolean);
begin
  FOutput.Write(FArticleStart);
end;

procedure TPdfTextStripper.EndArticle;
begin
  FOutput.Write(FArticleEnd);
end;

procedure TPdfTextStripper.BeginPage(const Page: TPDPage);
begin
end;

procedure TPdfTextStripper.FinishPage(const Page: TPDPage);
begin
end;

procedure TPdfTextStripper.ResetLineState;
begin
  FMaxYForLine := MaxYForLineResetValue;
  FMinYTopForLine := MinYTopForLineResetValue;
  FEndOfLastTextX := EndOfLastTextXResetValue;
  FLastWordSpacing := LastWordSpacingResetValue;
  FMaxHeightForLine := MaxHeightForLineResetValue;
  FPreviousAveCharWidth := -1;
  FLastPosition := nil;
  FLastLineStartPosition := nil;
  FStartOfPage := True;
  FStartOfArticle := False;
end;

procedure TPdfTextStripper.WritePage;
begin
  ResetLineState;
  FWrappers := TObjectList<TPositionWrapper>.Create(True);
  try
    if FCharactersByArticle.Count > 0 then
    begin
      WritePageStart;
    end;

    for var TextList in FCharactersByArticle do
    begin
      WriteArticle(TextList);
    end;
    WritePageEnd;
  finally
    FLastPosition := nil;
    FLastLineStartPosition := nil;
    FreeAndNil(FWrappers);
  end;
end;

class procedure TPdfTextStripper.SortPositions(const TextList: TObjectList<TTextPosition>);
begin
  // PDFBox sorts with Collections.sort and only takes its own merge sort, on the list as the first sort left it, when the JDK
  // finds the comparison inconsistent. The comparison is not transitive, so the two give different orders.
  const Comparison = TTextPositionComparator.AsComparison();
  if not TTimSort.Sort<TTextPosition>(TextList, Comparison) then
  begin
    TIterativeMergeSort.Sort<TTextPosition>(TextList, Comparison);
  end;
end;

class procedure TPdfTextStripper.RemoveContainedSpaces(const TextList: TObjectList<TTextPosition>);
begin
  if TextList.Count < 2 then
  begin
    Exit;
  end;

  const Kept = TList<TTextPosition>.Create;
  try
    var Previous := TextList[0];
    Kept.Add(Previous);
    for var Index := 1 to TextList.Count - 1 do
    begin
      const Position = TextList[Index];
      if (Position.Unicode = ' ') and Previous.CompletelyContains(Position) then
      begin
        Position.Free;
      end
      else
      begin
        Previous := Position;
        Kept.Add(Position);
      end;
    end;

    TextList.OwnsObjects := False;
    try
      TextList.Clear;
      TextList.AddRange(Kept);
    finally
      TextList.OwnsObjects := True;
    end;
  finally
    Kept.Free;
  end;
end;

procedure TPdfTextStripper.WriteArticle(const TextList: TObjectList<TTextPosition>);
begin
  if FSortByPosition then
  begin
    SortPositions(TextList);
    // PDFBOX-5487: a space that lies within the letters around it is dropped
    RemoveContainedSpaces(TextList);
  end;

  StartArticle;
  FStartOfArticle := True;

  // A line is queued before it is written, so that its words can be normalised
  const Line = TLine.Create;
  try
    FPreviousAveCharWidth := -1;
    for var Position in TextList do
    begin
      ProcessLinePosition(Position, Line);
    end;

    if Line.Count > 0 then
    begin
      const LastWords = Normalize(Line);
      WriteLine(LastWords);
      WriteParagraphEnd;
    end;
  finally
    Line.Free;
  end;
  EndArticle;
end;

class function TPdfTextStripper.JavaMin(const Left, Right: Single): Single;
begin
  if Left.IsNan or Right.IsNan then
  begin
    Result := NaN;
  end
  else if Left < Right then
  begin
    Result := Left;
  end
  else
  begin
    Result := Right;
  end;
end;

class function TPdfTextStripper.JavaMax(const Left, Right: Single): Single;
begin
  if Left.IsNan or Right.IsNan then
  begin
    Result := NaN;
  end
  else if Left > Right then
  begin
    Result := Left;
  end
  else
  begin
    Result := Right;
  end;
end;

class function TPdfTextStripper.MultiplyFloat(const Value1, Value2: Single): Single;
begin
  const Product: Single = Value1 * Value2;
  const Scaled: Single = Product * RoundingFactor;
  // Math.round: floor(x + 0.5), NaN gives 0, and the result saturates at the int range
  var Rounded := 0;
  if not Scaled.IsNan then
  begin
    const Floored: Double = Floor(Double(Scaled) + 0.5);
    if Floored >= 2147483647.0 then
    begin
      Rounded := MaxInt;
    end
    else if Floored <= -2147483648.0 then
    begin
      Rounded := Low(Integer);
    end
    else
    begin
      Rounded := Trunc(Floored);
    end;
  end;
  const Rounded32: Single = Rounded;
  Result := Rounded32 / RoundingFactor;
end;

class function TPdfTextStripper.Within(const First, Second, Variance: Single): Boolean;
begin
  const Upper: Single = First + Variance;
  const Lower: Single = First - Variance;
  Result := (Second < Upper) and (Second > Lower);
end;

class function TPdfTextStripper.Overlap(const Y1, Height1, Y2, Height2: Single): Boolean;
begin
  const Lower1: Single = Y1 - Height1;
  const Lower2: Single = Y2 - Height2;
  Result := (Within(Y1, Y2, SameLineTolerance) or ((Y2 <= Y1) and (Y2 >= Lower1)) or ((Y1 <= Y2) and (Y1 >= Lower2)));
end;

class function TPdfTextStripper.HasFontOrSizeChanged(const Current, Last: TTextPosition): Boolean;
begin
  if not TJavaFloat.IsSame(Current.FontSize, Last.FontSize) then
  begin
    Exit(True);
  end;
  if Current.Font = Last.Font then
  begin
    Exit(False);
  end;
  if not (Assigned(Current.Font) and Assigned(Last.Font)) then
  begin
    Exit(True);
  end;

  // Different font objects without a name differ as well, where PDFBox compares the hash codes of the objects
  const CurrentName = Current.Font.Name;
  Result := (CurrentName = '') or (CurrentName <> Last.Font.Name);
end;

function TPdfTextStripper.CalculateMetrics(const Position: TTextPosition): TPositionMetrics;
begin
  // When the text is sorted the direction adjusted values count, because the sorting used them
  if FSortByPosition then
  begin
    Result.X := Position.XDirAdj;
    Result.Y := Position.YDirAdj;
    Result.Width := Position.WidthDirAdj;
    Result.Height := Position.HeightDir;
  end
  else
  begin
    Result.X := Position.X;
    Result.Y := Position.Y;
    Result.Width := Position.Width;
    Result.Height := Position.Height;
  end;

  Result.WordSpacing := Position.WidthOfSpace;
  Result.DeltaSpace := CalculateDeltaSpace(Result.WordSpacing);
  Result.AverageCharWidth := CalculateAverageCharWidth(Result, Length(Position.IndividualWidths));
end;

function TPdfTextStripper.CalculateDeltaSpace(const WordSpacing: Single): Single;
begin
  // The expected width of the space, from the space of the font with some margin
  if TJavaFloat.IsSame(WordSpacing, 0) or WordSpacing.IsNan then
  begin
    Result := MaxSingle;
  end
  else if FLastWordSpacing < 0 then
  begin
    Result := WordSpacing * FSpacingTolerance;
  end
  else
  begin
    const Sum: Single = WordSpacing + FLastWordSpacing;
    const Average: Single = Sum / 2.0;
    Result := Average * FSpacingTolerance;
  end;
end;

function TPdfTextStripper.CalculateAverageCharWidth(const Metrics: TPositionMetrics; const WordCharCount: Integer): Single;
begin
  // Not a true average (an average of averages), which gave the best results in the experiments of PDFBox
  const CharCount: Single = WordCharCount;
  const PerCharacter: Single = Metrics.Width / CharCount;
  if FPreviousAveCharWidth < 0 then
  begin
    Result := PerCharacter;
  end
  else
  begin
    const Sum: Single = FPreviousAveCharWidth + PerCharacter;
    Result := Sum / 2.0;
  end;
end;

procedure TPdfTextStripper.ResetLineExtent;
begin
  FMaxYForLine := MaxYForLineResetValue;
  FMaxHeightForLine := MaxHeightForLineResetValue;
  FMinYTopForLine := MinYTopForLineResetValue;
end;

procedure TPdfTextStripper.StartNewLine(const Current: TPositionWrapper; const Line: TLine);
begin
  const Words = Normalize(Line);
  WriteLine(Words);
  Line.Clear;
  FLastLineStartPosition := HandleLineSeparation(Current, FLastPosition, FLastLineStartPosition, FMaxHeightForLine);
  ResetLineExtent;
end;

function TPdfTextStripper.NeedsWordSeparator(const ExpectedStartOfNextWordX: Single; const Metrics: TPositionMetrics): Boolean;
begin
  // Only when the last character was not a word separator already
  const LastUnicode = FLastPosition.Position.Unicode;
  Result := (not TJavaFloat.IsSame(ExpectedStartOfNextWordX, ExpectedStartOfNextWordXResetValue) and
             (ExpectedStartOfNextWordX < Metrics.X) and
             ((FWordSeparator = '') or not LastUnicode.EndsWith(FWordSeparator, False)));
end;

procedure TPdfTextStripper.ProcessLinePosition(const Position: TTextPosition; const Line: TLine);
begin
  // PDFBOX-3774: the spaces of the content stream can be ignored
  if (Position.Unicode = ' ') and FIgnoreContentStreamSpaceGlyphs then
  begin
    Exit;
  end;

  const Current = TPositionWrapper.Create(Position);
  FWrappers.Add(Current);

  // The average character width starts over when the font or its size changes
  if Assigned(FLastPosition) and HasFontOrSizeChanged(Position, FLastPosition.Position) then
  begin
    FPreviousAveCharWidth := -1;
  end;

  const Metrics = CalculateMetrics(Position);
  const DeltaCharWidth: Single = Metrics.AverageCharWidth * FAverageCharTolerance;

  // The smaller of the two estimates decides where the next word is expected
  var ExpectedStartOfNextWordX := ExpectedStartOfNextWordXResetValue;
  if not TJavaFloat.IsSame(FEndOfLastTextX, EndOfLastTextXResetValue) then
  begin
    ExpectedStartOfNextWordX := FEndOfLastTextX + JavaMin(Metrics.DeltaSpace, DeltaCharWidth);
  end;

  if Assigned(FLastPosition) then
  begin
    if FStartOfArticle then
    begin
      FLastPosition.IsArticleStart := True;
      FStartOfArticle := False;
    end;

    // The text is on the line when it overlaps the last baseline a little: the size of the last text takes care of a
    // superscript, the size of this text of a subscript
    if not Overlap(Metrics.Y, Metrics.Height, FMaxYForLine, FMaxHeightForLine) then
    begin
      StartNewLine(Current, Line);
      ExpectedStartOfNextWordX := ExpectedStartOfNextWordXResetValue;
    end;

    if NeedsWordSeparator(ExpectedStartOfNextWordX, Metrics) then
    begin
      Line.Add(Default(TLineItem));
    end;

    // At least the width of a space between the last character and this one: the font size may have changed completely
    const Gap: Single = Abs(Position.X - FLastPosition.Position.X);
    const GapLimit: Single = Metrics.WordSpacing + Metrics.DeltaSpace;
    if Gap > GapLimit then
    begin
      ResetLineExtent;
    end;
  end;

  if Metrics.Y >= FMaxYForLine then
  begin
    FMaxYForLine := Metrics.Y;
  end;
  FEndOfLastTextX := Metrics.X + Metrics.Width;

  if FStartOfPage and not Assigned(FLastPosition) then
  begin
    WriteParagraphStart;
  end;
  var Item: TLineItem;
  Item.Position := Position;
  Line.Add(Item);
  FMaxHeightForLine := JavaMax(FMaxHeightForLine, Metrics.Height);
  FMinYTopForLine := JavaMin(FMinYTopForLine, Metrics.Y - Metrics.Height);
  FLastPosition := Current;
  if FStartOfPage then
  begin
    FLastPosition.IsParagraphStart := True;
    FLastPosition.IsLineStart := True;
    FLastLineStartPosition := FLastPosition;
    FStartOfPage := False;
  end;
  FLastWordSpacing := Metrics.WordSpacing;
  FPreviousAveCharWidth := Metrics.AverageCharWidth;
end;

function TPdfTextStripper.HandleLineSeparation(const Current, LastPosition, LastLineStartPosition: TPositionWrapper; const MaxHeightForLine: Single): TPositionWrapper;
begin
  Current.IsLineStart := True;
  IsParagraphSeparation(Current, LastPosition, LastLineStartPosition, MaxHeightForLine);
  Result := Current;
  if not Current.IsParagraphStart then
  begin
    WriteLineSeparator;
  end
  else if LastPosition.IsArticleStart then
  begin
    if LastPosition.IsLineStart then
    begin
      WriteLineSeparator;
    end;
    WriteParagraphStart;
  end
  else
  begin
    WriteLineSeparator;
    WriteParagraphSeparator;
  end;
end;

function TPdfTextStripper.IsListItemRepeat(const Position, LastLineStartPosition: TPositionWrapper): Boolean;
begin
  // The previous line looks like a list item format, and this one is of the same format
  const LastFormat = TListItemPatterns.IndexOf(LastLineStartPosition.Position.Unicode);
  Result := (LastFormat <> TListItemPatterns.NoMatch) and (LastFormat = TListItemPatterns.IndexOf(Position.Position.Unicode));
end;

procedure TPdfTextStripper.IsParagraphSeparation(const Position, LastPosition, LastLineStartPosition: TPositionWrapper; const MaxHeightForLine: Single);
begin
  var NewParagraph := False;
  if not Assigned(LastLineStartPosition) then
  begin
    NewParagraph := True;
  end
  else
  begin
    const Current = Position.Position;
    const YGap: Single = Abs(Current.YDirAdj - LastPosition.Position.YDirAdj);
    const NewYVal = MultiplyFloat(FDropThreshold, MaxHeightForLine);
    const XGap: Single = Current.XDirAdj - LastLineStartPosition.Position.XDirAdj;
    const NewXVal = MultiplyFloat(FIndentThreshold, Current.WidthOfSpace);
    const PositionWidth = MultiplyFloat(ListItemWidthFactor, Current.Width);
    const NegativeSpace: Single = -Current.WidthOfSpace;

    if YGap > NewYVal then
    begin
      NewParagraph := True;
    end
    else if XGap > NewXVal then
    begin
      // Indented, but a hanging indent is screened for
      if not LastLineStartPosition.IsParagraphStart then
      begin
        NewParagraph := True;
      end
      else
      begin
        Position.IsHangingIndent := True;
      end;
    end
    else if XGap < NegativeSpace then
    begin
      // Left of the previous line. Was it a hanging indent?
      NewParagraph := not LastLineStartPosition.IsParagraphStart;
    end
    else if Abs(XGap) < PositionWidth then
    begin
      // Within a quarter of a character of the last line start: they are lined up
      if LastLineStartPosition.IsHangingIndent then
      begin
        Position.IsHangingIndent := True;
      end
      else if LastLineStartPosition.IsParagraphStart then
      begin
        NewParagraph := IsListItemRepeat(Position, LastLineStartPosition);
      end;
    end;
  end;

  if NewParagraph then
  begin
    Position.IsParagraphStart := True;
  end;
end;

function TPdfTextStripper.CreateWord(const Text: string; const Positions: TArray<TTextPosition>): TWordWithPositions;
begin
  Result.Text := NormalizeWord(Text);
  Result.Positions := Positions;
end;

// Some characters of the Alphabetic and Arabic presentation forms are changed to their NFKC form. Only that range: NFKC
// converts too many other things, such as the micro sign to the Greek letter.
function TPdfTextStripper.NormalizeWord(const Text: string): string;
begin
  var Builder: TStringBuilder := nil;
  try
    var CopiedUpTo := 1;
    for var Index := 1 to Length(Text) do
    begin
      const Character = Text[Index];
      const IsInRange = ((Character >= FirstPresentationForm) and (Character <= LastArabicPresentationFormA)) or
                        ((Character >= FirstArabicPresentationFormB) and (Character <= LastArabicPresentationFormB));
      if not IsInRange then
      begin
        Continue;
      end;

      if not Assigned(Builder) then
      begin
        Builder := TStringBuilder.Create(Length(Text) * 2);
      end;
      Builder.Append(Text, CopiedUpTo - 1, Index - CopiedUpTo);

      // Some fonts map U+FDF2 differently than the Unicode spec: they add an extra U+0627 to compensate
      if (Character = ArabicLigatureAllah) and (Index > 1) and ((Text[Index - 1] = ArabicAlef) or (Text[Index - 1] = ArabicAlefIsolated)) then
      begin
        Builder.Append(ArabicLamLamHeh);
      end
      else
      begin
        var Normalized: string;
        if not TPdfUnicodeText.Instance.TryGetPresentationForm(Character, Normalized) then
        begin
          Normalized := Character;
        end;
        // The decomposed Hebrew and Arabic letters come in reverse order
        if (Character >= FirstHebrewForm) and (Length(Normalized) > 1) then
        begin
          Normalized := ReverseString(Normalized);
        end;
        Builder.Append(Normalized);
      end;
      CopiedUpTo := Index + 1;
    end;

    if not Assigned(Builder) then
    begin
      Exit(HandleDirection(Text));
    end;
    Builder.Append(Text, CopiedUpTo - 1, Length(Text) - CopiedUpTo + 1);
    Result := HandleDirection(Builder.ToString);
  finally
    Builder.Free;
  end;
end;

function TPdfTextStripper.Normalize(const Line: TLine): TArray<TWordWithPositions>;
begin
  const Words = TList<TWordWithPositions>.Create;
  const LineBuilder = TStringBuilder.Create;
  const WordPositions = TList<TTextPosition>.Create;
  try
    for var Item in Line do
    begin
      if not Assigned(Item.Position) then
      begin
        const CompletedWord = CreateWord(LineBuilder.ToString, WordPositions.ToArray);
        Words.Add(CompletedWord);
        LineBuilder.Clear;
        WordPositions.Clear;
      end
      else
      begin
        LineBuilder.Append(Item.Position.VisuallyOrderedUnicode);
        WordPositions.Add(Item.Position);
      end;
    end;

    if LineBuilder.Length > 0 then
    begin
      const LastWord = CreateWord(LineBuilder.ToString, WordPositions.ToArray);
      Words.Add(LastWord);
    end;
    Result := Words.ToArray;
  finally
    WordPositions.Free;
    LineBuilder.Free;
    Words.Free;
  end;
end;

function TPdfTextStripper.HandleDirection(const Text: string): string;
begin
  Result := Text;
end;

procedure TPdfTextStripper.WriteLine(const Line: TArray<TWordWithPositions>);
begin
  for var Index := 0 to High(Line) do
  begin
    WriteString(Line[Index].Text, Line[Index].Positions);
    if Index < High(Line) then
    begin
      WriteWordSeparator;
    end;
  end;
end;

procedure TPdfTextStripper.WriteLineSeparator;
begin
  FOutput.Write(FLineSeparator);
end;

procedure TPdfTextStripper.WriteWordSeparator;
begin
  FOutput.Write(FWordSeparator);
end;

procedure TPdfTextStripper.WriteCharacters(const Text: TTextPosition);
begin
  FOutput.Write(Text.Unicode);
end;

procedure TPdfTextStripper.WriteString(const Text: string; const TextPositions: TArray<TTextPosition>);
begin
  WriteString(Text);
end;

procedure TPdfTextStripper.WriteString(const Text: string);
begin
  FOutput.Write(Text);
end;

procedure TPdfTextStripper.WriteParagraphSeparator;
begin
  WriteParagraphEnd;
  WriteParagraphStart;
end;

procedure TPdfTextStripper.WriteParagraphStart;
begin
  if FInParagraph then
  begin
    WriteParagraphEnd;
    FInParagraph := False;
  end;
  FOutput.Write(FParagraphStart);
  FInParagraph := True;
end;

procedure TPdfTextStripper.WriteParagraphEnd;
begin
  if not FInParagraph then
  begin
    WriteParagraphStart;
  end;
  FOutput.Write(FParagraphEnd);
  FInParagraph := False;
end;

procedure TPdfTextStripper.WritePageStart;
begin
  FOutput.Write(FPageStart);
end;

procedure TPdfTextStripper.WritePageEnd;
begin
  FOutput.Write(FPageEnd);
end;

procedure TPdfTextStripper.BeginMarkedContentSequence(const Tag: string; const Properties: TCosDictionary);
begin
  if FMarkedContents.Count >= MaxMarkedContentDepth then
  begin
    // Deeper sequences are only counted, so that their EMC operators stay balanced
    if not FIsDepthLimitLogged then
    begin
      FIsDepthLimitLogged := True;
      LogWarning('Marked content is nested deeper than %d levels, the sequences below that are ignored', [MaxMarkedContentDepth]);
    end;
    Inc(FUncountedMarkedContentDepth);
    inherited;
    Exit;
  end;

  const MarkedContent = TPDMarkedContent.Create(Tag, Properties);
  FMarkedContents.Add(MarkedContent);
  // A sequence without ActualText ends the actual text of the one around it, as in PDFBox
  FHasActualText := MarkedContent.TryGetActualText(FActualText);
  if FHasActualText then
  begin
    FActualText := StringReplace(FActualText, SoftHyphen, '', [rfReplaceAll]);
    FFirstActualTextPosition := True;
  end;
  inherited;
end;

procedure TPdfTextStripper.EndMarkedContentSequence;
begin
  if FUncountedMarkedContentDepth > 0 then
  begin
    Dec(FUncountedMarkedContentDepth);
  end
  else if FMarkedContents.Count > 0 then
  begin
    var Ignored: string;
    if FMarkedContents.Last.TryGetActualText(Ignored) then
    begin
      FHasActualText := False;
      FActualText := '';
    end;
    FMarkedContents.Delete(FMarkedContents.Count - 1);
  end;
  inherited;
end;

procedure TPdfTextStripper.ApplyActualText(const Text: TTextPosition);
begin
  if FFirstActualTextPosition then
  begin
    Text.SetUnicode(FActualText);
    FFirstActualTextPosition := False;
  end
  else
  begin
    Text.SetUnicode('');
  end;
end;

function TPdfTextStripper.IsOverlappingDuplicate(const Text: TTextPosition): Boolean;
begin
  const Character = Text.Unicode;
  var Column: TOverlapColumn;
  if not FCharacterListMapping.TryGetValue(Character, Column) then
  begin
    Column := TOverlapColumn.Create;
    FCharacterListMapping.Add(Character, Column);
  end;

  // The tolerance lets a character that was shown a little aside from the same one count as a repeat (a fake bold or a
  // shadow). Java float arithmetic gives Infinity or NaN for an empty character
  var Tolerance: Single := Text.Width / Length(Character);
  Tolerance := Tolerance / 3.0;
  Result := Column.HasNear(Text.X, Text.Y, Tolerance);
  if not Result then
  begin
    Column.Add(Text.X, Text.Y);
  end;
end;

class function TPdfTextStripper.BeadContains(const Bead: TPDThreadBead; const X, Y: Single): Boolean;
begin
  Result := ((X >= Bead.Rectangle.LowerLeftX) and (X <= Bead.Rectangle.UpperRightX) and
             (Y >= Bead.Rectangle.LowerLeftY) and (Y <= Bead.Rectangle.UpperRightY));
end;

function TPdfTextStripper.FindArticleIndex(const X, Y: Single): Integer;
begin
  var Found := -1;
  var LeftAndAbove := -1;
  var Left := -1;
  var Above := -1;
  if FShouldSeparateByBeads then
  begin
    var Index := 0;
    while (Index < Length(FBeadRectangles)) and (Found = -1) do
    begin
      const Bead = FBeadRectangles[Index];
      if not Bead.HasRectangle then
      begin
        Found := 0;
      end
      else if BeadContains(Bead, X, Y) then
      begin
        Found := Index * 2 + 1;
      end
      else if ((X < Bead.Rectangle.LowerLeftX) or (Y < Bead.Rectangle.UpperRightY)) and (LeftAndAbove = -1) then
      begin
        LeftAndAbove := Index * 2;
      end
      else if (X < Bead.Rectangle.LowerLeftX) and (Left = -1) then
      begin
        Left := Index * 2;
      end
      else if (Y < Bead.Rectangle.UpperRightY) and (Above = -1) then
      begin
        Above := Index * 2;
      end;
      Inc(Index);
    end;
  end
  else
  begin
    Found := 0;
  end;

  if Found <> -1 then
  begin
    Result := Found;
  end
  else if LeftAndAbove <> -1 then
  begin
    Result := LeftAndAbove;
  end
  else if Left <> -1 then
  begin
    Result := Left;
  end
  else if Above <> -1 then
  begin
    Result := Above;
  end
  else
  begin
    Result := FCharactersByArticle.Count - 1;
  end;
end;

procedure TPdfTextStripper.AddToArticle(const Text: TTextPosition; const ArticleIndex: Integer);
begin
  // Some PDF files show the diacritics (the accents) apart from their character, where they overlap it. They are put back
  // together if the two come after each other. Only the previous position is looked at, like PDFBox.
  const TextList = FCharactersByArticle[ArticleIndex];
  if TextList.Count = 0 then
  begin
    TextList.Add(Text);
    Exit;
  end;

  const Previous = TextList.Last;
  if Text.IsDiacritic and Previous.Contains(Text) then
  begin
    Previous.MergeDiacritic(Text);
    Text.Free;
  end
  else if Previous.IsDiacritic and Text.Contains(Previous) then
  begin
    Text.MergeDiacritic(Previous);
    TextList.Delete(TextList.Count - 1);
    TextList.Add(Text);
  end
  else
  begin
    TextList.Add(Text);
  end;
end;

procedure TPdfTextStripper.ProcessTextPosition(const Text: TTextPosition);
begin
  if FHasActualText then
  begin
    ApplyActualText(Text);
  end;

  if FSuppressDuplicateOverlappingText and not FHasActualText and IsOverlappingDuplicate(Text) then
  begin
    Text.Free;
    Exit;
  end;

  AddToArticle(Text, FindArticleIndex(Text.X, Text.Y));
end;

end.
