// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/shading/GouraudShadingContext.java, Type4ShadingContext.java,
// Type5ShadingContext.java, PDTriangleBasedShadingType.java, PDShadingType4.java, PDShadingType5.java and ShadedTriangle.java (3.0.8)
unit Pdf4D.Render.Shading.Triangle;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Types,
  Pdf4D.Common.Matrix,
  Pdf4D.Graphics.Shading,
  Pdf4D.Render.Renderer.Interfaces,
  Pdf4D.Render.Shading.Context;

const
  // The most triangles or patches that one shading paints; the rest of its data is skipped with a warning
  MaxMeshElements = 1000000;
  // The most triangles that one shading paints in all. A patch is cut into up to 512 triangles, so this is what bounds the time of
  // a shading of many patches.
  MaxMeshTriangles = 4000000;
  // The most work that one shading does for its pixels: a step of a line, a pixel that is tested against a triangle, a triangle. What is
  // more is skipped with a warning, so that a few bytes of data cannot keep a render busy for long.
  MaxMeshWork = 100000000;
  // A corner of a triangle is limited to this distance from the origin of the device, far beyond any device
  MaxMeshCoordinate = 1073741824;

type
  // A vertex or a corner of a patch in device space, with its colour values (the one value for a function)
  TPdfMeshVertex = record
    X: Double;
    Y: Double;
    Color: TArray<Single>;

    class function Create(const X, Y: Double; const Color: TArray<Single>): TPdfMeshVertex; static;
  end;

  // A line of pixels between two pixels, with a colour at each end (Line): Bresenham's algorithm gives its pixels
  TPdfMeshLine = record
    Start: TPoint;
    Finish: TPoint;
    StartColor: TArray<Single>;
    FinishColor: TArray<Single>;

    class function Create(const Start, Finish: TPoint; const StartColor, FinishColor: TArray<Single>): TPdfMeshLine; static;
    // The colour at the pixel (X, Y) of the line: linear along x, or along y for a vertical line (Line.calcColor)
    function ColorAt(const X, Y: Integer): TArray<Single>;
  end;

  // ShadedTriangle: a triangle with a colour at every corner. The degree is the number of corners that differ by 1/1000 pixel or more: a
  // degree of 2 is a line and of 1 a point. Three different corners in one line stay a triangle without area, as in PDFBox.
  TPdfShadedTriangle = record
  private
    FCorners: array[0..2] of TPdfMeshVertex;
    FDegree: Integer;
    FLine: TPdfMeshLine;
    FArea: Double;
    FValue0: Double;
    FValue1: Double;
    FValue2: Double;

    class function Overlaps(const First, Second: TPdfMeshVertex): Boolean; static;
    class function EdgeValue(const X, Y: Double; const First, Second: TPdfMeshVertex): Double; static;
    class function AreaOf(const X, Y: Double; const First, Second: TPdfMeshVertex): Double; static;
    class function CornerPixel(const Vertex: TPdfMeshVertex): TPoint; static;
    function CalculateDegree: Integer;
    procedure MakeLine;

  public
    class function Create(const First, Second, Third: TPdfMeshVertex): TPdfShadedTriangle; static;
    // Math.round: half up, within the range of an Integer
    class function RoundHalfUp(const Value: Double): Integer; static;

    // 0 for a triangle with a corner that is no number (nothing is painted), 1 for a point, 2 for a line, 3 for a triangle
    property Degree: Integer read FDegree;
    // The line of a triangle of the degree 2
    property Line: TPdfMeshLine read FLine;
    function Corner(const Index: Integer): TPdfMeshVertex;
    // The rounded corners of the triangle as pixels, which is the box that PDFBox tests
    function BoundaryLeft: Integer;
    function BoundaryRight: Integer;
    function BoundaryTop: Integer;
    function BoundaryBottom: Integer;
    // Whether the pixel (X, Y) lies in the triangle, its sides included. Only for a triangle (degree 3).
    function Contains(const X, Y: Integer): Boolean;
    // The colour values at the pixel (X, Y), weighted by the areas of the triangles with the sides. Only for a triangle (degree 3).
    function CalcColor(const X, Y: Integer): TArray<Single>;
  end;

  // The bits of the data of a mesh shading, the most significant bit first
  TPdfMeshBitReader = class
  private
    FBytes: TBytes;
    FPosition: Int64;

  public
    constructor Create(const Bytes: TBytes);

    function IsAtEnd: Boolean;
    function RemainingBits: Int64;
    // False when fewer than BitCount bits (1 to 32) are left; nothing is read then
    function TryRead(const BitCount: Integer; out Value: Int64): Boolean;
    // The data of one vertex or patch is padded to a whole number of bytes
    procedure AlignToByte;
  end;

  // Reads the flags, points and colours of the data of a mesh shading and puts them in device space. All reading is bounded by the data.
  TPdfMeshReader = class
  private
    FShading: TPDShadingMesh;
    FBits: TPdfMeshBitReader;
    FBitsPerCoordinate: Integer;
    FBitsPerComponent: Integer;
    FBitsPerFlag: Integer;
    FColorCount: Integer;
    FMaxCoordinate: Int64;
    FMaxComponent: Int64;
    FDecode: TArray<Single>;
    FMatrix: TPdfMatrix;
    FIsTruncationReported: Boolean;

    constructor Make(const Shading: TPDShadingMesh; const ShadingToDevice: TPdfMatrix; const Bits: TPdfMeshBitReader);
    class function IsLayoutValid(const Shading: TPDShadingMesh): Boolean; static;
    class function HasDecodeForColors(const Shading: TPDShadingMesh): Boolean; static;
    class function Interpolate(const Value: Int64; const MaxSource: Int64; const Minimum, Maximum: Single): Single; static;
    // The data of one vertex is padded to a whole number of bytes
    procedure AlignToByte;

  public
    destructor Destroy; override;

    // False, with a warning, when the data cannot be read or the entries of the shading do not fit the data. The caller owns the
    // result.
    class function TryOpen(const Shading: TPDShadingMesh; const ShadingToDevice: TPdfMatrix; out Reader: TPdfMeshReader): Boolean; static;

    function IsAtEnd: Boolean;
    // How many vertices (a point and its colour, padded to a whole number of bytes) the rest of the data can hold at most
    function RemainingVertexCount: Int64;
    // A flag is cut down to its last two bits
    function TryReadFlag(out Flag: Integer): Boolean;
    function TryReadPoint(out X, Y: Double): Boolean;
    function TryReadColor(out Color: TArray<Single>): Boolean;
    function TryReadVertex(out Vertex: TPdfMeshVertex): Boolean;
    function ColorCount: Integer;
    // Gives the warning about data that ends inside a vertex or a patch, once
    procedure ReportTruncation(const Element: string);
  end;

  // GouraudShadingContext: the triangles are painted into a table of the pixels of the area, later triangles over earlier ones, and the
  // pixel lookup reads the table
  TPdfGouraudShadingContext = class abstract(TPdfShadingContext)
  private
    const Painted = $1000000;
    // The cancel token is asked once for this much work
    const CancelInterval = 4096;

  private
    FArea: TRect;
    FPixels: TArray<Integer>;
    FCancel: IPdfCancelToken;
    FBudget: TPdfShadingBudget;
    FElementCount: Integer;
    FTriangleCount: Integer;
    FWork: Int64;
    FWorkChecked: Int64;
    FIsStopped: Boolean;
    FIsLimitReported: Boolean;

    procedure PlotPixel(const X, Y: Integer; const Color: TArray<Single>);
    function IsInArea(const X, Y: Integer): Boolean;
    function IsBeyondArea(const Position, Step, Low, High: Int64): Boolean;
    procedure FillTriangle(const Triangle: TPdfShadedTriangle);
    class function Sanitized(const Values: TArray<Single>): TArray<Single>; static;

  protected
    constructor InitializeMesh(const Shading: TPDShadingMesh; const ShadingToDevice: TPdfMatrix; const DeviceArea: TRect;
                               const Cancel: IPdfCancelToken; const Budget: TPdfShadingBudget);

    // Counts Units of work. False when the shading has to stop: it is cancelled, or has done more than MaxMeshWork or used up the budget
    // of the page (a warning, once).
    function Charge(const Units: Int64): Boolean;
    // The work is over: the reading of the rest of the data is skipped
    property IsStopped: Boolean read FIsStopped;
    // Bresenham's line: the pixels in the area get their colour from the line
    procedure PlotLine(const Line: TPdfMeshLine);

    // Counts a triangle or a patch of TriangleCount triangles. False when this shading has reached the limit of MaxMeshElements elements
    // or MaxMeshTriangles triangles, and the element must not be painted; the warning is given once.
    function TryAddElement(const TriangleCount: Integer = 1): Boolean;
    procedure DrawTriangle(const Triangle: TPdfShadedTriangle);
    function TryGetColorAt(const U, V: Single; out Rgb: Integer): Boolean; override;

  public
    function TryGetPixel(const X, Y: Integer; out Rgb: Integer): Boolean; override;
  end;

  // Type 4: the vertices with an edge flag, which says whether a vertex starts a triangle or adds one to the previous triangle
  TPdfType4ShadingContext = class(TPdfGouraudShadingContext)
  private
    FReader: TPdfMeshReader;
    FPrevious: TPdfShadedTriangle;
    FHasPrevious: Boolean;

    procedure ReadTriangles;
    // Reads the vertex after the flag. False when the data ends.
    function TryReadNextVertex(out Vertex: TPdfMeshVertex): Boolean;
    function TryStartTriangle(const First: TPdfMeshVertex): Boolean;
    function TryExtendTriangle(const Flag: Integer; const Vertex: TPdfMeshVertex): Boolean;

  public
    constructor Create(const Shading: TPDShadingMesh; const ShadingToDevice: TPdfMatrix; const DeviceArea: TRect; const Cancel: IPdfCancelToken;
                       const Budget: TPdfShadingBudget = nil);
  end;

  // Type 5: a lattice of vertices in rows, two triangles to a cell
  TPdfType5ShadingContext = class(TPdfGouraudShadingContext)
  private
    FReader: TPdfMeshReader;

    procedure ReadLattice;
    function TryReadRow(const VerticesPerRow: Integer; out Row: TArray<TPdfMeshVertex>): Boolean;
    function TryDrawRows(const Upper, Lower: TArray<TPdfMeshVertex>): Boolean;

  public
    constructor Create(const Shading: TPDShadingMesh; const ShadingToDevice: TPdfMatrix; const DeviceArea: TRect; const Cancel: IPdfCancelToken;
                       const Budget: TPdfShadingBudget = nil);
  end;

