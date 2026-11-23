// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.Fuzz;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Render.Device.Interfaces;

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
  // dumps the text, LimitedPageText does so with smaller budgets for operators and glyphs, TightPageText with a much smaller
  // operator budget for content that makes every operator expensive, the program kinds give the bytes to one parser of a font program or CMap and ask it for widths and Unicode, FontClasses loads the
  // document and asks the PDF font /F1 for widths and Unicode of every code.
  // Render loads a document and draws its first pages at 36 DPI with the backend of TFuzzRendering, after the text layout of phase 1.
  // Viewer opens the document in a viewer session (with the recording backend of TFuzzViewing) and asks for the tiles, the text and a
  // search of its pages, as a viewer does.
  // The decoder kinds give the bytes to one decoder: a JPEG image, CCITT data, an ICC profile (parsed and used for a transform), the
  // program of a PostScript function (as the stream of a function of type 4), a Type 1 or a Type 2 charstring (with the subroutines of a
  // real font), and the bytes of a TrueType font whose outlines are all asked for.
  TFuzzWork = (Structure, Text, PageText, LimitedPageText, TightPageText, TrueTypeProgram, OpenTypeProgram, CffProgram, Type1Program, CMapProgram, FontClasses,
               Render, Viewer, JpegDecoder, CcittDecoder, IccProfile, PostScriptFunction, Type1CharString, CffCharString, GlyphOutlines);

  TFuzzBackendFactory = reference to function: IPdfRenderBackend;

  // The backend of the Render work. The test project that has a backend sets it before it runs the work; the work raises when it is not set.
  TFuzzRendering = record
    class var Backend: TFuzzBackendFactory;
  end;

  TFuzzViewProbe = reference to procedure(const Bytes: TBytes; const Password: string);

  // What the Viewer work does. The test project that has the viewer units sets it before it runs the work; the work raises when it is not
  // set (the Skia test project has no use for it).
  TFuzzViewing = record
    class var Probe: TFuzzViewProbe;
  end;

  // The valid inputs that the decoder fuzz mutates, read from the test files and the resources
  TDecoderInputs = class
  strict private
    class var FType1CharString: TBytes;
    class var FType1Subrs: TArray<TBytes>;
    class var FCffCharString: TBytes;
    class var FCffGlobalSubrs: TArray<TBytes>;
    class var FCffLocalSubrs: TArray<TBytes>;

    class procedure LoadType1;
    class procedure LoadCff;
    class function ReferenceFile(const SubFolder, FileName: string): TBytes; static;

  public
    class function Jpeg(const FileName: string): TBytes; static;
    // The CCITT data of the image /Im1 of ccitt.pdf, Group 4 coded
    class function CcittData: TBytes; static;
    class function CmykProfile: TBytes; static;
    // The program of a function of type 4 that uses every operator
    class function PostScriptProgram: TBytes; static;
    class function Type1CharString: TBytes; static;
    class function Type1Subrs: TArray<TBytes>; static;
    class function CffCharString: TBytes; static;
    class function CffGlobalSubrs: TArray<TBytes>; static;
    class function CffLocalSubrs: TArray<TBytes>; static;
    // The offset and the size of the table in a TrueType font, False when there is no such table
    class function TryFindTable(const Font: TBytes; const Tag: string; out Offset, Size: Integer): Boolean; static;

    class destructor Destroy;
  end;

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
  public const
    // A Debug build renders about three times slower than a Release build; its render runs use fewer cases so that the whole test
    // program stays under 20 minutes per platform. Both Debug counts are here (docs/building.md names them): the mutations per file
    // of the mutated corpus and the generated graphics streams.
    DebugRenderMutationsPerFile = 6;
    DebugRenderGraphicsStreams = 600;
  public
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
    // The first FileCount files of the corpus (times the scale), or every file with IsWholeCorpus
    class procedure RunMutatedCorpus(const Work: TFuzzWork; const IsWholeCorpus: Boolean = False); static;

    procedure Run(const Name: string; const Bytes: TBytes; const Password: string; const Work: TFuzzWork);
    procedure AssertNoFailures;
  end;

implementation


