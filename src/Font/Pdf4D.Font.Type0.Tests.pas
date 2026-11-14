// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
unit Pdf4D.Font.Type0.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Font.Type0,
  Pdf4D.Model.DocumentContext,
  Pdf4D.Model.Tests.Support,
  Pdf4D.Tests.PdfBuilder;

type
  [TestFixture]
  TType0FontTests = class
  private
    FModels: TModelTestDocuments;
    FFonts: TObjectList<TPDType0Font>;
    FContext: TPDDocumentContext;

    function OpenFont(const Type0Body, DescendantBody: string; const ToUnicode: string = ''; const CIDToGIDMap: TBytes = nil;
                      const Context: TPDDocumentContext = nil): TPDType0Font;
    function Type0Entries(const Entries: string): string;
    function DescendantEntries(const Entries: string): string;
    function ReferenceAdvance(const GID: Integer): Single;
    class function Ascii(const Text: string): TBytes; static;
    procedure OpenWithoutDescendant;
    procedure OpenWithEmptyDescendantArray;
    procedure OpenWithDescendantThatIsNoDictionary;
    procedure OpenWithWrongDescendantType;
    procedure OpenWithUnknownEncoding;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestIdentityHWithToUnicode;

    [Test]
    procedure TestWArrayBothForms;

    [Test]
    procedure TestHugeWRangeIsBounded;

    [Test]
    procedure TestLaterWEntryOverridesEarlierRange;

    [Test]
    procedure TestMalformedWArrayKeepsWhatWasRead;

    [Test]
    procedure TestAverageSpaceAndHeightMatchPdfBox;

    [Test]
    procedure TestVerticalIdentityV;

    [Test]
    procedure TestW2Entries;

    [Test]
    procedure TestMalformedW2KeepsWhatWasRead;

    [Test]
    procedure TestUcs2FallbackForPredefinedCMap;

    [Test]
    procedure TestCidToGidMapStream;

    [Test]
    procedure TestCidToGidMapWithOddLength;

    [Test]
    procedure TestHugeCidToGidMapIsCutOff;

    [Test]
    procedure TestMissingDescendantRaises;

    [Test]
    procedure TestMissingDescendantArrayRaises;

    [Test]
    procedure TestDescendantThatIsNoDictionaryRaises;

    [Test]
    procedure TestDescendantWithWrongTypeRaises;

    [Test]
    procedure TestUnknownPredefinedCMapRaises;

    [Test]
    procedure TestUnmappedCodeHasNoUnicode;

    [Test]
    procedure TestUnicodeFromFontCmapWithoutToUnicode;

    [Test]
    procedure TestEmbeddedEncodingCMapStream;

    [Test]
    procedure TestEncodingCMapStreamCountsAgainstBudget;

    [Test]
    procedure TestReadCodeWithoutCMapRaises;

    [Test]
    procedure TestFactoryCachesPerDocument;

    [Test]
    procedure TestFailedFontIsNotParsedAgain;
  end;

implementation

uses
  System.Classes,
  Pdf4D.Common.Defines,
  Pdf4D.Common.Matrix,
  Pdf4D.Font.CIDFont,
  Pdf4D.Font.CIDFontType2,
  Pdf4D.Font.Factory,
  Pdf4D.FontBox.CMap,
  Pdf4D.FontBox.TrueType.Parser,
  Pdf4D.Tests.TestFonts,
  Pdf4D.Tests.TextDocuments;

const
  LiberationFile = 'LiberationSans-Regular.ttf';
  CapitalAGlyph = 36;
  Type0Start = '<< /Type /Font /Subtype /Type0 /BaseFont /LiberationSans /DescendantFonts [ 11 0 R ] ';
  DescendantStart = '<< /Type /Font /Subtype /CIDFontType2 /BaseFont /LiberationSans ' +
                    '/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /FontDescriptor 20 0 R ';
  IdentityMap = '/CIDToGIDMap /Identity ';
  ToUnicodeObject = 12;
  CIDToGIDObject = 13;
  EncodingObject = 14;
  CMapStart = '/CIDInit /ProcSet findresource begin 12 dict begin begincmap /CMapName /Test def /CMapType 2 def ';
  CMapEnd = 'endcmap CMapName currentdict /CMap defineresource pop end end';
  CapitalAToUnicode = CMapStart + '1 begincodespacerange <0000> <FFFF> endcodespacerange 1 beginbfchar <0024> <0041> endbfchar ' + CMapEnd;
  OneByteCidMap = CMapStart + '1 begincodespacerange <00> <FF> endcodespacerange 1 begincidrange <41> <5A> 36 endcidrange ' + CMapEnd;
  WideIdentityCMap = CMapStart + '1 begincodespacerange <000000> <FFFFFF> endcodespacerange 1 begincidrange <000000> <FFFFFF> 0 endcidrange ' + CMapEnd;
  ThreeCidChars = CMapStart + '1 begincodespacerange <00> <FF> endcodespacerange 3 begincidchar <41> 36 <42> 37 <43> 38 endcidchar ' + CMapEnd;

