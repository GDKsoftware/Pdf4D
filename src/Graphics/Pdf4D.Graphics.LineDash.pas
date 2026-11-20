// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/PDLineDashPattern.java (3.0.8)
unit Pdf4D.Graphics.LineDash;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Cos.PdfArray;

type
  // A line dash pattern for stroking paths. A value, like the immutable PDLineDashPattern: the dash array is never changed in place.
  TPDLineDashPattern = record
  private
    class function SaturatingTrunc(const Value: Double): Integer; static;
    class function NormalizePhase(const Dashes: TArray<Single>; const Phase: Integer): Integer; static;

  public
    Dashes: TArray<Single>;
    Phase: Integer;

    // No dashes and a phase of 0
    class function Empty: TPDLineDashPattern; static;
    // The dash array is copied. A negative phase is made positive as the PDF 2.0 specification says (8.4.3.6): it is incremented by
    // twice the sum of the lengths until it is positive, and becomes 0 when that sum is not positive. An item that is no number is 0.
    class function Create(const DashArray: TCosArray; const Phase: Integer): TPDLineDashPattern; static;

    function IsEmpty: Boolean;
  end;

implementation

uses
  System.Math;

{ TPDLineDashPattern }

class function TPDLineDashPattern.Empty: TPDLineDashPattern;
begin
  Result.Dashes := nil;
  Result.Phase := 0;
end;

class function TPDLineDashPattern.Create(const DashArray: TCosArray; const Phase: Integer): TPDLineDashPattern;
begin
  Result.Dashes := DashArray.ToFloatArray;
  Result.Phase := NormalizePhase(Result.Dashes, Phase);
end;

function TPDLineDashPattern.IsEmpty: Boolean;
begin
  Result := (Length(Dashes) = 0);
end;

// Java's (int) cast of a double: NaN is 0 and the ends of the range saturate
class function TPDLineDashPattern.SaturatingTrunc(const Value: Double): Integer;
begin
  if IsNan(Value) then
  begin
    Exit(0);
  end;

  if Value >= MaxInt then
  begin
    Exit(MaxInt);
  end;

  if Value <= Integer.MinValue then
  begin
    Exit(Integer.MinValue);
  end;

  Result := Trunc(Value);
end;

class function TPDLineDashPattern.NormalizePhase(const Dashes: TArray<Single>; const Phase: Integer): Integer;
begin
  Result := Phase;
  if Phase >= 0 then
  begin
    Exit;
  end;

  var TwiceSum: Single := 0;
  for var Dash in Dashes do
  begin
    TwiceSum := TwiceSum + Dash;
  end;
  TwiceSum := TwiceSum * 2;

  if not (TwiceSum > 0) then
  begin
    Exit(0);
  end;

  const Negated: Single = -Phase;
  var Increment: Double := TwiceSum;
  if not (Negated < TwiceSum) then
  begin
    // Negated is positive here, so cutting off the fraction is Math.floor, without the Integer range of Floor
    const WholeCycles: Double = Int(Negated / TwiceSum);
    Increment := (WholeCycles + 1) * TwiceSum;
  end;
  Result := SaturatingTrunc(Phase + Increment);
end;

end.