implementation

uses
  System.Math;

const
  FlagMask = 3;
  MaxBitsPerFlag = 8;
  MaxBitsPerValue = 32;
  // The barycentric weights of a point on a side are zero up to rounding
  InsideTolerance = 0.0000001;
  // The accuracy of the degree of a triangle (1/1000 pixel) and of a point that two corners share
  Thousand = 1000;
  // The steps of a line are counted as work in packs of this size
  LineChargeSteps = 1024;
  OverlapDistance = 0.001;
  EdgeFlagNewTriangle = 0;
  EdgeFlagLastSide = 1;
  EdgeFlagFirstAndLastCorner = 2;

{ TPdfMeshVertex }

class function TPdfMeshVertex.Create(const X, Y: Double; const Color: TArray<Single>): TPdfMeshVertex;
begin
  Result.X := X;
  Result.Y := Y;
  Result.Color := Color;
end;

// Math.round as a 64 bit number: half up
function HalfUp(const Value: Double): Int64;
begin
  const Shifted = Value + 0.5;
  Result := Trunc(Shifted);
  if Result > Shifted then
  begin
    Dec(Result);
  end;
end;

{ TPdfMeshLine }

class function TPdfMeshLine.Create(const Start, Finish: TPoint; const StartColor, FinishColor: TArray<Single>): TPdfMeshLine;
begin
  Result.Start := Start;
  Result.Finish := Finish;
  Result.StartColor := StartColor;
  Result.FinishColor := FinishColor;
