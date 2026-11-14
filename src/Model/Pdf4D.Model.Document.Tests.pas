// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Model.Document.Tests;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Model.Tests.Support;

type
  [TestFixture]
  TDocumentTests = class
  private
    FDocuments: TModelTestDocuments;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestVersionFromCatalogWins;

    [Test]
    procedure TestHeaderVersionWinsWhenItIsHigher;

    [Test]
    procedure TestCatalogVersionIsIgnoredBelowHeader14;

    [Test]
    procedure TestUnparsableCatalogVersionCountsAsAbsent;

    [Test]
    procedure TestPlainDocumentIsNotEncrypted;

    [Test]
    procedure TestNotAPdfRaisesAPdfException;

    [Test]
    procedure TestInformationKeepsFileOrderAndRawValues;

    [Test]
    procedure TestInformationDates;

    [Test]
    procedure TestMissingInformationGivesEmptyValues;

    [Test]
    procedure TestCatalogEntries;
  end;

implementation

uses
  System.Classes,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Model.AcroForm,
  Pdf4D.Model.Document,
  Pdf4D.Model.Outline;

{ TDocumentTests }

procedure TDocumentTests.Setup;
begin
  FDocuments := TModelTestDocuments.Create;
end;

procedure TDocumentTests.TearDown;
begin
  FDocuments.Free;
end;

procedure TDocumentTests.TestVersionFromCatalogWins;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [] /Count 0 >>');
  try
    Builder.AddObject(1, '<< /Type /Catalog /Pages 2 0 R /Version /1.7 >>');

    Assert.AreEqual<Single>(1.7, FDocuments.Open(Builder, '4').Version);
  finally
    Builder.Free;
  end;
end;

procedure TDocumentTests.TestHeaderVersionWinsWhenItIsHigher;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [] /Count 0 >>');
  try
    Builder.AddObject(1, '<< /Type /Catalog /Pages 2 0 R /Version /1.5 >>');

    Assert.AreEqual<Single>(1.7, FDocuments.Open(Builder, '7').Version);
  finally
    Builder.Free;
  end;
end;

procedure TDocumentTests.TestCatalogVersionIsIgnoredBelowHeader14;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [] /Count 0 >>');
  try
    Builder.AddObject(1, '<< /Type /Catalog /Pages 2 0 R /Version /1.7 >>');

    // PDFBox only reads the catalog version when the header says 1.4 or more
    Assert.AreEqual<Single>(1.3, FDocuments.Open(Builder, '3').Version);
  finally
    Builder.Free;
  end;
end;

procedure TDocumentTests.TestUnparsableCatalogVersionCountsAsAbsent;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [] /Count 0 >>');
  try
    Builder.AddObject(1, '<< /Type /Catalog /Pages 2 0 R /Version /abc >>');

    Assert.AreEqual<Single>(1.5, FDocuments.Open(Builder, '5').Version);
    Assert.IsTrue(FDocuments.HasLogLine('version number of the document catalog'));
  finally
    Builder.Free;
  end;
end;

procedure TDocumentTests.TestPlainDocumentIsNotEncrypted;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [] /Count 0 >>');
  try
    const Document = FDocuments.Open(Builder);

    Assert.IsFalse(Document.IsEncrypted);
    Assert.IsNotNull(Document.AccessPermission);
    Assert.IsTrue(Document.AccessPermission.CanPrint);
    Assert.IsNotNull(Document.CosDocument);
  finally
    Builder.Free;
  end;
end;

procedure TDocumentTests.TestNotAPdfRaisesAPdfException;
begin
  Assert.WillRaiseDescendant(
    procedure
    begin
      TPDDocument.Load(TBytesStream.Create(TEncoding.ASCII.GetBytes('this is not a pdf file')), True, TPdfLoadOptions.Default);
    end, EPdfException);
end;

