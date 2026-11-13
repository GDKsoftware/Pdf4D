// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
unit Pdf4D.Filter.ASCII85.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TASCII85FilterTests = class
  private
    function Decoded(const Text: string): string;

  public
    [Test]
    procedure TestASCII85WithTerminatorAndWhitespace;

    [Test]
    procedure TestASCII85BriefVectorGivesFullLastGroup;

    [Test]
    procedure TestASCII85ZeroGroup;

    [Test]
    procedure TestASCII85WithoutTerminator;

    [Test]
    procedure TestASCII85IncompleteGroupAtEndIsDropped;

    [Test]
    procedure TestASCII85EmptyData;

    [Test]
    procedure TestASCII85InvalidDataRaises;
  end;

implementation

uses
  System.SysUtils,
  Pdf4D.Common.Defines,
  Pdf4D.Filter.Tests.Support;

{ TASCII85FilterTests }

function TASCII85FilterTests.Decoded(const Text: string): string;
begin
  Result := TFilterTestSupport.AsciiString(TFilterTestSupport.Decode('ASCII85Decode', TFilterTestSupport.AsciiBytes(Text)));
end;

procedure TASCII85FilterTests.TestASCII85WithTerminatorAndWhitespace;
begin
  Assert.AreEqual('Hello World', Decoded('87cURD]i,"Ebo7~>'));
  Assert.AreEqual('Hello World', Decoded('87cUR D]i,"' + #13#10 + 'Ebo7 ~>'));
end;

// The vector of the task has a digit more than the encoding of 'Hello World'. A full last group gives four bytes.
procedure TASCII85FilterTests.TestASCII85BriefVectorGivesFullLastGroup;
begin
  const Result = Decoded('87cURD]i,"Ebo80~>');

  Assert.AreEqual('Hello World', Copy(Result, 1, 11));
  Assert.AreEqual<Integer>(12, Length(Result));
end;

procedure TASCII85FilterTests.TestASCII85ZeroGroup;
begin
  Assert.AreEqual<Integer>(4, Length(Decoded('z~>')));
  Assert.AreEqual(#0#0#0#0, Decoded('z~>'));
end;

procedure TASCII85FilterTests.TestASCII85WithoutTerminator;
begin
  Assert.AreEqual('Hell', Decoded('87cUR'));
end;

procedure TASCII85FilterTests.TestASCII85IncompleteGroupAtEndIsDropped;
begin
  Assert.AreEqual('Hell', Decoded('87cURD]i'));
end;

procedure TASCII85FilterTests.TestASCII85EmptyData;
begin
  Assert.AreEqual('', Decoded('~>'));
  Assert.AreEqual('', Decoded(''));
  Assert.AreEqual('', Decoded('A~>'));
end;

procedure TASCII85FilterTests.TestASCII85InvalidDataRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      Decoded('87cU' + #9 + 'R~>');
    end,
    EPdfParseException);
end;

end.
