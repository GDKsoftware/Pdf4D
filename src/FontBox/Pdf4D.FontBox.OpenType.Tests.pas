// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/test/java/org/apache/fontbox/ttf/OpenTypeFontTest.java (3.0.8), and tests of Pdf4D for
// fontbox/src/main/java/org/apache/fontbox/ttf/OTFParser.java and CFFTable.java (3.0.8)
unit Pdf4D.FontBox.OpenType.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Diagnostics,
  DUnitX.TestFramework;

type
  [TestFixture]
  TOpenTypeFontTests = class
  private
    const SourceSansPro = 'SourceSansProBold.otf';
    const Foglihten = 'FoglihtenNo07.otf';
    const LiberationSans = 'LiberationSans-Regular.ttf';
    const MaximumHostileMilliseconds = 1000;

  private
    class function HasAnyLayoutTable(const Tags: TArray<string>): Boolean; static;
    class function OutcomeOf(const Data: TBytes): string; static;

  public
    [Test]
    procedure TestOpenTypeCff;

    [Test]
    procedure TestSecondOpenTypeFileLoads;

    [Test]
    procedure TestCffFontIsReadWithTheFont;

    [Test]
    procedure TestHasLayoutTables;

    [Test]
    procedure TestTrueTypeFontThroughTheOpenTypeParser;

    [Test]
    procedure TestTrueTypeParserRefusesCffOutlines;

    [Test]
    procedure TestOpenTypeMemberOfACollection;

    [Test]
    procedure TestCff2WithoutCffIsUnsupported;

    [Test]
    procedure TestOpenTypeWithoutCffTable;

    [Test]
    procedure TestOpenTypeWithoutMandatoryTableRaises;

    [Test]
    procedure TestTruncatedOpenTypeOnlyRaisesParseException;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.FontBox.Cff.Font,
  Pdf4D.FontBox.OpenType,
  Pdf4D.FontBox.TrueType.Collection,
  Pdf4D.FontBox.TrueType.Font,
  Pdf4D.FontBox.TrueType.Parser,
  Pdf4D.Tests.TestFonts,
  Pdf4D.Tests.TrueTypeBuilder;

{ TOpenTypeFontTests }

class function TOpenTypeFontTests.HasAnyLayoutTable(const Tags: TArray<string>): Boolean;
begin
  for var Tag in Tags do
  begin
    const IsLayoutTag = ((Tag = 'BASE') or (Tag = 'GDEF') or (Tag = 'GPOS') or (Tag = 'GSUB') or (Tag = 'JSTF'));
    if IsLayoutTag then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TOpenTypeFontTests.OutcomeOf(const Data: TBytes): string;
begin
  Result := '';
  const Parser = TOTFParser.Create;
  try
    try
      Parser.Parse(Data).Free;
    except
      on Failure: Exception do
      begin
        Result := Failure.ClassName;
      end;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TOpenTypeFontTests.TestOpenTypeCff;
begin
  const Parser = TOTFParser.Create;
  try
    const Font = Parser.Parse(TTestFonts.Bytes(SourceSansPro));
    try
      Assert.IsTrue(Font.IsPostScript);
      Assert.IsTrue(Font.IsSupportedOTF);
      Assert.AreEqual('SourceSansPro-Bold', Font.CFF.Name);
      Assert.AreEqual('SourceSansPro-Bold', Font.Name);
      Assert.IsTrue(Font.NumberOfGlyphs > 0);
      Assert.AreEqual(Font.NumberOfGlyphs, Integer(Length(Font.CFF.CharStrings)));
    finally
      Font.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TOpenTypeFontTests.TestSecondOpenTypeFileLoads;
begin
  const Parser = TOTFParser.Create;
  try
    const Font = Parser.Parse(TTestFonts.Bytes(Foglihten));
    try
      Assert.IsTrue(Font.IsPostScript);
      Assert.IsTrue(Font.CFF is TCFFType1Font);
      Assert.IsFalse(Font.CFF.Name.IsEmpty);
    finally
      Font.Free;
    end;
  finally
    Parser.Free;
  end;
end;

// The parser reads every table before it hands the font out, so the CFF font is there and asking for it changes nothing
procedure TOpenTypeFontTests.TestCffFontIsReadWithTheFont;
begin
  const Parser = TOTFParser.Create;
  try
    const Font = Parser.Parse(TTestFonts.Bytes(SourceSansPro));
    try
      const First = Font.CFF;
      Assert.IsNotNull(First);
      Assert.AreSame(First, Font.CFF);
      Assert.AreEqual(Font.CFF.Name, TCFFType1Font(First).Name);
    finally
      Font.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TOpenTypeFontTests.TestHasLayoutTables;
begin
  for var FileName in [SourceSansPro, Foglihten] do
  begin
    const Parser = TOTFParser.Create;
    try
      const Font = Parser.Parse(TTestFonts.Bytes(FileName));
      try
        Assert.AreEqual(HasAnyLayoutTable(Font.TableTags), Font.HasLayoutTables, FileName);
      finally
        Font.Free;
      end;
    finally
      Parser.Free;
    end;
  end;
