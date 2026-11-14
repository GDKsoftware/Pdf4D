// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Encryption.Exemptions.Tests;

// Files that these tests encrypt themselves with the simplest handler (revision 2, RC4 with a 40 bit key, empty user
// password), so that each exemption of the security handler and each broken dictionary has a file of its own.

interface

uses
  System.SysUtils,
  System.Classes,
  DUnitX.TestFramework,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Document;

type
  TTestRc4Encryption = class
  private
    FFileKey: TBytes;
    FOwnerEntry: TBytes;
    FUserEntry: TBytes;
    FDocumentId: TBytes;

    class function Md5Of(const Data: TBytes): TBytes; static;
    class function PadPassword(const Password: string): TBytes; static;
    class function LittleEndian(const Value: Int64; const ByteCount: Integer): TBytes; static;

  public
    class function Hex(const Data: TBytes): string; static;
    class function Ascii(const Text: string): TBytes; static;

    constructor Create(const DocumentId: TBytes);

    // The text of the encryption dictionary. Extra holds the entries of version 4 files (/StmF and /StrF).
    function EncryptionDictionary(const Version: Integer; const Extra: string): string;
    function Encrypt(const ObjectNumber: Integer; const Data: TBytes): TBytes;
    function HexString(const ObjectNumber: Integer; const Text: string; const Encrypted: Boolean): string;

    property DocumentId: TBytes read FDocumentId;
  end;

  [TestFixture]
  TSecurityHandlerExemptionTests = class
  private
    FDocument: TCosDocument;

    class function CorpusFolder: string; static;

    function TrailerEntries(const Encryption: TTestRc4Encryption; const EncryptEntry: string): string;
    function BuildDocument(const Version: Integer; const FilterEntries: string; const EncryptStrings, EncryptStreams: Boolean): TBytes;
    function BuildObjectStreamDocument: TBytes;
    function BuildWithEncryptObject(const EncryptBody, EncryptEntry: string): TBytes;
    function BuildWithDocumentId(const IdEntryText: string): TBytes;
    function Open(const Data: TBytes; const Password: string): TCosDocument;
    function Fetch(const Number: Integer): TCosBase;
    function FetchDictionary(const Number: Integer): TCosDictionary;
    function FetchStream(const Number: Integer): TCosStream;
    function StringBytes(const Dictionary: TCosDictionary; const Key: string): TBytes;
    function RawBytes(const Stream: TCosStream): TBytes;
    procedure OpenBuilt(const Data: TBytes);
    procedure AssertBytes(const Expected, Actual: TBytes; const Description: string);
    procedure AssertOpenRaises(const Data: TBytes; const Password: string; const ExceptionClass: ExceptClass);
    function CorpusBytes(const RelativeName: string): TBytes;
    function Patched(const Data: TBytes; const Find, Replacement: string): TBytes;
    function WithBlankedHexTail(const Data: TBytes; const Marker: string; const BlankedChars: Integer): TBytes;
    function EncryptedStreamBytes(const Data: TBytes; const Encryption: TTestRc4Encryption; const ObjectOffset: Int64; const ObjectNumber: Integer): TBytes;

  public
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestEncryptedFileOfTheTestsOpens;

    [Test]
    procedure TestSignatureContentsWithTypeIsNotDecrypted;

    [Test]
    procedure TestSignatureContentsWithByteRangeIsNotDecrypted;

    [Test]
    procedure TestContentsOfAnOtherDictionaryIsDecrypted;

    [Test]
    procedure TestIdentityFiltersLeaveStringsAndStreams;

    [Test]
    procedure TestStreamFilterIdentityStillDecryptsStrings;

    [Test]
    procedure TestStringFilterIdentityStillDecryptsStreams;

    [Test]
    procedure TestCryptFilterIdentityStreamIsNotDecrypted;

    [Test]
    procedure TestCryptFilterWithNameIsDecrypted;

    [Test]
    procedure TestXRefStreamIsNotDecrypted;

    [Test]
    procedure TestStringsInObjectStreamAreDecryptedOnce;

    [Test]
    procedure TestMissingPermsRaises;

    [Test]
    procedure TestShortPermsRaises;

    [Test]
    procedure TestMissingUserEncryptionKeyRaises;

    [Test]
    procedure TestMissingOwnerEncryptionKeyRaises;

    [Test]
    procedure TestEncryptEntryThatIsNotADictionaryIsIgnored;

    [Test]
    procedure TestEncryptEntryWithAnIndirectStringIsIgnored;

    [Test]
    procedure TestDocumentIdWithoutStringsRaises;
  end;

