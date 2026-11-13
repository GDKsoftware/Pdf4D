// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
unit Pdf4D.Model.Page.Tests;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Model.Page,
  Pdf4D.Model.Rectangle,
  Pdf4D.Model.Tests.Support,
  Pdf4D.Tests.PdfBuilder;

type
  [TestFixture]
  TPageTests = class
  private
    FDocuments: TModelTestDocuments;

    // A page tree root with these entries and one page below it with the page entries
    function OnePage(const RootEntries, PageEntries: string): TPDPage;
    procedure AssertBox(const Expected: array of Single; const Actual: TPdfRectangle);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestInheritedMediaBoxAndRotate;

    [Test]
    procedure TestMediaBoxDefaultsToLetter;

    [Test]
    procedure TestMediaBoxIsNormalized;

    [Test]
    procedure TestShortAndHugeBoxValues;

    [Test]
    procedure TestCropBoxClippedToMediaBox;

    [Test]
    procedure TestCropBoxWithoutOverlapIsNotNormalized;

    [Test]
    procedure TestCropBoxDefaultsToMediaBoxAndIsInherited;

    [Test]
    procedure TestOtherBoxesDefaultToCropBoxAndAreNotInherited;

    [Test]
    procedure TestOtherBoxesAreClippedToMediaBox;

    [Test]
    procedure TestRotationIsNormalized;

    [Test]
    procedure TestUserUnit;

    [Test]
    procedure TestResourcesAreInherited;

    [Test]
    procedure TestContentStreams;

    [Test]
    procedure TestParentCycleEndsTheSearch;

    [Test]
    procedure TestParentThatIsNoPagesNodeIsNotInherited;

    [Test]
    procedure TestShortParentKeyIsUsedWithoutParent;
  end;

implementation

uses
  System.Classes,
  Pdf4D.Cos.Dictionary;

{ TPageTests }

procedure TPageTests.Setup;
begin
  FDocuments := TModelTestDocuments.Create;
end;

procedure TPageTests.TearDown;
begin
  FDocuments.Free;
end;

function TPageTests.OnePage(const RootEntries, PageEntries: string): TPDPage;
begin
  const Builder = TModelTestDocuments.NewBuilder(Format('<< /Type /Pages /Kids [3 0 R] /Count 1 %s >>', [RootEntries]));
  try
    Builder.AddObject(3, Format('<< /Type /Page /Parent 2 0 R %s >>', [PageEntries]));
    Result := FDocuments.Open(Builder).Pages.Get(0);
  finally
    Builder.Free;
  end;
end;

procedure TPageTests.AssertBox(const Expected: array of Single; const Actual: TPdfRectangle);
begin
  Assert.AreEqual<Single>(Expected[0], Actual.LowerLeftX, 'llx');
  Assert.AreEqual<Single>(Expected[1], Actual.LowerLeftY, 'lly');
  Assert.AreEqual<Single>(Expected[2], Actual.UpperRightX, 'urx');
  Assert.AreEqual<Single>(Expected[3], Actual.UpperRightY, 'ury');
end;

procedure TPageTests.TestInheritedMediaBoxAndRotate;
begin
  const Page = OnePage('/MediaBox [0 0 300 400] /Rotate 450', '');

  AssertBox([0, 0, 300, 400], Page.MediaBox);
  Assert.AreEqual(90, Page.Rotation);
  Assert.AreEqual<Single>(300, Page.MediaBox.Width);
  Assert.AreEqual<Single>(400, Page.MediaBox.Height);
end;

procedure TPageTests.TestMediaBoxDefaultsToLetter;
begin
  AssertBox([0, 0, 612, 792], OnePage('', '').MediaBox);
end;

procedure TPageTests.TestMediaBoxIsNormalized;
begin
  AssertBox([0, 10, 300, 400], OnePage('', '/MediaBox [300 400 0 10]').MediaBox);
end;

procedure TPageTests.TestShortAndHugeBoxValues;
begin
  // A missing value is 0, an extra value is ignored, a huge value is cut at the Integer limit
  AssertBox([0, 0, 5, 0], OnePage('', '/MediaBox [0 0 5]').MediaBox);
  AssertBox([0, 0, 1, 2], OnePage('', '/MediaBox [0 0 1 2 3 4]').MediaBox);
  AssertBox([0, -2147483648.0, 2147483648.0, 0], OnePage('', '/MediaBox [0 -100000000000 100000000000 0]').MediaBox);
  AssertBox([0, 0, 7, 0], OnePage('', '/MediaBox [0 (a) 7 /b]').MediaBox);
end;

procedure TPageTests.TestCropBoxClippedToMediaBox;
begin
  const Page = OnePage('', '/MediaBox [0 0 100 100] /CropBox [-10 10 50 200]');

  AssertBox([0, 10, 50, 100], Page.CropBox);
end;

procedure TPageTests.TestCropBoxWithoutOverlapIsNotNormalized;
begin
  // As in PDFBox, the clipped box of a crop box outside the media box has its corners the wrong way round
  const Page = OnePage('', '/MediaBox [0 0 100 100] /CropBox [200 200 300 300]');

  AssertBox([200, 200, 100, 100], Page.CropBox);
end;

procedure TPageTests.TestCropBoxDefaultsToMediaBoxAndIsInherited;
begin
  AssertBox([0, 0, 100, 50], OnePage('/MediaBox [0 0 100 50]', '').CropBox);
  AssertBox([10, 10, 20, 20], OnePage('/MediaBox [0 0 100 50] /CropBox [10 10 20 20]', '').CropBox);
end;

