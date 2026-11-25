// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Contains code derived from TwelveMonkeys ImageIO (CCITTFaxDecoderStream), Copyright (c) 2012, Harald Kuhr, BSD 3-Clause License.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/filter/CCITTFaxFilter.java (decode: the parameters, the choice of the compression type
// and the inversion of the bitmap) and CCITTFaxDecoderStream.java (3.0.8: decode1D, decode2D, getNextChangingElement, decodeRow*,
// decodeRun, readBit, the code tables and the code trees). The deviations are listed in docs/porting.md.
unit Pdf4D.Codec.CCITTFax;

interface

uses
  System.SysUtils,
  Pdf4D.Common.Log,
  Pdf4D.Cos.Dictionary;

type
  {$SCOPEDENUMS ON}
  // The compression types of CCITTFaxDecoderStream: modified Huffman RLE (type 2), Group 3 (T4) and Group 4 (T6)
  TCcittCompression = (ModifiedHuffman, Group3, Group4);
  {$SCOPEDENUMS OFF}

  // The DecodeParms of the CCITTFaxDecode filter with the defaults of PDF 32000 table 11
  TCCITTFaxParameters = record
    K: Integer;
    Columns: Integer;
    // The number of rows to decode: the height of the image wins over /Rows when both are given, like CCITTFaxFilter does
    Rows: Integer;
    EncodedByteAlign: Boolean;
    EndOfLine: Boolean;
    EndOfBlock: Boolean;
    BlackIs1: Boolean;
    DamagedRowsBeforeError: Integer;
    // CCITTFaxFilter reads /EndOfLine of a Group 3 1D image only when the entry exists (PDFBOX-6080)
    HasEndOfLine: Boolean;

    // Parms may be nil
    class function FromDictionary(const Parms: TCosDictionary; const ImageHeight: Integer): TCCITTFaxParameters; static;
  end;

  TCCITTFaxDecoder = class
  private
    class function RowBytesOf(const Columns: Integer): Integer; static;
    class procedure CheckDimensions(const Parameters: TCCITTFaxParameters; const MaxPixels: Int64); static;
    class function HasLeadingEndOfLine(const Header: TBytes): Boolean; static;
    class function HasEndOfLineInHeader(const Header: TBytes; const Count: Integer): Boolean; static;
    class function DetectGroup3(const Data: TBytes): TCcittCompression; static;
    class function CompressionOf(const Data: TBytes; const Parameters: TCCITTFaxParameters): TCcittCompression; static;
    class procedure DecodeRows(const Data: TBytes; const Parameters: TCCITTFaxParameters; const Compression: TCcittCompression; const Log: TPdfLog; var Rows: TBytes); static;
    class procedure InvertBits(var Rows: TBytes); static;
  public
    // The rows as 1 bit per pixel, padded to bytes, the bits inverted when /BlackIs1 is false, as CCITTFaxFilter returns them. Raises
    // EPdfParseException for dimensions that are not positive, for more than MaxPixels pixels and for empty data of a Group 3 stream that
    // has to be recognised. Damaged data keeps the rows that were decoded before it, with one warning in the log; a stream that ends
    // early is not reported, like PDFBox. The rest of the rows stays white (all bits 0 before the inversion). Log may be nil.
    class function Decode(const Data: TBytes; const Parameters: TCCITTFaxParameters; const MaxPixels: Int64; const Log: TPdfLog): TBytes; static;
  end;

implementation

uses
  System.Math,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Names;

