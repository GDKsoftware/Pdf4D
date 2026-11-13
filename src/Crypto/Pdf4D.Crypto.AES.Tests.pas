unit Pdf4D.Crypto.AES.Tests;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework;

type
  [TestFixture]
  TAESCipherTests = class
  private
    class function FromHex(const Hex: string): TBytes; static;
    class function ToHex(const Data: TBytes): string; static;
    class function RandomBytes(const Count: Integer): TBytes; static;
    class function EncryptWithDec(const Key, IV, Data: TBytes): TBytes; static;
    class function DecryptWithDec(const Key, IV, Data: TBytes): TBytes; static;
    class function PaddedBlock(const Tail: TBytes): TBytes; static;
  public
    [Test]
    [TestCase('C.1 AES-128', '000102030405060708090a0b0c0d0e0f,00112233445566778899aabbccddeeff,69c4e0d86a7b0430d8cdb78070b4c55a')]
    [TestCase('C.2 AES-192', '000102030405060708090a0b0c0d0e0f1011121314151617,00112233445566778899aabbccddeeff,dda97ca4864cdfe06eaf70a0ec0d7191')]
    [TestCase('C.3 AES-256', '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f,00112233445566778899aabbccddeeff,8ea2b7ca516745bfeafc49904b496089')]
    procedure TestAesFips197Vectors(const KeyHex, PlaintextHex, CiphertextHex: string);

    [Test]
    procedure TestAesCbcNistSp800_38a;

    [Test]
    procedure TestAesCbcNistSp800_38aDecrypt256;

    [Test]
    procedure TestAesCbcPaddingRemoved;

    [Test]
    procedure TestAesCbcPaddingOfAWholeBlockIsRemoved;

    [Test]
    [TestCase('Zero padding byte', '00')]
    [TestCase('Padding byte above 16', '11')]
    [TestCase('Inconsistent padding', '0302')]
    procedure TestAesCbcInvalidPaddingIsKeptAndReported(const TailHex: string);

    [Test]
    procedure TestAesCbcPartialLastBlockIsDroppedAndReported;

    [Test]
    procedure TestAesCbcEmptyDataGivesEmptyResult;

    [Test]
    procedure TestAesCbcWithoutPaddingRemovalKeepsAllBytes;

    [Test]
    procedure TestAesEcbNoPaddingRoundTrip;

    [Test]
    procedure TestAesEcbNoPaddingRejectsPartialBlock;

    [Test]
    procedure TestAesCbcNoPaddingRejectsPartialBlock;

    [Test]
    procedure TestAesCbcRejectsWrongIvLength;

    [Test]
    procedure TestAesBlockRejectsWrongLength;

    [Test]
    [TestCase('0 bytes', '0')]
    [TestCase('15 bytes', '15')]
    [TestCase('17 bytes', '17')]
    [TestCase('20 bytes', '20')]
    [TestCase('33 bytes', '33')]
    procedure TestAesRejectsWrongKeyLength(const KeyLength: Integer);

    [Test]
    procedure TestMatchesDecForRandomInputs;
  end;

implementation

uses
  Pdf4D.Crypto.AES,
  DECCipherBase,
  DECCiphers;

const
  Sp800_38aKey128 = '2b7e151628aed2a6abf7158809cf4f3c';
  Sp800_38aKey256 = '603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4';
  Sp800_38aIv = '000102030405060708090a0b0c0d0e0f';
  Sp800_38aPlaintext = '6bc1bee22e409f96e93d7e117393172a' +
                       'ae2d8a571e03ac9c9eb76fac45af8e51' +
                       '30c81c46a35ce411e5fbc1191a0a52ef' +
                       'f69f2445df4f9b17ad2b417be66c3710';
  Sp800_38aCbcAes128Ciphertext = '7649abac8119b246cee98e9b12e9197d' +
                                 '5086cb9b507219ee95db113a917678b2' +
                                 '73bed6b8e3c1743b7116e69e22229516' +
                                 '3ff1caa1681fac09120eca307586e1a7';
  Sp800_38aCbcAes256Ciphertext = 'f58c4c04d6e5f1ba779eabfb5f7bfbd6' +
                                 '9cfc4e967edb808d679f777bc6702c7d' +
                                 '39f23369a9d9bacfa530e26304231461' +
                                 'b2eb05e2c39be9fcda6c19078c6a9d1b';
  RandomSeed = 42;
  RandomCaseCount = 200;
  BlockSize = 16;

