// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
unit Pdf4D.Font.Type1.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Font.Base,
  Pdf4D.Font.Type1,
  Pdf4D.Model.Tests.Support,
  Pdf4D.Tests.PdfBuilder;

type
  [TestFixture]
  TType1FontTests = class
  private
    FModels: TModelTestDocuments;
    FFonts: TObjectList<TPDFont>;

    function OpenFont(const FontObject: string): TPDType1Font;
    function OpenAny(const Builder: TTestPdfBuilder): TPDFont;
    function OpenBuilder(const Builder: TTestPdfBuilder): TPDType1Font;
    function UnicodeOf(const Font: TPDFont; const Code: Integer): string;
    function OpenEmbeddedOpenSans: TPDType1Font;
    class function OpenSansSegments(out Segment1, Segment2: TBytes): TBytes; static;
    class function PatternBytes(const Count: Integer): TBytes; static;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestHelvetica;

    [Test]
    procedure TestHelveticaWinAnsiEuro;

    [Test]
    procedure TestDifferencesWithUniNames;

    [Test]
    procedure TestSymbol;

    [Test]
    procedure TestZapfDingbats;

    [Test]
    procedure TestEmbeddedType1BuiltInEncodingGivesUnicode;

    [Test]
    procedure TestEmbeddedType1WithWrongLengthsIsRepaired;

    [Test]
    procedure TestEmbeddedPfbInFontFile;

    [Test]
    procedure TestDamagedEmbeddedType1FallsBack;

    [Test]
    procedure TestEmptyEmbeddedType1IsDamaged;

    [Test]
    procedure TestNonEmbeddedNonStandardUsesMapper;

    [Test]
    procedure TestMissingBaseFontDoesNotFail;

    [Test]
    procedure TestUnknownCodeHasNoUnicode;

    [Test]
    procedure TestToUnicodeComesFirst;

    [Test]
    procedure TestFontFile3OnType1WithoutCffIsLogged;

    [Test]
    procedure TestIsSymbolic;

    [Test]
    procedure TestReadCodeIsOneByte;

    [Test]
    procedure TestFactoryTypesAndFallbacks;

    [Test]
    procedure TestFactoryCachesPerDocument;

    [Test]
    procedure TestFactoryDefaultFont;

    [Test]
    procedure TestSharedMapperFontIsNotFreed;
  end;

implementation

uses
  System.Classes,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Font.Encoding,
  Pdf4D.Font.Factory,
  Pdf4D.Font.GlyphList,
  Pdf4D.Font.Simple,
  Pdf4D.Font.Type1C,
  Pdf4D.FontBox.Pfb,
  Pdf4D.FontBox.Type1.Font,
  Pdf4D.Model.Document,
  Pdf4D.Tests.TestFonts,
  Pdf4D.Tests.TextDocuments;

const
  OpenSansFile = 'OpenSans-Regular.pfb';
  OpenSansFont = '<< /Type /Font /Subtype /Type1 /BaseFont /OpenSans-Regular /FontDescriptor 20 0 R >>';
  OpenSansDescriptor = '<< /Type /FontDescriptor /FontName /OpenSans-Regular /Flags 32 /FontBBox [0 0 0 0] /FontFile 21 0 R >>';
  NoUnicode = '<none>';

{ TType1FontTests }

procedure TType1FontTests.Setup;
begin
  FModels := TModelTestDocuments.Create;
  FFonts := TObjectList<TPDFont>.Create(True);
end;

procedure TType1FontTests.TearDown;
begin
  // The fonts use the dictionaries and the log of the document
  FreeAndNil(FFonts);
  FreeAndNil(FModels);
end;

function TType1FontTests.OpenAny(const Builder: TTestPdfBuilder): TPDFont;
begin
  try
    const Document = FModels.Open(Builder);
    Result := TPDFontFactory.CreateFont(TTextTestDocuments.FontDictionary(Document, 'F1'), Document.Context);
    FFonts.Add(Result);
  finally
    Builder.Free;
  end;
end;