{ TType0FontTests }

procedure TType0FontTests.Setup;
begin
  FModels := TModelTestDocuments.Create;
  FFonts := TObjectList<TPDType0Font>.Create(True);
end;

procedure TType0FontTests.TearDown;
begin
  FreeAndNil(FFonts);
  FreeAndNil(FContext);
  FreeAndNil(FModels);
end;

class function TType0FontTests.Ascii(const Text: string): TBytes;
begin
  Result := TEncoding.ASCII.GetBytes(Text);
end;

function TType0FontTests.Type0Entries(const Entries: string): string;
begin
  Result := Type0Start + Entries + ' >>';
end;

function TType0FontTests.DescendantEntries(const Entries: string): string;
begin
  Result := DescendantStart + Entries + ' >>';
end;

function TType0FontTests.OpenFont(const Type0Body, DescendantBody: string; const ToUnicode: string; const CIDToGIDMap: TBytes;
                                  const Context: TPDDocumentContext): TPDType0Font;
begin
  const Builder = TTextTestDocuments.NewBuilder(Type0Body + TTextTestDocuments.Separator + DescendantBody, '');
  try
    Builder.AddObject(20, '<< /Type /FontDescriptor /FontName /LiberationSans /Flags 4 /FontFile2 21 0 R >>');
    TTextTestDocuments.AddFontFile(Builder, 21, '/Length1 1', TTestFonts.Bytes(LiberationFile));
    if ToUnicode <> '' then
    begin
      Builder.AddStreamObject(ToUnicodeObject, '', Ascii(ToUnicode));
    end;
    if Length(CIDToGIDMap) > 0 then
    begin
      Builder.AddStreamObject(CIDToGIDObject, '', CIDToGIDMap);
    end;
    // The encoding CMap stream is object 14 when a test refers to it
    Builder.AddStreamObject(EncodingObject, '', Ascii(OneByteCidMap));
    Builder.AddStreamObject(EncodingObject + 1, '', Ascii(ThreeCidChars));
    Builder.AddStreamObject(EncodingObject + 2, '', Ascii(WideIdentityCMap));
    const Document = FModels.Open(Builder);
    var UsedContext := Context;
    if not Assigned(UsedContext) then
    begin
      UsedContext := Document.Context;
    end;
    Result := TPDFontFactory.CreateFont(TTextTestDocuments.FontDictionary(Document, 'F1'), UsedContext) as TPDType0Font;
    FFonts.Add(Result);
  finally
    Builder.Free;
  end;
end;

function TType0FontTests.ReferenceAdvance(const GID: Integer): Single;
begin
  // The advance of the font file itself, read without the font classes
  const Parser = TTTFParser.Create;
  try
    const Ttf = Parser.Parse(TTestFonts.Bytes(LiberationFile));
    try
      Result := Ttf.GetAdvanceWidth(GID) * (Single(1000) / Ttf.UnitsPerEm);
    finally
      Ttf.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TType0FontTests.TestIdentityHWithToUnicode;
var
  Value: string;
begin
  const Font = OpenFont(Type0Entries('/Encoding /Identity-H /ToUnicode 12 0 R'), DescendantEntries(IdentityMap), CapitalAToUnicode);

  var Position := 0;
  const Code = Font.ReadCode([$00, $24], Position);
  Assert.AreEqual(36, Code);
  Assert.AreEqual(2, Position);
  Assert.IsTrue(Font.TryToUnicode(Code, Value));
  Assert.AreEqual('A', Value);
  Assert.AreEqual(CapitalAGlyph, Font.CodeToGID(Code));
  Assert.AreEqual(Double(ReferenceAdvance(CapitalAGlyph)), Double(Font.GetWidthFromFont(Code)), 0.0001);
  Assert.AreEqual(Double(1000), Double(Font.GetWidth(Code)), 0.0001, 'without /W the width is /DW');
  Assert.IsTrue(Font.IsEmbedded);
  Assert.IsFalse(Font.IsVertical);
  Assert.IsFalse(Font.IsStandard14);
  Assert.AreEqual('Type0', Font.SubType);
