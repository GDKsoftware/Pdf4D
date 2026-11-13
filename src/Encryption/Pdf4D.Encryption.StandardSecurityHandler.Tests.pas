// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Encryption.StandardSecurityHandler.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  DUnitX.TestFramework,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Document;

type
  [TestFixture]
  TStandardSecurityHandlerTests = class
  private
    // The folder with the test corpus. PDF4D_CORPUS names it; without that the folders above the test program are searched,
    // which works from the build output on Windows and under WSL (the binary runs from the Windows file system there).
    class function CorpusFolder: string; static;
    class function CorpusFile(const RelativeName: string): string; static;

    function LoadCorpus(const RelativeName, Password: string): TCosDocument;
    function LoadBytes(const Data: TBytes): TCosDocument;
    function Producer(const Document: TCosDocument): string;
    function FirstContentStream(const Document: TCosDocument): TCosStream;
    function DecodedText(const Stream: TCosStream): string;
    function RawText(const Stream: TCosStream): string;
    function MetadataStream(const Document: TCosDocument): TCosStream;
    procedure AssertAllStreamsDecode(const Document: TCosDocument);
    function BuildWithEncryptDictionary(const Dictionary: string): TBytes;
    procedure AssertLoadRaises(const Dictionary: string; const ExceptionClass: ExceptClass);

  public
    [Test]
    [TestCase('rc4-40', 'rc4-40')]
    [TestCase('rc4-128', 'rc4-128')]
    [TestCase('aes-128', 'aes-128')]
    [TestCase('aes-256', 'aes-256')]
    procedure TestOpensEmptyUserPassword(const Variant: string);

    [Test]
    [TestCase('rc4-40', 'rc4-40')]
    [TestCase('rc4-128', 'rc4-128')]
    [TestCase('aes-128', 'aes-128')]
    [TestCase('aes-256', 'aes-256')]
    procedure TestOpensWithUserPassword(const Variant: string);

    [Test]
    [TestCase('rc4-40', 'rc4-40')]
    [TestCase('rc4-128', 'rc4-128')]
    [TestCase('aes-128', 'aes-128')]
    [TestCase('aes-256', 'aes-256')]
    procedure TestOpensWithOwnerPassword(const Variant: string);

    [Test]
    [TestCase('rc4-40', 'rc4-40')]
    [TestCase('rc4-128', 'rc4-128')]
    [TestCase('aes-128', 'aes-128')]
    [TestCase('aes-256', 'aes-256')]
    procedure TestWrongPasswordRaises(const Variant: string);

    [Test]
    [TestCase('rc4-40', 'rc4-40')]
    [TestCase('rc4-128', 'rc4-128')]
    [TestCase('aes-128', 'aes-128')]
    [TestCase('aes-256', 'aes-256')]
    procedure TestEmptyPasswordOnPasswordProtectedFileRaises(const Variant: string);

    [Test]
    procedure TestR5Document;

    [Test]
    [TestCase('40 bit', 'PasswordSample-40bit.pdf')]
    [TestCase('128 bit', 'PasswordSample-128bit.pdf')]
    [TestCase('256 bit', 'PasswordSample-256bit.pdf')]
    procedure TestPdfBoxPasswordSamples(const FileName: string);

    [Test]
    procedure TestPublicKeyRaisesUnsupported;

    [Test]
    procedure TestUnknownFilterRaisesUnsupported;

    [Test]
    procedure TestRawEncryptedBytesStayAvailable;

    [Test]
    procedure TestMetadataNotEncryptedWhenFlagFalse;

    [Test]
    procedure TestMetadataIsDecryptedWhenFlagTrue;

    [Test]
    procedure TestUnencryptedDocumentHasFullPermissions;

    [Test]
    procedure TestEncryptionDictionaryIsAvailable;

    [Test]
    procedure TestMissingOwnerEntryRaises;

    [Test]
    procedure TestMissingUserEntryRaises;

    [Test]
    procedure TestNonStringOwnerEntryRaises;

    [Test]
    procedure TestWrongLengthEntriesGiveWrongPassword;

    [Test]
    procedure TestUnknownRevisionRaises;

    [Test]
    [TestCase('zero', '0')]
    [TestCase('too long', '2048')]
    procedure TestInvalidKeyLengthRaises(const LengthInBits: string);

    [Test]
    procedure TestBrokenRevision6EntriesRaise;
  end;

  [TestFixture]
  TAccessPermissionTests = class
  public
    [Test]
    procedure TestDefaultHasAllPermissions;

    [Test]
    [TestCase('print', '-3900,True,False,False')]
    [TestCase('nothing', '-4,True,True,True')]
    [TestCase('only print', '4,True,False,False')]
    [TestCase('only faithful', '2048,False,False,True')]
    procedure TestBitsOfP(const P: Integer; const CanPrint, CanModify, CanPrintFaithful: Boolean);

    [Test]
    procedure TestOwnerPermissionNeedsAllBits;

    [Test]
    procedure TestReadOnlyIgnoresSetters;

    [Test]
    procedure TestFromBytes;
  end;

  [TestFixture]
  TSaslPrepTests = class
  public
    [Test]
    procedure TestAsciiStaysTheSame;

    [Test]
    procedure TestNonAsciiSpaceBecomesSpace;

    [Test]
    procedure TestSoftHyphenIsRemoved;

    [Test]
    procedure TestControlCharacterRaises;

    [Test]
    procedure TestCompatibilityCharactersAreNormalized;

    [Test]
    procedure TestRandALCatAndLCatTogetherRaises;

    [Test]
    procedure TestCombiningMarkIsComposed;

    [Test]
    procedure TestFullwidthLettersBecomeAscii;

    [Test]
    procedure TestHangulSyllableSurvivesDecompositionAndComposition;

    [Test]
    procedure TestCombiningMarksAreOrdered;

    [Test]
    procedure TestCompositionExclusionStaysDecomposed;

    [Test]
    procedure TestSingletonDecompositionIsNotComposedBack;

    [Test]
    procedure TestSuperscriptAndFractionAreMapped;
  end;