uses
  System.IOUtils,
  System.Diagnostics,
  System.Math,
  Pdf4D.Api.Document,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Codec.CCITTFax,
  Pdf4D.Codec.Jpeg,
  Pdf4D.Common.Defines,
  Pdf4D.Common.Log,
  Pdf4D.Common.Path,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Names,
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
  Pdf4D.FontBox.CharStringPath,
  Pdf4D.FontBox.Type1.Font,
  Pdf4D.Graphics.&Function,
  Pdf4D.Graphics.Icc.Profile,
  Pdf4D.Graphics.Icc.Transform,
  Pdf4D.IO.RandomAccessRead,
  Pdf4D.Model.Document,
  Pdf4D.Model.Page,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Renderer,
  Pdf4D.Render.Renderer.Interfaces,
  Pdf4D.Resources.Icc,
  Pdf4D.Tests.Corpus,
  Pdf4D.Tests.Functions,
  Pdf4D.Tests.TestFonts,
  Pdf4D.Tests.StructureDump,
  Pdf4D.Tests.TextDocuments,
  Pdf4D.Tests.PositionDump,
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
  TightOperatorBudget = 100000;
  ProbedGlyphs = 400;
  ProbedCodes = 300;
  ProbedFontKey = 'F1';
  RenderedPages = 10;
  RenderDpi = 36;
  MaxJpegPixels = 16000000;
  MaxCcittPixels = 1000000;
  CcittColumns = 96;
  CcittRows = 64;
  MaxProbedOutlines = 4000;
  IccProbeRowPixels = 64;
  JpegFolder = 'jpeg';
  PostScriptDomain = '0 1 0 1 0 1 0 1';
  PostScriptRange = '0 1 0 1 0 1';
  CcittCorpusFile = 'generated/render/ccitt.pdf';
  CcittImageName = 'Im1';
  Type1FontFile = 'OpenSans-Regular.pfb';
  CffFontFile = 'SourceSansProBold.otf';
  PostScriptSource =
    '{ 4 copy add add add 4 1 roll 3 index 2 index mul sub dup 0 lt { pop 0 } { dup 1 gt { pop 1 } if } ifelse ' +
    'exch 3 -1 roll 2 copy exch pop 360 mod abs sqrt 2 exp ln log atan cvi cvr truncate round floor ceiling neg ' +
    '1 2 roll idiv bitshift and or xor not eq ne ge gt le lt true false pop pop pop sin cos 10 div exch 5 index ' +
    'dup mul sub add 3 1 roll pop 0.5 mul }';

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

  // What the decoders and the renderer are asked to do with bytes
  TDecoderProbe = class
  strict private
    class function SilentLog: TPdfLog; static;
    class procedure CheckFinite(const Values: array of Single; const What: string); static;

  public
    class procedure Jpeg(const Bytes: TBytes); static;
    class procedure Ccitt(const Bytes: TBytes); static;
    class procedure Icc(const Bytes: TBytes); static;
    class procedure PostScript(const Bytes: TBytes); static;
    class procedure Type1CharString(const Bytes: TBytes); static;
    class procedure CffCharString(const Bytes: TBytes); static;
    class procedure GlyphOutlines(const Bytes: TBytes); static;
    class procedure Render(const Bytes: TBytes); static;
    class procedure View(const Bytes: TBytes; const Password: string); static;
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

{ TDecoderProbe }

class function TDecoderProbe.SilentLog: TPdfLog;
begin
  Result := TPdfLog.Create(procedure(const Level: TPdfLogLevel; const Message: string) begin end);
end;

class procedure TDecoderProbe.CheckFinite(const Values: array of Single; const What: string);
begin
  for var Value in Values do
  begin
    if IsNan(Value) or IsInfinite(Value) then
    begin
      raise EInvalidOpException.CreateFmt('%s is not finite', [What]);
    end;
  end;
end;

class procedure TDecoderProbe.Jpeg(const Bytes: TBytes);
begin
  const Log = SilentLog;
  try
    for var ColorTransform in [-1, 0, 1] do
    begin
      const Image = TJpegImage.Decode(Bytes, TJpegDecodeOptions.ForPdf(ColorTransform, MaxJpegPixels), Log);
      try
        if Length(Image.Samples) < Int64(Image.Width) * Image.Height * Image.Components then
        begin
          raise EInvalidOpException.CreateFmt('The JPEG image of %d x %d with %d components has %d samples',
                                              [Image.Width, Image.Height, Image.Components, Length(Image.Samples)]);
        end;
      finally
        Image.Free;
      end;
    end;
  finally
    Log.Free;
  end;
end;

