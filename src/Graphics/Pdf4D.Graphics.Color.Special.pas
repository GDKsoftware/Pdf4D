// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/color/PDPattern.java (3.0.8), the array [/Pattern base] with an
// underlying colour space for the colour of an uncoloured tiling pattern. The other special colour spaces are ported by a later task.
unit Pdf4D.Graphics.Color.Special;

{$EXCESSPRECISION OFF}

interface

uses
  Pdf4D.Graphics.Color,
  Pdf4D.Graphics.Color.Pattern;

type
  // The Pattern colour space of an array: the components of a colour are those of the underlying space, and the name of the pattern comes
  // with them. The space belongs to the document context, which also owns the underlying space when that is no shared one.
  TPDPatternColorSpace = class(TPDPattern)
  private
    FUnderlyingColorSpace: TPDColorSpace;

  public
    // UnderlyingColorSpace is not owned; nil for [/Pattern] without one
    constructor Create(const UnderlyingColorSpace: TPDColorSpace);

    // Nil for a pattern space without underlying space, whose patterns are coloured
    property UnderlyingColorSpace: TPDColorSpace read FUnderlyingColorSpace;
  end;

implementation

{ TPDPatternColorSpace }

constructor TPDPatternColorSpace.Create(const UnderlyingColorSpace: TPDColorSpace);
begin
  inherited Create;
  FUnderlyingColorSpace := UnderlyingColorSpace;
end;

end.
