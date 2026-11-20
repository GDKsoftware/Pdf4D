// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Tests of Pdf4D for the path part of fontbox/src/main/java/org/apache/fontbox/cff/Type1CharString.java and Type2CharString.java
// (3.0.8); the reference paths come from PDFBox
unit Pdf4D.FontBox.CharStringPath.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Common.Log,
  Pdf4D.Common.Path,
  Pdf4D.FontBox.Type1.Font;

type
  TSeacOperands = record
    LeftSideBearing: Double;
    Asb: Double;
    Adx: Double;
    Ady: Double;
    BaseCode: Integer;
    AccentCode: Integer;
  end;

  [TestFixture]
  TCharStringPathTests = class
  private
    FMessages: TList<string>;
    FLog: TPdfLog;

    class function Encode(const Parts: array of Integer): TBytes; static;
    class function Describe(const Path: TPdfPath): string; static;
    class function Tokens(const Text: string): TArray<string>; static;
    class procedure CheckSameTokens(const Expected, Actual, Context: string); static;
    class function Type1Subrs: TArray<TBytes>; static;
    class function SeacBase: TBytes; static;
    class function SeacAccent: TBytes; static;
    class function SeacCharString: TBytes; static;
    class function Dummy(const Count: Integer): TArray<TBytes>; static;
    class procedure FindSeac(const Font: TType1Font; out GlyphName: string; out Seac: TSeacOperands); static;

    function Type1Described(const CharString: TBytes; const Subrs: TArray<TBytes> = nil): string;
    function Type2Described(const CharString: TBytes; const LocalSubrs: TArray<TBytes> = nil): string;
    procedure CheckType1ReferencePaths(const FontFile: string);
    procedure CheckCffReferencePaths(const FontFile: string);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestType1PathsMatchPdfBox;

    [Test]
    procedure TestType1PathsMatchPdfBoxOfSecondFont;

    [Test]
    procedure TestCffPathsMatchPdfBox;

    [Test]
    procedure TestCffPathsMatchPdfBoxOfSecondFont;

    [Test]
    procedure TestSeacComposesAccent;

    [Test]
    procedure TestSeacWithoutLookupLeavesOutTheAccents;

    [Test]
    procedure TestFlexBecomesTwoCurves;

    [Test]
    procedure TestHintReplacementIsIgnored;

    [Test]
    procedure TestRecursiveSubrStopsPath;

    [Test]
    procedure TestDamagedCharStringGivesPartialPath;

    [Test]
    procedure TestType1ClosepathStartsAtTheCurrentPoint;

    [Test]
    procedure TestType1WithoutMovetoStartsTheSubpath;

    [Test]
    procedure TestType2LinesAndImplicitClose;

    [Test]
    procedure TestType2HintMaskBytesAreSkipped;

    [Test]
    procedure TestType2AlternatingCurves;

    [Test]
    procedure TestType2SubrIsCalled;

    [Test]
    procedure TestType2DamagedCharStringGivesPartialPath;

    [Test]
    procedure TestType2FlexGivesTwoCurves;

    [Test]
    procedure TestType2DivisionIsCollapsed;

    [Test]
    procedure TestType2SeacComposesAccentThroughLookup;

    [Test]
    procedure TestType2SeacWithoutLookupLeavesOutTheAccent;

    [Test]
    procedure TestCffFontComposesType2Seac;

    [Test]
    procedure TestCidPathByCid;

    [Test]
    procedure TestPathOfMissingGlyphIsNotdef;
  end;

implementation

uses
  System.Types,
  System.IOUtils,
  Pdf4D.FontBox.Cff.Font,
  Pdf4D.FontBox.CharStringPath,
  Pdf4D.FontBox.CharStringReaders,
  Pdf4D.FontBox.Cff.Parser,
  Pdf4D.FontBox.Encoding,
  Pdf4D.FontBox.OpenType,
  Pdf4D.Common.Defines,
  Pdf4D.Tests.CffBuilder,
  Pdf4D.Tests.TestFonts;

