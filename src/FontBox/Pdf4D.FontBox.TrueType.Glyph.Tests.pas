// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Tests of Pdf4D for fontbox/src/main/java/org/apache/fontbox/ttf/GlyphTable.java, GlyfSimpleDescript.java,
// GlyfCompositeDescript.java and GlyphRenderer.java (3.0.8); the reference paths come from PDFBox
unit Pdf4D.FontBox.TrueType.Glyph.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Common.Defines,
  Pdf4D.Common.Log,
  Pdf4D.Common.Path,
  Pdf4D.FontBox.TrueType.Font;

type
  // A glyph of a composite glyph that a test writes
  TTestComponent = record
    GlyphIndex: Integer;
    Flags: Integer;
    Argument1: Integer;
    Argument2: Integer;
    Scales: TArray<Integer>;
  end;

  [TestFixture]
  TTrueTypeGlyphTests = class
  private
    FMessages: TList<string>;
    FLog: TPdfLog;

    class function VerbName(const Verb: TPdfPathVerb): string; static;
    class function VerbPointCount(const Verb: TPdfPathVerb): Integer; static;
    class function Describe(const Path: TPdfPath): string; static;
    class function Tokens(const Text: string): TArray<string>; static;
    class procedure CheckSameTokens(const Expected, Actual, Context: string); static;
    class function ReferenceLines(const FontFile: string): TDictionary<string, string>; static;
    class function Component(const GlyphIndex, Flags, Argument1, Argument2: Integer; const Scales: array of Integer): TTestComponent; static;
    class function SimpleGlyph(const MinimumX: Integer; const EndPoints, Coordinates: array of Integer): TBytes; static;
    class function CompositeGlyph(const Components: array of TTestComponent): TBytes; static;
    class function RawSimpleGlyph(const MinimumX: Integer; const Body: array of Integer): TBytes; static;
    class function LeftSideBearing(const FontData: TBytes; const GID: Integer): Integer; static;
    class function PatchedFont(const Glyphs: array of TBytes; const MaximumDepth: Integer = 4): TBytes; static;
    class procedure SetLocaEntry(const FontData: TBytes; const GID, Offset: Integer); static;
    class function GlyphOffset(const FontData: TBytes; const GID: Integer): Integer; static;
    class function IsComposite(const FontData: TBytes; const GID: Integer): Boolean; static;

    function Parse(const FontData: TBytes): TTrueTypeFont;
    function DescribedGlyph(const FontData: TBytes; const GID: Integer): string;
    function SquareGlyph(const GID: Integer; const FontData: TBytes): TBytes;
    procedure CheckReferencePaths(const FontFile: string);
    function HasMessage(const Part: string): Boolean;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestGlyfPathsMatchPdfBox;

    [Test]
    procedure TestGlyfPathsMatchPdfBoxOfSecondFont;

    [Test]
    procedure TestPathByNameUsesTheGlyphOfTheName;

    [Test]
    procedure TestCompositeGlyphUsesComponentTransforms;

    [Test]
    procedure TestCompositeGlyphScaleAndTranslation;

    [Test]
    procedure TestCompositeGlyphTwoByTwoTransformation;

    [Test]
    procedure TestCompositeGlyphWithTwoComponentsHasTwoContours;

    [Test]
    procedure TestCompositeGlyphCycleStops;

    [Test]
    procedure TestCompositeGlyphCycleKeepsTheOtherComponents;

    [Test]
    procedure TestCompositeGlyphBeyondMaximumDepthIsLeftOut;

    [Test]
    procedure TestCompositeGlyphWithTooManyReadsStops;

    [Test]
    procedure TestTruncatedGlyfGivesNoPath;

    [Test]
    procedure TestGlyphCutOffInsideItsDataGivesNoPath;

    [Test]
    procedure TestEmptyGlyphIsEmptyPath;

    [Test]
    procedure TestGlyphBeyondTheNumberOfGlyphsIsEmptyPath;

    [Test]
    procedure TestContourOfOffCurvePointsStartsInTheMiddle;

    [Test]
    procedure TestRepeatedFlagsAndShortCoordinates;

    [Test]
    procedure TestNegativeShortCoordinates;

    [Test]
    procedure TestOpenTypeWithCffOutlinesUsesTheCffTable;
  end;

implementation

