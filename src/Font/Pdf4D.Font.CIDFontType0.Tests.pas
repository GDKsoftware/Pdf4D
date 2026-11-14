// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
unit Pdf4D.Font.CIDFontType0.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Font.CIDFontType0,
  Pdf4D.Font.Type0,
  Pdf4D.Model.Tests.Support;

type
  [TestFixture]
  TCIDFontType0Tests = class
  private
    FModels: TModelTestDocuments;
    FFonts: TObjectList<TPDType0Font>;

    function OpenFont(const DescendantEntries: string; const FontFile: TBytes; const FontFileDictionary: string = '/Subtype /CIDFontType0C'): TPDCIDFontType0;
    function CidFile: TBytes;
    class function Ascii(const Text: string): TBytes; static;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestCidFontType0FromCff;

    [Test]
    procedure TestWidthWithoutWArrayComesFromCharstring;

    [Test]
    procedure TestType1CffInCidContainerUsesCidAsGlyph;

    [Test]
    procedure TestNonEmbeddedFontUsesMapperSubstitute;

    [Test]
    procedure TestPfbInsteadOfCffIsDamagedAndFallsBack;

    [Test]
    procedure TestDamagedCffIsLoggedAndFallsBack;

    [Test]
    procedure TestFontMatrixAverageWidthAndEncode;

    [Test]
    procedure TestHugeFontMatrixGivesNoWidthInsteadOfAnException;

    [Test]
    procedure TestCidZeroIsNotdef;
  end;

implementation

uses
  Pdf4D.Common.Matrix,
  Pdf4D.Font.Factory,
  Pdf4D.FontBox.Cff.Font,
  Pdf4D.Tests.CffBuilder,
  Pdf4D.Tests.TextDocuments;

const
  Type0Entries = '<< /Type /Font /Subtype /Type0 /BaseFont /TestCff /DescendantFonts [ 11 0 R ] /Encoding /Identity-H >>';
  DescendantStart = '<< /Type /Font /Subtype /CIDFontType0 /BaseFont /TestCff ' +
                    '/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /FontDescriptor 20 0 R ';

{ TCIDFontType0Tests }

procedure TCIDFontType0Tests.Setup;
begin
  FModels := TModelTestDocuments.Create;
  FFonts := TObjectList<TPDType0Font>.Create(True);
end;

procedure TCIDFontType0Tests.TearDown;
begin
  FreeAndNil(FFonts);
  FreeAndNil(FModels);
end;

class function TCIDFontType0Tests.Ascii(const Text: string): TBytes;
begin
  Result := TEncoding.ASCII.GetBytes(Text);
end;

function TCIDFontType0Tests.CidFile: TBytes;
begin
  Result := TCffTestBuilder.CidKeyed('Adobe', 'Identity', 0, [1, 2], [480, 520]);
end;

function TCIDFontType0Tests.OpenFont(const DescendantEntries: string; const FontFile: TBytes; const FontFileDictionary: string): TPDCIDFontType0;
begin
  const Builder = TTextTestDocuments.NewBuilder(Type0Entries + TTextTestDocuments.Separator + DescendantStart + DescendantEntries + ' >>', '');
  try
    Builder.AddObject(20, '<< /Type /FontDescriptor /FontName /TestCff /Flags 4 /FontFile3 21 0 R >>');
    TTextTestDocuments.AddFontFile(Builder, 21, FontFileDictionary, FontFile);
    const Document = FModels.Open(Builder);
    const Type0 = TPDFontFactory.CreateFont(TTextTestDocuments.FontDictionary(Document, 'F1'), Document.Context) as TPDType0Font;
    FFonts.Add(Type0);
    Result := Type0.DescendantFont as TPDCIDFontType0;
  finally
    Builder.Free;
  end;
end;

procedure TCIDFontType0Tests.TestCidFontType0FromCff;
begin
  const Font = OpenFont('/W [1 [600]]', CidFile);

  Assert.IsTrue(Font.IsEmbedded);
  Assert.IsFalse(Font.IsDamaged);
  Assert.IsNotNull(Font.GetCIDKeyedFont);
  Assert.AreEqual(1, Font.CodeToCID(1));
  Assert.AreEqual(1, Font.CodeToGID(1));
  Assert.AreEqual(2, Font.CodeToGID(2));
  Assert.AreEqual(Double(600), Double(Font.GetWidth(1)), 0.0001, '/W wins over the charstring');
  Assert.AreEqual(Double(480), Double(Font.GetWidthFromFont(1)), 0.0001);
end;

