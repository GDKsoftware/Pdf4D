// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of the optional content part of PageDrawer (PDFBox 3.0.8): marked content with /OC, the membership dictionaries, the visibility
// expressions and /OC on image and form XObjects, through the recording device
unit Pdf4D.Render.PageDrawer.OptionalContent.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Types,
  System.Generics.Collections,
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
  TPageDrawerOptionalContentTests = class
  private
    const OnGroup = '5 0 R';
    const OffGroup = '6 0 R';
    // The group On (5) is enabled, the group Off (6) is in /OFF
    const Properties = '/Properties << /on 5 0 R /off 6 0 R /ocmd 7 0 R /plain << /MCID 1 >> >>';
    const OneFill = '0 0 10 10 re f';

  private
    FDocuments: TGraphicsDocuments;
    FBuilder: TTestPdfBuilder;
    FDocument: IPdfDocument;
    FRenderer: IPdfRenderer;
    FDevice: TRecordingDevice;
    FDeviceReference: IPdfRasterDevice;

    // Starts a document with the groups On and Off; the test adds objects from 7 on and then calls Run
    procedure Prepare(const Content: string; const Resources: string = Properties; const OcConfig: string = '/D << /OFF [6 0 R] >>');
    procedure AddGroups;
    procedure AddMembership(const Body: string);
    procedure Run(const Destination: TPdfRenderDestination = TPdfRenderDestination.Export);
    function Count(const Kind: TRecordedCallKind): Integer;
    function FillsAfterMembership(const Body: string): Integer;
    function FillsOfExpression(const Expression: string): Integer;
    function HasLogLine(const Fragment: string): Boolean;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestHiddenGroupSkipsContent;

    [Test]
    procedure TestVisibleGroupDrawsContent;

    [Test]
    procedure TestContentAfterTheSequenceIsDrawn;

    [Test]
    procedure TestHiddenGroupSkipsStrokesAndShadings;

    [Test]
    procedure TestNestedBdcRestoresVisibility;

    [Test]
    procedure TestPlainPropertyListIsVisible;

    [Test]
    procedure TestOcmdAnyOn;

    [Test]
    procedure TestOcmdAllOff;

    [Test]
    [TestCase('AnyOnVisible', 'AnyOn,On+Off,1')]
    [TestCase('AnyOnHidden', 'AnyOn,Off,0')]
    [TestCase('AllOnVisible', 'AllOn,On+On,1')]
    [TestCase('AllOnHidden', 'AllOn,On+Off,0')]
    [TestCase('AnyOffVisible', 'AnyOff,On+Off,1')]
    [TestCase('AnyOffHidden', 'AnyOff,On+On,0')]
    [TestCase('AllOffVisible', 'AllOff,Off+Off,1')]
    [TestCase('AllOffHidden', 'AllOff,On+Off,0')]
    [TestCase('UnknownPolicyIsAnyOn', 'Other,On+Off,1')]
    procedure TestOcmdPolicies(const Policy, Groups: string; const ExpectedFills: Integer);

    [Test]
    procedure TestOcmdWithoutGroupsIsVisible;

    [Test]
    procedure TestOcmdDefaultPolicyIsAnyOn;

    [Test]
    procedure TestVisibilityExpressionNotAnd;

    [Test]
    [TestCase('AndHidden', '[/And 5 0 R 6 0 R],0')]
    [TestCase('AndVisible', '[/And 5 0 R 5 0 R],1')]
    [TestCase('OrVisible', '[/Or 5 0 R 6 0 R],1')]
    [TestCase('OrHidden', '[/Or 6 0 R 6 0 R],0')]
    [TestCase('NotHidden', '[/Not 5 0 R],0')]
    [TestCase('NotVisible', '[/Not 6 0 R],1')]
    [TestCase('NotWithTwoOperandsIsVisible', '[/Not 5 0 R 6 0 R],1')]
    [TestCase('UnknownOperatorIsVisible', '[/Xor 5 0 R 6 0 R],1')]
    [TestCase('NoOperatorIsVisible', '[5 0 R 6 0 R],1')]
    [TestCase('NestedExpression', '[/And 5 0 R [/Not [/Or 6 0 R 6 0 R]]],1')]
    procedure TestVisibilityExpressions(const Expression: string; const ExpectedFills: Integer);

    [Test]
    procedure TestVisibilityExpressionBeatsGroups;

    [Test]
    procedure TestVisibilityExpressionDepthIsLimited;

    [Test]
    procedure TestSharedSubexpressionsAreEvaluatedOnce;

    [Test]
    procedure TestMembershipThatContainsItselfDoesNotHang;

    [Test]
    procedure TestViewUsageHidesGroupInViewOnly;

    [Test]
    procedure TestPrintUsageFallsBackToExport;

    [Test]
    procedure TestUsageOnShowsADisabledGroup;

    [Test]
    procedure TestDocumentWithoutOptionalContentPropertiesDrawsEverything;

    [Test]
    procedure TestImageWithHiddenOcIsSkipped;

    [Test]
    procedure TestImageWithVisibleOcIsDrawn;

    [Test]
    procedure TestFormWithHiddenOcIsSkipped;

    [Test]
    procedure TestTransparencyGroupWithHiddenOcIsSkipped;

    [Test]
    procedure TestFormWithVisibleOcIsDrawn;

    [Test]
    procedure TestFormInsideHiddenSequenceIsSkipped;
  end;

