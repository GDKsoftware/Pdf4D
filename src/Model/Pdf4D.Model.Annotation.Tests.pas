// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Model.Annotation.Tests;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Model.Annotation,
  Pdf4D.Model.Page,
  Pdf4D.Model.Tests.Support;

type
  [TestFixture]
  TAnnotationTests = class
  private
    FDocuments: TModelTestDocuments;

    // The page 3 holds Annots, the objects from 5 on are the Extra objects: number and body, in pairs
    function PageWithAnnotations(const Annots: string; const Extra: TArray<string>): TPDPage;
    function OnlyAnnotation(const Entries: string; const Extra: TArray<string>): TPDAnnotation;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestSubtypeAndRect;

    [Test]
    procedure TestRectNeedsFourNumbers;

    [Test]
    procedure TestFlags;

    [Test]
    procedure TestFlagsOfNonNumberAreZero;

    [Test]
    [TestCase('Square', 'Square,True')]
    [TestCase('Widget', 'Widget,True')]
    [TestCase('Stamp', 'Stamp,True')]
    [TestCase('PolyLine', 'PolyLine,True')]
    [TestCase('Sound', 'Sound,True')]
    [TestCase('Movie', 'Movie,False')]
    [TestCase('Screen', 'Screen,False')]
    [TestCase('Redact', 'Redact,False')]
    [TestCase('Lowercase', 'square,False')]
    procedure TestIsKnownType(const SubType: string; const Expected: Boolean);

    [Test]
    procedure TestWithoutSubtypeIsUnknown;

    [Test]
    procedure TestNormalAppearanceStream;

    [Test]
    procedure TestNormalAppearanceFollowsAppearanceState;

    [Test]
    procedure TestSubdictionaryWithoutStateHasNoAppearance;

    [Test]
    procedure TestSubdictionaryEntryThatIsNoStreamIsNoAppearance;

    [Test]
    procedure TestNoAppearance;

    [Test]
    procedure TestOptionalContent;

    [Test]
    procedure TestAnnotationsSkipEntriesThatAreNoDictionary;

    [Test]
    procedure TestAnnotationsAreLimited;

    [Test]
    procedure TestPageWithoutAnnotations;
  end;

implementation

uses
  Pdf4D.Cos.Dictionary,
  Pdf4D.Model.Rectangle,
  Pdf4D.Tests.PdfBuilder;

{ TAnnotationTests }

procedure TAnnotationTests.Setup;
begin
  FDocuments := TModelTestDocuments.Create;
end;

procedure TAnnotationTests.TearDown;
begin
  FDocuments.Free;
end;

function TAnnotationTests.PageWithAnnotations(const Annots: string; const Extra: TArray<string>): TPDPage;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  try
    Builder.AddObject(3, Format('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] %s >>', [Annots]));
    var Index := 0;
    while Index < Length(Extra) do
    begin
      Builder.AddObject(StrToInt(Extra[Index]), Extra[Index + 1]);
      Inc(Index, 2);
    end;
    Result := FDocuments.Open(Builder).Pages.Get(0);
  finally
    Builder.Free;
  end;
end;

function TAnnotationTests.OnlyAnnotation(const Entries: string; const Extra: TArray<string>): TPDAnnotation;
begin
  const Page = PageWithAnnotations('/Annots [5 0 R]', ['5', Format('<< /Type /Annot %s >>', [Entries])] + Extra);
  const Annotations = Page.Annotations;
  try
    Assert.AreEqual<Integer>(1, Annotations.Count);
    Result := Annotations.Extract(Annotations[0]);
  finally
    Annotations.Free;
  end;
end;

procedure TAnnotationTests.TestSubtypeAndRect;
begin
  const Annotation = OnlyAnnotation('/Subtype /Square /Rect [100 110 20 30]', []);
  try
    Assert.AreEqual('Square', Annotation.SubType);
    Assert.IsTrue(Annotation.HasRect);
    // The corners are put in order, like PDRectangle
    Assert.AreEqual<Single>(20, Annotation.Rect.LowerLeftX);
    Assert.AreEqual<Single>(30, Annotation.Rect.LowerLeftY);
    Assert.AreEqual<Single>(100, Annotation.Rect.UpperRightX);
    Assert.AreEqual<Single>(110, Annotation.Rect.UpperRightY);
  finally
    Annotation.Free;
  end;
end;

