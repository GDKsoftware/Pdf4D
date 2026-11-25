// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.PasswordRetry.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.PasswordRetry,
  Pdf4D.Tests.TestDocument;

type
  [TestFixture]
  TPdfPasswordRetryTests = class
  private
    FBench: TDocumentBench;
    FRetry: TPdfPasswordRetry;
    FQuestions: Integer;
    FAnswer: string;
    FIsCancelled: Boolean;
    FOpenErrors: Integer;

    procedure HandleOpenError(Sender: TObject; const Kind: TPdfOpenErrorKind; const Message: string);
    procedure OpenEncryptedFile;

  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestTheRightPasswordOpens;
    [Test]
    procedure TestThreeQuestionsAtMost;
    [Test]
    procedure TestCancelStops;
    [Test]
    procedure TestNoQuestionsWhenDisabled;
    [Test]
    procedure TestAStreamIsNotAskedAgain;
    [Test]
    procedure TestReopenNeedsAFile;
    [Test]
    procedure TestAWorkerCrashDoesNotAskForAPassword;
  end;

implementation

uses
  System.IOUtils,
  Pdf4D.Api.DocumentHandle,
  Pdf4D.Tests.Corpus,
  Pdf4D.Tests.ViewerDocuments;

const
  EncryptedFile = 'generated/encrypted/aes-128-user.pdf';
  WrongPassword = 'not the password';

{ TPdfPasswordRetryTests }

procedure TPdfPasswordRetryTests.Setup;
begin
  FBench := TDocumentBench.Create;
  FBench.Document.OnOpenError := HandleOpenError;
  FQuestions := 0;
  FOpenErrors := 0;
  FIsCancelled := False;
  FAnswer := '';
  FRetry := TPdfPasswordRetry.Create(
    function(out Password: string): Boolean
    begin
      Inc(FQuestions);
      Password := FAnswer;
      Result := not FIsCancelled;
    end);
  FRetry.Document := FBench.Document;
end;

procedure TPdfPasswordRetryTests.TearDown;
begin
  FreeAndNil(FRetry);
  FreeAndNil(FBench);
end;

procedure TPdfPasswordRetryTests.HandleOpenError(Sender: TObject; const Kind: TPdfOpenErrorKind; const Message: string);
begin
  Inc(FOpenErrors);
end;

procedure TPdfPasswordRetryTests.OpenEncryptedFile;
begin
  FBench.OpenFile(TCorpus.PdfPath(EncryptedFile), '');
end;

procedure TPdfPasswordRetryTests.TestTheRightPasswordOpens;
begin
  FAnswer := TCorpus.PasswordFor(EncryptedFile);

  OpenEncryptedFile;

  Assert.AreEqual(Ord(TPdfDocumentState.Open), Ord(FBench.Document.State));
  Assert.AreEqual(1, FQuestions, 'asked once');
  Assert.AreEqual(0, FRetry.Attempts, 'the count starts again after an open');
  Assert.AreEqual(0, FOpenErrors, 'nobody hears of the failure that was retried');
end;

procedure TPdfPasswordRetryTests.TestThreeQuestionsAtMost;
begin
  FAnswer := WrongPassword;

  OpenEncryptedFile;

  Assert.AreEqual(Ord(TPdfDocumentState.Failed), Ord(FBench.Document.State));
  Assert.AreEqual(MaxPasswordAttempts, FQuestions);
  Assert.IsFalse(FRetry.CanAsk, 'no more questions');
  Assert.AreEqual(1, FOpenErrors, 'the last failure is told');

  OpenEncryptedFile;
  Assert.AreEqual(2 * MaxPasswordAttempts, FQuestions, 'a new open asks again');
end;

procedure TPdfPasswordRetryTests.TestCancelStops;
begin
  FIsCancelled := True;

  OpenEncryptedFile;

  Assert.AreEqual(Ord(TPdfDocumentState.Failed), Ord(FBench.Document.State));
  Assert.AreEqual(1, FQuestions);
  Assert.AreEqual(1, FOpenErrors, 'the failure stands');
end;

procedure TPdfPasswordRetryTests.TestNoQuestionsWhenDisabled;
begin
  FRetry.IsEnabled := False;
  FAnswer := TCorpus.PasswordFor(EncryptedFile);

  OpenEncryptedFile;

  Assert.AreEqual(Ord(TPdfDocumentState.Failed), Ord(FBench.Document.State));
  Assert.AreEqual(0, FQuestions);
end;

procedure TPdfPasswordRetryTests.TestAStreamIsNotAskedAgain;
begin
  FAnswer := TCorpus.PasswordFor(EncryptedFile);

  FBench.OpenData(TFile.ReadAllBytes(TCorpus.PdfPath(EncryptedFile)));

  Assert.AreEqual(Ord(TPdfDocumentState.Failed), Ord(FBench.Document.State));
  Assert.AreEqual(Ord(TPdfOpenErrorKind.InvalidPassword), Ord(FBench.Document.OpenErrorKind));
  Assert.AreEqual(0, FQuestions, 'the data of the stream is gone');
end;

procedure TPdfPasswordRetryTests.TestReopenNeedsAFile;
begin
  Assert.IsFalse(FBench.Document.CanReopen);
  Assert.WillRaise(
    procedure
    begin
      FBench.Document.Reopen('secret');
    end,
    EInvalidOpException);
end;

// The kind of an earlier failed open must not outlive the open that followed: a crash of the worker is no wrong password
procedure TPdfPasswordRetryTests.TestAWorkerCrashDoesNotAskForAPassword;
begin
  {$IFDEF PDF4D_TESTS}
  FAnswer := WrongPassword;
  OpenEncryptedFile;
  Assert.AreEqual(MaxPasswordAttempts, FQuestions, 'the wrong password was asked for');

  // The file name of the first open stays, so the document could be opened again
  FBench.OpenData(TViewerDocuments.Invoice);
  Assert.AreEqual(Ord(TPdfDocumentState.Open), Ord(FBench.Document.State));

  TPdfDocumentHandle.StripperHook :=
    procedure
    begin
      raise EAccessViolation.Create('Injected access violation');
    end;
  try
    FBench.Document.RequestPageText(0, TPdfJobPriority.Visible, nil);
    FBench.WaitUntil(
      function: Boolean
      begin
        Result := (FBench.Document.State = TPdfDocumentState.Failed);
      end,
      'the document to fail');
  finally
    TPdfDocumentHandle.StripperHook := nil;
  end;

  Assert.AreEqual(Ord(TPdfOpenErrorKind.Other), Ord(FBench.Document.OpenErrorKind));
  Assert.IsFalse(FRetry.CanAsk, 'a crash is not a reason to ask for a password');
  Assert.AreEqual(MaxPasswordAttempts, FQuestions, 'nobody was asked again');
  {$ELSE}
  Assert.Pass('The hook exists in the test build only');
  {$ENDIF}
end;

end.
