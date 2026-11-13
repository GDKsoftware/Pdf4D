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
  Pdf4D.IO.RandomAccessRead.Tests in '..\src\IO\Pdf4D.IO.RandomAccessRead.Tests.pas',
  Pdf4D.Common.Utf8.Tests in '..\src\Common\Pdf4D.Common.Utf8.Tests.pas',
  Pdf4D.Cos.Float.Tests in '..\src\Cos\Pdf4D.Cos.Float.Tests.pas',
  Pdf4D.Cos.Name.Tests in '..\src\Cos\Pdf4D.Cos.Name.Tests.pas',
  Pdf4D.Cos.PdfDocEncoding.Tests in '..\src\Cos\Pdf4D.Cos.PdfDocEncoding.Tests.pas',
  Pdf4D.Cos.PdfString.Tests in '..\src\Cos\Pdf4D.Cos.PdfString.Tests.pas',
  Pdf4D.Cos.Dictionary.Tests in '..\src\Cos\Pdf4D.Cos.Dictionary.Tests.pas',
  Pdf4D.Cos.Document.Tests in '..\src\Cos\Pdf4D.Cos.Document.Tests.pas',
  Pdf4D.Filter.Tests.Support in '..\src\Filter\Pdf4D.Filter.Tests.Support.pas',
  Pdf4D.Filter.Factory.Tests in '..\src\Filter\Pdf4D.Filter.Factory.Tests.pas',
  Pdf4D.Filter.Flate.Tests in '..\src\Filter\Pdf4D.Filter.Flate.Tests.pas',
  Pdf4D.Filter.LZW.Tests in '..\src\Filter\Pdf4D.Filter.LZW.Tests.pas',
  Pdf4D.Filter.ASCII85.Tests in '..\src\Filter\Pdf4D.Filter.ASCII85.Tests.pas',
  Pdf4D.Filter.ASCIIHex.Tests in '..\src\Filter\Pdf4D.Filter.ASCIIHex.Tests.pas',
  Pdf4D.Filter.RunLength.Tests in '..\src\Filter\Pdf4D.Filter.RunLength.Tests.pas',
  Pdf4D.Filter.Predictor.Tests in '..\src\Filter\Pdf4D.Filter.Predictor.Tests.pas',
  Pdf4D.Cos.Stream.Tests in '..\src\Cos\Pdf4D.Cos.Stream.Tests.pas',
  Pdf4D.Parser.Base.Tests in '..\src\Parser\Pdf4D.Parser.Base.Tests.pas',
  Pdf4D.Tests.PdfBuilder in 'Support\Pdf4D.Tests.PdfBuilder.pas',
  Pdf4D.Parser.XrefTrailerResolver.Tests in '..\src\Parser\Pdf4D.Parser.XrefTrailerResolver.Tests.pas',
  Pdf4D.Parser.Xref.Tests in '..\src\Parser\Pdf4D.Parser.Xref.Tests.pas',
  Pdf4D.Parser.ObjectStream.Tests in '..\src\Parser\Pdf4D.Parser.ObjectStream.Tests.pas',
  Pdf4D.Parser.Pdf.Tests in '..\src\Parser\Pdf4D.Parser.Pdf.Tests.pas',
  Pdf4D.Parser.BruteForce.Tests in '..\src\Parser\Pdf4D.Parser.BruteForce.Tests.pas',
  Pdf4D.Crypto.RC4.Tests in '..\src\Crypto\Pdf4D.Crypto.RC4.Tests.pas',
  Pdf4D.Crypto.AES.Tests in '..\src\Crypto\Pdf4D.Crypto.AES.Tests.pas',
  Pdf4D.Encryption.StandardSecurityHandler.Tests in '..\src\Encryption\Pdf4D.Encryption.StandardSecurityHandler.Tests.pas',
  Pdf4D.Encryption.Exemptions.Tests in '..\src\Encryption\Pdf4D.Encryption.Exemptions.Tests.pas',
  Pdf4D.Model.DateConverter in '..\src\Model\Pdf4D.Model.DateConverter.pas',
  Pdf4D.Model.DateConverter.Tests in '..\src\Model\Pdf4D.Model.DateConverter.Tests.pas',
  Pdf4D.Model.Rectangle in '..\src\Model\Pdf4D.Model.Rectangle.pas',
  Pdf4D.Model.Page in '..\src\Model\Pdf4D.Model.Page.pas',
  Pdf4D.Model.PageTree in '..\src\Model\Pdf4D.Model.PageTree.pas',
  Pdf4D.Model.DocumentInformation in '..\src\Model\Pdf4D.Model.DocumentInformation.pas',
  Pdf4D.Model.DocumentCatalog in '..\src\Model\Pdf4D.Model.DocumentCatalog.pas',
  Pdf4D.Model.Document in '..\src\Model\Pdf4D.Model.Document.pas',
  Pdf4D.Model.Tests.Support in '..\src\Model\Pdf4D.Model.Tests.Support.pas',
  Pdf4D.Model.PageTree.Tests in '..\src\Model\Pdf4D.Model.PageTree.Tests.pas',
  Pdf4D.Model.Page.Tests in '..\src\Model\Pdf4D.Model.Page.Tests.pas',
  Pdf4D.Model.Document.Tests in '..\src\Model\Pdf4D.Model.Document.Tests.pas',
  Pdf4D.Model.TreeWalker in '..\src\Model\Pdf4D.Model.TreeWalker.pas',
  Pdf4D.Model.NameTree in '..\src\Model\Pdf4D.Model.NameTree.pas',
  Pdf4D.Model.NumberTree in '..\src\Model\Pdf4D.Model.NumberTree.pas',
  Pdf4D.Model.DestinationResolver in '..\src\Model\Pdf4D.Model.DestinationResolver.pas',
  Pdf4D.Model.Destination in '..\src\Model\Pdf4D.Model.Destination.pas',
  Pdf4D.Model.OutlineItem in '..\src\Model\Pdf4D.Model.OutlineItem.pas',
  Pdf4D.Model.Outline in '..\src\Model\Pdf4D.Model.Outline.pas',
  Pdf4D.Model.PageLabels in '..\src\Model\Pdf4D.Model.PageLabels.pas',
  Pdf4D.Model.EmbeddedFile in '..\src\Model\Pdf4D.Model.EmbeddedFile.pas',
  Pdf4D.Model.Field in '..\src\Model\Pdf4D.Model.Field.pas',
  Pdf4D.Model.AcroForm in '..\src\Model\Pdf4D.Model.AcroForm.pas',
  Pdf4D.Model.Field.Tests in '..\src\Model\Pdf4D.Model.Field.Tests.pas',
  Pdf4D.Model.Field.Golden.Tests in '..\src\Model\Pdf4D.Model.Field.Golden.Tests.pas',
  Pdf4D.Model.NameTree.Tests in '..\src\Model\Pdf4D.Model.NameTree.Tests.pas',
  Pdf4D.Model.PageLabels.Tests in '..\src\Model\Pdf4D.Model.PageLabels.Tests.pas',
  Pdf4D.Model.Outline.Tests in '..\src\Model\Pdf4D.Model.Outline.Tests.pas',
  Pdf4D.Model.EmbeddedFile.Tests in '..\src\Model\Pdf4D.Model.EmbeddedFile.Tests.pas',
  Pdf4D.Model.Navigation.Golden.Tests in '..\src\Model\Pdf4D.Model.Navigation.Golden.Tests.pas';

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
