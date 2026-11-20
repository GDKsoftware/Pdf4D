// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/shading/PatchMeshesShadingContext.java, Type6ShadingContext.java,
// Type7ShadingContext.java, PDMeshBasedShadingType.java, Patch.java, CoonsPatch.java and TensorPatch.java (3.0.8)
unit Pdf4D.Render.Shading.Patch;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  Pdf4D.Common.Matrix,
  Pdf4D.Graphics.Shading,
  Pdf4D.Render.Renderer.Interfaces,
  Pdf4D.Render.Shading.Triangle;

const
  // A patch is cut into at most this many parts in each direction. PDFBox cuts a patch into 2 ^ level parts with a level of 4 at most,
  // so this limit only guards against a change of that.
  MaxPatchDivisions = 64;

type
  TPdfPatchPoint = record
    X: Double;
    Y: Double;

    class function Create(const X, Y: Double): TPdfPatchPoint; static;
  end;

  // The four points of one side of a patch
  TPdfPatchEdge = array[0..3] of TPdfPatchPoint;
  // The colour values at the four corners: the corners of the control points (0, 0), (0, 3), (3, 3) and (3, 0)
  TPdfPatchColors = array[0..3] of TArray<Single>;

  // Patch: a bicubic surface over a grid of 4 x 4 control points, with a colour at every corner. The surface is cut into a grid of cells
  // whose corners are evaluated, and each cell becomes two triangles.
  TPdfPatch = class abstract
  private
    FControlPoints: array[0..3, 0..3] of TPdfPatchPoint;
    FCornerColors: TPdfPatchColors;

    class function EdgeEquationValue(const Point, First, Second: TPdfPatchPoint): Double; static;
    class function IsEdgeALine(const Edge: TPdfPatchEdge): Boolean; static;
    class function Distance(const First, Second: TPdfPatchPoint): Double; static;
    // 2 ^ level parts: a straight side gets fewer parts the shorter it is, any other side the most, and so does a pair of sides with an
    // inner control point that lies outside of them (KeepsHighLevel)
    class function DivisionsOf(const FirstSide, SecondSide: TPdfPatchEdge; const KeepsHighLevel: Boolean): Integer; static;
    class function Bernstein(const Index: Integer; const T: Double): Double; static;
    function ColumnEdge(const Column: Integer): TPdfPatchEdge;
    function RowEdge(const Row: Integer): TPdfPatchEdge;
    function SurfacePoint(const U, V: Double): TPdfPatchPoint;
    function CornerColorAt(const U, V: Double): TArray<Single>;
    function GridVertex(const U, V: Double): TPdfMeshVertex;
    class function Overlaps(const First, Second: TPdfMeshVertex): Boolean; static;

  protected
    constructor Initialize(const CornerColors: TPdfPatchColors);

    procedure SetControlPoint(const Row, Column: Integer; const Point: TPdfPatchPoint);
    function ControlPoint(const Row, Column: Integer): TPdfPatchPoint;
    // Whether an inner control point keeps the highest level of the divisions in the direction of the columns and of the rows (a Coons
    // patch has none of its own: its inner points follow from the sides)
    function KeepsHighLevelAlongColumns: Boolean; virtual;
    function KeepsHighLevelAlongRows: Boolean; virtual;

  public
    // The side of the patch that a following patch with the edge flag 1, 2 or 3 starts on (CoonsPatch.getFlag1Edge and so on)
    function Flag1Edge: TPdfPatchEdge;
    function Flag2Edge: TPdfPatchEdge;
    function Flag3Edge: TPdfPatchEdge;
    function CornerColor(const Index: Integer): TArray<Single>;
    function Triangles: TArray<TPdfShadedTriangle>;
  end;

  // Type 6: the 12 points of the four curves around the patch; the 4 inner control points follow from them
  TPdfCoonsPatch = class(TPdfPatch)
  public
    // Points are the 12 points in the order of the data
    constructor Create(const Points: TArray<TPdfPatchPoint>; const CornerColors: TPdfPatchColors);
  end;

  // Type 7: the 12 points around the patch and then the 4 inner control points
  TPdfTensorPatch = class(TPdfPatch)
  private
    // isOnSameSideCC and isOnSameSideDD: a point on the same side of both opposite sides is outside of the patch
    function IsOnSameSideOfColumns(const Point: TPdfPatchPoint): Boolean;
    function IsOnSameSideOfRows(const Point: TPdfPatchPoint): Boolean;

  protected
    function KeepsHighLevelAlongColumns: Boolean; override;
    function KeepsHighLevelAlongRows: Boolean; override;

  public
    // Points are the 16 points in the order of the data
    constructor Create(const Points: TArray<TPdfPatchPoint>; const CornerColors: TPdfPatchColors);
  end;

  // PatchMeshesShadingContext: reads the patches, one after the other, and paints their triangles
  TPdfPatchMeshesShadingContext = class abstract(TPdfGouraudShadingContext)
  private
    FPointCount: Integer;
    FReader: TPdfMeshReader;
    FPrevious: TPdfPatch;

    procedure ReadPatches;
    function TryReadPatch(const Flag: Integer; out Patch: TPdfPatch): Boolean;
    function TryReadPoints(const FirstIndex: Integer; const Points: TArray<TPdfPatchPoint>): Boolean;
    function TryReadColors(const FirstIndex: Integer; var Colors: TPdfPatchColors): Boolean;
    procedure UseImplicitEdge(const Flag: Integer; var Points: TArray<TPdfPatchPoint>; var Colors: TPdfPatchColors);
    function TryDrawPatch(const Patch: TPdfPatch): Boolean;

  protected
    function MakePatch(const Points: TArray<TPdfPatchPoint>; const Colors: TPdfPatchColors): TPdfPatch; virtual; abstract;

  public
    // PointCount is 12 for the type 6 and 16 for the type 7
    constructor Create(const Shading: TPDShadingMesh; const ShadingToDevice: TPdfMatrix; const DeviceArea: TRect; const Cancel: IPdfCancelToken;
                       const PointCount: Integer);
  end;

  TPdfType6ShadingContext = class(TPdfPatchMeshesShadingContext)
  protected
    function MakePatch(const Points: TArray<TPdfPatchPoint>; const Colors: TPdfPatchColors): TPdfPatch; override;

  public
    constructor Create(const Shading: TPDShadingMesh; const ShadingToDevice: TPdfMatrix; const DeviceArea: TRect; const Cancel: IPdfCancelToken);
  end;

  TPdfType7ShadingContext = class(TPdfPatchMeshesShadingContext)
  protected
    function MakePatch(const Points: TArray<TPdfPatchPoint>; const Colors: TPdfPatchColors): TPdfPatch; override;

  public
    constructor Create(const Shading: TPDShadingMesh; const ShadingToDevice: TPdfMatrix; const DeviceArea: TRect; const Cancel: IPdfCancelToken);
  end;

