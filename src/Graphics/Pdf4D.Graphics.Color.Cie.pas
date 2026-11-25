// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/color/PDCIEBasedColorSpace.java, PDCIEDictionaryBasedColorSpace.java,
// PDCalGray.java, PDCalRGB.java, PDLab.java, PDTristimulus.java and PDGamma.java (3.0.8). PDFBox lets java.awt.color.ColorSpace.CS_CIEXYZ
// turn XYZ into sRGB; Pdf4D does that with the matrix and the curve of the sRGB profile that Java carries (see Pdf4D.Graphics.Icc.Transform),
// after the 16-bit quantisation of the XYZ values that ICC_ColorSpace.toRGB applies.
unit Pdf4D.Graphics.Color.Cie;

{$EXCESSPRECISION OFF}
{$POINTERMATH ON}

interface

uses
  System.SysUtils,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Graphics.Color,
  Pdf4D.Render.Bitmap;

type
  // PDTristimulus: the X, Y and Z of a white or black point
  TPDTristimulus = record
    X: Single;
    Y: Single;
    Z: Single;

    class function Create(const X, Y, Z: Single): TPDTristimulus; static;
  end;

  // PDGamma: the exponents of the red, green and blue channel
  TPDGamma = record
    R: Single;
    G: Single;
    B: Single;

    class function Create(const R, G, B: Single): TPDGamma; static;
  end;

  // PDRange: the lowest and the highest value of a component
  TPDRange = record
    Minimum: Single;
    Maximum: Single;

    class function Create(const Minimum, Maximum: Single): TPDRange; static;
  end;

  // The last colours of an image row, which the conversion of the next pixels often asks for again. A pixel of up to 3 samples is a key.
  TCieColorCache = record
  private
    const Size = 4096;
    const Unused = -1;

  private
    Keys: array[0..Size - 1] of Integer;
    Values: array[0..Size - 1] of Cardinal;

    class function SlotOf(const Key: Integer): Integer; static;

  public
    procedure Clear;
    function TryGet(const Key: Integer; out Value: Cardinal): Boolean;
    procedure Add(const Key: Integer; const Value: Cardinal);
  end;
  PCieColorCache = ^TCieColorCache;

  // PDCIEBasedColorSpace: a colour space that goes through CIE XYZ. The image is converted pixel by pixel through ToRgb.
  TPDCIEBasedColorSpace = class abstract(TPDColorSpace)
  private
    procedure ConvertPixel(const Source: PByte; const Components: TArray<Single>; const Target: PByte);

  protected
    // The component that a sample of 0..1 stands for: the sample itself for the spaces that have no ranges
    function ComponentOfSample(const Component: Integer; const Fraction: Single): Single; virtual;

  public
    function ToRgbImage(const Raster: TPdfRaster): TPdfBitmap; override;
  end;

  // PDCIEDictionaryBasedColorSpace: the array [/Kind dictionary] with the white and the black point
  TPDCIEDictionaryBasedColorSpace = class abstract(TPDCIEBasedColorSpace)
  private
    FWhitePoint: TPDTristimulus;
    FBlackPoint: TPDTristimulus;

    class function ReadTristimulus(const Dictionary: TCosDictionary; const Key: string; const Default: TPDTristimulus): TPDTristimulus; static;
    // The 16-bit value that ICC_ColorSpace.toRGB makes of an XYZ component and the XYZ that the colour management reads from it
    class function QuantizedXyz(const Value: Single): Double; static;

  protected
    // Items is the colour space array; raises EPdfParseException when its second element is no dictionary or a point has fewer than 3 numbers
    constructor Create(const Items: TCosArray);

    // The dictionary of the array, for the entries of the descendants
    class function DictionaryOf(const Items: TCosArray): TCosDictionary; static;
    class function ReadNumbers(const Dictionary: TCosDictionary; const Key: string; const Count: Integer; out Values: TArray<Single>): Boolean; static;
    // Tests if the white point is 1 1 1, which PDFBox takes for "the white point" (the other white points skip the calibration)
    function IsWhitePoint: Boolean;
    class function JavaPower(const Base, Exponent: Single): Single; static;
    // convXYZtoRGB: negative values are 0
    class function ConvertXyzToRgb(const X, Y, Z: Single): TPdfRgb; static;

  public
    property WhitePoint: TPDTristimulus read FWhitePoint;
    property BlackPoint: TPDTristimulus read FBlackPoint;
  end;

  // PDCalGray
  TPDCalGray = class(TPDCIEDictionaryBasedColorSpace)
  private
    FGamma: Single;

  public
    constructor Create(const Items: TCosArray);

    function Name: string; override;
    function NumberOfComponents: Integer; override;
    function InitialColor: TPDColor; override;
    function ToRgb(const Components: TArray<Single>): TPdfRgb; override;

    property Gamma: Single read FGamma;
  end;

  // PDCalRGB
  TPDCalRGB = class(TPDCIEDictionaryBasedColorSpace)
  private
    FGamma: TPDGamma;
    FMatrix: TArray<Single>;

  public
    constructor Create(const Items: TCosArray);

    function Name: string; override;
    function NumberOfComponents: Integer; override;
    function InitialColor: TPDColor; override;
    function ToRgb(const Components: TArray<Single>): TPdfRgb; override;

    property Gamma: TPDGamma read FGamma;
    // The 9 values XA YA ZA XB YB ZB XC YC ZC
    property Matrix: TArray<Single> read FMatrix;
  end;

  // PDLab
  TPDLab = class(TPDCIEDictionaryBasedColorSpace)
  private
    FARange: TPDRange;
    FBRange: TPDRange;

    class function Inverse(const Value: Single): Single; static;

  protected
    function ComponentOfSample(const Component: Integer; const Fraction: Single): Single; override;

  public
    constructor Create(const Items: TCosArray);

    function Name: string; override;
    function NumberOfComponents: Integer; override;
    function GetDefaultDecode(const BitsPerComponent: Integer): TArray<Single>; override;
    function InitialColor: TPDColor; override;
    function ToRgb(const Components: TArray<Single>): TPdfRgb; override;

    property ARange: TPDRange read FARange;
    property BRange: TPDRange read FBRange;
  end;

