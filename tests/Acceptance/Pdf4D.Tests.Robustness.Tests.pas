// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.Robustness.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections,
  DUnitX.TestFramework;

type
  TMutationKind = (OverwriteBytes, Truncate, DuplicateBlock, ChangeObjectHeader);

  // What loading and dumping one mutated file came to: empty for success, otherwise the class and message of the exception
  TMutationOutcome = record
    Failure: string;
    IsPdfException: Boolean;
  end;

  // Mutates the bytes of a file with the random number generator of the calling thread, so RandSeed decides the result
  TMutator = record
  strict private
    class procedure Overwrite(var Bytes: TBytes); static;
    class procedure DuplicateBlock(var Bytes: TBytes); static;
    class function ObjectHeaderPositions(const Bytes: TBytes): TArray<Integer>; static;
    class procedure ChangeObjectHeader(var Bytes: TBytes); static;

  public
    class function Mutate(const Source: TBytes; const Kind: TMutationKind): TBytes; static;
  end;

  // What a run does with the bytes. Structure loads a document and dumps its structure, Text also dumps its text, PageText only
  // dumps the text, LimitedPageText does so with smaller budgets for operators and glyphs, the program
  // kinds give the bytes to one parser of a font program or CMap and ask it for widths and Unicode, FontClasses loads the
  // document and asks the PDF font /F1 for widths and Unicode of every code.
  TFuzzWork = (Structure, Text, PageText, LimitedPageText, TrueTypeProgram, OpenTypeProgram, CffProgram, Type1Program, CMapProgram, FontClasses);

  // Does the work on the bytes; used on the calling thread or on a worker thread
  TMutationRun = class
  strict private
    FBytes: TBytes;
    FPassword: string;
    FWork: TFuzzWork;
    FFinished: TEvent;
    FWorker: TThread;
    FOutcome: TMutationOutcome;
    procedure Execute;
    procedure DoWork;

  public
    constructor Create(const Bytes: TBytes; const Password: string); overload;
    constructor Create(const Bytes: TBytes; const Password: string; const Work: TFuzzWork); overload;
    destructor Destroy; override;

    // Runs on the calling thread
    function RunHere: TMutationOutcome;
    // Runs on a worker thread. False when it did not finish within the time: the thread then keeps running, a hang cannot be stopped.
    function RunWithin(const Milliseconds: Cardinal; out Outcome: TMutationOutcome): Boolean;
  end;

  // Seed and size of the fuzz runs. The environment variables PDF4D_FUZZ_SEED (added to every seed) and PDF4D_FUZZ_SCALE
  // (multiplies the number of cases) make a larger sweep with other seeds possible without a change of the code.
  TFuzzSettings = record
    class function SeedOffset: Integer; static;
    class function Scale(const Count: Integer): Integer; static;
    // The time one run may take, in seconds: PDF4D_FUZZ_SECONDS, 10 by default
    class function TimeLimitSeconds: Integer; static;
    // The file that gets the name and the duration of every run (PDF4D_FUZZ_TRACE), or empty
    class function TraceFile: string; static;
  end;

  // Runs the work on a worker thread with a time limit and collects the failures: only success or an EPdfException passes
  TFuzzCampaign = class
  strict private
    FFailures: TList<string>;

  public
    constructor Create;
    destructor Destroy; override;

    // For looking at a failure: the bytes go to the folder in PDF4D_ROBUSTNESS_OUTPUT
    class procedure SaveFailure(const Name: string; const Bytes: TBytes); static;
    class procedure Trace(const Name: string; const Milliseconds: Int64; const Failure: string); static;

    // Mutates the files of the corpus (a different mutation every time, the seed and the index are in the name of a failure)
    // and runs every mutation
    class procedure RunMutatedCorpus(const Work: TFuzzWork); static;

    procedure Run(const Name: string; const Bytes: TBytes; const Password: string; const Work: TFuzzWork);
    procedure AssertNoFailures;
  end;

  [TestFixture]
  TRobustnessTests = class
  public
    // Every mutation runs on a worker thread with a time limit and with the strict dump: success or an EPdfException, never another
    // exception and never a hang
    [Test]
    procedure TestMutatedCorpusFailsCleanlyInTime;
    [Test]
    procedure TestAllCorpusFilesLoadWithoutLeak;
  end;

