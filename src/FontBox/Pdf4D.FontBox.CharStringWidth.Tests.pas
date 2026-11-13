// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Tests of Pdf4D for fontbox/src/main/java/org/apache/fontbox/cff/Type1CharStringParser.java, Type2CharStringParser.java and
// Type2CharString.java (3.0.8); the reference widths come from PDFBox
unit Pdf4D.FontBox.CharStringWidth.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Common.Log,
  Pdf4D.FontBox.Cff.Font;

type
  TCffFontCheck = reference to procedure(const Font: TCFFFont);

  [TestFixture]
  TCharStringWidthTests = class
  private
    FMessages: TList<string>;
    FLog: TPdfLog;

    class function Bytes(const Values: array of Byte): TBytes; static;
    class function Repeated(const Value: Byte; const Count: Integer): TBytes; static;
    class function Type2WidthOf(const CharString: TBytes; const LocalSubrs: TArray<TBytes> = nil;
                                const GlobalSubrs: TArray<TBytes> = nil): Integer;
    procedure CheckReferenceWidths(const FontFile: string);
    procedure CheckWithCffFont(const Data: TBytes; const Check: TCffFontCheck);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestType1Hsbw;

    [Test]
    procedure TestType1HsbwInsideSubr;

    [Test]
    procedure TestType1Sbw;

    [Test]
    procedure TestType1HintReplacementUnrollsTheSubr;

    [Test]
    procedure TestType1WithoutHsbwGivesFalse;

    [Test]
    procedure TestType1RecursiveSubrStops;

    [Test]
    procedure TestType1SubrIndexOutOfRangeIsIgnored;

    [Test]
    procedure TestType1TruncatedCharStringIsLenient;

    [Test]
    procedure TestType1CallOtherSubrWithoutOperandsIsLenient;

    [Test]
    procedure TestType1DivisionByZeroIsLenient;

    [Test]
    procedure TestType2ExplicitWidth;

    [Test]
    procedure TestType2DefaultWidth;

    [Test]
    procedure TestType2WidthFromEndCharWithOneOperand;

    [Test]
    procedure TestType2WidthFromEndCharWithSeacOperands;

    [Test]
    procedure TestType2WidthFromStemHint;

    [Test]
    procedure TestType2WidthFromHintMaskWithoutMaskBytes;

    [Test]
    procedure TestType2WidthFromRMoveTo;

    [Test]
    procedure TestType2WidthInsideLocalSubr;

    [Test]
    procedure TestType2WidthInsideGlobalSubr;

    [Test]
    procedure TestType2DivisionIsCollapsed;

    [Test]
    procedure TestType2WithoutStackClearingOperatorIsZero;

    [Test]
    procedure TestType2OperatorBeforeTheFirstMoveGivesNoWidth;

    [Test]
    procedure TestType2WidthsMatchReference;

    [Test]
    procedure TestType2WidthsMatchReferenceOfSecondFont;

    [Test]
    procedure TestRecursiveSubrStops;

    [Test]
    procedure TestSubrsNestedToTheLimitStillWork;

    [Test]
    procedure TestSubrIndexOutOfRangeGivesDefault;

    [Test]
    procedure TestCallSubrWithoutSubrsKeepsTheOperand;

    [Test]
    procedure TestTruncatedCharStringIsLenient;

    [Test]
    procedure TestTruncatedHintMaskIsLenient;

    [Test]
    procedure TestTooManyOperationsGivesDefault;

    [Test]
    procedure TestTooManyOperandsGivesDefault;

    [Test]
    procedure TestFlexWithTooFewOperandsGivesDefault;

    [Test]
    procedure TestCallSubrWithFixedPointOperandGivesDefault;

    [Test]
    procedure TestEmptyCharStringIsZero;

    [Test]
    procedure TestGlyphBeyondTheCharStringsGetsNotdef;

    [Test]
    procedure TestCidWidthsFollowThePrivateDict;

    [Test]
    procedure TestCidWidthByCidBeyondTheCharStringsGetsDefault;

    [Test]
    procedure TestCidSelectorWidth;

    [Test]
    procedure TestCidInvalidSelectorRaises;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.FontBox.CharStringWidth,
  Pdf4D.FontBox.Cff.Charset,
  Pdf4D.FontBox.Cff.Parser,
  Pdf4D.FontBox.OpenType,
  Pdf4D.Tests.CffBuilder,
  Pdf4D.Tests.TestFonts;

