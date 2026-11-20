// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests for Pdf4D.Model.Resources, Pdf4D.Model.FormXObject, Pdf4D.Model.ExtendedGraphicsState and the resources of the page
unit Pdf4D.Model.Resources.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Model.Document,
  Pdf4D.Model.Tests.Support;

type
  [TestFixture]
  TResourcesTests = class
  private
    const HelveticaObject = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>';
    const BrokenFont = '<< /Type /Font /Subtype /Type0 /DescendantFonts [] >>';

  private
    FModels: TModelTestDocuments;

    // Two pages with the same resources body. The font objects are 10 and up, the XObject streams 20 and up.
    function OpenDocument(const ResourcesBody: string; const FontObjects: array of string): TPDDocument;
    function Ascii(const Text: string): TBytes;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestFontIsCachedPerDocument;

    [Test]
    procedure TestDirectFontIsCachedPerDictionary;

    [Test]
    procedure TestBrokenFontGivesFalseAndLogs;

    [Test]
    procedure TestMissingFontGivesFalse;

    [Test]
    procedure TestImageXObjectDetected;

    [Test]
    procedure TestXObjectThatIsNoStreamIsSkippedAndLogged;

    [Test]
    procedure TestExtGStateAndPropertiesAreDictionaries;

    [Test]
    procedure TestResourcesWithoutDictionaryAreEmpty;

    [Test]
    procedure TestFormMatrixDefaultsToIdentity;

    [Test]
    procedure TestFormMatrixAndBBox;

    [Test]
    procedure TestTransparencyGroup;

    [Test]
    procedure TestTransparencyGroupAttributes;

    [Test]
    procedure TestFormResourcesVariants;

    [Test]
    procedure TestFormResourcesPointingBackDoNotRecurse;

    [Test]
    procedure TestExtGStateFont;

    [Test]
    [TestCase('NoFont', '/Font [ ]')]
    [TestCase('FontNoSize', '/Font [10 0 R]')]
    [TestCase('SizeIsName', '/Font [10 0 R /Big]')]
    [TestCase('FontIsNotAnArray', '/Font 10')]
    [TestCase('BrokenFont', '/Font [11 0 R 14]')]
    procedure TestExtGStateWithBadFontStructureDoesNotFail(const Entries: string);

    [Test]
    procedure TestExtGStateFontThatIsNoDictionaryClearsFontAndSetsSize;

    [Test]
    procedure TestExtGStateIgnoresOtherKeys;

    [Test]
    procedure TestPageHasContents;

    [Test]
    procedure TestPageResourcesAreLazyAndShared;

    [Test]
    procedure TestPageWithoutResourcesGivesEmptyResources;
  end;

implementation

uses
  Pdf4D.Common.Matrix,
  Pdf4D.Content.GraphicsState,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Font.Base,
  Pdf4D.Model.ExtendedGraphicsState,
  Pdf4D.Model.FormXObject,
  Pdf4D.Model.Rectangle,
  Pdf4D.Model.Resources,
  Pdf4D.Tests.PdfBuilder;

{ TResourcesTests }

procedure TResourcesTests.Setup;
begin
  FModels := TModelTestDocuments.Create;
end;

procedure TResourcesTests.TearDown;
begin
  FreeAndNil(FModels);
end;

function TResourcesTests.Ascii(const Text: string): TBytes;
begin
  Result := TEncoding.ASCII.GetBytes(Text);
end;

