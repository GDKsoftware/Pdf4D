// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of the triangle mesh shadings (types 4 and 5), PDFBox 3.0.8: Type4ShadingContext, Type5ShadingContext, GouraudShadingContext
unit Pdf4D.Render.Shading.Triangle.Tests;

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
  Pdf4D.Render.Renderer.Interfaces,
  Pdf4D.Render.Shading.Context,
  Pdf4D.Tests.ShadingBuilder;

type
  // Says no for the first asks and yes after them, and counts the asks
  TCancelAfterToken = class(TInterfacedObject, IPdfCancelToken)
  private
    FAllowed: Integer;
    FAsked: Integer;

  public
    constructor Create(const Allowed: Integer);

    function IsCancelled: Boolean;

    property Asked: Integer read FAsked;
  end;

  [TestFixture]
  TTriangleShadingTests = class
  private
    const Red: array[0..2] of Byte = (255, 0, 0);
    const Green: array[0..2] of Byte = (0, 255, 0);
    const Blue: array[0..2] of Byte = (0, 0, 255);
    const Yellow: array[0..2] of Byte = (255, 255, 0);
    // The vertices are bytes of 0 to 255 in the shading space
    const MeshEntries = '/ColorSpace /DeviceRGB /BitsPerCoordinate 8 /BitsPerComponent 8 /Decode [0 255 0 255 0 1 0 1 0 1]';

  private
    FDocument: TShadingTestDocument;
    FShading: TPDShading;
    FBitmap: TPdfBitmap;

    procedure Make(const ShadingEntries: string; const Data: TBytes);
    procedure MakeFreeForm(const Data: TBytes);
    procedure RasterizeHundred;
    procedure AssertPixel(const X, Y, Red, Green, Blue, Tolerance: Integer);
    procedure AssertTransparent(const X, Y: Integer);
    procedure AssertPainted(const X, Y: Integer);
    class function OneTriangle: TMeshData; static;
    class function HugeStrip(const TriangleCount: Integer): TBytes; static;

  public
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestFreeFormTriangleGouraud;

    [Test]
    procedure TestLatticeForm;

    [Test]
    procedure TestEdgeFlagsReuseVertices;

    [Test]
    procedure TestEdgeFlagTwoReusesTheFirstAndLastCorner;

    [Test]
    procedure TestTruncatedMeshDataStops;

    [Test]
    procedure TestHugeTriangleCountIsBounded;

    [Test]
    procedure TestFunctionGivesTheColourOfTheParameter;

    [Test]
    procedure TestMeshWithoutStreamPaintsNothingAndWarns;

    [Test]
    procedure TestInvalidBitsPerCoordinatePaintsNothingAndWarns;

    [Test]
    procedure TestVertexOutsideTheAreaIsClipped;

    [Test]
    procedure TestDegenerateTrianglesPaintAPointAndALine;

    [Test]
    procedure TestThinTriangleIsFattenedByItsSides;

    [Test]
    procedure TestCornersThatDifferByAThousandthAreATriangleNotAPoint;

    [Test]
    procedure TestLatticeRowLongerThanTheDataPaintsNothingAndWarns;

    [Test]
    procedure TestCancelledTokenStopsTheMeshBeforeItIsPainted;

    [Test]
    procedure TestLineBetweenFarApartCornersIsBounded;

    [Test]
    procedure TestCornersFarBeyondTheDeviceRaiseNothing;
  end;

implementation

uses
  Pdf4D.Render.Shading.Triangle;

{ TCancelAfterToken }

constructor TCancelAfterToken.Create(const Allowed: Integer);
begin
  inherited Create;
  FAllowed := Allowed;
end;

function TCancelAfterToken.IsCancelled: Boolean;
begin
  Inc(FAsked);
  Result := (FAsked > FAllowed);
end;

{ TTriangleShadingTests }

procedure TTriangleShadingTests.TearDown;
begin
  FreeAndNil(FBitmap);
  FreeAndNil(FShading);
  FreeAndNil(FDocument);
end;

procedure TTriangleShadingTests.Make(const ShadingEntries: string; const Data: TBytes);
begin
  FDocument := TShadingTestDocument.CreateMesh(ShadingEntries, Data);
  FShading := FDocument.NewShading;
end;

procedure TTriangleShadingTests.MakeFreeForm(const Data: TBytes);
begin
  Make('/ShadingType 4 /BitsPerFlag 8 ' + MeshEntries, Data);
end;

procedure TTriangleShadingTests.RasterizeHundred;
begin
  FBitmap := TPdfShadingRasterizer.Rasterize(FShading, TPdfMatrix.Identity, TRect.Create(0, 0, 100, 100), nil);
end;

