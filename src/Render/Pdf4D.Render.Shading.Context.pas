// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/shading/ShadingContext.java and ShadingPaint.java (3.0.8): the colour of
// every pixel of an area, which the Java2D paint context makes tile by tile
unit Pdf4D.Render.Shading.Context;

{$EXCESSPRECISION OFF}
{$POINTERMATH ON}

interface

uses
  System.Types,
  Pdf4D.Common.Matrix,
  Pdf4D.Graphics.Shading,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Renderer.Interfaces;

type
  // The work that all shadings of one page may do together. Every shading is built again for every paint that uses it, so a small
  // shading that many fills use costs as much as the fills together; the budget bounds that. Not thread safe, like a context.
  TPdfShadingBudget = class
  private
    FRemaining: Int64;
    FIsExhausted: Boolean;
    FIsReported: Boolean;

  public
    constructor Create(const Limit: Int64);

    // False, and the budget is exhausted, when Units is more than what is left
    function TryCharge(const Units: Int64): Boolean;
    // Gives the warning about the exhausted budget, the first time only
    procedure Report(const Shading: TPDShading);

    property IsExhausted: Boolean read FIsExhausted;
  end;

  // The inverse of the matrix from shading space to device pixels, which a context needs to find the point of the shading that lies
  // under a pixel (the rat of PDFBox). A matrix that cannot be inverted has no point to give.
  TPdfShadingMapper = record
  private
    FA: Double;
    FB: Double;
    FC: Double;
    FD: Double;
    FE: Double;
    FF: Double;
    FDeterminant: Double;
    FIsValid: Boolean;

  public
    class function Create(const ShadingToDevice: TPdfMatrix): TPdfShadingMapper; static;

    function IsValid: Boolean;
    // The point of the shading under the top left corner of the pixel (X, Y), as Single like the float array of PDFBox
    procedure Map(const X, Y: Integer; out U, V: Single);
  end;

  // One shading, one device area: gives the colour of the pixels. A context is not thread safe.
  TPdfShadingContext = class abstract
  private
    FShading: TPDShading;
    FMapper: TPdfShadingMapper;
    FBackground: TArray<Single>;
    FHasBackground: Boolean;
    FRgbBackground: Integer;

  protected
    constructor Initialize(const Shading: TPDShading; const ShadingToDevice: TPdfMatrix);

    // The colour of the point (U, V) of the shading; False leaves the pixel transparent
    function TryGetColorAt(const U, V: Single; out Rgb: Integer): Boolean; virtual; abstract;
    // ShadingContext.convertToRGB: the colour in the colour space of the shading as red, green and blue in the bytes 0, 1 and 2 of an
    // Integer, each cut off (not rounded) from 255 times the component
    function ConvertToRgb(const Values: TArray<Single>): Integer;

    property Shading: TPDShading read FShading;
    property HasBackground: Boolean read FHasBackground;
    // The /Background in the same form as ConvertToRgb gives
    property RgbBackground: Integer read FRgbBackground;

  public
    // False when the pixel is not painted; Rgb as ConvertToRgb says
    function TryGetPixel(const X, Y: Integer; out Rgb: Integer): Boolean; virtual;
  end;

  TPdfShadingRasterizer = class
  private
    class function CreateContext(const Shading: TPDShading; const ShadingToDevice: TPdfMatrix; const DeviceArea: TRect;
                                 const Cancel: IPdfCancelToken; const Budget: TPdfShadingBudget): TPdfShadingContext; static;
    class function CreateMeshContext(const Shading: TPDShadingMesh; const ShadingToDevice: TPdfMatrix; const DeviceArea: TRect;
                                     const Cancel: IPdfCancelToken; const Budget: TPdfShadingBudget): TPdfShadingContext; static;
    // A shading costs its pixels, and a mesh shading also a fixed amount for reading its data (FixedWork); False when the budget cannot
    // pay that
    class function TryPayForArea(const Shading: TPDShading; const DeviceArea: TRect; const Budget: TPdfShadingBudget;
                                 const FixedWork: Int64): Boolean; static;
    class procedure PaintRows(const Context: TPdfShadingContext; const DeviceArea: TRect; const Cancel: IPdfCancelToken; const Bitmap: TPdfBitmap); static;

  public
    // Paints the shading into a bitmap that covers DeviceArea (device pixels), opaque where the shading has a colour and transparent
    // elsewhere. ShadingToDevice is the CTM (or the pattern matrix after the initial matrix) with the transform of the page. The cancel
    // token is asked before every row; a cancelled run gives the rows it has made. A mesh shading (the types 4 to 7) paints its triangles and
    // patches; one without usable data gives a transparent bitmap. Raises EArgumentOutOfRangeException when DeviceArea is empty or too large for a bitmap. Cancel may be nil. The caller owns
    // the result. The budget (may be nil: no page limit) is shared by the shadings of one page; one that cannot be paid for, or that
    // spends the rest, is skipped with a warning.
    class function Rasterize(const Shading: TPDShading; const ShadingToDevice: TPdfMatrix; const DeviceArea: TRect;
                             const Cancel: IPdfCancelToken; const Budget: TPdfShadingBudget = nil): TPdfBitmap; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Pdf4D.Render.Shading.Axial,
  Pdf4D.Render.Shading.&Function,
  Pdf4D.Render.Shading.Patch,
  Pdf4D.Render.Shading.Radial,
  Pdf4D.Render.Shading.Triangle;

