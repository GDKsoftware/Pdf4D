// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
unit Pdf4D.Font.TrueType.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Font.TrueType,
  Pdf4D.Model.Tests.Support,
  Pdf4D.Tests.PdfBuilder;

type
  [TestFixture]
  TTrueTypeFontTests = class
  private
    FModels: TModelTestDocuments;
    FFonts: TObjectList<TPDTrueTypeFont>;

    function OpenFont(const FontEntries: string; const FontFile: TBytes; const HasFontFile: Boolean; const Flags: Integer = 32): TPDTrueTypeFont;
    function OpenEmbedded(const FontEntries: string; const Flags: Integer = 32): TPDTrueTypeFont;
    function ReferenceGID(const Code: Integer): Integer;
    function WinSymbolFontBytes: TBytes;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestEmbeddedWinAnsi;

    [Test]
    procedure TestSymbolicTrueTypeWithoutEncoding;

    [Test]
    procedure TestSymbolicWinSymbolCmapUsesTheF000Range;

    [Test]
    procedure TestZeroUnitsPerEmGivesTheUnscaledAdvance;

    [Test]
    procedure TestNonSymbolicUsesUnicodeCmap;

    [Test]
    procedure TestCodeWithoutNameHasNoGlyph;

    [Test]
    procedure TestNonEmbeddedArialUsesMapper;

    [Test]
    procedure TestDamagedFontFile2FallsBack;

    [Test]
    procedure TestTruncatedFontFile2FallsBack;

    [Test]
    procedure TestFactoryCachesPerDocument;
  end;

implementation

uses
  Pdf4D.Font.Factory,
  Pdf4D.FontBox.TrueType.Cmap,
  Pdf4D.FontBox.TrueType.Parser,
  Pdf4D.Tests.TestFonts,
  Pdf4D.Tests.TrueTypeBuilder,
  Pdf4D.Tests.TextDocuments;

const
  LiberationFile = 'LiberationSans-Regular.ttf';
  CapitalAWidth = 666.9922;
  WinAnsiEntries = '/BaseFont /LiberationSans /FontDescriptor 20 0 R /Encoding /WinAnsiEncoding';

{ TTrueTypeFontTests }

procedure TTrueTypeFontTests.Setup;
begin
  FModels := TModelTestDocuments.Create;
  FFonts := TObjectList<TPDTrueTypeFont>.Create(True);
end;

procedure TTrueTypeFontTests.TearDown;
begin
  FreeAndNil(FFonts);
  FreeAndNil(FModels);
end;

function TTrueTypeFontTests.OpenFont(const FontEntries: string; const FontFile: TBytes; const HasFontFile: Boolean;
                                     const Flags: Integer): TPDTrueTypeFont;
begin
  const Builder = TTextTestDocuments.NewBuilder(Format('<< /Type /Font /Subtype /TrueType %s >>', [FontEntries]), '');
  try
    Builder.AddObject(20, Format('<< /Type /FontDescriptor /FontName /LiberationSans /Flags %d /FontFile2 21 0 R >>', [Flags]));
    if HasFontFile then
    begin
      TTextTestDocuments.AddFontFile(Builder, 21, '/Length1 1', FontFile);
    end;
    const Document = FModels.Open(Builder);
    Result := TPDFontFactory.CreateFont(TTextTestDocuments.FontDictionary(Document, 'F1'), Document.Context) as TPDTrueTypeFont;
    FFonts.Add(Result);
  finally
    Builder.Free;
  end;
end;

function TTrueTypeFontTests.OpenEmbedded(const FontEntries: string; const Flags: Integer): TPDTrueTypeFont;
begin
  Result := OpenFont(FontEntries, TTestFonts.Bytes(LiberationFile), True, Flags);
end;

function TTrueTypeFontTests.ReferenceGID(const Code: Integer): Integer;
begin
  // The Unicode cmap of the font file itself, read without the font class
  const Parser = TTTFParser.Create;
  try
    const Ttf = Parser.Parse(TTestFonts.Bytes(LiberationFile));
    try
      Result := Ttf.GetUnicodeCmapLookup.GetGlyphId(Code);
    finally
      Ttf.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TTrueTypeFontTests.TestEmbeddedWinAnsi;
var
  Value: string;
begin
  const Font = OpenEmbedded(WinAnsiEntries);

  Assert.IsTrue(Font.IsEmbedded);
  Assert.IsFalse(Font.IsDamaged);
  Assert.AreEqual(CapitalAWidth, Double(Font.GetWidth(65)), 0.0001);
  Assert.IsTrue(Font.TryToUnicode(65, Value));
  Assert.AreEqual('A', Value);
end;

procedure TTrueTypeFontTests.TestSymbolicTrueTypeWithoutEncoding;
var
  Value: string;
begin
  const Font = OpenEmbedded('/BaseFont /LiberationSans /FontDescriptor 20 0 R', 4);

  Assert.IsTrue(Font.IsSymbolic);
  Assert.IsTrue(ReferenceGID(65) > 0);
  Assert.AreEqual(ReferenceGID(65), Font.CodeToGID(65));
  Assert.AreEqual('A', Font.CodeToName(65), 'the built-in encoding has the post name of the glyph');
  Assert.IsTrue(Font.TryToUnicode(65, Value));
  Assert.AreEqual('A', Value);
  Assert.AreEqual(CapitalAWidth, Double(Font.GetWidthFromFont(65)), 0.0001);
end;

