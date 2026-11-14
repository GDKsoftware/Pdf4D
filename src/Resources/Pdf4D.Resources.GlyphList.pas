// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/resources/org/apache/pdfbox/resources/glyphlist (3.0.8), as data
unit Pdf4D.Resources.GlyphList;

interface

uses
  System.SysUtils;

type
  // The Adobe glyph lists of PDFBox, as resources.
  TPdfGlyphListResources = class
  public
    // ListName is glyphlist, zapfdingbats or additional.
    class function Load(const ListName: string): TBytes; static;
  end;

implementation

{$R 'Pdf4D.Resources.GlyphList.res'}

uses
  Pdf4D.Common.ResourceData;

{ TPdfGlyphListResources }

class function TPdfGlyphListResources.Load(const ListName: string): TBytes;
begin
  Result := TPdfResourceData.Load(TPdfResourceData.NameOf('GLYPHLIST', ListName));
end;

end.