class procedure TDecoderProbe.Ccitt(const Bytes: TBytes);
begin
  const Log = SilentLog;
  try
    for var K in [-1, 0, 1] do
    begin
      for var Rows in [CcittRows, 0] do
      begin
        var Parameters := Default(TCCITTFaxParameters);
        Parameters.K := K;
        Parameters.Columns := CcittColumns;
        Parameters.Rows := Rows;
        Parameters.EndOfBlock := True;
        Parameters.BlackIs1 := Odd(Rows);
        TCCITTFaxDecoder.Decode(Bytes, Parameters, MaxCcittPixels, Log);
      end;
    end;
  finally
    Log.Free;
  end;
end;

class procedure TDecoderProbe.Icc(const Bytes: TBytes);
begin
  const Profile = TIccProfile.Parse(Bytes);
  try
    const Transform = TIccTransform.Create(Profile);
    try
      const Components = Profile.NumberOfComponents;
      var Device: TArray<Single>;
      SetLength(Device, Components);
      var Rgb: array[0..2] of Single;
      for var Round := 0 to 4 do
      begin
        for var Index := 0 to Components - 1 do
        begin
          Device[Index] := Round / 4.0;
          if Odd(Index) then
          begin
            Device[Index] := 1 - Device[Index];
          end;
        end;
        Transform.ToRgb(@Device[0], @Rgb[0]);
        CheckFinite(Rgb, 'The sRGB value of the ICC transform');
      end;

      var Row: TBytes;
      SetLength(Row, IccProbeRowPixels * Components);
      for var Index := 0 to High(Row) do
      begin
        Row[Index] := Byte(Index * 37);
      end;
      var Output: TBytes;
      SetLength(Output, IccProbeRowPixels * 3);
      Transform.ToRgbRow(@Row[0], @Output[0], IccProbeRowPixels);
    finally
      Transform.Free;
    end;
  finally
    Profile.Free;
  end;
end;

class procedure TDecoderProbe.PostScript(const Bytes: TBytes);
begin
  const Builder = TFunctionTestBuilder.Create;
  try
    const Stream = Builder.NewStream(4, [TCosNames.Domain, PostScriptDomain, TCosNames.Range, PostScriptRange], Bytes);
    const Calculation = TPDFunction.Create(Stream, Builder.Context);
    try
      for var Round := 0 to 4 do
      begin
        const Value = Round / 4.0;
        const Output = Calculation.Eval([Value, 1 - Value, Value * Value, 0.5]);
        CheckFinite(Output, 'The output of the function');
      end;
    finally
      Calculation.Free;
    end;
  finally
    Builder.Free;
  end;
end;

class procedure TDecoderProbe.Type1CharString(const Bytes: TBytes);
begin
  const Log = SilentLog;
  try
    // The accents of a seac are looked up as the charstring that is being tried, so a seac that draws itself is part of it
    const Lookup: TFunc<string, TBytes> = function(Name: string): TBytes begin Result := Bytes; end;
    const Path = TCharStringPath.Type1Path(Bytes, TDecoderInputs.Type1Subrs, Lookup, Log);
    try
      Path.Bounds;
    finally
      Path.Free;
    end;
  finally
    Log.Free;
  end;
end;

class procedure TDecoderProbe.CffCharString(const Bytes: TBytes);
begin
  const Log = SilentLog;
  try
    const Lookup: TFunc<string, TBytes> = function(Name: string): TBytes begin Result := Bytes; end;
    const Path = TCharStringPath.Type2Path(Bytes, TDecoderInputs.CffGlobalSubrs, TDecoderInputs.CffLocalSubrs, Lookup, Log);
    try
      Path.Bounds;
    finally
      Path.Free;
    end;
  finally
    Log.Free;
  end;
end;

class procedure TDecoderProbe.GlyphOutlines(const Bytes: TBytes);
begin
  const Log = SilentLog;
  try
    const Parser = TTTFParser.Create(True);
    try
      const Font = Parser.Parse(Bytes);
      try
        for var Glyph := 0 to Min(Font.NumberOfGlyphs, MaxProbedOutlines) - 1 do
        begin
          var Path: TPdfPath;
          if Font.TryGetGlyphPath(Glyph, Path, Log) then
          begin
            try
              Path.Bounds;
            finally
              Path.Free;
            end;
          end;
        end;
      finally
        Font.Free;
      end;
    finally
      Parser.Free;
    end;
  finally
    Log.Free;
  end;
end;

