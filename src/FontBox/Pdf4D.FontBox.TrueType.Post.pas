// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/PostScriptTable.java (3.0.8)
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/WGL4Names.java (3.0.8)
unit Pdf4D.FontBox.TrueType.Post;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.FontBox.TrueType.DataStream,
  Pdf4D.FontBox.TrueType.Tables;

type
  // The 258 standard Macintosh glyph names of post formats 1 and 2 (Windows Glyph List 4)
  TWGL4Names = class sealed
  public
    const NumberOfMacGlyphs = 258;

  public
    class function TryGetGlyphName(const Index: Integer; out Name: string): Boolean; static;
  end;

  // A name index or a name count that does not fit the table gives ".undefined" or ".notdef", as in PDFBox. The table never reads
  // more than its data holds. A glyph without a name (format 2.5, or a table without names) has no entry.
  TPostScriptTable = class(TTTFTable)
  public
    const TableTag = 'post';

  private
    const MaximumNameIndex = 32767;
    const NotDefinedName = '.notdef';
    const UndefinedName = '.undefined';

  private
    FFormatType: Single;
    FItalicAngle: Single;
    FUnderlinePosition: SmallInt;
    FUnderlineThickness: SmallInt;
    FIsFixedPitch: Int64;
    FMinMemType42: Int64;
    FMaxMemType42: Int64;
    FMinMemType1: Int64;
    FMaxMemType1: Int64;
    FGlyphNames: TArray<string>;
    FHasGlyphName: TArray<Boolean>;
    FHasGlyphNames: Boolean;

    procedure SetAllNamesMissing(const Count: Integer);
    procedure SetName(const GID: Integer; const Name: string);
    procedure ReadFormat1;
    procedure ReadFormat2(const Data: TTTFDataStream);
    function ReadFormat2NameArray(const Data: TTTFDataStream; const Count: Integer): TArray<string>;
    procedure ReadFormat25(const Host: TTTFTableHost; const Data: TTTFDataStream);

  public
    procedure Read(const Host: TTTFTableHost; const Data: TTTFDataStream); override;

    // False when the glyph has no name
    function TryGetName(const GID: Integer; out Name: string): Boolean;
    // The number of glyphs the names cover
    function GlyphNameCount: Integer;

    property FormatType: Single read FFormatType;
    property ItalicAngle: Single read FItalicAngle;
    property UnderlinePosition: SmallInt read FUnderlinePosition;
    property UnderlineThickness: SmallInt read FUnderlineThickness;
    property IsFixedPitch: Int64 read FIsFixedPitch;
    property MinMemType42: Int64 read FMinMemType42;
    property MaxMemType42: Int64 read FMaxMemType42;
    property MinMemType1: Int64 read FMinMemType1;
    property MaxMemType1: Int64 read FMaxMemType1;
    // False when the table carries no glyph names (format 3, or no name data)
    property HasGlyphNames: Boolean read FHasGlyphNames;
  end;

implementation

uses
  System.Math,
  Pdf4D.Common.Defines;

