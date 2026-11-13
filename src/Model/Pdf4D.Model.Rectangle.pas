// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/common/PDRectangle.java (3.0.8), the read side
unit Pdf4D.Model.Rectangle;

interface

uses
  System.SysUtils,
  Pdf4D.Cos.PdfArray;

type
  TPdfRectangle = record
    LowerLeftX: Single;
    LowerLeftY: Single;
    UpperRightX: Single;
    UpperRightY: Single;

    // US Letter, the default media box of a page
    class function Letter: TPdfRectangle; static;

    // Port of the PDRectangle(COSArray) constructor: missing values are 0, extra values are ignored, a value beyond the
    // Integer range is replaced by the limit, and the corners are put in order so that the lower left one comes first.
    class function FromCosArray(const Value: TCosArray): TPdfRectangle; static;

    // Port of PDPage.clipToMediaBox. A box that does not overlap Bounds gives a rectangle with an upper right corner
    // before the lower left one, like PDFBox.
    function ClipTo(const Bounds: TPdfRectangle): TPdfRectangle;

    function Width: Single;
    function Height: Single;
  end;

implementation

type
  TJavaMath = record
    class function Min(const Left, Right: Single): Single; static;
    class function Max(const Left, Right: Single): Single; static;
    class function LimitHugeValue(const Value: Single): Single; static;
  end;

{ TJavaMath }

class function TJavaMath.Min(const Left, Right: Single): Single;
begin
  if Left.IsNan or Right.IsNan then
  begin
    Exit(Single.NaN);
  end;

  if Left < Right then
  begin
    Result := Left;
  end
  else
  begin
    Result := Right;
  end;
end;

class function TJavaMath.Max(const Left, Right: Single): Single;
begin
  if Left.IsNan or Right.IsNan then
  begin
    Exit(Single.NaN);
  end;

  if Left > Right then
  begin
    Result := Left;
  end
  else
  begin
    Result := Right;
  end;
end;

class function TJavaMath.LimitHugeValue(const Value: Single): Single;
begin
  Result := Value;
  if Abs(Value) > High(Integer) then
  begin
    if Value > 0 then
    begin
      Result := High(Integer);
    end
    else
    begin
      Result := -High(Integer);
    end;
  end;
end;

{ TPdfRectangle }

class function TPdfRectangle.Letter: TPdfRectangle;
begin
  Result.LowerLeftX := 0;
  Result.LowerLeftY := 0;
  Result.UpperRightX := 8.5 * 72;
  Result.UpperRightY := 11 * 72;
end;

class function TPdfRectangle.FromCosArray(const Value: TCosArray): TPdfRectangle;
begin
  const Numbers = Value.ToFloatArray;
  var Values: array[0..3] of Single;
  for var Index := 0 to 3 do
  begin
    if Index < Length(Numbers) then
    begin
      Values[Index] := TJavaMath.LimitHugeValue(Numbers[Index]);
    end
    else
    begin
      Values[Index] := 0;
    end;
  end;

  Result.LowerLeftX := TJavaMath.Min(Values[0], Values[2]);
  Result.LowerLeftY := TJavaMath.Min(Values[1], Values[3]);
  Result.UpperRightX := TJavaMath.Max(Values[0], Values[2]);
  Result.UpperRightY := TJavaMath.Max(Values[1], Values[3]);
end;

function TPdfRectangle.ClipTo(const Bounds: TPdfRectangle): TPdfRectangle;
begin
  Result.LowerLeftX := TJavaMath.Max(Bounds.LowerLeftX, LowerLeftX);
  Result.LowerLeftY := TJavaMath.Max(Bounds.LowerLeftY, LowerLeftY);
  Result.UpperRightX := TJavaMath.Min(Bounds.UpperRightX, UpperRightX);
  Result.UpperRightY := TJavaMath.Min(Bounds.UpperRightY, UpperRightY);
end;

function TPdfRectangle.Width: Single;
begin
  Result := UpperRightX - LowerLeftX;
end;

function TPdfRectangle.Height: Single;
begin
  Result := UpperRightY - LowerLeftY;
end;

end.
