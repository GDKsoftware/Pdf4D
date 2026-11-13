// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/font/FileSystemFontProvider.java (3.0.8)
unit Pdf4D.Font.FileSystemProvider.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Classes,
  DUnitX.TestFramework,
  Pdf4D.Common.Log,
  Pdf4D.Font.Provider;

type
  // The tests only look at folders that they make themselves, never at the fonts of the machine
  [TestFixture]
  TFileSystemFontProviderTests = class
  private
    const LiberationSans = 'LiberationSans-Regular.ttf';
    const JosefinSans = 'JosefinSans-Italic.ttf';
    const OpenSans = 'OpenSans-Regular.pfb';
    const SourceSans = 'SourceSansProBold.otf';
    const CollectionName = 'two.ttc';
    const LiberationSansTrueType = 'TTF:LiberationSans';
    const OpenSansType1 = 'PFB:OpenSans-Regular';
    const SourceSansOpenType = 'OTF:SourceSansPro-Bold';
    const TimeLimitMilliseconds = 2000;
    // The fonts that get loaded live at the same paths in every run, so that the process-wide font cache gets the same entries again
    const FontFolderName = 'Pdf4D-fs-provider-fonts';
    const WorkFolderName = 'Pdf4D-fs-provider-work';

  private
    class function JunkBytes: TBytes; static;
    class function Describe(const Info: TFontInfo): string; static;
    class function DescribeAll(const Infos: TArray<TFontInfo>): string; static;
    class function FindInfo(const Provider: IPdfFontProvider; const Description: string): TFontInfo; static;
    class function CollectionBytes: TBytes; static;
    class function FileNames(const Paths: TArray<string>): string; static;
    class function ContainsPath(const Paths: TArray<string>; const Expected: string): Boolean; static;

  private
    FFontFolder: string;
    FWorkFolder: string;
    FLogLines: TStringList;
    FLog: TPdfLog;
    FInfo: TFontInfo;

    function NewProvider(const Directories: TArray<string>): IPdfFontProvider;
    function LogText: string;
    procedure CopyTestFont(const FileName, Folder: string);
    procedure CopyTestFontAs(const FileName, Target: string);
    function NestedFolder(const Depth: Integer): string;
    procedure GetFontOfFieldInfo;
    {$IFDEF POSIX}
    procedure CreateSymbolicLink(const Target, LinkPath: string);
    {$ENDIF}

  public
    [SetupFixture]
    procedure SetupFixture;

    [TearDownFixture]
    procedure TearDownFixture;

    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestScanFindsFonts;

    [Test]
    procedure TestScanReadsTheHeaderFields;

    [Test]
    procedure TestJunkFontFileIsSkipped;

    [Test]
    procedure TestGetFontIsShared;

    [Test]
    procedure TestGetFontIsSharedBetweenProviders;

    [Test]
    procedure TestCollectionFontsAreLoadedByIndex;

    [Test]
    procedure TestFontDirectoriesForPlatform;

    [Test]
    procedure TestDirectoryListsOfEachPlatform;

    [Test]
    procedure TestDirectoryDepthIsBounded;

    [Test]
    procedure TestDirectoryAtTheDepthLimitIsScanned;

    [Test]
    procedure TestMissingDirectoryIsIgnored;

    [Test]
    procedure TestOnlyFontExtensionsAreFound;

    [Test]
    procedure TestScanHappensOnFirstUseAndOnce;

    [Test]
    procedure TestTrueTypeFontWithCffOutlinesIsSkipped;

    [Test]
    procedure TestFontThatDisappearedRaisesParseException;

    [Test]
    procedure TestTableHeadersMatchTheFullParse;

    [Test]
    procedure TestCollectionHeadersAreReadPerFont;

    {$IFDEF POSIX}
    [Test]
    procedure TestSymbolicLinkLoopTerminates;
    {$ENDIF}
  end;

implementation

