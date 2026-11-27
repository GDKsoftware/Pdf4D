// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Pixel tests of the transparency groups: the backdrop of a group that is not isolated, and blend modes on the page.
// The expected colours follow from the formulas of ISO 32000-1 11.3.5 and 11.4.8, which PDFBox 3.0.8 implements as well.
unit Pdf4D.Tests.RenderGroups.Base;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Tests.GraphicsDocuments;

type
  TGroupDevicePixelTestsBase = class abstract
  protected
    function CreateBackend: IPdfRenderBackend; virtual; abstract;

  private
    FBackend: IPdfRenderBackend;

    function FilledDevice(const Color: TPdfDeviceColor): IPdfRasterDevice;
    procedure AssertPixel(const Bitmap: TPdfBitmap; const Expected: TPdfDeviceColor; const Tolerance: Integer);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestRemoveBackdropGivesTheColourOfTheGroupAlone;

    [Test]
    procedure TestRemoveBackdropKeepsTheAlphaOfTheGroup;

    [Test]
    procedure TestRemoveBackdropWhereTheGroupIsEmptyGivesTransparent;

    [Test]
    procedure TestRemoveBackdropOutsideTheBackdropKeepsTheColour;
  end;

  TRenderGroupTestsBase = class abstract
  protected
    function CreateBackend: IPdfRenderBackend; virtual; abstract;

  private
    const Resources = '/XObject << /G1 5 0 R >> /ExtGState << /GsHalf << /ca 0.5 >> /GsMultiply << /BM /Multiply >> >>';
    const GroupResources = '/Resources << /ExtGState << /GsMultiply << /BM /Multiply >> >> >>';

  private
    FDocuments: TGraphicsDocuments;
    FDocument: IPdfDocument;

    function Render(const PageContent, GroupEntries, GroupContent: string): TPdfBitmap;
    procedure AssertPixel(const Bitmap: TPdfBitmap; const X, Y: Integer; const Expected: TPdfDeviceColor; const Tolerance: Integer);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestNonIsolatedGroupWithBlendModeUsesBackdrop;

    [Test]
    procedure TestIsolatedGroupWithBlendModeIgnoresBackdrop;

    [Test]
    procedure TestNonIsolatedGroupWithBlendModeKeepsTheBackdropOutsideItsShapes;

    [Test]
    procedure TestBlendModeOnPageFlattensOnWhite;

    [Test]
    procedure TestGroupAlphaIsAppliedOnceToOverlappingShapes;
  end;

implementation

uses
  Pdf4D.Common.Matrix,
  Pdf4D.Common.Path,
  Pdf4D.Render.GroupDevice,
  Pdf4D.Render.Renderer,
  Pdf4D.Render.Renderer.Interfaces;


const
  DeviceSize = 4;
  PageSize = 200;

{ TGroupDevicePixelTestsBase }

procedure TGroupDevicePixelTestsBase.Setup;
begin
  FBackend := CreateBackend;
end;

procedure TGroupDevicePixelTestsBase.TearDown;
begin
  FBackend := nil;
end;

function TGroupDevicePixelTestsBase.FilledDevice(const Color: TPdfDeviceColor): IPdfRasterDevice;
begin
  Result := FBackend.CreateRasterDevice(DeviceSize, DeviceSize);
  Result.Clear(Color);
end;

procedure TGroupDevicePixelTestsBase.AssertPixel(const Bitmap: TPdfBitmap; const Expected: TPdfDeviceColor; const Tolerance: Integer);
begin
  const Actual = Bitmap.GetPixel(1, 1);
  Assert.AreEqual(Double(Expected.R), Double(Actual.R), Tolerance, 'R');
  Assert.AreEqual(Double(Expected.G), Double(Actual.G), Tolerance, 'G');
  Assert.AreEqual(Double(Expected.B), Double(Actual.B), Tolerance, 'B');
  Assert.AreEqual(Double(Expected.A), Double(Actual.A), Tolerance, 'A');
end;

