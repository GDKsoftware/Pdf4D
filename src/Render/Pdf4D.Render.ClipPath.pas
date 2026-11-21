// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.ClipPath;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  Pdf4D.Common.Matrix,
  Pdf4D.Common.Path,
  Pdf4D.Render.Device.Interfaces;

type
  // The clip owns Path and keeps Parent alive, so a chain of clips frees itself from the last reference
  TPdfClipPath = class(TInterfacedObject, IPdfClipPath)
  private
    FParent: IPdfClipPath;
    FPath: TPdfPath;
    FTransform: TPdfMatrix;
    FFillRule: TPdfFillRule;
    FDepth: Integer;
    FBounds: TRectF;

    procedure ReleaseParents;

  public
    // Parent is nil for the first path. Takes ownership of Path.
    constructor Create(const Parent: IPdfClipPath; const Path: TPdfPath; const Transform: TPdfMatrix; const FillRule: TPdfFillRule);
    destructor Destroy; override;

    function Parent: IPdfClipPath;
    function Path: TPdfPath;
    function Transform: TPdfMatrix;
    function FillRule: TPdfFillRule;
    function Depth: Integer;
    function Bounds: TRectF;

    // A chain of one path: the rectangle of the bounds of Source, in device pixels. It stands in for a chain that has become too long,
    // and clips to what that chain would clip to at most (the shapes of its paths are lost). A bounds that is not finite gives an
    // empty rectangle.
    class function Flattened(const Source: IPdfClipPath): IPdfClipPath; static;
  end;

implementation

uses
  System.Math;

{ TPdfClipPath }

constructor TPdfClipPath.Create(const Parent: IPdfClipPath; const Path: TPdfPath; const Transform: TPdfMatrix; const FillRule: TPdfFillRule);
begin
  inherited Create;
  FParent := Parent;
  FPath := Path;
  FTransform := Transform;
  FFillRule := FillRule;
  FDepth := 1;

  const Shape = Path.Clone;
  try
    Shape.Transform(Transform);
    FBounds := Shape.Bounds;
  finally
    Shape.Free;
  end;

  if Assigned(Parent) then
  begin
    FDepth := Parent.Depth + 1;
    FBounds := TRectF.Intersect(Parent.Bounds, FBounds);
  end;
end;

class function TPdfClipPath.Flattened(const Source: IPdfClipPath): IPdfClipPath;
begin
  var Box := Source.Bounds;
  const IsFinite = ((not (IsNan(Box.Left) or IsInfinite(Box.Left) or IsNan(Box.Top) or IsInfinite(Box.Top))) and
                    (not (IsNan(Box.Right) or IsInfinite(Box.Right) or IsNan(Box.Bottom) or IsInfinite(Box.Bottom))));
  if not IsFinite then
  begin
    Box := TRectF.Create(0, 0, 0, 0);
  end;

  const Rectangle = TPdfPath.Create;
  try
    Rectangle.MoveTo(Box.Left, Box.Top);
    Rectangle.LineTo(Box.Right, Box.Top);
    Rectangle.LineTo(Box.Right, Box.Bottom);
    Rectangle.LineTo(Box.Left, Box.Bottom);
    Rectangle.ClosePath;
  except
    Rectangle.Free;
    raise;
  end;
  Result := TPdfClipPath.Create(nil, Rectangle, TPdfMatrix.Identity, TPdfFillRule.NonZero);
end;

destructor TPdfClipPath.Destroy;
begin
  ReleaseParents;
  FPath.Free;
  inherited;
end;

// Releasing the parent from the destructor would recurse once per link of a long chain. Instead every parent that nobody else holds
// is cut off from its own parent before it is released, so each destructor finds no parent left.
procedure TPdfClipPath.ReleaseParents;
begin
  var Link := FParent;
  FParent := nil;

  while Assigned(Link) do
  begin
    var Next: IPdfClipPath := nil;
    const Node = (Link as TObject);
    const IsOnlyHeldHere = ((Node is TPdfClipPath) and (TPdfClipPath(Node).RefCount = 1));
    if IsOnlyHeldHere then
    begin
      Next := TPdfClipPath(Node).FParent;
      TPdfClipPath(Node).FParent := nil;
    end;

    Link := Next;
  end;
end;

function TPdfClipPath.Parent: IPdfClipPath;
begin
  Result := FParent;
end;

function TPdfClipPath.Path: TPdfPath;
begin
  Result := FPath;
end;

function TPdfClipPath.Transform: TPdfMatrix;
begin
  Result := FTransform;
end;

function TPdfClipPath.FillRule: TPdfFillRule;
begin
  Result := FFillRule;
end;

function TPdfClipPath.Depth: Integer;
begin
  Result := FDepth;
end;

function TPdfClipPath.Bounds: TRectF;
begin
  Result := FBounds;
end;

end.