procedure TAnnotationTests.TestRectNeedsFourNumbers;
begin
  for var Entries in ['/Subtype /Square', '/Subtype /Square /Rect [1 2 3]', '/Subtype /Square /Rect [1 2 3 4 5]', '/Subtype /Square /Rect [1 2 3 /a]',
                      '/Subtype /Square /Rect 7'] do
  begin
    const Annotation = OnlyAnnotation(Entries, []);
    try
      Assert.IsFalse(Annotation.HasRect, Entries);
    finally
      Annotation.Free;
    end;
  end;
end;

procedure TAnnotationTests.TestFlags;
begin
  // Invisible 1, Hidden 2, Print 4, NoZoom 8, NoRotate 16, NoView 32
  const Annotation = OnlyAnnotation('/Subtype /Square /F 55', []);
  try
    Assert.AreEqual<Integer>(55, Annotation.Flags);
    Assert.IsTrue(Annotation.IsInvisible);
    Assert.IsTrue(Annotation.IsHidden);
    Assert.IsTrue(Annotation.IsPrinted);
    Assert.IsTrue(Annotation.IsNoRotate);
    Assert.IsTrue(Annotation.IsNoView);
  finally
    Annotation.Free;
  end;

  const Plain = OnlyAnnotation('/Subtype /Square /F 8', []);
  try
    Assert.IsFalse(Plain.IsInvisible);
    Assert.IsFalse(Plain.IsHidden);
    Assert.IsFalse(Plain.IsPrinted);
    Assert.IsFalse(Plain.IsNoRotate);
    Assert.IsFalse(Plain.IsNoView);
  finally
    Plain.Free;
  end;
end;

procedure TAnnotationTests.TestFlagsOfNonNumberAreZero;
begin
  const Annotation = OnlyAnnotation('/Subtype /Square /F /Hidden', []);
  try
    Assert.AreEqual<Integer>(0, Annotation.Flags);
    Assert.IsFalse(Annotation.IsHidden);
  finally
    Annotation.Free;
  end;
end;

procedure TAnnotationTests.TestIsKnownType(const SubType: string; const Expected: Boolean);
begin
  const Annotation = OnlyAnnotation(Format('/Subtype /%s', [SubType]), []);
  try
    Assert.AreEqual(Expected, Annotation.IsKnownType);
  finally
    Annotation.Free;
  end;
end;

procedure TAnnotationTests.TestWithoutSubtypeIsUnknown;
begin
  const Annotation = OnlyAnnotation('/Rect [0 0 1 1]', []);
  try
    Assert.AreEqual('', Annotation.SubType);
    Assert.IsFalse(Annotation.IsKnownType);
  finally
    Annotation.Free;
  end;
end;

procedure TAnnotationTests.TestNormalAppearanceStream;
begin
  const Annotation = OnlyAnnotation('/Subtype /Square /AP << /N 6 0 R >>', ['6', '<< /Marker 1 >>']);
  try
    var Appearance: TCosStream;
    // 6 is a plain dictionary here, not a stream: that is a subdictionary without state, so no appearance
    Assert.IsFalse(Annotation.TryGetNormalAppearance(Appearance));
  finally
    Annotation.Free;
  end;

  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  try
    Builder.AddObject(3, '<< /Type /Page /Parent 2 0 R /Annots [5 0 R] >>');
    Builder.AddObject(5, '<< /Type /Annot /Subtype /Square /AP << /N 6 0 R >> >>');
    Builder.AddStreamObject(6, '/Marker 7', TEncoding.ASCII.GetBytes('0 0 1 1 re f'));
    const Annotations = FDocuments.Open(Builder).Pages.Get(0).Annotations;
    try
      var Appearance: TCosStream;
      Assert.IsTrue(Annotations[0].TryGetNormalAppearance(Appearance));
      Assert.AreEqual<Integer>(7, Appearance.GetInt('Marker', 0));
    finally
      Annotations.Free;
    end;
  finally
    Builder.Free;
  end;
end;

procedure TAnnotationTests.TestNormalAppearanceFollowsAppearanceState;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  try
    Builder.AddObject(3, '<< /Type /Page /Parent 2 0 R /Annots [5 0 R] >>');
    Builder.AddObject(5, '<< /Type /Annot /Subtype /Widget /AS /On /AP << /N << /On 6 0 R /Off 7 0 R >> >> >>');
    Builder.AddStreamObject(6, '/Marker 1', TEncoding.ASCII.GetBytes('q Q'));
    Builder.AddStreamObject(7, '/Marker 2', TEncoding.ASCII.GetBytes('q Q'));
    const Annotations = FDocuments.Open(Builder).Pages.Get(0).Annotations;
    try
      var Appearance: TCosStream;
      Assert.IsTrue(Annotations[0].TryGetNormalAppearance(Appearance));
      Assert.AreEqual<Integer>(1, Appearance.GetInt('Marker', 0));
    finally
      Annotations.Free;
    end;
  finally
    Builder.Free;
  end;
