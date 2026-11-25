// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Tests of Pdf4D for getPath, getNormalizedPath and hasGlyph of the PDVectorFont fonts of PDFBox (3.0.8); the reference paths
// (tests/fonts/glyph-paths) come from PDFBox
unit Pdf4D.Font.GlyphPath.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Common.Path,
  Pdf4D.Font.Base,
  Pdf4D.Model.Tests.Support;

type
  [TestFixture]
  TGlyphPathTests = class
  private
    FModels: TModelTestDocuments;
    // One for every fixture that a test opens, because a TModelTestDocuments keeps one document
    FFixtureModels: TObjectList<TModelTestDocuments>;
    FFonts: TObjectList<TPDFont>;

    function OpenFixture(const Name: string): TPDFont;
    function OpenType3Font(const FontEntries: string; const CharProc: string): TPDFont;
    class function Describe(const Path: TPdfPath): string; static;
    class procedure CheckSameTokens(const Expected, Actual, Context: string); static;
    class function ReferenceLines(const Name: string): TArray<string>; static;
    class function HasGlyphField(const Line: string): Boolean; static;
    class function CommandsField(const Line: string): string; static;
    class function ReferenceCommands(const Name: string; const Code: Integer): string; static;
    procedure CheckAgainstReference(const Name: string);
    function CheckedPathDescription(const Font: TPDFont; const Code: Integer): string;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestStandard14HelveticaUsesLiberationSans;

    [Test]
    procedure TestStandard14PathStaysInFontUnits;

    [Test]
    procedure TestEmbeddedType1Path;

    [Test]
    procedure TestEmbeddedCffPath;

    [Test]
    procedure TestEmbeddedTrueTypePath;

    [Test]
    procedure TestEmbeddedTrueTypeSymbolicPath;

    [Test]
    procedure TestTrueTypeNormalizedPathIsScaledToThousandUnits;

    [Test]
    procedure TestCidFontType2IdentityPath;

    [Test]
    procedure TestCidFontType0Path;

    [Test]
    procedure TestMissingGlyphUsesNotdefLikePdfBox;

    [Test]
    procedure TestSubstituteDrawsNoNotdef;

    [Test]
    procedure TestDamagedEmbeddedFontFallsBackToMapper;

    [Test]
    procedure TestType3IsNotVectorFont;

    [Test]
    procedure TestOtherFontsAreVectorFonts;
  end;

implementation

uses
  System.IOUtils,
  Pdf4D.Font.CIDFontType0,
  Pdf4D.Font.Factory,
  Pdf4D.Font.Type0,
  Pdf4D.Font.Type3,
  Pdf4D.Tests.TestFonts,
  Pdf4D.Tests.TextDocuments;

const
  PathTolerance = 0.01;
  GlyphPathsFolder = 'glyph-paths';
  CapitalA = 65;
  FirstCodeWithoutGlyph = 1;
  Type3FontBody = '<< /Type /Font /Subtype /Type3 /FontBBox [0 0 100 100] /Encoding << /Differences [65 /A] >> ' +
                  '/CharProcs << /A 30 0 R >> %s >>';

{ TGlyphPathTests }

procedure TGlyphPathTests.Setup;
begin
  FModels := TModelTestDocuments.Create;
  FFixtureModels := TObjectList<TModelTestDocuments>.Create(True);
  FFonts := TObjectList<TPDFont>.Create(True);
end;

procedure TGlyphPathTests.TearDown;
begin
  FreeAndNil(FFonts);
  FreeAndNil(FFixtureModels);
  FreeAndNil(FModels);
end;

function TGlyphPathTests.OpenFixture(const Name: string): TPDFont;
begin
  const Bytes = TFile.ReadAllBytes(TTestFonts.Path(TPath.Combine(GlyphPathsFolder, Name + '.pdf')));
  const Models = TModelTestDocuments.Create;
  FFixtureModels.Add(Models);
  const Document = Models.OpenBytes(Bytes);
  Result := TPDFontFactory.CreateFont(TTextTestDocuments.FontDictionary(Document, 'F1'), Document.Context);
  FFonts.Add(Result);
end;

