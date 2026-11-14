// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/text/TextPosition.java (3.0.8)
unit Pdf4D.Text.TextPosition;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.Matrix,
  Pdf4D.Font.Base;

type
  // The Java float rules that the text code depends on
  TJavaFloat = record
  public
    // Float.compare: -0.0 is less than 0.0, and NaN is greater than everything and equal to itself
    class function Compare(const Left, Right: Single): Integer; static;
    // Float.compare(Left, Right) = 0
    class function IsSame(const Left, Right: Single): Boolean; static;
    // The (int) cast: truncates, saturates at the Integer range and turns NaN into 0
    class function ToInt(const Value: Single): Integer; static;
  end;

  // The position of one glyph (or, after merging, of a glyph with its diacritics) on the page, in display units, with the
  // legacy width and height rules of PDFBox. The font is not owned: it belongs to the document.
  TTextPosition = class
  private
    FTextMatrix: TPdfMatrix;
    FEndX: Single;
    FEndY: Single;
    FMaxHeight: Single;
    FRotation: Integer;
    FX: Single;
    FY: Single;
    FPageHeight: Single;
    FPageWidth: Single;
    FWidthOfSpace: Single;
    FCharCodes: TArray<Integer>;
    FFont: TPDFont;
    FFontSize: Single;
    FFontSizePt: Integer;
    FWidths: TArray<Single>;
    FUnicode: string;
    FDirection: Single;

    class function CreateDiacritics: TDictionary<Integer, string>; static;
    class function CombineDiacritic(const Text: string): string; static;
    class function JavaTrim(const Text: string): string; static;

    function XRot(const Rotation: Single): Single;
    function YLowerLeftRot(const Rotation: Single): Single;
    function WidthRot(const Rotation: Single): Single;
    function ComputeDirection: Single;
    procedure InsertDiacritic(const Index: Integer; const Diacritic: TTextPosition);
    function TryFindDiacriticIndex(const Diacritic: TTextPosition; out Index: Integer): Boolean;

    function GetDir: Single;
    function GetXDirAdj: Single;
    function GetYDirAdj: Single;
    function GetWidth: Single;
    function GetWidthDirAdj: Single;
    function GetHeightDir: Single;
    function GetFontSizeInPt: Single;
    function GetXScale: Single;
    function GetYScale: Single;
    function GetVisuallyOrderedUnicode: string;

  public
    class destructor Destroy;

    constructor Create(const PageRotation: Integer; const PageWidth, PageHeight: Single; const TextMatrix: TPdfMatrix; const EndX, EndY, MaxHeight,
                       IndividualWidth, SpaceWidth: Single; const Unicode: string; const CharCodes: TArray<Integer>; const Font: TPDFont;
                       const FontSize: Single; const FontSizeInPt: Integer);

    // Whether the other position overlaps this one on the line: more than 15% of the width in x, and some overlap in y
    function Contains(const Other: TTextPosition): Boolean;
    function CompletelyContains(const Other: TTextPosition): Boolean;
    // Adds a diacritic (a position of one character) to the character that it sits on
    procedure MergeDiacritic(const Diacritic: TTextPosition);
    // A single character of the category non-spacing mark, modifier symbol or modifier letter, except the prolonged sound
    // mark of Japanese
    function IsDiacritic: Boolean;

    function Equals(Obj: TObject): Boolean; override;
    function GetHashCode: Integer; override;
    function ToString: string; override;

    // The text is not put in visual order: there is no bidi, so right-to-left text stays in the order of the file
    property VisuallyOrderedUnicode: string read GetVisuallyOrderedUnicode;
    procedure SetUnicode(const Value: string);

    property Unicode: string read FUnicode;
    property CharacterCodes: TArray<Integer> read FCharCodes;
    property TextMatrix: TPdfMatrix read FTextMatrix;
    // 0, 90, 180 or 270: the direction of the text on the page
    property Dir: Single read GetDir;
    property X: Single read FX;
    property XDirAdj: Single read GetXDirAdj;
    property Y: Single read FY;
    property YDirAdj: Single read GetYDirAdj;
    property Width: Single read GetWidth;
    property WidthDirAdj: Single read GetWidthDirAdj;
    property Height: Single read FMaxHeight;
    property HeightDir: Single read GetHeightDir;
    property FontSize: Single read FFontSize;
    property FontSizeInPt: Single read GetFontSizeInPt;
    property Font: TPDFont read FFont;
    property WidthOfSpace: Single read FWidthOfSpace;
    property XScale: Single read GetXScale;
    property YScale: Single read GetYScale;
    property IndividualWidths: TArray<Single> read FWidths;
    property EndX: Single read FEndX;
    property EndY: Single read FEndY;
    // The rotation of the page
    property Rotation: Integer read FRotation;
    property PageHeight: Single read FPageHeight;
    property PageWidth: Single read FPageWidth;
  end;

