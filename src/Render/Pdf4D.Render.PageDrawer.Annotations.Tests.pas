// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of the annotation part of PageDrawer and PDFStreamEngine.processAnnotation (PDFBox 3.0.8), through the recording device
unit Pdf4D.Render.PageDrawer.Annotations.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Types,
  DUnitX.TestFramework,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Render.Options,
  Pdf4D.Render.Renderer.Interfaces,
  Pdf4D.Tests.GraphicsDocuments,
  Pdf4D.Tests.PdfBuilder,
  Pdf4D.Tests.RecordingDevice;

type
  [TestFixture]
  TPageDrawerAnnotationTests = class
  private
    const Tolerance: Single = 0.001;
    // An appearance of 10 x 10 that fills its whole box
    const SquareAppearance = '/Type /XObject /Subtype /Form /BBox [0 0 10 10]';
    const SquareContent = '0 0 10 10 re f';
    const NoView = 32;

  private
    FDocuments: TGraphicsDocuments;
    FBuilder: TTestPdfBuilder;
    FDocument: IPdfDocument;
    FRenderer: IPdfRenderer;
    FDevice: TRecordingDevice;
    FDeviceReference: IPdfRasterDevice;

    // The page content draws nothing; the annotations are the objects of Annots, from 5 on (the appearances come after them)
    procedure Prepare(const PageEntries: string; const Content: string = '');
    procedure AddSquare(const Number: Integer; const Entries: string; const Appearance: Integer);
    procedure AddAppearance(const Number: Integer; const Dictionary: string; const Content: string);
    procedure Run(const Options: TPdfRenderOptions; const ExtraRotation: Integer = 0); overload;
    procedure Run; overload;
    function Fills: TArray<TRecordedCall>;
    function DebugLinesAbout(const Fragment: string): Integer;
    function HasLogLine(const Fragment: string): Boolean;
    procedure AssertNear(const Expected, Actual: Single);
    procedure AssertBounds(const Left, Top, Right, Bottom: Single; const Actual: TRectF);
    function DrawnWith(const Destination: Integer; const Flags: Integer; const SubType: string): Integer;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestAnnotationAppearanceDrawnInRect;

    [Test]
    procedure TestAppearanceMatrixIsPartOfTheMapping;

    [Test]
    procedure TestAppearanceIsClippedToItsBBox;

    [Test]
    procedure TestAnnotationsAreDrawnAfterThePage;

    [Test]
    procedure TestAppearanceStateSelected;

    [Test]
    [TestCase('HiddenExport', '0,2,0')]
    [TestCase('HiddenView', '1,2,0')]
    [TestCase('HiddenPrint', '2,6,0')]
    [TestCase('NoViewExport', '0,32,0')]
    [TestCase('NoViewView', '1,32,0')]
    [TestCase('NoViewPrintedPrint', '2,36,1')]
    [TestCase('PlainExport', '0,0,1')]
    [TestCase('PlainView', '1,0,1')]
    [TestCase('NotPrintedPrint', '2,0,0')]
    [TestCase('PrintedPrint', '2,4,1')]
    [TestCase('InvisibleKnownTypeIsDrawn', '0,1,1')]
    procedure TestFlagsDecideWhetherAnnotationIsDrawn(const Destination, Flags, ExpectedFills: Integer);

    [Test]
    procedure TestHiddenAndNoViewSkipped;

    [Test]
    procedure TestNotPrintedSkippedForPrint;

    [Test]
    procedure TestInvisibleUnknownTypeIsSkipped;

    [Test]
    procedure TestUnknownTypeIsDrawn;

    [Test]
    procedure TestHiddenOptionalContentSkipsAnnotation;

    [Test]
    procedure TestVisibleOptionalContentDrawsAnnotation;

    [Test]
    procedure TestNoRotateOnRotatedPage;

    [Test]
    procedure TestRotatedPageRotatesAnnotationWithoutNoRotate;

    [Test]
    procedure TestNoRotateOnUpright;

    [Test]
    procedure TestAnnotationWithoutAppearanceIsSkipped;

    [Test]
    procedure TestAnnotationWithoutRectIsSkipped;

    [Test]
    procedure TestZeroSizedRectOrBBoxIsSkipped;

    [Test]
    procedure TestRenderAnnotationsOff;

    [Test]
    procedure TestAppearanceThatDrawsItselfIsNotRepeated;

    [Test]
    procedure TestJunkInAnnotsIsSkipped;

    [Test]
    procedure TestHugeNumberOfAnnotationsIsLimited;

    [Test]
    procedure TestAnnotationWithBrokenGeometryDoesNotStopTheOthers;

    [Test]
    procedure TestAppearanceThatCannotBeDecodedDoesNotRaise;

    [Test]
    procedure TestSameAppearanceOfSeveralAnnotationsIsDrawnForEach;
  end;

