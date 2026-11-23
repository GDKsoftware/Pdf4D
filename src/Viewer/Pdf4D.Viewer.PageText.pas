// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.PageText;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  System.Generics.Collections,
  Pdf4D.Api.Page.Interfaces,
  Pdf4D.Api.TextLayout.Interfaces,
  Pdf4D.Viewer.Types;

type
  // Immutable snapshot made on the worker; safe to share between threads. The arrays that it returns are its own: a caller must not
  // change them (a dynamic array is not copied on write).
  IPdfPageText = interface
    ['{B1C7E2A4-5D39-4F80-9A6B-3E2F1D7C8B05}']
    function PageIndex: Integer;
    // No words: a scanned page
    function IsEmpty: Boolean;
    // In reading order
    function Words: TArray<TPdfTextFragment>;
    function Segments: TArray<TPdfTextFragment>;
    function Lines: TArray<TPdfTextFragment>;
    function Links: TArray<TPdfLink>;
    // The points below are in PDF user space
    function TryFindSegmentAt(const Point: TPointF; out Segment: TPdfTextFragment): Boolean;
    function TryFindWordAt(const Point: TPointF; out WordIndex: Integer): Boolean;
    // False only when IsEmpty
    function TryFindNearestWord(const Point: TPointF; out WordIndex: Integer): Boolean;
    // The last link in /Annots order wins
    function TryFindLinkAt(const Point: TPointF; out Link: TPdfLink): Boolean;
    // Words Min(AnchorWord, FocusWord)..Max(AnchorWord, FocusWord). Raises EArgumentOutOfRangeException for an index outside Words.
    function Select(const AnchorWord, FocusWord: Integer; const Kind: TPdfSelectionKind): TPdfTextSelection;
    function SelectAll: TPdfTextSelection;
  end;

  TPdfPageText = class(TInterfacedObject, IPdfPageText)
  private
    type
      // The words and segments of one line, found through the bounds of the line. A word or segment outside every line is a group of
      // its own.
      TGroup = record
        Bounds: TRectF;
        Words: TArray<Integer>;
        Segments: TArray<Integer>;
      end;

  private
    FPageIndex: Integer;
    FWords: TArray<TPdfTextFragment>;
    FSegments: TArray<TPdfTextFragment>;
    FLines: TArray<TPdfTextFragment>;
    FLinks: TArray<TPdfLink>;
    // The first Length(FLines) groups are the lines, in the order of FLines
    FGroups: TArray<TGroup>;
    FWordGroups: TArray<Integer>;
    // The indexes of FLines ordered by Start, to find the line of a range
    FLinesByStart: TArray<Integer>;

    constructor CreateEmpty(const PageIndex: Integer);

    class function CopyFragments(const Fragments: TArray<TPdfTextFragment>): TArray<TPdfTextFragment>; static;
    class function CopyLinks(const Links: TArray<TPdfLink>): TArray<TPdfLink>; static;
    class function BoundsOf(const Quads: TArray<TPdfQuad>): TRectF; static;
    class function ContainsPoint(const Bounds: TRectF; const Point: TPointF): Boolean; static;
    class function AnyQuadContains(const Quads: TArray<TPdfQuad>; const Point: TPointF): Boolean; static;

    procedure BuildGroups;
    procedure SortLinesByStart;
    function FindLineOf(const Start: Integer): Integer;
    function GroupOf(const Fragment: TPdfTextFragment; const OrphanBounds: TList<TRectF>): Integer;
    procedure FillMembers(const WordGroups, SegmentGroups: TArray<Integer>);
    procedure CheckWordIndex(const WordIndex: Integer);
    function BuildSelectionQuads(const First, Last: Integer): TArray<TPdfQuad>;
    function JoinSelectionText(const First, Last: Integer): string;

  public
    // Copies everything; keeps no reference to Layout
    constructor Create(const Layout: IPdfTextLayout; const Links: TArray<TPdfLink>);

    class function Empty(const PageIndex: Integer): IPdfPageText; static;

    function PageIndex: Integer;
    function IsEmpty: Boolean;
    function Words: TArray<TPdfTextFragment>;
    function Segments: TArray<TPdfTextFragment>;
    function Lines: TArray<TPdfTextFragment>;
    function Links: TArray<TPdfLink>;
    function TryFindSegmentAt(const Point: TPointF; out Segment: TPdfTextFragment): Boolean;
    function TryFindWordAt(const Point: TPointF; out WordIndex: Integer): Boolean;
    function TryFindNearestWord(const Point: TPointF; out WordIndex: Integer): Boolean;
    function TryFindLinkAt(const Point: TPointF; out Link: TPdfLink): Boolean;
    function Select(const AnchorWord, FocusWord: Integer; const Kind: TPdfSelectionKind): TPdfTextSelection;
    function SelectAll: TPdfTextSelection;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.Generics.Defaults,
  Pdf4D.Common.Quad;

