// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Font.MapperImpl.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Font.Descriptor,
  Pdf4D.Font.Mapper;

type
  [TestFixture]
  TFontMapperTests = class
  private
    class var FSharedMappers: array[0..1] of IPdfFontMapper;

    class destructor Destroy;
    class function SharedMapper(const Index: Integer): IPdfFontMapper; static;

  private
    FOriginal: IPdfFontMapper;
    FDictionary: TCosDictionary;

    function NewMapper(const FontFiles: TArray<string>): IPdfFontMapper;
    function LastResortFont: Pointer;
    function DescriptorWith(const Flags: Integer; const FontName: string): TPDFontDescriptor;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestUnknownFontFallsBackToLiberationSans;

    [Test]
    procedure TestSubstituteFoundInProvider;

    [Test]
    procedure TestFontBoxFontPrefersType1ForStandard14;

    [Test]
    procedure TestCidFallbackIsLiberationSans;

    [Test]
    procedure TestLastResortFontIsSharedByMappers;

    [Test]
    [TestCase('SubsetTag', 'ABCDEF+LiberationSans')]
    [TestCase('OtherCase', 'liberationsans')]
    [TestCase('WindowsStyleName', 'LiberationSans,Bold')]
    procedure TestNameVariantsFindTheFont(const BaseFont: string);

    [Test]
    [TestCase('RegularSuffix', 'OpenSans')]
    [TestCase('WithoutHyphen', 'OpenSansRegular')]
    [TestCase('Exact', 'OpenSans-Regular')]
    procedure TestType1NameVariantsFindTheFont(const BaseFont: string);

    [Test]
    procedure TestOtherFormatIsNotFound;

    [Test]
    procedure TestStyleFlagsChooseTheFallback;

    [Test]
    procedure TestAddedSubstituteIsUsed;

    [Test]
    procedure TestOpenTypeCidFontIsFoundByName;

    [Test]
    procedure TestCharacterCollectionPicksFontWithCodePage;

    [Test]
    procedure TestCharacterCollectionWithoutCodePageFallsBack;

    [Test]
    procedure TestCharacterCollectionNeedsDescriptor;

    [Test]
    procedure TestFontWithRosMatchesItsCollection;

    [Test]
    procedure TestBestMatchByWeightClass;

    [Test]
    procedure TestBestMatchByPanose;

    [Test]
    procedure TestBarcodeFontIsLeftOut;

    [Test]
    procedure TestFontInfoDerivedValues;

    [Test]
    procedure TestBrokenFontFileCountsAsNotFound;

    [Test]
    procedure TestSetInstanceReplacesMapper;

    [Test]
    procedure TestSetInstanceNilGivesDefaultMapper;

    [Test]
    procedure TestMapperInstanceIsSharedByConcurrentReaders;

    [Test]
    procedure TestConcurrentFirstLookupOnFreshMapper;

    [Test]
    procedure TestSetInstanceRacingWithInstance;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.PdfString,
  Pdf4D.FontBox.FontBoxFont,
  Pdf4D.FontBox.OpenType,
  Pdf4D.FontBox.TrueType.Font,
  Pdf4D.FontBox.TrueType.Parser,
  Pdf4D.FontBox.Type1.Font,
  Pdf4D.Font.MapperImpl,
  Pdf4D.Font.Provider,
  Pdf4D.Tests.FontProvider,
  Pdf4D.Tests.TestFonts;

const
  LiberationSansFile = 'LiberationSans-Regular.ttf';
  OpenSansFile = 'OpenSans-Regular.pfb';
  SourceSansFile = 'SourceSansProBold.otf';
  JapaneseCodePage = 1 shl 17;
  KoreanCodePage = 1 shl 19;
  ChineseSimplifiedCodePage = 1 shl 18;
  ThreadCount = 8;
  RaceIterations = 3000;