function TResourcesTests.OpenDocument(const ResourcesBody: string; const FontObjects: array of string): TPDDocument;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>');
  try
    const PageBody = Format('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Resources << %s >> >>', [ResourcesBody]);
    Builder.AddObject(3, PageBody);
    Builder.AddObject(4, PageBody);
    for var Index := 0 to High(FontObjects) do
    begin
      Builder.AddObject(10 + Index, FontObjects[Index]);
    end;
    Builder.AddStreamObject(20, '/Type /XObject /Subtype /Image /Width 1 /Height 1', Ascii('x'));
    Builder.AddStreamObject(21, '/Type /XObject /Subtype /Form /BBox [0 0 10 20]', Ascii('0 0 m'));
    Builder.AddStreamObject(22, '/Type /XObject /Subtype /Form /Matrix [2 0 0 3 4 5] /Group << /S /Transparency >>', Ascii('0 0 m'));
    Builder.AddStreamObject(23, '/Type /XObject /Subtype /Form /Resources 24 0 R', Ascii('/Fm1 Do'));
    Builder.AddObject(24, '<< /XObject << /Fm1 23 0 R >> >>');
    Builder.AddStreamObject(25, '/Type /XObject /Subtype /Form /Resources 7', Ascii('/Fm1 Do'));
    Builder.AddStreamObject(26, '/Type /XObject /Subtype /Form /Matrix [1 0 0]', Ascii('0 0 m'));
    Builder.AddStreamObject(27, '/Type /XObject /Subtype /Form /Group << /S /Transparency /I true /K true /CS /DeviceRGB >>', Ascii('0 0 m'));
    Result := FModels.Open(Builder);
  finally
    Builder.Free;
  end;
end;

procedure TResourcesTests.TestFontIsCachedPerDocument;
begin
  const Document = OpenDocument('/Font << /F1 10 0 R >>', [HelveticaObject]);

  var First: TPDFont;
  var Second: TPDFont;
  Assert.IsTrue(Document.Pages.Get(0).Resources.TryGetFont('F1', First));
  Assert.IsTrue(Document.Pages.Get(1).Resources.TryGetFont('F1', Second));

  Assert.AreSame(First, Second, 'two pages that refer to one font dictionary share one font');
end;

procedure TResourcesTests.TestDirectFontIsCachedPerDictionary;
begin
  const Document = OpenDocument(Format('/Font << /F1 %s >>', [HelveticaObject]), []);
  const Resources = Document.Pages.Get(0).Resources;

  var First: TPDFont;
  var Second: TPDFont;
  Assert.IsTrue(Resources.TryGetFont('F1', First));
  Assert.IsTrue(Resources.TryGetFont('F1', Second));

  Assert.AreSame(First, Second);
end;

procedure TResourcesTests.TestBrokenFontGivesFalseAndLogs;
begin
  const Document = OpenDocument('/Font << /F1 10 0 R >>', [BrokenFont]);
  const Resources = Document.Pages.Get(0).Resources;

  var Font: TPDFont;
  Assert.IsFalse(Resources.TryGetFont('F1', Font));
  Assert.IsNull(Font);
  Assert.IsTrue(FModels.HasLogLine('F1'), 'the failure is logged with the font name');

  const LogCount = FModels.LogLines.Count;
  Assert.IsFalse(Resources.TryGetFont('F1', Font));
  Assert.AreEqual(LogCount, FModels.LogLines.Count, 'a font that failed is not made and logged again');
end;

procedure TResourcesTests.TestMissingFontGivesFalse;
begin
  const Document = OpenDocument('/Font << /F1 12 /F2 (text) >>', []);
  const Resources = Document.Pages.Get(0).Resources;

  var Font: TPDFont;
  Assert.IsFalse(Resources.TryGetFont('F9', Font));
  Assert.IsFalse(Resources.TryGetFont('F1', Font), 'an entry that is no dictionary');
  Assert.IsFalse(Resources.TryGetFont('F2', Font));
end;

procedure TResourcesTests.TestImageXObjectDetected;
begin
  const Document = OpenDocument('/XObject << /Im1 20 0 R /Fm1 21 0 R >>', []);
  const Resources = Document.Pages.Get(0).Resources;

  Assert.IsTrue(Resources.IsImageXObject('Im1'));
  Assert.IsFalse(Resources.IsImageXObject('Fm1'));
  Assert.IsFalse(Resources.IsImageXObject('Missing'));

  var XObject: TCosStream;
  Assert.IsTrue(Resources.TryGetXObject('Fm1', XObject));
  Assert.IsNotNull(XObject);