const
  // A part of an operator in Encode is OperatorBase + the code; the two byte operators are 12 b1, so EscapeBase + b1
  OperatorBase = 100000;
  OperatorEscape = 256;

  Hstem = OperatorBase + 1;
  Rmoveto = OperatorBase + 21;
  Hmoveto = OperatorBase + 22;
  Rlineto = OperatorBase + 5;
  Hlineto = OperatorBase + 6;
  Rrcurveto = OperatorBase + 8;
  Closepath = OperatorBase + 9;
  Callsubr = OperatorBase + 10;
  Return = OperatorBase + 11;
  Hsbw = OperatorBase + 13;
  Endchar = OperatorBase + 14;
  Hintmask = OperatorBase + 19;
  Hvcurveto = OperatorBase + 31;
  Div_ = OperatorBase + OperatorEscape + 12;
  Callothersubr = OperatorBase + OperatorEscape + 16;
  Pop = OperatorBase + OperatorEscape + 17;
  Setcurrentpoint = OperatorBase + OperatorEscape + 33;
  Flex = OperatorBase + OperatorEscape + 35;
  RawByte = 200000;

  PathTolerance = 0.01;
  // The base of the seac tests at its place and the accent moved by adx and ady. The last MoveTo after each Z is the pen position
  // that FontBox leaves behind a closepath; the move of the accent replaces the one of the base.
  SeacExpected = 'M 10 20 L 60 20 L 60 70 Z M 5 7 L 35 7 L 35 37 Z M 35 37';
  SeacBaseOnly = 'M 10 20 L 60 20 L 60 70 Z M 60 70';
  Type1Paths = 'paths';

{ TCharStringPathTests }

procedure TCharStringPathTests.Setup;
begin
  FMessages := TList<string>.Create;
  FLog := TPdfLog.Create(
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      FMessages.Add(Message);
    end);
end;

procedure TCharStringPathTests.TearDown;
begin
  FLog.Free;
  FMessages.Free;
end;

// Numbers take the one or two byte form that Type 1 and Type 2 share; RawByte + b is the byte b itself
class function TCharStringPathTests.Encode(const Parts: array of Integer): TBytes;
begin
  var Stream := TBytes(nil);
  for var Part in Parts do
  begin
    if Part >= RawByte then
    begin
      Stream := Stream + [Byte(Part - RawByte)];
    end
    else if Part >= OperatorBase then
    begin
      const Code = Part - OperatorBase;
      if Code >= OperatorEscape then
      begin
        Stream := Stream + [12, Byte(Code - OperatorEscape)];
      end
      else
      begin
        Stream := Stream + [Byte(Code)];
      end;
    end
    else if (Part >= -107) and (Part <= 107) then
    begin
      Stream := Stream + [Byte(Part + 139)];
    end
    else if Part > 0 then
    begin
      Stream := Stream + [Byte(247 + (Part - 108) div 256), Byte((Part - 108) mod 256)];
    end
    else
    begin
      Stream := Stream + [Byte(251 + (-Part - 108) div 256), Byte((-Part - 108) mod 256)];
    end;
  end;
  Result := Stream;
end;

class function TCharStringPathTests.Describe(const Path: TPdfPath): string;
begin
  var Parts := TList<string>.Create;
  try
    var PointIndex := 0;
    for var VerbIndex := 0 to Path.VerbCount - 1 do
    begin
      case Path.Verb(VerbIndex) of
        TPdfPathVerb.MoveTo:
          Parts.Add('M');
        TPdfPathVerb.LineTo:
          Parts.Add('L');
        TPdfPathVerb.QuadTo:
          Parts.Add('Q');
        TPdfPathVerb.CubicTo:
          Parts.Add('C');
        TPdfPathVerb.Close:
          Parts.Add('Z');
      else
        raise EArgumentException.Create('Unknown path verb');
      end;

      var PointCount := 0;
      case Path.Verb(VerbIndex) of
        TPdfPathVerb.MoveTo, TPdfPathVerb.LineTo:
          PointCount := 1;
        TPdfPathVerb.QuadTo:
          PointCount := 2;
        TPdfPathVerb.CubicTo:
          PointCount := 3;
      end;
      for var Count := 1 to PointCount do
      begin
        const Point = Path.Point(PointIndex);
        Parts.Add(FloatToStr(Point.X, TFormatSettings.Invariant));
        Parts.Add(FloatToStr(Point.Y, TFormatSettings.Invariant));
        Inc(PointIndex);
      end;
    end;
    Result := string.Join(' ', Parts.ToArray);
  finally
    Parts.Free;
  end;
