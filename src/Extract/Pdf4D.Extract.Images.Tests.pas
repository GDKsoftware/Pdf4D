// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Extract.Images.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Common.Defines,
  Pdf4D.Extract.Images.Interfaces;

type
  [TestFixture]
  TPdfImagesTests = class
  private
    const Tolerance = 0.01;
    const RotatedFile = 'generated/extract/images-rotated.pdf';
    const ReuseFile = 'generated/extract/images-reuse.pdf';
    const FiltersFile = 'generated/extract/images-filters.pdf';

  private
    FLog: TStringList;
    FPageImages: IPdfPageImages;

    procedure RecordLog(const Level: TPdfLogLevel; const Message: string);
    function ImagesOf(const RelativePath: string; const PageIndex: Integer): IPdfPageImages;
    procedure CheckBox(const Info: TPdfImageInfo; const Left, Top, Width, Height: Double);
    procedure CheckProperties(const Info: TPdfImageInfo; const Filters, ColorSpace: string; const BitsPerComponent, ComponentCount: Integer;
      const IsStencil, HasMask: Boolean);
    procedure GetDataTooHigh;
    procedure GetDataNegative;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestImageCountAndOrder;

    // The same image on the four rotations of a page with a CropBox that has an offset
    [Test]
    [TestCase('0', '0,70,450,100,50')]
    [TestCase('90', '1,100,70,50,100')]
    [TestCase('180', '2,330,100,100,50')]
    [TestCase('270', '3,450,330,50,100')]
    procedure TestBoxOnRotatedPages(const PageIndex: Integer; const Left, Top, Width, Height: Double);

    [Test]
    procedure TestMatrixIsTheCtmOfTheUnitSquare;

    [Test]
    procedure TestReusedXObjectSharesKey;

    [Test]
    procedure TestImageInFormIsFound;

    [Test]
    procedure TestInlineImageHasNoKey;

    [Test]
    procedure TestRecursiveFormTerminates;

    [Test]
    procedure TestPropertiesOfFilters;

    [Test]
    procedure TestListingDecodesNothing;

    [Test]
    procedure TestListingKeepsThePageAlive;

    [Test]
    procedure TestGetDataRejectsABadIndex;
  end;

implementation

uses
  System.Types,
  Pdf4D.Api.Document,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Api.Page.Interfaces,
  Pdf4D.Extract.Images,
  Pdf4D.Tests.Corpus;

procedure TPdfImagesTests.Setup;
begin
  FLog := TStringList.Create;
end;

procedure TPdfImagesTests.TearDown;
begin
  FPageImages := nil;
  FLog.Free;
end;

procedure TPdfImagesTests.RecordLog(const Level: TPdfLogLevel; const Message: string);
begin
  FLog.Add(Message);
end;

function TPdfImagesTests.ImagesOf(const RelativePath: string; const PageIndex: Integer): IPdfPageImages;
begin
  var Options := TPdfLoadOptions.Default;
  Options.OnLog := Self.RecordLog;
  const Document = TPdfDocument.Load(TCorpus.PdfPath(RelativePath), Options);
  Result := TPdfImages.OfPage(Document.Page(PageIndex));
end;

procedure TPdfImagesTests.CheckBox(const Info: TPdfImageInfo; const Left, Top, Width, Height: Double);
begin
  Assert.AreEqual(Left, Double(Info.Box.Left), Tolerance, 'Left');
  Assert.AreEqual(Top, Double(Info.Box.Top), Tolerance, 'Top');
  Assert.AreEqual(Width, Double(Info.Box.Width), Tolerance, 'Width');
  Assert.AreEqual(Height, Double(Info.Box.Height), Tolerance, 'Height');
end;

procedure TPdfImagesTests.CheckProperties(const Info: TPdfImageInfo; const Filters, ColorSpace: string; const BitsPerComponent, ComponentCount: Integer;
  const IsStencil, HasMask: Boolean);
