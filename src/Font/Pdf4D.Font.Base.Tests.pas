// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
unit Pdf4D.Font.Base.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Common.Defines,
  Pdf4D.Common.Log,
  Pdf4D.Common.Matrix,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Font.Base,
  Pdf4D.FontBox.BoundingBox,
  Pdf4D.Model.DocumentContext;

type
  // A font with one byte codes, a width of 500 in the font program and a space that encodes as code 32
  TTestFont = class(TPDFont)
  public
    function ReadCode(const Data: TBytes; var Position: Integer): Integer; override;
    function GetWidthFromFont(const Code: Integer): Single; override;
    function IsVertical: Boolean; override;
    function GetBoundingBox: TBoundingBox; override;
    function IsEmbedded: Boolean; override;
    function IsDamaged: Boolean; override;
  end;

  // As TTestFont, with the widths of a standard 14 font from a hook of its own
  TStandard14TestFont = class(TTestFont)
  protected
    function GetStandard14Width(const Code: Integer): Single; override;
  end;

  // As TTestFont, with a font matrix of its own and access to the scaling of a width
  TMatrixTestFont = class(TTestFont)
  public
    function GetFontMatrix: TPdfMatrix; override;
    function ScaledWidth(const Width: Single): Single;
  end;

  // As TTestFont, and it can encode, like a simple font does
  TEncodingTestFont = class(TTestFont)
  protected
    function TryEncode(const CodePoint: Integer; out Bytes: TBytes): Boolean; override;
  end;

  [TestFixture]
  TFontBaseTests = class
  private
    FDictionaries: TObjectList<TCosDictionary>;
    FFonts: TObjectList<TPDFont>;
    FMessages: TStringList;
    FContext: TPDDocumentContext;
    FLog: TPdfLog;

    procedure CreateContext(const Options: TPdfLoadOptions);
    function NewFontDictionary(const BaseFont: string): TCosDictionary;
    procedure AddWidths(const Dictionary: TCosDictionary; const FirstChar: Integer; const Widths: array of Integer);
    procedure AddToUnicodeStream(const Dictionary: TCosDictionary; const CMapText: string);
    procedure AddToUnicodeName(const Dictionary: TCosDictionary; const CMapName: string);
    procedure AddEncodingName(const Dictionary: TCosDictionary; const EncodingName: string);
    function NewFont(const Dictionary: TCosDictionary): TTestFont;
    function UnicodeOf(const Font: TPDFont; const Code: Integer): string;
    function CountMessages(const Level: string): Integer;
    function BfCharCMap(const Code: string): string;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestWidthsArray;

    [Test]
    procedure TestMissingWidthFromDescriptor;

    [Test]
    procedure TestWidthWithoutLastCharFallsBackToTheFont;

    [Test]
    procedure TestHasExplicitWidth;

    [Test]
    procedure TestAverageFontWidthCountsOnlyPositiveWidths;

    [Test]
    procedure TestDisplacementIsWidthInThousandths;

    [Test]
    procedure TestHorizontalFontHasNoPositionVector;

    [Test]
    procedure TestToUnicodeCMap;

    [Test]
    procedure TestBrokenToUnicodeIsIgnored;

    [Test]
    procedure TestToUnicodeWithoutMappingsIsReported;

    [Test]
    procedure TestPredefinedIdentityToUnicodeNameMapsCodeToCharacter;

    [Test]
    procedure TestIdentityStreamToUnicodeMapsCodeToCharacter;

    [Test]
    procedure TestUnknownToUnicodeNameIsIgnored;

    [Test]
    procedure TestToUnicodeIsNotAStreamOrName;

    [Test]
    procedure TestToUnicodeOfSimpleFontWithPredefinedEncodingUsesOneByteMappings;

    [Test]
    procedure TestNoToUnicodeGivesNothing;

    [Test]
    procedure TestSpaceWidthFromWidths;

    [Test]
    procedure TestSpaceWidthFromEncodingUsesTheCodeOfTheSpace;

    [Test]
    procedure TestSpaceWidthFromToUnicodeSpaceMapping;

    [Test]
    procedure TestSpaceWidthFallsBackToTheFont;

    [Test]
    procedure TestFontMatrixDefault;

    [Test]
    procedure TestNameAndSubType;

    [Test]
    procedure TestStandard14FontHasAfmAndDescriptor;

    [Test]
    procedure TestSymbolStandard14DescriptorIsSymbolic;

    [Test]
    procedure TestEmbeddedFontIsNotStandard14;

    [Test]
    procedure TestStandard14WidthComesFromTheHook;

    [Test]
    procedure TestEmbeddedStandard14NameDoesNotUseTheHook;

    [Test]
    procedure TestBaseStandard14WidthRaises;

    [Test]
    procedure TestAverageFontWidthOverflowGivesInfinity;

    [Test]
    procedure TestHugeFontMatrixGivesNoWidthAndOneWarning;

    [Test]
    procedure TestNoToUnicodeBudgetAcrossFonts;

    [Test]
    procedure TestToUnicodeBudgetIsPerDocument;

    [Test]
    procedure TestToUnicodeBudgetDoesNotChargePredefinedCMaps;
  end;

