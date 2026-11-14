// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
unit Pdf4D.Font.Type3.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Font.Base,
  Pdf4D.Font.Type3,
  Pdf4D.Model.Tests.Support;

type
  [TestFixture]
  TType3FontTests = class
  private
    FModels: TModelTestDocuments;
    FFonts: TObjectList<TPDFont>;

    function OpenFont(const FontEntries: string; const CharProcs: array of string): TPDType3Font;
    function OpenFontBody(const FontBody: string; const CharProcs: array of string): TPDFont;
    function AllGlyphsFontEntries(const Count: Integer): string;
    class function Ascii(const Text: string): TBytes; static;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestType3WidthsAndMatrix;

    [Test]
    procedure TestWidthsWithoutLastCharAreNotUsed;

    [Test]
    procedure TestType3WidthFromCharProc;

    [Test]
    procedure TestType3DifferencesUnicode;

    [Test]
    procedure TestUnknownSubtypeBecomesType1;

    [Test]
    procedure TestFactoryMakesType3Font;

    [Test]
    procedure TestWidthBeyondWidthsArrayIsZero;

    [Test]
    procedure TestHugeFirstAndLastCharDoNotOverflow;

    [Test]
    procedure TestMissingWidthOfDescriptorWins;

    [Test]
    [TestCase('TooShort', '/FontMatrix [0.5 0 0 0.5 0]')]
    [TestCase('NotANumber', '/FontMatrix [0.5 0 0 /Name 0 0]')]
    [TestCase('TooLong', '/FontMatrix [0.5 0 0 0.5 0 0 1]')]
    procedure TestFontMatrixThatIsNotSixNumbersGivesDefault(const MatrixEntry: string);

    [Test]
    procedure TestZeroFontMatrixGivesZeroDisplacement;

    [Test]
    procedure TestHugeFontMatrixGivesZeroDisplacement;

    [Test]
    procedure TestCharProcWithoutWidthOperatorGivesZeroAndWarning;

    [Test]
    procedure TestEmptyCharProcGivesZeroWithoutWarning;

    [Test]
    procedure TestCharProcOfD1;

    [Test]
    procedure TestCharProcsResourcesAndEncoding;

    [Test]
    procedure TestCharProcResourcesOfItsOwnWin;

    [Test]
    procedure TestBoundingBoxFromFontBBox;

    [Test]
    procedure TestBoundingBoxFromGlyphsWhenFontBBoxIsZero;

    [Test]
    procedure TestHugeNumberOfCharProcsIsBounded;

    [Test]
    procedure TestFlateBombGlyphProcedureSharedByAllCodesIsReadOnce;

    [Test]
    [TestCase('HalfOfBoundingBox', '/FontBBox [0 0 10 80] /CapHeight 5,40')]
    [TestCase('CapHeight', '/CapHeight 5 /Ascent 9,5')]
    [TestCase('Ascent', '/Ascent 9 /XHeight 7,9')]
    [TestCase('XHeightMinusDescent', '/XHeight 7 /Descent -2,9')]
    procedure TestHeightFromDescriptor(const DescriptorEntries: string; const Expected: Integer);

    [Test]
    procedure TestHeightWithoutDescriptorIsZero;

    [Test]
    procedure TestType3FontProperties;
  end;

implementation

uses
  System.Classes,
  System.Diagnostics,
  Pdf4D.Filter.Tests.Support,
  Pdf4D.Common.Defines,
  Pdf4D.Common.Matrix,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Font.Factory,
  Pdf4D.Font.Type1,
  Pdf4D.Model.Rectangle,
  Pdf4D.Tests.TextDocuments;

const
  FontStart = '<< /Type /Font /Subtype /Type3 /FontBBox [0 0 100 100] ';
  GlyphA = '/Encoding << /Differences [65 /A] >> /CharProcs << /A 30 0 R >> ';

{ TType3FontTests }

procedure TType3FontTests.Setup;
begin
  FModels := TModelTestDocuments.Create;
  FFonts := TObjectList<TPDFont>.Create(True);
