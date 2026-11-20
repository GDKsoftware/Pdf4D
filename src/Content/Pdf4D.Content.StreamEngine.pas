// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/contentstream/PDFStreamEngine.java (3.0.8), for text extraction
unit Pdf4D.Content.StreamEngine;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.Defines,
  Pdf4D.Common.Log,
  Pdf4D.Common.Matrix,
  Pdf4D.Content.GraphicsState,
  Pdf4D.Content.Operator,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Font.Base,
  Pdf4D.Model.FormXObject,
  Pdf4D.Model.Page,
  Pdf4D.Model.Rectangle,
  Pdf4D.Model.Resources,
  Pdf4D.Parser.ContentStream;

type
  // What the engine needs to know of an operator processor. TOperatorProcessor in Pdf4D.Content.OperatorProcessor adds the
  // engine and the helpers of the processors; it is split off because that unit uses this one.
  TOperatorProcessorBase = class abstract
  public
    function Name: string; virtual; abstract;
    // Operands are valid during the call only: the engine frees them when the operator is done
    procedure Process(const Operator: TContentOperator; const Operands: TArray<TCosBase>); virtual; abstract;
  end;

  // Runs content streams: the page, form XObjects and (through subclasses) the text operators. Besides the PDFBox
  // behaviour it enforces the limits of TPdfLoadOptions, because content streams can be hostile:
  // - a form that is already being drawn is skipped, and the form depth is limited;
  // - a page has a budget of operators and of glyphs; a page over budget stops, and keeps what was gathered;
  // - a page has a budget of decoded content bytes, counted for the page content and for every run of a form; the decoded
  //   data of a form is kept for the page, so that a form that is drawn again is not decoded again;
  // - an operator has a limited number of operands, and an array a limited number of items; the rest is dropped;
  // - q beyond the depth limit is ignored, and so is the Q that belongs to it.
  // The engine is not thread safe. It does not own the page.
  TPdfStreamEngine = class
  private
    type
      // Ends the page without a log line, like a budget that is used up, because the subclass asked for it
      EStopRequested = class(EPdfLimitExceededException);

      // What a nested stream replaces: the resources and the graphics stack
      TStreamFrame = record
        PreviousResources: TPDResources;
        CreatedResources: TPDResources;
        PreviousStack: TObjectList<TPDGraphicsState>;
        PreviousIgnoredSaves: Integer;
      end;

      // The decoded data of a stream that is drawn more than once on one page
      TCachedContent = record
        Data: TBytes;
        IsReadable: Boolean;
      end;

      // The content streams of a page, joined with a line feed. The buffer doubles when it is full, so that joining takes
      // linear time.
      TContentBuffer = record
      private
        FBytes: TBytes;
        FUsed: Int64;

      public
        procedure Append(const Data: TBytes);
        function ToBytes: TBytes;
      end;

  private
    const Hundred: Single = 100;
    const Thousand: Single = 1000;
    const SpaceCode = 32;
    const ContentSeparator = 10;

  private
    FProcessors: TObjectDictionary<string, TOperatorProcessorBase>;
    FStack: TObjectList<TPDGraphicsState>;
    FIgnoredSaves: Integer;
    FIsDepthWarningGiven: Boolean;
    FResources: TPDResources;
    FCurrentPage: TPDPage;
    FActiveStreams: TList<TCosStream>;
    FLevel: Integer;
    FOperatorCount: Int64;
    FGlyphCount: Integer;
    FContentBytes: Int64;
    FIsOperandLimitLogged: Boolean;
    FFormCache: TDictionary<TCosStream, TCachedContent>;
    FMaxOperators: Int64;
    FShouldProcessColorOperators: Boolean;
    FIsCharProcPending: Boolean;
    FMaxGlyphs: Integer;

    procedure InitPage(const Page: TPDPage);
    function GetDefaultFont: TPDFont;
    function GetOptions: TPdfLoadOptions;
    procedure CacheLimits;

    procedure ProcessPageContent;
    function ReadPageContent: TBytes;
    function TryReadStreamData(const Stream: TCosStream; out Data: TBytes): Boolean;
    function TryGetFormContent(const Stream: TCosStream; out Data: TBytes): Boolean;
    procedure ChargeContentBytes(const Count: Int64);
    function TryChargeContentBytes(const Count: Int64): Boolean;
    procedure RunPageContent;
    procedure ProcessForm(const Form: TPDFormXObject; const InitialState: TPDGraphicsState);
    procedure ProcessContent(const Data: TBytes; const Resources: TCosDictionary; const HasEmptyResources: Boolean; const InitialState: TPDGraphicsState;
      const Matrix: TPdfMatrix; const HasBBox: Boolean; const BBox: TPdfRectangle);
    procedure RunStream(const Stream: TCosStream; const Resources: TCosDictionary; const HasEmptyResources: Boolean; const InitialState: TPDGraphicsState;
      const Matrix: TPdfMatrix; const HasBBox: Boolean; const BBox: TPdfRectangle);
    procedure RequireCurrentPage;
    procedure CheckStopRequested;
    procedure ProcessStreamOperators(const Data: TBytes);
    procedure ProcessOperators(const Parser: TPdfStreamParser; const IsCharProc: Boolean);
    function TryReadToken(const Parser: TPdfStreamParser; out Token: TObject): Boolean;
    procedure LogOperandLimit;
    procedure RunOperator(const Operator: TContentOperator; const Operands: TObjectList<TObject>);
    function CreateFrameResources(const StreamResources: TCosDictionary; const HasEmptyResources: Boolean): TPDResources;

    function BeginFrame(const StreamResources: TCosDictionary; const HasEmptyResources: Boolean; const InitialState: TPDGraphicsState): TStreamFrame;
    procedure EndFrame(const Frame: TStreamFrame);

    procedure CountOperator;
    procedure RunProcessor(const Processor: TOperatorProcessorBase; const Operator: TContentOperator; const Operands: TArray<TCosBase>);
    procedure CountGlyph;
    procedure HandleOperatorFailure(const Operator: TContentOperator; const Operands: TArray<TCosBase>; const Failure: Exception);

    function IsVerticalFont(const Font: TPDFont): Boolean;
    function GetTextMatrixOrRaise: TPdfMatrix;

  protected
    // Called by ProcessPage after the page is set up, inside the floating point guard. A subclass prepares what it reads from
    // the page here.
    procedure PrepareEngineForPage(const Page: TPDPage); virtual;
    // The graphics state at the bottom of the stack of a page, made by ProcessPage. A subclass with a state of its own
    // returns it here; it overrides TPDGraphicsState.Clone as well.
    function CreateInitialGraphicsState(const Page: TPDPage): TPDGraphicsState; virtual;
    // Asked after every operator and before every content stream. True ends the page like a used up budget does, but
    // without a line in the log.
    function StopRequested: Boolean; virtual;
    // Where PDFBox calls clipToRect: at the start of a form (after its matrix), a group, a pattern, an annotation and a Type 3
    // glyph. Nothing by default.
    procedure ClipToRect(const Rect: TPdfRectangle); virtual;
    procedure ApplyTextAdjustment(const Tx, Ty: Single); virtual;
    procedure ShowText(const Bytes: TBytes); virtual;
    // Called for operators without a processor. Nothing by default.
    procedure UnsupportedOperator(const Operator: TContentOperator; const Operands: TArray<TCosBase>); virtual;

  public
    constructor Create;
    destructor Destroy; override;

    // The engine becomes the owner of Processor. A processor with the same name replaces the earlier one.
    procedure AddOperator(const Processor: TOperatorProcessorBase);

    // Runs the content of the page. Floating point exceptions are masked for the duration, as they are in Java. A page that
    // runs over its operator or glyph budget stops with a line in the log; what was gathered up to there stays. An
    // EPdfException of the structure of the page is raised as it is.
    procedure ProcessPage(const Page: TPDPage); virtual;

    procedure ShowTransparencyGroup(const Form: TPDFormXObject); virtual;
    procedure ShowForm(const Form: TPDFormXObject); virtual;
    // Runs a form like ShowForm does, but on InitialState (not nil) as the only state of the new graphics stack; the engine owns it from
    // the call on. For a subclass that draws a group with a changed state.
    procedure ProcessFormWithState(const Form: TPDFormXObject; const InitialState: TPDGraphicsState);

    // Runs Content with Resources (nil: those of the running stream) on the recursion guard, the budgets and the cache of
    // decoded form content that a form uses. Level is left to the caller, as in PDFBox where the Do operator keeps it.
    // InitialState becomes the only state of a new graphics stack; the engine owns it from the call on. Nil gives a clone
    // of the current state. Matrix is concatenated to the CTM of that state, and then ClipToRect(BBox) is called when HasBBox.
    // The stack and the resources that were current come back when the stream is done, also after an exception.
    // ProcessChildStream for the glyph procedure of a Type 3 font: a d1 as first operator makes it an uncoloured glyph
    procedure ProcessType3CharProc(const Content: TCosStream; const Resources: TCosDictionary; const InitialState: TPDGraphicsState);

    procedure ProcessChildStream(const Content: TCosStream; const Resources: TCosDictionary; const InitialState: TPDGraphicsState; const Matrix: TPdfMatrix;
      const HasBBox: Boolean; const BBox: TPdfRectangle);

    procedure BeginText; virtual;
    procedure EndText; virtual;

    procedure ShowTextString(const Bytes: TBytes);
    procedure ShowTextStrings(const Items: TCosArray);
    // The glyph is not drawn: a subclass collects it. Type 3 glyph procedures are not run.
    procedure ShowGlyph(const TextRenderingMatrix: TPdfMatrix; const Font: TPDFont; const Code: Integer; const Displacement: TPdfVector); virtual;

    // Tag is empty when BMC had no name; Properties is nil without properties. Both are valid during the call only.
    procedure BeginMarkedContentSequence(const Tag: string; const Properties: TCosDictionary); virtual;
    procedure EndMarkedContentSequence; virtual;

    // Looks the processor up by name and runs it. An exception from the processor goes through OperatorException, a
    // budget limit does not: it ends the page.
    procedure ProcessOperator(const Operator: TContentOperator; const Operands: TArray<TCosBase>); overload; virtual;
    procedure ProcessOperator(const Name: string; const Operands: TArray<TCosBase>); overload;
    // Like PDFStreamEngine.operatorException: a missing operand is an error, an empty graphics stack and a failing Do are
    // warnings. Where PDFBox throws for the rest, this logs an error as well, so that the stream goes on.
    procedure OperatorException(const Operator: TContentOperator; const Operands: TArray<TCosBase>; const Failure: EPdfException); virtual;

    procedure SaveGraphicsState;
    // Whether Q has a state to go back to (a q that was ignored because of the depth limit counts)
    function CanRestoreGraphicsState: Boolean;
    procedure RestoreGraphicsState;
    function GraphicsStackSize: Integer;
    function GraphicsState: TPDGraphicsState;

    // False outside BT..ET, where PDFBox has null
    function TryGetTextMatrix(out Matrix: TPdfMatrix): Boolean;
    procedure SetTextMatrix(const Matrix: TPdfMatrix);
    procedure ClearTextMatrix;
    function TryGetTextLineMatrix(out Matrix: TPdfMatrix): Boolean;
    procedure SetTextLineMatrix(const Matrix: TPdfMatrix);
    procedure ClearTextLineMatrix;

    procedure IncreaseLevel;
    procedure DecreaseLevel;

    procedure LogWarning(const Fmt: string; const Args: array of const);
    procedure LogError(const Fmt: string; const Args: array of const);

    // The resources of the stream that is being run (not owned)
    property Resources: TPDResources read FResources;
    property CurrentPage: TPDPage read FCurrentPage;
    // The limits of the document of the current page; the defaults without a page
    property Options: TPdfLoadOptions read GetOptions;
    property Level: Integer read FLevel;
    // False while the stream that runs is a glyph procedure of a Type 3 font that starts with d1: the colour operators that PDFBox
    // guards with isShouldProcessColorOperators (CS, cs and the device colour operators) are ignored then
    property ShouldProcessColorOperators: Boolean read FShouldProcessColorOperators;
  end;

