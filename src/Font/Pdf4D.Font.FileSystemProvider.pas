// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/font/FileSystemFontProvider.java (3.0.8)
unit Pdf4D.Font.FileSystemProvider;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  Pdf4D.Common.Log,
  Pdf4D.Common.SharedInstance,
  Pdf4D.FontBox.FontBoxFont,
  Pdf4D.FontBox.TrueType.Headers,
  Pdf4D.Font.Descriptor,
  Pdf4D.Font.Provider;

type
  // The fonts in the font folders of the machine. The folders are scanned when the infos are first asked for, once, and only the
  // headers of the font files are read. A font file that cannot be read is skipped with a warning. The fonts themselves are loaded
  // when GetFont is first called on an info: fully read, and then shared by the whole process.
  // Unlike PDFBox there is no cache on disk (.pdfbox.cache): Pdf4D never writes to the file system.
  TFileSystemFontProvider = class(TInterfacedObject, IPdfFontProvider)
  public
    // Font files above this size are skipped
    const MaximumFontFileSize = 256 * 1024 * 1024;
    // The scan stops adding fonts after this many (a collection holds several)
    const MaximumFontInfos = 100000;

  private
    type
      TFSFontInfo = class(TFontInfo)
      private
        const NoCollection = -1;

      private
        FFilePath: string;
        FCollectionIndex: Integer;
        FPostScriptName: string;
        FFormat: TFontFormat;
        FHasCIDSystemInfo: Boolean;
        FCIDSystemInfo: TPDCIDSystemInfo;
        FFamilyClass: Integer;
        FWeightClass: Integer;
        FCodePageRange1: Integer;
        FCodePageRange2: Integer;
        FMacStyle: Integer;
        FPanose: TBytes;

        class function AsciiUntilNul(const Bytes: TBytes; const Start, Count: Integer): string; static;

        procedure ReadCharacterCollection(const Headers: TFontHeaders);
        function CacheKey: string;
        function IsCollectionFile: Boolean;
        function ReadFontFile: TBytes;
        function LoadFont: TFontBoxFont;
        function LoadCollectionFont(const Data: TBytes): TFontBoxFont;
        function LoadTrueTypeFont(const Data: TBytes): TFontBoxFont;

      public
        constructor Create(const FilePath: string; const CollectionIndex: Integer; const FontFormat: TFontFormat; const Headers: TFontHeaders);

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

        property FilePath: string read FFilePath;
      end;

  private
    // The fonts that were loaded, by file and collection index. They belong to the process: the cache frees them at shutdown.
    class var FFonts: TPdfSharedInstance<TPdfSharedCache<string, TFontBoxFont>>;

    class destructor Destroy;
    class function CreateFontCache: TPdfSharedCache<string, TFontBoxFont>; static;
    class function FontCache: TPdfSharedCache<string, TFontBoxFont>; static;
    class function IsFileFailure(const Failure: Exception): Boolean; static;

  private
    FDirectories: TArray<string>;
    FLog: TPdfLog;
    FMaximumFileSize: Int64;
    FMaximumInfos: Integer;
    FLock: TCriticalSection;
    FInfos: TObjectList<TFSFontInfo>;
    FInfoArray: TArray<TFontInfo>;
    FIsScanned: Boolean;

    procedure EnsureScanned;
    procedure Scan;
    procedure ScanFile(const FilePath: string);
    procedure LogSkippedFile(const FilePath: string; const Reason: string);
    procedure AddInfo(const Info: TFSFontInfo);
    procedure AddTrueTypeFont(const FilePath: string; const IsOpenTypeFile: Boolean);
    procedure AddTrueTypeCollection(const FilePath: string);
    procedure AddType1Font(const FilePath: string);
    procedure AddFromHeaders(const FilePath: string; const CollectionIndex: Integer; const Headers: TFontHeaders);
    procedure GuardFileSize(const FilePath: string; const Size: Int64);

  public
    // The log is not owned; it must live as long as the provider does, because the scan happens when the infos are first asked for.
    // A nil log is allowed.
    constructor Create(const Directories: TArray<string>; const Log: TPdfLog);
    destructor Destroy; override;

    // The provider for the font folders of the machine. The log is optional, not owned and must outlive the provider.
    class function CreateDefault(const Log: TPdfLog = nil): IPdfFontProvider; static;

    function FontInfos: TArray<TFontInfo>;
    function ToDebugString: string;

    // The limits of the scan, for tests; set them before the infos are first asked for
    property MaximumFileSize: Int64 read FMaximumFileSize write FMaximumFileSize;
    property MaximumInfos: Integer read FMaximumInfos write FMaximumInfos;
  end;

