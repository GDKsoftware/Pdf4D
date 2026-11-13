// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/cos/PDFDocEncoding.java (3.0.8)
unit Pdf4D.Cos.PdfDocEncoding;

interface

uses
  System.SysUtils;

type
  TPdfDocEncoding = class
  private
    type
      TDeviation = record
        Code: Byte;
        Value: Word;
      end;

    const
      ReplacementChar = $FFFD;

      // Deviations from ISO-8859-1, from the table in ISO 32000-1:2008
      Deviations: array[0..41] of TDeviation = (
        (Code: $18; Value: $02D8),
        (Code: $19; Value: $02C7),
        (Code: $1A; Value: $02C6),
        (Code: $1B; Value: $02D9),
        (Code: $1C; Value: $02DD),
        (Code: $1D; Value: $02DB),
        (Code: $1E; Value: $02DA),
        (Code: $1F; Value: $02DC),
        (Code: $7F; Value: ReplacementChar),
        (Code: $80; Value: $2022),
        (Code: $81; Value: $2020),
        (Code: $82; Value: $2021),
        (Code: $83; Value: $2026),
        (Code: $84; Value: $2014),
        (Code: $85; Value: $2013),
        (Code: $86; Value: $0192),
        (Code: $87; Value: $2044),
        (Code: $88; Value: $2039),
        (Code: $89; Value: $203A),
        (Code: $8A; Value: $2212),
        (Code: $8B; Value: $2030),
        (Code: $8C; Value: $201E),
        (Code: $8D; Value: $201C),
        (Code: $8E; Value: $201D),
        (Code: $8F; Value: $2018),
        (Code: $90; Value: $2019),
        (Code: $91; Value: $201A),
        (Code: $92; Value: $2122),
        (Code: $93; Value: $FB01),
        (Code: $94; Value: $FB02),
        (Code: $95; Value: $0141),
        (Code: $96; Value: $0152),
        (Code: $97; Value: $0160),
        (Code: $98; Value: $0178),
        (Code: $99; Value: $017D),
        (Code: $9A; Value: $0131),
        (Code: $9B; Value: $0142),
        (Code: $9C; Value: $0153),
        (Code: $9D; Value: $0161),
        (Code: $9E; Value: $017E),
        (Code: $9F; Value: ReplacementChar),
        (Code: $A0; Value: $20AC)
      );

    class function TryFindDeviation(const Code: Byte; out Value: Word): Boolean; static;
    class function UnicodeOf(const Code: Byte): Char; static;

  public
    // Port of PDFDocEncoding.toString. Code $AD has no entry in the table and decodes to #0, as in PDFBox.
    class function Decode(const Bytes: TBytes): string; static;

    // False for a code without a character in PDFDocEncoding ($7F, $9F and $AD); Value is then U+FFFD.
    class function CodeToUnicode(const Code: Byte; out Value: Char): Boolean; static;
  end;

implementation

{ TPdfDocEncoding }

class function TPdfDocEncoding.Decode(const Bytes: TBytes): string;
begin
  SetLength(Result, Length(Bytes));
  for var Index := 0 to High(Bytes) do
  begin
    Result[Index + 1] := UnicodeOf(Bytes[Index]);
  end;
end;

class function TPdfDocEncoding.CodeToUnicode(const Code: Byte; out Value: Char): Boolean;
begin
  Result := (Code <> $AD) and (UnicodeOf(Code) <> Char(ReplacementChar));
  if Result then
  begin
    Value := UnicodeOf(Code);
  end
  else
  begin
    Value := Char(ReplacementChar);
  end;
end;

class function TPdfDocEncoding.UnicodeOf(const Code: Byte): Char;
begin
  var Deviation: Word;
  if TryFindDeviation(Code, Deviation) then
  begin
    Exit(Char(Deviation));
  end;

  // The remaining codes are ISO-8859-1; the one gap there is $AD
  if Code = $AD then
  begin
    Exit(#0);
  end;

  Result := Char(Code);
end;

class function TPdfDocEncoding.TryFindDeviation(const Code: Byte; out Value: Word): Boolean;
begin
  Value := 0;
  for var Deviation in Deviations do
  begin
    if Deviation.Code = Code then
    begin
      Value := Deviation.Value;
      Exit(True);
    end;
  end;

  Result := False;
end;

end.
