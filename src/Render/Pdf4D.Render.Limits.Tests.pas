// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of the limits of the renderer against hostile files: every limit holds, and every limit can be set
unit Pdf4D.Render.Limits.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  System.SysUtils,
  System.Diagnostics,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Common.Defines,
  Pdf4D.Common.Matrix,
  Pdf4D.Common.Path,
  Pdf4D.Render.Bitmap,
  Pdf4D.Render.Device.Interfaces,
  Pdf4D.Render.Options,
  Pdf4D.Render.Renderer.Interfaces,
  Pdf4D.Tests.GraphicsDocuments,
  Pdf4D.Tests.PdfBuilder,
  Pdf4D.Tests.RecordingDevice;

type
  {$SCOPEDENUMS ON}
  TChainKind = (Form, Type3, Pattern, SoftMask, Group);
  {$SCOPEDENUMS OFF}

  // The pixels of the layers that are alive, and the most that were alive at once
  TLayerMeter = class
  private
    FLivePixels: Int64;
    FPeakPixels: Int64;

  public
    procedure Add(const Pixels: Int64);
    procedure Remove(const Pixels: Int64);

    property PeakPixels: Int64 read FPeakPixels;
  end;

  // Draws nothing; its layers tell the meter how many pixels are alive
  TMeteredDevice = class(TInterfacedObject, IPdfRasterDevice)
  private
    FWidth: Integer;
    FHeight: Integer;
    FMeter: TLayerMeter;
    FIsLayer: Boolean;

  public
    constructor Create(const Width, Height: Integer; const Meter: TLayerMeter; const IsLayer: Boolean);
    destructor Destroy; override;

    function Width: Integer;
    function Height: Integer;
    procedure SetClip(const Clip: IPdfClipPath);
    procedure FillPath(const Path: TPdfPath; const Transform: TPdfMatrix; const FillRule: TPdfFillRule; const Paint: TPdfPaint;
                       const Composite: TPdfComposite);
    procedure StrokePath(const Path: TPdfPath; const Transform: TPdfMatrix; const Stroke: TPdfStrokeStyle; const Paint: TPdfPaint;
                         const Composite: TPdfComposite);
    procedure DrawBitmap(const Bitmap: TPdfBitmap; const BitmapToDevice: TPdfMatrix; const Filter: TPdfImageFilter;
                         const Composite: TPdfComposite);
    procedure Clear(const Color: TPdfDeviceColor);
    function CreateLayer(const Width, Height: Integer): IPdfRasterDevice;
    function TryReadPixels(const Area: TRect; out Bitmap: TPdfBitmap): Boolean;
    function ToBitmap: TPdfBitmap;
  end;

  TMeteredBackend = class(TInterfacedObject, IPdfRenderBackend)
  private
    FMeter: TLayerMeter;

  public
    constructor Create(const Meter: TLayerMeter);

    function Name: string;
    function CreateRasterDevice(const Width, Height: Integer): IPdfRasterDevice;
  end;

  [TestFixture]
  TRenderLimitTests = class
  private
    const ChainLength = 100;
    const ConfiguredDepth = 2;
    const GroupBox = '/BBox [0 0 100 100]';
    const GroupHead = '/Type /XObject /Subtype /Form /BBox [0 0 100 100] /Group << /S /Transparency /CS /DeviceGray >>';
    const WhiteSquare = '1 g 0 0 100 100 re f';
    const FirstState = 20;
    const FirstGlyph = 65;
    const FirstGlyphObject = 30;

  private
    FDocuments: TGraphicsDocuments;
    FDocument: IPdfDocument;
    FRenderer: IPdfRenderer;
    FDevice: TRecordingDevice;
    FDeviceReference: IPdfRasterDevice;

    procedure RenderBuilder(const Builder: TTestPdfBuilder; const Options: TPdfRenderOptions; const LoadOptions: TPdfLoadOptions);
    procedure RenderChain(const Kind: TChainKind; const Options: TPdfRenderOptions; const LoadOptions: TPdfLoadOptions);
    function CountLogLines(const Fragment: string): Integer;
    function FillCount: Integer;
    function LayerDepth(const UseLastLayer: Boolean): Integer;
    function WarningFragmentOf(const Kind: TChainKind; const Limit: Integer): string;
    function ExpectedDepthOf(const Kind: TChainKind; const Limit: Integer): Integer;
    procedure CheckChain(const Kind: TChainKind; const Limit: Integer; const Options: TPdfRenderOptions; const LoadOptions: TPdfLoadOptions);
    procedure AssertAllChains(const Options: TPdfRenderOptions; const LoadOptions: TPdfLoadOptions; const Limits: array of Integer);

    function FormChain: TTestPdfBuilder;
    function GroupChain: TTestPdfBuilder;
    function SoftMaskChain: TTestPdfBuilder;
    function PatternChain: TTestPdfBuilder;
    function Type3Chain: TTestPdfBuilder;
    function TilingPage(const Content: string): TTestPdfBuilder;
    function FanOutForms(const FormCount: Integer): TTestPdfBuilder;
    function MeshShadingPage(const FillCount: Integer): TTestPdfBuilder;
    function AnnotationPage(const AnnotationCount: Integer): TTestPdfBuilder;
    class function CompressedBytes(const Data: TBytes): TBytes; static;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestAllDepthLimitsHold;

    [Test]
    procedure TestDepthLimitsAreConfigurable;

    [Test]
    procedure TestImagePixelLimitIsConfigurable;

    [Test]
    procedure TestRenderPixelLimitIsConfigurable;

    [Test]
    procedure TestTilingCellLimitIsConfigurable;

    [Test]
    procedure TestTileEdgeLimitIsConfigurable;

    [Test]
    procedure TestAnnotationLimitIsConfigurable;

    [Test]
    procedure TestFormFanOutRespectsOperatorBudget;

    [Test]
    procedure TestManyTransparencyGroupsBoundMemory;

    [Test]
    procedure TestMeshShadingWorkIsBoundedForTheWholePage;

    [Test]
    procedure TestShadingWorkLimitIsConfigurable;
  end;