end;

procedure TType0FontTests.TestWArrayBothForms;
begin
  const Font = OpenFont(Type0Entries('/Encoding /Identity-H'), DescendantEntries(IdentityMap + '/W [36 [600 700] 40 45 500]'));

  Assert.AreEqual(Double(600), Double(Font.GetWidth(36)), 0.0001);
  Assert.AreEqual(Double(700), Double(Font.GetWidth(37)), 0.0001);
  Assert.AreEqual(Double(500), Double(Font.GetWidth(42)), 0.0001);
  Assert.AreEqual(Double(1000), Double(Font.GetWidth(100)), 0.0001, '/DW');
  Assert.IsTrue(Font.HasExplicitWidth(42));
  Assert.IsFalse(Font.HasExplicitWidth(100));
end;

procedure TType0FontTests.TestHugeWRangeIsBounded;
begin
  // PDFBox would keep two billion entries for the second range
  const Font = OpenFont(Type0Entries('/Encoding /Identity-H'),
                        DescendantEntries(IdentityMap + '/DW 800 /W [0 65535 1000 66000 2000000000 400 -5 -1 300]'));

  Assert.AreEqual(Double(1000), Double(Font.GetWidth(36)), 0.0001);
  Assert.AreEqual(Double(1000), Double(Font.GetWidth(65535)), 0.0001);
  Assert.IsTrue(Font.GetAverageFontWidth > 0);

  const Huge = OpenFont(Type0Entries('/Encoding /Identity-H'), DescendantEntries(IdentityMap + '/DW 800 /W [0 2000000000 400 100 [ 650 ]]'));
  Assert.AreEqual(Double(400), Double(Huge.GetWidth(36)), 0.0001);
  Assert.AreEqual(Double(400), Double(Huge.GetWidth(65535)), 0.0001);
  Assert.AreEqual(Double(650), Double(Huge.GetWidth(100)), 0.0001, 'a later entry wins over the range');
  Assert.IsTrue(Huge.HasExplicitWidth(7));
  Assert.IsTrue(Huge.GetAverageFontWidth > 399);
end;

procedure TType0FontTests.TestLaterWEntryOverridesEarlierRange;
begin
  const Font = OpenFont(Type0Entries('/Encoding /Identity-H'),
                        DescendantEntries(IdentityMap + '/W [0 3000000 400 5 [ 650 ] 0 3000000 450]'));

  // The last entry that names a CID wins, as with the puts of a HashMap
  Assert.AreEqual(Double(450), Double(Font.GetWidth(5)), 0.0001);

  const Other = OpenFont(Type0Entries('/Encoding /Identity-H'), DescendantEntries(IdentityMap + '/W [0 3000000 400 5 [ 650 ]]'));
  Assert.AreEqual(Double(650), Double(Other.GetWidth(5)), 0.0001);
  Assert.AreEqual(Double(400), Double(Other.GetWidth(6)), 0.0001);
end;

procedure TType0FontTests.TestMalformedWArrayKeepsWhatWasRead;
begin
  const Font = OpenFont(Type0Entries('/Encoding /Identity-H'),
                        DescendantEntries(IdentityMap + '/W [36 [600] /Name 5 [ /X 700 ] 50 51 450 60]'));

  Assert.AreEqual(Double(600), Double(Font.GetWidth(36)), 0.0001);
  Assert.AreEqual(Double(1000), Double(Font.GetWidth(5)), 0.0001, 'a bad member leaves its CID alone');
  Assert.AreEqual(Double(700), Double(Font.GetWidth(6)), 0.0001, 'the number after the bad member of the array is read');
  Assert.AreEqual(Double(450), Double(Font.GetWidth(50)), 0.0001);
  Assert.IsTrue(FModels.HasLogLine('Expected'));
end;

procedure TType0FontTests.TestAverageSpaceAndHeightMatchPdfBox;
begin
  // The values that PDFBox 3.0.8 gives for this font
  const Font = OpenFont(Type0Entries('/Encoding /Identity-V'), DescendantEntries(IdentityMap + '/W [36 [600 700] 40 45 500]'));

  Assert.AreEqual(Double(537.5), Double(Font.GetAverageFontWidth), 0.0001);
  Assert.AreEqual(Double(1000), Double(Font.GetSpaceWidth), 0.0001);
  Assert.AreEqual(Double(1.1171875), Double(Font.GetHeight(36)), 0.000001);
  Assert.AreEqual(Double(-0.3), Double(Font.GetPositionVector(36).X), 0.0001);
  Assert.AreEqual(Double(-0.35), Double(Font.GetPositionVector(37).X), 0.0001);