implementation

uses
  System.Hash,
  System.IOUtils,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.ObjectKey,
  Pdf4D.Cos.PdfObject,
  Pdf4D.Cos.PdfString,
  Pdf4D.Crypto.RC4,
  Pdf4D.Parser.Pdf,
  Pdf4D.Tests.PdfBuilder;

const
  CorpusEnvironmentVariable = 'PDF4D_CORPUS';
  EncryptedFolder = 'generated/encrypted/';
  KeyBytes = 5;
  PermissionsValue = -4;
  PermissionsBytes = 4;
  ObjectNumberBytes = 3;
  GenerationBytes = 2;
  MaxFolderLevels = 12;
  EncryptNumber = 5;
  PlainText = 'Hello encryption';
  StreamText = 'BT /F1 12 Tf (Stream) Tj ET';
  SignatureText = '0123456789ABCDEF';
  PackedText = 'Packed';
  OwnerPassword = 'owner';
  EmptyPassword = '';
  Aes256EmptyFile = 'aes-256-empty.pdf';
  Aes256UserFile = 'aes-256-user.pdf';
  StreamMarker = 'stream'#10;
  EndStreamMarker = #10'endstream';
  EncryptPadding: array[0..31] of Byte = (
    $28, $BF, $4E, $5E, $4E, $75, $8A, $41, $64, $00, $4E, $56, $FF, $FA, $01, $08,
    $2E, $2E, $00, $B6, $D0, $68, $3E, $80, $2F, $0C, $A9, $FE, $64, $53, $69, $7A);
  DocumentIdValue: array[0..15] of Byte = ($00, $11, $22, $33, $44, $55, $66, $77, $88, $99, $AA, $BB, $CC, $DD, $EE, $FF);

function TestDocumentId: TBytes;
begin
  SetLength(Result, Length(DocumentIdValue));
  Move(DocumentIdValue[0], Result[0], Length(DocumentIdValue));
end;

{ TTestRc4Encryption }

class function TTestRc4Encryption.Md5Of(const Data: TBytes): TBytes;
begin
  var Hash := THashMD5.Create;
  Hash.Update(Data);
  Result := Hash.HashAsBytes;
end;

class function TTestRc4Encryption.Hex(const Data: TBytes): string;
begin
  Result := '';
  for var Value in Data do
  begin
    Result := Result + IntToHex(Value, 2);
  end;
end;

class function TTestRc4Encryption.Ascii(const Text: string): TBytes;
begin
  SetLength(Result, Length(Text));
  for var Position := 1 to Length(Text) do
  begin
    Result[Position - 1] := Byte(Ord(Text[Position]));
  end;
end;

class function TTestRc4Encryption.PadPassword(const Password: string): TBytes;
begin
  const Typed = Ascii(Password);
  SetLength(Result, Length(EncryptPadding));
  for var Position := 0 to High(Result) do
  begin
    if Position < Length(Typed) then
    begin
      Result[Position] := Typed[Position];
    end
    else
    begin
      Result[Position] := EncryptPadding[Position - Length(Typed)];
    end;
  end;
end;

class function TTestRc4Encryption.LittleEndian(const Value: Int64; const ByteCount: Integer): TBytes;
begin
  SetLength(Result, ByteCount);
  for var Position := 0 to ByteCount - 1 do
  begin
    Result[Position] := Byte((Value shr (8 * Position)) and $FF);
  end;
end;

constructor TTestRc4Encryption.Create(const DocumentId: TBytes);
begin
  inherited Create;
  FDocumentId := DocumentId;

  // Algorithm 3: the owner entry is the padded user password, encrypted with a key from the owner password
  const OwnerDigest = Md5Of(PadPassword(OwnerPassword));
  const OwnerKey = Copy(OwnerDigest, 0, KeyBytes);
  FOwnerEntry := TRC4Cipher.Process(OwnerKey, PadPassword(EmptyPassword));

  // Algorithm 2: the file key
  const Material = PadPassword(EmptyPassword) + FOwnerEntry + LittleEndian(PermissionsValue, PermissionsBytes) + FDocumentId;
  const KeyDigest = Md5Of(Material);
  FFileKey := Copy(KeyDigest, 0, KeyBytes);

  // Algorithm 4: the user entry is the padding, encrypted with the file key
  var Padding: TBytes;
  SetLength(Padding, Length(EncryptPadding));
  Move(EncryptPadding[0], Padding[0], Length(EncryptPadding));
  FUserEntry := TRC4Cipher.Process(FFileKey, Padding);