implementation

uses
  System.Classes,
  System.Math,
  System.TypInfo,
  System.ZLib,
  Pdf4D.Render.Renderer;

const
  TimeLimitMilliseconds = 5000;

{ TLayerMeter }

procedure TLayerMeter.Add(const Pixels: Int64);
begin
  Inc(FLivePixels, Pixels);
  FPeakPixels := Max(FPeakPixels, FLivePixels);
end;

procedure TLayerMeter.Remove(const Pixels: Int64);
begin
  Dec(FLivePixels, Pixels);
end;

{ TMeteredDevice }

constructor TMeteredDevice.Create(const Width, Height: Integer; const Meter: TLayerMeter; const IsLayer: Boolean);
begin
  inherited Create;
  FWidth := Width;
  FHeight := Height;
  FMeter := Meter;
  FIsLayer := IsLayer;
  if FIsLayer then
  begin
    FMeter.Add(Int64(Width) * Height);
  end;
end;

destructor TMeteredDevice.Destroy;
begin
  if FIsLayer then
  begin
    FMeter.Remove(Int64(FWidth) * FHeight);
  end;
  inherited;
end;

function TMeteredDevice.Width: Integer;
begin
  Result := FWidth;
end;

function TMeteredDevice.Height: Integer;
begin
  Result := FHeight;
end;

procedure TMeteredDevice.SetClip(const Clip: IPdfClipPath);
begin
end;

procedure TMeteredDevice.FillPath(const Path: TPdfPath; const Transform: TPdfMatrix; const FillRule: TPdfFillRule; const Paint: TPdfPaint;
                                  const Composite: TPdfComposite);
begin
end;

procedure TMeteredDevice.StrokePath(const Path: TPdfPath; const Transform: TPdfMatrix; const Stroke: TPdfStrokeStyle; const Paint: TPdfPaint;
                                    const Composite: TPdfComposite);
begin
end;

procedure TMeteredDevice.DrawBitmap(const Bitmap: TPdfBitmap; const BitmapToDevice: TPdfMatrix; const Filter: TPdfImageFilter;
                                    const Composite: TPdfComposite);
begin
end;

procedure TMeteredDevice.Clear(const Color: TPdfDeviceColor);
begin
end;

function TMeteredDevice.CreateLayer(const Width, Height: Integer): IPdfRasterDevice;
begin
  Result := TMeteredDevice.Create(Width, Height, FMeter, True);
end;

function TMeteredDevice.TryReadPixels(const Area: TRect; out Bitmap: TPdfBitmap): Boolean;
begin
  Bitmap := nil;
  Result := False;