end;

function TPdfMeshLine.ColorAt(const X, Y: Integer): TArray<Single>;
begin
  if Start = Finish then
  begin
    Exit(StartColor);
  end;

  // Single arithmetic in the order of Line.calcColor: c0 * (p1 - p) / l + c1 * (p - p0) / l
  const IsVertical = (Start.X = Finish.X);
  var Length: Single;
  var Before, After: Integer;
  if IsVertical then
  begin
    Length := Finish.Y - Start.Y;
    Before := Finish.Y - Y;
    After := Y - Start.Y;
  end
  else
  begin
    Length := Finish.X - Start.X;
    Before := Finish.X - X;
    After := X - Start.X;
  end;

  SetLength(Result, System.Length(StartColor));
  for var Index := 0 to High(Result) do
  begin
    const FromStart = Single(Single(StartColor[Index] * Single(Before)) / Length);
    const FromFinish = Single(Single(FinishColor[Index] * Single(After)) / Length);
    Result[Index] := Single(FromStart + FromFinish);
  end;
end;

{ TPdfShadedTriangle }

class function TPdfShadedTriangle.RoundHalfUp(const Value: Double): Integer;
begin
  if IsNan(Value) then
  begin
    Exit(0);
  end;

  Result := HalfUp(Max(Min(Value, Double(MaxMeshCoordinate)), -Double(MaxMeshCoordinate)));
end;

class function TPdfShadedTriangle.Create(const First, Second, Third: TPdfMeshVertex): TPdfShadedTriangle;
begin
  Result.FCorners[0] := First;
  Result.FCorners[1] := Second;
  Result.FCorners[2] := Third;
  for var Index := 0 to 2 do
  begin
    if IsNan(Result.FCorners[Index].X) or IsNan(Result.FCorners[Index].Y) then
    begin
      Result.FDegree := 0;
      Exit;
    end;
    // No device is as big as this; it keeps the products of the edge equations far from overflow
    Result.FCorners[Index].X := Max(Min(Result.FCorners[Index].X, Double(MaxMeshCoordinate)), -Double(MaxMeshCoordinate));
    Result.FCorners[Index].Y := Max(Min(Result.FCorners[Index].Y, Double(MaxMeshCoordinate)), -Double(MaxMeshCoordinate));
  end;

  Result.FArea := AreaOf(Result.FCorners[0].X, Result.FCorners[0].Y, Result.FCorners[1], Result.FCorners[2]);
  Result.FDegree := Result.CalculateDegree;
  if Result.FDegree = 2 then
  begin
    Result.MakeLine;
  end;
  Result.FValue0 := EdgeValue(Result.FCorners[0].X, Result.FCorners[0].Y, Result.FCorners[1], Result.FCorners[2]);
  Result.FValue1 := EdgeValue(Result.FCorners[1].X, Result.FCorners[1].Y, Result.FCorners[2], Result.FCorners[0]);
  Result.FValue2 := EdgeValue(Result.FCorners[2].X, Result.FCorners[2].Y, Result.FCorners[0], Result.FCorners[1]);
end;

// Two points are one when they differ by less than 1/1000 in both directions (ShadedTriangle.overlaps)
class function TPdfShadedTriangle.Overlaps(const First, Second: TPdfMeshVertex): Boolean;
begin
  Result := ((Abs(First.X - Second.X) < OverlapDistance) and (Abs(First.Y - Second.Y) < OverlapDistance));
end;

class function TPdfShadedTriangle.EdgeValue(const X, Y: Double; const First, Second: TPdfMeshVertex): Double;
begin
  Result := (Second.Y - First.Y) * (X - First.X) - (Second.X - First.X) * (Y - First.Y);
end;

// getArea: the area of the triangle of the point (X, Y) and the vertices First and Second
class function TPdfShadedTriangle.AreaOf(const X, Y: Double; const First, Second: TPdfMeshVertex): Double;
begin
  Result := Abs((Second.X - First.X) * (Second.Y - Y) - (Second.X - X) * (Second.Y - First.Y)) / 2;
end;

class function TPdfShadedTriangle.CornerPixel(const Vertex: TPdfMeshVertex): TPoint;
begin
  Result := TPoint.Create(RoundHalfUp(Vertex.X), RoundHalfUp(Vertex.Y));
end;