const
  Default333 = 333;
  Nominal500 = 500;
  Endchar = 14;
  Hmoveto = 22;
  Callsubr = 10;
  Callgsubr = 29;
  Return = 11;

{ TCharStringWidthTests }

procedure TCharStringWidthTests.CheckWithCffFont(const Data: TBytes; const Check: TCffFontCheck);
begin
  const Parser = TCFFParser.Create(FLog);
  try
    const Fonts = Parser.Parse(Data);
    try
      Assert.AreEqual(1, Integer(Fonts.Count));
      Check(Fonts[0]);
    finally
      Fonts.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TCharStringWidthTests.Setup;
begin
  FMessages := TList<string>.Create;
  FLog := TPdfLog.Create(
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      FMessages.Add(Message);
    end);
end;

procedure TCharStringWidthTests.TearDown;
begin
  FLog.Free;
  FMessages.Free;
end;

class function TCharStringWidthTests.Bytes(const Values: array of Byte): TBytes;
begin
  SetLength(Result, Length(Values));
  for var Index := 0 to High(Values) do
  begin
    Result[Index] := Values[Index];
  end;
end;

class function TCharStringWidthTests.Repeated(const Value: Byte; const Count: Integer): TBytes;
begin
  SetLength(Result, Count);
  for var Index := 0 to Count - 1 do
  begin
    Result[Index] := Value;
  end;
end;

class function TCharStringWidthTests.Type2WidthOf(const CharString: TBytes; const LocalSubrs: TArray<TBytes>;
                                                  const GlobalSubrs: TArray<TBytes>): Integer;
begin
  Result := TCharStringWidth.Type2Width(CharString, GlobalSubrs, LocalSubrs, Default333, Nominal500);
end;

procedure TCharStringWidthTests.TestType1Hsbw;
begin
  var Width: Integer;

  const Found = TCharStringWidth.Type1Width(Bytes([189, 248, 236, 13]), nil, Width);

  Assert.IsTrue(Found);
  Assert.AreEqual(600, Width);
end;

procedure TCharStringWidthTests.TestType1HsbwInsideSubr;
begin
  var Width: Integer;
  const Subrs: TArray<TBytes> = [Bytes([189, 248, 236, 13, 11])];

  const Found = TCharStringWidth.Type1Width(Bytes([139, 10]), Subrs, Width);

  Assert.IsTrue(Found);
  Assert.AreEqual(600, Width);
end;

// sbx sby wx wy sbw
procedure TCharStringWidthTests.TestType1Sbw;
begin
  var Width: Integer;

  const Found = TCharStringWidth.Type1Width(Bytes([189, 139, 248, 236, 139, 12, 7]), nil, Width);

  Assert.IsTrue(Found);
  Assert.AreEqual(600, Width);
end;

// "7 1 3 callothersubr pop callsubr" calls subr 7: the result of the othersubr becomes the operand of callsubr
procedure TCharStringWidthTests.TestType1HintReplacementUnrollsTheSubr;
begin
  var Width: Integer;
  var Subrs: TArray<TBytes>;
  SetLength(Subrs, 8);
  Subrs[7] := Bytes([189, 248, 236, 13, 11]);

  const Found = TCharStringWidth.Type1Width(Bytes([146, 140, 142, 12, 16, 12, 17, 10]), Subrs, Width);

  Assert.IsTrue(Found);
  Assert.AreEqual(600, Width);
end;

procedure TCharStringWidthTests.TestType1WithoutHsbwGivesFalse;
begin
  var Width: Integer;

  Assert.IsFalse(TCharStringWidth.Type1Width(Bytes([139, 139, 21, 14]), nil, Width));
  Assert.IsFalse(TCharStringWidth.Type1Width(nil, nil, Width));
end;

procedure TCharStringWidthTests.TestType1RecursiveSubrStops;
begin
  var Width: Integer;
  const Subrs: TArray<TBytes> = [Bytes([139, 10])];

  const Found = TCharStringWidth.Type1Width(Bytes([139, 10]), Subrs, Width, FLog);

  Assert.IsFalse(Found);
  Assert.IsTrue(FMessages.Count > 0);
end;

