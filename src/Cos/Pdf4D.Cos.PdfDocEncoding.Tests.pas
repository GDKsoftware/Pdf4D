// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Cos.PdfDocEncoding.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPdfDocEncodingTests = class
  public
    [Test]
    procedure TestPdfDocEncodingSpecials;

    [Test]
    procedure TestAsciiAndLatin1PassThrough;

    [Test]
    procedure TestUndefinedCodes;

    [Test]
    procedure TestDecodeMatchesCodeToUnicode;

    [Test]
    procedure TestDecodeEmpty;
  end;

implementation

uses
  System.SysUtils,
  Pdf4D.Cos.PdfDocEncoding;

{ TPdfDocEncodingTests }

procedure TPdfDocEncodingTests.TestPdfDocEncodingSpecials;
begin
  var Value: Char;

  Assert.IsTrue(TPdfDocEncoding.CodeToUnicode($18, Value));
  Assert.AreEqual(#$02D8, Value);

  Assert.IsTrue(TPdfDocEncoding.CodeToUnicode($80, Value));
  Assert.AreEqual(#$2022, Value);

  Assert.IsTrue(TPdfDocEncoding.CodeToUnicode($A0, Value));
  Assert.AreEqual(#$20AC, Value);

  Assert.IsTrue(TPdfDocEncoding.CodeToUnicode($9E, Value));
  Assert.AreEqual(#$017E, Value);
end;

procedure TPdfDocEncodingTests.TestAsciiAndLatin1PassThrough;
begin
  Assert.AreEqual('Hello', TPdfDocEncoding.Decode(TBytes.Create($48, $65, $6C, $6C, $6F)));
  Assert.AreEqual(#$00E9#$00FF#$00A1, TPdfDocEncoding.Decode(TBytes.Create($E9, $FF, $A1)));
  Assert.AreEqual(#$0009#$0017, TPdfDocEncoding.Decode(TBytes.Create($09, $17)));
end;

procedure TPdfDocEncodingTests.TestUndefinedCodes;
begin
  var Value: Char;

  Assert.IsFalse(TPdfDocEncoding.CodeToUnicode($7F, Value));
  Assert.AreEqual(#$FFFD, Value);

  Assert.IsFalse(TPdfDocEncoding.CodeToUnicode($9F, Value));
  Assert.AreEqual(#$FFFD, Value);

  Assert.IsFalse(TPdfDocEncoding.CodeToUnicode($AD, Value));
  Assert.AreEqual(#$FFFD, Value);

  // PDFBox decodes the codes $7F and $9F to U+FFFD and $AD to a zero character
  Assert.AreEqual(#$FFFD#$FFFD#0, TPdfDocEncoding.Decode(TBytes.Create($7F, $9F, $AD)));
end;

procedure TPdfDocEncodingTests.TestDecodeMatchesCodeToUnicode;
begin
  for var Code := 0 to 255 do
  begin
    var Value: Char;
    if TPdfDocEncoding.CodeToUnicode(Byte(Code), Value) then
    begin
      Assert.AreEqual(Value, TPdfDocEncoding.Decode(TBytes.Create(Byte(Code)))[1], Format('Code %d', [Code]));
    end;
  end;
end;

procedure TPdfDocEncodingTests.TestDecodeEmpty;
begin
  Assert.AreEqual('', TPdfDocEncoding.Decode(nil));
end;

end.