class procedure TDecoderProbe.Render(const Bytes: TBytes);
begin
  if not Assigned(TFuzzRendering.Backend) then
  begin
    raise EProgrammerNotFound.Create('TFuzzRendering.Backend is not set');
  end;

  const Stream = TBytesStream.Create(Bytes);
  try
    const Document: IPdfDocument = TPdfDocument.Load(Stream, TPdfLoadOptions.Default);
    const Renderer: IPdfRenderer = TPdfRenderer.Create(Document, TFuzzRendering.Backend());
    for var Page := 0 to Min(Document.PageCount, RenderedPages) - 1 do
    begin
      var Bitmap: TPdfBitmap := nil;
      try
        try
          Renderer.RenderToBitmap(Page, TPdfRenderParams.FromDpi(RenderDpi), Bitmap);
        except
          // A page that cannot be drawn ends in a PDF exception; the next pages are still drawn
          on EPdfException do ;
        end;
      finally
        Bitmap.Free;
      end;
    end;
    TPositionDump.Probe(Document);
  finally
    Stream.Free;
  end;
end;

class procedure TDecoderProbe.View(const Bytes: TBytes; const Password: string);
begin
  if not Assigned(TFuzzViewing.Probe) then
  begin
    raise EProgrammerNotFound.Create('TFuzzViewing.Probe is not set');
  end;

  TFuzzViewing.Probe(Bytes, Password);
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
          TPositionDump.Probe(Document);
        end;
      finally
        Stream.Free;
      end;
    end;
    TFuzzWork.PageText, TFuzzWork.LimitedPageText, TFuzzWork.TightPageText:
    begin
      var Options := TPdfLoadOptions.Default;
      if FWork in [TFuzzWork.LimitedPageText, TFuzzWork.TightPageText] then
      begin
        Options.MaxOperatorsPerPage := LimitedOperatorBudget;
        Options.MaxGlyphsPerPage := LimitedGlyphBudget;
      end;
      if FWork = TFuzzWork.TightPageText then
      begin
        Options.MaxOperatorsPerPage := TightOperatorBudget;
      end;
      const Stream = TBytesStream.Create(FBytes);
      try
        const Document: IPdfDocument = TPdfDocument.Load(Stream, Options);
        TTextDump.Dump(Document, True);
        TPositionDump.Probe(Document);
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
    TFuzzWork.Render: TDecoderProbe.Render(FBytes);
    TFuzzWork.Viewer: TDecoderProbe.View(FBytes, FPassword);
    TFuzzWork.JpegDecoder: TDecoderProbe.Jpeg(FBytes);
    TFuzzWork.CcittDecoder: TDecoderProbe.Ccitt(FBytes);
    TFuzzWork.IccProfile: TDecoderProbe.Icc(FBytes);
    TFuzzWork.PostScriptFunction: TDecoderProbe.PostScript(FBytes);
    TFuzzWork.Type1CharString: TDecoderProbe.Type1CharString(FBytes);
    TFuzzWork.CffCharString: TDecoderProbe.CffCharString(FBytes);
    TFuzzWork.GlyphOutlines: TDecoderProbe.GlyphOutlines(FBytes);
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

{ TDecoderInputs }

class destructor TDecoderInputs.Destroy;
begin
  FType1CharString := nil;
  FType1Subrs := nil;
  FCffCharString := nil;
  FCffGlobalSubrs := nil;
  FCffLocalSubrs := nil;
end;

class function TDecoderInputs.ReferenceFile(const SubFolder, FileName: string): TBytes;
begin
  const Folder = TPath.Combine(TPath.Combine(TPath.GetDirectoryName(TCorpus.Folder), 'reference'), SubFolder);
  Result := TFile.ReadAllBytes(TPath.Combine(Folder, FileName));
end;

class function TDecoderInputs.Jpeg(const FileName: string): TBytes;
begin
  Result := ReferenceFile(JpegFolder, FileName);
end;

class function TDecoderInputs.CcittData: TBytes;
begin
  const Document = TPDDocument.Load(TFileStream.Create(TCorpus.PdfPath(CcittCorpusFile), fmOpenRead or fmShareDenyWrite), True, TPdfLoadOptions.Default);
  try
    var Stream: TCosStream;
    if not Document.Pages.Get(0).Resources.TryGetXObject(CcittImageName, Stream) then
    begin
      raise EInvalidOpException.Create('The CCITT test image is missing');
    end;
    Result := Stream.DecodeUntilImageFilter.Data;
  finally
    Document.Free;
  end;
end;

class function TDecoderInputs.CmykProfile: TBytes;
begin
  Result := TPdfIccResources.CmykProfile;
end;

