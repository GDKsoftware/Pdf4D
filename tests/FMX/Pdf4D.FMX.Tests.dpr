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
  Pdf4D.Tests.FmxBitmapPrintTarget in 'Support\Pdf4D.Tests.FmxBitmapPrintTarget.pas',
  Pdf4D.FMX.Painter in '..\..\src\FMX\Pdf4D.FMX.Painter.pas',
  Pdf4D.FMX.Document in '..\..\src\FMX\Pdf4D.FMX.Document.pas',
  Pdf4D.FMX.PageView in '..\..\src\FMX\Pdf4D.FMX.PageView.pas',
  Pdf4D.FMX.ViewSupport in '..\..\src\FMX\Pdf4D.FMX.ViewSupport.pas',
  Pdf4D.FMX.Thumbnails in '..\..\src\FMX\Pdf4D.FMX.Thumbnails.pas',
  Pdf4D.FMX.OutlineView in '..\..\src\FMX\Pdf4D.FMX.OutlineView.pas',
  Pdf4D.FMX.SearchBar in '..\..\src\FMX\Pdf4D.FMX.SearchBar.pas',
  Pdf4D.FMX.Print in '..\..\src\FMX\Pdf4D.FMX.Print.pas',
  Pdf4D.FMX.PrintDialog in '..\..\src\FMX\Pdf4D.FMX.PrintDialog.pas',
  Pdf4D.FMX.Actions in '..\..\src\FMX\Pdf4D.FMX.Actions.pas',
  Pdf4D.FMX.Toolbar in '..\..\src\FMX\Pdf4D.FMX.Toolbar.pas',
  Pdf4D.FMX.Backend.Skia in '..\..\src\FMX\Skia\Pdf4D.FMX.Backend.Skia.pas',
  Pdf4D.Tests.FmxHost.Tests in 'Support\Pdf4D.Tests.FmxHost.Tests.pas',
  Pdf4D.FMX.Painter.Tests in '..\..\src\FMX\Pdf4D.FMX.Painter.Tests.pas',
  Pdf4D.FMX.Document.Tests in '..\..\src\FMX\Pdf4D.FMX.Document.Tests.pas',
  Pdf4D.FMX.PageView.Tests in '..\..\src\FMX\Pdf4D.FMX.PageView.Tests.pas',
  Pdf4D.FMX.Thumbnails.Tests in '..\..\src\FMX\Pdf4D.FMX.Thumbnails.Tests.pas',
  Pdf4D.FMX.OutlineView.Tests in '..\..\src\FMX\Pdf4D.FMX.OutlineView.Tests.pas',
  Pdf4D.FMX.SearchBar.Tests in '..\..\src\FMX\Pdf4D.FMX.SearchBar.Tests.pas',
  Pdf4D.FMX.Actions.Tests in '..\..\src\FMX\Pdf4D.FMX.Actions.Tests.pas',
  Pdf4D.FMX.Toolbar.Tests in '..\..\src\FMX\Pdf4D.FMX.Toolbar.Tests.pas',
  Pdf4D.FMX.Print.Tests in '..\..\src\FMX\Pdf4D.FMX.Print.Tests.pas',
  Pdf4D.FMX.PrintDialog.Tests in '..\..\src\FMX\Pdf4D.FMX.PrintDialog.Tests.pas';

const
  ExitCodeTestsFailed = 1;
  ExitCodeMemoryLeak  = 2;
  ExitCodeMemoryCheckUnreliable = 3;

  // FMX on Windows keeps small blocks for its windows and for some of its controls (a page view with its scroll bars leaves four), and lets
  // go of them all when a count of this many has built up. A bare window adds one block to that count (found with a program that only makes
  // and frees TForm: the count of blocks rises by one per window and falls by fifteen on the sixteenth).
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

// Brings the count of blocks that FMX keeps back to the start of a batch, by making bare windows until the batch is let go: a window adds
// one block, except the one that completes the batch. Outstanding blocks measured before and after such a flush differ only by real leaks.
// False when the flush cannot be trusted. Checked: a release is seen within a batch of windows; then the next batch of windows has the
// pattern that was measured: each of the first WindowBatch - 1 windows adds exactly one block, and the window after those lets the whole
// batch go, which brings the count back to where it was after the first release. Another size of batch, a window that adds no block or a
// drop with another cause fail this. A deferred free of something else that happens to coincide with a window cannot be told apart.
function FlushFmxBlocks: Boolean;
begin
  var IsReleased := False;
  for var Attempt := 1 to WindowBatch do
  begin
    const Before = TMemoryCheck.OutstandingBlocks;
    TForm.CreateNew(nil).Free;
    if TMemoryCheck.OutstandingBlocks < Before then
    begin
      IsReleased := True;
      Break;
    end;
  end;

  const Settled = TMemoryCheck.OutstandingBlocks;
  var IsPatternKept := True;
  for var Window := 1 to WindowBatch do
  begin
    const Before = TMemoryCheck.OutstandingBlocks;
    TForm.CreateNew(nil).Free;
    const After = TMemoryCheck.OutstandingBlocks;
    if Window < WindowBatch then
    begin
      IsPatternKept := IsPatternKept and (After = Before + 1);
    end
    else
    begin
      IsPatternKept := IsPatternKept and (After = Settled);
    end;
  end;
  Result := IsReleased and IsPatternKept;
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
    const IsBaselineTrusted = FlushFmxBlocks;
    const Baseline = TMemoryCheck.OutstandingBlocks;
    const AllPassed = RunTests and WarmupPassed;
    const IsEndTrusted = FlushFmxBlocks;
    const BlocksAdded = TMemoryCheck.OutstandingBlocks - Baseline;
    const HasLeak = (BlocksAdded <> 0);

    if not AllPassed then
    begin
      ExitCode := ExitCodeTestsFailed;
    end
    else if not (IsBaselineTrusted and IsEndTrusted) then
    begin
      Writeln('Memory check not reliable: FMX did not let go of its blocks in the batch of windows that was expected.');
      ExitCode := ExitCodeMemoryCheckUnreliable;
    end
    else if HasLeak then
    begin
      Writeln(Format('Memory leak detected: %d blocks outstanding after the run.', [BlocksAdded]));
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