function TGlyphPathTests.OpenType3Font(const FontEntries: string; const CharProc: string): TPDFont;
begin
  const Builder = TTextTestDocuments.NewBuilder(Format(Type3FontBody, [FontEntries]), '');
  try
    Builder.AddStreamObject(30, '', TEncoding.ASCII.GetBytes(CharProc));
    const Document = FModels.Open(Builder);
    Result := TPDFontFactory.CreateFont(TTextTestDocuments.FontDictionary(Document, 'F1'), Document.Context);
    FFonts.Add(Result);
  finally
    Builder.Free;
  end;
end;

class function TGlyphPathTests.Describe(const Path: TPdfPath): string;
begin
  const Parts = TStringBuilder.Create;
  try
    var PointIndex := 0;
    for var VerbIndex := 0 to Path.VerbCount - 1 do
    begin
      var PointCount := 0;
      case Path.Verb(VerbIndex) of
        TPdfPathVerb.MoveTo:
          begin
            Parts.Append(' M');
            PointCount := 1;
          end;
        TPdfPathVerb.LineTo:
          begin
            Parts.Append(' L');
            PointCount := 1;
          end;
        TPdfPathVerb.QuadTo:
          begin
            Parts.Append(' Q');
            PointCount := 2;
          end;
        TPdfPathVerb.CubicTo:
          begin
            Parts.Append(' C');
            PointCount := 3;
          end;
        TPdfPathVerb.Close:
          Parts.Append(' Z');
      else
        raise EArgumentException.Create('Unknown path verb');
      end;

      for var Count := 1 to PointCount do
      begin
        const Point = Path.Point(PointIndex);
        Parts.AppendFormat(' %s %s', [FloatToStr(Point.X, TFormatSettings.Invariant), FloatToStr(Point.Y, TFormatSettings.Invariant)]);
        Inc(PointIndex);
      end;
    end;
    Result := Parts.ToString.Trim;
  finally
    Parts.Free;
  end;
end;

class procedure TGlyphPathTests.CheckSameTokens(const Expected, Actual, Context: string);
begin
  const ExpectedTokens = Expected.Split([' '], TStringSplitOptions.ExcludeEmpty);
  const ActualTokens = Actual.Split([' '], TStringSplitOptions.ExcludeEmpty);
  Assert.AreEqual(Length(ExpectedTokens), Length(ActualTokens), Context + ': ' + Actual);
  for var Index := 0 to High(ExpectedTokens) do
  begin
    var ExpectedNumber: Double;
    const IsNumber = TryStrToFloat(ExpectedTokens[Index], ExpectedNumber, TFormatSettings.Invariant);
    if IsNumber then
    begin
      Assert.AreEqual(ExpectedNumber, StrToFloat(ActualTokens[Index], TFormatSettings.Invariant), PathTolerance,
                      Format('%s, token %d', [Context, Index]));
    end
    else
    begin
      Assert.AreEqual(ExpectedTokens[Index], ActualTokens[Index], Format('%s, token %d', [Context, Index]));
    end;
  end;
end;

class function TGlyphPathTests.ReferenceLines(const Name: string): TArray<string>;
begin
  const FileName = TPath.Combine(GlyphPathsFolder, Name + '.pdf.paths.txt');
  Result := TFile.ReadAllLines(TTestFonts.Path(FileName), TEncoding.UTF8);
end;

// A line is "<code> <hasGlyph> <commands>", the commands starting with a space
class function TGlyphPathTests.HasGlyphField(const Line: string): Boolean;
begin
  Result := (Line.Chars[Line.IndexOf(' ') + 1] = '1');
end;

class function TGlyphPathTests.CommandsField(const Line: string): string;
begin
  const CommandsStart = Line.IndexOf(' ') + 3;
  if CommandsStart >= Line.Length then
  begin
    Exit('');
  end;
  Result := Line.Substring(CommandsStart).Trim;
end;

class function TGlyphPathTests.ReferenceCommands(const Name: string; const Code: Integer): string;
begin
  const Prefix = Format('%d ', [Code]);
  for var Line in ReferenceLines(Name) do
  begin
    if Line.StartsWith(Prefix) then
    begin
      Exit(CommandsField(Line));
    end;
  end;
  raise EArgumentException.CreateFmt('The reference of %s has no code %d', [Name, Code]);