uses
  System.IOUtils,
  Pdf4D.FontBox.OpenType,
  Pdf4D.FontBox.TrueType.Parser,
  Pdf4D.Tests.TestFonts,
  Pdf4D.Tests.TrueTypeBuilder;

const
  LiberationFont = 'LiberationSans-Regular.ttf';
  SecondFont = 'JosefinSans-Italic.ttf';
  PathsSuffix = '.paths.txt';
  PathTolerance = 0.01;
  GlyphKeyPrefix = 'gid';
  MaximumDepthOffset = 30;
  IndexToLocFormatOffset = 50;
  GlyphCountOffset = 4;

  OnCurveFlag = $01;
  ArgumentsAreXYValues = $0002;
  HasScale = $0008;
  MoreComponents = $0020;
  HasTwoByTwo = $0080;

  // 1.0 in the 2.14 fixed point of the composite glyph scales
  FixedOne = $4000;

{ TTrueTypeGlyphTests }

procedure TTrueTypeGlyphTests.Setup;
begin
  FMessages := TList<string>.Create;
  FLog := TPdfLog.Create(
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      FMessages.Add(Message);
    end);
end;

procedure TTrueTypeGlyphTests.TearDown;
begin
  FLog.Free;
  FMessages.Free;
end;

function TTrueTypeGlyphTests.HasMessage(const Part: string): Boolean;
begin
  for var Message in FMessages do
  begin
    if Message.Contains(Part) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TTrueTypeGlyphTests.VerbName(const Verb: TPdfPathVerb): string;
begin
  case Verb of
    TPdfPathVerb.MoveTo  : Result := 'M';
    TPdfPathVerb.LineTo  : Result := 'L';
    TPdfPathVerb.QuadTo  : Result := 'Q';
    TPdfPathVerb.CubicTo : Result := 'C';
    TPdfPathVerb.Close   : Result := 'Z';
  else
    raise EArgumentException.Create('Unknown path verb');
  end;
end;

class function TTrueTypeGlyphTests.VerbPointCount(const Verb: TPdfPathVerb): Integer;
begin
  case Verb of
    TPdfPathVerb.MoveTo, TPdfPathVerb.LineTo : Result := 1;
    TPdfPathVerb.QuadTo                      : Result := 2;
    TPdfPathVerb.CubicTo                     : Result := 3;
    TPdfPathVerb.Close                       : Result := 0;
  else
    raise EArgumentException.Create('Unknown path verb');
  end;
end;

class function TTrueTypeGlyphTests.Describe(const Path: TPdfPath): string;
begin
  const Parts = TList<string>.Create;
  try
    var PointIndex := 0;
    for var VerbIndex := 0 to Path.VerbCount - 1 do
    begin
      const Verb = Path.Verb(VerbIndex);
      Parts.Add(VerbName(Verb));
      for var Count := 1 to VerbPointCount(Verb) do
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

class function TTrueTypeGlyphTests.Tokens(const Text: string): TArray<string>;
begin
  Result := Text.Split([' '], TStringSplitOptions.ExcludeEmpty);
end;

class procedure TTrueTypeGlyphTests.CheckSameTokens(const Expected, Actual, Context: string);
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

// The commands per glyph key of a reference file; a glyph without a path has an empty text
class function TTrueTypeGlyphTests.ReferenceLines(const FontFile: string): TDictionary<string, string>;
begin
  Result := TDictionary<string, string>.Create;
  for var Line in TFile.ReadAllLines(TTestFonts.Path(FontFile + PathsSuffix), TEncoding.UTF8) do
  begin
    const Separator = Line.IndexOf(' ');
    if Separator < 0 then
    begin
      Result.Add(Line, '');
    end
    else
    begin
      Result.Add(Line.Substring(0, Separator), Line.Substring(Separator + 1));
    end;
  end;
end;

class function TTrueTypeGlyphTests.Component(const GlyphIndex, Flags, Argument1, Argument2: Integer; const Scales: array of Integer): TTestComponent;
begin
  Result.GlyphIndex := GlyphIndex;
  Result.Flags := Flags;
  Result.Argument1 := Argument1;
  Result.Argument2 := Argument2;
  Result.Scales := nil;
  for var Scale in Scales do
  begin
    Result.Scales := Result.Scales + [Scale];
  end;
