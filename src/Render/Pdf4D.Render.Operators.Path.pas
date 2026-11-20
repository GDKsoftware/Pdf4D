// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/contentstream/operator/graphics/*.java (3.0.8)
unit Pdf4D.Render.Operators.Path;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Content.Operator,
  Pdf4D.Content.Operators.DrawObject,
  Pdf4D.Cos.Base,
  Pdf4D.Render.GraphicsEngine;

type
  // re
  TAppendRectangleToPathOperator = class(TGraphicsOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // W
  TClipNonZeroRuleOperator = class(TGraphicsOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // W*
  TClipEvenOddRuleOperator = class(TGraphicsOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // s
  TCloseAndStrokePathOperator = class(TGraphicsOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // b
  TCloseFillNonZeroAndStrokePathOperator = class(TGraphicsOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // b*
  TCloseFillEvenOddAndStrokePathOperator = class(TGraphicsOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // h
  TClosePathOperator = class(TGraphicsOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // c
  TCurveToOperator = class(TGraphicsOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // y
  TCurveToReplicateFinalPointOperator = class(TGraphicsOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // v
  TCurveToReplicateInitialPointOperator = class(TGraphicsOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // Do. Forms are run as the core operator does; images are logged and skipped until they are drawn.
  TDrawObjectGraphicsOperator = class(TDrawObjectOperator)
  public
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // n
  TEndPathOperator = class(TGraphicsOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // B*
  TFillEvenOddAndStrokePathOperator = class(TGraphicsOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // f*
  TFillEvenOddRuleOperator = class(TGraphicsOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // B
  TFillNonZeroAndStrokePathOperator = class(TGraphicsOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // f
  TFillNonZeroRuleOperator = class(TGraphicsOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // F, the same as f
  TLegacyFillNonZeroRuleOperator = class(TFillNonZeroRuleOperator)
  public
    function Name: string; override;
  end;

  // l
  TLineToOperator = class(TGraphicsOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // m
  TMoveToOperator = class(TGraphicsOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // S
  TStrokePathOperator = class(TGraphicsOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // sh. Checks its operand and logs; the shading is not painted yet.
  TShadingFillOperator = class(TGraphicsOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  // BI. Logs; the inline image is not drawn yet.
  TBeginInlineImageOperator = class(TGraphicsOperatorProcessor)
  public
    function Name: string; override;
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
  end;

  TPathOperators = record
    // The path construction, painting and clipping operators, Do and the inline image and shading operators
    class procedure Register(const Engine: TPdfGraphicsEngine); static;
  end;

implementation

uses
  System.Types,
  Pdf4D.Content.OperatorProcessor,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Number,
  Pdf4D.Render.Device.Interfaces;

resourcestring
  WithoutMoveTo = '%s (%g, %g) without initial MoveTo';
  CloseWithoutMoveTo = 'ClosePath without initial MoveTo';
  ImageNotSupported = 'Drawing images is not supported yet: Do for an image is skipped';
  InlineImageNotSupported = 'Drawing inline images is not supported yet: BI is skipped';
  ShadingNameMissing = 'Operator %s needs a shading name';
  ShadingNotSupported = 'Painting shadings is not supported yet: sh is skipped';

const
  RectangleOperands = 4;
  CurveOperands = 6;
  ShortCurveOperands = 4;
  PointOperands = 2;

{ TPathOperators }

class procedure TPathOperators.Register(const Engine: TPdfGraphicsEngine);
begin
  Engine.AddOperator(TAppendRectangleToPathOperator.Create(Engine));
  Engine.AddOperator(TClipNonZeroRuleOperator.Create(Engine));
  Engine.AddOperator(TClipEvenOddRuleOperator.Create(Engine));
  Engine.AddOperator(TCloseAndStrokePathOperator.Create(Engine));
  Engine.AddOperator(TCloseFillNonZeroAndStrokePathOperator.Create(Engine));
  Engine.AddOperator(TCloseFillEvenOddAndStrokePathOperator.Create(Engine));
  Engine.AddOperator(TClosePathOperator.Create(Engine));
  Engine.AddOperator(TCurveToOperator.Create(Engine));
  Engine.AddOperator(TCurveToReplicateFinalPointOperator.Create(Engine));
  Engine.AddOperator(TCurveToReplicateInitialPointOperator.Create(Engine));
  Engine.AddOperator(TDrawObjectGraphicsOperator.Create(Engine));
  Engine.AddOperator(TEndPathOperator.Create(Engine));
  Engine.AddOperator(TFillEvenOddAndStrokePathOperator.Create(Engine));
  Engine.AddOperator(TFillEvenOddRuleOperator.Create(Engine));
  Engine.AddOperator(TFillNonZeroAndStrokePathOperator.Create(Engine));
  Engine.AddOperator(TFillNonZeroRuleOperator.Create(Engine));
  Engine.AddOperator(TLegacyFillNonZeroRuleOperator.Create(Engine));
  Engine.AddOperator(TLineToOperator.Create(Engine));
  Engine.AddOperator(TMoveToOperator.Create(Engine));
  Engine.AddOperator(TStrokePathOperator.Create(Engine));
  Engine.AddOperator(TShadingFillOperator.Create(Engine));
  Engine.AddOperator(TBeginInlineImageOperator.Create(Engine));
end;

{ TAppendRectangleToPathOperator }

function TAppendRectangleToPathOperator.Name: string;
begin
  Result := TOperatorNames.AppendRect;
end;

procedure TAppendRectangleToPathOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  RequireOperands(Operator, Operands, RectangleOperands);
  if not CheckArrayTypes(Operands, TCosNumber) then
  begin
    Exit;
  end;

  const Left = NumberAt(Operands, 0);
  const Bottom = NumberAt(Operands, 1);
  const Right = NumberAt(Operands, 2) + Left;
  const Top = NumberAt(Operands, 3) + Bottom;

  var P0, P1, P2, P3: TPointF;
  const AllFinite = (TryTransformPoint(Operator, Left, Bottom, P0) and
                     TryTransformPoint(Operator, Right, Bottom, P1) and
                     TryTransformPoint(Operator, Right, Top, P2) and
                     TryTransformPoint(Operator, Left, Top, P3));
  if AllFinite then
  begin
    GraphicsEngine.AppendRectangle(P0, P1, P2, P3);
  end;
end;

{ TClipNonZeroRuleOperator }

function TClipNonZeroRuleOperator.Name: string;
begin
  Result := TOperatorNames.ClipNonZero;
end;

procedure TClipNonZeroRuleOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  GraphicsEngine.Clip(TPdfFillRule.NonZero);
end;

{ TClipEvenOddRuleOperator }

function TClipEvenOddRuleOperator.Name: string;
begin
  Result := TOperatorNames.ClipEvenOdd;
end;

procedure TClipEvenOddRuleOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  GraphicsEngine.Clip(TPdfFillRule.EvenOdd);
end;

{ TCloseAndStrokePathOperator }

function TCloseAndStrokePathOperator.Name: string;
begin
  Result := TOperatorNames.CloseAndStroke;
end;

procedure TCloseAndStrokePathOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  Engine.ProcessOperator(TOperatorNames.ClosePath, Operands);
  Engine.ProcessOperator(TOperatorNames.StrokePath, Operands);
end;

{ TCloseFillNonZeroAndStrokePathOperator }

function TCloseFillNonZeroAndStrokePathOperator.Name: string;
begin
  Result := TOperatorNames.CloseFillNonZeroAndStroke;
end;

procedure TCloseFillNonZeroAndStrokePathOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  Engine.ProcessOperator(TOperatorNames.ClosePath, Operands);
  Engine.ProcessOperator(TOperatorNames.FillNonZeroAndStroke, Operands);
end;

{ TCloseFillEvenOddAndStrokePathOperator }

function TCloseFillEvenOddAndStrokePathOperator.Name: string;
begin
  Result := TOperatorNames.CloseFillEvenOddAndStroke;
end;

procedure TCloseFillEvenOddAndStrokePathOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  Engine.ProcessOperator(TOperatorNames.ClosePath, Operands);
  Engine.ProcessOperator(TOperatorNames.FillEvenOddAndStroke, Operands);
end;

{ TClosePathOperator }

function TClosePathOperator.Name: string;
begin
  Result := TOperatorNames.ClosePath;
end;

procedure TClosePathOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  var CurrentPoint: TPointF;
  const HasCurrentPoint = GraphicsEngine.TryGetCurrentPoint(CurrentPoint);
  if not HasCurrentPoint then
  begin
    Engine.LogWarning(CloseWithoutMoveTo, []);
    Exit;
  end;

  GraphicsEngine.ClosePath;
end;

{ TCurveToOperator }

function TCurveToOperator.Name: string;
begin
  Result := TOperatorNames.CurveTo;
end;

procedure TCurveToOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  RequireOperands(Operator, Operands, CurveOperands);
  if not CheckArrayTypes(Operands, TCosNumber) then
  begin
    Exit;
  end;

  var Point1, Point2, Point3: TPointF;
  const AllFinite = (TryTransformPoint(Operator, NumberAt(Operands, 0), NumberAt(Operands, 1), Point1) and
                     TryTransformPoint(Operator, NumberAt(Operands, 2), NumberAt(Operands, 3), Point2) and
                     TryTransformPoint(Operator, NumberAt(Operands, 4), NumberAt(Operands, 5), Point3));
  if not AllFinite then
  begin
    Exit;
  end;

  var CurrentPoint: TPointF;
  const HasCurrentPoint = GraphicsEngine.TryGetCurrentPoint(CurrentPoint);
  if HasCurrentPoint then
  begin
    GraphicsEngine.CurveTo(Point1.X, Point1.Y, Point2.X, Point2.Y, Point3.X, Point3.Y);
  end
  else
  begin
    Engine.LogWarning(WithoutMoveTo, ['curveTo', Point3.X, Point3.Y]);
    GraphicsEngine.MoveTo(Point3.X, Point3.Y);
  end;
end;

{ TCurveToReplicateFinalPointOperator }

function TCurveToReplicateFinalPointOperator.Name: string;
begin
  Result := TOperatorNames.CurveToReplicateFinalPoint;
end;

procedure TCurveToReplicateFinalPointOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  RequireOperands(Operator, Operands, ShortCurveOperands);
  if not CheckArrayTypes(Operands, TCosNumber) then
  begin
    Exit;
  end;

  var Point1, Point3: TPointF;
  const AllFinite = (TryTransformPoint(Operator, NumberAt(Operands, 0), NumberAt(Operands, 1), Point1) and
                     TryTransformPoint(Operator, NumberAt(Operands, 2), NumberAt(Operands, 3), Point3));
  if not AllFinite then
  begin
    Exit;
  end;

  var CurrentPoint: TPointF;
  const HasCurrentPoint = GraphicsEngine.TryGetCurrentPoint(CurrentPoint);
  if HasCurrentPoint then
  begin
    GraphicsEngine.CurveTo(Point1.X, Point1.Y, Point3.X, Point3.Y, Point3.X, Point3.Y);
  end
  else
  begin
    Engine.LogWarning(WithoutMoveTo, ['curveTo', Point3.X, Point3.Y]);
    GraphicsEngine.MoveTo(Point3.X, Point3.Y);
  end;
end;

{ TCurveToReplicateInitialPointOperator }

function TCurveToReplicateInitialPointOperator.Name: string;
begin
  Result := TOperatorNames.CurveToReplicateInitialPoint;
end;

procedure TCurveToReplicateInitialPointOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  RequireOperands(Operator, Operands, ShortCurveOperands);
  if not CheckArrayTypes(Operands, TCosNumber) then
  begin
    Exit;
  end;

  var Point2, Point3: TPointF;
  const AllFinite = (TryTransformPoint(Operator, NumberAt(Operands, 0), NumberAt(Operands, 1), Point2) and
                     TryTransformPoint(Operator, NumberAt(Operands, 2), NumberAt(Operands, 3), Point3));
  if not AllFinite then
  begin
    Exit;
  end;

  var CurrentPoint: TPointF;
  const HasCurrentPoint = GraphicsEngine.TryGetCurrentPoint(CurrentPoint);
  if HasCurrentPoint then
  begin
    GraphicsEngine.CurveTo(CurrentPoint.X, CurrentPoint.Y, Point2.X, Point2.Y, Point3.X, Point3.Y);
  end
  else
  begin
    Engine.LogWarning(WithoutMoveTo, ['curveTo', Point3.X, Point3.Y]);
    GraphicsEngine.MoveTo(Point3.X, Point3.Y);
  end;
end;

{ TDrawObjectGraphicsOperator }

procedure TDrawObjectGraphicsOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  const IsImage = ((Length(Operands) > 0) and (Operands[0] is TCosName) and Engine.Resources.IsImageXObject(TCosName(Operands[0]).Name));
  if IsImage then
  begin
    Engine.LogWarning(ImageNotSupported, []);
    Exit;
  end;

  inherited Process(Operator, Operands);
end;

{ TEndPathOperator }

function TEndPathOperator.Name: string;
begin
  Result := TOperatorNames.EndPath;
end;

procedure TEndPathOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  GraphicsEngine.EndPath;
end;

{ TFillEvenOddAndStrokePathOperator }

function TFillEvenOddAndStrokePathOperator.Name: string;
begin
  Result := TOperatorNames.FillEvenOddAndStroke;
end;

procedure TFillEvenOddAndStrokePathOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  GraphicsEngine.FillAndStrokePath(TPdfFillRule.EvenOdd);
end;

{ TFillEvenOddRuleOperator }

function TFillEvenOddRuleOperator.Name: string;
begin
  Result := TOperatorNames.FillEvenOdd;
end;

procedure TFillEvenOddRuleOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  GraphicsEngine.FillPath(TPdfFillRule.EvenOdd);
end;

{ TFillNonZeroAndStrokePathOperator }

function TFillNonZeroAndStrokePathOperator.Name: string;
begin
  Result := TOperatorNames.FillNonZeroAndStroke;
end;

procedure TFillNonZeroAndStrokePathOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  GraphicsEngine.FillAndStrokePath(TPdfFillRule.NonZero);
end;

{ TFillNonZeroRuleOperator }

function TFillNonZeroRuleOperator.Name: string;
begin
  Result := TOperatorNames.FillNonZero;
end;

procedure TFillNonZeroRuleOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  GraphicsEngine.FillPath(TPdfFillRule.NonZero);
end;

{ TLegacyFillNonZeroRuleOperator }

function TLegacyFillNonZeroRuleOperator.Name: string;
begin
  Result := TOperatorNames.LegacyFillNonZero;
end;

{ TLineToOperator }

function TLineToOperator.Name: string;
begin
  Result := TOperatorNames.LineTo;
end;

procedure TLineToOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  RequireOperands(Operator, Operands, PointOperands);
  const AreNumbers = ((Operands[0] is TCosNumber) and (Operands[1] is TCosNumber));
  if not AreNumbers then
  begin
    Exit;
  end;

  var Position: TPointF;
  if not TryTransformPoint(Operator, NumberAt(Operands, 0), NumberAt(Operands, 1), Position) then
  begin
    Exit;
  end;

  var CurrentPoint: TPointF;
  const HasCurrentPoint = GraphicsEngine.TryGetCurrentPoint(CurrentPoint);
  if HasCurrentPoint then
  begin
    GraphicsEngine.LineTo(Position.X, Position.Y);
  end
  else
  begin
    Engine.LogWarning(WithoutMoveTo, ['LineTo', Position.X, Position.Y]);
    GraphicsEngine.MoveTo(Position.X, Position.Y);
  end;
end;

{ TMoveToOperator }

function TMoveToOperator.Name: string;
begin
  Result := TOperatorNames.MoveTo;
end;

procedure TMoveToOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  RequireOperands(Operator, Operands, PointOperands);
  const AreNumbers = ((Operands[0] is TCosNumber) and (Operands[1] is TCosNumber));
  if not AreNumbers then
  begin
    Exit;
  end;

  var Position: TPointF;
  if TryTransformPoint(Operator, NumberAt(Operands, 0), NumberAt(Operands, 1), Position) then
  begin
    GraphicsEngine.MoveTo(Position.X, Position.Y);
  end;
end;

{ TStrokePathOperator }

function TStrokePathOperator.Name: string;
begin
  Result := TOperatorNames.StrokePath;
end;

procedure TStrokePathOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  GraphicsEngine.StrokePath;
end;

{ TShadingFillOperator }

function TShadingFillOperator.Name: string;
begin
  Result := TOperatorNames.ShadingFill;
end;

procedure TShadingFillOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  const HasName = ((Length(Operands) > 0) and (Operands[0] is TCosName));
  if not HasName then
  begin
    raise EPdfMissingOperandException.CreateFmt(ShadingNameMissing, [Operator.Name]);
  end;

  Engine.LogWarning(ShadingNotSupported, []);
end;

{ TBeginInlineImageOperator }

function TBeginInlineImageOperator.Name: string;
begin
  Result := TOperatorNames.BeginInlineImage;
end;

procedure TBeginInlineImageOperator.Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  const HasImageData = (Length(Operator.ImageData) > 0);
  if HasImageData then
  begin
    Engine.LogWarning(InlineImageNotSupported, []);
  end;
end;

end.