// The backdrop is red; the group paints (0, 0, 255) with Multiply, so the layer shows black. Taking the backdrop out gives the colour that
// the group would have had on a transparent backdrop for a normal blend, and for Multiply the colour the formula gives.
procedure TGroupDevicePixelTestsBase.TestRemoveBackdropGivesTheColourOfTheGroupAlone;
begin
  const Backdrop = TPdfBitmap.Create(DeviceSize, DeviceSize);
  try
    const Red = TPdfDeviceColor.Create(255, 0, 0);
    for var Y := 0 to DeviceSize - 1 do
    begin
      for var X := 0 to DeviceSize - 1 do
      begin
        Backdrop.SetPixel(X, Y, Red);
      end;
    end;

    const Image = FilledDevice(Red);
    const Alpha = FBackend.CreateRasterDevice(DeviceSize, DeviceSize);
    const Group = TPdfGroupDevice.Create(Image, Alpha);
    const Reference: IPdfRasterDevice = Group;
    const Path = TPdfPath.Create;
    try
      Path.MoveTo(0, 0);
      Path.LineTo(DeviceSize, 0);
      Path.LineTo(DeviceSize, DeviceSize);
      Path.LineTo(0, DeviceSize);
      Path.ClosePath;
      var Composite := TPdfComposite.Default;
      Composite.BlendMode := TPdfBlendMode.Multiply;
      Composite.AntiAlias := False;
      Reference.FillPath(Path, TPdfMatrix.Identity, TPdfFillRule.NonZero, TPdfPaint.Solid(TPdfDeviceColor.Create(128, 128, 255)), Composite);
    finally
      Path.Free;
    end;

    Group.RemoveBackdrop(Backdrop, 0, 0);
    const Result = Group.ToBitmap;
    try
      AssertPixel(Result, TPdfDeviceColor.Create(128, 0, 0), 2);
    finally
      Result.Free;
    end;
  finally
    Backdrop.Free;
  end;
end;

// A normal fill of half alpha over red: the layer is a mix, the group alone is the fill colour at half alpha
procedure TGroupDevicePixelTestsBase.TestRemoveBackdropKeepsTheAlphaOfTheGroup;
begin
  const Backdrop = TPdfBitmap.Create(DeviceSize, DeviceSize);
  try
    const Red = TPdfDeviceColor.Create(255, 0, 0);
    for var Y := 0 to DeviceSize - 1 do
    begin
      for var X := 0 to DeviceSize - 1 do
      begin
        Backdrop.SetPixel(X, Y, Red);
      end;
    end;

    const Group = TPdfGroupDevice.Create(FilledDevice(Red), FBackend.CreateRasterDevice(DeviceSize, DeviceSize));
    const Reference: IPdfRasterDevice = Group;
    const Path = TPdfPath.Create;
    try
      Path.MoveTo(0, 0);
      Path.LineTo(DeviceSize, 0);
      Path.LineTo(DeviceSize, DeviceSize);
      Path.LineTo(0, DeviceSize);
      Path.ClosePath;
      var Composite := TPdfComposite.Default;
      Composite.Alpha := 0.5;
      Composite.AntiAlias := False;
      Reference.FillPath(Path, TPdfMatrix.Identity, TPdfFillRule.NonZero, TPdfPaint.Solid(TPdfDeviceColor.Create(0, 0, 255)), Composite);
    finally
      Path.Free;
    end;

    Group.RemoveBackdrop(Backdrop, 0, 0);
    const Result = Group.ToBitmap;
    try
      // Premultiplied: (0, 0, 255) at alpha 128 is (0, 0, 128, 128)
      AssertPixel(Result, TPdfDeviceColor.Create(0, 0, 128, 128), 3);
    finally
      Result.Free;
    end;
  finally
    Backdrop.Free;
  end;
end;

procedure TGroupDevicePixelTestsBase.TestRemoveBackdropWhereTheGroupIsEmptyGivesTransparent;
begin
  const Backdrop = TPdfBitmap.Create(DeviceSize, DeviceSize);
  try
    const Group = TPdfGroupDevice.Create(FilledDevice(TPdfDeviceColor.Create(255, 0, 0)), FBackend.CreateRasterDevice(DeviceSize, DeviceSize));
    const Reference: IPdfRasterDevice = Group;

    Group.RemoveBackdrop(Backdrop, 0, 0);
    const Result = Group.ToBitmap;
    try
      AssertPixel(Result, TPdfDeviceColor.Transparent, 0);
    finally
      Result.Free;
    end;
  finally
    Backdrop.Free;
  end;
end;

procedure TGroupDevicePixelTestsBase.TestRemoveBackdropOutsideTheBackdropKeepsTheColour;
begin
  const Backdrop = TPdfBitmap.Create(1, 1);
  try
    const Group = TPdfGroupDevice.Create(FilledDevice(TPdfDeviceColor.Create(10, 20, 30)), FBackend.CreateRasterDevice(DeviceSize, DeviceSize));
    const Reference: IPdfRasterDevice = Group;
    Reference.Clear(TPdfDeviceColor.Create(10, 20, 30));

    // Pixel (1, 1) of the group is (11, 11) of the backdrop, which does not exist: transparent backdrop
    Group.RemoveBackdrop(Backdrop, 10, 10);
    const Result = Group.ToBitmap;
    try
      AssertPixel(Result, TPdfDeviceColor.Create(10, 20, 30), 1);
    finally
      Result.Free;
    end;
  finally
    Backdrop.Free;
  end;
end;

{ TRenderGroupTestsBase }

procedure TRenderGroupTestsBase.Setup;
begin
  FDocuments := TGraphicsDocuments.Create;
end;

procedure TRenderGroupTestsBase.TearDown;
begin
  FDocument := nil;
  FreeAndNil(FDocuments);
end;

