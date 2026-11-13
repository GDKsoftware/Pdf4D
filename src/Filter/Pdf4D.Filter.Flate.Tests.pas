unit Pdf4D.Filter.Flate.Tests;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework;

type
  [TestFixture]
  TFlateFilterTests = class
  private
    function SampleText(const Length: Integer): TBytes;

  public
    [Test]
    procedure TestFlateRoundTrip;

    [Test]
    procedure TestFlateTruncatedKeepsDecodedPrefix;

    [Test]
    procedure TestFlateBombRaisesLimitExceeded;

    [Test]
    procedure TestFlateDataErrorIsLoggedAndGivesNoException;

    [Test]
    procedure TestFlateAppliesPngPredictorFromDecodeParms;

    [Test]
    procedure TestFlateLargeOutputIsComplete;
  end;

implementation

uses
  System.Classes,
  System.ZLib,
  Pdf4D.Common.Defines,
  Pdf4D.Common.Log,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Name,
  Pdf4D.Filter.Tests.Support;

{ TFlateFilterTests }

// Text with enough variation that it does not shrink to a few bytes
function TFlateFilterTests.SampleText(const Length: Integer): TBytes;
begin
  SetLength(Result, Length);
  var Seed: Cardinal := 12345;
  for var Index := 0 to Length - 1 do
  begin
    Seed := Cardinal((UInt64(Seed) * 1103515245 + 12345) and $FFFFFFFF);
    Result[Index] := Byte(Ord('a') + ((Seed shr 16) mod 26));
  end;
end;

procedure TFlateFilterTests.TestFlateRoundTrip;
begin
  const Compressed = TFilterTestSupport.Compress(TFilterTestSupport.AsciiBytes('Hello'));

  Assert.AreEqual('Hello', TFilterTestSupport.AsciiString(TFilterTestSupport.Decode('FlateDecode', Compressed)));
  Assert.AreEqual('Hello', TFilterTestSupport.AsciiString(TFilterTestSupport.Decode('Fl', Compressed)));
end;

procedure TFlateFilterTests.TestFlateTruncatedKeepsDecodedPrefix;
begin
  const Original = SampleText(10 * 1024);
  var Compressed := TFilterTestSupport.Compress(Original);
  SetLength(Compressed, Length(Compressed) div 2);

  const Decoded = TFilterTestSupport.Decode('FlateDecode', Compressed);

  Assert.IsTrue(Length(Decoded) > 0, 'the decoded prefix is not empty');
  Assert.IsTrue(Length(Decoded) < Length(Original));
  Assert.IsTrue(CompareMem(@Decoded[0], @Original[0], Length(Decoded)), 'the output is a prefix of the original');
end;

procedure TFlateFilterTests.TestFlateBombRaisesLimitExceeded;
begin
  const Output = TBytesStream.Create;
  try
    const Compressor = TZCompressionStream.Create(Output);
    try
      var Block: TBytes;
      SetLength(Block, 1024 * 1024);
      for var Count := 1 to 64 do
      begin
        Compressor.WriteBuffer(Block[0], Length(Block));
      end;
    finally
      Compressor.Free;
    end;
    const Compressed = Copy(Output.Bytes, 0, Output.Size);

    Assert.WillRaise(
      procedure
      begin
        TFilterTestSupport.Decode('FlateDecode', Compressed, nil, nil, 1024 * 1024);
      end,
      EPdfLimitExceededException);

    Assert.AreEqual<Integer>(64 * 1024 * 1024, Length(TFilterTestSupport.Decode('FlateDecode', Compressed, nil, nil, 64 * 1024 * 1024)));
  finally
    Output.Free;
  end;
end;

procedure TFlateFilterTests.TestFlateDataErrorIsLoggedAndGivesNoException;
begin
  var Lines := 0;
  const Log = TPdfLog.Create(
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      Inc(Lines);
    end);
  try
    const Garbage: TBytes = [$78, $9C, $FF, $FF, $FF, $FF, $FF, $FF];

    Assert.AreEqual<Integer>(0, Length(TFilterTestSupport.Decode('FlateDecode', Garbage, nil, Log)));
    Assert.AreEqual(1, Lines);
  finally
    Log.Free;
  end;
end;

procedure TFlateFilterTests.TestFlateAppliesPngPredictorFromDecodeParms;
begin
  const Parameters = TCosDictionary.Create;
  try
    const DecodeParms = TCosDictionary.Create;
    DecodeParms.SetItem('Predictor', TCosInteger.Create(12));
    DecodeParms.SetItem('Columns', TCosInteger.Create(4));
    Parameters.SetItem('DecodeParms', DecodeParms);
    // DecodeParms is only used together with /Filter
    Parameters.SetItem('Filter', TCosName.Create('FlateDecode'));

    const Rows: TBytes = [2, 1, 2, 3, 4, 2, 1, 1, 1, 1];
    const Decoded = TFilterTestSupport.Decode('FlateDecode', TFilterTestSupport.Compress(Rows), Parameters);

    Assert.AreEqual('0102030402030405', TFilterTestSupport.ToHex(Decoded));
  finally
    Parameters.Free;
  end;
end;

procedure TFlateFilterTests.TestFlateLargeOutputIsComplete;
begin
  const Original = SampleText(500 * 1024);

  const Decoded = TFilterTestSupport.Decode('FlateDecode', TFilterTestSupport.Compress(Original));

  Assert.IsTrue((Length(Decoded) = Length(Original)) and CompareMem(@Decoded[0], @Original[0], Length(Decoded)));
end;

end.
