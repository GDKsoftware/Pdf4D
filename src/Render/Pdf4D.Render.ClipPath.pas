// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.ClipPath;

{$EXCESSPRECISION OFF}

interface

uses
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

    procedure ReleaseParents;

  public
    // Parent is nil for the first path. Takes ownership of Path.
    constructor Create(const Parent: IPdfClipPath; const Path: TPdfPath; const Transform: TPdfMatrix; const FillRule: TPdfFillRule);
    destructor Destroy; override;

    function Parent: IPdfClipPath;
    function Path: TPdfPath;
    function Transform: TPdfMatrix;
    function FillRule: TPdfFillRule;
  end;

implementation

{ TPdfClipPath }

constructor TPdfClipPath.Create(const Parent: IPdfClipPath; const Path: TPdfPath; const Transform: TPdfMatrix; const FillRule: TPdfFillRule);
begin
  inherited Create;
  FParent := Parent;
  FPath := Path;
  FTransform := Transform;
  FFillRule := FillRule;
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

end.