implementation

uses
  System.IOUtils,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Cos.PdfString,
  Pdf4D.Encryption.AccessPermission,
  Pdf4D.Encryption.SaslPrep,
  Pdf4D.Parser.Pdf,
  Pdf4D.Tests.PdfBuilder;

const
  CorpusEnvironmentVariable = 'PDF4D_CORPUS';
  EncryptedFolder = 'generated/encrypted/';
  PdfBoxEncryptionFolder = 'pdfbox/org/apache/pdfbox/encryption/';
  R5SampleName = 'generated/encrypted/r5-sample.pdf';
  R5SamplePassword = 'JUL2023rfi';
  UserPassword = 'user';
  OwnerPassword = 'owner';
  MaxFolderLevels = 12;
  XpacketStart = '<?xpacket';

{ TStandardSecurityHandlerTests }

class function TStandardSecurityHandlerTests.CorpusFolder: string;
begin
  const FromEnvironment = GetEnvironmentVariable(CorpusEnvironmentVariable);
  if FromEnvironment <> '' then
  begin
    Exit(FromEnvironment);
  end;

  var Folder := TPath.GetDirectoryName(ParamStr(0));
  for var Level := 1 to MaxFolderLevels do
  begin
    const Candidate = TPath.Combine(TPath.Combine(Folder, 'corpus'), 'manifest.csv');
    if TFile.Exists(Candidate) then
    begin
      Exit(TPath.Combine(Folder, 'corpus'));
    end;
    Folder := TPath.GetDirectoryName(Folder);
  end;
  Result := '';
end;

class function TStandardSecurityHandlerTests.CorpusFile(const RelativeName: string): string;
begin
  const Folder = CorpusFolder;
  if Folder = '' then
  begin
    Exit('');
  end;
  Result := TPath.Combine(Folder, RelativeName.Replace('/', PathDelim));
end;

