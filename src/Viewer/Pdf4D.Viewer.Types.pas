// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.Types;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.UITypes,
  Pdf4D.Common.Defines,
  Pdf4D.Common.Quad,
  Pdf4D.Model.Rectangle,
  Pdf4D.Api.Page.Interfaces,
  Pdf4D.Api.TextLayout.Interfaces;

const
  MinZoom: Single = 0.1;
  MaxZoom: Single = 8;
  // The steps of ZoomIn and ZoomOut, and the percentages of a zoom list
  PdfZoomSteps: array[0..11] of Integer = (10, 25, 50, 75, 100, 125, 150, 200, 300, 400, 600, 800);
  PercentPerFactor = 100;
  // The largest side of a page in pixels; a zoom that would make a page larger is clamped
  MaxPageEdgePixels = 100000;
  // Logical pixels (at 96 dpi) between pages and around them
  PageGap = 8;
  DefaultTileCacheBytes: Int64 = 128 * 1024 * 1024;
  DefaultThumbnailCacheBytes: Int64 = 32 * 1024 * 1024;
  // Pages per document
  DefaultPageTextCacheCount = 64;
  // Search hits per document; a search that finds more stops there
  DefaultMaxSearchHits = 10000;
  // The most pixels of one render of the missing tiles of a page; a larger batch is split in bands
  MaxTileBatchPixels: Int64 = 8 * 1024 * 1024;
  // Printing renders at most this many dots per inch, in bands of at most this many pixels
  DefaultMaxPrintDpi = 300;
  DefaultMaxBandPixels: Int64 = 8 * 1024 * 1024;

type
  {$SCOPEDENUMS ON}
  TPdfDocumentState = (Closed, Opening, Open, Failed);
  TPdfOpenErrorKind = (InvalidPassword, FileError, ParseError, LimitExceeded, Other);
  TPdfZoomMode = (Factor, FitWidth, FitPage);
  TPdfScrollMode = (Continuous, SinglePage);
  TPdfOverlayStyle = (Fill, Frame, Ellipse);
  TPdfSelectionKind = (Click, Drag);
  // The first value is the most urgent
  TPdfJobPriority = (Open, Print, Visible, PageText, Prefetch, Thumbnail, Search);
  TPdfDocumentChange = (Opening, Opened, OpenFailed, Closed, CurrentPage, Overlays, SearchResults, CurrentSearchHit);
  TPdfCursorKind = (Default, Text, Link);
  TPdfViewerKey = (Up, Down, Left, Right, PageUp, PageDown, Home, End_, ZoomIn, ZoomOut, ZoomReset, SelectAll);
  {$SCOPEDENUMS OFF}

  // A programming or configuration error, such as a command that the framework runs
  EPdfViewerException = class(Exception);

  TPdfPageInfo = record
    CropBox: TPdfRectangle;
    // /Rotate normalised to 0, 90, 180 or 270, as TPdfRenderer does
    Rotation: Integer;
    Label_: string;
  end;

  // Pre-order, at most 100000 entries and depth 64
  TPdfOutlineEntry = record
    Title: string;
    // 0 for top-level items
    Level: Integer;
    HasPage: Boolean;
    // Valid when HasPage
    PageIndex: Integer;
  end;

  TPdfViewerPermissions = record
    CanPrint: Boolean;
    // CanExtractContent
    CanCopy: Boolean;
  end;

  TPdfTextSelection = record
    Kind: TPdfSelectionKind;
    PageIndex: Integer;
    // Words joined with ' ' on a line and sLineBreak between lines
    Text: string;
    // One per line, PDF user space
    Quads: TArray<TPdfQuad>;
  end;

  TPdfOverlay = record
    Id: Integer;
    PageIndex: Integer;
    Quads: TArray<TPdfQuad>;
    Style: TPdfOverlayStyle;
    // Alpha included
    Color: TAlphaColor;
  end;

  TPdfSearchHit = record
    PageIndex: Integer;
    Text: string;
    Quads: TArray<TPdfQuad>;
  end;

  TPdfTextSelectedEvent = procedure(Sender: TObject; const Selection: TPdfTextSelection) of object;
  TPdfHoverChangedEvent = procedure(Sender: TObject; const HasSegment: Boolean; const Segment: TPdfTextFragment) of object;
  TPdfLinkClickEvent = procedure(Sender: TObject; const Link: TPdfLink) of object;
  TPdfOpenErrorEvent = procedure(Sender: TObject; const Kind: TPdfOpenErrorKind; const Message: string) of object;
  TPdfLogNotifyEvent = procedure(Sender: TObject; const Level: TPdfLogLevel; const Message: string) of object;
  TPdfPrintFailedEvent = procedure(Sender: TObject; const Message: string) of object;

  // A switch that an owner turns off when it dies, and that closures it handed out check before they touch the owner. Shared by a session
  // with the jobs and results it started, and by a dialog with the print job it frees late: nothing that finds it off is delivered.
  IPdfLifetimeToken = interface
    ['{0B4A7E15-9C32-4D68-8F01-5A6D3E2C9B47}']
    function IsAlive: Boolean;
    procedure Kill;
  end;

  TPdfLifetimeToken = class(TInterfacedObject, IPdfLifetimeToken)
  private
    FAlive: Integer;

  public
    constructor Create;
    // Thread safe
    function IsAlive: Boolean;
    procedure Kill;
  end;

implementation

uses
  System.SyncObjs;

{ TPdfLifetimeToken }

constructor TPdfLifetimeToken.Create;
begin
  inherited Create;
  FAlive := 1;
end;

function TPdfLifetimeToken.IsAlive: Boolean;
begin
  Result := (TInterlocked.CompareExchange(FAlive, 0, 0) = 1);
end;

procedure TPdfLifetimeToken.Kill;
begin
  TInterlocked.Exchange(FAlive, 0);
end;

end.