procedure TCharStringWidthTests.TestType1SubrIndexOutOfRangeIsIgnored;
begin
  var Width: Integer;
  const Subrs: TArray<TBytes> = [Bytes([11])];

  // 99 callsubr is ignored with a warning; the hsbw after it still counts
  const Found = TCharStringWidth.Type1Width(Bytes([238, 10, 189, 248, 236, 13]), Subrs, Width, FLog);

  Assert.IsTrue(Found);
  Assert.AreEqual(600, Width);
  Assert.IsTrue(FMessages.Count > 0);
end;

procedure TCharStringWidthTests.TestType1TruncatedCharStringIsLenient;
begin
  var Width: Integer;

  Assert.WillNotRaise(
    procedure
    begin
      TCharStringWidth.Type1Width(Bytes([255, 0, 0]), nil, Width, FLog);
      TCharStringWidth.Type1Width(Bytes([248]), nil, Width, FLog);
      TCharStringWidth.Type1Width(Bytes([12]), nil, Width, FLog);
      TCharStringWidth.Type1Width(Bytes([139, 139, 12, 16]), nil, Width, FLog);
    end);
  Assert.IsFalse(TCharStringWidth.Type1Width(Bytes([255, 0, 0]), nil, Width, FLog));
end;

procedure TCharStringWidthTests.TestType1CallOtherSubrWithoutOperandsIsLenient;
begin
  var Width: Integer;

  Assert.IsFalse(TCharStringWidth.Type1Width(Bytes([12, 16, 12, 17]), nil, Width, FLog));
  Assert.IsFalse(TCharStringWidth.Type1Width(Bytes([139, 12, 16, 12, 17]), nil, Width, FLog));
  // The number of arguments is far larger than the stack
  Assert.IsFalse(TCharStringWidth.Type1Width(Bytes([255, 127, 255, 255, 255, 139 + 5, 12, 16, 12, 17]), nil, Width, FLog));
end;

procedure TCharStringWidthTests.TestType1DivisionByZeroIsLenient;
begin
  var Width: Integer;

  // "5 0 div 1 3 callothersubr pop": the quotient is needed as an integer
  const Found = TCharStringWidth.Type1Width(Bytes([144, 139, 12, 12, 140, 142, 12, 16, 12, 17]), nil, Width, FLog);

  Assert.IsFalse(Found);
end;

procedure TCharStringWidthTests.TestType2ExplicitWidth;
begin
  Assert.AreEqual(600, Type2WidthOf(Bytes([239, 139, Hmoveto])));
end;

procedure TCharStringWidthTests.TestType2DefaultWidth;
begin
  Assert.AreEqual(Default333, Type2WidthOf(Bytes([139, Hmoveto])));
end;

procedure TCharStringWidthTests.TestType2WidthFromEndCharWithOneOperand;
begin
  Assert.AreEqual(600, Type2WidthOf(Bytes([239, Endchar])));
  Assert.AreEqual(Default333, Type2WidthOf(Bytes([Endchar])));
end;

// The deprecated seac form: width adx ady bchar achar endchar
procedure TCharStringWidthTests.TestType2WidthFromEndCharWithSeacOperands;
begin
  Assert.AreEqual(600, Type2WidthOf(Bytes([239, 139, 139, 140, 141, Endchar])));
  // Four operands is seac without a width
  Assert.AreEqual(Default333, Type2WidthOf(Bytes([139, 139, 140, 141, Endchar])));
end;

procedure TCharStringWidthTests.TestType2WidthFromStemHint;
begin
  // width hstem pair: three operands is odd
  Assert.AreEqual(600, Type2WidthOf(Bytes([239, 139, 140, 1])));
  Assert.AreEqual(Default333, Type2WidthOf(Bytes([139, 140, 3])));
end;

procedure TCharStringWidthTests.TestType2WidthFromHintMaskWithoutMaskBytes;
begin
  // A hintmask as the first operator after a width: the mask bytes are not needed for the width
  Assert.AreEqual(600, Type2WidthOf(Bytes([239, 19])));
  Assert.AreEqual(600, Type2WidthOf(Bytes([239, 20])));
  Assert.AreEqual(Default333, Type2WidthOf(Bytes([239, 139, 19])));
end;

procedure TCharStringWidthTests.TestType2WidthFromRMoveTo;
begin
  Assert.AreEqual(600, Type2WidthOf(Bytes([239, 139, 139, 21])));
  Assert.AreEqual(Default333, Type2WidthOf(Bytes([139, 139, 21])));
end;