type
  // A font that the tests describe by hand. The font is a copy of LiberationSans that the info owns.
  TFakeFontInfo = class(TFontInfo)
  private
    FPostScriptName: string;
    FFont: TTrueTypeFont;
    FHasCIDSystemInfo: Boolean;
    FCIDSystemInfo: TPDCIDSystemInfo;
    FWeightClass: Integer;
    FCodePageRange1: Integer;
    FPanose: TBytes;
    FIsBroken: Boolean;
    FFormat: TFontFormat;

  public
    constructor Create(const PostScriptName: string; const FontFormat: TFontFormat = TFontFormat.TTF);
    destructor Destroy; override;

    function WithCodePage(const CodePage: Integer): TFakeFontInfo;
    function WithWeightClass(const WeightClass: Integer): TFakeFontInfo;
    function WithRos(const Registry, Ordering: string): TFakeFontInfo;
    function WithPanose(const Panose: TBytes): TFakeFontInfo;
    function Broken: TFakeFontInfo;

    function PostScriptName: string; override;
    function Format: TFontFormat; override;
    function TryGetCIDSystemInfo(out Info: TPDCIDSystemInfo): Boolean; override;
    function GetFont: TFontBoxFont; override;
    function FamilyClass: Integer; override;
    function WeightClass: Integer; override;
    function CodePageRange1: Integer; override;
    function CodePageRange2: Integer; override;
    function MacStyle: Integer; override;
    function TryGetPanose(out Panose: TPDPanoseClassification): Boolean; override;
  end;

  TFakeFontProvider = class(TInterfacedObject, IPdfFontProvider)
  private
    FInfos: TObjectList<TFontInfo>;

  public
    constructor Create(const Infos: array of TFakeFontInfo);
    destructor Destroy; override;

    function FontInfos: TArray<TFontInfo>;
    function ToDebugString: string;
  end;

  // Waits for the gate, then does the first lookup on a mapper that nobody has used yet: the lazy font index is built in the race
  TFirstLookupThread = class(TThread)
  private
    FGate: TEvent;
    FMapper: IPdfFontMapper;
    FFont: Pointer;
    FFailure: string;

  protected
    procedure Execute; override;

  public
    constructor Create(const Gate: TEvent; const Mapper: IPdfFontMapper);

    property Font: Pointer read FFont;
    property Failure: string read FFailure;
  end;

  // Waits for the gate, then asks for the process-wide mapper over and over
  TInstanceReader = class(TThread)
  private
    FGate: TEvent;
    FIterations: Integer;
    FFirst: Pointer;
    FAllSame: Boolean;
    FIsDefaultRace: Boolean;
    FFailure: string;

  protected
    procedure Execute; override;

  public
    constructor Create(const Gate: TEvent; const Iterations: Integer; const IsDefaultRace: Boolean);

    property First: Pointer read FFirst;
    property AllSame: Boolean read FAllSame;
    property Failure: string read FFailure;
  end;

  TInstanceWriter = class(TThread)
  private
    FGate: TEvent;
    FMapperA: IPdfFontMapper;
    FMapperB: IPdfFontMapper;

  protected
    procedure Execute; override;

  public
    constructor Create(const Gate: TEvent; const MapperA, MapperB: IPdfFontMapper);
  end;

{ TFakeFontInfo }

constructor TFakeFontInfo.Create(const PostScriptName: string; const FontFormat: TFontFormat);
begin
  inherited Create;
  FPostScriptName := PostScriptName;
  FFormat := FontFormat;
  FWeightClass := -1;
  const Parser = TTTFParser.Create;
  try
    FFont := Parser.Parse(TTestFonts.Bytes(LiberationSansFile));
  finally
    Parser.Free;
  end;
end;

destructor TFakeFontInfo.Destroy;
begin
  FFont.Free;
  inherited;
end;

function TFakeFontInfo.WithCodePage(const CodePage: Integer): TFakeFontInfo;
begin
  FCodePageRange1 := CodePage;
  Result := Self;
end;

function TFakeFontInfo.WithWeightClass(const WeightClass: Integer): TFakeFontInfo;
begin
  FWeightClass := WeightClass;
  Result := Self;
end;

function TFakeFontInfo.WithRos(const Registry, Ordering: string): TFakeFontInfo;
begin
  FHasCIDSystemInfo := True;
  FCIDSystemInfo := TPDCIDSystemInfo.Create(Registry, Ordering, 0);
  Result := Self;
end;

function TFakeFontInfo.WithPanose(const Panose: TBytes): TFakeFontInfo;
begin
  FPanose := Panose;
  Result := Self;
end;

function TFakeFontInfo.Broken: TFakeFontInfo;
begin
  FIsBroken := True;
  Result := Self;
end;

function TFakeFontInfo.PostScriptName: string;
begin
  Result := FPostScriptName;
end;

function TFakeFontInfo.Format: TFontFormat;
begin
  Result := FFormat;
end;

function TFakeFontInfo.TryGetCIDSystemInfo(out Info: TPDCIDSystemInfo): Boolean;
begin
  Info := FCIDSystemInfo;
  Result := FHasCIDSystemInfo;