type
  // The end of the data: the EOFException of the decoder stream
  ECcittDataEnd = class(Exception);

  TCcittCode = record
    Bits: Integer;
    Code: Integer;
    Run: Integer;
  end;

  TCcittNode = record
    Left: Integer;
    Right: Integer;
    Value: Integer;
    IsLeaf: Boolean;
  end;

  // A code tree of CCITTFaxDecoderStream as a list of nodes; the node 0 is the root
  TCcittTree = class
  private
    FNodes: TArray<TCcittNode>;

    function Walk(const Position: Integer; const Bit: Boolean): Integer;
    procedure SetChild(const Position: Integer; const Bit: Boolean; const Child: Integer);

  public
    constructor Create;

    // Tree.fill(depth, path, value)
    procedure FillValue(const Depth, Path, Value: Integer);
    // Tree.fill(depth, path, node)
    procedure FillNode(const Depth, Path, Node: Integer);
    function AddNode(const Value: Integer; const IsLeaf: Boolean): Integer;
    procedure SetChildren(const Position, Left, Right: Integer);
    // The node below Position for Bit, -1 when there is none
    function Step(const Position: Integer; const Bit: Boolean): Integer;
    function IsLeaf(const Position: Integer): Boolean;
    function ValueOf(const Position: Integer): Integer;
  end;

  TCcittRowDecoder = class
  private
    FData: TBytes;
    FBitPosition: Int64;
    FColumns: Integer;
    FCompression: TCcittCompression;
    FTwoDimensional: Boolean;
    FByteAligned: Boolean;
    FReferenceRow: TArray<Integer>;
    FCurrentRow: TArray<Integer>;
    FReferenceCount: Integer;
    FCurrentCount: Integer;
    FLastChangingElement: Integer;
    FScanBudget: Int64;
    FWhiteTree: TCcittTree;
    FBlackTree: TCcittTree;
    FEolTree: TCcittTree;
    FCodeTree: TCcittTree;

    class function CreateRunTree(const Codes: array of TCcittCode): TCcittTree; static;
    class procedure AddEolAndFill(const Tree: TCcittTree); static;
    class function CreateCodeTree: TCcittTree; static;

    function ReadBit: Boolean;
    procedure AlignToByte;
    procedure AddChange(const Position: Integer);
    function DecodeRun(const Tree: TCcittTree): Integer;
    procedure Decode1D;
    procedure DecodeHorizontalMode(const White: Boolean; var Position: Integer);
    procedure DecodePassMode(const White: Boolean; var Position: Integer);
    procedure DecodeVerticalMode(const Offset: Integer; var White: Boolean; var Position: Integer);
    procedure Decode2D;
    function GetNextChangingElement(const ReferencePosition: Integer; const White: Boolean): Integer;
    procedure SkipToEndOfLine;
    procedure DecodeRowType2;
    procedure DecodeRowType4;
    procedure DecodeRowType6;

  public
    constructor Create(const Data: TBytes; const Columns: Integer; const Compression: TCcittCompression; const TwoDimensional, ByteAligned: Boolean);
    destructor Destroy; override;

    // Decodes the next row. Raises ECcittDataEnd at the end of the data and EPdfParseException for a malformed row.
    procedure DecodeRow;
    // Sets the bits of the black runs of the row that was decoded in Target, which holds zero bits there; the row starts at Offset
    procedure PaintRow(var Target: TBytes; const Offset: Integer);
  end;

