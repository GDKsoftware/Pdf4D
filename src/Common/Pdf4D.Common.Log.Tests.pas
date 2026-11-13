unit Pdf4D.Common.Log.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPdfLogTests = class
  public
    [Test]
    procedure TestLogForwardsLevelAndFormattedMessage;

    [Test]
    procedure TestNilCallbackIsIgnored;

    [Test]
    procedure TestDefaultOptions;
  end;

implementation

uses
  System.SysUtils,
  Pdf4D.Common.Defines,
  Pdf4D.Common.Log;

{ TPdfLogTests }

procedure TPdfLogTests.TestLogForwardsLevelAndFormattedMessage;
begin
  var ReceivedLevel := TPdfLogLevel.Debug;
  var ReceivedMessage := '';
  const Log = TPdfLog.Create(
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      ReceivedLevel := Level;
      ReceivedMessage := Message;
    end);
  try
    Log.Warning('Object %d missing', [12]);

    Assert.AreEqual<TPdfLogLevel>(TPdfLogLevel.Warning, ReceivedLevel);
    Assert.AreEqual('Object 12 missing', ReceivedMessage);
  finally
    Log.Free;
  end;
end;

procedure TPdfLogTests.TestNilCallbackIsIgnored;
begin
  const Log = TPdfLog.Create(nil);
  try
    Assert.WillNotRaise(
      procedure
      begin
        Log.Error('Nobody listens');
        Log.Info('Object %d', [1]);
      end);
  finally
    Log.Free;
  end;
end;

procedure TPdfLogTests.TestDefaultOptions;
begin
  const Options = TPdfLoadOptions.Default;

  Assert.AreEqual<Int64>(256 * 1024 * 1024, Options.MaxDecodedStreamSize);
  Assert.AreEqual(500, Options.MaxNestingDepth);
  Assert.AreEqual('', Options.Password);
  Assert.IsFalse(Assigned(Options.OnLog));
end;

end.
