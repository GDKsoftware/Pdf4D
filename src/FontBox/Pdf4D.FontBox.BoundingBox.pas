// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/util/BoundingBox.java (3.0.8)
unit Pdf4D.FontBox.BoundingBox;

{$EXCESSPRECISION OFF}

interface

type
  TBoundingBox = record
    LowerLeftX: Single;
    LowerLeftY: Single;
    UpperRightX: Single;
    UpperRightY: Single;

    class function Create(const LowerLeftX, LowerLeftY, UpperRightX, UpperRightY: Single): TBoundingBox; static;

    function Width: Single;
    function Height: Single;
    function Contains(const X, Y: Single): Boolean;
  end;

implementation

{ TBoundingBox }

class function TBoundingBox.Create(const LowerLeftX, LowerLeftY, UpperRightX, UpperRightY: Single): TBoundingBox;
begin
  Result.LowerLeftX  := LowerLeftX;
  Result.LowerLeftY  := LowerLeftY;
  Result.UpperRightX := UpperRightX;
  Result.UpperRightY := UpperRightY;
end;

function TBoundingBox.Width: Single;
begin
  Result := UpperRightX - LowerLeftX;
end;

function TBoundingBox.Height: Single;
begin
  Result := UpperRightY - LowerLeftY;
end;

function TBoundingBox.Contains(const X, Y: Single): Boolean;
begin
  Result := ((X >= LowerLeftX) and (X <= UpperRightX) and (Y >= LowerLeftY) and (Y <= UpperRightY));
end;

end.