// The number of different corners, at the accuracy of 1/1000 pixel (calcDeg)
function TPdfShadedTriangle.CalculateDegree: Integer;
begin
  var X, Y: array[0..2] of Int64;
  for var Index := 0 to 2 do
  begin
    X[Index] := HalfUp(FCorners[Index].X * Thousand);
    Y[Index] := HalfUp(FCorners[Index].Y * Thousand);
  end;

  Result := 0;
  for var Index := 0 to 2 do
  begin
    var IsKnown := False;
    for var Earlier := 0 to Index - 1 do
    begin
      IsKnown := (IsKnown or ((X[Earlier] = X[Index]) and (Y[Earlier] = Y[Index])));
    end;
    if not IsKnown then
    begin
      Inc(Result);
    end;
  end;
end;

// A triangle of the degree 2 is the line between two of its corners
procedure TPdfShadedTriangle.MakeLine;
begin
  if Overlaps(FCorners[1], FCorners[2]) and (not Overlaps(FCorners[0], FCorners[2])) then
  begin
    FLine := TPdfMeshLine.Create(CornerPixel(FCorners[0]), CornerPixel(FCorners[2]), FCorners[0].Color, FCorners[2].Color);
  end
  else
  begin
    FLine := TPdfMeshLine.Create(CornerPixel(FCorners[1]), CornerPixel(FCorners[2]), FCorners[1].Color, FCorners[2].Color);
  end;
end;

function TPdfShadedTriangle.Corner(const Index: Integer): TPdfMeshVertex;
begin
  Result := FCorners[Index];
end;

function TPdfShadedTriangle.BoundaryLeft: Integer;
begin
  Result := Min(CornerPixel(FCorners[0]).X, Min(CornerPixel(FCorners[1]).X, CornerPixel(FCorners[2]).X));
end;

function TPdfShadedTriangle.BoundaryRight: Integer;
begin
  Result := Max(CornerPixel(FCorners[0]).X, Max(CornerPixel(FCorners[1]).X, CornerPixel(FCorners[2]).X));
end;

function TPdfShadedTriangle.BoundaryTop: Integer;
begin
  Result := Min(CornerPixel(FCorners[0]).Y, Min(CornerPixel(FCorners[1]).Y, CornerPixel(FCorners[2]).Y));
end;

function TPdfShadedTriangle.BoundaryBottom: Integer;
begin
  Result := Max(CornerPixel(FCorners[0]).Y, Max(CornerPixel(FCorners[1]).Y, CornerPixel(FCorners[2]).Y));
end;

// The pixel is outside when a corner and the pixel lie on different sides of the opposite side; on a side it is inside. For three corners
// in one line every pixel is inside, as in PDFBox (all values are 0).
function TPdfShadedTriangle.Contains(const X, Y: Integer): Boolean;
begin
  Result := False;
  if EdgeValue(X, Y, FCorners[1], FCorners[2]) * FValue0 < 0 then
  begin
    Exit;
  end;
  if EdgeValue(X, Y, FCorners[2], FCorners[0]) * FValue1 < 0 then
  begin
    Exit;
  end;
  Result := (EdgeValue(X, Y, FCorners[0], FCorners[1]) * FValue2 >= 0);
end;

// Single arithmetic like PDFBox: the weights are floats of the ratios of the areas. A triangle without area gives weights that are no
// numbers, which the colour conversion takes as 0 or the largest value.
function TPdfShadedTriangle.CalcColor(const X, Y: Integer): TArray<Single>;
begin
  const FirstWeight = Single(AreaOf(X, Y, FCorners[1], FCorners[2]) / FArea);
  const SecondWeight = Single(AreaOf(X, Y, FCorners[2], FCorners[0]) / FArea);
  const ThirdWeight = Single(AreaOf(X, Y, FCorners[0], FCorners[1]) / FArea);
  SetLength(Result, Length(FCorners[0].Color));
  for var Index := 0 to High(Result) do
  begin
    Result[Index] := Single(Single(Single(FCorners[0].Color[Index] * FirstWeight) + Single(FCorners[1].Color[Index] * SecondWeight)) +
                            Single(FCorners[2].Color[Index] * ThirdWeight));
  end;
end;

{ TPdfMeshBitReader }

constructor TPdfMeshBitReader.Create(const Bytes: TBytes);
begin
  inherited Create;
  FBytes := Bytes;
end;

function TPdfMeshBitReader.IsAtEnd: Boolean;
begin
  Result := (FPosition >= (Int64(Length(FBytes)) * 8));
end;

function TPdfMeshBitReader.RemainingBits: Int64;
begin
  Result := Max(Int64(Length(FBytes)) * 8 - FPosition, 0);
end;

function TPdfMeshBitReader.TryRead(const BitCount: Integer; out Value: Int64): Boolean;
begin
  Value := 0;
  Result := ((FPosition + BitCount) <= (Int64(Length(FBytes)) * 8));
  if not Result then
  begin
    Exit;
  end;

  var Remaining := BitCount;
  while Remaining > 0 do
  begin
    const BitsLeftInByte = 8 - Integer(FPosition and 7);
    const Take = Min(Remaining, BitsLeftInByte);
    const Shifted = (FBytes[FPosition shr 3] shr (BitsLeftInByte - Take)) and ((1 shl Take) - 1);
    Value := ((Value shl Take) or Shifted);
    Inc(FPosition, Take);
    Dec(Remaining, Take);
  end;
end;

procedure TPdfMeshBitReader.AlignToByte;
begin
  FPosition := ((FPosition + 7) and (not Int64(7)));
end;

{ TPdfMeshReader }