const
  ByteScale = 255;
  GreenShift = 8;
  BlueShift = 16;
  ChannelMask = 255;
  OpaqueAlpha = 255;
  BytesPerPixel = 4;
  // What reading the data of a mesh shading costs besides its pixels: the decoding of a compressed stream is the same for every paint
  MeshReadWork = 4096;
  BudgetWarning = 'The shadings of the page exceed the work limit of the page; the rest of them are skipped';

{ TPdfShadingBudget }

constructor TPdfShadingBudget.Create(const Limit: Int64);
begin
  inherited Create;
  FRemaining := Max(Limit, 0);
end;

function TPdfShadingBudget.TryCharge(const Units: Int64): Boolean;
begin
  if FIsExhausted then
  begin
    Exit(False);
  end;

  if Units > FRemaining then
  begin
    FRemaining := 0;
    FIsExhausted := True;
    Exit(False);
  end;

  Dec(FRemaining, Units);
  Result := True;
end;

procedure TPdfShadingBudget.Report(const Shading: TPDShading);
begin
  if not FIsReported then
  begin
    FIsReported := True;
    Shading.Warn(BudgetWarning, []);
  end;
end;

{ TPdfShadingMapper }

class function TPdfShadingMapper.Create(const ShadingToDevice: TPdfMatrix): TPdfShadingMapper;
begin
  Result.FA := ShadingToDevice.ScaleX;
  Result.FB := ShadingToDevice.ShearY;
  Result.FC := ShadingToDevice.ShearX;
  Result.FD := ShadingToDevice.ScaleY;
  Result.FE := ShadingToDevice.TranslateX;
  Result.FF := ShadingToDevice.TranslateY;
  Result.FDeterminant := Result.FA * Result.FD - Result.FB * Result.FC;
  Result.FIsValid := ((Result.FDeterminant <> 0) and (not IsNan(Result.FDeterminant)) and (not IsInfinite(Result.FDeterminant)));
end;

function TPdfShadingMapper.IsValid: Boolean;
begin
  Result := FIsValid;
end;

// The offset from the translation is taken first, so that a pixel that lies exactly on the image of a point gives that point
procedure TPdfShadingMapper.Map(const X, Y: Integer; out U, V: Single);
begin
  const OffsetX = X - FE;
  const OffsetY = Y - FF;
  U := (FD * OffsetX - FC * OffsetY) / FDeterminant;
  V := (FA * OffsetY - FB * OffsetX) / FDeterminant;
end;

{ TPdfShadingContext }

constructor TPdfShadingContext.Initialize(const Shading: TPDShading; const ShadingToDevice: TPdfMatrix);
begin
  inherited Create;
  FShading := Shading;
  FMapper := TPdfShadingMapper.Create(ShadingToDevice);
  FHasBackground := Shading.TryGetBackground(FBackground);
  if FHasBackground then
  begin
    FRgbBackground := ConvertToRgb(FBackground);
  end;
end;

function TPdfShadingContext.ConvertToRgb(const Values: TArray<Single>): Integer;
begin
  const Rgb = FShading.ColorSpace.ToRgb(Values);
  const Red = Trunc(Min(Max(Rgb.R, 0), 1) * ByteScale);
  const Green = Trunc(Min(Max(Rgb.G, 0), 1) * ByteScale);
  const Blue = Trunc(Min(Max(Rgb.B, 0), 1) * ByteScale);
  Result := (Red or (Green shl GreenShift) or (Blue shl BlueShift));
end;

function TPdfShadingContext.TryGetPixel(const X, Y: Integer; out Rgb: Integer): Boolean;
begin
  Rgb := 0;
  if not FMapper.IsValid then
  begin
    Exit(False);
  end;

  var U, V: Single;
  FMapper.Map(X, Y, U, V);
  Result := TryGetColorAt(U, V, Rgb);
end;

{ TPdfShadingRasterizer }

