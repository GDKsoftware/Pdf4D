// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
unit Pdf4D.Crypto.RC4;

// Replaces javax.crypto.Cipher with ARCFOUR as used by
// pdfbox/src/main/java/org/apache/pdfbox/pdmodel/encryption/SecurityHandler.java (3.0.8)

interface

uses
  System.SysUtils;

type
  TRC4Cipher = class
  private
    type
      TRC4State = array[0..255] of Byte;

  private
    class procedure GuardKey(const Key: TBytes); static;
    class function ScheduleKey(const Key: TBytes): TRC4State; static;
  public
    // RC4 encrypts and decrypts with the same operation
    class function Process(const Key, Data: TBytes): TBytes; static;
  end;

implementation

const
  MinKeyLength = 1;
  MaxKeyLength = 256;
  StateSize = 256;
  InvalidKeyLengthMessage = 'RC4 key must be 1 to 256 bytes, got %d';

{ TRC4Cipher }

class function TRC4Cipher.Process(const Key, Data: TBytes): TBytes;
begin
  GuardKey(Key);

  var State := ScheduleKey(Key);
  SetLength(Result, Length(Data));
  var I := 0;
  var J := 0;
  for var Index := 0 to High(Data) do
  begin
    I := (I + 1) mod StateSize;
    J := (J + State[I]) mod StateSize;

    const Swapped = State[I];
    State[I] := State[J];
    State[J] := Swapped;

    const KeyStreamByte = State[(State[I] + State[J]) mod StateSize];
    Result[Index] := Data[Index] xor KeyStreamByte;
  end;
end;

class function TRC4Cipher.ScheduleKey(const Key: TBytes): TRC4State;
begin
  for var Index := 0 to StateSize - 1 do
  begin
    Result[Index] := Byte(Index);
  end;

  var J := 0;
  for var I := 0 to StateSize - 1 do
  begin
    J := (J + Result[I] + Key[I mod Length(Key)]) mod StateSize;

    const Swapped = Result[I];
    Result[I] := Result[J];
    Result[J] := Swapped;
  end;
end;

class procedure TRC4Cipher.GuardKey(const Key: TBytes);
begin
  const KeyLength = Length(Key);
  const IsValidKeyLength = ((KeyLength >= MinKeyLength) and (KeyLength <= MaxKeyLength));
  if not IsValidKeyLength then
  begin
    raise EArgumentException.CreateFmt(InvalidKeyLengthMessage, [KeyLength]);
  end;
end;

end.
