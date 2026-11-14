// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/encoding/Encoding.java, StandardEncoding.java,
// MacRomanEncoding.java and BuiltInEncoding.java (3.0.8)
unit Pdf4D.FontBox.Encoding;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.SharedInstance;

type
  // A PostScript encoding vector of a font program. After construction the maps must not be modified.
  TFontBoxEncoding = class abstract
  private
    FCodeToName: TDictionary<Integer, string>;
    FNameToCode: TDictionary<string, Integer>;

  protected
    procedure AddCharacterEncoding(const Code: Integer; const Name: string);

  public
    constructor Create;
    destructor Destroy; override;

    // The name of the code, or .notdef when the encoding has none
    function GetName(const Code: Integer): string;
    function GetCode(const Name: string; out Code: Integer): Boolean;
    // The map belongs to the encoding and must not be changed
    function CodeToNameMap: TDictionary<Integer, string>;
  end;

  TFontBoxStandardEncoding = class(TFontBoxEncoding)
  private
    class var FShared: TPdfSharedInstance<TFontBoxStandardEncoding>;

    class destructor Destroy;

  public
    constructor Create;

    // The shared instance, which the caller does not own
    class function Instance: TFontBoxStandardEncoding; static;
  end;

  TFontBoxMacRomanEncoding = class(TFontBoxEncoding)
  private
    class var FShared: TPdfSharedInstance<TFontBoxMacRomanEncoding>;

    class destructor Destroy;

  public
    constructor Create;

    // The shared instance, which the caller does not own
    class function Instance: TFontBoxMacRomanEncoding; static;
  end;

  // The encoding that a font program carries itself
  TFontBoxBuiltInEncoding = class(TFontBoxEncoding)
  public
    // Copies the mapping
    constructor Create(const CodeToName: TDictionary<Integer, string>);
  end;

implementation

type
  TEntry = record
    Code: Integer;
    Name: string;
  end;

