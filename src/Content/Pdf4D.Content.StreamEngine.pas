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
  Pdf4D.Model.Resources;

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
  // - q beyond the depth limit is ignored, and so is the Q that belongs to it.
  // The engine is not thread safe. It does not own the page.
  TPdfStreamEngine = class
  private
    type
      // What a nested stream replaces: the resources and the graphics stack
      TStreamFrame = record
        PreviousResources: TPDResources;
        CreatedResources: TPDResources;
        PreviousStack: TObjectList<TPDGraphicsState>;
        PreviousIgnoredSaves: Integer;
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

    procedure InitPage(const Page: TPDPage);
    function GetDefaultFont: TPDFont;
    function GetOptions: TPdfLoadOptions;

    procedure ProcessPageContent;
    function ReadPageContent: TBytes;
    function TryReadStreamData(const Stream: TCosStream; out Data: TBytes): Boolean;
    procedure ProcessForm(const Form: TPDFormXObject);
    procedure ProcessContent(const Data: TBytes; const Resources: TCosDictionary; const HasEmptyResources: Boolean; const Matrix: TPdfMatrix);
    procedure ProcessStreamOperators(const Data: TBytes);
    procedure ProcessOperators(const Parser: TObject);
    function TryReadToken(const Parser: TObject; out Token: TObject): Boolean;

    function BeginFrame(const StreamResources: TCosDictionary; const HasEmptyResources: Boolean): TStreamFrame;
    procedure EndFrame(const Frame: TStreamFrame);

    procedure CountOperator;
    procedure CountGlyph;
    function TryHandleOperatorFailure(const Operator: TContentOperator; const Operands: TArray<TCosBase>; const Failure: Exception): Boolean;

    function IsVerticalFont(const Font: TPDFont): Boolean;
    function GetTextMatrixOrRaise: TPdfMatrix;

  protected
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

    procedure ShowTransparencyGroup(const Form: TPDFormXObject);
    procedure ShowForm(const Form: TPDFormXObject);

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
  end;

implementation

uses
  System.Classes,
  System.Math,
  Pdf4D.Common.FloatGuard,
  Pdf4D.Content.OperatorProcessor,
  Pdf4D.Cos.Number,
  Pdf4D.Cos.PdfString,
  Pdf4D.Font.Factory,
  Pdf4D.Parser.ContentStream;

{ TPdfStreamEngine }

constructor TPdfStreamEngine.Create;
begin
  inherited Create;
  FProcessors := TObjectDictionary<string, TOperatorProcessorBase>.Create([doOwnsValues]);
  FStack := TObjectList<TPDGraphicsState>.Create(True);
  FActiveStreams := TList<TCosStream>.Create;
end;

destructor TPdfStreamEngine.Destroy;
begin
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
  FStack.Add(TPDGraphicsState.Create);
  FIgnoredSaves := 0;
  FIsDepthWarningGiven := False;
  FResources := nil;
  FActiveStreams.Clear;
  FLevel := 0;
  FOperatorCount := 0;
  FGlyphCount := 0;
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
    if Page.HasContents then
    begin
      try
        ProcessPageContent;
      except
        on Failure: EPdfLimitExceededException do
        begin
          LogError('Processing of the page stopped, the text so far is kept: %s', [Failure.Message]);
        end;
      end;
    end;
  finally
    TPdfFloatGuard.Leave(PreviousMask);
  end;
end;

procedure TPdfStreamEngine.ProcessPageContent;
begin
  const Data = ReadPageContent;
  ProcessContent(Data, nil, False, TPdfMatrix.Identity);
end;

function TPdfStreamEngine.ReadPageContent: TBytes;
begin
  Result := nil;
  for var Stream in FCurrentPage.ContentStreams do
  begin
    var Data: TBytes;
    if TryReadStreamData(Stream, Data) then
    begin
      // PDFBox puts a line feed between the streams of /Contents: an operator may not run into the next stream
      Result := Result + Data + [ContentSeparator];
    end;
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
  ProcessForm(Form);
end;

procedure TPdfStreamEngine.ShowForm(const Form: TPDFormXObject);
begin
  ProcessForm(Form);
end;

procedure TPdfStreamEngine.ProcessForm(const Form: TPDFormXObject);
begin
  if not Assigned(FCurrentPage) then
  begin
    raise EInvalidOpException.Create('No current page, call ProcessPage instead');
  end;

  // PDFBox only has the depth limit. A form that draws itself would use up all the depth, 50 times over at every level.
  if FActiveStreams.Contains(Form.Stream) then
  begin
    LogWarning('Form XObject draws itself (recursion), skipped', []);
    Exit;
  end;

  var Data: TBytes;
  if not TryReadStreamData(Form.Stream, Data) then
  begin
    Exit;
  end;

  var FormResources: TCosDictionary;
  if not Form.TryGetResources(FormResources) then
  begin
    FormResources := nil;
  end;

  FActiveStreams.Add(Form.Stream);
  try
    ProcessContent(Data, FormResources, Form.HasEmptyResources, Form.Matrix);
  finally
    FActiveStreams.Delete(FActiveStreams.Count - 1);
  end;
end;

