// Licensed under the Apache License, Version 2.0; see the LICENSE file.
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
    procedure TestBadFormatStringLogsRawText;

    [Test]
    procedure TestRaisingCallbackIsContained;

    [Test]
    procedure TestNoFormatWithoutCallback;

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

procedure TPdfLogTests.TestBadFormatStringLogsRawText;
begin
  var ReceivedMessage := '';
  const Log = TPdfLog.Create(
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      ReceivedMessage := Message;
    end);
  try
    Assert.WillNotRaise(
      procedure
      begin
        Log.Warning('Broken %d and %s', ['text']);
      end);
    Assert.AreEqual('Broken %d and %s', ReceivedMessage);

    Log.Warning('Object %d of %s', [12]);
    Assert.IsTrue(ReceivedMessage.StartsWith('Object %d of %s'));

    Log.Warning('Wrong %q', [1]);
    Assert.AreEqual('Wrong %q', ReceivedMessage);
  finally
    Log.Free;
  end;
end;

procedure TPdfLogTests.TestRaisingCallbackIsContained;
begin
  var CallCount := 0;
  const Log = TPdfLog.Create(
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      Inc(CallCount);
      raise EAbort.Create('Callback failure');
    end);
  try
    Assert.WillNotRaise(
      procedure
      begin
        Log.Info('Plain');
        Log.Error('Object %d', [3]);
        Log.Error('a');
      end);
    Assert.AreEqual(3, CallCount);
  finally
    Log.Free;
  end;
end;

procedure TPdfLogTests.TestNoFormatWithoutCallback;
begin
  // A format string that would raise is never evaluated when nobody listens; observable only as not raising and not failing
  const Log = TPdfLog.Create(nil);
  try
    Assert.WillNotRaise(
      procedure
      begin
        Log.Warning('%d', ['x']);
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
  Assert.AreEqual(50, Options.MaxFormXObjectDepth);
  Assert.AreEqual<Int64>(10000000, Options.MaxOperatorsPerPage);
  Assert.AreEqual(2000000, Options.MaxGlyphsPerPage);
  Assert.AreEqual(16 * 1024 * 1024, Options.MaxInlineImageSize);
  Assert.AreEqual(4096, Options.MaxGraphicsStateDepth);
  Assert.AreEqual('', Options.Password);
  Assert.IsFalse(Assigned(Options.OnLog));
end;

end.