procedure TPageTests.TestOtherBoxesDefaultToCropBoxAndAreNotInherited;
begin
  const Page = OnePage('/MediaBox [0 0 100 100] /CropBox [5 5 95 95] /BleedBox [1 1 99 99] /TrimBox [2 2 98 98] /ArtBox [3 3 97 97]', '');

  AssertBox([5, 5, 95, 95], Page.BleedBox);
  AssertBox([5, 5, 95, 95], Page.TrimBox);
  AssertBox([5, 5, 95, 95], Page.ArtBox);
end;

procedure TPageTests.TestOtherBoxesAreClippedToMediaBox;
begin
  const Page = OnePage('/MediaBox [0 0 100 100]', '/BleedBox [-5 -5 50 50] /TrimBox [10 10 150 150] /ArtBox [20 20 30 30]');

  AssertBox([0, 0, 50, 50], Page.BleedBox);
  AssertBox([10, 10, 100, 100], Page.TrimBox);
  AssertBox([20, 20, 30, 30], Page.ArtBox);
end;

procedure TPageTests.TestRotationIsNormalized;
begin
  Assert.AreEqual(0, OnePage('', '').Rotation);
  Assert.AreEqual(90, OnePage('', '/Rotate 90').Rotation);
  Assert.AreEqual(270, OnePage('', '/Rotate -90').Rotation);
  Assert.AreEqual(0, OnePage('', '/Rotate 360').Rotation);
  Assert.AreEqual(180, OnePage('', '/Rotate -540').Rotation);
  Assert.AreEqual(90, OnePage('', '/Rotate 450').Rotation);
  // Not a multiple of 90
  Assert.AreEqual(0, OnePage('', '/Rotate 45').Rotation);
  Assert.AreEqual(0, OnePage('', '/Rotate 100').Rotation);
  // A real number counts by its integer part
  Assert.AreEqual(90, OnePage('', '/Rotate 90.7').Rotation);
  Assert.AreEqual(0, OnePage('', '/Rotate 89.9').Rotation);
  // Not a number
  Assert.AreEqual(0, OnePage('', '/Rotate (90)').Rotation);
  // The page's own value wins over the inherited one
  Assert.AreEqual(180, OnePage('/Rotate 90', '/Rotate 180').Rotation);
end;

procedure TPageTests.TestUserUnit;
begin
  Assert.AreEqual<Single>(1, OnePage('', '').UserUnit);
  Assert.AreEqual<Single>(2.5, OnePage('', '/UserUnit 2.5').UserUnit);
  Assert.AreEqual<Single>(1, OnePage('', '/UserUnit 0').UserUnit);
  Assert.AreEqual<Single>(1, OnePage('', '/UserUnit -3').UserUnit);
  // Not inherited
  Assert.AreEqual<Single>(1, OnePage('/UserUnit 4', '').UserUnit);
end;

procedure TPageTests.TestResourcesAreInherited;
begin
  var Resources: TCosDictionary;
  Assert.IsTrue(OnePage('/Resources << /ProcSet [/PDF] >>', '').TryGetResources(Resources));
  Assert.IsTrue(Resources.ContainsKey('ProcSet'));

  Assert.IsFalse(OnePage('', '').TryGetResources(Resources));
  Assert.IsNull(Resources);
  // An entry that is no dictionary is no resources
  Assert.IsFalse(OnePage('', '/Resources 5').TryGetResources(Resources));
end;

procedure TPageTests.TestContentStreams;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R 4 0 R 5 0 R] /Count 3 >>');
  try
    Builder.AddObject(3, '<< /Type /Page /Parent 2 0 R /Contents 6 0 R >>');
    Builder.AddObject(4, '<< /Type /Page /Parent 2 0 R /Contents [6 0 R 7 0 R 99 0 R 5] >>');
    Builder.AddObject(5, '<< /Type /Page /Parent 2 0 R >>');
    Builder.AddStreamObject(6, '', TEncoding.ASCII.GetBytes('q Q'));
    Builder.AddStreamObject(7, '', TEncoding.ASCII.GetBytes('BT ET'));
    const Document = FDocuments.Open(Builder);

    Assert.AreEqual<Integer>(1, Length(Document.Pages.Get(0).ContentStreams));
    // The missing object and the integer are left out
    Assert.AreEqual<Integer>(2, Length(Document.Pages.Get(1).ContentStreams));
    Assert.AreEqual<Integer>(0, Length(Document.Pages.Get(2).ContentStreams));
  finally
    Builder.Free;
  end;
end;

procedure TPageTests.TestParentCycleEndsTheSearch;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R] /Count 1 /Parent 4 0 R >>');
  try
    Builder.AddObject(4, '<< /Type /Pages /Parent 2 0 R >>');
    Builder.AddObject(3, '<< /Type /Page /Parent 2 0 R >>');
    const Page = FDocuments.Open(Builder).Pages.Get(0);

    AssertBox([0, 0, 612, 792], Page.MediaBox);
    Assert.AreEqual(0, Page.Rotation);
  finally
    Builder.Free;
  end;
end;

procedure TPageTests.TestParentThatIsNoPagesNodeIsNotInherited;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  try
    Builder.AddObject(3, '<< /Type /Page /Parent 4 0 R >>');
    Builder.AddObject(4, '<< /Type /Other /Rotate 90 >>');
    const Page = FDocuments.Open(Builder).Pages.Get(0);

    Assert.AreEqual(0, Page.Rotation);
  finally
    Builder.Free;
  end;
end;

procedure TPageTests.TestShortParentKeyIsUsedWithoutParent;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R] /Count 1 /Rotate 270 >>');
  try
    Builder.AddObject(3, '<< /Type /Page /P 2 0 R >>');
    const Page = FDocuments.Open(Builder).Pages.Get(0);

    Assert.AreEqual(270, Page.Rotation);
  finally
    Builder.Free;
  end;
end;

end.