end;

// A glyph of lines and curves without short coordinates. Coordinates are x, y and 1 for on the curve or 0 for off, per point.
class function TTrueTypeGlyphTests.SimpleGlyph(const MinimumX: Integer; const EndPoints, Coordinates: array of Integer): TBytes;
begin
  const PointCount = Length(Coordinates) div 3;
  const Writer = TTestByteWriter.Create;
  try
    Writer.U16(Length(EndPoints));
    Writer.U16(MinimumX);
    Writer.Zeros(6);
    for var EndPoint in EndPoints do
    begin
      Writer.U16(EndPoint);
    end;
    Writer.U16(0);

    for var Index := 0 to PointCount - 1 do
    begin
      Writer.U8(Coordinates[(Index * 3) + 2] * OnCurveFlag);
    end;

    var Previous := 0;
    for var Index := 0 to PointCount - 1 do
    begin
      Writer.U16(Coordinates[Index * 3] - Previous);
      Previous := Coordinates[Index * 3];
    end;
    Previous := 0;
    for var Index := 0 to PointCount - 1 do
    begin
      Writer.U16(Coordinates[(Index * 3) + 1] - Previous);
      Previous := Coordinates[(Index * 3) + 1];
    end;
    Result := Writer.ToBytes;
  finally
    Writer.Free;
  end;
end;

// A simple glyph from bytes: one contour, with the body after the header and the contour count
class function TTrueTypeGlyphTests.RawSimpleGlyph(const MinimumX: Integer; const Body: array of Integer): TBytes;
begin
  const Writer = TTestByteWriter.Create;
  try
    Writer.U16(1);
    Writer.U16(MinimumX);
    Writer.Zeros(6);
    for var Value in Body do
    begin
      Writer.U8(Value);
    end;
    Result := Writer.ToBytes;
  finally
    Writer.Free;
  end;
end;

class function TTrueTypeGlyphTests.CompositeGlyph(const Components: array of TTestComponent): TBytes;
begin
  const Writer = TTestByteWriter.Create;
  try
    Writer.U16($FFFF);
    Writer.Zeros(8);
    for var Index := 0 to High(Components) do
    begin
      var Flags := Components[Index].Flags;
      if Index < High(Components) then
      begin
        Flags := Flags or MoreComponents;
      end;
      Writer.U16(Flags);
      Writer.U16(Components[Index].GlyphIndex);
      Writer.U8(Components[Index].Argument1);
      Writer.U8(Components[Index].Argument2);
      for var Scale in Components[Index].Scales do
      begin
        Writer.U16(Scale);
      end;
    end;
    Result := Writer.ToBytes;
  finally
    Writer.Free;
  end;
end;

class function TTrueTypeGlyphTests.LeftSideBearing(const FontData: TBytes; const GID: Integer): Integer;
begin
  const Parser = TTTFParser.Create;
  try
    const Font = Parser.Parse(FontData);
    try
      Result := Font.HorizontalMetrics.GetLeftSideBearing(GID);
    finally
      Font.Free;
    end;
  finally
    Parser.Free;
  end;
end;

// Liberation Sans with the glyphs of the test as its first glyphs (the first one is glyph 0) and no outlines for the others
class function TTrueTypeGlyphTests.PatchedFont(const Glyphs: array of TBytes; const MaximumDepth: Integer): TBytes;
begin
  Result := TTestFonts.Bytes(LiberationFont);
  const GlyphCount = TTrueTypeTestData.Unsigned16(Result, TTrueTypeTestData.TableOffset(Result, 'maxp') + GlyphCountOffset);
  const IsLongFormat = (TTrueTypeTestData.Unsigned16(Result, TTrueTypeTestData.TableOffset(Result, 'head') + IndexToLocFormatOffset) = 1);

  const GlyfWriter = TTestByteWriter.Create;
  const LocaWriter = TTestByteWriter.Create;
  try
    var Total := 0;
    for var GID := 0 to GlyphCount do
    begin
      if IsLongFormat then
      begin
        LocaWriter.U32(Total);
      end
      else
      begin
        LocaWriter.U16(Total div 2);
      end;

      if GID <= High(Glyphs) then
      begin
        GlyfWriter.Append(Glyphs[GID]);
        Inc(Total, Length(Glyphs[GID]));
        if Odd(Total) then
        begin
          GlyfWriter.U8(0);
          Inc(Total);
        end;
      end;
    end;

    TTrueTypeTestData.ReplaceTable(Result, 'glyf', 'glyf', GlyfWriter.ToBytes);
    TTrueTypeTestData.ReplaceTable(Result, 'loca', 'loca', LocaWriter.ToBytes);
  finally
    LocaWriter.Free;
    GlyfWriter.Free;
  end;
  TTrueTypeTestData.Write16(Result, TTrueTypeTestData.TableOffset(Result, 'maxp') + MaximumDepthOffset, MaximumDepth);