const
  DefaultColumns = 1728;
  // The change lists of a row take 8 bytes per column; a fax row of a million pixels is already far beyond a fax
  MaxColumns = 1024 * 1024;
  ByteBits = 8;
  HeaderLength = 20;
  EolBits = 12;
  EolWindowMask = $FFF;
  PassModeValue = -3000;
  HorizontalModeValue = -4000;
  EolValue = -2000;
  FillValue = -1000;
  MakeupRunStart = 64;
  // A run total stays far below the range of an Integer, however many make-up codes a damaged stream strings together
  MaxRunTotal = MaxInt div 2;
  // A well-formed row searches the reference row about once; the budget stops crafted rows that make the search repeat
  ScanStepsPerColumn = 8;
  ScanStepsPerRow = 1024;

  BlackCodes: array[0..103] of TCcittCode = (
    (Bits: 2; Code: $2; Run: 3), (Bits: 2; Code: $3; Run: 2), (Bits: 3; Code: $2; Run: 1), (Bits: 3; Code: $3; Run: 4),
    (Bits: 4; Code: $2; Run: 6), (Bits: 4; Code: $3; Run: 5), (Bits: 5; Code: $3; Run: 7), (Bits: 6; Code: $4; Run: 9),
    (Bits: 6; Code: $5; Run: 8), (Bits: 7; Code: $4; Run: 10), (Bits: 7; Code: $5; Run: 11), (Bits: 7; Code: $7; Run: 12),
    (Bits: 8; Code: $4; Run: 13), (Bits: 8; Code: $7; Run: 14), (Bits: 9; Code: $18; Run: 15), (Bits: 10; Code: $17; Run: 16),
    (Bits: 10; Code: $18; Run: 17), (Bits: 10; Code: $37; Run: 0), (Bits: 10; Code: $8; Run: 18), (Bits: 10; Code: $F; Run: 64),
    (Bits: 11; Code: $17; Run: 24), (Bits: 11; Code: $18; Run: 25), (Bits: 11; Code: $28; Run: 23), (Bits: 11; Code: $37; Run: 22),
    (Bits: 11; Code: $67; Run: 19), (Bits: 11; Code: $68; Run: 20), (Bits: 11; Code: $6C; Run: 21), (Bits: 11; Code: $8; Run: 1792),
    (Bits: 11; Code: $C; Run: 1856), (Bits: 11; Code: $D; Run: 1920), (Bits: 12; Code: $12; Run: 1984), (Bits: 12; Code: $13; Run: 2048),
    (Bits: 12; Code: $14; Run: 2112), (Bits: 12; Code: $15; Run: 2176), (Bits: 12; Code: $16; Run: 2240), (Bits: 12; Code: $17; Run: 2304),
    (Bits: 12; Code: $1C; Run: 2368), (Bits: 12; Code: $1D; Run: 2432), (Bits: 12; Code: $1E; Run: 2496), (Bits: 12; Code: $1F; Run: 2560),
    (Bits: 12; Code: $24; Run: 52), (Bits: 12; Code: $27; Run: 55), (Bits: 12; Code: $28; Run: 56), (Bits: 12; Code: $2B; Run: 59),
    (Bits: 12; Code: $2C; Run: 60), (Bits: 12; Code: $33; Run: 320), (Bits: 12; Code: $34; Run: 384), (Bits: 12; Code: $35; Run: 448),
    (Bits: 12; Code: $37; Run: 53), (Bits: 12; Code: $38; Run: 54), (Bits: 12; Code: $52; Run: 50), (Bits: 12; Code: $53; Run: 51),
    (Bits: 12; Code: $54; Run: 44), (Bits: 12; Code: $55; Run: 45), (Bits: 12; Code: $56; Run: 46), (Bits: 12; Code: $57; Run: 47),
    (Bits: 12; Code: $58; Run: 57), (Bits: 12; Code: $59; Run: 58), (Bits: 12; Code: $5A; Run: 61), (Bits: 12; Code: $5B; Run: 256),
    (Bits: 12; Code: $64; Run: 48), (Bits: 12; Code: $65; Run: 49), (Bits: 12; Code: $66; Run: 62), (Bits: 12; Code: $67; Run: 63),
    (Bits: 12; Code: $68; Run: 30), (Bits: 12; Code: $69; Run: 31), (Bits: 12; Code: $6A; Run: 32), (Bits: 12; Code: $6B; Run: 33),
    (Bits: 12; Code: $6C; Run: 40), (Bits: 12; Code: $6D; Run: 41), (Bits: 12; Code: $C8; Run: 128), (Bits: 12; Code: $C9; Run: 192),
    (Bits: 12; Code: $CA; Run: 26), (Bits: 12; Code: $CB; Run: 27), (Bits: 12; Code: $CC; Run: 28), (Bits: 12; Code: $CD; Run: 29),
    (Bits: 12; Code: $D2; Run: 34), (Bits: 12; Code: $D3; Run: 35), (Bits: 12; Code: $D4; Run: 36), (Bits: 12; Code: $D5; Run: 37),
    (Bits: 12; Code: $D6; Run: 38), (Bits: 12; Code: $D7; Run: 39), (Bits: 12; Code: $DA; Run: 42), (Bits: 12; Code: $DB; Run: 43),
    (Bits: 13; Code: $4A; Run: 640), (Bits: 13; Code: $4B; Run: 704), (Bits: 13; Code: $4C; Run: 768), (Bits: 13; Code: $4D; Run: 832),
    (Bits: 13; Code: $52; Run: 1280), (Bits: 13; Code: $53; Run: 1344), (Bits: 13; Code: $54; Run: 1408), (Bits: 13; Code: $55; Run: 1472),
    (Bits: 13; Code: $5A; Run: 1536), (Bits: 13; Code: $5B; Run: 1600), (Bits: 13; Code: $64; Run: 1664), (Bits: 13; Code: $65; Run: 1728),
    (Bits: 13; Code: $6C; Run: 512), (Bits: 13; Code: $6D; Run: 576), (Bits: 13; Code: $72; Run: 896), (Bits: 13; Code: $73; Run: 960),
    (Bits: 13; Code: $74; Run: 1024), (Bits: 13; Code: $75; Run: 1088), (Bits: 13; Code: $76; Run: 1152), (Bits: 13; Code: $77; Run: 1216));

  WhiteCodes: array[0..103] of TCcittCode = (
    (Bits: 4; Code: $7; Run: 2), (Bits: 4; Code: $8; Run: 3), (Bits: 4; Code: $B; Run: 4), (Bits: 4; Code: $C; Run: 5),
    (Bits: 4; Code: $E; Run: 6), (Bits: 4; Code: $F; Run: 7), (Bits: 5; Code: $12; Run: 128), (Bits: 5; Code: $13; Run: 8),
    (Bits: 5; Code: $14; Run: 9), (Bits: 5; Code: $1B; Run: 64), (Bits: 5; Code: $7; Run: 10), (Bits: 5; Code: $8; Run: 11),
    (Bits: 6; Code: $17; Run: 192), (Bits: 6; Code: $18; Run: 1664), (Bits: 6; Code: $2A; Run: 16), (Bits: 6; Code: $2B; Run: 17),
    (Bits: 6; Code: $3; Run: 13), (Bits: 6; Code: $34; Run: 14), (Bits: 6; Code: $35; Run: 15), (Bits: 6; Code: $7; Run: 1),
    (Bits: 6; Code: $8; Run: 12), (Bits: 7; Code: $13; Run: 26), (Bits: 7; Code: $17; Run: 21), (Bits: 7; Code: $18; Run: 28),
    (Bits: 7; Code: $24; Run: 27), (Bits: 7; Code: $27; Run: 18), (Bits: 7; Code: $28; Run: 24), (Bits: 7; Code: $2B; Run: 25),
    (Bits: 7; Code: $3; Run: 22), (Bits: 7; Code: $37; Run: 256), (Bits: 7; Code: $4; Run: 23), (Bits: 7; Code: $8; Run: 20),
    (Bits: 7; Code: $C; Run: 19), (Bits: 8; Code: $12; Run: 33), (Bits: 8; Code: $13; Run: 34), (Bits: 8; Code: $14; Run: 35),
    (Bits: 8; Code: $15; Run: 36), (Bits: 8; Code: $16; Run: 37), (Bits: 8; Code: $17; Run: 38), (Bits: 8; Code: $1A; Run: 31),
    (Bits: 8; Code: $1B; Run: 32), (Bits: 8; Code: $2; Run: 29), (Bits: 8; Code: $24; Run: 53), (Bits: 8; Code: $25; Run: 54),
    (Bits: 8; Code: $28; Run: 39), (Bits: 8; Code: $29; Run: 40), (Bits: 8; Code: $2A; Run: 41), (Bits: 8; Code: $2B; Run: 42),
    (Bits: 8; Code: $2C; Run: 43), (Bits: 8; Code: $2D; Run: 44), (Bits: 8; Code: $3; Run: 30), (Bits: 8; Code: $32; Run: 61),
    (Bits: 8; Code: $33; Run: 62), (Bits: 8; Code: $34; Run: 63), (Bits: 8; Code: $35; Run: 0), (Bits: 8; Code: $36; Run: 320),
    (Bits: 8; Code: $37; Run: 384), (Bits: 8; Code: $4; Run: 45), (Bits: 8; Code: $4A; Run: 59), (Bits: 8; Code: $4B; Run: 60),
    (Bits: 8; Code: $5; Run: 46), (Bits: 8; Code: $52; Run: 49), (Bits: 8; Code: $53; Run: 50), (Bits: 8; Code: $54; Run: 51),
    (Bits: 8; Code: $55; Run: 52), (Bits: 8; Code: $58; Run: 55), (Bits: 8; Code: $59; Run: 56), (Bits: 8; Code: $5A; Run: 57),
    (Bits: 8; Code: $5B; Run: 58), (Bits: 8; Code: $64; Run: 448), (Bits: 8; Code: $65; Run: 512), (Bits: 8; Code: $67; Run: 640),
    (Bits: 8; Code: $68; Run: 576), (Bits: 8; Code: $A; Run: 47), (Bits: 8; Code: $B; Run: 48), (Bits: 9; Code: $98; Run: 1472),
    (Bits: 9; Code: $99; Run: 1536), (Bits: 9; Code: $9A; Run: 1600), (Bits: 9; Code: $9B; Run: 1728), (Bits: 9; Code: $CC; Run: 704),
    (Bits: 9; Code: $CD; Run: 768), (Bits: 9; Code: $D2; Run: 832), (Bits: 9; Code: $D3; Run: 896), (Bits: 9; Code: $D4; Run: 960),
    (Bits: 9; Code: $D5; Run: 1024), (Bits: 9; Code: $D6; Run: 1088), (Bits: 9; Code: $D7; Run: 1152), (Bits: 9; Code: $D8; Run: 1216),
    (Bits: 9; Code: $D9; Run: 1280), (Bits: 9; Code: $DA; Run: 1344), (Bits: 9; Code: $DB; Run: 1408), (Bits: 11; Code: $8; Run: 1792),
    (Bits: 11; Code: $C; Run: 1856), (Bits: 11; Code: $D; Run: 1920), (Bits: 12; Code: $12; Run: 1984), (Bits: 12; Code: $13; Run: 2048),
    (Bits: 12; Code: $14; Run: 2112), (Bits: 12; Code: $15; Run: 2176), (Bits: 12; Code: $16; Run: 2240), (Bits: 12; Code: $17; Run: 2304),
    (Bits: 12; Code: $1C; Run: 2368), (Bits: 12; Code: $1D; Run: 2432), (Bits: 12; Code: $1E; Run: 2496), (Bits: 12; Code: $1F; Run: 2560));

