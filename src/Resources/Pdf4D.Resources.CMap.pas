// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/resources/org/apache/fontbox/cmap (3.0.8), as data
unit Pdf4D.Resources.CMap;

interface

uses
  System.SysUtils;

type
  // The predefined CMaps of FontBox, as resources.
  TPdfCMapResources = class
  public
    // True for the exact, case-sensitive name of a predefined CMap, such as 'Identity-H'.
    class function IsPredefined(const CMapName: string): Boolean; static;
    // Returns False when CMapName is not the exact name of a predefined CMap. Other spellings of a name do not match.
    class function TryLoad(const CMapName: string; out Data: TBytes): Boolean; static;
    // The exact names of all predefined CMaps
    class function Names: TArray<string>; static;
  end;

implementation

{$R 'Pdf4D.Resources.CMap.res'}

uses
  Pdf4D.Common.ResourceData;

const
  // The file names of the CMap folder of FontBox; the resource names made from them lose case and punctuation
  PredefinedNames: array[0..91] of string = (
    '83pv-RKSJ-H', '90ms-RKSJ-H', '90ms-RKSJ-V', '90msp-RKSJ-H', '90msp-RKSJ-V', '90pv-RKSJ-H', '90pv-RKSJ-V',
    'Add-RKSJ-H', 'Add-RKSJ-V', 'Adobe-CNS1-0', 'Adobe-CNS1-1', 'Adobe-CNS1-2', 'Adobe-CNS1-3', 'Adobe-CNS1-4',
    'Adobe-CNS1-5', 'Adobe-CNS1-6', 'Adobe-CNS1-UCS2', 'Adobe-GB1-0', 'Adobe-GB1-1', 'Adobe-GB1-2', 'Adobe-GB1-3',
    'Adobe-GB1-4', 'Adobe-GB1-5', 'Adobe-GB1-UCS2', 'Adobe-Japan1-0', 'Adobe-Japan1-1', 'Adobe-Japan1-2',
    'Adobe-Japan1-3', 'Adobe-Japan1-4', 'Adobe-Japan1-5', 'Adobe-Japan1-6', 'Adobe-Japan1-7', 'Adobe-Japan1-UCS2',
    'Adobe-Japan2-0', 'Adobe-Korea1-0', 'Adobe-Korea1-1', 'Adobe-Korea1-2', 'Adobe-Korea1-UCS2', 'B5pc-H',
    'B5pc-V', 'CNS-EUC-H', 'CNS-EUC-V', 'ETen-B5-H', 'ETen-B5-V', 'ETenms-B5-H', 'ETenms-B5-V', 'EUC-H', 'EUC-V',
    'Ext-RKSJ-H', 'Ext-RKSJ-V', 'GB-EUC-H', 'GB-EUC-V', 'GBK-EUC-H', 'GBK-EUC-V', 'GBK2K-H', 'GBK2K-V',
    'GBKp-EUC-H', 'GBKp-EUC-V', 'GBpc-EUC-H', 'GBpc-EUC-V', 'H', 'HKscs-B5-H', 'HKscs-B5-V', 'Identity-H',
    'Identity-V', 'KSC-EUC-H', 'KSC-EUC-V', 'KSCms-UHC-H', 'KSCms-UHC-HW-H', 'KSCms-UHC-HW-V', 'KSCms-UHC-V',
    'KSCpc-EUC-H', 'KSCpc-EUC-V', 'UniCNS-UCS2-H', 'UniCNS-UCS2-V', 'UniCNS-UTF16-H', 'UniCNS-UTF16-V',
    'UniGB-UCS2-H', 'UniGB-UCS2-V', 'UniGB-UTF16-H', 'UniGB-UTF16-V', 'UniJIS-UCS2-H', 'UniJIS-UCS2-HW-H',
    'UniJIS-UCS2-HW-V', 'UniJIS-UCS2-V', 'UniJIS-UTF16-H', 'UniJIS-UTF16-V', 'UniKS-UCS2-H', 'UniKS-UCS2-V',
    'UniKS-UTF16-H', 'UniKS-UTF16-V', 'V'
  );

{ TPdfCMapResources }

class function TPdfCMapResources.IsPredefined(const CMapName: string): Boolean;
begin
  for var Known in PredefinedNames do
  begin
    if Known = CMapName then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TPdfCMapResources.Names: TArray<string>;
begin
  SetLength(Result, Length(PredefinedNames));
  for var Index := 0 to High(PredefinedNames) do
  begin
    Result[Index] := PredefinedNames[Index];
  end;
end;

class function TPdfCMapResources.TryLoad(const CMapName: string; out Data: TBytes): Boolean;
begin
  Data := nil;
  if not IsPredefined(CMapName) then
  begin
    Exit(False);
  end;

  Result := TPdfResourceData.TryLoad(TPdfResourceData.NameOf('CMAP', CMapName), Data);
end;

end.