end;

class procedure TTrueTypeGlyphTests.SetLocaEntry(const FontData: TBytes; const GID, Offset: Integer);
begin
  const IsLongFormat = (TTrueTypeTestData.Unsigned16(FontData, TTrueTypeTestData.TableOffset(FontData, 'head') + IndexToLocFormatOffset) = 1);
  const LocaOffset = TTrueTypeTestData.TableOffset(FontData, 'loca');
  if IsLongFormat then
  begin
    TTrueTypeTestData.Write32(FontData, LocaOffset + (GID * 4), UInt32(Offset));
  end
  else
  begin
    TTrueTypeTestData.Write16(FontData, LocaOffset + (GID * 2), Offset div 2);
  end;
end;

// The offset of the glyph in the glyf table
class function TTrueTypeGlyphTests.GlyphOffset(const FontData: TBytes; const GID: Integer): Integer;
begin
  const IsLongFormat = (TTrueTypeTestData.Unsigned16(FontData, TTrueTypeTestData.TableOffset(FontData, 'head') + IndexToLocFormatOffset) = 1);
  const LocaOffset = TTrueTypeTestData.TableOffset(FontData, 'loca');
  if IsLongFormat then
  begin
    Result := Integer(TTrueTypeTestData.Unsigned32(FontData, LocaOffset + (GID * 4)));
  end
  else
  begin
    Result := TTrueTypeTestData.Unsigned16(FontData, LocaOffset + (GID * 2)) * 2;
  end;
end;

class function TTrueTypeGlyphTests.IsComposite(const FontData: TBytes; const GID: Integer): Boolean;
begin
  const IsEmpty = (GlyphOffset(FontData, GID) = GlyphOffset(FontData, GID + 1));
  if IsEmpty then
  begin
    Exit(False);
  end;

  const ContourCount = SmallInt(TTrueTypeTestData.Unsigned16(FontData, TTrueTypeTestData.TableOffset(FontData, 'glyf') + GlyphOffset(FontData, GID)));
  Result := (ContourCount < 0);
end;

function TTrueTypeGlyphTests.Parse(const FontData: TBytes): TTrueTypeFont;
begin
  const Parser = TTTFParser.Create(False, FLog);
  try
    Result := Parser.Parse(FontData);
  finally
    Parser.Free;
  end;
end;

// The path of the glyph as text; 'no path' when the font has none
function TTrueTypeGlyphTests.DescribedGlyph(const FontData: TBytes; const GID: Integer): string;
begin
  const Font = Parse(FontData);
  try
    var Path: TPdfPath;
    if not Font.TryGetGlyphPath(GID, Path, FLog) then
    begin
      Exit('no path');
    end;
    try
      Result := Describe(Path);
    finally
      Path.Free;
    end;
  finally
    Font.Free;
  end;
end;

// A square from (0, 0) to (100, 100) as the glyph; the glyph starts at its left side bearing, so the points are as written
function TTrueTypeGlyphTests.SquareGlyph(const GID: Integer; const FontData: TBytes): TBytes;
begin
  Result := SimpleGlyph(LeftSideBearing(FontData, GID), [3], [0, 0, 1, 100, 0, 1, 100, 100, 1, 0, 100, 1]);
end;

