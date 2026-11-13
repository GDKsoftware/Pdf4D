// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/encryption/StandardSecurityHandler.java (3.0.8), the decrypting side
// Algorithms 1.A, 2, 2.A, 2.B, 3 to 7 and 11 to 13 of ISO 32000-2 7.6.4 and 7.6.5
unit Pdf4D.Encryption.StandardSecurityHandler;

interface

uses
  System.SysUtils,
  Pdf4D.Common.Log,
  Pdf4D.Encryption.Dictionary,
  Pdf4D.Encryption.SecurityHandler;

type
  TStandardSecurityHandler = class(TSecurityHandler)
  private
    type
      // What the checks of the passwords need from the encryption dictionary
      TEncryptionParameters = record
        UserKey: TBytes;
        OwnerKey: TBytes;
        Permissions: Integer;
        DocumentId: TBytes;
        Revision: Integer;
        KeyLengthInBytes: Integer;
        EncryptMetadata: Boolean;
      end;

  private
    class function Concat(const First, Second, Third: TBytes): TBytes; static;
    class function BytesEqual(const First, Second: TBytes): Boolean; static;
    class function Truncate127(const Value: TBytes): TBytes; static;
    class function TruncateOrPad(const Password: TBytes): TBytes; static;
    class function Md5Of(const Data: TBytes): TBytes; static;
    class function Sha2Of(const Version: Integer; const Data: TBytes): TBytes; static;
    class function XorWithRound(const Key: TBytes; const Round: Integer): TBytes; static;
    class function AdjustUserKey(const UserKey: TBytes): TBytes; static;
    class function ComputeSha256(const Input, Password, UserKey: TBytes): TBytes; static;
    class function ComputeHash2A(const Password, Salt, UserKey: TBytes): TBytes; static;
    class function ComputeHash2B(const Input, Password, UserKey: TBytes): TBytes; static;
    class function NextHash2BRound(const K: TBytes; const Password, UserKey: TBytes; out E: TBytes): TBytes; static;
    class function RepeatedHashInput(const Password, K, UserKey: TBytes): TBytes; static;
    class function ComputeRC4Key(const OwnerPassword: TBytes; const Revision, KeyLengthInBytes: Integer): TBytes; static;
    class function GetUserPassword234(const OwnerPassword, Owner: TBytes; const Revision, KeyLengthInBytes: Integer): TBytes; static;
    class function ComputeEncryptedKeyRev234(const Password: TBytes; const Parameters: TEncryptionParameters): TBytes; static;
    class function ComputeUserPassword(const Password: TBytes; const Parameters: TEncryptionParameters): TBytes; static;
    class function IsUserPassword234(const Password: TBytes; const Parameters: TEncryptionParameters): Boolean; static;
    class function IsOwnerPassword234(const OwnerPassword: TBytes; const Parameters: TEncryptionParameters): Boolean; static;
    class function IsUserPassword56(const Password: TBytes; const Parameters: TEncryptionParameters): Boolean; static;
    class function IsOwnerPassword56(const OwnerPassword: TBytes; const Parameters: TEncryptionParameters): Boolean; static;
    class function PasswordToBytes(const Password: string; const Revision: Integer): TBytes; static;
    class function Latin1Bytes(const Text: string): TBytes; static;
    class procedure GuardKeyLength(const Parameters: TEncryptionParameters); static;

    function IsOwnerPassword(const PasswordBytes: TBytes; const Parameters: TEncryptionParameters): Boolean;
    function IsUserPassword(const PasswordBytes: TBytes; const Parameters: TEncryptionParameters): Boolean;
    function ComputeEncryptedKey(const Password: TBytes; const Parameters: TEncryptionParameters; const EncryptionKeys: TBytes;
                                 const IsOwner: Boolean): TBytes;
    function ComputeEncryptedKeyRev56(const Password: TBytes; const Parameters: TEncryptionParameters; const EncryptedFileKey: TBytes;
                                      const IsOwner: Boolean): TBytes;
    function ReadParameters(const Encryption: TPdfEncryption; const DocumentId: TBytes; const KeyLengthInBytes: Integer): TEncryptionParameters;
    function ReadKeyLengthInBytes(const Encryption: TPdfEncryption): Integer;
    procedure ApplyCryptFilterMethod(const Encryption: TPdfEncryption; var KeyLengthInBytes: Integer);
    procedure ValidatePerms(const Encryption: TPdfEncryption; const Permissions: Integer; const EncryptMetadata: Boolean);
    procedure SetAccessPermission(const Permissions: Integer; const IsOwner: Boolean);

  public
    // Port of prepareForDecryption: checks the owner password first and then the user password. Raises
    // EPdfInvalidPasswordException when neither fits. The password is the text the user typed, empty for none.
    procedure PrepareForDecryption(const Encryption: TPdfEncryption; const DocumentId: TBytes; const Password: string);
  end;