end;

function TTestRc4Encryption.EncryptionDictionary(const Version: Integer; const Extra: string): string;
begin
  const OwnerHex = Hex(FOwnerEntry);
  const UserHex = Hex(FUserEntry);
  Result := Format('<< /Filter /Standard /V %d /R 2 /Length 40 /P %d /O <%s> /U <%s> %s >>', [Version, PermissionsValue, OwnerHex, UserHex, Extra]);
end;

// Algorithm 1: the key of an object is the file key with the number and the generation, hashed
function TTestRc4Encryption.Encrypt(const ObjectNumber: Integer; const Data: TBytes): TBytes;
begin
  const Material = FFileKey + LittleEndian(ObjectNumber, ObjectNumberBytes) + LittleEndian(0, GenerationBytes);
  const Digest = Md5Of(Material);
  const ObjectKey = Copy(Digest, 0, Length(Material));
  Result := TRC4Cipher.Process(ObjectKey, Data);
end;

function TTestRc4Encryption.HexString(const ObjectNumber: Integer; const Text: string; const Encrypted: Boolean): string;
begin
  var Bytes := Ascii(Text);
  if Encrypted then
  begin
    Bytes := Encrypt(ObjectNumber, Bytes);
  end;
  Result := '<' + Hex(Bytes) + '>';
end;

{ TSecurityHandlerExemptionTests }

procedure TSecurityHandlerExemptionTests.TearDown;
begin
  FreeAndNil(FDocument);
end;

class function TSecurityHandlerExemptionTests.CorpusFolder: string;
begin
  const FromEnvironment = GetEnvironmentVariable(CorpusEnvironmentVariable);
  if FromEnvironment <> '' then
  begin
    Exit(FromEnvironment);
  end;

  var Folder := TPath.GetDirectoryName(ParamStr(0));
  for var Level := 1 to MaxFolderLevels do
  begin
    const Candidate = TPath.Combine(Folder, 'corpus');
    if TFile.Exists(TPath.Combine(Candidate, 'manifest.csv')) then
    begin
      Exit(Candidate);
    end;
    Folder := TPath.GetDirectoryName(Folder);
  end;
  Result := '';
end;

function TSecurityHandlerExemptionTests.CorpusBytes(const RelativeName: string): TBytes;
begin
  const FileName = TPath.Combine(CorpusFolder, (EncryptedFolder + RelativeName).Replace('/', PathDelim));
  Assert.IsTrue(TFile.Exists(FileName), Format('Corpus file %s was not found, set %s', [RelativeName, CorpusEnvironmentVariable]));
  Result := TFile.ReadAllBytes(FileName);
end;

function TSecurityHandlerExemptionTests.Open(const Data: TBytes; const Password: string): TCosDocument;
begin
  var Options := TPdfLoadOptions.Default;
  Options.Password := Password;
  Result := TPdfParser.Parse(TBytesStream.Create(Data), True, Options);
end;

procedure TSecurityHandlerExemptionTests.OpenBuilt(const Data: TBytes);
begin
  FreeAndNil(FDocument);
  FDocument := Open(Data, EmptyPassword);
end;

function TSecurityHandlerExemptionTests.Fetch(const Number: Integer): TCosBase;
begin
  const Key = TCosObjectKey.Make(Number, 0);
  const Proxy = FDocument.GetObjectFromPool(Key);
  Result := Proxy.GetObject;
end;

function TSecurityHandlerExemptionTests.FetchDictionary(const Number: Integer): TCosDictionary;
begin
  const Loaded = Fetch(Number);
  Assert.IsTrue(Loaded is TCosDictionary, Format('Object %d is not a dictionary', [Number]));
  Result := TCosDictionary(Loaded);
end;

