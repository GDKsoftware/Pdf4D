// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/TrueTypeCollection.java (3.0.8)
unit Pdf4D.FontBox.TrueType.Collection.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework;

type
  [TestFixture]
  TTrueTypeCollectionTests = class
  private
    const LiberationSans = 'LiberationSans-Regular.ttf';
    const JosefinSans = 'JosefinSans-Italic.ttf';

  private
    class function CollectionOf(const First, Second: string): TBytes; static;
    class function HeaderWithCount(const Count: Int64): TBytes; static;

  public
    [Test]
    procedure TestCollectionOfTwoFonts;

    [Test]
    procedure TestFontsOfACollectionAreIndependentOfTheCollection;

    [Test]
    procedure TestVersion2HeaderIsAccepted;

    [Test]
    procedure TestTryGetFontByName;

    [Test]
    procedure TestTryGetFontByNameWithoutMatch;

    [Test]
    [TestCase('Zero', '0')]
    [TestCase('Above the limit', '1025')]
    [TestCase('Absurd', '2147483647')]
    [TestCase('Largest', '4294967295')]
    procedure TestCollectionWithAbsurdCount(const Count: Int64);

    [Test]
    procedure TestMissingHeaderRaises;

    [Test]
    procedure TestTruncatedHeaderRaises;

    [Test]
    procedure TestOffsetBeyondTheEndRaisesWhenTheFontIsRead;

    [Test]
    procedure TestOffsetInsideGarbageRaisesWhenTheFontIsRead;

    [Test]
    procedure TestFontIndexOutOfRangeRaises;

    [Test]
    procedure TestOpenTypeFontInACollectionUsesTheOpenTypeParser;

    [Test]
    procedure TestRepeatedOffsetsAreLookedAtOnce;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.FontBox.TrueType.Collection,
  Pdf4D.FontBox.TrueType.Font,
  Pdf4D.FontBox.OpenType,
  Pdf4D.Tests.TestFonts,
  Pdf4D.Tests.TrueTypeBuilder;

{ TTrueTypeCollectionTests }

class function TTrueTypeCollectionTests.CollectionOf(const First, Second: string): TBytes;
begin
  Result := TTrueTypeTestData.BuildCollection([TTestFonts.Bytes(First), TTestFonts.Bytes(Second)]);
end;

class function TTrueTypeCollectionTests.HeaderWithCount(const Count: Int64): TBytes;
begin
  const Writer = TTestByteWriter.Create;
  try
    Writer.U32($74746366); // ttcf
    Writer.U32($00010000);
    Writer.U32(Count);
    Writer.Zeros(64);
    Result := Writer.ToBytes;
  finally
    Writer.Free;
  end;
end;

procedure TTrueTypeCollectionTests.TestCollectionOfTwoFonts;
begin
  const Collection = TTrueTypeCollection.Create(CollectionOf(LiberationSans, LiberationSans));
  try
    Assert.AreEqual<Integer>(2, Collection.Count);

    for var Index := 0 to Collection.Count - 1 do
    begin
      const Font = Collection.FontAt(Index);
      try
        Assert.AreEqual('LiberationSans', Font.Name);
        Assert.AreEqual<Integer>(2048, Font.UnitsPerEm);
        Assert.AreEqual<Integer>(1366, Font.GetAdvanceWidth(Font.NameToGID('A')));
      finally
        Font.Free;
      end;
    end;
  finally
    Collection.Free;
  end;
end;

// The collection can go while a font of it is in use: the font holds on to the data it needs
procedure TTrueTypeCollectionTests.TestFontsOfACollectionAreIndependentOfTheCollection;
begin
  var Font: TTrueTypeFont;
  const Collection = TTrueTypeCollection.Create(CollectionOf(LiberationSans, JosefinSans));
  try
    Font := Collection.FontAt(1);
  finally
    Collection.Free;
  end;

  try
    Assert.AreNotEqual('LiberationSans', Font.Name);
    Assert.IsTrue(Font.NumberOfGlyphs > 0);
  finally
    Font.Free;
  end;
end;

procedure TTrueTypeCollectionTests.TestVersion2HeaderIsAccepted;
begin
  const Data = TTrueTypeTestData.BuildCollection([TTestFonts.Bytes(LiberationSans)], 2.0);

  const Collection = TTrueTypeCollection.Create(Data);
  try
    Assert.AreEqual<Integer>(1, Collection.Count);
    const Font = Collection.FontAt(0);
    try
      Assert.AreEqual('LiberationSans', Font.Name);
    finally
      Font.Free;
    end;
  finally
    Collection.Free;
  end;
end;

procedure TTrueTypeCollectionTests.TestTryGetFontByName;
begin
  const Collection = TTrueTypeCollection.Create(CollectionOf(JosefinSans, LiberationSans));
  try
    var Font: TTrueTypeFont;
    Assert.IsTrue(Collection.TryGetFontByName('LiberationSans', Font));
    try
      Assert.AreEqual('LiberationSans', Font.Name);
    finally
      Font.Free;
    end;
  finally
    Collection.Free;
  end;