end;

function TMeteredDevice.ToBitmap: TPdfBitmap;
begin
  Result := TPdfBitmap.Create(FWidth, FHeight);
end;

{ TMeteredBackend }

constructor TMeteredBackend.Create(const Meter: TLayerMeter);
begin
  inherited Create;
  FMeter := Meter;
end;

function TMeteredBackend.Name: string;
begin
  Result := 'Metered';
end;

function TMeteredBackend.CreateRasterDevice(const Width, Height: Integer): IPdfRasterDevice;
begin
  Result := TMeteredDevice.Create(Width, Height, FMeter, False);
end;

{ TRenderLimitTests }

class function TRenderLimitTests.CompressedBytes(const Data: TBytes): TBytes;
begin
  ZCompress(Data, Result);
end;

procedure TRenderLimitTests.Setup;
begin
  FDocuments := TGraphicsDocuments.Create;
  FDevice := TRecordingDevice.Create(TGraphicsDocuments.PageSize, TGraphicsDocuments.PageSize);
  FDeviceReference := FDevice;
end;

procedure TRenderLimitTests.TearDown;
begin
  FDeviceReference := nil;
  FRenderer := nil;
  FDocument := nil;
  FreeAndNil(FDocuments);
end;

procedure TRenderLimitTests.RenderBuilder(const Builder: TTestPdfBuilder; const Options: TPdfRenderOptions; const LoadOptions: TPdfLoadOptions);
begin
  FDocument := FDocuments.Open(Builder, LoadOptions);
  FRenderer := TPdfRenderer.Create(FDocument, TRecordingBackend.Create);
  var Params := TPdfRenderParams.Create(1);
  Params.Options := Options;

  const Status = FRenderer.RenderPage(0, FDeviceReference, Params);

  Assert.AreEqual(TPdfRenderStatus.Completed, Status);
end;

procedure TRenderLimitTests.RenderChain(const Kind: TChainKind; const Options: TPdfRenderOptions; const LoadOptions: TPdfLoadOptions);
begin
  var Builder: TTestPdfBuilder;
  case Kind of
    TChainKind.Form     : Builder := FormChain;
    TChainKind.Type3    : Builder := Type3Chain;
    TChainKind.Pattern  : Builder := PatternChain;
    TChainKind.SoftMask : Builder := SoftMaskChain;
    TChainKind.Group    : Builder := GroupChain;
  else
    raise EArgumentOutOfRangeException.Create('Unknown chain kind');
  end;

  try
    RenderBuilder(Builder, Options, LoadOptions);
  finally
    Builder.Free;
  end;
end;

function TRenderLimitTests.CountLogLines(const Fragment: string): Integer;
begin
  Result := 0;
  for var Line in FDocuments.LogLines do
  begin
    if Line.Contains(Fragment) then
    begin
      Inc(Result);
    end;
  end;
end;

function TRenderLimitTests.FillCount: Integer;
begin
  Result := 0;
  for var Call in FDevice.Calls do
  begin
    if Call.Kind = TRecordedCallKind.Fill then
    begin
      Inc(Result);
    end;
  end;
end;

function TRenderLimitTests.LayerDepth(const UseLastLayer: Boolean): Integer;
begin
  Result := 0;
  var Device := FDevice;
  while Device.LayerCount > 0 do
  begin
    Inc(Result);
    if UseLastLayer then
    begin
      Device := Device.Layers[Device.LayerCount - 1];
    end
    else
    begin
      Device := Device.Layers[0];
    end;
  end;
end;

function TRenderLimitTests.WarningFragmentOf(const Kind: TChainKind; const Limit: Integer): string;
begin
  case Kind of
    TChainKind.Form     : Result := 'recursion is too deep';
    TChainKind.Type3    : Result := Format('Type 3 glyphs are nested as deep as the limit of %d,', [Limit]);
    TChainKind.Pattern  : Result := Format('Patterns are nested as deep as the limit of %d,', [Limit]);
    TChainKind.SoftMask : Result := Format('Soft masks are nested as deep as the limit of %d,', [Limit]);
    TChainKind.Group    : Result := Format('Transparency groups are nested as deep as the limit of %d,', [Limit]);
  else
    raise EArgumentOutOfRangeException.Create('Unknown chain kind');
  end;
end;