procedure TTriangleShadingTests.AssertPixel(const X, Y, Red, Green, Blue, Tolerance: Integer);
begin
  const Pixel = TShadingPixels.At(FBitmap, X, Y);
  const Description = Format('pixel (%d, %d) is %s', [X, Y, TShadingPixels.Describe(Pixel)]);
  Assert.IsTrue(TShadingPixels.AreNear(Pixel, Red, Green, Blue, 255, Tolerance), Description);
end;

procedure TTriangleShadingTests.AssertPainted(const X, Y: Integer);
begin
  Assert.AreEqual<Integer>(255, TShadingPixels.At(FBitmap, X, Y).A, Format('pixel (%d, %d) is painted', [X, Y]));
end;

procedure TTriangleShadingTests.AssertTransparent(const X, Y: Integer);
begin
  Assert.AreEqual<Integer>(0, TShadingPixels.At(FBitmap, X, Y).A, Format('pixel (%d, %d) is transparent', [X, Y]));
end;

class function TTriangleShadingTests.OneTriangle: TMeshData;
begin
  Result.AddVertex(0, 10, 10, Red);
  Result.AddVertex(0, 90, 10, Green);
  Result.AddVertex(0, 10, 90, Blue);
end;

// One triangle for each vertex after the first two. The triangles up to the limit lie in the corner (10, 10), the triangles beyond
// the limit near (85, 85).
class function TTriangleShadingTests.HugeStrip(const TriangleCount: Integer): TBytes;
const
  VertexBytes = 6;
begin
  SetLength(Result, (TriangleCount + 2) * VertexBytes);
  for var Index := 0 to TriangleCount + 1 do
  begin
    const IsBeyondLimit = ((Index - 2) >= MaxMeshElements);
    const Base = IfThen(IsBeyondLimit, 85, 10);
    const Start = Index * VertexBytes;
    Result[Start] := IfThen(Index < 3, 0, 1);
    Result[Start + 1] := Base + (Index mod 3);
    Result[Start + 2] := Base + ((Index + 1) mod 3);
    Result[Start + 3] := 200;
    Result[Start + 4] := 0;
    Result[Start + 5] := 0;
  end;
end;

procedure TTriangleShadingTests.TestFreeFormTriangleGouraud;
begin
  MakeFreeForm(OneTriangle.Bytes);

  RasterizeHundred;

  AssertPixel(10, 10, 255, 0, 0, 2);
  AssertPixel(90, 10, 0, 255, 0, 2);
  AssertPixel(10, 90, 0, 0, 255, 2);
  AssertPixel(37, 37, 85, 85, 85, 3);
  AssertTransparent(80, 80);
  AssertTransparent(5, 5);
end;

procedure TTriangleShadingTests.TestLatticeForm;
begin
  var Data: TMeshData;
  Data.AddVertex(-1, 10, 10, Red);
  Data.AddVertex(-1, 90, 10, Green);
  Data.AddVertex(-1, 10, 90, Blue);
  Data.AddVertex(-1, 90, 90, Yellow);
  Make('/ShadingType 5 /VerticesPerRow 2 ' + MeshEntries, Data.Bytes);

  RasterizeHundred;

  AssertPixel(10, 10, 255, 0, 0, 2);
  AssertPixel(90, 10, 0, 255, 0, 2);
  AssertPixel(10, 90, 0, 0, 255, 2);
  AssertPixel(90, 90, 255, 255, 0, 2);
  AssertPixel(50, 50, 0, 127, 127, 3);
  AssertPixel(75, 75, 159, 207, 47, 3);
  AssertTransparent(5, 5);
end;

procedure TTriangleShadingTests.TestEdgeFlagsReuseVertices;
begin
  var Data := OneTriangle;
  Data.AddVertex(1, 90, 90, Yellow);
  MakeFreeForm(Data.Bytes);

  RasterizeHundred;

  AssertPixel(90, 90, 255, 255, 0, 2);
  AssertPixel(90, 10, 0, 255, 0, 2);
  AssertPixel(10, 90, 0, 0, 255, 2);
  AssertPainted(70, 70);
end;

procedure TTriangleShadingTests.TestEdgeFlagTwoReusesTheFirstAndLastCorner;
begin
  var Data := OneTriangle;
  Data.AddVertex(2, 90, 90, Yellow);
  MakeFreeForm(Data.Bytes);

  RasterizeHundred;

  // The second triangle is (10, 10), (10, 90), (90, 90): the corner (90, 10) is not part of it
  AssertPixel(90, 90, 255, 255, 0, 2);
  AssertPainted(25, 70);
  AssertTransparent(80, 30);
end;