const
  StandardSecurityFilterName = 'Standard';

implementation

uses
  System.Hash,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Names,
  Pdf4D.Crypto.AES,
  Pdf4D.Crypto.RC4,
  Pdf4D.Encryption.AccessPermission,
  Pdf4D.Encryption.SaslPrep;

const
  Revision2 = 2;
  Revision3 = 3;
  Revision4 = 4;
  Revision5 = 5;
  Revision6 = 6;
  Version1 = 1;
  Version4 = 4;
  Version5 = 5;
  Sha256Version = 0;
  Sha384Version = 1;
  Sha512Version = 2;
  MaxPasswordBytes = 127;
  PaddingLength = 32;
  Md5Length = 16;
  MaxRc4KeyBytes = 16;
  UserKeyLengthRevision56 = 48;
  HashLength = 32;
  ValidationSaltLength = 8;
  KeySaltOffset = 40;
  MinOwnerLengthRevision56 = 40;
  Aes128Bytes = 16;
  BitsPerByte = 8;
  Version1KeyBytes = 5;
  Hash2BFixedRounds = 64;
  Hash2BRoundLimitOffset = 32;
  AesBlockLength = 16;
  PermsConstantOffset = 9;
  PermsMetadataOffset = 8;
  PermsLength = 16;
  UnknownCharacter = Ord('?');
  Latin1Limit = $100;
  FullPermissionsBytes = 4;
  RevisionFourMinimumKeyBytes = 16;
  UnknownRevisionMessage = 'Unknown Encryption Revision %d';

  EncryptPadding: array[0..31] of Byte = (
    $28, $BF, $4E, $5E, $4E, $75, $8A, $41, $64, $00, $4E, $56, $FF, $FA, $01, $08,
    $2E, $2E, $00, $B6, $D0, $68, $3E, $80, $2F, $0C, $A9, $FE, $64, $53, $69, $7A);

{ TStandardSecurityHandler }

class function TStandardSecurityHandler.Concat(const First, Second, Third: TBytes): TBytes;
begin
  Result := First + Second + Third;
end;

class function TStandardSecurityHandler.BytesEqual(const First, Second: TBytes): Boolean;
begin
  Result := (Length(First) = Length(Second));
  if not Result then
  begin
    Exit;
  end;

  // Compares all bytes so that the time does not tell where they differ
  var Difference: Byte := 0;
  for var Position := 0 to High(First) do
  begin
    Difference := Difference or (First[Position] xor Second[Position]);
  end;
  Result := (Difference = 0);
end;

class function TStandardSecurityHandler.Truncate127(const Value: TBytes): TBytes;
begin
  if Length(Value) <= MaxPasswordBytes then
  begin
    Exit(Value);
  end;
  Result := Copy(Value, 0, MaxPasswordBytes);
end;

class function TStandardSecurityHandler.TruncateOrPad(const Password: TBytes): TBytes;
begin
  SetLength(Result, PaddingLength);
  const BytesBeforePad = Length(Password);
  for var Position := 0 to PaddingLength - 1 do
  begin
    if Position < BytesBeforePad then
    begin
      Result[Position] := Password[Position];
    end
    else
    begin
      Result[Position] := EncryptPadding[Position - BytesBeforePad];
    end;
  end;
end;

class function TStandardSecurityHandler.Md5Of(const Data: TBytes): TBytes;
begin
  var Hash := THashMD5.Create;
  Hash.Update(Data);
  Result := Hash.HashAsBytes;
