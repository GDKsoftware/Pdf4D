// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/util/autodetect/FontDirFinder.java, NativeFontDirFinder.java,
// WindowsFontDirFinder.java, UnixFontDirFinder.java, MacFontDirFinder.java and FontFileFinder.java (3.0.8)
unit Pdf4D.Font.DirFinder;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.Log;

type
  // Where the fonts of the machine live. Only the folders that PDFBox looks in (WindowsFontDirFinder, UnixFontDirFinder and
  // MacFontDirFinder, with the user folder of Windows instead of the PostScript folder), and none of them has to exist.
  TFontDirFinder = class
  private
    {$IFNDEF MSWINDOWS}
    class function UserHomeDirectory: string; static;
    {$ENDIF}
    class function TrimTrailingSlash(const Directory: string): string; static;

  public
    // The folders for the platform that the library is built for
    class function SearchableDirectories: TArray<string>; static;
    // The folder lists of each platform; they only build paths and can be called on any platform
    class function WindowsDirectories(const WindowsDirectory, LocalAppData: string): TArray<string>; static;
    class function UnixDirectories(const HomeDirectory: string): TArray<string>; static;
    class function MacDirectories(const HomeDirectory: string): TArray<string>; static;
  end;

  // Finds the font files below some folders. The search is bounded: folders go at most MaximumDepth levels deep, a folder is
  // visited once (through its canonical path, so a symbolic link that points back ends the search), and the number of folders
  // and of font files is limited. A folder that cannot be read is skipped with a warning.
  TFontFileFinder = class
  public
    const MaximumDepth = 16;
    const MaximumDirectories = 20000;
    const MaximumFiles = 50000;

  private
    class function IsFontFile(const FileName: string): Boolean; static;
    class function EnumerateOrdered(const Directory: string; const WantFiles: Boolean): TArray<string>; static;

  private
    FLog: TPdfLog;
    FVisited: TDictionary<string, Boolean>;
    FFiles: TList<string>;
    FDirectoryCount: Integer;
    FIsLimitLogged: Boolean;

    function CanonicalKey(const Directory: string): string;
    function ResolveLink(const Directory: string): string;
    function IsFull: Boolean;
    procedure LogLimit(const Message: string);
    procedure LogUnreadable(const Directory: string; const Failure: Exception);
    function TryListDirectory(const Directory: string; const WantFiles: Boolean; out Entries: TArray<string>): Boolean;
    procedure AddFontFiles(const Directory: string);
    procedure ScanDirectory(const Directory: string; const Depth: Integer);
    procedure ScanChildren(const Directory: string; const Depth: Integer);

  public
    constructor Create(const Log: TPdfLog);
    destructor Destroy; override;

    // The font files (.ttf, .otf, .ttc, .otc and .pfb) in the folders and below them, in the order of the folders and, inside a
    // folder, of the file names. Folders that do not exist are skipped. The log is not owned and only used while Find runs.
    class function Find(const Directories: TArray<string>; const Log: TPdfLog = nil): TArray<string>; static;
  end;

implementation

uses
  System.IOUtils,
  System.Generics.Defaults;

const
  FontExtensions: array[0..4] of string = ('.ttf', '.otf', '.ttc', '.otc', '.pfb');

{ TFontDirFinder }