procedure TTriangleShadingTests.TestTruncatedMeshDataStops;
begin
  var Data := OneTriangle;
  Data.AddVertex(1, 90, 90, Yellow);
  const WholeLength = Length(Data.Bytes);
  MakeFreeForm(Data.Truncated(WholeLength - 3));

  RasterizeHundred;

  AssertPixel(10, 10, 255, 0, 0, 2);
  AssertTransparent(90, 90);
  Assert.AreEqual<Integer>(1, FDocument.CountLogLines('ends in the middle of'), 'one warning');
end;

procedure TTriangleShadingTests.TestHugeTriangleCountIsBounded;
begin
  MakeFreeForm(HugeStrip(MaxMeshElements + 20));

  RasterizeHundred;

  AssertTransparent(88, 88);
  Assert.AreEqual<Integer>(1, FDocument.CountLogLines('limit'), 'one warning');
end;

procedure TTriangleShadingTests.TestFunctionGivesTheColourOfTheParameter;
begin
  var Data: TMeshData;
  Data.AddVertex(0, 10, 10, [0]);
  Data.AddVertex(0, 90, 10, [255]);
  Data.AddVertex(0, 10, 90, [255]);
  Make('/ShadingType 4 /ColorSpace /DeviceRGB /BitsPerCoordinate 8 /BitsPerComponent 8 /BitsPerFlag 8 /Decode [0 255 0 255 0 1] ' +
       '/Function << /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >>', Data.Bytes);

  RasterizeHundred;

  AssertPixel(10, 10, 255, 0, 0, 2);
  AssertPixel(90, 10, 0, 0, 255, 2);
end;

procedure TTriangleShadingTests.TestMeshWithoutStreamPaintsNothingAndWarns;
begin
  FDocument := TShadingTestDocument.Create('/ShadingType 4 /ColorSpace /DeviceRGB /BitsPerCoordinate 8 /BitsPerComponent 8 /BitsPerFlag 8');
  FShading := FDocument.NewShading;

  RasterizeHundred;

  AssertTransparent(50, 50);
  Assert.IsTrue(FDocument.HasLogLine('no data'));
end;

procedure TTriangleShadingTests.TestInvalidBitsPerCoordinatePaintsNothingAndWarns;
begin
  Make('/ShadingType 4 /ColorSpace /DeviceRGB /BitsPerCoordinate 0 /BitsPerComponent 8 /BitsPerFlag 8 /Decode [0 255 0 255 0 1 0 1 0 1]',
       OneTriangle.Bytes);

  RasterizeHundred;

  AssertTransparent(30, 30);
  Assert.IsTrue(FDocument.HasLogLine('BitsPerCoordinate'));
end;

procedure TTriangleShadingTests.TestVertexOutsideTheAreaIsClipped;
begin
  var Data: TMeshData;
  Data.AddVertex(0, 10, 10, Red);
  Data.AddVertex(0, 250, 10, Green);
  Data.AddVertex(0, 10, 250, Blue);
  MakeFreeForm(Data.Bytes);

  RasterizeHundred;

  AssertPixel(10, 10, 255, 0, 0, 2);
  AssertPainted(99, 99);
  AssertTransparent(5, 99);
end;

procedure TTriangleShadingTests.TestDegenerateTrianglesPaintAPointAndALine;
begin
  var Data: TMeshData;
  Data.AddVertex(0, 20, 20, Red);
  Data.AddVertex(0, 20, 20, Red);
  Data.AddVertex(0, 20, 20, Red);
  Data.AddVertex(0, 40, 60, Green);
  Data.AddVertex(0, 80, 60, Blue);
  Data.AddVertex(0, 60, 60, Yellow);
  MakeFreeForm(Data.Bytes);

  RasterizeHundred;

  AssertPixel(20, 20, 255, 0, 0, 2);
  AssertPixel(40, 60, 0, 255, 0, 2);
  AssertPixel(80, 60, 0, 0, 255, 2);
  AssertTransparent(60, 40);
end;

// calcPixelTable draws the three sides of a triangle with Bresenham's algorithm after it has filled it: a triangle that is thinner than a pixel
// and holds no pixel centre is still visible. The corners (10, 10.4), (90, 10.4) and (50, 10.7) round to the pixels (10, 10), (90, 10) and
// (50, 11); no pixel lies inside.
procedure TTriangleShadingTests.TestThinTriangleIsFattenedByItsSides;
begin
  var Data: TMeshData;
  Data.AddVertex(0, 10, 104, Red);
  Data.AddVertex(0, 90, 104, Green);
  Data.AddVertex(0, 50, 107, Blue);
  Make('/ShadingType 4 /BitsPerFlag 8 /ColorSpace /DeviceRGB /BitsPerCoordinate 8 /BitsPerComponent 8 /Decode [0 255 0 25.5 0 1 0 1 0 1]', Data.Bytes);

  RasterizeHundred;

  AssertPixel(10, 10, 255, 0, 0, 2);
  AssertPixel(90, 10, 0, 255, 0, 2);
  AssertPixel(50, 10, 128, 127, 0, 3);
  AssertPainted(30, 10);
  AssertPainted(50, 11);
  AssertTransparent(50, 20);
