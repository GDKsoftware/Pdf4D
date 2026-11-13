// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
unit Pdf4D.Common.Utf8;

interface

uses
  System.SysUtils;

type
  // Own UTF-8 and UTF-16 decoders, so that every platform decodes malformed input the same way.
  TPdfUtf8 = class
  private
    const ReplacementChar = #$FFFD;

    class function SequenceLength(const Bytes: TBytes; const Index: Integer): Integer; static;
    class function IsContinuation(const Bytes: TBytes; const Index: Integer): Boolean; static;
    class function CodePointAt(const Bytes: TBytes; const Index, Length: Integer): Cardinal; static;
    class procedure AppendCodePoint(const Builder: TStringBuilder; const CodePoint: Cardinal); static;
    class function ReadCodeUnit(const Bytes: TBytes; const Index: Integer; const BigEndian: Boolean): Integer; static;

  public
    // Returns False when Bytes is not well-formed UTF-8 (overlong forms, surrogates and values above U+10FFFF included).
    class function TryDecodeStrict(const Bytes: TBytes; out Text: string): Boolean; static;

    // Malformed bytes become U+FFFD, one per byte.
    class function DecodeLenient(const Bytes: TBytes; const Start: Integer): string; static;

    // Malformed input (a lone surrogate, or an odd trailing byte) becomes U+FFFD.
    class function DecodeUtf16(const Bytes: TBytes; const Start: Integer; const BigEndian: Boolean): string; static;
  end;

implementation

{ TPdfUtf8 }

class function TPdfUtf8.TryDecodeStrict(const Bytes: TBytes; out Text: string): Boolean;
begin
  Text := '';
  const Builder = TStringBuilder.Create(System.Length(Bytes));
  try
    var Index := 0;
    while Index < System.Length(Bytes) do
    begin
      const Count = SequenceLength(Bytes, Index);
      if Count = 0 then
      begin
        Exit(False);
      end;

      AppendCodePoint(Builder, CodePointAt(Bytes, Index, Count));
      Inc(Index, Count);
    end;

    Text := Builder.ToString;
    Result := True;
  finally
    Builder.Free;
  end;
end;

class function TPdfUtf8.DecodeLenient(const Bytes: TBytes; const Start: Integer): string;
begin
  Result := '';
  if (Start < 0) or (Start >= System.Length(Bytes)) then
  begin
    Exit;
  end;

  const Builder = TStringBuilder.Create(System.Length(Bytes) - Start);
  try
    var Index := Start;
    while Index < System.Length(Bytes) do
    begin
      const Count = SequenceLength(Bytes, Index);
      if Count = 0 then
      begin
        Builder.Append(ReplacementChar);
        Inc(Index);
      end
      else
      begin
        AppendCodePoint(Builder, CodePointAt(Bytes, Index, Count));
        Inc(Index, Count);
      end;
    end;

    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TPdfUtf8.DecodeUtf16(const Bytes: TBytes; const Start: Integer; const BigEndian: Boolean): string;
begin
  Result := '';
  if (Start < 0) or (Start >= System.Length(Bytes)) then
  begin
    Exit;
  end;

  const Available = System.Length(Bytes) - Start;
  const Builder = TStringBuilder.Create(Available div 2 + 1);
  try
    var HighSurrogate := 0;
    for var UnitIndex := 0 to Available div 2 - 1 do
    begin
      const CodeUnit = ReadCodeUnit(Bytes, Start + UnitIndex * 2, BigEndian);

      if (HighSurrogate <> 0) and ((CodeUnit < $DC00) or (CodeUnit > $DFFF)) then
      begin
        Builder.Append(ReplacementChar);
        HighSurrogate := 0;
      end;

      if (CodeUnit >= $D800) and (CodeUnit <= $DBFF) then
      begin
        HighSurrogate := CodeUnit;
      end
      else if (CodeUnit >= $DC00) and (CodeUnit <= $DFFF) then
      begin
        if HighSurrogate = 0 then
        begin
          Builder.Append(ReplacementChar);
        end
        else
        begin
          Builder.Append(Char(HighSurrogate));
          Builder.Append(Char(CodeUnit));
          HighSurrogate := 0;
        end;
      end
      else
      begin
        Builder.Append(Char(CodeUnit));
      end;
    end;

    if (HighSurrogate <> 0) or Odd(Available) then
    begin
      Builder.Append(ReplacementChar);
    end;

    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TPdfUtf8.ReadCodeUnit(const Bytes: TBytes; const Index: Integer; const BigEndian: Boolean): Integer;
begin
  if BigEndian then
  begin
    Result := (Bytes[Index] shl 8) or Bytes[Index + 1];
  end
  else
  begin
    Result := (Bytes[Index + 1] shl 8) or Bytes[Index];
  end;
end;

class function TPdfUtf8.SequenceLength(const Bytes: TBytes; const Index: Integer): Integer;
begin
  const Lead = Bytes[Index];
  const Remaining = System.Length(Bytes) - Index;

  if Lead < $80 then
  begin
    Exit(1);
  end;

  var Count: Integer;
  var SecondLow := $80;
  var SecondHigh := $BF;
  case Lead of
    $C2..$DF:
      Count := 2;
    $E0:
      begin
        Count := 3;
        SecondLow := $A0;
      end;
    $E1..$EC, $EE..$EF:
      Count := 3;
    $ED:
      begin
        Count := 3;
        SecondHigh := $9F;
      end;
    $F0:
      begin
        Count := 4;
        SecondLow := $90;
      end;
    $F1..$F3:
      Count := 4;
    $F4:
      begin
        Count := 4;
        SecondHigh := $8F;
      end;
  else
    Exit(0);
  end;

  if Count > Remaining then
  begin
    Exit(0);
  end;

  if (Bytes[Index + 1] < SecondLow) or (Bytes[Index + 1] > SecondHigh) then
  begin
    Exit(0);
  end;

  for var Offset := 2 to Count - 1 do
  begin
    if not IsContinuation(Bytes, Index + Offset) then
    begin
      Exit(0);
    end;
  end;

  Result := Count;
end;

class function TPdfUtf8.IsContinuation(const Bytes: TBytes; const Index: Integer): Boolean;
begin
  Result := (Bytes[Index] and $C0) = $80;
end;

class function TPdfUtf8.CodePointAt(const Bytes: TBytes; const Index, Length: Integer): Cardinal;
begin
  case Length of
    1:
      Result := Bytes[Index];
    2:
      Result := (Cardinal(Bytes[Index] and $1F) shl 6) or (Bytes[Index + 1] and $3F);
    3:
      Result := (Cardinal(Bytes[Index] and $0F) shl 12) or (Cardinal(Bytes[Index + 1] and $3F) shl 6) or (Bytes[Index + 2] and $3F);
  else
    Result := (Cardinal(Bytes[Index] and $07) shl 18) or (Cardinal(Bytes[Index + 1] and $3F) shl 12) or
              (Cardinal(Bytes[Index + 2] and $3F) shl 6) or (Bytes[Index + 3] and $3F);
  end;
end;

class procedure TPdfUtf8.AppendCodePoint(const Builder: TStringBuilder; const CodePoint: Cardinal);
begin
  if CodePoint < $10000 then
  begin
    Builder.Append(Char(CodePoint));
  end
  else
  begin
    const Offset = CodePoint - $10000;
    Builder.Append(Char($D800 + (Offset shr 10)));
    Builder.Append(Char($DC00 + (Offset and $3FF)));
  end;
end;

end.
