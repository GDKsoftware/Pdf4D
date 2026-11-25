// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
program Pdf4D.Skia.Tests;

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
  Pdf4D.Common.FloatGuard in '..\..\src\Common\Pdf4D.Common.FloatGuard.pas',
  Pdf4D.Common.Matrix in '..\..\src\Common\Pdf4D.Common.Matrix.pas',
  Pdf4D.Common.Path in '..\..\src\Common\Pdf4D.Common.Path.pas',
  Pdf4D.Render.Bitmap in '..\..\src\Render\Pdf4D.Render.Bitmap.pas',
  Pdf4D.Render.Device.Interfaces in '..\..\src\Render\Pdf4D.Render.Device.Interfaces.pas',
  Pdf4D.Render.ClipPath in '..\..\src\Render\Pdf4D.Render.ClipPath.pas',
  Pdf4D.Render.Skia.Convert in '..\..\src\Render\Skia\Pdf4D.Render.Skia.Convert.pas',
  Pdf4D.Render.Skia.Device in '..\..\src\Render\Skia\Pdf4D.Render.Skia.Device.pas',
  Pdf4D.Render.Skia.Backend in '..\..\src\Render\Skia\Pdf4D.Render.Skia.Backend.pas',
  Pdf4D.Tests.DeviceContract in '..\Support\Pdf4D.Tests.DeviceContract.pas',
  Pdf4D.Render.Skia.Device.Tests in'..\..\src\Render\Skia\Pdf4D.Render.Skia.Device.Tests.pas',
  Pdf4D.Tests.Png in '..\Support\Pdf4D.Tests.Png.pas',
  Pdf4D.Tests.RenderCompare in '..\Support\Pdf4D.Tests.RenderCompare.pas',
  Pdf4D.Tests.RenderCompare.Tests in '..\Support\Pdf4D.Tests.RenderCompare.Tests.pas',
  Pdf4D.Tests.ReferenceBackends in 'Acceptance\Pdf4D.Tests.ReferenceBackends.pas',
  Pdf4D.Tests.Corpus in '..\Support\Pdf4D.Tests.Corpus.pas',
  Pdf4D.Tests.FontProvider in '..\Support\Pdf4D.Tests.FontProvider.pas',
  Pdf4D.Tests.TextGolden in '..\Support\Pdf4D.Tests.TextGolden.pas',
  Pdf4D.Tests.RenderGolden.Tests in 'Acceptance\Pdf4D.Tests.RenderGolden.Tests.pas',
  Pdf4D.Tests.RenderGroups.Tests in 'Acceptance\Pdf4D.Tests.RenderGroups.Tests.pas',
  Pdf4D.Tests.RenderSoftMasks.Tests in 'Acceptance\Pdf4D.Tests.RenderSoftMasks.Tests.pas',
  Pdf4D.Tests.RenderTiling.Tests in 'Acceptance\Pdf4D.Tests.RenderTiling.Tests.pas',
  Pdf4D.Tests.Fuzz in '..\Support\Pdf4D.Tests.Fuzz.pas',
  Pdf4D.Tests.RenderRobustness.Tests in 'Acceptance\Pdf4D.Tests.RenderRobustness.Tests.pas',
  Pdf4D.Tests.RenderPerformance.Tests in 'Acceptance\Pdf4D.Tests.RenderPerformance.Tests.pas';

const
  ExitCodeTestsFailed = 1;
  ExitCodeMemoryLeak  = 2;

  // The mask that Delphi starts with; System.Skia (SkInitialize) masks every floating point exception process-wide
  DelphiDefaultExceptionMask: TArithmeticExceptionMask = [exDenormalized, exUnderflow, exPrecision];

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

  SetExceptionMask(DelphiDefaultExceptionMask);
  TMemoryCheck.Install;

  ExitCode := 0;
  try
    TDUnitX.CheckCommandLine;
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