constructor TPdfMeshReader.Make(const Shading: TPDShadingMesh; const ShadingToDevice: TPdfMatrix; const Bits: TPdfMeshBitReader);
begin
  inherited Create;
  FShading := Shading;
  FBits := Bits;
  FBitsPerCoordinate := Shading.BitsPerCoordinate;
  FBitsPerComponent := Shading.BitsPerComponent;
  FBitsPerFlag := Shading.BitsPerFlag;
  FColorCount := Shading.ColorComponentCount;
  FMaxCoordinate := (Int64(1) shl FBitsPerCoordinate) - 1;
  FMaxComponent := (Int64(1) shl FBitsPerComponent) - 1;
  FMatrix := ShadingToDevice;
  SetLength(FDecode, (2 + FColorCount) * 2);
  for var Parameter := 0 to 1 + FColorCount do
  begin
    Shading.TryGetDecode(Parameter, FDecode[Parameter * 2], FDecode[Parameter * 2 + 1]);
  end;
end;

destructor TPdfMeshReader.Destroy;
begin
  FBits.Free;
  inherited;
end;

class function TPdfMeshReader.IsLayoutValid(const Shading: TPDShadingMesh): Boolean;
begin
  Result := False;
  if (Shading.BitsPerCoordinate < 1) or (Shading.BitsPerCoordinate > MaxBitsPerValue) then
  begin
    Shading.Warn('The mesh shading has an invalid /BitsPerCoordinate (%d)', [Shading.BitsPerCoordinate]);
  end
  else if (Shading.BitsPerComponent < 1) or (Shading.BitsPerComponent > MaxBitsPerValue) then
  begin
    Shading.Warn('The mesh shading has an invalid /BitsPerComponent (%d)', [Shading.BitsPerComponent]);
  end
  else if (Shading.ShadingType <> 5) and ((Shading.BitsPerFlag < 1) or (Shading.BitsPerFlag > MaxBitsPerFlag)) then
  begin
    Shading.Warn('The mesh shading has an invalid /BitsPerFlag (%d)', [Shading.BitsPerFlag]);
  end
  else if Shading.ColorComponentCount < 1 then
  begin
    Shading.Warn('The mesh shading has no colour components', []);
  end
  else
  begin
    Result := HasDecodeForColors(Shading);
  end;
end;

class function TPdfMeshReader.HasDecodeForColors(const Shading: TPDShadingMesh): Boolean;
begin
  var Minimum, Maximum: Single;
  Result := True;
  for var Parameter := 0 to 1 + Shading.ColorComponentCount do
  begin
    Result := (Result and Shading.TryGetDecode(Parameter, Minimum, Maximum));
  end;
  if not Result then
  begin
    Shading.Warn('The /Decode of the mesh shading has fewer than %d numbers', [(2 + Shading.ColorComponentCount) * 2]);
  end;
end;

class function TPdfMeshReader.TryOpen(const Shading: TPDShadingMesh; const ShadingToDevice: TPdfMatrix; out Reader: TPdfMeshReader): Boolean;
begin
  Reader := nil;
  var Data: TBytes;
  if (not Shading.TryReadData(Data)) or (not IsLayoutValid(Shading)) then
  begin
    Exit(False);
  end;

  // collectTriangles and collectPatches give nothing when the range of x or y is empty
  var MinimumX, MaximumX, MinimumY, MaximumY: Single;
  Shading.TryGetDecode(0, MinimumX, MaximumX);
  Shading.TryGetDecode(1, MinimumY, MaximumY);
  if (MinimumX = MaximumX) or (MinimumY = MaximumY) then
  begin
    Exit(False);
  end;

  Reader := TPdfMeshReader.Make(Shading, ShadingToDevice, TPdfMeshBitReader.Create(Data));
  Result := True;
end;

class function TPdfMeshReader.Interpolate(const Value: Int64; const MaxSource: Int64; const Minimum, Maximum: Single): Single;
begin
  Result := Minimum + (Single(Value) * (Maximum - Minimum) / Single(MaxSource));
end;

function TPdfMeshReader.IsAtEnd: Boolean;
begin
  Result := FBits.IsAtEnd;
end;

procedure TPdfMeshReader.AlignToByte;
begin
  FBits.AlignToByte;
end;

function TPdfMeshReader.RemainingVertexCount: Int64;
begin
  const BitsOfVertex = 2 * Int64(FBitsPerCoordinate) + Int64(FColorCount) * FBitsPerComponent;
  const BitsOfBytes = ((BitsOfVertex + 7) div 8) * 8;
  Result := (FBits.RemainingBits div BitsOfBytes);
end;

function TPdfMeshReader.ColorCount: Integer;
begin
  Result := FColorCount;
end;

function TPdfMeshReader.TryReadFlag(out Flag: Integer): Boolean;
begin
  var Value: Int64;
  Result := FBits.TryRead(FBitsPerFlag, Value);
  Flag := (Integer(Value) and FlagMask);
end;

function TPdfMeshReader.TryReadPoint(out X, Y: Double): Boolean;
begin
  X := 0;
  Y := 0;
  var RawX, RawY: Int64;
  Result := (FBits.TryRead(FBitsPerCoordinate, RawX) and FBits.TryRead(FBitsPerCoordinate, RawY));
  if not Result then
  begin
    Exit;
  end;

  const ShadingX = Interpolate(RawX, FMaxCoordinate, FDecode[0], FDecode[1]);
  const ShadingY = Interpolate(RawY, FMaxCoordinate, FDecode[2], FDecode[3]);
  X := (Double(FMatrix.ScaleX) * ShadingX + Double(FMatrix.ShearX) * ShadingY + FMatrix.TranslateX);
  Y := (Double(FMatrix.ShearY) * ShadingX + Double(FMatrix.ScaleY) * ShadingY + FMatrix.TranslateY);
end;

