// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.CancelToken.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  DUnitX.TestFramework,
  Pdf4D.Render.Renderer.Interfaces,
  Pdf4D.Render.CancelToken;

type
  [TestFixture]
  TPdfCancelTokenTests = class
  public
    [Test]
    procedure TestNewTokenIsNotCancelled;

    [Test]
    procedure TestCancelIsSticky;

    [Test]
    procedure TestCancelTokenFromOtherThread;
  end;

implementation

{ TPdfCancelTokenTests }

procedure TPdfCancelTokenTests.TestNewTokenIsNotCancelled;
begin
  const Token: IPdfCancelToken = TPdfCancelToken.Create;

  Assert.IsFalse(Token.IsCancelled);
end;

procedure TPdfCancelTokenTests.TestCancelIsSticky;
begin
  const Token = TPdfCancelToken.Create;
  const Reference: IPdfCancelToken = Token;

  Token.Cancel;
  Token.Cancel;

  Assert.IsTrue(Reference.IsCancelled);
end;

procedure TPdfCancelTokenTests.TestCancelTokenFromOtherThread;
begin
  const Token = TPdfCancelToken.Create;
  const Reference: IPdfCancelToken = Token;

  const Worker = TThread.CreateAnonymousThread(
    procedure
    begin
      Token.Cancel;
    end);
  Worker.FreeOnTerminate := False;
  try
    Worker.Start;
    Worker.WaitFor;

    Assert.IsTrue(Reference.IsCancelled);
  finally
    Worker.Free;
  end;
end;

end.