end;

procedure TOpenTypeFontTests.TestTrueTypeFontThroughTheOpenTypeParser;
begin
  const Parser = TOTFParser.Create;
  try
    const Font = Parser.Parse(TTestFonts.Bytes(LiberationSans));
    try
      Assert.IsFalse(Font.IsPostScript);
      Assert.IsTrue(Font.IsSupportedOTF);
      Assert.AreEqual('LiberationSans', Font.Name);
      Assert.WillRaise(
        procedure
        begin
          Font.CFF;
        end,
        EPdfUnsupportedFeatureException);
    finally
      Font.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TOpenTypeFontTests.TestTrueTypeParserRefusesCffOutlines;
begin
  const Data = TTestFonts.Bytes(SourceSansPro);
  const Parser = TTTFParser.Create;
  try
    Assert.WillRaise(
      procedure
      begin
        Parser.Parse(Data).Free;
      end,
      EPdfParseException);
  finally
    Parser.Free;
  end;
end;

procedure TOpenTypeFontTests.TestOpenTypeMemberOfACollection;
begin
  const Collection = TTrueTypeCollection.Create(TTrueTypeTestData.BuildCollection([TTestFonts.Bytes(SourceSansPro),
                                                                                  TTestFonts.Bytes(LiberationSans)]));
  try
    const OpenType = Collection.FontAt(0);
    try
      Assert.IsTrue(OpenType is TOpenTypeFont);
      Assert.AreEqual('SourceSansPro-Bold', TOpenTypeFont(OpenType).CFF.Name);
    finally
      OpenType.Free;
    end;

    const TrueType = Collection.FontAt(1);
    try
      Assert.AreEqual('LiberationSans', TrueType.Name);
    finally
      TrueType.Free;
    end;

    var Found: TTrueTypeFont;
    Assert.IsTrue(Collection.TryGetFontByName('SourceSansPro-Bold', Found));
    Found.Free;
  finally
    Collection.Free;
  end;
end;

// A font with CFF2 outlines and no CFF table: the directory of an OTTO font with the single table CFF2
procedure TOpenTypeFontTests.TestCff2WithoutCffIsUnsupported;
begin
  const Writer = TTestByteWriter.Create;
  try
    Writer.U32($4F54544F);
    Writer.U16(1);
    Writer.U16(16);
    Writer.U16(0);
    Writer.U16(0);
    Writer.U8(Ord('C'));
    Writer.U8(Ord('F'));
    Writer.U8(Ord('F'));
    Writer.U8(Ord('2'));
    Writer.U32(0);
    Writer.U32(28);
    Writer.U32(4);
    Writer.U32(0);

    const Data = Writer.ToBytes;
    const Parser = TOTFParser.Create;
    try
      Assert.WillRaise(
        procedure
        begin
          Parser.Parse(Data).Free;
        end,
        EPdfUnsupportedFeatureException);
    finally
      Parser.Free;
    end;
  finally
    Writer.Free;
  end;
end;

// An OTTO font whose CFF table is gone still loads, as in PDFBox, but it has no CFF font to give
procedure TOpenTypeFontTests.TestOpenTypeWithoutCffTable;
begin
  var Data := TTestFonts.Bytes(SourceSansPro);
  TTrueTypeTestData.ReplaceTable(Data, 'CFF ', 'ZZZZ', nil);
  const Parser = TOTFParser.Create;
  try
    const Font = Parser.Parse(Data);
    try
      Assert.IsTrue(Font.IsPostScript);
      Assert.WillRaise(
        procedure
        begin
          Font.CFF;
        end,
        EPdfUnsupportedFeatureException);
    finally
      Font.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TOpenTypeFontTests.TestOpenTypeWithoutMandatoryTableRaises;
begin
  var Data := TTestFonts.Bytes(SourceSansPro);
  TTrueTypeTestData.ReplaceTable(Data, 'hmtx', 'ZZZZ', nil);
  Assert.AreEqual(EPdfParseException.ClassName, OutcomeOf(Data));
end;

procedure TOpenTypeFontTests.TestTruncatedOpenTypeOnlyRaisesParseException;
begin
  const Data = TTestFonts.Bytes(SourceSansPro);
  const Stopwatch = TStopwatch.StartNew;
  for var Step := 0 to 40 do
  begin
    const Outcome = OutcomeOf(Copy(Data, 0, Length(Data) * Step div 41));
    Assert.IsTrue((Outcome = '') or (Outcome = EPdfParseException.ClassName), Format('step %d: %s', [Step, Outcome]));
  end;
  Assert.IsTrue(Stopwatch.ElapsedMilliseconds < 10 * MaximumHostileMilliseconds, 'Parsing took too long');
end;

end.