// The layers (cells, soft masks, groups) that lie inside each other when the chain stops; a chain of forms or glyphs has no layers,
// and nothing of it is painted
function TRenderLimitTests.ExpectedDepthOf(const Kind: TChainKind; const Limit: Integer): Integer;
begin
  if Kind in [TChainKind.Form, TChainKind.Type3] then
  begin
    Result := 0;
  end
  else
  begin
    Result := Limit;
  end;
end;

procedure TRenderLimitTests.CheckChain(const Kind: TChainKind; const Limit: Integer; const Options: TPdfRenderOptions;
                                       const LoadOptions: TPdfLoadOptions);
begin
  const Name = GetEnumName(TypeInfo(TChainKind), Ord(Kind));
  const Watch = TStopwatch.StartNew;

  // A group or a soft mask is a form too: its chain meets the limit of the forms first when that one is lowered
  var ChainLoadOptions := TPdfLoadOptions.Default;
  if Kind = TChainKind.Form then
  begin
    ChainLoadOptions := LoadOptions;
  end;

  RenderChain(Kind, Options, ChainLoadOptions);

  Assert.IsTrue(Watch.ElapsedMilliseconds < TimeLimitMilliseconds, Format('%s took %d ms', [Name, Watch.ElapsedMilliseconds]));
  Assert.AreEqual<Integer>(1, CountLogLines(WarningFragmentOf(Kind, Limit)), Format('one warning for %s: %s', [Name, string.Join(' / ', FDocuments.LogLines.ToArray)]));
  Assert.AreEqual<Integer>(ExpectedDepthOf(Kind, Limit), LayerDepth(Kind = TChainKind.SoftMask), Format('depth of %s', [Name]));
  if Kind in [TChainKind.Form, TChainKind.Type3] then
  begin
    Assert.AreEqual<Integer>(0, FillCount, Format('the end of the %s chain is not reached', [Name]));
  end;
end;

procedure TRenderLimitTests.AssertAllChains(const Options: TPdfRenderOptions; const LoadOptions: TPdfLoadOptions; const Limits: array of Integer);
begin
  var Index := 0;
  for var Kind := Low(TChainKind) to High(TChainKind) do
  begin
    TearDown;
    Setup;
    CheckChain(Kind, Limits[Index], Options, LoadOptions);
    Inc(Index);
  end;
end;

// Object 5 + Index draws object 5 + Index + 1; the last one draws a rectangle
function TRenderLimitTests.FormChain: TTestPdfBuilder;
begin
  Result := TGraphicsDocuments.NewBuilder(TEncoding.ASCII.GetBytes('/G1 Do'), '/XObject << /G1 5 0 R >>');
  try
    for var Index := 0 to ChainLength - 1 do
    begin
      var Content := '0 0 1 rg 0 0 10 10 re f';
      var Resources := '';
      if Index < ChainLength - 1 then
      begin
        Content := '/G1 Do';
        Resources := Format('/Resources << /XObject << /G1 %d 0 R >> >>', [5 + Index + 1]);
      end;
      Result.AddStreamObject(5 + Index, Format('/Type /XObject /Subtype /Form %s %s', [GroupBox, Resources]), TEncoding.ASCII.GetBytes(Content));
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TRenderLimitTests.GroupChain: TTestPdfBuilder;
begin
  Result := TGraphicsDocuments.NewBuilder(TEncoding.ASCII.GetBytes('/G1 Do'), '/XObject << /G1 5 0 R >>');
  try
    for var Index := 0 to ChainLength - 1 do
    begin
      var Content := '0 0 1 rg 0 0 10 10 re f';
      var Resources := '';
      if Index < ChainLength - 1 then
      begin
        Content := '/G1 Do';
        Resources := Format('/Resources << /XObject << /G1 %d 0 R >> >>', [5 + Index + 1]);
      end;
      Result.AddStreamObject(5 + Index, Format('/Type /XObject /Subtype /Form %s /Group << /S /Transparency /I true >> %s', [GroupBox, Resources]),
                             TEncoding.ASCII.GetBytes(Content));
    end;
  except
    Result.Free;
    raise;
  end;
end;