end;

procedure TResourcesTests.TestXObjectThatIsNoStreamIsSkippedAndLogged;
begin
  const Document = OpenDocument('/XObject << /Bad << /Subtype /Form >> /Num 5 >>', []);
  const Resources = Document.Pages.Get(0).Resources;

  var XObject: TCosStream;
  Assert.IsFalse(Resources.TryGetXObject('Bad', XObject));
  Assert.IsNull(XObject);
  Assert.IsTrue(FModels.HasLogLine('Bad'));
  Assert.IsFalse(Resources.TryGetXObject('Num', XObject));
  Assert.IsFalse(Resources.IsImageXObject('Bad'));
  Assert.IsFalse(Resources.TryGetXObject('Missing', XObject));
end;

procedure TResourcesTests.TestExtGStateAndPropertiesAreDictionaries;
begin
  const Document = OpenDocument('/ExtGState << /GS1 << /LW 2 >> /GS2 5 >> /Properties << /MC0 << /Type /OC >> >>', []);
  const Resources = Document.Pages.Get(0).Resources;

  var Dictionary: TCosDictionary;
  Assert.IsTrue(Resources.TryGetExtGState('GS1', Dictionary));
  Assert.IsFalse(Resources.TryGetExtGState('GS2', Dictionary));
  Assert.IsFalse(Resources.TryGetExtGState('GS3', Dictionary));
  Assert.IsTrue(Resources.TryGetProperties('MC0', Dictionary));
  Assert.IsFalse(Resources.TryGetProperties('MC1', Dictionary));
end;

procedure TResourcesTests.TestResourcesWithoutDictionaryAreEmpty;
begin
  const Document = OpenDocument('', []);
  const Empty = TPDResources.Create(nil, Document.Context);
  try
    var Font: TPDFont;
    var Dictionary: TCosDictionary;
    var XObject: TCosStream;
    Assert.IsFalse(Empty.TryGetFont('F1', Font));
    Assert.IsFalse(Empty.TryGetXObject('X', XObject));
    Assert.IsFalse(Empty.IsImageXObject('X'));
    Assert.IsFalse(Empty.TryGetExtGState('G', Dictionary));
    Assert.IsFalse(Empty.TryGetProperties('P', Dictionary));
    Assert.IsNull(Empty.CosObject);
  finally
    Empty.Free;
  end;

  Assert.WillRaise(
    procedure
    begin
      TPDResources.Create(nil, nil);
    end,
    EArgumentNilException);
end;

procedure TResourcesTests.TestFormMatrixDefaultsToIdentity;
begin
  const Document = OpenDocument('/XObject << /Fm1 21 0 R /Fm6 26 0 R >>', []);
  const Resources = Document.Pages.Get(0).Resources;

  var Stream: TCosStream;
  Assert.IsTrue(Resources.TryGetXObject('Fm1', Stream));
  const Form = TPDFormXObject.Create(Stream);
  try
    Assert.IsTrue(Form.Matrix.IsEqual(TPdfMatrix.Identity));
    Assert.AreSame(Stream, Form.Stream);
  finally
    Form.Free;
  end;

  Assert.IsTrue(Resources.TryGetXObject('Fm6', Stream));
  const ShortMatrixForm = TPDFormXObject.Create(Stream);
  try
    Assert.IsTrue(ShortMatrixForm.Matrix.IsEqual(TPdfMatrix.Identity), 'a matrix with fewer than six numbers is the identity');
  finally
    ShortMatrixForm.Free;
  end;
end;