end;

class function TStandardSecurityHandler.Sha2Of(const Version: Integer; const Data: TBytes): TBytes;
begin
  var Hash: THashSHA2;
  case Version of
    Sha256Version : Hash := THashSHA2.Create(SHA256);
    Sha384Version : Hash := THashSHA2.Create(SHA384);
    Sha512Version : Hash := THashSHA2.Create(SHA512);
  else
    raise EArgumentException.CreateFmt('Unknown SHA-2 version %d', [Version]);
  end;
  Hash.Update(Data);
  Result := Hash.HashAsBytes;
end;

class function TStandardSecurityHandler.XorWithRound(const Key: TBytes; const Round: Integer): TBytes;
begin
  SetLength(Result, Length(Key));
  for var Position := 0 to High(Key) do
  begin
    Result[Position] := Key[Position] xor Byte(Round);
  end;
end;

class function TStandardSecurityHandler.Latin1Bytes(const Text: string): TBytes;
begin
  SetLength(Result, Length(Text));
  for var Position := 1 to Length(Text) do
  begin
    // Java replaces what ISO-8859-1 does not have by a question mark
    const CharCode = Ord(Text[Position]);
    if CharCode < Latin1Limit then
    begin
      Result[Position - 1] := Byte(CharCode);
    end
    else
    begin
      Result[Position - 1] := UnknownCharacter;
    end;
  end;
end;

// The revisions 5 and 6 use UTF-8, and only revision 6 puts the password through SASLprep, like PDFBox
class function TStandardSecurityHandler.PasswordToBytes(const Password: string; const Revision: Integer): TBytes;
begin
  const IsRevision56 = ((Revision = Revision5) or (Revision = Revision6));
  if not IsRevision56 then
  begin
    Exit(Latin1Bytes(Password));
  end;

  var Prepared := Password;
  if Revision = Revision6 then
  begin
    try
      Prepared := TPdfSaslPrep.SaslPrepQuery(Password);
    except
      on Failure: EPdfSaslPrepException do
      begin
        raise EPdfInvalidPasswordException.CreateFmt('The password cannot be used: %s', [Failure.Message]);
      end;
    end;
  end;
  Result := TEncoding.UTF8.GetBytes(Prepared);
end;

class procedure TStandardSecurityHandler.GuardKeyLength(const Parameters: TEncryptionParameters);
begin
  const IsRevision234 = ((Parameters.Revision >= Revision2) and (Parameters.Revision <= Revision4));
  const IsValid = ((Parameters.KeyLengthInBytes >= 1) and (Parameters.KeyLengthInBytes <= MaxRc4KeyBytes));
  if IsRevision234 and (not IsValid) then
  begin
    raise EPdfParseException.CreateFmt('Invalid encryption key length of %d bytes', [Parameters.KeyLengthInBytes]);
  end;
end;

{ algorithms for revision 2 to 4 }

// Steps a to d of algorithm 3, the key to encrypt the user password with
class function TStandardSecurityHandler.ComputeRC4Key(const OwnerPassword: TBytes; const Revision, KeyLengthInBytes: Integer): TBytes;
begin
  const PaddedPassword = TruncateOrPad(OwnerPassword);
  var Digest := Md5Of(PaddedPassword);
  if (Revision = Revision3) or (Revision = Revision4) then
  begin
    for var Round := 0 to 49 do
    begin
      // This deviates from the specification: omitting the length keeps the file from opening in Adobe Reader with the
      // owner password when the key has 40 bits
      const KeyPart = Copy(Digest, 0, KeyLengthInBytes);
      Digest := Md5Of(KeyPart);
    end;
  end;
  Result := Copy(Digest, 0, KeyLengthInBytes);
end;

// Algorithm 7: the user password from the owner password
class function TStandardSecurityHandler.GetUserPassword234(const OwnerPassword, Owner: TBytes; const Revision, KeyLengthInBytes: Integer): TBytes;
begin
  const Rc4Key = ComputeRC4Key(OwnerPassword, Revision, KeyLengthInBytes);
  Result := nil;
  if Revision = Revision2 then
  begin
    Result := TRC4Cipher.Process(Rc4Key, Owner);
  end
  else if (Revision = Revision3) or (Revision = Revision4) then
  begin
    Result := Copy(Owner);
    for var Round := 19 downto 0 do
    begin
      const IterationKey = XorWithRound(Rc4Key, Round);
      Result := TRC4Cipher.Process(IterationKey, Result);
    end;
  end;
