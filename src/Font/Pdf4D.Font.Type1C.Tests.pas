// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
unit Pdf4D.Font.Type1C.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Font.Type1C,
  Pdf4D.Model.Tests.Support,
  Pdf4D.Tests.PdfBuilder;

type
  [TestFixture]
  TType1CFontTests = class
  private
    FModels: TModelTestDocuments;
    FFonts: TObjectList<TPDType1CFont>;

    function OpenFont(const FontFileDictionary: string; const FontFile: TBytes): TPDType1CFont;
    function OpenSourceSans: TPDType1CFont;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestType1C;

    [Test]
    procedure TestType1CUnicodeAndEncoding;

    [Test]
    procedure TestEmptyFontFileIsLoggedAndFallsBack;

    [Test]
    procedure TestDamagedFontFileFallsBack;

    [Test]
    procedure TestAverageWidth;
  end;

implementation

uses
  Pdf4D.Font.Factory,
  Pdf4D.Font.GlyphList,
  Pdf4D.Tests.TestFonts,
  Pdf4D.Tests.TextDocuments;

const
  SourceSansFile = 'SourceSansProBold.otf';
  Type1CFont = '<< /Type /Font /Subtype /Type1 /BaseFont /SourceSansPro-Bold /FontDescriptor 20 0 R >>';

{ TType1CFontTests }

procedure TType1CFontTests.Setup;
begin
  FModels := TModelTestDocuments.Create;
  FFonts := TObjectList<TPDType1CFont>.Create(True);
end;

procedure TType1CFontTests.TearDown;
begin
  FreeAndNil(FFonts);
  FreeAndNil(FModels);
end;

function TType1CFontTests.OpenFont(const FontFileDictionary: string; const FontFile: TBytes): TPDType1CFont;
begin
  const Builder = TTextTestDocuments.NewBuilder(Type1CFont, '');
  try
    Builder.AddObject(20, '<< /Type /FontDescriptor /FontName /SourceSansPro-Bold /Flags 32 /FontFile3 21 0 R >>');
    TTextTestDocuments.AddFontFile(Builder, 21, FontFileDictionary, FontFile);
    const Document = FModels.Open(Builder);
    Result := TPDFontFactory.CreateFont(TTextTestDocuments.FontDictionary(Document, 'F1'), Document.Context) as TPDType1CFont;
    FFonts.Add(Result);
  finally
    Builder.Free;
  end;
end;

function TType1CFontTests.OpenSourceSans: TPDType1CFont;
begin
  Result := OpenFont('/Subtype /Type1C', TTestFonts.Bytes(SourceSansFile));
end;

procedure TType1CFontTests.TestType1C;
begin
  const Font = OpenSourceSans;

  Assert.IsTrue(Font.IsEmbedded);
  Assert.IsFalse(Font.IsDamaged);
  Assert.IsNotNull(Font.GetCFFType1Font);

  const Reference = TTestFonts.ReferenceWidths(SourceSansFile);
  try
    const GID = Font.GetCFFType1Font.NameToGID('A');
    Assert.IsTrue(GID > 0);
    const Matrix = Font.GetFontMatrix;
    const Expected = Double(Reference['gid' + IntToStr(GID)]) * Matrix.GetValue(0, 0) * 1000;
    Assert.AreEqual(Expected, Double(Font.GetWidth(65)), 0.001);
  finally
    Reference.Free;
  end;
end;

procedure TType1CFontTests.TestType1CUnicodeAndEncoding;
var
  Value: string;
begin
  const Font = OpenSourceSans;

  Assert.IsTrue(Font.TryToUnicode(65, TGlyphList.TextExtraction, Value));
  Assert.AreEqual('A', Value);
  Assert.IsTrue(Font.GetCFFType1Font.HasGlyph('A'));
  Assert.AreEqual('A', Font.CodeToName(65));
end;

procedure TType1CFontTests.TestEmptyFontFileIsLoggedAndFallsBack;
begin
  const Font = OpenFont('/Subtype /Type1C', nil);

  Assert.IsFalse(Font.IsEmbedded);
  Assert.IsFalse(Font.IsDamaged, 'PDFBox only logs an empty font file');
  Assert.IsTrue(FModels.HasLogLine('Invalid data for embedded Type1C font'));
  Assert.IsTrue(Font.GetWidthFromFont(65) > 0);
end;

procedure TType1CFontTests.TestDamagedFontFileFallsBack;
begin
  var Garbage: TBytes;
  SetLength(Garbage, 3000);
  for var Index := 0 to High(Garbage) do
  begin
    Garbage[Index] := Byte((Index * 131) + 7);
  end;
  const Font = OpenFont('/Subtype /Type1C', Garbage);

  Assert.IsFalse(Font.IsEmbedded);
  Assert.IsTrue(Font.IsDamaged);
  Assert.IsTrue(FModels.HasLogLine('Type1C font'));
  Assert.IsTrue(Font.GetWidthFromFont(65) > 0, 'the font mapper gives a substitute');
end;

procedure TType1CFontTests.TestAverageWidth;
begin
  Assert.AreEqual(Single(500), OpenSourceSans.GetAverageFontWidth);
end;

end.