implementation

uses
  System.Character,
  System.Math,
  Pdf4D.Common.SharedInstance,
  Pdf4D.Text.UnicodeTables;

const
  ProlongedSoundMark = Char($30FC);
  // The Unicode combining marks, first the ones that PDFBox maps by hand (see CreateDiacritics)
  DiacriticPairs: array[0..30, 0..1] of Integer = (
    ($0060, $0300), ($02CB, $0300), ($0027, $0301), ($02B9, $0301), ($02CA, $0301), ($005E, $0302), ($02C6, $0302),
    ($007E, $0303), ($02C9, $0304), ($00B0, $030A), ($02BA, $030B), ($02C7, $030C), ($02C8, $030D), ($0022, $030E),
    ($02BB, $0312), ($02BC, $0313), ($0486, $0313), ($055A, $0313), ($02BD, $0314), ($0485, $0314), ($0559, $0314),
    ($02D4, $031D), ($02D5, $031E), ($02D6, $031F), ($02D7, $0320), ($02B2, $0321), ($02CC, $0329), ($02B7, $032B),
    ($02CD, $0331), ($005F, $0332), ($204E, $0359));
  PercentageLimit = 0.15;
  NoDirection = -1;

var
  // Shared and immutable after publication, made on first use
  DiacriticsInstance: TPdfSharedInstance<TDictionary<Integer, string>>;

{ TJavaFloat }

class function TJavaFloat.Compare(const Left, Right: Single): Integer;
begin
  if Left < Right then
  begin
    Exit(-1);
  end;
  if Left > Right then
  begin
    Exit(1);
  end;

  const LeftIsNan = IsNan(Left);
  const RightIsNan = IsNan(Right);
  if LeftIsNan or RightIsNan then
  begin
    Exit(Ord(LeftIsNan) - Ord(RightIsNan));
  end;

  // Equal as numbers; only the sign of a zero can still tell them apart
  const LeftIsNegativeZero = (Left.SpecialType = TFloatSpecial.fsNZero);
  const RightIsNegativeZero = (Right.SpecialType = TFloatSpecial.fsNZero);
  Result := Ord(RightIsNegativeZero) - Ord(LeftIsNegativeZero);
end;

class function TJavaFloat.IsSame(const Left, Right: Single): Boolean;
begin
  Result := (Compare(Left, Right) = 0);
end;

class function TJavaFloat.ToInt(const Value: Single): Integer;
begin
  if IsNan(Value) then
  begin
    Exit(0);
  end;
  if Value >= 2147483648.0 then
  begin
    Exit(High(Integer));
  end;
  if Value <= -2147483648.0 then
  begin
    Exit(Low(Integer));
  end;
  Result := Trunc(Value);
end;

{ TTextPosition }

class destructor TTextPosition.Destroy;
begin
  DiacriticsInstance.Release;
end;