class function TDecoderInputs.PostScriptProgram: TBytes;
begin
  Result := TEncoding.ASCII.GetBytes(PostScriptSource);
end;

// The longest charstring of the font: it has the most operators to damage
class procedure TDecoderInputs.LoadType1;
begin
  if Length(FType1CharString) > 0 then
  begin
    Exit;
  end;

  const Font = TType1Font.CreateWithPFB(TTestFonts.Bytes(Type1FontFile));
  try
    var Longest: TBytes;
    for var Pair in Font.CharStringsDict do
    begin
      if Length(Pair.Value) > Length(Longest) then
      begin
        Longest := Pair.Value;
      end;
    end;
    FType1Subrs := Font.Subrs;
    FType1CharString := Longest;
  finally
    Font.Free;
  end;
end;

class procedure TDecoderInputs.LoadCff;
begin
  if Length(FCffCharString) > 0 then
  begin
    Exit;
  end;

  const OpenType = TTestFonts.Bytes(CffFontFile);
  var Offset, Size: Integer;
  if not TryFindTable(OpenType, 'CFF ', Offset, Size) then
  begin
    raise EInvalidOpException.Create('The font has no CFF table');
  end;

  const Parser = TCFFParser.Create;
  try
    const Fonts = Parser.Parse(Copy(OpenType, Offset, Size));
    try
      const Font = Fonts[0] as TCFFType1Font;
      var Longest: TBytes;
      for var CharString in Font.CharStrings do
      begin
        if Length(CharString) > Length(Longest) then
        begin
          Longest := CharString;
        end;
      end;
      FCffGlobalSubrs := Font.GlobalSubrs;
      FCffLocalSubrs := Font.LocalSubrs;
      FCffCharString := Longest;
    finally
      Fonts.Free;
    end;
  finally
    Parser.Free;
  end;
end;

class function TDecoderInputs.Type1CharString: TBytes;
begin
  LoadType1;
  Result := FType1CharString;
end;

class function TDecoderInputs.Type1Subrs: TArray<TBytes>;
begin
  LoadType1;
  Result := FType1Subrs;
end;

class function TDecoderInputs.CffCharString: TBytes;
begin
  LoadCff;
  Result := FCffCharString;
end;

class function TDecoderInputs.CffGlobalSubrs: TArray<TBytes>;
begin
  LoadCff;
  Result := FCffGlobalSubrs;
end;

class function TDecoderInputs.CffLocalSubrs: TArray<TBytes>;
begin
  LoadCff;
  Result := FCffLocalSubrs;
end;

class function TDecoderInputs.TryFindTable(const Font: TBytes; const Tag: string; out Offset, Size: Integer): Boolean;
const
  HeaderSize = 12;
  RecordSize = 16;
begin
  Offset := 0;
  Size := 0;
  const TableCount = (Font[4] shl 8) or Font[5];
  for var Index := 0 to TableCount - 1 do
  begin
    const Entry = HeaderSize + (Index * RecordSize);
    if TEncoding.ASCII.GetString(Font, Entry, 4) = Tag then
    begin
      Offset := (Font[Entry + 8] shl 24) or (Font[Entry + 9] shl 16) or (Font[Entry + 10] shl 8) or Font[Entry + 11];
      Size := (Font[Entry + 12] shl 24) or (Font[Entry + 13] shl 16) or (Font[Entry + 14] shl 8) or Font[Entry + 15];
      Exit(True);
    end;
  end;
  Result := False;
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

class procedure TFuzzCampaign.RunMutatedCorpus(const Work: TFuzzWork; const IsWholeCorpus: Boolean);
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
    var FileLimit := Min(TFuzzSettings.Scale(FileCount), Length(Files));
    if IsWholeCorpus then
    begin
      FileLimit := Length(Files);
    end;
    for var FileIndex := 0 to FileLimit - 1 do
    begin
      const FileName = Files[FileIndex];
      const Source = TFile.ReadAllBytes(TCorpus.PdfPath(FileName));
      const Password = TCorpus.PasswordFor(FileName);
      const FileSeed = Seed + TFuzzSettings.SeedOffset + FileIndex;
      RandSeed := FileSeed;

      var MutationCount := MutationsPerFile;
      {$IFDEF DEBUG}
      if Work = TFuzzWork.Render then
      begin
        MutationCount := TFuzzSettings.DebugRenderMutationsPerFile;
      end;
      {$ENDIF}
      for var Index := 0 to TFuzzSettings.Scale(MutationCount) - 1 do
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

end.