implementation

uses
  System.Math,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Names,
  Pdf4D.Graphics.Icc.Profile,
  Pdf4D.Graphics.Icc.Transform;

resourcestring
  CieNeedsDictionary = 'A CIE based colour space array must have a dictionary as second element';
  CieTooFewNumbers = 'The /%s entry of a CIE based colour space needs %d numbers, it has %d';

const
  MaxXyzEncoding = 65535;
  // 1 + 32767/32768, the largest XYZ value of the 16-bit encoding of java.awt.color.ColorSpace.CS_CIEXYZ: 32768 steps for 1.0
  XyzSteps = 32768.0;
  DefaultWhite = 1.0;
  DefaultGamma = 1.0;
  LabLightnessScale = 100.0;
  LabLowerRange = -100.0;
  LabUpperRange = 100.0;
  LabInverseThreshold = 6.0 / 29.0;
  MatrixCount = 9;
  TristimulusCount = 3;
  RangeCount = 4;
  PixelKeyBytes = 3;

{ TPDTristimulus }

class function TPDTristimulus.Create(const X, Y, Z: Single): TPDTristimulus;
begin
  Result.X := X;
  Result.Y := Y;
  Result.Z := Z;
end;

{ TPDGamma }

class function TPDGamma.Create(const R, G, B: Single): TPDGamma;
begin
  Result.R := R;
  Result.G := G;
  Result.B := B;
end;

{ TPDRange }

class function TPDRange.Create(const Minimum, Maximum: Single): TPDRange;
begin
  Result.Minimum := Minimum;
  Result.Maximum := Maximum;
end;

{ TCieColorCache }

class function TCieColorCache.SlotOf(const Key: Integer): Integer;
begin
  Result := (Key xor (Key shr 12)) and (Size - 1);
end;

procedure TCieColorCache.Clear;
begin
  for var Slot := 0 to Size - 1 do
  begin
    Keys[Slot] := Unused;
  end;
end;

function TCieColorCache.TryGet(const Key: Integer; out Value: Cardinal): Boolean;
begin
  const Slot = SlotOf(Key);
  Result := (Keys[Slot] = Key);
  if Result then
  begin
    Value := Values[Slot];
  end
  else
  begin
    Value := 0;
  end;
end;

procedure TCieColorCache.Add(const Key: Integer; const Value: Cardinal);
begin
  const Slot = SlotOf(Key);
  Keys[Slot] := Key;
  Values[Slot] := Value;
end;

{ TPDCIEBasedColorSpace }

