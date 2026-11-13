// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.CffBuilder;

interface

uses
  System.SysUtils;

type
  TCffType1Options = record
    FontName: string;
    GlyphCount: Integer;
    // The bytes at the charset offset; empty leaves the charset operator out
    CharsetData: TBytes;
    // The bytes at the encoding offset; empty leaves the encoding operator out
    EncodingData: TBytes;
    StringIndexEntries: TArray<string>;
    LocalSubrs: TArray<TBytes>;
    DefaultWidthX: Integer;
    NominalWidthX: Integer;
    // DICT bytes put in front of the top DICT entries the builder makes
    ExtraTopDict: TBytes;

    class function Standard: TCffType1Options; static;
  end;

  // Builds small CFF font sets for tests. Numbers in DICTs always take five bytes, so offsets can be worked out without
  // iteration.
  TCffBuilder = class
  private
    const IntegerOperandSize = 5;

  private
    class function TopDict(const Options: TCffType1Options; const CharStringsOffset, CharsetOffset, EncodingOffset,
                           PrivateSize, PrivateOffset: Integer): TBytes; static;
    class function PrivateDict(const Options: TCffType1Options): TBytes; static;
    class function CharStringIndex(const GlyphCount: Integer): TBytes; static;

  public
    class function Concat(const Parts: array of TBytes): TBytes; static;
    class function Bytes(const Values: array of Byte): TBytes; static;
    class function AsciiBytes(const Text: string): TBytes; static;
    // An INDEX; OffSize is 1 to 4
    class function Index(const Entries: TArray<TBytes>; const OffSize: Integer = 2): TBytes; static;
    // A DICT integer operand that always takes five bytes (operator 29)
    class function IntegerOperand(const Value: Integer): TBytes; static;
    class function RealOperand(const Nibbles: array of Byte): TBytes; static;
    // A Type 1-equivalent font set (header, name, top DICT, string and global subr INDEX, charstrings, private DICT)
    class function Type1Font(const Options: TCffType1Options): TBytes; static;
  end;

implementation

const
  HeaderSize = 4;
  EndCharString = $0E;

{ TCffType1Options }

class function TCffType1Options.Standard: TCffType1Options;
begin
  Result := Default(TCffType1Options);
  Result.FontName := 'TestFont';
  Result.GlyphCount := 3;
  Result.DefaultWidthX := 500;
  Result.NominalWidthX := 600;
end;

{ TCffBuilder }

class function TCffBuilder.Concat(const Parts: array of TBytes): TBytes;
begin
  Result := nil;
  for var Part in Parts do
  begin
    Result := Result + Part;
  end;
end;

class function TCffBuilder.Bytes(const Values: array of Byte): TBytes;
begin
  SetLength(Result, Length(Values));
  for var Position := 0 to High(Values) do
  begin
    Result[Position] := Values[Position];
  end;
end;

class function TCffBuilder.AsciiBytes(const Text: string): TBytes;
begin
  SetLength(Result, Length(Text));
  for var Position := 0 to Length(Text) - 1 do
  begin
    Result[Position] := Byte(Text[Position + 1]);
  end;
end;

class function TCffBuilder.Index(const Entries: TArray<TBytes>; const OffSize: Integer): TBytes;
begin
  if Length(Entries) = 0 then
  begin
    Exit(Bytes([0, 0]));
  end;

  var Data: TBytes := nil;
  var Offsets: TBytes := nil;
  var Offset := 1;
  for var Position := 0 to Length(Entries) do
  begin
    for var Shift := OffSize - 1 downto 0 do
    begin
      Offsets := Offsets + Bytes([Byte((Offset shr (Shift * 8)) and $FF)]);
    end;
    if Position < Length(Entries) then
    begin
      Data := Data + Entries[Position];
      Inc(Offset, Length(Entries[Position]));
    end;
  end;

  Result := Concat([Bytes([Byte(Length(Entries) shr 8), Byte(Length(Entries) and $FF), Byte(OffSize)]), Offsets, Data]);
end;

class function TCffBuilder.IntegerOperand(const Value: Integer): TBytes;
begin
  Result := Bytes([29, Byte((Value shr 24) and $FF), Byte((Value shr 16) and $FF), Byte((Value shr 8) and $FF),
                   Byte(Value and $FF)]);