implementation

uses
  System.Math,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Float,
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Font.Descriptor,
  Pdf4D.FontBox.Afm;

{ TTestFont }

function TTestFont.ReadCode(const Data: TBytes; var Position: Integer): Integer;
begin
  Result := Data[Position];
  Inc(Position);
end;

function TTestFont.GetWidthFromFont(const Code: Integer): Single;
begin
  Result := 500;
end;

function TTestFont.IsVertical: Boolean;
begin
  Result := False;
end;

function TTestFont.GetBoundingBox: TBoundingBox;
begin
  Result := TBoundingBox.Create(0, 0, 1000, 1000);
end;

function TTestFont.IsEmbedded: Boolean;
begin
  Result := CosObject.ContainsKey('FontFile');
end;

function TTestFont.IsDamaged: Boolean;
begin
  Result := False;
end;

{ TStandard14TestFont }

function TStandard14TestFont.GetStandard14Width(const Code: Integer): Single;
begin
  Result := 278;
end;

{ TMatrixTestFont }

function TMatrixTestFont.GetFontMatrix: TPdfMatrix;
begin
  Result := TPdfMatrix.Create(3E38, 0, 0, 3E38, 0, 0);
end;

function TMatrixTestFont.ScaledWidth(const Width: Single): Single;
begin
  Result := ScaleToTextSpace(Width);
end;

{ TEncodingTestFont }

function TEncodingTestFont.TryEncode(const CodePoint: Integer; out Bytes: TBytes): Boolean;
begin
  Bytes := [Byte(CodePoint + 1)];
  Result := True;
end;

{ TFontBaseTests }

procedure TFontBaseTests.Setup;
begin
  FDictionaries := TObjectList<TCosDictionary>.Create(True);
  FFonts := TObjectList<TPDFont>.Create(True);
  FMessages := TStringList.Create;
  CreateContext(TPdfLoadOptions.Default);
end;

procedure TFontBaseTests.TearDown;
begin
  FreeAndNil(FFonts);
  FreeAndNil(FContext);
  FreeAndNil(FLog);
  FreeAndNil(FDictionaries);
  FreeAndNil(FMessages);
end;

procedure TFontBaseTests.CreateContext(const Options: TPdfLoadOptions);
begin
  FFonts.Clear;
  FreeAndNil(FContext);
  FreeAndNil(FLog);
  // The context does not own the log, so the fixture keeps it for as long as the context lives
  FLog := TPdfLog.Create(
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      FMessages.Add(Format('%d:%s', [Ord(Level), Message]));
    end);
  FContext := TPDDocumentContext.Create(FLog, Options);
end;

function TFontBaseTests.NewFontDictionary(const BaseFont: string): TCosDictionary;
begin
  Result := TCosDictionary.Create;
  FDictionaries.Add(Result);
  Result.SetItem(TCosNames.Type_, TCosName.Create(TCosNames.Font));
  Result.SetItem(TCosNames.Subtype, TCosName.Create('Type1'));
  if BaseFont <> '' then
  begin
    Result.SetItem(TCosNames.BaseFont, TCosName.Create(BaseFont));
  end;
end;

