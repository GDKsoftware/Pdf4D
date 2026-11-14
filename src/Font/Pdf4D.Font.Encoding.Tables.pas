// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/font/encoding/StandardEncoding.java, WinAnsiEncoding.java,
// MacRomanEncoding.java, MacOSRomanEncoding.java, MacExpertEncoding.java, SymbolEncoding.java and
// ZapfDingbatsEncoding.java (3.0.8)
unit Pdf4D.Font.Encoding.Tables;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Common.SharedInstance,
  Pdf4D.Font.Encoding;

type
  // The predefined encodings. Each has one shared instance that is made at first use and never changes afterwards; the
  // caller does not own it.
  TStandardEncoding = class(TPdfEncoding)
  private
    class var FShared: TPdfSharedInstance<TStandardEncoding>;

    class destructor Destroy;

  public
    constructor Create;

    class function Instance: TStandardEncoding; static;

    function EncodingName: string; override;
  end;

  TWinAnsiEncoding = class(TPdfEncoding)
  private
    class var FShared: TPdfSharedInstance<TWinAnsiEncoding>;

    class destructor Destroy;

  public
    constructor Create;

    class function Instance: TWinAnsiEncoding; static;

    function EncodingName: string; override;
  end;

  TMacRomanEncoding = class(TPdfEncoding)
  private
    class var FShared: TPdfSharedInstance<TMacRomanEncoding>;

    class destructor Destroy;

  public
    constructor Create;

    class function Instance: TMacRomanEncoding; static;

    function EncodingName: string; override;
  end;

  // MacRomanEncoding plus 16 entries of the Mac OS character set
  TMacOSRomanEncoding = class(TMacRomanEncoding)
  private
    class var FSharedMacOS: TPdfSharedInstance<TMacOSRomanEncoding>;

    class destructor Destroy;

  public
    constructor Create;

    class function Instance: TMacOSRomanEncoding; reintroduce; static;
  end;

  TMacExpertEncoding = class(TPdfEncoding)
  private
    class var FShared: TPdfSharedInstance<TMacExpertEncoding>;

    class destructor Destroy;

  public
    constructor Create;

    class function Instance: TMacExpertEncoding; static;

    function EncodingName: string; override;
  end;

  TSymbolEncoding = class(TPdfEncoding)
  private
    class var FShared: TPdfSharedInstance<TSymbolEncoding>;

    class destructor Destroy;

  public
    constructor Create;

    class function Instance: TSymbolEncoding; static;

    function EncodingName: string; override;
  end;

  TZapfDingbatsEncoding = class(TPdfEncoding)
  private
    class var FShared: TPdfSharedInstance<TZapfDingbatsEncoding>;

    class destructor Destroy;

  public
    constructor Create;

    class function Instance: TZapfDingbatsEncoding; static;

    function EncodingName: string; override;
  end;

implementation

type
  TEntry = record
    Code: Integer;
    Name: string;
  end;

