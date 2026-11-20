// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Not a port of PDFBox, which leaves the conversion of ICC colours to the Java colour management. Written from the
// specification ICC.1:2010: device values go through the A2B0 table (or else A2B1, A2B2) or through the matrix and the
// curves of the profile to the D50 PCS, from there through the Bradford-adapted matrix of sRGB and the sRGB curve to sRGB.
// The CLUT is interpolated the way Little CMS does (tetrahedral over the last three inputs, linear over the others), which
// is the colour management behind Java's ICC_ColorSpace.
unit Pdf4D.Graphics.Icc.Transform;

{$POINTERMATH ON}
{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Graphics.Icc.Profile;

const
  // Entries of the cache of ToRgbRow; a power of two
  IccRowCacheSize = 4096;

type
  TIccCacheEntry = record
    Key: Cardinal;
    Red: Byte;
    Green: Byte;
    Blue: Byte;
    IsUsed: Boolean;
  end;

  // The position in a CLUT that a colour falls on: per input the point below the colour and the distance to it
  TIccClutCursor = record
    Points: array[0..MaxIccClutInputs - 1] of Integer;
    Fractions: array[0..MaxIccClutInputs - 1] of Single;
  end;

  // Converts device values of a profile to sRGB. A transform does not own the profile, which must outlive it, and is not
  // thread safe (it keeps a cache).
  TIccTransform = class
  private
    FProfile: TIccProfile;
    FComponents: Integer;
    FCache: TArray<TIccCacheEntry>;

    class function CleanInput(const Value: Single): Single; static;
    class procedure LabToXyz(const L, A, B: Double; const Xyz: PDouble); static;
    class procedure XyzToSrgb(const Xyz: PDouble; const Output: PSingle); static;
    class function SrgbEncode(const Linear: Double): Double; static;
    class function LabInverse(const Value: Double): Double; static;

    procedure DeviceToXyz(const Device: PSingle; const Xyz: PDouble);
    procedure LutToXyz(const Device: PSingle; const Xyz: PDouble);
    procedure MatrixTrcToXyz(const Device: PSingle; const Xyz: PDouble);
    procedure GrayTrcToXyz(const Device: PSingle; const Xyz: PDouble);
    procedure RunLut(const Lut: TIccLut; const Values: PSingle);
    procedure RunClut(const Lut: TIccLut; const Values: PSingle);
    procedure RunMatrix(const Lut: TIccLut; const Values: PSingle);
    procedure PcsToXyz(const Lut: TIccLut; const Values: PSingle; const Xyz: PDouble);
    procedure CacheLookup(const Pixel: PByte; const Target: PByte);
    procedure ConvertPixel(const Pixel: PByte; const Target: PByte);

    class procedure MakeCursor(const Lut: TIccLut; const Values: PSingle; out Cursor: TIccClutCursor); static;
    class function ClutEntry(const Lut: TIccLut; const Position: Integer): Single; static;
    class procedure InterpolateDimension(const Lut: TIccLut; const Cursor: TIccClutCursor; const Dimension, Base: Integer; const Output: PSingle); static;
    class procedure InterpolateLinear(const Lut: TIccLut; const Cursor: TIccClutCursor; const Dimension, Base: Integer; const Output: PSingle); static;
    class procedure InterpolateBilinear(const Lut: TIccLut; const Cursor: TIccClutCursor; const Dimension, Base: Integer; const Output: PSingle); static;
    class procedure InterpolateTetrahedral(const Lut: TIccLut; const Cursor: TIccClutCursor; const Dimension, Base: Integer; const Output: PSingle); static;

  public
    constructor Create(const Profile: TIccProfile);

    // Input has NumberOfComponents values of 0..1 (anything else is clamped, not a number is 0), Output gets 3 values of 0..1.
    // Never raises.
    procedure ToRgb(const Input: PSingle; const Output: PSingle);

    // Converts Count pixels of 8-bit samples (NumberOfComponents bytes each) to 8-bit RGB (3 bytes each). The cache that it
    // fills on the first call makes up the only allocation. Never raises.
    procedure ToRgbRow(const Input: PByte; const Output: PByte; const Count: Integer);
  end;

implementation

uses
  System.Math;

const
  // The D50 white of the PCS
  WhiteX = 0.9642;
  WhiteZ = 0.8249;

  // The PCS encoding of XYZ in a LUT: 1.0 is 1 + 32767/32768
  XyzEncodingScale = 65535.0 / 32768.0;

  // Lab in a LUT (ICC.1:2010, 6.3.4.2 and 10.8): L* 100 and a* 255 are the largest value; lut16 uses 0xFF00 and 0x8000 steps
  LegacyLabLightnessScale = 65535.0 / 65280.0 * 100.0;
  LegacyLabChromaScale = 65535.0 / 256.0;

  LabEpsilon = 6.0 / 29.0;

  // The XYZ (D50) to linear sRGB matrix: the inverse of the colorants of the sRGB profile that Java carries (the HP sRGB
  // profile, also the sRGB.icc of PDFBox: 0.43585 0.38533 0.14302 / 0.22238 0.71704 0.06059 / 0.01392 0.09714 0.71384)
  XyzToRed: array[0..2] of Double = (3.1359360, -1.6187167, -0.4908983);
  XyzToGreen: array[0..2] of Double = (-0.9786602, 1.9160115, 0.0334424);
  XyzToBlue: array[0..2] of Double = (0.0720400, -0.2291706, 1.4058998);

  MaxDeviceChannels = MaxIccClutInputs;
  ByteScale = 1.0 / 255.0;
  ClutScale = 1.0 / 65535.0;
  MaxCachedComponents = 4;

{ TIccTransform }

constructor TIccTransform.Create(const Profile: TIccProfile);
begin
  inherited Create;
  FProfile := Profile;
  FComponents := Profile.NumberOfComponents;
end;

// Not a number is 0, infinity and the rest outside 0..1 clamp. Works on the bits so that no comparison sees a NaN (a
// comparison with a NaN raises in Delphi when the exception is not masked).
class function TIccTransform.CleanInput(const Value: Single): Single;
begin
  var Bits: Cardinal;
  Move(Value, Bits, SizeOf(Bits));
  const IsSpecial = ((Bits and $7F800000) = $7F800000);
  if IsSpecial then
  begin
    const IsNan = ((Bits and $007FFFFF) <> 0);
    const IsNegative = ((Bits and $80000000) <> 0);
    if IsNan or IsNegative then
    begin
      Exit(0.0);
    end;
    Exit(1.0);
  end;

  if Value < 0.0 then
  begin
    Result := 0.0;
  end
  else if Value > 1.0 then
  begin
    Result := 1.0;
  end
  else
  begin
    Result := Value;
  end;
end;

class function TIccTransform.LabInverse(const Value: Double): Double;
begin
  if Value > LabEpsilon then
  begin
    Result := Value * Value * Value;
  end
  else
  begin
    Result := 3.0 * LabEpsilon * LabEpsilon * (Value - 4.0 / 29.0);
  end;
end;

// CIE L*a*b* (D50) to XYZ; Xyz points at 3 values
class procedure TIccTransform.LabToXyz(const L, A, B: Double; const Xyz: PDouble);
begin
  const FY = (L + 16.0) / 116.0;
  const FX = FY + A / 500.0;
  const FZ = FY - B / 200.0;
  Xyz[0] := WhiteX * LabInverse(FX);
  Xyz[1] := LabInverse(FY);
  Xyz[2] := WhiteZ * LabInverse(FZ);
end;

class function TIccTransform.SrgbEncode(const Linear: Double): Double;
begin
  const Clamped = TIccCurve.ClampToUnit(Linear);
  if Clamped <= 0.0031308 then
  begin
    Result := 12.92 * Clamped;
  end
  else
  begin
    Result := 1.055 * TIccCurve.SafePower(Clamped, 1.0 / 2.4) - 0.055;
  end;
end;

class procedure TIccTransform.XyzToSrgb(const Xyz: PDouble; const Output: PSingle);
begin
  const Red = XyzToRed[0] * Xyz[0] + XyzToRed[1] * Xyz[1] + XyzToRed[2] * Xyz[2];
  const Green = XyzToGreen[0] * Xyz[0] + XyzToGreen[1] * Xyz[1] + XyzToGreen[2] * Xyz[2];
  const Blue = XyzToBlue[0] * Xyz[0] + XyzToBlue[1] * Xyz[1] + XyzToBlue[2] * Xyz[2];
  Output[0] := SrgbEncode(Red);
  Output[1] := SrgbEncode(Green);
  Output[2] := SrgbEncode(Blue);
end;

procedure TIccTransform.ToRgb(const Input: PSingle; const Output: PSingle);
begin
  var Device: array[0..MaxDeviceChannels - 1] of Single;
  var Xyz: array[0..2] of Double;

  for var Index := 0 to FComponents - 1 do
  begin
    Device[Index] := CleanInput(Input[Index]);
  end;
  DeviceToXyz(@Device[0], @Xyz[0]);
  XyzToSrgb(@Xyz[0], Output);
end;

procedure TIccTransform.DeviceToXyz(const Device: PSingle; const Xyz: PDouble);
begin
  case FProfile.SourceKind of
    TIccSourceKind.Lut       : LutToXyz(Device, Xyz);
    TIccSourceKind.MatrixTrc : MatrixTrcToXyz(Device, Xyz);
    TIccSourceKind.GrayTrc   : GrayTrcToXyz(Device, Xyz);
  else
    raise ENotSupportedException.CreateFmt('Unsupported ICC source: %d', [Ord(FProfile.SourceKind)]);
  end;
end;

procedure TIccTransform.MatrixTrcToXyz(const Device: PSingle; const Xyz: PDouble);
begin
  const Red = FProfile.Curves[0].Evaluate(Device[0]);
  const Green = FProfile.Curves[1].Evaluate(Device[1]);
  const Blue = FProfile.Curves[2].Evaluate(Device[2]);
  const Colorants = FProfile.Colorants;
  for var Row := 0 to 2 do
  begin
    Xyz[Row] := Colorants[Row] * Red + Colorants[3 + Row] * Green + Colorants[6 + Row] * Blue;
  end;
end;

procedure TIccTransform.GrayTrcToXyz(const Device: PSingle; const Xyz: PDouble);
begin
  const Luminance = FProfile.Curves[0].Evaluate(Device[0]);
  if FProfile.Pcs = TIccPcs.Lab then
  begin
    LabToXyz(Luminance * 100.0, 0.0, 0.0, Xyz);
  end
  else
  begin
    Xyz[0] := WhiteX * Luminance;
    Xyz[1] := Luminance;
    Xyz[2] := WhiteZ * Luminance;
  end;
end;

procedure TIccTransform.LutToXyz(const Device: PSingle; const Xyz: PDouble);
begin
  var Values: array[0..MaxDeviceChannels - 1] of Single;
  for var Index := 0 to FComponents - 1 do
  begin
    Values[Index] := Device[Index];
  end;

  RunLut(FProfile.Lut, @Values[0]);
  PcsToXyz(FProfile.Lut, @Values[0], Xyz);
end;

// The stages in the order of lutAToB: A curves, CLUT, M curves, matrix, B curves (a lut8 or lut16 has A, CLUT and B)
procedure TIccTransform.RunLut(const Lut: TIccLut; const Values: PSingle);
begin
  const HasCurvesA = (Lut.ACurves.Count > 0);
  if HasCurvesA then
  begin
    for var Index := 0 to Lut.InputCount - 1 do
    begin
      Values[Index] := Lut.ACurves[Index].Evaluate(Values[Index]);
    end;
  end;

  const HasClut = (Length(Lut.GridPoints) > 0);
  if HasClut then
  begin
    RunClut(Lut, Values);
  end;

  const HasCurvesM = (Lut.MCurves.Count > 0);
  if HasCurvesM then
  begin
    for var Index := 0 to 2 do
    begin
      Values[Index] := Lut.MCurves[Index].Evaluate(Values[Index]);
    end;
  end;

  const HasMatrix = (Length(Lut.Matrix) > 0);
  if HasMatrix then
  begin
    RunMatrix(Lut, Values);
  end;

  const HasCurvesB = (Lut.BCurves.Count > 0);
  for var Index := 0 to 2 do
  begin
    if HasCurvesB then
    begin
      Values[Index] := Lut.BCurves[Index].Evaluate(Values[Index]);
    end
    else
    begin
      Values[Index] := TIccCurve.ClampToUnit(Values[Index]);
    end;
  end;
end;

procedure TIccTransform.RunMatrix(const Lut: TIccLut; const Values: PSingle);
begin
  const Matrix = Lut.Matrix;
  var Result: array[0..2] of Single;
  for var Row := 0 to 2 do
  begin
    const Sum = Matrix[Row * 3] * Values[0] + Matrix[Row * 3 + 1] * Values[1] + Matrix[Row * 3 + 2] * Values[2] + Matrix[9 + Row];
    Result[Row] := TIccCurve.ClampToUnit(Sum);
  end;
  for var Row := 0 to 2 do
  begin
    Values[Row] := Result[Row];
  end;
end;

procedure TIccTransform.RunClut(const Lut: TIccLut; const Values: PSingle);
begin
  var Cursor: TIccClutCursor;
  var Output: array[0..2] of Single;

  MakeCursor(Lut, Values, Cursor);
  InterpolateDimension(Lut, Cursor, 0, 0, @Output[0]);
  for var Index := 0 to 2 do
  begin
    Values[Index] := Output[Index];
  end;
end;

procedure TIccTransform.PcsToXyz(const Lut: TIccLut; const Values: PSingle; const Xyz: PDouble);
begin
  if FProfile.Pcs = TIccPcs.Xyz then
  begin
    for var Index := 0 to 2 do
    begin
      Xyz[Index] := Values[Index] * XyzEncodingScale;
    end;
    Exit;
  end;

  if Lut.LabEncoding = TIccLabEncoding.Legacy16 then
  begin
    LabToXyz(Values[0] * LegacyLabLightnessScale, Values[1] * LegacyLabChromaScale - 128.0, Values[2] * LegacyLabChromaScale - 128.0, Xyz);
  end
  else
  begin
    LabToXyz(Values[0] * 100.0, Values[1] * 255.0 - 128.0, Values[2] * 255.0 - 128.0, Xyz);
  end;
end;

class procedure TIccTransform.MakeCursor(const Lut: TIccLut; const Values: PSingle; out Cursor: TIccClutCursor);
begin
  for var Dimension := 0 to Lut.InputCount - 1 do
  begin
    const LastPoint = Lut.GridPoints[Dimension] - 1;
    const Position = Values[Dimension] * LastPoint;
    const Point = Min(Trunc(Position), LastPoint - 1);
    Cursor.Points[Dimension] := Point;
    Cursor.Fractions[Dimension] := Position - Point;
  end;
end;

class function TIccTransform.ClutEntry(const Lut: TIccLut; const Position: Integer): Single;
begin
  Result := Lut.Clut[Position] * ClutScale;
end;

// Interpolates over the inputs from Dimension on, the corner of the cell at Base: more than three inputs left is a linear
// interpolation between the cells of the two points of this input, three is tetrahedral, two bilinear and one linear
class procedure TIccTransform.InterpolateDimension(const Lut: TIccLut; const Cursor: TIccClutCursor; const Dimension, Base: Integer; const Output: PSingle);
begin
  const Remaining = Lut.InputCount - Dimension;
  case Remaining of
    1 : InterpolateLinear(Lut, Cursor, Dimension, Base, Output);
    2 : InterpolateBilinear(Lut, Cursor, Dimension, Base, Output);
    3 : InterpolateTetrahedral(Lut, Cursor, Dimension, Base, Output);
  else
    var Low: array[0..2] of Single;
    var High: array[0..2] of Single;
    const LowBase = Base + Cursor.Points[Dimension] * Lut.Strides[Dimension];
    InterpolateDimension(Lut, Cursor, Dimension + 1, LowBase, @Low[0]);
    InterpolateDimension(Lut, Cursor, Dimension + 1, LowBase + Lut.Strides[Dimension], @High[0]);
    const Fraction = Cursor.Fractions[Dimension];
    for var Channel := 0 to 2 do
    begin
      Output[Channel] := Low[Channel] + (High[Channel] - Low[Channel]) * Fraction;
    end;
  end;
end;

class procedure TIccTransform.InterpolateLinear(const Lut: TIccLut; const Cursor: TIccClutCursor; const Dimension, Base: Integer; const Output: PSingle);
begin
  const Origin = Base + Cursor.Points[Dimension] * Lut.Strides[Dimension];
  const Fraction = Cursor.Fractions[Dimension];
  for var Channel := 0 to 2 do
  begin
    const Low = ClutEntry(Lut, Origin + Channel);
    const High = ClutEntry(Lut, Origin + Lut.Strides[Dimension] + Channel);
    Output[Channel] := Low + (High - Low) * Fraction;
  end;
end;

class procedure TIccTransform.InterpolateBilinear(const Lut: TIccLut; const Cursor: TIccClutCursor; const Dimension, Base: Integer; const Output: PSingle);
begin
  const StrideX = Lut.Strides[Dimension];
  const StrideY = Lut.Strides[Dimension + 1];
  const Origin = Base + Cursor.Points[Dimension] * StrideX + Cursor.Points[Dimension + 1] * StrideY;
  const FractionX = Cursor.Fractions[Dimension];
  const FractionY = Cursor.Fractions[Dimension + 1];
  for var Channel := 0 to 2 do
  begin
    const C00 = ClutEntry(Lut, Origin + Channel);
    const C10 = ClutEntry(Lut, Origin + StrideX + Channel);
    const C01 = ClutEntry(Lut, Origin + StrideY + Channel);
    const C11 = ClutEntry(Lut, Origin + StrideX + StrideY + Channel);
    const AlongY0 = C00 + (C01 - C00) * FractionY;
    const AlongY1 = C10 + (C11 - C10) * FractionY;
    Output[Channel] := AlongY0 + (AlongY1 - AlongY0) * FractionX;
  end;
end;

// Tetrahedral interpolation (Little CMS, Eval3Inputs): the cell is split in six tetrahedra by the order of the fractions
class procedure TIccTransform.InterpolateTetrahedral(const Lut: TIccLut; const Cursor: TIccClutCursor; const Dimension, Base: Integer; const Output: PSingle);
begin
  const StrideX = Lut.Strides[Dimension];
  const StrideY = Lut.Strides[Dimension + 1];
  const StrideZ = Lut.Strides[Dimension + 2];
  const Origin = Base + Cursor.Points[Dimension] * StrideX + Cursor.Points[Dimension + 1] * StrideY + Cursor.Points[Dimension + 2] * StrideZ;
  const Rx = Cursor.Fractions[Dimension];
  const Ry = Cursor.Fractions[Dimension + 1];
  const Rz = Cursor.Fractions[Dimension + 2];

  for var Channel := 0 to 2 do
  begin
    const C000 = ClutEntry(Lut, Origin + Channel);
    const C001 = ClutEntry(Lut, Origin + StrideZ + Channel);
    const C010 = ClutEntry(Lut, Origin + StrideY + Channel);
    const C011 = ClutEntry(Lut, Origin + StrideY + StrideZ + Channel);
    const C100 = ClutEntry(Lut, Origin + StrideX + Channel);
    const C101 = ClutEntry(Lut, Origin + StrideX + StrideZ + Channel);
    const C110 = ClutEntry(Lut, Origin + StrideX + StrideY + Channel);
    const C111 = ClutEntry(Lut, Origin + StrideX + StrideY + StrideZ + Channel);

    var Slope1, Slope2, Slope3: Single;
    if (Rx >= Ry) and (Ry >= Rz) then
    begin
      Slope1 := C100 - C000;
      Slope2 := C110 - C100;
      Slope3 := C111 - C110;
    end
    else if (Rx >= Rz) and (Rz >= Ry) then
    begin
      Slope1 := C100 - C000;
      Slope2 := C111 - C101;
      Slope3 := C101 - C100;
    end
    else if (Rz >= Rx) and (Rx >= Ry) then
    begin
      Slope1 := C101 - C001;
      Slope2 := C111 - C101;
      Slope3 := C001 - C000;
    end
    else if (Ry >= Rx) and (Rx >= Rz) then
    begin
      Slope1 := C110 - C010;
      Slope2 := C010 - C000;
      Slope3 := C111 - C110;
    end
    else if (Ry >= Rz) and (Rz >= Rx) then
    begin
      Slope1 := C111 - C011;
      Slope2 := C010 - C000;
      Slope3 := C011 - C010;
    end
    else
    begin
      Slope1 := C111 - C011;
      Slope2 := C011 - C001;
      Slope3 := C001 - C000;
    end;
    Output[Channel] := C000 + Slope1 * Rx + Slope2 * Ry + Slope3 * Rz;
  end;
end;

procedure TIccTransform.ConvertPixel(const Pixel: PByte; const Target: PByte);
begin
  var Device: array[0..MaxDeviceChannels - 1] of Single;
  var Rgb: array[0..2] of Single;

  for var Index := 0 to FComponents - 1 do
  begin
    Device[Index] := Pixel[Index] * ByteScale;
  end;
  ToRgb(@Device[0], @Rgb[0]);
  for var Index := 0 to 2 do
  begin
    Target[Index] := Byte(Trunc(Rgb[Index] * 255.0 + 0.5));
  end;
end;

procedure TIccTransform.CacheLookup(const Pixel: PByte; const Target: PByte);
begin
  var Key: Cardinal := 0;
  for var Index := 0 to FComponents - 1 do
  begin
    Key := (Key shl 8) or Pixel[Index];
  end;
  const Slot = Integer(((UInt64(Key) * UInt64(2654435761)) and $FFFFFFFF) shr 20) and (IccRowCacheSize - 1);

  const IsCached = (FCache[Slot].IsUsed and (FCache[Slot].Key = Key));
  if not IsCached then
  begin
    ConvertPixel(Pixel, Target);
    FCache[Slot].Key := Key;
    FCache[Slot].Red := Target[0];
    FCache[Slot].Green := Target[1];
    FCache[Slot].Blue := Target[2];
    FCache[Slot].IsUsed := True;
    Exit;
  end;

  Target[0] := FCache[Slot].Red;
  Target[1] := FCache[Slot].Green;
  Target[2] := FCache[Slot].Blue;
end;

procedure TIccTransform.ToRgbRow(const Input: PByte; const Output: PByte; const Count: Integer);
begin
  const IsCacheUsed = (FComponents <= MaxCachedComponents);
  if IsCacheUsed and (Length(FCache) = 0) then
  begin
    SetLength(FCache, IccRowCacheSize);
  end;

  for var Pixel := 0 to Count - 1 do
  begin
    if IsCacheUsed then
    begin
      CacheLookup(Input + Pixel * FComponents, Output + Pixel * 3);
    end
    else
    begin
      ConvertPixel(Input + Pixel * FComponents, Output + Pixel * 3);
    end;
  end;
end;

end.