resourcestring
  CcittInvalidDimensions = 'Invalid CCITT image dimensions: columns=%d, rows=%d';
  CcittTooLarge = 'CCITT image of %d x %d pixels is over the limit of %d pixels';
  CcittNoHeader = 'EOF while reading CCITT header';
  CcittEndOfData = 'Unexpected end of Huffman RLE stream';
  CcittUnknownCode = 'Unknown code in Huffman RLE stream';
  CcittTooManyChanges = 'Malformed CCITT stream';
  CcittTooMuchWork = 'CCITT row needs too much work to decode';
  CcittDamaged = 'The CCITT data is damaged after %d of %d rows (%s); the rest of the image is white';

{ TCCITTFaxParameters }

class function TCCITTFaxParameters.FromDictionary(const Parms: TCosDictionary; const ImageHeight: Integer): TCCITTFaxParameters;
begin
  Result := Default(TCCITTFaxParameters);
  Result.Columns := DefaultColumns;
  Result.EndOfBlock := True;
  var DictionaryRows := 0;
  if Assigned(Parms) then
  begin
    Result.K := Parms.GetInt(TCosNames.K, 0);
    Result.Columns := Parms.GetInt(TCosNames.Columns, DefaultColumns);
    DictionaryRows := Parms.GetInt(TCosNames.Rows, 0);
    Result.EncodedByteAlign := Parms.GetBoolean(TCosNames.EncodedByteAlign, False);
    var EndOfLineEntry: TCosBase;
    Result.HasEndOfLine := Parms.TryGetDictionaryObject(TCosNames.EndOfLine, EndOfLineEntry);
    Result.EndOfLine := Parms.GetBoolean(TCosNames.EndOfLine, False);
    Result.EndOfBlock := Parms.GetBoolean(TCosNames.EndOfBlock, True);
    Result.BlackIs1 := Parms.GetBoolean(TCosNames.BlackIs1, False);
    Result.DamagedRowsBeforeError := Parms.GetInt(TCosNames.DamagedRowsBeforeError, 0);
  end;

  // PDFBOX-771, PDFBOX-3727: /Rows sometimes holds an incorrect value
  const BothGiven = ((DictionaryRows > 0) and (ImageHeight > 0));
  if BothGiven then
  begin
    Result.Rows := ImageHeight;
  end
  else
  begin
    Result.Rows := Max(DictionaryRows, ImageHeight);
  end;