// The font with a cmap table that has one (3, 0) subtable of format 6, which maps F041, F042 and F043 to the glyphs 36, 37 and 38
function TTrueTypeFontTests.WinSymbolFontBytes: TBytes;
begin
  const FirstCode = $F041;
  const Subtable = TTestByteWriter.Create;
  try
    Subtable.U16(6);
    Subtable.U16(10 + (2 * 3));
    Subtable.U16(0);
    Subtable.U16(FirstCode);
    Subtable.U16(3);
    Subtable.U16(36);
    Subtable.U16(37);
    Subtable.U16(38);

    const Table = TTestByteWriter.Create;
    try
      Table.U16(0);
      Table.U16(1);
      Table.U16(3);
      Table.U16(0);
      Table.U32(12);
      Table.Append(Subtable.ToBytes);

      Result := TTestFonts.Bytes(LiberationFile);
      TTrueTypeTestData.ReplaceTable(Result, 'cmap', 'cmap', Table.ToBytes);
    finally
      Table.Free;
    end;
  finally
    Subtable.Free;
  end;
end;

procedure TTrueTypeFontTests.TestSymbolicWinSymbolCmapUsesTheF000Range;
begin
  // The expected glyphs are the ones PDFBox 3.0.8 gives for the same font file: 65 -> 36, 66 -> 37, 67 -> 38, 68 -> 0
  const Font = OpenFont('/BaseFont /LiberationSans /FontDescriptor 20 0 R', WinSymbolFontBytes, True, 4);

  Assert.IsTrue(Font.IsSymbolic);
  Assert.IsFalse(Font.IsDamaged);
  Assert.AreEqual(36, Font.CodeToGID(65));
  Assert.AreEqual(37, Font.CodeToGID(66));
  Assert.AreEqual(38, Font.CodeToGID(67));
  Assert.AreEqual(0, Font.CodeToGID(68));
end;

procedure TTrueTypeFontTests.TestZeroUnitsPerEmGivesTheUnscaledAdvance;
begin
  var Bytes := TTestFonts.Bytes(LiberationFile);
  // unitsPerEm is at offset 18 of the head table
  TTrueTypeTestData.Write16(Bytes, TTrueTypeTestData.TableOffset(Bytes, 'head') + 18, 0);
  const Font = OpenFont(WinAnsiEntries, Bytes, True);

  Assert.IsTrue(Font.IsEmbedded);
  // 666.9922 per thousand at 2048 units per em is 1366 units
  Assert.AreEqual(Double(1366), Double(Font.GetWidthFromFont(65)), 0.0001);
end;

procedure TTrueTypeFontTests.TestNonSymbolicUsesUnicodeCmap;
begin
  const Font = OpenEmbedded(WinAnsiEntries);

  Assert.AreEqual(ReferenceGID(65), Font.CodeToGID(65));
  // 128 is the Euro sign in WinAnsiEncoding
  Assert.AreEqual(ReferenceGID($20AC), Font.CodeToGID(128));
  Assert.IsTrue(Font.HasGlyph(65));
  Assert.IsTrue(Font.HasGlyph('A'));
end;

procedure TTrueTypeFontTests.TestCodeWithoutNameHasNoGlyph;
begin
  const Font = OpenEmbedded(WinAnsiEntries);

  Assert.AreEqual(0, Font.CodeToGID(0));
  Assert.IsFalse(Font.HasGlyph(0));
end;

procedure TTrueTypeFontTests.TestNonEmbeddedArialUsesMapper;
begin
  const Font = OpenFont('/BaseFont /Arial,Bold /Encoding /WinAnsiEncoding', nil, False);

  Assert.IsFalse(Font.IsEmbedded);
  Assert.IsFalse(Font.IsDamaged);
  Assert.IsNotNull(Font.GetTrueTypeFont);
  Assert.AreEqual(CapitalAWidth, Double(Font.GetWidthFromFont(65)), 0.0001);
end;

procedure TTrueTypeFontTests.TestDamagedFontFile2FallsBack;
begin
  var Garbage: TBytes;
  SetLength(Garbage, 3000);
  for var Index := 0 to High(Garbage) do
  begin
    Garbage[Index] := Byte((Index * 131) + 7);
  end;
  const Font = OpenFont('/BaseFont /LiberationSans /FontDescriptor 20 0 R /FirstChar 65 /LastChar 65 /Widths [ 555 ] ' +
                        '/Encoding /WinAnsiEncoding', Garbage, True);

  Assert.IsFalse(Font.IsEmbedded);
  Assert.IsTrue(Font.IsDamaged);
  Assert.IsTrue(FModels.HasLogLine('Could not read embedded TTF'));
  Assert.AreEqual(Double(555), Double(Font.GetWidth(65)), 0.0001);
  Assert.IsTrue(Font.GetWidthFromFont(65) > 0, 'the font mapper gives a substitute');
end;

procedure TTrueTypeFontTests.TestTruncatedFontFile2FallsBack;
begin
  const Whole = TTestFonts.Bytes(LiberationFile);
  const Truncated = Copy(Whole, 0, Length(Whole) div 3);
  const Font = OpenFont(WinAnsiEntries, Truncated, True);

  Assert.IsFalse(Font.IsEmbedded);
  Assert.IsTrue(Font.IsDamaged);
  Assert.IsTrue(Font.GetWidthFromFont(65) > 0);
end;

procedure TTrueTypeFontTests.TestFactoryCachesPerDocument;
begin
  const Builder = TTextTestDocuments.NewBuilder('<< /Type /Font /Subtype /TrueType /BaseFont /Arial >>', '');
  try
    const Document = FModels.Open(Builder);
    const Dictionary = TTextTestDocuments.FontDictionary(Document, 'F1');
    const First = TPDFontFactory.GetFont(Dictionary, Document.Context);
    Assert.IsTrue(First is TPDTrueTypeFont);
    Assert.AreSame(First, TPDFontFactory.GetFont(Dictionary, Document.Context));
  finally
    Builder.Free;
  end;
end;

end.