class function TTextPosition.CreateDiacritics: TDictionary<Integer, string>;
begin
  Result := TDictionary<Integer, string>.Create(Length(DiacriticPairs));
  for var Index := 0 to High(DiacriticPairs) do
  begin
    Result.Add(DiacriticPairs[Index, 0], Char(DiacriticPairs[Index, 1]));
  end;
end;

constructor TTextPosition.Create(const PageRotation: Integer; const PageWidth, PageHeight: Single; const TextMatrix: TPdfMatrix; const EndX, EndY,
                                 MaxHeight, IndividualWidth, SpaceWidth: Single; const Unicode: string; const CharCodes: TArray<Integer>;
                                 const Font: TPDFont; const FontSize: Single; const FontSizeInPt: Integer);
begin
  inherited Create;
  FTextMatrix := TextMatrix;
  FEndX := EndX;
  FEndY := EndY;
  FRotation := PageRotation;
  FMaxHeight := MaxHeight;
  FPageHeight := PageHeight;
  FPageWidth := PageWidth;
  FWidths := [IndividualWidth];
  FWidthOfSpace := SpaceWidth;
  FUnicode := Unicode;
  FCharCodes := CharCodes;
  FFont := Font;
  FFontSize := FontSize;
  FFontSizePt := FontSizeInPt;
  FDirection := NoDirection;

  FX := XRot(FRotation);
  if (FRotation = 0) or (FRotation = 180) then
  begin
    FY := FPageHeight - YLowerLeftRot(FRotation);
  end
  else
  begin
    FY := FPageWidth - YLowerLeftRot(FRotation);
  end;
end;

procedure TTextPosition.SetUnicode(const Value: string);
begin
  FUnicode := Value;
end;

function TTextPosition.GetVisuallyOrderedUnicode: string;
begin
  Result := FUnicode;
end;

function TTextPosition.ComputeDirection: Single;
begin
  const A = FTextMatrix.ScaleY;
  const B = FTextMatrix.ShearY;
  const C = FTextMatrix.ShearX;
  const D = FTextMatrix.ScaleX;

  // 12 0   left to right
  // 0 12
  if (A > 0) and (Abs(B) < D) and (Abs(C) < A) and (D > 0) then
  begin
    Result := 0;
  end
  // -12 0   right to left (upside down)
  // 0 -12
  else if (A < 0) and (Abs(B) < Abs(D)) and (Abs(C) < Abs(A)) and (D < 0) then
  begin
    Result := 180;
  end
  // 0  12    up
  // -12 0
  else if (Abs(A) < Abs(C)) and (B > 0) and (C < 0) and (Abs(D) < B) then
  begin
    Result := 90;
  end
  // 0  -12   down
  // 12 0
  else if (Abs(A) < C) and (B < 0) and (C > 0) and (Abs(D) < Abs(B)) then
  begin
    Result := 270;
  end
  else
  begin
    Result := 0;
  end;
end;

function TTextPosition.GetDir: Single;
begin
  if FDirection < 0 then
  begin
    FDirection := ComputeDirection;
  end;
  Result := FDirection;
end;

function TTextPosition.XRot(const Rotation: Single): Single;
begin
  Result := 0;
  if TJavaFloat.IsSame(Rotation, 0) then
  begin
    Result := FTextMatrix.TranslateX;
  end
  else if TJavaFloat.IsSame(Rotation, 90) then
  begin
    Result := FTextMatrix.TranslateY;
  end
  else if TJavaFloat.IsSame(Rotation, 180) then
  begin
    Result := FPageWidth - FTextMatrix.TranslateX;
  end
  else if TJavaFloat.IsSame(Rotation, 270) then
  begin
    Result := FPageHeight - FTextMatrix.TranslateY;
  end;
end;

function TTextPosition.GetXDirAdj: Single;
begin
  Result := XRot(Dir);
end;

