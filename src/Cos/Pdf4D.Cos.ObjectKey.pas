// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/cos/COSObjectKey.java (3.0.8)
unit Pdf4D.Cos.ObjectKey;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults;

type
  TCosObjectKey = record
    Number: Int64;
    Generation: Integer;
    // Port of COSObjectKey.getStreamIndex: the position inside the object stream, -1 when unknown. Not part of equality.
    StreamIndex: Integer;

    class function Make(const Number: Int64; const Generation: Integer): TCosObjectKey; static;
    class function MakeInObjectStream(const Number: Int64; const StreamIndex: Integer): TCosObjectKey; static;
    class operator Equal(const Left, Right: TCosObjectKey): Boolean;
    class operator NotEqual(const Left, Right: TCosObjectKey): Boolean;

    function ToString: string;
  end;

  // The default comparer hashes the raw bytes of a record, which includes padding: use this one for dictionaries.
  TCosObjectKeyComparer = class(TInterfacedObject, IEqualityComparer<TCosObjectKey>, IComparer<TCosObjectKey>)
  public
    function Equals(const Left, Right: TCosObjectKey): Boolean; reintroduce;
    function GetHashCode(const Value: TCosObjectKey): Integer; reintroduce;
    function Compare(const Left, Right: TCosObjectKey): Integer;
  end;

implementation

{ TCosObjectKey }

class function TCosObjectKey.Make(const Number: Int64; const Generation: Integer): TCosObjectKey;
begin
  Result.Number := Number;
  Result.Generation := Generation;
  Result.StreamIndex := -1;
end;

class function TCosObjectKey.MakeInObjectStream(const Number: Int64; const StreamIndex: Integer): TCosObjectKey;
begin
  Result := Make(Number, 0);
  Result.StreamIndex := StreamIndex;
end;

class operator TCosObjectKey.Equal(const Left, Right: TCosObjectKey): Boolean;
begin
  Result := ((Left.Number = Right.Number) and (Left.Generation = Right.Generation));
end;

class operator TCosObjectKey.NotEqual(const Left, Right: TCosObjectKey): Boolean;
begin
  Result := not (Left = Right);
end;

function TCosObjectKey.ToString: string;
begin
  Result := Format('%d %d R', [Number, Generation]);
end;

{ TCosObjectKeyComparer }

function TCosObjectKeyComparer.Equals(const Left, Right: TCosObjectKey): Boolean;
begin
  Result := (Left = Right);
end;

function TCosObjectKeyComparer.GetHashCode(const Value: TCosObjectKey): Integer;
begin
  // The generation is below 2^32 and the factor too, so the product fits in 64 bits for every number
  const Mixed = UInt64(Value.Number) xor (UInt64(Cardinal(Value.Generation)) * $9E3779B1);
  Result := Integer(Cardinal((Mixed xor (Mixed shr 32)) and $FFFFFFFF));
end;

function TCosObjectKeyComparer.Compare(const Left, Right: TCosObjectKey): Integer;
begin
  if Left.Number <> Right.Number then
  begin
    if Left.Number < Right.Number then
    begin
      Exit(-1);
    end;
    Exit(1);
  end;

  if Left.Generation < Right.Generation then
  begin
    Exit(-1);
  end;
  if Left.Generation > Right.Generation then
  begin
    Exit(1);
  end;
  Result := 0;
end;

end.