implementation

uses
  System.SysUtils,
  System.Math;

const
  CoonsPointCount = 12;
  TensorPointCount = 16;
  EdgePointCount = 4;
  CornerCount = 4;
  ImplicitColorCount = 2;
  EdgeFlagFree = 0;
  EdgeFlagFirstSide = 1;
  EdgeFlagSecondSide = 2;
  EdgeFlagThirdSide = 3;
  LongSide = 800;
  MediumSide = 400;
  ShortSide = 200;
  MaxLevel = 4;
  // Points closer than this are one point
  OverlapDistance = 0.001;

{ TPdfPatchPoint }

class function TPdfPatchPoint.Create(const X, Y: Double): TPdfPatchPoint;
begin
  Result.X := X;
  Result.Y := Y;
end;

{ TPdfPatch }

constructor TPdfPatch.Initialize(const CornerColors: TPdfPatchColors);
begin
  inherited Create;
  FCornerColors := CornerColors;
end;

procedure TPdfPatch.SetControlPoint(const Row, Column: Integer; const Point: TPdfPatchPoint);
begin
  FControlPoints[Row, Column] := Point;
end;

function TPdfPatch.ControlPoint(const Row, Column: Integer): TPdfPatchPoint;
begin
  Result := FControlPoints[Row, Column];