const
  StandardTable: array[0..148] of TEntry = (
    (Code: 65; Name: 'A'), (Code: 225; Name: 'AE'), (Code: 66; Name: 'B'), (Code: 67; Name: 'C'),
    (Code: 68; Name: 'D'), (Code: 69; Name: 'E'), (Code: 70; Name: 'F'), (Code: 71; Name: 'G'), (Code: 72; Name: 'H'),
    (Code: 73; Name: 'I'), (Code: 74; Name: 'J'), (Code: 75; Name: 'K'), (Code: 76; Name: 'L'),
    (Code: 232; Name: 'Lslash'), (Code: 77; Name: 'M'), (Code: 78; Name: 'N'), (Code: 79; Name: 'O'),
    (Code: 234; Name: 'OE'), (Code: 233; Name: 'Oslash'), (Code: 80; Name: 'P'), (Code: 81; Name: 'Q'),
    (Code: 82; Name: 'R'), (Code: 83; Name: 'S'), (Code: 84; Name: 'T'), (Code: 85; Name: 'U'), (Code: 86; Name: 'V'),
    (Code: 87; Name: 'W'), (Code: 88; Name: 'X'), (Code: 89; Name: 'Y'), (Code: 90; Name: 'Z'), (Code: 97; Name: 'a'),
    (Code: 194; Name: 'acute'), (Code: 241; Name: 'ae'), (Code: 38; Name: 'ampersand'),
    (Code: 94; Name: 'asciicircum'), (Code: 126; Name: 'asciitilde'), (Code: 42; Name: 'asterisk'),
    (Code: 64; Name: 'at'), (Code: 98; Name: 'b'), (Code: 92; Name: 'backslash'), (Code: 124; Name: 'bar'),
    (Code: 123; Name: 'braceleft'), (Code: 125; Name: 'braceright'), (Code: 91; Name: 'bracketleft'),
    (Code: 93; Name: 'bracketright'), (Code: 198; Name: 'breve'), (Code: 183; Name: 'bullet'), (Code: 99; Name: 'c'),
    (Code: 207; Name: 'caron'), (Code: 203; Name: 'cedilla'), (Code: 162; Name: 'cent'),
    (Code: 195; Name: 'circumflex'), (Code: 58; Name: 'colon'), (Code: 44; Name: 'comma'),
    (Code: 168; Name: 'currency'), (Code: 100; Name: 'd'), (Code: 178; Name: 'dagger'),
    (Code: 179; Name: 'daggerdbl'), (Code: 200; Name: 'dieresis'), (Code: 36; Name: 'dollar'),
    (Code: 199; Name: 'dotaccent'), (Code: 245; Name: 'dotlessi'), (Code: 101; Name: 'e'), (Code: 56; Name: 'eight'),
    (Code: 188; Name: 'ellipsis'), (Code: 208; Name: 'emdash'), (Code: 177; Name: 'endash'),
    (Code: 61; Name: 'equal'), (Code: 33; Name: 'exclam'), (Code: 161; Name: 'exclamdown'), (Code: 102; Name: 'f'),
    (Code: 174; Name: 'fi'), (Code: 53; Name: 'five'), (Code: 175; Name: 'fl'), (Code: 166; Name: 'florin'),
    (Code: 52; Name: 'four'), (Code: 164; Name: 'fraction'), (Code: 103; Name: 'g'), (Code: 251; Name: 'germandbls'),
    (Code: 193; Name: 'grave'), (Code: 62; Name: 'greater'), (Code: 171; Name: 'guillemotleft'),
    (Code: 187; Name: 'guillemotright'), (Code: 172; Name: 'guilsinglleft'), (Code: 173; Name: 'guilsinglright'),
    (Code: 104; Name: 'h'), (Code: 205; Name: 'hungarumlaut'), (Code: 45; Name: 'hyphen'), (Code: 105; Name: 'i'),
    (Code: 106; Name: 'j'), (Code: 107; Name: 'k'), (Code: 108; Name: 'l'), (Code: 60; Name: 'less'),
    (Code: 248; Name: 'lslash'), (Code: 109; Name: 'm'), (Code: 197; Name: 'macron'), (Code: 110; Name: 'n'),
    (Code: 57; Name: 'nine'), (Code: 35; Name: 'numbersign'), (Code: 111; Name: 'o'), (Code: 250; Name: 'oe'),
    (Code: 206; Name: 'ogonek'), (Code: 49; Name: 'one'), (Code: 227; Name: 'ordfeminine'),
    (Code: 235; Name: 'ordmasculine'), (Code: 249; Name: 'oslash'), (Code: 112; Name: 'p'),
    (Code: 182; Name: 'paragraph'), (Code: 40; Name: 'parenleft'), (Code: 41; Name: 'parenright'),
    (Code: 37; Name: 'percent'), (Code: 46; Name: 'period'), (Code: 180; Name: 'periodcentered'),
    (Code: 189; Name: 'perthousand'), (Code: 43; Name: 'plus'), (Code: 113; Name: 'q'), (Code: 63; Name: 'question'),
    (Code: 191; Name: 'questiondown'), (Code: 34; Name: 'quotedbl'), (Code: 185; Name: 'quotedblbase'),
    (Code: 170; Name: 'quotedblleft'), (Code: 186; Name: 'quotedblright'), (Code: 96; Name: 'quoteleft'),
    (Code: 39; Name: 'quoteright'), (Code: 184; Name: 'quotesinglbase'), (Code: 169; Name: 'quotesingle'),
    (Code: 114; Name: 'r'), (Code: 202; Name: 'ring'), (Code: 115; Name: 's'), (Code: 167; Name: 'section'),
    (Code: 59; Name: 'semicolon'), (Code: 55; Name: 'seven'), (Code: 54; Name: 'six'), (Code: 47; Name: 'slash'),
    (Code: 32; Name: 'space'), (Code: 163; Name: 'sterling'), (Code: 116; Name: 't'), (Code: 51; Name: 'three'),
    (Code: 196; Name: 'tilde'), (Code: 50; Name: 'two'), (Code: 117; Name: 'u'), (Code: 95; Name: 'underscore'),
    (Code: 118; Name: 'v'), (Code: 119; Name: 'w'), (Code: 120; Name: 'x'), (Code: 121; Name: 'y'),
    (Code: 165; Name: 'yen'), (Code: 122; Name: 'z'), (Code: 48; Name: 'zero')
  );

  MacRomanTable: array[0..206] of TEntry = (
    (Code: 65; Name: 'A'), (Code: 174; Name: 'AE'), (Code: 231; Name: 'Aacute'), (Code: 229; Name: 'Acircumflex'),
    (Code: 128; Name: 'Adieresis'), (Code: 203; Name: 'Agrave'), (Code: 129; Name: 'Aring'),
    (Code: 204; Name: 'Atilde'), (Code: 66; Name: 'B'), (Code: 67; Name: 'C'), (Code: 130; Name: 'Ccedilla'),
    (Code: 68; Name: 'D'), (Code: 69; Name: 'E'), (Code: 131; Name: 'Eacute'), (Code: 230; Name: 'Ecircumflex'),
    (Code: 232; Name: 'Edieresis'), (Code: 233; Name: 'Egrave'), (Code: 70; Name: 'F'), (Code: 71; Name: 'G'),
    (Code: 72; Name: 'H'), (Code: 73; Name: 'I'), (Code: 234; Name: 'Iacute'), (Code: 235; Name: 'Icircumflex'),
    (Code: 236; Name: 'Idieresis'), (Code: 237; Name: 'Igrave'), (Code: 74; Name: 'J'), (Code: 75; Name: 'K'),
    (Code: 76; Name: 'L'), (Code: 77; Name: 'M'), (Code: 78; Name: 'N'), (Code: 132; Name: 'Ntilde'),
    (Code: 79; Name: 'O'), (Code: 206; Name: 'OE'), (Code: 238; Name: 'Oacute'), (Code: 239; Name: 'Ocircumflex'),
    (Code: 133; Name: 'Odieresis'), (Code: 241; Name: 'Ograve'), (Code: 175; Name: 'Oslash'),
    (Code: 205; Name: 'Otilde'), (Code: 80; Name: 'P'), (Code: 81; Name: 'Q'), (Code: 82; Name: 'R'),
    (Code: 83; Name: 'S'), (Code: 84; Name: 'T'), (Code: 85; Name: 'U'), (Code: 242; Name: 'Uacute'),
    (Code: 243; Name: 'Ucircumflex'), (Code: 134; Name: 'Udieresis'), (Code: 244; Name: 'Ugrave'),
    (Code: 86; Name: 'V'), (Code: 87; Name: 'W'), (Code: 88; Name: 'X'), (Code: 89; Name: 'Y'),
    (Code: 217; Name: 'Ydieresis'), (Code: 90; Name: 'Z'), (Code: 97; Name: 'a'), (Code: 135; Name: 'aacute'),
    (Code: 137; Name: 'acircumflex'), (Code: 171; Name: 'acute'), (Code: 138; Name: 'adieresis'),
    (Code: 190; Name: 'ae'), (Code: 136; Name: 'agrave'), (Code: 38; Name: 'ampersand'), (Code: 140; Name: 'aring'),
    (Code: 94; Name: 'asciicircum'), (Code: 126; Name: 'asciitilde'), (Code: 42; Name: 'asterisk'),
    (Code: 64; Name: 'at'), (Code: 139; Name: 'atilde'), (Code: 98; Name: 'b'), (Code: 92; Name: 'backslash'),
    (Code: 124; Name: 'bar'), (Code: 123; Name: 'braceleft'), (Code: 125; Name: 'braceright'),
    (Code: 91; Name: 'bracketleft'), (Code: 93; Name: 'bracketright'), (Code: 249; Name: 'breve'),
    (Code: 165; Name: 'bullet'), (Code: 99; Name: 'c'), (Code: 255; Name: 'caron'), (Code: 141; Name: 'ccedilla'),
    (Code: 252; Name: 'cedilla'), (Code: 162; Name: 'cent'), (Code: 246; Name: 'circumflex'),
    (Code: 58; Name: 'colon'), (Code: 44; Name: 'comma'), (Code: 169; Name: 'copyright'),
    (Code: 219; Name: 'currency'), (Code: 100; Name: 'd'), (Code: 160; Name: 'dagger'),
    (Code: 224; Name: 'daggerdbl'), (Code: 161; Name: 'degree'), (Code: 172; Name: 'dieresis'),
    (Code: 214; Name: 'divide'), (Code: 36; Name: 'dollar'), (Code: 250; Name: 'dotaccent'),
    (Code: 245; Name: 'dotlessi'), (Code: 101; Name: 'e'), (Code: 142; Name: 'eacute'),
    (Code: 144; Name: 'ecircumflex'), (Code: 145; Name: 'edieresis'), (Code: 143; Name: 'egrave'),
    (Code: 56; Name: 'eight'), (Code: 201; Name: 'ellipsis'), (Code: 209; Name: 'emdash'),
    (Code: 208; Name: 'endash'), (Code: 61; Name: 'equal'), (Code: 33; Name: 'exclam'),
    (Code: 193; Name: 'exclamdown'), (Code: 102; Name: 'f'), (Code: 222; Name: 'fi'), (Code: 53; Name: 'five'),
    (Code: 223; Name: 'fl'), (Code: 196; Name: 'florin'), (Code: 52; Name: 'four'), (Code: 218; Name: 'fraction'),
    (Code: 103; Name: 'g'), (Code: 167; Name: 'germandbls'), (Code: 96; Name: 'grave'), (Code: 62; Name: 'greater'),
    (Code: 199; Name: 'guillemotleft'), (Code: 200; Name: 'guillemotright'), (Code: 220; Name: 'guilsinglleft'),
    (Code: 221; Name: 'guilsinglright'), (Code: 104; Name: 'h'), (Code: 253; Name: 'hungarumlaut'),
    (Code: 45; Name: 'hyphen'), (Code: 105; Name: 'i'), (Code: 146; Name: 'iacute'), (Code: 148; Name: 'icircumflex'),
    (Code: 149; Name: 'idieresis'), (Code: 147; Name: 'igrave'), (Code: 106; Name: 'j'), (Code: 107; Name: 'k'),
    (Code: 108; Name: 'l'), (Code: 60; Name: 'less'), (Code: 194; Name: 'logicalnot'), (Code: 109; Name: 'm'),
    (Code: 248; Name: 'macron'), (Code: 181; Name: 'mu'), (Code: 110; Name: 'n'), (Code: 57; Name: 'nine'),
    (Code: 150; Name: 'ntilde'), (Code: 35; Name: 'numbersign'), (Code: 111; Name: 'o'), (Code: 151; Name: 'oacute'),
    (Code: 153; Name: 'ocircumflex'), (Code: 154; Name: 'odieresis'), (Code: 207; Name: 'oe'),
    (Code: 254; Name: 'ogonek'), (Code: 152; Name: 'ograve'), (Code: 49; Name: 'one'),
    (Code: 187; Name: 'ordfeminine'), (Code: 188; Name: 'ordmasculine'), (Code: 191; Name: 'oslash'),
    (Code: 155; Name: 'otilde'), (Code: 112; Name: 'p'), (Code: 166; Name: 'paragraph'),
    (Code: 40; Name: 'parenleft'), (Code: 41; Name: 'parenright'), (Code: 37; Name: 'percent'),
    (Code: 46; Name: 'period'), (Code: 225; Name: 'periodcentered'), (Code: 228; Name: 'perthousand'),
    (Code: 43; Name: 'plus'), (Code: 177; Name: 'plusminus'), (Code: 113; Name: 'q'), (Code: 63; Name: 'question'),
    (Code: 192; Name: 'questiondown'), (Code: 34; Name: 'quotedbl'), (Code: 227; Name: 'quotedblbase'),
    (Code: 210; Name: 'quotedblleft'), (Code: 211; Name: 'quotedblright'), (Code: 212; Name: 'quoteleft'),
    (Code: 213; Name: 'quoteright'), (Code: 226; Name: 'quotesinglbase'), (Code: 39; Name: 'quotesingle'),
    (Code: 114; Name: 'r'), (Code: 168; Name: 'registered'), (Code: 251; Name: 'ring'), (Code: 115; Name: 's'),
    (Code: 164; Name: 'section'), (Code: 59; Name: 'semicolon'), (Code: 55; Name: 'seven'), (Code: 54; Name: 'six'),
    (Code: 47; Name: 'slash'), (Code: 32; Name: 'space'), (Code: 163; Name: 'sterling'), (Code: 116; Name: 't'),
    (Code: 51; Name: 'three'), (Code: 247; Name: 'tilde'), (Code: 170; Name: 'trademark'), (Code: 50; Name: 'two'),
    (Code: 117; Name: 'u'), (Code: 156; Name: 'uacute'), (Code: 158; Name: 'ucircumflex'),
    (Code: 159; Name: 'udieresis'), (Code: 157; Name: 'ugrave'), (Code: 95; Name: 'underscore'),
    (Code: 118; Name: 'v'), (Code: 119; Name: 'w'), (Code: 120; Name: 'x'), (Code: 121; Name: 'y'),
    (Code: 216; Name: 'ydieresis'), (Code: 180; Name: 'yen'), (Code: 122; Name: 'z'), (Code: 48; Name: 'zero')
  );