function TPDCIEBasedColorSpace.ComponentOfSample(const Component: Integer; const Fraction: Single): Single;
begin
  Result := Fraction;
end;

procedure TPDCIEBasedColorSpace.ConvertPixel(const Source: PByte; const Components: TArray<Single>; const Target: PByte);
begin
  for var Component := 0 to NumberOfComponents - 1 do
  begin
    const Fraction: Single = Single(Source[Component]) / Single(255);
    Components[Component] := ComponentOfSample(Component, Fraction);
  end;

  const Rgb = ToRgb(Components);
  Target[0] := TruncateChannelToByte(Rgb.R);
  Target[1] := TruncateChannelToByte(Rgb.G);
  Target[2] := TruncateChannelToByte(Rgb.B);
end;

function TPDCIEBasedColorSpace.ToRgbImage(const Raster: TPdfRaster): TPdfBitmap;
begin
  CheckRaster(Raster);
  const Count = NumberOfComponents;
  const IsKeyable = (Count <= PixelKeyBytes);

  var Cache: PCieColorCache;
  New(Cache);
  try
    Cache.Clear;
    Result := TPdfBitmap.Create(Raster.Width, Raster.Height);
    try
      var Components: TArray<Single>;
      SetLength(Components, Count);
      var Row: TBytes;
      SetLength(Row, Raster.Width * 3);
      for var Y := 0 to Raster.Height - 1 do
      begin
        const Source = Raster.RowStart(Y);
        for var X := 0 to Raster.Width - 1 do
        begin
          const Pixel = Source + X * Count;
          const Target: PByte = @Row[X * 3];
          var Key := 0;
          for var Component := 0 to Count - 1 do
          begin
            Key := Key or (Integer(Pixel[Component]) shl (Component * 8));
          end;

          var PackedColor: Cardinal;
          if IsKeyable and Cache.TryGet(Key, PackedColor) then
          begin
            Target[0] := Byte(PackedColor);
            Target[1] := Byte(PackedColor shr 8);
            Target[2] := Byte(PackedColor shr 16);
            Continue;
          end;

          ConvertPixel(Pixel, Components, Target);
          if IsKeyable then
          begin
            Cache.Add(Key, Cardinal(Target[0]) or (Cardinal(Target[1]) shl 8) or (Cardinal(Target[2]) shl 16));
          end;
        end;
        StoreRgbRow(Result, Y, @Row[0]);
      end;
    except
      Result.Free;
      raise;
    end;
  finally
    Dispose(Cache);
  end;
end;

{ TPDCIEDictionaryBasedColorSpace }

constructor TPDCIEDictionaryBasedColorSpace.Create(const Items: TCosArray);
begin
  inherited Create;
  const Dictionary = DictionaryOf(Items);
  FWhitePoint := ReadTristimulus(Dictionary, TCosNames.WhitePoint, TPDTristimulus.Create(DefaultWhite, DefaultWhite, DefaultWhite));
  FBlackPoint := ReadTristimulus(Dictionary, TCosNames.BlackPoint, TPDTristimulus.Create(0, 0, 0));
end;

class function TPDCIEDictionaryBasedColorSpace.DictionaryOf(const Items: TCosArray): TCosDictionary;
begin
  const HasDictionary = ((Items.Count >= 2) and (Items.GetObject(1) is TCosDictionary));
  if not HasDictionary then
  begin
    raise EPdfParseException.Create(CieNeedsDictionary);
  end;

  Result := TCosDictionary(Items.GetObject(1));
end;

// A missing entry or one that is no array is absent; an array with too few numbers fails (PDFBox reads past its end)
class function TPDCIEDictionaryBasedColorSpace.ReadNumbers(const Dictionary: TCosDictionary; const Key: string; const Count: Integer;
                                                           out Values: TArray<Single>): Boolean;
begin
  Values := nil;
  var Items: TCosArray;
  Result := Dictionary.TryGetCosArray(Key, Items);
  if not Result then
  begin
    Exit;
  end;

  if Items.Count < Count then
  begin
    raise EPdfParseException.CreateFmt(CieTooFewNumbers, [Key, Count, Items.Count]);
  end;

  Values := Items.ToFloatArray;
end;

class function TPDCIEDictionaryBasedColorSpace.ReadTristimulus(const Dictionary: TCosDictionary; const Key: string;
                                                               const Default: TPDTristimulus): TPDTristimulus;
