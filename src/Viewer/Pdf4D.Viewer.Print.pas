// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.Print;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  System.SysUtils,
  Pdf4D.Render.Bitmap,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.Session,
  Pdf4D.Viewer.Document;

type
  {$SCOPEDENUMS ON}
  TPdfPrintScale = (ActualSize, Fit);
  TPdfPrintRangeKind = (All, Current, Pages);
  TPdfPrintStatus = (Completed, Cancelled, Failed);
  {$SCOPEDENUMS OFF}

  TPdfPrintSettings = record
    RangeKind: TPdfPrintRangeKind;
    // 1-based, inclusive; RangeKind = Pages
    FromPage, ToPage: Integer;
    Scale: TPdfPrintScale;
    Copies: Integer;
    MaxDpi: Integer;
    Title: string;

    // All pages, Fit, 1 copy, DefaultMaxPrintDpi, no title
    class function Default: TPdfPrintSettings; static;
    // Raises EArgumentOutOfRangeException for an empty range or one outside 1..PageCount
    function PageIndexes(const PageCount, CurrentPage: Integer): TArray<Integer>;
  end;

  TPdfPrintPagePlan = record
    PageIndex: Integer;
    // 90 when page and paper orientation differ, else 0
    ViewRotation: Integer;
    RenderScale: Single;
    // The whole page at RenderScale
    RenderSize: TSize;
    // Printer pixels inside the printable area, centred
    Dest: TRect;
    // Where the whole page lands, centred and not clipped: it lies partly outside the printable area for ActualSize on a smaller paper
    FullDest: TRect;
    // Render regions, top to bottom, together exactly RenderSize. A band has as many rows of the full width as fit in MaxBandPixels, but
    // at least one row: when RenderSize.cx alone exceeds MaxBandPixels, a band is larger than that
    Bands: TArray<TRect>;
  end;

  TPdfPrintPlanner = class
  private
    class function ShareOf(const Value, DestExtent, SourceExtent: Integer): Integer; static;

  public
    // Raises EArgumentOutOfRangeException for an empty printable area, a DPI, MaxDpi or MaxBandPixels that is not above zero
    class function PlanPage(const Page: TPdfPageInfo; const PageIndex: Integer; const PrintableSize: TSize; const PrinterDpi: TPointF;
                            const Settings: TPdfPrintSettings; const MaxBandPixels: Int64): TPdfPrintPagePlan; static;
    // The printer pixels of one band: its share of FullDest
    class function BandDest(const Plan: TPdfPrintPagePlan; const Band: TRect): TRect; static;
  end;

  IPdfPrintTarget = interface
    ['{E3B6A1D5-9F27-4C08-A4E2-6D1B8F0C5A39}']
    // Printer pixels
    function PrintableSize: TSize;
    function Dpi: TPointF;
    procedure BeginDocument(const Title: string; const Copies: Integer);
    // Before every page
    procedure BeginPage;
    // The band is valid during the call only; Dest may reach outside the printable area, which the target clips
    procedure DrawBand(const Band: TPdfBitmap; const Dest: TRect);
    procedure EndDocument;
    procedure AbortDocument;
  end;

  TPdfPrintProgressEvent = reference to procedure(const Printed, Total: Integer);
  TPdfPrintDoneEvent = reference to procedure(const Status: TPdfPrintStatus; const ErrorMessage: string);
  TPdfPrintLogEvent = reference to procedure(const Message: string);

  // Prints a range of pages of an open document to a target, one band at a time: it asks the session for a band (priority Print), draws it
  // on the target in the callback and then asks for the next, so that no more than one band is in memory. UI thread only. OnDone comes
  // once, unless the job is destroyed first. Do not free the job inside OnProgress or OnDone: the job still runs code after the callback
  // returns. Free it after the callback, for instance from a queued call.
  TPdfPrintJob = class
  private
    FLink: TPdfDocumentLink;
    FDocument: TPdf4DCustomDocument;
    FTarget: IPdfPrintTarget;
    FSettings: TPdfPrintSettings;
    FPages: TArray<Integer>;
    FMaxBandPixels: Int64;
    FOnProgress: TPdfPrintProgressEvent;
    FOnDone: TPdfPrintDoneEvent;
    FIsStarted: Boolean;
    FIsRunning: Boolean;
    FIsDocumentBegun: Boolean;
    FIsCompleted: Boolean;
    // The position in FPages of the next page to begin, and how many pages are printed
    FNextPage: Integer;
    FPrinted: Integer;
    FHasPage: Boolean;
    FPlan: TPdfPrintPagePlan;
    FBandIndex: Integer;
    FRequest: IPdfViewerRequest;
    FOnLog: TPdfPrintLogEvent;

    procedure HandleDocumentChange(const Change: TPdfDocumentChange);
    // Goes on until a band is asked for or the job is over
    procedure Advance;
    procedure Step;
    procedure BeginNextPage;
    function IsBandOnPaper(const Band: TRect): Boolean;
    procedure RequestBand;
    function BandDoneEvent: TPdfRenderDoneEvent;
    procedure HandleBand(const Outcome: TPdfRenderResult);
    procedure CancelRequest;
    class function FailureText(const Message, Fallback: string): string; static;
    // Empty when the target aborted, else why it did not (the bare text, without a lead-in)
    function AbortTarget: string;
    function ComposeEndMessage(const ErrorMessage, AbortFailure: string): string;
    procedure Finish(const Status: TPdfPrintStatus; const ErrorMessage: string);

  public
    // Raises EInvalidOpException when Document.CanPrint is False, and EArgumentOutOfRangeException for a range or a number of copies
    // that is not valid for the document
    constructor Create(const Document: TPdf4DCustomDocument; const Target: IPdfPrintTarget; const Settings: TPdfPrintSettings);
    // Cancels a running job (AbortDocument), without a callback
    destructor Destroy; override;

    // The target and the session are called from here on. A failure of either one ends the job at once, so OnDone may be called before
    // Start returns.
    procedure Start(const OnProgress: TPdfPrintProgressEvent; const OnDone: TPdfPrintDoneEvent);
    // Aborts the document and calls OnDone(Cancelled); nothing when the job is not running
    procedure Cancel;
    function IsRunning: Boolean;

    // The most pixels of one render; DefaultMaxBandPixels. Set before Start.
    property MaxBandPixels: Int64 read FMaxBandPixels write FMaxBandPixels;
    // Where a failure goes that has no OnDone to report to: aborting the document when the job is destroyed while it runs
    property OnLog: TPdfPrintLogEvent read FOnLog write FOnLog;
  end;

