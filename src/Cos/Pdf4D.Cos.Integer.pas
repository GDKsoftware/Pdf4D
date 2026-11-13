// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/cos/COSInteger.java (3.0.8)
unit Pdf4D.Cos.Integer;

interface

uses
  Pdf4D.Cos.Number;

type
  TCosInteger = class(TCosNumber)
  private
    FValue: Int64;
    FIsValid: Boolean;

  public
    // Port of COSInteger.OUT_OF_RANGE_MAX and OUT_OF_RANGE_MIN: a number the parser could not hold in an Int64.
    class function CreateOutOfRange(const TooLarge: Boolean): TCosInteger; static;

    constructor Create(const Value: Int64);

    function FloatValue: Single; override;
    function IntValue: Integer; override;
    function LongValue: Int64; override;

    property Value: Int64 read FValue;
    property IsValid: Boolean read FIsValid;
  end;

implementation

{ TCosInteger }

class function TCosInteger.CreateOutOfRange(const TooLarge: Boolean): TCosInteger;
begin
  if TooLarge then
  begin
    Result := TCosInteger.Create(High(Int64));
  end
  else
  begin
    Result := TCosInteger.Create(Low(Int64));
  end;
  Result.FIsValid := False;
end;

constructor TCosInteger.Create(const Value: Int64);
begin
  inherited Create;
  FValue := Value;
  FIsValid := True;
end;

function TCosInteger.FloatValue: Single;
begin
  Result := FValue;
end;

function TCosInteger.IntValue: Integer;
begin
  // Truncates to the low 32 bits, like the (int) cast in Java
  Result := Integer(FValue and $FFFFFFFF);
end;

function TCosInteger.LongValue: Int64;
begin
  Result := FValue;
end;

end.