// Every group sets the soft mask of the next one
function TRenderLimitTests.SoftMaskChain: TTestPdfBuilder;
begin
  Result := TGraphicsDocuments.NewBuilder(TEncoding.ASCII.GetBytes('/GsMask gs 0 0 1 rg 20 20 50 50 re f'),
                                          Format('/ExtGState << /GsMask %d 0 R >>', [FirstState]));
  try
    for var Index := 0 to ChainLength - 1 do
    begin
      const StateObject = FirstState + 2 * Index;
      const GroupObject = StateObject + 1;
      Result.AddObject(StateObject, Format('<< /Type /ExtGState /SMask << /Type /Mask /S /Luminosity /G %d 0 R >> >>', [GroupObject]));
      const NextResources = Format('/Resources << /ExtGState << /GsMask %d 0 R >> >>', [StateObject + 2]);
      Result.AddStreamObject(GroupObject, GroupHead + ' ' + NextResources, TEncoding.ASCII.GetBytes('/GsMask gs ' + WhiteSquare));
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TRenderLimitTests.PatternChain: TTestPdfBuilder;
begin
  Result := TGraphicsDocuments.NewBuilder(TEncoding.ASCII.GetBytes('/Pattern cs /P1 scn 0 0 100 100 re f'), '/Pattern << /P1 5 0 R >>');
  try
    for var Index := 0 to ChainLength - 1 do
    begin
      const Entries = Format('/Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 /BBox [0 0 10 10] /XStep 10 /YStep 10 ' +
                             '/Resources << /Pattern << /P1 %d 0 R >> >>', [5 + Index + 1]);
      Result.AddStreamObject(5 + Index, Entries, TEncoding.ASCII.GetBytes('0 0 1 rg 0 0 3 3 re f /Pattern cs /P1 scn 0 0 10 10 re f'));
    end;
  except
    Result.Free;
    raise;
  end;
end;

// Glyph A shows B, B shows C and so on; the last glyph draws a rectangle
function TRenderLimitTests.Type3Chain: TTestPdfBuilder;
begin
  const Names = TStringBuilder.Create;
  const Widths = TStringBuilder.Create;
  const Procs = TStringBuilder.Create;
  Result := TGraphicsDocuments.NewBuilder(TEncoding.ASCII.GetBytes(Format('BT /F1 10 Tf 100 100 Td <%.2x> Tj ET', [FirstGlyph])), '/Font << /F1 5 0 R >>');
  try
    try
    for var Index := 0 to ChainLength - 1 do
    begin
      Names.AppendFormat('/g%d ', [Index]);
      Widths.Append('50 ');
      Procs.AppendFormat('/g%d %d 0 R ', [Index, FirstGlyphObject + Index]);
      var Content := '0 0 40 40 re f';
      if Index < ChainLength - 1 then
      begin
        Content := Format('BT /F1 1 Tf <%.2x> Tj ET', [FirstGlyph + Index + 1]);
      end;
      Result.AddStreamObject(FirstGlyphObject + Index, '', TEncoding.ASCII.GetBytes(Content));
    end;
    Result.AddObject(5, Format('<< /Type /Font /Subtype /Type3 /FontBBox [0 0 100 100] /FontMatrix [0.01 0 0 0.01 0 0] /FirstChar %d /LastChar %d ' +
                               '/Widths [%s] /Encoding << /Differences [%d %s] >> /CharProcs << %s >> /Resources << /Font << /F1 5 0 R >> >> >>',
                               [FirstGlyph, FirstGlyph + ChainLength - 1, Widths.ToString, FirstGlyph, Names.ToString, Procs.ToString]));
    except
      Result.Free;
      raise;
    end;
  finally
    Procs.Free;
    Widths.Free;
    Names.Free;
  end;
end;

function TRenderLimitTests.TilingPage(const Content: string): TTestPdfBuilder;
begin
  Result := TGraphicsDocuments.NewBuilder(TEncoding.ASCII.GetBytes(Content), '/Pattern << /P1 5 0 R >>');
  try
    Result.AddStreamObject(5, '/Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 /BBox [0 0 10 10] /XStep 10 /YStep 10 /Resources << >>',
                           TEncoding.ASCII.GetBytes('1 0 0 rg 0 0 5 5 re f'));
  except
    Result.Free;
    raise;
  end;
end;