implementation

uses
  System.Classes,
  System.Math,
  Pdf4D.Common.FloatGuard,
  Pdf4D.Content.OperatorProcessor,
  Pdf4D.Cos.Number,
  Pdf4D.Cos.PdfString,
  Pdf4D.Font.Factory;

{ TPdfStreamEngine }

constructor TPdfStreamEngine.Create;
begin
  inherited Create;
  FShouldProcessColorOperators := True;
  FProcessors := TObjectDictionary<string, TOperatorProcessorBase>.Create([doOwnsValues]);
  FStack := TObjectList<TPDGraphicsState>.Create(True);
  FActiveStreams := TList<TCosStream>.Create;
  FFormCache := TDictionary<TCosStream, TCachedContent>.Create;
  CacheLimits;
end;

destructor TPdfStreamEngine.Destroy;
begin
  FFormCache.Free;
  FActiveStreams.Free;
  FStack.Free;
  FProcessors.Free;
  inherited;
end;

procedure TPdfStreamEngine.AddOperator(const Processor: TOperatorProcessorBase);
begin
  if not Assigned(Processor) then
  begin
    raise EArgumentNilException.Create('Processor');
  end;

  FProcessors.AddOrSetValue(Processor.Name, Processor);
end;

function TPdfStreamEngine.GetOptions: TPdfLoadOptions;
begin
  if Assigned(FCurrentPage) then
  begin
    Result := FCurrentPage.Context.Options;
  end
  else
  begin
    Result := TPdfLoadOptions.Default;
  end;
