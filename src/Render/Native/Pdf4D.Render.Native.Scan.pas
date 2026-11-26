// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: tiny-skia v0.12.0 src/scan/mod.rs
// Port of: tiny-skia v0.12.0 src/scan/path.rs
// Copyright (c) 2006 The Android Open Source Project, (c) 2011 Google Inc., (c) 2020 Yevhenii Reizner. BSD-3-Clause, see licenses/tiny-skia-BSD-3-Clause.txt.
unit Pdf4D.Render.Native.Scan;

{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  System.Math,
  Pdf4D.Render.Native.Scalar,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.FixedPoint,
  Pdf4D.Render.Native.Path,
  Pdf4D.Render.Native.Edge,
  Pdf4D.Render.Native.EdgeBuilder,
  Pdf4D.Render.Native.Blitter,
  Pdf4D.Render.Native.Scan.HairlineAntiAlias;

// The non-anti-aliased scan converter and the rectangle fills of scan/mod.rs.
//
// Rust panics reachable from input become early exits that draw nothing: a path whose edges cannot be built, a shift outside the edge
// builder's range and a span whose right end lies left of its start (u32 subtraction in Rust). The walk of the edges draws one row in Rust
// even when the rows to draw are empty. With clipped edges no edge is active in that row, so nothing is drawn there either; the two only
// differ after the row shift has wrapped (|y| of about 5.4e8 and more), where here nothing is drawn.
//
// The edge list of Rust is a Vec with indices as links; the sort of Rust is stable, so the sort here is a merge sort on (first_y, x).
//
// Deviations from tiny-skia that keep its pixels and bound its worst case (a path whose edges cross each other on many rows takes time
// that grows with the square of their number when each edge ripples back to its place, as Skia does):
// 1. When the edges of a row have rippled back more than a few steps per edge, the rest of the row only updates the edges and the active
//    list is sorted once at the end of the row, with the stable merge sort. The insertion of Rust is a stable sort as well, so the list
//    is the same.
// 2. Before the walk, an upper bound of its work is taken from the rows that the edges span (16 units for an edge in a row, 1024 for a row);
//    when it is over the limit of the scan converter (EdgeWorkLimit) the fill raises EPdfLimitExceededException before it draws anything.
//    The walk counts its work as well (edges visited, steps rippled, a sort) and stops at the limit; with the bound that is a guard only,
//    which a mode of the sort that is not Auto can reach.
//
// Must run inside TTsFloatMode, like the edge builder it uses.

type
  TTsFillRule = (
    Winding,
    EvenOdd);

  TTsScan = record
  private type
    TSortItem = record
      Key: Int64;
      Index: Integer;
    end;

  public const
    // The default limit of the work of one path in the walk of its edges: a unit is 3 for an edge in a row of the walk (a row of the
    // anti-aliased walk is a quarter of a pixel row), 1 for a step of an edge that ripples back and 8 per edge of a row that is sorted.
    DefaultEdgeWorkLimit: Int64 = 800000000;

{$IFDEF PDF4D_TESTS}
  public type
    // How a row of the walk puts the edges that moved back in order: ripple each one back (Never), sort the list at the end of the row
    // (Always), or ripple until it takes more than a few steps per edge and then sort (Auto, the default). The three give the same
    // pixels; the other two are for the tests, which are compiled with PDF4D_TESTS. Without it the mode is Auto.
    TDeferMode = (Auto, Always, Never);

  public class var
    DeferMode: TDeferMode;
    // The number of rows that were sorted at their end, and how many of those were switched to that by the Auto mode in the middle of the row
    DeferredRowCount: Integer;
    AutoSwitchCount: Integer;
{$ENDIF}

  private const
    // Bias used for conservative rounding of float rects to int rects, to nudge the irects a little larger, so we don't "think" a path's
    // bounds are inside a clip, when (due to numeric drift in the scan-converter) we might walk beyond the predicted limits.
    ConservativeRoundBias: Double = 0.5 + 1.5 / TTsFdot6.One;

  private
    class function RoundDownToInt(const X: Single): Integer; static;
    class function RoundUpToInt(const X: Single): Integer; static;
    class function TryConservativeRoundToInt(const Src: TTsRect; out Rounded: TTsIntRect): Boolean; static;
    class procedure FillIntRect(const Rect: TTsIntRect; const Clip: TTsScreenIntRect; const Blitter: TTsBlitter); static;

    class procedure MergeSort(var Items, Scratch: TArray<TSortItem>; const Count: Integer); static;
    class procedure SortEdges(var Edges: TArray<TTsEdge>); static;
    class function EdgeWorkBound(const Edges: TArray<TTsEdge>; const StartY, StopY: Integer): Int64; static;
    class procedure SortActiveEdges(const FirstInactiveIdx: Integer; var Edges: TArray<TTsEdge>; var Items, Scratch: TArray<TSortItem>); static;
    class function WalkEdges(const FillRule: TTsFillRule; const StartY, StopY, RightClip: Cardinal; var Edges: TArray<TTsEdge>;
                             const Blitter: TTsBlitter): Boolean; static;
    class procedure RemoveEdge(const CurrIdx: Integer; var Edges: TArray<TTsEdge>); static;
    class function BackwardInsertEdgeBasedOnX(const CurrIdx: Integer; var Edges: TArray<TTsEdge>): Integer; static;
    class procedure Reposition(const CurrIdx, Visited: Integer; var Edges: TArray<TTsEdge>; var Rippled: Integer; var IsDeferred: Boolean); static;
    class procedure InsertEdgeAfter(const CurrIdx, AfterIdx: Integer; var Edges: TArray<TTsEdge>); static;
    class function BackwardInsertStart(const PrevIdx, X: Integer; var Edges: TArray<TTsEdge>): Integer; static;
    class procedure InsertNewEdges(const NewIdx, CurrY: Integer; var Edges: TArray<TTsEdge>); static;

  public
    // The limit of the work of a path, of the calling thread; 0 (the start value of a thread) is DefaultEdgeWorkLimit. The device sets it
    // from its limits for each draw.
    class function EdgeWorkLimit: Int64; static;
    class procedure SetEdgeWorkLimit(const Value: Int64); static;
    // With the dry run on, a fill takes the bound of its work, raises when it is over the limit, and else draws nothing. A draw in tiles
    // makes a dry run over all of them first, so that a tile over the limit raises before another one is drawn.
    class procedure SetEdgeWorkDryRun(const Value: Boolean); static;

    class procedure FillRect(const Rect: TTsRect; const Clip: TTsScreenIntRect; const Blitter: TTsBlitter); static;
    class procedure FillRectAntiAlias(const Rect: TTsRect; const Clip: TTsScreenIntRect; const Blitter: TTsBlitter); static;

    class procedure FillPath(const Path: TTsPath; const FillRule: TTsFillRule; const Clip: TTsScreenIntRect;
                             const Blitter: TTsBlitter); static;

    // The shared walk of the non-anti-aliased and the anti-aliased fill. StartY and StopY are in pixels, the walk shifts them.
    class procedure FillPathImpl(const Path: TTsPath; const FillRule: TTsFillRule; const ClipRect: TTsScreenIntRect;
                                 const StartY, StopY, ShiftEdgesUp: Integer; const PathContainedInClip: Boolean;
                                 const Blitter: TTsBlitter); static;
  end;

implementation

uses
  Pdf4D.Common.Defines;

threadvar
  GEdgeWorkLimit: Int64;
  GEdgeWorkDryRun: Boolean;

{ TTsScan }

class function TTsScan.EdgeWorkLimit: Int64;
begin
  Result := GEdgeWorkLimit;
  if Result <= 0 then
  begin
    Result := DefaultEdgeWorkLimit;
  end;
end;

class procedure TTsScan.SetEdgeWorkLimit(const Value: Int64);
begin
  GEdgeWorkLimit := Value;
end;

class procedure TTsScan.SetEdgeWorkDryRun(const Value: Boolean);
begin
  GEdgeWorkDryRun := Value;
end;

class procedure TTsScan.FillRect(const Rect: TTsRect; const Clip: TTsScreenIntRect; const Blitter: TTsBlitter);
begin
  var Rounded: TTsIntRect;
  if Rect.TryRound(Rounded) then
  begin
    FillIntRect(Rounded, Clip, Blitter);
  end;
end;

class procedure TTsScan.FillIntRect(const Rect: TTsIntRect; const Clip: TTsScreenIntRect; const Blitter: TTsBlitter);
begin
  var Clipped: TTsIntRect;
  if not Rect.TryIntersect(Clip.ToIntRect, Clipped) then
  begin
    // everything was clipped out
    Exit;
  end;

  var ScreenRect: TTsScreenIntRect;
  if not Clipped.TryToScreenIntRect(ScreenRect) then
  begin
    Exit;
  end;

  Blitter.BlitRect(ScreenRect);
end;

class procedure TTsScan.FillRectAntiAlias(const Rect: TTsRect; const Clip: TTsScreenIntRect; const Blitter: TTsBlitter);
begin
  TTsScanHairlineAntiAlias.FillRect(Rect, Clip, Blitter);
end;

class procedure TTsScan.FillPath(const Path: TTsPath; const FillRule: TTsFillRule; const Clip: TTsScreenIntRect;
                                 const Blitter: TTsBlitter);
begin
  var Ir: TTsIntRect;
  if not TryConservativeRoundToInt(Path.Bounds, Ir) then
  begin
    Exit;
  end;

  // If the bounds cannot be converted into a ScreenIntRect, the path is out of clip.
  var PathContainedInClip := False;
  var Bounds: TTsScreenIntRect;
  if Ir.TryToScreenIntRect(Bounds) then
  begin
    PathContainedInClip := Clip.Contains(Bounds);
  end;

  // TODO: SkScanClipper

  FillPathImpl(Path, FillRule, Clip, Ir.Y, Ir.Bottom, 0, PathContainedInClip, Blitter);
end;

// Conservative rounding function, which effectively nudges the int-rect to be slightly larger than Rect::round() might have produced. This
// is a safety-net for the scan-converter, which inspects the returned int-rect, and may disable clipping (for speed) if it thinks all of
// the edges will fit inside the clip's bounds. The scan-converter introduces slight numeric errors due to accumulated += of the slope, so
// this function is used to return a conservatively large int-bounds, and thus we will only disable clipping if we're sure the edges will
// stay in-bounds.
class function TTsScan.TryConservativeRoundToInt(const Src: TTsRect; out Rounded: TTsIntRect): Boolean;
begin
  // We must use `from_ltrb`, otherwise rounding will be incorrect.
  Result := TTsIntRect.TryFromLTRB(RoundDownToInt(Src.Left), RoundDownToInt(Src.Top), RoundUpToInt(Src.Right), RoundUpToInt(Src.Bottom),
                                   Rounded);
end;

// Round the value down. This is used to round the top and left of a rectangle, and corresponds to the way the scan converter treats the
// top and left edges. It has a slight bias to make the "rounded" int smaller than a normal round, to create a more conservative int-bounds
// (larger) from a float rect.
class function TTsScan.RoundDownToInt(const X: Single): Integer;
begin
  var Xx: Double := X;
  Xx := Xx - ConservativeRoundBias;

  // The saturating cast of the ceiling; the clamp keeps the ceiling inside the range of an Integer
  if not (Xx < High(Integer)) then
  begin
    Exit(High(Integer));
  end;

  if not (Xx > Low(Integer)) then
  begin
    Exit(Low(Integer));
  end;

  Result := Ceil(Xx);
end;

// Round the value up. This is used to round the right and bottom of a rectangle.
class function TTsScan.RoundUpToInt(const X: Single): Integer;
begin
  var Xx: Double := X;
  Xx := Xx + ConservativeRoundBias;

  if not (Xx < High(Integer)) then
  begin
    Exit(High(Integer));
  end;

  if not (Xx > Low(Integer)) then
  begin
    Exit(Low(Integer));
  end;

  Result := Floor(Xx);
end;

class procedure TTsScan.FillPathImpl(const Path: TTsPath; const FillRule: TTsFillRule; const ClipRect: TTsScreenIntRect;
                                     const StartY, StopY, ShiftEdgesUp: Integer; const PathContainedInClip: Boolean;
                                     const Blitter: TTsBlitter);
begin
  var ShiftedClip: TTsShiftedIntRect;
  if not TTsShiftedIntRect.TryCreate(ClipRect, ShiftEdgesUp, ShiftedClip) then
  begin
    Exit;
  end;

  var Edges: TArray<TTsEdge>;
  var IsBuilt: Boolean;
  if PathContainedInClip then
  begin
    IsBuilt := TTsBasicEdgeBuilder.TryBuildEdgesUnclipped(Path, ShiftEdgesUp, Edges);
  end
  else
  begin
    IsBuilt := TTsBasicEdgeBuilder.TryBuildEdges(Path, ShiftedClip, ShiftEdgesUp, Edges);
  end;

  if not IsBuilt then
  begin
    // no edges to render, just return
    Exit;
  end;

  var ShiftedStartY := TTsScalar.LeftShift(StartY, ShiftEdgesUp);
  var ShiftedStopY := TTsScalar.LeftShift(StopY, ShiftEdgesUp);

  const Top = Integer(ShiftedClip.Shifted.Y);
  if (not PathContainedInClip) and (ShiftedStartY < Top) then
  begin
    ShiftedStartY := Top;
  end;

  const Bottom = Integer(ShiftedClip.Shifted.Bottom);
  if (not PathContainedInClip) and (ShiftedStopY > Bottom) then
  begin
    ShiftedStopY := Bottom;
  end;

  if (ShiftedStartY < 0) or (ShiftedStopY < 0) then
  begin
    Exit;
  end;

  // No rows to draw: Rust walks one row anyway, in which no clipped edge is active; the start row is only not before the stop row here
  // after the row shift has wrapped (|y| of about 5.4e8 and more)
  if ShiftedStartY >= ShiftedStopY then
  begin
    Exit;
  end;

  // The bound of the work is taken before anything is drawn: a path over the limit changes no pixel
  if EdgeWorkBound(Edges, ShiftedStartY, ShiftedStopY) > EdgeWorkLimit then
  begin
    raise EPdfLimitExceededException.Create('The edges of the path take more work than the limit of the scan converter');
  end;

  if GEdgeWorkDryRun then
  begin
    Exit;
  end;

  SortEdges(Edges);

  const EdgeCount = Length(Edges);
  var Linked: TArray<TTsEdge>;
  SetLength(Linked, EdgeCount + 2);

  // The head sentinel; the other fields are the defaults of LineEdge
  Linked[0] := Default(TTsEdge);
  Linked[0].Kind := TTsEdgeKind.Line;
  Linked[0].Line.Prev := TTsLineEdge.NoLink;
  Linked[0].Line.Next := 1;
  Linked[0].Line.X := Low(Integer);
  Linked[0].Line.FirstY := Low(Integer);

  for var Index := 0 to EdgeCount - 1 do
  begin
    Linked[Index + 1] := Edges[Index];
    Linked[Index + 1].Line.Prev := Index;
    Linked[Index + 1].Line.Next := Index + 2;
  end;

  Linked[EdgeCount + 1] := Default(TTsEdge);
  Linked[EdgeCount + 1].Kind := TTsEdgeKind.Line;
  Linked[EdgeCount + 1].Line.Prev := EdgeCount;
  Linked[EdgeCount + 1].Line.Next := TTsLineEdge.NoLink;
  Linked[EdgeCount + 1].Line.FirstY := High(Integer);

  // TODO: walk_simple_edges

  if not WalkEdges(FillRule, Cardinal(ShiftedStartY), Cardinal(ShiftedStopY), ShiftedClip.Shifted.Right, Linked, Blitter) then
  begin
    raise EPdfLimitExceededException.Create('The edges of the path take more work than the limit of the scan converter');
  end;
end;

// An upper bound of the work that WalkEdges counts for the rows StartY..StopY - 1, from the rows that each edge spans in them: a row costs
// 3 per edge, the ripple of the row stops after 4 steps per edge and 1024 (plus one last ripple of at most one step per edge) and the sort
// at the end of the row 8 per edge, 16 per edge in all, and 1024 for the row. The bound holds for the Auto mode of the sort.
class function TTsScan.EdgeWorkBound(const Edges: TArray<TTsEdge>; const StartY, StopY: Integer): Int64;
begin
  var Spans: Int64 := 0;
  for var Index := 0 to High(Edges) do
  begin
    var LastRow: Int64 := Edges[Index].Line.LastY;
    case Edges[Index].Kind of
      TTsEdgeKind.Quadratic:
        LastRow := Max(LastRow, Int64(Edges[Index].Quadratic.EndRow));
      TTsEdgeKind.Cubic:
        LastRow := Max(LastRow, Int64(Edges[Index].Cubic.EndRow));
    end;

    const First = Max(Int64(Edges[Index].Line.FirstY), Int64(StartY));
    const Last = Min(LastRow, Int64(StopY) - 1);
    if Last >= First then
    begin
      Inc(Spans, Last - First + 1);
    end;
  end;

  Result := 16 * Spans + 1024 * (Int64(StopY) - StartY);
end;

// The stable sort of Rust on (first_y, x): a merge sort of the indices with the two values as one key
// The stable merge sort of the first Count items on Key; the sorted items are in Items afterwards (Scratch is the second buffer)
class procedure TTsScan.MergeSort(var Items, Scratch: TArray<TSortItem>; const Count: Integer);
begin
  var RunWidth := 1;
  while RunWidth < Count do
  begin
    var RunStart := 0;
    while RunStart < Count do
    begin
      const Middle = Min(RunStart + RunWidth, Count);
      const RunEnd = Min(RunStart + 2 * RunWidth, Count);

      var LeftIndex := RunStart;
      var RightIndex := Middle;
      var Target := RunStart;
      while (LeftIndex < Middle) and (RightIndex < RunEnd) do
      begin
        if Items[RightIndex].Key < Items[LeftIndex].Key then
        begin
          Scratch[Target] := Items[RightIndex];
          Inc(RightIndex);
        end
        else
        begin
          Scratch[Target] := Items[LeftIndex];
          Inc(LeftIndex);
        end;

        Inc(Target);
      end;

      while LeftIndex < Middle do
      begin
        Scratch[Target] := Items[LeftIndex];
        Inc(LeftIndex);
        Inc(Target);
      end;

      while RightIndex < RunEnd do
      begin
        Scratch[Target] := Items[RightIndex];
        Inc(RightIndex);
        Inc(Target);
      end;

      RunStart := RunEnd;
    end;

    const Swapped = Items;
    Items := Scratch;
    Scratch := Swapped;
    RunWidth := RunWidth * 2;
  end;
end;

class procedure TTsScan.SortEdges(var Edges: TArray<TTsEdge>);
begin
  const Count = Length(Edges);
  if Count < 2 then
  begin
    Exit;
  end;

  var Items: TArray<TSortItem>;
  SetLength(Items, Count);
  for var Index := 0 to Count - 1 do
  begin
    Items[Index].Key := Int64(Edges[Index].Line.FirstY) * 4294967296 + (Int64(Edges[Index].Line.X) + 2147483648);
    Items[Index].Index := Index;
  end;

  var Scratch: TArray<TSortItem>;
  SetLength(Scratch, Count);
  MergeSort(Items, Scratch, Count);

  var Sorted: TArray<TTsEdge>;
  SetLength(Sorted, Count);
  for var Index := 0 to Count - 1 do
  begin
    Sorted[Index] := Edges[Items[Index].Index];
  end;

  Edges := Sorted;
end;

// Sorts the active edges (the list from the head to FirstInactiveIdx) on x with the stable merge sort and links them again: the list that
// the ripple of every edge back to its place makes
class procedure TTsScan.SortActiveEdges(const FirstInactiveIdx: Integer; var Edges: TArray<TTsEdge>; var Items, Scratch: TArray<TSortItem>);
begin
  var Count := 0;
  var Idx := Edges[0].Line.Next;
  while Idx <> FirstInactiveIdx do
  begin
    if Count = Length(Items) then
    begin
      SetLength(Items, Max(2 * Count, 1024));
      SetLength(Scratch, Length(Items));
    end;

    Items[Count].Key := Edges[Idx].Line.X;
    Items[Count].Index := Idx;
    Inc(Count);
    Idx := Edges[Idx].Line.Next;
  end;

  MergeSort(Items, Scratch, Count);

  var PrevIdx := 0;
  for var Index := 0 to Count - 1 do
  begin
    const CurrIdx = Items[Index].Index;
    Edges[PrevIdx].Line.Next := CurrIdx;
    Edges[CurrIdx].Line.Prev := PrevIdx;
    PrevIdx := CurrIdx;
  end;

  Edges[PrevIdx].Line.Next := FirstInactiveIdx;
  Edges[FirstInactiveIdx].Line.Prev := PrevIdx;
end;

// TODO: simplify!
// Returns False when the work of the walk went over the limit; the walk has stopped then. With the bound taken before the walk that is
// a guard only.
class function TTsScan.WalkEdges(const FillRule: TTsFillRule; const StartY, StopY, RightClip: Cardinal; var Edges: TArray<TTsEdge>;
                                 const Blitter: TTsBlitter): Boolean;
begin
  Result := True;
  var Work: Int64 := 0;
  const Limit = EdgeWorkLimit;
  var SortItems: TArray<TSortItem> := nil;
  var SortScratch: TArray<TSortItem> := nil;
  var CurrY := StartY;
  var WindingMask := -1;
  if FillRule = TTsFillRule.EvenOdd then
  begin
    WindingMask := 1;
  end;

  while True do
  begin
    var W := 0;
    var Left: Cardinal := 0;
    var PrevX := Edges[0].Line.X;
    var Visited := 0;
    var Rippled := 0;
    var IsDeferred := False;

    var CurrIdx := Edges[0].Line.Next;
    while Edges[CurrIdx].Line.FirstY <= Integer(CurrY) do
    begin
      Inc(Visited);
      const X = Cardinal(TTsFdot16.RoundToI32(Edges[CurrIdx].Line.X)); // TODO: check

      if (W and WindingMask) = 0 then
      begin
        // we're starting interval
        Left := X;
      end;

      W := W + Edges[CurrIdx].Line.Winding;

      if (W and WindingMask) = 0 then
      begin
        // we finished an interval; the width is X - Left, an empty or negative one draws nothing
        if X > Left then
        begin
          Blitter.BlitH(Left, CurrY, X - Left);
        end;
      end;

      const NextIdx = Edges[CurrIdx].Line.Next;
      var NewX: Integer;

      if Edges[CurrIdx].Line.LastY = Integer(CurrY) then
      begin
        // are we done with this edge?
        case Edges[CurrIdx].Kind of
          TTsEdgeKind.Line:
            RemoveEdge(CurrIdx, Edges);

          TTsEdgeKind.Quadratic:
            if (Edges[CurrIdx].Quadratic.CurveCount > 0) and Edges[CurrIdx].Quadratic.Update then
            begin
              NewX := Edges[CurrIdx].Quadratic.Line.X;

              if NewX < PrevX then
              begin
                // ripple current edge backwards until it is x-sorted
                Reposition(CurrIdx, Visited, Edges, Rippled, IsDeferred);
              end
              else
              begin
                PrevX := NewX;
              end;
            end
            else
            begin
              RemoveEdge(CurrIdx, Edges);
            end;

          TTsEdgeKind.Cubic:
            if (Edges[CurrIdx].Cubic.CurveCount < 0) and Edges[CurrIdx].Cubic.Update then
            begin
              NewX := Edges[CurrIdx].Cubic.Line.X;

              if NewX < PrevX then
              begin
                // ripple current edge backwards until it is x-sorted
                Reposition(CurrIdx, Visited, Edges, Rippled, IsDeferred);
              end
              else
              begin
                PrevX := NewX;
              end;
            end
            else
            begin
              RemoveEdge(CurrIdx, Edges);
            end;
        end;
      end
      else
      begin
        NewX := Edges[CurrIdx].Line.X + Edges[CurrIdx].Line.Dx;
        Edges[CurrIdx].Line.X := NewX;

        if NewX < PrevX then
        begin
          // ripple current edge backwards until it is x-sorted
          Reposition(CurrIdx, Visited, Edges, Rippled, IsDeferred);
        end
        else
        begin
          PrevX := NewX;
        end;
      end;

      CurrIdx := NextIdx;
    end;

    if (W and WindingMask) <> 0 then
    begin
      // was our right-edge culled away?
      if RightClip > Left then
      begin
        Blitter.BlitH(Left, CurrY, RightClip - Left);
      end;
    end;

    Inc(Work, 3 * Int64(Visited) + Rippled);
    if IsDeferred then
    begin
{$IFDEF PDF4D_TESTS}
      Inc(DeferredRowCount);
{$ENDIF}
      SortActiveEdges(CurrIdx, Edges, SortItems, SortScratch);
      Inc(Work, 8 * Int64(Visited));
    end;

    if Work > Limit then
    begin
      Exit(False);
    end;

    Inc(CurrY);
    if CurrY >= StopY then
    begin
      Break;
    end;

    // now current edge points to the first edge with a Yint larger than curr_y
    InsertNewEdges(CurrIdx, Integer(CurrY), Edges);
  end;
end;

class procedure TTsScan.RemoveEdge(const CurrIdx: Integer; var Edges: TArray<TTsEdge>);
begin
  const Prev = Edges[CurrIdx].Line.Prev;
  const Next = Edges[CurrIdx].Line.Next;

  Edges[Prev].Line.Next := Next;
  Edges[Next].Line.Prev := Prev;
end;

// Returns the number of edges that it passed
class function TTsScan.BackwardInsertEdgeBasedOnX(const CurrIdx: Integer; var Edges: TArray<TTsEdge>): Integer;
begin
  Result := 0;
  const X = Edges[CurrIdx].Line.X;
  var PrevIdx := Edges[CurrIdx].Line.Prev;
  while PrevIdx <> 0 do
  begin
    if Edges[PrevIdx].Line.X > X then
    begin
      PrevIdx := Edges[PrevIdx].Line.Prev;
      Inc(Result);
    end
    else
    begin
      Break;
    end;
  end;

  const NextIdx = Edges[PrevIdx].Line.Next;
  if NextIdx <> CurrIdx then
  begin
    RemoveEdge(CurrIdx, Edges);
    InsertEdgeAfter(CurrIdx, PrevIdx, Edges);
  end;
end;

// Ripples the edge back to its place unless the row is deferred. When the edges of the row have passed more than 4 edges each and a
// little more, the row is deferred: the rest of it only updates the edges, and the list is sorted at the end of the row.
class procedure TTsScan.Reposition(const CurrIdx, Visited: Integer; var Edges: TArray<TTsEdge>; var Rippled: Integer; var IsDeferred: Boolean);
begin
  if IsDeferred then
  begin
    Exit;
  end;

{$IFDEF PDF4D_TESTS}
  if DeferMode = TDeferMode.Always then
  begin
    IsDeferred := True;
    Exit;
  end;
{$ENDIF}

  Inc(Rippled, BackwardInsertEdgeBasedOnX(CurrIdx, Edges));
{$IFDEF PDF4D_TESTS}
  if DeferMode = TDeferMode.Never then
  begin
    Exit;
  end;
{$ENDIF}
  if Int64(Rippled) > 4 * Int64(Visited) + 1024 then
  begin
    IsDeferred := True;
{$IFDEF PDF4D_TESTS}
    Inc(AutoSwitchCount);
{$ENDIF}
  end;
end;

class procedure TTsScan.InsertEdgeAfter(const CurrIdx, AfterIdx: Integer; var Edges: TArray<TTsEdge>);
begin
  Edges[CurrIdx].Line.Prev := AfterIdx;
  Edges[CurrIdx].Line.Next := Edges[AfterIdx].Line.Next;

  const AfterNextIdx = Edges[AfterIdx].Line.Next;
  Edges[AfterNextIdx].Line.Prev := CurrIdx;
  Edges[AfterIdx].Line.Next := CurrIdx;
end;

// Start from the right side, searching backwards for the point to begin the new edge list insertion, marching forwards from here. The
// implementation could have started from the left of the prior insertion, and search to the right, or with some additional caching, binary
// search the starting point. More work could be done to determine optimal new edge insertion.
class function TTsScan.BackwardInsertStart(const PrevIdx, X: Integer; var Edges: TArray<TTsEdge>): Integer;
begin
  Result := PrevIdx;
  while Edges[Result].Line.Prev <> TTsLineEdge.NoLink do
  begin
    Result := Edges[Result].Line.Prev;
    if Edges[Result].Line.X <= X then
    begin
      Break;
    end;
  end;
end;

class procedure TTsScan.InsertNewEdges(const NewIdx, CurrY: Integer; var Edges: TArray<TTsEdge>);
begin
  var NewEdgeIdx := NewIdx;
  if Edges[NewEdgeIdx].Line.FirstY <> CurrY then
  begin
    Exit;
  end;

  const PrevIdx = Edges[NewEdgeIdx].Line.Prev;
  if Edges[PrevIdx].Line.X <= Edges[NewEdgeIdx].Line.X then
  begin
    Exit;
  end;

  // find first x pos to insert
  var StartIdx := BackwardInsertStart(PrevIdx, Edges[NewEdgeIdx].Line.X, Edges);

  // insert the lot, fixing up the links as we go
  while True do
  begin
    const NextIdx = Edges[NewEdgeIdx].Line.Next;
    var KeepEdge := False;
    while True do
    begin
      const AfterIdx = Edges[StartIdx].Line.Next;
      if AfterIdx = NewEdgeIdx then
      begin
        KeepEdge := True;
        Break;
      end;

      if Edges[AfterIdx].Line.X >= Edges[NewEdgeIdx].Line.X then
      begin
        Break;
      end;

      StartIdx := AfterIdx;
    end;

    if not KeepEdge then
    begin
      RemoveEdge(NewEdgeIdx, Edges);
      InsertEdgeAfter(NewEdgeIdx, StartIdx, Edges);
    end;

    StartIdx := NewEdgeIdx;
    NewEdgeIdx := NextIdx;

    if Edges[NewEdgeIdx].Line.FirstY <> CurrY then
    begin
      Break;
    end;
  end;
end;

end.
