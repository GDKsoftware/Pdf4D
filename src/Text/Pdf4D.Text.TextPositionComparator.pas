// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/text/TextPositionComparator.java (3.0.8)
unit Pdf4D.Text.TextPositionComparator;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Defaults,
  Pdf4D.Text.TextPosition;

type
  // Sorts text by direction first, then top to bottom, and left to right within a line. The comparison uses a tolerance, so
  // it is not transitive: the stripper sorts with TTimSort first and falls back to TIterativeMergeSort when TimSort detects that.
  TTextPositionComparator = class
  public
    class function Compare(const Left, Right: TTextPosition): Integer; static;
    class function AsComparison: TComparison<TTextPosition>; static;
  end;

implementation

const
  LineTolerance: Double = 0.1;

{ TTextPositionComparator }

class function TTextPositionComparator.AsComparison: TComparison<TTextPosition>;
begin
  Result :=
    function(const Left, Right: TTextPosition): Integer
    begin
      Result := Compare(Left, Right);
    end;
end;

class function TTextPositionComparator.Compare(const Left, Right: TTextPosition): Integer;
begin
  // Only text in the same direction is compared
  const DirectionOrder = TJavaFloat.Compare(Left.Dir, Right.Dir);
  if DirectionOrder <> 0 then
  begin
    Exit(DirectionOrder);
  end;

  const LeftX = Left.XDirAdj;
  const RightX = Right.XDirAdj;

  const LeftYBottom = Left.YDirAdj;
  const RightYBottom = Right.YDirAdj;

  // The coordinates are adjusted so that 0,0 is in the upper left
  const LeftYTop = LeftYBottom - Left.HeightDir;
  const RightYTop = RightYBottom - Right.HeightDir;

  const YDifference = Abs(LeftYBottom - RightYBottom);

  // A simple tolerance comparison. Java compares the float difference with the double 0.1.
  if (Double(YDifference) < LineTolerance) or
     ((RightYBottom >= LeftYTop) and (RightYBottom <= LeftYBottom)) or
     ((LeftYBottom >= RightYTop) and (LeftYBottom <= RightYBottom)) then
  begin
    Result := TJavaFloat.Compare(LeftX, RightX);
  end
  else if LeftYBottom < RightYBottom then
  begin
    Result := -1;
  end
  else
  begin
    Result := 1;
  end;
end;

end.
