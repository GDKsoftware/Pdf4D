// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/FontHeaders.java (3.0.8)
unit Pdf4D.FontBox.TrueType.Headers;

interface

uses
  System.SysUtils;

type
  // What a font scan needs to know about a TrueType or OpenType font, read without parsing the whole font: the "name" and "head"
  // tables, the "OS/2" table and the registry, ordering and supplement of a CFF table. The fields that PDFBox leaves null have a
  // Has... flag. A font that cannot be used has an Error.
  TFontHeaders = record
  public
    // The length of the "gcid" data that holds the character collection of an Apple AAT font
    const GcidLength = 142;

  public
    // Empty when the headers were read; otherwise why the font cannot be used
    Error: string;
    // Empty when the font has no PostScript name
    Name: string;
    FontFamily: string;
    FontSubFamily: string;
    HasMacStyle: Boolean;
    MacStyle: Integer;
    HasOS2Windows: Boolean;
    FamilyClass: Integer;
    WeightClass: Integer;
    // The 32 bits of the field as a signed value, like Java's (int) cast
    CodePageRange1: Integer;
    CodePageRange2: Integer;
    Panose: TBytes;
    IsOpenTypePostScript: Boolean;
    // The registry, ordering and supplement of a CFF font that has a ROS operator
    HasCIDSystemInfo: Boolean;
    Registry: string;
    Ordering: string;
    Supplement: Integer;
    // The first GcidLength bytes of the "gcid" table of a font that is not an OpenType PostScript font, or empty
    Gcid: TBytes;

    class function Failed(const Error: string): TFontHeaders; static;
  end;

implementation

{ TFontHeaders }

class function TFontHeaders.Failed(const Error: string): TFontHeaders;
begin
  Result := Default(TFontHeaders);
  Result.Error := Error;
end;

end.
