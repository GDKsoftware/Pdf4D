// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/TrueTypeCollection.java (3.0.8)
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/TTCDataStream.java (3.0.8)
unit Pdf4D.FontBox.TrueType.Collection;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.IO.RandomAccessRead,
  Pdf4D.FontBox.TrueType.DataStream,
  Pdf4D.FontBox.TrueType.Font,
  Pdf4D.FontBox.TrueType.Headers;

type
  // A TrueType collection (ttcf). The collection keeps the file data; every font that comes out of it is a separate object with
  // its own stream over that data and all its tables read, and belongs to the caller. A font with CFF outlines (OTTO) comes out as
  // a TOpenTypeFont.
  TTrueTypeCollection = class
  private
    const TagCollection = 'ttcf';
    const TagOpenType = 'OTTO';
    const MaximumFonts = 1024;
    const MinimumVersionWithSignature = 2;

  private
    FData: TBytes;
    FFontOffsets: TArray<Int64>;

    class function ReadFontOffsets(const Stream: TTTFDataStream): TArray<Int64>; static;
    class function IsOpenTypeFontAt(const Stream: TTTFDataStream; const FontOffset: Int64): Boolean; static;
    class function ReadFontHeadersAt(const Source: TRandomAccessRead; const FontOffset: Int64): TFontHeaders; static;
    procedure ReadHeader;
    function IsOpenTypeFont(const FontOffset: Int64): Boolean;
    function ParseFont(const FontOffset: Int64): TTrueTypeFont;

  public
    // The headers of every font of the collection, one per font and in its order, read from the source without loading it. The
    // source belongs to the caller. A font that cannot be read, or whose offset an earlier font already used, has an Error in its
    // headers; a collection header that cannot be read raises EPdfParseException.
    class function ReadAllFontHeaders(const Source: TRandomAccessRead): TArray<TFontHeaders>; static;

    constructor Create(const Data: TBytes);

    function Count: Integer;
    // The caller owns the font. A font that cannot be read raises EPdfParseException.
    function FontAt(const Index: Integer): TTrueTypeFont;
    // The caller owns the font. Fonts that do not match are released.
    function TryGetFontByName(const Name: string; out Font: TTrueTypeFont): Boolean;
  end;

implementation

uses
  System.Generics.Collections,
  Pdf4D.Common.Defines,
  Pdf4D.FontBox.OpenType,
  Pdf4D.FontBox.TrueType.Parser;

{ TTrueTypeCollection }

constructor TTrueTypeCollection.Create(const Data: TBytes);
begin
  inherited Create;
  FData := Data;
  ReadHeader;
end;

class function TTrueTypeCollection.ReadFontOffsets(const Stream: TTTFDataStream): TArray<Int64>;
begin
  if Stream.ReadTag <> TagCollection then
  begin
    raise EPdfParseException.Create('Missing TTC header');
  end;

  const Version = Stream.Read32Fixed;
  // PDFBox reads the count as an int, so a count of 2^31 or more is negative there and refused as well
  const NumFonts = Stream.ReadUnsignedInt;
  const IsCountValid = ((NumFonts > 0) and (NumFonts <= MaximumFonts));
  if not IsCountValid then
  begin
    raise EPdfParseException.CreateFmt('Invalid number of fonts %d', [NumFonts]);
  end;

  SetLength(Result, Integer(NumFonts));
  for var Index := 0 to Integer(NumFonts) - 1 do
  begin
    Result[Index] := Stream.ReadUnsignedInt;
  end;

  if Version >= MinimumVersionWithSignature then
  begin
    // The digital signature fields are not used
    Stream.ReadUnsignedShort;
    Stream.ReadUnsignedShort;
    Stream.ReadUnsignedShort;
  end;
end;

procedure TTrueTypeCollection.ReadHeader;
begin
  const Stream = TTTFMemoryDataStream.Create(FData);
  try
    FFontOffsets := ReadFontOffsets(Stream);
  finally
    Stream.Free;
  end;
end;

