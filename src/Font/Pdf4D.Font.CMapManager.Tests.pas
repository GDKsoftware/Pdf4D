// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
unit Pdf4D.Font.CMapManager.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  DUnitX.TestFramework,
  Pdf4D.FontBox.CMap,
  Pdf4D.Font.CMapManager;

type
  // Asks for the shared CMap as soon as all threads are ready
  TCMapThread = class(TThread)
  private
    FStart: TObject;
    FResult: TCMap;
    FFailure: string;

  protected
    procedure Execute; override;

  public
    constructor Create(const Start: TObject);

    property Result: TCMap read FResult;
    property Failure: string read FFailure;
  end;

  [TestFixture]
  TCMapManagerTests = class
  private
    function ParseText(const Text: string): TCMap;
    function UnicodeOf(const CMap: TCMap; const Code: Integer): string;

  public
    [Test]
    procedure TestToUnicodeBfCharAndBfRange;

    [Test]
    procedure TestBfRangeWithArray;

    [Test]
    procedure TestBfRangeCarriesOverTheLastByteOfTheTarget;

    [Test]
    procedure TestTwoByteCodespace;

    [Test]
    procedure TestIdentityH;

    [Test]
    procedure TestIdentityVHasVerticalWritingMode;

    [Test]
    procedure TestPredefinedUsecmap;

    [Test]
    procedure TestAdobeJapan1Ucs2;

    [Test]
    procedure TestUnknownPredefinedReturnsFalse;

    [Test]
    procedure TestOnlyExactPredefinedNamesAreAccepted;

    [Test]
    procedure TestPredefinedCMapIsShared;

    [Test]
    procedure TestPredefinedCMapConcurrentFirstUse;
  end;

implementation

uses
  System.SyncObjs,
  Pdf4D.IO.RandomAccessRead;

type
  TStartSignal = class
  public
    Gate: TEvent;

    constructor Create;
    destructor Destroy; override;
  end;

function Bytes(const Values: array of Byte): TBytes;
begin
  SetLength(Result, Length(Values));
  for var Index := 0 to High(Values) do
  begin
    Result[Index] := Values[Index];
  end;
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

{ TCMapThread }

constructor TCMapThread.Create(const Start: TObject);
begin
  inherited Create(False);
  FStart := Start;
end;

procedure TCMapThread.Execute;
begin
  try
    TStartSignal(FStart).Gate.WaitFor(INFINITE);
    if not TCMapManager.TryGetPredefinedCMap('UniGB-UCS2-H', FResult) then
    begin
      FFailure := 'The predefined CMap was not found';
    end;
  except
    on Error: Exception do
    begin
      FFailure := Error.Message;
    end;
  end;
end;

{ TCMapManagerTests }

function TCMapManagerTests.ParseText(const Text: string): TCMap;
begin
  const Source = TRandomAccessRead.FromBytes(TEncoding.ASCII.GetBytes(Text));
  try
    Result := TCMapManager.ParseCMap(Source);
  finally
    Source.Free;
  end;
end;

function TCMapManagerTests.UnicodeOf(const CMap: TCMap; const Code: Integer): string;
begin
  if not CMap.TryToUnicode(Code, Result) then
  begin
    Result := '<none>';
  end;
end;

