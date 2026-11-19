// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Text.GlyphQuad.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Types,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Common.Matrix,
  Pdf4D.Common.Quad,
  Pdf4D.FontBox.BoundingBox,
  Pdf4D.Font.Base,
  Pdf4D.Font.Type1,
  Pdf4D.Model.Tests.Support,
  Pdf4D.Text.TextPosition;

type
  // A font whose bounding box is empty, which no font that the factory makes gives: a font without usable box takes the one of the
  // substitute font
  TEmptyBoxFont = class(TPDType1Font)
  public
    function GetBoundingBox: TBoundingBox; override;
  end;

  [TestFixture]
  TGlyphQuadTests = class
  private
    FModels: TModelTestDocuments;
    FFonts: TObjectList<TPDFont>;
    FPositions: TObjectList<TTextPosition>;

    function OpenFont(const FontObject, DescriptorObject: string; const HasEmptyBox: Boolean = False): TPDFont;
    function NewPosition(const Font: TPDFont; const Matrix: TPdfMatrix; const EndX, EndY, IndividualWidth: Single): TTextPosition;
    function CreateQuad(const Position: TTextPosition; const CropX, CropY: Single): TPdfQuad;
    procedure AssertPoint(const Expected: TPointF; const Actual: TPointF);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestHelveticaQuad;

    [Test]
    procedure TestCropLowerLeftIsAdded;

    [Test]
    procedure TestRotatedTextMatrixRotatesQuad;

    [Test]
    procedure TestMirroredTextHasPositiveBounds;

    [Test]
    procedure TestZeroAdvanceUsesIndividualWidth;

    [Test]
    procedure TestZeroAscentDescentFallsBackToBoundingBox;

    [Test]
    procedure TestEmptyBoundingBoxFallsBackToPdfBoxHeight;

    [Test]
    procedure TestType3UsesPdfBoxHeight;

    [Test]
    [TestCase('NaN', 'True')]
    [TestCase('Infinity', 'False')]
    procedure TestNonFiniteMatrixGivesNoQuad(const IsNaNValue: Boolean);
  end;

implementation

uses
  System.Math,
  Pdf4D.Font.Factory,
  Pdf4D.Text.GlyphQuad,
  Pdf4D.Tests.TextDocuments;

const
  PageWidth = 612;
  PageHeight = 792;
  Tolerance = 0.001;
  GlyphMaxHeight = 9;
  Type1Font = '<< /Type /Font /Subtype /Type1 /BaseFont /Test-Font /FontDescriptor 20 0 R >>';
  Type3FontWithDescriptor = '<< /Type /Font /Subtype /Type3 /FontBBox [0 0 100 100] /FontMatrix [0.001 0 0 0.001 0 0] /CharProcs << >> ' +
                            '/Encoding << /Differences [] >> /FontDescriptor 20 0 R >>';
  DescriptorWithoutAscentDescent = '<< /Type /FontDescriptor /FontName /Test-Font /Flags 32 /Ascent 0 /Descent 0 /FontBBox [0 -200 1000 800] >>';
  DescriptorWithEmptyBox = '<< /Type /FontDescriptor /FontName /Test-Font /Flags 32 /Ascent 0 /Descent 0 /FontBBox [0 0 0 0] >>';
  Type3Descriptor = '<< /Type /FontDescriptor /FontName /Test-Font /Flags 32 /Ascent 800 /Descent -200 /FontBBox [0 0 100 100] >>';

{ TEmptyBoxFont }

function TEmptyBoxFont.GetBoundingBox: TBoundingBox;
begin
  Result := TBoundingBox.Create(0, 0, 0, 0);
end;

{ TGlyphQuadTests }

procedure TGlyphQuadTests.Setup;
begin
  FModels := TModelTestDocuments.Create;
  FFonts := TObjectList<TPDFont>.Create(True);
  FPositions := TObjectList<TTextPosition>.Create(True);
