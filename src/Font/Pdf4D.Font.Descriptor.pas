// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/font/PDFontDescriptor.java (3.0.8), the read side
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/font/PDPanose.java and PDPanoseClassification.java (3.0.8)
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/font/PDCIDSystemInfo.java and CIDSystemInfo.java (3.0.8)
unit Pdf4D.Font.Descriptor;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Model.Rectangle;

type
  // The 10 PANOSE bytes. A PDF byte is read as signed, like a Java byte.
  TPDPanoseClassification = record
  public
    const Length = 10;

  public
    Bytes: TBytes;

    function FamilyKind: Integer;
    function SerifStyle: Integer;
    function Weight: Integer;
    function Proportion: Integer;
    function Contrast: Integer;
    function StrokeVariation: Integer;
    function ArmStyle: Integer;
    function Letterform: Integer;
    function Midline: Integer;
    function XHeight: Integer;
    function ToString: string;

  private
    function SignedByte(const Index: Integer): Integer;
  end;

  // The "Panose" entry of the Style dictionary of a font descriptor: 12 bytes, the sFamilyClass and the PANOSE bytes
  TPDPanose = record
  public
    const Length = 12;

  public
    Bytes: TBytes;

    function FamilyClass: Integer;
    function Panose: TPDPanoseClassification;
  end;

  // The registry, ordering and supplement of a character collection, for example Adobe-Japan1-6. An absent registry or
  // ordering is an empty string.
  TPDCIDSystemInfo = record
    Registry: string;
    Ordering: string;
    Supplement: Integer;

    class function Create(const Registry, Ordering: string; const Supplement: Integer): TPDCIDSystemInfo; static;
    // Port of the PDCIDSystemInfo(COSDictionary) getters. False when there is no dictionary.
    class function TryFromDictionary(const Dictionary: TCosDictionary; out Info: TPDCIDSystemInfo): Boolean; static;

    function ToString: string;
  end;

  // Wraps the font descriptor dictionary. The dictionary belongs to the document and must outlive the descriptor.
  TPDFontDescriptor = class
  private
    const FlagFixedPitch = 1;
    const FlagSerif = 2;
    const FlagSymbolic = 4;
    const FlagScript = 8;
    const FlagNonSymbolic = 32;
    const FlagItalic = 64;
    const FlagAllCap = 65536;
    const FlagSmallCap = 131072;
    const FlagForceBold = 262144;

  private
    FDictionary: TCosDictionary;

    function IsFlagBitOn(const Bit: Integer): Boolean;

  public
    constructor Create(const Dictionary: TCosDictionary);

    function IsFixedPitch: Boolean;
    function IsSerif: Boolean;
    function IsSymbolic: Boolean;
    function IsScript: Boolean;
    function IsNonSymbolic: Boolean;
    function IsItalic: Boolean;
    function IsAllCap: Boolean;
    function IsSmallCap: Boolean;
    function IsForceBold: Boolean;

    function Flags: Integer;
    // Empty when the descriptor has no name
    function FontName: string;
    // Empty when the descriptor has no family
    function FontFamily: string;
    function FontStretch: string;
    function FontWeight: Single;
    function TryGetFontBoundingBox(out Box: TPdfRectangle): Boolean;
    function ItalicAngle: Single;
    function Ascent: Single;
    function Descent: Single;
    function Leading: Single;
    // A negative value in the file is made positive, like PDFBox does (PDFBOX-429)
    function CapHeight: Single;
    function XHeight: Single;
    function StemV: Single;
    function StemH: Single;
    function AverageWidth: Single;
    function MaxWidth: Single;
    function HasWidths: Boolean;
    function HasMissingWidth: Boolean;
    function MissingWidth: Single;
    function CharSet: string;

    function TryGetFontFile(out Stream: TCosStream): Boolean;
    function TryGetFontFile2(out Stream: TCosStream): Boolean;
    function TryGetFontFile3(out Stream: TCosStream): Boolean;
    function TryGetCIDSet(out Stream: TCosStream): Boolean;
    // False when there is no Style dictionary, no Panose string or fewer than 12 bytes
    function TryGetPanose(out Panose: TPDPanose): Boolean;

    property CosObject: TCosDictionary read FDictionary;
  end;

implementation

uses
  System.Math,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Cos.PdfString;

{ TPDPanoseClassification }

function TPDPanoseClassification.SignedByte(const Index: Integer): Integer;
begin
  if Index < System.Length(Bytes) then
  begin
    Result := ShortInt(Bytes[Index]);
  end
  else
  begin
    Result := 0;
  end;
end;

function TPDPanoseClassification.FamilyKind: Integer;
begin
  Result := SignedByte(0);
end;

function TPDPanoseClassification.SerifStyle: Integer;
begin
  Result := SignedByte(1);
end;