implementation

uses
  System.Generics.Collections,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Render.Renderer;

const
  AnnotationObject = 5;
  AppearanceObject = 20;
  ExportDestination = 0;
  ViewDestination = 1;
  PrintDestination = 2;

{ TPageDrawerAnnotationTests }

procedure TPageDrawerAnnotationTests.Setup;
begin
  FDocuments := TGraphicsDocuments.Create;
  FDevice := TRecordingDevice.Create(TGraphicsDocuments.PageSize, TGraphicsDocuments.PageSize);
  FDeviceReference := FDevice;
end;

procedure TPageDrawerAnnotationTests.TearDown;
begin
  FDeviceReference := nil;
  FRenderer := nil;
  FDocument := nil;
  FreeAndNil(FBuilder);
  FreeAndNil(FDocuments);
end;

procedure TPageDrawerAnnotationTests.Prepare(const PageEntries, Content: string);
begin
  FRenderer := nil;
  FDocument := nil;
  FreeAndNil(FBuilder);
  FDevice.Calls.Clear;
  FBuilder := TGraphicsDocuments.NewBuilder(TEncoding.ASCII.GetBytes(Content), '', PageEntries);
end;

procedure TPageDrawerAnnotationTests.AddSquare(const Number: Integer; const Entries: string; const Appearance: Integer);
begin
  FBuilder.AddObject(Number, Format('<< /Type /Annot /Subtype /Square /Rect [100 100 120 120] /AP << /N %d 0 R >> %s >>', [Appearance, Entries]));
end;

procedure TPageDrawerAnnotationTests.AddAppearance(const Number: Integer; const Dictionary, Content: string);
begin
  FBuilder.AddStreamObject(Number, Dictionary, TEncoding.ASCII.GetBytes(Content));
end;

procedure TPageDrawerAnnotationTests.Run(const Options: TPdfRenderOptions; const ExtraRotation: Integer);
begin
  FDocument := FDocuments.Open(FBuilder);
  FRenderer := TPdfRenderer.Create(FDocument, TRecordingBackend.Create);

  var Params := TPdfRenderParams.Create(1);
  Params.Options := Options;
  Params.ExtraRotation := ExtraRotation;
  const Status = FRenderer.RenderPage(0, FDeviceReference, Params);

  Assert.AreEqual(TPdfRenderStatus.Completed, Status);
end;

procedure TPageDrawerAnnotationTests.Run;
begin
  Run(TPdfRenderOptions.Default);
end;

function TPageDrawerAnnotationTests.Fills: TArray<TRecordedCall>;
begin
  const Found = TList<TRecordedCall>.Create;
  try
    for var Call in FDevice.Calls do
    begin
      if Call.Kind = TRecordedCallKind.Fill then
      begin
        Found.Add(Call);
      end;
    end;
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