end;

class function TCharStringPathTests.Tokens(const Text: string): TArray<string>;
begin
  Result := Text.Split([' '], TStringSplitOptions.ExcludeEmpty);
end;

class procedure TCharStringPathTests.CheckSameTokens(const Expected, Actual, Context: string);
begin
  const ExpectedTokens = Tokens(Expected);
  const ActualTokens = Tokens(Actual);
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

// subr 0: end of flex, subr 1: begin of flex, subr 2: a flex point, as the Type 1 fonts have them
class function TCharStringPathTests.Type1Subrs: TArray<TBytes>;
begin
  Result := [
    Encode([3, 0, Callothersubr, Pop, Pop, Setcurrentpoint, Return]),
    Encode([0, 1, Callothersubr, Return]),
    Encode([0, 2, Callothersubr, Return])];
end;

function TCharStringPathTests.Type1Described(const CharString: TBytes; const Subrs: TArray<TBytes>): string;
begin
  const Path = TCharStringPath.Type1Path(CharString, Subrs, nil, FLog);
  try
    Result := Describe(Path);
  finally
    Path.Free;
  end;
end;

function TCharStringPathTests.Type2Described(const CharString: TBytes; const LocalSubrs: TArray<TBytes>): string;
begin
  const Path = TCharStringPath.Type2Path(CharString, nil, LocalSubrs, FLog);
  try
    Result := Describe(Path);
  finally
    Path.Free;
  end;
end;

procedure TCharStringPathTests.CheckType1ReferencePaths(const FontFile: string);
begin
  const Font = TType1Font.CreateWithPFB(TTestFonts.Bytes(FontFile));
  try
    var Checked := 0;
    for var Line in TFile.ReadAllLines(TTestFonts.Path(FontFile + '.' + Type1Paths + '.txt'), TEncoding.UTF8) do
    begin
      const Separator = Line.IndexOf(' ');
      if Separator <= 0 then
      begin
        Continue;
      end;
      const Key = Line.Substring(0, Separator);
      var Path: TPdfPath;
      Assert.IsTrue(Font.TryGetPath(Key, Path), Format('%s in %s', [Key, FontFile]));
      try
        CheckSameTokens(Line.Substring(Separator + 1), Describe(Path), Format('%s in %s', [Key, FontFile]));
      finally
        Path.Free;
      end;
      Inc(Checked);
    end;
    Assert.IsTrue(Checked >= 100, 'Glyphs checked in ' + FontFile);
  finally
    Font.Free;
  end;
end;

procedure TCharStringPathTests.CheckCffReferencePaths(const FontFile: string);
begin
  const Parser = TOTFParser.Create;
  try
    const Font = Parser.Parse(TTestFonts.Bytes(FontFile));
    try
      var Checked := 0;
      for var Line in TFile.ReadAllLines(TTestFonts.Path(FontFile + '.' + Type1Paths + '.txt'), TEncoding.UTF8) do
      begin
        const Separator = Line.IndexOf(' ');
        if Separator <= 0 then
        begin
          Continue;
        end;
        const Key = Line.Substring(0, Separator);
        const Number = StrToInt(Key.Substring(3));
        var Path: TPdfPath;
        if Key.StartsWith('cid') then
        begin
          Assert.IsTrue(Font.CFF.TryGetPathByCid(Number, Path), Key);
        end
        else
        begin
          Assert.IsTrue(Font.CFF.TryGetPathByGid(Number, Path), Key);
        end;
        try
          CheckSameTokens(Line.Substring(Separator + 1), Describe(Path), Format('%s in %s', [Key, FontFile]));
        finally
          Path.Free;
        end;
        Inc(Checked);
      end;
      Assert.IsTrue(Checked >= 100, 'Glyphs checked in ' + FontFile);
    finally
      Font.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TCharStringPathTests.TestType1PathsMatchPdfBox;