end;

function TFakeFontInfo.GetFont: TFontBoxFont;
begin
  if FIsBroken then
  begin
    raise EPdfParseException.Create('The font file is damaged');
  end;
  Result := FFont;
end;

function TFakeFontInfo.FamilyClass: Integer;
begin
  Result := -1;
end;

function TFakeFontInfo.WeightClass: Integer;
begin
  Result := FWeightClass;
end;

function TFakeFontInfo.CodePageRange1: Integer;
begin
  Result := FCodePageRange1;
end;

function TFakeFontInfo.CodePageRange2: Integer;
begin
  Result := 0;
end;

function TFakeFontInfo.MacStyle: Integer;
begin
  Result := 0;
end;

function TFakeFontInfo.TryGetPanose(out Panose: TPDPanoseClassification): Boolean;
begin
  Panose.Bytes := Copy(FPanose);
  Result := (Length(FPanose) = TPDPanoseClassification.Length);
end;

{ TFakeFontProvider }

constructor TFakeFontProvider.Create(const Infos: array of TFakeFontInfo);
begin
  inherited Create;
  FInfos := TObjectList<TFontInfo>.Create(True);
  for var Info in Infos do
  begin
    FInfos.Add(Info);
  end;
end;

destructor TFakeFontProvider.Destroy;
begin
  FInfos.Free;
  inherited;
end;

function TFakeFontProvider.FontInfos: TArray<TFontInfo>;
begin
  Result := FInfos.ToArray;
end;

function TFakeFontProvider.ToDebugString: string;
begin
  Result := '';
end;

{ TFirstLookupThread }

constructor TFirstLookupThread.Create(const Gate: TEvent; const Mapper: IPdfFontMapper);
begin
  inherited Create(True);
  FGate := Gate;
  FMapper := Mapper;
end;

procedure TFirstLookupThread.Execute;
begin
  try
    FGate.WaitFor(INFINITE);
    const Mapping = FMapper.GetTrueTypeFont('Arial', nil);
    FFont := Pointer(Mapping.Font);
    if (not Assigned(Mapping.Font)) or Mapping.IsFallback or (Mapping.Font.Name <> 'LiberationSans') then
    begin
      FFailure := 'The mapper gave an unexpected font';
    end;
  except
    on E: Exception do
    begin
      FFailure := E.ClassName + ': ' + E.Message;
    end;
  end;
end;

{ TInstanceReader }

constructor TInstanceReader.Create(const Gate: TEvent; const Iterations: Integer; const IsDefaultRace: Boolean);
begin
  inherited Create(True);
  FGate := Gate;
  FIterations := Iterations;
  FIsDefaultRace := IsDefaultRace;
  FAllSame := True;
end;

procedure TInstanceReader.Execute;
begin
  try
    FGate.WaitFor(INFINITE);
    for var Round := 1 to FIterations do
    begin
      const Mapper = TPdfFontMappers.Instance;
      if FIsDefaultRace then
      begin
        if not Assigned(FFirst) then
        begin
          FFirst := Pointer(Mapper);
        end;
        FAllSame := (FAllSame and (FFirst = Pointer(Mapper)));
      end
      else
      begin
        const Mapping = Mapper.GetTrueTypeFont('Foo', nil);
        if (not Assigned(Mapping.Font)) or (Mapping.Font.Name <> 'LiberationSans') or not Mapping.IsFallback then
        begin
          FFailure := 'The mapper gave an unexpected font';
          Exit;
        end;
      end;
    end;
  except
    on E: Exception do
    begin
      FFailure := E.ClassName + ': ' + E.Message;
    end;
  end;
end;

{ TInstanceWriter }

constructor TInstanceWriter.Create(const Gate: TEvent; const MapperA, MapperB: IPdfFontMapper);
begin
  inherited Create(True);
  FGate := Gate;
  FMapperA := MapperA;
  FMapperB := MapperB;
end;

procedure TInstanceWriter.Execute;
begin
  FGate.WaitFor(INFINITE);
  for var Round := 1 to RaceIterations do
  begin
    TPdfFontMappers.SetInstance(FMapperA);
    TPdfFontMappers.SetInstance(FMapperB);
    TPdfFontMappers.SetInstance(nil);
  end;
end;

{ TFontMapperTests }

class destructor TFontMapperTests.Destroy;
begin
  FSharedMappers[0] := nil;
  FSharedMappers[1] := nil;
end;

