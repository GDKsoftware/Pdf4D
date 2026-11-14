// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Font.GlyphList.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Common.Defines,
  Pdf4D.Common.Log,
  Pdf4D.Font.GlyphList;

type
  // Asks for the shared list as soon as all threads are ready
  TGlyphListThread = class(TThread)
  private
    FStart: TObject;
    FResult: TGlyphList;
    FFailure: string;

  protected
    procedure Execute; override;

  public
    constructor Create(const Start: TObject);

    property Result: TGlyphList read FResult;
    property Failure: string read FFailure;
  end;

  [TestFixture]
  TGlyphListTests = class
  private
    FMessages: TList<string>;
    FLog: TPdfLog;

    function Unicode(const List: TGlyphList; const Name: string): string;
    function IsFound(const List: TGlyphList; const Name: string): Boolean;
    procedure CreateWithoutSemicolon;
    procedure CreateWithBadHex;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestGlyphListBasics;

    [Test]
    procedure TestEntryCounts;

    [Test]
    procedure TestUniNameWithDisallowedAreaWarns;

    [Test]
    procedure TestUniNameWithoutNumberWarns;

    [Test]
    procedure TestUniNameWithSuffix;

    [Test]
    procedure TestNameWithSuffixOfUnknownGlyph;

    [Test]
    procedure TestLeadingDotIsNotASuffix;

    [Test]
    procedure TestMultiCodePointEntry;

    [Test]
    procedure TestEmptyNameAndLogMayBeNil;

    [Test]
    procedure TestZapfDingbatsList;

    [Test]
    procedure TestTextExtractionListHasAdditional;

    [Test]
    procedure TestAdobeListHasNoAdditionalNames;

    [Test]
    procedure TestReverseMappingPrefersStandardEncodings;

    [Test]
    procedure TestCodePointToNameOutsideRange;

    [Test]
    procedure TestSequenceToName;

    [Test]
    procedure TestInvalidEntryRaises;

    [Test]
    procedure TestSharedListsAreTheSame;

    [Test]
    procedure TestGlyphListConcurrentFirstUse;
  end;

implementation

uses
  System.SyncObjs;

type
  TStartSignal = class
  public
    Gate: TEvent;

    constructor Create;
    destructor Destroy; override;
  end;

{ TStartSignal }

constructor TStartSignal.Create;
begin
  inherited Create;
  Gate := TEvent.Create(nil, True, False, '');
end;

destructor TStartSignal.Destroy;
begin
  Gate.Free;
  inherited;
end;

{ TGlyphListThread }

constructor TGlyphListThread.Create(const Start: TObject);
begin
  inherited Create(False);
  FStart := Start;
end;

procedure TGlyphListThread.Execute;
begin
  try
    TStartSignal(FStart).Gate.WaitFor(INFINITE);
    FResult := TGlyphList.AdobeGlyphList;
  except
    on Error: Exception do
    begin
      FFailure := Error.Message;
    end;
  end;
end;

{ TGlyphListTests }

procedure TGlyphListTests.Setup;
begin
  FMessages := TList<string>.Create;
  FLog := TPdfLog.Create(
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      FMessages.Add(Message);
    end);
end;

procedure TGlyphListTests.TearDown;
begin
  FLog.Free;
  FMessages.Free;
end;

function TGlyphListTests.Unicode(const List: TGlyphList; const Name: string): string;
begin
  Assert.IsTrue(List.TryToUnicode(Name, FLog, Result), Name);
end;

function TGlyphListTests.IsFound(const List: TGlyphList; const Name: string): Boolean;
begin
  var Value: string;
  Result := List.TryToUnicode(Name, FLog, Value);
end;

procedure TGlyphListTests.CreateWithoutSemicolon;
begin
  TGlyphList.Create(TEncoding.ASCII.GetBytes('nosemicolon')).Free;
end;

procedure TGlyphListTests.CreateWithBadHex;
begin
  TGlyphList.Create(TEncoding.ASCII.GetBytes('a;00ZZ')).Free;
end;