implementation

uses
  Pdf4D.Render.Renderer;

const
  ImageResources = '/XObject << /Im1 8 0 R >>';

{ TPageDrawerOptionalContentTests }

procedure TPageDrawerOptionalContentTests.Setup;
begin
  FDocuments := TGraphicsDocuments.Create;
  FDevice := TRecordingDevice.Create(TGraphicsDocuments.PageSize, TGraphicsDocuments.PageSize);
  FDeviceReference := FDevice;
end;

procedure TPageDrawerOptionalContentTests.TearDown;
begin
  FDeviceReference := nil;
  FRenderer := nil;
  FDocument := nil;
  FreeAndNil(FBuilder);
  FreeAndNil(FDocuments);
end;

procedure TPageDrawerOptionalContentTests.Prepare(const Content, Resources, OcConfig: string);
begin
  FRenderer := nil;
  FDocument := nil;
  FreeAndNil(FBuilder);
  FDevice.Calls.Clear;
  FBuilder := TGraphicsDocuments.NewBuilder(TEncoding.ASCII.GetBytes(Content), Resources);
  FBuilder.AddObject(1, Format('<< /Type /Catalog /Pages 2 0 R /OCProperties << /OCGs [5 0 R 6 0 R] %s >> >>', [OcConfig]));
  AddGroups;
end;

procedure TPageDrawerOptionalContentTests.AddGroups;
begin
  FBuilder.AddObject(5, '<< /Type /OCG /Name (On) >>');
  FBuilder.AddObject(6, '<< /Type /OCG /Name (Off) >>');
end;

procedure TPageDrawerOptionalContentTests.AddMembership(const Body: string);
begin
  FBuilder.AddObject(7, Body);
end;

procedure TPageDrawerOptionalContentTests.Run(const Destination: TPdfRenderDestination);
begin
  FDocument := FDocuments.Open(FBuilder);
  FRenderer := TPdfRenderer.Create(FDocument, TRecordingBackend.Create);

  var Params := TPdfRenderParams.Create(1);
  Params.Options.Destination := Destination;
  const Status = FRenderer.RenderPage(0, FDeviceReference, Params);

  Assert.AreEqual(TPdfRenderStatus.Completed, Status);
end;

function TPageDrawerOptionalContentTests.Count(const Kind: TRecordedCallKind): Integer;
begin
  Result := 0;
  for var Call in FDevice.Calls do
  begin
    if Call.Kind = Kind then
    begin
      Inc(Result);
    end;
  end;
end;

function TPageDrawerOptionalContentTests.HasLogLine(const Fragment: string): Boolean;
begin
  Result := False;
  for var Line in FDocuments.AllLogLines do
  begin
    Result := (Result or Line.Contains(Fragment));
  end;
end;

function TPageDrawerOptionalContentTests.FillsAfterMembership(const Body: string): Integer;
begin
  Prepare('/OC /ocmd BDC ' + OneFill + ' EMC');
  AddMembership(Body);
  Run;
  Result := Count(TRecordedCallKind.Fill);
end;