function TType1FontTests.OpenBuilder(const Builder: TTestPdfBuilder): TPDType1Font;
begin
  Result := OpenAny(Builder) as TPDType1Font;
end;

function TType1FontTests.OpenFont(const FontObject: string): TPDType1Font;
begin
  Result := OpenBuilder(TTextTestDocuments.NewBuilder(FontObject, ''));
end;

function TType1FontTests.UnicodeOf(const Font: TPDFont; const Code: Integer): string;
begin
  if not Font.TryToUnicode(Code, TGlyphList.TextExtraction, Result) then
  begin
    Result := NoUnicode;
  end;
end;

class function TType1FontTests.OpenSansSegments(out Segment1, Segment2: TBytes): TBytes;
begin
  const Pfb = TPfbParser.Create(TTestFonts.Bytes(OpenSansFile));
  try
    Segment1 := Pfb.Segment1;
    Segment2 := Pfb.Segment2;
  finally
    Pfb.Free;
  end;
  Result := Segment1 + Segment2;
end;

class function TType1FontTests.PatternBytes(const Count: Integer): TBytes;
begin
  SetLength(Result, Count);
  for var Index := 0 to Count - 1 do
  begin
    Result[Index] := Byte(((Index * 37) + (Index shr 3)) and $7F) + 1;
  end;
end;

function TType1FontTests.OpenEmbeddedOpenSans: TPDType1Font;
begin
  var Segment1: TBytes;
  var Segment2: TBytes;
  const Data = OpenSansSegments(Segment1, Segment2);
  const Builder = TTextTestDocuments.NewBuilder(OpenSansFont, '');
  Builder.AddObject(20, OpenSansDescriptor);
  TTextTestDocuments.AddFontFile(Builder, 21, Format('/Length1 %d /Length2 %d', [Length(Segment1), Length(Segment2)]), Data);
  Result := OpenBuilder(Builder);
end;

procedure TType1FontTests.TestHelvetica;
begin
  const Font = OpenFont(TTextTestDocuments.HelveticaF1);

  Assert.AreEqual(Single(667), Font.GetWidth(65));
  Assert.AreEqual('A', UnicodeOf(Font, 65));
  Assert.AreEqual(Single(278), Font.GetSpaceWidth);
  Assert.IsTrue(Font.IsStandard14);
  Assert.IsFalse(Font.IsEmbedded);
  Assert.IsFalse(Font.IsDamaged);
end;

procedure TType1FontTests.TestHelveticaWinAnsiEuro;
begin
  const Font = OpenFont('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>');

  Assert.AreEqual(string(Char($20AC)), UnicodeOf(Font, 128));
  Assert.AreEqual(Single(556), Font.GetWidth(128));
end;

procedure TType1FontTests.TestDifferencesWithUniNames;
begin
  const Font = OpenFont('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding << /Type /Encoding ' +
                        '/BaseEncoding /WinAnsiEncoding /Differences [65 /fi 66 /uni00E9 67 /g42] >> >>');

  Assert.AreEqual(string(Char($FB01)), UnicodeOf(Font, 65));
  Assert.AreEqual(string(Char($00E9)), UnicodeOf(Font, 66));
  Assert.AreEqual(NoUnicode, UnicodeOf(Font, 67));
  Assert.IsFalse(Font.IsStandard14, 'Differences that differ from the base encoding turn off the standard 14 handling');
end;

procedure TType1FontTests.TestSymbol;
begin
  const Font = OpenFont('<< /Type /Font /Subtype /Type1 /BaseFont /Symbol >>');

  Assert.AreEqual(string(Char($03B1)), UnicodeOf(Font, 97));
  Assert.AreEqual(Single(631), Font.GetWidth(97));
  Assert.IsTrue(Font.IsSymbolic);
end;

procedure TType1FontTests.TestZapfDingbats;
begin
  const Font = OpenFont('<< /Type /Font /Subtype /Type1 /BaseFont /ZapfDingbats >>');

  Assert.AreEqual(string(Char($2701)), UnicodeOf(Font, 33));
  Assert.AreEqual(Single(974), Font.GetWidth(33));
end;

