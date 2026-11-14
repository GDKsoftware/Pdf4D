// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/encryption/SaslPrep.java (3.0.8)
// SASLprep of RFC 4013 for the passwords of revision 6. Differences with PDFBox: the normalization is a port of the algorithm
// (the RTL has none), and Java knows the bidirectional class of a character and Delphi does not, so the check of RFC 3454 section 6 uses the Hebrew and Arabic blocks for RandALCat and
// the other letters for LCat.
unit Pdf4D.Encryption.SaslPrep;

interface

uses
  System.SysUtils;

type
  // Raised for a password with a prohibited character, like the IllegalArgumentException of PDFBox
  EPdfSaslPrepException = class(Exception);

  TPdfSaslPrep = class
  private
    class function NonAsciiSpace(const Value: Char): Boolean; static;
    class function MappedToNothing(const Value: Char): Boolean; static;
    class function AsciiControl(const Value: Char): Boolean; static;
    class function NonAsciiControl(const CodePoint: Integer): Boolean; static;
    class function PrivateUse(const CodePoint: Integer): Boolean; static;
    class function NonCharacterCodePoint(const CodePoint: Integer): Boolean; static;
    class function SurrogateCodePoint(const CodePoint: Integer): Boolean; static;
    class function InappropriateForPlainText(const CodePoint: Integer): Boolean; static;
    class function InappropriateForCanonical(const CodePoint: Integer): Boolean; static;
    class function ChangeDisplayProperties(const CodePoint: Integer): Boolean; static;
    class function Tagging(const CodePoint: Integer): Boolean; static;
    class function IsRandALCat(const CodePoint: Integer): Boolean; static;
    class function IsLCat(const CodePoint: Integer): Boolean; static;
    class function CodePointAt(const Text: string; const Position: Integer; out Width: Integer): Integer; static;
    class function MapCharacters(const Text: string): string; static;
    class function Normalize(const Mapped: string): string; static;
    class procedure CheckProhibitedAndBidi(const Normalized: string); static;
    class function IsAscii(const Text: string): Boolean; static;

  public
    // Port of saslPrepQuery: unassigned code points are allowed. Raises EPdfSaslPrepException.
    class function SaslPrepQuery(const Value: string): string; static;

    class function Prohibited(const CodePoint: Integer): Boolean; static;
  end;

implementation

uses
  System.Character,
  Pdf4D.Encryption.UnicodeNormalization;

const
  HighSurrogateFirst = $D800;
  HighSurrogateLast = $DBFF;
  LowSurrogateFirst = $DC00;
  LowSurrogateLast = $DFFF;
  FirstSupplementaryCodePoint = $10000;
  SurrogateBits = 10;
  AsciiLimit = $80;
  NonCharacterPlaneStep = $10000;
  FirstPlaneNonCharacter = $FFFE;
  LastPlaneNonCharacter = $FFFF;
  LastPlane = 16;

{ TPdfSaslPrep }

