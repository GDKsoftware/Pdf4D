// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/cff/Type1CharStringParser.java, Type2CharStringParser.java,
// Type2CharString.java and the width handling of Type1CharString.java (3.0.8)
unit Pdf4D.FontBox.CharStringReaders;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.Log;

const
  // An operator is a b0 below 32; the two byte operators (b0 = 12) get EscapeBase + b1
  EscapeBase = 256;

  CodeHStem = 1;
  CodeVStem = 3;
  CodeVMoveTo = 4;
  CodeRLineTo = 5;
  CodeHLineTo = 6;
  CodeVLineTo = 7;
  CodeRRCurveTo = 8;
  CodeCallSubr = 10;
  CodeReturn = 11;
  CodeEscape = 12;
  CodeHSBW = 13;
  CodeEndChar = 14;
  CodeHStemHM = 18;
  CodeHintMask = 19;
  CodeCntrMask = 20;
  CodeRMoveTo = 21;
  CodeHMoveTo = 22;
  CodeVStemHM = 23;
  CodeRCurveLine = 24;
  CodeRLineCurve = 25;
  CodeVVCurveTo = 26;
  CodeShortInt = 28;
  CodeCallGSubr = 29;
  CodeVHCurveTo = 30;
  CodeHVCurveTo = 31;
  CodeSBW = EscapeBase + 7;
  CodeDiv = EscapeBase + 12;
  CodeCallOtherSubr = EscapeBase + 16;
  CodePop = EscapeBase + 17;
  CodeHFlex = EscapeBase + 34;
  CodeFlex = EscapeBase + 35;
  CodeHFlex1 = EscapeBase + 36;
  CodeFlex1 = EscapeBase + 37;

  OtherSubrEndFlex = 0;
  OtherSubrBeginFlex = 1;
  OtherSubrHintReplacement = 3;

  FlexOperandCount = 12;
  Flex1OperandCount = 11;
  HFlexOperandCount = 7;
  HFlex1OperandCount = 9;

  // The bias of the subroutine numbers by the size of the INDEX (Type 2 charstrings, technical note 5177)
  SmallIndexLimit = 1240;
  MediumIndexLimit = 33900;
  SmallBias = 107;
  MediumBias = 1131;
  LargeBias = 32768;

