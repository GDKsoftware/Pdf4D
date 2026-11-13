unit Pdf4D.Model.Field.Tests;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Model.AcroForm,
  Pdf4D.Model.Tests.Support,
  Pdf4D.Tests.PdfBuilder;

type
  [TestFixture]
  TFieldTests = class
  private
    FDocuments: TModelTestDocuments;

    function OpenForm(const Builder: TTestPdfBuilder): TPDAcroForm;
    function NewFormBuilder(const FormExtra: string): TTestPdfBuilder;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestTextFieldValueAndQualifiedName;

    [Test]
    procedure TestInheritedFieldType;

    [Test]
    procedure TestCheckBoxValue;

    [Test]
    procedure TestRadioFlagWins;

    [Test]
    procedure TestKindsFollowTheTypeAndTheFlagsOfTheField;

    [Test]
    procedure TestChoiceMultipleValues;

    [Test]
    procedure TestWidgetKidsAreNotFields;

    [Test]
    procedure TestFieldTreeCycleTerminates;

    [Test]
    procedure TestFieldTreeIsDepthFirstAndSkipsARepeatedField;

    [Test]
    procedure TestKindUsesOnlyTheOwnFlags;

    [Test]
    procedure TestFlagsOfATerminalFieldAreInherited;

    [Test]
    procedure TestValueIsInheritedFromTheParentAndTheForm;

    [Test]
    procedure TestTextValueFromAStream;

    [Test]
    procedure TestExportValueByIndex;

    [Test]
    procedure TestOnValuesComeFromTheAppearance;

    [Test]
    procedure TestTryGetField;

    [Test]
    procedure TestObjectWithoutTypeIsNoField;

    [Test]
    procedure TestKidWithoutNameButWithTypeIsAChildField;

    [Test]
    procedure TestArrayWithIndirectStringRaises;

    [Test]
    procedure TestVeryDeepChainIsCutOff;

    [Test]
    procedure TestCatalogGivesNoFormWithoutAcroForm;
  end;

implementation

uses
  System.Classes,
  Pdf4D.Common.Defines,
  Pdf4D.Model.Document,
  Pdf4D.Model.Field;

{ TFieldTests }

procedure TFieldTests.Setup;
begin
  FDocuments := TModelTestDocuments.Create;
end;

procedure TFieldTests.TearDown;
begin
  FDocuments.Free;
end;

function TFieldTests.NewFormBuilder(const FormExtra: string): TTestPdfBuilder;
begin
  Result := TModelTestDocuments.NewBuilderWithPages(1, '/AcroForm 3 0 R');
  try
    Result.AddObject(3, Format('<< %s >>', [FormExtra]));
  except
    Result.Free;
    raise;
  end;
end;

function TFieldTests.OpenForm(const Builder: TTestPdfBuilder): TPDAcroForm;
begin
  var Form: TPDAcroForm;
  Assert.IsTrue(FDocuments.Open(Builder).Catalog.TryGetAcroForm(Form));
  Result := Form;
end;

procedure TFieldTests.TestTextFieldValueAndQualifiedName;
begin
  const Builder = NewFormBuilder('/Fields [4 0 R]');
  try
    Builder.AddObject(4, '<< /T (person) /Kids [5 0 R] >>');
    Builder.AddObject(5, '<< /T (name) /TU (The name) /FT /Tx /V (Jan) /Parent 4 0 R >>');
    const Form = OpenForm(Builder);

    Assert.AreEqual<Integer>(1, Length(Form.Fields));
    Assert.AreEqual<Integer>(2, Length(Form.GetFieldTree));
    Assert.AreEqual(TPdfFieldKind.NonTerminal, Form.Fields[0].Kind);
    Assert.AreEqual('', Form.Fields[0].ValueAsString);
    const Child = Form.Fields[0].Children[0];
    Assert.AreEqual('person.name', Child.FullyQualifiedName);
    Assert.AreEqual('name', Child.PartialName);
    Assert.AreEqual('The name', Child.AlternateName);
    Assert.AreEqual(TPdfFieldKind.Text, Child.Kind);
    Assert.AreEqual('Jan', Child.ValueAsString);
    Assert.IsTrue(Child.Parent = Form.Fields[0]);
  finally
    Builder.Free;
  end;
end;

