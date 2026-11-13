// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/font/FontInfo.java, FontProvider.java and FontFormat.java (3.0.8)
unit Pdf4D.Font.Provider;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.FontBox.FontBoxFont,
  Pdf4D.Font.Descriptor;

type
  {$SCOPEDENUMS ON}
  TFontFormat = (TTF, OTF, PFB);
  {$SCOPEDENUMS OFF}

  // Information about a font that a provider has found. The provider owns its infos.
  TFontInfo = class abstract
  public
    function PostScriptName: string; virtual; abstract;
    function Format: TFontFormat; virtual; abstract;
    // False when the font has no CIDSystemInfo
    function TryGetCIDSystemInfo(out Info: TPDCIDSystemInfo): Boolean; virtual; abstract;
    // The font is shared: the info keeps it and the caller does not free it. It is fully read and does not change. Raises
    // EPdfParseException when the font file cannot be read.
    function GetFont: TFontBoxFont; virtual; abstract;
    // The sFamilyClass field of the "OS/2" table, or -1
    function FamilyClass: Integer; virtual; abstract;
    // The usWeightClass field of the "OS/2" table, or -1
    function WeightClass: Integer; virtual; abstract;
    // The ulCodePageRange1 field of the "OS/2" table as a signed 32-bit value, or 0
    function CodePageRange1: Integer; virtual; abstract;
    function CodePageRange2: Integer; virtual; abstract;
    // The macStyle field of the "head" table, or -1
    function MacStyle: Integer; virtual; abstract;
    // False when the font has no PANOSE classification
    function TryGetPanose(out Panose: TPDPanoseClassification): Boolean; virtual; abstract;

    // The usWeightClass as a PANOSE weight
    function WeightClassAsPanose: Integer;
    // Both code page range fields as one 64-bit value
    function CodePageRange: Int64;
    function ToString: string; override;
  end;

  IPdfFontProvider = interface
    ['{5F0B8E2C-3D1A-4C77-9A58-6E21B4D0C913}']
    // The infos belong to the provider and live as long as the provider does
    function FontInfos: TArray<TFontInfo>;
    function ToDebugString: string;
  end;

implementation

uses
  System.TypInfo;

// Like Integer.toHexString: lower case, and a negative value as 32 bits
function HexOf(const Value: Integer): string;
begin
  Result := IntToHex(Value, 1).ToLowerInvariant;
end;

{ TFontInfo }

function TFontInfo.WeightClassAsPanose: Integer;
begin
  case WeightClass of
    100 : Result := 2;
    200 : Result := 3;
    300 : Result := 4;
    400 : Result := 5;
    500 : Result := 6;
    600 : Result := 7;
    700 : Result := 8;
    800 : Result := 9;
    900 : Result := 10;
  else
    Result := 0;
  end;
end;

function TFontInfo.CodePageRange: Int64;
begin
  const Range1 = Int64(Cardinal(CodePageRange1));
  const Range2 = Int64(Cardinal(CodePageRange2));
  Result := (Range2 shl 32) or Range1;
end;

function TFontInfo.ToString: string;
begin
  var Info: TPDCIDSystemInfo;
  var CIDText := 'null';
  if TryGetCIDSystemInfo(Info) then
  begin
    CIDText := Info.ToString;
  end;

  const FormatName = GetEnumName(TypeInfo(TFontFormat), Ord(Format));
  Result := System.SysUtils.Format('%s (%s, mac: 0x%s, os/2: 0x%s, cid: %s)',
                                   [PostScriptName, FormatName, HexOf(MacStyle), HexOf(FamilyClass), CIDText]);
end;

end.
