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
    // Returns False when CMapName is not one of the predefined CMaps.
    class function TryLoad(const CMapName: string; out Data: TBytes): Boolean; static;
  end;

implementation

{$R 'Pdf4D.Resources.CMap.res'}

uses
  Pdf4D.Common.ResourceData;

{ TPdfCMapResources }

class function TPdfCMapResources.TryLoad(const CMapName: string; out Data: TBytes): Boolean;
begin
  Result := TPdfResourceData.TryLoad(TPdfResourceData.NameOf('CMAP', CMapName), Data);
end;

end.
