// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/rendering/PageDrawer.java (3.0.8): applySoftMaskToPaint and applyTransferFunction, and
// pdfbox/src/main/java/org/apache/pdfbox/rendering/SoftMask.java (3.0.8): the mask of the SoftPaintContext. The device multiplies the
// alpha of what it draws with the mask, so there is no paint object.
unit Pdf4D.Render.SoftMaskPaint;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  Pdf4D.Cos.Base,
  Pdf4D.Graphics.&Function,
  Pdf4D.Graphics.SoftMask,
  Pdf4D.Model.DocumentContext,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.PageDrawer;

type
  // applyTransferFunction
  TPdfImageTransfer = class
  private
    class function TryCreateFunctions(const Transfer: TCosBase; const Context: TPDDocumentContext; out Functions: TArray<TPDFunction>): Boolean; static;
    class function Unpremultiplied(const Premultiplied, Alpha: Byte): Byte; static;
    class function Premultiplied(const Value, Alpha: Byte): Byte; static;

  public
    // The transfer function for every value of a channel: (int) (f(i / 255) * 255), limited to 0..255. Transfer may be nil.
    class function Table(const Transfer: TPDFunction): TArray<Byte>; static;

    // Replaces the colours of Bitmap (premultiplied) by what the transfer function gives for them, and keeps the alpha. Transfer is the
    // function, or an array of at least three functions (red, green and blue; a fourth is for gray, which an RGB image does not use). A
    // transfer that cannot be made is logged and leaves the bitmap as it is.
    class procedure Apply(const Bitmap: TPdfBitmap; const Transfer: TCosBase; const Context: TPDDocumentContext); static;
  end;

  TPdfSoftMaskBuilder = class
  private
    class function TryGetBackdropColor(const Drawer: TPdfPageDrawer; const Mask: IPdfSoftMask; out Color: TPdfDeviceColor): Boolean; static;
    class function TryMakeBackdropColor(const Drawer: TPdfPageDrawer; const Mask: IPdfSoftMask; out Color: TPdfDeviceColor): Boolean; static;
    class function GrayOf(const Red, Green, Blue: Byte): Byte; static;

  public
    // applySoftMaskToPaint: the mask of the group of Mask, in the pixels of the device of Drawer. nil when the group draws nothing in the
    // device (Adobe ignores empty soft masks). The caller owns the mask.
    class function Build(const Drawer: TPdfPageDrawer; const Mask: IPdfSoftMask): TPdfAlphaMask; static;

    // The alpha of Image (IsAlpha) or its luminosity as a mask whose top left pixel lies at (Left, Top) of the device, outside which the
    // mask has OutsideValue. Transfer may be nil and is applied to the values and to OutsideValue. Image holds premultiplied values over
    // a black backdrop, as the layer of a group does.
    class function MaskFromImage(const Image: TPdfBitmap; const Left, Top: Integer; const IsAlpha: Boolean; const OutsideValue: Byte;
                                 const Transfer: TPDFunction): TPdfAlphaMask; static;
    // The luminosity of a colour in 0..255, with the weights of the gray conversion of Java2D (0.299, 0.587 and 0.114)
    class function Luminosity(const Color: TPdfDeviceColor): Byte; static;
  end;

implementation

uses
  System.Math,
  System.SysUtils,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Graphics.Color,
  Pdf4D.Graphics.Color.Factory,
  Pdf4D.Model.FormXObject,
  Pdf4D.Model.Resources;

resourcestring
  TransferIgnored = 'A transfer function is ignored: %s';
  BackdropIgnored = 'The /BC of a soft mask is ignored: %s';

const
  ChannelCount = 256;
  MaxChannel = 255;
  BytesPerPixel = 4;
  AlphaOffset = 3;
  // 0.299, 0.587 and 0.114 in 256ths, as the conversion of Java2D from an RGB image to a gray image has them
  RedWeight = 77;
  GreenWeight = 150;
  BlueWeight = 29;
  WeightShift = 8;
  WeightRounding = 128;
  ColorChannels = 3;
  AlphaSubType = 'Alpha';