const
  FirstWinAnsiBulletCode = 33;
  LastWinAnsiBulletCode = 255;

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

  WinAnsiTable: array[0..217] of TEntry = (
    (Code: 65; Name: 'A'), (Code: 198; Name: 'AE'), (Code: 193; Name: 'Aacute'), (Code: 194; Name: 'Acircumflex'),
    (Code: 196; Name: 'Adieresis'), (Code: 192; Name: 'Agrave'), (Code: 197; Name: 'Aring'),
    (Code: 195; Name: 'Atilde'), (Code: 66; Name: 'B'), (Code: 67; Name: 'C'), (Code: 199; Name: 'Ccedilla'),
    (Code: 68; Name: 'D'), (Code: 69; Name: 'E'), (Code: 201; Name: 'Eacute'), (Code: 202; Name: 'Ecircumflex'),
    (Code: 203; Name: 'Edieresis'), (Code: 200; Name: 'Egrave'), (Code: 208; Name: 'Eth'), (Code: 128; Name: 'Euro'),
    (Code: 70; Name: 'F'), (Code: 71; Name: 'G'), (Code: 72; Name: 'H'), (Code: 73; Name: 'I'),
    (Code: 205; Name: 'Iacute'), (Code: 206; Name: 'Icircumflex'), (Code: 207; Name: 'Idieresis'),
    (Code: 204; Name: 'Igrave'), (Code: 74; Name: 'J'), (Code: 75; Name: 'K'), (Code: 76; Name: 'L'),
    (Code: 77; Name: 'M'), (Code: 78; Name: 'N'), (Code: 209; Name: 'Ntilde'), (Code: 79; Name: 'O'),
    (Code: 140; Name: 'OE'), (Code: 211; Name: 'Oacute'), (Code: 212; Name: 'Ocircumflex'),
    (Code: 214; Name: 'Odieresis'), (Code: 210; Name: 'Ograve'), (Code: 216; Name: 'Oslash'),
    (Code: 213; Name: 'Otilde'), (Code: 80; Name: 'P'), (Code: 81; Name: 'Q'), (Code: 82; Name: 'R'),
    (Code: 83; Name: 'S'), (Code: 138; Name: 'Scaron'), (Code: 84; Name: 'T'), (Code: 222; Name: 'Thorn'),
    (Code: 85; Name: 'U'), (Code: 218; Name: 'Uacute'), (Code: 219; Name: 'Ucircumflex'),
    (Code: 220; Name: 'Udieresis'), (Code: 217; Name: 'Ugrave'), (Code: 86; Name: 'V'), (Code: 87; Name: 'W'),
    (Code: 88; Name: 'X'), (Code: 89; Name: 'Y'), (Code: 221; Name: 'Yacute'), (Code: 159; Name: 'Ydieresis'),
    (Code: 90; Name: 'Z'), (Code: 142; Name: 'Zcaron'), (Code: 97; Name: 'a'), (Code: 225; Name: 'aacute'),
    (Code: 226; Name: 'acircumflex'), (Code: 180; Name: 'acute'), (Code: 228; Name: 'adieresis'),
    (Code: 230; Name: 'ae'), (Code: 224; Name: 'agrave'), (Code: 38; Name: 'ampersand'), (Code: 229; Name: 'aring'),
    (Code: 94; Name: 'asciicircum'), (Code: 126; Name: 'asciitilde'), (Code: 42; Name: 'asterisk'),
    (Code: 64; Name: 'at'), (Code: 227; Name: 'atilde'), (Code: 98; Name: 'b'), (Code: 92; Name: 'backslash'),
    (Code: 124; Name: 'bar'), (Code: 123; Name: 'braceleft'), (Code: 125; Name: 'braceright'),
    (Code: 91; Name: 'bracketleft'), (Code: 93; Name: 'bracketright'), (Code: 166; Name: 'brokenbar'),
    (Code: 149; Name: 'bullet'), (Code: 99; Name: 'c'), (Code: 231; Name: 'ccedilla'), (Code: 184; Name: 'cedilla'),
    (Code: 162; Name: 'cent'), (Code: 136; Name: 'circumflex'), (Code: 58; Name: 'colon'), (Code: 44; Name: 'comma'),
    (Code: 169; Name: 'copyright'), (Code: 164; Name: 'currency'), (Code: 100; Name: 'd'),
    (Code: 134; Name: 'dagger'), (Code: 135; Name: 'daggerdbl'), (Code: 176; Name: 'degree'),
    (Code: 168; Name: 'dieresis'), (Code: 247; Name: 'divide'), (Code: 36; Name: 'dollar'), (Code: 101; Name: 'e'),
    (Code: 233; Name: 'eacute'), (Code: 234; Name: 'ecircumflex'), (Code: 235; Name: 'edieresis'),
    (Code: 232; Name: 'egrave'), (Code: 56; Name: 'eight'), (Code: 133; Name: 'ellipsis'),
    (Code: 151; Name: 'emdash'), (Code: 150; Name: 'endash'), (Code: 61; Name: 'equal'), (Code: 240; Name: 'eth'),
    (Code: 33; Name: 'exclam'), (Code: 161; Name: 'exclamdown'), (Code: 102; Name: 'f'), (Code: 53; Name: 'five'),
    (Code: 131; Name: 'florin'), (Code: 52; Name: 'four'), (Code: 103; Name: 'g'), (Code: 223; Name: 'germandbls'),
    (Code: 96; Name: 'grave'), (Code: 62; Name: 'greater'), (Code: 171; Name: 'guillemotleft'),
    (Code: 187; Name: 'guillemotright'), (Code: 139; Name: 'guilsinglleft'), (Code: 155; Name: 'guilsinglright'),
    (Code: 104; Name: 'h'), (Code: 45; Name: 'hyphen'), (Code: 105; Name: 'i'), (Code: 237; Name: 'iacute'),
    (Code: 238; Name: 'icircumflex'), (Code: 239; Name: 'idieresis'), (Code: 236; Name: 'igrave'),
    (Code: 106; Name: 'j'), (Code: 107; Name: 'k'), (Code: 108; Name: 'l'), (Code: 60; Name: 'less'),
    (Code: 172; Name: 'logicalnot'), (Code: 109; Name: 'm'), (Code: 175; Name: 'macron'), (Code: 181; Name: 'mu'),
    (Code: 215; Name: 'multiply'), (Code: 110; Name: 'n'), (Code: 57; Name: 'nine'), (Code: 241; Name: 'ntilde'),
    (Code: 35; Name: 'numbersign'), (Code: 111; Name: 'o'), (Code: 243; Name: 'oacute'),
    (Code: 244; Name: 'ocircumflex'), (Code: 246; Name: 'odieresis'), (Code: 156; Name: 'oe'),
    (Code: 242; Name: 'ograve'), (Code: 49; Name: 'one'), (Code: 189; Name: 'onehalf'),
    (Code: 188; Name: 'onequarter'), (Code: 185; Name: 'onesuperior'), (Code: 170; Name: 'ordfeminine'),
    (Code: 186; Name: 'ordmasculine'), (Code: 248; Name: 'oslash'), (Code: 245; Name: 'otilde'),
    (Code: 112; Name: 'p'), (Code: 182; Name: 'paragraph'), (Code: 40; Name: 'parenleft'),
    (Code: 41; Name: 'parenright'), (Code: 37; Name: 'percent'), (Code: 46; Name: 'period'),
    (Code: 183; Name: 'periodcentered'), (Code: 137; Name: 'perthousand'), (Code: 43; Name: 'plus'),
    (Code: 177; Name: 'plusminus'), (Code: 113; Name: 'q'), (Code: 63; Name: 'question'),
    (Code: 191; Name: 'questiondown'), (Code: 34; Name: 'quotedbl'), (Code: 132; Name: 'quotedblbase'),
    (Code: 147; Name: 'quotedblleft'), (Code: 148; Name: 'quotedblright'), (Code: 145; Name: 'quoteleft'),
    (Code: 146; Name: 'quoteright'), (Code: 130; Name: 'quotesinglbase'), (Code: 39; Name: 'quotesingle'),
    (Code: 114; Name: 'r'), (Code: 174; Name: 'registered'), (Code: 115; Name: 's'), (Code: 154; Name: 'scaron'),
    (Code: 167; Name: 'section'), (Code: 59; Name: 'semicolon'), (Code: 55; Name: 'seven'), (Code: 54; Name: 'six'),
    (Code: 47; Name: 'slash'), (Code: 32; Name: 'space'), (Code: 163; Name: 'sterling'), (Code: 116; Name: 't'),
    (Code: 254; Name: 'thorn'), (Code: 51; Name: 'three'), (Code: 190; Name: 'threequarters'),
    (Code: 179; Name: 'threesuperior'), (Code: 152; Name: 'tilde'), (Code: 153; Name: 'trademark'),
    (Code: 50; Name: 'two'), (Code: 178; Name: 'twosuperior'), (Code: 117; Name: 'u'), (Code: 250; Name: 'uacute'),
    (Code: 251; Name: 'ucircumflex'), (Code: 252; Name: 'udieresis'), (Code: 249; Name: 'ugrave'),
    (Code: 95; Name: 'underscore'), (Code: 118; Name: 'v'), (Code: 119; Name: 'w'), (Code: 120; Name: 'x'),
    (Code: 121; Name: 'y'), (Code: 253; Name: 'yacute'), (Code: 255; Name: 'ydieresis'), (Code: 165; Name: 'yen'),
    (Code: 122; Name: 'z'), (Code: 158; Name: 'zcaron'), (Code: 48; Name: 'zero'), (Code: 160; Name: 'nbspace'),
    (Code: 173; Name: 'sfthyphen')
  );

  MacRomanTable: array[0..207] of TEntry = (
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
    (Code: 216; Name: 'ydieresis'), (Code: 180; Name: 'yen'), (Code: 122; Name: 'z'), (Code: 48; Name: 'zero'),
    (Code: 202; Name: 'nbspace')
  );

  MacOSRomanTable: array[0..15] of TEntry = (
    (Code: 173; Name: 'notequal'), (Code: 176; Name: 'infinity'), (Code: 178; Name: 'lessequal'),
    (Code: 179; Name: 'greaterequal'), (Code: 182; Name: 'partialdiff'), (Code: 183; Name: 'summation'),
    (Code: 184; Name: 'product'), (Code: 185; Name: 'pi'), (Code: 186; Name: 'integral'), (Code: 189; Name: 'Omega'),
    (Code: 195; Name: 'radical'), (Code: 197; Name: 'approxequal'), (Code: 198; Name: 'Delta'),
    (Code: 215; Name: 'lozenge'), (Code: 219; Name: 'Euro'), (Code: 240; Name: 'apple')
  );

  MacExpertTable: array[0..164] of TEntry = (
    (Code: 190; Name: 'AEsmall'), (Code: 135; Name: 'Aacutesmall'), (Code: 137; Name: 'Acircumflexsmall'),
    (Code: 39; Name: 'Acutesmall'), (Code: 138; Name: 'Adieresissmall'), (Code: 136; Name: 'Agravesmall'),
    (Code: 140; Name: 'Aringsmall'), (Code: 97; Name: 'Asmall'), (Code: 139; Name: 'Atildesmall'),
    (Code: 243; Name: 'Brevesmall'), (Code: 98; Name: 'Bsmall'), (Code: 174; Name: 'Caronsmall'),
    (Code: 141; Name: 'Ccedillasmall'), (Code: 201; Name: 'Cedillasmall'), (Code: 94; Name: 'Circumflexsmall'),
    (Code: 99; Name: 'Csmall'), (Code: 172; Name: 'Dieresissmall'), (Code: 250; Name: 'Dotaccentsmall'),
    (Code: 100; Name: 'Dsmall'), (Code: 142; Name: 'Eacutesmall'), (Code: 144; Name: 'Ecircumflexsmall'),
    (Code: 145; Name: 'Edieresissmall'), (Code: 143; Name: 'Egravesmall'), (Code: 101; Name: 'Esmall'),
    (Code: 68; Name: 'Ethsmall'), (Code: 102; Name: 'Fsmall'), (Code: 96; Name: 'Gravesmall'),
    (Code: 103; Name: 'Gsmall'), (Code: 104; Name: 'Hsmall'), (Code: 34; Name: 'Hungarumlautsmall'),
    (Code: 146; Name: 'Iacutesmall'), (Code: 148; Name: 'Icircumflexsmall'), (Code: 149; Name: 'Idieresissmall'),
    (Code: 147; Name: 'Igravesmall'), (Code: 105; Name: 'Ismall'), (Code: 106; Name: 'Jsmall'),
    (Code: 107; Name: 'Ksmall'), (Code: 194; Name: 'Lslashsmall'), (Code: 108; Name: 'Lsmall'),
    (Code: 244; Name: 'Macronsmall'), (Code: 109; Name: 'Msmall'), (Code: 110; Name: 'Nsmall'),
    (Code: 150; Name: 'Ntildesmall'), (Code: 207; Name: 'OEsmall'), (Code: 151; Name: 'Oacutesmall'),
    (Code: 153; Name: 'Ocircumflexsmall'), (Code: 154; Name: 'Odieresissmall'), (Code: 242; Name: 'Ogoneksmall'),
    (Code: 152; Name: 'Ogravesmall'), (Code: 191; Name: 'Oslashsmall'), (Code: 111; Name: 'Osmall'),
    (Code: 155; Name: 'Otildesmall'), (Code: 112; Name: 'Psmall'), (Code: 113; Name: 'Qsmall'),
    (Code: 251; Name: 'Ringsmall'), (Code: 114; Name: 'Rsmall'), (Code: 167; Name: 'Scaronsmall'),
    (Code: 115; Name: 'Ssmall'), (Code: 185; Name: 'Thornsmall'), (Code: 126; Name: 'Tildesmall'),
    (Code: 116; Name: 'Tsmall'), (Code: 156; Name: 'Uacutesmall'), (Code: 158; Name: 'Ucircumflexsmall'),
    (Code: 159; Name: 'Udieresissmall'), (Code: 157; Name: 'Ugravesmall'), (Code: 117; Name: 'Usmall'),
    (Code: 118; Name: 'Vsmall'), (Code: 119; Name: 'Wsmall'), (Code: 120; Name: 'Xsmall'),
    (Code: 180; Name: 'Yacutesmall'), (Code: 216; Name: 'Ydieresissmall'), (Code: 121; Name: 'Ysmall'),
    (Code: 189; Name: 'Zcaronsmall'), (Code: 122; Name: 'Zsmall'), (Code: 38; Name: 'ampersandsmall'),
    (Code: 129; Name: 'asuperior'), (Code: 245; Name: 'bsuperior'), (Code: 169; Name: 'centinferior'),
    (Code: 35; Name: 'centoldstyle'), (Code: 130; Name: 'centsuperior'), (Code: 58; Name: 'colon'),
    (Code: 123; Name: 'colonmonetary'), (Code: 44; Name: 'comma'), (Code: 178; Name: 'commainferior'),
    (Code: 248; Name: 'commasuperior'), (Code: 182; Name: 'dollarinferior'), (Code: 36; Name: 'dollaroldstyle'),
    (Code: 37; Name: 'dollarsuperior'), (Code: 235; Name: 'dsuperior'), (Code: 165; Name: 'eightinferior'),
    (Code: 56; Name: 'eightoldstyle'), (Code: 161; Name: 'eightsuperior'), (Code: 228; Name: 'esuperior'),
    (Code: 214; Name: 'exclamdownsmall'), (Code: 33; Name: 'exclamsmall'), (Code: 86; Name: 'ff'),
    (Code: 89; Name: 'ffi'), (Code: 90; Name: 'ffl'), (Code: 87; Name: 'fi'), (Code: 208; Name: 'figuredash'),
    (Code: 76; Name: 'fiveeighths'), (Code: 176; Name: 'fiveinferior'), (Code: 53; Name: 'fiveoldstyle'),
    (Code: 222; Name: 'fivesuperior'), (Code: 88; Name: 'fl'), (Code: 162; Name: 'fourinferior'),
    (Code: 52; Name: 'fouroldstyle'), (Code: 221; Name: 'foursuperior'), (Code: 47; Name: 'fraction'),
    (Code: 45; Name: 'hyphen'), (Code: 95; Name: 'hypheninferior'), (Code: 209; Name: 'hyphensuperior'),
    (Code: 233; Name: 'isuperior'), (Code: 241; Name: 'lsuperior'), (Code: 247; Name: 'msuperior'),
    (Code: 187; Name: 'nineinferior'), (Code: 57; Name: 'nineoldstyle'), (Code: 225; Name: 'ninesuperior'),
    (Code: 246; Name: 'nsuperior'), (Code: 43; Name: 'onedotenleader'), (Code: 74; Name: 'oneeighth'),
    (Code: 124; Name: 'onefitted'), (Code: 72; Name: 'onehalf'), (Code: 193; Name: 'oneinferior'),
    (Code: 49; Name: 'oneoldstyle'), (Code: 71; Name: 'onequarter'), (Code: 218; Name: 'onesuperior'),
    (Code: 78; Name: 'onethird'), (Code: 175; Name: 'osuperior'), (Code: 91; Name: 'parenleftinferior'),
    (Code: 40; Name: 'parenleftsuperior'), (Code: 93; Name: 'parenrightinferior'),
    (Code: 41; Name: 'parenrightsuperior'), (Code: 46; Name: 'period'), (Code: 179; Name: 'periodinferior'),
    (Code: 249; Name: 'periodsuperior'), (Code: 192; Name: 'questiondownsmall'), (Code: 63; Name: 'questionsmall'),
    (Code: 229; Name: 'rsuperior'), (Code: 125; Name: 'rupiah'), (Code: 59; Name: 'semicolon'),
    (Code: 77; Name: 'seveneighths'), (Code: 166; Name: 'seveninferior'), (Code: 55; Name: 'sevenoldstyle'),
    (Code: 224; Name: 'sevensuperior'), (Code: 164; Name: 'sixinferior'), (Code: 54; Name: 'sixoldstyle'),
    (Code: 223; Name: 'sixsuperior'), (Code: 32; Name: 'space'), (Code: 234; Name: 'ssuperior'),
    (Code: 75; Name: 'threeeighths'), (Code: 163; Name: 'threeinferior'), (Code: 51; Name: 'threeoldstyle'),
    (Code: 73; Name: 'threequarters'), (Code: 61; Name: 'threequartersemdash'), (Code: 220; Name: 'threesuperior'),
    (Code: 230; Name: 'tsuperior'), (Code: 42; Name: 'twodotenleader'), (Code: 170; Name: 'twoinferior'),
    (Code: 50; Name: 'twooldstyle'), (Code: 219; Name: 'twosuperior'), (Code: 79; Name: 'twothirds'),
    (Code: 188; Name: 'zeroinferior'), (Code: 48; Name: 'zerooldstyle'), (Code: 226; Name: 'zerosuperior')
  );

  SymbolTable: array[0..188] of TEntry = (
    (Code: 65; Name: 'Alpha'), (Code: 66; Name: 'Beta'), (Code: 67; Name: 'Chi'), (Code: 68; Name: 'Delta'),
    (Code: 69; Name: 'Epsilon'), (Code: 72; Name: 'Eta'), (Code: 160; Name: 'Euro'), (Code: 71; Name: 'Gamma'),
    (Code: 193; Name: 'Ifraktur'), (Code: 73; Name: 'Iota'), (Code: 75; Name: 'Kappa'), (Code: 76; Name: 'Lambda'),
    (Code: 77; Name: 'Mu'), (Code: 78; Name: 'Nu'), (Code: 87; Name: 'Omega'), (Code: 79; Name: 'Omicron'),
    (Code: 70; Name: 'Phi'), (Code: 80; Name: 'Pi'), (Code: 89; Name: 'Psi'), (Code: 194; Name: 'Rfraktur'),
    (Code: 82; Name: 'Rho'), (Code: 83; Name: 'Sigma'), (Code: 84; Name: 'Tau'), (Code: 81; Name: 'Theta'),
    (Code: 85; Name: 'Upsilon'), (Code: 161; Name: 'Upsilon1'), (Code: 88; Name: 'Xi'), (Code: 90; Name: 'Zeta'),
    (Code: 192; Name: 'aleph'), (Code: 97; Name: 'alpha'), (Code: 38; Name: 'ampersand'), (Code: 208; Name: 'angle'),
    (Code: 225; Name: 'angleleft'), (Code: 241; Name: 'angleright'), (Code: 187; Name: 'approxequal'),
    (Code: 171; Name: 'arrowboth'), (Code: 219; Name: 'arrowdblboth'), (Code: 223; Name: 'arrowdbldown'),
    (Code: 220; Name: 'arrowdblleft'), (Code: 222; Name: 'arrowdblright'), (Code: 221; Name: 'arrowdblup'),
    (Code: 175; Name: 'arrowdown'), (Code: 190; Name: 'arrowhorizex'), (Code: 172; Name: 'arrowleft'),
    (Code: 174; Name: 'arrowright'), (Code: 173; Name: 'arrowup'), (Code: 189; Name: 'arrowvertex'),
    (Code: 42; Name: 'asteriskmath'), (Code: 124; Name: 'bar'), (Code: 98; Name: 'beta'),
    (Code: 123; Name: 'braceleft'), (Code: 125; Name: 'braceright'), (Code: 236; Name: 'bracelefttp'),
    (Code: 237; Name: 'braceleftmid'), (Code: 238; Name: 'braceleftbt'), (Code: 252; Name: 'bracerighttp'),
    (Code: 253; Name: 'bracerightmid'), (Code: 254; Name: 'bracerightbt'), (Code: 239; Name: 'braceex'),
    (Code: 91; Name: 'bracketleft'), (Code: 93; Name: 'bracketright'), (Code: 233; Name: 'bracketlefttp'),
    (Code: 234; Name: 'bracketleftex'), (Code: 235; Name: 'bracketleftbt'), (Code: 249; Name: 'bracketrighttp'),
    (Code: 250; Name: 'bracketrightex'), (Code: 251; Name: 'bracketrightbt'), (Code: 183; Name: 'bullet'),
    (Code: 191; Name: 'carriagereturn'), (Code: 99; Name: 'chi'), (Code: 196; Name: 'circlemultiply'),
    (Code: 197; Name: 'circleplus'), (Code: 167; Name: 'club'), (Code: 58; Name: 'colon'), (Code: 44; Name: 'comma'),
    (Code: 64; Name: 'congruent'), (Code: 227; Name: 'copyrightsans'), (Code: 211; Name: 'copyrightserif'),
    (Code: 176; Name: 'degree'), (Code: 100; Name: 'delta'), (Code: 168; Name: 'diamond'),
    (Code: 184; Name: 'divide'), (Code: 215; Name: 'dotmath'), (Code: 56; Name: 'eight'),
    (Code: 206; Name: 'element'), (Code: 188; Name: 'ellipsis'), (Code: 198; Name: 'emptyset'),
    (Code: 101; Name: 'epsilon'), (Code: 61; Name: 'equal'), (Code: 186; Name: 'equivalence'),
    (Code: 104; Name: 'eta'), (Code: 33; Name: 'exclam'), (Code: 36; Name: 'existential'), (Code: 53; Name: 'five'),
    (Code: 166; Name: 'florin'), (Code: 52; Name: 'four'), (Code: 164; Name: 'fraction'), (Code: 103; Name: 'gamma'),
    (Code: 209; Name: 'gradient'), (Code: 62; Name: 'greater'), (Code: 179; Name: 'greaterequal'),
    (Code: 169; Name: 'heart'), (Code: 165; Name: 'infinity'), (Code: 242; Name: 'integral'),
    (Code: 243; Name: 'integraltp'), (Code: 244; Name: 'integralex'), (Code: 245; Name: 'integralbt'),
    (Code: 199; Name: 'intersection'), (Code: 105; Name: 'iota'), (Code: 107; Name: 'kappa'),
    (Code: 108; Name: 'lambda'), (Code: 60; Name: 'less'), (Code: 163; Name: 'lessequal'),
    (Code: 217; Name: 'logicaland'), (Code: 216; Name: 'logicalnot'), (Code: 218; Name: 'logicalor'),
    (Code: 224; Name: 'lozenge'), (Code: 45; Name: 'minus'), (Code: 162; Name: 'minute'), (Code: 109; Name: 'mu'),
    (Code: 180; Name: 'multiply'), (Code: 57; Name: 'nine'), (Code: 207; Name: 'notelement'),
    (Code: 185; Name: 'notequal'), (Code: 203; Name: 'notsubset'), (Code: 110; Name: 'nu'),
    (Code: 35; Name: 'numbersign'), (Code: 119; Name: 'omega'), (Code: 118; Name: 'omega1'),
    (Code: 111; Name: 'omicron'), (Code: 49; Name: 'one'), (Code: 40; Name: 'parenleft'),
    (Code: 41; Name: 'parenright'), (Code: 230; Name: 'parenlefttp'), (Code: 231; Name: 'parenleftex'),
    (Code: 232; Name: 'parenleftbt'), (Code: 246; Name: 'parenrighttp'), (Code: 247; Name: 'parenrightex'),
    (Code: 248; Name: 'parenrightbt'), (Code: 182; Name: 'partialdiff'), (Code: 37; Name: 'percent'),
    (Code: 46; Name: 'period'), (Code: 94; Name: 'perpendicular'), (Code: 102; Name: 'phi'),
    (Code: 106; Name: 'phi1'), (Code: 112; Name: 'pi'), (Code: 43; Name: 'plus'), (Code: 177; Name: 'plusminus'),
    (Code: 213; Name: 'product'), (Code: 204; Name: 'propersubset'), (Code: 201; Name: 'propersuperset'),
    (Code: 181; Name: 'proportional'), (Code: 121; Name: 'psi'), (Code: 63; Name: 'question'),
    (Code: 214; Name: 'radical'), (Code: 96; Name: 'radicalex'), (Code: 205; Name: 'reflexsubset'),
    (Code: 202; Name: 'reflexsuperset'), (Code: 226; Name: 'registersans'), (Code: 210; Name: 'registerserif'),
    (Code: 114; Name: 'rho'), (Code: 178; Name: 'second'), (Code: 59; Name: 'semicolon'), (Code: 55; Name: 'seven'),
    (Code: 115; Name: 'sigma'), (Code: 86; Name: 'sigma1'), (Code: 126; Name: 'similar'), (Code: 54; Name: 'six'),
    (Code: 47; Name: 'slash'), (Code: 32; Name: 'space'), (Code: 170; Name: 'spade'), (Code: 39; Name: 'suchthat'),
    (Code: 229; Name: 'summation'), (Code: 116; Name: 'tau'), (Code: 92; Name: 'therefore'),
    (Code: 113; Name: 'theta'), (Code: 74; Name: 'theta1'), (Code: 51; Name: 'three'),
    (Code: 228; Name: 'trademarksans'), (Code: 212; Name: 'trademarkserif'), (Code: 50; Name: 'two'),
    (Code: 95; Name: 'underscore'), (Code: 200; Name: 'union'), (Code: 34; Name: 'universal'),
    (Code: 117; Name: 'upsilon'), (Code: 195; Name: 'weierstrass'), (Code: 120; Name: 'xi'), (Code: 48; Name: 'zero'),
    (Code: 122; Name: 'zeta')
  );

  ZapfDingbatsTable: array[0..187] of TEntry = (
    (Code: 32; Name: 'space'), (Code: 33; Name: 'a1'), (Code: 34; Name: 'a2'), (Code: 35; Name: 'a202'),
    (Code: 36; Name: 'a3'), (Code: 37; Name: 'a4'), (Code: 38; Name: 'a5'), (Code: 39; Name: 'a119'),
    (Code: 40; Name: 'a118'), (Code: 41; Name: 'a117'), (Code: 42; Name: 'a11'), (Code: 43; Name: 'a12'),
    (Code: 44; Name: 'a13'), (Code: 45; Name: 'a14'), (Code: 46; Name: 'a15'), (Code: 47; Name: 'a16'),
    (Code: 48; Name: 'a105'), (Code: 49; Name: 'a17'), (Code: 50; Name: 'a18'), (Code: 51; Name: 'a19'),
    (Code: 52; Name: 'a20'), (Code: 53; Name: 'a21'), (Code: 54; Name: 'a22'), (Code: 55; Name: 'a23'),
    (Code: 56; Name: 'a24'), (Code: 57; Name: 'a25'), (Code: 58; Name: 'a26'), (Code: 59; Name: 'a27'),
    (Code: 60; Name: 'a28'), (Code: 61; Name: 'a6'), (Code: 62; Name: 'a7'), (Code: 63; Name: 'a8'),
    (Code: 64; Name: 'a9'), (Code: 65; Name: 'a10'), (Code: 66; Name: 'a29'), (Code: 67; Name: 'a30'),
    (Code: 68; Name: 'a31'), (Code: 69; Name: 'a32'), (Code: 70; Name: 'a33'), (Code: 71; Name: 'a34'),
    (Code: 72; Name: 'a35'), (Code: 73; Name: 'a36'), (Code: 74; Name: 'a37'), (Code: 75; Name: 'a38'),
    (Code: 76; Name: 'a39'), (Code: 77; Name: 'a40'), (Code: 78; Name: 'a41'), (Code: 79; Name: 'a42'),
    (Code: 80; Name: 'a43'), (Code: 81; Name: 'a44'), (Code: 82; Name: 'a45'), (Code: 83; Name: 'a46'),
    (Code: 84; Name: 'a47'), (Code: 85; Name: 'a48'), (Code: 86; Name: 'a49'), (Code: 87; Name: 'a50'),
    (Code: 88; Name: 'a51'), (Code: 89; Name: 'a52'), (Code: 90; Name: 'a53'), (Code: 91; Name: 'a54'),
    (Code: 92; Name: 'a55'), (Code: 93; Name: 'a56'), (Code: 94; Name: 'a57'), (Code: 95; Name: 'a58'),
    (Code: 96; Name: 'a59'), (Code: 97; Name: 'a60'), (Code: 98; Name: 'a61'), (Code: 99; Name: 'a62'),
    (Code: 100; Name: 'a63'), (Code: 101; Name: 'a64'), (Code: 102; Name: 'a65'), (Code: 103; Name: 'a66'),
    (Code: 104; Name: 'a67'), (Code: 105; Name: 'a68'), (Code: 106; Name: 'a69'), (Code: 107; Name: 'a70'),
    (Code: 108; Name: 'a71'), (Code: 109; Name: 'a72'), (Code: 110; Name: 'a73'), (Code: 111; Name: 'a74'),
    (Code: 112; Name: 'a203'), (Code: 113; Name: 'a75'), (Code: 114; Name: 'a204'), (Code: 115; Name: 'a76'),
    (Code: 116; Name: 'a77'), (Code: 117; Name: 'a78'), (Code: 118; Name: 'a79'), (Code: 119; Name: 'a81'),
    (Code: 120; Name: 'a82'), (Code: 121; Name: 'a83'), (Code: 122; Name: 'a84'), (Code: 123; Name: 'a97'),
    (Code: 124; Name: 'a98'), (Code: 125; Name: 'a99'), (Code: 126; Name: 'a100'), (Code: 161; Name: 'a101'),
    (Code: 162; Name: 'a102'), (Code: 163; Name: 'a103'), (Code: 164; Name: 'a104'), (Code: 165; Name: 'a106'),
    (Code: 166; Name: 'a107'), (Code: 167; Name: 'a108'), (Code: 168; Name: 'a112'), (Code: 169; Name: 'a111'),
    (Code: 170; Name: 'a110'), (Code: 171; Name: 'a109'), (Code: 172; Name: 'a120'), (Code: 173; Name: 'a121'),
    (Code: 174; Name: 'a122'), (Code: 175; Name: 'a123'), (Code: 176; Name: 'a124'), (Code: 177; Name: 'a125'),
    (Code: 178; Name: 'a126'), (Code: 179; Name: 'a127'), (Code: 180; Name: 'a128'), (Code: 181; Name: 'a129'),
    (Code: 182; Name: 'a130'), (Code: 183; Name: 'a131'), (Code: 184; Name: 'a132'), (Code: 185; Name: 'a133'),
    (Code: 186; Name: 'a134'), (Code: 187; Name: 'a135'), (Code: 188; Name: 'a136'), (Code: 189; Name: 'a137'),
    (Code: 190; Name: 'a138'), (Code: 191; Name: 'a139'), (Code: 192; Name: 'a140'), (Code: 193; Name: 'a141'),
    (Code: 194; Name: 'a142'), (Code: 195; Name: 'a143'), (Code: 196; Name: 'a144'), (Code: 197; Name: 'a145'),
    (Code: 198; Name: 'a146'), (Code: 199; Name: 'a147'), (Code: 200; Name: 'a148'), (Code: 201; Name: 'a149'),
    (Code: 202; Name: 'a150'), (Code: 203; Name: 'a151'), (Code: 204; Name: 'a152'), (Code: 205; Name: 'a153'),
    (Code: 206; Name: 'a154'), (Code: 207; Name: 'a155'), (Code: 208; Name: 'a156'), (Code: 209; Name: 'a157'),
    (Code: 210; Name: 'a158'), (Code: 211; Name: 'a159'), (Code: 212; Name: 'a160'), (Code: 213; Name: 'a161'),
    (Code: 214; Name: 'a163'), (Code: 215; Name: 'a164'), (Code: 216; Name: 'a196'), (Code: 217; Name: 'a165'),
    (Code: 218; Name: 'a192'), (Code: 219; Name: 'a166'), (Code: 220; Name: 'a167'), (Code: 221; Name: 'a168'),
    (Code: 222; Name: 'a169'), (Code: 223; Name: 'a170'), (Code: 224; Name: 'a171'), (Code: 225; Name: 'a172'),
    (Code: 226; Name: 'a173'), (Code: 227; Name: 'a162'), (Code: 228; Name: 'a174'), (Code: 229; Name: 'a175'),
    (Code: 230; Name: 'a176'), (Code: 231; Name: 'a177'), (Code: 232; Name: 'a178'), (Code: 233; Name: 'a179'),
    (Code: 234; Name: 'a193'), (Code: 235; Name: 'a180'), (Code: 236; Name: 'a199'), (Code: 237; Name: 'a181'),
    (Code: 238; Name: 'a200'), (Code: 239; Name: 'a182'), (Code: 241; Name: 'a201'), (Code: 242; Name: 'a183'),
    (Code: 243; Name: 'a184'), (Code: 244; Name: 'a197'), (Code: 245; Name: 'a185'), (Code: 246; Name: 'a194'),
    (Code: 247; Name: 'a198'), (Code: 248; Name: 'a186'), (Code: 249; Name: 'a195'), (Code: 250; Name: 'a187'),
    (Code: 251; Name: 'a188'), (Code: 252; Name: 'a189'), (Code: 253; Name: 'a190'), (Code: 254; Name: 'a191')
  );