procedure TFieldTests.TestInheritedFieldType;
begin
  const Builder = NewFormBuilder('/Fields [4 0 R]');
  try
    Builder.AddObject(4, '<< /T (a) /FT /Tx /Kids [5 0 R] >>');
    Builder.AddObject(5, '<< /T (b) /Parent 4 0 R >>');
    const Form = OpenForm(Builder);

    Assert.AreEqual(TPdfFieldKind.NonTerminal, Form.Fields[0].Kind);
    Assert.AreEqual(TPdfFieldKind.Text, Form.Fields[0].Children[0].Kind);
  finally
    Builder.Free;
  end;
end;

procedure TFieldTests.TestCheckBoxValue;
begin
  const Builder = NewFormBuilder('/Fields [4 0 R 5 0 R 6 0 R 7 0 R]');
  try
    Builder.AddObject(4, '<< /T (on) /FT /Btn /V /Yes >>');
    Builder.AddObject(5, '<< /T (off) /FT /Btn /V /Off >>');
    Builder.AddObject(6, '<< /T (none) /FT /Btn >>');
    Builder.AddObject(7, '<< /T (text) /FT /Btn /V (Yes) >>');
    const Form = OpenForm(Builder);

    Assert.AreEqual(TPdfFieldKind.CheckBox, Form.Fields[0].Kind);
    Assert.AreEqual('Yes', Form.Fields[0].ValueAsString);
    Assert.AreEqual('Off', Form.Fields[1].ValueAsString);
    Assert.AreEqual('Off', Form.Fields[2].ValueAsString);
    Assert.AreEqual('Off', Form.Fields[3].ValueAsString);
  finally
    Builder.Free;
  end;
end;

procedure TFieldTests.TestRadioFlagWins;
begin
  const Builder = NewFormBuilder('/Fields [4 0 R]');
  try
    Builder.AddObject(4, '<< /T (r) /FT /Btn /Ff 32768 /V /Two /Kids [5 0 R] >>');
    Builder.AddObject(5, '<< /Subtype /Widget /Parent 4 0 R >>');
    const Form = OpenForm(Builder);

    Assert.AreEqual(TPdfFieldKind.RadioButton, Form.Fields[0].Kind);
    Assert.AreEqual('Two', Form.Fields[0].ValueAsString);
    Assert.AreEqual(32768, Form.Fields[0].Flags);
  finally
    Builder.Free;
  end;
end;

procedure TFieldTests.TestKindsFollowTheTypeAndTheFlagsOfTheField;
begin
  const Builder = NewFormBuilder('/Fields [4 0 R 5 0 R 6 0 R 7 0 R 8 0 R]');
  try
    Builder.AddObject(4, '<< /T (push) /FT /Btn /Ff 65536 /V /X >>');
    Builder.AddObject(5, '<< /T (combo) /FT /Ch /Ff 131072 >>');
    Builder.AddObject(6, '<< /T (list) /FT /Ch >>');
    Builder.AddObject(7, '<< /T (sig) /FT /Sig /V << /Type /Sig >> >>');
    Builder.AddObject(8, '<< /T (both) /FT /Btn /Ff 98304 >>');
    const Fields = OpenForm(Builder).Fields;

    Assert.AreEqual(TPdfFieldKind.PushButton, Fields[0].Kind);
    Assert.AreEqual('', Fields[0].ValueAsString);
    Assert.AreEqual(TPdfFieldKind.ComboBox, Fields[1].Kind);
    Assert.AreEqual(TPdfFieldKind.ListBox, Fields[2].Kind);
    Assert.AreEqual(TPdfFieldKind.Signature, Fields[3].Kind);
    Assert.AreEqual('', Fields[3].ValueAsString);
    Assert.AreEqual(TPdfFieldKind.RadioButton, Fields[4].Kind);
  finally
    Builder.Free;
  end;
end;

procedure TFieldTests.TestChoiceMultipleValues;
begin
  const Builder = NewFormBuilder('/Fields [4 0 R 5 0 R 6 0 R]');
  try
    Builder.AddObject(4, '<< /T (multi) /FT /Ch /V [(a) (b)] >>');
    Builder.AddObject(5, '<< /T (single) /FT /Ch /Ff 131072 /V (x) >>');
    Builder.AddObject(6, '<< /T (empty) /FT /Ch >>');
    const Fields = OpenForm(Builder).Fields;

    Assert.AreEqual<Integer>(2, Length(Fields[0].Values));
    Assert.AreEqual('a', Fields[0].Values[0]);
    Assert.AreEqual('b', Fields[0].Values[1]);
    Assert.AreEqual('[a, b]', Fields[0].ValueAsString);
    Assert.AreEqual('x', Fields[1].Values[0]);
    Assert.AreEqual('[x]', Fields[1].ValueAsString);
    Assert.AreEqual<Integer>(0, Length(Fields[2].Values));
    Assert.AreEqual('[]', Fields[2].ValueAsString);
  finally
    Builder.Free;
  end;
