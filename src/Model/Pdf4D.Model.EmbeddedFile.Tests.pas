// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
unit Pdf4D.Model.EmbeddedFile.Tests;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Model.Tests.Support;

type
  [TestFixture]
  TEmbeddedFileTests = class
  private
    FDocuments: TModelTestDocuments;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestEmbeddedFilePrefersUF;

    [Test]
    procedure TestFilenameFallsBackThroughTheEntriesAndThenTheKey;

    [Test]
    procedure TestDataIsDecodedThroughTheFilters;

    [Test]
    procedure TestSizeComesOnlyFromTheParams;

    [Test]
    procedure TestEntryWithoutStreamHasNoDataAndNoSize;

    [Test]
    procedure TestOnlyTheStreamF;

    [Test]
    procedure TestDataBeyondTheLimitRaises;

    [Test]
    procedure TestTreeWithKidsGivesTheEntriesInOrder;

    [Test]
    procedure TestValueThatIsNoDictionaryRaisesAndNullIsAnEmptySpecification;

    [Test]
    procedure TestNoEmbeddedFilesGivesNoEntries;

    [Test]
    procedure TestTheDocumentOwnsTheEntries;
  end;

implementation

uses
  System.DateUtils,
  Pdf4D.Common.Defines,
  Pdf4D.Model.Document,
  Pdf4D.Model.EmbeddedFile,
  Pdf4D.Tests.PdfBuilder;

const
  CatalogExtra = '/Names << /EmbeddedFiles 3 0 R >>';

{ TEmbeddedFileTests }

procedure TEmbeddedFileTests.Setup;
begin
  FDocuments := TModelTestDocuments.Create;
end;

procedure TEmbeddedFileTests.TearDown;
begin
  FDocuments.Free;
end;

procedure TEmbeddedFileTests.TestEmbeddedFilePrefersUF;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, CatalogExtra);
  try
    Builder.AddObject(3, '<< /Names [(key.txt) 4 0 R] >>');
    Builder.AddObject(4, '<< /Type /Filespec /F (a.txt) /UF <FEFF00E4002E007400780074> /Desc (A description) /EF << /F 5 0 R >> >>');
    Builder.AddStreamObject(5, '/Type /EmbeddedFile /Subtype /text#2Fplain /Params << /Size 5 /CreationDate (D:20240102030405Z) /ModDate (D:20240102030406+01''00'') >>',
      TEncoding.ASCII.GetBytes('hello'));
    const Files = FDocuments.Open(Builder).GetEmbeddedFiles;

    Assert.AreEqual<Integer>(1, Length(Files));
    const Attachment = Files[0];
    Assert.AreEqual(#$00E4 + '.txt', Attachment.FileName);
    Assert.AreEqual('key.txt', Attachment.Key);
    Assert.AreEqual('A description', Attachment.Description);
    var Subtype: string;
    Assert.IsTrue(Attachment.TryGetSubtype(Subtype));
    Assert.AreEqual('text/plain', Subtype);
    var Size: Integer;
    Assert.IsTrue(Attachment.TryGetSize(Size));
    Assert.AreEqual(5, Size);
    Assert.AreEqual('hello', TEncoding.ASCII.GetString(Attachment.GetData));

    var Value: TDateTime;
    var Offset: Integer;
    Assert.IsTrue(Attachment.TryGetCreationDate(Value, Offset));
    Assert.AreEqual(EncodeDateTime(2024, 1, 2, 3, 4, 5, 0), Value);
    Assert.AreEqual(0, Offset);
    Assert.IsTrue(Attachment.TryGetModDate(Value, Offset));
    Assert.AreEqual(EncodeDateTime(2024, 1, 2, 3, 4, 6, 0), Value);
    Assert.AreEqual(60, Offset);
  finally
    Builder.Free;
  end;
end;

procedure TEmbeddedFileTests.TestFilenameFallsBackThroughTheEntriesAndThenTheKey;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, CatalogExtra);
  try
    Builder.AddObject(3, '<< /Names [(k1) 4 0 R (k2) 5 0 R (k3) 6 0 R (k4) 7 0 R (k5) 8 0 R (k6) 9 0 R] >>');
    Builder.AddObject(4, '<< /F (f) /Unix (unix) /Mac (mac) /DOS (dos) >>');
    Builder.AddObject(5, '<< /F (f) /Unix (unix) /Mac (mac) >>');
    Builder.AddObject(6, '<< /F (f) /Unix (unix) >>');
    Builder.AddObject(7, '<< /F (f) >>');
    Builder.AddObject(8, '<< /F /NotAString >>');
    Builder.AddObject(9, '<< /UF (uf) /DOS (dos) >>');
    const Files = FDocuments.Open(Builder).GetEmbeddedFiles;

    Assert.AreEqual<Integer>(6, Length(Files));
    Assert.AreEqual('dos', Files[0].FileName);
    Assert.AreEqual('mac', Files[1].FileName);
    Assert.AreEqual('unix', Files[2].FileName);
    Assert.AreEqual('f', Files[3].FileName);
    Assert.AreEqual('k5', Files[4].FileName);
    Assert.AreEqual('uf', Files[5].FileName);
    var FileName: string;
    Assert.IsFalse(Files[4].TryGetFilename(FileName));
    Assert.AreEqual('', Files[4].Description);
  finally
    Builder.Free;
  end;
