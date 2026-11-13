unit Pdf4D.Tests.Robustness.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
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

  // Loads the bytes and dumps the whole structure; used on the calling thread or on a worker thread
  TMutationRun = class
  strict private
    FBytes: TBytes;
    FPassword: string;
    FFinished: TEvent;
    FOutcome: TMutationOutcome;
    procedure Execute;

  public
    constructor Create(const Bytes: TBytes; const Password: string);
    destructor Destroy; override;

    // Runs on the calling thread
    function RunHere: TMutationOutcome;
    // Runs on a worker thread. False when it did not finish within the time: the thread then keeps running, a hang cannot be stopped.
    function RunWithin(const Milliseconds: Cardinal; out Outcome: TMutationOutcome): Boolean;
  end;

  [TestFixture]
  TRobustnessTests = class
  strict private
    class function MutationName(const FileName: string; const Index: Integer; const Kind: TMutationKind): string; static;
    class procedure SaveFailure(const Name: string; const Bytes: TBytes); static;

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
  Pdf4D.Tests.Corpus,
  Pdf4D.Tests.StructureDump;

const
  Seed = 1234;
  FileCount = 50;
  MutationsPerFile = 20;
  MaxMutationSeconds = 10;
  MaxOverwriteBytes = 64;
  MaxDuplicatedBytes = 4096;
  MaxReportedFailures = 20;
  OutputEnvironmentVariable = 'PDF4D_ROBUSTNESS_OUTPUT';
  ObjectKeyword = 'obj';

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
  FBytes := Bytes;
  FPassword := Password;
  FFinished := TEvent.Create(nil, True, False, '');
end;

destructor TMutationRun.Destroy;
begin
  FFinished.Free;
  inherited;
end;

procedure TMutationRun.Execute;
begin
  FOutcome.Failure := '';
  FOutcome.IsPdfException := False;
  try
    var Options := TPdfLoadOptions.Default;
    Options.Password := FPassword;
    const Stream = TBytesStream.Create(FBytes);
    try
      const Document: IPdfDocument = TPdfDocument.Load(Stream, Options);
      TStructureDump.Dump(Document, True);
    finally
      Stream.Free;
    end;
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
  TThread.CreateAnonymousThread(
    procedure
    begin
      Execute;
      FFinished.SetEvent;
    end).Start;

  Result := FFinished.WaitFor(Milliseconds) = wrSignaled;
  if Result then
  begin
    Outcome := FOutcome;
  end;
end;

{ TRobustnessTests }

class function TRobustnessTests.MutationName(const FileName: string; const Index: Integer; const Kind: TMutationKind): string;
const
  KindNames: array[TMutationKind] of string = ('overwrite', 'truncate', 'duplicate', 'object-header');
begin
  Result := Format('%s mutation %d (%s)', [FileName, Index, KindNames[Kind]]);
end;

// For looking at a failure: the mutated file goes to the folder in PDF4D_ROBUSTNESS_OUTPUT
class procedure TRobustnessTests.SaveFailure(const Name: string; const Bytes: TBytes);
begin
  const Folder = GetEnvironmentVariable(OutputEnvironmentVariable);
  if Folder <> '' then
  begin
    TDirectory.CreateDirectory(Folder);
    TFile.WriteAllBytes(TPath.Combine(Folder, TPath.GetFileNameWithoutExtension(Name.Replace('/', '__').Replace(' ', '_')) + '.pdf'), Bytes);
  end;
end;

procedure TRobustnessTests.TestMutatedCorpusFailsCleanlyInTime;
begin
  const Files = TCorpus.Files;
  if Length(Files) = 0 then
  begin
    Assert.Fail('The corpus was not found: set PDF4D_CORPUS or run the test program below the tests folder');
  end;

  var Failures: TArray<string> := nil;
  for var FileIndex := 0 to Min(FileCount, Length(Files)) - 1 do
  begin
    const FileName = Files[FileIndex];
    const Source = TFile.ReadAllBytes(TCorpus.PdfPath(FileName));
    const Password = TCorpus.PasswordFor(FileName);
    RandSeed := Seed + FileIndex;

    for var Index := 0 to MutationsPerFile - 1 do
    begin
      const Kind = TMutationKind(Index mod (Ord(High(TMutationKind)) + 1));
      const Mutated = TMutator.Mutate(Source, Kind);
      const Name = MutationName(FileName, Index, Kind);
      const Run = TMutationRun.Create(Mutated, Password);
      var Outcome: TMutationOutcome;
      const Watch = TStopwatch.StartNew;
      const Finished = Run.RunWithin(MaxMutationSeconds * 1000, Outcome);

      if not Finished then
      begin
        // The worker may still use the run, so it is not freed
        Failures := Failures + [Format('%s: no result after %d s', [Name, MaxMutationSeconds])];
        SaveFailure(Name, Mutated);
        Continue;
      end;
      Run.Free;

      if (Outcome.Failure <> '') and not Outcome.IsPdfException then
      begin
        Failures := Failures + [Format('%s: %s', [Name, Outcome.Failure])];
        SaveFailure(Name, Mutated);
      end
      else if (Watch.ElapsedMilliseconds > MaxMutationSeconds * 1000) then
      begin
        Failures := Failures + [Format('%s: took %d ms', [Name, Watch.ElapsedMilliseconds])];
      end;
    end;
  end;

  if Length(Failures) > 0 then
  begin
    const Reported = Copy(Failures, 0, MaxReportedFailures);
    Assert.Fail(Format('%d of the mutations failed, the first %d:%s%s',
                       [Length(Failures), Length(Reported), sLineBreak, string.Join(sLineBreak, Reported)]));
  end;
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
