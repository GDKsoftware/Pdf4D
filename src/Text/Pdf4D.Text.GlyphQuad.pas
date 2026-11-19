// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Text.GlyphQuad;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  Pdf4D.Common.Quad,
  Pdf4D.Text.TextPosition;

type
  // The quad of one glyph in PDF user space, without page rotation: the baseline follows the text matrix, the height runs from
  // the descent to the ascent of the font
  TGlyphQuad = class
  private
    class function GetAdvance(const Position: TTextPosition; const Start, CropLowerLeft: TPointF): TPointF; static;
    class function BuildQuad(const Position: TTextPosition; const Start, Advance: TPointF): TPdfQuad; static;
    class function TryGetVerticalExtent(const Position: TTextPosition; out Descent, Ascent: Single): Boolean; static;
    class function TryGetBoundingBoxExtent(const Position: TTextPosition; out Descent, Ascent: Single): Boolean; static;
    class function Normalize(const Vector: TPointF): TPointF; static;
    class function Offset(const Origin, Direction: TPointF; const Distance: Single): TPointF; static;

  public
    // False when the glyph has no finite quad, for instance with a matrix of NaN or infinity
    class function TryCreate(const Position: TTextPosition; const CropLowerLeft: TPointF; out Quad: TPdfQuad): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Pdf4D.Common.FloatGuard,
  Pdf4D.Common.Matrix,
  Pdf4D.Font.Base,
  Pdf4D.Font.Descriptor,
  Pdf4D.Font.Type3;

const
  GlyphSpaceUnitsPerEm = 1000;

{ TGlyphQuad }

class function TGlyphQuad.TryCreate(const Position: TTextPosition; const CropLowerLeft: TPointF; out Quad: TPdfQuad): Boolean;
begin
  const Previous = TPdfFloatGuard.Enter;
  try
    const Matrix = Position.TextMatrix;
    const Start = TPointF.Create(Matrix.TranslateX + CropLowerLeft.X, Matrix.TranslateY + CropLowerLeft.Y);
    const Advance = GetAdvance(Position, Start, CropLowerLeft);

    Quad := BuildQuad(Position, Start, Advance);
    Result := Quad.IsFinite;
  finally
    TPdfFloatGuard.Leave(Previous);
  end;
end;

class function TGlyphQuad.GetAdvance(const Position: TTextPosition; const Start, CropLowerLeft: TPointF): TPointF;
begin
  Result := TPointF.Create(Position.EndX + CropLowerLeft.X - Start.X, Position.EndY + CropLowerLeft.Y - Start.Y);

  const HasAdvance = ((Result.X <> 0) or (Result.Y <> 0));
  const HasIndividualWidth = (Length(Position.IndividualWidths) > 0);
  if HasAdvance or (not HasIndividualWidth) then
  begin
    Exit;
  end;

  const Matrix = Position.TextMatrix;
  const Direction = Normalize(TPointF.Create(Matrix.ScaleX, Matrix.ShearY));
  const Width = Position.IndividualWidths[0];
  Result := TPointF.Create(Direction.X * Width, Direction.Y * Width);
end;

class function TGlyphQuad.BuildQuad(const Position: TTextPosition; const Start, Advance: TPointF): TPdfQuad;
begin
  var Descent: Single;
  var Ascent: Single;
  const Matrix = Position.TextMatrix;
  var Up := TPointF.Create(Matrix.ShearX / GlyphSpaceUnitsPerEm, Matrix.ScaleY / GlyphSpaceUnitsPerEm);
  if not TryGetVerticalExtent(Position, Descent, Ascent) then
  begin
    Up := Normalize(TPointF.Create(Matrix.ShearX, Matrix.ScaleY));
    Descent := 0;
    Ascent := Position.HeightDir;
  end;

  const BottomStart = Offset(Start, Up, Descent);
  const TopStart = Offset(Start, Up, Ascent);
  Result := TPdfQuad.Create(BottomStart,
                            TPointF.Create(BottomStart.X + Advance.X, BottomStart.Y + Advance.Y),
                            TPointF.Create(TopStart.X + Advance.X, TopStart.Y + Advance.Y),
                            TopStart);
end;

class function TGlyphQuad.TryGetVerticalExtent(const Position: TTextPosition; out Descent, Ascent: Single): Boolean;
begin
  Descent := 0;
  Ascent := 0;
  if Position.Font is TPDType3Font then
  begin
    Exit(False);
  end;

  var Descriptor: TPDFontDescriptor;
  const HasDescriptor = Position.Font.TryGetFontDescriptor(Descriptor);
  const HasMetrics = (HasDescriptor and ((Descriptor.Ascent <> 0) or (Descriptor.Descent <> 0)));
  if HasMetrics then
  begin
    Descent := Descriptor.Descent;
    Ascent := Descriptor.Ascent;
    Exit(True);
  end;

  Result := TryGetBoundingBoxExtent(Position, Descent, Ascent);
end;

class function TGlyphQuad.TryGetBoundingBoxExtent(const Position: TTextPosition; out Descent, Ascent: Single): Boolean;
begin
  const Box = Position.Font.GetBoundingBox;
  const IsEmpty = ((Box.Width = 0) and (Box.Height = 0));

  Descent := Box.LowerLeftY;
  Ascent := Box.UpperRightY;
  Result := (not IsEmpty);
end;

class function TGlyphQuad.Normalize(const Vector: TPointF): TPointF;
begin
  const Length = Sqrt(Vector.X * Vector.X + Vector.Y * Vector.Y);

  Result := TPointF.Create(Vector.X / Length, Vector.Y / Length);
end;

class function TGlyphQuad.Offset(const Origin, Direction: TPointF; const Distance: Single): TPointF;
begin
  Result := TPointF.Create(Origin.X + Direction.X * Distance, Origin.Y + Direction.Y * Distance);
end;

end.