end;

procedure TTrueTypeCollectionTests.TestTryGetFontByNameWithoutMatch;
begin
  const Collection = TTrueTypeCollection.Create(CollectionOf(LiberationSans, LiberationSans));
  try
    var Font: TTrueTypeFont;
    Assert.IsFalse(Collection.TryGetFontByName('NoSuchFont', Font));
    Assert.IsNull(Font);
  finally
    Collection.Free;
  end;
end;

procedure TTrueTypeCollectionTests.TestCollectionWithAbsurdCount(const Count: Int64);
begin
  const Data = HeaderWithCount(Count);

  Assert.WillRaise(
    procedure
    begin
      TTrueTypeCollection.Create(Data).Free;
    end,
    EPdfParseException);
end;

procedure TTrueTypeCollectionTests.TestMissingHeaderRaises;
begin
  const Data = TTestFonts.Bytes(LiberationSans);

  Assert.WillRaise(
    procedure
    begin
      TTrueTypeCollection.Create(Data).Free;
    end,
    EPdfParseException);
end;

procedure TTrueTypeCollectionTests.TestTruncatedHeaderRaises;
begin
  var Data := HeaderWithCount(3);
  SetLength(Data, 14);

  Assert.WillRaise(
    procedure
    begin
      TTrueTypeCollection.Create(Data).Free;
    end,
    EPdfParseException);
end;

procedure TTrueTypeCollectionTests.TestOffsetBeyondTheEndRaisesWhenTheFontIsRead;
begin
  const Writer = TTestByteWriter.Create;
  try
    Writer.U32($74746366);
    Writer.U32($00010000);
    Writer.U32(2);
    Writer.U32($FFFFFFF0);
    Writer.U32($7FFFFFFF);
    const Collection = TTrueTypeCollection.Create(Writer.ToBytes);
    try
      Assert.AreEqual<Integer>(2, Collection.Count);
      Assert.WillRaise(
        procedure
        begin
          Collection.FontAt(0).Free;
        end,
        EPdfParseException);
      Assert.WillRaise(
        procedure
        begin
          Collection.FontAt(1).Free;
        end,
        EPdfParseException);
    finally
      Collection.Free;
    end;
  finally
    Writer.Free;
  end;
end;

// An offset into the middle of a font gives a table directory that is not one
procedure TTrueTypeCollectionTests.TestOffsetInsideGarbageRaisesWhenTheFontIsRead;
begin
  const Font = TTestFonts.Bytes(LiberationSans);
  const Writer = TTestByteWriter.Create;
  try
    Writer.U32($74746366);
    Writer.U32($00010000);
    Writer.U32(1);
    Writer.U32(20 + 100000);
    Writer.Append(Font);
    const Collection = TTrueTypeCollection.Create(Writer.ToBytes);
    try
      Assert.WillRaise(
        procedure
        begin
          Collection.FontAt(0).Free;
        end,
        EPdfParseException);
    finally
      Collection.Free;
    end;
  finally
    Writer.Free;
  end;
end;

procedure TTrueTypeCollectionTests.TestFontIndexOutOfRangeRaises;
begin
  const Collection = TTrueTypeCollection.Create(CollectionOf(LiberationSans, LiberationSans));
  try
    Assert.WillRaise(
      procedure
      begin
        Collection.FontAt(2).Free;
      end,
      EPdfParseException);
    Assert.WillRaise(
      procedure
      begin
        Collection.FontAt(-1).Free;
      end,
      EPdfParseException);
  finally
    Collection.Free;
  end;
end;

procedure TTrueTypeCollectionTests.TestOpenTypeFontInACollectionUsesTheOpenTypeParser;
begin
  const Collection = TTrueTypeCollection.Create(TTrueTypeTestData.BuildCollection([TTestFonts.Bytes('FoglihtenNo07.otf')]));
  try
    const Font = Collection.FontAt(0);
    try
      Assert.IsTrue(Font is TOpenTypeFont, 'An OTTO font of a collection is read by the OpenType parser');
      Assert.IsTrue(Font.HasTable('CFF '));
    finally
      Font.Free;
    end;
  finally
    Collection.Free;
  end;
end;

procedure TTrueTypeCollectionTests.TestRepeatedOffsetsAreLookedAtOnce;
begin
  const Data = CollectionOf(LiberationSans, LiberationSans);
  // The second offset becomes the first one
  Move(Data[12], Data[16], 4);

  const Collection = TTrueTypeCollection.Create(Data);
  try
    var Font: TTrueTypeFont;
    Assert.IsFalse(Collection.TryGetFontByName('NoSuchFont', Font));
    Assert.IsNull(Font);
    Assert.IsTrue(Collection.TryGetFontByName('LiberationSans', Font));
    Font.Free;
  finally
    Collection.Free;
  end;
end;

end.