implementation

uses
  System.Math,
  Pdf4D.Viewer.ResourceStrings,
  Pdf4D.Viewer.ViewTransform;

const
  PointsPerInch = 72;
  RightAngle = 90;
  FullTurn = 360;

{ TPdfPrintSettings }

class function TPdfPrintSettings.Default: TPdfPrintSettings;
begin
  Result.RangeKind := TPdfPrintRangeKind.All;
  Result.FromPage := 1;
  Result.ToPage := 1;
  Result.Scale := TPdfPrintScale.Fit;
  Result.Copies := 1;
  Result.MaxDpi := DefaultMaxPrintDpi;
  Result.Title := '';
end;

function TPdfPrintSettings.PageIndexes(const PageCount, CurrentPage: Integer): TArray<Integer>;
begin
  var First := 0;
  var Last := PageCount - 1;
  case RangeKind of
    TPdfPrintRangeKind.All:
      begin
        // All pages: the range above
      end;
    TPdfPrintRangeKind.Current:
      begin
        First := CurrentPage;
        Last := CurrentPage;
      end;
    TPdfPrintRangeKind.Pages:
      begin
        First := FromPage - 1;
        Last := ToPage - 1;
      end;
  else
    raise ENotSupportedException.CreateFmt('Unsupported print range: %d', [Ord(RangeKind)]);
  end;

  const IsRangeValid = (First >= 0) and (Last < PageCount) and (First <= Last);
  if not IsRangeValid then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('The pages %d to %d are not within the %d pages of the document', [First + 1, Last + 1, PageCount]);
  end;

  SetLength(Result, Last - First + 1);
  for var Index := 0 to High(Result) do
  begin
    Result[Index] := First + Index;
  end;
end;

{ TPdfPrintPlanner }

class function TPdfPrintPlanner.PlanPage(const Page: TPdfPageInfo; const PageIndex: Integer; const PrintableSize: TSize;
                                         const PrinterDpi: TPointF; const Settings: TPdfPrintSettings;
                                         const MaxBandPixels: Int64): TPdfPrintPagePlan;
