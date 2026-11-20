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
  Pdf4D.Render.Shading.Context;

const
  // The most triangles or patches that one shading paints; the rest of its data is skipped with a warning
  MaxMeshElements = 1000000;
  // The most triangles that one shading paints in all. A patch is cut into up to 512 triangles, so this is what bounds the time of
  // a shading of many patches.
  MaxMeshTriangles = 4000000;

type
  // A vertex or a corner of a patch in device space, with its colour values (the one value for a function)
  TPdfMeshVertex = record
    X: Double;
    Y: Double;
    Color: TArray<Single>;

    class function Create(const X, Y: Double; const Color: TArray<Single>): TPdfMeshVertex; static;
  end;

  // ShadedTriangle: a triangle with a colour at every corner. Corners that fall on the same pixel make a point or a line, which
  // PDFBox paints as such (the degree 1 and 2).
  TPdfShadedTriangle = record
  private
    FCorners: array[0..2] of TPdfMeshVertex;
    FDegree: Integer;
    FLineStart: Integer;
    FLineEnd: Integer;
    FDoubleArea: Double;

    class function RoundedX(const Vertex: TPdfMeshVertex): Integer; static;
    class function RoundedY(const Vertex: TPdfMeshVertex): Integer; static;
    function HasSameRoundedPoint(const First, Second: Integer): Boolean;
    procedure DetermineDegree;
    procedure ChooseLineEnds;

  public
    class function Create(const First, Second, Third: TPdfMeshVertex): TPdfShadedTriangle; static;

    // 1 for a point, 2 for a line (also three corners in a line), 3 for a triangle
    property Degree: Integer read FDegree;
    function Corner(const Index: Integer): TPdfMeshVertex;
    // The pixels that the corners cover; the line has the corners LineStart and LineEnd
    function LineStart: TPdfMeshVertex;
    function LineEnd: TPdfMeshVertex;
    function BoundaryLeft: Integer;
    function BoundaryRight: Integer;
    function BoundaryTop: Integer;
    function BoundaryBottom: Integer;
    // Whether the point (X, Y) lies in the triangle, its sides included. Only for a triangle (degree 3).
    function Contains(const X, Y: Double): Boolean;
    // The colour values at (X, Y), the weighted sum of the colours of the corners. Only for a triangle (degree 3).
    function CalcColor(const X, Y: Double): TArray<Single>;
  end;

  // The bits of the data of a mesh shading, the most significant bit first
  TPdfMeshBitReader = class
  private
    FBytes: TBytes;
    FPosition: Int64;

  public
    constructor Create(const Bytes: TBytes);

    function IsAtEnd: Boolean;
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

  public
    destructor Destroy; override;

    // False, with a warning, when the data cannot be read or the entries of the shading do not fit the data. The caller owns the
    // result.
    class function TryOpen(const Shading: TPDShadingMesh; const ShadingToDevice: TPdfMatrix; out Reader: TPdfMeshReader): Boolean; static;

    function IsAtEnd: Boolean;
    procedure AlignToByte;
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

  private
    FArea: TRect;
    FPixels: TArray<Integer>;
    FElementCount: Integer;
    FTriangleCount: Integer;
    FIsLimitReported: Boolean;

    procedure PlotPixel(const X, Y: Integer; const Color: TArray<Single>);
    procedure PlotPoint(const Triangle: TPdfShadedTriangle);
    procedure PlotLine(const Triangle: TPdfShadedTriangle);
    procedure FillTriangle(const Triangle: TPdfShadedTriangle);
    class function LineParameter(const Start, Finish: Integer; const Current: Integer): Single; static;

  protected
    constructor InitializeMesh(const Shading: TPDShadingMesh; const ShadingToDevice: TPdfMatrix; const DeviceArea: TRect);

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
    constructor Create(const Shading: TPDShadingMesh; const ShadingToDevice: TPdfMatrix; const DeviceArea: TRect);
  end;

  // Type 5: a lattice of vertices in rows, two triangles to a cell
  TPdfType5ShadingContext = class(TPdfGouraudShadingContext)
  private
    FReader: TPdfMeshReader;

    procedure ReadLattice;
    function TryReadRow(const VerticesPerRow: Integer; out Row: TArray<TPdfMeshVertex>): Boolean;
    function TryDrawRows(const Upper, Lower: TArray<TPdfMeshVertex>): Boolean;

  public
    constructor Create(const Shading: TPDShadingMesh; const ShadingToDevice: TPdfMatrix; const DeviceArea: TRect);
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

