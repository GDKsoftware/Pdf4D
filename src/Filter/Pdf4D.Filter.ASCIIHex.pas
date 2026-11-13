// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/filter/ASCIIHexFilter.java (3.0.8)
unit Pdf4D.Filter.ASCIIHex;

interface

uses
  System.SysUtils,
  System.Classes,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Filter.Base,
  Pdf4D.Filter.ByteReader;

type
  TASCIIHexFilter = class(TPdfFilter)
  private
    const EndOfData = Ord('>');

  private
    class function IsWhitespace(const Value: Integer): Boolean; static;
    class function HexValue(const Value: Integer): Integer; static;

    function DigitValue(const Value: Integer): Integer;
    class procedure WriteValue(const Output: TStream; const Value: Integer); static;

  public
    procedure Decode(const Input, Output: TStream; const Parameters: TCosDictionary; const Index: Integer); override;
  end;

implementation

{ TASCIIHexFilter }

procedure TASCIIHexFilter.Decode(const Input, Output: TStream; const Parameters: TCosDictionary; const Index: Integer);
begin
  const Reader = TByteReader.Create(Input);
  try
    var FirstByte := Reader.ReadByte;
    while FirstByte <> -1 do
    begin
      while IsWhitespace(FirstByte) do
      begin
        FirstByte := Reader.ReadByte;
      end;

      if (FirstByte = -1) or (FirstByte = EndOfData) then
      begin
        Break;
      end;

      var Value := DigitValue(FirstByte) * 16;
      const SecondByte = Reader.ReadByte;
      if (SecondByte = -1) or (SecondByte = EndOfData) then
      begin
        // The second digit counts as 0 at the end of the data
        WriteValue(Output, Value);
        Break;
      end;

      Inc(Value, DigitValue(SecondByte));
      WriteValue(Output, Value);
      FirstByte := Reader.ReadByte;
    end;
  finally
    Reader.Free;
  end;
end;

// An invalid digit is logged and counts as -1, like in PDFBox
function TASCIIHexFilter.DigitValue(const Value: Integer): Integer;
begin
  Result := HexValue(Value);
  if (Result = -1) and Assigned(Log) then
  begin
    Log.Error('Invalid hex, int: %d char: %s', [Value, Char(Value)]);
  end;
end;

class function TASCIIHexFilter.HexValue(const Value: Integer): Integer;
begin
  case Value of
    Ord('0')..Ord('9'): Result := Value - Ord('0');
    Ord('A')..Ord('F'): Result := Value - Ord('A') + 10;
    Ord('a')..Ord('f'): Result := Value - Ord('a') + 10;
  else
    Result := -1;
  end;
end;

// Like OutputStream.write(int): only the low 8 bits count
class procedure TASCIIHexFilter.WriteValue(const Output: TStream; const Value: Integer);
begin
  const Data = Byte(Value and $FF);
  Output.WriteBuffer(Data, 1);
end;

class function TASCIIHexFilter.IsWhitespace(const Value: Integer): Boolean;
begin
  case Value of
    0, 9, 10, 12, 13, 32: Result := True;
  else
    Result := False;
  end;
end;

end.