type
  TCharStringItem = record
    IsCommand: Boolean;
    IsInteger: Boolean;
    Value: Double;
    Code: Integer;
  end;

  // The bytes of one charstring or subroutine, read with explicit byte order. A read beyond the end raises.
  TCharStringInput = class
  private
    FBytes: TBytes;
    FPosition: Integer;

  public
    constructor Create(const Bytes: TBytes);

    function HasRemaining: Boolean;
    function ReadByte: Integer;
    function PeekByte(const Offset: Integer): Integer;
    function ReadShort: Integer;
    function ReadUnsignedShort: Integer;
    function ReadInt: Integer;
  end;

  // What the Type 1 and the Type 2 interpreter share: the sequence of numbers and operators that the parser builds
  TCharStringReader = class abstract
  private
    FItems: TList<TCharStringItem>;
    FOperations: Integer;
    FLog: TPdfLog;

  protected
    FIsDone: Boolean;

    procedure CountOperation;
    procedure AddNumber(const Value: Double; const IsInteger: Boolean);
    procedure AddCommand(const Code: Integer);
    function PopItem: TCharStringItem;
    function PopInteger: Integer;
    procedure RemoveTrailingReturn;
    procedure Warn(const Fmt: string; const Args: array of const);

  public
    constructor Create(const Log: TPdfLog);
    destructor Destroy; override;

    // Java's float division, which does not raise for a divisor of zero
    class function DivideSingles(const Dividend, Divisor: Single): Single; static;

    // The numbers and operators that the parser has read so far, also when it stopped with an exception
    property Items: TList<TCharStringItem> read FItems;
  end;

  TType2Reader = class(TCharStringReader)
  private
    FGlobalSubrs: TArray<TBytes>;
    FLocalSubrs: TArray<TBytes>;
    FDefaultWidthX: Integer;
    FNominalWidthX: Integer;
    // The operands the Type 2 operator conversion has at hand
    FPending: TList<Double>;
    // True when the conversion already gave an operator, so that no width is added any more
    FHasEmittedOperator: Boolean;
    // False reads up to the operator that gives the width; True reads the whole charstring, with the mask bytes skipped
    FIsWholeCharString: Boolean;
    FHStemCount: Integer;
    FVStemCount: Integer;

    class function IsStackClearing(const Code: Integer): Boolean; static;
    class function ReadNumber(const B0: Integer; const Input: TCharStringInput): TCharStringItem; static;
    class function SubrNumber(const Operand, SubrCount: Integer): Int64; static;

    procedure ParseSequence(const Bytes: TBytes; const Depth: Integer);
    procedure ParseToken(const Input: TCharStringInput; const Depth: Integer);
    procedure ParseCommand(const B0: Integer; const Input: TCharStringInput);
    procedure ProcessCallSubr(const Subrs: TArray<TBytes>; const Depth: Integer);
    function CountTrailingNumbers: Integer;
    procedure CountStems(const Code: Integer);
    procedure SkipMask(const Input: TCharStringInput);

    function DetermineWidth: Integer;
    function IsCollapsibleDivision(const Index: Integer): Boolean;
    procedure CollapseDivision;
    procedure AddPendingOperand(const Value: Double);
    function WidthAtStackClearing(const Code: Integer): Integer;
    function StackClearingNeedsWidth(const Code: Integer): Boolean;
    procedure ConvertOtherCommand(const Code: Integer);
    function EmitsOperator(const Code: Integer): Boolean;

  public
    constructor Create(const GlobalSubrs, LocalSubrs: TArray<TBytes>; const DefaultWidthX, NominalWidthX: Integer;
                       const Log: TPdfLog);
    destructor Destroy; override;

    function ReadWidth(const CharString: TBytes): Integer;
    // Reads the whole charstring into Items. The parser raises EPdfParseException for a damaged charstring; Items then holds
    // what was read before the damage.
    procedure ReadAll(const CharString: TBytes);
  end;

  TType1Reader = class(TCharStringReader)
  private
    FSubrs: TArray<TBytes>;
    // False stops at the first hsbw or sbw; True reads the whole charstring
    FIsWholeCharString: Boolean;

    class function ReadNumber(const B0: Integer; const Input: TCharStringInput): Integer; static;

    procedure ParseSequence(const Bytes: TBytes; const Depth: Integer);
    procedure ParseToken(const Input: TCharStringInput; const Depth: Integer);
    procedure ProcessCallSubr(const Depth: Integer);
    procedure RemoveTrailingIntegers;
    procedure ProcessCallOtherSubr(const Input: TCharStringInput);
    procedure ApplyOtherSubr(const OtherSubrNumber, ArgumentCount: Integer; const Results: TList<Integer>);
    procedure PushPops(const Input: TCharStringInput; const Results: TList<Integer>);
    function RemoveInteger: Integer;

    function WidthOfFirstSidebearing(out Width: Integer): Boolean;

  public
    constructor Create(const Subrs: TArray<TBytes>; const Log: TPdfLog);

    function TryReadWidth(const CharString: TBytes; out Width: Integer): Boolean;
    // Reads the whole charstring into Items, with the subroutines and callothersubr expanded. Raises EPdfParseException for a
    // damaged charstring; Items then holds what was read before the damage.
    procedure ReadAll(const CharString: TBytes);
  end;

implementation

uses
  System.Math,
  Pdf4D.Common.Defines,
  Pdf4D.FontBox.Cff.Font,
  Pdf4D.FontBox.CharStringWidth;

const
  TruncatedTokenMessage = 'The charstring ends in the middle of a token';
  IntegerOperandMessage = 'The charstring expects an integer operand';
  TooManyOperandsMessage = 'The charstring has more than %d operands for one operator';
  SubrsTooDeepMessage = 'Subroutines are nested deeper than %d';