end;

function TPdfPatch.CornerColor(const Index: Integer): TArray<Single>;
begin
  Result := FCornerColors[Index];
end;

function TPdfPatch.Flag1Edge: TPdfPatchEdge;
begin
  for var Row := 0 to 3 do
  begin
    Result[Row] := FControlPoints[Row, 3];
  end;
end;

function TPdfPatch.Flag2Edge: TPdfPatchEdge;
begin
  for var Column := 0 to 3 do
  begin
    Result[Column] := FControlPoints[3, 3 - Column];
  end;
end;

function TPdfPatch.Flag3Edge: TPdfPatchEdge;
begin
  for var Row := 0 to 3 do
  begin
    Result[Row] := FControlPoints[3 - Row, 0];
  end;
end;

function TPdfPatch.KeepsHighLevelAlongColumns: Boolean;
begin
  Result := False;
end;

function TPdfPatch.KeepsHighLevelAlongRows: Boolean;
begin
  Result := False;
end;

function TPdfPatch.ColumnEdge(const Column: Integer): TPdfPatchEdge;
begin
  for var Row := 0 to 3 do
  begin
    Result[Row] := FControlPoints[Row, Column];
  end;
end;

function TPdfPatch.RowEdge(const Row: Integer): TPdfPatchEdge;
begin
  for var Column := 0 to 3 do
  begin
    Result[Column] := FControlPoints[Row, Column];
  end;
end;

class function TPdfPatch.EdgeEquationValue(const Point, First, Second: TPdfPatchPoint): Double;
begin
  Result := (Second.Y - First.Y) * (Point.X - First.X) - (Second.X - First.X) * (Point.Y - First.Y);
end;

class function TPdfPatch.IsEdgeALine(const Edge: TPdfPatchEdge): Boolean;
begin
  const FirstValue = Abs(EdgeEquationValue(Edge[1], Edge[0], Edge[3]));
  const SecondValue = Abs(EdgeEquationValue(Edge[2], Edge[0], Edge[3]));
  const SpanX = Abs(Edge[0].X - Edge[3].X);
  const SpanY = Abs(Edge[0].Y - Edge[3].Y);
  Result := (((FirstValue <= SpanX) and (SecondValue <= SpanX)) or ((FirstValue <= SpanY) and (SecondValue <= SpanY)));
end;

class function TPdfPatch.Distance(const First, Second: TPdfPatchPoint): Double;
begin
  Result := Sqrt(Sqr(First.X - Second.X) + Sqr(First.Y - Second.Y));
end;

class function TPdfPatch.DivisionsOf(const FirstSide, SecondSide: TPdfPatchEdge; const KeepsHighLevel: Boolean): Integer;
begin
  var Level := MaxLevel;
  if IsEdgeALine(FirstSide) and IsEdgeALine(SecondSide) and (not KeepsHighLevel) then
  begin
    const FirstLength = Distance(FirstSide[0], FirstSide[3]);
    const SecondLength = Distance(SecondSide[0], SecondSide[3]);
    if (FirstLength > LongSide) or (SecondLength > LongSide) then
    begin
      Level := 4;
    end
    else if (FirstLength > MediumSide) or (SecondLength > MediumSide) then
    begin
      Level := 3;
    end
    else if (FirstLength > ShortSide) or (SecondLength > ShortSide) then
    begin
      Level := 2;
    end
    else
    begin
      Level := 1;
    end;
  end;

  Result := Min(1 shl Level, MaxPatchDivisions);
end;

class function TPdfPatch.Bernstein(const Index: Integer; const T: Double): Double;
begin
  const Rest = 1 - T;
  case Index of
    0 : Result := Rest * Rest * Rest;
    1 : Result := 3 * T * Rest * Rest;
    2 : Result := 3 * T * T * Rest;
    3 : Result := T * T * T;
  else
    raise EArgumentOutOfRangeException.CreateFmt('A Bernstein polynomial of a cubic has the index 0 to 3, not %d', [Index]);
  end;