end;

procedure TFieldTests.TestWidgetKidsAreNotFields;
begin
  const Builder = NewFormBuilder('/Fields [4 0 R]');
  try
    Builder.AddObject(4, '<< /T (f) /FT /Tx /Kids [5 0 R 6 0 R] >>');
    Builder.AddObject(5, '<< /Subtype /Widget /Parent 4 0 R >>');
    Builder.AddObject(6, '<< /Subtype /Widget /Parent 4 0 R >>');
    const Form = OpenForm(Builder);

    Assert.AreEqual<Integer>(1, Length(Form.GetFieldTree));
    Assert.AreEqual(TPdfFieldKind.Text, Form.Fields[0].Kind);
    Assert.AreEqual<Integer>(0, Length(Form.Fields[0].Children));
  finally
    Builder.Free;
  end;
end;

procedure TFieldTests.TestFieldTreeCycleTerminates;
begin
  const Builder = NewFormBuilder('/Fields [4 0 R]');
  try
    Builder.AddObject(4, '<< /T (a) /Kids [5 0 R 4 0 R] /Parent 5 0 R >>');
    Builder.AddObject(5, '<< /T (b) /Kids [4 0 R] /Parent 4 0 R >>');
    const Form = OpenForm(Builder);

    const Tree = Form.GetFieldTree;

    Assert.AreEqual<Integer>(2, Length(Tree));
    Assert.AreEqual('a', Tree[0].FullyQualifiedName);
    Assert.AreEqual('a.b', Tree[1].FullyQualifiedName);
  finally
    Builder.Free;
  end;
end;

procedure TFieldTests.TestFieldTreeIsDepthFirstAndSkipsARepeatedField;
begin
  const Builder = NewFormBuilder('/Fields [4 0 R 7 0 R]');
  try
    Builder.AddObject(4, '<< /T (a) /Kids [5 0 R 6 0 R 5 0 R] >>');
    Builder.AddObject(5, '<< /T (x) /FT /Tx /Parent 4 0 R >>');
    Builder.AddObject(6, '<< /T (y) /FT /Tx /Parent 4 0 R >>');
    Builder.AddObject(7, '<< /T (b) /FT /Tx >>');
    const Tree = OpenForm(Builder).GetFieldTree;

    Assert.AreEqual<Integer>(4, Length(Tree));
    Assert.AreEqual('a', Tree[0].FullyQualifiedName);
    Assert.AreEqual('a.x', Tree[1].FullyQualifiedName);
    Assert.AreEqual('a.y', Tree[2].FullyQualifiedName);
    Assert.AreEqual('b', Tree[3].FullyQualifiedName);
  finally
    Builder.Free;
  end;
end;

procedure TFieldTests.TestKindUsesOnlyTheOwnFlags;
begin
  const Builder = NewFormBuilder('/Fields [4 0 R]');
  try
    Builder.AddObject(4, '<< /T (p) /FT /Btn /Ff 32768 /Kids [5 0 R] >>');
    Builder.AddObject(5, '<< /T (k) /Parent 4 0 R >>');
    const Child = OpenForm(Builder).Fields[0].Children[0];

    Assert.AreEqual(TPdfFieldKind.CheckBox, Child.Kind);
    Assert.AreEqual(32768, Child.Flags);
  finally
    Builder.Free;
  end;
end;

procedure TFieldTests.TestFlagsOfATerminalFieldAreInherited;
begin
  const Builder = NewFormBuilder('/Fields [4 0 R]');
  try
    Builder.AddObject(4, '<< /T (p) /Ff 5 /Kids [5 0 R 6 0 R] >>');
    Builder.AddObject(5, '<< /T (k) /FT /Tx /Parent 4 0 R >>');
    Builder.AddObject(6, '<< /T (l) /FT /Tx /Ff 2 /Parent 4 0 R >>');
    const Parent = OpenForm(Builder).Fields[0];

    Assert.AreEqual(5, Parent.Flags);
    Assert.AreEqual(5, Parent.Children[0].Flags);
    Assert.AreEqual(2, Parent.Children[1].Flags);
  finally
    Builder.Free;
  end;
