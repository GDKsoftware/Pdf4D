// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/resources/org/apache/pdfbox/resources/afm (3.0.8), as data
unit Pdf4D.Resources.Afm;

interface

uses
  System.SysUtils;

type
  // The AFM files of the standard 14 fonts, as resources.
  TPdfAfmResources = class
  public
    // FontName is a PostScript name such as Helvetica-BoldOblique, or MustRead for the licence notice that goes with the AFM files.
    class function Load(const FontName: string): TBytes; static;
  end;

implementation

{$R 'Pdf4D.Resources.Afm.res'}

uses
  Pdf4D.Common.ResourceData;

{ TPdfAfmResources }

class function TPdfAfmResources.Load(const FontName: string): TBytes;
begin
  Result := TPdfResourceData.Load(TPdfResourceData.NameOf('AFM', FontName));
end;

end.
