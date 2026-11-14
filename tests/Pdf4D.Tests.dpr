// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
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
  Pdf4D.Common.ResourceData in '..\src\Common\Pdf4D.Common.ResourceData.pas',
  Pdf4D.Resources.GlyphList in '..\src\Resources\Pdf4D.Resources.GlyphList.pas',
  Pdf4D.Resources.Afm in '..\src\Resources\Pdf4D.Resources.Afm.pas',
  Pdf4D.Resources.CMap in '..\src\Resources\Pdf4D.Resources.CMap.pas',
  Pdf4D.Resources.Fonts in '..\src\Resources\Pdf4D.Resources.Fonts.pas',
  Pdf4D.Resources.Unicode in '..\src\Resources\Pdf4D.Resources.Unicode.pas',
  Pdf4D.Text.UnicodeTables in '..\src\Text\Pdf4D.Text.UnicodeTables.pas',
  Pdf4D.Text.UnicodeTables.Tests in '..\src\Text\Pdf4D.Text.UnicodeTables.Tests.pas',
  Pdf4D.FontBox.Encoding in '..\src\FontBox\Pdf4D.FontBox.Encoding.pas',
  Pdf4D.Font.Encoding in '..\src\Font\Pdf4D.Font.Encoding.pas',
  Pdf4D.Font.Encoding.Tables in '..\src\Font\Pdf4D.Font.Encoding.Tables.pas',
  Pdf4D.Font.GlyphList in '..\src\Font\Pdf4D.Font.GlyphList.pas',
  Pdf4D.Font.Encoding.Tests in '..\src\Font\Pdf4D.Font.Encoding.Tests.pas',
  Pdf4D.Font.GlyphList.Tests in '..\src\Font\Pdf4D.Font.GlyphList.Tests.pas',
  Pdf4D.FontBox.CMap in '..\src\FontBox\Pdf4D.FontBox.CMap.pas',
  Pdf4D.FontBox.CMapParser in '..\src\FontBox\Pdf4D.FontBox.CMapParser.pas',
  Pdf4D.Font.CMapManager in '..\src\Font\Pdf4D.Font.CMapManager.pas',
  Pdf4D.FontBox.CMapParser.Tests in '..\src\FontBox\Pdf4D.FontBox.CMapParser.Tests.pas',
  Pdf4D.Font.CMapManager.Tests in '..\src\Font\Pdf4D.Font.CMapManager.Tests.pas',
  Pdf4D.FontBox.BoundingBox in '..\src\FontBox\Pdf4D.FontBox.BoundingBox.pas',
  Pdf4D.FontBox.Afm in '..\src\FontBox\Pdf4D.FontBox.Afm.pas',
  Pdf4D.FontBox.AfmParser in '..\src\FontBox\Pdf4D.FontBox.AfmParser.pas',
  Pdf4D.Font.Standard14 in '..\src\Font\Pdf4D.Font.Standard14.pas',
  Pdf4D.FontBox.AfmParser.Tests in '..\src\FontBox\Pdf4D.FontBox.AfmParser.Tests.pas',
  Pdf4D.Font.Standard14.Tests in '..\src\Font\Pdf4D.Font.Standard14.Tests.pas',
  Pdf4D.FontBox.FontBoxFont in '..\src\FontBox\Pdf4D.FontBox.FontBoxFont.pas',
  Pdf4D.FontBox.TrueType.DataStream in '..\src\FontBox\Pdf4D.FontBox.TrueType.DataStream.pas',
  Pdf4D.FontBox.TrueType.Tables in '..\src\FontBox\Pdf4D.FontBox.TrueType.Tables.pas',
  Pdf4D.FontBox.TrueType.Font in '..\src\FontBox\Pdf4D.FontBox.TrueType.Font.pas',
  Pdf4D.FontBox.TrueType.Cmap in '..\src\FontBox\Pdf4D.FontBox.TrueType.Cmap.pas',
  Pdf4D.FontBox.TrueType.Post in '..\src\FontBox\Pdf4D.FontBox.TrueType.Post.pas',
  Pdf4D.FontBox.TrueType.Vertical in '..\src\FontBox\Pdf4D.FontBox.TrueType.Vertical.pas',
  Pdf4D.FontBox.TrueType.Parser in '..\src\FontBox\Pdf4D.FontBox.TrueType.Parser.pas',
  Pdf4D.FontBox.TrueType.Collection in '..\src\FontBox\Pdf4D.FontBox.TrueType.Collection.pas',
  Pdf4D.Tests.TestFonts in 'Support\Pdf4D.Tests.TestFonts.pas',
  Pdf4D.Tests.TrueTypeBuilder in 'Support\Pdf4D.Tests.TrueTypeBuilder.pas',
  Pdf4D.FontBox.TrueType.Parser.Tests in '..\src\FontBox\Pdf4D.FontBox.TrueType.Parser.Tests.pas',
  Pdf4D.FontBox.TrueType.Cmap.Tests in '..\src\FontBox\Pdf4D.FontBox.TrueType.Cmap.Tests.pas',
  Pdf4D.FontBox.TrueType.Post.Tests in '..\src\FontBox\Pdf4D.FontBox.TrueType.Post.Tests.pas',
  Pdf4D.FontBox.TrueType.Vertical.Tests in '..\src\FontBox\Pdf4D.FontBox.TrueType.Vertical.Tests.pas',
  Pdf4D.FontBox.TrueType.Collection.Tests in '..\src\FontBox\Pdf4D.FontBox.TrueType.Collection.Tests.pas',
  Pdf4D.FontBox.Cff.DataInput in '..\src\FontBox\Pdf4D.FontBox.Cff.DataInput.pas',
  Pdf4D.FontBox.Cff.StandardStrings in '..\src\FontBox\Pdf4D.FontBox.Cff.StandardStrings.pas',
  Pdf4D.FontBox.Cff.Charset in '..\src\FontBox\Pdf4D.FontBox.Cff.Charset.pas',
  Pdf4D.FontBox.Cff.Encoding in '..\src\FontBox\Pdf4D.FontBox.Cff.Encoding.pas',
  Pdf4D.FontBox.Cff.Font in '..\src\FontBox\Pdf4D.FontBox.Cff.Font.pas',
  Pdf4D.FontBox.Cff.Parser in '..\src\FontBox\Pdf4D.FontBox.Cff.Parser.pas',
  Pdf4D.FontBox.Cff.Type1FontUtil in '..\src\FontBox\Pdf4D.FontBox.Cff.Type1FontUtil.pas',
  Pdf4D.FontBox.CharStringWidth in '..\src\FontBox\Pdf4D.FontBox.CharStringWidth.pas',
  Pdf4D.FontBox.Pfb in '..\src\FontBox\Pdf4D.FontBox.Pfb.pas',
  Pdf4D.FontBox.Type1.Lexer in '..\src\FontBox\Pdf4D.FontBox.Type1.Lexer.pas',
  Pdf4D.FontBox.Type1.Parser in '..\src\FontBox\Pdf4D.FontBox.Type1.Parser.pas',
  Pdf4D.FontBox.Type1.Font in '..\src\FontBox\Pdf4D.FontBox.Type1.Font.pas',
  Pdf4D.FontBox.OpenType in '..\src\FontBox\Pdf4D.FontBox.OpenType.pas',
  Pdf4D.Tests.CffBuilder in 'Support\Pdf4D.Tests.CffBuilder.pas',
  Pdf4D.Tests.CffParseOutcome in 'Support\Pdf4D.Tests.CffParseOutcome.pas',
  Pdf4D.FontBox.Cff.Parser.Tests in '..\src\FontBox\Pdf4D.FontBox.Cff.Parser.Tests.pas',
  Pdf4D.FontBox.Cff.CID.Tests in '..\src\FontBox\Pdf4D.FontBox.Cff.CID.Tests.pas',
  Pdf4D.FontBox.CharStringWidth.Tests in '..\src\FontBox\Pdf4D.FontBox.CharStringWidth.Tests.pas',
  Pdf4D.FontBox.Type1.Font.Tests in '..\src\FontBox\Pdf4D.FontBox.Type1.Font.Tests.pas',
  Pdf4D.FontBox.OpenType.Tests in '..\src\FontBox\Pdf4D.FontBox.OpenType.Tests.pas',
  Pdf4D.Font.Descriptor in '..\src\Font\Pdf4D.Font.Descriptor.pas',
  Pdf4D.Font.Provider in '..\src\Font\Pdf4D.Font.Provider.pas',
  Pdf4D.Font.Mapper in '..\src\Font\Pdf4D.Font.Mapper.pas',
  Pdf4D.Font.MapperImpl in '..\src\Font\Pdf4D.Font.MapperImpl.pas',
  Pdf4D.Tests.FontProvider in 'Support\Pdf4D.Tests.FontProvider.pas',
  Pdf4D.Font.Descriptor.Tests in '..\src\Font\Pdf4D.Font.Descriptor.Tests.pas',
  Pdf4D.Font.MapperImpl.Tests in '..\src\Font\Pdf4D.Font.MapperImpl.Tests.pas',
  Pdf4D.FontBox.TrueType.Headers in '..\src\FontBox\Pdf4D.FontBox.TrueType.Headers.pas',
  Pdf4D.Font.DirFinder in '..\src\Font\Pdf4D.Font.DirFinder.pas',
  Pdf4D.Font.FileSystemProvider in '..\src\Font\Pdf4D.Font.FileSystemProvider.pas',
  Pdf4D.Font.FileSystemProvider.Tests in '..\src\Font\Pdf4D.Font.FileSystemProvider.Tests.pas',
  Pdf4D.Common.Matrix in '..\src\Common\Pdf4D.Common.Matrix.pas',
  Pdf4D.Common.Matrix.Tests in '..\src\Common\Pdf4D.Common.Matrix.Tests.pas',
  Pdf4D.Font.Base in '..\src\Font\Pdf4D.Font.Base.pas',
  Pdf4D.Font.Base.Tests in '..\src\Font\Pdf4D.Font.Base.Tests.pas',
  Pdf4D.Font.Simple in '..\src\Font\Pdf4D.Font.Simple.pas',
  Pdf4D.Font.Type1 in '..\src\Font\Pdf4D.Font.Type1.pas',
  Pdf4D.Font.Type1C in '..\src\Font\Pdf4D.Font.Type1C.pas',
  Pdf4D.Font.TrueType in '..\src\Font\Pdf4D.Font.TrueType.pas',
  Pdf4D.Font.CIDFont in '..\src\Font\Pdf4D.Font.CIDFont.pas',
  Pdf4D.Font.CIDFontType0 in '..\src\Font\Pdf4D.Font.CIDFontType0.pas',
  Pdf4D.Font.CIDFontType2 in '..\src\Font\Pdf4D.Font.CIDFontType2.pas',
  Pdf4D.Font.Type3 in '..\src\Font\Pdf4D.Font.Type3.pas',
  Pdf4D.Font.Type0 in '..\src\Font\Pdf4D.Font.Type0.pas',
  Pdf4D.Font.Factory in '..\src\Font\Pdf4D.Font.Factory.pas',
  Pdf4D.Tests.TextDocuments in 'Support\Pdf4D.Tests.TextDocuments.pas',
  Pdf4D.Font.Type1.Tests in '..\src\Font\Pdf4D.Font.Type1.Tests.pas',
  Pdf4D.Font.Type1C.Tests in '..\src\Font\Pdf4D.Font.Type1C.Tests.pas',
  Pdf4D.Font.TrueType.Tests in '..\src\Font\Pdf4D.Font.TrueType.Tests.pas',
  Pdf4D.Font.Type0.Tests in '..\src\Font\Pdf4D.Font.Type0.Tests.pas',
  Pdf4D.Font.CIDFontType0.Tests in '..\src\Font\Pdf4D.Font.CIDFontType0.Tests.pas',
  Pdf4D.Font.Type3.Tests in '..\src\Font\Pdf4D.Font.Type3.Tests.pas',
  Pdf4D.Common.ResourceData.Tests in '..\src\Common\Pdf4D.Common.ResourceData.Tests.pas',
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
  Pdf4D.Parser.ContentStream.Tests in '..\src\Parser\Pdf4D.Parser.ContentStream.Tests.pas',
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
  Pdf4D.Common.SharedInstance in '..\src\Common\Pdf4D.Common.SharedInstance.pas',
  Pdf4D.Common.SharedInstance.Tests in '..\src\Common\Pdf4D.Common.SharedInstance.Tests.pas',
  Pdf4D.Model.DocumentContext in '..\src\Model\Pdf4D.Model.DocumentContext.pas',
  Pdf4D.Model.Rectangle in '..\src\Model\Pdf4D.Model.Rectangle.pas',
  Pdf4D.Model.Page in '..\src\Model\Pdf4D.Model.Page.pas',
  Pdf4D.Model.PageTree in '..\src\Model\Pdf4D.Model.PageTree.pas',
  Pdf4D.Model.DocumentInformation in '..\src\Model\Pdf4D.Model.DocumentInformation.pas',
  Pdf4D.Model.DocumentCatalog in '..\src\Model\Pdf4D.Model.DocumentCatalog.pas',
  Pdf4D.Model.Document in '..\src\Model\Pdf4D.Model.Document.pas',
  Pdf4D.Model.Tests.Support in '..\src\Model\Pdf4D.Model.Tests.Support.pas',
  Pdf4D.Model.PageTree.Tests in '..\src\Model\Pdf4D.Model.PageTree.Tests.pas',
  Pdf4D.Model.DocumentContext.Tests in '..\src\Model\Pdf4D.Model.DocumentContext.Tests.pas',
  Pdf4D.Model.Page.Tests in '..\src\Model\Pdf4D.Model.Page.Tests.pas',
  Pdf4D.Content.GraphicsState in '..\src\Content\Pdf4D.Content.GraphicsState.pas',
  Pdf4D.Model.Resources in '..\src\Model\Pdf4D.Model.Resources.pas',
  Pdf4D.Model.FormXObject in '..\src\Model\Pdf4D.Model.FormXObject.pas',
  Pdf4D.Model.ExtendedGraphicsState in '..\src\Model\Pdf4D.Model.ExtendedGraphicsState.pas',
  Pdf4D.Content.GraphicsState.Tests in '..\src\Content\Pdf4D.Content.GraphicsState.Tests.pas',
  Pdf4D.Model.Resources.Tests in '..\src\Model\Pdf4D.Model.Resources.Tests.pas',
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
  Pdf4D.Model.NameTree.Tests in '..\src\Model\Pdf4D.Model.NameTree.Tests.pas',
  Pdf4D.Model.PageLabels.Tests in '..\src\Model\Pdf4D.Model.PageLabels.Tests.pas',
  Pdf4D.Model.Outline.Tests in '..\src\Model\Pdf4D.Model.Outline.Tests.pas',
  Pdf4D.Model.EmbeddedFile.Tests in '..\src\Model\Pdf4D.Model.EmbeddedFile.Tests.pas',
  Pdf4D.Api.Document.Interfaces in '..\src\Api\Pdf4D.Api.Document.Interfaces.pas',
  Pdf4D.Api.Page.Interfaces in '..\src\Api\Pdf4D.Api.Page.Interfaces.pas',
  Pdf4D.Api.Outline.Interfaces in '..\src\Api\Pdf4D.Api.Outline.Interfaces.pas',
  Pdf4D.Api.Field.Interfaces in '..\src\Api\Pdf4D.Api.Field.Interfaces.pas',
  Pdf4D.Api.Attachment.Interfaces in '..\src\Api\Pdf4D.Api.Attachment.Interfaces.pas',
  Pdf4D.Api.DocumentHandle in '..\src\Api\Pdf4D.Api.DocumentHandle.pas',
  Pdf4D.Api.Page in '..\src\Api\Pdf4D.Api.Page.pas',
  Pdf4D.Api.OutlineItem in '..\src\Api\Pdf4D.Api.OutlineItem.pas',
  Pdf4D.Api.Field in '..\src\Api\Pdf4D.Api.Field.pas',
  Pdf4D.Api.Attachment in '..\src\Api\Pdf4D.Api.Attachment.pas',
  Pdf4D.Api.Document in '..\src\Api\Pdf4D.Api.Document.pas',
  Pdf4D.Api.Document.Tests in '..\src\Api\Pdf4D.Api.Document.Tests.pas',
  Pdf4D.Tests.Corpus in 'Support\Pdf4D.Tests.Corpus.pas',
  Pdf4D.Tests.StructureDump in 'Support\Pdf4D.Tests.StructureDump.pas',
  Pdf4D.Tests.Golden in 'Support\Pdf4D.Tests.Golden.pas',
  Pdf4D.Tests.Golden.Comparer.Tests in 'Support\Pdf4D.Tests.Golden.Comparer.Tests.pas',
  Pdf4D.Tests.Golden.Tests in 'Acceptance\Pdf4D.Tests.Golden.Tests.pas',
  Pdf4D.Tests.Robustness.Tests in 'Acceptance\Pdf4D.Tests.Robustness.Tests.pas';

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

  // Test output must not depend on the fonts of the machine: only the fonts that a test names can be found, and everything
  // else ends up in the last-resort font (LiberationSans), like in the oracle.
  TPdfFontMappers.SetDefaultProvider(TTestFontProvider.Empty);
  TPdfFontMappers.SetInstance(TFontMapperImpl.Create(TTestFontProvider.Empty));

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
