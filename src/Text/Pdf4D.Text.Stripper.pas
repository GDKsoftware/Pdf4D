// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/text/PDFTextStripper.java (3.0.8), part 1: pages, articles, actual text and
// the text positions
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
  Pdf4D.Text.TextPosition;

type
  // The y values of the characters that were shown at one x position
  TOverlapYValues = class
  private
    FValues: TList<Single>;

    function LowerBound(const Value: Single): Integer;

  public
    constructor Create;
    destructor Destroy; override;

    // The values are kept in the order of Float.compare, without doubles (a TreeSet of Float)
    procedure Add(const Value: Single);
    function HasValueIn(const From, Till: Single): Boolean;
  end;

  // The positions where one character was shown, as x with its y values (a TreeMap of Float to a TreeSet of Float)
  TOverlapColumn = class
  private
    FX: TList<Single>;
    FYValues: TObjectList<TOverlapYValues>;

    function LowerBound(const Value: Single): Integer;

  public
    constructor Create;
    destructor Destroy; override;

    procedure Add(const X, Y: Single);
    // Whether a position with x in [X - Tolerance, X + Tolerance) has a y in [Y - Tolerance, Y + Tolerance). Java throws when
    // the range runs backwards (a negative tolerance); here that is an empty range.
    function HasNear(const X, Y, Tolerance: Single): Boolean;
  end;

  TPdfTextStripper = class(TLegacyPdfStreamEngine)
  private
    const MaxBeadsPerPage = 500;
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
    FFirstActualTextPosition: Boolean;
    FHasActualText: Boolean;
    FActualText: string;
    FCharactersByArticle: TObjectList<TObjectList<TTextPosition>>;
    FCharacterListMapping: TObjectDictionary<string, TOverlapColumn>;
    FDocument: TPDDocument;
    FOutput: TTextWriter;

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
    // Writes the text of the page that was processed. Empty here.
    procedure WritePage; virtual;
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
  Pdf4D.Common.FloatGuard,
  Pdf4D.Content.Operators.MarkedContent;

const
  DefaultIndentThreshold: Single = 2.0;
  DefaultDropThreshold: Single = 2.5;
  DefaultSpacingTolerance: Single = 0.5;
  DefaultAverageCharTolerance: Single = 0.3;
  NoPageNumber = -1;

{ TOverlapYValues }

constructor TOverlapYValues.Create;
begin
  inherited Create;
  FValues := TList<Single>.Create;
end;

destructor TOverlapYValues.Destroy;
begin
  FValues.Free;
  inherited;
end;

function TOverlapYValues.LowerBound(const Value: Single): Integer;
begin
  Result := 0;
  var High := FValues.Count;
  while Result < High do
  begin
    const Middle = Result + (High - Result) div 2;
    if TJavaFloat.Compare(FValues[Middle], Value) < 0 then
    begin
      Result := Middle + 1;
    end
    else
    begin
      High := Middle;
    end;
  end;
end;

procedure TOverlapYValues.Add(const Value: Single);
begin
  const Index = LowerBound(Value);
  if (Index >= FValues.Count) or not TJavaFloat.IsSame(FValues[Index], Value) then
  begin
    FValues.Insert(Index, Value);
  end;
end;

function TOverlapYValues.HasValueIn(const From, Till: Single): Boolean;
begin
  const Index = LowerBound(From);
  Result := (Index < FValues.Count) and (TJavaFloat.Compare(FValues[Index], Till) < 0);
end;

{ TOverlapColumn }

constructor TOverlapColumn.Create;
begin
  inherited Create;
  FX := TList<Single>.Create;
  FYValues := TObjectList<TOverlapYValues>.Create(True);
end;

destructor TOverlapColumn.Destroy;
begin
  FYValues.Free;
  FX.Free;
  inherited;
end;

function TOverlapColumn.LowerBound(const Value: Single): Integer;
begin
  Result := 0;
  var High := FX.Count;
  while Result < High do
  begin
    const Middle = Result + (High - Result) div 2;
    if TJavaFloat.Compare(FX[Middle], Value) < 0 then
    begin
      Result := Middle + 1;
    end
    else
    begin
      High := Middle;
    end;
  end;
end;

procedure TOverlapColumn.Add(const X, Y: Single);
begin
  const Index = LowerBound(X);
  if (Index >= FX.Count) or not TJavaFloat.IsSame(FX[Index], X) then
  begin
    FX.Insert(Index, X);
    FYValues.Insert(Index, TOverlapYValues.Create);
  end;
  FYValues[Index].Add(Y);
end;

function TOverlapColumn.HasNear(const X, Y, Tolerance: Single): Boolean;
begin
  Result := False;
  const XFrom: Single = X - Tolerance;
  const XTill: Single = X + Tolerance;
  const YFrom: Single = Y - Tolerance;
  const YTill: Single = Y + Tolerance;
  if (TJavaFloat.Compare(XFrom, XTill) > 0) or (TJavaFloat.Compare(YFrom, YTill) > 0) then
  begin
    Exit;
  end;

  var Index := LowerBound(XFrom);
  while (Index < FX.Count) and (TJavaFloat.Compare(FX[Index], XTill) < 0) do
  begin
    if FYValues[Index].HasValueIn(YFrom, YTill) then
    begin
      Exit(True);
    end;
    Inc(Index);
  end;
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
  if Assigned(Bookmark) and Bookmark.TryGetPageIndex(PageIndex) then
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
  for var Article in FCharactersByArticle do
  begin
    Article.Clear;
  end;

  while FCharactersByArticle.Count < NumberOfArticleSections do
  begin
    FCharactersByArticle.Add(TObjectList<TTextPosition>.Create(True));
  end;
end;

procedure TPdfTextStripper.FillBeadRectangles(const Page: TPDPage);
begin
  FBeadRectangles := Page.ThreadBeads;
  if Length(FBeadRectangles) > MaxBeadsPerPage then
  begin
    LogWarning('The page has %d article beads, only the first %d are used', [Length(FBeadRectangles), MaxBeadsPerPage]);
    SetLength(FBeadRectangles, MaxBeadsPerPage);
  end;

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

procedure TPdfTextStripper.WritePage;
begin
end;

procedure TPdfTextStripper.BeginMarkedContentSequence(const Tag: string; const Properties: TCosDictionary);
begin
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
  if FMarkedContents.Count > 0 then
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
