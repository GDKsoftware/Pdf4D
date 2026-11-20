// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/state/PDGraphicsState.java (3.0.8), without colour, clipping and line style
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/state/PDTextState.java (3.0.8)
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/state/RenderingMode.java (3.0.8)
unit Pdf4D.Content.GraphicsState;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Common.Matrix,
  Pdf4D.Font.Base;

type
  {$SCOPEDENUMS ON}
  TRenderingMode = (Fill, Stroke, FillStroke, Neither, FillClip, StrokeClip, FillStrokeClip, NeitherClip);
  {$SCOPEDENUMS OFF}

  TRenderingModeHelper = record helper for TRenderingMode
    // RenderingMode.fromInt gives an ArrayIndexOutOfBoundsException for a value outside 0..7; this gives False
    class function TryFromInt(const Value: Integer; out Mode: TRenderingMode): Boolean; static;

    function IntValue: Integer;
    function IsFill: Boolean;
    function IsStroke: Boolean;
    function IsClip: Boolean;
  end;

  // The text state parameters (PDF 32000, 9.3). Font is not owned: it belongs to the document context.
  TPDTextState = record
    CharacterSpacing: Single;
    WordSpacing: Single;
    // A percentage, 100 by default
    HorizontalScaling: Single;
    Leading: Single;
    Font: TPDFont;
    FontSize: Single;
    RenderingMode: TRenderingMode;
    Rise: Single;
    Knockout: Boolean;

    // The values of a new PDTextState. Default(TPDTextState) has a horizontal scaling of 0.
    class function Create: TPDTextState; static;
  end;

  // The part of PDGraphicsState that text extraction needs: the CTM, the text state and the two text matrices, which
  // PDFBox keeps here as well so that q and Q save and restore them. Colour, clipping and line style are left out.
  TPDGraphicsState = class
  private
    FCurrentTransformationMatrix: TPdfMatrix;
    FTextMatrix: TPdfMatrix;
    FHasTextMatrix: Boolean;
    FTextLineMatrix: TPdfMatrix;
    FHasTextLineMatrix: Boolean;

  protected
    // Copies the fields of this class into Target. A Clone of a subclass makes its own object, calls this, and copies the
    // fields it adds.
    procedure CopyBaseTo(const Target: TPDGraphicsState);

  public
    // A public field because a record in a property cannot be changed in place (State.TextState.FontSize := 12)
    TextState: TPDTextState;

    // The CTM is the identity, the text state is TPDTextState.Create and there are no text matrices
    constructor Create;

    // An independent copy: changing the copy leaves this state alone. The font is shared, as in PDFBox. A subclass that adds
    // fields overrides this, so that q and the start of a form keep them.
    function Clone: TPDGraphicsState; virtual;

    // The text matrices are null until BT sets them, as in PDFBox
    function TryGetTextMatrix(out Matrix: TPdfMatrix): Boolean;
    procedure SetTextMatrix(const Matrix: TPdfMatrix);
    procedure ClearTextMatrix;
    function TryGetTextLineMatrix(out Matrix: TPdfMatrix): Boolean;
    procedure SetTextLineMatrix(const Matrix: TPdfMatrix);
    procedure ClearTextLineMatrix;

    property CurrentTransformationMatrix: TPdfMatrix read FCurrentTransformationMatrix write FCurrentTransformationMatrix;
  end;

implementation

{ TRenderingModeHelper }

class function TRenderingModeHelper.TryFromInt(const Value: Integer; out Mode: TRenderingMode): Boolean;
begin
  Result := ((Value >= Ord(Low(TRenderingMode))) and (Value <= Ord(High(TRenderingMode))));
  if Result then
  begin
    Mode := TRenderingMode(Value);
  end
  else
  begin
    Mode := TRenderingMode.Fill;
  end;
end;

function TRenderingModeHelper.IntValue: Integer;
begin
  Result := Ord(Self);
end;

function TRenderingModeHelper.IsFill: Boolean;
begin
  Result := (Self in [TRenderingMode.Fill, TRenderingMode.FillStroke, TRenderingMode.FillClip, TRenderingMode.FillStrokeClip]);
end;

function TRenderingModeHelper.IsStroke: Boolean;
begin
  Result := (Self in [TRenderingMode.Stroke, TRenderingMode.FillStroke, TRenderingMode.StrokeClip, TRenderingMode.FillStrokeClip]);
end;

function TRenderingModeHelper.IsClip: Boolean;
begin
  Result := (Self in [TRenderingMode.FillClip, TRenderingMode.StrokeClip, TRenderingMode.FillStrokeClip, TRenderingMode.NeitherClip]);
end;

{ TPDTextState }

class function TPDTextState.Create: TPDTextState;
begin
  Result := Default(TPDTextState);
  Result.HorizontalScaling := 100;
  Result.RenderingMode := TRenderingMode.Fill;
  Result.Knockout := True;
end;

{ TPDGraphicsState }

constructor TPDGraphicsState.Create;
begin
  inherited Create;
  FCurrentTransformationMatrix := TPdfMatrix.Identity;
  TextState := TPDTextState.Create;
end;

procedure TPDGraphicsState.CopyBaseTo(const Target: TPDGraphicsState);
begin
  Target.FCurrentTransformationMatrix := FCurrentTransformationMatrix;
  Target.TextState := TextState;
  Target.FTextMatrix := FTextMatrix;
  Target.FHasTextMatrix := FHasTextMatrix;
  Target.FTextLineMatrix := FTextLineMatrix;
  Target.FHasTextLineMatrix := FHasTextLineMatrix;
end;

function TPDGraphicsState.Clone: TPDGraphicsState;
begin
  Result := TPDGraphicsState.Create;
  CopyBaseTo(Result);
end;

function TPDGraphicsState.TryGetTextMatrix(out Matrix: TPdfMatrix): Boolean;
begin
  Result := FHasTextMatrix;
  if Result then
  begin
    Matrix := FTextMatrix;
  end
  else
  begin
    Matrix := TPdfMatrix.Identity;
  end;
end;

procedure TPDGraphicsState.SetTextMatrix(const Matrix: TPdfMatrix);
begin
  FTextMatrix := Matrix;
  FHasTextMatrix := True;
end;

procedure TPDGraphicsState.ClearTextMatrix;
begin
  FHasTextMatrix := False;
end;

function TPDGraphicsState.TryGetTextLineMatrix(out Matrix: TPdfMatrix): Boolean;
begin
  Result := FHasTextLineMatrix;
  if Result then
  begin
    Matrix := FTextLineMatrix;
  end
  else
  begin
    Matrix := TPdfMatrix.Identity;
  end;
end;

procedure TPDGraphicsState.SetTextLineMatrix(const Matrix: TPdfMatrix);
begin
  FTextLineMatrix := Matrix;
  FHasTextLineMatrix := True;
end;

procedure TPDGraphicsState.ClearTextLineMatrix;
begin
  FHasTextLineMatrix := False;
end;

end.
