// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Filter.LZW.Tests;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework;

type
  [TestFixture]
  TLZWFilterTests = class
  private
    function SampleData(const Length: Integer): TBytes;
    function Encode(const Data: TBytes; const EarlyChange: Boolean): TBytes;
    function Decode(const Compressed: TBytes; const EarlyChange: Integer): TBytes;
    procedure AssertRoundTrip(const Data: TBytes; const EarlyChange: Boolean);

  public
    [Test]
    procedure TestLzwSpecificationExample;

    [Test]
    procedure TestLzwEarlyChange;

    [Test]
    procedure TestLzwWithoutEndOfDataKeepsDecodedData;

    [Test]
    procedure TestLzwInvalidCodeIsLoggedAndEndsTheData;

    [Test]
    procedure TestLzwAppliesPredictor;

    [Test]
    procedure TestLzwExpansionRaisesLimitExceeded;
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  Pdf4D.Common.Defines,
  Pdf4D.Common.Log,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Name,
  Pdf4D.Filter.Tests.Support;

type
  // The encoder of LZWFilter.encode, with a choice for the early change
  TLzwTestEncoder = class
  private
    FOutput: TBytesStream;
    FBitBuffer: Cardinal;
    FBitCount: Integer;
    FTable: TList<TBytes>;
    FEarlyChange: Boolean;

    procedure WriteBits(const Code, Count: Integer);
    procedure ResetTable;
    function FindCode(const Pattern: TBytes): Integer;
    function Chunk(const TableSize: Integer): Integer;

  public
    constructor Create(const EarlyChange: Boolean);
    destructor Destroy; override;

    function Encode(const Data: TBytes): TBytes;
  end;

{ TLzwTestEncoder }

constructor TLzwTestEncoder.Create(const EarlyChange: Boolean);
begin
  inherited Create;
  FEarlyChange := EarlyChange;
  FOutput := TBytesStream.Create;
  FTable := TList<TBytes>.Create;
end;

destructor TLzwTestEncoder.Destroy;
begin
  FTable.Free;
  FOutput.Free;
  inherited;
end;

procedure TLzwTestEncoder.ResetTable;
begin
  FTable.Clear;
  for var Value := 0 to 255 do
  begin
    FTable.Add([Byte(Value)]);
  end;
  FTable.Add(nil);
  FTable.Add(nil);
end;

procedure TLzwTestEncoder.WriteBits(const Code, Count: Integer);
begin
  FBitBuffer := (FBitBuffer shl Count) or Cardinal(Code);
  Inc(FBitCount, Count);
  while FBitCount >= 8 do
  begin
    Dec(FBitCount, 8);
    const Value = Byte((FBitBuffer shr FBitCount) and $FF);
    FOutput.WriteBuffer(Value, 1);
  end;
  FBitBuffer := FBitBuffer and ((Cardinal(1) shl FBitCount) - 1);
end;

function TLzwTestEncoder.Chunk(const TableSize: Integer): Integer;
begin
  var Size := TableSize;
  if FEarlyChange then
  begin
    Inc(Size);
  end;

  if Size >= 2048 then
  begin
    Result := 12;
  end
  else if Size >= 1024 then
  begin
    Result := 11;
  end
  else if Size >= 512 then
  begin
    Result := 10;
  end
  else
  begin
    Result := 9;
  end;
end;

function TLzwTestEncoder.FindCode(const Pattern: TBytes): Integer;
begin
  if Length(Pattern) = 1 then
  begin
    Exit(Pattern[0]);
  end;

  for var Code := 258 to FTable.Count - 1 do
  begin
    const Entry = FTable[Code];
    if (Length(Entry) = Length(Pattern)) and CompareMem(@Entry[0], @Pattern[0], Length(Pattern)) then
    begin
      Exit(Code);
    end;
  end;
  Result := -1;
end;

function TLzwTestEncoder.Encode(const Data: TBytes): TBytes;
begin
  ResetTable;
  WriteBits(256, 9);
  var Pattern: TBytes := nil;
  var FoundCode := -1;
  for var Value in Data do
  begin
    if Length(Pattern) = 0 then
    begin
      Pattern := [Value];
      FoundCode := Value;
      Continue;
    end;

    Pattern := Pattern + [Value];
    const NewCode = FindCode(Pattern);
    if NewCode = -1 then
    begin
      WriteBits(FoundCode, Chunk(FTable.Count - 1));
      FTable.Add(Pattern);
      if FTable.Count = 4096 then
      begin
        WriteBits(256, Chunk(FTable.Count - 1));
        ResetTable;
      end;
      Pattern := [Value];
      FoundCode := Value;
    end
    else
    begin
      FoundCode := NewCode;
    end;
  end;

  if FoundCode <> -1 then
  begin
    WriteBits(FoundCode, Chunk(FTable.Count - 1));
  end;
  WriteBits(257, Chunk(FTable.Count));
  WriteBits(0, 7);
  Result := Copy(FOutput.Bytes, 0, FOutput.Size);
end;

{ TLZWFilterTests }

// A few symbols, so that the same patterns come back and the table fills up
function TLZWFilterTests.SampleData(const Length: Integer): TBytes;
begin
  SetLength(Result, Length);
  var Seed: Cardinal := 987;
  for var Index := 0 to Length - 1 do
  begin
    Seed := Cardinal((UInt64(Seed) * 1103515245 + 12345) and $FFFFFFFF);
    Result[Index] := Byte(Ord('a') + ((Seed shr 16) mod 6));
  end;
