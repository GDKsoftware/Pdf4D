// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests for the hooks of Pdf4D.Content.StreamEngine that a renderer builds on
unit Pdf4D.Content.StreamEngine.Hooks.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Api.Document,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Api.DocumentModel.Interfaces,
  Pdf4D.Common.Defines,
  Pdf4D.Common.Log,
  Pdf4D.Common.Matrix,
  Pdf4D.Content.GraphicsState,
  Pdf4D.Content.Operator,
  Pdf4D.Content.Operators.DrawObject,
  Pdf4D.Content.Operators.State,
  Pdf4D.Content.Operators.Text,
  Pdf4D.Content.StreamEngine,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Font.Base,
  Pdf4D.Model.DocumentContext,
  Pdf4D.Model.FormXObject,
  Pdf4D.Model.Page,
  Pdf4D.Model.Rectangle,
  Pdf4D.Model.Tests.Support,
  Pdf4D.Tests.PdfBuilder;

type
  // A graphics state with a field of its own, to see that Clone keeps it
  TMarkedGraphicsState = class(TPDGraphicsState)
  public
    Marker: Integer;

    class var DestroyedCount: Integer;

    destructor Destroy; override;
    function Clone: TPDGraphicsState; override;
  end;

  TChildMode = (None, Plain, Failing, NilContent);

  TClipRecord = record
    Rect: TPdfRectangle;
    TranslateX: Single;
  end;

  TGlyphRecord = record
    IsMarked: Boolean;
    Marker: Integer;
    StackSize: Integer;
    ClassName: string;
  end;

  // Records what the hooks give and can be told what to do in them
  THookEngine = class(TPdfStreamEngine)
  private
    FOperatorsSeen: Integer;
    FStopAfter: Integer;
    FUseMarkedState: Boolean;
    FChildMode: TChildMode;
    FFormsSeen: Integer;
    FMaxLevelSeen: Integer;
    FClips: TList<TClipRecord>;
    FGlyphs: TList<TGlyphRecord>;
    FStackSizeAfterChild: Integer;
    FChildFailureSeen: Boolean;
    FNilContentRejected: Boolean;

    procedure RunChild(const Form: TPDFormXObject);

  protected
    function CreateInitialGraphicsState(const Page: TPDPage): TPDGraphicsState; override;
    function StopRequested: Boolean; override;
    procedure ClipToRect(const Rect: TPdfRectangle); override;

  public
    constructor Create;
    destructor Destroy; override;

    procedure ProcessOperator(const Operator: TContentOperator; const Operands: TArray<TCosBase>); override;
    procedure ShowForm(const Form: TPDFormXObject); override;
    procedure ShowGlyph(const TextRenderingMatrix: TPdfMatrix; const Font: TPDFont; const Code: Integer; const Displacement: TPdfVector); override;

    property OperatorsSeen: Integer read FOperatorsSeen;
    property StopAfter: Integer read FStopAfter write FStopAfter;
    property UseMarkedState: Boolean read FUseMarkedState write FUseMarkedState;
    property ChildMode: TChildMode read FChildMode write FChildMode;
    property FormsSeen: Integer read FFormsSeen;
    property MaxLevelSeen: Integer read FMaxLevelSeen;
    property Clips: TList<TClipRecord> read FClips;
    property Glyphs: TList<TGlyphRecord> read FGlyphs;
    property StackSizeAfterChild: Integer read FStackSizeAfterChild;
    property ChildFailureSeen: Boolean read FChildFailureSeen;
    property NilContentRejected: Boolean read FNilContentRejected;
  end;

  [TestFixture]
  TStreamEngineHooksTests = class
  private
    const FormObject = 20;
    const PageHeader = '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 10 0 R >> /XObject << %s >> >> >>';
    const HelveticaBody = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>';

  private
    FModels: TModelTestDocuments;
    FLines: TList<string>;
    FLog: TPdfLog;
    FContext: TPDDocumentContext;
    FPage: TPDPage;
    FEngine: THookEngine;
    FDocumentStream: TBytesStream;

    function NewBuilder(const Content: string; const FormCount: Integer): TTestPdfBuilder;
    procedure AddForm(const Builder: TTestPdfBuilder; const Index: Integer; const Dictionary, Content, Resources: string);
    procedure Run(const Builder: TTestPdfBuilder); overload;
    procedure Run(const Builder: TTestPdfBuilder; const Options: TPdfLoadOptions); overload;
    function HasLogLine(const Fragment: string): Boolean;
    function ChainResources(const NextIndex: Integer): string;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestInitialStateComesFromSubclass;

    [Test]
    procedure TestStopRequestedEndsPage;

    [Test]
    procedure TestClipToRectCalledForFormBBox;

    [Test]
    procedure TestNoClipWithoutBBox;

    [Test]
    procedure TestChildStreamRestoresStack;

    [Test]
    procedure TestChildStreamRestoresStackAfterException;

    [Test]
    procedure TestChildStreamCountsAgainstBudget;

    [Test]
    procedure TestChildStreamHonoursFormDepth;

    [Test]
    procedure TestChildStreamWithoutContentIsRejected;

    [Test]
    procedure TestDocumentExposesModel;
  end;