begin
  const IsPaperValid = (PrintableSize.cx > 0) and (PrintableSize.cy > 0);
  if not IsPaperValid then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('The printable area %d by %d is empty', [PrintableSize.cx, PrintableSize.cy]);
  end;

  const IsDpiValid = (PrinterDpi.X > 0) and (PrinterDpi.Y > 0);
  if not IsDpiValid then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('The printer resolution %g by %g is not above zero', [Double(PrinterDpi.X), Double(PrinterDpi.Y)]);
  end;

  if (Settings.MaxDpi < 1) or (MaxBandPixels < 1) then
  begin
    raise EArgumentOutOfRangeException.Create('The maximum resolution and the band size are not above zero');
  end;

  // The page in points as it is shown: after /Rotate
  var PageWidth: Double := Page.CropBox.Width;
  var PageHeight: Double := Page.CropBox.Height;
  if (Page.Rotation = RightAngle) or (Page.Rotation = FullTurn - RightAngle) then
  begin
    PageWidth := Page.CropBox.Height;
    PageHeight := Page.CropBox.Width;
  end;

  if not ((PageWidth > 0) and (PageHeight > 0)) then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('Page %d has no size', [PageIndex + 1]);
  end;

  // A page that is turned to the orientation of the paper. The paper is judged in inches: the pixels of a printer with a different
  // resolution per axis (600 by 300 dpi) say nothing about its shape
  Result.PageIndex := PageIndex;
  Result.ViewRotation := 0;
  const PaperWidth: Double = PrintableSize.cx / PrinterDpi.X;
  const PaperHeight: Double = PrintableSize.cy / PrinterDpi.Y;
  if (PageWidth > PageHeight) <> (PaperWidth > PaperHeight) then
  begin
    Result.ViewRotation := RightAngle;
    const Turned = PageWidth;
    PageWidth := PageHeight;
    PageHeight := Turned;
  end;

  // Printer pixels at actual size
  const NaturalX: Double = PageWidth * PrinterDpi.X / PointsPerInch;
  const NaturalY: Double = PageHeight * PrinterDpi.Y / PointsPerInch;
  var Factor: Double := 1;
  if Settings.Scale = TPdfPrintScale.Fit then
  begin
    Factor := Min(PrintableSize.cx / NaturalX, PrintableSize.cy / NaturalY);
  end;

  const DestWidth = Max(1, Round(NaturalX * Factor));
  const DestHeight = Max(1, Round(NaturalY * Factor));
  const Left = Floor((PrintableSize.cx - DestWidth) / 2);
  const Top = Floor((PrintableSize.cy - DestHeight) / 2);
  Result.FullDest := TRect.Create(Left, Top, Left + DestWidth, Top + DestHeight);
  Result.Dest := TRect.Intersect(Result.FullDest, TRect.Create(0, 0, PrintableSize.cx, PrintableSize.cy));

  // The render is no finer than the printer or than MaxDpi; the printer scales it to its pixels
  const RenderDpi: Double = Min(Max(PrinterDpi.X, PrinterDpi.Y) * Factor, Settings.MaxDpi);
  const Transform = TPdfViewTransform.Create(Page, Result.ViewRotation, RenderDpi / PointsPerInch, PointsPerInch);
  Result.RenderScale := Transform.Scale;
  Result.RenderSize := Transform.Size;

  // Rows of the full width, so that a band is one rectangle and the memory is bounded
  const RowsPerBand = Max(Int64(1), MaxBandPixels div Result.RenderSize.cx);
  var Bands: TArray<TRect>;
  var BandTop := 0;
  while BandTop < Result.RenderSize.cy do
  begin
    const BandBottom = Integer(Min(Int64(Result.RenderSize.cy), BandTop + RowsPerBand));
    Bands := Bands + [TRect.Create(0, BandTop, Result.RenderSize.cx, BandBottom)];
    BandTop := BandBottom;
  end;
  Result.Bands := Bands;
end;

class function TPdfPrintPlanner.BandDest(const Plan: TPdfPrintPagePlan; const Band: TRect): TRect;
begin
  const Full = Plan.FullDest;
  const Source = Plan.RenderSize;
  Result.Left := Full.Left + ShareOf(Band.Left, Full.Width, Source.cx);
  Result.Top := Full.Top + ShareOf(Band.Top, Full.Height, Source.cy);
  Result.Right := Full.Left + ShareOf(Band.Right, Full.Width, Source.cx);
  Result.Bottom := Full.Top + ShareOf(Band.Bottom, Full.Height, Source.cy);
end;

// The scaling is done in Int64 and Double: a page can have billions of pixels
class function TPdfPrintPlanner.ShareOf(const Value, DestExtent, SourceExtent: Integer): Integer;
begin
  Result := Round(Int64(Value) * DestExtent / SourceExtent);
end;

{ TPdfPrintJob }