{ TCharStringInput }

constructor TCharStringInput.Create(const Bytes: TBytes);
begin
  inherited Create;
  FBytes := Bytes;
end;

function TCharStringInput.HasRemaining: Boolean;
begin
  Result := (FPosition < Length(FBytes));
end;

function TCharStringInput.ReadByte: Integer;
begin
  if not HasRemaining then
  begin
    raise EPdfParseException.Create(TruncatedTokenMessage);
  end;
  Result := FBytes[FPosition];
  Inc(FPosition);
end;

function TCharStringInput.PeekByte(const Offset: Integer): Integer;
begin
  const IsBeyondEnd = ((Offset < 0) or (Offset >= Length(FBytes) - FPosition));
  if IsBeyondEnd then
  begin
    raise EPdfParseException.Create(TruncatedTokenMessage);
  end;
  Result := FBytes[FPosition + Offset];
end;

function TCharStringInput.ReadUnsignedShort: Integer;
begin
  const HighByte = ReadByte;
  const LowByte = ReadByte;
  Result := (HighByte shl 8) or LowByte;
end;

function TCharStringInput.ReadShort: Integer;
begin
  Result := ReadUnsignedShort;
  if Result > High(SmallInt) then
  begin
    Result := Result - $10000;
  end;
end;

function TCharStringInput.ReadInt: Integer;
begin
  const HighWord = ReadUnsignedShort;
  const LowWord = ReadUnsignedShort;
  Result := Integer((Cardinal(HighWord) shl 16) or Cardinal(LowWord));
end;

{ TCharStringReader }

constructor TCharStringReader.Create(const Log: TPdfLog);
begin
  inherited Create;
  FItems := TList<TCharStringItem>.Create;
  FLog := Log;
end;

destructor TCharStringReader.Destroy;
begin
  FItems.Free;
  inherited;
end;

procedure TCharStringReader.CountOperation;
begin
  Inc(FOperations);
  if FOperations > MaxOperations then
  begin
    raise EPdfParseException.CreateFmt('The charstring has more than %d operations', [MaxOperations]);
  end;
end;

procedure TCharStringReader.AddNumber(const Value: Double; const IsInteger: Boolean);
begin
  var Item := Default(TCharStringItem);
  Item.Value := Value;
  Item.IsInteger := IsInteger;
  FItems.Add(Item);
end;

procedure TCharStringReader.AddCommand(const Code: Integer);
begin
  var Item := Default(TCharStringItem);
  Item.IsCommand := True;
  Item.Code := Code;
  FItems.Add(Item);
end;

function TCharStringReader.PopItem: TCharStringItem;
begin
  if FItems.Count = 0 then
  begin
    raise EPdfParseException.Create('The charstring takes an operand that is not there');
  end;
  Result := FItems.Last;
  FItems.Delete(FItems.Count - 1);
end;

function TCharStringReader.PopInteger: Integer;
begin
  const Item = PopItem;
  const IsIntegerNumber = ((not Item.IsCommand) and Item.IsInteger);
  if not IsIntegerNumber then
  begin
    raise EPdfParseException.Create(IntegerOperandMessage);
  end;
  Result := TCFFNumber.ToInt(Item.Value);
end;

// A subroutine ends with return, which does not belong to the sequence of the caller
procedure TCharStringReader.RemoveTrailingReturn;
begin
  if FItems.Count = 0 then
  begin
    raise EPdfParseException.Create('The subroutine of the charstring is empty');
  end;
  const Last = FItems.Last;
  const IsReturn = (Last.IsCommand and (Last.Code = CodeReturn));
  if IsReturn then
  begin
    FItems.Delete(FItems.Count - 1);
  end;
end;

procedure TCharStringReader.Warn(const Fmt: string; const Args: array of const);
begin
  if Assigned(FLog) then
  begin
    FLog.Warning(Fmt, Args);
  end;
end;