implementation

uses
  System.IOUtils,
  System.Diagnostics,
  System.Math,
  Pdf4D.Api.Document,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Common.Defines,
  Pdf4D.Font.Base,
  Pdf4D.Font.Factory,
  Pdf4D.FontBox.Cff.Font,
  Pdf4D.FontBox.Cff.Parser,
  Pdf4D.FontBox.CMap,
  Pdf4D.FontBox.CMapParser,
  Pdf4D.FontBox.OpenType,
  Pdf4D.FontBox.TrueType.Cmap,
  Pdf4D.FontBox.TrueType.Font,
  Pdf4D.FontBox.TrueType.Parser,
  Pdf4D.FontBox.Type1.Font,
  Pdf4D.IO.RandomAccessRead,
  Pdf4D.Model.Document,
  Pdf4D.Tests.Corpus,
  Pdf4D.Tests.StructureDump,
  Pdf4D.Tests.TextDocuments,
  Pdf4D.Tests.TextDump;

const
  Seed = 1234;
  FileCount = 50;
  MutationsPerFile = 20;
  MaxMutationSeconds = 10;
  MaxOverwriteBytes = 64;
  MaxDuplicatedBytes = 4096;
  MaxReportedFailures = 20;
  OutputEnvironmentVariable = 'PDF4D_ROBUSTNESS_OUTPUT';
  SeedEnvironmentVariable = 'PDF4D_FUZZ_SEED';
  SecondsEnvironmentVariable = 'PDF4D_FUZZ_SECONDS';
  TraceEnvironmentVariable = 'PDF4D_FUZZ_TRACE';
  ScaleEnvironmentVariable = 'PDF4D_FUZZ_SCALE';
  ObjectKeyword = 'obj';
  LimitedOperatorBudget = 1000000;
  LimitedGlyphBudget = 200000;
  ProbedGlyphs = 400;
  ProbedCodes = 300;
  ProbedFontKey = 'F1';

type
  // What the parsers of font programs and CMaps and the font classes are asked, so that a damaged program shows itself in the
  // widths and the Unicode values and not only when it is read
  TFontProgramProbe = class
  strict private
    class procedure TouchTrueTypeFont(const Font: TTrueTypeFont); static;
    class procedure TouchCmapLookup(const Lookup: TCmapSubtable); static;
    class procedure TouchCffFont(const Font: TCFFFont); static;
    class procedure TouchCffType1Font(const Font: TCFFType1Font); static;
    class procedure TouchCffCIDFont(const Font: TCFFCIDFont); static;
    class procedure TouchCMap(const CMap: TCMap); static;
    class procedure ParseCMap(const Bytes: TBytes; const IsStrict: Boolean); static;
    class procedure TouchFont(const Font: TPDFont); static;
    class function CodeBytes: TBytes; static;

  public
    class procedure TrueType(const Bytes: TBytes); static;
    class procedure OpenType(const Bytes: TBytes); static;
    class procedure Cff(const Bytes: TBytes); static;
    class procedure Type1(const Bytes: TBytes); static;
    class procedure CMap(const Bytes: TBytes); static;
    class procedure FontClasses(const Bytes: TBytes); static;
  end;

{ TFontProgramProbe }

class function TFontProgramProbe.CodeBytes: TBytes;
begin
  SetLength(Result, 512);
  for var Index := 0 to High(Result) do
  begin
    Result[Index] := Byte(Index * 7);
  end;
end;

class procedure TFontProgramProbe.TouchCmapLookup(const Lookup: TCmapSubtable);
const
  CodePoints: array[0..8] of Integer = (0, 32, 65, 97, $E9, $20AC, $FFFD, $10000, $1F600);