procedure TCIDFontType0Tests.TestWidthWithoutWArrayComesFromCharstring;
begin
  const Font = OpenFont('', CidFile);

  Assert.AreEqual(Double(520), Double(Font.GetWidthFromFont(2)), 0.0001);
  Assert.AreEqual(Double(1000), Double(Font.GetWidth(2)), 0.0001, '/DW is the default width');
end;

procedure TCIDFontType0Tests.TestType1CffInCidContainerUsesCidAsGlyph;
begin
  const Font = OpenFont('', TCffTestBuilder.Type1Font(TCffType1Options.Standard));

  Assert.IsTrue(Font.IsEmbedded);
  Assert.IsNull(Font.GetCIDKeyedFont);
  Assert.IsTrue(Font.GetFontBoxFont is TCFFType1Font);
  Assert.AreEqual(2, Font.CodeToGID(2), 'the CID is the glyph');
  Assert.AreEqual(Double(500), Double(Font.GetWidthFromFont(1)), 0.0001, 'the default width of the font');
end;

procedure TCIDFontType0Tests.TestNonEmbeddedFontUsesMapperSubstitute;
begin
  const Font = OpenFont('', nil, '');

  Assert.IsFalse(Font.IsEmbedded);
  Assert.IsNull(Font.GetCIDKeyedFont);
  Assert.IsNotNull(Font.GetFontBoxFont);
  Assert.IsTrue(FModels.HasLogLine('fallback'));
  const NotdefWidth = Double(Font.GetFontBoxFont.GetWidth('.notdef')) * Font.GetFontMatrix.ScaleX * 1000;
  Assert.AreEqual(NotdefWidth, Double(Font.GetWidthFromFont(1)), 0.001, 'no ToUnicode gives .notdef, scaled by the font matrix');
end;

procedure TCIDFontType0Tests.TestPfbInsteadOfCffIsDamagedAndFallsBack;
begin
  const Font = OpenFont('', Ascii('%!PS-AdobeFont-1.0: TestCff'));

  Assert.IsTrue(Font.IsDamaged);
  Assert.IsFalse(Font.IsEmbedded);
  Assert.IsTrue(FModels.HasLogLine('Found PFB'));
  Assert.IsTrue(Font.GetWidthFromFont(1) >= 0);
end;

procedure TCIDFontType0Tests.TestDamagedCffIsLoggedAndFallsBack;
begin
  var Data := CidFile;
  SetLength(Data, 40);

  const Font = OpenFont('', Data);

  Assert.IsTrue(Font.IsDamaged);
  Assert.IsFalse(Font.IsEmbedded);
  Assert.IsTrue(FModels.HasLogLine('embedded CFF'));
  Assert.IsTrue(Font.GetWidthFromFont(1) >= 0);
end;

procedure TCIDFontType0Tests.TestFontMatrixAverageWidthAndEncode;
var
  Bytes: TBytes;
begin
  const Font = OpenFont('', CidFile);

  Assert.AreEqual(Double(0.001), Double(Font.GetFontMatrix.ScaleX), 0.000001);
  Assert.AreEqual(Double(500), Double(Font.GetAverageFontWidth), 0);
  Assert.IsFalse(Font.TryEncode(65, Bytes));
  Assert.IsTrue(Length(Bytes) = 0);
end;

procedure TCIDFontType0Tests.TestHugeFontMatrixGivesNoWidthInsteadOfAnException;
begin
  // 1e35 * 480 * 1000 is beyond a Single; PDFBox goes on with an infinity
  const Huge = TCffTestBuilder.RealOperand([$1, $B, $3, $5, $F]);
  const Zero = TCffTestBuilder.Bytes([$8B]);
  var Options := TCffCidOptions.Standard;
  Options.CIDs := [1];
  Options.Widths := [480];
  Options.ExtraTopDict := TCffTestBuilder.Concat([Huge, Zero, Zero, Huge, Zero, Zero, TCffTestBuilder.Bytes([12, 7])]);
  const Font = OpenFont('', TCffTestBuilder.CidFont(Options));

  Assert.IsTrue(Font.IsEmbedded);
  Assert.AreEqual(Double(0), Double(Font.GetWidthFromFont(1)), 0, 'no width instead of an infinity');
  Assert.IsTrue(FModels.HasLogLine('out of range'));
end;

procedure TCIDFontType0Tests.TestCidZeroIsNotdef;
begin
  const Font = OpenFont('', CidFile);

  Assert.AreEqual(Double(1000), Double(Font.GetWidth(0)), 0.0001);
  Assert.AreEqual(0, Font.CodeToGID(0));
  Assert.IsTrue(Font.GetWidthFromFont(0) >= 0);
end;
end.