// Java's float division, which does not raise for a divisor of zero
class function TCharStringReader.DivideSingles(const Dividend, Divisor: Single): Single;
begin
  if Divisor <> 0 then
  begin
    Exit(Dividend / Divisor);
  end;
  if IsNaN(Dividend) or (Dividend = 0) then
  begin
    Exit(Single.NaN);
  end;
  if Dividend > 0 then
  begin
    Exit(Single.PositiveInfinity);
  end;
  Result := Single.NegativeInfinity;
end;

{ TType2Reader }

constructor TType2Reader.Create(const GlobalSubrs, LocalSubrs: TArray<TBytes>; const DefaultWidthX, NominalWidthX: Integer;
                                     const Log: TPdfLog);
begin
  inherited Create(Log);
  FGlobalSubrs := GlobalSubrs;
  FLocalSubrs := LocalSubrs;
  FDefaultWidthX := DefaultWidthX;
  FNominalWidthX := NominalWidthX;
  FPending := TList<Double>.Create;
end;

destructor TType2Reader.Destroy;
begin
  FPending.Free;
  inherited;
end;

function TType2Reader.ReadWidth(const CharString: TBytes): Integer;
begin
  ParseSequence(CharString, 0);
  Result := DetermineWidth;
end;

procedure TType2Reader.ReadAll(const CharString: TBytes);
begin
  FIsWholeCharString := True;
  ParseSequence(CharString, 0);
end;

// The operators that take the width off the stack when they come first (clearStack of Type2CharString)
class function TType2Reader.IsStackClearing(const Code: Integer): Boolean;
begin
  case Code of
    CodeHStem, CodeVStem, CodeHStemHM, CodeVStemHM, CodeHintMask, CodeCntrMask,
    CodeHMoveTo, CodeVMoveTo, CodeRMoveTo, CodeEndChar:
      Result := True;
  else
    Result := False;
  end;
end;

class function TType2Reader.SubrNumber(const Operand, SubrCount: Integer): Int64;
begin
  if SubrCount < SmallIndexLimit then
  begin
    Exit(Int64(SmallBias) + Operand);
  end;
  if SubrCount < MediumIndexLimit then
  begin
    Exit(Int64(MediumBias) + Operand);
  end;
  Result := Int64(LargeBias) + Operand;
end;

class function TType2Reader.ReadNumber(const B0: Integer; const Input: TCharStringInput): TCharStringItem;
begin
  Result := Default(TCharStringItem);
  Result.IsInteger := True;
  if B0 = CodeShortInt then
  begin
    Result.Value := Input.ReadShort;
  end
  else if (B0 >= 32) and (B0 <= 246) then
  begin
    Result.Value := B0 - 139;
  end
  else if (B0 >= 247) and (B0 <= 250) then
  begin
    Result.Value := (B0 - 247) * 256 + Input.ReadByte + 108;
  end
  else if (B0 >= 251) and (B0 <= 254) then
  begin
    Result.Value := -(B0 - 251) * 256 - Input.ReadByte - 108;
  end
  else
  begin
    // 16.16 fixed point; PDFBox divides the fraction by 65535
    const WholePart = Input.ReadShort;
    const Fraction = Input.ReadUnsignedShort / 65535;
    Result.Value := WholePart + Fraction;
    Result.IsInteger := False;
  end;
end;

procedure TType2Reader.ParseSequence(const Bytes: TBytes; const Depth: Integer);
begin
  const Input = TCharStringInput.Create(Bytes);
  try
    while Input.HasRemaining and not FIsDone do
    begin
      CountOperation;
      ParseToken(Input, Depth);
    end;
  finally
    Input.Free;
  end;
end;

procedure TType2Reader.ParseToken(const Input: TCharStringInput; const Depth: Integer);
begin
  const B0 = Input.ReadByte;
  if B0 = CodeCallSubr then
  begin
    ProcessCallSubr(FLocalSubrs, Depth);
  end
  else if B0 = CodeCallGSubr then
  begin
    ProcessCallSubr(FGlobalSubrs, Depth);
  end
  else
  begin
    const IsNumber = ((B0 = CodeShortInt) or (B0 >= 32));
    if IsNumber then
    begin
      const Number = ReadNumber(B0, Input);
      AddNumber(Number.Value, Number.IsInteger);
    end
    else
    begin
      ParseCommand(B0, Input);
    end;
  end;