end;

procedure TEmbeddedFileTests.TestDataIsDecodedThroughTheFilters;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, CatalogExtra);
  try
    Builder.AddObject(3, '<< /Names [(k) 4 0 R] >>');
    Builder.AddObject(4, '<< /F (a.bin) /EF << /F 5 0 R >> >>');
    Builder.AddStreamObject(5, '/Filter /ASCIIHexDecode', TEncoding.ASCII.GetBytes('68656C6C6F00ff>'));
    const Data = FDocuments.Open(Builder).GetEmbeddedFiles[0].GetData;
    Assert.AreEqual<Integer>(7, Length(Data));
    Assert.AreEqual('hello', TEncoding.ASCII.GetString(Data, 0, 5));
    Assert.AreEqual(Byte(0), Data[5]);
    Assert.AreEqual(Byte($FF), Data[6]);
  finally
    Builder.Free;
  end;
end;

procedure TEmbeddedFileTests.TestSizeComesOnlyFromTheParams;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, CatalogExtra);
  try
    Builder.AddObject(3, '<< /Names [(a) 4 0 R (b) 5 0 R (c) 6 0 R (d) 7 0 R] >>');
    Builder.AddObject(4, '<< /EF << /F 8 0 R >> >>');
    Builder.AddObject(5, '<< /EF << /F 9 0 R >> >>');
    Builder.AddObject(6, '<< /EF << /F 10 0 R >> >>');
    Builder.AddObject(7, '<< /EF << /F 11 0 R >> >>');
    // No /Params, a negative size, a size of zero and a size that is no number
    Builder.AddStreamObject(8, '/Type /EmbeddedFile', TEncoding.ASCII.GetBytes('1234'));
    Builder.AddStreamObject(9, '/Params << /Size -1 >>', TEncoding.ASCII.GetBytes('1234'));
    Builder.AddStreamObject(10, '/Params << /Size 0 >>', TEncoding.ASCII.GetBytes('1234'));
    Builder.AddStreamObject(11, '/Params << /Size (7) >>', TEncoding.ASCII.GetBytes('1234'));
    const Files = FDocuments.Open(Builder).GetEmbeddedFiles;

    var Size: Integer;
    Assert.IsFalse(Files[0].TryGetSize(Size));
    Assert.IsFalse(Files[1].TryGetSize(Size));
    Assert.IsTrue(Files[2].TryGetSize(Size));
    Assert.AreEqual(0, Size);
    Assert.IsFalse(Files[3].TryGetSize(Size));
    var Value: TDateTime;
    var Offset: Integer;
    Assert.IsFalse(Files[2].TryGetCreationDate(Value, Offset));
    var Subtype: string;
    Assert.IsFalse(Files[2].TryGetSubtype(Subtype));
  finally
    Builder.Free;
  end;
end;

procedure TEmbeddedFileTests.TestEntryWithoutStreamHasNoDataAndNoSize;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, CatalogExtra);
  try
    Builder.AddObject(3, '<< /Names [(k) 4 0 R] >>');
    Builder.AddObject(4, '<< /F (a.txt) >>');
    const Files = FDocuments.Open(Builder).GetEmbeddedFiles;

    Assert.AreEqual<Integer>(1, Length(Files));
    Assert.IsFalse(Files[0].HasEmbeddedStream);
    var Size: Integer;
    Assert.IsFalse(Files[0].TryGetSize(Size));
    Assert.WillRaiseDescendant(
      procedure
      begin
        Files[0].GetData;
      end, EPdfParseException);
  finally
    Builder.Free;
  end;