end;

{ TCcittTree }

constructor TCcittTree.Create;
begin
  inherited Create;
  AddNode(0, False);
end;

function TCcittTree.AddNode(const Value: Integer; const IsLeaf: Boolean): Integer;
begin
  Result := Length(FNodes);
  SetLength(FNodes, Result + 1);
  FNodes[Result].Left := -1;
  FNodes[Result].Right := -1;
  FNodes[Result].Value := Value;
  FNodes[Result].IsLeaf := IsLeaf;
end;

procedure TCcittTree.SetChildren(const Position, Left, Right: Integer);
begin
  FNodes[Position].Left := Left;
  FNodes[Position].Right := Right;
end;

function TCcittTree.Walk(const Position: Integer; const Bit: Boolean): Integer;
begin
  if Bit then
  begin
    Result := FNodes[Position].Right;
  end
  else
  begin
    Result := FNodes[Position].Left;
  end;
end;

procedure TCcittTree.SetChild(const Position: Integer; const Bit: Boolean; const Child: Integer);
begin
  if Bit then
  begin
    FNodes[Position].Right := Child;
  end
  else
  begin
    FNodes[Position].Left := Child;
  end;
end;

procedure TCcittTree.FillValue(const Depth, Path, Value: Integer);
begin
  var Current := 0;
  for var Level := 0 to Depth - 1 do
  begin
    const BitPosition = Depth - 1 - Level;
    const IsSet = (((Path shr BitPosition) and 1) = 1);
    var Next := Walk(Current, IsSet);
    if Next < 0 then
    begin
      const IsLastLevel = (Level = Depth - 1);
      Next := AddNode(Value, IsLastLevel);
      SetChild(Current, IsSet, Next);
    end;
    Current := Next;
  end;
end;

procedure TCcittTree.FillNode(const Depth, Path, Node: Integer);
begin
  var Current := 0;
  for var Level := 0 to Depth - 1 do
  begin
    const BitPosition = Depth - 1 - Level;
    const IsSet = (((Path shr BitPosition) and 1) = 1);
    var Next := Walk(Current, IsSet);
    if Next < 0 then
    begin
      const IsLastLevel = (Level = Depth - 1);
      if IsLastLevel then
      begin
        Next := Node;
      end
      else
      begin
        Next := AddNode(0, False);
      end;
      SetChild(Current, IsSet, Next);
    end;
    Current := Next;
  end;
end;

function TCcittTree.Step(const Position: Integer; const Bit: Boolean): Integer;
begin
  Result := Walk(Position, Bit);
end;

function TCcittTree.IsLeaf(const Position: Integer): Boolean;
begin
  Result := FNodes[Position].IsLeaf;
end;

function TCcittTree.ValueOf(const Position: Integer): Integer;
begin
  Result := FNodes[Position].Value;
end;

{ TCcittRowDecoder }

constructor TCcittRowDecoder.Create(const Data: TBytes; const Columns: Integer; const Compression: TCcittCompression; const TwoDimensional, ByteAligned: Boolean);
begin
  inherited Create;
  FData := Data;
  FColumns := Columns;
  FCompression := Compression;
  FTwoDimensional := TwoDimensional;
  FByteAligned := ByteAligned;
  SetLength(FReferenceRow, Columns + 2);
  SetLength(FCurrentRow, Columns + 2);

  FWhiteTree := CreateRunTree(WhiteCodes);
  FBlackTree := CreateRunTree(BlackCodes);
  FEolTree := TCcittTree.Create;
  AddEolAndFill(FEolTree);
  FCodeTree := CreateCodeTree;
end;

destructor TCcittRowDecoder.Destroy;
begin
  FCodeTree.Free;
  FEolTree.Free;
  FBlackTree.Free;
  FWhiteTree.Free;
  inherited Destroy;
end;