uses
  System.IOUtils,
  System.TypInfo,
  System.Diagnostics,
  System.Generics.Collections,
  System.Generics.Defaults,
  {$IFDEF POSIX}
  Posix.Unistd,
  {$ENDIF}
  Pdf4D.Common.Defines,
  Pdf4D.IO.RandomAccessRead,
  Pdf4D.FontBox.FontBoxFont,
  Pdf4D.FontBox.OpenType,
  Pdf4D.FontBox.TrueType.Collection,
  Pdf4D.FontBox.TrueType.Font,
  Pdf4D.FontBox.TrueType.Headers,
  Pdf4D.FontBox.TrueType.Parser,
  Pdf4D.FontBox.TrueType.Tables,
  Pdf4D.FontBox.Type1.Font,
  Pdf4D.Font.Descriptor,
  Pdf4D.Font.DirFinder,
  Pdf4D.Font.FileSystemProvider,
  Pdf4D.Tests.TestFonts,
  Pdf4D.Tests.TrueTypeBuilder;

{ TFileSystemFontProviderTests }

class function TFileSystemFontProviderTests.JunkBytes: TBytes;
begin
  const SavedSeed = RandSeed;
  RandSeed := 11;
  SetLength(Result, 4096);
  for var Index := 0 to Length(Result) - 1 do
  begin
    Result[Index] := Byte(Random(256));
  end;
  RandSeed := SavedSeed;
end;

class function TFileSystemFontProviderTests.CollectionBytes: TBytes;
begin
  Result := TTrueTypeTestData.BuildCollection([TTestFonts.Bytes(LiberationSans), TTestFonts.Bytes(LiberationSans)]);
end;

class function TFileSystemFontProviderTests.Describe(const Info: TFontInfo): string;
begin
  Result := Format('%s:%s', [GetEnumName(TypeInfo(TFontFormat), Ord(Info.Format)), Info.PostScriptName]);
end;

class function TFileSystemFontProviderTests.DescribeAll(const Infos: TArray<TFontInfo>): string;
begin
  const Lines = TList<string>.Create;
  try
    for var Info in Infos do
    begin
      Lines.Add(Describe(Info));
    end;
    Lines.Sort(TStringComparer.Ordinal);
    Result := string.Join(', ', Lines.ToArray);
  finally
    Lines.Free;
  end;
end;

class function TFileSystemFontProviderTests.FindInfo(const Provider: IPdfFontProvider; const Description: string): TFontInfo;
begin
  for var Info in Provider.FontInfos do
  begin
    if Describe(Info) = Description then
    begin
      Exit(Info);
    end;
  end;
  raise EArgumentException.CreateFmt('The provider has no font %s', [Description]);
end;

class function TFileSystemFontProviderTests.FileNames(const Paths: TArray<string>): string;
begin
  const Names = TList<string>.Create;
  try
    for var Path in Paths do
    begin
      Names.Add(TPath.GetFileName(Path));
    end;
    Result := string.Join(', ', Names.ToArray);
  finally
    Names.Free;
  end;
end;

class function TFileSystemFontProviderTests.ContainsPath(const Paths: TArray<string>; const Expected: string): Boolean;
begin
  for var Path in Paths do
  begin
    if SameText(Path, Expected) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TFileSystemFontProviderTests.SetupFixture;
begin
  FFontFolder := TPath.Combine(TPath.GetTempPath, FontFolderName);
  if TDirectory.Exists(FFontFolder) then
  begin
    TDirectory.Delete(FFontFolder, True);
  end;
  TDirectory.CreateDirectory(FFontFolder);

  CopyTestFont(LiberationSans, FFontFolder);
  CopyTestFont(OpenSans, FFontFolder);
  TFile.WriteAllBytes(TPath.Combine(FFontFolder, CollectionName), CollectionBytes);
  TFile.WriteAllBytes(TPath.Combine(FFontFolder, 'junk.ttf'), JunkBytes);
  TFile.WriteAllBytes(TPath.Combine(FFontFolder, 'junk.ttc'), JunkBytes);
  TFile.WriteAllBytes(TPath.Combine(FFontFolder, 'junk.pfb'), JunkBytes);

  const SubFolder = TPath.Combine(FFontFolder, 'sub');
  TDirectory.CreateDirectory(SubFolder);
  CopyTestFont(SourceSans, SubFolder);
end;

procedure TFileSystemFontProviderTests.TearDownFixture;
begin
  if TDirectory.Exists(FFontFolder) then
  begin
    TDirectory.Delete(FFontFolder, True);
  end;
end;

