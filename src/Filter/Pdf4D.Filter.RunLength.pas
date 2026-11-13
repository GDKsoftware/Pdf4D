// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/filter/RunLengthDecodeFilter.java (3.0.8)
unit Pdf4D.Filter.RunLength;

interface

uses
  System.SysUtils,
  System.Classes,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Filter.Base,
  Pdf4D.Filter.ByteReader;

type
  TRunLengthFilter = class(TPdfFilter)
  private
    const EndOfData = 128;

  private
    class procedure CopyLiteral(const Reader: TByteReader; const Output: TStream; const Count: Integer); static;
    class procedure WriteRun(const Output: TStream; const Value: Byte; const Count: Integer); static;

  public
    procedure Decode(const Input, Output: TStream; const Parameters: TCosDictionary; const Index: Integer); override;
  end;

implementation

{ TRunLengthFilter }

procedure TRunLengthFilter.Decode(const Input, Output: TStream; const Parameters: TCosDictionary; const Index: Integer);
begin
  const Reader = TByteReader.Create(Input);
  try
    var DupAmount := Reader.ReadByte;
    while (DupAmount <> -1) and (DupAmount <> EndOfData) do
    begin
      if DupAmount <= 127 then
      begin
        CopyLiteral(Reader, Output, DupAmount + 1);
      end
      else
      begin
        const DupByte = Reader.ReadByte;
        if DupByte = -1 then
        begin
          Break;
        end;
        WriteRun(Output, Byte(DupByte), 257 - DupAmount);
      end;
      DupAmount := Reader.ReadByte;
    end;
  finally
    Reader.Free;
  end;
end;

class procedure TRunLengthFilter.CopyLiteral(const Reader: TByteReader; const Output: TStream; const Count: Integer);
begin
  var Buffer: TBytes;
  SetLength(Buffer, Count);
  var Remaining := Count;
  while Remaining > 0 do
  begin
    const Read = Reader.ReadBytes(Buffer, Remaining);
    if Read = 0 then
    begin
      Break;
    end;
    Output.WriteBuffer(Buffer[0], Read);
    Dec(Remaining, Read);
  end;
end;

class procedure TRunLengthFilter.WriteRun(const Output: TStream; const Value: Byte; const Count: Integer);
begin
  var Buffer: TBytes;
  SetLength(Buffer, Count);
  FillChar(Buffer[0], Count, Value);
  Output.WriteBuffer(Buffer[0], Count);
end;

end.