implementation

uses
  System.TypInfo,
  Pdf4D.Common.Defines,
  Pdf4D.IO.RandomAccessRead,
  Pdf4D.FontBox.OpenType,
  Pdf4D.FontBox.TrueType.Collection,
  Pdf4D.FontBox.TrueType.Font,
  Pdf4D.FontBox.TrueType.Parser,
  Pdf4D.FontBox.Type1.Font,
  Pdf4D.Font.DirFinder;

const
  GcidRegistryStart = 10;
  GcidOrderingStart = 76;
  GcidNameLength = 64;

{ TFileSystemFontProvider.TFSFontInfo }

constructor TFileSystemFontProvider.TFSFontInfo.Create(const FilePath: string; const CollectionIndex: Integer; const FontFormat: TFontFormat;
                                                       const Headers: TFontHeaders);
begin
  inherited Create;
  FFilePath := FilePath;
  FCollectionIndex := CollectionIndex;
  FPostScriptName := Headers.Name;
  FFormat := FontFormat;

  FFamilyClass := -1;
  FWeightClass := -1;
  FMacStyle := -1;
  if Headers.HasMacStyle then
  begin
    FMacStyle := Headers.MacStyle;
  end;
  // Apple's AAT fonts have no OS/2 table
  if Headers.HasOS2Windows then
  begin
    FFamilyClass := Headers.FamilyClass;
    FWeightClass := Headers.WeightClass;
    FCodePageRange1 := Headers.CodePageRange1;
    FCodePageRange2 := Headers.CodePageRange2;
    FPanose := Copy(Headers.Panose);
  end;

  ReadCharacterCollection(Headers);
end;

class function TFileSystemFontProvider.TFSFontInfo.AsciiUntilNul(const Bytes: TBytes; const Start, Count: Integer): string;
begin
  Result := '';
  for var Index := Start to Start + Count - 1 do
  begin
    if Bytes[Index] = 0 then
    begin
      Break;
    end;
    Result := Result + Char(Bytes[Index]);
  end;
end;

procedure TFileSystemFontProvider.TFSFontInfo.ReadCharacterCollection(const Headers: TFontHeaders);
begin
  if Headers.IsOpenTypePostScript then
  begin
    FHasCIDSystemInfo := Headers.HasCIDSystemInfo;
    FCIDSystemInfo := TPDCIDSystemInfo.Create(Headers.Registry, Headers.Ordering, Headers.Supplement);
    Exit;
  end;

  // Apple's AAT fonts have a "gcid" table with CID info. PDFBox computes the supplement as (b140 << 8) & b141, which is always 0.
  const HasGcid = (Length(Headers.Gcid) >= TFontHeaders.GcidLength);
  if HasGcid then
  begin
    FHasCIDSystemInfo := True;
    FCIDSystemInfo := TPDCIDSystemInfo.Create(AsciiUntilNul(Headers.Gcid, GcidRegistryStart, GcidNameLength),
                                              AsciiUntilNul(Headers.Gcid, GcidOrderingStart, GcidNameLength), 0);
  end;
end;

function TFileSystemFontProvider.TFSFontInfo.PostScriptName: string;
begin
  Result := FPostScriptName;
end;

function TFileSystemFontProvider.TFSFontInfo.Format: TFontFormat;
begin
  Result := FFormat;
