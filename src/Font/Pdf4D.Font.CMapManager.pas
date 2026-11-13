// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/font/CMapManager.java (3.0.8)
unit Pdf4D.Font.CMapManager;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Common.SharedInstance,
  Pdf4D.FontBox.CMap,
  Pdf4D.IO.RandomAccessRead;

type
  // The predefined CMaps are parsed once, on first use, and shared by all threads and documents. A shared CMap does
  // not change.
  TCMapManager = class
  private
    class var FPredefinedCMaps: TPdfSharedInstance<TPdfSharedCache<string, TCMap>>;

    class destructor Destroy;

    class function CreatePredefinedCache: TPdfSharedCache<string, TCMap>; static;
    // Not const: the signature has to be the one of TFunc<string, TCMap>
    class function ParsePredefinedCMap(Name: string): TCMap; static;

  public
    // The shared predefined CMap of that name; the caller does not own it. False when there is no such CMap.
    class function TryGetPredefinedCMap(const Name: string; out CMap: TCMap): Boolean; static;
    // Parses an embedded CMap in strict mode. The caller owns the result.
    class function ParseCMap(const Source: TRandomAccessRead): TCMap; static;
  end;

implementation

uses
  Pdf4D.FontBox.CMapParser,
  Pdf4D.Resources.CMap;

{ TCMapManager }

class destructor TCMapManager.Destroy;
begin
  FPredefinedCMaps.Release;
end;

class function TCMapManager.CreatePredefinedCache: TPdfSharedCache<string, TCMap>;
begin
  Result := TPdfSharedCache<string, TCMap>.Create;
end;

class function TCMapManager.ParsePredefinedCMap(Name: string): TCMap;
begin
  const Parser = TCMapParser.Create(False);
  try
    Result := Parser.ParsePredefined(Name);
  finally
    Parser.Free;
  end;
end;

class function TCMapManager.TryGetPredefinedCMap(const Name: string; out CMap: TCMap): Boolean;
begin
  CMap := nil;
  const Cache = FPredefinedCMaps.Get(CreatePredefinedCache);
  if Cache.TryGet(Name, CMap) then
  begin
    Exit(True);
  end;

  var Data: TBytes;
  if not TPdfCMapResources.TryLoad(Name, Data) then
  begin
    Exit(False);
  end;

  CMap := Cache.GetOrAdd(Name, ParsePredefinedCMap);
  Result := True;
end;

class function TCMapManager.ParseCMap(const Source: TRandomAccessRead): TCMap;
begin
  const Parser = TCMapParser.Create(True);
  try
    Result := Parser.Parse(Source);
  finally
    Parser.Free;
  end;
end;

end.