function TPageDrawerAnnotationTests.DebugLinesAbout(const Fragment: string): Integer;
begin
  Result := 0;
  for var Line in FDocuments.AllLogLines do
  begin
    if Line.StartsWith('Debug:') and Line.Contains(Fragment) then
    begin
      Inc(Result);
    end;
  end;
end;

function TPageDrawerAnnotationTests.HasLogLine(const Fragment: string): Boolean;
begin
  Result := False;
  for var Line in FDocuments.AllLogLines do
  begin
    Result := (Result or Line.Contains(Fragment));
  end;
end;

procedure TPageDrawerAnnotationTests.AssertNear(const Expected, Actual: Single);
begin
  Assert.AreEqual(Double(Expected), Double(Actual), Double(Tolerance));
end;

procedure TPageDrawerAnnotationTests.AssertBounds(const Left, Top, Right, Bottom: Single; const Actual: TRectF);
begin
  AssertNear(Left, Actual.Left);
  AssertNear(Top, Actual.Top);
  AssertNear(Right, Actual.Right);
  AssertNear(Bottom, Actual.Bottom);
end;

procedure TPageDrawerAnnotationTests.TestAnnotationAppearanceDrawnInRect;
begin
  Prepare('/Annots [5 0 R]');
  AddSquare(AnnotationObject, '', AppearanceObject);
  AddAppearance(AppearanceObject, SquareAppearance, SquareContent);
  Run;

  const Found = Fills;
  Assert.AreEqual<Integer>(1, Length(Found));
  // The box of 10 x 10 is mapped on the rectangle of 20 x 20: scale 2, and the page is 200 high
  AssertBounds(100, 80, 120, 100, Found[0].DeviceBounds);
end;

procedure TPageDrawerAnnotationTests.TestAppearanceMatrixIsPartOfTheMapping;
begin
  Prepare('/Annots [5 0 R]');
  AddSquare(AnnotationObject, '', AppearanceObject);
  AddAppearance(AppearanceObject, '/Type /XObject /Subtype /Form /BBox [0 0 10 10] /Matrix [0 1 -1 0 0 0]', SquareContent);
  Run;

  const Found = Fills;
  Assert.AreEqual<Integer>(1, Length(Found));
  AssertBounds(100, 80, 120, 100, Found[0].DeviceBounds);
end;

procedure TPageDrawerAnnotationTests.TestAppearanceIsClippedToItsBBox;
begin
  Prepare('/Annots [5 0 R]');
  AddSquare(AnnotationObject, '', AppearanceObject);
  AddAppearance(AppearanceObject, SquareAppearance, '-5 -5 30 30 re f');
  Run;

  const Found = Fills;
  Assert.AreEqual<Integer>(1, Length(Found));
  // The crop box and the box of the appearance
  Assert.AreEqual<Integer>(2, Found[0].ClipDepth);
end;

procedure TPageDrawerAnnotationTests.TestAnnotationsAreDrawnAfterThePage;
begin
  Prepare('/Annots [5 0 R]', '0 0 50 50 re f');
  AddSquare(AnnotationObject, '', AppearanceObject);
  AddAppearance(AppearanceObject, SquareAppearance, SquareContent);
  Run;

  const Found = Fills;
  Assert.AreEqual<Integer>(2, Length(Found));
  AssertBounds(0, 150, 50, 200, Found[0].DeviceBounds);
  AssertBounds(100, 80, 120, 100, Found[1].DeviceBounds);
end;

procedure TPageDrawerAnnotationTests.TestAppearanceStateSelected;
begin
  Prepare('/Annots [5 0 R]');
  FBuilder.AddObject(AnnotationObject, '<< /Type /Annot /Subtype /Widget /Rect [100 100 120 120] /AS /On /AP << /N << /On 20 0 R /Off 21 0 R >> >> >>');
  AddAppearance(20, SquareAppearance, '1 0 0 rg ' + SquareContent);
  AddAppearance(21, SquareAppearance, '0 0 1 rg ' + SquareContent);
  Run;

  const Found = Fills;
  Assert.AreEqual<Integer>(1, Length(Found));
  Assert.AreEqual(Byte(255), Found[0].Paint.Color.R);
  Assert.AreEqual(Byte(0), Found[0].Paint.Color.B);