class function TTrueTypeCollection.IsOpenTypeFontAt(const Stream: TTTFDataStream; const FontOffset: Int64): Boolean;
begin
  Stream.Seek(FontOffset);
  Result := (Stream.ReadTag = TagOpenType);
end;

class function TTrueTypeCollection.ReadFontHeadersAt(const Source: TRandomAccessRead; const FontOffset: Int64): TFontHeaders;
begin
  const Stream = TTTFRandomAccessDataStream.Create(Source);
  var IsOpenType: Boolean;
  try
    IsOpenType := IsOpenTypeFontAt(Stream, FontOffset);
  finally
    Stream.Free;
  end;

  var Parser: TTTFParser;
  if IsOpenType then
  begin
    Parser := TOTFParser.Create;
  end
  else
  begin
    Parser := TTTFParser.Create;
  end;
  try
    Result := Parser.ParseTableHeaders(Source, FontOffset);
  finally
    Parser.Free;
  end;
end;

class function TTrueTypeCollection.ReadAllFontHeaders(const Source: TRandomAccessRead): TArray<TFontHeaders>;
begin
  var Offsets: TArray<Int64>;
  const Stream = TTTFRandomAccessDataStream.Create(Source);
  try
    Offsets := ReadFontOffsets(Stream);
  finally
    Stream.Free;
  end;

  const SeenOffsets = TDictionary<Int64, Boolean>.Create;
  const Headers = TList<TFontHeaders>.Create;
  try
    for var Offset in Offsets do
    begin
      if not SeenOffsets.TryAdd(Offset, True) then
      begin
        Headers.Add(TFontHeaders.Failed('The font offset is used by an earlier font of the collection'));
        Continue;
      end;

      try
        Headers.Add(ReadFontHeadersAt(Source, Offset));
      except
        on Failure: EPdfException do
        begin
          Headers.Add(TFontHeaders.Failed(Failure.Message));
        end;
      end;
    end;
    Result := Headers.ToArray;
  finally
    Headers.Free;
    SeenOffsets.Free;
  end;
end;

function TTrueTypeCollection.Count: Integer;
begin
  Result := System.Length(FFontOffsets);
end;

function TTrueTypeCollection.FontAt(const Index: Integer): TTrueTypeFont;
begin
  const IsIndexValid = ((Index >= 0) and (Index < Count));
  if not IsIndexValid then
  begin
    raise EPdfParseException.CreateFmt('The collection has no font %d; it holds %d fonts', [Index, Count]);
  end;

  Result := ParseFont(FFontOffsets[Index]);
end;

function TTrueTypeCollection.IsOpenTypeFont(const FontOffset: Int64): Boolean;
begin
  const Stream = TTTFMemoryDataStream.Create(FData);
  try
    Stream.Seek(FontOffset);
    Result := (Stream.ReadTag = TagOpenType);
  finally
    Stream.Free;
  end;
end;

function TTrueTypeCollection.ParseFont(const FontOffset: Int64): TTrueTypeFont;
begin
  if IsOpenTypeFont(FontOffset) then
  begin
    const OpenTypeParser = TOTFParser.Create;
    try
      Result := OpenTypeParser.Parse(FData, FontOffset);
    finally
      OpenTypeParser.Free;
    end;
  end
  else
  begin
    const Parser = TTTFParser.Create;
    try
      Result := Parser.Parse(FData, FontOffset);
    finally
      Parser.Free;
    end;
  end;
end;

function TTrueTypeCollection.TryGetFontByName(const Name: string; out Font: TTrueTypeFont): Boolean;
begin
  // Offsets that repeat point at a font that was already looked at, so a hostile collection cannot make the parser repeat the work
  const SeenOffsets = TDictionary<Int64, Boolean>.Create;
  try
    for var Index := 0 to Count - 1 do
    begin
      if not SeenOffsets.TryAdd(FFontOffsets[Index], True) then
      begin
        Continue;
      end;

      const Candidate = FontAt(Index);
      if Candidate.Name = Name then
      begin
        Font := Candidate;
        Exit(True);
      end;
      Candidate.Free;
    end;
  finally
    SeenOffsets.Free;
  end;

  Font := nil;
  Result := False;
end;

end.