procedure TType1FontTests.TestEmbeddedType1BuiltInEncodingGivesUnicode;
begin
  const Font = OpenEmbeddedOpenSans;

  Assert.IsTrue(Font.IsEmbedded);
  Assert.IsFalse(Font.IsDamaged);
  Assert.AreEqual('A', UnicodeOf(Font, 65));

  const Reference = TTestFonts.ReferenceWidths(OpenSansFile);
  try
    const Matrix = Font.GetType1Font.FontMatrix;
    Assert.IsTrue(Length(Matrix) = 6);
    const Expected = Double(Reference['A']) * Matrix[0] * 1000;
    Assert.AreEqual(Expected, Double(Font.GetWidth(65)), 0.001);
  finally
    Reference.Free;
  end;
end;

procedure TType1FontTests.TestEmbeddedType1WithWrongLengthsIsRepaired;
begin
  var Segment1: TBytes;
  var Segment2: TBytes;
  const Data = OpenSansSegments(Segment1, Segment2);
  const Builder = TTextTestDocuments.NewBuilder(OpenSansFont, '');
  Builder.AddObject(20, OpenSansDescriptor);
  TTextTestDocuments.AddFontFile(Builder, 21, '/Length1 12 /Length2 99999999', Data);
  const Font = OpenBuilder(Builder);

  Assert.IsTrue(Font.IsEmbedded);
  Assert.IsFalse(Font.IsDamaged);
  Assert.AreEqual('A', UnicodeOf(Font, 65));
  Assert.IsTrue(FModels.HasLogLine('Length1'));
end;

procedure TType1FontTests.TestEmbeddedPfbInFontFile;
begin
  const Builder = TTextTestDocuments.NewBuilder(OpenSansFont, '');
  Builder.AddObject(20, OpenSansDescriptor);
  TTextTestDocuments.AddFontFile(Builder, 21, '/Length1 0 /Length2 0', TTestFonts.Bytes(OpenSansFile));
  const Font = OpenBuilder(Builder);

  Assert.IsTrue(Font.IsEmbedded);
  Assert.AreEqual('A', UnicodeOf(Font, 65));
end;

procedure TType1FontTests.TestDamagedEmbeddedType1FallsBack;
begin
  const Builder = TTextTestDocuments.NewBuilder('<< /Type /Font /Subtype /Type1 /BaseFont /Foo /FirstChar 65 /LastChar 66 ' +
                                                '/Widths [700 710] /FontDescriptor 20 0 R >>', '');
  Builder.AddObject(20, '<< /Type /FontDescriptor /FontName /Foo /Flags 32 /FontFile 21 0 R >>');
  TTextTestDocuments.AddFontFile(Builder, 21, '/Length1 1000 /Length2 1048', PatternBytes(2048));
  const Font = OpenBuilder(Builder);

  Assert.IsTrue(Font.IsDamaged);
  Assert.IsFalse(Font.IsEmbedded);
  Assert.AreEqual(Single(700), Font.GetWidth(65));
  Assert.AreEqual(Single(710), Font.GetWidth(66));
  Assert.IsTrue(FModels.HasLogLine('Type1 font'), 'the damaged font is logged');
  Assert.IsNotNull(Font.GetFontBoxFont, 'the mapper gives a substitute');
end;

procedure TType1FontTests.TestEmptyEmbeddedType1IsDamaged;
begin
  const Builder = TTextTestDocuments.NewBuilder('<< /Type /Font /Subtype /Type1 /BaseFont /Foo /FontDescriptor 20 0 R >>', '');
  Builder.AddObject(20, '<< /Type /FontDescriptor /FontName /Foo /Flags 32 /FontFile 21 0 R >>');
  TTextTestDocuments.AddFontFile(Builder, 21, '/Length1 0 /Length2 0', nil);
  const Font = OpenBuilder(Builder);

  Assert.IsTrue(Font.IsDamaged);
  Assert.IsFalse(Font.IsEmbedded);
end;

