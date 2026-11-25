// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.TextMatcher;

{$EXCESSPRECISION OFF}

interface

type
  // 1-based, in UTF-16 code units
  TPdfTextMatch = record
    Start: Integer;
    Length: Integer;
  end;

  TPdfTextMatcher = class
  private
    class function IsWhitespace(const Value: Char): Boolean; static;
    class function NormalizeQuery(const Query: string): string; static;
    // Upper case by the invariant mapping of the RTL, never by the locale of the user: a Turkish i must not become a dotted capital I
    class function FoldCase(const Value: Char): Char; static;
    class function CharsEqual(const TextChar, QueryChar: Char; const MatchCase: Boolean): Boolean; static;
    class function TryMatchAt(const Text, Query: string; const Start: Integer; const MatchCase: Boolean; out AfterMatch: Integer): Boolean; static;

  public
    // Whitespace in the query matches any run of whitespace in the text; matches do not overlap
    class function FindAll(const Text, Query: string; const MatchCase: Boolean): TArray<TPdfTextMatch>; static;
  end;

implementation

uses
  System.SysUtils;

const
  LastAsciiChar = #$007F;

{ TPdfTextMatcher }

class function TPdfTextMatcher.FindAll(const Text, Query: string; const MatchCase: Boolean): TArray<TPdfTextMatch>;
begin
  Result := nil;

  const NormalizedQuery = NormalizeQuery(Query);
  if NormalizedQuery.IsEmpty then
  begin
    Exit;
  end;

  var Count := 0;
  var Position := 1;
  while Position <= Text.Length do
  begin
    var AfterMatch: Integer;
    const IsMatch = (not IsWhitespace(Text[Position])) and
                    TryMatchAt(Text, NormalizedQuery, Position, MatchCase, AfterMatch);
    if IsMatch then
    begin
      if Count = System.Length(Result) then
      begin
        SetLength(Result, (Count * 2) + 4);
      end;
      Result[Count].Start  := Position;
      Result[Count].Length := AfterMatch - Position;
      Inc(Count);
      Position := AfterMatch;
    end
    else
    begin
      Inc(Position);
    end;
  end;

  SetLength(Result, Count);
end;

class function TPdfTextMatcher.IsWhitespace(const Value: Char): Boolean;
begin
  Result := CharInSet(Value, [' ', #9, #10, #13, #$00A0]);
end;

class function TPdfTextMatcher.NormalizeQuery(const Query: string): string;
begin
  Result := '';

  var PendingSpace := False;
  for var QueryChar in Query do
  begin
    if IsWhitespace(QueryChar) then
    begin
      PendingSpace := not Result.IsEmpty;
    end
    else
    begin
      if PendingSpace then
      begin
        Result := Result + ' ';
        PendingSpace := False;
      end;
      Result := Result + QueryChar;
    end;
  end;
end;

class function TPdfTextMatcher.FoldCase(const Value: Char): Char;
begin
  if Value <= LastAsciiChar then
  begin
    Result := Value;
    if CharInSet(Value, ['a'..'z']) then
    begin
      Result := Char(Ord(Value) - (Ord('a') - Ord('A')));
    end;
    Exit;
  end;

  // A mapping that does not give exactly one character leaves the character as it is
  const Folded = string(Value).ToUpperInvariant;
  Result := Value;
  if Folded.Length = 1 then
  begin
    Result := Folded[1];
  end;
end;

class function TPdfTextMatcher.CharsEqual(const TextChar, QueryChar: Char; const MatchCase: Boolean): Boolean;
begin
  if MatchCase then
  begin
    Result := (TextChar = QueryChar);
  end
  else
  begin
    Result := (FoldCase(TextChar) = FoldCase(QueryChar));
  end;
end;

class function TPdfTextMatcher.TryMatchAt(const Text, Query: string; const Start: Integer; const MatchCase: Boolean; out AfterMatch: Integer): Boolean;
begin
  Result := False;
  AfterMatch := Start;

  for var QueryChar in Query do
  begin
    const IsEndOfText = (AfterMatch > Text.Length);
    if IsEndOfText then
    begin
      Exit;
    end;

    if QueryChar = ' ' then
    begin
      if not IsWhitespace(Text[AfterMatch]) then
      begin
        Exit;
      end;
      while (AfterMatch <= Text.Length) and IsWhitespace(Text[AfterMatch]) do
      begin
        Inc(AfterMatch);
      end;
    end
    else
    begin
      if not CharsEqual(Text[AfterMatch], QueryChar, MatchCase) then
      begin
        Exit;
      end;
      Inc(AfterMatch);
    end;
  end;

  Result := True;
end;

end.
