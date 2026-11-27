// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.RenderRobustness.Base;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Classes,
  DUnitX.TestFramework,
  Pdf4D.Font.Mapper,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Tests.Fuzz,
  Pdf4D.Tests.PdfBuilder;

type
  // The bytes of a content stream, written one piece at a time
  TGraphicsWriter = class
  strict private
    FStream: TBytesStream;

  public
    constructor Create;
    destructor Destroy; override;

    // Text with ASCII characters only
    procedure Put(const Text: string);
    procedure PutByte(const Value: Byte);
    function ToBytes: TBytes;
  end;

  // Random content streams from a grammar of all operators that the renderer draws (paths, clips, colours and colour spaces, patterns,
  // shadings, images, forms, soft masks, text and marked content), with operands of every kind. The random number generator of the
  // calling thread decides, so RandSeed decides the result.
  TGraphicsGenerator = class
  public
    const StyleCount = 8;

  strict private
    FWriter: TGraphicsWriter;

    class function Pick(const Values: array of string): string; static;
    class function ToArray(const Values: array of string): TArray<string>; static;
    class function NamesOf(const OperatorName: string): TArray<string>; static;

    procedure PutNumber;
    procedure PutCoordinate;
    procedure PutName(const Pool: array of string);
    procedure PutString;
    procedure PutArray;
    procedure PutDictionary;
    procedure PutAnyOperand;
    procedure PutOperand(const Kind: Char; const OperatorName: string);
    procedure PutOperator(const OperatorName, Operands: string);
    procedure PutRandomOperator;
    procedure PutOperators(const Count: Integer);
    procedure PutShapes;
    procedure PutClips;
    procedure PutColors;
    procedure PutText;
    procedure PutPaintedObjects;
    procedure PutInlineImages;
    procedure PutDegenerateNumbers;
    procedure PutStyle(const Style: Integer);

  public
    constructor Create;
    destructor Destroy; override;

    // The content stream of that index (seed and index together are the whole input). Index mod StyleCount decides what kind of
    // stream it is, so every kind comes up in every run.
    class function Generate(const Seed, Index: Integer): TBytes; static;
  end;

  // Documents of one page of 200 x 200 pt for the fuzz runs
  TRenderFuzzDocuments = class
  strict private
    class function PageResources: string; static;
    class procedure AddImages(const Builder: TTestPdfBuilder); static;
    class procedure AddForms(const Builder: TTestPdfBuilder); static;
    class procedure AddGraphicsStates(const Builder: TTestPdfBuilder); static;
    class procedure AddShadings(const Builder: TTestPdfBuilder); static;
    class procedure AddPatterns(const Builder: TTestPdfBuilder); static;
    class procedure AddColorSpaces(const Builder: TTestPdfBuilder); static;
    class procedure AddFonts(const Builder: TTestPdfBuilder; const LiberationSans: TBytes); static;

  public
    // A page with Content and the resources below, which a content stream names:
    //   fonts /F1 (Helvetica), /F2 (LiberationSans as Type 0 font, embedded), /F3 (Type 3);
    //   images /Im0 (RGB with a soft mask), /Im1 (stencil mask); forms /Fm1 (draws itself), /Fm2;
    //   graphics states /GS1 (line, dash, alpha, blend mode), /GS2 (luminosity soft mask whose group sets /GS2 again), /GS3 (alpha soft
    //   mask), /GS4 (font and the rest); shadings /Sh0 (axial), /Sh1 (radial), /Sh2 (triangle mesh), /Sh3 (function based);
    //   patterns /P1 (coloured tiling), /P2 (uncoloured tiling), /P3 (shading pattern), /P4 (tiling that uses itself);
    //   colour spaces /CsIcc, /CsPat, /CsIdx, /CsSep, /CsLab, /CsCal, /CsDN; properties /MC0; one annotation
    class function Page(const Content, LiberationSans: TBytes): TBytes; static;
    // A page of Resources (the text of the dictionary) that draws Content; Objects are the objects 5, 6, ... A stream is written as
    // 'stream:<entries of the dictionary>|<data>'
    class function HostilePage(const Content: string; const Resources: string; const Objects: array of string): TBytes; static;
  end;

  TRenderRobustnessTestsBase = class abstract
  strict private
    // The mapper that the fixture found, put back by TearDown (the test program installs its own for all fixtures)
    FFoundMapper: IPdfFontMapper;
    // One mapper for all runs: a mapper that has been replaced stays in memory until the process ends
    class var FHermeticMapper: IPdfFontMapper;

    function PixelOf(const Content: string; const X, Y: Integer): TPdfDeviceColor;
    class function RepeatText(const Text: string; const Count: Integer): string; static;
    class function PageWithImage(const ImageEntries: string; const ImageData: TBytes; const Extra: string = ''): TBytes; static;
    class procedure RunHostileImages(const Campaign: TFuzzCampaign); static;
    class procedure RunHostilePaint(const Campaign: TFuzzCampaign); static;
    class procedure RunHostileGeometry(const Campaign: TFuzzCampaign); static;

  protected
    function CreateBackend: IPdfRenderBackend; virtual; abstract;
    // Documents that only one backend gets (the huge ones of the native backend); nothing by default
    procedure RunExtraHostile(const Campaign: TFuzzCampaign); virtual;

    class function Latin1(const Text: string): TBytes; static;
    class procedure RunHostile(const Campaign: TFuzzCampaign; const Name: string; const Document: TBytes; const TimeLimitSeconds: Integer = 0); static;
    class procedure RunHostileContent(const Campaign: TFuzzCampaign; const Name, Content: string; const TimeLimitSeconds: Integer = 0); static;

  public
    [Setup]
    procedure SetUp;

    [TearDown]
    procedure TearDown;

    // The page of the generated streams has the resources that the grammar names: what it draws is not white
    [Test]
    procedure TestPageOfGeneratedStreamsDrawsItsResources;
    [Test]
    procedure TestMutatedCorpusRendersSafely;
    [Test]
    procedure TestGeneratedGraphicsStreamsRenderSafely;
    [Test]
    procedure TestHostileRenderDocuments;
  end;

implementation

uses
  Pdf4D.Api.Document,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Common.Defines,
  Pdf4D.Font.MapperImpl,
  Pdf4D.Render.Renderer,
  Pdf4D.Render.Renderer.Interfaces,
  Pdf4D.Model.Tests.Support,
  Pdf4D.Resources.Icc,
  Pdf4D.Tests.FontProvider,
  Pdf4D.Tests.TestFonts;

type
  TOperatorShape = record
    Name: string;
    // One letter per operand: n number, N name, s string, a array, d dictionary
    Operands: string;
  end;

