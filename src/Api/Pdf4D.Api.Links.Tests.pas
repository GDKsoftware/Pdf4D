// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Api.Links.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Api.Page.Interfaces,
  Pdf4D.Tests.PdfBuilder;

type
  [TestFixture]
  TApiLinksTests = class
  private
    FStreams: TObjectList<TStream>;
    FLogLines: TList<string>;

    function Load(const Data: TBytes): IPdfDocument;
    function LoadBuilder(const Builder: TTestPdfBuilder): IPdfDocument;
    // Two pages (objects 3 and 5), the annotations are the objects 20 and up and all on page 0
    function LinksOf(const Annotations: TArray<string>; const CatalogExtra: string = ''): TArray<TPdfLink>;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestGoToLinkResolvesPage;

    [Test]
    procedure TestUriLink;

    [Test]
    procedure TestPageWithoutLinks;

    [Test]
    procedure TestNamedDestinationResolves;

    [Test]
    procedure TestGoToActionResolvesPage;

    [Test]
    procedure TestQuadPointsWinOverRect;

    [Test]
    procedure TestInvalidQuadPointsFallBackToRect;

    [Test]
    procedure TestBrokenLinksAreSkipped;
    [Test]
    procedure TestHugeQuadPointsAreLimited;

    [Test]
    procedure TestLinkWithoutDestinationAndAction;

    [Test]
    procedure TestOtherActionsGiveKindOther;

    [Test]
    procedure TestNonLinkAnnotationsAreIgnored;

    [Test]
    procedure TestLinksKeepAnnotsOrder;
  end;

implementation

uses
  System.Types,
  Pdf4D.Api.Document,
  Pdf4D.Common.Defines,
  Pdf4D.Model.Tests.Support,
  Pdf4D.Tests.ViewerDocuments;

const
  Tolerance = 0.001;
  FirstAnnotationObject = 20;
  PageFormat = '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] %s >>';

{ TApiLinksTests }

procedure TApiLinksTests.Setup;
begin
  FStreams := TObjectList<TStream>.Create(True);
  FLogLines := TList<string>.Create;
end;

procedure TApiLinksTests.TearDown;
begin
  FLogLines.Free;
  FStreams.Free;
end;

function TApiLinksTests.Load(const Data: TBytes): IPdfDocument;
begin
  const Stream = TBytesStream.Create(Data);
  FStreams.Add(Stream);

  var Options := TPdfLoadOptions.Default;
  Options.OnLog :=
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      FLogLines.Add(Message);
    end;
  Result := TPdfDocument.Load(Stream, Options);
end;

function TApiLinksTests.LoadBuilder(const Builder: TTestPdfBuilder): IPdfDocument;
begin
  try
    Result := Load(Builder.Build(TXrefStyle.Table));
  finally
    Builder.Free;
  end;
end;

function TApiLinksTests.LinksOf(const Annotations: TArray<string>; const CatalogExtra: string): TArray<TPdfLink>;
begin
  const Builder = TTestPdfBuilder.Create;
  try
    Builder.AddObject(1, Format('<< /Type /Catalog /Pages 2 0 R %s >>', [CatalogExtra]));
    Builder.AddObject(2, '<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>');
    Builder.SetRoot(1);

    const References = TStringBuilder.Create;
    try
      for var Index := 0 to High(Annotations) do
      begin
        References.AppendFormat('%d 0 R ', [FirstAnnotationObject + Index]);
        Builder.AddObject(FirstAnnotationObject + Index, Annotations[Index]);
      end;
      Builder.AddObject(3, Format(PageFormat, [Format('/Annots [%s]', [References.ToString])]));
    finally
      References.Free;
    end;
    Builder.AddObject(5, Format(PageFormat, ['']));
  except
    Builder.Free;
    raise;
  end;

  Result := LoadBuilder(Builder).Page(0).Links;
end;