function TSecurityHandlerExemptionTests.FetchStream(const Number: Integer): TCosStream;
begin
  const Loaded = Fetch(Number);
  Assert.IsTrue(Loaded is TCosStream, Format('Object %d is not a stream', [Number]));
  Result := TCosStream(Loaded);
end;

function TSecurityHandlerExemptionTests.StringBytes(const Dictionary: TCosDictionary; const Key: string): TBytes;
begin
  var Value: TCosBase;
  Assert.IsTrue(Dictionary.TryGetDictionaryObject(Key, Value), Format('The dictionary has no /%s', [Key]));
  Assert.IsTrue(Value is TCosString, Format('/%s is not a string', [Key]));
  Result := Copy(TCosString(Value).Bytes);
end;

function TSecurityHandlerExemptionTests.RawBytes(const Stream: TCosStream): TBytes;
begin
  const Data = Stream.CreateRawStream;
  try
    SetLength(Result, Data.Size);
    Data.Position := 0;
    if Length(Result) > 0 then
    begin
      Data.ReadBuffer(Result, Length(Result));
    end;
  finally
    Data.Free;
  end;
end;

procedure TSecurityHandlerExemptionTests.AssertBytes(const Expected, Actual: TBytes; const Description: string);
begin
  Assert.AreEqual(TTestRc4Encryption.Hex(Expected), TTestRc4Encryption.Hex(Actual), Description);
end;

procedure TSecurityHandlerExemptionTests.AssertOpenRaises(const Data: TBytes; const Password: string; const ExceptionClass: ExceptClass);
begin
  Assert.WillRaise(
    procedure
    begin
      Open(Data, Password).Free;
    end,
    ExceptionClass);
end;

{ building files }

function TSecurityHandlerExemptionTests.TrailerEntries(const Encryption: TTestRc4Encryption; const EncryptEntry: string): string;
begin
  const IdHex = TTestRc4Encryption.Hex(Encryption.DocumentId);
  Result := Format('/Encrypt %s /ID [<%s> <%s>]', [EncryptEntry, IdHex, IdHex]);
end;

