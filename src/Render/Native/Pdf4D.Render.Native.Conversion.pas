// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.Native.Conversion;

{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  System.Math,
  Pdf4D.Common.Matrix,
  Pdf4D.Common.Path,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Render.Native.Transform,
  Pdf4D.Render.Native.Path,
  Pdf4D.Render.Native.Color,
  Pdf4D.Render.Native.BlendMode,
  Pdf4D.Render.Native.Pipeline.Context,
  Pdf4D.Render.Native.Scan,
  Pdf4D.Render.Native.Shader,
  Pdf4D.Render.Native.Stroker,
  Pdf4D.Render.Native.Dash;

type
  // The translation of the device types of Pdf4D into the types of the port of tiny-skia. A conversion of input that can be wrong (a
  // path with a point that is not finite, a stroke with a dash that tiny-skia refuses) gives False, and the caller draws nothing.
  //
  // The conversions that invert a transform must run inside TTsFloatMode, like everything that works with the transform.
  TTsConversion = record
  public
    // A path of the verbs and points of Path; QuadTo stays a quad. False for a path without a usable segment (nothing, or only a MoveTo)
    // and for a path with a point that is not finite.
    class function TryToPath(const Path: TPdfPath; out Ts: TTsPath): Boolean; static;

    // PDF [a b c d e f] is x' = a * x + c * y + e, y' = b * x + d * y + f: FromRow(a, b, c, d, e, f)
    class function ToTransform(const Matrix: TPdfMatrix): TTsTransform; static;

    // The transform of a matrix that maps to the device: False when the transform or its inverse is not finite (a singular matrix, a scale
    // that is so small that its inverse overflows), because nothing sensible can be drawn with it.
    class function TryToDeviceTransform(const Matrix: TPdfMatrix; out Ts: TTsTransform): Boolean; static;

    // False for a width or miter limit that is not finite or a negative width, and for a dash that tiny-skia refuses (not finite, negative,
    // an odd number of lengths, a sum of zero)
    class function TryToStroke(const Style: TPdfStrokeStyle; out Stroke: TTsStroke): Boolean; static;

    // The color with the alpha of Composite on top of its own: an alpha that is not a number counts as 0
    class function ToColor(const Color: TPdfDeviceColor; const Alpha: Single): TTsColor; static;

    class function ToFilterQuality(const Filter: TPdfImageFilter): TTsFilterQuality; static;
    class function ToSpreadMode(const Mode: TPdfTileMode): TTsSpreadMode; static;
    class function ToBlendMode(const Mode: TPdfBlendMode): TTsBlendMode; static;
    class function ToLineCap(const Cap: TPdfLineCap): TTsLineCap; static;
    class function ToLineJoin(const Join: TPdfLineJoin): TTsLineJoin; static;
    class function ToFillRule(const Rule: TPdfFillRule): TTsFillRule; static;
  end;

implementation

function IsFiniteSingle(const Value: Single): Boolean;
begin
  Result := not (IsNan(Value) or IsInfinite(Value));
end;

{ TTsConversion }

class function TTsConversion.TryToPath(const Path: TPdfPath; out Ts: TTsPath): Boolean;
begin
  Ts := Default(TTsPath);

  for var PointIndex := 0 to Path.PointCount - 1 do
  begin
    const Point = Path.Point(PointIndex);
    if not (IsFiniteSingle(Point.X) and IsFiniteSingle(Point.Y)) then
    begin
      Exit(False);
    end;
  end;

  var Builder := TTsPathBuilder.New;
  var PointIndex := 0;
  for var VerbIndex := 0 to Path.VerbCount - 1 do
  begin
    case Path.Verb(VerbIndex) of
      TPdfPathVerb.MoveTo:
        begin
          Builder.MoveTo(Path.Point(PointIndex).X, Path.Point(PointIndex).Y);
          Inc(PointIndex);
        end;
      TPdfPathVerb.LineTo:
        begin
          Builder.LineTo(Path.Point(PointIndex).X, Path.Point(PointIndex).Y);
          Inc(PointIndex);
        end;
      TPdfPathVerb.QuadTo:
        begin
          Builder.QuadTo(Path.Point(PointIndex).X, Path.Point(PointIndex).Y, Path.Point(PointIndex + 1).X, Path.Point(PointIndex + 1).Y);
          Inc(PointIndex, 2);
        end;
      TPdfPathVerb.CubicTo:
        begin
          Builder.CubicTo(Path.Point(PointIndex).X, Path.Point(PointIndex).Y, Path.Point(PointIndex + 1).X, Path.Point(PointIndex + 1).Y,
                          Path.Point(PointIndex + 2).X, Path.Point(PointIndex + 2).Y);
          Inc(PointIndex, 3);
        end;
      TPdfPathVerb.Close:
        begin
          Builder.Close;
        end;
    end;
  end;

  Result := Builder.TryFinish(Ts);
end;

class function TTsConversion.ToTransform(const Matrix: TPdfMatrix): TTsTransform;
begin
  Result := TTsTransform.FromRow(Matrix.GetValue(0, 0), Matrix.GetValue(0, 1), Matrix.GetValue(1, 0), Matrix.GetValue(1, 1),
                                 Matrix.GetValue(2, 0), Matrix.GetValue(2, 1));
end;

class function TTsConversion.TryToDeviceTransform(const Matrix: TPdfMatrix; out Ts: TTsTransform): Boolean;
begin
  Ts := ToTransform(Matrix);
  if not Ts.IsFinite then
  begin
    Exit(False);
  end;

  var Inverted: TTsTransform;
  if not Ts.TryInvert(Inverted) then
  begin
    Exit(False);
  end;

  Result := Inverted.IsFinite;
end;

class function TTsConversion.TryToStroke(const Style: TPdfStrokeStyle; out Stroke: TTsStroke): Boolean;
begin
  Stroke := TTsStroke.New;

  if not (IsFiniteSingle(Style.Width) and (Style.Width >= 0)) then
  begin
    Exit(False);
  end;

  if not IsFiniteSingle(Style.MiterLimit) then
  begin
    Exit(False);
  end;

  Stroke.Width := Style.Width;
  Stroke.MiterLimit := Style.MiterLimit;
  Stroke.LineCap := ToLineCap(Style.Cap);
  Stroke.LineJoin := ToLineJoin(Style.Join);

  if Length(Style.Dashes) = 0 then
  begin
    Exit(True);
  end;

  Stroke.HasDash := TTsStrokeDash.TryCreate(Style.Dashes, Style.DashPhase, Stroke.Dash);
  Result := Stroke.HasDash;
end;

class function TTsConversion.ToColor(const Color: TPdfDeviceColor; const Alpha: Single): TTsColor;
begin
  Result := TTsColor.FromRgba8(Color.R, Color.G, Color.B, Color.A);

  var Opacity := Alpha;
  if IsNan(Opacity) then
  begin
    Opacity := 0;
  end;

  Result.ApplyOpacity(Opacity);
end;

class function TTsConversion.ToFilterQuality(const Filter: TPdfImageFilter): TTsFilterQuality;
begin
  case Filter of
    TPdfImageFilter.Nearest  : Result := TTsFilterQuality.Nearest;
    TPdfImageFilter.Bilinear : Result := TTsFilterQuality.Bilinear;
    TPdfImageFilter.Bicubic  : Result := TTsFilterQuality.Bicubic;
  else
    raise ENotSupportedException.CreateFmt('Unsupported image filter: %d', [Ord(Filter)]);
  end;
end;

class function TTsConversion.ToSpreadMode(const Mode: TPdfTileMode): TTsSpreadMode;
begin
  case Mode of
    TPdfTileMode.Decal    : Result := TTsSpreadMode.Decal;
    TPdfTileMode.&Repeat  : Result := TTsSpreadMode.&Repeat;
  else
    raise ENotSupportedException.CreateFmt('Unsupported tile mode: %d', [Ord(Mode)]);
  end;
end;

class function TTsConversion.ToBlendMode(const Mode: TPdfBlendMode): TTsBlendMode;
begin
  case Mode of
    TPdfBlendMode.Normal     : Result := TTsBlendMode.SourceOver;
    TPdfBlendMode.Multiply   : Result := TTsBlendMode.Multiply;
    TPdfBlendMode.Screen     : Result := TTsBlendMode.Screen;
    TPdfBlendMode.Overlay    : Result := TTsBlendMode.Overlay;
    TPdfBlendMode.Darken     : Result := TTsBlendMode.Darken;
    TPdfBlendMode.Lighten    : Result := TTsBlendMode.Lighten;
    TPdfBlendMode.ColorDodge : Result := TTsBlendMode.ColorDodge;
    TPdfBlendMode.ColorBurn  : Result := TTsBlendMode.ColorBurn;
    TPdfBlendMode.HardLight  : Result := TTsBlendMode.HardLight;
    TPdfBlendMode.SoftLight  : Result := TTsBlendMode.SoftLight;
    TPdfBlendMode.Difference : Result := TTsBlendMode.Difference;
    TPdfBlendMode.Exclusion  : Result := TTsBlendMode.Exclusion;
    TPdfBlendMode.Hue        : Result := TTsBlendMode.Hue;
    TPdfBlendMode.Saturation : Result := TTsBlendMode.Saturation;
    TPdfBlendMode.Color      : Result := TTsBlendMode.Color;
    TPdfBlendMode.Luminosity : Result := TTsBlendMode.Luminosity;
  else
    raise ENotSupportedException.CreateFmt('Unsupported blend mode: %d', [Ord(Mode)]);
  end;
end;

class function TTsConversion.ToLineCap(const Cap: TPdfLineCap): TTsLineCap;
begin
  case Cap of
    TPdfLineCap.Butt   : Result := TTsLineCap.Butt;
    TPdfLineCap.Round  : Result := TTsLineCap.Round;
    TPdfLineCap.Square : Result := TTsLineCap.Square;
  else
    raise ENotSupportedException.CreateFmt('Unsupported line cap: %d', [Ord(Cap)]);
  end;
end;

class function TTsConversion.ToLineJoin(const Join: TPdfLineJoin): TTsLineJoin;
begin
  case Join of
    TPdfLineJoin.Miter : Result := TTsLineJoin.Miter;
    TPdfLineJoin.Round : Result := TTsLineJoin.Round;
    TPdfLineJoin.Bevel : Result := TTsLineJoin.Bevel;
  else
    raise ENotSupportedException.CreateFmt('Unsupported line join: %d', [Ord(Join)]);
  end;
end;

class function TTsConversion.ToFillRule(const Rule: TPdfFillRule): TTsFillRule;
begin
  case Rule of
    TPdfFillRule.NonZero : Result := TTsFillRule.Winding;
    TPdfFillRule.EvenOdd : Result := TTsFillRule.EvenOdd;
  else
    raise ENotSupportedException.CreateFmt('Unsupported fill rule: %d', [Ord(Rule)]);
  end;
end;

end.
