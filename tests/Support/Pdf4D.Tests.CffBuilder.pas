// Copyright 2026 GDK Software
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
    // DICT bytes put in front of the private DICT entries the builder makes
    ExtraPrivateDict: TBytes;

    class function Standard: TCffType1Options; static;
  end;

  // A CID-keyed font set. Glyph n (from 1) has the CID CIDs[n - 1] and the charstring "<Widths[n - 1]> endchar".
  TCffCidOptions = record
    Registry: string;
    Ordering: string;
    Supplement: Integer;
    CIDs: TArray<Integer>;
    Widths: TArray<Integer>;
    DefaultWidthX: Integer;
    NominalWidthX: Integer;
    // How many font DICTs the builder makes; each has the private DICT. Ignored when FontDictBytes is set.
    FontDictCount: Integer;
    // How many of the font DICTs the builder makes have no Private entry (the first ones)
    FontDictsWithoutPrivate: Integer;
    // DICT bytes put in front of every font DICT the builder makes
    FontDictExtra: TBytes;
    // DICT bytes that replace the font DICTs the builder makes
    FontDictBytes: TArray<TBytes>;
    // Bytes that replace the whole FDArray INDEX
    FDArrayRaw: TBytes;
    // DICT bytes that replace the ROS entry (its operands and the operator)
    RosData: TBytes;
    // The local subroutines of the private DICT
    LocalSubrs: TArray<TBytes>;
    // Bytes that replace the charset (empty: format 0 with the CIDs) and the FDSelect (empty: format 3, one range)
    CharsetData: TBytes;
    FDSelectData: TBytes;
    // Leave the charset operator out of the top DICT
    OmitCharset: Boolean;
    OmitFDArray: Boolean;
    OmitFDSelect: Boolean;
    // DICT bytes put in front of the top DICT entries the builder makes
    ExtraTopDict: TBytes;
    // DICT bytes put in front of the private DICT entries the builder makes
    ExtraPrivateDict: TBytes;

    class function Standard: TCffCidOptions; static;
  end;

  // Builds small CFF font sets for tests. Numbers in DICTs always take five bytes, so offsets can be worked out without
  // iteration.
  TCffTestBuilder = class
  private
    const IntegerOperandSize = 5;

  private
    class function TopDict(const Options: TCffType1Options; const CharStringsOffset, CharsetOffset, EncodingOffset,
                           PrivateSize, PrivateOffset: Integer): TBytes; static;
    class function PrivateDict(const Options: TCffType1Options): TBytes; static;
    class function CharStringIndex(const GlyphCount: Integer): TBytes; static;
    class function Type2Number(const Value: Integer): TBytes; static;
    class function CidCharStringIndex(const Options: TCffCidOptions): TBytes; static;
    class function CidCharset(const Options: TCffCidOptions): TBytes; static;
    class function CidFDSelect(const Options: TCffCidOptions): TBytes; static;
    class function CidPrivateDict(const Options: TCffCidOptions): TBytes; static;
    class function CidFontDicts(const Options: TCffCidOptions; const PrivateSize, PrivateOffset: Integer): TBytes; static;
    class function CidTopDict(const Options: TCffCidOptions; const CharStringsOffset, CharsetOffset, FDSelectOffset,
                              FDArrayOffset: Integer): TBytes; static;

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
    // A CID-keyed font set (header, name, top DICT, string and global subr INDEX, charstrings, charset, FDSelect, FDArray and
    // private DICT)
    class function CidFont(const Options: TCffCidOptions): TBytes; static;
    // Glyph 0 is .notdef and glyph n has the CID CIDs[n - 1] and the width Widths[n - 1]; one font DICT, FDSelect format 3
    // and NominalWidthX 0
    class function CidKeyed(const Registry, Ordering: string; const Supplement: Integer; const CIDs: TArray<Integer>;
                            const Widths: TArray<Integer>): TBytes; static;
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

{ TCffCidOptions }

class function TCffCidOptions.Standard: TCffCidOptions;
begin
  Result := Default(TCffCidOptions);
  Result.Registry := 'Adobe';
  Result.Ordering := 'Identity';
  Result.DefaultWidthX := 1000;
  Result.FontDictCount := 1;
end;

{ TCffTestBuilder }

class function TCffTestBuilder.Concat(const Parts: array of TBytes): TBytes;
begin
  Result := nil;
  for var Part in Parts do
  begin
    Result := Result + Part;
  end;
end;

class function TCffTestBuilder.Bytes(const Values: array of Byte): TBytes;
begin
  SetLength(Result, Length(Values));
  for var Position := 0 to High(Values) do
  begin
    Result[Position] := Values[Position];
  end;
end;

class function TCffTestBuilder.AsciiBytes(const Text: string): TBytes;
begin
  SetLength(Result, Length(Text));
  for var Position := 0 to Length(Text) - 1 do
  begin
    Result[Position] := Byte(Text[Position + 1]);
  end;
end;