class function TPdfShadingRasterizer.Rasterize(const Shading: TPDShading; const ShadingToDevice: TPdfMatrix; const DeviceArea: TRect;
                                               const Cancel: IPdfCancelToken; const Budget: TPdfShadingBudget): TPdfBitmap;
begin
  Result := TPdfBitmap.Create(DeviceArea.Width, DeviceArea.Height);
  try
    const Context = CreateContext(Shading, ShadingToDevice, DeviceArea, Cancel, Budget);
    if Assigned(Context) then
    begin
      try
        PaintRows(Context, DeviceArea, Cancel, Result);
      finally
        Context.Free;
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

class function TPdfShadingRasterizer.CreateContext(const Shading: TPDShading; const ShadingToDevice: TPdfMatrix; const DeviceArea: TRect;
                                                   const Cancel: IPdfCancelToken; const Budget: TPdfShadingBudget): TPdfShadingContext;
begin
  Result := nil;
  if Shading is TPDShadingType1 then
  begin
    if TryPayForArea(Shading, DeviceArea, Budget, 0) then
    begin
      Result := TPdfFunctionShadingContext.Create(TPDShadingType1(Shading), ShadingToDevice);
    end;
  end
  else if Shading is TPDShadingType2 then
  begin
    if TryPayForArea(Shading, DeviceArea, Budget, 0) then
    begin
      Result := TPdfAxialShadingContext.Create(TPDShadingType2(Shading), ShadingToDevice, DeviceArea);
    end;
  end
  else if Shading is TPDShadingType3 then
  begin
    if TryPayForArea(Shading, DeviceArea, Budget, 0) then
    begin
      Result := TPdfRadialShadingContext.Create(TPDShadingType3(Shading), ShadingToDevice, DeviceArea);
    end;
  end
  else if Shading is TPDShadingMesh then
  begin
    if TryPayForArea(Shading, DeviceArea, Budget, MeshReadWork) then
    begin
      Result := CreateMeshContext(TPDShadingMesh(Shading), ShadingToDevice, DeviceArea, Cancel, Budget);
    end;
  end;
end;

class function TPdfShadingRasterizer.TryPayForArea(const Shading: TPDShading; const DeviceArea: TRect; const Budget: TPdfShadingBudget;
                                                   const FixedWork: Int64): Boolean;
begin
  Result := True;
  if Assigned(Budget) and (not Budget.TryCharge(Int64(DeviceArea.Width) * DeviceArea.Height + FixedWork)) then
  begin
    Budget.Report(Shading);
    Result := False;
  end;
end;

class function TPdfShadingRasterizer.CreateMeshContext(const Shading: TPDShadingMesh; const ShadingToDevice: TPdfMatrix; const DeviceArea: TRect;
                                                       const Cancel: IPdfCancelToken; const Budget: TPdfShadingBudget): TPdfShadingContext;
begin
  case Shading.ShadingType of
    4 : Result := TPdfType4ShadingContext.Create(Shading, ShadingToDevice, DeviceArea, Cancel, Budget);
    5 : Result := TPdfType5ShadingContext.Create(Shading, ShadingToDevice, DeviceArea, Cancel, Budget);
    6 : Result := TPdfType6ShadingContext.Create(Shading, ShadingToDevice, DeviceArea, Cancel, Budget);
    7 : Result := TPdfType7ShadingContext.Create(Shading, ShadingToDevice, DeviceArea, Cancel, Budget);
  else
    raise EArgumentOutOfRangeException.CreateFmt('A mesh shading is of the type 4 to 7, not %d', [Shading.ShadingType]);
  end;
end;

class procedure TPdfShadingRasterizer.PaintRows(const Context: TPdfShadingContext; const DeviceArea: TRect; const Cancel: IPdfCancelToken;
                                                const Bitmap: TPdfBitmap);
begin
  for var Row := 0 to Bitmap.Height - 1 do
  begin
    if Assigned(Cancel) and Cancel.IsCancelled then
    begin
      Exit;
    end;

    const Line = Bitmap.ScanLine(Row);
    for var Column := 0 to Bitmap.Width - 1 do
    begin
      var Rgb: Integer;
      if Context.TryGetPixel(DeviceArea.Left + Column, DeviceArea.Top + Row, Rgb) then
      begin
        const Pixel = Line + Column * BytesPerPixel;
        Pixel[0] := (Rgb and ChannelMask);
        Pixel[1] := ((Rgb shr GreenShift) and ChannelMask);
        Pixel[2] := ((Rgb shr BlueShift) and ChannelMask);
        Pixel[3] := OpaqueAlpha;
      end;
    end;
  end;
end;

end.
