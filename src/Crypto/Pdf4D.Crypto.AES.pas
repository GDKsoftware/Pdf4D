unit Pdf4D.Crypto.AES;

// Replaces javax.crypto.Cipher with AES/CBC/PKCS5Padding, AES/CBC/NoPadding and AES/ECB/NoPadding as used by
// pdfbox/src/main/java/org/apache/pdfbox/pdmodel/encryption/SecurityHandler.java and StandardSecurityHandler.java (3.0.8)
// A plain round-based AES (FIPS-197) with explicit tables. Readability goes before speed.

interface

uses
  System.SysUtils;

type
  TAESCipher = class
  private
    type
      TAESState = array[0..15] of Byte;
      TAESWord = array[0..3] of Byte;
      TAESMatrix = array[0..3, 0..3] of Byte;

  private
    FRoundKeys: TBytes;
    FRoundCount: Integer;

    class function Multiply(const Left, Right: Byte): Byte; static;
    class function SubstituteWord(const Word: TAESWord): TAESWord; static;
    class function RotateWord(const Word: TAESWord): TAESWord; static;
    class function SubstituteBytes(const State: TAESState; const Table: array of Byte): TAESState; static;
    class function ShiftRows(const State: TAESState): TAESState; static;
    class function InverseShiftRows(const State: TAESState): TAESState; static;
    class function MixColumns(const State: TAESState; const Matrix: TAESMatrix): TAESState; static;
    class function XorStates(const Left, Right: TAESState): TAESState; static;
    class function LoadState(const Data: TBytes; const Offset: Integer): TAESState; static;
    class procedure StoreState(const State: TAESState; const Data: TBytes; const Offset: Integer); static;
    class function TryGetPaddingLength(const Data: TBytes; out PaddingLength: Integer): Boolean; static;
    class procedure GuardKey(const Key: TBytes); static;
    class procedure GuardWholeBlocks(const Data: TBytes); static;
    class procedure GuardBlock(const Block: TBytes); static;
    class procedure GuardIV(const IV: TBytes); static;

    procedure ExpandKey(const Key: TBytes);
    function GetKeyWord(const WordIndex: Integer): TAESWord;
    procedure SetKeyWord(const WordIndex: Integer; const Word: TAESWord);
    function NextKeyWord(const WordIndex, KeyWordCount: Integer): TAESWord;
    function AddRoundKey(const State: TAESState; const Round: Integer): TAESState;
    function EncryptState(const State: TAESState): TAESState;
    function DecryptState(const State: TAESState): TAESState;
    function DecryptBlocksCbc(const IV, Data: TBytes; const BlockCount: Integer): TBytes;

  public
    constructor Create(const Key: TBytes);

    function EncryptBlock(const Block: TBytes): TBytes;
    function DecryptBlock(const Block: TBytes): TBytes;

    // Without RemovePadding all decrypted bytes are returned. With it, valid PKCS#7 padding is removed.
    // WasLenient reports that the input was not well formed: a trailing partial block was dropped, or the padding
    // was invalid and left in place. Like PDFBox, this never raises, so the caller can log it.
    function DecryptCbc(const IV, Data: TBytes; const RemovePadding: Boolean): TBytes; overload;
    function DecryptCbc(const IV, Data: TBytes; const RemovePadding: Boolean; out WasLenient: Boolean): TBytes; overload;

    function EncryptCbcNoPadding(const IV, Data: TBytes): TBytes;
    function DecryptEcbNoPadding(const Data: TBytes): TBytes;
  end;

implementation