end;

procedure TPdfStreamEngine.LogWarning(const Fmt: string; const Args: array of const);
begin
  if Assigned(FCurrentPage) and Assigned(FCurrentPage.Context.Log) then
  begin
    FCurrentPage.Context.Log.Warning(Fmt, Args);
  end;
end;

procedure TPdfStreamEngine.LogError(const Fmt: string; const Args: array of const);
begin
  if Assigned(FCurrentPage) and Assigned(FCurrentPage.Context.Log) then
  begin
    FCurrentPage.Context.Log.Error(Fmt, Args);
  end;
end;

procedure TPdfStreamEngine.InitPage(const Page: TPDPage);
begin
  if not Assigned(Page) then
  begin
    raise EArgumentNilException.Create('Page');
  end;

  FCurrentPage := Page;
  FStack.Clear;
  FStack.Add(CreateInitialGraphicsState(Page));
  FIgnoredSaves := 0;
  FIsDepthWarningGiven := False;
  FResources := nil;
  FActiveStreams.Clear;
  FLevel := 0;
  FOperatorCount := 0;
  FGlyphCount := 0;
  FContentBytes := 0;
  FIsOperandLimitLogged := False;
  FShouldProcessColorOperators := True;
  FIsCharProcPending := False;
  FFormCache.Clear;
  CacheLimits;
end;

// The limits are read once per page: Options hands out a copy of the whole record, which is too much work per operator and glyph
procedure TPdfStreamEngine.CacheLimits;
begin
  const PageOptions = Options;
  FMaxOperators := PageOptions.MaxOperatorsPerPage;
  FMaxGlyphs := PageOptions.MaxGlyphsPerPage;
end;

function TPdfStreamEngine.GetDefaultFont: TPDFont;
begin
  const Context = FCurrentPage.Context;
  // One default font per document: the context is the key
  var Cached: TObject;
  if Context.TryGetCachedObject(Context, Cached) then
  begin
    Exit(TPDFont(Cached));
  end;

  Result := TPDFontFactory.CreateDefaultFont(Context);
  try
    Context.AddCachedObject(Context, Result);
  except
    Result.Free;
    raise;
  end;
end;