begin
  var Values: TArray<Single>;
  if ReadNumbers(Dictionary, Key, TristimulusCount, Values) then
  begin
    Result := TPDTristimulus.Create(Values[0], Values[1], Values[2]);
  end
  else
  begin
    Result := Default;
  end;
end;

function TPDCIEDictionaryBasedColorSpace.IsWhitePoint: Boolean;
begin
  Result := ((FWhitePoint.X = DefaultWhite) and (FWhitePoint.Y = DefaultWhite) and (FWhitePoint.Z = DefaultWhite));
end;

// (short) of the float, so that a value that is too large wraps
class function TPDCIEDictionaryBasedColorSpace.QuantizedXyz(const Value: Single): Double;
begin
  // convXYZtoRGB sets a negative value to 0; a value that is not a number ends as 0 in the colour management
  const IsNegativeOrNan = (IsNan(Value) or (Value < 0.0));
  if IsNegativeOrNan then
  begin
    Exit(0.0);
  end;

  const Scaled = Value * Single(XyzSteps) + Single(0.5);

  if Scaled >= 2147483647.0 then
  begin
    Exit(MaxXyzEncoding / XyzSteps);
  end;

  Result := (Trunc(Scaled) and MaxXyzEncoding) / XyzSteps;
end;

class function TPDCIEDictionaryBasedColorSpace.ConvertXyzToRgb(const X, Y, Z: Single): TPdfRgb;
begin
  var Xyz: array[0..2] of Double;
  Xyz[0] := QuantizedXyz(X);
  Xyz[1] := QuantizedXyz(Y);
  Xyz[2] := QuantizedXyz(Z);

  var Output: array[0..2] of Single;
  TIccTransform.XyzToSrgb(@Xyz[0], @Output[0]);
  Result := TPdfRgb.Create(Output[0], Output[1], Output[2]);
end;

// Math.pow of Java for a float base: not a number for a negative base with a fraction as exponent
class function TPDCIEDictionaryBasedColorSpace.JavaPower(const Base, Exponent: Single): Single;
begin
  if IsNan(Base) or IsNan(Exponent) then
  begin
    Exit(NaN);
  end;

  if Exponent = 0.0 then
  begin
    Exit(1.0);
  end;

  if Base = 0.0 then
  begin
    if Exponent > 0.0 then
    begin
      Exit(0.0);
    end;
    Exit(Infinity);
  end;

  if Base > 0.0 then
  begin
    Exit(TIccCurve.SafePower(Base, Exponent));
  end;

  const IsWhole = (Abs(Exponent) < 9007199254740992.0) and (Exponent = Round(Exponent));
  if not IsWhole then
  begin
    Exit(NaN);
  end;

  const Magnitude = TIccCurve.SafePower(-Base, Exponent);
  if Odd(Round(Exponent)) then
  begin
    Exit(-Magnitude);
  end;
  Result := Magnitude;
end;

{ TPDCalGray }

constructor TPDCalGray.Create(const Items: TCosArray);
begin
  inherited Create(Items);
  FGamma := DictionaryOf(Items).GetFloat(TCosNames.Gamma, DefaultGamma);
end;

function TPDCalGray.Name: string;
begin
  Result := TCosNames.CalGray;
end;

function TPDCalGray.NumberOfComponents: Integer;
begin
  Result := 1;
end;

function TPDCalGray.InitialColor: TPDColor;
begin
  Result := TPDColor.Create(Self, [0.0]);
end;

// PDFBOX-4119 caches the results; the conversion is the same without
function TPDCalGray.ToRgb(const Components: TArray<Single>): TPdfRgb;
begin
  const Value = NormalizeComponents(Components)[0];
  if not IsWhitePoint then
  begin
    Exit(TPdfRgb.Create(Value, Value, Value));
  end;

  const PowAG = JavaPower(Value, FGamma);
  Result := ConvertXyzToRgb(PowAG, PowAG, PowAG);
end;

{ TPDCalRGB }

constructor TPDCalRGB.Create(const Items: TCosArray);
begin
  inherited Create(Items);
  const Dictionary = DictionaryOf(Items);

  var Gammas: TArray<Single>;
  if ReadNumbers(Dictionary, TCosNames.Gamma, TristimulusCount, Gammas) then
  begin
    FGamma := TPDGamma.Create(Gammas[0], Gammas[1], Gammas[2]);
  end
  else
  begin
    FGamma := TPDGamma.Create(DefaultGamma, DefaultGamma, DefaultGamma);
  end;

  if not ReadNumbers(Dictionary, TCosNames.Matrix, MatrixCount, FMatrix) then
  begin
    FMatrix := [1, 0, 0, 0, 1, 0, 0, 0, 1];
  end;
