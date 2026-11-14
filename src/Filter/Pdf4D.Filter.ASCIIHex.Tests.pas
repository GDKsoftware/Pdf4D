// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Filter.ASCIIHex.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TASCIIHexFilterTests = class
  private
    function Decoded(const Text: string): string;

  public
    [Test]
    procedure TestASCIIHexIgnoresWhitespace;

    [Test]
    procedure TestASCIIHexOddDigitCountEndsWithZero;

    [Test]
    procedure TestASCIIHexLowerCaseAndNoTerminator;

    [Test]
    procedure TestASCIIHexInvalidDigitIsLogged;
  end;

implementation

uses
  System.SysUtils,
  Pdf4D.Common.Defines,
  Pdf4D.Common.Log,
  Pdf4D.Filter.Tests.Support;

{ TASCIIHexFilterTests }

function TASCIIHexFilterTests.Decoded(const Text: string): string;
begin
  Result := TFilterTestSupport.ToHex(TFilterTestSupport.Decode('ASCIIHexDecode', TFilterTestSupport.AsciiBytes(Text)));
end;

procedure TASCIIHexFilterTests.TestASCIIHexIgnoresWhitespace;
begin
  const Bytes = TFilterTestSupport.Decode('ASCIIHexDecode', TFilterTestSupport.AsciiBytes('48 65 6C6C 6F>'));

  Assert.AreEqual('Hello', TFilterTestSupport.AsciiString(Bytes));
end;

procedure TASCIIHexFilterTests.TestASCIIHexOddDigitCountEndsWithZero;
begin
  Assert.AreEqual('4120', Decoded('41 2>'));
  Assert.AreEqual('40', Decoded('4'));
end;

procedure TASCIIHexFilterTests.TestASCIIHexLowerCaseAndNoTerminator;
begin
  Assert.AreEqual('ABCDEF', Decoded('abcdef'));
  Assert.AreEqual('', Decoded('>'));
  Assert.AreEqual('', Decoded(''));
end;

procedure TASCIIHexFilterTests.TestASCIIHexInvalidDigitIsLogged;
begin
  var Lines := 0;
  const Log = TPdfLog.Create(
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      Inc(Lines);
    end);
  try
    TFilterTestSupport.Decode('AHx', TFilterTestSupport.AsciiBytes('4G>'), nil, Log);

    Assert.AreEqual(1, Lines);
  finally
    Log.Free;
  end;
end;

end.