// The mappers that the tests put in the process-wide slot are made once: a replaced mapper stays alive until the process
// ends, so a new one per run would look like a leak
class function TFontMapperTests.SharedMapper(const Index: Integer): IPdfFontMapper;
begin
  if not Assigned(FSharedMappers[Index]) then
  begin
    FSharedMappers[Index] := TFontMapperImpl.Create(TTestFontProvider.Empty);
  end;
  Result := FSharedMappers[Index];
end;

procedure TFontMapperTests.Setup;
begin
  FOriginal := TPdfFontMappers.Instance;
  FDictionary := TCosDictionary.Create;
end;

procedure TFontMapperTests.TearDown;
begin
  TPdfFontMappers.SetInstance(FOriginal);
  FOriginal := nil;
  FDictionary.Free;
end;

function TFontMapperTests.NewMapper(const FontFiles: TArray<string>): IPdfFontMapper;
begin
  Result := TFontMapperImpl.Create(TTestFontProvider.Create(FontFiles));
end;

function TFontMapperTests.LastResortFont: Pointer;
begin
  const Mapping = NewMapper(nil).GetTrueTypeFont('Foo', nil);
  Result := Pointer(Mapping.Font);
end;

function TFontMapperTests.DescriptorWith(const Flags: Integer; const FontName: string): TPDFontDescriptor;
begin
  FDictionary.SetItem(TCosNames.Flags, TCosInteger.Create(Flags));
  FDictionary.SetItem(TCosNames.FontName, TCosName.Create(FontName));
  Result := TPDFontDescriptor.Create(FDictionary);
end;

procedure TFontMapperTests.TestUnknownFontFallsBackToLiberationSans;
begin
  const Mapper = NewMapper(nil);

  const Mapping = Mapper.GetTrueTypeFont('Foo', nil);

  Assert.IsTrue(Mapping.IsFallback);
  Assert.AreEqual('LiberationSans', Mapping.Font.Name);
end;

procedure TFontMapperTests.TestSubstituteFoundInProvider;
begin
  const Mapper = NewMapper([LiberationSansFile]);

  const Mapping = Mapper.GetTrueTypeFont('Arial', nil);

  Assert.IsFalse(Mapping.IsFallback);
  Assert.AreEqual('LiberationSans', Mapping.Font.Name);
  Assert.IsTrue(Pointer(Mapping.Font) <> LastResortFont, 'The font should come from the provider');
end;

procedure TFontMapperTests.TestFontBoxFontPrefersType1ForStandard14;
begin
  const Mapper = NewMapper([OpenSansFile, LiberationSansFile]);

  const Mapping = Mapper.GetFontBoxFont('OpenSans-Regular', nil);

  Assert.IsFalse(Mapping.IsFallback);
  Assert.IsTrue(Mapping.Font is TType1Font);
  Assert.AreEqual('OpenSans-Regular', Mapping.Font.Name);
end;

procedure TFontMapperTests.TestCidFallbackIsLiberationSans;
begin
  const Mapper = NewMapper(nil);
  const Japan1 = TPDCIDSystemInfo.Create('Adobe', 'Japan1', 6);

  const Mapping = Mapper.GetCIDFont('MSMincho', nil, True, Japan1);

  Assert.IsTrue(Mapping.IsFallback);
  Assert.IsFalse(Mapping.IsCIDFont);
  Assert.AreEqual('LiberationSans', Mapping.TrueTypeFont.Name);
end;

procedure TFontMapperTests.TestLastResortFontIsSharedByMappers;
begin
  const First = NewMapper(nil).GetTrueTypeFont('Foo', nil);
  const Second = NewMapper(nil).GetFontBoxFont('Bar', nil);

  Assert.IsTrue(Pointer(First.Font) = Pointer(Second.Font));
end;

procedure TFontMapperTests.TestNameVariantsFindTheFont(const BaseFont: string);
begin
  const Mapper = NewMapper([LiberationSansFile]);

  const Mapping = Mapper.GetTrueTypeFont(BaseFont, nil);

  Assert.IsFalse(Mapping.IsFallback);
  Assert.AreEqual('LiberationSans', Mapping.Font.Name);
end;

procedure TFontMapperTests.TestType1NameVariantsFindTheFont(const BaseFont: string);
begin
  const Mapper = NewMapper([OpenSansFile]);

  const Mapping = Mapper.GetFontBoxFont(BaseFont, nil);

  Assert.IsFalse(Mapping.IsFallback);
  Assert.AreEqual('OpenSans-Regular', Mapping.Font.Name);