end;

// Algorithm 2: the encryption key from the password
class function TStandardSecurityHandler.ComputeEncryptedKeyRev234(const Password: TBytes; const Parameters: TEncryptionParameters): TBytes;
begin
  var Material := TruncateOrPad(Password) + Parameters.OwnerKey;
  for var Shift := 0 to FullPermissionsBytes - 1 do
  begin
    Material := Material + [Byte((Parameters.Permissions shr (Shift * BitsPerByte)) and $FF)];
  end;
  Material := Material + Parameters.DocumentId;

  // Revisions 4 and up: when the metadata is not encrypted, four bytes with the value $FF are added
  if (Parameters.Revision = Revision4) and (not Parameters.EncryptMetadata) then
  begin
    Material := Material + [$FF, $FF, $FF, $FF];
  end;

  var Digest := Md5Of(Material);
  if (Parameters.Revision = Revision3) or (Parameters.Revision = Revision4) then
  begin
    for var Round := 0 to 49 do
    begin
      const KeyPart = Copy(Digest, 0, Parameters.KeyLengthInBytes);
      Digest := Md5Of(KeyPart);
    end;
  end;
  Result := Copy(Digest, 0, Parameters.KeyLengthInBytes);
end;

// Algorithms 4 and 5: the /U value for a password
class function TStandardSecurityHandler.ComputeUserPassword(const Password: TBytes; const Parameters: TEncryptionParameters): TBytes;
begin
  const EncryptionKey = ComputeEncryptedKeyRev234(Password, Parameters);
  var Padding: TBytes;
  SetLength(Padding, Length(EncryptPadding));
  Move(EncryptPadding[0], Padding[0], Length(EncryptPadding));

  if Parameters.Revision = Revision2 then
  begin
    Exit(TRC4Cipher.Process(EncryptionKey, Padding));
  end;

  var Encrypted := Md5Of(Padding + Parameters.DocumentId);
  for var Round := 0 to 19 do
  begin
    const IterationKey = XorWithRound(EncryptionKey, Round);
    Encrypted := TRC4Cipher.Process(IterationKey, Encrypted);
  end;
  Result := Copy(Encrypted, 0, Md5Length) + Copy(Padding, 0, PaddingLength - Md5Length);
end;

class function TStandardSecurityHandler.IsUserPassword234(const Password: TBytes; const Parameters: TEncryptionParameters): Boolean;
begin
  const Computed = ComputeUserPassword(Password, Parameters);
  if Parameters.Revision = Revision2 then
  begin
    Exit(BytesEqual(Parameters.UserKey, Computed));
  end;

  // Only the first 16 bytes are compared
  const ExpectedStart = Copy(Parameters.UserKey, 0, Md5Length);
  const ComputedStart = Copy(Computed, 0, Md5Length);
  Result := BytesEqual(ExpectedStart, ComputedStart);
end;

class function TStandardSecurityHandler.IsOwnerPassword234(const OwnerPassword: TBytes; const Parameters: TEncryptionParameters): Boolean;
begin
  const UserPassword = GetUserPassword234(OwnerPassword, Parameters.OwnerKey, Parameters.Revision, Parameters.KeyLengthInBytes);
  Result := IsUserPassword234(UserPassword, Parameters);
end;

{ algorithms for revision 5 and 6 }

class function TStandardSecurityHandler.AdjustUserKey(const UserKey: TBytes): TBytes;
begin
  if UserKey = nil then
  begin
    Exit(nil);
  end;
  if Length(UserKey) < UserKeyLengthRevision56 then
  begin
    raise EPdfParseException.Create('Bad U length');
  end;
  Result := Copy(UserKey, 0, UserKeyLengthRevision56);
end;