type
  TPdfQuadHitTest = record helper for TPdfQuad
  private
    class function Cross(const From, Towards, Point: TPointF): Single; static;
    class function DistanceToSegment(const From, Towards, Point: TPointF): Single; static;

  public
    // Quads are convex; the edge counts as inside
    function Contains(const Point: TPointF): Boolean;
    // Zero inside the quad, else the distance to the nearest edge
    function DistanceTo(const Point: TPointF): Single;
  end;

{ TPdfQuadHitTest }

class function TPdfQuadHitTest.Cross(const From, Towards, Point: TPointF): Single;
begin
  Result := ((Towards.X - From.X) * (Point.Y - From.Y)) - ((Towards.Y - From.Y) * (Point.X - From.X));
end;

class function TPdfQuadHitTest.DistanceToSegment(const From, Towards, Point: TPointF): Single;
begin
  const Edge = Towards - From;
  const EdgeLengthSquared = (Edge.X * Edge.X) + (Edge.Y * Edge.Y);
  const IsPoint = (EdgeLengthSquared <= 0);
  if IsPoint then
  begin
    Exit(Point.Distance(From));
  end;

  const Along = (((Point.X - From.X) * Edge.X) + ((Point.Y - From.Y) * Edge.Y)) / EdgeLengthSquared;
  const Nearest = From + (Edge * EnsureRange(Along, 0, 1));
  Result := Point.Distance(Nearest);
end;

function TPdfQuadHitTest.Contains(const Point: TPointF): Boolean;
begin
  const First = Cross(P1, P2, Point);
  const Second = Cross(P2, P3, Point);
  const Third = Cross(P3, P4, Point);
  const Fourth = Cross(P4, P1, Point);
  const HasNegative = ((First < 0) or (Second < 0) or (Third < 0) or (Fourth < 0));
  const HasPositive = ((First > 0) or (Second > 0) or (Third > 0) or (Fourth > 0));

  // A quad that has collapsed to a point or a line gives only zeros: it holds no point, it must not hold every point
  const IsInside = ((HasNegative or HasPositive) and not (HasNegative and HasPositive));
  Result := (IsFinite and IsInside);
end;

function TPdfQuadHitTest.DistanceTo(const Point: TPointF): Single;
begin
  if not IsFinite then
  begin
    Exit(MaxSingle);
  end;
  if Contains(Point) then
  begin
    Exit(0);
  end;

  Result := Min(Min(DistanceToSegment(P1, P2, Point), DistanceToSegment(P2, P3, Point)),
                Min(DistanceToSegment(P3, P4, Point), DistanceToSegment(P4, P1, Point)));
end;

{ TPdfPageText }

constructor TPdfPageText.CreateEmpty(const PageIndex: Integer);
begin
  inherited Create;

  FPageIndex := PageIndex;
end;

constructor TPdfPageText.Create(const Layout: IPdfTextLayout; const Links: TArray<TPdfLink>);
begin
  inherited Create;

  FPageIndex := Layout.PageIndex;
  FWords := CopyFragments(Layout.Words);
  FSegments := CopyFragments(Layout.Segments);
  FLines := CopyFragments(Layout.Lines);
  FLinks := CopyLinks(Links);
  BuildGroups;