end;

function TFileSystemFontProvider.TFSFontInfo.TryGetCIDSystemInfo(out Info: TPDCIDSystemInfo): Boolean;
begin
  Info := FCIDSystemInfo;
  Result := FHasCIDSystemInfo;
end;

function TFileSystemFontProvider.TFSFontInfo.FamilyClass: Integer;
begin
  Result := FFamilyClass;
end;

function TFileSystemFontProvider.TFSFontInfo.WeightClass: Integer;
begin
  Result := FWeightClass;
end;

function TFileSystemFontProvider.TFSFontInfo.CodePageRange1: Integer;
begin
  Result := FCodePageRange1;
end;

function TFileSystemFontProvider.TFSFontInfo.CodePageRange2: Integer;
begin
  Result := FCodePageRange2;
end;

function TFileSystemFontProvider.TFSFontInfo.MacStyle: Integer;
begin
  Result := FMacStyle;
end;

function TFileSystemFontProvider.TFSFontInfo.TryGetPanose(out Panose: TPDPanoseClassification): Boolean;
begin
  Panose.Bytes := Copy(FPanose);
  Result := (Length(FPanose) >= TPDPanoseClassification.Length);
end;

function TFileSystemFontProvider.TFSFontInfo.CacheKey: string;
begin
  Result := System.SysUtils.Format('%s|%d', [FFilePath, FCollectionIndex]);
end;

function TFileSystemFontProvider.TFSFontInfo.IsCollectionFile: Boolean;
begin
  Result := (FCollectionIndex <> NoCollection);
end;

function TFileSystemFontProvider.TFSFontInfo.ReadFontFile: TBytes;
begin
  const Source = TRandomAccessRead.FromFile(FFilePath);
  try
    const Size = Source.Length;
    if Size > MaximumFontFileSize then
    begin
      raise EPdfLimitExceededException.CreateFmt('The font file is %d bytes, more than the limit of %d', [Size, MaximumFontFileSize]);
    end;
    Result := Source.ReadFully(Integer(Size));
  finally
    Source.Free;
  end;
end;

function TFileSystemFontProvider.TFSFontInfo.LoadCollectionFont(const Data: TBytes): TFontBoxFont;
begin
  const Collection = TTrueTypeCollection.Create(Data);
  try
    // The font has its own stream over the data, so it stays valid when the collection goes
    Result := Collection.FontAt(FCollectionIndex);
  finally
    Collection.Free;
  end;
end;

function TFileSystemFontProvider.TFSFontInfo.LoadTrueTypeFont(const Data: TBytes): TFontBoxFont;
begin
  const IsOpenTypeFile = SameText(ExtractFileExt(FFilePath), '.otf');
  if IsOpenTypeFile then
  begin
    const OpenTypeParser = TOTFParser.Create;
    try
      Result := OpenTypeParser.Parse(Data);
    finally
      OpenTypeParser.Free;
    end;
  end
  else
  begin
    const Parser = TTTFParser.Create;
    try
      Result := Parser.Parse(Data);
    finally
      Parser.Free;
    end;
  end;
end;

function TFileSystemFontProvider.TFSFontInfo.LoadFont: TFontBoxFont;
begin
  try
    const Data = ReadFontFile;
    if FFormat = TFontFormat.PFB then
    begin
      Result := TType1Font.CreateWithPFB(Data);
    end
    else if IsCollectionFile then
    begin
      Result := LoadCollectionFont(Data);
    end
    else
    begin
      Result := LoadTrueTypeFont(Data);
    end;
  except
    on EPdfException do
    begin
      raise;
    end;
    on Failure: Exception do
    begin
      if not IsFileFailure(Failure) then
      begin
        raise;
      end;
      raise EPdfParseException.CreateFmt('Could not load the font file ''%s'': %s', [FFilePath, Failure.Message]);
    end;
  end;
end;