end;

procedure TEmbeddedFileTests.TestOnlyTheStreamF;
begin
  // As in PDFBox the stream of /UF is not what getEmbeddedFile gives
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, CatalogExtra);
  try
    Builder.AddObject(3, '<< /Names [(k) 4 0 R] >>');
    Builder.AddObject(4, '<< /UF (a.txt) /EF << /UF 5 0 R >> >>');
    Builder.AddStreamObject(5, '/Params << /Size 4 >>', TEncoding.ASCII.GetBytes('1234'));
    Assert.IsFalse(FDocuments.Open(Builder).GetEmbeddedFiles[0].HasEmbeddedStream);
  finally
    Builder.Free;
  end;
end;

procedure TEmbeddedFileTests.TestDataBeyondTheLimitRaises;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, CatalogExtra);
  try
    Builder.AddObject(3, '<< /Names [(k) 4 0 R] >>');
    Builder.AddObject(4, '<< /EF << /F 5 0 R >> >>');
    Builder.AddStreamObject(5, '/Filter /ASCIIHexDecode', TEncoding.ASCII.GetBytes('68656C6C6F>'));
    FDocuments.MaxDecodedStreamSize := 3;
    const Files = FDocuments.Open(Builder).GetEmbeddedFiles;
    Assert.WillRaiseDescendant(
      procedure
      begin
        Files[0].GetData;
      end, EPdfLimitExceededException);
  finally
    Builder.Free;
  end;
end;

procedure TEmbeddedFileTests.TestTreeWithKidsGivesTheEntriesInOrder;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, CatalogExtra);
  try
    Builder.AddObject(3, '<< /Kids [4 0 R 5 0 R] >>');
    Builder.AddObject(4, '<< /Names [(z) 6 0 R (y) 6 0 R] >>');
    Builder.AddObject(5, '<< /Names [(a) 7 0 R] >>');
    Builder.AddObject(6, '<< /F (six) >>');
    Builder.AddObject(7, '<< /F (seven) >>');
    const Files = FDocuments.Open(Builder).GetEmbeddedFiles;
    Assert.AreEqual<Integer>(3, Length(Files));
    Assert.AreEqual('z', Files[0].Key);
    Assert.AreEqual('y', Files[1].Key);
    Assert.AreEqual('a', Files[2].Key);
    Assert.AreEqual('seven', Files[2].FileName);
  finally
    Builder.Free;
  end;
end;

procedure TEmbeddedFileTests.TestValueThatIsNoDictionaryRaisesAndNullIsAnEmptySpecification;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, CatalogExtra);
  try
    Builder.AddObject(3, '<< /Names [(nothing) null] >>');
    const Document = FDocuments.Open(Builder);
    const Files = Document.GetEmbeddedFiles;
    Assert.AreEqual<Integer>(1, Length(Files));
    Assert.AreEqual('nothing', Files[0].FileName);
    Assert.IsFalse(Files[0].HasEmbeddedStream);

    Builder.AddObject(3, '<< /Names [(bad) 5] >>');
    const Other = FDocuments.Open(Builder);
    Assert.WillRaiseDescendant(
      procedure
      begin
        Other.GetEmbeddedFiles;
      end, EPdfParseException);
  finally
    Builder.Free;
  end;
end;

procedure TEmbeddedFileTests.TestNoEmbeddedFilesGivesNoEntries;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, '');
  try
    Assert.AreEqual<Integer>(0, Length(FDocuments.Open(Builder).GetEmbeddedFiles));
  finally
    Builder.Free;
  end;
end;

procedure TEmbeddedFileTests.TestTheDocumentOwnsTheEntries;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, CatalogExtra);
  try
    Builder.AddObject(3, '<< /Names [(k) 4 0 R] >>');
    Builder.AddObject(4, '<< /F (a) >>');
    const Document = FDocuments.Open(Builder);
    Assert.AreSame(Document.GetEmbeddedFiles[0], Document.GetEmbeddedFiles[0]);
  finally
    Builder.Free;
  end;
end;

end.