function TRenderGroupTestsBase.Render(const PageContent, GroupEntries, GroupContent: string): TPdfBitmap;
begin
  const Builder = TGraphicsDocuments.NewBuilder(TEncoding.ASCII.GetBytes(PageContent), Resources);
  try
    Builder.AddStreamObject(5, Format('/Type /XObject /Subtype /Form /BBox [0 0 100 100] %s %s', [GroupEntries, GroupResources]),
                            TEncoding.ASCII.GetBytes(GroupContent));
    FDocument := FDocuments.Open(Builder);
  finally
    Builder.Free;
  end;

  const Renderer: IPdfRenderer = TPdfRenderer.Create(FDocument, CreateBackend);
  Assert.AreEqual(TPdfRenderStatus.Completed, Renderer.RenderToBitmap(0, TPdfRenderParams.Create(1), Result));
end;

// The page row of a point is PageSize - Y
procedure TRenderGroupTestsBase.AssertPixel(const Bitmap: TPdfBitmap; const X, Y: Integer; const Expected: TPdfDeviceColor; const Tolerance: Integer);
begin
  const Actual = Bitmap.GetPixel(X, PageSize - Y);
  Assert.AreEqual(Double(Expected.R), Double(Actual.R), Tolerance, Format('R at (%d, %d)', [X, Y]));
  Assert.AreEqual(Double(Expected.G), Double(Actual.G), Tolerance, Format('G at (%d, %d)', [X, Y]));
  Assert.AreEqual(Double(Expected.B), Double(Actual.B), Tolerance, Format('B at (%d, %d)', [X, Y]));
  Assert.AreEqual(Double(Expected.A), Double(Actual.A), Tolerance, Format('A at (%d, %d)', [X, Y]));
end;

// Red page, a group with a Multiply fill of (0.5, 0.5, 1): the fill sees the red backdrop, so it is (0.5, 0, 0)
procedure TRenderGroupTestsBase.TestNonIsolatedGroupWithBlendModeUsesBackdrop;
begin
  const Bitmap = Render('1 0 0 rg 0 0 200 200 re f /G1 Do', '/Group << /S /Transparency /I false >>', '/GsMultiply gs 0.5 0.5 1 rg 20 20 40 40 re f');
  try
    AssertPixel(Bitmap, 40, 40, TPdfDeviceColor.Create(128, 0, 0), 2);
  finally
    Bitmap.Free;
  end;
end;

procedure TRenderGroupTestsBase.TestIsolatedGroupWithBlendModeIgnoresBackdrop;
begin
  const Bitmap = Render('1 0 0 rg 0 0 200 200 re f /G1 Do', '/Group << /S /Transparency /I true >>', '/GsMultiply gs 0.5 0.5 1 rg 20 20 40 40 re f');
  try
    AssertPixel(Bitmap, 40, 40, TPdfDeviceColor.Create(128, 128, 255), 2);
  finally
    Bitmap.Free;
  end;
end;

procedure TRenderGroupTestsBase.TestNonIsolatedGroupWithBlendModeKeepsTheBackdropOutsideItsShapes;
begin
  const Bitmap = Render('1 0 0 rg 0 0 200 200 re f /G1 Do', '/Group << /S /Transparency /I false >>', '/GsMultiply gs 0.5 0.5 1 rg 20 20 40 40 re f');
  try
    AssertPixel(Bitmap, 80, 80, TPdfDeviceColor.Create(255, 0, 0), 1);
    AssertPixel(Bitmap, 150, 150, TPdfDeviceColor.Create(255, 0, 0), 1);
  finally
    Bitmap.Free;
  end;
end;

procedure TRenderGroupTestsBase.TestBlendModeOnPageFlattensOnWhite;
begin
  const Bitmap = Render('/GsMultiply gs 0.5 0.5 1 rg 20 20 100 100 re f', '', '');
  try
    AssertPixel(Bitmap, 50, 50, TPdfDeviceColor.Create(128, 128, 255), 2);
    AssertPixel(Bitmap, 190, 190, TPdfDeviceColor.White, 0);
  finally
    Bitmap.Free;
  end;
end;

// Two opaque overlapping rectangles in a group drawn with ca 0.5 are one shape: the overlap is as light as the rest
procedure TRenderGroupTestsBase.TestGroupAlphaIsAppliedOnceToOverlappingShapes;
begin
  const Bitmap = Render('/GsHalf gs /G1 Do', '/Group << /S /Transparency /I true >>', '1 0 0 rg 10 10 50 50 re f 1 0 0 rg 40 40 50 50 re f');
  try
    AssertPixel(Bitmap, 20, 20, TPdfDeviceColor.Create(255, 128, 128), 2);
    AssertPixel(Bitmap, 50, 50, TPdfDeviceColor.Create(255, 128, 128), 2);
    AssertPixel(Bitmap, 80, 80, TPdfDeviceColor.Create(255, 128, 128), 2);
  finally
    Bitmap.Free;
  end;
end;

end.