end;

function TPdfPatch.SurfacePoint(const U, V: Double): TPdfPatchPoint;
begin
  var X := 0.0;
  var Y := 0.0;
  for var Row := 0 to 3 do
  begin
    for var Column := 0 to 3 do
    begin
      const Weight = Bernstein(Row, U) * Bernstein(Column, V);
      X := X + FControlPoints[Row, Column].X * Weight;
      Y := Y + FControlPoints[Row, Column].Y * Weight;
    end;
  end;
  Result := TPdfPatchPoint.Create(X, Y);
end;

// The colours of the corners (0, 0), (0, 3), (3, 3) and (3, 0) of the control points, mixed bilinearly
function TPdfPatch.CornerColorAt(const U, V: Double): TArray<Single>;
begin
  SetLength(Result, Length(FCornerColors[0]));
  for var Index := 0 to High(Result) do
  begin
    Result[Index] := (FCornerColors[0][Index] * (1 - U) * (1 - V) +
                      FCornerColors[1][Index] * (1 - U) * V +
                      FCornerColors[2][Index] * U * V +
                      FCornerColors[3][Index] * U * (1 - V));
  end;
end;

function TPdfPatch.GridVertex(const U, V: Double): TPdfMeshVertex;
begin
  const Point = SurfacePoint(U, V);
  Result := TPdfMeshVertex.Create(Point.X, Point.Y, CornerColorAt(U, V));
end;

class function TPdfPatch.Overlaps(const First, Second: TPdfMeshVertex): Boolean;
begin
  Result := ((Abs(First.X - Second.X) < OverlapDistance) and (Abs(First.Y - Second.Y) < OverlapDistance));
end;

// Patch.getShadedTriangles: a cell with two corners on one point gives only the triangle that still has an area
function TPdfPatch.Triangles: TArray<TPdfShadedTriangle>;
begin
  const UDivisions = DivisionsOf(ColumnEdge(0), ColumnEdge(3), KeepsHighLevelAlongColumns);
  const VDivisions = DivisionsOf(RowEdge(0), RowEdge(3), KeepsHighLevelAlongRows);
  var Grid: TArray<TPdfMeshVertex>;
  const Stride = VDivisions + 1;
  SetLength(Grid, (UDivisions + 1) * Stride);
  for var Row := 0 to UDivisions do
  begin
    for var Column := 0 to VDivisions do
    begin
      Grid[Row * Stride + Column] := GridVertex(Row / UDivisions, Column / VDivisions);
    end;
  end;

  SetLength(Result, UDivisions * VDivisions * 2);
  var Count := 0;
  for var Row := 0 to UDivisions - 1 do
  begin
    for var Column := 0 to VDivisions - 1 do
    begin
      // The corners of getShadedTriangles: p0 and p2 are opposite, p1 is the next one in the direction of the rows (u) and p3 in the
      // direction of the columns (v)
      const P0 = Grid[Row * Stride + Column];
      const P1 = Grid[(Row + 1) * Stride + Column];
      const P2 = Grid[(Row + 1) * Stride + Column + 1];
      const P3 = Grid[Row * Stride + Column + 1];
      const HasLowerTriangle = (not (Overlaps(P0, P1) or Overlaps(P0, P3)));
      const HasUpperTriangle = (not (HasLowerTriangle and (Overlaps(P2, P1) or Overlaps(P2, P3))));
      if HasLowerTriangle then
      begin
        Result[Count] := TPdfShadedTriangle.Create(P0, P1, P3);
        Inc(Count);
      end;
      if HasUpperTriangle then
      begin
        Result[Count] := TPdfShadedTriangle.Create(P3, P1, P2);
        Inc(Count);
      end;
    end;
  end;
  SetLength(Result, Count);
end;

{ TPdfCoonsPatch }