// The hash of revision 5: SHA-256 over the password, the salt and the user key
class function TStandardSecurityHandler.ComputeSha256(const Input, Password, UserKey: TBytes): TBytes;
begin
  const AdjustedUserKey = AdjustUserKey(UserKey);
  Result := Sha2Of(Sha256Version, Input + Password + AdjustedUserKey);
end;

// Algorithm 2.A for the hash
class function TStandardSecurityHandler.ComputeHash2A(const Password, Salt, UserKey: TBytes): TBytes;
begin
  const AdjustedUserKey = AdjustUserKey(UserKey);
  const TruncatedPassword = Truncate127(Password);
  const Input = Concat(TruncatedPassword, Salt, AdjustedUserKey);
  Result := ComputeHash2B(Input, TruncatedPassword, AdjustedUserKey);
end;

// The password, K and the user key repeated 64 times
class function TStandardSecurityHandler.RepeatedHashInput(const Password, K, UserKey: TBytes): TBytes;
begin
  var RepeatedBlock := Password + K;
  if Length(UserKey) >= UserKeyLengthRevision56 then
  begin
    RepeatedBlock := RepeatedBlock + Copy(UserKey, 0, UserKeyLengthRevision56);
  end;

  SetLength(Result, Length(RepeatedBlock) * Hash2BFixedRounds);
  for var Repetition := 0 to Hash2BFixedRounds - 1 do
  begin
    Move(RepeatedBlock[0], Result[Repetition * Length(RepeatedBlock)], Length(RepeatedBlock));
  end;
end;

// One round of algorithm 2.B: K becomes the hash of the AES encryption of the repeated input. E is the encrypted input.
class function TStandardSecurityHandler.NextHash2BRound(const K: TBytes; const Password, UserKey: TBytes; out E: TBytes): TBytes;
begin
  const FirstHalf = Copy(K, 0, AesBlockLength);
  const SecondHalf = Copy(K, AesBlockLength, AesBlockLength);
  const Cipher = TAESCipher.Create(FirstHalf);
  try
    const Repeated = RepeatedHashInput(Password, K, UserKey);
    E := Cipher.EncryptCbcNoPadding(SecondHalf, Repeated);
  finally
    Cipher.Free;
  end;

  // The first 16 bytes of E as a big-endian number modulo 3. 256 is 1 modulo 3, so the sum of the bytes gives the same.
  var Remainder := 0;
  for var Position := 0 to AesBlockLength - 1 do
  begin
    Remainder := (Remainder + E[Position]) mod 3;
  end;
  Result := Sha2Of(Remainder, E);
end;

// Algorithm 2.B of ISO 32000-2
class function TStandardSecurityHandler.ComputeHash2B(const Input, Password, UserKey: TBytes): TBytes;
begin
  var K := Sha2Of(Sha256Version, Input);
  var E: TBytes;
  var Round := 0;
  repeat
    K := NextHash2BRound(K, Password, UserKey, E);
    Inc(Round);
  until ((Round >= Hash2BFixedRounds) and (E[High(E)] <= (Round - Hash2BRoundLimitOffset)));

  Result := Copy(K, 0, HashLength);
end;

class function TStandardSecurityHandler.IsUserPassword56(const Password: TBytes; const Parameters: TEncryptionParameters): Boolean;
begin
  const TruncatedPassword = Truncate127(Password);
  const UserHash = Copy(Parameters.UserKey, 0, HashLength);
  const ValidationSalt = Copy(Parameters.UserKey, HashLength, ValidationSaltLength);

  var Computed: TBytes;
  if Parameters.Revision = Revision5 then
  begin
    Computed := ComputeSha256(TruncatedPassword, ValidationSalt, nil);
  end
  else
  begin
    Computed := ComputeHash2A(TruncatedPassword, ValidationSalt, nil);
  end;
  Result := BytesEqual(Computed, UserHash);
end;