{ TStandardEncoding }

class destructor TStandardEncoding.Destroy;
begin
  FShared.Release;
end;

constructor TStandardEncoding.Create;
begin
  inherited Create;
  for var Entry in StandardTable do
  begin
    Add(Entry.Code, Entry.Name);
  end;
end;

class function TStandardEncoding.Instance: TStandardEncoding;
begin
  Result := FShared.Get(
    function: TStandardEncoding
    begin
      Result := TStandardEncoding.Create;
    end);
end;

function TStandardEncoding.EncodingName: string;
begin
  Result := 'StandardEncoding';
end;

{ TWinAnsiEncoding }

class destructor TWinAnsiEncoding.Destroy;
begin
  FShared.Release;
end;

constructor TWinAnsiEncoding.Create;
begin
  inherited Create;
  for var Entry in WinAnsiTable do
  begin
    Add(Entry.Code, Entry.Name);
  end;
  // From the PDF specification: in WinAnsiEncoding all unused codes greater than 40 (octal) map to the bullet character
  for var Code := FirstWinAnsiBulletCode to LastWinAnsiBulletCode do
  begin
    if not Contains(Code) then
    begin
      Add(Code, 'bullet');
    end;
  end;
end;

class function TWinAnsiEncoding.Instance: TWinAnsiEncoding;
begin
  Result := FShared.Get(
    function: TWinAnsiEncoding
    begin
      Result := TWinAnsiEncoding.Create;
    end);