procedure TFileSystemFontProviderTests.Setup;
begin
  FWorkFolder := TPath.Combine(TPath.GetTempPath, WorkFolderName);
  if TDirectory.Exists(FWorkFolder) then
  begin
    TDirectory.Delete(FWorkFolder, True);
  end;
  TDirectory.CreateDirectory(FWorkFolder);

  FLogLines := TStringList.Create;
  FLog := TPdfLog.Create(
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      FLogLines.Add(Message);
    end);
  FInfo := nil;
end;

procedure TFileSystemFontProviderTests.TearDown;
begin
  FLog.Free;
  FLogLines.Free;
  if TDirectory.Exists(FWorkFolder) then
  begin
    TDirectory.Delete(FWorkFolder, True);
  end;
end;

function TFileSystemFontProviderTests.NewProvider(const Directories: TArray<string>): IPdfFontProvider;
begin
  Result := TFileSystemFontProvider.Create(Directories, FLog);
end;

function TFileSystemFontProviderTests.LogText: string;
begin
  Result := FLogLines.Text;
end;

procedure TFileSystemFontProviderTests.CopyTestFont(const FileName, Folder: string);
begin
  CopyTestFontAs(FileName, TPath.Combine(Folder, FileName));
end;

procedure TFileSystemFontProviderTests.CopyTestFontAs(const FileName, Target: string);
begin
  TFile.WriteAllBytes(Target, TTestFonts.Bytes(FileName));
end;

// The folder that is Depth levels below the work folder, with all the folders in between
function TFileSystemFontProviderTests.NestedFolder(const Depth: Integer): string;
begin
  Result := FWorkFolder;
  for var Level := 1 to Depth do
  begin
    Result := TPath.Combine(Result, 'd');
  end;
  TDirectory.CreateDirectory(Result);
end;

procedure TFileSystemFontProviderTests.GetFontOfFieldInfo;
begin
  FInfo.GetFont;
end;

{$IFDEF POSIX}
procedure TFileSystemFontProviderTests.CreateSymbolicLink(const Target, LinkPath: string);
begin
  const TargetBytes = UTF8String(Target);
  const LinkBytes = UTF8String(LinkPath);
  Assert.AreEqual(0, symlink(PAnsiChar(TargetBytes), PAnsiChar(LinkBytes)));
end;
{$ENDIF}

procedure TFileSystemFontProviderTests.TestScanFindsFonts;
begin
  const Provider = NewProvider([FFontFolder]);

  const Actual = DescribeAll(Provider.FontInfos);

  const Expected = Format('%s, %s, %s, %s, %s', [SourceSansOpenType, OpenSansType1, LiberationSansTrueType, LiberationSansTrueType,
                                                  LiberationSansTrueType]);
  Assert.AreEqual(Expected, Actual);
end;

procedure TFileSystemFontProviderTests.TestScanReadsTheHeaderFields;
begin
  const Provider = NewProvider([FFontFolder]);
  const Parser = TTTFParser.Create;
  try
    const Reference = Parser.Parse(TTestFonts.Bytes(LiberationSans));
    try
      var OS2: TOS2WindowsMetricsTable;
      Assert.IsTrue(Reference.TryGetOS2Windows(OS2));

      const TrueTypeInfo = FindInfo(Provider, LiberationSansTrueType);
      Assert.AreEqual(Integer(OS2.WeightClass), TrueTypeInfo.WeightClass);
      Assert.AreEqual(Integer(OS2.FamilyClass), TrueTypeInfo.FamilyClass);
      Assert.AreEqual(Reference.Header.MacStyle, TrueTypeInfo.MacStyle);
      Assert.AreEqual(Integer(Cardinal(OS2.CodePageRange1 and $FFFFFFFF)), TrueTypeInfo.CodePageRange1);
      Assert.AreEqual(Integer(Cardinal(OS2.CodePageRange2 and $FFFFFFFF)), TrueTypeInfo.CodePageRange2);
      var Panose: TPDPanoseClassification;
      Assert.IsTrue(TrueTypeInfo.TryGetPanose(Panose));
      Assert.AreEqual<NativeInt>(Length(OS2.Panose), Length(Panose.Bytes));
      Assert.AreEqual(OS2.Panose[2], Panose.Bytes[2]);
    finally
      Reference.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TFileSystemFontProviderTests.TestJunkFontFileIsSkipped;
