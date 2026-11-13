unit Pdf4D.Cos.Name.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCosNameTests = class
  public
    [Test]
    procedure TestNameDecodesUtf8ElseLatin1;

    [Test]
    procedure TestMalformedUtf8FallsBackToLatin1;

    [Test]
    procedure TestSupplementaryPlaneCharacter;

    [Test]
    procedure TestEmptyName;

    [Test]
    procedure TestCreateKeepsName;

    [Test]
    procedure TestNamesAreStringConstants;
  end;

implementation

uses
  System.SysUtils,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names;

{ TCosNameTests }

procedure TCosNameTests.TestNameDecodesUtf8ElseLatin1;
begin
  Assert.AreEqual(#$00E9, TCosName.DecodeBytes(TBytes.Create($C3, $A9)));
  Assert.AreEqual(#$00E9, TCosName.DecodeBytes(TBytes.Create($E9)));
  Assert.AreEqual('Name', TCosName.DecodeBytes(TBytes.Create($4E, $61, $6D, $65)));
end;

procedure TCosNameTests.TestMalformedUtf8FallsBackToLatin1;
begin
  // PDFBox 3.0.8 falls back to ISO-8859-1, so a byte in $80..$9F stays a control character
  Assert.AreEqual(#$0080, TCosName.DecodeBytes(TBytes.Create($80)));
  // Overlong form of U+002F
  Assert.AreEqual(#$00C0#$00AF, TCosName.DecodeBytes(TBytes.Create($C0, $AF)));
  // Encoded surrogate
  Assert.AreEqual(#$00ED#$00A0#$0080, TCosName.DecodeBytes(TBytes.Create($ED, $A0, $80)));
  // Truncated sequence
  Assert.AreEqual('A'#$00E2#$0082, TCosName.DecodeBytes(TBytes.Create($41, $E2, $82)));
  // A well-formed U+FFFD counts as lossy decoding, as in PDFBox
  Assert.AreEqual(#$00EF#$00BF#$00BD, TCosName.DecodeBytes(TBytes.Create($EF, $BF, $BD)));
end;

procedure TCosNameTests.TestSupplementaryPlaneCharacter;
begin
  Assert.AreEqual(#$D83D#$DE00, TCosName.DecodeBytes(TBytes.Create($F0, $9F, $98, $80)));
end;

procedure TCosNameTests.TestEmptyName;
begin
  Assert.AreEqual('', TCosName.DecodeBytes(nil));
end;

procedure TCosNameTests.TestCreateKeepsName;
begin
  const Name = TCosName.Create('Pages');
  try
    Assert.AreEqual('Pages', Name.Name);
    Assert.IsFalse(Name.Direct);
    Name.Direct := True;
    Assert.IsTrue(Name.Direct);
  finally
    Name.Free;
  end;
end;

procedure TCosNameTests.TestNamesAreStringConstants;
begin
  Assert.AreEqual('Type', TCosNames.Type_);
  Assert.AreEqual('Pages', TCosNames.Pages);
  Assert.AreEqual('Kids', TCosNames.Kids);
  Assert.AreEqual('Count', TCosNames.Count);
  Assert.AreEqual('Parent', TCosNames.Parent);
  Assert.AreEqual('Length', TCosNames.Length);
  Assert.AreEqual('Filter', TCosNames.Filter);
  Assert.AreEqual('DecodeParms', TCosNames.DecodeParms);
  Assert.AreEqual('MediaBox', TCosNames.MediaBox);
  Assert.AreEqual('Root', TCosNames.Root);
  Assert.AreEqual('Prev', TCosNames.Prev);
  Assert.AreEqual('XRefStm', TCosNames.XRefStm);
  Assert.AreEqual('Encrypt', TCosNames.Encrypt);
  Assert.AreEqual('Off', TCosNames.Off);
  Assert.AreEqual('OFF', TCosNames.OffOcg);
  Assert.AreEqual('adbe.pkcs7.detached', TCosNames.AdbePkcs7Detached);
end;

end.