function TPdfStreamEngine.BeginFrame(const StreamResources: TCosDictionary; const HasEmptyResources: Boolean): TStreamFrame;
begin
  Result := Default(TStreamFrame);
  Result.PreviousResources := FResources;
  // Resource lookup: the resources of the stream, else those of the parent stream (not in the PDF specification, but
  // PDFBOX-1359 does it and Acrobat copes), else those of the page
  if Assigned(StreamResources) then
  begin
    Result.CreatedResources := TPDResources.Create(StreamResources, FCurrentPage.Context);
    FResources := Result.CreatedResources;
  end
  else if HasEmptyResources then
  begin
    Result.CreatedResources := TPDResources.Create(nil, FCurrentPage.Context);
    FResources := Result.CreatedResources;
  end
  else if not Assigned(FResources) then
  begin
    FResources := FCurrentPage.Resources;
  end;

  // saveGraphicsStack: the stream runs on a stack of its own that starts with a copy of the current state
  Result.PreviousStack := FStack;
  Result.PreviousIgnoredSaves := FIgnoredSaves;
  FStack := TObjectList<TPDGraphicsState>.Create(True);
  FStack.Add(Result.PreviousStack.Last.Clone);
  FIgnoredSaves := 0;
end;

procedure TPdfStreamEngine.EndFrame(const Frame: TStreamFrame);
begin
  FStack.Free;
  FStack := Frame.PreviousStack;
  FIgnoredSaves := Frame.PreviousIgnoredSaves;
  FResources := Frame.PreviousResources;
  Frame.CreatedResources.Free;
end;

procedure TPdfStreamEngine.ProcessContent(const Data: TBytes; const Resources: TCosDictionary; const HasEmptyResources: Boolean; const Matrix: TPdfMatrix);
begin
  const Frame = BeginFrame(Resources, HasEmptyResources);
  try
    var Ctm := GraphicsState.CurrentTransformationMatrix;
    Ctm.ConcatenateWith(Matrix);
    GraphicsState.CurrentTransformationMatrix := Ctm;
    ProcessStreamOperators(Data);
  finally
    EndFrame(Frame);
  end;
end;

procedure TPdfStreamEngine.ProcessStreamOperators(const Data: TBytes);
begin
  const Parser = TPdfStreamParser.Create(Data, Options, FCurrentPage.Context.Log);
  try
    ProcessOperators(Parser);
  finally
    // The operands that point into the pool of the parser are gone by now
    Parser.Free;
  end;
end;

function TPdfStreamEngine.TryReadToken(const Parser: TObject; out Token: TObject): Boolean;
begin
  Token := nil;
  Result := True;
  try
    Token := TPdfStreamParser(Parser).ParseNextToken;
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

procedure TPdfStreamEngine.ProcessOperators(const Parser: TObject);
begin
  // The tokens are made one at a time: a large stream is never held in memory as a list of tokens
  const Operands = TObjectList<TObject>.Create(True);
  try
    var Token: TObject;
    while TryReadToken(Parser, Token) and Assigned(Token) do
    begin
      if Token is TContentOperator then
      begin
        try
          var Values: TArray<TCosBase>;
          SetLength(Values, Operands.Count);
          for var Index := 0 to Operands.Count - 1 do
          begin
            Values[Index] := TCosBase(Operands[Index]);
          end;
          ProcessOperator(TContentOperator(Token), Values);
        finally
          Token.Free;
          Operands.Clear;
        end;
      end
      else if Token is TCosBase then
      begin
        Operands.Add(Token);
      end
      else
      begin
        Token.Free;
      end;
    end;
  finally
    Operands.Free;
  end;
end;

procedure TPdfStreamEngine.CountOperator;
begin
  Inc(FOperatorCount);
  if FOperatorCount > Options.MaxOperatorsPerPage then
  begin
    raise EPdfLimitExceededException.CreateFmt('The page has more than %d operators', [Options.MaxOperatorsPerPage]);
  end;
end;

procedure TPdfStreamEngine.CountGlyph;
begin
  if FGlyphCount >= Options.MaxGlyphsPerPage then
  begin
    raise EPdfLimitExceededException.CreateFmt('The page has more than %d glyphs', [Options.MaxGlyphsPerPage]);
  end;
  Inc(FGlyphCount);
end;

procedure TPdfStreamEngine.ProcessOperator(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  CountOperator;

  var Processor: TOperatorProcessorBase;
  if not FProcessors.TryGetValue(Operator.Name, Processor) then
  begin
    UnsupportedOperator(Operator, Operands);
    Exit;
  end;

  try
    Processor.Process(Operator, Operands);
  except
    on Failure: EPdfLimitExceededException do
    begin
      raise;
    end;
    on Failure: Exception do
    begin
      if not TryHandleOperatorFailure(Operator, Operands, Failure) then
      begin
        // A mistake in the library, not in the file
        raise;
      end;
    end;
  end;
end;

function TPdfStreamEngine.TryHandleOperatorFailure(const Operator: TContentOperator; const Operands: TArray<TCosBase>; const Failure: Exception): Boolean;
begin
  Result := True;
  if Failure is EPdfException then
  begin
    OperatorException(Operator, Operands, EPdfException(Failure));
  end
  else if TPdfFailure.IsInputFailure(Failure) then
  begin
    LogError('Operator %s failed: %s', [Operator.Name, Failure.Message]);
  end
  else
  begin
    Result := False;
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
