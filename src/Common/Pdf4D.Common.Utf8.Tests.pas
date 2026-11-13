// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
unit Pdf4D.Common.Utf8.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPdfUtf8Tests = class
  public
    [Test]
    procedure TestStrictAcceptsWellFormedInput;

    [Test]
    procedure TestStrictRejectsMalformedInput;

    [Test]
    procedure TestLenientReplacesMalformedBytes;

    [Test]
    procedure TestLenientStartBeyondEnd;

    [Test]
    procedure TestUtf16BigAndLittleEndian;
  end;

implementation

uses
  System.SysUtils,
  Pdf4D.Common.Utf8;

{ TPdfUtf8Tests }

procedure TPdfUtf8Tests.TestStrictAcceptsWellFormedInput;
begin
  var Text: string;

  Assert.IsTrue(TPdfUtf8.TryDecodeStrict(nil, Text));
  Assert.AreEqual('', Text);

  Assert.IsTrue(TPdfUtf8.TryDecodeStrict(TBytes.Create($7F, $C2, $80, $DF, $BF, $E0, $A0, $80, $ED, $9F, $BF, $EF, $BF, $BF), Text));
  Assert.AreEqual(#$007F#$0080#$07FF#$0800#$D7FF#$FFFF, Text);

  Assert.IsTrue(TPdfUtf8.TryDecodeStrict(TBytes.Create($F0, $90, $80, $80, $F4, $8F, $BF, $BF), Text));
  Assert.AreEqual(#$D800#$DC00#$DBFF#$DFFF, Text);
end;

procedure TPdfUtf8Tests.TestStrictRejectsMalformedInput;
begin
  var Text: string;

  // Lone continuation byte, invalid lead bytes
  Assert.IsFalse(TPdfUtf8.TryDecodeStrict(TBytes.Create($80), Text));
  Assert.IsFalse(TPdfUtf8.TryDecodeStrict(TBytes.Create($C0, $80), Text));
  Assert.IsFalse(TPdfUtf8.TryDecodeStrict(TBytes.Create($C1, $BF), Text));
  Assert.IsFalse(TPdfUtf8.TryDecodeStrict(TBytes.Create($F5, $80, $80, $80), Text));
  Assert.IsFalse(TPdfUtf8.TryDecodeStrict(TBytes.Create($FF), Text));
  // Overlong three and four byte forms
  Assert.IsFalse(TPdfUtf8.TryDecodeStrict(TBytes.Create($E0, $80, $80), Text));
  Assert.IsFalse(TPdfUtf8.TryDecodeStrict(TBytes.Create($F0, $80, $80, $80), Text));
  // Surrogates and values above U+10FFFF
  Assert.IsFalse(TPdfUtf8.TryDecodeStrict(TBytes.Create($ED, $A0, $80), Text));
  Assert.IsFalse(TPdfUtf8.TryDecodeStrict(TBytes.Create($F4, $90, $80, $80), Text));
  // Truncated and badly continued sequences
  Assert.IsFalse(TPdfUtf8.TryDecodeStrict(TBytes.Create($E2, $82), Text));
  Assert.IsFalse(TPdfUtf8.TryDecodeStrict(TBytes.Create($C3), Text));
  Assert.IsFalse(TPdfUtf8.TryDecodeStrict(TBytes.Create($E2, $82, $41), Text));
  Assert.AreEqual('', Text);
end;

procedure TPdfUtf8Tests.TestLenientReplacesMalformedBytes;
begin
  Assert.AreEqual('A'#$FFFD'B', TPdfUtf8.DecodeLenient(TBytes.Create($41, $80, $42), 0));
  Assert.AreEqual(#$FFFD#$FFFD, TPdfUtf8.DecodeLenient(TBytes.Create($E2, $82), 0));
  Assert.AreEqual(#$00E9, TPdfUtf8.DecodeLenient(TBytes.Create($EF, $BB, $BF, $C3, $A9), 3));
end;

procedure TPdfUtf8Tests.TestLenientStartBeyondEnd;
begin
  Assert.AreEqual('', TPdfUtf8.DecodeLenient(TBytes.Create($41), 1));
  Assert.AreEqual('', TPdfUtf8.DecodeLenient(TBytes.Create($41), 9));
  Assert.AreEqual('', TPdfUtf8.DecodeLenient(TBytes.Create($41), -1));
end;

procedure TPdfUtf8Tests.TestUtf16BigAndLittleEndian;
begin
  Assert.AreEqual('A'#$00E9, TPdfUtf8.DecodeUtf16(TBytes.Create($00, $41, $00, $E9), 0, True));
  Assert.AreEqual('A'#$00E9, TPdfUtf8.DecodeUtf16(TBytes.Create($41, $00, $E9, $00), 0, False));
  Assert.AreEqual('A', TPdfUtf8.DecodeUtf16(TBytes.Create($FF, $00, $41), 1, True));
  Assert.AreEqual('', TPdfUtf8.DecodeUtf16(nil, 0, True));
end;

end.