function TPDPanoseClassification.Weight: Integer;
begin
  Result := SignedByte(2);
end;

function TPDPanoseClassification.Proportion: Integer;
begin
  Result := SignedByte(3);
end;

function TPDPanoseClassification.Contrast: Integer;
begin
  Result := SignedByte(4);
end;

function TPDPanoseClassification.StrokeVariation: Integer;
begin
  Result := SignedByte(5);
end;

function TPDPanoseClassification.ArmStyle: Integer;
begin
  Result := SignedByte(6);
end;

function TPDPanoseClassification.Letterform: Integer;
begin
  Result := SignedByte(7);
end;

function TPDPanoseClassification.Midline: Integer;
begin
  Result := SignedByte(8);
end;

function TPDPanoseClassification.XHeight: Integer;
begin
  Result := SignedByte(9);
end;

function TPDPanoseClassification.ToString: string;
begin
  Result := Format('{ FamilyKind = %d, SerifStyle = %d, Weight = %d, Proportion = %d, Contrast = %d, StrokeVariation = %d, ' +
                   'ArmStyle = %d, Letterform = %d, Midline = %d, XHeight = %d}',
                   [FamilyKind, SerifStyle, Weight, Proportion, Contrast, StrokeVariation, ArmStyle, Letterform, Midline, XHeight]);
end;

{ TPDPanose }

function TPDPanose.FamilyClass: Integer;
begin
  const IsComplete = (System.Length(Bytes) >= Length);
  if not IsComplete then
  begin
    Exit(0);
  end;

  const HighByte = Integer(ShortInt(Bytes[0]));
  Result := HighByte * 256 + Bytes[1];
end;

function TPDPanose.Panose: TPDPanoseClassification;
begin
  Result.Bytes := nil;
  const IsComplete = (System.Length(Bytes) >= Length);
  if IsComplete then
  begin
    Result.Bytes := Copy(Bytes, 2, TPDPanoseClassification.Length);
  end;
end;

{ TPDCIDSystemInfo }

class function TPDCIDSystemInfo.Create(const Registry, Ordering: string; const Supplement: Integer): TPDCIDSystemInfo;
begin
  Result.Registry := Registry;
  Result.Ordering := Ordering;
  Result.Supplement := Supplement;
end;

class function TPDCIDSystemInfo.TryFromDictionary(const Dictionary: TCosDictionary; out Info: TPDCIDSystemInfo): Boolean;
begin
  Info := TPDCIDSystemInfo.Create('', '', -1);
  Result := Assigned(Dictionary);
  if not Result then
  begin
    Exit;
  end;

  Info.Registry := Dictionary.GetNameAsString(TCosNames.Registry, '');
  Info.Ordering := Dictionary.GetNameAsString(TCosNames.Ordering, '');
  Info.Supplement := Dictionary.GetInt(TCosNames.Supplement, -1);
end;

function TPDCIDSystemInfo.ToString: string;
begin
  Result := Format('%s-%s-%d', [Registry, Ordering, Supplement]);
end;

{ TPDFontDescriptor }

constructor TPDFontDescriptor.Create(const Dictionary: TCosDictionary);
begin
  inherited Create;
  if not Assigned(Dictionary) then
  begin
    raise EArgumentNilException.Create('The font descriptor needs a dictionary');
  end;
  FDictionary := Dictionary;
end;

function TPDFontDescriptor.Flags: Integer;
begin
  Result := FDictionary.GetInt(TCosNames.Flags, 0);
end;

function TPDFontDescriptor.IsFlagBitOn(const Bit: Integer): Boolean;
begin
  Result := ((Flags and Bit) <> 0);
end;

function TPDFontDescriptor.IsFixedPitch: Boolean;
begin
  Result := IsFlagBitOn(FlagFixedPitch);
end;

function TPDFontDescriptor.IsSerif: Boolean;
begin
  Result := IsFlagBitOn(FlagSerif);
end;

function TPDFontDescriptor.IsSymbolic: Boolean;
begin
  Result := IsFlagBitOn(FlagSymbolic);
end;

function TPDFontDescriptor.IsScript: Boolean;
begin
  Result := IsFlagBitOn(FlagScript);
end;

function TPDFontDescriptor.IsNonSymbolic: Boolean;
begin
  Result := IsFlagBitOn(FlagNonSymbolic);
end;

function TPDFontDescriptor.IsItalic: Boolean;
begin
  Result := IsFlagBitOn(FlagItalic);
end;

function TPDFontDescriptor.IsAllCap: Boolean;
begin
  Result := IsFlagBitOn(FlagAllCap);
end;

function TPDFontDescriptor.IsSmallCap: Boolean;
begin
  Result := IsFlagBitOn(FlagSmallCap);
end;

function TPDFontDescriptor.IsForceBold: Boolean;
begin
  Result := IsFlagBitOn(FlagForceBold);