begin
  CheckType1ReferencePaths('OpenSans-Regular.pfb');
end;

procedure TCharStringPathTests.TestType1PathsMatchPdfBoxOfSecondFont;
begin
  CheckType1ReferencePaths('DejaVuSerifCondensed.pfb');
end;

procedure TCharStringPathTests.TestCffPathsMatchPdfBox;
begin
  CheckCffReferencePaths('SourceSansProBold.otf');
end;

procedure TCharStringPathTests.TestCffPathsMatchPdfBoxOfSecondFont;
begin
  CheckCffReferencePaths('FoglihtenNo07.otf');
end;

class function TCharStringPathTests.Dummy(const Count: Integer): TArray<TBytes>;
begin
  SetLength(Result, Count);
  for var Index := 0 to Count - 1 do
  begin
    Result[Index] := Encode([Return]);
  end;
end;

// The first glyph (by name) that has a seac, with the operands of that seac
class procedure TCharStringPathTests.FindSeac(const Font: TType1Font; out GlyphName: string; out Seac: TSeacOperands);
begin
  GlyphName := '';
  Seac := Default(TSeacOperands);
  const Names = TList<string>.Create(Font.CharStringsDict.Keys);
  try
    Names.Sort;
    for var Name in Names do
    begin
      const Reader = TType1Reader.Create(Font.Subrs, nil);
      try
        Reader.ReadAll(Font.CharStringsDict[Name]);
        const Operands = TList<Double>.Create;
        try
          var HasSidebearing := False;
          for var Item in Reader.Items do
          begin
            if not Item.IsCommand then
            begin
              Operands.Add(Item.Value);
              Continue;
            end;
            if (Item.Code = CodeHSBW) and (not HasSidebearing) and (Operands.Count >= 2) then
            begin
              Seac.LeftSideBearing := Operands[0];
              HasSidebearing := True;
            end;
            if (Item.Code = EscapeBase + 6) and (Operands.Count >= 5) then
            begin
              Seac.Asb := Operands[0];
              Seac.Adx := Operands[1];
              Seac.Ady := Operands[2];
              Seac.BaseCode := Round(Operands[3]);
              Seac.AccentCode := Round(Operands[4]);
              GlyphName := Name;
              Exit;
            end;
            Operands.Clear;
          end;
        finally
          Operands.Free;
        end;
      finally
        Reader.Free;
      end;
    end;
  finally
    Names.Free;
  end;
end;

procedure TCharStringPathTests.TestSeacComposesAccent;
begin
  const Font = TType1Font.CreateWithPFB(TTestFonts.Bytes('OpenSans-Regular.pfb'));
  try
    var GlyphName: string;
    var Seac: TSeacOperands;
    FindSeac(Font, GlyphName, Seac);
    Assert.AreNotEqual('', GlyphName, 'A glyph with seac in OpenSans');

    var Composite: TPdfPath;
    var Base: TPdfPath;
    var Accent: TPdfPath;
    Assert.IsTrue(Font.TryGetPath(GlyphName, Composite));
    try
      Assert.IsTrue(Font.TryGetPath(TFontBoxStandardEncoding.Instance.GetName(Seac.BaseCode), Base));
      try
        Assert.IsTrue(Font.TryGetPath(TFontBoxStandardEncoding.Instance.GetName(Seac.AccentCode), Accent));
        try
          var Expected := Accent.Bounds;
          Expected.Offset(Seac.LeftSideBearing + Seac.Adx - Seac.Asb, Seac.Ady);
          Expected := TRectF.Union(Base.Bounds, Expected);

          Assert.IsFalse(Composite.IsEmpty);
          Assert.AreEqual(Expected.Left, Composite.Bounds.Left, PathTolerance);
          Assert.AreEqual(Expected.Top, Composite.Bounds.Top, PathTolerance);
          Assert.AreEqual(Expected.Right, Composite.Bounds.Right, PathTolerance);
          Assert.AreEqual(Expected.Bottom, Composite.Bounds.Bottom, PathTolerance);
          Assert.IsTrue(Composite.VerbCount >= Base.VerbCount + Accent.VerbCount - 1);
        finally
          Accent.Free;
        end;
      finally
        Base.Free;
      end;
    finally
      Composite.Free;
    end;
  finally
    Font.Free;
  end;
