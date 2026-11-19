// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.PositionDump;

interface

uses
  System.SysUtils,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Api.Page.Interfaces,
  Pdf4D.Api.TextLayout.Interfaces;

type
  // Writes the position dump of docs/golden-format.md ("Position goldens"), the same lines that the PDFBox oracle writes
  TPositionDump = record
  strict private
    const
      MaxPages = 50;

    class procedure CheckFinite(const Fragments: TArray<TPdfTextFragment>; const Source: string); static;
    class procedure ProbePage(const Page: IPdfPage; const PageNumber: Integer); static;

  public
    // Lenient: every exception becomes an "error" line. Strict: only a PDF exception does, any other exception (an access
    // violation, a range error) goes to the caller.
    class function Dump(const Document: IPdfDocument; const IsStrict: Boolean = False): string; static;
    // The number as the oracle writes it: two decimals, a point, NaN and Infinity spelled like Java does
    class function Number(const Value: Single): string; static;
    // Runs ExtractTextWithPositions and the TextLayout of every page, and raises EInvalidOpException when a quad is not finite.
    // Exceptions of the document itself (EPdfException) go to the caller.
    class procedure Probe(const Document: IPdfDocument); static;
  end;

implementation

uses
  System.Math,
  Pdf4D.Api.Document,
  Pdf4D.Common.Defines,
  Pdf4D.Model.Page,
  Pdf4D.Text.Stripper,
  Pdf4D.Text.TextPosition;

const
  LineFeed = #10;
  ErrorLine = 'error';

type
  // Collects per line of the stripper the first and the last position
  TLineCollector = class(TPdfTextStripper)
  strict private
    FLines: TStringBuilder;
    FStartX: Single;
    FStartY: Single;
    FEndX: Single;
    FEndY: Single;
    FGlyphs: Integer;

    procedure FlushLine;

  protected
    procedure BeginPage(const Page: TPDPage); override;
    procedure FinishPage(const Page: TPDPage); override;
    procedure WriteLineSeparator; override;
    procedure WriteString(const Text: string; const TextPositions: TArray<TTextPosition>); override;

  public
    constructor Create;
    destructor Destroy; override;

    procedure AddErrorLine;
    function Lines: string;
  end;

{ TLineCollector }

constructor TLineCollector.Create;
begin
  inherited Create;
  FLines := TStringBuilder.Create;
end;

destructor TLineCollector.Destroy;
begin
  FLines.Free;
  inherited;
end;

procedure TLineCollector.AddErrorLine;
begin
  FLines.Append(ErrorLine).Append(LineFeed);
end;

function TLineCollector.Lines: string;
begin
  Result := FLines.ToString;
end;

procedure TLineCollector.BeginPage(const Page: TPDPage);
begin
  FLines.Append(Format('page %d', [CurrentPageNo])).Append(LineFeed);
  inherited;
end;

procedure TLineCollector.FinishPage(const Page: TPDPage);
begin
  FlushLine;
  inherited;
end;

procedure TLineCollector.WriteLineSeparator;
begin
  FlushLine;
  inherited;
end;

procedure TLineCollector.WriteString(const Text: string; const TextPositions: TArray<TTextPosition>);
begin
  if Length(TextPositions) > 0 then
  begin
    if FGlyphs = 0 then
    begin
      FStartX := TextPositions[0].TextMatrix.TranslateX;
      FStartY := TextPositions[0].TextMatrix.TranslateY;
    end;
    const Last = TextPositions[High(TextPositions)];
    FEndX := Last.EndX;
    FEndY := Last.EndY;
    Inc(FGlyphs, Length(TextPositions));
  end;
  inherited;
end;

procedure TLineCollector.FlushLine;
begin
  if FGlyphs > 0 then
  begin
    FLines.Append(Format('line: %s %s %s %s %d', [TPositionDump.Number(FStartX), TPositionDump.Number(FStartY),
                                                  TPositionDump.Number(FEndX), TPositionDump.Number(FEndY), FGlyphs]));
    FLines.Append(LineFeed);
  end;
  FGlyphs := 0;
end;

{ TPositionDump }

class function TPositionDump.Number(const Value: Single): string;
begin
  if IsNaN(Value) then
  begin
    Exit('NaN');
  end;
  if IsInfinite(Value) then
  begin
    if Value > 0 then
    begin
      Exit('Infinity');
    end;
    Exit('-Infinity');
  end;
  Result := Format('%.2f', [Double(Value)], TFormatSettings.Invariant);
end;

class function TPositionDump.Dump(const Document: IPdfDocument; const IsStrict: Boolean): string;
begin
  const Collector = TLineCollector.Create;
  try
    Collector.SortByPosition := True;
    Collector.StartPage := 1;
    Collector.EndPage := Min(Document.PageCount, MaxPages);
    try
      Collector.GetText((Document as TPdfDocument).ModelDocument);
    except
      on EPdfException do
      begin
        Collector.AddErrorLine;
      end;
      on Exception do
      begin
        if IsStrict then
        begin
          raise;
        end;
        Collector.AddErrorLine;
      end;
    end;
    Result := Collector.Lines;
  finally
    Collector.Free;
  end;
end;

class procedure TPositionDump.CheckFinite(const Fragments: TArray<TPdfTextFragment>; const Source: string);
begin
  for var Fragment in Fragments do
  begin
    for var Quad in Fragment.Quads do
    begin
      if not Quad.IsFinite then
      begin
        raise EInvalidOpException.CreateFmt('%s has a quad that is not finite (page index %d)', [Source, Fragment.PageIndex]);
      end;
    end;
  end;
end;

class procedure TPositionDump.ProbePage(const Page: IPdfPage; const PageNumber: Integer);
begin
  const Layout = Page.TextLayout;
  CheckFinite(Layout.Words, Format('The words of page %d', [PageNumber]));
  CheckFinite(Layout.Segments, Format('The segments of page %d', [PageNumber]));
  CheckFinite(Layout.Lines, Format('The lines of page %d', [PageNumber]));
end;

class procedure TPositionDump.Probe(const Document: IPdfDocument);
begin
  const Positioned = Document.ExtractTextWithPositions;
  const Text = Positioned.Text;
  if Text <> '' then
  begin
    CheckFinite(Positioned.Locate(1, Length(Text)), 'The positioned text');
  end;

  var PageNumber := 0;
  for var Page in Document.Pages do
  begin
    Inc(PageNumber);
    ProbePage(Page, PageNumber);
  end;
end;

end.