end;

procedure TFontMapperTests.TestOtherFormatIsNotFound;
begin
  const Mapper = NewMapper([OpenSansFile]);

  const Mapping = Mapper.GetTrueTypeFont('OpenSans-Regular', nil);

  Assert.IsTrue(Mapping.IsFallback);
  Assert.AreEqual('LiberationSans', Mapping.Font.Name);
end;

procedure TFontMapperTests.TestStyleFlagsChooseTheFallback;
begin
  const Provider = TFakeFontProvider.Create([TFakeFontInfo.Create('MyCourier'), TFakeFontInfo.Create('MyTimesBoldItalic'),
                                             TFakeFontInfo.Create('MyHelveticaBold')]);
  const Mapper = TFontMapperImpl.Create(Provider);
  Mapper.AddSubstitute('Courier', 'MyCourier');
  Mapper.AddSubstitute('Times-BoldItalic', 'MyTimesBoldItalic');
  Mapper.AddSubstitute('Helvetica-Bold', 'MyHelveticaBold');
  const MapperInterface: IPdfFontMapper = Mapper;
  const LastResort = LastResortFont;
  const Descriptor = DescriptorWith(1, 'Unknown');
  try
    const FixedPitch = MapperInterface.GetTrueTypeFont('Foo', Descriptor);
    Assert.IsTrue(FixedPitch.IsFallback);
    Assert.IsTrue(Pointer(FixedPitch.Font) <> LastResort, 'Fixed pitch: Courier');

    FDictionary.SetItem(TCosNames.Flags, TCosInteger.Create(2 + 64));
    FDictionary.SetItem(TCosNames.FontName, TCosName.Create('Foo-Heavy'));
    Assert.IsTrue(Pointer(MapperInterface.GetTrueTypeFont('Foo', Descriptor).Font) <> LastResort, 'Serif, heavy and italic: Times-BoldItalic');

    FDictionary.SetItem(TCosNames.Flags, TCosInteger.Create(0));
    FDictionary.SetItem(TCosNames.FontName, TCosName.Create('Foo-Black'));
    Assert.IsTrue(Pointer(MapperInterface.GetTrueTypeFont('Foo', Descriptor).Font) <> LastResort, 'Black: Helvetica-Bold');

    FDictionary.SetItem(TCosNames.FontName, TCosName.Create('Foo-Light'));
    Assert.IsTrue(Pointer(MapperInterface.GetTrueTypeFont('Foo', Descriptor).Font) = LastResort, 'Helvetica has no substitute here');

    Assert.IsTrue(Pointer(MapperInterface.GetTrueTypeFont('Foo', nil).Font) = LastResort, 'Without a descriptor: Times-Roman');
  finally
    Descriptor.Free;
  end;
end;

procedure TFontMapperTests.TestAddedSubstituteIsUsed;
begin
  const Provider = TFakeFontProvider.Create([TFakeFontInfo.Create('CompanyFont')]);
  const Mapper = TFontMapperImpl.Create(Provider);
  const IMapper: IPdfFontMapper = Mapper;

  Assert.IsTrue(IMapper.GetTrueTypeFont('Calibri', nil).IsFallback);

  Mapper.AddSubstitute('calibri', 'CompanyFont');

  const Mapping = IMapper.GetTrueTypeFont('Calibri', nil);
  Assert.IsFalse(Mapping.IsFallback);
  Assert.AreEqual('LiberationSans', Mapping.Font.Name);
end;

procedure TFontMapperTests.TestOpenTypeCidFontIsFoundByName;
begin
  const Reader = TTestFontProvider.Create([SourceSansFile]);
  const PostScriptName = Reader.FontInfos[0].PostScriptName;
  const Mapper: IPdfFontMapper = TFontMapperImpl.Create(Reader);
  const Japan1 = TPDCIDSystemInfo.Create('Adobe', 'Japan1', 6);

  const Mapping = Mapper.GetCIDFont(PostScriptName, nil, True, Japan1);

  Assert.IsFalse(Mapping.IsFallback);
  Assert.IsTrue(Mapping.IsCIDFont);
  Assert.IsTrue(Mapping.Font is TOpenTypeFont);
  Assert.IsFalse(Assigned(Mapping.TrueTypeFont));
end;