// The EOL (000000000001) and the fill (a run of 0 bits before an EOL) are codes of every run tree
class procedure TCcittRowDecoder.AddEolAndFill(const Tree: TCcittTree);
begin
  const EolNode = Tree.AddNode(EolValue, True);
  const FillNode = Tree.AddNode(FillValue, False);
  Tree.SetChildren(FillNode, FillNode, EolNode);
  Tree.FillNode(EolBits, 0, FillNode);
  Tree.FillNode(EolBits, 1, EolNode);
end;

class function TCcittRowDecoder.CreateRunTree(const Codes: array of TCcittCode): TCcittTree;
begin
  Result := TCcittTree.Create;
  for var Entry in Codes do
  begin
    Result.FillValue(Entry.Bits, Entry.Code, Entry.Run);
  end;
  AddEolAndFill(Result);
end;

// The codes of the 2D modes: pass, horizontal and the vertical offsets -3 to 3
class function TCcittRowDecoder.CreateCodeTree: TCcittTree;
begin
  Result := TCcittTree.Create;
  Result.FillValue(4, 1, PassModeValue);
  Result.FillValue(3, 1, HorizontalModeValue);
  Result.FillValue(1, 1, 0);
  Result.FillValue(3, 3, 1);
  Result.FillValue(6, 3, 2);
  Result.FillValue(7, 3, 3);
  Result.FillValue(3, 2, -1);
  Result.FillValue(6, 2, -2);
  Result.FillValue(7, 2, -3);
end;

function TCcittRowDecoder.ReadBit: Boolean;
begin
  const ByteIndex = FBitPosition shr 3;
  if ByteIndex >= Length(FData) then
  begin
    raise ECcittDataEnd.Create(CcittEndOfData);
  end;

  const BitMask = $80 shr (FBitPosition and 7);
  Result := ((FData[ByteIndex] and BitMask) <> 0);
  Inc(FBitPosition);
end;

// resetBuffer: the rest of the byte is skipped
procedure TCcittRowDecoder.AlignToByte;
begin
  FBitPosition := (FBitPosition + 7) and not Int64(7);
end;

// The arrays of the changes of the Java code have columns + 2 entries: one more is the ArrayIndexOutOfBoundsException that the stream
// turns into an IOException
procedure TCcittRowDecoder.AddChange(const Position: Integer);
begin
  const IsFull = (FCurrentCount >= Length(FCurrentRow));
  if IsFull then
  begin
    raise EPdfParseException.Create(CcittTooManyChanges);
  end;
  FCurrentRow[FCurrentCount] := Position;
  Inc(FCurrentCount);
end;

function TCcittRowDecoder.DecodeRun(const Tree: TCcittTree): Integer;
begin
  var Total := 0;
  var Node := 0;
  while True do
  begin
    Node := Tree.Step(Node, ReadBit);
    if Node < 0 then
    begin
      raise EPdfParseException.Create(CcittUnknownCode);
    end;

    if Tree.IsLeaf(Node) then
    begin
      const Value = Tree.ValueOf(Node);
      Total := Min(Total + Value, MaxRunTotal);
      if Value >= MakeupRunStart then
      begin
        Node := 0;
      end
      else if Value >= 0 then
      begin
        Exit(Total);
      end
      else
      begin
        Exit(FColumns);
      end;
    end;
  end;
end;

procedure TCcittRowDecoder.Decode1D;
begin
  var Position := 0;
  var White := True;
  FCurrentCount := 0;

  repeat
    var Run: Integer;
    if White then
    begin
      Run := DecodeRun(FWhiteTree);
    end
    else
    begin
      Run := DecodeRun(FBlackTree);
    end;

    Position := Min(Position + Run, MaxRunTotal);
    AddChange(Position);
    White := not White;
  until Position >= FColumns;
end;

procedure TCcittRowDecoder.DecodeHorizontalMode(const White: Boolean; var Position: Integer);
begin
  var FirstTree := FBlackTree;
  var SecondTree := FWhiteTree;
  if White then
  begin
    FirstTree := FWhiteTree;
    SecondTree := FBlackTree;
  end;

  Position := Min(Position + DecodeRun(FirstTree), MaxRunTotal);
  AddChange(Position);

  Position := Min(Position + DecodeRun(SecondTree), MaxRunTotal);
  AddChange(Position);
end;

procedure TCcittRowDecoder.DecodePassMode(const White: Boolean; var Position: Integer);
begin
  const ChangingElement = GetNextChangingElement(Position, White) + 1;
  if ChangingElement >= FReferenceCount then
  begin
    Position := FColumns;
  end
  else
  begin
    Position := FReferenceRow[ChangingElement];
  end;
end;

procedure TCcittRowDecoder.DecodeVerticalMode(const Offset: Integer; var White: Boolean; var Position: Integer);
begin
  const ChangingElement = GetNextChangingElement(Position, White);
  const HasNoChangingElement = ((ChangingElement >= FReferenceCount) or (ChangingElement = -1));
  if HasNoChangingElement then
  begin
    Position := FColumns + Offset;
  end
  else
  begin
    Position := FReferenceRow[ChangingElement] + Offset;
  end;

  AddChange(Position);
  White := not White;
