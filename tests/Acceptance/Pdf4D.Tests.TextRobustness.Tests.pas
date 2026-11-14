// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.TextRobustness.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  DUnitX.TestFramework,
  Pdf4D.Tests.PdfBuilder,
  Pdf4D.Tests.Robustness.Tests;

type
  // The bytes of a content stream, written one piece at a time
  TContentWriter = class
  strict private
    FStream: TBytesStream;

  public
    constructor Create;
    destructor Destroy; override;

    // Text with ASCII characters only
    procedure Put(const Text: string);
    procedure PutByte(const Value: Byte);
    procedure PutBytes(const Value: TBytes);
    function ToBytes: TBytes;
  end;

  // Random content streams: the operators of the text extraction with operands of every type, structures that are too deep and
  // lists that are too long. The random number generator of the calling thread decides, so RandSeed decides the result.
  TContentGenerator = class
  public
    const StyleCount = 8;

  strict private
    FWriter: TContentWriter;

    class function Pick(const Values: array of string): string; static;
    class function RandomBytes(const MaxCount: Integer): TBytes; static;

    procedure PutNumber;
    procedure PutName(const Pool: array of string);
    procedure PutLiteralString(const Value: TBytes);
    procedure PutString;
    procedure PutArray;
    procedure PutDictionary;
    procedure PutAnyOperand;
    procedure PutOperand(const Kind: Char; const OperatorName: string);
    procedure PutOperator(const OperatorName, Operands: string);
    procedure PutRandomOperator;
    procedure PutTextOperators;
    procedure PutOperators(const Count: Integer);
    procedure PutDeepSave;
    procedure PutDeepMarkedContent;
    procedure PutShowArrays;
    procedure PutForms;
    procedure PutInlineImages;
    procedure PutTextState;
    procedure PutStyle(const Style: Integer);

  public
    constructor Create;
    destructor Destroy; override;

    // The content stream of that index (seed and index together are the whole input). Index mod StyleCount decides what kind of
    // stream it is, so every kind comes up in every run.
    class function Generate(const Seed, Index: Integer): TBytes; static;
  end;

  // Documents of one page for the fuzz runs
  TFuzzDocuments = class
  strict private
    const ChainFirstObject = 50;

    class function PageFonts: string; static;
    class function PageResources: string; static;
    class procedure AddForms(const Builder: TTestPdfBuilder; const ChainLength: Integer); static;
    class procedure AddFontObjects(const Builder: TTestPdfBuilder; const FontFile: TBytes); static;

  public
    // A page with Content, with Helvetica (/F1), LiberationSans as Type 0 font with Identity-H (/F2), a Type 3 font (/F3), the
    // forms /Fm1 (draws itself), /Fm2 and /Fm3 (draw each other twice), /Fm4 (shows text) and /Chain0 (a chain of forms that draw
    // the next one twice, ChainLength of them), the graphics state /GS1 and the properties /MC0
    class function ContentPage(const Content, LiberationSans: TBytes; const ChainLength: Integer): TBytes; static;
  end;

  // The font programs and the embedding that the font fuzz uses
  TEmbeddedProgram = (TrueType, Type1, Cff, ToUnicode);

  TFontDocuments = class
  strict private
    class function ShowTextCodes(const IsComposite: Boolean): string; static;
    class function SimpleFont(const Embedding: TEmbeddedProgram): string; static;
    class function CompositeFont(const Embedding: TEmbeddedProgram): string; static;

  public
    // The CFF table of an OpenType font
    class function CffTable(const OpenType: TBytes): TBytes; static;
    // A page with text in /F1, a font that uses the program (a simple font when IsComposite is False, a Type 0 font otherwise).
    // Segment1 and Segment2 are the parts of a Type 1 program, and Data is the whole program for the other kinds.
    class function Embed(const Embedding: TEmbeddedProgram; const IsComposite: Boolean; const Data: TBytes; const Segment1Size: Integer): TBytes; static;
  end;

  [TestFixture]
  TTextRobustnessTests = class
  strict private
    const ToUnicodeSource = '/CIDInit /ProcSet findresource begin 12 dict begin begincmap ' +
      '/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def /CMapName /Adobe-Identity-UCS def /CMapType 2 def ' +
      '1 begincodespacerange <00> <FF> endcodespacerange 3 beginbfchar <41> <0058> <42> <00590059> <43> <D83DDE00> endbfchar ' +
      '2 beginbfrange <61> <7A> <0041> <30> <32> [<0061> <0062> <0063>] endbfrange ' +
      '1 begincidrange <00> <FF> 0 endcidrange endcmap CMapName currentdict /CMap defineresource pop end end';

    class function FontMutation(const Source: TBytes; const Index: Integer): TBytes; static;
    class function MutatedName(const What: string; const Seed, Index: Integer; const Kind: TMutationKind): string; static;
    class procedure RunMutatedProgram(const Embedding: TEmbeddedProgram; const Source, DirectSource: TBytes; const Segment1Size: Integer;
                                      const Seed: Integer; const DirectWork: TFuzzWork; const Campaign: TFuzzCampaign); static;
    class function Latin1(const Text: string): TBytes; static;
    class function RepeatText(const Text: string; const Count: Integer): string; static;
    class procedure RunHostile(const Campaign: TFuzzCampaign; const Name: string; const Content: string); static;
    class procedure RunHostileFont(const Campaign: TFuzzCampaign; const Name: string; const Embedding: TEmbeddedProgram;
                                   const Data: TBytes; const Segment1Size: Integer); static;
    class function TrueTypeWithTableOffsetBeyondTheEnd: TBytes; static;
    class function CffWithAbsurdIndexCount: TBytes; static;

  public
    [Test]
    procedure TestMutatedCorpusTextNeverCrashes;
    [Test]
    procedure TestGeneratedContentStreamsNeverCrash;
    [Test]
    procedure TestMutatedFontProgramsNeverCrash;
    [Test]
    procedure TestHostileSyntheticDocuments;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  Pdf4D.FontBox.Pfb,
  Pdf4D.Tests.TextDocuments,
  Pdf4D.Tests.TestFonts;

