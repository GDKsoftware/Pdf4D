// Port of: pdfbox/src/main/java/org/apache/pdfbox/filter/ASCII85Filter.java and ASCII85InputStream.java (3.0.8)
unit Pdf4D.Filter.ASCII85;

interface

uses
  System.SysUtils,
  System.Classes,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Filter.Base,
  Pdf4D.Filter.ByteReader;

type
  TASCII85Filter = class(TPdfFilter)
  private
    const Terminator = Ord('~');
    const Offset = Ord('!');
    const PaddingU = Ord('u');
    const ZeroGroup = Ord('z');
    const GroupLength = 5;

  private
    // The next byte that is not a line break or a space. Like PDFBox, a byte of $FF counts as the end of the data.
    class function NextSignificantByte(const Reader: TByteReader): Integer; static;
    class function DecodeGroup(const Digits: array of Byte): Cardinal; static;

  public
    procedure Decode(const Input, Output: TStream; const Parameters: TCosDictionary; const Index: Integer); override;
  end;

implementation

uses
  Pdf4D.Common.Defines;

{ TASCII85Filter }

procedure TASCII85Filter.Decode(const Input, Output: TStream; const Parameters: TCosDictionary; const Index: Integer);
begin
  const Reader = TByteReader.Create(Input);
  try
    var Digits: array[0..GroupLength - 1] of Byte;
    var Decoded: array[0..3] of Byte;
    while True do
    begin
      const First = NextSignificantByte(Reader);
      if (First = -1) or (First = Terminator) then
      begin
        Break;
      end;

      var OutputLength := 4;
      if First = ZeroGroup then
      begin
        FillChar(Decoded, SizeOf(Decoded), 0);
      end
      else
      begin
        Digits[0] := Byte(First);
        var Count := 1;
        var Ended := False;
        while Count < GroupLength do
        begin
          const Next = NextSignificantByte(Reader);
          if Next = -1 then
          begin
            // The data ends inside a group: the incomplete group is dropped
            Exit;
          end;

          Digits[Count] := Byte(Next);
          Inc(Count);
          if Next = Terminator then
          begin
            Digits[Count - 1] := PaddingU;
            Ended := True;
            Break;
          end;
        end;

        // A group of N digits followed by the terminator gives N - 1 bytes
        if Ended then
        begin
          OutputLength := Count - 2;
        end;

        if OutputLength = 0 then
        begin
          Break;
        end;

        for var Position := Count to GroupLength - 1 do
        begin
          Digits[Position] := PaddingU;
        end;

        const Value = DecodeGroup(Digits);
        Decoded[0] := Byte(Value shr 24);
        Decoded[1] := Byte(Value shr 16);
        Decoded[2] := Byte(Value shr 8);
        Decoded[3] := Byte(Value);
        if Ended then
        begin
          Output.WriteBuffer(Decoded, OutputLength);
          Break;
        end;
      end;

      Output.WriteBuffer(Decoded, OutputLength);
    end;
  finally
    Reader.Free;
  end;
end;

class function TASCII85Filter.NextSignificantByte(const Reader: TByteReader): Integer;
begin
  repeat
    Result := Reader.ReadByte;
  until (Result <> 10) and (Result <> 13) and (Result <> 32);

  if Result = $FF then
  begin
    Result := -1;
  end;
end;

class function TASCII85Filter.DecodeGroup(const Digits: array of Byte): Cardinal;
begin
  var Total: Int64 := 0;
  for var Digit in Digits do
  begin
    const Value = Integer(Digit) - Offset;
    if (Value < 0) or (Value > 93) then
    begin
      raise EPdfParseException.Create('Invalid data in Ascii85 stream');
    end;
    Total := (Total * 85) + Value;
  end;
  Result := Cardinal(Total and $FFFFFFFF);
end;

end.