{ TPdfImageTransfer }

class function TPdfImageTransfer.Table(const Transfer: TPDFunction): TArray<Byte>;
begin
  SetLength(Result, ChannelCount);
  for var Value := 0 to MaxChannel do
  begin
    Result[Value] := Byte(Value);
    if not Assigned(Transfer) then
    begin
      Continue;
    end;

    const Output = Transfer.Eval([Value / MaxChannel]);
    const IsNumber = ((Length(Output) > 0) and (not IsNan(Output[0])));
    if IsNumber then
    begin
      Result[Value] := Byte(Trunc(Max(Min(Output[0], 1), 0) * MaxChannel));
    end;
  end;
end;

class procedure TPdfImageTransfer.Apply(const Bitmap: TPdfBitmap; const Transfer: TCosBase; const Context: TPDDocumentContext);
begin
  var Functions: TArray<TPDFunction>;
  if not TryCreateFunctions(Transfer, Context, Functions) then
  begin
    Exit;
  end;

  try
    const IsPerColor = (Length(Functions) > 1);
    var Tables: array[0..ColorChannels - 1] of TArray<Byte>;
    for var Channel := 0 to ColorChannels - 1 do
    begin
      Tables[Channel] := Table(Functions[Channel * Ord(IsPerColor)]);
    end;

    for var Y := 0 to Bitmap.Height - 1 do
    begin
      const Row = Bitmap.ScanLine(Y);
      for var X := 0 to Bitmap.Width - 1 do
      begin
        const Pixel = Row + X * BytesPerPixel;
        const Alpha = Pixel[AlphaOffset];
        for var Channel := 0 to ColorChannels - 1 do
        begin
          const Value = Tables[Channel][Unpremultiplied(Pixel[Channel], Alpha)];
          Pixel[Channel] := Premultiplied(Value, Alpha);
        end;
      end;
    end;
  finally
    for var Item in Functions do
    begin
      Item.Free;
    end;
  end;
end;

class function TPdfImageTransfer.TryCreateFunctions(const Transfer: TCosBase; const Context: TPDDocumentContext;
                                                    out Functions: TArray<TPDFunction>): Boolean;
begin
  Functions := nil;
  try
    if Transfer is TCosArray then
    begin
      const Items = TCosArray(Transfer);
      for var Index := 0 to ColorChannels - 1 do
      begin
        SetLength(Functions, Index + 1);
        Functions[Index] := nil;
        Functions[Index] := TPDFunction.Create(Items.GetObject(Index), Context);
      end;
    end
    else
    begin
      Functions := [TPDFunction.Create(Transfer, Context)];
    end;
    Result := True;
  except
    on Error: EPdfParseException do
    begin
      for var Item in Functions do
      begin
        Item.Free;
      end;
      Functions := nil;
      if Assigned(Context.Log) then
      begin
        Context.Log.Warning(TransferIgnored, [Error.Message]);
      end;
      Result := False;
    end;
  end;
end;

class function TPdfImageTransfer.Unpremultiplied(const Premultiplied, Alpha: Byte): Byte;
begin
  if Alpha = 0 then
  begin
    Exit(0);
  end;
  Result := Byte(Min((Premultiplied * MaxChannel + Alpha div 2) div Alpha, MaxChannel));
end;

class function TPdfImageTransfer.Premultiplied(const Value, Alpha: Byte): Byte;
begin
  Result := Byte((Value * Alpha + MaxChannel div 2) div MaxChannel);
end;

{ TPdfSoftMaskBuilder }