end;

procedure TType3FontTests.TearDown;
begin
  FreeAndNil(FFonts);
  FreeAndNil(FModels);
end;

class function TType3FontTests.Ascii(const Text: string): TBytes;
begin
  Result := TEncoding.ASCII.GetBytes(Text);
end;

// The glyph procedures are the objects 30 and up
function TType3FontTests.OpenFontBody(const FontBody: string; const CharProcs: array of string): TPDFont;
begin
  const Builder = TTextTestDocuments.NewBuilder(FontBody, '');
  try
    for var Index := 0 to High(CharProcs) do
    begin
      Builder.AddStreamObject(30 + Index, '', Ascii(CharProcs[Index]));
    end;
    const Document = FModels.Open(Builder);
    Result := TPDFontFactory.CreateFont(TTextTestDocuments.FontDictionary(Document, 'F1'), Document.Context);
    FFonts.Add(Result);
  finally
    Builder.Free;
  end;
end;

function TType3FontTests.OpenFont(const FontEntries: string; const CharProcs: array of string): TPDType3Font;
begin
  Result := OpenFontBody(FontStart + FontEntries + ' >>', CharProcs) as TPDType3Font;
end;

function TType3FontTests.AllGlyphsFontEntries(const Count: Integer): string;
begin
  const Entries = TStringBuilder.Create;
  try
    Entries.Append('/FontBBox [0 0 0 0] /Encoding << /Differences [65 /G0] >> /CharProcs << ');
    for var Index := 0 to Count - 1 do
    begin
      Entries.AppendFormat('/G%d 30 0 R ', [Index]);
    end;
    Entries.Append('>>');
    Result := Entries.ToString;
  finally
    Entries.Free;
  end;
end;

procedure TType3FontTests.TestType3WidthsAndMatrix;
begin
  const Font = OpenFont('/FontMatrix [0.01 0 0 0.01 0 0] /FirstChar 65 /LastChar 65 /Widths [50]', []);

  Assert.AreEqual(Double(50), Double(Font.GetWidth(65)), 0.0001);
  Assert.AreEqual(Double(0.01), Double(Font.GetFontMatrix.ScaleX), 0.000001);
  Assert.IsTrue(Font.HasExplicitWidth(65));
  const Displacement = Font.GetDisplacement(65);
  Assert.AreEqual(Double(0.5), Double(Displacement.X), 0.000001, 'the width goes through the font matrix, not through 1/1000');
  Assert.AreEqual(Double(0), Double(Displacement.Y), 0.000001);
end;

procedure TType3FontTests.TestWidthsWithoutLastCharAreNotUsed;
begin
  // PDFBox reads /LastChar with the default -1, so no code is in range: the width comes from the glyph procedure, and there is none
  const Font = OpenFont('/FirstChar 65 /Widths [50]', []);

  Assert.AreEqual(Double(0), Double(Font.GetWidth(65)), 0.0001);
end;

procedure TType3FontTests.TestType3WidthFromCharProc;
begin
  const Font = OpenFont(GlyphA, ['70 0 d0']);

  Assert.AreEqual(Double(70), Double(Font.GetWidthFromFont(65)), 0.0001);
  Assert.AreEqual(Double(70), Double(Font.GetWidth(65)), 0.0001, 'without /Widths the glyph procedure gives the width');
  Assert.AreEqual(Double(0), Double(Font.GetWidthFromFont(66)), 0.0001, 'a code without a glyph procedure');
  Assert.AreEqual(Double(0.07), Double(Font.GetDisplacement(65).X), 0.000001);
end;

procedure TType3FontTests.TestType3DifferencesUnicode;
var
  Value: string;
begin
  const Font = OpenFont('/Encoding << /Differences [65 /B] >>', []);

  Assert.IsTrue(Font.TryToUnicode(65, Value));
  Assert.AreEqual('B', Value);
  Assert.AreEqual('B', Font.CodeToName(65));
end;