const
  BlockSize = 16;
  WordSize = 4;
  ColumnCount = 4;
  MaxPaddingLength = 16;
  EnlargedKeySchedule = 6;

  SBox: array[0..255] of Byte = (
    $63, $7C, $77, $7B, $F2, $6B, $6F, $C5, $30, $01, $67, $2B, $FE, $D7, $AB, $76,
    $CA, $82, $C9, $7D, $FA, $59, $47, $F0, $AD, $D4, $A2, $AF, $9C, $A4, $72, $C0,
    $B7, $FD, $93, $26, $36, $3F, $F7, $CC, $34, $A5, $E5, $F1, $71, $D8, $31, $15,
    $04, $C7, $23, $C3, $18, $96, $05, $9A, $07, $12, $80, $E2, $EB, $27, $B2, $75,
    $09, $83, $2C, $1A, $1B, $6E, $5A, $A0, $52, $3B, $D6, $B3, $29, $E3, $2F, $84,
    $53, $D1, $00, $ED, $20, $FC, $B1, $5B, $6A, $CB, $BE, $39, $4A, $4C, $58, $CF,
    $D0, $EF, $AA, $FB, $43, $4D, $33, $85, $45, $F9, $02, $7F, $50, $3C, $9F, $A8,
    $51, $A3, $40, $8F, $92, $9D, $38, $F5, $BC, $B6, $DA, $21, $10, $FF, $F3, $D2,
    $CD, $0C, $13, $EC, $5F, $97, $44, $17, $C4, $A7, $7E, $3D, $64, $5D, $19, $73,
    $60, $81, $4F, $DC, $22, $2A, $90, $88, $46, $EE, $B8, $14, $DE, $5E, $0B, $DB,
    $E0, $32, $3A, $0A, $49, $06, $24, $5C, $C2, $D3, $AC, $62, $91, $95, $E4, $79,
    $E7, $C8, $37, $6D, $8D, $D5, $4E, $A9, $6C, $56, $F4, $EA, $65, $7A, $AE, $08,
    $BA, $78, $25, $2E, $1C, $A6, $B4, $C6, $E8, $DD, $74, $1F, $4B, $BD, $8B, $8A,
    $70, $3E, $B5, $66, $48, $03, $F6, $0E, $61, $35, $57, $B9, $86, $C1, $1D, $9E,
    $E1, $F8, $98, $11, $69, $D9, $8E, $94, $9B, $1E, $87, $E9, $CE, $55, $28, $DF,
    $8C, $A1, $89, $0D, $BF, $E6, $42, $68, $41, $99, $2D, $0F, $B0, $54, $BB, $16);

  InverseSBox: array[0..255] of Byte = (
    $52, $09, $6A, $D5, $30, $36, $A5, $38, $BF, $40, $A3, $9E, $81, $F3, $D7, $FB,
    $7C, $E3, $39, $82, $9B, $2F, $FF, $87, $34, $8E, $43, $44, $C4, $DE, $E9, $CB,
    $54, $7B, $94, $32, $A6, $C2, $23, $3D, $EE, $4C, $95, $0B, $42, $FA, $C3, $4E,
    $08, $2E, $A1, $66, $28, $D9, $24, $B2, $76, $5B, $A2, $49, $6D, $8B, $D1, $25,
    $72, $F8, $F6, $64, $86, $68, $98, $16, $D4, $A4, $5C, $CC, $5D, $65, $B6, $92,
    $6C, $70, $48, $50, $FD, $ED, $B9, $DA, $5E, $15, $46, $57, $A7, $8D, $9D, $84,
    $90, $D8, $AB, $00, $8C, $BC, $D3, $0A, $F7, $E4, $58, $05, $B8, $B3, $45, $06,
    $D0, $2C, $1E, $8F, $CA, $3F, $0F, $02, $C1, $AF, $BD, $03, $01, $13, $8A, $6B,
    $3A, $91, $11, $41, $4F, $67, $DC, $EA, $97, $F2, $CF, $CE, $F0, $B4, $E6, $73,
    $96, $AC, $74, $22, $E7, $AD, $35, $85, $E2, $F9, $37, $E8, $1C, $75, $DF, $6E,
    $47, $F1, $1A, $71, $1D, $29, $C5, $89, $6F, $B7, $62, $0E, $AA, $18, $BE, $1B,
    $FC, $56, $3E, $4B, $C6, $D2, $79, $20, $9A, $DB, $C0, $FE, $78, $CD, $5A, $F4,
    $1F, $DD, $A8, $33, $88, $07, $C7, $31, $B1, $12, $10, $59, $27, $80, $EC, $5F,
    $60, $51, $7F, $A9, $19, $B5, $4A, $0D, $2D, $E5, $7A, $9F, $93, $C9, $9C, $EF,
    $A0, $E0, $3B, $4D, $AE, $2A, $F5, $B0, $C8, $EB, $BB, $3C, $83, $53, $99, $61,
    $17, $2B, $04, $7E, $BA, $77, $D6, $26, $E1, $69, $14, $63, $55, $21, $0C, $7D);

  RoundConstants: array[1..10] of Byte = ($01, $02, $04, $08, $10, $20, $40, $80, $1B, $36);

  MixColumnsMatrix: TAESCipher.TAESMatrix = (
    (2, 3, 1, 1),
    (1, 2, 3, 1),
    (1, 1, 2, 3),
    (3, 1, 1, 2));

  InverseMixColumnsMatrix: TAESCipher.TAESMatrix = (
    (14, 11, 13, 9),
    (9, 14, 11, 13),
    (13, 9, 14, 11),
    (11, 13, 9, 14));

  InvalidKeyLengthMessage = 'AES key must be 16, 24 or 32 bytes, got %d';
  InvalidBlockLengthMessage = 'AES block must be 16 bytes, got %d';
  InvalidIVLengthMessage = 'AES initialization vector must be 16 bytes, got %d';
  InvalidDataLengthMessage = 'AES data without padding must be a multiple of 16 bytes, got %d';