end;

function TPDCalRGB.Name: string;
begin
  Result := TCosNames.CalRGB;
end;

function TPDCalRGB.NumberOfComponents: Integer;
begin
  Result := 3;
end;

function TPDCalRGB.InitialColor: TPDColor;
begin
  Result := TPDColor.Create(Self, [0.0, 0.0, 0.0]);
end;

function TPDCalRGB.ToRgb(const Components: TArray<Single>): TPdfRgb;
begin
  const Values = NormalizeComponents(Components);
  if not IsWhitePoint then
  begin
    // PDFBOX-2553: the calibration is skipped, which works for the white point D65 only
    Exit(TPdfRgb.Create(Values[0], Values[1], Values[2]));
  end;

  const PowAR = JavaPower(Values[0], FGamma.R);
  const PowBG = JavaPower(Values[1], FGamma.G);
  const PowCB = JavaPower(Values[2], FGamma.B);
  const X = FMatrix[0] * PowAR + FMatrix[3] * PowBG + FMatrix[6] * PowCB;
  const Y = FMatrix[1] * PowAR + FMatrix[4] * PowBG + FMatrix[7] * PowCB;
  const Z = FMatrix[2] * PowAR + FMatrix[5] * PowBG + FMatrix[8] * PowCB;
  Result := ConvertXyzToRgb(X, Y, Z);
end;

{ TPDLab }

constructor TPDLab.Create(const Items: TCosArray);
begin
  inherited Create(Items);

  var Values: TArray<Single>;
  if ReadNumbers(DictionaryOf(Items), TCosNames.Range, RangeCount, Values) then
  begin
    FARange := TPDRange.Create(Values[0], Values[1]);
    FBRange := TPDRange.Create(Values[2], Values[3]);
  end
  else
  begin
    FARange := TPDRange.Create(LabLowerRange, LabUpperRange);
    FBRange := TPDRange.Create(LabLowerRange, LabUpperRange);
  end;
end;

function TPDLab.Name: string;
begin
  Result := TCosNames.Lab;
end;

function TPDLab.NumberOfComponents: Integer;
begin
  Result := 3;
end;

function TPDLab.GetDefaultDecode(const BitsPerComponent: Integer): TArray<Single>;
begin
  Result := [0, LabLightnessScale, FARange.Minimum, FARange.Maximum, FBRange.Minimum, FBRange.Maximum];
end;

function TPDLab.InitialColor: TPDColor;
begin
  Result := TPDColor.Create(Self, [0.0, Max(0.0, FARange.Minimum), Max(0.0, FBRange.Minimum)]);
end;

// The scaling of the samples of toRGBImage: L* to 0..100, a* and b* to their ranges
function TPDLab.ComponentOfSample(const Component: Integer; const Fraction: Single): Single;
begin
  case Component of
    0 : Result := Fraction * Single(LabLightnessScale);
    1 : Result := FARange.Minimum + Fraction * (FARange.Maximum - FARange.Minimum);
  else
    Result := FBRange.Minimum + Fraction * (FBRange.Maximum - FBRange.Minimum);
  end;
end;

// The reverse transformation f^-1
class function TPDLab.Inverse(const Value: Single): Single;
begin
  if Value > LabInverseThreshold then
  begin
    Result := Value * Value * Value;
  end
  else
  begin
    Result := (108.0 / 841.0) * (Value - (4.0 / 29.0));
  end;
end;

// CIE L*a*b* to RGB; the black point is not used, as in PDFBox
function TPDLab.ToRgb(const Components: TArray<Single>): TPdfRgb;
begin
  const Values = NormalizeComponents(Components);
  const LStar: Single = (Values[0] + 16.0) * (1.0 / 116.0);
  const X = FWhitePoint.X * Inverse(LStar + Values[1] * (1.0 / 500.0));
  const Y = FWhitePoint.Y * Inverse(LStar);
  const Z = FWhitePoint.Z * Inverse(LStar - Values[2] * (1.0 / 200.0));
  Result := ConvertXyzToRgb(X, Y, Z);
end;

end.