end;

function TPageDrawerAnnotationTests.DrawnWith(const Destination, Flags: Integer; const SubType: string): Integer;
begin
  Prepare('/Annots [5 0 R]');
  FBuilder.AddObject(AnnotationObject, Format('<< /Type /Annot /Subtype /%s /Rect [100 100 120 120] /F %d /AP << /N 20 0 R >> >>', [SubType, Flags]));
  AddAppearance(AppearanceObject, SquareAppearance, SquareContent);

  var Options := TPdfRenderOptions.Default;
  Options.Destination := TPdfRenderDestination(Destination);
  Run(Options);
  Result := Length(Fills);
end;

procedure TPageDrawerAnnotationTests.TestFlagsDecideWhetherAnnotationIsDrawn(const Destination, Flags, ExpectedFills: Integer);
begin
  Assert.AreEqual<Integer>(ExpectedFills, DrawnWith(Destination, Flags, 'Square'));
end;

procedure TPageDrawerAnnotationTests.TestHiddenAndNoViewSkipped;
begin
  Assert.AreEqual<Integer>(0, DrawnWith(ExportDestination, 2, 'Square'), 'hidden, export');
  Assert.AreEqual<Integer>(0, DrawnWith(ViewDestination, NoView, 'Square'), 'no view, view');
  Assert.AreEqual<Integer>(0, DrawnWith(ExportDestination, NoView, 'Square'), 'no view, export');
end;

procedure TPageDrawerAnnotationTests.TestNotPrintedSkippedForPrint;
begin
  Assert.AreEqual<Integer>(0, DrawnWith(PrintDestination, 0, 'Square'));
  Assert.AreEqual<Integer>(1, DrawnWith(PrintDestination, 4, 'Square'));
end;

procedure TPageDrawerAnnotationTests.TestInvisibleUnknownTypeIsSkipped;
begin
  Assert.AreEqual<Integer>(0, DrawnWith(ExportDestination, 1, 'Movie'));
end;

procedure TPageDrawerAnnotationTests.TestUnknownTypeIsDrawn;
begin
  Assert.AreEqual<Integer>(1, DrawnWith(ExportDestination, 0, 'Movie'));
end;

procedure TPageDrawerAnnotationTests.TestHiddenOptionalContentSkipsAnnotation;
begin
  Prepare('/Annots [5 0 R]');
  FBuilder.AddObject(1, '<< /Type /Catalog /Pages 2 0 R /OCProperties << /OCGs [6 0 R] /D << /OFF [6 0 R] >> >> >>');
  FBuilder.AddObject(6, '<< /Type /OCG /Name (Off) >>');
  AddSquare(AnnotationObject, '/OC 6 0 R', AppearanceObject);
  AddAppearance(AppearanceObject, SquareAppearance, SquareContent);
  Run;

  Assert.AreEqual<Integer>(0, Length(Fills));
end;

procedure TPageDrawerAnnotationTests.TestVisibleOptionalContentDrawsAnnotation;
begin
  Prepare('/Annots [5 0 R]');
  FBuilder.AddObject(1, '<< /Type /Catalog /Pages 2 0 R /OCProperties << /OCGs [6 0 R] /D << /BaseState /ON >> >> >>');
  FBuilder.AddObject(6, '<< /Type /OCG /Name (On) >>');
  AddSquare(AnnotationObject, '/OC 6 0 R', AppearanceObject);
  AddAppearance(AppearanceObject, SquareAppearance, SquareContent);
  Run;

  Assert.AreEqual<Integer>(1, Length(Fills));
end;