class function TStandardSecurityHandler.IsOwnerPassword56(const OwnerPassword: TBytes; const Parameters: TEncryptionParameters): Boolean;
begin
  if Length(Parameters.OwnerKey) < MinOwnerLengthRevision56 then
  begin
    // PDFBOX-5104
    raise EPdfParseException.Create('Owner password is too short');
  end;

  const TruncatedPassword = Truncate127(OwnerPassword);
  const OwnerHash = Copy(Parameters.OwnerKey, 0, HashLength);
  const ValidationSalt = Copy(Parameters.OwnerKey, HashLength, ValidationSaltLength);

  var Computed: TBytes;
  if Parameters.Revision = Revision5 then
  begin
    Computed := ComputeSha256(TruncatedPassword, ValidationSalt, Parameters.UserKey);
  end
  else
  begin
    Computed := ComputeHash2A(TruncatedPassword, ValidationSalt, Parameters.UserKey);
  end;
  Result := BytesEqual(Computed, OwnerHash);
end;

// Algorithm 2.A: the file encryption key from the /OE or /UE entry
function TStandardSecurityHandler.ComputeEncryptedKeyRev56(const Password: TBytes; const Parameters: TEncryptionParameters;
                                                           const EncryptedFileKey: TBytes; const IsOwner: Boolean): TBytes;
begin
  var KeySalt: TBytes;
  var Hash: TBytes;
  if IsOwner then
  begin
    KeySalt := Copy(Parameters.OwnerKey, KeySaltOffset, ValidationSaltLength);
    if Parameters.Revision = Revision5 then
    begin
      Hash := ComputeSha256(Password, KeySalt, Parameters.UserKey);
    end
    else
    begin
      Hash := ComputeHash2A(Password, KeySalt, Parameters.UserKey);
    end;
  end
  else
  begin
    KeySalt := Copy(Parameters.UserKey, KeySaltOffset, ValidationSaltLength);
    if Parameters.Revision = Revision5 then
    begin
      Hash := ComputeSha256(Password, KeySalt, nil);
    end
    else
    begin
      Hash := ComputeHash2A(Password, KeySalt, nil);
    end;
  end;

  var ZeroVector: TBytes;
  SetLength(ZeroVector, AesBlockLength);
  const Cipher = TAESCipher.Create(Hash);
  try
    Result := Cipher.DecryptCbc(ZeroVector, EncryptedFileKey, False);
  finally
    Cipher.Free;
  end;
end;

{ checking the password }

function TStandardSecurityHandler.IsOwnerPassword(const PasswordBytes: TBytes; const Parameters: TEncryptionParameters): Boolean;
begin
  case Parameters.Revision of
    Revision2, Revision3, Revision4 : Result := IsOwnerPassword234(PasswordBytes, Parameters);
    Revision5, Revision6            : Result := IsOwnerPassword56(PasswordBytes, Parameters);
  else
    raise EPdfParseException.CreateFmt(UnknownRevisionMessage, [Parameters.Revision]);
  end;
end;

function TStandardSecurityHandler.IsUserPassword(const PasswordBytes: TBytes; const Parameters: TEncryptionParameters): Boolean;
begin
  case Parameters.Revision of
    Revision2, Revision3, Revision4 : Result := IsUserPassword234(PasswordBytes, Parameters);
    Revision5, Revision6            : Result := IsUserPassword56(PasswordBytes, Parameters);
  else
    raise EPdfParseException.CreateFmt(UnknownRevisionMessage, [Parameters.Revision]);
  end;
end;

// EncryptionKeys is the /OE entry for the owner and the /UE entry for the user, used by revisions 5 and 6 only
function TStandardSecurityHandler.ComputeEncryptedKey(const Password: TBytes; const Parameters: TEncryptionParameters;
                                                      const EncryptionKeys: TBytes; const IsOwner: Boolean): TBytes;
begin
  const IsRevision56 = ((Parameters.Revision = Revision5) or (Parameters.Revision = Revision6));
  if IsRevision56 then
  begin
    Result := ComputeEncryptedKeyRev56(Password, Parameters, EncryptionKeys, IsOwner);
  end
  else
  begin
    Result := ComputeEncryptedKeyRev234(Password, Parameters);
  end;
end;

procedure TStandardSecurityHandler.SetAccessPermission(const Permissions: Integer; const IsOwner: Boolean);
begin
  if IsOwner then
  begin
    SetCurrentAccessPermission(TPdfAccessPermission.GetOwnerAccessPermission);
  end
  else
  begin
    const UserPermission = TPdfAccessPermission.Create(Permissions);
    UserPermission.SetReadOnly;
    SetCurrentAccessPermission(UserPermission);
  end;