function TTextPosition.YLowerLeftRot(const Rotation: Single): Single;
begin
  Result := 0;
  if TJavaFloat.IsSame(Rotation, 0) then
  begin
    Result := FTextMatrix.TranslateY;
  end
  else if TJavaFloat.IsSame(Rotation, 90) then
  begin
    Result := FPageWidth - FTextMatrix.TranslateX;
  end
  else if TJavaFloat.IsSame(Rotation, 180) then
  begin
    Result := FPageHeight - FTextMatrix.TranslateY;
  end
  else if TJavaFloat.IsSame(Rotation, 270) then
  begin
    Result := FTextMatrix.TranslateX;
  end;
end;

function TTextPosition.GetYDirAdj: Single;
begin
  const Direction = Dir;
  // Some PDFBox code assumes that the 0,0 point is in the upper left, not in the lower left
  if TJavaFloat.IsSame(Direction, 0) or TJavaFloat.IsSame(Direction, 180) then
  begin
    Result := FPageHeight - YLowerLeftRot(Direction);
  end
  else
  begin
    Result := FPageWidth - YLowerLeftRot(Direction);
  end;
end;

function TTextPosition.WidthRot(const Rotation: Single): Single;
begin
  if TJavaFloat.IsSame(Rotation, 90) or TJavaFloat.IsSame(Rotation, 270) then
  begin
    Result := Abs(FEndY - FTextMatrix.TranslateY);
  end
  else
  begin
    Result := Abs(FEndX - FTextMatrix.TranslateX);
  end;
end;

function TTextPosition.GetWidth: Single;
begin
  Result := WidthRot(FRotation);
end;

function TTextPosition.GetWidthDirAdj: Single;
begin
  Result := WidthRot(Dir);
end;

function TTextPosition.GetHeightDir: Single;
begin
  // Not really a rotation dependent calculation, but defined for symmetry
  Result := FMaxHeight;
end;

function TTextPosition.GetFontSizeInPt: Single;
begin
  Result := FFontSizePt;
end;

function TTextPosition.GetXScale: Single;
begin
  Result := FTextMatrix.ScalingFactorX;
end;

function TTextPosition.GetYScale: Single;
begin
  Result := FTextMatrix.ScalingFactorY;
end;

function TTextPosition.Contains(const Other: TTextPosition): Boolean;
begin
  const ThisXStart: Double = XDirAdj;
  const ThisWidth: Double = WidthDirAdj;
  const ThisXEnd: Double = ThisXStart + ThisWidth;

  const OtherXStart: Double = Other.XDirAdj;
  const OtherXEnd: Double = OtherXStart + Other.WidthDirAdj;

  // No overlap in x at all
  if (OtherXEnd <= ThisXStart) or (OtherXStart >= ThisXEnd) then
  begin
    Exit(False);
  end;

  // No overlap in y at all. 0.0 is in the upper left and the y coordinate is the top of the position.
  const ThisYStart: Double = YDirAdj;
  const OtherYStart: Double = Other.YDirAdj;
  if (OtherYStart + Other.HeightDir < ThisYStart) or (OtherYStart > ThisYStart + HeightDir) then
  begin
    Exit(False);
  end;

  // Less than 15% overlap in x is negligible, the percentage was found by trial and error on the PDFBox regression files
  if (OtherXStart > ThisXStart) and (OtherXEnd > ThisXEnd) then
  begin
    Result := ((ThisXEnd - OtherXStart) / ThisWidth > PercentageLimit);
  end
  else if (OtherXStart < ThisXStart) and (OtherXEnd < ThisXEnd) then
  begin
    Result := ((OtherXEnd - ThisXStart) / ThisWidth > PercentageLimit);
  end
  else
  begin
    Result := True;
  end;
end;

function TTextPosition.CompletelyContains(const Other: TTextPosition): Boolean;
begin
  // (0, 0) is in the upper left and the y coordinate is the top of the position
  const ThisLeft = XDirAdj;
  const ThisRight = ThisLeft + WidthDirAdj;
  const OtherLeft = Other.XDirAdj;
  const OtherRight = OtherLeft + Other.WidthDirAdj;
  if (ThisLeft > OtherLeft) or (OtherRight > ThisRight) then
  begin
    Exit(False);
  end;

  const ThisTop = YDirAdj;
  const ThisBottom = ThisTop + HeightDir;
  const OtherTop = Other.YDirAdj;
  const OtherBottom = OtherTop + Other.HeightDir;
  Result := not ((ThisTop > OtherTop) or (OtherBottom > ThisBottom));