// The fan-out of the stream engine: every form draws the next one twice
function TRenderLimitTests.FanOutForms(const FormCount: Integer): TTestPdfBuilder;
begin
  Result := TGraphicsDocuments.NewBuilder(TEncoding.ASCII.GetBytes('/Fm0 Do'), '/XObject << /Fm0 5 0 R >>');
  try
    for var Index := 0 to FormCount - 1 do
    begin
      var Content := '0 0 1 rg 0 0 1 1 re f';
      var Resources := '';
      if Index < FormCount - 1 then
      begin
        Content := '0 0 1 rg 0 0 1 1 re f /Fm0 Do /Fm0 Do';
        Resources := Format('/Resources << /XObject << /Fm0 %d 0 R >> >>', [5 + Index + 1]);
      end;
      Result.AddStreamObject(5 + Index, Format('/Type /XObject /Subtype /Form %s %s', [GroupBox, Resources]), TEncoding.ASCII.GetBytes(Content));
    end;
  except
    Result.Free;
    raise;
  end;
end;

// One small compressed type 4 shading in a shading pattern, which paints FillCount rectangles
function TRenderLimitTests.MeshShadingPage(const FillCount: Integer): TTestPdfBuilder;
begin
  const Content = TStringBuilder.Create;
  try
    Content.Append('/Pattern cs /P1 scn');
    for var Index := 1 to FillCount do
    begin
      Content.Append(' 0 0 100 100 re f');
    end;
    Result := TGraphicsDocuments.NewBuilder(TEncoding.ASCII.GetBytes(Content.ToString), '/Pattern << /P1 << /PatternType 2 /Shading 7 0 R >> >>');
  finally
    Content.Free;
  end;

  try
    const Mesh: TBytes = [0, 0, 0, 255, 0, 0,
                          0, 255, 0, 0, 255, 0,
                          0, 0, 255, 0, 0, 255];
    Result.AddStreamObject(7, '/ShadingType 4 /ColorSpace /DeviceRGB /BitsPerCoordinate 8 /BitsPerComponent 8 /BitsPerFlag 8 ' +
                              '/Decode [0 255 0 255 0 1 0 1 0 1] /Filter /FlateDecode', CompressedBytes(Mesh));
  except
    Result.Free;
    raise;
  end;
end;

function TRenderLimitTests.AnnotationPage(const AnnotationCount: Integer): TTestPdfBuilder;
begin
  const References = TStringBuilder.Create;
  try
    for var Index := 1 to AnnotationCount do
    begin
      References.Append('5 0 R ');
    end;
    Result := TGraphicsDocuments.NewBuilder(TEncoding.ASCII.GetBytes(''), '', Format('/Annots [%s]', [References.ToString]));
  finally
    References.Free;
  end;

  try
    Result.AddObject(5, '<< /Type /Annot /Subtype /Square /Rect [100 100 120 120] /AP << /N 20 0 R >> >>');
    Result.AddStreamObject(20, '/Type /XObject /Subtype /Form /BBox [0 0 20 20]', TEncoding.ASCII.GetBytes('0 0 20 20 re f'));
  except
    Result.Free;
    raise;
  end;
end;

procedure TRenderLimitTests.TestAllDepthLimitsHold;
begin
  // Form, Type 3, pattern, soft mask, group
  AssertAllChains(TPdfRenderOptions.Default, TPdfLoadOptions.Default,
                  [DefaultMaxFormXObjectDepth, DefaultMaxType3Depth, DefaultMaxPatternDepth, DefaultMaxSoftMaskDepth, DefaultMaxTransparencyGroupDepth]);
end;

procedure TRenderLimitTests.TestDepthLimitsAreConfigurable;
begin
  var Options := TPdfRenderOptions.Default;
  Options.MaxType3Depth := ConfiguredDepth;
  Options.MaxPatternDepth := ConfiguredDepth;
  Options.MaxSoftMaskDepth := ConfiguredDepth;
  Options.MaxTransparencyGroupDepth := ConfiguredDepth;
  var LoadOptions := TPdfLoadOptions.Default;
  LoadOptions.MaxFormXObjectDepth := ConfiguredDepth;

  AssertAllChains(Options, LoadOptions, [ConfiguredDepth, ConfiguredDepth, ConfiguredDepth, ConfiguredDepth, ConfiguredDepth]);
end;

