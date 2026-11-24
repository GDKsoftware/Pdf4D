// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.SearchBarModel;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.Document;

type
  // What a search bar does with its query, for every framework: Enter searches, or goes to the next hit when the query and the case did
  // not change; Shift+Enter goes to the previous hit; an empty query or Escape clears the search. The bar shows ResultText and updates it
  // in OnChanged. UI thread only.
  TPdfSearchBarModel = class
  private
    FLink: TPdfDocumentLink;
    // What the last search looked for; a search was done when FHasSearched
    FHasSearched: Boolean;
    FLastQuery: string;
    FLastMatchCase: Boolean;
    FOnChanged: TNotifyEvent;

    function GetDocument: TPdf4DCustomDocument;
    procedure SetDocument(const Value: TPdf4DCustomDocument);
    procedure HandleDocumentChange(const Change: TPdfDocumentChange);
    function IsSameSearch(const Query: string; const MatchCase: Boolean): Boolean;
    procedure StartSearch(const Query: string; const MatchCase: Boolean);
    procedure Changed;

  public
    constructor Create;
    destructor Destroy; override;

    function CanSearch: Boolean;
    // Goes to the next or previous hit of the search of the query, starts that search, or clears the search for an empty query
    procedure Advance(const Query: string; const MatchCase, IsForward: Boolean);
    // A search that was done is done again with the other case
    procedure MatchCaseChanged(const Query: string; const MatchCase: Boolean);
    // Takes the hits away and stops a search that runs
    procedure Clear;
    // 'n of m' ('n of m+' when the search stopped at its limit), 'Searching...' or 'No results' after a search, else empty
    function ResultText: string;

    // Through an internal link; the search belongs to the document that was open, so a change of document or of its state forgets it
    property Document: TPdf4DCustomDocument read GetDocument write SetDocument;
    property HasSearched: Boolean read FHasSearched;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
  end;

implementation

uses
  System.Math,
  System.SysUtils,
  Pdf4D.Viewer.ResourceStrings;

{ TPdfSearchBarModel }

constructor TPdfSearchBarModel.Create;
begin
  inherited Create;
  FLink := TPdfDocumentLink.Create(HandleDocumentChange);
end;

destructor TPdfSearchBarModel.Destroy;
begin
  FOnChanged := nil;
  FLink.Free;
  inherited;
end;

function TPdfSearchBarModel.GetDocument: TPdf4DCustomDocument;
begin
  Result := FLink.Document;
end;

procedure TPdfSearchBarModel.SetDocument(const Value: TPdf4DCustomDocument);
begin
  if Value = FLink.Document then
  begin
    Exit;
  end;

  FLink.Document := Value;
  FHasSearched := False;
  Changed;
end;

procedure TPdfSearchBarModel.HandleDocumentChange(const Change: TPdfDocumentChange);
begin
  case Change of
    TPdfDocumentChange.Opening,
    TPdfDocumentChange.Opened,
    TPdfDocumentChange.OpenFailed,
    TPdfDocumentChange.Closed:
      begin
        FHasSearched := False;
        Changed;
      end;
    TPdfDocumentChange.SearchResults,
    TPdfDocumentChange.CurrentSearchHit:
      Changed;
    TPdfDocumentChange.CurrentPage,
    TPdfDocumentChange.Overlays:
      begin
        // Not of interest
      end;
  else
    raise ENotSupportedException.CreateFmt('Unsupported document change: %d', [Ord(Change)]);
  end;
end;

procedure TPdfSearchBarModel.Changed;
begin
  if Assigned(FOnChanged) then
  begin
    FOnChanged(Self);
  end;
end;

function TPdfSearchBarModel.CanSearch: Boolean;
begin
  Result := Assigned(Document) and (Document.State = TPdfDocumentState.Open);
end;

function TPdfSearchBarModel.IsSameSearch(const Query: string; const MatchCase: Boolean): Boolean;
begin
  Result := FHasSearched and (Query = FLastQuery) and (MatchCase = FLastMatchCase);
end;

procedure TPdfSearchBarModel.StartSearch(const Query: string; const MatchCase: Boolean);
begin
  FHasSearched := True;
  FLastQuery := Query;
  FLastMatchCase := MatchCase;
  Document.Search(FLastQuery, FLastMatchCase);
  Changed;
end;

procedure TPdfSearchBarModel.Advance(const Query: string; const MatchCase, IsForward: Boolean);
begin
  if not CanSearch then
  begin
    Exit;
  end;

  if Query = '' then
  begin
    Clear;
  end
  else if IsSameSearch(Query, MatchCase) then
  begin
    if IsForward then
    begin
      Document.NextSearchHit;
    end
    else
    begin
      Document.PriorSearchHit;
    end;
  end
  else
  begin
    StartSearch(Query, MatchCase);
  end;
end;

procedure TPdfSearchBarModel.MatchCaseChanged(const Query: string; const MatchCase: Boolean);
begin
  if CanSearch and FHasSearched and (Query <> '') then
  begin
    StartSearch(Query, MatchCase);
  end;
end;

procedure TPdfSearchBarModel.Clear;
begin
  FHasSearched := False;
  FLastQuery := '';
  if Assigned(Document) then
  begin
    // An empty query takes the hits away and stops a search that is running
    Document.Search('', False);
  end;
  Changed;
end;

function TPdfSearchBarModel.ResultText: string;
begin
  Result := '';
  if not (Assigned(Document) and FHasSearched) then
  begin
    Exit;
  end;

  const Count = Document.SearchHitCount;
  if Count > 0 then
  begin
    var Index: Integer;
    var Hit: TPdfSearchHit;
    Document.TryGetCurrentSearchHit(Index, Hit);
    var Template := SSearchResultCount;
    if Document.IsSearchCapped then
    begin
      Template := SSearchResultCountCapped;
    end;
    Result := Format(Template, [Max(Index, 0) + 1, Count]);
  end
  else if Document.IsSearching then
  begin
    Result := SSearching;
  end
  else
  begin
    Result := SSearchNoResults;
  end;
end;

end.