{ TPdfShadedTriangle }

class function TPdfShadedTriangle.Create(const First, Second, Third: TPdfMeshVertex): TPdfShadedTriangle;
begin
  Result.FCorners[0] := First;
  Result.FCorners[1] := Second;
  Result.FCorners[2] := Third;
  Result.DetermineDegree;
end;

// Java's Math.round: half up
class function TPdfShadedTriangle.RoundedX(const Vertex: TPdfMeshVertex): Integer;
begin
  Result := Floor(Vertex.X + 0.5);
end;

class function TPdfShadedTriangle.RoundedY(const Vertex: TPdfMeshVertex): Integer;
begin
  Result := Floor(Vertex.Y + 0.5);
end;

function TPdfShadedTriangle.HasSameRoundedPoint(const First, Second: Integer): Boolean;
begin
  const SameX = (RoundedX(FCorners[First]) = RoundedX(FCorners[Second]));
  const SameY = (RoundedY(FCorners[First]) = RoundedY(FCorners[Second]));
  Result := (SameX and SameY);
end;

// The degree is the number of different pixels under the corners. Three different pixels in one line make a line as well, because
// such a triangle has no area to fill.
procedure TPdfShadedTriangle.DetermineDegree;
begin
  FLineStart := 0;
  FLineEnd := 1;
  FDoubleArea := ((FCorners[1].X - FCorners[0].X) * (FCorners[2].Y - FCorners[0].Y) -
                  (FCorners[2].X - FCorners[0].X) * (FCorners[1].Y - FCorners[0].Y));

  const FirstEqualsSecond = HasSameRoundedPoint(0, 1);
  const SecondEqualsThird = HasSameRoundedPoint(1, 2);
  const ThirdEqualsFirst = HasSameRoundedPoint(2, 0);
  if FirstEqualsSecond and SecondEqualsThird then
  begin
    FDegree := 1;
  end
  else if FirstEqualsSecond then
  begin
    FDegree := 2;
    FLineEnd := 2;
  end
  else if SecondEqualsThird or ThirdEqualsFirst then
  begin
    FDegree := 2;
  end
  else if FDoubleArea = 0 then
  begin
    FDegree := 2;
    ChooseLineEnds;
  end
  else
  begin
    FDegree := 3;
  end;
end;

// Of three pixels in one line, the two that are farthest apart are the ends
procedure TPdfShadedTriangle.ChooseLineEnds;
begin
  var Longest := -1.0;
  for var First := 0 to 1 do
  begin
    for var Second := First + 1 to 2 do
    begin
      const DeltaX = RoundedX(FCorners[First]) - RoundedX(FCorners[Second]);
      const DeltaY = RoundedY(FCorners[First]) - RoundedY(FCorners[Second]);
      const Distance = (Sqr(Double(DeltaX)) + Sqr(Double(DeltaY)));
      if Distance > Longest then
      begin
        Longest := Distance;
        FLineStart := First;
        FLineEnd := Second;
      end;
    end;
  end;
end;

function TPdfShadedTriangle.Corner(const Index: Integer): TPdfMeshVertex;
begin
  Result := FCorners[Index];
end;

function TPdfShadedTriangle.LineStart: TPdfMeshVertex;
begin
  Result := FCorners[FLineStart];
end;

function TPdfShadedTriangle.LineEnd: TPdfMeshVertex;
begin
  Result := FCorners[FLineEnd];
end;

function TPdfShadedTriangle.BoundaryLeft: Integer;
begin
  Result := Floor(Min(FCorners[0].X, Min(FCorners[1].X, FCorners[2].X)));