end;

class function TPdfPageText.Empty(const PageIndex: Integer): IPdfPageText;
begin
  Result := TPdfPageText.CreateEmpty(PageIndex);
end;

class function TPdfPageText.CopyFragments(const Fragments: TArray<TPdfTextFragment>): TArray<TPdfTextFragment>;
begin
  SetLength(Result, Length(Fragments));
  for var Index := 0 to High(Fragments) do
  begin
    Result[Index] := Fragments[Index];
    Result[Index].Quads := Copy(Fragments[Index].Quads);
  end;
end;

class function TPdfPageText.CopyLinks(const Links: TArray<TPdfLink>): TArray<TPdfLink>;
begin
  SetLength(Result, Length(Links));
  for var Index := 0 to High(Links) do
  begin
    Result[Index] := Links[Index];
    Result[Index].Quads := Copy(Links[Index].Quads);
  end;
end;

class function TPdfPageText.BoundsOf(const Quads: TArray<TPdfQuad>): TRectF;
begin
  Result := TRectF.Empty;
  for var Quad in Quads do
  begin
    if Quad.IsFinite then
    begin
      Result := TRectF.Union(Result, Quad.Bounds);
    end;
  end;
end;

class function TPdfPageText.ContainsPoint(const Bounds: TRectF; const Point: TPointF): Boolean;
begin
  const IsInsideX = ((Point.X >= Bounds.Left) and (Point.X <= Bounds.Right));
  const IsInsideY = ((Point.Y >= Bounds.Top) and (Point.Y <= Bounds.Bottom));

  Result := (IsInsideX and IsInsideY);
end;

class function TPdfPageText.AnyQuadContains(const Quads: TArray<TPdfQuad>; const Point: TPointF): Boolean;
begin
  for var Quad in Quads do
  begin
    if Quad.Contains(Point) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

// Linear in the words and segments: the group of every one is found first, the member arrays are sized once and then filled. Growing
// them one by one would copy them again for every word, which a page with very many words on a line cannot afford.
procedure TPdfPageText.BuildGroups;
begin
  SortLinesByStart;

  const OrphanBounds = TList<TRectF>.Create;
  try
    SetLength(FWordGroups, Length(FWords));
    for var Index := 0 to High(FWords) do
    begin
      FWordGroups[Index] := GroupOf(FWords[Index], OrphanBounds);
    end;

    var SegmentGroups: TArray<Integer>;
    SetLength(SegmentGroups, Length(FSegments));
    for var Index := 0 to High(FSegments) do
    begin
      SegmentGroups[Index] := GroupOf(FSegments[Index], OrphanBounds);
    end;

    SetLength(FGroups, Length(FLines) + OrphanBounds.Count);
    for var Index := 0 to High(FLines) do
    begin
      FGroups[Index].Bounds := BoundsOf(FLines[Index].Quads);
    end;
    for var Index := 0 to OrphanBounds.Count - 1 do
    begin
      FGroups[Length(FLines) + Index].Bounds := OrphanBounds[Index];
    end;

    FillMembers(FWordGroups, SegmentGroups);
  finally
    OrphanBounds.Free;
  end;
end;

procedure TPdfPageText.FillMembers(const WordGroups, SegmentGroups: TArray<Integer>);
begin
  var WordCounts: TArray<Integer>;
  var SegmentCounts: TArray<Integer>;
  SetLength(WordCounts, Length(FGroups));
  SetLength(SegmentCounts, Length(FGroups));
  for var GroupIndex in WordGroups do
  begin
    Inc(WordCounts[GroupIndex]);
  end;
  for var GroupIndex in SegmentGroups do
  begin
    Inc(SegmentCounts[GroupIndex]);
  end;

  for var GroupIndex := 0 to High(FGroups) do
  begin
    SetLength(FGroups[GroupIndex].Words, WordCounts[GroupIndex]);
    SetLength(FGroups[GroupIndex].Segments, SegmentCounts[GroupIndex]);
  end;

  // The counts now give the next free place of each group
  SetLength(WordCounts, 0);
  SetLength(WordCounts, Length(FGroups));
  SetLength(SegmentCounts, 0);
  SetLength(SegmentCounts, Length(FGroups));
  for var WordIndex := 0 to High(WordGroups) do
  begin
    const GroupIndex = WordGroups[WordIndex];
    FGroups[GroupIndex].Words[WordCounts[GroupIndex]] := WordIndex;
    Inc(WordCounts[GroupIndex]);
  end;
  for var SegmentIndex := 0 to High(SegmentGroups) do
  begin
    const GroupIndex = SegmentGroups[SegmentIndex];
    FGroups[GroupIndex].Segments[SegmentCounts[GroupIndex]] := SegmentIndex;
    Inc(SegmentCounts[GroupIndex]);
  end;