procedure TCMapManagerTests.TestToUnicodeBfCharAndBfRange;
begin
  const CMap = ParseText('1 begincodespacerange <00> <FF> endcodespacerange ' +
                         '2 beginbfchar <01> <0041> <02> <FB01> endbfchar ' +
                         '1 beginbfrange <10> <12> <0061> endbfrange');
  try
    Assert.AreEqual('A', UnicodeOf(CMap, 1));
    Assert.AreEqual(#$FB01, UnicodeOf(CMap, 2));
    Assert.AreEqual('b', UnicodeOf(CMap, $11));
    Assert.AreEqual('<none>', UnicodeOf(CMap, $13));
  finally
    CMap.Free;
  end;
end;

procedure TCMapManagerTests.TestBfRangeCarriesOverTheLastByteOfTheTarget;
begin
  // From PDFBOX-5350: <3104> maps to <BFD0>, so <31E0> is <BFD0> plus 220 = <C0AC>
  const CMap = ParseText('1 begincodespacerange <0000> <FFFF> endcodespacerange 1 beginbfrange <3104> <31F5> <BFD0> endbfrange');
  try
    Assert.AreEqual(#$BFD0, UnicodeOf(CMap, $3104));
    Assert.AreEqual(#$C000, UnicodeOf(CMap, $3134));
    Assert.AreEqual(#$C0AC, UnicodeOf(CMap, $31E0));
  finally
    CMap.Free;
  end;
end;

procedure TCMapManagerTests.TestBfRangeWithArray;
begin
  const CMap = ParseText('1 begincodespacerange <00> <FF> endcodespacerange ' +
                         '1 beginbfrange <20> <21> [<0058> <0059>] endbfrange');
  try
    Assert.AreEqual('X', UnicodeOf(CMap, $20));
    Assert.AreEqual('Y', UnicodeOf(CMap, $21));
  finally
    CMap.Free;
  end;
end;

procedure TCMapManagerTests.TestTwoByteCodespace;
begin
  const CMap = ParseText('1 begincodespacerange <0000> <FFFF> endcodespacerange');
  try
    var Position := 0;

    const Code = CMap.ReadCode(Bytes([$01, $02]), Position);

    Assert.AreEqual($0102, Code);
    Assert.AreEqual(2, Position);
  finally
    CMap.Free;
  end;
end;

procedure TCMapManagerTests.TestIdentityH;
begin
  var CMap: TCMap;
  Assert.IsTrue(TCMapManager.TryGetPredefinedCMap('Identity-H', CMap));

  var Position := 0;
  Assert.AreEqual(65, CMap.ReadCode(Bytes([$00, $41]), Position));
  Assert.AreEqual(2, Position);
  Assert.AreEqual(65, CMap.ToCID(65));
  Assert.AreEqual(0, CMap.WMode);
end;

procedure TCMapManagerTests.TestIdentityVHasVerticalWritingMode;
begin
  var CMap: TCMap;
  Assert.IsTrue(TCMapManager.TryGetPredefinedCMap('Identity-V', CMap));

  Assert.AreEqual(1, CMap.WMode);
  Assert.AreEqual(65, CMap.ToCID(65), 'Identity-V uses the mappings of Identity-H');
end;

procedure TCMapManagerTests.TestPredefinedUsecmap;
begin
  var Base: TCMap;
  var Derived: TCMap;
  Assert.IsTrue(TCMapManager.TryGetPredefinedCMap('UniJIS-UCS2-H', Base));
  Assert.IsTrue(TCMapManager.TryGetPredefinedCMap('UniJIS-UCS2-HW-H', Derived));

  Assert.AreEqual('UniJIS-UCS2-HW-H', Derived.Name);
  Assert.IsTrue(Derived.HasCIDMappings);
  Assert.AreEqual(Base.ToCID(Bytes([$30, $42])), Derived.ToCID(Bytes([$30, $42])), 'hiragana comes from UniJIS-UCS2-H');
  Assert.AreNotEqual(0, Derived.ToCID(Bytes([$30, $42])));
  Assert.AreEqual(Base.ToCID(Bytes([$00, $41])), Derived.ToCID(Bytes([$00, $41])));

  var Position := 0;
  Assert.AreEqual($3042, Derived.ReadCode(Bytes([$30, $42]), Position), 'the codespace ranges are copied as well');
  Assert.AreEqual(2, Position);
end;

procedure TCMapManagerTests.TestAdobeJapan1Ucs2;
begin
  var CMap: TCMap;
  Assert.IsTrue(TCMapManager.TryGetPredefinedCMap('Adobe-Japan1-UCS2', CMap));

  Assert.AreEqual(#$3042, UnicodeOf(CMap, 843));
end;

procedure TCMapManagerTests.TestUnknownPredefinedReturnsFalse;
begin
  var CMap: TCMap;

  Assert.IsFalse(TCMapManager.TryGetPredefinedCMap('No-Such-CMap', CMap));
  Assert.IsFalse(TCMapManager.TryGetPredefinedCMap('', CMap));
  Assert.IsFalse(TCMapManager.TryGetPredefinedCMap('../Identity-H/..', CMap));
end;

procedure TCMapManagerTests.TestOnlyExactPredefinedNamesAreAccepted;
begin
  var CMap: TCMap;
  var Exact: TCMap;

  Assert.IsTrue(TCMapManager.TryGetPredefinedCMap('Identity-H', Exact));
  Assert.IsFalse(TCMapManager.TryGetPredefinedCMap('identity-h', CMap));
  Assert.IsNull(CMap);
  Assert.IsFalse(TCMapManager.TryGetPredefinedCMap('IDENTITY-H', CMap));
  Assert.IsFalse(TCMapManager.TryGetPredefinedCMap('Identity+H', CMap));
  Assert.IsFalse(TCMapManager.TryGetPredefinedCMap('Identity_H', CMap));
  Assert.IsFalse(TCMapManager.TryGetPredefinedCMap('UniJIS.UCS2.H', CMap));

  // The exact name still gives the one shared CMap
  Assert.IsTrue(TCMapManager.TryGetPredefinedCMap('Identity-H', CMap));
  Assert.AreSame(Exact, CMap);
end;

procedure TCMapManagerTests.TestPredefinedCMapIsShared;
begin
  var First: TCMap;
  var Second: TCMap;
  Assert.IsTrue(TCMapManager.TryGetPredefinedCMap('UniKS-UCS2-H', First));
  Assert.IsTrue(TCMapManager.TryGetPredefinedCMap('UniKS-UCS2-H', Second));

  Assert.AreSame(First, Second);
end;

procedure TCMapManagerTests.TestPredefinedCMapConcurrentFirstUse;
begin
  const ThreadCount = 8;
  const Signal = TStartSignal.Create;
  try
    var Threads: TArray<TCMapThread>;
    SetLength(Threads, ThreadCount);
    for var Index := 0 to ThreadCount - 1 do
    begin
      Threads[Index] := TCMapThread.Create(Signal);
    end;

    Signal.Gate.SetEvent;
    for var Thread in Threads do
    begin
      Thread.WaitFor;
    end;

    try
      var Expected: TCMap;
      Assert.IsTrue(TCMapManager.TryGetPredefinedCMap('UniGB-UCS2-H', Expected));
      for var Thread in Threads do
      begin
        Assert.AreEqual('', Thread.Failure);
        Assert.AreSame(Expected, Thread.Result);
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