function TPageDrawerOptionalContentTests.FillsOfExpression(const Expression: string): Integer;
begin
  Result := FillsAfterMembership(Format('<< /Type /OCMD /VE %s >>', [Expression]));
end;

procedure TPageDrawerOptionalContentTests.TestHiddenGroupSkipsContent;
begin
  Prepare('/OC /off BDC ' + OneFill + ' EMC');
  Run;

  Assert.AreEqual<Integer>(0, Count(TRecordedCallKind.Fill));
end;

procedure TPageDrawerOptionalContentTests.TestVisibleGroupDrawsContent;
begin
  Prepare('/OC /on BDC ' + OneFill + ' EMC');
  Run;

  Assert.AreEqual<Integer>(1, Count(TRecordedCallKind.Fill));
end;

procedure TPageDrawerOptionalContentTests.TestContentAfterTheSequenceIsDrawn;
begin
  Prepare('/OC /off BDC 0 0 10 10 re f EMC 20 20 10 10 re f');
  Run;

  Assert.AreEqual<Integer>(1, Count(TRecordedCallKind.Fill));
end;

procedure TPageDrawerOptionalContentTests.TestHiddenGroupSkipsStrokesAndShadings;
begin
  const Shading = '/Shading << /Sh1 << /ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 100 0] ' +
                  '/Function << /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >> >> >>';
  Prepare('/OC /off BDC 0 0 m 50 50 l S 0 0 20 20 re B /Sh1 sh EMC', Properties + ' ' + Shading);
  Run;

  Assert.AreEqual<Integer>(0, Count(TRecordedCallKind.Stroke));
  Assert.AreEqual<Integer>(0, Count(TRecordedCallKind.Fill));
  Assert.AreEqual<Integer>(0, Count(TRecordedCallKind.Bitmap));
end;

procedure TPageDrawerOptionalContentTests.TestNestedBdcRestoresVisibility;
begin
  // The inner sequences are inside the hidden one, whatever they are; only the fill after the outer EMC is drawn
  Prepare('/OC /off BDC /Span BMC 0 0 1 1 re f /Tag /plain BDC 0 0 2 2 re f /OC /on BDC 0 0 3 3 re f EMC EMC 0 0 4 4 re f EMC 0 0 5 5 re f EMC 0 0 6 6 re f');
  Run;

  Assert.AreEqual<Integer>(1, Count(TRecordedCallKind.Fill));
end;

procedure TPageDrawerOptionalContentTests.TestPlainPropertyListIsVisible;
begin
  Prepare('/Tag /plain BDC ' + OneFill + ' EMC');
  Run;

  Assert.AreEqual<Integer>(1, Count(TRecordedCallKind.Fill));
end;

procedure TPageDrawerOptionalContentTests.TestOcmdAnyOn;
begin
  Assert.AreEqual<Integer>(1, FillsAfterMembership('<< /Type /OCMD /OCGs [5 0 R 6 0 R] /P /AnyOn >>'));
end;

procedure TPageDrawerOptionalContentTests.TestOcmdAllOff;
begin
  Assert.AreEqual<Integer>(0, FillsAfterMembership('<< /Type /OCMD /OCGs [5 0 R 6 0 R] /P /AllOff >>'));
end;

procedure TPageDrawerOptionalContentTests.TestOcmdPolicies(const Policy, Groups: string; const ExpectedFills: Integer);
begin
  var References := '';
  for var Group in Groups.Split(['+']) do
  begin
    if Group = 'On' then
    begin
      References := References + OnGroup + ' ';
    end
    else
    begin
      References := References + OffGroup + ' ';
    end;
  end;

  Assert.AreEqual<Integer>(ExpectedFills, FillsAfterMembership(Format('<< /Type /OCMD /OCGs [%s] /P /%s >>', [References, Policy])));
end;

procedure TPageDrawerOptionalContentTests.TestOcmdWithoutGroupsIsVisible;
begin
  Assert.AreEqual<Integer>(1, FillsAfterMembership('<< /Type /OCMD /OCGs [] >>'));
end;

procedure TPageDrawerOptionalContentTests.TestOcmdDefaultPolicyIsAnyOn;
begin
  Assert.AreEqual<Integer>(0, FillsAfterMembership('<< /Type /OCMD /OCGs 6 0 R >>'));