{ TFontBoxEncoding }

constructor TFontBoxEncoding.Create;
begin
  inherited Create;
  FCodeToName := TDictionary<Integer, string>.Create(250);
  FNameToCode := TDictionary<string, Integer>.Create(250);
end;

destructor TFontBoxEncoding.Destroy;
begin
  FNameToCode.Free;
  FCodeToName.Free;
  inherited;
end;

procedure TFontBoxEncoding.AddCharacterEncoding(const Code: Integer; const Name: string);
begin
  FCodeToName.AddOrSetValue(Code, Name);
  FNameToCode.AddOrSetValue(Name, Code);
end;

function TFontBoxEncoding.GetName(const Code: Integer): string;
begin
  if not FCodeToName.TryGetValue(Code, Result) then
  begin
    Result := '.notdef';
  end;
end;

function TFontBoxEncoding.GetCode(const Name: string; out Code: Integer): Boolean;
begin
  Result := FNameToCode.TryGetValue(Name, Code);
end;

function TFontBoxEncoding.CodeToNameMap: TDictionary<Integer, string>;
begin
  Result := FCodeToName;
end;

{ TFontBoxStandardEncoding }

class destructor TFontBoxStandardEncoding.Destroy;
begin
  FShared.Release;
end;

class function TFontBoxStandardEncoding.Instance: TFontBoxStandardEncoding;
begin
  Result := FShared.Get(
    function: TFontBoxStandardEncoding
    begin
      Result := TFontBoxStandardEncoding.Create;
    end);
end;

constructor TFontBoxStandardEncoding.Create;
begin
  inherited Create;
  for var Entry in StandardTable do
  begin
    AddCharacterEncoding(Entry.Code, Entry.Name);
  end;
end;

{ TFontBoxMacRomanEncoding }

class destructor TFontBoxMacRomanEncoding.Destroy;
begin
  FShared.Release;
end;

class function TFontBoxMacRomanEncoding.Instance: TFontBoxMacRomanEncoding;
begin
  Result := FShared.Get(
    function: TFontBoxMacRomanEncoding
    begin
      Result := TFontBoxMacRomanEncoding.Create;
    end);
end;

constructor TFontBoxMacRomanEncoding.Create;
begin
  inherited Create;
  for var Entry in MacRomanTable do
  begin
    AddCharacterEncoding(Entry.Code, Entry.Name);
  end;
end;

{ TFontBoxBuiltInEncoding }

constructor TFontBoxBuiltInEncoding.Create(const CodeToName: TDictionary<Integer, string>);
begin
  inherited Create;
  for var Pair in CodeToName do
  begin
    AddCharacterEncoding(Pair.Key, Pair.Value);
  end;
end;

end.