procedure TRenderLimitTests.TestImagePixelLimitIsConfigurable;
begin
  var Options := TPdfRenderOptions.Default;
  Options.MaxImagePixels := 100;
  const Builder = TGraphicsDocuments.NewBuilder(TEncoding.ASCII.GetBytes('20 0 0 20 0 0 cm /Im1 Do'), '/XObject << /Im1 5 0 R >>');
  try
    var Pixels: TBytes;
    SetLength(Pixels, 20 * 20);
    Builder.AddStreamObject(5, '/Type /XObject /Subtype /Image /Width 20 /Height 20 /ColorSpace /DeviceGray /BitsPerComponent 8', Pixels);
    RenderBuilder(Builder, Options, TPdfLoadOptions.Default);
  finally
    Builder.Free;
  end;

  var Found := False;
  for var Call in FDevice.Calls do
  begin
    if Call.Kind = TRecordedCallKind.Bitmap then
    begin
      Found := True;
      Assert.IsTrue(Call.BitmapWidth * Call.BitmapHeight <= 100, Format('Bitmap of %d x %d', [Call.BitmapWidth, Call.BitmapHeight]));
    end;
  end;
  Assert.IsTrue(Found, 'the image is drawn');
  Assert.AreEqual<Integer>(1, CountLogLines('is subsampled'));
end;

procedure TRenderLimitTests.TestRenderPixelLimitIsConfigurable;
begin
  var Params := TPdfRenderParams.Create(1);
  Params.Options.MaxRenderPixels := 1000;
  const Builder = TGraphicsDocuments.NewBuilder(TEncoding.ASCII.GetBytes('0 0 10 10 re f'), '');
  try
    FDocument := FDocuments.Open(Builder);
  finally
    Builder.Free;
  end;
  FRenderer := TPdfRenderer.Create(FDocument, TRecordingBackend.Create);
  const SmallDevice: IPdfRasterDevice = TRecordingDevice.Create(40, 40);

  var IsRaised := False;
  try
    FRenderer.RenderPage(0, SmallDevice, Params);
  except
    on EPdfLimitExceededException do
    begin
      IsRaised := True;
    end;
  end;

  Assert.IsTrue(IsRaised, 'a device of 1600 pixels is over the limit of 1000');
end;

procedure TRenderLimitTests.TestTilingCellLimitIsConfigurable;
begin
  var Options := TPdfRenderOptions.Default;
  Options.MaxTilingCells := 10;
  const Builder = TilingPage('/Pattern cs /P1 scn 0 0 100 100 re f');
  try
    RenderBuilder(Builder, Options, TPdfLoadOptions.Default);
  finally
    Builder.Free;
  end;

  Assert.AreEqual<Integer>(0, FillCount, '100 cells are over the limit of 10');
  Assert.IsTrue(CountLogLines('cells') > 0);
end;

procedure TRenderLimitTests.TestTileEdgeLimitIsConfigurable;
begin
  var Options := TPdfRenderOptions.Default;
  Options.MaxTileEdge := 4;
  const Builder = TilingPage('/Pattern cs /P1 scn 0 0 100 100 re f');
  try
    RenderBuilder(Builder, Options, TPdfLoadOptions.Default);
  finally
    Builder.Free;
  end;

  Assert.AreEqual<Integer>(1, FDevice.LayerCount);
  Assert.IsTrue(FDevice.Layers[0].Width <= 4, 'the cell of 10 pixels is cut down to the edge limit');
  Assert.IsTrue(FDevice.Layers[0].Height <= 4);
end;

procedure TRenderLimitTests.TestAnnotationLimitIsConfigurable;
begin
  var Options := TPdfRenderOptions.Default;
  Options.MaxAnnotations := 3;
  const Builder = AnnotationPage(8);
  try
    RenderBuilder(Builder, Options, TPdfLoadOptions.Default);
  finally
    Builder.Free;
  end;

  Assert.AreEqual<Integer>(3, FillCount);
  Assert.AreEqual<Integer>(1, CountLogLines('only the first 3 are drawn'));
end;

procedure TRenderLimitTests.TestFormFanOutRespectsOperatorBudget;
begin
  var LoadOptions := TPdfLoadOptions.Default;
  LoadOptions.MaxOperatorsPerPage := 20000;
  const Builder = FanOutForms(20);
  const Watch = TStopwatch.StartNew;
  var IsStopped := False;
  try
    try
      RenderBuilder(Builder, TPdfRenderOptions.Default, LoadOptions);
    except
      on Failure: EPdfLimitExceededException do
      begin
        IsStopped := Failure.Message.Contains('operators');
      end;
    end;
  finally
    Builder.Free;
  end;

  Assert.IsTrue(Watch.ElapsedMilliseconds < TimeLimitMilliseconds, Format('Took %d ms', [Watch.ElapsedMilliseconds]));
  Assert.IsTrue(IsStopped or (CountLogLines('operators') > 0), 'the operator budget ends the page');
  Assert.IsTrue(FillCount <= 20001, 'no more drawing than the budget allows');
