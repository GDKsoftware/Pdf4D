// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
program Pdf4D.FMX.Tests;

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  System.Math,
  System.IOUtils,
  FMX.Forms,
  DUnitX.Loggers.Console,
  DUnitX.Loggers.XML.NUnit,
  DUnitX.TestFramework,
  Pdf4D.Tests.MemoryCheck in '..\Pdf4D.Tests.MemoryCheck.pas',
  Pdf4D.Tests.FmxHost in 'Support\Pdf4D.Tests.FmxHost.pas',
  Pdf4D.FMX.Painter in '..\..\src\FMX\Pdf4D.FMX.Painter.pas',
  Pdf4D.FMX.Document in '..\..\src\FMX\Pdf4D.FMX.Document.pas',
  Pdf4D.FMX.Backend.Skia in '..\..\src\FMX\Skia\Pdf4D.FMX.Backend.Skia.pas',
  Pdf4D.Tests.FmxHost.Tests in 'Support\Pdf4D.Tests.FmxHost.Tests.pas',
  Pdf4D.FMX.Painter.Tests in '..\..\src\FMX\Pdf4D.FMX.Painter.Tests.pas',
  Pdf4D.FMX.Document.Tests in '..\..\src\FMX\Pdf4D.FMX.Document.Tests.pas';

const
  ExitCodeTestsFailed = 1;
  ExitCodeMemoryLeak  = 2;

  // FMX on Windows keeps one small block (56 bytes) for every window it made, and lets go of them all when a count of this many has built up
  // (found with a program that only makes and frees TForm: the count of blocks rises by one per window and falls by fifteen on the sixteenth)
  WindowBatch = 16;

  // The mask that Delphi starts with; System.Skia (SkInitialize) masks every floating point exception process-wide
  DelphiDefaultExceptionMask: TArithmeticExceptionMask = [exDenormalized, exUnderflow, exPrecision];

function PlatformName: string;
begin
  {$IF Defined(WIN64)}
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

// Whether the blocks that are outstanding after a run, compared with before it, are more than the windows of that run explain. The windows
// that were made are counted by TFmxTestHost; which of the sixteen places in the batch the run started at is not known, so the difference
// is either the number of windows in the batch that the run added, or that number less one batch.
function HasLeakBeyondWindows(const BlocksAdded: NativeInt; const WindowsMade: Integer): Boolean;
begin
  const Pending = WindowsMade mod WindowBatch;
  Result := (BlocksAdded <> Pending) and (BlocksAdded <> Pending - WindowBatch);
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

  SetExceptionMask(DelphiDefaultExceptionMask);
  TMemoryCheck.Install;

  ExitCode := 0;
  try
    TDUnitX.CheckCommandLine;
    // The first run initializes DUnitX's global registries, the FMX platform services and the canvas; leaks are measured on the second run.
    const WarmupPassed = RunTests;
    const Baseline = TMemoryCheck.OutstandingBlocks;
    const WindowsBefore = TFmxTestHost.WindowsMade;
    const AllPassed = RunTests and WarmupPassed;
    const HasLeak = HasLeakBeyondWindows(TMemoryCheck.OutstandingBlocks - Baseline, TFmxTestHost.WindowsMade - WindowsBefore);

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