function TStandardSecurityHandlerTests.LoadCorpus(const RelativeName, Password: string): TCosDocument;
begin
  const FileName = CorpusFile(RelativeName);
  Assert.IsTrue(TFile.Exists(FileName), Format('Corpus file %s was not found, set %s', [RelativeName, CorpusEnvironmentVariable]));

  var Options := TPdfLoadOptions.Default;
  Options.Password := Password;
  Result := TPdfParser.Parse(TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone), True, Options);
end;

function TStandardSecurityHandlerTests.LoadBytes(const Data: TBytes): TCosDocument;
begin
  Result := TPdfParser.Parse(TBytesStream.Create(Data), True, TPdfLoadOptions.Default);
end;

function TStandardSecurityHandlerTests.Producer(const Document: TCosDocument): string;
begin
  var Info: TCosDictionary;
  Assert.IsTrue(Document.Trailer.TryGetCosDictionary(TCosNames.Info, Info), 'The trailer has no /Info');
  Result := Info.GetString(TCosNames.Producer, '<missing>');
end;

function TStandardSecurityHandlerTests.FirstContentStream(const Document: TCosDocument): TCosStream;
begin
  var Root: TCosDictionary;
  var Pages: TCosDictionary;
  Assert.IsTrue(Document.Trailer.TryGetCosDictionary(TCosNames.Root, Root), 'No /Root');
  Assert.IsTrue(Root.TryGetCosDictionary(TCosNames.Pages, Pages), 'No /Pages');

  // The first page is the first leaf of the page tree
  var Page := Pages;
  var Kids: TCosArray;
  while Page.TryGetCosArray(TCosNames.Kids, Kids) and (Kids.Count > 0) do
  begin
    const Kid = Kids.GetObject(0);
    Assert.IsTrue(Kid is TCosDictionary, 'A kid is not a dictionary');
    Page := TCosDictionary(Kid);
  end;

  var Contents: TCosBase;
  Assert.IsTrue(Page.TryGetDictionaryObject(TCosNames.Contents, Contents), 'No /Contents');
  if Contents is TCosArray then
  begin
    Contents := TCosArray(Contents).GetObject(0);
  end;
  Assert.IsTrue(Contents is TCosStream, 'The contents are not a stream');
  Result := TCosStream(Contents);
end;

function TStandardSecurityHandlerTests.DecodedText(const Stream: TCosStream): string;
begin
  const Data = Stream.CreateDecodedStream;
  try
    var Bytes: TBytes;
    SetLength(Bytes, Data.Size);
    Data.Position := 0;
    Data.ReadBuffer(Bytes, Length(Bytes));
    Result := TEncoding.ANSI.GetString(Bytes);
  finally
    Data.Free;
  end;
end;

function TStandardSecurityHandlerTests.RawText(const Stream: TCosStream): string;
begin
  const Data = Stream.CreateRawStream;
  try
    var Bytes: TBytes;
    SetLength(Bytes, Data.Size);
    Data.Position := 0;
    Data.ReadBuffer(Bytes, Length(Bytes));
    Result := TEncoding.ANSI.GetString(Bytes);
  finally
    Data.Free;
  end;
end;

function TStandardSecurityHandlerTests.MetadataStream(const Document: TCosDocument): TCosStream;
begin
  var Root: TCosDictionary;
  Assert.IsTrue(Document.Trailer.TryGetCosDictionary(TCosNames.Root, Root), 'No /Root');
  Assert.IsTrue(Root.TryGetCosStream(TCosNames.Metadata, Result), 'The catalog has no /Metadata stream');
end;

// Every stream decodes: with a wrong key the Flate data would be damaged
procedure TStandardSecurityHandlerTests.AssertAllStreamsDecode(const Document: TCosDocument);
begin
  var StreamCount := 0;
  for var Key in Document.ObjectKeys do
  begin
    const Loaded = Document.GetObjectFromPool(Key).GetObject;
    if Loaded is TCosStream then
    begin
      Inc(StreamCount);
      // Up to the first image filter: the images are not decoded
      const Decoded = TCosStream(Loaded).DecodeUntilImageFilter;
      Assert.IsTrue(Length(Decoded.Data) > 0, Format('Stream %s has no data', [Key.ToString]));
    end;
  end;
  Assert.IsTrue(StreamCount > 0, 'The file has no streams');