// -107 callsubr: subr number 0
procedure TCharStringWidthTests.TestType2WidthInsideLocalSubr;
begin
  const Subrs: TArray<TBytes> = [Bytes([239, 139, Return])];

  Assert.AreEqual(600, Type2WidthOf(Bytes([32, Callsubr, Hmoveto]), Subrs));
end;

procedure TCharStringWidthTests.TestType2WidthInsideGlobalSubr;
begin
  const Subrs: TArray<TBytes> = [Bytes([239, 139, Return])];

  Assert.AreEqual(600, Type2WidthOf(Bytes([32, Callgsubr, Hmoveto]), nil, Subrs));
  // The subroutine itself ends the charstring
  const Ending: TArray<TBytes> = [Bytes([239, Endchar])];
  Assert.AreEqual(600, Type2WidthOf(Bytes([32, Callgsubr]), nil, Ending));
end;

// 10 20 div 5 hmoveto: the division becomes one operand (0.5), so there are two operands and the width is 0.5 + 500
procedure TCharStringWidthTests.TestType2DivisionIsCollapsed;
begin
  Assert.AreEqual(500, Type2WidthOf(Bytes([149, 159, 12, 12, 144, Hmoveto])));
  // 10 20 div hmoveto leaves one operand: the default width
  Assert.AreEqual(Default333, Type2WidthOf(Bytes([149, 159, 12, 12, Hmoveto])));
  // A division by zero does not raise
  Assert.WillNotRaise(
    procedure
    begin
      Type2WidthOf(Bytes([149, 139, 12, 12, 139, Hmoveto]));
    end);
end;

procedure TCharStringWidthTests.TestType2WithoutStackClearingOperatorIsZero;
begin
  Assert.AreEqual(0, Type2WidthOf(Bytes([139, 139, 5])));
  Assert.AreEqual(0, Type2WidthOf(Bytes([139, 139])));
end;

// PDFBox adds the width only when the converted sequence is still empty, so a rlineto before the first move leaves it at 0
procedure TCharStringWidthTests.TestType2OperatorBeforeTheFirstMoveGivesNoWidth;
begin
  Assert.AreEqual(0, Type2WidthOf(Bytes([139, 139, 5, 239, 139, Hmoveto])));
  // A rlineto without operands converts to nothing
  Assert.AreEqual(600, Type2WidthOf(Bytes([5, 239, 139, Hmoveto])));
end;

procedure TCharStringWidthTests.CheckReferenceWidths(const FontFile: string);
begin
  const Reference = TTestFonts.ReferenceWidths(FontFile);
  try
    const Parser = TOTFParser.Create;
    try
      const Font = Parser.Parse(TTestFonts.Bytes(FontFile));
      try
        const Cff = Font.CFF;
        var Checked := 0;
        for var Pair in Reference do
        begin
          const IsGlyphKey = Pair.Key.StartsWith('gid');
          if IsGlyphKey then
          begin
            const GID = StrToInt(Pair.Key.Substring(3));
            var Actual: Single;
            if Cff is TCFFCIDFont then
            begin
              Actual := TCFFCIDFont(Cff).GetWidthForCID(Cff.Charset.GetCIDForGID(GID));
            end
            else
            begin
              Actual := Cff.GetWidth(Cff.Charset.GetNameForGID(GID));
            end;
            Assert.AreEqual(Pair.Value, Actual, Format('Width of %s in %s', [Pair.Key, FontFile]));
            Inc(Checked);
          end;
        end;
        Assert.AreEqual(Integer(Font.NumberOfGlyphs), Checked);
      finally
        Font.Free;
      end;
    finally
      Parser.Free;
    end;
  finally
    Reference.Free;
  end;
end;

procedure TCharStringWidthTests.TestType2WidthsMatchReference;
begin
  CheckReferenceWidths('SourceSansProBold.otf');
end;

procedure TCharStringWidthTests.TestType2WidthsMatchReferenceOfSecondFont;
begin
  CheckReferenceWidths('FoglihtenNo07.otf');
end;

procedure TCharStringWidthTests.TestRecursiveSubrStops;
begin
  // -107 callsubr in subr 0: subr 0 calls itself
  const Subrs: TArray<TBytes> = [Bytes([32, Callsubr])];

  const Width = TCharStringWidth.Type2Width(Bytes([32, Callsubr]), nil, Subrs, Default333, Nominal500, FLog);

  Assert.AreEqual(Default333, Width);
  Assert.IsTrue(FMessages.Count > 0);
  Assert.IsTrue(FMessages[0].Contains('deeper'));
end;