begin
  for var CodePoint in CodePoints do
  begin
    Lookup.GetGlyphId(CodePoint);
  end;
  for var Glyph := 0 to 20 do
  begin
    Lookup.GetCharCodes(Glyph);
  end;
end;

class procedure TFontProgramProbe.TouchTrueTypeFont(const Font: TTrueTypeFont);
begin
  const GlyphCount = Min(Font.NumberOfGlyphs, ProbedGlyphs);
  for var Glyph := 0 to GlyphCount - 1 do
  begin
    Font.GetAdvanceWidth(Glyph);
  end;
  for var Name in ['A', '.notdef', 'space', 'uni0041', 'gid5', 'g5', 'nonexistent'] do
  begin
    Font.NameToGID(Name);
    Font.GetWidth(Name);
    Font.HasGlyph(Name);
  end;

  var Lookup: TCmapSubtable;
  if Font.TryGetUnicodeCmapLookup(False, Lookup) then
  begin
    TouchCmapLookup(Lookup);
  end;
  if Font.TryGetUnicodeCmapLookup(True, Lookup) then
  begin
    TouchCmapLookup(Lookup);
  end;

  Font.Name;
  Font.FontBBox;
  Font.FontMatrix;
  Font.UnitsPerEm;
end;

class procedure TFontProgramProbe.TouchCffType1Font(const Font: TCFFType1Font);
begin
  for var Glyph := 0 to ProbedGlyphs - 1 do
  begin
    Font.GetWidthForGID(Glyph);
  end;
  for var Name in ['A', '.notdef', 'space', 'uni0041', 'nonexistent'] do
  begin
    Font.NameToGID(Name);
  end;
end;

class procedure TFontProgramProbe.TouchCffCIDFont(const Font: TCFFCIDFont);
begin
  for var CID := 0 to ProbedGlyphs - 1 do
  begin
    Font.CIDToGID(CID);
    Font.GetWidthForCID(CID);
  end;
end;

class procedure TFontProgramProbe.TouchCffFont(const Font: TCFFFont);
begin
  Font.Name;
  Font.FontBBox;
  Font.FontMatrix;
  if Font is TCFFType1Font then
  begin
    Font.GetWidth('A');
    Font.HasGlyph('A');
    TouchCffType1Font(TCFFType1Font(Font));
  end
  else if Font is TCFFCIDFont then
  begin
    TouchCffCIDFont(TCFFCIDFont(Font));
  end;
end;

class procedure TFontProgramProbe.TouchCMap(const CMap: TCMap);
begin
  var Value: string;
  for var Code := 0 to ProbedCodes - 1 do
  begin
    CMap.TryToUnicode(Code, Value);
    CMap.TryToUnicode(Code, 2, Value);
    CMap.ToCID(Code);
    CMap.ToCID(Code, 2);
  end;
  CMap.TryToUnicode($4E00, Value);
  CMap.ToCID($FFFF, 2);
  CMap.ToCID(Integer($FFFFFFFF), 4);

  const Data = CodeBytes;
  var Position := 0;
  while Position < Length(Data) do
  begin
    CMap.ReadCode(Data, Position);
  end;
  CMap.TryGetSpaceMapping(Position);
  CMap.HasCIDMappings;
  CMap.HasUnicodeMappings;
end;

class procedure TFontProgramProbe.ParseCMap(const Bytes: TBytes; const IsStrict: Boolean);
begin
  const Parser = TCMapParser.Create(IsStrict);
  try
    const Source = TRandomAccessRead.FromBytes(Bytes);
    try
      const CMap = Parser.Parse(Source);
      try
        TouchCMap(CMap);
      finally
        CMap.Free;
      end;
    finally
      Source.Free;
    end;
  finally
    Parser.Free;
  end;
end;