class function TFontDirFinder.TrimTrailingSlash(const Directory: string): string;
begin
  Result := Directory;
  while Result.EndsWith('/') or Result.EndsWith('\') do
  begin
    Result := Result.Substring(0, Result.Length - 1);
  end;
end;

{$IFNDEF MSWINDOWS}
class function TFontDirFinder.UserHomeDirectory: string;
begin
  Result := GetEnvironmentVariable('HOME');
  if Result = '' then
  begin
    Result := TPath.GetHomePath;
  end;
end;
{$ENDIF}

class function TFontDirFinder.WindowsDirectories(const WindowsDirectory, LocalAppData: string): TArray<string>;
begin
  Result := nil;
  if WindowsDirectory <> '' then
  begin
    Result := Result + [TPath.Combine(WindowsDirectory, 'Fonts')];
  end;
  if LocalAppData <> '' then
  begin
    Result := Result + [TPath.Combine(LocalAppData, 'Microsoft\Windows\Fonts')];
  end;
end;

class function TFontDirFinder.UnixDirectories(const HomeDirectory: string): TArray<string>;
begin
  Result := nil;
  const Home = TrimTrailingSlash(HomeDirectory);
  if Home <> '' then
  begin
    Result := [Format('%s/.fonts', [Home]), Format('%s/.local/share/fonts', [Home])];
  end;
  Result := Result + ['/usr/local/fonts', '/usr/local/share/fonts', '/usr/share/fonts', '/usr/X11R6/lib/X11/fonts', '/usr/share/X11/fonts'];
end;

class function TFontDirFinder.MacDirectories(const HomeDirectory: string): TArray<string>;
begin
  Result := nil;
  const Home = TrimTrailingSlash(HomeDirectory);
  if Home <> '' then
  begin
    Result := [Format('%s/Library/Fonts', [Home])];
  end;
  Result := Result + ['/Library/Fonts', '/System/Library/Fonts', '/Network/Library/Fonts'];
end;

class function TFontDirFinder.SearchableDirectories: TArray<string>;
begin
  {$IF DEFINED(MSWINDOWS)}
  Result := WindowsDirectories(GetEnvironmentVariable('WINDIR'), GetEnvironmentVariable('LOCALAPPDATA'));
  {$ELSEIF DEFINED(MACOS)}
  Result := MacDirectories(UserHomeDirectory);
  {$ELSE}
  Result := UnixDirectories(UserHomeDirectory);
  {$ENDIF}
end;

{ TFontFileFinder }

class function TFontFileFinder.Find(const Directories: TArray<string>; const Log: TPdfLog): TArray<string>;
begin
  const Finder = TFontFileFinder.Create(Log);
  try
    for var Directory in Directories do
    begin
      Finder.ScanDirectory(Directory, 0);
    end;
    Result := Finder.FFiles.ToArray;
  finally
    Finder.Free;
  end;
end;

constructor TFontFileFinder.Create(const Log: TPdfLog);
begin
  inherited Create;
  FLog := Log;
  FVisited := TDictionary<string, Boolean>.Create;
  FFiles := TList<string>.Create;
end;

destructor TFontFileFinder.Destroy;
begin
  FFiles.Free;
  FVisited.Free;
  inherited;
end;

class function TFontFileFinder.IsFontFile(const FileName: string): Boolean;
begin
  const Extension = TPath.GetExtension(FileName).ToLowerInvariant;
  for var FontExtension in FontExtensions do
  begin
    if Extension = FontExtension then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

// The same folder gets the same key, whatever way it was reached. Windows ignores the case of a path.
function TFontFileFinder.CanonicalKey(const Directory: string): string;
begin
  Result := ExcludeTrailingPathDelimiter(TPath.GetFullPath(Directory));
  {$IFDEF MSWINDOWS}
  Result := Result.ToLowerInvariant;
  {$ENDIF}
end;

// The folder that a symbolic link points to, or the folder itself when it is no link or the link cannot be resolved
function TFontFileFinder.ResolveLink(const Directory: string): string;
begin
  Result := Directory;
  try
    var Target: string;
    if not TFile.GetSymLinkTarget(Directory, Target) then
    begin
      Exit;
    end;

    if TPath.IsRelativePath(Target) then
    begin
      Target := TPath.Combine(TPath.GetDirectoryName(ExcludeTrailingPathDelimiter(Directory)), Target);
    end;
    Result := Target;
  except
    on Failure: Exception do
    begin
      Result := Directory;
    end;
  end;
end;

function TFontFileFinder.IsFull: Boolean;
begin
  Result := (FFiles.Count >= MaximumFiles) or (FDirectoryCount >= MaximumDirectories);
end;

procedure TFontFileFinder.LogLimit(const Message: string);
begin
  if Assigned(FLog) and not FIsLimitLogged then
  begin
    FLog.Warning(Message);
  end;
  FIsLimitLogged := True;
end;

procedure TFontFileFinder.LogUnreadable(const Directory: string; const Failure: Exception);
begin
  if Assigned(FLog) then
  begin
    FLog.Warning('Skip the font folder ''%s'' which cannot be read: %s', [Directory, Failure.Message]);
  end;
end;

class function TFontFileFinder.EnumerateOrdered(const Directory: string; const WantFiles: Boolean): TArray<string>;
begin
  if WantFiles then
  begin
    Result := TDirectory.GetFiles(Directory);
  end
  else
  begin
    Result := TDirectory.GetDirectories(Directory);
  end;
  TArray.Sort<string>(Result, TStringComparer.Ordinal);
end;

function TFontFileFinder.TryListDirectory(const Directory: string; const WantFiles: Boolean; out Entries: TArray<string>): Boolean;
begin
  Entries := nil;
  try
    Entries := EnumerateOrdered(Directory, WantFiles);
    Result := True;
  except
    on Failure: Exception do
    begin
      LogUnreadable(Directory, Failure);
      Result := False;
    end;
  end;
end;

procedure TFontFileFinder.AddFontFiles(const Directory: string);
begin
  var Files: TArray<string>;
  if not TryListDirectory(Directory, True, Files) then
  begin
    Exit;
  end;

  for var FileName in Files do
  begin
    if not IsFontFile(FileName) then
    begin
      Continue;
    end;

    if FFiles.Count >= MaximumFiles then
    begin
      LogLimit(Format('Stop looking for fonts after %d font files', [MaximumFiles]));
      Exit;
    end;
    FFiles.Add(FileName);
  end;
end;

procedure TFontFileFinder.ScanChildren(const Directory: string; const Depth: Integer);
begin
  var Children: TArray<string>;
  if not TryListDirectory(Directory, False, Children) then
  begin
    Exit;
  end;

  for var Child in Children do
  begin
    if IsFull then
    begin
      Exit;
    end;
    ScanDirectory(ResolveLink(Child), Depth + 1);
  end;
end;

procedure TFontFileFinder.ScanDirectory(const Directory: string; const Depth: Integer);
begin
  if Depth > MaximumDepth then
  begin
    LogLimit(Format('Skip the font folder ''%s'' and the ones that are deeper than %d levels', [Directory, MaximumDepth]));
    Exit;
  end;

  if FDirectoryCount >= MaximumDirectories then
  begin
    LogLimit(Format('Stop looking for fonts after %d folders', [MaximumDirectories]));
    Exit;
  end;

  const IsNewDirectory = (TDirectory.Exists(Directory) and FVisited.TryAdd(CanonicalKey(Directory), True));
  if not IsNewDirectory then
  begin
    Exit;
  end;

  Inc(FDirectoryCount);
  AddFontFiles(Directory);
  ScanChildren(Directory, Depth);
end;

end.