procedure TResourcesTests.TestFormMatrixAndBBox;
begin
  const Document = OpenDocument('/XObject << /Fm1 21 0 R /Fm2 22 0 R >>', []);
  const Resources = Document.Pages.Get(0).Resources;
  var Stream: TCosStream;
  var BBox: TPdfRectangle;

  Assert.IsTrue(Resources.TryGetXObject('Fm1', Stream));
  const WithBBox = TPDFormXObject.Create(Stream);
  try
    Assert.IsTrue(WithBBox.TryGetBBox(BBox));
    Assert.AreEqual(Double(20), Double(BBox.UpperRightY), 0.0001);
  finally
    WithBBox.Free;
  end;

  Assert.IsTrue(Resources.TryGetXObject('Fm2', Stream));
  const WithMatrix = TPDFormXObject.Create(Stream);
  try
    Assert.IsFalse(WithMatrix.TryGetBBox(BBox));
    Assert.AreEqual(Double(2), Double(WithMatrix.Matrix.ScaleX), 0.0001);
    Assert.AreEqual(Double(3), Double(WithMatrix.Matrix.ScaleY), 0.0001);
    Assert.AreEqual(Double(4), Double(WithMatrix.Matrix.TranslateX), 0.0001);
    Assert.AreEqual(Double(5), Double(WithMatrix.Matrix.TranslateY), 0.0001);
  finally
    WithMatrix.Free;
  end;
end;

procedure TResourcesTests.TestTransparencyGroupAttributes;
begin
  const Document = OpenDocument('/XObject << /Fm1 21 0 R /Fm2 22 0 R /Fm7 27 0 R >>', []);
  const Resources = Document.Pages.Get(0).Resources;
  var Stream: TCosStream;
  var Attributes: TPDTransparencyGroupAttributes;

  Assert.IsTrue(Resources.TryGetXObject('Fm7', Stream));
  const Full = TPDFormXObject.Create(Stream);
  try
    Assert.IsTrue(Full.TryGetGroup(Attributes));
    Assert.IsTrue(Attributes.IsIsolated);
    Assert.IsTrue(Attributes.IsKnockout);
    Assert.IsTrue(Assigned(Attributes.ColorSpace));
  finally
    Full.Free;
  end;

  Assert.IsTrue(Resources.TryGetXObject('Fm2', Stream));
  const Minimal = TPDFormXObject.Create(Stream);
  try
    Assert.IsTrue(Minimal.TryGetGroup(Attributes));
    Assert.IsFalse(Attributes.IsIsolated);
    Assert.IsFalse(Attributes.IsKnockout);
    Assert.IsFalse(Assigned(Attributes.ColorSpace));
  finally
    Minimal.Free;
  end;

  Assert.IsTrue(Resources.TryGetXObject('Fm1', Stream));
  const NoGroup = TPDFormXObject.Create(Stream);
  try
    Assert.IsFalse(NoGroup.TryGetGroup(Attributes));
  finally
    NoGroup.Free;
  end;
end;

procedure TResourcesTests.TestTransparencyGroup;
begin
  const Document = OpenDocument('/XObject << /Fm1 21 0 R /Fm2 22 0 R >>', []);
  const Resources = Document.Pages.Get(0).Resources;
  var Stream: TCosStream;

  Assert.IsTrue(Resources.TryGetXObject('Fm2', Stream));
  const Group = TPDFormXObject.Create(Stream);
  try
    Assert.IsTrue(Group.IsTransparencyGroup);
  finally
    Group.Free;
  end;

  Assert.IsTrue(Resources.TryGetXObject('Fm1', Stream));
  const NoGroup = TPDFormXObject.Create(Stream);
  try
    Assert.IsFalse(NoGroup.IsTransparencyGroup);
  finally
    NoGroup.Free;
  end;
end;

