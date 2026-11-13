unit Pdf4D.Model.Navigation.Golden.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Model.Document,
  Pdf4D.Model.Outline,
  Pdf4D.Model.OutlineItem;

type
  // Compares what the corpus files give for the outline, the attachments and the page labels with the golden dumps of the
  // PDFBox oracle (see docs/golden-format.md)
  [TestFixture]
  TNavigationGoldenTests = class
  private
    FOutlineLines: Integer;
    FAttachmentLines: Integer;

    class function CorpusFolder: string; static;
    class function EscapeText(const Text: string): string; static;
    class function PasswordOf(const Notes: string): string; static;

    procedure AddOutlineLines(const Document: TPDDocument; const Lines: TList<string>);
    procedure AddOutlineLevel(const Document: TPDDocument; const Node: TPDOutlineNode; const Level: Integer;
                              const Seen: TDictionary<TObject, Boolean>; const Lines: TList<string>);
    procedure AddAttachmentLines(const Document: TPDDocument; const Lines: TList<string>);
    function LabelsOf(const Document: TPDDocument): TArray<string>;
    function Differences(const Expected, Actual: TList<string>; const Prefix: string): string;
    function CompareFile(const PdfFile, GoldenFile, Password: string): string;

  public
    [Test]
    procedure TestOutlinesAttachmentsAndLabelsMatchTheGoldenDumps;
  end;

implementation

uses
  System.IOUtils,
  System.Math,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Model.PageLabels;

const
  CorpusEnvironmentVariable = 'PDF4D_CORPUS';
  OutlineDepthLimit = 64;
  OutlinePrefix = 'outline: ';
  AttachmentPrefix = 'attachment: ';
  LabelMarker = ' label=';

{ TNavigationGoldenTests }

class function TNavigationGoldenTests.CorpusFolder: string;
begin
  const FromEnvironment = GetEnvironmentVariable(CorpusEnvironmentVariable);
  if FromEnvironment <> '' then
  begin
    Exit(FromEnvironment);
  end;

  var Folder := TPath.GetDirectoryName(ParamStr(0));
  while Folder <> '' do
  begin
    if TFile.Exists(TPath.Combine(TPath.Combine(Folder, 'corpus'), 'manifest.csv')) then
    begin
      Exit(TPath.Combine(Folder, 'corpus'));
    end;
    const Parent = TPath.GetDirectoryName(Folder);
    if Parent = Folder then
    begin
      Break;
    end;
    Folder := Parent;
  end;
  Result := '';
end;

