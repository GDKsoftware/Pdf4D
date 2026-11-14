// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/resources/org/apache/pdfbox/resources/ttf (3.0.8), as data
unit Pdf4D.Resources.Fonts;

interface

uses
  System.SysUtils;

type
  // The fonts that Pdf4D carries itself, as resources.
  TPdfFontResources = class
  public
    // LiberationSans-Regular.ttf, the fallback font of the font mapper.
    class function LiberationSans: TBytes; static;
  end;

implementation

{$R 'Pdf4D.Resources.Fonts.res'}

uses
  Pdf4D.Common.ResourceData;

{ TPdfFontResources }

class function TPdfFontResources.LiberationSans: TBytes;
begin
  Result := TPdfResourceData.Load(TPdfResourceData.NameOf('FONT', 'LiberationSans'));
end;

end.
