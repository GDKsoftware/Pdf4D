// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.Skia.Convert;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  System.UITypes,
  System.Math.Vectors,
  System.Skia,
  Pdf4D.Common.Matrix,
  Pdf4D.Common.Path,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Device.Interfaces;

type
  // The translation of Pdf4D device types into System.Skia types. Only the System.Skia API that Delphi 12 and 13 share is used.
  TPdfSkiaConvert = class
  private
    class function StrokeCap(const Cap: TPdfLineCap): TSkStrokeCap; static;
    class function StrokeJoin(const Join: TPdfLineJoin): TSkStrokeJoin; static;
    class function TileMode(const Mode: TPdfTileMode): TSkTileMode; static;
    class function Sampling(const Filter: TPdfImageFilter): TSkSamplingOptions; static;
    class function ScaledAlpha(const Alpha: Byte; const Composite: TPdfComposite): Byte; static;
    class function SolidPaint(const Color: TPdfDeviceColor; const Composite: TPdfComposite): ISkPaint; static;
    class function ShaderPaint(const Paint: TPdfPaint; const Transform: TPdfMatrix; const Composite: TPdfComposite): ISkPaint; static;

  public
    // The same row-vector convention on both sides: x' = a * x + c * y + e
    class function Matrix(const Value: TPdfMatrix): TMatrix; static;
    // False for a matrix that cannot be inverted
    class function TryInvert(const Value: TPdfMatrix; out Inverse: TPdfMatrix): Boolean; static;
    class function Path(const Source: TPdfPath; const FillRule: TPdfFillRule): ISkPath; static;
    // An image with a copy of the pixels of Bitmap
    class function Image(const Bitmap: TPdfBitmap): ISkImage; static;
    // The paint for FillPath and StrokePath; Transform is the matrix that the canvas has when the paint is used. False when
    // the paint cannot be made because Transform cannot be inverted (a bitmap paint then covers nothing).
    class function TryMakePaint(const Paint: TPdfPaint; const Transform: TPdfMatrix; const Composite: TPdfComposite; out SkPaint: ISkPaint): Boolean; static;
    // A paint for DrawImageRect: opaque white with the alpha of Composite
    class function ImagePaint(const Composite: TPdfComposite): ISkPaint; static;
    class procedure MakeStroke(const Stroke: TPdfStrokeStyle; const SkPaint: ISkPaint); static;
    class function ImageSampling(const Filter: TPdfImageFilter): TSkSamplingOptions; static;
    class function MakeColor(const Alpha, Red, Green, Blue: Byte): TAlphaColor; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

const
  MaxChannel = 255;

{ TPdfSkiaConvert }

class function TPdfSkiaConvert.Matrix(const Value: TPdfMatrix): TMatrix;
begin
  Result := TMatrix.Identity;
  Result.m11 := Value.GetValue(0, 0);
  Result.m12 := Value.GetValue(0, 1);
  Result.m21 := Value.GetValue(1, 0);
  Result.m22 := Value.GetValue(1, 1);
  Result.m31 := Value.GetValue(2, 0);
  Result.m32 := Value.GetValue(2, 1);
end;

class function TPdfSkiaConvert.TryInvert(const Value: TPdfMatrix; out Inverse: TPdfMatrix): Boolean;
begin
  const A: Double = Value.GetValue(0, 0);
  const B: Double = Value.GetValue(0, 1);
  const C: Double = Value.GetValue(1, 0);
  const D: Double = Value.GetValue(1, 1);
  const E: Double = Value.GetValue(2, 0);
  const F: Double = Value.GetValue(2, 1);

  const Determinant = A * D - B * C;
  const IsInvertible = (Abs(Determinant) > 1E-30);
  Inverse := TPdfMatrix.Identity;
  if not IsInvertible then
  begin
    Exit(False);
  end;

  Inverse := TPdfMatrix.Create(D / Determinant, -B / Determinant, -C / Determinant, A / Determinant,
                               (C * F - D * E) / Determinant, (B * E - A * F) / Determinant);
  Result := True;
end;