end;

procedure TCcittRowDecoder.Decode2D;
begin
  FReferenceCount := FCurrentCount;
  const Previous = FCurrentRow;
  FCurrentRow := FReferenceRow;
  FReferenceRow := Previous;

  var White := True;
  var Position := 0;
  FCurrentCount := 0;

  while Position < FColumns do
  begin
    var Node := 0;
    while True do
    begin
      Node := FCodeTree.Step(Node, ReadBit);
      if Node < 0 then
      begin
        Break;
      end;

      if FCodeTree.IsLeaf(Node) then
      begin
        const Mode = FCodeTree.ValueOf(Node);
        case Mode of
          HorizontalModeValue : DecodeHorizontalMode(White, Position);
          PassModeValue       : DecodePassMode(White, Position);
        else
          DecodeVerticalMode(Mode, White, Position);
        end;
        Break;
      end;
    end;
  end;
end;

function TCcittRowDecoder.GetNextChangingElement(const ReferencePosition: Integer; const White: Boolean): Integer;
begin
  var Start := (FLastChangingElement and not 1);
  if not White then
  begin
    Inc(Start);
  end;
  if Start > 2 then
  begin
    Dec(Start, 2);
  end;

  if ReferencePosition = 0 then
  begin
    Exit(Start);
  end;

  var Index := Start;
  while Index < FReferenceCount do
  begin
    Dec(FScanBudget);
    if FScanBudget < 0 then
    begin
      raise EPdfParseException.Create(CcittTooMuchWork);
    end;
    if ReferencePosition < FReferenceRow[Index] then
    begin
      FLastChangingElement := Index;
      Exit(Index);
    end;
    Inc(Index, 2);
  end;
  Result := -1;
end;

// Reads up to the next EOL, a row of 0 bits before it included
procedure TCcittRowDecoder.SkipToEndOfLine;
begin
  var Node := 0;
  while True do
  begin
    Node := FEolTree.Step(Node, ReadBit);
    if Node < 0 then
    begin
      Node := 0;
    end
    else if FEolTree.IsLeaf(Node) then
    begin
      Exit;
    end;
  end;
end;

procedure TCcittRowDecoder.DecodeRowType2;
begin
  if FByteAligned then
  begin
    AlignToByte;
  end;
  Decode1D;
end;

procedure TCcittRowDecoder.DecodeRowType4;
begin
  if FByteAligned then
  begin
    AlignToByte;
  end;
  SkipToEndOfLine;

  const IsOneDimensional = ((not FTwoDimensional) or ReadBit);
  if IsOneDimensional then
  begin
    Decode1D;
  end
  else
  begin
    Decode2D;
  end;
end;

procedure TCcittRowDecoder.DecodeRowType6;
begin
  if FByteAligned then
  begin
    AlignToByte;
  end;
  Decode2D;
end;

procedure TCcittRowDecoder.DecodeRow;
begin
  FScanBudget := ScanStepsPerColumn * (Int64(FColumns) + 2) + ScanStepsPerRow;
  case FCompression of
    TCcittCompression.ModifiedHuffman : DecodeRowType2;
    TCcittCompression.Group3          : DecodeRowType4;
    TCcittCompression.Group4          : DecodeRowType6;
  else
    raise ENotSupportedException.CreateFmt('Unsupported CCITT compression: %d', [Ord(FCompression)]);
  end;
  FLastChangingElement := 0;
end;

procedure TCcittRowDecoder.PaintRow(var Target: TBytes; const Offset: Integer);
begin
  var Position := 0;
  var White := True;
  for var Change := 0 to FCurrentCount do
  begin
    var NextChange := FColumns;
    if Change <> FCurrentCount then
    begin
      NextChange := Min(FCurrentRow[Change], FColumns);
    end;

    if not White then
    begin
      for var Pixel := Position to NextChange - 1 do
      begin
        const ByteIndex = Offset + (Pixel shr 3);
        Target[ByteIndex] := Target[ByteIndex] or Byte($80 shr (Pixel and 7));
      end;
    end;
    Position := Max(Position, NextChange);
    White := not White;
  end;
end;

{ TCCITTFaxDecoder }

class function TCCITTFaxDecoder.RowBytesOf(const Columns: Integer): Integer;
begin
  Result := (Columns + ByteBits - 1) div ByteBits;
end;

// Throws like CCITTFaxFilter for dimensions that are not positive; the limits on the size are the ones of the Delphi code
class procedure TCCITTFaxDecoder.CheckDimensions(const Parameters: TCCITTFaxParameters; const MaxPixels: Int64);
begin
  const AreDimensionsValid = ((Parameters.Columns > 0) and (Parameters.Rows > 0));
  if not AreDimensionsValid then
  begin
    raise EPdfParseException.CreateFmt(CcittInvalidDimensions, [Parameters.Columns, Parameters.Rows]);
  end;

  const IsTooLarge = ((Parameters.Columns > MaxColumns) or (Int64(Parameters.Columns) * Parameters.Rows > MaxPixels));
  if IsTooLarge then
  begin
    raise EPdfParseException.CreateFmt(CcittTooLarge, [Parameters.Columns, Parameters.Rows, MaxPixels]);
  end;
