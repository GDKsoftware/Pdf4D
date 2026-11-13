unit Pdf4D.Api.Document.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Tests.PdfBuilder;

type
  [TestFixture]
  TApiDocumentTests = class
  private
    FFileNames: TList<string>;
    FStreams: TObjectList<TStream>;
    FLogLines: TList<string>;

    function PdfBytes(const Builder: TTestPdfBuilder): TBytes;
    function WriteTempFile(const Data: TBytes): string;
    function LoadFromMemory(const Builder: TTestPdfBuilder): IPdfDocument;
    procedure LoadFile(const FileName: string);
    {$IFNDEF MSWINDOWS}
    class function DescriptorPointsTo(const Descriptor: Integer; const FileName: string): Boolean; static;
    {$ENDIF}
    class function IsHeldOpen(const FileName: string): Boolean; static;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestLoadFromFileAndReadBasics;

    [Test]
    procedure TestPageOutlivesDocumentReference;

    [Test]
    procedure TestDocumentOutlivesPageReference;

    [Test]
    procedure TestFileIsReleasedAfterLastReference;

    [Test]
    procedure TestPageIndexOutOfRange;

    [Test]
    procedure TestUsageExampleCompiles;

    [Test]
    procedure TestOutlineChildrenOutliveDocument;

    [Test]
    procedure TestFieldsGiveValuesAndAFailingFieldGivesEmptyValues;

    [Test]
    procedure TestAttachmentGivesDataAndSize;

    [Test]
    procedure TestPageLabels;

    [Test]
    procedure TestNoPageLabelsGiveEmptyLabels;

    [Test]
    procedure TestInfoAndXmpMetadata;

    [Test]
    procedure TestMissingFileRaisesAPdfException;

    [Test]
    procedure TestNotAPdfRaisesAParseException;

    [Test]
    procedure TestFailedLoadReleasesTheFile;
  end;

implementation

uses
  {$IFDEF LINUX}
  Posix.Unistd,
  {$ENDIF}
  System.IOUtils,
  Pdf4D.Api.Attachment.Interfaces,
  Pdf4D.Api.Field.Interfaces,
  Pdf4D.Api.Outline.Interfaces,
  Pdf4D.Api.Page.Interfaces,
  Pdf4D.Api.Document,
  Pdf4D.Common.Defines,
  Pdf4D.Model.Field,
  Pdf4D.Model.Tests.Support;

const
  MaxDescriptorsChecked = 255;

{ TApiDocumentTests }

procedure TApiDocumentTests.Setup;
begin
  FFileNames := TList<string>.Create;
  FStreams := TObjectList<TStream>.Create(True);
  FLogLines := TList<string>.Create;
end;

procedure TApiDocumentTests.TearDown;
begin
  FStreams.Free;
  for var FileName in FFileNames do
  begin
    if TFile.Exists(FileName) then
    begin
      TFile.Delete(FileName);
    end;
  end;
  FFileNames.Free;
  FLogLines.Free;
end;

function TApiDocumentTests.PdfBytes(const Builder: TTestPdfBuilder): TBytes;
begin
  Result := Builder.Build(TXrefStyle.Table);
end;

function TApiDocumentTests.WriteTempFile(const Data: TBytes): string;
begin
  Result := TPath.GetTempFileName;
  FFileNames.Add(Result);
  TFile.WriteAllBytes(Result, Data);
end;

function TApiDocumentTests.LoadFromMemory(const Builder: TTestPdfBuilder): IPdfDocument;
begin
  var Options := TPdfLoadOptions.Default;
  Options.OnLog :=
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      FLogLines.Add(Message);
    end;

  const Stream = TBytesStream.Create(PdfBytes(Builder));
  FStreams.Add(Stream);
  Result := TPdfDocument.Load(Stream, Options);
end;

procedure TApiDocumentTests.LoadFile(const FileName: string);
begin
  const Document = TPdfDocument.Load(FileName);
  Assert.IsNotNull(Document);
end;

{$IFNDEF MSWINDOWS}
class function TApiDocumentTests.DescriptorPointsTo(const Descriptor: Integer; const FileName: string): Boolean;
begin
  var Buffer: array[0..4095] of UTF8Char;
  const LinkPath = UTF8String(Format('/proc/self/fd/%d', [Descriptor]));
  const Count = readlink(MarshaledAString(LinkPath), @Buffer[0], SizeOf(Buffer) - 1);
  Result := (Count > 0);
  if Result then
  begin
    Buffer[Count] := #0;
    Result := (UTF8ToString(MarshaledAString(@Buffer[0])) = FileName);
  end;
end;
{$ENDIF}

// On Windows a file that a stream has open for reading refuses a second writer. On Linux deleting an open file succeeds,
// so the descriptors of the process tell whether it is still open.
class function TApiDocumentTests.IsHeldOpen(const FileName: string): Boolean;
begin
  {$IFDEF MSWINDOWS}
  try
    TFileStream.Create(FileName, fmOpenReadWrite or fmShareDenyNone).Free;
    Result := False;
  except
    on Failure: EStreamError do
    begin
      Result := True;
    end;
  end;
  {$ELSE}
  Result := False;
  for var Descriptor := 0 to MaxDescriptorsChecked do
  begin
    Result := (Result or DescriptorPointsTo(Descriptor, FileName));
  end;
  {$ENDIF}