end;

procedure TPageDrawerOptionalContentTests.TestVisibilityExpressionNotAnd;
begin
  // And(On, Off) is hidden, so its Not is visible
  Assert.AreEqual<Integer>(1, FillsOfExpression('[/Not [/And 5 0 R 6 0 R]]'));
end;

procedure TPageDrawerOptionalContentTests.TestVisibilityExpressions(const Expression: string; const ExpectedFills: Integer);
begin
  Assert.AreEqual<Integer>(ExpectedFills, FillsOfExpression(Expression));
end;

procedure TPageDrawerOptionalContentTests.TestVisibilityExpressionBeatsGroups;
begin
  // The expression says visible, the groups alone would hide the content
  Assert.AreEqual<Integer>(1, FillsAfterMembership('<< /Type /OCMD /OCGs [6 0 R] /VE [/Not 6 0 R] >>'));
  // An empty expression is not used
  Assert.AreEqual<Integer>(0, FillsAfterMembership('<< /Type /OCMD /OCGs [6 0 R] /VE [] >>'));
end;

procedure TPageDrawerOptionalContentTests.TestVisibilityExpressionDepthIsLimited;
begin
  const Levels = 200;
  Prepare('/OC /ocmd BDC ' + OneFill + ' EMC');
  AddMembership('<< /Type /OCMD /VE 20 0 R >>');
  for var Level := 0 to Levels - 1 do
  begin
    FBuilder.AddObject(20 + Level, Format('[/Not %d 0 R]', [21 + Level]));
  end;
  FBuilder.AddObject(20 + Levels, '[/Not 6 0 R]');
  Run;

  Assert.IsTrue(HasLogLine('Visibility expressions'), string.Join('|', FDocuments.AllLogLines.ToArray));
end;

procedure TPageDrawerOptionalContentTests.TestSharedSubexpressionsAreEvaluatedOnce;
begin
  // Every level uses the next one twice: evaluated without memory this is 2^100 steps
  const Levels = 100;
  Prepare('/OC /ocmd BDC ' + OneFill + ' EMC');
  AddMembership('<< /Type /OCMD /VE 20 0 R >>');
  for var Level := 0 to Levels - 1 do
  begin
    FBuilder.AddObject(20 + Level, Format('[/And %d 0 R %d 0 R]', [21 + Level, 21 + Level]));
  end;
  FBuilder.AddObject(20 + Levels, '[/Or 5 0 R 6 0 R]');
  Run;

  Assert.IsTrue(Count(TRecordedCallKind.Fill) <= 1);
end;

procedure TPageDrawerOptionalContentTests.TestMembershipThatContainsItselfDoesNotHang;
begin
  Assert.IsTrue(FillsAfterMembership('<< /Type /OCMD /OCGs [7 0 R 5 0 R] /P /AllOn >>') <= 1);
end;

procedure TPageDrawerOptionalContentTests.TestViewUsageHidesGroupInViewOnly;
begin
  Prepare('/OC /on BDC ' + OneFill + ' EMC');
  FBuilder.AddObject(5, '<< /Type /OCG /Name (On) /Usage << /View << /ViewState /OFF >> >> >>');
  Run(TPdfRenderDestination.View);
  Assert.AreEqual<Integer>(0, Count(TRecordedCallKind.Fill), 'view');
  FDevice.Calls.Clear;

  FRenderer := nil;
  FDocument := nil;
  Run(TPdfRenderDestination.Export);
  Assert.AreEqual<Integer>(1, Count(TRecordedCallKind.Fill), 'export');
end;

procedure TPageDrawerOptionalContentTests.TestPrintUsageFallsBackToExport;
begin
  Prepare('/OC /on BDC ' + OneFill + ' EMC');
  FBuilder.AddObject(5, '<< /Type /OCG /Name (On) /Usage << /Export << /ExportState /OFF >> /Print << /PrintState /ON >> >> >>');
  Run(TPdfRenderDestination.Print);
  Assert.AreEqual<Integer>(1, Count(TRecordedCallKind.Fill), 'print state on');
  FDevice.Calls.Clear;

  FRenderer := nil;
  FDocument := nil;
  Run(TPdfRenderDestination.View);
  Assert.AreEqual<Integer>(0, Count(TRecordedCallKind.Fill), 'view falls back to export');