end;

procedure TFieldTests.TestValueIsInheritedFromTheParentAndTheForm;
begin
  const Builder = NewFormBuilder('/Fields [4 0 R 6 0 R] /V (formvalue)');
  try
    Builder.AddObject(4, '<< /T (p) /V (parentvalue) /Kids [5 0 R] >>');
    Builder.AddObject(5, '<< /T (k) /FT /Tx /Parent 4 0 R >>');
    Builder.AddObject(6, '<< /T (own) /FT /Tx >>');
    const Form = OpenForm(Builder);

    Assert.AreEqual('parentvalue', Form.Fields[0].Children[0].ValueAsString);
    Assert.AreEqual('formvalue', Form.Fields[1].ValueAsString);
  finally
    Builder.Free;
  end;
end;

procedure TFieldTests.TestTextValueFromAStream;
begin
  const Builder = NewFormBuilder('/Fields [4 0 R]');
  try
    Builder.AddObject(4, '<< /T (rich) /FT /Tx /V 5 0 R >>');
    Builder.AddStreamObject(5, '', TEncoding.ASCII.GetBytes('rich text'));
    const Form = OpenForm(Builder);

    Assert.AreEqual('rich text', Form.Fields[0].ValueAsString);
  finally
    Builder.Free;
  end;
end;

procedure TFieldTests.TestExportValueByIndex;
begin
  const Builder = NewFormBuilder('/Fields [4 0 R 5 0 R 6 0 R 7 0 R]');
  try
    Builder.AddObject(4, '<< /T (a) /FT /Btn /Ff 32768 /Opt [(first) (second)] /V /1 >>');
    Builder.AddObject(5, '<< /T (b) /FT /Btn /Ff 32768 /Opt [(first) (second)] /V /5 >>');
    Builder.AddObject(6, '<< /T (c) /FT /Btn /Ff 32768 /Opt [(first) (second)] /V /x >>');
    Builder.AddObject(7, '<< /T (d) /FT /Btn /Ff 32768 /Opt (only) /V /0 >>');
    const Fields = OpenForm(Builder).Fields;

    Assert.AreEqual('second', Fields[0].ValueAsString);
    Assert.AreEqual('5', Fields[1].ValueAsString);
    Assert.AreEqual('x', Fields[2].ValueAsString);
    Assert.AreEqual('only', Fields[3].ValueAsString);
    Assert.AreEqual<Integer>(2, Length(Fields[0].ExportValues));
    Assert.AreEqual('second', Fields[0].ExportValues[1]);
  finally
    Builder.Free;
  end;
end;

procedure TFieldTests.TestOnValuesComeFromTheAppearance;
begin
  const Builder = NewFormBuilder('/Fields [4 0 R 8 0 R]');
  try
    Builder.AddObject(4, '<< /T (r) /FT /Btn /Ff 32768 /Kids [5 0 R 6 0 R 7 0 R] >>');
    Builder.AddObject(5, '<< /Subtype /Widget /Parent 4 0 R /AP << /N << /A 9 0 R /Off 9 0 R >> >> >>');
    Builder.AddObject(6, '<< /Subtype /Widget /Parent 4 0 R /AP << /N << /Off 9 0 R /B 9 0 R >> >> >>');
    Builder.AddObject(7, '<< /Subtype /Widget /Parent 4 0 R /AP << /N << /A 9 0 R >> >> >>');
    Builder.AddObject(8, '<< /T (c) /FT /Btn /Opt [(one) (one) (two)] >>');
    Builder.AddStreamObject(9, '', nil);
    const Fields = OpenForm(Builder).Fields;

    Assert.AreEqual<Integer>(2, Length(Fields[0].OnValues));
    Assert.AreEqual('A', Fields[0].OnValues[0]);
    Assert.AreEqual('B', Fields[0].OnValues[1]);
    Assert.AreEqual<Integer>(2, Length(Fields[1].OnValues));
    Assert.AreEqual('one', Fields[1].OnValues[0]);
    Assert.AreEqual('two', Fields[1].OnValues[1]);
  finally
    Builder.Free;
  end;