// Port of escapeText of the oracle
class function TNavigationGoldenTests.EscapeText(const Text: string): string;
begin
  const Builder = TStringBuilder.Create;
  try
    for var Character in Text do
    begin
      case Character of
        '\': Builder.Append('\\');
        #10: Builder.Append('\n');
        #13: Builder.Append('\r');
        #9: Builder.Append('\t');
      else
        if (Character < ' ') or (Character = #$7F) then
        begin
          Builder.Append('\x').Append(IntToHex(Ord(Character), 2));
        end
        else
        begin
          Builder.Append(Character);
        end;
      end;
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TNavigationGoldenTests.PasswordOf(const Notes: string): string;
begin
  Result := '';
  const Marker = 'password=';
  const Position = Notes.IndexOf(Marker);
  if Position >= 0 then
  begin
    Result := Notes.Substring(Position + Marker.Length);
    const End_ = Result.IndexOfAny([',', ';', ' ']);
    if End_ >= 0 then
    begin
      Result := Result.Substring(0, End_);
    end;
  end;
end;

procedure TNavigationGoldenTests.AddOutlineLevel(const Document: TPDDocument; const Node: TPDOutlineNode; const Level: Integer;
                                                  const Seen: TDictionary<TObject, Boolean>; const Lines: TList<string>);
begin
  for var Item in Node do
  begin
    // The oracle remembers an item before it looks at the depth
    const IsRepeated = Seen.ContainsKey(Item.CosObject);
    Seen.AddOrSetValue(Item.CosObject, True);
    if IsRepeated or (Level > OutlineDepthLimit) then
    begin
      Continue;
    end;

    var Target: string := '?';
    var PageIndex: Integer;
    if Item.TryGetPageIndex(PageIndex) then
    begin
      Target := IntToStr(PageIndex + 1);
    end;
    Lines.Add(OutlinePrefix + StringOfChar(' ', 2 * Level) + EscapeText(Item.Title) + ' -> ' + Target);
    AddOutlineLevel(Document, Item, Level + 1, Seen, Lines);
  end;
end;

procedure TNavigationGoldenTests.AddOutlineLines(const Document: TPDDocument; const Lines: TList<string>);
begin
  var Outline: TPDDocumentOutline;
  if not Document.Catalog.TryGetOutline(Outline) then
  begin
    Exit;
  end;

  const Seen = TDictionary<TObject, Boolean>.Create;
  try
    AddOutlineLevel(Document, Outline, 0, Seen, Lines);
  finally
    Seen.Free;
  end;
end;

procedure TNavigationGoldenTests.AddAttachmentLines(const Document: TPDDocument; const Lines: TList<string>);
begin
  for var Attachment in Document.GetEmbeddedFiles do
  begin
    var Size: string := '?';
    var Value: Integer;
    if Attachment.TryGetSize(Value) then
    begin
      Size := IntToStr(Value);
    end;
    Lines.Add(AttachmentPrefix + EscapeText(Attachment.FileName) + ' | ' + Size);
  end;
end;

// The oracle reads the labels of the catalog's /PageLabels, and gives none when the catalog has no /PageLabels
function TNavigationGoldenTests.LabelsOf(const Document: TPDDocument): TArray<string>;
begin
  var Dictionary: TCosDictionary;
  if not Document.Catalog.TryGetPageLabels(Dictionary) then
  begin
    Exit(nil);
  end;

  const Labels = TPDPageLabels.Create(Document, Dictionary);
  try
    Result := Labels.GetLabelsByPageIndices;
  finally
    Labels.Free;
  end;
end;

function TNavigationGoldenTests.Differences(const Expected, Actual: TList<string>; const Prefix: string): string;
begin
  Result := '';
  if Expected.Count <> Actual.Count then
  begin
    Result := Format('%s: %d lines expected, %d found. ', [Prefix, Expected.Count, Actual.Count]);
  end;
  for var Index := 0 to Min(Expected.Count, Actual.Count) - 1 do
  begin
    if Expected[Index] <> Actual[Index] then
    begin
      Exit(Result + Format('%s line %d: expected "%s", found "%s"', [Prefix, Index, Expected[Index], Actual[Index]]));
    end;
  end;
end;

function TNavigationGoldenTests.CompareFile(const PdfFile, GoldenFile, Password: string): string;
begin
  const GoldenLines = TFile.ReadAllLines(GoldenFile, TEncoding.UTF8);
  if (Length(GoldenLines) > 0) and GoldenLines[0].StartsWith('load-error:') then
  begin
    Exit('');
  end;

  const ExpectedOutline = TList<string>.Create;
  const ExpectedAttachments = TList<string>.Create;
  const ExpectedLabels = TList<string>.Create;
  const ActualOutline = TList<string>.Create;
  const ActualAttachments = TList<string>.Create;
  try
    for var Line in GoldenLines do
    begin
      if Line.StartsWith(OutlinePrefix) then
      begin
        ExpectedOutline.Add(Line);
      end
      else if Line.StartsWith(AttachmentPrefix) then
      begin
        ExpectedAttachments.Add(Line);
      end
      else if Line.StartsWith('page ') then
      begin
        ExpectedLabels.Add(Line.Substring(Line.IndexOf(LabelMarker) + LabelMarker.Length));
      end;
    end;

    Inc(FOutlineLines, ExpectedOutline.Count);
    Inc(FAttachmentLines, ExpectedAttachments.Count);

    var Options := TPdfLoadOptions.Default;
    Options.Password := Password;
    const Document = TPDDocument.Load(TFileStream.Create(PdfFile, fmOpenRead or fmShareDenyWrite), True, Options);
    try
      try
        AddOutlineLines(Document, ActualOutline);
      except
        on EPdfException do
        begin
          ActualOutline.Clear;
          ActualOutline.Add('outline: error');
        end;
      end;

      try
        AddAttachmentLines(Document, ActualAttachments);
      except
        on EPdfException do
        begin
          ActualAttachments.Clear;
          ActualAttachments.Add('attachment: error');
        end;
      end;

      const Labels = TList<string>.Create;
      try
        try
          Labels.AddRange(LabelsOf(Document));
        except
          on EPdfException do
          begin
            Labels.Clear;
          end;
        end;
        const ActualLabels = TList<string>.Create;
        try
          for var Index := 0 to ExpectedLabels.Count - 1 do
          begin
            if Index < Labels.Count then
            begin
              ActualLabels.Add(EscapeText(Labels[Index]));
            end
            else
            begin
              ActualLabels.Add('');
            end;
          end;
          Result := Differences(ExpectedLabels, ActualLabels, 'labels');
        finally
          ActualLabels.Free;
        end;
      finally
        Labels.Free;
      end;
    finally
      Document.Free;
    end;

    Result := Result + Differences(ExpectedOutline, ActualOutline, 'outline') +
              Differences(ExpectedAttachments, ActualAttachments, 'attachments');
  finally
    ActualAttachments.Free;
    ActualOutline.Free;
    ExpectedLabels.Free;
    ExpectedAttachments.Free;
    ExpectedOutline.Free;
  end;
end;

procedure TNavigationGoldenTests.TestOutlinesAttachmentsAndLabelsMatchTheGoldenDumps;
begin
  const Corpus = CorpusFolder;
  if Corpus = '' then
  begin
    Assert.Fail('The corpus was not found');
  end;

  const GoldenFolder = TPath.Combine(TPath.GetDirectoryName(Corpus), 'golden');
  var Problems := '';
  var FileCount := 0;
  const Rows = TFile.ReadAllLines(TPath.Combine(Corpus, 'manifest.csv'), TEncoding.UTF8);
  for var Index := 1 to High(Rows) do
  begin
    const Columns = Rows[Index].Split([';']);
    if Length(Columns) < 4 then
    begin
      Continue;
    end;

    const GoldenFile = TPath.Combine(GoldenFolder, Columns[0].Replace('/', '__') + '.dump.txt');
    const PdfFile = TPath.Combine(Corpus, Columns[0].Replace('/', PathDelim));
    if not (TFile.Exists(GoldenFile) and TFile.Exists(PdfFile)) then
    begin
      Continue;
    end;

    Inc(FileCount);
    try
      const Found = CompareFile(PdfFile, GoldenFile, PasswordOf(string.Join(';', Copy(Columns, 3))));
      if Found <> '' then
      begin
        Problems := Problems + Columns[0] + ': ' + Found + sLineBreak;
      end;
    except
      on Error: Exception do
      begin
        Problems := Problems + Columns[0] + ': ' + Error.ClassName + ' ' + Error.Message + sLineBreak;
      end;
    end;
  end;

  Assert.IsTrue(FileCount > 0, 'No corpus file was found');
  Assert.IsTrue(FOutlineLines > 0, 'The golden dumps have no outline');
  Assert.IsTrue(FAttachmentLines > 0, 'The golden dumps have no attachment');
  Assert.AreEqual('', Problems);
end;

end.