end;

function TPdfShadedTriangle.BoundaryRight: Integer;
begin
  Result := Ceil(Max(FCorners[0].X, Max(FCorners[1].X, FCorners[2].X)));
end;

function TPdfShadedTriangle.BoundaryTop: Integer;
begin
  Result := Floor(Min(FCorners[0].Y, Min(FCorners[1].Y, FCorners[2].Y)));
end;

function TPdfShadedTriangle.BoundaryBottom: Integer;
begin
  Result := Ceil(Max(FCorners[0].Y, Max(FCorners[1].Y, FCorners[2].Y)));
end;

function TPdfShadedTriangle.Contains(const X, Y: Double): Boolean;
begin
  const FirstWeight = ((FCorners[1].X - X) * (FCorners[2].Y - Y) - (FCorners[2].X - X) * (FCorners[1].Y - Y)) / FDoubleArea;
  const SecondWeight = ((FCorners[2].X - X) * (FCorners[0].Y - Y) - (FCorners[0].X - X) * (FCorners[2].Y - Y)) / FDoubleArea;
  const ThirdWeight = 1 - FirstWeight - SecondWeight;
  Result := ((FirstWeight >= -InsideTolerance) and (SecondWeight >= -InsideTolerance) and (ThirdWeight >= -InsideTolerance));
end;

function TPdfShadedTriangle.CalcColor(const X, Y: Double): TArray<Single>;
begin
  const FirstWeight = ((FCorners[1].X - X) * (FCorners[2].Y - Y) - (FCorners[2].X - X) * (FCorners[1].Y - Y)) / FDoubleArea;
  const SecondWeight = ((FCorners[2].X - X) * (FCorners[0].Y - Y) - (FCorners[0].X - X) * (FCorners[2].Y - Y)) / FDoubleArea;
  const ThirdWeight = 1 - FirstWeight - SecondWeight;
  SetLength(Result, Length(FCorners[0].Color));
  for var Index := 0 to High(Result) do
  begin
    Result[Index] := (FCorners[0].Color[Index] * FirstWeight +
                      FCorners[1].Color[Index] * SecondWeight +
                      FCorners[2].Color[Index] * ThirdWeight);
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

constructor TPdfGouraudShadingContext.InitializeMesh(const Shading: TPDShadingMesh; const ShadingToDevice: TPdfMatrix; const DeviceArea: TRect);
begin
  inherited Initialize(Shading, ShadingToDevice);
  FArea := DeviceArea;
  SetLength(FPixels, Int64(DeviceArea.Width) * DeviceArea.Height);
end;

function TPdfGouraudShadingContext.TryGetColorAt(const U, V: Single; out Rgb: Integer): Boolean;
begin
  raise ENotSupportedException.Create('A mesh shading is read by pixel, not by the point of the shading');
end;

function TPdfGouraudShadingContext.TryGetPixel(const X, Y: Integer; out Rgb: Integer): Boolean;
begin
  Rgb := 0;
  const IsInArea = ((X >= FArea.Left) and (X < FArea.Right) and (Y >= FArea.Top) and (Y < FArea.Bottom));
  if IsInArea then
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

function TPdfGouraudShadingContext.TryAddElement(const TriangleCount: Integer): Boolean;
begin
  Result := ((FElementCount < MaxMeshElements) and ((FTriangleCount + TriangleCount) <= MaxMeshTriangles));
  if Result then
  begin
    Inc(FElementCount);
    Inc(FTriangleCount, TriangleCount);
    Exit;
  end;

  if not FIsLimitReported then
  begin
    FIsLimitReported := True;
    Shading.Warn('The mesh shading exceeds the limit of %d triangles or patches (or %d triangles); the rest is skipped', [MaxMeshElements, MaxMeshTriangles]);
  end;
end;