end;

// The width is known at the first operator that clears the stack, so the interpretation ends there. The mask bytes of
// hintmask and cntrmask follow that operator and are not needed for the width.
procedure TType2Reader.ParseCommand(const B0: Integer; const Input: TCharStringInput);
begin
  var Code := B0;
  if B0 = CodeEscape then
  begin
    Code := EscapeBase + Input.ReadByte;
  end;

  if FIsWholeCharString then
  begin
    CountStems(Code);
    const HasMask = ((Code = CodeHintMask) or (Code = CodeCntrMask));
    if HasMask then
    begin
      SkipMask(Input);
    end;
  end;

  AddCommand(Code);
  if (not FIsWholeCharString) and IsStackClearing(Code) then
  begin
    FIsDone := True;
  end;
end;

function TType2Reader.CountTrailingNumbers: Integer;
begin
  Result := 0;
  for var Index := Items.Count - 1 downto 0 do
  begin
    if Items[Index].IsCommand then
    begin
      Exit;
    end;
    Inc(Result);
  end;
end;

// The stems are counted to know how long the mask of hintmask and cntrmask is. The numbers before hintmask are vstem hints.
procedure TType2Reader.CountStems(const Code: Integer);
begin
  case Code of
    CodeHStem, CodeHStemHM:
      Inc(FHStemCount, CountTrailingNumbers div 2);
    CodeVStem, CodeVStemHM, CodeHintMask, CodeCntrMask:
      Inc(FVStemCount, CountTrailingNumbers div 2);
  end;
end;

procedure TType2Reader.SkipMask(const Input: TCharStringInput);
begin
  const MaskLength = (FHStemCount + FVStemCount + 7) div 8;
  for var Index := 1 to MaskLength do
  begin
    Input.ReadByte;
  end;
end;

procedure TType2Reader.ProcessCallSubr(const Subrs: TArray<TBytes>; const Depth: Integer);
begin
  // PDFBox does nothing when there are no subroutines, and leaves the operand where it is
  if Length(Subrs) = 0 then
  begin
    Exit;
  end;
  if Depth >= MaxSubrDepth then
  begin
    raise EPdfParseException.CreateFmt(SubrsTooDeepMessage, [MaxSubrDepth]);
  end;

  const Number = SubrNumber(PopInteger, Length(Subrs));
  const IsInRange = ((Number >= 0) and (Number < Length(Subrs)));
  if not IsInRange then
  begin
    raise EPdfParseException.CreateFmt('The subroutine number %d is outside the %d subroutines', [Number, Length(Subrs)]);
  end;

  ParseSequence(Subrs[Number], Depth + 1);
  if not FIsDone then
  begin
    RemoveTrailingReturn;
  end;
end;

// Type2CharString.convertType1ToType2, as far as it decides the width: the first operator that clears the stack adds the
// width, unless an operator was converted before it. Without such an operator the width is 0.
function TType2Reader.DetermineWidth: Integer;
begin
  FPending.Clear;
  FHasEmittedOperator := False;
  for var Index := 0 to Items.Count - 1 do
  begin
    const Item = Items[Index];
    if not Item.IsCommand then
    begin
      AddPendingOperand(Item.Value);
    end
    else if IsCollapsibleDivision(Index) then
    begin
      CollapseDivision;
    end
    else if IsStackClearing(Item.Code) then
    begin
      Exit(WidthAtStackClearing(Item.Code));
    end
    else
    begin
      ConvertOtherCommand(Item.Code);
    end;
  end;
  Result := 0;
end;

// PDFBOX-5987: "num denom div" is replaced by its result. PDFBox looks at the two items before the operator in the sequence
// as it was parsed, so a second div after a collapsed one is not collapsed.
function TType2Reader.IsCollapsibleDivision(const Index: Integer): Boolean;
begin
  Result := ((Items[Index].Code = CodeDiv) and (Index >= 2) and (not Items[Index - 2].IsCommand) and
             (not Items[Index - 1].IsCommand) and (FPending.Count >= 2));
