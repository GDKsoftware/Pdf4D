// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.FlowEvents;

{$EXCESSPRECISION OFF}

interface

uses
  System.Generics.Collections,
  Pdf4D.Api.TextLayout.Interfaces,
  Pdf4D.Common.Quad,
  Pdf4D.Viewer.Types;

type
  // The events of the end-to-end flow of a viewer, one line each: kind, page, text and the quads rounded to 0.01 in PDF user space. The VCL
  // and the FMX viewer show the same document the same way, so both flows write the same lines; tests/reference/viewer/flow-events.txt holds
  // them. The VCL flow writes the file when it is not there, and compares otherwise; the FMX flow only compares.
  TFlowEventLog = class
  private
    FLines: TList<string>;

    class function QuadsText(const Quads: TArray<TPdfQuad>): string; static;
    class function Rounded(const Value: Single): string; static;
    class function EscapedText(const Text: string): string; static;
    class function Normalized(const Text: string): string; static;
    procedure Add(const Kind: string; const PageIndex: Integer; const Text: string; const Quads: TArray<TPdfQuad>);

  public
    constructor Create;
    destructor Destroy; override;

    class function ReferencePath: string; static;

    procedure AddHover(const HasSegment: Boolean; const Segment: TPdfTextFragment);
    procedure AddSelection(const Selection: TPdfTextSelection);
    procedure AddSearchHits(const Hits: TArray<TPdfSearchHit>);

    // The lines, with a line feed after each
    function Text: string;
    // Writes the reference file; the caller checks that it is not there yet
    procedure WriteReference;
    function ReadReference: string;
    function HasReference: Boolean;
  end;

implementation

uses
  System.IOUtils,
  System.Math,
  System.SysUtils,
  Pdf4D.Tests.Corpus;

const
  ReferenceFolderName = 'reference';
  ReferenceSubFolderName = 'viewer';
  ReferenceFileName = 'flow-events.txt';
  LineFeed = #10;

{ TFlowEventLog }

constructor TFlowEventLog.Create;
begin
  inherited Create;
  FLines := TList<string>.Create;
end;

destructor TFlowEventLog.Destroy;
begin
  FLines.Free;
  inherited;
end;

class function TFlowEventLog.ReferencePath: string;
begin
  const CorpusFolder = TCorpus.Folder;
  if CorpusFolder = '' then
  begin
    raise EInvalidOpException.Create('The test corpus is not found, so the folder of the reference files is unknown.');
  end;

  Result := TPath.Combine(TPath.Combine(TPath.Combine(TPath.GetDirectoryName(CorpusFolder), ReferenceFolderName), ReferenceSubFolderName),
                          ReferenceFileName);
end;

class function TFlowEventLog.Rounded(const Value: Single): string;
begin
  // A value that rounds to zero has no sign
  const Clean = IfThen(Abs(Value) < 0.005, 0.0, Value);
  Result := Format('%.2f', [Clean], TFormatSettings.Invariant);
end;

class function TFlowEventLog.QuadsText(const Quads: TArray<TPdfQuad>): string;
begin
  var Parts: TArray<string>;
  for var Quad in Quads do
  begin
    Parts := Parts + [Format('(%s,%s %s,%s %s,%s %s,%s)', [Rounded(Quad.P1.X), Rounded(Quad.P1.Y), Rounded(Quad.P2.X), Rounded(Quad.P2.Y),
                                                           Rounded(Quad.P3.X), Rounded(Quad.P3.Y), Rounded(Quad.P4.X), Rounded(Quad.P4.Y)])];
  end;
  Result := string.Join(' ', Parts);
end;

class function TFlowEventLog.EscapedText(const Text: string): string;
begin
  Result := Text.Replace('\', '\\').Replace(#13, '\r').Replace(#10, '\n');
end;

class function TFlowEventLog.Normalized(const Text: string): string;
begin
  Result := Text.Replace(#13#10, LineFeed);
end;

procedure TFlowEventLog.Add(const Kind: string; const PageIndex: Integer; const Text: string; const Quads: TArray<TPdfQuad>);
begin
  FLines.Add(Format('%s page=%d text="%s" quads=%s', [Kind, PageIndex, EscapedText(Text), QuadsText(Quads)]));
end;

procedure TFlowEventLog.AddHover(const HasSegment: Boolean; const Segment: TPdfTextFragment);
begin
  if HasSegment then
  begin
    Add('hover', Segment.PageIndex, Segment.Text, Segment.Quads);
  end
  else
  begin
    FLines.Add('hover-none');
  end;
end;

procedure TFlowEventLog.AddSelection(const Selection: TPdfTextSelection);
begin
  Add('selected', Selection.PageIndex, Selection.Text, Selection.Quads);
end;

procedure TFlowEventLog.AddSearchHits(const Hits: TArray<TPdfSearchHit>);
begin
  for var Hit in Hits do
  begin
    Add('search-hit', Hit.PageIndex, Hit.Text, Hit.Quads);
  end;
end;

function TFlowEventLog.Text: string;
begin
  Result := '';
  for var Line in FLines do
  begin
    Result := Result + Line + LineFeed;
  end;
end;

procedure TFlowEventLog.WriteReference;
begin
  const Path = ReferencePath;
  TDirectory.CreateDirectory(TPath.GetDirectoryName(Path));
  TFile.WriteAllText(Path, Text, TUTF8Encoding.Create(False));
end;

function TFlowEventLog.HasReference: Boolean;
begin
  Result := TFile.Exists(ReferencePath);
end;

function TFlowEventLog.ReadReference: string;
begin
  Result := Normalized(TFile.ReadAllText(ReferencePath, TEncoding.UTF8));
end;

end.
