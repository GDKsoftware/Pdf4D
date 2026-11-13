// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Filter.Tests.Support;

interface

uses
  System.SysUtils,
  System.Classes,
  Pdf4D.Common.Log,
  Pdf4D.Cos.Dictionary;

type
  TFilterTestSupport = class
  public
    class function AsciiBytes(const Text: string): TBytes; static;
    class function AsciiString(const Data: TBytes): string; static;
    // The bytes as hexadecimal text, to compare bytes in an assertion
    class function ToHex(const Data: TBytes): string; static;

    // Deflates with a zlib header, like a Flate stream in a PDF
    class function Compress(const Data: TBytes): TBytes; static;

    // Decodes Input with the filter of that name. Parameters is the dictionary of the stream, nil for an empty one.
    class function Decode(const Name: string; const Input: TBytes; const Parameters: TCosDictionary = nil; const Log: TPdfLog = nil; const Limit: Int64 = High(Int64)): TBytes; static;
  end;

implementation

uses
  System.ZLib,
  Pdf4D.Filter.Base,
  Pdf4D.Filter.Factory,
  Pdf4D.Filter.LimitedStream;

{ TFilterTestSupport }

class function TFilterTestSupport.AsciiBytes(const Text: string): TBytes;
begin
  Result := TEncoding.ASCII.GetBytes(Text);
end;

class function TFilterTestSupport.AsciiString(const Data: TBytes): string;
begin
  Result := TEncoding.ASCII.GetString(Data);
end;

class function TFilterTestSupport.ToHex(const Data: TBytes): string;
begin
  Result := '';
  for var Value in Data do
  begin
    Result := Result + IntToHex(Value, 2);
  end;
end;

class function TFilterTestSupport.Compress(const Data: TBytes): TBytes;
begin
  const Output = TBytesStream.Create;
  try
    const Compressor = TZCompressionStream.Create(Output);
    try
      if Length(Data) > 0 then
      begin
        Compressor.WriteBuffer(Data[0], Length(Data));
      end;
    finally
      Compressor.Free;
    end;
    Result := Copy(Output.Bytes, 0, Output.Size);
  finally
    Output.Free;
  end;
end;

class function TFilterTestSupport.Decode(const Name: string; const Input: TBytes; const Parameters: TCosDictionary; const Log: TPdfLog; const Limit: Int64): TBytes;
begin
  var Filter: TPdfFilter;
  if not TFilterFactory.TryGetFilter(Name, Filter) then
  begin
    raise EArgumentException.CreateFmt('No filter %s', [Name]);
  end;

  const OwnParameters = TCosDictionary.Create;
  const Source = TBytesStream.Create(Input);
  const Target = TBytesStream.Create;
  try
    Filter.Log := Log;
    const Limited = TLimitedStream.Create(Target, Limit);
    try
      if Assigned(Parameters) then
      begin
        Filter.Decode(Source, Limited, Parameters, 0);
      end
      else
      begin
        Filter.Decode(Source, Limited, OwnParameters, 0);
      end;
    finally
      Limited.Free;
    end;
    Result := Copy(Target.Bytes, 0, Target.Size);
  finally
    Target.Free;
    Source.Free;
    OwnParameters.Free;
    Filter.Free;
  end;
end;

end.
