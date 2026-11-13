// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/test/java/org/apache/fontbox/ttf/TestTTFParser.java (3.0.8)
unit Pdf4D.FontBox.TrueType.Post.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.FontBox.TrueType.Post,
  Pdf4D.Tests.TrueTypeBuilder;

type
  [TestFixture]
  TTrueTypePostTests = class
  private
    const Fixed10 = $00010000;
    const Fixed20 = $00020000;
    const Fixed25 = $00028000;
    const Fixed30 = $00030000;

  private
    class function PostHeader(const Writer: TTestByteWriter; const FormatType: Int64): TTestByteWriter; static;
    class procedure WriteName(const Writer: TTestByteWriter; const Name: string); static;
    class procedure ReadPostTable(const Host: TTestTableHost; const Bytes: TBytes); static;
    class function LoadPost(const Host: TTestTableHost; const Bytes: TBytes): TPostScriptTable; static;

  public
    [Test]
    procedure TestStandardMacNames;

    [Test]
    procedure TestFormat1HasTheStandardNames;

    [Test]
    procedure TestFormat2MixesStandardAndOwnNames;

    [Test]
    procedure TestFormat2NameCutOffByTheEndBecomesNotDef;

    [Test]
    procedure TestFormat2NameCountBeyondDataRaises;

    [Test]
    procedure TestFormat2GlyphCountBeyondDataRaises;

    [Test]
    procedure TestFormat25UsesTheOffsets;

    [Test]
    procedure TestFormat25OffsetsBeyondDataRaise;

    [Test]
    procedure TestFormat3HasNoNames;

    [Test]
    procedure TestTableWithoutNameDataLogsAndHasNoNames;

    [Test]
    procedure TestHeaderFields;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Common.Log,
  Pdf4D.FontBox.TrueType.DataStream;

{ TTrueTypePostTests }

class function TTrueTypePostTests.PostHeader(const Writer: TTestByteWriter; const FormatType: Int64): TTestByteWriter;
begin
  Writer.U32(FormatType);
  Writer.U32(0); // italic angle
  Writer.U16(-100 and $FFFF);
  Writer.U16(50);
  Writer.U32(1);
  Writer.U32(2);
  Writer.U32(3);
  Writer.U32(4);
  Writer.U32(5);
  Result := Writer;
end;

class procedure TTrueTypePostTests.WriteName(const Writer: TTestByteWriter; const Name: string);
begin
  Writer.U8(Name.Length);
  for var Letter in Name do
  begin
    Writer.U8(Ord(Letter));
  end;
end;

class procedure TTrueTypePostTests.ReadPostTable(const Host: TTestTableHost; const Bytes: TBytes);
begin
  LoadPost(Host, Bytes);
end;

class function TTrueTypePostTests.LoadPost(const Host: TTestTableHost; const Bytes: TBytes): TPostScriptTable;
begin
  Result := TPostScriptTable.Create(TPostScriptTable.TableTag, 0, 0, Length(Bytes));
  Host.AddTable(Result);
  const Stream = TTTFMemoryDataStream.Create(Bytes);
  try
    Result.Read(Host, Stream);
  finally
    Stream.Free;
  end;
end;

procedure TTrueTypePostTests.TestStandardMacNames;
begin
  var Name: string;

  Assert.IsTrue(TWGL4Names.TryGetGlyphName(0, Name));
  Assert.AreEqual('.notdef', Name);
  Assert.IsTrue(TWGL4Names.TryGetGlyphName(36, Name));
  Assert.AreEqual('A', Name);
  Assert.IsTrue(TWGL4Names.TryGetGlyphName(TWGL4Names.NumberOfMacGlyphs - 1, Name));
  Assert.AreEqual('dcroat', Name);
  Assert.IsFalse(TWGL4Names.TryGetGlyphName(TWGL4Names.NumberOfMacGlyphs, Name));
  Assert.IsFalse(TWGL4Names.TryGetGlyphName(-1, Name));
end;

