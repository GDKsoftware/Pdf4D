// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Model.OptionalContent.Tests;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Model.Document,
  Pdf4D.Model.OptionalContent,
  Pdf4D.Model.Tests.Support;

type
  [TestFixture]
  TOptionalContentTests = class
  private
    FDocuments: TModelTestDocuments;
    FDocument: TPDDocument;
    FProperties: TPDOptionalContentProperties;

    // The groups A, B and C are the objects 5, 6 and 7, Config is the text of /D. Other is added to the catalog.
    procedure OpenWith(const Config: string);
    // The dictionary of object Number, found through the document
    function ObjectAt(const Key: string; const Index: Integer): TCosDictionary;
    function GroupAt(const Index: Integer): TCosDictionary;
    function ParsedDictionary(const Entries: string): TCosDictionary;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestBaseStateOnEnablesGroupsExceptOff;

    [Test]
    procedure TestBaseStateOffDisablesGroupsExceptOn;

    [Test]
    procedure TestOnWinsOverOff;

    [Test]
    procedure TestUnchangedAndUnknownBaseStateCountAsOn;

    [Test]
    procedure TestMissingConfigurationEnablesEverything;

    [Test]
    procedure TestEntriesThatAreNoDictionaryAreIgnored;

    [Test]
    procedure TestCatalogWithoutProperties;

    [Test]
    procedure TestKindOf;

    [Test]
    procedure TestRenderStateOfUsage;

    [Test]
    procedure TestRenderStateWithoutUsage;

    [Test]
    procedure TestMembershipGroups;

    [Test]
    procedure TestMembershipPolicyAndExpression;
  end;

implementation

uses
  Pdf4D.Cos.Base,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Tests.PdfBuilder;

const
  GroupBodies: array[0..2] of string = ('<< /Type /OCG /Name (A) >>', '<< /Type /OCG /Name (B) >>', '<< /Type /OCG /Name (C) >>');

{ TOptionalContentTests }

procedure TOptionalContentTests.Setup;
begin
  FDocuments := TModelTestDocuments.Create;
end;

procedure TOptionalContentTests.TearDown;
begin
  FDocuments.Free;
end;

procedure TOptionalContentTests.OpenWith(const Config: string);
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  try
    Builder.AddObject(1, Format('<< /Type /Catalog /Pages 2 0 R /OCProperties << /OCGs [5 0 R 6 0 R 7 0 R] /D << %s >> >> >>', [Config]));
    Builder.AddObject(3, '<< /Type /Page /Parent 2 0 R >>');
    for var Index := 0 to High(GroupBodies) do
    begin
      Builder.AddObject(5 + Index, GroupBodies[Index]);
    end;
    FDocument := FDocuments.Open(Builder);
  finally
    Builder.Free;
  end;
  Assert.IsTrue(FDocument.Catalog.TryGetOptionalContentProperties(FProperties));
end;

function TOptionalContentTests.ObjectAt(const Key: string; const Index: Integer): TCosDictionary;
begin
  var OcProperties: TCosDictionary;
  var Items: TCosArray;
  Assert.IsTrue(FDocument.Catalog.CosObject.TryGetCosDictionary('OCProperties', OcProperties));
  Assert.IsTrue(OcProperties.TryGetCosArray(Key, Items));
  Result := TCosDictionary(Items.GetObject(Index));
end;

function TOptionalContentTests.GroupAt(const Index: Integer): TCosDictionary;
begin
  Result := ObjectAt('OCGs', Index);
end;

// A dictionary that is not part of the document, made by loading a document that holds it as a page
function TOptionalContentTests.ParsedDictionary(const Entries: string): TCosDictionary;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  try
    Builder.AddObject(3, '<< /Type /Page /Parent 2 0 R >>');
    Builder.AddObject(5, Format('<< %s >>', [Entries]));
    Builder.AddObject(6, '<< /Type /OCG /Name (G) /Usage << /View << /ViewState /OFF >> /Print << /PrintState /ON >> /Export << /ExportState /OFF >> >> >>');
    Builder.AddObject(1, '<< /Type /Catalog /Pages 2 0 R /Probe 5 0 R /Group 6 0 R >>');
    FDocument := FDocuments.Open(Builder);
  finally
    Builder.Free;
  end;
  Assert.IsTrue(FDocument.Catalog.CosObject.TryGetCosDictionary('Probe', Result));