end;

function TTextPosition.TryFindDiacriticIndex(const Diacritic: TTextPosition; out Index: Integer): Boolean;
begin
  Index := 0;
  Result := False;
  const DiacriticXStart = Diacritic.XDirAdj;
  const DiacriticXEnd = DiacriticXStart + Diacritic.FWidths[0];
  var CurrentXStart := XDirAdj;
  const Count = Length(FUnicode);

  var Position := 0;
  while (Position < Count) and (not Result) do
  begin
    if Position >= Length(FWidths) then
    begin
      // A ligature: PDFBOX-2831
      Break;
    end;

    const CurrentXEnd = CurrentXStart + FWidths[Position];
    // The diacritic overlaps the current character and the one before it. Without a previous character it goes behind the
    // current one.
    if (DiacriticXStart < CurrentXStart) and (DiacriticXEnd <= CurrentXEnd) then
    begin
      Index := Position;
      if Position > 0 then
      begin
        const OverlapWithCurrent = (DiacriticXEnd - CurrentXStart) / FWidths[Position];
        const OverlapWithPrevious = (CurrentXStart - DiacriticXStart) / FWidths[Position - 1];
        if not (OverlapWithCurrent >= OverlapWithPrevious) then
        begin
          Index := Position - 1;
        end;
      end;
      Result := True;
    end
    // The diacritic covers this character completely, so it belongs to it
    else if DiacriticXStart < CurrentXStart then
    begin
      Index := Position;
      Result := True;
    end
    // The character width contains the diacritic completely
    else if DiacriticXEnd <= CurrentXEnd then
    begin
      Index := Position;
      Result := True;
    end
    // The last character of the position gets the diacritic at its end
    else if Position = Count - 1 then
    begin
      Index := Position;
      Result := True;
    end;

    if not Result then
    begin
      CurrentXStart := CurrentXStart + FWidths[Position];
    end;
    Inc(Position);
  end;
end;

procedure TTextPosition.MergeDiacritic(const Diacritic: TTextPosition);
begin
  if Length(Diacritic.Unicode) > 1 then
  begin
    Exit;
  end;

  var Index: Integer;
  if TryFindDiacriticIndex(Diacritic, Index) then
  begin
    InsertDiacritic(Index, Diacritic);
  end;
end;

procedure TTextPosition.InsertDiacritic(const Index: Integer; const Diacritic: TTextPosition);
begin
  // Java index Index is Delphi position Index + 1
  var Last := Index;
  var Merged := Copy(FUnicode, 1, Index);

  var NewWidths: TArray<Single>;
  SetLength(NewWidths, Length(FWidths) + 1);
  for var Position := 0 to Index - 1 do
  begin
    NewWidths[Position] := FWidths[Position];
  end;
  // A zero width entry for the diacritic
  NewWidths[Index] := FWidths[Index];
  NewWidths[Index + 1] := 0;
  for var Position := Index + 1 to High(FWidths) do
  begin
    NewWidths[Position + 1] := FWidths[Position];
  end;

  // Combining diacritics always go after the base character, whether the string is in presentation or in logical order
  Merged := Merged + FUnicode[Index + 1];
  // A surrogate pair that starts here stays together
  if (Index < Length(FUnicode) - 1) and FUnicode[Index + 1].IsHighSurrogate and FUnicode[Index + 2].IsLowSurrogate then
  begin
    Merged := Merged + FUnicode[Index + 2];
    Inc(Last);
  end;
  Merged := Merged + CombineDiacritic(Diacritic.Unicode) + Copy(FUnicode, Last + 2, MaxInt);

  FUnicode := Merged;
  FWidths := NewWidths;