procedure TPdfGouraudShadingContext.PlotPixel(const X, Y: Integer; const Color: TArray<Single>);
begin
  const IsInArea = ((X >= FArea.Left) and (X < FArea.Right) and (Y >= FArea.Top) and (Y < FArea.Bottom));
  if not IsInArea then
  begin
    Exit;
  end;

  var Values := Color;
  if Shading.HasFunction then
  begin
    Values := Shading.EvalFunction(Values);
  end;
  FPixels[(Y - FArea.Top) * FArea.Width + (X - FArea.Left)] := (ConvertToRgb(Values) or Painted);
end;

procedure TPdfGouraudShadingContext.DrawTriangle(const Triangle: TPdfShadedTriangle);
begin
  case Triangle.Degree of
    1: PlotPoint(Triangle);
    2: PlotLine(Triangle);
  else
    FillTriangle(Triangle);
  end;
end;

procedure TPdfGouraudShadingContext.PlotPoint(const Triangle: TPdfShadedTriangle);
begin
  const Corner = Triangle.Corner(0);
  PlotPixel(Floor(Corner.X + 0.5), Floor(Corner.Y + 0.5), Corner.Color);
end;

// Line.calcColor: the colour follows x, or y for a vertical line
class function TPdfGouraudShadingContext.LineParameter(const Start, Finish: Integer; const Current: Integer): Single;
begin
  Result := (Current - Start) / (Finish - Start);
end;

procedure TPdfGouraudShadingContext.PlotLine(const Triangle: TPdfShadedTriangle);
begin
  const Start = Triangle.LineStart;
  const Finish = Triangle.LineEnd;
  const StartX = Floor(Start.X + 0.5);
  const StartY = Floor(Start.Y + 0.5);
  const FinishX = Floor(Finish.X + 0.5);
  const FinishY = Floor(Finish.Y + 0.5);
  const StepCount = Max(Abs(FinishX - StartX), Abs(FinishY - StartY));
  const IsVertical = (StartX = FinishX);
  for var Step := 0 to StepCount do
  begin
    const X = StartX + Floor((FinishX - StartX) * Step / StepCount + 0.5);
    const Y = StartY + Floor((FinishY - StartY) * Step / StepCount + 0.5);
    const Parameter = IfThen(IsVertical, LineParameter(StartY, FinishY, Y), LineParameter(StartX, FinishX, X));
    var Color: TArray<Single>;
    SetLength(Color, Length(Start.Color));
    for var Index := 0 to High(Color) do
    begin
      Color[Index] := (Start.Color[Index] * (1 - Parameter) + Finish.Color[Index] * Parameter);
    end;
    PlotPixel(X, Y, Color);
  end;
end;

procedure TPdfGouraudShadingContext.FillTriangle(const Triangle: TPdfShadedTriangle);
begin
  const Left = Max(Triangle.BoundaryLeft, FArea.Left);
  const Right = Min(Triangle.BoundaryRight, FArea.Right - 1);
  const Top = Max(Triangle.BoundaryTop, FArea.Top);
  const Bottom = Min(Triangle.BoundaryBottom, FArea.Bottom - 1);
  for var X := Left to Right do
  begin
    for var Y := Top to Bottom do
    begin
      if Triangle.Contains(X, Y) then
      begin
        PlotPixel(X, Y, Triangle.CalcColor(X, Y));
      end;
    end;
  end;
end;

{ TPdfType4ShadingContext }

constructor TPdfType4ShadingContext.Create(const Shading: TPDShadingMesh; const ShadingToDevice: TPdfMatrix; const DeviceArea: TRect);
begin
  inherited InitializeMesh(Shading, ShadingToDevice, DeviceArea);
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
  while not FReader.IsAtEnd do
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

constructor TPdfType5ShadingContext.Create(const Shading: TPDShadingMesh; const ShadingToDevice: TPdfMatrix; const DeviceArea: TRect);
begin
  inherited InitializeMesh(Shading, ShadingToDevice, DeviceArea);
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

  var Upper, Lower: TArray<TPdfMeshVertex>;
  if not TryReadRow(VerticesPerRow, Upper) then
  begin
    Exit;
  end;

  while TryReadRow(VerticesPerRow, Lower) do
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