{ TAESCipher }

constructor TAESCipher.Create(const Key: TBytes);
begin
  inherited Create;

  GuardKey(Key);
  ExpandKey(Key);
end;

function TAESCipher.EncryptBlock(const Block: TBytes): TBytes;
begin
  GuardBlock(Block);

  SetLength(Result, BlockSize);
  StoreState(EncryptState(LoadState(Block, 0)), Result, 0);
end;

function TAESCipher.DecryptBlock(const Block: TBytes): TBytes;
begin
  GuardBlock(Block);

  SetLength(Result, BlockSize);
  StoreState(DecryptState(LoadState(Block, 0)), Result, 0);
end;

function TAESCipher.DecryptCbc(const IV, Data: TBytes; const RemovePadding: Boolean): TBytes;
begin
  var WasLenient: Boolean;
  Result := DecryptCbc(IV, Data, RemovePadding, WasLenient);
end;

function TAESCipher.DecryptCbc(const IV, Data: TBytes; const RemovePadding: Boolean; out WasLenient: Boolean): TBytes;
begin
  GuardIV(IV);

  const BlockCount = Length(Data) div BlockSize;
  WasLenient := ((Length(Data) mod BlockSize) <> 0);
  Result := DecryptBlocksCbc(IV, Data, BlockCount);

  const ShouldCheckPadding = (RemovePadding and (Length(Result) > 0));
  if ShouldCheckPadding then
  begin
    var PaddingLength: Integer;
    if TryGetPaddingLength(Result, PaddingLength) then
    begin
      SetLength(Result, Length(Result) - PaddingLength);
    end
    else
    begin
      WasLenient := True;
    end;
  end;
end;

function TAESCipher.EncryptCbcNoPadding(const IV, Data: TBytes): TBytes;
begin
  GuardIV(IV);
  GuardWholeBlocks(Data);

  SetLength(Result, Length(Data));
  var Chain := LoadState(IV, 0);
  for var BlockIndex := 0 to (Length(Data) div BlockSize) - 1 do
  begin
    const Plain = LoadState(Data, BlockIndex * BlockSize);
    Chain := EncryptState(XorStates(Plain, Chain));
    StoreState(Chain, Result, BlockIndex * BlockSize);
  end;
end;

function TAESCipher.DecryptEcbNoPadding(const Data: TBytes): TBytes;
begin
  GuardWholeBlocks(Data);

  SetLength(Result, Length(Data));
  for var BlockIndex := 0 to (Length(Data) div BlockSize) - 1 do
  begin
    const Offset = BlockIndex * BlockSize;
    StoreState(DecryptState(LoadState(Data, Offset)), Result, Offset);
  end;
end;

function TAESCipher.DecryptBlocksCbc(const IV, Data: TBytes; const BlockCount: Integer): TBytes;
begin
  SetLength(Result, BlockCount * BlockSize);
  var Chain := LoadState(IV, 0);
  for var BlockIndex := 0 to BlockCount - 1 do
  begin
    const Offset = BlockIndex * BlockSize;
    const Encrypted = LoadState(Data, Offset);
    StoreState(XorStates(DecryptState(Encrypted), Chain), Result, Offset);
    Chain := Encrypted;
  end;
end;