end;

function TGlyphPathTests.CheckedPathDescription(const Font: TPDFont; const Code: Integer): string;
begin
  var Path: TPdfPath;
  Assert.IsTrue(Font.TryGetNormalizedPath(Code, Path), Format('Code %d has a normalized path', [Code]));
  try
    Result := Describe(Path);
  finally
    Path.Free;
  end;
end;

procedure TGlyphPathTests.CheckAgainstReference(const Name: string);
begin
  const Font = OpenFixture(Name);
  var Checked := 0;
  for var Line in ReferenceLines(Name) do
  begin
    const Code = StrToInt(Line.Substring(0, Line.IndexOf(' ')));
    const Context = Format('%s, code %d', [Name, Code]);
    Assert.AreEqual(HasGlyphField(Line), Font.HasGlyph(Code), Context + ' hasGlyph');

    const Commands = CommandsField(Line);
    if Commands <> '!' then
    begin
      CheckSameTokens(Commands, CheckedPathDescription(Font, Code), Context);
    end;
    Inc(Checked);
  end;
  Assert.IsTrue(Checked >= 256, 'Codes checked in ' + Name);
end;

procedure TGlyphPathTests.TestStandard14HelveticaUsesLiberationSans;
begin
  const Font = OpenFixture('std14-helvetica');

  Assert.IsFalse(Font.IsEmbedded);
  Assert.IsTrue(Font.IsStandard14);
  CheckAgainstReference('std14-helvetica');
end;

// PDType1Font does not scale the TrueType glyphs of its substitute: the font matrix does
procedure TGlyphPathTests.TestStandard14PathStaysInFontUnits;
begin
  const Font = OpenFixture('std14-helvetica');

  var Path: TPdfPath;
  Assert.IsTrue(Font.TryGetNormalizedPath(CapitalA, Path));
  try
    // LiberationSans has 2048 units per em, and the capital A is 1409 high
    Assert.AreEqual(Double(1409), Double(Path.Bounds.Height), PathTolerance);
  finally
    Path.Free;
  end;
  Assert.AreEqual(Double(1 / 2048), Double(Font.GetFontMatrix.GetValue(0, 0)), 0.000001);
end;

procedure TGlyphPathTests.TestEmbeddedType1Path;
begin
  const Font = OpenFixture('embedded-type1');

  Assert.IsTrue(Font.IsEmbedded);
  CheckAgainstReference('embedded-type1');
end;

procedure TGlyphPathTests.TestEmbeddedCffPath;
begin
  const Font = OpenFixture('embedded-cff');

  Assert.IsTrue(Font.IsEmbedded);
  CheckAgainstReference('embedded-cff');
end;

procedure TGlyphPathTests.TestEmbeddedTrueTypePath;
begin
  const Font = OpenFixture('embedded-truetype');

  Assert.IsTrue(Font.IsEmbedded);
  CheckAgainstReference('embedded-truetype');
end;

// The font has a (3, 0) cmap with the glyphs at 0xF020 and up (the rule of PDFBox adds 0xF000 to the code), and six glyphs at the
// codes 200 to 205 themselves
procedure TGlyphPathTests.TestEmbeddedTrueTypeSymbolicPath;
begin
  const Font = OpenFixture('embedded-truetype-symbolic');

  Assert.IsTrue(Font.IsEmbedded);
  Assert.IsTrue(Font.HasGlyph(CapitalA), 'Reached through 0xF041');
  Assert.IsTrue(Font.HasGlyph(200), 'Reached directly');
  CheckAgainstReference('embedded-truetype-symbolic');
end;

procedure TGlyphPathTests.TestTrueTypeNormalizedPathIsScaledToThousandUnits;
begin
  const Font = OpenFixture('embedded-truetype');

  var Path: TPdfPath;
  var Normalized: TPdfPath;
  Assert.IsTrue(Font.TryGetPath(CapitalA, Path));
  try
    Assert.IsTrue(Font.TryGetNormalizedPath(CapitalA, Normalized));
    try
      Assert.AreEqual(Double(1409), Double(Path.Bounds.Height), PathTolerance);
      Assert.AreEqual(Double(1409 * 1000 / 2048), Double(Normalized.Bounds.Height), PathTolerance);
    finally
      Normalized.Free;
    end;
  finally
    Path.Free;
  end;