end;

procedure TType0FontTests.TestVerticalIdentityV;
begin
  const Font = OpenFont(Type0Entries('/Encoding /Identity-V'), DescendantEntries(IdentityMap));

  Assert.IsTrue(Font.IsVertical);
  const Displacement = Font.GetDisplacement(36);
  Assert.AreEqual(Double(0), Double(Displacement.X), 0.0001);
  Assert.AreEqual(Double(-1), Double(Displacement.Y), 0.0001);
  // The default position vector is (w0 / 2, 880), scaled by -1/1000
  const Position = Font.GetPositionVector(36);
  Assert.AreEqual(Double(-0.5), Double(Position.X), 0.0001);
  Assert.AreEqual(Double(-0.88), Double(Position.Y), 0.0001);
end;

procedure TType0FontTests.TestW2Entries;
begin
  const Font = OpenFont(Type0Entries('/Encoding /Identity-V'),
                        DescendantEntries(IdentityMap + '/DW2 [900 -800] /W2 [36 [-500 250 800] 40 45 -600 100 700]'));

  Assert.AreEqual(Double(-0.5), Double(Font.GetDisplacement(36).Y), 0.0001);
  Assert.AreEqual(Double(-0.25), Double(Font.GetPositionVector(36).X), 0.0001);
  Assert.AreEqual(Double(-0.8), Double(Font.GetPositionVector(36).Y), 0.0001);
  Assert.AreEqual(Double(-0.6), Double(Font.GetDisplacement(42).Y), 0.0001);
  Assert.AreEqual(Double(-0.1), Double(Font.GetPositionVector(42).X), 0.0001);
  Assert.AreEqual(Double(-0.8), Double(Font.GetDisplacement(100).Y), 0.0001, '/DW2');
  Assert.AreEqual(Double(-0.9), Double(Font.GetPositionVector(100).Y), 0.0001, '/DW2');
end;

procedure TType0FontTests.TestMalformedW2KeepsWhatWasRead;
begin
  const Font = OpenFont(Type0Entries('/Encoding /Identity-V'),
                        DescendantEntries(IdentityMap + '/W2 [36 [-500 250 800] /Junk 5 40 [ 1 2 ] 70 80 1 2]'));

  Assert.AreEqual(Double(-0.5), Double(Font.GetDisplacement(36).Y), 0.0001);
  Assert.AreEqual(Double(-1), Double(Font.GetDisplacement(75).Y), 0.0001, 'the rest of the array is dropped');
  Assert.IsTrue(FModels.HasLogLine('Invalid /W2'));
end;

procedure TType0FontTests.TestUcs2FallbackForPredefinedCMap;
var
  Value: string;