end;

procedure TOptionalContentTests.TestBaseStateOnEnablesGroupsExceptOff;
begin
  OpenWith('/BaseState /ON /OFF [6 0 R]');

  Assert.IsTrue(FProperties.IsGroupEnabled(GroupAt(0)));
  Assert.IsFalse(FProperties.IsGroupEnabled(GroupAt(1)));
  Assert.IsTrue(FProperties.IsGroupEnabled(GroupAt(2)));
end;

procedure TOptionalContentTests.TestBaseStateOffDisablesGroupsExceptOn;
begin
  OpenWith('/BaseState /OFF /ON [7 0 R]');

  Assert.IsFalse(FProperties.IsGroupEnabled(GroupAt(0)));
  Assert.IsFalse(FProperties.IsGroupEnabled(GroupAt(1)));
  Assert.IsTrue(FProperties.IsGroupEnabled(GroupAt(2)));
end;

procedure TOptionalContentTests.TestOnWinsOverOff;
begin
  // PDOptionalContentProperties.isGroupEnabled looks in /ON first
  OpenWith('/ON [5 0 R] /OFF [5 0 R 6 0 R]');

  Assert.IsTrue(FProperties.IsGroupEnabled(GroupAt(0)));
  Assert.IsFalse(FProperties.IsGroupEnabled(GroupAt(1)));
end;

procedure TOptionalContentTests.TestUnchangedAndUnknownBaseStateCountAsOn;
begin
  OpenWith('/BaseState /Unchanged /OFF [5 0 R]');
  Assert.IsFalse(FProperties.IsGroupEnabled(GroupAt(0)));
  Assert.IsTrue(FProperties.IsGroupEnabled(GroupAt(1)));

  OpenWith('/BaseState /Whatever /OFF [5 0 R]');
  Assert.IsFalse(FProperties.IsGroupEnabled(GroupAt(0)));
  Assert.IsTrue(FProperties.IsGroupEnabled(GroupAt(1)));
end;

procedure TOptionalContentTests.TestMissingConfigurationEnablesEverything;
begin
  OpenWith('');

  Assert.IsTrue(FProperties.IsGroupEnabled(GroupAt(0)));
  Assert.IsTrue(FProperties.IsGroupEnabled(GroupAt(2)));
end;

procedure TOptionalContentTests.TestEntriesThatAreNoDictionaryAreIgnored;
begin
  OpenWith('/BaseState /ON /OFF [1 (x) /N null 6 0 R 99 0 R]');

  Assert.IsFalse(FProperties.IsGroupEnabled(GroupAt(1)));
  Assert.IsTrue(FProperties.IsGroupEnabled(GroupAt(0)));
end;

procedure TOptionalContentTests.TestCatalogWithoutProperties;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  try
    Builder.AddObject(3, '<< /Type /Page /Parent 2 0 R >>');
    FDocument := FDocuments.Open(Builder);
  finally
    Builder.Free;
  end;

  Assert.IsFalse(FDocument.Catalog.TryGetOptionalContentProperties(FProperties));
end;

procedure TOptionalContentTests.TestKindOf;
begin
  Assert.AreEqual(TPDOptionalContentKind.Group, TPDPropertyList.KindOf(ParsedDictionary('/Type /OCG')));
  Assert.AreEqual(TPDOptionalContentKind.Membership, TPDPropertyList.KindOf(ParsedDictionary('/Type /OCMD')));
  Assert.AreEqual(TPDOptionalContentKind.Other, TPDPropertyList.KindOf(ParsedDictionary('/Type /Foo')));
  Assert.AreEqual(TPDOptionalContentKind.Other, TPDPropertyList.KindOf(ParsedDictionary('/MCID 3')));
  Assert.AreEqual(TPDOptionalContentKind.Other, TPDPropertyList.KindOf(ParsedDictionary('/Type (OCG)')));
