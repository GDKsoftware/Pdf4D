// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.FmxBitmapPrintTarget;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.Types,
  System.SysUtils,
  System.Generics.Collections,
  FMX.Graphics,
  Pdf4D.Render.Bitmap,
  Pdf4D.Viewer.Print,
  Pdf4D.FMX.PrintDialog;

type
  // A print target that needs no printer: a page is a white bitmap of the printable size, drawn with the code of the printer target, and
  // EndDocument writes the pages as PNG files
  TFmxBitmapPrintTarget = class(TInterfacedObject, IPdfPrintTarget)
  private
    FPrintable: TSize;
    FDpi: TPointF;
    FFolder: string;
    FPages: TObjectList<TBitmap>;
    FDrawBandCount: Integer;
    FIsBegun: Boolean;
    FIsEnded: Boolean;
    FIsAborted: Boolean;
    FCopies: Integer;
    FTitle: string;
    FLastDest: TRect;
    FDrawDelayMs: Integer;

  public
    // Folder may be empty: no files are written then
    constructor Create(const Printable: TSize; const Dpi: TPointF; const Folder: string);
    destructor Destroy; override;

    function PrintableSize: TSize;
    function Dpi: TPointF;
    procedure BeginDocument(const Title: string; const Copies: Integer);
    procedure BeginPage;
    procedure DrawBand(const Band: TPdfBitmap; const Dest: TRect);
    procedure EndDocument;
    procedure AbortDocument;

    property Pages: TObjectList<TBitmap> read FPages;
    property DrawBandCount: Integer read FDrawBandCount;
    property IsBegun: Boolean read FIsBegun;
    property IsEnded: Boolean read FIsEnded;
    property IsAborted: Boolean read FIsAborted;
    property Copies: Integer read FCopies;
    property Title: string read FTitle;
    // The destination of the last band; it may reach outside the printable area
    property LastDest: TRect read FLastDest;
    // Waits this long in every DrawBand, to make a job last
    property DrawDelayMs: Integer read FDrawDelayMs write FDrawDelayMs;
  end;

  // A print dialog that prints on a bitmap target instead of a printer
  TFmxBitmapPrintDialog = class(TPdf4DPrintDialog)
  private
    FPrintable: TSize;
    FDpi: TPointF;
    FFolder: string;
    FDrawDelayMs: Integer;
    FTarget: TFmxBitmapPrintTarget;
    FTargetReference: IPdfPrintTarget;

  protected
    function CreateTarget: IPdfPrintTarget; override;

  public
    constructor Create(Owner: TComponent); override;

    property Printable: TSize read FPrintable write FPrintable;
    property PrinterDpi: TPointF read FDpi write FDpi;
    property Folder: string read FFolder write FFolder;
    property DrawDelayMs: Integer read FDrawDelayMs write FDrawDelayMs;
    // The target of the last job; it is alive as long as the dialog is
    property Target: TFmxBitmapPrintTarget read FTarget;
  end;

implementation

uses
  System.IOUtils,
  System.UITypes,
  Pdf4D.FMX.Print;

{ TFmxBitmapPrintTarget }

constructor TFmxBitmapPrintTarget.Create(const Printable: TSize; const Dpi: TPointF; const Folder: string);
begin
  inherited Create;
  FPrintable := Printable;
  FDpi := Dpi;
  FFolder := Folder;
  FPages := TObjectList<TBitmap>.Create(True);
end;

destructor TFmxBitmapPrintTarget.Destroy;
begin
  FPages.Free;
  inherited;
end;

function TFmxBitmapPrintTarget.PrintableSize: TSize;
begin
  Result := FPrintable;
end;

function TFmxBitmapPrintTarget.Dpi: TPointF;
begin
  Result := FDpi;
end;

procedure TFmxBitmapPrintTarget.BeginDocument(const Title: string; const Copies: Integer);
begin
  FIsBegun := True;
  FTitle := Title;
  FCopies := Copies;
end;

procedure TFmxBitmapPrintTarget.BeginPage;
begin
  const Page = TBitmap.Create(FPrintable.cx, FPrintable.cy);
  try
    if Page.Canvas.BeginScene then
    begin
      try
        Page.Canvas.Clear(TAlphaColors.White);
      finally
        Page.Canvas.EndScene;
      end;
    end;
    FPages.Add(Page);
  except
    Page.Free;
    raise;
  end;
end;

procedure TFmxBitmapPrintTarget.DrawBand(const Band: TPdfBitmap; const Dest: TRect);
begin
  Inc(FDrawBandCount);
  if FDrawDelayMs > 0 then
  begin
    TThread.Sleep(FDrawDelayMs);
  end;
  FLastDest := Dest;
  TPdfFmxBandDrawer.Draw(FPages.Last.Canvas, Band, Dest, TRect.Create(0, 0, FPrintable.cx, FPrintable.cy));
end;

procedure TFmxBitmapPrintTarget.EndDocument;
begin
  FIsEnded := True;
  if FFolder = '' then
  begin
    Exit;
  end;

  ForceDirectories(FFolder);
  for var Index := 0 to FPages.Count - 1 do
  begin
    FPages[Index].SaveToFile(TPath.Combine(FFolder, Format('page-%d.png', [Index + 1])));
  end;
end;

procedure TFmxBitmapPrintTarget.AbortDocument;
begin
  FIsAborted := True;
end;

{ TFmxBitmapPrintDialog }

constructor TFmxBitmapPrintDialog.Create(Owner: TComponent);
begin
  inherited Create(Owner);
  // Letter paper at 150 dpi
  FPrintable := TSize.Create(1275, 1650);
  FDpi := TPointF.Create(150, 150);
  ShowProgress := False;
end;

function TFmxBitmapPrintDialog.CreateTarget: IPdfPrintTarget;
begin
  FTarget := TFmxBitmapPrintTarget.Create(FPrintable, FDpi, FFolder);
  FTarget.DrawDelayMs := FDrawDelayMs;
  FTargetReference := FTarget;
  Result := FTargetReference;
end;

end.