constructor TPdfPrintJob.Create(const Document: TPdf4DCustomDocument; const Target: IPdfPrintTarget; const Settings: TPdfPrintSettings);
begin
  inherited Create;

  if (not Assigned(Document)) or (not Assigned(Target)) then
  begin
    raise EArgumentNilException.Create('A print job needs a document and a target');
  end;

  if not Document.CanPrint then
  begin
    raise EInvalidOpException.Create('The document does not allow printing');
  end;

  if Settings.Copies < 1 then
  begin
    raise EArgumentOutOfRangeException.CreateFmt('%d copies is not above zero', [Settings.Copies]);
  end;

  FDocument := Document;
  FTarget := Target;
  FSettings := Settings;
  FPages := Settings.PageIndexes(Document.PageCount, Document.CurrentPage);
  FMaxBandPixels := DefaultMaxBandPixels;
  FLink := TPdfDocumentLink.Create(HandleDocumentChange);
  FLink.Document := Document;
end;

destructor TPdfPrintJob.Destroy;
begin
  FLink.Free;

  // No callback: whoever frees a job does not wait for it
  if FIsRunning then
  begin
    FIsRunning := False;
    CancelRequest;
    const AbortFailure = AbortTarget;
    if (AbortFailure <> '') and Assigned(FOnLog) then
    begin
      FOnLog(Format(SPrintAbortFailed, [AbortFailure]));
    end;
  end;

  inherited;
end;

procedure TPdfPrintJob.HandleDocumentChange(const Change: TPdfDocumentChange);
begin
  case Change of
    TPdfDocumentChange.Opening,
    TPdfDocumentChange.OpenFailed,
    TPdfDocumentChange.Closed:
      if FIsRunning then
      begin
        Finish(TPdfPrintStatus.Failed, 'The document was closed while it was printed');
      end;
    TPdfDocumentChange.Opened,
    TPdfDocumentChange.CurrentPage,
    TPdfDocumentChange.Overlays,
    TPdfDocumentChange.SearchResults,
    TPdfDocumentChange.CurrentSearchHit:
      // The pages and the plan of the job do not depend on these
      Exit;
  else
    raise ENotSupportedException.CreateFmt('Unsupported document change: %d', [Ord(Change)]);
  end;
end;

procedure TPdfPrintJob.Start(const OnProgress: TPdfPrintProgressEvent; const OnDone: TPdfPrintDoneEvent);
begin
  if FIsStarted then
  begin
    raise EInvalidOpException.Create('The print job was started already');
  end;

  FIsStarted := True;
  FIsRunning := True;
  FOnProgress := OnProgress;
  FOnDone := OnDone;

  var Failure := '';
  var IsFailed := False;
  try
    FTarget.BeginDocument(FSettings.Title, FSettings.Copies);
    FIsDocumentBegun := True;
  except
    on E: Exception do
    begin
      IsFailed := True;
      Failure := FailureText(E.Message, SPrintBeginFailed);
    end;
  end;

  if IsFailed then
  begin
    Finish(TPdfPrintStatus.Failed, Failure);
    Exit;
  end;

  Advance;
end;

procedure TPdfPrintJob.Cancel;
begin
  if FIsRunning then
  begin
    Finish(TPdfPrintStatus.Cancelled, '');
  end;
end;

function TPdfPrintJob.IsRunning: Boolean;
begin
  Result := FIsRunning;
end;

procedure TPdfPrintJob.Advance;
begin
  var Failure := '';
  var IsFailed := False;
  try
    while FIsRunning and (not FIsCompleted) and (not Assigned(FRequest)) do
    begin
      Step;
    end;
  except
    on E: Exception do
    begin
      IsFailed := True;
      Failure := E.Message;
    end;
  end;

  // Outside of the try, so that an exception of OnDone is not taken for a failure of the job (OnProgress runs inside the try)
  if IsFailed then
  begin
    Finish(TPdfPrintStatus.Failed, Failure);
  end
  else if FIsCompleted then
  begin
    Finish(TPdfPrintStatus.Completed, '');
  end;
end;

// One move of the job: begin a page, ask for a band, or finish a page or the document
procedure TPdfPrintJob.Step;
begin
  if not FHasPage then
  begin
    if FNextPage >= Length(FPages) then
    begin
      FTarget.EndDocument;
      FIsCompleted := True;
    end
    else
    begin
      BeginNextPage;
    end;
    Exit;
  end;

  Inc(FBandIndex);
  if FBandIndex > High(FPlan.Bands) then
  begin
    FHasPage := False;
    Inc(FPrinted);
    if Assigned(FOnProgress) then
    begin
      FOnProgress(FPrinted, Length(FPages));
    end;
  end
  else if IsBandOnPaper(FPlan.Bands[FBandIndex]) then
  begin
    RequestBand;
  end;