end;

// Algorithm 13: validates /Perms. Relaxed to accommodate buggy encoders: a difference is logged.
procedure TStandardSecurityHandler.ValidatePerms(const Encryption: TPdfEncryption; const Permissions: Integer; const EncryptMetadata: Boolean);
begin
  var EncryptedPerms: TBytes;
  if not Encryption.TryGetPerms(EncryptedPerms) then
  begin
    raise EPdfParseException.Create('The /Perms entry of the encryption dictionary is missing');
  end;
  if (Length(EncryptedPerms) < PermsLength) or ((Length(EncryptedPerms) mod AesBlockLength) <> 0) then
  begin
    raise EPdfParseException.CreateFmt('The /Perms entry of the encryption dictionary has %d bytes', [Length(EncryptedPerms)]);
  end;

  // The 16 byte Perms string, decrypted with AES-256 in ECB mode and the file encryption key
  const Cipher = TAESCipher.Create(EncryptionKey);
  var Perms: TBytes;
  try
    Perms := Cipher.DecryptEcbNoPadding(EncryptedPerms);
  finally
    Cipher.Free;
  end;

  // Bytes 9 to 11 are the characters a, d, b
  const HasConstant = ((Perms[PermsConstantOffset] = Ord('a')) and (Perms[PermsConstantOffset + 1] = Ord('d')) and
                       (Perms[PermsConstantOffset + 2] = Ord('b')));
  if not HasConstant then
  begin
    Log.Warning('Verification of permissions failed (constant)');
  end;

  // Bytes 0 to 3, a little-endian integer, should match the value in the P key
  var PermsP: Cardinal := 0;
  for var Position := FullPermissionsBytes - 1 downto 0 do
  begin
    PermsP := (PermsP shl BitsPerByte) or Perms[Position];
  end;
  if Integer(PermsP) <> Permissions then
  begin
    Log.Warning('Verification of permissions failed (%.8X != %.8X)', [PermsP, Cardinal(Permissions)]);
  end;

  var ExpectedFlag := Ord('F');
  if EncryptMetadata then
  begin
    ExpectedFlag := Ord('T');
  end;
  if Perms[PermsMetadataOffset] <> ExpectedFlag then
  begin
    Log.Warning('Verification of permissions failed (EncryptMetadata)');
  end;
end;

{ reading the encryption dictionary }

function TStandardSecurityHandler.ReadKeyLengthInBytes(const Encryption: TPdfEncryption): Integer;
begin
  if Encryption.GetVersion = Version1 then
  begin
    Exit(Version1KeyBytes);
  end;
  Result := Encryption.GetLength div BitsPerByte;
end;

// For V 4 and 5 the method of the standard crypt filter says whether AES is used and how long the key is
procedure TStandardSecurityHandler.ApplyCryptFilterMethod(const Encryption: TPdfEncryption; var KeyLengthInBytes: Integer);
begin
  var CryptFilter: TPdfCryptFilterDictionary;
  if not Encryption.TryGetStdCryptFilterDictionary(CryptFilter) then
  begin
    Exit;
  end;

  try
    var Method: string;
    if not CryptFilter.TryGetCryptFilterMethod(Method) then
    begin
      Exit;
    end;

    const IsAes128 = (Method = TCosNames.AESV2);
    const IsAes256 = (Method = TCosNames.AESV3);
    if not (IsAes128 or IsAes256) then
    begin
      Exit;
    end;

    const MethodBytes = Aes128Bytes * (1 + Ord(IsAes256));
    KeyLengthInBytes := MethodBytes;
    UseAES := True;
    if Encryption.Dictionary.ContainsKey(TCosNames.Length) then
    begin
      // PDFBOX-5345
      const NewLength = Encryption.GetLength div BitsPerByte;
      if NewLength < KeyLengthInBytes then
      begin
        Log.Warning('Using %d bytes key length instead of %d in AESV%d encryption?!', [NewLength, KeyLengthInBytes, 2 + Ord(IsAes256)]);
        KeyLengthInBytes := NewLength;
      end;
    end;
  finally
    CryptFilter.Free;
  end;