end;

procedure TCharStringPathTests.TestSeacWithoutLookupLeavesOutTheAccents;
begin
  const Font = TType1Font.CreateWithPFB(TTestFonts.Bytes('OpenSans-Regular.pfb'));
  try
    var GlyphName: string;
    var Seac: TSeacOperands;
    FindSeac(Font, GlyphName, Seac);

    const Path = TCharStringPath.Type1Path(Font.CharStringsDict[GlyphName], Font.Subrs, nil, FLog);
    try
      Assert.IsTrue(Path.IsEmpty);
      Assert.IsTrue(FMessages.Count > 0);
    finally
      Path.Free;
    end;
  finally
    Font.Free;
  end;
end;

procedure TCharStringPathTests.TestFlexBecomesTwoCurves;
begin
  // The start is (100, 100). The seven flex points are moves: the reference point, then the points of two curves.
  const CharString = Encode([0, 1000, Hsbw, 100, 100, Rmoveto, 1, Callsubr,
                             50, 0, Rmoveto, 2, Callsubr, -50, 10, Rmoveto, 2, Callsubr,
                             20, 10, Rmoveto, 2, Callsubr, 20, 0, Rmoveto, 2, Callsubr,
                             20, 0, Rmoveto, 2, Callsubr, 20, -10, Rmoveto, 2, Callsubr,
                             20, -10, Rmoveto, 2, Callsubr, 50, 200, 100, 0, Callsubr, Endchar]);

  Assert.AreEqual('M 100 100 C 100 110 120 120 140 120 C 160 120 180 110 200 100', Type1Described(CharString, Type1Subrs));
end;

// "4 1 3 callothersubr pop callsubr" calls subr 4, which has hints only
procedure TCharStringPathTests.TestHintReplacementIsIgnored;
begin
  var Subrs := Dummy(5);
  Subrs[4] := Encode([10, 20, Hstem, 30, 40, OperatorBase + 3, Return]);
  const CharString = Encode([0, 500, Hsbw, 100, 100, Rmoveto, 4, 1, 3, Callothersubr, Pop, Callsubr, 50, 0, Rlineto, Endchar]);

  Assert.AreEqual('M 100 100 L 150 100', Type1Described(CharString, Subrs));
  Assert.AreEqual(0, Integer(FMessages.Count));
end;

procedure TCharStringPathTests.TestRecursiveSubrStopsPath;
begin
  const Subrs: TArray<TBytes> = [Encode([0, Callsubr])];
  const CharString = Encode([0, 500, Hsbw, 100, 100, Rmoveto, 50, 0, Rlineto, 0, Callsubr, Endchar]);

  Assert.AreEqual('M 100 100 L 150 100', Type1Described(CharString, Subrs));
  Assert.IsTrue(FMessages.Count > 0);
  Assert.IsTrue(FMessages[0].Contains('deeper'));
end;

procedure TCharStringPathTests.TestDamagedCharStringGivesPartialPath;
begin
  // A number of five bytes that ends after its first byte
  const CharString = Encode([0, 500, Hsbw, 100, 100, Rmoveto, 50, 0, Rlineto, RawByte + 255, RawByte + 0]);

  // Damage is not an exception: the glyph keeps the path up to it
  const Description = Type1Described(CharString);

  Assert.AreEqual('M 100 100 L 150 100', Description);
  Assert.IsTrue(FMessages.Count > 0);
end;