procedure TTrueTypeGlyphTests.CheckReferencePaths(const FontFile: string);
begin
  const Reference = ReferenceLines(FontFile);
  try
    const Font = Parse(TTestFonts.Bytes(FontFile));
    try
      for var Pair in Reference do
      begin
        const GID = StrToInt(Pair.Key.Substring(Length(GlyphKeyPrefix)));
        var Path: TPdfPath;
        Assert.IsTrue(Font.TryGetGlyphPath(GID, Path), Format('%s in %s', [Pair.Key, FontFile]));
        try
          CheckSameTokens(Pair.Value, Describe(Path), Format('%s in %s', [Pair.Key, FontFile]));
        finally
          Path.Free;
        end;
      end;
      Assert.IsTrue(Reference.Count >= 250, 'Glyphs checked in ' + FontFile);
    finally
      Font.Free;
    end;
  finally
    Reference.Free;
  end;
end;

procedure TTrueTypeGlyphTests.TestGlyfPathsMatchPdfBox;
begin
  CheckReferencePaths(LiberationFont);
end;

procedure TTrueTypeGlyphTests.TestGlyfPathsMatchPdfBoxOfSecondFont;
begin
  CheckReferencePaths(SecondFont);
end;

procedure TTrueTypeGlyphTests.TestPathByNameUsesTheGlyphOfTheName;
begin
  const Reference = ReferenceLines(LiberationFont);
  try
    const Font = Parse(TTestFonts.Bytes(LiberationFont));
    try
      const GID = Font.NameToGID('A');
      Assert.IsTrue((GID > 0) and (GID < 300), 'A is among the glyphs of the reference file');

      var Path: TPdfPath;
      Assert.IsTrue(Font.TryGetPath('A', Path));
      try
        CheckSameTokens(Reference[GlyphKeyPrefix + IntToStr(GID)], Describe(Path), 'A');
      finally
        Path.Free;
      end;
    finally
      Font.Free;
    end;
  finally
    Reference.Free;
  end;
end;

procedure TTrueTypeGlyphTests.TestCompositeGlyphUsesComponentTransforms;
begin
  const FontData = TTestFonts.Bytes(LiberationFont);
  const Reference = ReferenceLines(LiberationFont);
  try
    var Checked := 0;
    for var GID := 0 to 299 do
    begin
      const HasReferencePath = (Reference[GlyphKeyPrefix + IntToStr(GID)] <> '');
      if HasReferencePath and IsComposite(FontData, GID) then
      begin
        CheckSameTokens(Reference[GlyphKeyPrefix + IntToStr(GID)], DescribedGlyph(FontData, GID), Format('composite glyph %d', [GID]));
        Inc(Checked);
      end;
    end;
    Assert.IsTrue(Checked >= 10, 'Composite glyphs among the reference glyphs');
  finally
    Reference.Free;
  end;
end;

procedure TTrueTypeGlyphTests.TestCompositeGlyphScaleAndTranslation;
begin
  const Base = TTestFonts.Bytes(LiberationFont);
  const FontData = PatchedFont([nil, SquareGlyph(1, Base),
                                CompositeGlyph([Component(1, ArgumentsAreXYValues or HasScale, 10, 20, [FixedOne div 2])])]);

  Assert.AreEqual('M 10 20 L 60 20 L 60 70 L 10 70 L 10 20 Z', DescribedGlyph(FontData, 2));
end;

procedure TTrueTypeGlyphTests.TestCompositeGlyphTwoByTwoTransformation;
begin
  const Base = TTestFonts.Bytes(LiberationFont);
  // x' = -y and y' = x: a quarter turn
  const FontData = PatchedFont([nil, SquareGlyph(1, Base),
                                CompositeGlyph([Component(1, ArgumentsAreXYValues or HasTwoByTwo, 0, 0, [0, FixedOne, $10000 - FixedOne, 0])])]);

  Assert.AreEqual('M 0 0 L 0 100 L -100 100 L -100 0 L 0 0 Z', DescribedGlyph(FontData, 2));
end;

procedure TTrueTypeGlyphTests.TestCompositeGlyphWithTwoComponentsHasTwoContours;
begin
  const Base = TTestFonts.Bytes(LiberationFont);
  const FontData = PatchedFont([nil, SquareGlyph(1, Base),
                                CompositeGlyph([Component(1, ArgumentsAreXYValues, 0, 0, []),
                                                Component(1, ArgumentsAreXYValues, 120, 0, [])])]);

  Assert.AreEqual('M 0 0 L 100 0 L 100 100 L 0 100 L 0 0 Z M 120 0 L 220 0 L 220 100 L 120 100 L 120 0 Z', DescribedGlyph(FontData, 2));
end;