end;

function TWinAnsiEncoding.EncodingName: string;
begin
  Result := 'WinAnsiEncoding';
end;

{ TMacRomanEncoding }

class destructor TMacRomanEncoding.Destroy;
begin
  FShared.Release;
end;

constructor TMacRomanEncoding.Create;
begin
  inherited Create;
  for var Entry in MacRomanTable do
  begin
    Add(Entry.Code, Entry.Name);
  end;
end;

class function TMacRomanEncoding.Instance: TMacRomanEncoding;
begin
  Result := FShared.Get(
    function: TMacRomanEncoding
    begin
      Result := TMacRomanEncoding.Create;
    end);
end;

function TMacRomanEncoding.EncodingName: string;
begin
  Result := 'MacRomanEncoding';
end;

{ TMacOSRomanEncoding }

class destructor TMacOSRomanEncoding.Destroy;
begin
  FSharedMacOS.Release;
end;

constructor TMacOSRomanEncoding.Create;
begin
  inherited Create;
  // Differences and additions to MacRomanEncoding
  for var Entry in MacOSRomanTable do
  begin
    Add(Entry.Code, Entry.Name);
  end;
end;

class function TMacOSRomanEncoding.Instance: TMacOSRomanEncoding;
begin
  Result := FSharedMacOS.Get(
    function: TMacOSRomanEncoding
    begin
      Result := TMacOSRomanEncoding.Create;
    end);