procedure TPageDrawerAnnotationTests.TestNoRotateOnRotatedPage;
begin
  Prepare('/Rotate 90 /Annots [5 0 R]');
  AddSquare(AnnotationObject, '/F 16', AppearanceObject);
  AddAppearance(AppearanceObject, SquareAppearance, SquareContent);
  Run;

  const Found = Fills;
  Assert.AreEqual<Integer>(1, Length(Found));
  // The upper left corner of the rectangle, (100, 120) in the page, stays where it is and the annotation turns against the page
  // (x, y) -> (y, x) on the device for a page turned 90 degrees: the corner is at (120, 100) and the box goes right and down from there
  AssertBounds(120, 100, 140, 120, Found[0].DeviceBounds);
end;

procedure TPageDrawerAnnotationTests.TestRotatedPageRotatesAnnotationWithoutNoRotate;
begin
  Prepare('/Rotate 90 /Annots [5 0 R]');
  AddSquare(AnnotationObject, '', AppearanceObject);
  AddAppearance(AppearanceObject, SquareAppearance, SquareContent);
  Run;

  const Found = Fills;
  Assert.AreEqual<Integer>(1, Length(Found));
  AssertBounds(100, 100, 120, 120, Found[0].DeviceBounds);
end;

procedure TPageDrawerAnnotationTests.TestNoRotateOnUpright;
begin
  Prepare('/Annots [5 0 R]');
  AddSquare(AnnotationObject, '/F 16', AppearanceObject);
  AddAppearance(AppearanceObject, SquareAppearance, SquareContent);
  Run;

  const Found = Fills;
  Assert.AreEqual<Integer>(1, Length(Found));
  AssertBounds(100, 80, 120, 100, Found[0].DeviceBounds);
end;

procedure TPageDrawerAnnotationTests.TestAnnotationWithoutAppearanceIsSkipped;
begin
  Prepare('/Annots [5 0 R]');
  FBuilder.AddObject(AnnotationObject, '<< /Type /Annot /Subtype /Square /Rect [100 100 120 120] >>');
  Run;

  Assert.AreEqual<Integer>(0, Length(Fills));
  Assert.AreEqual<Integer>(1, DebugLinesAbout('has no normal appearance'), string.Join('|', FDocuments.AllLogLines.ToArray));
end;

procedure TPageDrawerAnnotationTests.TestAnnotationWithoutRectIsSkipped;
begin
  Prepare('/Annots [5 0 R]');
  FBuilder.AddObject(AnnotationObject, '<< /Type /Annot /Subtype /Square /AP << /N 20 0 R >> >>');
  AddAppearance(AppearanceObject, SquareAppearance, SquareContent);
  Run;

  Assert.AreEqual<Integer>(0, Length(Fills));
end;

procedure TPageDrawerAnnotationTests.TestZeroSizedRectOrBBoxIsSkipped;
begin
  Prepare('/Annots [5 0 R 6 0 R]');
  FBuilder.AddObject(5, '<< /Type /Annot /Subtype /Square /Rect [100 100 100 120] /AP << /N 20 0 R >> >>');
  FBuilder.AddObject(6, '<< /Type /Annot /Subtype /Square /Rect [100 100 120 120] /AP << /N 21 0 R >> >>');
  AddAppearance(20, SquareAppearance, SquareContent);
  AddAppearance(21, '/Type /XObject /Subtype /Form /BBox [0 0 0 10]', SquareContent);
  Run;

  Assert.AreEqual<Integer>(0, Length(Fills));
end;

procedure TPageDrawerAnnotationTests.TestRenderAnnotationsOff;
begin
  Prepare('/Annots [5 0 R]');
  AddSquare(AnnotationObject, '', AppearanceObject);
  AddAppearance(AppearanceObject, SquareAppearance, SquareContent);
  var Options := TPdfRenderOptions.Default;
  Options.RenderAnnotations := False;
  Run(Options);

  Assert.AreEqual<Integer>(0, Length(Fills));
end;