procedure TCharStringPathTests.TestType1ClosepathStartsAtTheCurrentPoint;
begin
  const CharString = Encode([0, 500, Hsbw, 100, 100, Rmoveto, 50, 0, Rlineto, 0, 50, Rlineto, Closepath, Endchar]);

  Assert.AreEqual('M 100 100 L 150 100 L 150 150 Z M 150 150', Type1Described(CharString));
end;

procedure TCharStringPathTests.TestType1WithoutMovetoStartsTheSubpath;
begin
  Assert.AreEqual('M 50 0', Type1Described(Encode([0, 500, Hsbw, 50, 0, Rlineto, Endchar])));
  Assert.IsTrue(FMessages.Count > 0);
end;

procedure TCharStringPathTests.TestType2LinesAndImplicitClose;
begin
  Assert.AreEqual('M 100 100 L 150 100 Z M 150 100', Type2Described(Encode([100, 100, Rmoveto, 50, 0, Rlineto, Endchar])));
end;

// The mask of hintmask follows it in the charstring: 2 stems need one byte, and 192 would be a number otherwise
procedure TCharStringPathTests.TestType2HintMaskBytesAreSkipped;
begin
  const CharString = Encode([10, 20, Hstem, 30, 40, Hintmask, RawByte + 192, 100, 100, Rmoveto, 50, 0, Rlineto, Endchar]);

  Assert.AreEqual('M 100 100 L 150 100 Z M 150 100', Type2Described(CharString));
end;

procedure TCharStringPathTests.TestType2AlternatingCurves;
begin
  const CharString = Encode([100, 100, Rmoveto, 10, 20, 30, 40, Hvcurveto, Endchar]);

  Assert.AreEqual('M 100 100 C 110 100 130 130 130 170 Z M 130 170', Type2Described(CharString));
end;

// The operand -107 is the first subr of a font with fewer than 1240 subrs
procedure TCharStringPathTests.TestType2SubrIsCalled;
begin
  const Subrs: TArray<TBytes> = [Encode([50, 0, Rlineto, Return])];

  Assert.AreEqual('M 100 100 L 150 100 Z M 150 100', Type2Described(Encode([100, 100, Rmoveto, -107, Callsubr, Endchar]), Subrs));
end;

procedure TCharStringPathTests.TestType2DamagedCharStringGivesPartialPath;
begin
  // A shortint that ends after its first byte
  const CharString = Encode([100, 100, Rmoveto, 50, 0, Rlineto, RawByte + 28, RawByte + 0]);

  const Description = Type2Described(CharString);

  Assert.AreEqual('M 100 100 L 150 100', Description);
  Assert.IsTrue(FMessages.Count > 0);
end;

procedure TCharStringPathTests.TestType2FlexGivesTwoCurves;
begin
  const CharString = Encode([100, 100, Rmoveto, 10, 0, 10, 10, 10, 0, 10, 0, 10, -10, 10, 0, 50, Flex, Endchar]);

  Assert.AreEqual('M 100 100 C 110 100 120 110 130 110 C 140 110 150 100 160 100 Z M 160 100', Type2Described(CharString));
end;

procedure TCharStringPathTests.TestType2DivisionIsCollapsed;
begin
  const CharString = Encode([100, 100, Rmoveto, 100, 2, Div_, 0, Rlineto, Endchar]);

  Assert.AreEqual('M 100 100 L 150 100 Z M 150 100', Type2Described(CharString));
end;

class function TCharStringPathTests.SeacBase: TBytes;
begin
  Result := Encode([10, 20, Rmoveto, 50, 0, Rlineto, 0, 50, Rlineto, Endchar]);
end;

class function TCharStringPathTests.SeacAccent: TBytes;
begin
  Result := Encode([0, 0, Rmoveto, 30, 0, Rlineto, 0, 30, Rlineto, Endchar]);
end;

// adx ady bchar achar endchar, with the codes 65 (A) and 66 (B) of StandardEncoding
class function TCharStringPathTests.SeacCharString: TBytes;
begin
  Result := Encode([5, 7, 65, 66, Endchar]);