end;

{ TMacExpertEncoding }

class destructor TMacExpertEncoding.Destroy;
begin
  FShared.Release;
end;

constructor TMacExpertEncoding.Create;
begin
  inherited Create;
  for var Entry in MacExpertTable do
  begin
    Add(Entry.Code, Entry.Name);
  end;
end;

class function TMacExpertEncoding.Instance: TMacExpertEncoding;
begin
  Result := FShared.Get(
    function: TMacExpertEncoding
    begin
      Result := TMacExpertEncoding.Create;
    end);
end;

function TMacExpertEncoding.EncodingName: string;
begin
  Result := 'MacExpertEncoding';
end;

{ TSymbolEncoding }

class destructor TSymbolEncoding.Destroy;
begin
  FShared.Release;
end;

constructor TSymbolEncoding.Create;
begin
  inherited Create;
  for var Entry in SymbolTable do
  begin
    Add(Entry.Code, Entry.Name);
  end;
end;

class function TSymbolEncoding.Instance: TSymbolEncoding;
begin
  Result := FShared.Get(
    function: TSymbolEncoding
    begin
      Result := TSymbolEncoding.Create;
    end);
end;

function TSymbolEncoding.EncodingName: string;
begin
  Result := 'SymbolEncoding';
end;

{ TZapfDingbatsEncoding }

class destructor TZapfDingbatsEncoding.Destroy;
begin
  FShared.Release;
end;

constructor TZapfDingbatsEncoding.Create;
begin
  inherited Create;
  for var Entry in ZapfDingbatsTable do
  begin
    Add(Entry.Code, Entry.Name);
  end;
end;

class function TZapfDingbatsEncoding.Instance: TZapfDingbatsEncoding;
begin
  Result := FShared.Get(
    function: TZapfDingbatsEncoding
    begin
      Result := TZapfDingbatsEncoding.Create;
    end);
end;

function TZapfDingbatsEncoding.EncodingName: string;
begin
  Result := 'ZapfDingbatsEncoding';
end;

end.
