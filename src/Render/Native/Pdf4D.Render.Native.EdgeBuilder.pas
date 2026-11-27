// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: tiny-skia v0.12.0 src/edge_builder.rs
// Copyright (c) 2011 Google Inc., (c) 2020 Yevhenii Reizner. BSD-3-Clause, see licenses/tiny-skia-BSD-3-Clause.txt.
unit Pdf4D.Render.Native.EdgeBuilder;

{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

uses
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.PathGeometry,
  Pdf4D.Render.Native.Path,
  Pdf4D.Render.Native.Edge,
  Pdf4D.Render.Native.EdgeClipper;

// Builds the edges of a path for the scan converter. Skia returns a linked list here; Rust mimics it with a Vec and so does this port
// with a dynamic array that grows by doubling (memory and time are linear in the number of segments).
//
// PathEdge and PathEdgeIter are in the edge clipper unit (see there).
//
// The Rust build_edges takes an optional clip; TryBuildEdges is the clipped one and TryBuildEdgesUnclipped the one with None. A shift
// outside 0..TTsLineEdge.MaxShift (Rust uses 0 and 2) gives False.

type
  TTsShiftedIntRect = record
  private
    FShifted: TTsScreenIntRect;
    FRecovered: TTsScreenIntRect;
    FShift: Integer;

  public
    class function TryCreate(const Rect: TTsScreenIntRect; const Shift: Integer; out Shifted: TTsShiftedIntRect): Boolean; static;

    function Shifted: TTsScreenIntRect;
    function Recover: TTsScreenIntRect;
  end;

  TTsBasicEdgeBuilder = record
  private type
    TCombine = (
      No,
      Partial,
      Total);

  private
    FEdges: TArray<TTsEdge>;
    FCount: Integer;
    FClipShift: Integer;

    procedure Append(const Edge: TTsEdge);
    function TryBuild(const Path: TTsPath; const HasClip: Boolean; const Clip: TTsShiftedIntRect; const CanCullToTheRight: Boolean): Boolean;
    procedure PushLine(const P0, P1: TTsPoint);
    procedure PushQuad(const Points: array of TTsPoint; const PointsOffset: Integer);
    procedure PushCubic(const Points: array of TTsPoint; const PointsOffset: Integer);
    class function CombineVertical(const Edge: TTsLineEdge; var Last: TTsLineEdge): TCombine; static;

  public
    class function Create(const ClipShift: Integer): TTsBasicEdgeBuilder; static;

    // Returns False for a path with infinite or NaN segments after clipping, and for fewer than 2 edges
    class function TryBuildEdges(const Path: TTsPath; const Clip: TTsShiftedIntRect; const ClipShift: Integer;
                                 out Edges: TArray<TTsEdge>): Boolean; static;
    class function TryBuildEdgesUnclipped(const Path: TTsPath; const ClipShift: Integer; out Edges: TArray<TTsEdge>): Boolean; static;
  end;

implementation

const
  InitialCapacity = 64;

{ TTsShiftedIntRect }

class function TTsShiftedIntRect.TryCreate(const Rect: TTsScreenIntRect; const Shift: Integer; out Shifted: TTsShiftedIntRect): Boolean;
begin
  Shifted := Default(TTsShiftedIntRect);

  if (Shift < 0) or (Shift > TTsLineEdge.MaxShift) then
  begin
    Exit(False);
  end;

  // u32 shifts lose the bits that do not fit
  if not TTsScreenIntRect.TryFromXYWH(Rect.X shl Shift, Rect.Y shl Shift, Rect.Width shl Shift, Rect.Height shl Shift, Shifted.FShifted) then
  begin
    Exit(False);
  end;

  // Rust unwraps this one in recover(), because the original rect was valid; the bits of a shifted rect that lost some can still fail
  if not TTsScreenIntRect.TryFromXYWH(Shifted.FShifted.X shr Shift, Shifted.FShifted.Y shr Shift, Shifted.FShifted.Width shr Shift,
                                      Shifted.FShifted.Height shr Shift, Shifted.FRecovered) then
  begin
    Shifted := Default(TTsShiftedIntRect);
    Exit(False);
  end;

  Shifted.FShift := Shift;
  Result := True;
end;

function TTsShiftedIntRect.Shifted: TTsScreenIntRect;
begin
  Result := FShifted;
end;

function TTsShiftedIntRect.Recover: TTsScreenIntRect;
begin
  Result := FRecovered;
end;

{ TTsBasicEdgeBuilder }

class function TTsBasicEdgeBuilder.Create(const ClipShift: Integer): TTsBasicEdgeBuilder;
begin
  Result := Default(TTsBasicEdgeBuilder);
  Result.FClipShift := ClipShift;
  SetLength(Result.FEdges, InitialCapacity);
end;

class function TTsBasicEdgeBuilder.TryBuildEdges(const Path: TTsPath; const Clip: TTsShiftedIntRect; const ClipShift: Integer;
                                                 out Edges: TArray<TTsEdge>): Boolean;
begin
  Edges := nil;

  // If we're convex, then we need both edges, even if the right edge is past the clip.
  // let can_cull_to_the_right = !path.isConvex();
  const CanCullToTheRight = False; // TODO: this

  var Builder := Create(ClipShift);
  if not Builder.TryBuild(Path, True, Clip, CanCullToTheRight) then
  begin
    // infinite or NaN segments detected during edges building
    Exit(False);
  end;

  if Builder.FCount < 2 then
  begin
    Exit(False);
  end;

  SetLength(Builder.FEdges, Builder.FCount);
  Edges := Builder.FEdges;
  Result := True;
end;

class function TTsBasicEdgeBuilder.TryBuildEdgesUnclipped(const Path: TTsPath; const ClipShift: Integer;
                                                          out Edges: TArray<TTsEdge>): Boolean;
begin
  Edges := nil;

  var Builder := Create(ClipShift);
  if not Builder.TryBuild(Path, False, Default(TTsShiftedIntRect), False) then
  begin
    Exit(False);
  end;

  if Builder.FCount < 2 then
  begin
    Exit(False);
  end;

  SetLength(Builder.FEdges, Builder.FCount);
  Edges := Builder.FEdges;
  Result := True;
end;

function TTsBasicEdgeBuilder.TryBuild(const Path: TTsPath; const HasClip: Boolean; const Clip: TTsShiftedIntRect;
                                      const CanCullToTheRight: Boolean): Boolean;
begin
  if (FClipShift < 0) or (FClipShift > TTsLineEdge.MaxShift) then
  begin
    Exit(False);
  end;

  if HasClip then
  begin
    const ClipRect = Clip.Recover.ToRect;

    var Iter := TTsEdgeClipperIter.Create(Path, ClipRect, CanCullToTheRight);
    var Edges: TTsClippedEdges;
    while Iter.TryNext(Edges) do
    begin
      for var Index := 0 to Edges.Count - 1 do
      begin
        const Edge = Edges.Items[Index];

        case Edge.Kind of
          TTsPathEdgeKind.LineTo:
          begin
            if (not Edge.P0.IsFinite) or (not Edge.P1.IsFinite) then
            begin
              Exit(False);
            end;

            PushLine(Edge.P0, Edge.P1);
          end;

          TTsPathEdgeKind.QuadTo:
          begin
            if (not Edge.P0.IsFinite) or (not Edge.P1.IsFinite) or (not Edge.P2.IsFinite) then
            begin
              Exit(False);
            end;

            PushQuad([Edge.P0, Edge.P1, Edge.P2], 0);
          end;
        else
          if (not Edge.P0.IsFinite) or (not Edge.P1.IsFinite) or (not Edge.P2.IsFinite) or (not Edge.P3.IsFinite) then
          begin
            Exit(False);
          end;

          PushCubic([Edge.P0, Edge.P1, Edge.P2, Edge.P3], 0);
        end;
      end;
    end;

    Exit(True);
  end;

  var Iter := TTsPathEdgeIter.Create(Path);
  var Edge: TTsPathEdge;
  while Iter.TryNext(Edge) do
  begin
    case Edge.Kind of
      TTsPathEdgeKind.LineTo:
        PushLine(Edge.P0, Edge.P1);

      TTsPathEdgeKind.QuadTo:
      begin
        var QuadPoints: TTsPoints3;
        QuadPoints[0] := Edge.P0;
        QuadPoints[1] := Edge.P1;
        QuadPoints[2] := Edge.P2;

        var MonoX: TTsPoints5;
        for var Index := 0 to High(MonoX) do
        begin
          MonoX[Index] := TTsPoint.Zero;
        end;

        const QuadCount = TTsPathGeometry.ChopQuadAtYExtrema(QuadPoints, MonoX);
        for var Index := 0 to QuadCount do
        begin
          PushQuad(MonoX, Index * 2);
        end;
      end;
    else
      var CubicPoints: TTsPoints4;
      CubicPoints[0] := Edge.P0;
      CubicPoints[1] := Edge.P1;
      CubicPoints[2] := Edge.P2;
      CubicPoints[3] := Edge.P3;

      var MonoY: TTsPoints10;
      for var Index := 0 to High(MonoY) do
      begin
        MonoY[Index] := TTsPoint.Zero;
      end;

      const CubicCount = TTsPathGeometry.ChopCubicAtYExtrema(CubicPoints, MonoY);
      for var Index := 0 to CubicCount do
      begin
        PushCubic(MonoY, Index * 3);
      end;
    end;
  end;

  Result := True;
end;

procedure TTsBasicEdgeBuilder.Append(const Edge: TTsEdge);
begin
  if FCount = Length(FEdges) then
  begin
    SetLength(FEdges, Length(FEdges) * 2);
  end;

  FEdges[FCount] := Edge;
  Inc(FCount);
end;

procedure TTsBasicEdgeBuilder.PushLine(const P0, P1: TTsPoint);
begin
  var Line: TTsLineEdge;
  if not TTsLineEdge.TryCreate(P0, P1, FClipShift, Line) then
  begin
    Exit;
  end;

  var Combine := TCombine.No;
  if Line.IsVertical and (FCount > 0) and (FEdges[FCount - 1].Kind = TTsEdgeKind.Line) then
  begin
    Combine := CombineVertical(Line, FEdges[FCount - 1].Line);
  end;

  case Combine of
    TCombine.Total:
      Dec(FCount);

    TCombine.Partial:
      ;
  else
    var Edge := Default(TTsEdge);
    Edge.Kind := TTsEdgeKind.Line;
    Edge.Line := Line;
    Append(Edge);
  end;
end;

procedure TTsBasicEdgeBuilder.PushQuad(const Points: array of TTsPoint; const PointsOffset: Integer);
begin
  var Quadratic: TTsQuadraticEdge;
  if TTsQuadraticEdge.TryCreate(Points, PointsOffset, FClipShift, Quadratic) then
  begin
    var Edge := Default(TTsEdge);
    Edge.Kind := TTsEdgeKind.Quadratic;
    Edge.Quadratic := Quadratic;
    Append(Edge);
  end;
end;

procedure TTsBasicEdgeBuilder.PushCubic(const Points: array of TTsPoint; const PointsOffset: Integer);
begin
  var Cubic: TTsCubicEdge;
  if TTsCubicEdge.TryCreate(Points, PointsOffset, FClipShift, Cubic) then
  begin
    var Edge := Default(TTsEdge);
    Edge.Kind := TTsEdgeKind.Cubic;
    Edge.Cubic := Cubic;
    Append(Edge);
  end;
end;

class function TTsBasicEdgeBuilder.CombineVertical(const Edge: TTsLineEdge; var Last: TTsLineEdge): TCombine;
begin
  if (Last.Dx <> 0) or (Edge.X <> Last.X) then
  begin
    Exit(TCombine.No);
  end;

  if Edge.Winding = Last.Winding then
  begin
    if TTsScalar.WrappingAddI32(Edge.LastY, 1) = Last.FirstY then
    begin
      Last.FirstY := Edge.FirstY;
      Exit(TCombine.Partial);
    end;

    if Edge.FirstY = TTsScalar.WrappingAddI32(Last.LastY, 1) then
    begin
      Last.LastY := Edge.LastY;
      Exit(TCombine.Partial);
    end;

    Exit(TCombine.No);
  end;

  if Edge.FirstY = Last.FirstY then
  begin
    if Edge.LastY = Last.LastY then
    begin
      Exit(TCombine.Total);
    end;

    if Edge.LastY < Last.LastY then
    begin
      Last.FirstY := TTsScalar.WrappingAddI32(Edge.LastY, 1);
      Exit(TCombine.Partial);
    end;

    Last.FirstY := TTsScalar.WrappingAddI32(Last.LastY, 1);
    Last.LastY := Edge.LastY;
    Last.Winding := Edge.Winding;
    Exit(TCombine.Partial);
  end;

  if Edge.LastY = Last.LastY then
  begin
    if Edge.FirstY > Last.FirstY then
    begin
      Last.LastY := TTsScalar.WrappingSubI32(Edge.FirstY, 1);
    end
    else
    begin
      Last.LastY := TTsScalar.WrappingSubI32(Last.FirstY, 1);
      Last.FirstY := Edge.FirstY;
      Last.Winding := Edge.Winding;
    end;

    Exit(TCombine.Partial);
  end;

  Result := TCombine.No;
end;

end.