procedure TFontMapperTests.TestCharacterCollectionPicksFontWithCodePage;
begin
  const Japanese = TFakeFontInfo.Create('JapaneseFont').WithCodePage(JapaneseCodePage);
  const Provider = TFakeFontProvider.Create([TFakeFontInfo.Create('Latin'), Japanese, TFakeFontInfo.Create('Korean').WithCodePage(KoreanCodePage)]);
  const Mapper: IPdfFontMapper = TFontMapperImpl.Create(Provider);
  const Descriptor = DescriptorWith(0, 'MSMincho');
  try
    const Mapping = Mapper.GetCIDFont('MSMincho', Descriptor, True, TPDCIDSystemInfo.Create('Adobe', 'Japan1', 6));

    Assert.IsTrue(Mapping.IsFallback);
    Assert.IsTrue(Pointer(Mapping.TrueTypeFont) = Pointer(Japanese.GetFont));
  finally
    Descriptor.Free;
  end;
end;

procedure TFontMapperTests.TestCharacterCollectionWithoutCodePageFallsBack;
begin
  const Provider = TFakeFontProvider.Create([TFakeFontInfo.Create('Korean').WithCodePage(KoreanCodePage),
                                             TFakeFontInfo.Create('Chinese').WithCodePage(ChineseSimplifiedCodePage)]);
  const Mapper: IPdfFontMapper = TFontMapperImpl.Create(Provider);
  const Descriptor = DescriptorWith(0, 'MSMincho');
  try
    const Mapping = Mapper.GetCIDFont('MSMincho', Descriptor, True, TPDCIDSystemInfo.Create('Adobe', 'Japan1', 6));

    Assert.IsTrue(Mapping.IsFallback);
    Assert.IsTrue(Pointer(Mapping.TrueTypeFont) = LastResortFont);
  finally
    Descriptor.Free;
  end;
end;

procedure TFontMapperTests.TestCharacterCollectionNeedsDescriptor;
begin
  const Provider = TFakeFontProvider.Create([TFakeFontInfo.Create('JapaneseFont').WithCodePage(JapaneseCodePage)]);
  const Mapper: IPdfFontMapper = TFontMapperImpl.Create(Provider);
  const Japan1 = TPDCIDSystemInfo.Create('Adobe', 'Japan1', 6);

  Assert.IsTrue(Pointer(Mapper.GetCIDFont('MSMincho', nil, True, Japan1).TrueTypeFont) = LastResortFont);

  const Descriptor = DescriptorWith(0, 'MSMincho');
  try
    const WithoutInfo = Mapper.GetCIDFont('MSMincho', Descriptor, False, Japan1);
    Assert.IsTrue(Pointer(WithoutInfo.TrueTypeFont) = LastResortFont);

    const Identity = Mapper.GetCIDFont('MSMincho', Descriptor, True, TPDCIDSystemInfo.Create('Adobe', 'Identity', 0));
    Assert.IsTrue(Pointer(Identity.TrueTypeFont) = LastResortFont);
  finally
    Descriptor.Free;
  end;
end;

procedure TFontMapperTests.TestFontWithRosMatchesItsCollection;
begin
  const Match = TFakeFontInfo.Create('GB1Font').WithRos('Adobe', 'GB1');
  const Provider = TFakeFontProvider.Create([TFakeFontInfo.Create('CNS1Font').WithRos('Adobe', 'CNS1'), Match,
                                             TFakeFontInfo.Create('NoRosButCodePage').WithCodePage(JapaneseCodePage)]);
  const Mapper: IPdfFontMapper = TFontMapperImpl.Create(Provider);
  const Descriptor = DescriptorWith(0, 'SimSun');
  try
    const Mapping = Mapper.GetCIDFont('SimSun', Descriptor, True, TPDCIDSystemInfo.Create('Adobe', 'GB1', 5));

    Assert.IsTrue(Pointer(Mapping.TrueTypeFont) = Pointer(Match.GetFont));
  finally
    Descriptor.Free;
  end;
end;

procedure TFontMapperTests.TestBestMatchByWeightClass;
begin
  const Light = TFakeFontInfo.Create('Light').WithCodePage(JapaneseCodePage).WithWeightClass(300);
  const Bold = TFakeFontInfo.Create('Bold').WithCodePage(JapaneseCodePage).WithWeightClass(700);
  const Normal = TFakeFontInfo.Create('Normal').WithCodePage(JapaneseCodePage).WithWeightClass(400);
  const Provider = TFakeFontProvider.Create([Light, Normal, Bold]);
  const Mapper: IPdfFontMapper = TFontMapperImpl.Create(Provider);
  const Descriptor = DescriptorWith(0, 'MSMincho');
  FDictionary.SetItem(TCosNames.FontWeight, TCosInteger.Create(700));
  try
    const Mapping = Mapper.GetCIDFont('MSMincho', Descriptor, True, TPDCIDSystemInfo.Create('Adobe', 'Japan1', 6));

    Assert.IsTrue(Pointer(Mapping.TrueTypeFont) = Pointer(Bold.GetFont));
  finally
    Descriptor.Free;
  end;