procedure TType1FontTests.TestNonEmbeddedNonStandardUsesMapper;
begin
  const Font = OpenFont('<< /Type /Font /Subtype /Type1 /BaseFont /Foo >>');

  Assert.IsFalse(Font.IsEmbedded);
  Assert.AreEqual(Double(666.9922), Double(Font.GetWidth(65)), 0.001);
  Assert.AreEqual('A', UnicodeOf(Font, 65));
  Assert.IsTrue(FModels.HasLogLine('fallback font'));
end;

procedure TType1FontTests.TestMissingBaseFontDoesNotFail;
begin
  const Font = OpenFont('<< /Type /Font /Subtype /Type1 >>');

  Assert.AreEqual('', Font.Name);
  Assert.IsTrue(Font.GetWidth(65) > 0);
  Assert.AreEqual('A', UnicodeOf(Font, 65));
end;

procedure TType1FontTests.TestUnknownCodeHasNoUnicode;
begin
  const Font = OpenFont(TTextTestDocuments.HelveticaF1);

  Assert.AreEqual(NoUnicode, UnicodeOf(Font, 1));
  Assert.AreEqual(NoUnicode, UnicodeOf(Font, 1000), 'a code beyond one byte is unknown too');
  Assert.AreEqual(NoUnicode, UnicodeOf(Font, -5));
  Assert.IsTrue(FModels.HasLogLine('No Unicode mapping'));
end;

procedure TType1FontTests.TestToUnicodeComesFirst;
begin
  const Builder = TTextTestDocuments.NewBuilder('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /ToUnicode 20 0 R >>', '');
  TTextTestDocuments.AddFontFile(Builder, 20, '', TEncoding.ASCII.GetBytes(
    '1 begincodespacerange <00> <FF> endcodespacerange 1 beginbfchar <41> <0042> endbfchar'));
  const Font = OpenBuilder(Builder);

  Assert.AreEqual('B', UnicodeOf(Font, 65));
  Assert.AreEqual('C', UnicodeOf(Font, 67), 'a code that the CMap does not have falls back to the encoding');
end;

procedure TType1FontTests.TestFontFile3OnType1WithoutCffIsLogged;
begin
  const Builder = TTextTestDocuments.NewBuilder('<< /Type /Font /Subtype /Bogus /BaseFont /Foo /FontDescriptor 20 0 R >>', '');
  Builder.AddObject(20, '<< /Type /FontDescriptor /FontName /Foo /Flags 32 /FontFile3 21 0 R >>');
  TTextTestDocuments.AddFontFile(Builder, 21, '/Subtype /Type1C', PatternBytes(10));
  // An unknown subtype is read as Type 1, which has no use for a CFF font file
  const WithFontFile3 = OpenAny(Builder);

  Assert.IsFalse(WithFontFile3.IsEmbedded);
  Assert.IsTrue(FModels.HasLogLine('/FontFile3 for Type1 font not supported'));
end;

procedure TType1FontTests.TestIsSymbolic;
begin
  Assert.IsFalse(OpenFont('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>').IsSymbolic);
  Assert.IsFalse(OpenFont('<< /Type /Font /Subtype /Type1 /BaseFont /Foo /Encoding /WinAnsiEncoding >>').IsSymbolic);
  Assert.IsTrue(OpenFont('<< /Type /Font /Subtype /Type1 /BaseFont /Foo /Encoding << /Differences [1 /fancy] >> >>').IsSymbolic);
  Assert.IsTrue(OpenFont('<< /Type /Font /Subtype /Type1 /BaseFont /ZapfDingbats >>').IsSymbolic);
end;

procedure TType1FontTests.TestReadCodeIsOneByte;
begin
  const Font = OpenFont(TTextTestDocuments.HelveticaF1);
  const Data: TBytes = [65, 66];

  var Position := 0;
  Assert.AreEqual(65, Font.ReadCode(Data, Position));
  Assert.AreEqual(1, Position);
  Assert.AreEqual(66, Font.ReadCode(Data, Position));
  Assert.AreEqual(-1, Font.ReadCode(Data, Position));
  Assert.AreEqual(2, Position);
end;