function TFileSystemFontProvider.TFSFontInfo.GetFont: TFontBoxFont;
begin
  Result := FontCache.GetOrAdd(CacheKey,
    function(Key: string): TFontBoxFont
    begin
      Result := LoadFont;
    end);
end;

{ TFileSystemFontProvider }

class destructor TFileSystemFontProvider.Destroy;
begin
  FFonts.Release;
end;

class function TFileSystemFontProvider.CreateFontCache: TPdfSharedCache<string, TFontBoxFont>;
begin
  Result := TPdfSharedCache<string, TFontBoxFont>.Create;
end;

class function TFileSystemFontProvider.FontCache: TPdfSharedCache<string, TFontBoxFont>;
begin
  Result := FFonts.Get(CreateFontCache);
end;

// A failure of the file system or of the data of a file, as opposed to a mistake in the library
class function TFileSystemFontProvider.IsFileFailure(const Failure: Exception): Boolean;
begin
  Result := (TPdfFailure.IsInputFailure(Failure) or (Failure is EInOutError) or (Failure is EOSError));
end;

class function TFileSystemFontProvider.CreateDefault(const Log: TPdfLog): IPdfFontProvider;
begin
  Result := TFileSystemFontProvider.Create(TFontDirFinder.SearchableDirectories, Log);
end;

constructor TFileSystemFontProvider.Create(const Directories: TArray<string>; const Log: TPdfLog);
begin
  inherited Create;
  FDirectories := Copy(Directories);
  FLog := Log;
  FMaximumFileSize := MaximumFontFileSize;
  FMaximumInfos := MaximumFontInfos;
  FLock := TCriticalSection.Create;
  FInfos := TObjectList<TFSFontInfo>.Create(True);
end;

destructor TFileSystemFontProvider.Destroy;
begin
  FInfos.Free;
  FLock.Free;
  inherited;
end;

procedure TFileSystemFontProvider.EnsureScanned;
begin
  FLock.Enter;
  try
    if FIsScanned then
    begin
      Exit;
    end;

    try
      Scan;
    except
      // The infos of a scan that failed halfway are not trusted; the next call scans again
      FInfos.Clear;
      raise;
    end;

    SetLength(FInfoArray, FInfos.Count);
    for var Index := 0 to FInfos.Count - 1 do
    begin
      FInfoArray[Index] := FInfos[Index];
    end;
    FIsScanned := True;
  finally
    FLock.Leave;
  end;
end;

procedure TFileSystemFontProvider.Scan;
begin
  for var FilePath in TFontFileFinder.Find(FDirectories, FLog) do
  begin
    if FInfos.Count >= FMaximumInfos then
    begin
      if Assigned(FLog) then
      begin
        FLog.Warning('Stop scanning fonts after %d fonts', [FMaximumInfos]);
      end;
      Exit;
    end;
    ScanFile(FilePath);
  end;
end;

procedure TFileSystemFontProvider.LogSkippedFile(const FilePath: string; const Reason: string);
begin
  if Assigned(FLog) then
  begin
    FLog.Warning('Could not load font file ''%s'': %s', [FilePath, Reason]);
  end;
end;

procedure TFileSystemFontProvider.GuardFileSize(const FilePath: string; const Size: Int64);
begin
  if Size > FMaximumFileSize then
  begin
    raise EPdfLimitExceededException.CreateFmt('the file is %d bytes, more than the limit of %d', [Size, FMaximumFileSize]);
  end;
end;

// A file that cannot be read never stops the scan: whatever goes wrong with one file, the others are still found
procedure TFileSystemFontProvider.ScanFile(const FilePath: string);
begin
  try
    const Extension = ExtractFileExt(FilePath).ToLowerInvariant;
    if (Extension = '.ttf') or (Extension = '.otf') then
    begin
      AddTrueTypeFont(FilePath, (Extension = '.otf'));
    end
    else if (Extension = '.ttc') or (Extension = '.otc') then
    begin
      AddTrueTypeCollection(FilePath);
    end
    else if Extension = '.pfb' then
    begin
      AddType1Font(FilePath);
    end;
  except
    on Failure: Exception do
    begin
      LogSkippedFile(FilePath, Failure.Message);
    end;
  end;