end;

procedure TPageDrawerOptionalContentTests.TestUsageOnShowsADisabledGroup;
begin
  Prepare('/OC /off BDC ' + OneFill + ' EMC');
  FBuilder.AddObject(6, '<< /Type /OCG /Name (Off) /Usage << /Export << /ExportState /ON >> >> >>');
  Run;

  Assert.AreEqual<Integer>(1, Count(TRecordedCallKind.Fill));
end;

procedure TPageDrawerOptionalContentTests.TestDocumentWithoutOptionalContentPropertiesDrawsEverything;
begin
  Prepare('/OC /off BDC ' + OneFill + ' EMC');
  FBuilder.AddObject(1, '<< /Type /Catalog /Pages 2 0 R >>');
  Run;

  Assert.AreEqual<Integer>(1, Count(TRecordedCallKind.Fill));
end;

procedure TPageDrawerOptionalContentTests.TestImageWithHiddenOcIsSkipped;
begin
  Prepare('q 50 0 0 50 10 10 cm /Im1 Do Q', ImageResources);
  FBuilder.AddStreamObject(8, '/Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace /DeviceGray /BitsPerComponent 8 /OC 6 0 R',
                           TBytes.Create(128));
  Run;

  Assert.AreEqual<Integer>(0, Count(TRecordedCallKind.Bitmap));
  Assert.AreEqual<Integer>(0, Count(TRecordedCallKind.Fill));
end;

procedure TPageDrawerOptionalContentTests.TestImageWithVisibleOcIsDrawn;
begin
  Prepare('q 50 0 0 50 10 10 cm /Im1 Do Q', ImageResources);
  FBuilder.AddStreamObject(8, '/Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace /DeviceGray /BitsPerComponent 8 /OC 5 0 R',
                           TBytes.Create(128));
  Run;

  Assert.AreEqual<Integer>(1, Count(TRecordedCallKind.Bitmap));
end;

procedure TPageDrawerOptionalContentTests.TestFormWithHiddenOcIsSkipped;
begin
  Prepare('/Fm1 Do', '/XObject << /Fm1 8 0 R >>');
  FBuilder.AddStreamObject(8, '/Type /XObject /Subtype /Form /BBox [0 0 100 100] /OC 6 0 R', TEncoding.ASCII.GetBytes(OneFill));
  Run;

  Assert.AreEqual<Integer>(0, Count(TRecordedCallKind.Fill));
end;

procedure TPageDrawerOptionalContentTests.TestTransparencyGroupWithHiddenOcIsSkipped;
begin
  Prepare('/Fm1 Do', '/XObject << /Fm1 8 0 R >>');
  FBuilder.AddStreamObject(8, '/Type /XObject /Subtype /Form /BBox [0 0 100 100] /Group << /S /Transparency >> /OC 6 0 R',
                           TEncoding.ASCII.GetBytes(OneFill));
  Run;

  Assert.AreEqual<Integer>(0, FDevice.LayerCount, 'no layer is made');
  Assert.AreEqual<Integer>(0, Count(TRecordedCallKind.Fill));
  Assert.AreEqual<Integer>(0, Count(TRecordedCallKind.Bitmap));
end;

procedure TPageDrawerOptionalContentTests.TestFormWithVisibleOcIsDrawn;
begin
  Prepare('/Fm1 Do', '/XObject << /Fm1 8 0 R >>');
  FBuilder.AddStreamObject(8, '/Type /XObject /Subtype /Form /BBox [0 0 100 100] /OC 5 0 R', TEncoding.ASCII.GetBytes(OneFill));
  Run;

  Assert.AreEqual<Integer>(1, Count(TRecordedCallKind.Fill));
end;

procedure TPageDrawerOptionalContentTests.TestFormInsideHiddenSequenceIsSkipped;
begin
  Prepare('/OC /off BDC /Fm1 Do EMC', Properties + ' /XObject << /Fm1 8 0 R >>');
  FBuilder.AddStreamObject(8, '/Type /XObject /Subtype /Form /BBox [0 0 100 100]', TEncoding.ASCII.GetBytes(OneFill));
  Run;

  Assert.AreEqual<Integer>(0, Count(TRecordedCallKind.Fill));
end;

end.