end;

procedure TFieldTests.TestTryGetField;
begin
  const Builder = NewFormBuilder('/Fields [4 0 R]');
  try
    Builder.AddObject(4, '<< /T (person) /Kids [5 0 R] >>');
    Builder.AddObject(5, '<< /T (name) /FT /Tx /Parent 4 0 R >>');
    const Form = OpenForm(Builder);

    var Field: TPDField;
    Assert.IsTrue(Form.TryGetField('person.name', Field));
    Assert.AreEqual(TPdfFieldKind.Text, Field.Kind);
    Assert.IsFalse(Form.TryGetField('person.nothing', Field));
    Assert.IsFalse(Form.TryGetField('', Field));
  finally
    Builder.Free;
  end;
end;

procedure TFieldTests.TestObjectWithoutTypeIsNoField;
begin
  const Builder = NewFormBuilder('/Fields [4 0 R 5 0 R 6 0 R (text) 7 0 R]');
  try
    Builder.AddObject(4, '<< /T (no type) >>');
    Builder.AddObject(5, '<< /T (strange) /FT /Foo >>');
    Builder.AddObject(6, '<< /T (named) /FT /Tx >>');
    Builder.AddObject(7, '<< /Kids [8 0 R] >>');
    Builder.AddObject(8, '<< /FT /Tx >>');
    const Form = OpenForm(Builder);

    Assert.AreEqual<Integer>(1, Length(Form.Fields));
    Assert.AreEqual('named', Form.Fields[0].FullyQualifiedName);
  finally
    Builder.Free;
  end;
end;

procedure TFieldTests.TestKidWithoutNameButWithTypeIsAChildField;
begin
  const Builder = NewFormBuilder('/Fields [4 0 R]');
  try
    Builder.AddObject(4, '<< /T (p) /Kids [5 0 R 6 0 R] >>');
    Builder.AddObject(5, '<< /T (named) /FT /Tx /Parent 4 0 R >>');
    Builder.AddObject(6, '<< /FT /Tx /Parent 4 0 R /V (anonymous) >>');
    const Children = OpenForm(Builder).Fields[0].Children;

    Assert.AreEqual<Integer>(2, Length(Children));
    Assert.AreEqual('p', Children[1].FullyQualifiedName);
    Assert.AreEqual('', Children[1].PartialName);
    Assert.AreEqual('anonymous', Children[1].ValueAsString);
  finally
    Builder.Free;
  end;
end;

procedure TFieldTests.TestArrayWithIndirectStringRaises;
begin
  const Builder = NewFormBuilder('/Fields [4 0 R 5 0 R]');
  try
    Builder.AddObject(4, '<< /T (c) /FT /Ch /V [6 0 R] >>');
    Builder.AddObject(5, '<< /T (b) /FT /Btn /V /1 /Opt [(a) 1] >>');
    Builder.AddObject(6, '(indirect)');
    const Fields = OpenForm(Builder).Fields;

    Assert.WillRaise(
      procedure
      begin
        Fields[0].Values;
      end,
      EPdfParseException);
    Assert.WillRaise(
      procedure
      begin
        Fields[1].ValueAsString;
      end,
      EPdfParseException);
  finally
    Builder.Free;
  end;
end;

procedure TFieldTests.TestVeryDeepChainIsCutOff;
begin
  const ChainLength = 2000;
  const Builder = NewFormBuilder('/Fields [4 0 R]');
  try
    for var Level := 0 to ChainLength - 1 do
    begin
      Builder.AddObject(4 + Level, Format('<< /T (n) /FT /Tx /Kids [%d 0 R] /Parent %d 0 R >>', [5 + Level, 3 + Level]));
    end;
    Builder.AddObject(4 + ChainLength, '<< /T (end) /FT /Tx >>');
    const Form = OpenForm(Builder);

    const Tree = Form.GetFieldTree;

    Assert.IsTrue(Length(Tree) <= MaxFieldDepth + 1);
    Assert.IsTrue(Length(Tree) > 10);
  finally
    Builder.Free;
  end;
end;

procedure TFieldTests.TestCatalogGivesNoFormWithoutAcroForm;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, '');
  try
    var Form: TPDAcroForm;
    Assert.IsFalse(FDocuments.Open(Builder).Catalog.TryGetAcroForm(Form));
  finally
    Builder.Free;
  end;
end;

end.