{ TAESCipherTests }

class function TAESCipherTests.FromHex(const Hex: string): TBytes;
begin
  SetLength(Result, Length(Hex) div 2);
  for var Index := 0 to High(Result) do
  begin
    const Pair = Copy(Hex, (Index * 2) + 1, 2);
    Result[Index] := StrToInt('$' + Pair);
  end;
end;

class function TAESCipherTests.ToHex(const Data: TBytes): string;
begin
  Result := '';
  for var Value in Data do
  begin
    Result := Result + LowerCase(IntToHex(Value, 2));
  end;
end;

class function TAESCipherTests.RandomBytes(const Count: Integer): TBytes;
begin
  SetLength(Result, Count);
  for var Index := 0 to Count - 1 do
  begin
    Result[Index] := Random(256);
  end;
end;

// DEC's EncodeBytes and DecodeBytes work in place on the array they are given, so they get a copy.
class function TAESCipherTests.EncryptWithDec(const Key, IV, Data: TBytes): TBytes;
begin
  const Cipher = TCipher_AES.Create;
  try
    Cipher.Mode := cmCBCx;
    Cipher.Init(Key, IV);
    Result := Cipher.EncodeBytes(Copy(Data));
  finally
    Cipher.Free;
  end;
end;

class function TAESCipherTests.DecryptWithDec(const Key, IV, Data: TBytes): TBytes;
begin
  const Cipher = TCipher_AES.Create;
  try
    Cipher.Mode := cmCBCx;
    Cipher.Init(Key, IV);
    Result := Cipher.DecodeBytes(Copy(Data));
  finally
    Cipher.Free;
  end;
end;

class function TAESCipherTests.PaddedBlock(const Tail: TBytes): TBytes;
begin
  SetLength(Result, BlockSize);
  for var Index := 0 to High(Result) do
  begin
    Result[Index] := $AA;
  end;
  for var Index := 0 to High(Tail) do
  begin
    Result[BlockSize - Length(Tail) + Index] := Tail[Index];
  end;
end;

procedure TAESCipherTests.TestAesFips197Vectors(const KeyHex, PlaintextHex, CiphertextHex: string);
begin
  const Cipher = TAESCipher.Create(FromHex(KeyHex));
  try
    Assert.AreEqual(CiphertextHex, ToHex(Cipher.EncryptBlock(FromHex(PlaintextHex))));
    Assert.AreEqual(PlaintextHex, ToHex(Cipher.DecryptBlock(FromHex(CiphertextHex))));
  finally
    Cipher.Free;
  end;
end;

procedure TAESCipherTests.TestAesCbcNistSp800_38a;
begin
  const Cipher = TAESCipher.Create(FromHex(Sp800_38aKey128));
  try
    const Actual = Cipher.EncryptCbcNoPadding(FromHex(Sp800_38aIv), FromHex(Sp800_38aPlaintext));

    Assert.AreEqual(Sp800_38aCbcAes128Ciphertext, ToHex(Actual));
  finally
    Cipher.Free;
  end;
end;

procedure TAESCipherTests.TestAesCbcNistSp800_38aDecrypt256;
begin
  const Cipher = TAESCipher.Create(FromHex(Sp800_38aKey256));
  try
    const Actual = Cipher.DecryptCbc(FromHex(Sp800_38aIv), FromHex(Sp800_38aCbcAes256Ciphertext), False);

    Assert.AreEqual(Sp800_38aPlaintext, ToHex(Actual));
  finally
    Cipher.Free;
  end;
end;

