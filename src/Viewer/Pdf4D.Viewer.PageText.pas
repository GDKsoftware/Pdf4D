// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.PageText;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  Pdf4D.Api.Page.Interfaces,
  Pdf4D.Api.TextLayout.Interfaces,
  Pdf4D.Viewer.Types;

type
  // Immutable snapshot made on the worker; safe to share between threads.
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
    function AddOrphanGroup(const Fragment: TPdfTextFragment): Integer;
    procedure AddWordToGroups(const WordIndex: Integer);
    procedure AddSegmentToGroups(const SegmentIndex: Integer);
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
  System.Generics.Collections,
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
  const Crosses = TArray<Single>.Create(Cross(P1, P2, Point), Cross(P2, P3, Point), Cross(P3, P4, Point), Cross(P4, P1, Point));
  var HasNegative := False;
  var HasPositive := False;
  for var Value in Crosses do
  begin
    HasNegative := HasNegative or (Value < 0);
    HasPositive := HasPositive or (Value > 0);
  end;

  Result := (IsFinite and not (HasNegative and HasPositive));
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

procedure TPdfPageText.BuildGroups;
begin
  SetLength(FGroups, Length(FLines));
  for var Index := 0 to High(FLines) do
  begin
    FGroups[Index].Bounds := BoundsOf(FLines[Index].Quads);
  end;
  SortLinesByStart;

  SetLength(FWordGroups, Length(FWords));
  for var Index := 0 to High(FWords) do
  begin
    AddWordToGroups(Index);
  end;
  for var Index := 0 to High(FSegments) do
  begin
    AddSegmentToGroups(Index);
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

function TPdfPageText.AddOrphanGroup(const Fragment: TPdfTextFragment): Integer;
begin
  Result := Length(FGroups);
  SetLength(FGroups, Result + 1);
  FGroups[Result].Bounds := BoundsOf(Fragment.Quads);
end;

procedure TPdfPageText.AddWordToGroups(const WordIndex: Integer);
begin
  var GroupIndex := FindLineOf(FWords[WordIndex].Start);
  const IsOutsideLines = (GroupIndex < 0);
  if IsOutsideLines then
  begin
    GroupIndex := AddOrphanGroup(FWords[WordIndex]);
  end;

  FGroups[GroupIndex].Words := FGroups[GroupIndex].Words + [WordIndex];
  FWordGroups[WordIndex] := GroupIndex;
end;

procedure TPdfPageText.AddSegmentToGroups(const SegmentIndex: Integer);
begin
  var GroupIndex := FindLineOf(FSegments[SegmentIndex].Start);
  const IsOutsideLines = (GroupIndex < 0);
  if IsOutsideLines then
  begin
    GroupIndex := AddOrphanGroup(FSegments[SegmentIndex]);
  end;

  FGroups[GroupIndex].Segments := FGroups[GroupIndex].Segments + [SegmentIndex];
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
  for var Group in FGroups do
  begin
    if ContainsPoint(Group.Bounds, Point) then
    begin
      for var SegmentIndex in Group.Segments do
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
  for var Group in FGroups do
  begin
    if ContainsPoint(Group.Bounds, Point) then
    begin
      for var Candidate in Group.Words do
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
  Result := nil;
  var LineGroup := -1;
  for var WordIndex := First to Last do
  begin
    for var Quad in FWords[WordIndex].Quads do
    begin
      const IsNewLine = (FWordGroups[WordIndex] <> LineGroup);
      if IsNewLine then
      begin
        Result := Result + [Quad];
        LineGroup := FWordGroups[WordIndex];
      end
      else
      begin
        Result[High(Result)] := Result[High(Result)].Extend(Quad);
      end;
    end;
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
