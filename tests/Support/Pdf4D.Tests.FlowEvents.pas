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
  // and the FMX viewer show the same document the same way, so both flows write the same lines; tests/reference/viewer/flow-events.txt in the
  // source tree holds them. The file is only written when PDF4D_RECORD_FLOW_EVENTS=1 is set and the caller allows it (the VCL flow); a
  // missing file is a failure, so a regression cannot write its own baseline.
  TFlowEventLog = class
  private
    FLines: TList<string>;

    class function QuadsText(const Quads: TArray<TPdfQuad>): string; static;
    class function Rounded(const Value: Single): string; static;
    class function EscapedText(const Text: string): string; static;
    class function Normalized(const Text: string): string; static;
    class function FirstDifference(const Expected, Actual: string): string; static;
    procedure Add(const Kind: string; const PageIndex: Integer; const Text: string; const Quads: TArray<TPdfQuad>);

  public
    constructor Create;
    destructor Destroy; override;

    // The reference file in the source tree (tests/reference/viewer/flow-events.txt), found from the program folder upward; it does not depend on PDF4D_CORPUS
    class function ReferencePath: string; static;
    // True when the environment asks to write the reference file: PDF4D_RECORD_FLOW_EVENTS=1
    class function IsRecording: Boolean; static;

    procedure AddHover(const HasSegment: Boolean; const Segment: TPdfTextFragment);
    procedure AddSelection(const Selection: TPdfTextSelection);
    procedure AddSearchHits(const Hits: TArray<TPdfSearchHit>);
    // A line that names a step of the flow, so that the lines can be read
    procedure AddStep(const Name: string);

    // The lines, with a line feed after each
    function Text: string;
    // Compares the lines with the reference file and returns '' when they are equal, else what differs. When IsRecording and AllowWrite,
    // the file is written instead and '' is returned.
    function Verify(const AllowWrite: Boolean): string;
  end;

implementation

uses
  System.IOUtils,
  System.Math,
  System.StrUtils,
  System.SysUtils;

const
  CorpusFolderName = 'corpus';
  ReferenceFolderName = 'reference';
  ReferenceSubFolderName = 'viewer';
  ReferenceFileName = 'flow-events.txt';
  RecordEnvironmentVariable = 'PDF4D_RECORD_FLOW_EVENTS';
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
  // The tests folder is the first folder from the program upward that holds both the corpus and the reference images
  var Current := TPath.GetDirectoryName(ParamStr(0));
  while Current <> '' do
  begin
    const IsTestsFolder = TDirectory.Exists(TPath.Combine(Current, CorpusFolderName)) and TDirectory.Exists(TPath.Combine(Current, ReferenceFolderName));
    if IsTestsFolder then
    begin
      Exit(TPath.Combine(TPath.Combine(TPath.Combine(Current, ReferenceFolderName), ReferenceSubFolderName), ReferenceFileName));
    end;

    const Parent = TPath.GetDirectoryName(Current);
    if Parent = Current then
    begin
      Break;
    end;
    Current := Parent;
  end;
  raise EInvalidOpException.Create('The tests folder is not found from the program folder upward, so the reference file cannot be located.');
end;

class function TFlowEventLog.IsRecording: Boolean;
begin
  Result := GetEnvironmentVariable(RecordEnvironmentVariable) = '1';
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

procedure TFlowEventLog.AddStep(const Name: string);
begin
  FLines.Add('step ' + Name);
end;

class function TFlowEventLog.FirstDifference(const Expected, Actual: string): string;
begin
  const ExpectedLines = Expected.Split([LineFeed]);
  const ActualLines = Actual.Split([LineFeed]);
  for var Index := 0 to Max(Length(ExpectedLines), Length(ActualLines)) - 1 do
  begin
    const ExpectedLine = IfThen(Index < Length(ExpectedLines), ExpectedLines[Index], '(no line)');
    const ActualLine = IfThen(Index < Length(ActualLines), ActualLines[Index], '(no line)');
    if ExpectedLine <> ActualLine then
    begin
      Exit(Format('line %d differs: the reference has "%s", the flow gave "%s"', [Index + 1, ExpectedLine, ActualLine]));
    end;
  end;
  Result := 'the events differ';
end;

function TFlowEventLog.Verify(const AllowWrite: Boolean): string;
begin
  const Path = ReferencePath;
  if AllowWrite and IsRecording then
  begin
    TDirectory.CreateDirectory(TPath.GetDirectoryName(Path));
    const Encoding = TUTF8Encoding.Create(False);
    try
      TFile.WriteAllText(Path, Text, Encoding);
    finally
      Encoding.Free;
    end;
    Exit('');
  end;

  if not TFile.Exists(Path) then
  begin
    Exit(Format('The reference file %s is missing; set %s=1 and run the VCL flow test to write it', [Path, RecordEnvironmentVariable]));
  end;

  const Expected = Normalized(TFile.ReadAllText(Path, TEncoding.UTF8));
  if Expected = Text then
  begin
    Exit('');
  end;
  Result := FirstDifference(Expected, Text);
end;

end.
