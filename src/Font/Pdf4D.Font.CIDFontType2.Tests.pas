// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
unit Pdf4D.Font.CIDFontType2.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Font.CIDFontType2,
  Pdf4D.Font.Type0,
  Pdf4D.Model.Tests.Support,
  Pdf4D.Tests.PdfBuilder;

type
  // CIDFontType2 descendants that are damaged or not embedded: the font program comes from the font mapper
  [TestFixture]
  TCIDFontType2FallbackTests = class
  private
    FModels: TModelTestDocuments;
    FFonts: TObjectList<TPDType0Font>;

    class function Type0Body(const DescendantObject: Integer): string; static;
    class function DescendantBody(const Entries: string): string; static;
    function NewBuilder(const DescendantEntries: string): TTestPdfBuilder;
    procedure AddToUnicode(const Builder: TTestPdfBuilder);
    function OpenFonts(const Builder: TTestPdfBuilder; const Count: Integer): TArray<TPDType0Font>;
    function CountLogLines(const Fragment: string): Integer;
    class function Descendant(const Font: TPDType0Font): TPDCIDFontType2; static;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestDamagedFontFile2FallsBackWithALogLine;

    [Test]
    procedure TestNonEmbeddedFontMapsThroughTheSubstituteCmap;

    [Test]
    procedure TestSameFontUsesCIDToGIDMapAndWarnsOncePerFont;

    [Test]
    procedure TestTwoFontsShareOneSubstituteAndNeitherFreesIt;
  end;

implementation

uses
  System.Classes,
  Pdf4D.Font.Factory,
  Pdf4D.Tests.TestFonts,
  Pdf4D.Tests.TextDocuments;

const
  ToUnicodeObject = 14;
  FirstDescendantObject = 12;
  CapitalAGlyph = 36;
  CapitalACode = $24;
  CMapStart = '/CIDInit /ProcSet findresource begin 12 dict begin begincmap /CMapName /Test def /CMapType 2 def ';
  CMapEnd = 'endcmap CMapName currentdict /CMap defineresource pop end end';
  CapitalAToUnicode = CMapStart + '1 begincodespacerange <0000> <FFFF> endcodespacerange 1 beginbfchar <0024> <0041> endbfchar ' + CMapEnd;

{ TCIDFontType2FallbackTests }

procedure TCIDFontType2FallbackTests.Setup;
begin
  FModels := TModelTestDocuments.Create;
  FFonts := TObjectList<TPDType0Font>.Create(True);
end;

procedure TCIDFontType2FallbackTests.TearDown;
begin
  FreeAndNil(FFonts);
  FreeAndNil(FModels);
end;

class function TCIDFontType2FallbackTests.Type0Body(const DescendantObject: Integer): string;
begin
  Result := Format('<< /Type /Font /Subtype /Type0 /BaseFont /LiberationSans /Encoding /Identity-H /ToUnicode %d 0 R ' +
                   '/DescendantFonts [ %d 0 R ] >>', [ToUnicodeObject, DescendantObject]);
end;

class function TCIDFontType2FallbackTests.DescendantBody(const Entries: string): string;
begin
  Result := Format('<< /Type /Font /Subtype /CIDFontType2 /BaseFont /LiberationSans /FontDescriptor 20 0 R ' +
                   '/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> %s >>', [Entries]);
end;

function TCIDFontType2FallbackTests.NewBuilder(const DescendantEntries: string): TTestPdfBuilder;
begin
  // F1 and F2 are the Type 0 fonts, objects 12 and 13 are their descendants
  const Separator = TTextTestDocuments.Separator;
  const Bodies = Type0Body(FirstDescendantObject) + Separator + Type0Body(FirstDescendantObject + 1) + Separator +
                 DescendantBody(DescendantEntries) + Separator + DescendantBody(DescendantEntries);
  Result := TTextTestDocuments.NewBuilder(Bodies, '');
end;

procedure TCIDFontType2FallbackTests.AddToUnicode(const Builder: TTestPdfBuilder);
begin
  Builder.AddStreamObject(ToUnicodeObject, '', TEncoding.ASCII.GetBytes(CapitalAToUnicode));
end;

function TCIDFontType2FallbackTests.OpenFonts(const Builder: TTestPdfBuilder; const Count: Integer): TArray<TPDType0Font>;
begin
  try
    const Document = FModels.Open(Builder);
    SetLength(Result, Count);
    for var Index := 0 to Count - 1 do
    begin
      const Dictionary = TTextTestDocuments.FontDictionary(Document, Format('F%d', [Index + 1]));
      Result[Index] := TPDFontFactory.CreateFont(Dictionary, Document.Context) as TPDType0Font;
      FFonts.Add(Result[Index]);
    end;
  finally
    Builder.Free;
  end;