procedure TResourcesTests.TestFormResourcesVariants;
begin
  const Document = OpenDocument('/XObject << /Fm1 21 0 R /Fm3 23 0 R /Fm5 25 0 R >>', []);
  const Resources = Document.Pages.Get(0).Resources;
  var Stream: TCosStream;
  var FormResources: TCosDictionary;

  Assert.IsTrue(Resources.TryGetXObject('Fm1', Stream));
  const Missing = TPDFormXObject.Create(Stream);
  try
    Assert.IsFalse(Missing.TryGetResources(FormResources));
    Assert.IsFalse(Missing.HasEmptyResources, 'no entry: the engine uses the resources of the page');
  finally
    Missing.Free;
  end;

  Assert.IsTrue(Resources.TryGetXObject('Fm3', Stream));
  const WithResources = TPDFormXObject.Create(Stream);
  try
    Assert.IsTrue(WithResources.TryGetResources(FormResources));
    Assert.IsFalse(WithResources.HasEmptyResources);
  finally
    WithResources.Free;
  end;

  Assert.IsTrue(Resources.TryGetXObject('Fm5', Stream));
  const NotADictionary = TPDFormXObject.Create(Stream);
  try
    Assert.IsFalse(NotADictionary.TryGetResources(FormResources));
    Assert.IsTrue(NotADictionary.HasEmptyResources, 'an entry that is no dictionary counts as empty resources');
  finally
    NotADictionary.Free;
  end;
end;

procedure TResourcesTests.TestFormResourcesPointingBackDoNotRecurse;
begin
  const Document = OpenDocument('/XObject << /Fm3 23 0 R >>', []);
  var Stream: TCosStream;
  Assert.IsTrue(Document.Pages.Get(0).Resources.TryGetXObject('Fm3', Stream));

  const Form = TPDFormXObject.Create(Stream);
  try
    var FormResourcesDictionary: TCosDictionary;
    Assert.IsTrue(Form.TryGetResources(FormResourcesDictionary));
    const FormResources = TPDResources.Create(FormResourcesDictionary, Document.Context);
    try
      var Again: TCosStream;
      Assert.IsTrue(FormResources.TryGetXObject('Fm1', Again));
      Assert.AreSame(Stream, Again, 'the form resources lead back to the same form, which is a lookup and no recursion');
    finally
      FormResources.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TResourcesTests.TestExtGStateFont;
begin
  const Document = OpenDocument('/Font << /F1 10 0 R >> /ExtGState << /GS1 << /Font [10 0 R 14] /LW 3 /CA 0.5 >> >>', [HelveticaObject]);
  const Resources = Document.Pages.Get(0).Resources;
  var Dictionary: TCosDictionary;
  Assert.IsTrue(Resources.TryGetExtGState('GS1', Dictionary));
  const State = TPDGraphicsState.Create;
  const ExtGState = TPDExtendedGraphicsState.Create(Dictionary);
  try
    ExtGState.CopyIntoGraphicsState(State, Resources);

    Assert.AreEqual(Double(14), Double(State.TextState.FontSize), 0.0001);
    var Font: TPDFont;
    Assert.IsTrue(Resources.TryGetFont('F1', Font));
    Assert.AreSame(Font, State.TextState.Font, 'the font of object 10, from the document cache');
  finally
    ExtGState.Free;
    State.Free;
  end;
end;

procedure TResourcesTests.TestExtGStateWithBadFontStructureDoesNotFail(const Entries: string);
begin
  const Document = OpenDocument(Format('/ExtGState << /GS1 << %s >> >>', [Entries]), [HelveticaObject, BrokenFont]);
  const Resources = Document.Pages.Get(0).Resources;
  var Dictionary: TCosDictionary;
  Assert.IsTrue(Resources.TryGetExtGState('GS1', Dictionary));
  const State = TPDGraphicsState.Create;
  const ExtGState = TPDExtendedGraphicsState.Create(Dictionary);
  try
    State.TextState.FontSize := 9;

    ExtGState.CopyIntoGraphicsState(State, Resources);

    Assert.AreEqual(Double(9), Double(State.TextState.FontSize), 0.0001, 'a bad size leaves the size alone');
  finally
    ExtGState.Free;
    State.Free;
  end;
end;