procedure TAESCipherTests.TestAesCbcPaddingRemoved;
begin
  // 5 bytes of data followed by 11 bytes of PKCS#7 padding (value 11)
  const Padded = FromHex('0102030405' + '0b0b0b0b0b0b0b0b0b0b0b');
  const Iv = FromHex(Sp800_38aIv);
  const Cipher = TAESCipher.Create(FromHex(Sp800_38aKey128));
  try
    const Encrypted = Cipher.EncryptCbcNoPadding(Iv, Padded);

    var WasLenient: Boolean;
    const Actual = Cipher.DecryptCbc(Iv, Encrypted, True, WasLenient);

    Assert.AreEqual('0102030405', ToHex(Actual));
    Assert.IsFalse(WasLenient);
  finally
    Cipher.Free;
  end;
end;

procedure TAESCipherTests.TestAesCbcPaddingOfAWholeBlockIsRemoved;
begin
  const Block = '6bc1bee22e409f96e93d7e117393172a';
  const Padded = FromHex(Block + '10101010101010101010101010101010');
  const Iv = FromHex(Sp800_38aIv);
  const Cipher = TAESCipher.Create(FromHex(Sp800_38aKey128));
  try
    const Encrypted = Cipher.EncryptCbcNoPadding(Iv, Padded);

    var WasLenient: Boolean;
    const Actual = Cipher.DecryptCbc(Iv, Encrypted, True, WasLenient);

    Assert.AreEqual(Block, ToHex(Actual));
    Assert.IsFalse(WasLenient);
  finally
    Cipher.Free;
  end;
end;

procedure TAESCipherTests.TestAesCbcInvalidPaddingIsKeptAndReported(const TailHex: string);
begin
  const Padded = PaddedBlock(FromHex(TailHex));
  const Iv = FromHex(Sp800_38aIv);
  const Cipher = TAESCipher.Create(FromHex(Sp800_38aKey128));
  try
    const Encrypted = Cipher.EncryptCbcNoPadding(Iv, Padded);

    var WasLenient: Boolean;
    const Actual = Cipher.DecryptCbc(Iv, Encrypted, True, WasLenient);

    Assert.AreEqual(ToHex(Padded), ToHex(Actual));
    Assert.IsTrue(WasLenient);
  finally
    Cipher.Free;
  end;
end;

procedure TAESCipherTests.TestAesCbcPartialLastBlockIsDroppedAndReported;
begin
  const Iv = FromHex(Sp800_38aIv);
  const Cipher = TAESCipher.Create(FromHex(Sp800_38aKey128));
  try
    const Encrypted = Cipher.EncryptCbcNoPadding(Iv, FromHex(Sp800_38aPlaintext));
    const Truncated = Copy(Encrypted, 0, 35);

    var WasLenient: Boolean;
    const Actual = Cipher.DecryptCbc(Iv, Truncated, False, WasLenient);

    Assert.AreEqual(Copy(Sp800_38aPlaintext, 1, 64), ToHex(Actual));
    Assert.IsTrue(WasLenient);
  finally
    Cipher.Free;
  end;
end;

procedure TAESCipherTests.TestAesCbcEmptyDataGivesEmptyResult;
begin
  const Cipher = TAESCipher.Create(FromHex(Sp800_38aKey128));
  try
    var WasLenient: Boolean;
    const Actual = Cipher.DecryptCbc(FromHex(Sp800_38aIv), nil, True, WasLenient);

    Assert.AreEqual<Integer>(0, Length(Actual));
    Assert.IsFalse(WasLenient);
  finally
    Cipher.Free;
  end;
end;

procedure TAESCipherTests.TestAesCbcWithoutPaddingRemovalKeepsAllBytes;
begin
  const PaddedHex = '0102030405' + '0b0b0b0b0b0b0b0b0b0b0b';
  const Iv = FromHex(Sp800_38aIv);
  const Cipher = TAESCipher.Create(FromHex(Sp800_38aKey128));
  try
    const Encrypted = Cipher.EncryptCbcNoPadding(Iv, FromHex(PaddedHex));

    var WasLenient: Boolean;
    const Actual = Cipher.DecryptCbc(Iv, Encrypted, False, WasLenient);

    Assert.AreEqual(PaddedHex, ToHex(Actual));
    Assert.IsFalse(WasLenient);
  finally
    Cipher.Free;
  end;