end;

function TCIDFontType2FallbackTests.CountLogLines(const Fragment: string): Integer;
begin
  Result := 0;
  for var Line in FModels.LogLines do
  begin
    if Line.Contains(Fragment) then
    begin
      Inc(Result);
    end;
  end;
end;

class function TCIDFontType2FallbackTests.Descendant(const Font: TPDType0Font): TPDCIDFontType2;
begin
  Result := Font.DescendantFont as TPDCIDFontType2;
end;

procedure TCIDFontType2FallbackTests.TestDamagedFontFile2FallsBackWithALogLine;
begin
  var Garbage: TBytes;
  SetLength(Garbage, 3000);
  for var Index := 0 to High(Garbage) do
  begin
    Garbage[Index] := Byte((Index * 131) + 7);
  end;
  const Builder = NewBuilder('/W [36 [600]]');
  Builder.AddObject(20, '<< /Type /FontDescriptor /FontName /LiberationSans /Flags 4 /FontFile2 21 0 R >>');
  TTextTestDocuments.AddFontFile(Builder, 21, '/Length1 1', Garbage);
  AddToUnicode(Builder);

  const Font = OpenFonts(Builder, 1)[0];

  Assert.IsTrue(Descendant(Font).IsDamaged);
  Assert.IsFalse(Descendant(Font).IsEmbedded);
  Assert.IsTrue(FModels.HasLogLine('Could not read embedded OTF'), 'the damaged font is logged');
  Assert.AreEqual(Double(600), Double(Font.GetWidth(CapitalACode)), 0.0001, '/W still decides');
  Assert.IsNotNull(Descendant(Font).GetTrueTypeFont, 'the mapper gives a substitute');
  Assert.IsTrue(Descendant(Font).GetWidthFromFont(CapitalACode) > 0);
end;

procedure TCIDFontType2FallbackTests.TestNonEmbeddedFontMapsThroughTheSubstituteCmap;
begin
  const Builder = NewBuilder('');
  Builder.AddObject(20, '<< /Type /FontDescriptor /FontName /LiberationSans /Flags 4 >>');
  AddToUnicode(Builder);

  const Font = OpenFonts(Builder, 1)[0];

  Assert.IsFalse(Descendant(Font).IsEmbedded);
  Assert.IsFalse(Descendant(Font).IsDamaged);
  // The code maps to "A" in the ToUnicode CMap and "A" to its glyph in the cmap of the substitute
  Assert.AreEqual(CapitalAGlyph, Descendant(Font).CodeToGID(CapitalACode));
  Assert.IsTrue(Descendant(Font).GetWidthFromFont(CapitalACode) > 0);
end;

procedure TCIDFontType2FallbackTests.TestSameFontUsesCIDToGIDMapAndWarnsOncePerFont;
begin
  const Builder = NewBuilder('/CIDToGIDMap 15 0 R');
  Builder.AddObject(20, '<< /Type /FontDescriptor /FontName /LiberationSans /Flags 4 >>');
  AddToUnicode(Builder);
  // CID 36 (the code of "A") maps to glyph 40, which the cmap of the substitute would never give
  var GlyphMap: TBytes;
  SetLength(GlyphMap, 2 * (CapitalACode + 2));
  GlyphMap[2 * CapitalACode + 1] := 40;
  Builder.AddStreamObject(15, '', GlyphMap);

  const Font = OpenFonts(Builder, 1)[0];

  Assert.AreEqual(40, Descendant(Font).CodeToGID(CapitalACode), 'the CIDToGIDMap is used for the same font');
  Descendant(Font).CodeToGID(CapitalACode);
  Descendant(Font).CodeToGID(CapitalACode + 1);
  Assert.AreEqual(1, CountLogLines('Using non-embedded GIDs'));
end;

procedure TCIDFontType2FallbackTests.TestTwoFontsShareOneSubstituteAndNeitherFreesIt;
begin
  const Builder = NewBuilder('');
  Builder.AddObject(20, '<< /Type /FontDescriptor /FontName /LiberationSans /Flags 4 >>');
  AddToUnicode(Builder);
  const Fonts = OpenFonts(Builder, 2);
  const Second = Fonts[1];

  Assert.AreSame(Descendant(Fonts[0]).GetTrueTypeFont, Descendant(Second).GetTrueTypeFont);
  FFonts.Delete(0);

  Assert.AreEqual(CapitalAGlyph, Descendant(Second).CodeToGID(CapitalACode), 'the substitute is still there');
end;

end.
