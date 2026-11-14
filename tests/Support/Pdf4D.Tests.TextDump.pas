// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.TextDump;

interface

uses
  System.SysUtils,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Api.TextOptions;

type
  // Writes the text dump of docs/golden-format.md ("Text goldens"), the same text that the PDFBox oracle writes
  TTextDump = record
  strict private
    const
      MaxPages = 50;
    class function SectionOptions(const Start, Stop: Integer; const IsSorted: Boolean): TPdfTextOptions; static;
    class function SeparatorOptions: TPdfTextOptions; static;
    class function WithoutSurrogates(const Text: string): string; static;
    class function EscapedLine(const Line: string): string; static;
    class function Lines(const Text: string): string; static;
    class function Section(const Document: IPdfDocument; const Heading: string; const Options: TPdfTextOptions; const IsStrict: Boolean): string; static;

  public
    // Lenient: every exception of a section becomes an "error" line. Strict: only a PDF exception does, any other
    // exception (an access violation, a range error) goes to the caller.
    class function Dump(const Document: IPdfDocument; const IsStrict: Boolean = False): string; static;
  end;

implementation

uses
  System.Character,
  Pdf4D.Common.Defines,
  Pdf4D.Tests.StructureDump;

const
  LineFeed = #10;
  ErrorSectionFormat = '%s'#10'error'#10;

{ TTextDump }

class function TTextDump.SectionOptions(const Start, Stop: Integer; const IsSorted: Boolean): TPdfTextOptions;
begin
  Result := TPdfTextOptions.Default;
  Result.SortByPosition := IsSorted;
  Result.StartPage := Start;
  Result.EndPage := Stop;
  Result.LineSeparator := LineFeed;
  Result.PageEnd := LineFeed;
end;

class function TTextDump.SeparatorOptions: TPdfTextOptions;
begin
  Result := TPdfTextOptions.Default;
  Result.StartPage := 1;
  Result.EndPage := 2;
  Result.LineSeparator := '<EOL>' + LineFeed;
  Result.WordSeparator := '<W>';
  Result.ParagraphStart := '<P>';
  Result.ParagraphEnd := '</P>';
  Result.PageStart := '<PAGE>';
  Result.PageEnd := '</PAGE>' + LineFeed;
  Result.ArticleStart := '<A>';
  Result.ArticleEnd := '</A>';
end;

// The oracle writes an unpaired surrogate as "?"
class function TTextDump.WithoutSurrogates(const Text: string): string;
begin
  Result := Text;
  var Position := 1;
  while Position <= Result.Length do
  begin
    const Character = Result[Position];
    if Character.IsHighSurrogate and (Position < Result.Length) and Result[Position + 1].IsLowSurrogate then
    begin
      Inc(Position, 2);
      Continue;
    end;
    if Character.IsSurrogate then
    begin
      Result[Position] := '?';
    end;
    Inc(Position);
  end;
end;

class function TTextDump.EscapedLine(const Line: string): string;
begin
  if Line = '' then
  begin
    Exit('|');
  end;

  var Escaped := TStructureDump.EscapedText(WithoutSurrogates(Line));
  if Line.EndsWith(' ') then
  begin
    Escaped := Escaped.Substring(0, Escaped.Length - 1) + '\x20';
  end;
  Result := '| ' + Escaped;
end;

class function TTextDump.Lines(const Text: string): string;
begin
  var Pieces := Text.Split([LineFeed]);
  if (Length(Pieces) > 0) and (Pieces[High(Pieces)] = '') then
  begin
    SetLength(Pieces, Length(Pieces) - 1);
  end;

  const Builder = TStringBuilder.Create;
  try
    for var Piece in Pieces do
    begin
      Builder.Append(EscapedLine(Piece)).Append(LineFeed);
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TTextDump.Section(const Document: IPdfDocument; const Heading: string; const Options: TPdfTextOptions; const IsStrict: Boolean): string;
begin
  Result := Heading + LineFeed;
  try
    Result := Result + Lines(Document.ExtractText(Options));
  except
    on EPdfException do
    begin
      Result := Format(ErrorSectionFormat, [Heading]);
    end;
    on Exception do
    begin
      if IsStrict then
      begin
        raise;
      end;
      Result := Format(ErrorSectionFormat, [Heading]);
    end;
  end;
end;

class function TTextDump.Dump(const Document: IPdfDocument; const IsStrict: Boolean): string;
begin
  const Builder = TStringBuilder.Create;
  try
    var Limit := Document.PageCount;
    if Limit > MaxPages then
    begin
      Limit := MaxPages;
    end;
    for var Page := 1 to Limit do
    begin
      Builder.Append(Section(Document, Format('text: default page %d', [Page]), SectionOptions(Page, Page, False), IsStrict));
    end;
    for var Page := 1 to Limit do
    begin
      Builder.Append(Section(Document, Format('text: sorted page %d', [Page]), SectionOptions(Page, Page, True), IsStrict));
    end;
    Builder.Append(Section(Document, 'text: range 2-3', SectionOptions(2, 3, False), IsStrict));
    Builder.Append(Section(Document, 'text: separators 1-2', SeparatorOptions, IsStrict));
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

end.
