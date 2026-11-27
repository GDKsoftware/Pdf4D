// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// The render comparison with the PDFBox reference images on the native backend; the tests are in Pdf4D.Tests.RenderGolden.Base, the
// pages that differ are in the Native entries of the known-differences files and in pending-native.txt
unit Pdf4D.Tests.RenderGolden.Native.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  DUnitX.TestFramework,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Tests.RenderGolden.Base;

type
  // A native backend whose devices make every rectangular clip a mask as well, to compare the two ways to clip on real files
  TMaskClipBackend = class(TInterfacedObject, IPdfRenderBackend)
  strict private
    FInner: IPdfRenderBackend;

  public
    constructor Create;

    function Name: string;
    function CreateRasterDevice(const Width, Height: Integer): IPdfRasterDevice;
  end;

  [TestFixture]
  TNativeRenderGoldenTests = class(TRenderGoldenTestsBase)
  strict private
    class procedure Measure(const Left, Right: TPdfBitmap; out PixelCount, Largest: Integer); static;

  protected
    function CreateBackend: IPdfRenderBackend; override;
    function BackendName: string; override;
    function PendingFileName: string; override;

  public
    // The rectangular clip of the device is an optimisation: the scan converter gets the clip rectangle and builds the edges of a path that
    // crosses it against that rectangle, where the mask clip lets the whole path through and zeroes the pixels outside. The pixels are the
    // same for a path that stays inside the rectangle. A path that crosses it is cut by the edge clipper first: a quadratic or cubic that
    // crosses the rectangle is chopped, each piece gets a subdivision of its own and the edges of the whole visible part of the curve move
    // (a straight line is rounded to the grid again at the cut), so the coverage of pixels along such a path moves by a level or more (the
    // outline of the tiger at the top of its clip, glyphs on the last rows of survey.pdf). Skia does the same. The last two numbers of a
    // case are the limits: the largest difference of a channel and the number of pixels that differ. The two measured on Win64 are the
    // limits with a margin (twice the pixels and 4 levels more), because the flattening is f32 and, on Win32, x87; the first four pages
    // are byte for byte equal.
    [Test]
    [TestCase('Clip', 'generated/render/clip.pdf,1,0,0')]
    [TestCase('Paths', 'generated/render/paths.pdf,1,0,0')]
    [TestCase('Images', 'generated/render/images.pdf,1,0,0')]
    [TestCase('Transparency', 'generated/render/transparency.pdf,1,0,0')]
    [TestCase('Survey', 'pdfbox/input/rendering/survey.pdf,1,20,16')]
    // Win32 (x87) moves the edges of the tiger by more levels: 13 measured, with 7921 pixels (the pixel count is below the limit)
    {$IFDEF CPUX86}
    [TestCase('Tiger', 'pdfbox/input/rendering/tiger-as-form-xobject.pdf,1,13,15804')]
    {$ELSE}
    [TestCase('Tiger', 'pdfbox/input/rendering/tiger-as-form-xobject.pdf,1,11,15804')]
    {$ENDIF}
    procedure TestForcedMaskClipGivesTheSamePixels(const RelativePath: string; const Page, MaxDifference, MaxPixels: Integer);
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Pdf4D.Api.Document,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Common.Defines,
  Pdf4D.Render.Native.Backend,
  Pdf4D.Render.Native.Device,
  Pdf4D.Render.Renderer,
  Pdf4D.Render.Renderer.Interfaces,
  Pdf4D.Tests.Corpus;

const
  RenderDpi = 72;
  BytesPerPixel = 4;

{ TMaskClipBackend }

constructor TMaskClipBackend.Create;
begin
  inherited Create;
  FInner := TPdfNativeBackend.Create;
end;

function TMaskClipBackend.Name: string;
begin
  Result := FInner.Name;
end;

function TMaskClipBackend.CreateRasterDevice(const Width, Height: Integer): IPdfRasterDevice;
begin
  Result := FInner.CreateRasterDevice(Width, Height);
  (Result as TPdfNativeDevice).ForceMaskClip := True;
end;

{ TNativeRenderGoldenTests }

function TNativeRenderGoldenTests.CreateBackend: IPdfRenderBackend;
begin
  Result := TPdfNativeBackend.Create;
end;

function TNativeRenderGoldenTests.BackendName: string;
begin
  Result := 'Native';
end;

function TNativeRenderGoldenTests.PendingFileName: string;
begin
  Result := 'pending-native.txt';
end;

// How many pixels differ and by how much a channel at most
class procedure TNativeRenderGoldenTests.Measure(const Left, Right: TPdfBitmap; out PixelCount, Largest: Integer);
begin
  PixelCount := 0;
  Largest := 0;
  for var Y := 0 to Left.Height - 1 do
  begin
    for var X := 0 to Left.Width - 1 do
    begin
      var PixelLargest := 0;
      for var Channel := 0 to BytesPerPixel - 1 do
      begin
        PixelLargest := Max(PixelLargest, Abs(Integer(Left.ScanLine(Y)[X * BytesPerPixel + Channel]) - Integer(Right.ScanLine(Y)[X * BytesPerPixel + Channel])));
      end;
      if PixelLargest > 0 then
      begin
        Inc(PixelCount);
        Largest := Max(Largest, PixelLargest);
      end;
    end;
  end;
end;

procedure TNativeRenderGoldenTests.TestForcedMaskClipGivesTheSamePixels(const RelativePath: string; const Page, MaxDifference, MaxPixels: Integer);
begin
  var Options := TPdfLoadOptions.Default;
  Options.Password := TCorpus.PasswordFor(RelativePath);
  const Document: IPdfDocument = TPdfDocument.Load(TCorpus.PdfPath(RelativePath), Options);

  var Fast: TPdfBitmap := nil;
  var Forced: TPdfBitmap := nil;
  try
    const FastRenderer: IPdfRenderer = TPdfRenderer.Create(Document, CreateBackend);
    FastRenderer.RenderToBitmap(Page - 1, TPdfRenderParams.FromDpi(RenderDpi), Fast);
    const ForcedRenderer: IPdfRenderer = TPdfRenderer.Create(Document, TMaskClipBackend.Create);
    ForcedRenderer.RenderToBitmap(Page - 1, TPdfRenderParams.FromDpi(RenderDpi), Forced);

    Assert.AreEqual<Integer>(Length(Fast.Pixels), Length(Forced.Pixels), 'the renders have the same size');
    var PixelCount, Largest: Integer;
    Measure(Fast, Forced, PixelCount, Largest);
    Assert.IsTrue((PixelCount <= MaxPixels) and (Largest <= MaxDifference),
                  Format('%s page %d: %d pixels differ, by %d at most, between the rectangular clip and the mask clip (limits %d and %d)', [RelativePath, Page, PixelCount, Largest, MaxPixels, MaxDifference]));
  finally
    Forced.Free;
    Fast.Free;
  end;
end;

end.
