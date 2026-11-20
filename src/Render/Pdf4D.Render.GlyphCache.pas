// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/rendering/GlyphCache.java (3.0.8), with a bound on the size of the cache
unit Pdf4D.Render.GlyphCache;

{$EXCESSPRECISION OFF}

interface

uses
  System.Generics.Collections,
  Pdf4D.Common.Log,
  Pdf4D.Common.Path,
  Pdf4D.Font.Base;

type
  // The outlines of the glyphs that a renderer has drawn, per font and code. PDFBox keeps one unbounded map per font; this cache has
  // one bound for all fonts, because a document can have any number of fonts and codes. When the bound is reached the cache starts
  // again from empty, so a path that TryGetPath gave is valid until the next call. A font is known by its dictionary, so that two
  // font objects of one dictionary share their paths.
  TPdfGlyphCache = class
  public
    const DefaultMaxEntries = 8192;
    const DefaultMaxPoints = 4 * 1024 * 1024;

  private
    FLog: TPdfLog;
    FMaxEntries: Integer;
    FMaxPoints: Integer;
    FFonts: TObjectDictionary<NativeInt, TObjectDictionary<Integer, TPdfPath>>;
    FEntryCount: Integer;
    FPointCount: Integer;

    class function FontKey(const Font: TPDFont): NativeInt; static;
    function TryFindEntry(const Font: TPDFont; const Code: Integer; out Path: TPdfPath): Boolean;
    function LoadPath(const Font: TPDFont; const Code: Integer): TPdfPath;
    procedure Remember(const Font: TPDFont; const Code: Integer; const Path: TPdfPath);
    procedure Restart;

  public
    // Log may be nil and is not owned
    constructor Create(const Log: TPdfLog; const MaxEntries: Integer = DefaultMaxEntries; const MaxPoints: Integer = DefaultMaxPoints);
    destructor Destroy; override;

    // GlyphCache.getPathForCharacterCode: the normalized path of the font program, in its glyph space, which the font matrix scales.
    // The path belongs to the cache. False, with one line in the log per font and code, when the font has no outline for the code.
    function TryGetPath(const Font: TPDFont; const Code: Integer; out Path: TPdfPath): Boolean;

    // The codes (also those without a glyph) that the cache remembers
    property EntryCount: Integer read FEntryCount;
  end;

implementation

uses
  System.SysUtils,
  Pdf4D.Common.Defines;

{ TPdfGlyphCache }

constructor TPdfGlyphCache.Create(const Log: TPdfLog; const MaxEntries, MaxPoints: Integer);
begin
  inherited Create;
  FLog := Log;
  FMaxEntries := MaxEntries;
  FMaxPoints := MaxPoints;
  FFonts := TObjectDictionary<NativeInt, TObjectDictionary<Integer, TPdfPath>>.Create([doOwnsValues]);
end;

destructor TPdfGlyphCache.Destroy;
begin
  FFonts.Free;
  inherited;
end;

class function TPdfGlyphCache.FontKey(const Font: TPDFont): NativeInt;
begin
  Result := NativeInt(Font.CosObject);
end;

function TPdfGlyphCache.TryFindEntry(const Font: TPDFont; const Code: Integer; out Path: TPdfPath): Boolean;
begin
  Path := nil;
  var Entries: TObjectDictionary<Integer, TPdfPath>;
  Result := (FFonts.TryGetValue(FontKey(Font), Entries) and Entries.TryGetValue(Code, Path));
end;

// A font that fails on damaged data has no glyph, like one that says so
function TPdfGlyphCache.LoadPath(const Font: TPDFont; const Code: Integer): TPdfPath;
begin
  Result := nil;
  try
    if not Font.TryGetNormalizedPath(Code, Result) then
    begin
      Result := nil;
    end;
  except
    on Failure: Exception do
    begin
      if TPdfFailure.IsFatal(Failure) then
      begin
        raise;
      end;
      Result := nil;
      if Assigned(FLog) then
      begin
        FLog.Error('The glyph for code %d of font %s could not be read: %s', [Code, Font.Name, Failure.Message]);
      end;
    end;
  end;

  if (not Assigned(Result)) and Assigned(FLog) then
  begin
    FLog.Warning('No glyph for code %d in font %s', [Code, Font.Name]);
  end;
end;

procedure TPdfGlyphCache.Restart;
begin
  FFonts.Clear;
  FEntryCount := 0;
  FPointCount := 0;
end;

procedure TPdfGlyphCache.Remember(const Font: TPDFont; const Code: Integer; const Path: TPdfPath);
begin
  var Points := 0;
  if Assigned(Path) then
  begin
    Points := Path.PointCount;
  end;

  if (FEntryCount >= FMaxEntries) or (FPointCount + Points > FMaxPoints) then
  begin
    Restart;
  end;

  var Entries: TObjectDictionary<Integer, TPdfPath>;
  if not FFonts.TryGetValue(FontKey(Font), Entries) then
  begin
    Entries := TObjectDictionary<Integer, TPdfPath>.Create([doOwnsValues]);
    FFonts.Add(FontKey(Font), Entries);
  end;
  Entries.Add(Code, Path);
  Inc(FEntryCount);
  Inc(FPointCount, Points);
end;

function TPdfGlyphCache.TryGetPath(const Font: TPDFont; const Code: Integer; out Path: TPdfPath): Boolean;
begin
  if TryFindEntry(Font, Code, Path) then
  begin
    Exit(Assigned(Path));
  end;

  Path := LoadPath(Font, Code);
  try
    Remember(Font, Code, Path);
  except
    Path.Free;
    raise;
  end;
  Result := Assigned(Path);
end;

end.