end;

procedure TRenderLimitTests.TestManyTransparencyGroupsBoundMemory;
begin
  const Meter = TLayerMeter.Create;
  try
    const Content = TStringBuilder.Create;
    for var Index := 1 to 1000 do
    begin
      Content.Append('/G1 Do ');
    end;
    const Builder = TGraphicsDocuments.NewBuilder(TEncoding.ASCII.GetBytes(Content.ToString), '/XObject << /G1 5 0 R >>');
    try
      Builder.AddStreamObject(5, '/Type /XObject /Subtype /Form /BBox [0 0 100 100] /Group << /S /Transparency /I true >>',
                              TEncoding.ASCII.GetBytes('0 0 1 rg 0 0 100 100 re f'));
      FDocument := FDocuments.Open(Builder);
    finally
      Builder.Free;
      Content.Free;
    end;
    FRenderer := TPdfRenderer.Create(FDocument, TMeteredBackend.Create(Meter));
    const DeviceReference: IPdfRasterDevice = TMeteredDevice.Create(TGraphicsDocuments.PageSize, TGraphicsDocuments.PageSize, Meter, False);
    const Watch = TStopwatch.StartNew;

    Assert.AreEqual(TPdfRenderStatus.Completed, FRenderer.RenderPage(0, DeviceReference, TPdfRenderParams.Create(1)));

    const PagePixels = Int64(TGraphicsDocuments.PageSize) * TGraphicsDocuments.PageSize;
    Assert.IsTrue(Meter.PeakPixels > 0, 'the groups are drawn on layers');
    Assert.IsTrue(Meter.PeakPixels <= 4 * PagePixels, Format('Peak of %d layer pixels for a page of %d', [Meter.PeakPixels, PagePixels]));
    Assert.IsTrue(Watch.ElapsedMilliseconds < TimeLimitMilliseconds, Format('Took %d ms', [Watch.ElapsedMilliseconds]));
  finally
    Meter.Free;
  end;
end;

// A small compressed mesh shading that many fills use: every fill builds the mesh again, so the work of the page has to be bounded as a whole
procedure TRenderLimitTests.TestMeshShadingWorkIsBoundedForTheWholePage;
begin
  const PaintedFills = 400;
  var Options := TPdfRenderOptions.Default;
  Options.MaxShadingWork := 1000000;
  const Builder = MeshShadingPage(PaintedFills);
  const Watch = TStopwatch.StartNew;
  try
    RenderBuilder(Builder, Options, TPdfLoadOptions.Default);
  finally
    Builder.Free;
  end;

  Assert.IsTrue(Watch.ElapsedMilliseconds < TimeLimitMilliseconds, Format('Took %d ms', [Watch.ElapsedMilliseconds]));
  Assert.IsTrue(FillCount > 0, 'the first fills are painted');
  Assert.IsTrue(FillCount < PaintedFills, Format('%d of %d fills are painted', [FillCount, PaintedFills]));
  Assert.AreEqual<Integer>(1, CountLogLines('mesh shadings of the page'), string.Join(' / ', FDocuments.LogLines.ToArray));
end;

procedure TRenderLimitTests.TestShadingWorkLimitIsConfigurable;
begin
  const PaintedFills = 50;
  const Builder = MeshShadingPage(PaintedFills);
  try
    RenderBuilder(Builder, TPdfRenderOptions.Default, TPdfLoadOptions.Default);
  finally
    Builder.Free;
  end;

  Assert.AreEqual<Integer>(PaintedFills, FillCount, 'the default budget does not touch an ordinary page');
  Assert.AreEqual<Integer>(0, CountLogLines('mesh shadings of the page'));
  Assert.IsTrue(DefaultMaxShadingWork > 0);
  Assert.AreEqual(DefaultMaxShadingWork, TPdfRenderOptions.Default.MaxShadingWork);
end;

end.