procedure TPageDrawerAnnotationTests.TestAppearanceThatDrawsItselfIsNotRepeated;
begin
  Prepare('/Annots [5 0 R]');
  AddSquare(AnnotationObject, '', AppearanceObject);
  AddAppearance(AppearanceObject, '/Type /XObject /Subtype /Form /BBox [0 0 10 10] /Resources << /XObject << /Fm 20 0 R >> >>',
                '/Fm Do ' + SquareContent);
  Run;

  Assert.AreEqual<Integer>(1, Length(Fills));
  Assert.IsTrue(HasLogLine('draws itself'));
end;

procedure TPageDrawerAnnotationTests.TestJunkInAnnotsIsSkipped;
begin
  Prepare('/Annots [42 null (x) /Name 99 0 R << >> [1 2] 5 0 R 6 0 R]');
  AddSquare(AnnotationObject, '', AppearanceObject);
  FBuilder.AddObject(6, '<< /Type /Annot /Subtype /Square /Rect [/a /b /c /d] /AP << /N 99 0 R >> >>');
  AddAppearance(AppearanceObject, SquareAppearance, SquareContent);
  Run;

  Assert.AreEqual<Integer>(1, Length(Fills));
end;

procedure TPageDrawerAnnotationTests.TestHugeNumberOfAnnotationsIsLimited;
begin
  const Count = 12000;
  const Annots = TStringBuilder.Create;
  try
    for var Index := 1 to Count do
    begin
      Annots.Append('5 0 R ');
    end;
    Prepare(Format('/Annots [%s]', [Annots.ToString]));
  finally
    Annots.Free;
  end;
  FBuilder.AddObject(AnnotationObject, '<< /Type /Annot /Subtype /Square /Rect [100 100 120 120] >>');
  Run;

  Assert.IsTrue(DebugLinesAbout('has no normal appearance') < Count, 'only a limited number of annotations is looked at');
  Assert.IsTrue(HasLogLine('annotations'), 'the limit is logged');
end;

procedure TPageDrawerAnnotationTests.TestAnnotationWithBrokenGeometryDoesNotStopTheOthers;
begin
  Prepare('/Annots [5 0 R 6 0 R]');
  // A scale beyond the range of a Single
  FBuilder.AddObject(5, '<< /Type /Annot /Subtype /Square /Rect [0 0 300000000000000000000000000000000000000.0 300000000000000000000000000000000000000.0] /AP << /N 20 0 R >> >>');
  AddSquare(6, '', 21);
  AddAppearance(20, '/Type /XObject /Subtype /Form /BBox [0 0 0.0000000001 0.0000000001]', SquareContent);
  AddAppearance(21, SquareAppearance, SquareContent);
  Run;

  Assert.IsTrue(Length(Fills) >= 1);
  AssertBounds(100, 80, 120, 100, Fills[High(Fills)].DeviceBounds);
end;

procedure TPageDrawerAnnotationTests.TestAppearanceThatCannotBeDecodedDoesNotRaise;
begin
  Prepare('/Annots [5 0 R 6 0 R]');
  AddSquare(5, '', 20);
  AddSquare(6, '', 21);
  AddAppearance(20, '/Type /XObject /Subtype /Form /BBox [0 0 10 10] /Filter /FlateDecode', 'this is not deflate data');
  AddAppearance(21, SquareAppearance, SquareContent);
  Run;

  Assert.AreEqual<Integer>(1, Length(Fills));
end;

procedure TPageDrawerAnnotationTests.TestSameAppearanceOfSeveralAnnotationsIsDrawnForEach;
begin
  Prepare('/Annots [5 0 R 5 0 R 5 0 R]');
  AddSquare(AnnotationObject, '', AppearanceObject);
  AddAppearance(AppearanceObject, SquareAppearance, SquareContent);
  Run;

  Assert.AreEqual<Integer>(3, Length(Fills));
end;

end.