end;

procedure TStandardSecurityHandlerTests.TestOpensEmptyUserPassword(const Variant: string);
begin
  const Base = LoadCorpus(EncryptedFolder + 'base.pdf', '');
  try
    const Encrypted = LoadCorpus(EncryptedFolder + Variant + '-empty.pdf', '');
    try
      Assert.AreEqual(Producer(Base), Producer(Encrypted));
      Assert.AreEqual(DecodedText(FirstContentStream(Base)), DecodedText(FirstContentStream(Encrypted)));
      Assert.IsNotNull(Encrypted.Encryption);
    finally
      Encrypted.Free;
    end;
  finally
    Base.Free;
  end;
end;

procedure TStandardSecurityHandlerTests.TestOpensWithUserPassword(const Variant: string);
begin
  const Base = LoadCorpus(EncryptedFolder + 'base.pdf', '');
  try
    const Encrypted = LoadCorpus(EncryptedFolder + Variant + '-user.pdf', UserPassword);
    try
      Assert.AreEqual(Producer(Base), Producer(Encrypted));
      Assert.AreEqual(DecodedText(FirstContentStream(Base)), DecodedText(FirstContentStream(Encrypted)));
      Assert.IsTrue(Encrypted.AccessPermission.IsReadOnly, 'The permissions of the user are read only');
    finally
      Encrypted.Free;
    end;
  finally
    Base.Free;
  end;
end;

procedure TStandardSecurityHandlerTests.TestOpensWithOwnerPassword(const Variant: string);
begin
  const Base = LoadCorpus(EncryptedFolder + 'base.pdf', '');
  try
    const Encrypted = LoadCorpus(EncryptedFolder + Variant + '-user.pdf', OwnerPassword);
    try
      Assert.IsTrue(Encrypted.AccessPermission.IsOwnerPermission);
      Assert.AreEqual(Producer(Base), Producer(Encrypted));
      Assert.AreEqual(DecodedText(FirstContentStream(Base)), DecodedText(FirstContentStream(Encrypted)));
    finally
      Encrypted.Free;
    end;
  finally
    Base.Free;
  end;
end;

procedure TStandardSecurityHandlerTests.TestWrongPasswordRaises(const Variant: string);
begin
  Assert.WillRaise(
    procedure
    begin
      LoadCorpus(EncryptedFolder + Variant + '-user.pdf', 'nope').Free;
    end,
    EPdfInvalidPasswordException);
end;

procedure TStandardSecurityHandlerTests.TestEmptyPasswordOnPasswordProtectedFileRaises(const Variant: string);
begin
  Assert.WillRaise(
    procedure
    begin
      LoadCorpus(EncryptedFolder + Variant + '-user.pdf', '').Free;
    end,
    EPdfInvalidPasswordException);
end;

procedure TStandardSecurityHandlerTests.TestR5Document;
begin
  if not TFile.Exists(CorpusFile(R5SampleName)) then
  begin
    Assert.Pass('The corpus has no R5 file');
  end;

  const Document = LoadCorpus(R5SampleName, R5SamplePassword);
  try
    Assert.AreEqual(5, Document.Encryption.GetRevision);
    Assert.IsNotNull(Document.Trailer.GetItem(TCosNames.Root));
    AssertAllStreamsDecode(Document);
  finally
    Document.Free;
  end;
end;

procedure TStandardSecurityHandlerTests.TestPdfBoxPasswordSamples(const FileName: string);
begin
  const Document = LoadCorpus(PdfBoxEncryptionFolder + FileName, UserPassword);
  try
    Assert.IsNotNull(Document.Encryption);

    AssertAllStreamsDecode(Document);
  finally
    Document.Free;
  end;
end;