end;

procedure TFontMapperTests.TestBestMatchByPanose;
begin
  const SansBytes: TBytes = [2, 11, 5, 2, 2, 2, 2, 2, 2, 4];
  const SerifBytes: TBytes = [2, 2, 5, 2, 2, 2, 2, 2, 2, 4];
  const Sans = TFakeFontInfo.Create('Sans').WithCodePage(JapaneseCodePage).WithPanose(SansBytes).WithWeightClass(400);
  const Serif = TFakeFontInfo.Create('Serif').WithCodePage(JapaneseCodePage).WithPanose(SerifBytes).WithWeightClass(400);
  const Provider = TFakeFontProvider.Create([Sans, Serif]);
  const Mapper: IPdfFontMapper = TFontMapperImpl.Create(Provider);

  const Wanted: TBytes = [0, 0, 2, 2, 5, 2, 2, 2, 2, 2, 2, 4];
  const Style = TCosDictionary.Create;
  Style.SetItem(TCosNames.Panose, TCosString.Create(Wanted, False));
  FDictionary.SetItem(TCosNames.Style, Style);
  const Descriptor = DescriptorWith(0, 'MSMincho');
  try
    const Mapping = Mapper.GetCIDFont('MSMincho', Descriptor, True, TPDCIDSystemInfo.Create('Adobe', 'Japan1', 6));

    Assert.IsTrue(Pointer(Mapping.TrueTypeFont) = Pointer(Serif.GetFont), 'The exact serif style wins');
  finally
    Descriptor.Free;
  end;
end;

procedure TFontMapperTests.TestBarcodeFontIsLeftOut;
begin
  const BarcodeBytes: TBytes = [0, 0, 5, 2, 2, 2, 2, 2, 2, 4];
  const Barcode = TFakeFontInfo.Create('Code39Barcode').WithCodePage(JapaneseCodePage).WithPanose(BarcodeBytes);
  const Provider = TFakeFontProvider.Create([Barcode]);
  const Mapper: IPdfFontMapper = TFontMapperImpl.Create(Provider);

  const Wanted: TBytes = [0, 0, 0, 0, 5, 2, 2, 2, 2, 2, 2, 4];
  const Style = TCosDictionary.Create;
  Style.SetItem(TCosNames.Panose, TCosString.Create(Wanted, False));
  FDictionary.SetItem(TCosNames.Style, Style);
  const Descriptor = DescriptorWith(0, 'MSMincho');
  try
    const Mapping = Mapper.GetCIDFont('MSMincho', Descriptor, True, TPDCIDSystemInfo.Create('Adobe', 'Japan1', 6));

    Assert.IsTrue(Pointer(Mapping.TrueTypeFont) = LastResortFont);
  finally
    Descriptor.Free;
  end;
end;

procedure TFontMapperTests.TestFontInfoDerivedValues;
begin
  const Info = TFakeFontInfo.Create('Test').WithWeightClass(700);
  const OddWeight = TFakeFontInfo.Create('Odd').WithWeightClass(450);
  const NoWeight = TFakeFontInfo.Create('None');
  try
    Assert.AreEqual(8, Info.WeightClassAsPanose);
    Assert.AreEqual(0, OddWeight.WeightClassAsPanose);
    Assert.AreEqual(0, NoWeight.WeightClassAsPanose);
    Assert.AreEqual('Test (TTF, mac: 0x0, os/2: 0xffffffff, cid: null)', Info.ToString);
  finally
    NoWeight.Free;
    OddWeight.Free;
    Info.Free;
  end;
end;

procedure TFontMapperTests.TestBrokenFontFileCountsAsNotFound;
begin
  const Provider = TFakeFontProvider.Create([TFakeFontInfo.Create('Arial').Broken]);
  const Mapper: IPdfFontMapper = TFontMapperImpl.Create(Provider);

  const Mapping = Mapper.GetTrueTypeFont('Arial', nil);

  Assert.IsTrue(Mapping.IsFallback);
  Assert.IsTrue(Pointer(Mapping.Font) = LastResortFont);
