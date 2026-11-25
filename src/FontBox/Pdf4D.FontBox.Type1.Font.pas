// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/type1/Type1Font.java (3.0.8)
unit Pdf4D.FontBox.Type1.Font;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.Log,
  Pdf4D.Common.Path,
  Pdf4D.FontBox.BoundingBox,
  Pdf4D.FontBox.Encoding,
  Pdf4D.FontBox.FontBoxFont,
  Pdf4D.FontBox.Type1.Parser;

type
  // An Adobe Type 1 font program
  TType1Font = class(TFontBoxFont)
  private
    FData: TType1FontData;
    FSubrs: TArray<TBytes>;
    FSegment1: TBytes;
    FSegment2: TBytes;
    FLog: TPdfLog;

    function SeacCharString(const GlyphName: string): TBytes;

    constructor CreateFromData(const Data: TType1FontData; const Segment1, Segment2: TBytes; const Log: TPdfLog);

  public
    // Reads a PFB file. Raises EPdfParseException for a damaged file. The log is optional and must outlive the font.
    class function CreateWithPFB(const Data: TBytes; const Log: TPdfLog = nil): TType1Font; static;
    // The segments as a PDF font file stream has them: the clear text and the encrypted part, without the PFB headers
    class function CreateWithSegments(const Segment1, Segment2: TBytes; const Log: TPdfLog = nil): TType1Font; static;

    destructor Destroy; override;

    function Name: string; override;
    // Raises EPdfParseException when the FontBBox does not have 4 numbers
    function FontBBox: TBoundingBox; override;
    // The FontMatrix of the font; empty when the font has none
    function FontMatrix: TArray<Single>; override;
    // The width of the glyph in font units. A name that the font does not have gets the width of .notdef; raises
    // EPdfParseException when there is no .notdef either. A glyph without a width in its charstring gets 0.
    function GetWidth(const GlyphName: string): Single; override;
    function HasGlyph(const GlyphName: string): Boolean; override;
    // The outline of the glyph in glyph space. A name that the font does not have gets the outline of .notdef; False when there
    // is no .notdef either. A damaged charstring gives the outline up to the damage.
    function TryGetPath(const GlyphName: string; out Path: TPdfPath): Boolean; override;

    function FontName: string;
    // The encoding of the font, or nil when the font declares none. The font owns it.
    function Encoding: TFontBoxEncoding;
    function PaintType: Integer;
    function FontType: Integer;
    function UniqueID: Integer;
    function StrokeWidth: Single;
    function FontID: string;

    function Version: string;
    function Notice: string;
    function FullName: string;
    function FamilyName: string;
    function Weight: string;
    function ItalicAngle: Single;
    function IsFixedPitch: Boolean;
    function UnderlinePosition: Single;
    function UnderlineThickness: Single;

    function BlueValues: TArray<Single>;
    function OtherBlues: TArray<Single>;
    function FamilyBlues: TArray<Single>;
    function FamilyOtherBlues: TArray<Single>;
    function BlueScale: Single;
    function BlueShift: Integer;
    function BlueFuzz: Integer;
    function StdHW: TArray<Single>;
    function StdVW: TArray<Single>;
    function StemSnapH: TArray<Single>;
    function StemSnapV: TArray<Single>;
    function IsForceBold: Boolean;
    function LanguageGroup: Integer;

    // The decrypted subroutines; a subroutine that the font does not define is empty
    function Subrs: TArray<TBytes>;
    // The decrypted charstrings by glyph name. The dictionary belongs to the font and must not be changed.
    function CharStringsDict: TDictionary<string, TBytes>;
    function ASCIISegment: TBytes;
    function BinarySegment: TBytes;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.FontBox.CharStringPath,
  Pdf4D.FontBox.CharStringWidth,
  Pdf4D.FontBox.Pfb;

const
  NotdefName = '.notdef';
  BBoxNumberCount = 4;

{ TType1Font }

class function TType1Font.CreateWithPFB(const Data: TBytes; const Log: TPdfLog): TType1Font;
begin
  const Pfb = TPfbParser.Create(Data);
  try
    Result := CreateWithSegments(Pfb.Segment1, Pfb.Segment2, Log);
  finally
    Pfb.Free;
  end;
end;

class function TType1Font.CreateWithSegments(const Segment1, Segment2: TBytes; const Log: TPdfLog): TType1Font;
begin
  const Parser = TType1Parser.Create;
  try
    const Data = Parser.Parse(Segment1, Segment2, Log);
    Result := TType1Font.CreateFromData(Data, Segment1, Segment2, Log);
  finally
    Parser.Free;
  end;
end;

constructor TType1Font.CreateFromData(const Data: TType1FontData; const Segment1, Segment2: TBytes; const Log: TPdfLog);
begin
  inherited Create;
  FData := Data;
  FSubrs := Data.Subrs.ToArray;
  FSegment1 := Segment1;
  FSegment2 := Segment2;
  FLog := Log;
end;

destructor TType1Font.Destroy;
begin
  FData.Free;
  inherited;
end;

function TType1Font.Name: string;
begin
  Result := FData.FontName;
end;

