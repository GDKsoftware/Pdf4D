// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
unit Pdf4D.Cos.PdfString.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCosStringTests = class
  public
    [Test]
    procedure TestStringBomDetection;

    [Test]
    procedure TestUtf16LittleEndianBom;

    [Test]
    procedure TestUtf8BomWithMultiByteCharacters;

    [Test]
    procedure TestWithoutBomUsesPdfDocEncoding;

    [Test]
    procedure TestMalformedUtf16BecomesReplacementCharacter;

    [Test]
    procedure TestSurrogatePairInUtf16;

    [Test]
    procedure TestEmptyAndBomOnlyStrings;

    [Test]
    procedure TestBytesAreWritableAndCopiedOnCreate;

    [Test]
    procedure TestIsHexIsKept;
  end;

implementation

uses
  System.SysUtils,
  Pdf4D.Cos.PdfString;

{ TCosStringTests }

procedure TCosStringTests.TestStringBomDetection;
begin
  const Utf16 = TCosString.Create(TBytes.Create($FE, $FF, $00, $41), False);
  const Utf8 = TCosString.Create(TBytes.Create($EF, $BB, $BF, $41), False);
  const Plain = TCosString.Create(TBytes.Create($41), False);
  try
    Assert.AreEqual('A', Utf16.GetString);
    Assert.AreEqual('A', Utf8.GetString);
    Assert.AreEqual('A', Plain.GetString);
  finally
    Plain.Free;
    Utf8.Free;
    Utf16.Free;
  end;
end;

procedure TCosStringTests.TestUtf16LittleEndianBom;
begin
  const Text = TCosString.Create(TBytes.Create($FF, $FE, $41, $00, $E9, $00), False);
  try
    Assert.AreEqual('A'#$00E9, Text.GetString);
  finally
    Text.Free;
  end;
end;

procedure TCosStringTests.TestUtf8BomWithMultiByteCharacters;
begin
  const Text = TCosString.Create(TBytes.Create($EF, $BB, $BF, $C3, $A9, $E2, $82, $AC, $F0, $9F, $98, $80), False);
  try
    Assert.AreEqual(#$00E9#$20AC#$D83D#$DE00, Text.GetString);
  finally
    Text.Free;
  end;
end;

procedure TCosStringTests.TestWithoutBomUsesPdfDocEncoding;
begin
  const Text = TCosString.Create(TBytes.Create($80, $E9, $A0), True);
  try
    Assert.AreEqual(#$2022#$00E9#$20AC, Text.GetString);
  finally
    Text.Free;
  end;
end;

procedure TCosStringTests.TestMalformedUtf16BecomesReplacementCharacter;
begin
  // Lone high surrogate, then a lone low surrogate, then an odd trailing byte
  const Text = TCosString.Create(TBytes.Create($FE, $FF, $D8, $00, $00, $41, $DC, $00, $00, $42, $00), False);
  try
    Assert.AreEqual(#$FFFD'A'#$FFFD'B'#$FFFD, Text.GetString);
  finally
    Text.Free;
  end;
end;

procedure TCosStringTests.TestSurrogatePairInUtf16;
begin
  const Text = TCosString.Create(TBytes.Create($FE, $FF, $D8, $3D, $DE, $00), False);
  try
    Assert.AreEqual(#$D83D#$DE00, Text.GetString);
  finally
    Text.Free;
  end;
end;

procedure TCosStringTests.TestEmptyAndBomOnlyStrings;
begin
  const Empty = TCosString.Create(nil, False);
  const BomOnly = TCosString.Create(TBytes.Create($FE, $FF), False);
  const Utf8BomOnly = TCosString.Create(TBytes.Create($EF, $BB, $BF), False);
  try
    Assert.AreEqual('', Empty.GetString);
    Assert.AreEqual('', BomOnly.GetString);
    Assert.AreEqual('', Utf8BomOnly.GetString);
  finally
    Utf8BomOnly.Free;
    BomOnly.Free;
    Empty.Free;
  end;
end;

procedure TCosStringTests.TestBytesAreWritableAndCopiedOnCreate;
begin
  var Source := TBytes.Create($41, $42);
  const Text = TCosString.Create(Source, False);
  try
    Source[0] := $5A;
    Assert.AreEqual('AB', Text.GetString);

    Text.Bytes := TBytes.Create($43);
    Assert.AreEqual('C', Text.GetString);
    Assert.AreEqual<Integer>(1, Length(Text.Bytes));
  finally
    Text.Free;
  end;
end;

procedure TCosStringTests.TestIsHexIsKept;
begin
  const Hex = TCosString.Create(nil, True);
  const Literal = TCosString.Create(nil, False);
  try
    Assert.IsTrue(Hex.IsHex);
    Assert.IsFalse(Literal.IsHex);
  finally
    Literal.Free;
    Hex.Free;
  end;
end;

end.
