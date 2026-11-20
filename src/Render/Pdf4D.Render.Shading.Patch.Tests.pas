// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of the patch mesh shadings (types 6 and 7), PDFBox 3.0.8: Type6ShadingContext, Type7ShadingContext, PatchMeshesShadingContext,
// CoonsPatch, TensorPatch
unit Pdf4D.Render.Shading.Patch.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Math,
  System.Types,
  DUnitX.TestFramework,
  Pdf4D.Common.Matrix,
  Pdf4D.Graphics.Shading,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Shading.Context,
  Pdf4D.Render.Shading.Patch,
  Pdf4D.Tests.ShadingBuilder;

type
  [TestFixture]
  TPatchShadingTests = class
  private
    const Red: array[0..2] of Byte = (255, 0, 0);
    const Green: array[0..2] of Byte = (0, 255, 0);
    const Blue: array[0..2] of Byte = (0, 0, 255);
    const Yellow: array[0..2] of Byte = (255, 255, 0);
    const MeshEntries = '/ColorSpace /DeviceRGB /BitsPerCoordinate 8 /BitsPerComponent 8 /BitsPerFlag 8 /Decode [0 255 0 255 0 1 0 1 0 1]';
    // The data of the cells S6 and S7 of generated/render/shadings.pdf: coordinates of 16 bits that map 0..65535 to 0..100
    const WideEntries = '/ColorSpace /DeviceRGB /BitsPerCoordinate 16 /BitsPerComponent 8 /BitsPerFlag 8 /Decode [0 100 0 100 0 1 0 1 0 1]';
    // The square (10, 10) to (90, 90) with straight sides: the points run from the lower left corner up the left side, along the top and
    // down the right side
    const SquareOutline: array[0..11, 0..1] of Byte = ((10, 10), (10, 37), (10, 63), (10, 90), (37, 90), (63, 90), (90, 90), (90, 63),
                                                       (90, 37), (90, 10), (63, 10), (37, 10));

  private
    FDocument: TShadingTestDocument;
    FShading: TPDShading;
    FBitmap: TPdfBitmap;

    procedure Make(const ShadingEntries: string; const Data: TBytes);
    procedure RasterizeSquare(const Size: Integer);
    procedure AssertPixel(const X, Y, Red, Green, Blue, Tolerance: Integer);
    procedure AssertPainted(const X, Y: Integer);
    procedure AssertTransparent(const X, Y: Integer);
    class function SquarePatch: TMeshData; static;
    // The data of two patches that are not padded to whole bytes: flags of 2 bits and colours of 4 bits
    class function UnpaddedPatches: TBytes; static;
    class function SquareTensorPoints(const InnerX, InnerY: Double): TArray<TPdfPatchPoint>; static;
    class function PatchColors: TPdfPatchColors; static;
    class function WidePatch(const WithInnerPoints: Boolean): TBytes; static;
    class function HugePatchStrip(const PatchCount: Integer): TBytes; static;

  public
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestCoonsPatchCorners;

    [Test]
    procedure TestTensorPatchMatchesReference;

    [Test]
    procedure TestCoonsPatchMatchesReferenceOutline;

    [Test]
    procedure TestEdgeFlagsReuseVertices;

    [Test]
    procedure TestTruncatedMeshDataStops;

    [Test]
    procedure TestHugePatchCountIsBounded;

    [Test]
    procedure TestCoonsPatchWithCurvedSidesFollowsTheCurve;

    [Test]
    procedure TestPatchWithoutDataPaintsNothingAndWarns;

    [Test]
    procedure TestPatchDataIsNotPaddedToWholeBytes;

    [Test]
    procedure TestTensorPatchWithStraightSidesAndInnerPointsInsideHasFewCells;

    [Test]
    procedure TestTensorPatchWithAnInnerPointOutsideKeepsTheHighestLevel;
  end;

implementation

uses
  System.Classes,
  Pdf4D.Render.Shading.Triangle;

