// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/FontBoxFont.java (3.0.8)
unit Pdf4D.FontBox.FontBoxFont;

{$EXCESSPRECISION OFF}

interface

uses
  Pdf4D.FontBox.BoundingBox;

type
  // Glyph paths are left out: Pdf4D does not render
  TFontBoxFont = class abstract
  public
    // Empty when the font has no name
    function Name: string; virtual; abstract;
    function FontBBox: TBoundingBox; virtual; abstract;
    function FontMatrix: TArray<Single>; virtual; abstract;
    function GetWidth(const GlyphName: string): Single; virtual; abstract;
    function HasGlyph(const GlyphName: string): Boolean; virtual; abstract;
  end;

implementation

end.