function TStandardSecurityHandlerTests.BuildWithEncryptDictionary(const Dictionary: string): TBytes;
begin
  const Builder = TTestPdfBuilder.Create;
  try
    Builder.AddObject(1, '<< /Type /Catalog /Pages 2 0 R >>');
    Builder.AddObject(2, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
    Builder.AddObject(3, '<< /Type /Page /Parent 2 0 R >>');
    Builder.AddObject(5, Dictionary);
    Builder.SetRoot(1);
    Builder.TrailerExtra := '/Encrypt 5 0 R /ID [<00112233445566778899AABBCCDDEEFF> <00112233445566778899AABBCCDDEEFF>]';
    Result := Builder.Build(TXrefStyle.Table);
  finally
    Builder.Free;
  end;
end;

procedure TStandardSecurityHandlerTests.AssertLoadRaises(const Dictionary: string; const ExceptionClass: ExceptClass);
begin
  const Data = BuildWithEncryptDictionary(Dictionary);
  Assert.WillRaise(
    procedure
    begin
      LoadBytes(Data).Free;
    end,
    ExceptionClass);
end;

procedure TStandardSecurityHandlerTests.TestPublicKeyRaisesUnsupported;
begin
  AssertLoadRaises('<< /Filter /Adobe.PubSec /V 4 >>', EPdfUnsupportedFeatureException);
end;

procedure TStandardSecurityHandlerTests.TestUnknownFilterRaisesUnsupported;
begin
  AssertLoadRaises('<< /Filter /Other /V 4 >>', EPdfUnsupportedFeatureException);
end;

procedure TStandardSecurityHandlerTests.TestRawEncryptedBytesStayAvailable;
begin
  const Base = LoadCorpus(EncryptedFolder + 'base.pdf', '');
  try
    const Encrypted = LoadCorpus(EncryptedFolder + 'aes-128-empty.pdf', '');
    try
      const Stream = FirstContentStream(Encrypted);
      const FirstRead = RawText(Stream);
      const SecondRead = RawText(Stream);

      Assert.IsTrue(Length(FirstRead) > 0);
      Assert.AreEqual(FirstRead, SecondRead);
      Assert.AreEqual(RawText(FirstContentStream(Base)), FirstRead);
      Assert.AreEqual(DecodedText(FirstContentStream(Base)), DecodedText(Stream));
    finally
      Encrypted.Free;
    end;
  finally
    Base.Free;
  end;
end;

procedure TStandardSecurityHandlerTests.TestMetadataNotEncryptedWhenFlagFalse;
begin
  const Document = LoadCorpus(EncryptedFolder + 'aes-256-nometa.pdf', '');
  try
    Assert.IsFalse(Document.Encryption.IsEncryptMetaData);
    Assert.IsTrue(RawText(MetadataStream(Document)).StartsWith(XpacketStart), 'The XMP stream is not readable');
  finally
    Document.Free;
  end;
end;

procedure TStandardSecurityHandlerTests.TestMetadataIsDecryptedWhenFlagTrue;
begin
  const Document = LoadCorpus(EncryptedFolder + 'aes-256-empty.pdf', '');
  try
    Assert.IsTrue(Document.Encryption.IsEncryptMetaData);
    Assert.IsTrue(RawText(MetadataStream(Document)).StartsWith(XpacketStart), 'The XMP stream is not decrypted');
  finally
    Document.Free;
  end;
end;

procedure TStandardSecurityHandlerTests.TestUnencryptedDocumentHasFullPermissions;
begin
  const Document = LoadCorpus(EncryptedFolder + 'base.pdf', '');
  try
    Assert.IsNull(Document.Encryption);
    Assert.IsTrue(Document.AccessPermission.IsOwnerPermission);
  finally
    Document.Free;
  end;
end;

procedure TStandardSecurityHandlerTests.TestEncryptionDictionaryIsAvailable;
begin
  const Document = LoadCorpus(EncryptedFolder + 'aes-128-empty.pdf', '');
  try
    var Filter: string;
    Assert.IsTrue(Document.Encryption.TryGetFilter(Filter));
    Assert.AreEqual('Standard', Filter);
    Assert.AreEqual(4, Document.Encryption.GetVersion);
    Assert.AreEqual(4, Document.Encryption.GetRevision);
    Assert.AreEqual(128, Document.Encryption.GetLength);
  finally
    Document.Free;
  end;
end;

procedure TStandardSecurityHandlerTests.TestMissingOwnerEntryRaises;
begin
  AssertLoadRaises('<< /Filter /Standard /V 1 /R 2 /U (0123456789ABCDEF0123456789ABCDEF) /P -4 >>', EPdfParseException);
end;

procedure TStandardSecurityHandlerTests.TestMissingUserEntryRaises;
begin
  AssertLoadRaises('<< /Filter /Standard /V 1 /R 2 /O (0123456789ABCDEF0123456789ABCDEF) /P -4 >>', EPdfParseException);
end;

procedure TStandardSecurityHandlerTests.TestNonStringOwnerEntryRaises;
begin
  AssertLoadRaises('<< /Filter /Standard /V 1 /R 2 /O /Name /U (0123456789ABCDEF0123456789ABCDEF) /P -4 >>', EPdfParseException);
end;

procedure TStandardSecurityHandlerTests.TestWrongLengthEntriesGiveWrongPassword;
begin
  AssertLoadRaises('<< /Filter /Standard /V 2 /R 3 /Length 128 /O (x) /U (y) /P -4 >>', EPdfInvalidPasswordException);
end;

procedure TStandardSecurityHandlerTests.TestUnknownRevisionRaises;
begin
  AssertLoadRaises('<< /Filter /Standard /V 1 /R 9 /O (x) /U (y) /P -4 >>', EPdfParseException);
end;

procedure TStandardSecurityHandlerTests.TestInvalidKeyLengthRaises(const LengthInBits: string);
begin
  AssertLoadRaises(Format('<< /Filter /Standard /V 2 /R 3 /Length %s /O (x) /U (y) /P -4 >>', [LengthInBits]), EPdfParseException);
end;

procedure TStandardSecurityHandlerTests.TestBrokenRevision6EntriesRaise;
begin
  AssertLoadRaises('<< /Filter /Standard /V 5 /R 6 /O (x) /U (y) /P -4 >>', EPdfInvalidPasswordException);
end;

{ TAccessPermissionTests }

procedure TAccessPermissionTests.TestDefaultHasAllPermissions;
begin
  const Permission = TPdfAccessPermission.Create;
  try
    Assert.IsTrue(Permission.IsOwnerPermission);
    Assert.IsFalse(Permission.IsReadOnly);
  finally
    Permission.Free;
  end;
end;

procedure TAccessPermissionTests.TestBitsOfP(const P: Integer; const CanPrint, CanModify, CanPrintFaithful: Boolean);
begin
  const Permission = TPdfAccessPermission.Create(P);
  try
    Assert.AreEqual(CanPrint, Permission.CanPrint, 'print');
    Assert.AreEqual(CanModify, Permission.CanModify, 'modify');
    Assert.AreEqual(CanPrintFaithful, Permission.CanPrintFaithful, 'faithful');
  finally
    Permission.Free;
  end;
end;

procedure TAccessPermissionTests.TestOwnerPermissionNeedsAllBits;
begin
  const Permission = TPdfAccessPermission.Create(-3904);
  try
    Assert.IsFalse(Permission.IsOwnerPermission);
  finally
    Permission.Free;
  end;
end;

procedure TAccessPermissionTests.TestReadOnlyIgnoresSetters;
begin
  const Permission = TPdfAccessPermission.Create(0);
  try
    Permission.SetReadOnly;
    Permission.SetCanPrint(True);
    Assert.IsFalse(Permission.CanPrint);

    const Copy = Permission.Clone;
    try
      Assert.IsTrue(Copy.IsReadOnly);
    finally
      Copy.Free;
    end;
  finally
    Permission.Free;
  end;
end;

procedure TAccessPermissionTests.TestFromBytes;
begin
  const Permission = TPdfAccessPermission.FromBytes([$FF, $FF, $F0, $C0]);
  try
    Assert.AreEqual(Integer($FFFFF0C0), Permission.PermissionBytes);
  finally
    Permission.Free;
  end;
end;

{ TSaslPrepTests }

procedure TSaslPrepTests.TestAsciiStaysTheSame;
begin
  Assert.AreEqual('user Pass-1', TPdfSaslPrep.SaslPrepQuery('user Pass-1'));
end;

procedure TSaslPrepTests.TestNonAsciiSpaceBecomesSpace;
begin
  Assert.AreEqual('a b', TPdfSaslPrep.SaslPrepQuery('a' + #$00A0 + 'b'));
end;

procedure TSaslPrepTests.TestSoftHyphenIsRemoved;
begin
  Assert.AreEqual('ab', TPdfSaslPrep.SaslPrepQuery('a' + #$00AD + 'b'));
end;

procedure TSaslPrepTests.TestControlCharacterRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      TPdfSaslPrep.SaslPrepQuery('a' + #$0007 + 'b');
    end,
    EPdfSaslPrepException);
end;

procedure TSaslPrepTests.TestCompatibilityCharactersAreNormalized;
begin
  // The ligature fi (U+FB01) becomes the two letters
  Assert.AreEqual('final', TPdfSaslPrep.SaslPrepQuery(#$FB01 + 'nal'));
end;

procedure TSaslPrepTests.TestRandALCatAndLCatTogetherRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      TPdfSaslPrep.SaslPrepQuery(#$05D0 + 'a' + #$05D1);
    end,
    EPdfSaslPrepException);
end;

procedure TSaslPrepTests.TestCombiningMarkIsComposed;
begin
  // e followed by U+0301 becomes U+00E9
  Assert.AreEqual(#$00E9, TPdfSaslPrep.SaslPrepQuery('e' + #$0301));
end;

procedure TSaslPrepTests.TestFullwidthLettersBecomeAscii;
begin
  Assert.AreEqual('Ab1', TPdfSaslPrep.SaslPrepQuery(#$FF21 + #$FF42 + #$FF11));
end;

procedure TSaslPrepTests.TestHangulSyllableSurvivesDecompositionAndComposition;
begin
  // U+D55C, and the same syllable written as its three jamo
  Assert.AreEqual(#$D55C, TPdfSaslPrep.SaslPrepQuery(#$1112 + #$1161 + #$11AB));
  Assert.AreEqual(#$D55C, TPdfSaslPrep.SaslPrepQuery(#$D55C));
end;

procedure TSaslPrepTests.TestCombiningMarksAreOrdered;
begin
  // a with a dot below (class 220) and an acute (class 230): the order of the marks in the input does not matter
  Assert.AreEqual(TPdfSaslPrep.SaslPrepQuery('a' + #$0323 + #$0301), TPdfSaslPrep.SaslPrepQuery('a' + #$0301 + #$0323));
end;

procedure TSaslPrepTests.TestCompositionExclusionStaysDecomposed;
begin
  // U+0958 (Devanagari letter qa) is in CompositionExclusions.txt: it becomes ka and nukta and stays that way
  Assert.AreEqual(#$0915 + #$093C, TPdfSaslPrep.SaslPrepQuery(#$0958));
end;

procedure TSaslPrepTests.TestSingletonDecompositionIsNotComposedBack;
begin
  // The angstrom sign U+212B decomposes to U+00C5 only
  Assert.AreEqual(#$00C5, TPdfSaslPrep.SaslPrepQuery(#$212B));
end;

procedure TSaslPrepTests.TestSuperscriptAndFractionAreMapped;
begin
  Assert.AreEqual('2', TPdfSaslPrep.SaslPrepQuery(#$00B2));
  Assert.AreEqual('1' + #$2044 + '4', TPdfSaslPrep.SaslPrepQuery(#$00BC));
end;

end.