end;

procedure TGlyphQuadTests.TearDown;
begin
  FreeAndNil(FPositions);
  FreeAndNil(FFonts);
  FreeAndNil(FModels);
end;

function TGlyphQuadTests.OpenFont(const FontObject, DescriptorObject: string; const HasEmptyBox: Boolean): TPDFont;
begin
  const Builder = TTextTestDocuments.NewBuilder(FontObject, '');
  try
    if not DescriptorObject.IsEmpty then
    begin
      Builder.AddObject(20, DescriptorObject);
    end;
    const Document = FModels.Open(Builder);
    const Dictionary = TTextTestDocuments.FontDictionary(Document, 'F1');
    if HasEmptyBox then
    begin
      Result := TEmptyBoxFont.Create(Dictionary, Document.Context);
    end
    else
    begin
      Result := TPDFontFactory.CreateFont(Dictionary, Document.Context);
    end;
    FFonts.Add(Result);
  finally
    Builder.Free;
  end;
end;

function TGlyphQuadTests.NewPosition(const Font: TPDFont; const Matrix: TPdfMatrix; const EndX, EndY, IndividualWidth: Single): TTextPosition;
begin
  Result := TTextPosition.Create(0, PageWidth, PageHeight, Matrix, EndX, EndY, GlyphMaxHeight, IndividualWidth, 3, 'F', [70], Font, 12, 12);
  FPositions.Add(Result);
end;

function TGlyphQuadTests.CreateQuad(const Position: TTextPosition; const CropX, CropY: Single): TPdfQuad;
begin
  const Created = TGlyphQuad.TryCreate(Position, TPointF.Create(CropX, CropY), Result);

  Assert.IsTrue(Created);
end;

procedure TGlyphQuadTests.AssertPoint(const Expected: TPointF; const Actual: TPointF);
begin
  Assert.AreEqual(Double(Expected.X), Double(Actual.X), Tolerance);
  Assert.AreEqual(Double(Expected.Y), Double(Actual.Y), Tolerance);
end;

procedure TGlyphQuadTests.TestHelveticaQuad;
begin
  const Font = OpenFont(TTextTestDocuments.HelveticaF1, '');
  const Position = NewPosition(Font, TPdfMatrix.Create(12, 0, 0, 12, 100, 700), 106.672, 700, 6.672);

  const Quad = CreateQuad(Position, 0, 0);

  AssertPoint(TPointF.Create(100, 697.516), Quad.P1);
  AssertPoint(TPointF.Create(106.672, 697.516), Quad.P2);
  AssertPoint(TPointF.Create(106.672, 708.616), Quad.P3);
  AssertPoint(TPointF.Create(100, 708.616), Quad.P4);
end;

procedure TGlyphQuadTests.TestCropLowerLeftIsAdded;
begin
  const Font = OpenFont(TTextTestDocuments.HelveticaF1, '');
  const Position = NewPosition(Font, TPdfMatrix.Create(12, 0, 0, 12, 100, 700), 106.672, 700, 6.672);

  const Quad = CreateQuad(Position, 10, 20);

  AssertPoint(TPointF.Create(110, 717.516), Quad.P1);
  AssertPoint(TPointF.Create(116.672, 717.516), Quad.P2);
  AssertPoint(TPointF.Create(116.672, 728.616), Quad.P3);
  AssertPoint(TPointF.Create(110, 728.616), Quad.P4);
end;

procedure TGlyphQuadTests.TestRotatedTextMatrixRotatesQuad;
begin
  const Font = OpenFont(TTextTestDocuments.HelveticaF1, '');
  const Position = NewPosition(Font, TPdfMatrix.Create(0, 12, -12, 0, 100, 700), 100, 706.672, 6.672);

  const Quad = CreateQuad(Position, 0, 0);

  AssertPoint(TPointF.Create(100 + 2.484, 700), Quad.P1);
  AssertPoint(TPointF.Create(100 + 2.484, 706.672), Quad.P2);
  AssertPoint(TPointF.Create(100 - 8.616, 706.672), Quad.P3);
  AssertPoint(TPointF.Create(100 - 8.616, 700), Quad.P4);