end;

class function TTextPosition.JavaTrim(const Text: string): string;
begin
  var First := 1;
  var Last := Length(Text);
  while (First <= Last) and (Text[First] <= ' ') do
  begin
    Inc(First);
  end;
  while (Last >= First) and (Text[Last] <= ' ') do
  begin
    Dec(Last);
  end;
  Result := Copy(Text, First, Last - First + 1);
end;

class function TTextPosition.CombineDiacritic(const Text: string): string;
begin
  if Text = '' then
  begin
    Exit('');
  end;

  // Unicode has special combining forms of the diacritic characters, which are the ones we want
  const Diacritics = DiacriticsInstance.Get(CreateDiacritics);
  var CodePoint := Integer(Text[1]);
  if Text[1].IsHighSurrogate and (Length(Text) > 1) then
  begin
    CodePoint := Char.ConvertToUtf32(Text, 0);
  end;

  var Combining: string;
  if Diacritics.TryGetValue(CodePoint, Combining) then
  begin
    Exit(Combining);
  end;

  // Normalizer.normalize(text, NFKC).trim(). The table has the characters that can be a diacritic; any other character
  // normalizes to itself here.
  var Normalized: string;
  if (Length(Text) = 1) and TPdfUnicodeText.Instance.TryGetNfkc(Text[1], Normalized) then
  begin
    Result := Normalized;
  end
  else
  begin
    Result := JavaTrim(Text);
  end;
end;

function TTextPosition.IsDiacritic: Boolean;
begin
  if Length(FUnicode) <> 1 then
  begin
    Exit(False);
  end;

  // PDFBOX-3833: the prolonged sound mark is no real diacritic like the diaeresis. It is printed after the previous glyph
  // and may touch the next one, which must not make it a diacritic.
  if FUnicode[1] = ProlongedSoundMark then
  begin
    Exit(False);
  end;

  Result := TPdfUnicodeText.Instance.IsDiacriticCategory(FUnicode[1]);
end;

function TTextPosition.ToString: string;
begin
  Result := FUnicode;
end;

function TTextPosition.Equals(Obj: TObject): Boolean;
begin
  if Obj = Self then
  begin
    Exit(True);
  end;
  if not (Obj is TTextPosition) then
  begin
    Exit(False);
  end;

  // The mutable fields (unicode and widths) are not compared: PDFBOX-4701
  const Other = TTextPosition(Obj);
  Result := (TJavaFloat.IsSame(Other.FEndX, FEndX) and TJavaFloat.IsSame(Other.FEndY, FEndY) and
             TJavaFloat.IsSame(Other.FMaxHeight, FMaxHeight) and (FRotation = Other.FRotation) and
             TJavaFloat.IsSame(Other.FX, FX) and TJavaFloat.IsSame(Other.FY, FY) and
             TJavaFloat.IsSame(Other.FPageHeight, FPageHeight) and TJavaFloat.IsSame(Other.FPageWidth, FPageWidth) and
             TJavaFloat.IsSame(Other.FWidthOfSpace, FWidthOfSpace) and TJavaFloat.IsSame(Other.FFontSize, FFontSize) and
             (FFontSizePt = Other.FFontSizePt) and FTextMatrix.IsEqual(Other.FTextMatrix) and
             (Length(FCharCodes) = Length(Other.FCharCodes)) and (FFont = Other.FFont));
  if Result then
  begin
    for var Index := 0 to High(FCharCodes) do
    begin
      Result := (Result and (FCharCodes[Index] = Other.FCharCodes[Index]));
    end;
  end;
end;

function TTextPosition.GetHashCode: Integer;
begin
  // Consistent with Equals: only fields that Equals compares, and only ones that cannot differ by a negative zero
  Result := FRotation;
  Result := Result xor (FFontSizePt shl 8);
  for var Code in FCharCodes do
  begin
    Result := Result xor Code;
  end;
end;

end.
