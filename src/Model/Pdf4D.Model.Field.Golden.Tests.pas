unit Pdf4D.Model.Field.Golden.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Model.AcroForm,
  Pdf4D.Model.Document,
  Pdf4D.Model.Field;

type
  // Compares the form fields of the corpus files with the "field:" lines of the golden dumps of the PDFBox oracle (see
  // docs/golden-format.md)
  [TestFixture]
  TFieldGoldenTests = class
  private
    FFieldLines: Integer;

    class function CorpusFolder: string; static;
    class function EscapeText(const Text: string): string; static;
    class function PasswordOf(const Notes: string): string; static;
    class function KindName(const Kind: TPdfFieldKind): string; static;

    function FieldLine(const Item: TPDField): string;
    procedure AddFieldLines(const Document: TPDDocument; const Lines: TList<string>);
    function Differences(const Expected, Actual: TList<string>): string;
    function CompareFile(const PdfFile, GoldenFile, Password: string): string;

  public
    [Test]
    procedure TestFieldsMatchTheGoldenDumps;
  end;

implementation

uses
  System.IOUtils,
  System.Math,
  Pdf4D.Common.Defines;


const
  CorpusEnvironmentVariable = 'PDF4D_CORPUS';
  FieldPrefix = 'field: ';
  Separator = ' | ';

{ TFieldGoldenTests }

class function TFieldGoldenTests.CorpusFolder: string;
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
class function TFieldGoldenTests.EscapeText(const Text: string): string;
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

class function TFieldGoldenTests.PasswordOf(const Notes: string): string;
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

class function TFieldGoldenTests.KindName(const Kind: TPdfFieldKind): string;
begin
  case Kind of
    TPdfFieldKind.Text        : Result := 'text';
    TPdfFieldKind.CheckBox    : Result := 'checkbox';
    TPdfFieldKind.RadioButton : Result := 'radio';
    TPdfFieldKind.PushButton  : Result := 'pushbutton';
    TPdfFieldKind.ComboBox    : Result := 'combo';
    TPdfFieldKind.ListBox     : Result := 'list';
    TPdfFieldKind.Signature   : Result := 'signature';
    TPdfFieldKind.NonTerminal : Result := 'nonterminal';
  else
    Result := 'unknown';
  end;
end;

// Port of dumpField of the oracle: choice fields join their values with a comma, the others give the value as string
function TFieldGoldenTests.FieldLine(const Item: TPDField): string;
begin
  var Value := '';
  try
    case Item.Kind of
      TPdfFieldKind.NonTerminal:
      begin
        Value := '';
      end;
      TPdfFieldKind.ComboBox, TPdfFieldKind.ListBox:
      begin
        const Parts = TList<string>.Create;
        try
          for var Part in Item.Values do
          begin
            Parts.Add(EscapeText(Part));
          end;
          Value := string.Join(',', Parts.ToArray);
        finally
          Parts.Free;
        end;
      end;
    else
      Value := EscapeText(Item.ValueAsString);
    end;
  except
    on EPdfException do
    begin
      Value := '<error>';
    end;
  end;
  Result := FieldPrefix + EscapeText(Item.FullyQualifiedName) + Separator + KindName(Item.Kind) + Separator + Value;
end;

procedure TFieldGoldenTests.AddFieldLines(const Document: TPDDocument; const Lines: TList<string>);
begin
  var Form: TPDAcroForm;
  if not Document.Catalog.TryGetAcroForm(Form) then
  begin
    Exit;
  end;

  for var Field in Form.GetFieldTree do
  begin
    Lines.Add(FieldLine(Field));
  end;
end;

function TFieldGoldenTests.Differences(const Expected, Actual: TList<string>): string;
begin
  Result := '';
  if Expected.Count <> Actual.Count then
  begin
    Result := Format('%d lines expected, %d found. ', [Expected.Count, Actual.Count]);
  end;
  for var Index := 0 to Min(Expected.Count, Actual.Count) - 1 do
  begin
    if Expected[Index] <> Actual[Index] then
    begin
      Exit(Result + Format('line %d: expected "%s", found "%s"', [Index, Expected[Index], Actual[Index]]));
    end;
  end;
end;

function TFieldGoldenTests.CompareFile(const PdfFile, GoldenFile, Password: string): string;
begin
  const GoldenLines = TFile.ReadAllLines(GoldenFile, TEncoding.UTF8);
  if (Length(GoldenLines) > 0) and GoldenLines[0].StartsWith('load-error:') then
  begin
    Exit('');
  end;

  const Expected = TList<string>.Create;
  const Actual = TList<string>.Create;
  try
    for var Line in GoldenLines do
    begin
      if Line.StartsWith(FieldPrefix) then
      begin
        Expected.Add(Line);
      end;
    end;
    Inc(FFieldLines, Expected.Count);

    var Options := TPdfLoadOptions.Default;
    Options.Password := Password;
    const Document = TPDDocument.Load(TFileStream.Create(PdfFile, fmOpenRead or fmShareDenyWrite), True, Options);
    try
      try
        AddFieldLines(Document, Actual);
      except
        on EPdfException do
        begin
          Actual.Clear;
          Actual.Add('field: error');
        end;
      end;
    finally
      Document.Free;
    end;

    Result := Differences(Expected, Actual);
  finally
    Actual.Free;
    Expected.Free;
  end;
end;

procedure TFieldGoldenTests.TestFieldsMatchTheGoldenDumps;
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
  Assert.IsTrue(FFieldLines > 0, 'The golden dumps have no field');
  Assert.AreEqual('', Problems);
end;

end.
