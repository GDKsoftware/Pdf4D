// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
program Pdf4D.Vcl.Tests;

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  System.Math,
  System.IOUtils,
  DUnitX.Loggers.Console,
  DUnitX.Loggers.XML.NUnit,
  DUnitX.TestFramework,
  Pdf4D.Tests.MemoryCheck in '..\Pdf4D.Tests.MemoryCheck.pas',
  Pdf4D.Tests.VclHost in 'Support\Pdf4D.Tests.VclHost.pas',
  Pdf4D.Vcl.Painter in '..\..\src\Vcl\Pdf4D.Vcl.Painter.pas',
  Pdf4D.Vcl.ViewSupport in '..\..\src\Vcl\Pdf4D.Vcl.ViewSupport.pas',
  Pdf4D.Vcl.Document in '..\..\src\Vcl\Pdf4D.Vcl.Document.pas',
  Pdf4D.Vcl.PageView in '..\..\src\Vcl\Pdf4D.Vcl.PageView.pas',
  Pdf4D.Vcl.Thumbnails in '..\..\src\Vcl\Pdf4D.Vcl.Thumbnails.pas',
  Pdf4D.Vcl.OutlineView in '..\..\src\Vcl\Pdf4D.Vcl.OutlineView.pas',
  Pdf4D.Vcl.SearchBar in '..\..\src\Vcl\Pdf4D.Vcl.SearchBar.pas',
  Pdf4D.Vcl.Actions in '..\..\src\Vcl\Pdf4D.Vcl.Actions.pas',
  Pdf4D.Vcl.Toolbar in '..\..\src\Vcl\Pdf4D.Vcl.Toolbar.pas',
  Pdf4D.Vcl.Print in '..\..\src\Vcl\Pdf4D.Vcl.Print.pas',
  Pdf4D.Vcl.PrintDialog in '..\..\src\Vcl\Pdf4D.Vcl.PrintDialog.pas',
  Pdf4D.Vcl.Viewer in '..\..\src\Vcl\Pdf4D.Vcl.Viewer.pas',
  Pdf4D.Tests.BitmapPrintTarget in 'Support\Pdf4D.Tests.BitmapPrintTarget.pas',
  Pdf4D.Vcl.Backend.Skia in '..\..\src\Vcl\Skia\Pdf4D.Vcl.Backend.Skia.pas',
  Pdf4D.Vcl.Painter.Tests in '..\..\src\Vcl\Pdf4D.Vcl.Painter.Tests.pas',
  Pdf4D.Vcl.PageView.Tests in '..\..\src\Vcl\Pdf4D.Vcl.PageView.Tests.pas',
  Pdf4D.Vcl.Thumbnails.Tests in '..\..\src\Vcl\Pdf4D.Vcl.Thumbnails.Tests.pas',
  Pdf4D.Vcl.OutlineView.Tests in '..\..\src\Vcl\Pdf4D.Vcl.OutlineView.Tests.pas',
  Pdf4D.Vcl.SearchBar.Tests in '..\..\src\Vcl\Pdf4D.Vcl.SearchBar.Tests.pas',
  Pdf4D.Vcl.Actions.Tests in '..\..\src\Vcl\Pdf4D.Vcl.Actions.Tests.pas',
  Pdf4D.Vcl.Toolbar.Tests in '..\..\src\Vcl\Pdf4D.Vcl.Toolbar.Tests.pas',
  Pdf4D.Vcl.Print.Tests in '..\..\src\Vcl\Pdf4D.Vcl.Print.Tests.pas',
  Pdf4D.Vcl.PrintDialog.Tests in '..\..\src\Vcl\Pdf4D.Vcl.PrintDialog.Tests.pas',
  Pdf4D.Vcl.Viewer.Tests in '..\..\src\Vcl\Pdf4D.Vcl.Viewer.Tests.pas',
  Pdf4D.Vcl.Streaming.Tests in '..\..\src\Vcl\Pdf4D.Vcl.Streaming.Tests.pas',
  Pdf4D.Tests.VclViewerFlows.Tests in 'Acceptance\Pdf4D.Tests.VclViewerFlows.Tests.pas',
  Pdf4D.Tests.VclPerformance.Tests in 'Acceptance\Pdf4D.Tests.VclPerformance.Tests.pas';

const
  ExitCodeTestsFailed = 1;
  ExitCodeMemoryLeak  = 2;

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

// The first run writes results-<platform>-pass1.xml, the second results-<platform>.xml, so that a failure of the first run stays visible
const
  Pass1Suffix = '-pass1';

function ResultsFileName(const Suffix: string): string;
begin
  const BinaryFolder = TPath.GetDirectoryName(ParamStr(0));
  const TestsFolder = TPath.GetFullPath(TPath.Combine(BinaryFolder, '..' + PathDelim + '..'));
  Result := TPath.Combine(TestsFolder, Format('results-%s%s.xml', [PlatformName, Suffix]));
end;

function RunTests(const ResultsSuffix: string): Boolean;
begin
  const Runner = TDUnitX.CreateRunner;
  Runner.UseRTTI := True;
  Runner.AddLogger(TDUnitXConsoleLogger.Create(True));
  Runner.AddLogger(TDUnitXXMLNUnitFileLogger.Create(ResultsFileName(ResultsSuffix)));

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
    // The first run initializes DUnitX's global registries, the VCL application and GDI+; leaks are measured on the second run.
    const WarmupPassed = RunTests(Pass1Suffix);
    const Baseline = TMemoryCheck.OutstandingBlocks;
    const AllPassed = RunTests('') and WarmupPassed;
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