begin
  const Font = OpenFont(Type0Entries('/Encoding /UniJIS-UCS2-H'),
                        '<< /Type /Font /Subtype /CIDFontType2 /BaseFont /LiberationSans ' +
                        '/CIDSystemInfo << /Registry (Adobe) /Ordering (Japan1) /Supplement 4 >> ' +
                        '/FontDescriptor 20 0 R /CIDToGIDMap /Identity >>');

  var Position := 0;
  const Code = Font.ReadCode([$30, $42], Position);
  Assert.AreEqual($3042, Code);
  Assert.AreEqual(843, Font.CodeToCID(Code));
  Assert.IsTrue(Font.TryToUnicode(Code, Value));
  Assert.AreEqual(#$3042, Value);
  var UCS2: TCMap;
  Assert.IsTrue(Font.TryGetCMapUCS2(UCS2));
  Assert.AreEqual('Adobe-Japan1-UCS2', UCS2.Name);
end;

procedure TType0FontTests.TestCidToGidMapStream;
begin
  const Font = OpenFont(Type0Entries('/Encoding /Identity-H'),
                        DescendantEntries('/CIDToGIDMap 13 0 R'), '', [$00, $00, $00, $05]);

  Assert.AreEqual(5, Font.CodeToGID(1));
  Assert.AreEqual(0, Font.CodeToGID(2), 'a CID beyond a short map has glyph 0');
  Assert.AreEqual(0, Font.CodeToGID(0));
end;

procedure TType0FontTests.TestCidToGidMapWithOddLength;
begin
  const Font = OpenFont(Type0Entries('/Encoding /Identity-H'),
                        DescendantEntries('/CIDToGIDMap 13 0 R'), '', [$00, $00, $00, $05, $00, $09, $07]);

  Assert.AreEqual(5, Font.CodeToGID(1));
  Assert.AreEqual(9, Font.CodeToGID(2));
  Assert.AreEqual(0, Font.CodeToGID(3), 'the odd last byte is no entry');
end;

procedure TType0FontTests.TestHugeCidToGidMapIsCutOff;
begin
  var Map: TBytes;
  SetLength(Map, 3000000);
  for var Index := 0 to (Length(Map) div 2) - 1 do
  begin
    Map[Index * 2] := 0;
    Map[(Index * 2) + 1] := 9;
  end;

  // Three byte codes, so that the code is the CID up to 16777215
  const Font = OpenFont(Type0Entries('/Encoding 16 0 R'), DescendantEntries('/CIDToGIDMap 13 0 R'), '', Map);

  Assert.AreEqual(9, Font.CodeToGID(1));
  Assert.AreEqual(9, Font.CodeToGID(1000000));
  Assert.AreEqual(0, Font.CodeToGID(1200000), 'beyond the part of the map that is read');
  Assert.IsTrue(FModels.HasLogLine('too large'));
end;

procedure TType0FontTests.OpenWithoutDescendant;
begin
  OpenFont('<< /Type /Font /Subtype /Type0 /BaseFont /X /Encoding /Identity-H >>', DescendantEntries(IdentityMap));
end;

procedure TType0FontTests.OpenWithEmptyDescendantArray;
begin
  OpenFont('<< /Type /Font /Subtype /Type0 /BaseFont /X /Encoding /Identity-H /DescendantFonts [] >>', DescendantEntries(IdentityMap));
end;

procedure TType0FontTests.OpenWithDescendantThatIsNoDictionary;
begin
  OpenFont('<< /Type /Font /Subtype /Type0 /BaseFont /X /Encoding /Identity-H /DescendantFonts [ 5 ] >>', DescendantEntries(IdentityMap));
end;

procedure TType0FontTests.OpenWithWrongDescendantType;
begin
  OpenFont(Type0Entries('/Encoding /Identity-H'), '<< /Type /Page /Subtype /CIDFontType2 >>');
end;

procedure TType0FontTests.OpenWithUnknownEncoding;
begin
  OpenFont(Type0Entries('/Encoding /NoSuchCMap-H'), DescendantEntries(IdentityMap));
end;

procedure TType0FontTests.TestMissingDescendantRaises;
begin
  Assert.WillRaiseWithMessageRegex(OpenWithEmptyDescendantArray, EPdfParseException, 'Descendant font array is empty');
end;

procedure TType0FontTests.TestMissingDescendantArrayRaises;
begin
  Assert.WillRaiseWithMessageRegex(OpenWithoutDescendant, EPdfParseException, 'Missing descendant font array');
end;

procedure TType0FontTests.TestDescendantThatIsNoDictionaryRaises;
begin
  Assert.WillRaiseWithMessageRegex(OpenWithDescendantThatIsNoDictionary, EPdfParseException, 'Missing descendant font dictionary');
end;

procedure TType0FontTests.TestDescendantWithWrongTypeRaises;
begin
  Assert.WillRaiseWithMessageRegex(OpenWithWrongDescendantType, EPdfParseException, 'wrong type');
end;

procedure TType0FontTests.TestUnknownPredefinedCMapRaises;
begin
  Assert.WillRaise(OpenWithUnknownEncoding, EPdfParseException);
end;

procedure TType0FontTests.TestUnmappedCodeHasNoUnicode;
var
  Value: string;
begin
  const Font = OpenFont(Type0Entries('/Encoding /Identity-H'), DescendantEntries(IdentityMap));

  // The CID is beyond the glyphs of the font, so the glyph is .notdef, which has no character
  Assert.IsFalse(Font.TryToUnicode(65535, Value));
  Assert.AreEqual('', Value);
  Assert.IsTrue(FModels.HasLogLine('No Unicode mapping for CID+65535'));
end;

procedure TType0FontTests.TestUnicodeFromFontCmapWithoutToUnicode;
var
  Value: string;
begin
  const Font = OpenFont(Type0Entries('/Encoding /Identity-H'), DescendantEntries(IdentityMap));

  Assert.IsTrue(Font.TryToUnicode(CapitalAGlyph, Value), 'PDFBOX-5324');
  Assert.AreEqual('A', Value);
end;

procedure TType0FontTests.TestEmbeddedEncodingCMapStream;
var
  Value: string;
begin
  const Font = OpenFont(Type0Entries('/Encoding 14 0 R'), DescendantEntries(IdentityMap));

  var Position := 0;
  const Code = Font.ReadCode([$41, $42], Position);
  Assert.AreEqual($41, Code);
  Assert.AreEqual(1, Position, 'the codespace has one byte codes');
  Assert.AreEqual(36, Font.CodeToCID(Code));
  Assert.AreEqual(CapitalAGlyph, Font.CodeToGID(Code));
  Assert.IsTrue(Font.TryToUnicode(Code, Value));
  Assert.AreEqual('A', Value);
end;

procedure TType0FontTests.TestEncodingCMapStreamCountsAgainstBudget;
begin
  var Options := TPdfLoadOptions.Default;
  Options.MaxToUnicodeMappings := 1;
  FContext := TPDDocumentContext.Create(nil, Options);

  const Font = OpenFont(Type0Entries('/Encoding 15 0 R'), DescendantEntries(IdentityMap), '', nil, FContext);

  Assert.IsTrue(FContext.IsToUnicodeBudgetExhausted);
  var Position := 0;
  Assert.WillRaise(
    procedure
    begin
      Font.ReadCode([$41], Position);
    end, EPdfParseException);
end;

procedure TType0FontTests.TestReadCodeWithoutCMapRaises;
begin
  const Font = OpenFont(Type0Entries(''), DescendantEntries(IdentityMap));

  Assert.IsFalse(Font.IsVertical);
  var Position := 0;
  Assert.WillRaise(
    procedure
    begin
      Font.ReadCode([$41], Position);
    end, EPdfParseException);
  Assert.AreEqual(0, Font.CodeToCID(65), 'no CMap, no CID');
end;

procedure TType0FontTests.TestFailedFontIsNotParsedAgain;
begin
  // The descendant is parsed before the encoding is found to be unknown; the second request must not do that again
  const Builder = TTextTestDocuments.NewBuilder(Type0Entries('/Encoding /NoSuchCMap-H') + TTextTestDocuments.Separator + DescendantEntries(IdentityMap), '');
  try
    Builder.AddObject(20, '<< /Type /FontDescriptor /FontName /LiberationSans /Flags 4 /FontFile2 21 0 R >>');
    TTextTestDocuments.AddFontFile(Builder, 21, '/Length1 1', TTestFonts.Bytes(LiberationFile));
    const Document = FModels.Open(Builder);
    const Dictionary = TTextTestDocuments.FontDictionary(Document, 'F1');
    Assert.WillRaiseWithMessageRegex(
      procedure
      begin
        TPDFontFactory.GetFont(Dictionary, Document.Context);
      end, EPdfParseException, 'predefined CMap');
    Assert.IsTrue(TPDFontFactory.HasFailed(Dictionary, Document.Context));

    Assert.WillRaiseWithMessageRegex(
      procedure
      begin
        TPDFontFactory.GetFont(Dictionary, Document.Context);
      end, EPdfParseException, 'earlier');
  finally
    Builder.Free;
  end;
end;

procedure TType0FontTests.TestFactoryCachesPerDocument;
begin
  const Builder = TTextTestDocuments.NewBuilder(Type0Entries('/Encoding /Identity-H') + TTextTestDocuments.Separator + DescendantEntries(IdentityMap), '');
  try
    Builder.AddObject(20, '<< /Type /FontDescriptor /FontName /LiberationSans /Flags 4 /FontFile2 21 0 R >>');
    TTextTestDocuments.AddFontFile(Builder, 21, '/Length1 1', TTestFonts.Bytes(LiberationFile));
    const Document = FModels.Open(Builder);
    const Dictionary = TTextTestDocuments.FontDictionary(Document, 'F1');
    const First = TPDFontFactory.GetFont(Dictionary, Document.Context);
    Assert.IsTrue(First is TPDType0Font);
    Assert.AreSame(First, TPDFontFactory.GetFont(Dictionary, Document.Context));
    Assert.IsTrue(TPDType0Font(First).DescendantFont is TPDCIDFontType2);
    Assert.AreSame(First, TPDType0Font(First).DescendantFont.Parent);
  finally
    Builder.Free;
  end;
end;

end.