function TType1Font.FontBBox: TBoundingBox;
begin
  const Numbers = FData.FontBBox;
  if Length(Numbers) < BBoxNumberCount then
  begin
    raise EPdfParseException.CreateFmt('FontBBox must have 4 numbers, but has %d', [Length(Numbers)]);
  end;
  Result := TBoundingBox.Create(Numbers[0], Numbers[1], Numbers[2], Numbers[3]);
end;

function TType1Font.FontMatrix: TArray<Single>;
begin
  Result := FData.FontMatrix;
end;

function TType1Font.GetWidth(const GlyphName: string): Single;
begin
  var CharString: TBytes;
  if not FData.CharStrings.TryGetValue(GlyphName, CharString) then
  begin
    if not FData.CharStrings.TryGetValue(NotdefName, CharString) then
    begin
      raise EPdfParseException.Create('.notdef is not defined');
    end;
  end;

  var Width: Integer;
  if TCharStringWidth.Type1Width(CharString, FSubrs, Width, FLog) then
  begin
    Result := Width;
  end
  else
  begin
    Result := 0;
  end;
end;

function TType1Font.HasGlyph(const GlyphName: string): Boolean;
begin
  Result := FData.CharStrings.ContainsKey(GlyphName);
end;

function TType1Font.TryGetPath(const GlyphName: string; out Path: TPdfPath): Boolean;
begin
  Path := nil;
  var CharString: TBytes;
  const HasCharString = (FData.CharStrings.TryGetValue(GlyphName, CharString) or
                         FData.CharStrings.TryGetValue(NotdefName, CharString));
  if not HasCharString then
  begin
    Exit(False);
  end;

  Path := TCharStringPath.Type1Path(CharString, FSubrs,
    function(Name: string): TBytes
    begin
      Result := SeacCharString(Name);
    end, FLog);
  Result := True;
end;

// The component of a seac: a glyph that the font does not have is replaced by .notdef, as in PDFBox
function TType1Font.SeacCharString(const GlyphName: string): TBytes;
begin
  if not FData.CharStrings.TryGetValue(GlyphName, Result) then
  begin
    FData.CharStrings.TryGetValue(NotdefName, Result);
  end;
end;

function TType1Font.FontName: string;
begin
  Result := FData.FontName;
end;

function TType1Font.Encoding: TFontBoxEncoding;
begin
  Result := FData.Encoding;
end;

function TType1Font.PaintType: Integer;
begin
  Result := FData.PaintType;
end;

function TType1Font.FontType: Integer;
begin
  Result := FData.FontType;
end;

function TType1Font.UniqueID: Integer;
begin
  Result := FData.UniqueID;
end;

function TType1Font.StrokeWidth: Single;
begin
  Result := FData.StrokeWidth;
end;

function TType1Font.FontID: string;
begin
  Result := FData.FontID;
end;

function TType1Font.Version: string;
begin
  Result := FData.Version;
end;

function TType1Font.Notice: string;
begin
  Result := FData.Notice;
end;

function TType1Font.FullName: string;
begin
  Result := FData.FullName;
end;

function TType1Font.FamilyName: string;
begin
  Result := FData.FamilyName;
end;

function TType1Font.Weight: string;
begin
  Result := FData.Weight;
end;

function TType1Font.ItalicAngle: Single;
begin
  Result := FData.ItalicAngle;
end;

function TType1Font.IsFixedPitch: Boolean;
begin
  Result := FData.IsFixedPitch;
end;

function TType1Font.UnderlinePosition: Single;
begin
  Result := FData.UnderlinePosition;
end;

function TType1Font.UnderlineThickness: Single;
begin
  Result := FData.UnderlineThickness;
end;

function TType1Font.BlueValues: TArray<Single>;
begin
  Result := FData.BlueValues;
end;

function TType1Font.OtherBlues: TArray<Single>;
begin
  Result := FData.OtherBlues;
end;

function TType1Font.FamilyBlues: TArray<Single>;
begin
  Result := FData.FamilyBlues;
end;

function TType1Font.FamilyOtherBlues: TArray<Single>;
begin
  Result := FData.FamilyOtherBlues;
end;

function TType1Font.BlueScale: Single;
begin
  Result := FData.BlueScale;
end;

function TType1Font.BlueShift: Integer;
begin
  Result := FData.BlueShift;
end;

function TType1Font.BlueFuzz: Integer;
begin
  Result := FData.BlueFuzz;
end;

function TType1Font.StdHW: TArray<Single>;
begin
  Result := FData.StdHW;
end;

function TType1Font.StdVW: TArray<Single>;
begin
  Result := FData.StdVW;
end;

function TType1Font.StemSnapH: TArray<Single>;
begin
  Result := FData.StemSnapH;
end;

function TType1Font.StemSnapV: TArray<Single>;
begin
  Result := FData.StemSnapV;
end;

function TType1Font.IsForceBold: Boolean;
begin
  Result := FData.ForceBold;
end;

function TType1Font.LanguageGroup: Integer;
begin
  Result := FData.LanguageGroup;
end;

function TType1Font.Subrs: TArray<TBytes>;
begin
  Result := FSubrs;
end;

function TType1Font.CharStringsDict: TDictionary<string, TBytes>;
begin
  Result := FData.CharStrings;
end;

function TType1Font.ASCIISegment: TBytes;
begin
  Result := FSegment1;
end;

function TType1Font.BinarySegment: TBytes;
begin
  Result := FSegment2;
end;

end.
