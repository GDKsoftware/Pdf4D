// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/TrueTypeCollection.java (3.0.8)
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/TTCDataStream.java (3.0.8)
unit Pdf4D.FontBox.TrueType.Collection;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.FontBox.TrueType.Font;

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

    procedure ReadHeader;
    function IsOpenTypeFont(const FontOffset: Int64): Boolean;
    function ParseFont(const FontOffset: Int64): TTrueTypeFont;

  public
    constructor Create(const Data: TBytes);

    function Count: Integer;
    // The caller owns the font. A font that cannot be read raises EPdfParseException.
    function FontAt(const Index: Integer): TTrueTypeFont;
    // The caller owns the font. Fonts that do not match are released.
    function TryGetFontByName(const Name: string; out Font: TTrueTypeFont): Boolean;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.FontBox.OpenType,
  Pdf4D.FontBox.TrueType.DataStream,
  Pdf4D.FontBox.TrueType.Parser;

{ TTrueTypeCollection }

constructor TTrueTypeCollection.Create(const Data: TBytes);
begin
  inherited Create;
  FData := Data;
  ReadHeader;
end;

procedure TTrueTypeCollection.ReadHeader;
begin
  const Stream = TTTFMemoryDataStream.Create(FData);
  try
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

    SetLength(FFontOffsets, Integer(NumFonts));
    for var Index := 0 to Integer(NumFonts) - 1 do
    begin
      FFontOffsets[Index] := Stream.ReadUnsignedInt;
    end;

    if Version >= MinimumVersionWithSignature then
    begin
      // The digital signature fields are not used
      Stream.ReadUnsignedShort;
      Stream.ReadUnsignedShort;
      Stream.ReadUnsignedShort;
    end;
  finally
    Stream.Free;
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
  for var Index := 0 to Count - 1 do
  begin
    const Candidate = FontAt(Index);
    if Candidate.Name = Name then
    begin
      Font := Candidate;
      Exit(True);
    end;
    Candidate.Free;
  end;

  Font := nil;
  Result := False;
end;

end.