end;

procedure TPdfPrintJob.BeginNextPage;
begin
  const PageIndex = FPages[FNextPage];
  FPlan := TPdfPrintPlanner.PlanPage(FDocument.Pages[PageIndex], PageIndex, FTarget.PrintableSize, FTarget.Dpi, FSettings, FMaxBandPixels);
  Inc(FNextPage);
  FBandIndex := -1;
  FHasPage := True;
  FTarget.BeginPage;
end;

// A page at actual size on a small paper reaches beyond it: the bands that lie wholly outside are not rendered
function TPdfPrintJob.IsBandOnPaper(const Band: TRect): Boolean;
begin
  Result := not TRect.Intersect(TPdfPrintPlanner.BandDest(FPlan, Band), FPlan.Dest).IsEmpty;
end;

procedure TPdfPrintJob.RequestBand;
begin
  const Session = FDocument.Session;
  if not Assigned(Session) then
  begin
    raise EInvalidOpException.Create('The document has no session to render with');
  end;

  FRequest := Session.RequestRender(FPlan.PageIndex, FPlan.RenderScale, FPlan.ViewRotation, FPlan.Bands[FBandIndex], TPdfJobPriority.Print,
                                    BandDoneEvent());
end;

function TPdfPrintJob.BandDoneEvent: TPdfRenderDoneEvent;
begin
  Result :=
    procedure(const Outcome: TPdfRenderResult)
    begin
      HandleBand(Outcome);
    end;
end;

procedure TPdfPrintJob.HandleBand(const Outcome: TPdfRenderResult);
begin
  if not FIsRunning then
  begin
    Exit;
  end;

  FRequest := nil;

  var Failure := '';
  var IsFailed := False;
  if Outcome.Succeeded then
  begin
    try
      FTarget.DrawBand(Outcome.Bitmap, TPdfPrintPlanner.BandDest(FPlan, FPlan.Bands[FBandIndex]));
    except
      on E: Exception do
      begin
        IsFailed := True;
        Failure := FailureText(E.Message, SPrintBandDrawFailed);
      end;
    end;
  end
  else
  begin
    IsFailed := True;
    Failure := FailureText(Outcome.ErrorMessage, SPrintBandRenderFailed);
  end;

  if IsFailed then
  begin
    Finish(TPdfPrintStatus.Failed, Failure);
  end
  else
  begin
    Advance;
  end;
end;

procedure TPdfPrintJob.CancelRequest;
begin
  if Assigned(FRequest) then
  begin
    FRequest.Cancel;
    FRequest := nil;
  end;
end;

function TPdfPrintJob.AbortTarget: string;
begin
  Result := '';
  if not FIsDocumentBegun then
  begin
    Exit;
  end;

  FIsDocumentBegun := False;
  try
    FTarget.AbortDocument;
  except
    on E: Exception do
    begin
      Result := FailureText(E.Message, E.ClassName);
    end;
  end;
end;

class function TPdfPrintJob.FailureText(const Message, Fallback: string): string;
begin
  Result := Message;
  if Result = '' then
  begin
    Result := Fallback;
  end;
end;

function TPdfPrintJob.ComposeEndMessage(const ErrorMessage, AbortFailure: string): string;
begin
  Result := ErrorMessage;
  if AbortFailure = '' then
  begin
    Exit;
  end;

  if ErrorMessage = '' then
  begin
    Result := Format(SPrintAbortFailed, [AbortFailure]);
  end
  else
  begin
    Result := Format(SPrintFailedAndAbortFailed, [ErrorMessage, AbortFailure]);
  end;
end;

// The one end of a job: nothing is called on the target or the callbacks afterwards
procedure TPdfPrintJob.Finish(const Status: TPdfPrintStatus; const ErrorMessage: string);
begin
  if not FIsRunning then
  begin
    Exit;
  end;

  const OnDone = FOnDone;
  FIsRunning := False;
  FOnProgress := nil;
  FOnDone := nil;
  CancelRequest;
  var AbortFailure := '';
  if Status <> TPdfPrintStatus.Completed then
  begin
    AbortFailure := AbortTarget;
  end;

  if Assigned(OnDone) then
  begin
    OnDone(Status, ComposeEndMessage(ErrorMessage, AbortFailure));
  end;
end;

end.