function TPdfMeshReader.TryReadColor(out Color: TArray<Single>): Boolean;
begin
  SetLength(Color, FColorCount);
  Result := True;
  for var Index := 0 to FColorCount - 1 do
  begin
    var Raw: Int64;
    if not FBits.TryRead(FBitsPerComponent, Raw) then
    begin
      Exit(False);
    end;
    Color[Index] := Interpolate(Raw, FMaxComponent, FDecode[(2 + Index) * 2], FDecode[(2 + Index) * 2 + 1]);
  end;
end;

function TPdfMeshReader.TryReadVertex(out Vertex: TPdfMeshVertex): Boolean;
begin
  var X, Y: Double;
  var Color: TArray<Single>;
  Result := (TryReadPoint(X, Y) and TryReadColor(Color));
  if Result then
  begin
    Vertex := TPdfMeshVertex.Create(X, Y, Color);
    AlignToByte;
  end;
end;

procedure TPdfMeshReader.ReportTruncation(const Element: string);
begin
  if not FIsTruncationReported then
  begin
    FIsTruncationReported := True;
    FShading.Warn('The data of the mesh shading ends in the middle of %s', [Element]);
  end;
end;

{ TPdfGouraudShadingContext }

constructor TPdfGouraudShadingContext.InitializeMesh(const Shading: TPDShadingMesh; const ShadingToDevice: TPdfMatrix; const DeviceArea: TRect;
                                                     const Cancel: IPdfCancelToken; const Budget: TPdfShadingBudget);
begin
  inherited Initialize(Shading, ShadingToDevice);
  FArea := DeviceArea;
  FCancel := Cancel;
  FBudget := Budget;
  SetLength(FPixels, Int64(DeviceArea.Width) * DeviceArea.Height);
end;

function TPdfGouraudShadingContext.TryGetColorAt(const U, V: Single; out Rgb: Integer): Boolean;
begin
  raise ENotSupportedException.Create('A mesh shading is read by pixel, not by the point of the shading');
end;

function TPdfGouraudShadingContext.IsInArea(const X, Y: Integer): Boolean;
begin
  Result := ((X >= FArea.Left) and (X < FArea.Right) and (Y >= FArea.Top) and (Y < FArea.Bottom));
end;

function TPdfGouraudShadingContext.TryGetPixel(const X, Y: Integer; out Rgb: Integer): Boolean;
begin
  Rgb := 0;
  if IsInArea(X, Y) then
  begin
    const Stored = FPixels[(Y - FArea.Top) * FArea.Width + (X - FArea.Left)];
    if Stored <> 0 then
    begin
      Rgb := (Stored and (Painted - 1));
      Exit(True);
    end;
  end;

  Rgb := RgbBackground;
  Result := HasBackground;
end;

function TPdfGouraudShadingContext.Charge(const Units: Int64): Boolean;
begin
  if FIsStopped then
  begin
    Exit(False);
  end;

  Inc(FWork, Units);
  if FWork > MaxMeshWork then
  begin
    FIsStopped := True;
    Shading.Warn('The mesh shading exceeds the work limit of %d steps; the rest is skipped', [MaxMeshWork]);
  end
  else if Assigned(FBudget) and (not FBudget.TryCharge(Units)) then
  begin
    FIsStopped := True;
    FBudget.Report(Shading);
  end
  else if (FWork div CancelInterval) <> FWorkChecked then
  begin
    FWorkChecked := (FWork div CancelInterval);
    FIsStopped := (Assigned(FCancel) and FCancel.IsCancelled);
  end;
  Result := (not FIsStopped);
end;

function TPdfGouraudShadingContext.TryAddElement(const TriangleCount: Integer): Boolean;
begin
  Result := ((not FIsStopped) and (FElementCount < MaxMeshElements) and ((FTriangleCount + TriangleCount) <= MaxMeshTriangles));
  if Result then
  begin
    Inc(FElementCount);
    Inc(FTriangleCount, TriangleCount);
    Exit(Charge(1));
  end;

  if (not FIsStopped) and (not FIsLimitReported) then
  begin
    FIsLimitReported := True;
    Shading.Warn('The mesh shading exceeds the limit of %d triangles or patches (or %d triangles); the rest is skipped', [MaxMeshElements, MaxMeshTriangles]);
  end;
end;

// The values that a triangle without area gives are no numbers or infinite; Java cuts those to 0 and to the largest value
class function TPdfGouraudShadingContext.Sanitized(const Values: TArray<Single>): TArray<Single>;
begin
  Result := Copy(Values);
  for var Index := 0 to High(Result) do
  begin
    if IsNan(Result[Index]) then
    begin
      Result[Index] := 0;
    end
    else if IsInfinite(Result[Index]) then
    begin
      Result[Index] := IfThen(Result[Index] > 0, MaxSingle, -MaxSingle);
    end;
  end;
end;

procedure TPdfGouraudShadingContext.PlotPixel(const X, Y: Integer; const Color: TArray<Single>);
begin
  if not IsInArea(X, Y) then
  begin
    Exit;
  end;

  var Values := Sanitized(Color);
  if Shading.HasFunction then
  begin
    Values := Sanitized(Shading.EvalFunction(Values));
  end;
  FPixels[(Y - FArea.Top) * FArea.Width + (X - FArea.Left)] := (ConvertToRgb(Values) or Painted);
end;

procedure TPdfGouraudShadingContext.DrawTriangle(const Triangle: TPdfShadedTriangle);
begin
  if not Charge(1) then
  begin
    Exit;
  end;

  case Triangle.Degree of
    0: ;
    2: PlotLine(Triangle.Line);
  else
    FillTriangle(Triangle);
  end;