end;

function TStandardSecurityHandler.ReadParameters(const Encryption: TPdfEncryption; const DocumentId: TBytes; const KeyLengthInBytes: Integer): TEncryptionParameters;
begin
  Result.Revision := Encryption.GetRevision;
  Result.Permissions := Encryption.GetPermissions;
  Result.DocumentId := DocumentId;
  Result.KeyLengthInBytes := KeyLengthInBytes;
  Result.EncryptMetadata := Encryption.IsEncryptMetaData;
  if not Encryption.TryGetUserKey(Result.UserKey) then
  begin
    raise EPdfParseException.Create('The /U entry of the encryption dictionary is missing');
  end;
  if not Encryption.TryGetOwnerKey(Result.OwnerKey) then
  begin
    raise EPdfParseException.Create('The /O entry of the encryption dictionary is missing');
  end;
end;

procedure TStandardSecurityHandler.PrepareForDecryption(const Encryption: TPdfEncryption; const DocumentId: TBytes; const Password: string);
begin
  const EncryptionVersion = Encryption.GetVersion;
  // The filter names are only used with security version 4 and 5
  if EncryptionVersion >= Version4 then
  begin
    StreamFilterName := Encryption.GetStreamFilterName;
    StringFilterName := Encryption.GetStringFilterName;
  end;
  DecryptMetadata := Encryption.IsEncryptMetaData;

  var KeyLengthInBytes := ReadKeyLengthInBytes(Encryption);
  if (EncryptionVersion = Version4) or (EncryptionVersion = Version5) then
  begin
    ApplyCryptFilterMethod(Encryption, KeyLengthInBytes);
  end;

  const Parameters = ReadParameters(Encryption, DocumentId, KeyLengthInBytes);
  GuardKeyLength(Parameters);

  var UserEncryptionKey: TBytes;
  var OwnerEncryptionKey: TBytes;
  const IsRevision56 = ((Parameters.Revision = Revision5) or (Parameters.Revision = Revision6));
  if IsRevision56 then
  begin
    Encryption.TryGetUserEncryptionKey(UserEncryptionKey);
    Encryption.TryGetOwnerEncryptionKey(OwnerEncryptionKey);
  end;

  var PasswordBytes := PasswordToBytes(Password, Parameters.Revision);
  var IsOwner: Boolean;
  if IsOwnerPassword(PasswordBytes, Parameters) then
  begin
    IsOwner := True;
    if not IsRevision56 then
    begin
      PasswordBytes := GetUserPassword234(PasswordBytes, Parameters.OwnerKey, Parameters.Revision, Parameters.KeyLengthInBytes);
    end;
  end
  else if IsUserPassword(PasswordBytes, Parameters) then
  begin
    IsOwner := False;
  end
  else
  begin
    raise EPdfInvalidPasswordException.Create('Cannot decrypt PDF, the password is incorrect');
  end;
  SetAccessPermission(Parameters.Permissions, IsOwner);

  var EncryptionKeys: TBytes;
  if IsOwner then
  begin
    EncryptionKeys := OwnerEncryptionKey;
  end
  else
  begin
    EncryptionKeys := UserEncryptionKey;
  end;

  const MissingKeys = (IsRevision56 and (EncryptionKeys = nil));
  if MissingKeys then
  begin
    raise EPdfParseException.Create('The /OE or /UE entry of the encryption dictionary is missing');
  end;

  var FileKey := ComputeEncryptedKey(PasswordBytes, Parameters, EncryptionKeys, IsOwner);
  if (Parameters.Revision = Revision4) and (Length(FileKey) < RevisionFourMinimumKeyBytes) then
  begin
    Log.Info('PDFBOX-5955: padding RC4 key to length 16');
    SetLength(FileKey, RevisionFourMinimumKeyBytes);
  end;
  EncryptionKey := FileKey;

  if IsRevision56 then
  begin
    ValidatePerms(Encryption, Parameters.Permissions, Parameters.EncryptMetadata);
  end;
end;

end.
