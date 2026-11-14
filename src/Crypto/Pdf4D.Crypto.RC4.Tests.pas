// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Crypto.RC4.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRC4CipherTests = class
  public
    [Test]
    procedure TestRC4KnownVector;

    [Test]
    procedure TestRC4IsItsOwnInverse;

    [Test]
    procedure TestRC4EmptyDataGivesEmptyResult;

    [Test]
    procedure TestRC4KeyOfOneByteIsAccepted;

    [Test]
    procedure TestRC4KeyOf256BytesIsAccepted;

    [Test]
    procedure TestRC4EmptyKeyRaises;

    [Test]
    procedure TestRC4KeyLongerThan256BytesRaises;
  end;

implementation

uses
  System.SysUtils,
  Pdf4D.Filter.Tests.Support,
  Pdf4D.Crypto.RC4;

{ TRC4CipherTests }

procedure TRC4CipherTests.TestRC4KnownVector;
begin
  const Key = TFilterTestSupport.AsciiBytes('Key');
  const Plaintext = TFilterTestSupport.AsciiBytes('Plaintext');

  const Actual = TRC4Cipher.Process(Key, Plaintext);

  Assert.AreEqual('BBF316E8D940AF0AD3', TFilterTestSupport.ToHex(Actual));
end;

procedure TRC4CipherTests.TestRC4IsItsOwnInverse;
begin
  const Key: TBytes = [1, 2, 3, 4, 5];
  const Plaintext = TFilterTestSupport.AsciiBytes('Attack at dawn');

  const Restored = TRC4Cipher.Process(Key, TRC4Cipher.Process(Key, Plaintext));

  Assert.AreEqual('Attack at dawn', TFilterTestSupport.AsciiString(Restored));
end;

procedure TRC4CipherTests.TestRC4EmptyDataGivesEmptyResult;
begin
  const Key: TBytes = [1, 2, 3];

  const Actual = TRC4Cipher.Process(Key, nil);

  Assert.AreEqual<Integer>(0, Length(Actual));
end;

procedure TRC4CipherTests.TestRC4KeyOfOneByteIsAccepted;
begin
  const Key: TBytes = [$42];
  const Data: TBytes = [0, 0, 0, 0];

  Assert.AreEqual<Integer>(4, Length(TRC4Cipher.Process(Key, Data)));
end;

procedure TRC4CipherTests.TestRC4KeyOf256BytesIsAccepted;
begin
  var Key: TBytes;
  SetLength(Key, 256);
  const Data: TBytes = [0, 0, 0, 0];

  Assert.AreEqual<Integer>(4, Length(TRC4Cipher.Process(Key, Data)));
end;

procedure TRC4CipherTests.TestRC4EmptyKeyRaises;
begin
  const Data: TBytes = [1, 2, 3];

  Assert.WillRaise(
    procedure
    begin
      TRC4Cipher.Process(nil, Data);
    end,
    EArgumentException);
end;

procedure TRC4CipherTests.TestRC4KeyLongerThan256BytesRaises;
begin
  var Key: TBytes;
  SetLength(Key, 257);
  const Data: TBytes = [1, 2, 3];

  Assert.WillRaise(
    procedure
    begin
      TRC4Cipher.Process(Key, Data);
    end,
    EArgumentException);
end;

end.