procedure TTrueTypeGlyphTests.TestCompositeGlyphCycleStops;
begin
  const FontData = PatchedFont([nil, CompositeGlyph([Component(1, ArgumentsAreXYValues, 0, 0, [])])]);

  const Description = DescribedGlyph(FontData, 1);

  Assert.AreEqual('', Description);
  Assert.IsTrue(HasMessage('component of itself'), 'The log names the cycle');
end;

procedure TTrueTypeGlyphTests.TestCompositeGlyphCycleKeepsTheOtherComponents;
begin
  const Base = TTestFonts.Bytes(LiberationFont);
  // glyph 1 holds glyph 2 and glyph 3; glyph 2 holds glyph 1 again
  const FontData = PatchedFont([nil,
                                CompositeGlyph([Component(2, ArgumentsAreXYValues, 0, 0, []), Component(3, ArgumentsAreXYValues, 5, 6, [])]),
                                CompositeGlyph([Component(1, ArgumentsAreXYValues, 0, 0, [])]),
                                SquareGlyph(3, Base)]);

  Assert.AreEqual('M 5 6 L 105 6 L 105 106 L 5 106 L 5 6 Z', DescribedGlyph(FontData, 1));
  Assert.IsTrue(HasMessage('component of itself'), 'The log names the cycle');
end;

procedure TTrueTypeGlyphTests.TestCompositeGlyphBeyondMaximumDepthIsLeftOut;
begin
  const Base = TTestFonts.Bytes(LiberationFont);
  const Glyphs: TArray<TBytes> = [nil,
                  CompositeGlyph([Component(2, ArgumentsAreXYValues, 0, 0, [])]),
                  CompositeGlyph([Component(3, ArgumentsAreXYValues, 0, 0, [])]),
                  SquareGlyph(3, Base)];

  Assert.AreEqual('M 0 0 L 100 0 L 100 100 L 0 100 L 0 0 Z', DescribedGlyph(PatchedFont(Glyphs, 2), 1), 'depth 2 is allowed');

  FMessages.Clear;
  Assert.AreEqual('', DescribedGlyph(PatchedFont(Glyphs, 1), 1), 'depth 1 is not enough');
  Assert.IsTrue(HasMessage('maximum level'), 'The log names the depth');
end;

procedure TTrueTypeGlyphTests.TestCompositeGlyphWithTooManyReadsStops;
begin
  const Base = TTestFonts.Bytes(LiberationFont);
  const LastComposite = 12;
  // every composite glyph holds the next glyph twice, so the number of reads doubles with every level
  var Glyphs: TArray<TBytes> := [nil];
  for var GID := 1 to LastComposite do
  begin
    Glyphs := Glyphs + [CompositeGlyph([Component(GID + 1, ArgumentsAreXYValues, 0, 0, []), Component(GID + 1, ArgumentsAreXYValues, 0, 0, [])])];
  end;
  Glyphs := Glyphs + [SquareGlyph(LastComposite + 1, Base)];
  const FontData = PatchedFont(Glyphs, 16);

  const Description = DescribedGlyph(FontData, 1);

  Assert.AreNotEqual('no path', Description);
  const Squares = Length(Description.Split(['Z'])) - 1;
  Assert.IsTrue((Squares > 0) and (Squares < 1024), Format('%d squares, one for every glyph read', [Squares]));
  Assert.IsTrue(HasMessage('too many other glyphs'), 'The log says the glyph was cut short');
end;

procedure TTrueTypeGlyphTests.TestTruncatedGlyfGivesNoPath;
begin
  const Base = TTestFonts.Bytes(LiberationFont);
  const FontData = PatchedFont([nil, SquareGlyph(1, Base)]);
  const GlyfLength = TTrueTypeTestData.TableLength(FontData, 'glyf');
  SetLocaEntry(FontData, 1, GlyfLength + 100);
  SetLocaEntry(FontData, 2, GlyfLength + 200);

  Assert.AreEqual('no path', DescribedGlyph(FontData, 1));
  Assert.IsTrue(HasMessage('beyond the glyf table'), 'The log says where the glyph is');
end;

