// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.RecordingPainter;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  System.UITypes,
  System.Generics.Collections,
  Pdf4D.Render.Bitmap,
  Pdf4D.Viewer.Painter.Interfaces;

type
  {$SCOPEDENUMS ON}
  TPaintKind = (FillRect, DrawImage, FillPolygon, FramePolygon, FillEllipse, FrameEllipse, DrawText);
  {$SCOPEDENUMS OFF}

  // An image that remembers its size and nothing else
  TFakeImage = class(TInterfacedObject, IPdfViewImage)
  private
    FWidth: Integer;
    FHeight: Integer;

  public
    constructor Create(const Width, Height: Integer);

    function Width: Integer;
    function Height: Integer;
  end;

  TPaintCall = record
    Kind: TPaintKind;
    // FillRect, DrawImage (destination), the ellipses and DrawText
    Rect: TRectF;
    // DrawImage
    Source: TRect;
    Image: IPdfViewImage;
    // The polygons
    Points: TArray<TPointF>;
    Color: TAlphaColor;
    // FramePolygon and FrameEllipse
    Width: Single;
    Text: string;
  end;

  // Writes down every call, in order
  TRecordingPainter = class(TInterfacedObject, IPdfViewPainter)
  private
    FCalls: TList<TPaintCall>;

    procedure Add(const Call: TPaintCall);

  public
    constructor Create;
    destructor Destroy; override;

    procedure FillRect(const Rect: TRectF; const Color: TAlphaColor);
    procedure DrawImage(const Image: IPdfViewImage; const Source: TRect; const Dest: TRectF);
    procedure FillPolygon(const Points: TArray<TPointF>; const Color: TAlphaColor);
    procedure FramePolygon(const Points: TArray<TPointF>; const Color: TAlphaColor; const Width: Single);
    procedure FillEllipse(const Rect: TRectF; const Color: TAlphaColor);
    procedure FrameEllipse(const Rect: TRectF; const Color: TAlphaColor; const Width: Single);
    procedure DrawText(const Text: string; const Rect: TRectF; const Color: TAlphaColor);

    function Count(const Kind: TPaintKind): Integer;
    // The calls of one kind, in order
    function Of_(const Kind: TPaintKind): TArray<TPaintCall>;
    procedure Reset;

    property Calls: TList<TPaintCall> read FCalls;
  end;

  // Writes down what the controller asks of its host
  TRecordingHost = class(TInterfacedObject, IPdfViewHost)
  private
    FInvalidated: TList<TRect>;
    FScrollStateChanges: Integer;
    FCursorChanges: Integer;
    FImagesCreated: Integer;

  public
    constructor Create;
    destructor Destroy; override;

    procedure Invalidate(const Rect: TRect);
    procedure ScrollStateChanged;
    procedure CursorChanged;
    function CreateImage(const Bitmap: TPdfBitmap): IPdfViewImage;

    // True when one of the invalidated rectangles contains Rect
    function Covers(const Rect: TRect): Boolean;
    procedure Reset;

    property Invalidated: TList<TRect> read FInvalidated;
    property ScrollStateChanges: Integer read FScrollStateChanges;
    property CursorChanges: Integer read FCursorChanges;
    property ImagesCreated: Integer read FImagesCreated;
  end;

implementation

{ TFakeImage }

constructor TFakeImage.Create(const Width, Height: Integer);
begin
  inherited Create;
  FWidth := Width;
  FHeight := Height;
end;

function TFakeImage.Width: Integer;
begin
  Result := FWidth;
end;

function TFakeImage.Height: Integer;
begin
  Result := FHeight;
end;

{ TRecordingPainter }

constructor TRecordingPainter.Create;
begin
  inherited Create;
  FCalls := TList<TPaintCall>.Create;
end;

destructor TRecordingPainter.Destroy;
begin
  FCalls.Free;
  inherited;
end;

procedure TRecordingPainter.Add(const Call: TPaintCall);
begin
  FCalls.Add(Call);
end;

procedure TRecordingPainter.FillRect(const Rect: TRectF; const Color: TAlphaColor);
begin
  var Call: TPaintCall;
  Call.Kind := TPaintKind.FillRect;
  Call.Rect := Rect;
  Call.Color := Color;
  Add(Call);