end;

procedure TOptionalContentTests.TestRenderStateOfUsage;
begin
  ParsedDictionary('');
  var Group: TCosDictionary;
  Assert.IsTrue(FDocument.Catalog.CosObject.TryGetCosDictionary('Group', Group));

  var IsOn: Boolean;
  Assert.IsTrue(TPDOptionalContentGroup.TryGetRenderState(Group, TPDOptionalContentUsage.View, IsOn));
  Assert.IsFalse(IsOn, 'View');
  Assert.IsTrue(TPDOptionalContentGroup.TryGetRenderState(Group, TPDOptionalContentUsage.Print, IsOn));
  Assert.IsTrue(IsOn, 'Print');
  Assert.IsTrue(TPDOptionalContentGroup.TryGetRenderState(Group, TPDOptionalContentUsage.Export, IsOn));
  Assert.IsFalse(IsOn, 'Export');
end;

procedure TOptionalContentTests.TestRenderStateWithoutUsage;
begin
  // The view and print usage fall back to the export usage; a state that is neither ON nor OFF is undefined
  const Group = ParsedDictionary('/Type /OCG /Usage << /Export << /ExportState /Off >> /View << /ViewState /Maybe >> >>');
  var IsOn: Boolean;

  Assert.IsTrue(TPDOptionalContentGroup.TryGetRenderState(Group, TPDOptionalContentUsage.Print, IsOn), 'print falls back to export');
  Assert.IsFalse(IsOn);
  Assert.IsTrue(TPDOptionalContentGroup.TryGetRenderState(Group, TPDOptionalContentUsage.View, IsOn), 'unknown view state falls back to export');
  Assert.IsFalse(IsOn);

  const Plain = ParsedDictionary('/Type /OCG');
  Assert.IsFalse(TPDOptionalContentGroup.TryGetRenderState(Plain, TPDOptionalContentUsage.View, IsOn));
end;

procedure TOptionalContentTests.TestMembershipGroups;
begin
  Assert.AreEqual<Integer>(0, Length(TPDOptionalContentMembership.Groups(ParsedDictionary('/Type /OCMD'))));
  Assert.AreEqual<Integer>(0, Length(TPDOptionalContentMembership.Groups(ParsedDictionary('/Type /OCMD /OCGs 5'))));
  Assert.AreEqual<Integer>(1, Length(TPDOptionalContentMembership.Groups(ParsedDictionary('/Type /OCMD /OCGs 6 0 R'))));
  // Entries that are no dictionary are left out
  Assert.AreEqual<Integer>(2, Length(TPDOptionalContentMembership.Groups(ParsedDictionary('/Type /OCMD /OCGs [6 0 R 1 (x) null 6 0 R]'))));
end;

procedure TOptionalContentTests.TestMembershipPolicyAndExpression;
begin
  Assert.AreEqual('AnyOn', TPDOptionalContentMembership.VisibilityPolicy(ParsedDictionary('/Type /OCMD')));
  Assert.AreEqual('AllOff', TPDOptionalContentMembership.VisibilityPolicy(ParsedDictionary('/Type /OCMD /P /AllOff')));
  Assert.AreEqual('AnyOn', TPDOptionalContentMembership.VisibilityPolicy(ParsedDictionary('/Type /OCMD /P (AllOff)')));

  var Expression: TCosArray;
  Assert.IsFalse(TPDOptionalContentMembership.TryGetVisibilityExpression(ParsedDictionary('/Type /OCMD'), Expression));
  Assert.IsFalse(TPDOptionalContentMembership.TryGetVisibilityExpression(ParsedDictionary('/Type /OCMD /VE []'), Expression), 'empty');
  Assert.IsFalse(TPDOptionalContentMembership.TryGetVisibilityExpression(ParsedDictionary('/Type /OCMD /VE 5'), Expression));
  Assert.IsTrue(TPDOptionalContentMembership.TryGetVisibilityExpression(ParsedDictionary('/Type /OCMD /VE [/Not 6 0 R]'), Expression));
  Assert.AreEqual<Integer>(2, Expression.Count);
end;

end.