function TSecurityHandlerExemptionTests.BuildDocument(const Version: Integer; const FilterEntries: string; const EncryptStrings, EncryptStreams: Boolean): TBytes;
begin
  const Encryption = TTestRc4Encryption.Create(TestDocumentId);
  try
    const Builder = TTestPdfBuilder.Create;
    try
      Builder.AddObject(1, '<< /Type /Catalog /Pages 2 0 R >>');
      Builder.AddObject(2, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
      Builder.AddObject(3, '<< /Type /Page /Parent 2 0 R >>');
      Builder.AddObject(4, '<< /Title ' + Encryption.HexString(4, PlainText, EncryptStrings) + ' >>');
      Builder.AddObject(EncryptNumber, Encryption.EncryptionDictionary(Version, FilterEntries));

      const PlainSignature = Encryption.HexString(6, SignatureText, False);
      Builder.AddObject(6, Format('<< /Type /Sig /Contents %s /Reason %s >>', [PlainSignature, Encryption.HexString(6, PlainText, EncryptStrings)]));
      Builder.AddObject(7, Format('<< /Contents %s /ByteRange [0 1 2 3] /Name %s >>', [PlainSignature, Encryption.HexString(7, PlainText, EncryptStrings)]));

      const PlainStream = TTestRc4Encryption.Ascii(StreamText);
      var Stored8 := PlainStream;
      var Stored11 := PlainStream;
      if EncryptStreams then
      begin
        Stored8 := Encryption.Encrypt(8, PlainStream);
        Stored11 := Encryption.Encrypt(11, PlainStream);
      end;
      Builder.AddStreamObject(8, '', Stored8);
      Builder.AddStreamObject(9, '/Type /XRef', PlainStream);
      Builder.AddStreamObject(10, '/Filter [/Crypt] /DecodeParms [<< /Name /Identity >>]', PlainStream);
      Builder.AddStreamObject(11, '/Filter [/Crypt] /DecodeParms [<< /Name /StdCF >>]', Stored11);
      Builder.AddObject(12, '<< /Contents ' + Encryption.HexString(12, PlainText, EncryptStrings) + ' >>');

      Builder.SetRoot(1);
      Builder.TrailerExtra := TrailerEntries(Encryption, '5 0 R') + ' /Info 4 0 R';
      Result := Builder.Build(TXrefStyle.Table);
    finally
      Builder.Free;
    end;
  finally
    Encryption.Free;
  end;
end;

function TSecurityHandlerExemptionTests.EncryptedStreamBytes(const Data: TBytes; const Encryption: TTestRc4Encryption; const ObjectOffset: Int64; const ObjectNumber: Integer): TBytes;
begin
  // The data of the stream between "stream" and "endstream", encrypted in place: RC4 does not change the length
  var Text := '';
  for var Value in Data do
  begin
    Text := Text + Chr(Value);
  end;

  const StreamStart = Pos(StreamMarker, Text, Integer(ObjectOffset) + 1) + Length(StreamMarker);
  const StreamEnd = Pos(EndStreamMarker, Text, StreamStart);
  Assert.IsTrue(StreamEnd > StreamStart, 'The object stream was not found in the file');

  const Plain = Copy(Data, StreamStart - 1, StreamEnd - StreamStart);
  const Encrypted = Encryption.Encrypt(ObjectNumber, Plain);
  Result := Copy(Data);
  Move(Encrypted[0], Result[StreamStart - 1], Length(Encrypted));
end;

function TSecurityHandlerExemptionTests.BuildObjectStreamDocument: TBytes;
begin
  const Encryption = TTestRc4Encryption.Create(TestDocumentId);
  try
    const Builder = TTestPdfBuilder.Create;
    try
      Builder.AddObject(1, '<< /Type /Catalog /Pages 2 0 R >>');
      Builder.AddObject(2, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
      Builder.AddObject(3, '<< /Type /Page /Parent 2 0 R >>');
      Builder.AddObject(EncryptNumber, Encryption.EncryptionDictionary(1, ''));
      Builder.AddCompressedObject(8, '<< /S (' + PackedText + ') >>', 6);
      Builder.AddCompressedObject(9, '(' + PackedText + ')', 6);
      Builder.SetRoot(1);
      Builder.TrailerExtra := TrailerEntries(Encryption, '5 0 R');

      const Plain = Builder.Build(TXrefStyle.Stream);
      Result := EncryptedStreamBytes(Plain, Encryption, Builder.OffsetOf(6), 6);
    finally
      Builder.Free;
    end;
  finally
    Encryption.Free;
  end;
end;

function TSecurityHandlerExemptionTests.BuildWithEncryptObject(const EncryptBody, EncryptEntry: string): TBytes;
begin
  const Builder = TTestPdfBuilder.Create;
  try
    Builder.AddObject(1, '<< /Type /Catalog /Pages 2 0 R >>');
    Builder.AddObject(2, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
    Builder.AddObject(3, '<< /Type /Page /Parent 2 0 R >>');
    if EncryptBody <> '' then
    begin
      Builder.AddObject(EncryptNumber, EncryptBody);
    end;
    Builder.SetRoot(1);
    Builder.TrailerExtra := '/Encrypt ' + EncryptEntry;
    Result := Builder.Build(TXrefStyle.Table);
  finally
    Builder.Free;
  end;
end;

function TSecurityHandlerExemptionTests.BuildWithDocumentId(const IdEntryText: string): TBytes;
begin
  const Encryption = TTestRc4Encryption.Create(TestDocumentId);
  try
    const Builder = TTestPdfBuilder.Create;
    try
      Builder.AddObject(1, '<< /Type /Catalog /Pages 2 0 R >>');
      Builder.AddObject(2, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
      Builder.AddObject(3, '<< /Type /Page /Parent 2 0 R >>');
      Builder.AddObject(EncryptNumber, Encryption.EncryptionDictionary(1, ''));
      Builder.SetRoot(1);
      Builder.TrailerExtra := '/Encrypt 5 0 R ' + IdEntryText;
      Result := Builder.Build(TXrefStyle.Table);
    finally
      Builder.Free;
    end;
  finally
    Encryption.Free;
  end;
end;

{ patching corpus files }

function TSecurityHandlerExemptionTests.Patched(const Data: TBytes; const Find, Replacement: string): TBytes;
begin
  Assert.AreEqual(Length(Find), Length(Replacement), 'A patch keeps the length, so that the offsets stay valid');
  var Text := '';
  for var Value in Data do
  begin
    Text := Text + Chr(Value);
  end;

  const Position = Pos(Find, Text);
  Assert.IsTrue(Position > 0, Format('%s is not in the file', [Find]));
  Result := Copy(Data);
  for var Offset := 1 to Length(Replacement) do
  begin
    Result[Position - 1 + Offset - 1] := Byte(Ord(Replacement[Offset]));
  end;
end;

// The hex digits in front of the closing > of the string that follows Marker become spaces: the string loses bytes
function TSecurityHandlerExemptionTests.WithBlankedHexTail(const Data: TBytes; const Marker: string; const BlankedChars: Integer): TBytes;
begin
  var Text := '';
  for var Value in Data do
  begin
    Text := Text + Chr(Value);
  end;

  const MarkerPosition = Pos(Marker, Text);
  Assert.IsTrue(MarkerPosition > 0, Format('%s is not in the file', [Marker]));
  const ClosePosition = Pos('>', Text, MarkerPosition);
  Result := Copy(Data);
  for var Offset := 1 to BlankedChars do
  begin
    Result[ClosePosition - 1 - Offset] := Ord(' ');
  end;
end;

{ tests }

procedure TSecurityHandlerExemptionTests.TestEncryptedFileOfTheTestsOpens;
begin
  OpenBuilt(BuildDocument(1, '', True, True));

  AssertBytes(TTestRc4Encryption.Ascii(PlainText), StringBytes(FetchDictionary(4), TCosNames.Title), 'The string of the info dictionary');
  AssertBytes(TTestRc4Encryption.Ascii(StreamText), RawBytes(FetchStream(8)), 'The data of the stream');
end;

procedure TSecurityHandlerExemptionTests.TestSignatureContentsWithTypeIsNotDecrypted;
begin
  OpenBuilt(BuildDocument(1, '', True, True));

  const Signature = FetchDictionary(6);

  AssertBytes(TTestRc4Encryption.Ascii(SignatureText), StringBytes(Signature, TCosNames.Contents), '/Contents of a /Type /Sig dictionary');
  AssertBytes(TTestRc4Encryption.Ascii(PlainText), StringBytes(Signature, TCosNames.Reason), 'The other strings are decrypted');
end;

procedure TSecurityHandlerExemptionTests.TestSignatureContentsWithByteRangeIsNotDecrypted;
begin
  OpenBuilt(BuildDocument(1, '', True, True));

  const Signature = FetchDictionary(7);

  AssertBytes(TTestRc4Encryption.Ascii(SignatureText), StringBytes(Signature, TCosNames.Contents), '/Contents with a /ByteRange');
  AssertBytes(TTestRc4Encryption.Ascii(PlainText), StringBytes(Signature, TCosNames.Name), 'The other strings are decrypted');
end;

procedure TSecurityHandlerExemptionTests.TestContentsOfAnOtherDictionaryIsDecrypted;
begin
  OpenBuilt(BuildDocument(1, '', True, True));

  AssertBytes(TTestRc4Encryption.Ascii(PlainText), StringBytes(FetchDictionary(12), TCosNames.Contents), '/Contents without a signature');
end;

procedure TSecurityHandlerExemptionTests.TestIdentityFiltersLeaveStringsAndStreams;
begin
  OpenBuilt(BuildDocument(4, '/StmF /Identity /StrF /Identity', False, False));

  AssertBytes(TTestRc4Encryption.Ascii(PlainText), StringBytes(FetchDictionary(4), TCosNames.Title), 'The string stays as it is');
  AssertBytes(TTestRc4Encryption.Ascii(StreamText), RawBytes(FetchStream(8)), 'The stream stays as it is');
end;

procedure TSecurityHandlerExemptionTests.TestStreamFilterIdentityStillDecryptsStrings;
begin
  OpenBuilt(BuildDocument(4, '/StmF /Identity /StrF /StdCF', True, False));

  AssertBytes(TTestRc4Encryption.Ascii(PlainText), StringBytes(FetchDictionary(4), TCosNames.Title), 'The string is decrypted');
  AssertBytes(TTestRc4Encryption.Ascii(StreamText), RawBytes(FetchStream(8)), 'The stream stays as it is');
end;

procedure TSecurityHandlerExemptionTests.TestStringFilterIdentityStillDecryptsStreams;
begin
  OpenBuilt(BuildDocument(4, '/StmF /StdCF /StrF /Identity', False, True));

  AssertBytes(TTestRc4Encryption.Ascii(PlainText), StringBytes(FetchDictionary(4), TCosNames.Title), 'The string stays as it is');
  AssertBytes(TTestRc4Encryption.Ascii(StreamText), RawBytes(FetchStream(8)), 'The stream is decrypted');
end;

procedure TSecurityHandlerExemptionTests.TestCryptFilterIdentityStreamIsNotDecrypted;
begin
  OpenBuilt(BuildDocument(1, '', True, True));

  AssertBytes(TTestRc4Encryption.Ascii(StreamText), RawBytes(FetchStream(10)), 'A stream with its own Identity crypt filter');
end;

procedure TSecurityHandlerExemptionTests.TestCryptFilterWithNameIsDecrypted;
begin
  OpenBuilt(BuildDocument(1, '', True, True));

  AssertBytes(TTestRc4Encryption.Ascii(StreamText), RawBytes(FetchStream(11)), 'A stream with a crypt filter that has a name');
end;

procedure TSecurityHandlerExemptionTests.TestXRefStreamIsNotDecrypted;
begin
  OpenBuilt(BuildDocument(1, '', True, True));

  AssertBytes(TTestRc4Encryption.Ascii(StreamText), RawBytes(FetchStream(9)), 'A stream of /Type /XRef');
end;

procedure TSecurityHandlerExemptionTests.TestStringsInObjectStreamAreDecryptedOnce;
begin
  OpenBuilt(BuildObjectStreamDocument);

  const PackedDictionary = FetchDictionary(8);
  AssertBytes(TTestRc4Encryption.Ascii(PackedText), StringBytes(PackedDictionary, 'S'), 'A string in a dictionary of the object stream');

  const Loaded = Fetch(9);
  Assert.IsTrue(Loaded is TCosString, 'Object 9 is not a string');
  AssertBytes(TTestRc4Encryption.Ascii(PackedText), TCosString(Loaded).Bytes, 'A string object of the object stream');
end;

procedure TSecurityHandlerExemptionTests.TestMissingPermsRaises;
begin
  const Data = Patched(CorpusBytes(Aes256EmptyFile), '/Perms <', '/PermX <');

  AssertOpenRaises(Data, EmptyPassword, EPdfParseException);
end;

procedure TSecurityHandlerExemptionTests.TestShortPermsRaises;
begin
  const Data = WithBlankedHexTail(CorpusBytes(Aes256EmptyFile), '/Perms <', 4);

  AssertOpenRaises(Data, EmptyPassword, EPdfParseException);
end;

procedure TSecurityHandlerExemptionTests.TestMissingUserEncryptionKeyRaises;
begin
  const Data = Patched(CorpusBytes(Aes256EmptyFile), '/UE <', '/UX <');

  AssertOpenRaises(Data, EmptyPassword, EPdfParseException);
end;

procedure TSecurityHandlerExemptionTests.TestMissingOwnerEncryptionKeyRaises;
begin
  const Data = Patched(CorpusBytes(Aes256UserFile), '/OE <', '/OX <');

  AssertOpenRaises(Data, OwnerPassword, EPdfParseException);
end;

procedure TSecurityHandlerExemptionTests.TestEncryptEntryThatIsNotADictionaryIsIgnored;
begin
  // Like PDFBox: without a dictionary the file counts as not encrypted
  OpenBuilt(BuildWithEncryptObject('', '42'));

  Assert.IsNull(FDocument.Encryption);
  Assert.IsNotNull(FDocument.Trailer.GetItem(TCosNames.Root));
end;

procedure TSecurityHandlerExemptionTests.TestEncryptEntryWithAnIndirectStringIsIgnored;
begin
  OpenBuilt(BuildWithEncryptObject('(not a dictionary)', '5 0 R'));

  Assert.IsNull(FDocument.Encryption);
  Assert.IsNotNull(FDocument.Trailer.GetItem(TCosNames.Root));
end;

procedure TSecurityHandlerExemptionTests.TestDocumentIdWithoutStringsRaises;
begin
  AssertOpenRaises(BuildWithDocumentId('/ID [1 2]'), EmptyPassword, EPdfParseException);
end;

end.