end;

procedure TRecordingPainter.DrawImage(const Image: IPdfViewImage; const Source: TRect; const Dest: TRectF);
begin
  var Call: TPaintCall;
  Call.Kind := TPaintKind.DrawImage;
  Call.Image := Image;
  Call.Source := Source;
  Call.Rect := Dest;
  Add(Call);
end;

procedure TRecordingPainter.FillPolygon(const Points: TArray<TPointF>; const Color: TAlphaColor);
begin
  var Call: TPaintCall;
  Call.Kind := TPaintKind.FillPolygon;
  Call.Points := Copy(Points);
  Call.Color := Color;
  Add(Call);
end;

procedure TRecordingPainter.FramePolygon(const Points: TArray<TPointF>; const Color: TAlphaColor; const Width: Single);
begin
  var Call: TPaintCall;
  Call.Kind := TPaintKind.FramePolygon;
  Call.Points := Copy(Points);
  Call.Color := Color;
  Call.Width := Width;
  Add(Call);
end;

procedure TRecordingPainter.FillEllipse(const Rect: TRectF; const Color: TAlphaColor);
begin
  var Call: TPaintCall;
  Call.Kind := TPaintKind.FillEllipse;
  Call.Rect := Rect;
  Call.Color := Color;
  Add(Call);
end;

procedure TRecordingPainter.FrameEllipse(const Rect: TRectF; const Color: TAlphaColor; const Width: Single);
begin
  var Call: TPaintCall;
  Call.Kind := TPaintKind.FrameEllipse;
  Call.Rect := Rect;
  Call.Color := Color;
  Call.Width := Width;
  Add(Call);
end;

procedure TRecordingPainter.DrawText(const Text: string; const Rect: TRectF; const Color: TAlphaColor);
begin
  var Call: TPaintCall;
  Call.Kind := TPaintKind.DrawText;
  Call.Text := Text;
  Call.Rect := Rect;
  Call.Color := Color;
  Add(Call);
end;

function TRecordingPainter.Count(const Kind: TPaintKind): Integer;
begin
  Result := 0;
  for var Call in FCalls do
  begin
    if Call.Kind = Kind then
    begin
      Inc(Result);
    end;
  end;
end;

function TRecordingPainter.Of_(const Kind: TPaintKind): TArray<TPaintCall>;
begin
  const Found = TList<TPaintCall>.Create;
  try
    for var Call in FCalls do
    begin
      if Call.Kind = Kind then
      begin
        Found.Add(Call);
      end;
    end;
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

procedure TRecordingPainter.Reset;
begin
  FCalls.Clear;
end;

{ TRecordingHost }

constructor TRecordingHost.Create;
begin
  inherited Create;
  FInvalidated := TList<TRect>.Create;
end;

destructor TRecordingHost.Destroy;
begin
  FInvalidated.Free;
  inherited;
end;

procedure TRecordingHost.Invalidate(const Rect: TRect);
begin
  FInvalidated.Add(Rect);
end;

procedure TRecordingHost.ScrollStateChanged;
begin
  Inc(FScrollStateChanges);
end;

procedure TRecordingHost.CursorChanged;
begin
  Inc(FCursorChanges);
end;

function TRecordingHost.CreateImage(const Bitmap: TPdfBitmap): IPdfViewImage;
begin
  Inc(FImagesCreated);
  Result := TFakeImage.Create(Bitmap.Width, Bitmap.Height);
end;

function TRecordingHost.Covers(const Rect: TRect): Boolean;
begin
  Result := False;
  for var Invalidated in FInvalidated do
  begin
    if (Invalidated.Left <= Rect.Left) and (Invalidated.Top <= Rect.Top) and
       (Invalidated.Right >= Rect.Right) and (Invalidated.Bottom >= Rect.Bottom) then
    begin
      Exit(True);
    end;
  end;
end;

procedure TRecordingHost.Reset;
begin
  FInvalidated.Clear;
  FScrollStateChanges := 0;
  FCursorChanges := 0;
end;

end.