class procedure TFontProgramProbe.TrueType(const Bytes: TBytes);
begin
  const Parser = TTTFParser.Create(True);
  try
    const Font = Parser.Parse(Bytes);
    try
      TouchTrueTypeFont(Font);
    finally
      Font.Free;
    end;
  finally
    Parser.Free;
  end;
end;

class procedure TFontProgramProbe.OpenType(const Bytes: TBytes);
begin
  const Parser = TOTFParser.Create(True);
  try
    const Font = Parser.Parse(Bytes);
    try
      TouchTrueTypeFont(Font);
      if Font.IsPostScript then
      begin
        TouchCffFont(Font.CFF);
      end;
    finally
      Font.Free;
    end;
  finally
    Parser.Free;
  end;
end;

class procedure TFontProgramProbe.Cff(const Bytes: TBytes);
begin
  const Parser = TCFFParser.Create;
  try
    const Fonts = Parser.Parse(Bytes);
    try
      for var Font in Fonts do
      begin
        TouchCffFont(Font);
      end;
    finally
      Fonts.Free;
    end;
  finally
    Parser.Free;
  end;
end;

class procedure TFontProgramProbe.Type1(const Bytes: TBytes);
begin
  const Font = TType1Font.CreateWithPFB(Bytes);
  try
    Font.FontBBox;
    Font.FontMatrix;
    Font.FontName;
    for var Name in ['A', '.notdef', 'space', 'uni0041', 'nonexistent'] do
    begin
      Font.GetWidth(Name);
      Font.HasGlyph(Name);
    end;
    for var Code := 0 to 255 do
    begin
      Font.Encoding.GetName(Code);
    end;
  finally
    Font.Free;
  end;
end;

class procedure TFontProgramProbe.CMap(const Bytes: TBytes);
begin
  ParseCMap(Bytes, False);
  ParseCMap(Bytes, True);
end;

class procedure TFontProgramProbe.TouchFont(const Font: TPDFont);
begin
  var Value: string;
  for var Code := 0 to ProbedCodes - 1 do
  begin
    Font.GetWidth(Code);
    Font.GetWidthFromFont(Code);
    Font.HasExplicitWidth(Code);
    Font.GetDisplacement(Code);
    Font.TryToUnicode(Code, Value);
  end;
  Font.TryToUnicode($FFFF, Value);

  const Data = CodeBytes;
  var Position := 0;
  while Position < Length(Data) do
  begin
    Font.ReadCode(Data, Position);
  end;

  Font.GetSpaceWidth;
  Font.GetAverageFontWidth;
  Font.GetFontMatrix;
  Font.GetBoundingBox;
end;

class procedure TFontProgramProbe.FontClasses(const Bytes: TBytes);
begin
  const Document = TPDDocument.Load(TBytesStream.Create(Bytes), True, TPdfLoadOptions.Default);
  try
    const Dictionary = TTextTestDocuments.FontDictionary(Document, ProbedFontKey);
    TouchFont(TPDFontFactory.GetFont(Dictionary, Document.Context));
  finally
    Document.Free;
  end;
end;

{ TMutator }

class procedure TMutator.Overwrite(var Bytes: TBytes);
begin
  const Count = 1 + Random(MaxOverwriteBytes);
  if Length(Bytes) < Count then
  begin
    Exit;
  end;

  const Start = Random(Length(Bytes) - Count + 1);
  for var Index := Start to Start + Count - 1 do
  begin
    Bytes[Index] := Random(256);
  end;
end;

class procedure TMutator.DuplicateBlock(var Bytes: TBytes);
begin
  if Length(Bytes) = 0 then
  begin
    Exit;
  end;

  const Count = 1 + Random(Min(Length(Bytes), MaxDuplicatedBytes));
  const Start = Random(Length(Bytes) - Count + 1);
  const Target = Random(Length(Bytes) + 1);
  const Block = Copy(Bytes, Start, Count);
  Insert(Block, Bytes, Target);
end;