end;

procedure TAnnotationTests.TestSubdictionaryWithoutStateHasNoAppearance;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  try
    Builder.AddObject(3, '<< /Type /Page /Parent 2 0 R /Annots [5 0 R 8 0 R] >>');
    Builder.AddObject(5, '<< /Type /Annot /Subtype /Widget /AP << /N << /On 6 0 R >> >> >>');
    Builder.AddObject(8, '<< /Type /Annot /Subtype /Widget /AS /Missing /AP << /N << /On 6 0 R >> >> >>');
    Builder.AddStreamObject(6, '', TEncoding.ASCII.GetBytes('q Q'));
    const Annotations = FDocuments.Open(Builder).Pages.Get(0).Annotations;
    try
      var Appearance: TCosStream;
      Assert.AreEqual<Integer>(2, Annotations.Count);
      Assert.IsFalse(Annotations[0].TryGetNormalAppearance(Appearance), 'no /AS');
      Assert.IsFalse(Annotations[1].TryGetNormalAppearance(Appearance), 'state without stream');
    finally
      Annotations.Free;
    end;
  finally
    Builder.Free;
  end;
end;

procedure TAnnotationTests.TestSubdictionaryEntryThatIsNoStreamIsNoAppearance;
begin
  // PDFBOX-1599: the file has /null as entry
  const Annotation = OnlyAnnotation('/Subtype /Widget /AS /On /AP << /N << /On null /Off 1 >> >>', []);
  try
    var Appearance: TCosStream;
    Assert.IsFalse(Annotation.TryGetNormalAppearance(Appearance));
  finally
    Annotation.Free;
  end;
end;

procedure TAnnotationTests.TestNoAppearance;
begin
  for var Entries in ['/Subtype /Square', '/Subtype /Square /AP 5', '/Subtype /Square /AP << /R 5 >>', '/Subtype /Square /AP << /N 5 >>'] do
  begin
    const Annotation = OnlyAnnotation(Entries, []);
    try
      var Appearance: TCosStream;
      Assert.IsFalse(Annotation.TryGetNormalAppearance(Appearance), Entries);
    finally
      Annotation.Free;
    end;
  end;
end;

procedure TAnnotationTests.TestOptionalContent;
begin
  const Annotation = OnlyAnnotation('/Subtype /Square /OC 6 0 R', ['6', '<< /Type /OCG /Name (A) >>']);
  try
    var Value: TCosDictionary;
    Assert.IsTrue(Annotation.TryGetOptionalContent(Value));
    Assert.AreEqual('A', Value.GetString('Name', ''));
  finally
    Annotation.Free;
  end;

  const Without = OnlyAnnotation('/Subtype /Square /OC 5', []);
  try
    var Value: TCosDictionary;
    Assert.IsFalse(Without.TryGetOptionalContent(Value));
  finally
    Without.Free;
  end;
end;

procedure TAnnotationTests.TestAnnotationsSkipEntriesThatAreNoDictionary;
begin
  const Page = PageWithAnnotations('/Annots [5 0 R 42 null /Name 7 6 0 R (text) 99 0 R]', ['5', '<< /Subtype /Square >>', '6', '<< /Subtype /Circle >>']);
  const Annotations = Page.Annotations;
  try
    Assert.AreEqual<Integer>(2, Annotations.Count);
    Assert.AreEqual('Square', Annotations[0].SubType);
    Assert.AreEqual('Circle', Annotations[1].SubType);
  finally
    Annotations.Free;
  end;
end;

procedure TAnnotationTests.TestAnnotationsAreLimited;
begin
  const Page = PageWithAnnotations('/Annots [5 0 R 5 0 R 5 0 R 5 0 R 5 0 R]', ['5', '<< /Subtype /Square >>']);
  const Annotations = Page.Annotations(3);
  try
    Assert.AreEqual<Integer>(3, Annotations.Count);
  finally
    Annotations.Free;
  end;
end;

procedure TAnnotationTests.TestPageWithoutAnnotations;
begin
  for var Entry in ['', '/Annots 5', '/Annots << >>'] do
  begin
    const Annotations = PageWithAnnotations(Entry, []).Annotations;
    try
      Assert.AreEqual<Integer>(0, Annotations.Count, Entry);
    finally
      Annotations.Free;
    end;
  end;
end;

end.