procedure TApiLinksTests.TestGoToLinkResolvesPage;
begin
  const Links = Load(TViewerDocuments.Invoice).Page(0).Links;

  Assert.AreEqual<Integer>(2, Length(Links));
  Assert.AreEqual<Integer>(Ord(TPdfLinkKind.GoTo), Ord(Links[0].Kind));
  Assert.AreEqual(0, Links[0].PageIndex);
  Assert.AreEqual(1, Links[0].TargetPageIndex);
  Assert.AreEqual<Integer>(1, Length(Links[0].Quads));
  const Bounds = Links[0].Quads[0].Bounds;
  Assert.AreEqual(Double(100), Double(Bounds.Left), Tolerance);
  Assert.AreEqual(Double(200), Double(Bounds.Right), Tolerance);
  Assert.AreEqual(Double(600), Double(Bounds.Top), Tolerance);
  Assert.AreEqual(Double(620), Double(Bounds.Bottom), Tolerance);
end;

procedure TApiLinksTests.TestUriLink;
begin
  const Links = Load(TViewerDocuments.Invoice).Page(0).Links;

  Assert.AreEqual<Integer>(Ord(TPdfLinkKind.Uri), Ord(Links[1].Kind));
  Assert.AreEqual('https://example.com/', Links[1].Uri);
end;

procedure TApiLinksTests.TestPageWithoutLinks;
begin
  const Document = Load(TViewerDocuments.Invoice);

  Assert.AreEqual<Integer>(0, Length(Document.Page(1).Links));
end;

procedure TApiLinksTests.TestNamedDestinationResolves;
begin
  const Links = LinksOf(['<< /Type /Annot /Subtype /Link /Rect [10 10 50 30] /Dest (chapter) >>'],
                        '/Names << /Dests << /Names [(chapter) [5 0 R /Fit]] >> >>');

  Assert.AreEqual<Integer>(1, Length(Links));
  Assert.AreEqual<Integer>(Ord(TPdfLinkKind.GoTo), Ord(Links[0].Kind));
  Assert.AreEqual(1, Links[0].TargetPageIndex);
end;

procedure TApiLinksTests.TestGoToActionResolvesPage;
begin
  const Links = LinksOf(['<< /Type /Annot /Subtype /Link /Rect [10 10 50 30] /A << /S /GoTo /D [5 0 R /Fit] >> >>']);

  Assert.AreEqual<Integer>(1, Length(Links));
  Assert.AreEqual(1, Links[0].TargetPageIndex);
end;

procedure TApiLinksTests.TestQuadPointsWinOverRect;
begin
  const Links = LinksOf(['<< /Type /Annot /Subtype /Link /Rect [0 0 500 500] /A << /S /URI /URI (x) >> ' +
                         '/QuadPoints [10 30 50 30 10 10 50 10  60 30 90 30 60 10 90 10] >>']);

  Assert.AreEqual<Integer>(1, Length(Links));
  Assert.AreEqual<Integer>(2, Length(Links[0].Quads));
  const First = Links[0].Quads[0].Bounds;
  Assert.AreEqual(Double(10), Double(First.Left), Tolerance);
  Assert.AreEqual(Double(50), Double(First.Right), Tolerance);
  Assert.AreEqual(Double(10), Double(First.Top), Tolerance);
  Assert.AreEqual(Double(30), Double(First.Bottom), Tolerance);
  Assert.AreEqual(Double(60), Double(Links[0].Quads[1].Bounds.Left), Tolerance);
  Assert.AreEqual(Double(10), Double(Links[0].Quads[0].P1.X), Tolerance);
  Assert.AreEqual(Double(10), Double(Links[0].Quads[0].P1.Y), Tolerance);
  Assert.AreEqual(Double(30), Double(Links[0].Quads[0].P4.Y), Tolerance);
end;

procedure TApiLinksTests.TestInvalidQuadPointsFallBackToRect;
begin
  const Links = LinksOf(['<< /Type /Annot /Subtype /Link /Rect [100 200 300 400] /A << /S /URI /URI (x) >> /QuadPoints [1 2 3 4 5 6 7] >>']);

  Assert.AreEqual<Integer>(1, Length(Links));
  Assert.AreEqual<Integer>(1, Length(Links[0].Quads));
  const Bounds = Links[0].Quads[0].Bounds;
  Assert.AreEqual(Double(100), Double(Bounds.Left), Tolerance);
  Assert.AreEqual(Double(300), Double(Bounds.Right), Tolerance);
  Assert.AreEqual(Double(200), Double(Bounds.Top), Tolerance);
  Assert.AreEqual(Double(400), Double(Bounds.Bottom), Tolerance);