end;

function TLZWFilterTests.Encode(const Data: TBytes; const EarlyChange: Boolean): TBytes;
begin
  const Encoder = TLzwTestEncoder.Create(EarlyChange);
  try
    Result := Encoder.Encode(Data);
  finally
    Encoder.Free;
  end;
end;

function TLZWFilterTests.Decode(const Compressed: TBytes; const EarlyChange: Integer): TBytes;
begin
  const Parameters = TCosDictionary.Create;
  try
    const DecodeParms = TCosDictionary.Create;
    DecodeParms.SetItem('EarlyChange', TCosInteger.Create(EarlyChange));
    Parameters.SetItem('DecodeParms', DecodeParms);
    Parameters.SetItem('Filter', TCosName.Create('LZWDecode'));

    Result := TFilterTestSupport.Decode('LZWDecode', Compressed, Parameters);
  finally
    Parameters.Free;
  end;
end;

procedure TLZWFilterTests.AssertRoundTrip(const Data: TBytes; const EarlyChange: Boolean);
begin
  var Flag := 0;
  if EarlyChange then
  begin
    Flag := 1;
  end;

  const Decoded = Decode(Encode(Data, EarlyChange), Flag);

  Assert.AreEqual(Length(Data), Length(Decoded));
  Assert.AreEqual(TFilterTestSupport.ToHex(Data), TFilterTestSupport.ToHex(Decoded));
end;

procedure TLZWFilterTests.TestLzwSpecificationExample;
begin
  // ISO 32000-1, 7.4.4.2: 45 45 45 45 45 65 45 45 45 66
  const Compressed: TBytes = [$80, $0B, $60, $50, $22, $0C, $0C, $85, $01];

  Assert.AreEqual('2D2D2D2D2D412D2D2D42', TFilterTestSupport.ToHex(TFilterTestSupport.Decode('LZWDecode', Compressed)));
  Assert.AreEqual('2D2D2D2D2D412D2D2D42', TFilterTestSupport.ToHex(TFilterTestSupport.Decode('LZW', Compressed)));
end;

procedure TLZWFilterTests.TestLzwEarlyChange;
begin
  // Long enough for the code length to grow to 10, 11 and 12 bits and for the table to be cleared
  AssertRoundTrip(SampleData(40000), True);
  AssertRoundTrip(SampleData(40000), False);
  AssertRoundTrip(SampleData(3000), True);
  AssertRoundTrip(SampleData(3000), False);
  AssertRoundTrip(nil, True);
  AssertRoundTrip([65], False);
end;

procedure TLZWFilterTests.TestLzwWithoutEndOfDataKeepsDecodedData;
begin
  var Lines := 0;
  const Log = TPdfLog.Create(
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      Inc(Lines);
    end);
  try
    // The example without its last bytes
    const Compressed: TBytes = [$80, $0B, $60, $50, $22, $0C, $0C];

    const Decoded = TFilterTestSupport.Decode('LZWDecode', Compressed, nil, Log);

    Assert.IsTrue(Length(Decoded) >= 6);
    Assert.AreEqual('2D2D2D2D2D41', Copy(TFilterTestSupport.ToHex(Decoded), 1, 12));
    Assert.AreEqual(1, Lines);
  finally
    Log.Free;
  end;
end;

procedure TLZWFilterTests.TestLzwInvalidCodeIsLoggedAndEndsTheData;
begin
  var Lines := 0;
  const Log = TPdfLog.Create(
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      Inc(Lines);
    end);
  try
    // Code 300 straight after the start: there is no entry for it
    const Compressed: TBytes = [$96, $00, $00];

    Assert.AreEqual<Integer>(0, Length(TFilterTestSupport.Decode('LZWDecode', Compressed, nil, Log)));
    Assert.AreEqual(1, Lines);
  finally
    Log.Free;
  end;
end;

procedure TLZWFilterTests.TestLzwAppliesPredictor;
begin
  const Parameters = TCosDictionary.Create;
  try
    const DecodeParms = TCosDictionary.Create;
    DecodeParms.SetItem('Predictor', TCosInteger.Create(12));
    DecodeParms.SetItem('Columns', TCosInteger.Create(3));
    Parameters.SetItem('DecodeParms', DecodeParms);
    Parameters.SetItem('Filter', TCosName.Create('LZWDecode'));

    const Rows: TBytes = [2, 1, 2, 3, 2, 1, 1, 1];
    const Decoded = TFilterTestSupport.Decode('LZWDecode', Encode(Rows, True), Parameters);

    Assert.AreEqual('010203020304', TFilterTestSupport.ToHex(Decoded));
  finally
    Parameters.Free;
  end;
end;

procedure TLZWFilterTests.TestLzwExpansionRaisesLimitExceeded;
begin
  var Data: TBytes;
  SetLength(Data, 100000);
  FillChar(Data[0], Length(Data), Ord('a'));
  const Compressed = Encode(Data, True);

  Assert.WillRaise(
    procedure
    begin
      TFilterTestSupport.Decode('LZWDecode', Compressed, nil, nil, 1000);
    end,
    EPdfLimitExceededException);
  Assert.AreEqual<Integer>(Length(Data), Length(TFilterTestSupport.Decode('LZWDecode', Compressed, nil, nil, Length(Data))));
end;

end.