procedure TType3FontTests.TestUnknownSubtypeBecomesType1;
begin
  const Font = OpenFontBody('<< /Type /Font /Subtype /Foo /BaseFont /Helvetica >>', []);

  Assert.IsTrue(Font is TPDType1Font);
  Assert.IsTrue(FModels.HasLogLine('Invalid font subtype'));
end;

procedure TType3FontTests.TestFactoryMakesType3Font;
begin
  const Font = OpenFont('', []);

  Assert.AreEqual('Type3', Font.SubType);
  Assert.IsTrue(Font.IsEmbedded);
  Assert.IsFalse(Font.IsDamaged);
  Assert.IsFalse(Font.IsStandard14);
  Assert.IsFalse(Font.IsSymbolic);
  Assert.IsFalse(Font.IsVertical);
  Assert.WillRaise(
    procedure
    begin
      Font.GetFontBoxFont;
    end,
    EPdfUnsupportedFeatureException);
end;

procedure TType3FontTests.TestWidthBeyondWidthsArrayIsZero;
begin
  const Font = OpenFont('/FirstChar 65 /LastChar 70 /Widths [50]', []);

  Assert.AreEqual(Double(50), Double(Font.GetWidth(65)), 0.0001);
  Assert.AreEqual(Double(0), Double(Font.GetWidth(66)), 0.0001, 'in the range of /FirstChar and /LastChar, beyond /Widths');
  Assert.IsFalse(Font.HasExplicitWidth(66));
end;

procedure TType3FontTests.TestHugeFirstAndLastCharDoNotOverflow;
begin
  const Font = OpenFont('/FirstChar -2147483648 /LastChar 2147483647 /Widths [1 2 3]', []);

  Assert.AreEqual(Double(0), Double(Font.GetWidth(65)), 0.0001);
  Assert.AreEqual(Double(0), Double(Font.GetWidth(2147483647)), 0.0001);
  Assert.AreEqual(Double(1), Double(Font.GetWidth(-2147483648)), 0.0001);
end;

procedure TType3FontTests.TestMissingWidthOfDescriptorWins;
begin
  const Font = OpenFont(GlyphA + '/FontDescriptor << /Type /FontDescriptor /FontName /T3 /Flags 4 /MissingWidth 33 >>', ['70 0 d0']);

  Assert.AreEqual(Double(33), Double(Font.GetWidth(65)), 0.0001, 'a descriptor means /MissingWidth, not the glyph procedure');
end;

procedure TType3FontTests.TestFontMatrixThatIsNotSixNumbersGivesDefault(const MatrixEntry: string);
begin
  const Font = OpenFont(MatrixEntry, []);

  Assert.AreEqual(Double(0.001), Double(Font.GetFontMatrix.ScaleX), 0.000001);
end;
procedure TType3FontTests.TestZeroFontMatrixGivesZeroDisplacement;
begin
  const Font = OpenFont('/FontMatrix [0 0 0 0 0 0] /FirstChar 65 /LastChar 65 /Widths [50]', []);

  const Displacement = Font.GetDisplacement(65);
  Assert.AreEqual(Double(0), Double(Displacement.X), 0);
  Assert.AreEqual(Double(0), Double(Displacement.Y), 0);
  Assert.AreEqual(Double(50), Double(Font.GetWidth(65)), 0.0001);
end;

procedure TType3FontTests.TestHugeFontMatrixGivesZeroDisplacement;
begin
  const Huge = '100000000000000000000000000000000000000.0';
  const Font = OpenFont(Format('/FontMatrix [%s 0 0 %s 0 0] /FirstChar 65 /LastChar 65 /Widths [50]', [Huge, Huge]), []);

  const Displacement = Font.GetDisplacement(65);
  Assert.AreEqual(Double(0), Double(Displacement.X), 0);
  Assert.IsTrue(FModels.HasLogLine('out of range'));
end;

procedure TType3FontTests.TestCharProcWithoutWidthOperatorGivesZeroAndWarning;
begin
  const Font = OpenFont(GlyphA, ['1 0 0 rg 10 10 m']);

  Assert.AreEqual(Double(0), Double(Font.GetWidthFromFont(65)), 0);
  Assert.IsTrue(FModels.HasLogLine('glyph procedure'));