// The inner control points that make the bicubic surface equal to the Coons surface of the four curves
constructor TPdfCoonsPatch.Create(const Points: TArray<TPdfPatchPoint>; const CornerColors: TPdfPatchColors);
begin
  inherited Initialize(CornerColors);
  SetControlPoint(0, 0, Points[0]);
  SetControlPoint(0, 1, Points[1]);
  SetControlPoint(0, 2, Points[2]);
  SetControlPoint(0, 3, Points[3]);
  SetControlPoint(1, 3, Points[4]);
  SetControlPoint(2, 3, Points[5]);
  SetControlPoint(3, 3, Points[6]);
  SetControlPoint(3, 2, Points[7]);
  SetControlPoint(3, 1, Points[8]);
  SetControlPoint(3, 0, Points[9]);
  SetControlPoint(2, 0, Points[10]);
  SetControlPoint(1, 0, Points[11]);

  const P00 = ControlPoint(0, 0);
  const P01 = ControlPoint(0, 1);
  const P02 = ControlPoint(0, 2);
  const P03 = ControlPoint(0, 3);
  const P10 = ControlPoint(1, 0);
  const P13 = ControlPoint(1, 3);
  const P20 = ControlPoint(2, 0);
  const P23 = ControlPoint(2, 3);
  const P30 = ControlPoint(3, 0);
  const P31 = ControlPoint(3, 1);
  const P32 = ControlPoint(3, 2);
  const P33 = ControlPoint(3, 3);
  SetControlPoint(1, 1, TPdfPatchPoint.Create(
    (-4 * P00.X + 6 * (P01.X + P10.X) - 2 * (P03.X + P30.X) + 3 * (P31.X + P13.X) - P33.X) / 9,
    (-4 * P00.Y + 6 * (P01.Y + P10.Y) - 2 * (P03.Y + P30.Y) + 3 * (P31.Y + P13.Y) - P33.Y) / 9));
  SetControlPoint(1, 2, TPdfPatchPoint.Create(
    (-4 * P03.X + 6 * (P02.X + P13.X) - 2 * (P00.X + P33.X) + 3 * (P32.X + P10.X) - P30.X) / 9,
    (-4 * P03.Y + 6 * (P02.Y + P13.Y) - 2 * (P00.Y + P33.Y) + 3 * (P32.Y + P10.Y) - P30.Y) / 9));
  SetControlPoint(2, 1, TPdfPatchPoint.Create(
    (-4 * P30.X + 6 * (P31.X + P20.X) - 2 * (P33.X + P00.X) + 3 * (P01.X + P23.X) - P03.X) / 9,
    (-4 * P30.Y + 6 * (P31.Y + P20.Y) - 2 * (P33.Y + P00.Y) + 3 * (P01.Y + P23.Y) - P03.Y) / 9));
  SetControlPoint(2, 2, TPdfPatchPoint.Create(
    (-4 * P33.X + 6 * (P32.X + P23.X) - 2 * (P30.X + P03.X) + 3 * (P02.X + P20.X) - P00.X) / 9,
    (-4 * P33.Y + 6 * (P32.Y + P23.Y) - 2 * (P30.Y + P03.Y) + 3 * (P02.Y + P20.Y) - P00.Y) / 9));
end;

{ TPdfTensorPatch }

function TPdfTensorPatch.IsOnSameSideOfColumns(const Point: TPdfPatchPoint): Boolean;
begin
  const FirstColumn = EdgeEquationValue(Point, ControlPoint(0, 0), ControlPoint(3, 0));
  const LastColumn = EdgeEquationValue(Point, ControlPoint(0, 3), ControlPoint(3, 3));
  Result := ((FirstColumn * LastColumn) > 0);
end;

function TPdfTensorPatch.IsOnSameSideOfRows(const Point: TPdfPatchPoint): Boolean;
begin
  const FirstRow = EdgeEquationValue(Point, ControlPoint(0, 0), ControlPoint(0, 3));
  const LastRow = EdgeEquationValue(Point, ControlPoint(3, 0), ControlPoint(3, 3));
  Result := ((FirstRow * LastRow) > 0);
end;