begin
  const Provider = NewProvider([FFontFolder]);

  const Actual = DescribeAll(Provider.FontInfos);

  Assert.AreEqual<NativeInt>(5, Length(Provider.FontInfos));
  Assert.IsFalse(Actual.Contains('junk'));
  Assert.IsTrue(LogText.Contains('junk.ttf'), 'The log has no line about junk.ttf: ' + LogText);
  Assert.IsTrue(LogText.Contains('junk.ttc'), 'The log has no line about junk.ttc: ' + LogText);
  Assert.IsTrue(LogText.Contains('junk.pfb'), 'The log has no line about junk.pfb: ' + LogText);
end;

procedure TFileSystemFontProviderTests.TestGetFontIsShared;
begin
  const Provider = NewProvider([FFontFolder]);

  const TrueTypeInfo = FindInfo(Provider, LiberationSansTrueType);
  const First = TrueTypeInfo.GetFont;
  const Second = TrueTypeInfo.GetFont;

  Assert.AreSame(First, Second);
  Assert.IsTrue(First is TTrueTypeFont);
  Assert.AreEqual('LiberationSans', First.Name);
  Assert.IsTrue(FindInfo(Provider, OpenSansType1).GetFont is TType1Font);
  Assert.IsTrue(FindInfo(Provider, SourceSansOpenType).GetFont is TOpenTypeFont);
end;

procedure TFileSystemFontProviderTests.TestGetFontIsSharedBetweenProviders;
begin
  const FirstProvider = NewProvider([FFontFolder]);
  const SecondProvider = NewProvider([FFontFolder]);

  const First = FindInfo(FirstProvider, OpenSansType1).GetFont;
  const Second = FindInfo(SecondProvider, OpenSansType1).GetFont;

  Assert.AreSame(First, Second);
end;

procedure TFileSystemFontProviderTests.TestCollectionFontsAreLoadedByIndex;
begin
  TFile.WriteAllBytes(TPath.Combine(FWorkFolder, CollectionName), CollectionBytes);
  const Provider = NewProvider([FWorkFolder]);

  const Infos = Provider.FontInfos;
  Assert.AreEqual<NativeInt>(2, Length(Infos));
  const First = Infos[0].GetFont;
  const Second = Infos[1].GetFont;

  Assert.AreNotSame(First, Second);
  Assert.AreEqual('LiberationSans', First.Name);
  Assert.AreEqual('LiberationSans', Second.Name);
  Assert.AreSame(First, Infos[0].GetFont);
end;

procedure TFileSystemFontProviderTests.TestFontDirectoriesForPlatform;
begin
  const Directories = TFontDirFinder.SearchableDirectories;

  {$IF DEFINED(MSWINDOWS)}
  Assert.IsTrue(ContainsPath(Directories, TPath.Combine(GetEnvironmentVariable('WINDIR'), 'Fonts')));
  {$ELSEIF DEFINED(MACOS)}
  Assert.IsTrue(ContainsPath(Directories, '/Library/Fonts'));
  {$ELSE}
  Assert.IsTrue(ContainsPath(Directories, '/usr/share/fonts'));
  {$ENDIF}
end;

procedure TFileSystemFontProviderTests.TestDirectoryListsOfEachPlatform;
begin
  const UnixExpected = '/home/kees/.fonts, /home/kees/.local/share/fonts, /usr/local/fonts, /usr/local/share/fonts, /usr/share/fonts, ' +
                       '/usr/X11R6/lib/X11/fonts, /usr/share/X11/fonts';
  Assert.AreEqual(UnixExpected, string.Join(', ', TFontDirFinder.UnixDirectories('/home/kees/')));

  const MacExpected = '/home/kees/Library/Fonts, /Library/Fonts, /System/Library/Fonts, /Network/Library/Fonts';
  Assert.AreEqual(MacExpected, string.Join(', ', TFontDirFinder.MacDirectories('/home/kees')));

  const NoHomeExpected = '/Library/Fonts, /System/Library/Fonts, /Network/Library/Fonts';
  Assert.AreEqual(NoHomeExpected, string.Join(', ', TFontDirFinder.MacDirectories('')));

  Assert.AreEqual<NativeInt>(0, Length(TFontDirFinder.WindowsDirectories('', '')));
  {$IFDEF MSWINDOWS}
  const WindowsExpected = 'C:\Windows\Fonts, C:\Users\kees\AppData\Local\Microsoft\Windows\Fonts';
  Assert.AreEqual(WindowsExpected, string.Join(', ', TFontDirFinder.WindowsDirectories('C:\Windows', 'C:\Users\kees\AppData\Local')));
  {$ENDIF}
