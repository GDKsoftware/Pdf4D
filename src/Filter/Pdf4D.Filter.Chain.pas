// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: the decode loop of pdfbox/src/main/java/org/apache/pdfbox/filter/Filter.java and
// PDStream.createInputStream(List) (3.0.8)
unit Pdf4D.Filter.Chain;

interface

uses
  System.SysUtils,
  System.Classes,
  Pdf4D.Common.Log,
  Pdf4D.Cos.Dictionary;

type
  TFilterChain = class
  private
    class function CountDecodableFilters(const FilterNames: TArray<string>; const StopAtImageFilter: Boolean): Integer; static;
    class function RemoveDuplicates(const FilterNames: TArray<string>; const Count: Integer; const Log: TPdfLog): TArray<string>; static;
    class function ApplyFilter(const Data: TBytes; const Name: string; const Dictionary: TCosDictionary; const Index: Integer; const Limit: Int64; const Log: TPdfLog; const StopAtLimit: Boolean): TBytes; static;
    class function DecodeFilters(const Data: TBytes; const FilterNames: TArray<string>; const Dictionary: TCosDictionary; const Limit, PrefixLimit: Int64; const Log: TPdfLog): TBytes; static;

  public
    // Applies the filters in order to Data, the raw bytes of a stream whose dictionary is Dictionary. Every filter may
    // give at most Limit bytes (EPdfLimitExceededException). An unknown filter, and an image filter unless
    // StopAtImageFilter is set, raise EPdfUnsupportedFeatureException. With StopAtImageFilter the filters from the
    // first image filter on are not applied and are returned in RemainingFilters.
    class function Decode(const Data: TBytes; const FilterNames: TArray<string>; const Dictionary: TCosDictionary; const Limit: Int64; const Log: TPdfLog; const StopAtImageFilter: Boolean; out RemainingFilters: TArray<string>): TBytes; static;

    // The first MaxCount bytes of the decoded data (fewer when it is shorter), without decoding the rest: the last filter
    // stops after the prefix, and reaching MaxCount is no error. The earlier filters may give at most Limit bytes each.
    // Raises like Decode for an unknown or an image filter.
    class function DecodePrefix(const Data: TBytes; const FilterNames: TArray<string>; const Dictionary: TCosDictionary; const Limit: Int64; const MaxCount: Integer; const Log: TPdfLog): TBytes; static;
  end;

implementation

uses
  System.Generics.Collections,
  Pdf4D.Common.Defines,
  Pdf4D.Filter.Base,
  Pdf4D.Filter.Factory,
  Pdf4D.Filter.LimitedStream;

{ TFilterChain }

class function TFilterChain.Decode(const Data: TBytes; const FilterNames: TArray<string>; const Dictionary: TCosDictionary; const Limit: Int64; const Log: TPdfLog; const StopAtImageFilter: Boolean; out RemainingFilters: TArray<string>): TBytes;
begin
  const Count = CountDecodableFilters(FilterNames, StopAtImageFilter);
  RemainingFilters := Copy(FilterNames, Count, Length(FilterNames) - Count);

  Result := DecodeFilters(Data, Copy(FilterNames, 0, Count), Dictionary, Limit, 0, Log);
end;

class function TFilterChain.DecodePrefix(const Data: TBytes; const FilterNames: TArray<string>; const Dictionary: TCosDictionary; const Limit: Int64; const MaxCount: Integer; const Log: TPdfLog): TBytes;
begin
  if MaxCount <= 0 then
  begin
    Exit(nil);
  end;

  const Count = CountDecodableFilters(FilterNames, False);
  Result := DecodeFilters(Data, Copy(FilterNames, 0, Count), Dictionary, Limit, MaxCount, Log);
  if Length(Result) > MaxCount then
  begin
    SetLength(Result, MaxCount);
  end;
end;

class function TFilterChain.DecodeFilters(const Data: TBytes; const FilterNames: TArray<string>; const Dictionary: TCosDictionary; const Limit, PrefixLimit: Int64; const Log: TPdfLog): TBytes;
begin
  const Names = RemoveDuplicates(FilterNames, Length(FilterNames), Log);
  Result := Data;
  for var Index := 0 to High(Names) do
  begin
    const IsPrefixStage = ((PrefixLimit > 0) and (Index = High(Names)));
    if IsPrefixStage then
    begin
      Result := ApplyFilter(Result, Names[Index], Dictionary, Index, PrefixLimit, Log, True);
    end
    else
    begin
      Result := ApplyFilter(Result, Names[Index], Dictionary, Index, Limit, Log, False);
    end;
  end;
end;

// Checks the filters before decoding anything, so an unsupported filter is not found after a lot of work
class function TFilterChain.CountDecodableFilters(const FilterNames: TArray<string>; const StopAtImageFilter: Boolean): Integer;
begin
  for var Index := 0 to High(FilterNames) do
  begin
    const Name = FilterNames[Index];
    if TFilterFactory.IsImageFilter(Name) then
    begin
      if StopAtImageFilter then
      begin
        Exit(Index);
      end;
      raise EPdfUnsupportedFeatureException.CreateFmt('Decoding with the image filter %s is not supported', [Name]);
    end;

    var Filter: TPdfFilter;
    if not TFilterFactory.TryGetFilter(Name, Filter) then
    begin
      raise EPdfUnsupportedFeatureException.CreateFmt('Invalid filter: %s', [Name]);
    end;
    Filter.Free;
  end;
  Result := Length(FilterNames);
end;

// PDFBox keeps one instance per filter, so a filter in the list twice (also under its abbreviation) is applied once
class function TFilterChain.RemoveDuplicates(const FilterNames: TArray<string>; const Count: Integer; const Log: TPdfLog): TArray<string>;
begin
  const Seen = TList<string>.Create;
  try
    for var Index := 0 to Count - 1 do
    begin
      const CanonicalName = TFilterFactory.CanonicalName(FilterNames[Index]);
      if not Seen.Contains(CanonicalName) then
      begin
        Seen.Add(CanonicalName);
      end
      else if Assigned(Log) then
      begin
        Log.Warning('Removed duplicated filter entries');
      end;
    end;
    Result := Seen.ToArray;
  finally
    Seen.Free;
  end;
end;

class function TFilterChain.ApplyFilter(const Data: TBytes; const Name: string; const Dictionary: TCosDictionary; const Index: Integer; const Limit: Int64; const Log: TPdfLog; const StopAtLimit: Boolean): TBytes;
begin
  var Filter: TPdfFilter;
  if not TFilterFactory.TryGetFilter(Name, Filter) then
  begin
    raise EPdfUnsupportedFeatureException.CreateFmt('Invalid filter: %s', [Name]);
  end;

  try
    Filter.Log := Log;
    const Input = TBytesStream.Create(Data);
    const Output = TBytesStream.Create;
    try
      const Limited = TLimitedStream.Create(Output, Limit, StopAtLimit);
      try
        try
          Filter.Decode(Input, Limited, Dictionary, Index);
        except
          // The prefix is complete: what the output holds is the result
          on EPdfOutputPrefixReached do
          begin
          end;
        end;
      finally
        Limited.Free;
      end;
      // Take the buffer over without a copy: the stream lets go of its reference first, so the array is unique and
      // SetLength trims it in place (a shared array would be copied, and the peak would be capacity plus size)
      const DataSize = Output.Size;
      Result := Output.Bytes;
      Output.Clear;
      SetLength(Result, DataSize);
    finally
      Output.Free;
      Input.Free;
    end;
  finally
    Filter.Free;
  end;
end;

end.
