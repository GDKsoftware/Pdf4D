// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/resources/org/apache/pdfbox/resources/icc (3.0.8), as data
unit Pdf4D.Resources.Icc;

interface

uses
  System.SysUtils;

type
  // The ICC profiles that Pdf4D carries itself, as resources.
  TPdfIccResources = class
  public
    // CGATS001Compat-v2-micro.icc, the profile that PDDeviceCMYK loads.
    class function CmykProfile: TBytes; static;
  end;

implementation

{$R 'Pdf4D.Resources.Icc.res'}

uses
  Pdf4D.Common.ResourceData;

{ TPdfIccResources }

class function TPdfIccResources.CmykProfile: TBytes;
begin
  Result := TPdfResourceData.Load(TPdfResourceData.NameOf('ICC', 'CMYK'));
end;

end.
