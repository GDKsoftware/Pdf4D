unit Pdf4D.Filter.RunLength.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRunLengthFilterTests = class
  public
    [Test]
    procedure TestRunLength;

    [Test]
    procedure TestRunLengthStopsAtEndOfData;

    [Test]
    procedure TestRunLengthTruncatedDataKeepsWhatWasDecoded;

    [Test]
    procedure TestRunLengthLongRun;
  end;

implementation

uses
  System.SysUtils,
  Pdf4D.Filter.Tests.Support;

{ TRunLengthFilterTests }

procedure TRunLengthFilterTests.TestRunLength;
begin
  // A literal run of 3 bytes, a run of 3 times 'x' (257 - 254) and the end of data
  const Compressed: TBytes = [2, Ord('a'), Ord('b'), Ord('c'), 254, Ord('x'), 128];

  Assert.AreEqual('abcxxx', TFilterTestSupport.AsciiString(TFilterTestSupport.Decode('RunLengthDecode', Compressed)));
  Assert.AreEqual('abcxxx', TFilterTestSupport.AsciiString(TFilterTestSupport.Decode('RL', Compressed)));
end;

procedure TRunLengthFilterTests.TestRunLengthStopsAtEndOfData;
begin
  const Compressed: TBytes = [0, Ord('a'), 128, 0, Ord('b')];

  Assert.AreEqual('a', TFilterTestSupport.AsciiString(TFilterTestSupport.Decode('RL', Compressed)));
end;

procedure TRunLengthFilterTests.TestRunLengthTruncatedDataKeepsWhatWasDecoded;
begin
  const Compressed: TBytes = [255, Ord('z'), 4, Ord('a'), Ord('b')];

  Assert.AreEqual('zzab', TFilterTestSupport.AsciiString(TFilterTestSupport.Decode('RL', Compressed)));
  Assert.AreEqual('', TFilterTestSupport.AsciiString(TFilterTestSupport.Decode('RL', [200])));
end;

procedure TRunLengthFilterTests.TestRunLengthLongRun;
begin
  // 129 is the longest run: 257 - 129 = 128 bytes
  const Compressed: TBytes = [129, 7, 128];

  Assert.AreEqual<Integer>(128, Length(TFilterTestSupport.Decode('RL', Compressed)));
end;

end.