type
  TOperatorShape = record
    Name: string;
    // One letter per operand: n number, N name, s string, a array, d dictionary
    Operands: string;
  end;

const
  ContentSeed = 4321;
  FuzzChainLength = 10;
  HostileChainLength = 25;
  ContentStreamCount = 2000;
  ProgramSeed = 5678;
  MutationsPerProgram = 300;
  LiberationSansFile = 'LiberationSans-Regular.ttf';
  OpenSansFile = 'OpenSans-Regular.pfb';
  SourceSansFile = 'SourceSansProBold.otf';
  MaxDeepStructure = 9000;
  MaxArrayElements = 20000;
  HeadWindow = 4096;
  UnknownProgramMessage = 'Unknown program';
  NameOperandFormat = '/%s ';
  OperatorFormat = '%s ';
  FontSizeFormat = '/%s %s Tf [ ';
  InlineImageFormat = 'BI %s ';
  FormDrawFormat = '/%s Do ';
  ShowCodesFormat = 'BT /F1 12 Tf 72 700 Td %s> Tj ET';
  EmbeddedFormat = '%s embedded';
  EmbeddedType0Format = '%s embedded in a Type 0 font';
  FontClassesFormat = '%s font classes';
  ParserFormat = '%s parser';
  SurroundedFormat = '%s%s%s';

  Shapes: array[0..79] of TOperatorShape = (
    (Name: 'q'; Operands: ''), (Name: 'Q'; Operands: ''), (Name: 'BT'; Operands: ''), (Name: 'ET'; Operands: ''),
    (Name: 'Td'; Operands: 'nn'), (Name: 'TD'; Operands: 'nn'), (Name: 'Tm'; Operands: 'nnnnnn'), (Name: 'T*'; Operands: ''),
    (Name: 'Tc'; Operands: 'n'), (Name: 'Tw'; Operands: 'n'), (Name: 'Tz'; Operands: 'n'), (Name: 'TL'; Operands: 'n'),
    (Name: 'Tf'; Operands: 'Nn'), (Name: 'Tr'; Operands: 'n'), (Name: 'Ts'; Operands: 'n'), (Name: 'Tj'; Operands: 's'),
    (Name: 'TJ'; Operands: 'a'), (Name: ''''; Operands: 's'), (Name: '"'; Operands: 'nns'), (Name: 'cm'; Operands: 'nnnnnn'),
    (Name: 'gs'; Operands: 'N'), (Name: 'Do'; Operands: 'N'), (Name: 'BMC'; Operands: 'N'), (Name: 'BDC'; Operands: 'Nd'),
    (Name: 'EMC'; Operands: ''), (Name: 'MP'; Operands: 'N'), (Name: 'DP'; Operands: 'Nd'), (Name: 'd0'; Operands: 'nn'),
    (Name: 'd1'; Operands: 'nnnnnn'), (Name: 'BX'; Operands: ''), (Name: 'EX'; Operands: ''), (Name: 'w'; Operands: 'n'),
    (Name: 'J'; Operands: 'n'), (Name: 'j'; Operands: 'n'), (Name: 'M'; Operands: 'n'), (Name: 'i'; Operands: 'n'),
    (Name: 'd'; Operands: 'an'), (Name: 'ri'; Operands: 'N'), (Name: 're'; Operands: 'nnnn'), (Name: 'm'; Operands: 'nn'),
    (Name: 'l'; Operands: 'nn'), (Name: 'c'; Operands: 'nnnnnn'), (Name: 'v'; Operands: 'nnnn'), (Name: 'y'; Operands: 'nnnn'),
    (Name: 'h'; Operands: ''), (Name: 'S'; Operands: ''), (Name: 's'; Operands: ''), (Name: 'f'; Operands: ''),
    (Name: 'F'; Operands: ''), (Name: 'f*'; Operands: ''), (Name: 'B'; Operands: ''), (Name: 'B*'; Operands: ''),
    (Name: 'b'; Operands: ''), (Name: 'b*'; Operands: ''), (Name: 'n'; Operands: ''), (Name: 'W'; Operands: ''),
    (Name: 'W*'; Operands: ''), (Name: 'sh'; Operands: 'N'), (Name: 'g'; Operands: 'n'), (Name: 'G'; Operands: 'n'),
    (Name: 'rg'; Operands: 'nnn'), (Name: 'RG'; Operands: 'nnn'), (Name: 'k'; Operands: 'nnnn'), (Name: 'K'; Operands: 'nnnn'),
    (Name: 'cs'; Operands: 'N'), (Name: 'CS'; Operands: 'N'), (Name: 'sc'; Operands: 'nnn'), (Name: 'SC'; Operands: 'nnn'),
    (Name: 'scn'; Operands: 'nnnN'), (Name: 'SCN'; Operands: 'nnnN'), (Name: 'BI'; Operands: ''), (Name: 'ID'; Operands: ''),
    (Name: 'EI'; Operands: ''), (Name: 'Tj'; Operands: 's'), (Name: 'TJ'; Operands: 'a'), (Name: 'Tf'; Operands: 'Nn'),
    (Name: 'Tm'; Operands: 'nnnnnn'), (Name: 'Do'; Operands: 'N'), (Name: 'q'; Operands: ''), (Name: 'Q'; Operands: '')
  );

  // The operators that change the text state or show text, which a text stream is mostly made of
  TextShapeCount = 19;

  Numbers: array[0..39] of string = (
    '0', '-0', '+0', '.0', '-.0', '0.', '0.0000000000001', '1', '-1', '12', '0.5', '-3.75', '255', '65535', '65536', '2147483647',
    '2147483648', '-2147483648', '-2147483649', '4294967296', '9223372036854775807', '9223372036854775808', '-9223372036854775808',
    '340282346638528859811704183484516925440', '340282366920938463463374607431768211456', '99999999999999999999999999999999999999999999999999',
    '-99999999999999999999999999999999999999999999999999', '0.00000000000000000000000000000000000000000000001', '1e10', '1e308',
    '1.2.3', '--5', '+-5', '1-2', '.', '-', 'NaN', '-Infinity', '1.#INF', '-1.#IND');

  FontNames: array[0..5] of string = ('F1', 'F2', 'F3', 'F9', 'Helv', '');
  FormNames: array[0..6] of string = ('Fm1', 'Fm2', 'Fm3', 'Fm4', 'Chain0', 'Missing', 'Im0');
  OtherNames: array[0..9] of string = ('GS1', 'GS9', 'MC0', 'MC9', 'OC', 'P', 'Span', 'Artifact', 'Pattern', 'DeviceRGB');

  InlineImageDictionaries: array[0..5] of string = (
    '/W 1 /H 1 /BPC 8 /CS /G', '/W 100000 /H 100000 /BPC 8 /CS /RGB', '/W -1 /H -1', '/W 2 /H 2 /BPC 1 /IM true /F /AHx',
    '/W 1 /H 1 /BPC 8 /CS /G /F [/Fl /A85] /DP [<< /Predictor 15 >> null]', '/Garbage << [ ] >> /W');

{ TContentWriter }

constructor TContentWriter.Create;
begin
  inherited Create;
  FStream := TBytesStream.Create;
end;

destructor TContentWriter.Destroy;
begin
  FStream.Free;
  inherited;
end;

procedure TContentWriter.Put(const Text: string);
begin
  for var Character in Text do
  begin
    PutByte(Byte(Ord(Character) and $7F));
  end;
end;

procedure TContentWriter.PutByte(const Value: Byte);
begin
  FStream.WriteBuffer(Value, 1);
end;

procedure TContentWriter.PutBytes(const Value: TBytes);
begin
  if Length(Value) > 0 then
  begin
    FStream.WriteBuffer(Value[0], Length(Value));
  end;
end;

function TContentWriter.ToBytes: TBytes;
begin
  Result := Copy(FStream.Bytes, 0, FStream.Size);
end;

{ TContentGenerator }

constructor TContentGenerator.Create;
begin
  inherited Create;
  FWriter := TContentWriter.Create;
end;

destructor TContentGenerator.Destroy;
begin
  FWriter.Free;
  inherited;
end;

class function TContentGenerator.Pick(const Values: array of string): string;
begin
  Result := Values[Random(Length(Values))];
end;

// Random bytes, or printable characters, or the two-byte codes of a font with Identity-H for printable characters
class function TContentGenerator.RandomBytes(const MaxCount: Integer): TBytes;
begin
  SetLength(Result, Random(MaxCount + 1));
  const Mode = Random(3);
  for var Index := 0 to High(Result) do
  begin
    case Mode of
      0: Result[Index] := Random(256);
      1: Result[Index] := 32 + Random(95);
    else
      Result[Index] := IfThen(Odd(Index), 32 + Random(95), 0);
    end;
  end;
end;

procedure TContentGenerator.PutNumber;
begin
  case Random(10) of
    0..4: FWriter.Put(IntToStr(Random(2000) - 200));
    5..6: FWriter.Put(Format('%d.%d', [Random(1000) - 100, Random(1000)], TFormatSettings.Invariant));
    else FWriter.Put(Pick(Numbers));
  end;
  FWriter.Put(' ');
end;

procedure TContentGenerator.PutName(const Pool: array of string);
begin
  FWriter.Put(Format(NameOperandFormat, [Pick(Pool)]));
end;

// A literal string; one in twenty is not escaped, so that the parentheses and backslashes in it are what is being tried
procedure TContentGenerator.PutLiteralString(const Value: TBytes);
begin
  const IsEscaped = (Random(20) <> 0);
  FWriter.Put('(');
  for var Item in Value do
  begin
    if IsEscaped and (Item in [Ord('('), Ord(')'), Ord(Chr(92))]) then
    begin
      FWriter.PutByte(92);
    end;
    FWriter.PutByte(Item);
  end;
  FWriter.Put(') ');
end;

procedure TContentGenerator.PutString;
begin
  const Value = RandomBytes(Pick(['4', '20', '300']).ToInteger);
  if Random(4) = 0 then
  begin
    FWriter.Put('<');
    for var Item in Value do
    begin
      FWriter.Put(IntToHex(Item, 2));
    end;
    FWriter.Put('> ');
  end
  else
  begin
    PutLiteralString(Value);
  end;
end;

procedure TContentGenerator.PutArray;
begin
  FWriter.Put('[ ');
  for var Index := 1 to Random(8) do
  begin
    if Random(2) = 0 then
    begin
      PutNumber;
    end
    else
    begin
      PutString;
    end;
  end;
  FWriter.Put('] ');
end;

procedure TContentGenerator.PutDictionary;
begin
  FWriter.Put('<< ');
  for var Index := 1 to Random(4) do
  begin
    PutName(['MCID', 'ActualText', 'E', 'Lang', 'Alt', 'Type', 'O']);
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

procedure TContentGenerator.PutAnyOperand;
begin
  case Random(9) of
    0: PutNumber;
    1: PutName(FontNames);
    2: PutString;
    3: PutArray;
    4: PutDictionary;
    5: FWriter.Put(Pick(['true ', 'false ', 'null ']));
    6: FWriter.Put('[ ] ');
    7: FWriter.Put('<< >> ');
  else
    FWriter.Put('[ [ [ << /A [ ] >> ] ] ] ');
  end;
end;

procedure TContentGenerator.PutOperand(const Kind: Char; const OperatorName: string);
begin
  case Kind of
    'n': PutNumber;
    's': PutString;
    'a': PutArray;
    'd': PutDictionary;
  else
    if OperatorName = 'Tf' then
    begin
      PutName(FontNames);
    end
    else if OperatorName = 'Do' then
    begin
      PutName(FormNames);
    end
    else
    begin
      PutName(OtherNames);
    end;
  end;
end;

procedure TContentGenerator.PutOperator(const OperatorName, Operands: string);
begin
  if Random(4) = 0 then
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

procedure TContentGenerator.PutRandomOperator;
begin
  // Half of the operators change the text state or show text, so that the page keeps having text to extract
  var Shape := Shapes[Random(Length(Shapes))];
  if Random(2) = 0 then
  begin
    Shape := Shapes[Random(TextShapeCount)];
  end;

  // The inline image operators need their own structure, otherwise the rest of the stream is swallowed as image data
  const IsInlineImageOperator = (Shape.Name = 'BI') or (Shape.Name = 'ID') or (Shape.Name = 'EI');
  if IsInlineImageOperator then
  begin
    PutOperator(Shapes[Random(TextShapeCount)].Name, '');
  end
  else
  begin
    PutOperator(Shape.Name, Shape.Operands);
  end;
end;

procedure TContentGenerator.PutTextOperators;
begin
  const Shape = Shapes[Random(TextShapeCount)];
  PutOperator(Shape.Name, Shape.Operands);
end;

procedure TContentGenerator.PutOperators(const Count: Integer);
begin
  FWriter.Put('BT /F1 12 Tf ');
  for var Index := 1 to Count do
  begin
    PutRandomOperator;
    if Random(20) = 0 then
    begin
      FWriter.Put(sLineBreak);
    end;
  end;
end;

procedure TContentGenerator.PutDeepSave;
begin
  for var Index := 1 to 3000 + Random(MaxDeepStructure) do
  begin
    FWriter.Put(Pick(['q ', 'q 1 0 0 1 1 1 cm ', 'q BT ']));
  end;
  PutOperators(20 + Random(30));
  for var Index := 1 to Random(MaxDeepStructure) do
  begin
    FWriter.Put('Q ');
  end;
end;

procedure TContentGenerator.PutDeepMarkedContent;
begin
  for var Index := 1 to 1000 + Random(MaxDeepStructure) do
  begin
    case Random(3) of
      0: FWriter.Put('/Span BMC ');
      1: FWriter.Put('/Span << /MCID 1 /ActualText (a) >> BDC ');
    else
      FWriter.Put('/P /MC0 BDC ');
    end;
  end;
  FWriter.Put('BT /F1 12 Tf (text) Tj ET ');
  for var Index := 1 to Random(MaxDeepStructure) do
  begin
    FWriter.Put('EMC ');
  end;
end;

procedure TContentGenerator.PutShowArrays;
begin
  FWriter.Put('BT ');
  for var Round := 1 to 1 + Random(5) do
  begin
    FWriter.Put(Format(FontSizeFormat, [Pick(['F1', 'F1', 'F2', 'F3']), Pick(['12', '12', '0', '-5', '1000', '0.0001'])]));
    for var Index := 1 to 100 + Random(MaxArrayElements) do
    begin
      if Random(3) = 0 then
      begin
        PutNumber;
      end
      else
      begin
        PutLiteralString(RandomBytes(4));
      end;
    end;
    FWriter.Put('] TJ ');
  end;
  FWriter.Put('ET ');
end;

procedure TContentGenerator.PutForms;
begin
  FWriter.Put('BT /F1 12 Tf (before) Tj ET ');
  for var Index := 1 to 5 + Random(40) do
  begin
    if Random(3) = 0 then
    begin
      PutRandomOperator;
    end
    else
    begin
      FWriter.Put(Format(FormDrawFormat, [Pick(FormNames)]));
    end;
  end;
  FWriter.Put('BT /F1 12 Tf (after) Tj ET ');
end;

procedure TContentGenerator.PutInlineImages;
begin
  FWriter.Put('BT /F1 12 Tf (text) Tj ET ');
  for var Index := 1 to 1 + Random(4) do
  begin
    FWriter.Put(Format(InlineImageFormat, [Pick(InlineImageDictionaries)]));
    case Random(4) of
      0: ;
      1: FWriter.Put('ID ');
    else
      FWriter.Put('ID ');
      FWriter.PutBytes(RandomBytes(2000));
      // Without EI on one of four: the stream ends in the image
      if Random(4) <> 0 then
      begin
        FWriter.Put(' EI ');
      end;
    end;
    FWriter.Put('BT /F1 12 Tf (more) Tj ET ');
  end;
end;

procedure TContentGenerator.PutTextState;
begin
  FWriter.Put('BT ');
  for var Index := 1 to 100 + Random(200) do
  begin
    if Random(3) = 0 then
    begin
      FWriter.Put(Format(NameOperandFormat, [Pick(['F1', 'F2', 'F3'])]));
      PutNumber;
      FWriter.Put('Tf ');
      PutString;
      FWriter.Put(Pick(['Tj ', 'TJ ', '" ', ''' ']));
    end
    else
    begin
      PutTextOperators;
    end;
  end;
end;

procedure TContentGenerator.PutStyle(const Style: Integer);
begin
  case Style of
    0: PutOperators(60 + Random(200));
    1: PutDeepSave;
    2: PutDeepMarkedContent;
    3: PutShowArrays;
    4: PutForms;
    5: PutInlineImages;
    6: PutTextState;
  else
    // Pieces of the other styles one after the other
    for var Piece := 1 to 3 do
    begin
      PutStyle(Random(StyleCount - 1));
    end;
  end;
end;

class function TContentGenerator.Generate(const Seed, Index: Integer): TBytes;
begin
  RandSeed := Seed + Index;
  const Generator = TContentGenerator.Create;
  try
    Generator.PutStyle(Index mod StyleCount);
    Result := Generator.FWriter.ToBytes;
  finally
    Generator.Free;
  end;
end;

{ TFuzzDocuments }

class function TFuzzDocuments.PageFonts: string;
begin
  // F1 is object 10, F2 is 11, F3 is 12; the descendant of F2 is object 13
  const Helvetica = TTextTestDocuments.HelveticaF1;
  const Type0 = '<< /Type /Font /Subtype /Type0 /BaseFont /LiberationSans /Encoding /Identity-H /DescendantFonts [ 13 0 R ] >>';
  const Type3 = '<< /Type /Font /Subtype /Type3 /FontBBox [0 0 100 100] /FontMatrix [0.01 0 0 0.01 0 0] ' +
                '/CharProcs << /a 30 0 R /b 31 0 R >> /Encoding << /Type /Encoding /Differences [97 /a /b] >> ' +
                '/FirstChar 97 /LastChar 98 /Widths [50 60] >>';
  Result := string.Join(TTextTestDocuments.Separator, [Helvetica, Type0, Type3]);
end;

class function TFuzzDocuments.PageResources: string;
begin
  Result := '<< /Font << /F1 10 0 R /F2 11 0 R /F3 12 0 R >> ' +
            '/XObject << /Fm1 40 0 R /Fm2 41 0 R /Fm3 42 0 R /Fm4 43 0 R /Chain0 50 0 R >> ' +
            '/ExtGState << /GS1 44 0 R >> /Properties << /MC0 45 0 R >> >>';
end;

class procedure TFuzzDocuments.AddForms(const Builder: TTestPdfBuilder; const ChainLength: Integer);
const
  FormStart = '/Type /XObject /Subtype /Form /BBox [0 0 100 100] /Resources ';
  Fonts = '/Font << /F1 10 0 R >> ';
  FormResourcesFormat = '%s<< %s%s>>';
begin
  Builder.AddStreamObject(40, Format(FormResourcesFormat, [FormStart, Fonts, '/XObject << /Fm1 40 0 R >> ']), TEncoding.ASCII.GetBytes('BT /F1 12 Tf (self) Tj ET /Fm1 Do'));
  Builder.AddStreamObject(41, Format(FormResourcesFormat, [FormStart, Fonts, '/XObject << /Fm3 42 0 R >> ']), TEncoding.ASCII.GetBytes('BT /F1 12 Tf (two) Tj ET /Fm3 Do /Fm3 Do'));
  Builder.AddStreamObject(42, Format(FormResourcesFormat, [FormStart, Fonts, '/XObject << /Fm2 41 0 R >> ']), TEncoding.ASCII.GetBytes('BT /F1 12 Tf (three) Tj ET /Fm2 Do /Fm2 Do'));
  Builder.AddStreamObject(43, Format(FormResourcesFormat, [FormStart, Fonts, '']), TEncoding.ASCII.GetBytes('BT /F1 12 Tf (four) Tj ET'));
  Builder.AddObject(44, '<< /Type /ExtGState /Font [ 10 0 R 12 ] /LW 2 >>');
  Builder.AddObject(45, '<< /Type /OCG /Name (layer) >>');

  for var Index := 0 to ChainLength - 1 do
  begin
    const Number = ChainFirstObject + Index;
    const NextName = Format('Chain%d', [Index + 1]);
    var Content := 'BT /F1 12 Tf (x) Tj ET';
    var Resources := Format('<< %s>>', [Fonts]);
    if Index < ChainLength - 1 then
    begin
      Content := Content + Format(' /%s Do /%s Do', [NextName, NextName]);
      Resources := Format('<< %s/XObject << /%s %d 0 R >> >>', [Fonts, NextName, Number + 1]);
    end;
    Builder.AddStreamObject(Number, FormStart + Resources, TEncoding.ASCII.GetBytes(Content));
  end;
end;

class procedure TFuzzDocuments.AddFontObjects(const Builder: TTestPdfBuilder; const FontFile: TBytes);
begin
  Builder.AddObject(13, '<< /Type /Font /Subtype /CIDFontType2 /BaseFont /LiberationSans /FontDescriptor 20 0 R ' +
                        '/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /CIDToGIDMap /Identity /DW 600 >>');
  Builder.AddObject(20, '<< /Type /FontDescriptor /FontName /LiberationSans /Flags 4 /FontBBox [0 0 1000 1000] /FontFile2 21 0 R >>');
  TTextTestDocuments.AddFontFile(Builder, 21, Format('/Length1 %d', [Length(FontFile)]), FontFile);
  Builder.AddStreamObject(30, '', TEncoding.ASCII.GetBytes('50 0 d0 0 0 100 100 re f'));
  Builder.AddStreamObject(31, '', TEncoding.ASCII.GetBytes('60 0 0 0 100 100 d1 0 0 50 50 re f'));
end;

class function TFuzzDocuments.ContentPage(const Content, LiberationSans: TBytes; const ChainLength: Integer): TBytes;
begin
  const Builder = TTextTestDocuments.NewBuilder(PageFonts, '');
  try
    Builder.AddObject(3, Format('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents %d 0 R /Resources %s >>',
                                [TTextTestDocuments.ContentObject, PageResources]));
    Builder.AddStreamObject(TTextTestDocuments.ContentObject, '', Content);
    AddFontObjects(Builder, LiberationSans);
    AddForms(Builder, ChainLength);
    Result := Builder.Build(TXrefStyle.Table);
  finally
    Builder.Free;
  end;
end;

{ TFontDocuments }

class function TFontDocuments.CffTable(const OpenType: TBytes): TBytes;
begin
  const TableCount = (OpenType[4] shl 8) or OpenType[5];
  for var Index := 0 to TableCount - 1 do
  begin
    const Entry = 12 + (16 * Index);
    const Tag = TEncoding.ASCII.GetString(OpenType, Entry, 4);
    if Tag = 'CFF ' then
    begin
      const Offset = (OpenType[Entry + 8] shl 24) or (OpenType[Entry + 9] shl 16) or (OpenType[Entry + 10] shl 8) or OpenType[Entry + 11];
      const Size = (OpenType[Entry + 12] shl 24) or (OpenType[Entry + 13] shl 16) or (OpenType[Entry + 14] shl 8) or OpenType[Entry + 15];
      Exit(Copy(OpenType, Offset, Size));
    end;
  end;
  raise EArgumentException.Create('The font has no CFF table');
end;

class function TFontDocuments.ShowTextCodes(const IsComposite: Boolean): string;
begin
  const Codes = TStringBuilder.Create;
  try
    if IsComposite then
    begin
      Codes.Append('<0024004800480049> Tj <');
      for var Code := 0 to 299 do
      begin
        Codes.Append(IntToHex(Code, 4));
      end;
    end
    else
    begin
      Codes.Append('(Hello, World! \(A\)) Tj <');
      for var Code := 0 to 255 do
      begin
        Codes.Append(IntToHex(Code, 2));
      end;
    end;
    Result := Format(ShowCodesFormat, [Codes.ToString]);
  finally
    Codes.Free;
  end;
end;

class function TFontDocuments.SimpleFont(const Embedding: TEmbeddedProgram): string;
begin
  case Embedding of
    TEmbeddedProgram.TrueType:
      Result := '<< /Type /Font /Subtype /TrueType /BaseFont /LiberationSans /Encoding /WinAnsiEncoding /FontDescriptor 20 0 R >>';
    TEmbeddedProgram.Type1:
      Result := '<< /Type /Font /Subtype /Type1 /BaseFont /OpenSans-Regular /FontDescriptor 20 0 R >>';
    TEmbeddedProgram.Cff:
      Result := '<< /Type /Font /Subtype /Type1 /BaseFont /SourceSansPro-Bold /FontDescriptor 20 0 R >>';
    TEmbeddedProgram.ToUnicode:
      Result := '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /ToUnicode 22 0 R >>';
  else
    raise EArgumentOutOfRangeException.Create(UnknownProgramMessage);
  end;
end;

class function TFontDocuments.CompositeFont(const Embedding: TEmbeddedProgram): string;
begin
  const ToUnicodeEntry = IfThen(Embedding = TEmbeddedProgram.ToUnicode, '/ToUnicode 22 0 R', '');
  Result := Format('<< /Type /Font /Subtype /Type0 /BaseFont /FuzzFont /Encoding /Identity-H %s /DescendantFonts [ 13 0 R ] >>', [ToUnicodeEntry]);
end;

class function TFontDocuments.Embed(const Embedding: TEmbeddedProgram; const IsComposite: Boolean; const Data: TBytes; const Segment1Size: Integer): TBytes;
begin
  var FontBody := SimpleFont(Embedding);
  if IsComposite then
  begin
    FontBody := CompositeFont(Embedding);
  end;

  const Builder = TTextTestDocuments.NewBuilder(FontBody, ShowTextCodes(IsComposite));
  try
    const Subtype = IfThen(Embedding = TEmbeddedProgram.Cff, 'CIDFontType0', 'CIDFontType2');
    Builder.AddObject(13, Format('<< /Type /Font /Subtype /%s /BaseFont /FuzzFont /FontDescriptor 20 0 R ' +
                                 '/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /DW 500 >>', [Subtype]));
    case Embedding of
      TEmbeddedProgram.TrueType:
      begin
        Builder.AddObject(20, '<< /Type /FontDescriptor /FontName /LiberationSans /Flags 32 /FontBBox [0 0 1000 1000] /FontFile2 21 0 R >>');
        TTextTestDocuments.AddFontFile(Builder, 21, Format('/Length1 %d', [Length(Data)]), Data);
      end;
      TEmbeddedProgram.Type1:
      begin
        Builder.AddObject(20, '<< /Type /FontDescriptor /FontName /OpenSans-Regular /Flags 32 /FontBBox [0 0 1000 1000] /FontFile 21 0 R >>');
        TTextTestDocuments.AddFontFile(Builder, 21, Format('/Length1 %d /Length2 %d', [Segment1Size, Length(Data) - Segment1Size]), Data);
      end;
      TEmbeddedProgram.Cff:
      begin
        Builder.AddObject(20, '<< /Type /FontDescriptor /FontName /SourceSansPro-Bold /Flags 32 /FontBBox [0 0 1000 1000] /FontFile3 21 0 R >>');
        TTextTestDocuments.AddFontFile(Builder, 21, IfThen(IsComposite, '/Subtype /CIDFontType0C', '/Subtype /Type1C'), Data);
      end;
      TEmbeddedProgram.ToUnicode:
      begin
        Builder.AddObject(20, '<< /Type /FontDescriptor /FontName /FuzzFont /Flags 4 /FontBBox [0 0 1000 1000] >>');
        Builder.AddStreamObject(22, '', Data);
      end;
    else
      raise EArgumentOutOfRangeException.Create(UnknownProgramMessage);
    end;
    Result := Builder.Build(TXrefStyle.Table);
  finally
    Builder.Free;
  end;
end;

{ TTextRobustnessTests }

class function TTextRobustnessTests.Latin1(const Text: string): TBytes;
begin
  SetLength(Result, Length(Text));
  for var Index := 0 to High(Result) do
  begin
    Result[Index] := Byte(Ord(Text[Index + 1]) and $FF);
  end;
end;

class function TTextRobustnessTests.RepeatText(const Text: string; const Count: Integer): string;
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

// Half of the mutations only touch the first bytes, where the headers and tables are
class function TTextRobustnessTests.FontMutation(const Source: TBytes; const Index: Integer): TBytes;
begin
  const Kind = TMutationKind(Index mod (Ord(High(TMutationKind)) + 1));
  const HeadOnly = ((Index div 4) mod 2 = 0) and (Kind <> TMutationKind.Truncate) and (Length(Source) > HeadWindow);
  if not HeadOnly then
  begin
    Exit(TMutator.Mutate(Source, Kind));
  end;
  Result := TMutator.Mutate(Copy(Source, 0, HeadWindow), Kind) + Copy(Source, HeadWindow, Length(Source) - HeadWindow);
end;

class function TTextRobustnessTests.MutatedName(const What: string; const Seed, Index: Integer; const Kind: TMutationKind): string;
const
  KindNames: array[TMutationKind] of string = ('overwrite', 'truncate', 'duplicate', 'object-header');
begin
  Result := Format('%s seed %d mutation %d (%s)', [What, Seed, Index, KindNames[Kind]]);
end;

// Source is the program as it is embedded, DirectSource is what the parser of the program takes (the same, except for Type 1, where it
// is the PFB file); both are mutated in the same way
class procedure TTextRobustnessTests.RunMutatedProgram(const Embedding: TEmbeddedProgram; const Source, DirectSource: TBytes; const Segment1Size: Integer;
                                                       const Seed: Integer; const DirectWork: TFuzzWork; const Campaign: TFuzzCampaign);
const
  ProgramNames: array[TEmbeddedProgram] of string = ('TrueType', 'Type 1', 'CFF', 'ToUnicode');
begin
  const FullSeed = Seed + TFuzzSettings.SeedOffset;
  RandSeed := FullSeed;
  for var Index := 0 to TFuzzSettings.Scale(MutationsPerProgram) - 1 do
  begin
    const Kind = TMutationKind(Index mod (Ord(High(TMutationKind)) + 1));
    const Mutated = FontMutation(Source, Index);
    const IsComposite = Odd(Index);
    const Name = MutatedName(ProgramNames[Embedding], FullSeed, Index, Kind);

    Campaign.Run(Format(EmbeddedFormat, [Name]), TFontDocuments.Embed(Embedding, IsComposite, Mutated, Segment1Size), '', TFuzzWork.PageText);
    Campaign.Run(Format(FontClassesFormat, [Name]), TFontDocuments.Embed(Embedding, IsComposite, Mutated, Segment1Size), '', TFuzzWork.FontClasses);
    Campaign.Run(Format(ParserFormat, [Name]), FontMutation(DirectSource, Index), '', DirectWork);
  end;
end;

procedure TTextRobustnessTests.TestMutatedCorpusTextNeverCrashes;
begin
  TFuzzCampaign.RunMutatedCorpus(TFuzzWork.Text);
end;

procedure TTextRobustnessTests.TestGeneratedContentStreamsNeverCrash;
begin
  const LiberationSans = TTestFonts.Bytes(LiberationSansFile);
  const Seed = ContentSeed + TFuzzSettings.SeedOffset;
  const Campaign = TFuzzCampaign.Create;
  try
    for var Index := 0 to TFuzzSettings.Scale(ContentStreamCount) - 1 do
    begin
      const Content = TContentGenerator.Generate(Seed, Index);
      const Name = Format('content stream seed %d index %d (style %d)', [Seed, Index, Index mod TContentGenerator.StyleCount]);
      Campaign.Run(Name, TFuzzDocuments.ContentPage(Content, LiberationSans, FuzzChainLength), '', TFuzzWork.PageText);
    end;
    Campaign.AssertNoFailures;
  finally
    Campaign.Free;
  end;
end;

procedure TTextRobustnessTests.TestMutatedFontProgramsNeverCrash;
begin
  const Campaign = TFuzzCampaign.Create;
  try
    const TrueType = TTestFonts.Bytes(LiberationSansFile);
    RunMutatedProgram(TEmbeddedProgram.TrueType, TrueType, TrueType, 0, ProgramSeed, TFuzzWork.TrueTypeProgram, Campaign);

    const Pfb = TPfbParser.Create(TTestFonts.Bytes(OpenSansFile));
    try
      RunMutatedProgram(TEmbeddedProgram.Type1, Pfb.Segment1 + Pfb.Segment2, TTestFonts.Bytes(OpenSansFile), Length(Pfb.Segment1), ProgramSeed + 1, TFuzzWork.Type1Program, Campaign);
    finally
      Pfb.Free;
    end;

    const Cff = TFontDocuments.CffTable(TTestFonts.Bytes(SourceSansFile));
    RunMutatedProgram(TEmbeddedProgram.Cff, Cff, Cff, 0, ProgramSeed + 2, TFuzzWork.CffProgram, Campaign);
    const OpenType = TTestFonts.Bytes(SourceSansFile);
    RunMutatedProgram(TEmbeddedProgram.Cff, Cff, OpenType, 0, ProgramSeed + 4, TFuzzWork.OpenTypeProgram, Campaign);
    const ToUnicode = TEncoding.ASCII.GetBytes(ToUnicodeSource);
    RunMutatedProgram(TEmbeddedProgram.ToUnicode, ToUnicode, ToUnicode, 0, ProgramSeed + 3, TFuzzWork.CMapProgram, Campaign);
    Campaign.AssertNoFailures;
  finally
    Campaign.Free;
  end;
end;

class procedure TTextRobustnessTests.RunHostile(const Campaign: TFuzzCampaign; const Name: string; const Content: string);
begin
  Campaign.Run(Name, TFuzzDocuments.ContentPage(Latin1(Content), TTestFonts.Bytes(LiberationSansFile), HostileChainLength), '', TFuzzWork.LimitedPageText);
end;

class procedure TTextRobustnessTests.RunHostileFont(const Campaign: TFuzzCampaign; const Name: string; const Embedding: TEmbeddedProgram;
                                                    const Data: TBytes; const Segment1Size: Integer);
begin
  Campaign.Run(Format(EmbeddedFormat, [Name]), TFontDocuments.Embed(Embedding, False, Data, Segment1Size), '', TFuzzWork.PageText);
  Campaign.Run(Format(EmbeddedType0Format, [Name]), TFontDocuments.Embed(Embedding, True, Data, Segment1Size), '', TFuzzWork.PageText);
  Campaign.Run(Format(FontClassesFormat, [Name]), TFontDocuments.Embed(Embedding, False, Data, Segment1Size), '', TFuzzWork.FontClasses);
end;

// The offset of the first table is moved far beyond the end of the data
class function TTextRobustnessTests.TrueTypeWithTableOffsetBeyondTheEnd: TBytes;
begin
  Result := TTestFonts.Bytes(LiberationSansFile);
  const FirstEntry = 12;
  Result[FirstEntry + 8] := $7F;
  Result[FirstEntry + 9] := $FF;
  Result[FirstEntry + 10] := $FF;
  Result[FirstEntry + 11] := $F0;
end;

// The count of the first INDEX (the names of the fonts) is 65535
class function TTextRobustnessTests.CffWithAbsurdIndexCount: TBytes;
begin
  Result := TFontDocuments.CffTable(TTestFonts.Bytes(SourceSansFile));
  const HeaderSize = Result[2];
  Result[HeaderSize] := $FF;
  Result[HeaderSize + 1] := $FF;
end;

procedure TTextRobustnessTests.TestHostileSyntheticDocuments;
const
  TextBlock = 'BT /F1 12 Tf 72 700 Td (visible) Tj ET ';
begin
  const Campaign = TFuzzCampaign.Create;
  try
    // Review focus 2: hostile content streams
    RunHostile(Campaign, 'form that draws itself', TextBlock + '/Fm1 Do ' + TextBlock);
    RunHostile(Campaign, 'forms that draw each other twice', TextBlock + '/Fm2 Do ' + TextBlock);
    RunHostile(Campaign, 'chain of forms that draw the next one twice', TextBlock + '/Chain0 Do ' + TextBlock);
    RunHostile(Campaign, 'inline image without EI', Format(SurroundedFormat, [TextBlock, 'BI /W 1 /H 1 /BPC 8 /CS /G ID ', RepeatText('x', 1000000)]));
    RunHostile(Campaign, 'inline image with a huge size and no data', TextBlock + 'BI /W 100000 /H 100000 /BPC 8 /CS /RGB ID ');
    RunHostile(Campaign, 'BI without ID', Format(SurroundedFormat, [TextBlock, 'BI /W 1 /H 1 ', RepeatText('/Name ', 20000)]));
    RunHostile(Campaign, 'q without Q', Format(SurroundedFormat, [TextBlock, RepeatText('q ', 50000), TextBlock]));
    RunHostile(Campaign, 'BMC without EMC', Format(SurroundedFormat, [TextBlock, RepeatText('/Span BMC ', 30000), TextBlock]));
    RunHostile(Campaign, 'BDC without EMC', Format(SurroundedFormat, [TextBlock, RepeatText('/Span << /MCID 1 >> BDC ', 30000), TextBlock]));
    RunHostile(Campaign, 'Q without q', Format(SurroundedFormat, [RepeatText('Q ', 50000), TextBlock, RepeatText('EMC ', 50000)]));
    RunHostile(Campaign, 'arrays nested 200000 deep', Format('%s%s TJ %s', [TextBlock, RepeatText('[ ', 200000), TextBlock]));
    RunHostile(Campaign, 'dictionaries nested 200000 deep', Format('%s%s BDC %s', [TextBlock, RepeatText('<< /A ', 200000), TextBlock]));
    RunHostile(Campaign, 'TJ with three million glyphs', Format('BT /F1 12 Tf [%s] TJ ET', [RepeatText('(AAAAAAAAAA) -1 ', 300000)]));
    RunHostile(Campaign, 'Tj with three million glyphs', Format('BT /F1 12 Tf (%s) Tj ET', [RepeatText('A', 3000000)]));
    RunHostile(Campaign, 'Tj with two million glyphs in a Type 0 font', Format('BT /F2 12 Tf <%s> Tj ET', [RepeatText('0024', 2100000)]));
    RunHostile(Campaign, 'a million operators without operands', Format('%s%s', [RepeatText('q Q ', 500000), TextBlock]));
    RunHostile(Campaign, 'a million operands', Format('%sTj %s', [RepeatText('1 ', 1000000), TextBlock]));
    RunHostile(Campaign, 'a million line moves', Format('BT /F1 12 Tf %sET', [RepeatText('T* (a) Tj ', 100000)]));

    // Review focus 3: damaged font programs, with the text of the page still to come
    const TrueType = TTestFonts.Bytes(LiberationSansFile);
    RunHostileFont(Campaign, 'TrueType cut after 200 bytes', TEmbeddedProgram.TrueType, Copy(TrueType, 0, 200), 0);
    RunHostileFont(Campaign, 'TrueType cut after 5000 bytes', TEmbeddedProgram.TrueType, Copy(TrueType, 0, 5000), 0);
    RunHostileFont(Campaign, 'TrueType cut in the middle', TEmbeddedProgram.TrueType, Copy(TrueType, 0, Length(TrueType) div 2), 0);
    RunHostileFont(Campaign, 'TrueType with a table beyond the end', TEmbeddedProgram.TrueType, TrueTypeWithTableOffsetBeyondTheEnd, 0);
    RunHostileFont(Campaign, 'CFF with an absurd INDEX count', TEmbeddedProgram.Cff, CffWithAbsurdIndexCount, 0);

    const Pfb = TPfbParser.Create(TTestFonts.Bytes(OpenSansFile));
    try
      const Segment1 = Pfb.Segment1;
      var BrokenEexec: TBytes;
      SetLength(BrokenEexec, Length(Pfb.Segment2));
      FillChar(BrokenEexec[0], Length(BrokenEexec), $55);
      RunHostileFont(Campaign, 'Type 1 with a broken eexec part', TEmbeddedProgram.Type1, Segment1 + BrokenEexec, Length(Segment1));
      RunHostileFont(Campaign, 'Type 1 without the encrypted part', TEmbeddedProgram.Type1, Segment1, Length(Segment1));
    finally
      Pfb.Free;
    end;
    Campaign.AssertNoFailures;
  finally
    Campaign.Free;
  end;
end;

end.
