// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/color/PDDeviceGray.java, PDDeviceRGB.java and PDDeviceCMYK.java
// (3.0.8). DeviceCMYK converts with the profile CGATS001Compat-v2-micro that PDFBox loads, through Pdf4D.Graphics.Icc.Transform.
unit Pdf4D.Graphics.Color.Device;

{$EXCESSPRECISION OFF}
{$POINTERMATH ON}

interface

uses
  System.SysUtils,
  Pdf4D.Common.SharedInstance,
  Pdf4D.Graphics.Color,
  Pdf4D.Graphics.Icc.Profile,
  Pdf4D.Graphics.Icc.Transform,
  Pdf4D.Render.Bitmap;

type
  // The device spaces are made once for the process and shared by all documents and threads: they hold no state that changes.
  TPDDeviceGray = class(TPDColorSpace)
  private
    class var FInstance: TPdfSharedInstance<TPDDeviceGray>;

    class destructor Destroy;

  public
    class function Instance: TPDDeviceGray; static;

    function Name: string; override;
    function NumberOfComponents: Integer; override;
    function InitialColor: TPDColor; override;
    function ToRgb(const Components: TArray<Single>): TPdfRgb; override;
    function ToRgbImage(const Raster: TPdfRaster): TPdfBitmap; override;
  end;

  TPDDeviceRGB = class(TPDColorSpace)
  private
    class var FInstance: TPdfSharedInstance<TPDDeviceRGB>;

    class destructor Destroy;

  public
    class function Instance: TPDDeviceRGB; static;

    function Name: string; override;
    function NumberOfComponents: Integer; override;
    function InitialColor: TPDColor; override;
    // PDFBox gives the components back as they are and clamps later (PageDrawer.clampColor); every user clamps, so this clamps
    function ToRgb(const Components: TArray<Single>): TPdfRgb; override;
    function ToRgbImage(const Raster: TPdfRaster): TPdfBitmap; override;
  end;

  TPDDeviceCMYK = class(TPDColorSpace)
  private
    class var FInstance: TPdfSharedInstance<TPDDeviceCMYK>;

    FProfile: TIccProfile;
    // Only ToRgb of the transform is used on this one, which keeps no state; an image makes a transform of its own
    FTransform: TIccTransform;

    class destructor Destroy;

    class function CreateInstance: TPDDeviceCMYK; static;

    constructor Create;

  public
    destructor Destroy; override;

    class function Instance: TPDDeviceCMYK; static;

    function Name: string; override;
    function NumberOfComponents: Integer; override;
    function InitialColor: TPDColor; override;
    function ToRgb(const Components: TArray<Single>): TPdfRgb; override;
    function ToRgbImage(const Raster: TPdfRaster): TPdfBitmap; override;
  end;

implementation

uses
  Pdf4D.Cos.Names,
  Pdf4D.Resources.Icc;

const
  GrayComponents = 1;
  RgbComponents = 3;
  CmykComponents = 4;

{ TPDDeviceGray }

class destructor TPDDeviceGray.Destroy;
begin
  FInstance.Release;
end;

class function TPDDeviceGray.Instance: TPDDeviceGray;
begin
  Result := FInstance.Get(
    function: TPDDeviceGray
    begin
      Result := TPDDeviceGray.Create;
    end);
end;

function TPDDeviceGray.Name: string;
begin
  Result := TCosNames.DeviceGray;
end;

function TPDDeviceGray.NumberOfComponents: Integer;
begin
  Result := GrayComponents;
end;

function TPDDeviceGray.InitialColor: TPDColor;
begin
  Result := TPDColor.Create(Self, [0.0]);
end;

function TPDDeviceGray.ToRgb(const Components: TArray<Single>): TPdfRgb;
begin
  const Gray = ClampColor(NormalizeComponents(Components)[0]);
  Result := TPdfRgb.Create(Gray, Gray, Gray);
end;

