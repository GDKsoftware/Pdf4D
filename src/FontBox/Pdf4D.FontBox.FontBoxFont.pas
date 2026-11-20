// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/FontBoxFont.java (3.0.8)
unit Pdf4D.FontBox.FontBoxFont;

{$EXCESSPRECISION OFF}

interface

uses
  Pdf4D.Common.Path,
  Pdf4D.FontBox.BoundingBox;

type
  // The glyph outlines are in glyph space: the caller scales them with the FontMatrix
  TFontBoxFont = class abstract
  public
    // Empty when the font has no name
    function Name: string; virtual; abstract;
    function FontBBox: TBoundingBox; virtual; abstract;
    function FontMatrix: TArray<Single>; virtual; abstract;
    function GetWidth(const GlyphName: string): Single; virtual; abstract;
    function HasGlyph(const GlyphName: string): Boolean; virtual; abstract;
    // The outline of the glyph; the caller owns the path. A font does not cache paths: the glyph cache of the renderer does.
    // False when the font has no outline for the glyph, or cannot make outlines (a TrueType font does not yet).
    function TryGetPath(const GlyphName: string; out Path: TPdfPath): Boolean; virtual; abstract;
  end;

implementation

end.
