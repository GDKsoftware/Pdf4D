program Pdf4D.Tests;

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  System.IOUtils,
  DUnitX.Loggers.Console,
  DUnitX.Loggers.XML.NUnit,
  DUnitX.TestFramework,
  Pdf4D.Tests.MemoryCheck in 'Pdf4D.Tests.MemoryCheck.pas',
  Pdf4D.Common.Log.Tests in '..\src\Common\Pdf4D.Common.Log.Tests.pas',
  Pdf4D.IO.RandomAccessRead.Tests in '..\src\IO\Pdf4D.IO.RandomAccessRead.Tests.pas';

const
  ExitCodeTestsFailed = 1;
  ExitCodeMemoryLeak  = 2;

function PlatformName: string;
begin
  {$IF Defined(LINUX64)}
  Result := 'Linux64';
  {$ELSEIF Defined(WIN64)}
  Result := 'Win64';
  {$ELSEIF Defined(MSWINDOWS)}
  Result := 'Win32';
  {$ELSE}
  Result := 'Other';
  {$ENDIF}
end;

function ResultsFileName: string;
begin
  const BinaryFolder = TPath.GetDirectoryName(ParamStr(0));
  const TestsFolder = TPath.GetFullPath(TPath.Combine(BinaryFolder, '..' + PathDelim + '..'));
  Result := TPath.Combine(TestsFolder, Format('results-%s.xml', [PlatformName]));
end;

function RunTests: Boolean;
begin
  const Runner = TDUnitX.CreateRunner;
  Runner.UseRTTI := True;
  Runner.AddLogger(TDUnitXConsoleLogger.Create(True));
  Runner.AddLogger(TDUnitXXMLNUnitFileLogger.Create(ResultsFileName));

  const RunResults = Runner.Execute;
  Result := RunResults.AllPassed;
end;

begin
  {$IFDEF DEBUG}
  ReportMemoryLeaksOnShutdown := True;
  {$ENDIF}

  TMemoryCheck.Install;

  ExitCode := 0;
  try
    // The first run initializes DUnitX's global registries and loggers; leaks are measured on the second run.
    const WarmupPassed = RunTests;
    const Baseline = TMemoryCheck.OutstandingBlocks;
    const AllPassed = RunTests and WarmupPassed;
    const HasLeak = (TMemoryCheck.OutstandingBlocks <> Baseline);

    if not AllPassed then
    begin
      ExitCode := ExitCodeTestsFailed;
    end
    else if HasLeak then
    begin
      Writeln('Memory leak detected: allocations outstanding after the run.');
      ExitCode := ExitCodeMemoryLeak;
    end;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := ExitCodeTestsFailed;
    end;
  end;
end.