end;

// Whether a line that goes on in the direction of Step has left the range Low..High - 1 for good
function TPdfGouraudShadingContext.IsBeyondArea(const Position, Step, Low, High: Int64): Boolean;
begin
  Result := (((Step > 0) and (Position >= High)) or ((Step < 0) and (Position < Low)));
end;

// Line.calcLine: Bresenham's algorithm. Only the pixels in the area are plotted; the line stops when it has left the area for good, and the
// steps count as work.
procedure TPdfGouraudShadingContext.PlotLine(const Line: TPdfMeshLine);
begin
  var X: Int64 := Line.Start.X;
  var Y: Int64 := Line.Start.Y;
  const FinishX: Int64 = Line.Finish.X;
  const FinishY: Int64 = Line.Finish.Y;
  const IsOutside = ((Max(X, FinishX) < FArea.Left) or (Min(X, FinishX) >= FArea.Right) or
                     (Max(Y, FinishY) < FArea.Top) or (Min(Y, FinishY) >= FArea.Bottom));
  if IsOutside then
  begin
    Exit;
  end;

  const DeltaX = Abs(FinishX - X);
  const DeltaY = Abs(FinishY - Y);
  const StepX = IfThen(X < FinishX, 1, -1);
  const StepY = IfThen(Y < FinishY, 1, -1);
  var Error := DeltaX - DeltaY;
  var Pending := 0;
  while True do
  begin
    if IsInArea(Integer(X), Integer(Y)) then
    begin
      PlotPixel(Integer(X), Integer(Y), Line.ColorAt(Integer(X), Integer(Y)));
    end;

    const IsDone = ((X = FinishX) and (Y = FinishY));
    const HasLeft = (IsBeyondArea(X, StepX, FArea.Left, FArea.Right) or IsBeyondArea(Y, StepY, FArea.Top, FArea.Bottom));
    if IsDone or HasLeft then
    begin
      Break;
    end;

    const Doubled = 2 * Error;
    if Doubled > -DeltaY then
    begin
      Dec(Error, DeltaY);
      Inc(X, StepX);
    end;
    if Doubled < DeltaX then
    begin
      Inc(Error, DeltaX);
      Inc(Y, StepY);
    end;

    Inc(Pending);
    if Pending = LineChargeSteps then
    begin
      if not Charge(Pending) then
      begin
        Exit;
      end;
      Pending := 0;
    end;
  end;
  Charge(Pending);
end;

// calcPixelTable: the pixels of the box of the triangle that lie in it, and then its three sides as lines, which fattens the triangle and
// closes the seams between neighbours
procedure TPdfGouraudShadingContext.FillTriangle(const Triangle: TPdfShadedTriangle);
begin
  const Left = Max(Triangle.BoundaryLeft, FArea.Left);
  const Right = Min(Triangle.BoundaryRight, FArea.Right - 1);
  const Top = Max(Triangle.BoundaryTop, FArea.Top);
  const Bottom = Min(Triangle.BoundaryBottom, FArea.Bottom - 1);
  for var X := Left to Right do
  begin
    if not Charge(Max(Bottom - Top + 1, 1)) then
    begin
      Exit;
    end;

    for var Y := Top to Bottom do
    begin
      if Triangle.Contains(X, Y) then
      begin
        PlotPixel(X, Y, Triangle.CalcColor(X, Y));
      end;
    end;
  end;

  const First = TPoint.Create(TPdfShadedTriangle.RoundHalfUp(Triangle.Corner(0).X), TPdfShadedTriangle.RoundHalfUp(Triangle.Corner(0).Y));
  const Second = TPoint.Create(TPdfShadedTriangle.RoundHalfUp(Triangle.Corner(1).X), TPdfShadedTriangle.RoundHalfUp(Triangle.Corner(1).Y));
  const Third = TPoint.Create(TPdfShadedTriangle.RoundHalfUp(Triangle.Corner(2).X), TPdfShadedTriangle.RoundHalfUp(Triangle.Corner(2).Y));
  PlotLine(TPdfMeshLine.Create(First, Second, Triangle.Corner(0).Color, Triangle.Corner(1).Color));
  PlotLine(TPdfMeshLine.Create(Second, Third, Triangle.Corner(1).Color, Triangle.Corner(2).Color));
  PlotLine(TPdfMeshLine.Create(Third, First, Triangle.Corner(2).Color, Triangle.Corner(0).Color));
end;

{ TPdfType4ShadingContext }

constructor TPdfType4ShadingContext.Create(const Shading: TPDShadingMesh; const ShadingToDevice: TPdfMatrix; const DeviceArea: TRect;
                                           const Cancel: IPdfCancelToken; const Budget: TPdfShadingBudget);
begin
  inherited InitializeMesh(Shading, ShadingToDevice, DeviceArea, Cancel, Budget);
  if TPdfMeshReader.TryOpen(Shading, ShadingToDevice, FReader) then
  begin
    try
      ReadTriangles;
    finally
      FreeAndNil(FReader);
    end;
  end;
end;

// Type4ShadingContext / PDShadingType4.collectTriangles. A flag other than 0 to 2 ends the data, because the vertices after it cannot be
// placed.
procedure TPdfType4ShadingContext.ReadTriangles;
begin
  while (not FReader.IsAtEnd) and (not IsStopped) do
  begin
    var Flag: Integer;
    var Vertex: TPdfMeshVertex;
    if not (FReader.TryReadFlag(Flag) and FReader.TryReadVertex(Vertex)) then
    begin
      FReader.ReportTruncation('a vertex');
      Exit;
    end;

    const StartsTriangle = (Flag = EdgeFlagNewTriangle);
    var IsContinued: Boolean;
    if StartsTriangle then
    begin
      IsContinued := TryStartTriangle(Vertex);
    end
    else
    begin
      IsContinued := TryExtendTriangle(Flag, Vertex);
    end;

    if not IsContinued then
    begin
      Exit;
    end;
  end;