class function TPdfSoftMaskBuilder.Build(const Drawer: TPdfPageDrawer; const Mask: IPdfSoftMask): TPdfAlphaMask;
begin
  Result := nil;
  const Form = Mask.Group;
  if not Assigned(Form) then
  begin
    Exit;
  end;

  const IsAlpha = (Mask.SubType = AlphaSubType);
  var Backdrop := TPdfDeviceColor.Transparent;
  const HasBackdrop = ((not IsAlpha) and TryGetBackdropColor(Drawer, Mask, Backdrop));

  var Bounds: TRect;
  var Image: TPdfBitmap;
  if not Drawer.TryRenderMaskGroup(Form, Mask.InitialTransformationMatrix, HasBackdrop, Backdrop, Bounds, Image) then
  begin
    Exit;
  end;

  try
    var OutsideValue: Byte := 0;
    if HasBackdrop then
    begin
      OutsideValue := Luminosity(Backdrop);
    end;
    Result := MaskFromImage(Image, Bounds.Left, Bounds.Top, IsAlpha, OutsideValue, Mask.TransferFunction);
  finally
    Image.Free;
  end;
end;

// The /BC in the colour space of the group, as the colour of the layer that the group is drawn on
class function TPdfSoftMaskBuilder.TryGetBackdropColor(const Drawer: TPdfPageDrawer; const Mask: IPdfSoftMask; out Color: TPdfDeviceColor): Boolean;
begin
  Color := TPdfDeviceColor.Transparent;
  try
    Result := TryMakeBackdropColor(Drawer, Mask, Color);
  except
    on Error: Exception do
    begin
      const IsRecoverable = ((Error is EPdfException) or (Error is EArgumentException) or (Error is EInvalidOpException));
      if not IsRecoverable then
      begin
        raise;
      end;
      Drawer.LogWarning(BackdropIgnored, [Error.Message]);
      Result := False;
    end;
  end;
end;

class function TPdfSoftMaskBuilder.TryMakeBackdropColor(const Drawer: TPdfPageDrawer; const Mask: IPdfSoftMask; out Color: TPdfDeviceColor): Boolean;
begin
  var Components: TArray<Single>;
  var Group: TPDTransparencyGroupAttributes;
  const HasEntries = (Mask.TryGetBackdropColor(Components) and Mask.Group.TryGetGroup(Group) and Assigned(Group.ColorSpace));
  if not HasEntries then
  begin
    Exit(False);
  end;

  const Resources = TPDResources.Create(nil, Drawer.Page.Context);
  try
    const Space = TPDColorSpaceFactory.Create(Group.ColorSpace, Resources);
    Color := TPDColor.Create(Space, Components).ToRgb.ToDeviceColor;
  finally
    Resources.Free;
  end;
  Result := True;
end;

class function TPdfSoftMaskBuilder.GrayOf(const Red, Green, Blue: Byte): Byte;
begin
  Result := Byte((RedWeight * Red + GreenWeight * Green + BlueWeight * Blue + WeightRounding) shr WeightShift);
end;

class function TPdfSoftMaskBuilder.Luminosity(const Color: TPdfDeviceColor): Byte;
begin
  Result := GrayOf(Color.R, Color.G, Color.B);
end;

class function TPdfSoftMaskBuilder.MaskFromImage(const Image: TPdfBitmap; const Left, Top: Integer; const IsAlpha: Boolean;
                                                 const OutsideValue: Byte; const Transfer: TPDFunction): TPdfAlphaMask;
begin
  const Table = TPdfImageTransfer.Table(Transfer);
  Result := TPdfAlphaMask.Create(Left, Top, Image.Width, Image.Height, Table[OutsideValue]);
  try
    const Values = Result.Values;
    var Index := 0;
    for var Y := 0 to Image.Height - 1 do
    begin
      const Row = Image.ScanLine(Y);
      for var X := 0 to Image.Width - 1 do
      begin
        const Pixel = Row + X * BytesPerPixel;
        var Value := Pixel[AlphaOffset];
        if not IsAlpha then
        begin
          Value := GrayOf(Pixel[0], Pixel[1], Pixel[2]);
        end;
        Values[Index] := Table[Value];
        Inc(Index);
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.
