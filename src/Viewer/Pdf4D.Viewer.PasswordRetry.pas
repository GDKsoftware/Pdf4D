// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.PasswordRetry;

{$EXCESSPRECISION OFF}

interface

uses
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.Document;

const
  MaxPasswordAttempts = 3;

type
  // Asks the user for the password of the document; False when the user cancels
  TPdfPasswordQuery = reference to function(out Password: string): Boolean;

  // Asks for the password of a document that failed to open for want of it, and opens the file again with the answer, at most
  // MaxPasswordAttempts times for one open of the application; a cancel stops the questions. Only a file can be opened again: a document
  // from a stream is gone once it has failed. The question is asked inside the OpenFailed notification of the document. UI thread only.
  TPdfPasswordRetry = class
  private
    FLink: TPdfDocumentLink;
    FQuery: TPdfPasswordQuery;
    FIsEnabled: Boolean;
    FAttempts: Integer;
    FIsReopening: Boolean;

    function GetDocument: TPdf4DCustomDocument;
    procedure SetDocument(const Value: TPdf4DCustomDocument);
    procedure HandleDocumentChange(const Change: TPdfDocumentChange);
    procedure Retry;

  public
    constructor Create(const Query: TPdfPasswordQuery);
    destructor Destroy; override;

    // Whether the document failed for want of a password and may be asked for it once more
    function CanAsk: Boolean;

    // Through an internal link
    property Document: TPdf4DCustomDocument read GetDocument write SetDocument;
    // False: no questions
    property IsEnabled: Boolean read FIsEnabled write FIsEnabled;
    // The questions since the open of the application, or since the last successful open
    property Attempts: Integer read FAttempts;
  end;

implementation

uses
  System.SysUtils;

{ TPdfPasswordRetry }

constructor TPdfPasswordRetry.Create(const Query: TPdfPasswordQuery);
begin
  inherited Create;
  if not Assigned(Query) then
  begin
    raise EArgumentNilException.Create('A password retry needs a query');
  end;

  FQuery := Query;
  FIsEnabled := True;
  FLink := TPdfDocumentLink.Create(HandleDocumentChange);
end;

destructor TPdfPasswordRetry.Destroy;
begin
  FLink.Free;
  inherited;
end;

function TPdfPasswordRetry.GetDocument: TPdf4DCustomDocument;
begin
  Result := FLink.Document;
end;

procedure TPdfPasswordRetry.SetDocument(const Value: TPdf4DCustomDocument);
begin
  FLink.Document := Value;
  FAttempts := 0;
end;

function TPdfPasswordRetry.CanAsk: Boolean;
begin
  const Current = Document;
  Result := FIsEnabled and Assigned(Current) and (Current.State = TPdfDocumentState.Failed) and
            (Current.OpenErrorKind = TPdfOpenErrorKind.InvalidPassword) and (FAttempts < MaxPasswordAttempts) and Current.CanReopen;
end;

procedure TPdfPasswordRetry.HandleDocumentChange(const Change: TPdfDocumentChange);
begin
  case Change of
    TPdfDocumentChange.Opening:
      // An open of the application starts the count again; an open of the retry goes on with it
      if not FIsReopening then
      begin
        FAttempts := 0;
      end;
    TPdfDocumentChange.Opened:
      FAttempts := 0;
    TPdfDocumentChange.OpenFailed:
      if CanAsk then
      begin
        Retry;
      end;
    TPdfDocumentChange.Closed,
    TPdfDocumentChange.CurrentPage,
    TPdfDocumentChange.Overlays,
    TPdfDocumentChange.SearchResults,
    TPdfDocumentChange.CurrentSearchHit:
      begin
        // The questions do not depend on these
      end;
  else
    raise ENotSupportedException.CreateFmt('Unsupported document change: %d', [Ord(Change)]);
  end;
end;

procedure TPdfPasswordRetry.Retry;
begin
  Inc(FAttempts);

  var Password: string;
  if not FQuery(Password) then
  begin
    // The user does not want to open it: no more questions, and the failure stands
    FAttempts := MaxPasswordAttempts;
    Exit;
  end;

  // The failure of this attempt is not told further: the open of the answer takes its place
  FIsReopening := True;
  try
    Document.Reopen(Password);
  finally
    FIsReopening := False;
  end;
end;

end.