procedure TCharStringWidthTests.TestSubrsNestedToTheLimitStillWork;
begin
  // Subr n calls subr n + 1; the last one pushes the width and ends
  var Subrs: TArray<TBytes>;
  SetLength(Subrs, MaxSubrDepth);
  for var Index := 0 to MaxSubrDepth - 2 do
  begin
    Subrs[Index] := Bytes([Byte(Index + 1 - 107 + 139), Callsubr, Return]);
  end;
  Subrs[MaxSubrDepth - 1] := Bytes([239, 139, Return]);

  const Width = TCharStringWidth.Type2Width(Bytes([32, Callsubr, Hmoveto]), nil, Subrs, Default333, Nominal500, FLog);

  Assert.AreEqual(600, Width);
  Assert.AreEqual(0, Integer(FMessages.Count));
end;

procedure TCharStringWidthTests.TestSubrIndexOutOfRangeGivesDefault;
begin
  const Subrs: TArray<TBytes> = [Bytes([Return])];

  // The operand 100 gives subr number 207, a negative operand gives a negative number
  Assert.AreEqual(Default333, TCharStringWidth.Type2Width(Bytes([239, Callsubr, Hmoveto]), nil, Subrs, Default333, Nominal500, FLog));
  Assert.AreEqual(Default333, TCharStringWidth.Type2Width(Bytes([28, 128, 0, Callsubr, Hmoveto]), nil, Subrs, Default333, Nominal500, FLog));
  Assert.AreEqual(Default333, TCharStringWidth.Type2Width(Bytes([28, 127, 255, Callgsubr, Hmoveto]), Subrs, nil, Default333, Nominal500, FLog));
  Assert.IsTrue(FMessages.Count >= 3);
end;

// PDFBox does not call anything when there are no subroutines, and the operand stays on the stack
procedure TCharStringWidthTests.TestCallSubrWithoutSubrsKeepsTheOperand;
begin
  Assert.AreEqual(Default333, Type2WidthOf(Bytes([139, Callsubr, Hmoveto])));
  Assert.AreEqual(600, Type2WidthOf(Bytes([239, 139, Callsubr, Hmoveto])));
end;

procedure TCharStringWidthTests.TestTruncatedCharStringIsLenient;
begin
  // A number that stops in the middle, in each of the forms
  Assert.AreEqual(Default333, TCharStringWidth.Type2Width(Bytes([28, 1]), nil, nil, Default333, Nominal500, FLog));
  Assert.AreEqual(Default333, TCharStringWidth.Type2Width(Bytes([247]), nil, nil, Default333, Nominal500, FLog));
  Assert.AreEqual(Default333, TCharStringWidth.Type2Width(Bytes([251]), nil, nil, Default333, Nominal500, FLog));
  Assert.AreEqual(Default333, TCharStringWidth.Type2Width(Bytes([255, 0, 1, 2]), nil, nil, Default333, Nominal500, FLog));
  Assert.AreEqual(Default333, TCharStringWidth.Type2Width(Bytes([12]), nil, nil, Default333, Nominal500, FLog));
  Assert.IsTrue(FMessages.Count >= 5);
end;

procedure TCharStringWidthTests.TestTruncatedHintMaskIsLenient;
begin
  // The width is known before the mask bytes would be read
  Assert.AreEqual(600, TCharStringWidth.Type2Width(Bytes([239, 139, 140, 1, 19]), nil, nil, Default333, Nominal500, FLog));
end;

procedure TCharStringWidthTests.TestTooManyOperationsGivesDefault;
begin
  // Rlineto without operands does nothing, so a long run of them never reaches an operator that clears the stack
  const CharString = Repeated(5, MaxOperations + 10);

  Assert.AreEqual(Default333, TCharStringWidth.Type2Width(CharString, nil, nil, Default333, Nominal500, FLog));
  Assert.IsTrue(FMessages.Count > 0);
end;

procedure TCharStringWidthTests.TestTooManyOperandsGivesDefault;
begin
  const CharString = TCffTestBuilder.Concat([Repeated(139, MaxOperands + 1), Bytes([Hmoveto])]);

  Assert.AreEqual(Default333, TCharStringWidth.Type2Width(CharString, nil, nil, Default333, Nominal500, FLog));
  Assert.IsTrue(FMessages.Count > 0);
end;