const
  MacGlyphNames: array[0..TWGL4Names.NumberOfMacGlyphs - 1] of string = (
    '.notdef','.null', 'nonmarkingreturn', 'space', 'exclam', 'quotedbl',
    'numbersign', 'dollar', 'percent', 'ampersand', 'quotesingle',
    'parenleft', 'parenright', 'asterisk', 'plus', 'comma', 'hyphen',
    'period', 'slash', 'zero', 'one', 'two', 'three', 'four', 'five',
    'six', 'seven', 'eight', 'nine', 'colon', 'semicolon', 'less',
    'equal', 'greater', 'question', 'at', 'A', 'B', 'C', 'D', 'E', 'F',
    'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S',
    'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'bracketleft', 'backslash',
    'bracketright', 'asciicircum', 'underscore', 'grave', 'a', 'b',
    'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o',
    'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', 'braceleft',
    'bar', 'braceright', 'asciitilde', 'Adieresis', 'Aring',
    'Ccedilla', 'Eacute', 'Ntilde', 'Odieresis', 'Udieresis', 'aacute',
    'agrave', 'acircumflex', 'adieresis', 'atilde', 'aring',
    'ccedilla', 'eacute', 'egrave', 'ecircumflex', 'edieresis',
    'iacute', 'igrave', 'icircumflex', 'idieresis', 'ntilde', 'oacute',
    'ograve', 'ocircumflex', 'odieresis', 'otilde', 'uacute', 'ugrave',
    'ucircumflex', 'udieresis', 'dagger', 'degree', 'cent', 'sterling',
    'section', 'bullet', 'paragraph', 'germandbls', 'registered',
    'copyright', 'trademark', 'acute', 'dieresis', 'notequal', 'AE',
    'Oslash', 'infinity', 'plusminus', 'lessequal', 'greaterequal',
    'yen', 'mu', 'partialdiff', 'summation', 'product', 'pi',
    'integral', 'ordfeminine', 'ordmasculine', 'Omega', 'ae', 'oslash',
    'questiondown', 'exclamdown', 'logicalnot', 'radical', 'florin',
    'approxequal', 'Delta', 'guillemotleft', 'guillemotright',
    'ellipsis', 'nonbreakingspace', 'Agrave', 'Atilde', 'Otilde', 'OE',
    'oe', 'endash', 'emdash', 'quotedblleft', 'quotedblright',
    'quoteleft', 'quoteright', 'divide', 'lozenge', 'ydieresis',
    'Ydieresis', 'fraction', 'currency', 'guilsinglleft',
    'guilsinglright', 'fi', 'fl', 'daggerdbl', 'periodcentered',
    'quotesinglbase', 'quotedblbase', 'perthousand', 'Acircumflex',
    'Ecircumflex', 'Aacute', 'Edieresis', 'Egrave', 'Iacute',
    'Icircumflex', 'Idieresis', 'Igrave', 'Oacute', 'Ocircumflex',
    'apple', 'Ograve', 'Uacute', 'Ucircumflex', 'Ugrave', 'dotlessi',
    'circumflex', 'tilde', 'macron', 'breve', 'dotaccent', 'ring',
    'cedilla', 'hungarumlaut', 'ogonek', 'caron', 'Lslash', 'lslash',
    'Scaron', 'scaron', 'Zcaron', 'zcaron', 'brokenbar', 'Eth', 'eth',
    'Yacute', 'yacute', 'Thorn', 'thorn', 'minus', 'multiply',
    'onesuperior', 'twosuperior', 'threesuperior', 'onehalf',
    'onequarter', 'threequarters', 'franc', 'Gbreve', 'gbreve',
    'Idotaccent', 'Scedilla', 'scedilla', 'Cacute', 'cacute', 'Ccaron',
    'ccaron', 'dcroat'
  );

{ TWGL4Names }

class function TWGL4Names.TryGetGlyphName(const Index: Integer; out Name: string): Boolean;
begin
  Result := ((Index >= 0) and (Index < NumberOfMacGlyphs));
  if Result then
  begin
    Name := MacGlyphNames[Index];
  end
  else
  begin
    Name := '';
  end;
end;

{ TPostScriptTable }

procedure TPostScriptTable.SetAllNamesMissing(const Count: Integer);
begin
  SetLength(FGlyphNames, Count);
  SetLength(FHasGlyphName, Count);
  FHasGlyphNames := True;
end;

procedure TPostScriptTable.SetName(const GID: Integer; const Name: string);
begin
  FGlyphNames[GID] := Name;
  FHasGlyphName[GID] := True;
end;

procedure TPostScriptTable.ReadFormat1;
begin
  // The font holds exactly the 258 glyphs of the standard Macintosh set
  SetAllNamesMissing(TWGL4Names.NumberOfMacGlyphs);
  for var Index := 0 to TWGL4Names.NumberOfMacGlyphs - 1 do
  begin
    SetName(Index, MacGlyphNames[Index]);
  end;
end;

function TPostScriptTable.ReadFormat2NameArray(const Data: TTTFDataStream; const Count: Integer): TArray<string>;
begin
  SetLength(Result, Count);
  for var Index := 0 to Count - 1 do
  begin
    const NumberOfChars = Data.ReadUnsignedByte;
    try
      Result[Index] := Data.ReadString(NumberOfChars, TTTFStringEncoding.Latin1);
    except
      on EPdfParseException do
      begin
        // PDFBOX-4851: the data ends early
        for var Remaining := Index to Count - 1 do
        begin
          Result[Remaining] := NotDefinedName;
        end;
        Break;
      end;
    end;
  end;
end;

