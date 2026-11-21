// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/state/PDGraphicsState.java (3.0.8), the part that
// Pdf4D.Content.GraphicsState leaves out: colour, line style, clipping, blending and alpha
unit Pdf4D.Graphics.State;

{$EXCESSPRECISION OFF}

interface

uses
  Pdf4D.Common.Path,
  Pdf4D.Common.Matrix,
  Pdf4D.Content.GraphicsState,
  Pdf4D.Cos.Base,
  Pdf4D.Graphics.Color,
  Pdf4D.Graphics.LineDash,
  Pdf4D.Graphics.SoftMask,
  Pdf4D.Render.Device.Interfaces;

type
  // The graphics state of the renderer. The colour spaces are not owned (the document context or the process owns them) and neither
  // is Transfer.
  TPdfRenderGraphicsState = class(TPDGraphicsState)
  public
    // The clip of the page and of the forms and groups that are running; nil until the page clip is set. The chain is immutable and
    // shared by a state and its clones.
    Clip: IPdfClipPath;
    StrokingColor: TPDColor;
    NonStrokingColor: TPDColor;
    // Kept apart from the colours, as PDGraphicsState does: a colour that could not be made has no colour space of its own
    StrokingColorSpace: TPDColorSpace;
    NonStrokingColorSpace: TPDColorSpace;
    LineWidth: Single;
    // The values as the file gives them, so possibly outside 0..2; the device maps those to the default
    LineCap: Integer;
    LineJoin: Integer;
    MiterLimit: Single;
    DashPattern: TPDLineDashPattern;
    // One of the four names of the PDF specification, or empty while none is set
    RenderingIntent: string;
    StrokeAdjustment: Boolean;
    Flatness: Single;
    BlendMode: TPdfBlendMode;
    AlphaConstant: Single;
    NonStrokeAlphaConstant: Single;
    AlphaSource: Boolean;
    Transfer: TCosBase;
    // The soft mask that gs set; nil for none. Immutable, so a state and its clones share it.
    SoftMask: IPdfSoftMask;

    // The initial state of a page: black DeviceGray, a line width of 1, miter limit 10, no dashes, no clip, Normal blending
    constructor Create;

    function Clone: TPDGraphicsState; override;

    // Makes the intersection of the current clip and Path (in the space that PathToDevice maps to device pixels) the new clip. The path
    // is copied, so the caller keeps it. A chain that would become longer than MaxDepth paths (at least 1) is replaced by the rectangle of
    // its bounds, which keeps the work of every clip change bounded; the result says that this happened.
    function IntersectClip(const Path: TPdfPath; const PathToDevice: TPdfMatrix; const FillRule: TPdfFillRule;
                           const MaxDepth: Integer = High(Integer)): Boolean;
  end;

implementation

uses
  System.Math,
  Pdf4D.Graphics.Color.Device,
  Pdf4D.Render.ClipPath;

const
  DefaultLineWidth = 1;
  DefaultMiterLimit = 10;
  DefaultFlatness = 1;
  OpaqueAlpha = 1;

{ TPdfRenderGraphicsState }

constructor TPdfRenderGraphicsState.Create;
begin
  inherited Create;
  const Gray = TPDDeviceGray.Instance;
  StrokingColorSpace := Gray;
  NonStrokingColorSpace := Gray;
  StrokingColor := Gray.InitialColor;
  NonStrokingColor := Gray.InitialColor;
  LineWidth := DefaultLineWidth;
  MiterLimit := DefaultMiterLimit;
  DashPattern := TPDLineDashPattern.Empty;
  Flatness := DefaultFlatness;
  BlendMode := TPdfBlendMode.Normal;
  AlphaConstant := OpaqueAlpha;
  NonStrokeAlphaConstant := OpaqueAlpha;
end;

function TPdfRenderGraphicsState.Clone: TPDGraphicsState;
begin
  const Copy = TPdfRenderGraphicsState.Create;
  CopyBaseTo(Copy);
  Copy.Clip := Clip;
  Copy.StrokingColor := StrokingColor;
  Copy.NonStrokingColor := NonStrokingColor;
  Copy.StrokingColorSpace := StrokingColorSpace;
  Copy.NonStrokingColorSpace := NonStrokingColorSpace;
  Copy.LineWidth := LineWidth;
  Copy.LineCap := LineCap;
  Copy.LineJoin := LineJoin;
  Copy.MiterLimit := MiterLimit;
  Copy.DashPattern := DashPattern;
  Copy.RenderingIntent := RenderingIntent;
  Copy.StrokeAdjustment := StrokeAdjustment;
  Copy.Flatness := Flatness;
  Copy.BlendMode := BlendMode;
  Copy.AlphaConstant := AlphaConstant;
  Copy.NonStrokeAlphaConstant := NonStrokeAlphaConstant;
  Copy.AlphaSource := AlphaSource;
  Copy.Transfer := Transfer;
  Copy.SoftMask := SoftMask;
  Result := Copy;
end;

function TPdfRenderGraphicsState.IntersectClip(const Path: TPdfPath; const PathToDevice: TPdfMatrix; const FillRule: TPdfFillRule;
                                               const MaxDepth: Integer): Boolean;
begin
  Clip := TPdfClipPath.Create(Clip, Path.Clone, PathToDevice, FillRule);
  Result := (Clip.Depth > Max(MaxDepth, 1));
  if Result then
  begin
    Clip := TPdfClipPath.Flattened(Clip);
  end;
end;

end.