end;

procedure TApiDocumentTests.TestLoadFromFileAndReadBasics;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(2, '');
  try
    Builder.AddObject(3, '<< /Title (T) >>');
    Builder.TrailerExtra := '/Info 3 0 R';
    const FileName = WriteTempFile(PdfBytes(Builder));

    const Document = TPdfDocument.Load(FileName);

    Assert.AreEqual(2, Document.PageCount);
    Assert.AreEqual('T', Document.Info.Title);
    Assert.AreEqual<Integer>(2, Length(Document.Pages));
    Assert.IsFalse(Document.IsEncrypted);
    Assert.IsNotNull(Document.Permissions);
    Assert.IsNotNull(Document.CosDocument);
  finally
    Builder.Free;
  end;
end;

procedure TApiDocumentTests.TestPageOutlivesDocumentReference;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(2, '');
  try
    var Document := LoadFromMemory(Builder);
    var Page := Document.Page(0);

    Document := nil;

    Assert.AreEqual<Single>(612, Page.MediaBox.Width);
    Assert.AreEqual(0, Page.Index);
    Assert.AreEqual(0, Page.Rotation);
    Assert.IsNotNull(Page.CosObject);
  finally
    Builder.Free;
  end;
end;

procedure TApiDocumentTests.TestDocumentOutlivesPageReference;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(2, '');
  try
    var Document := LoadFromMemory(Builder);
    var Page := Document.Page(1);

    Page := nil;

    Assert.AreEqual(2, Document.PageCount);
    Assert.AreEqual(1, Document.Page(1).Index);
  finally
    Builder.Free;
  end;
end;

procedure TApiDocumentTests.TestFileIsReleasedAfterLastReference;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, '');
  try
    const FileName = WriteTempFile(PdfBytes(Builder));
    var Document := TPdfDocument.Load(FileName);
    var Page := Document.Page(0);

    Document := nil;
    Assert.IsTrue(IsHeldOpen(FileName), 'The page still keeps the file open');

    Page := nil;
    Assert.IsFalse(IsHeldOpen(FileName), 'The last reference is gone, so the file is closed');
    TFile.Delete(FileName);
    Assert.IsFalse(TFile.Exists(FileName));
  finally
    Builder.Free;
  end;
end;

procedure TApiDocumentTests.TestPageIndexOutOfRange;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(2, '');
  try
    const Document = LoadFromMemory(Builder);

    Assert.WillRaise(
      procedure
      begin
        Document.Page(2);
      end,
      EArgumentOutOfRangeException);
    Assert.WillRaise(
      procedure
      begin
        Document.Page(-1);
      end,
      EArgumentOutOfRangeException);
  finally
    Builder.Free;
  end;
end;

procedure TApiDocumentTests.TestUsageExampleCompiles;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(3, '');
  try
    const Document = LoadFromMemory(Builder);

    var Lines := '';
    for var Page in Document.Pages do
    begin
      Lines := Lines + Format('%d: %.0f;', [Page.Index, Page.MediaBox.Width]);
    end;

    Assert.AreEqual('0: 612;1: 612;2: 612;', Lines);
  finally
    Builder.Free;
  end;
end;

procedure TApiDocumentTests.TestOutlineChildrenOutliveDocument;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(2, '/Outlines 3 0 R');
  try
    Builder.AddObject(3, '<< /Type /Outlines /First 4 0 R /Last 4 0 R /Count 2 >>');
    Builder.AddObject(4, '<< /Title (Chapter) /Parent 3 0 R /First 5 0 R /Last 5 0 R /Dest [11 0 R /Fit] >>');
    Builder.AddObject(5, '<< /Title (Section) /Parent 4 0 R /Dest [10 0 R /Fit] >>');
    var Document := LoadFromMemory(Builder);
    var Items := Document.Outline;
    var Children := Items[0].Children;

    Document := nil;
    Items := nil;

    Assert.AreEqual<Integer>(1, Length(Children));
    Assert.AreEqual('Section', Children[0].Title);
    var PageIndex: Integer;
    Assert.IsTrue(Children[0].TryGetPageIndex(PageIndex));
    Assert.AreEqual(0, PageIndex);
  finally
    Builder.Free;
  end;
end;