const
  // The pixels of the reference (PDFBox) for the cell S7 of shadings.pdf, page 1: the cell lies at x 265, y 280 (device pixels)
  // More patches than the triangles of one shading allow: a patch with curved sides has 512 triangles
  HugePatchCount = MaxMeshTriangles div 100;
  ReferenceCellLeft = 265;
  ReferenceCellBottom = 380;
  // x, y and the colour of a pixel
  ReferencePixels: array[0..7, 0..4] of Integer = ((290, 305, 56, 169, 43), (305, 305, 50, 146, 78), (335, 305, 40, 90, 154), (350, 305, 45, 66, 184),
                                                   (275, 365, 233, 34, 0), (305, 365, 246, 101, 3), (335, 365, 229, 174, 17), (350, 365, 225, 204, 25));
  CurvedOutline: array[0..11, 0..1] of Byte = ((10, 10), (10, 37), (10, 63), (10, 90), (37, 100), (63, 100), (90, 90), (90, 63), (90, 37),
                                               (90, 10), (63, 10), (37, 10));

{ TPatchShadingTests }

procedure TPatchShadingTests.TearDown;
begin
  FreeAndNil(FBitmap);
  FreeAndNil(FShading);
  FreeAndNil(FDocument);
end;

procedure TPatchShadingTests.Make(const ShadingEntries: string; const Data: TBytes);
begin
  FDocument := TShadingTestDocument.CreateMesh(ShadingEntries, Data);
  FShading := FDocument.NewShading;
end;

procedure TPatchShadingTests.RasterizeSquare(const Size: Integer);
begin
  FBitmap := TPdfShadingRasterizer.Rasterize(FShading, TPdfMatrix.Identity, TRect.Create(0, 0, Size, Size), nil);
end;

procedure TPatchShadingTests.AssertPixel(const X, Y, Red, Green, Blue, Tolerance: Integer);
begin
  const Pixel = TShadingPixels.At(FBitmap, X, Y);
  const Description = Format('pixel (%d, %d) is %s', [X, Y, TShadingPixels.Describe(Pixel)]);
  Assert.IsTrue(TShadingPixels.AreNear(Pixel, Red, Green, Blue, 255, Tolerance), Description);
end;

procedure TPatchShadingTests.AssertPainted(const X, Y: Integer);
begin
  Assert.AreEqual<Integer>(255, TShadingPixels.At(FBitmap, X, Y).A, Format('pixel (%d, %d) is painted', [X, Y]));
end;

procedure TPatchShadingTests.AssertTransparent(const X, Y: Integer);
begin
  Assert.AreEqual<Integer>(0, TShadingPixels.At(FBitmap, X, Y).A, Format('pixel (%d, %d) is transparent', [X, Y]));
end;

// Flag 0, the outline of the square and the colours red (lower left), green (upper left), blue (upper right) and yellow (lower right)
class function TPatchShadingTests.SquarePatch: TMeshData;
begin
  Result.AddByte(0);
  for var Index := 0 to 11 do
  begin
    Result.AddPoint(SquareOutline[Index, 0], SquareOutline[Index, 1]);
  end;
  Result.AddColor(Red);
  Result.AddColor(Green);
  Result.AddColor(Blue);
  Result.AddColor(Yellow);
end;

// The patch of the cells S6 (12 points) and S7 (16 points) of the reference
class function TPatchShadingTests.WidePatch(const WithInnerPoints: Boolean): TBytes;
const
  Scale = 65535 div 100;
  Outline: array[0..11, 0..1] of Integer = ((5, 5), (5, 35), (5, 65), (5, 95), (35, 99), (65, 75), (95, 95), (95, 65), (95, 35), (95, 5),
                                            (65, 1), (35, 25));
  Inner: array[0..3, 0..1] of Integer = ((33, 33), (33, 66), (66, 66), (66, 33));
begin
  var Data: TMeshData;
  Data.AddByte(0);
  for var Index := 0 to 11 do
  begin
    Data.AddWord(Outline[Index, 0] * Scale);
    Data.AddWord(Outline[Index, 1] * Scale);
  end;
  if WithInnerPoints then
  begin
    for var Index := 0 to 3 do
    begin
      Data.AddWord(Inner[Index, 0] * Scale);
      Data.AddWord(Inner[Index, 1] * Scale);
    end;
  end;
  Data.AddColor(Red);
  Data.AddColor(Green);
  Data.AddColor(Blue);
  Data.AddColor(Yellow);
  Result := Data.Bytes;