end;

procedure TFileSystemFontProviderTests.TestDirectoryDepthIsBounded;
begin
  CopyTestFont(JosefinSans, FWorkFolder);
  CopyTestFont(LiberationSans, NestedFolder(40));
  const Stopwatch = TStopwatch.StartNew;

  const Found = TFontFileFinder.Find([FWorkFolder], FLog);

  Assert.IsTrue(Stopwatch.ElapsedMilliseconds < TimeLimitMilliseconds, Format('The scan took %d ms', [Stopwatch.ElapsedMilliseconds]));
  Assert.AreEqual(JosefinSans, FileNames(Found));
  Assert.IsTrue(LogText.Contains('deeper'), 'The log does not say that the scan stopped: ' + LogText);
end;

procedure TFileSystemFontProviderTests.TestDirectoryAtTheDepthLimitIsScanned;
begin
  const LimitFolder = NestedFolder(TFontFileFinder.MaximumDepth);
  CopyTestFontAs(LiberationSans, TPath.Combine(LimitFolder, 'at-limit.ttf'));
  CopyTestFontAs(LiberationSans, TPath.Combine(NestedFolder(TFontFileFinder.MaximumDepth + 1), 'beyond-limit.ttf'));

  const Found = TFontFileFinder.Find([FWorkFolder]);

  Assert.AreEqual('at-limit.ttf', FileNames(Found));
end;

procedure TFileSystemFontProviderTests.TestMissingDirectoryIsIgnored;
begin
  const Provider = NewProvider([TPath.Combine(FWorkFolder, 'nothing-here')]);

  Assert.AreEqual<NativeInt>(0, Length(Provider.FontInfos));
  Assert.AreEqual('', Provider.ToDebugString);
end;

procedure TFileSystemFontProviderTests.TestOnlyFontExtensionsAreFound;
begin
  const Names: TArray<string> = ['a.ttf', 'B.TTF', 'c.otf', 'd.ttc', 'e.otc', 'f.pfb', 'g.txt', 'h.ttf.bak', 'i.pfm', 'ttf'];
  for var Name in Names do
  begin
    TFile.WriteAllBytes(TPath.Combine(FWorkFolder, Name), [1, 2, 3]);
  end;

  const Found = TFontFileFinder.Find([FWorkFolder]);

  Assert.AreEqual('B.TTF, a.ttf, c.otf, d.ttc, e.otc, f.pfb', FileNames(Found));
end;

procedure TFileSystemFontProviderTests.TestScanHappensOnFirstUseAndOnce;
begin
  CopyTestFont(LiberationSans, FWorkFolder);
  const Provider = NewProvider([FWorkFolder]);
  CopyTestFont(JosefinSans, FWorkFolder);

  const First = Provider.FontInfos;
  CopyTestFont(SourceSans, FWorkFolder);
  const Second = Provider.FontInfos;

  Assert.AreEqual<NativeInt>(2, Length(First));
  Assert.AreEqual<NativeInt>(2, Length(Second));
  Assert.AreSame(First[0], Second[0]);
end;

procedure TFileSystemFontProviderTests.TestTrueTypeFontWithCffOutlinesIsSkipped;
begin
  CopyTestFontAs(SourceSans, TPath.Combine(FWorkFolder, 'cff.ttf'));
  const Provider = NewProvider([FWorkFolder]);

  Assert.AreEqual<NativeInt>(0, Length(Provider.FontInfos));
  Assert.IsTrue(LogText.Contains('cff.ttf'), 'The log has no line about cff.ttf: ' + LogText);
  Assert.IsTrue(LogText.Contains('CFF outlines'), 'The log does not give the reason: ' + LogText);