procedure TFontBaseTests.AddWidths(const Dictionary: TCosDictionary; const FirstChar: Integer; const Widths: array of Integer);
begin
  const Values = TCosArray.Create;
  Dictionary.SetItem(TCosNames.Widths, Values);
  for var Width in Widths do
  begin
    Values.Add(TCosInteger.Create(Width));
  end;
  Dictionary.SetItem(TCosNames.FirstChar, TCosInteger.Create(FirstChar));
  Dictionary.SetItem(TCosNames.LastChar, TCosInteger.Create(FirstChar + High(Widths)));
end;

procedure TFontBaseTests.AddToUnicodeStream(const Dictionary: TCosDictionary; const CMapText: string);
begin
  const Stream = TCosStream.Create;
  Dictionary.SetItem(TCosNames.ToUnicode, Stream);
  Stream.SetRawData(TEncoding.ASCII.GetBytes(CMapText));
end;

procedure TFontBaseTests.AddToUnicodeName(const Dictionary: TCosDictionary; const CMapName: string);
begin
  Dictionary.SetItem(TCosNames.ToUnicode, TCosName.Create(CMapName));
end;

procedure TFontBaseTests.AddEncodingName(const Dictionary: TCosDictionary; const EncodingName: string);
begin
  Dictionary.SetItem(TCosNames.Encoding, TCosName.Create(EncodingName));
end;

function TFontBaseTests.NewFont(const Dictionary: TCosDictionary): TTestFont;
begin
  Result := TTestFont.Create(Dictionary, FContext);
  FFonts.Add(Result);
end;

function TFontBaseTests.UnicodeOf(const Font: TPDFont; const Code: Integer): string;
begin
  if not Font.TryToUnicode(Code, Result) then
  begin
    Result := '<none>';
  end;
end;

function TFontBaseTests.CountMessages(const Level: string): Integer;
begin
  Result := 0;
  for var Message in FMessages do
  begin
    if Message.StartsWith(Level + ':') then
    begin
      Inc(Result);
    end;
  end;
end;

function TFontBaseTests.BfCharCMap(const Code: string): string;
begin
  Result := Format('1 begincodespacerange <00> <FF> endcodespacerange 1 beginbfchar <%s> <0041> endbfchar', [Code]);
end;

procedure TFontBaseTests.TestWidthsArray;
begin
  const Dictionary = NewFontDictionary('Test');
  AddWidths(Dictionary, 65, [600, 700]);
  const Font = NewFont(Dictionary);

  Assert.AreEqual(Single(600), Font.GetWidth(65));
  Assert.AreEqual(Single(700), Font.GetWidth(66));
  Assert.AreEqual(Single(500), Font.GetWidth(67), 'outside the widths the font decides');
  Assert.AreEqual(Single(500), Font.GetWidth(64));
end;

procedure TFontBaseTests.TestMissingWidthFromDescriptor;
begin
  const Dictionary = NewFontDictionary('Test');
  AddWidths(Dictionary, 65, [600, 700]);
  const Descriptor = TCosDictionary.Create;
  Dictionary.SetItem(TCosNames.FontDescriptor, Descriptor);
  Descriptor.SetItem(TCosNames.MissingWidth, TCosInteger.Create(250));
  const Font = NewFont(Dictionary);

  Assert.AreEqual(Single(700), Font.GetWidth(66));
  Assert.AreEqual(Single(250), Font.GetWidth(67));
end;

procedure TFontBaseTests.TestWidthWithoutLastCharFallsBackToTheFont;
begin
  const Dictionary = NewFontDictionary('Test');
  AddWidths(Dictionary, 65, [600, 700]);
  Dictionary.RemoveItem(TCosNames.LastChar);
  const Font = NewFont(Dictionary);

  // PDFBox needs /LastChar for a width from /Widths
  Assert.AreEqual(Single(500), Font.GetWidth(65));
end;

procedure TFontBaseTests.TestHasExplicitWidth;
begin
  const Dictionary = NewFontDictionary('Test');
  AddWidths(Dictionary, 65, [600, 700]);
  const Font = NewFont(Dictionary);
  const NoWidths = NewFont(NewFontDictionary('Test'));

  Assert.IsTrue(Font.HasExplicitWidth(65));
  Assert.IsTrue(Font.HasExplicitWidth(66));
  Assert.IsFalse(Font.HasExplicitWidth(67));
  Assert.IsFalse(Font.HasExplicitWidth(64));
  Assert.IsFalse(NoWidths.HasExplicitWidth(65));
