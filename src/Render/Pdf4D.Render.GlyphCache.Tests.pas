// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests for Pdf4D.Render.GlyphCache
unit Pdf4D.Render.GlyphCache.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Common.Defines,
  Pdf4D.Common.Log,
  Pdf4D.Font.Base,
  Pdf4D.Model.Tests.Support,
  Pdf4D.Render.GlyphCache;

type
  [TestFixture]
  TGlyphCacheTests = class
  private
    FModels: TModelTestDocuments;
    FFonts: TObjectList<TPDFont>;
    FLog: TPdfLog;
    FLogLines: TList<string>;
    FCache: TPdfGlyphCache;

    function OpenHelvetica: TPDFont;
    function NewCache(const MaxEntries: Integer): TPdfGlyphCache;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestGlyphCacheReturnsSamePath;

    [Test]
    procedure TestTwoFontObjectsOfOneDictionaryShareThePath;

    [Test]
    procedure TestMissingGlyphIsLoggedOnce;

    [Test]
    procedure TestCacheIsBounded;
  end;

implementation

uses
  Pdf4D.Common.Path,
  Pdf4D.Font.Factory,
  Pdf4D.Tests.TextDocuments;

const
  CapitalA = 65;
  CodeWithoutGlyph = 1;

{ TGlyphCacheTests }

procedure TGlyphCacheTests.Setup;
begin
  FModels := TModelTestDocuments.Create;
  FFonts := TObjectList<TPDFont>.Create(True);
  FLogLines := TList<string>.Create;
  FLog := TPdfLog.Create(
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      FLogLines.Add(Message);
    end);
  FCache := NewCache(TPdfGlyphCache.DefaultMaxEntries);
end;

procedure TGlyphCacheTests.TearDown;
begin
  FreeAndNil(FCache);
  FreeAndNil(FLog);
  FreeAndNil(FLogLines);
  FreeAndNil(FFonts);
  FreeAndNil(FModels);
end;

function TGlyphCacheTests.NewCache(const MaxEntries: Integer): TPdfGlyphCache;
begin
  Result := TPdfGlyphCache.Create(FLog, MaxEntries);
end;

function TGlyphCacheTests.OpenHelvetica: TPDFont;
begin
  const Builder = TTextTestDocuments.NewBuilder(TTextTestDocuments.HelveticaF1, '');
  try
    const Document = FModels.Open(Builder);
    Result := TPDFontFactory.CreateFont(TTextTestDocuments.FontDictionary(Document, 'F1'), Document.Context);
    FFonts.Add(Result);
  finally
    Builder.Free;
  end;
end;

procedure TGlyphCacheTests.TestGlyphCacheReturnsSamePath;
begin
  const Font = OpenHelvetica;

  var First: TPdfPath;
  var Second: TPdfPath;
  Assert.IsTrue(FCache.TryGetPath(Font, CapitalA, First));
  Assert.IsTrue(FCache.TryGetPath(Font, CapitalA, Second));

  Assert.AreSame(First, Second);
  Assert.AreEqual(1, FCache.EntryCount);
  Assert.IsFalse(First.IsEmpty);
end;

procedure TGlyphCacheTests.TestTwoFontObjectsOfOneDictionaryShareThePath;
begin
  const Font = OpenHelvetica;
  const Twin = TPDFontFactory.CreateFont(Font.CosObject, Font.Context);
  FFonts.Add(Twin);

  var First: TPdfPath;
  var Second: TPdfPath;
  Assert.IsTrue(FCache.TryGetPath(Font, CapitalA, First));
  Assert.IsTrue(FCache.TryGetPath(Twin, CapitalA, Second));

  Assert.AreSame(First, Second);
end;

procedure TGlyphCacheTests.TestMissingGlyphIsLoggedOnce;
begin
  const Font = OpenHelvetica;
  var Path: TPdfPath;
  const FoundFirst = FCache.TryGetPath(Font, CodeWithoutGlyph, Path);
  const LinesAfterFirst = FLogLines.Count;

  const FoundAgain = FCache.TryGetPath(Font, CodeWithoutGlyph, Path);

  Assert.AreEqual(FoundFirst, FoundAgain);
  Assert.AreEqual(LinesAfterFirst, FLogLines.Count);
end;

procedure TGlyphCacheTests.TestCacheIsBounded;
begin
  const Small = NewCache(10);
  try
    const Font = OpenHelvetica;
    for var Code := 32 to 126 do
    begin
      var Path: TPdfPath;
      Small.TryGetPath(Font, Code, Path);
      Assert.IsTrue(Small.EntryCount <= 10);
    end;
  finally
    Small.Free;
  end;
end;

end.