procedure TResourcesTests.TestExtGStateFontThatIsNoDictionaryClearsFontAndSetsSize;
begin
  const Document = OpenDocument('/ExtGState << /GS1 << /Font [5 14] >> >>', [HelveticaObject]);
  const Resources = Document.Pages.Get(0).Resources;
  var Dictionary: TCosDictionary;
  Assert.IsTrue(Resources.TryGetExtGState('GS1', Dictionary));
  const State = TPDGraphicsState.Create;
  const ExtGState = TPDExtendedGraphicsState.Create(Dictionary);
  try
    var Font: TPDFont;
    Assert.IsTrue(Document.Pages.Get(0).Resources.TryGetExtGState('GS1', Dictionary));
    State.TextState.Font := nil;

    ExtGState.CopyIntoGraphicsState(State, Resources);

    Assert.IsNull(State.TextState.Font, 'PDFBox sets a null font, the engine then uses its default');
    Assert.AreEqual(Double(14), Double(State.TextState.FontSize), 0.0001);
    Assert.IsFalse(Resources.TryGetFont('F1', Font));
  finally
    ExtGState.Free;
    State.Free;
  end;
end;

procedure TResourcesTests.TestExtGStateIgnoresOtherKeys;
begin
  const Document = OpenDocument('/ExtGState << /GS1 << /LW 3 /LC 1 /D [[2] 0] /CA 0.5 /BM /Multiply >> >>', []);
  var Dictionary: TCosDictionary;
  Assert.IsTrue(Document.Pages.Get(0).Resources.TryGetExtGState('GS1', Dictionary));
  const State = TPDGraphicsState.Create;
  const ExtGState = TPDExtendedGraphicsState.Create(Dictionary);
  try
    State.TextState.FontSize := 12;

    ExtGState.CopyIntoGraphicsState(State, Document.Pages.Get(0).Resources);

    Assert.AreEqual(Double(12), Double(State.TextState.FontSize), 0.0001);
    Assert.IsNull(State.TextState.Font);
  finally
    ExtGState.Free;
    State.Free;
  end;
end;

procedure TResourcesTests.TestPageHasContents;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R 4 0 R 5 0 R 6 0 R 7 0 R] /Count 5 >>');
  try
    Builder.AddObject(3, '<< /Type /Page /Parent 2 0 R /Contents 10 0 R >>');
    Builder.AddObject(4, '<< /Type /Page /Parent 2 0 R /Contents 11 0 R >>');
    Builder.AddObject(5, '<< /Type /Page /Parent 2 0 R /Contents [10 0 R] >>');
    Builder.AddObject(6, '<< /Type /Page /Parent 2 0 R /Contents [] >>');
    Builder.AddObject(7, '<< /Type /Page /Parent 2 0 R >>');
    Builder.AddStreamObject(10, '', Ascii('q Q'));
    Builder.AddStreamObject(11, '', nil);
    const Document = FModels.Open(Builder);

    Assert.IsTrue(Document.Pages.Get(0).HasContents, 'a stream with data');
    Assert.IsFalse(Document.Pages.Get(1).HasContents, 'an empty stream');
    Assert.IsTrue(Document.Pages.Get(2).HasContents, 'an array with an item');
    Assert.IsFalse(Document.Pages.Get(3).HasContents, 'an empty array');
    Assert.IsFalse(Document.Pages.Get(4).HasContents, 'no contents');
  finally
    Builder.Free;
  end;
end;

procedure TResourcesTests.TestPageResourcesAreLazyAndShared;
begin
  const Document = OpenDocument('/Font << /F1 10 0 R >>', [HelveticaObject]);
  const Page = Document.Pages.Get(0);

  Assert.AreSame(Page.Resources, Page.Resources, 'made once, owned by the page');
  var PageResources: TCosDictionary;
  Assert.IsTrue(Page.TryGetResources(PageResources));
  Assert.AreSame(PageResources, Page.Resources.CosObject);
end;

procedure TResourcesTests.TestPageWithoutResourcesGivesEmptyResources;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  try
    Builder.AddObject(3, '<< /Type /Page /Parent 2 0 R >>');
    const Page = FModels.Open(Builder).Pages.Get(0);

    var Font: TPDFont;
    Assert.IsNotNull(Page.Resources);
    Assert.IsNull(Page.Resources.CosObject);
    Assert.IsFalse(Page.Resources.TryGetFont('F1', Font));
  finally
    Builder.Free;
  end;
end;

end.