class function TPdfSaslPrep.NonAsciiSpace(const Value: Char): Boolean;
begin
  Result := ((Value = #$00A0) or
             (Value = #$1680) or
             ((Value >= #$2000) and (Value <= #$200B)) or
             (Value = #$202F) or
             (Value = #$205F) or
             (Value = #$3000));
end;

class function TPdfSaslPrep.MappedToNothing(const Value: Char): Boolean;
begin
  Result := ((Value = #$00AD) or
             (Value = #$034F) or
             (Value = #$1806) or
             (Value = #$180B) or
             (Value = #$180C) or
             (Value = #$180D) or
             (Value = #$200B) or
             (Value = #$200C) or
             (Value = #$200D) or
             (Value = #$2060) or
             ((Value >= #$FE00) and (Value <= #$FE0F)) or
             (Value = #$FEFF));
end;

class function TPdfSaslPrep.AsciiControl(const Value: Char): Boolean;
begin
  Result := ((Value <= #$001F) or (Value = #$007F));
end;

class function TPdfSaslPrep.NonAsciiControl(const CodePoint: Integer): Boolean;
begin
  Result := (((CodePoint >= $0080) and (CodePoint <= $009F)) or
             (CodePoint = $06DD) or
             (CodePoint = $070F) or
             (CodePoint = $180E) or
             (CodePoint = $200C) or
             (CodePoint = $200D) or
             (CodePoint = $2028) or
             (CodePoint = $2029) or
             (CodePoint = $2060) or
             (CodePoint = $2061) or
             (CodePoint = $2062) or
             (CodePoint = $2063) or
             ((CodePoint >= $206A) and (CodePoint <= $206F)) or
             (CodePoint = $FEFF) or
             ((CodePoint >= $FFF9) and (CodePoint <= $FFFC)) or
             ((CodePoint >= $1D173) and (CodePoint <= $1D17A)));
end;

class function TPdfSaslPrep.PrivateUse(const CodePoint: Integer): Boolean;
begin
  Result := (((CodePoint >= $E000) and (CodePoint <= $F8FF)) or
             ((CodePoint >= $F0000) and (CodePoint <= $FFFFD)) or
             ((CodePoint >= $100000) and (CodePoint <= $10FFFD)));
end;

class function TPdfSaslPrep.NonCharacterCodePoint(const CodePoint: Integer): Boolean;
begin
  if (CodePoint >= $FDD0) and (CodePoint <= $FDEF) then
  begin
    Exit(True);
  end;

  // The last two code points of each plane: $FFFE, $FFFF, $1FFFE, $1FFFF up to $10FFFE, $10FFFF
  for var Plane := 0 to LastPlane do
  begin
    const First = (Plane * NonCharacterPlaneStep) + FirstPlaneNonCharacter;
    const Last = (Plane * NonCharacterPlaneStep) + LastPlaneNonCharacter;
    if (CodePoint >= First) and (CodePoint <= Last) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TPdfSaslPrep.SurrogateCodePoint(const CodePoint: Integer): Boolean;
begin
  Result := ((CodePoint >= HighSurrogateFirst) and (CodePoint <= LowSurrogateLast));
end;

class function TPdfSaslPrep.InappropriateForPlainText(const CodePoint: Integer): Boolean;
begin
  Result := ((CodePoint >= $FFF9) and (CodePoint <= $FFFD));
end;

class function TPdfSaslPrep.InappropriateForCanonical(const CodePoint: Integer): Boolean;
begin
  Result := ((CodePoint >= $2FF0) and (CodePoint <= $2FFB));
end;

class function TPdfSaslPrep.ChangeDisplayProperties(const CodePoint: Integer): Boolean;
begin
  Result := ((CodePoint = $0340) or
             (CodePoint = $0341) or
             (CodePoint = $200E) or
             (CodePoint = $200F) or
             ((CodePoint >= $202A) and (CodePoint <= $202E)) or
             ((CodePoint >= $206A) and (CodePoint <= $206F)));
end;

class function TPdfSaslPrep.Tagging(const CodePoint: Integer): Boolean;
begin
  Result := ((CodePoint = $E0001) or ((CodePoint >= $E0020) and (CodePoint <= $E007F)));
end;

// PDFBox casts the code point to a char for the space and control checks, so a supplementary code point is judged by its
// low 16 bits there. That is kept.
class function TPdfSaslPrep.Prohibited(const CodePoint: Integer): Boolean;
begin
  const AsChar = Char(Word(CodePoint and $FFFF));
  Result := (NonAsciiSpace(AsChar) or
             AsciiControl(AsChar) or
             NonAsciiControl(CodePoint) or
             PrivateUse(CodePoint) or
             NonCharacterCodePoint(CodePoint) or
             SurrogateCodePoint(CodePoint) or
             InappropriateForPlainText(CodePoint) or
             InappropriateForCanonical(CodePoint) or
             ChangeDisplayProperties(CodePoint) or
             Tagging(CodePoint));
end;

class function TPdfSaslPrep.IsRandALCat(const CodePoint: Integer): Boolean;
begin
  Result := (((CodePoint >= $0590) and (CodePoint <= $08FF)) or
             ((CodePoint >= $FB1D) and (CodePoint <= $FDFF)) or
             ((CodePoint >= $FE70) and (CodePoint <= $FEFF)) or
             ((CodePoint >= $10800) and (CodePoint <= $10FFF)) or
             ((CodePoint >= $1E800) and (CodePoint <= $1EFFF)));
end;

class function TPdfSaslPrep.IsLCat(const CodePoint: Integer): Boolean;
begin
  const CodePointText = Char.ConvertFromUtf32(CodePoint);
  const IsLetterCodePoint = Char.IsLetter(CodePointText, 0);
  Result := (IsLetterCodePoint and (not IsRandALCat(CodePoint)));
end;

// Java: String.codePointAt. A surrogate that does not belong to a pair is a code point of its own.
class function TPdfSaslPrep.CodePointAt(const Text: string; const Position: Integer; out Width: Integer): Integer;
begin
  Width := 1;
  Result := Ord(Text[Position]);
  const IsHigh = ((Result >= HighSurrogateFirst) and (Result <= HighSurrogateLast));
  const HasNext = (Position < Length(Text));
  if IsHigh and HasNext then
  begin
    const Low = Ord(Text[Position + 1]);
    if (Low >= LowSurrogateFirst) and (Low <= LowSurrogateLast) then
    begin
      Result := FirstSupplementaryCodePoint + ((Result - HighSurrogateFirst) shl SurrogateBits) + (Low - LowSurrogateFirst);
      Width := 2;
    end;
  end;
end;

class function TPdfSaslPrep.MapCharacters(const Text: string): string;
begin
  var Mapped := Text;
  for var Position := 1 to Length(Mapped) do
  begin
    if NonAsciiSpace(Mapped[Position]) then
    begin
      Mapped[Position] := ' ';
    end;
  end;

  Result := '';
  for var Value in Mapped do
  begin
    if not MappedToNothing(Value) then
    begin
      Result := Result + Value;
    end;
  end;
end;

class function TPdfSaslPrep.IsAscii(const Text: string): Boolean;
begin
  for var Value in Text do
  begin
    if Ord(Value) >= AsciiLimit then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

class function TPdfSaslPrep.Normalize(const Mapped: string): string;
begin
  // Text of ASCII characters is its own NFKC form
  if IsAscii(Mapped) then
  begin
    Exit(Mapped);
  end;

  const Normalizer = TPdfUnicodeNormalizer.Create;
  try
    Result := Normalizer.NormalizeNfkc(Mapped);
  finally
    Normalizer.Free;
  end;
end;

class procedure TPdfSaslPrep.CheckProhibitedAndBidi(const Normalized: string);
begin
  var ContainsRandALCat := False;
  var ContainsLCat := False;
  var InitialRandALCat := False;
  var Position := 1;
  while Position <= Length(Normalized) do
  begin
    var Width: Integer;
    const CodePoint = CodePointAt(Normalized, Position, Width);
    if Prohibited(CodePoint) then
    begin
      raise EPdfSaslPrepException.CreateFmt('Prohibited character U+%.4X at position %d', [CodePoint, Position - 1]);
    end;

    const RandALCat = IsRandALCat(CodePoint);
    ContainsRandALCat := (ContainsRandALCat or RandALCat);
    ContainsLCat := (ContainsLCat or IsLCat(CodePoint));
    InitialRandALCat := (InitialRandALCat or ((Position = 1) and RandALCat));

    Inc(Position, Width);
    const IsAtEnd = (Position > Length(Normalized));
    if InitialRandALCat and IsAtEnd and (not RandALCat) then
    begin
      raise EPdfSaslPrepException.Create('First character is RandALCat, but last character is not');
    end;
  end;

  if ContainsRandALCat and ContainsLCat then
  begin
    raise EPdfSaslPrepException.Create('Contains both RandALCat characters and LCat characters');
  end;
end;

class function TPdfSaslPrep.SaslPrepQuery(const Value: string): string;
begin
  const Mapped = MapCharacters(Value);
  Result := Normalize(Mapped);
  CheckProhibitedAndBidi(Result);
end;

end.
