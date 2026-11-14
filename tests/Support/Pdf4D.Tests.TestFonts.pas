// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.TestFonts;

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  // The fonts in tests/fonts and the glyph widths that PDFBox gives for them (<font>.widths.txt)
  TTestFonts = class
  private
    class function Folder: string; static;

  public
    class function Path(const FileName: string): string; static;
    class function Bytes(const FileName: string): TBytes; static;
    // Font units per glyph key (for example gid10). The caller owns the dictionary.
    class function ReferenceWidths(const FileName: string): TDictionary<string, Single>; static;
  end;

implementation

uses
  System.IOUtils;

const
  FontsEnvironmentVariable = 'PDF4D_FONTS';
  ManifestName = 'manifest.csv';
  WidthsSuffix = '.widths.txt';

{ TTestFonts }

class function TTestFonts.Folder: string;
begin
  const FromEnvironment = GetEnvironmentVariable(FontsEnvironmentVariable);
  if FromEnvironment <> '' then
  begin
    Exit(FromEnvironment);
  end;

  var Current := TPath.GetDirectoryName(ParamStr(0));
  while Current <> '' do
  begin
    const Candidate = TPath.Combine(Current, 'fonts');
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
  raise EFileNotFoundException.Create('The test fonts folder (tests/fonts) was not found; set PDF4D_FONTS');
end;

class function TTestFonts.Path(const FileName: string): string;
begin
  Result := TPath.Combine(Folder, FileName);
end;

class function TTestFonts.Bytes(const FileName: string): TBytes;
begin
  Result := TFile.ReadAllBytes(Path(FileName));
end;

class function TTestFonts.ReferenceWidths(const FileName: string): TDictionary<string, Single>;
begin
  Result := TDictionary<string, Single>.Create;
  try
    for var Line in TFile.ReadAllLines(Path(FileName + WidthsSuffix), TEncoding.UTF8) do
    begin
      const Separator = Line.IndexOf(' ');
      if Separator > 0 then
      begin
        const Key = Line.Substring(0, Separator);
        const Width = StrToFloat(Line.Substring(Separator + 1), TFormatSettings.Invariant);
        Result.AddOrSetValue(Key, Width);
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.