end;

procedure TType2Reader.CollapseDivision;
begin
  const Divisor = Single(FPending[FPending.Count - 1]);
  const Dividend = Single(FPending[FPending.Count - 2]);
  FPending.Delete(FPending.Count - 1);
  FPending.Delete(FPending.Count - 1);
  FPending.Add(DivideSingles(Dividend, Divisor));
end;

procedure TType2Reader.AddPendingOperand(const Value: Double);
begin
  if FPending.Count >= MaxOperands then
  begin
    raise EPdfParseException.CreateFmt(TooManyOperandsMessage, [MaxOperands]);
  end;
  FPending.Add(Value);
end;

function TType2Reader.StackClearingNeedsWidth(const Code: Integer): Boolean;
begin
  const Count = FPending.Count;
  case Code of
    CodeHStem, CodeVStem, CodeHStemHM, CodeVStemHM, CodeHintMask, CodeCntrMask:
      Result := Odd(Count);
    CodeHMoveTo, CodeVMoveTo:
      Result := (Count > 1);
    CodeRMoveTo:
      Result := (Count > 2);
    CodeEndChar:
      Result := ((Count = 5) or (Count = 1));
  else
    Result := False;
  end;
end;

// The width is the first operand plus NominalWidthX, or DefaultWidthX. Both go through Single, as in Java.
function TType2Reader.WidthAtStackClearing(const Code: Integer): Integer;
begin
  if FHasEmittedOperator then
  begin
    Exit(0);
  end;

  if StackClearingNeedsWidth(Code) then
  begin
    const FirstOperand = Single(FPending[0]);
    const Nominal = Single(FNominalWidthX);
    const Width = Single(FirstOperand + Nominal);
    Result := TCFFNumber.ToInt(Width);
  end
  else
  begin
    const Default = Single(FDefaultWidthX);
    Result := TCFFNumber.ToInt(Default);
  end;
end;

procedure TType2Reader.ConvertOtherCommand(const Code: Integer);
begin
  if EmitsOperator(Code) then
  begin
    FHasEmittedOperator := True;
  end;
  FPending.Clear;
end;

// Whether the conversion of the operator gives at least one operator of the converted sequence. The flex operators raise in
// PDFBox when they have too few operands.
function TType2Reader.EmitsOperator(const Code: Integer): Boolean;
begin
  const Count = FPending.Count;
  case Code of
    CodeRLineTo, CodeRCurveLine:
      Result := (Count >= 2);
    CodeHLineTo, CodeVLineTo:
      Result := (Count >= 1);
    CodeRRCurveTo, CodeRLineCurve:
      Result := (Count >= 6);
    CodeVVCurveTo, CodeHVCurveTo, CodeVHCurveTo:
      Result := (Count >= 4);
    CodeHFlex:
      Result := (Count >= HFlexOperandCount);
    CodeHFlex1:
      Result := (Count >= HFlex1OperandCount);
    CodeFlex:
      begin
        if Count < FlexOperandCount then
        begin
          raise EPdfParseException.Create('The flex operator has too few operands');
        end;
        Result := True;
      end;
    CodeFlex1:
      begin
        if Count < Flex1OperandCount then
        begin
          raise EPdfParseException.Create('The flex1 operator has too few operands');
        end;
        Result := True;
      end;
  else
    Result := True;
  end;
end;

{ TType1Reader }

constructor TType1Reader.Create(const Subrs: TArray<TBytes>; const Log: TPdfLog);
begin
  inherited Create(Log);
  FSubrs := Subrs;
end;

procedure TType1Reader.ReadAll(const CharString: TBytes);
begin
  FIsWholeCharString := True;
  ParseSequence(CharString, 0);
end;

function TType1Reader.TryReadWidth(const CharString: TBytes; out Width: Integer): Boolean;
begin
  Width := 0;
  ParseSequence(CharString, 0);
  Result := (FIsDone and WidthOfFirstSidebearing(Width));