end;

procedure TFontMapperTests.TestSetInstanceReplacesMapper;
begin
  const Stub = SharedMapper(0);

  TPdfFontMappers.SetInstance(Stub);
  Assert.IsTrue(Pointer(TPdfFontMappers.Instance) = Pointer(Stub));

  TPdfFontMappers.SetInstance(FOriginal);
  Assert.IsTrue(Pointer(TPdfFontMappers.Instance) = Pointer(FOriginal));
end;

procedure TFontMapperTests.TestSetInstanceNilGivesDefaultMapper;
begin
  TPdfFontMappers.SetInstance(nil);

  const Default = TPdfFontMappers.Instance;

  Assert.IsTrue(Assigned(Default));
  Assert.IsTrue(Pointer(Default) <> Pointer(FOriginal));
  Assert.IsTrue(Pointer(Default) = Pointer(TPdfFontMappers.Instance));
  Assert.AreEqual('LiberationSans', Default.GetTrueTypeFont('Foo', nil).Font.Name);
end;

procedure TFontMapperTests.TestMapperInstanceIsSharedByConcurrentReaders;
begin
  TPdfFontMappers.SetInstance(nil);
  const Gate = TEvent.Create(nil, True, False, '');
  var Readers: array[0..ThreadCount - 1] of TInstanceReader;
  try
    for var Index := 0 to ThreadCount - 1 do
    begin
      Readers[Index] := TInstanceReader.Create(Gate, 1000, True);
      Readers[Index].Start;
    end;

    Gate.SetEvent;
    for var Reader in Readers do
    begin
      Reader.WaitFor;
    end;

    for var Reader in Readers do
    begin
      Assert.AreEqual('', Reader.Failure);
      Assert.IsTrue(Reader.AllSame, 'A thread saw another mapper');
      Assert.IsTrue(Reader.First = Readers[0].First, 'The threads share one mapper');
    end;
  finally
    for var Reader in Readers do
    begin
      Reader.Free;
    end;
    Gate.Free;
  end;
end;

procedure TFontMapperTests.TestConcurrentFirstLookupOnFreshMapper;
begin
  const Mapper = NewMapper([LiberationSansFile]);
  const Gate = TEvent.Create(nil, True, False, '');
  var Threads: array[0..ThreadCount - 1] of TFirstLookupThread;
  try
    for var Index := 0 to ThreadCount - 1 do
    begin
      Threads[Index] := TFirstLookupThread.Create(Gate, Mapper);
      Threads[Index].Start;
    end;

    Gate.SetEvent;
    for var Thread in Threads do
    begin
      Thread.WaitFor;
    end;

    for var Thread in Threads do
    begin
      Assert.AreEqual('', Thread.Failure);
      Assert.IsTrue(Thread.Font = Threads[0].Font, 'The threads got different fonts');
    end;
  finally
    for var Thread in Threads do
    begin
      Thread.Free;
    end;
    Gate.Free;
  end;
end;

procedure TFontMapperTests.TestSetInstanceRacingWithInstance;
begin
  const MapperA = SharedMapper(0);
  const MapperB = SharedMapper(1);
  // What a mapper makes on first use is made before the threads start: which mapper a reader meets first is a matter of
  // timing, and the leak check of the test program needs the same allocations in every run
  MapperA.GetTrueTypeFont('Foo', nil);
  MapperB.GetTrueTypeFont('Foo', nil);
  TPdfFontMappers.SetInstance(nil);
  TPdfFontMappers.Instance.GetTrueTypeFont('Foo', nil);
  const Gate = TEvent.Create(nil, True, False, '');
  var Readers: array[0..ThreadCount - 1] of TInstanceReader;
  const Writer = TInstanceWriter.Create(Gate, MapperA, MapperB);
  try
    for var Index := 0 to ThreadCount - 1 do
    begin
      Readers[Index] := TInstanceReader.Create(Gate, RaceIterations, False);
      Readers[Index].Start;
    end;
    Writer.Start;

    Gate.SetEvent;
    Writer.WaitFor;
    for var Reader in Readers do
    begin
      Reader.WaitFor;
    end;

    for var Reader in Readers do
    begin
      Assert.AreEqual('', Reader.Failure);
    end;
  finally
    for var Reader in Readers do
    begin
      Reader.Free;
    end;
    Writer.Free;
    Gate.Free;
  end;
end;

end.