end;

function TPDFontDescriptor.FontName: string;
begin
  Result := FDictionary.GetNameAsString(TCosNames.FontName, '');
end;

function TPDFontDescriptor.FontFamily: string;
begin
  Result := FDictionary.GetString(TCosNames.FontFamily, '');
end;

function TPDFontDescriptor.FontStretch: string;
begin
  Result := FDictionary.GetNameAsString(TCosNames.FontStretch, '');
end;

function TPDFontDescriptor.FontWeight: Single;
begin
  Result := FDictionary.GetFloat(TCosNames.FontWeight, 0);
end;

function TPDFontDescriptor.TryGetFontBoundingBox(out Box: TPdfRectangle): Boolean;
begin
  var Values: TCosArray;
  Result := FDictionary.TryGetCosArray(TCosNames.FontBBox, Values);
  if Result then
  begin
    Box := TPdfRectangle.FromCosArray(Values);
  end
  else
  begin
    Box := Default(TPdfRectangle);
  end;
end;

function TPDFontDescriptor.ItalicAngle: Single;
begin
  Result := FDictionary.GetFloat(TCosNames.ItalicAngle, 0);
end;

function TPDFontDescriptor.Ascent: Single;
begin
  Result := FDictionary.GetFloat(TCosNames.Ascent, 0);
end;

function TPDFontDescriptor.Descent: Single;
begin
  Result := FDictionary.GetFloat(TCosNames.Descent, 0);
end;

function TPDFontDescriptor.Leading: Single;
begin
  Result := FDictionary.GetFloat(TCosNames.Leading, 0);
end;

function TPDFontDescriptor.CapHeight: Single;
begin
  Result := Abs(FDictionary.GetFloat(TCosNames.CapHeight, 0));
end;

function TPDFontDescriptor.XHeight: Single;
begin
  Result := Abs(FDictionary.GetFloat(TCosNames.XHeight, 0));
end;

function TPDFontDescriptor.StemV: Single;
begin
  Result := FDictionary.GetFloat(TCosNames.StemV, 0);
end;

function TPDFontDescriptor.StemH: Single;
begin
  Result := FDictionary.GetFloat(TCosNames.StemH, 0);
end;

function TPDFontDescriptor.AverageWidth: Single;
begin
  Result := FDictionary.GetFloat(TCosNames.AvgWidth, 0);
end;

function TPDFontDescriptor.MaxWidth: Single;
begin
  Result := FDictionary.GetFloat(TCosNames.MaxWidth, 0);
end;

function TPDFontDescriptor.HasWidths: Boolean;
begin
  Result := (FDictionary.ContainsKey(TCosNames.Widths) or FDictionary.ContainsKey(TCosNames.MissingWidth));
end;

function TPDFontDescriptor.HasMissingWidth: Boolean;
begin
  Result := FDictionary.ContainsKey(TCosNames.MissingWidth);
end;

function TPDFontDescriptor.MissingWidth: Single;
begin
  Result := FDictionary.GetFloat(TCosNames.MissingWidth, 0);
end;

function TPDFontDescriptor.CharSet: string;
begin
  Result := FDictionary.GetString(TCosNames.CharSet, '');
end;

function TPDFontDescriptor.TryGetFontFile(out Stream: TCosStream): Boolean;
begin
  Result := FDictionary.TryGetCosStream(TCosNames.FontFile, Stream);
end;

function TPDFontDescriptor.TryGetFontFile2(out Stream: TCosStream): Boolean;
begin
  Result := FDictionary.TryGetCosStream(TCosNames.FontFile2, Stream);
end;

function TPDFontDescriptor.TryGetFontFile3(out Stream: TCosStream): Boolean;
begin
  Result := FDictionary.TryGetCosStream(TCosNames.FontFile3, Stream);
end;

function TPDFontDescriptor.TryGetCIDSet(out Stream: TCosStream): Boolean;
begin
  Result := FDictionary.TryGetCosStream(TCosNames.CIDSet, Stream);
end;

function TPDFontDescriptor.TryGetPanose(out Panose: TPDPanose): Boolean;
begin
  Panose := Default(TPDPanose);
  var Style: TCosDictionary;
  if not FDictionary.TryGetCosDictionary(TCosNames.Style, Style) then
  begin
    Exit(False);
  end;

  var Item: TCosBase;
  const HasPanoseString = (Style.TryGetDictionaryObject(TCosNames.Panose, Item) and (Item is TCosString));
  if not HasPanoseString then
  begin
    Exit(False);
  end;

  const Bytes = TCosString(Item).Bytes;
  Result := (System.Length(Bytes) >= TPDPanose.Length);
  if Result then
  begin
    Panose.Bytes := Copy(Bytes);
  end;
end;

end.