end;

// A patch with flag 1 for each of PatchCount - 1, so that a patch costs 23 bytes. The last 20 patches lie near (85, 85), the others in the
// corner (10, 10).
class function TPatchShadingTests.HugePatchStrip(const PatchCount: Integer): TBytes;
const
  FirstPatchBytes = 37;
  NextPatchBytes = 23;
begin
  SetLength(Result, FirstPatchBytes + (PatchCount - 1) * NextPatchBytes);
  for var Index := 0 to PatchCount - 1 do
  begin
    const IsFirst = (Index = 0);
    const Start = IfThen(IsFirst, 0, FirstPatchBytes + (Index - 1) * NextPatchBytes);
    const Base = IfThen(Index >= HugePatchCount - 20, 85, 10);
    Result[Start] := IfThen(IsFirst, 0, 1);
    const PointCount = IfThen(IsFirst, 12, 8);
    for var PointIndex := 0 to PointCount - 1 do
    begin
      Result[Start + 1 + PointIndex * 2] := Base + ((PointIndex + Index) mod 4);
      Result[Start + 2 + PointIndex * 2] := Base + ((PointIndex * 3 + Index) mod 4);
    end;
    // Colour values 7 each; the bytes of the colours are not zero, which a flag read after them would show as a bad flag
    const ColorStart = Start + 1 + PointCount * 2;
    const ColorCount = IfThen(IsFirst, 12, 6);
    for var ColorIndex := 0 to ColorCount - 1 do
    begin
      Result[ColorStart + ColorIndex] := 7;
    end;
  end;
end;

// A patch of the type 6 with the flag 0: the sides of the rectangle from x0 to x1 and y 10 to 90, and four colours. Every value is written with
// the number of bits it has in the shading: flag 2, coordinate 8 and colour 4.
class function TPatchShadingTests.UnpaddedPatches: TBytes;
const
  SideY: array[0..3] of Integer = (10, 37, 63, 90);
var
  Bits: TBits;
  Count: Integer;

  procedure Add(const Value, BitCount: Integer);
  begin
    for var Position := BitCount - 1 downto 0 do
    begin
      Bits.Size := Count + 1;
      Bits[Count] := (((Value shr Position) and 1) = 1);
      Inc(Count);
    end;
  end;

  procedure AddPatch(const Left, Right: Integer);
  begin
    const Third = (Right - Left) div 3;
    Add(0, 2);
    // From the lower left corner up the left side, along the top, down the right side and back along the bottom
    for var Index := 0 to 3 do
    begin
      Add(Left, 8);
      Add(SideY[Index], 8);
    end;
    for var Index := 1 to 3 do
    begin
      Add(Left + Index * Third, 8);
      Add(90, 8);
    end;
    for var Index := 2 downto 0 do
    begin
      Add(Right, 8);
      Add(SideY[Index], 8);
    end;
    for var Index := 2 downto 1 do
    begin
      Add(Left + Index * Third, 8);
      Add(10, 8);
    end;
    for var Corner := 0 to 3 do
    begin
      Add(IfThen(Corner = 0, 15, 0), 4);
      Add(IfThen(Corner = 1, 15, 0), 4);
      Add(IfThen(Corner >= 2, 15, 0), 4);
    end;
  end;

begin
  Bits := TBits.Create;
  try
    Count := 0;
    AddPatch(5, 41);
    AddPatch(59, 95);
    SetLength(Result, (Count + 7) div 8);
    for var Position := 0 to Count - 1 do
    begin
      if Bits[Position] then
      begin
        Result[Position div 8] := Result[Position div 8] or (128 shr (Position mod 8));
      end;
    end;
  finally
    Bits.Free;
  end;
end;

// readPatch of PDFBox reads no padding after a patch: the second patch starts right after the colours of the first, here 2 bits after a byte
procedure TPatchShadingTests.TestPatchDataIsNotPaddedToWholeBytes;
begin
  Make('/ShadingType 6 /ColorSpace /DeviceRGB /BitsPerCoordinate 8 /BitsPerComponent 4 /BitsPerFlag 2 /Decode [0 255 0 255 0 1 0 1 0 1]', UnpaddedPatches);

  RasterizeSquare(100);

  AssertPainted(20, 50);
  AssertPainted(77, 50);
  AssertTransparent(50, 50);