procedure TPdfStreamEngine.ProcessPage(const Page: TPDPage);
begin
  const PreviousMask = TPdfFloatGuard.Enter;
  try
    InitPage(Page);
    PrepareEngineForPage(Page);
    if Page.HasContents then
    begin
      RunPageContent;
    end;
  finally
    TPdfFloatGuard.Leave(PreviousMask);
  end;
end;

procedure TPdfStreamEngine.PrepareEngineForPage(const Page: TPDPage);
begin
end;

function TPdfStreamEngine.CreateInitialGraphicsState(const Page: TPDPage): TPDGraphicsState;
begin
  Result := TPDGraphicsState.Create;
end;

function TPdfStreamEngine.StopRequested: Boolean;
begin
  Result := False;
end;

procedure TPdfStreamEngine.ClipToRect(const Rect: TPdfRectangle);
begin
end;

procedure TPdfStreamEngine.CheckStopRequested;
begin
  if StopRequested then
  begin
    raise EStopRequested.Create('A stop was requested');
  end;
end;

procedure TPdfStreamEngine.RunPageContent;
begin
  try
    ProcessPageContent;
  except
    on Failure: EStopRequested do
    begin
      // The subclass asked for it: no line in the log
      Exit;
    end;
    on Failure: EPdfLimitExceededException do
    begin
      LogError('Processing of the page stopped, the text so far is kept: %s', [Failure.Message]);
    end;
    on Failure: EPdfException do
    begin
      raise;
    end;
    on Failure: Exception do
    begin
      if TPdfFailure.IsFatal(Failure) then
      begin
        // A mistake in the library or the runtime, not in the file
        raise;
      end;
      raise EPdfParseException.CreateFmt('Processing of the page failed: %s: %s', [Failure.ClassName, Failure.Message]);
    end;
  end;
end;

procedure TPdfStreamEngine.ProcessPageContent;
begin
  const Data = ReadPageContent;
  ProcessContent(Data, nil, False, nil, TPdfMatrix.Identity, False, Default(TPdfRectangle));
end;

procedure TPdfStreamEngine.ChargeContentBytes(const Count: Int64);
begin
  const Limit = Options.MaxContentBytesPerPage;
  if (Count > Limit) or (FContentBytes > Limit - Count) then
  begin
    raise EPdfLimitExceededException.CreateFmt('The page has more than %d bytes of content', [Limit]);
  end;
  FContentBytes := FContentBytes + Count;
end;

function TPdfStreamEngine.TryChargeContentBytes(const Count: Int64): Boolean;
begin
  Result := True;
  try
    ChargeContentBytes(Count);
  except
    on Failure: EPdfLimitExceededException do
    begin
      LogError('The rest of the page content is skipped: %s', [Failure.Message]);
      Result := False;
    end;
  end;
end;

function TPdfStreamEngine.ReadPageContent: TBytes;
begin
  var Buffer := Default(TContentBuffer);
  try
    for var Stream in FCurrentPage.ContentStreams do
    begin
      var Data: TBytes;
      if TryReadStreamData(Stream, Data) then
      begin
        if not TryChargeContentBytes(Length(Data) + 1) then
        begin
          // What was read so far is run, as for a form that goes over budget
          Break;
        end;
        Buffer.Append(Data);
      end;
    end;
    Result := Buffer.ToBytes;
  except
    on Failure: EOutOfMemory do
    begin
      raise EPdfLimitExceededException.Create('Not enough memory for the content of the page');
    end;
  end;
end;

// An operator may not run into the next stream, so the streams of /Contents are joined with a line feed, as PDFBox does
procedure TPdfStreamEngine.TContentBuffer.Append(const Data: TBytes);
begin
  const Needed = FUsed + Length(Data) + 1;
  if Needed > High(Integer) then
  begin
    raise EPdfLimitExceededException.Create('The content of the page is too large for one buffer');
  end;

  if Needed > Length(FBytes) then
  begin
    SetLength(FBytes, Min(Max(Needed, Int64(Length(FBytes)) * 2), Int64(High(Integer))));
  end;
  if Length(Data) > 0 then
  begin
    Move(Data[0], FBytes[FUsed], Length(Data));
  end;
  FBytes[FUsed + Length(Data)] := ContentSeparator;
  FUsed := Needed;
end;

function TPdfStreamEngine.TContentBuffer.ToBytes: TBytes;
begin
  SetLength(FBytes, FUsed);
  Result := FBytes;
end;

// Decodes a form once per page, and charges the page for its bytes every time it is run
function TPdfStreamEngine.TryGetFormContent(const Stream: TCosStream; out Data: TBytes): Boolean;
begin
  var Cached: TCachedContent;
  if not FFormCache.TryGetValue(Stream, Cached) then
  begin
    Cached.IsReadable := TryReadStreamData(Stream, Cached.Data);
    if Cached.IsReadable then
    begin
      ChargeContentBytes(Length(Cached.Data) + 1);
    end;
    FFormCache.Add(Stream, Cached);
    Data := Cached.Data;
    Exit(Cached.IsReadable);
  end;

  Data := Cached.Data;
  Result := Cached.IsReadable;
  if Result then
  begin
    ChargeContentBytes(Length(Data) + 1);
  end;
end;