procedure TGlyphListTests.TestGlyphListBasics;begin
  const List = TGlyphList.AdobeGlyphList;
  Assert.AreEqual('A', Unicode(List, 'A'));
  Assert.AreEqual(#$FB01, Unicode(List, 'fi'));
  Assert.AreEqual(#$20AC, Unicode(List, 'Euro'));
  Assert.AreEqual('A', Unicode(List, 'uni0041'));
  Assert.AreEqual('A', Unicode(List, 'u0041'));
  Assert.AreEqual('a', Unicode(List, 'a.sc'));
  Assert.IsFalse(IsFound(List, 'g123'));
  Assert.AreEqual<Integer>(0, FMessages.Count);

  Assert.IsFalse(IsFound(List, 'uniD800'));
  Assert.AreEqual<Integer>(1, FMessages.Count);
end;

procedure TGlyphListTests.TestEntryCounts;
begin
  Assert.AreEqual<Integer>(4281, TGlyphList.AdobeGlyphList.Count);
  Assert.AreEqual<Integer>(202, TGlyphList.ZapfDingbats.Count);
end;

procedure TGlyphListTests.TestUniNameWithDisallowedAreaWarns;
begin
  const List = TGlyphList.AdobeGlyphList;
  Assert.IsFalse(IsFound(List, 'uniD800'));
  Assert.IsFalse(IsFound(List, 'uDFFF'));
  Assert.AreEqual<Integer>(2, FMessages.Count);
  Assert.Contains(FMessages[0], 'disallowed code area');
  Assert.IsTrue(IsFound(List, 'uniD7FF'));
  Assert.IsTrue(IsFound(List, 'uniE000'));
  Assert.AreEqual<Integer>(2, FMessages.Count);
end;

procedure TGlyphListTests.TestUniNameWithoutNumberWarns;
begin
  Assert.IsFalse(IsFound(TGlyphList.AdobeGlyphList, 'uniXYZW'));
  Assert.AreEqual<Integer>(1, FMessages.Count);
  Assert.Contains(FMessages[0], 'Not a number');
end;

procedure TGlyphListTests.TestUniNameWithSuffix;
begin
  Assert.AreEqual('A', Unicode(TGlyphList.AdobeGlyphList, 'uni0041.alt'));
  Assert.AreEqual(#$FB01, Unicode(TGlyphList.AdobeGlyphList, 'fi.small.alt'));
end;

procedure TGlyphListTests.TestNameWithSuffixOfUnknownGlyph;
begin
  Assert.IsFalse(IsFound(TGlyphList.AdobeGlyphList, 'g123.alt'));
end;

procedure TGlyphListTests.TestLeadingDotIsNotASuffix;
begin
  Assert.IsFalse(IsFound(TGlyphList.AdobeGlyphList, '.notdef'));
  Assert.IsFalse(IsFound(TGlyphList.AdobeGlyphList, '.A'));
end;

procedure TGlyphListTests.TestMultiCodePointEntry;
begin
  // The glyph list has entries that are more than one character, for example Hebrew letters with a vowel point
  const List = TGlyphList.AdobeGlyphList;
  const Value = Unicode(List, 'dalethatafpatahhebrew');
  Assert.AreEqual<Integer>(2, Length(Value));
  Assert.AreNotEqual('.notdef', List.SequenceToName(Value));
end;

procedure TGlyphListTests.TestEmptyNameAndLogMayBeNil;
begin
  var Value: string;
  Assert.IsFalse(TGlyphList.AdobeGlyphList.TryToUnicode('', Value));
  Assert.IsFalse(TGlyphList.AdobeGlyphList.TryToUnicode('uniD800', Value));
  Assert.IsTrue(TGlyphList.AdobeGlyphList.TryToUnicode('uni0041', Value));
  Assert.AreEqual('A', Value);
end;

procedure TGlyphListTests.TestZapfDingbatsList;
begin
  Assert.AreEqual(#$2701, Unicode(TGlyphList.ZapfDingbats, 'a1'));
  Assert.IsFalse(IsFound(TGlyphList.ZapfDingbats, 'A'));
end;

procedure TGlyphListTests.TestTextExtractionListHasAdditional;
begin
  Assert.AreEqual(#$3008, Unicode(TGlyphList.TextExtraction, 'angbracketleft'));
  Assert.AreEqual('A', Unicode(TGlyphList.TextExtraction, 'A'));
  Assert.IsTrue(TGlyphList.TextExtraction.Count > TGlyphList.AdobeGlyphList.Count);
end;

procedure TGlyphListTests.TestAdobeListHasNoAdditionalNames;
begin
  // The Adobe list is not changed by building the text extraction list on top of it
  Assert.IsFalse(IsFound(TGlyphList.AdobeGlyphList, 'angbracketleft'));
  Assert.AreEqual<Integer>(4281, TGlyphList.AdobeGlyphList.Count);
  Assert.IsFalse(IsFound(TGlyphList.AdobeGlyphList, 'tildewide'));
end;

procedure TGlyphListTests.TestReverseMappingPrefersStandardEncodings;
begin
  const List = TGlyphList.AdobeGlyphList;
  Assert.AreEqual('asciitilde', List.CodePointToName($7E));
  Assert.AreNotEqual('tilde', List.CodePointToName($7E));
  Assert.AreEqual('A', List.CodePointToName(Ord('A')));
  Assert.AreEqual('fi', List.CodePointToName($FB01));
  // PDFBOX-3884: tilde (U+02DC) is the name of the standard encodings
  Assert.AreEqual('tilde', List.CodePointToName($02DC));
end;

procedure TGlyphListTests.TestCodePointToNameOutsideRange;
begin
  const List = TGlyphList.AdobeGlyphList;
  Assert.AreEqual('.notdef', List.CodePointToName(-1));
  Assert.AreEqual('.notdef', List.CodePointToName($110000));
  Assert.AreEqual('.notdef', List.CodePointToName($D800));
  Assert.AreEqual('.notdef', List.CodePointToName($10FFFF));
  Assert.AreEqual('.notdef', List.CodePointToName(0));
end;

procedure TGlyphListTests.TestSequenceToName;
begin
  Assert.AreEqual('fi', TGlyphList.AdobeGlyphList.SequenceToName(#$FB01));
  Assert.AreEqual('.notdef', TGlyphList.AdobeGlyphList.SequenceToName('fi'));
  Assert.AreEqual('.notdef', TGlyphList.AdobeGlyphList.SequenceToName(''));
end;

procedure TGlyphListTests.TestInvalidEntryRaises;
begin
  Assert.WillRaise(CreateWithoutSemicolon, EPdfParseException);
  Assert.WillRaise(CreateWithBadHex, EPdfParseException);


  const List = TGlyphList.Create(TEncoding.ASCII.GetBytes('# comment'#13#10'one;0031'#10'pair;0041 1F600'#13'dup;0032'#10'dup;0033'));
  try
    Assert.AreEqual<Integer>(3, List.Count);
    var Value: string;
    Assert.IsTrue(List.TryToUnicode('pair', Value));
    Assert.AreEqual<Integer>(3, Length(Value));
    Assert.IsTrue(List.TryToUnicode('dup', Value));
    Assert.AreEqual('3', Value);
  finally
    List.Free;
  end;
end;

procedure TGlyphListTests.TestSharedListsAreTheSame;
begin
  Assert.AreSame(TGlyphList.AdobeGlyphList, TGlyphList.AdobeGlyphList);
  Assert.AreSame(TGlyphList.ZapfDingbats, TGlyphList.ZapfDingbats);
  Assert.AreSame(TGlyphList.TextExtraction, TGlyphList.TextExtraction);
  Assert.AreNotSame(TGlyphList.AdobeGlyphList, TGlyphList.TextExtraction);
end;

procedure TGlyphListTests.TestGlyphListConcurrentFirstUse;
begin
  const ThreadCount = 8;
  const Signal = TStartSignal.Create;
  try
    var Threads: TArray<TGlyphListThread>;
    SetLength(Threads, ThreadCount);
    for var Index := 0 to ThreadCount - 1 do
    begin
      Threads[Index] := TGlyphListThread.Create(Signal);
    end;

    Signal.Gate.SetEvent;
    for var Thread in Threads do
    begin
      Thread.WaitFor;
    end;

    try
      for var Thread in Threads do
      begin
        Assert.AreEqual('', Thread.Failure);
        Assert.AreSame(TGlyphList.AdobeGlyphList, Thread.Result);
      end;
    finally
      for var Thread in Threads do
      begin
        Thread.Free;
      end;
    end;
  finally
    Signal.Free;
  end;
end;

end.