procedure TCharStringWidthTests.TestFlexWithTooFewOperandsGivesDefault;
begin
  Assert.AreEqual(Default333, TCharStringWidth.Type2Width(Bytes([139, 139, 12, 35, Endchar]), nil, nil, Default333, Nominal500, FLog));
  Assert.AreEqual(Default333, TCharStringWidth.Type2Width(Bytes([139, 139, 12, 37, Endchar]), nil, nil, Default333, Nominal500, FLog));
  Assert.IsTrue(FMessages.Count >= 2);
end;

// The 16.16 number is not an integer, so it cannot be a subroutine number
procedure TCharStringWidthTests.TestCallSubrWithFixedPointOperandGivesDefault;
begin
  const Subrs: TArray<TBytes> = [Bytes([239, 139, Return])];

  Assert.AreEqual(Default333, TCharStringWidth.Type2Width(Bytes([255, 0, 0, 0, 1, Callsubr, Hmoveto]), nil, Subrs, Default333, Nominal500, FLog));
end;

procedure TCharStringWidthTests.TestEmptyCharStringIsZero;
begin
  Assert.AreEqual(0, Type2WidthOf(nil));
end;

procedure TCharStringWidthTests.TestGlyphBeyondTheCharStringsGetsNotdef;
begin
  var Options := TCffType1Options.Standard;
  Options.GlyphCount := 3;

  CheckWithCffFont(TCffTestBuilder.Type1Font(Options),
    procedure(const Font: TCFFFont)
    begin
      // The glyphs are all "endchar": the default width of the font
      Assert.AreEqual<Single>(Options.DefaultWidthX, Font.GetWidth('unknown'));
      Assert.AreEqual<Single>(Options.DefaultWidthX, TCFFType1Font(Font).GetWidthForGID(1));
      Assert.AreEqual<Single>(Options.DefaultWidthX, TCFFType1Font(Font).GetWidthForGID(999));
      Assert.AreEqual<Single>(Options.DefaultWidthX, TCFFType1Font(Font).GetWidthForGID(-1));
    end);
end;

procedure TCharStringWidthTests.TestCidWidthsFollowThePrivateDict;
begin
  CheckWithCffFont(TCffTestBuilder.CidKeyed('Adobe', 'Japan1', 6, [843, 844], [480, 520]),
    procedure(const Font: TCFFFont)
    begin
      const CidFont = TCFFCIDFont(Font);
      Assert.AreEqual<Single>(480, CidFont.GetWidthForCID(843));
      Assert.AreEqual<Single>(520, CidFont.GetWidthForCID(844));
      // A CID that the charset does not have is .notdef, which has the default width
      Assert.AreEqual<Single>(1000, CidFont.GetWidthForCID(1));
    end);
end;

// The charset maps CID 1000 to a glyph that the font does not have: .notdef, with the private DICT of that glyph
procedure TCharStringWidthTests.TestCidWidthByCidBeyondTheCharStringsGetsDefault;
begin
  var Options := TCffCidOptions.Standard;
  Options.CIDs := [0];
  Options.Widths := [500];
  Options.CharsetData := TCffTestBuilder.Bytes([2, 0, 0, $FF, $FF]);

  CheckWithCffFont(TCffTestBuilder.CidFont(Options),
    procedure(const Font: TCFFFont)
    begin
      const CidFont = TCFFCIDFont(Font);
      Assert.AreEqual(1001, CidFont.CIDToGID(1000));
      Assert.AreEqual<Single>(1000, CidFont.GetWidthForCID(1000));
      Assert.AreEqual<Single>(1000, CidFont.GetWidthForCID(Integer.MaxValue));
      Assert.AreEqual<Single>(1000, CidFont.GetWidthForCID(-5));
    end);
end;

procedure TCharStringWidthTests.TestCidSelectorWidth;
begin
  CheckWithCffFont(TCffTestBuilder.CidKeyed('Adobe', 'Japan1', 6, [843, 844], [480, 520]),
    procedure(const Font: TCFFFont)
    begin
      Assert.AreEqual<Single>(520, Font.GetWidth('\844'));
    end);
end;

procedure TCharStringWidthTests.TestCidInvalidSelectorRaises;
begin
  CheckWithCffFont(TCffTestBuilder.CidKeyed('Adobe', 'Japan1', 6, [843], [480]),
    procedure(const Font: TCFFFont)
    begin
      Assert.WillRaise(
        procedure
        begin
          Font.GetWidth('A');
        end,
        EPdfParseException);
    end);
end;

end.