function TPdfStreamEngine.TryReadStreamData(const Stream: TCosStream; out Data: TBytes): Boolean;
begin
  Data := nil;
  Result := False;
  try
    const Decoded = Stream.CreateDecodedStream;
    try
      SetLength(Data, Decoded.Size);
      Decoded.Position := 0;
      if Length(Data) > 0 then
      begin
        Decoded.ReadBuffer(Data[0], Length(Data));
      end;
      Result := True;
    finally
      Decoded.Free;
    end;
  except
    on Failure: Exception do
    begin
      const IsRecoverable = ((Failure is EPdfException) or TPdfFailure.IsInputFailure(Failure));
      if not IsRecoverable then
      begin
        raise;
      end;
      Data := nil;
      LogError('Skipped a content stream that could not be read: %s', [Failure.Message]);
    end;
  end;
end;

procedure TPdfStreamEngine.ShowTransparencyGroup(const Form: TPDFormXObject);
begin
  ProcessForm(Form, nil);
end;

procedure TPdfStreamEngine.ShowForm(const Form: TPDFormXObject);
begin
  ProcessForm(Form, nil);
end;

procedure TPdfStreamEngine.ProcessFormWithState(const Form: TPDFormXObject; const InitialState: TPDGraphicsState);
begin
  if not Assigned(InitialState) then
  begin
    raise EArgumentNilException.Create('InitialState');
  end;
  ProcessForm(Form, InitialState);
end;

procedure TPdfStreamEngine.RequireCurrentPage;
begin
  if not Assigned(FCurrentPage) then
  begin
    raise EInvalidOpException.Create('No current page, call ProcessPage instead');
  end;
end;

procedure TPdfStreamEngine.ProcessForm(const Form: TPDFormXObject; const InitialState: TPDGraphicsState);
begin
  var FormResources: TCosDictionary;
  if not Form.TryGetResources(FormResources) then
  begin
    FormResources := nil;
  end;

  var BBox: TPdfRectangle;
  const HasBBox = Form.TryGetBBox(BBox);
  RunStream(Form.Stream, FormResources, Form.HasEmptyResources, InitialState, Form.Matrix, HasBBox, BBox);
end;

procedure TPdfStreamEngine.ProcessChildStream(const Content: TCosStream; const Resources: TCosDictionary; const InitialState: TPDGraphicsState; const Matrix: TPdfMatrix;
  const HasBBox: Boolean; const BBox: TPdfRectangle);
begin
  if Content = nil then
  begin
    InitialState.Free;
    raise EArgumentNilException.Create('Content');
  end;
  RunStream(Content, Resources, False, InitialState, Matrix, HasBBox, BBox);
end;

procedure TPdfStreamEngine.ProcessType3CharProc(const Content: TCosStream; const Resources: TCosDictionary; const InitialState: TPDGraphicsState);
begin
  FIsCharProcPending := True;
  try
    ProcessChildStream(Content, Resources, InitialState, TPdfMatrix.Identity, False, Default(TPdfRectangle));
  finally
    FIsCharProcPending := False;
  end;
end;

// The engine owns InitialState from here on; BeginFrame hands it to the new graphics stack, so until then every way out
// frees it
procedure TPdfStreamEngine.RunStream(const Stream: TCosStream; const Resources: TCosDictionary; const HasEmptyResources: Boolean; const InitialState: TPDGraphicsState;
  const Matrix: TPdfMatrix; const HasBBox: Boolean; const BBox: TPdfRectangle);
begin
  var Data: TBytes;
  try
    RequireCurrentPage;
    // PDFBox only has the depth limit. A form that draws itself would use up all the depth, 50 times over at every level.
    if FActiveStreams.Contains(Stream) then
    begin
      LogWarning('Form XObject draws itself (recursion), skipped', []);
      InitialState.Free;
      Exit;
    end;

    if not TryGetFormContent(Stream, Data) then
    begin
      InitialState.Free;
      Exit;
    end;
  except
    InitialState.Free;
    raise;
  end;

  FActiveStreams.Add(Stream);
  try
    ProcessContent(Data, Resources, HasEmptyResources, InitialState, Matrix, HasBBox, BBox);
  finally
    FActiveStreams.Delete(FActiveStreams.Count - 1);
  end;
end;

function TPdfStreamEngine.CreateFrameResources(const StreamResources: TCosDictionary; const HasEmptyResources: Boolean): TPDResources;
begin
  Result := nil;
  if Assigned(StreamResources) then
  begin
    Result := TPDResources.Create(StreamResources, FCurrentPage.Context);
  end
  else if HasEmptyResources then
  begin
    Result := TPDResources.Create(nil, FCurrentPage.Context);
  end;
end;

function TPdfStreamEngine.BeginFrame(const StreamResources: TCosDictionary; const HasEmptyResources: Boolean; const InitialState: TPDGraphicsState): TStreamFrame;
begin
  Result := Default(TStreamFrame);
  // saveGraphicsStack: the stream runs on a stack of its own that starts with a copy of the current state, or with the state
  // the caller gives. Everything that can fail is made first, so that a failure leaves the engine as it was.
  const NewStack = TObjectList<TPDGraphicsState>.Create(True);
  try
    if Assigned(InitialState) then
    begin
      NewStack.Add(InitialState);
    end
    else
    begin
      NewStack.Add(FStack.Last.Clone);
    end;
    Result.CreatedResources := CreateFrameResources(StreamResources, HasEmptyResources);
  except
    NewStack.Free;
    raise;
  end;

  Result.PreviousResources := FResources;
  Result.PreviousStack := FStack;
  Result.PreviousIgnoredSaves := FIgnoredSaves;
  FStack := NewStack;
  FIgnoredSaves := 0;

  // Resource lookup: the resources of the stream, else those of the parent stream (not in the PDF specification, but
  // PDFBOX-1359 does it and Acrobat copes), else those of the page
  if Assigned(Result.CreatedResources) then
  begin
    FResources := Result.CreatedResources;
  end
  else if not Assigned(FResources) then
  begin
    FResources := FCurrentPage.Resources;
  end;