function TAESCipher.EncryptState(const State: TAESState): TAESState;
begin
  Result := AddRoundKey(State, 0);
  for var Round := 1 to FRoundCount - 1 do
  begin
    Result := SubstituteBytes(Result, SBox);
    Result := ShiftRows(Result);
    Result := MixColumns(Result, MixColumnsMatrix);
    Result := AddRoundKey(Result, Round);
  end;

  Result := SubstituteBytes(Result, SBox);
  Result := ShiftRows(Result);
  Result := AddRoundKey(Result, FRoundCount);
end;

function TAESCipher.DecryptState(const State: TAESState): TAESState;
begin
  Result := AddRoundKey(State, FRoundCount);
  for var Round := FRoundCount - 1 downto 1 do
  begin
    Result := InverseShiftRows(Result);
    Result := SubstituteBytes(Result, InverseSBox);
    Result := AddRoundKey(Result, Round);
    Result := MixColumns(Result, InverseMixColumnsMatrix);
  end;

  Result := InverseShiftRows(Result);
  Result := SubstituteBytes(Result, InverseSBox);
  Result := AddRoundKey(Result, 0);
end;

function TAESCipher.AddRoundKey(const State: TAESState; const Round: Integer): TAESState;
begin
  for var Index := 0 to BlockSize - 1 do
  begin
    Result[Index] := State[Index] xor FRoundKeys[(Round * BlockSize) + Index];
  end;
end;

procedure TAESCipher.ExpandKey(const Key: TBytes);
begin
  const KeyWordCount = Length(Key) div WordSize;
  FRoundCount := KeyWordCount + EnlargedKeySchedule;
  const TotalWordCount = ColumnCount * (FRoundCount + 1);
  SetLength(FRoundKeys, TotalWordCount * WordSize);

  for var Index := 0 to Length(Key) - 1 do
  begin
    FRoundKeys[Index] := Key[Index];
  end;

  for var WordIndex := KeyWordCount to TotalWordCount - 1 do
  begin
    SetKeyWord(WordIndex, NextKeyWord(WordIndex, KeyWordCount));
  end;
end;

function TAESCipher.NextKeyWord(const WordIndex, KeyWordCount: Integer): TAESWord;
begin
  var Word := GetKeyWord(WordIndex - 1);
  const StartsKeyBlock = ((WordIndex mod KeyWordCount) = 0);
  const IsExtraSubstitution = ((KeyWordCount > 6) and ((WordIndex mod KeyWordCount) = 4));
  if StartsKeyBlock then
  begin
    Word := SubstituteWord(RotateWord(Word));
    Word[0] := Word[0] xor RoundConstants[WordIndex div KeyWordCount];
  end
  else if IsExtraSubstitution then
  begin
    Word := SubstituteWord(Word);
  end;

  const EarlierWord = GetKeyWord(WordIndex - KeyWordCount);
  for var Index := 0 to WordSize - 1 do
  begin
    Result[Index] := EarlierWord[Index] xor Word[Index];
  end;
end;

function TAESCipher.GetKeyWord(const WordIndex: Integer): TAESWord;
begin
  for var Index := 0 to WordSize - 1 do
  begin
    Result[Index] := FRoundKeys[(WordIndex * WordSize) + Index];
  end;
end;

procedure TAESCipher.SetKeyWord(const WordIndex: Integer; const Word: TAESWord);
begin
  for var Index := 0 to WordSize - 1 do
  begin
    FRoundKeys[(WordIndex * WordSize) + Index] := Word[Index];
  end;
end;

class function TAESCipher.SubstituteWord(const Word: TAESWord): TAESWord;
begin
  for var Index := 0 to WordSize - 1 do
  begin
    Result[Index] := SBox[Word[Index]];
  end;
end;

class function TAESCipher.RotateWord(const Word: TAESWord): TAESWord;
begin
  for var Index := 0 to WordSize - 1 do
  begin
    Result[Index] := Word[(Index + 1) mod WordSize];
  end;
end;

class function TAESCipher.SubstituteBytes(const State: TAESState; const Table: array of Byte): TAESState;
begin
  for var Index := 0 to BlockSize - 1 do
  begin
    Result[Index] := Table[State[Index]];
  end;
end;

// The state is stored column by column: the byte at row Row of column Column is State[Row + (4 * Column)].
// Row Row moves left by Row columns.
class function TAESCipher.ShiftRows(const State: TAESState): TAESState;
begin
  for var Row := 0 to 3 do
  begin
    for var Column := 0 to ColumnCount - 1 do
    begin
      const SourceColumn = (Column + Row) mod ColumnCount;
      Result[Row + (WordSize * Column)] := State[Row + (WordSize * SourceColumn)];
    end;
  end;