end;

procedure TFileSystemFontProviderTests.TestFontThatDisappearedRaisesParseException;
begin
  CopyTestFontAs(LiberationSans, TPath.Combine(FWorkFolder, 'gone.ttf'));
  const Provider = NewProvider([FWorkFolder]);
  FInfo := Provider.FontInfos[0];
  TFile.Delete(TPath.Combine(FWorkFolder, 'gone.ttf'));

  Assert.WillRaise(GetFontOfFieldInfo, EPdfParseException);
end;

procedure TFileSystemFontProviderTests.TestTableHeadersMatchTheFullParse;
begin
  const TrueTypeSource = TRandomAccessRead.FromBytes(TTestFonts.Bytes(LiberationSans));
  const OpenTypeSource = TRandomAccessRead.FromBytes(TTestFonts.Bytes(SourceSans));
  try
    const TrueTypeParser = TTTFParser.Create;
    const OpenTypeParser = TOTFParser.Create;
    try
      const TrueTypeHeaders = TrueTypeParser.ParseTableHeaders(TrueTypeSource);
      const OpenTypeHeaders = OpenTypeParser.ParseTableHeaders(OpenTypeSource);
      const TrueTypeFont = TrueTypeParser.Parse(TTestFonts.Bytes(LiberationSans));
      try
        Assert.AreEqual('', TrueTypeHeaders.Error);
        Assert.AreEqual(TrueTypeFont.Name, TrueTypeHeaders.Name);
        Assert.IsTrue(TrueTypeHeaders.HasMacStyle);
        Assert.AreEqual(TrueTypeFont.Header.MacStyle, TrueTypeHeaders.MacStyle);
        Assert.IsFalse(TrueTypeHeaders.IsOpenTypePostScript);
      finally
        TrueTypeFont.Free;
      end;

      const OpenTypeFont = OpenTypeParser.Parse(TTestFonts.Bytes(SourceSans));
      try
        Assert.AreEqual('', OpenTypeHeaders.Error);
        Assert.AreEqual(OpenTypeFont.Name, OpenTypeHeaders.Name);
        Assert.IsTrue(OpenTypeHeaders.IsOpenTypePostScript);
        Assert.IsFalse(OpenTypeHeaders.HasCIDSystemInfo);
      finally
        OpenTypeFont.Free;
      end;
    finally
      OpenTypeParser.Free;
      TrueTypeParser.Free;
    end;
  finally
    OpenTypeSource.Free;
    TrueTypeSource.Free;
  end;
end;

procedure TFileSystemFontProviderTests.TestCollectionHeadersAreReadPerFont;
begin
  const Source = TRandomAccessRead.FromBytes(CollectionBytes);
  try
    const AllHeaders = TTrueTypeCollection.ReadAllFontHeaders(Source);

    Assert.AreEqual<NativeInt>(2, Length(AllHeaders));
    Assert.AreEqual('', AllHeaders[0].Error);
    Assert.AreEqual('', AllHeaders[1].Error);
    Assert.AreEqual('LiberationSans', AllHeaders[0].Name);
    Assert.AreEqual('LiberationSans', AllHeaders[1].Name);
  finally
    Source.Free;
  end;
end;

{$IFDEF POSIX}
procedure TFileSystemFontProviderTests.TestSymbolicLinkLoopTerminates;
begin
  const Inner = TPath.Combine(FWorkFolder, 'inner');
  TDirectory.CreateDirectory(Inner);
  CopyTestFont(LiberationSans, Inner);
  CreateSymbolicLink(FWorkFolder, TPath.Combine(Inner, 'back'));
  CreateSymbolicLink(Inner, TPath.Combine(Inner, 'self'));
  CreateSymbolicLink(Inner, TPath.Combine(FWorkFolder, 'alias'));
  const Stopwatch = TStopwatch.StartNew;

  const Found = TFontFileFinder.Find([FWorkFolder]);

  Assert.IsTrue(Stopwatch.ElapsedMilliseconds < TimeLimitMilliseconds, Format('The scan took %d ms', [Stopwatch.ElapsedMilliseconds]));
  Assert.AreEqual(LiberationSans, FileNames(Found));
end;
{$ENDIF}

end.