begin
  Assert.AreEqual(Filters, string.Join(',', Info.Filters), 'Filters');
  Assert.AreEqual(ColorSpace, Info.ColorSpace, 'ColorSpace');
  Assert.AreEqual(BitsPerComponent, Info.BitsPerComponent, 'BitsPerComponent');
  Assert.AreEqual(ComponentCount, Info.ComponentCount, 'ComponentCount');
  Assert.AreEqual(IsStencil, Info.IsStencil, 'IsStencil');
  Assert.AreEqual(HasMask, Info.HasMask, 'HasMask');
  Assert.IsFalse(Info.IsInline);
end;

procedure TPdfImagesTests.TestImageCountAndOrder;
begin
  const Images = ImagesOf(ReuseFile, 0).Images;

  Assert.AreEqual<Integer>(8, Length(Images));
  for var Index: Integer := 0 to High(Images) do
  begin
    Assert.AreEqual(Index, Images[Index].Index);
    Assert.AreEqual<Integer>(0, Images[Index].PageIndex);
  end;
  // Five placements of one XObject, then the image of the form, the inline image and the image of the form that draws itself
  for var Index: Integer := 0 to 4 do
  begin
    Assert.AreEqual<Integer>(2, Images[Index].PixelWidth);
    CheckBox(Images[Index], 20 + Index * 50, 170, 30, 30);
  end;
  Assert.AreEqual<Integer>(3, Images[5].PixelWidth);
  Assert.IsTrue(Images[6].IsInline);
  Assert.AreEqual<Integer>(3, Images[7].PixelHeight);
end;

procedure TPdfImagesTests.TestBoxOnRotatedPages(const PageIndex: Integer; const Left, Top, Width, Height: Double);
begin
  const Images = ImagesOf(RotatedFile, PageIndex).Images;

  Assert.AreEqual<Integer>(1, Length(Images));
  CheckBox(Images[0], Left, Top, Width, Height);
  Assert.AreEqual(PageIndex, Images[0].PageIndex);
end;

procedure TPdfImagesTests.TestMatrixIsTheCtmOfTheUnitSquare;
begin
  const Info = ImagesOf(RotatedFile, 1).Images[0];

  // q 100 0 0 50 120 200 cm: the matrix is in user space whatever the rotation of the page
  Assert.AreEqual(Double(100), Double(Info.Matrix.ScaleX), Tolerance);
  Assert.AreEqual(Double(50), Double(Info.Matrix.ScaleY), Tolerance);
  Assert.AreEqual(Double(120), Double(Info.Matrix.TranslateX), Tolerance);
  Assert.AreEqual(Double(200), Double(Info.Matrix.TranslateY), Tolerance);
end;

procedure TPdfImagesTests.TestReusedXObjectSharesKey;
begin
  const Images = ImagesOf(ReuseFile, 0).Images;

  Assert.IsTrue(Images[0].ObjectNumber > 0, 'The XObject has a key');
  for var Index: Integer := 1 to 4 do
  begin
    Assert.AreEqual(Images[0].ObjectNumber, Images[Index].ObjectNumber, 'Object number');
    Assert.AreEqual(Images[0].Generation, Images[Index].Generation, 'Generation');
    Assert.IsTrue(Images[Index].Box.Left > Images[Index - 1].Box.Left, 'Distinct boxes');
  end;
  Assert.AreNotEqual(Images[0].ObjectNumber, Images[5].ObjectNumber, 'Another XObject, another key');
end;

procedure TPdfImagesTests.TestImageInFormIsFound;
begin
  const Images = ImagesOf(ReuseFile, 0).Images;

  Assert.AreEqual<Integer>(3, Images[5].PixelWidth);
  Assert.AreEqual<Integer>(1, Images[5].PixelHeight);
  Assert.IsFalse(Images[5].IsInline);
  Assert.IsTrue(Images[5].ObjectNumber > 0);
  // The form is placed at (300, 300) and the image inside it at (5, 5), 40 x 20 points
  CheckBox(Images[5], 305, 475, 40, 20);
end;