implementation

{ TMarkedGraphicsState }

destructor TMarkedGraphicsState.Destroy;
begin
  Inc(DestroyedCount);
  inherited;
end;

function TMarkedGraphicsState.Clone: TPDGraphicsState;
begin
  const Copy = TMarkedGraphicsState.Create;
  CopyBaseTo(Copy);
  Copy.Marker := Marker;
  Result := Copy;
end;

{ THookEngine }

constructor THookEngine.Create;
begin
  inherited Create;
  FClips := TList<TClipRecord>.Create;
  FGlyphs := TList<TGlyphRecord>.Create;
  TTextOperators.Register(Self);
  TStateOperators.Register(Self);
  TDrawObjectOperators.Register(Self);
end;

destructor THookEngine.Destroy;
begin
  FGlyphs.Free;
  FClips.Free;
  inherited;
end;

function THookEngine.CreateInitialGraphicsState(const Page: TPDPage): TPDGraphicsState;
begin
  if not FUseMarkedState then
  begin
    Exit(inherited CreateInitialGraphicsState(Page));
  end;

  const State = TMarkedGraphicsState.Create;
  State.Marker := 42;
  Result := State;
end;

function THookEngine.StopRequested: Boolean;
begin
  Result := ((FStopAfter > 0) and (FOperatorsSeen >= FStopAfter));
end;

procedure THookEngine.ClipToRect(const Rect: TPdfRectangle);
begin
  var Item: TClipRecord;
  Item.Rect := Rect;
  Item.TranslateX := GraphicsState.CurrentTransformationMatrix.TranslateX;
  FClips.Add(Item);
  if FChildMode = TChildMode.Failing then
  begin
    raise EPdfParseException.Create('Clip failed');
  end;
end;

procedure THookEngine.ProcessOperator(const Operator: TContentOperator; const Operands: TArray<TCosBase>);
begin
  Inc(FOperatorsSeen);
  inherited ProcessOperator(Operator, Operands);
end;

procedure THookEngine.ShowForm(const Form: TPDFormXObject);
begin
  Inc(FFormsSeen);
  FMaxLevelSeen := Level;
  if FChildMode = TChildMode.None then
  begin
    inherited ShowForm(Form);
    Exit;
  end;

  RunChild(Form);
end;