procedure TPostScriptTable.ReadFormat2(const Data: TTTFDataStream);
begin
  const NumGlyphs = Data.ReadUnsignedShort;
  const GlyphNameIndex = Data.ReadUnsignedShortArray(NumGlyphs);
  var MaxIndex := Low(Integer);
  for var Index in GlyphNameIndex do
  begin
    // PDFBOX-808: the numbers from 32768 are reserved
    if Index <= MaximumNameIndex then
    begin
      MaxIndex := Max(MaxIndex, Index);
    end;
  end;

  var NameArray: TArray<string> := nil;
  if MaxIndex >= TWGL4Names.NumberOfMacGlyphs then
  begin
    NameArray := ReadFormat2NameArray(Data, MaxIndex - TWGL4Names.NumberOfMacGlyphs + 1);
  end;

  SetAllNamesMissing(NumGlyphs);
  for var GID := 0 to NumGlyphs - 1 do
  begin
    const Index = GlyphNameIndex[GID];
    if Index < TWGL4Names.NumberOfMacGlyphs then
    begin
      SetName(GID, MacGlyphNames[Index]);
    end
    else if (Index <= MaximumNameIndex) and Assigned(NameArray) then
    begin
      SetName(GID, NameArray[Index - TWGL4Names.NumberOfMacGlyphs]);
    end
    else
    begin
      SetName(GID, UndefinedName);
    end;
  end;
end;

procedure TPostScriptTable.ReadFormat25(const Host: TTTFTableHost; const Data: TTTFDataStream);
begin
  const NumGlyphs = Host.NumberOfGlyphs;
  const IsBeyondEnd = (Int64(NumGlyphs) > Data.OriginalDataSize - Data.CurrentPosition);
  if IsBeyondEnd then
  begin
    raise EPdfParseException.CreateFmt('The post table (format 2.5) has %d offsets but the data is shorter', [NumGlyphs]);
  end;

  SetAllNamesMissing(NumGlyphs);
  var BadIndexCount := 0;
  for var GID := 0 to NumGlyphs - 1 do
  begin
    const Index = GID + 1 + Data.ReadSignedByte;
    var Name: string;
    if TWGL4Names.TryGetGlyphName(Index, Name) then
    begin
      SetName(GID, Name);
    end
    else
    begin
      Inc(BadIndexCount);
      if BadIndexCount <= MaximumLoggedRecordProblems then
      begin
        Host.LogWarning(Format('incorrect glyph name index %d, valid numbers 0..%d', [Index, TWGL4Names.NumberOfMacGlyphs]));
      end;
    end;
  end;

  if BadIndexCount > MaximumLoggedRecordProblems then
  begin
    Host.LogWarning(Format('%d glyph name indexes of the post table are incorrect', [BadIndexCount]));
  end;
end;

procedure TPostScriptTable.Read(const Host: TTTFTableHost; const Data: TTTFDataStream);
begin
  FFormatType := Data.Read32Fixed;
  FItalicAngle := Data.Read32Fixed;
  FUnderlinePosition := Data.ReadSignedShort;
  FUnderlineThickness := Data.ReadSignedShort;
  FIsFixedPitch := Data.ReadUnsignedInt;
  FMinMemType42 := Data.ReadUnsignedInt;
  FMaxMemType42 := Data.ReadUnsignedInt;
  FMinMemType1 := Data.ReadUnsignedInt;
  FMaxMemType1 := Data.ReadUnsignedInt;

  const HasNoNameData = (Data.CurrentPosition = Data.OriginalDataSize);
  if HasNoNameData then
  begin
    Host.LogWarning(Format('No PostScript name data is provided for the font %s', [Host.Name]));
  end
  else if FFormatType = 1.0 then
  begin
    ReadFormat1;
  end
  else if FFormatType = 2.0 then
  begin
    ReadFormat2(Data);
  end
  else if FFormatType = 2.5 then
  begin
    ReadFormat25(Host, Data);
  end;
  FInitialized := True;
end;

function TPostScriptTable.TryGetName(const GID: Integer; out Name: string): Boolean;
begin
  Name := '';
  const IsOutside = ((GID < 0) or (GID >= System.Length(FGlyphNames)));
  if IsOutside then
  begin
    Exit(False);
  end;

  Result := FHasGlyphName[GID];
  if Result then
  begin
    Name := FGlyphNames[GID];
  end;
end;

function TPostScriptTable.GlyphNameCount: Integer;
begin
  Result := System.Length(FGlyphNames);
end;

end.