class function TPdfSkiaConvert.Path(const Source: TPdfPath; const FillRule: TPdfFillRule): ISkPath;
begin
  const Builder: ISkPathBuilder = TSkPathBuilder.Create;
  case FillRule of
    TPdfFillRule.NonZero : Builder.FillType := TSkPathFillType.Winding;
    TPdfFillRule.EvenOdd : Builder.FillType := TSkPathFillType.EvenOdd;
  else
    raise ENotSupportedException.CreateFmt('Unsupported fill rule: %d', [Ord(FillRule)]);
  end;

  var PointIndex := 0;
  for var VerbIndex := 0 to Source.VerbCount - 1 do
  begin
    const Verb = Source.Verb(VerbIndex);
    case Verb of
      TPdfPathVerb.MoveTo:
        begin
          Builder.MoveTo(Source.Point(PointIndex));
          Inc(PointIndex);
        end;
      TPdfPathVerb.LineTo:
        begin
          Builder.LineTo(Source.Point(PointIndex));
          Inc(PointIndex);
        end;
      TPdfPathVerb.QuadTo:
        begin
          Builder.QuadTo(Source.Point(PointIndex), Source.Point(PointIndex + 1));
          Inc(PointIndex, 2);
        end;
      TPdfPathVerb.CubicTo:
        begin
          Builder.CubicTo(Source.Point(PointIndex), Source.Point(PointIndex + 1), Source.Point(PointIndex + 2));
          Inc(PointIndex, 3);
        end;
      TPdfPathVerb.Close:
        begin
          Builder.Close;
        end;
    else
      raise ENotSupportedException.CreateFmt('Unsupported path verb: %d', [Ord(Verb)]);
    end;
  end;

  Result := Builder.Detach;
end;

class function TPdfSkiaConvert.Image(const Bitmap: TPdfBitmap): ISkImage;
begin
  const ImageInfo = TSkImageInfo.Create(Bitmap.Width, Bitmap.Height, TSkColorType.RGBA8888, TSkAlphaType.Premul);
  Result := TSkImage.MakeRasterCopy(ImageInfo, @Bitmap.Pixels[0], Bitmap.Stride);
end;

class function TPdfSkiaConvert.TryMakePaint(const Paint: TPdfPaint; const Transform: TPdfMatrix; const Composite: TPdfComposite;
                                            out SkPaint: ISkPaint): Boolean;
begin
  SkPaint := nil;
  case Paint.Kind of
    TPdfPaintKind.Solid  : SkPaint := SolidPaint(Paint.Color, Composite);
    TPdfPaintKind.Bitmap : SkPaint := ShaderPaint(Paint, Transform, Composite);
  else
    raise ENotSupportedException.CreateFmt('Unsupported paint kind: %d', [Ord(Paint.Kind)]);
  end;

  Result := Assigned(SkPaint);
  if Result then
  begin
    SkPaint.AntiAlias := Composite.AntiAlias;
  end;
end;

class function TPdfSkiaConvert.ImagePaint(const Composite: TPdfComposite): ISkPaint;
begin
  Result := TSkPaint.Create;
  Result.Color := MakeColor(ScaledAlpha(MaxChannel, Composite), MaxChannel, MaxChannel, MaxChannel);
  Result.AntiAlias := Composite.AntiAlias;
end;

class procedure TPdfSkiaConvert.MakeStroke(const Stroke: TPdfStrokeStyle; const SkPaint: ISkPaint);
begin
  SkPaint.Style := TSkPaintStyle.Stroke;
  SkPaint.StrokeWidth := Stroke.Width;
  SkPaint.StrokeCap := StrokeCap(Stroke.Cap);
  SkPaint.StrokeJoin := StrokeJoin(Stroke.Join);
  SkPaint.StrokeMiter := Stroke.MiterLimit;

  const IsDashed = (Length(Stroke.Dashes) > 0);
  if IsDashed then
  begin
    SkPaint.PathEffect := TSkPathEffect.MakeDash(Stroke.Dashes, Stroke.DashPhase);
  end;
end;

class function TPdfSkiaConvert.ImageSampling(const Filter: TPdfImageFilter): TSkSamplingOptions;
begin
  Result := Sampling(Filter);
