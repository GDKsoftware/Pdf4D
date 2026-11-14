// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Font.ToUnicodeCache.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Model.Tests.Support;

type
  // Fonts that share one /ToUnicode stream parse it, and charge its mappings to the document, once
  [TestFixture]
  TToUnicodeCacheTests = class
  private
    FModels: TModelTestDocuments;

    function OpenDocumentWithSharedToUnicode(const FontCount: Integer; const ToUnicode: TBytes; const StreamEntries: string): TObject;
    procedure CheckAllFontsShare(const FontCount: Integer; const ToUnicode: TBytes; const StreamEntries: string);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestThousandFontsShareOneToUnicodeStream;

    [Test]
    procedure TestZeroMappingStreamIsCachedAndNotParsedAgain;
  end;

implementation

uses
  System.Classes,
  System.Diagnostics,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Names,
  Pdf4D.Font.Base,
  Pdf4D.Font.Factory,
  Pdf4D.Filter.Tests.Support,
  Pdf4D.Model.Document,
  Pdf4D.Model.DocumentContext,
  Pdf4D.Tests.PdfBuilder,
  Pdf4D.Tests.TextDocuments;

const
  SharedFontCount = 1000;
  ToUnicodeObject = 5000;
  CMapStart = '/CIDInit /ProcSet findresource begin 12 dict begin begincmap /CMapName /Test def /CMapType 2 def ';
  CMapEnd = 'endcmap CMapName currentdict /CMap defineresource pop end end';
  CodeSpace = '1 begincodespacerange <00> <FF> endcodespacerange ';
  OneMapping = CMapStart + CodeSpace + '1 beginbfchar <01> <0041> endbfchar ' + CMapEnd;
  NoMapping = CMapStart + CodeSpace + CMapEnd;
  FontBody = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /ToUnicode 5000 0 R >>';

{ TToUnicodeCacheTests }

procedure TToUnicodeCacheTests.Setup;
begin
  FModels := TModelTestDocuments.Create;
end;

procedure TToUnicodeCacheTests.TearDown;
begin
  FreeAndNil(FModels);
end;

function TToUnicodeCacheTests.OpenDocumentWithSharedToUnicode(const FontCount: Integer; const ToUnicode: TBytes; const StreamEntries: string): TObject;
begin
  const Bodies = TStringBuilder.Create;
  try
    for var Index := 1 to FontCount do
    begin
      if Index > 1 then
      begin
        Bodies.Append(TTextTestDocuments.Separator);
      end;
      Bodies.Append(FontBody);
    end;
    const Builder = TTextTestDocuments.NewBuilder(Bodies.ToString, '');
    try
      Builder.AddStreamObject(ToUnicodeObject, StreamEntries, ToUnicode);
      Result := FModels.Open(Builder);
    finally
      Builder.Free;
    end;
  finally
    Bodies.Free;
  end;
end;

procedure TToUnicodeCacheTests.CheckAllFontsShare(const FontCount: Integer; const ToUnicode: TBytes; const StreamEntries: string);
begin
  const Document = OpenDocumentWithSharedToUnicode(FontCount, ToUnicode, StreamEntries) as TPDDocument;
  var Stream: TCosBase;
  const Fonts = TTextTestDocuments.FontDictionary(Document, 'F1');
  Assert.IsTrue(Fonts.TryGetDictionaryObject(TCosNames.ToUnicode, Stream));

  for var Index := 1 to FontCount do
  begin
    const Dictionary = TTextTestDocuments.FontDictionary(Document, Format('F%d', [Index]));
    Assert.IsNotNull(TPDFontFactory.GetFont(Dictionary, Document.Context));
  end;

  var Cached: TObject;
  Assert.IsTrue(Document.Context.TryGetCachedObject(TPDCacheScope.ToUnicode, Stream, Cached), 'the parsed CMap is kept per stream');
  Assert.IsNotNull(TToUnicodeCacheEntry(Cached).CMap);
end;

procedure TToUnicodeCacheTests.TestThousandFontsShareOneToUnicodeStream;
begin
  CheckAllFontsShare(SharedFontCount, TEncoding.ASCII.GetBytes(OneMapping), '');

  const Context = FModels.Document.Context;
  Assert.AreEqual<Int64>(1, Context.ToUnicodeMappings, 'the mappings are charged once, not once per font');
  var Value: string;
  const Font = TPDFontFactory.GetFont(TTextTestDocuments.FontDictionary(FModels.Document, 'F777'), Context);
  Assert.IsTrue(Font.TryToUnicode(1, Value));
  Assert.AreEqual('A', Value);
end;

procedure TToUnicodeCacheTests.TestZeroMappingStreamIsCachedAndNotParsedAgain;
begin
  // 8 MiB of blanks in front of the CMap: decoding and parsing it a thousand times would take minutes
  const Blanks = StringOfChar(' ', 8 * 1024 * 1024);
  const Data = TFilterTestSupport.Compress(TEncoding.ASCII.GetBytes(Blanks + NoMapping));
  const Watch = TStopwatch.StartNew;

  CheckAllFontsShare(SharedFontCount, Data, '/Filter /FlateDecode');

  Assert.IsTrue(Watch.ElapsedMilliseconds < 20000, 'the stream is decoded and parsed once');
  Assert.AreEqual<Int64>(0, FModels.Document.Context.ToUnicodeMappings);
end;

end.