end;

// The line of the fragment, or a new group of its own after the lines, whose bounds are added to OrphanBounds
function TPdfPageText.GroupOf(const Fragment: TPdfTextFragment; const OrphanBounds: TList<TRectF>): Integer;
begin
  Result := FindLineOf(Fragment.Start);
  const IsOutsideLines = (Result < 0);
  if IsOutsideLines then
  begin
    Result := Length(FLines) + OrphanBounds.Count;
    const Bounds = BoundsOf(Fragment.Quads);
    OrphanBounds.Add(Bounds);
  end;
end;

procedure TPdfPageText.SortLinesByStart;
begin
  SetLength(FLinesByStart, Length(FLines));
  for var Index := 0 to High(FLines) do
  begin
    FLinesByStart[Index] := Index;
  end;

  TArray.Sort<Integer>(FLinesByStart, TComparer<Integer>.Construct(
    function(const Left, Right: Integer): Integer
    begin
      Result := TComparer<Integer>.Default.Compare(FLines[Left].Start, FLines[Right].Start);
    end));
end;

// The line whose range holds Start, or -1
function TPdfPageText.FindLineOf(const Start: Integer): Integer;
begin
  var Lower := 0;
  var Upper := Length(FLinesByStart) - 1;
  while Lower <= Upper do
  begin
    const Middle = (Lower + Upper) div 2;
    const Line = FLines[FLinesByStart[Middle]];
    const IsBefore = (Start < Line.Start);
    const IsAfter = (Start >= (Line.Start + Line.Length));
    if IsBefore then
    begin
      Upper := Middle - 1;
    end
    else if IsAfter then
    begin
      Lower := Middle + 1;
    end
    else
    begin
      Exit(FLinesByStart[Middle]);
    end;
  end;
  Result := -1;
end;

procedure TPdfPageText.CheckWordIndex(const WordIndex: Integer);
begin
  const IsInside = ((WordIndex >= 0) and (WordIndex < Length(FWords)));
  if not IsInside then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('Word index %d is outside the %d words', [WordIndex, Length(FWords)]);
  end;
end;

function TPdfPageText.PageIndex: Integer;
begin
  Result := FPageIndex;
end;

function TPdfPageText.IsEmpty: Boolean;
begin
  Result := (Length(FWords) = 0);
end;

function TPdfPageText.Words: TArray<TPdfTextFragment>;
begin
  Result := FWords;
end;

function TPdfPageText.Segments: TArray<TPdfTextFragment>;
begin
  Result := FSegments;
end;

function TPdfPageText.Lines: TArray<TPdfTextFragment>;
begin
  Result := FLines;
end;

function TPdfPageText.Links: TArray<TPdfLink>;
begin
  Result := FLinks;
end;

function TPdfPageText.TryFindSegmentAt(const Point: TPointF; out Segment: TPdfTextFragment): Boolean;
begin
  for var GroupIndex := 0 to High(FGroups) do
  begin
    if ContainsPoint(FGroups[GroupIndex].Bounds, Point) then
    begin
      for var SegmentIndex in FGroups[GroupIndex].Segments do
      begin
        if AnyQuadContains(FSegments[SegmentIndex].Quads, Point) then
        begin
          Segment := FSegments[SegmentIndex];
          Exit(True);
        end;
      end;
    end;
  end;

  Segment := Default(TPdfTextFragment);
  Result := False;