end;

// streamData[0] == 0 and the first 4 bits of streamData[1] are 0001 or streamData[1] is 1: an EOL (000000000001) leads the data
class function TCCITTFaxDecoder.HasLeadingEndOfLine(const Header: TBytes): Boolean;
begin
  const FirstByteIsZero = (Header[0] = 0);
  const SecondByteEndsEol = (((Header[1] shr 4) = 1) or (Header[1] = 1));
  Result := (FirstByteIsZero and SecondByteEndsEol);
end;

// Looks for an EOL anywhere in the first bits of the header: 11 zero bits and a one, after the 12 bits that were seen
class function TCCITTFaxDecoder.HasEndOfLineInHeader(const Header: TBytes; const Count: Integer): Boolean;
begin
  var Window := ((Header[0] shl 4) or (Header[1] shr 4)) and EolWindowMask;
  for var BitIndex := EolBits to Count * ByteBits - 1 do
  begin
    const Bit = (Header[BitIndex div ByteBits] shr (7 - (BitIndex mod ByteBits))) and 1;
    Window := ((Window shl 1) + Bit) and EolWindowMask;
    if Window = 1 then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

// The type of a stream with /K 0 and no /EndOfLine: findCompressionType of the TwelveMonkeys decoder, as CCITTFaxFilter does it
class function TCCITTFaxDecoder.DetectGroup3(const Data: TBytes): TCcittCompression;
begin
  if Length(Data) = 0 then
  begin
    raise EPdfParseException.Create(CcittNoHeader);
  end;

  const Count = Min(Length(Data), HeaderLength);
  var Header: TBytes;
  SetLength(Header, HeaderLength);
  Move(Data[0], Header[0], Count);

  const IsGroup3 = (HasLeadingEndOfLine(Header) or HasEndOfLineInHeader(Header, Count));
  if IsGroup3 then
  begin
    Result := TCcittCompression.Group3;
  end
  else
  begin
    Result := TCcittCompression.ModifiedHuffman;
  end;
end;

class function TCCITTFaxDecoder.CompressionOf(const Data: TBytes; const Parameters: TCCITTFaxParameters): TCcittCompression;
begin
  if Parameters.K < 0 then
  begin
    Exit(TCcittCompression.Group4);
  end;
  if Parameters.K > 0 then
  begin
    Exit(TCcittCompression.Group3);
  end;

  if Parameters.HasEndOfLine then
  begin
    // PDFBOX-6080: respect the parameter if it exists
    if Parameters.EndOfLine then
    begin
      Exit(TCcittCompression.Group3);
    end;
    Exit(TCcittCompression.ModifiedHuffman);
  end;
  Result := DetectGroup3(Data);
end;

class procedure TCCITTFaxDecoder.DecodeRows(const Data: TBytes; const Parameters: TCCITTFaxParameters; const Compression: TCcittCompression;
                                            const Log: TPdfLog; var Rows: TBytes);
begin
  const IsTwoDimensional = ((Compression = TCcittCompression.Group3) and (Parameters.K > 0));
  const RowDecoder = TCcittRowDecoder.Create(Data, Parameters.Columns, Compression, IsTwoDimensional, Parameters.EncodedByteAlign);
  try
    const RowBytes = RowBytesOf(Parameters.Columns);
    for var RowIndex := 0 to Parameters.Rows - 1 do
    begin
      try
        RowDecoder.DecodeRow;
      except
        on ECcittDataEnd do
        begin
          Exit;
        end;
        on Error: EPdfParseException do
        begin
          if Assigned(Log) then
          begin
            Log.Warning(CcittDamaged, [RowIndex, Parameters.Rows, Error.Message]);
          end;
          Exit;
        end;
      end;
      RowDecoder.PaintRow(Rows, RowIndex * RowBytes);
    end;
  finally
    RowDecoder.Free;
  end;
end;

// invertBitmap
class procedure TCCITTFaxDecoder.InvertBits(var Rows: TBytes);
begin
  for var Index := 0 to Length(Rows) - 1 do
  begin
    Rows[Index] := not Rows[Index];
  end;
end;

class function TCCITTFaxDecoder.Decode(const Data: TBytes; const Parameters: TCCITTFaxParameters; const MaxPixels: Int64; const Log: TPdfLog): TBytes;
begin
  CheckDimensions(Parameters, MaxPixels);
  const Compression = CompressionOf(Data, Parameters);

  Result := nil;
  SetLength(Result, RowBytesOf(Parameters.Columns) * Parameters.Rows);
  DecodeRows(Data, Parameters, Compression, Log, Result);

  if not Parameters.BlackIs1 then
  begin
    InvertBits(Result);
  end;
end;

end.