// The position of the last character before every "obj" that follows digits (the generation number)
class function TMutator.ObjectHeaderPositions(const Bytes: TBytes): TArray<Integer>;
begin
  Result := nil;
  for var Index := 2 to Length(Bytes) - Length(ObjectKeyword) do
  begin
    const IsKeyword = (Bytes[Index] = Ord('o')) and (Bytes[Index + 1] = Ord('b')) and (Bytes[Index + 2] = Ord('j'));
    if IsKeyword and (Bytes[Index - 1] = Ord(' ')) and (Bytes[Index - 2] in [Ord('0')..Ord('9')]) then
    begin
      Result := Result + [Index - 2];
    end;
  end;
end;

class procedure TMutator.ChangeObjectHeader(var Bytes: TBytes);
begin
  const Positions = ObjectHeaderPositions(Bytes);
  if Length(Positions) = 0 then
  begin
    Overwrite(Bytes);
    Exit;
  end;

  // Changes one digit of "<number> <generation> obj": the generation or one of the digits of the number before it
  var Position := Positions[Random(Length(Positions))];
  var Back := Random(6);
  while (Back > 0) and (Position > 0) and (Bytes[Position - 1] in [Ord('0')..Ord('9'), Ord(' ')]) do
  begin
    Dec(Position);
    Dec(Back);
  end;
  if Bytes[Position] in [Ord('0')..Ord('9')] then
  begin
    Bytes[Position] := Ord('0') + Random(10);
  end;
end;

class function TMutator.Mutate(const Source: TBytes; const Kind: TMutationKind): TBytes;
begin
  Result := Copy(Source);
  case Kind of
    TMutationKind.OverwriteBytes:
      Overwrite(Result);
    TMutationKind.Truncate:
      SetLength(Result, Random(Length(Result) + 1));
    TMutationKind.DuplicateBlock:
      DuplicateBlock(Result);
    TMutationKind.ChangeObjectHeader:
      ChangeObjectHeader(Result);
  else
    raise EArgumentOutOfRangeException.Create('Unknown mutation kind');
  end;
end;

{ TMutationRun }

constructor TMutationRun.Create(const Bytes: TBytes; const Password: string);
begin
  Create(Bytes, Password, TFuzzWork.Structure);
end;

constructor TMutationRun.Create(const Bytes: TBytes; const Password: string; const Work: TFuzzWork);
begin
  FBytes := Bytes;
  FPassword := Password;
  FWork := Work;
  FFinished := TEvent.Create(nil, True, False, '');
end;

destructor TMutationRun.Destroy;
begin
  // The worker may still be inside SetEvent when the wait returns: wait until the thread has ended before the event goes
  if Assigned(FWorker) then
  begin
    FWorker.WaitFor;
    FWorker.Free;
  end;
  FFinished.Free;
  inherited;
end;

procedure TMutationRun.DoWork;
begin
  case FWork of
    TFuzzWork.Structure, TFuzzWork.Text:
    begin
      var Options := TPdfLoadOptions.Default;
      Options.Password := FPassword;
      const Stream = TBytesStream.Create(FBytes);
      try
        const Document: IPdfDocument = TPdfDocument.Load(Stream, Options);
        TStructureDump.Dump(Document, True);
        if FWork = TFuzzWork.Text then
        begin
          TTextDump.Dump(Document, True);
        end;
      finally
        Stream.Free;
      end;
    end;
    TFuzzWork.PageText, TFuzzWork.LimitedPageText:
    begin
      var Options := TPdfLoadOptions.Default;
      if FWork = TFuzzWork.LimitedPageText then
      begin
        Options.MaxOperatorsPerPage := LimitedOperatorBudget;
        Options.MaxGlyphsPerPage := LimitedGlyphBudget;
      end;
      const Stream = TBytesStream.Create(FBytes);
      try
        const Document: IPdfDocument = TPdfDocument.Load(Stream, Options);
        TTextDump.Dump(Document, True);
      finally
        Stream.Free;
      end;
    end;
    TFuzzWork.TrueTypeProgram: TFontProgramProbe.TrueType(FBytes);
    TFuzzWork.OpenTypeProgram: TFontProgramProbe.OpenType(FBytes);
    TFuzzWork.CffProgram: TFontProgramProbe.Cff(FBytes);
    TFuzzWork.Type1Program: TFontProgramProbe.Type1(FBytes);
    TFuzzWork.CMapProgram: TFontProgramProbe.CMap(FBytes);
    TFuzzWork.FontClasses: TFontProgramProbe.FontClasses(FBytes);
  else
    raise EArgumentOutOfRangeException.Create('Unknown fuzz work');
  end;