end;

function TPdfPageText.TryFindWordAt(const Point: TPointF; out WordIndex: Integer): Boolean;
begin
  for var GroupIndex := 0 to High(FGroups) do
  begin
    if ContainsPoint(FGroups[GroupIndex].Bounds, Point) then
    begin
      for var Candidate in FGroups[GroupIndex].Words do
      begin
        if AnyQuadContains(FWords[Candidate].Quads, Point) then
        begin
          WordIndex := Candidate;
          Exit(True);
        end;
      end;
    end;
  end;

  WordIndex := -1;
  Result := False;
end;

function TPdfPageText.TryFindNearestWord(const Point: TPointF; out WordIndex: Integer): Boolean;
begin
  WordIndex := -1;
  if IsEmpty then
  begin
    Exit(False);
  end;

  WordIndex := 0;
  var NearestDistance := MaxSingle;
  for var Candidate := 0 to High(FWords) do
  begin
    for var Quad in FWords[Candidate].Quads do
    begin
      const Distance = Quad.DistanceTo(Point);
      if Distance < NearestDistance then
      begin
        NearestDistance := Distance;
        WordIndex := Candidate;
      end;
    end;
  end;
  Result := True;
end;

function TPdfPageText.TryFindLinkAt(const Point: TPointF; out Link: TPdfLink): Boolean;
begin
  for var Index := High(FLinks) downto 0 do
  begin
    if AnyQuadContains(FLinks[Index].Quads, Point) then
    begin
      Link := FLinks[Index];
      Exit(True);
    end;
  end;

  Link := Default(TPdfLink);
  Result := False;
end;

function TPdfPageText.BuildSelectionQuads(const First, Last: Integer): TArray<TPdfQuad>;
begin
  const Quads = TList<TPdfQuad>.Create;
  try
    var LineGroup := -1;
    for var WordIndex := First to Last do
    begin
      for var Quad in FWords[WordIndex].Quads do
      begin
        const IsNewLine = (FWordGroups[WordIndex] <> LineGroup);
        if IsNewLine then
        begin
          Quads.Add(Quad);
          LineGroup := FWordGroups[WordIndex];
        end
        else
        begin
          Quads[Quads.Count - 1] := Quads[Quads.Count - 1].Extend(Quad);
        end;
      end;
    end;
    Result := Quads.ToArray;
  finally
    Quads.Free;
  end;
end;

function TPdfPageText.JoinSelectionText(const First, Last: Integer): string;
begin
  const Builder = TStringBuilder.Create;
  try
    for var WordIndex := First to Last do
    begin
      const IsAfterFirst = (WordIndex > First);
      const IsNewLine = (IsAfterFirst and (FWordGroups[WordIndex] <> FWordGroups[WordIndex - 1]));
      if IsNewLine then
      begin
        Builder.Append(sLineBreak);
      end
      else if IsAfterFirst then
      begin
        Builder.Append(' ');
      end;
      Builder.Append(FWords[WordIndex].Text);
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

function TPdfPageText.Select(const AnchorWord, FocusWord: Integer; const Kind: TPdfSelectionKind): TPdfTextSelection;
begin
  CheckWordIndex(AnchorWord);
  CheckWordIndex(FocusWord);

  const First = Min(AnchorWord, FocusWord);
  const Last = Max(AnchorWord, FocusWord);
  Result.Kind := Kind;
  Result.PageIndex := FPageIndex;
  Result.Text := JoinSelectionText(First, Last);
  Result.Quads := BuildSelectionQuads(First, Last);
end;

function TPdfPageText.SelectAll: TPdfTextSelection;
begin
  if IsEmpty then
  begin
    Result := Default(TPdfTextSelection);
    Result.Kind := TPdfSelectionKind.Drag;
    Result.PageIndex := FPageIndex;
    Exit;
  end;

  Result := Select(0, High(FWords), TPdfSelectionKind.Drag);
end;

end.