end;

procedure TFileSystemFontProvider.AddInfo(const Info: TFSFontInfo);
begin
  FInfos.Add(Info);
end;

procedure TFileSystemFontProvider.AddFromHeaders(const FilePath: string; const CollectionIndex: Integer; const Headers: TFontHeaders);
begin
  if Headers.Error <> '' then
  begin
    LogSkippedFile(FilePath, Headers.Error);
    Exit;
  end;

  if Headers.Name = '' then
  begin
    LogSkippedFile(FilePath, 'the ''name'' table has no PostScript name');
    Exit;
  end;

  // Bitmap fonts have no "head" table
  if not Headers.HasMacStyle then
  begin
    Exit;
  end;

  var FontFormat := TFontFormat.TTF;
  if Headers.IsOpenTypePostScript then
  begin
    FontFormat := TFontFormat.OTF;
  end;
  AddInfo(TFSFontInfo.Create(FilePath, CollectionIndex, FontFormat, Headers));
end;

procedure TFileSystemFontProvider.AddTrueTypeFont(const FilePath: string; const IsOpenTypeFile: Boolean);
begin
  var Parser: TTTFParser;
  if IsOpenTypeFile then
  begin
    Parser := TOTFParser.Create;
  end
  else
  begin
    Parser := TTTFParser.Create;
  end;
  try
    const Source = TRandomAccessRead.FromFile(FilePath);
    try
      GuardFileSize(FilePath, Source.Length);
      AddFromHeaders(FilePath, TFSFontInfo.NoCollection, Parser.ParseTableHeaders(Source));
    finally
      Source.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TFileSystemFontProvider.AddTrueTypeCollection(const FilePath: string);
begin
  const Source = TRandomAccessRead.FromFile(FilePath);
  try
    GuardFileSize(FilePath, Source.Length);
    const AllHeaders = TTrueTypeCollection.ReadAllFontHeaders(Source);
    for var Index := 0 to Length(AllHeaders) - 1 do
    begin
      if FInfos.Count >= FMaximumInfos then
      begin
        Exit;
      end;
      AddFromHeaders(FilePath, Index, AllHeaders[Index]);
    end;
  finally
    Source.Free;
  end;
end;

// Type 1 fonts have no header to read: the font is parsed to get its name and released again, to save memory
procedure TFileSystemFontProvider.AddType1Font(const FilePath: string);
begin
  const Source = TRandomAccessRead.FromFile(FilePath);
  try
    GuardFileSize(FilePath, Source.Length);
    const Data = Source.ReadFully(Integer(Source.Length));
    const Font = TType1Font.CreateWithPFB(Data);
    try
      if Font.Name = '' then
      begin
        LogSkippedFile(FilePath, 'the font has no PostScript name');
        Exit;
      end;

      var Headers := Default(TFontHeaders);
      Headers.Name := Font.Name;
      AddInfo(TFSFontInfo.Create(FilePath, TFSFontInfo.NoCollection, TFontFormat.PFB, Headers));
    finally
      Font.Free;
    end;
  finally
    Source.Free;
  end;
end;

function TFileSystemFontProvider.FontInfos: TArray<TFontInfo>;
begin
  EnsureScanned;
  Result := FInfoArray;
end;

function TFileSystemFontProvider.ToDebugString: string;
begin
  const Lines = TStringBuilder.Create;
  try
    for var Info in FontInfos do
    begin
      const FormatName = GetEnumName(TypeInfo(TFontFormat), Ord(Info.Format));
      Lines.AppendLine(Format('%s: %s: %s', [FormatName, Info.PostScriptName, (Info as TFSFontInfo).FilePath]));
    end;
    Result := Lines.ToString;
  finally
    Lines.Free;
  end;
end;

end.