class function TCffTestBuilder.Index(const Entries: TArray<TBytes>; const OffSize: Integer): TBytes;
begin
  if Length(Entries) = 0 then
  begin
    Exit(Bytes([0, 0]));
  end;

  var DataSize := 0;
  for var Entry in Entries do
  begin
    Inc(DataSize, Length(Entry));
  end;

  // One allocation: an INDEX of 65535 entries must not take quadratic time to make
  const IndexHeaderSize = 3;
  const OffsetsSize = (Length(Entries) + 1) * OffSize;
  SetLength(Result, IndexHeaderSize + OffsetsSize + DataSize);
  Result[0] := Byte(Length(Entries) shr 8);
  Result[1] := Byte(Length(Entries) and $FF);
  Result[2] := Byte(OffSize);
  var Offset := 1;
  var DataPosition := IndexHeaderSize + OffsetsSize;
  for var Position := 0 to Length(Entries) do
  begin
    for var Shift := OffSize - 1 downto 0 do
    begin
      Result[IndexHeaderSize + (Position * OffSize) + (OffSize - 1 - Shift)] := Byte((Offset shr (Shift * 8)) and $FF);
    end;
    if Position < Length(Entries) then
    begin
      if Length(Entries[Position]) > 0 then
      begin
        Move(Entries[Position][0], Result[DataPosition], Length(Entries[Position]));
      end;
      Inc(DataPosition, Length(Entries[Position]));
      Inc(Offset, Length(Entries[Position]));
    end;
  end;
end;

class function TCffTestBuilder.IntegerOperand(const Value: Integer): TBytes;
begin
  Result := Bytes([29, Byte((Value shr 24) and $FF), Byte((Value shr 16) and $FF), Byte((Value shr 8) and $FF),
                   Byte(Value and $FF)]);
end;

class function TCffTestBuilder.RealOperand(const Nibbles: array of Byte): TBytes;
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

class function TCffTestBuilder.CharStringIndex(const GlyphCount: Integer): TBytes;
begin
  var Entries: TArray<TBytes>;
  SetLength(Entries, GlyphCount);
  for var Glyph := 0 to GlyphCount - 1 do
  begin
    Entries[Glyph] := Bytes([EndCharString]);
  end;
  Result := Index(Entries, 4);
end;

class function TCffTestBuilder.PrivateDict(const Options: TCffType1Options): TBytes;
begin
  Result := Concat([Options.ExtraPrivateDict, IntegerOperand(Options.DefaultWidthX), Bytes([20]), IntegerOperand(Options.NominalWidthX), Bytes([21])]);
  if Length(Options.LocalSubrs) > 0 then
  begin
    // The offset of the local subroutines is counted from the start of the private DICT: they follow it directly
    const SizeWithSubrs = Length(Result) + IntegerOperandSize + 1;
    Result := Concat([Result, IntegerOperand(SizeWithSubrs), Bytes([19])]);
  end;
end;