function TPdfTensorPatch.KeepsHighLevelAlongColumns: Boolean;
begin
  Result := (IsOnSameSideOfColumns(ControlPoint(1, 1)) or IsOnSameSideOfColumns(ControlPoint(1, 2)) or
             IsOnSameSideOfColumns(ControlPoint(2, 1)) or IsOnSameSideOfColumns(ControlPoint(2, 2)));
end;

function TPdfTensorPatch.KeepsHighLevelAlongRows: Boolean;
begin
  Result := (IsOnSameSideOfRows(ControlPoint(1, 1)) or IsOnSameSideOfRows(ControlPoint(1, 2)) or
             IsOnSameSideOfRows(ControlPoint(2, 1)) or IsOnSameSideOfRows(ControlPoint(2, 2)));
end;

constructor TPdfTensorPatch.Create(const Points: TArray<TPdfPatchPoint>; const CornerColors: TPdfPatchColors);
begin
  inherited Initialize(CornerColors);
  SetControlPoint(0, 0, Points[0]);
  SetControlPoint(0, 1, Points[1]);
  SetControlPoint(0, 2, Points[2]);
  SetControlPoint(0, 3, Points[3]);
  SetControlPoint(1, 3, Points[4]);
  SetControlPoint(2, 3, Points[5]);
  SetControlPoint(3, 3, Points[6]);
  SetControlPoint(3, 2, Points[7]);
  SetControlPoint(3, 1, Points[8]);
  SetControlPoint(3, 0, Points[9]);
  SetControlPoint(2, 0, Points[10]);
  SetControlPoint(1, 0, Points[11]);
  SetControlPoint(1, 1, Points[12]);
  SetControlPoint(1, 2, Points[13]);
  SetControlPoint(2, 2, Points[14]);
  SetControlPoint(2, 1, Points[15]);
end;

{ TPdfPatchMeshesShadingContext }

constructor TPdfPatchMeshesShadingContext.Create(const Shading: TPDShadingMesh; const ShadingToDevice: TPdfMatrix; const DeviceArea: TRect;
                                                 const Cancel: IPdfCancelToken; const PointCount: Integer);
begin
  inherited InitializeMesh(Shading, ShadingToDevice, DeviceArea, Cancel);
  FPointCount := PointCount;
  if TPdfMeshReader.TryOpen(Shading, ShadingToDevice, FReader) then
  begin
    try
      ReadPatches;
    finally
      FreeAndNil(FReader);
      FreeAndNil(FPrevious);
    end;
  end;
end;

// PDMeshBasedShadingType.collectPatches
procedure TPdfPatchMeshesShadingContext.ReadPatches;
begin
  while (not FReader.IsAtEnd) and (not IsStopped) do
  begin
    var Flag: Integer;
    if not FReader.TryReadFlag(Flag) then
    begin
      FReader.ReportTruncation('a patch');
      Exit;
    end;

    const IsContinuation = (Flag <> EdgeFlagFree);
    if IsContinuation and (not Assigned(FPrevious)) then
    begin
      Shading.Warn('The mesh shading continues a patch before it has one; the rest of the data is skipped', []);
      Exit;
    end;

    var Patch: TPdfPatch;
    if not TryReadPatch(Flag, Patch) then
    begin
      FReader.ReportTruncation('a patch');
      Exit;
    end;

    FreeAndNil(FPrevious);
    FPrevious := Patch;
    if not TryDrawPatch(Patch) then
    begin
      Exit;
    end;
  end;
end;

function TPdfPatchMeshesShadingContext.TryDrawPatch(const Patch: TPdfPatch): Boolean;
begin
  const Triangles = Patch.Triangles;
  Result := TryAddElement(Length(Triangles));
  if not Result then
  begin
    Exit;
  end;

  for var Triangle in Triangles do
  begin
    DrawTriangle(Triangle);
  end;
end;