end;

procedure TGlyphQuadTests.TestMirroredTextHasPositiveBounds;
begin
  const Font = OpenFont(TTextTestDocuments.HelveticaF1, '');
  const Position = NewPosition(Font, TPdfMatrix.Create(12, 0, 0, -12, 100, 700), 106.672, 700, 6.672);

  const Bounds = CreateQuad(Position, 0, 0).Bounds;

  Assert.IsTrue(Bounds.Width > 0);
  Assert.IsTrue(Bounds.Height > 0);
end;

procedure TGlyphQuadTests.TestZeroAdvanceUsesIndividualWidth;
begin
  const Font = OpenFont(TTextTestDocuments.HelveticaF1, '');
  const Position = NewPosition(Font, TPdfMatrix.Create(12, 0, 0, 12, 100, 700), 100, 700, 6.672);

  const Quad = CreateQuad(Position, 0, 0);

  AssertPoint(TPointF.Create(106.672, 697.516), Quad.P2);
  AssertPoint(TPointF.Create(106.672, 708.616), Quad.P3);
end;

procedure TGlyphQuadTests.TestZeroAscentDescentFallsBackToBoundingBox;
begin
  const Font = OpenFont(Type1Font, DescriptorWithoutAscentDescent);
  const Position = NewPosition(Font, TPdfMatrix.Create(12, 0, 0, 12, 100, 700), 106.672, 700, 6.672);

  const Quad = CreateQuad(Position, 0, 0);

  Assert.AreEqual(Double(700 - 200 / 1000 * 12), Double(Quad.P1.Y), Tolerance);
  Assert.AreEqual(Double(700 + 800 / 1000 * 12), Double(Quad.P4.Y), Tolerance);
end;

procedure TGlyphQuadTests.TestEmptyBoundingBoxFallsBackToPdfBoxHeight;
begin
  const Font = OpenFont(Type1Font, DescriptorWithEmptyBox, True);
  const Position = NewPosition(Font, TPdfMatrix.Create(12, 0, 0, 12, 100, 700), 106.672, 700, 6.672);

  const Quad = CreateQuad(Position, 0, 0);

  Assert.AreEqual(Double(700), Double(Quad.P1.Y), Tolerance);
  Assert.AreEqual(Double(700 + GlyphMaxHeight), Double(Quad.P4.Y), Tolerance);
end;

procedure TGlyphQuadTests.TestType3UsesPdfBoxHeight;
begin
  const Font = OpenFont(Type3FontWithDescriptor, Type3Descriptor);
  const Position = NewPosition(Font, TPdfMatrix.Create(12, 0, 0, 12, 100, 700), 106.672, 700, 6.672);

  const Quad = CreateQuad(Position, 0, 0);

  Assert.AreEqual(Double(700), Double(Quad.P1.Y), Tolerance);
  Assert.AreEqual(Double(700 + GlyphMaxHeight), Double(Quad.P4.Y), Tolerance);
end;

procedure TGlyphQuadTests.TestNonFiniteMatrixGivesNoQuad(const IsNaNValue: Boolean);
begin
  var Value := Single(Infinity);
  if IsNaNValue then
  begin
    Value := NaN;
  end;
  const Font = OpenFont(TTextTestDocuments.HelveticaF1, '');
  const Position = NewPosition(Font, TPdfMatrix.Create(12, 0, 0, Value, 100, 700), 106.672, 700, 6.672);
  var Quad: TPdfQuad;

  const Created = TGlyphQuad.TryCreate(Position, TPointF.Create(0, 0), Quad);

  Assert.IsFalse(Created);
end;

end.