end;

class function TType1Reader.ReadNumber(const B0: Integer; const Input: TCharStringInput): Integer;
begin
  if B0 <= 246 then
  begin
    Result := B0 - 139;
  end
  else if B0 <= 250 then
  begin
    Result := (B0 - 247) * 256 + Input.ReadByte + 108;
  end
  else if B0 <= 254 then
  begin
    Result := -(B0 - 251) * 256 - Input.ReadByte - 108;
  end
  else
  begin
    Result := Input.ReadInt;
  end;
end;

procedure TType1Reader.ParseSequence(const Bytes: TBytes; const Depth: Integer);
begin
  const Input = TCharStringInput.Create(Bytes);
  try
    while Input.HasRemaining and not FIsDone do
    begin
      CountOperation;
      ParseToken(Input, Depth);
    end;
  finally
    Input.Free;
  end;
end;

procedure TType1Reader.ParseToken(const Input: TCharStringInput; const Depth: Integer);
begin
  const B0 = Input.ReadByte;
  if B0 = CodeCallSubr then
  begin
    ProcessCallSubr(Depth);
  end
  else if (B0 = CodeEscape) and (Input.PeekByte(0) = CodeCallOtherSubr - EscapeBase) then
  begin
    ProcessCallOtherSubr(Input);
  end
  else if B0 < 32 then
  begin
    var Code := B0;
    if B0 = CodeEscape then
    begin
      Code := EscapeBase + Input.ReadByte;
    end;
    AddCommand(Code);
    // The width is known at the first hsbw or sbw
    FIsDone := ((not FIsWholeCharString) and ((Code = CodeHSBW) or (Code = CodeSBW)));
  end
  else
  begin
    AddNumber(ReadNumber(B0, Input), True);
  end;
end;

procedure TType1Reader.ProcessCallSubr(const Depth: Integer);
begin
  const Operand = PopItem;
  const IsIntegerOperand = ((not Operand.IsCommand) and Operand.IsInteger);
  if not IsIntegerOperand then
  begin
    Warn('A parameter for callsubr is ignored, an integer was expected', []);
    Exit;
  end;

  const SubrIndex = TCFFNumber.ToInt(Operand.Value);
  const IsInRange = ((SubrIndex >= 0) and (SubrIndex < Length(FSubrs)));
  if not IsInRange then
  begin
    Warn('callsubr is ignored, operand: %d, subrs: %d', [SubrIndex, Length(FSubrs)]);
    RemoveTrailingIntegers;
    Exit;
  end;

  if Depth >= MaxSubrDepth then
  begin
    raise EPdfParseException.CreateFmt(SubrsTooDeepMessage, [MaxSubrDepth]);
  end;

  ParseSequence(FSubrs[SubrIndex], Depth + 1);
  if not FIsDone then
  begin
    RemoveTrailingReturn;
  end;
end;

// All the parameters of the ignored call go, and there can be more than one
procedure TType1Reader.RemoveTrailingIntegers;
begin
  while (Items.Count > 0) and (not Items.Last.IsCommand) do
  begin
    Items.Delete(Items.Count - 1);
  end;
end;

// callothersubr is expanded in the sequence, as PDFBox does: the flex and hint replacement cases keep their semantics and
// the pops that follow take the results
procedure TType1Reader.ProcessCallOtherSubr(const Input: TCharStringInput);
begin
  Input.ReadByte;
  const OtherSubrNumber = PopInteger;
  const ArgumentCount = PopInteger;

  const Results = TList<Integer>.Create;
  try
    ApplyOtherSubr(OtherSubrNumber, ArgumentCount, Results);
    PushPops(Input, Results);
    if Results.Count > 0 then
    begin
      Warn('A value is left on the PostScript stack', []);
    end;
  finally
    Results.Free;
  end;
end;