end;

// 16 points in the order of the data: the outline of the square from (10, 10) to (90, 90) with straight sides and the four inner points
class function TPatchShadingTests.SquareTensorPoints(const InnerX, InnerY: Double): TArray<TPdfPatchPoint>;
begin
  SetLength(Result, 16);
  for var Index := 0 to 11 do
  begin
    Result[Index] := TPdfPatchPoint.Create(SquareOutline[Index, 0], SquareOutline[Index, 1]);
  end;
  Result[12] := TPdfPatchPoint.Create(InnerX, InnerY);
  Result[13] := TPdfPatchPoint.Create(37, 63);
  Result[14] := TPdfPatchPoint.Create(63, 63);
  Result[15] := TPdfPatchPoint.Create(63, 37);
end;

class function TPatchShadingTests.PatchColors: TPdfPatchColors;
begin
  Result[0] := [1, 0, 0];
  Result[1] := [0, 1, 0];
  Result[2] := [0, 0, 1];
  Result[3] := [1, 1, 0];
end;

// TensorPatch.calcLevel: straight sides of 80 pixels that no inner point leaves are cut into 2 x 2 cells, two triangles each
procedure TPatchShadingTests.TestTensorPatchWithStraightSidesAndInnerPointsInsideHasFewCells;
begin
  const Patch = TPdfTensorPatch.Create(SquareTensorPoints(37, 37), PatchColors);
  try
    Assert.AreEqual<Integer>(8, Length(Patch.Triangles));
  finally
    Patch.Free;
  end;
end;

// An inner point at (130, 130) lies on the same side of both sides at x = 10 and x = 90 and of both at y = 10 and y = 90, so the patch
// bulges out of them and is cut into the 16 x 16 cells of the highest level
procedure TPatchShadingTests.TestTensorPatchWithAnInnerPointOutsideKeepsTheHighestLevel;
begin
  const Patch = TPdfTensorPatch.Create(SquareTensorPoints(130, 130), PatchColors);
  try
    Assert.AreEqual<Integer>(512, Length(Patch.Triangles));
  finally
    Patch.Free;
  end;
end;

procedure TPatchShadingTests.TestCoonsPatchCorners;
begin
  Make('/ShadingType 6 ' + MeshEntries, SquarePatch.Bytes);

  RasterizeSquare(100);

  AssertPixel(10, 10, 255, 0, 0, 2);
  AssertPixel(10, 90, 0, 255, 0, 2);
  AssertPixel(90, 90, 0, 0, 255, 2);
  AssertPixel(90, 10, 255, 255, 0, 2);
  AssertPixel(50, 50, 127, 127, 63, 3);
  AssertTransparent(5, 50);
  AssertTransparent(95, 50);
end;

// The values are the pixels that PDFBox renders in the reference of shadings.pdf (cell S7, page 1) in the rows 305 and 365 of the page,
// away from the columns that PDFBox paints with other colours
procedure TPatchShadingTests.TestTensorPatchMatchesReference;
begin
  Make('/ShadingType 7 ' + WideEntries, WidePatch(True));
  const ShadingToDevice = TPdfMatrix.Create(1, 0, 0, -1, ReferenceCellLeft, ReferenceCellBottom);

  FBitmap := TPdfShadingRasterizer.Rasterize(FShading, ShadingToDevice, TRect.Create(260, 270, 370, 390), nil);

  for var Index := 0 to High(ReferencePixels) do
  begin
    const Reference = ReferencePixels[Index];
    const Pixel = TShadingPixels.At(FBitmap, Reference[0] - 260, Reference[1] - 270);
    const Description = Format('pixel (%d, %d) is %s', [Reference[0], Reference[1], TShadingPixels.Describe(Pixel)]);
    Assert.IsTrue(TShadingPixels.AreNear(Pixel, Reference[2], Reference[3], Reference[4], 255, 6), Description);
  end;
end;

