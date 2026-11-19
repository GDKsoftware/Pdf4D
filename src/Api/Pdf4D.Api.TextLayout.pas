// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Api.TextLayout;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  Pdf4D.Api.TextLayout.Interfaces,
  Pdf4D.Text.Layout,
  Pdf4D.Text.PositionedText;

type
  // Owns the positioned text. It is a copy of what was read: it keeps no reference to the document.
  TPdfPositionedTextResult = class(TInterfacedObject, IPdfPositionedText)
  private
    FPositioned: TPdfPositionedText;

  public
    // Takes the ownership of Positioned
    constructor Create(const Positioned: TPdfPositionedText);
    destructor Destroy; override;

    function Text: string;
    function Locate(const Start, Length: Integer): TArray<TPdfTextFragment>;
  end;

  TPdfTextLayout = class(TInterfacedObject, IPdfTextLayout)
  private
    FPageIndex: Integer;
    FText: string;
    FWords: TArray<TPdfTextFragment>;
    FSegments: TArray<TPdfTextFragment>;
    FLines: TArray<TPdfTextFragment>;

    // Dynamic arrays are shared on assignment, so what leaves the layout is copied, quads included
    class function CopyOf(const Fragment: TPdfTextFragment): TPdfTextFragment; static;
    class function CopiesOf(const Fragments: TArray<TPdfTextFragment>): TArray<TPdfTextFragment>; static;
    class function ToFragments(const PageIndex: Integer; const Items: TArray<TPdfLayoutItem>): TArray<TPdfTextFragment>; static;
    class function TryFindAt(const Fragments: TArray<TPdfTextFragment>; const Point: TPointF; out Fragment: TPdfTextFragment): Boolean; static;

  public
    constructor Create(const Layout: TPdfPageLayout; const Text: string);

    // Whether the point lies in the quad, edges included. A quad that is not finite or has no area contains no point.
    class function IsInsideQuad(const Point: TPointF; const Quad: TPdfQuad): Boolean; static;

    function PageIndex: Integer;
    function Text: string;
    function Words: TArray<TPdfTextFragment>;
    function Segments: TArray<TPdfTextFragment>;
    function Lines: TArray<TPdfTextFragment>;
    function TryFindSegmentAt(const Point: TPointF; out Fragment: TPdfTextFragment): Boolean;
    function TryFindWordAt(const Point: TPointF; out Fragment: TPdfTextFragment): Boolean;
  end;

implementation

{ TPdfPositionedTextResult }

constructor TPdfPositionedTextResult.Create(const Positioned: TPdfPositionedText);
begin
  inherited Create;
  FPositioned := Positioned;
end;

destructor TPdfPositionedTextResult.Destroy;
begin
  FPositioned.Free;
  inherited;
end;

function TPdfPositionedTextResult.Text: string;
begin
  Result := FPositioned.Text;
end;

function TPdfPositionedTextResult.Locate(const Start, Length: Integer): TArray<TPdfTextFragment>;
begin
  const Runs = FPositioned.Locate(Start, Length);

  SetLength(Result, System.Length(Runs));
  for var Index := 0 to High(Runs) do
  begin
    Result[Index].PageIndex := Runs[Index].PageIndex;
    Result[Index].Text := Runs[Index].Text;
    Result[Index].Quads := Runs[Index].Quads;
    Result[Index].Start := 0;
    Result[Index].Length := 0;
  end;
end;

{ TPdfTextLayout }

constructor TPdfTextLayout.Create(const Layout: TPdfPageLayout; const Text: string);
begin
  inherited Create;
  FPageIndex := Layout.PageIndex;
  FText := Text;
  FWords := ToFragments(Layout.PageIndex, Layout.Words);
  FSegments := ToFragments(Layout.PageIndex, Layout.Segments);
  FLines := ToFragments(Layout.PageIndex, Layout.Lines);
end;

class function TPdfTextLayout.ToFragments(const PageIndex: Integer; const Items: TArray<TPdfLayoutItem>): TArray<TPdfTextFragment>;
begin
  SetLength(Result, Length(Items));
  for var Index := 0 to High(Items) do
  begin
    Result[Index].PageIndex := PageIndex;
    Result[Index].Text := Items[Index].Text;
    Result[Index].Quads := Items[Index].Quads;
    Result[Index].Start := Items[Index].Start;
    Result[Index].Length := Items[Index].Length;
  end;
end;

class function TPdfTextLayout.CopyOf(const Fragment: TPdfTextFragment): TPdfTextFragment;
begin
  Result := Fragment;
  Result.Quads := Copy(Fragment.Quads);
end;

class function TPdfTextLayout.CopiesOf(const Fragments: TArray<TPdfTextFragment>): TArray<TPdfTextFragment>;
begin
  SetLength(Result, Length(Fragments));
  for var Index := 0 to High(Fragments) do
  begin
    Result[Index] := CopyOf(Fragments[Index]);
  end;
end;

// A convex quad holds the point when the point lies on the same side of all four edges, whichever way the corners run
class function TPdfTextLayout.IsInsideQuad(const Point: TPointF; const Quad: TPdfQuad): Boolean;
begin
  if not Quad.IsFinite then
  begin
    Exit(False);
  end;

  const Corners: TArray<TPointF> = [Quad.P1, Quad.P2, Quad.P3, Quad.P4];

  var HasPositive := False;
  var HasNegative := False;
  for var Index := 0 to High(Corners) do
  begin
    const From = Corners[Index];
    const Till = Corners[(Index + 1) mod Length(Corners)];
    const Cross = (Double(Till.X) - From.X) * (Double(Point.Y) - From.Y) - (Double(Till.Y) - From.Y) * (Double(Point.X) - From.X);
    HasPositive := (HasPositive or (Cross > 0));
    HasNegative := (HasNegative or (Cross < 0));
  end;

  // Without a nonzero cross product (a quad without area, or a point that is not finite) there is nothing to say the point is inside
  Result := (HasPositive xor HasNegative);
end;

class function TPdfTextLayout.TryFindAt(const Fragments: TArray<TPdfTextFragment>; const Point: TPointF; out Fragment: TPdfTextFragment): Boolean;
begin
  for var Candidate in Fragments do
  begin
    for var Quad in Candidate.Quads do
    begin
      if IsInsideQuad(Point, Quad) then
      begin
        Fragment := CopyOf(Candidate);
        Exit(True);
      end;
    end;
  end;

  Fragment := Default(TPdfTextFragment);
  Result := False;
end;

function TPdfTextLayout.PageIndex: Integer;
begin
  Result := FPageIndex;
end;

function TPdfTextLayout.Text: string;
begin
  Result := FText;
end;

function TPdfTextLayout.Words: TArray<TPdfTextFragment>;
begin
  Result := CopiesOf(FWords);
end;

function TPdfTextLayout.Segments: TArray<TPdfTextFragment>;
begin
  Result := CopiesOf(FSegments);
end;

function TPdfTextLayout.Lines: TArray<TPdfTextFragment>;
begin
  Result := CopiesOf(FLines);
end;

function TPdfTextLayout.TryFindSegmentAt(const Point: TPointF; out Fragment: TPdfTextFragment): Boolean;
begin
  Result := TryFindAt(FSegments, Point, Fragment);
end;

function TPdfTextLayout.TryFindWordAt(const Point: TPointF; out Fragment: TPdfTextFragment): Boolean;
begin
  Result := TryFindAt(FWords, Point, Fragment);
end;

end.