procedure TTrueTypePostTests.TestFormat1HasTheStandardNames;
begin
  const Host = TTestTableHost.Create(258);
  try
    const Writer = TTestByteWriter.Create;
    try
      PostHeader(Writer, Fixed10);
      // A table that ends exactly at the end of the font data counts as a table without names, as in PDFBox
      Writer.U32(0);
      const Post = LoadPost(Host, Writer.ToBytes);

      var Name: string;
      Assert.IsTrue(Post.HasGlyphNames);
      Assert.AreEqual<Integer>(258, Post.GlyphNameCount);
      Assert.IsFalse(Post.TryGetName(258, Name));
    finally
      Writer.Free;
    end;
  finally
    Host.Free;
  end;
end;

procedure TTrueTypePostTests.TestFormat2MixesStandardAndOwnNames;
begin
  const Host = TTestTableHost.Create(5);
  try
    const Writer = TTestByteWriter.Create;
    try
      PostHeader(Writer, Fixed20);
      Writer.U16(5);
      for var Index in [0, 3, 258, 259, 40000] do
      begin
        Writer.U16(Index);
      end;
      WriteName(Writer, 'foo');
      WriteName(Writer, 'bar');
      const Post = LoadPost(Host, Writer.ToBytes);

      var Name: string;
      Assert.IsTrue(Post.TryGetName(0, Name));
      Assert.AreEqual('.notdef', Name);
      Assert.IsTrue(Post.TryGetName(1, Name));
      Assert.AreEqual('space', Name);
      Assert.IsTrue(Post.TryGetName(2, Name));
      Assert.AreEqual('foo', Name);
      Assert.IsTrue(Post.TryGetName(3, Name));
      Assert.AreEqual('bar', Name);
      Assert.IsTrue(Post.TryGetName(4, Name), 'an index from 32768 is reserved');
      Assert.AreEqual('.undefined', Name);
      Assert.IsFalse(Post.TryGetName(5, Name));
      Assert.IsFalse(Post.TryGetName(-1, Name));
    finally
      Writer.Free;
    end;
  finally
    Host.Free;
  end;
end;

procedure TTrueTypePostTests.TestFormat2NameCutOffByTheEndBecomesNotDef;
begin
  const Host = TTestTableHost.Create(3);
  try
    const Writer = TTestByteWriter.Create;
    try
      PostHeader(Writer, Fixed20);
      Writer.U16(3);
      for var Index in [258, 259, 260] do
      begin
        Writer.U16(Index);
      end;
      WriteName(Writer, 'foo');
      // The second name claims 9 characters and the data holds 2
      Writer.U8(9);
      Writer.U8(Ord('a'));
      Writer.U8(Ord('b'));
      const Post = LoadPost(Host, Writer.ToBytes);

      var Name: string;
      Assert.IsTrue(Post.TryGetName(0, Name));
      Assert.AreEqual('foo', Name);
      Assert.IsTrue(Post.TryGetName(1, Name));
      Assert.AreEqual('.notdef', Name);
      Assert.IsTrue(Post.TryGetName(2, Name));
      Assert.AreEqual('.notdef', Name);
    finally
      Writer.Free;
    end;
  finally
    Host.Free;
  end;
end;

// The highest index promises 32510 names that the data does not hold
procedure TTrueTypePostTests.TestFormat2NameCountBeyondDataRaises;
begin
  const Host = TTestTableHost.Create(1);
  try
    const Writer = TTestByteWriter.Create;
    try
      PostHeader(Writer, Fixed20);
      Writer.U16(1);
      Writer.U16(32767);
      const Bytes = Writer.ToBytes;

      Assert.WillRaise(
        procedure
        begin
          ReadPostTable(Host, Bytes);
        end,
        EPdfParseException);
    finally
      Writer.Free;
    end;
  finally
    Host.Free;
  end;
end;

procedure TTrueTypePostTests.TestFormat2GlyphCountBeyondDataRaises;
begin
  const Host = TTestTableHost.Create(1);
  try
    const Writer = TTestByteWriter.Create;
    try
      PostHeader(Writer, Fixed20);
      Writer.U16(65535);
      Writer.U16(3);
      const Bytes = Writer.ToBytes;

      Assert.WillRaise(
        procedure
        begin
          ReadPostTable(Host, Bytes);
        end,
        EPdfParseException);
    finally
      Writer.Free;
    end;
  finally
    Host.Free;
  end;
end;