end;

class function TAESCipher.InverseShiftRows(const State: TAESState): TAESState;
begin
  for var Row := 0 to 3 do
  begin
    for var Column := 0 to ColumnCount - 1 do
    begin
      const TargetColumn = (Column + Row) mod ColumnCount;
      Result[Row + (WordSize * TargetColumn)] := State[Row + (WordSize * Column)];
    end;
  end;
end;

class function TAESCipher.MixColumns(const State: TAESState; const Matrix: TAESMatrix): TAESState;
begin
  for var Column := 0 to ColumnCount - 1 do
  begin
    for var Row := 0 to 3 do
    begin
      var Sum: Byte := 0;
      for var Term := 0 to 3 do
      begin
        Sum := Sum xor Multiply(Matrix[Row, Term], State[Term + (WordSize * Column)]);
      end;
      Result[Row + (WordSize * Column)] := Sum;
    end;
  end;
end;

// Multiplication in GF(2^8) modulo x^8 + x^4 + x^3 + x + 1
class function TAESCipher.Multiply(const Left, Right: Byte): Byte;
begin
  var Factor := Left;
  var Remaining := Right;
  Result := 0;
  while Remaining <> 0 do
  begin
    if (Remaining and 1) <> 0 then
    begin
      Result := Result xor Factor;
    end;

    const OverflowsField = ((Factor and $80) <> 0);
    Factor := Byte(Factor shl 1);
    if OverflowsField then
    begin
      Factor := Factor xor $1B;
    end;
    Remaining := Remaining shr 1;
  end;
end;

class function TAESCipher.XorStates(const Left, Right: TAESState): TAESState;
begin
  for var Index := 0 to BlockSize - 1 do
  begin
    Result[Index] := Left[Index] xor Right[Index];
  end;
end;

class function TAESCipher.LoadState(const Data: TBytes; const Offset: Integer): TAESState;
begin
  for var Index := 0 to BlockSize - 1 do
  begin
    Result[Index] := Data[Offset + Index];
  end;
end;

class procedure TAESCipher.StoreState(const State: TAESState; const Data: TBytes; const Offset: Integer);
begin
  for var Index := 0 to BlockSize - 1 do
  begin
    Data[Offset + Index] := State[Index];
  end;
end;

class function TAESCipher.TryGetPaddingLength(const Data: TBytes; out PaddingLength: Integer): Boolean;
begin
  PaddingLength := 0;
  const DataLength = Length(Data);
  const LastByte = Data[DataLength - 1];
  const IsPaddingLengthPlausible = ((LastByte >= 1) and (LastByte <= MaxPaddingLength) and (LastByte <= DataLength));
  if not IsPaddingLengthPlausible then
  begin
    Exit(False);
  end;

  for var Index := DataLength - LastByte to DataLength - 1 do
  begin
    if Data[Index] <> LastByte then
    begin
      Exit(False);
    end;
  end;

  PaddingLength := LastByte;
  Result := True;
end;

class procedure TAESCipher.GuardKey(const Key: TBytes);
begin
  const KeyLength = Length(Key);
  const IsValidKeyLength = ((KeyLength = 16) or (KeyLength = 24) or (KeyLength = 32));
  if not IsValidKeyLength then
  begin
    raise EArgumentException.CreateFmt(InvalidKeyLengthMessage, [KeyLength]);
  end;
end;

class procedure TAESCipher.GuardBlock(const Block: TBytes);
begin
  if Length(Block) <> BlockSize then
  begin
    raise EArgumentException.CreateFmt(InvalidBlockLengthMessage, [Length(Block)]);
  end;
end;

class procedure TAESCipher.GuardIV(const IV: TBytes);
begin
  if Length(IV) <> BlockSize then
  begin
    raise EArgumentException.CreateFmt(InvalidIVLengthMessage, [Length(IV)]);
  end;
end;

class procedure TAESCipher.GuardWholeBlocks(const Data: TBytes);
begin
  if (Length(Data) mod BlockSize) <> 0 then
  begin
    raise EArgumentException.CreateFmt(InvalidDataLengthMessage, [Length(Data)]);
  end;
end;

end.