end;

procedure TType3FontTests.TestEmptyCharProcGivesZeroWithoutWarning;
begin
  const Font = OpenFont(GlyphA, ['']);

  Assert.AreEqual(Double(0), Double(Font.GetWidthFromFont(65)), 0);
  Assert.IsFalse(FModels.HasLogLine('glyph procedure'));
end;

procedure TType3FontTests.TestCharProcOfD1;
begin
  const Font = OpenFont(GlyphA, ['  % comment' + #10 + '80 0 -5 -6 30 40 d1 0 0 m']);
  var Stream: TCosStream;
  var Box: TPdfRectangle;
  Assert.IsTrue(Font.TryGetCharProc(65, Stream));

  const CharProc = TPDType3CharProc.Create(Font, Stream);
  try
    var Width: Single;
    Assert.IsTrue(CharProc.TryGetWidth(Width));
    Assert.AreEqual(Double(80), Double(Width), 0);
    Assert.IsTrue(CharProc.TryGetGlyphBBox(Box));
    Assert.AreEqual(Double(-5), Double(Box.LowerLeftX), 0);
    Assert.AreEqual(Double(-6), Double(Box.LowerLeftY), 0);
    Assert.AreEqual(Double(30), Double(Box.UpperRightX), 0);
    Assert.AreEqual(Double(40), Double(Box.UpperRightY), 0);
  finally
    CharProc.Free;
  end;
end;

procedure TType3FontTests.TestCharProcsResourcesAndEncoding;
var
  CharProcs: TCosDictionary;
  CharProc: TCosStream;
  Resources: TCosDictionary;
begin
  const Font = OpenFont(GlyphA + '/Resources << /ProcSet [/PDF] >>', ['70 0 d0']);

  Assert.IsTrue(Font.TryGetCharProcs(CharProcs));
  Assert.AreEqual(1, CharProcs.Count);
  Assert.IsTrue(Font.TryGetCharProc(65, CharProc));
  Assert.IsFalse(Font.TryGetCharProc(66, CharProc));
  Assert.IsTrue(Font.HasGlyph('A'));
  Assert.IsFalse(Font.HasGlyph('B'));
  Assert.IsTrue(Font.TryGetResources(Resources));
  Assert.IsTrue(Resources.ContainsKey('ProcSet'));
end;

procedure TType3FontTests.TestCharProcResourcesOfItsOwnWin;
var
  Stream: TCosStream;
  Resources: TCosDictionary;
begin
  const Builder = TTextTestDocuments.NewBuilder(FontStart + GlyphA + '/Resources << /FromFont [] >> >>', '');
  try
    Builder.AddStreamObject(30, '/Resources << /FromProc [] >>', Ascii('70 0 d0'));
    const Document = FModels.Open(Builder);
    const Font = TPDFontFactory.CreateFont(TTextTestDocuments.FontDictionary(Document, 'F1'), Document.Context) as TPDType3Font;
    FFonts.Add(Font);
    Assert.IsTrue(Font.TryGetCharProc(65, Stream));

    const CharProc = TPDType3CharProc.Create(Font, Stream);
    try
      Assert.IsTrue(CharProc.TryGetResources(Resources));
      Assert.IsTrue(Resources.ContainsKey('FromProc'));
      Assert.IsTrue(FModels.HasLogLine('resources'));
    finally
      CharProc.Free;
    end;
  finally
    Builder.Free;
  end;
end;

procedure TType3FontTests.TestBoundingBoxFromFontBBox;
begin
  const Font = OpenFont('', []);

  const Box = Font.GetBoundingBox;
  Assert.AreEqual(Double(100), Double(Box.Width), 0);
  Assert.AreEqual(Double(100), Double(Box.Height), 0);
end;

procedure TType3FontTests.TestBoundingBoxFromGlyphsWhenFontBBoxIsZero;
begin
  const Font = OpenFontBody('<< /Type /Font /Subtype /Type3 /FontBBox [0 0 0 0] ' + GlyphA + '>>', ['80 0 -5 -6 30 40 d1']) as TPDType3Font;

  const Box = Font.GetBoundingBox;
  Assert.AreEqual(Double(-5), Double(Box.LowerLeftX), 0);
  Assert.AreEqual(Double(-6), Double(Box.LowerLeftY), 0);
  Assert.AreEqual(Double(30), Double(Box.UpperRightX), 0);
  Assert.AreEqual(Double(40), Double(Box.UpperRightY), 0);
end;

procedure TType3FontTests.TestHugeNumberOfCharProcsIsBounded;
begin
  const Font = OpenFontBody('<< /Type /Font /Subtype /Type3 ' + AllGlyphsFontEntries(20000) + ' >>', ['80 0 -5 -6 30 40 d1']) as TPDType3Font;

  const Box = Font.GetBoundingBox;
  Assert.AreEqual(Double(30), Double(Box.UpperRightX), 0);
  Assert.IsTrue(FModels.HasLogLine('glyph procedures'));
end;

procedure TType3FontTests.TestFlateBombGlyphProcedureSharedByAllCodesIsReadOnce;
begin
  // A glyph procedure that starts with d0 and then expands to 64 MiB, used by 256 codes
  var Bomb: TBytes;
  SetLength(Bomb, 64 * 1024 * 1024);
  const Start = Ascii('70 0 d0 ');
  Move(Start[0], Bomb[0], Length(Start));
  const Compressed = TFilterTestSupport.Compress(Bomb);
  Bomb := nil;

  const Names = TStringBuilder.Create;
  const CharProcs = TStringBuilder.Create;
  try
    for var Index := 0 to 255 do
    begin
      Names.AppendFormat('/G%d ', [Index]);
      CharProcs.AppendFormat('/G%d 30 0 R ', [Index]);
    end;
    const Builder = TTextTestDocuments.NewBuilder(Format('%s/Encoding << /Differences [0 %s] >> /CharProcs << %s >> >>',
                                                         [FontStart, Names.ToString, CharProcs.ToString]), '');
    try
      Builder.AddStreamObject(30, '/Filter /FlateDecode', Compressed);
      const Document = FModels.Open(Builder);
      const Font = TPDFontFactory.CreateFont(TTextTestDocuments.FontDictionary(Document, 'F1'), Document.Context);
      FFonts.Add(Font);

      const Watch = TStopwatch.StartNew;
      for var Code := 0 to 255 do
      begin
        Assert.AreEqual(Double(70), Double(Font.GetWidthFromFont(Code)), 0.0001);
      end;

      Assert.IsTrue(Watch.ElapsedMilliseconds < 5000, 'the bomb is decoded as a prefix, and once');
    finally
      Builder.Free;
    end;
  finally
    CharProcs.Free;
    Names.Free;
  end;
end;

procedure TType3FontTests.TestHeightFromDescriptor(const DescriptorEntries: string; const Expected: Integer);
begin
  const Font = OpenFont('/FontDescriptor << /Type /FontDescriptor /FontName /T3 /Flags 4 ' + DescriptorEntries + ' >>', []);

  Assert.AreEqual(Double(Expected), Double(Font.GetHeight(65)), 0);
end;

procedure TType3FontTests.TestHeightWithoutDescriptorIsZero;
begin
  const Font = OpenFont('', []);

  Assert.AreEqual(Double(0), Double(Font.GetHeight(65)), 0);
end;
procedure TType3FontTests.TestType3FontProperties;
begin
  const Font = OpenFont('/Name /T3Font /Encoding /Foo', []);

  Assert.AreEqual('T3Font', Font.Name);
  Assert.IsTrue(FModels.HasLogLine('Unknown encoding'));
  var Position := 0;
  Assert.AreEqual(7, Font.ReadCode([7, 8], Position));
  Assert.AreEqual(1, Position);
end;

end.