procedure TTrueTypeGlyphTests.TestGlyphCutOffInsideItsDataGivesNoPath;
begin
  // The glyph says it has four points and ends after its flags
  const Glyph = RawSimpleGlyph(0, [0, 3, 0, 0, OnCurveFlag, OnCurveFlag]);
  const FontData = PatchedFont([nil, Glyph]);

  Assert.AreEqual('no path', DescribedGlyph(FontData, 1));
  Assert.IsTrue(HasMessage('Glyph 1 cannot be read'), 'The log names the glyph');
end;

procedure TTrueTypeGlyphTests.TestEmptyGlyphIsEmptyPath;
begin
  const Reference = ReferenceLines(LiberationFont);
  try
    Assert.AreEqual('', Reference['gid1'], 'gid1 has no outline in PDFBox');

    const Font = Parse(TTestFonts.Bytes(LiberationFont));
    try
      var Path: TPdfPath;
      Assert.IsTrue(Font.TryGetGlyphPath(1, Path), 'glyph 1');
      try
        Assert.IsTrue(Path.IsEmpty);
        Assert.AreEqual(0, Path.VerbCount);
      finally
        Path.Free;
      end;

      Assert.IsTrue(Font.TryGetPath('space', Path), 'space');
      try
        Assert.IsTrue(Path.IsEmpty);
      finally
        Path.Free;
      end;
    finally
      Font.Free;
    end;
  finally
    Reference.Free;
  end;
end;

procedure TTrueTypeGlyphTests.TestGlyphBeyondTheNumberOfGlyphsIsEmptyPath;
begin
  const Font = Parse(TTestFonts.Bytes(LiberationFont));
  try
    var Path: TPdfPath;
    Assert.IsTrue(Font.TryGetGlyphPath(Font.NumberOfGlyphs, Path));
    try
      Assert.IsTrue(Path.IsEmpty);
    finally
      Path.Free;
    end;
  finally
    Font.Free;
  end;
end;

procedure TTrueTypeGlyphTests.TestContourOfOffCurvePointsStartsInTheMiddle;
begin
  const FontData = PatchedFont([nil, SimpleGlyph(LeftSideBearing(TTestFonts.Bytes(LiberationFont), 1), [2], [0, 0, 0, 100, 0, 0, 50, 100, 0])]);

  Assert.AreEqual('M 25 50 Q 0 0 50 0 Q 100 0 75 50 Q 50 100 25 50 Z', DescribedGlyph(FontData, 1));
end;

procedure TTrueTypeGlyphTests.TestRepeatedFlagsAndShortCoordinates;
begin
  // flags: on the curve, short and positive in x and y, repeated three more times; then the x and y bytes
  const Glyph = RawSimpleGlyph(LeftSideBearing(TTestFonts.Bytes(LiberationFont), 1),
                               [0, 3, 0, 0, $3F, 3, 10, 20, 30, 40, 1, 2, 3, 4]);
  const FontData = PatchedFont([nil, Glyph]);

  Assert.AreEqual('M 10 1 L 30 3 L 60 6 L 100 10 L 10 1 Z', DescribedGlyph(FontData, 1));
end;

procedure TTrueTypeGlyphTests.TestNegativeShortCoordinates;
begin
  // flags: on the curve, short and negative in x and y
  const Glyph = RawSimpleGlyph(LeftSideBearing(TTestFonts.Bytes(LiberationFont), 1),
                               [0, 1, 0, 0, $07, $07, 5, 7, 1, 2]);
  const FontData = PatchedFont([nil, Glyph]);

  Assert.AreEqual('M -5 -1 L -12 -3 L -5 -1 Z', DescribedGlyph(FontData, 1));
end;

procedure TTrueTypeGlyphTests.TestOpenTypeWithCffOutlinesUsesTheCffTable;
begin
  const Reference = ReferenceLines('FoglihtenNo07.otf');
  try
    const Parser = TOTFParser.Create(False, FLog);
    try
      const Font = Parser.Parse(TTestFonts.Bytes('FoglihtenNo07.otf'));
      try
        for var GID in [0, 5, 20, 100] do
        begin
          var Path: TPdfPath;
          Assert.IsTrue(Font.TryGetGlyphPath(GID, Path), Format('glyph %d', [GID]));
          try
            CheckSameTokens(Reference[GlyphKeyPrefix + IntToStr(GID)], Describe(Path), Format('glyph %d', [GID]));
          finally
            Path.Free;
          end;
        end;
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

end.