procedure TTrueTypePostTests.TestFormat25UsesTheOffsets;
begin
  const Warnings = TList<string>.Create;
  const Log = TPdfLog.Create(
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      Warnings.Add(Message);
    end);
  const Host = TTestTableHost.Create(4);
  try
    Host.Log := Log;
    const Writer = TTestByteWriter.Create;
    try
      PostHeader(Writer, Fixed25);
      Writer.U8($80); // -128: the index of glyph 0 becomes negative
      Writer.U8(0);
      Writer.U8($FE); // -2
      Writer.U8(32);
      const Post = LoadPost(Host, Writer.ToBytes);

      var Name: string;
      Assert.IsFalse(Post.TryGetName(0, Name), 'a glyph with a bad index has no name');
      Assert.IsTrue(Post.TryGetName(1, Name));
      Assert.AreEqual('nonmarkingreturn', Name);
      Assert.IsTrue(Post.TryGetName(2, Name));
      Assert.AreEqual('.null', Name);
      Assert.IsTrue(Post.TryGetName(3, Name));
      Assert.AreEqual('A', Name);
      Assert.AreEqual<Integer>(1, Warnings.Count);
    finally
      Writer.Free;
    end;
  finally
    Host.Free;
    Log.Free;
    Warnings.Free;
  end;
end;

procedure TTrueTypePostTests.TestFormat25OffsetsBeyondDataRaise;
begin
  const Host = TTestTableHost.Create(60000);
  try
    const Writer = TTestByteWriter.Create;
    try
      PostHeader(Writer, Fixed25);
      Writer.U8(0);
      const Bytes = Writer.ToBytes;

      Assert.WillRaise(
        procedure
        begin
          ReadPostTable(Host, Bytes);
        end,
        EPdfParseException);
    finally
      Writer.Free;
    end;
  finally
    Host.Free;
  end;
end;

procedure TTrueTypePostTests.TestFormat3HasNoNames;
begin
  const Host = TTestTableHost.Create(5);
  try
    const Writer = TTestByteWriter.Create;
    try
      PostHeader(Writer, Fixed30);
      Writer.U32(0);
      const Post = LoadPost(Host, Writer.ToBytes);

      var Name: string;
      Assert.IsFalse(Post.HasGlyphNames);
      Assert.IsFalse(Post.TryGetName(1, Name));
      Assert.AreEqual<Integer>(0, Post.GlyphNameCount);
    finally
      Writer.Free;
    end;
  finally
    Host.Free;
  end;
end;

procedure TTrueTypePostTests.TestTableWithoutNameDataLogsAndHasNoNames;
begin
  const Warnings = TList<string>.Create;
  const Log = TPdfLog.Create(
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      Warnings.Add(Message);
    end);
  const Host = TTestTableHost.Create(5);
  try
    Host.Log := Log;
    const Writer = TTestByteWriter.Create;
    try
      const Post = LoadPost(Host, PostHeader(Writer, Fixed20).ToBytes);

      var Name: string;
      Assert.IsFalse(Post.HasGlyphNames);
      Assert.IsFalse(Post.TryGetName(0, Name));
      Assert.AreEqual<Integer>(1, Warnings.Count);
    finally
      Writer.Free;
    end;
  finally
    Host.Free;
    Log.Free;
    Warnings.Free;
  end;
end;

procedure TTrueTypePostTests.TestHeaderFields;
begin
  const Host = TTestTableHost.Create(5);
  try
    const Writer = TTestByteWriter.Create;
    try
      PostHeader(Writer, Fixed30);
      Writer.U32(0);
      const Post = LoadPost(Host, Writer.ToBytes);

      Assert.AreEqual(Double(3), Double(Post.FormatType));
      Assert.AreEqual<Integer>(-100, Integer(Post.UnderlinePosition));
      Assert.AreEqual<Integer>(50, Integer(Post.UnderlineThickness));
      Assert.AreEqual<Int64>(1, Post.IsFixedPitch);
      Assert.AreEqual<Int64>(2, Post.MinMemType42);
      Assert.AreEqual<Int64>(5, Post.MaxMemType1);
    finally
      Writer.Free;
    end;
  finally
    Host.Free;
  end;
end;

end.
