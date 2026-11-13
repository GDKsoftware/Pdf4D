// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/filter/FilterFactory.java (3.0.8)
unit Pdf4D.Filter.Factory;

interface

uses
  System.SysUtils,
  Pdf4D.Filter.Base;

type
  TFilterFactory = class
  public
    // The full name of a filter given by its abbreviation (AHx, A85, LZW, Fl, RL, DCT, CCF), else the name as it is
    class function CanonicalName(const Name: string): string; static;

    // The caller owns the filter. Gives False for an unknown filter and for an image filter, which has no decoder.
    class function TryGetFilter(const Name: string; out Filter: TPdfFilter): Boolean; static;

    class function IsImageFilter(const Name: string): Boolean; static;
  end;

implementation

uses
  Pdf4D.Cos.Names,
  Pdf4D.Filter.ASCII85,
  Pdf4D.Filter.ASCIIHex,
  Pdf4D.Filter.Flate,
  Pdf4D.Filter.Identity,
  Pdf4D.Filter.LZW,
  Pdf4D.Filter.RunLength;

{ TFilterFactory }

class function TFilterFactory.CanonicalName(const Name: string): string;
begin
  if Name = TCosNames.AHx then
  begin
    Result := TCosNames.ASCIIHexDecode;
  end
  else if Name = TCosNames.A85 then
  begin
    Result := TCosNames.ASCII85Decode;
  end
  else if Name = TCosNames.LZW then
  begin
    Result := TCosNames.LZWDecode;
  end
  else if Name = TCosNames.FlateDecodeAbbreviation then
  begin
    Result := TCosNames.FlateDecode;
  end
  else if Name = TCosNames.RL then
  begin
    Result := TCosNames.RunLengthDecode;
  end
  else if Name = TCosNames.DCT then
  begin
    Result := TCosNames.DCTDecode;
  end
  else if Name = TCosNames.CCF then
  begin
    Result := TCosNames.CCITTFaxDecode;
  end
  else
  begin
    Result := Name;
  end;
end;

class function TFilterFactory.TryGetFilter(const Name: string; out Filter: TPdfFilter): Boolean;
begin
  Filter := nil;
  const CanonicalFilterName = CanonicalName(Name);
  Result := True;
  if CanonicalFilterName = TCosNames.FlateDecode then
  begin
    Filter := TFlateFilter.Create;
  end
  else if CanonicalFilterName = TCosNames.LZWDecode then
  begin
    Filter := TLZWFilter.Create;
  end
  else if CanonicalFilterName = TCosNames.ASCIIHexDecode then
  begin
    Filter := TASCIIHexFilter.Create;
  end
  else if CanonicalFilterName = TCosNames.ASCII85Decode then
  begin
    Filter := TASCII85Filter.Create;
  end
  else if CanonicalFilterName = TCosNames.RunLengthDecode then
  begin
    Filter := TRunLengthFilter.Create;
  end
  else if CanonicalFilterName = TCosNames.Crypt then
  begin
    Filter := TCryptFilter.Create;
  end
  else
  begin
    Result := False;
  end;
end;

class function TFilterFactory.IsImageFilter(const Name: string): Boolean;
begin
  const CanonicalFilterName = CanonicalName(Name);
  Result := (CanonicalFilterName = TCosNames.DCTDecode) or
            (CanonicalFilterName = TCosNames.JPXDecode) or
            (CanonicalFilterName = TCosNames.JBIG2Decode) or
            (CanonicalFilterName = TCosNames.CCITTFaxDecode);
end;

end.