end;

procedure TCharStringPathTests.TestType2SeacComposesAccentThroughLookup;
begin
  const Lookup: TFunc<string, TBytes> =
    function(GlyphName: string): TBytes
    begin
      if GlyphName = 'A' then
      begin
        Exit(SeacBase);
      end;
      Result := SeacAccent;
    end;

  const Path = TCharStringPath.Type2Path(SeacCharString, nil, nil, Lookup, FLog);
  try
    CheckSameTokens(SeacExpected, Describe(Path), 'seac');
  finally
    Path.Free;
  end;
end;

procedure TCharStringPathTests.TestType2SeacWithoutLookupLeavesOutTheAccent;
begin
  const Path = TCharStringPath.Type2Path(SeacCharString, nil, nil, FLog);
  try
    Assert.AreEqual('', Describe(Path));
  finally
    Path.Free;
  end;
  Assert.IsTrue(FMessages.Count > 0, 'The missing accent is logged');
end;

// Glyph 1 is A, 2 is B (charset SIDs 34 and 35) and 3 is the seac of both
procedure TCharStringPathTests.TestCffFontComposesType2Seac;
begin
  var Options := TCffType1Options.Standard;
  Options.GlyphCount := 4;
  Options.CharsetData := TCffTestBuilder.Bytes([0, 0, 34, 0, 35, 0, 36]);
  Options.CharStrings := [Encode([Endchar]), SeacBase, SeacAccent, SeacCharString];
  const Parser = TCFFParser.Create(FLog);
  try
    const Fonts = Parser.Parse(TCffTestBuilder.Type1Font(Options));
    try
      const Font = Fonts[0] as TCFFType1Font;
      var Path: TPdfPath;

      Assert.IsTrue(Font.TryGetPathByGid(3, Path));
      try
        CheckSameTokens(SeacExpected, Describe(Path), 'seac glyph');
      finally
        Path.Free;
      end;

      Assert.IsTrue(Font.TryGetPathByGid(1, Path));
      try
        CheckSameTokens(SeacBaseOnly, Describe(Path), 'base glyph');
      finally
        Path.Free;
      end;
    finally
      Fonts.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TCharStringPathTests.TestCidPathByCid;
begin
  const Parser = TCFFParser.Create(FLog);
  try
    const Fonts = Parser.Parse(TCffTestBuilder.CidKeyed('Adobe', 'Identity', 0, [5, 7], [500, 500]));
    try
      const Font = Fonts[0] as TCFFCIDFont;
      var Path: TPdfPath;

      Assert.IsTrue(Font.TryGetPathByCid(7, Path));
      Path.Free;
      Assert.IsTrue(Font.TryGetPathByGid(1, Path));
      Path.Free;
      // A CID that the charset does not have gets .notdef
      Assert.IsTrue(Font.TryGetPathByCid(99, Path));
      Path.Free;
      Assert.IsTrue(Font.TryGetPath(Char(92) + '7', Path));
      Assert.IsTrue(Path.IsEmpty);
      Path.Free;
      var IsRaised := False;
      try
        Font.TryGetPath('7', Path);
      except
        on EPdfParseException do
        begin
          IsRaised := True;
        end;
      end;
      Assert.IsTrue(IsRaised);
    finally
      Fonts.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TCharStringPathTests.TestPathOfMissingGlyphIsNotdef;
begin
  const Font = TType1Font.CreateWithPFB(TTestFonts.Bytes('OpenSans-Regular.pfb'));
  try
    var Missing: TPdfPath;
    var Notdef: TPdfPath;

    Assert.IsTrue(Font.TryGetPath('NoSuchGlyph', Missing));
    try
      Assert.IsTrue(Font.TryGetPath('.notdef', Notdef));
      try
        Assert.AreEqual(Describe(Notdef), Describe(Missing));
        Assert.IsFalse(Missing.IsEmpty);
      finally
        Notdef.Free;
      end;
    finally
      Missing.Free;
    end;
  finally
    Font.Free;
  end;
end;

end.
