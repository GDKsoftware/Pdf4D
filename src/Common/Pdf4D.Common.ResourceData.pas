// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/resources/org/apache/pdfbox/resources and fontbox/src/main/resources/org/apache/fontbox/cmap (3.0.8), as data
unit Pdf4D.Common.ResourceData;

interface

uses
  System.SysUtils;

type
  // Reads the zlib-compressed RCDATA resources that tools/resources/build-resources.ps1 builds.
  TPdfResourceData = class
  public
    // 'PDF4D_' + Group + '_' + Item in capitals, every character outside A-Z and 0-9 replaced by an underscore.
    class function NameOf(const Group, Item: string): string; static;

    // Returns False when the resource does not exist.
    class function TryLoad(const Name: string; out Data: TBytes): Boolean; static;

    // Inflates the stored bytes of the resource Name. Raises EPdfException when they are damaged. TryLoad uses it; it is
    // public so that a test can feed it damaged data.
    class function Decompress(const Name: string; const Compressed: TBytes): TBytes; static;

    // Raises EPdfException when the resource does not exist.
    class function Load(const Name: string): TBytes; static;
  end;

implementation

uses
  System.Classes,
  System.Types,
  System.ZLib,
  Pdf4D.Common.Defines;

{ TPdfResourceData }

class function TPdfResourceData.NameOf(const Group, Item: string): string;
begin
  const Raw = 'PDF4D_' + Group + '_' + Item;
  const Builder = TStringBuilder.Create(Length(Raw));
  try
    for var Character in Raw.ToUpperInvariant do
    begin
      if ((Character >= 'A') and (Character <= 'Z')) or ((Character >= '0') and (Character <= '9')) then
      begin
        Builder.Append(Character);
      end
      else
      begin
        Builder.Append('_');
      end;
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TPdfResourceData.TryLoad(const Name: string; out Data: TBytes): Boolean;
begin
  Data := nil;
  var Compressed: TBytes := nil;
  try
    const Stream = TResourceStream.Create(HInstance, Name, RT_RCDATA);
    try
      SetLength(Compressed, Stream.Size);
      if Stream.Size > 0 then
      begin
        Stream.ReadBuffer(Compressed, Stream.Size);
      end;
    finally
      Stream.Free;
    end;
  except
    on EResNotFound do
    begin
      Exit(False);
    end;
  end;

  Data := Decompress(Name, Compressed);
  Result := True;
end;

class function TPdfResourceData.Decompress(const Name: string; const Compressed: TBytes): TBytes;
begin
  // No limit on the output: the input is data that is linked into the program, not data from a PDF
  try
    ZDecompress(Compressed, Result);
  except
    on E: EZLibError do
    begin
      raise EPdfException.CreateFmt('Resource %s is damaged: %s', [Name, E.Message]);
    end;
  end;
end;

class function TPdfResourceData.Load(const Name: string): TBytes;
begin
  if not TryLoad(Name, Result) then
  begin
    raise EPdfException.CreateFmt('Resource %s is missing', [Name]);
  end;
end;

end.