function TPDDeviceGray.ToRgbImage(const Raster: TPdfRaster): TPdfBitmap;
begin
  CheckRaster(Raster);
  Result := TPdfBitmap.Create(Raster.Width, Raster.Height);
  try
    for var Y := 0 to Raster.Height - 1 do
    begin
      const Source = Raster.RowStart(Y);
      const Target = Result.ScanLine(Y);
      for var X := 0 to Raster.Width - 1 do
      begin
        Target[X * 4] := Source[X];
        Target[X * 4 + 1] := Source[X];
        Target[X * 4 + 2] := Source[X];
        Target[X * 4 + 3] := 255;
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

{ TPDDeviceRGB }

class destructor TPDDeviceRGB.Destroy;
begin
  FInstance.Release;
end;

class function TPDDeviceRGB.Instance: TPDDeviceRGB;
begin
  Result := FInstance.Get(
    function: TPDDeviceRGB
    begin
      Result := TPDDeviceRGB.Create;
    end);
end;

function TPDDeviceRGB.Name: string;
begin
  Result := TCosNames.DeviceRGB;
end;

function TPDDeviceRGB.NumberOfComponents: Integer;
begin
  Result := RgbComponents;
end;

function TPDDeviceRGB.InitialColor: TPDColor;
begin
  Result := TPDColor.Create(Self, [0.0, 0.0, 0.0]);
end;

function TPDDeviceRGB.ToRgb(const Components: TArray<Single>): TPdfRgb;
begin
  const Values = NormalizeComponents(Components);
  Result := TPdfRgb.Create(ClampColor(Values[0]), ClampColor(Values[1]), ClampColor(Values[2]));
end;

function TPDDeviceRGB.ToRgbImage(const Raster: TPdfRaster): TPdfBitmap;
begin
  CheckRaster(Raster);
  Result := TPdfBitmap.Create(Raster.Width, Raster.Height);
  try
    for var Y := 0 to Raster.Height - 1 do
    begin
      StoreRgbRow(Result, Y, Raster.RowStart(Y));
    end;
  except
    Result.Free;
    raise;
  end;
end;

{ TPDDeviceCMYK }

class destructor TPDDeviceCMYK.Destroy;
begin
  FInstance.Release;
end;

class function TPDDeviceCMYK.CreateInstance: TPDDeviceCMYK;
begin
  Result := TPDDeviceCMYK.Create;
end;

constructor TPDDeviceCMYK.Create;
begin
  inherited Create;
  FProfile := TIccProfile.Parse(TPdfIccResources.CmykProfile);
  FTransform := TIccTransform.Create(FProfile);
end;

destructor TPDDeviceCMYK.Destroy;
begin
  FTransform.Free;
  FProfile.Free;
  inherited;
end;

class function TPDDeviceCMYK.Instance: TPDDeviceCMYK;
begin
  Result := FInstance.Get(
    function: TPDDeviceCMYK
    begin
      Result := CreateInstance;
    end);
end;

function TPDDeviceCMYK.Name: string;
begin
  Result := TCosNames.DeviceCMYK;
end;

function TPDDeviceCMYK.NumberOfComponents: Integer;
begin
  Result := CmykComponents;
end;

function TPDDeviceCMYK.InitialColor: TPDColor;
begin
  Result := TPDColor.Create(Self, [0.0, 0.0, 0.0, 1.0]);
end;

function TPDDeviceCMYK.ToRgb(const Components: TArray<Single>): TPdfRgb;
begin
  const Values = NormalizeComponents(Components);
  var Rgb: array[0..2] of Single;
  FTransform.ToRgb(@Values[0], @Rgb[0]);
  Result := TPdfRgb.Create(Rgb[0], Rgb[1], Rgb[2]);
end;

function TPDDeviceCMYK.ToRgbImage(const Raster: TPdfRaster): TPdfBitmap;
begin
  CheckRaster(Raster);
  const Transform = TIccTransform.Create(FProfile);
  try
    Result := ConvertWithTransform(Raster, Transform);
  finally
    Transform.Free;
  end;
end;

end.