end;

procedure TPdfStreamEngine.EndFrame(const Frame: TStreamFrame);
begin
  FStack.Free;
  FStack := Frame.PreviousStack;
  FIgnoredSaves := Frame.PreviousIgnoredSaves;
  FResources := Frame.PreviousResources;
  Frame.CreatedResources.Free;
end;

procedure TPdfStreamEngine.ProcessContent(const Data: TBytes; const Resources: TCosDictionary; const HasEmptyResources: Boolean; const InitialState: TPDGraphicsState;
  const Matrix: TPdfMatrix; const HasBBox: Boolean; const BBox: TPdfRectangle);
begin
  const Frame = BeginFrame(Resources, HasEmptyResources, InitialState);
  try
    CheckStopRequested;
    var Ctm := GraphicsState.CurrentTransformationMatrix;
    Ctm.ConcatenateWith(Matrix);
    GraphicsState.CurrentTransformationMatrix := Ctm;
    // PDFBox clips to the BBox of a form after its matrix is part of the CTM
    if HasBBox then
    begin
      ClipToRect(BBox);
    end;
    ProcessStreamOperators(Data);
  finally
    EndFrame(Frame);
  end;
end;

procedure TPdfStreamEngine.ProcessStreamOperators(const Data: TBytes);
begin
  const Parser = TPdfStreamParser.Create(Data, Options, FCurrentPage.Context.Log);
  // Only the stream that the pending flag was set for is a glyph procedure, not the streams it runs
  const IsCharProc = FIsCharProcPending;
  FIsCharProcPending := False;
  try
    ProcessOperators(Parser, IsCharProc);
  finally
    // The operands that point into the pool of the parser are gone by now
    Parser.Free;
  end;
end;

function TPdfStreamEngine.TryReadToken(const Parser: TPdfStreamParser; out Token: TObject): Boolean;
begin
  Token := nil;
  Result := True;
  try
    Token := Parser.ParseNextToken;
  except
    on Failure: Exception do
    begin
      const IsRecoverable = ((Failure is EPdfException) or TPdfFailure.IsInputFailure(Failure));
      if not IsRecoverable then
      begin
        raise;
      end;
      LogError('The content stream cannot be read any further: %s', [Failure.Message]);
      Result := False;
    end;
  end;
end;

procedure TPdfStreamEngine.ProcessOperators(const Parser: TPdfStreamParser; const IsCharProc: Boolean);
begin
  // Every stream starts with the colour operators on, and a glyph procedure that starts with d1 turns them off; the setting of
  // the stream that this one was started from comes back at the end
  const PreviousShouldProcessColorOperators = FShouldProcessColorOperators;
  FShouldProcessColorOperators := True;
  var IsFirstOperator := True;

  // The tokens are made one at a time: a large stream is never held in memory as a list of tokens
  const Operands = TObjectList<TObject>.Create(True);
  try
    var Token: TObject;
    while TryReadToken(Parser, Token) and Assigned(Token) do
    begin
      if Token is TContentOperator then
      begin
        if IsFirstOperator and IsCharProc and (TContentOperator(Token).Name = TOperatorNames.Type3D1) then
        begin
          FShouldProcessColorOperators := False;
        end;
        IsFirstOperator := False;
        try
          RunOperator(TContentOperator(Token), Operands);
        finally
          Token.Free;
          Operands.Clear;
        end;
      end
      else if (Token is TCosBase) and (Operands.Count < MaxContentOperands) then
      begin
        Operands.Add(Token);
      end
      else
      begin
        if Token is TCosBase then
        begin
          LogOperandLimit;
        end;
        Token.Free;
      end;
    end;
  finally
    Operands.Free;
    FShouldProcessColorOperators := PreviousShouldProcessColorOperators;
  end;
end;

procedure TPdfStreamEngine.LogOperandLimit;
begin
  if not FIsOperandLimitLogged then
  begin
    FIsOperandLimitLogged := True;
    LogWarning('An operator has more than %d operands, the rest is dropped', [MaxContentOperands]);
  end;
end;

procedure TPdfStreamEngine.RunOperator(const Operator: TContentOperator; const Operands: TObjectList<TObject>);
begin
  var Values: TArray<TCosBase>;
  SetLength(Values, Operands.Count);
  for var Index := 0 to Operands.Count - 1 do
  begin
    Values[Index] := TCosBase(Operands[Index]);
  end;
  ProcessOperator(Operator, Values);
end;

procedure TPdfStreamEngine.CountOperator;
begin
  Inc(FOperatorCount);
  if FOperatorCount > FMaxOperators then
  begin
    raise EPdfLimitExceededException.CreateFmt('The page has more than %d operators', [FMaxOperators]);
  end;
end;

procedure TPdfStreamEngine.CountGlyph;
begin
  if FGlyphCount >= FMaxGlyphs then
  begin
    raise EPdfLimitExceededException.CreateFmt('The page has more than %d glyphs', [FMaxGlyphs]);
  end;
  Inc(FGlyphCount);
end;