end;

procedure TApiLinksTests.TestBrokenLinksAreSkipped;
begin
  const Links = LinksOf(['<< /Type /Annot /Subtype /Link /A << /S /URI /URI (x) >> >>',
                         '<< /Type /Annot /Subtype /Link /Rect [10 10 50 30] /Dest [99 0 R /Fit] >>',
                         '<< /Type /Annot /Subtype /Link /Rect [10 10 50 30] /Dest (nowhere) >>',
                         '<< /Type /Annot /Subtype /Link /Rect [10 10 50 30] /A << /S /GoTo >> >>',
                         '<< /Type /Annot /Subtype /Link /Rect [10 10 50 30] /A << /S /URI >> >>',
                         '<< /Type /Annot /Subtype /Link /Rect [10 10 50 30] /A << /S /URI /URI (kept) >> >>']);

  Assert.AreEqual<Integer>(1, Length(Links));
  Assert.AreEqual('kept', Links[0].Uri);
  Assert.IsTrue(FLogLines.Count >= 5, 'Every skipped link goes to the log');
end;

procedure TApiLinksTests.TestHugeQuadPointsAreLimited;
begin
  const Links = LinksOf(['<< /Type /Annot /Subtype /Link /Rect [10 10 50 30] /A << /S /URI /URI (x) >> ' +
                         '/QuadPoints [1e38 1e38 -1e38 1e38 1e38 -1e38 -1e38 -1e38] >>']);

  Assert.AreEqual<Integer>(1, Length(Links));
  Assert.AreEqual<Integer>(1, Length(Links[0].Quads));
  Assert.IsTrue(Links[0].Quads[0].IsFinite);
  const Bounds = Links[0].Quads[0].Bounds;
  Assert.IsTrue((Abs(Bounds.Left) <= 2147483648.0) and (Abs(Bounds.Right) <= 2147483648.0));
  Assert.IsTrue((Abs(Bounds.Top) <= 2147483648.0) and (Abs(Bounds.Bottom) <= 2147483648.0));
end;

procedure TApiLinksTests.TestLinkWithoutDestinationAndAction;
begin
  const Links = LinksOf(['<< /Type /Annot /Subtype /Link /Rect [10 10 50 30] >>']);

  Assert.AreEqual<Integer>(0, Length(Links));
end;

procedure TApiLinksTests.TestOtherActionsGiveKindOther;
begin
  const Links = LinksOf(['<< /Type /Annot /Subtype /Link /Rect [10 10 50 30] /A << /S /Launch /F (a.exe) >> >>',
                         '<< /Type /Annot /Subtype /Link /Rect [10 10 50 30] /A << /S /Named /N /NextPage >> >>']);

  Assert.AreEqual<Integer>(2, Length(Links));
  Assert.AreEqual<Integer>(Ord(TPdfLinkKind.Other), Ord(Links[0].Kind));
  Assert.AreEqual<Integer>(Ord(TPdfLinkKind.Other), Ord(Links[1].Kind));
end;

procedure TApiLinksTests.TestNonLinkAnnotationsAreIgnored;
begin
  const Links = LinksOf(['<< /Type /Annot /Subtype /Square /Rect [10 10 50 30] /A << /S /URI /URI (x) >> >>']);

  Assert.AreEqual<Integer>(0, Length(Links));
end;

procedure TApiLinksTests.TestLinksKeepAnnotsOrder;
begin
  const Links = LinksOf(['<< /Type /Annot /Subtype /Link /Rect [10 10 50 30] /A << /S /URI /URI (first) >> >>',
                         '<< /Type /Annot /Subtype /Link /Rect [10 10 50 30] /A << /S /URI /URI (second) >> >>']);

  Assert.AreEqual<Integer>(2, Length(Links));
  Assert.AreEqual('first', Links[0].Uri);
  Assert.AreEqual('second', Links[1].Uri);
end;

end.