procedure TPatchShadingTests.TestCoonsPatchMatchesReferenceOutline;
begin
  Make('/ShadingType 6 ' + WideEntries, WidePatch(False));
  const ShadingToDevice = TPdfMatrix.Create(1, 0, 0, -1, ReferenceCellLeft, ReferenceCellBottom);

  FBitmap := TPdfShadingRasterizer.Rasterize(FShading, ShadingToDevice, TRect.Create(260, 270, 370, 390), nil);

  // Just inside the corners of the outline the colours are those of the corners
  const LowerLeft = TShadingPixels.At(FBitmap, ReferenceCellLeft + 7 - 260, ReferenceCellBottom - 7 - 270);
  Assert.IsTrue(TShadingPixels.AreNear(LowerLeft, 255, 0, 0, 255, 40), TShadingPixels.Describe(LowerLeft));
  const UpperRight = TShadingPixels.At(FBitmap, ReferenceCellLeft + 93 - 260, ReferenceCellBottom - 93 - 270);
  Assert.IsTrue(TShadingPixels.AreNear(UpperRight, 0, 0, 255, 255, 40), TShadingPixels.Describe(UpperRight));
end;

procedure TPatchShadingTests.TestEdgeFlagsReuseVertices;
begin
  var Data := SquarePatch;
  // Flag 1: the new patch starts on the upper side of the first (the points 3 to 6), which has the colours green and blue
  Data.AddByte(1);
  Data.AddPoint(90, 117);
  Data.AddPoint(90, 143);
  Data.AddPoint(90, 170);
  Data.AddPoint(63, 170);
  Data.AddPoint(37, 170);
  Data.AddPoint(10, 170);
  Data.AddPoint(10, 143);
  Data.AddPoint(10, 117);
  Data.AddColor(Yellow);
  Data.AddColor(Red);
  Make('/ShadingType 6 ' + MeshEntries, Data.Bytes);

  RasterizeSquare(200);

  AssertPixel(10, 90, 0, 255, 0, 2);
  AssertPixel(90, 90, 0, 0, 255, 2);
  AssertPixel(90, 170, 255, 255, 0, 2);
  AssertPixel(10, 170, 255, 0, 0, 2);
  AssertPainted(30, 140);
end;

procedure TPatchShadingTests.TestTruncatedMeshDataStops;
begin
  var Data := SquarePatch;
  Data.AddByte(1);
  Data.AddPoint(90, 117);
  Data.AddPoint(90, 143);
  Make('/ShadingType 6 ' + MeshEntries, Data.Bytes);

  RasterizeSquare(200);

  AssertPixel(10, 10, 255, 0, 0, 2);
  AssertTransparent(50, 140);
  Assert.AreEqual<Integer>(1, FDocument.CountLogLines('ends in the middle of'), 'one warning');
end;

procedure TPatchShadingTests.TestHugePatchCountIsBounded;
begin
  Make('/ShadingType 6 ' + MeshEntries, HugePatchStrip(HugePatchCount));

  RasterizeSquare(100);

  AssertTransparent(88, 88);
  Assert.AreEqual<Integer>(1, FDocument.CountLogLines('limit'), 'one warning');
end;

procedure TPatchShadingTests.TestCoonsPatchWithCurvedSidesFollowsTheCurve;
begin
  var Data: TMeshData;
  Data.AddByte(0);
  // The upper side bulges up to y = 97.5 in the middle; the lower side stays at y = 10
  for var Index := 0 to 11 do
  begin
    Data.AddPoint(CurvedOutline[Index, 0], CurvedOutline[Index, 1]);
  end;
  Data.AddColor(Red);
  Data.AddColor(Green);
  Data.AddColor(Blue);
  Data.AddColor(Yellow);
  Make('/ShadingType 6 ' + MeshEntries, Data.Bytes);

  RasterizeSquare(100);

  AssertPainted(50, 96);
  AssertTransparent(50, 99);
  AssertTransparent(12, 95);
end;

procedure TPatchShadingTests.TestPatchWithoutDataPaintsNothingAndWarns;
begin
  FDocument := TShadingTestDocument.Create('/ShadingType 7 /ColorSpace /DeviceRGB /BitsPerCoordinate 8 /BitsPerComponent 8 /BitsPerFlag 8');
  FShading := FDocument.NewShading;

  RasterizeSquare(100);

  AssertTransparent(50, 50);
  Assert.IsTrue(FDocument.HasLogLine('no data'));
end;

end.
