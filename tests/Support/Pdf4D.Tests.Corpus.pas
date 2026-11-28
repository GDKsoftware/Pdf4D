// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.Corpus;

interface

uses
  System.SysUtils;

type
  // The test corpus (tests/corpus, listed in manifest.csv) and the golden files that belong to it
  TCorpus = record
  strict private
    class function Manifest: TArray<string>; static;
    class function FolderFromProgram: string; static;

  public
    // The folder with manifest.csv: PDF4D_CORPUS when set, otherwise the first "corpus" folder with a manifest on the way
    // up from the test program. Empty when there is none.
    class function Folder: string; static;
    // The folder with the golden dumps, next to the corpus folder
    class function GoldenFolder: string; static;

    // The files of the manifest, relative to the corpus folder, with / as separator
    class function Files: TArray<string>; static;
    // The password of the file: the value after "password=" in the notes, empty when there is none
    class function PasswordFor(const RelativePath: string): string; static;

    class function PdfPath(const RelativePath: string): string; static;
    // The name of the golden files of a file: the relative path with / replaced by __
    class function GoldenName(const RelativePath: string): string; static;
    class function GoldenPath(const RelativePath: string): string; static;
    class function KnownDifferencesPath(const RelativePath: string): string; static;
    // The text golden of PDFBox and the known differences of the text
    class function TextGoldenPath(const RelativePath: string): string; static;
    class function TextKnownDifferencesPath(const RelativePath: string): string; static;
    // The position golden of PDFBox and the known differences of the positions
    class function PositionsGoldenPath(const RelativePath: string): string; static;
    class function PositionsKnownDifferencesPath(const RelativePath: string): string; static;
    // The image location golden of PDFBox and the known differences of the image locations
    class function ImagesGoldenPath(const RelativePath: string): string; static;
    class function ImagesKnownDifferencesPath(const RelativePath: string): string; static;
  end;

implementation

uses
  System.IOUtils;

const
  CorpusEnvironmentVariable = 'PDF4D_CORPUS';
  ManifestName = 'manifest.csv';
  PasswordMarker = 'password=';
  NotesColumn = 3;

{ TCorpus }

class function TCorpus.FolderFromProgram: string;
begin
  var Current := TPath.GetDirectoryName(ParamStr(0));
  while Current <> '' do
  begin
    const Candidate = TPath.Combine(Current, 'corpus');
    if TFile.Exists(TPath.Combine(Candidate, ManifestName)) then
    begin
      Exit(Candidate);
    end;

    const Parent = TPath.GetDirectoryName(Current);
    if Parent = Current then
    begin
      Break;
    end;
    Current := Parent;
  end;
  Result := '';
end;

class function TCorpus.Folder: string;
begin
  const FromEnvironment = GetEnvironmentVariable(CorpusEnvironmentVariable);
  if FromEnvironment <> '' then
  begin
    Result := FromEnvironment;
  end
  else
  begin
    Result := FolderFromProgram;
  end;
end;

class function TCorpus.GoldenFolder: string;
begin
  Result := TPath.Combine(TPath.GetDirectoryName(Folder), 'golden');
end;

class function TCorpus.Manifest: TArray<string>;
begin
  const Rows = TFile.ReadAllLines(TPath.Combine(Folder, ManifestName), TEncoding.UTF8);
  // The first row holds the column names
  if Length(Rows) > 1 then
  begin
    Result := Copy(Rows, 1, Length(Rows) - 1);
  end
  else
  begin
    Result := nil;
  end;
end;

class function TCorpus.Files: TArray<string>;
begin
  Result := nil;
  if Folder = '' then
  begin
    Exit;
  end;

  for var Row in Manifest do
  begin
    const Columns = Row.Split([';']);
    if (Length(Columns) >= 4) and (Columns[0] <> '') then
    begin
      Result := Result + [Columns[0]];
    end;
  end;
end;

class function TCorpus.PasswordFor(const RelativePath: string): string;
begin
  Result := '';
  for var Row in Manifest do
  begin
    const Columns = Row.Split([';']);
    if (Length(Columns) < 4) or (Columns[0] <> RelativePath) then
    begin
      Continue;
    end;

    // The notes may contain the separator
    const Notes = string.Join(';', Copy(Columns, NotesColumn));
    const Position = Notes.IndexOf(PasswordMarker);
    if Position >= 0 then
    begin
      Result := Notes.Substring(Position + PasswordMarker.Length);
      const Stop = Result.IndexOfAny([',', ';', ' ']);
      if Stop >= 0 then
      begin
        Result := Result.Substring(0, Stop);
      end;
    end;
    Exit;
  end;
end;

class function TCorpus.PdfPath(const RelativePath: string): string;
begin
  Result := TPath.Combine(Folder, RelativePath.Replace('/', PathDelim));
end;

class function TCorpus.GoldenName(const RelativePath: string): string;
begin
  Result := RelativePath.Replace('/', '__');
end;

class function TCorpus.GoldenPath(const RelativePath: string): string;
begin
  Result := TPath.Combine(GoldenFolder, GoldenName(RelativePath) + '.dump.txt');
end;

class function TCorpus.KnownDifferencesPath(const RelativePath: string): string;
begin
  Result := TPath.Combine(GoldenFolder, GoldenName(RelativePath) + '.known-differences.txt');
end;

class function TCorpus.TextGoldenPath(const RelativePath: string): string;
begin
  Result := TPath.Combine(GoldenFolder, GoldenName(RelativePath) + '.text.txt');
end;

class function TCorpus.TextKnownDifferencesPath(const RelativePath: string): string;
begin
  Result := TPath.Combine(GoldenFolder, GoldenName(RelativePath) + '.text-known-differences.txt');
end;

class function TCorpus.PositionsGoldenPath(const RelativePath: string): string;
begin
  Result := TPath.Combine(GoldenFolder, GoldenName(RelativePath) + '.positions.txt');
end;

class function TCorpus.PositionsKnownDifferencesPath(const RelativePath: string): string;
begin
  Result := TPath.Combine(GoldenFolder, GoldenName(RelativePath) + '.positions.known-differences.txt');
end;

class function TCorpus.ImagesGoldenPath(const RelativePath: string): string;
begin
  Result := TPath.Combine(GoldenFolder, GoldenName(RelativePath) + '.images.txt');
end;

class function TCorpus.ImagesKnownDifferencesPath(const RelativePath: string): string;
begin
  Result := TPath.Combine(GoldenFolder, GoldenName(RelativePath) + '.images.known-differences.txt');
end;

end.