end;

procedure TAESCipherTests.TestAesEcbNoPaddingRoundTrip;
begin
  const Cipher = TAESCipher.Create(FromHex(Sp800_38aKey256));
  try
    const Plaintext = FromHex(Sp800_38aPlaintext);
    var Encrypted: TBytes;
    for var BlockIndex := 0 to 3 do
    begin
      Encrypted := Encrypted + Cipher.EncryptBlock(Copy(Plaintext, BlockIndex * BlockSize, BlockSize));
    end;

    Assert.AreEqual(Sp800_38aPlaintext, ToHex(Cipher.DecryptEcbNoPadding(Encrypted)));
  finally
    Cipher.Free;
  end;
end;

procedure TAESCipherTests.TestAesEcbNoPaddingRejectsPartialBlock;
begin
  const Cipher = TAESCipher.Create(FromHex(Sp800_38aKey128));
  try
    const Partial = FromHex('000102');

    Assert.WillRaise(
      procedure
      begin
        Cipher.DecryptEcbNoPadding(Partial);
      end,
      EArgumentException);
  finally
    Cipher.Free;
  end;
end;

procedure TAESCipherTests.TestAesCbcNoPaddingRejectsPartialBlock;
begin
  const Cipher = TAESCipher.Create(FromHex(Sp800_38aKey128));
  try
    const Iv = FromHex(Sp800_38aIv);
    const Partial = FromHex('000102');

    Assert.WillRaise(
      procedure
      begin
        Cipher.EncryptCbcNoPadding(Iv, Partial);
      end,
      EArgumentException);
  finally
    Cipher.Free;
  end;
end;

procedure TAESCipherTests.TestAesCbcRejectsWrongIvLength;
begin
  const Cipher = TAESCipher.Create(FromHex(Sp800_38aKey128));
  try
    const ShortIv = FromHex('0001');
    const Data = FromHex(Sp800_38aPlaintext);

    Assert.WillRaise(
      procedure
      begin
        Cipher.DecryptCbc(ShortIv, Data, False);
      end,
      EArgumentException);
  finally
    Cipher.Free;
  end;
end;

procedure TAESCipherTests.TestAesBlockRejectsWrongLength;
begin
  const Cipher = TAESCipher.Create(FromHex(Sp800_38aKey128));
  try
    const Partial = FromHex('000102');

    Assert.WillRaise(
      procedure
      begin
        Cipher.EncryptBlock(Partial);
      end,
      EArgumentException);
    Assert.WillRaise(
      procedure
      begin
        Cipher.DecryptBlock(Partial);
      end,
      EArgumentException);
  finally
    Cipher.Free;
  end;
end;

procedure TAESCipherTests.TestAesRejectsWrongKeyLength(const KeyLength: Integer);
begin
  var Key: TBytes;
  SetLength(Key, KeyLength);

  Assert.WillRaise(
    procedure
    begin
      TAESCipher.Create(Key).Free;
    end,
    EArgumentException);
end;

procedure TAESCipherTests.TestMatchesDecForRandomInputs;
begin
  RandSeed := RandomSeed;
  for var CaseIndex := 1 to RandomCaseCount do
  begin
    const KeyLength = 16 + (16 * Random(2));
    const Key = RandomBytes(KeyLength);
    const Iv = RandomBytes(BlockSize);
    const Plaintext = RandomBytes(BlockSize * (1 + Random(8)));

    const Cipher = TAESCipher.Create(Key);
    try
      const Ours = Cipher.EncryptCbcNoPadding(Iv, Plaintext);

      Assert.AreEqual(ToHex(EncryptWithDec(Key, Iv, Plaintext)), ToHex(Ours), Format('Encrypt, case %d', [CaseIndex]));
      Assert.AreEqual(ToHex(DecryptWithDec(Key, Iv, Ours)), ToHex(Cipher.DecryptCbc(Iv, Ours, False)), Format('Decrypt, case %d', [CaseIndex]));
    finally
      Cipher.Free;
    end;
  end;
end;

end.