const
  GraphicsSeed = 8642;
  {$IFDEF DEBUG}
  // A Debug build renders about three times slower than a Release build (TFuzzSettings in Pdf4D.Tests.Fuzz holds both Debug counts)
  GraphicsStreamCount = TFuzzSettings.DebugRenderGraphicsStreams;
  {$ELSE}
  GraphicsStreamCount = 2000;
  {$ENDIF}
  LiberationSansFile = 'LiberationSans-Regular.ttf';
  NameOperandFormat = '/%s ';
  OperatorFormat = '%s ';
  InlineImageFormat = 'BI %s ';
  JpegFile = 'pdfbox-jpeg.jpg';
  PageFormat = '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources %s %s >>';
  FormStart = '/Type /XObject /Subtype /Form /BBox [0 0 200 200] ';
  StreamPrefix = 'stream:';

  Shapes: array[0..78] of TOperatorShape = (
    (Name: 'm'; Operands: 'nn'), (Name: 'l'; Operands: 'nn'), (Name: 'c'; Operands: 'nnnnnn'), (Name: 'v'; Operands: 'nnnn'),
    (Name: 'y'; Operands: 'nnnn'), (Name: 'h'; Operands: ''), (Name: 're'; Operands: 'nnnn'), (Name: 'S'; Operands: ''),
    (Name: 's'; Operands: ''), (Name: 'f'; Operands: ''), (Name: 'F'; Operands: ''), (Name: 'f*'; Operands: ''),
    (Name: 'B'; Operands: ''), (Name: 'B*'; Operands: ''), (Name: 'b'; Operands: ''), (Name: 'b*'; Operands: ''),
    (Name: 'n'; Operands: ''), (Name: 'W'; Operands: ''), (Name: 'W*'; Operands: ''), (Name: 'q'; Operands: ''),
    (Name: 'Q'; Operands: ''), (Name: 'cm'; Operands: 'nnnnnn'), (Name: 'w'; Operands: 'n'), (Name: 'J'; Operands: 'n'),
    (Name: 'j'; Operands: 'n'), (Name: 'M'; Operands: 'n'), (Name: 'd'; Operands: 'an'), (Name: 'ri'; Operands: 'N'),
    (Name: 'i'; Operands: 'n'), (Name: 'gs'; Operands: 'N'), (Name: 'g'; Operands: 'n'), (Name: 'G'; Operands: 'n'),
    (Name: 'rg'; Operands: 'nnn'), (Name: 'RG'; Operands: 'nnn'), (Name: 'k'; Operands: 'nnnn'), (Name: 'K'; Operands: 'nnnn'),
    (Name: 'cs'; Operands: 'N'), (Name: 'CS'; Operands: 'N'), (Name: 'sc'; Operands: 'nnn'), (Name: 'SC'; Operands: 'nnn'),
    (Name: 'scn'; Operands: 'nnnN'), (Name: 'SCN'; Operands: 'nnnN'), (Name: 'sh'; Operands: 'N'), (Name: 'Do'; Operands: 'N'),
    (Name: 'BT'; Operands: ''), (Name: 'ET'; Operands: ''), (Name: 'Tc'; Operands: 'n'), (Name: 'Tw'; Operands: 'n'),
    (Name: 'Tz'; Operands: 'n'), (Name: 'TL'; Operands: 'n'), (Name: 'Tf'; Operands: 'Nn'), (Name: 'Tr'; Operands: 'n'),
    (Name: 'Ts'; Operands: 'n'), (Name: 'Td'; Operands: 'nn'), (Name: 'TD'; Operands: 'nn'), (Name: 'Tm'; Operands: 'nnnnnn'),
    (Name: 'T*'; Operands: ''), (Name: 'Tj'; Operands: 's'), (Name: 'TJ'; Operands: 'a'), (Name: ''''; Operands: 's'),
    (Name: '"'; Operands: 'nns'), (Name: 'd0'; Operands: 'nn'), (Name: 'd1'; Operands: 'nnnnnn'), (Name: 'BMC'; Operands: 'N'),
    (Name: 'BDC'; Operands: 'Nd'), (Name: 'MP'; Operands: 'N'), (Name: 'DP'; Operands: 'Nd'), (Name: 'EMC'; Operands: ''),
    (Name: 'BX'; Operands: ''), (Name: 'EX'; Operands: ''), (Name: 'BDC'; Operands: 'NN'), (Name: 'sh'; Operands: 'N'),
    (Name: 'Do'; Operands: 'N'), (Name: 'gs'; Operands: 'N'), (Name: 'f'; Operands: ''), (Name: 'S'; Operands: ''),
    (Name: 'B'; Operands: ''), (Name: 'scn'; Operands: 'N'), (Name: 'cs'; Operands: 'N')
  );

  // The shapes that build and paint paths, which are most of what the renderer draws
  PathShapeCount = 19;

  Numbers: array[0..39] of string = (
    '0', '-0', '+0', '.0', '-.0', '0.', '0.0000000000001', '1', '-1', '12', '0.5', '-3.75', '255', '65535', '65536', '2147483647',
    '2147483648', '-2147483648', '-2147483649', '4294967296', '9223372036854775807', '9223372036854775808', '-9223372036854775808',
    '340282346638528859811704183484516925440', '340282366920938463463374607431768211456', '99999999999999999999999999999999999999999999999999',
    '-99999999999999999999999999999999999999999999999999', '0.00000000000000000000000000000000000000000000001', '1e10', '1e308',
    '1.2.3', '--5', '+-5', '1-2', '.', '-', 'NaN', '-Infinity', '1.#INF', '-1.#IND');

  Degenerate: array[0..11] of string = ('1e30', '-1e30', '1e38', '-1e38', '3.4e38', '0.0000001', '100000', '-100000', '99999999999', '0', '0.001', '16777217');

  ColorSpaceNames: array[0..11] of string = ('DeviceRGB', 'DeviceGray', 'DeviceCMYK', 'Pattern', 'CsIcc', 'CsPat', 'CsIdx', 'CsSep',
                                             'CsLab', 'CsCal', 'CsDN', 'Missing');
  GraphicsStateNames: array[0..4] of string = ('GS1', 'GS2', 'GS3', 'GS4', 'Missing');
  XObjectNames: array[0..4] of string = ('Im0', 'Im1', 'Fm1', 'Fm2', 'Missing');
  ShadingNames: array[0..4] of string = ('Sh0', 'Sh1', 'Sh2', 'Sh3', 'Missing');
  PatternNames: array[0..4] of string = ('P1', 'P2', 'P3', 'P4', 'Missing');
  FontNames: array[0..4] of string = ('F1', 'F2', 'F3', 'Missing', '');
  MarkedNames: array[0..5] of string = ('OC', 'Span', 'Artifact', 'MC0', 'P', 'Missing');
  IntentNames: array[0..4] of string = ('RelativeColorimetric', 'AbsoluteColorimetric', 'Perceptual', 'Saturation', 'Foo');

  InlineImageDictionaries: array[0..7] of string = (
    '/W 1 /H 1 /BPC 8 /CS /G', '/W 100000 /H 100000 /BPC 8 /CS /RGB', '/W -1 /H -1', '/W 2 /H 2 /BPC 1 /IM true /F /AHx',
    '/W 1 /H 1 /BPC 8 /CS /G /F [/Fl /A85] /DP [<< /Predictor 15 >> null]', '/Garbage << [ ] >> /W',
    '/W 4 /H 4 /BPC 8 /CS /CMYK /D [1 0 1 0 1 0 1 0]', '/W 3 /H 3 /BPC 4 /CS [/I /RGB 1 <FF000000FF00>]');

{ TGraphicsWriter }

constructor TGraphicsWriter.Create;
begin
  inherited Create;
  FStream := TBytesStream.Create;
end;

destructor TGraphicsWriter.Destroy;
begin
  FStream.Free;
  inherited;
end;

procedure TGraphicsWriter.Put(const Text: string);
begin
  for var Character in Text do
  begin
    PutByte(Byte(Ord(Character) and $7F));
  end;
end;

procedure TGraphicsWriter.PutByte(const Value: Byte);
begin
  FStream.WriteBuffer(Value, 1);
end;

function TGraphicsWriter.ToBytes: TBytes;
begin
  Result := Copy(FStream.Bytes, 0, FStream.Size);
end;

{ TGraphicsGenerator }

constructor TGraphicsGenerator.Create;
begin
  inherited Create;
  FWriter := TGraphicsWriter.Create;
end;

destructor TGraphicsGenerator.Destroy;
begin
  FWriter.Free;
  inherited;
end;

class function TGraphicsGenerator.Pick(const Values: array of string): string;
begin
  Result := Values[Random(Length(Values))];
end;

class function TGraphicsGenerator.ToArray(const Values: array of string): TArray<string>;
begin
  SetLength(Result, Length(Values));
  for var Index := 0 to High(Values) do
  begin
    Result[Index] := Values[Index];
  end;
end;

class function TGraphicsGenerator.NamesOf(const OperatorName: string): TArray<string>;
begin
  if (OperatorName = 'cs') or (OperatorName = 'CS') then
  begin
    Result := ToArray(ColorSpaceNames);
  end
  else if OperatorName = 'gs' then
  begin
    Result := ToArray(GraphicsStateNames);
  end
  else if OperatorName = 'Do' then
  begin
    Result := ToArray(XObjectNames);
  end
  else if OperatorName = 'sh' then
  begin
    Result := ToArray(ShadingNames);
  end
  else if (OperatorName = 'scn') or (OperatorName = 'SCN') then
  begin
    Result := ToArray(PatternNames);
  end
  else if OperatorName = 'Tf' then
  begin
    Result := ToArray(FontNames);
  end
  else if OperatorName = 'ri' then
  begin
    Result := ToArray(IntentNames);
  end
  else
  begin
    Result := ToArray(MarkedNames);
  end;
end;

procedure TGraphicsGenerator.PutNumber;
begin
  case Random(12) of
    0..5: FWriter.Put(IntToStr(Random(260) - 30));
    6..8: FWriter.Put(Format('%d.%d', [Random(260) - 30, Random(1000)], TFormatSettings.Invariant));
    9: FWriter.Put(Format('%d.%d', [Random(2), Random(1000)], TFormatSettings.Invariant));
    10: FWriter.Put(Pick(Degenerate));
  else
    FWriter.Put(Pick(Numbers));
  end;
  FWriter.Put(' ');
end;

// A coordinate on or near the page
procedure TGraphicsGenerator.PutCoordinate;
begin
  FWriter.Put(Format('%d.%d ', [Random(220) - 10, Random(100)], TFormatSettings.Invariant));
end;

procedure TGraphicsGenerator.PutName(const Pool: array of string);
begin
  FWriter.Put(Format(NameOperandFormat, [Pick(Pool)]));
end;

procedure TGraphicsGenerator.PutString;
begin
  FWriter.Put('(');
  for var Index := 1 to Random(30) do
  begin
    case Random(4) of
      0: FWriter.PutByte(Random(256));
      1: FWriter.Put(Pick(['\(', '\)', '\\', '\n', '\101']));
    else
      FWriter.PutByte(32 + Random(95));
    end;
  end;
  FWriter.Put(') ');
end;

procedure TGraphicsGenerator.PutArray;
begin
  FWriter.Put('[ ');
  for var Index := 1 to Random(8) do
  begin
    if Random(3) = 0 then
    begin
      PutString;
    end
    else
    begin
      PutNumber;
    end;
  end;
  FWriter.Put('] ');
end;

procedure TGraphicsGenerator.PutDictionary;
begin
  FWriter.Put('<< ');
  for var Index := 1 to Random(4) do
  begin
    PutName(['MCID', 'ActualText', 'E', 'Lang', 'Type', 'O']);
    if Random(2) = 0 then
    begin
      PutNumber;
    end
    else
    begin
      PutString;
    end;
  end;
  FWriter.Put('>> ');
end;

procedure TGraphicsGenerator.PutAnyOperand;
begin
  case Random(9) of
    0: PutNumber;
    1: PutName(FontNames);
    2: PutString;
    3: PutArray;
    4: PutDictionary;
    5: FWriter.Put(Pick(['true ', 'false ', 'null ']));
    6: PutName(ColorSpaceNames);
    7: FWriter.Put('<< >> ');
  else
    FWriter.Put('[ [ [ << /A [ ] >> ] ] ] ');
  end;
end;

procedure TGraphicsGenerator.PutOperand(const Kind: Char; const OperatorName: string);
begin
  case Kind of
    'n': PutNumber;
    's': PutString;
    'a': PutArray;
    'd': PutDictionary;
  else
    PutName(NamesOf(OperatorName));
  end;
end;

procedure TGraphicsGenerator.PutOperator(const OperatorName, Operands: string);
begin
  if Random(5) = 0 then
  begin
    // Wrong operands: another number of them, of any type
    for var Index := 1 to Random(9) do
    begin
      PutAnyOperand;
    end;
  end
  else
  begin
    for var Index := 1 to Length(Operands) do
    begin
      PutOperand(Operands[Index], OperatorName);
    end;
  end;
  FWriter.Put(Format(OperatorFormat, [OperatorName]));
end;

procedure TGraphicsGenerator.PutRandomOperator;
begin
  const Shape = Shapes[Random(Length(Shapes))];
  PutOperator(Shape.Name, Shape.Operands);
end;

procedure TGraphicsGenerator.PutOperators(const Count: Integer);
begin
  for var Index := 1 to Count do
  begin
    PutRandomOperator;
    if Random(20) = 0 then
    begin
      FWriter.Put(sLineBreak);
    end;
  end;
end;

// Paths with plausible coordinates, painted and stroked in different ways, with state that changes in between
procedure TGraphicsGenerator.PutShapes;
begin
  for var Shape := 1 to 10 + Random(40) do
  begin
    if Random(4) = 0 then
    begin
      PutOperator(Pick(['w', 'J', 'j', 'M', 'd', 'gs', 'g', 'rg', 'RG', 'k', 'cm', 'q', 'Q']), '');
    end;
    FWriter.Put(Format('%d %d m ', [Random(200), Random(200)]));
    for var Segment := 1 to Random(8) do
    begin
      case Random(5) of
        0, 1:
        begin
          PutCoordinate;
          PutCoordinate;
          FWriter.Put('l ');
        end;
        2:
        begin
          for var Index := 1 to 6 do
          begin
            PutCoordinate;
          end;
          FWriter.Put('c ');
        end;
        3:
        begin
          for var Index := 1 to 4 do
          begin
            PutCoordinate;
          end;
          FWriter.Put(Pick(['v ', 'y ']));
        end;
      else
        for var Index := 1 to 4 do
        begin
          PutCoordinate;
        end;
        FWriter.Put('re ');
      end;
    end;
    FWriter.Put(Pick(['h ', '']));
    FWriter.Put(Pick(['S ', 's ', 'f ', 'f* ', 'B ', 'B* ', 'b ', 'b* ', 'n ']));
  end;
end;

procedure TGraphicsGenerator.PutClips;
begin
  for var Round := 1 to 5 + Random(20) do
  begin
    FWriter.Put('q ');
    for var Piece := 1 to 1 + Random(3) do
    begin
      FWriter.Put(Format('%d %d %d %d re ', [Random(200), Random(200), Random(150) - 20, Random(150) - 20]));
    end;
    FWriter.Put(Pick(['W n ', 'W* n ', 'W f ', 'W* S ', 'W ', 'W* ']));
    FWriter.Put(Format('%d %d %d %d re ', [Random(200), Random(200), Random(200), Random(200)]));
    FWriter.Put(Pick(['f ', 'B ', 'S ']));
    PutRandomOperator;
    if Random(3) <> 0 then
    begin
      FWriter.Put('Q ');
    end;
  end;
end;

procedure TGraphicsGenerator.PutColors;
begin
  for var Round := 1 to 10 + Random(30) do
  begin
    case Random(4) of
      0: PutOperator(Pick(['cs', 'CS']), 'N');
      1:
      begin
        for var Index := 1 to Random(6) do
        begin
          PutNumber;
        end;
        FWriter.Put(Pick(['sc ', 'SC ', 'scn ', 'SCN ']));
      end;
      2:
      begin
        for var Index := 1 to Random(5) do
        begin
          PutNumber;
        end;
        PutName(PatternNames);
        FWriter.Put(Pick(['scn ', 'SCN ']));
      end;
    else
      PutOperator(Pick(['g', 'G', 'rg', 'RG', 'k', 'K']), Pick(['n', 'nnn', 'nnnn']));
    end;
    FWriter.Put(Format('%d %d %d %d re ', [Random(200), Random(200), Random(120), Random(120)]));
    FWriter.Put(Pick(['f ', 'B ', 'S ', 'f* ']));
  end;
end;

procedure TGraphicsGenerator.PutText;
begin
  FWriter.Put('BT ');
  for var Round := 1 to 10 + Random(40) do
  begin
    case Random(6) of
      0:
      begin
        PutName(FontNames);
        FWriter.Put(Pick(['12 ', '1 ', '0 ', '-8 ', '100 ', '24 ']));
        FWriter.Put('Tf ');
      end;
      1: FWriter.Put(Format('%d Tr ', [Random(10)]));
      2: FWriter.Put(Format('1 0 0 1 %d %d Tm ', [Random(200), Random(200)]));
      3:
      begin
        PutString;
        FWriter.Put(Pick(['Tj ', '''', '" ']));
      end;
      4:
      begin
        PutArray;
        FWriter.Put('TJ ');
      end;
    else
      PutOperator(Pick(['Tc', 'Tw', 'Tz', 'TL', 'Ts', 'Td', 'TD', 'T*', 'q', 'Q', 'cm', 'w', 'rg']), '');
    end;
  end;
  FWriter.Put(Pick(['ET ', '']));
end;

// Forms, images, shadings and graphics states with soft masks, in any state
procedure TGraphicsGenerator.PutPaintedObjects;
begin
  for var Round := 1 to 5 + Random(25) do
  begin
    if Random(3) = 0 then
    begin
      PutRandomOperator;
    end;
    case Random(5) of
      0: FWriter.Put(Format('q %d 0 0 %d %d %d cm /%s Do Q ', [Random(200) - 20, Random(200) - 20, Random(100), Random(100), Pick(XObjectNames)]));
      1: FWriter.Put(Format('/%s sh ', [Pick(ShadingNames)]));
      2: FWriter.Put(Format('/%s gs ', [Pick(GraphicsStateNames)]));
      3: FWriter.Put(Format('/%s Do ', [Pick(XObjectNames)]));
    else
      FWriter.Put(Format('q 0 0 %d %d re W n /%s sh Q ', [Random(200), Random(200), Pick(ShadingNames)]));
    end;
  end;
end;

procedure TGraphicsGenerator.PutInlineImages;
begin
  for var Index := 1 to 1 + Random(4) do
  begin
    FWriter.Put('q 100 0 0 100 20 20 cm ');
    FWriter.Put(Format(InlineImageFormat, [Pick(InlineImageDictionaries)]));
    case Random(4) of
      0: ;
      1: FWriter.Put('ID ');
    else
      FWriter.Put('ID ');
      for var Count := 1 to Random(2000) do
      begin
        FWriter.PutByte(Random(256));
      end;
      if Random(4) <> 0 then
      begin
        FWriter.Put(' EI ');
      end;
    end;
    FWriter.Put('Q ');
  end;
end;

procedure TGraphicsGenerator.PutDegenerateNumbers;
begin
  for var Round := 1 to 20 + Random(60) do
  begin
    case Random(6) of
      0:
      begin
        for var Index := 1 to 6 do
        begin
          FWriter.Put(Pick(Degenerate) + ' ');
        end;
        FWriter.Put('cm ');
      end;
      1: FWriter.Put(Format('%s %s m %s %s l %s %s l h ', [Pick(Degenerate), Pick(Degenerate), Pick(Degenerate), Pick(Degenerate), Pick(Degenerate), Pick(Degenerate)]));
      2: FWriter.Put(Format('%s w ', [Pick(Degenerate)]));
      3: FWriter.Put(Format('[%s %s] %s d ', [Pick(['0', '0.0001', '1e30', '5']), Pick(['0', '0.0001', '1e30', '5']), Pick(Degenerate)]));
      4: FWriter.Put(Format('%s %s %s %s re ', [Pick(Degenerate), Pick(Degenerate), Pick(Degenerate), Pick(Degenerate)]));
    else
      FWriter.Put(Pick(['f ', 'S ', 'B ', 'W n ', 'f* ', 'b* ', 'q ', 'Q ']));
    end;
    if Random(3) = 0 then
    begin
      FWriter.Put(Pick(['f ', 'S ', 'B ', 'f* ']));
    end;
  end;
end;

procedure TGraphicsGenerator.PutStyle(const Style: Integer);
begin
  case Style of
    0: PutOperators(60 + Random(200));
    1: PutShapes;
    2: PutClips;
    3: PutColors;
    4: PutText;
    5: PutPaintedObjects;
    6: PutInlineImages;
  else
    // Degenerate numbers, then pieces of the other styles one after the other
    PutDegenerateNumbers;
    for var Piece := 1 to 2 do
    begin
      PutStyle(Random(StyleCount - 1));
    end;
  end;
end;

class function TGraphicsGenerator.Generate(const Seed, Index: Integer): TBytes;
begin
  RandSeed := Seed + Index;
  const Generator = TGraphicsGenerator.Create;
  try
    // A coloured and a stroked start, so that the first operators have something to draw with
    Generator.FWriter.Put('1 0 0 rg 0 0 1 RG 2 w ');
    Generator.PutStyle(Index mod StyleCount);
    Result := Generator.FWriter.ToBytes;
  finally
    Generator.Free;
  end;
end;

{ TRenderFuzzDocuments }

class function TRenderFuzzDocuments.PageResources: string;
begin
  Result := '<< /Font << /F1 10 0 R /F2 11 0 R /F3 12 0 R >> ' +
            '/XObject << /Im0 60 0 R /Im1 61 0 R /Fm1 62 0 R /Fm2 63 0 R >> ' +
            '/ExtGState << /GS1 70 0 R /GS2 71 0 R /GS3 72 0 R /GS4 73 0 R >> ' +
            '/Shading << /Sh0 80 0 R /Sh1 81 0 R /Sh2 82 0 R /Sh3 83 0 R >> ' +
            '/Pattern << /P1 90 0 R /P2 91 0 R /P3 92 0 R /P4 93 0 R >> ' +
            '/ColorSpace << /CsIcc [/ICCBased 100 0 R] /CsPat [/Pattern /DeviceRGB] /CsIdx [/Indexed /DeviceRGB 3 <FF000000FF000000FFFFFF00>] ' +
            '/CsSep [/Separation /Spot /DeviceCMYK 101 0 R] /CsLab [/Lab << /WhitePoint [0.95 1 1.09] /Range [-100 100 -100 100] >>] ' +
            '/CsCal [/CalRGB << /WhitePoint [0.95 1 1.09] /Gamma [2.2 2.2 2.2] >>] /CsDN [/DeviceN [/A /B] /DeviceRGB 102 0 R] >> ' +
            '/Properties << /MC0 110 0 R >> >>';
end;

class procedure TRenderFuzzDocuments.AddImages(const Builder: TTestPdfBuilder);
begin
  var Ramp: TBytes;
  SetLength(Ramp, 48);
  for var Index := 0 to High(Ramp) do
  begin
    Ramp[Index] := Byte(Index * 5);
  end;
  Builder.AddStreamObject(60, '/Type /XObject /Subtype /Image /Width 4 /Height 4 /ColorSpace /DeviceRGB /BitsPerComponent 8 /SMask 64 0 R', Ramp);
  Builder.AddStreamObject(61, '/Type /XObject /Subtype /Image /Width 8 /Height 8 /ImageMask true /BitsPerComponent 1',
                          TBytes.Create($AA, $55, $AA, $55, $F0, $0F, $F0, $0F));
  Builder.AddStreamObject(64, '/Type /XObject /Subtype /Image /Width 4 /Height 4 /ColorSpace /DeviceGray /BitsPerComponent 8',
                          Copy(Ramp, 0, 16));
end;

class procedure TRenderFuzzDocuments.AddForms(const Builder: TTestPdfBuilder);
const
  SelfResources = '/Resources << /XObject << /Fm1 62 0 R >> >> ';
begin
  Builder.AddStreamObject(62, FormStart + SelfResources, TEncoding.ASCII.GetBytes('0 1 0 rg 0 0 50 50 re f /Fm1 Do'));
  Builder.AddStreamObject(63, FormStart + '/Resources << /Font << /F1 10 0 R >> >> ',
                          TEncoding.ASCII.GetBytes('1 0 0 rg 10 10 80 80 re f BT /F1 12 Tf 20 20 Td (Hi) Tj ET'));
end;

class procedure TRenderFuzzDocuments.AddGraphicsStates(const Builder: TTestPdfBuilder);
const
  GroupEntries = '/Group << /S /Transparency /CS /DeviceGray >> ';
begin
  Builder.AddObject(70, '<< /Type /ExtGState /LW 3 /LC 1 /LJ 1 /D [[3 2] 0] /CA 0.5 /ca 0.5 /BM /Multiply >>');
  Builder.AddObject(71, '<< /Type /ExtGState /SMask << /Type /Mask /S /Luminosity /G 74 0 R /BC [0] >> >>');
  Builder.AddObject(72, '<< /Type /ExtGState /SMask << /Type /Mask /S /Alpha /G 75 0 R >> >>');
  Builder.AddObject(73, '<< /Type /ExtGState /Font [10 0 R 12] /OP true /op true /OPM 1 /SA true /AIS false /TK false /FL 3 /SM 0.1 ' +
                        '/BM [/Foo /Normal] /TR /Identity /HT /Default /ML 4 /RI /Perceptual >>');
  // The group of the soft mask sets the soft mask again
  Builder.AddStreamObject(74, FormStart + GroupEntries + '/Resources << /ExtGState << /GS2 71 0 R >> >> ',
                          TEncoding.ASCII.GetBytes('0.5 g 0 0 200 200 re f /GS2 gs 1 g 0 0 100 100 re f'));
  Builder.AddStreamObject(75, FormStart + GroupEntries, TEncoding.ASCII.GetBytes('0 g 20 20 120 120 re f'));
end;

class procedure TRenderFuzzDocuments.AddShadings(const Builder: TTestPdfBuilder);
begin
  // Three vertices of a triangle mesh: flag, x, y and three colour values of one byte each
  const Triangle: TBytes = [0, 10, 10, 255, 0, 0, 0, 240, 20, 0, 255, 0, 0, 120, 240, 0, 0, 255];
  Builder.AddObject(84, '<< /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >>');
  Builder.AddObject(80, '<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 200 200] /Function 84 0 R /Extend [true true] >>');
  Builder.AddObject(81, '<< /ShadingType 3 /ColorSpace /DeviceRGB /Coords [100 100 0 100 100 80] /Function 84 0 R /Extend [true false] >>');
  Builder.AddStreamObject(82, '/ShadingType 4 /ColorSpace /DeviceRGB /BitsPerCoordinate 8 /BitsPerComponent 8 /BitsPerFlag 8 ' +
                              '/Decode [0 200 0 200 0 1 0 1 0 1]', Triangle);
  Builder.AddObject(83, '<< /ShadingType 1 /ColorSpace /DeviceRGB /Domain [0 1 0 1] /Matrix [200 0 0 200 0 0] /Function 85 0 R >>');
  Builder.AddStreamObject(85, '/FunctionType 4 /Domain [0 1 0 1] /Range [0 1 0 1 0 1]', TEncoding.ASCII.GetBytes('{ 2 copy mul }'));
end;

class procedure TRenderFuzzDocuments.AddPatterns(const Builder: TTestPdfBuilder);
const
  Entries = '/Type /Pattern /PatternType 1 /TilingType 1 /BBox [0 0 20 20] /XStep 20 /YStep 20 ';
begin
  Builder.AddStreamObject(90, Entries + '/PaintType 1 /Resources << >>', TEncoding.ASCII.GetBytes('1 0 0 rg 0 0 10 10 re f 0 0 1 rg 10 10 10 10 re f'));
  Builder.AddStreamObject(91, Entries + '/PaintType 2 /Resources << >>', TEncoding.ASCII.GetBytes('0 0 10 10 re f'));
  Builder.AddObject(92, '<< /Type /Pattern /PatternType 2 /Shading 80 0 R /Matrix [1 0 0 1 0 0] >>');
  // The pattern paints with itself
  Builder.AddStreamObject(93, Entries + '/PaintType 1 /Resources << /Pattern << /P4 93 0 R >> /ColorSpace << /CsPat [/Pattern] >> >>',
                          TEncoding.ASCII.GetBytes('/CsPat cs /P4 scn 0 0 10 10 re f'));
end;

class procedure TRenderFuzzDocuments.AddColorSpaces(const Builder: TTestPdfBuilder);
begin
  Builder.AddStreamObject(100, '/N 4', TPdfIccResources.CmykProfile);
  Builder.AddObject(101, '<< /FunctionType 2 /Domain [0 1] /C0 [0 0 0 0] /C1 [0 1 1 0] /N 1 >>');
  Builder.AddStreamObject(102, '/FunctionType 4 /Domain [0 1 0 1] /Range [0 1 0 1 0 1]', TEncoding.ASCII.GetBytes('{ 2 copy add 2 div }'));
  Builder.AddObject(110, '<< /Type /OCG /Name (layer) >>');
end;

class procedure TRenderFuzzDocuments.AddFonts(const Builder: TTestPdfBuilder; const LiberationSans: TBytes);
begin
  Builder.AddObject(10, '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
  Builder.AddObject(11, '<< /Type /Font /Subtype /Type0 /BaseFont /LiberationSans /Encoding /Identity-H /DescendantFonts [ 13 0 R ] >>');
  Builder.AddObject(12, '<< /Type /Font /Subtype /Type3 /FontBBox [0 0 100 100] /FontMatrix [0.01 0 0 0.01 0 0] ' +
                        '/CharProcs << /a 30 0 R /b 31 0 R >> /Encoding << /Type /Encoding /Differences [97 /a /b] >> ' +
                        '/FirstChar 97 /LastChar 98 /Widths [50 60] /Resources << /Font << /F3 12 0 R >> >> >>');
  Builder.AddObject(13, '<< /Type /Font /Subtype /CIDFontType2 /BaseFont /LiberationSans /FontDescriptor 20 0 R ' +
                        '/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /CIDToGIDMap /Identity /DW 600 >>');
  Builder.AddObject(20, '<< /Type /FontDescriptor /FontName /LiberationSans /Flags 4 /FontBBox [0 0 1000 1000] /FontFile2 21 0 R >>');
  Builder.AddStreamObject(21, Format('/Length1 %d', [Length(LiberationSans)]), LiberationSans);
  // The second glyph shows text in the Type 3 font itself
  Builder.AddStreamObject(30, '', TEncoding.ASCII.GetBytes('50 0 d0 0 0 100 100 re f'));
  Builder.AddStreamObject(31, '', TEncoding.ASCII.GetBytes('60 0 0 0 100 100 d1 0 0 50 50 re f BT /F3 100 Tf (ab) Tj ET'));
end;

class function TRenderFuzzDocuments.Page(const Content, LiberationSans: TBytes): TBytes;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  try
    Builder.AddObject(3, Format(PageFormat, [PageResources, '/Annots [120 0 R]']));
    Builder.AddStreamObject(4, '', Content);
    AddFonts(Builder, LiberationSans);
    AddImages(Builder);
    AddForms(Builder);
    AddGraphicsStates(Builder);
    AddShadings(Builder);
    AddPatterns(Builder);
    AddColorSpaces(Builder);
    Builder.AddObject(120, '<< /Type /Annot /Subtype /Square /Rect [10 10 100 100] /F 4 /AP << /N 121 0 R >> >>');
    Builder.AddStreamObject(121, FormStart + '/Resources << /XObject << /Fm1 62 0 R /Self 121 0 R >> >> ',
                            TEncoding.ASCII.GetBytes('0 0 1 rg 0 0 100 100 re f /Fm1 Do'));
    Result := Builder.Build(TXrefStyle.Table);
  finally
    Builder.Free;
  end;
end;

class function TRenderFuzzDocuments.HostilePage(const Content: string; const Resources: string; const Objects: array of string): TBytes;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  try
    Builder.AddObject(3, Format(PageFormat, [Resources, '']));
    Builder.AddStreamObject(4, '', TEncoding.ASCII.GetBytes(Content));
    for var Index := 0 to High(Objects) do
    begin
      if Objects[Index].StartsWith(StreamPrefix) then
      begin
        const Parts = Objects[Index].Substring(Length(StreamPrefix)).Split(['|']);
        Builder.AddStreamObject(5 + Index, Parts[0], TEncoding.ASCII.GetBytes(Parts[1]));
      end
      else
      begin
        Builder.AddObject(5 + Index, Objects[Index]);
      end;
    end;
    Result := Builder.Build(TXrefStyle.Table);
  finally
    Builder.Free;
  end;
end;

{ TRenderRobustnessTestsBase }

procedure TRenderRobustnessTestsBase.SetUp;
begin
  // The renders use no font of the machine: embedded fonts, the standard 14 and the built-in LiberationSans
  if not Assigned(FHermeticMapper) then
  begin
    FHermeticMapper := TFontMapperImpl.Create(TTestFontProvider.Empty);
  end;
  FFoundMapper := TPdfFontMappers.Instance;
  TPdfFontMappers.SetInstance(FHermeticMapper);
  TFuzzRendering.Backend := function: IPdfRenderBackend
    begin
      Result := CreateBackend;
    end;
end;

procedure TRenderRobustnessTestsBase.RunExtraHostile(const Campaign: TFuzzCampaign);
begin
end;

procedure TRenderRobustnessTestsBase.TearDown;
begin
  TFuzzRendering.Backend := nil;
  TPdfFontMappers.SetInstance(FFoundMapper);
  FFoundMapper := nil;
end;

class function TRenderRobustnessTestsBase.Latin1(const Text: string): TBytes;
begin
  SetLength(Result, Length(Text));
  for var Index := 0 to High(Result) do
  begin
    Result[Index] := Byte(Ord(Text[Index + 1]) and $FF);
  end;
end;

class function TRenderRobustnessTestsBase.RepeatText(const Text: string; const Count: Integer): string;
begin
  const Builder = TStringBuilder.Create(Length(Text) * Count);
  try
    for var Index := 1 to Count do
    begin
      Builder.Append(Text);
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

// The colour of a pixel of the page at 36 DPI (100 x 100 pixels), top left is (0, 0)
function TRenderRobustnessTestsBase.PixelOf(const Content: string; const X, Y: Integer): TPdfDeviceColor;
begin
  const Stream = TBytesStream.Create(TRenderFuzzDocuments.Page(Latin1(Content), TTestFonts.Bytes(LiberationSansFile)));
  try
    const Document: IPdfDocument = TPdfDocument.Load(Stream, TPdfLoadOptions.Default);
    const Renderer: IPdfRenderer = TPdfRenderer.Create(Document, CreateBackend);
    var Bitmap: TPdfBitmap := nil;
    try
      Renderer.RenderToBitmap(0, TPdfRenderParams.FromDpi(36), Bitmap);
      Result := Bitmap.GetPixel(X, Y);
    finally
      Bitmap.Free;
    end;
  finally
    Stream.Free;
  end;
end;

procedure TRenderRobustnessTestsBase.TestPageOfGeneratedStreamsDrawsItsResources;
const
  // The pixel is at (120, 120) pt, outside the rectangle of the annotation
  Left = 60;
  Top = 40;
  Contents: array[0..7] of string = (
    '0 0 1 rg 0 0 200 200 re f',
    '/Sh0 sh',
    '/Sh2 sh',
    '/Sh3 sh',
    'q 200 0 0 200 0 0 cm /Im0 Do Q',
    '0 0 1 rg q 200 0 0 200 0 0 cm /Im1 Do Q',
    '/Pattern cs /P1 scn 0 0 200 200 re f',
    '/CsIcc cs 0 1 1 0 sc 0 0 200 200 re f');
begin
  const White = TPdfDeviceColor.White;
  for var Index := 0 to High(Contents) do
  begin
    const Pixel = PixelOf(Contents[Index], Left, Top);
    const IsWhite = (Pixel.R = White.R) and (Pixel.G = White.G) and (Pixel.B = White.B);
    Assert.IsFalse(IsWhite, Format('The page of "%s" is white at (120, 120)', [Contents[Index]]));
  end;
end;

procedure TRenderRobustnessTestsBase.TestMutatedCorpusRendersSafely;
begin
  TFuzzCampaign.RunMutatedCorpus(TFuzzWork.Render, True);
end;

procedure TRenderRobustnessTestsBase.TestGeneratedGraphicsStreamsRenderSafely;
begin
  const LiberationSans = TTestFonts.Bytes(LiberationSansFile);
  const Seed = GraphicsSeed + TFuzzSettings.SeedOffset;
  const Campaign = TFuzzCampaign.Create;
  try
    for var Index := 0 to TFuzzSettings.Scale(GraphicsStreamCount) - 1 do
    begin
      const Content = TGraphicsGenerator.Generate(Seed, Index);
      const Name = Format('graphics stream seed %d index %d (style %d)', [Seed, Index, Index mod TGraphicsGenerator.StyleCount]);
      Campaign.Run(Name, TRenderFuzzDocuments.Page(Content, LiberationSans), '', TFuzzWork.Render);
    end;
    Campaign.AssertNoFailures;
  finally
    Campaign.Free;
  end;
end;

class procedure TRenderRobustnessTestsBase.RunHostile(const Campaign: TFuzzCampaign; const Name: string; const Document: TBytes;
                                                      const TimeLimitSeconds: Integer);
begin
  Campaign.Run(Name, Document, '', TFuzzWork.Render, TimeLimitSeconds);
end;

class procedure TRenderRobustnessTestsBase.RunHostileContent(const Campaign: TFuzzCampaign; const Name, Content: string;
                                                             const TimeLimitSeconds: Integer);
begin
  RunHostile(Campaign, Name, TRenderFuzzDocuments.Page(Latin1(Content), TTestFonts.Bytes(LiberationSansFile)), TimeLimitSeconds);
end;

// A page that draws the image /Im with the entries and the data
class function TRenderRobustnessTestsBase.PageWithImage(const ImageEntries: string; const ImageData: TBytes; const Extra: string): TBytes;
begin
  const Builder = TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  try
    Builder.AddObject(3, Format(PageFormat, ['<< /XObject << /Im 5 0 R >> >>', '']));
    Builder.AddStreamObject(4, '', TEncoding.ASCII.GetBytes('q 150 0 0 150 20 20 cm /Im Do Q 0 0 1 rg 0 0 20 20 re f'));
    Builder.AddStreamObject(5, '/Type /XObject /Subtype /Image ' + ImageEntries, ImageData);
    if Extra <> '' then
    begin
      Builder.AddStreamObject(6, Extra, TBytes.Create($00, $FF, $80, $40, $20, $10, $08, $04, $02));
    end;
    Result := Builder.Build(TXrefStyle.Table);
  finally
    Builder.Free;
  end;
end;

// Review focus 1: damaged or hostile image data
class procedure TRenderRobustnessTestsBase.RunHostileImages(const Campaign: TFuzzCampaign);
begin
  const Jpeg = TDecoderInputs.Jpeg(JpegFile);
  var Garbage: TBytes;
  SetLength(Garbage, 3000);
  RandSeed := 31337;
  for var Index := 0 to High(Garbage) do
  begin
    Garbage[Index] := Random(256);
  end;

  RunHostile(Campaign, 'truncated JPEG', PageWithImage('/Width 100 /Height 100 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode',
                                                       Copy(Jpeg, 0, Length(Jpeg) div 3)));
  RunHostile(Campaign, 'JPEG cut in the header', PageWithImage('/Width 100 /Height 100 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode',
                                                               Copy(Jpeg, 0, 40)));
  RunHostile(Campaign, 'huge declared size with ten bytes', PageWithImage('/Width 100000 /Height 100000 /ColorSpace /DeviceRGB /BitsPerComponent 8',
                                                                          TBytes.Create(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)));
  RunHostile(Campaign, 'huge declared size of a stencil mask', PageWithImage('/Width 2000000000 /Height 2000000000 /ImageMask true /BitsPerComponent 1',
                                                                             TBytes.Create(1, 2, 3, 4)));
  RunHostile(Campaign, '16 bits with an odd number of bytes', PageWithImage('/Width 3 /Height 3 /ColorSpace /DeviceRGB /BitsPerComponent 16',
                                                                            TBytes.Create(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23)));
  RunHostile(Campaign, 'Indexed lookup that is too short', PageWithImage('/Width 3 /Height 3 /BitsPerComponent 8 /ColorSpace [/Indexed /DeviceRGB 255 <FF0000>]',
                                                                         TBytes.Create(0, 1, 2, 250, 251, 252, 253, 254, 255)));
  RunHostile(Campaign, 'Indexed with a negative hival', PageWithImage('/Width 3 /Height 3 /BitsPerComponent 8 /ColorSpace [/Indexed /DeviceRGB -5 <FF0000>]',
                                                                      TBytes.Create(0, 1, 2, 3, 4, 5, 6, 7, 8)));
  RunHostile(Campaign, 'soft mask with other dimensions', PageWithImage('/Width 4 /Height 4 /ColorSpace /DeviceGray /BitsPerComponent 8 /SMask 6 0 R',
                                                                        TBytes.Create(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15),
                                                                        '/Type /XObject /Subtype /Image /Width 3 /Height 3 /ColorSpace /DeviceGray /BitsPerComponent 8'));
  RunHostile(Campaign, 'soft mask of 100000 x 100000', PageWithImage('/Width 4 /Height 4 /ColorSpace /DeviceGray /BitsPerComponent 8 /SMask 6 0 R',
                                                                     TBytes.Create(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15),
                                                                     '/Type /XObject /Subtype /Image /Width 100000 /Height 100000 /ColorSpace /DeviceGray /BitsPerComponent 8'));
  RunHostile(Campaign, 'CCITT stream full of garbage', PageWithImage('/Width 1728 /Height 2000 /ColorSpace /DeviceGray /BitsPerComponent 1 ' +
                                                                     '/Filter /CCITTFaxDecode /DecodeParms << /K -1 /Columns 1728 /Rows 2000 >>', Garbage));
  RunHostile(Campaign, 'CCITT stream with a huge declared size', PageWithImage('/Width 100000 /Height 100000 /ColorSpace /DeviceGray /BitsPerComponent 1 ' +
                                                                               '/Filter /CCITTFaxDecode /DecodeParms << /K 0 /Columns 100000 /Rows 100000 >>', Garbage));
  RunHostile(Campaign, 'Flate stream full of garbage', PageWithImage('/Width 50 /Height 50 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode', Garbage));
  RunHostile(Campaign, 'image with zero size', PageWithImage('/Width 0 /Height 0 /ColorSpace /DeviceRGB /BitsPerComponent 8', TBytes.Create(1, 2, 3)));
  RunHostile(Campaign, 'image with 3 bits per component', PageWithImage('/Width 5 /Height 5 /ColorSpace /DeviceRGB /BitsPerComponent 3', Garbage));
  RunHostile(Campaign, 'image with a /Decode of NaN', PageWithImage('/Width 2 /Height 2 /ColorSpace /DeviceGray /BitsPerComponent 8 /Decode [1e39 -1e39]',
                                                                    TBytes.Create(1, 2, 3, 4)));
end;

// Review focus 2: recursion through paint
class procedure TRenderRobustnessTestsBase.RunHostilePaint(const Campaign: TFuzzCampaign);
const
  Group = '/Type /XObject /Subtype /Form /BBox [0 0 200 200] /Group << /S /Transparency /CS /DeviceGray >> ';
  Mark = '0 0 1 rg 0 0 20 20 re f';
begin
  // A tiling pattern that uses itself as colour
  RunHostileContent(Campaign, 'tiling pattern that paints with itself', '/Pattern cs /P4 scn 0 0 200 200 re f ' + Mark);
  RunHostileContent(Campaign, 'tiling pattern that paints with itself, stroked', '/Pattern CS /P4 SCN 10 w 0 0 200 200 re S ' + Mark);
  // A soft mask whose group sets the same graphics state
  RunHostileContent(Campaign, 'soft mask whose group sets the same graphics state', '/GS2 gs 0 1 0 rg 0 0 200 200 re f 1 0 0 rg 0 0 20 20 re f');
  RunHostileContent(Campaign, 'soft masks after each other', '/GS2 gs /GS3 gs /GS2 gs 0 1 0 rg 0 0 200 200 re f');
  // A Type 3 glyph that shows its own font
  RunHostileContent(Campaign, 'Type 3 glyph that shows its own font', 'BT /F3 20 Tf 20 100 Td (bbbbbb) Tj ET ' + Mark);
  // A form that draws itself
  RunHostileContent(Campaign, 'form that draws itself', '/Fm1 Do ' + Mark);
  // The appearance of an annotation that draws a form that refers to itself is part of every page of the generated documents; this one
  // is an appearance that draws itself
  RunHostile(Campaign, 'annotation whose appearance draws itself', TRenderFuzzDocuments.HostilePage(Mark, '<< >>',
    ['<< /Type /Annot /Subtype /Square /Rect [10 10 100 100] /F 4 /AP << /N 6 0 R >> >>',
     StreamPrefix + '/Type /XObject /Subtype /Form /BBox [0 0 100 100] /Resources << /XObject << /Self 6 0 R >> >>|0 0 1 rg 0 0 50 50 re f /Self Do']));
  // A soft mask whose group draws with a pattern whose cell sets the soft mask again
  RunHostile(Campaign, 'soft mask group with a pattern that sets the soft mask',
    TRenderFuzzDocuments.HostilePage('/GS gs 1 0 0 rg 0 0 200 200 re f ' + Mark, '<< /ExtGState << /GS 5 0 R >> >>',
      ['<< /Type /ExtGState /SMask << /Type /Mask /S /Alpha /G 6 0 R >> >>',
       StreamPrefix + Group + '/Resources << /Pattern << /Pat 7 0 R >> >>|/Pattern cs /Pat scn 0 0 200 200 re f',
       StreamPrefix + '/Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 /BBox [0 0 10 10] /XStep 10 /YStep 10 ' +
         '/Resources << /ExtGState << /GS 5 0 R >> >>|/GS gs 0 0 5 5 re f']));
  // Two groups that draw each other
  RunHostile(Campaign, 'transparency groups that draw each other', TRenderFuzzDocuments.HostilePage('/A Do ' + Mark, '<< /XObject << /A 5 0 R /B 6 0 R >> >>',
    [StreamPrefix + Group + '/Resources << /XObject << /B 6 0 R >> >>|0 1 0 rg 0 0 50 50 re f /B Do',
     StreamPrefix + Group + '/Resources << /XObject << /A 5 0 R >> >>|1 0 0 rg 0 0 50 50 re f /A Do']));
end;

// Review focus 4: degenerate geometry
class procedure TRenderRobustnessTestsBase.RunHostileGeometry(const Campaign: TFuzzCampaign);
const
  Square = '10 10 m 190 10 l 190 190 l 10 190 l h ';
begin
  RunHostileContent(Campaign, 'NaN and Infinity in a path', 'NaN NaN m Infinity -Infinity l 1.#INF 1.#IND l h f 0 0 1 rg 0 0 20 20 re f');
  RunHostileContent(Campaign, 'NaN and Infinity in a stroked path', '5 w NaN 10 m 100 Infinity l 1.#INF 50 l S 0 0 1 rg 0 0 20 20 re f');
  RunHostileContent(Campaign, 'coordinates of 1e30', '1e30 1e30 m -1e30 1e30 l -1e30 -1e30 l h f 1e30 w 0 0 m 1e30 1e30 l S 0 0 1 rg 0 0 20 20 re f');
  RunHostileContent(Campaign, 'coordinates beyond Single', '3.5e38 3.5e38 m -3.5e38 1e38 l 100 100 l 1e39 0 l B 0 0 1 rg 0 0 20 20 re f');
  RunHostileContent(Campaign, 'curves of 1e30', '0 0 m 1e30 0 -1e30 1e30 200 200 c 1e30 1e30 1e30 1e30 v 1e30 1e30 y S 0 0 1 rg 0 0 20 20 re f');
  RunHostileContent(Campaign, 'CTM of zeros', '0 0 0 0 0 0 cm ' + Square + 'f ' + Square + 'S /Im0 Do /Sh0 sh BT /F1 12 Tf (x) Tj ET');
  RunHostileContent(Campaign, 'CTM of 1e30', 'q 1e30 0 0 1e30 0 0 cm ' + Square + 'B /Im0 Do /Sh0 sh Q 0 0 1 rg 0 0 20 20 re f');
  RunHostileContent(Campaign, 'singular CTM with images and patterns', 'q 1 1 1 1 0 0 cm /Pattern cs /P1 scn ' + Square + 'f /Im1 Do /Sh1 sh Q 0 0 1 rg 0 0 20 20 re f');
  RunHostileContent(Campaign, 'line width 0', '0 w ' + Square + 'S 0 0 1 rg 0 0 20 20 re f');
  RunHostileContent(Campaign, 'dash array with zeros only', '[0 0] 0 d 5 w ' + Square + 'S [0] 3 d ' + Square + 'S 0 0 1 rg 0 0 20 20 re f');
  RunHostileContent(Campaign, 'dash array of tiny values', '[0.0000001 0.0000001] 0 d 5 w ' + Square + 'S 0 0 1 rg 0 0 20 20 re f');
  RunHostileContent(Campaign, 'dash array with a huge phase', '[3 2] 1e30 d 5 w ' + Square + 'S [1e30 1e30] 0 d ' + Square + 'S 0 0 1 rg 0 0 20 20 re f');
  RunHostileContent(Campaign, 'empty clip', '0 0 0 0 re W n ' + Square + 'f /Im0 Do /Sh0 sh BT /F1 12 Tf (x) Tj ET 0 0 1 rg 0 0 20 20 re f');
  RunHostileContent(Campaign, 'clip without a path', 'W n ' + Square + 'f 0 0 1 rg 0 0 20 20 re f');
  RunHostileContent(Campaign, 'clip of NaN', 'NaN NaN NaN NaN re W n ' + Square + 'f');
  RunHostileContent(Campaign, 'a thousand nested empty clips', RepeatText('0 0 0 0 re W n q ', 1000) + Square + 'f');
  RunHostileContent(Campaign, 'text matrix of zeros', 'BT /F1 12 Tf 0 0 0 0 0 0 Tm (x) Tj ET BT /F2 1e30 Tf 1e30 0 0 1e30 0 0 Tm <0024> Tj ET');
  RunHostileContent(Campaign, 'font size of NaN and 1e30', 'BT /F1 NaN Tf (x) Tj /F1 1e30 Tf (x) Tj /F2 -1e30 Tf <002400240024> Tj ET');
  RunHostileContent(Campaign, 'degenerate rectangle', '10 10 0 0 re f 10 10 0 0 re S 10 10 -5 0 re B 1e30 1e30 1e-30 1e-30 re f');
  RunHostileContent(Campaign, 'shading with a zero matrix', 'q 0 0 0 0 0 0 cm /Sh0 sh /Sh1 sh /Sh2 sh /Sh3 sh Q 0 0 1 rg 0 0 20 20 re f');
end;

procedure TRenderRobustnessTestsBase.TestHostileRenderDocuments;
begin
  const Campaign = TFuzzCampaign.Create;
  try
    RunHostileImages(Campaign);
    RunHostilePaint(Campaign);
    RunHostileGeometry(Campaign);
    RunExtraHostile(Campaign);
    Campaign.AssertNoFailures;
  finally
    Campaign.Free;
  end;
end;

end.