procedure TPdfImagesTests.TestInlineImageHasNoKey;
begin
  const Info = ImagesOf(ReuseFile, 0).Images[6];

  Assert.IsTrue(Info.IsInline);
  Assert.AreEqual<Integer>(0, Info.ObjectNumber);
  Assert.AreEqual<Integer>(0, Info.Generation);
  Assert.AreEqual<Integer>(2, Info.PixelWidth);
  Assert.AreEqual<Integer>(2, Info.PixelHeight);
  Assert.AreEqual('DeviceRGB', Info.ColorSpace);
  Assert.AreEqual('ASCIIHexDecode', string.Join(',', Info.Filters));
  CheckBox(Info, 100, 650, 50, 50);
end;

procedure TPdfImagesTests.TestRecursiveFormTerminates;
begin
  const Images = ImagesOf(ReuseFile, 0).Images;

  // The form draws its image once and then itself, which the engine skips
  Assert.AreEqual<Integer>(8, Length(Images));
  Assert.AreEqual<Integer>(1, Images[7].PixelWidth);
  Assert.AreEqual<Integer>(3, Images[7].PixelHeight);
  CheckBox(Images[7], 200, 570, 10, 30);
end;

procedure TPdfImagesTests.TestPropertiesOfFilters;
begin
  const Images = ImagesOf(FiltersFile, 0).Images;

  Assert.AreEqual<Integer>(12, Length(Images));
  CheckProperties(Images[0], 'DCTDecode', 'DeviceRGB', 8, 3, False, False);
  CheckProperties(Images[1], 'FlateDecode', 'DeviceRGB', 8, 3, False, False);
  CheckProperties(Images[2], 'FlateDecode,DCTDecode', 'DeviceRGB', 8, 3, False, False);
  CheckProperties(Images[3], 'CCITTFaxDecode', 'DeviceGray', 1, 1, False, False);
  CheckProperties(Images[4], '', 'Indexed', 8, 1, False, False);
  CheckProperties(Images[5], '', 'DeviceCMYK', 8, 4, False, False);
  CheckProperties(Images[6], 'FlateDecode', 'DeviceRGB', 8, 3, False, True);
  CheckProperties(Images[7], '', '', 1, 1, True, False);
  CheckProperties(Images[8], 'FlateDecode', 'DeviceRGB', 8, 3, False, False);
  CheckProperties(Images[9], 'JPXDecode', '', -1, 0, False, False);
  CheckProperties(Images[10], '', 'ICCBased', 8, 3, False, False);
  CheckProperties(Images[11], '', 'DeviceRGB', 8, 3, False, True);
  Assert.AreEqual<Integer>(96, Images[3].PixelWidth);
  Assert.AreEqual<Integer>(64, Images[3].PixelHeight);
  Assert.AreEqual<Integer>(4, Images[8].PixelWidth);
end;

procedure TPdfImagesTests.TestListingDecodesNothing;
begin
  const Images = ImagesOf(FiltersFile, 0).Images;

  // The damaged Flate image and the JPX stream are listed; reading their pixels would raise or log
  Assert.AreEqual<Integer>(12, Length(Images));
  Assert.AreEqual<Integer>(0, FLog.Count, 'Log: ' + FLog.Text);
end;

procedure TPdfImagesTests.TestListingKeepsThePageAlive;
begin
  const PageImages = ImagesOf(RotatedFile, 2);

  const Images = PageImages.Images;

  Assert.AreEqual<Integer>(1, Length(Images));
  Assert.AreEqual<Integer>(2, Images[0].PageIndex);
end;

procedure TPdfImagesTests.GetDataTooHigh;
begin
  FPageImages.GetData(1);
end;

procedure TPdfImagesTests.GetDataNegative;
begin
  FPageImages.GetData(-1);
end;

procedure TPdfImagesTests.TestGetDataRejectsABadIndex;
begin
  FPageImages := ImagesOf(RotatedFile, 0);

  Assert.WillRaise(GetDataTooHigh, EArgumentOutOfRangeException);
  Assert.WillRaise(GetDataNegative, EArgumentOutOfRangeException);
end;

end.