procedure TDocumentTests.TestInformationKeepsFileOrderAndRawValues;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [] /Count 0 >>');
  try
    Builder.AddObject(3, '<< /Title (Hello) /Zed 12 /Author <FEFF00410042> /Alpha (x) /Trapped /True /Subject (S) /Keywords (K) /Creator (C) /Producer (P) >>');
    Builder.TrailerExtra := '/Info 3 0 R';
    const Information = FDocuments.Open(Builder).DocumentInformation;

    Assert.AreEqual('Hello', Information.Title);
    Assert.AreEqual('AB', Information.Author);
    Assert.AreEqual('S', Information.Subject);
    Assert.AreEqual('K', Information.Keywords);
    Assert.AreEqual('C', Information.Creator);
    Assert.AreEqual('P', Information.Producer);
    Assert.AreEqual('True', Information.Trapped);
    Assert.AreEqual('Title,Zed,Author,Alpha,Trapped,Subject,Keywords,Creator,Producer', string.Join(',', Information.Keys));

    var Value: string;
    Assert.IsTrue(Information.TryGetCustomValue('Alpha', Value));
    Assert.AreEqual('x', Value);
    // A value that is no string, and one that is missing
    Assert.IsFalse(Information.TryGetCustomValue('Zed', Value));
    Assert.IsFalse(Information.TryGetCustomValue('Nope', Value));

    Assert.IsTrue(Information.CosObject.GetItem('Zed') is TCosBase);
    Assert.AreEqual(12, Information.CosObject.GetInt('Zed', 0));
  finally
    Builder.Free;
  end;
end;

procedure TDocumentTests.TestInformationDates;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [] /Count 0 >>');
  try
    Builder.AddObject(3, '<< /CreationDate (D:20050512235959+02''00'') /ModDate (not a date) >>');
    Builder.TrailerExtra := '/Info 3 0 R';
    const Information = FDocuments.Open(Builder).DocumentInformation;

    var Value: TDateTime;
    var OffsetMinutes: Integer;
    Assert.IsTrue(Information.TryGetCreationDate(Value, OffsetMinutes));
    Assert.AreEqual(120, OffsetMinutes);
    Assert.AreEqual<TDateTime>(EncodeDate(2005, 5, 12) + EncodeTime(23, 59, 59, 0), Value);
    Assert.IsFalse(Information.TryGetModificationDate(Value, OffsetMinutes));
  finally
    Builder.Free;
  end;
end;

procedure TDocumentTests.TestMissingInformationGivesEmptyValues;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [] /Count 0 >>');
  try
    const Information = FDocuments.Open(Builder).DocumentInformation;

    Assert.AreEqual('', Information.Title);
    Assert.AreEqual<Integer>(0, Length(Information.Keys));
    var Value: TDateTime;
    var OffsetMinutes: Integer;
    Assert.IsFalse(Information.TryGetCreationDate(Value, OffsetMinutes));
  finally
    Builder.Free;
  end;
end;

procedure TDocumentTests.TestCatalogEntries;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [] /Count 0 >>');
  try
    Builder.AddObject(1, '<< /Type /Catalog /Pages 2 0 R /Outlines 3 0 R /PageLabels << /Nums [] >> /AcroForm << /Fields [] >> /Names << >> /Dests << >> /Metadata 4 0 R /Version /1.6 >>');
    Builder.AddObject(3, '<< /Type /Outlines >>');
    Builder.AddStreamObject(4, '/Type /Metadata /Subtype /XML', TEncoding.ASCII.GetBytes('<x/>'));
    const Catalog = FDocuments.Open(Builder).Catalog;

    var Dictionary: TCosDictionary;
    var Metadata: TCosStream;
    var Outline: TPDDocumentOutline;
    Assert.IsTrue(Catalog.TryGetOutline(Outline));
    Assert.IsTrue(Catalog.TryGetPageLabels(Dictionary));
    var AcroForm: TPDAcroForm;
    Assert.IsTrue(Catalog.TryGetAcroForm(AcroForm));
    Assert.IsTrue(Catalog.TryGetNames(Dictionary));
    Assert.IsTrue(Catalog.TryGetDests(Dictionary));
    Assert.IsTrue(Catalog.TryGetMetadata(Metadata));
    Assert.AreEqual('1.6', Catalog.Version);
  finally
    Builder.Free;
  end;

  const Plain = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [] /Count 0 >>');
  try
    const PlainCatalog = FDocuments.Open(Plain).Catalog;

    var Metadata: TCosStream;
    var Outline: TPDDocumentOutline;
    Assert.IsFalse(PlainCatalog.TryGetOutline(Outline));
    Assert.IsFalse(PlainCatalog.TryGetMetadata(Metadata));
    Assert.AreEqual('', PlainCatalog.Version);
  finally
    Plain.Free;
  end;
end;

end.