end;

class function TCffBuilder.RealOperand(const Nibbles: array of Byte): TBytes;
begin
  Result := Bytes([30]);
  var Position := 0;
  while Position < Length(Nibbles) do
  begin
    const HighNibble = Nibbles[Position] shl 4;
    var Low := $F;
    if Position + 1 < Length(Nibbles) then
    begin
      Low := Nibbles[Position + 1];
    end;
    Result := Result + Bytes([Byte(HighNibble or Low)]);
    Inc(Position, 2);
  end;
end;

class function TCffBuilder.CharStringIndex(const GlyphCount: Integer): TBytes;
begin
  var Entries: TArray<TBytes>;
  SetLength(Entries, GlyphCount);
  for var Glyph := 0 to GlyphCount - 1 do
  begin
    Entries[Glyph] := Bytes([EndCharString]);
  end;
  Result := Index(Entries, 4);
end;

class function TCffBuilder.PrivateDict(const Options: TCffType1Options): TBytes;
begin
  Result := Concat([IntegerOperand(Options.DefaultWidthX), Bytes([20]), IntegerOperand(Options.NominalWidthX), Bytes([21])]);
  if Length(Options.LocalSubrs) > 0 then
  begin
    // The offset of the local subroutines is counted from the start of the private DICT: they follow it directly
    const SizeWithSubrs = Length(Result) + IntegerOperandSize + 1;
    Result := Concat([Result, IntegerOperand(SizeWithSubrs), Bytes([19])]);
  end;
end;

class function TCffBuilder.TopDict(const Options: TCffType1Options; const CharStringsOffset, CharsetOffset,
                                   EncodingOffset, PrivateSize, PrivateOffset: Integer): TBytes;
begin
  Result := Concat([Options.ExtraTopDict, IntegerOperand(-10), IntegerOperand(-20), IntegerOperand(1000), IntegerOperand(900), Bytes([5])]);
  if Length(Options.CharsetData) > 0 then
  begin
    Result := Concat([Result, IntegerOperand(CharsetOffset), Bytes([15])]);
  end;
  if Length(Options.EncodingData) > 0 then
  begin
    Result := Concat([Result, IntegerOperand(EncodingOffset), Bytes([16])]);
  end;
  Result := Concat([Result, IntegerOperand(CharStringsOffset), Bytes([17]), IntegerOperand(PrivateSize),
                    IntegerOperand(PrivateOffset), Bytes([18])]);
end;

class function TCffBuilder.Type1Font(const Options: TCffType1Options): TBytes;
begin
  var Strings: TArray<TBytes>;
  SetLength(Strings, Length(Options.StringIndexEntries));
  for var Position := 0 to High(Strings) do
  begin
    Strings[Position] := AsciiBytes(Options.StringIndexEntries[Position]);
  end;

  const Header = Bytes([1, 0, HeaderSize, 4]);
  const NameIndex = Index([AsciiBytes(Options.FontName)], 1);
  const StringIndex = Index(Strings);
  const GlobalSubrs = Index(nil);
  const CharStrings = CharStringIndex(Options.GlyphCount);
  const PrivateData = PrivateDict(Options);
  var Subrs: TBytes := nil;
  if Length(Options.LocalSubrs) > 0 then
  begin
    Subrs := Index(Options.LocalSubrs);
  end;

  const TopIndexSize = Length(Index([TopDict(Options, 0, 0, 0, 0, 0)], 1));
  const CharStringsOffset = Length(Header) + Length(NameIndex) + TopIndexSize + Length(StringIndex) + Length(GlobalSubrs);
  const CharsetOffset = CharStringsOffset + Length(CharStrings);
  const EncodingOffset = CharsetOffset + Length(Options.CharsetData);
  const PrivateOffset = EncodingOffset + Length(Options.EncodingData);

  const FinalTopDict = TopDict(Options, CharStringsOffset, CharsetOffset, EncodingOffset, Length(PrivateData),
                               PrivateOffset);
  Result := Concat([Header, NameIndex, Index([FinalTopDict], 1), StringIndex, GlobalSubrs, CharStrings, Options.CharsetData,
                    Options.EncodingData, PrivateData, Subrs]);
end;

end.