end;

procedure TGlyphPathTests.TestCidFontType2IdentityPath;
begin
  const Font = OpenFixture('cid-type2-identity');

  Assert.IsTrue(Font.IsEmbedded);
  CheckAgainstReference('cid-type2-identity');
end;

procedure TGlyphPathTests.TestCidFontType0Path;
begin
  const Font = OpenFixture('cid-type0');

  Assert.IsTrue(Font.IsEmbedded);
  Assert.IsTrue(Font is TPDType0Font);
  Assert.IsTrue(TPDType0Font(Font).DescendantFont is TPDCIDFontType0);
  CheckAgainstReference('cid-type0');
end;

// PDFBox draws glyph 0 of an embedded TrueType font and .notdef of an embedded Type 1 font; neither has a glyph
procedure TGlyphPathTests.TestMissingGlyphUsesNotdefLikePdfBox;
begin
  const TrueTypeFont = OpenFixture('embedded-truetype');
  const Type1Font = OpenFixture('embedded-type1');

  Assert.IsFalse(TrueTypeFont.HasGlyph(FirstCodeWithoutGlyph));
  const GlyphZero = CheckedPathDescription(TrueTypeFont, FirstCodeWithoutGlyph);
  Assert.IsTrue(GlyphZero <> '', 'The box of glyph 0');
  CheckSameTokens(ReferenceCommands('embedded-truetype', FirstCodeWithoutGlyph), GlyphZero, 'glyph 0');

  Assert.IsFalse(Type1Font.HasGlyph(FirstCodeWithoutGlyph));
  CheckSameTokens(ReferenceCommands('embedded-type1', FirstCodeWithoutGlyph), CheckedPathDescription(Type1Font, FirstCodeWithoutGlyph), '.notdef');
end;

// Acrobat draws no .notdef for a Type 1 font that PDFBox has to substitute
procedure TGlyphPathTests.TestSubstituteDrawsNoNotdef;
begin
  const Font = OpenFixture('std14-helvetica');

  Assert.IsFalse(Font.HasGlyph(FirstCodeWithoutGlyph));
  Assert.AreEqual('', CheckedPathDescription(Font, FirstCodeWithoutGlyph));
end;

procedure TGlyphPathTests.TestDamagedEmbeddedFontFallsBackToMapper;
begin
  const Font = OpenFixture('damaged-truetype');

  Assert.IsFalse(Font.IsEmbedded);
  Assert.IsTrue(Font.IsDamaged);
  CheckAgainstReference('damaged-truetype');
end;

procedure TGlyphPathTests.TestType3IsNotVectorFont;
begin
  const Font = OpenType3Font('', '70 0 d0');

  Assert.IsFalse(Font.IsVectorFont);
  var Path: TPdfPath;
  Assert.IsFalse(Font.TryGetPath(CapitalA, Path));
  Assert.IsNull(Path);

  var CharProc: TPDType3CharProc;
  Assert.IsTrue(TPDType3Font(Font).TryGetCharProc(CapitalA, CharProc));
  Assert.IsNotNull(CharProc);
  var Again: TPDType3CharProc;
  Assert.IsTrue(TPDType3Font(Font).TryGetCharProc(CapitalA, Again));
  Assert.IsTrue(CharProc = Again, 'The font keeps the procedure');
  Assert.IsFalse(TPDType3Font(Font).TryGetCharProc(CapitalA + 1, Again));
  Assert.IsTrue(Font.HasGlyph(CapitalA));
  Assert.IsFalse(Font.HasGlyph(CapitalA + 1));
end;

procedure TGlyphPathTests.TestOtherFontsAreVectorFonts;
begin
  for var Name in ['std14-helvetica', 'embedded-type1', 'embedded-cff', 'embedded-truetype', 'cid-type2-identity', 'cid-type0'] do
  begin
    Assert.IsTrue(OpenFixture(Name).IsVectorFont, Name);
  end;
end;

end.