end;

function TPdfType4ShadingContext.TryReadNextVertex(out Vertex: TPdfMeshVertex): Boolean;
begin
  var Flag: Integer;
  Result := (FReader.TryReadFlag(Flag) and FReader.TryReadVertex(Vertex));
  if not Result then
  begin
    FReader.ReportTruncation('a triangle');
  end;
end;

// The flags of the second and the third vertex of a free triangle are ignored
function TPdfType4ShadingContext.TryStartTriangle(const First: TPdfMeshVertex): Boolean;
begin
  var Second, Third: TPdfMeshVertex;
  Result := (TryReadNextVertex(Second) and TryReadNextVertex(Third));
  if not Result then
  begin
    Exit;
  end;

  FPrevious := TPdfShadedTriangle.Create(First, Second, Third);
  FHasPrevious := True;
  Result := TryAddElement;
  if Result then
  begin
    DrawTriangle(FPrevious);
  end;
end;

function TPdfType4ShadingContext.TryExtendTriangle(const Flag: Integer; const Vertex: TPdfMeshVertex): Boolean;
begin
  const IsKnownFlag = ((Flag = EdgeFlagLastSide) or (Flag = EdgeFlagFirstAndLastCorner));
  if not IsKnownFlag then
  begin
    Shading.Warn('The mesh shading has the edge flag %d, which is not 0 to 2; the rest of the data is skipped', [Flag]);
    Exit(False);
  end;

  if not FHasPrevious then
  begin
    Shading.Warn('The mesh shading continues a triangle before it has one; the rest of the data is skipped', []);
    Exit(False);
  end;

  if Flag = EdgeFlagLastSide then
  begin
    FPrevious := TPdfShadedTriangle.Create(FPrevious.Corner(1), FPrevious.Corner(2), Vertex);
  end
  else
  begin
    FPrevious := TPdfShadedTriangle.Create(FPrevious.Corner(0), FPrevious.Corner(2), Vertex);
  end;

  Result := TryAddElement;
  if Result then
  begin
    DrawTriangle(FPrevious);
  end;
end;

{ TPdfType5ShadingContext }

constructor TPdfType5ShadingContext.Create(const Shading: TPDShadingMesh; const ShadingToDevice: TPdfMatrix; const DeviceArea: TRect;
                                           const Cancel: IPdfCancelToken; const Budget: TPdfShadingBudget);
begin
  inherited InitializeMesh(Shading, ShadingToDevice, DeviceArea, Cancel, Budget);
  if TPdfMeshReader.TryOpen(Shading, ShadingToDevice, FReader) then
  begin
    try
      ReadLattice;
    finally
      FreeAndNil(FReader);
    end;
  end;
end;

// PDShadingType5.collectTriangles: the rows go in pairs, a row that is not complete at the end of the data is dropped
procedure TPdfType5ShadingContext.ReadLattice;
begin
  const VerticesPerRow = TPDShadingMesh(Shading).VerticesPerRow;
  if VerticesPerRow < 2 then
  begin
    Shading.Warn('The mesh shading has an invalid /VerticesPerRow (%d)', [VerticesPerRow]);
    Exit;
  end;

  // Two rows are needed for a triangle. A row longer than the data, or than the limit, is never read: it would only be an allocation.
  const RowsFit = ((Int64(VerticesPerRow) * 2 <= FReader.RemainingVertexCount) and (VerticesPerRow <= MaxMeshElements));
  if not RowsFit then
  begin
    Shading.Warn('The mesh shading has /VerticesPerRow %d, which does not fit two rows in its data or the limit of %d; nothing is painted', [VerticesPerRow, MaxMeshElements]);
    Exit;
  end;

  var Upper, Lower: TArray<TPdfMeshVertex>;
  if not TryReadRow(VerticesPerRow, Upper) then
  begin
    Exit;
  end;

  while (not IsStopped) and TryReadRow(VerticesPerRow, Lower) do
  begin
    if not TryDrawRows(Upper, Lower) then
    begin
      Exit;
    end;
    Upper := Lower;
  end;
end;

function TPdfType5ShadingContext.TryReadRow(const VerticesPerRow: Integer; out Row: TArray<TPdfMeshVertex>): Boolean;
begin
  SetLength(Row, VerticesPerRow);
  for var Index := 0 to VerticesPerRow - 1 do
  begin
    if FReader.IsAtEnd then
    begin
      Exit(False);
    end;

    if not FReader.TryReadVertex(Row[Index]) then
    begin
      FReader.ReportTruncation('a vertex');
      Exit(False);
    end;
  end;
  Result := True;
end;

// Each cell is the two triangles on its diagonal from the upper right to the lower left
function TPdfType5ShadingContext.TryDrawRows(const Upper, Lower: TArray<TPdfMeshVertex>): Boolean;
begin
  Result := True;
  for var Column := 0 to High(Upper) - 1 do
  begin
    Result := (TryAddElement and TryAddElement);
    if not Result then
    begin
      Exit;
    end;

    DrawTriangle(TPdfShadedTriangle.Create(Upper[Column], Upper[Column + 1], Lower[Column]));
    DrawTriangle(TPdfShadedTriangle.Create(Upper[Column + 1], Lower[Column], Lower[Column + 1]));
  end;
end;

end.
