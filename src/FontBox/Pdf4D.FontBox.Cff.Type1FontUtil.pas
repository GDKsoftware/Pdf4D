// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/cff/Type1FontUtil.java (3.0.8)
unit Pdf4D.FontBox.Cff.Type1FontUtil;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils;

type
  // Hex coding and the eexec and charstring encryption of Type 1 font programs
  TType1FontUtil = record
  private
    const EexecKey = 55665;
    const CharstringKey = 4330;
    const EexecRandomBytes = 4;
    const MultiplyConstant = 52845;
    const AddConstant = 22719;

  private
    class function Encrypt(const Plain: TBytes; const Key, RandomByteCount: Integer): TBytes; static;
    class function Decrypt(const Cipher: TBytes; const Key, RandomByteCount: Integer): TBytes; static;
    class function NextKey(const Key, CipherByte: Integer): Integer; static;

  public
    // Upper case hex digits
    class function HexEncode(const Bytes: TBytes): string; static;
    // Raises EPdfParseException for an odd length or a character that is no hex digit
    class function HexDecode(const Text: string): TBytes; static;

    class function EexecEncrypt(const Bytes: TBytes): TBytes; static;
    class function EexecDecrypt(const Bytes: TBytes): TBytes; static;
    class function CharstringEncrypt(const Bytes: TBytes; const RandomByteCount: Integer): TBytes; static;
    class function CharstringDecrypt(const Bytes: TBytes; const RandomByteCount: Integer): TBytes; static;
  end;

implementation

uses
  Pdf4D.Common.Defines;

{ TType1FontUtil }

class function TType1FontUtil.HexEncode(const Bytes: TBytes): string;
begin
  const Builder = TStringBuilder.Create;
  try
    for var Value in Bytes do
    begin
      Builder.Append(IntToHex(Value, 2));
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TType1FontUtil.HexDecode(const Text: string): TBytes;
begin
  if Odd(Length(Text)) then
  begin
    raise EPdfParseException.Create('A hex string must have an even number of digits');
  end;

  SetLength(Result, Length(Text) div 2);
  for var Index := 0 to High(Result) do
  begin
    var Value: Integer;
    if not TryStrToInt('$' + Copy(Text, Index * 2 + 1, 2), Value) then
    begin
      raise EPdfParseException.CreateFmt('Invalid hex digits at position %d', [Index * 2]);
    end;
    Result[Index] := Value;
  end;
end;

class function TType1FontUtil.NextKey(const Key, CipherByte: Integer): Integer;
begin
  // Java computes this in an int that wraps around and keeps 16 bits. Doing it in 64 bits gives the same 16 bits.
  const Product = Int64((CipherByte + Key) and $FFFF) * MultiplyConstant + AddConstant;
  Result := Integer(Product and $FFFF);
end;

class function TType1FontUtil.Encrypt(const Plain: TBytes; const Key, RandomByteCount: Integer): TBytes;
begin
  var Buffer: TBytes;
  SetLength(Buffer, Length(Plain) + RandomByteCount);
  if Length(Plain) > 0 then
  begin
    Move(Plain[0], Buffer[RandomByteCount], Length(Plain));
  end;

  var CurrentKey := Key;
  SetLength(Result, Length(Buffer));
  for var Index := 0 to High(Buffer) do
  begin
    const Cipher = Buffer[Index] xor (CurrentKey shr 8);
    Result[Index] := Cipher;
    CurrentKey := NextKey(CurrentKey, Cipher);
  end;
end;

class function TType1FontUtil.Decrypt(const Cipher: TBytes; const Key, RandomByteCount: Integer): TBytes;
begin
  if Length(Cipher) < RandomByteCount then
  begin
    raise EPdfParseException.Create('Encrypted Type 1 data is shorter than its random bytes');
  end;

  var CurrentKey := Key;
  SetLength(Result, Length(Cipher) - RandomByteCount);
  for var Index := 0 to High(Cipher) do
  begin
    const Plain = Cipher[Index] xor (CurrentKey shr 8);
    if Index >= RandomByteCount then
    begin
      Result[Index - RandomByteCount] := Plain;
    end;
    CurrentKey := NextKey(CurrentKey, Cipher[Index]);
  end;
end;

class function TType1FontUtil.EexecEncrypt(const Bytes: TBytes): TBytes;
begin
  Result := Encrypt(Bytes, EexecKey, EexecRandomBytes);
end;

class function TType1FontUtil.EexecDecrypt(const Bytes: TBytes): TBytes;
begin
  Result := Decrypt(Bytes, EexecKey, EexecRandomBytes);
end;

class function TType1FontUtil.CharstringEncrypt(const Bytes: TBytes; const RandomByteCount: Integer): TBytes;
begin
  Result := Encrypt(Bytes, CharstringKey, RandomByteCount);
end;

class function TType1FontUtil.CharstringDecrypt(const Bytes: TBytes; const RandomByteCount: Integer): TBytes;
begin
  Result := Decrypt(Bytes, CharstringKey, RandomByteCount);
end;

end.