procedure TType1Reader.ApplyOtherSubr(const OtherSubrNumber, ArgumentCount: Integer; const Results: TList<Integer>);
begin
  case OtherSubrNumber of
    OtherSubrEndFlex:
      begin
        Results.Add(RemoveInteger);
        Results.Add(RemoveInteger);
        PopItem;
        AddNumber(OtherSubrEndFlex, True);
        AddCommand(CodeCallOtherSubr);
      end;
    OtherSubrBeginFlex:
      begin
        AddNumber(OtherSubrBeginFlex, True);
        AddCommand(CodeCallOtherSubr);
      end;
    OtherSubrHintReplacement:
      begin
        Results.Add(RemoveInteger);
      end;
  else
    for var Argument := 1 to ArgumentCount do
    begin
      CountOperation;
      Results.Add(RemoveInteger);
    end;
  end;
end;

// A pop must follow immediately. PDFBox peeks at the bytes, so a charstring that ends here raises.
procedure TType1Reader.PushPops(const Input: TCharStringInput; const Results: TList<Integer>);
begin
  const PopSecondByte = CodePop - EscapeBase;
  while (Input.PeekByte(0) = CodeEscape) and (Input.PeekByte(1) = PopSecondByte) do
  begin
    CountOperation;
    Input.ReadByte;
    Input.ReadByte;
    if Results.Count = 0 then
    begin
      raise EPdfParseException.Create('A pop has no result of callothersubr');
    end;
    AddNumber(Results.Last, True);
    Results.Delete(Results.Count - 1);
  end;
end;

// PDFBox cannot run div while it unrolls the subroutines, so a div among the arguments is carried out here
function TType1Reader.RemoveInteger: Integer;
begin
  const Item = PopItem;
  if not Item.IsCommand then
  begin
    if not Item.IsInteger then
    begin
      raise EPdfParseException.Create(IntegerOperandMessage);
    end;
    Exit(TCFFNumber.ToInt(Item.Value));
  end;
  if Item.Code <> CodeDiv then
  begin
    raise EPdfParseException.CreateFmt('Unexpected charstring command %d', [Item.Code]);
  end;

  const Divisor = PopInteger;
  const Dividend = PopInteger;
  if Divisor = 0 then
  begin
    raise EPdfParseException.Create('The charstring divides by zero');
  end;
  // Java wraps the one quotient that does not fit an integer
  const IsOverflowingQuotient = ((Dividend = Integer.MinValue) and (Divisor = -1));
  if IsOverflowingQuotient then
  begin
    Exit(Integer.MinValue);
  end;
  Result := Dividend div Divisor;
end;

// Type1CharString.render up to the first hsbw or sbw. The operands are the numbers since the last operator; a div among them
// gives its quotient and keeps the operands.
function TType1Reader.WidthOfFirstSidebearing(out Width: Integer): Boolean;
begin
  Width := 0;
  const Operands = TList<Double>.Create;
  try
    for var Item in Items do
    begin
      if not Item.IsCommand then
      begin
        if Operands.Count >= MaxOperands then
        begin
          raise EPdfParseException.CreateFmt(TooManyOperandsMessage, [MaxOperands]);
        end;
        Operands.Add(Item.Value);
      end
      else if (Item.Code = CodeDiv) and (Operands.Count >= 2) then
      begin
        const Divisor = Single(Operands.Last);
        Operands.Delete(Operands.Count - 1);
        const Dividend = Single(Operands.Last);
        Operands.Delete(Operands.Count - 1);
        Operands.Add(DivideSingles(Dividend, Divisor));
      end
      else if (Item.Code = CodeHSBW) or (Item.Code = CodeSBW) then
      begin
        // PDFBox reads the width at a fixed place in the operands: 2nd for hsbw, 3rd for sbw
        var WidthPosition := 1;
        if Item.Code = CodeSBW then
        begin
          WidthPosition := 2;
        end;
        if Operands.Count > WidthPosition then
        begin
          Width := TCFFNumber.ToInt(Operands[WidthPosition]);
        end;
        Exit(True);
      end
      else
      begin
        Operands.Clear;
      end;
    end;
    Result := False;
  finally
    Operands.Free;
  end;
end;
end.