class function TCffTestBuilder.TopDict(const Options: TCffType1Options; const CharStringsOffset, CharsetOffset,
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

class function TCffTestBuilder.Type1Font(const Options: TCffType1Options): TBytes;
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

class function TCffTestBuilder.Type2Number(const Value: Integer): TBytes;
begin
  if (Value >= -107) and (Value <= 107) then
  begin
    Exit(Bytes([Byte(Value + 139)]));
  end;
  if (Value >= 108) and (Value <= 1131) then
  begin
    const Rest = Value - 108;
    Exit(Bytes([Byte(247 + (Rest shr 8)), Byte(Rest and $FF)]));
  end;
  if (Value >= -1131) and (Value <= -108) then
  begin
    const Rest = -Value - 108;
    Exit(Bytes([Byte(251 + (Rest shr 8)), Byte(Rest and $FF)]));
  end;
  Result := Bytes([28, Byte((Value shr 8) and $FF), Byte(Value and $FF)]);
end;

class function TCffTestBuilder.CidCharStringIndex(const Options: TCffCidOptions): TBytes;
begin
  var Entries: TArray<TBytes>;
  SetLength(Entries, Length(Options.CIDs) + 1);
  Entries[0] := Bytes([EndCharString]);
  for var Glyph := 1 to Length(Options.CIDs) do
  begin
    Entries[Glyph] := Concat([Type2Number(Options.Widths[Glyph - 1] - Options.NominalWidthX), Bytes([EndCharString])]);
  end;
  Result := Index(Entries, 4);
end;

class function TCffTestBuilder.CidCharset(const Options: TCffCidOptions): TBytes;
begin
  if Length(Options.CharsetData) > 0 then
  begin
    Exit(Options.CharsetData);
  end;

  Result := Bytes([0]);
  for var CID in Options.CIDs do
  begin
    Result := Concat([Result, Bytes([Byte(CID shr 8), Byte(CID and $FF)])]);
  end;
end;

class function TCffTestBuilder.CidFDSelect(const Options: TCffCidOptions): TBytes;
begin
  if Length(Options.FDSelectData) > 0 then
  begin
    Exit(Options.FDSelectData);
  end;

  const GlyphCount = Length(Options.CIDs) + 1;
  Result := Bytes([3, 0, 1, 0, 0, 0, Byte(GlyphCount shr 8), Byte(GlyphCount and $FF)]);
end;

class function TCffTestBuilder.CidPrivateDict(const Options: TCffCidOptions): TBytes;
begin
  Result := Concat([Options.ExtraPrivateDict, IntegerOperand(Options.DefaultWidthX), Bytes([20]), IntegerOperand(Options.NominalWidthX), Bytes([21])]);
  if Length(Options.LocalSubrs) > 0 then
  begin
    // The offset of the local subroutines is counted from the start of the private DICT: they follow it directly
    const SizeWithSubrs = Length(Result) + IntegerOperandSize + 1;
    Result := Concat([Result, IntegerOperand(SizeWithSubrs), Bytes([19])]);
  end;
end;

class function TCffTestBuilder.CidFontDicts(const Options: TCffCidOptions; const PrivateSize, PrivateOffset: Integer): TBytes;
begin
  if Length(Options.FDArrayRaw) > 0 then
  begin
    Exit(Options.FDArrayRaw);
  end;

  var Entries: TArray<TBytes>;
  if Length(Options.FontDictBytes) > 0 then
  begin
    Entries := Options.FontDictBytes;
  end
  else
  begin
    SetLength(Entries, Options.FontDictCount);
    for var Position := 0 to High(Entries) do
    begin
      Entries[Position] := Options.FontDictExtra;
      if Position >= Options.FontDictsWithoutPrivate then
      begin
        Entries[Position] := Concat([Entries[Position], IntegerOperand(PrivateSize), IntegerOperand(PrivateOffset),
                                     Bytes([18])]);
      end;
    end;
  end;
  Result := Index(Entries, 2);
end;

class function TCffTestBuilder.CidTopDict(const Options: TCffCidOptions; const CharStringsOffset, CharsetOffset,
                                          FDSelectOffset, FDArrayOffset: Integer): TBytes;
begin
  var Ros := Options.RosData;
  if Length(Ros) = 0 then
  begin
    // The registry and the ordering are the first two strings of the String INDEX
    Ros := Concat([IntegerOperand(391), IntegerOperand(392), IntegerOperand(Options.Supplement), Bytes([12, 30])]);
  end;
  Result := Concat([Options.ExtraTopDict, Ros, IntegerOperand(0), IntegerOperand(-200), IntegerOperand(1000),
                    IntegerOperand(900), Bytes([5])]);
  if not Options.OmitCharset then
  begin
    Result := Concat([Result, IntegerOperand(CharsetOffset), Bytes([15])]);
  end;
  if not Options.OmitFDSelect then
  begin
    Result := Concat([Result, IntegerOperand(FDSelectOffset), Bytes([12, 37])]);
  end;
  if not Options.OmitFDArray then
  begin
    Result := Concat([Result, IntegerOperand(FDArrayOffset), Bytes([12, 36])]);
  end;
  Result := Concat([Result, IntegerOperand(CharStringsOffset), Bytes([17])]);
end;

class function TCffTestBuilder.CidFont(const Options: TCffCidOptions): TBytes;
begin
  const Header = Bytes([1, 0, HeaderSize, 4]);
  const NameIndex = Index([AsciiBytes('TestCID')], 1);
  const StringIndex = Index([AsciiBytes(Options.Registry), AsciiBytes(Options.Ordering)]);
  const GlobalSubrs = Index(nil);
  const CharStrings = CidCharStringIndex(Options);
  const Charset = CidCharset(Options);
  const FDSelect = CidFDSelect(Options);
  const PrivateData = CidPrivateDict(Options);
  const FontDictsSize = Length(CidFontDicts(Options, 0, 0));

  const TopIndexSize = Length(Index([CidTopDict(Options, 0, 0, 0, 0)], 2));
  const CharStringsOffset = Length(Header) + Length(NameIndex) + TopIndexSize + Length(StringIndex) + Length(GlobalSubrs);
  const CharsetOffset = CharStringsOffset + Length(CharStrings);
  const FDSelectOffset = CharsetOffset + Length(Charset);
  const FDArrayOffset = FDSelectOffset + Length(FDSelect);
  const PrivateOffset = FDArrayOffset + FontDictsSize;

  const TopDict = CidTopDict(Options, CharStringsOffset, CharsetOffset, FDSelectOffset, FDArrayOffset);
  var Subrs: TBytes := nil;
  if Length(Options.LocalSubrs) > 0 then
  begin
    Subrs := Index(Options.LocalSubrs);
  end;
  Result := Concat([Header, NameIndex, Index([TopDict], 2), StringIndex, GlobalSubrs, CharStrings, Charset, FDSelect,
                    CidFontDicts(Options, Length(PrivateData), PrivateOffset), PrivateData, Subrs]);
end;

class function TCffTestBuilder.CidKeyed(const Registry, Ordering: string; const Supplement: Integer;
                                        const CIDs: TArray<Integer>; const Widths: TArray<Integer>): TBytes;
begin
  var Options := TCffCidOptions.Standard;
  Options.Registry := Registry;
  Options.Ordering := Ordering;
  Options.Supplement := Supplement;
  Options.CIDs := CIDs;
  Options.Widths := Widths;
  Result := CidFont(Options);
end;

end.