end;

procedure TMutationRun.Execute;
begin
  FOutcome.Failure := '';
  FOutcome.IsPdfException := False;
  try
    DoWork;
  except
    on Failure: Exception do
    begin
      FOutcome.Failure := Failure.ClassName + ': ' + Failure.Message;
      FOutcome.IsPdfException := Failure is EPdfException;
    end;
  end;
end;

function TMutationRun.RunHere: TMutationOutcome;
begin
  Execute;
  Result := FOutcome;
end;

function TMutationRun.RunWithin(const Milliseconds: Cardinal; out Outcome: TMutationOutcome): Boolean;
begin
  FFinished.ResetEvent;
  FWorker := TThread.CreateAnonymousThread(
    procedure
    begin
      Execute;
      FFinished.SetEvent;
    end);
  // The run owns the thread object, so it is never freed while it can still signal
  FWorker.FreeOnTerminate := False;
  FWorker.Start;

  Result := FFinished.WaitFor(Milliseconds) = wrSignaled;
  if Result then
  begin
    Outcome := FOutcome;
  end;
end;

{ TFuzzSettings }

class function TFuzzSettings.SeedOffset: Integer;
begin
  Result := StrToIntDef(GetEnvironmentVariable(SeedEnvironmentVariable), 0);
end;

class function TFuzzSettings.TimeLimitSeconds: Integer;
begin
  Result := Max(1, StrToIntDef(GetEnvironmentVariable(SecondsEnvironmentVariable), MaxMutationSeconds));
end;

class function TFuzzSettings.TraceFile: string;
begin
  Result := GetEnvironmentVariable(TraceEnvironmentVariable);
end;

class function TFuzzSettings.Scale(const Count: Integer): Integer;
begin
  Result := Count * Max(1, StrToIntDef(GetEnvironmentVariable(ScaleEnvironmentVariable), 1));
end;

{ TFuzzCampaign }

constructor TFuzzCampaign.Create;
begin
  inherited Create;
  FFailures := TList<string>.Create;
end;

destructor TFuzzCampaign.Destroy;
begin
  FFailures.Free;
  inherited;
end;

class procedure TFuzzCampaign.SaveFailure(const Name: string; const Bytes: TBytes);
begin
  const Folder = GetEnvironmentVariable(OutputEnvironmentVariable);
  if Folder <> '' then
  begin
    TDirectory.CreateDirectory(Folder);
    TFile.WriteAllBytes(TPath.Combine(Folder, TPath.GetFileNameWithoutExtension(Name.Replace('/', '__').Replace(' ', '_')) + '.bin'), Bytes);
  end;
end;

