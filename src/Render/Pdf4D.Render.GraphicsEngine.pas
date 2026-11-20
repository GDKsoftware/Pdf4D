// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/contentstream/PDFGraphicsStreamEngine.java (3.0.8)
// Port of: pdfbox/src/main/java/org/apache/pdfbox/contentstream/PDFStreamEngine.java (3.0.8), transformedPoint
unit Pdf4D.Render.GraphicsEngine;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  System.SysUtils,
  Pdf4D.Content.GraphicsState,
  Pdf4D.Content.Operator,
  Pdf4D.Content.OperatorProcessor,
  Pdf4D.Content.StreamEngine,
  Pdf4D.Cos.Base,
  Pdf4D.Graphics.State,
  Pdf4D.Model.Page,
  Pdf4D.Render.Device.Interfaces;

type
  // A stream engine that reports what a page draws: the path construction, painting and clipping operators call the abstract methods
  // below, with points that the current transformation matrix has been applied to. A subclass paints or collects. The engine
  // registers the text, marked content, path, colour and state operators; the text operators show their glyphs through ShowGlyph.
  TPdfGraphicsEngine = class abstract(TPdfStreamEngine)
  protected
    // A TPdfRenderGraphicsState
    function CreateInitialGraphicsState(const Page: TPDPage): TPDGraphicsState; override;

  public
    constructor Create;

    // The graphics state at the top of the stack as the state of the renderer
    function RenderState: TPdfRenderGraphicsState;

    // PDFStreamEngine.transformedPoint: the point after the CTM. False when the result is not a finite number (a CTM with huge
    // values), where Java would go on with an infinity or NaN.
    function TryTransformPoint(const X, Y: Single; out Point: TPointF): Boolean;

    // The corners in the order of the re operator: lower left, lower right, upper right, upper left
    procedure AppendRectangle(const P0, P1, P2, P3: TPointF); virtual; abstract;
    // procedure DrawImage(const Image: TPDImage); virtual; abstract; is added together with TPDImage
    procedure Clip(const FillRule: TPdfFillRule); virtual; abstract;
    procedure MoveTo(const X, Y: Single); virtual; abstract;
    procedure LineTo(const X, Y: Single); virtual; abstract;
    procedure CurveTo(const X1, Y1, X2, Y2, X3, Y3: Single); virtual; abstract;
    // False when the path has no current point
    function TryGetCurrentPoint(out Point: TPointF): Boolean; virtual; abstract;
    procedure ClosePath; virtual; abstract;
    procedure EndPath; virtual; abstract;
    procedure StrokePath; virtual; abstract;
    procedure FillPath(const FillRule: TPdfFillRule); virtual; abstract;
    procedure FillAndStrokePath(const FillRule: TPdfFillRule); virtual; abstract;
    procedure ShadingFill(const ShadingName: string); virtual; abstract;
  end;

  // The base of the processors that need the graphics engine and not just the stream engine
  TGraphicsOperatorProcessor = class abstract(TOperatorProcessor)
  private
    function GetGraphicsEngine: TPdfGraphicsEngine;

  protected
    // The point after the CTM; logs and gives False for coordinates that do not end up as a finite number
    function TryTransformPoint(const Operator: TContentOperator; const X, Y: Single; out Point: TPointF): Boolean;
    // The value of operand Index, which the caller has checked to be a number
    class function NumberAt(const Operands: TArray<TCosBase>; const Index: Integer): Single; static;

    property GraphicsEngine: TPdfGraphicsEngine read GetGraphicsEngine;
  end;

implementation

uses
  System.Math,
  Pdf4D.Content.Operators.MarkedContent,
  Pdf4D.Content.Operators.Text,
  Pdf4D.Cos.Number,
  Pdf4D.Render.Operators.Color,
  Pdf4D.Render.Operators.Path,
  Pdf4D.Render.Operators.State;

{ TPdfGraphicsEngine }

constructor TPdfGraphicsEngine.Create;
begin
  inherited Create;
  TTextOperators.Register(Self);
  TMarkedContentOperators.Register(Self);
  TPathOperators.Register(Self);
  TColorOperators.Register(Self);
  TRenderStateOperators.Register(Self);
end;

function TPdfGraphicsEngine.CreateInitialGraphicsState(const Page: TPDPage): TPDGraphicsState;
begin
  Result := TPdfRenderGraphicsState.Create;
end;

function TPdfGraphicsEngine.RenderState: TPdfRenderGraphicsState;
begin
  Result := TPdfRenderGraphicsState(GraphicsState);
end;

function TPdfGraphicsEngine.TryTransformPoint(const X, Y: Single; out Point: TPointF): Boolean;
begin
  Point := GraphicsState.CurrentTransformationMatrix.TransformPoint(X, Y);
  Result := (not (IsNan(Point.X) or IsInfinite(Point.X) or IsNan(Point.Y) or IsInfinite(Point.Y)));
end;

{ TGraphicsOperatorProcessor }

function TGraphicsOperatorProcessor.GetGraphicsEngine: TPdfGraphicsEngine;
begin
  Result := (Engine as TPdfGraphicsEngine);
end;

class function TGraphicsOperatorProcessor.NumberAt(const Operands: TArray<TCosBase>; const Index: Integer): Single;
begin
  Result := TCosNumber(Operands[Index]).FloatValue;
end;

function TGraphicsOperatorProcessor.TryTransformPoint(const Operator: TContentOperator; const X, Y: Single; out Point: TPointF): Boolean;
begin
  Result := GraphicsEngine.TryTransformPoint(X, Y, Point);
  if not Result then
  begin
    Engine.LogError('Operator %s skipped: the point (%g, %g) does not give a finite coordinate', [Operator.Name, X, Y]);
  end;
end;

end.