// The points and colours that a patch with the edge flag 1 to 3 takes from the previous patch
procedure TPdfPatchMeshesShadingContext.UseImplicitEdge(const Flag: Integer; var Points: TArray<TPdfPatchPoint>; var Colors: TPdfPatchColors);
begin
  var Edge: TPdfPatchEdge;
  var FirstCorner, SecondCorner: Integer;
  case Flag of
    EdgeFlagFirstSide:
      begin
        Edge := FPrevious.Flag1Edge;
        FirstCorner := 1;
        SecondCorner := 2;
      end;
    EdgeFlagSecondSide:
      begin
        Edge := FPrevious.Flag2Edge;
        FirstCorner := 2;
        SecondCorner := 3;
      end;
    EdgeFlagThirdSide:
      begin
        Edge := FPrevious.Flag3Edge;
        FirstCorner := 3;
        SecondCorner := 0;
      end;
  else
    raise EArgumentOutOfRangeException.CreateFmt('An edge flag of a patch is 1 to 3 when it continues a patch, not %d', [Flag]);
  end;

  for var Index := 0 to EdgePointCount - 1 do
  begin
    Points[Index] := Edge[Index];
  end;
  Colors[0] := FPrevious.CornerColor(FirstCorner);
  Colors[1] := FPrevious.CornerColor(SecondCorner);
end;

function TPdfPatchMeshesShadingContext.TryReadPoints(const FirstIndex: Integer; const Points: TArray<TPdfPatchPoint>): Boolean;
begin
  for var Index := FirstIndex to FPointCount - 1 do
  begin
    var X, Y: Double;
    if not FReader.TryReadPoint(X, Y) then
    begin
      Exit(False);
    end;
    Points[Index] := TPdfPatchPoint.Create(X, Y);
  end;
  Result := True;
end;

function TPdfPatchMeshesShadingContext.TryReadColors(const FirstIndex: Integer; var Colors: TPdfPatchColors): Boolean;
begin
  for var Index := FirstIndex to CornerCount - 1 do
  begin
    if not FReader.TryReadColor(Colors[Index]) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

function TPdfPatchMeshesShadingContext.TryReadPatch(const Flag: Integer; out Patch: TPdfPatch): Boolean;
begin
  Patch := nil;
  var Points: TArray<TPdfPatchPoint>;
  SetLength(Points, FPointCount);
  var Colors: TPdfPatchColors;
  var FirstPoint := 0;
  var FirstColor := 0;
  if Flag <> EdgeFlagFree then
  begin
    UseImplicitEdge(Flag, Points, Colors);
    FirstPoint := EdgePointCount;
    FirstColor := ImplicitColorCount;
  end;

  Result := (TryReadPoints(FirstPoint, Points) and TryReadColors(FirstColor, Colors));
  // The data of a patch is not padded to a whole number of bytes here: readPatch of PDFBox does not read any padding
  if Result then
  begin
    Patch := MakePatch(Points, Colors);
  end;
end;

{ TPdfType6ShadingContext }

constructor TPdfType6ShadingContext.Create(const Shading: TPDShadingMesh; const ShadingToDevice: TPdfMatrix; const DeviceArea: TRect;
                                           const Cancel: IPdfCancelToken);
begin
  inherited Create(Shading, ShadingToDevice, DeviceArea, Cancel, CoonsPointCount);
end;

function TPdfType6ShadingContext.MakePatch(const Points: TArray<TPdfPatchPoint>; const Colors: TPdfPatchColors): TPdfPatch;
begin
  Result := TPdfCoonsPatch.Create(Points, Colors);
end;

{ TPdfType7ShadingContext }

constructor TPdfType7ShadingContext.Create(const Shading: TPDShadingMesh; const ShadingToDevice: TPdfMatrix; const DeviceArea: TRect;
                                           const Cancel: IPdfCancelToken);
begin
  inherited Create(Shading, ShadingToDevice, DeviceArea, Cancel, TensorPointCount);
end;

function TPdfType7ShadingContext.MakePatch(const Points: TArray<TPdfPatchPoint>; const Colors: TPdfPatchColors): TPdfPatch;
begin
  Result := TPdfTensorPatch.Create(Points, Colors);
end;

end.