procedure TApiDocumentTests.TestFieldsGiveValuesAndAFailingFieldGivesEmptyValues;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, '/AcroForm 3 0 R');
  try
    Builder.AddObject(3, '<< /Fields [4 0 R 5 0 R 7 0 R] >>');
    Builder.AddObject(4, '<< /T (good) /FT /Tx /V (hello) >>');
    Builder.AddObject(5, '<< /T (bad) /FT /Ch /V [6 0 R] >>');
    Builder.AddObject(6, '(indirect)');
    Builder.AddObject(7, '<< /T (multi) /FT /Ch /V [(a) (b)] >>');
    const Document = LoadFromMemory(Builder);

    const Fields = Document.Fields;

    Assert.AreEqual<Integer>(3, Length(Fields));
    Assert.AreEqual('good', Fields[0].Name);
    Assert.AreEqual('good', Fields[0].FullyQualifiedName);
    Assert.AreEqual(TPdfFieldKind.Text, Fields[0].Kind);
    Assert.AreEqual('hello', Fields[0].Value);
    Assert.AreEqual('', Fields[1].Value);
    Assert.AreEqual<Integer>(0, Length(Fields[1].Values));
    Assert.AreEqual<Integer>(2, Length(Fields[2].Values));
    Assert.AreEqual('b', Fields[2].Values[1]);
    Assert.IsTrue(FLogLines.Count > 0, 'The broken field is logged');
  finally
    Builder.Free;
  end;
end;

procedure TApiDocumentTests.TestAttachmentGivesDataAndSize;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, '/Names << /EmbeddedFiles 3 0 R >>');
  try
    Builder.AddObject(3, '<< /Names [(key.txt) 4 0 R] >>');
    Builder.AddObject(4, '<< /Type /Filespec /F (a.txt) /Desc (A description) /EF << /F 5 0 R >> >>');
    Builder.AddStreamObject(5, '/Type /EmbeddedFile /Params << /Size 5 >>', TEncoding.ASCII.GetBytes('hello'));
    var Document := LoadFromMemory(Builder);
    var Attachments := Document.Attachments;

    Document := nil;

    Assert.AreEqual<Integer>(1, Length(Attachments));
    Assert.AreEqual('a.txt', Attachments[0].FileName);
    Assert.AreEqual('A description', Attachments[0].Description);
    var Size: Int64;
    Assert.IsTrue(Attachments[0].TryGetSize(Size));
    Assert.AreEqual<Int64>(5, Size);
    Assert.AreEqual('hello', TEncoding.ASCII.GetString(Attachments[0].Data));
  finally
    Builder.Free;
  end;
end;

procedure TApiDocumentTests.TestPageLabels;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(3, '/PageLabels << /Nums [0 << /S /r >> 2 << /S /D /P (A-) >>] >>');
  try
    const Document = LoadFromMemory(Builder);

    const Pages = Document.Pages;

    Assert.AreEqual('i', Pages[0].Label_);
    Assert.AreEqual('ii', Pages[1].Label_);
    Assert.AreEqual('A-1', Pages[2].Label_);
  finally
    Builder.Free;
  end;
end;

procedure TApiDocumentTests.TestNoPageLabelsGiveEmptyLabels;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, '');
  try
    const Document = LoadFromMemory(Builder);

    Assert.AreEqual('', Document.Page(0).Label_);
  finally
    Builder.Free;
  end;
end;

procedure TApiDocumentTests.TestInfoAndXmpMetadata;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(1, '/Metadata 4 0 R');
  try
    Builder.AddObject(3, '<< /Title (T) /Author (A) /CreationDate (D:20240102030405Z) /Custom (c) >>');
    Builder.AddStreamObject(4, '/Type /Metadata /Subtype /XML', TEncoding.ASCII.GetBytes('<x/>'));
    Builder.TrailerExtra := '/Info 3 0 R';
    const Document = LoadFromMemory(Builder);

    const Info = Document.Info;

    Assert.AreEqual('A', Info.Author);
    Assert.AreEqual('', Info.Subject);
    Assert.AreEqual<Integer>(4, Length(Info.Keys));
    Assert.AreEqual('Title', Info.Keys[0]);
    var Value: string;
    Assert.IsTrue(Info.TryGetValue('Custom', Value));
    Assert.AreEqual('c', Value);
    var Created: TDateTime;
    Assert.IsTrue(Info.TryGetCreationDate(Created));
    Assert.AreEqual<TDateTime>(EncodeDate(2024, 1, 2) + EncodeTime(3, 4, 5, 0), Created);
    Assert.IsFalse(Info.TryGetModificationDate(Created));
    Assert.AreEqual('<x/>', TEncoding.ASCII.GetString(Document.XmpMetadata));
  finally
    Builder.Free;
  end;
end;

procedure TApiDocumentTests.TestMissingFileRaisesAPdfException;
begin
  const FileName = TPath.Combine(TPath.GetTempPath, 'pdf4d-does-not-exist.pdf');

  Assert.WillRaise(
    procedure
    begin
      LoadFile(FileName);
    end,
    EPdfFileException);
end;

procedure TApiDocumentTests.TestNotAPdfRaisesAParseException;
begin
  const FileName = WriteTempFile(TEncoding.ASCII.GetBytes('this is not a pdf file at all'));

  Assert.WillRaise(
    procedure
    begin
      LoadFile(FileName);
    end,
    EPdfParseException);
end;

procedure TApiDocumentTests.TestFailedLoadReleasesTheFile;
begin
  const FileName = WriteTempFile(TEncoding.ASCII.GetBytes('this is not a pdf file at all'));

  Assert.WillRaise(
    procedure
    begin
      LoadFile(FileName);
    end,
    EPdfParseException);

  Assert.IsFalse(IsHeldOpen(FileName), 'A failed load must close the file');
end;

end.