procedure THookEngine.RunChild(const Form: TPDFormXObject);
begin
  var Resources: TCosDictionary;
  if not Form.TryGetResources(Resources) then
  begin
    Resources := nil;
  end;

  var BBox: TPdfRectangle;
  const HasBBox = Form.TryGetBBox(BBox);
  const OuterDepth = GraphicsStackSize;
  const State = TMarkedGraphicsState.Create;
  State.Marker := 7;
  try
    if FChildMode = TChildMode.NilContent then
    begin
      ProcessChildStream(nil, Resources, State, Form.Matrix, HasBBox, BBox);
    end
    else
    begin
      ProcessChildStream(Form.Stream, Resources, State, Form.Matrix, HasBBox, BBox);
    end;
  except
    on EArgumentNilException do
    begin
      FNilContentRejected := True;
    end;
    on Failure: EPdfParseException do
    begin
      FChildFailureSeen := True;
    end;
  end;
  FStackSizeAfterChild := GraphicsStackSize - OuterDepth;
end;

procedure THookEngine.ShowGlyph(const TextRenderingMatrix: TPdfMatrix; const Font: TPDFont; const Code: Integer; const Displacement: TPdfVector);
begin
  var Item: TGlyphRecord;
  Item.IsMarked := (GraphicsState is TMarkedGraphicsState);
  Item.Marker := 0;
  if Item.IsMarked then
  begin
    Item.Marker := TMarkedGraphicsState(GraphicsState).Marker;
  end;
  Item.StackSize := GraphicsStackSize;
  Item.ClassName := GraphicsState.ClassName;
  FGlyphs.Add(Item);
end;

{ TStreamEngineHooksTests }

procedure TStreamEngineHooksTests.Setup;
begin
  FModels := TModelTestDocuments.Create;
  FLines := TList<string>.Create;
  FLog := TPdfLog.Create(
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      FLines.Add(Message);
    end);
  FEngine := THookEngine.Create;
end;

procedure TStreamEngineHooksTests.TearDown;
begin
  FreeAndNil(FDocumentStream);
  FreeAndNil(FEngine);
  FreeAndNil(FPage);
  FreeAndNil(FContext);
  FreeAndNil(FLog);
  FreeAndNil(FLines);
  FreeAndNil(FModels);
end;