procedure TPdfStreamEngine.ProcessOperator(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  CountOperator;

  var Processor: TOperatorProcessorBase;
  if FProcessors.TryGetValue(Operator.Name, Processor) then
  begin
    RunProcessor(Processor, Operator, Operands);
  end
  else
  begin
    UnsupportedOperator(Operator, Operands);
  end;
  CheckStopRequested;
end;

procedure TPdfStreamEngine.RunProcessor(const Processor: TOperatorProcessorBase; const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  try
    Processor.Process(Operator, Operands);
  except
    on Failure: EPdfLimitExceededException do
    begin
      raise;
    end;
    on Failure: EOutOfMemory do
    begin
      // Every operator after this one would fail the same way: the page ends here and keeps its text, as for a limit
      raise EPdfLimitExceededException.CreateFmt('The page ran out of memory at operator %s', [Operator.Name]);
    end;
    on Failure: Exception do
    begin
      if TPdfFailure.IsFatal(Failure) then
      begin
        // A mistake in the library or the runtime, not in the file
        raise;
      end;
      HandleOperatorFailure(Operator, Operands, Failure);
    end;
  end;
end;

// The stream goes on after a failing operator, whatever the failure: a hostile file can drive the font and CMap code into
// exceptions that are no EPdfException
procedure TPdfStreamEngine.HandleOperatorFailure(const Operator: TContentOperator; const Operands: TArray<TCosBase>; const Failure: Exception);
begin
  if Failure is EPdfException then
  begin
    OperatorException(Operator, Operands, EPdfException(Failure));
  end
  else
  begin
    LogError('Operator %s failed: %s: %s', [Operator.Name, Failure.ClassName, Failure.Message]);
  end;
end;

procedure TPdfStreamEngine.ProcessOperator(const Name: string; const Operands: TArray<TCosBase>);
begin
  const Operator = TContentOperator.Create(Name);
  try
    ProcessOperator(Operator, Operands);
  finally
    Operator.Free;
  end;
end;

procedure TPdfStreamEngine.UnsupportedOperator(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
end;

procedure TPdfStreamEngine.OperatorException(const Operator: TContentOperator; const Operands: TArray<TCosBase>; const Failure: EPdfException);
begin
  if Failure is EPdfEmptyGraphicsStackException then
  begin
    LogWarning('%s', [Failure.Message]);
  end
  else if Failure is EPdfMissingOperandException then
  begin
    LogError('%s', [Failure.Message]);
  end
  else if Operator.Name = TOperatorNames.DrawObject then
  begin
    // Too forgiving, but PDFBox has always worked this way for Do
    LogWarning('Operator %s failed: %s', [Operator.Name, Failure.Message]);
  end
  else
  begin
    LogError('Operator %s failed: %s', [Operator.Name, Failure.Message]);
  end;
end;

procedure TPdfStreamEngine.BeginText;
begin
end;

procedure TPdfStreamEngine.EndText;
begin
end;

function TPdfStreamEngine.IsVerticalFont(const Font: TPDFont): Boolean;
begin
  Result := (Assigned(Font) and Font.IsVertical);
end;

function TPdfStreamEngine.GetTextMatrixOrRaise: TPdfMatrix;
begin
  if not GraphicsState.TryGetTextMatrix(Result) then
  begin
    raise EPdfParseException.Create('There is no text matrix outside BT and ET');
  end;
end;

procedure TPdfStreamEngine.ShowTextString(const Bytes: TBytes);
begin
  ShowText(Bytes);
end;

procedure TPdfStreamEngine.ShowTextStrings(const Items: TCosArray);
begin
  const TextState = GraphicsState.TextState;
  const FontSize = TextState.FontSize;
  const HorizontalScaling = TextState.HorizontalScaling / Hundred;
  const IsVertical = IsVerticalFont(TextState.Font);

  for var Index := 0 to Items.Count - 1 do
  begin
    const Item = Items.Get(Index);
    if Item is TCosNumber then
    begin
      const Adjustment = TCosNumber(Item).FloatValue;
      if IsVertical then
      begin
        ApplyTextAdjustment(0, -Adjustment / Thousand * FontSize);
      end
      else
      begin
        ApplyTextAdjustment(-Adjustment / Thousand * FontSize * HorizontalScaling, 0);
      end;
    end
    else if Item is TCosString then
    begin
      ShowText(TCosString(Item).Bytes);
    end
    else if Item is TCosArray then
    begin
      LogError('Nested arrays are not allowed in an array for TJ operation', []);
    end
    else
    begin
      LogError('Unknown type %s in array for TJ operation', [Item.ClassName]);
    end;
  end;
end;

procedure TPdfStreamEngine.ApplyTextAdjustment(const Tx, Ty: Single);
begin
  var Matrix := GetTextMatrixOrRaise;
  Matrix.Translate(Tx, Ty);
  GraphicsState.SetTextMatrix(Matrix);
end;

procedure TPdfStreamEngine.ShowText(const Bytes: TBytes);
begin
  const State = GraphicsState;
  const TextState = State.TextState;
  var TextMatrix: TPdfMatrix;
  if not State.TryGetTextMatrix(TextMatrix) then
  begin
    // Outside BT..ET there is no text matrix
    Exit;
  end;

  var Font := TextState.Font;
  if not Assigned(Font) then
  begin
    LogWarning('No current font, will use default', []);
    Font := GetDefaultFont;
  end;

  const FontSize = TextState.FontSize;
  const HorizontalScaling = TextState.HorizontalScaling / Hundred;
  const CharSpacing = TextState.CharacterSpacing;
  // The text state parameters in matrix form
  const Parameters = TPdfMatrix.Create(FontSize * HorizontalScaling, 0, 0, FontSize, 0, TextState.Rise);

  var Position := 0;
  while Position < Length(Bytes) do
  begin
    const Before = Position;
    const Code = Font.ReadCode(Bytes, Position);
    if Position <= Before then
    begin
      // A font that does not consume anything would make the loop endless
      Position := Before + 1;
    end;

    // Word spacing is for the single-byte code 32 only, in a simple font or in a composite font that has it as a one-byte code
    var WordSpacing: Single := 0;
    if ((Position - Before) = 1) and (Code = SpaceCode) then
    begin
      WordSpacing := TextState.WordSpacing;
    end;

    // Text space to device space
    var TextRenderingMatrix := Parameters.Multiply(TextMatrix).Multiply(State.CurrentTransformationMatrix);
    if Font.IsVertical then
    begin
      // The position vector gives the vertical origin from the horizontal one
      const Origin = Font.GetPositionVector(Code);
      TextRenderingMatrix.Translate(Origin.X, Origin.Y);
    end;

    const Displacement = Font.GetDisplacement(Code);

    CountGlyph;
    ShowGlyph(TextRenderingMatrix, Font, Code, Displacement);

    var Tx: Single;
    var Ty: Single;
    if Font.IsVertical then
    begin
      Tx := 0;
      Ty := Displacement.Y * FontSize + CharSpacing + WordSpacing;
    end
    else
    begin
      Tx := (Displacement.X * FontSize + CharSpacing + WordSpacing) * HorizontalScaling;
      Ty := 0;
    end;

    // The text matrix is read again: a subclass may have changed it while it showed the glyph
    if not State.TryGetTextMatrix(TextMatrix) then
    begin
      Exit;
    end;
    TextMatrix.Translate(Tx, Ty);
    State.SetTextMatrix(TextMatrix);
  end;
end;

procedure TPdfStreamEngine.ShowGlyph(const TextRenderingMatrix: TPdfMatrix; const Font: TPDFont; const Code: Integer; const Displacement: TPdfVector);
begin
end;

procedure TPdfStreamEngine.BeginMarkedContentSequence(const Tag: string; const Properties: TCosDictionary);
begin
end;

procedure TPdfStreamEngine.EndMarkedContentSequence;
begin
end;

procedure TPdfStreamEngine.SaveGraphicsState;
begin
  if FStack.Count >= Max(Options.MaxGraphicsStateDepth, 1) then
  begin
    // The Q that belongs to this q is ignored as well
    Inc(FIgnoredSaves);
    if not FIsDepthWarningGiven then
    begin
      FIsDepthWarningGiven := True;
      LogWarning('The graphics state stack is as deep as the limit of %d, further q operators are ignored', [Options.MaxGraphicsStateDepth]);
    end;
    Exit;
  end;

  FStack.Add(FStack.Last.Clone);
end;

function TPdfStreamEngine.CanRestoreGraphicsState: Boolean;
begin
  Result := ((FIgnoredSaves > 0) or (FStack.Count > 1));
end;

procedure TPdfStreamEngine.RestoreGraphicsState;
begin
  if FIgnoredSaves > 0 then
  begin
    Dec(FIgnoredSaves);
  end
  else if FStack.Count > 1 then
  begin
    FStack.Delete(FStack.Count - 1);
  end
  else
  begin
    raise EPdfEmptyGraphicsStackException.Create('Cannot execute restore, the graphics stack is empty');
  end;
end;

function TPdfStreamEngine.GraphicsStackSize: Integer;
begin
  Result := FStack.Count;
end;

function TPdfStreamEngine.GraphicsState: TPDGraphicsState;
begin
  if FStack.Count = 0 then
  begin
    raise EInvalidOpException.Create('There is no graphics state before ProcessPage');
  end;
  Result := FStack.Last;
end;

function TPdfStreamEngine.TryGetTextMatrix(out Matrix: TPdfMatrix): Boolean;
begin
  Result := GraphicsState.TryGetTextMatrix(Matrix);
end;

procedure TPdfStreamEngine.SetTextMatrix(const Matrix: TPdfMatrix);
begin
  GraphicsState.SetTextMatrix(Matrix);
end;

procedure TPdfStreamEngine.ClearTextMatrix;
begin
  GraphicsState.ClearTextMatrix;
end;

function TPdfStreamEngine.TryGetTextLineMatrix(out Matrix: TPdfMatrix): Boolean;
begin
  Result := GraphicsState.TryGetTextLineMatrix(Matrix);
end;

procedure TPdfStreamEngine.SetTextLineMatrix(const Matrix: TPdfMatrix);
begin
  GraphicsState.SetTextLineMatrix(Matrix);
end;

procedure TPdfStreamEngine.ClearTextLineMatrix;
begin
  GraphicsState.ClearTextLineMatrix;
end;

procedure TPdfStreamEngine.IncreaseLevel;
begin
  Inc(FLevel);
end;

procedure TPdfStreamEngine.DecreaseLevel;
begin
  Dec(FLevel);
  if FLevel < 0 then
  begin
    LogError('level is %d', [FLevel]);
  end;
end;

end.
