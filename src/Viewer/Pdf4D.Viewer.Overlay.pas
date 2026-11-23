// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.Overlay;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.UITypes,
  System.Generics.Collections,
  Pdf4D.Common.Quad,
  Pdf4D.Viewer.Types;

type
  // The overlays of one document: shapes in PDF user space that the views draw over a page. UI thread only.
  TPdfOverlayList = class
  private
    FItems: TList<TPdfOverlay>;
    FNextId: Integer;
    FIsOpen: TFunc<Boolean>;
    FPageCount: TFunc<Integer>;
    FOnChanged: TProc;

    procedure CheckCanAdd(const PageIndex: Integer; const Quads: TArray<TPdfQuad>);
    procedure Changed;

  public
    // IsOpen and PageCount tell what the document is now; OnChanged is called after Add, Remove and Clear changed the list
    constructor Create(const IsOpen: TFunc<Boolean>; const PageCount: TFunc<Integer>; const OnChanged: TProc);
    destructor Destroy; override;

    // Raises EInvalidOpException when the document is not Open, EArgumentOutOfRangeException for a page outside it and
    // EArgumentException for no quads or a quad that is not finite
    function Add(const PageIndex: Integer; const Quads: TArray<TPdfQuad>; const Style: TPdfOverlayStyle; const Color: TAlphaColor): Integer;
    // An unknown Id does nothing
    procedure Remove(const Id: Integer);
    procedure Clear;
    function Items: TArray<TPdfOverlay>;
    function OnPage(const PageIndex: Integer): TArray<TPdfOverlay>;
  end;

implementation

uses
  Pdf4D.Viewer.ResourceStrings;

{ TPdfOverlayList }

constructor TPdfOverlayList.Create(const IsOpen: TFunc<Boolean>; const PageCount: TFunc<Integer>; const OnChanged: TProc);
begin
  inherited Create;
  FItems := TList<TPdfOverlay>.Create;
  FNextId := 1;
  FIsOpen := IsOpen;
  FPageCount := PageCount;
  FOnChanged := OnChanged;
end;

destructor TPdfOverlayList.Destroy;
begin
  FItems.Free;
  inherited;
end;

function TPdfOverlayList.Add(const PageIndex: Integer; const Quads: TArray<TPdfQuad>; const Style: TPdfOverlayStyle;
                             const Color: TAlphaColor): Integer;
begin
  CheckCanAdd(PageIndex, Quads);

  var Overlay: TPdfOverlay;
  Overlay.Id := FNextId;
  Overlay.PageIndex := PageIndex;
  Overlay.Quads := Copy(Quads);
  Overlay.Style := Style;
  Overlay.Color := Color;
  Inc(FNextId);
  FItems.Add(Overlay);
  Result := Overlay.Id;

  Changed;
end;

procedure TPdfOverlayList.CheckCanAdd(const PageIndex: Integer; const Quads: TArray<TPdfQuad>);
begin
  if not FIsOpen() then
  begin
    raise EInvalidOpException.Create(SOverlayWhileNotOpen);
  end;

  if (PageIndex < 0) or (PageIndex >= FPageCount()) then
  begin
    raise EArgumentOutOfRangeException.CreateFmt(SOverlayPageOutside, [PageIndex]);
  end;

  if Length(Quads) = 0 then
  begin
    raise EArgumentException.Create(SOverlayNoQuads);
  end;

  for var Quad in Quads do
  begin
    if not Quad.IsFinite then
    begin
      raise EArgumentException.Create(SOverlayQuadNotFinite);
    end;
  end;
end;

procedure TPdfOverlayList.Remove(const Id: Integer);
begin
  for var Index := 0 to FItems.Count - 1 do
  begin
    if FItems[Index].Id = Id then
    begin
      FItems.Delete(Index);
      Changed;
      Exit;
    end;
  end;
end;

procedure TPdfOverlayList.Clear;
begin
  if FItems.Count = 0 then
  begin
    Exit;
  end;

  FItems.Clear;
  Changed;
end;

function TPdfOverlayList.Items: TArray<TPdfOverlay>;
begin
  Result := FItems.ToArray;
end;

function TPdfOverlayList.OnPage(const PageIndex: Integer): TArray<TPdfOverlay>;
begin
  Result := nil;
  for var Overlay in FItems do
  begin
    if Overlay.PageIndex = PageIndex then
    begin
      Result := Result + [Overlay];
    end;
  end;
end;

procedure TPdfOverlayList.Changed;
begin
  if Assigned(FOnChanged) then
  begin
    FOnChanged();
  end;
end;

end.