end;

class function TPdfSkiaConvert.MakeColor(const Alpha, Red, Green, Blue: Byte): TAlphaColor;
begin
  Result := (TAlphaColor(Alpha) shl 24) or (TAlphaColor(Red) shl 16) or (TAlphaColor(Green) shl 8) or TAlphaColor(Blue);
end;

class function TPdfSkiaConvert.StrokeCap(const Cap: TPdfLineCap): TSkStrokeCap;
begin
  case Cap of
    TPdfLineCap.Butt   : Result := TSkStrokeCap.Butt;
    TPdfLineCap.Round  : Result := TSkStrokeCap.Round;
    TPdfLineCap.Square : Result := TSkStrokeCap.Square;
  else
    raise ENotSupportedException.CreateFmt('Unsupported line cap: %d', [Ord(Cap)]);
  end;
end;

class function TPdfSkiaConvert.StrokeJoin(const Join: TPdfLineJoin): TSkStrokeJoin;
begin
  case Join of
    TPdfLineJoin.Miter : Result := TSkStrokeJoin.Miter;
    TPdfLineJoin.Round : Result := TSkStrokeJoin.Round;
    TPdfLineJoin.Bevel : Result := TSkStrokeJoin.Bevel;
  else
    raise ENotSupportedException.CreateFmt('Unsupported line join: %d', [Ord(Join)]);
  end;
end;

class function TPdfSkiaConvert.TileMode(const Mode: TPdfTileMode): TSkTileMode;
begin
  case Mode of
    TPdfTileMode.Decal   : Result := TSkTileMode.Decal;
    TPdfTileMode.&Repeat : Result := TSkTileMode.Repeat;
  else
    raise ENotSupportedException.CreateFmt('Unsupported tile mode: %d', [Ord(Mode)]);
  end;
end;

class function TPdfSkiaConvert.Sampling(const Filter: TPdfImageFilter): TSkSamplingOptions;
begin
  case Filter of
    TPdfImageFilter.Nearest  : Result := TSkSamplingOptions.Create(TSkFilterMode.Nearest, TSkMipmapMode.None);
    TPdfImageFilter.Bilinear : Result := TSkSamplingOptions.Create(TSkFilterMode.Linear, TSkMipmapMode.None);
    TPdfImageFilter.Bicubic  : Result := TSkSamplingOptions.Create(TSkCubicResampler.Mitchell);
  else
    raise ENotSupportedException.CreateFmt('Unsupported image filter: %d', [Ord(Filter)]);
  end;
end;

class function TPdfSkiaConvert.ScaledAlpha(const Alpha: Byte; const Composite: TPdfComposite): Byte;
begin
  const Scaled = Round(Alpha * Composite.Alpha);
  Result := Byte(EnsureRange(Scaled, 0, MaxChannel));
end;

class function TPdfSkiaConvert.SolidPaint(const Color: TPdfDeviceColor; const Composite: TPdfComposite): ISkPaint;
begin
  Result := TSkPaint.Create;
  Result.Color := MakeColor(ScaledAlpha(Color.A, Composite), Color.R, Color.G, Color.B);
end;

class function TPdfSkiaConvert.ShaderPaint(const Paint: TPdfPaint; const Transform: TPdfMatrix; const Composite: TPdfComposite): ISkPaint;
begin
  Result := nil;

  // The shader is concatenated with the matrix of the canvas, which is Transform, so its local matrix first undoes Transform
  var InverseTransform: TPdfMatrix;
  const CanInvert = TryInvert(Transform, InverseTransform);
  if not CanInvert then
  begin
    Exit;
  end;

  const LocalMatrix = Paint.BitmapToDevice.Multiply(InverseTransform);
  const Tile = TileMode(Paint.TileMode);
  const Shader = Image(Paint.Bitmap).MakeShader(Matrix(LocalMatrix), Sampling(Paint.Filter), Tile, Tile);

  Result := TSkPaint.Create;
  Result.Color := MakeColor(ScaledAlpha(MaxChannel, Composite), MaxChannel, MaxChannel, MaxChannel);
  Result.Shader := Shader;
end;

end.