procedure TType1FontTests.TestFactoryTypesAndFallbacks;
begin
  Assert.IsTrue(OpenFont('<< /Type /Font /Subtype /MMType1 /BaseFont /Helvetica >>') is TPDType1Font);
  Assert.IsTrue(OpenFont('<< /Type /Font /BaseFont /Helvetica >>') is TPDType1Font, 'a missing subtype gives Type 1');
  Assert.IsTrue(OpenFont('<< /Type /Font /Subtype /Bogus /BaseFont /Helvetica >>') is TPDType1Font, 'an unknown subtype gives Type 1');
  Assert.IsTrue(FModels.HasLogLine('Invalid font subtype'));
  Assert.IsTrue(OpenFont('<< /Type /Foo /Subtype /Type1 /BaseFont /Helvetica >>') is TPDType1Font);
  Assert.IsTrue(FModels.HasLogLine('Expected ''Font'' dictionary'));
  FFonts.Clear;

  const Builder = TTextTestDocuments.NewBuilder('<< /Type /Font /Subtype /Type1 /BaseFont /Foo /FontDescriptor 20 0 R >>', '');
  Builder.AddObject(20, '<< /Type /FontDescriptor /FontName /Foo /Flags 32 /FontFile3 21 0 R >>');
  TTextTestDocuments.AddFontFile(Builder, 21, '/Subtype /Type1C', PatternBytes(10));
  var Font: TPDFont := nil;
  try
    const Document = FModels.Open(Builder);
    Font := TPDFontFactory.CreateFont(TTextTestDocuments.FontDictionary(Document, 'F1'), Document.Context);
    Assert.IsTrue(Font is TPDType1CFont, 'a /FontFile3 gives a Type 1C font');
    Assert.IsTrue(Font.IsDamaged);
  finally
    Font.Free;
    Builder.Free;
  end;

  const Unsupported = TTextTestDocuments.NewBuilder('<< /Type /Font /Subtype /Type3 >>', '');
  try
    const Document = FModels.Open(Unsupported);
    const Dictionary = TTextTestDocuments.FontDictionary(Document, 'F1');
    var Raised := False;
    try
      TPDFontFactory.CreateFont(Dictionary, Document.Context).Free;
    except
      on EPdfUnsupportedFeatureException do
      begin
        Raised := True;
      end;
    end;
    Assert.IsTrue(Raised, 'a Type 3 font is not supported yet');
  finally
    Unsupported.Free;
  end;
end;

procedure TType1FontTests.TestFactoryCachesPerDocument;
begin
  const Builder = TTextTestDocuments.NewBuilder(TTextTestDocuments.HelveticaF1, '');
  try
    const Document = FModels.Open(Builder);
    const Dictionary = TTextTestDocuments.FontDictionary(Document, 'F1');
    const First = TPDFontFactory.GetFont(Dictionary, Document.Context);
    const Second = TPDFontFactory.GetFont(Dictionary, Document.Context);

    Assert.AreSame(First, Second, 'a font dictionary is parsed once per document');
    Assert.AreEqual(Single(667), First.GetWidth(65));
  finally
    Builder.Free;
  end;
end;

procedure TType1FontTests.TestFactoryDefaultFont;
begin
  const Font = TPDFontFactory.CreateDefaultFont(nil);
  try
    Assert.AreEqual('Helvetica', Font.Name);
    Assert.AreEqual(Single(667), Font.GetWidth(65));
    Assert.AreEqual(string(Char($20AC)), UnicodeOf(Font, 128));
  finally
    Font.Free;
  end;
end;

procedure TType1FontTests.TestSharedMapperFontIsNotFreed;
begin
  // Two fonts that get the same substitute: freeing one must leave the other working
  const First = OpenFont('<< /Type /Font /Subtype /Type1 /BaseFont /Foo >>');
  const Second = OpenFont('<< /Type /Font /Subtype /Type1 /BaseFont /Bar >>');
  Assert.AreSame(First.GetFontBoxFont, Second.GetFontBoxFont);
  FFonts.Delete(0);

  Assert.AreEqual(Double(666.9922), Double(Second.GetWidth(65)), 0.001);
end;

end.