class procedure TFuzzCampaign.Trace(const Name: string; const Milliseconds: Int64; const Failure: string);
begin
  const FileName = TFuzzSettings.TraceFile;
  if FileName <> '' then
  begin
    TFile.AppendAllText(FileName, Format('%d'#9'%s'#9'%s', [Milliseconds, Name, Copy(Failure, 1, 80)]) + sLineBreak);
  end;
end;

procedure TFuzzCampaign.Run(const Name: string; const Bytes: TBytes; const Password: string; const Work: TFuzzWork);
begin
  const Job = TMutationRun.Create(Bytes, Password, Work);
  var Outcome: TMutationOutcome;
  const Watch = TStopwatch.StartNew;
  const Finished = Job.RunWithin(TFuzzSettings.TimeLimitSeconds * 1000, Outcome);

  if not Finished then
  begin
    Trace(Name, Watch.ElapsedMilliseconds, 'no result');
    // The worker may still use the run, so it is not freed
    FFailures.Add(Format('%s: no result after %d s', [Name, TFuzzSettings.TimeLimitSeconds]));
    SaveFailure(Name, Bytes);
    Exit;
  end;
  Job.Free;
  Trace(Name, Watch.ElapsedMilliseconds, Outcome.Failure);

  if (Outcome.Failure <> '') and not Outcome.IsPdfException then
  begin
    FFailures.Add(Format('%s: %s', [Name, Outcome.Failure]));
    SaveFailure(Name, Bytes);
  end
  else if (Watch.ElapsedMilliseconds > TFuzzSettings.TimeLimitSeconds * 1000) then
  begin
    FFailures.Add(Format('%s: took %d ms', [Name, Watch.ElapsedMilliseconds]));
  end;
end;

procedure TFuzzCampaign.AssertNoFailures;
begin
  if FFailures.Count > 0 then
  begin
    const Reported = Copy(FFailures.ToArray, 0, MaxReportedFailures);
    Assert.Fail(Format('%d of the runs failed, the first %d:%s%s',
                       [FFailures.Count, Length(Reported), sLineBreak, string.Join(sLineBreak, Reported)]));
  end;
end;

class procedure TFuzzCampaign.RunMutatedCorpus(const Work: TFuzzWork);
const
  KindNames: array[TMutationKind] of string = ('overwrite', 'truncate', 'duplicate', 'object-header');
begin
  const Files = TCorpus.Files;
  if Length(Files) = 0 then
  begin
    Assert.Fail('The corpus was not found: set PDF4D_CORPUS or run the test program below the tests folder');
  end;

  const Campaign = TFuzzCampaign.Create;
  try
    for var FileIndex := 0 to Min(TFuzzSettings.Scale(FileCount), Length(Files)) - 1 do
    begin
      const FileName = Files[FileIndex];
      const Source = TFile.ReadAllBytes(TCorpus.PdfPath(FileName));
      const Password = TCorpus.PasswordFor(FileName);
      const FileSeed = Seed + TFuzzSettings.SeedOffset + FileIndex;
      RandSeed := FileSeed;

      for var Index := 0 to TFuzzSettings.Scale(MutationsPerFile) - 1 do
      begin
        const Kind = TMutationKind(Index mod (Ord(High(TMutationKind)) + 1));
        const Mutated = TMutator.Mutate(Source, Kind);
        Campaign.Run(Format('%s seed %d mutation %d (%s)', [FileName, FileSeed, Index, KindNames[Kind]]), Mutated, Password, Work);
      end;
    end;
    Campaign.AssertNoFailures;
  finally
    Campaign.Free;
  end;
end;

{ TRobustnessTests }

procedure TRobustnessTests.TestMutatedCorpusFailsCleanlyInTime;
begin
  TFuzzCampaign.RunMutatedCorpus(TFuzzWork.Structure);
end;

procedure TRobustnessTests.TestAllCorpusFilesLoadWithoutLeak;
begin
  const Files = TCorpus.Files;
  if Length(Files) = 0 then
  begin
    Assert.Fail('The corpus was not found: set PDF4D_CORPUS or run the test program below the tests folder');
  end;

  for var FileName in Files do
  begin
    const Run = TMutationRun.Create(TFile.ReadAllBytes(TCorpus.PdfPath(FileName)), TCorpus.PasswordFor(FileName));
    try
      const Outcome = Run.RunHere;
      // Files that PDFBox cannot open either end in a PDF exception
      if (Outcome.Failure <> '') and not Outcome.IsPdfException then
      begin
        Assert.Fail(Format('%s: %s', [FileName, Outcome.Failure]));
      end;
    finally
      Run.Free;
    end;
  end;
end;

end.