function TStreamEngineHooksTests.NewBuilder(const Content: string; const FormCount: Integer): TTestPdfBuilder;
begin
  Result := TModelTestDocuments.NewBuilder('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  try
    const XObjects = TStringBuilder.Create;
    try
      for var Index := 0 to FormCount - 1 do
      begin
        XObjects.AppendFormat('/Fm%d %d 0 R ', [Index, FormObject + Index]);
      end;
      Result.AddObject(3, Format(PageHeader, [XObjects.ToString]));
    finally
      XObjects.Free;
    end;
    Result.AddStreamObject(4, '', TEncoding.ASCII.GetBytes(Content));
    Result.AddObject(10, HelveticaBody);
  except
    Result.Free;
    raise;
  end;
end;

procedure TStreamEngineHooksTests.AddForm(const Builder: TTestPdfBuilder; const Index: Integer; const Dictionary, Content, Resources: string);
begin
  var Entries := '/Type /XObject /Subtype /Form ' + Dictionary;
  if Resources <> '' then
  begin
    Entries := Entries + ' /Resources ' + Resources;
  end;
  Builder.AddStreamObject(FormObject + Index, Entries, TEncoding.ASCII.GetBytes(Content));
end;

function TStreamEngineHooksTests.ChainResources(const NextIndex: Integer): string;
begin
  Result := Format('<< /Font << /F1 10 0 R >> /XObject << /Fm1 %d 0 R >> >>', [FormObject + NextIndex]);
end;

procedure TStreamEngineHooksTests.Run(const Builder: TTestPdfBuilder);
begin
  Run(Builder, TPdfLoadOptions.Default);
end;

procedure TStreamEngineHooksTests.Run(const Builder: TTestPdfBuilder; const Options: TPdfLoadOptions);
begin
  try
    const Document = FModels.Open(Builder);
    FContext := TPDDocumentContext.Create(FLog, Options);
    FPage := TPDPage.Create(Document.Pages.Get(0).CosObject, FContext);
    FEngine.ProcessPage(FPage);
  finally
    Builder.Free;
  end;
end;

function TStreamEngineHooksTests.HasLogLine(const Fragment: string): Boolean;
begin
  Result := False;
  for var Line in FLines do
  begin
    Result := (Result or Line.Contains(Fragment));
  end;
end;

procedure TStreamEngineHooksTests.TestInitialStateComesFromSubclass;
begin
  FEngine.UseMarkedState := True;
  Run(NewBuilder('q BT /F1 12 Tf (A) Tj ET Q BT /F1 12 Tf (B) Tj ET', 0));

  Assert.AreEqual<Integer>(2, FEngine.Glyphs.Count);
  Assert.IsTrue(FEngine.Glyphs[0].IsMarked);
  Assert.AreEqual<Integer>(2, FEngine.Glyphs[0].StackSize);
  Assert.AreEqual<Integer>(42, FEngine.Glyphs[0].Marker);
  Assert.AreEqual<Integer>(1, FEngine.Glyphs[1].StackSize);
  Assert.AreEqual<Integer>(42, FEngine.Glyphs[1].Marker);
end;

procedure TStreamEngineHooksTests.TestStopRequestedEndsPage;
begin
  FEngine.StopAfter := 3;
  Run(NewBuilder('q BT /F1 12 Tf (A) Tj ET Q', 0));

  Assert.AreEqual<Integer>(3, FEngine.OperatorsSeen);
  Assert.AreEqual<Integer>(0, FEngine.Glyphs.Count);
  Assert.IsFalse(HasLogLine('stop'), string.Join('|', FLines.ToArray));
end;

procedure TStreamEngineHooksTests.TestClipToRectCalledForFormBBox;
begin
  const Builder = NewBuilder('/Fm0 Do', 1);
  AddForm(Builder, 0, '/BBox [0 0 10 10] /Matrix [1 0 0 1 50 0]', 'BT /F1 12 Tf (A) Tj ET', '');
  Run(Builder);

  Assert.AreEqual<Integer>(1, FEngine.Clips.Count);
  Assert.AreEqual<Single>(0, FEngine.Clips[0].Rect.LowerLeftX);
  Assert.AreEqual<Single>(10, FEngine.Clips[0].Rect.UpperRightX);
  Assert.AreEqual<Single>(10, FEngine.Clips[0].Rect.UpperRightY);
  Assert.AreEqual<Single>(50, FEngine.Clips[0].TranslateX);
  Assert.AreEqual<Integer>(1, FEngine.Glyphs.Count);
end;

procedure TStreamEngineHooksTests.TestNoClipWithoutBBox;
begin
  const Builder = NewBuilder('/Fm0 Do', 1);
  AddForm(Builder, 0, '', 'BT /F1 12 Tf (A) Tj ET', '');
  Run(Builder);

  Assert.AreEqual<Integer>(0, FEngine.Clips.Count);
  Assert.AreEqual<Integer>(1, FEngine.Glyphs.Count);
end;

procedure TStreamEngineHooksTests.TestChildStreamRestoresStack;
begin
  FEngine.ChildMode := TChildMode.Plain;
  const Builder = NewBuilder('q /Fm0 Do BT /F1 12 Tf (B) Tj ET Q', 1);
  AddForm(Builder, 0, '', 'q q BT /F1 12 Tf (A) Tj ET', '');
  Run(Builder);

  Assert.AreEqual<Integer>(2, FEngine.Glyphs.Count);
  Assert.IsTrue(FEngine.Glyphs[0].IsMarked);
  Assert.AreEqual<Integer>(7, FEngine.Glyphs[0].Marker);
  Assert.AreEqual<Integer>(3, FEngine.Glyphs[0].StackSize);
  Assert.AreEqual<Integer>(0, FEngine.StackSizeAfterChild);
  Assert.AreEqual<Integer>(2, FEngine.Glyphs[1].StackSize);
  Assert.IsFalse(FEngine.Glyphs[1].IsMarked);
end;

procedure TStreamEngineHooksTests.TestChildStreamRestoresStackAfterException;
begin
  FEngine.ChildMode := TChildMode.Failing;
  const Builder = NewBuilder('q /Fm0 Do BT /F1 12 Tf (B) Tj ET Q', 1);
  AddForm(Builder, 0, '/BBox [0 0 10 10]', 'BT /F1 12 Tf (A) Tj ET', '');
  Run(Builder);

  Assert.IsTrue(FEngine.ChildFailureSeen);
  Assert.AreEqual<Integer>(0, FEngine.StackSizeAfterChild);
  Assert.AreEqual<Integer>(1, FEngine.Glyphs.Count);
  Assert.AreEqual<Integer>(2, FEngine.Glyphs[0].StackSize);
end;

procedure TStreamEngineHooksTests.TestChildStreamWithoutContentIsRejected;
begin
  TMarkedGraphicsState.DestroyedCount := 0;
  FEngine.ChildMode := TChildMode.NilContent;
  const Builder = NewBuilder('q /Fm0 Do Q', 1);
  AddForm(Builder, 0, '', 'q Q', '');
  Run(Builder);

  Assert.IsTrue(FEngine.NilContentRejected);
  Assert.AreEqual<Integer>(1, TMarkedGraphicsState.DestroyedCount, 'The initial state is freed');
  Assert.AreEqual<Integer>(0, FEngine.StackSizeAfterChild);
end;

procedure TStreamEngineHooksTests.TestChildStreamCountsAgainstBudget;
begin
  FEngine.ChildMode := TChildMode.Plain;
  var Options := TPdfLoadOptions.Default;
  Options.MaxOperatorsPerPage := 8;
  const Builder = NewBuilder('/Fm0 Do BT /F1 12 Tf (B) Tj ET', 1);
  AddForm(Builder, 0, '', 'q Q q Q q Q q Q q Q q Q', '');
  Run(Builder, Options);

  Assert.IsTrue(HasLogLine('more than 8 operators'));
  Assert.AreEqual<Integer>(0, FEngine.Glyphs.Count);
  Assert.AreEqual<Integer>(8, FEngine.OperatorsSeen - 1);
end;

procedure TStreamEngineHooksTests.TestChildStreamHonoursFormDepth;
begin
  FEngine.ChildMode := TChildMode.Plain;
  const FormCount = 60;
  const Builder = NewBuilder('/Fm0 Do', FormCount);
  for var Index := 0 to FormCount - 1 do
  begin
    if Index < FormCount - 1 then
    begin
      AddForm(Builder, Index, '', 'BT /F1 12 Tf (A) Tj ET /Fm1 Do', ChainResources(Index + 1));
    end
    else
    begin
      AddForm(Builder, Index, '', 'BT /F1 12 Tf (A) Tj ET', ChainResources(Index));
    end;
  end;
  Run(Builder);

  Assert.AreEqual<Integer>(50, FEngine.Glyphs.Count);
  Assert.AreEqual<Integer>(50, FEngine.FormsSeen);
  Assert.IsTrue(HasLogLine('recursion is too deep'));
end;

procedure TStreamEngineHooksTests.TestDocumentExposesModel;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(3, '');
  try
    FDocumentStream := TBytesStream.Create(Builder.Build(TXrefStyle.Table));
    const Document = TPdfDocument.Load(FDocumentStream, TPdfLoadOptions.Default);
    var Model: IPdfDocumentModel;
    Assert.IsTrue(Supports(Document, IPdfDocumentModel, Model));
    Assert.AreEqual<Integer>(Document.PageCount, Model.ModelDocument.Pages.Count);
    Assert.AreEqual<Integer>(3, Model.ModelDocument.Pages.Count);
  finally
    Builder.Free;
  end;
end;

end.