end;

// calcDeg counts the corners that differ by 1/1000 or more, not the pixels they round to: these corners are a triangle, whose sides end on the
// same pixel. The last side that is drawn gives the pixel the colour of the third corner.
procedure TTriangleShadingTests.TestCornersThatDifferByAThousandthAreATriangleNotAPoint;
begin
  var Data: TMeshData;
  Data.AddVertex(0, 200, 200, Red);
  Data.AddVertex(0, 202, 200, Green);
  Data.AddVertex(0, 200, 203, Blue);
  Make('/ShadingType 4 /BitsPerFlag 8 /ColorSpace /DeviceRGB /BitsPerCoordinate 8 /BitsPerComponent 8 /Decode [0 25.5 0 25.5 0 1 0 1 0 1]', Data.Bytes);

  RasterizeHundred;

  AssertPixel(20, 20, 0, 0, 255, 2);
  AssertTransparent(21, 20);
end;

// A /VerticesPerRow that two rows of the data cannot hold is not allocated: nothing is painted and the warning says why
procedure TTriangleShadingTests.TestLatticeRowLongerThanTheDataPaintsNothingAndWarns;
begin
  var Data: TMeshData;
  Data.AddVertex(-1, 10, 10, Red);
  Data.AddVertex(-1, 90, 10, Green);
  Data.AddVertex(-1, 10, 90, Blue);
  Data.AddVertex(-1, 90, 90, Yellow);
  Make('/ShadingType 5 /VerticesPerRow 50000000 ' + MeshEntries, Data.Bytes);

  RasterizeHundred;

  AssertTransparent(50, 50);
  Assert.IsTrue(FDocument.HasLogLine('VerticesPerRow'));
end;

// A token that cancels after a few asks stops the triangles while they are made, so that nothing of them is painted
procedure TTriangleShadingTests.TestCancelledTokenStopsTheMeshBeforeItIsPainted;
begin
  var Data: TMeshData;
  for var Index := 1 to 200 do
  begin
    Data.AddVertex(0, 0, 0, Red);
    Data.AddVertex(0, 250, 0, Green);
    Data.AddVertex(0, 0, 250, Blue);
  end;
  MakeFreeForm(Data.Bytes);
  const Token = TCancelAfterToken.Create(2);
  const TokenReference: IPdfCancelToken = Token;

  FBitmap := TPdfShadingRasterizer.Rasterize(FShading, TPdfMatrix.Identity, TRect.Create(0, 0, 100, 100), TokenReference);

  AssertTransparent(10, 0);
  AssertTransparent(10, 5);
  Assert.IsTrue(Token.Asked >= 3, 'the token is asked while the mesh is made');
end;

// Two corners 2 * 10^9 pixels apart: the line between them has no more steps than the limit of the work allows, and nothing runs for long
procedure TTriangleShadingTests.TestLineBetweenFarApartCornersIsBounded;
begin
  var Data: TMeshData;
  Data.AddVertex(0, 0, 0, Red);
  Data.AddVertex(0, 255, 255, Green);
  Data.AddVertex(0, 255, 255, Green);
  Make('/ShadingType 4 /BitsPerFlag 8 /ColorSpace /DeviceRGB /BitsPerCoordinate 8 /BitsPerComponent 8 /Decode [-1000000000 1000000000 -1000000000 1000000000 0 1 0 1 0 1]',
       Data.Bytes);

  RasterizeHundred;

  AssertTransparent(50, 50);
  Assert.AreEqual<Integer>(1, FDocument.CountLogLines('work limit'), 'one warning');
end;

// Corners of 10^37 pixels away are far beyond any device: they are limited and the conversion to whole pixels cannot overflow
procedure TTriangleShadingTests.TestCornersFarBeyondTheDeviceRaiseNothing;
begin
  Make('/ShadingType 4 /BitsPerFlag 8 /ColorSpace /DeviceRGB /BitsPerCoordinate 8 /BitsPerComponent 8 /Decode [-1e38 1e38 -1e38 1e38 0 1 0 1 0 1]',
       OneTriangle.Bytes);

  RasterizeHundred;

  Assert.AreEqual<Integer>(100, FBitmap.Width);
  AssertTransparent(50, 50);
end;

end.