end;

procedure TFontBaseTests.TestAverageFontWidthCountsOnlyPositiveWidths;
begin
  const Dictionary = NewFontDictionary('Test');
  AddWidths(Dictionary, 0, [600, 0, 700, -50]);
  const Font = NewFont(Dictionary);

  Assert.AreEqual(Single(650), Font.GetAverageFontWidth);
  Assert.AreEqual(Single(0), NewFont(NewFontDictionary('Test')).GetAverageFontWidth);
end;

procedure TFontBaseTests.TestDisplacementIsWidthInThousandths;
begin
  const Dictionary = NewFontDictionary('Test');
  AddWidths(Dictionary, 65, [600]);
  const Font = NewFont(Dictionary);

  const Displacement = Font.GetDisplacement(65);

  Assert.AreEqual(Single(0.6), Displacement.X, 0.00001);
  Assert.AreEqual(Single(0), Displacement.Y);
end;

procedure TFontBaseTests.TestHorizontalFontHasNoPositionVector;
begin
  const Font = NewFont(NewFontDictionary('Test'));

  Assert.WillRaise(
    procedure
    begin
      Font.GetPositionVector(65);
    end,
    EPdfUnsupportedFeatureException);
end;

procedure TFontBaseTests.TestToUnicodeCMap;
begin
  const Dictionary = NewFontDictionary('Test');
  AddToUnicodeStream(Dictionary, '1 begincodespacerange <00> <FF> endcodespacerange ' +
                                 '2 beginbfchar <01> <0041> <02> <FB01> endbfchar');
  const Font = NewFont(Dictionary);

  Assert.AreEqual('A', UnicodeOf(Font, 1));
  Assert.AreEqual(#$FB01, UnicodeOf(Font, 2));
  Assert.AreEqual('<none>', UnicodeOf(Font, 3));
  Assert.AreEqual(0, FMessages.Count);
end;

procedure TFontBaseTests.TestBrokenToUnicodeIsIgnored;
begin
  const Dictionary = NewFontDictionary('Test');
  AddToUnicodeStream(Dictionary, 'this is not a CMap )))) <<<< 12 begincodespacerange <zz> endbfchar');
  var Font: TTestFont;

  Assert.WillNotRaise(
    procedure
    begin
      Font := NewFont(Dictionary);
    end);

  Assert.AreEqual('<none>', UnicodeOf(Font, 65));
  Assert.IsTrue(CountMessages(IntToStr(Ord(TPdfLogLevel.Warning))) + CountMessages(IntToStr(Ord(TPdfLogLevel.Error))) > 0,
                'the problem is logged');
end;

procedure TFontBaseTests.TestToUnicodeWithoutMappingsIsReported;
begin
  const Dictionary = NewFontDictionary('Test');
  AddToUnicodeStream(Dictionary, '1 begincodespacerange <00> <FF> endcodespacerange');
  const Font = NewFont(Dictionary);

  Assert.AreEqual('<none>', UnicodeOf(Font, 65));
  Assert.AreEqual(1, CountMessages(IntToStr(Ord(TPdfLogLevel.Warning))));
end;

procedure TFontBaseTests.TestPredefinedIdentityToUnicodeNameMapsCodeToCharacter;
begin
  const Dictionary = NewFontDictionary('Test');
  AddToUnicodeName(Dictionary, 'Identity-H');
  const Font = NewFont(Dictionary);

  Assert.AreEqual('A', UnicodeOf(Font, 65));
  Assert.AreEqual(#$20AC, UnicodeOf(Font, $20AC));
end;

procedure TFontBaseTests.TestIdentityStreamToUnicodeMapsCodeToCharacter;
begin
  const Dictionary = NewFontDictionary('Test');
  AddToUnicodeStream(Dictionary, '/CIDInit /ProcSet findresource begin 12 dict begin begincmap ' +
                                 '/CMapName /Identity-H def 1 begincodespacerange <0000> <FFFF> endcodespacerange endcmap');
  AddEncodingName(Dictionary, 'Identity-H');
  const Font = NewFont(Dictionary);

  // The stream has no Unicode mappings and the font is identity encoded: the predefined identity CMap takes over
  Assert.AreEqual('B', UnicodeOf(Font, 66));
end;

procedure TFontBaseTests.TestUnknownToUnicodeNameIsIgnored;
begin
  const Dictionary = NewFontDictionary('Test');
  AddToUnicodeName(Dictionary, 'No-Such-CMap');
  const Font = NewFont(Dictionary);

  Assert.AreEqual('<none>', UnicodeOf(Font, 65));
  Assert.AreEqual(1, CountMessages(IntToStr(Ord(TPdfLogLevel.Error))));
end;

procedure TFontBaseTests.TestToUnicodeIsNotAStreamOrName;
begin
  const Dictionary = NewFontDictionary('Test');
  Dictionary.SetItem(TCosNames.ToUnicode, TCosInteger.Create(5));
  const Font = NewFont(Dictionary);

  Assert.AreEqual('<none>', UnicodeOf(Font, 65));
  Assert.AreEqual(1, CountMessages(IntToStr(Ord(TPdfLogLevel.Error))));
end;

procedure TFontBaseTests.TestToUnicodeOfSimpleFontWithPredefinedEncodingUsesOneByteMappings;
begin
  const Dictionary = NewFontDictionary('Test');
  const CMapText = '2 begincodespacerange <00> <FF> <0000> <FFFF> endcodespacerange 1 beginbfchar <0041> <0059> endbfchar';
  AddToUnicodeStream(Dictionary, CMapText);
  AddEncodingName(Dictionary, 'WinAnsiEncoding');
  const WithEncoding = NewFont(Dictionary);
  const PlainDictionary = NewFontDictionary('Test');
  AddToUnicodeStream(PlainDictionary, CMapText);
  const WithoutEncoding = NewFont(PlainDictionary);

  Assert.AreEqual('<none>', UnicodeOf(WithEncoding, $41), 'only one byte mappings count with a predefined encoding');
  Assert.AreEqual('Y', UnicodeOf(WithoutEncoding, $41));
end;

procedure TFontBaseTests.TestNoToUnicodeGivesNothing;
begin
  const Font = NewFont(NewFontDictionary('Test'));

  Assert.AreEqual('<none>', UnicodeOf(Font, 65));
  Assert.AreEqual(0, FMessages.Count);
end;

procedure TFontBaseTests.TestSpaceWidthFromWidths;
begin
  const Dictionary = NewFontDictionary('Test');
  AddWidths(Dictionary, 32, [250]);
  const Font = NewFont(Dictionary);

  Assert.AreEqual(Single(250), Font.GetSpaceWidth);
end;

procedure TFontBaseTests.TestSpaceWidthFromEncodingUsesTheCodeOfTheSpace;
begin
  const Dictionary = NewFontDictionary('Test');
  AddWidths(Dictionary, 33, [333]);
  const Font = TEncodingTestFont.Create(Dictionary, FContext);
  FFonts.Add(Font);

  // The font encodes the space as code 33
  Assert.AreEqual(Single(333), Font.GetSpaceWidth);
end;

procedure TFontBaseTests.TestSpaceWidthFromToUnicodeSpaceMapping;
begin
  const Dictionary = NewFontDictionary('Test');
  AddWidths(Dictionary, 3, [333]);
  AddToUnicodeStream(Dictionary, '1 begincodespacerange <00> <FF> endcodespacerange 1 beginbfchar <03> <0020> endbfchar');
  const Font = NewFont(Dictionary);

  Assert.AreEqual(Single(333), Font.GetSpaceWidth);
end;

procedure TFontBaseTests.TestSpaceWidthFallsBackToTheFont;
begin
  const Dictionary = NewFontDictionary('Test');
  AddWidths(Dictionary, 40, [100]);
  const Font = NewFont(Dictionary);

  // No width for code 32 in /Widths: the width from the font program is used
  Assert.AreEqual(Single(500), Font.GetSpaceWidth);
end;

procedure TFontBaseTests.TestFontMatrixDefault;
begin
  const Font = NewFont(NewFontDictionary('Test'));

  const Matrix = Font.GetFontMatrix;

  Assert.AreEqual(Single(0.001), Matrix.ScaleX);
  Assert.AreEqual(Single(0.001), Matrix.ScaleY);
  Assert.AreEqual(Single(0), Matrix.ShearX);
  Assert.AreEqual(Single(0), Matrix.TranslateX);
end;

procedure TFontBaseTests.TestNameAndSubType;
begin
  const Font = NewFont(NewFontDictionary('ABCDEF+Test'));
  const Unnamed = NewFont(NewFontDictionary(''));

  Assert.AreEqual('ABCDEF+Test', Font.Name);
  Assert.AreEqual('Type1', Font.SubType);
  Assert.AreEqual('', Unnamed.Name);
  Assert.AreSame(FContext, Font.Context);
end;

procedure TFontBaseTests.TestStandard14FontHasAfmAndDescriptor;
begin
  const Font = NewFont(NewFontDictionary('Helvetica'));

  var Metrics: TFontMetrics;
  var Descriptor: TPDFontDescriptor;
  Assert.IsTrue(Font.IsStandard14);
  Assert.IsTrue(Font.TryGetStandardAFM(Metrics));
  Assert.AreEqual('Helvetica', Metrics.FontName);
  Assert.IsTrue(Font.TryGetFontDescriptor(Descriptor));
  Assert.AreEqual('Helvetica', Descriptor.FontName);
  Assert.IsTrue(Descriptor.IsNonSymbolic);
  Assert.IsFalse(Descriptor.IsSymbolic);
  Assert.AreEqual(Metrics.Ascender, Descriptor.Ascent);
  Assert.AreEqual(Metrics.CapHeight, Descriptor.CapHeight);
end;

procedure TFontBaseTests.TestSymbolStandard14DescriptorIsSymbolic;
begin
  const Font = NewFont(NewFontDictionary('Symbol'));

  var Descriptor: TPDFontDescriptor;
  Assert.IsTrue(Font.TryGetFontDescriptor(Descriptor));
  Assert.IsTrue(Descriptor.IsSymbolic);
  Assert.IsFalse(Descriptor.IsNonSymbolic);
end;

procedure TFontBaseTests.TestEmbeddedFontIsNotStandard14;
begin
  const Dictionary = NewFontDictionary('Helvetica');
  Dictionary.SetItem('FontFile', TCosDictionary.Create);
  const Font = NewFont(Dictionary);

  var Metrics: TFontMetrics;
  Assert.IsFalse(Font.IsStandard14);
  Assert.IsTrue(Font.TryGetStandardAFM(Metrics), 'the AFM is looked up by name, as in PDFBox');
  Assert.AreEqual(Single(500), Font.GetWidth(65));
end;

procedure TFontBaseTests.TestStandard14WidthComesFromTheHook;
begin
  const Font = TStandard14TestFont.Create(NewFontDictionary('Helvetica'), FContext);
  FFonts.Add(Font);

  Assert.IsTrue(Font.IsStandard14);
  Assert.AreEqual(Single(278), Font.GetWidth(65));
end;

procedure TFontBaseTests.TestEmbeddedStandard14NameDoesNotUseTheHook;
begin
  const Dictionary = NewFontDictionary('Helvetica');
  Dictionary.SetItem('FontFile', TCosDictionary.Create);
  const Font = TStandard14TestFont.Create(Dictionary, FContext);
  FFonts.Add(Font);

  Assert.IsFalse(Font.IsStandard14);
  Assert.AreEqual(Single(500), Font.GetWidth(65), 'an embedded font goes to the font program');
end;

procedure TFontBaseTests.TestBaseStandard14WidthRaises;
begin
  const Font = NewFont(NewFontDictionary('Helvetica'));

  Assert.WillRaise(
    procedure
    begin
      Font.GetWidth(65);
    end, EPdfUnsupportedFeatureException);
end;

procedure TFontBaseTests.TestAverageFontWidthOverflowGivesInfinity;
begin
  const Dictionary = NewFontDictionary('Test');
  const Values = TCosArray.Create;
  Dictionary.SetItem(TCosNames.Widths, Values);
  Values.Add(TCosFloat.Create(3E38));
  Values.Add(TCosFloat.Create(3E38));
  const Font = NewFont(Dictionary);

  // With overflow unmasked the sum raises, with it masked it is an infinity: both give Java's result
  const Previous = SetExceptionMask([exDenormalized, exUnderflow, exPrecision]);
  try
    Assert.IsTrue(IsInfinite(Font.GetAverageFontWidth));
  finally
    SetExceptionMask(Previous);
  end;
end;

procedure TFontBaseTests.TestHugeFontMatrixGivesNoWidthAndOneWarning;
begin
  const Font = TMatrixTestFont.Create(NewFontDictionary('Test'), FContext);
  FFonts.Add(Font);

  Assert.AreEqual(Single(0), Font.ScaledWidth(1000));
  Assert.AreEqual(Single(0), Font.ScaledWidth(1000));
  Assert.AreEqual(1, CountMessages(IntToStr(Ord(TPdfLogLevel.Warning))));
end;

procedure TFontBaseTests.TestNoToUnicodeBudgetAcrossFonts;
begin
  const First = NewFontDictionary('One');
  const Second = NewFontDictionary('Two');
  const Third = NewFontDictionary('Three');
  AddToUnicodeStream(First, BfCharCMap('01'));
  AddToUnicodeStream(Second, BfCharCMap('01'));
  AddToUnicodeStream(Third, BfCharCMap('01'));

  Assert.AreEqual('A', UnicodeOf(NewFont(First), 1));
  Assert.AreEqual('A', UnicodeOf(NewFont(Second), 1));
  Assert.AreEqual('A', UnicodeOf(NewFont(Third), 1));
  Assert.AreEqual(0, FMessages.Count);
end;

procedure TFontBaseTests.TestToUnicodeBudgetIsPerDocument;
begin
  var Options := TPdfLoadOptions.Default;
  Options.MaxToUnicodeMappings := 3;
  CreateContext(Options);
  const First = NewFontDictionary('One');
  const Second = NewFontDictionary('Two');
  const Third = NewFontDictionary('Three');
  AddToUnicodeStream(First, '1 begincodespacerange <00> <FF> endcodespacerange 2 beginbfchar <01> <0041> <02> <0042> endbfchar');
  AddToUnicodeStream(Second, '1 begincodespacerange <00> <FF> endcodespacerange 2 beginbfchar <01> <0043> <02> <0044> endbfchar');
  AddToUnicodeStream(Third, '1 begincodespacerange <00> <FF> endcodespacerange 1 beginbfchar <01> <0045> endbfchar');

  const FirstFont = NewFont(First);
  const SecondFont = NewFont(Second);
  const ThirdFont = NewFont(Third);

  Assert.AreEqual('B', UnicodeOf(FirstFont, 2), 'two mappings fit in the budget of three');
  Assert.AreEqual('<none>', UnicodeOf(SecondFont, 1), 'the second CMap takes the total over the budget');
  Assert.AreEqual('<none>', UnicodeOf(ThirdFont, 1), 'once the budget is gone no ToUnicode CMap is read');
  Assert.AreEqual(1, CountMessages(IntToStr(Ord(TPdfLogLevel.Warning))), 'the budget is exceeded once and logged once');
  Assert.IsTrue(FContext.IsToUnicodeBudgetExhausted);
end;

procedure TFontBaseTests.TestToUnicodeBudgetDoesNotChargePredefinedCMaps;
begin
  var Options := TPdfLoadOptions.Default;
  Options.MaxToUnicodeMappings := 1;
  CreateContext(Options);
  for var Index := 1 to 5 do
  begin
    const Dictionary = NewFontDictionary('Font');
    AddToUnicodeName(Dictionary, 'Identity-H');
    UnicodeOf(NewFont(Dictionary), 65);
  end;

  // The warnings are the ones of PDFBox for an identity CMap without Unicode mappings, none of them is about the budget
  Assert.IsFalse(FContext.IsToUnicodeBudgetExhausted);
  for var Message in FMessages do
  begin
    Assert.IsFalse(Message.Contains('exceed'), Message);
  end;
end;

end.
